"""The result and GAME OVER boxes: where they stand, and their NES colours.

The result boxes stand on the third floor (rows 6-8) and GAME OVER on the
second (rows 11-13), on every target (DESIGN.md sections 59-61). On the NES each
box's colours are four attribute bytes over two attribute rows, and the halves
it does not cover are written as CONSTANT P0 -- which is only right if they
are P0 on every screen. That is checked here against the generated
attributes, so a store change that breaks it fails the build instead of
recolouring scenery around a box.
"""
from pathlib import Path
import re
import unittest
import genart
import gennescolor
import gentitle
from levelplay_test import Basic


class SkyMessageTest(unittest.TestCase):
    def test_positions_and_symmetric_border(self):
        for nes in (False, True):
            for name in gentitle.MESSAGES:
                runs = gentitle.runs_of(name, nes)
                expected = 11 if name == 'msg_over' else 6
                self.assertEqual(runs[0][0], expected, (name, nes))
                self.assertEqual([len(text) for _, _, text in runs], [16]*3)
                self.assertEqual(runs[0][2], ' '*16)
                self.assertEqual(runs[2][2], ' '*16)

    def test_the_only_half_left_alone_is_p0_on_every_screen(self):
        # attribute row 4 (PPU 16-19): the lower half, under GAME OVER. The
        # result box covers attribute row 2 whole.
        for screen in range(8):
            a = gennescolor.attributes(screen)
            for col in range(2, 6):
                self.assertEqual(a[4 * 8 + col] & 240, 0, (screen, col))

    def test_p3_is_p0_but_for_black_so_the_slab_keeps_its_colours(self):
        source = Path(__file__).parents[1].joinpath('src/KEYSTONE.bas').read_text()
        for p0, p3 in ((1, 13), (3, 15)):
            v0 = re.search(r'PALETTE %d,(\d+)' % p0, source)[1]
            v3 = re.search(r'PALETTE %d,(\d+)' % p3, source)[1]
            self.assertEqual(v0, v3, (p0, p3))
        # and P3's index 2 is P1's paper, the box's own blue
        self.assertEqual(re.search(r'PALETTE 14,(\d+)', source)[1],
                         re.search(r'PALETTE 5,(\d+)', source)[1])

    def test_p3_index_2_is_the_navy_border(self):
        source = Path(__file__).parents[1].joinpath('src/KEYSTONE.bas').read_text()
        self.assertIn('PALETTE 14,1', source)
        pixels = gennescolor.store_pixels()
        self.assertEqual(pixels[genart.CODES['ECAR']-96], [[2]*8 for _ in range(8)])

    def test_nes_boxatt_writes_exactly_the_box(self):
        source = Path(__file__).parents[1].joinpath('src/KEYSTONE.bas').read_text()
        for nav, second, border, line in ((9170, False, 8488, 0), (9178, True, 8712, 2)):
            vm = Basic(source, 'NES')
            vm.values.update({'#nav': nav})
            vm.run('nes_boxatt')
            want = set(range(nav, nav + 4)) | set(range(border, border + 16))
            if second:
                want |= set(range(nav + 8, nav + 12))
            self.assertEqual(set(vm.memory), want, nav)
            self.assertEqual([vm.memory[i] for i in range(nav, nav + 4)], [95]*4)
            if second:
                self.assertEqual([vm.memory[i] for i in range(nav + 8, nav + 12)], [15]*4)
            # the navy row: the result box's TOP row, GAME OVER's bottom one
            name = 'msg_over' if second else 'msg_timeup'
            row = gentitle.runs_of(name, True)[line][0] + 3
            self.assertEqual(border, 8192 + row * 32 + gentitle.BOX_COL)
            # and the box's attribute row is the one holding its first row
            first = gentitle.runs_of(name, True)[0][0] + 3
            self.assertEqual(nav, 9152 + (first // 4) * 8 + gentitle.BOX_COL // 4)


if __name__ == '__main__':
    unittest.main()
