#!/usr/bin/env python3
"""Keystone Kapers font -- an arcade-style face to replace CVBasic's stock 8x8.

Williams' cabinet font is heavy, squared and slightly condensed: thick uniform
strokes, flat terminals, no serifs and no thin joins. The stock CVBasic font is a
thin generic ASCII face and reads like a BASIC listing rather than an arcade game,
which undoes a lot of the work the sprites do.

Drawn 5 wide x 7 tall inside the 8x8 cell, with a blank column at the right for
letter spacing and a blank row at the bottom for line spacing -- so text never
touches text, which is what keeps a heavy face legible at this size.

ONLY CHARACTERS 32-90 are defined: space, the punctuation the game actually
prints, the digits, and A-Z. That is 59 characters x 8 bytes = 472 bytes, and
anything above 'Z' is never printed. Undefined slots emit blanks rather than
being skipped, because DEFINE CHAR takes a CONTIGUOUS run -- a gap would shift
every letter after it.

Digits are drawn first and most carefully: the score is the text most on screen.

Run:  python3 genfont.py      writes ../src/font.bas
"""

import os

# BLACK INK ON DARK BLUE, one byte repeated for every scan line of every
# character. The TMS9918 bitmap colour table is one byte per 8x1 line -- high
# nibble ink, low nibble background -- so 1 (black) over 4 (dark blue) is
# 1 * 16 + 4.
#
# THIS USED TO BE A VPOKE LOOP and it was the slowest thing in the boot: 1,416
# writes of this one value, paced by 24 WAITs, before the title could be drawn.
# CVBasic's DEFINE COLOR does the same job in a single synchronous LDIRVM3 with
# interrupts off, but it reads the value from a TABLE -- so the table is 472
# identical bytes, and they cost nothing because they live in the data bank.
INK = 1
PAPER = 4
COLBYTE = INK * 16 + PAPER

# 5x7. '#' on, '.' off.
GLYPHS = {
" ": "..... ..... ..... ..... ..... ..... .....",
"0": ".###. #...# #..## #.#.# ##..# #...# .###.",
"1": "..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.",
"2": ".###. #...# ....# ..##. .#... #.... #####",
"3": "####. ....# ....# .###. ....# ....# ####.",
"4": "...#. ..##. .#.#. #..#. ##### ...#. ...#.",
"5": "##### #.... ####. ....# ....# #...# .###.",
"6": ".###. #.... #.... ####. #...# #...# .###.",
"7": "##### ....# ...#. ..#.. .#... .#... .#...",
"8": ".###. #...# #...# .###. #...# #...# .###.",
"9": ".###. #...# #...# .#### ....# ....# .###.",
"A": ".###. #...# #...# #...# ##### #...# #...#",
"B": "####. #...# #...# ####. #...# #...# ####.",
"C": ".###. #...# #.... #.... #.... #...# .###.",
"D": "###.. #..#. #...# #...# #...# #..#. ###..",
"E": "##### #.... #.... ####. #.... #.... #####",
"F": "##### #.... #.... ####. #.... #.... #....",
"G": ".###. #...# #.... #.### #...# #...# .####",
"H": "#...# #...# #...# ##### #...# #...# #...#",
"I": ".###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.",
"J": "..### ...#. ...#. ...#. #..#. #..#. .##..",
"K": "#...# #..#. #.#.. ##... #.#.. #..#. #...#",
"L": "#.... #.... #.... #.... #.... #.... #####",
"M": "#...# ##.## #.#.# #.#.# #...# #...# #...#",
"N": "#...# ##..# #.#.# #.#.# #..## #...# #...#",
"O": ".###. #...# #...# #...# #...# #...# .###.",
"P": "####. #...# #...# ####. #.... #.... #....",
"Q": ".###. #...# #...# #...# #.#.# #..#. .##.#",
"R": "####. #...# #...# ####. #.#.. #..#. #...#",
"S": ".#### #.... #.... .###. ....# ....# ####.",
"T": "##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
"U": "#...# #...# #...# #...# #...# #...# .###.",
"V": "#...# #...# #...# #...# #...# .#.#. ..#..",
"W": "#...# #...# #...# #.#.# #.#.# ##.## #...#",
"X": "#...# #...# .#.#. ..#.. .#.#. #...# #...#",
"Y": "#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..",
"Z": "##### ....# ...#. ..#.. .#... #.... #####",
"&": ".##.. #..#. #.#.. .#... #.#.# #..#. .##.#",
"/": "....# ....# ...#. ..#.. .#... #.... #....",
"-": "..... ..... ..... ##### ..... ..... .....",
".": "..... ..... ..... ..... ..... .##.. .##..",
",": "..... ..... ..... ..... .##.. .##.. .#...",
"!": "..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..",
"?": ".###. #...# ....# ..##. ..#.. ..... ..#..",
":": "..... .##.. .##.. ..... .##.. .##.. .....",
"'": "..#.. ..#.. ..... ..... ..... ..... .....",
"(": "...#. ..#.. .#... .#... .#... ..#.. ...#.",
")": ".#... ..#.. ...#. ...#. ...#. ..#.. .#...",
"+": "..... ..#.. ..#.. ##### ..#.. ..#.. .....",
"=": "..... ..... ##### ..... ##### ..... .....",
"*": "..... #.#.# .###. ##### .###. #.#.# .....",
"<": "...#. ..#.. .#... #.... .#... ..#.. ...#.",
">": ".#... ..#.. ...#. ....# ...#. ..#.. .#...",
"#": ".#.#. ##### .#.#. .#.#. ##### .#.#. .....",
"$": "..#.. .#### #.#.. .###. ..#.# ####. ..#..",
"%": "##..# ##..# ...#. ..#.. .#... #..## #..##",
'"': ".#.#. .#.#. ..... ..... ..... ..... .....",
";": "..... .##.. .##.. ..... .##.. .##.. .#...",
"@": ".###. #...# #.### #.#.# #.### #.... .###.",
"[": "..##. ..#.. ..#.. ..#.. ..#.. ..#.. ..##.",
"]": ".##.. ..#.. ..#.. ..#.. ..#.. ..#.. .##..",
"\\": "#.... #.... .#... ..#.. ...#. ....# ....#",
"^": "..#.. .#.#. #...# ..... ..... ..... .....",
"_": "..... ..... ..... ..... ..... ..... #####",
"`": ".#... ..#.. ..... ..... ..... ..... .....",
}

