#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Render the title screen offline, from the shipped table, as a PNG.

Judging this from an emulator screenshot does not work: Classic99 scales its
window to fit and CLIPS the right-hand columns at every size tried, so the one
thing a full-width marquee frame needs checking -- that it closes on the right --
is exactly what the capture cannot show.

This paints what the name table will hold, from `src/title.bas` (the bytes the
cart carries) plus the font and store patterns out of the generators, so the
layout can be checked in a second and at any zoom.

Run:  python3 prevtitle.py [out.png] [scale]
"""

import io
import os
import re
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import genart as g                                          # noqa: E402

SRC = os.path.join(HERE, os.pardir, 'src')

# TMS9918 palette, approximate sRGB -- same table preview.py uses
PAL = [
    (0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
    (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
    (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
    (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255),
]


def read_block(path, label):
    """The DATA BYTE values under `label:`."""
    txt = io.open(path, encoding='utf-8').read()
    m = re.search(r'^%s:[^\n]*\n((?:\s*DATA BYTE[^\n]*\n)+)' % label,
                  txt, re.M)
    if not m:
        raise SystemExit('prevtitle: no %s in %s' % (label, path))
    out = []
    for line in m.group(1).strip().split('\n'):
        # font.bas annotates each glyph with a trailing comment naming the
        # character it draws -- strip it before parsing numbers
        body = line.split('DATA BYTE', 1)[1].split("'")[0]
        for tok in body.split(','):
            tok = tok.strip()
            if tok:
                out.append(int(tok[1:], 16) if tok.startswith('$')
                           else int(tok))
    return out


def bits_of_bytes(vals):
    """8 rows of 8 bits from 8 pattern bytes."""
    return ["".join('#' if (v >> (7 - b)) & 1 else '.' for b in range(8))
            for v in vals]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE,
                                                             'title.png')
    scale = int(sys.argv[2]) if len(sys.argv) > 2 else 3

    table = read_block(os.path.join(SRC, 'title.bas'), 'title_tbl')

    # WHAT EACH CODE LOOKS LIKE, TAKEN FROM THE SHIPPED DATA rather than from
    # the generators' Python. The point of this previewer is to show what the
    # cart will actually draw, so it reads the same blocks the cart carries.
    font = read_block(os.path.join(SRC, 'font.bas'), 'font_bits')
    fcol = read_block(os.path.join(SRC, 'font.bas'), 'font_col')
    spat = read_block(os.path.join(SRC, 'art.bas'), 'store_pat')
    scol = read_block(os.path.join(SRC, 'art.bas'), 'store_col')

    pat, col = {}, {}
    for i in range(len(font) // 8):
        pat[32 + i] = bits_of_bytes(font[i * 8:i * 8 + 8])
        b = fcol[i * 8]
        col[32 + i] = (b >> 4, b & 15)
    for i in range(len(spat) // 8):
        pat[96 + i] = bits_of_bytes(spat[i * 8:i * 8 + 8])
        b = scol[i * 8]
        col[96 + i] = (b >> 4, b & 15)

    # THE TITLE'S DISPLAY FACE, loaded at 182 from bank 2. Without this the big
    # letters render as blanks and the preview quietly shows an empty card.
    # ONE BLOCK PER DEFINE RUN, and the CODES come from titleface rather than
    # from a base plus an index -- the face is split across two runs of the
    # character table because no single run is long enough, and a previewer
    # that assumed one contiguous block would draw the letters in the wrong
    # place while agreeing with itself.
    import titleface
    seen = 0
    for k, (start, count) in enumerate(titleface.blocks()):
        tpat = read_block(os.path.join(SRC, 'titlefont.bas'), 'tfont_pat%d' % k)
        tcol = read_block(os.path.join(SRC, 'titlefont.bas'), 'tfont_col%d' % k)
        for i in range(count):
            pat[start + i] = bits_of_bytes(tpat[i * 8:i * 8 + 8])
            b = tcol[i * 8]
            col[start + i] = (b >> 4, b & 15)
        seen += count

    # walk the display list exactly as run_list does
    name = [[32] * 32 for _ in range(24)]
    i = 0
    while i < len(table) and table[i] != 255:
        row, cl, n = table[i], table[i + 1], table[i + 2]
        i += 3
        for k in range(n):
            name[row][cl + k] = table[i + k]
        i += n

    # FIRE TO START is printed by title_input, not from the table
    for k, ch in enumerate("FIRE TO START"):
        name[20][9 + k] = ord(ch)

    W, H = 32 * 8, 24 * 8
    px = [[PAL[g.HUD_BG]] * W for _ in range(H)]
    for r in range(24):
        for c in range(32):
            code = name[r][c]
            bits = pat.get(code)
            if bits is None:
                continue
            fg, bg = col.get(code, (g.BLACK, g.HUD_BG))
            for y in range(8):
                for x in range(8):
                    on = bits[y][x] == '#'
                    px[r * 8 + y][c * 8 + x] = PAL[fg if on else bg]

    w, h = W * scale, H * scale
    raw = b''
    for y in range(h):
        row = b''.join(bytes(px[y // scale][x // scale]) for x in range(w))
        raw += b'\x00' + row

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data +
                struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))

    io.open(out, 'wb').write(
        b'\x89PNG\r\n\x1a\n' +
        chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) +
        chunk(b'IDAT', zlib.compress(raw, 9)) +
        chunk(b'IEND', b''))
    print('wrote %s (%dx%d)' % (out, w, h))
    return 0


if __name__ == '__main__':
    sys.exit(main())
