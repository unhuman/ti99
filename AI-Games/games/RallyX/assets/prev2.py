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
im = Image.new("RGB", (16*S*2 + S*2, 16*S), (222,151,71))
px = im.load()
for f in range(2):                      # two animation frames, side by side
    for k in range(4):
        idx = f*4 + k
        cr, cc = divmod(k, 2)
        for ly in range(8):
            fg = PAL[(col[idx][ly] >> 4) & 0xF]
            bg = PAL[col[idx][ly] & 0xF]
            for lx in range(8):
                c = fg if (pat[idx][ly] & (0x80 >> lx)) else bg
                if c is None: continue
                X = (cc*8+lx)*S + f*(16*S + 2*S)
                Y = (cr*8+ly)*S
                for yy in range(Y, Y+S):
                    for xx in range(X, X+S):
                        px[xx, yy] = c
im.save("bang-preview.png")
print("wrote bang-preview.png (two 2x2 frames)")
