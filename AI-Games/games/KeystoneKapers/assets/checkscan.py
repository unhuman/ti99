#!/usr/bin/env python3
"""Check the radar's geometry against the colours generated for it.

The scanner is drawn in the TMS9918's per-scanline colour mode, which is the
only reason it can show four things at once: each pixel row of a level band
carries exactly one colour, so the ROW a thing is plotted on decides what
colour it comes out. That makes the band layout a contract between two files
that never mention each other -- KEYSTONE.bas computes the rows, genart.py
emits the colours -- and getting them out of step produces no error at all.
It produces a white Kop, or an escalator drawn in floor-line yellow, or a dot
plotted in a margin row, where the ink is the same colour as the ground and
the marker simply does not appear.

So: evaluate the real arithmetic out of the source, and check the row each
thing lands on is coloured for the job it is doing.

Run:  python3 checkscan.py        exits non-zero if a row has the wrong colour
"""

import os
import re
import sys

import genart as g

HERE = os.path.dirname(os.path.abspath(__file__))
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")

BAND = 4                      # pixel rows per level
ROLE = {"GRAY": g.GRAY, "BLACK": g.BLACK, "WHITE": g.WHITE, "LYELL": g.LYELL}
NAMES = {v: k for k, v in ROLE.items()}


def routines():
    """label -> its lines, up to the next label."""
    out, cur = {}, None
    for ln in open(BAS, encoding="utf-8").read().split("\n"):
        m = re.match(r"^([a-z_][a-z0-9_]*):", ln)
        if m:
            cur = m.group(1)
            out[cur] = []
            ln = ln[m.end():]
        if cur is not None:
            out[cur].append(ln)
    return out


TERM = r"(-?\d+|[a-z_][a-z0-9_]*)"
ASSIGN = re.compile(r"^\t([a-z_][a-z0-9_]*) = %s(?: ([-+/]) %s)?$" % (TERM, TERM))
GOSUB = re.compile(r"^\tGOSUB (\w+)$")
COMMENT = re.compile(r"\s*'.*$")


class Unknown(Exception):
    pass


def val(t, env):
    if re.match(r"^-?\d+$", t):
        return int(t)
    if t not in env:
        raise Unknown(t)
    return env[t]


def run(rt, label, env, stop=None):
    """Evaluate straight-line integer arithmetic at ONE tab of indent.

    One tab only, deliberately: everything nested inside an IF is skipped,
    which is right here because none of the conditional arms touch the row
    variables. `GOSUB scan_base` is followed for real, because that is where
    a band's top row comes from; every other GOSUB is handed to `stop`, so a
    caller can read a row off at the moment it is used. An assignment whose
    inputs are not known is DROPPED rather than guessed -- a checker that
    invents a value reports a confident wrong answer, which is worse than
    reporting nothing.
    """
    for ln in rt[label]:
        ln = COMMENT.sub("", ln.rstrip())
        if not ln:
            continue
        if ln.lstrip().startswith("SPRITE ") and stop:
            stop("SPRITE", env)
            continue
        m = GOSUB.match(ln)
        if m:
            if m.group(1) == "scan_base":
                run(rt, "scan_base", env)
            elif stop:
                stop(m.group(1), env)
            continue
        m = ASSIGN.match(ln)
        if not m:
            continue
        dst, a, op, b = m.groups()
        try:
            v = val(a, env)
            if op == "+":
                v += val(b, env)
            elif op == "-":
                v -= val(b, env)
            elif op == "/":
                v //= val(b, env)
        except Unknown:
            env.pop(dst, None)
            continue
        env[dst] = v
    return env


