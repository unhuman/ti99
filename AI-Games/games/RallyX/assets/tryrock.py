"""Compare rock colour options side by side before committing to one."""
from PIL import Image
import re, math
src = open("../src/tiles.bas").read()
m = re.search(r"^rockpat:\n\t'.*\n((?:\tDATA BYTE .*\n)+)", src, re.M)
pat = [[int(v[1:], 16) for v in ln.split()[2].split(",")]
       for ln in m.group(1).strip("\n").split("\n")]
TAN, GREY, BLACK, WHITE = (222,151,71), (203,203,203), (0,0,0), (255,255,255)
# option -> per-row fg for rows 0..15
opts = [
    ("grey (now)",    [GREY]*16),
    ("solid black",   [BLACK]*16),
    ("grey cap 0-5",  [GREY]*6 + [BLACK]*10),
    ("grey cap 0-1",  [GREY]*2 + [BLACK]*14),
    ("white cap 0-1", [WHITE]*2 + [BLACK]*14),
]
S = 10
im = Image.new("RGB", (len(opts)*17*S, 17*S), TAN)
px = im.load()
for oi, (name, rows) in enumerate(opts):
    ox = oi*17*S
    for idx in range(4):
        cr, cc = divmod(idx, 2)
        for ly in range(8):
            y = cr*8 + ly
            for lx in range(8):
                if pat[idx][ly] & (0x80 >> lx):
                    X, Y = ox + (cc*8+lx)*S, y*S
                    for yy in range(Y, Y+S):
                        for xx in range(X, X+S):
                            px[xx, yy] = rows[y]
im.save("rock-options.png")
print("wrote rock-options.png:", ", ".join(n for n, _ in opts))
