#!/usr/bin/env python3
"""Bake the RALLY-X title logo into src/title.bas.

Modelled on the X68000 port's title screen: heavy slab letters in orange
with a dark-blue drop shadow, on the tan road colour.

THE COLOUR RULE DECIDES THE DESIGN. A TMS9918 character row carries ONE
foreground and ONE background colour, so orange letter + blue shadow + tan
background is three colours in a single row and cannot be drawn. The way
out is that the conflict is only ever *within a row*: for each of the 8
rows of each character cell we pick ONE ink --

    a row that contains any LETTER pixel  -> orange, and only letter
                                             pixels are lit in that row
    otherwise, if it has SHADOW pixels    -> blue
    otherwise                             -> blank

Losing the shadow on rows that also hold letter pixels costs nothing
visible, because a drop shadow offset down-and-right shows almost entirely
on rows BELOW the glyph, which are letter-free.

CHARACTER BUDGET: the title borrows codes the game is not using while it is
on screen -- the radar canvas (144-255) is 112 of them and round_init
already re-uploads it on every round, so the restore path exists and is
proven. Cells are DEDUPED (blank and repeated stems collapse to one code),
which is what keeps the count affordable.

Run from assets/:  C:\\cygwin64\\bin\\python3.9.exe gentitle.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- glyphs
# Slab letters on a 14x20 body, drawn as row strings so the shapes stay
# readable and editable. '#' is ink.
# Built from a top block, a repeated STEM row and a bottom block, so the
# letters can be made taller without hand-typing every row -- and so every
# glyph stays exactly GH tall by construction.
def _g(top, stem, bot):
    rows = top + [stem] * (GH - len(top) - len(bot)) + bot
    # A row of the wrong width silently SHIFTS every pixel after it, and a
    # glyph that needs no stem (X) gets its middle blanked out. Both happened;
    # neither was visible in the data, only in the render. Check here.
    assert len(rows) == GH, "glyph is %d rows, want %d" % (len(rows), GH)
    for r in rows:
        assert len(r) == GW, "glyph row %r is %d wide, want %d" % (r, len(r), GW)
    return rows


def _lit(rows):
    """A glyph with no repeated stem -- every row given explicitly."""
    return _g(rows, "." * GW, [])


GW, GH = 14, 22          # glyph body: tall and heavy, like the X68000 logo
PITCH = 15               # 1 px between glyphs
SHX, SHY = 4, 5          # drop-shadow offset, down and to the right

GLYPHS = {
    "R": _g(["############..",
             "#############.",
             "###.......###.",
             "###........###",
             "###........###",
             "###.......###.",
             "#############.",
             "############..",
             "###...####....",
             "###....####..."],
            "###.....####..",
            ["###......####.",
             "###.......####",
             "###.......####"]),
    "A": _g(["....######....",
             "...########...",
             "..###....###..",
             ".###......###.",
             "###........###",
             "###........###",
             "###........###",
             "##############",
             "##############"],
            "###........###",
            ["###........###",
             "###........###"]),
    "L": _g(["###...........",
             "###..........."],
            "###...........",
            ["###...........",
             "##############",
             "##############"]),
    "Y": _g(["###........###",
             "###........###",
             ".###......###.",
             "..###....###..",
             "...###..###...",
             "....######....",
             ".....####.....",
             ".....####....."],
            ".....####.....",
            [".....####.....",
             ".....####....."]),
    "-": _lit(["..............",
               "..............",
               "..............",
               "..............",
               "..............",
               "..............",
               "..............",
               "..............",
               "..............",
               "..###########.",
               "..###########.",
               "..###########.",
               "..............",
               "..............",
               "..............",
               "..............",
               "..............",
               "..............",
               "..............",
               "..............",
               "..............",
               ".............."]),
    "X": _lit(["###........###",
               "###........###",
               ".###......###.",
               ".###......###.",
               "..###....###..",
               "..###....###..",
               "...###..###...",
               "...###..###...",
               "....######....",
               ".....####.....",
               ".....####.....",
               ".....####.....",
               ".....####.....",
               "....######....",
               "...###..###...",
               "...###..###...",
               "..###....###..",
               "..###....###..",
               ".###......###.",
               ".###......###.",
               "###........###",
               "###........###"]),
}

WORD = "RALLY-X"

COLS, ROWS = 15, 4       # title block in CHARACTERS  (120 x 32 px)
TOPM = 1                 # top margin, so the caps are not flush to the edge
W, H = COLS * 8, ROWS * 8

letter = [[0] * W for _ in range(H)]
x0 = (W - (len(WORD) * PITCH - (PITCH - GW))) // 2
for i, ch in enumerate(WORD):
    g = GLYPHS[ch]
    for y, row in enumerate(g):
        for x, c in enumerate(row):
            if c == "#":
                px, py = x0 + i * PITCH + x, y + TOPM
                if 0 <= px < W and 0 <= py < H:
                    letter[py][px] = 1

shadow = [[0] * W for _ in range(H)]
for y in range(H):
    for x in range(W):
        if letter[y][x]:
            sx, sy = x + SHX, y + SHY
            if 0 <= sx < W and 0 <= sy < H:
                shadow[sy][sx] = 1

# KEEP ONLY THE SHADOW BELOW THE WORD. The per-cell-row ink rule means any
# shadow pixel sharing a row with a letter pixel in the SAME character is
# dropped, which left the shadow as disconnected blue fragments scattered
# inside and between the letters -- it read as debris, not as a shadow.
# Restricting it to rows that are letter-free across the WHOLE logo gives
# one clean offset band under the word, which is what the X68000 title
# actually reads as at this size.
# SHADOW REMOVED. Even restricted to the band below the word it read as a
# row of disconnected blue blocks rather than a shadow -- the per-row ink
# rule cannot carry a shadow that hugs the letters, and a detached one just
# looks like debris. Plain orange caps on the tan field are cleaner.
for y in range(H):
    shadow[y] = [0] * W

# --------------------------------------------------- cells, with dedup
ORANGE_ON_TAN = 0x9A     # light red (9) on tan (10) -- the logo body
BLUE_ON_TAN = 0x4A       # dark blue (4) on tan      -- the drop shadow
BLANK = 0xAA             # tan on tan                -- invisible filler

cells, layout = [], []
index = {}
for cr in range(ROWS):
    row_codes = []
    for cc in range(COLS):
        pat, col = [], []
        for ly in range(8):
            y = cr * 8 + ly
            lit_letter = any(letter[y][cc * 8 + lx] for lx in range(8))
            src = letter if lit_letter else shadow
            ink = ORANGE_ON_TAN if lit_letter else BLUE_ON_TAN
            bits = 0
            for lx in range(8):
                if src[y][cc * 8 + lx]:
                    bits |= 0x80 >> lx
            if bits == 0:
                ink = BLANK
            pat.append(bits)
            col.append(ink)
        key = (tuple(pat), tuple(col))
        if key not in index:
            index[key] = len(cells)
            cells.append((pat, col))
        row_codes.append(index[key])
    layout.append(row_codes)

BASE = 144               # borrow the radar canvas codes while the title is up
NCELL = 64               # table is PADDED to a fixed size so the source can
                         # DEFINE a constant count -- otherwise every art
                         # tweak silently changes how many chars to upload
assert len(cells) <= NCELL, "logo needs %d cells, only %d" % (len(cells), NCELL)
while len(cells) < NCELL:
    cells.append(([0] * 8, [0xAA] * 8))

out = ["\t' GENERATED by assets/gentitle.py -- do not hand-edit.",
       "\t' RALLY-X title logo: %d x %d chars, %d UNIQUE cells (deduped from"
       % (COLS, ROWS, len(cells)),
       "\t' %d), uploaded at char %d over the radar canvas -- which the title" % (COLS * ROWS, BASE),
       "\t' does not need and round_init re-uploads for every round anyway.",
       "\t' Orange body, dark-blue drop shadow, both on tan; the per-ROW ink",
       "\t' choice is what keeps it inside the two-colours-per-row limit.",
       ""]
out.append("title_pat:")
for pat, _ in cells:
    out.append("\tDATA BYTE " + ",".join("$%02X" % b for b in pat))
out.append("title_col:")
for _, col in cells:
    out.append("\tDATA BYTE " + ",".join("$%02X" % b for b in col))
out.append("title_map:")
out.append("\t' %d rows of %d char codes, row-major" % (ROWS, COLS))
for row in layout:
    out.append("\tDATA BYTE " + ",".join(str(BASE + c) for c in row))
open(os.path.join(HERE, "..", "src", "title.bas"), "w").write("\n".join(out) + "\n")

print("logo %d x %d chars, %d unique cells (of %d), base char %d"
      % (COLS, ROWS, len(cells), COLS * ROWS, BASE))
print("wrote src/title.bas")
