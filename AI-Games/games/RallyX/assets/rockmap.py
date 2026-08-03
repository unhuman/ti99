"""Render maze 1 with the first N rocks marked, to check placement offline
rather than hunting for one in a 12x12 window of a 34x58 maze."""
from PIL import Image, ImageDraw
import re, os

rows = [l.rstrip("\n") for l in open("maze1.txt").readlines()[:56]]
src = open("../src/rocks.bas").read()
m = re.search(r"^rock_data_1:\n((?:\tDATA BYTE .*\n)+)", src, re.M)
rocks = [tuple(int(v) for v in ln.split(None, 2)[2].split(","))
         for ln in m.group(1).strip("\n").split("\n")]
it = open("../src/items.bas").read().split("\n")
cur, items = None, {}
for line in it:
    t = line.strip()
    if t.endswith(":"):
        cur = items.setdefault(t[:-1], [])
    elif t.startswith("DATA BYTE") and cur is not None:
        cur.append(tuple(int(v) for v in t.split(None, 2)[2].split(",")))
flags = items["flag_data_1"]
start = items["start_data_1"][0]

S = 9
im = Image.new("RGB", (34 * S, 58 * S), (222, 151, 71))
d = ImageDraw.Draw(im)
for r in range(58):
    for c in range(34):
        solid = (r == 0 or r == 57 or c == 0 or c == 33
                 or rows[r - 1][c - 1] == "#")
        if solid:
            d.rectangle([c * S, r * S, c * S + S - 1, r * S + S - 1],
                        fill=(33, 200, 66))
for (r, c) in flags:
    d.rectangle([c*S+1, r*S+1, c*S+S-2, r*S+S-2], fill=(255, 255, 255))
d.rectangle([start[1]*S+1, start[0]*S+1, start[1]*S+S-2, start[0]*S+S-2],
            fill=(60, 60, 255))
for i, (r, c) in enumerate(rocks):
    col = (170, 170, 170) if i >= 5 else (255, 0, 0)   # first 5 = round 6
    d.ellipse([c*S+1, r*S+1, c*S+S-2, r*S+S-2], fill=col)
    d.text((c*S+2, r*S), str(i + 1), fill=(0, 0, 0))
im.save("rock-map.png")
print("wrote rock-map.png -- red = first 5 (round 6), grey = later")
for i, (r, c) in enumerate(rocks[:6]):
    print("  rock %2d at (%d,%d)  manhattan from start %d"
          % (i + 1, r, c, abs(r - start[0]) + abs(c - start[1])))
