#!/usr/bin/env python3
"""
BUST-A-BOBBLE 2 -- generates candidate levels for the EXPERT cart.

Writes assets/levels2.txt in exactly the format assets/levels.txt uses, so
genlevels.py consumes it unchanged. The arcade set is transcribed; this set is
generated, because there was nothing worth transcribing: Puzzle Bobble 2 is
principally a two-player game, and our own measurements say the arcade's SHAPES
were never what made it hard (28 of the 30 rounds clear before the ceiling drops
even once). The difficulty here comes from the shot-count drop rule, the colour
count and the bubble density -- see the depth note below for why it does NOT come
from digging deeper.

WHY THE DEPTH CEILING IS 8 ROWS, NOT 11. The layout format stores 11 rows and it
is tempting to use them. You cannot. check_death is

    CEILROW + top + 2*r + 1 >= DEATHROW      (1 + top + 2r + 1 >= 20)

so a bubble in grid row r kills at top >= 18 - 2r, and `top` starts at 0:

    rows   deepest row   ceiling drops before death
      6         5              8
      7         6              6
      8         7              4
      9         8              2
     10         9              0   <-- game over the instant the round loads
     11        10              0

The arcade set already runs to 8 rows, so depth is very nearly spent as a lever
-- the mean of 6.6 is not headroom, it is a distribution whose top end is already
at the wall. `maxr <= 8` is asserted below, and drops-to-death is printed per
level so a too-deep candidate is obvious rather than mysterious.

EVERYTHING IS DETERMINISTIC. One LCG, seeded per level from the level number, so
the whole set regenerates byte-identically. That matters because the pipeline is
generate -> prove -> rank -> re-emit: if a regeneration produced different boards
the proof would no longer describe the shipped bytes.

Run:  python3 genexpert.py [--levels N] [--seed S] [--out FILE]
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import transcribe_stages as ts          # noqa: E402  -- neighbours/reachable/sequence

OUT = os.path.join(HERE, "levels2.txt")

NSEQ = 32
MAXROW = 8              # deepest grid row a bubble may occupy (see the note above)
MAXCELL = 8             # gauge is 8 cells, so the base shot count caps there


def width(r):
    """Odd rows are 7 wide -- the half-cell hex stagger."""
    return 8 if (r & 1) == 0 else 7


class Rand(object):
    """The same LCG transcribe_stages.sequence() uses, so the two agree."""

    def __init__(self, seed):
        self.s = (seed * 2654435761 + 12345) & 0x7FFFFFFF

    def __call__(self, n):
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        return (self.s >> 16) % n


# ---------------------------------------------------------------- shape

def make_shape(rng, rows, mirror):
    """An occupancy grid that is CONNECTED TO THE CEILING BY CONSTRUCTION.

    Row 0 is seeded solid -- it is the only row the ceiling holds, and an arcade
    board hangs from a full ceiling rather than from a few pegs. Every cell below
    may be placed only if it already touches an occupied cell in the row ABOVE,
    which makes a detached blob impossible rather than merely unlikely. That is
    the defect (`--anchors`) that produced three different apparent bugs in the
    drop logic before it was tracked to the data.

    MOST BOARDS ARE MIRRORED. Free-running placement produces a field that
    trickles down and drifts to one side -- it reads as noise, not as a level
    someone designed. Building the left half and reflecting it costs nothing and
    is what makes the result look deliberate; the arcade's own layouts are
    largely symmetric. The COLOURS are not mirrored, only the shape: reflecting
    them too would hand the player matched pairs across the axis.
    """
    grid = [[False] * width(r) for r in range(rows)]
    grid[0] = [True] * 8                        # a full ceiling row

    for r in range(1, rows):
        w = width(r)
        half = (w + 1) // 2 if mirror else w
        # Dense near the ceiling, thinning with depth, so the field hangs.
        keep = 88 - 7 * r
        if keep < 35:
            keep = 35
        for c in range(half):
            above = [(rr, cc) for (rr, cc) in ts.neighbours(grid, r, c) if rr == r - 1]
            if any(grid[rr][cc] for (rr, cc) in above) and rng(100) < keep:
                grid[r][c] = True
        if mirror:
            for c in range(half):
                if grid[r][c]:
                    grid[r][w - 1 - c] = True
        if not any(grid[r]):
            # An empty row severs everything below it. Force one supported cell
            # rather than letting the layout quietly end early.
            for c in range(w):
                above = [(rr, cc) for (rr, cc) in ts.neighbours(grid, r, c) if rr == r - 1]
                if any(grid[rr][cc] for (rr, cc) in above):
                    grid[r][c] = True
                    if mirror:
                        grid[r][w - 1 - c] = True
                    break
    return grid


# ---------------------------------------------------------------- colour

def colour(rng, shape, ncol):
    """Colour the cells so the board does NOT arrive pre-matched.

    DESIGN.md 7 records this rule and never applied it to the arcade set: colour
    one cell at a time and reject any colour that would join TWO OR MORE
    already-placed neighbours of that colour. The arcade set instead uses a
    banding rule -- pairs shifted one step per row -- which stacks colours into
    3s and 4s mechanically and is why those boards read as diagonal stripes.

    Among the survivors the least-used colour wins, which keeps the palette even;
    a colour that appears once or twice is a forced detour rather than a target.
    """
    rows = len(shape)
    grid = [["."] * width(r) for r in range(rows)]
    used = dict((k, 0) for k in range(1, ncol + 1))
    forced = 0
    for r in range(rows):
        for c in range(width(r)):
            if not shape[r][c]:
                continue
            joins = {}
            for k in range(1, ncol + 1):
                n = 0
                for (rr, cc) in ts.neighbours(grid, r, c):
                    if grid[rr][cc] == str(k):
                        n += 1
                joins[k] = n
            ok = [k for k in joins if joins[k] < 2]
            if not ok:
                ok = [k for k in joins if joins[k] == min(joins.values())]
                forced += 1
            best = min(used[k] for k in ok)
            ok = [k for k in ok if used[k] == best]
            k = ok[rng(len(ok))]
            grid[r][c] = str(k)
            used[k] += 1

    # THEN REPAIR WHAT THE PLACEMENT RULE CANNOT SEE. Rejecting a colour that
    # joins two neighbours stops a cell from COMPLETING a group, but a run of
    # three still forms when each cell joins only one at the moment it is placed
    # and a later neighbour chains them. So sweep the finished board and recolour
    # one cell out of every group that survived.
    for _ in range(40):
        gs = groups(grid)
        if not gs:
            break
        for comp in gs:
            r, c = comp[rng(len(comp))]
            old = grid[r][c]
            for k in range(1, ncol + 1):
                if str(k) == old:
                    continue
                n = 0
                for (rr, cc) in ts.neighbours(grid, r, c):
                    if grid[rr][cc] == str(k):
                        n += 1
                if n < 2:
                    used[int(old)] -= 1
                    grid[r][c] = str(k)
                    used[k] += 1
                    break
    return grid, used, forced


def groups(grid):
    """Every connected same-colour run of 3+ already sitting on the board."""
    seen, out = set(), []
    for r in range(len(grid)):
        for c in range(width(r)):
            if grid[r][c] == "." or (r, c) in seen:
                continue
            k, stack, comp = grid[r][c], [(r, c)], []
            seen.add((r, c))
            while stack:
                cell = stack.pop()
                comp.append(cell)
                for (rr, cc) in ts.neighbours(grid, cell[0], cell[1]):
                    if (rr, cc) not in seen and grid[rr][cc] == k:
                        seen.add((rr, cc))
                        stack.append((rr, cc))
            if len(comp) >= 3:
                out.append(comp)
    return out


# ---------------------------------------------------------------- one level

def build(n, rng):
    rows = 6 + rng(4)                       # 6..9; 9 is a two-drop round
    # COLOURS ARE CAPPED AT 6, AND THIS IS MEASURED, NOT GUESSED. The first set
    # ran 5..8 and the solver proved all 50 at --overhead 30:
    #
    #     5 colours   12 won   0 lost   100%
    #     6 colours   13 won   1 lost    93%
    #     7 colours    7 won   3 lost    70%
    #     8 colours    2 won  12 lost    14%
    #
    # Eight colours is not hard, it is broken -- round 6 was only 6 rows and 33
    # bubbles and the solver reported it "not clearable even with the clock off",
    # so neither the drop rule nor the depth was the obstacle.
    #
    # The cause is this generator arguing with itself. Three in contact must pop,
    # so a colour needs material; with 8 colours over ~33 bubbles that is ~4 each,
    # and then the cluster-repair pass below strips out the groups that WOULD have
    # been there, leaving the player to assemble every group from a palette that
    # has barely enough of anything. The no-pre-made-clusters rule and a high
    # colour count fight, and the clusters rule wins.
    #
    # Note what does NOT predict failure: bubbles-per-colour. Failures ran 3.1 to
    # 6.5 and winnable rounds went as low as 3.8, so the ratio separates nothing.
    # The colour COUNT does.
    ncol = 4 + rng(3)                       # 4..6
    mirror = rng(4) > 0                     # 3 boards in 4 are symmetric
    shape = make_shape(rng, rows, mirror)

    occupied = set((r, c) for r in range(rows) for c in range(width(r)) if shape[r][c])
    maxr = max(r for (r, c) in occupied)
    if maxr > MAXROW:
        return None                          # would load already dead -- see header

    grid, used, forced = colour(rng, shape, ncol)

    # Only colours that actually landed count: a sparse board does not always
    # receive every colour its palette declares.
    live = sorted(int(k) for k in used if used[k] > 0)
    if not live or max(live) != len(live):
        return None                          # palette must be a prefix 1..N
    if min(used[k] for k in live) < 4:
        # FOUR, not two. Three in contact must pop, and the cluster-repair pass
        # deliberately breaks up any group that arrives pre-made -- so a colour
        # with exactly three on the board has to be rebuilt from scratch with no
        # margin for a misfire. Two was the old threshold and it let through
        # boards that were arithmetically clearable and practically not.
        return None

    st = {"n": n, "ncol": len(live)}
    rowstr = ["".join(row) for row in grid]
    seq = ts.sequence(st, rowstr)

    return {
        "n": n,
        "rows": rowstr,
        "ncol": len(live),
        "maxr": maxr,
        "bubbles": len(occupied),
        "drops": 18 - 2 * maxr,
        "groups": len(groups(grid)),
        "forced": forced,
        "seq": seq,
        # b, the base shot count. thr falls from b to b-(ncol-1) as colours are
        # eliminated, floored at 1, so this leaves ~3 shots a drop on the last
        # colour. Capped at the gauge's 8 cells.
        "shots": min(MAXCELL, len(live) + 2),
        # The fallback clock, not the pressure. Generous on purpose: a tight one
        # would reintroduce the thinking-time dependency the shot rule removes.
        "droptime": 35.0,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--levels", type=int, default=50, help="how many to emit")
    ap.add_argument("--seed", type=int, default=1, help="LCG seed offset")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()

    levels, n, tries = [], 0, 0
    while len(levels) < args.levels and tries < args.levels * 200:
        tries += 1
        n += 1
        lv = build(n, Rand(n * 7919 + args.seed))
        if lv is None:
            continue
        lv["n"] = len(levels) + 1
        levels.append(lv)
    if len(levels) < args.levels:
        sys.stderr.write("error: only %d of %d candidates were viable\n"
                         % (len(levels), args.levels))
        return 1

    with open(args.out, "w", newline="\n") as fh:
        fh.write("# BUST-A-BOBBLE 2 -- level data. GENERATED by assets/genexpert.py.\n"
                 "# Do not hand-edit: regenerate instead.\n"
                 "#\n"
                 "# Unlike the arcade set these shapes are ORIGINAL. See the header of\n"
                 "# genexpert.py for why (Puzzle Bobble 2 is a two-player game, and the\n"
                 "# arcade shapes were measured not to be what made it hard).\n"
                 "#\n"
                 "# SHOTS is the base ceiling-drop interval in bubbles fired; the engine\n"
                 "# drops every SHOTS-minus-missing-colours shots, so it accelerates as the\n"
                 "# board empties. DROPTIME is the anti-idle FALLBACK only.\n"
                 "#\n"
                 "# '.' = empty, '1'..'8' = colour. Even rows 8 cells, odd rows 7, indented.\n"
                 "# 1 red  2 green  3 blue  4 yellow  5 cyan  6 magenta  7 grey  8 white\n\n")
        for lv in levels:
            fh.write("LEVEL %d\n" % lv["n"])
            fh.write("COLOURS %d\n" % lv["ncol"])
            fh.write("SHOTS %d\n" % lv["shots"])
            fh.write("DROPTIME %g\n" % lv["droptime"])
            fh.write("SEQ %s\n" % lv["seq"])
            for r, row in enumerate(lv["rows"]):
                fh.write((" " if (r & 1) else "") + row + "\n")
            fh.write("\n")

    print("wrote %s -- %d levels" % (os.path.normpath(args.out), len(levels)))
    print()
    print("  lvl  rows  deep  drops  bubbles  colours  b   pre-made 3+  forced")
    bad = 0
    for lv in levels:
        flag = ""
        if lv["groups"]:
            flag = "  <--"
            bad += 1
        print("  %3d  %4d  %4d  %5d  %7d  %7d  %2d  %11d  %6d%s"
              % (lv["n"], len(lv["rows"]), lv["maxr"], lv["drops"], lv["bubbles"],
                 lv["ncol"], lv["shots"], lv["groups"], lv["forced"], flag))
    print()
    print("  depth   %d..%d   (8 is the ceiling: 9 loads with 0 drops of headroom)"
          % (min(len(l["rows"]) for l in levels), max(len(l["rows"]) for l in levels)))
    print("  bubbles %d..%d   colours %d..%d"
          % (min(l["bubbles"] for l in levels), max(l["bubbles"] for l in levels),
             min(l["ncol"] for l in levels), max(l["ncol"] for l in levels)))
    print("  %d of %d levels arrive with a pre-made group of 3+" % (bad, len(levels)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
