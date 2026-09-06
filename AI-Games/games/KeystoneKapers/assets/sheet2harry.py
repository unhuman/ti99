#!/usr/bin/env python3
"""Turn the run-cycle sheet into Harry's four running frames.

INPUT   ref2600/runcycle-sheet.png -- eight silhouettes of a running figure,
        two rows of four, drawn on a printed grid.
OUTPUT  harryrun1.txt .. harryrun4.txt -- 16x24 '#'/'.' art, one per beat,
        carrying OUR head over the sheet's body.

Four beats out of eight keeps the cycle legible at the rate the game animates
and costs half the patterns. WHICH four, and IN WHAT ORDER, is measured -- see
USE below. Taking every other frame is the obvious choice and it is wrong.

WHY THIS IS A SEPARATE SCRIPT AND NOT PART OF genart.py: it needs PIL, and
genart runs inside the build. A missing imaging library must not be able to
fail a cartridge build over art that has not changed since the last run -- so
this writes text files, genart reads them, and the build depends on nothing but
the standard library. The .txt files are also editable by hand, which is the
point of having them.

Three things here were wrong on the first attempt and are worth keeping:

  * THE NECK IS A LOCAL MINIMUM, not the narrowest row. The narrowest row in
    the upper third is the top of the SCALP -- two pixels of head -- so cutting
    there grafts the whole head on along with the body.
  * SCALE ISOTROPICALLY, ANCHORED ON THE NECK. Scaling each body's own ink
    bounding box to fill the sprite stretches it by a different amount in every
    frame (an outstretched arm widens the box) and centres the BOX rather than
    the BODY, so the torso slides out from under the head.
  * A SILHOUETTE FLATTERS. Judge the result striped, the way the game draws
    him: the bands chop the figure up and thin limbs lose whole rows to the
    black half.

Run:  python3 sheet2harry.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SHEET = os.path.join(HERE, "ref2600", "runcycle-sheet.png")

# the eight figures on the sheet, left to right, top row first
BOXES = {
    1: (39, 62, 224, 383), 2: (288, 62, 480, 383),
    3: (532, 75, 742, 383), 4: (775, 62, 992, 383),
    5: (32, 421, 212, 735), 6: (282, 421, 480, 722),
    7: (532, 421, 749, 735), 8: (767, 421, 998, 735),
}
# WHICH FOUR, AND IN WHAT ORDER. Not 1, 3, 5, 7-and-friends: in an eight-frame
# run cycle, frame n+4 is the SAME POSE WITH THE LEGS SWAPPED, and a side-view
# silhouette of a symmetric figure cannot tell those two apart. Every other
# frame therefore gives two pictures, not four. Measured on this sheet, the
# trailing leg sweeps down-LEFT in frames 1, 2 and 5 and down-RIGHT in 3, 4, 6,
# 7 and 8, and within each group the frames are near-duplicates:
#
#     1 vs 5  16 px      3 vs 8   7 px      3 vs 4  18 px      1 vs 2  11 px
#
# So 1, 3, 5, 8 -- which alternates sides correctly and whose CONSECUTIVE steps
# are a healthy 49 px -- plays as A, B, A, B: the legs going back and forth
# between two positions, which is exactly how it was reported from play. The
# consecutive step is the number that looks reassuring here and it is the wrong
# one; the smallest pair ANYWHERE in the cycle is what decides how many frames
# the cycle has.
#
# 1 -> 4 -> 5 -> 3 still alternates left, right, left, right, and puts the two
# unavoidable near-duplicates (1 and 5, 4 and 3) OPPOSITE each other in the
# cycle rather than adjacent. Closest pair 16 px, smallest consecutive step 50.
# 16 is the best any alternating set can do, because the sheet only offers
# three left-sweep frames and they are all within 16 px of each other.
#
# assets/checkanim.py measures this on the shipped patterns and fails the
# build, so a future reshuffle cannot quietly go back to two frames.
USE = (1, 4, 5, 3)

W = 16              # sprite width
HEADROWS = 9        # rows 0-8 are ours: cap 0-2, face 3-8
HBODY = 24 - HEADROWS
NECKCOL = 7         # the column our head's neck sits over
FILL = 0.55         # ink fraction that makes a target cell solid

# Our Harry's head, rows 0-8 of HARRY_TOP in genart.py. Copied rather than
# imported so this script has no import cycle with the module it feeds.
HEAD = [
    ".....#####......",
    ".....#####......",
    ".....#####......",
    "....######......",
    "....#####.......",
    "....######......",
    "....#####.......",
    "....####........",
    ".....####.......",
]


def grid():
    from PIL import Image
    im = Image.open(SHEET).convert("L")
    w, h = im.size
    px = im.load()
    # solid black only: the printed grid is light grey and must not count
    return [[1 if px[x, y] < 100 else 0 for x in range(w)] for y in range(h)]


def neck(g, box):
    x0, y0, x1, y1 = box
    widths = [sum(1 for x in range(x0, x1) if g[y][x]) for y in range(y0, y1)]
    limit = max(6, (y1 - y0) // 2)
    i = max(range(limit), key=lambda k: widths[k])       # widest part of head
    while i + 1 < limit and widths[i + 1] <= widths[i]:  # down to the dip
        i += 1
    return y0 + i


def body(g, box):
    x0, y0, x1, y1 = box
    ny = neck(g, box)
    nxs = [x for x in range(x0, x1) if g[ny][x]]
    ncx = (min(nxs) + max(nxs)) / 2.0
    scale = (y1 - ny) / float(HBODY)
    out = []
    for r in range(HBODY):
        row = ""
        for q in range(W):
            sx0 = ncx + (q - NECKCOL) * scale
            sy0 = ny + r * scale
            ink = tot = 0
            for yy in range(int(sy0), max(int(sy0) + 1, int(sy0 + scale))):
                for xx in range(int(sx0), max(int(sx0) + 1, int(sx0 + scale))):
                    if x0 <= xx < x1 and y0 <= yy < y1:
                        tot += 1
                        ink += g[yy][xx]
            row += "#" if tot and ink / float(tot) >= FILL else "."
        out.append(row)
    return out


def main():
    if not os.path.exists(SHEET):
        sys.exit("sheet not found: %s" % SHEET)
    g = grid()
    for i, n in enumerate(USE, 1):
        rows = HEAD + body(g, BOXES[n])
        assert len(rows) == 24, len(rows)
        out = os.path.join(HERE, "harryrun%d.txt" % i)
        with open(out, "w") as fh:
            fh.write("\n".join(rows) + "\n")
        print("wrote %s  (sheet frame %d)" % (os.path.basename(out), n))


if __name__ == "__main__":
    main()
