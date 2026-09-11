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
PIL_A = (4, 11, 20, 27)
PIL_B = (7, 15, 24)


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
    _pillars(t, PIL_A)
    _counter(t, 14, 19)
    slab_row(t[4])
    return t


def t_aisle_b():
    t = blank(WALL)
    _pillars(t, PIL_B)
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
    # OUTBOARD POSTS, FOUR PIXELS WIDE. The jambs used to live inside the
    # doorway's own end columns, which cost a quarter of the opening to frame
    # it. They are in the WALL column either side now (see EJAMBL in
    # genart.py): the inner half of that character is the post and the outer
    # half is still shop floor, which is two colours in one cell and all this
    # VDP allows.
    #
    # THEY ARE PART OF THE MAP, not part of the car. A door frame does not
    # appear when the doors open, and drawing it here means car_cell never has
    # to know about it -- which is what let its two column special-cases go.
    for r in range(r0, r1 + 1):
        t[r][c0 - 1] = EJAMBL
        t[r][c1 + 1] = EJAMBR
        for c in range(c0, c1 + 1):
            # the bottom row of the doorway carries the threshold, so the
            # static map agrees with what draw_car paints over it. The
            # threshold spans the OPENING only -- it is the plate between the
            # jambs, and the jambs stand on the floor beside it.
            t[r][c] = EDOORS if r == r1 else EDOOR
    for c in range(4, 9):
        t[2][c] = SHELFT
        t[3][c] = SHELFB
    slab_row(t[4])
    return t


