#!/usr/bin/env python3
"""Put our sprite beside the reference, on the REFERENCE's grid.

Ours is 16 px wide by 24 tall; the 2600's is 8 clocks by ~19 scanlines. The
only honest comparison squashes ours down to theirs -- halve the columns, scale
the rows -- and prints the two side by side, because "does it look like the
video" is a question about the silhouette, not about our extra resolution.

Run:  python3 cmpref.py
"""
import genart as g

# Transcribed off the video onto the 2600's own grid (DESIGN.md 0h) from a
# frame DEEP INSIDE A 127-FRAME RIGHTWARD RUN, so this is the RIGHT-facing
# figure -- which is what the base art has to be, since `kldir = 1` (right)
# selects it unmirrored.
#
# THE FIRST TRANSCRIPTION CAME FROM A FRAME WHERE HE WAS TURNING. Its body
# leaned the other way, the art was built on it, and the whole animation came
# out inverted: he ran facing backwards. A single frame does not establish a
# facing -- take one from the middle of a long monotone run, which is what
# `dirs.py`'s search for the longest monotone stretch is for.
REF_KELLY = [
    "..KKKK..",   # crown, 4 of 8
    "..KKKK..",
    "..KKKK..",
    "KKKKKKKK",   # brim, the FULL 8
    ".K...KK.",
    "..SSSS..",   # face, left of centre
    "..SSS...",
    "..SSS...",
    "...SS...",
    "..BB....",   # a shoulder stub, on the LEFT when facing right
    "..BBBB..",
    "..BBBBB.",
    "..BBBBB.",
    "..BBBBB.",
    ".BBBBBB.",   # body, inset a clock either side
    ".BBBBBB.",
    ".BBBBBB.",
    ".BBBBBB.",
    "..K.....",   # dark feet
]


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


def main():
    mine = squash(ours(g.KELLY_TOP, g.KELLY_LEG2), len(REF_KELLY))
    print("  reference        ours (squashed to their grid)")
    for i in range(len(REF_KELLY)):
        mark = "  " if REF_KELLY[i] == mine[i] else " <"
        print("%2d %s   %s%s" % (i, REF_KELLY[i], mine[i], mark))
    n = sum(1 for i in range(len(REF_KELLY)) if REF_KELLY[i] == mine[i])
    print("\n%d of %d rows identical" % (n, len(REF_KELLY)))


if __name__ == "__main__":
    main()
