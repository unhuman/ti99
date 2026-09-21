#!/usr/bin/env python3
"""NES-native 2bpp store tiles and screen attributes, derived from live art.

Grey is shared colour zero. P0: green/black/gold; P1: blue/pink/gold;
P2: orange/black/gold; P3: green/blue/gold. Buildings and pillars therefore
stay grey in every palette. Fixtures with black outlines switch back to P0.
"""
from pathlib import Path
import re
import genart as art
import genstore as store

SKY_ROWS = {'SKY0': 0, 'BLDGM0': 0, 'BLDGW0': 0,
            'SKY1': 1, 'BLDGM1': 1,
            'SKY2': 2, 'BLDGL': 2, 'BLDGH': 2}


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
    if tile_row < 2:
        row = tile_row*8+y
        density = (0, 0, 0, 0, 2, 4, 6, 8, 8, 10, 12, 14, 16, 16, 16, 16)[row]
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
    result = []
    for name, code, pattern, fg, bg in art.CHARS:
        bits = art.char_bytes(pattern)
        rows = colours_by_row[(code-96)*8:(code-95)*8]
        pixels = [[ink[(rows[y] >> 4) if bits[y] & (128 >> x) else (rows[y] & 15)]
                   for x in range(8)] for y in range(8)]
        if name in ('SHELFT', 'SHELFB'):
            pixels = shelf[:8] if name == 'SHELFT' else shelf[8:]
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


def attributes(screen):
    # One palette number per 16x16 quadrant, then pack four into each byte.
    quads = [[0] * 16 for _ in range(16)]
    for y in range(3):  # HUD plus first two skyline tile rows (PPU rows 4,5)
        quads[y] = [1] * 16
    quads[3] = [2] * 16  # skyline rows 6,7; orange then gold, grey buildings
    templates = dict(store.TEMPLATES)
    for level, start in enumerate((19, 14, 9)):
        tilemap = templates[store.INDEX[level][screen]]
        for y, row in enumerate(tilemap):
            for x, tile in enumerate(row):
                if tile in (store.SHELFT, store.SHELFB):
                    quads[(start + y) // 2][x // 2] = 3
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
        art.emit(f, 'nes_attrs', [v for s in range(8) for v in attributes(s)],
                 'eight screens, 64 attribute bytes each; fixtures mask to P0')


if __name__ == '__main__':
    main()
