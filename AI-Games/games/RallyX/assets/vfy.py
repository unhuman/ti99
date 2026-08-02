# Every generated flag / start / spawn must sit on a ROAD cell.
import re, io
ROWS, COLS = 58, 34
def logical(lvl):
    rows = [l.rstrip("\n") for l in open("maze%d.txt" % lvl).readlines()[:56]]
    g = []
    for r in range(ROWS):
        line = []
        for c in range(COLS):
            if r in (0, ROWS-1) or c in (0, COLS-1): line.append("T")
            elif rows[r-1][c-1] == "#": line.append("W")
            else: line.append(".")
        g.append(line)
    return g
src = io.open("../src/items.bas", encoding="utf-8").read()
bad = 0
for lvl in (1,2,3,4):
    g = logical(lvl)
    for kind in ("flag_data", "start_data", "espawn_data"):
        m = re.search(r"^%s_%d:\n((?:\tDATA BYTE .*\n)+)" % (kind, lvl), src, re.M)
        for ln in m.group(1).strip("\n").split("\n"):
            r, c = [int(v) for v in ln.split()[2].split(",")]
            if g[r][c] != ".":
                print("  BAD %s L%d (%d,%d) = %s" % (kind, lvl, r, c, g[r][c])); bad += 1
    # start must have a clear run north
    m = re.search(r"^start_data_%d:\n\tDATA BYTE (\d+),(\d+)" % lvl, src, re.M)
    sr, sc = int(m.group(1)), int(m.group(2))
    if not (g[sr-1][sc] == "." and g[sr-2][sc] == "."):
        print("  L%d start has no clear run north" % lvl); bad += 1
print("all cells on road, starts clear" if bad == 0 else "%d PROBLEMS" % bad)
