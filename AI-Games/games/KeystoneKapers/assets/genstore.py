#!/usr/bin/env python3
"""Keystone Kapers store map -- band templates + the per-(screen,level) index.

THE STORE IS 8 SCREENS x 4 LEVELS = 32 BANDS, and storing 32 literal 5x32
char blocks would be 5,120 bytes of the one budget that actually binds (the
24,336-byte TI fixed area).  Instead there are EIGHT templates and a 32-byte
index saying which template each band uses -- about 1.3 KB for the entire
building.

Every template is 5 rows x 32 cols = 160 bytes:

    rows 0-3   air        32 px, which is exactly the headroom budget in
                          DESIGN.md 2 -- a 16 px Kelly plus a 14 px jump
    row  4     floor slab the surface everything stands ON.  An actor's feet
                          rest at the TOP pixel of this row.

All eight live in ONE contiguous block under ONE label, so a blit is
`SCREEN stor_tpl, tpl*160, row*32, 32, 5, 32` with no label ladder -- RallyX
needed a 4-way IF over its maze tables because SCREEN needs a literal label
and a label cannot be chosen by a variable.  One block sidesteps that.

160 is EVEN, so the block cannot leave the assembler's location counter odd
and misalign the word tables after it (CLAUDE.md 3A).

Run:  python3 genstore.py            writes ../src/store.bas
      python3 genstore.py --preview  also prints the store as ASCII
"""

import os
import sys

# CHARACTER CODES COME FROM genart.py, they are not written down twice.
# This file used to keep its own copy "in sync by hand", and genart.py's table
# has been renumbered three times since -- each renumbering a chance for the
# two lists to disagree silently, which is exactly how a collectible ended up
# drawing an exit door. globals().update() drops every name (SLAB, SHELFT,
# ESCW0 ...) in at its real value, so a name that no longer exists is an
# immediate NameError rather than a wrong picture.
from genart import CODES, ESC_W_GRID, ESC_E_GRID

globals().update(CODES)

W = 32          # columns in a screen
H = 5           # rows in a band

# The escalator boarding zones and the elevator doorway, in COLUMNS.  The
# source turns these into pixel ranges; they are here because they are
# properties of the ART, and a boarding zone that does not line up with the
# drawn escalator is a step that does nothing.
ESC_COLS = 15            # the flight is fifteen characters across
ESC_C0_W = 1             # west flight occupies cols 1-15
ESC_C0_E = W - 16        # east flight occupies cols 16-30
ESC_W_COLS = (0, 6)      # west escalator occupies cols 0-6
ESC_E_COLS = (25, 31)    # east escalator occupies cols 25-31
ELEV_COLS = (14, 17)     # elevator doorway, 4 cols = 32 px
ELEV_ROWS = (0, 3)       # doorway rows -- the FULL band, as the reference


def blank(fill):
    return [[fill] * W for _ in range(H)]


def slab_row(row):
    for c in range(W):
        row[c] = SLAB


# TWO QUIET BLOCKS PER SCREEN, and a lot of plain green. An earlier version put
# four or five detailed units on every screen, which is busy and hard to read --
# and it is not what the game looks like. The 2600's aisles are mostly empty.
# THE STORE HAS TWO KINDS OF FURNITURE AND THEY ARE DIFFERENT SHAPES.
# This used to be two wide two-row blocks, one blue and one grey, which is not
# what the reference draws and is why the aisles read as flat. The reference
# has WIDE BLUE COUNTERS standing on the floor bar -- roughly a third of a
# screen, half a band tall -- and, separately, NARROW FULL-HEIGHT PILLARS, one
# character wide, spaced regularly down the aisle. The pillars are what give
# the store depth and a sense of travel as the screens flip; a grey slab in
# the same shape as the blue one gave neither.
def _pillars(t, cols):
    for c in cols:
        for r in range(4):
            t[r][c] = COUNTR


def _counter(t, c0, c1):
    """A counter stands ON the floor: bottom half of the band only."""
    for c in range(c0, c1):
        t[2][c] = SHELFT
        t[3][c] = SHELFB


