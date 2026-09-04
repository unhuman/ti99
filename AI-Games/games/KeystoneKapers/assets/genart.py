#!/usr/bin/env python3
"""Keystone Kapers art -- sprites and store characters.

Two things here are load-bearing and are documented in DESIGN.md rather than
being obvious from the pixels:

1. EVERY SPRITE IS 16x16. Sprite size and magnification are GLOBAL on the
   TMS9918, so a shopping cart is not an 8x8 sprite -- it is a cart drawn 16
   wide and 8 tall inside a 16x16 box. There is no mixing sizes.

2. EVERY 8-PX OBJECT IS DRAWN IN ROWS 8-15 OF ITS BOX, and so is ducking Kelly.
   That makes ONE placement rule serve the whole game: an object's bottom edge
   is always `y + 16`, so a thing resting on the floor is at `y = FLOORY - 16`
   whether it is standing Kelly, a ducked Kelly, a cart or a radio. Getting
   this wrong per-object is how a hazard ends up floating or buried.

Sprite bytes are QUADRANT-ORDERED for the VDP: 16 rows of the left half, then
16 rows of the right half.

Every DATA BYTE block here is an EVEN number of bytes. An odd run leaves the
assembler's location counter odd and silently misaligns every word table
defined after it (CLAUDE.md 3A) -- the failure mode is one array index
returning plausible garbage, for ever.

Run:  python3 genart.py      writes ../src/art.bas
"""

import os

# --------------------------------------------------------------------------
# SPRITES.  16 rows of 16 columns.  '#' on, '.' off.
# --------------------------------------------------------------------------

# Officer Kelly and Harry are TWO SPRITES TALL -- 24 px, built from a 16 px top
# sprite and the top half of a second one below it.  They used to be 16 px, and
# at that size they read as tokens rather than as a policeman chasing a crook.
#
# THE HEIGHT IS NOT FREE, AND THE ARITHMETIC WAS CHECKED BEFORE THE ART WAS
# DRAWN.  A band gives 32 px of air over the floor line, plus the 7 px of the
# ceiling row that sits below THAT row's 1 px slab line -- 39 px of real
# headroom.  A 24 px figure with the 14 px jump needs 38.  It fits, with one
# pixel spare, and every window in DESIGN.md 5a is unchanged: jumpable at a ball
# height of <= 8, duckable at >= 6, three pixels of overlap, and nothing free
# below 22.  Dropping the jump to 10 px to "make room" would have opened a DEAD
# BAND at 5 -- so the apex is load-bearing and must stay 14.
#
# The two sprites never share a scanline with each other, so a band still costs
# Kelly 1 + Harry 1 + two obstacles = four per line, which is the VDP's limit.

KELLY_TOP = """
....########....
....########....
....########....
################
################
..........####..
....######......
....######......
....######......
....######......
................
..........####..
..##############
..##############
..##############
..##############
"""

# THE ARMS SWING, AND THEY DO IT IN THE TUNIC'S OWN SPRITE. The reference
# swings them plainly enough to see at this size -- a skin-coloured hand
# appears beside the face on half the cycle -- but a hand of its own would be a
# fourth box on those rows, and four is the whole per-line budget with Harry
# present. Moving the ARMS inside the blue tunic pattern costs one extra
# pattern per facing and no boxes at all: they lift and spread on the frames
# where the legs are at full stride, and hang on the passing frames.
KELLY_TOP_B = """
....########....
....########....
....########....
################
################
..........####..
....######......
....######......
....######......
....######......
................
..........####..
..############..
..############..
..############..
..##############
"""

# THREE COLOURS PER FIGURE, AND THE HARDWARE DECIDES WHERE THE SEAMS GO.
# A TMS9918 sprite carries one colour, so a hat, a face and a body mean three
# sprites -- and the VDP counts sprite BOXES per scanline, not pixels, so an
# empty overlap costs exactly as much as a full one. Three 16 px boxes stacked
# inside a 24 px figure therefore overlap three-deep somewhere, and Kelly plus
# Harry would be SIX on the lines where they meet -- the endgame chase -- with
# two silently dropped.
#
# The arrangement that fits: TWO sprites share the top box (rows 0-15) and ONE
# sits in the bottom box (rows 16-23). Those two boxes never share a scanline,
# so an actor costs at most 2 and a meeting costs 4 -- exactly the limit, which
# is also why obstacles are suppressed on Harry's floor (DESIGN.md 5).
#
# The consequence is the interesting part: the top box holds only TWO colours,
# and the face sits between the hat and the torso. So HAT AND TORSO MUST SHARE
# A COLOUR. Kelly is a black hat over a black tunic with blue trousers; Harry
# is a striped cap over a striped body. It is not a stylistic choice.
#
# ONE COLOUR PER ROW is what keeps the bands legible: no scanline may carry
# pixels from two of an actor's sprites, or they would fight for the cell.
def band(art, keep):
    """Keep only rows in `keep`; blank the others. One sprite, one colour."""
    rows = art.strip("\n").split("\n")
    return "\n" + "\n".join(
        r if i in keep else "." * len(r) for i, r in enumerate(rows)) + "\n"


# A SPRITE'S BOX ONLY HAS TO COVER THE ROWS IT USES. The first version parked
# every band at the figure's top y, so all three boxes spanned rows 0-15 and an
# actor cost three boxes on every line of its upper half -- six with two actors,
# and one of them had to be sacrificed. But the y is free: a band whose pixels
# sit at figure rows 3-5 can be drawn at y-10 with the pattern pushed to the
# BOTTOM of its box, and then the box covers rows -10..5 and nothing lower.
# Placing each band's box over just its own rows brings a meeting down to FOUR
# boxes on the worst line, which is exactly the VDP's limit -- so nothing has
# to drop and Harry keeps his stripes.
def shift(art, n):
    """Slide the pattern n rows DOWN inside its 16-row box (negative = up)."""
    nl = chr(10)
    rows = art.strip(nl).split(nl)
    blank = "." * len(rows[0])
    out = []
    for i in range(16):
        j = i - n
        out.append(rows[j] if 0 <= j < len(rows) else blank)
    return nl + nl.join(out) + nl


# THE RUN IS FOUR FRAMES AND IT LEANS. Only rows 0-7 are used: the figure is
# 24 px, not 32.
#
# It was two frames, and both were SYMMETRIC about the centre line -- so the
# legs said nothing about which way he was going, and mirroring them for the
# other facing produced the identical pattern. Measured off the reference
# video (DESIGN.md 0g) the original runs a four-pose cycle with a clear
# forward lean: a long contact stride, a passing pose with the trailing leg
# swung under the body, and then the same two with the feet swapped.
#
# THE SWAP IS A MIRROR, WHICH IS WHY FOUR POSES COST TWO DRAWINGS. In a side
# view, "left foot forward" is the horizontal mirror of "right foot forward" --
# the facing lives in the hat, face and tunic, not in the legs. So the cycle is
#
#     A, B, mirror(A), mirror(B)
#
# and the same four patterns serve BOTH facings, just entered at a different
# point. Four real poses for the price of the two the symmetric pair already
# cost.
KELLY_LEG1 = """
..##############
..##############
..####....#####.
..####....#####.
.#####.....####.
.#####.....####.
..####.....####.
..####.....####.
................
................
................
................
................
................
................
................
"""

