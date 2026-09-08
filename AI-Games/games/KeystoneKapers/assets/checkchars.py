#!/usr/bin/env python3
"""Check every hand-written character and SPRITE number against genart.py.

The character table is GENERATED and automatically de-duplicated, so a code is
not a fact about the source -- it is a result. Adding one character, or merging
two that happen to be identical, renumbers everything after it. Any number
written down by hand then points somewhere else, silently:

  * `CONST CH_CASE = 113` shipped once. A renumbering had turned 113 into
    EXITC, so the second collectible drew an EXIT DOOR in the aisle. A
    plausible-looking box, no error, and nothing connecting it to a change made
    in a different file.
  * `CH_ECAR` and `CH_EDOOR` were BOTH one too high, because SHELFB merged into
    SHELFT and EDOOR merged into SHAFT. The elevator shaft drew the CAR pattern
    on every floor and the open car drew an escalator step. Again no error.

So none of these numbers may be trusted. `CONST CH_<NAME>` is checked against
`CODES["<NAME>"]`, and the `DEFINE CHAR`/`DEFINE COLOR` counts that load the
table are checked against its actual length -- a table that outgrows its load
is simply not loaded, and the extra characters draw as whatever was in VRAM.

SPRITE PATTERNS ARE THE SAME PROBLEM ONE LAYER DOWN. A sprite is four patterns
wide, so the n-th entry of genart's table is pattern 4n, and every one of those
numbers is also written by hand here as a `CONST P_...` and again as the base
of a `DEFINE SPRITE`. Adding one figure pose renumbers everything after it.
Adding the four-frame run cycle did exactly that and pushed the obstacles up by
two sprites: the constants still said the cart was pattern 96, which had become
Harry's third leg frame, and `DEFINE SPRITE 24,1,spr_cart` loaded the cart
straight over it. Harry would have run on a shopping trolley, and nothing in
the build would have said a word.

Run:  python3 checkchars.py        exits non-zero if a number is stale
"""

import os
import re
import sys

import genart as g

HERE = os.path.dirname(os.path.abspath(__file__))
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")

CONST_RE = re.compile(r"^\s*CONST CH_(\w+)\s*=\s*(\d+)")
LOAD_RE = re.compile(r"^\s*DEFINE (CHAR|COLOR) (\d+),(\d+),store_(pat|col)")
PCONST_RE = re.compile(r"^\s*CONST P_(\w+)\s*=\s*(\d+)")

# HARRY BORROWS BEAT 4 WHILE HE RIDES. The sprite table is full (63 of 64), so
# his standing pose has no slot: esc_stand copies it over these four and
# esc_run puts the run art back. The constants are therefore aliases for
# another sprite's pattern number, not names of their own.
SWAP_LABELS = set(l for l, _a, _c in g.SPRITES_SWAP)

BORROWED = {
    "HSTB": "HBODY",
    "HSTS": "HBODY2",
    "HSTL": "HBODY3",
    "HSTLS": "HBODY4",
}
DEFSPR_RE = re.compile(r"^\s*DEFINE SPRITE (\d+),(\d+),(\w+)")

# The two FACING constants are offsets, not patterns: adding one to a figure's
# RIGHT band gives its LEFT one, which only works while genart keeps the two
# blocks the same shape and the same distance apart.
FACING = {"KFACING": ("KHAT", "KLHAT"), "HFACING": ("HBODY", "HLBODY"),
          "HLEGFACING": ("HLEG1", "HLLEG1")}