def t_roof(kind, scr=0):
    """kind: 'plain', 'west' (the escalator head-house), 'east' (the exit).

    `scr` is WHICH SCREEN this template is for, and it exists to give the city
    parallax. The skyline is sampled ONE column further along per screen, so
    crossing a seam slides the horizon by 1 of 32 -- a 1/32 rate against the
    foreground. Without it the buildings are identical on all eight screens and
    the roof reads as wallpaper: the foreground jumps a whole screen and the
    horizon does not move at all.

    IT WAS TWO COLUMNS AND THAT WAS TOO MUCH TO FOLLOW. The rate has to be slow
    enough that the eye reads the far city as the SAME city seen from further
    along -- at two columns a crossing changed enough of the silhouette that
    the continuity broke and it read as a different skyline rather than a moved
    one. Distance is sold by moving very little, not by moving visibly.

    DIRECTION, because parallax sense is easy to invert and impossible to spot
    in a still: screen s+1 column c shows what screen s had at column c+2, so
    the buildings travel LEFT as the player runs EAST. That is correct -- the
    far thing moves against you, more slowly.

    Only rows 0-2 shift. Row 3 is the solid wall of building at the height an
    actor occupies and row 4 is the deck the player runs on; both are the same
    on every screen, and sliding either would be sliding the floor.
    """
    # THE ROOF IS SKY, THEN SKYLINE, THEN GREY -- in that order, top to bottom,
    # which is what the reference shows and what the first version got wrong.
    # It was sky all the way down to the deck, so Kelly (dark blue) stood
    # against a dark blue field and could not be seen at all up here. The grey
    # backdrop is the half of that fix the sky colour does not cover: it puts
    # a light neutral behind the figure at the height he actually occupies.
    # THE SKYLINE, THREE ROWS DEEP. Row 3 is a continuous wall of brick at the
    # height an actor and a cart actually occupy; rows 2 and 1 are the
    # roofline. A flat grey backdrop stood here and swallowed the roof's
    # shopping carts whole -- see the note over BLDGW in genart.py.
    #
    # ROW 1 USED TO BE THE PARAPET, a crenellated band of medium red across the
    # whole screen. Above a lit skyline it stopped reading as a horizon and
    # started reading as a ROW OF FLAMES. It is gone, and the tallest buildings
    # take that row instead.
    #
    # AND THE TALLEST REACH INTO ROW 0. The skyline now uses all four of the
    # band's rows above the deck: row 3 is always solid wall, rows 2 and 1 may
    # be a full storey, and the very tallest carry a 4px BLDGM into row 0. The
    # top of the city is 28 pixels -- three and a half characters, with 4px of
    # sky still above it, which is enough to keep it reading as a horizon.
    #
    # Heights, in pixels, from the six steps below:  8  11  14  20  24  28
    #
    # Written out rather than generated: one row of 32 numbers, meant to look
    # deliberate rather than random, and it never changes.
    #   0 sky              1 low block   2 tall block
    #   3 full + a 4px top  4 two full    5 two full + a 4px top
    SKYLINE = [2, 4, 1, 0, 3, 5, 2, 1, 0, 4, 3, 1, 2, 5, 4, 0,
               1, 3, 2, 4, 0, 2, 5, 3, 1, 0, 4, 2, 3, 1, 5, 2]
    # ROW-SPECIFIC SKY. The backdrop is a gradient down the band (SKYGRAD in
    # genart.py), and a character cannot know which row it was placed in, so
    # the sky and the two partial buildings come in one variant per row.
    # ONLY THE TOP OF THE SKYLINE GOES UP, and that restriction is not
    # cosmetic. The gradient's bottom band -- the yellow -- lives on band
    # lines 20-23, and row 3 is solid building from line 24 down, so a column
    # only shows yellow if its building is SHORTER than twelve pixels. Raising
    # every step by four (8 11 14 20 24 28 -> 12 14 20 24 28 32) put every
    # column at twelve or more and the yellow vanished from the sky entirely.
    #
    # So the two TALLEST steps gain four pixels each and the three short ones
    # are untouched:
    #
    #     8  11  14  20  24  28   ->   8  11  14  20  28  32
    #
    # The tallest now fills the whole band and meets the score line's own
    # blue; the low blocks still cut down far enough to let the yellow through.
    ROW0 = (SKY0, SKY0, SKY0, SKY0, BLDGM0, BLDGW0)
    ROW1 = (SKY1, SKY1, SKY1, BLDGM1, BLDGW, BLDGW)
    ROW2 = (SKY2, BLDGL, BLDGH, BLDGW, BLDGW, BLDGW)
    t = blank(SKY0)
    for c in range(W):
        h = SKYLINE[(c + scr) & 31]
        t[0][c] = ROW0[h]
        t[1][c] = ROW1[h]
        t[2][c] = ROW2[h]
        t[3][c] = BLDGW
    # No arrival art for the west escalator: the flight is drawn in the band
    # BELOW and its top meets this deck, same as every other floor.
    if kind == "east":
        # NO DOOR. Six cells of EXITC stood at columns 28-30, rows 2-3 -- a
        # white box character on dark blue, which on screen reads as six purple
        # dots on white and was asked about as a graphical fault before it was
        # asked to be removed. The roof's east end is the edge of the BUILDING
        # and the crook goes over it; a doorway there says he leaves through
        # something, which is a different and wrong statement about how the
        # round ends.
        #
        # Removing it is also what lets him run the last two characters east:
        # the door was where he stopped, so the escape point could not move
        # right while it stood there. See XROOF in KEYSTONE.bas.
        #
        # THE CHARACTER ITSELF IS DELIBERATELY LEFT DEFINED in genart.py, and
        # this is a trade rather than an oversight. Deleting it renumbers every
        # code above 156 -- checkchars.py named 21 stale constants when it was
        # tried, and renumber.py would have rewritten them from genart's tables
        # -- to reclaim 16 bytes of PATTERN AND COLOUR TABLE, which live in a
        # bank with 6,500 free. That spends blast radius on the budget that is
        # not scarce; the fixed area, which is the one that binds, does not
        # change either way.
        # THE LAST OF THE PARAPET. Its crenellated red read as flames beside
        # the lit skyline, the same as the band across row 1 did, so the
        # building carries on to the screen edge instead -- which is also a
        # plainer statement of what the edge IS: the end of the roof.
        t[3][31] = BLDGW
        t[2][31] = BLDGW
    slab_row(t[4])
    for c in range(W):
        t[4][c] = ROOFS
    if kind == "east":
        t[4][31] = ROOFS       # the deck runs to the edge, as it must
    return t


TEMPLATES = [
    ("T_AISLE_A", t_aisle_a()),
    ("T_AISLE_B", t_aisle_b()),
    ("T_ESC_W", t_escalator(west=True)),
    ("T_ESC_E", t_escalator(west=False)),
    ("T_ELEV", t_elev()),
    # ONE ROOF TEMPLATE PER SCREEN, so the skyline can differ across the
    # store (see t_roof). Screen 0 carries the head-house and screen 7 the
    # exit door, on top of their own offsets. Five more templates than the
    # three this replaced -- 800 bytes, and they land in the ROM BANK with
    # store.bas rather than in the fixed area, which is the only reason this
    # is cheap. See DESIGN.md 13a for the costing, and for the first version
    # of it that charged bank data against the fixed area and concluded the
    # cheap option was unaffordable.
    ("T_ROOF0", t_roof("west", 0)),
    ("T_ROOF1", t_roof("plain", 1)),
    ("T_ROOF2", t_roof("plain", 2)),
    ("T_ROOF3", t_roof("plain", 3)),
    ("T_ROOF4", t_roof("plain", 4)),
    ("T_ROOF5", t_roof("plain", 5)),
    ("T_ROOF6", t_roof("plain", 6)),
    ("T_ROOF7", t_roof("east", 7)),
    ("T_END_W", t_endwall(west=True)),
    ("T_END_E", t_endwall(west=False)),
]
TID = {name: i for i, (name, _) in enumerate(TEMPLATES)}


