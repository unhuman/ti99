#!/usr/bin/env python3
"""Bake all four mazes into per-bank includes, plus their item lists.

Companion to genmap.py, which still owns the maze-independent ART
(tiles.bas: wall quadrants, flag/smoke overlays, radar tables). This script
owns everything that is PER MAZE:

  src/map2_1.bas .. map2_4.bas   68x116 CHAR map each (7,888 B), one per
                                 TI bank -- an 8 K bank holds one with room
                                 to spare.
  src/items.bas                  per-maze flag cells, player start and the
                                 four enemy spawns.

THE LOGICAL MAP IS GONE. map2 already encodes cell type in its top-left
quadrant -- road cells are plain ROAD in all four quadrants, trees are TREE,
walls are edged variants 96..111 -- so the same ">= ROADCH" test works
straight off map2, and `probe` reads that. That saves 1,972 bytes per maze
and is what lets four of them fit without pushing the TI fixed area past
its 24,336-byte cap.

Flag placement: the arcade rips only show 4-7 flags on maps 2-4 (some are
obscured), and no player start at all, so those cannot be transcribed. The
TEN POSITIONS FROM MAP 1 are used as a distribution template and each is
snapped to the nearest road cell in the target maze -- the arcade's spread
is preserved without inventing a layout.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
WALL0, TREE, ROAD = 96, 112, 113
COLS, ROWS = 34, 58                 # bordered logical
MAZES = (1, 2, 3, 4)

# Map 1's flag cells (bordered coords), used as the spread template.
TEMPLATE = [(13, 13), (18, 23), (23, 18), (28, 8), (36, 14),
            (39, 7), (39, 29), (46, 4), (8, 28), (54, 22)]


def load(lvl):
    f = os.path.join(HERE, "maze%d.txt" % lvl)
    rows = [l.rstrip("\n") for l in open(f).readlines()[:56]]
    assert len(rows) == 56 and all(len(r) == 32 for r in rows), \
        "maze%d.txt must be 56 rows x 32 cols" % lvl
    return rows


def build_logical(rows):
    g = []
    for r in range(ROWS):
        line = []
        for c in range(COLS):
            if r == 0 or r == ROWS - 1 or c == 0 or c == COLS - 1:
                line.append(TREE)
            elif rows[r - 1][c - 1] == "#":
                line.append(WALL0)
            else:
                line.append(ROAD)
        g.append(line)
    return g


def build_map2(logical):
    def solid(r, c):
        if r <= 0 or r >= ROWS - 1 or c <= 0 or c >= COLS - 1:
            return True
        return logical[r][c] != ROAD

    m = []
    for r in range(ROWS):
        top, bot = [], []
        for c in range(COLS):
            cell = logical[r][c]
            if cell == ROAD:
                q = [ROAD] * 4
            elif cell == TREE:
                q = [TREE] * 4
            else:
                n = 0 if solid(r - 1, c) else 1
                s = 0 if solid(r + 1, c) else 1
                w = 0 if solid(r, c - 1) else 2
                e = 0 if solid(r, c + 1) else 2
                q = [96 + n + w, 100 + n + e, 104 + s + w, 108 + s + e]
            top += q[0:2]
            bot += q[2:4]
        m.append(top)
        m.append(bot)
    return m


def road(logical, r, c):
    return 0 <= r < ROWS and 0 <= c < COLS and logical[r][c] == ROAD


def pick_flags(logical):
    """Snap each template position to the nearest free road cell."""
    used, out = set(), []
    for tr, tc in TEMPLATE:
        best, bestd = None, 10 ** 9
        for r in range(1, ROWS - 1):
            for c in range(1, COLS - 1):
                if not road(logical, r, c) or (r, c) in used:
                    continue
                d = (r - tr) ** 2 + (c - tc) ** 2
                if d < bestd:
                    best, bestd = (r, c), d
        assert best, "no road cell available for template %s" % ((tr, tc),)
        used.add(best)
        out.append(best)
    return out


# Maze 1's start was found by hand from the arcade reference shot (player
# facing up a clear corridor, chasers lined up in a row behind) and signed
# off, so it is pinned rather than re-derived.
START_OVERRIDE = {
    1: ((35, 22), [(38, 19), (38, 22), (38, 25), (38, 23)]),
}


def pick_start(logical):
    """A start cell with a clear run NORTH and four spawn cells 3 rows south.

    Same shape as map 1's hand-found start: the player faces up an open
    corridor with the chasers lined up behind, each able to drive at him.
    """
    best = None
    for r in range(34, 48):
        for c in range(6, COLS - 6):
            if not (road(logical, r, c) and road(logical, r - 1, c)
                    and road(logical, r - 2, c)):
                continue
            sp = [sc for sc in range(c - 4, c + 5)
                  if road(logical, r + 3, sc) and road(logical, r + 2, sc)]
            if len(sp) < 4:
                continue
            # prefer spawns spread around the player's column
            sp.sort(key=lambda x: abs(x - c))
            cand = (r, c, sorted(sp[:4]))
            if best is None:
                best = cand
    assert best, "no viable start found"
    r, c, sp = best
    return (r, c), [(r + 3, x) for x in sp]


def data_bytes(vals, per=17):
    out = []
    for i in range(0, len(vals), per):
        out.append("\tDATA BYTE " + ",".join("$%02X" % v for v in vals[i:i + per]))
    return out


items = ["\t' GENERATED by assets/genmaps4.py -- do not hand-edit.",
         "\t' Per-maze item lists: 10 flag cells, player start, 4 enemy spawns.",
         "\t' All bordered (row,col) pairs.", ""]

for lvl in MAZES:
    rows = load(lvl)
    logical = build_logical(rows)
    m2 = build_map2(logical)

    out = ["\t' GENERATED by assets/genmaps4.py from assets/maze%d.txt." % lvl,
           "\t' CHAR map 116 rows x 68 cols, 2x2 chars per logical cell.",
           "\t' Cell TYPE is readable from the top-left quadrant, which is what",
           "\t' `probe` tests -- there is no separate logical map.",
           "map2_%d:" % lvl]
    for line in m2:
        out.extend(data_bytes(line))
    open(os.path.join(HERE, "..", "src", "map2_%d.bas" % lvl), "w").write(
        "\n".join(out) + "\n")

    flags = pick_flags(logical)
    if lvl in START_OVERRIDE:
        (sr, sc), spawns = START_OVERRIDE[lvl]
    else:
        (sr, sc), spawns = pick_start(logical)
    items.append("flag_data_%d:" % lvl)
    for r, c in flags:
        items.append("\tDATA BYTE %d,%d" % (r, c))
    items.append("start_data_%d:" % lvl)
    items.append("\tDATA BYTE %d,%d" % (sr, sc))
    items.append("espawn_data_%d:" % lvl)
    for r, c in spawns:
        items.append("\tDATA BYTE %d,%d" % (r, c))
    items.append("")

    print("maze %d: map2 %d bytes, start (%d,%d), spawns %s"
          % (lvl, len(m2) * len(m2[0]), sr, sc, spawns))

open(os.path.join(HERE, "..", "src", "items.bas"), "w").write("\n".join(items) + "\n")
print("wrote src/map2_1..4.bas and src/items.bas")
