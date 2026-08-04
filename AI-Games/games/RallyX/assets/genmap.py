#!/usr/bin/env python3
"""Bake maze1.txt into the RaltiX (CVBasic) map/tile includes.

The world renders at 2x2 characters per logical maze cell (16-px roads, the
16x16 car exactly fills a lane). Two map encodings are generated:

  src/map0.bas  (TI bank 0 -- always visible; gameplay PEEKs need no switch)
    map1:   34x58 LOGICAL map, one byte per cell: wall 96 / tree 112 /
            road 113 (codes >= 113 drivable -- one compare in `probe`).
  src/map2.bas  (TI bank 1 -- selected during gameplay for SCREEN blits)
    map2:   68x116 CHAR map, 2x2 chars per logical cell, walls pre-edged
            with quadrant variants, stride 68.
  src/tiles.bas (TI bank 2 -- selected only during init / round setup)
    wallpat/wallcol:   16 quadrant wall chars (codes 96-111), 2-px road-
                       facing inset. Quadrant needs only its 2 edge bits:
                       TL 96+ (N=1,W=2), TR 100+ (N=1,E=2),
                       BL 104+ (S=1,W=2), BR 108+ (S=1,E=2).
    ovlpat/ovlcol:     overlay chars 0-15: flags F/S/L as 2x2 quadrant
                       sets (F 0-3, S 4-7, L 8-11, order TL TR BL BR)
                       and a 2x2 smoke puff (12-15).
    radar_zero/radar_base: blank radar canvas patterns + base colors.

Char codes must match DESIGN.md section 4.
Run from assets/: C:\\cygwin64\\bin\\python3.9.exe genmap.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

rows = [l.rstrip("\n") for l in open(os.path.join(HERE, "maze1.txt")).readlines()[:56]]
assert len(rows) == 56 and all(len(r) == 32 for r in rows), "maze1.txt must be 56 rows x 32 cols"

WALL0, TREE, ROAD = 96, 112, 113
COLS, ROWS = 34, 58  # bordered logical

def solid(r, c):
    """True if bordered cell (r,c) is wall or tree (border ring counts)."""
    if r <= 0 or r >= ROWS - 1 or c <= 0 or c >= COLS - 1:
        return True
    return rows[r - 1][c - 1] == "#"

def data_byte_lines(vals, per=17, indent="\t"):
    out = []
    for i in range(0, len(vals), per):
        out.append(indent + "DATA BYTE " + ",".join("$%02X" % v for v in vals[i:i + per]))
    return out

# --- logical map (collision/AI/radar) --------------------------------------
logical = []
for r in range(ROWS):
    line = []
    for c in range(COLS):
        if r == 0 or r == ROWS - 1 or c == 0 or c == COLS - 1:
            line.append(TREE)
        elif rows[r - 1][c - 1] == "#":
            line.append(WALL0)  # any wall code < 113 works for probe
        else:
            line.append(ROAD)
    logical.append(line)

# --- quadrant wall chars ----------------------------------------------------
def quad_pattern(top_inset, side_left, side_inset, bottom_inset):
    """8x8 quadrant: solid, minus a 2-px inset on road-facing edges.
    top_inset/bottom_inset clear rows 0-1 / 6-7; side_inset clears the
    2 outer columns (left cols if side_left else right cols)."""
    pat = []
    for row in range(8):
        bits = 0xFF
        if side_inset:
            bits &= 0x3F if side_left else 0xFC
        if top_inset and row < 2:
            bits = 0
        if bottom_inset and row >= 6:
            bits = 0
        pat.append(bits)
    return pat

wallpat = []
for quad in range(4):          # 0 TL, 1 TR, 2 BL, 3 BR
    for v in range(4):         # bit0 = N/S road-facing, bit1 = W/E road-facing
        vert = v & 1
        horiz = v & 2
        top = vert and quad in (0, 1)
        bottom = vert and quad in (2, 3)
        left = quad in (0, 2)
        wallpat.append(quad_pattern(top, left, horiz, bottom))

# --- doubled char map -------------------------------------------------------
map2 = []
for r in range(ROWS):
    top_line, bot_line = [], []
    for c in range(COLS):
        cell = logical[r][c]
        if cell == ROAD:
            q = [ROAD] * 4
        elif cell == TREE:
            q = [TREE] * 4
        else:
            n = 0 if solid(r - 1, c) else 1
            s = 0 if solid(r + 1, c) else 1
            w = 0 if solid(r, c - 1) else 2
            e = 0 if solid(r, c + 1) else 2
            q = [96 + n + w, 100 + n + e, 104 + s + w, 108 + s + e]
        top_line += q[0:2]
        bot_line += q[2:4]
    map2.append(top_line)
    map2.append(bot_line)

# --- 16x16 overlay art (flags + smoke), split into quadrants ---------------
def quads(rows16):
    """16 ints (16-bit rows) -> 4 chars of 8 bytes: TL TR BL BR."""
    tl = [(v >> 8) & 0xFF for v in rows16[:8]]
    tr = [v & 0xFF for v in rows16[:8]]
    bl = [(v >> 8) & 0xFF for v in rows16[8:]]
    br = [v & 0xFF for v in rows16[8:]]
    return [tl, tr, bl, br]

flag16 = [
    0b0001111111000000,
    0b0001111111111000,
    0b0001111111111110,
    0b0001111111111000,
    0b0001111111000000,
    0b0001100000000000,
    0b0001100000000000,
    0b0001100000000000,
    0b0001100000000000,
    0b0001100000000000,
    0b0001100000000000,
    0b0001100000000000,
    0b0001100000000000,
    0b0001100000000000,
    0b0000000000000000,
    0b0000000000000000,
]
def puff16():
    """The arcade smoke PUFF-BALL: a rosette of round lobes.

    Traced from the arcade screenshot (assets/ref-smoke.png, native 288x224
    so 1 px = 1 game px): the puff is a pale cream blob whose lobes are
    separated by black outlines -- it reads as popcorn, not as a cloud.

    A TI char row has only fg+bg, so we can't draw a third outline colour.
    Instead we light each lobe's INTERIOR and leave its EDGE unlit: where
    lobes overlap those edges become the internal separations, and against
    the tan road they read exactly like the arcade's outlines.
    """
    # A SOLID bumpy ball (big centre + four diagonal bumps), with small
    # bites taken out of the perimeter at the cardinals. Carving full
    # outlines between overlapping lobes ate the fill and came out hollow;
    # a solid blob with a lobed silhouette is what reads as popcorn at 16px.
    lobes = [(7.5, 7.5, 5.5), (4.3, 4.3, 3.0), (10.7, 4.3, 3.0),
             (4.3, 10.7, 3.0), (10.7, 10.7, 3.0)]
    notches = [(7.5, 1.6, 1.4), (7.5, 13.4, 1.4),
               (1.6, 7.5, 1.4), (13.4, 7.5, 1.4)]
    rows = []
    for y in range(16):
        bits = 0
        for x in range(16):
            on = any((x - cx) ** 2 + (y - cy) ** 2 <= r * r for cx, cy, r in lobes)
            if on:
                if any((x - cx) ** 2 + (y - cy) ** 2 <= r * r for cx, cy, r in notches):
                    on = False
            if on:
                bits |= 1 << (15 - x)
        rows.append(bits)
    return rows

smoke16 = puff16()


def rock16():
    """A boulder: lumpy mass, wider at the base, sitting ON the road.

    Chars 24-27, i.e. clear of the flag/smoke overlays (0-15) and of the
    BANG burst (16-23), and safely under 32 -- redefining 32 would rewrite
    SPACE and wreck every blank cell on the screen (see genbang.py).

    Not a clean circle: a circle at 16px reads as a ball. Overlapping lobes
    with a flattened, wider bottom read as a rock, and the small bites out
    of the top-left silhouette give it facets.
    """
    lobes = [(7.5, 9.0, 5.6), (5.0, 6.0, 3.4), (10.4, 6.2, 3.2),
             (7.6, 4.6, 2.8)]
    bites = [(2.0, 3.4, 2.2), (13.2, 3.6, 2.0), (7.5, 1.2, 1.6)]
    rows = []
    for y in range(16):
        bits = 0
        for x in range(16):
            on = any((x - cx) ** 2 + (y - cy) ** 2 <= r * r for cx, cy, r in lobes)
            # flat base: the boulder rests on the road, it does not float
            if y >= 14:
                on = False
            if on and any((x - cx) ** 2 + (y - cy) ** 2 <= r * r
                          for cx, cy, r in bites):
                on = False
            if on:
                bits |= 1 << (15 - x)
        rows.append(bits)
    return rows


rock16 = rock16()
rockpat = quads(rock16)
# THERE IS ONLY ONE GREY on the TMS9918 (14), so "a darker grey" does not
# exist -- the darker choices are black, dark blue, dark red, dark green.
# Plain grey on the tan road was too low-contrast to pick out while driving.
#
# BLACK on tan it is: the strongest contrast the palette offers here, and
# nothing else in the playfield is black, so a boulder can only be a
# boulder. Shading it (grey highlight band on top, black below) was tried
# first and rejected from the render -- colour is per ROW, so any highlight
# is a full-width band and the rock came out looking like a pot with a lid
# rather than a rock. The lumpy silhouette alone reads as stone.
rockcol = [["$1A"] * 8] * 4

ovlpat = quads(flag16) * 3 + quads(smoke16)
# Flag colours are chosen for CONTRAST AGAINST THE TAN ROAD (bg A = dark
# yellow). The original yellow-on-tan flag was nearly invisible; white,
# light red and cyan all read cleanly on it.
FLAGCOLS = ["$FA", "$9A", "$7A"]   # F white / S light red / L cyan, on tan
ovlcol = []
for fc in FLAGCOLS:
    ovlcol += [[fc] * 8] * 4
ovlcol += [["$FA"] * 8] * 4     # smoke: ONE colour (white on tan) in all
                                # four quadrants -- a per-quadrant split is
                                # what made the cloud look half-grey

# --- emit -------------------------------------------------------------------
out = []
out.append("\t' GENERATED by assets/genmap.py from assets/maze1.txt -- do not hand-edit.")
out.append("\t' LOGICAL 34x58 map: wall 96 / tree 112 / road 113 (TI bank 0).")
out.append("map1:")
for r in range(ROWS):
    out.extend(data_byte_lines(logical[r]))
open(os.path.join(HERE, "..", "src", "map0.bas"), "w").write("\n".join(out) + "\n")

out = []
out.append("\t' GENERATED by assets/genmap.py -- do not hand-edit.")
out.append("\t' CHAR map 116 rows x 68 cols, 2x2 chars per logical cell (TI bank 1).")
out.append("map2:")
for line in map2:
    out.extend(data_byte_lines(line))
open(os.path.join(HERE, "..", "src", "map2.bas"), "w").write("\n".join(out) + "\n")

out = []
out.append("\t' GENERATED by assets/genmap.py -- do not hand-edit (TI bank 2).")
out.append("wallpat:")
qn = ["TL", "TR", "BL", "BR"]
for i, p in enumerate(wallpat):
    out.append("\tDATA BYTE " + ",".join("$%02X" % b for b in p) +
               "\t' %s v%d" % (qn[i // 4], i % 4))
out.append("wallcol:")
out.append("\t' green (2) on tan (10) every row, all 16 quadrant chars")
for i in range(16):
    out.append("\tDATA BYTE $2A,$2A,$2A,$2A,$2A,$2A,$2A,$2A")
out.append("ovlpat:")
out.append("\t' chars 0-15: F 0-3, S 4-7, L 8-11, smoke 12-15 (TL TR BL BR)")
for p in ovlpat:
    out.append("\tDATA BYTE " + ",".join("$%02X" % b for b in p))
out.append("ovlcol:")
for c8 in ovlcol:
    out.append("\tDATA BYTE " + ",".join(c8))
out.append("rockpat:")
out.append("	' chars 24-27: rock boulder, 2x2 quadrants (TL TR BL BR)")
for p in rockpat:
    out.append("	DATA BYTE " + ",".join("$%02X" % b for b in p))
out.append("rockcol:")
out.append("	' black (1) on tan road (10): max contrast, and nothing else is black")
for c8 in rockcol:
    out.append("	DATA BYTE " + ",".join(c8))
out.append("radar_zero:")
out.append("\t' 112 x 8 zero pattern rows: blank radar canvas (chars 144-255)")
for i in range(112):
    out.append("\tDATA BYTE $00,$00,$00,$00,$00,$00,$00,$00")
out.append("radar_base:")
out.append("\t' 112 x 8 base colors: white dots on dark blue")
for i in range(112):
    out.append("\tDATA BYTE $F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4")
open(os.path.join(HERE, "..", "src", "tiles.bas"), "w").write("\n".join(out) + "\n")

print("wrote map0.bas (logical %dx%d), map2.bas (chars %dx%d), tiles.bas" %
      (COLS, ROWS, len(map2[0]), len(map2)))
