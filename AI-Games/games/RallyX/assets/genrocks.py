#!/usr/bin/env python3
"""Bake per-maze ROCK lists into src/rocks.bas.

Rocks are the arcade's late-game pressure: static, lethal, and there are more
of them every round. Round R places the first (R-1) rocks of its maze's list,
so round 1 has none (the arcade's level-1 rip shows none either) and the
count keeps climbing long after every other difficulty dial has maxed out.

THE HARD CONSTRAINT IS REACHABILITY. A rock is lethal, not solid, but the
player still cannot drive through one -- so a rock dropped in a one-wide
corridor can cut a flag off from the start and make the round unwinnable.
Because round R uses a PREFIX of the list, it is not enough for the full set
to be safe: EVERY prefix has to be. The list is therefore built one rock at a
time and each candidate is only accepted if all ten flags are still reachable
from the start with it in place -- which makes every prefix safe by
construction.

Placement is farthest-point sampling so the rocks spread over the maze
instead of clumping, and the first ones to appear (the low rounds) are the
ones furthest from everything else.

Excluded outright: flag cells, the player start and its surroundings, and the
enemy spawn cells.

Run from assets/:  C:\\cygwin64\\bin\\python3.9.exe genrocks.py
"""
import os
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
COLS, ROWS = 34, 58                 # bordered logical
MAZES = (1, 2, 3, 4)
MAXROCK = 16                        # ceiling; the real cap is whatever the
                                    # tightest maze can take safely
START_CLEAR = 5                     # keep rocks this far from the start cell


def load(lvl):
    f = os.path.join(HERE, "maze%d.txt" % lvl)
    rows = [l.rstrip("\n") for l in open(f).readlines()[:56]]
    assert len(rows) == 56 and all(len(r) == 32 for r in rows), \
        "maze%d.txt must be 56 rows x 32 cols" % lvl
    return rows


def road_set(rows):
    """Bordered road cells -- the border ring is always tree."""
    road = set()
    for r in range(1, ROWS - 1):
        for c in range(1, COLS - 1):
            if rows[r - 1][c - 1] != "#":
                road.add((r, c))
    return road


def parse_items():
    """Read back what genmaps4.py emitted, so the two can never disagree."""
    path = os.path.join(HERE, "..", "src", "items.bas")
    text = open(path).read().split("\n")
    out, cur, label = {}, None, None
    for line in text:
        line = line.strip()
        if line.endswith(":"):
            label = line[:-1]
            cur = out.setdefault(label, [])
        elif line.startswith("DATA BYTE") and cur is not None:
            r, c = [int(v) for v in line.split(None, 2)[2].split(",")]
            cur.append((r, c))
    return out


def reachable(road, rocks, start):
    seen, q = {start}, deque([start])
    while q:
        r, c = q.popleft()
        for nr, nc in ((r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)):
            if (nr, nc) in road and (nr, nc) not in rocks and (nr, nc) not in seen:
                seen.add((nr, nc))
                q.append((nr, nc))
    return seen


