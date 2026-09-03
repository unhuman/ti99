#!/usr/bin/env python3
"""Check every hand-written character number in KEYSTONE.bas against genart.py.

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


def main():
    src = open(BAS, encoding="utf-8").read().split("\n")
    bad = []
    seen = 0
    loads = 0

    for n, ln in enumerate(src, 1):
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

    if bad:
        for b in bad:
            print("FAIL: " + b)
        return 1
    print("character numbers OK -- %d CH_ constants match genart's table, "
          "both loads cover all %d characters" % (seen, len(g.CHARS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
