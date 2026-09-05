#!/usr/bin/env python3
"""Rewrite KEYSTONE.bas's character/sprite constants from genart's own tables.

EVERY `CONST CH_*` AND `CONST P_*` IS A NUMBER THAT GENART DECIDES. Adding one
character in the middle of CHARS_BASE renumbers everything after it, and giving
two identical cells different colours un-merges them and does the same -- so a
colour change can silently move twenty character codes. checkchars.py catches
the mismatch, but catching it leaves the numbers to be fixed by hand.

This fixes them: for each `CONST CH_NAME = n` it looks NAME up in genart.CODES,
and for each `CONST P_NAME = n` in genart.SPR, and rewrites n. It also updates
the escalator's `DEFINE CHAR <first>,<count>` lines, whose first code is
ESC_FIRST and whose counts are ESC_ANIM_W / ESC_ANIM_E, and the store's
`DEFINE CHAR 96,<n>` / `DEFINE COLOR 96,<n>` counts.

Names it cannot resolve are REPORTED, not skipped silently -- an unresolvable
CH_* means the character was renamed or deleted and the source still refers to
it, which is exactly the case where guessing would be worst.

Run:  python3 renumber.py        (rewrites ../src/KEYSTONE.bas in place)
"""

import io
import os
import re
import sys

import genart as g

HERE = os.path.dirname(os.path.abspath(__file__))
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")

# CH_* names that are not characters in their own right
SKIP = set()


def main():
    src = io.open(BAS, encoding="utf-8").read()
    changed, bad = [], []

    def fix_const(m):
        kind, name, old = m.group(1), m.group(2), int(m.group(3))
        table = g.CODES if kind == "CH" else g.SPR
        if name not in table:
            bad.append("CONST %s_%s has no %s in genart" % (kind, name, name))
            return m.group(0)
        new = table[name]
        if new != old:
            changed.append("%s_%s %d -> %d" % (kind, name, old, new))
        return "CONST %s_%s = %d" % (kind, name, new)

    # P_KFACING / P_HFACING are OFFSETS between the two facings, not codes.
    src = re.sub(r"CONST (CH|P)_(?!KFACING|HFACING)(\w+) = (\d+)", fix_const, src)

    # the escalator's animated block: first code and the two counts
    def fix_esc(m):
        first, cnt, lbl = int(m.group(1)), int(m.group(2)), m.group(3)
        want_first = g.ESC_FIRST if lbl.startswith("esc_phw") else \
            g.ESC_FIRST + g.ESC_ANIM_W
        want_cnt = g.ESC_ANIM_W if lbl.startswith("esc_phw") else g.ESC_ANIM_E
        if (first, cnt) != (want_first, want_cnt):
            changed.append("DEFINE CHAR %d,%d,%s -> %d,%d"
                           % (first, cnt, lbl, want_first, want_cnt))
        return "DEFINE CHAR %d,%d,%s" % (want_first, want_cnt, lbl)

    src = re.sub(r"DEFINE CHAR (\d+),(\d+),(esc_ph\w+)", fix_esc, src)

    # DEFINE SPRITE <index>,<count>,<label>. The index is a SPRITE number and a
    # sprite is four patterns, so it is genart's pattern number over four --
    # and giving one actor an extra frame shifts every actor after it. That is
    # how the cart landed on top of Harry's legs.
    def fix_sprite(m):
        idx, cnt, lbl = int(m.group(1)), int(m.group(2)), m.group(3)
        for label, arts, _c in g.SPRITES:
            if label == lbl:
                first = g.SPR[arts[0][0]] // 4
                n = len(arts)
                if (idx, cnt) != (first, n):
                    changed.append("DEFINE SPRITE %d,%d,%s -> %d,%d"
                                   % (idx, cnt, lbl, first, n))
                return "DEFINE SPRITE %d,%d,%s" % (first, n, lbl)
        bad.append("DEFINE SPRITE names %s, which genart does not define" % lbl)
        return m.group(0)

    src = re.sub(r"DEFINE SPRITE (\d+),(\d+),(spr_\w+)", fix_sprite, src)

    # the store block's own size
    n = len(g.CHARS)
    def fix_store(m):
        if int(m.group(2)) != n:
            changed.append("DEFINE %s 96,%s -> %d" % (m.group(1), m.group(2), n))
        return "DEFINE %s 96,%d,store_%s" % (m.group(1), n,
                                             "pat" if m.group(1) == "CHAR" else "col")

    src = re.sub(r"DEFINE (CHAR|COLOR) 96,(\d+),store_(?:pat|col)", fix_store, src)

    if bad:
        for b in bad:
            print("FAIL  " + b)
        return 1
    io.open(BAS, "w", encoding="utf-8", newline="").write(src)
    if changed:
        print("renumbered %d:" % len(changed))
        for c in changed:
            print("   " + c)
    else:
        print("nothing to renumber")
    return 0


if __name__ == "__main__":
    sys.exit(main())
