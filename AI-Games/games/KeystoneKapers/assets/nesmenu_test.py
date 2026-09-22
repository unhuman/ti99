"""Execute the actual NES menu assembly with scripted controller frames."""
from collections import defaultdict, deque
from pathlib import Path
import unittest

from looptiming_test import platform_source

HERE = Path(__file__).parent
BASIC = HERE.parent.joinpath('src/KEYSTONE.bas').read_text()
SHIM = HERE.joinpath('nes_chr.asm').read_text()
MENU = SHIM.split('nes_title_code:', 1)[1].split('; Brown suitcase', 1)[0]
MENU = 'nes_title_code:' + MENU


class Menu:
    def __init__(self, source=MENU):
        self.mem = defaultdict(int)
        self.code, self.labels, self.data = [], {}, {}
        self.frames, self.writes = deque(), []
        label = None
        for raw in source.splitlines():
            line = raw.split(';')[0].strip()
            if line.endswith(':'):
                label = line[:-1]
                self.labels[label] = len(self.code)
            elif line.startswith('DB '):
                self.data[label] = [int(x) for x in line[3:].split(',')]
            elif line:
                self.code.append(line.split(maxsplit=1))

    def run(self, name):
        r, returns = dict(A=0, X=0, Y=0), []
        pc, carry, zero = self.labels[name], False, False

        def value(arg):
            if arg.startswith('#'):
                return int(arg[1:].replace('$', '0x'), 0)
            if ',' in arg:
                base, index = arg.split(',')
                return self.data[base][r[index]]
            return self.mem[arg]

        for _ in range(20000):
            op, *args = self.code[pc]
            arg = args[0] if args else ''
            pc += 1
            if op in ('LDA', 'LDX', 'LDY'):
                r[op[-1]] = value(arg)
                zero = r[op[-1]] == 0
            elif op in ('STA', 'STX', 'STY'):
                self.mem[arg] = r[op[-1]]
            elif op in ('CMP', 'CPY'):
                v = r['A' if op == 'CMP' else 'Y']
                zero, carry = v == value(arg), v >= value(arg)
            elif op == 'AND':
                r['A'] &= value(arg)
                zero = r['A'] == 0
            elif op in ('INC', 'DEC'):
                self.mem[arg] = (self.mem[arg] + (1 if op == 'INC' else -1)) & 255
                zero = self.mem[arg] == 0
            elif op == 'INY':
                r['Y'] = (r['Y'] + 1) & 255
                zero = r['Y'] == 0
            elif op in ('TYA', 'TAX'):
                r[op[2]] = r[op[1]]
                zero = r[op[2]] == 0
            elif op == 'CLC':
                carry = False
            elif op in ('ADC', 'SBC'):
                n = r['A'] + value(arg) + carry if op == 'ADC' else r['A'] - value(arg) - (not carry)
                carry = n > 255 if op == 'ADC' else n >= 0
                r['A'] = n & 255
                zero = r['A'] == 0
            elif op in ('BEQ', 'BNE', 'BCC'):
                if {'BEQ': zero, 'BNE': not zero, 'BCC': not carry}[op]:
                    pc = self.labels[arg]
            elif op in ('JSR', 'JMP'):
                if arg == 'wait':
                    if not self.frames:
                        raise AssertionError('Menu waits beyond supplied input')
                    self.mem['joy1_data'] = self.frames.popleft()
                elif arg == 'WRTVRM':
                    self.writes.append((r['A'] + 256*r['Y'], r['X']))
                    # Runtime scratch/registers need not survive a VRAM call.
                    r.update(A=171, X=172, Y=173)
                    if op == 'JMP':
                        if not returns:
                            return
                        pc = returns.pop()
                else:
                    if op == 'JSR':
                        returns.append(pc)
                    pc = self.labels[arg]
            elif op == 'RTS':
                if not returns:
                    return
                pc = returns.pop()
            else:
                raise AssertionError('Unmodelled menu opcode: ' + op)
        raise AssertionError('Menu failed to return')

    def inputs(self, values):
        for value in values:
            self.mem['joy1_data'] = value
            self.run('nes_title_code')


