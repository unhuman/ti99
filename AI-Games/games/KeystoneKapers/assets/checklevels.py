#!/usr/bin/env python3
"""Hold the Krook progression to the one the original actually uses.

THIS USED TO READ THE GATES OUT OF THE SOURCE, and there are no gates any more.
Arrivals, doubling and floor occupancy were a ladder of `IF krk < n` tests inside
`load_band`; they are a per-Krook DATA TABLE now (`genstore.levels()`, emitted as
`stor_lvl`), because those gates could only express things about
(Krook, floor, kind) and the original needs "this screen is empty" and "this
floor has a cart here and a plane there".

So the assertions moved with the thing they assert. What is checked here:

    from the TABLE      arrivals, doubling, the roof's no-biplane rule, no
                        parked hazard on a boarding zone, the DENSITY CURVE,
                        and that level 1 really has an empty screen
    from the SOURCE     the dials that are still code -- tall balls, cart and
                        biplane speeds -- and the time bonus

**The density curve is the assertion this file exists for now.** Everything else
was already pinned somewhere; "how much is on screen" never was, and it is what
was reported from play: *"the obstacle density, especially on the early levels is
wrong"*. The targets are measured, not chosen -- see assets/ref2600/hazards.md.

Run:  python3 checklevels.py       exits non-zero if the progression drifts
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")

sys.path.insert(0, HERE)
import genstore as g                                    # noqa: E402

# Dials that are still CODE, and the Krook they change on. The convention is the
# trap this half exists to catch: a hazard that ARRIVES at Krook n is written
# `IF krk < n` (suppressed below n), while a dial that CHANGES at n is written
# `IF krk > n-1`. Those are the same level expressed two ways, and mixing them up
# shifts a dial by one round with nothing to show for it.
CHANGES = {
    "tall balls (arcs = 1)": (r"arcs = 0\s*\n\s*IF krk > (\d+) THEN arcs = 1", 5),
    "carts faster": (r"IF krk > (\d+) THEN ocsp", 7),
    "biplanes faster": (r"IF krk > (\d+) THEN opsp", 8),
}

# WHAT THE ORIGINAL DOES, WRITTEN HERE AND NOT IMPORTED FROM THE GENERATOR.
#
# The first version of this file read `genstore.ARRIVE` and `genstore.DOUBLE` for
# its expectations, which makes the assertion vacuous: it only proves the
# generator obeys its own constant. Running it against a mutated generator proved
# exactly that -- moving `DOUBLE[BALL]` from 9 to 6 moved the table AND the
# expectation together, and the check reported success on a table that pairs
# balls three rounds early.
#
# These are the measured numbers from assets/ref2600/hazards.md. Two independent
# statements of the same fact is the whole point; if they disagree, one of them
# is wrong and the build stops.
ARRIVE_WANT = {g.BALL: 1, g.RADIO: 2, g.CART: 3, g.PLANE: 4}
DOUBLE_WANT = {g.RADIO: 6, g.BALL: 9, g.CART: 11}       # biplanes: never
# The most hazards ever seen on ONE SCREEN at once, per level, measured.
#
# HELD HERE, NOT IMPORTED -- reading `genstore.MAXLOAD` for the expectation makes
# the check vacuous in exactly the way the note above describes, and the first
# version of this assertion did precisely that: raising the generator's cap
# raised the checker's threshold with it and a table piling ten onto one screen
# reported success.
#
# AND IT WAS A SINGLE NUMBER, 7, WHICH IS NO CONSTRAINT ON THE EARLY ROUNDS.
# Krook 1 places five hazards and put three of them on one screen -- a wall of
# balls with the rest of the store empty -- while a game-wide cap of seven sat
# there being satisfied. The original never shows more than TWO at once on level
# 1, in 57 sampled frames. A cap that only binds at the end of the game does not
# describe the shape of the beginning.
MAXLOAD_WANT = {1: 2, 2: 3, 3: 4, 4: 5, 5: 5, 6: 7,
                7: 7, 8: 7, 9: 7, 10: 8, 11: 9}

# HAZARDS VISIBLE ON ONE SCREEN, MEASURED OFF THE ORIGINAL -- its AISLE screens,
# against our PLACEABLE screens. From assets/ref2600/hazards.md.
#
# THE FIRST VERSION AVERAGED OVER ALL EIGHT SCREENS ON BOTH SIDES, and that is
# not like for like: nothing may ever stand on our two escalator screens, so a
# whole-store average is a quarter lower by construction and no table could reach
# a figure measured on a game that does put hazards on its end screens. It made
# Krook 7 look 0.52 short of a target it could not have hit.
#
# The sample dips at levels 5 and 10 (n is about thirty frames each), so the
# target is the running maximum -- the trend the design follows, not the noise.
DENSITY = {1: 0.71, 2: 1.50, 3: 2.47, 4: 3.28, 5: 3.28, 6: 3.97,
           7: 4.04, 8: 4.50, 9: 4.97, 10: 4.97, 11: 5.15}
# Half a hazard a screen. Tighter than the measurement deserves at n=30, and
# loose enough that the table is not fitted to sampling noise.
DENSITY_TOL = 0.5

NAME = {g.CART: "cart", g.BALL: "ball", g.RADIO: "radio", g.PLANE: "biplane"}


def rows():
    """[krook] -> the 32 band bytes for that Krook."""
    flat = g.levels()
    return {k: flat[(k - 1) * 32:k * 32] for k in range(1, g.KROOKS + 1)}


def main():
    src = open(BAS, encoding="utf-8").read()
    bad = []
    table = rows()

    # ---------------------------------------------------------------- arrivals
    # The first Krook each kind appears on anywhere in the store.
    first = {}
    for k in range(1, g.KROOKS + 1):
        for b in table[k]:
            kind = b & 7
            if kind and kind not in first:
                first[kind] = k
    for kind, want in sorted(ARRIVE_WANT.items()):
        got = first.get(kind)
        if got is None:
            bad.append("%s never appears at any Krook" % NAME[kind])
        elif got != want:
            bad.append("%s first appears on Krook %d, should be %d"
                       % (NAME[kind], got, want))
        else:
            print("  %-10s arrives at Krook %d" % (NAME[kind], got))

    # ---------------------------------------------------------------- doubling
    # The first Krook each kind is given a second slot. Biplanes must never be:
    # one, in every one of the 21 levels of the measured playthrough, and they
    # are the only hazard that must be DUCKED rather than jumped, so a pair is a
    # different problem from a pair of anything else.
    dbl = {}
    for k in range(1, g.KROOKS + 1):
        for b in table[k]:
            kind = b & 7
            if kind and (b & 8) and kind not in dbl:
                dbl[kind] = k
    for kind, want in sorted(DOUBLE_WANT.items()):
        got = dbl.get(kind)
        if got is None:
            bad.append("%s is never doubled; the original pairs it from Krook %d"
                       % (NAME[kind], want))
        elif got != want:
            bad.append("%s is first doubled on Krook %d, should be %d"
                       % (NAME[kind], got, want))
        else:
            print("  %-10s doubles at Krook %d" % (NAME[kind], got))
    if g.PLANE in dbl:
        bad.append("biplanes are doubled at Krook %d; the original never puts "
                   "two on one floor (assets/ref2600/hazards.md)" % dbl[g.PLANE])
    else:
        print("  %-10s never doubles" % "biplane")

    # ------------------------------------------------- placement side-conditions
    for k in range(1, g.KROOKS + 1):
        for band, b in enumerate(table[k]):
            kind = b & 7
            if not kind:
                continue
            lv, scr = band // 8, band % 8
            # NOTHING AT ALL ON AN ESCALATOR SCREEN, on any Krook. That is where
            # the player has to stop and board; a hazard there is a toll on a
            # manoeuvre the game has already committed them to. It is a property
            # of the TEMPLATE, not of a screen number -- floors 0 and 2 climb
            # from screen 0 and floor 1 from screen 7.
            if g.esc_band(lv, scr):
                bad.append("Krook %d puts a %s on the ESCALATOR screen "
                           "(floor %d screen %d)" % (k, NAME[kind], lv, scr))
            # The roof is where the round is decided and a biplane costs a whole
            # Kop rather than nine seconds. The measurement agrees: the
            # original's roof shows only radios and carts, at every level.
            if lv == 3 and kind == g.PLANE:
                bad.append("Krook %d puts a biplane on the ROOF (screen %d)"
                           % (k, scr))
            # AND NO RADIO ON THE ROOF. A radio is drawn as CHARACTERS, so it
            # shares its cells' two colours with whatever it stands on -- flat
            # green on a shop floor, the parallax skyline on the roof. Reported
            # from play as "the colors get messed up". This one is ours, not the
            # original's: the 2600 does put radios up there.
            if lv == 3 and kind == g.RADIO:
                bad.append("Krook %d puts a radio on the ROOF (screen %d); it is "
                           "drawn as characters and the skyline has already "
                           "spent both colours of every cell" % (k, scr))
            # A radio does not move, so it is the only hazard that can PARK on a
            # boarding zone. A rolling cart crossing the escalator foot is a
            # hazard; a radio sitting on it is a toll.
            if kind == g.RADIO and not g._radio_ok(g.INDEX[lv][scr]):
                bad.append("Krook %d puts a radio on floor %d screen %d, whose "
                           "boarding zone a rack position would sit on"
                           % (k, lv, scr))

    # ----------------------------------------------------------------- density
    # THE ONE THAT WAS NEVER PINNED. Reported from play as too dense on the
    # early levels; the port showed two hazards on level 1 where the original
    # shows a median of nought.
    print()
    for k in range(1, g.KROOKS + 1):
        got, want = g.density(k), DENSITY[k]
        if abs(got - want) > DENSITY_TOL:
            bad.append("Krook %d shows %.2f hazards a screen; the original "
                       "shows %.2f (tolerance %.2f)"
                       % (k, got, want, DENSITY_TOL))
        else:
            print("  Krook %-2d  %.2f hazards a screen (original %.2f)"
                  % (k, got, want))

    # NO SCREEN MAY BE A WALL OF HAZARDS. Seven is the most ever seen on screen
    # at once in the measured playthrough. Matching the AVERAGE says nothing
    # about this: spending the doubling budget in fill order gave one screen TEN
    # while another had one, which reads as an impassable stretch next to an
    # empty one. Reported as "sometimes the distribution feels heavy on certain
    # screens".
    for k in range(1, g.KROOKS + 1):
        for s in range(8):
            n = 0
            for lv in range(4):
                b = table[k][lv * 8 + s]
                kind = b & 7
                if kind:
                    n += 1
                    if b & 8:
                        n += 1
                        if kind == g.RADIO and k > 7:
                            n += 1
            if n > MAXLOAD_WANT[k]:
                bad.append("Krook %d screen %d carries %d hazards; the original "
                           "never shows more than %d at once"
                           % (k, s, n, MAXLOAD_WANT[k]))

    # AND AT LEAST ONE SCREEN OF LEVEL 1 MUST BE COMPLETELY BARE -- all four
    # floors. Under the old gates a populated screen could never be empty on any
    # Krook, which is precisely the defect this replaced; a density figure alone
    # would not catch its return, because an average can be met by spreading
    # thinly everywhere.
    empty = [s for s in range(8)
             if not any(table[1][lv * 8 + s] & 7 for lv in range(4))]
    if not empty:
        bad.append("every screen of Krook 1 carries a hazard on some floor; the "
                   "original's level 1 has a median of ZERO on screen")
    else:
        print("\n  Krook 1 has %d completely empty screens: %s"
              % (len(empty), empty))

    # ----------------------------------------------- the dials that are still code
    print()
    for name, (pat, want) in sorted(CHANGES.items()):
        m = re.search(pat, src)
        if not m:
            bad.append("%s: pattern not found -- the dial has been rewritten, "
                       "so this check no longer covers it" % name)
            continue
        got = int(m.group(1))
        at = got if "krk < " in m.group(0) else got + 1
        if at != want:
            bad.append("%s changes at Krook %d, should be %d" % (name, at, want))
        else:
            print("  %-24s changes at Krook %d" % (name, at))

    # THE TIME BONUS, IN THE UNIT THE SCORE IS ACTUALLY KEPT IN.
    #
    # `#score` counts in UNITS OF TEN -- the prize is `#addv = 5` for fifty
    # points and the bonus Kop threshold is `#nextk = 1000` for ten thousand --
    # so a band written as 100 pays a THOUSAND a time unit. It was, and it did,
    # for as long as the tally had existed: reported from play as "it seems like
    # you awarded 1000 per time unit left". Nothing failed, the digits all lined
    # up, and the only symptom was a score that ran away.
    #
    # So the bands are checked in POINTS -- band x 10 -- which is the number the
    # manual quotes and the number a player counts. Writing the check in the
    # source's own unit would have agreed with the bug.
    want_points = [(0, 100), (10, 200), (16, 300)]
    m = re.search(r"#bval = (\d+)\s*\n\s*IF krk > (\d+) THEN #bval = (\d+)"
                  r"\s*\n\s*IF krk > (\d+) THEN #bval = (\d+)", src)
    if not m:
        bad.append("the time-bonus bands are not three `#bval` assignments any "
                   "more -- this check no longer covers the scoring unit")
    else:
        base, k2, b2, k3, b3 = (int(g_) for g_ in m.groups())
        got = [(0, base * 10), (k2 + 1, b2 * 10), (k3 + 1, b3 * 10)]
        if got != want_points:
            bad.append("time bonus pays %s per time unit from Krooks %s; the "
                       "original pays 100/200/300 from 1/10/16. `#addv` is in "
                       "UNITS OF TEN, so a band written in points pays ten "
                       "times over"
                       % ([p for _k, p in got], [kk for kk, _p in got]))
        else:
            print("  %-24s 100/200/300 points from Krook 1/10/16"
                  % "time bonus")

    # AND THE SOURCE MUST ACTUALLY BE READING THE TABLE. Everything above tests
    # the generator; if `load_band` stopped consulting `stor_lvl` the generated
    # bytes would be perfect and the game would ignore them.
    if "stor_lvl" not in src:
        bad.append("KEYSTONE.bas never mentions stor_lvl -- the level table is "
                   "generated and not read, so none of the above reaches play")

    if bad:
        print()
        for b in bad:
            print("FAIL  " + b)
        return 1
    print("\nOK: the level table matches the measured original.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
