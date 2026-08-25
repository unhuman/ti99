#!/usr/bin/env python3
"""Check every PRINT AT and HUD VPOKE in UFO.bas against the 32x24 screen.

Two failures this catches, both of which look like anything but a layout bug
when you meet them in an emulator:

  * A string that runs past column 31 WRAPS onto the next row and overwrites
    whatever was there, so the damage shows up on a line you were not editing.
  * A VPOKE that drops a digit into a cell some PRINT AT already owns. The
    838 setup screen did exactly this -- the difficulty digit was written at
    column 16, which is the middle of the word DIFFICULTY, so it read as a
    typo in the label rather than as a misplaced value.

Neither is visible in the source: both are arithmetic on a bare offset.

Run:  python3 checklayout.py        exits non-zero if anything is wrong
"""

import os
import re
import sys

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "UFO.bas")
NAME_TABLE = 6144

PRINT_RE = re.compile(r'^\s*PRINT AT (\d+),"([^"]*)"')
LABEL_RE = re.compile(r"^([a-z_][a-z0-9_]*):")
# Only the HUD writes we can resolve statically: `#var = <literal>` followed by
# a VPOKE of that var. Anything computed in a loop is out of scope.
SETADDR_RE = re.compile(r"^\s*#(\w+) = (\d{4,5})\b")
# WHICH SCREEN EACH ROUTINE PAINTS. Grouping by LABEL is not enough, and the
# first version of this file proved it: the 838 screen's text is printed under
# `setup838` while its digits are written under `su_draw`, so a per-label check
# compared them against nothing and passed the very collision it exists to
# catch. A row only means something within one screen, so the screen is the
# unit -- and it has to be written down, because nothing in the source says it.
SCREEN = {
    "title_screen": "TITLE",
    "setup838": "SETUP", "su_loop": "SETUP", "su_draw": "SETUP",
    "new_game": "GAME", "main": "GAME", "prt_dout": "GAME",
    "prt_lives": "GAME", "do_death": "GAME", "lprate": "GAME",
}


def screen_of(label):
    return SCREEN.get(label, "?" + label)


VPOKE_RE = re.compile(r"^\s*VPOKE #(\w+),")


def main():
    lines = open(SRC, encoding="utf-8").read().split("\n")

    bad = []
    prints = []          # (lineno, label, row, col, text)
    pokes = []           # (lineno, label, row, col, varname)
    label = "(top)"
    addrs = {}

    for n, ln in enumerate(lines, 1):
        m = LABEL_RE.match(ln)
        if m:
            label = m.group(1)

        m = SETADDR_RE.match(ln)
        if m:
            addrs[m.group(1)] = int(m.group(2))

        m = VPOKE_RE.match(ln)
        if m and m.group(1) in addrs:
            off = addrs[m.group(1)] - NAME_TABLE
            if 0 <= off < 768:
                pokes.append((n, label, off // 32, off % 32, m.group(1)))

        m = PRINT_RE.match(ln)
        if m:
            off, text = int(m.group(1)), m.group(2)
            row, col = off // 32, off % 32
            prints.append((n, label, row, col, text))
            if col + len(text) > 32:
                bad.append("line %d (%s): PRINT AT %d is row %d col %d, %d chars "
                           "-- runs %d past column 31 and WRAPS"
                           % (n, label, off, row, col, len(text),
                              col + len(text) - 32))
            if row > 23:
                bad.append("line %d (%s): PRINT AT %d is row %d, off screen"
                           % (n, label, off, row))

    # A VPOKE landing inside a PRINT AT in the same routine is a collision.
    unknown = sorted({l for _, l, _, _, _ in prints + pokes} - set(SCREEN))
    if unknown:
        bad.append("routines not in the SCREEN map, so their rows were compared "
                   "against nothing: %s" % ", ".join(unknown))

    for pn, plabel, prow, pcol, var in pokes:
        for tn, tlabel, trow, tcol, text in prints:
            if screen_of(tlabel) != screen_of(plabel) or trow != prow:
                continue
            if tcol <= pcol < tcol + len(text):
                ch = text[pcol - tcol]
                bad.append("line %d (%s): VPOKE #%s writes row %d col %d, which is "
                           "INSIDE the string printed at line %d (%r) -- it lands on "
                           "the %r"
                           % (pn, plabel, var, prow, pcol, tn, text, ch))

    for n, label, row, col, text in prints:
        print("  %-5s row %2d col %2d  %-30r  %s"
              % (screen_of(label), row, col, text, label))
    print()
    for n, label, row, col, var in pokes:
        print("  %-5s row %2d col %2d  <#%s>%s%s"
              % (screen_of(label), row, col, var,
                 " " * max(1, 22 - len(var)), label))
    print()

    if bad:
        for b in bad:
            print("FAIL: " + b)
        return 1
    print("layout OK -- %d strings, %d resolvable HUD writes, no overflow, no collisions"
          % (len(prints), len(pokes)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
