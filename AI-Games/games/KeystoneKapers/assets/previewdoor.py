#!/usr/bin/env python3
"""Render the elevator doorway in all three door states, from the shipped art.

The doorway is the one place in the game where a single character cell has to
carry two unrelated things at once -- the door (or the car behind it) and the
floor's own threshold -- so it is the obvious suspect whenever it looks wrong,
and it is worth being able to LOOK at without playing to the right floor and
waiting for the car.

This mirrors car_cell in KEYSTONE.bas exactly: four columns, four band rows,
three states. If this and the game ever disagree, one of them has been edited
without the other.

Run:  python3 previewdoor.py [out.png]
"""

import os
import re
import sys

import genart as g

HERE = os.path.dirname(os.path.abspath(__file__))
C = g.CODES

# TMS9918 palette, approximate sRGB
PAL = [
    (0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
    (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
    (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
    (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255),
]


def read_bytes(path, label):
    """Pull one DATA BYTE block out of a .bas file by label."""
    txt = open(path, encoding="utf-8").read()
    m = re.search(r"^%s:.*?$" % re.escape(label), txt, re.M)
    if not m:
        raise SystemExit("label %s not found in %s" % (label, path))
    out = []
    for line in txt[m.end():].split("\n"):
        t = line.strip()
        if not t or t.startswith("'"):
            continue
        if not t.startswith("DATA BYTE"):
            break
        for tok in t[9:].split(","):
            tok = tok.strip()
            out.append(int(tok[1:], 16) if tok.startswith("$") else int(tok))
    return out


def car_cell(cst, crw, ccl):
    """The exact logic of car_cell in KEYSTONE.bas."""
    ccw = C["EDOOR"]
    if crw == 3:
        ccw = C["EDOORS"]
    if cst == 1:
        if 0 < ccl < 3:
            ccw = C["EDHALF"]
            if crw == 0:
                ccw = C["EDHALFT"]
            if crw == 3:
                ccw = C["EDHALFS"]
    if cst == 2:
        ccw = C["ECAR"]
        if crw == 0:
            ccw = C["ECART"]
        if crw == 3:
            ccw = C["ECARS"]
        if ccl == 0:
            ccw = C["ECARL"]
            if crw == 0:
                ccw = C["ECARLT"]
            if crw == 3:
                ccw = C["ECARLS"]
        if ccl == 3:
            ccw = C["ECARR"]
            if crw == 0:
                ccw = C["ECARRT"]
            if crw == 3:
                ccw = C["ECARRS"]
    return ccw


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "doors.png")

    # the SHIPPED tables, read the same way preview.py reads them -- these
    # are the bytes the cartridge carries, not a second copy of the intent
    art = os.path.join(HERE, "..", "src", "art.bas")
    pat = read_bytes(art, "store_pat")
    col = read_bytes(art, "store_col")

    # three states side by side, each 4 cols x 5 rows (the band's 4 doorway
    # rows plus the floor bar under it), 2 columns of gap between
    CW, CH_, GAP = 4, 5, 2
    W = (CW * 3 + GAP * 2) * 8
    H = CH_ * 8
    px = [[(0, 0, 0)] * W for _ in range(H)]

    for st in range(3):
        x0 = st * (CW + GAP) * 8
        for crw in range(5):
            for ccl in range(4):
                code = C["SLAB"] if crw == 4 else car_cell(st, crw, ccl)
                o = (code - 96) * 8
                for line in range(8):
                    bits = pat[o + line]
                    cb = col[o + line]
                    fg, bg = PAL[cb >> 4], PAL[cb & 15]
                    y = crw * 8 + line
                    for b in range(8):
                        px[y][x0 + ccl * 8 + b] = fg if (bits << b) & 0x80 else bg

    try:
        from PIL import Image
        im = Image.new("RGB", (W, H))
        im.putdata([p for row in px for p in row])
        im = im.resize((W * 8, H * 8), Image.NEAREST)
        im.save(out)
        print("wrote %s  (shut | part-open | open, 8x)" % os.path.normpath(out))
    except ImportError:
        print("PIL not available")
        return 1

    # and say, in words, how many colours each scan line of the bottom row uses
    print()
    print("bottom row (the sill), colours per 8x1 scan line:")
    for nm in ("EDOORS", "EDHALFS", "ECARS"):
        o = (C[nm] - 96) * 8
        used = sorted({(col[o + l] >> 4, col[o + l] & 15) for l in range(8)})
        print("  %-8s %s" % (nm, "  ".join("line fg=%2d bg=%2d" % u for u in used)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
