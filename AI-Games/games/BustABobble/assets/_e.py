#!/usr/bin/env python3
"""Per-bar melody (top of each chord) and bass, measured off the engraving."""
from PIL import Image

PNG = r"C:\Users\Howie\Downloads\BobbleMusic.png"
SYS = [([78, 86, 94, 103, 111], [164, 172, 181, 189, 197], 1, [64, 334, 529, 742, 957]),
       ([289, 297, 305, 313, 322], [375, 383, 391, 399, 408], 5, [64, 393, 667, 957]),
       ([469, 477, 485, 493, 501], [555, 563, 571, 579, 587], 8, [55, 411, 674, 948]),
       ([679, 688, 696, 704, 712], [765, 774, 782, 790, 798], 11, [55, 393, 681, 948]),
       ([877, 885, 894, 902, 910], [963, 971, 980, 988, 996], 14, [57, 362, 556, 756, 950]),
       ([1051, 1059, 1067, 1075, 1083], [1137, 1145, 1153, 1161, 1169], 18, [44, 325, 626])]
CIDX = {"C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6}


def heads(px, x0, x1, y0, y1):
    runs = {}
    for y in range(y0, y1):
        x = x0
        while x < x1:
            if px[x, y] < 160:
                s = x
                while x < x1 and px[x, y] < 160:
                    x += 1
                if 6 <= x - s <= 15:
                    runs.setdefault(y, []).append([s, x])
            else:
                x += 1
    out, used = [], set()
    for y in sorted(runs):
        for i, (s, e) in enumerate(runs[y]):
            if (y, i) in used:
                continue
            comp = [(y, s, e)]
            used.add((y, i))
            yy, cs, ce = y + 1, s, e
            while yy in runs:
                hit = None
                for j, (s2, e2) in enumerate(runs[yy]):
                    if (yy, j) in used:
                        continue
                    if min(ce, e2) - max(cs, s2) >= 4:
                        hit = (j, s2, e2)
                        break
                if hit is None:
                    break
                used.add((yy, hit[0]))
                comp.append((yy, hit[1], hit[2]))
                cs, ce = hit[1], hit[2]
                yy += 1
            if 4 <= len(comp) <= 34:
                wid = max(b - a for _, a, b in comp)
                if 8 <= wid <= 13:
                    cx = sum((a + b) / 2.0 for _, a, b in comp) / len(comp)
                    ys = [t for t, _, _ in comp]
                    # A chord of stacked thirds is ONE blob: its top edge is the
                    # top note's top edge and its bottom edge the bottom note's,
                    # and a notehead is about 7 rows, so its centre is 3.5 in.
                    out.append((cx, min(ys) + 3.5, max(ys) - 3.5))
    return out


def name(cy, lines, ref):
    step = (lines[4] - lines[0]) / 8.0
    k = int(round((cy - lines[0]) / step))
    n = ref[1] * 7 + CIDX[ref[0]] - k
    return "CDEFGAB"[n % 7] + str(n // 7), n


im = Image.open(PNG).convert("L")
w, h = im.size
px = im.load()
for treb, bass, bar0, bars in SYS:
    for bi in range(len(bars) - 1):
        x0, x1 = bars[bi] + 4, bars[bi + 1] - 2
        step = (treb[4] - treb[0]) / 8.0
        tl = heads(px, x0, x1, treb[0] - int(7 * step), treb[4] + int(5 * step))
        bl = heads(px, x0, x1, bass[0] - int(5 * step), bass[4] + int(6 * step))
        # cluster by x: notes within 5 px are one chord
        def clus(lst, lines, ref, top):
            lst.sort()
            groups = []
            for rec in lst:
                if groups and rec[0] - groups[-1][0][0] <= 5:
                    groups[-1].append(rec)
                else:
                    groups.append([rec])
            out = []
            for g in groups:
                cy = min(p[1] for p in g) if top else max(p[2] for p in g)
                nm, _ = name(cy, lines, ref)
                out.append("%d:%s" % (int(g[0][0]), nm))
            return out
        mel = clus(tl, treb, ("F", 5), True)
        bas = clus(bl, bass, ("A", 3), False)
        print("bar %2d  mel: %s" % (bar0 + bi, " ".join(mel)))
        print("        bас: %s" % " ".join(bas))
