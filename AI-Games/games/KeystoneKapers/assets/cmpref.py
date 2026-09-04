#!/usr/bin/env python3
"""Put our sprite beside the reference, on the REFERENCE's grid.

Ours is 16 px wide by 24 tall; the 2600's is 8 clocks by ~19 scanlines. The
only honest comparison squashes ours down to theirs -- halve the columns, scale
the rows -- and prints the two side by side, because "does it look like the
video" is a question about the silhouette, not about our extra resolution.
"""
import sys
import genart as g

# transcribed off the video onto the 2600's own grid -- see DESIGN.md 0h
REF_KELLY = """\
..KKKK..
..KKKK..
..KKKK..
KKKKKKKK
.....KK.
..SSS...
..SSS...
..SSS...
........
.....BB.
.BBBBBB.
.BBBBBBB
.BBBBBBB
.BBBBBBB
.BBBBBBB
.BBBBBBB
..BBBBBB
..BBBBB.
...KKKKK"""


def rows(art):
    return [r for r in art.strip("\n").split("\n")]


def ours(top, legs):
    """The whole figure as 24 rows of 16, from the band definitions."""
    t, l = rows(top), rows(legs)
    out = []
    for i in range(16):
        line = ""
        for x in range(16):
            ch = t[i][x]
            if ch != "#":
                line += "."
            elif i in g.HAT:
                line += "K"
            elif i in g.FACE:
                line += "S"
            else:
                line += "B"
        out.append(line)
    for i in range(8):
        out.append("".join("B" if c == "#" else "." for c in l[i]))
    return out


def squash(fig, nrows):
    """16 wide -> 8 (a column is set if either half is), 24 rows -> nrows."""
    out = []
    for r in range(nrows):
        src = fig[int(r * len(fig) / nrows)]
        line = ""
        for c in range(8):
            a, b = src[2 * c], src[2 * c + 1]
            line += a if a != "." else b
        out.append(line)
    return out


ref = rows(REF_KELLY)
mine = squash(ours(g.KELLY_TOP, g.KELLY_LEG2), len(ref))
print("  reference        ours (squashed to their grid)")
for i in range(len(ref)):
    same = "  " if ref[i] == mine[i] else " <"
    print("%2d %s   %s%s" % (i, ref[i], mine[i], same))
n = sum(1 for i in range(len(ref)) if ref[i] == mine[i])
print("\n%d of %d rows identical" % (n, len(ref)))