KELLY_LEG2 = """
..##############
..##############
..############..
...####..#####..
...####..#####..
...####..#####..
..#####..#####..
..#####..#####..
................
................
................
................
................
................
................
................
"""

# DUCKED: 8 px, drawn in rows 0-7 of a single sprite placed at FLOORY - 8.
#
# IT HAS A FRONT NOW. The old crouch was a symmetric blob -- mirroring it for
# the other facing produced a nearly identical shape, so ducking read as the
# figure being squashed rather than as him dropping into a crouch and still
# looking where he is going. The brim is the tell: it reaches further FORWARD
# than back, the head is tucked down behind it, the back hunches over the
# leading knee and the feet trail. Mirrored, all of that swaps and the crouch
# faces the other way.
KELLY_DUCK = """
################
################
....######......
....######......
..############..
.##############.
.####......####.
####........####
................
................
................
................
................
................
................
................
"""

# Harry Hooligan.  Flat cap and a sack over the shoulder -- "not a cop" from
# the silhouette alone, which is all you get at this size.
HARRY_TOP = """
....########....
....########....
################
################
...########.....
...########.....
...########.....
...########.....
...########.....
...########.....
...########.....
..############..
..############..
..############..
.##############.
.##############.
"""

HARRY_LEG1 = """
..############..
..############..
..###......###..
..###......###..
.###........###.
.###........###.
.####......####.
.####......####.
................
................
................
................
................
................
................
................
"""

HARRY_LEG2 = """
..############..
..############..
...##########...
....###..###....
....###..###....
...####..####...
...####..####...
..#####..#####..
................
................
................
................
................
................
................
................
"""


# THE BANDS, AND THEY ARE THE REFERENCE'S PROPORTIONS RATHER THAN A GUESS.
# Transcribed off the video onto the 2600's own pixel grid (DESIGN.md 0h), the
# original Kelly is 8 clocks by about 19 scanlines and reads:
#
#     rows 0-2  crown, 4 of 8 wide          rows 5-7   face, 3 of 8
#     row  3    brim, the FULL 8            rows 9-17  body, 6-7 of 8
#
# -- so his HEAD IS 42% OF HIS HEIGHT and the brim is a flat line right across
# him. Ours was a small head on a long thin body with wire arms and separated
# legs: a different character entirely, which is what "it does not look like
# the video" meant. These row sets are that 42% carried onto our 24 px figure,
# and the art above is the same silhouette at twice the horizontal resolution.
HAT = set(range(0, 6))          # crown, the full-width brim, and its back
FACE = set(range(6, 10))        # the one skin band
TORSO = set(range(10, 16))      # a blank neck row, then shoulders and tunic

# KELLY'S HAT IS ITS OWN SPRITE NOW, and that is what buys Harry a striped cap.
# While hat and tunic shared a slot, that slot's box had to span rows 0-15 and
# sat across every line of the upper body -- which left no room for a second
# stripe colour up at the cap. Split, each box covers only its own band:
# hat -13..2, face -10..5, tunic 6..21. The hat can also be BLACK again, which
# is what the reference has.
KELLY_HAT = shift(band(KELLY_TOP, HAT), 10)             # drawn at y-10
KELLY_BODY = shift(band(KELLY_TOP, TORSO), -10)         # drawn at y+10
KELLY_BODY_B = shift(band(KELLY_TOP_B, TORSO), -10)     # the arm-back frame
KELLY_FACE = shift(band(KELLY_TOP, FACE), 6)            # drawn at y-6
# HARRY WEARS STRIPES, AND HE CAN AFFORD THEM. Two colours alternating down a
# figure needs a second sprite over the same rows, which is a THIRD box in his
# top half -- five with Kelly's two, one past the VDP's four. He gets away with
# it because obstacles are suppressed on his floor (DESIGN.md 5), so the only
# line that can ever overflow is one where he is level with Kelly, and the
# overflow is arranged to drop the STRIPE sprite: it is the highest-numbered
# slot on those rows, so he degrades to plain white rather than losing a limb.
# HARRY IS STRIPED FROM CAP TO HEM. Both stripe colours run the full height of
# his upper half, so both boxes span rows 0-15 and neither can be tucked out of
# the way -- that is affordable only because Kelly's hat moved into its own
# box. His face is pushed DOWN instead (box 3..18) so it clears the cap rows,
# where his two stripe boxes and Kelly's two already make four.
# HARRY IS SHORTER AND HIS FACE IS BIGGER. Measured the same way: about 16
# scanlines, of which the face is a third -- a flat white cap with one black
# band, a big skin face, a striped body and legs that split wide apart. His
# stripes are horizontal bands about one scanline each, so at our resolution
# they are single rows.
# HARRY IS SHORTER AND HIS FACE IS BIGGER. Measured the same way (DESIGN.md
# 0h): about 17 scanlines, of which the FACE is a third -- a flat white cap
# with one black band across it, a big skin face, a striped body, and legs that
# split wide apart. That face is the thing that makes him read as a different
# character to Kelly at this size, and ours had it at half the size.
HSTRIPE = {3, 12, 14}
HCAP = set(range(0, 4))
HFACEB = set(range(4, 11))
HBODYB = set(range(11, 16))
HARRY_BODY = band(HARRY_TOP, (HCAP | HBODYB) - HSTRIPE)
HARRY_STRIPE = band(HARRY_TOP, (HCAP | HBODYB) & HSTRIPE)
HARRY_FACE = shift(band(HARRY_TOP, HFACEB), -4)         # drawn at y+4

# DUCKED, KELLY KEEPS HIS BRIM, and that is worth a third sprite. The crouch
# used to be two bands -- hat and body together in BLUE, face in skin -- which
# made the one feature that says "Kelly" at this size, the flat black brim
# right across him, disappear the moment he ducked. He stopped looking like
# himself and started looking like a blue lump.
#
# Three bands is three boxes on those eight rows instead of two. It is
# affordable because he does not need to duck on Harry's floor -- obstacles are
# suppressed there (DESIGN.md 5), so no biplane ever appears on it -- and if he
# ducks there anyway the VDP drops the HIGHEST-numbered sprites, which are
# Harry's, so the degradation lands on the crook and not on the player.
# assets/checkbands.py checks the count rather than trusting this paragraph.
KELLY_DHAT = band(KELLY_DUCK, set(range(0, 2)))         # the brim, BLACK
KELLY_DFACE = band(KELLY_DUCK, set(range(2, 4)))        # the face, skin
KELLY_DBODY = band(KELLY_DUCK, set(range(4, 8)))        # the crouch, blue

# --------------------------------------------------------------------------
# Obstacles.  All 8 px tall, all in rows 8-15.  See the note at the top.
# --------------------------------------------------------------------------

# A WIRE BASKET, and you can see through it. The reference cart is a mesh of
# uprights between two rails on a solid wheeled base; the first version was a
# plain hollow rectangle, which reads as a box rather than as a trolley.
CART = """
................
................
................
................
................
................
................
................
..############..
..#.#.#.#.#..#..
..#.#.#.#.#..#..
..############..
..############..
...#........#...
..###......###..
..###......###..
"""

# SOLID, not a ring. The reference ball is a filled disc; drawn as an outline
# it read as a doughnut and, worse, the store showed through the middle of it,
# which made it look like scenery rather than something in your way.
BALL = """
................
................
................
................
................
................
................
................
.....######.....
...##########...
..############..
.##############.
.##############.
..############..
...##########...
.....######.....
"""

