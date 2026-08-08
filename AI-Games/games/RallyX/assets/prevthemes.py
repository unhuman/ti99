#!/usr/bin/env python3
"""Render every round THEME offline, as the TMS9918 would paint it.

WHY OFFLINE: emulator screenshots are the wrong tool for judging colour --
ColEm's fixed scale clips the screen and Classic99's stretch resamples the
pixels, so a contrast call made from a screenshot is a call made about the
scaler. This paints the name table directly from the SAME data the cart
uses: the wall/shrub colour tables out of src/tiles.bas, the char map out of
src/map2_N.bas, the sprites out of RALLYX.bas. If it reads here, it reads.

Each theme is drawn on its OWN maze (theme = mz = (round-1) AND 3), with a
flag, a rock, a puff of smoke and both cars dropped on nearby road cells --
the point is to see the reserved inks (player dark blue, chaser dark red,
rock black, smoke grey) against that theme's walls and shrubs, not to see
the walls alone.

Run from assets/:  C:\\cygwin64\\bin\\python3.9.exe prevthemes.py
"""
import os
import re

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src")

# TMS9918A palette, index -> RGB. 0 is transparent (sprites only).
PAL = {
    0x0: None,          0x1: (0, 0, 0),      0x2: (33, 200, 66),
    0x3: (94, 220, 120), 0x4: (84, 85, 237), 0x5: (125, 118, 252),
    0x6: (212, 82, 77), 0x7: (66, 235, 245), 0x8: (252, 85, 84),
    0x9: (255, 121, 120), 0xA: (212, 193, 84), 0xB: (230, 206, 128),
    0xC: (33, 176, 59), 0xD: (201, 91, 186), 0xE: (204, 204, 204),
    0xF: (255, 255, 255),
}

THEMES = ["spring", "frost", "autumn", "night"]
SCALE = 3
VIEW = 24               # the playfield window is 24 x 24 chars


def load(name):
    return open(os.path.join(SRC, name)).read()


def grab(text, label):
    """DATA BYTE rows under `label`, one list per row. Accepts $hex and
    decimal, and tolerates a trailing ' comment."""
    m = re.search(r"^%s:\s*$" % re.escape(label), text, re.M)
    if not m:
        raise KeyError(label)
    rows = []
    for line in text[m.end():].split("\n"):
        s = line.strip()
        if not s or s.startswith("'"):
            continue
        if not s.upper().startswith("DATA BYTE"):
            break
        body = s[len("DATA BYTE"):].split("'")[0]
        rows.append([int(v.strip()[1:], 16) if v.strip().startswith("$")
                     else int(v.strip()) for v in body.split(",") if v.strip()])
    return rows


main = load("RALLYX.bas")
tiles = load("tiles.bas")

wallpat = grab(tiles, "wallpat")
ovlpat = grab(tiles, "ovlpat")
ovlcol = grab(tiles, "ovlcol")
rockpat = grab(tiles, "rockpat")
rockcol = grab(tiles, "rockcol")
misc_chars = grab(main, "misc_chars")
car = grab(main, "car_bitmaps")            # 4 headings x 2 halves x 16 rows


def charset(theme):
    """code -> (pattern rows, colour rows), for every code this view uses."""
    wallcol = grab(tiles, "wallcol_%s" % theme)
    treecol = grab(tiles, "treecol_%s" % theme)
    cs = {}
    for i in range(16):
        cs[96 + i] = (wallpat[i], wallcol[i])
    cs[112] = (misc_chars[0], treecol[0])
    cs[113] = (misc_chars[1], grab(main, "misc_colors")[1])   # road: NEVER themed
    for i in range(16):                     # flags 0-11, smoke 12-15
        cs[i] = (ovlpat[i], ovlcol[i])
    for i in range(4):
        cs[24 + i] = (rockpat[i], rockcol[i])
    return cs


