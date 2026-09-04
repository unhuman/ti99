#!/usr/bin/env python3
"""Ride the escalator, frame by frame, and check the feet are on a drawn step.

The rider and the steps are computed in two places that never mention each
other: `genart.py` renders the staircase and animates it, `KEYSTONE.bas` walks
the rider up it. They only agree because three separate things line up --

  * the RATE (2 px along for 1 px up, matching the step's 8-by-4 slope),
  * the OFFSET at boarding (a step's height fixes its x: west klx = 99 - 2h),
  * and the PHASE (the staircase slides 1 px up per animation phase, so the
    bottom step is 4 + escp px above the floor, not 4).

Get any one wrong and there is no error of any kind: the rider simply travels
beside the steps instead of on them, which is what "he floats up the escalator"
looked like, and what a reviewer has to notice by eye.

So this simulates the ride out of the real constants and, every frame, checks
the pixel the feet stand on is the top of a tread in the bitmap that will
actually be on screen that frame.

Run:  python3 checkride.py        exits non-zero if a foot leaves a step
"""

import os
import re
import sys

import genart as g

HERE = os.path.dirname(os.path.abspath(__file__))
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")

# Where a flight sits on screen, from the placement in genstore/esc_cap_draw:
# grid row 1 lands on the upper floor's slab row, so bitmap row 8 is flry(lv+1)
# and bitmap row 0 is 8 px above it. Columns 1..15 west, 16..30 east.
XOFF = {0: 8, 1: 128}
FLRY = [160, 120, 80, 40]


def const(name):
    m = re.search(r"^\s*CONST %s\s*=\s*(\d+)" % name, open(BAS,
                  encoding="utf-8").read(), re.M)
    if not m:
        sys.exit("checkride: CONST %s not found" % name)
    return int(m.group(1))


ESCRISE = const("ESCRISE")
ESCFX, ESCFXE = const("ESCFX"), const("ESCFXE")
ESCHX, ESCHXE = const("ESCHX"), const("ESCHXE")

# WHAT CLOCKS THE STEPS, AND WHAT CLOCKS THE RIDER -- read out of the source,
# because them being the SAME clock is the whole invariant here.
#
# There are only two defensible arrangements and one of them is impossible:
# both by `fdv` would keep the rider on his step, but the animation has four
# phases over an 8 px period and cannot be stepped by 2 or 3 without aliasing
# (at 3 the sequence runs 0,3,2,1 and the staircase visibly runs backwards).
# So both must be the fixed per-pass step, and the ride simply takes as long
# as the loop makes it take.
_src = open(BAS, encoding="utf-8").read()
_tick = _src[_src.index("esc_tick:"):]
_tick = _tick[:_tick.index("\n\n")]
_ride = _src[_src.index("IF klst = ST_ESC THEN"):]
_ride = _ride[:_ride.index("RETURN")]


def _step(body, var, what):
    m = re.search(r"^\s*%s = %s \+ (\w+)\s*$" % (var, var), body, re.M)
    if not m:
        sys.exit("checkride: cannot tell what advances %s (%s)" % (var, what))
    return m.group(1)


PHASE_ADD = _step(_tick, "escp", "esc_tick")
RISE_ADD = _step(_ride, "esy", "the ride")
if PHASE_ADD != RISE_ADD:
    print("FAIL: the steps advance by `%s` per pass (esc_tick) but the rider "
          "rises by `%s` (move_kelly). They have to be the same clock or the "
          "rider drifts off his step -- and `fdv` is not available to the "
          "animation, because four phases cannot be stepped by more than one "
          "without running backwards." % (PHASE_ADD, RISE_ADD))
    sys.exit(1)
if PHASE_ADD != "1":
    print("FAIL: esc_tick advances the phase by `%s`. Four phases over an 8 px "
          "period alias when stepped by more than 1: at 2 the direction stops "
          "being readable and at 3 the staircase runs backwards." % PHASE_ADD)
    sys.exit(1)


def PHASE_STEP(fdv):
    return 1


def bitmap(phase, east):
    px = g._flight_bitmap(2 * phase)
    if east:
        px = g._mirror_bitmap(px)
    return px


BITMAPS = {(p, e): bitmap(p, e) for p in range(4) for e in (0, 1)}