# A CATHEDRAL RADIO IS A DOME WITH AN AERIAL, not a box with a hole in it.
# The first version was a rectangle with an inner rectangle, which reads as a
# crate or a window -- and this is a thing you must JUMP, so what it is has to
# be legible in the half second before you reach it. The reference is an arched
# case, widest at the foot, with two little prongs on top.
RADIO = """
................
................
................
................
................
................
................
................
....##....##....
.....######.....
...##########...
..############..
..############..
..############..
..############..
..############..
"""

# Toy biplane.  Flies at head height; the only thing in the store that kills.
#
# THE PROPELLER ARC IS IN THE PATTERN, NOT A SECOND SPRITE. Video (DESIGN.md
# 0b) shows a dark green body with a LIGHT green dashed prop above the nose,
# and a TMS9918 sprite carries exactly ONE colour -- two tones means two
# sprites. The scanline budget forbids that: 1 record says a band already
# costs Kelly 1 + Harry 1 + two obstacles = four, which is the hardware's
# per-line limit, and a fifth sprite drops out. Dropping THE ONE OBSTACLE THAT
# KILLS is a worse bug than a colour compromise, so the whole plane is light
# green: right hue family, the dashed arc still reads as a spinning prop, and
# it stays visible against the medium green store.
#
# THE 8 PX ENVELOPE IS UNCHANGED -- prop on the first row, body on the rest,
# bottom edge still row 15. The duck/jump windows in 5a depend on that box, so
# growing the sprite upward to fit the prop would have quietly moved them.
PLANE_R = """
................
................
................
................
................
................
................
................
...##..##..##...
.......##.......
....########....
..############..
.###########.##.
..############..
....########....
.......##.......
"""

# Propeller phase 2. THE PROP IS THE ONLY MOVING PART A TOY PLANE HAS, and a
# static dashed arc reads as a decal rather than as a spinning blade. Two
# frames alternating between a broken arc and a solid disc is the whole trick
# -- it is how every 8-bit game has ever drawn a propeller, and it costs one
# extra pattern pair per facing.
PLANE_R2 = """
................
................
................
................
................
................
................
................
....########....
.......##.......
....########....
..############..
.###########.##.
..############..
....########....
.......##.......
"""

'''Money bags and suitcases are CHARACTERS, not sprites -- see CHARS below.

A band already carries Kelly plus three obstacles, which is exactly the VDP's
four-sprites-per-scanline limit. A fifth sprite on that line does not flicker,
it VANISHES -- and the highest-numbered slot is the one dropped, which would
have been the collectible. A prize that disappears when the floor gets busy is
worse than no prize at all, and it would look like a scoring bug rather than a
sprite bug. They are static and sit on the slab, so a character costs nothing.
'''


# --------------------------------------------------------------------------
# THE ESCALATOR IS RENDERED, NOT HAND-DRAWN.
#
# Four hand-drawn characters gave a bare diagonal staircase -- no band, no
# rails, no depth -- and it never looked like the reference no matter how the
# treads were nudged. The reference is a PARALLELOGRAM: two parallel rails
# eight pixels apart running at 1:2, closed at both ends, with white step
# wedges inside it -- a flat tread with a riser dropping from its leading end.
#
# That shape does not decompose into a small repeating tile by hand, because
# the band crosses character boundaries at a different offset in every column.
# So it is drawn once as a 64x40 bitmap -- the true size of a flight, eight
# characters across and five down -- and SLICED into characters, with the
# distinct cells deduplicated. The store templates then place the cells from
# the same grid, so the art and the placement can never drift apart.
# THE FLIGHT IS TRANSCRIBED FROM THE COLECOVISION SCREENSHOT, PIXEL BY PIXEL.
#
# Dumping that shot as ASCII settled three things I had been getting wrong by
# reasoning about it instead of reading it:
#
#  1. THE SLOPE IS 1:2 -- eight pixels across per four down. The 2.7 I measured
#     earlier came from a bounding box that included the flat end caps, so I
#     flattened a correct angle into a wrong one.
#  2. EACH STEP IS DRAWN IN PERSPECTIVE, not as a flat block. Per step: the
#     TREAD's left edge holds still while its right edge pulls in two pixels a
#     row (9, 7, 5, 3), and the RISER is a constant 8-wide block sliding two
#     pixels left a row. That pair is what reads as a staircase seen from the
#     side; a filled band with a stepped edge never will.
#  3. A separate 3-pixel BALUSTRADE runs 18 px to the left of each tread.
#
# Offsets below are measured off rows 100-104 of cv327.png: tread left 122,
# riser left 134 (+12), balustrade 104 (-18), the next step 8 px on.
#
# IT OCCUPIES THE BAND'S AIR ONLY -- four rows, never the floor bar. A cell
# holding both the flight and a floor bar would need four colours in one 8x1
# row and the VDP gives two, so anything drawn over a bar ERASES it: that is
# what wiped the floor and the storey above it. Reaching from the top of one
# bar to the underside of the next is what connects the floors.
FLIGHT_W, FLIGHT_H = 120, 48
FLIGHT_COLS, FLIGHT_ROWS = 15, 6
STEP_RUN, STEP_RISE = 8, 4
# TEN STEPS, RISING THE FULL 40 PX BETWEEN FLOOR SURFACES, so the top tread
# lands ON the floor bar above exactly as the reference does.
#
# I dropped this to eight once, on the belief that a character carrying both a
# floor bar and the flight needed FOUR colours in one 8x1 scan line. That was
# simply wrong. Colour here is per scan line, and any single line of such a
# character needs only TWO: whatever the floor shows on that line, and black
# for the flight. So the cells that land on the bar get COMPOSITE colours --
# the floor's, line for line -- and the bar survives underneath the stairs.
# Shortening the flight instead also dragged the handrail up away from the
# steps, because the cap keeps its offset above the staircase.
STEPS = 10
TREAD_W = 9              # at the top of a step, narrowing by 2 a row
RISER_W = 8
RISER_OFF = 12           # riser left, relative to the tread's left edge
BALU_OFF = 18            # balustrade left, the other way
BALU_W = 3
TREAD_X = 96             # origin, chosen so nothing lands at a negative x

# THE ENDS ARE NOT THE MIDDLE, and leaving them off is what made this read as
# a repeating texture rather than a staircase. Measured off cv327.png:
#
#   FOOT  (rows 114-119) the balustrade stops descending and becomes a 2 px
#         VERTICAL NEWEL POST for six rows -- the rail curling down to meet
#         the floor.
#   HEAD  (rows 81-88) it runs HORIZONTAL for 16 px, starting 14 px right of
#         the diagonal's top, and then drops as a 3 px post at the far end.
#
# The head cap sits ABOVE the diagonal, which is why the flight is five rows
# where the staircase alone is four. That top row is the only part that
# overlaps the floor bar above -- two or three characters wide -- and the
# reference overwrites the bar in exactly the same place.
HEAD_LIFT = 8            # rows of head cap above the staircase
HEAD_BAR_OFF = 14        # horizontal rail start, right of the diagonal top
HEAD_BAR_W = 16
POST_W = 2               # the foot's newel post
POST_ROWS = 6