# WHICH COLUMNS CARRY A SUPPORT BEAM IS READ BACK OFF THE TEMPLATE, not kept
# beside it. The first version had a hand-written table -- and because the same
# tuple both drew the beams and filled the table, the two could not disagree,
# so the guard checking them against each other passed on every input including
# the broken ones. Deriving it means there is only one source and nothing left
# to check but the width (below).
#
# A beam is a column that is COUNTR for all four AIR rows. A counter is COUNTR
# too, but only in the bottom half, so it is not one.
def _beam_cols(t):
    # THE END WALL COUNTS AS ONE. It is a full-height column of brick at the
    # extreme edge, and like a pillar it stopped three pixels under the floor
    # above -- so the building's own outside wall had a green stripe through it
    # at every storey. Whatever fills all four air rows gets its top stamped.
    return [c for c in range(W)
            if all(t[r][c] in (COUNTR, ENDWALL) for r in range(4))]

A, B, EW, EE, EL = "T_AISLE_A", "T_AISLE_B", "T_ESC_W", "T_ESC_E", "T_ELEV"
R0, R1, R2, R3 = "T_ROOF0", "T_ROOF1", "T_ROOF2", "T_ROOF3"
R4, R5, R6, R7 = "T_ROOF4", "T_ROOF5", "T_ROOF6", "T_ROOF7"
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
    [R0, R1, R2, R3, R4, R5, R6, R7],  # lv3  roof -- one per screen, exit EAST
]

# Which end each floor's working escalator is at: 0 = west, 1 = east, 255 = none
ESC_SIDE = [0, 1, 0, 255]

# --------------------------------------------------------------------------
# OBSTACLES.  The table stores THREE slots per band, but only TWO are ever
# live: load_band reads the third to keep the six-bytes-per-band stride and
# throws it away.  Slot 0 is always live; slot 1 arrives at KROOK 6 -- the
# original's "double radios" round.
#
# TWO IS THE HARD CAP and it is not a taste decision: the band already carries
# Kelly AND, on his own floor, Harry, and the VDP shows four sprites per
# scanline and simply drops the fifth.  Three was the original number and it
# was sized against Kelly alone.
#
# (This comment said "three slots, slot 1 at Krook 2, slot 2 at Krook 4" long
# after all three of those numbers had changed.  The authority is
# assets/checklevels.py, which reads every threshold back out of the source.)
#
# Kinds: 0 none, 1 cart, 2 ball, 3 radio, 4 biplane.
# Biplanes only fly on floors 2 and 3 and the roof -- they are the one thing
# that kills, and the ground floor is where the player is still learning.
#
# Placement avoids the escalator and elevator zones: an obstacle parked on a
# boarding zone turns a route into a toll, which is not difficulty, it is a
# level-design bug that looks like one.
NONE, CART, BALL, RADIO, PLANE = 0, 1, 2, 3, 4

# Columns that must stay clear, per template. These finally MATTER: screens 0, 3
# and 7 used to carry no obstacles at all, so _clear_x was consulted for nothing
# and never once fired. They are named T_ROOF0/T_ROOF7 because the roof gained a
# template per screen when the skyline was given parallax (DESIGN.md 13a); they
# said T_ROOF_W and T_ROOF_E for exactly as long as it took to notice, matching
# nothing.
_BUSY = {
    "T_ESC_W": (0, 8), "T_ESC_E": (23, 31), "T_ELEV": (12, 19),
    "T_ROOF0": (0, 5), "T_ROOF7": (26, 31),
}


def _clear_x(tplname, x):
    """True if a 16 px obstacle at x avoids this band's boarding zone."""
    if tplname not in _BUSY:
        return True
    c0, c1 = _BUSY[tplname]
    return (x + 16) < c0 * 8 or x > (c1 + 1) * 8


# WHERE A RADIO CAN STAND. A radio is the only hazard that does not move, so it
# is the only one that can PARK on a boarding zone -- a rolling cart crosses the
# escalator foot and is gone, which is a hazard; a radio sitting on it is a toll.
# The rack is chosen at run time (load_band picks 0/1/2 by slot and Krook), so
# the generator cannot steer an individual radio away from the zone; it can only
# decline to put radios on a screen that has one.
RADIO_RACK_X = (56, 120, 184)


