#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""The title screen, as data -- writes src/title.bas.

WHY THE TITLE IS A TABLE
------------------------
It was twelve `PRINT AT n,"..."` statements, and CVBasic embeds a string literal
in the FIXED AREA -- the one budget that cannot be grown (linkticart writes
exactly three loader pages and discards the rest; they are the 32K expansion's
RAM at >A000, not cart ROM). 190 characters of title text sat in the scarcest
place in the program.

Here it is a display list in a ROM bank, walked by a dozen statements in
`title_draw`. That buys the bytes back once -- and, more usefully, means the
title's content and layout stop costing code at all. A better title screen
becomes an edit to THIS FILE plus a rebuild, not a fight with the byte cap.

THIS FILE IS THE SINGLE SOURCE OF TRUTH for what the title says, and
`checklayout.py` imports `TITLE` from here rather than parsing `PRINT AT` out of
the source. That matters: the whole method of that gate is reading `PRINT AT
n,"literal"` to catch a string running past column 31 or a write landing inside
another label, and moving the text into a table would otherwise have made the
title INVISIBLE to it -- trading a build gate for bytes. Importing keeps the
coverage and keeps one copy of the text.

THE FORMAT is a flat list of runs:

    row, col, length, byte * length      repeated
    255                                  ends it

Row and column rather than a 16-bit screen offset, because reassembling a 16-bit
offset from two bytes needs a multiply, and on the TMS9900 `MPY` clobbers r0 --
reading the product's variable on the next line returns the HIGH word (CLAUDE.md
3A). `row * 32` by five doublings has no such hazard and is smaller.
"""

import io
import os
import sys

import genart
import titleface

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, os.pardir, 'src', 'title.bas')
# THE DISPLAY FACE GOES IN A SEPARATE FILE because it goes in a different BANK.
# It is 640 bytes of pattern and colour and bank 1 had 370 free -- but it is
# read once, by a DEFINE at setup, so it belongs in bank 2 with the font.
FACE_OUT = os.path.join(HERE, os.pardir, 'src', 'titlefont.bas')

# Where the display face is loaded is decided by titleface.FREE_RUNS -- the
# character table has no run long enough for it, so it goes in two pieces. See
# the note there; the first attempt at a single block ran into the radar.

COLS = 32

# (row, column, text). The character codes ARE ASCII: the font is loaded with
# `DEFINE CHAR 32,59`, so codes 32..90 are space through 'Z' and a byte of text
# needs no translation.
#
# `FIRE TO START` is deliberately NOT here. It is printed by `title_input`, the
# routine that does the reading, so its arrival marks the moment the screen goes
# live -- see DESIGN.md 0e-sexies. Moving it into this table would print it with
# the rest and undo that.
# ---------------------------------------------------------------------------
# THE MARQUEE FRAME
# ---------------------------------------------------------------------------
#
# A ring of bulbs around the screen, after the Activision title card: a theatre
# marquee. The reference has a white panel inside a black surround; ours keeps
# the dark blue field it already had, so the bulbs sit straight on it and the
# screen still has exactly one background colour.
#
# IT NEEDS NO NEW MECHANISM. A bulb is one character and the frame is just runs
# of characters at fixed positions -- which is precisely what the display list
# already is. So the whole frame is bank data, drawn by the same `run_list`
# walker as the text, and costs the fixed area nothing at all.
#
# DENSE ALONG THE TOP AND BOTTOM, SPARSE DOWN THE SIDES, which is how the
# reference reads and is not an economy: bulbs every other cell horizontally
# give a run of lamps, while the sides carry fewer, further apart. It is also
# much cheaper -- a horizontal run is ONE entry of 28 bytes, but a vertical one
# would be a separate three-byte entry per bulb, so sparse sides cost a
# fraction of dense ones.
FRAME_TOP, FRAME_BOT = 1, 22
FRAME_L, FRAME_R = 1, 30

# CLUSTERS OF THREE, as the reference has them -- three lamps, a gap, three
# lamps. Every-other-cell was tried first and reads as a dotted rule rather than
# a marquee: it is the grouping that says "sign", not the bulbs.
#
# THE CLUSTERS ARE PLACED, NOT REPEATED, and that is the whole trick. Repeating
# "###." across the width leaves whatever the width happens to give at the
# right-hand end; mirroring a repeated half instead puts two clusters back to
# back at the seam, which came out as a SEVEN-BULB RUN through the middle of the
# top row -- symmetric, and plainly wrong.
#
# So a fixed number of clusters is spread across the width and the remainder
# goes into the GAPS, distributed from the middle outwards so the row stays a
# palindrome. Gaps of two and three read as even; a doubled cluster does not.
#
# SIX, NOT SEVEN. Seven clusters in thirty cells cannot be symmetric at all --
# the middle one would have to start at 13.5 -- and it leaves single-cell gaps
# that make the lamps touch.
CLUSTERS = 6

# rows down each side. Evenly spaced between the corners, and deliberately not
# every row: at one per row the sides read as two solid bars.
SIDE_ROWS = [4, 7, 10, 13, 16, 19]


def bulb():
    """The bulb's character code, taken from genart rather than typed here.

    A HAND-WRITTEN CHARACTER NUMBER IS A BUG WAITING FOR A RENAME -- the store
    table has been renumbered before and a literal here would have gone stale
    silently, drawing whatever now occupies that code.
    """
    return genart.CODES["BULB"]


def bulb_row(width, n=None):
    """[bool] -- `n` clusters of three, spread symmetrically across `width`."""
    n = CLUSTERS if n is None else n
    gaps_n = n - 1
    spare = width - 3 * n
    if spare < gaps_n:
        raise SystemExit(
            "a %d-cell marquee row cannot hold %d clusters of three with a gap "
            "between each -- it needs %d cells and has %d"
            % (width, n, 4 * n - 1, width))
    gaps = [spare // gaps_n] * gaps_n
    # THE REMAINDER GOES INTO SYMMETRIC PAIRS OF GAPS, working outwards from
    # the middle. Handing it out one gap at a time in "distance from centre"
    # order is not the same thing and does not stay a palindrome -- it produced
    # [2,3,3,2,2], which is a sign that leans right.
    extra = spare % gaps_n
    mid = gaps_n // 2
    if extra % 2 and gaps_n % 2:
        gaps[mid] += 1          # the exact middle can take one on its own
        extra -= 1
    lo = mid - 1
    hi = mid + 1 if gaps_n % 2 else mid
    while extra >= 2 and lo >= 0:
        gaps[lo] += 1
        gaps[hi] += 1
        extra -= 2
        lo -= 1
        hi += 1
    if gaps != gaps[::-1]:
        # a palindrome is the point; say so rather than drawing a lopsided sign
        raise SystemExit("marquee gaps %r are not symmetric" % (gaps,))

    out = []
    for i in range(n):
        out += [True] * 3
        if i < gaps_n:
            out += [False] * gaps[i]
    return out


def big_runs():
    """The display-face words, as display-list runs.

    A letter is two cells across and two down, so a word is TWO runs: the top
    halves of every letter, then the bottom halves. That keeps it in the same
    `row, col, bytes` format as the rest of the table and needs nothing new in
    the walker.
    """
    out = []
    for row, col, word in BIG:
        top, bot = [], []
        for ch in word:
            if ch == " ":
                top += [" ", " "]
                bot += [" ", " "]
                continue
            q = [titleface.code_of(ch, i) for i in range(4)]
            top += [chr(q[0]), chr(q[1])]
            bot += [chr(q[2]), chr(q[3])]
        out.append((row, col, "".join(top)))
        out.append((row + 1, col, "".join(bot)))
    return out


def frame_runs():
    """The marquee, as display-list runs."""
    ch = chr(bulb())
    width = FRAME_R - FRAME_L + 1
    row = "".join(ch if lit else " " for lit in bulb_row(width))
    out = [(FRAME_TOP, FRAME_L, row), (FRAME_BOT, FRAME_L, row)]
    for r in SIDE_ROWS:
        out.append((r, FRAME_L, ch))
        out.append((r, FRAME_R, ch))
    return out


# The text, centred inside the frame -- columns 2..29, so the middle is 16.
#
# `DUCK PLANES AND HIGH ONES` used to start at column 6, which put its last
# character in column 30 -- the frame's right-hand column. The generator's own
# double-write check catches that, which is why the text moved rather than the
# frame.
# LAID OUT AS A TITLE CARD, after the Activision original: the name stacked and
# spaced at the top, then who made it, then who made this.
#
# THE TITLE IS SPACED, NOT ENLARGED. `K E Y S T O N E` reads as a display line
# at a glance where `KEYSTONE` reads as a sentence, and it costs nothing: two
# genuinely large letters would need a 2x2 cell each -- about ten distinct
# letters, forty characters, some 640 bytes of pattern and colour -- and bank 1
# has 362 free. That is a real option, but it needs the store art moved to bank
# 2 first (it is read once at setup, so it qualifies), and it is a bigger change
# than a layout.
#
# THE ATTRIBUTION IS DELIBERATELY WORDED. The reference card reads
# `COPYRIGHT 1983,1984 ACTIVISION`, which is THEIR notice about THEIR program;
# reproducing it here would say this cart is that program. `ORIGINAL 1983
# ACTIVISION` credits where the game came from and leaves our own line to say
# what this is -- honest homage rather than an imitation of a rights notice.
# THE NAME IS DRAWN IN THE DISPLAY FACE, two cells per letter, so it is two
# rows of the name table per word -- see big_runs. Spacing the ordinary font out
# was the previous approximation and it still read as body text with gaps in it.
BIG = [
    (3, 8, "KEYSTONE"),         # 8 letters x 2 cells = 16 cells, centred
    (6, 10, "KAPERS"),          # 6 x 2 = 12 cells
]

TITLE = [
    (9, 8, "BY GARRY KITCHEN"),
    (11, 4, "ORIGINAL 1983 ACTIVISION"),
    (12, 4, "2026 UNHUMAN AND CLAUDE"),

    (14, 5, "STICK RUN     FIRE JUMP"),
    (15, 3, "DOWN DUCK     UP ELEVATOR"),

    (17, 4, "JUMP CARTS AND LOW BALLS"),
    (18, 3, "DUCK PLANES AND HIGH ONES"),
]

# THE END-OF-ROUND MESSAGE BOXES, same format, same walker.
#
# Each is a whole SCENE -- the blank bar above, the text, the blank bar below --
# rather than three separate writes, so a call site is one address and one
# GOSUB instead of three PRINT ATs. The blank rows are repeated in every scene
# and that is deliberate: they cost bank bytes, which are plentiful, to save
# fixed-area bytes, which are not. Spending the abundant budget for the scarce
# one is the whole point (CLAUDE.md 3A warns about doing it backwards).
#
# THIRTEEN WIDE AT COLUMN 10, which is the longest message plus one space each
# side, centred on the screen's own centre. Every font character is black on
# the HUD's dark blue, so a row of SPACES is a solid bar -- the frame costs no
# new characters. Every string is padded to exactly 13 so the box has straight
# edges; the generator checks it.
#
# THE ROWS ARE THE ONES THE PRINT ATs USED, and they were checked rather than
# assumed: 330 = row 10 col 10, 362 = row 11, 394 = row 12, so the reason box's
# TOP row is 10. GAME OVER was 266 = row 8 and 298 = row 9, which is two rows
# above the box, not three. Getting either wrong moves the message and nothing
# in the build would have said so.
BOX_ROW, BOX_COL, BOX_W = 10, 10, 13

MESSAGES = {
    "msg_gothim": ["             ", "  GOT HIM!   ", "             "],
    "msg_away":   ["             ", " HE GOT AWAY ", "             "],
    "msg_plane":  ["             ", " THE BIPLANE ", "             "],
    "msg_timeup": ["             ", "  TIME UP!   ", "             "],
    # stacked ABOVE the reason, two rows higher, so GAME OVER appears with the
    # reason rather than replacing it
    "msg_over":   ["             ", "  GAME OVER  "],
}

# where each scene's first row sits: the reason boxes at row 10, the GAME OVER
# overlay two rows above them so it stacks ON TOP of the reason rather than
# replacing it
MSG_ROW = {
    "msg_gothim": BOX_ROW, "msg_away": BOX_ROW,
    "msg_plane": BOX_ROW, "msg_timeup": BOX_ROW,
    "msg_over": BOX_ROW - 2,
}

END = 255


def runs_of(name):
    """One message scene as (row, col, text) runs."""
    top = MSG_ROW[name]
    return [(top + i, BOX_COL, t) for i, t in enumerate(MESSAGES[name])]


def table(runs=None):
    """A display list as bytes, with the checks that make it safe."""
    out = []
    seen = {}
    if runs is None:
        runs = frame_runs() + big_runs() + TITLE
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
        for c in range(col, col + len(text)):
            if (row, c) in seen:
                raise SystemExit(
                    "row %d column %d is written twice: %r and %r"
                    % (row, c, seen[(row, c)], text))
            seen[(row, c)] = text
        for ch in text:
            if ord(ch) == bulb():
                continue            # a marquee bulb, from the store table
            if ord(ch) in titleface.codes():
                continue            # a display-face quadrant
            if not 32 <= ord(ch) <= 90:
                raise SystemExit(
                    "%r contains %r, which is outside the loaded font "
                    "(codes 32..90)" % (text, ch))
        out += [row, col, len(text)] + [ord(c) for c in text]
    out.append(END)
    # EVERY DATA BLOCK MUST BE AN EVEN NUMBER OF BYTES. An odd run leaves the
    # assembler's location counter odd and silently misaligns every word table
    # defined after it (CLAUDE.md 3A). A second terminator is the cheapest
    # padding there is -- the walker stops at the first.
    if len(out) % 2:
        out.append(END)
    return out


def main():
    data = table()
    with io.open(OUT, 'w', encoding='utf-8', newline='') as fh:
        fh.write("\t' ==================================================\n")
        fh.write("\t' THE TITLE SCREEN, AS A DISPLAY LIST\n")
        fh.write("\t' Generated by assets/gentitle.py -- do not edit here.\n")
        fh.write("\t' Edit TITLE in that file and rebuild.\n")
        fh.write("\t'\n")
        fh.write("\t' row, col, length, then `length` ASCII bytes; 255 ends.\n")
        fh.write("\t' Walked by title_draw. Lives in a ROM bank, so the text\n")
        fh.write("\t' costs no fixed-area bytes at all.\n")
        fh.write("\t' ==================================================\n")
        fh.write("\ntitle_tbl:\n")
        for i in range(0, len(data), 8):
            fh.write("\tDATA BYTE %s\n"
                     % ",".join(str(b) for b in data[i:i + 8]))

        fh.write("\n\t' ---- the end-of-round message boxes, same format\n")
        for name in sorted(MESSAGES):
            block = table(runs_of(name))
            for t in MESSAGES[name]:
                if len(t) != BOX_W:
                    raise SystemExit(
                        "%s line %r is %d wide, not %d -- the box would have "
                        "a ragged edge" % (name, t, len(t), BOX_W))
            fh.write("\n%s:\n" % name)
            for i in range(0, len(block), 8):
                fh.write("\tDATA BYTE %s\n"
                         % ",".join(str(b) for b in block[i:i + 8]))

    # ---- the display face, into its own file for bank 2 ----
    face = titleface.patterns()
    runsdef = titleface.blocks()
    cbyte = (genart.WHITE << 4) | genart.HUD_BG
    with io.open(FACE_OUT, 'w', encoding='utf-8', newline='') as fh:
        fh.write("\t' ==================================================\n")
        fh.write("\t' THE TITLE'S DISPLAY FACE -- 16x16 letters\n")
        fh.write("\t' Generated by assets/gentitle.py from titleface.py.\n")
        fh.write("\t' Do not edit here; edit the glyphs and rebuild.\n")
        fh.write("\t'\n")
        fh.write("\t' Four characters per letter: TL TR BL BR, in the order\n")
        fh.write("\t' %s\n" % " ".join(titleface.letters()))
        fh.write("\t'\n")
        fh.write("\t' IN TWO PIECES, because the character table has no run\n")
        fh.write("\t' long enough -- see titleface.FREE_RUNS. setup_font must\n")
        fh.write("\t' load them with EXACTLY these arguments:\n")
        for k, (start, count) in enumerate(runsdef):
            fh.write("\t'     DEFINE CHAR  %3d,%2d,tfont_pat%d\n"
                     % (start, count, k))
            fh.write("\t'     DEFINE COLOR %3d,%2d,tfont_col%d\n"
                     % (start, count, k))
        fh.write("\t'\n")
        fh.write("\t' LIVES IN BANK 2 -- read once by those DEFINEs, never\n")
        fh.write("\t' during play.\n")
        fh.write("\t' ==================================================\n")
        at = 0
        for k, (start, count) in enumerate(runsdef):
            chunk = face[at * 8:(at + count) * 8]
            at += count
            fh.write("\ntfont_pat%d:\t' codes %d..%d\n"
                     % (k, start, start + count - 1))
            for i in range(0, len(chunk), 8):
                fh.write("\tDATA BYTE %s\n"
                         % ",".join("$%02X" % b for b in chunk[i:i + 8]))
            # EIGHT COLOUR BYTES PER CHARACTER, one per scan line -- not one
            # (CLAUDE.md 3A). Lamp-white letters on the HUD's dark blue.
            fh.write("\ntfont_col%d:\n" % k)
            n = count * 8
            for i in range(0, n, 8):
                fh.write("\tDATA BYTE %s\n"
                         % ",".join(["$%02X" % cbyte] * min(8, n - i)))
    print("wrote %s -- %d letters, %d characters in %d blocks (%s), %d bytes"
          % (os.path.normpath(FACE_OUT), len(titleface.letters()),
             len(face) // 8, len(runsdef),
             ", ".join("%d..%d" % (a, a + n - 1) for a, n in runsdef),
             len(face) * 2))

    runs = frame_runs() + big_runs() + TITLE
    chars = sum(len(t) for _r, _c, t in runs)
    print("wrote %s -- %d runs (%d frame, %d display), %d characters, %d bytes"
          % (os.path.normpath(OUT), len(runs), len(frame_runs()),
             len(big_runs()), chars, len(data)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
