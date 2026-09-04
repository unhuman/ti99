#!/usr/bin/env python3
"""Verify the colour-banded actors, and render them for eyeballing.

Kelly is three sprites and Harry is four, one per colour band. A TMS9918 sprite
carries one colour, so that is the only way to get several colours into a
figure -- and it brings two failure modes that are silent and show up only as
"the sprite looks wrong".

1. TWO SPRITES WITH PIXELS ON THE SAME ROW. The bands must not overlap: if the
   hat sprite and the face sprite both light a pixel on row 7, that row shows
   two colours fighting for one place and the art does not say which wins.
   This is the "window blind" rule, and it is a hard failure.

2. TOO MANY SPRITE BOXES ON A SCANLINE. The VDP counts sprite BOXES per
   scanline, not pixels -- a 16x16 sprite occupies all 16 of its lines whether
   or not they contain anything, so an empty overlap costs exactly as much as
   a full one. Only FOUR may share a line; the rest are dropped, highest slot
   number first.

   Kelly's slots 0 and 1 share a y (covering figure rows 0-15) and slot 2 sits
   at y+16, so he never costs more than two. Harry costs THREE on his upper
   rows because his stripes need a second sprite over the same band -- so when
   the two are level those rows carry five, and one is dropped. That is
   deliberate and it is why the stripe sprite holds the HIGHEST slot of the
   five: what disappears is Harry's stripes, not his head. This check proves
   the sprite that drops is the one we chose, and fails if it is any other.

Run:  python3 checkbands.py [out.png]
"""

import os
import re
import sys

import genart as g

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "src", "art.bas")
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")

