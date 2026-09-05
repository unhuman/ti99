#!/usr/bin/env python3
"""Check every PRINT AT and HUD VPOKE in KEYSTONE.bas against the 32x24 screen.

Two failures this catches, both of which look like anything but a layout bug
when you meet them in an emulator:

  * A string that runs past column 31 WRAPS onto the next row and overwrites
    whatever was there, so the damage shows up on a line you were not editing.
  * A VPOKE that drops a digit into a cell some PRINT AT already owns. UFO's
    838 screen did exactly this -- the difficulty digit landed in the middle
    of the word DIFFICULTY, so it read as a typo in the label rather than as
    a misplaced value.

Neither is visible in the source: both are arithmetic on a bare offset.

TWO THINGS THIS VERSION DOES THAT UFO'S DID NOT, both because this source is
shaped differently and a check that quietly stops applying is worse than no
check at all:

  1. IT TRACKS WHEN AN ADDRESS STOPS BEING KNOWN. This game builds name-table
     addresses in steps -- `#pva = 6144` then `#pva = #pva + #bdst(lv)` -- and
     it does that deliberately, because CVBasic silently truncates a folded
     constant expression. UFO's checker would have taken the 6144 at face
     value and reported the scanner writing to row 0 column 0, on top of the
     score. A confident wrong answer from a checker is the worst outcome
     available, so any assignment that is not a bare literal marks the
     variable UNRESOLVABLE and its writes are reported as unchecked rather
     than checked against a stale number.
  2. IT REFUSES TO PASS ON AN UNMAPPED ROUTINE. Rows only mean the same thing
     within one SCREEN, and screen boundaries are not derivable from the
     source -- they have to be declared. UFO's first checker grouped by LABEL
     and so compared the 838 screen's digits against nothing, passing the very
     bug it existed to catch.

Run:  python3 checklayout.py        exits non-zero if anything is wrong
"""

import os
import re
import sys

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "src", "KEYSTONE.bas")
NAME_TABLE = 6144

PRINT_RE = re.compile(r'^\s*PRINT AT (\d+),"([^"]*)"')
LABEL_RE = re.compile(r"^([a-z_][a-z0-9_]*):")
# `#var = <bare literal>` -- the only form we can resolve
SETLIT_RE = re.compile(r"^\s*#(\w+)\s*=\s*(\d+)\s*(?:'.*)?$")
# any other assignment to a #var, which makes it unresolvable from here on
SETANY_RE = re.compile(r"^\s*#(\w+)\s*=")
VPOKE_RE = re.compile(r"^\s*VPOKE #(\w+),")

# WHICH SCREEN EACH ROUTINE PAINTS. This has to be written down; nothing in
# the source says it, and a row only means something within one screen.
SCREEN = {
    "title_screen": "TITLE", "alock_cal": "TITLE", "title_wait": "TITLE",

    "setup838": "SETUP", "su_loop": "SETUP", "su_draw": "SETUP",
    "su_tens": "SETUP", "su_ones": "SETUP",

    "new_game": "GAME", "start_krook": "GAME", "main": "GAME",
    "draw_screen": "GAME", "draw_prizes": "GAME", "draw_car": "GAME",
    "esc_cap_draw": "GAME",   # the escalator handrail's top turn,
                              # stamped into the floor above
    "beam_tops": "GAME",      # support-beam tops, likewise stamped into the
                              # slab row of the band above
    "radio_draw": "GAME",     # the victrola, four cells stamped into the
                              # band's air rows after the blit
    "coll_prize": "GAME", "scan_canvas": "GAME",
    "hud_all": "GAME", "hud_score": "GAME", "hud_time": "GAME",
    "hud_kops": "GAME", "prt_digits": "GAME", "prt_dloop": "GAME",
    "prt_dsub": "GAME", "prt_dout": "GAME", "add_score": "GAME",
    "tick_timer": "GAME", "tick_flash": "GAME",
    "do_catch": "GAME", "do_escape": "GAME", "do_death": "GAME",
    "lose_kop": "GAME",

    # These write the PATTERN table (base 4096), not the name table, so they
    # can never collide with a printed string. Mapped anyway, because an
    # unmapped drawing routine has to fail rather than be silently skipped.
    "scan_set": "PATT",
    "scan_mark": "PATT",      # a marker's three rows, pattern AND colour
    "scan_wipe1": "PATT",     # and giving the character its base colour back
    "scan_escc": "PATT",      # the flight's own colour, per character
    "scan_clr": "PATT", "scan_tick": "PATT",
    "scan_addr": "PATT", "scan_wipe": "PATT", "scan_furn": "PATT",
    "scan_or1": "PATT", "scan_pat": "PATT", "scan_base": "PATT",
    "scan_clr1": "PATT", "scan_escs": "PATT", "scan_elev": "PATT",
    # Writes the COLOUR table at >2000, which is neither the name table
    # nor the pattern table, so it can collide with nothing here.
    "font_colour": "COLR", "scan_colour": "COLR", "store_colour": "COLR",
    # repaints screen third 0's colour table so a flight crossing the roof
    # shows the deck behind it and one crossing a shop floor shows the bar --
    # same characters, told apart by which third they are in
    "esc_deck_col": "COLR",
}

