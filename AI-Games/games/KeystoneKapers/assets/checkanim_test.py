#!/usr/bin/env python3
"""Prove checkanim.py can see the defect it exists for, and that the one cycle
it lets through is let through ON PURPOSE.

A CHECK WHOSE SCOPE IS NARROWER THAN THE BUG IS WORSE THAN NO CHECK, because it
reports success -- checklayout_test.py exists for the same reason, and its
subject passed the very defect it was built for on its first version.

There is a second failure mode here that is subtler and just as bad: a check
that was WEAKENED to accommodate art somebody chose to keep. The wrong response
to a cycle that is deliberately two pictures is to drop MINDIFF until it passes,
because that blinds the check for every other band at the same time. The right
one is a named exemption with a reason -- still measured, still printed. So this
test requires that the ONE remaining exemption (`dp`, the biplane: one airframe,
two propellers) names a band that really exists, and that none of Kelly's does.

And a third, which is the one that actually bit: a check that quietly measures
LESS than it used to. Rewriting Kelly's run from a two-bit ladder to a one-bit
assignment made his band invisible to the extractor, and `checkanim.py` went on
printing "animation OK" with one band fewer and no mention of the loss. The
bands are therefore asserted here BY NAME with the beat count each must have.

Run:  python3 checkanim_test.py
"""

import io
import sys

import checkanim as ca
import genart as g


def check(label, a, b, expect_below):
    d = ca.diff(a, b)
    ok = (d < ca.MINDIFF) == expect_below
    print("  %-46s %3d px  %s" % (label, d, "ok" if ok else "WRONG"))
    return ok


def main():
    print("checkanim_test -- MINDIFF = %d" % ca.MINDIFF)
    good = True

    # THE KOP RUNS TWO BEATS NOW, AND THEY ARE TWO DRAWINGS.
    #
    # He used to run four: A, B, mirror(A), mirror(B). Both drawings were
    # near-symmetric, so each mirrored to itself and the pairs measured 4 px
    # and 8 -- a two-frame cycle wearing four beats, carried here as a named
    # exemption because it was the animation the reviewer wanted.
    #
    # Both poses were then redrawn with asymmetric strides, which fixed the
    # repetition and broke something else: a mirrored stride reads as the
    # figure TURNING ROUND, so he appeared to face the wrong way on half his
    # beats. The mirrored beats are gone and the cycle is the two drawings it
    # always really was.
    #
    # So the pairing under test changes with it. The old assertion compared a
    # pose against its own mirror, which is a beat the game no longer plays;
    # this compares the two beats it DOES play, as whole merged bodies -- which
    # is also what is on screen, since the tunic and legs are one sprite.
    print("\nthe Kop's cycle: two beats, and they must be two pictures")
    good &= check("Kop beat1 vs beat2 (run1 vs run2)",
                  g.KELLY_RUN1, g.KELLY_RUN2, False)
    good &= check("Kop LEFT beat1 vs beat2 (mirrored pair)",
                  g.mirror(g.KELLY_RUN1), g.mirror(g.KELLY_RUN2), False)

    # NOTHING OF KELLY'S MAY BE EXEMPT. The whole point of the redraw was to
    # stop needing one, and an exemption outliving its defect would quietly
    # re-admit a repeated beat on the one band that is not allowed to fail.
    #
    # The check is on HIS bands rather than on the dict being empty, because
    # `dp` -- the biplane -- is legitimately one airframe with two propellers
    # and carries a named entry of its own. Asserting emptiness would have
    # forced that real exemption out, or forced this test to be deleted.
    kelly = sorted(v for v in ca.EXEMPT if v.startswith("k"))
    print("  %-46s %s"
          % ("no Kop band is exempt",
             "ok" if not kelly else "WRONG -- %s is exempt, so a return to a "
                                    "repeated beat would not fail the build"
                                    % ", ".join(kelly)))
    good &= not kelly
    # And every exemption must still name a band the source actually has, or it
    # is a silencer pointed at nothing -- which is how one survives the code it
    # was written about.
    bands, _c = ca.parse(io.open(ca.BAS, encoding="utf-8").read())
    stale = sorted(v for v in ca.EXEMPT if v not in bands)
    print("  %-46s %s"
          % ("every exemption names a real band",
             "ok" if not stale else "WRONG -- %s is exempt but no longer "
                                    "exists" % ", ".join(stale)))
    good &= not stale

    # AND THE PARSER MUST STILL FIND EVERY BAND. This is the regression that
    # actually happened: the run was rewritten from a two-bit ladder
    # (`kb = kb + 4` / `+ 8`) to a one-bit assignment (`kb = P_KRUN2`), the
    # extractor only knew the adding form, and Kelly's band vanished from the
    # check. The file went on printing "animation OK" with one band fewer and
    # nothing named the loss. Widening the window past the comment block then
    # turned up two MORE bands that had been invisible the same way.
    #
    # So the bands are asserted by name. A check that silently measures less
    # than it used to is the failure mode this whole file is about.
    print("\nthe parser must still find every animated band")
    for var, want in (("kb", 2), ("hp", 4), ("hq", 4), ("dp", 2)):
        n = len(ca.beats_of(bands[var])) if var in bands else 0
        print("  %-46s %s"
              % ("%s has %d beats" % (var, want),
                 "ok" if n == want else
                 "WRONG -- found %d, so this band is not being measured" % n))
        good &= n == want

    print("\nHarry's cycle: four drawn poses, must all be ACCEPTED")
    H = [g.HARRY_LEG1, g.HARRY_LEG2, g.HARRY_LEG3, g.HARRY_LEG4]
    HS = [g.HARRY_LEG1S, g.HARRY_LEG2S, g.HARRY_LEG3S, g.HARRY_LEG4S]
    B = [g.HARRY_BODY, g.HARRY_BODY2, g.HARRY_BODY3, g.HARRY_BODY4]
    BS = [g.HARRY_STRIPE, g.HARRY_STRIPE2, g.HARRY_STRIPE3, g.HARRY_STRIPE4]
    for i in range(4):
        for j in range(i + 1, 4):
            # THE WHOLE FIGURE, both halves. In the white half alone Harry's
            # beats 2 and 4 were once byte-identical while the black half they
            # are drawn with differed by 34 -- which is why checkanim adds the
            # derived bands back in rather than trusting the one it names.
            good &= check("Harry legs beat%d vs beat%d (white + stripes)"
                          % (i + 1, j + 1),
                          H[i] + HS[i], H[j] + HS[j], False)
    for i in range(4):
        for j in range(i + 1, 4):
            # Body PLUS stripes, for the same reason as the legs: the white
            # torso alone measures 9 px between beats 1 and 2 and 6 between 2
            # and 4, because most of a striped shirt lives in the black half.
            # Testing the half would have failed art that is correct.
            good &= check("Harry torso beat%d vs beat%d (white + stripes)"
                          % (i + 1, j + 1),
                          B[i] + BS[i], B[j] + BS[j], False)

    print()
    if not good:
        print("checkanim_test FAILED -- checkanim cannot see the defect it "
              "exists for, or rejects art that is currently shipped")
        return 1
    print("checkanim_test OK -- the Kop runs two distinct beats with nothing "
          "of his exempt; Harry's four drawn beats are accepted; every band "
          "is still found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