def put_char(px, cs, code, cc, cr):
    pat, col = cs[code]
    for ly in range(8):
        fg, bg = PAL[(col[ly] >> 4) & 0xF], PAL[col[ly] & 0xF]
        for lx in range(8):
            c = fg if pat[ly] & (0x80 >> lx) else bg
            if c is None:
                continue
            X, Y = (cc * 8 + lx) * SCALE, (cr * 8 + ly) * SCALE
            for yy in range(Y, Y + SCALE):
                for xx in range(X, X + SCALE):
                    px[xx, yy] = c


def put_sprite(px, heading, colour, cx, cy):
    """16x16 sprite: rows 0-15 are the LEFT half, 16-31 the right."""
    rgb = PAL[colour]
    left, right = car[heading * 2], car[heading * 2 + 1]
    for ly in range(16):
        for half, bits in ((0, left[ly]), (1, right[ly])):
            for lx in range(8):
                if not bits & (0x80 >> lx):
                    continue
                X, Y = (cx + half * 8 + lx) * SCALE, (cy + ly) * SCALE
                for yy in range(Y, Y + SCALE):
                    for xx in range(X, X + SCALE):
                        px[xx, yy] = rgb


def road_cells(cmap, r0, c0):
    """logical cells in the window whose 2x2 block is all road."""
    out = []
    # stop 2 chars short of the right/bottom edge: a 2x2 overlay placed on
    # the last cell gets clipped, which reads as a broken sprite
    for r in range(0, VIEW - 2, 2):
        for c in range(0, VIEW - 2, 2):
            blk = [cmap[r0 + r + dr][c0 + c + dc] for dr in (0, 1) for dc in (0, 1)]
            if all(v == 113 for v in blk):
                out.append((r, c))
    return out


def render(theme, mz):
    cs = charset(theme)
    # the char map wraps across several DATA BYTE lines per map row (68 cols,
    # 17 per line), so flatten and re-chunk rather than trusting line breaks
    flat = [v for ln in grab(load("map2_%d.bas" % (mz + 1)), "map2_%d" % (mz + 1))
            for v in ln]
    cmap = [flat[i:i + 68] for i in range(0, len(flat), 68)]
    # ANCHOR THE WINDOW ON THE MAZE CORNER so the border ring is in shot: the
    # shrubs ARE half the theme, and a mid-maze window shows none of them.
    r0, c0 = 0, 0
    im = Image.new("RGB", (VIEW * 8 * SCALE, VIEW * 8 * SCALE), PAL[0xA])
    px = im.load()
    for r in range(VIEW):
        for c in range(VIEW):
            put_char(px, cs, cmap[r0 + r][c0 + c], c, r)

    # overlays on real road cells, so nothing is drawn over a wall
    cells = road_cells(cmap, r0, c0)
    assert len(cells) >= 6, "%s: only %d free road cells in the window" % (theme, len(cells))
    for base, (r, c) in ((0, cells[0]), (24, cells[len(cells) // 2]),
                         (12, cells[-1])):          # flag F, rock, smoke
        for k, (dr, dc) in enumerate(((0, 0), (0, 1), (1, 0), (1, 1))):
            put_char(px, cs, base + k, c + dc, r + dr)

    # both cars, on road, one lane apart -- these are the reserved inks
    pr, pc = cells[len(cells) // 3]
    put_sprite(px, 2, 4, pc * 8, pr * 8)            # player, heading E, dark blue
    er, ec = cells[len(cells) // 3 + 1]
    put_sprite(px, 0, 6, ec * 8, er * 8)            # chaser, heading N, dark red
    return im


sheet = Image.new("RGB", (VIEW * 8 * SCALE * 2 + 24, VIEW * 8 * SCALE * 2 + 24),
                  (24, 24, 24))
for i, theme in enumerate(THEMES):
    im = render(theme, i)
    im.save(os.path.join(HERE, "theme-%d-%s.png" % (i + 1, theme)))
    sheet.paste(im, (8 + (i % 2) * (VIEW * 8 * SCALE + 8),
                     8 + (i // 2) * (VIEW * 8 * SCALE + 8)))
    print("theme-%d-%s.png  (maze %d)" % (i + 1, theme, i + 1))
sheet.save(os.path.join(HERE, "theme-sheet.png"))
print("theme-sheet.png -- all four, in round order")