def _flight_bitmap(step_shift=0):
    """One west flight (head at the LEFT), as rows of bits.

    Built in the reference's own orientation -- head at the RIGHT -- and then
    mirrored, so every transcribed offset stays exactly as measured.

    THE FRAME IS DRAWN FIRST AND NEVER MOVES; the stairs slide through it and
    are CLIPPED to it. Extending the step run past both ends is what lets steps
    enter and leave, but without a clip they simply ran out past the top of the
    escalator -- stairs hanging in the air beyond the handrail.
    """
    px = [[0] * FLIGHT_W for _ in range(FLIGHT_H)]

    def span(x0, w, y):
        for x in range(x0, x0 + w):
            if 0 <= x < FLIGHT_W and 0 <= y < FLIGHT_H:
                px[y][x] = 1

    # The frame's geometry, worked out before anything is drawn because it is
    # what bounds the stairs.
    top_x = TREAD_X - BALU_OFF                  # balustrade at the top step
    bar_x = top_x + 2 * (HEAD_LIFT - 2) + 2     # the head rail's left end
    last = FLIGHT_H - POST_ROWS - 1
    fk, fm = divmod(last - HEAD_LIFT, STEP_RISE)
    post_x = TREAD_X - STEP_RUN * fk - BALU_OFF - 2 * fm - 2
    frame_l = post_x                            # the foot's newel post
    frame_r = bar_x + HEAD_BAR_W                # just past the head's post

    def stepspan(x0, w, y):
        """A run of step, clipped to the frame at both ends and at the top."""
        if y < HEAD_LIFT:
            return
        for x in range(max(x0, frame_l), min(x0 + w, frame_r)):
            if 0 <= x < FLIGHT_W and 0 <= y < FLIGHT_H:
                px[y][x] = 1

    # THE STEPS TRAVEL ALONG THE SLOPE, not sideways. Shifting only x sheared
    # the staircase horizontally -- the stairs slid across the frame instead of
    # climbing it. A step moves STEP_RUN across for STEP_RISE up, so the shift
    # carries half as much vertical as horizontal.
    for k in range(-2, STEPS + 2):
        tl = TREAD_X - STEP_RUN * k + step_shift
        for m in range(STEP_RISE):
            y = HEAD_LIFT + STEP_RISE * k + m - step_shift // 2
            stepspan(tl, TREAD_W - 2 * m, y)                 # the tread
            stepspan(tl + RISER_OFF - 2 * m, RISER_W, y)     # its riser

    # The balustrade is FRAME, so it is drawn once and statically. It used to
    # be emitted inside the step loop, which slid it along with them -- which
    # happened to look right only because a straight line shifted along its own
    # direction is indistinguishable from itself.
    for y in range(HEAD_LIFT, FLIGHT_H - POST_ROWS):
        span(TREAD_X - BALU_OFF - 2 * (y - HEAD_LIFT), BALU_W, y)

    # THE FOOT'S NEWEL POST picks up exactly where the diagonal stopped, two
    # pixels further left.
    for y in range(FLIGHT_H - POST_ROWS, FLIGHT_H):
        span(post_x, POST_W, y)

    # THE HEAD CAP IS A CONTINUOUS LOOP: the diagonal keeps climbing above the
    # top step, turns horizontal, and a post drops from the far end of that
    # rail back down to meet the staircase.
    for y in range(2, HEAD_LIFT):
        span(top_x + 2 * (HEAD_LIFT - y), BALU_W, y)
    span(bar_x, HEAD_BAR_W, 0)
    span(bar_x, HEAD_BAR_W, 1)
    for y in range(2, HEAD_LIFT + 1):
        span(bar_x + HEAD_BAR_W - 1, 2, y)

    return [list(reversed(r)) for r in px]                  # head to the LEFT


def _cellpat(px, r, c):
    """One 8x8 character out of a flight bitmap."""
    out = []
    for y in range(8):
        b = 0
        for x in range(8):
            if px[r * 8 + y][c * 8 + x]:
                b |= 0x80 >> x
        out.append(b)
    return tuple(out)


def _mirror_bitmap(px):
    return [list(reversed(r)) for r in px]


# FOUR PHASES OF 2 PX. The step pattern repeats every 8 across and 4 down, so
# four even shifts cover one full cycle and each carries a whole pixel of
# vertical. Two phases cannot work at all: a half-period shift is symmetric,
# so there is no telling up from down and the eye reads it as shaking. Three
# would need a shift of 8/3, and half of that is not a pixel.
PHASES = 4


def _slice_phases(mirrored):
    """Cut every animation phase at once, and share a character between two
    grid positions ONLY IF THEY MATCH IN ALL OF THEM.

    Deduplicating on phase 0 alone is wrong and the round-trip check caught it:
    a clipped cell at the end of the flight can happen to equal an interior
    cell while the steps are at rest, and then diverge the moment they move --
    so one of the two positions draws the other's picture. Keying on the whole
    phase set makes that impossible by construction.
    """
    bitmaps = []
    for p in range(PHASES):
        # POSITIVE: the steps travel toward the HEAD, which is the way an
        # up escalator carries you. Negative ran them backwards down it.
        # Even shifts only: a diagonal step needs half as much vertical
        # as horizontal, and half of an odd number is not a pixel.
        px = _flight_bitmap(2 * p)
        bitmaps.append(_mirror_bitmap(px) if mirrored else px)

    keys, grid = [], []
    for r in range(FLIGHT_ROWS):
        row = []
        for c in range(FLIGHT_COLS):
            key = tuple(_cellpat(px, r, c) for px in bitmaps)
            if not any(any(pat) for pat in key):
                row.append(None)
            else:
                if key not in keys:
                    keys.append(key)
                row.append(keys.index(key))
        grid.append(row)
    # phases[p][i] is the pattern for cell i at phase p
    phases = [[list(k[p]) for k in keys] for p in range(PHASES)]
    return phases, grid


ESC_W_PHASES, ESC_W_GRID = _slice_phases(False)
ESC_E_PHASES, ESC_E_GRID = _slice_phases(True)
ESC_W_CELLS = ESC_W_PHASES[0]
ESC_E_CELLS = ESC_E_PHASES[0]


ESC_E_PHASES, ESC_E_GRID = _slice_phases(True)
ESC_W_CELLS = ESC_W_PHASES[0]
ESC_E_CELLS = ESC_E_PHASES[0]


def mirror(art):
    """Flip 16-wide art left-to-right. THE VDP CANNOT MIRROR A SPRITE -- there
    is no flip bit -- so every actor needs both facings drawn out in full."""
    nl = chr(10)
    rows = art.strip(nl).split(nl)
    return nl + nl.join("".join(reversed((r + "." * 16)[:16]))
                        for r in rows) + nl


def sprite_bytes(art):
    """16x16 art -> 32 bytes, QUADRANT-ORDERED for the VDP: sixteen rows of the
    LEFT half, then sixteen rows of the right. Read it as sequential rows and
    every sprite comes out shredded into vertical stripes."""
    nl = chr(10)
    rows = art.strip(nl).split(nl)
    if len(rows) != 16:
        raise SystemExit("sprite needs 16 rows, got %d" % len(rows))
    left, right = [], []
    for r in rows:
        r = (r + "." * 16)[:16]
        lb = rb = 0
        for c in range(8):
            if r[c] == "#":
                lb |= 0x80 >> c
            if r[c + 8] == "#":
                rb |= 0x80 >> c
        left.append(lb)
        right.append(rb)
    return left + right