def t_aisle_a():
    t = blank(WALL)
    _pillars(t, (4, 11, 20, 27))
    _counter(t, 14, 19)
    slab_row(t[4])
    return t


def t_aisle_b():
    t = blank(WALL)
    _pillars(t, (7, 15, 24))
    _counter(t, 2, 6)
    _counter(t, 18, 23)
    slab_row(t[4])
    return t


def t_escalator(west):
    """A staircase climbing OUT of this band toward the ceiling.

    It is drawn in the band you are LEAVING -- the top of the flight meets the
    slab of the band above, which is that floor's ceiling, so no arrival art
    is needed on the floor you land on.

    THE END SCREENS CARRY NOTHING BUT THE ESCALATOR. No shelving, no counters.
    They are the turning points of a three-traverse climb, and the player
    arrives at them under time pressure looking for one thing; decorating them
    only makes the thing they came for harder to pick out.
    """
    t = blank(WALL)
    slab_row(t[4])

    # THE FLIGHT IS PLACED FROM THE RENDERED GRID, cell for cell. genart.py
    # draws one whole flight as a 64x40 bitmap -- two rails eight pixels apart
    # at 1:2, closed at both ends, with a stepped wedge every eight pixels --
    # and slices it into characters. Six distinct cells cover a flight. Doing
    # it this way is why the shape finally matches the reference: nobody is
    # hand-drawing a tile and hoping it lines up with its neighbours.
    #
    # The last grid row lands on the SLAB row on purpose, so the foot of the
    # flight cuts through the floor line exactly as it does in the original.
    # THE FLIGHT IS SIX ROWS TALL AND THE BAND IS FIVE, so its top row is not
    # ours to draw: the head genuinely belongs to the floor above, and the game
    # stamps that row in when the screen is drawn (esc_head in KEYSTONE.bas).
    # This is the "crossing over" the ColecoVision does -- the flight runs from
    # one floor line THROUGH to the next rather than sitting inside one band.
    # FOUR ROWS, WHICH IS EXACTLY THE BAND'S AIR -- rows 0-3, never row 4.
    # Row 4 is the floor bar, and a cell carrying both the bar and the flight
    # would need four colours in one 8x1 scan line where the VDP allows two.
    # So anything drawn over a bar erases it: that is what wiped this floor's
    # line and, through the head stamp, the whole storey above. The flight now
    # runs from the top of one bar to the underside of the next, which is what
    # connects the floors without destroying either.
    # ROWS 1-4 ARE THE STAIRCASE and they fill the band's air exactly. Row 0
    # is the head cap -- the handrail's horizontal turn -- which sits one row
    # higher, in the floor above, and is stamped in at run time (esc_cap).
    # That is the only part that crosses a floor bar, and the reference
    # crosses it in the same place.
    grid = ESC_W_GRID if west else ESC_E_GRID
    pre = "ESCW" if west else "ESCE"
    c0 = ESC_C0_W if west else ESC_C0_E
    for r in range(2, 6):
        for c in range(ESC_COLS):
            cell = grid[r][c]
            if cell is not None:
                t[r - 2][c0 + c] = CODES["%s%d" % (pre, cell)]

    for r in range(4):
        t[r][0 if west else W - 1] = ENDWALL
    return t


def t_endwall(west):
    """An end screen with no escalator: bare, and walled.

    Without something solid in the extreme column the player runs into the edge
    of the screen and the building appears simply to stop -- which reads as
    though they ought to be able to keep going, and then as though the game has
    stuck them. A wall answers the question before they ask it.
    """
    t = blank(WALL)
    for r in range(4):
        t[r][0 if west else W - 1] = ENDWALL
    slab_row(t[4])
    return t


def t_elev():
    t = blank(WALL)
    c0, c1 = ELEV_COLS
    r0, r1 = ELEV_ROWS
    for r in range(r0, r1 + 1):
        t[r][c0 - 1] = SHAFT
        t[r][c1 + 1] = SHAFT
        for c in range(c0, c1 + 1):
            t[r][c] = EDOOR
    for c in range(4, 9):
        t[2][c] = SHELFT
        t[3][c] = SHELFB
    slab_row(t[4])
    return t


