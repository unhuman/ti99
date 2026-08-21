#!/usr/bin/env python3
"""Find noteheads on an engraved score and report their measured pitch.

Pitch is the part eyes get wrong and pixels get right: the five staff lines are a
ruler with 4.1-pixel steps, so a notehead's centre names its own note. Rhythm is
NOT read here -- beams, dots and rests are read by eye off the crops, where they
are large and unambiguous.

A notehead is an ink blob 7-14 px wide and 4-10 px tall. Stems are 1-2 px wide,
beams are 20+, staff lines span the page, so all three fall out on width alone.
"""
import sys
from PIL import Image

PNG = r"C:\Users\Howie\Downloads\BobbleMusic.png"

# staff line groups measured from row ink density (see the session notes)
SYSTEMS = [
    # (treble lines, bass lines, first bar number, x range)
    ([78, 86, 94, 103, 111], [164, 172, 181, 189, 197], 1),
    ([289, 297, 305, 313, 322], [375, 383, 391, 399, 408], 5),
    ([469, 477, 485, 493, 501], [555, 563, 571, 579, 587], 8),
    ([679, 688, 696, 704, 712], [765, 774, 782, 790, 798], 11),
    ([877, 885, 894, 902, 910], [963, 971, 980, 988, 996], 14),
    ([1051, 1059, 1067, 1075, 1083], [1137, 1145, 1153, 1161, 1169], 18),
]

TREBLE = "FEDCBAGFEDCBAG"      # from the top line F5 downward, one letter a step
BASS = "AGFEDCBAGFEDCB"        # from the top line A3 downward


def blobs(px, w, x0, x1, y0, y1):
    """Ink blobs in a window, as (cx, cy, width, height)."""
    runs = {}
    for y in range(y0, y1):
        x = x0
        while x < x1:
            if px[x, y] < 160:
                s = x
                while x < x1 and px[x, y] < 160:
                    x += 1
                if 6 <= x - s <= 15:
                    runs.setdefault(y, []).append((s, x))
            else:
                x += 1
    # group vertically adjacent runs that overlap horizontally
    out, used = [], set()
    for y in sorted(runs):
        for i, (s, e) in enumerate(runs[y]):
            if (y, i) in used:
                continue
            comp = [(y, s, e)]
            used.add((y, i))
            yy = y + 1
            while yy in runs:
                hit = None
                for j, (s2, e2) in enumerate(runs[yy]):
                    if (yy, j) in used:
                        continue
                    if min(e, e2) - max(s, s2) >= 4:
                        hit = (j, s2, e2)
                        break
                if hit is None:
                    break
                used.add((yy, hit[0]))
                comp.append((yy, hit[1], hit[2]))
                s, e = hit[1], hit[2]
                yy += 1
            hgt = len(comp)
            if 4 <= hgt <= 11:
                cx = sum((a + b) / 2.0 for _, a, b in comp) / hgt
                cy = sum(t for t, _, _ in comp) / float(hgt) + 0.5
                wid = max(b - a for _, a, b in comp)
                out.append((cx, cy, wid, hgt))
    return out


def pitch(cy, lines, names, top_octave):
    step = (lines[4] - lines[0]) / 8.0          # half a line gap = one diatonic step
    k = (cy - lines[0]) / step                  # 0 at the top line, + downward
    k = int(round(k))
    letter = names[k % 7] if k >= 0 else names[(k % 7 + 7) % 7]
    # octave: count how many letter-C boundaries we cross from the reference
    idx = k
    return letter, idx


def main():
    im = Image.open(PNG).convert("L")
    w, h = im.size
    px = im.load()
    which = sys.argv[1] if len(sys.argv) > 1 else "1"
    n = int(which) - 1
    treb, bass, bar0 = SYSTEMS[n]
    print("system %d (from bar %d)" % (n + 1, bar0))
    for label, lines, names, ref in (("treble", treb, TREBLE, ("F", 5)),
                                     ("bass", bass, BASS, ("A", 3))):
        step = (lines[4] - lines[0]) / 8.0
        lo, hi = lines[0] - int(6 * step), lines[4] + int(6 * step)
        found = blobs(px, w, 40, w - 10, lo, hi)
        found.sort()
        print("  %s: %d heads   (step %.2f px, top line %s%d at y=%d)"
              % (label, len(found), step, ref[0], ref[1], lines[0]))
        # Diatonic numbering from C: C=0 D=1 E=2 F=3 G=4 A=5 B=6, number =
        # octave*7 + that. Octaves turn over at C, which is what the first
        # attempt got wrong (it rolled at A and produced B6s in a bass staff).
        CIDX = {"C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6}
        refn = ref[1] * 7 + CIDX[ref[0]]
        out = []
        for cx, cy, wd, ht in found:
            if not (8 <= wd <= 13):
                continue                      # clefs, dots, time signature
            k = int(round((cy - lines[0]) / step))
            n = refn - k
            out.append("%3d:%s%d" % (int(cx), "CDEFGAB"[n % 7], n // 7))
        for i in range(0, len(out), 12):
            print("     " + " ".join(out[i:i + 12]))


if __name__ == "__main__":
    main()