def _radio_ok(tplname):
    """True if EVERY rack position on this screen clears the boarding zone."""
    return all(_clear_x(tplname, x) for x in RADIO_RACK_X)


# ==========================================================================
# THE LEVEL TABLE. One byte per band per Krook -- the whole difficulty ramp.
#
# THIS USED TO BE CODE. The layout was a fixed 192-byte table with ONE KIND PER
# FLOOR (floor 1 all balls, floor 2 all radios ...), and every per-Krook
# decision was a ladder of `IF krk < n` gates inside load_band. Those gates can
# only say things about (Krook, floor, kind), so two things the original does
# were simply not expressible:
#
#   * "this screen is empty"     -- a populated screen could NEVER be empty. The
#     arrival gate downgraded an unarrived kind to a BEACH BALL rather than
#     removing it, and floors 0 and 2 had no occupancy gate at all, so both
#     carried a ball on every screen from Krook 1 forever. Reported from play as
#     "you put balls on every screen on the 1st and 3rd floors", and it was
#     provable from the gates rather than a tuning accident.
#   * "this floor has a cart here and a plane there" -- the kind was a property
#     of the floor, for the whole game.
#
# Measured against the original (assets/ref2600/hazards.md): level 1 shows a
# MEDIAN OF ZERO hazards on screen where the port showed two, and every floor
# carries two to four different kinds from level 3 on.
#
# So the ramp is data now, and `density()` below computes what it will actually
# look like so the numbers can be checked rather than hoped at.
# ==========================================================================

# How many Krook rows the table holds. Krook 12 and up reuse the last row --
# the measurement shows the original stops changing at 11.
KROOKS = 11

# WHICH KROOK EACH KIND ARRIVES ON, and which it starts coming in twos on.
# Straight from hazards.md; checklevels.py asserts both against this dict.
ARRIVE = {BALL: 1, RADIO: 2, CART: 3, PLANE: 4}
DOUBLE = {RADIO: 6, BALL: 9, CART: 11}          # PLANE never doubles

# HOW MANY BANDS CARRY A HAZARD, and how many of those carry a second, per
# Krook. Tuned so density() lands on the measured column in hazards.md; the
# checker holds it there.
BANDS   = {1: 5, 2: 11, 3: 16, 4: 20, 5: 20, 6: 20,
           7: 20, 8: 20, 9: 20, 10: 20, 11: 20}
DOUBLED = {1: 0, 2: 0, 3: 0, 4: 0, 5: 1, 6: 4,
           7: 5, 8: 5, 9: 6, 10: 6, 11: 7}

# THE ORDER BANDS FILL IN. Fixed, so each Krook is a superset of the one before
# and the ramp reads as the store filling up rather than as a reshuffle.
#
# Hazard screens fill first and the escalator/elevator screens last, because
# that is the order the original fills them: at level 1 its end screens average
# 0.33 hazards against the aisles' 0.71, and by level 4 the two are level.
_SCR_ORDER = (2, 5, 1, 6, 4, 3, 0, 7)
_LV_ORDER = (0, 2, 3, 1)


# NOTHING EVER STANDS ON AN ESCALATOR SCREEN. Not a rolling one, not a parked
# one, on any Krook. That screen is where the player has to STOP and board, and a
# hazard there is a toll on a manoeuvre the game has already committed them to
# rather than a difficulty they can read and answer.
#
# It is a property of the TEMPLATE, not of a screen number: floors 0 and 2 climb
# from the west (screen 0) and floor 1 from the east (screen 7), so "screen 0" is
# an escalator on two floors and an end wall on a third. Three bands in all.
#
# The ELEVATOR screen is deliberately NOT in here -- the reviewer wants hazards
# there, and waiting for a car is not the same as stepping onto a moving stair.
ESC_TPL = ("T_ESC_W", "T_ESC_E")
SCREENS = 8             # screens per floor
SCR_LAST = SCREENS - 1  # the east end screen of every floor


