"""Execute the shipped BASIC movement routines against deterministic geometry.

This deliberately small interpreter rejects unsupported executed statements.
VDP tile reads are replaced by a floor/ceiling fixture; gameplay branches, byte
arithmetic, jump data, landing rules and hitboxes come from HARDHAT.bas.
It does not emulate CPU timing, input hardware, or prove whole-level reachability.
"""
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor, as_completed
import copy
from itertools import repeat
import os
from pathlib import Path
import re

SOURCE = Path(__file__).resolve().parent.parent / 'src/HARDHAT.bas'


def ti_source_lines(source):
    """Select the TI994A preprocessor path before the BASIC interpreter runs."""
    active = True
    branches = []
    selected = []
    for raw in source.splitlines():
        directive = raw.split("'")[0].strip().lower()
        if directive.startswith('#if '):
            condition = directive[4:].strip()
            assert condition == 'ti994a', 'unsupported preprocessor condition: ' + condition
            branches.append((active, True, False))
            active = active
        elif directive == '#else':
            assert branches and not branches[-1][2], 'unmatched/duplicate #else'
            parent, condition, _ = branches[-1]
            branches[-1] = (parent, condition, True)
            active = parent and not condition
        elif directive == '#endif':
            assert branches, 'unmatched #endif'
            active = branches.pop()[0]
        elif active:
            selected.append(raw)
    assert not branches, 'unterminated preprocessor block'
    return selected


def reject_mutation(item):
    """Return only when this known-bad source is rejected by its owning check."""
    mutation_index, mutant, check = item
    try:
        check(mutant)
    except AssertionError:
        return mutation_index, check.__name__
    raise AssertionError('checker accepted historical defect: ' + check.__name__)


