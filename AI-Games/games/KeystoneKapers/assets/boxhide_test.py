"""box_hide must hide exactly the actors that touch an end-of-round box.

The result boxes (GOT HIM!, HE GOT AWAY, THE BIPLANE, TIME'S UP!) stand on
the third floor, where anyone on that floor stands, and the VDP draws every sprite over
text. box_hide (KEYSTONE.bas, DESIGN.md sections 58-59) hides a figure whose sprites
touch the box and leaves the rest of the cast standing.

The production BASIC is EXECUTED (levelplay_test.Basic), and its decisions are
compared against ground truth computed here from gentitle.py's box constants and
the sprite offsets draw_actors uses -- never from box_hide's own limits, which is
the thing under test. Every position is swept, including the wrapped y of a
Kelly jumping on the roof.
"""
import unittest

import gentitle
from levelplay_test import Basic

SPRHID = 209
BOX_Y0 = gentitle.BOX_ROW * 8
BOX_Y1 = (gentitle.BOX_ROW + 3) * 8 - 1                 # three rows
BOX_X0 = gentitle.BOX_COL * 8
BOX_X1 = (gentitle.BOX_COL + gentitle.BOX_W) * 8 - 1


def touches(ys, x):
    """Ground truth: do 16x16 sprites at these y (VDP lines y+1..y+16) and x
    overlap the box?"""
    if x + 15 < BOX_X0 or x > BOX_X1:
        return False
    for y in ys:
        top = y - 256 if y >= 240 else y                # above the screen
        if top + 16 >= BOX_Y0 and top + 1 <= BOX_Y1:
            return True
    return False


def hidden(vm):
    return {c[1] for c in vm.calls if isinstance(c, tuple) and c[2] == SPRHID}


