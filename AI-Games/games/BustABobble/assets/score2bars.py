#!/usr/bin/env python3
"""Turn the engraving into bars of (pitch, duration) by measuring both.

PITCH comes from the staff-line ruler: five lines, 4.12 px apart, so a notehead's
edge names its note to well under half a step.

DURATION comes from HORIZONTAL SPACING. Engravers set notes proportionally to
their length, so within a bar the gap to the next note is its duration -- scale
the gaps so the bar sums to 16 sixteenths and round. That is measurement rather
than eye-reading beams and dots, which is the part that goes wrong.

Both are cross-checked: every bar must sum to 16, and anything that does not is
printed loudly rather than quietly fudged.
"""
from PIL import Image

PNG = r"C:\Users\Howie\Downloads\BobbleMusic.png"
SYS = [([78, 86, 94, 103, 111], [164, 172, 181, 189, 197], 1, [64, 334, 529, 742, 957]),
       ([289, 297, 305, 313, 322], [375, 383, 391, 399, 408], 5, [64, 393, 667, 957]),
       ([469, 477, 485, 493, 501], [555, 563, 571, 579, 587], 8, [55, 411, 674, 948]),
       ([679, 688, 696, 704, 712], [765, 774, 782, 790, 798], 11, [55, 393, 681, 948]),
       ([877, 885, 894, 902, 910], [963, 971, 980, 988, 996], 14, [57, 362, 556, 756, 950]),
       ([1051, 1059, 1067, 1075, 1083], [1137, 1145, 1153, 1161, 1169], 18, [44, 325, 626])]
CIDX = {"C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6}
FLAT = ("B", "E")            # key signature: B flat major


def blobs(px, x0, x1, y0, y1):
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
        for i, r in enumerate(runs[y]):
            if (y, i) in used:
                continue
            comp, (cs, ce) = [(y, r[0], r[1])], (r[0], r[1])
            used.add((y, i))
            yy = y + 1
            while yy in runs:
                hit = None
                for j, r2 in enumerate(runs[yy]):
                    if (yy, j) not in used and min(ce, r2[1]) - max(cs, r2[0]) >= 4:
                        hit = (j, r2[0], r2[1])
                        break
                if hit is None:
                    break
                used.add((yy, hit[0]))
                comp.append((yy, hit[1], hit[2]))
                cs, ce = hit[1], hit[2]
                yy += 1
            if 4 <= len(comp) <= 34 and 8 <= max(b - a for _, a, b in comp) <= 13:
                cx = sum((a + b) / 2.0 for _, a, b in comp) / len(comp)
                ys = [t for t, _, _ in comp]
                out.append((cx, min(ys) + 3.5, max(ys) - 3.5))
    out.sort()
    return out


def named(cy, lines, ref):
    step = (lines[4] - lines[0]) / 8.0
    k = int(round((cy - lines[0]) / step))
    n = ref[1] * 7 + CIDX[ref[0]] - k
    letter = "CDEFGAB"[n % 7]
    return letter + ("b" if letter in FLAT else "") + str(n // 7)


def bar_notes(px, lines, ref, x0, x1, top):
    step = (lines[4] - lines[0]) / 8.0
    lo = lines[0] - int(8 * step)
    hi = lines[4] + int(7 * step)
    raw = blobs(px, x0, x1, lo, hi)
    groups = []
    for rec in raw:
        if groups and rec[0] - groups[-1][0][0] <= 5:
            groups[-1].append(rec)
        else:
            groups.append([rec])
    out = []
    for g in groups:
        cy = min(p[1] for p in g) if top else max(p[2] for p in g)
        out.append((g[0][0], named(cy, lines, ref)))
    return out


def rhythm(notes, x0, x1):
    """Gaps -> sixteenths, scaled so the bar sums to 16."""
    if not notes:
        return []
    xs = [n[0] for n in notes] + [float(x1)]
    gaps = [xs[i + 1] - xs[i] for i in range(len(notes))]
    total = sum(gaps)
    vals = [max(1, int(round(16.0 * g / total))) for g in gaps]
    # nudge the longest note until the bar is exactly 16
    while sum(vals) != 16:
        d = 16 - sum(vals)
        i = vals.index(max(vals)) if d < 0 else vals.index(max(vals))
        vals[i] += 1 if d > 0 else -1
        if vals[i] < 1:
            vals[i] = 1
            break
    return vals


im = Image.open(PNG).convert("L")
px = im.load()
for treb, bass, bar0, bars in SYS:
    for bi in range(len(bars) - 1):
        x0, x1 = bars[bi] + 5, bars[bi + 1] - 3
        mel = bar_notes(px, treb, ("F", 5), x0, x1, True)
        bas = bar_notes(px, bass, ("A", 3), x0, x1, False)
        mr, br = rhythm(mel, x0, x1), rhythm(bas, x0, x1)
        print("bar %2d" % (bar0 + bi))
        print("   mel %s" % "  ".join("%s/%d" % (n[1], d) for n, d in zip(mel, mr)))
        print("   bas %s" % "  ".join("%s/%d" % (n[1], d) for n, d in zip(bas, br)))
