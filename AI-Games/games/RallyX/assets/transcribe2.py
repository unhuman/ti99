from PIL import Image
from collections import Counter

im = Image.open("Rally-X-Level1.png").convert("RGB")
px = im.load()

X0, Y0, PITCH, COLS, ROWS = 89, 112, 24, 32, 56

ROAD = (222, 151, 71)
WALLG = (71, 184, 0)

flags, specials, players, enemies = [], [], [], []
grid = []
for r in range(ROWS):
    row = ""
    for c in range(COLS):
        x0, y0 = X0 + c*PITCH, Y0 + r*PITCH
        # item detection over whole cell
        has = Counter()
        for yy in range(y0, y0+PITCH):
            for xx in range(x0, x0+PITCH):
                has[px[xx, yy]] += 1
        if has[(255, 255, 0)] >= 10:
            if has[(222, 0, 0)] >= 5:
                specials.append((r, c))
            else:
                flags.append((r, c))
        if has[(33, 71, 222)] >= 10:
            players.append((r, c))
        if has[(104, 0, 0)] >= 60:
            enemies.append((r, c))
        # base classify from inner window
        inner = Counter()
        for yy in range(y0+8, y0+16):
            for xx in range(x0+8, x0+16):
                inner[px[xx, yy]] += 1
        road = inner[ROAD] + inner[(208, 121, 44)]
        wall = inner[WALLG] + inner[(184, 71, 0)]
        if road >= wall and road > 0:
            row += "."
        elif wall > 0:
            row += "#"
        else:
            # items sit on road; trees shouldn't appear inside
            row += "."
    grid.append(row)

print("MAZE (base):")
for i, g in enumerate(grid):
    print("%2d %s" % (i, g))
print("flags:", flags)
print("special:", specials)
print("player:", players)
print("enemies:", enemies)

# sanity: wall/road counts
walls = sum(g.count("#") for g in grid)
print("wall cells:", walls, "road cells:", 32*56-walls)

with open("maze1.txt", "w") as f:
    for g in grid:
        f.write(g + "\n")
    f.write("flags %r\n" % flags)
    f.write("special %r\n" % specials)
    f.write("player %r\n" % players)
    f.write("enemies %r\n" % enemies)
