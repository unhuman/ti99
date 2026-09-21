#!/usr/bin/env python3
"""NES-native 2bpp store tiles and screen attributes, derived from live art.

Grey is shared colour zero. P0: green/black/gold; P1: navy/pink/gold;
P2: orange/black/gold; P3: green/navy/gold. Buildings and pillars therefore
stay grey in every palette. Fixtures with black outlines switch back to P0.
"""
from pathlib import Path
import re
import genart as art
import genstore as store

SKY_ROWS = {'SKY0': 0, 'BLDGM0': 0, 'BLDGW0': 0,
            'SKY1': 1, 'BLDGM1': 1,
            'SKY2': 2, 'BLDGL': 2, 'BLDGH': 2}


DETAIL_BASE = 200
DETAIL_NAMES = ('FLOOR0', 'EDGEL', 'EDGER', 'EDGESL', 'EDGESR',
                'LIFTLINTEL', 'LIFTRAIL', 'SKYCAP')
DETAIL_CODES = {name: DETAIL_BASE+i for i, name in enumerate(DETAIL_NAMES)}
ELEVATOR_NAMES = ('EDOOR', 'ECAR', 'ECARS', 'EDOORS', 'ECART', 'EJAMBL',
                  'EJAMBR', 'LIFTLINTEL', 'LIFTRAIL')


def read_elevator(text=None):
    if text is None:
        text = Path(__file__).with_name('nes-elevator.txt').read_text()
    blocks, current = {}, None
    indices = {'S': 0, 'G': 1, 'B': 2, 'Y': 3}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('[') and line.endswith(']'):
            current = line[1:-1]
            if current not in ELEVATOR_NAMES or current in blocks:
                raise ValueError('Unknown or duplicate elevator tile: '+current)
            blocks[current] = []
        else:
            if current is None or len(line) != 8 or any(p not in indices for p in line):
                raise ValueError('Elevator art needs named 8-pixel S/G/B/Y rows')
            blocks[current].append([indices[p] for p in line])
    if set(blocks) != set(ELEVATOR_NAMES) or any(len(rows) != 8 for rows in blocks.values()):
        raise ValueError('Elevator art needs all nine named 8x8 tiles')
    return blocks


def colours():
    """The committed colour conversion, before native shelf/sky overrides."""
    out = []
    for name, code, pattern, fg, bg in art.CHARS:
        rows = art.colour_block(name, fg, bg)
        if name in SKY_ROWS:
            skyrow = SKY_ROWS[name]
            for y, value in enumerate(rows):
                if value & 15 != art.GRAY:
                    # These source colours encode indices 1, 2 and 3 under
                    # nes_inkmap; their actual hues come from P1/P2.
                    paper = art.MGREEN if skyrow == 0 else art.BLACK
                    if skyrow == 2:
                        paper = art.MGREEN if y < 4 else art.LYELL
                    rows[y] = (value & 240) | paper
        if name == 'SHELFT':
            rows = [0xB1] * 3 + [0x11] * 5  # gold lip, blue body in P3
        elif name == 'SHELFB':
            rows = [0x11] * 8
        out.extend(rows)
    return out