def t_roof(kind):
    """kind: 'plain', 'west' (the escalator head-house), 'east' (the exit)."""
    # THE ROOF IS SKY, THEN SKYLINE, THEN GREY -- in that order, top to bottom,
    # which is what the reference shows and what the first version got wrong.
    # It was sky all the way down to the deck, so Kelly (dark blue) stood
    # against a dark blue field and could not be seen at all up here. The grey
    # backdrop is the half of that fix the sky colour does not cover: it puts
    # a light neutral behind the figure at the height he actually occupies.
    t = blank(SKY)
    for c in range(W):
        t[1][c] = PARAP        # the horizon, on every roof screen
        t[2][c] = ROOFBG
        t[3][c] = ROOFBG
    # No arrival art for the west escalator: the flight is drawn in the band
    # BELOW and its top meets this deck, same as every other floor.
    if kind == "east":
        # the door Harry is running for, and the parapet he goes over
        for c in range(28, 31):
            t[2][c] = EXITC
            t[3][c] = EXITC
        t[3][31] = PARAP
        t[2][31] = PARAP
    slab_row(t[4])
    for c in range(W):
        t[4][c] = ROOFS
    if kind == "east":
        t[4][31] = PARAP
    return t


TEMPLATES = [
    ("T_AISLE_A", t_aisle_a()),
    ("T_AISLE_B", t_aisle_b()),
    ("T_ESC_W", t_escalator(west=True)),
    ("T_ESC_E", t_escalator(west=False)),
    ("T_ELEV", t_elev()),
    ("T_ROOF", t_roof("plain")),
    ("T_ROOF_W", t_roof("west")),
    ("T_ROOF_E", t_roof("east")),
    ("T_END_W", t_endwall(west=True)),
    ("T_END_E", t_endwall(west=False)),
]
TID = {name: i for i, (name, _) in enumerate(TEMPLATES)}

A, B, EW, EE, EL = "T_AISLE_A", "T_AISLE_B", "T_ESC_W", "T_ESC_E", "T_ELEV"
RF, RW, RE = "T_ROOF", "T_ROOF_W", "T_ROOF_E"
NW, NE = "T_END_W", "T_END_E"

# INDEX[lv][scr].  lv 0 = floor 1 (bottom band), lv 3 = roof.
#
# Only ONE escalator per floor, at that floor's alternating end -- west, east,
# west.  An escalator drawn where none works would be a step the player runs
# to and nothing happens, which reads as a broken game; across the building
# escalators still appear at BOTH end screens, which is the store's layout.
#
# The elevator serves floors 1-3 and NOT the roof.  If it reached the roof it
# would replace the whole climb and the three traverses would mean nothing.
#
# THE END SCREENS CARRY NOTHING BUT THE ESCALATOR -- or, on a floor whose
# escalator is at the other end, nothing but the wall.
INDEX = [
    [EW, A, B, EL, A, B, A, NE],    # lv0  floor 1  -- climbs WEST
    [NW, B, A, EL, B, A, B, EE],    # lv1  floor 2  -- climbs EAST
    [EW, A, B, EL, A, B, A, NE],    # lv2  floor 3  -- climbs WEST
    [RW, RF, RF, RF, RF, RF, RF, RE],  # lv3  roof   -- exit at the EAST edge
]

# Which end each floor's working escalator is at: 0 = west, 1 = east, 255 = none
ESC_SIDE = [0, 1, 0, 255]

# --------------------------------------------------------------------------
# OBSTACLES.  Three slots per band; slot 0 is always live, slot 1 arrives at
# Krook 2 and slot 2 at Krook 4.  THREE IS THE HARD CAP and it is not a taste
# decision: a band already carries Kelly, and the VDP shows four sprites per
# scanline and simply drops the fifth.
#
# Kinds: 0 none, 1 cart, 2 ball, 3 radio, 4 biplane.
# Biplanes only fly on floors 2 and 3 and the roof -- they are the one thing
# that kills, and the ground floor is where the player is still learning.
#
# Placement avoids the escalator and elevator zones: an obstacle parked on a
# boarding zone turns a route into a toll, which is not difficulty, it is a
# level-design bug that looks like one.
NONE, CART, BALL, RADIO, PLANE = 0, 1, 2, 3, 4

