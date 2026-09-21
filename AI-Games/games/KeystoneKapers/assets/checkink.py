#!/usr/bin/env python3
"""Which store characters COLLAPSE TO ONE COLOUR under the NES ink map?

A TMS cell carries an ink and a paper per scan line. The NES shim (nes_chr.asm)
maps both through `nes_inkmap` onto one of four palette indices -- and when both
land on the SAME index the cell is a solid block of that colour with the
artwork gone. `nes_chrinks` scans all eight lines for a non-degenerate one
first, so a character only fails when EVERY line collapses.

That failure is silent and it does not look like a colour bug: it looks like a
solid block of scenery in the middle of the shop, which reads as a drawing
fault or a stale character number. A white block on the floor past the
escalator tops was reported from play as exactly that.

It also guards a change to the ink map itself. Moving a colour to a different
index is a two-sided edit -- it separates one pair and can merge another -- and
nothing else in the build would notice the second half.

Run:  python3 checkink.py        exits non-zero if any character collapses
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "src", "art.bas")
CHR_ASM = os.path.join(HERE, "nes_chr.asm")
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")

NAMES = ["TRANSP", "BLACK", "MGREEN", "LGREEN", "DBLUE", "LBLUE", "DRED", "CYAN",
         "MRED", "LRED", "DYELL", "LYELL", "DGREEN", "MAGENTA", "GRAY", "WHITE"]
ROLE = ["backdrop", "base", "struct", "light"]

# The store characters start at this code -- KEYSTONE.bas: DEFINE CHAR 96,89.
STORE_FIRST = 96

# CHARACTERS THAT ARE SOLID ON PURPOSE, each named with its reason.
#
# These are still MEASURED and still printed on every run; only the failure is
# suppressed. Relaxing the rule instead -- "allow three collapses" -- would
# blind the check for every other character at the same moment, which is how a
# gate quietly stops being one (CLAUDE.md 3A).
EXEMPT = {
    100: "CH_SHELFB: legacy solid fill; NES replaces it with native shelf art",
    107: "CH_COUNTR, the pillar/counter column: one flat grey by design",
    179: "CH_SCANBK, the black strip either side of the radar",
}


def ink_only():
    """Characters re-uploaded with `#ncol = 0`, which never see a colour table.

    A second upload with no colour table takes a character OUT of the TMS map
    entirely: its ink comes from `nink` and its paper is the backdrop. Asking
    whether such a character's two table colours collapse is meaningless -- the
    table is not consulted for it -- so the question is skipped rather than
    answered wrongly.

    THIS IS READ OUT OF THE SOURCE, NOT LISTED HERE. A hand-kept copy of which
    characters bypass the table is a second copy of a decision the game already
    makes, and CLAUDE.md has the scar to prove those go stale in silence. The
    set is small today and will not stay that way.
    """
    src = open(BAS, encoding="utf-8", errors="replace").read()
    consts = {m.group(1): int(m.group(2)) for m in
              re.finditer(r"^\s*CONST (CH_\w+)\s*=\s*(\d+)", src, re.M)}
    lines = src.split("\n")
    out = {}
    for i, line in enumerate(lines):
        if line.strip() != "#ncol = 0":
            continue
        # the matching `nchr = ...` sits a few lines above, in the same block
        for j in range(i - 1, max(-1, i - 8), -1):
            m = re.match(r"^\s*nchr = (\w+)\s*$", lines[j])
            if not m:
                continue
            tok = m.group(1)
            code = consts.get(tok, int(tok) if tok.isdigit() else None)
            if code is not None:
                out[code] = tok
            break
    return out


def read_inkmap():
    """The live table out of nes_chr.asm, so this cannot drift from the game."""
    src = open(CHR_ASM, encoding="utf-8").read()
    # The FIRST `DB` after the label, skipping any comment lines in between --
    # a checker that cannot survive a comment being added above its data is one
    # that gets deleted the first time it cries wolf.
    i = src.index("nes_inkmap:")
    m = re.search(r"^\s*DB\s+([0-9,\s]+?)\s*$", src[i:], re.M)
    if not m:
        raise SystemExit("found nes_inkmap but no DB line after it")
    vals = [int(v) for v in m.group(1).split(",")]
    if len(vals) != 16:
        raise SystemExit("nes_inkmap has %d entries, expected 16" % len(vals))
    return vals


def read_store_col():
    """store_col as a list of 8-byte groups, one per character."""
    src = open(ART, encoding="utf-8").read()
    i = src.index("store_col:")
    tail = src[i:]
    # stop at the next label at column 0
    m = re.search(r"\n[A-Za-z_][A-Za-z0-9_]*:", tail[10:])
    if m:
        tail = tail[:10 + m.start()]
    out = []
    for line in tail.split("\n"):
        line = line.split("'")[0]
        m2 = re.match(r"\s*DATA BYTE\s+(.*)$", line)
        if not m2:
            continue
        for tok in m2.group(1).split(","):
            tok = tok.strip()
            if not tok:
                continue
            out.append(int(tok[1:], 16) if tok.startswith("$") else int(tok))
    if len(out) % 8:
        raise SystemExit("store_col is %d bytes, not a multiple of 8" % len(out))
    return [out[i:i + 8] for i in range(0, len(out), 8)]


def main():
    inkmap = read_inkmap()
    chars = read_store_col()
    print("ink map : " + ", ".join(
        "%s->%d(%s)" % (NAMES[c], inkmap[c], ROLE[inkmap[c]]) for c in range(16)))
    print("checking %d store characters (codes %d-%d)\n"
          % (len(chars), STORE_FIRST, STORE_FIRST + len(chars) - 1))

    bad = []
    for n, rows in enumerate(chars):
        code = STORE_FIRST + n
        # nes_chrinks: the first line whose two indices DIFFER wins.
        usable = None
        for y, b in enumerate(rows):
            ink, paper = inkmap[b >> 4], inkmap[b & 15]
            if ink != paper:
                usable = y
                break
        if usable is None:
            b = rows[0]
            ink, paper = b >> 4, b & 15
            bad.append((code, NAMES[ink], NAMES[paper], inkmap[ink]))

    solo = ink_only()
    if solo:
        print("re-uploaded with no colour table, so the table cannot decide "
              "them: %s" % ", ".join("%d (%s)" % (c, n)
                                     for c, n in sorted(solo.items())))
        print()

    if bad:
        print("characters that collapse to one index:")
        for code, ink, paper, idx in bad:
            why = EXEMPT.get(code)
            if code in solo:
                why = "sent with its own ink (%s) -- no colour table" % solo[code]
            print("  char %3d  %-7s on %-7s -> both index %d (%s)%s"
                  % (code, ink, paper, idx, ROLE[idx],
                     "   EXEMPT: " + why if why else "   *** SOLID BLOCK ***"))
        print()

    unexpected = [b for b in bad if b[0] not in EXEMPT and b[0] not in solo]
    if unexpected:
        print("%d character(s) will render as a featureless block, and none of "
              "them is meant to." % len(unexpected))
        print("Separate the two colours in nes_inkmap -- see the pairs note "
              "beside the table in nes_chr.asm.")
        return 1

    stale = sorted(set(EXEMPT) - {b[0] for b in bad})
    if stale:
        print("exempt but no longer collapsing: %s" % stale)
        print("Drop them from EXEMPT -- an exemption nobody needs hides the "
              "next character that takes that code.")
        return 1

    print("OK -- %d collapse, all %d of them named and intentional"
          % (len(bad), len(EXEMPT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