def main():
    src = open(BAS, encoding="utf-8").read().split("\n")
    bad = []
    seen = 0
    loads = 0
    defspr = 0
    swapped = 0

    for n, ln in enumerate(src, 1):
        m = CONST_RE.match(ln)
        if m:
            name, code = m.group(1), int(m.group(2))
            seen += 1
            if name not in g.CODES:
                bad.append("line %d: CONST CH_%s has no character called %r in "
                           "genart.py -- either it was renamed there or the "
                           "constant is dead" % (n, name, name))
            elif g.CODES[name] != code:
                bad.append("line %d: CONST CH_%s = %d, but genart.py puts %s at "
                           "%d (%s is at %d)"
                           % (n, name, code, name, g.CODES[name],
                              dict((v, k) for k, v in g.CODES.items()).get(
                                  code, "nothing"), code))

        m = PCONST_RE.match(ln)
        if m:
            name, pat = m.group(1), int(m.group(2))
            seen += 1
            if name in BORROWED:
                # A BORROWED SLOT IS NOT A SPRITE NAME, it is the pattern
                # number of an existing one that gets overwritten at runtime.
                # Checking it against the sprite it borrows is stronger than
                # checking it against itself: this is exactly the number a
                # renumber would move out from under esc_stand, and the
                # symptom would be a standing pose appearing in the middle of
                # the run cycle rather than any kind of error.
                lend = BORROWED[name]
                if g.SPR[lend] != pat:
                    bad.append("line %d: CONST P_%s = %d, but %s -- the "
                               "sprite it borrows -- is at %d"
                               % (n, name, pat, lend, g.SPR[lend]))
            elif name in FACING:
                right, left = FACING[name]
                want = g.SPR[left] - g.SPR[right]
                if pat != want:
                    bad.append("line %d: CONST P_%s = %d, but genart puts %s "
                               "%d patterns after %s"
                               % (n, name, pat, left, want, right))
            elif name not in g.SPR:
                bad.append("line %d: CONST P_%s has no sprite called %r in "
                           "genart.py -- renamed there, or the constant is dead"
                           % (n, name, name))
            elif g.SPR[name] != pat:
                rev = dict((v, k) for k, v in g.SPR.items())
                bad.append("line %d: CONST P_%s = %d, but genart puts %s at %d "
                           "(%d is %s)"
                           % (n, name, pat, name, g.SPR[name], pat,
                              rev.get(pat, "nothing")))

        m = DEFSPR_RE.match(ln)
        if m:
            base, count, label = int(m.group(1)), int(m.group(2)), m.group(3)
            defspr += 1
            if label in SWAP_LABELS:
                swapped += 1
            if label in SWAP_LABELS:
                # LOADED AT RUNTIME, NOT AT STARTUP. These have no slot of
                # their own; the index they are written to is the borrowed one
                # and is checked through the P_HST* constants above.
                continue
            if label not in g.SPR_FIRST:
                bad.append("line %d: DEFINE SPRITE loads %r, which genart does "
                           "not emit" % (n, label))
                continue
            # DEFINE SPRITE indexes SPRITES, not patterns -- a sprite is four
            want_base = g.SPR_FIRST[label] // 4
            want_n = g.SPR_FIRST[label + "_n"]
            if base != want_base:
                bad.append("line %d: DEFINE SPRITE loads %s at sprite %d "
                           "(pattern %d); genart puts it at sprite %d "
                           "(pattern %d) -- it would land on top of %s"
                           % (n, label, base, base * 4, want_base,
                              want_base * 4,
                              dict((v, k) for k, v in g.SPR.items()).get(
                                  base * 4, "nothing")))
            if count != want_n:
                bad.append("line %d: DEFINE SPRITE loads %d sprites of %s, but "
                           "genart emits %d -- the rest would keep whatever was "
                           "in VRAM" % (n, count, label, want_n))

        m = LOAD_RE.match(ln)
        if m:
            loads += 1
            kind, base, count = m.group(1), int(m.group(2)), int(m.group(3))
            if base != 96:
                bad.append("line %d: DEFINE %s loads the store table from %d; "
                           "genart.py starts it at 96" % (n, kind, base))
            if count != len(g.CHARS):
                bad.append("line %d: DEFINE %s loads %d store characters, but "
                           "genart.py generates %d -- the last %d would never "
                           "be defined and would draw as whatever is in VRAM"
                           % (n, kind, count, len(g.CHARS),
                              len(g.CHARS) - count))

    if seen == 0:
        bad.append("found no `CONST CH_... = n` lines at all -- this check has "
                   "stopped applying, which is worse than it failing")
    if loads != 2:
        bad.append("expected 2 store-table loads (DEFINE CHAR + DEFINE COLOR), "
                   "found %d" % loads)
    # The startup loads must still cover every table in SPRITES exactly
    # once; the runtime swaps are counted separately and excluded above.
    defspr -= swapped
    if defspr != len([1 for _l, _a, _c in g.SPRITES]):
        bad.append("genart emits %d sprite tables but the source has %d "
                   "DEFINE SPRITE calls -- one is never loaded"
                   % (len(g.SPRITES), defspr))

    if bad:
        for b in bad:
            print("FAIL: " + b)
        return 1
    print("numbers OK -- %d CH_/P_ constants match genart's tables, both store "
          "loads cover all %d characters, and %d DEFINE SPRITE calls load every "
          "sprite where its constants say it is"
          % (seen, len(g.CHARS), defspr))
    return 0


if __name__ == "__main__":
    sys.exit(main())