_BUSY = {  # columns that must stay clear, per template
    "T_ESC_W": (0, 8), "T_ESC_E": (23, 31), "T_ELEV": (12, 19),
    "T_ROOF_W": (0, 5), "T_ROOF_E": (26, 31),
}


def _clear_x(tplname, x):
    """True if a 16 px obstacle at x avoids this band's boarding zone."""
    if tplname not in _BUSY:
        return True
    c0, c1 = _BUSY[tplname]
    return (x + 16) < c0 * 8 or x > (c1 + 1) * 8


def obstacles():
    """Deterministic, hand-shaped placement -- a level, not a slot machine."""
    # per level, the palette the floor draws from
    palette = {
        0: [CART, BALL, RADIO],
        1: [BALL, CART, PLANE],
        2: [CART, PLANE, BALL],
        3: [PLANE, NONE, PLANE],
    }
    xs = [40, 150, 96]          # slot 0, 1, 2 starting x -- spread across
    out = []
    for lv in range(4):
        for scr in range(8):
            tpl = INDEX[lv][scr]
            # NOTHING HAZARDOUS ON THE END OR ELEVATOR SCREENS. Those three are
            # where the player has to STOP and do something precise -- board a
            # flight, wait for a car -- and a rolling cart there does not add
            # difficulty, it adds a toll on a manoeuvre the game has already
            # committed them to. The arcade keeps them clear for the same
            # reason.
            if scr in (0, 3, 7):
                out += [NONE, 0] * 3
                continue
            # ONE KIND PER BAND. A floor carrying a cart AND a ball asks two
            # different questions at once -- jump this, read that one's phase --
            # and the answer to one is the wrong answer to the other. Two of the
            # same thing is a floor with a rule; one of each is a floor with a
            # trick. The kind rotates by screen and level so the store still
            # varies, just never within a single stretch of floor.
            bandkind = palette[lv][(scr + lv) % 3]
            for s in range(3):
                k = bandkind
                x = (xs[s] + scr * 23) % 232
                if not _clear_x(tpl, x):
                    x = 120 if _clear_x(tpl, 120) else 0
                    if not _clear_x(tpl, x):
                        k = NONE
                if lv == 3 and k not in (PLANE, NONE):
                    k = NONE            # the roof is open sky, not an aisle
                out += [k, x]
    return out


# --------------------------------------------------------------------------
# COLLECTIBLES.  One per band at most: 0 none, 1 money bag, 2 suitcase.
# Characters, not sprites (see genart.py) -- they sit in the air row directly
# above the slab.  Stored as (kind, COLUMN), not a pixel x, because that is
# what a name-table poke needs.
def collectibles():
    out = []
    for lv in range(4):
        for scr in range(8):
            tpl = INDEX[lv][scr]
            kind, col = 0, 0
            if lv < 3 and scr not in (0, 3, 7):     # not the roof, not an
                if (scr + lv) % 3 == 1:             # escalator/elevator screen
                    kind = 1 if (scr % 2) == 0 else 2
                    col = 6 + ((scr * 5) % 18)
                    if not _clear_x(tpl, col * 8):
                        kind = 0
            out += [kind, col]
    return out