# THE HUD, DECLARED. Every field on row 0 as (name, row, col, width). The
# digit printers walk forward from their start column, so checking only the
# first cell they touch would miss a field that overruns into the next one --
# which is the same "scope narrower than the bug" failure that let UFO's first
# checker pass. Declaring the extents is the only way to check them.
HUD_FIELDS = [
    ("SCORE label",  0,  0, 5),
    ("score digits", 0,  6, 6),   # 5 digits + the fixed trailing zero
    ("TIME label",   0, 14, 4),
    ("time digits",  0, 19, 2),
    ("kop icons",    0, 26, 6),
]


def screen_of(label):
    return SCREEN.get(label, "?" + label)


def main():
    lines = open(SRC, encoding="utf-8").read().split("\n")

    bad = []
    prints = []          # (lineno, label, row, col, text)
    pokes = []           # (lineno, label, row, col, varname)
    unchecked = []       # (lineno, label, varname)
    label = "(top)"
    # var -> EVERY literal it currently might hold. prt_dout is reached from
    # both hud_score and hud_time, and taking only the most recent assignment
    # would check one of its two columns and quietly ignore the other.
    addrs = {}

    for n, ln in enumerate(lines, 1):
        m = LABEL_RE.match(ln)
        if m:
            label = m.group(1)

        m = SETLIT_RE.match(ln)
        if m:
            addrs.setdefault(m.group(1), set()).add(int(m.group(2)))
        else:
            m = SETANY_RE.match(ln)
            if m:
                # built in steps, or from a table -- we no longer know it, and
                # pretending we do is how a checker reports a wrong answer
                addrs.pop(m.group(1), None)

        m = VPOKE_RE.match(ln)
        if m:
            var = m.group(1)
            hits = sorted(addrs.get(var, ()))
            if not hits:
                unchecked.append((n, label, var))
            for a in hits:
                off = a - NAME_TABLE
                if 0 <= off < 768:
                    pokes.append((n, label, off // 32, off % 32, var))
                else:
                    unchecked.append((n, label, var))

        m = PRINT_RE.match(ln)
        if m:
            off, text = int(m.group(1)), m.group(2)
            row, col = off // 32, off % 32
            prints.append((n, label, row, col, text))
            if col + len(text) > 32:
                bad.append("line %d (%s): PRINT AT %d is row %d col %d, %d chars "
                           "-- runs %d past column 31 and WRAPS onto the next row"
                           % (n, label, off, row, col, len(text),
                              col + len(text) - 32))
            if row > 23:
                bad.append("line %d (%s): PRINT AT %d is row %d, off screen"
                           % (n, label, off, row))

    touched = {l for _, l, _, _, _ in prints + pokes}
    touched |= {l for _, l, _ in unchecked}
    unknown = sorted(touched - set(SCREEN))
    if unknown:
        bad.append("routines that draw but are not in the SCREEN map, so their "
                   "rows were compared against nothing: %s" % ", ".join(unknown))

    # the declared HUD fields: on screen, and not on top of each other
    for i, (nm, row, col, wid) in enumerate(HUD_FIELDS):
        if col + wid > 32:
            bad.append("HUD field %r is row %d col %d width %d -- runs past "
                       "column 31" % (nm, row, col, wid))
        for nm2, row2, col2, wid2 in HUD_FIELDS[i + 1:]:
            if row2 != row:
                continue
            if col < col2 + wid2 and col2 < col + wid:
                bad.append("HUD fields %r (col %d..%d) and %r (col %d..%d) "
                           "OVERLAP" % (nm, col, col + wid - 1,
                                        nm2, col2, col2 + wid2 - 1))

    for pn, plabel, prow, pcol, var in pokes:
        for tn, tlabel, trow, tcol, text in prints:
            if screen_of(tlabel) != screen_of(plabel) or trow != prow:
                continue
            if tcol <= pcol < tcol + len(text):
                ch = text[pcol - tcol]
                bad.append("line %d (%s): VPOKE #%s writes row %d col %d, which "
                           "is INSIDE the string printed at line %d (%r) -- it "
                           "lands on the %r"
                           % (pn, plabel, var, prow, pcol, tn, text, ch))

    for n, label, row, col, text in prints:
        print("  %-5s row %2d col %2d  %-32r %s"
              % (screen_of(label), row, col, text, label))
    print()
    for n, label, row, col, var in pokes:
        print("  %-5s row %2d col %2d  <#%s> %s" % (screen_of(label), row, col,
                                                    var, label))
    print()
    for n, label, var in unchecked:
        print("  %-5s line %-5d #%-6s built in steps -- NOT statically checked (%s)"
              % (screen_of(label), n, var, label))
    print()

    if bad:
        for b in bad:
            print("FAIL: " + b)
        return 1
    print("layout OK -- %d strings, %d resolvable HUD writes, %d writes not "
          "statically resolvable; no overflow, no collisions"
          % (len(prints), len(pokes), len(unchecked)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