class BoxHideTest(unittest.TestCase):
    def machine(self, platform):
        vm = Basic(platform=platform)
        vm.arrays['flry'].update({0: 160, 1: 120, 2: 80, 3: 40})
        # every obstacle parked well clear, unless a test moves it
        vm.arrays['obx'].update({i: 0 for i in range(8)})
        return vm

    def test_the_box_geometry_is_the_one_the_routine_assumes(self):
        # rows 7-9 (the third floor), columns 8-23 -- DESIGN.md section 59.
        # box_hide's comments and limits are written for exactly this.
        self.assertEqual((BOX_Y0, BOX_Y1, BOX_X0, BOX_X1), (56, 79, 64, 191))

    def test_kelly_goes_whole_exactly_when_any_part_touches(self):
        for platform in ('TI994A', 'COLECOVISION'):
            vm = self.machine(platform)
            vm.values['hy2'] = 150                      # Harry clear
            for ky in list(range(0, 190, 1)) + list(range(246, 256)):
                for x in (0, 48, 49, 50, 120, 191, 192, 240):
                    ys = [(ky - 10) & 255, (ky - 5) & 255, (ky + 11) & 255]
                    vm.calls.clear()
                    vm.values.update(klx=x, kby=(ky + 11) & 255, hx=0)
                    vm.run('box_hide')
                    got = hidden(vm) & {0, 1, 2}
                    want = {0, 1, 2} if touches(ys, x) else set()
                    self.assertEqual(got, want, (platform, ky, x))

    def test_harry_goes_whole_exactly_when_any_part_touches(self):
        for platform in ('TI994A', 'COLECOVISION'):
            vm = self.machine(platform)
            vm.values['kby'] = 150                      # Kelly clear
            for hy in range(0, 180):
                for x in (0, 48, 49, 120, 191, 192):
                    ys = [(hy - 7) & 255, hy, (hy + 16) & 255]
                    vm.calls.clear()
                    vm.values.update(hx=x, hy2=(hy + 16) & 255, klx=0)
                    vm.run('box_hide')
                    got = hidden(vm) & {4, 5, 6, 7, 27}
                    want = {4, 5, 6, 7, 27} if touches(ys, x) else set()
                    self.assertEqual(got, want, (platform, hy, x))

    def test_obstacles_one_by_one(self):
        for platform in ('TI994A', 'COLECOVISION'):
            vm = self.machine(platform)
            vm.values.update(kby=150, hy2=150)
            for slot in range(8):
                for height in (0, 20):                  # 20 is the biplane
                    for x in (20, 49, 120, 191, 200):
                        vm.arrays['obx'].update({i: 0 for i in range(8)})
                        vm.arrays['obh'].update({i: 0 for i in range(8)})
                        vm.arrays['obx'][slot] = x
                        vm.arrays['obh'][slot] = height
                        vm.calls.clear()
                        vm.run('box_hide')
                        y = vm.arrays['flry'][slot // 2] - 16 - height
                        want = {slot + 8} if touches([y], x) else set()
                        self.assertEqual(hidden(vm) & set(range(8, 16)), want,
                                         (platform, slot, height, x))

    def test_both_boxes_are_guarded_on_every_target(self):
        from looptiming_test import platform_source
        from levelplay_test import SOURCE
        for platform, call in (('TI994A', 'GOSUB box_hide'),
                               ('COLECOVISION', 'GOSUB box_hide'),
                               ('NES', 'ASM JSR nes_boxhide')):
            code = platform_source(SOURCE, platform)
            for msg in ('msg_gothim', 'msg_timeup'):
                before = code[:code.index('#tta = VARPTR %s(0)' % msg)]
                self.assertIn(call, before[-400:], (platform, msg))

    def test_nes_routine_uses_the_tms_limits_moved_by_the_nes_box_offset(self):
        """nes_boxhide (6502) cannot be executed here, so its constants are
        checked against the geometry. Sprite y is a screen line on both
        machines; the NES box is at PPU row runs_of + 3 (run_list's picture
        offset), so it lies (that row * 8 - BOX_Y0) lines lower than the TMS
        box, and every limit the TMS routine uses moves by the same amount."""
        import os
        import re
        nes_row = gentitle.runs_of('msg_timeup', nes=True)[0][0] + 3
        shift = nes_row * 8 - BOX_Y0
        # The TMS routine's limits, absolute: y (or kby, hy2) from 16 lines
        # above the box's first line, to under 60 / 62 / 39 more than that.
        low = BOX_Y0 - 16
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'nes_chr.asm')
        with open(path) as fh:
            asm = fh.read()
        body = asm[asm.index('nes_boxhide:'):asm.index('nes_bhide:')]
        # Kelly's kby, Harry's hy2, an obstacle's y, then nes_bxy's floor
        self.assertEqual([int(v) for v in re.findall(r'CPY #(\d+)', body)],
                         [low + 60 + shift, low + 62 + shift, low + 39 + shift,
                          low + shift])
        self.assertEqual(re.findall(r'CMP #(\d+)', body), ['49', '192'])

    def test_nes_fill_runs_draw_the_same_box(self):
        """The NES message tables use fill runs; the production run_list must
        draw from them exactly the box the literal runs describe."""
        import re
        from pathlib import Path
        text = Path(__file__).parents[1].joinpath('src/title.bas').read_text()
        for name in gentitle.MESSAGES:
            block = re.search(r'#if NES\n%s:\n(.*?)#endif' % name, text, re.S)[1]
            data = [int(v) for v in re.findall(r'DATA BYTE ([\d,]+)', block)
                    for v in v.split(',')]
            self.assertTrue(any(b > 127 and b != 255 for b in data), name)
            vm = Basic(platform='NES')
            vm.memory.update(enumerate(data, 40000))
            vm.values['#tta'] = 40000
            vm.run('run_list')
            for row, col, line in gentitle.runs_of(name, nes=True):
                for i, ch in enumerate(line):
                    addr = 8288 + row * 32 + col + i
                    self.assertEqual(vm.memory[addr], ord(ch), (name, row, col + i))


if __name__ == '__main__':
    unittest.main()
