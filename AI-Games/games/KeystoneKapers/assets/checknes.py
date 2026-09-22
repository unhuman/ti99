#!/usr/bin/env python3
"""Every raw name-table address must be gated for the NES, and gated CORRECTLY.

A VPOKE takes a RAW VRAM address. On the TI the name table is at 6144; on the
NES it is at 8192, and this port drops the picture three rows to clear overscan,
so the same cell is 96 bytes further on again. The NES form of any raw address
is therefore exactly

    TI address + 2144          (8192 + 96 - 6144)

An UNGATED constant does not merely draw in the wrong place on the NES -- 6144
and everything near it is BELOW $2000, which is the PATTERN table. The HUD's
score and timer shipped like this: the digits never appeared, and every update
wrote them over the artwork of a store character, which read as random colour
corruption somewhere else entirely.

That is a bug no layout checker can see, because the layout is right and the
base is wrong. So this reads the constants out of the source and checks both
halves: that a raw address is gated at all, and that the NES half is the TI half
plus the offset -- a hand-typed second constant is exactly the kind of thing
that goes stale (CLAUDE.md: a second copy of a decision silently drifts).

Run:  python3 checknes.py
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# argv[1] lets the mutation test point this at a deliberately broken copy. A
# gate that has only ever been run against good input is not known to be a gate.
BAS = (sys.argv[1] if len(sys.argv) > 1
       else os.path.join(HERE, "..", "src", "KEYSTONE.bas"))

TI_BASE = 6144
TI_END = TI_BASE + 768                  # the TI name table, 24 rows of 32
NES_DELTA = 2144                        # 8192 + 96 - 6144

# THE HUD SITS ONE ROW HIGHER THAN THE PICTURE, AND THAT IS DELIBERATE.
#
# The store is dropped three rows (+96) so its top row clears the NES's
# overscan. The HUD does not need all three: it is one row of text with nothing
# above it, row 2 is comfortably inside the visible area on this machine, and
# giving the score line its own row back buys a row of picture. So these
# variables -- and ONLY these -- are gated at +2112 instead.
#
# This is an exemption by NAME with a reason, not a relaxed rule. Every other
# raw address is still held to exactly +2144, the exempt ones are still
# MEASURED against their own delta rather than skipped, and both numbers are
# printed on every build so a wrong one is visible rather than tolerated.
HUD_DELTA = 2112                        # 8192 + 64 - 6144
HUD_VARS = {"#psa", "#pla"}             # hud_score, hud_time, hud_kops

# AND THE SCANNER SITS ONE ROW LOWER, FOR THE OPPOSITE REASON.
#
# The NES name table is THIRTY rows where the TI's is twenty-four. On the TI the
# scanner is already on the last three rows and cannot move; here there are
# three rows below it, which are blank cells -- and a blank cell is all paper,
# so once the font gained a paper they came out as the store's green under the
# instrument. They are filled with CH_SCANBK to carry the grey to the bottom
# edge, and the instrument then moves down one row to sit in the middle of that
# strip rather than at the top of it.
#
# Same rule as the HUD's exemption: by NAME, with a reason, still measured
# against its own delta rather than skipped, and printed on every build.
SCAN_DELTA = 2176                       # 8192 + 128 - 6144, one row below the picture
SCAN_VARS = {"#sva"}                    # scan_canvas


# AND ONE VARIABLE IS USED AT TWO DIFFERENT OFFSETS, WHICH A PER-NAME RULE
# CANNOT EXPRESS.
#
# #psa is the digit printer's address, and the digit printer is shared: the
# in-game HUD hands it a row at +2112, and the TITLE card hands it a row at
# +2144. The title's card is drawn by run_list, whose NES base is 8288 -- the
# picture offset -- because that same walker draws the message boxes over the
# store and they have to line up with it. So the title's score line sits three
# rows down like the picture, and its digits have to sit with their labels.
#
# Gated on the ROUTINE as well as the name, because that is the thing that
# actually decides: the offset belongs to the screen being drawn. A rule keyed
# on the variable alone reported the title's two addresses as "off by 32",
# which is a defect that is not there -- the mirror of a check whose scope is
# too narrow, and it costs the same trust (CLAUDE.md 3A).
PICTURE_PAIRS = {("title_score", "#psa")}   # the title card, via run_list's base


def expected(var, label=None):
    if (label, var) in PICTURE_PAIRS:
        return NES_DELTA
    if var in HUD_VARS:
        return HUD_DELTA
    if var in SCAN_VARS:
        return SCAN_DELTA
    return NES_DELTA

ASSIGN = re.compile(r"^\s*(#?\w+)\s*=\s*(\d+)\s*(?:'.*)?$")
LABEL = re.compile(r"^([a-z_][a-z0-9_]*):")


def scan():
    """Walk the file tracking #if NES / #else / #endif state and the routine."""
    out = []
    state = []                          # stack of 'NES' | 'NOT_NES' | 'OTHER'
    label = "(top)"
    for n, raw in enumerate(open(BAS, encoding="utf-8", errors="replace"), 1):
        line = raw.rstrip("\n")
        s = line.strip()
        m = LABEL.match(line)
        if m:
            label = m.group(1)
        if s.startswith("#if "):
            state.append("NES" if s[4:].strip() == "NES" else "OTHER")
            continue
        if s.startswith("#else"):
            if state:
                top = state[-1]
                state[-1] = {"NES": "NOT_NES", "NOT_NES": "NES"}.get(top, "OTHER")
            continue
        if s.startswith("#endif"):
            if state:
                state.pop()
            continue
        m = ASSIGN.match(line)
        if not m:
            continue
        val = int(m.group(2))
        here = state[-1] if state else "PLAIN"
        out.append((n, m.group(1), val, here, label))
    return out