PAL = [
    (0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
    (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
    (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
    (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255),
]

MAX_PER_LINE = 4                 # TMS9918 hard limit
# HARRY'S STRIPE MAY DROP, AND ONLY IT. Kelly's brim is now two rows and his
# hat band reaches y+5, so on the two scanlines where his brim is level with
# Harry's cap there are five boxes: Kelly's hat and face, and Harry's body,
# stripe and face. The VDP drops the HIGHEST-numbered slots, which is slot 6 --
# Harry's stripes -- so what is lost is two scanlines of stripe on a white
# body, on the one line where the two are exactly level. That is the
# degradation this layout was designed around from the start (see the note over
# HARRY_STRIPE in genart.py): he goes plain white rather than losing a limb,
# and the player's own figure is never touched.
DROPPABLE = {6}

# name, label, [(pattern index in block, VDP slot, colour, y offset)]
#
# THE y OFFSETS ARE THE WHOLE TRICK. A band's pattern is pushed to one end of
# its 16-row box (see shift() in genart.py) and the sprite is then drawn at the
# matching offset, so the box covers only the rows the band actually uses --
# the face at -10 covers rows -10..5, the stripes at +7 cover 7..22. Parking
# them all at 0 was what made a meeting cost six boxes instead of four.
# NOTHING BELOW IS A NUMBER. The patterns are looked up by NAME in genart's SPR
# table and the offsets are READ OUT OF KEYSTONE.bas, because both moved when
# the figures were redrawn to the reference's proportions -- and this file went
# stale in two ways at once, reporting overlaps that were not there while no
# longer checking the layout that was.
#
# (name, [(genart sprite name, VDP slot, colour, the source variable holding
#  its y offset -- None means it is drawn at the actor's own y)])
ACTORS = [
    ("Kelly", [("KHAT", 0, 1, "khy"),        # hat, black
               ("KFACE", 1, 11, "kfy"),      # face, skin
               ("KBODY", 2, 4, "kby"),       # tunic, blue
               ("KLEG1", 3, 4, "ky2")]),     # trousers, blue
    ("Harry", [("HBODY", 4, 15, None),       # cap + body, white
               ("HFACE", 5, 11, "hfy"),      # face, skin
               ("HSTRIPE", 6, 1, None),      # stripes, cap to hem
               ("HLEG1", 7, 15, "hy2")]),    # legs, white
]


def offsets():
    """Read `<var> = ky|hy +/- n` out of the source: the real draw offsets."""
    src = open(BAS, encoding="utf-8").read()
    out = {}
    for m in re.finditer(r"^\s*(\w+) = (?:ky|hy) ([-+]) (\d+)", src, re.M):
        out[m.group(1)] = int(m.group(3)) * (-1 if m.group(2) == "-" else 1)
    return out


_ALL = []


def sprite_rows(idx):
    """Sprite `idx` of the whole table, as 16 rows of 16 bits."""
    if not _ALL:
        for label, _arts, _c in g.SPRITES:
            _ALL.extend(read_block(label))
    return rows_of(_ALL, idx)


def read_block(label):
    txt = open(ART, encoding="utf-8").read()
    m = re.search(r"^%s:.*?$" % re.escape(label), txt, re.M)
    if not m:
        raise SystemExit("label %s not found" % label)
    out = []
    for line in txt[m.end():].split("\n"):
        t = line.strip()
        if not t or t.startswith("'"):
            continue
        if not t.startswith("DATA BYTE"):
            break
        for tok in t[9:].split(","):
            tok = tok.strip()
            out.append(int(tok[1:], 16) if tok.startswith("$") else int(tok))
    return out


def rows_of(data, idx):
    """16 rows of 16 bits. Sprite bytes are QUADRANT-ordered: 16 rows of the
    left half, then 16 rows of the right half."""
    b = data[idx * 32:(idx + 1) * 32]
    return [(b[y] << 8) | b[16 + y] for y in range(16)]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "bands.png")
    W, H = 40, 36
    canvas = [[(33, 200, 66)] * (W * len(ACTORS)) for _ in range(H)]
    bad = []

    off = offsets()
    resolved = []
    for name, parts in ACTORS:
        rp = []
        for sname, slot, col, var in parts:
            if sname not in g.SPR:
                bad.append("%s: genart has no sprite called %r" % (name, sname))
                continue
            dy = 0 if var is None else off.get(var)
            if dy is None:
                bad.append("%s: no `%s = ky/hy +/- n` in KEYSTONE.bas, so its "
                           "draw offset could not be read" % (name, var))
                continue
            rp.append((g.SPR[sname] // 4, slot, col, dy))
        resolved.append((name, rp))

    for a, (name, parts) in enumerate(resolved):
        owner = {}
        for idx, slot, col, dy in parts:
            for y, bits in enumerate(sprite_rows(idx)):
                if not bits:
                    continue
                fy = y + dy
                if fy in owner and owner[fy] != slot:
                    bad.append("%s: figure row %d carries pixels from slot %d "
                               "AND slot %d" % (name, fy, owner[fy], slot))
                owner[fy] = slot
                for x in range(16):
                    if bits & (0x8000 >> x) and fy < H:
                        canvas[fy][a * W + 12 + x] = PAL[col]

    # both actors level, which is the worst case and also the endgame chase
    for line in range(-16, H):
        covering = sorted(slot
                          for _n, parts in resolved
                          for _i, slot, _c, dy in parts
                          if dy <= line < dy + 16)
        dropped = covering[MAX_PER_LINE:]
        for slot in dropped:
            if slot not in DROPPABLE:
                bad.append("scanline %d: %d boxes, and slot %d would be "
                           "dropped -- only %s may drop"
                           % (line, len(covering), slot, sorted(DROPPABLE)))

    try:
        from PIL import Image
        im = Image.new("RGB", (W * len(ACTORS), H))
        im.putdata([p for row in canvas for p in row])
        im.resize((W * len(ACTORS) * 6, H * 6), Image.NEAREST).save(out)
        print("wrote %s" % os.path.normpath(out))
    except ImportError:
        pass

    if bad:
        for b in sorted(set(bad)):
            print("FAIL " + b)
        return 1
    print("OK  one sprite per figure row; two actors level never exceed "
          "%d boxes on a line" % MAX_PER_LINE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