FIRST, LAST = 32, 90


def glyph_bytes(ch):
    art = GLYPHS.get(ch)
    if art is None:
        return [0] * 8
    rows = art.split()
    assert len(rows) == 7, (ch, len(rows))
    out = []
    for r in rows:
        assert len(r) == 5, (ch, r)
        v = 0
        for i in range(5):
            v = (v << 1) | (0 if r[i] == "." else 1)
        out.append(v << 3)          # 5 bits left-aligned; 3 blank cols at right
    out.append(0)                   # blank row at the bottom
    return out


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "src", "font.bas")
    n = LAST - FIRST + 1
    data = []
    missing = []
    for c in range(FIRST, LAST + 1):
        ch = chr(c)
        if ch not in GLYPHS and ch != " ":
            missing.append(ch)
        data += glyph_bytes(ch)
    assert len(data) == n * 8
    assert len(data) % 2 == 0
    # DEFINE COLOR READS EIGHT BYTES PER CHARACTER, NOT ONE (CLAUDE.md 3A).
    # Supply fewer and it silently reads whatever follows in ROM as colour data:
    # the text comes out in random colours with no error at build or run time.
    # Asserted rather than commented, because the failure is invisible.
    cols = [COLBYTE] * (n * 8)
    assert len(cols) == n * 8
    # An odd-length DATA BYTE block leaves the location counter odd and shifts
    # every word table defined after it in the same segment, for ever
    # (CLAUDE.md 3A). Both blocks here are even; keep them that way.
    assert len(cols) % 2 == 0

    with open(out, "w", newline="\n") as fh:
        fh.write("""\t' Keystone Kapers font -- GENERATED by assets/genfont.py. Do not edit; regenerate.
\t'
\t' Characters %d-%d (%d of them), 8 bytes each = %d bytes. Williams' cabinet face:
\t' heavy, squared, flat terminals, no serifs -- drawn 5x7 inside the 8x8 cell so a
\t' blank column at the right and a blank row at the bottom keep it legible.
\t'
\t' Loaded with DEFINE CHAR %d,%d,font_bits. The run must be CONTIGUOUS, so slots
\t' with no glyph emit blanks rather than being skipped -- a gap would shift every
\t' letter after it.

font_bits:
""" % (FIRST, LAST, n, n * 8, FIRST, n))
        for i in range(0, len(data), 8):
            ch = chr(FIRST + i // 8)
            label = "space" if ch == " " else ch
            fh.write("\tDATA BYTE " + ",".join("$%02X" % b for b in data[i:i + 8])
                     + "\t' " + label + "\n")

        fh.write("""
\t' THE COLOUR TABLE, %d bytes of the same value ($%02X = black ink on dark blue).
\t'
\t' Loaded with DEFINE COLOR %d,%d,font_col, which is ONE synchronous call that
\t' writes all three screen thirds (define_color always does the LDIRVM3 triple
\t' copy). It replaced a VPOKE loop that wrote this one value 1,416 times paced by
\t' 24 WAITs -- the largest scripted delay in the boot, and the reason the title
\t' screen used to fill in visibly rather than appearing at once.
\t'
\t' EIGHT BYTES PER CHARACTER, not one. Supply fewer and DEFINE COLOR reads
\t' whatever follows in ROM as colour data, with no error at build or run time.

font_col:
""" % (len(cols), COLBYTE, FIRST, n))
        for i in range(0, len(cols), 8):
            ch = chr(FIRST + i // 8)
            label = "space" if ch == " " else ch
            fh.write("\tDATA BYTE " + ",".join("$%02X" % b for b in cols[i:i + 8])
                     + "\t' " + label + "\n")

    print("wrote %s -- %d chars, %d bytes of pattern + %d of colour%s"
          % (os.path.normpath(out), n, len(data), len(cols),
             (", blank: " + "".join(missing)) if missing else ""))


if __name__ == "__main__":
    main()