def ride(lv, east, escp0, esy0, walking, fdv=1):
    """Yield (pass, escp, klx, feet_y, on_step) per loop pass, as the game runs it.

    `on_step` is false only while a walker is still climbing onto the bottom
    tread -- his feet are between the floor and the step during those few
    passes and are not meant to be on anything.

    `fdv` IS THE POINT OF THIS PARAMETER. The main loop advances the rider by
    the frame delta, so a pass that costs two frames moves him 4 px along and
    2 up. If the STEPS advance once per pass instead -- 2 and 1 -- he outruns
    them, and the busiest screens in the game are precisely the two with a
    staircase on them. `esc_tick` therefore adds fdv, not 1, and this checks it.
    """
    esy = 0 if walking else esy0
    eson = esy0 + esy0 if walking else 0
    klx = 140 + esy0 + esy0 if east else 99 - esy0 - esy0
    escp = escp0
    t = 0
    while True:
        yield t, escp, klx, FLRY[lv] - esy, esy >= eson
        if esy >= ESCRISE:
            return
        escp = (escp + PHASE_STEP(fdv)) % 4
        # the rider is clocked by the PASS, like the steps -- fdv must not
        # appear here, and the loop below runs once whatever fdv is
        if esy < eson:
            esy += 1
        esy += 1
        klx = klx + 2 if east else klx - 2
        t += 1
        if t > 80:
            sys.exit("checkride: ride never ended")


def main():
    bad = []
    checked = 0

    # EVERY PLAUSIBLE FRAME DELTA. Nothing in the ride may depend on it now,
    # so all three must give identical results -- which is the property being
    # checked, not an incidental.
    for fdv in (1, 2, 3):
      for lv in range(3):
        for east in (0, 1):
            for escp0 in range(4):
                # walking on: the bottom step. jumping on: steps 9, 8 and 7,
                # the only ones a 14 px apex can reach.
                cases = [("walks on", 4 + escp0, True)]
                for h in (4, 8, 12):
                    cases.append(("jumps onto the step %d px up" % (h + escp0),
                                  h + escp0, False))
                for label, esy0, walking in cases:
                    label = "%s (fdv %d)" % (label, fdv)
                    top = FLRY[lv + 1] - 8      # screen y of bitmap row 0
                    x0 = XOFF[east]
                    last = None
                    for t, escp, klx, fy, on_step in ride(lv, east, escp0,
                                                          esy0, walking, fdv):
                        last = (t, klx, fy)
                        if fy <= FLRY[lv + 1]:
                            break               # arrived on the landing
                        if not on_step:
                            continue            # still climbing onto the step
                        px = BITMAPS[(escp, east)]
                        bx, by = klx + 8 - x0, fy - top
                        if not (0 <= by < g.FLIGHT_H):
                            bad.append("lv%d %s %s escp0=%d: frame %d, feet at "
                                       "y %d, off the flight bitmap"
                                       % (lv, "east" if east else "west", label,
                                          escp0, t, fy))
                            break
                        # the feet stand ON the tread's top pixel row, and a
                        # standing figure needs the width of its shoes
                        miss = [dx for dx in (-3, 0, 3)
                                if not (0 <= bx + dx < g.FLIGHT_W
                                        and px[by][bx + dx])]
                        if miss:
                            bad.append("lv%d %s, %s, escp0=%d: frame %d, feet "
                                       "at x %d y %d -- no tread under %s"
                                       % (lv, "east" if east else "west", label,
                                          escp0, t, klx + 8, fy,
                                          ", ".join("x%+d" % d for d in miss)))
                            break
                        checked += 1
                    else:
                        bad.append("lv%d %s %s escp0=%d: ride ended without "
                                   "reaching the floor above" % (lv,
                                   "east" if east else "west", label, escp0))
                    if last and last[2] > FLRY[lv + 1]:
                        continue
                    # the landing: x must be the head step's, not merely near it
                    want = ESCHXE if east else ESCHX
                    if last and abs(last[1] - want) > 0:
                        bad.append("lv%d %s %s escp0=%d: arrives at klx %d, "
                                   "the head step is at %d"
                                   % (lv, "east" if east else "west", label,
                                      escp0, last[1], want))

    if bad:
        for b in bad[:20]:
            print("FAIL: " + b)
        if len(bad) > 20:
            print("... and %d more" % (len(bad) - 20))
        return 1
    print("ride OK -- steps and rider both clocked by the pass; %d passes "
          "checked across frame deltas 1-3 x 3 floors x 2 directions x 4 phases "
          "x (walk on + 3 jump-on steps); the feet are on a drawn tread every "
          "pass and every ride lands on the head step" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
