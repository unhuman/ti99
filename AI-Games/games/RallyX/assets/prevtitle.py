"""Render the generated logo exactly as the VDP will draw it."""
from PIL import Image
import re
src = open("../src/title.bas").read()
def grab(name):
    m = re.search(r"^%s:\n(?:\t'.*\n)*((?:\tDATA BYTE .*\n)+)" % name, src, re.M)
    return [ln.split(None, 2)[2].split(",") for ln in m.group(1).strip("\n").split("\n")]
pat = [[int(v.strip()[1:], 16) for v in r] for r in grab("title_pat")]
col = [[int(v.strip()[1:], 16) for v in r] for r in grab("title_col")]
mp  = [[int(v.strip()) for v in r] for r in grab("title_map")]
PAL = {0x1:(0,0,0), 0x4:(33,71,222), 0x9:(255,110,90), 0xA:(222,151,71), 0xF:(255,255,255)}
S = 9
rows, cols = len(mp), len(mp[0])
im = Image.new("RGB", (cols*8*S, rows*8*S), PAL[0xA])
px = im.load()
for cr in range(rows):
    for cc in range(cols):
        idx = mp[cr][cc] - 144
        for ly in range(8):
            fg = PAL[(col[idx][ly] >> 4) & 0xF]
            bg = PAL[col[idx][ly] & 0xF]
            for lx in range(8):
                c = fg if pat[idx][ly] & (0x80 >> lx) else bg
                X, Y = (cc*8+lx)*S, (cr*8+ly)*S
                for yy in range(Y, Y+S):
                    for xx in range(X, X+S):
                        px[xx, yy] = c
im.save("title-big.png")
print("wrote title-big.png  (%dx%d chars)" % (cols, rows))
