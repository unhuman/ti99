#!/usr/bin/env python3
"""Two hazards on one floor must be takeable, and must not start on the player.

THERE ARE ONLY TWO SAFE GAPS. Kelly closes on an oncoming hazard at
(KWALK64 + its speed)/64 px a FRAME, and the jump arc holds its 14 px apex for 9
FRAMES and is airborne for 28. So:

    gap <=  22 px   ONE JUMP CLEARS BOTH
    gap >=  82 px   he can LAND BETWEEN them

Anything between those is the dangerous middle: too far apart to clear together,
too close to land between.

WHAT SHIPPED. The second hazard sat at `(lx AND 63) + 64`, so the gap was a
difference of two placement bytes -- 46 px on screens 1 and 2, 70 px on 4, 5 and
6. Screens 2 and 4 flank the lift, which is how it surfaced: "on the left and
right of the elevator they seem closer together". 46 is inside the one-jump
window and fine; **70 is squarely in the dangerous middle**, and that is the
actual defect the asymmetry was pointing at.

THE SECOND WINDOW *IS* AVAILABLE, AND THIS FILE SAID OTHERWISE FOR MONTHS. It
argued that a gap big enough to land in puts the second hazard in the doorway --
"at 168 px it starts within 72 px of the wall he walks in through". Both numbers
came from multiplying the arc's length by a per-PASS speed when the arc is
indexed in FRAMES, so the whole window was inflated about 2.4x. Landing between
needs 82 px, not 168, and 82 + the 120 px reaction budget fits inside the 240 px
of placeable floor with room to spare. A wrong unit did not just misplace the
threshold: it argued a whole design option out of existence, and the game
shipped a pair taken as one obstacle because of it.

The price is that slot 0's jitter must narrow -- see stag0_max() -- so this file
still checks the entry distance as well as the gap. A spacing rule that only
looks at the pair will happily put one of them in the doorway.

MEASURED AGAINST THE ORIGINAL. assets/ref2600/hazards.md counts hazards frame by
frame through a full 2600 playthrough: two MOVING hazards on one floor are never
closer than 108 px in our scale across 21 levels, and static radios come as close
as 54. The thresholds derived here from our own arc -- 82 moving, 49 static --
sit just below each, from evidence that knows nothing about this jump. That
agreement is the strongest check this model has.

WHY NO OTHER CHECK SEES ANY OF THIS. checkball.py sweeps a SINGLE ball against
the jump and the crouch and is right about every frame of it; checklevels.py
pins WHEN the second hazard arrives and is right about that. Neither asks
whether two hazards that are each individually fair are fair together. A
property of a pair is invisible to every check written about one of them.

Run:  python3 checkspace.py
"""

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")
STORE = os.path.join(HERE, "..", "src", "store.bas")

# The walkable width a hazard is placed across -- `obx = 240 - stag`.
SPAN = 240
# How much clear ground the NEARER hazard must have at entry, in pixels. 120 is
# twenty passes, about eight tenths of a second: enough to see it and commit to
# a jump. Not derived -- a reaction budget is a judgement, and it is written
# here rather than buried so it can be argued with.
WARNPX = 120


def read(path):
    return io.open(path, encoding="utf-8").read()


def const(src, name):
    m = re.search(r"CONST %s = (\d+)" % name, src)
    if not m:
        sys.exit("checkspace: no CONST %s in KEYSTONE.bas -- the source shape "
                 "changed and this check is now blind" % name)
    return int(m.group(1))


def jump_arc(store):
    """(apex hold, airborne) in passes, read off the shipped arc."""
    m = re.search(r"^jarc_tbl:.*?\n((?:\s*DATA BYTE .*\n)+)", store, re.M)
    if not m:
        sys.exit("checkspace: no jarc_tbl in store.bas")
    vals = []
    for line in m.group(1).strip().split("\n"):
        vals += [int(v) for v in line.split("DATA BYTE", 1)[1].split(",")]
    top = max(vals)
    return sum(1 for v in vals if v == top), sum(1 for v in vals if v > 0)


def hazard_speeds(src):
    out = []
    for var in ("obsp", "ocsp", "opsp"):
        out += [int(v) for v in re.findall(r"\b%s = (\d+)" % var, src)]
    if not out:
        sys.exit("checkspace: found no hazard speeds in start_krook")
    return sorted(set(out))


def stag0_max(src):
    """The widest slot 0 can stagger in from the far edge, WHEN PAIRED.

    This was hard-coded as 63, and it stopped being true the moment the gap grew
    past the one-jump window: a pair spanning HAZGAP has to leave the player his
    reaction distance at the entry wall too, and the three do not fit in 240 px
    unless slot 0's jitter narrows. The source narrows it with a second mask
    applied from the first doubling, so the number this check needs is that
    mask -- read it, rather than restating a constant that has moved once
    already and would fail silently by being generous.
    """
    m = re.search(r"IF krk > \d+ THEN stag = lx AND (\w+)", src)
    if not m:
        sys.exit("checkspace: no paired-case stagger mask (`IF krk > n THEN "
                 "stag = lx AND ...`) -- the placement rule changed and the "
                 "entry-distance test below is now measuring the wrong thing")
    name = m.group(1)
    return int(name) if name.isdigit() else const(src, name)


