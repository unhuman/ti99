from PIL import Image
import re
src = open("../src/tiles.bas").read()
m = re.search(r"^rockpat:\n\t'.*\n((?:\tDATA BYTE .*\n)+)", src, re.M)
pat = [[int(v[1:], 16) for v in ln.split()[2].split(",")]
       for ln in m.group(1).strip("\n").split("\n")]
GREY, TAN = (203, 203, 203), (222, 151, 71)
S = 16
im = Image.new("RGB", (16 * S * 2, 16 * S), TAN)
px = im.load()
for idx in range(4):
    cr, cc = divmod(idx, 2)
    for ly in range(8):
        for lx in range(8):
            on = pat[idx][ly] & (0x80 >> lx)
            X, Y = (cc * 8 + lx) * S, (cr * 8 + ly) * S
            c = GREY if on else TAN
            for yy in range(Y, Y + S):
                for xx in range(X, X + S):
                    px[xx, yy] = c
# second copy on the green wall colour, to check it reads there too
for y in range(16 * S):
    for x in range(16 * S, 32 * S):
        px[x, y] = (33, 200, 66)
for idx in range(4):
    cr, cc = divmod(idx, 2)
    for ly in range(8):
        for lx in range(8):
            if pat[idx][ly] & (0x80 >> lx):
                X, Y = (cc * 8 + lx) * S + 16 * S, (cr * 8 + ly) * S
                for yy in range(Y, Y + S):
                    for xx in range(X, X + S):
                        px[xx, yy] = GREY
im.save("rock-preview.png")
print("wrote rock-preview.png")
