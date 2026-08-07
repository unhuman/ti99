"""Render the three flags as the VDP will, next to the arcade reference."""
from PIL import Image
import re
src = open("../src/tiles.bas").read()
def grab(name):
    m = re.search(r"^%s:\n(?:\t'.*\n)*((?:\tDATA BYTE .*\n)+)" % name, src, re.M)
    rows = m.group(1).strip("\n").split("\n")
    return [[v.strip() for v in ln.split(None, 2)[2].split(",")] for ln in rows]
pat = [[int(v[1:], 16) for v in r] for r in grab("ovlpat")]
col = grab("ovlcol")
PAL = {0x1:(0,0,0), 0x7:(33,200,222), 0x9:(255,110,90), 0xA:(222,151,71), 0xF:(255,255,255)}
S = 14
names = ["F (normal)", "S (double)", "L (lucky)"]
out = Image.new("RGB", (16*S*3, 16*S), PAL[0xA])
px = out.load()
for f in range(3):
    for q in range(4):
        idx = f*4 + q
        cr, cc = divmod(q, 2)
        for ly in range(8):
            cv = col[idx][ly]
            fg = PAL[int(cv[1], 16)]
            bg = PAL[int(cv[2], 16)]
            for lx in range(8):
                on = pat[idx][ly] & (0x80 >> lx)
                X = (f*16 + cc*8 + lx)*S
                Y = (cr*8 + ly)*S
                c = fg if on else bg
                for yy in range(Y, Y+S):
                    for xx in range(X, X+S):
                        px[xx, yy] = c
out.save("flag-new.png")
print("wrote flag-new.png:", ", ".join(names))
