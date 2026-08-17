#!/usr/bin/env python3
"""BUST-A-BOBBLE -- generates src/juggle.bas: the victory screen's juggling path.

WHAT IT IS. One closed loop, 64 steps, walked by all eight balls at once with a
phase offset of 8 steps each. Two bytes a step and the whole animation is a table
lookup: ball i sits at step (t + 8*i) AND 63. That is why there is a loop rather
than eight arcs -- eight independent paths would be eight tables and eight sets of
state, and this is 128 bytes and one counter.

WHY IT IS GENERATED, AND WHAT IS VERIFIED. The TMS9918 draws only FOUR sprites on
any scanline and SILENTLY DROPS the fifth (SPRITE FLICKER is off in this game, so
there is no rotation to save it). The screen shows eleven sprites: eight balls, the
creature's body, and his two arms. So a path that looks lovely on paper can make
balls vanish on the machine, and it fails worst exactly where balls bunch up -- at
the top of the loop, where they move slowest.

So the loop is not a circle. It is:

  * an ELLIPSE, wider than it is tall, sitting above the creature's head, and
  * walked with a SPEED PROFILE -- fast across the bottom, slow over the top, like
    a thrown ball -- so the bottom of the loop, which is the only part that shares
    scanlines with the creature and his arms, holds at most one ball at a time.

and this script sweeps the shape parameters, counts sprites per scanline for every
one of the 64 phases, and refuses to emit a table that ever exceeds four. The
number it prints is the real margin.

Run:  python3 genjuggle.py
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "src", "juggle.bas")

STEPS = 64               # must be a power of two: the game does `AND 63`
NBALLS = 8
PHASE = STEPS // NBALLS  # 8 steps between balls

SPR = 16                 # every sprite here is 16x16
MAXLINE = 4              # TMS9918 sprites per scanline before the rest are dropped

# The creature, fixed. Body 16 px wide centred on the screen, arms 8 px either
# side at the same y -- exactly the offsets tw_draw uses on the title screen, so
# the shoulder meets him at shoulder height and the arm stays clear of his eyes.
BODY_X = 120
BODY_Y = 143             # sprite y reads one low on this VDP: covers rows 144-159
ARM_DX = 8

# Text rows that must stay clear of the loop: CONGRATULATIONS! on row 4 (y 32-39)
# and PRESS FIRE on row 22 (y 176-183). Row 23 is overscan on real hardware and
# clipped in Classic99, which is why PRESS FIRE is not on it.
# These bound the BALL SPRITE'S EXTENT, not the path it is centred on -- the two
# differ by 8 px and bounding the path let a ball overlap the CONGRATULATIONS! row
# while every printed number looked fine.
TOP_LIMIT = 40           # highest ball top-left: covers rows 41+, clear of row 3's text
BOT_LIMIT = 158          # lowest ball bottom row, well clear of PRESS FIRE on row 22

# The bottom of the loop must land IN HIS HANDS -- a ball whose top-left y is in
# this window has its lower edge among the arm sprites' hands (which sit in the arm
# sprite's TOP four rows, i.e. screen rows BODY_Y+1..BODY_Y+4), so the catch reads
# as a catch. Without this the sweep happily floats the whole ring above his head.
HAND_LOW = 128
HAND_HIGH = 136


def path(cx, cy, rx, ry, power):
    """The loop, as STEPS (x, y) sprite positions.

    `power` shapes the speed: the parameter is warped by a sine so that equal time
    steps cover more arc along the bottom than over the top. power=1 is a plain
    constant-speed circle (balls bunch at top AND bottom); higher values push the
    bunching entirely into the top, where nothing else is drawn.
    """
    pts = []
    for i in range(STEPS):
        u = i / float(STEPS)                    # 0..1 around the loop
        # Warp u so the bottom half is traversed quickly. sin(2*pi*u) is negative
        # over the bottom half of the loop, so subtracting it there speeds it up.
        w = u + (power * math.sin(2.0 * math.pi * u) / (2.0 * math.pi))
        a = 2.0 * math.pi * w
        # -cos so step 0 is the BOTTOM of the loop (a ball at his hands), which
        # makes the phase offsets read as "just thrown, just caught".
        x = cx + rx * math.sin(a)
        y = cy - ry * math.cos(a)
        pts.append((int(round(x)) - SPR // 2, int(round(y)) - SPR // 2))
    return pts


def worst_scanline(pts):
    """Max sprites on any scanline, over every phase of the animation."""
    worst = 0
    where = None
    for t in range(STEPS):
        ys = [BODY_Y + 1, BODY_Y + 1, BODY_Y + 1]        # body + two arms
        for b in range(NBALLS):
            ys.append(pts[(t + b * PHASE) % STEPS][1] + 1)
        for line in range(192):
            n = sum(1 for y in ys if y <= line < y + SPR)
            if n > worst:
                worst, where = n, (t, line)
    return worst, where


def main():
    best = None
    # THE LOOP HAS TO REACH HIS HANDS. A first sweep that only asked for "safe and
    # big" put the whole ring above his head, which reads as a ring floating over a
    # creature rather than a creature juggling -- the balls never went anywhere near
    # him. So the bottom of the loop is now a hard requirement, and it is what makes
    # the speed warp necessary: at the bottom the ball shares scanlines with the
    # body and both arms, which is 3 sprites already, so only ONE ball may be down
    # there at a time. Constant speed puts three in that band.
    for cy in range(76, 111, 2):
        for ry in range(30, 53, 2):
            for power in (0.0, 0.3, 0.5, 0.7, 0.9, 1.1, 1.3, 1.5):
                for rx in range(44, 69, 4):
                    pts = path(128, cy, rx, ry, power)
                    if min(x for x, y in pts) < 4 or max(x for x, y in pts) > 236:
                        continue
                    if min(y for x, y in pts) < TOP_LIMIT:
                        continue
                    low = max(y for x, y in pts)
                    if low + SPR > BOT_LIMIT:
                        continue
                    if low < HAND_LOW or low > HAND_HIGH:
                        continue
                    worst, where = worst_scanline(pts)
                    if worst > MAXLINE:
                        continue
                    # Among safe shapes: least crowded first (margin is worth more
                    # than looks here, since the failure is invisible), then widest
                    # -- a wide loop reads as juggling, a narrow one as two columns
                    # of balls bouncing.
                    score = (worst, -rx, -ry)
                    if best is None or score < best[0]:
                        best = (score, pts, rx, ry, power, worst, where, cy)

    if best is None:
        sys.stderr.write(
            "error: no loop shape keeps every scanline at or under %d sprites.\n"
            "       Eight 16x16 balls plus a body and two arms is 11 sprites; if\n"
            "       this ever triggers, drop to six balls in the ring or move the\n"
            "       arms off the body's scanlines -- do NOT just ship it, the\n"
            "       machine will silently stop drawing balls.\n" % MAXLINE)
        return 1

    _, pts, rx, ry, power, worst, where, cy = best

    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]

    L = []
    w = L.append
    w("\t' BUST-A-BOBBLE victory-screen juggling path -- GENERATED by")
    w("\t' assets/genjuggle.py. Do not edit; change the shape there and regenerate.")
    w("\t'")
    w("\t' %d steps around one closed loop. Ball i is at step (t + %d*i) AND %d, so"
      % (STEPS, PHASE, STEPS - 1))
    w("\t' all eight balls share this one table and one counter.")
    w("\t'")
    w("\t' Ellipse rx=%d ry=%d about (128,%d), speed warp %.1f -- fast across the"
      % (rx, ry, cy, power))
    w("\t' bottom, slow over the top, so the bottom of the loop (the only part that")
    w("\t' shares scanlines with the creature and his arms) holds one ball at a time.")
    w("\t'")
    w("\t' VERIFIED: worst case %d sprites on any scanline, of the 4 the TMS9918 will"
      % worst)
    w("\t' draw, counting all 8 balls + body + 2 arms, over every phase. The 5th")
    w("\t' sprite on a line is silently dropped, so this is a correctness property,")
    w("\t' not a nicety. genjuggle.py re-proves it on every run.")
    w("\t'")
    w("\t' These are SPRITE coordinates (y reads one low on this VDP), top-left of")
    w("\t' each 16x16 ball.")
    w("")
    w("jug_x:")
    for i in range(0, STEPS, 8):
        w("\tDATA BYTE " + ",".join("%3d" % v for v in xs[i:i + 8]))
    w("")
    w("jug_y:")
    for i in range(0, STEPS, 8):
        w("\tDATA BYTE " + ",".join("%3d" % v for v in ys[i:i + 8]))

    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(L) + "\n")

    print("wrote %s" % os.path.normpath(OUT))
    print("  ellipse rx=%d ry=%d centre (128,%d), speed warp %.1f" % (rx, ry, cy, power))
    print("  x %d..%d, y %d..%d  (ball top-left, sprite coords)"
          % (min(xs), max(xs), min(ys), max(ys)))
    print("  worst scanline: %d sprites of %d allowed (phase %d, line %d)"
          % (worst, MAXLINE, where[0], where[1]))
    print("  table %d B (%d steps x 2)" % (STEPS * 2, STEPS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
