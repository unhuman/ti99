"""Check palette sharing, generated colours and the real fixture-mask assembly."""
from pathlib import Path
import re
import itertools
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
        elif op == 'SEC':
            carry = 1
        elif op == 'SBC':
            result = registers['A'] - operand(arg) - (1-carry)
            carry = int(result >= 0)
            registers['A'] = result & 255
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
        elif op in ('INX', 'INY', 'DEX', 'DEY'):
            reg = op[-1]
            registers[reg] = (registers[reg] + (1 if op in ('INX', 'INY') else -1)) & 255
        elif op in ('CPX', 'CPY', 'CMP'):
            result = registers['A' if op == 'CMP' else op[-1]] - operand(arg)
            zero = result == 0
            carry = int(result >= 0)
            negative = bool(result & 128)
        elif op == 'JMP':
            pc = labels[arg]
        elif op in ('BNE', 'BEQ', 'BPL', 'BCC'):
            if {'BNE': not zero, 'BEQ': zero, 'BPL': not negative, 'BCC': not carry}[op]:
                pc = labels[arg]
        else:
            raise AssertionError('unmodelled instruction ' + op)
        if op in ('LDA', 'LDX', 'LDY', 'TXA', 'TAX', 'TAY', 'INX', 'INY', 'DEX', 'DEY',
                  'ADC', 'SBC', 'AND', 'ORA', 'ASL', 'LSR', 'PLA'):
            reg = op[-1] if op in ('LDA', 'LDX', 'LDY', 'INX', 'INY', 'DEX', 'DEY') else (op[2] if op in ('TXA', 'TAX', 'TAY') else 'A')
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
    def test_door_block_matches_previous_cell_addresses(self):
        from checkvblank import nes_lines
        source = (HERE.parent / 'src/KEYSTONE.bas').read_text()
        bases = {int(i): int(v) for i, v in
                 re.findall(r'#bdst\((\d)\) = (\d+)', source)}
        column = int(re.search(r'CONST ELCOL = (\d+)', source)[1])
        body = source.split('draw_car:', 1)[1].split('car_cell:', 1)[0].splitlines()
        live = nes_lines(body)
        body = [line.split("'", 1)[0].strip() for i, line in enumerate(body) if i in live]
        start = body.index('cst = 0')
        end = next(i for i, line in enumerate(body) if line.startswith('SCREEN '))
        args = body[end].split(' ', 1)[1].split(',')
        self.assertEqual(args[0], 'lift_nes_cells')
        width, height, stride = map(int, args[3:])
        cells = colour.lift_cells()
        for floor, moving_floor, door in itertools.product(range(3), repeat=3):
            state = {'clv': floor, 'elvl': moving_floor, 'eldp': door, 'ELCOL': column}
            def value(expr):
                expr = expr.replace('#bdst(clv)', str(bases[floor]))
                expr = re.sub(r'(\d+)\.', r'\1', expr)
                expr = re.sub(r'#[a-z]+|[a-z]+|ELCOL', lambda m: str(state[m[0]]), expr)
                self.assertRegex(expr, r'^[0-9 +*=-]+$')
                return eval(expr.replace(' = ', ' == '), {'__builtins__': {}})
            for line in body[start:end]:
                if not line:
                    continue
                if line.startswith('IF '):
                    condition, line = line[3:].split(' THEN ')
                    if not value(condition):
                        continue
                name, expr = line.split(' = ')
                state[name] = value(expr)
            offset, destination = value(args[1]), 8192 + value(args[2])
            actual = {destination + y*32 + x: cells[offset+y*stride+x]
                      for y in range(height) for x in range(width)}
            cst = door if floor == moving_floor else 0
            expected = {8288+bases[floor]+y*32+column+x: cells[cst*16+y*4+x]
                        for y in range(4) for x in range(4)}
            self.assertEqual(actual, expected)

    def test_generated_data_is_current(self):
        text = (HERE.parent / 'src/nescolor.bas').read_text()
        for label, expected in [('store_nes_chr', colour.store_chr()),
                                ('detail_nes_chr', colour.detail_chr()),
                                ('suitcase_nes_chr', colour.suitcase_chr()),
                                ('lift_nes_cells', colour.lift_cells()),
                                ('blank_nes_row', [colour.DETAIL_CODES['SKYCAP']]*32),
                                ('floor_nes_row', [colour.DETAIL_CODES['FLOOR0']]*32),
                                ('nes_attrs', sum([colour.attributes(s) for s in range(8)], []))]:
            block = text.split(label + ':', 1)[1].split('\n\n', 1)[0]
            actual = [int(v, 16) for v in re.findall(r'\$([0-9A-Fa-f]{2})', block)]
            self.assertEqual(actual, expected)

    def test_suitcase_overlay_uses_only_its_oam_and_disappears_on_collection(self):
        source = (HERE / 'nes_chr.asm').read_text().split('nes_suitcases:', 1)[1]
        for kinds in itertools.product(range(4), repeat=4):
            memory = [0xAB]*0x400
            columns, floors = [0, 15, 30, 31], [184, 144, 104, 64]
            memory[0x10:0x14] = kinds
            memory[0x20:0x24] = columns
            memory[0x30:0x34] = floors
            result = execute(source, {'array_COK':0x10, 'array_COC':0x20,
                                     'array_FLRY':0x30}, memory)
            self.assertEqual(result[0x200:0x2B0], [0xAB]*176)
            self.assertEqual(result[0x2D0:0x300], [0xAB]*48)
            for band, kind in enumerate(kinds):
                left = result[0x2B0+band*8:0x2B4+band*8]
                right = result[0x2B4+band*8:0x2B8+band*8]
                if kind == 2:
                    self.assertEqual(left, [floors[band]-17, 93, 1, columns[band]*8])
                    self.assertEqual(right, [240 if columns[band]==31 else floors[band]-17,
                                             95, 1, (columns[band]*8+8)&255])
                else:
                    self.assertEqual((left[0],right[0]), (240,240))

    def test_suitcase_brown_pixels_match_ti_outline_exactly(self):
        tiles = colour.suitcase_chr()
        source = {name: pattern for name, code, pattern, fg, bg in art.CHARS}
        for i, name in enumerate(('CASETL','CASEBL','CASETR','CASEBR')):
            tile = tiles[i*16:(i+1)*16]
            self.assertEqual(tile[:8], [0]*8)
            self.assertEqual(tile[8:], art.char_bytes(source[name]))
        basic = (HERE.parent/'src/KEYSTONE.bas').read_text()
        self.assertRegex(basic, r'PALETTE 22,23\b')
        draw = basic.split('draw_actors:',1)[1].split('hide_play:',1)[0]
        self.assertLess(draw.index('ASM JSR nes_oam2'), draw.index('ASM JSR nes_suitcases'))

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
            for slot in range(56, 64):
                y, tile, palette, x = result[0x200+slot*4:0x204+slot*4]
                if y != 240:
                    visible.append(x)
                    self.assertEqual((y, tile, palette), (15, 199, 1))
            self.assertEqual(visible, [216] if spare > 5 else list(range(240-spare*8, 240, 8)))
            self.assertEqual(result[0x200:0x2E0], [0xAB]*224)
            hidden = execute(hide, {}, result)
            self.assertEqual(hidden[0x2E0:0x300:4], [240]*8)
        data = (HERE.parent / 'src/nescolor.bas').read_text().split('hud_hat_pat:', 1)[1].split('\n\n', 1)[0]
        actual = [int(v, 16) for v in re.findall(r'\$([0-9A-Fa-f]{2})', data)]
        hat = next(pattern for name, code, pattern, fg, bg in art.CHARS if name == 'KOPIC')
        self.assertEqual(actual, art.char_bytes(hat) + [0]*8)

    def test_native_tiles_preserve_non_shelf_and_non_sky_pixels(self):
        tiles = colour.store_pixels()
        packed = colour.store_chr()
        self.assertEqual(len(packed), 89*16)
        ink = checkink.read_inkmap()
        old_rows = colour.colours()
        for index, (name, code, pattern, fg, bg) in enumerate(art.CHARS):
            data = packed[index*16:(index+1)*16]
            decoded = [[((data[y] >> (7-x)) & 1) |
                        (((data[y+8] >> (7-x)) & 1) << 1)
                        for x in range(8)] for y in range(8)]
            self.assertEqual(decoded, tiles[index])
            original_bits = art.char_bytes(pattern)
            original_colours = art.colour_block(name, fg, bg)
            for y in range(8):
                for x in range(8):
                    if name in ('SHELFT', 'SHELFB') or name in colour.ELEVATOR_NAMES:
                        continue
                    if name in colour.SKY_ROWS and original_colours[y] & 15 != art.GRAY and not original_bits[y] & (128 >> x):
                        continue
                    row = old_rows[index*8+y]
                    old = ink[row >> 4 if original_bits[y] & (128 >> x) else row & 15]
                    self.assertEqual(decoded[y][x], old, (name, x, y))
        shelf = colour.read_shelf()
        self.assertTrue(any(set(row) == {0, 1, 2, 3} for row in shelf),
                        'The book spines must exercise all four NES inks on one row')
        # All rows retain a dark blue structure beneath the two-pixel cap.
        self.assertEqual(shelf[0], [3]*8)
        self.assertEqual(shelf[1], [0]*8)
        self.assertEqual(shelf[-1], [2]*8)

    def test_elevator_openings_and_thresholds(self):
        pixels = {code: tile for code, tile in enumerate(colour.store_pixels(), 96)}
        pixels.update({code: tile for code, tile in
                       zip(colour.DETAIL_CODES.values(), colour.detail_tiles())})
        cells = colour.lift_cells()
        self.assertEqual(len(cells), 48)
        views = []
        for state in range(3):
            view = [[pixels[cells[state*16+(y//8)*4+x//8]][y%8][x%8]
                     for x in range(32)] for y in range(32)]
            views.append(view)
            self.assertEqual(view[:4], [[0]*32]*4)  # fixed lintel height
            self.assertEqual(view[4], [3]*32)
            self.assertEqual(view[30:], [[3]*32]*2)  # fixed two-pixel sill
        closed, partial, opened = views
        self.assertEqual(closed[10][15:17], [2, 2])  # closed centre seam
        self.assertEqual(partial[10][8:24], [2]*16)
        self.assertNotEqual(partial[10][:8], [2]*8)
        self.assertNotEqual(partial[10][24:], [2]*8)
        self.assertEqual(opened[10], [2]*32)
        self.assertEqual(opened[20], [3]*32)  # back-wall handrail
        self.assertEqual(partial[20][8:24], [3]*16)
        for name, columns in [('EJAMBL', range(4)), ('EJAMBR', range(4, 8))]:
            tile = pixels[art.CODES[name]]
            self.assertTrue(all(row[x] == 1 for row in tile for x in columns))

    def test_elevator_reader_rejects_bad_sections(self):
        valid = (HERE / 'nes-elevator.txt').read_text()
        for bad in (valid.replace('[ECAR]', '[NO_SUCH_TILE]'),
                    valid+'\n[EDOOR]\n', valid.replace('GGGGBSYS', 'BAD'),
                    valid.split('[LIFTRAIL]')[0]):
            with self.assertRaises(ValueError):
                colour.read_elevator(bad)

    def test_navy_trim_matches_across_store_and_shelf_palettes(self):
        basic = (HERE.parent / 'src/KEYSTONE.bas').read_text()
        values = {int(index): int(value) for index, value in
                  re.findall(r'^\s*PALETTE\s+(\d+),(\d+)', basic, re.M)}
        self.assertEqual((values[2], values[14]), (15, 1))
        # Skyline index 2 is unused by buildings/gradient (skymessage_test);
        # navy there supplies the message's third row. Other colours persist.
        for index, value in {1:26, 3:40, 5:1, 6:36, 7:40, 9:38, 10:1,
                             11:40, 13:26, 15:40, 17:18, 21:15, 25:39,
                             26:16, 27:22, 29:48}.items():
            self.assertEqual(values[index], value, index)

    def test_ground_trim_changes_only_the_bottom_three_pixels(self):
        normal = colour.store_pixels()[art.CODES['SLAB']-96]
        bottom = colour.detail_tiles()[0]
        self.assertEqual(normal[:5], bottom[:5])
        self.assertEqual(bottom[5:], [[2]*8]*3)
        for screen in range(8):
            tilemap = dict(store.TEMPLATES)[store.INDEX[0][screen]]
            self.assertEqual(tilemap[4], [store.SLAB]*32)

    def test_animated_escalators_keep_shared_colours(self):
        ink = checkink.read_inkmap()
        actual = colour.store_pixels()
        for name, code, pattern, fg, bg in art.CHARS:
            if not 110 <= code < 122:
                continue
            bits = art.char_bytes(pattern)
            rows = art.colour_block(name, fg, bg)
            expected = [[ink[rows[y] >> 4 if bits[y] & (128 >> x) else rows[y] & 15]
                         for x in range(8)] for y in range(8)]
            self.assertEqual(actual[code-96], expected, name)

    def test_shelf_reader_rejects_broken_art(self):
        for bad in ('B'*8+'\n', ('B'*7+'\n')*16, ('X'*8+'\n')*16,
                    ('B'*8+'\n')*17):
            with self.assertRaises(ValueError):
                colour.read_shelf(bad)

    def test_sky_gradient_retains_end_colours(self):
        tiles = colour.store_pixels()
        top = tiles[art.CODES['SKY0']-96]
        middle = tiles[art.CODES['SKY1']-96]
        bottom = tiles[art.CODES['SKY2']-96]
        cap = colour.detail_tiles()[-1]
        self.assertEqual(cap[:4], [[1]*8]*4)
        self.assertTrue(any(2 in row for row in cap[4:]))
        self.assertTrue(any(2 in row for row in top[:4]))
        self.assertEqual(middle[-1], [2]*8)
        self.assertEqual(bottom[-1], [3]*8)
        self.assertTrue(any(len(set(row)) == 2 for row in top+middle))
        self.assertTrue(any(len(set(row)) == 2 for row in bottom))

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

    def test_trim_preserves_black_escalators_and_radios(self):
        # Inspect the actual generated attributes after the real fixture mask.
        for screen in range(8):
            initial = colour.attributes(screen)
            tilemap = dict(store.TEMPLATES)[store.INDEX[0][screen]]
            for row, tiles in enumerate(tilemap):
                for col, tile in enumerate(tiles):
                    if 110 <= tile < 122:
                        y = 19 + row
                        value = initial[y//4*8+col//4]
                        self.assertEqual((value >> ((y & 2)*2+(col & 2))) & 3, 0)
            for col in store.RADIO_COLS:
                actual = fixture_mask(0x2000+21*32+col, initial)
                for y in (21, 22):
                    for x in (col, col+1):
                        value = actual[y//4*8+x//4]
                        self.assertEqual((value >> ((y & 2)*2+(x & 2))) & 3, 0)

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