class MenuTest(unittest.TestCase):
    def test_setup_restores_title_attributes_after_cls(self):
        from levelplay_test import Basic
        vm = Basic(BASIC, 'NES')
        vm.run('setup838')
        self.assertEqual([vm.memory[9152+i] for i in range(64)], [170]*64)
        self.assertEqual(vm.calls[:2], ['SCREEN DISABLE', 'WAIT'])
        self.assertIn('SCREEN ENABLE', vm.calls)
        broken = BASIC.replace('GOSUB title_background', '', 2)
        vm = Basic(broken, 'NES')
        vm.run('setup838')
        self.assertEqual([vm.memory[9152+i] for i in range(64)], [0]*64)

    def test_entry_order_holds_and_wrong_inputs(self):
        vm = Menu()
        vm.inputs([8]*8 + [0, 2, 2, 0, 1, 1, 0, 4])
        self.assertEqual(vm.mem['cvb_T838'], 4)
        for wrong in (1, 4, 3, 9, 128, 64):
            vm = Menu()
            vm.inputs([8, 0, wrong, 0, 2, 0, 1, 0, 4])
            self.assertNotEqual(vm.mem['cvb_T838'], 4)
        vm = Menu()
        vm.inputs([8, 0, 2, 0, 8, 0, 2, 0, 1, 0, 4])
        self.assertEqual(vm.mem['cvb_T838'], 4)

    def test_selection_limits_holds_release_and_decimal_display(self):
        for maximum, initial, address in ((9, 3, 8465), (17, 1, 8529)):
            for direction, expected in ((1, maximum), (2, maximum), (4, 1), (8, 1)):
                vm = Menu()
                vm.mem.update({'cvb_SK': initial, 'cvb_SUT': maximum,
                               'cvb_#SUA': address & 255, 'cvb_#SUA+1': address >> 8})
                # Entry direction must be released. Short holds count once.
                vm.frames.extend([4, 4, 0] + [direction, direction, direction, 0]*25 + [128, 128, 0])
                vm.run('nes_choose')
                self.assertEqual(vm.mem['cvb_SK'], expected)
                self.assertFalse(vm.frames)
                self.assertEqual(vm.writes[-2:], [(address, 48+expected//10), (address+1, 48+expected%10)])

    def test_defaults_confirm_with_either_fire_button(self):
        for button in (64, 128):
            vm = Menu()
            vm.mem.update({'cvb_SK': 3, 'cvb_SUT': 9, 'cvb_#SUA': 16, 'cvb_#SUA+1': 33})
            vm.frames.extend([button, 0, button, button, 0])
            vm.run('nes_choose')
            self.assertFalse(vm.frames)
            self.assertEqual(vm.mem['cvb_SK'], 3)

    def test_held_directions_repeat_at_quarter_second_intervals(self):
        for direction, sign in ((1, 1), (2, 1), (4, -1), (8, -1)):
            for duration, changes in ((1, 1), (15, 1), (16, 2), (30, 2), (31, 3)):
                vm = Menu()
                vm.mem.update({'cvb_SK': 5, 'cvb_SUT': 9})
                vm.frames.extend([0] + [direction]*duration + [64, 64, 0])
                vm.run('nes_choose')
                self.assertEqual(vm.mem['cvb_SK'], 5+sign*changes)
                self.assertFalse(vm.frames)

    def test_direction_change_and_new_press_do_not_wait_for_repeat(self):
        vm = Menu()
        vm.mem.update({'cvb_SK': 5, 'cvb_SUT': 9})
        vm.frames.extend([0, 1, 2, 0, 2, 128, 0])
        vm.run('nes_choose')
        self.assertEqual(vm.mem['cvb_SK'], 8)

    def test_release_regression_is_detectable(self):
        broken = MENU.replace('JSR nes_menu_release', 'JSR wait', 1)
        vm = Menu(broken)
        vm.mem.update({'cvb_SK': 3, 'cvb_SUT': 9})
        vm.frames.extend([4, 4, 0, 128, 0])
        vm.run('nes_choose')
        self.assertNotEqual(vm.mem['cvb_SK'], 3)

    def test_platform_guards(self):
        for platform in ('TI994A', 'COLECOVISION'):
            code = platform_source(BASIC, platform)
            self.assertNotIn('ASM JSR nes_choose', code)
            self.assertNotIn('ASM JSR nes_title_code', code)
            self.assertIn('IF t838 = 3 THEN', code)
            self.assertIn('sk = cont1.key', code)
            self.assertNotIn('nes_cancel:', code)
            self.assertNotIn('IF cont1.key = 11 THEN RETURN', code)
        code = platform_source(BASIC, 'NES')
        self.assertIn('ASM JSR nes_choose', code)
        self.assertNotIn('sk = cont1.key', code)
        self.assertNotIn('tk = cont1.key', code)
        self.assertIn('IF cont1.key = 11 THEN RETURN', code)
        self.assertIn('IF cont1.key = 11 THEN GOTO btn_rel', code)
        main = code.split('main:', 1)[1]
        self.assertLess(main.index('IF cont1.key = 10 THEN GOTO nes_cancel'),
                        main.index('IF hfz = 0 THEN'))

    def test_cancel_stops_sound_without_recording_a_score(self):
        from levelplay_test import Basic
        for flags in range(4):
            for score in (99, 100, 101):
                vm = Basic(platform='NES')
                vm.stubs.update(('snd_off', 'boot'))
                vm.values.update({'#score': score, '#hi': 100, 'scmark': flags,
                                  'kops0': 9, 'krk0': 17})
                vm.run('nes_cancel')
                self.assertEqual(vm.calls, ['snd_off'])
                self.assertEqual((vm.values['#hi'], vm.values['scmark']), (100, flags))
                self.assertEqual(vm.values['#score'], score)
                self.assertEqual((vm.values['kops0'], vm.values['krk0']), (0, 0))

    def test_hud_counts_clear_previous_display_and_preserve_spacing(self):
        from levelplay_test import Basic
        from genfont import glyph_bytes
        self.assertEqual(glyph_bytes('*')[:2], [0, 0])  # lowercase x-height
        self.assertNotEqual(glyph_bytes('*'), glyph_bytes('X'))
        for platform, base in (('NES', 8256), ('TI994A', 6144), ('COLECOVISION', 6144)):
            vm = Basic(platform=platform)
            vm.memory.update({base+i: 99 for i in range(32)})
            for total in list(range(10)) + list(range(9, -1, -1)):
                vm.values['kops'] = total
                vm.run('hud_kops')
                spare = max(0, total-1)
                hat = 32 if platform == 'NES' else 155
                expected = [32, 32, hat, 42, 48+spare] if spare > 5 else [32]*(5-spare)+[hat]*spare
                self.assertEqual([vm.memory[base+i] for i in range(25, 30)], expected)
                self.assertTrue(all(vm.memory[base+i] == 99 for i in list(range(25))+[30, 31]))

    def test_address_checker_rejects_menu_offset_and_guard_regressions(self):
        import checknes
        import io
        import tempfile
        from contextlib import redirect_stdout
        from unittest.mock import patch
        for replacement in ('8464', '6321', '8529'):
            broken = BASIC.replace('#sua = 8465', '#sua = '+replacement, 1)
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory)/'KEYSTONE.bas'
                path.write_text(broken)
                with patch.object(checknes, 'BAS', str(path)), redirect_stdout(io.StringIO()):
                    self.assertEqual(checknes.main(), 1)


if __name__ == '__main__':
    unittest.main()
