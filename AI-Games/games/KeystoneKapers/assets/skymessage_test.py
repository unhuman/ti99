"""The result and GAME OVER boxes: where they stand, and their NES colours.

The result boxes stand on the third floor (rows 7-9) and GAME OVER on the
second (rows 11-13), on every target (DESIGN.md section 59). On the NES each
box's colours are four attribute bytes over two attribute rows, and the halves
it does not cover are written as CONSTANT P0 -- which is only right if they
are P0 on every screen. That is checked here against the generated
attributes, so a store change that breaks it fails the build instead of
recolouring scenery around a box.
"""
from pathlib import Path
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
                expected = 11 if name == 'msg_over' else 7
                self.assertEqual(runs[0][0], expected, (name, nes))
                self.assertEqual([len(text) for _, _, text in runs], [16]*3)
                self.assertEqual(runs[0][2], ' '*16)
                self.assertEqual(runs[2][2], ' '*16)

    def test_every_half_the_boxes_leave_alone_is_p0_on_every_screen(self):
        # attribute row 2 (PPU 8-11): upper half is the roof slab over the box
        # attribute row 3 (PPU 12-15): lower half is the second floor under it
        # attribute row 4 (PPU 16-19): lower half is under GAME OVER
        for screen in range(8):
            a = gennescolor.attributes(screen)
            for col in range(2, 6):
                self.assertEqual(a[2 * 8 + col] & 15, 0, (screen, col))
                self.assertEqual(a[3 * 8 + col] & 240, 0, (screen, col))
                self.assertEqual(a[4 * 8 + col] & 240, 0, (screen, col))

    def test_p3_index_2_is_the_navy_border(self):
        source = Path(__file__).parents[1].joinpath('src/KEYSTONE.bas').read_text()
        self.assertIn('PALETTE 14,1', source)
        pixels = gennescolor.store_pixels()
        self.assertEqual(pixels[genart.CODES['ECAR']-96], [[2]*8 for _ in range(8)])

    def test_nes_boxatt_writes_exactly_the_box(self):
        source = Path(__file__).parents[1].joinpath('src/KEYSTONE.bas').read_text()
        for nav, first, border in ((9170, 80, 8584), (9178, 95, 8712)):
            vm = Basic(source, 'NES')
            vm.values.update({'#nav': nav})
            vm.run('nes_boxatt')
            self.assertEqual(set(vm.memory),
                             set(range(nav, nav + 4)) | set(range(nav + 8, nav + 12)) |
                             set(range(border, border + 16)), nav)
            self.assertEqual([vm.memory[i] for i in range(nav, nav + 4)], [first]*4)
            self.assertEqual([vm.memory[i] for i in range(nav + 8, nav + 12)], [15]*4)
            # the border row is the box's third row, in PPU coordinates
            row = gentitle.runs_of('msg_over' if nav == 9178 else 'msg_timeup', True)[2][0] + 3
            self.assertEqual(border, 8192 + row * 32 + gentitle.BOX_COL)


if __name__ == '__main__':
    unittest.main()
