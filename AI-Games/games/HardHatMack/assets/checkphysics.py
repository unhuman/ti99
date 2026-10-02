"""Execute the shipped BASIC movement routines against deterministic geometry.

This deliberately small interpreter rejects unsupported executed statements.
VDP tile reads are replaced by a floor/ceiling fixture; gameplay branches, byte
arithmetic, jump data, landing rules and hitboxes come from HARDHAT.bas.
It does not emulate CPU timing, input hardware, or prove whole-level reachability.
"""
from collections import defaultdict
import copy
from pathlib import Path
import re

SOURCE = Path(__file__).resolve().parent.parent / 'src/HARDHAT.bas'


class Basic:
    def __init__(self, source, floor=168, holes=()):
        self.v = defaultdict(int)
        self.arc = []
        self.arrays = {}
        self.expr_cache = {}
        self.floor, self.holes = floor, holes
        self.screen = None
        self.data = []
        self.sound = []
        self.sound_times = []
        self.wait_count = 0
        self.sprites = {}
        self.pattern_writes = []
        self.color_writes = []
        self.bank = 1
        self.frame_inputs = iter(())
        self.random_values = iter(())
        self.lines = [line.split("'")[0].strip().lower()
                      for line in source.splitlines()]
        self.labels = {line[:-1]: i for i, line in enumerate(self.lines)
                       if re.fullmatch(r'\w+:', line)}
        self.ends, self.elses = {}, {}
        stack = []
        for i, line in enumerate(self.lines):
            if line.startswith('if ') and line.endswith(' then'):
                stack.append((i, []))
            elif line == 'else' or line.startswith('elseif '):
                stack[-1][1].append(i)
            elif line == 'end if':
                start, branches = stack.pop()
                self.ends[start] = i
                for b in branches:
                    self.ends[b] = i
                for j, b in enumerate(branches):
                    self.elses[b] = branches[j + 1] if j + 1 < len(branches) else i
                self.elses[start] = branches[0] if branches else i
        assert not stack
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

    def expr(self, text):
        functions = dict(tile=self.tile, jtab=self.arc.__getitem__,
                         vaddr=lambda row, col: 6144 + row * 32 + col,
                         cpos=lambda row, col: row * 32 + col,
                         random=lambda limit: next(self.random_values, 1) % limit)
        functions.update({k: v.__getitem__ for k, v in self.arrays.items() if k != 'jtab'})
        key = text
        if key not in self.expr_cache:
            text = text.replace('cont1.button', 'input_button').replace('cont1.key', 'input_key')
            text = re.sub(r'\$([\da-f]+)', lambda m: str(int(m[1], 16)), text)
            text = text.replace('<>', '!=')
            text = re.sub(r'(?<![<>!=])=(?!=)', '==', text)
            text = re.sub(r'\band\b', '&', text).replace('/', '//')
            text = re.sub(r'#?[a-z_]\w*', lambda m: m[0] if m[0] in functions
                          else 'v[%r]' % m[0], text)
            self.expr_cache[key] = compile(text, '<BASIC expression>', 'eval')
        return eval(self.expr_cache[key], {'__builtins__': {}}, dict(v=self.v, **functions))

    def run(self, label):
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
            elif line == 'cls':
                self.screen = [32] * 768
            elif line == 'wait':
                sample = next(self.frame_inputs, None)
                assert sample is not None, 'input trace exhausted: '+label
                self.v.update(sample)
                self.wait_count += 1
            elif line.startswith('restore '):
                start = self.labels[line[8:]] + 1
                self.data = [self.expr(v.strip()) for ln in self.lines[start:]
                             if ln.startswith('data byte ') for v in ln[10:].split(',')]
            elif line.startswith('read byte '):
                target = line[10:]
                indexed = re.fullmatch(r'(\w+)\((.+)\)', target)
                if indexed:
                    self.arrays[indexed[1]][self.expr(indexed[2])] = self.data.pop(0)
                else:
                    self.v[target] = self.data.pop(0)
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
            elif line.startswith(('define char ', 'define color ')):
                # Record hardware-only uploads, including the actual ROM offset.
                color=line.startswith('define color ')
                first, count, pointer = line[13 if color else 12:].split(',', 2)
                m = re.fullmatch(r'varptr (\w+)\((.+)\)', pointer)
                if pointer.startswith(('varptr claw_pat','varptr press_')):
                    assert self.bank==2, 'animation data read from wrong bank'
                (self.color_writes if color else self.pattern_writes).append((self.expr(first),self.expr(count),
                    m[1] if m else pointer, self.expr(m[2]) if m else 0))
            elif line.startswith('bank select '):
                self.bank=self.expr(line[12:])
            elif line.startswith(('#if ', '#endif')):
                pass
            elif line.startswith('print '):
                pass  # Output-only hardware calls do not affect these tests.
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
    assert re.findall(r'gosub (\w+)', world) == routines
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
    script=source+'\nbutton_test:\n'+block+'\tRETURN\n'
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
                for _ in range(40):
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
                vm.v.update(mx=84 if side==0 else 156, my=168,
                            jr=1-side, jl=side, padok=1)
                vm.run('spring_begin')
                for _ in range(36):
                    vm.run('mack_step')
                assert vm.v['mx'] == (156 if side==0 else 84)
                assert vm.v['my'] == 168 and vm.v['st']==vm.v['s_jump']
                for _ in range(50):
                    vm.run('mack_step'); vm.run('beam_move')
                    if vm.v['st'] in (vm.v['s_walk'], vm.v['s_dead']): break
                assert vm.v['st']==vm.v['s_walk'] and vm.v['my']==120, (
                    'spring cannot reach opposite lower platform', side,dict(vm.v))