def char_bytes(art):
    """Art rows, or a ready-made list of 8 pattern bytes."""
    if isinstance(art, (list, tuple)):
        return list(art)
    nl = chr(10)
    rows = art.strip(nl).split(nl)
    if len(rows) != 8:
        raise SystemExit("char needs 8 rows, got %d" % len(rows))
    out = []
    for r in rows:
        r = (r + "." * 8)[:8]
        b = 0
        for c in range(8):
            if r[c] == "#":
                b |= 0x80 >> c
        out.append(b)
    return out


def colour_block(name, fg, bg):
    """EIGHT colour bytes per char: this mode colours each 8x1 scan line
    separately. One byte per char reads ROM as colour data (CLAUDE.md 3A).

    fg and bg may each be one colour or a list of eight -- the per-row form is
    what lets a character carry THREE colours, which the floor bar needs.
    """
    fgs = list(fg) if isinstance(fg, (list, tuple)) else [fg] * 8
    bgs = list(bg) if isinstance(bg, (list, tuple)) else [bg] * 8
    if len(fgs) != 8 or len(bgs) != 8:
        raise SystemExit("%s: colour lists must be 8 long, got %d/%d"
                         % (name, len(fgs), len(bgs)))
    return [(f << 4) | b for f, b in zip(fgs, bgs)]


def emit(fh, label, data, comment=""):
    """One DATA BYTE block. EVERY BLOCK MUST BE AN EVEN NUMBER OF BYTES: an odd
    run leaves the assembler's location counter odd and silently misaligns
    every word table defined after it (CLAUDE.md 3A)."""
    if len(data) % 2:
        raise SystemExit("%s is %d bytes -- ODD blocks misalign every word "
                         "table after them" % (label, len(data)))
    fh.write("\n%s:%s\n" % (label, ("\t' " + comment) if comment else ""))
    for i in range(0, len(data), 8):
        fh.write("\tDATA BYTE %s\n"
                 % ",".join("$%02X" % b for b in data[i:i + 8]))


# THE LAYOUT IS A CONTRACT WITH THE SELECTION CODE, and it is arranged so that
# code is three statements instead of two branches:
#
#   * Everything that FACES -- hat, face, tunic, crouch -- comes in a RIGHT
#     block followed by a LEFT block of the same shape, so switching facing is
#     one fixed offset added to each (P_KFACING for Kelly, P_HFACING for
#     Harry) rather than a duplicated if/else arm.
#   * The LEGS DO NOT FACE and are shared by both. In a side view "left foot
#     forward" is the horizontal mirror of "right foot forward", so the four
#     poses are A, B, mirror(A), mirror(B) and the same four serve either
#     direction -- entered at a different point in the cycle, which is
#     invisible because the phase runs continuously anyway. Four real poses for
#     the price of the two the old symmetric pair cost.
#   * The four are CONSECUTIVE, so picking one is `first + 4*phase` with the
#     phase taken from two bits of the animation counter: two IFs adding 4 and
#     8, and no divide (`/` compiles to a real TMS9900 DIV, CLAUDE.md 3A).
SPRITES = [
    ("spr_kelly", [("KHAT", KELLY_HAT), ("KFACE", KELLY_FACE),
                   ("KBODY", KELLY_BODY), ("KBODYB", KELLY_BODY_B),
                   ("KDHAT", KELLY_DHAT), ("KDFACE", KELLY_DFACE),
                   ("KDBODY", KELLY_DBODY),
                   ("KLHAT", mirror(KELLY_HAT)),
                   ("KLFACE", mirror(KELLY_FACE)),
                   ("KLBODY", mirror(KELLY_BODY)),
                   ("KLBODYB", mirror(KELLY_BODY_B)),
                   ("KLDHAT", mirror(KELLY_DHAT)),
                   ("KLDFACE", mirror(KELLY_DFACE)),
                   ("KLDBODY", mirror(KELLY_DBODY)),
                   ("KLEG1", KELLY_LEG1), ("KLEG2", KELLY_LEG2),
                   ("KLEG3", mirror(KELLY_LEG1)),
                   ("KLEG4", mirror(KELLY_LEG2))],
     "Kelly: RIGHT hat/face/tunic/tunic-arm-up/duck-hat/duck-face, then the "
     "same LEFT (+24), then the FOUR shared run frames. Patterns 0..60"),
    ("spr_harry", [("HBODY", HARRY_BODY), ("HFACE", HARRY_FACE),
                   ("HSTRIPE", HARRY_STRIPE),
                   ("HLBODY", mirror(HARRY_BODY)),
                   ("HLFACE", mirror(HARRY_FACE)),
                   ("HLSTRIPE", mirror(HARRY_STRIPE)),
                   ("HLEG1", HARRY_LEG1), ("HLEG2", HARRY_LEG2),
                   ("HLEG3", mirror(HARRY_LEG1)),
                   ("HLEG4", mirror(HARRY_LEG2))],
     "Harry: RIGHT white/face/stripes, then the same LEFT (+12), then the "
     "FOUR shared run frames. Patterns 64..100"),
    ("spr_cart", [("CART", CART)], "shopping cart -- jump it"),
    ("spr_ball", [("BALL", BALL)],
     "beach ball -- jump it LOW, duck it HIGH"),
    ("spr_radio", [("RADIO", RADIO)], "cathedral radio, stationary"),
    ("spr_plane", [("PLANE", PLANE_R), ("PLANEL", mirror(PLANE_R)),
                   ("PLANE2", PLANE_R2), ("PLANEL2", mirror(PLANE_R2))],
     "toy biplane -- DUCK. The only thing that kills."),
]

# name -> SPRITE PATTERN NUMBER, which is what KEYSTONE.bas's P_* constants
# have to agree with. A sprite is four patterns wide, so the n-th sprite in
# this table is pattern 4n -- and every one of those numbers is written by
# hand in the source, where nothing but assets/checkchars.py connects the two.
SPR = {}
_n = 0
for _label, _arts, _c in SPRITES:
    for _name, _a in _arts:
        SPR[_name] = 4 * _n
        _n += 1
SPR_FIRST = {}
for _label, _arts, _c in SPRITES:
    SPR_FIRST[_label] = SPR[_arts[0][0]]
    SPR_FIRST[_label + "_n"] = len(_arts)


# The TMS9918's sixteen colours. Its two GREENS are nearly the same to the eye
# (12 is (33,176,59), 2 is (33,200,66)), which is a trap the reference walks
# straight into -- see the note on the store characters below.
TRANSP, BLACK, MGREEN, LGREEN = 0, 1, 2, 3
DBLUE, LBLUE, DRED, CYAN = 4, 5, 6, 7
MRED, LRED, DYELL, LYELL = 8, 9, 10, 11
DGREEN, MAGENTA, GRAY, WHITE = 12, 13, 14, 15

