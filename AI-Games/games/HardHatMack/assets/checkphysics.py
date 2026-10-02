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
                         random=lambda limit: 1 % limit)
        functions.update({k: v.__getitem__ for k, v in self.arrays.items() if k != 'jtab'})
        key = text
        if key not in self.expr_cache:
            text = text.replace('cont1.button', '0')
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
                self.sound.append(tuple(self.expr(x) if x else None
                                        for x in line[6:].split(',')))
            elif re.match(r'(sprite|print) ', line):
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
    block = source.split('actors_move:')[1].split("' Vandal: lethal")[1].split("' OSHA man:")[0]
    width, height = re.search(r'hbw = (\d+)\s+hbh = (\d+)\s+GOSUB mack_hit\s+IF hit', block).groups()
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
        assert safe >= 3, 'no usable jump window at enemy speed %s: %s' % (speed, safe)
        counts.append(safe)
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
                for _ in range(14):
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
    for n,x,y,safe,bad in ((2,48,120,90,10),(2,184,120,90,20),
                          (3,56,58,90,30)):
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
    cells=[origin,origin+1,origin+32,origin+33]
    assert [parked[x] for x in cells]==[227,229,228,230]
    vm.run('elev_back');assert vm.screen==parked
    vm.v.update(emov=1,ely=vm.v['ely']-1);vm.run('elev_back')
    assert vm.screen==original, 'moving elevator left cabin characters behind'
    vm.v.update(emov=0,ely=vm.v['elty']);vm.run('elev_back')
    assert vm.v['elpaint']==1 and vm.screen!=original
    assert 'DEFINE CHAR 227,4,cage_bitmap' in source, 'cabin art diverged from sprite'
    # Start from the actual level-2 spawn, walk, jump onto the conveyor and
    # jump from its last roller onto the crane. All actors/hazards are live.
    wins=0
    for phase in range(0,128,16):
        vm=Basic(source);vm.v.update(lv=2);vm.run('init_level')
        vm.v.update(hzphase=phase,jr=1)
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


def sound_contract(source):
    for pitch, duration in ((600,14),(300,5),(360,12),(140,12),(180,8),(400,6)):
        vm = Basic(source)
        vm.v.update(snd2=duration,sndvol=12)
        vm.v['#sndpitch']=pitch
        vm.run('tone_start')
        # Busy-frame deltas must consume the same envelope time.
        for delta in (4,3,4,3):
            vm.v['#fd']=delta
            vm.run('sound_tick')
        assert vm.v['snd2']==0 and vm.sound[-1]==(2,None,0), 'tone stuck on'
        assert all(0 < event[1] <= 1023 for event in vm.sound if event[1] is not None)


def main():
    source = SOURCE.read_text(encoding='utf-8')
    windows = clear_windows(source)
    momentum(source)
    clock_contract(source)
    inventory_contract(source)
    machinery(source)
    transfers(source)
    sound_contract(source)
    fidelity(source)
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
        (source.replace('jhang = 16', 'jhang = 0'), clear_windows),
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
    ])
    for mutant, check in mutants:
        try:
            check(mutant)
        except AssertionError:
            continue
        raise AssertionError('checker accepted historical defect')
    print('Physics: 32-step jumps, both gap directions, fall momentum, fatal landings OK')
    print('Safe enemy launch positions (stationary / half speed / full speed):', windows)
    print('All level parsers, pails, box delivery, belt surfaces and 448 lift steps OK')
    print('Twelve platform transfers, both spring transfers and sound envelopes OK')
    print('Walk-offs, parked/moving cabin and %d/8 live conveyor entries OK' % entry_wins)
    print('Hazard windows, magnet ride, drill/enemy routes and death rollback OK')
    print('Shared world clock and inventory/HUD OK; all %d defect mutations rejected' % len(mutants))


if __name__ == '__main__':
    main()