def read_shelf(text=None):
    if text is None:
        text = Path(__file__).with_name('nes-shelf.txt').read_text()
    lines = [line.strip() for line in text.splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    if len(lines) != 16 or any(len(line) != 8 for line in lines):
        raise ValueError('nes-shelf.txt must contain exactly sixteen 8-pixel rows')
    indices = {'S': 0, 'G': 1, 'B': 2, 'Y': 3}
    if any(pixel not in indices for row in lines for pixel in row):
        raise ValueError('nes-shelf.txt allows only S, G, B and Y pixels')
    return [[indices[pixel] for pixel in row] for row in lines]


def pack_tile(pixels):
    """Native NES 2bpp: eight rows of plane 0, then eight of plane 1."""
    return [sum(((pixel >> plane) & 1) << (7-x) for x, pixel in enumerate(row))
            for plane in (0, 1) for row in pixels]


def sky_pixel(tile_row, x, y):
    # The 4x4 ordered pattern adds intermediate blends without new palettes.
    bayer = ((0, 8, 2, 10), (12, 4, 14, 6),
             (3, 11, 1, 9), (15, 7, 13, 5))
    if tile_row == -1:
        # PPU row 3 lies between the HUD and buildings. Keep its upper
        # half blue, then begin the pink blend halfway through the gap.
        density = (0, 0, 0, 0, 1, 2, 3, 4)[y]
        return 2 if bayer[y & 3][x & 3] < density else 1
    if tile_row < 2:
        row = tile_row*8+y
        density = (4, 6, 8, 8, 10, 10, 12, 12, 12, 14, 14, 16, 16, 16, 16, 16)[row]
        return 2 if bayer[y & 3][x & 3] < density else 1
    density = (0, 2, 4, 6, 10, 12, 14, 16)[y]
    return 3 if bayer[y & 3][x & 3] < density else 1


def store_pixels():
    source = Path(__file__).with_name('nes_chr.asm').read_text().split('nes_inkmap:', 1)[1]
    values = re.search(r'^\s*DB\s+([0-9,]+)', source, re.M).group(1)
    ink = [int(value) for value in values.split(',')]
    assert len(ink) == 16
    colours_by_row = colours()
    shelf = read_shelf()
    elevator = read_elevator()
    result = []
    for name, code, pattern, fg, bg in art.CHARS:
        bits = art.char_bytes(pattern)
        rows = colours_by_row[(code-96)*8:(code-95)*8]
        pixels = [[ink[(rows[y] >> 4) if bits[y] & (128 >> x) else (rows[y] & 15)]
                   for x in range(8)] for y in range(8)]
        if name in ('SHELFT', 'SHELFB'):
            pixels = shelf[:8] if name == 'SHELFT' else shelf[8:]
        elif name in elevator:
            pixels = elevator[name]
        elif name in SKY_ROWS:
            original = art.colour_block(name, fg, bg)
            for y in range(8):
                for x in range(8):
                    # Only sky PAPER changes. Keep silhouettes and windows.
                    if original[y] & 15 != art.GRAY and not bits[y] & (128 >> x):
                        pixels[y][x] = sky_pixel(SKY_ROWS[name], x, y)
        result.append(pixels)
    return result


def store_chr():
    return [value for pixels in store_pixels() for value in pack_tile(pixels)]


def detail_tiles():
    elevator = read_elevator()
    floor = [row[:] for row in store_pixels()[art.CODES['SLAB']-96]]
    for row in floor[5:]:
        for x, pixel in enumerate(row):
            if pixel == 1:
                row[x] = 2
    result = [floor]
    for name in ('EDOOR', 'EDOORS'):
        for x in (7, 0):
            rows = [row[:] for row in elevator[name]]
            for row in rows[:(6 if name == 'EDOORS' else 8)]:
                row[x] = 2
            result.append(rows)
    result.extend(elevator[name] for name in ('LIFTLINTEL', 'LIFTRAIL'))
    result.append([[sky_pixel(-1, x, y) for x in range(8)] for y in range(8)])
    return result


def detail_chr():
    return [value for pixels in detail_tiles() for value in pack_tile(pixels)]


def lift_cells():
    codes = dict(art.CODES, **DETAIL_CODES)
    states = (
        (('LIFTLINTEL',)*4,
         ('EDOOR', 'EDGEL', 'EDGER', 'EDOOR'),
         ('EDOOR', 'EDGEL', 'EDGER', 'EDOOR'),
         ('EDOORS', 'EDGESL', 'EDGESR', 'EDOORS')),
        (('LIFTLINTEL', 'ECART', 'ECART', 'LIFTLINTEL'),
         ('EDGEL', 'ECAR', 'ECAR', 'EDGER'),
         ('EDGEL', 'LIFTRAIL', 'LIFTRAIL', 'EDGER'),
         ('EDGESL', 'ECARS', 'ECARS', 'EDGESR')),
        (('ECART',)*4, ('ECAR',)*4, ('LIFTRAIL',)*4, ('ECARS',)*4),
    )
    return [codes[name] for state in states for row in state for name in row]


def suitcase_chr():
    # Outline only: index 2 uses the independent brown sprite colour.
    # Pair order for 8x16 sprites is TL/BL, TR/BR.
    chars = {name: pattern for name, code, pattern, fg, bg in art.CHARS}
    return [v for name in ('CASETL', 'CASEBL', 'CASETR', 'CASEBR')
            for v in ([0]*8 + art.char_bytes(chars[name]))]


def attributes(screen):
    # One palette number per 16x16 quadrant, then pack four into each byte.
    quads = [[0] * 16 for _ in range(16)]
    for y in range(3):  # HUD plus first two skyline tile rows (PPU rows 4,5)
        quads[y] = [1] * 16
    quads[3] = [2] * 16  # skyline rows 6,7; orange then gold, grey buildings
    quads[11] = [3] * 16  # ground-floor trim; fixture masks still win
    templates = dict(store.TEMPLATES)
    for level, start in enumerate((19, 14, 9)):
        tilemap = templates[store.INDEX[level][screen]]
        for y, row in enumerate(tilemap):
            for x, tile in enumerate(row):
                if tile in (store.SHELFT, store.SHELFB):
                    quads[(start + y) // 2][x // 2] = 3
    # Animated escalators retain P0 black, including their lowest step.
    bottom = templates[store.INDEX[0][screen]][3]
    for x, tile in enumerate(bottom):
        if 110 <= tile < 122:
            quads[11][x//2] = 0
    return [quads[y][x] | quads[y][x+1] << 2 |
            quads[y+1][x] << 4 | quads[y+1][x+1] << 6
            for y in range(0, 16, 2) for x in range(0, 16, 2)]


def main():
    path = Path(__file__).resolve().parent.parent / 'src' / 'nescolor.bas'
    with path.open('w', encoding='utf-8', newline='') as f:
        f.write("\t' GENERATED by assets/gennescolor.py; NES only.\n")
        hat = next(pattern for name, code, pattern, fg, bg in art.CHARS if name == 'KOPIC')
        art.emit(f, 'hud_hat_pat', art.char_bytes(hat) + [0]*8,
                 'NES reserve icon: CHR 198/199, used by OAM 56..60')
        art.emit(f, 'store_nes_chr', store_chr(), '89 native NES 2bpp tiles, codes 96..184')
        art.emit(f, 'suitcase_nes_chr', suitcase_chr(), 'brown outline overlay: CHR 92..95, paired vertically')
        art.emit(f, 'detail_nes_chr', detail_chr(), 'native tiles 200..207: floor trim, lift details and upper sky')
        art.emit(f, 'lift_nes_cells', lift_cells(), 'closed, partly open, open; 4x4 tiles each')
        art.emit(f, 'blank_nes_row', [DETAIL_CODES['SKYCAP']]*32, 'replace old title score row with upper sky')
        art.emit(f, 'floor_nes_row', [DETAIL_CODES['FLOOR0']]*32, 'ground-floor bar only, PPU row 23')
        art.emit(f, 'nes_attrs', [v for s in range(8) for v in attributes(s)],
                 'eight screens, 64 attribute bytes each; fixtures mask to P0')


if __name__ == '__main__':
    main()