# --------------------------------------------------------------------------
# STORE CHARACTERS.  8x8 patterns plus an 8-byte colour block each: this is the
# per-8x1-scanline colour mode, so DEFINE COLOR reads EIGHT bytes per character,
# not one (CLAUDE.md 3A).  Supply fewer and it reads whatever follows in ROM as
# colour data.
#
# THE PALETTE IS MEASURED FROM GAMEPLAY VIDEO, not from screenshots and not
# from memory -- see DESIGN.md 0b and 0c for what that corrected. The notes
# that used to sit against each entry were lost when this table was destroyed
# by a bad regex; the bytes below are the recovered originals, so the artwork
# is unchanged. The reasoning that survives:
#
#   * The floor is a THICK OLIVE BAR with a light top row, not a hairline --
#     three colours in one character, which is why some entries carry a LIST
#     of eight colours rather than one pair.
#   * DARK GREEN IS NOT A COLOUR next to medium green on this VDP (12 is
#     (33,176,59), 2 is (33,200,66)). Where the reference uses it against the
#     store -- the lift shaft -- use GREY instead.
#   * The sky is CYAN because Kelly's tunic is dark blue and he vanished
#     against a dark blue sky on the roof.
#   * Blank cells still need their own code: what they show is their
#     BACKGROUND colour, which is the whole point of them.
#
# Identical entries are merged automatically further down, so listing SHELFB
# beside SHELFT (or ROOFBG beside SHAFT) costs nothing -- they resolve to one
# character code.
CHARS_BASE = [
    ("SLAB", 0, """
########
........
........
........
........
........
........
........
""", LYELL, [DYELL, DYELL, DYELL, DYELL, DYELL, MGREEN, MGREEN, MGREEN]),


    ("SHELFT", 0, """
########
########
########
########
########
########
########
########
""", DBLUE, DBLUE),

    ("SHELFB", 0, """
########
########
########
########
########
########
########
########
""", DBLUE, DBLUE),

    ("COUNTR", 0, """
########
########
########
########
########
########
########
########
""", GRAY, GRAY),

    ("SHAFT", 0, """
........
........
........
........
........
........
........
........
""", WHITE, GRAY),

    ("EDOOR", 0, """
........
........
........
........
........
........
........
........
""", WHITE, GRAY),

    ("ECAR", 0, """
........
........
........
........
........
........
........
........
""", WHITE, CYAN),


    ("PARAP", 0, """
..##..##
..##..##
#####.##
########
########
########
########
########
""", MRED, CYAN),

    ("SKY", 0, """
........
........
........
........
........
........
........
........
""", WHITE, CYAN),

    ("WALL", 0, """
........
........
........
........
........
........
........
........
""", WHITE, MGREEN),

    ("KOPIC", 0, """
..####..
.######.
.#.##.#.
..####..
.######.
.##..##.
.##..##.
.#....#.
""", WHITE, DBLUE),

    ("EXITC", 0, """
########
#......#
#.####.#
#.#..#.#
#.#..#.#
#.####.#
#......#
########
""", WHITE, DBLUE),

    ("BAG", 0, """
..####..
.##..##.
########
########
##.##.##
########
.######.
..####..
""", LYELL, MGREEN),

    ("CASE", 0, """
...##...
.######.
########
########
###..###
########
########
........
""", DRED, MGREEN),

    ("ROOFS", 0, """
########
########
........
........
........
........
........
........
""", WHITE, GRAY),

    ("ROOFBG", 0, """
........
........
........
........
........
........
........
........
""", WHITE, GRAY),

    ("EDHALF", 0, """
##....##
##....##
##....##
##....##
##....##
##....##
##....##
##....##
""", BLACK, CYAN),

    ("ENDWALL", 0, """
##.#####
##.#####
........
#####.##
#####.##
........
##.#####
##.#####
""", GRAY, DGREEN),

    # THE STRIP EITHER SIDE OF THE SCANNER. The canvas is 16 chars wide and
    # centred, so eight columns at each end of rows 21-23 are not part of it.
    # They held the SPACE character, whose colour is black on CYAN -- the
    # HUD's sky, on row 0, where it belongs -- so the radar sat in a cyan
    # strip with margins that stopped at its own edges, and the gap above and
    # below it read as a border round a panel rather than as space. The 2600
    # puts its scanner in a grey band the width of the screen, so this is
    # grey. The font's colour cannot be repurposed for these rows: the title
    # screen prints at rows 16, 19 and 21, and recolouring the bottom third
    # of the font would take that text with it. One blank character is
    # cheaper than the alternative and cannot affect anything else.
    ("SCANBK", 0, """
........
........
........
........
........
........
........
........
""", GRAY, GRAY),

]

# The scanner canvas: 48 characters (16 cols x 3 rows) that start blank and are
# drawn into by VPOKEing the PATTERN table directly, so a moving dot costs two
# writes and no name-table traffic at all.

# THE FLIGHT CELLS ARE SPLICED IN AND THE WHOLE TABLE IS RENUMBERED, so no
# character code is ever written down by hand. Hard-coded codes are how the
# second collectible ended up drawing an EXIT DOOR: a renumbering somewhere
# else moved the table underneath a literal 113 that nobody thought to check.
# genstore.py imports CODES from here rather than keeping its own copy.
# ONLY THE CELLS THAT ACTUALLY MOVE ARE RE-DEFINED, AND THAT IS MEASURED, NOT
# ASSUMED. The animated block used to be "everything except the head cap" --
# eighteen cells, of which SIX move. The balustrade, the frame and the foot are
# byte-identical in all four phases, so three quarters of the phase tables said
# nothing at all, at 32 bytes a cell.
#
# The same mistake in the other direction is what froze the top of the flight:
# the row that crosses the floor above is drawn with the COMPOSITE characters
# (same pattern, floor colours -- see BAR_BG below), and those are separate
# character codes. They were never in the animated block, so the top two steps
# of every staircase stood still while the rest climbed. Whether a cell moves
# is a property of its PATTERN, so the composites move exactly when their plain
# twins do, and they belong in the block for the same reason.
def _movers(phases):
    """Indices whose pattern differs between phases -- the steps, and only them."""
    return [i for i in range(len(phases[0]))
            if any(phases[p][i] != phases[0][i] for p in range(1, PHASES))]


_W_MOVE = _movers(ESC_W_PHASES)
_E_MOVE = _movers(ESC_E_PHASES)


def _used(grid):
    return sorted({c for r in grid for c in r if c is not None})


# THE CELLS THAT CROSS A FLOOR GET A SECOND, COMPOSITE COPY: same pattern, but
# coloured line-for-line as the floor is, with black for the flight. Grid row 1
# is the row that lands on the bar; grid row 0 is the head cap's own row.
#
# The floor bar (see SLAB) is one light row, four olive, three green. Drawn
# with those as the BACKGROUND and black as the foreground, a character shows
# the bar wherever the flight is not -- so the floor runs across underneath the
# staircase instead of being punched through by it.
BAR_BG = [LYELL] + [DYELL] * 4 + [MGREEN] * 3

# THE ROOF IS NOT A SHOPPING FLOOR AND IS NOT COLOURED LIKE ONE. The flight up
# from floor 3 crosses into the roof band, where the "floor" is the grey DECK
# (two white rows over grey) and the air above it is grey rather than green.
# Composites for that crossing therefore need the roof's colours, not the
# store's -- the same idea, different palette. Only the WEST flight climbs to
# the roof (floor 3's escalator is at the west end), so only it needs them.
DECK_BG = [WHITE, WHITE] + [GRAY] * 6      # roof row 4, the deck itself
ROOFAIR_BG = [GRAY] * 8                    # roof row 3, the grey backdrop

# (name, cell index, that direction's phases, that direction's movers, bg)
_PLAIN = [("ESCW%d" % i, i, ESC_W_PHASES, _W_MOVE, MGREEN) for i in _used(ESC_W_GRID)] \
       + [("ESCE%d" % i, i, ESC_E_PHASES, _E_MOVE, MGREEN) for i in _used(ESC_E_GRID)]