def stagger_rule(src):
    """What slot 1 is offset from, and by what. Checked by NAME.

    The defect this file exists for was a magic 64 where a reasoned distance
    belongs. A check that only compared numbers would pass the moment somebody
    wrote the right number in by hand and then had no reason to keep it in step
    with the jump.
    """
    m = re.search(r"IF ls = 1 THEN stag = (\w+) \+ (\w+)", src)
    if not m:
        sys.exit("checkspace: could not find the slot-1 stagger rule -- the "
                 "source shape changed and this check is now blind")
    return m.group(1), m.group(2)


def verdict(gap, together, between):
    if gap <= together:
        return "one jump clears both"
    if gap >= between:
        return "can land between them"
    return None


def main():
    src = read(BAS)
    store = read(STORE)

    walk = const(src, "KWALK64")
    gap = const(src, "HAZGAP")
    hold, air = jump_arc(store)
    speeds = hazard_speeds(src)
    base, off = stagger_rule(src)
    stagmax = stag0_max(src)

    # FRAMES AND SIXTY-FOURTHS OF A PIXEL, WHICH IS WHAT THE MACHINE USES.
    #
    # This multiplied the arc's length by a per-PASS speed, and the arc is
    # indexed by `kjf`, which advances by the frame delta -- so its entries are
    # FRAMES and always were. Passes are about 2.4 frames, so every closing
    # distance printed here came out roughly 2.4x too large, and the gap the
    # game ships was chosen against those inflated numbers.
    #
    # Both sides are per-frame now: Kelly by KWALK64 and the hazards by obsp
    # and friends, all in sixty-fourths of a pixel per frame.
    #
    # THE TWO BOUNDS HAVE OPPOSITE WORST CASES, AND USING ONE SPEED FOR BOTH
    # MAKES THE SECOND OF THEM OPTIMISTIC.
    #
    # Clearing a pair together is hardest against the SLOWEST hazard: the slower
    # the pair closes, the fewer pixels drift past underneath during the apex
    # hold, so the gap that still fits is smaller.
    #
    # Landing between them is hardest against the FASTEST: the whole airborne
    # time is spent closing, so a quicker hazard eats more ground and the gap
    # has to be bigger. Computing it from the slowest speed -- which this file
    # did -- reports a threshold the fast rounds do not meet, and it never
    # showed because the shipped gap sits in the other window entirely.
    slow, fast = min(speeds), max(speeds)
    close = (walk + slow) / 64.0            # px per frame, slowest hazard
    close_f = (walk + fast) / 64.0          # px per frame, fastest hazard
    together = int(hold * close)
    between = int(air * close_f) + 1
    near = SPAN - stagmax - gap

    print("jump holds its apex %d frames and is airborne %d; closing %.2f "
          "px/frame at the slowest hazard and %.2f at the fastest"
          % (hold, air, close, close_f))
    print("  one jump clears both at   <= %3d px" % together)
    print("  landing between needs     >= %3d px" % between)
    print("  HAZGAP is %d px -- %s" % (gap, verdict(gap, together, between)
                                       or "THE DANGEROUS MIDDLE"))
    print("  nearer hazard at entry:   >= %3d px (%.1f frames of warning)"
          % (near, near / close))

    bad = []

    if off != "HAZGAP":
        bad.append("slot 1 is offset by `%s`, not HAZGAP -- the gap has to be "
                   "reasoned from the jump, not written in by hand" % off)
    if base != "stg0":
        bad.append("slot 1 is measured from `%s`, not from slot 0's own "
                   "stagger -- the GAP then still varies by screen even though "
                   "the offset is fixed, which is the shipped defect in a "
                   "politer form" % base)

    if verdict(gap, together, between) is None:
        bad.append("HAZGAP is %d px: too far apart for one jump to clear both "
                   "(<= %d) and too close to land between (>= %d). That is the "
                   "dangerous middle -- the player clears the first and comes "
                   "down onto the second." % (gap, together, between))

    if near < WARNPX:
        bad.append("the nearer hazard can start %d px from where the player "
                   "walks in, under the %d px reaction budget -- `stag` is "
                   "distance from the FAR edge, so widening the gap moves the "
                   "second hazard TOWARD him" % (near, WARNPX))

    # ...and the same window per speed, for the record. This compared a gap in
    # PIXELS against a product in sixty-fourths of a pixel, so its threshold came
    # out 64x too large and the note could never fire.
    for sp in speeds:
        if sp > slow:
            lim = int(hold * (walk + sp) / 64.0)
            if gap > lim:
                print("  NOTE at speed %d a pair needs <= %d px to clear "
                      "together; this gap does not" % (sp, lim))

    if bad:
        print()
        print("checkspace FAILED")
        for b in bad:
            print("  " + b)
        return 1
    print("spacing OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