def main():
    rows = scan()
    bad = []

    # The controller menu is a separate implementation, not interleaved
    # per-address branches. Check its complete address sequence explicitly:
    # row 5/7, column 16, with the NES picture shifted down three rows.
    menu = [(val, st) for _, var, val, st, lbl in rows
            if lbl == 'setup838' and var == '#sua']
    menu_expected = [(8192+(5+3)*32+16, 'NES'),
                     (8192+(7+3)*32+16, 'NES'),
                     (6144+5*32+16, 'NOT_NES'),
                     (6144+7*32+16, 'NOT_NES'),
                     (6144+7*32+16, 'NOT_NES')]
    if menu != menu_expected:
        bad.append('setup838 digit addresses/platform guards differ from '
                   'rows 5/7, column 16 (+3 rows on NES): %r' % (menu,))

    # 1. every TI-range raw address must sit in a NON-NES branch
    ti_hits = [r for r in rows if TI_BASE <= r[2] < TI_END]
    ungated = [r for r in ti_hits if r[3] in ("PLAIN", "NES")]
    for n, var, val, st, lbl in ungated:
        where = ("no #if at all" if st == "PLAIN"
                 else "inside the #if NES branch, which is backwards")
        bad.append("KEYSTONE.bas:%d  %s = %d is a raw TI name-table address "
                   "with %s. On the NES that is $%04X, inside the PATTERN "
                   "table -- it will corrupt character art. Gate it and use "
                   "%d." % (n, var, val, where, val, val + expected(var, lbl)))

    # 2. each gated pair must differ by exactly the offset that routine uses.
    #    Pair them by the variable name, taking the NES assignment nearest
    #    above the TI one.
    for i, (n, var, val, st, lbl) in enumerate(rows):
        if st != "NOT_NES" or not (TI_BASE <= val < TI_END):
            continue
        if lbl == 'setup838' and var == '#sua':
            continue  # fully checked above, including all NES assignments
        mate = None
        for j in range(i - 1, max(-1, i - 8), -1):
            n2, var2, val2, st2, _l2 = rows[j]
            if var2 == var and st2 == "NES":
                mate = (n2, val2)
                break
        if mate is None:
            bad.append("KEYSTONE.bas:%d  %s = %d is in a #else but no matching "
                       "`%s = <addr>` was found in the #if NES branch above it"
                       % (n, var, val, var))
            continue
        n2, val2 = mate
        want = expected(var, lbl)
        if val2 != val + want:
            bad.append("KEYSTONE.bas:%d  %s = %d (NES) should be %d -- the TI "
                       "form at line %d is %d and %s writes at +%d. Off by %d."
                       % (n2, var, val2, val + want, n, val, lbl, want,
                          val2 - (val + want)))

    if bad:
        for b in bad:
            print("FAIL " + b)
        return 1
    gated = [r for r in ti_hits if r[3] == "NOT_NES"]
    card = [r for r in gated if (r[4], r[1]) in PICTURE_PAIRS]
    hud = [r for r in gated if r[1] in HUD_VARS and r not in card]
    # NOT `scan`: that is this module's own parsing function, and shadowing
    # it breaks the call above with an UnboundLocalError.
    scanner = [r for r in gated if r[1] in SCAN_VARS]
    # EVERY NUMBER GETS PRINTED, INCLUDING THE EXEMPT ONES. An exemption that
    # goes quiet is how a gate stops being a gate: if the HUD or the scanner
    # ever drifts off its own row the count moves here, in plain sight, on
    # every build.
    print("checknes: %d raw name-table addresses, all gated for NES -- "
          "%d at +%d (the picture, %d of them the title card's score line), "
          "%d at +%d (the HUD, one row higher), "
          "%d at +%d (the scanner, one row lower)"
          % (len(gated), len(gated) - len(hud) - len(scanner), NES_DELTA,
             len(card), len(hud), HUD_DELTA, len(scanner), SCAN_DELTA))
    return 0


if __name__ == "__main__":
    sys.exit(main())
