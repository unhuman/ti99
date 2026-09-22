"""Skyline messages preserve the HUD and every pixel outside their box."""
from pathlib import Path
import unittest
import genart
import genstore
import gentitle
import gennescolor
from levelplay_test import Basic


class SkyMessageTest(unittest.TestCase):
    def test_positions_and_symmetric_border(self):
        for nes in (False, True):
            offset, hud = (3, 2) if nes else (0, 0)
            for name in gentitle.MESSAGES:
                runs = gentitle.runs_of(name, nes)
                expected = (14 if nes else 11) if name == 'msg_over' else hud+2
                self.assertEqual(runs[0][0]+offset, expected)
                self.assertEqual([len(text) for _, _, text in runs], [16]*3)
                self.assertEqual(runs[0][2], ' '*16)
                self.assertEqual(runs[2][2], ' '*16)

    def test_nes_palette_change_cannot_recolour_existing_skyline(self):
        source = Path(__file__).parents[1].joinpath('src/KEYSTONE.bas').read_text()
        self.assertIn('PALETTE 10,1', source)
        pixels = gennescolor.store_pixels()
        for screen in range(8):
            attrs = gennescolor.attributes(screen)
            self.assertEqual(attrs[10:14], [165]*4)
            roof = dict(genstore.TEMPLATES)['T_ROOF'+str(screen)]
            # P2 occupies exactly these skyline rows. Its index 2 was unused.
            for row in (2, 3):
                for code in roof[row]:
                    self.assertNotIn(2, [v for r in pixels[code-96] for v in r])
        self.assertEqual(pixels[genart.CODES['ECAR']-96], [[2]*8 for _ in range(8)])
        vm = Basic(source, 'NES')
        vm.values.update({'#nav': 9162, 'ch_ecar': genart.CODES['ECAR']})
        vm.run('nes_boxatt')
        self.assertEqual(set(vm.memory), set(range(9162, 9166)) | set(range(8392, 8408)))
        self.assertEqual([vm.memory[i] for i in range(9162, 9166)], [165]*4)
        vm = Basic(source, 'NES')
        original = [3, 0, 12, 15, 0, 240, 160, 80]
        vm.arrays['nmsg'].update(enumerate(
            (original[i] & 15) | (original[i+4] & 240) for i in range(4)))
        vm.values.update({'#nav': 9178, 'ch_ecar': genart.CODES['ECAR']})
        vm.run('nes_boxatt')
        self.assertEqual(set(vm.memory), set(range(9178, 9182)) |
                         set(range(9186, 9190)) | set(range(8712, 8728)))
        self.assertEqual([vm.memory[i] for i in range(9178, 9182)],
                         [(v & 15) | 80 for v in original[:4]])
        self.assertEqual([vm.memory[i] for i in range(9186, 9190)],
                         [(v & 240) | 15 for v in original[4:]])


if __name__ == '__main__':
    unittest.main()
