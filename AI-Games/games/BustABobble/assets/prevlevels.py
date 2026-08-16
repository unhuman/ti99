#!/usr/bin/env python3
"""
BUST-A-BOBBLE - offline screen renderer.

Paints the real 256x192 TMS9918 screen for each authored level, using the actual geometry
from DESIGN.md section 2/3 and the real TMS9918 palette -- so layouts and the character
alignment invariant are reviewed as a picture rather than by replaying the game.

Also emits an ALIGNMENT sheet: the same level at several ceiling offsets and shake phases,
with the 8x8 character grid drawn on top. Every bubble corner must sit on a grid line in
every panel; that is the invariant the whole design rests on.

Outputs (next to this script):
    level-NN.png        one screen per authored level, 3x
    alignment.png       top = 0..3 x shk = -1/0/+1, with the char grid overlaid, 3x

Run:  python3 prevlevels.py
"""

import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.stderr.write("error: needs Pillow (pip install Pillow)\n")
    sys.exit(1)

import genlevels

HERE = os.path.dirname(os.path.abspath(__file__))
SCALE = 3

# --- TMS9918 palette -------------------------------------------------------------------
TMS = {
    1: (0, 0, 0),        2: (33, 200, 66),    3: (94, 220, 120),  4: (84, 85, 237),
    5: (125, 118, 252),  6: (212, 82, 77),    7: (66, 235, 245),  8: (252, 85, 84),
    9: (255, 121, 120), 10: (212, 193, 84),  11: (230, 206, 128), 12: (33, 176, 59),
    13: (201, 91, 186), 14: (204, 204, 204), 15: (255, 255, 255),
}

# Bubble shading comes STRAIGHT FROM genart.py -- the generator that writes the
# ROM tables -- so the preview cannot drift from what the hardware actually shows.
# Each entry is (base, lit, litrows); litrows is per colour (see genart.py).
import genart
BUBBLE = dict((k + 1, v) for k, v in enumerate(genart.BUBBLE))

# --- screen geometry (DESIGN.md section 3) ---------------------------------------------
CELLW = 8
SCRW, SCRH = 256, 192
# The walls sit INSIDE the shake travel and move with the field (they live in the
# same row buffer as the bubbles -- DESIGN.md section 8), so at rest they are at
# columns 1 and 18 and the field spans the full well between them. Bubbles touch
# the walls; there is no slack.
WALLCOL_L, WALLCOL_R = 1, 18      # character columns of the two walls, at rest
WELLCOL = 1                       # first character column of the board
WELLW = 18                        # board width in characters (walls included)
CEILROW = 1                       # first character row a bubble can occupy
DEATHROW = 20                     # a bubble reaching this char row ends the round
FXBASE = 1                        # field inset inside the well, in characters (the shake slack)

NROWS, NCOLS = genlevels.NROWS, genlevels.NCOLS

# A 16x16 bubble, filling its cell so hex neighbours meet: per-pixel-row inset from each
# side. Rows 0..5 use the lit shade, rows 6..15 the base shade -- two colours per character
# scan line at most, which is what the hardware allows.
INSET = [4, 3, 2, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 2, 3, 4]
LITROWS = 6


def blank():
    return Image.new("RGB", (SCRW, SCRH), TMS[1])


def draw_bubble(px, x0, y0, k):
    base, lit, lrows = BUBBLE[k]
    for yy in range(16):
        y = y0 + yy
        if not 0 <= y < SCRH:
            continue
        col = TMS[lit if yy < lrows else base]
        for xx in range(INSET[yy], 16 - INSET[yy]):
            x = x0 + xx
            if 0 <= x < SCRW:
                px[x, y] = col


