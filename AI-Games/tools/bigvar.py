#!/usr/bin/env python3
"""Find PLAIN (8-bit) CVBasic variables assigned a value over 255.

A CVBasic variable without a `#` prefix is EIGHT BITS. Assigning it anything
above 255 silently keeps the low byte -- no error at build time, none at run
time, and the result is almost always a plausible-looking wrong number rather
than an obvious zero. CLAUDE.md 3A records two occasions this shipped:

    rdp = 463   -> 207   the 838 menu drew its digits at row 6, not row 14
    sdc = 713   -> 201   a black 2x2 hole punched through the playfield

Both read as odd layout choices rather than as bugs, for weeks. This is the
companion to tools/bigconst.py, which covers the `CONST` form of the same
hazard; between them they cover both ways the truncation gets in.

WHAT IT FLAGS: an assignment `name = ...` where `name` is lower-case and has no
`#`, and the expression contains an integer literal above 255. The literal is
what matters, not the final value: CVBasic evaluates the whole expression in 8
bits, so `scti = 300 - rnd * 30` truncates 300 to 44 BEFORE the subtraction --
which is exactly how RALLY-X's round-1 head start became the SHORTEST one
instead of the longest.

REVIEW EACH HIT. An expression that only ever reduces below 256 (`x = 300 - 100`)
is a false positive, and a variable used purely as a flag may not care. The fix
where it is real is a `#` variable, or a bare literal at the point of use.

Run:  python3 tools/bigvar.py [path ...]      exit 1 if anything is found
"""

import glob
import os
import re
import sys

# name = ... , where name is a plain lower-case variable (no '#', not a member)
ASSIGN = re.compile(r"(?<![#\w.$])([a-z][a-z_0-9]*)\s*=\s*([^:']+)")
# A literal that is a DIVISOR cannot overflow the target -- `bpx = #bx / 256` is the
# normal way to bring a 16-bit fixed-point value down into a byte, and flagging it
# would make the tool cry wolf on correct code. Multiplication is NOT exempt: an
# 8-bit `x = y * 300` truncates exactly like a bare assignment.
LITERAL = re.compile(r"(?<![\w.$>])(?<!/\s)(?<!/)(\d+)(?![\w.])")

# `=` also appears as a comparison inside these, where no assignment happens
SKIP = re.compile(r"^\s*(IF|WHILE|UNTIL|ELSEIF|CONST|DIM|DATA|REM)\b", re.I)


def accepted():
    """(basename, variable, value) triples recorded as deliberately not fixed.

    Kept in tools/truncation-accepted.txt rather than as markers in the source,
    because some live in RELEASED games whose sources must not be touched at all
    -- not even to add a comment. Matched on the basename so line numbers drifting
    does not break an entry.
    """
    out = set()
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "truncation-accepted.txt")
    if not os.path.isfile(path):
        return out
    for line in open(path, encoding="utf-8"):
        line = line.split("#")[0].split()
        if len(line) >= 3:
            out.add((line[0], line[1], line[2]))
    return out


ACCEPTED = accepted()


def scan(path):
    hits = []
    for n, raw in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        # An ACCEPTED truncation is marked in the line's own comment, so the reason
        # travels with the code instead of rotting in a list somewhere else. A gate
        # that fires on findings everyone has agreed to live with is a gate everyone
        # learns to ignore, which is worse than no gate.
        if "TRUNCATION-OK" in raw:
            continue
        line = raw.split("'")[0]          # strip trailing comment
        if not line.strip() or SKIP.match(line):
            continue
        for m in ASSIGN.finditer(line):
            expr = m.group(2)
            big = [int(x) for x in LITERAL.findall(expr) if int(x) > 255]
            base = os.path.basename(path)
            big = [x for x in big if (base, m.group(1), str(x)) not in ACCEPTED]
            if big:
                hits.append((n, m.group(1), expr.strip(), max(big)))
    return hits


def main():
    args = sys.argv[1:]
    if not args:
        here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        args = sorted(glob.glob(os.path.join(here, "games", "*", "src", "*.bas")))
    total = 0
    for path in args:
        hits = scan(path)
        if not hits:
            continue
        rel = os.path.relpath(path)
        for n, name, expr, big in hits:
            print("%s:%d  %s = %s   (%d truncates to %d)"
                  % (rel, n, name, expr, big, big & 255))
        total += len(hits)
    print()
    print("  %d plain-variable assignment(s) with a literal over 255" % total)
    if total:
        print("  A plain CVBasic variable is 8-BIT: the low byte is kept, silently.")
        print("  Use a # variable, or review each hit -- an expression that always")
        print("  reduces below 256 is a false positive.")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
