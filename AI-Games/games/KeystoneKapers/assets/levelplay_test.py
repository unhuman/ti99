"""Exercise real BASIC level loading, prize lifetime and fast hazard movement.

This deliberately executes the production statements, including byte wrapping;
it is not a second implementation of load_band that could agree with itself.
"""
from collections import defaultdict
from pathlib import Path
import re
import random
import unittest
from unittest.mock import patch
from contextlib import redirect_stdout
import io

import genstore
from levelmodel import speeds
from looptiming_test import platform_source

SOURCE = Path(__file__).parents[1].joinpath('src/KEYSTONE.bas').read_text()


class Basic:
    def __init__(self, source=SOURCE, platform='NES'):
        self.source = source
        self.platform = platform
        self.rng = random.Random(0)
        self.addresses = {}
        self.lines = [s.strip() for s in platform_source(source, platform).splitlines()]
        self.labels = {s[:-1]: i for i, s in enumerate(self.lines) if s.endswith(':')}
        self.values = defaultdict(int)
        self.arrays = defaultdict(lambda: defaultdict(int))
        self.memory = defaultdict(int)
        self.constants = dict((k, int(v)) for k, v in
                              re.findall(r'CONST (\w+) = (\d+)\b', source))
        self.stubs = set()
        self.calls = []
        self.ends, self.elses, self.nexts = {}, {}, {}
        blocks, loops = [], []
        for i, line in enumerate(self.lines):
            if line.startswith('IF ') and line.endswith(' THEN'):
                blocks.append(i)
            elif line == 'ELSE':
                self.elses[blocks[-1]] = i
            elif line == 'END IF':
                begin = blocks.pop()
                self.ends[begin] = i
                if begin in self.elses:
                    self.ends[self.elses[begin]] = i
            elif line.startswith('FOR '):
                loops.append(i)
            elif line.startswith('NEXT '):
                begin = loops.pop()
                self.nexts[begin] = i

    def value(self, expression):
        expression = re.sub(r'VARPTR (\w+)\(0\)',
                            lambda m: str(self.addresses[m[1]]), expression)
        def token(m):
            word = m[0]
            if word in ('AND', 'OR'):
                return '&' if word == 'AND' else '|'
            if word.endswith('('):
                word = word[:-1]
                return 'mem(' if word == 'PEEK' else 'rnd(' if word == 'RANDOM' else 'arr(%r,' % word
            if word in self.constants:
                return str(self.constants[word])
            return 'var(%r)' % word
        text = re.sub(r'#[A-Za-z]\w*|[A-Za-z]\w*\(?', token, expression)
        text = text.replace('<>', '!=')
        text = text.replace('/', '//')
        text = re.sub(r'(?<![<>=!])=(?!=)', '==', text)
        return eval(text, {'__builtins__': {}}, {
            'var': lambda n: self.values[n],
            'arr': lambda n, i: self.arrays[n][i],
            'mem': lambda i: self.memory[i],
            'rnd': self.rng.randrange,
        })

    def assign(self, target, value):
        value &= 65535 if target.startswith('#') else 255
        if '(' in target:
            name, index = target[:-1].split('(', 1)
            self.arrays[name][self.value(index)] = value
        else:
            self.values[target] = value

    def run(self, name, limit=20000):
        pc, returns, loops = self.labels[name] + 1, [], []
        for _ in range(limit):
            line = self.lines[pc]
            current = pc
            pc += 1
            if not line or line.endswith(':') or line.startswith('ASM '):
                continue
            if line.startswith('IF '):
                condition, statement = line[3:].split(' THEN', 1)
                yes = bool(self.value(condition))
                if not statement.strip():
                    if not yes:
                        pc = self.elses.get(current, self.ends[current]) + 1
                    continue
                alternatives = statement.strip().split(' ELSE ', 1)
                line = alternatives[0] if yes else alternatives[1] if len(alternatives) > 1 else ''
                if not line:
                    continue
            if line == 'ELSE':
                pc = self.ends[current] + 1
            elif line == 'END IF':
                pass
            elif line.startswith('FOR '):
                target, bounds = line[4:].split(' = ')
                begin, end = map(self.value, bounds.split(' TO '))
                self.assign(target, begin)
                loops.append((target, end, current))
            elif line.startswith('NEXT '):
                target, end, begin = loops[-1]
                if self.values[target] < end:
                    self.assign(target, self.values[target] + 1)
                    pc = begin + 1
                else:
                    loops.pop()
            elif line.startswith('GOSUB '):
                callee = line[6:]
                self.calls.append(callee)
                if callee not in self.stubs:
                    returns.append(pc)
                    pc = self.labels[callee] + 1
            elif line.startswith('GOTO '):
                if line[5:] in self.stubs:
                    return
                pc = self.labels[line[5:]] + 1
            elif line.startswith('VPOKE '):
                address, value = line[6:].split(',', 1)
                self.memory[self.value(address)] = self.value(value)
            elif line.startswith('PRINT AT '):
                address, text = line[9:].split(',', 1)
                base = 8192 if self.platform == 'NES' else 6144
                for i, ch in enumerate(text.strip().strip('"')):
                    self.memory[base+self.value(address)+i] = ord(ch)
            elif line == 'CLS':
                base = 8192 if self.platform == 'NES' else 6144
                self.memory.update({base+i: 32 for i in range(768)})
                if self.platform == 'NES':
                    self.memory.update({9152+i: 0 for i in range(64)})
            elif line in ('SCREEN DISABLE', 'SCREEN ENABLE', 'WAIT'):
                self.calls.append(line)
            elif line.startswith('BANK SELECT '):
                self.calls.append('bank:'+line.split()[-1])
            elif line == 'RETURN':
                if not returns:
                    return
                pc = returns.pop()
            elif ' = ' in line:
                target, expression = line.split(' = ', 1)
                self.assign(target, self.value(expression))
            else:
                raise AssertionError('Unsupported executed BASIC: ' + line)
        raise AssertionError('BASIC execution did not terminate: ' + name)


