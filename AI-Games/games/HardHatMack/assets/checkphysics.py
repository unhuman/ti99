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
        text = text.replace('cont1.button', '0')
        text = re.sub(r'\$([\da-f]+)', lambda m: str(int(m[1], 16)), text)
        text = text.replace('<>', '!=')
        text = re.sub(r'(?<![<>!=])=(?!=)', '==', text)
        text = re.sub(r'\band\b', '&', text)
        text = text.replace('/', '//')
        functions = dict(tile=self.tile, jtab=self.arc.__getitem__,
                         vaddr=lambda row, col: 6144 + row * 32 + col,
                         cpos=lambda row, col: row * 32 + col)
        functions.update({k: v.__getitem__ for k, v in self.arrays.items() if k != 'jtab'})
        text = re.sub(r'#?[a-z_]\w*', lambda m: m[0] if m[0] in functions
                      else 'v[%r]' % m[0], text)
        return eval(text, {'__builtins__': {}}, dict(v=self.v, **functions))

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
                self.v[line[10:]] = self.data.pop(0)
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
                'beam_move', 'mag_move', 'mag_catch', 'elev_move']
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
        assert vm.v['nitem'] == 6
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
            vm.v.update(mx=100, my=128, bonbeam=1, pnside=0)
            previous = (vm.v['mx'], vm.v['my'])
            visited = set()
            for _ in range(480):
                vm.run('beam_move')
                now = (vm.v['mx'], vm.v['my'])
                assert sum(abs(a-b) for a,b in zip(now,previous)) == 1, 'lift teleported rider'
                vm.run('beam_sup')
                assert vm.v['bsup'] == 1 and vm.v['my'] + 16 == vm.v['bmy']
                visited.add((vm.v['pnlx'], vm.v['pnyl']))
                previous = now
            assert len(visited) == 240
            # Boxes survive pickup/delivery with no stale level-1 gaps involved.
            for i in range(6):
                vm.v.update(mx=vm.arrays['itc'][i]*8-8,
                            my=vm.arrays['itr'][i]*8-8)
                vm.run('take_item')
                assert vm.v['carry'] == 1
                vm.v.update(mx=112,my=168)
                vm.run('deliver_zone')
                assert vm.v['carry']==1, 'box delivered outside an IN machine'
                vm.v.update(mx=32 if i%2==0 else 200,my=168)
                vm.run('deliver_zone')
                assert vm.v['nbox'] == 5-i
            assert vm.v['lvdone'] == 1


def transfers(source):
    # Controlled takeoff positions, then actual movement and moving surfaces.
    # These verify the transfers; they are not autonomous full play-throughs.
    for level in (2, 3):
        base = Basic(source); base.v.update(lv=level); base.run('init_level')
        for floor, phases in ((72, (28,28) if level==2 else (70,10)),
                              (104, (56,56) if level==2 else (38,38)),
                              (136, (88,88) if level==2 else (5,70))):
            for side, phase in enumerate(phases):
                vm = copy.deepcopy(base)
                if level == 3:
                    vm.v.update(pnphase=phase); vm.run('beam_move')
                    x = vm.v['pnlx' if side==0 else 'pnrx']
                    y = vm.v['pnyl' if side==0 else 'pnyr']
                    vm.v.update(mx=x+4, my=y-16, pnside=side)
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
            for side, phase in ((0,3),(1,60)):
                vm = copy.deepcopy(base)
                vm.v.update(pnphase=phase); vm.run('beam_move')
                vm.v.update(mx=84 if side==0 else 156, my=168,
                            jr=1-side, jl=side, padok=1)
                vm.run('mack_step')
                for _ in range(50):
                    vm.run('mack_step'); vm.run('beam_move')
                    if vm.v['st'] in (vm.v['s_walk'], vm.v['s_dead']): break
                assert vm.v['bonbeam']==1, 'spring cannot reach circulating lift'


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
    for mutant, check in mutants:
        try:
            check(mutant)
        except AssertionError:
            continue
        raise AssertionError('checker accepted historical defect')
    print('Physics: 32-step jumps, both gap directions, fall momentum, fatal landings OK')
    print('Safe enemy launch positions (stationary / half speed / full speed):', windows)
    print('All level parsers, pails, box delivery, belt surfaces and 480 lift steps OK')
    print('Twelve platform transfers, both spring boardings and sound envelopes OK')
    print('Shared world clock and inventory/HUD OK; all nine defect mutations rejected')


if __name__ == '__main__':
    main()