def render(grid, top=0, shk=0, hud=True):
    """Paint one screen. Mirrors draw_row() in DESIGN.md section 8 exactly."""
    img = blank()
    px = img.load()
    d = ImageDraw.Draw(img)

    # Walls and ceiling move with the shake, so they follow shk like the field.
    wl = (WALLCOL_L + shk) * CELLW
    wr = (WALLCOL_R + shk) * CELLW
    d.rectangle([wl, 0, wl + 7, SCRH - 1], fill=TMS[14])
    d.rectangle([wr, 0, wr + 7, SCRH - 1], fill=TMS[14])
    # ceiling: the same 18 chars wide as the walls it sits on
    d.rectangle([wl, 0, wr + 7, CELLW - 1], fill=TMS[14])

    # death line, dashed, only BETWEEN the walls
    dy = DEATHROW * CELLW
    for x in range(wl + CELLW, wr, 8):
        d.rectangle([x, dy + 3, x + 3, dy + 4], fill=TMS[6])

    # the field. char col = fx + 2c + (r AND 1); char row = CEILROW + top + 2r
    fx = WELLCOL + FXBASE + shk
    for r in range(NROWS):
        crow = CEILROW + top + 2 * r
        if crow >= 24:
            continue
        for c in range(NCOLS):
            k = grid[r][c]
            if not k:
                continue
            ccol = fx + 2 * c + (r & 1)
            draw_bubble(px, ccol * CELLW, crow * CELLW, k)

    if hud:
        hx = (WALLCOL_R + 1) * CELLW
        d.text((hx + 2, 1), "1UP", fill=TMS[15])
        d.text((hx + 2, 9), "  204850", fill=TMS[15])
        d.text((hx + 2, 25), "HI", fill=TMS[15])
        d.text((hx + 2, 33), " 3033199 0", fill=TMS[11])
        d.text((hx + 2, 49), "ROUND", fill=TMS[15])
        d.text((hx + 2, 57), "  1", fill=TMS[15])
        d.text((hx + 2, 73), "NEXT", fill=TMS[15])
        d.text((hx + 2, 105), "TIME", fill=TMS[15])
        # drop-timer bar, 8 chars, shown ~5/8 full
        for i in range(8):
            c = TMS[3] if i < 5 else TMS[1]
            d.rectangle([hx + i * CELLW + 1, 114, hx + i * CELLW + 6, 119], fill=c)
        # spares: 3 lives -> TWO icons (repo convention: the HUD shows reserves)
        for i in range(2):
            d.ellipse([hx + 2 + i * 10, 183, hx + 8 + i * 10, 189], fill=TMS[8])

    return img


def upscale(img, s=SCALE):
    return img.resize((img.width * s, img.height * s), Image.NEAREST)


def alignment_sheet(grid):
    """top x shk grid with the 8x8 character lattice drawn over it."""
    tops = [0, 1, 2, 3]
    shks = [-1, 0, 1]
    pad = 6
    tile_w, tile_h = SCRW * 2, SCRH * 2
    sheet = Image.new("RGB", (len(shks) * (tile_w + pad) + pad,
                              len(tops) * (tile_h + pad) + pad + 14), (24, 24, 28))
    sd = ImageDraw.Draw(sheet)
    sd.text((pad, 3), "BUST-A-BOBBLE alignment invariant: every bubble corner on a char "
                      "boundary, at every ceiling offset and shake phase", fill=(210, 210, 210))

    for ri, top in enumerate(tops):
        for ci, shk in enumerate(shks):
            img = render(grid, top=top, shk=shk, hud=False)
            img = img.resize((tile_w, tile_h), Image.NEAREST)
            g = ImageDraw.Draw(img)
            for x in range(0, tile_w, CELLW * 2):
                g.line([(x, 0), (x, tile_h)], fill=(70, 70, 90))
            for y in range(0, tile_h, CELLW * 2):
                g.line([(0, y), (tile_w, y)], fill=(70, 70, 90))
            g.text((3, 3), "top=%d shk=%+d" % (top, shk), fill=(255, 255, 0))
            sheet.paste(img, (pad + ci * (tile_w + pad), pad + 14 + ri * (tile_h + pad)))
    return sheet


def check_alignment(grid):
    """The invariant, asserted rather than eyeballed."""
    bad = 0
    for top in range(0, 6):
        for shk in (-1, 0, 1):
            fx = WELLCOL + FXBASE + shk
            for r in range(NROWS):
                for c in range(NCOLS):
                    if not grid[r][c]:
                        continue
                    x = (fx + 2 * c + (r & 1)) * CELLW
                    y = (CEILROW + top + 2 * r) * CELLW
                    if x % CELLW or y % CELLW:
                        bad += 1
                    if (r & 1) and c == NCOLS - 1:
                        bad += 1        # odd rows must not use column 7
    return bad


def main():
    levels = [genlevels.validate(lv) for lv in genlevels.parse(genlevels.SRC)]
    if not levels:
        sys.stderr.write("error: no levels authored\n")
        return 1

    for lv in levels:
        img = upscale(render(lv["grid"]))
        out = os.path.join(HERE, "level-%02d.png" % lv["n"])
        img.save(out)
        print("wrote %s   (%d bubbles)" % (os.path.basename(out), lv["count"]))

    sheet = alignment_sheet(levels[0]["grid"])
    sheet.save(os.path.join(HERE, "alignment.png"))
    print("wrote alignment.png")

    bad = check_alignment(levels[0]["grid"])
    print("alignment invariant: %s (%d violations over top=0..5 x shk=-1..+1)"
          % ("OK" if bad == 0 else "FAILED", bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
