#!/usr/bin/env python3
"""Transcribe all four arcade Rally-X maps at the cell grid -> mazeN.txt.

Generalises transcribe2.py (which hardcoded level 1's origin) to all four
rips. Origins were found by align2.py, which locates the maze body from
per-row / per-column counts of maze-base pixels rather than by eye -- the
rips are cropped differently and three of the four are NOT at level 1's
offset.

Each cell is 24 px. Base type comes from the dominant colour of the cell's
inner 8x8 window (items sit on road and would otherwise skew a whole-cell
vote); items are detected over the whole cell.
"""
from PIL import Image
from collections import Counter

# Each arcade map recolours its WALLS -- level 1 green, 2 brown, 3 grey-green,
# 4 grey -- so a wall-colour test only works for the map it was written for
# (that is why levels 3 and 4 first came out with ~10 wall cells). The ROAD
# colour is the one constant across all four, so classification is "road, or
# else wall", which needs no per-level palette at all.
ROADSET = {(222, 151, 71), (208, 121, 44), (197, 100, 26)}
PITCH, COLS, ROWS = 24, 32, 56

ORIGINS = {1: (89, 112), 2: (80, 104), 3: (76, 97), 4: (79, 104)}


def transcribe(lvl):
    x0o, y0o = ORIGINS[lvl]
    im = Image.open("Rally-X-Level%d.png" % lvl).convert("RGB")
    px = im.load()
    flags, specials, players, enemies = [], [], [], []
    grid = []
    for r in range(ROWS):
        row = ""
        for c in range(COLS):
            x0, y0 = x0o + c * PITCH, y0o + r * PITCH
            has = Counter()
            for yy in range(y0, y0 + PITCH):
                for xx in range(x0, x0 + PITCH):
                    has[px[xx, yy]] += 1
            if has[(255, 255, 0)] >= 10:
                if has[(222, 0, 0)] >= 5:
                    specials.append((r, c))
                else:
                    flags.append((r, c))
            if has[(33, 71, 222)] >= 10:
                players.append((r, c))
            if has[(104, 0, 0)] >= 60:
                enemies.append((r, c))
            road = 0
            for yy in range(y0 + 8, y0 + 16):
                for xx in range(x0 + 8, x0 + 16):
                    if px[xx, yy] in ROADSET:
                        road += 1
            row += "." if road >= 32 else "#"   # 64-px window, majority
        grid.append(row)

    walls = sum(g.count("#") for g in grid)
    print("L%d origin=%s wall=%d road=%d flags=%d special=%d player=%s enemies=%d"
          % (lvl, (x0o, y0o), walls, COLS * ROWS - walls,
             len(flags), len(specials), players, len(enemies)))

    with open("maze%d.txt" % lvl, "w") as f:
        for g in grid:
            f.write(g + "\n")
        f.write("flags %r\n" % flags)
        f.write("special %r\n" % specials)
        f.write("player %r\n" % players)
        f.write("enemies %r\n" % enemies)
    return grid


if __name__ == "__main__":
    for lvl in (1, 2, 3, 4):
        transcribe(lvl)
