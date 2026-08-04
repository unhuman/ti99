"""Render the shaded boulder on the road, and next to a car for scale."""
from PIL import Image
import re
src = open("../src/tiles.bas").read()
def grab(name):
    m = re.search(r"^%s:\n\t'.*\n((?:\tDATA BYTE .*\n)+)" % name, src, re.M)
    return [[int(v[1:], 16) for v in ln.split()[2].split(",")]
            for ln in m.group(1).strip("\n").split("\n")]
pat, col = grab("rockpat"), grab("rockcol")
PAL = {0x1: (0, 0, 0), 0xA: (222, 151, 71), 0xE: (203, 203, 203),
       0x2: (33, 200, 66)}
S = 14
im = Image.new("RGB", (16 * S * 2, 16 * S), PAL[0xA])
px = im.load()
for panel, bg in ((0, 0xA), (1, 0x2)):
    for y in range(16 * S):
        for x in range(16 * S):
            px[panel * 16 * S + x, y] = PAL[bg]
    for idx in range(4):
        cr, cc = divmod(idx, 2)
        for ly in range(8):
            fg = PAL[(col[idx][ly] >> 4) & 0xF]
            for lx in range(8):
                if pat[idx][ly] & (0x80 >> lx):
                    X = (cc * 8 + lx) * S + panel * 16 * S
                    Y = (cr * 8 + ly) * S
                    for yy in range(Y, Y + S):
                        for xx in range(X, X + S):
                            px[xx, yy] = fg
im.save("rock-preview2.png")
print("wrote rock-preview2.png (left: on road, right: on wall green)")