def esc_screens():
    """Screen indices that carry an escalator on ANY floor.

    A SCREEN IS THE WHOLE VERTICAL SLICE -- all four floors at once -- and that
    is the unit the rule is about. Two narrower readings were tried and both were
    wrong:

      1. the band whose TEMPLATE is a flight. A flight is drawn in the band you
         are LEAVING, so this caught the foot and missed the head: a cart stood
         at the top of floor 3's escalator, on the roof.
      2. the foot AND the head. Better, and still not it -- floor 1's screen 7
         kept a ball while floor 2's escalator stood on that same screen, one
         band above it. All four bands are on screen together, so the player sees
         a hazard and an escalator in the same picture, which is the thing the
         rule exists to prevent.

    Reported twice before it was got right: "There should never be hazards on the
    escalator screen", then "you placed hazard on the starting escalator screen.
    This rule -- no hazards on escalator screens -- needs to be reflected."

    Derived rather than listed, because which screen an escalator lives on is a
    fact about ESC_SIDE and INDEX, and a hand-written (0, 7) would go stale the
    day a floor changed sides.
    """
    out = set()
    for lv in range(4):
        for scr in range(SCREENS):
            if INDEX[lv][scr] in ESC_TPL:
                out.add(scr)                        # the foot, drawn here
            elif lv > 0 and ESC_SIDE[lv - 1] == 0 and scr == 0:
                out.add(scr)                        # the head, arriving west
            elif lv > 0 and ESC_SIDE[lv - 1] == 1 and scr == SCR_LAST:
                out.add(scr)                        # the head, arriving east
    return out


ESC_SCREENS = esc_screens()


def esc_band(lv, scr):
    """True if this band sits on an escalator screen, on any floor."""
    return scr in ESC_SCREENS


# HOW UNEVENLY THE SCREENS FILL. 0 fills them all at the same rate; larger
# numbers let some screens run ahead and leave others bare.
#
# THE FIRST VERSION FILLED PERFECTLY EVENLY and it was wrong in a way the mean
# could not show. Matching the original's AVERAGE hazards-per-screen says nothing
# about the SPREAD, and the original's spread is wide at every level: 12-19% of
# its screens are empty even at levels 4 to 8, with a tail of screens carrying
# five, six and seven. Ours put three on two thirds of the screens and four on
# the rest -- no relief anywhere, and no variety. Reported as "sometimes the
# distribution feels heavy on certain screens" and "there are no hazards on the
# first band on the way to the elevator", which are the same observation from
# both ends: uniform load reads as relentless AND as arbitrary.
#
# Fitted to the measured histogram rather than chosen -- see fit_spread() in the
# module docstring's --fit mode.
SPREAD = 3

# THE MOST ANY ONE SCREEN MAY CARRY. Seven is the largest number of hazards seen
# on screen at once anywhere in the measured 2600 playthrough, so this is a
# measurement rather than a preference.
MAXLOAD = 7


def fill_order(krook=1):
    """The placeable bands, in the order THIS Krook populates them.

    Screens fill at different rates, and which screen runs ahead rotates with the
    Krook -- so a screen that is bare on one round is busy on the next, and no
    stretch of shop is permanently the quiet one.
    """
    screens = [s for s in range(SCREENS) if s not in ESC_SCREENS]
    eager = {s: (i + krook) % len(screens) for i, s in enumerate(screens)}
    bands = [(lv, scr) for scr in screens for lv in range(4)]

    # SPREAD is the screen STRIDE, and the two ends of its range are the two
    # wrong answers. At 1 the screens fill in lockstep -- every screen gets its
    # first hazard before any gets a second -- which is the uniform load that was
    # reported as "heavy" everywhere and left no screen quiet. At 4 (a screen's
    # whole height) they fill strictly one at a time, which piles everything onto
    # a few screens and leaves the rest bare. In between, screens overlap by a
    # controllable amount, and the last screen in the order can fall far enough
    # behind to stay EMPTY -- which the original does at every level.
    def key(b):
        lv, scr = b
        return (_LV_ORDER.index(lv) + eager[scr] * SPREAD, scr, lv)

    return sorted(bands, key=key)


def _kind_for(lv, scr, krook, seq):
    """Pick this band's hazard, mixing kinds across floors AND screens."""
    live = [k for k in (BALL, RADIO, CART, PLANE) if ARRIVE[k] <= krook]
    tpl = INDEX[lv][scr]
    # THE ROOF GETS CARTS AND NOTHING ELSE, for two separate reasons.
    #
    # No biplane: the roof is where the round is decided, and a biplane costs a
    # whole Kop rather than nine seconds. The measurement agrees -- the
    # original's roof shows only radios and carts, at every level.
    #
    # AND NO RADIO, which is OURS rather than the original's. A radio is drawn as
    # CHARACTERS, not a sprite, so it has to share its cells' two colours with
    # whatever it stands on; on a shop floor that is flat green and fine, and on
    # the roof it is the parallax skyline. Reported from play as "the colors get
    # messed up". The TMS9918 allows two colours per 8x1 line and the roof has
    # already spent both.
    #
    # That leaves carts, which the reference does put on the roof -- one was
    # tracked crossing it.
    if lv == 3:
        live = [k for k in live if k == CART]
    # ...and no RADIO where a rack position would sit on a boarding zone.
    if not _radio_ok(tpl):
        live = [k for k in live if k != RADIO]
    return live[seq % len(live)] if live else NONE


