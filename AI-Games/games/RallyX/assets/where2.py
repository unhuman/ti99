import re
src = open("../src/rocks.bas").read()
it = open("../src/items.bas").read().split("\n")
cur, items = None, {}
for line in it:
    t = line.strip()
    if t.endswith(":"):
        cur = items.setdefault(t[:-1], [])
    elif t.startswith("DATA BYTE") and cur is not None:
        cur.append(tuple(int(v) for v in t.split(None, 2)[2].split(",")))
# round 6 -> mz = (6-1) AND 3 = 1 -> maze 2
m = re.search(r"^rock_data_2:\n((?:\tDATA BYTE .*\n)+)", src, re.M)
rocks = [tuple(int(v) for v in ln.split(None, 2)[2].split(","))
         for ln in m.group(1).strip("\n").split("\n")]
start = items["start_data_2"][0]
print("maze 2 start (row,col) =", start)
for i, (r, c) in enumerate(rocks[:5]):
    print("  rock %d at (%d,%d):  %+d rows, %+d cols from start"
          % (i + 1, r, c, r - start[0], c - start[1]))
