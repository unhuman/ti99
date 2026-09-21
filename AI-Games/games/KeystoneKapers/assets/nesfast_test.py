"""Direct redraw writes preserve source data and leave the PPU out of palettes."""
from pathlib import Path
import unittest
from nesfast import patch

HERE = Path(__file__).parent
SHIM = (HERE / 'nes_fast.asm').read_text()


def run(entry, memory, a=0, x=0, y=0):
    code, labels = [], {}
    for raw in SHIM.splitlines():
        line = raw.split(';')[0].strip()
        if line.endswith(':'):
            labels[line[:-1]] = len(code)
        elif line:
            code.append(line.split())
    r, stack, writes = dict(A=a, X=x, Y=y), [], []
    returns = []
    zero, pc = False, labels[entry]
    def value(arg):
        if arg.startswith('#'):
            literal = arg[1:].replace('$', '0x')
            if literal == 'array_NSC%256':
                return memory['array_NSC'] & 255
            if literal == 'array_NSC/256':
                return memory['array_NSC'] >> 8
            return int(literal, 0)
        if arg == '(temp),Y':
            return memory[(memory['temp'] + 256*memory['temp+1'] + r['Y']) & 65535]
        return memory[arg]
    for _ in range(20000):
        op, *args = code[pc]
        arg = args[0] if args else ''
        pc += 1
        if op == 'RTS':
            if returns:
                pc = returns.pop()
                continue
            return r, writes
        if op in ('LDA', 'LDX', 'LDY'):
            r[op[-1]] = value(arg)
        elif op in ('STA', 'STY'):
            address = ((memory['temp'] + 256*memory['temp+1'] + r['Y']) & 65535) if arg == '(temp),Y' else arg
            memory[address] = r[op[-1]]
            writes.append((address, r[op[-1]]))
        elif op in ('CMP', 'CPY'):
            zero = r['A' if op == 'CMP' else 'Y'] == value(arg)
        elif op == 'INY':
            r['Y'] = (r['Y']+1) & 255
        elif op in ('TXA', 'TYA', 'TAY'):
            r[op[2]] = r[op[1]]
        elif op == 'PHA':
            stack.append(r['A'])
        elif op == 'PLA':
            r['A'] = stack.pop()
        elif op == 'AND':
            r['A'] &= value(arg)
        elif op in ('INC', 'DEC'):
            memory[arg] = (memory[arg] + (1 if op == 'INC' else -1)) & 255
            zero = memory[arg] == 0
        elif op == 'JSR':
            assert arg == 'LDIRVM'
            returns.append(pc)
            pc = labels['nes_fast_copy']
        elif op == 'JMP':
            pc = labels[arg]
        elif op in ('BNE', 'BEQ'):
            if zero == (op == 'BEQ'):
                pc = labels[arg]
        else:
            raise AssertionError('Unmodelled opcode '+op)
        if op in ('LDA', 'LDX', 'LDY', 'INY', 'TXA', 'TYA', 'TAY', 'PLA', 'AND'):
            reg = op[-1] if op in ('LDA', 'LDX', 'LDY', 'INY') else ('Y' if op == 'TAY' else 'A')
            zero = r[reg] == 0
    raise AssertionError('Transfer did not return')


class FastTest(unittest.TestCase):
    def test_copy_lengths_and_source_page_crossing(self):
        for count in (1, 32, 64, 96, 160, 256):
            memory = {i: i & 255 for i in range(0x80f0, 0x82f0)}
            memory.update({'temp': 0xf0, 'temp+1': 0x80, 'temp2': count & 255,
                           'pointer': 0x80, 'pointer+1': 0x20})
            r, writes = run('nes_fast_copy', memory, y=73)
            self.assertEqual(r['Y'], 73)
            self.assertEqual([v for key, v in writes if key == 'PPUDATA'],
                             [(0xf0+i) & 255 for i in range(count)])
            self.assertEqual(writes[-2:], [('PPUADDR', 0), ('PPUADDR', 0)])
            self.assertEqual((memory['temp'], memory['temp+1']), (0xf0, 0x80))

    def test_pokes_keep_backdrop_black_and_park_palette_address(self):
        for address, byte, expected in ((0x3f00, 16, 15), (0x3f09, 38, 38),
                                        (0x2080, 77, 77)):
            _, writes = run('nes_fast_poke', {}, a=address & 255, y=address >> 8, x=byte)
            self.assertEqual(writes[:2], [('PPUADDR', address >> 8), ('PPUADDR', address & 255)])
            self.assertEqual([v for key, v in writes if key == 'PPUDATA'], [expected])
            self.assertEqual(writes[-2:], [('PPUADDR', 0), ('PPUADDR', 0)])

    def test_radar_shadow_and_vram_match_without_overwriting_neighbours(self):
        memory = {i: 123 for i in range(0x467, 0x769)}
        memory.update({'array_NSC': 0x468, 'cvb_#NSB': 0, 'cvb_#NSB+1': 0x1d})
        _, writes = run('nes_scan_clear', memory)
        expected = ([255]*8 + [0]*8)*48
        self.assertEqual([memory[i] for i in range(0x468, 0x768)], expected)
        self.assertEqual([v for key, v in writes if key == 'PPUDATA'], expected)
        self.assertEqual((memory[0x467], memory[0x768]), (123, 123))
        self.assertEqual([v for key, v in writes if key == 'PPUADDR'],
                         [0x1d, 0, 0, 0, 0x1e, 0, 0, 0, 0x1f, 0, 0, 0])

    def test_runtime_hooks_fail_closed_and_leave_normal_path(self):
        stub = 'WRTVRM:\noriginal_poke\nLDIRVM:\noriginal_copy\nwait:\noriginal_wait\n\t; Load sprites\nppu_work\n\t; Read controllers\ninput_work\n'
        result = patch(stub)
        self.assertIn('BIT mode\n\tBMI.L nes_fast_poke\noriginal_poke', result)
        self.assertIn('BIT mode\n\tBMI.L nes_fast_copy\noriginal_copy', result)
        self.assertIn('BMI.L .fast_skip', result)
        self.assertIn('.fast_skip:\n\t; Read controllers\ninput_work', result)
        with self.assertRaises(ValueError):
            patch(stub.replace('; Read controllers', '; changed runtime'))
        with self.assertRaises(ValueError):
            patch(stub + '\nwait:\n')


if __name__ == '__main__':
    unittest.main()
