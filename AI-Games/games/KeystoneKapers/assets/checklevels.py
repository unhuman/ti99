#!/usr/bin/env python3
"""Hold the Krook progression to the one the original actually uses.

The table below is not a design choice, it is RESEARCH -- two independent
readings of the published level guides agree on it:

    1  short beach balls, nothing else      5  balls go tall
    2  + radios                             6  a second hazard per floor
    3  + shopping carts                     7  carts get faster
    4  + biplanes                           8+ biplanes get faster

Nothing in the source says where those numbers came from, and every one of them
is a bare integer in an `IF krk < n` or `IF krk > n` that a later tuning pass
would happily nudge. So this reads the real comparisons back out of
src/KEYSTONE.bas and fails the build if any of them moves.

The threshold convention is the trap this exists to catch: a hazard that ARRIVES
at Krook n is written `IF krk < n THEN ...` (suppressed below n), while a dial
that CHANGES at Krook n is written `IF krk > n-1 THEN ...`. Those are the same
level expressed two different ways, and mixing them up shifts a hazard by one
round with nothing to show for it.

Run:  python3 checklevels.py       exits non-zero if the progression drifts
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")

# what arrives, and on which Krook -- written as `IF krk < n`
ARRIVES = {
    "OB_RADIO": 2,
    "OB_CART": 3,
    "OB_PLANE": 4,
}
# dials that change, and on which Krook -- written as `IF krk > n-1`
CHANGES = {
    "tall balls (arcs = 1)": (r"arcs = 0\s*\n\s*IF krk > (\d+) THEN arcs = 1", 5),
    # WHICH KINDS DOUBLE, AND FROM WHEN -- one threshold per kind, measured
    # frame by frame from a full 2600 playthrough (assets/ref2600/hazards.md).
    # This was a SINGLE gate at Krook 6 for every kind, which put two balls on a
    # floor five rounds early and paired biplanes, which the original never does
    # in 21 levels. Biplanes are the hazard that must be DUCKED rather than
    # jumped, so a pair of them is a different question from a pair of anything
    # else -- and the answer the original gives is "no".
    #
    # Each pattern runs on to the `IF krk < ldbl` that CONSUMES the threshold.
    # That is not padding: this loop infers the threshold convention from the
    # text it matched, so a pattern stopping at the assignment reads as the
    # `krk >` form and reports every kind one Krook late. Carrying the gate into
    # the match settles the convention and pins that the threshold really is
    # spent on a suppress-below test.
    "second radio": (r"IF lk = OB_RADIO THEN ldbl = (\d+)[\s\S]{0,200}?"
                     r"IF krk < ldbl", 6),
    "second ball": (r"IF lk = OB_BALL THEN ldbl = (\d+)[\s\S]{0,200}?"
                    r"IF krk < ldbl", 9),
    "second cart": (r"IF lk = OB_CART THEN ldbl = (\d+)[\s\S]{0,200}?"
                    r"IF krk < ldbl", 11),
    "carts faster": (r"IF krk > (\d+) THEN ocsp", 7),
    "biplanes faster": (r"IF krk > (\d+) THEN opsp", 8),
    # HOW MANY FLOORS CARRY A HAZARD AT ALL. The kind-arrival gates above turn
    # a hazard that has not arrived into a beach ball rather than nothing, so
    # without these two every floor was occupied from Krook 1 -- four identical
    # balls in view at once, where the original is "merely a few". Floor 1 joins
    # on Krook 2 and the roof on Krook 3.
    "floor 1 occupied": (r"IF krk < (\d+) THEN\s*\n\s*IF llv = 1 THEN lk = 0", 2),
    "roof occupied": (r"IF krk < (\d+) THEN\s*\n\s*IF llv = 3 THEN lk = 0", 3),
}


def main():
    src = open(BAS, encoding="utf-8").read()
    bad = []

    for kind, want in sorted(ARRIVES.items()):
        m = re.search(r"IF lk = %s THEN\s*\n\s*IF krk < (\d+) THEN lk = OB_BALL"
                      % kind, src)
        if not m:
            bad.append("%s: no `IF lk = %s THEN / IF krk < n THEN lk = OB_BALL` "
                       "gate found -- the hazard is not being held back at all"
                       % (kind, kind))
            continue
        got = int(m.group(1))
        if got != want:
            bad.append("%s arrives at Krook %d, should be %d" % (kind, got, want))
        else:
            print("  %-10s arrives at Krook %d" % (kind, got))

    for name, (pat, want) in sorted(CHANGES.items()):
        m = re.search(pat, src)
        if not m:
            bad.append("%s: pattern not found -- the dial has been rewritten, "
                       "so this check no longer covers it" % name)
            continue
        got = int(m.group(1))
        # `IF krk > n` fires from n+1; `IF krk < n` suppresses below n
        at = got if "krk < " in m.group(0) else got + 1
        if at != want:
            bad.append("%s changes at Krook %d, should be %d" % (name, at, want))
        else:
            print("  %-24s changes at Krook %d" % (name, at))

    # Krook 1 must be beach balls and nothing else -- the whole point of the
    # progression is that the thing which costs a life is not the first thing
    # a new player meets.
    if "IF lk = OB_PLANE THEN" not in src:
        bad.append("nothing suppresses biplanes on the early Krooks")

    # BIPLANES NEVER COME IN TWOS. One, in every one of the 21 levels reached in
    # the measured playthrough, across 800+ frame-sightings -- every other hazard
    # doubles and this one does not. It is also the only hazard that must be
    # DUCKED, so a pair is a different problem from a pair of anything else.
    #
    # The rule is expressed as an ABSENCE -- the default `ldbl` is never lowered
    # for OB_PLANE -- and an absence is exactly what a later edit reinstates
    # without noticing, so it is checked rather than trusted.
    m = re.search(r"ldbl = (\d+)\s*'", src)
    if not m:
        bad.append("no default `ldbl` -- the per-kind doubling table has been "
                   "rewritten and biplanes may now pair")
    elif int(m.group(1)) <= 21:
        bad.append("the default doubling Krook is %s, which is inside the range "
                   "the original was measured over -- biplanes would pair"
                   % m.group(1))
    if re.search(r"IF lk = OB_PLANE THEN ldbl", src):
        bad.append("biplanes have been given a doubling Krook; the original "
                   "never puts two on one floor (assets/ref2600/hazards.md)")
    if not bad:
        print("  %-24s never double" % "biplanes")

    if bad:
        print()
        for b in bad:
            print("FAIL  " + b)
        return 1
    print("\nOK: the Krook progression matches the published one.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
