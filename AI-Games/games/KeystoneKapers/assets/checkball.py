#!/usr/bin/env python3
"""Prove no beach-ball height is unavoidable, from the SHIPPED bytes.

DESIGN.md 5a promises that at every height the ball reaches, at least one of
jumping and ducking works. That promise is the product of four numbers chosen
together -- jump apex, ducked height, the ball's hitbox inset, and the arc
apexes -- and any one of them can be edited on its own by someone who does not
know about the other three. A one-pixel hole would not crash, would not show up
in a screenshot, and would present in play as an occasional unfair hit, which
is indistinguishable from bad luck.

So it is checked mechanically, over EVERY frame of EVERY arc, against the
constants read out of the source rather than repeated here.

Run:  python3 checkball.py       exits non-zero if any height is unavoidable
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src")


def const(name):
    txt = open(os.path.join(SRC, "KEYSTONE.bas"), encoding="utf-8").read()
    m = re.search(r"^\s*CONST %s = (\d+)" % re.escape(name), txt, re.M)
    if not m:
        raise SystemExit("CONST %s not found" % name)
    return int(m.group(1))


def jump_apex():
    """The arc now lives in a generated table, not in the source.

    It moved there to save ROM, and this check has to follow it -- reading the
    old assignments would have found nothing and, had it defaulted instead of
    failing, would have silently stopped verifying the ball windows.
    """
    txt = open(os.path.join(SRC, "store.bas"), encoding="utf-8").read()
    m = re.search(r"^jarc_tbl:.*?$", txt, re.M)
    if not m:
        raise SystemExit("jarc_tbl not found in store.bas")
    vals = []
    for line in txt[m.end():].split(chr(10)):
        t = line.strip()
        if not t or t.startswith("'"):
            continue
        if not t.startswith("DATA BYTE"):
            break
        for tok in t[9:].split(","):
            tok = tok.strip()
            vals.append(int(tok[1:], 16) if tok.startswith("$") else int(tok))
    if not vals:
        raise SystemExit("jarc_tbl is empty")
    return max(vals), len(vals)


def arcs():
    txt = open(os.path.join(SRC, "store.bas"), encoding="utf-8").read()
    m = re.search(r"^stor_arc:.*?$", txt, re.M)
    if not m:
        raise SystemExit("stor_arc not found")
    out = []
    for line in txt[m.end():].split("\n"):
        s = line.strip()
        if not s or s.startswith("'"):
            continue
        if not s.startswith("DATA BYTE"):
            break
        out += [int(v) for v in s[9:].split(",")]
    if len(out) != 96:
        raise SystemExit("expected 3 x 32 arc entries, got %d" % len(out))
    return [out[0:32], out[32:64], out[64:96]]


def main():
    stand = const("STANDH")
    duck = const("DUCKH")
    apex, frames = jump_apex()

    # The ball's art is 8 px tall in rows 8-15 of its box; the hitbox is the
    # middle 4, i.e. [bb+2, bb+6) above the slab. This mirrors coll_obst.
    def hits(kfeet, kheight, bb):
        lo, hi = bb + 2, bb + 6
        return kfeet < hi and lo < kfeet + kheight

    bad = []
    print("jump apex %d px over %d frames; standing %d, ducked %d"
          % (apex, frames, stand, duck))
    for i, arc in enumerate(arcs()):
        peak = max(arc)
        for f, bb in enumerate(arc):
            jump_ok = not hits(apex, stand, bb)
            duck_ok = not hits(0, duck, bb)
            free = not hits(0, stand, bb)
            if free:
                bad.append("arc %d frame %d: ball at %d px clears a STANDING "
                           "Kelly -- it is FREE, and the hardest balls in the "
                           "game must not be the only ones you can walk under"
                           % (i, f, bb))
            if not jump_ok and not duck_ok:
                bad.append("arc %d frame %d: ball at %d px can be neither "
                           "jumped nor ducked -- DEAD BAND" % (i, f, bb))
        j = sum(1 for bb in arc if not hits(apex, stand, bb))
        d = sum(1 for bb in arc if not hits(0, duck, bb))
        print("  arc %d: apex %2d px -- jumpable on %2d/32 frames, "
              "duckable on %2d/32" % (i, peak, j, d))

    if bad:
        for b in sorted(set(bad)):
            print("FAIL: " + b)
        return 1
    print("ball arcs OK -- every frame of every arc is jumpable or duckable, "
          "and none is free")
    return 0


if __name__ == "__main__":
    sys.exit(main())
