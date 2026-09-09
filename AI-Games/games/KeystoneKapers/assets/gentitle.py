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
FRAME_TOP, FRAME_BOT = 1, 21
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
    (4, 9, "KEYSTONE"),         # 12 cells wide
    (8, 11, "KAPERS"),          # 9 cells -- a blank row between the two
]


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


def big_runs():
    """The name, as display-list runs -- three per word."""
    codes = allocate()[0]
    out = []
    for row, col, word in BIG:
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
TITLE = [
    (13, 8, "BY GARRY KITCHEN"),
    (15, 4, "2026 UNHUMAN AND CLAUDE"),
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
# THE ROWS ARE THE ONES THE PRINT ATs USED, checked rather than assumed:
# 330 = row 10 col 10, 362 = row 11, 394 = row 12, so the reason box's top row
# is 10. GAME OVER was 266 = row 8 and 298 = row 9 -- two rows above, not three.
BOX_ROW, BOX_COL, BOX_W = 10, 10, 13

MESSAGES = {
    "msg_gothim": ["             ", "  GOT HIM!   ", "             "],
    "msg_away":   ["             ", " HE GOT AWAY ", "             "],
    "msg_plane":  ["             ", " THE BIPLANE ", "             "],
    "msg_timeup": ["             ", "  TIME UP!   ", "             "],
    "msg_over":   ["             ", "  GAME OVER  "],
}

MSG_ROW = {
    "msg_gothim": BOX_ROW, "msg_away": BOX_ROW,
    "msg_plane": BOX_ROW, "msg_timeup": BOX_ROW,
    "msg_over": BOX_ROW - 2,
}


def runs_of(name):
    """One message scene as (row, col, text) runs."""
    top = MSG_ROW[name]
    return [(top + i, BOX_COL, t) for i, t in enumerate(MESSAGES[name])]


def table(runs=None):
    """A display list as bytes, with the checks that make it safe."""
    if runs is None:
        runs = frame_runs() + big_runs() + TITLE
    art = set(allocate()[0].values()) | set(genart.CODES["BULB%d" % p] for p in range(4))
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
    cbyte = (genart.WHITE << 4) | genart.HUD_BG

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
    print("wrote %s -- %d distinct cells in %d block(s) (%s), %d bytes"
          % (os.path.normpath(FACE_OUT), len(codes), len(blocks),
             ", ".join("%d..%d" % (a, a + n - 1) for a, n in blocks),
             len(pats) * 2))

    data = table()
    with io.open(OUT, 'w', encoding='utf-8', newline='') as fh:
        fh.write("\t' ==================================================\n")
        fh.write("\t' THE TITLE SCREEN, AS A DISPLAY LIST\n")
        fh.write("\t' Generated by assets/gentitle.py -- do not edit here.\n")
        fh.write("\t'\n")
        fh.write("\t' row, col, length, then `length` bytes; 255 ends.\n")
        fh.write("\t' Walked by title_draw, and by do_catch and lose_kop for\n")
        fh.write("\t' the message boxes below.\n")
        fh.write("\t' ==================================================\n")
        fh.write("\ntitle_tbl:\n")
        for i in range(0, len(data), 8):
            fh.write("\tDATA BYTE %s\n"
                     % ",".join(str(b) for b in data[i:i + 8]))

        fh.write("\n\t' ---- the end-of-round message boxes, same format\n")
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
    print("wrote %s -- %d runs (%d marquee, %d name), %d bytes"
          % (os.path.normpath(OUT), len(runs), len(frame_runs()),
             len(big_runs()), len(data)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
