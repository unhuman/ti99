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

# AND A BORROWED SLOT MUST BE A SLOT SOMETHING ELSE REALLY OWNS.
#
# These were briefly made RESIDENT on the NES, at "a 32-code gap that nothing
# else uses" -- 176..207. That gap does not exist. 176..207 is HLLEG1..4 and
# HLLEGS1..4, Harry's own left-facing leg bands, and the setup upload wrote the
# standing pose over them: running left drew standing art in the leg slots, as a
# detached striped block below his feet on alternate frames.
#
# The check that was added with it made this WORSE, not better. It verified that
# `CONST P_HSTB` equalled the `nchr` of the upload beside `VARPTR spr_hstand(0)`
# -- two halves of the same mistake agreeing with each other. A constant is only
# checked when it is compared against something INDEPENDENT of it, which here is
# genart's own table. So `check_free` below asks the question that was never
# asked: is any pattern range written by a setup upload already owned by a
# resident sprite?
DEFSPR_RE = re.compile(r"^\s*DEFINE SPRITE (\d+),(\d+),(\w+)")

# AND THE TWO RAW OFFSETS INTO store_pat, which are bytes rather than codes.
#
# The NES re-sends CH_SKY2 and CH_BLDGL at setup with a colour table of their
# own, and reaches their art with `#nsrc = #nsrc + 456`. That 456 is
# (153 - 96) * 8 -- character number minus the table's base, times eight bytes a
# character -- and it CANNOT be written that way in the source: the product is
# over 255 and a folded constant expression truncates silently (CLAUDE.md 3A).
#
# So it is a bare literal, which is exactly the kind of number this file exists
# to distrust. A renumber that moves SKY2 leaves 456 pointing at some other
# character's art, and the symptom would be a wrong-looking patch of sky rather
# than anything that fails.
OFFSET_RE = re.compile(r"^\s*#nsrc = #nsrc \+ (\d+)\s*' char (\d+), CH_(\w+)")

# The two FACING constants are offsets, not patterns: adding one to a figure's
# RIGHT band gives its LEFT one, which only works while genart keeps the two
# blocks the same shape and the same distance apart.
FACING = {"KFACING": ("KHAT", "KLHAT"), "HFACING": ("HBODY", "HLBODY"),
          "HLEGFACING": ("HLEG1", "HLLEG1")}


# THE "IS THIS RANGE FREE?" QUESTION LIVES IN checkpat.py NOW.
#
# A narrower version of it sat here and was removed rather than kept beside the
# new one: checkpat models BOTH tables, every upload form and the declared
# borrows, and two hand-kept lists of the same thing go stale independently --
# which is how the check that was supposed to catch the 176 overwrite ended up
# agreeing with it.
def main():
    src = open(BAS, encoding="utf-8").read().split("\n")
    bad = []
    seen = 0
    loads = 0
    defspr = 0
    swapped = 0

    branch = []                 # '#if NES' nesting, so the two forms are told apart

    for n, ln in enumerate(src, 1):
        st = ln.strip()
        if st.startswith("#if "):
            branch.append("NES" if st[4:].strip() == "NES" else "OTHER")
        elif st.startswith("#else"):
            if branch:
                branch[-1] = {"NES": "NOT_NES",
                              "NOT_NES": "NES"}.get(branch[-1], "OTHER")
        elif st.startswith("#endif"):
            if branch:
                branch.pop()
        in_nes = bool(branch) and branch[-1] == "NES"

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

        m = OFFSET_RE.match(ln)
        if m:
            off, code, cname = int(m.group(1)), int(m.group(2)), m.group(3)
            seen += 1
            if cname not in g.CODES:
                bad.append("line %d: the store_pat offset names CH_%s, which "
                           "genart.py does not emit" % (n, cname))
            else:
                want_code = g.CODES[cname]
                want_off = (want_code - 96) * 8
                if code != want_code:
                    bad.append("line %d: the comment says char %d but genart "
                               "puts %s at %d" % (n, code, cname, want_code))
                if off != want_off:
                    bad.append("line %d: #nsrc + %d points at char %d, but %s "
                               "is char %d and wants + %d -- the sky override "
                               "would load some other character's art"
                               % (n, off, 96 + off // 8, cname, want_code,
                                  want_off))

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