class LevelPlayTest(unittest.TestCase):
    def test_runtime_counts_match_table_and_radio_positions(self):
        table = genstore.levels()
        for platform in ('NES', 'COLECO', 'TI994A'):
            vm = Basic(platform=platform)
            vm.values.update({'#stlv': 4096, 'hsc': 255})
            vm.memory.update(enumerate(table, 4096))
            vm.arrays['lv8'].update(enumerate([0, 8, 16, 24]))
            for krook in range(1, 17):  # 17+ use the persistent random map
                for screen in range(8):
                    vm.values.update(krk=krook, klsc=screen)
                    vm.run('load_band')
                    row = min(krook, genstore.KROOKS) - 1
                    for floor in range(4):
                        byte = table[row * 32 + floor * 8 + screen]
                        kind = byte & 7
                        count = (1 + bool(byte & 8) +
                                 bool(byte & 8 and kind == 3 and krook >= 8)) if kind else 0
                        slots = [floor * 2, floor * 2 + 1, 8 + floor]
                        live = [slot for slot in slots if vm.arrays['obk'][slot]]
                        self.assertEqual(len(live), count, (platform, krook, floor, screen))
                        if kind == 3:
                            positions = sorted(vm.arrays['obx'][slot] for slot in live)
                            self.assertEqual(positions, {1: [120], 2: [56, 184],
                                                         3: [56, 120, 184]}[count])

    def test_prizes_reset_on_new_game_and_capture_but_not_retry(self):
        for platform in ('NES', 'COLECO', 'TI994A'):
            vm = Basic(platform=platform)
            vm.stubs.add('start_krook')
            vm.arrays['takn'].update(enumerate([255] * 4))
            vm.run('new_game')
            self.assertEqual([vm.arrays['takn'][i] for i in range(4)], [0] * 4)
            capture = SOURCE.split('do_catch:', 1)[1].split('bonus_count:', 1)[0]
            tail = capture[capture.index('\tkrk = krk + 1'):]
            vm = Basic('advance:\n' + tail + '\n' + SOURCE, platform)
            vm.stubs.update(('start_krook', 'main'))
            for krook in range(1, 5):
                vm.values['krk'] = krook
                vm.arrays['takn'].update(enumerate([255] * 4))
                vm.run('advance')
                self.assertEqual(vm.values['krk'], krook + 1)
                self.assertEqual([vm.arrays['takn'][i] for i in range(4)], [0] * 4)
            # The common retry routine must not provide a prize-farming reset.
            start = SOURCE.split('start_krook:', 1)[1].split('draw_screen:', 1)[0]
            self.assertNotIn('GOSUB reset_prizes', start)
            self.assertNotRegex(start, r'takn\(\d\) = 0')

    def test_measured_speed_tiers_and_accumulator_capacity(self):
        vm = Basic()
        for level in range(1, 22):
            cart = 192 if 7 <= level <= 10 else 96
            plane = 96 if level < 8 else 192 if level < 12 else 264
            self.assertEqual(speeds(SOURCE, level), {1: cart, 2: 48, 3: 0, 4: plane})
        for speed in (25, 48, 57, 96, 111, 144, 192):
            for remainder in range(64):
                for frames in (1, 2, 3, 5):
                    vm.values.update(pacc=remainder, psp64=speed, fdv=frames)
                    vm.run('pace_step')
                    expected = divmod(remainder + speed * frames, 64)
                    self.assertEqual((vm.values['pspd'], vm.values['pacc']), expected)

    def test_fast_plane_wraps_both_edges_without_byte_overflow(self):
        vm = Basic()
        vm.values.update(obsp=48, ocsp=96, opsp=192, fdv=5)
        vm.arrays['obk'][0] = 4
        for direction in (0, 1):
            for x in range(241):
                vm.values['oacp'] = 0
                vm.arrays['obx'][0] = x
                vm.arrays['obd'][0] = direction
                vm.run('upd_obst')
                actual = vm.arrays['obx'][0]
                expected = (x + (30 if direction else -30)) % 240
                self.assertEqual(actual % 240, expected, (direction, x))
                self.assertLessEqual(actual, 240)
        vm.values['hfz'] = 1
        vm.arrays['obx'][0] = 123
        vm.run('upd_obst')
        self.assertEqual(vm.arrays['obx'][0], 123)

    def test_each_shopping_floor_keeps_encounter_variety(self):
        table = genstore.levels()
        for level in range(3, 12):
            row = table[(level - 1) * 32:level * 32]
            for floor in range(3):
                kinds = set(v & 7 for v in row[floor * 8:floor * 8 + 8]) - {0}
                self.assertGreaterEqual(len(kinds), 2 if level == 3 else 3,
                                        (level, floor, kinds))

    def test_screen_edges_do_not_alias_collision_coordinates(self):
        for platform in ('NES', 'TI994A', 'COLECOVISION'):
            vm = Basic(platform=platform)
            vm.stubs.add('do_hit')
            vm.values.update(klv=0, kjh=0, klst=0, fdv=1)
            for kind in (1, 2, 3, 4):
                vm.arrays['obk'][0] = kind
                for player in (0, 1, 7, 8, 12, 232, 239, 240, 247, 248, 252, 255):
                    # Also cover hypothetical obstacle bytes beyond the normal
                    # x240 limit: neither operand may alias the opposite edge.
                    for obstacle in (0, 1, 8, 12, 228, 232, 239, 240, 248, 252, 255):
                        vm.values.update(klx=player, dead=0, ospc=0, ospp=0)
                        vm.arrays['obx'][0] = obstacle
                        vm.arrays['obht'][0] = 0
                        vm.calls.clear()
                        vm.run('coll_obst')
                        self.assertEqual(bool(vm.values['dead'] or 'do_hit' in vm.calls),
                                         abs(player - obstacle) < 12,
                                         (platform, kind, player, obstacle))

    def test_wrapping_planes_do_not_sweep_across_the_screen(self):
        vm = Basic()
        vm.arrays['obk'][0] = 4
        vm.values.update(klv=0, kjh=0, klst=0, obsp=48, ocsp=96, opsp=192, fdv=5)
        for direction in (0, 1):
            for old_x in ((0, 1, 15, 29) if direction == 0 else (211, 225, 239, 240)):
                for player in (0, 8, 60, 120, 180, 232, 240, 248, 252, 255):
                    vm.values.update(klx=player, dead=0, oacp=0)
                    vm.arrays['obx'][0] = old_x
                    vm.arrays['obd'][0] = direction
                    vm.arrays['obht'][0] = 0
                    vm.run('upd_obst')
                    new_x = vm.arrays['obx'][0]
                    vm.run('coll_obst')
                    # Endpoint overlap plus the incoming centre segment;
                    # wrapping itself never traverses the middle of the floor.
                    crossing = (new_x <= player <= min(240, new_x + 29)
                                if direction == 0 else max(0, new_x - 29) <= player <= new_x)
                    expected = abs(player - new_x) < 12 or crossing
                    self.assertEqual(bool(vm.values['dead']), expected,
                                     (direction, old_x, new_x, player))

    def test_real_updates_deliver_distinct_speeds(self):
        for level in (3, 7, 8, 11, 12, 16, 20):
            vm = Basic()
            wanted = speeds(SOURCE, level)
            vm.values.update(obsp=wanted[2], ocsp=wanted[1], opsp=wanted[4] // 2)
            vm.arrays['obk'].update({0: 1, 2: 2, 4: 4})
            totals = [0, 0, 0]
            # 160 frames covers whole accumulator periods, including the
            # fractional late-plane cap (two-pixel steps at 132/64).
            for frames in [2, 3] * 32:
                vm.values['fdv'] = frames
                vm.run('upd_obst')
                for i, name in enumerate(('ospc', 'ospb', 'ospp')):
                    totals[i] += vm.values[name]
            self.assertEqual(totals, [wanted[k] * 160 // 64 for k in (1, 2, 4)])

    def test_fast_traffic_cannot_pass_through_a_standing_player(self):
        vm = Basic()
        vm.stubs.add('do_hit')
        for kind in (1, 4):
            vm.arrays['obk'][0] = kind
            for direction in (0, 1):
                sign = 1 if direction else -1
                vm.arrays['obd'][0] = direction
                for travel in (6, 15, 24, 30):
                    for player_move in (-9, 0, 9):
                        for old_relative in range(-42, 43, 3):
                            if abs(old_relative) < 12:
                                continue  # contact was already present on the preceding pass
                            player = 100 + player_move
                            obstacle = 100 + old_relative + sign * travel
                            relative = obstacle - player
                            expected = abs(relative) < 12 or old_relative * relative < 0
                            for duck in (False, True):
                                vm.values.update(klv=0, klx=player, kjh=0, dead=0,
                                                 klst=vm.constants['ST_DUCK' if duck else 'ST_RUN'],
                                                 kprev=vm.constants['ST_DUCK' if duck else 'ST_RUN'],
                                                 ospc=travel, ospp=travel, fdv=3)
                                vm.arrays['obx'][0] = obstacle
                                vm.arrays['obht'][0] = 0
                                vm.calls.clear()
                                vm.run('coll_obst')
                                hit = bool(vm.values['dead'] or 'do_hit' in vm.calls)
                                self.assertEqual(hit, expected and not (duck and kind == 4),
                                                 (kind, direction, travel, player_move,
                                                  old_relative, duck))

    def test_pose_transition_disables_sweep_but_not_direct_overlap(self):
        for platform in ('NES', 'TI994A', 'COLECOVISION'):
            for previous, current, x, killed in ((0, 0, 80, 1),
                                                (2, 0, 80, 0),
                                                (1, 0, 80, 0),
                                                (0, 2, 80, 0),
                                                (2, 2, 80, 0),
                                                (2, 0, 95, 1)):
                vm = Basic(platform=platform)
                vm.values.update(klv=0, klx=100, kjh=0, klst=current,
                                 kprev=previous, ospp=30, fdv=3)
                vm.arrays['obk'][0] = vm.constants['OB_PLANE']
                vm.arrays['obd'][0] = 0
                vm.arrays['obx'][0] = x
                vm.run('coll_obst')
                self.assertEqual(vm.values['dead'], killed,
                                 (platform, previous, current, x))

    def test_spacing_gate_rejects_fast_cart_pairs(self):
        import checkspace
        bad = SOURCE.replace('IF krk > 10 THEN ocsp = 96', 'IF krk > 10 THEN ocsp = 192')
        self.assertNotEqual(bad, SOURCE)
        original_read = checkspace.read
        with patch.object(checkspace, 'read', lambda path: bad if path == checkspace.BAS
                          else original_read(path)), redirect_stdout(io.StringIO()) as output:
            self.assertEqual(checkspace.main(), 1)
        self.assertIn('too far apart', output.getvalue())

    def test_late_plane_allows_three_footsteps_between_ducks(self):
        # 100 ms to release after a plane clears, the real duck-release pass,
        # then three 14-pixel footfalls and one additional update of margin.
        # Test both approach directions and fractional accumulator phases.
        stride = int(re.search(r'IF sfw > (\d+) THEN', SOURCE)[1]) + 1
        vm = Basic()
        vm.stubs.add('try_esc')

        def trial(speed, frames, walk_phase, plane_phase, direction):
            vm.values.clear()
            vm.arrays.clear()
            vm.calls.clear()
            vm.values.update(klsc=3, klv=0, klx=120, klst=2, ind=1,
                             inr=1-direction, inl=direction, opsp=speed,
                             fdv=frames, kacc=walk_phase, oacp=plane_phase)
            vm.arrays['obk'][0] = 4
            vm.arrays['obx'][0] = 108 if direction == 0 else 132
            vm.arrays['obd'][0] = direction

            def tick():
                vm.run('move_kelly')
                vm.run('upd_obst')
                vm.run('coll_obst')

            for _ in range(6 // frames):
                tick()
            vm.values['ind'] = 0
            tick()  # current production duck-release delay
            for _ in range(30):
                if abs(vm.values['klx'] - 120) >= 3 * stride or vm.values['dead']:
                    break
                tick()
            tick()  # leave one more update to press down again
            cleared = not vm.values['dead']
            vm.values['ind'] = 1
            for _ in range(12):
                tick()
            return cleared and not vm.values['dead']

        for frames in (2, 3):
            for walk_phase in (0, 21, 42, 63):
                for plane_phase in (0, 21, 42, 63):
                    for direction in (0, 1):
                        self.assertTrue(trial(speeds(SOURCE, 16)[4] // 2, frames,
                                              walk_phase, plane_phase, direction),
                                        (frames, walk_phase, plane_phase, direction))
        self.assertFalse(trial(192, 3, 0, 0, 0), 'old level-16 speed must fail')

    def test_jump_hitbox_tracks_drawn_feet_without_lowering_hat(self):
        # Use the editable art as the independent boundary, not JUMPTUCK.
        def ink_rows(name):
            rows = [r for r in Path(__file__).with_name(name).read_text().splitlines()
                    if re.fullmatch(r'[.#0-]{16}', r)]
            return [i for i, row in enumerate(rows) if set(row) != {'.'}]
        stand = ink_rows('kelly-run1.txt')
        jump = ink_rows('kelly-run2.txt')
        tuck = max(stand) - max(jump)
        self.assertEqual(tuck, 2)
        self.assertEqual(min(stand), min(jump))
        self.assertIn('IF klst = ST_JUMP THEN kb = P_KRUN2', SOURCE)
        for platform in ('NES', 'TI994A', 'COLECOVISION'):
            vm = Basic(platform=platform)
            vm.stubs.add('do_hit')
            for state in ('ST_RUN', 'ST_JUMP', 'ST_DUCK'):
                for lift in range(15):
                    # All hazard kinds; sweep ball height across both edges.
                    for kind in (1, 2, 3, 4):
                        for ball_bottom in range(32) if kind == 2 else (0,):
                            vm.values.update(klv=0, klx=100, kjh=lift, dead=0,
                                             klst=vm.constants[state], fdv=1)
                            vm.calls.clear()
                            vm.arrays['obht'][0] = 0
                            vm.arrays['obk'][0] = kind
                            vm.arrays['obx'][0] = 100
                            vm.arrays['obh'][0] = ball_bottom
                            vm.run('coll_obst')
                            feet = lift + (tuck if state == 'ST_JUMP' else 0)
                            hat = lift + (11 if state == 'ST_DUCK' else 24)
                            low, high = {1: (0, 12), 2: (ball_bottom + 2, ball_bottom + 6),
                                         3: (0, 8), 4: (20, 30)}[kind]
                            expected = feet < high and low < hat
                            self.assertEqual(vm.values['kfh'], feet)
                            self.assertEqual(vm.values['ktop'], hat)
                            self.assertEqual(bool(vm.values['dead'] or 'do_hit' in vm.calls),
                                             expected, (platform, state, lift, kind, ball_bottom))


if __name__ == '__main__':
    unittest.main()