def levels():
    """KROOKS rows x 32 bands x 1 byte.

    bits 0-2  kind (0 none, 1 cart, 2 ball, 3 radio, 4 biplane)
    bit  3    a second hazard on this band
    bits 4-7  unused

    THE STAGGER IS NOT IN HERE. It was, as a nibble, and unpacking it costs a
    DIVIDE -- CVBasic's `/` compiles to a real TMS9900 DIV (CLAUDE.md 3A) and
    this is the one budget with nothing to spare. load_band derives it from the
    band index instead, which is a fact it already has in hand and which spreads
    just as well. Storing a value that can be computed is only free when the
    unpacking is.
    """
    out = []
    for krook in range(1, KROOKS + 1):
        order = fill_order(krook)
        row = [NONE] * 32
        n, d = BANDS[krook], DOUBLED[krook]
        doubled_left = d
        filled = []
        for seq, (lv, scr) in enumerate(order[:n]):
            kind = _kind_for(lv, scr, krook, seq)
            if kind == NONE:
                continue
            row[lv * 8 + scr] = kind
            filled.append((lv, scr, kind))

        # DOUBLE ROUND-ROBIN ACROSS SCREENS, NOT IN FILL ORDER.
        #
        # Spending the doubling budget in fill order piles it onto whichever
        # screens come first, and a screen with all four bands doubled carries
        # TEN hazards once the third radios arrive -- against a maximum of seven
        # ever observed in the original. Krook 9 read [4, 3, 1, 7, 6, 10] and
        # Krook 11 [2, 9, 7, 7, 6, 2]: one stretch of shop impassable, another
        # empty. That is the "sometimes the distribution feels heavy on certain
        # screens" report, and it comes from the doubling rather than from which
        # bands are occupied.
        #
        # One pass hands a second hazard to each screen in turn, so the budget
        # spreads before it deepens.
        # AND NO SCREEN MAY EXCEED MAXLOAD, which round-robin alone does not
        # guarantee: once the other screens run out of bands whose KIND is
        # allowed to pair, the loop keeps returning to the one that has them.
        # Krook 9 still reached ten that way. The cap is the original's observed
        # maximum, so it is a measurement rather than a preference.
        by_screen = {}
        for lv, scr, kind in filled:
            by_screen.setdefault(scr, []).append((lv, kind))

        def load(scr):
            n = 0
            for lv, kind in by_screen[scr]:
                b = row[lv * 8 + scr]
                n += 1
                if b & 8:
                    n += 1
                    if kind == RADIO and krook > 7:
                        n += 1
            return n

        while doubled_left > 0:
            spent = 0
            for scr in sorted(by_screen):
                if doubled_left <= 0:
                    break
                if load(scr) >= MAXLOAD:
                    continue
                for lv, kind in by_screen[scr]:
                    # a band can only be doubled once its OWN kind pairs
                    if krook >= DOUBLE.get(kind, 99) and not row[lv * 8 + scr] & 8:
                        row[lv * 8 + scr] |= 8
                        doubled_left -= 1
                        spent += 1
                        break
            if not spent:
                break               # nothing left that is allowed to double
        out += row
    return out


def preview_levels():
    """The whole difficulty ramp as a grid, so it can be corrected on paper.

    Reading 352 bytes of DATA BYTE tells you nothing about whether level 1 is
    sparse or whether a floor carries a mix. This does, in one screenful.
    """
    mark = {NONE: ".", CART: "c", BALL: "b", RADIO: "r", PLANE: "p"}
    flat = levels()
    print("      screens 0-7 per floor; UPPER CASE = two of them")
    print("      . empty   b ball   r radio   c cart   p biplane")
    for krook in range(1, KROOKS + 1):
        row = flat[(krook - 1) * 32:krook * 32]
        print("\n  Krook %-2d   %.2f on screen" % (krook, density(krook)))
        for lv in (3, 2, 1, 0):
            cells = ""
            for scr in range(8):
                b = row[lv * 8 + scr]
                ch = mark[b & 7]
                cells += ch.upper() if (b & 8) else ch
            name = ("floor 1", "floor 2", "floor 3", "roof")[lv]
            print("    %-8s %s" % (name, " ".join(cells)))


