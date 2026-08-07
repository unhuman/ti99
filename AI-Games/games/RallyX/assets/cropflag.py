from PIL import Image
from collections import Counter
im = Image.open("Rally-X-Level1.png").convert("RGB")
px = im.load()
PITCH = 24
x0o, y0o = 89, 112
found = []
for r in range(56):
    for c in range(32):
        x0, y0 = x0o + c*PITCH, y0o + r*PITCH
        has = Counter()
        for yy in range(y0, y0+PITCH):
            for xx in range(x0, x0+PITCH):
                has[px[xx, yy]] += 1
        if has[(255,255,0)] >= 10:
            found.append((r, c, has[(222,0,0)] >= 5, x0, y0))
print("flags found:", [(f[0], f[1], 'SPECIAL' if f[2] else '') for f in found])
# crop the first plain flag and the special one, 8x upscale, side by side
plain = next(f for f in found if not f[2])
spec  = next((f for f in found if f[2]), plain)
S = 12
out = Image.new("RGB", (PITCH*S*2 + 20, PITCH*S), (0,0,0))
for k, f in enumerate((plain, spec)):
    crop = im.crop((f[3], f[4], f[3]+PITCH, f[4]+PITCH)).resize((PITCH*S, PITCH*S), Image.NEAREST)
    out.paste(crop, (k*(PITCH*S+20), 0))
out.save("flag-ref.png")
print("wrote flag-ref.png  (left = normal flag, right = special)")
# dump the exact pixel grid of the plain flag so the shape can be copied, not eyeballed
x0, y0 = plain[3], plain[4]
print("\nplain flag %dx%d grid (Y=yellow, r=red, .=road/other):" % (PITCH, PITCH))
for yy in range(y0, y0+PITCH):
    line = ""
    for xx in range(x0, x0+PITCH):
        p = px[xx, yy]
        line += "Y" if p == (255,255,0) else ("r" if p == (222,0,0) else ".")
    print("  " + line)
