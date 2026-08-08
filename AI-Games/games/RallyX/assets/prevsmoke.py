"""Render the shaded smoke puff exactly as the VDP will draw it."""
from PIL import Image
import re
src = open("../src/tiles.bas").read()
m = re.search(r"^ovlpat:\n(?:\t'.*\n)*((?:\tDATA BYTE .*\n)+)", src, re.M)
pat = [[int(v.strip()[1:], 16) for v in ln.split(None, 2)[2].split(",")]
       for ln in m.group(1).strip("\n").split("\n")]
m = re.search(r"^ovlcol:\n((?:\t.*\n)+?)(?=^[a-z_]+:)", src, re.M)
col = [[int(v.strip()[1:], 16) for v in ln.split(None, 2)[2].split(",")]
       for ln in m.group(1).strip("\n").split("\n") if "DATA BYTE" in ln]
PAL = {0x1: (0,0,0), 0xA: (222,151,71), 0xE: (204,204,204), 0xF: (255,255,255)}
S = 14
im = Image.new("RGB", (16*S, 16*S), PAL[0xA]); px = im.load()
for q in range(4):                       # smoke = chars 12..15
    idx = 12 + q
    cr, cc = divmod(q, 2)
    for ly in range(8):
        fg = PAL[(col[idx][ly] >> 4) & 0xF]
        bg = PAL[col[idx][ly] & 0xF]
        for lx in range(8):
            c = fg if pat[idx][ly] & (0x80 >> lx) else bg
            X, Y = (cc*8+lx)*S, (cr*8+ly)*S
            for yy in range(Y, Y+S):
                for xx in range(X, X+S):
                    px[xx, yy] = c
im.save("smoke-preview.png")
print("wrote smoke-preview.png")
