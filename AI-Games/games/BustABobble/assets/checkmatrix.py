#!/usr/bin/env python3
"""
Cross-check a difficulty matrix of winnability proofs for IMPOSSIBLE RESULTS.

WHY THIS EXISTS. solvelevels.py is a beam search, and it says so: finding a line
proves a round winnable, but NOT finding one proves nothing -- it reports
UNPROVEN and leaves you to judge. That is honest, and on its own it is not
enough, because an UNPROVEN has two very different causes that print almost
identically:

    round 31  UNPROVEN   no surviving shot
    round 31  UNPROVEN   depth limit (90 shots), best left 19 bubbles

The first is a level killing you. The second is the SEARCH giving up. Only the
trailing text tells them apart, and a tally that counts "unproven" does not.

A matrix gives us a check the solver cannot make from inside a single run:

    A LEVEL PROVEN AT A HARDER SETTING MUST BE WINNABLE AT EVERY EASIER ONE.

Harder settings are strictly more pressure -- the same board, the same clock, the
same shot sequence, only a bigger charge per shot -- so any easier setting can
replay the harder line and finish with clock to spare. If a level passes at hard
and fails at medium, the medium result is FALSE. Nothing about the game is wrong.

That is not hypothetical: expert level 31 passed at hard and reported UNPROVEN at
medium, purely on the depth limit, and it proves in 93 shots at --depth 160. The
counterintuitive part is that EASIER settings need a DEEPER search -- more clock
means longer viable lines -- so the default depth bites hardest where the game is
most forgiving.

Run:  python3 checkmatrix.py m_arcade_easy.txt m_arcade_medium.txt m_arcade_hard.txt
      (in increasing order of difficulty -- the order is the whole point)

Exit code 1 if any impossible pair is found, so a build can gate on it.
"""

import os
import re
import sys


def read(path):
    """{level: (winnable, reason)} from a file of solvelevels result lines."""
    out = {}
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\s*round (\d+)\s+(\S+)\s*(.*)", line)
        if not m:
            continue
        lvl, verdict, rest = int(m.group(1)), m.group(2), m.group(3).strip()
        win = verdict.startswith("WINNABLE")
        # A level can appear twice if a run was resumed; a failure is never
        # overwritten by a later success, so the pessimistic reading wins.
        if lvl in out and not out[lvl][0]:
            continue
        out[lvl] = (win, rest)
    return out


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    paths = sys.argv[1:]
    cols = []
    for p in paths:
        if not os.path.exists(p):
            sys.stderr.write("error: %s does not exist\n" % p)
            return 2
        cols.append((os.path.basename(p), read(p)))

    print("  %-28s %s" % ("file (easiest first)", "winnable / total"))
    for name, d in cols:
        print("  %-28s %d / %d" % (name, sum(1 for w, _ in d.values() if w), len(d)))
    print()

    bad = 0
    # Compare every column against every HARDER column to its right.
    for i in range(len(cols)):
        for j in range(i + 1, len(cols)):
            easy_name, easy = cols[i]
            hard_name, hard = cols[j]
            for lvl in sorted(set(easy) & set(hard)):
                if hard[lvl][0] and not easy[lvl][0]:
                    bad += 1
                    print("  IMPOSSIBLE: level %d passes in %s but fails in %s"
                          % (lvl, hard_name, easy_name))
                    print("              %s is strictly easier, so it can replay the"
                          " harder line." % easy_name)
                    print("              the failure is the SEARCH, not the level:"
                          " %s" % (easy[lvl][1] or "no reason given"))
                    print("              re-run that level with a larger --depth"
                          " (and --beam if needed)")
    if bad:
        print()
        print("  %d impossible result(s) -- the matrix contains at least that many"
              " false negatives" % bad)
        return 1
    print("  no impossible pairs: every level that passes at a harder setting also"
          " passes at every easier one")
    return 0


if __name__ == "__main__":
    sys.exit(main())