def pick_rocks(road, flags, start, spawns):
    banned = set(flags) | set(spawns) | {start}
    # keep the opening clear so the player is not boxed in at spawn
    for r, c in list(road):
        if abs(r - start[0]) + abs(c - start[1]) < START_CLEAR:
            banned.add((r, c))
    # a rock must not sit next to a flag either -- reaching the flag means
    # driving into that cell, and a lethal neighbour makes it a coin flip
    for fr, fc in flags:
        for d in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            banned.add((fr + d[0], fc + d[1]))

    cand = sorted(road - banned)
    chosen = []
    # ENEMY SPAWNS ARE IN THE PROOF TOO, not just the flags. The cars treat
    # rocks as walls, so a rock that seals a spawn into a pocket would leave
    # that car circling a closet for the whole round. Flags being reachable
    # does not imply the spawns are.
    must_reach = set(flags) | set(spawns)
    # SEED AT THE MIDDLE OF THE MAZE, and spread relative to the other ROCKS
    # only. Including the start in the spread reference looked reasonable and
    # was quite wrong: farthest-point sampling then makes rock #1 the cell
    # furthest from where the player starts, so the early rounds -- the ones
    # with one or two rocks -- put them where nobody ever drives. Seeding at
    # the centre and spreading rock-to-rock gives an even covering of the
    # whole maze at EVERY prefix length, which is what "one more rock each
    # round" is supposed to feel like.
    cy, cx = ROWS // 2, COLS // 2
    while len(chosen) < MAXROCK:
        # bestd starts UNSET, not -1: the first-pick metric is a NEGATED
        # distance, so with bestd = -1 only a candidate within one cell of the
        # maze centre could ever win. Maze 3's centre is a wall, so nothing
        # qualified, the loop bailed on the first iteration and that maze
        # silently got zero rocks.
        best, bestd = None, None
        for cell in cand:
            if chosen:
                d = min(abs(cell[0] - a[0]) + abs(cell[1] - a[1]) for a in chosen)
            else:
                # first pick: nearest the centre, so negate the distance
                d = -(abs(cell[0] - cy) + abs(cell[1] - cx))
            if bestd is None or d > bestd:
                best, bestd = cell, d
        if best is None:
            break
        cand.remove(best)
        trial = set(chosen) | {best}
        if must_reach <= reachable(road, trial, start):
            chosen.append(best)
        if not cand:
            break
    # ORDER BY DISTANCE FROM THE START, nearest first. Farthest-point
    # sampling picks good POSITIONS but a terrible ORDER: after the centre
    # seed it jumps straight to the maze corners, so rounds 2-5 -- one to
    # four rocks -- would put them where nobody drives.
    #
    # Reordering is free because reachability is MONOTONE: removing a rock
    # can only open paths, so if the full set leaves every flag reachable
    # then so does every subset, in any order. The incremental check above
    # is what guarantees the full set; the prefixes come along for nothing.
    chosen.sort(key=lambda rc: abs(rc[0] - start[0]) + abs(rc[1] - start[1]))
    return chosen


lines = ["\t' GENERATED by assets/genrocks.py -- do not hand-edit.",
         "\t' Per-maze rock cells, bordered (row,col), ORDERED: round R uses",
         "\t' the first (R-1). Every PREFIX is verified to leave all ten flags",
         "\t' reachable from the start, so no round can be made unwinnable.",
         ""]

items = parse_items()
counts = []
for lvl in MAZES:
    rows = load(lvl)
    road = road_set(rows)
    flags = items["flag_data_%d" % lvl]
    start = items["start_data_%d" % lvl][0]
    spawns = items["espawn_data_%d" % lvl]
    rocks = pick_rocks(road, flags, start, spawns)
    counts.append(len(rocks))

    # Paranoia: re-verify every prefix independently, AFTER the reorder.
    # Monotonicity says checking the full set is enough, but this is cheap
    # and it is the property the game actually depends on.
    need = set(flags) | set(spawns)
    for k in range(len(rocks) + 1):
        assert need <= reachable(road, set(rocks[:k]), start), \
            "maze %d prefix %d strands a flag or a spawn" % (lvl, k)

    lines.append("rock_data_%d:" % lvl)
    for r, c in rocks:
        lines.append("\tDATA BYTE %d,%d" % (r, c))
    lines.append("")
    print("maze %d: %d rocks, all %d prefixes reachability-checked"
          % (lvl, len(rocks), len(rocks) + 1))

cap = min(counts)
lines.insert(4, "\t' MAXROCK must not exceed %d -- the tightest maze here." % cap)
lines.insert(5, "")
open(os.path.join(HERE, "..", "src", "rocks.bas"), "w").write("\n".join(lines) + "\n")
print("\nwrote src/rocks.bas -- counts %s, so MAXROCK caps at %d" % (counts, cap))