def fidelity(source):
    def level(n):
        vm=Basic(source); vm.v.update(lv=n, lives=2); vm.run('init_level')
        return vm
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
    assert vm.v['#score']==score+10 and vm.v['emov']==1 and vm.v['eld']==0
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
    assert vm.v['lvdone']==1 and vm.v['mx']==112
    # Moving hazards must have both safe and lethal windows.
    for n,x,y,safe,bad in ((2,184,120,90,20),(2,184,120,90,44),
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
            assert captures>=2, ('no usable factory lift entry',side,floor,captures)
    return wins


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
    vm=Basic(source+'\nframe_start_test:\n'+prefix+'\tRETURN\nrender_tail_test:\n'+tail)
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
    for _ in range(97):
        vm.run('site_step');vm.run('site_draw');poses.append(vm.v['clawstep'])
        assert vm.bank==1, 'animation bank not restored'
        assert vm.sprites[14][0]==209, 'level-2 smasher still uses a sprite'
    assert set(poses)==set(range(17)) and poses[0]==poses[96]==0
    assert all(abs(a-b)<=1 for a,b in zip(poses,poses[1:])), 'pincers snap between poses'
    assert all(len(set(poses[i:i+5]))>1 for i in range(93)), 'pincers pause at an endpoint'
    assert len(vm.pattern_writes)<97*3, 'unchanged machinery reuploads every pass'
    patterns=table('press_pat');colors=table('press_col')
    assert len(patterns)==len(colors)==32*48
    for row in range(3):
        assert vm.screen[(14+row)*32+23:(14+row)*32+25]==[243+row*2,244+row*2]
    feet=table('pressfoot_pat')
    assert len(feet)==3*8*16
    footcolors=table('pressfoot_col')
    for level,base,origin,low,high in ((2,112,184,104,124),(3,48,56,40,62)):
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
            for y in range(max(0,phase-8)):
                assert painted(7,y) and painted(8,y), 'floating smasher head'
            for y in range(max(0,phase-8),min(24,phase-4)):
                assert painted(1,y) and painted(14,y), 'smasher head too narrow'
                for tile in range(2):
                    assert colors[phase*48+(y//8*2+tile)*8+y%8]==[0xf1,0xd1,0x81,0x61][y-(phase-8)], 'head color slips across a cell'
            vm.v.update(presslast=255)
            vm.run('site_draw')
            assert vm.bank==1 and vm.sprites[14][0]==209, 'sprite smasher or wrong bank'
            assert vm.pattern_writes[-1]==(243,6,'press_pat',phase*48)
            assert vm.color_writes[-1]==(243,6,'press_col',phase*48)
            top=max(base,position+8);bottom=min(base+(23 if level==2 else 25),position+11)
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
                assert (249,2,'pressfoot_pat',offset) in vm.pattern_writes, 'wrong belt/head frame'
                assert (249,2,'pressfoot_col',depth*16) in vm.color_writes, 'wrong head foot colors'
                for y in range(depth):
                    assert footcolors[depth*16+y]==[0x81,0x61][2-depth+y]
        assert min(positions)==low and max(positions)==high, ('smasher travel',level,positions)
        assert all(abs(a-b)<=1 for a,b in zip(positions,positions[1:]+positions[:1])), 'smasher snaps back'
        assert positions.count(high)<=10, 'smasher pins player too long'
        assert low+8>=base and positions.count(low)>=32, 'smasher must wait visibly at the top'
        assert positions[28 if level==2 else 44]==high, 'wrong downward smasher speed'
        assert high+11==(135 if level==2 else 73), 'head must finish exactly above surface'
        if level==3:
            assert vm.screen[8*32+7]==vm.v['t_sbox'], 'piston erased conveyor box'
            vm.v.update(mx=52,my=56,ch=vm.v['t_sbox']);vm.run('take_item')
            assert vm.arrays['itst'][1]==1 and vm.v['carry']==1
            vm.run('site_draw')
            assert vm.screen[8*32+7]==247, 'box pickup punched a hole in the piston'
            assert vm.screen[4*32+12]==vm.v['t_sbox'], 'piston changed other boxes'


def slag_cadence(source):
    vm=Basic(source);vm.v.update(lv=2);vm.run('init_level')
    vm.v.update(mx=112,my=80,bmy=167,bmd=0,bmactive=1)
    returns=[];emissions=[]
    for tick in range(1,1191):
        vm.run('beam_move');vm.run('site_step')
        if vm.v['#slagclock']==0:emissions.append(tick)
        if vm.v['bmy']==167 and vm.v['bmd']==0:
            returns.append(vm.v['slagphase']<68)
    assert emissions==[317,634,951], ('unexpected glop release interval',emissions)
    assert len(returns)==5 and any(returns) and not all(returns), 'glop locked to crane visits'


def visual_hazards(source):
    """Execute trajectories/render calls; compare lethal regions with visible art."""
    vm=Basic(source);vm.v.update(lv=2);vm.run('init_level')
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
        assert visible==(clock<136), ('slag visibility/collision phase',clock)
        if visible:
            path.append((vm.v['blobx'],vm.v['bloby']))
            assert vm.sprites[15][1]==vm.v['blobx']
            if 32<=clock<88:
                vm.v.update(fx=vm.v['blobx']+8,kx0=vm.arrays['cvx0'][1],
                            ky0=vm.arrays['cvy0'][1],kdy=16)
                vm.run('belt_surface')
                assert abs(vm.v['bloby']+9-vm.v['srf'])<=1, ('slag buried below belt',clock)
        assert vm.pattern_writes[-1][0] in (156,238,243)
    assert all(path[i]==path[i+1] for i in range(0,136,2)), 'slag ignores half-speed clock'
    assert len(set(x for x,y in path[:32]))==1
    assert all(0<=b[0]-a[0]<=1 and abs(b[1]-a[1])<=2 for a,b in zip(path,path[1:]))
    assert path[100][1]<path[88][1] and path[-1][1]>path[100][1], 'missing roller arc'
    # The factory's treads must travel in the same direction as its carrier.
    for level,direction in ((2,1),(3,-1)):
        vm.v.update(lv=level)
        for clock in range(16):
            vm.v['hzphase']=clock;vm.run('site_draw')
            expected=(direction*(clock//2))%8
            belt=[w for w in vm.pattern_writes if w[0]==156][-1]
            assert belt==(156,6,'belt_anim0',expected*48), 'belt animation direction/rate'
    # Full game-over entry, stopped before the intentional timed/key wait.
    stop='\tFOR i = 1 TO 75\n'
    assert source.count(stop)==1
    for y,moving in ((168,0),(72,0),(117,1)):
        end=Basic(source.replace(stop,'\tRETURN\n',1))
        end.v.update(lv=1);end.run('init_level')
        end.v.update(ely=y,emov=moving);end.run('elev_back')
        end.run('game_over')
        assert end.sprites[2]==(y-1,end.v['elx'],8,15), 'game-over lost elevator floor'
        assert end.sprites[9]==(y-17,end.v['elx'],84,15), 'game-over lost moving cage'
        assert all(v[0]==209 for k,v in end.sprites.items() if k not in (2,9))

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
        vm=Basic(source+'\nspeed_tick:\n'+clock+'\tRETURN\n');steps=0
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
        assert vm.v['mx']==start+(10 if level==2 else -10), 'belt speed'
    vm=Basic(source);vm.v.update(lv=3);vm.run('init_level')
    vm.v.update(boxfall=1,boxy=128,mx=112,my=80)
    for _ in range(39):vm.run('factory_step')
    assert vm.v['boxy']==167 and vm.v['boxfall']==1, 'factory box drops too fast'
    vm.run('factory_step');assert vm.v['boxfall']==0
    for start,bounced in ((150,False),(156,False),(157,True)):
        vm=Basic(source);vm.v.update(bolon=1,bon=1,bx=120,by=start,bvel=1,bph=0,bnx=0)
        vm.run('bolt_move')
        assert (vm.v['bph']==1)==bounced, 'rivet bounces above the visible floor'


def chain_and_pickups(source):
    for mode in ('walk','jump','fall'):
        vm=Basic(source);vm.v.update(lv=2);vm.run('init_level')
        # Reach the chain from its clear right-hand approach without Up held.
        vm.v.update(mx=210,my=168,jl=1)
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
    assert vm.screen[22*32+17:22*32+19]==[vm.v['t_mixbas']]*2, 'pickup overwrites machine support'
    assert vm.screen[22*32+19:22*32+21]==[vm.v['t_lboxl'],vm.v['t_lboxl']+1], 'hazard overwrites ground pail'
    vm.v.update(mx=120,my=168)
    before=vm.v['#score'];vm.run('mack_step')
    assert vm.v['#score']==before+200 and vm.arrays['itst'][7]==1, 'spray can not collectible'
    assert vm.screen[22*32+17:22*32+19]==[vm.v['t_mixbas']]*2, 'pickup erased machine support'


def setup_inputs(source):
    def input_trace(keys):
        for key in keys:
            yield dict(input_key=15,input_button=0)
            for _ in range(3):yield dict(input_key=key,input_button=0)
    for lives in range(1,10):
        for level in range(1,4):
            vm=Basic(source);vm.v.update(input_key=15,lv=1,lives=2)
            vm.frame_inputs=iter([dict(input_key=15,input_button=0)]+list(input_trace([8,3,8,0,lives,9,0,level])))
            vm.run('title_screen')
            assert vm.v['lives']==lives-1 and vm.v['lv']==level and vm.bank==1, '838 selection / bank return'
            vm.run('init_level')
            assert vm.screen[54:63]==[32]*(10-lives)+[vm.v['t_hat']]*(lives-1), 'reserve hats wrong'
    # Incorrect code, a held digit, and title navigation must not select a level.
    vm=Basic(source);vm.v.update(input_key=15,lv=1,lives=2)
    vm.frame_inputs=iter([dict(input_key=15,input_button=0)]+list(input_trace([8,5,3,8]))+[dict(input_button=1)])
    vm.run('title_screen')
    assert vm.v['lv']==1 and vm.v['lives']==2 and vm.bank==1
    vm=Basic(source);vm.v.update(titleheld=15,input_key=3)
    vm.run('menu_key');assert vm.v['setupkey']==3
    vm.run('menu_key');assert vm.v['setupkey']==15, 'held digit accepted twice'


def repeat_enemies(source):
    # Execute the real completion transition, stopping before the frame loop.
    advance=source[source.index('\tlevelno = levelno + 1'):source.index('\ngame_over:')]
    advance=advance.replace('GOTO main_loop','RETURN')
    vm=Basic(source+'\nadvance_fixture:\n'+advance)
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


def main():
    source = SOURCE.read_text(encoding='utf-8')
    windows = clear_windows(source)
    momentum(source)
    clock_contract(source)
    inventory_contract(source)
    hammer_release(source)
    machinery(source)
    transfers(source)
    sound_contract(source)
    pincer_passage(source)
    crane_contact(source)
    machinery_animation(source)
    chain_and_pickups(source)
    setup_inputs(source)
    repeat_enemies(source)
    factory_challenge(source)
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
        (source.replace('IF itst(1) = 1 THEN','IF itst(1) = 0 THEN'), machinery_animation),
        (source.replace('\tGOSUB sound_tick\n','').replace('\tGOTO main_loop','\tGOSUB sound_tick\n\tGOTO main_loop'), sound_contract),
    ]
    mutants.extend([
        (source.replace('gapst(resetgap) = 0','gapst(resetgap) = 1'),fidelity),
        (source.replace('IF mgarm = 0 THEN RETURN','IF mgon = 0 THEN RETURN'),fidelity),
        (source.replace('IF hzphase < 64 THEN','IF hzphase < 0 THEN'),fidelity),
        (source.replace('pny = 64 + pnpos','pny = 144 - pnpos'),fidelity),
        (source.replace('ry = ry + 1','ry = ry'),fidelity),
    ])
    mutants.extend([
        (source.replace('tc = TILE(mx + 8,my + 1)', 'tc = T_VOID'),review_feedback),
        (source.replace('IF jix < 8 THEN jix = 7', 'jhang = 0\n\t\t\t\t\t\tIF jix < 8 THEN jix = 8'),review_feedback),
        (source.replace('st_fall:\n','st_fall:\n\tjhz = 2\n'),review_feedback),
        (source.replace('IF elpaint = 0 THEN RETURN','IF elpaint = 1 THEN RETURN'),review_feedback),
        (source.replace('bloby = 165 -','bloby = 175 -'),visual_hazards),
        (source.replace('ey = pressy\n','ey = pressy + 8\n'),machinery_animation),
        (source.replace('ey = by - 4','ey = by'),visual_hazards),
        (source.replace('IF lv = 3 THEN cvaf = (8 - cvaf) AND 7',''),visual_hazards),
        (source.replace('ex = 62 - clawshift','ex = 200'),visual_hazards),
        (source.replace('game_over:\n\tGOSUB quiet_screen\n\tGOSUB elev_draw','game_over:\n\tGOSUB quiet_screen'),visual_hazards),
        (source.replace('DATA BYTE 7, 14,3,17','DATA BYTE 7, 14,3,10'),visual_hazards),
        (source.replace('boxy = boxy + 1','boxy = boxy + 3'),speed_contract),
        (source.replace('fy = by + 9','fy = by + 16'),speed_contract),
        (source.replace('CONST T_ELEV   = 236','CONST T_ELEV   = 135'),review_feedback),
    ])
    mutants.extend([
        (source.replace('DATA BYTE 8, 22,21,1,166','DATA BYTE 8, 22,23,1,166'),chain_and_pickups),
        (source.replace('IF jb = 0 THEN GOSUB grab_chain','jb = 0'),chain_and_pickups),
        (source.replace('DATA BYTE 5,4,2, 22,16','DATA BYTE 5,4,2, 22,17'),chain_and_pickups),
        (source.replace('IF pressy < 104 THEN pressy = 104','IF pressy < 104 THEN pressy = 96'),machinery_animation),
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
        (source.replace('jbhc = jbhc + #fd','jbhc = jbhc + 1'),hammer_release),
    ])
    for mutant, check in mutants:
        assert mutant!=source, 'defect mutation did not change source: '+check.__name__
        try:
            check(mutant)
        except AssertionError:
            continue
        raise AssertionError('checker accepted historical defect: '+check.__name__)
    print('Physics: 32-step jumps, both gap directions, fall momentum, fatal landings OK')
    print('Enemy over-jump wins (stationary / half speed / full speed; must be zero):', windows)
    print('All level parsers, pails, box delivery, belt surfaces and 448 lift steps OK')
    print('Twelve platform transfers, both spring transfers and sound envelopes OK')
    print('Walk-offs, parked/moving cabin and %d/8 live conveyor entries OK' % entry_wins)
    print('Hazard windows, magnet ride, drill/enemy routes and death rollback OK')
    print('Slag on belt, paired jaws, animation clocks, visible hitboxes and game-over elevator OK')
    print('Shared world clock and inventory/HUD OK; all %d defect mutations rejected' % len(mutants))


if __name__ == '__main__':
    main()
