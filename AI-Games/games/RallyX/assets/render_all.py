from PIL import Image
CELL = 6
for lvl in (1, 2, 3, 4):
    rows = [l.rstrip("\n") for l in open("maze%d.txt" % lvl).readlines()[:56]]
    im = Image.new("RGB", (32*CELL, 56*CELL), (222, 151, 71))
    px = im.load()
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch == "#":
                for y in range(r*CELL, r*CELL+CELL):
                    for x in range(c*CELL, c*CELL+CELL):
                        px[x, y] = (40, 160, 40)
    im.save("maze%d-render.png" % lvl)
    print("maze%d-render.png" % lvl)
