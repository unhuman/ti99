"""Exercise the actual TI cancel-key assembly against the keyboard matrix."""
from pathlib import Path
import unittest

from looptiming_test import platform_source

BASIC = Path(__file__).parent.parent.joinpath('src/KEYSTONE.bas').read_text()


def scan(columns):
    helper = BASIC.split('ti_cancel_key:', 1)[1].split('score_start:', 1)[0]
    code = [s.strip()[4:] for s in helper.splitlines() if s.strip().startswith('ASM ')]
    labels = {s.rstrip(':'): i for i, s in enumerate(code) if s.endswith(':')}
    regs = {f'R{i}': 0 for i in range(16)}
    pc, col, irq, result, equal = 0, None, 2, 0, False
    for _ in range(100):
        if pc == len(code):
            assert irq == 2
            return result
        line = code[pc]
        pc += 1
        if line.endswith(':'):
            continue
        op, arg = line.split(' ', 1)
        parts = arg.split(',')
        if op == 'LIMI':
            irq = int(arg)
        elif op == 'LI':
            regs[parts[0]] = int(parts[1][1:], 16)
        elif op == 'CLR':
            regs[arg] = 0
        elif op == 'LDCR':
            assert irq == 0 and regs['R12'] == 0x24 and parts[1] == '3'
            col = (regs[parts[0]] >> 8) & 7
        elif op == 'SRC':
            r, count = parts[0], int(parts[1])
            regs[r] = ((regs[r] >> count) | (regs[r] << (16-count))) & 65535
        elif op == 'STCR':
            assert irq == 0 and regs['R12'] == 6 and parts[1] == '8'
            regs[parts[0]] = columns[col] << 8
        elif op == 'CZC':
            equal = (regs[parts[0]] & regs[parts[1]]) == 0
        elif op in ('JEQ', 'JNE'):
            if equal == (op == 'JEQ'):
                pc = labels[arg]
        elif op == 'MOVB':
            if parts[1] == '@cvb_TK':
                result = regs[parts[0]] >> 8
            else:
                assert parts == ['@cvb_TK', 'R0']
                regs['R0'] = result << 8
                equal = result == 0
        else:
            raise AssertionError(line)
    raise AssertionError('scan did not terminate')


class CancelKeys(unittest.TestCase):
    def test_keypad_setup_cancel_discards_each_partial_entry(self):
        from collections import deque
        from levelplay_test import Basic

        class Input(Basic):
            def value(self, expression):
                if expression == 'keyval':
                    return self.keys.popleft()
                return super().value(expression)

        for cancel in (10, 11):
            for prefix in ([], [15, 5], [15, 5, 15, 0]):
                for release in ([], [15]):
                    vm = Input(BASIC.replace('cont1.key', 'keyval'), 'COLECOVISION')
                    vm.keys = deque(prefix + release + [cancel])
                    vm.stubs.update(('title_draw', 'title_wait'))
                    vm.values.update({'kops0': 9, 'krk0': 17, '#score': 99,
                                      '#hi': 100, 'scmark': 2})
                    vm.run('title_setup')
                    self.assertFalse(vm.keys)
                    self.assertEqual((vm.values['kops0'], vm.values['krk0']), (0, 0))
                    self.assertEqual((vm.values['#score'], vm.values['#hi'], vm.values['scmark']),
                                     (99, 100, 2))
                    self.assertIn('title_draw', vm.calls)
                    base = 8192 if vm.platform == 'NES' else 6144
                    prompt = base + (681 + 96 if vm.platform == 'NES' else 681)
                    self.assertEqual(''.join(chr(vm.memory[prompt+i]) for i in range(13)),
                                     'FIRE TO START')

    def test_coleco_cancellation_preserves_scores(self):
        from levelplay_test import Basic
        code = platform_source(BASIC, 'COLECOVISION')
        for key in (10, 11):
            self.assertIn(f'IF cont1.key = {key} THEN GOTO cv_cancel', code)
        for score in (99, 100, 101):
            vm = Basic(platform='COLECOVISION')
            vm.stubs.update(('snd_off', 'boot'))
            vm.values.update({'#score': score, '#hi': 100, 'scmark': 2,
                              'kops0': 9, 'krk0': 17})
            vm.run('cv_cancel')
            self.assertEqual(vm.calls, ['snd_off'])
            self.assertEqual((vm.values['#score'], vm.values['#hi'], vm.values['scmark']),
                             (score, 100, 2))
            self.assertEqual((vm.values['kops0'], vm.values['krk0']), (0, 0))

    def test_modifier_and_digit_combinations(self):
        for modifiers in range(256):
            for back in (False, True):
                for redo in (False, True):
                    columns = [modifiers, 255 ^ (8 if back else 0),
                               255 ^ (8 if redo else 0)]
                    self.assertEqual(scan(columns), int(not modifiers & 16 and (back or redo)))

    def test_other_keys_do_not_cancel(self):
        for column in (1, 2):
            for row in range(8):
                cols = [239, 255, 255]
                cols[column] ^= 1 << row
                self.assertEqual(scan(cols), int(row == 3))

    def test_platform_and_bank_guards(self):
        for platform in ('NES', 'COLECOVISION'):
            self.assertNotIn('ti_cancel_key', platform_source(BASIC, platform))
        code = platform_source(BASIC, 'TI994A')
        self.assertIn('BANK SELECT 2\nGOSUB ti_cancel_key\nBANK SELECT 1\nIF tk THEN GOTO boot', code)
        self.assertGreater(code.index('ti_cancel_key:'), code.index('BANK 2'))
        helper = code.split('ti_cancel_key:', 1)[1].split('score_start:', 1)[0]
        self.assertNotIn('score_record', helper)
        self.assertIn('GOSUB snd_off', helper)
        self.assertIn('kops0 = 0', helper)
        self.assertIn('krk0 = 0', helper)
        self.assertIn('ASM MOVB @cvb_TK,R0\nIF tk THEN', helper)
        self.assertTrue(helper.rstrip().endswith('RETURN'))


if __name__ == '__main__':
    unittest.main()
