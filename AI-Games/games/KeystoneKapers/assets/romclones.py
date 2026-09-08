#!/usr/bin/env python3
"""Repeated statement sequences in the CVBasic source -- duplication, measured.

Every byte of the fixed area is scarce (CLAUDE.md 3A), and the three times this
game has been rescued from the cap it was by finding two pieces of code doing the
same job -- the prize erase and the radio erase turning into one `wipe_2x2`, the
838 page's two draw routines, the font colour fill that a table already held.
Each was found by reading, which does not scale to 4,200 lines.

This finds them mechanically: strip comments and blank lines, normalise each
statement, and report every run of >= MIN statements that occurs more than once,
ranked by the bytes it could plausibly return (extra copies x length).

WHAT IT CANNOT TELL YOU is whether a clone is worth folding. A run of N
statements factored into a GOSUB costs the call, the return, and any parameter
staging -- so short clones with many distinct variables are usually a loss.
Ranked output is a reading list, not a work list.

Usage:
    python3 romclones.py [-m 4] [-n 25] [source.bas]
"""

import os
import re
import sys

# A rough per-statement cost, from romprofile.py's totals: 20,580 bytes of game
# code over roughly a thousand statements. Only used for ranking.
BYTES_PER_STMT = 20


def statements(path):
    """[(line_no, normalised_text)] -- code only, comments and blanks dropped."""
    out = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for n, raw in enumerate(fh, 1):
            s = raw.strip()
            if not s or s.startswith("'"):
                continue
            # a trailing comment on a real statement
            if "'" in s:
                q = 0
                for i, c in enumerate(s):
                    if c == '"':
                        q ^= 1
                    elif c == "'" and not q:
                        s = s[:i].strip()
                        break
            if not s:
                continue
            out.append((n, re.sub(r"\s+", " ", s)))
    return out


def main():
    args = list(sys.argv[1:])
    minlen, top = 4, 25
    for flag, setter in (("-m", "minlen"), ("-n", "top")):
        if flag in args:
            i = args.index(flag)
            if setter == "minlen":
                minlen = int(args[i + 1])
            else:
                top = int(args[i + 1])
            del args[i:i + 2]
    here = os.path.dirname(os.path.abspath(__file__))
    path = args[0] if args else os.path.join(here, "..", "src", "KEYSTONE.bas")

    stmts = statements(path)
    text = [t for _, t in stmts]
    lines = [n for n, _ in stmts]

    # Longest repeated runs, greedily: index every window of MIN statements,
    # then extend each duplicated window as far as it stays duplicated.
    seen = {}
    for i in range(len(text) - minlen + 1):
        seen.setdefault(tuple(text[i:i + minlen]), []).append(i)

    found = []
    covered = set()
    for key, idxs in seen.items():
        if len(idxs) < 2:
            continue
        if any(i in covered for i in idxs):
            continue
        # extend while every occurrence still matches
        n = minlen
        while True:
            if idxs[-1] + n >= len(text):
                break
            nxt = text[idxs[0] + n]
            if all(text[j + n] == nxt for j in idxs[1:]):
                n += 1
            else:
                break
        # non-overlapping occurrences only
        keep, last = [], -10 ** 9
        for j in idxs:
            if j >= last + n:
                keep.append(j)
                last = j
        if len(keep) < 2:
            continue
        for j in keep:
            covered.update(range(j, j + n))
        found.append((n, keep))

    found.sort(key=lambda f: -(f[0] * (len(f[1]) - 1)))

    print("%d statements of code in %s" % (len(text), os.path.basename(path)))
    print("Repeated runs of >= %d statements, ranked by removable bytes\n" % minlen)
    shown = 0
    for n, idxs in found:
        if shown >= top:
            break
        shown += 1
        gain = n * (len(idxs) - 1) * BYTES_PER_STMT
        print("%2d statements x %d copies  ~%4d B   lines %s"
              % (n, len(idxs), gain,
                 ", ".join(str(lines[j]) for j in idxs)))
        for t in text[idxs[0]:idxs[0] + min(n, 6)]:
            print("      %s" % t)
        if n > 6:
            print("      ... (%d more)" % (n - 6))
        print()


if __name__ == "__main__":
    main()
