"""Execute score-origin lifetime and rendered markers on every target."""
import unittest
from levelplay_test import Basic
from genfont import glyph_bytes
from looptiming_test import platform_source
from levelplay_test import SOURCE


class ScoreMarksTest(unittest.TestCase):
    def test_ti_score_helpers_have_bank_selected_at_each_entry(self):
        source = platform_source(SOURCE, 'TI994A')
        bank = source.rindex('BANK 2')
        for helper in ('score_start', 'score_mark', 'title_score', 'score_record'):
            self.assertGreater(source.index(helper+':'), bank)
        # title_draw calls title_score, and on the TI the whole title (title_draw
        # .. title_setup) now LIVES in bank 2, so bank 2 is mapped at that call by
        # construction. What must hold instead: the title is inside the bank-2
        # region, boot maps bank 2 immediately before entering it, and nothing in
        # it switches banks (a BANK SELECT there would unmap the running code).
        bank_end = source.index('BANK 1', bank)
        for routine in ('title_draw:', 'title_input:', 'title_wait:', 'title_setup:'):
            self.assertTrue(bank < source.index(routine) < bank_end, routine)
        title = source[source.index('title_draw:'):source.index('title_setup:')]
        title_setup = source[source.index('title_setup:'):bank_end].split('RETURN\n')
        self.assertNotIn('BANK SELECT', title)
        self.assertNotIn('BANK SELECT', ''.join(title_setup[:2]))
        self.assertLess(title.index('GOSUB title_score'), len(title))
        boot = source[source.index('\nboot:'):]
        call = boot.index('GOSUB title_draw')
        self.assertTrue(boot[:call].rstrip().endswith('BANK SELECT 2'))
        for caller, helper in (('new_game', 'score_start'), ('hud_all', 'score_mark'), ('lose_kop', 'score_record')):
            call = source.index('GOSUB '+helper, source.index(caller+':'))
            self.assertTrue(source[:call].rstrip().endswith('BANK SELECT 2'))
            following = source[call:].splitlines()[1:]
            self.assertEqual(next(line.strip() for line in following if line.strip()), 'BANK SELECT 1')

    def test_setup_defaults_still_mark_and_normal_restart_preserves_record(self):
        for platform in ('NES', 'TI994A', 'COLECOVISION'):
            for previous in range(4):
                for setup in (False, True):
                    vm = Basic(platform=platform)
                    vm.stubs.update(('reset_prizes', 'start_krook'))
                    vm.values.update(scmark=previous, kops0=3 if setup else 0,
                                     krk0=1 if setup else 0)
                    vm.run('new_game')
                    self.assertEqual(vm.values['scmark'], (previous & 2) | int(setup))
                    self.assertEqual(vm.values['kops'], 3)
                    self.assertEqual(vm.values['krk'], 1)

    def test_record_inherits_origin_and_unmarked_score_wins_ties(self):
        for platform in ('NES', 'TI994A', 'COLECOVISION'):
            for flags in range(4):
                for score in (99, 100, 101):
                    vm = Basic(platform=platform)
                    vm.values.update({'scmark': flags, '#score': score, '#hi': 100})
                    vm.run('score_record')
                    self.assertEqual(vm.values['#hi'], max(100, score))
                    expected = 3 * (flags & 1) if score > 100 else flags
                    if score == 100 and flags == 2:
                        expected = 0
                    self.assertEqual(vm.values['scmark'], expected)

    def test_title_and_hud_markers_do_not_touch_digits_or_spacing(self):
        for platform in ('NES', 'TI994A', 'COLECOVISION'):
            title_base = 8288 if platform == 'NES' else 6144
            hud_base = 8256 if platform == 'NES' else 6144
            for flags in range(4):
                vm = Basic(platform=platform)
                vm.values.update({'scmark': flags, '#score': 65535, '#hi': 65535})
                vm.memory.update({title_base+i: 32 for i in range(32)})
                vm.run('title_score')
                for column, bit in ((8, 1), (23, 2)):
                    self.assertEqual(''.join(chr(vm.memory[title_base+column+i])
                                             for i in range(6)), '655350')
                    self.assertEqual(vm.memory[title_base+column+6], 60 if flags & bit else 32)
                vm.stubs.update(('hud_time', 'hud_kops'))
                vm.memory.update({hud_base+i: 32 for i in range(32)})
                vm.run('hud_all')
                self.assertEqual(vm.memory[hud_base+14], 60 if flags & 1 else 32)
                self.assertEqual(vm.memory[hud_base+15], 32)
                self.assertEqual(''.join(chr(vm.memory[hud_base+i]) for i in range(16, 20)), 'TIME')
                vm.memory[hud_base+14] = 99
                vm.run('hud_score')
                self.assertEqual(vm.memory[hud_base+14], 99, 'score updates must leave static marker alone')

    def test_marker_glyph_preserves_lowercase_reserve_x(self):
        self.assertNotEqual(glyph_bytes('<'), glyph_bytes('*'))
        self.assertTrue(any(glyph_bytes('<')))
        self.assertNotEqual(glyph_bytes('<')[0], 0)
        self.assertEqual(glyph_bytes('<')[5:], [0, 0, 0])
        self.assertEqual(glyph_bytes('*')[:2], [0, 0])


if __name__ == '__main__':
    unittest.main()
