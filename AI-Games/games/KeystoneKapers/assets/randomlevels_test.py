"""Execute production random-map generation, loading and lifetime rules."""
from pathlib import Path
import re
import unittest
from levelplay_test import Basic
import genstore

SOURCE = Path(__file__).parents[1].joinpath('src/KEYSTONE.bas').read_text()


def machine(platform='NES', source=SOURCE):
    vm = Basic(source, platform)
    vm.addresses['random_hazards'] = 2048
    data = re.search(r'random_hazards:\s*DATA BYTE ([\d,]+)', source)[1]
    vm.memory.update(enumerate(map(int, data.split(',')), 2048))
    vm.memory.update(enumerate(genstore.levels(), 4096))
    vm.values.update({'#stlv': 4096, 'hsc': 255})
    vm.arrays['lv8'].update(enumerate([0, 8, 16, 24]))
    return vm


def layout(vm):
    result = []
    for i in range(32):
        vm.values['lix'] = i
        vm.run('random_get')
        result.append(vm.values['lby'])
    return result


def count(v):
    return 0 if not v else 3 if v == 11 else 2 if v & 8 else 1


class RandomLevelTest(unittest.TestCase):
    def test_variety_safety_counts_and_actual_screen_loading(self):
        for platform in ('NES', 'TI994A', 'COLECOVISION'):
            vm = machine(platform)
            vm.values['krk'] = 17
            layouts, totals = set(), set()
            for seed in range(32):
                vm.rng.seed(seed)
                vm.run('reset_prizes')
                row = layout(vm)
                layouts.add(tuple(row))
                totals.add(sum(map(count, row)))
                self.assertTrue(set(row) <= {0, 1, 2, 3, 4, 9, 10, 11})
                for band, value in enumerate(row):
                    screen, floor = band % 8, band // 8
                    if screen in (0, 7):
                        self.assertEqual(value, 0)
                    if floor == 3:
                        self.assertIn(value, (0, 1, 9))
                    if screen == 3:
                        self.assertNotEqual(value & 7, 3)
                for screen in range(8):
                    self.assertLessEqual(sum(count(row[i]) for i in range(screen, 32, 8)), 9)
                    vm.values['klsc'] = screen
                    vm.run('load_band')
                    for floor in range(4):
                        expected = row[floor*8+screen]
                        slots = (2*floor, 2*floor+1, 8+floor)
                        kinds = [vm.arrays['obk'][i] for i in slots if vm.arrays['obk'][i]]
                        self.assertEqual(kinds, [expected & 7]*count(expected))
                    self.assertEqual(layout(vm), row)  # crossings cannot reroll
            self.assertEqual(len(layouts), 32)
            self.assertGreater(len(totals), 3)  # not a permutation of 31 hazards

    def test_new_games_wins_and_deaths(self):
        for platform in ('NES', 'TI994A', 'COLECOVISION'):
            vm = machine(platform)
            vm.stubs.add('start_krook')
            vm.values['krk0'] = 17
            vm.run('new_game')
            first = layout(vm)
            self.assertTrue(any(first))
            if platform == 'TI994A':
                self.assertEqual([c for c in vm.calls if c.startswith('bank:')], ['bank:2', 'bank:1'])
            # Execute the retry setup while stubbing only rendering/sound work.
            vm.stubs.discard('start_krook')
            start = SOURCE.split('start_krook:', 1)[1].split('draw_screen:', 1)[0]
            vm.stubs.update(set(re.findall(r'GOSUB (\w+)', start)) - {'reset_prizes', 'random_level'})
            vm.run('start_krook')
            self.assertEqual(layout(vm), first)
            capture = SOURCE.split('do_catch:', 1)[1].split('bonus_count:', 1)[0]
            tail = capture[capture.index('\tkrk = krk + 1'):]
            winner = machine(platform, 'advance:\n'+tail+'\n'+SOURCE)
            winner.stubs.update(('start_krook', 'main'))
            winner.values['krk'] = 17
            winner.rng.seed(123)
            winner.run('advance')
            self.assertTrue(any(layout(winner)))
            self.assertNotEqual(layout(winner), first)
            winner.values['krk'] = 16
            winner.run('advance')
            self.assertEqual(winner.values['krk'], 17)
            self.assertTrue(any(layout(winner)))

    def test_early_levels_do_not_generate(self):
        vm = machine()
        vm.arrays['rhaz'].update(enumerate([171]*16))
        for level in range(1, 17):
            vm.values['krk'] = level
            vm.run('reset_prizes')
            self.assertEqual(list(vm.arrays['rhaz'].values()), [171]*16)

    def test_ti_generator_and_its_data_share_bank_two(self):
        from looptiming_test import platform_source
        bank, placement = 0, {}
        for line in platform_source(SOURCE, 'TI994A').splitlines():
            if re.fullmatch(r'BANK \d+', line):
                bank = int(line.split()[1])
            if line.endswith(':'):
                placement[line[:-1]] = bank
        for label in ('random_level', 'random_set', 'random_hazards'):
            self.assertEqual(placement[label], 2)
        self.assertEqual(placement['random_get'], 0)

    def test_nes_time_blink_never_erases_gradient(self):
        vm = machine()
        vm.stubs.add('hud_time')
        vm.memory.update({8192+i: 207 for i in range(64, 128)})
        vm.values.update(tsec=9, tflon=1, fphs=0)
        vm.run('tick_flash')
        for col in (16, 17, 18, 19, 21, 22):
            self.assertEqual(vm.memory[8192+64+col], 32)
        self.assertTrue(all(vm.memory[8192+i] == 207 for i in range(96, 128)))
        vm.values['fphs'] = 16
        vm.run('tick_flash')
        self.assertEqual(''.join(chr(vm.memory[8192+64+i]) for i in range(16, 20)), 'TIME')
        self.assertTrue(all(vm.memory[8192+i] == 207 for i in range(96, 128)))

    def test_old_blink_offset_is_a_negative_control(self):
        broken = SOURCE.replace('PRINT AT 16 + 64,"    "', 'PRINT AT 16 + 96,"    "')
        self.assertNotEqual(broken, SOURCE)
        vm = machine(source=broken)
        vm.memory.update({8192+i: 207 for i in range(96, 128)})
        vm.values.update(tsec=9, tflon=1, fphs=0)
        vm.run('tick_flash')
        self.assertFalse(all(vm.memory[8192+i] == 207 for i in range(96, 128)))


if __name__ == '__main__':
    unittest.main()
