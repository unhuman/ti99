"""Kelly's x per frame, so a run's DIRECTION is a fact and not an assumption."""
import glob
from PIL import Image


def cls(c):
    r, g, b = c
    if b > 110 and b > r + 55 and b > g + 35:
        return "B"
    if r < 80 and g < 80 and b < 80:
        return "K"
    if r > 165 and g > 125 and b < 140 and r > g + 20:
        return "S"
    return "."


def locate(px):
    for y in range(60, 300):
        x = 24
        while x < 460:
            if cls(px[x, y]) == "K":
                w = 0
                while x + w < 460 and cls(px[x + w, y]) == "K":
                    w += 1
                if 8 <= w <= 14:
                    for yy in range(y + 5, y + 16):
                        if cls(px[x + w // 2, yy]) == "S":
                            return x + w // 2, y
                x += max(w, 1)
            else:
                x += 1
    return None


prev = None
runs = []
for f in sorted(glob.glob("dk/*.png")):
    px = Image.open(f).convert("RGB").load()
    k = locate(px)
    if not k:
        prev = None
        continue
    if prev is not None and abs(k[0] - prev[1]) < 14:
        runs.append((f, k[0], k[1], k[0] - prev[1]))
    prev = (f, k[0])
# the longest monotone stretches
for want, label in ((1, "RIGHT"), (-1, "LEFT")):
    best, cur = [], []
    for f, x, y, d in runs:
        if d * want > 0:
            cur.append((f, x, y))
        else:
            if len(cur) > len(best):
                best = cur
            cur = []
    if len(cur) > len(best):
        best = cur
    print("longest %s run: %d frames, %s .. %s" %
          (label, len(best), best[0][0] if best else "-",
           best[-1][0] if best else "-"))
    if best:
        print("   x %d -> %d, hat top y %d" % (best[0][1], best[-1][1], best[0][2]))
        print("   sample frames:", [b[0] for b in best[:3]], "...",
              [b[0] for b in best[-2:]])
