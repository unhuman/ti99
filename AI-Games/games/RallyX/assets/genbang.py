#!/usr/bin/env python3
"""Generate src/bang.bas -- the crash starburst and the score-popup glyphs.

CHAR CODES MUST STAY BELOW 32. Everything from 32 up is the printable ASCII
font: 32 is SPACE, which CLS fills the whole screen with and which every
PRINT pads with. A first cut put the burst at 16..33 and so redefined space
as a chunk of tan starburst -- the panel's blank areas and every padded
field turned into yellow rubble. So:

  chars 16..23    BANG burst: TWO 2x2 animation frames (16x16 px each)
  chars 140..143  the score popup's 2x2 box -- NOT fixed art. Only four
                  codes are reserved; their patterns are composed in RAM at
                  pickup from a 3x5 mini font and uploaded with
                  DEFINE CHAR ...,VARPTR, so any value fits 16x16 px.

The TMS9918 gives two colours per 8-pixel ROW of a character, which is what
makes dark lettering inside a light shape possible: the burst's letter band
(the middle character row) flips to black-on-light-yellow while the rest stays
light-yellow-on-ROAD-TAN. Tan rather than transparent, because a transparent
pixel shows the BACKDROP -- the star ended up in a black box the moment the
crash border-strobe finished. Cars only ever crash on road, so tan is the
colour that disappears.
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
W = H = 16                      # 2x2 chars -- ONE maze cell, no more
LET_TOP, LET_BOT = 6, 10        # narrow letter band, so the star still shows

# TWO animation frames, 4 chars each: 16-19 and 20-23. The explosion is
# CHARACTERS, not sprites -- it belongs to the roadway, and a sprite drifts
# out of register with the map the moment anything scrolls. Animating costs
# 4 VPOKEs (swap which frame's codes are on the name table), not a pattern
# reupload.
BANG_BASE = 16

# ---------------------------------------------------------------- burst shape
def make_star(base, amp, phase):
    g = [[0] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            dx = x - (W / 2.0 - 0.5)
            dy = (y - (H / 2.0 - 0.5))
            r = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            if r <= base + amp * math.cos(8.0 * a + phase):
                g[y][x] = 1
    return g

STARS = [make_star(5.0, 3.2, 0.0), make_star(6.6, 2.6, math.pi / 8)]

# 3x5 letters: four of them across 16 px is all that fits.
LETTERS = {
    "B": ["110", "101", "110", "101", "110"],
    "A": ["010", "101", "111", "101", "101"],
    "N": ["101", "111", "111", "111", "101"],
    "G": ["011", "100", "101", "101", "011"],
}
letters = [[0] * W for _ in range(H)]
for idx, ch in enumerate("BANG"):
    x0 = idx * 4
    for y, rowbits in enumerate(LETTERS[ch]):
        for x, b in enumerate(rowbits):
            if b == "1":
                letters[LET_TOP + y][x0 + x] = 1

bang_pat, bang_col = [], []
for star in STARS:
    for cr in range(H // 8):
        for cc in range(W // 8):
            rows, cols = [], []
            for ly in range(8):
                y = cr * 8 + ly
                lettered = LET_TOP <= y <= LET_BOT
                src = letters if lettered else star
                bits = 0
                for lx in range(8):
                    if src[y][cc * 8 + lx]:
                        bits |= 0x80 >> lx
                rows.append(bits)
                # The blast is RED, the lettering black on it.
                #   $19 = black on light red   (the BANG band)
                #   $9A = light red on ROAD TAN (the spikes)
                # Tan, not transparent: a transparent pixel shows the
                # BACKDROP, which put the star in a black box the moment the
                # crash border-strobe finished. Cars only crash on road.
                cols.append(0x19 if lettered else 0x9A)
            bang_pat.append(rows)
            bang_col.append(cols)

# ------------------------------------------------------------- popup glyphs
# 3x5 MINI font. The popup has to fit the same 2x2 cell as the burst, i.e.
# 16x16 px, so "1000x2" cannot be built from 8x8 characters -- there is only
# room for four 4-px columns. Instead the four characters of the box are
# composed in RAM at pickup and uploaded with DEFINE CHAR ...,VARPTR, so any
# value works with only four character codes reserved.
#
# Each row is stored with its three pixels already in bits 7..5, so slot 0
# and slot 2 use the byte as-is and the odd slots just shift right by 4.
MINI = {
    "0": ["111", "101", "101", "101", "111"],
    "1": ["010", "110", "010", "010", "111"],
    "2": ["111", "001", "111", "100", "111"],
    "3": ["111", "001", "111", "001", "111"],
    "4": ["101", "101", "111", "001", "001"],
    "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"],
    "7": ["111", "001", "001", "001", "001"],
    "8": ["111", "101", "111", "101", "111"],
    "9": ["111", "101", "111", "001", "111"],
    "x": ["000", "101", "010", "101", "000"],
}
mini = []
for ch in "0123456789x":
    mini.append([int(r, 2) << 5 for r in MINI[ch]])


def emit(name, tiles):
    out = ["%s:" % name]
    for t in tiles:
        out.append("\tDATA BYTE " + ",".join("$%02X" % v for v in t))
    return out


lines = ["\t' GENERATED by assets/genbang.py -- do not hand-edit.",
         "\t' chars %d-%d BANG burst (4x3). Popup box = chars 140-143, composed"
         % (BANG_BASE, BANG_BASE + 11),
         "\t' in RAM at pickup from mini_font (see minifont.bas, TI bank 0).",
         "\t' NOTHING may land on char 32 (SPACE) -- redefining it wrecks every",
         "\t' blank cell on the screen.",
         ""]
lines += emit("bang_pat", bang_pat) + [""]
lines += emit("bang_col", bang_col) + [""]
# Popup: BLACK ON ROAD TAN ($1A), every row. White-on-black read as a hole
# punched in the roadway; black on tan sits in the road like painted markings.
lines += emit("pop_col", [[0x1A] * 8 for _ in range(4)])
open(os.path.join(HERE, "..", "src", "bang.bas"), "w").write("\n".join(lines) + "\n")

# The mini font is read by gameplay code, which runs with TI bank 1 or 2
# selected -- so it must live in bank 0, the only one always mapped.
mf = ["\t' GENERATED by assets/genbang.py -- do not hand-edit.",
      "\t' 3x5 popup font, glyphs 0-9 then 'x'. MUST stay in TI bank 0:",
      "\t' gameplay PEEKs it while another bank is selected.",
      ""]
mf += emit("mini_font", mini)
open(os.path.join(HERE, "..", "src", "minifont.bas"), "w").write("\n".join(mf) + "\n")

print("wrote src/bang.bas (burst %d chars at %d) and src/minifont.bas (%d glyphs)"
      % (len(bang_pat), BANG_BASE, len(mini)))