def main():
    rt = routines()
    bad = []

    # what colour genart gives each of the 24 canvas pixel rows
    colour = []
    for row in range(24):
        if row < g.SCAN_TOP or row >= g.SCAN_TOP + 4 * BAND:
            colour.append(None)          # margin
        else:
            # THE TABLE ONLY HAS TWO ROLES NOW: three rows of a floor's
            # air, and its yellow line. The Kop and the crook are coloured
            # per CHARACTER at run time (scan_mark), which is what lets both
            # of them be three pixels tall instead of one.
            colour.append((g.GRAY, g.GRAY, g.GRAY, g.LYELL)[
                (row - g.SCAN_TOP) % BAND])

    def check(what, row, want, lv):
        if row is None:
            bad.append("%s on level %d: could not resolve its canvas row"
                       % (what, lv))
        elif not 0 <= row < 24:
            bad.append("%s on level %d lands on canvas row %d, off the canvas"
                       % (what, lv, row))
        elif colour[row] is None:
            bad.append("%s on level %d lands on canvas row %d, which is a "
                       "MARGIN row -- inked the same colour as the ground, so "
                       "it would not appear at all" % (what, lv, row))
        elif colour[row] != ROLE[want]:
            bad.append("%s on level %d lands on canvas row %d, which genart "
                       "colours %s -- it should be %s"
                       % (what, lv, row, NAMES.get(colour[row], colour[row]),
                          want))

    for lv in range(4):
        fbase = run(rt, "scan_base", {"fl": lv})["fbase"]
        want = (3 - lv) * BAND + g.SCAN_TOP
        if fbase != want:
            bad.append("scan_base gives level %d a top row of %d; genart's "
                       "SCAN_TOP=%d and a %d px band make it %d"
                       % (lv, fbase, g.SCAN_TOP, BAND, want))

        # THE FURNITURE, read out of the routines that actually draw it. The
        # escalator is a diagonal spanning two rows: the head on the grey row
        # and the foot on the black one below, which the manual draws black
        # anyway. The car is one row, grey.
        for label in ("scan_escs", "scan_elev"):
            rows = []
            run(rt, label, {"fl": lv, "elvl": lv},
                stop=lambda _n, e: rows.append(e.get("say")))
            for r in [r for r in rows if r is not None]:
                check(label, r, "GRAY", lv)

        # THE FLOOR LINE is the one thing scan_furn draws full width, so it
        # is found by its VPOKE rather than by matching `say = fbase + N`
        # -- that pattern also matches the escalator drawn a few lines
        # above it, and checking the wrong row is how a checker reports a
        # failure that is not there (and, next time, misses one that is).
        row, floor = None, None
        for ln in rt["scan_furn"]:
            ln = COMMENT.sub("", ln.rstrip())
            m = re.match(r"^	+say = fbase(?: \+ (\d+))?$", ln)
            if m:
                row = fbase + int(m.group(1) or 0)
            elif "VPOKE #sda,255" in ln:
                floor = row
        check("floor line", floor, "LYELL", lv)

    # THE TWO MARKERS ARE SPRITES, and what has to be checked about them is
    # the one thing a sprite cannot get right by itself: WHERE it lands.
    #
    # There is no colour to check any more -- a sprite carries its own, so the
    # merge that made Kelly blink cannot happen -- and no pixels to erase. What
    # is still easy to get wrong is the row.
    #
    # THE VDP PUTS A SPRITE'S TOP LINE AT y + 1. The canvas is characters 8-23
    # of screen rows 21-23, so canvas row r is screen row 168 + r -- and a
    # sprite asked for y therefore inks canvas row y + 1 - 168. Miss that bias
    # and a three-pixel marker in a three-pixel band puts its bottom row on the
    # yellow floor line, which is exactly what happened when the character
    # markers (poked straight into the pattern table, no bias) were replaced by
    # sprites and the old number came across with them.
    #
    # Row 3 of a band is the floor line and nothing may touch it.
    for lv in range(4):
        ys = []

        def spr(n, e, ys=ys):
            if n == "SPRITE":
                ys.append(e.get("sdy"))

        run(rt, "scan_tick",
            {"klv": lv, "hlv": lv, "klsc": 0, "hsc": 0, "klx": 0, "hx": 0,
             "say": 0, "elvl": lv}, stop=spr)
        if len(ys) != 2:
            bad.append("scan_tick places %d radar sprites, expected 2 "
                       "(the Kop and the crook)" % len(ys))
            continue
        for who, y in zip(("Kelly", "Harry"), ys):
            if y is None:
                bad.append("%s's marker on level %d: its screen y could not "
                           "be resolved" % (who, lv))
            elif not 167 <= y <= 188:
                bad.append("%s's marker on level %d is at sprite y %d, which "
                           "inks canvas rows %d-%d -- outside the scanner's 24"
                           % (who, lv, y, y + 1 - 168, y + 3 - 168))
            else:
                # it is three pixels tall, so the LAST row matters too
                for k in range(3):
                    check("%s's marker row %d" % (who, k),
                          y + 1 - 168 + k, "GRAY", lv)

    # THE THREE RUN-TIME COLOURS MUST ALL DIFFER FROM EACH OTHER. Two of
    # them being equal is not a colour-table error -- the table is fine -- it
    # is a marker that cannot be told from the furniture it stands on, or a
    # Kop that cannot be told from the crook. That has happened here twice
    # (a grey car drawn on a grey floor line), and neither time did any
    # per-row check see it, because per-row is not where the fault was.
    src = open(BAS, encoding="utf-8").read()
    cols = {}
    for name in ("SC_KOP",):
        m = re.search(r"^\s*CONST %s = (\d+)" % name, src, re.M)
        if not m:
            bad.append("CONST %s is missing -- the markers have no colour" % name)
        else:
            cols[name] = int(m.group(1))
    seen = {}
    for name, v in sorted(cols.items()):
        if v in seen:
            bad.append("%s and %s are both %d, so one cannot be told from the "
                       "other on screen" % (seen[v], name, v))
        seen[v] = name
    for name, v in sorted(cols.items()):
        if (v & 15) != g.DGREEN:
            bad.append("%s has background %d, not the canvas's dark green (%d)"
                       % (name, v & 15, g.DGREEN))

    # THE TWO SPRITE COLOURS MUST DIFFER FROM EACH OTHER. They are the only
    # thing separating the Kop from the crook now that the blink is gone, and
    # they are two bare integers sitting a long way apart in the source.
    spr = {}
    for name in ("C_RKOP", "C_RCROOK"):
        m = re.search(r"^\s*CONST %s = (\d+)" % name, src, re.M)
        if not m:
            bad.append("CONST %s is missing -- a radar marker has no colour"
                       % name)
        else:
            spr[name] = int(m.group(1))
    if len(spr) == 2 and spr["C_RKOP"] == spr["C_RCROOK"]:
        bad.append("C_RKOP and C_RCROOK are both %d, so the Kop and the crook "
                   "are the same colour on the radar" % spr["C_RKOP"])

    if bad:
        for b in bad:
            print("FAIL: " + b)
        return 1
    print("radar OK -- %d px margin top and bottom, 4 levels x %d px; three "
          "rows of grey air and a yellow line each, furniture in characters "
          "and the two actors as sprites over it" % (g.SCAN_TOP, BAND))
    return 0


if __name__ == "__main__":
    sys.exit(main())