# --------------------------------------------------------------------------
# BOUNCE ARCS.  Three of them, 32 frames each -- and the apex is the ONLY thing
# that changes with the Krook.
#
# THE HEIGHTS ARE 8 / 10 / 12, not the 4 / 8 / 12 they started at. The old low
# arc was a stub: the ball barely left the floor, which looked wrong next to a
# 2600 beach ball and gave the early game nothing to read. It was only that low
# because the ORIGINAL jump could not reliably clear anything taller -- the arc
# touched its apex for four frames, so a taller ball meant a frame-perfect
# jump. Now that the jump holds 14 px for nine frames, the balls can bounce the
# height they are supposed to.
#
# In art-bottom pixels above the slab, with the ball's hitbox being the middle
# 4 px of its 8 px art, Kelly standing 16 px, ducked 8 px and jumping to 14:
#
#   jumpable   while  apex <= 8     (at 14 px of lift, a higher ball clips him)
#   duckable   while  apex >= 6     (ducked he is 8 px tall)
#   FREE       while  apex >= 14    -- which is why the cap is 12
#
# so the three arcs land exactly on the three regimes of DESIGN.md 5a:
#
#   apex  8   the top of the JUMP band -- jump it, and it is a real hop now
#   apex 10   duck-only at the peak, jumpable lower down: read the phase
#   apex 12   duck-only, and two pixels clear of becoming free
#
# The 6..8 overlap is what guarantees there is no height at which the ball can
# be neither jumped nor ducked; an unavoidable hazard is not difficulty.
def bounce_arcs():
    out = []
    for apex in (8, 10, 12):
        for t in range(32):
            u = (t - 16) / 16.0
            h = apex * (1.0 - u * u)
            out.append(max(0, int(round(h))))
    return out


def emit(fh, label, data, comment=""):
    if len(data) % 2:
        raise SystemExit("%s is %d bytes -- ODD blocks misalign every word "
                         "table after them" % (label, len(data)))
    fh.write("\n%s:%s\n" % (label, ("\t' " + comment) if comment else ""))
    for i in range(0, len(data), 16):
        fh.write("\tDATA BYTE " + ",".join(str(b) for b in data[i:i + 16]) + "\n")


ESC_CAP_PAIRS = 8            # fixed group size, so the game can index it


