#!/usr/bin/env python3
"""Prove checkspace.py rejects both spacings that were actually played.

A CHECK WHOSE SCOPE IS NARROWER THAN THE BUG IS WORSE THAN NO CHECK, because it
reports success. This one has two known-bad inputs, and they fail for opposite
reasons -- which is the point, because the first fix for the first of them WAS
the second of them:

  70 px   THE DANGEROUS MIDDLE. Shipped on screens 4, 5 and 6 (screens 1 and 2
          got 46 px, which is fine), because the second hazard sat at
          `(lx AND 63) + 64` and the gap was a difference of two placement
          bytes. Too far apart for one jump to clear both, too close to land
          between.

  176 px  THE SECOND HAZARD IN THE DOORWAY. The first attempt at fixing 70 --
          size the gap so a jump fits between the pair. `stag` is distance from
          the FAR edge, so widening the gap moves the second hazard TOWARD the
          player: at 176 it starts about 64 px from the wall he walks in
          through and there is no time to read it. Reported from play as "the
          2nd ball seems to be placed where the player is entering, and
          immediately the player cannot dodge".

Both are checked against the real constants, so if the jump arc or the walking
speed ever change these move with them.

Run:  python3 checkspace_test.py
"""

import sys

import checkspace as cs


def main():
    src = cs.read(cs.BAS)
    store = cs.read(cs.STORE)
    walk = cs.const(src, "WALKSP")
    hold, air = cs.jump_arc(store)
    slow = min(cs.hazard_speeds(src))
    close = walk + slow
    together = hold * close
    between = air * close
    shipped = cs.const(src, "HAZGAP")

    print("checkspace_test -- one jump clears both at <= %d px, landing "
          "between needs >= %d px" % (together, between))
    print("                   the nearer hazard must have >= %d px at entry"
          % cs.WARNPX)
    good = True

    def check(label, gap, want_ok):
        near = cs.SPAN - cs.STAG0_MAX - gap
        ok_gap = cs.verdict(gap, together, between) is not None
        ok_near = near >= cs.WARNPX
        ok = ok_gap and ok_near
        why = []
        if not ok_gap:
            why.append("dangerous middle")
        if not ok_near:
            why.append("starts %d px from the entry" % near)
        print("   %-28s gap %3d px  %-9s %s"
              % (label, gap, "accepted" if ok else "rejected",
                 "ok" if ok == want_ok else "WRONG -- " + (", ".join(why) or
                                                           "no reason given")))
        return ok == want_ok

    print()
    print("  the two that were played:")
    good &= check("shipped, screens 4/5/6", 70, False)
    good &= check("first fix attempt", 176, False)

    print()
    print("  and the one that is shipped now:")
    good &= check("current HAZGAP", shipped, True)

    print()
    print("  the boundaries themselves:")
    good &= check("exactly the one-jump limit", together, True)
    good &= check("one past it", together + 1, False)

    print()
    if not good:
        print("checkspace_test FAILED -- checkspace does not reject a spacing "
              "that was played and found broken, or rejects the one shipped")
        return 1
    print("checkspace_test OK -- rejects the dangerous middle AND the doorway "
          "case, accepts what is shipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
