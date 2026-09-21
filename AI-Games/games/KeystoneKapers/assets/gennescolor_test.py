"""Check palette sharing, generated colours and the real fixture-mask assembly."""
from pathlib import Path
import re
import unittest
import genart as art
import genstore as store
import gennescolor as colour
import checkink

HERE = Path(__file__).resolve().parent


def execute(source, names, memory):
    """Execute the actual small shim routines; reject unmodelled instructions."""
    code, labels = [], {}
    for line in source.splitlines():
        line = line.split(';')[0].strip()
        if not line:
            continue
        if ':' in line:
            name, line = line.split(':', 1)
            labels[name] = len(code)
            line = line.strip()
            if line.startswith('DB '):
                values = [int(x.replace('$', '0x'), 0) for x in line[3:].split(',')]
                memory[names[name]:names[name]+len(values)] = values
                continue
        if line:
            code.append(line.split(maxsplit=1))
    registers = {'A': 0, 'X': 0, 'Y': 0}
    carry, zero, negative, pc = 0, False, False, 0
    stack = []

    def address(token):
        parts = token.split(',')
        base = parts[0].split('+')
        return (int(base[0][1:], 16) if base[0].startswith('$') else names[base[0]]) + (int(base[1]) if len(base) > 1 else 0) + (
            registers[parts[1]] if len(parts) > 1 else 0)

    def operand(token):
        return int(token[1:].replace('$', '0x'), 0) if token.startswith('#') else memory[address(token)]

    for _ in range(500):
        op, *rest = code[pc]
        arg = rest[0] if rest else ''
        pc += 1
        if op == 'RTS':
            assert not stack
            return memory
        if op in ('LDA', 'LDX', 'LDY'):
            registers[op[-1]] = operand(arg)
        elif op == 'STA':
            memory[address(arg)] = registers['A']
        elif op == 'CLC':
            carry = 0
        elif op == 'ADC':
            result = registers['A'] + operand(arg) + carry
            carry = int(result > 255)
            registers['A'] = result & 255
        elif op in ('ASL', 'LSR'):
            old = registers['A']
            carry = (old >> 7) if op == 'ASL' else old & 1
            registers['A'] = ((old << 1) & 255) if op == 'ASL' else old >> 1
        elif op == 'AND':
            registers['A'] &= operand(arg)
        elif op == 'ORA':
            registers['A'] |= operand(arg)
        elif op in ('TXA', 'TAX', 'TAY'):
            registers[op[2]] = registers[op[1]]
        elif op == 'PHA':
            stack.append(registers['A'])
        elif op == 'PLA':
            registers['A'] = stack.pop()
        elif op in ('INX', 'DEX', 'DEY'):
            reg = op[-1]
            registers[reg] = (registers[reg] + (1 if op == 'INX' else -1)) & 255
        elif op in ('CPX', 'CPY'):
            zero = registers[op[-1]] == operand(arg)
        elif op in ('BNE', 'BEQ', 'BPL'):
            if {'BNE': not zero, 'BEQ': zero, 'BPL': not negative}[op]:
                pc = labels[arg]
        else:
            raise AssertionError('unmodelled instruction ' + op)
        if op in ('LDA', 'LDX', 'LDY', 'TXA', 'TAX', 'TAY', 'INX', 'DEX', 'DEY',
                  'ADC', 'AND', 'ORA', 'ASL', 'LSR', 'PLA'):
            reg = op[-1] if op in ('LDA', 'LDX', 'LDY', 'INX', 'DEX', 'DEY') else (op[2] if op in ('TXA', 'TAX', 'TAY') else 'A')
            zero = registers[reg] == 0
            negative = bool(registers[reg] & 128)
    raise AssertionError('mask routine did not return')


def fixture_mask(vram, initial):
    source = (HERE / 'nes_chr.asm').read_text().split('nes_fixture_pal:', 1)[1]
    source = source.split('nes_attrs_put:', 1)[0]
    names = {'cvb_#PVA': 0x10, 'pointer': 0x12, 'temp': 0x14,
             'array_NESB': 0x100, 'nes_fixture_offsets': 0x200,
             'nes_fixture_masks': 0x210}
    memory = [0] * 0x300
    memory[0x10:0x12] = [vram & 255, vram >> 8]
    memory[0x100:0x140] = initial
    return execute(source, names, memory)[0x100:0x140]


