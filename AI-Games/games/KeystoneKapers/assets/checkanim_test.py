#!/usr/bin/env python3
"""Prove checkanim.py can see the defect it exists for, and that the one cycle
it lets through is let through ON PURPOSE.

A CHECK WHOSE SCOPE IS NARROWER THAN THE BUG IS WORSE THAN NO CHECK, because it
reports success -- checklayout_test.py exists for the same reason, and its
subject passed the very defect it was built for on its first version.

There is a second failure mode here that is subtler and just as bad: a check
that was WEAKENED to accommodate art somebody chose to keep. The Kop's legs are
two near-symmetric drawings mirrored, so his four beats really are two pictures
-- and that is the animation the reviewer asked for. The wrong response is to
drop MINDIFF until he passes, because that blinds the check for every other
band at the same time. The right one is a named exemption with a reason, which
is what this test enforces: the measurement must still SEE 4 px, and `kq` must
still be listed with a reason for why that is acceptable.

Run:  python3 checkanim_test.py
"""

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

    # The Kop plays A, B, mirror(A), mirror(B). The measurement must still call
    # these repeats; only the EXEMPT entry stops them failing the build.
    print("\nthe Kop's cycle: must still MEASURE as repeated beats")
    K = [g.KELLY_LEG1, g.KELLY_LEG2,
         g.mirror(g.KELLY_LEG1), g.mirror(g.KELLY_LEG2)]
    good &= check("Kop beat1 vs beat3 (A vs mirror A)", K[0], K[2], True)
    good &= check("Kop beat2 vs beat4 (B vs mirror B)", K[1], K[3], True)

    print("\n  ...and must be exempted by name, with a reason")
    reason = ca.EXEMPT.get("kq", "")
    ok = len(reason) > 40
    print("  %-46s %s" % ("kq listed in checkanim.EXEMPT",
                          "ok" if ok else "WRONG -- MINDIFF was probably "
                                          "lowered instead"))
    good &= ok

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
    print("checkanim_test OK -- measures the Kop's repeats and exempts them by "
          "name; accepts Harry's four drawn beats")
    return 0


if __name__ == "__main__":
    sys.exit(main())
