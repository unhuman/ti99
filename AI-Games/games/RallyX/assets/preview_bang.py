# Paint the generated burst so it can be checked before it goes near the ROM.
from PIL import Image
import re
src = open("../src/bang.bas").read()
def grab(name):
    m = re.search(r"^%s:\n((?:\tDATA BYTE .*\n)+)" % name, src, re.M)
    return [[int(v[1:], 16) for v in ln.split()[2].split(",")]
            for ln in m.group(1).strip("\n").split("\n")]
pat, col = grab("bang_pat"), grab("bang_col")
PAL = {0x0: None, 0x1: (0,0,0), 0xA: (222,151,71), 0xB: (255,255,120)}
S = 12
im = Image.new("RGB", (32*S, 24*S), (222,151,71))
px = im.load()
for idx in range(len(pat)):
    cr, cc = divmod(idx, 4)
    for ly in range(8):
        fg = PAL[(col[idx][ly] >> 4) & 0xF]
        bg = PAL[col[idx][ly] & 0xF]
        for lx in range(8):
            on = pat[idx][ly] & (0x80 >> lx)
            c = fg if on else bg
            if c is None:
                continue
            X, Y = (cc*8+lx)*S, (cr*8+ly)*S
            for yy in range(Y, Y+S):
                for xx in range(X, X+S):
                    px[xx, yy] = c
im.save("bang-preview.png")
print("wrote bang-preview.png")