class ColourTest(unittest.TestCase):
    def test_generated_data_is_current(self):
        text = (HERE.parent / 'src/nescolor.bas').read_text()
        for label, expected in [('nes_store_col', colour.colours()),
                                ('nes_attrs', sum([colour.attributes(s) for s in range(8)], []))]:
            block = text.split(label + ':', 1)[1].split('\n\n', 1)[0]
            actual = [int(v, 16) for v in re.findall(r'\$([0-9A-Fa-f]{2})', block)]
            self.assertEqual(actual, expected)

    def test_hats_remain_black_and_right_justified(self):
        source = (HERE / 'nes_chr.asm').read_text()
        draw = source.split('nes_hats:', 1)[1].split('nes_hats_hide:', 1)[0]
        hide = source.split('nes_hats_hide:', 1)[1]
        basic = (HERE.parent / 'src/KEYSTONE.bas').read_text()
        self.assertRegex(basic, r'PALETTE 21,15\b')  # black sprite palette 1
        for spare in range(256):
            memory = [0xAB] * 0x300
            memory[0x10] = spare
            result = execute(draw, {'cvb_SPARE': 0x10}, memory)
            visible = []
            for slot in range(56, 61):
                y, tile, palette, x = result[0x200+slot*4:0x204+slot*4]
                if y != 240:
                    visible.append(x)
                    self.assertEqual((y, tile, palette), (15, 199, 1))
            self.assertEqual(visible, list(range(256-min(spare, 5)*8, 256, 8)))
            self.assertEqual(result[0x200:0x2E0], [0xAB]*224)
            self.assertEqual(result[0x2F4:0x300], [0xAB]*12)
            hidden = execute(hide, {}, result)
            self.assertEqual(hidden[0x2E0:0x2F4:4], [240]*5)
        data = (HERE.parent / 'src/nescolor.bas').read_text().split('hud_hat_pat:', 1)[1].split('\n\n', 1)[0]
        actual = [int(v, 16) for v in re.findall(r'\$([0-9A-Fa-f]{2})', data)]
        hat = next(pattern for name, code, pattern, fg, bg in art.CHARS if name == 'KOPIC')
        self.assertEqual(actual, art.char_bytes(hat) + [0]*8)

    def test_counter_and_structure_roles(self):
        ink = checkink.read_inkmap()
        self.assertEqual((ink[art.GRAY], ink[art.BLACK], ink[art.STORE_BG], ink[art.LYELL], ink[art.DRED]),
                         (0, 2, 1, 3, 0))
        colours = colour.colours()
        for name, code, pattern, fg, bg in art.CHARS:
            rows = colours[(code-96)*8:(code-95)*8]
            if name == 'SHELFT':
                self.assertEqual([ink[v >> 4] for v in rows], [3]*3 + [2]*5)
            elif name == 'SHELFB':
                self.assertEqual([ink[v >> 4] for v in rows], [2]*8)
            elif name == 'COUNTR':
                self.assertEqual([ink[v >> 4] for v in rows], [0]*8)
        for screen in range(8):
            attrs = colour.attributes(screen)
            for level, start in enumerate((19, 14, 9)):
                tilemap = dict(store.TEMPLATES)[store.INDEX[level][screen]]
                for row, tiles in enumerate(tilemap):
                    for col, tile in enumerate(tiles):
                        if tile in (store.SHELFT, store.SHELFB):
                            y = start + row
                            value = attrs[(y//4)*8+col//4]
                            self.assertEqual((value >> ((y & 2)*2 + (col & 2))) & 3, 3)

    def test_fixture_masks_only_its_quadrants(self):
        # Includes odd alignment and page crossings; preserve unrelated
        # quadrants, and compose correctly when several fixtures share a byte.
        for row in range(29):
            for col in range(31):
                initial = [255] * 64
                expected = initial[:]
                for y in (row, row+1):
                    for x in (col, col+1):
                        index = y//4*8 + x//4
                        expected[index] &= 255 ^ (3 << ((y & 2)*2 + (x & 2)))
                actual = fixture_mask(0x2000 + row*32 + col, initial)
                self.assertEqual(actual, expected, (row, col))
                self.assertEqual(fixture_mask(0x2000 + row*32 + col, actual), expected)


if __name__ == '__main__':
    unittest.main()
