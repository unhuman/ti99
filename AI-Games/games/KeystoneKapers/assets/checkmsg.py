#!/usr/bin/env python3
"""Every message box drawn during play must be given its colours.

THE MISS THIS EXISTS FOR
------------------------
On the NES a message box's text takes its paper from the attribute table, and
over the store that is P0 -- gold on the same green the box sits on, which is
hard to read. Each box therefore points its four attribute bytes at P1, the HUD's
dark blue and white, right after it is drawn.

That was written out by hand at the sites that needed it, and one was missed:
**GOT HIM! kept the store's colours while every other box changed.** Nothing
failed. It is a perfectly readable message in the wrong palette, so no gate that
checks layout, overflow or collisions could see it -- and the author of the
change had no list to check against, because the list was "the places I edited".

So the rule is checked against the PRODUCER instead: anything that draws a
message list has to colour it.

WHAT IS CHECKED
---------------
For every `GOSUB run_list` that draws a MESSAGE (a `#tta = VARPTR msg_*`), the
NES build must, within a few lines:

  * `WAIT` before it -- PPUBUF accumulates for a whole pass, and without a flush
    the box's sixty-odd writes share a vblank with the pass's radar and HUD
    traffic; the copy then overruns and the tail is discarded at the PPU, which
    is the corrupted-box fault; and
  * `GOSUB nes_boxatt` after it, with an `#nav` set first.

The TITLE's `run_list` is deliberately excluded on both counts: it is not a
message, it is drawn at boot with nothing else queued, and a WAIT per run there
made the logo visibly assemble itself.

Run:  python3 checkmsg.py        exits non-zero if a box is drawn uncoloured
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BAS = (sys.argv[1] if len(sys.argv) > 1
       else os.path.join(HERE, "..", "src", "KEYSTONE.bas"))

TTA = re.compile(r"^\s*(?:IF .*THEN )?#tta = VARPTR (\w+)\(0\)")
# TRAILING COMMENTS ARE ALLOWED ON ALL OF THESE. The first version anchored at
# end-of-line and reported GAME OVER as having no WAIT, because its WAIT carries
# an explanatory comment -- a false alarm from the checker, not a fault in the
# code, and the kind that gets a gate deleted.
CALL = re.compile(r"^\s*GOSUB run_list\s*(?:'.*)?$")
BOXATT = re.compile(r"^\s*GOSUB nes_boxatt\s*(?:'.*)?$")
NAV = re.compile(r"^\s*#nav = (\d+)")
WAIT = re.compile(r"^\s*WAIT\s*(?:'.*)?$")

LOOKBACK = 10                           # lines above the GOSUB for the source
LOOKAHEAD = 8                           # and below it for the colouring


def _code(src, i, n):
    """The next (or previous) `n` lines that are not comments or blanks.

    Anchored at line `i`: a positive `n` walks forward from it, a negative one
    walks backward. Comments and blank lines are skipped rather than counted,
    so a window is a bound on STATEMENTS and cannot be closed by documentation.
    """
    step = 1 if n > 0 else -1
    out, j = [], i
    while len(out) < abs(n) and 0 <= j < len(src):
        s = src[j].strip()
        if s and not s.startswith("'"):
            out.append(src[j])
        j += step
    return out


def main(path=None, quiet=False):
    src = open(path or BAS, encoding="utf-8").read().split("\n")
    bad, seen = [], 0

    for i, ln in enumerate(src):
        if not CALL.match(ln):
            continue
        # which list is being drawn? the nearest #tta above
        what = None
        for j in range(i - 1, max(-1, i - LOOKBACK), -1):
            m = TTA.match(src[j])
            if m:
                what = m.group(1)
                break
        if what is None:
            bad.append("line %d: GOSUB run_list with no `#tta = VARPTR ...` "
                       "above it -- this file cannot tell what it draws"
                       % (i + 1))
            continue
        if not what.startswith("msg_"):
            continue                    # the title, deliberately
        seen += 1

        # THE WINDOWS COUNT CODE LINES, NOT SOURCE LINES.
        #
        # They counted source lines, so a paragraph of comment between the draw
        # and its colouring pushed the `GOSUB nes_boxatt` out of reach and the
        # file reported two boxes as "drawn but never coloured" -- on code that
        # was correct, with the reason sitting four lines further down.
        #
        # A check that fails on working code is as expensive as one that passes
        # on broken code: the obvious response to it is to weaken the rule.
        # checkanim.py had the identical bug from the other direction, where a
        # comment block hid an animation band and the gate went quietly blind.
        has_wait = any(WAIT.match(l) for l in _code(src, i, -LOOKBACK))
        has_att = any(BOXATT.match(l) for l in _code(src, i, LOOKAHEAD))
        has_nav = any(NAV.match(l) for l in _code(src, i, LOOKAHEAD))

        if not has_wait:
            bad.append("line %d: %s is drawn with no WAIT in front of it. "
                       "PPUBUF accumulates for a whole pass, so the box's "
                       "writes would share a vblank with the radar and the "
                       "HUD, the copy would overrun it and the tail would be "
                       "discarded -- a box with characters missing."
                       % (i + 1, what))
        if not has_att:
            bad.append("line %d: %s is drawn but never coloured -- no `GOSUB "
                       "nes_boxatt` follows it. The box keeps the STORE's "
                       "palette: gold text on the green it is sitting on. "
                       "Nothing fails and it is simply hard to read, which is "
                       "how GOT HIM! stayed that way while the others changed."
                       % (i + 1, what))
        elif not has_nav:
            bad.append("line %d: %s calls nes_boxatt without setting #nav "
                       "first, so it would colour whatever four bytes were "
                       "left over" % (i + 1, what))

    if seen == 0:
        bad.append("found no message boxes at all -- this check has stopped "
                   "applying, which is worse than it failing")

    if quiet:
        return 1 if bad else 0
    print("checkmsg: %d message box(es) drawn during play" % seen)
    if bad:
        for b in bad:
            print("FAIL: " + b)
        return 1
    print("messages OK -- every box is flushed before it is drawn and coloured "
          "after it")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else None))