def esc_cap_bytes():
    """The two rows of flight that belong to the floor ABOVE.

    Six groups of fixed length, so the game can index straight to the one it
    wants: west store rows 0 and 1, east store rows 0 and 1, then west ROOF
    rows 0 and 1. Row 0 lands on the band above's air, row 1 on its floor.

    THE FLOOR SURVIVES UNDERNEATH because row 1 uses COMPOSITE characters --
    the same flight pattern, coloured line for line as the floor is, with black
    for the flight's own pixels. Every scan line of such a character needs only
    two colours, which is exactly what the VDP gives. Stamping the plain green
    cells there instead is what punched a hole through the storey above.

    The roof groups exist because the roof is not coloured like a shopping
    floor: its air is grey and its "floor" is the white-topped deck, so the
    flight up from floor 3 needs its own pair.
    """
    out = []
    groups = (
        (ESC_W_GRID, ESC_C0_W, "ESCW", "ESCWB"),    # west, into a shop floor
        (ESC_E_GRID, ESC_C0_E, "ESCE", "ESCEB"),    # east, into a shop floor
        (ESC_W_GRID, ESC_C0_W, "ESCWR", "ESCWD"),   # west, into the ROOF
    )
    for grid, c0, pre0, pre1 in groups:
        for r, pre in ((0, pre0), (1, pre1)):
            pairs = []
            for c in range(ESC_COLS):
                cell = grid[r][c]
                if cell is not None:
                    pairs += [c0 + c, CODES["%s%d" % (pre, cell)]]
            if len(pairs) > ESC_CAP_PAIRS * 2:
                raise SystemExit("esc_cap group needs %d pairs, max %d"
                                 % (len(pairs) // 2, ESC_CAP_PAIRS))
            out += pairs + [0, 0] * (ESC_CAP_PAIRS - len(pairs) // 2)
    return out


def preview():
    glyph = {SLAB: "=", SHELFT: "T", SHELFB: "L", COUNTR: "c",
             SHAFT: "|", EDOOR: "D", ECAR: "C",
             PARAP: "^", SKY: ".", WALL: " ", KOPIC: "k",
             EXITC: "E", ROOFS: "~", ROOFBG: ",", ENDWALL: "H"}
    # Built from CODES, not from a fixed count: the flight has been resliced
    # several times and a hard-coded 6 silently stopped covering it.
    for _n, _c in CODES.items():
        if _n.startswith("ESCW"):
            glyph[_c] = "/"
        elif _n.startswith("ESCE"):
            glyph[_c] = chr(92)
    names = ["roof   ", "floor 3", "floor 2", "floor 1"]
    for i, lv in enumerate((3, 2, 1, 0)):
        print("%s" % names[i])
        for r in range(H):
            line = ""
            for scr in range(8):
                t = dict(TEMPLATES)[INDEX[lv][scr]]
                line += "".join(glyph[c] for c in t[r]) + "|"
            print("  " + line)
        print()


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "src", "store.bas")

    tpl = []
    for name, t in TEMPLATES:
        for r in range(H):
            tpl += t[r]
    assert len(tpl) == len(TEMPLATES) * W * H

    idx = []
    for lv in range(4):
        for scr in range(8):
            idx.append(TID[INDEX[lv][scr]])

    with open(out, "w") as fh:
        fh.write("""\t' Keystone Kapers store -- GENERATED by assets/genstore.py. Do not edit.
\t'
\t' EIGHT band templates of 5 rows x 32 cols (160 bytes each) plus a 32-byte
\t' index over (level, screen). The whole 8-screen, 4-level building is about
\t' 1.3 KB instead of the 5,120 bytes it would cost to store literally.
\t'
\t' All eight templates are ONE contiguous block under ONE label, so a band
\t' blit is
\t'     SCREEN stor_tpl, tpl*160, toprow*32, 32, 5, 32
\t' with no label ladder -- SCREEN needs a literal label and a label cannot be
\t' chosen by a variable, which is why RallyX needed a 4-way IF over its maze
\t' tables. One block sidesteps it.
\t'
\t' 160 is EVEN, so this cannot leave the location counter odd and misalign
\t' the word tables defined after it.
""")
        fh.write("\t'\n\t' template ids:\n")
        for i, (name, _) in enumerate(TEMPLATES):
            fh.write("\t'   %d %s\n" % (i, name))

        emit(fh, "stor_tpl", tpl,
             "%d templates x %d bytes" % (len(TEMPLATES), W * H))
        emit(fh, "stor_ix", idx, "[lv*8 + scr] -> template id")
        # The jump arc: height above the floor for each frame of a jump.
        # It lived as thirty separate assignments in the source, which
        # cost several bytes of code apiece; as a table it is thirty
        # bytes and a loop.
        emit(fh, "jarc_tbl", [0, 3, 6, 8, 10, 11, 12, 13, 13, 14, 14, 14, 14, 14, 14, 14, 14, 14, 13, 13, 12, 12, 11, 10, 9, 7, 5, 3, 1, 0],
             "jump height per frame, 30 frames")
        emit(fh, "esc_cap", esc_cap_bytes(),
             "head cap: (col,char) pairs, west then east, 0,0 ends each")
        emit(fh, "stor_esc", ESC_SIDE + [0] * 4,
             "per level: 0 = climbs west, 1 = east, 255 = no escalator (padded even)")

        ob = obstacles()
        co = collectibles()
        ba = bounce_arcs()
        emit(fh, "stor_ob", ob,
             "[lv*8+scr] -> 3 x (kind, x). Slot 1 from Krook 2, slot 2 from Krook 4")
        emit(fh, "stor_co", co, "[lv*8+scr] -> (kind, column). 0 = nothing here")
        emit(fh, "stor_arc", ba,
             "3 bounce arcs x 32 frames, apex 4 / 8 / 12 -- see DESIGN.md 5a")

    live = sum(1 for i in range(0, len(ob), 2) if ob[i])
    prizes = sum(1 for i in range(0, len(co), 2) if co[i])
    print("wrote %s -- %d templates, %d bytes of map + %d index"
          % (os.path.normpath(out), len(TEMPLATES), len(tpl), len(idx)))
    print("       %d obstacle slots filled of %d, %d collectibles, arcs peak %d"
          % (live, len(ob) // 2, prizes, max(ba)))

    if "--preview" in sys.argv:
        print()
        preview()


if __name__ == "__main__":
    main()