class Basic:
    # Immutable DATA is identical across VMs of the same source. Keep only the
    # most recent source so mutation tests cannot accumulate hundreds of carts.
    _byte_source = None
    _byte_cache = None
    # Most defect checks construct many fresh VMs for the same mutated source.
    # Their control-flow index is immutable too; parsing the full BASIC file for
    # every simulated VM used to dominate the cost of mutation testing.
    _parse_source = None
    _parse_cache = None

    def __init__(self, source, floor=168, holes=()):
        self.v = defaultdict(int)
        self.arc = []
        self.arrays = {}
        self.expr_cache = {}
        self.floor, self.holes = floor, holes
        self.screen = None
        self.data_pos = 0
        self.sound = []
        self.sound_times = []
        self.wait_count = 0
        self.sprites = {}
        self.sprite_writes = []
        self.prints = []
        self.cursor = 0
        self.pattern_writes = []
        self.color_writes = []
        self.vram = {}
        self.vram_writes = []
        self.rom_tables = {}
        self.bank = 1
        self.frame_inputs = repeat({})
        self.random_values = iter(())
        if Basic._parse_source != source:
            lines = [line.split("'")[0].strip().lower()
                     for line in ti_source_lines(source)]
            labels = {line[:-1]: i for i, line in enumerate(lines)
                      if re.fullmatch(r'\w+:', line)}
            label_banks = {}
            declared_bank = 0
            for line in lines:
                if re.fullmatch(r'bank [0-9]+',line):declared_bank=int(line.split()[1])
                if re.fullmatch(r'\w+:',line):label_banks[line[:-1]]=declared_bank
            ends, elses = {}, {}
            stack = []
            for i, line in enumerate(lines):
                if line.startswith('if ') and line.endswith(' then'):
                    stack.append((i, []))
                elif line == 'else' or line.startswith('elseif '):
                    stack[-1][1].append(i)
                elif line == 'end if':
                    start, branches = stack.pop()
                    ends[start] = i
                    for b in branches:
                        ends[b] = i
                    for j, b in enumerate(branches):
                        elses[b] = branches[j + 1] if j + 1 < len(branches) else i
                    elses[start] = branches[0] if branches else i
            assert not stack
            Basic._parse_source = source
            Basic._parse_cache = (lines, labels, label_banks, ends, elses)
        self.lines, self.labels, self.label_banks, self.ends, self.elses = Basic._parse_cache
        for line in self.lines:
            m = re.fullmatch(r'const (\w+)\s*=\s*(.+)', line)
            if m:
                self.v[m[1]] = self.expr(m[2])
        for line in self.lines:
            m = re.fullmatch(r'dim (\w+)\((.+)\)', line)
            if m:
                self.arrays[m[1]] = [0] * self.expr(m[2])
        j = self.labels['jump_data'] + 1
        data = next(x for x in self.lines[j:] if x.startswith('data byte'))
        self.arc = list(map(int, data[10:].split(',')))
        size = int(re.search(r'dim jtab\((\d+)\)', '\n'.join(self.lines))[1])
        assert len(self.arc) == size == 16
        if Basic._byte_source != source:
            values=[];offsets={}
            for line in self.lines:
                if line.endswith(':'):offsets[line[:-1]]=len(values)
                if line.startswith('data byte '):
                    for value in line[10:].split(','):
                        value=value.strip()
                        assert re.fullmatch(r'\$[0-9a-f]+|[0-9]+',value), ('unsupported DATA literal',value)
                        values.append(int(value[1:],16) if value.startswith('$') else int(value))
            Basic._byte_source=source
            Basic._byte_cache=(tuple(values),offsets)
        self.byte_data,self.data_offsets=Basic._byte_cache
        self.v.update(mx=40, my=152, st=self.v['s_walk'], ely=209, jhz=1)

    def tile(self, x, y):
        assert 0 <= x <= 255 and 0 <= y <= 191, (x, y)
        if self.screen is not None:
            return self.screen[(y // 8) * 32 + x // 8]
        if y // 8 == self.floor // 8 and x // 8 not in self.holes:
            return self.v['t_gird']
        if y // 8 == (self.floor - 32) // 8:
            return self.v['t_gird']
        return 32

    def rom_byte(self, label, offset):
        assert self.label_banks[label] == self.bank, ('wrong lookup bank', label, self.bank)
        if label not in self.rom_tables:
            values = []
            for line in self.lines[self.labels[label]+1:]:
                if line.endswith(':'): break
                if line.startswith('data byte '):
                    values.extend(self.expr(v) for v in line[10:].split(','))
            self.rom_tables[label] = values
        return self.rom_tables[label][offset]

    def upload(self, address, count, label, offset):
        assert self.label_banks[label] in (0, self.bank), ('wrong VRAM source bank', label)
        assert 0 <= address < address + count <= 16384
        self.vram_writes.append((address,count,label,offset))
        for i in range(count): self.vram[address+i] = (label,offset+i)

    def expect_upload(self, address, count, label, offset):
        assert all(self.vram.get(address+i)==(label,offset+i) for i in range(count)), ('wrong VRAM coverage',address,count,label,offset)

    def expr(self, text):
        functions = dict(tile=self.tile, jtab=self.arc.__getitem__,
                         vaddr=lambda row, col: 6144 + row * 32 + col,
                         cpos=lambda row, col: row * 32 + col,
                         random=lambda limit: next(self.random_values, 1) % limit)
        text = re.sub(r'peek\(varptr (lift_[xy])\(([^()]*)\)\)', r'rom_\1(\2)', text)
        functions.update({"rom_"+label: (lambda offset, label=label: self.rom_byte(label, offset))
                          for label in ('lift_x','lift_y')})
        functions.update({k: v.__getitem__ for k, v in self.arrays.items() if k != 'jtab'})
        key = text
        if key not in self.expr_cache:
            text = text.replace('cont1.button', 'input_button').replace('cont1.key', 'input_key')
            text = text.replace('cont2.button2', 'input_fctn')
            text = re.sub(r'\$([\da-f]+)', lambda m: str(int(m[1], 16)), text)
            text = text.replace('<>', '!=')
            text = re.sub(r'(?<![<>!=])=(?!=)', '==', text)
            text = re.sub(r'\band\b', '&', text).replace('/', '//')
            text = re.sub(r'#?[a-z_]\w*', lambda m: m[0] if m[0] in functions
                          else 'v[%r]' % m[0], text)
            self.expr_cache[key] = compile(text, '<BASIC expression>', 'eval')
        return eval(self.expr_cache[key], {'__builtins__': {}}, dict(v=self.v, **functions))

    def run(self, label):
        assert self.label_banks[label] in (0,self.bank), ('routine in wrong bank',label,self.bank,self.label_banks[label])
        pc, loops, steps = self.labels[label] + 1, [], 0
        while True:
            steps += 1
            assert steps < 10000, 'nonterminating ' + label
            line = self.lines[pc]
            if not line or line.endswith(':') or line == 'end if':
                pc += 1
                continue
            if line.startswith('if '):
                cond, statement = line[3:].split(' then', 1)
                if not self.expr(cond):
                    if statement:
                        pc += 1
                    else:
                        pc = self.elses[pc]
                        while self.lines[pc].startswith('elseif '):
                            if self.expr(self.lines[pc][7:-5]):
                                break
                            pc = self.elses[pc]
                        pc += 1
                    continue
                if not statement:
                    pc += 1
                    continue
                line = statement.strip()
            if line == 'else' or line.startswith('elseif '):
                pc = self.ends[pc] + 1
                continue
            if line == 'return':
                return
            if line.startswith('goto '):
                pc = self.labels[line[5:]] + 1
                continue
            if line.startswith('gosub '):
                self.run(line[6:])
            elif line == 'asm movb r0,@cvb_backreq':
                # Model the TI-only raw CRU FCTN+8/9 scanner. The assembly
                # opcode/column guards are also checked in title_hotkeys.
                self.v['backreq'] = int(bool(self.v['input_fctn'] and
                                             self.v['input_key'] in (8,9)))
            elif line.startswith('asm '):
                pass
            elif line == 'cls':
                self.screen = [32] * 768
                self.cursor = 0
            elif line.startswith('screen '):
                assert line=='screen title_map' and self.bank==3, 'unexpected screen source/bank'
                start=self.labels['title_map']+1
                data=[self.expr(v.strip()) for ln in self.lines[start:]
                      if ln.startswith('data byte ') for v in ln[10:].split(',')]
                self.screen=data[:768]
            elif line == 'wait':
                sample = next(self.frame_inputs, None)
                assert sample is not None, 'input trace exhausted: '+label
                self.v.update(sample)
                self.wait_count += 1
            elif line.startswith('restore '):
                self.data_pos = self.data_offsets[line[8:]]
            elif line.startswith('read byte '):
                value = self.byte_data[self.data_pos]
                self.data_pos += 1
                target = line[10:]
                indexed = re.fullmatch(r'(\w+)\((.+)\)', target)
                if indexed:
                    self.arrays[indexed[1]][self.expr(indexed[2])] = value
                else:
                    self.v[target] = value
            elif line.startswith('on '):
                value, labels = line[3:].split(' goto ')
                pc = self.labels[labels.split(',')[self.expr(value)]] + 1
                continue
            elif line.startswith('vpoke '):
                address, value = line[6:].split(',', 1)
                if self.screen is not None:
                    offset = self.expr(address) - 6144
                    assert 0 <= offset < 768, ('name table write', offset)
                    self.screen[offset] = self.expr(value)
            elif line.startswith('for '):
                m = re.fullmatch(r'for (\w+) = (.+) to (.+)', line)
                self.v[m[1]] = self.expr(m[2])
                loops.append((m[1], self.expr(m[3]), pc + 1))
            elif line.startswith('next '):
                var, end, start = loops[-1]
                assert var == line[5:]
                self.v[var] = (self.v[var] + 1) & 255
                if self.v[var] <= end:
                    pc = start
                    continue
                loops.pop()
            elif line.startswith('sound '):
                event=tuple(self.expr(x) if x else None for x in line[6:].split(','))
                self.sound.append(event)
                self.sound_times.append((self.wait_count,event))
            elif line.startswith('sprite '):
                args = tuple(self.expr(x) for x in line[7:].split(','))
                self.sprites[args[0]] = args[1:]
            elif line.startswith('define sprite '):
                first,count,pointer=line[14:].split(',')
                assert (pointer,self.bank) in (('dance_bitmap',2),('burn_bitmap',2),('brick_edge',3),('mack_jump_left',4)), 'unexpected sprite upload/bank'
                self.sprite_writes.append((self.expr(first),self.expr(count),pointer))
            elif line.startswith('define vram '):
                address,count,pointer=line[12:].split(',',2)
                m=re.fullmatch(r'varptr (\w+)\((.+)\)',pointer)
                label=m[1] if m else pointer; offset=self.expr(m[2]) if m else 0
                target=self.expr(address);size=self.expr(count)
                self.upload(target,size,label,offset)
                assert target%8==0 and size%8==0, 'unaligned tile upload'
                (self.color_writes if target>=8192 else self.pattern_writes).append((target%2048//8,size//8,label,offset))
            elif line.startswith(('define char ', 'define color ')):
                # Record hardware-only uploads, including the actual ROM offset.
                color=line.startswith('define color ')
                first, count, pointer = line[13 if color else 12:].split(',', 2)
                m = re.fullmatch(r'varptr (\w+)\((.+)\)', pointer)
                data_label=m[1] if m else pointer
                assert self.label_banks[data_label] in (0,self.bank), ('wrong art bank',data_label,self.bank,self.label_banks[data_label])
                if pointer.startswith(('varptr claw_pat','varptr press_','varptr tramp_',
                                       'varptr pad_anim','varptr pad_colors')):
                    assert self.bank==4, 'animation data read from wrong bank'
                if pointer in ('title_pat','title_col','fixture_pat','fixture_col','machine_art','machine_col') or pointer.startswith(('varptr beat_','varptr inflash_')):
                    assert self.bank==3, 'title art read from wrong bank'
                (self.color_writes if color else self.pattern_writes).append((self.expr(first),self.expr(count),
                    m[1] if m else pointer, self.expr(m[2]) if m else 0))
                for third in range(3):
                    self.upload((8192 if color else 0)+third*2048+self.expr(first)*8,
                                self.expr(count)*8,data_label,self.expr(m[2]) if m else 0)
            elif line.startswith('bank select '):
                self.bank=self.expr(line[12:])
            elif line.startswith(('#if ', '#endif')):
                pass
            elif line.startswith('print '):
                m=re.fullmatch(r'print at (cpos\([^)]*\)|#?\w+|\d+),(.+)',line)
                offset=self.expr(m[1]) if m else self.cursor
                body=m[2] if m else line[6:]
                values=[]
                for token in re.findall(r'"[^"]*"|[^,]+',body):
                    if token.startswith('"'):values.append(token[1:-1])
                    else:
                        number=re.fullmatch(r'(?:<(\.?)(\d+)>)?(.+)',token)
                        value=str(self.expr(number[3]));width=int(number[2] or 0)
                        values.append(value.rjust(width) if number[1]=='.' else value.zfill(width))
                rendered=''.join(values)
                self.cursor=offset+len(rendered)
                self.prints.append((offset,rendered))
                if self.screen is None:self.screen=[32]*768
                for i,c in enumerate(rendered):self.screen[offset+i]=ord(c)
            else:
                m = re.fullmatch(r'(#?\w+)(?:\((.+)\))? = (.+)', line)
                assert m, 'unsupported executed statement: ' + line
                value = self.expr(m[3]) & (65535 if m[1][0] == '#' else 255)
                if m[2]:
                    self.arrays[m[1]][self.expr(m[2])] = value
                else:
                    self.v[m[1]] = value
            pc += 1


def jump(source, direction=2, holes=()):
    vm = Basic(source, holes=holes)
    vm.v.update(jbe=1, jr=int(direction == 2), jl=int(direction == 0))
    vm.run('mack_step')
    assert vm.v['jbe'] == 0, 'jump press was not consumed'
    positions = []
    for _ in range(80):
        vm.run('mack_step')
        positions.append((vm.v['mx'], vm.v['my']))
        if vm.v['st'] in (vm.v['s_walk'], vm.v['s_dead']):
            break
    return vm, positions


def clear_windows(source):
    vm, path = jump(source)
    assert vm.v['st'] == vm.v['s_walk'] and vm.v['my'] == 152
    # Actual enemy collision routine and dimensions from the vandal caller.
    block = source.split('banked_actors_move:')[1].split("' Vandal: lethal")[1].split("' OSHA man:")[0]
    width, height = re.search(r'hbw = (\d+)\s+hbh = (\d+)\s+GOSUB hazard_hit', block).groups()
    counts = []
    for speed in (0, 0.5, 1):
        safe = 0
        for start in range(48, 105):
            collided = False
            for step, (x, y) in enumerate(path, 1):
                vm.v.update(mx=x, my=y, ex=int(start-speed*step), ey=152,
                            hbw=int(width), hbh=int(height))
                vm.run('mack_hit')
                collided |= bool(vm.v['hit'])
            if not collided and path[-1][0] > start - speed*len(path) + int(width):
                safe += 1
        assert safe == 0, 'ordinary jump clears enemy at speed %s: %s' % (speed, safe)
        counts.append(safe)
    # An enemy on the next floor must not become an invisible vertical wall.
    vm.v.update(mx=40,my=120,ex=40,ey=152,hbw=int(width),hbh=int(height))
    vm.run('mack_hit');assert not vm.v['hit'], 'enemy reaches across floors'
    return counts


def momentum(source):
    vm = Basic(source, floor=184)
    vm.v.update(st=vm.v['s_fall'], mx=100, my=145, fcy=145, jhz=2)
    vm.run('mack_step')
    assert vm.v['mx'] == 101, 'fall lost horizontal momentum'
    vm.v.update(my=170, fcy=130)
    vm.run('land_chk')
    assert vm.v['st'] == vm.v['s_dead'], 'fatal landing deferred and can be overwritten'
    vm.run('mack_step')
    assert vm.v['st'] == vm.v['s_dead'], 'catch-up step revived Mack'


def clock_contract(source):
    clean = '\n'.join(line.split("'")[0].strip().lower() for line in source.splitlines())
    world = clean.split('world_step:')[1].split('mack_step:')[0]
    routines = ['mack_step', 'actors_step', 'actors_move', 'bolt_move',
                'beam_move', 'mag_move', 'mag_catch', 'elev_move', 'site_step']
    assert sorted(re.findall(r'gosub (\w+)', world)) == sorted(routines)
    class Trace(Basic):
        def run(self,label):
            if label in routines:self.trace.append(label)
            super().run(label)
    for level,specific in ((1,['bolt_move','elev_move']),
                           (2,['beam_move','mag_move','mag_catch']),
                           (3,['beam_move'])):
        vm=Trace(source);vm.trace=[];vm.v['lv']=level;vm.run('init_level');vm.trace=[]
        vm.run('world_step')
        assert vm.trace==routines[:3]+specific+['site_step'], ('wrong site simulation dispatch',level,vm.trace)
    main = clean.split('main_loop:')[1].split('level_complete:')[0]
    assert re.search(r'for s8 = 1 to #hd\s+gosub world_step\s+next s8', main)
    for routine in routines:
        assert 'gosub ' + routine not in main, routine + ' also runs outside the common clock'


def inventory_contract(source):
    vm = Basic(source)
    vm.v.update(lv=3, carry=1, mx=56)
    vm.arrays['gapr'][0] = 21
    vm.arrays['gapc'][0] = 9
    vm.run('try_fill')
    assert vm.v['carry'] == 1, 'steel box consumed by stale level-1 gap'
    vm.v.update(lv=1)
    vm.run('try_fill')
    assert vm.v['carry'] == 0 and vm.arrays['gapst'][0] == 1, 'level-1 deposit broken'
    vm.v.update(i=5, xlife=0)
    vm.v['#score'] = 10000
    vm.run('hud_score')
    assert vm.v['i'] == 5, 'extra-life HUD clobbered pickup index'


def hammer_release(source):
    # Execute the shipped input block, then the real pickup collision. Testing
    # drop_hammer alone missed a release immediately undone by actors_move.
    block=source[source.index("\t' Button rising edge"):source.index('\tIF st = S_DEAD THEN\n\t\tGOSUB dead_tick')]
    script=source+'\nBANK 0\nbutton_test:\n'+block+'\tRETURN\n'
    for delta in (1,2,3,4):
        for near_spawn in (False,True):
            vm=Basic(script);vm.v['lv']=1;vm.run('init_level')
            vm.v.update(mx=vm.v['jhx0'] if near_spawn else 100,my=vm.v['jhy0'],
                        carry=2,jhtk=1,jb=1,von=0,oon=0,**{'#fd':delta})
            elapsed=0
            while elapsed<45:
                vm.run('button_test');vm.run('actors_move');elapsed+=delta
                assert vm.v['carry']==(2 if elapsed<45 else 0), ('hold-to-drop timing/recatch',delta,near_spawn,elapsed)
            assert vm.v['jhtk']==0 and (vm.v['jhx'],vm.v['jhy'])==(vm.v['jhx0'],vm.v['jhy0'])
            for _ in range(70):vm.run('button_test');vm.run('actors_move')
            assert vm.v['carry']==0, 'continued hold recatches released hammer'
            vm.v['jb']=0;vm.run('button_test');vm.run('actors_move')
            assert vm.v['carry']==0 and vm.v['jbhc']==0, 'release alone recatches hammer'
            # Separation re-arms normal pickup. A previously saturated button
            # must start a new hold period when catching the roaming hammer.
            vm.v['mx']=100;vm.run('actors_move')
            vm.v.update(mx=vm.v['jhx'],my=vm.v['jhy'],jb=1,jbhc=45)
            vm.run('actors_move')
            assert vm.v['carry']==2 and vm.v['jbhc']==0, 'pickup inherits saturated hold'
            elapsed=0
            while elapsed<45:vm.run('button_test');elapsed+=delta
            assert vm.v['carry']==0 and vm.bank==1, 'held-through-pickup hammer cannot be dropped'
    for carry in (0,1,2):
        vm=Basic(script);vm.v.update(carry=carry,jhtk=1,jb=1,**{'#fd':1})
        for _ in range(44):vm.run('button_test')
        assert vm.v['carry']==carry, 'short press drops inventory'
        vm.v['jb']=0;vm.run('button_test')
        assert vm.v['jbhc']==0
        vm.v['jb']=1;vm.run('button_test')
        assert vm.v['jbe']==1 and vm.v['carry']==carry, 'fresh jump press broken'


def single_item(source):
    # Both real pickup orders, including touching both objects in one world step.
    for first in ('block', 'hammer'):
        vm=Basic(source);vm.v['lv']=1;vm.run('init_level')
        index=next(i for i in range(vm.v['nitem']) if vm.arrays['itk'][i]==0)
        vm.v.update(mx=vm.arrays['itc'][index]*8-8,
                    my=vm.arrays['itr'][index]*8-8,von=0,oon=0,ch=vm.v['t_brick'])
        vm.v.update(jhx=vm.v['mx'],jhy=vm.v['my'])
        if first=='block':
            vm.run('take_item');vm.run('actors_move')
            assert vm.v['carry']==1 and vm.v['jhtk']==0, 'hammer replaces held block'
            assert vm.arrays['itst'][index]==1
        else:
            vm.run('actors_move');before=vm.v['#score'];vm.run('take_item')
            assert vm.v['carry']==2 and vm.v['jhtk']==1, 'block replaces held hammer'
            assert vm.arrays['itst'][index]==0 and vm.v['#score']==before, 'occupied hands consume block'
            assert vm.screen[vm.arrays['itr'][index]*32+vm.arrays['itc'][index]]==vm.v['t_brick']

    assert 'GOSUB inventory_draw' in source.split('main_loop:')[1].split('inventory_draw:')[0]
    vm=Basic(source);vm.v.update(lv=1,mx=96,my=152,jhtk=0)
    for facing in (0,1):
        vm.v['mdir']=facing
        # Reuse the same sprite table: transitions must clear the old layers.
        for carry in (1,0,2,1,2,0):
            vm.v.update(carry=carry,jhtk=int(carry==2),jhx=104,jhy=152)
            vm.run('inventory_draw')
            assert (vm.sprites[31][0]!=209)==(carry==1), 'stale block outline after changing inventory'
            if carry==1:
                assert vm.sprites[1][2:]==(28,6) and vm.sprites[3][0]==209, 'loose hammer looks carried with block'
            elif carry==2:
                assert vm.sprites[1][2] in (24,40) and vm.sprites[3][0]==209
            else:
                assert vm.sprites[1][0]==209 and vm.sprites[3][0]!=209
        vm.v.update(carry=1,jhtk=0)
        for dx,dy,hidden in ((-17,0,True),(17,0,True),(0,11,True),
                             (-18,0,False),(18,0,False),(0,12,False),(0,-32,False)):
            vm.v.update(jhx=96+dx,jhy=152+dy)
            before=(vm.v['jhx'],vm.v['jhy'],vm.v['carry'],vm.v['jhtk'])
            vm.run('inventory_draw')
            assert (vm.sprites[3][0]==209)==hidden, 'loose hammer occlusion boundary'
            assert before==(vm.v['jhx'],vm.v['jhy'],vm.v['carry'],vm.v['jhtk']), 'drawing changes item ownership or route'


def machinery(source):
    # Run the real level parser and use its name table and surface coordinates.
    for level in (1, 2, 3):
        vm = Basic(source)
        vm.v.update(lv=level)
        vm.run('init_level')
        assert vm.v['nitem'] == {1: 6, 2: 8, 3: 7}[level]
        if level == 1:
            for i in range(4):
                vm.v.update(mx=vm.arrays['itc'][i]*8-8,
                            my=vm.arrays['itr'][i]*8-8)
                vm.run('take_item')
                assert vm.v['carry']==1
                vm.v.update(mx=vm.arrays['gapc'][i]*8-16,
                            my=vm.arrays['gapr'][i]*8-16)
                vm.run('try_fill')
                assert vm.v['carry']==0 and vm.arrays['gapst'][i]==1
            vm.v.update(carry=2)
            for i in range(4):
                vm.v.update(mx=vm.arrays['gapc'][i]*8-8,
                            my=vm.arrays['gapr'][i]*8-16)
                vm.run('rivet_gap')
            assert vm.v['nriv']==4 and vm.v['lvdone']==1
        if level == 2:
            assert sum(c == vm.v['t_lboxl'] for c in vm.screen) == 6
            # Both inclined machines have the drawn 2:1 slope, including rollers.
            for belt in range(2):
                lo, hi = vm.arrays['cvx0'][belt], vm.arrays['cvx1'][belt]
                for x in range(lo, hi + 1):
                    vm.v.update(fx=x, kx0=lo, kx1=hi,
                                ky0=vm.arrays['cvy0'][belt], kdy=16)
                    vm.run('belt_surface')
                    rise = min(16, max(0, (x - lo - 3) // 2))
                    assert vm.v['srf'] == vm.arrays['cvy0'][belt] - rise
            # Every pail is removable and the last arms, rather than wins, the magnet.
            for i in range(6):
                vm.v.update(mx=vm.arrays['itc'][i]*8-8,
                            my=vm.arrays['itr'][i]*8-8)
                vm.run('take_item')
                assert vm.arrays['itst'][i] == 1
                address = vm.arrays['itr'][i]*32 + vm.arrays['itc'][i]
                assert vm.screen[address:address+2]==[32,32], 'half a pail left behind'
            assert vm.v['nlbr'] == 0 and vm.v['mgarm'] == 1
            assert vm.v['lvdone'] == 0
        if level == 3:
            assert all(vm.tile(x, y) not in (153, 154)
                       for x in (120, 128) for y in range(64, 144)), 'shaft is still a ladder'
            # Complete two revolutions with a rider. No teleport at a corner,
            # no vertical drift, and support comes from the actual paddle span.
            assert (vm.v['mx'], vm.v['my']) == (212, 56), 'factory spawn is not upper-right'
            vm.v.update(mx=104, my=48, bonbeam=1, pnside=0)
            previous = (vm.v['mx'], vm.v['my'])
            visited = set()
            for _ in range(448):
                vm.run('beam_move')
                now = (vm.v['mx'], vm.v['my'])
                assert sum(abs(a-b) for a,b in zip(now,previous)) == 1, 'lift teleported rider'
                vm.run('beam_sup')
                assert vm.v['bsup'] == 1 and vm.v['my'] + 16 == vm.v['bmy']
                visited.add((vm.arrays['pnxcar'][0], vm.arrays['pnycar'][0]))
                assert len(set(zip(vm.arrays['pnxcar'], vm.arrays['pnycar']))) == 4
                previous = now
            assert len(visited) == 224
            # Boxes survive pickup/delivery with no stale level-1 gaps involved.
            for i in range(6):
                vm.v.update(mx=vm.arrays['itc'][i]*8-8,
                            my=vm.arrays['itr'][i]*8-8)
                vm.run('take_item')
                assert vm.v['carry'] == 1
                vm.v.update(mx=112,my=168)
                vm.run('deliver_zone')
                assert vm.v['carry']==1, 'box delivered outside an IN machine'
                vm.v.update(mx=24 if i%2==0 else 208,my=120,st=vm.v['s_walk'])
                vm.run('deliver_zone')
                assert vm.v['carry']==0 and vm.v['boxfall']==1 and vm.v['nbox']==6-i
                for _ in range(66):
                    vm.run('factory_step')
                assert vm.v['nbox'] == 5-i
            assert vm.v['lvdone'] == 1


def transfers(source):
    # Controlled takeoff positions, then actual movement and moving surfaces.
    # These verify the transfers; they are not autonomous full play-throughs.
    for level in (2, 3):
        base = Basic(source); base.v.update(lv=level); base.run('init_level')
        for floor, phases in ((72, (28,28) if level==2 else (8,184)),
                              (104, (56,56) if level==2 else (40,152)),
                              (136, (88,88) if level==2 else (72,120))):
            for side, phase in enumerate(phases):
                vm = copy.deepcopy(base)
                if level == 3:
                    vm.v.update(pnphase=phase); vm.run('lift_positions')
                    x = vm.arrays['pnxcar'][0]
                    y = vm.arrays['pnycar'][0]
                    vm.v.update(mx=x-4 if side==0 else x+4, my=y-16, pnside=0)
                else:
                    vm.v.update(bmy=48+phase, bmd=0,
                                mx=100 if side==0 else 124, my=32+phase)
                vm.v.update(jbe=1, jl=1-side, jr=side, bonbeam=1)
                vm.run('mack_step')
                for _ in range(65):
                    vm.run('mack_step'); vm.run('beam_move')
                    if vm.v['st'] in (vm.v['s_walk'], vm.v['s_dead']): break
                landing = 74 if (level, floor, side)==(3,72,0) else floor
                assert vm.v['st']==vm.v['s_walk'] and vm.v['my']+16==landing, (
                    'platform transfer failed', level, floor, side, vm.v['my'],vm.v['st'])
                assert vm.v['bonbeam']==0
        if level == 3:
            for side in (0, 1):
                vm = copy.deepcopy(base)
                vm.v.update(mx=80 if side==0 else 152, my=160,
                            jr=1-side, jl=side, mdir=1-side, padok=1)
                vm.run('spring_begin')
                # A normal floor approach crosses safely to the opposite pad.
                for _ in range(52):
                    if vm.v['st']==vm.v['s_dead']: break
                    vm.run('mack_step')
                assert vm.v['springhit']==0 and vm.v['st']!=vm.v['s_dead'], (
                    'ordinary two-pad transfer hits the cabinet',side,dict(vm.v))



def fidelity(source):
    death=source.split('mack_die:\n',1)[1].split('\ndeath_cleanup:',1)[0]
    assert 'BANK SELECT' not in death and 'banked_' not in death, (
        'mack_die must preserve the active cartridge bank while banked collisions unwind')
    def level(n):
        vm=Basic(source); vm.v.update(lv=n, lives=2, levelno=n, **{'#score':1000}); vm.run('init_level')
        return vm
    for stage in (1,2,3):
        vm=level(stage)
        assert vm.screen[1:7]==list(map(ord,'  5000')), ('score missing on first level frame',stage)
        assert vm.screen[27:29]==[vm.v['t_hat']]*2, ('top-row reserve hats missing after level paint',stage)
        assert vm.screen[16:20]==list(map(ord,'5000')), ('bonus missing on first level frame',stage)
    # Carrying a loose block through an elevator ride and dying must restore
    # the item, clear inventory, and permit it to be picked up again.
    vm=level(1);item=0
    row,col=vm.arrays['itr'][item],vm.arrays['itc'][item]
    vm.v.update(mx=col*8-8,my=row*8-8,ch=vm.v['t_brick'])
    vm.run('take_item')
    assert vm.v['carry']==1 and vm.arrays['itst'][item]==1, 'test block pickup setup failed'
    vm.v.update(ely=vm.v['elby'],elpaint=0)
    vm.v.update(jhx=88,jhy=56,jhway=7)
    vm.run('mack_die');vm.v['#fd']=1;vm.run('dead_tick')
    assert vm.v['carry']==1 and vm.arrays['itst'][item]==1 and vm.v['dclean']==1, (
        'death restored held block before the blink finished')
    assert (vm.v['jhx'],vm.v['jhy'],vm.v['jhway'])==(88,56,7), (
        'death reset the roaming hammer before the blink finished')
    vm.v['#fd']=40;vm.run('dead_tick')
    assert vm.v['carry']==0 and vm.arrays['itst'][item]==0, 'death left stale block inventory or failed to restore item'
    assert (vm.v['jhx'],vm.v['jhy'],vm.v['jhway'])==(vm.v['jhx0'],vm.v['jhy0'],0), (
        'death did not restore the roaming hammer at respawn')
    vm.v.update(mx=col*8-8,my=row*8-8,ch=vm.v['t_brick'])
    vm.run('take_item')
    assert vm.v['carry']==1 and vm.arrays['itst'][item]==1, 'restored block cannot be picked up again'
    # The last life still cleans up at the end of the blink, before Game Over.
    vm=level(1);vm.v.update(carry=2,jhtk=1,jhx=120,jhy=80,jhway=9,lives=0)
    vm.run('mack_die');vm.v['#fd']=1;vm.run('dead_tick')
    assert vm.v['carry']==2 and vm.v['jhtk']==1 and vm.v['gameov']==0, (
        'last-life inventory or Game Over changed before the blink finished')
    vm.v['#fd']=40;vm.run('dead_tick')
    assert vm.v['carry']==0 and vm.v['jhtk']==0, 'last-life death retained held hammer'
    assert (vm.v['jhx'],vm.v['jhy'],vm.v['jhway'])==(vm.v['jhx0'],vm.v['jhy0'],0), (
        'last-life death left hammer off its route origin')
    vm=level(1);vm.v['lives']=0;item=0
    row,col=vm.arrays['itr'][item],vm.arrays['itc'][item]
    vm.v.update(mx=col*8-8,my=row*8-8,ch=vm.v['t_brick'])
    vm.run('take_item');vm.run('mack_die');vm.v['#fd']=1;vm.run('dead_tick')
    assert vm.v['carry']==1 and vm.arrays['itst'][item]==1
    vm.v['#fd']=40;vm.run('dead_tick')
    assert vm.v['carry']==0 and vm.arrays['itst'][item]==1, 'last-life death must clear carried state without restoring a pickup on Game Over'
    assert vm.screen[row*32+col]==vm.v['t_void'], 'last-life death restored a stray block into the Game Over scene'
    vm=level(1);vm.v.update(lives=2,**{'#fd':1})
    for remaining in (1,0):
        vm.run('mack_die')
        for _ in range(40):vm.run('dead_tick')
        assert vm.v['lives']==remaining and vm.v['st']==vm.v['s_walk'], (
            'a non-final death must consume one reserve and respawn',remaining)
    vm.run('mack_die')
    for _ in range(40):vm.run('dead_tick')
    assert vm.v['lives']==0 and vm.v['gameov']==1, 'third death must enter Game Over with no reserves'
    # Deposited but unfastened girders return to their own pickup slots.
    vm=level(1)
    for i in (0,1):
        vm.v.update(mx=vm.arrays['itc'][i]*8-8,my=vm.arrays['itr'][i]*8-8)
        vm.run('take_item')
        vm.v.update(mx=vm.arrays['gapc'][i]*8-16,my=vm.arrays['gapr'][i]*8-16)
        vm.run('try_fill')
    vm.v.update(carry=2,mx=vm.arrays['gapc'][0]*8-8,my=152)
    vm.run('rivet_gap')
    vm.v.update(dtm=0); vm.v['#fd']=4; vm.run('dead_tick')
    assert vm.arrays['gapst'][:2]==[2,0] and vm.arrays['itst'][:2]==[1,0]
    vm.v.update(st=vm.v['s_jump'],mx=44,my=13,ely=152,elty=56)
    score=vm.v['#score']; vm.run('bell_step'); vm.run('bell_step')
    assert vm.v['#score']==score+2 and vm.v['emov']==1 and vm.v['eld']==0
    # Drive the actual drill route through every beam; never jump diagonally.
    route=source.split('drill_route:')[1].split('steel_bitmap:')[0]
    coords=[int(x) for line in route.splitlines() if 'DATA BYTE' in line
            for x in line.split('DATA BYTE')[1].split(',')]
    vm.arrays['drillx'][:]=coords[::2]; vm.arrays['drilly'][:]=coords[1::2]
    vm.v.update(jhx=32,jhy=152,jhway=0)
    visited=set()
    for _ in range(2300):
        old=(vm.v['jhx'],vm.v['jhy']); vm.run('route_drill')
        now=(vm.v['jhx'],vm.v['jhy'])
        assert sum(abs(a-b) for a,b in zip(old,now))<=1
        visited.add(now)
    assert set(zip(coords[::2],coords[1::2])) <= visited
    # Magnet waits for all six pails before moving or catching,
    # and carries Mack to the top platform before finishing.
    vm=level(2); old=vm.v['mgx']
    for _ in range(8): vm.run('mag_move')
    assert vm.v['mgx']==old
    vm.v['mgarm']=1
    for _ in range(8): vm.run('mag_move')
    assert vm.v['mgx']!=old
    vm.v['mgarm']=0
    vm.v.update(st=vm.v['s_jump'],mx=vm.v['mgx'],my=20)
    vm.run('mag_catch'); assert vm.v['st']!=8
    vm.v.update(mgarm=1,mgx=196,mx=196)
    vm.run('mag_catch'); assert vm.v['st']==8 and vm.v['lvdone']==0
    for _ in range(84): vm.run('mag_move')
    assert vm.v['st']==9 and vm.v['lvdone']==0 and vm.v['mx']==120 and vm.v['my']==24
    for _ in range(44): vm.run('mag_move')
    assert vm.v['mgx']==156 and vm.v['lvdone']==0 and vm.v['mx']==120
    vm.run('mag_move')
    assert vm.v['mgx']==157 and vm.v['lvdone']==1 and vm.v['mx']==120
    # The two valve cells must remain distinct from the Level-1 thrower upload.
    spigot=re.search(r'DEFINE CHAR (\d+),(\d+),spigot_pat',source)
    thrower=re.search(r'DEFINE CHAR (\d+),(\d+),thrower_pat',source)
    assert spigot and thrower
    valve_codes=set(range(int(spigot[1]),int(spigot[1])+int(spigot[2])))
    thrower_codes=set(range(int(thrower[1]),int(thrower[1])+int(thrower[2])))
    assert not valve_codes & thrower_codes, 'rivet thrower replaces part of the lower valve'
    assert vm.screen[18*32+2:18*32+7]==[225]*4+[226], 'lower-conveyor valve is missing or overwritten'
    # Moving hazards must have both safe and lethal windows.
    for n,x,y,safe,bad in ((2,184,120,20,24),(2,184,120,90,44),
                          (3,56,58,20,36)):
        for phase,dead in ((safe,False),(bad,True)):
            vm=level(n);vm.v.update(mx=x,my=y,hzphase=phase-1)
            vm.run('site_step')
            assert (vm.v['st']==vm.v['s_dead'])==dead, ('hazard window',n,x,phase)
    for n,x,y in ((2,224,24),(2,80,164),(3,120,148),(3,40,162)):
        vm=level(n);vm.v.update(mx=x,my=y,hzphase=90)
        vm.run('site_step');assert vm.v['st']==vm.v['s_dead'], ('scenery still harmless',n,x)
    for x in (84,156):
        vm=level(3);vm.v.update(mx=x,my=159,st=vm.v['s_fall'],fct=3,fcy=145)
        vm.run('mack_step');vm.run('site_step')
        assert vm.v['st']==7, 'spring approach killed before it could bounce'
    # Four paddles, left down/right up; every tier is visited by both enemies.
    vm=level(3);vm.v.update(pnphase=0);vm.run('lift_positions')
    before=list(vm.arrays['pnycar']);vm.run('lift_move')
    assert vm.arrays['pnycar'][0]==before[0]+1
    assert vm.arrays['pnycar'][2]==before[2]-1
    for n,x,y in ((2,176,168),(3,168,88),(3,16,88)):
        vm=level(n);vm.v.update(rx=x,ry=y,rf=1,rp=0,atg=1)
        seen=set()
        for _ in range(600):
            vm.run('site_route');seen.add(vm.v['ry'])
        assert ({120,168} if n==2 else {88,120}) <= seen


def review_feedback(source):
    # Reproduce the reported upper-left conveyor soft-lock, carrying a box.
    # The belt stands two pixels below a normal girder, so only the head can
    # reach the short chain initially. Continue up all the way to the roof.
    vm=Basic(source);vm.v.update(lv=3);vm.run('init_level')
    vm.v.update(mx=28,my=58,carry=1,ju=1)
    vm.run('mack_step')
    assert vm.v['st']==vm.v['s_climb'] and vm.v['my']==57
    for _ in range(40):
        vm.run('mack_step')
        if vm.v['st']==vm.v['s_walk']:break
    assert vm.v['st']==vm.v['s_walk'] and vm.v['my']==24, 'short-chain climb stuck'
    # Walk-offs are vertical even if a direction remains held. A deliberate
    # jump still keeps its own committed momentum (covered by momentum()).
    for n in (1,2,3):
        for direction in (0,2):
            vm=Basic(source,holes=tuple(range(32)))
            vm.v.update(lv=n,jl=int(direction==0),jr=int(direction==2),jhz=direction)
            vm.run('st_walk'); x=vm.v['mx']
            assert vm.v['st']==vm.v['s_fall'] and vm.v['jhz']==1
            for _ in range(5): vm.run('mack_step')
            assert vm.v['mx']==x, ('walk-off drift',n,direction)
    # Parked cabin is backed by characters and erases at its OLD position.
    vm=Basic(source); vm.v.update(lv=1);vm.run('init_level')
    original=vm.screen[:];vm.run('elev_back');parked=vm.screen[:]
    origin=(vm.v['ely']//8-2)*32+vm.v['elx']//8
    cells=[origin,origin+1,origin+32,origin+33,origin+64,origin+65]
    assert [parked[x] for x in cells]==[227,229,228,230,236,237]
    vm.run('elev_back');assert vm.screen==parked
    vm.v.update(emov=1,ely=vm.v['ely']-1);vm.run('elev_back')
    assert vm.screen==original, 'moving elevator left cabin characters behind'
    vm.v.update(emov=0,ely=vm.v['elty']);vm.run('elev_back')
    assert vm.v['elpaint']==1 and vm.screen!=original
    assert 'DEFINE CHAR 227,4,cage_bitmap' in source, 'cabin art diverged from sprite'
    vm.v.update(ely=168,emov=0,elpaint=0,mx=20,my=152,st=vm.v['s_walk'],jl=1,elarm=1)
    vm.run('elev_back')
    for _ in range(20):
        vm.run('mack_step')
        if vm.v['emov']:break
    assert vm.v['emov']==1 and vm.v['st']==vm.v['s_ride'], 'background floor prevents boarding'

    # Start from the actual level-2 spawn, walk, jump onto the conveyor and
    # jump from its last roller onto the crane. All actors/hazards are live.
    wins=0
    for phase in range(0,128,16):
        vm=Basic(source);vm.v.update(lv=2);vm.run('init_level')
        vm.v.update(hzphase=phase,**{'#slagclock':phase*2},jr=1)
        initial_beam=vm.v['bmy'];vm.run('beam_move')
        assert vm.v['bmy']==initial_beam, 'crane leaves before first boarding'
        for _ in range(100):
            if vm.v['st']==vm.v['s_walk']:
                vm.v['jbe']=int(vm.v['mx'] in (28,70,71,72))
            vm.run('world_step')
            if vm.v['st']==vm.v['s_dead']:break
            if vm.v['bonbeam']:
                assert vm.v['bmactive']==1
                wins+=1;break
    assert wins>=6, ('insufficient conveyor entry windows',wins,8)
    # The inverse direction matters too: all six factory side tiers must
    # have a real launch window onto the rotating paddles, with hazards live.
    # Where a boarded rider then goes is pinned too: the right lane climbs
    # to the top; the left lane carries a rider who stays aboard down into
    # the bottom gear's sparks (he has to jump off -- no wrap under the lift).
    for side in (0,1):
        for floor in (72,104,136):
            captures=0
            for phase in range(0,224,16):
                vm=Basic(source);vm.v.update(lv=3);vm.run('init_level')
                vm.v.update(pnphase=phase);vm.run('lift_positions')
                vm.v.update(mx=80 if side==0 else 174,my=floor-16,
                            jbe=1,jr=1-side,jl=side)
                for _ in range(60):
                    vm.run('mack_step');vm.run('beam_move');vm.run('site_step')
                    if vm.v['st']==vm.v['s_dead']:break
                    if vm.v['bonbeam']:
                        captures+=1;break
                if not vm.v['bonbeam']:continue
                vm.v.update(jbe=0,jl=0,jr=0)
                for _ in range(200):
                    if side==1 and vm.arrays['pnycar'][vm.v['pnside']]==64:break
                    vm.run('mack_step');vm.run('beam_move');vm.run('site_step')
                    if vm.v['st']==vm.v['s_dead']:break
                if side:
                    assert vm.v['st']!=vm.v['s_dead'], ('right-lane rider dies on the climb',floor,phase)
                else:
                    assert vm.v['st']==vm.v['s_dead'] and gear_spark_touch(vm), (
                        'left-lane rider escapes the gear sparks',floor,phase)
            assert captures>=2, ('no usable factory lift entry',side,floor,captures)
    return wins


def gear_spark_touch(vm):
    # Mack's 12x12 art (mx+2..13, my+4..15) against the live spark cells
    # (codes 108-111) on the playfield rows of this VM's name table.
    cells={(c*8+x,r*8+y) for r in range(1,24) for c in range(32)
           if 108<=vm.screen[r*32+c]<=111 for x in range(8) for y in range(8)}
    mx,my=vm.v['mx'],vm.v['my']
    return any((x,y) in cells for x in range(mx+2,mx+14) for y in range(my+4,my+16))


def upper_conveyor(source):
    base=Basic(source);base.v['lv']=2;base.run('init_level')
    assert (base.arrays['cvx0'][0],base.arrays['cvx1'][0])==(176,215), 'upper conveyor not one character right'
    assert (base.arrays['cvx0'][1],base.arrays['cvx1'][1])==(40,79), 'lower conveyor moved'
    assert base.screen[8*32+22]==159 and base.screen[6*32+26]==159, 'roller art and surface disagree'
    assert base.screen[7*32+26]==base.screen[8*32+26]==160, 'support did not move with conveyor'
    for phase in (0,1,16,30,32,63):
        for walking in (0,1):
            vm=copy.deepcopy(base);vm.v.update(mx=204,my=34,jr=walking,hzphase=phase)
            for _ in range(16):
                vm.run('world_step')
                if vm.v['st']==vm.v['s_dead']:break
            assert vm.v['st']==vm.v['s_dead'] and vm.v['my']==34 and vm.v['burnfall']==1, (
                'belt exit did not ignite Mack',phase,walking)
    # Every plume phase, including fully retracted, must use the burning fall.
    for phase in range(64):
        vm=copy.deepcopy(base);vm.v.update(mx=208,my=34,hzphase=phase,st=vm.v['s_walk'])
        vm.run('upper_belt_edge')
        assert vm.v['st']==vm.v['s_dead'] and vm.v['burnfall']==1 and vm.v['dtm']==12, (
            'upper belt exit used ordinary death while plume was retracted',phase)
    # A deliberate jump from the last roller can still catch the live magnet.
    for x,direction in ((198,2),(206,1)):
        vm=copy.deepcopy(base);vm.v.update(mx=x,my=34,jbe=1,jr=int(direction==2),mgarm=1,mgx=208,mgd=0)
        for _ in range(32):
            vm.run('world_step')
            if vm.v['st'] in (8,vm.v['s_dead']):break
        assert vm.v['st']==8, 'new edge blocks the magnet jump'
    # The rule is confined to this high exit, not lower tiers or other sites.
    for level,y in ((1,24),(2,56),(2,120),(3,24)):
        vm=Basic(source);vm.v['lv']=level;vm.run('init_level')
        vm.v.update(mx=208,my=y);vm.run('upper_belt_edge')
        assert vm.v['st']!=vm.v['s_dead'], 'edge rule leaks onto another floor/site'


def title_scores(source):
    for units in (0,1,2,5,7,40,13108,65535):
        title=Basic(source)
        title.v.update(last838=1,**{'#lastscore':units,'#hi':units})
        title.frame_inputs=iter([{},dict(input_button=0,input_key=15),dict(input_button=1)]+[{}]*60)
        title.run('title_screen')
        text=str(units*5)+'*'
        assert ''.join(map(chr,title.screen[34:34+len(text)]))==text, 'last score must start at its label with adjoining marker'
        assert ''.join(map(chr,title.screen[56:62]))==str(units*5).rjust(6), 'high score alignment changed'
    over=source[source.index('game_over:\n'):source.index("\t' 75 video frames")]
    start=source[source.index('new_game:\n'):source.index('main_loop:\n')]
    clearpos=start.find('\tCLS\n');charpos=start.find('\tGOSUB game_chars')
    assert clearpos >= 0 and charpos >= 0 and clearpos < charpos, (
        'title/838 screen must clear before gameplay reassigns character patterns')
    vm=Basic(source+'\nBANK 0\nscore_end_test:\n'+over+'\tRETURN\nscore_start_test:\n'+start+'\tRETURN\n')
    vm.v.update(lv=1,**{'#score':1234,'#hi':900});vm.run('init_level')
    vm.run('score_end_test')
    vm.frame_inputs=iter([{},dict(input_button=0,input_key=15),dict(input_button=1)]+[{}]*60)
    vm.run('score_start_test')
    assert vm.v['#score']==0 and vm.v['#lastscore']==1234 and vm.v['#hi']==1234, 'last/high score lost on restart'
    assert (34,'6170') in vm.prints and (56,'  6170') in vm.prints, 'title score values/positions wrong'
    assert (0*32+2,'last score') in vm.prints and (20,'high score') in vm.prints
    assert (18*32+5,'2026 unhuman and c&c ai') in vm.prints, 'title credit missing'
    assert (23*32+7,'press fire to start') in vm.prints, 'start prompt misplaced'
    title_index=next(i for i,p in enumerate(vm.pattern_writes) if p[2]=='title_pat')
    assert any(p[2]=='tile_pat' for p in vm.pattern_writes[title_index+1:]), 'title art leaks into gameplay'
    assert vm.bank==1 and vm.v['lv']==1 and vm.v['lives']==2, 'normal start changed'
    vm.v.update(**{'#score':600,'#hi':1234});vm.run('score_end_test')
    assert vm.v['#lastscore']==600 and vm.v['#hi']==1234, 'lower last score overwrites high score'
    # Provenance belongs to each saved score, not to the current menu choice.
    for assisted,score,last_star,high_star in ((1,2000,1,1),(0,700,0,1),(0,2000,0,1),(0,2500,0,0),(1,800,1,0)):
        vm.v.update(game838=assisted,**{'#score':score})
        vm.run('score_end_test')
        assert vm.v['last838']==last_star and vm.v['hi838']==high_star, '838 score provenance lost'
        vm.prints.clear()
        vm.frame_inputs=iter([{},dict(input_button=0,input_key=15),dict(input_button=1)]+[{}]*60)
        vm.run('score_start_test')
        assert ((34+len(str(score*5)),'*') in vm.prints)==bool(last_star), 'last score asterisk wrong'
        assert ((62,'*') in vm.prints)==bool(high_star), 'high score asterisk wrong'
        assert vm.v['game838']==0, '838 status leaks into normal next game'
    vm.v.update(game838=1,hi838=1);vm.prints.clear();vm.run('hud_all')
    assert (7,'*') in vm.prints and (24,'*') not in vm.prints, 'current-score HUD marker wrong'
    # Level completion can claim the record before game over.
    award=source[source.index('level_complete:\n'):source.index('\tlevelno = levelno + 1')]
    win=Basic(source+'\nBANK 0\naward_test:\n'+award+'\tRETURN\n')
    for assisted in (1,0):
        win.v.update(lv=1,game838=assisted,**{'#score':1000,'#bonus':5000,'#hi':900})
        # Fifty four-frame ticks, followed by the level-one fanfare.
        win.frame_inputs=iter([{}]*400)
        win.run('award_test')
        assert win.v['#hi']==2000 and win.v['hi838']==assisted, 'completion score provenance wrong'


def score_range(source):
    vm=Basic(source)
    # Both final digits (0/5), old overflow boundary, and full six-digit range.
    for units in (0,1,2,5,7,40,1399,1400,13107,13108,65535):
        vm.v.update(game838=0,**{'#scvalue':units,'#scpos':100})
        vm.run('score_print')
        assert ''.join(map(chr,vm.screen[1:8]))==str(units*5).rjust(6)+' ', 'HUD score formatting/range wrong'
        assert vm.screen[0]==32, 'HUD score lost its left margin'
        assert vm.bank==1, 'score renderer did not restore level-data bank'
        vm.bank=3;vm.v['#scpos']=100;vm.run('banked_score_left')
        assert ''.join(map(chr,vm.screen[100:107]))==str(units*5).ljust(7), 'title last-score alignment changed'
        vm.v['#scpos']=100;vm.run('banked_score_print')
        assert ''.join(map(chr,vm.screen[100:106]))==str(units*5).rjust(6), 'high score formatting changed'
        vm.bank=1
    vm.v.update(**{'#score':65534,'#award':7});vm.run('add_score')
    assert vm.v['#score']==65535, 'score overflow wraps'
    vm.v.update(xlife=0,lives=2,**{'#score':1399});vm.run('hud_score')
    assert vm.v['lives']==2, 'extra life awarded too early'
    vm.v['#score']=1400;vm.run('hud_score');vm.run('hud_score')
    assert vm.v['lives']==3, 'extra life threshold changed or repeats'
    vm.v.update(lv=1,levelno=1);vm.run('init_level')
    vm.v.update(game838=1,hi838=1,**{'#score':65535,'#hi':65535,'#bonus':5000});vm.run('hud_all')
    assert ''.join(map(chr,vm.screen[1:8]))=='327675*', 'HUD score overlaps marker'
    assert vm.screen[8:10]==[32]*2 and vm.screen[20]==32 and vm.screen[21:29]==[32]*5+[vm.v['t_hat']]*3, (
        'top-row hats overlap the score or bonus')
    assert ''.join(map(chr,vm.screen[10:20]))=='bonus 5000', 'bonus did not move left as a unit'
    for level in (1,9,10,99,100,255,1):
        vm.v['levelno']=level;vm.run('hud_all')
        label=('l'+str(level) if level<100 else str(level)).rjust(3)
        assert ''.join(map(chr,vm.screen[29:32]))==label, (
            'level not right-aligned or stale digits remain',level)
    vm.v.update(game838=0,hi838=0,**{'#score':1,'#hi':2,'#bonus':0});vm.run('hud_all')
    assert ''.join(map(chr,vm.screen[1:8]))=='     5 ', 'old score digits/marker remain'
    assert ''.join(map(chr,vm.screen[16:20]))=='   0', 'zero bonus missing or padded'


def mack_animation(source):
    draw=source[source.index('\tIF mdir = 1 THEN\n\t\tmfr'):source.index("\tGOSUB elev_draw\n\t' Crane")]
    patterns={}
    for start,count,label in re.findall(r'DEFINE SPRITE (\d+),(\d+),(\w+)',source):
        body=source[source.index(label+':\n')+len(label)+2:]
        body=re.split(r'^\w+:',body,maxsplit=1,flags=re.M)[0]
        rows=re.findall(r'BITMAP "([.X]+)"',body)
        assert len(rows)>=int(count)*16, ('short sprite upload',label)
        for i in range(int(count)):
            code=(int(start)+i)*4
            assert code not in patterns, ('sprite patterns overlap',code,label)
            patterns[code]=rows[i*16:(i+1)*16]
    vm=Basic(source+'\nBANK 0\nrun_draw_test:\n'+draw+'\tRETURN\n')
    for direction in (0,1):
        expected=[48,48,52,52,48,48,132,132] if not direction else [0,0,44,44,0,0,124,124]
        colors={0:60,44:64,48:68,52:72,124:128,132:136}
        for phase,code in enumerate(expected):
            for frame in (0,255):
                vm.v.update(st=vm.v['s_walk'],mdir=direction,jr=direction,jl=1-direction,
                            steptick=phase,frame=frame)
                vm.run('run_draw_test')
                white,purple=vm.sprites[0][2],vm.sprites[8][2]
                assert white==code and purple==colors[code], 'run layers/cadence do not follow walked distance'
                assert white in patterns and purple in patterns, 'run pose not uploaded'
                assert all(not(a==b=='X') for ra,rb in zip(patterns[white],patterns[purple])
                           for a,b in zip(ra,rb)), 'Mack color layers overlap'
            vm.v.update(jr=0,jl=0)
            vm.run('run_draw_test')
            assert vm.sprites[0][2]==(0 if direction else 48), 'idle Mack holds a running stride'
        for state in ('s_jump','s_fall','s_tramp'):
            vm.v.update(st=vm.v[state],jr=1,jl=0,steptick=7)
            vm.run('run_draw_test')
            assert vm.sprites[0][2]==(32 if direction else 140) and vm.sprites[8][2]==(76 if direction else 144), 'airborne pose ignores facing'
    for right,left in ((0,48),(44,52),(124,132),(32,140),(76,144)):
        assert patterns[left]==[row[::-1] for row in patterns[right]], 'directional sprite is not mirrored'
    for right,left in ((60,68),(64,72),(128,136)):
        assert patterns[left]==[row[::-1] for row in patterns[right]], 'hair/clothes face the wrong way'
    for direction in (0,1):
        vm.v.update(st=vm.v['s_walk'],mdir=1-direction,jl=1-direction,jr=direction)
        vm.run('start_jump')
        assert vm.v['mdir']==direction, 'jump retains old facing'
    vm.run('mack_air_chars');assert vm.bank==1, 'airborne art loader leaves wrong bank'


def elevator_dance(source):
    draw=source[source.index('\tIF mdir = 1 THEN\n\t\tmfr'):source.index("\tGOSUB elev_draw\n\t' Crane")]
    art=source[source.index('dance_bitmap:\n'):source.index('banked_completion_music:\n')]
    rows=re.findall(r'BITMAP "([.X]+)"',art)
    assert len(rows)==64 and all(len(row)==16 for row in rows), 'dance sprite pairs malformed'
    assert rows[15].count('X') and rows[47].count('X'), 'dance feet lift off cabin floor'
    assert rows[:16]!=rows[32:48], 'dance crouches identical'
    for down in (0,1):
        for delta in (1,2,4):
            vm=Basic(source+'\nBANK 0\ndance_draw_test:\n'+draw+'\tRETURN\n')
            vm.v['lv']=1;vm.run('init_level')
            end=vm.v['elby'] if down else vm.v['elty']
            vm.v.update(ely=end-1 if down else end+1,eld=down,emov=1,elarm=0,
                        st=vm.v['s_ride'],mx=vm.v['elx'],jbe=1,jr=1)
            vm.run('elev_move')
            assert vm.v['edance']==32 and vm.v['emov']==0, 'arrival does not start dance'
            start=(vm.v['mx'],vm.v['my']);vm.sound=[];poses=set()
            for frame in range(0,32,delta):
                vm.run('st_ride');vm.run('elev_move')
                assert (vm.v['mx'],vm.v['my'])==start and vm.v['st']==vm.v['s_ride'], 'input moves Mack during dance'
                vm.v['#fd']=delta;vm.run('sound_tick');vm.run('dance_draw_test')
                poses.add(vm.sprites[0][2])
                assert vm.v['edance']==32-frame-delta, 'dance timing depends on frame batching'
                if vm.v['edance']:
                    assert vm.sprites[8][2]==vm.v['dancecolour'], 'clothes do not follow dance pose'
            assert {0,108,116}<=poses, 'dance poses not rendered'
            assert [upload for upload in vm.sprite_writes if upload[2]=='dance_bitmap']==[(27,4,'dance_bitmap')], (
                'dance sprite upload count/bank wrong')
            pitches=[e[1] for e in vm.sound if e[0]==0 and e[1] is not None and e[2]>0]
            assert pitches==[280,447,280,447,280,447,280], 'arrival two-tone rhythm changed'
            assert vm.sound[-1]==(0,None,0), 'dance sound remains latched'
            vm.v.update(jbe=0,jr=0);vm.run('elev_move')
            assert vm.v['edance']==0, 'parked elevator repeats dance'
            vm.v['jr']=1
            for _ in range(20):
                vm.run('st_ride')
                if vm.v['st']!=vm.v['s_ride']:break
            assert vm.v['emov']==0 and vm.v['st']==vm.v['s_walk'] and vm.v['mx']>start[0], (
                'right input after the dance must walk Mack out of the cabin')
            for stop in ('mack_die','quiet_screen','init_level'):
                vm.v.update(edance=20,st=vm.v['s_ride']);vm.run(stop)
                assert vm.v['edance']==0, 'dance survives death/screen change'
        empty=Basic(source);empty.v['lv']=1;empty.run('init_level')
        empty.v.update(ely=end-1 if down else end+1,eld=down,emov=1,st=empty.v['s_walk'])
        empty.run('elev_move')
        assert empty.v['edance']==0, 'empty summoned elevator starts dance'


def elevator_boarding(source):
    for floor in (72,168):
        for x in range(23):
            vm=Basic(source);vm.v['lv']=1;vm.run('init_level')
            vm.v.update(ely=floor,mx=x,my=floor-16,fcy=floor-16,
                        st=vm.v['s_fall'],ch=32,elarm=1,jbe=0)
            vm.run('fall_land')
            if x <= 15:
                assert vm.v['st']==vm.v['s_ride'], ('overlapping landing not boarded',floor,x)
                vm.run('mack_step')
                assert vm.v['emov']==1 and vm.v['mx']==vm.v['elx'], ('supported rider stranded',floor,x)
                assert vm.v['eld']==int(floor==72) and vm.v['elarm']==0
            else:
                assert vm.v['st']!=vm.v['s_ride'], ('non-overlapping landing boarded',floor,x)
            # Arrival remains disarmed; standing still cannot reverse the trip.
            if x <= 15:
                vm.v.update(emov=0,jl=0,jr=0);vm.run('st_ride')
                assert vm.v['emov']==0, 'parked arrival immediately reverses'
        # The chain at column 3 puts only Mack's outer sprite pixels over the
        # elevator; that must not count as a boarding overlap.
        vm=Basic(source);vm.v['lv']=1;vm.run('init_level')
        vm.v.update(ely=floor,mx=20,my=floor-16,fcy=floor-16,
                    st=vm.v['s_fall'],ch=32,elarm=1,jbe=0)
        vm.run('fall_land')
        assert vm.v['st']!=vm.v['s_ride'] and vm.v['emov']==0, (
            'chain-side sprite edge overlap must not board elevator')
        vm=Basic(source);vm.v['lv']=1;vm.run('init_level')
        vm.v.update(ely=floor,mx=20,my=floor-16,st=vm.v['s_walk'],
                    elarm=1,jl=0,jr=0)
        vm.run('st_walk')
        assert vm.v['st']!=vm.v['s_ride'] and vm.v['emov']==0, (
            'walking off the chain must not enter or start the elevator')
        # Right walks onto the adjacent beam without moving the elevator.
        vm=Basic(source);vm.v['lv']=1;vm.run('init_level')
        vm.v.update(ely=floor,mx=vm.v['elx'],my=floor-16,st=vm.v['s_ride'],
                    emov=0,elarm=0,jl=0,jr=1)
        for _ in range(20):
            vm.run('st_ride')
            if vm.v['st']!=vm.v['s_ride']:break
        assert vm.v['emov']==0 and vm.v['st']==vm.v['s_walk'], (
            'right input must leave the parked elevator, not summon another ride')
        assert vm.v['mx']>=vm.v['elx']+8 and vm.v['elarm']==1

        # Left must not send the parked elevator back on a trip. This shaft
        # abuts the screen edge, so moving left can stop at x=0 while still
        # inside the cabin; the tested escape is the supported right-hand beam.
        vm=Basic(source);vm.v['lv']=1;vm.run('init_level')
        vm.v.update(ely=floor,mx=vm.v['elx'],my=floor-16,st=vm.v['s_ride'],
                    emov=0,elarm=0,jl=1,jr=0)
        for _ in range(20):
            vm.run('st_ride')
            if vm.v['st']!=vm.v['s_ride']:break
        assert vm.v['emov']==0 and vm.v['mx']<=vm.v['elx'], (
            'left input must not start another elevator ride')

    # The Level 1 elevator stays where it was during death, then returns to
    # the bottom stop only when the next life begins.
    for oldy,moving in ((72,0),(117,1),(168,0)):
        vm=Basic(source);vm.v['lv']=1;vm.run('init_level')
        vm.v.update(ely=oldy,emov=moving,elarm=0,edance=12,elpaint=0,lives=2)
        if not moving:
            vm.run('elev_back')
        oldbase=(oldy//8-2)*32+vm.v['elx']//8
        vm.run('mack_die');vm.v['#fd']=1;vm.run('dead_tick')
        assert vm.v['st']==vm.v['s_dead'] and vm.v['ely']==oldy and vm.v['emov']==moving, (
            'elevator reset before death animation finished',oldy,moving,dict(vm.v))
        assert vm.v['elarm']==0 and vm.v['dclean']==1
        vm.v['#fd']=40;vm.run('dead_tick')
        assert vm.v['st']==vm.v['s_walk'] and vm.v['ely']==vm.v['elby'], (
            'death did not reset elevator at respawn',oldy,moving,dict(vm.v))
        assert vm.v['emov']==0 and vm.v['eld']==0 and vm.v['elarm']==1 and vm.v['edance']==0
        base=(vm.v['elby']//8-2)*32+vm.v['elx']//8
        assert [vm.screen[p] for p in (base,base+1,base+32,base+33,base+64,base+65)]==[
            227,229,228,230,236,237], 'reset elevator cabin/floor was not repainted'
        if not moving and oldy!=vm.v['elby']:
            assert [vm.screen[p] for p in (oldbase,oldbase+1,oldbase+32,oldbase+33,oldbase+64,oldbase+65)]==[32]*6, (
                'death left a duplicate parked cabin at the old stop')
    for x,y in ((24,152),(32,152),(8,148),(8,156)):
        vm=Basic(source);vm.v['lv']=1;vm.run('init_level')
        vm.v.update(mx=x,my=y,st=vm.v['s_ride'],elarm=1,jbe=0)
        vm.run('st_ride')
        assert vm.v['emov']==0, 'unsupported rider starts elevator'


def end_screen_timing(source):
    for origin in (0,65500):
        for mode,expected in (('idle',600),('held',600),('fresh',90),('early',110),
                              ('lockout',600),('earliest',76)):
            vm=Basic(source);vm.v['frame']=origin
            def frames():
                for frame in range(1,602):
                    button=(mode=='held' or (mode=='fresh' and frame>=90) or
                            (mode=='early' and (frame<=100 or frame>=110)) or
                            (mode=='lockout' and 20<=frame<=30) or
                            (mode=='earliest' and frame>=76))
                    yield dict(frame=(origin+frame)&65535,input_button=int(button))
            vm.frame_inputs=frames();vm.run('gameover_wait')
            assert vm.wait_count==expected, ('game-over delay/release/timeout',origin,mode,vm.wait_count)
    for key in (8,9):
        for age in (1,40,90):
            vm=Basic(source);vm.frame_inputs=iter(
                [{}]*(age-1)+[dict(input_fctn=1,input_key=key)])
            vm.run('gameover_wait')
            assert vm.wait_count==age, ('REDO/BACK cannot leave Game Over delay',key,age)
    for remaining in (0,5,95,105,5000):
        for score in (1000,65530):
            vm=Basic(source);vm.v.update(xlife=1,**{'#bonus':remaining,'#score':score})
            vm.frame_inputs=iter([{}]*210);vm.run('bonus_countdown')
            ticks=(remaining+99)//100
            assert vm.v['#bonus']==0 and vm.v['#score']==min(65535,score+remaining//5), 'bonus lost, doubled or overflowed'
            shown=[int(text.strip()) for pos,text in vm.prints if pos==16]
            assert shown==[max(0,remaining-100*n) for n in range(1,ticks+1)], 'bonus does not visibly count down'
            pulses=[(t,e) for t,e in vm.sound_times if e==(3,5,7)]
            assert [t for t,e in pulses]==list(range(0,ticks*4,4)), 'bonus ticker cadence'
            silences=[t for t,e in vm.sound_times if e==(3,None,0)]
            assert silences==list(range(2,ticks*4,4)), 'bonus tick needs a short, audible pulse'
            assert vm.wait_count==ticks*4
            if ticks:assert vm.sound[-1]==(3,None,0), 'bonus ticker remains latched'


def victory_scene(source):
    loop=source[source.index('main_loop:\n'):source.index('bonus_countdown:\n')]
    assert loop.find('IF lvdone = 1 THEN GOTO level_complete') > loop.find('GOSUB enemy_draw') >= 0, (
        'victory freezes sprites before the final frame is drawn')
    complete=source[source.index('level_complete:\n'):source.index('game_over:\n')]
    assert 'GOSUB quiet_screen' not in complete and 0 <= complete.find('GOSUB quiet_audio') < complete.find('GOSUB bonus_countdown') < complete.find('GOSUB init_level'), (
        'victory clears the completed site before awarding the bonus')
    music=source[source.index('banked_completion_music:\n'):source.index('victory_music1:\n')]
    assert 'GOSUB quiet_screen' not in music, 'fanfare erased frozen victory sprites'
    for stage in (1,2,3):
        vm=Basic(source);vm.v.update(lv=stage,levelno=stage,xlife=1)
        vm.run('init_level')
        vm.v['#bonus']=200
        vm.sprites[0]=(48,96,0,15)
        vm.sprites[3]=(64,104,24,7)
        frozen=dict(vm.sprites)
        vm.v.update(snd0=8,snd1=8,snd2=8,snd3=8)
        vm.run('quiet_audio')
        assert vm.sprites==frozen and all(vm.v[k]==0 for k in ('snd0','snd1','snd2','snd3')), (
            'victory audio stop erased a sprite or left a gameplay sound active',stage)
        vm.frame_inputs=iter([{}]*12)
        vm.run('bonus_countdown')
        assert vm.sprites==frozen and vm.v['#bonus']==0, (
            'bonus award altered the frozen victory sprites',stage)
        # Exercise the actual award/fanfare path, ending just before the next
        # main loop. The scene may clear only when init_level begins.
        end=source.index('level_complete:\n')
        stop=source.index('game_over:\n',end)
        full=source[:end]+source[end:stop].replace('\tGOTO main_loop\n','\tRETURN\n')+source[stop:]
        run=Basic(full);run.v.update(lv=stage,levelno=stage,lives=2,xlife=1)
        run.run('init_level');run.v.update(lvdone=1,**{'#bonus':200})
        run.sprites[0]=(48,96,0,15);run.sprites[3]=(64,104,24,7)
        held=dict(run.sprites)
        waits=[]
        def frames():
            for tick in range(300):
                if run.v['lv']==stage:
                    waits.append(tick)
                    assert run.sprites==held, ('victory sprites vanished during tally/fanfare',stage,tick)
                yield {}
        run.frame_inputs=frames();run.run('level_complete')
        assert len(waits)>8 and run.v['lv']==(stage%3)+1, (
            'victory did not complete tally and advance to next site',stage)


def death_timing(source):
    # The three sites have different machinery, but none may restore carried
    # inventory, reset the hammer, or consume a reserve during the death pose.
    for stage in (1,2,3):
        vm=Basic(source);vm.v.update(lv=stage,levelno=stage,lives=2)
        vm.run('init_level')
        vm.v.update(jhx=88,jhy=64,jhway=7,**{'#bonus':4200})
        vm.v['hzphase']=23
        vm.v['clawstep']=5
        vm.v['bmy']=104
        vm.v['pnphase']=11
        if stage!=2:
            item=next(i for i in range(vm.v['nitem']) if vm.arrays['itk'][i]==0)
            row,col=vm.arrays['itr'][item],vm.arrays['itc'][item]
            cell=row*32+col
            original=vm.screen[cell]
            vm.v.update(mx=col*8-8,my=row*8-8,
                        ch=vm.v['t_brick'] if stage==1 else vm.v['t_sbox'])
            vm.run('take_item')
            assert vm.v['carry']==1 and vm.arrays['itst'][item]==1 and vm.screen[cell]==32
        else:
            vm.v['carry']=0
        before=tuple(vm.v[k] for k in
                     ('carry','jhx','jhy','jhway','lives','#bonus','hzphase','clawstep','bmy','pnphase'))
        vm.run('mack_die')
        vm.v['#fd']=1;vm.run('dead_tick');vm.run('site_draw')
        after=tuple(vm.v[k] for k in
                    ('carry','jhx','jhy','jhway','lives','#bonus','hzphase','clawstep','bmy','pnphase'))
        assert after==before and vm.v['dclean']==1 and vm.v['st']==vm.v['s_dead'], (
            'site reset before the death sequence ended',stage,before,after)
        if stage!=2:
            assert vm.arrays['itst'][item]==1 and vm.screen[cell]==32, (
                'carried box reappeared on the map during death',stage)
        vm.v['#fd']=39;vm.run('dead_tick')
        assert vm.v['dclean']==0 and vm.v['st']==vm.v['s_walk'] and vm.v['lives']==1, (
            'site failed to respawn after the death sequence',stage)
        assert vm.v['#bonus']==5000 and (vm.v['jhx'],vm.v['jhy'],vm.v['jhway'])==(
            vm.v['jhx0'],vm.v['jhy0'],0)
        if stage!=2:
            assert vm.v['carry']==0 and vm.arrays['itst'][item]==0 and vm.screen[cell]==original, (
                'carried box did not return at respawn',stage)


def girder_spacing(source):
    expected={1:{4,5,11,12,17,18,24,25},
              2:{3,4,8,9,12,13,15,16,19,20,24,25},
              3:{3,4,8,9,13,14,18,19,23,24,27,28}}
    vm=Basic(source)
    for level in (1,2,3,1):
        vm.v['lv']=level;vm.run('init_level')
        plain,dotted=0,0
        for cell,ch in enumerate(vm.screen):
            if ch in (128,129,130,134):
                # The user requested rivets across the short furnace support,
                # independently of the long girders' repeating column pattern.
                furnace_support=level==2 and cell in (6*32+28,6*32+29)
                assert (ch==134)==(cell%32 in expected[level] or furnace_support), ('girder spacing',level,cell)
                plain+=ch!=134;dotted+=ch==134
                vm.v.update(mx=cell%32*8-8,my=cell//32*8-16)
                if vm.v['mx']>=0:
                    vm.run('foot_probe');assert vm.v['sup']==1, 'plain/riveted cell lost support'
        assert plain>dotted>0, 'rivets crowd out plain beam sections'
        assert (134,1,'girder_dot_col',(level-1)*8) in vm.color_writes, 'rivet palette not updated'
        expected_art='beamplain_pat' if level==2 else 'fixture_pat'
        assert [w[2] for w in vm.pattern_writes if w[0]==96][-1]==expected_art, 'crane slices corrupt next-site cabinet'
        assert vm.bank==1, 'girder setup leaks bank'
    # The repaired holes must continue the established pattern, not restart it.
    for col in (10,11,16,18):
        vm.v.update(lv=1,mx=col*8-8,my=56,carry=2)
        vm.arrays['gapr'][0]=9;vm.arrays['gapc'][0]=col;vm.arrays['gapst'][0]=1
        vm.run('rivet_gap')
        assert vm.screen[9*32+col]==(134 if col in expected[1] else 132), 'rivet repair breaks beam spacing'
    vm.v['lv']=2;vm.run('init_level')
    for offset in range(8):
        vm.v.update(bmy=136+offset,bmyd=255);vm.run('beam_draw')
        top=vm.screen[17*32+12:17*32+17];bottom=vm.screen[18*32+12:18*32+17]
        assert top==[192+offset,192+offset,96+offset,192+offset,192+offset]
        assert bottom==[200+offset,200+offset,104+offset,200+offset,200+offset]
    body=re.search(r'^beamplain_pat:\n.*?(?=^\w+:)',source,re.M|re.S).group()
    data=[int(v[1:],16) for v in re.findall(r'\$[0-9A-F]{2}',body)]
    for offset in range(8):
        pixels=data[offset*8:offset*8+8]+data[64+offset*8:72+offset*8]
        assert pixels==[0]*offset+[255]*8+[0]*(8-offset), 'plain crane slice has a hole or stray pixels'


def factory_drive(source):
    def table(label):
        body=re.search(r'^'+label+r':\n.*?(?=^\w+:)',source,re.M|re.S)[0]
        return [int(v[1:],16) for v in re.findall(r'\$[0-9A-F]{2}',body)]
    chains=table('drivechain_pat');colors=table('drivechain_col')
    wheels=table('wheel_anim_pat')
    assert len(chains)==len(colors)==128 and len(wheels)==256
    assert len({tuple(wheels[i:i+32]) for i in range(0,256,32)})==8, 'wheel spokes do not turn'
    for phase in range(8):
        for row in range(8):
            for half,direction in ((0,1),(8,-1)):
                index=phase*16+half+row;previous=half+(row-direction*phase)%8
                assert chains[index]==chains[previous], 'chain links slip against paddle direction'
                assert colors[index]==colors[previous], 'chain highlight detached from moving link'
    for batch in (1,2,4):
        vm=Basic(source);vm.v['lv']=3;vm.run('init_level')
        for elapsed in range(0,448,batch):
            for _ in range(batch):vm.run('lift_move')
            vm.pattern_writes.clear();vm.color_writes.clear()
            vm.v['hzphase']=(elapsed*3+17)%128
            vm.run('fixture_draw')
            phase=vm.v['pnphase']
            assert vm.v['chainlast']==phase%8, 'chain drifted from actual paddle position'
            assert vm.v['drivelast']==phase//4%8, 'wheel drifted from actual paddle position'
            assert (208,2,'drivechain_pat',phase%8*16) in vm.pattern_writes
            assert (208,2,'drivechain_col',phase%8*16) in vm.color_writes
            offset=phase//4%8*32
            vm.expect_upload(912,16,'wheel_anim_pat',offset)
            vm.expect_upload(2976,16,'wheel_anim_pat',offset+16)
            vm.expect_upload(5008,32,'wheel_anim_pat',offset)
            assert vm.bank==1, 'drive renderer leaves the wrong bank selected'
            vm.pattern_writes.clear();vm.color_writes.clear();vm.run('fixture_draw')
            assert not vm.pattern_writes and not vm.color_writes, 'stopped drive keeps uploading art'


def work_sounds(source):
    for fx,pitch,vol,length in ((0,550,8,6),(1,860,5,2),(2,700,7,3),(3,240,9,5),(4,120,13,8)):
        vm=Basic(source);vm.v.update(workfx=fx,snd0=10,snd2=12)
        vm.run('work_sound')
        assert (1,pitch,vol) in vm.sound and vm.v['snd1']==length, 'missing material sound'
        assert vm.v['snd0']==10 and vm.v['snd2']==12, 'work sound interrupts reward/jump'
        assert vm.bank==1, 'work sound leaks bank'
        vm.v['#fd']=12;vm.run('sound_tick')
        assert vm.v['snd1']==0 and (1,None,0) in vm.sound, 'work sound never stops'
        if fx!=4:assert (3,None,0) in vm.sound
    for guard,value in (('st',None),('snd3',10),('snd1',6)):
        vm=Basic(source);vm.v[guard]=vm.v['s_dead'] if value is None else value;vm.run('work_sound')
        assert not vm.sound, 'work sound replaces a higher-priority effect'
    vm=Basic(source);vm.v.update(lv=1,ely=144,elty=72,emov=0)
    vm.run('elev_move');assert not vm.sound, 'parked elevator rattles'
    vm.v['emov']=1;vm.run('elev_move')
    assert (1,860,5) in vm.sound, 'moving elevator lacks ratchet'
    assert any(ch==0 and pitch is not None and vol==10 for ch,pitch,vol in vm.sound), 'moving elevator lacks directional tone'
    vm=Basic(source);vm.v.update(lv=1,ely=96,elty=72,elby=168,emov=1,eld=0)
    vm.run('elev_move');rise=next(pitch for ch,pitch,vol in vm.sound if ch==0)
    vm.v.update(ely=96,emov=1,eld=1);vm.sound.clear();vm.run('elev_move')
    lower=next(pitch for ch,pitch,vol in vm.sound if ch==0)
    assert rise==lower and rise==519, 'elevator pitch should follow cabin height in both directions'
    for start,direction,first,last,step in ((168,0,1023,407,-56),(72,1,351,967,56)):
        vm=Basic(source);vm.v.update(lv=1,ely=start,elty=72,elby=168,emov=1,eld=direction)
        for _ in range(96):vm.run('elev_move')
        notes=[pitch for ch,pitch,vol in vm.sound if ch==0 and pitch is not None and vol==10]
        assert len(notes)==12 and notes[0]==first and notes[-1]==last, (
            'elevator sweep endpoints or eight-pixel cadence are wrong',direction,notes)
        assert all(1<=pitch<=1023 for pitch in notes), 'elevator divider exceeds the PSG field'
        assert all(b-a==step for a,b in zip(notes,notes[1:])), (
            'elevator pitch travels opposite the cabin',direction,notes)
        assert vm.v['emov']==0 and (0,None,0) in vm.sound, 'elevator tone continues after parking'
    vm=Basic(source);vm.v.update(lv=3);vm.run('init_level')
    vm.v.update(boxfall=3,outputtick=15,nbox=1,boxx=64,boxy=176)
    vm.run('factory_output')
    assert (1,120,13) in vm.sound and vm.bank==1, 'bucket arrival lacks quiet ping or leaks bank'


def factory_challenge(source):
    wins=0
    for phase in range(0,128,8):
        vm=Basic(source);vm.v['lv']=3;vm.run('init_level')
        assert all(vm.screen[row*32+10]!=155 for row in (6,7,8)), 'factory shortcut chain restored'
        assert vm.screen[6*32+4]==155, 'original left escape chain missing'
        vm.v['pnphase']=8;vm.run('lift_positions')
        vm.v.update(mx=vm.arrays['pnxcar'][0]-4,my=vm.arrays['pnycar'][0]-16,
                    pnside=0,bonbeam=1,jbe=1,jl=1,hzphase=phase)
        vm.run('world_step')
        for _ in range(50):
            if vm.v['st'] in (vm.v['s_walk'],vm.v['s_dead']):break
            vm.run('world_step')
        vm.v.update(jl=1,ju=1,jbe=0)
        for _ in range(100):
            if vm.v['st']==vm.v['s_dead']:break
            if vm.v['st']==vm.v['s_walk'] and vm.v['my']==24:break
            vm.run('world_step')
        if vm.v['st']==vm.v['s_walk'] and vm.v['my']==24 and vm.v['carry']==1:wins+=1
    assert 6<=wins<16, ('factory box route must be reachable and require timing',wins)


def sound_contract(source):
    # Execute the actual frame-start and render-tail sound ordering. A busy
    # pass must expire the old effect, then let a newly triggered one survive.
    prefix=source[source.index('\t#fd = FRAME'):source.index("\t' Pace scaling")]
    tail=source[source.index("\t' L2 crane beam is rendered"):source.index('tone_start:')]
    tail=tail.replace('\tGOTO main_loop','\tRETURN')
    vm=Basic(source+'\nBANK 0\nframe_start_test:\n'+prefix+'\tRETURN\nrender_tail_test:\n'+tail)
    vm.v.update(frame=4,snd3=1,jr=1,steptick=7)
    vm.run('frame_start_test')
    assert vm.v['snd3']==0, 'old sound not aged before new activity'
    vm.run('mack_step');vm.run('render_tail_test')
    assert vm.v['snd3']==2 and vm.sound[-1]==(3,4,7), 'fresh sound erased in busy frame'
    for pitch, duration in ((600,14),(300,5),(360,12),(140,12),(180,8),(400,6)):
        vm = Basic(source)
        vm.v.update(sfxlen=duration,sndvol=12)
        vm.v['#sndpitch']=pitch;vm.run('tone_start')
        channel=2 if pitch in (600,300,360) else 0
        for delta in (4,3,4,3,4,3,4):
            vm.v['#fd']=delta;vm.run('sound_tick')
        assert vm.v['snd'+str(channel)]==0 and (channel,None,0) in vm.sound, 'tone stuck on'
        assert all(0 < event[1] <= 1023 for event in vm.sound if event[1] is not None)
        assert vm.bank==1

    vm=Basic(source);vm.v.update(jr=1);vm.v['#fd']=1
    for _ in range(24):
        vm.run('mack_step');vm.run('sound_tick')
    assert vm.sound.count((3,4,7))==3, 'walking has no regular footsteps'
    assert (1,900,7) in vm.sound and (1,740,7) in vm.sound, 'boots lack alternating taps'
    vm.run('sound_tick')
    assert vm.v['snd3']==0 and (3,None,0) in vm.sound and (1,None,0) in vm.sound, 'footstep stuck on'
    for state,x,direction in (('s_walk',40,0),('s_walk',240,1),('s_jump',40,1)):
        quiet=Basic(source);quiet.v.update(st=quiet.v[state],mx=x,jr=direction,steptick=7)
        quiet.run('mack_step')
        assert not any(e[0] in (1,3) for e in quiet.sound), 'idle, blocked or airborne footsteps'
    vm=Basic(source);vm.v.update(jr=1,steptick=7,snd3=10,snd1=5,snd2=12)
    vm.run('mack_step')
    assert vm.v['snd3']==10 and vm.v['snd2']==12 and not vm.sound, 'step interrupts effect'
    vm.v.update(snd0=10,snd1=6);vm.run('quiet_screen')
    for ch in range(4):
        assert (ch,None,0) in vm.sound and vm.v['snd'+str(ch)]==0, 'channel survives screen transition'
    for level,carry,hz,claw in ((1,2,7,0),(2,0,27,0),(3,0,43,0),(2,0,80,47)):
        vm=Basic(source);vm.v.update(lv=level);vm.run('init_level')
        vm.v.update(mx=112,my=80,carry=carry,hzphase=hz,clawclock=claw,**{'#slagclock':180})
        vm.run('site_step')
        assert (3,5,8) in vm.sound and (1,180,10) in vm.sound, ('silent machinery',level,carry,hz,claw)
        vm.v['#fd']=7;vm.run('sound_tick')
        assert vm.v['snd3']==vm.v['snd1']==0 and (1,None,0) in vm.sound, 'machine impact stuck on'
    vm=Basic(source);vm.v.update(snd3=10);vm.run('machine_clack')
    assert vm.v['snd3']==10 and not vm.sound, 'machinery interrupts riveting'
    vm.v['snd3']=2;vm.run('machine_clack')
    assert (3,5,8) in vm.sound and (1,180,10) in vm.sound, 'footsteps mask machinery'
    # A pickup during a jump must leave its pitch, volume and lifetime intact.
    vm=Basic(source);vm.v.update(sfxlen=12,sndvol=8,**{'#sndpitch':360});vm.run('tone_start')
    motion=tuple(vm.v[k] for k in ('snd2','snd2v','#motionpitch'))
    vm.v.update(sfxlen=8,sndvol=10,**{'#sndpitch':180});vm.run('tone_start')
    assert tuple(vm.v[k] for k in ('snd2','snd2v','#motionpitch'))==motion, 'pickup erases jump sound'
    assert vm.v['snd0']>0 and vm.sound[-1][0]==0
    vm.run('mack_die')
    assert vm.v['snd0']==vm.v['snd1']==0 and (3,6,10) in vm.sound, 'death lacks priority/impact'
    events=len(vm.sound);vm.v.update(sfxlen=8,**{'#sndpitch':180});vm.run('tone_start')
    assert len(vm.sound)==events, 'pickup overrides death'
    # Execute every site's actual score, including voice/bank selection.
    themes=[]
    for level in (1,2,3):
        vm=Basic(source);vm.v['lv']=level;vm.frame_inputs=iter([{}]*300);vm.run('completion_music')
        notes=[(frame,event) for frame,event in vm.sound_times if event[0]==0 and event[1] is not None and event[2]>0]
        assert len(notes)==12 and len({e[1] for _,e in notes})>=6, 'completion is still a short beep pattern'
        themes.append(tuple(e[1] for _,e in notes))
        assert themes[-1][-1]==107, 'site theme does not resolve to shared tonic'
        for channel in (1,2):
            assert len([e for _,e in vm.sound_times if e[0]==channel and e[1] is not None and e[2]>0])==12, 'fanfare missing harmony or bass'
        assert 120<=vm.wait_count<=160 and vm.bank==1, 'fanfare duration or bank return'
        last={}
        for frame,event in vm.sound_times:
            ch,pitch,vol=event;last[ch]=vol
            if pitch is not None:assert 0<pitch<=1023
        assert last=={0:0,1:0,2:0,3:0}, 'fanfare leaves a channel latched'
    assert len(set(themes))==3, 'sites share the same fanfare'
    # Held Up makes one chain clink per eight pixels, never stationary buzzing.
    vm=Basic(source);vm.v['lv']=3;vm.run('init_level');vm.sound=[]
    vm.v.update(mx=28,my=57,st=vm.v['s_climb'],ju=1)
    for _ in range(12):vm.run('mack_step');vm.v['#fd']=1;vm.run('sound_tick')
    assert (1,240,7) in vm.sound, 'silent chain climbing'



def pincer_passage(source):
    # A one-pixel shoe/edge graze was the specific failure in the lower crane
    # approach. Preserve that allowance even when a different launch can win.
    graze=Basic(source);graze.v.update(lv=2);graze.run('init_level')
    graze.v.update(mx=30,my=120,clawclock=95,**{'#slagclock':180})
    graze.run('site_step')
    assert graze.v['st']!=graze.v['s_dead'], 'pincer kills a shoe-edge graze'
    art=re.search(r'^claw_pat:\n.*?(?=^\w+:)',source,re.M|re.S).group()
    data=[int(n[1:],16) for n in re.findall(r'\$[0-9A-F]{2}',art)]
    assert len(data)==680, 'pincers need seventeen full-width poses'
    cells=[i%32 for i,ch in enumerate(graze.screen) if 238<=ch<=242]
    assert len(cells)==5 and cells==list(range(cells[0],cells[0]+5))
    assert 88-(max(cells)+1)*8>=16, 'no full standing patch right of the open jaws'
    for y in range(2,8):
        gaps=[]
        for pose in range(17):
            frame=data[pose*40:][:40]
            xs=[tile*8+x for tile in range(5) for x in range(8)
                if frame[tile*8+y] & (128>>x)]
            gaps.append(min(x for x in xs if x>=20)-max(x for x in xs if x<20)-1)
        assert gaps[0]>=32 and gaps[-1]==0, ('whole jaw face must open and touch',y,gaps)
    # Two real jumps: over the first jaw, land in the opening, then over the
    # other. Real ledge/ceiling geometry and live hazard timing, both directions.
    for direction,start,end in ((0,78,14),(1,14,78)):
        wins=0
        for phase in range(0,96,12):
            vm=Basic(source);vm.v.update(lv=2);vm.run('init_level')
            vm.v.update(mx=start,my=120,clawclock=phase,**{'#slagclock':180})
            for hop in range(2):
                vm.v.update(jbe=1,jl=1-direction,jr=direction)
                vm.run('mack_step');vm.run('site_step')
                for _ in range(32):
                    if vm.v['st']==vm.v['s_dead']:break
                    vm.run('mack_step');vm.run('site_step')
                if vm.v['st']==vm.v['s_dead']:break
            if vm.v['st']==vm.v['s_walk'] and abs(vm.v['mx']-end)<=2:
                wins+=1
        assert wins>=3, ('no generous two-jump pincer passage',direction,wins)
    # The reference route stages on the right of the jaws BEFORE two jumps.
    # Walk off the rising girder as it reaches the ledge, stop on that safe
    # patch, and wait for full closure. Keep the six-of-eight gate and all
    # hazards live; the former direct two-hop shortcut skipped the safe patch.
    for height in (128,136,144):
        wins=0
        for phase in range(0,96,12):
            vm=Basic(source);vm.v.update(lv=2);vm.run('init_level')
            vm.v.update(mx=88,my=height-16,bmy=height,bmactive=1,bonbeam=1,
                        bmd=0,clawclock=phase,**{'#slagclock':180})
            while vm.v['bmy']>136:vm.run('world_step')
            for _ in range(64):
                vm.v['jl']=int(vm.v['mx']>74)
                vm.run('world_step')
                if vm.v['mx']==74 and vm.v['my']==120:break
                if vm.v['st']==vm.v['s_dead']:break
            assert (vm.v['mx'],vm.v['my'],vm.v['st'])==(74,120,vm.v['s_walk']), 'cannot stage beside jaws'
            vm.v['jl']=0
            previous=vm.v['clawstep']
            for _ in range(97):
                vm.run('world_step')
                if vm.v['clawstep']==16 and previous==15:break
                previous=vm.v['clawstep']
            assert vm.v['st']==vm.v['s_walk'], 'right waiting patch is unsafe'
            before=vm.v['nlbr']
            for hop in range(2):
                vm.v.update(jbe=1,jl=1)
                vm.run('world_step')
                for _ in range(48):
                    vm.run('world_step')
                    if vm.v['st'] in (vm.v['s_dead'],vm.v['s_walk']):break
                if vm.v['st']==vm.v['s_dead']:break
                vm.v.update(jbe=0,jl=0)
                for _ in range(12):vm.run('world_step')
            wins+=vm.v['st']==vm.v['s_walk'] and vm.v['mx']==10 and vm.v['nlbr']==before-1
        assert wins>=6, ('unfair crane-to-pincer approach',height,wins)

    # Real re-press margin: stop after landing, release FIRE, wait 12 world
    # steps (~178 ms), then jump again. A continuous launch window around full closure
    # (including a 12-step release/re-press pause) must work both ways, with ALL world hazards advancing.
    seed=Basic(source);seed.v['lv']=2;seed.run('init_level')
    for direction,start,end in ((0,78,14),(1,14,78)):
        for phase in range(40,59,2):
            vm=copy.deepcopy(seed)
            vm.v.update(mx=start,my=120,clawclock=phase,**{'#slagclock':180})
            for hop in range(2):
                vm.v.update(jbe=1,jl=1-direction,jr=direction)
                vm.run('world_step')
                for _ in range(48):
                    vm.run('world_step')
                    if vm.v['st'] in (vm.v['s_dead'],vm.v['s_walk']):break
                assert vm.v['st']==vm.v['s_walk'], ('pincer landing',direction,phase,hop)
                if hop==0:
                    vm.v.update(jbe=0,jl=0,jr=0)
                    for _ in range(12):vm.run('world_step')
                    assert vm.v['st']==vm.v['s_walk'], ('no time to re-press jump',direction,phase)
            assert abs(vm.v['mx']-end)<=2, ('pincer crossing incomplete',direction,phase)


def crane_contact(source):
    seed=Basic(source);seed.v['lv']=2;seed.run('init_level')
    # The rising girder crosses the feet during the jump's stationary apex.
    # The old descent-only catch misses this and subsequently falls through.
    for height in (112,136,160):
        for x in (83,96,120,133):
            vm=copy.deepcopy(seed)
            vm.v.update(mx=x,my=height-18,bmy=height,bmd=0,bmactive=1,
                        st=vm.v['s_jump'],jix=8,jhang=16,jhz=1,fcy=height-18)
            for _ in range(4):vm.run('world_step')
            assert vm.v['bonbeam']==1 and vm.v['st']==vm.v['s_walk'], ('apex falls through rising girder',height,x)
            assert vm.v['my']+16==vm.v['bmy'], 'rider not on surface'
        for x,y in ((60,height-18),(104,height-14)):
            vm=copy.deepcopy(seed)
            vm.v.update(mx=x,my=y,bmy=height,bmd=0,bmactive=1,
                        st=vm.v['s_jump'],jix=8,jhang=16,jhz=1,fcy=y)
            for _ in range(4):vm.run('world_step')
            assert not vm.v['bonbeam'], 'girder catches outside span or from underneath'
    # This is a place to STOP, not merely a pixel a scripted jump passes over.
    for x in (70,74,78,82):
        vm=copy.deepcopy(seed);vm.v.update(mx=x,my=120)
        for _ in range(129):vm.run('world_step')
        assert (vm.v['mx'],vm.v['my'],vm.v['st'])==(x,120,vm.v['s_walk']), ('unsafe standing patch',x)
    vm=copy.deepcopy(seed);vm.v.update(mx=83,my=120);vm.run('foot_probe')
    assert vm.v['sup']==0, 'standing patch extends invisibly into gap'


def machinery_animation(source):
    def table(label):
        block=re.search(r'^'+label+r':\n.*?(?=^\w+:)',source,re.M|re.S).group()
        return [int(n[1:],16) for n in re.findall(r'\$[0-9A-F]{2}',block)]
    vm=Basic(source);vm.v.update(lv=2);vm.run('init_level')
    poses=[]
    vm.v.update(mx=112,my=80,clawclock=95)
    for _ in range(91):
        vm.run('site_step');vm.run('site_draw');poses.append(vm.v['clawstep'])
        assert vm.bank==1, 'animation bank not restored'
        assert vm.sprites[14][0]==209, 'level-2 smasher still uses a sprite'
    assert set(poses)==set(range(17)) and poses[0]==poses[90]==0
    assert all(abs(a-b)<=1 for a,b in zip(poses,poses[1:])), 'pincers snap between poses'
    assert all(len(set(poses[i:i+5]))>1 for i in range(87)), 'pincers pause at an endpoint'
    assert len(vm.pattern_writes)<97*3, 'unchanged machinery reuploads every pass'
    patterns=table('press_pat');colors=table('press_col')
    assert len(patterns)==len(colors)==32*48
    for row in range(3):
        assert vm.screen[(14+row)*32+23:(14+row)*32+25]==[243+row*2,244+row*2]
    feet=table('pressfoot_pat')
    assert len(feet)==3*8*16
    footcolors=table('pressfoot_col')
    for level,base,origin,low,high in ((2,112,184,105,124),(3,48,56,41,62)):
        vm=Basic(source);vm.v.update(lv=level);vm.run('init_level')
        hit=Basic(source);hit.v.update(lv=level);hit.run('init_level')
        positions=[]
        for clock in range(128):
            vm.v.update(mx=112,my=80,hzphase=clock-1,st=vm.v['s_walk'])
            vm.run('site_step');vm.run('site_draw')
            position=vm.v['pressy'];positions.append(position)
            phase=position-(96 if level==2 else 32)
            frame=patterns[phase*48:][:48]
            def painted(x,y):return bool(frame[(y//8*2+x//8)*8+y%8] & (128>>(x%8)))
            for y in range(max(0,phase-9)):
                assert painted(7,y) and painted(8,y), 'floating smasher head'
            for y in range(max(0,phase-9),min(24,phase-4)):
                assert painted(1,y) and painted(14,y), 'smasher head too narrow'
                for tile in range(2):
                    assert colors[phase*48+(y//8*2+tile)*8+y%8]==[0xf1,0xf1,0xe1,0xf1,0xf1][y-(phase-9)], 'head color slips across a cell'
            vm.v.update(presslast=255)
            vm.run('site_draw')
            assert vm.bank==1 and vm.sprites[14][0]==209, 'sprite smasher or wrong bank'
            for row in range(3):
                third=((14 if level==2 else 6)+row)//8
                for color,label in ((0,'press_pat'),(8192,'press_col')):
                    vm.expect_upload(color+third*2048+(243+row*2)*8,16,label,phase*48+row*16)
            top=max(base,position+7);bottom=min(base+(23 if level==2 else 25),position+11)
            for y in range(base-32,base+34):
                hit.v.update(mx=origin,my=y,hzphase=clock-1,st=hit.v['s_walk'],**{'#slagclock':180})
                hit.run('site_step')
                if hit.v['st']==hit.v['s_dead']:
                    assert top<=bottom and y+15>=top and y+4<=bottom, 'invisible smasher hit'
            if top<=bottom:
                y=(top+bottom)//2-9
                # The new outer head edges also have to be lethal: merely
                # enlarging the artwork would leave these contacts harmless.
                for dx in (-7,0,7):
                    hit.v.update(mx=origin+dx,my=y,hzphase=clock-1,st=hit.v['s_walk'])
                    hit.run('site_step')
                    assert hit.v['st']==hit.v['s_dead'], 'wide smasher edge is harmless'
            if level==3:
                depth=max(0,phase-28)
                offset=(depth*8+vm.v['cvaf'])*16
                foot=feet[offset:offset+16]
                for tile in range(2):
                    # Surface/rails and moving treads remain unchanged below
                    # the two extra head rows, in every conveyor phase.
                    belt=table('belt_anim%d'%vm.v['cvaf'])[40:48]
                    assert foot[tile*8+2:tile*8+8]==belt[2:8], 'smasher erases belt'
                    assert bool(foot[tile*8+1])==(depth==2), 'head misses belt rail'
                assert vm.screen[9*32+7:9*32+9]==[249,250], 'missing smasher foot cells'
                vm.expect_upload(4040,16,'pressfoot_pat',offset)
                vm.expect_upload(12232,16,'pressfoot_col',depth*16)
                for y in range(depth):
                    assert footcolors[depth*16+y]==[0xf1,0xf1][2-depth+y]
        assert min(positions)==low and max(positions)==high, ('smasher travel',level,positions)
        assert all(-1<=b-a<=(3 if level==2 else 2) for a,b in zip(positions,positions[1:]+positions[:1])), 'smasher snaps back'
        assert positions.count(high)<=10, 'smasher pins player too long'
        impact=28 if level==2 else 44
        assert positions.index(high)==impact, 'smasher impact beat moved'
        assert sum(b>a for a,b in zip(positions,positions[1:]))==(8 if level==2 else 18), 'smasher downstroke not quicker'
        last_parked=max(i for i,p in enumerate(positions[:impact]) if p==low)
        assert impact-last_parked==(8 if level==2 else 18), 'smasher downstroke timing wrong'
        assert positions[96:]==[low]*32, 'smasher top pause lost'
        assert low+8>=base and positions.count(low)>=32, 'smasher must wait visibly at the top'
        assert positions[28 if level==2 else 44]==high, 'wrong downward smasher speed'
        assert high+11==(135 if level==2 else 73), 'head must finish exactly above surface'
        if level==3:
            assert vm.screen[8*32+6]==vm.v['t_sbox'], 'conveyor box missing from left of piston'
            assert vm.screen[8*32+7]==247, 'conveyor box overlaps piston'
            vm.v.update(mx=44,my=56,ch=vm.v['t_sbox']);vm.run('take_item')
            assert vm.arrays['itst'][1]==1 and vm.v['carry']==1
            vm.run('site_draw')
            assert vm.screen[8*32+7]==247, 'box pickup punched a hole in the piston'
            assert vm.screen[8*32+6]==32, 'collected conveyor box remains visible'
            assert vm.screen[4*32+12]==vm.v['t_sbox'], 'piston changed other boxes'


def slag_cadence(source):
    vm=Basic(source);vm.v.update(lv=2);vm.run('init_level')
    vm.v.update(mx=112,my=80,bmy=167,bmd=0,bmactive=1)
    returns=[];emissions=[]
    for tick in range(1,1191):
        vm.run('beam_move');vm.run('site_step')
        if vm.v['#slagclock']==0:emissions.append(tick)
        if vm.v['bmy']==167 and vm.v['bmd']==0:
            returns.append(vm.v['slagphase']<60)
    assert emissions==[317,634,951], ('unexpected glop release interval',emissions)
    assert len(returns)==5 and any(returns) and not all(returns), 'glop locked to crane visits'


def visual_hazards(source):
    """Execute trajectories/render calls; compare lethal regions with visible art."""
    vm=Basic(source);vm.v.update(lv=2);vm.run('init_level')
    assert vm.screen[12*32+7:12*32+9]==[167,168], 'mid-left crate is not two hazard cells'
    assert vm.screen[12*32+3:12*32+5]==[183,184], 'mid-left pail did not move left'
    vm.run('beam_draw')
    for _ in range(250):
        assert all(vm.screen[row*32+14]==178 for row in range(3,vm.v['bmy']//8)), 'broken crane cable'
        vm.v['bmactive']=1;vm.run('beam_move');vm.run('beam_draw')
    assert vm.screen[16*32+4:16*32+9]==[238,239,240,241,242], 'missing paired pincers'
    path=[]
    for clock in range(317):
        vm.v.update(mx=112,my=80,st=vm.v['s_walk'],**{'#slagclock':(clock-1)%317})
        vm.run('site_step');vm.run('site_draw')
        visible=vm.sprites[15][0]!=209
        assert visible==(clock<120), ('slag visibility/collision phase',clock)
        if visible:
            path.append((vm.v['blobx'],vm.v['bloby']))
            assert vm.sprites[15][1]==vm.v['blobx']
            if 32<=clock<88:
                vm.v.update(fx=vm.v['blobx']+8,kx0=vm.arrays['cvx0'][1],
                            ky0=vm.arrays['cvy0'][1],kdy=16)
                vm.run('belt_surface')
                assert abs(vm.v['bloby']+9-vm.v['srf'])<=1, ('slag buried below belt',clock)
        assert vm.pattern_writes[-1][0] in (120,124,156,238,243,247)
    assert all(path[i]==path[i+1] for i in range(0,120,2)), 'slag ignores half-speed clock'
    assert len(set(x for x,y in path[:32]))==1
    assert all(0<=b[0]-a[0]<=1 and abs(b[1]-a[1])<=2 for a,b in zip(path,path[1:]))
    assert path[100][1]<path[88][1] and path[-1][1]>path[100][1], 'missing roller arc'
    # Actual final sprite footprint enters the visible opening, not the grass.
    x,y=path[-1]
    assert 83<=x+5<=x+10<=90 and 169<=y+4<=y+9<=174, 'slag misses receiver mouth'
    assert vm.screen[21*32+10:21*32+12]==[189,190], 'receiver top missing'
    assert vm.screen[22*32+10:22*32+12]==[162,163], 'receiver base repeats one half'
    assert vm.screen[21*32+17:21*32+19]==[32,32], 'extra machine right of crane'
    assert vm.screen[22*32+17:22*32+19]==[32,32], 'extra machine base right of crane'
    departed=Basic(source);departed.v.update(lv=3);departed.run('init_level')
    departed.arrays['pnxcar'][:]=[120]*4
    departed.arrays['pnycar'][:]=[100]*4
    departed.v.update(mx=80,my=84,bonbeam=1,st=departed.v['s_walk'])
    departed.run('st_walk')
    assert departed.v['st']==departed.v['s_fall'] and departed.v['springfatal']==1, (
        'walking off a rotating panel loses the hazardous spring route')
    # Floor approaches must cross both pads. A drop directly from a moving
    # panel retains the dangerous route into the central rivet cabinet.
    for start,direction in ((80,1),(152,0)):
        for fatal in (0,1):
            spring=Basic(source);spring.v.update(lv=3);spring.run('init_level')
            spring.v.update(mx=start,my=160,springdir=direction,springphase=1,
                            springtick=0,springhit=0,springfatal=fatal,st=7)
            for _ in range(36):
                spring.run('spring_transfer')
                if spring.v['springhit']:break
            if fatal:
                assert spring.v['springhit']==1 and spring.v['st']==spring.v['s_dead'], (
                    'panel fall misses lethal cabinet',start)
                assert spring.v['mx']+16>=112 and spring.v['mx']<144
                # The cabinet is three rows tall: its top is y=160.
                assert spring.v['my']+16>=160 and spring.v['my']<184
            else:
                assert spring.v['springhit']==0 and spring.v['st']==7
                assert spring.v['mx']==(152 if direction else 80), ('spring misses far pad',start)
    # The factory's treads must travel in the same direction as its carrier.
    for level,direction in ((2,1),(3,-1)):
        vm.v.update(lv=level)
        for clock in range(16):
            vm.v['hzphase']=clock;vm.run('site_draw')
            expected=((-clock) if level==3 else clock//2)%8
            if level==3:
                vm.expect_upload(3336,8,'belt_anim0',expected*48+40)
                vm.expect_upload(3320,8,'belt_anim0',expected*48+24)
            else:
                for third in range(3):vm.expect_upload(third*2048+1248,32,'belt_anim0',expected*48)
    # Full game-over entry, stopped before the intentional timed/key wait.
    stop='\tGOSUB gameover_wait\n'
    assert source.count(stop)==1
    for y,moving in ((168,0),(72,0),(117,1)):
        end=Basic(source.replace(stop,'\tRETURN\n',1))
        end.v.update(lv=1);end.run('init_level')
        end.v.update(ely=y,emov=moving,carry=2,jhtk=1)
        if not moving:end.run('elev_back')
        end.run('mack_die');end.v['#fd']=40;end.run('dead_tick')
        # Model the last gameplay frame with both hammer sprites on screen.
        end.sprites[1]=(80,80,24,7)
        end.sprites[3]=(80,80,24,7)
        end.run('game_over')
        assert end.sprites[0][0]==209, 'game-over left Mack visible'
        assert all(v[0]==209 for k,v in end.sprites.items() if k!=0), (
            'game-over left a gameplay sprite visible')
        assert end.v['carry']==0 and end.v['jhtk']==0, 'game-over retained the held jackhammer'
        assert 'GOSUB elev_draw' not in source[source.index('game_over:\n'):source.index('gameover_wait:\n')], (
            'game-over must leave the character-backed cabin without reactivating elevator sprites')
    for stage in (1,2,3):
        end=Basic(source.replace(stop,'\tRETURN\n',1))
        end.v.update(lv=stage,levelno=stage,lives=0)
        end.run('init_level')
        if stage!=2:
            row=end.arrays['itr'][0];col=end.arrays['itc'][0]
            end.screen[row*32+col]=32
            end.arrays['itst'][0]=1
            end.v.update(carry=1,cidx=0)
        end.run('mack_die');end.v['#fd']=40;end.run('dead_tick')
        if stage!=2:
            assert end.screen[row*32+col]==32, (
                'last-life cleanup restored a loose box on Game Over',stage)
        before=end.screen[:]
        for slot in range(32):end.sprites[slot]=(80,80,24,7)
        end.run('game_over')
        message={row*32+col for row in (10,11,12) for col in range(10,21)}
        assert all(a==b for index,(a,b) in enumerate(zip(before,end.screen))
                   if index not in message), ('game-over wrote stray map characters',stage)
        assert all(end.sprites[slot][0]==209 for slot in range(32)), (
            'game-over retained an item or hazard sprite',stage)

    # A kill may not occur across empty space. Bounds are derived from the
    # editable BITMAP rows, with Mack's six-pixel torso/12-pixel height.
    def bounds(label, row_start=0, row_end=16):
        body=source.split(label+':',1)[1].split('\n\n',1)[0]
        rows=re.findall(r'BITMAP "([.X]+)"',body)
        assert len(rows)>=16 and all(len(r)==16 for r in rows)
        pixels=[(x,y) for y,row in enumerate(rows[:16]) for x,c in enumerate(row)
                if c=='X' and row_start<=y<row_end]
        return min(x for x,y in pixels),min(y for x,y in pixels),max(x for x,y in pixels),max(y for x,y in pixels)
    profiles=[]
    for level in (2,3):
        for phase in (0,12,24,36,47,63,95,127):
            test=Basic(source);test.v.update(lv=level);test.run('init_level')
            real_run=test.run; calls=[]
            def capture(label):
                if label=='mack_hit':
                    calls.append(tuple(test.v[k] for k in ('ex','ey','hbw','hbh')))
                    test.v['hit']=0
                else:real_run(label)
            test.run=capture
            test.v.update(mx=112,my=80,hzphase=phase-1,clawclock=(phase-1)%96,**{'#slagclock':(phase-1)%317})
            test.run('site_step')
            if level==2:
                assert len(calls)==(4 if phase<120 else 3), 'hidden slag still has a collision box'
                if phase<120:
                    profiles.append((calls[-1],(test.v['blobx'],test.v['bloby']),bounds('slag_bitmap'),'slag'))
                art=re.search(r'^claw_pat:\n.*?(?=^\w+:)',source,re.M|re.S).group()
                data=[int(n[1:],16) for n in re.findall(r'\$[0-9A-F]{2}',art)]
                frame=data[test.v['clawstep']*40:][:40]
                pixels=[(tile*8+x,y) for tile in range(5) for y in range(8)
                        for x in range(8) if frame[tile*8+y] & (128>>x)]
                for side in (0,1):
                    jaw=[(x,y) for x,y in pixels if (x>=20)==bool(side)]
                    rect=(min(x for x,y in jaw),min(y for x,y in jaw),
                          max(x for x,y in jaw),max(y for x,y in jaw))
                    profiles.append((calls[side],(32,128),rect,'pincer'))
    bolt=Basic(source);bolt.v.update(bolon=1,bon=1,bx=120,by=80,bvel=1,bph=1,bct=4)
    bolt.run('bolt_move')
    profiles.append((tuple(bolt.v[k] for k in ('ex','ey','hbw','hbh')),
                     (bolt.v['bx'],bolt.v['by']),bounds('bolt_bitmap'),'rivet'))
    for profile,(x,y),(left,top,right,bottom),name in profiles:
        hit=Basic(source);hit.v.update(ex=profile[0],ey=profile[1],hbw=profile[2],hbh=profile[3])
        for dx in range(-16,17):
            for dy in range(-20,21):
                hit.v.update(mx=x+dx,my=y+dy);hit.run('mack_hit')
                if hit.v['hit']:
                    assert dx+10>=left and dx+5<=right and dy+15>=top and dy+4<=bottom, (name,'invisible lethal margin',dx,dy)
        hit.v.update(mx=x+(left+right)//2-8,my=y+(top+bottom)//2-10)
        hit.run('mack_hit');assert hit.v['hit'], (name,'harmless at direct contact')
    # Both jaws move and both can kill; the open center and a clear jump are safe.
    for clock,x,y,dead in ((0,40,120,False),(48,44,120,True),
                           (0,27,120,True),(0,61,120,True),(48,44,109,False)):
        test=Basic(source);test.v.update(lv=2);test.run('init_level')
        test.v.update(clawclock=(clock-1)%96,mx=x,my=y,hzphase=90,**{'#slagclock':180})
        test.run('site_step')
        assert (test.v['st']==test.v['s_dead'])==dead, ('pincer contact',clock,x,y)


def speed_contract(source):
    # A two-second interval has the same budget with 1-, 2- or 4-frame passes.
    clock=source[source.index('\t#hacc = #hacc +'):source.index("\t' Read the stick")]
    for deltas in ([1]*120,[2]*60,[4]*30,[1,3]*30):
        vm=Basic(source+'\nBANK 0\nspeed_tick:\n'+clock+'\tRETURN\n');steps=0
        for delta in deltas:
            vm.v['#fd']=delta;vm.run('speed_tick');steps+=vm.v['#hd']
        assert steps==135 and vm.v['#hacc']==0, 'world speed depends on render rate'
    vm=Basic(source);vm.v.update(jr=1)
    for _ in range(20):vm.run('st_walk')
    assert vm.v['mx']==60, 'walking speed'
    vm.v.update(ely=160,elty=72,emov=1,eld=0)
    for _ in range(20):vm.run('elev_move')
    assert vm.v['ely']==140, 'elevator speed'
    vm.v.update(lv=2,bmy=150,bmon=1,bmactive=1,bmd=0)
    for _ in range(20):vm.run('beam_move')
    assert vm.v['bmy']==130, 'crane speed'
    vm.v.update(mgon=1,mgarm=1,mgx=160,mgd=0,mgtk=0)
    for _ in range(20):vm.run('mag_move')
    assert vm.v['mgx']==150, 'searching magnet speed'
    vm.v.update(st=8)
    for _ in range(20):vm.run('mag_move')
    assert vm.v['mgx']==130 and vm.v['mx']==130, 'loaded magnet speed'
    for level in (2,3):
        vm=Basic(source);vm.v.update(lv=level,rx=168 if level==2 else 200,ry=120 if level==2 else 88,rf=0,rp=0)
        for tick in range(20):vm.v['atg']=tick;vm.run('site_route')
        assert vm.v['rx']==(158 if level==2 else 190), 'enemy walk rate'
        vm.v.update(rp=1,ry=120 if level==2 else 88)
        for tick in range(20):vm.v['atg']=tick;vm.run('site_route')
        assert vm.v['ry']==(130 if level==2 else 98), 'enemy climb rate'
        vm=Basic(source);vm.v.update(lv=level);vm.run('init_level')
        vm.v.update(mx=44 if level==2 else 60,my=157 if level==2 else 58)
        start=vm.v['mx']
        for tick in range(20):vm.v['hzphase']=tick;vm.run('conv_sup')
        assert vm.v['mx']==start+(10 if level==2 else -20), 'belt speed'
    factory_belt_balance(source)
    vm=Basic(source);vm.v.update(lv=3);vm.run('init_level')
    vm.v.update(boxfall=1,boxy=128,mx=112,my=80)
    for _ in range(39):vm.run('factory_step')
    assert vm.v['boxy']==167 and vm.v['boxfall']==1, 'factory box drops too fast'
    vm.run('factory_step');assert vm.v['boxfall']==2
    for start,bounced in ((150,False),(156,False),(157,True)):
        vm=Basic(source);vm.v.update(bolon=1,bon=1,bx=120,by=start,bvel=1,bph=0,bnx=0)
        vm.run('bolt_move')
        assert (vm.v['bph']==1)==bounced, 'rivet bounces above the visible floor'


def factory_belt_balance(source):
    # Execute real walking plus belt support, at both clock parities. Right
    # input must cancel each individual tick, not merely average out later.
    for phase in (0,1):
        for direction,delta in ((1,0),(0,-1),(-1,-2)):
            vm=Basic(source);vm.v.update(lv=3);vm.run('init_level')
            vm.v.update(mx=78,my=58,jr=int(direction==1),jl=int(direction==-1))
            for tick in range(12):
                vm.v['hzphase']=(phase+tick)%128;vm.run('mack_step')
                assert vm.v['mx']==78+delta*(tick+1), 'factory belt fails walking balance'
                assert vm.v['st']==vm.v['s_walk'] and vm.v['my']==58, 'factory belt loses support'
            vm.run('site_draw')
            assert vm.v['cvaf']==(-vm.v['hzphase'])%8, 'factory tread rate differs from travel'
    vm=Basic(source);vm.v['lv']=3;vm.run('init_level')
    edge=vm.arrays['cvx1'][0]-8
    vm.v.update(mx=edge,my=58,jr=1)
    for tick in range(128):
        vm.v['hzphase']=tick;vm.run('mack_step')
        assert vm.v['mx']==edge and vm.v['st']==vm.v['s_walk'], 'right input escapes the factory roller'


def chain_and_pickups(source):
    for mode in ('walk','jump','fall'):
        vm=Basic(source);vm.v.update(lv=2);vm.run('init_level')
        # Reach the chain from its clear right-hand approach without Up held.
        vm.v.update(mx=228,my=168,jl=1)
        for _ in range(30):
            vm.run('mack_step')
            assert vm.v['st']!=vm.v['s_dead'], 'hazard blocks chain base'
        vm.v.update(jl=0,ju=1)
        if mode=='jump':
            vm.v.update(jbe=1,jb=1);vm.run('mack_step');vm.run('mack_step')
            assert vm.v['st']==vm.v['s_jump'], 'held Fire recatches chain'
            vm.v['jb']=0
        if mode=='fall':vm.v.update(st=vm.v['s_fall'],my=158,fcy=158,jhz=1)
        vm.run('mack_step')
        assert vm.v['st']==vm.v['s_climb'], 'Up failed to catch chain in '+mode
        for _ in range(55):
            vm.v['hzphase']=90;vm.run('mack_step');vm.run('site_step')
            assert vm.v['st']!=vm.v['s_dead'], 'chain ascent blocked'
            if vm.v['st']==vm.v['s_walk']:break
        assert vm.v['my']==120 and vm.v['st']==vm.v['s_walk'], 'cannot reach chain landing'
    vm=Basic(source);vm.v.update(lv=2);vm.run('init_level')
    assert vm.screen[22*32+10:22*32+12]==[162,163], 'pickup overwrites receiver support'
    assert vm.screen[22*32+19:22*32+21]==[vm.v['t_lboxl'],vm.v['t_lboxl']+1], 'hazard overwrites ground pail'
    vm.v.update(mx=120,my=168)
    before=vm.v['#score'];vm.run('mack_step')
    assert vm.v['#score']==before+40 and vm.arrays['itst'][7]==1, 'spray can not collectible'
    assert vm.screen[22*32+10:22*32+12]==[162,163], 'pickup erased receiver support'
    assert vm.screen[22*32+17:22*32+19]==[32,32], 'removed machine reappears after pickup'


def setup_inputs(source):
    def input_trace(keys):
        for key in keys:
            yield dict(input_key=15,input_button=0)
            for _ in range(3):yield dict(input_key=key,input_button=0)
    for lives in range(1,10):
        for level in range(1,7):
            vm=Basic(source);vm.v.update(input_key=15,lv=1,lives=2)
            vm.frame_inputs=iter([dict(input_key=15,input_button=0)]+list(input_trace([8,3,8,0,lives,9,0,level]))+[dict(input_key=15,input_button=0)]*50)
            vm.run('title_screen')
            actual=level if level<=3 else level-3
            assert vm.v['lives']==lives-1 and vm.v['lv']==actual and vm.v['levelno']==level and vm.bank==1, '838 selection / bank return'
            assert vm.v['game838']==1, '838 game not marked'
            assert (11*32+20,str(level)) in vm.prints, '838 level selection was not shown'
            vm.run('init_level')
            assert vm.screen[21:29]==[32]*(9-lives)+[vm.v['t_hat']]*(lives-1), 'top-row reserve hats wrong'
            if level==4:
                assert vm.v['lv']==1 and vm.v['von']==1 and vm.v['oon']==1, '838 level 4 does not start the harder two-enemy level 1'
    # Incorrect code, a held digit, and title navigation must not select a level.
    vm=Basic(source);vm.v.update(input_key=15,lv=1,lives=2)
    vm.frame_inputs=iter([dict(input_key=15,input_button=0)]+list(input_trace([8,5,3,8]))+[dict(input_button=1),{}])
    vm.run('title_screen')
    assert vm.v['lv']==1 and vm.v['lives']==2 and vm.bank==1 and vm.v['game838']==0
    vm=Basic(source);vm.v.update(titleheld=15,input_key=3)
    vm.bank=3;vm.run('menu_key');assert vm.v['setupkey']==3
    vm.bank=3;vm.run('menu_key');assert vm.v['setupkey']==15, 'held digit accepted twice'


def title_hotkeys(source):
    scanner=source[source.index('back_key:\n'):source.index('title_screen:\n')]
    for opcode in ('ASM LI R1,>1000','ASM LI R0,>0100',
                   'ASM LI R0,>0200','ASM LI R1,>0800',
                   'ASM MOVB R0,@cvb_BACKREQ','ASM LIMI 2'):
        assert opcode in scanner, ('TI REDO/BACK scanner lost its matrix guard',opcode)
    assert scanner.count('ASM LI R0,>0100')==2, 'TI BACK column or pressed flag changed'
    assert 'cont1.key = 254' not in scanner, 'bare FCTN triggers BACK'
    for key in (8,9):
        vm=Basic(source);vm.v.update(input_fctn=1,input_key=key)
        vm.run('back_key')
        assert vm.v['backreq']==1, ('TI FCTN+%d failed to return to title' % key)
        for prompt in ('setup_lives','setup_level'):
            vm=Basic(source);vm.bank=3;vm.v['titleheld']=15
            vm.frame_inputs=iter([dict(input_fctn=1,input_key=key)])
            vm.run(prompt)
            assert vm.v['title_abort']==1, ('838 prompt ignores REDO/BACK',prompt,key)
    vm=Basic(source);vm.v.update(input_fctn=0,input_key=8)
    vm.run('back_key')
    assert vm.v['backreq']==0, 'ordinary 8 should not leave gameplay'
    vm=Basic(source);vm.v.update(input_fctn=1,input_key=254)
    vm.run('back_key')
    assert vm.v['backreq']==0, 'bare FCTN/joystick direction must not leave gameplay'
    vm=Basic(source);vm.bank=3;vm.v['titleheld']=15
    vm.frame_inputs=iter([dict(input_key=2)]+[{}]*9+
                         [dict(input_fctn=1,input_key=9)])
    vm.run('setup_level')
    assert vm.v['title_abort']==1 and vm.wait_count==11, (
        '838 confirmation delay ignores BACK')


def repeat_enemies(source):
    # Execute the real completion transition, stopping before the frame loop.
    advance=source[source.index('\tlevelno = levelno + 1'):source.index('\ngame_over:')]
    advance=advance.replace('GOTO main_loop','RETURN')
    vm=Basic(source+'\nBANK 0\nadvance_fixture:\n'+advance)
    vm.v.update(lv=3,levelno=3,lives=2)
    vm.run('advance_fixture')
    assert (vm.v['lv'],vm.v['levelno'],vm.v['von'],vm.v['oon'])==(1,4,1,1), 'no extra enemy on second tour'
    for n in (1,2,3):
        vm=Basic(source);vm.v.update(lv=n,levelno=n);vm.run('init_level')
        assert vm.v['oon']==int(n==3) and (vm.v['vkind'],vm.v['okind'])==(0,1), 'first tour changed'
        for kinds in ((0,0),(0,1),(1,0),(1,1)):
            vm=Basic(source);vm.v.update(lv=n,levelno=n+3,lives=2)
            vm.random_values=iter(kinds);vm.run('init_level')
            assert vm.bank==1 and vm.v['von']==vm.v['oon']==1
            assert (vm.v['vkind'],vm.v['okind'])==kinds, 'enemy pair is not independently chosen'
            for frame in (0,1):
                vm.v['anm2']=frame;vm.run('enemy_draw')
                for slot,kind in zip((4,5),kinds):
                    assert vm.sprites[slot][2:]==((16,11) if kind else (36 if frame else 12,3)), 'wrong enemy type art'
                assert vm.bank==1, 'enemy drawing leaves bank selected'
            vm.v.update(mx=240,my=0,jhtk=1)
            seen=[set(),set()];previous=(vm.v['vx'],vm.v['vy'],vm.v['ox'],vm.v['oy'])
            for tick in range(2100 if n==1 else 850):
                vm.run('actors_step');vm.run('actors_move')
                now=tuple(vm.v[k] for k in ('vx','vy','ox','oy'))
                assert all(abs(a-b)<=1 for a,b in zip(previous,now)), 'enemy teleports'
                seen[0].add(now[1]);seen[1].add(now[3]);previous=now
                assert vm.bank==1, 'enemy movement leaves bank selected'
            required={24,56,88,120,152} if n==1 else ({120,168} if n==2 else {88,120})
            assert all(required<=ys for ys in seen), ('enemy stuck on one tier',n,seen)
            # Both actors remain lethal, regardless of chosen costume.
            for x,y in ((vm.v['vx'],vm.v['vy']),(vm.v['ox'],vm.v['oy'])):
                vm.v.update(mx=x,my=y,st=vm.v['s_walk']);vm.run('actors_move')
                assert vm.v['st']==vm.v['s_dead'], 'second enemy harmless'
            vm.v.update(dtm=0,**{'#fd':4});vm.run('dead_tick')
            assert (vm.v['ox'],vm.v['oy'],vm.v['opath'])==(vm.v['ox0'],vm.v['oy0'],0), 'second enemy does not reset on death'
            assert (vm.v['vkind'],vm.v['okind'])==kinds, 'death rerolled the pair'
            if n==1:assert (vm.v['ob'],vm.v['odr'])==(2,0)


def trampoline_animation(source):
    for entry in (5,9,13,17,21):
        vm=Basic(source);vm.v.update(lv=1,lives=2);vm.run('init_level')
        vm.v.update(my=entry*8-16,fcy=entry*8-16)
        vm.run('tramp_in2')
        target=168 if entry==5 else entry*8-32
        assert vm.v['trgy']==target and vm.v['mx']==vm.v['trx']
        for _ in range(100):
            vm.run('mack_step')
            if vm.v['trph']==3:break
        else:raise AssertionError('trampoline never compresses at impact')
        vm.run('site_draw')
        for depth in (1,2,3,4,3,2,1,0):
            vm.run('mack_step');vm.run('site_draw')
            assert vm.v['trpose']==depth, 'missing smooth compression/rebound'
            assert vm.v['my']+16==vm.v['trby']+depth, 'Mack detaches from spring cap'
            assert (137,2,'tramp_pat',depth*16) in vm.pattern_writes[-1:], 'wrong springboard frame'
            assert (137,2,'tramp_col',depth*16) in vm.color_writes[-1:], 'springboard colors stay behind'
            assert vm.bank==1, 'springboard leaves wrong cartridge bank'
        assert vm.v['trph']==1 and vm.sound[-1][0]==2, 'spring does not launch with sound'
        uploads=len(vm.pattern_writes)
        for _ in range(100):
            vm.run('mack_step');vm.run('site_draw')
            if vm.v['st']==vm.v['s_walk']:break
        assert vm.v['st']==vm.v['s_walk'] and vm.v['my']+16==target, 'spring delivers wrong floor'
        assert len(vm.pattern_writes)==uploads, 'idle trampoline uploads every frame'
    # Rendering remains synchronized when several world steps share one pass.
    for batch in (1,2,4):
        vm=Basic(source);vm.v.update(lv=1);vm.run('init_level')
        vm.v.update(st=vm.v['s_tramp'],trph=3,trtick=0,my=168,trpose=0)
        for elapsed in range(batch,9,batch):
            for _ in range(batch):vm.run('mack_step')
            vm.run('site_draw')
            expected=min(elapsed,8-elapsed)
            assert vm.v['my']==168+expected
            assert vm.pattern_writes[-1]==(137,2,'tramp_pat',expected*16)
    vm.v.update(st=vm.v['s_tramp'],trpose=4,trlast=4)
    vm.run('mack_die')
    vm.run('site_draw')
    assert vm.v['trpose']==4 and vm.v['trlast']==4, 'Level 1 spring resets during death'
    vm.v['#fd']=40;vm.run('dead_tick')
    assert vm.v['trpose']==0 and vm.pattern_writes[-1]==(137,2,'tramp_pat',0), (
        'Level 1 spring did not release after death')
    vm.run('init_level');vm.run('site_draw')
    assert vm.v['trlast']==0, 'new level misses initial spring pose'

    # Leaving a trampoline without reaching floor support must become a
    # fall; otherwise the leftward exit keeps decrementing byte-sized mx and
    # eventually wraps Mack to the far right while he remains alive.
    vm=Basic(source);vm.v.update(lv=1);vm.run('init_level')
    vm.v.update(trph=2,mx=8,my=168,st=vm.v['s_tramp'])
    for _ in range(9):
        vm.run('st_tramp')
        if vm.v['st']==vm.v['s_fall']:break
    assert vm.v['mx']==0 and vm.v['st']==vm.v['s_fall'] and vm.v['jhz']==1, (
        'unsupported trampoline exit must fall at the edge before x wraps')


def factory_spring_animation(source):
    for side in (0,1):
        for batch in (1,2,4):
            vm=Basic(source);vm.v.update(lv=3,lives=2);vm.run('init_level')
            assert vm.screen[22*32+10:22*32+12]==[139,140], 'left spring not two cells above ground'
            assert vm.screen[22*32+19:22*32+21]==[141,142], 'right spring overlaps drums or ground'
            assert vm.screen[23*32+10:23*32+12]==[133,133]
            assert vm.screen[23*32+19:23*32+21]==[133,133]
            # Facing the cabinet: the inward, floor-to-floor transfer.
            vm.v.update(mx=80 if side==0 else 152,my=160,mdir=1-side)
            vm.run('spring_begin');vm.run('site_draw')
            for elapsed in range(batch,9,batch):
                for _ in range(batch):vm.run('mack_step')
                vm.run('site_draw')
                assert vm.bank==1, 'factory spring leaks its code/graphics bank'
                tick=elapsed
                depth=min(tick,8-tick)
                active=side
                assert vm.v['my']==160+depth, 'factory rider detaches from cap'
                assert vm.v['mx']==(80 if active==0 else 152), 'factory rider drifts during compression'
                for pad in (0,1):
                    expect=depth if pad==active else 0
                    writes=[w for w in vm.pattern_writes if w[0]==139+pad*2]
                    colors=[w for w in vm.color_writes if w[0]==139+pad*2]
                    assert writes and colors, 'factory spring graphics never uploaded'
                    assert writes[-1]==(139+pad*2,2,'tramp_pat',expect*16), 'wrong factory pad or pose'
                    assert colors[-1]==(139+pad*2,2,'tramp_col',expect*16), 'factory pad colors do not follow cap'
            for _ in range(40):
                vm.run('mack_step')
                if vm.v['st']==vm.v['s_dead']:break
            assert vm.v['st']!=vm.v['s_dead'] and vm.v['springhit']==0, 'floor-to-floor factory arc hits cabinet'
            assert any(e[0]==2 and e[1]==300 for e in vm.sound), 'spring launch sound missing before death'
            vm.v.update(mx=80 if side==0 else 152,my=160,mdir=1-side,springfatal=1)
            vm.run('spring_begin')
            for _ in range(52):
                vm.run('mack_step')
                if vm.v['st']==vm.v['s_dead']:break
            assert vm.v['st']==vm.v['s_dead'] and vm.v['springhit']==1, 'panel fall should hit the central cabinet'
            assert any(e[0]==2 and e[1]==600 for e in vm.sound), 'cabinet collision misses death sound'
            count=len([w for w in vm.pattern_writes if w[0] in (139,141)])
            for _ in range(3):vm.run('site_draw')
            assert len([w for w in vm.pattern_writes if w[0] in (139,141)])==count, 'idle factory pads keep uploading'
            vm.v.update(st=7,trpose=4,springpad=side);vm.run('site_draw')
            active=(vm.v['trlast'],vm.v['trrightlast'])
            vm.run('mack_die');vm.run('site_draw')
            assert (vm.v['trlast'],vm.v['trrightlast'])==active, (
                'factory spring resets during death animation',side)
            vm.v['#fd']=40;vm.run('dead_tick')
            assert vm.v['trlast']==vm.v['trrightlast']==0, (
                'factory spring did not release after death',side)
    for x in (80,152):
        vm=Basic(source);vm.v.update(lv=3);vm.run('init_level')
        vm.v.update(mx=x,my=152,st=vm.v['s_fall']);vm.run('mack_step')
        assert vm.v['st']==7 and vm.v['my']==152, 'factory spring snaps a falling rider to the ground'
        for _ in range(4):vm.run('mack_step')
        assert vm.v['my']==160 and vm.v['trpose']==0, 'factory spring compresses before contact'
    for col in (10,11,19,20):
        vm=Basic(source);vm.v.update(lv=3);vm.run('init_level')
        vm.v.update(mx=col*8-8,my=160);vm.run('foot_probe')
        assert vm.v['sup']==1 and vm.v['ch']==vm.v['t_pad'], 'one spring half is not recognized as a pad'


PADDLE_EXITS=(('walk',0),('walk',1),('jump',0),('jump',1))


def paddle_bucket_bounce(source,exits=PADDLE_EXITS):
    # Leaving a rotating paddle sideways must never reverse Mack: the outer
    # pad carries him ON into that side's rivet bucket, where he dies. Walk
    # and jump off paddle 0 at every circuit phase in both directions; the
    # other three paddles share the same circuit. main() runs each exit
    # slice in its own worker, since the full sweep is ~900 simulated exits.
    base=Basic(source);base.v.update(lv=3,lives=2);base.run('init_level')
    screen=base.screen
    buckets=sorted(c for c in range(31) if screen[22*32+c:22*32+c+2]==[112,113])
    assert len(buckets)==2, ('expected one bucket per side', buckets)
    pads=[c for c in range(32) if base.v['t_pad']<=screen[22*32+c]<=base.v['t_pad_r']+1]
    assert len(pads)==4, ('expected two two-cell pads', pads)
    for col in buckets:
        assert base.v['t_solid0']<=screen[23*32+col]<=base.v['t_solid1'], 'bucket has no floor under it'
    ground=23*8
    beam_bottom={}
    for side,col in enumerate(buckets):
        rows=[r for r in range(22) if any(
            base.v['t_solid0']<=screen[r*32+c]<=base.v['t_solid1'] for c in (col,col+1))]
        beam_bottom[side]=max(rows)*8+7
    def outward_bucket(vm,d,path,what):
        # Mack's 12-px art (mx+2..mx+13) ends inside the bucket, feet on its floor.
        # (springhit is the shared death signal; position says where it struck.)
        left=buckets[d]*8
        assert vm.v['st']==vm.v['s_dead'], (what,'misses the bucket death',vm.v['mx'],vm.v['my'])
        assert left<=vm.v['mx']+2 and vm.v['mx']+13<=left+15, (what,'dies outside the bucket',vm.v['mx'])
        assert vm.v['my']+16==ground, (what,'does not reach the bucket floor',vm.v['my'])
        step=[b-a for a,b in zip(path,path[1:])]
        assert all((s<=0) if d==0 else (s>=0) for s in step), (what,'inverse movement',path)
    # An outward arrival already past the cap keeps its place: no snap back.
    for d,x in ((0,68),(1,167)):
        vm=Basic(source);vm.v.update(lv=3);vm.run('init_level')
        vm.v.update(mx=x,my=152,st=vm.v['s_fall'],mdir=d)
        vm.run('mack_step')
        assert vm.v['st']==7 and vm.v['mx']==x, ('outward pad snaps Mack backwards',d,vm.v['mx'])
        path=[x]
        for _ in range(60):
            vm.run('mack_step');path.append(vm.v['mx'])
            if vm.v['st']==vm.v['s_dead']:break
        outward_bucket(vm,d,path,('overshoot',d))
    reached={}
    for mode,d in exits:
        reached[mode,d]=0
        for phase in range(224):
            vm=copy.deepcopy(base)
            vm.v.update(pnphase=phase);vm.run('lift_positions')
            vm.v.update(mx=vm.arrays['pnxcar'][0],my=vm.arrays['pnycar'][0]-16,pnside=0,
                        bonbeam=1,st=vm.v['s_walk'],mdir=d,jl=1-d,jr=d,jbe=int(mode=='jump'))
            path=None;high=255
            for _ in range(300):
                for routine in ('mack_step','beam_move','site_step'):
                    before=vm.v['mx']
                    vm.run(routine);vm.v['jbe']=0
                    if path is None and vm.v['st']==7:
                        path=[before]
                    if path is not None:
                        path.append(vm.v['mx']);high=min(high,vm.v['my'])
                    if vm.v['st']==vm.v['s_dead']:break
                if vm.v['st']==vm.v['s_dead']:break
                # Landed on a girder or belt, not a pad: a different route.
                if vm.v['st']==vm.v['s_walk'] and vm.v['bonbeam']==0:break
            if path is None:continue
            reached[mode,d]+=1
            what=(mode,'right' if d else 'left',phase)
            assert vm.v['springdir']==d and vm.v['springpad']==d and vm.v['springbin']==1, (
                what,'paddle exit bounces back toward the cabinet')
            outward_bucket(vm,d,path,what)
            assert high+4>beam_bottom[d], (what,'bucket hop hits the beam above it',high)
    # Every combination must actually exercise the pads, or this sweep is blind.
    for key,count in reached.items():
        assert count>=40, ('too few paddle exits reach a pad',key,count)
    return reached


def gear_sparks(source):
    # Spark jets standing on the cabinet roof, firing up beside the BOTTOM
    # gear: nobody rides under the lift, the top pass stays safe, and a
    # spring crossing cuts their power both ways.
    base=Basic(source);base.v.update(lv=3,lives=2);base.run('init_level')
    screen=base.screen
    # Playfield rows only: this VM lower-cases PRINT text, so the row-0 HUD
    # holds ASCII 108-111 that the real TI prints in capitals.
    sparks=sorted((r,c) for r in range(1,24) for c in range(32) if 108<=screen[r*32+c]<=111)
    assert sparks==[(r,c) for r in (17,18,19) for c in (14,17)], ('spark cells moved',sparks)
    for c in (14,17):
        assert [screen[r*32+c] for r in (17,18,19)]==[108,109,110], 'jet is not top/middle/emitter'
    assert screen[19*32+15:19*32+17]==[32,32], 'something between the roof emitters'
    assert all(screen[r*32+c]==32 for r in (7,8,9) for c in (14,17)), 'top gear grew sparks'
    for r,first in ((20,96),(21,100),(22,104)):
        assert screen[r*32+14:r*32+18]==list(range(first,first+4)), ('cabinet rows/codes moved',r)
    # Lethal pixels come from the map; Mack's 12x12 art is mx+2..13, my+4..15.
    cells={(c*8+x,r*8+y) for r,c in sparks for x in range(8) for y in range(8)}
    def touching(x,y):
        return any((px,py) in cells for px in range(x+2,x+14) for py in range(y+4,y+16))
    s_dead,s_walk=base.v['s_dead'],base.v['s_walk']
    # Riders going down the left side die in the left jet, wherever they
    # stand: one on the paddle's outer edge only meets it once his paddle has
    # turned along the bottom, but none gets his paddle as far as the jet.
    # Every left-lane start converges on the same descent, so sweep stances
    # densely and starts coarsely.
    jet_x=min(px for px,py in cells)
    rides=[(60,stance) for stance in range(16)]+[(p,s) for p in range(0,80,8) for s in (0,7,15)]
    for phase,stance in rides:
        vm=copy.deepcopy(base)
        vm.v.update(pnphase=phase);vm.run('lift_positions')
        x,y=vm.arrays['pnxcar'][0],vm.arrays['pnycar'][0]
        vm.v.update(mx=x+stance-8,my=y-16,pnside=0,bonbeam=1,st=s_walk,jl=0,jr=0)
        for _ in range(200):
            vm.run('mack_step');vm.run('beam_move');vm.run('site_step')
            if vm.v['st']==s_dead:break
            assert not (vm.arrays['pnycar'][0]==144 and vm.arrays['pnxcar'][0]>=jet_x), (
                'rider rides under the gear',phase,stance)
        assert vm.v['st']==s_dead and touching(vm.v['mx'],vm.v['my']), (
            'rider not killed by the gear sparks',phase,stance,vm.v['mx'],vm.v['my'])
    # Riding over the top, from the right lane round into the left lane, is safe.
    for stance in (0,7,15):
        vm=copy.deepcopy(base)
        vm.v.update(pnphase=150);vm.run('lift_positions')
        x,y=vm.arrays['pnxcar'][0],vm.arrays['pnycar'][0]
        vm.v.update(mx=x+stance-8,my=y-16,pnside=0,bonbeam=1,st=s_walk,jl=0,jr=0)
        topped=False
        for _ in range(100):
            vm.run('mack_step');vm.run('beam_move');vm.run('site_step')
            topped|=vm.arrays['pnycar'][0]==64
            assert vm.v['st']!=s_dead and vm.v['bonbeam']==1, ('top pass is not safe',stance)
        assert topped
    # The left side is not a trap: from a descending paddle, a jump right
    # still reaches a climbing right-lane paddle across a broad window.
    crossings=0
    for phase in range(0,72,8):
        vm=copy.deepcopy(base)
        vm.v.update(pnphase=phase);vm.run('lift_positions')
        x,y=vm.arrays['pnxcar'][0],vm.arrays['pnycar'][0]
        vm.v.update(mx=x,my=y-16,pnside=0,bonbeam=1,st=s_walk,jbe=1,jr=1,jl=0,mdir=1)
        for _ in range(120):
            vm.run('mack_step');vm.v['jbe']=0;vm.run('beam_move');vm.run('site_step')
            if vm.v['st']==s_dead:break
            if vm.v['bonbeam'] and vm.v['pnside']!=0 and vm.v['st']==s_walk:
                crossings+=vm.arrays['pnxcar'][vm.v['pnside']]>=120;break
    assert crossings>=5, ('left lane can no longer jump to the climbing lane',crossings)
    # Spring crossings both ways: the first pad cuts the power, the far pad
    # restores it, and the flight really does pass through the spark cells.
    for side in (0,1):
        vm=copy.deepcopy(base)
        vm.v.update(mx=80 if side==0 else 152,my=160,mdir=1-side)
        assert vm.v['gearoff']==0
        vm.run('spring_begin')
        assert vm.v['gearoff']==1, ('first trampoline leaves the sparks live',side)
        path=[];restored=None
        for step in range(120):
            vm.run('mack_step');vm.run('site_step')
            assert vm.v['st']!=s_dead, ('spring crossing dies',side,vm.v['mx'],vm.v['my'])
            path.append((vm.v['mx'],vm.v['my']))
            if restored is None and vm.v['gearoff']==0:
                restored=(vm.v['mx'],vm.v['my'])
                assert vm.v['springphase']==2, 'power back before the far pad'
            if vm.v['st']==s_walk:break
        assert restored and restored[0]==(152 if side==0 else 80), ('power not restored at the far pad',side,restored)
        assert not touching(*restored), 'power restored with Mack inside the sparks'
        assert vm.v['st']==s_walk, ('second bounce never lands',side,vm.v['st'])
        assert any(touching(x,y) for x,y in path), 'crossing misses the sparks: power cut is not load-bearing'
    # Anyone touching live sparks dies, not only riders: a plain fall.
    vm=copy.deepcopy(base)
    vm.arrays['pnxcar'][:]=[0]*4;vm.arrays['pnycar'][:]=[0]*4
    vm.v.update(mx=100,my=96,st=base.v['s_fall'],jhz=1,fct=0,fcy=96)
    for _ in range(60):
        vm.run('mack_step');vm.run('site_step')
        if vm.v['st']==s_dead:break
    assert vm.v['st']==s_dead and touching(vm.v['mx'],vm.v['my']) and vm.v['my']<130, (
        'falling into live sparks is harmless',vm.v['my'])
    # The shorter cabinet still swallows a faller -- at its new top.
    vm=copy.deepcopy(base)
    vm.arrays['pnxcar'][:]=[0]*4;vm.arrays['pnycar'][:]=[0]*4
    vm.v.update(mx=120,my=120,st=base.v['s_fall'],jhz=1,fct=0,fcy=120)
    for _ in range(60):
        vm.run('mack_step');vm.run('site_step')
        if vm.v['st']==s_dead:break
    assert vm.v['st']==s_dead and not touching(vm.v['mx'],vm.v['my']), 'cabinet faller hit by sparks'
    assert vm.v['my']>=148, ('cabinet kills above its new top',vm.v['my'])
    # Drawing: bottom third only, live poses follow the clock, cold when off.
    vm=copy.deepcopy(base);vm.run('site_draw')
    for phase in range(16):
        vm.v['hzphase']=phase;vm.run('site_draw')
        vm.expect_upload(4960,24,'gearspark_pat',(phase//2&7)*24)
        vm.expect_upload(13152,24,'gearspark_col',0)
        assert vm.bank==1, 'gear spark drawing leaks its bank'
    vm.v['gearoff']=1;vm.run('site_draw')
    vm.expect_upload(4960,24,'gearspark_pat',192);vm.expect_upload(13152,24,'gearspark_col',24)
    vm.v['gearoff']=0;vm.run('site_draw')
    vm.expect_upload(13152,24,'gearspark_col',0)
    assert not any(vm.vram.get(a,('',0))[0].startswith('gearspark') for third in (0,2048)
                   for a in range(third+864,third+888)), 'gear sparks drawn outside the bottom third'
    # Every reset restores the power: death cleanup and a fresh level.
    vm=copy.deepcopy(base);vm.v['gearoff']=1;vm.run('death_cleanup')
    assert vm.v['gearoff']==0 and vm.bank==1, 'death leaves the gear sparks off'
    vm=copy.deepcopy(base);vm.v.update(gearoff=1,gearlast=3);vm.run('init_level')
    assert vm.v['gearoff']==0 and vm.v['gearlast']==255, 'new level keeps stale gear spark state'


def fixture_contract(source):
    def table(label):
        body=re.search(r'^'+label+r':\n.*?(?=^\w+:)',source,re.M|re.S).group()
        return [int(v[1:],16) for v in re.findall(r'\$[0-9A-F]{2}',body)]
    ownership=Basic(source)
    # Site-specific codes must survive successive sites and death redraws.
    for level in (1,2,3,1):
        ownership.v['lv']=level;ownership.run('init_level')
        if level!=2:
            pattern={1:'support_pat',3:'eject_pat'}[level]
            assert [w for w in ownership.pattern_writes if w[0]==120][-1]==(120,2,pattern,0), 'wrong site scenery after level change'
        if level==1:
            launcher=[ownership.screen[r*32+28:r*32+30] for r in (3,4)]
            assert launcher==[[232,233],[234,235]], 'upper-right rivet launcher artwork is missing or displaced'
            ownership.v.update(bon=0,btm=1)
            ownership.run('bolt_move')
            assert (ownership.v['bx'],ownership.v['by'])==(216,27), 'rivet does not leave the fixed launcher mouth'
            for column in (6,14,23):
                assert ownership.screen[22*32+column]==120
                assert ownership.screen[23*32+column]==121, 'pedestal repeats its top instead of a single footing'
    for count,pointer in re.findall(r'DEFINE SPRITE \d+,([0-9]+),(\w+)',source.split('new_game:')[0]):
        assert ownership.label_banks[pointer]==1, ('startup sprite outside bank 1',pointer)
    assert ownership.label_banks['drill_route']==1, 'startup route outside bank 1'
    ownership.run('game_chars')
    credit_source=source.replace('title_release:\n','title_release:\n\tRETURN\n',1)
    credit=Basic(credit_source);credit.bank=3;credit.run('banked_title')
    for ch,off in ((97,0),(100,8),(110,16)):
        assert (ch,1,'credit_pat',off) in credit.pattern_writes, 'scenery corrupts title credit'
        assert (ch,1,'credit_col',0) in credit.color_writes, 'title credit has scenery colors'
    pats,cols=table('tile_pat'),table('tile_col')
    assert pats[24:32]==table('item_pat')[:8] and cols[24:32]==table('item_col')[:8], 'placed block changes appearance'
    assert pats[32:40]==pats[:8] and cols[32:40]==cols[:8], 'riveted block differs from girder'
    for off in (0,8,16):
        assert [i for i,v in enumerate(table('girder_dot_pat')[off:off+8]) if v==231]==[3,4], 'rivets above girder center'
        assert 231 not in pats[off:off+8], 'plain girder still has rivets'
    assert cols[8:16]==[0x41,0x31,0x31,0x34,0x34,0x31,0x31,0x41], 'green/blue girder palette'
    for offset in range(8):
        shifted=table('beamshift_col')[offset*8:offset*8+8]+table('beamshift_col')[64+offset*8:72+offset*8]
        assert shifted[offset:offset+8]==cols[8:16], 'crane palette differs from fixed girders'
    for half in (0,1):
        vm=Basic(source);vm.v['lv']=2;vm.run('init_level')
        for i in range(6):
            row,col=vm.arrays['itr'][i],vm.arrays['itc'][i]
            assert vm.screen[(row-1)*32+col:(row-1)*32+col+2]==[118,119], 'missing pail handle row'
            vm.v.update(mx=(col+half)*8-8,my=row*8-8,ch=vm.v['t_lboxl']+half)
            vm.run('take_item')
            assert vm.arrays['itst'][i]==1, 'pail half cannot be collected'
            for r in (row-1,row):assert vm.screen[r*32+col:r*32+col+2]==[32,32], 'pail fragment left after pickup'
            assert vm.screen[(row+1)*32+col] in (129,133,134), 'pickup erases girder'
    vm=Basic(source);vm.v['lv']=2;vm.run('init_level')
    assert all(vm.screen[r*32+26]==152 for r in range(18,22)), 'chain not at platform edge'
    assert all(vm.screen[r*32+c]==32 for r in range(18,23) for c in (24,25)), 'removed pump blocks chain approach'
    assert vm.screen[22*32+19:22*32+23]==[183,184,32,166], 'dynamite crowds the ground pail or moved from column 22'
    assert vm.screen[21*32+22]==165, 'sparking fuse is not above the dynamite stick'
    for phase,character in ((0,165),(4,169),(8,170),(12,171)):
        vm.v['hzphase']=phase;vm.run('site_draw')
        assert vm.screen[21*32+22]==character and vm.screen[22*32+22]==166, (
            'dynamite fuse does not spark over its stationary stick',phase)
        vm.vram_writes.clear();vm.run('site_draw')
        assert vm.screen[21*32+22]==character, 'unchanged fuse phase drifts'
    for beam in (160,156,120):
        vm.v.update(bmy=beam,bmd=0);vm.vram_writes.clear();vm.run('fixture_draw')
        assert not vm.vram_writes, 'removed pump still animates'
    assert 'beat_pat:' not in source and 'beat_col:' not in source, 'unused pump frames retained'
    vm=Basic(source);vm.v['lv']=3;vm.run('init_level')
    assert vm.screen[4*32+10:4*32+12]==[186,32], 'top wrench did not move one cell left'
    vm.v.update(mx=72,my=24,ch=vm.v['t_wrench'])
    before=vm.v['#score'];vm.run('take_item')
    assert vm.v['#score']==before+40 and vm.screen[4*32+10]==32, 'shifted wrench cannot be claimed'
    for side in (0,1):
        vm=Basic(source);vm.v['lv']=3;vm.run('init_level')
        for row in (7,17):
            assert vm.screen[row*32+15:row*32+17]==[114,115], 'missing rounded axle'
            assert vm.screen[(row+1)*32+15:(row+1)*32+17]==[116,117], 'partial axle'
        for c in (8,21):assert vm.screen[22*32+c:22*32+c+2]==[112,113], 'bucket is two repeated cans'
        for c in (4,25):
            assert vm.screen[19*32+c:19*32+c+2]==[124,125], 'IN not above processor'
            assert vm.screen[20*32+c:20*32+c+2]==[126,127], 'missing down arrow'
        vm.v['hzphase']=0;vm.run('fixture_draw');vm.v['hzphase']=32;vm.run('fixture_draw')
        assert vm.pattern_writes[-2:]==[(124,4,'inflash_pat',0),(124,4,'inflash_pat',32)], 'IN does not flash'
        assert not any(table('inflash_pat')[32:]), 'IN dark phase still visible'
        vm.v.update(carry=1,cidx=0,mx=24 if side==0 else 208,my=120,nbox=1)
        vm.run('deliver_zone')
        before=vm.v['#score'];vm.v.update(mx=208 if side==0 else 24,my=80)
        for _ in range(40):vm.run('factory_step')
        assert vm.v['nbox']==0 and vm.v['boxfall']==2 and not vm.v['lvdone'], 'last box skips processing'
        for _ in range(10):vm.run('factory_step')
        assert vm.v['boxfall']==3,'processor never ejects rivet'
        portcol=7 if side==0 else 24
        assert vm.screen[21*32+portcol]==120+side, 'processor has no bucket-facing outlet'
        lower=219 if side==0 else 215
        assert vm.screen[22*32+portcol]==lower, 'outlet is detached from lower housing'
        pp,pc=table('eject_pat'),table('eject_col')
        mp,mc=table('machine_art'),table('machine_col')
        def machine_tile(ch):
            if ch in (120,121):
                i=(ch-120)*8
                return pp[i:i+8],pc[i:i+8]
            assert 210<=ch<=219, 'missing processor housing tile'
            i=(ch-210)*8
            return mp[i:i+8],mc[i:i+8]
        for row in (21,22):
            for col in range(5):
                assert machine_tile(vm.screen[row*32+3+col])==machine_tile(vm.screen[row*32+24+col]), 'processors are not visually identical'
        def port_ink(x,y):
            x-=portcol*8;y-=168
            assert 0<=x<8 and 0<=y<16, 'rivet starts outside its outlet'
            if y>=8:
                i=(lower-210)*8+y-8
                return mc[i]//16 if mp[i] & (128>>x) else mc[i]%16
            i=side*8+y
            return pc[i]//16 if pp[i] & (128>>x) else pc[i]%16
        art=re.search(r'^bolt_bitmap:\n(.*?)(?=^\w+:)',source,re.M|re.S)[1]
        bolt=re.findall(r'BITMAP "([.X]+)"',art)
        for y,row in enumerate(bolt):
            for x,pixel in enumerate(row):
                if pixel=='X':
                    assert port_ink(vm.v['boxx']+x,vm.v['boxy']+y)==1, 'rivet appears on the casing instead of in the dark outlet'
        # A solid lower lip and attachment edge distinguish an actual nozzle
        # from empty black space coincidentally under the initial sprite.
        lip=range(2,5) if side==0 else range(3,6)
        assert all(port_ink(portcol*8+x,177)==15 for x in lip), 'outlet has no lower lip'
        for x,y in ((1,4),(1,5),(0,6),(0,7),(1,8)):
            assert port_ink(portcol*8+(x if side==0 else 7-x),168+y)==15, 'angled outlet rim is broken'
        path=[]
        for _ in range(15):
            vm.run('factory_step');vm.run('site_draw')
            path.append((vm.v['boxx'],vm.v['boxy']))
            assert vm.sprites[15][2]==20, 'output is still a box'
            assert vm.bank==1, 'output bank not restored'
        assert all((b[0]-a[0])==(1 if side==0 else -1) for a,b in zip(path,path[1:])), 'rivet flies away from bucket'
        assert [y for x,y in path[:8]]==list(range(167,159,-1)), 'rivet does not leave the angled mouth diagonally'
        x,y=path[-1];bucketleft=64 if side==0 else 168
        assert bucketleft<=x+6<=x+8<bucketleft+16 and 176<=y+4<=y+8<184, 'rivet misses bucket'
        vm.run('factory_step');assert vm.v['boxfall']==0 and vm.v['lvdone']==1
        assert vm.v['#score']==before+5, 'processor awards delivery twice'


def data_cache_contract(source):
    shifted=source.replace('DATA BYTE 5,13, 21,25','DATA BYTE 5,13, 21,24')
    assert shifted!=source
    # A mutation must not inherit the previous cart's level data, and restoring
    # the original source must restore its spawn rather than retain the mutation.
    for text,x in ((source,196),(shifted,188),(source,196)):
        vm=Basic(text);vm.v['lv']=1;vm.run('init_level')
        assert vm.v['mx']==x, 'cached DATA leaked between source variants'


def bank_call_safety(source):
    bank=0
    for raw in ti_source_lines(source):
        line=raw.split("'")[0].strip().lower()
        if re.fullmatch(r'bank [1-6]',line):bank=int(line[-1])
        if bank and line.startswith('bank select '):
            raise AssertionError('banked TI caller switches cartridge page before its return')
    hud=source[source.index('hud_all:\n'):source.index('hud_lives:\n')]
    assert hud.index('BANK SELECT 2')<hud.index('GOSUB banked_hud_all')<hud.index('BANK SELECT 1')<hud.index('GOSUB score_print'), (
        'HUD score call no longer returns through fixed ROM')


def optimized_rendering(source):
    # Every paddle, every phase, including the three wraparound tails.
    vm=Basic(source)
    for phase in range(224):
        vm.v['pnphase']=phase;vm.run('lift_positions')
        for i in range(4):
            p=(phase+i*56)%224
            x=104 if p<80 else (p+24 if p<112 else (136 if p<192 else 328-p))
            y=64+p if p<80 else (144 if p<112 else (256-p if p<192 else 64))
            assert (vm.arrays['pnxcar'][i],vm.arrays['pnycar'][i])==(x,y), 'paddle lookup changed route'
        assert vm.bank==1, 'motion bank not restored'
    # Measure real transferred bytes; source-line counts miss triple copies.
    for level,limit in ((2,328),(3,312)):
        vm=Basic(source);vm.v['lv']=level;vm.run('init_level');vm.run('site_draw')
        for phase in range(1,128):
            vm.v.update(mx=112,my=80,hzphase=phase-1,pnphase=phase,st=0)
            vm.run('site_step');vm.vram_writes.clear();vm.run('site_draw')
            # The new wall sparks have a separate, fixed 16-byte allowance;
            # retain the existing budget for all previously optimized art.
            sparkbytes=sum(w[1] for w in vm.vram_writes if w[0]==3360) if level==3 else 0
            assert sparkbytes<=16, 'spark animation exceeds two cells'
            # The bottom gear's three spark-jet cells likewise: one 24-byte
            # pose, never its colours as well while the power is unchanged.
            gearbytes=sum(w[1] for w in vm.vram_writes if w[0] in (4960,13152)) if level==3 else 0
            assert gearbytes<=24, 'gear spark animation exceeds its three cells'
            assert sum(w[1] for w in vm.vram_writes)-sparkbytes-gearbytes<=limit, ('excess dynamic VRAM traffic',level,phase)
            if level==3:
                for third in (1,2):
                    for color,label in ((0,'drivechain_pat'),(8192,'drivechain_col')):
                        vm.expect_upload(color+third*2048+1664,16,label,phase%8*16)
                vm.expect_upload(5088,32,'inflash_pat',(phase//32%2)*32)
            else:
                vm.expect_upload(6000,40,'claw_pat',vm.v['clawstep']*40)
                assert not any(w[0] in (5056,13248) for w in vm.vram_writes), 'removed pump still uploads'
    # Spring art appears only in the bottom third on both sites.
    for level,codes in ((1,(137,)),(3,(139,141))):
        vm=Basic(source);vm.v['lv']=level;vm.run('init_level');vm.run('site_draw')
        for code in codes:
            vm.expect_upload(4096+code*8,16,'tramp_pat',0)
            vm.expect_upload(12288+code*8,16,'tramp_col',0)


def wall_sparks(source):
    vm=Basic(source);vm.v['lv']=3;vm.run('init_level')
    assert vm.screen[8*32+2:8*32+4]==[164,165], 'wall emitter halves repeat'
    for clock in range(32):
        vm.v['hzphase']=clock;vm.run('site_draw')
        vm.expect_upload(3360,16,'spark_pat',(clock//2%8)*16)
        vm.expect_upload(11552,16,'spark_col',0)
        vm.vram_writes.clear();vm.run('site_draw')
        assert not any(w[0]==3360 for w in vm.vram_writes), 'unchanged sparks reuploaded'
    # Both halves remain the dangerous belt endpoint, with the escape chain clear.
    for x in (20,28,33):
        vm.v.update(mx=x-8,my=58,jr=0,jl=0,st=vm.v['s_walk'])
        vm.run('mack_step')
        assert (vm.v['st']==vm.v['s_dead'])==(x<32), 'spark endpoint collision moved'
    vm.v['lv']=2;vm.run('init_level');vm.run('site_draw')
    vm.expect_upload(3360,16,'haz_pat',0)
    vm.expect_upload(11552,16,'haz_col',0)


def furnace_contract(source):
    vm=Basic(source);vm.v['lv']=2;vm.run('init_level')
    assert all(128<=vm.screen[6*32+c]<=151 for c in (28,29)), 'furnace only half supported'
    assert vm.screen[6*32+28:6*32+30]==[vm.v['t_girdr']]*2, 'furnace support missing centered rivets'
    assert vm.screen[4*32+28:4*32+30]==[120,121], 'furnace upper halves duplicated'
    assert vm.screen[5*32+28:5*32+30]==[122,123], 'furnace lower halves duplicated'
    assert vm.screen[3*32+26:3*32+28]==[124,125]
    assert vm.screen[4*32+26:4*32+28]==[126,127]
    table=re.search(r'^fire_pat:\n.*?(?=^\w+:)',source,re.M|re.S)[0]
    art=[int(n[1:],16) for n in re.findall(r'\$[0-9A-F]{2}',table)]
    assert len(art)==17*32
    color_table=re.search(r'^fire_col:\n.*?(?=^\w+:)',source,re.M|re.S)[0]
    color_art=[int(n[1:],16) for n in re.findall(r'\$[0-9A-F]{2}',color_table)]
    assert len(color_art)==4*32, 'flame color cycle must contain four palettes'
    assert len({tuple(color_art[i:i+32]) for i in range(0,len(color_art),32)})==4, 'flame colors do not cycle'
    assert {7,9,10}<={color>>4 for color in color_art}, 'flame needs multiple red tones'
    red_bands=[color_art[p*32+row*8:p*32+(row+1)*8] for p in range(4) for row in range(4)]
    assert all(sum((color>>4) in (7,9,10) for color in band)>=4 for band in red_bands), \
        'flame palette needs at least half red shades in every band'
    depths=[]
    for phase in range(128):
        vm.v.update(mx=112,my=80,hzphase=phase-1,st=0)
        vm.run('site_step');vm.run('site_draw');depth=vm.v['firedepth'];depths.append(depth)
        color=(phase//8)&3
        assert vm.v['firecolor']==color, 'flame palette cycle timing changed'
        vm.expect_upload(9184,32,'fire_col',color*32)
        expected=min(phase%64//2,32-phase%64//2)
        assert depth==expected, 'furnace no longer extends and retracts smoothly'
        vm.expect_upload(992,32,'fire_pat',depth*32)
        vm.expect_upload(960,32,'furnace_pat',0)
        frame=art[depth*32:depth*32+32]
        pixels={(x+208,y+24) for y in range(16) for x in range(16)
                if frame[(y//8*2+x//8)*8+y%8] & (128>>(x%8))}
        assert {x for x,y in pixels}==set(range(224-depth,224)), 'fire does not emerge leftward'
        if depth >= 8:
            column_heights=[len({y for px,y in pixels if px==x}) for x in range(224-depth,224)]
            assert max(column_heights)>=7 and min(column_heights)<=3, 'flame is a thin uniform streak'
            assert len(set(column_heights))>=4, 'flame outline is not turbulent'
        if phase%8==0:
            for x in (200,208,215,220,228):
                for y in (14,20,24,32,40,48):
                    dead=any(x+5<=px<=x+10 and y+4<=py<=y+15 for px,py in pixels)
                    dead=dead or (x+10>=225 and x+5<=238 and y+4<=47 and y+15>=34)
                    vm.v.update(mx=x,my=y,hzphase=phase,st=0);vm.run('furnace_step')
                    assert (vm.v['st']==vm.v['s_dead'])==dead, 'invisible curved-flame collision'
    assert depths[:64]==depths[64:], 'furnace cycle drifts'
    vm=Basic(source);vm.v.update(lv=2,lives=2);vm.run('init_level')
    vm.v.update(mx=220,my=32,hzphase=20,st=vm.v['s_walk'])
    vm.run('furnace_step')
    assert vm.v['st']==vm.v['s_dead'] and vm.v['burnfall']==1, 'furnace skips ignition'
    ground_ticks=0
    for frame in range(1,65):
        vm.v.update(frame=frame,**{'#fd':1});vm.run('dead_tick')
        if vm.v['burnfall'] and vm.v['my']==168:
            assert vm.sprites[0][0]==167, 'burning Mack was drawn through the floor'
            ground_ticks+=1
        if vm.v['burnfall']==0:break
    assert ground_ticks>=12 and vm.v['burnfall']==0, 'burning Mack did not pause on the ground'
    assert vm.v['lives']==1 and vm.v['st']==vm.v['s_walk'], 'burning death did not consume one life'


def main():
    source = SOURCE.read_text(encoding='utf-8')
    # The paddle-exit sweep is the longest single check. Its four slices run
    # in workers while the serial checks below proceed in this process.
    sweep_pool = ProcessPoolExecutor(max_workers=len(PADDLE_EXITS))
    bucket_jobs = [sweep_pool.submit(paddle_bucket_bounce, source, (key,))
                   for key in PADDLE_EXITS]
    data_cache_contract(source)
    bank_call_safety(source)
    optimized_rendering(source)
    furnace_contract(source)
    wall_sparks(source)
    windows = clear_windows(source)
    momentum(source)
    clock_contract(source)
    inventory_contract(source)
    hammer_release(source)
    single_item(source)
    machinery(source)
    transfers(source)
    sound_contract(source)
    pincer_passage(source)
    crane_contact(source)
    machinery_animation(source)
    chain_and_pickups(source)
    setup_inputs(source)
    title_hotkeys(source)
    repeat_enemies(source)
    factory_challenge(source)
    upper_conveyor(source)
    title_scores(source)
    score_range(source)
    mack_animation(source)
    elevator_dance(source)
    elevator_boarding(source)
    end_screen_timing(source)
    victory_scene(source)
    death_timing(source)
    girder_spacing(source)
    factory_drive(source)
    work_sounds(source)
    trampoline_animation(source)
    factory_spring_animation(source)
    gear_sparks(source)
    fixture_contract(source)
    slag_cadence(source)
    fidelity(source)
    visual_hazards(source)
    speed_contract(source)
    entry_wins=review_feedback(source)
    for state in ('s_climb', 's_ride'):
        vm = Basic(source)
        vm.v.update(st=vm.v[state], jbe=1, jr=1)
        vm.run('mack_step')
        assert vm.v['st'] == vm.v['s_jump'] and vm.v['jbe'] == 0
    for direction, expected in [(0, 8), (1, 40), (2, 72)]:
        vm, path = jump(source, direction)
        assert len(path) == 32 and min(y for x, y in path) == 141
        assert vm.v['mx'] == expected and vm.v['my'] == 152
    # Sweep jumps across a real one-cell floor opening from both lips.
    for direction in (0, 2):
        for x in range(56, 64) if direction == 2 else range(72, 80):
            vm = Basic(source, holes=(9,))
            vm.v.update(mx=x, jbe=1, jr=int(direction == 2), jl=int(direction == 0))
            vm.run('mack_step')
            for _ in range(32):
                vm.run('mack_step')
            assert vm.v['st'] == vm.v['s_walk'], 'jump failed to clear single-cell gap'
    # Known defects MUST fail: short clearance, lost momentum, deferred death.
    mutants = [
        (source.replace('banked_hud_all:\n','banked_hud_all:\n\tBANK SELECT 3\n',1),bank_call_safety),
        (source.replace('DATA BYTE 8, 23,6,1,121','DATA BYTE 8, 23,6,1,120'),fixture_contract),
        (source.replace('DATA BYTE 8, 21,22,1,165','DATA BYTE 8, 21,21,1,165'),fixture_contract),
        (source.replace('DATA BYTE 8, 22,22,1,166','DATA BYTE 8, 22,21,1,166'),fixture_contract),
        (source.replace('fusepose = (hzphase / 4) AND 3','fusepose = 0'),fixture_contract),
        (source.replace('DATA BYTE 5,4,1, 4,10','DATA BYTE 5,4,1, 4,11'),fixture_contract),
        (source.replace("' Clear floor approach to the chain; the decorative pump is removed.", 'DATA BYTE 8, 21,24,1,120'),fixture_contract),
        (source.replace('chainpose = pnphase AND 7','chainpose = hzphase AND 7'),factory_drive),
        (source.replace('drivepose = (pnphase / 4) AND 7','drivepose = 0'),factory_drive),
        (source.replace('VARPTR drivechain_col(chainpose * 16)','VARPTR drivechain_col(0)'),factory_drive),
        (source.replace('SOUND 1,#workpitch,workvol','SOUND 1,#workpitch,0'),work_sounds),
        (source.replace('#elevpitch = 351 + (ely - elty) * 7',
                        '#elevpitch = 1100 - (ely - elty) * 5'),work_sounds),
        (source.replace('IF (ely AND 7) = 0 THEN','IF (ely AND 15) = 0 THEN'),work_sounds),
        (source.replace('IF workfx = 4 THEN GOSUB work_sound','workfx = 255'),work_sounds),
        (source.replace("DEFINE CHAR 97,1,credit_pat","DEFINE CHAR 98,1,credit_pat"),fixture_contract),
        (source.replace("\tDEFINE CHAR 210,10,machine_art","\tDEFINE CHAR 210,10,steel_bitmap"),fixture_contract),
        (source.replace('IF (clawclock AND 15) = 15 THEN clawclock = clawclock + 1','clawclock = clawclock'),machinery_animation),
        (source.replace('ch = 118','ch = T_VOID'),fixture_contract),
        (source.replace('IF ch = T_LBOXR THEN c2 = c2 - 1','c2 = c2'),fixture_contract),
        (source.replace('fixturepose = (hzphase / 32) AND 1','fixturepose = 0'),fixture_contract),
        (source.replace('IF outputside = 1 THEN boxx = 189','IF outputside = 1 THEN boxx = 192'),fixture_contract),
        (source.replace('boxy = 168','boxy = 163'),fixture_contract),
        (source.replace('IF outputtick <= 8 THEN\n\t\tboxy = boxy - 1','IF outputtick <= 8 THEN\n\t\tboxy = boxy'),fixture_contract),
        (source.replace('21,7,1,120','21,7,1,32'),fixture_contract),

        (source.replace('DATA BYTE 8, 22,10,1,139','DATA BYTE 8, 23,10,1,139'),factory_spring_animation),
        (source.replace('GOSUB factory_springs_draw','trleft = 0'),factory_spring_animation),
        (source.replace('trph = 3\n\t\t\ttrtick = 0','trph = 1\n\t\t\ttrtick = 0'),trampoline_animation),
        (source.replace('my = trby + trpose - 16','my = trby - 16'),trampoline_animation),
        (source.replace('VARPTR tramp_pat(trpose * 16)','VARPTR tramp_pat(0)'),trampoline_animation),
        (source.replace('hbw = 8\n\t\thbh = 12', 'hbw = 8\n\t\thbh = 10'), clear_windows),
        (source.replace('st_fall:\n', 'st_fall:\n\tjhz = 1\n'), momentum),
        (source.replace('IF fd2 > FATALFALL THEN GOSUB mack_die',
                        'IF fd2 > FATALFALL THEN ded = 1'), momentum),
        (source.replace('\tGOSUB bolt_move\n', ''), clock_contract),
        (source.replace('\tIF lv <> 1 THEN RETURN\n', ''), inventory_contract),
        (source.replace('hl_slot', 'i'), inventory_contract),
        (source.replace('IF #cvt > kdy THEN #cvt = kdy',
                        'IF #cvt > kdy THEN #cvt = 0'), machinery),
        (source.replace('my = bmy - 16', 'my = bmy - 15'), machinery),
        (source.replace('SOUND 2,,0', 'SOUND 2,,8'), sound_contract),
        (source.replace('SOUND 3,4,7', 'SOUND 3,4,0'), sound_contract),
        (source.replace('SOUND 3,,0', 'SOUND 3,,8'), sound_contract),
        (source.replace('IF mx <> walkx THEN', 'IF mx = walkx THEN'), sound_contract),
        (source.replace('SOUND 3,5,8', 'SOUND 3,5,0'), sound_contract),
        (source.replace('clawstep = clawclock / 3', 'clawstep = 16'), pincer_passage),
        (source.replace('hbw = 4\n\thbh = 6','hbw = 5\n\thbh = 6'), pincer_passage),
        (source.replace('#slagclock >= 317','#slagclock >= 256'), slag_cadence),
        (source.replace('clawstep = clawclock / 3','clawstep = clawclock / 8'), machinery_animation),
        (source.replace('DATA BYTE $00,$00,$3C,$3C,$3C,$FF,$FF,$FF',
                        'DATA BYTE $00,$00,$3C,$3C,$3C,$E7,$E7,$E7'), pincer_passage),
        (source.replace('IF pressy > 62 THEN pressy = 62','IF pressy > 55 THEN pressy = 55'), machinery_animation),
        (source.replace('IF hzphase < 96 THEN','IF hzphase < 48 THEN'), machinery_animation),
        (source.replace('IF pressy > 124 THEN pressy = 124','IF pressy > 127 THEN pressy = 127'), machinery_animation),
        (source.replace('IF fy > bmold THEN RETURN','RETURN'), crane_contact),
        (source.replace('TILE(mx + 5,fy)','TILE(mx + 8,fy)'), crane_contact),
        (source.replace('16,4,1,238','16,5,1,238').replace('16,5,1,239','16,6,1,239')
               .replace('16,6,1,240','16,7,1,240').replace('16,7,1,241','16,8,1,241')
               .replace('16,8,1,242','16,9,1,242'), pincer_passage),
        (source.replace('GOSUB animated_machines','ded = 0'), machinery_animation),
        (source.replace("GOSUB hazard_hit\n\t' Slag emerges", "ded = 0\n\t' Slag emerges"), machinery_animation),
        (source.replace('BANK SELECT 2','BANK SELECT 1'), machinery_animation),
        (source.replace('hbw = 8\n\thbh = 8','hbw = 6\n\thbh = 8'), machinery_animation),
        (source.replace('DATA BYTE 5,2, 8,6','DATA BYTE 5,2, 8,7'), machinery_animation),
        (source.replace('\tGOSUB sound_tick\n','').replace('\tGOTO main_loop','\tGOSUB sound_tick\n\tGOTO main_loop'), sound_contract),
    ]
    mutants.extend([
        (source.replace('gapst(resetgap) = 0','gapst(resetgap) = 1'),fidelity),
        (source.replace('IF mgarm = 0 THEN RETURN','IF mgon = 0 THEN RETURN'),fidelity),
        (source.replace('IF hzphase < 64 THEN','IF hzphase < 0 THEN'),fidelity),
        (source.replace('lift_y(#pnlookup + 0)','lift_y(223 - #pnlookup)'),fidelity),
        (source.replace('ry = ry + 1','ry = ry'),fidelity),
        (source.replace('lives = lives - 1','lives = lives'),fidelity),
        (source.replace('dead_tick:\n', 'dead_tick:\n\tGOSUB death_cleanup\n',1),death_timing),
        (source.replace('level_complete:\n', 'level_complete:\n\tGOSUB quiet_screen\n',1),victory_scene),
        (source.replace('\tGOSUB quiet_audio\n\tGOSUB bonus_countdown',
                        '\tGOSUB bonus_countdown'),victory_scene),
        (source.replace('GOSUB quiet_audio\n\tIF lv = 1 THEN RESTORE victory_music1',
                        'GOSUB quiet_screen\n\tIF lv = 1 THEN RESTORE victory_music1'),victory_scene),
        (source.replace('GOSUB quiet_audio\n\tRETURN\n\nvictory_music1',
                        'GOSUB quiet_screen\n\tRETURN\n\nvictory_music1'),victory_scene),
        (source.replace('mack_die:\n\tIF st = S_DEAD THEN RETURN','mack_die:\n\tIF st = S_DEAD THEN RETURN\n\tBANK SELECT 1',1),fidelity),
    ])
    mutants.extend([
        (source.replace('tc = TILE(mx + 8,my + 1)', 'tc = T_VOID'),review_feedback),
        (source.replace('IF jix < 8 THEN jix = 7', 'jhang = 0\n\t\t\t\t\t\tIF jix < 8 THEN jix = 8'),review_feedback),
        (source.replace('st_fall:\n','st_fall:\n\tjhz = 2\n'),review_feedback),
        (source.replace('IF elpaint = 0 THEN RETURN','IF elpaint = 1 THEN RETURN'),review_feedback),
        (source.replace('bloby = 165 -','bloby = 175 -'),visual_hazards),
        (source.replace('ey = pressy\n','ey = pressy + 8\n'),machinery_animation),
        (source.replace('ey = by - 4','ey = by'),visual_hazards),
        (source.replace('IF lv = 3 THEN cvaf = (8 - (hzphase AND 7)) AND 7',''),visual_hazards),
        (source.replace('ex = 62 - clawshift','ex = 200'),visual_hazards),
        (source.replace('game_over:\n\tGOSUB quiet_screen','game_over:',1),visual_hazards),
        (source.replace('DATA BYTE 7, 14,3,17','DATA BYTE 7, 14,3,10'),visual_hazards),
        (source.replace('boxy = boxy + 1','boxy = boxy + 3'),speed_contract),
        (source.replace('fy = by + 9','fy = by + 16'),speed_contract),
        (source.replace('CONST T_ELEV   = 236','CONST T_ELEV   = 135'),review_feedback),
    ])
    mutants.extend([
        (source.replace('DATA BYTE 8, 22,22,1,166','DATA BYTE 8, 22,26,1,166'),chain_and_pickups),
        (source.replace('IF jb = 0 THEN GOSUB grab_chain','jb = 0'),chain_and_pickups),
        (source.replace('DATA BYTE 5,4,2, 22,16','DATA BYTE 5,4,2, 22,17'),chain_and_pickups),
        (source.replace('IF pressy < 105 THEN pressy = 105','IF pressy < 105 THEN pressy = 96'),machinery_animation),
        (source.replace('lives = setupkey - 1','lives = setupkey'),setup_inputs),
        (source.replace('IF titleheld <> 15 THEN','IF titleheld = 255 THEN'),setup_inputs),
    ])
    mutants.extend([
        (source.replace('IF levelno < 4 THEN RETURN','RETURN'),repeat_enemies),
        (source.replace('okind = RANDOM(2)','okind = vkind'),repeat_enemies),
        (source.replace('ob = rb','ob = 2'),repeat_enemies),
        (source.replace("' No right-end shortcut: enter the conveyor from the lift and escape left.", 'DATA BYTE 10,10,6,3,155'),factory_challenge),
        (source.replace('SOUND 0,,0','SOUND 0,,8'),sound_contract),
        (source.replace('SOUND 1,,0','SOUND 1,,8'),sound_contract),
        (source.replace('SOUND 1,#songharm,6','SOUND 1,#songharm,0'),sound_contract),
        (source.replace('RESTORE victory_music2','RESTORE victory_music1'),sound_contract),
        (source.replace('\tjhlock = 1\n','\tjhlock = 0\n'),hammer_release),
        (source.replace('carry = 2\n\t\t\t\tjbhc = 0','carry = 2'),hammer_release),
        (source.replace('IF carry = 2 THEN GOSUB drop_hammer','carry = carry'),hammer_release),
        (source.replace('IF carry <> 0 THEN RETURN',''),single_item),
        (source.replace('IF carry = 0 THEN\n\t\t\t\' Grabbing','IF carry < 2 THEN\n\t\t\t\' Grabbing'),single_item),
        (source.replace('hbw = 18','hbw = 0'),single_item),
        (source.replace('SPRITE 31,209,0,0,0',''),single_item),
        (source.replace('FOR qslot = 0 TO 31','FOR qslot = 0 TO 17'),visual_hazards),
        (source.replace('IF cx <= cvx1(0) THEN RETURN\n\tGOSUB mack_burn',
                        'IF cx <= cvx1(0) THEN RETURN\n\tGOSUB mack_die'),upper_conveyor),
        (source.replace('IF lives > 0 THEN\n\t\t\titst(cidx)',
                        'IF lives >= 0 THEN\n\t\t\titst(cidx)'),visual_hazards),
        (source.replace("mx = elx\t\t' any supported boarding snaps fully into the cabin",
                        "mx = mx\t\t' any supported boarding snaps fully into the cabin"),elevator_boarding),
        (source.replace('IF elarm = 1 THEN\n\t\tGOSUB elev_sup',
                        'IF elarm = 0 THEN\n\t\tGOSUB elev_sup'),elevator_boarding),
        (source.replace('IF jr THEN mx = mx + 1','IF jr THEN mx = mx'),elevator_boarding),
        (source.replace('ely = elby\n\temov = 0','ely = elty\n\temov = 0',1),elevator_boarding),
        (source.replace('IF cx <= elx + 15 THEN','IF cx < elx + 15 THEN'),elevator_boarding),
        (source.replace('IF setupkey > 6 THEN GOTO setup_level','IF setupkey > 3 THEN GOTO setup_level'),setup_inputs),
        (source.replace('ASM LI R1,>1000','ASM LI R1,>0800',1),title_hotkeys),
        (source.replace('ASM LI R0,>0100','ASM LI R0,>0300',1),title_hotkeys),
        (source.replace('ASM LI R0,>0200','ASM LI R0,>0300',1),title_hotkeys),
        (source.replace('ASM LI R1,>0800','ASM LI R1,>0400',1),title_hotkeys),
        (source.replace('DATA BYTE 8, 3,28,1,232','DATA BYTE 8, 3,27,1,232'),fixture_contract),
        (source.replace('bx = 216','bx = 240'),fixture_contract),
        (source.replace('IF girder_mark(c) THEN ch = T_GIRDR','ch = T_GIRDR'),girder_spacing),
        (source.replace('IF girder_mark(gapc(i)) THEN ch = T_GIRDR','ch = T_GIRDR'),girder_spacing),
        (source.replace('IF i = 3 THEN bc9 = 96 + boff','bc9 = uc'),girder_spacing),
        (source.replace('IF i = 3 THEN bc9 = 104 + boff','bc9 = lc'),girder_spacing),
        (source.replace('IF blobx > 80 THEN blobx = 80','blobx = blobx'),visual_hazards),
        (source.replace('IF slagphase >= 60 THEN RETURN','IF slagphase >= 68 THEN RETURN').replace('IF slagphase < 60 THEN','IF slagphase < 68 THEN'),visual_hazards),
        (source.replace('jbhc = jbhc + #fd','jbhc = jbhc + 1'),hammer_release),
        (source.replace('DATA BYTE 6, 8,22,2','DATA BYTE 6, 8,21,2'),upper_conveyor),
        (source.replace('GOSUB upper_belt_edge','cx = mx'),upper_conveyor),
        (source.replace('#lastscore = #score','#lastscore = 0'),title_scores),
        (source.replace('#scvalue = #hi','#scvalue = #score'),title_scores),
        (source.replace('\tCLS\n\tGOSUB game_chars','\tGOSUB game_chars',1),title_scores),
        (source.replace('BANK SELECT 3','BANK SELECT 2'),title_scores),
        (source.replace('2026 UNHUMAN and C&C AI','2026'),title_scores),
        (source.replace('hi838 = game838','hi838 = 0'),title_scores),
        (source.replace('last838 = game838','last838 = 0'),title_scores),
        (source.replace('game838 = 0','game838 = 1'),title_scores),
        (source.replace('game838 = 1','game838 = 0'),setup_inputs),
        (source.replace('IF #score > #hi THEN','IF #score >= #hi THEN'),title_scores),
        (source.replace('#award = #bonus_slice / 5','#award = #bonus_slice'),end_screen_timing),
        (source.replace('#go_age >= 600','#go_age >= 675'),end_screen_timing),
        (source.replace('#go_age < 75','#go_age < 1'),end_screen_timing),
        (source.replace('IF cont1.button THEN GOTO gover_rel','IF cont1.button THEN RETURN'),end_screen_timing),
        (source.replace('SOUND 3,5,7','SOUND 3,5,0'),end_screen_timing),
        (source.replace('SOUND 3,5,7\n\tWAIT\n\tWAIT',
                        'SOUND 3,5,7\n\tWAIT'),end_screen_timing),
        (source.replace('#score >= 1400','#score >= 7000'),score_range),
        (source.replace('#score_room = 65535 - #score','#score_room = 65535'),score_range),
        (source.replace('#sctens = #scvalue / 2','#sctens = #scvalue'),score_range),
        (source.replace('<.5>#sctens','<5>#sctens'),score_range),
        (source.replace('IF steptick AND 2 THEN','IF FRAME AND 2 THEN'),mack_animation),
        (source.replace('DEFINE SPRITE 31,4,mack_run_extra',''),mack_animation),
        (source.replace('IF mfr >= 124 THEN mcf = mfr + 4',''),mack_animation),
        (source.replace('IF mdir = 0 THEN mfr = 140',''),mack_animation),
        (source.replace('edance = 32','edance = 0'),elevator_dance),
        (source.replace('IF edance THEN RETURN',''),elevator_dance),
        (source.replace('edance = edance - 1','edance = edance - 2'),elevator_dance),
        (source.replace('IF dancenote AND 1 THEN #dancepitch = 447','IF dancenote AND 1 THEN #dancepitch = 280'),elevator_dance),
        (source.replace('IF st = S_RIDE THEN\n\t\tmy = ely - 16','IF st <> S_DEAD THEN\n\t\tmy = ely - 16'),elevator_dance),
        (source.replace('IF edance THEN mfr = dancebody',''),elevator_dance),
        (source.replace('edance = 0','edance = edance'),elevator_dance),
        (source.replace('IF levelno < 100 THEN PRINT AT CPOS(0,29),"L",levelno','IF levelno < 10 THEN PRINT AT CPOS(0,29),"L",levelno'),score_range),
        (source.replace('CPOS(0,HUD_BONUS_COL),<.4>#bonus','CPOS(0,2),<.4>#bonus'),score_range),
        (source.replace('PRINT AT CPOS(0,10),"BONUS "','PRINT AT CPOS(0,15),"BONUS "'),score_range),
        (source.replace('PRINT AT CPOS(0,10),"BONUS "','PRINT AT CPOS(0,11),"BONUS "'),score_range),
        (source.replace('#va = VADDR(0,21)','#va = VADDR(0,7)'),score_range),
        (source.replace('DEFINE CHAR 225,2,spigot_pat','DEFINE CHAR 231,2,spigot_pat'),fidelity),
        (source.replace('DATA BYTE 8, 18,6,1,226','DATA BYTE 8, 18,6,1,232'),fidelity),
        (source.replace("mx = 120\t' place Mack one character right", "mx = 112\t' place Mack one character right"),fidelity),
        (source.replace('IF my < 168 THEN\n\t\t\tmy = my + #fd * 3','IF my < 184 THEN\n\t\t\tmy = my + #fd * 3'),furnace_contract),
    ])
    mutants.extend([
        (source.replace('IF lv = 3 THEN cvdrag = 1',''),factory_belt_balance),
        (source.replace('IF jr THEN fx = walkx + 8',''),factory_belt_balance),
        (source.replace('DEFINE VRAM 3360,16','DEFINE VRAM 1312,16'),wall_sparks),
        (source.replace('DEFINE VRAM 3360,16,haz_pat',''),wall_sparks),
        (source.replace('pressy = pressy + presspart\n\t\tEND IF\n\t\tIF pressy > 124','pressy = pressy + pressstep\n\t\tEND IF\n\t\tIF pressy > 124',1),machinery_animation),
        (source.replace('presspart = pressstep / 6','presspart = 0'),machinery_animation),
        (source.replace('DEFINE VRAM 3320,24','DEFINE VRAM 1272,24'),visual_hazards),
        (source.replace('DEFINE VRAM 3712,16','DEFINE VRAM 1664,16'),optimized_rendering),
        (source.replace('DEFINE VRAM 4040,16','DEFINE VRAM 1992,16'),machinery_animation),
        (source.replace('BANK SELECT 4','BANK SELECT 1'),optimized_rendering),
        (source.replace('lift_x(#pnlookup + 56)','lift_x(#pnlookup + 55)'),optimized_rendering),
        (source.replace('DATA BYTE 8, 6,28,2,134','DATA BYTE 8, 6,29,1,134'),furnace_contract),
        (source.replace('DATA BYTE 8, 6,28,2,134','DATA BYTE 8, 6,28,2,129'),furnace_contract),
        (source.replace('IF firedepth > 16 THEN firedepth = 32 - firedepth','IF firedepth > 16 THEN firedepth = 16'),furnace_contract),
        (source.replace('IF my + 15 >= firetop THEN','IF my + 15 >= 24 THEN'),furnace_contract),
        (source.replace('VARPTR fire_col(firecolor * 32)','VARPTR fire_col(0)'),furnace_contract),
        (source.replace('DATA BYTE $71,$71,$91,$91,$A1,$C1,$A1,$91',
                        'DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1',1),furnace_contract),
    ])
    mutants.extend([
        (source.replace('springdir = mdir','springdir = 1 - springpad'),paddle_bucket_bounce),
        (source.replace('IF mx > 80 THEN mx = 80','mx = 80'),paddle_bucket_bounce),
        (source.replace('IF springtick <= 8 THEN\n\t\t\tmy = my - 2',
                        'IF springtick <= 8 THEN\n\t\t\tmy = my - 3'),paddle_bucket_bounce),
        (source.replace('IF mx > 64 THEN mx = mx - 1','mx = mx - 1'),paddle_bucket_bounce),
        (source.replace('IF springphase = 1 THEN GOTO bin_hop',
                        'IF springphase = 9 THEN GOTO bin_hop'),paddle_bucket_bounce),
    ])
    mutants.extend([
        (source.replace('\tgearoff = 1\n','\n',1),gear_sparks),
        (source.replace("\t\tgearoff = 0\t' far pad reached","\t\tgearlast = 0\t' far pad reached",1),gear_sparks),
        (source.replace('DEFINE VRAM 4960,24','DEFINE VRAM 2912,24',1),gear_sparks),
        (source.replace('ex = 108\n\tGOSUB hazard_hit\n\tex = 132','ex = 112\n\tGOSUB hazard_hit\n\tex = 132',1),gear_sparks),
        (source.replace('\tIF my >= 148 THEN\n','\tIF my >= 140 THEN\n',1),gear_sparks),
        (source.replace('IF my + 16 >= 160 THEN','IF my + 16 >= 152 THEN',1),visual_hazards),
    ])
    bucket_exits = {}
    for job in bucket_jobs:
        bucket_exits.update(job.result())
    sweep_pool.shutdown()
    assert sorted(bucket_exits) == sorted(PADDLE_EXITS), 'paddle-exit sweep lost a slice'
    print('Physics behavior sweeps passed; checking %d defect mutations' % len(mutants),flush=True)
    tasks = []
    for mutation_index,(mutant, check) in enumerate(mutants,1):
        assert mutant != source, 'defect mutation did not change source: ' + check.__name__
        tasks.append((mutation_index, mutant, check))
    workers = min(4, os.cpu_count() or 1, len(tasks))
    with ProcessPoolExecutor(max_workers=workers) as pool:
        pending = [pool.submit(reject_mutation, task) for task in tasks]
        for checked, future in enumerate(as_completed(pending), 1):
            future.result()
            if checked % 20 == 0:
                print('Mutation checks: %d/%d (%d workers)' %
                      (checked, len(tasks), workers), flush=True)
    print('Physics: 32-step jumps, both gap directions, fall momentum, fatal landings OK')
    print('Enemy over-jump wins (stationary / half speed / full speed; must be zero):', windows)
    print('All level parsers, pails, box delivery, belt surfaces and 448 lift steps OK')
    print('Twelve platform transfers, both spring transfers and sound envelopes OK')
    print('Paddle exits bouncing on into a bucket: walk left %d, walk right %d, jump left %d, jump right %d'
          % (bucket_exits['walk',0],bucket_exits['walk',1],bucket_exits['jump',0],bucket_exits['jump',1]))
    print('Walk-offs, parked/moving cabin and %d/8 live conveyor entries OK' % entry_wins)
    print('Hazard windows, magnet ride, drill/enemy routes and death rollback OK')
    print('Slag on belt, paired jaws, animation clocks, visible hitboxes and game-over elevator OK')
    print('Shared world clock and inventory/HUD OK; all %d defect mutations rejected' % len(mutants))


if __name__ == '__main__':
    main()
