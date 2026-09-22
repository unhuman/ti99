#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""The title screen, as data -- writes src/title.bas and src/titlefont.bas.

WHY THE TITLE IS A TABLE
------------------------
It was twelve `PRINT AT n,"..."` statements, and CVBasic embeds a string literal
in the FIXED AREA -- the one budget that cannot be grown (linkticart writes
exactly three loader pages and discards the rest; they are the 32K expansion's
RAM at >A000, not cart ROM).

Here the whole screen is a display list in a ROM bank, walked by a dozen
statements in `title_draw`: the marquee, the name and every line of text are the
same `row, col, bytes` runs. Changing the title costs bank bytes, of which there
are thousands, instead of code bytes, of which there are hundreds.

THIS FILE IS THE SINGLE SOURCE OF TRUTH for what the title says, and
`checklayout.py` imports from here rather than parsing `PRINT AT` out of the
source -- that gate's whole method is reading those literals, so moving the text
into a table would otherwise have made the title invisible to it.

THE FORMAT is a flat list of runs:

    row, col, length, byte * length      repeated
    255                                  ends it

Row and column rather than a 16-bit screen offset, because reassembling one from
two bytes needs a multiply, and on the TMS9900 `MPY` clobbers r0 -- the next line
that reads the product gets the HIGH word (CLAUDE.md 3A). Five doublings do not.
"""

import io
import os
import sys

import genart
import titleword

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, os.pardir, 'src', 'title.bas')
# The name's artwork goes in a separate file because it goes in a different
# BANK: it is read once, by a DEFINE at setup, so it belongs in bank 2 with the
# font rather than in bank 1 with everything read during play.
FACE_OUT = os.path.join(HERE, os.pardir, 'src', 'titlefont.bas')
# AND THE DISPLAY LIST SPLITS FROM THE MESSAGE BOXES FOR THE SAME REASON, which
# is a distinction the single file used to hide. Both are the same FORMAT --
# runs of characters walked by run_list -- so they lived together, but they are
# read at completely different times:
#
#   title_tbl   walked once by title_draw, at boot and on return to the title
#   msg_*       walked when a ROUND ENDS, mid-game, with bank 1 selected
#
# So the display list can live on a page that is not permanently mapped and the
# message boxes cannot. Putting the whole file in bank 2 would have returned
# bytes from the wrong page at the exact moment a life is lost, with no error
# at build or run time -- which is the failure this split exists to prevent.
DL_OUT = os.path.join(HERE, os.pardir, 'src', 'titledl.bas')

COLS = 32
END = 255

# ---------------------------------------------------------------------------
# THE MARQUEE
# ---------------------------------------------------------------------------
#
# Three lamps, one dark cell, all the way round -- the reference's own rhythm,
# on every side rather than just the top.
#
# IT IS ONE CONTINUOUS RING, not four runs that happen to meet. Walking the
# perimeter and lighting `i mod 4 < 3` makes the corners fall out of the rhythm
# automatically, which is what a real marquee does and what four independently
# laid-out sides cannot do: those give a four-lamp run at one corner and a
# double gap at another, and no amount of shuffling the ends fixes both.
#
# THE FRAME'S SIZE IS CHOSEN SO THE RING CLOSES. A perimeter that is not a
# multiple of four has a seam where the pattern restarts. Rows 1..21 by columns
# 2..28 gives 92, which is 23 clusters exactly -- and it keeps two columns clear
# on the left, three on the right and two rows at the bottom, so nothing is lost
# to a real set's overscan.
FRAME_TOP, FRAME_BOT = 3, 23
FRAME_L, FRAME_R = 2, 28

CLUSTER, GAP = 3, 1
PERIOD = CLUSTER + GAP


def bulb(phase):
    """The character code for a perimeter cell in phase 0..3.

    EVERY cell of the frame is a bulb character -- including the dark ones.
    A space would be cheaper in the table and would make the chase impossible:
    the animation works by redefining which of the four PATTERNS is blank, so a
    cell that is a space can never light up.
    """
    return genart.CODES["BULB%d" % phase]


def perimeter():
    """[(row, col)] clockwise from the top-left corner, each cell once."""
    out = []
    for c in range(FRAME_L, FRAME_R + 1):
        out.append((FRAME_TOP, c))
    for r in range(FRAME_TOP + 1, FRAME_BOT + 1):
        out.append((r, FRAME_R))
    for c in range(FRAME_R - 1, FRAME_L - 1, -1):
        out.append((FRAME_BOT, c))
    for r in range(FRAME_BOT - 1, FRAME_TOP, -1):
        out.append((r, FRAME_L))
    return out


def frame_runs():
    """The marquee as display-list runs -- horizontals long, sides per cell."""
    ring = perimeter()
    if len(ring) % PERIOD:
        raise SystemExit(
            "the marquee ring is %d cells, which is not a whole number of "
            "%d-cell clusters -- the pattern would restart at a seam. Rows "
            "%d..%d by columns %d..%d gives %d; try a frame one row or one "
            "column different."
            % (len(ring), PERIOD, FRAME_TOP, FRAME_BOT, FRAME_L, FRAME_R,
               len(ring)))

    # EVERY cell carries its phase, dark ones included -- see bulb().
    phase = {}
    for i, rc in enumerate(ring):
        phase[rc] = i % PERIOD

    out = []
    # the horizontal sides are one run each -- 27 cells for three bytes of
    # header, where a per-cell entry would cost four bytes per lamp
    for row in (FRAME_TOP, FRAME_BOT):
        text = "".join(chr(bulb(phase[(row, c)]))
                       for c in range(FRAME_L, FRAME_R + 1))
        out.append((row, FRAME_L, text))
    # the verticals cannot be one run, so each is its own single-cell entry
    for r in range(FRAME_TOP + 1, FRAME_BOT):
        for c in (FRAME_L, FRAME_R):
            out.append((r, c, chr(bulb(phase[(r, c)]))))
    return out


# ---------------------------------------------------------------------------
# THE NAME
# ---------------------------------------------------------------------------
#
# Drawn as whole KERNED WORDS and sliced on the character grid -- see
# titleword.py. Each word is three cells tall, so it is three runs.
#
# The interior is rows 2..20 by columns 3..27, so the centre column is 15.
BIG = [
    (8, 9, "KEYSTONE"),         # 12 cells wide
    (12, 11, "KAPERS"),         # 9 cells -- a blank row between the two
]

# Coleco's French card reuses exactly the same large word tiles.
COLECO_BIG = [(6, 12, "KAPERS"), (10, 11, "KEYSTONE")]
COLECO_TEXT = [(8, 8, "les"), (12, 8, "de"),
               (15, 7, "par GARRY KITCHEN")]
# Five-pixel lowercase text, one 8x8 cell per letter. These slots are free
# on TMS targets; some have separate NES-only owners, so load only on Coleco.
LOWER_ROWS = {
    'a': [0, 0, 14, 1, 15, 17, 15, 0],
    'c': [0, 0, 14, 17, 16, 17, 14, 0],
    'd': [1, 1, 15, 17, 17, 17, 15, 0],
    'e': [0, 0, 14, 17, 31, 16, 14, 0],
    'g': [0, 0, 15, 17, 15, 1, 17, 14],
    'h': [16, 16, 30, 17, 17, 17, 17, 0],
    'i': [4, 0, 12, 4, 4, 4, 14, 0],
    'k': [16, 16, 18, 20, 24, 20, 18, 0],
    'l': [12, 4, 4, 4, 4, 4, 14, 0],
    'n': [0, 0, 30, 17, 17, 17, 17, 0],
    'p': [0, 0, 30, 17, 30, 16, 16, 16],
    'r': [0, 0, 22, 25, 16, 16, 16, 0],
    's': [0, 0, 15, 16, 14, 1, 30, 0],
    't': [4, 4, 14, 4, 4, 5, 2, 0],
    'y': [0, 0, 17, 17, 15, 1, 17, 14],
}
LOWER_BLOCKS = [(197, 11), (91, 4)]
LOWER_CODES = dict(zip(sorted(LOWER_ROWS),
                       [c for start, n in LOWER_BLOCKS
                        for c in range(start, start + n)]))


def word_cells():
    """{cell pattern: [(row, col)]} -- every cell the words need, deduped."""
    want = {}
    for row, col, word in BIG:
        grid = titleword.cells(word)
        for cy, cells_row in enumerate(grid):
            for cx, cell in enumerate(cells_row):
                if "#" not in "".join(cell):
                    continue        # blank -- the space character serves
                want.setdefault(tuple(cell), []).append((row + cy, col + cx))
    return want


def free_codes():
    """Character codes nothing else uses, derived rather than written down.

    THE FIRST VERSION OF THIS WAS A LITERAL and it collided with the radar
    canvas: the name's S and T came out as the scanner's green diagonals, on a
    screen with no radar on it, because the clash is in the PATTERN table and
    has nothing to do with what is displayed. Deriving it from genart means a
    future character cannot quietly land on top of the title.
    """
    used = [False] * 256
    for i in range(32, 32 + 59):                    # the font
        used[i] = True
    for _n, code, _a, _f, _b in genart.CHARS:       # the store art
        used[code] = True
    for i in range(genart.SCAN_FIRST,
                   genart.SCAN_FIRST + genart.SCAN_N):
        used[i] = True                              # the radar canvas
    runs, start = [], None
    for i in range(256):
        if not used[i] and start is None:
            start = i
        if used[i] and start is not None:
            runs.append((start, i - start))
            start = None
    if start is not None:
        runs.append((start, 256 - start))
    return sorted(runs, key=lambda r: -r[1])


def allocate():
    """(codes {cell: code}, blocks [(first, count)], patterns [bytes])."""
    want = word_cells()
    order = sorted(want, key=lambda k: min(want[k]))
    runs = free_codes()
    have = sum(n for _s, n in runs)
    if len(order) > have:
        raise SystemExit(
            "the title's name needs %d character codes and only %d are free "
            "(%s). Narrow the letters in titleword.py -- the advance decides "
            "the cell count."
            % (len(order), have,
               ", ".join("%d..%d" % (s, s + n - 1) for s, n in runs)))

    codes, blocks, pats = {}, [], []
    i = 0
    for start, count in runs:
        if i >= len(order):
            break
        n = min(count, len(order) - i)
        blocks.append((start, n))
        for k in range(n):
            codes[order[i + k]] = start + k
            pats += titleword.char_bytes(list(order[i + k]))
        i += n
    return codes, blocks, pats


def big_runs(big=None):
    """The name, as display-list runs -- three per word."""
    codes = allocate()[0]
    out = []
    for row, col, word in BIG if big is None else big:
        grid = titleword.cells(word)
        for cy, cells_row in enumerate(grid):
            text = ""
            for cell in cells_row:
                key = tuple(cell)
                text += chr(codes[key]) if key in codes else " "
            out.append((row + cy, col, text))
    return out


# ---------------------------------------------------------------------------
# THE TEXT
# ---------------------------------------------------------------------------
#
# Centred on column 15, the middle of the interior.
#
# `FIRE TO START` is deliberately NOT here. It is printed by `title_input`, the
# routine that does the reading, so its arrival marks the moment the screen goes
# live -- see DESIGN.md 0e-sexies.
#
# THE ATTRIBUTION IS DELIBERATELY WORDED. The reference card reads
# `COPYRIGHT 1983,1984 ACTIVISION`, which is THEIR notice about THEIR program;
# reproducing it would say this cart is that program. `ORIGINAL 1983 ACTIVISION`
# credits where the game came from and leaves our own line to say what this is.
# NOTHING RUNS TO THE FRAME. The interior is columns 3..27, and a 25-character
# line fills it exactly -- which put the text hard against the side lamps and
# read as crowding rather than as a card. Every line is now 23 or fewer, so
# there is a clear column inside the marquee on both sides.
# THE AUTHOR'S LINE SITS ABOVE THE NAME NOW, not below it as a credit. Reading
# it as a possessive makes one phrase of three lines -- the way the original's
# own box front is laid out -- instead of a logo followed by a footnote. That
# also retires the separate `BY GARRY KITCHEN` line, which is why BIG moved two
# rows down: the name keeps its place on the screen while gaining a line above.
#
# THE WHOLE CARD SITS TWO ROWS LOWER THAN IT USED TO, marquee and all, to free
# row 0 for the score line below. The frame is rows 3..23 where it was 1..21 --
# same 21 x 27, so the lamp ring is the same 92 cells and still divides by the
# chase period, which the check in frame_runs() would otherwise fail.
#
# THE SCORE LINE IS LABELS HERE AND DIGITS AT RUN TIME. `title_score` in
# KEYSTONE.bas writes the numbers.
#
# IT IS JUSTIFIED TO THE MARQUEE, not spaced by eye. `SCORE:` starts at column
# 2, which is FRAME_L, and the HI field ENDS at column 28, which is FRAME_R --
# so the line the card sits under has the same left and right edges as the card
# itself. `HI:` therefore sits at 20..22 and its six digits at 23..28, and the
# score's own six start at 8 (the column the in-game HUD uses too, which is not
# a coincidence worth breaking).
TITLE = [
    (0, 2, "SCORE:"),
    (0, 20, "HI:"),
    (6, 8, "GARRY KITCHEN'S"),
    (18, 4, "2026 UNHUMAN AND CLAUDE"),
]

# ---------------------------------------------------------------------------
# THE END-OF-ROUND MESSAGE BOXES, same format, same walker
# ---------------------------------------------------------------------------
#
# Each is a whole SCENE -- blank bar, text, blank bar -- so a call site is one
# address and one GOSUB instead of three PRINT ATs. The blank rows repeat in
# every scene deliberately: they cost bank bytes, which are plentiful, to save
# fixed-area bytes, which are not.
#
# The visible box is 16x3 at row 13 col 8; GAME OVER sits four rows above.
# NES picture rows are three lower, so their attribute blocks begin at PPU
# rows 16 and 12. Each attribute byte contains FOUR independently selectable
# 16x16 quadrants, not one indivisible 32x32 palette region. nes_boxatt uses
# P1 on the upper quadrants and P3 on the lower quadrants. Their shared navy
# permits a three-row box while retaining scenery on the fourth tile row.
BOX_ROW, BOX_COL, BOX_W = 13, 8, 16

def _line(text):
    """One message line, CENTRED in the box and padded to its full width.

    It was centred by hand and two of the five were not: `GOT HIM!` and
    `TIME UP!` each sat one column left of centre, with the surplus on the
    right. That is invisible in a source listing -- the lines are all the right
    LENGTH, which is the only thing the width check downstream could ask -- and
    on screen it reads as the box having a wider margin on one side.
    """
    if len(text) > BOX_W:
        raise SystemExit("%r is %d wide and the box is %d"
                         % (text, len(text), BOX_W))
    left = (BOX_W - len(text)) // 2
    return " " * left + text + " " * (BOX_W - len(text) - left)


BLANK = " " * BOX_W


def _box(text):
    """A whole message scene: one blank row, the text, one blank row.

    THREE ROWS, BECAUSE FOUR CANNOT BE CENTRED. A four-row box carrying a
    one-row message pads either one above and two below or two above and one
    below, and there is no third option -- both were built and both were
    reported, the first as "an extra row below the message" and the second as
    "an extra border of spacing over the top". Fixing one end moved the fault
    to the other, which is what an impossible constraint feels like from the
    outside.

    On NES, nes_boxatt selects P1 for the top two tile rows and P3 for
    the lower pair. A solid index-2 tile paints only the third row navy,
    matching P1's paper. The fourth row retains its scenery tiles.
    """
    return [BLANK, _line(text), BLANK]


MESSAGES = {
    "msg_gothim": _box("GOT HIM!"),
    "msg_away":   _box("HE GOT AWAY"),
    "msg_plane":  _box("THE BIPLANE"),
    "msg_timeup": _box("TIME'S UP!"),
    "msg_over":   _box("GAME OVER"),
}

# GAME OVER STACKS BELOW THE REASON NOW, NOT ABOVE IT.
#
# It moved down four rows with the others when BOX_ROW did -- it is written as
# an offset from BOX_ROW precisely so it cannot be left behind -- but it stayed
# the TOP of the pair, so on screen it was still the highest thing in the
# middle of the store and still read as sitting too high.
#
# Below is also the only other place it can go. The attribute grid allows a box
# to start on rows 1, 5, 9, 13, 17, 21 and nowhere else (BOX_ROW), so with the
# reason box at 13 its neighbours are 9 and 17 -- there is no nudge available,
# only a side.
#
# And it reads better this way round: what happened, then the consequence.
# "TIME'S UP!" over "GAME OVER" is the order the player learns it in.
MSG_ROW = {
    "msg_gothim": BOX_ROW, "msg_away": BOX_ROW,
    "msg_plane": BOX_ROW, "msg_timeup": BOX_ROW,
    "msg_over": BOX_ROW - 4,
}


def runs_of(name):
    """One message scene as (row, col, text) runs."""
    top = MSG_ROW[name]
    return [(top + i, BOX_COL, t) for i, t in enumerate(MESSAGES[name])]


def coleco_runs():
    text = [(row, col, ''.join(chr(LOWER_CODES[c]) if c in LOWER_CODES else c
                              for c in line))
            for row, col, line in COLECO_TEXT]
    return (frame_runs() + big_runs(COLECO_BIG) + text
            + [run for run in TITLE if run[2] != "GARRY KITCHEN'S"])


def table(runs=None, extra_codes=()):
    """A display list as bytes, with the checks that make it safe."""
    if runs is None:
        runs = frame_runs() + big_runs() + TITLE
    art = set(allocate()[0].values()) | set(genart.CODES["BULB%d" % p] for p in range(4))
    art.update(extra_codes)
    out, seen = [], {}
    for row, col, text in runs:
        if not 0 <= row < 24:
            raise SystemExit("row %d is off screen: %r" % (row, text))
        if col + len(text) > COLS:
            raise SystemExit(
                "%r at row %d col %d runs to column %d -- a PRINT past column "
                "31 wraps onto the NEXT row and silently overwrites it"
                % (text, row, col, col + len(text)))
        if len(text) > 255:
            raise SystemExit("%r is longer than one length byte" % text)
        for i, ch in enumerate(text):
            c = col + i
            if ch == " ":
                continue            # a run's own padding writes nothing new
            if (row, c) in seen:
                raise SystemExit(
                    "row %d column %d is written twice: %r and %r"
                    % (row, c, seen[(row, c)], text))
            seen[(row, c)] = text
            if ord(ch) in art:
                continue
            if not 32 <= ord(ch) <= 90:
                raise SystemExit(
                    "%r contains %r, outside the loaded font (32..90)"
                    % (text, ch))
        out += [row, col, len(text)] + [ord(c) for c in text]
    out.append(END)
    # EVERY DATA BLOCK MUST BE AN EVEN NUMBER OF BYTES -- an odd run leaves the
    # assembler's location counter odd and silently misaligns every word table
    # after it (CLAUDE.md 3A). A second terminator is the cheapest padding.
    if len(out) % 2:
        out.append(END)
    return out


def main():
    titleword.check_heights()
    codes, blocks, pats = allocate()
    # Light yellow title text matches the latest TI/Coleco HUD and messages.
    # NES maps this ink to its existing gold palette entry.
    cbyte = (genart.LYELL << 4) | genart.HUD_BG
    unused = {c for start, n in free_codes() for c in range(start, start + n)}
    unused -= set(codes.values())
    assert set(LOWER_CODES.values()) <= unused, 'lowercase overlaps existing art'
    assert len(LOWER_CODES) == sum(n for _, n in LOWER_BLOCKS)

    with io.open(FACE_OUT, 'w', encoding='utf-8', newline='') as fh:
        fh.write("\t' ==================================================\n")
        fh.write("\t' THE TITLE'S NAME -- whole kerned words, sliced\n")
        fh.write("\t' Generated by assets/gentitle.py from titleword.py.\n")
        fh.write("\t' Do not edit here; edit the glyphs and rebuild.\n")
        fh.write("\t'\n")
        fh.write("\t' %d distinct cells; blanks use the space character and\n"
                 % len(codes))
        fh.write("\t' repeated cells share a code. setup_font must load them\n")
        fh.write("\t' with EXACTLY these arguments:\n")
        for k, (start, count) in enumerate(blocks):
            fh.write("\t'     DEFINE CHAR  %3d,%2d,tfont_pat%d\n"
                     % (start, count, k))
            fh.write("\t'     DEFINE COLOR %3d,%2d,tfont_col%d\n"
                     % (start, count, k))
        fh.write("\t'\n")
        fh.write("\t' LIVES IN BANK 2 -- read once by those DEFINEs.\n")
        fh.write("\t' ==================================================\n")
        at = 0
        for k, (start, count) in enumerate(blocks):
            chunk = pats[at * 8:(at + count) * 8]
            at += count
            fh.write("\ntfont_pat%d:\t' codes %d..%d\n"
                     % (k, start, start + count - 1))
            for i in range(0, len(chunk), 8):
                fh.write("\tDATA BYTE %s\n"
                         % ",".join("$%02X" % b for b in chunk[i:i + 8]))
            # EIGHT COLOUR BYTES PER CHARACTER, one per scan line, not one
            fh.write("\ntfont_col%d:\n" % k)
            n = count * 8
            for i in range(0, n, 8):
                fh.write("\tDATA BYTE %s\n"
                         % ",".join(["$%02X" % cbyte] * min(8, n - i)))
        fh.write("\n#if COLECOVISION\n")
        letters = sorted(LOWER_CODES, key=LOWER_CODES.get)
        for k, (start, count) in enumerate(LOWER_BLOCKS):
            fh.write("\nclower_pat%d:\n" % k)
            for code in range(start, start + count):
                letter = next(c for c in letters if LOWER_CODES[c] == code)
                fh.write("\tDATA BYTE %s\n" % ','.join(
                    '$%02X' % (v << 2) for v in LOWER_ROWS[letter]))
            fh.write("\nclower_col%d:\n" % k)
            for _ in range(count):
                fh.write("\tDATA BYTE %s\n" % ','.join(['$%02X' % cbyte] * 8))
        fh.write("#endif\n")
    print("wrote %s -- %d distinct cells in %d block(s) (%s), %d bytes"
          % (os.path.normpath(FACE_OUT), len(codes), len(blocks),
             ", ".join("%d..%d" % (a, a + n - 1) for a, n in blocks),
             len(pats) * 2))

    data = table()
    with io.open(DL_OUT, 'w', encoding='utf-8', newline='') as fh:
        fh.write("\t' ==================================================\n")
        fh.write("\t' THE TITLE SCREEN, AS A DISPLAY LIST\n")
        fh.write("\t' Generated by assets/gentitle.py -- do not edit here.\n")
        fh.write("\t'\n")
        fh.write("\t' row, col, length, then `length` bytes; 255 ends.\n")
        fh.write("\t' Walked by title_draw only.\n")
        fh.write("\t'\n")
        fh.write("\t' LIVES IN BANK 2, with the fonts, because it is read ONCE\n")
        fh.write("\t' -- at boot and on a return to the title. title_draw\n")
        fh.write("\t' selects bank 2 around its walk and restores bank 1.\n")
        fh.write("\t' The message boxes in title.bas are the same format and\n")
        fh.write("\t' CANNOT come with it: they are read when a round ends.\n")
        fh.write("\t' ==================================================\n")
        fh.write("\n#if COLECOVISION\ntitle_tbl:\n")
        french = table(coleco_runs(), LOWER_CODES.values())
        for i in range(0, len(french), 8):
            fh.write("\tDATA BYTE %s\n" % ','.join(str(b) for b in french[i:i + 8]))
        fh.write("#else\ntitle_tbl:\n")
        for i in range(0, len(data), 8):
            fh.write("\tDATA BYTE %s\n"
                     % ",".join(str(b) for b in data[i:i + 8]))
        fh.write("#endif\n")

    with io.open(OUT, 'w', encoding='utf-8', newline='') as fh:
        fh.write("\t' ==================================================\n")
        fh.write("\t' THE END-OF-ROUND MESSAGE BOXES\n")
        fh.write("\t' Generated by assets/gentitle.py -- do not edit here.\n")
        fh.write("\t'\n")
        fh.write("\t' row, col, length, then `length` bytes; 255 ends -- the\n")
        fh.write("\t' same format as the title's display list, walked by the\n")
        fh.write("\t' same run_list, from do_catch and lose_kop.\n")
        fh.write("\t'\n")
        fh.write("\t' THESE STAY IN BANK 1. They are read MID-GAME, when a\n")
        fh.write("\t' round ends, so they must sit on the permanently mapped\n")
        fh.write("\t' page. The display list went to bank 2 (titledl.bas);\n")
        fh.write("\t' these following it would fail exactly when a life is\n")
        fh.write("\t' lost, and silently.\n")
        fh.write("\t' ==================================================\n")
        for name in sorted(MESSAGES):
            for t in MESSAGES[name]:
                if len(t) != BOX_W:
                    raise SystemExit(
                        "%s line %r is %d wide, not %d -- the box would have "
                        "a ragged edge" % (name, t, len(t), BOX_W))
            block = table(runs_of(name))
            fh.write("\n%s:\n" % name)
            for i in range(0, len(block), 8):
                fh.write("\tDATA BYTE %s\n"
                         % ",".join(str(b) for b in block[i:i + 8]))

    runs = frame_runs() + big_runs() + TITLE
    print("wrote %s -- %d runs (%d marquee, %d name), %d bytes  [BANK 2]"
          % (os.path.normpath(DL_OUT), len(runs), len(frame_runs()),
             len(big_runs()), len(data)))
    print("wrote %s -- %d message boxes  [BANK 1, read when a round ends]"
          % (os.path.normpath(OUT), len(MESSAGES)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