_COMP = []
for _w, _grid, _phs, _mv in (("ESCW", ESC_W_GRID, ESC_W_PHASES, _W_MOVE),
                             ("ESCE", ESC_E_GRID, ESC_E_PHASES, _E_MOVE)):
    for _i in sorted({c for c in _grid[1] if c is not None}):
        _COMP.append(("%sB%d" % (_w, _i), _i, _phs, _mv, BAR_BG))
for _i in sorted({c for c in ESC_W_GRID[0] if c is not None}):
    _COMP.append(("ESCWR%d" % _i, _i, ESC_W_PHASES, _W_MOVE, ROOFAIR_BG))
for _i in sorted({c for c in ESC_W_GRID[1] if c is not None}):
    _COMP.append(("ESCWD%d" % _i, _i, ESC_W_PHASES, _W_MOVE, DECK_BG))

# MOVERS FIRST, AND WEST BEFORE EAST. One DEFINE CHAR per phase covers exactly
# the movers and everything static sits past the end of the range -- but only
# ONE DIRECTION is ever on screen (screen 0 carries a west flight, screen 7 an
# east one), so grouping them by direction lets esc_tick rewrite just that half.
#
# THAT IS A FRAME-RATE FIX, NOT A TIDY-UP. Rewriting all fifteen cells every
# pass is 120 bytes of pattern table, which is the only per-pass work unique to
# those two screens -- and they were the two screens that visibly ran slow, with
# the legs and the footsteps dragging because their counters were per-pass.
# West needs nine cells and east six, so the write drops to 72 or 48 bytes.
def _isw(e):
    return e[0].startswith("ESCW")


ESC_ANIM = ([e for e in _PLAIN + _COMP if e[1] in e[3] and _isw(e)]
            + [e for e in _PLAIN + _COMP if e[1] in e[3] and not _isw(e)])
ESC_ANIM_W = len([e for e in ESC_ANIM if _isw(e)])
ESC_STATIC = [e for e in _PLAIN + _COMP if e[1] not in e[3]]
ESC_ANIM_N = len(ESC_ANIM)
ESC_ANIM_E = ESC_ANIM_N - ESC_ANIM_W

_SPLICED = []
for _e in CHARS_BASE:
    if _e[0] == "PARAP":          # the flight cells go in here
        for _n, _i, _phs, _mv, _bg in ESC_ANIM + ESC_STATIC:
            # BLACK, as the ColecoVision draws it -- a black staircase
            # under a black handrail, with the surface behind showing
            # through: green for the store, the floor bar where it
            # crosses one, grey and white on the roof.
            _SPLICED.append((_n, 0, _phs[0][_i], BLACK, _bg))
    _SPLICED.append(_e)


# IDENTICAL CHARACTERS SHARE ONE CODE. Several of these were the same 8x8 twice
# over -- the top and bottom halves of a counter are both a solid block, and the
# lift shaft, its doorway and the grey roof backdrop are all a blank cell on
# grey. At 16 bytes each (pattern plus its eight colour bytes) in a ROM with a
# few hundred bytes spare, that is worth collecting automatically rather than
# noticing by eye: merging on (pattern, foreground, background) keeps working
# as the art changes, and it costs nothing at run time because a name that
# resolves to a shared code draws exactly the same cell.
CHARS, CODES = [], {}
_seen = {}
for _n, _c, _a, _f, _b in _SPLICED:
    # fg/bg may each be a single colour or a list of eight, so both are
    # normalised before being used as a dictionary key.
    _key = (tuple(char_bytes(_a)),
            tuple(_f) if isinstance(_f, (list, tuple)) else _f,
            tuple(_b) if isinstance(_b, (list, tuple)) else _b)
    # ANIMATED CELLS NEVER SHARE A CODE. Two flight cells can look identical
    # while the steps are at rest and differ the moment they move, so merging
    # them on their phase-0 picture would make one of them draw the other's
    # animation. Cheaper to spend three characters than to reason about it.
    if _n.startswith("ESCW") or _n.startswith("ESCE"):
        _key = (_n,) + _key
    if _key not in _seen:
        _seen[_key] = 96 + len(CHARS)
        CHARS.append((_n, _seen[_key], _a, _f, _b))
    CODES[_n] = _seen[_key]

# THE MOVING CELLS MUST STAY CONTIGUOUS, AND START THE RUN -- one DEFINE CHAR
# per phase rewrites exactly them, so a gap would animate a bystander and a
# stray would freeze a step. Checked, not assumed: the dedup above runs between
# here and the ordering, and it is the sort of thing that goes wrong quietly.
ESC_FIRST = CODES[ESC_ANIM[0][0]]
ESC_ANIM_CODES = [CODES[_n] for _n, _i, _p, _m, _b in ESC_ANIM]
if ESC_ANIM_CODES != list(range(ESC_FIRST, ESC_FIRST + ESC_ANIM_N)):
    raise SystemExit("moving flight cells are not contiguous: %r"
                     % ESC_ANIM_CODES)
_ESC_ALL = [CODES[_n] for _n, _i, _p, _m, _b in ESC_ANIM + ESC_STATIC]
ESC_N = len(_ESC_ALL)
if sorted(_ESC_ALL) != list(range(ESC_FIRST, ESC_FIRST + ESC_N)):
    raise SystemExit("flight cells are not contiguous: %r" % sorted(_ESC_ALL))

# AND EVERY CELL WHOSE PATTERN CHANGES MUST BE INSIDE THAT RUN. This is the
# check that would have caught the frozen top steps: the composites that cross
# the floor move exactly when their plain twins do, and being outside the run
# is not visible anywhere in the source -- it just leaves part of the staircase
# standing still.
_frozen = [_n for _n, _i, _p, _m, _b in ESC_STATIC if _i in _m]
if _frozen:
    raise SystemExit("these cells MOVE but sit outside the animated run, so "
                     "they would be drawn frozen: %r" % _frozen)

# The scanner canvas sits ABOVE the store characters. It was at 144 and the
# store table grew past it, which would have had the two silently overwriting
# each other's patterns -- so the overlap is now checked, below, rather than
# left to be noticed on screen.
SCAN_FIRST, SCAN_N = 160, 48

# The first pixel row of the instrument inside its 24-row canvas -- the top
# margin. Four levels of four rows is 16, so the same number is left at the
# bottom. KEYSTONE.bas's scan_base adds this to (3-fl)*4; the two have to
# agree, so checkscan.py compares them.
SCAN_TOP = 4

if 96 + len(CHARS) > SCAN_FIRST:
    raise SystemExit(
        "store characters reach %d and the scanner canvas starts at %d -- "
        "they would overwrite each other. Move SCAN_FIRST up (and the "
        "matching bases in KEYSTONE.bas: DEFINE COLOR, scan_canvas, scan_pat, "
        "scan_addr, scan_wipe, scan_colour)."
        % (96 + len(CHARS) - 1, SCAN_FIRST))