def density(krook):
    """Hazards visible on one screen, averaged over the PLACEABLE screens.

    Not over all eight. The escalator screens are structurally empty -- nothing
    may ever stand on them -- so including them drags the average down by a
    quarter and no table could ever reach a figure measured on a game that does
    put hazards there. Dividing by eight was comparing our whole store against
    the original's aisles.

    So this is the density of the screens that can carry anything, and the target
    it is checked against is the original's AISLE-screen column in
    assets/ref2600/hazards.md. Like for like.

    Counted the way the GAME will count it -- a doubled band shows two, and a
    doubled radio band shows three from Krook 8 -- rather than as a byte count.
    """
    row = levels()[(min(krook, KROOKS) - 1) * 32:][:32]
    total = 0
    for band, b in enumerate(row):
        kind = b & 7
        if not kind:
            continue
        total += 1
        if b & 8:
            total += 1
            if kind == RADIO and krook > 7:
                total += 1          # the third radio, synthesised in load_band
    return total / float(SCREENS - len(ESC_SCREENS))


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
# THE HEIGHTS ARE 8 / 10 / 12, and the point of the first one is that it can
# be JUMPED AT EVERY POINT OF ITS BOUNCE.
#
# In art-bottom pixels above the slab, with the ball's hitbox the middle 4 px
# of its 8 px art, and the SHIPPED figures -- Kelly standing 24, ducked 11,
# jumping to 14 -- the two windows do not overlap at all:
#
#   jumpable   while  bb <= 8
#   duckable   while  bb >= 9
#   FREE       never  (bb + 2 < 24 always, so standing is always a hit)
#
# so the apex alone decides HOW MUCH of a round's bounce demands a duck:
#
#   apex  9   25 frames jump,  7 duck -- Krooks 1-4
#   apex 16   11 frames jump, 21 duck -- Krooks 5-9
#   apex 20    9 frames jump, 23 duck -- Krooks 10+
#
# 21 is the ceiling, and it is not the band's: a ball is FREE -- clearable by a
# STANDING Kelly, the one thing no arc may ever be -- once its hitbox bottom
# reaches STANDH, i.e. at bb >= 22. 20 keeps two pixels off that.
#
# AND THE APEX IS ONLY HALF OF WHY A TALL BALL GETS DUCKED. The bounce phase is
# seeded so the ball meets the player at a known point of its cycle, and for the
# tall arcs KEYSTONE.bas seeds that point to the APEX rather than the ground.
# Without that, the seeding hands out a free jump on arrival however high the
# ball bounces -- reported from play as easy to just keep running and jump over,
# and the apex had nothing to do with it.
#
# The top of every arc is a duck, and the taller the ball bounces the more of
# its cycle that is. Ducking is in the vocabulary from the first ball.
#
# AND THE APEXES HAVE TO DIFFER BY SOMETHING A PLAYER CAN SEE. They were
# 9 / 10 / 12 -- tuned entirely by that frame split, which is the right thing to
# tune and the wrong thing to tune ALONE. Three pixels of spread across the
# whole game, on a character 24 px tall, is invisible: reported from play as
# "I do not see balls bouncing higher" on Krook 8, and the report is correct.
# The tall ball was ONE PIXEL taller than the short one.
#
# checkball.py passed throughout, because its question is "is every frame of
# every arc jumpable or duckable" -- a question about one arc at a time. Whether
# three arcs are distinguishable FROM EACH OTHER is a property of the set, and
# it is invisible to every check written about a member of it. That is the same
# lesson checkanim.py exists for, in a different subsystem: rank on the closest
# pair, not on each item alone. checkball.py now measures the spread too.
#
# The ceiling is real but distant: a band is 32 px of air, the art is 8 px tall,
# and a ball is FREE (clearable standing) at bb >= 22. 19 leaves three pixels of
# margin on the free rule and five under the ceiling.
#
# There is no height at which the ball can be neither jumped nor ducked, which
# is what assets/checkball.py actually asserts (that, and that no frame is
# clearable standing).
def bounce_arcs():
    """The three bounce heights, and the LOWEST one is 9 for a reason.

    A BALL AT THE TOP OF ITS ARC MUST NOT BE JUMPABLE, on every arc including
    the first. The rule the player is meant to learn is "jump it low, duck it
    high", and it is meant to be learnable from the opening screen -- what
    changes with the Krook is how MUCH of the bounce is duck-only, because the
    ball bounces higher, not whether ducking exists at all.

    At apex 9 the hitbox sits at 11..15 against a jump apex of exactly 14. The
    hit test is `kfh < oht` and 14 < 15 is true, so the top of the arc is a
    duck. It still clears the crouch: DUCKH is 11 and the test is `ohb < ktop`,
    so 11 < 11 is false and ducking passes under it.

    EIGHT WAS TRIED AND REJECTED. It puts the band at 10..14, and 14 < 14 is
    false, so the jump clears it by a single pixel of arithmetic and the low
    arc becomes jumpable on all 32 frames. The published guides do read that
    way -- level 5 is where "the balls start to bounce higher" -- but the call
    here is that the duck should be in the vocabulary from the first ball and
    that later rounds get MORE of it, not the first sight of it. Reverted at
    the reviewer's word, twice.

    Both ends of this are one pixel wide, which is why assets/checkball.py
    sweeps every crouch height against every apex rather than trusting the
    arithmetic here.

    THE OTHER TWO ARE NOT PINNED, AND THEY WERE FAR TOO CLOSE TO IT. 9 / 10 / 12
    made the "tall" ball of Krook 5 exactly one pixel taller than the short one
    of Krook 1. 16 and 20 are visibly different heights while leaving arc 0
    exactly where the reviewer twice put it -- what changes across the game is
    the height, which is what the guides describe and what a player can actually
    see, and the frame split follows from it.
    """
    out = []
    for apex in (9, 16, 20):
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
        # the ROOF crossing uses the SAME characters as the shop-floor one;
        # they are coloured apart by screen third (see genart.py's ESC_DECK)
        (ESC_W_GRID, ESC_C0_W, "ESCWR", "ESCWB"),   # west, into the ROOF
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
             PARAP: "^", SKY0: ".", SKY1: ".", SKY2: ".", WALL: " ", KOPIC: "k",
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

    for name, cols in ((n, _beam_cols(t)) for n, t in TEMPLATES):
        if len(cols) > 4:
            raise SystemExit(
                "%s has %d support beams and stor_pil has room for four: %r. "
                "Widen the table in BOTH this emit and beam_tops' inner FOR."
                % (name, len(cols), cols))

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
        # WHICH COLUMNS A TEMPLATE STANDS ITS SUPPORT BEAMS IN, four bytes
        # apiece, 0 ending the run. The beam tops are stamped at run time
        # into the slab row above (see draw_screen): a template only knows
        # its own band, and the row a beam has to reach belongs to the band
        # above it, whose template is chosen independently per screen.
        # COLUMN PLUS ONE, because 0 has to mean "no more" AND column 0 is a
        # real place -- it is where the WEST end wall stands. Stored raw, the
        # terminator swallowed it: every west wall on every floor was skipped,
        # so the building's left-hand side had no support reaching the storey
        # above while the right-hand side did. The east wall at column 31 was
        # fine, which is exactly why it took so long to see.
        emit(fh, "stor_pil",
             [c for _n, t in TEMPLATES
              for c in ([x + 1 for x in _beam_cols(t)] + [0, 0, 0, 0])[:4]],
             "per template: up to 4 support-beam columns PLUS ONE, 0 ends")
        emit(fh, "stor_esc", ESC_SIDE + [0] * 4,
             "per level: 0 = climbs west, 1 = east, 255 = no escalator (padded even)")

        ob = levels()
        co = collectibles()
        ba = bounce_arcs()
        emit(fh, "stor_lvl", ob,
             "[krook-1][lv*8+scr] -> kind | doubled<<3. "
             "%d Krook rows; 12+ reuse the last" % KROOKS)
        emit(fh, "stor_co", co, "[lv*8+scr] -> (kind, column). 0 = nothing here")
        emit(fh, "stor_arc", ba,
             "3 bounce arcs x 32 frames, apex 9 / 14 / 19 -- see DESIGN.md 5a")

    live = sum(1 for b in ob if b & 7)
    prizes = sum(1 for i in range(0, len(co), 2) if co[i])
    print("wrote %s -- %d templates, %d bytes of map + %d index"
          % (os.path.normpath(out), len(TEMPLATES), len(tpl), len(idx)))
    print("       %d obstacle slots filled of %d, %d collectibles, arcs peak %d"
          % (live, len(ob), prizes, max(ba)))
    print("       hazards visible per screen, by Krook:")
    print("         " + "  ".join("%d:%.2f" % (k, density(k))
                                  for k in range(1, KROOKS + 1)))

    if "--preview" in sys.argv:
        print()
        preview()
    if "--levels" in sys.argv:
        print()
        preview_levels()


if __name__ == "__main__":
    main()
