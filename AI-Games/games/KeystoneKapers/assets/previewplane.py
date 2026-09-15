#!/usr/bin/env python3
"""Render the biplane the way the VDP will -- the only way to judge a sprite.

THE WHOLE ANIMATION IS TWO FRAMES. One sprite, one colour, two propeller
phases; `draw_obst` picks between them with `IF fphs AND 4`, so each phase
holds for four passes. Both facings are drawn out in full because the VDP has
no flip bit, which makes four patterns in total -- but only two pictures.

The strip at the bottom is the pair alternating as it will on screen. A
propeller either reads as spin there or it reads as flicker, and a single
still cannot tell you which.

Run:  python3 previewplane.py [out.png]
"""
import os
import sys

import genart as g

HERE = os.path.dirname(os.path.abspath(__file__))
PAL = [(0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
       (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
       (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
       (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255)]
BG = PAL[g.STORE_BG]

C_PLANE = 11        # must match KEYSTONE.bas -- the plane is ONE colour now


def rows(art):
    return [r for r in art.strip("\n").split("\n")]


def cell(art):
    """One 16x16 sprite box on the store's own background."""
    out = [[BG for _ in range(16)] for _ in range(16)]
    for y, line in enumerate(rows(art)):
        for x, ch in enumerate(line):
            if ch == "#":
                out[y][x] = PAL[C_PLANE]
    return out


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "plane.png")
    a = g.overlay(g.PLANE_R, g.PROP_A)
    b = g.overlay(g.PLANE_R, g.PROP_B)
    al, bl = g.mirror(a), g.mirror(b)

    # row 0: the two frames, facing right      (what the game flips between)
    # row 1: the two frames, facing left
    # row 2: the right-facing pair alternating, four times -- the spin test
    grid = [[cell(a), cell(b)],
            [cell(al), cell(bl)],
            [cell(a), cell(b), cell(a), cell(b), cell(a), cell(b)]]

    try:
        from PIL import Image
    except ImportError:
        sys.exit("previewplane needs PIL")

    cols = max(len(r) for r in grid)
    W = H = 16
    im = Image.new("RGB", ((W + 2) * cols, (H + 2) * len(grid)), (255, 0, 255))
    for r, rowset in enumerate(grid):
        for c, fr in enumerate(rowset):
            for y in range(H):
                for x in range(W):
                    im.putpixel((c * (W + 2) + x, r * (H + 2) + y), fr[y][x])
    im.resize((im.width * 12, im.height * 12), Image.NEAREST).save(out)

    drawn = [n for n, line in enumerate(rows(a)) if set(line) != {"."}]
    used = [x for line in rows(a) for x, ch in enumerate(line) if ch != "."]
    print("wrote %s" % os.path.normpath(out))
    print("  frames in the animation : 2   (phase A, phase B)")
    print("  patterns in ROM         : 4   (two phases x two facings)")
    print("  envelope                : %d wide, %d tall, rows %d-%d"
          % (max(used) - min(used) + 1, drawn[-1] - drawn[0] + 1,
             drawn[0], drawn[-1]))
    print("  rows: facing right, facing left, then the spin test")


if __name__ == "__main__":
    main()