def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "src", "art.bas")

    with open(out, "w") as fh:
        fh.write("""\t' Keystone Kapers art -- GENERATED by assets/genart.py. Do not edit; regenerate.
\t'
\t' EVERY SPRITE IS 16x16: sprite size and magnification are GLOBAL on the
\t' TMS9918, so small objects are drawn small INSIDE a 16x16 box rather than
\t' being small sprites.
\t'
\t' EVERY 8-PX OBJECT SITS IN ROWS 8-15 OF ITS BOX, ducked Kelly included, so
\t' one rule places them all: bottom edge = y + 16, and a thing resting on the
\t' floor is at y = FLOORY - 16.
\t'
\t' Sprite bytes are QUADRANT-ORDERED: 16 rows of the left half, then 16 of
\t' the right. Every block is an EVEN number of bytes -- an odd DATA BYTE run
\t' silently misaligns every word table after it (CLAUDE.md 3A).
""")

        total = 0
        pat = 0
        for label, arts, comment in SPRITES:
            data = []
            for _name, a in arts:
                data += sprite_bytes(a)
            emit(fh, label, data, comment)
            total += len(data)
            pat += 4 * len(arts)

        # ------------------------------------------------------------- chars
        fh.write("\n\t' ------------------------------------------------ store characters\n")
        fh.write("\t' Codes 96-115. Loaded as ONE contiguous run, so the order here is\n")
        fh.write("\t' the order of the codes -- a gap would shift every char after it.\n")
        codes = [c for _, c, _, _, _ in CHARS]
        if codes != list(range(96, 96 + len(CHARS))):
            raise SystemExit("store chars must be contiguous from 96: %r" % codes)

        pdata = []
        cdata = []
        for name, code, art, fg, bg in CHARS:
            pdata += char_bytes(art)
            cdata += colour_block(name, fg, bg)
        emit(fh, "store_pat", pdata, "%d chars, 8 bytes each" % len(CHARS))
        emit(fh, "store_col", cdata, "EIGHT colour bytes per char, not one")

        # Four phases x four characters x 8 bytes = 128 bytes, and it animates
        # every escalator on the screen at once. Steps travel UP the flight,
        # which is the direction the thing actually carries people.
        art = {n: a for n, _c, a, _f, _b in CHARS}
        # Both directions, in code order, so one DEFINE CHAR covers the lot.
        # The shift runs NEGATIVE so the steps climb: a west flight carries you
        # up to the left, and mirroring turns that into up-to-the-right for an
        # east one. Four phases of two pixels covers the 8 px period.
        for p in range(PHASES):
            for tag, sel, base, n in (
                    ("w", ESC_ANIM[:ESC_ANIM_W], ESC_FIRST, ESC_ANIM_W),
                    ("e", ESC_ANIM[ESC_ANIM_W:],
                     ESC_FIRST + ESC_ANIM_W, ESC_ANIM_E)):
                blk = []
                for _n, i, phs, _mv, _bg in sel:
                    blk += phs[p][i]
                emit(fh, "esc_ph%s%d" % (tag, p), blk,
                     "chars %d-%d, phase %d -- DEFINE CHAR %d,%d,esc_ph%s%d"
                     % (base, base + n - 1, p, base, n, tag, p))
                total += len(blk)
        total += len(pdata) + len(cdata)

        # ---------------------------------------------------- scanner canvas
        fh.write("\n\t' -------------------------------------------------- scanner canvas\n")
        fh.write("\t' Chars %d-%d: 16 cols x 3 rows over screen rows 21-23. Blank to start;\n"
                 "\t' dots are plotted by VPOKEing the PATTERN table (rows 21-23 sit in the\n"
                 "\t' third screen third, so every scanner pattern is at base 4096).\n"
                 % (SCAN_FIRST, SCAN_FIRST + SCAN_N - 1))
        fh.write("\n\t' --------------------------------------------------- font colours\n")
        fh.write("\t' Chars 32-90, EIGHT bytes each. Without this the font keeps whatever\n"
                 "\t' CVBasic left in the colour table, which on a green store made the HUD\n"
                 "\t' unreadable.\n")


        # THE SCANNER IS COLOURED BY PIXEL ROW, WHICH IS THE ONLY REASON IT CAN
        # SHOW FOUR DIFFERENT THINGS AT ONCE. It was white-on-black throughout,
        # so the floor lines, the escalators, the elevator and the two actors
        # were all the same white -- the instrument you navigate by when Harry
        # is off-screen, drawn in one colour, with the player indistinguishable
        # from the furniture.
        #
        # This mode colours each 8x1 scan line separately, and DESIGN.md 6
        # already assigns every pixel row of a level band a fixed job. So the
        # role of a row is known at BUILD time and each one gets its own
        # colour, with no cost at all at run time:
        #
        #   band row 0    escalator head, elevator car   GREY
        #   band row 1    Kelly -- and the escalator FOOT, which the manual
        #                 draws black anyway, so the slash spans both rows
        #   band row 2    Harry                          WHITE
        #   band row 3    the floor line                 YELLOW
        #
        # FOUR PIXELS A LEVEL, AND FOUR IS THE FLOOR. The Kop, the crook, the
        # furniture and the floor lines are four different colours and a
        # colour costs a whole pixel row in this mode, so none of them can
        # share one. It was six, with the escalator taking two rows and one
        # row left clear, and at six the instrument filled all 24 rows of its
        # canvas edge to edge -- touching the shop floor above and the bottom
        # of the screen below. Sixteen pixel rows of content leaves EIGHT
        # empty, and they are split evenly: MARGIN rows above and below.
        #
        # The canvas is 3 char rows of 16, so char ci sits in row ci//16 and
        # its scan line `line` is global pixel row ci//16*8 + line.
        # ONLY THREE DISTINCT BLOCKS, one per canvas character row, each of
        # which the game repeats across its sixteen columns. Emitting all 48
        # spent 384 bytes to say the same thing three times over. The blocks
        # are no longer identical -- the first and last carry the margins --
        # which is why there are three of them rather than one.
        # THE MARGIN IS GREY, NOT GREEN, and that is the whole point of it.
        # A margin inked the same as the scanner's own dark-green ground is
        # padding INSIDE the box: the box still runs from the shop floor to
        # the bottom of the screen and still touches both. And DGREEN is
        # within a few counts of the store's MGREEN on this palette, so the
        # box does not even read as a separate thing -- it reads as more
        # store. Grey is what the 2600 has: measured off the reference video,
        # its scanner is a green box inset in a GREY band the width of the
        # screen, with a few pixels of grey above and below it. (This was
        # briefly black, which reads fine but is not the original.)
        scol = []
        for crow in range(3):
            for line in range(8):
                row = crow * 8 + line
                if row < SCAN_TOP or row >= SCAN_TOP + 16:
                    fg = bg = GRAY
                else:
                    fg = (GRAY, BLACK, WHITE, LYELL)[(row - SCAN_TOP) % 4]
                    bg = DGREEN
                scol.append((fg << 4) | bg)
        emit(fh, "scan_col3", scol,
             "one 8-byte block per canvas row: %d px of GREY margin, then "
             "furniture grey / Kelly black / Harry white / floor line yellow "
             "per 4 px level, on dark green" % SCAN_TOP)
        total += 24

        fh.write("\n\t' code map, for the source to reference:\n")
        for name, code, art, fg, bg in CHARS:
            fh.write("\t'   %-3d %s\n" % (code, name))

    print("wrote %s -- %d sprite patterns, %d chars, %d bytes"
          % (os.path.normpath(out), pat // 4, len(CHARS), total))


if __name__ == "__main__":
    main()
