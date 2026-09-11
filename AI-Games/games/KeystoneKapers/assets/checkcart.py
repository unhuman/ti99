#!/usr/bin/env python3
"""A cart's ART, its HITBOX and the JUMP ARC are three numbers that must agree.

They live in three different files, are maintained by three different hands,
and NOTHING relates them:

  genart.py       CART, drawn 12 px tall in rows 4-15 of a 16x16 box
  KEYSTONE.bas    coll_obst, `IF ck = OB_CART THEN oht = 12`
  store.bas       jarc_tbl, the jump arc -- 30 frames, apex 14

Change any one alone and the game is quietly wrong in a way no other check in
this directory can see:

  ART TALLER THAN HITBOX -- the player clips through the top of a trolley they
  can plainly see, which reads as the collision being broken rather than as an
  art edit that was never finished.

  HITBOX TALLER THAN ART -- they are hit by nothing, several pixels above a cart
  that visibly passed underneath them. This is the worse of the two, because it
  is invisible in every screenshot.

  EITHER ONE ABOVE THE APEX -- the cart becomes unjumpable, and since a cart is
  the hazard the game teaches you to jump, that deletes a mechanic rather than
  making it harder. The apex is 14 and is held for nine frames; the arc is what
  decides this, not the apex alone, so the WINDOW is measured rather than the
  peak compared.

WHY THIS FILE EXISTS AT ALL: checkball.py already sweeps a ball against the
jump and the crouch, and it is about BALLS -- its hitbox comes from the bounce
arc, not from the sprite. Nothing was watching the two obstacles whose height is
a constant. Raising the cart from 8 px to 12 px is exactly the edit this guards.

Run:  python3 checkcart.py
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import genart                                            # noqa: E402

BAS = os.path.join(HERE, os.pardir, "src", "KEYSTONE.bas")
STORE = os.path.join(HERE, os.pardir, "src", "store.bas")

# A window narrower than this is a precision stunt rather than a jump. The 8 px
# cart cleared on 22 of 30 frames; at 12 px it is 16. Ten is the point below
# which the timing stops being something a player can feel out.
MIN_WINDOW = 10

# PIXELS THAT LOOK LIKE A HIT AND ARE NOT. Kelly is 16 px, so a hazard of width
# w visually overlaps him once the centres are within 8 + w/2, while the hit
# only fires inside CATCHR. Three is what the ball has shipped with since it was
# drawn 14 px wide, and it is the most anything here has ever had -- so it is
# the bound, written down once as a number rather than inferred from whichever
# hazard happens to be widest today.
MAX_SLACK = 3


def art_rows(block):
    """(first drawn row, last drawn row) of a 16-row art block."""
    rows = [r for r in block.strip("\n").split("\n") if r]
    if len(rows) != 16:
        sys.exit("checkcart: CART is %d rows, expected 16" % len(rows))
    drawn = [i for i, r in enumerate(rows) if set(r) != {"."}]
    return drawn[0], drawn[-1]


def art_width(block):
    """How many columns the drawing actually spans."""
    rows = [r for r in block.strip("\n").split("\n") if r]
    cols = [i for r in rows for i, ch in enumerate(r) if ch != "."]
    return max(cols) - min(cols) + 1


def main():
    bad = []
    src = io.open(BAS, encoding="utf-8").read()
    store = io.open(STORE, encoding="utf-8").read()

    top, bottom = art_rows(genart.CART)
    art_h = bottom - top + 1

    # RULE 2 OF genart.py: every obstacle's bottom edge is `y + 16`, so the art
    # must reach row 15. A cart drawn 12 px tall in rows 2-13 is the same 12 px
    # and floats two pixels off the floor, on every screen, for ever.
    if bottom != 15:
        bad.append("CART's lowest drawn row is %d, not 15 -- it would float "
                   "%d px above the slab (genart.py rule 2)"
                   % (bottom, 15 - bottom))

    m = re.search(r"IF ck = OB_CART THEN oht = (\d+)", src)
    if not m:
        bad.append("no `IF ck = OB_CART THEN oht = N` in coll_obst -- a cart is "
                   "taking the default hitbox, which is the RADIO's 8 px")
        oht = None
    else:
        oht = int(m.group(1))
        if oht != art_h:
            bad.append("CART art is %d px tall but its hitbox oht is %d -- "
                       "%s" % (art_h, oht,
                               "the player clips through the top"
                               if art_h > oht else
                               "the player is hit above the cart"))

    # WIDTH IS BOUNDED BY A SHARED CONSTANT, NOT BY THE 16 PX BOX. The hit test
    # is `cdx < CATCHR` on CENTRES and is taken BEFORE any per-kind branch, so a
    # cart cannot be given a wider radius of its own -- and CATCHR is also what
    # decides when Kelly catches Harry (`hdd < CATCHR THEN caught = 1`), so
    # raising it would change the arrest, which is a different mechanic
    # entirely.
    #
    # Kelly is 16 px, so a hazard of width w overlaps him once the centres are
    # within 8 + w/2, while the hit only fires inside CATCHR. The difference is
    # pixels that LOOK like a hit and are not. The ball ships at 14 px, so that
    # is the most forgiveness anything in this game has ever had; a cart wider
    # than the ball would be worse than shipped art, which is the line.
    cw, bw = art_width(genart.CART), art_width(genart.BALL)
    cm = re.search(r"CONST CATCHR = (\d+)", src)
    if not cm:
        bad.append("no `CONST CATCHR` in KEYSTONE.bas, so cart width cannot be "
                   "checked against the hit radius")
    else:
        catchr = int(cm.group(1))
        slack = (8 + cw // 2) - catchr
        print("  cart width      %d px (ball %d), CATCHR %d -> %d px overlap "
              "before a hit" % (cw, bw, catchr, slack))
        # MEASURED AGAINST AN ABSOLUTE, NOT AGAINST THE BALL. The first version
        # of this asserted `cart <= ball`, which is a RATIO TEST: widen both and
        # it passes while the game gets worse. A mutation that caught the ball
        # as well as the cart sailed straight through it, reporting 16 px
        # against 16. A checker needs at least one anchor that does not move.
        if slack > MAX_SLACK:
            bad.append("a %d px cart leaves %d px of overlap before the hit "
                       "fires (CATCHR is %d and shared with the arrest, so it "
                       "cannot widen to match); %d is the most any shipped "
                       "hazard has" % (cw, slack, catchr, MAX_SLACK))
        if bw > cw and (8 + bw // 2) - catchr > MAX_SLACK:
            bad.append("the BALL is %d px wide and now exceeds the same bound "
                       "-- MAX_SLACK describes the whole game, not just carts"
                       % bw)

    am = re.search(r"jarc_tbl:[^\n]*\n((?:\s*DATA BYTE[^\n]*\n)+)", store)
    if not am:
        bad.append("cannot find jarc_tbl in store.bas, so cart clearance "
                   "cannot be checked")
    elif oht is not None:
        arc = []
        for line in am.group(1).splitlines():
            arc += [int(x) for x in re.findall(r"\d+", line.split("BYTE")[-1])]
        apex = max(arc)
        window = sum(1 for h in arc if h >= oht)
        print("  cart art        %d px, rows %d-%d" % (art_h, top, bottom))
        print("  cart hitbox     oht = %d" % oht)
        print("  jump arc        %d frames, apex %d" % (len(arc), apex))
        print("  clears on       %d of %d frames" % (window, len(arc)))
        if oht > apex:
            bad.append("a %d px cart cannot be jumped at all: the arc's apex "
                       "is %d" % (oht, apex))
        elif oht == apex:
            bad.append("a %d px cart is cleared only AT the apex (%d) -- no "
                       "margin, so a single lost frame is a hit" % (oht, apex))
        elif window < MIN_WINDOW:
            bad.append("a %d px cart clears on only %d of %d frames; below %d "
                       "that is a precision stunt, not a jump"
                       % (oht, window, len(arc), MIN_WINDOW))

    if bad:
        print()
        for b in bad:
            print("FAIL  " + b)
        return 1
    print("\nOK: the cart's art, its hitbox and the jump arc agree.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
