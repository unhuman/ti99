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
            colour.append((g.GRAY, g.BLACK, g.WHITE, g.LYELL)[
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
                check(label, r, "GRAY" if r == fbase else "BLACK", lv)

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

    # the two dots, from scan_tick's own arithmetic
    for lv in range(4):
        rows = []
        run(rt, "scan_tick",
            {"klv": lv, "hlv": lv, "klsc": 0, "hsc": 0, "klx": 0, "hx": 0,
             "say": 0, "elvl": lv},
            stop=lambda n, e: rows.append(e.get("say")) if n == "scan_addr"
            else None)
        if len(rows) != 2:
            bad.append("scan_tick plots %d dots, expected 2 (Kelly, Harry)"
                       % len(rows))
        else:
            check("Kelly's dot", rows[0], "BLACK", lv)
            check("Harry's dot", rows[1], "WHITE", lv)

    if bad:
        for b in bad:
            print("FAIL: " + b)
        return 1
    print("radar OK -- %d px margin top and bottom, 4 levels x %d px; "
          "escalator heads and the car grey, Kelly black, Harry white, "
          "floor lines yellow" % (g.SCAN_TOP, BAND))
    return 0


if __name__ == "__main__":
    sys.exit(main())
