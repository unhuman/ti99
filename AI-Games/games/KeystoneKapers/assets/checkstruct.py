#!/usr/bin/env python3
"""No erase routine may clear a character that means PERMANENT STRUCTURE.

The building's outside wall and a free-standing pillar both get their tops
stamped into the floor bar above them, by the same routine, one row apart in
the source.  They are not the same thing.  A radio or a prize stands in FRONT
of a pillar, so the pillar's cap has to come down or it hangs in the air above
the fixture -- but the outside wall is the building, and taking its cap away
leaves the storey above resting on nothing at the edge of the screen.

`beam_clear` cleared both for months.  It only ever showed on the escalator
screens (the flight fills the middle of the band, so those are the only screens
where a fixture is pushed out far enough for the two-cell clear to reach column
0 or 31), and it survived four passes over the templates, the beam-column
table and the draw order -- all of which were correct.

THE STRUCTURE SET IS DERIVED, NOT LISTED.  A hand-written list of "characters
that must not be cleared" would be a second copy of the same decision and could
not disagree with the first, which is the vacuous-guard failure this repo has
already shipped once (see _beam_cols in genstore.py).  So this reads
`beam_tops` itself: any character assigned inside an edge test -- `IF btc = 0`
or `IF btc = 31` -- is an END WALL cap by construction, because those two
branches are what "extreme column" means.

Then every VPEEK-driven clear is checked against that set.

Run:  python3 checkstruct.py        (exit 1 on a violation)
"""

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")


def routines(src):
    """label -> body, splitting on lines that are a bare `label:`."""
    out, cur, buf = {}, None, []
    for line in src.splitlines():
        m = re.match(r"^\s*([a-z_][a-z0-9_]*):\s*(?:'.*)?$", line)
        if m:
            if cur:
                out[cur] = "\n".join(buf)
            cur, buf = m.group(1), []
        elif cur:
            buf.append(line)
    if cur:
        out[cur] = "\n".join(buf)
    return out


def structure_chars(body):
    """Characters beam_tops writes ONLY at column 0 or column 31."""
    found, depth_edge = set(), 0
    for line in body.splitlines():
        t = line.strip()
        if re.match(r"^IF btc = (0|31) THEN\s*$", t):
            depth_edge += 1
            continue
        if depth_edge:
            if t == "END IF":
                depth_edge -= 1
                continue
            for m in re.finditer(r"=\s*(CH_[A-Z0-9_]+)", t):
                found.add(m.group(1))
    return found


def main():
    src = io.open(BAS, encoding="utf-8").read()
    rt = routines(src)

    if "beam_one" not in rt:
        print("FAIL  no beam_one: this check no longer knows where the caps "
              "are stamped, so it cannot derive the structure set")
        return 1

    struct = structure_chars(rt["beam_one"])
    if not struct:
        print("FAIL  beam_one has no `IF btc = 0/31` edge branch, so no "
              "character could be identified as an end-wall cap. Either the "
              "edge test moved or the caps went away -- check by hand.")
        return 1

    bad = []
    for name, body in sorted(rt.items()):
        if "VPEEK" not in body:
            continue
        # a clear is `IF <var> = CH_X THEN ... VPOKE`; the pattern below is
        # deliberately loose -- any test against a structure char inside a
        # routine that also POKEs is worth reporting
        if "VPOKE" not in body:
            continue
        for m in re.finditer(r"IF\s+\w+\s*=\s*(CH_[A-Z0-9_]+)", body):
            if m.group(1) in struct:
                bad.append((name, m.group(1)))

    print("end-wall caps (derived from beam_one's edge tests): %s"
          % ", ".join(sorted(struct)))
    if bad:
        for name, ch in bad:
            print("FAIL  %s clears %s -- that is the BUILDING'S OUTSIDE WALL, "
                  "not a pillar cap. Clearing it leaves the floor above "
                  "unsupported at column 0 / 31, which shows only on the "
                  "escalator screens." % (name, ch))
        return 1
    print("OK    no erase routine touches them")
    return 0


if __name__ == "__main__":
    sys.exit(main())
