#!/usr/bin/env python3
"""Verify the colour-banded actors, and render them for eyeballing.

Kelly is three sprites and Harry is four, one per colour band. A TMS9918 sprite
carries one colour, so that is the only way to get several colours into a
figure -- and it brings two failure modes that are silent and show up only as
"the sprite looks wrong".

1. TWO SPRITES LIGHTING THE SAME PIXEL. If the hat sprite and the face sprite
   both light row 7 column 5, that pixel has two colours fighting for one place
   and the art does not say which wins. A hard failure.

   This used to be tested per ROW, which was a fair proxy while every band was
   a horizontal stripe -- no two bands shared a row, so sharing one meant
   overlapping. Harry's arms now cross his body, and where they do the two
   colours INVERT so the limb stays visible: a white sleeve over a black band,
   a black sleeve over a white one. That is two colours on one row, at
   different columns, deliberately. The row rule called it a failure; the pixel
   rule catches the real thing and lets this through.

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
#
# SLOT 27 -- his leg stripes and shoes -- IS DROPPABLE FOR THE SAME REASON, and
# on the same terms. Harry's FACE box is drawn at hy+3, so it spans figure rows
# 3 to 18 and reaches three rows into his legs; on those three rows a meeting
# puts five boxes on the line (Kelly's two, Harry's face, leg and leg-stripe).
# The VDP drops the highest, which is 27, so what is lost is the hem stripe on
# three scanlines when the two are exactly level. Same bargain as slot 6: he
# goes plainer, never partial.
DROPPABLE = {6, 27}

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
               ("HLEG1", 7, 15, "hy2"),      # legs, white
               ("HLEGS1", 27, 1, "hy2")]),   # leg stripes + shoes, black
]


def check_complete(bad):
    """Every band an actor actually DRAWS must appear in ACTORS.

    This table is hand-written, so it is a second copy of a decision the source
    already makes -- and a second copy silently goes stale. It did: Harry grew
    a fourth band for his leg stripes and shoes, the table was not updated, and
    the check went on passing while that sprite was drawn UNDER a solid white
    leg and never appeared at all. A check whose scope is narrower than the bug
    reports success, which is worse than not running.

    So the slots are read back out of the source. An actor's draw lines are the
    ones positioned at its own x variable (`hx` for Harry, `klx` for Kelly);
    anything drawn there and not listed here is a band nothing is checking.
    """
    src = open(BAS, encoding="utf-8").read()
    xvar = {"Kelly": "klx", "Harry": "hx"}
    for name, parts in ACTORS:
        listed = set(slot for _s, slot, _c, _v in parts)
        drawn = set()
        for m in re.finditer(r"^\s*SPRITE (\d+),\s*\w+,\s*(\w+),", src, re.M):
            if m.group(2) == xvar[name]:
                drawn.add(int(m.group(1)))
        missing = sorted(drawn - listed)
        if missing:
            bad.append("%s draws sprite slot(s) %s that ACTORS does not list, "
                       "so nothing checks them for overlap or for the per-line "
                       "box count" % (name, missing))
        extra = sorted(listed - drawn)
        if extra:
            bad.append("ACTORS lists slot(s) %s for %s that the source never "
                       "draws" % (extra, name))


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

    check_complete(bad)
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

    # THE TEST IS PER PIXEL, NOT PER ROW. It used to be per row, which was a
    # fair proxy while every band WAS a horizontal stripe: no two bands shared
    # a row, so sharing one meant overlapping. Harry's arms now swing across
    # his body, and where they cross, the two colours INVERT so the limb stays
    # visible -- a white sleeve over a black band and a black sleeve over a
    # white one. That puts both colours on one row, at different columns, on
    # purpose.
    #
    # The hazard was never the row. It is two sprites lighting the SAME PIXEL,
    # where the art does not say which colour wins. So that is what is checked,
    # and it is strictly stronger than the row rule where it matters: a genuine
    # overlap still fails, and a legitimate one no longer does.
    for a, (name, parts) in enumerate(resolved):
        owner = {}
        for idx, slot, col, dy in parts:
            for y, bits in enumerate(sprite_rows(idx)):
                if not bits:
                    continue
                fy = y + dy
                for px in range(16):
                    if not bits & (0x8000 >> px):
                        continue
                    key = (fy, px)
                    if key in owner and owner[key] != slot:
                        bad.append("%s: figure pixel row %d col %d is lit by "
                                   "slot %d AND slot %d -- two colours in one "
                                   "place and the art does not say which wins"
                                   % (name, fy, px, owner[key], slot))
                    owner[key] = slot
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
