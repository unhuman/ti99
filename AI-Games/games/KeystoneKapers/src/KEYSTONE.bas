	' ==========================================================================
	' KEYSTONE KAPERS -- CVBasic, dual target TI-99/4A + ColecoVision.
	'
	' Garry Kitchen's 1983 Activision game. See DESIGN.md; 0 records the
	' research and the four places the sources disagree.
	'
	' Fifty seconds to run Harry Hooligan down inside a department store eight
	' screens wide and four levels tall, before he reaches the roof.
	'
	' THE THREE DECISIONS THIS FILE IS BUILT ON, all from DESIGN.md:
	'
	'   * THE VIEW FLIPS, IT DOES NOT SCROLL. Eight discrete screens; crossing
	'     an edge blits the next one. The per-frame budget never pays for the
	'     store at all -- RallyX repaints 576 chars every camera cell and had
	'     to have all its movement rewritten to survive that.
	'   * A SCREEN IS EXACTLY 256 PX, so an actor's x within its screen is one
	'     unsigned byte. No 16-bit world coordinate exists in this program.
	'   * ZERO PER-FRAME VDP READS. An actor's floor is an index into flry(),
	'     never a question asked of the screen, so the Ms. Pac-Man trap
	'     (actors x per-actor search) is absent by construction.
	'
	' The rules that shaped the code, all from CLAUDE.md 3A, because every one
	' of them fails SILENTLY:
	'
	'   * A plain variable is 8-BIT and a CONST over 255 TRUNCATES. Every
	'     name-table offset past row 7 is a #var or a bare literal.
	'   * Every #var comparison is UNSIGNED.
	'   * `<cmp> AND <cmp>` is miscompiled by the 9900 backend. Nested IFs.
	'   * A sprite at y=208 TERMINATES the sprite list. Hidden sprites go 209.
	'   * A GOSUB left by GOTO never pops. Death, catch and escape are STATES
	'     set in a routine and acted on at the top of the main loop.
	'   * MPY clobbers r0. Nothing here multiplies into an index -- the tables
	'     tsrc()/bdst()/lv8() exist precisely so that no multiply is needed on
	'     a path that reads the result back.
	' ==========================================================================

	' ---------------------------------------------------------------- BANKING
	' THE ART AND THE STORE MAP LIVE IN ROM BANK 1 ON THE TI. The fixed area
	' is 24,336 bytes -- three 8,112-byte loader pages -- and unbanked this
	' program filled 24,304 of them, so there was no room left for anything at
	' all. `linkticart` does not warn when you exceed it; it silently discards
	' the top of the image, and what goes missing is whatever sits nearest the
	' end, usually a DATA block rather than code. Nothing errors.
	'
	' WHAT IS SAFE TO BANK. Everything moved here is read at SETUP (the
	' DEFINE CHAR / DEFINE SPRITE calls) or on a screen crossing (the template
	' blit and the escalator's phase tables) -- and, because there is exactly
	' ONE data bank and it is selected ONCE at startup and never switched, it
	' stays mapped for the life of the program. The rule in CLAUDE.md 3A is
	' about SWITCHING inside a frame or under the vblank ISR; with a single
	' permanently-selected bank there is no switch to miss. A missed
	' BANK SELECT would return bytes from the wrong page with no error at
	' build or run time, which is why there is only one and it is set before
	' anything reads from it.
	'
	' BANK ROM 128 sizes ColecoVision's Megacart mapper, NOT the TI cart --
	' that comes from how many bank files the assembler emits -- and it is
	' one of only four values the compiler accepts (128/256/512/1024).
	' The whole thing is gated on TI994A: the Coleco build is Z80 and roughly
	' half the size, so it neither needs banking nor wants to become a
	' Megacart image.
	#if TI994A
	BANK ROM 128
	#endif
	CONST SPRHID = 209		' NOT 208 -- 208 terminates the sprite list

	' ------------------------------------------------------------- geometry
	' A band is 5 rows: 4 rows of air (32 px) over one floor slab. Standing
	' Kelly is 16 px, so headroom is 16 px and the jump apex is 14 -- two
	' short of the ceiling, because an arc that bonks is silently truncated.
	' 4 px/frame = 240 px/s. At 2 it was not merely sluggish, it was
	' ARITHMETICALLY TOO SLOW: the climb is three traverses = 6,144 px, which
	' at 2 px/frame is 51 seconds of pure running against a 50-second clock,
	' before a single obstacle, escalator ride or catch. At 3 it is 34 s --
	' and 34 s was still wrong, for a reason a per-actor speed check cannot
	' see: HARRY'S CLIMB IS ALSO 34 s (DESIGN.md 4a). Kelly being 1.5x faster
	' bought nothing, because Harry's route is two thirds the length of
	' Kelly's -- he spawns beside floor 2's escalator and effectively skips a
	' traverse. A chase resolves on PATH / SPEED, not on speed, and the two
	' quotients were equal, so pursuit on foot could never close. At 4 the
	' climb is 25 s against Harry's 45, and the elevator buys back more.
	CONST WALKSP = 4		' px per PASS -- the old unit, kept only for
					' the checkers' arithmetic and the comments
					' that quote it. Nothing moves by it now.
	' SIXTY-FOURTHS OF A PIXEL PER FRAME, which is what he actually walks by.
	'
	' HIS OLD BEST-CASE SPEED, MADE CONSTANT -- not his old average. WALKSP was
	' 4 px per loop PASS, so what he actually did depended on the screen: 104 px/s
	' on a light one at 26 passes/s, 80 px/s on the lift and escalator screens at
	' 20. Matching the MEASURED AVERAGE of 23.8 passes/s gave 95.6 px/s (102/64),
	' which is the same average and an 8% loss on exactly the screens a chase
	' spends most of its time crossing -- the crook was already per-frame and did
	' not change, so the ratio that decides the chase quietly dropped. Played, it
	' read as only just catching him on the last screen.
	'
	' 111/64 is 104.1 px/s: his best case, everywhere. He is now at least as fast
	' as he ever was on any screen rather than faster on some and slower on
	' others, and the chase margin goes from 10.6 s to 17.3 s.
	CONST KWALK64 = 111
	' The bounce phase, in sixty-fourths of a phase per frame. 32 phases at
	' 25/64 per frame is 1.37 s an arc, against the 1.35 s one phase per pass
	' gives at 23.8 passes a second.
	CONST BOUNCE64 = 25
	CONST XWALL = 232		' furthest left edge at the store's east wall
	CONST XWALW = 8			' nearest left edge at the west wall
	CONST STANDH = 24		' Kelly standing -- TWO SPRITES tall
	' KELLY DUCKED. It was 8 px, which is not a crouch -- it is a squash, with
	' no room to draw a figure bending in a DIRECTION. 11 px is, and the
	' biplane is raised to match (obh below, and the hitbox in coll_obst):
	' with the plane at 16..22 an 11 px crouch passes five pixels under it and
	' a 24 px standing Kop does not. The apex is 14, so a jump still cannot
	' clear it either -- the plane stays the one obstacle that must be ducked.
	'
	' AND 11 IS THE CEILING, not a preference. Duckable means the obstacle
	' clears the crouch, jumpable means it clears under the apex; raising the
	' crouch raises the duckable floor, so past 11 a band of beach-ball
	' heights is neither. A sweep of every crouch height against every ball
	' hitbox puts the limit at 11, and shrinking the ball does not move it --
	' the apex is what binds. assets/checkball.py fails the build on it.
	CONST DUCKH = 11		' Kelly ducked -- bent over, not squashed
	CONST CATCHR = 12		' catch / hit radius, centre to centre

	' Kelly states
	CONST ST_RUN = 0
	CONST ST_JUMP = 1
	CONST ST_DUCK = 2
	CONST ST_ESC = 3		' riding an escalator -- no input, invincible
	CONST ST_ELEV = 4		' inside the car     -- no input, invincible

	' obstacle kinds, matching assets/genstore.py
	CONST OB_CART = 1
	CONST OB_BALL = 2
	CONST OB_RADIO = 3
	CONST OB_PLANE = 4

	' sprite patterns (DEFINE SPRITE index n -> pattern n*4)
	' THE VDP CANNOT MIRROR A SPRITE -- there is no flip bit -- so every actor
	' that runs both ways carries a second set of frames. assets/genart.py
	' generates the left ones from the right ones so the two directions are
	' guaranteed identical.
	' KELLY AND HARRY ARE 24 PX -- a 16 px top sprite with the top half of a
	' second sprite below it. A band gives 32 px of air plus the 7 px of the
	' ceiling row under its 1 px slab line = 39 px, and 24 + the 14 px jump is
	' 38. The apex CANNOT be reduced to buy room: at 10 px the ball's jump and
	' duck windows stop overlapping and a dead band opens (DESIGN.md 5a).
	'
	' The two sprites never share a scanline, so a band still costs Kelly 1 +
	' Harry 1 + two obstacles = four per line.
	' Pattern numbers are genart.py's SPRITES order x 4. Move one there and
	' this table must move with it -- nothing checks the correspondence.
	' SPRITE PATTERNS, laid out by genart.py so the selection code is three
	' statements rather than two mirrored branches. Everything that FACES comes
	' in a RIGHT block and then a LEFT block of the same shape, so changing
	' facing is one fixed offset; the LEGS do not face and are shared.
	CONST P_KHAT = 0		' Kelly RIGHT: hat, black
	CONST P_KFACE = 4		'              face, skin
	CONST P_KBODY = 8		'              tunic, arms down
	CONST P_KBODYB = 12		'              tunic, leading arm up
	CONST P_KDHAT = 16		'              ducked: the brim, black
	CONST P_KDFACE = 20		'              ducked: face
	CONST P_KDBODY = 24		'              ducked: the crouch, blue
	CONST P_KFACING = 28		' add this for Kelly's LEFT set
	' THE RUN IS FOUR FRAMES AND BOTH FACINGS SHARE THEM. In a side view "left
	' foot forward" is the horizontal mirror of "right foot forward", so the
	' cycle is A, B, mirror(A), mirror(B) and which way he is going lives in
	' the hat, face and tunic. Consecutive, so a frame is P_KLEG1 + 4*phase.
	CONST P_KLEG1 = 56
	' FOUR TORSOS AND FOUR STRIPE LAYERS, consecutive: a beat is
	' P_HBODY + 4*phase, the same arithmetic as P_KLEG1 and P_HLEG1. They come
	' from the run-cycle sheet (assets/sheet2harry.py -> harryrun1..4.txt), so
	' the arms and shoulders are DRAWN for each beat rather than being one
	' torso with its arms flipped.
	CONST P_HBODY = 72		' Harry RIGHT: cap + body, white, 4 beats
	CONST P_HSTRIPE = 88		'              the stripes, cap to hem, 4 beats
	CONST P_HFACE = 104		'              face, skin
	' 36, NOT 20: the right-hand set grows an entry every time Harry gains a
	' frame, and the left set starts after ALL of it. It went 12 -> 16 when he
	' got a second torso frame, 16 -> 20 when the stripes stopped being one
	' drawing shared by both frames, and 20 -> 36 when the run went to four
	' drawn beats (4 bodies + 4 stripes + 1 face = 9 patterns of 4).
	' renumber.py rewrites every other P_ constant from genart's table but
	' deliberately leaves this one alone -- it is an OFFSET between two
	' groups, not a pattern number, and there is nothing in the table to
	' look it up from. checkchars.py is what holds it honest.
	CONST P_HFACING = 36		' add this for Harry's LEFT set
	CONST P_HLEG1 = 144
	CONST P_HLEGS1 = 160		' the same four poses again, in BLACK: the
					' stripes carrying on down the legs, and
					' the shoes
	' 32: four white poses plus four black ones, so the LEFT set starts after
	' both. The legs used to share one set between the facings -- fine while
	' the stride stayed inside the body's width, and plainly wrong once the
	' sheet's poses reached the full 16 columns: he ran left with his back
	' foot leading. Applied to hq and hqs together, in the same IF that turns
	' the torso round, so a facing can never be half-applied.
	CONST P_HLEGFACING = 32
	CONST P_RADCAR = 220		' the radar's lift car
	CONST C_RCAR = 14		' grey, like the furniture it replaced
	CONST P_RADDOT = 224		' the radar marker, both actors
	CONST C_RKOP = 1		' the Kop, black on the scanner
	CONST C_RCROOK = 15		' the crook, white
	CONST P_CART = 208
	CONST P_BALL = 212
	CONST P_PLANE = 228
	CONST P_PLANEL = 232
	' THE PROPELLER IS ITS OWN SPRITE so it can be its own colour. Two
	' phases, each facing: A is the near-solid disc, B the broken blades.
	CONST P_PROPA = 236
	CONST P_PROPAL = 240
	CONST P_PROPB = 244
	CONST P_PROPBL = 248

	CONST C_KELLY = 4		' the Kop's blue trousers
	' THE HAT IS BLACK AGAIN, as the reference has it. It went blue because
	' it shared a sprite with the tunic and the elevator shaft was black, so
	' the Kop vanished in the one place the game most wants you to go. Both
	' halves of that are now fixed: the hat has its own sprite, and the shaft
	' is GREY -- the reference's dark green is indistinguishable from the
	' store's own ground on this VDP, so it needed replacing anyway. That is
	' MORE true now, not less: the store's ground has since moved to dark
	' green itself (genart's STORE_BG), so a dark-green shaft would now be
	' the identical byte.
	CONST C_KHAT = 1
	CONST C_SKIN = 11		' the one skin band, both actors
	CONST C_HSTRIPE = 1		' Harry's stripes -- the sprite that is
					' allowed to drop when he is level with Kelly
	CONST C_HARRY = 15		' white -- and the white dot on the scanner
	' WHITE. The reference's carts are white wire baskets, and grey put them
	' a shade off the pillars and the roof deck they cross.
	CONST C_CART = 15
	' RED, measured off gameplay video (DESIGN.md 0b) -- it was light yellow,
	' which came from a static screenshot. Red also happens to be the most
	' legible choice on the green store, and this is the obstacle whose right
	' answer changes in mid-air, so it is the one the player most needs to see.
	CONST C_BALL = 8
	' THE ONE THING THAT KILLS GETS ITS OWN COLOUR. Everything else in the
	' store costs nine seconds; the biplane costs a Kop, and a player has no
	' way to learn that except by losing one. Red says it before they do.
	' YELLOW BODY OVER A BLACK DETAIL LAYER -- cockpit and spinning propeller.
	' One TMS9918 sprite has one colour, so this takes two, and the second is
	' affordable because of PRIORITY: it goes in a HIGH slot (16-23), and the
	' VDP drops the highest-numbered sprites on an overfull scan line. So the
	' thing that vanishes when Kelly, a plane and a high ball share a line is
	' the detail -- cosmetic -- and never the plane the player must dodge.
	'
	' The body is HOLED where the cockpit goes. A lower slot number wins, so
	' the black layer can only show through where the yellow has nothing.
	CONST C_PLANE = 11		' yellow body
	CONST C_PROP = 1		' black cockpit and propeller

	' store chars
	' THE FLIGHT'S COLOUR, as (fg << 4) | DGREEN. The colour table only knows
	' ROWS, and a flight has to be black on a row whose base is grey, so
	' scan_escc writes this into the flight's own character. It is the only
	' run-time colour left -- the two actors are sprites and carry theirs.
	CONST SC_KOP = 28		' black on dark green
	CONST CH_SHELFT = 99		' a counter's top half -- what wipe_shelf walks
	CONST CH_COUNTR = 107		' a pillar/counter column: the ONLY thing a
					' fixture may erase (renumber.py fills this)
	CONST CH_SLAB = 96
	' THE VICTROLA IS FOUR CELLS. Its top-right cell has two versions and the
	' sound marks live there, so the pulse is one VPOKE of a different
	' CHARACTER CODE -- not a DEFINE CHAR, which in bitmap mode is LDIRVM3's
	' triple copy (CLAUDE.md 3A) and would cost three times its size every
	' time it blinked.
	CONST CH_RADTL0 = 101
	CONST CH_RADTL1 = 103
	CONST CH_RADTR0 = 102
	CONST CH_RADTR1 = 104
	CONST CH_RADBL = 105
	CONST CH_RADBR = 106
	CONST CH_ROOFS = 165		' the roof surface
	CONST CH_SLABE = 97		' the bar with BRICK carried up through it
	CONST CH_ROOFSE = 98		' and the roof deck likewise
	CONST CH_ROOFSP = 166		' the roof with a beam under it
	CONST CH_SLABP = 180		' the same bar with a beam under it
	CONST CH_ECAR = 109
	CONST CH_EDOOR = 108
	CONST CH_WALL = 154
	CONST CH_KOPIC = 155
	CONST CH_ECARS = 173		' the car's row-3 sill
	' THE OPEN CAR IS NOW THREE CHARACTERS, NOT NINE. Its end columns used to
	' carry four pixels of jamb apiece -- a 32px box with a 24px opening --
	' and each of those needed a header twin and a sill twin. The jambs moved
	' out into the wall column either side (EJAMBL/EJAMBR, drawn by t_elev and
	' never touched at run time), so every doorway column is now plain car:
	' the opening is the full 32px and six constants went with the six
	' characters.
	CONST CH_EDOORS = 174		' and the SHUT door's own sill: the threshold
					' belongs to the landing, not to the car
	' HOW FAR THE RIDER RISES, WHICH IS NOT THE SAME NUMBER, and conflating
	' the two is what left Kelly a pixel short of being in the car.
	'
	' ELSTEP is a fact about the ART: the lip is two character-graphics pixels
	' proud of the shop floor, exact and unambiguous. ELRIDE is where the
	' SPRITE has to sit to look like it is standing on that lip -- and a
	' sprite is not placed the way a character is. The VDP puts a sprite's
	' top line at y + 1, so a rider lifted by exactly the drawn step height
	' renders one pixel into it rather than on it.
	'
	' Keeping them as one constant made that impossible to express: the
	' comment even claimed the shared value meant "the drawing and the
	' standing height can only ever agree", when agreeing is precisely what
	' they must not do.
	CONST ELRIDE = 3		' ELSTEP + the VDP's one-line sprite bias
	CONST CH_ECART = 175		' half doorway below (renumber.py fills these)
	CONST CH_SCANBK = 179		' blank black, the strip either side of the radar
	CONST CH_BAGTL = 157		' the prizes are 2x2 now
	CONST CH_BAGTR = 158
	CONST CH_BAGBL = 159
	CONST CH_BAGBR = 160
	CONST CH_CASETL = 161
	CONST CH_CASETR = 162
	CONST CH_CASEBL = 163
	CONST CH_CASEBR = 164
	' NAMED, because this was the literal 113 and the escalator rework
	' renumbered the character table underneath it. 113 became EXITC, so
	' the second collectible quietly drew an EXIT DOOR in the aisle -- a
	' plausible-looking box, no error, and nothing to connect it to a
	' change made somewhere else entirely.

	' the elevator doorway, in pixels and columns
	CONST ELXL = 112
	CONST ELXR = 143
	CONST ELCOL = 14		' first of 4 doorway columns
	CONST ELWAIT = 100		' frames stopped at a floor
	' TWO SECONDS BETWEEN FLOORS. `elt` counts down by `fdv`, the FRAME
	' delta, so this is real frames and not loop passes -- 120 of them is
	' 2.0 s on both 60 Hz targets, and it stays 2.0 s when the loop gets
	' busy. It was 45 (0.75 s), which is faster than a lift has any business
	' being and gave the doors barely time to read as opening.
	CONST ELMOVE = 120		' frames in transit between floors
	' HOW FAR THE SECOND HAZARD ON A FLOOR TRAILS THE FIRST, in pixels.
	'
	' THERE ARE ONLY TWO SAFE ANSWERS AND THE SCREEN ONLY FITS ONE OF THEM.
	' Kelly closes on an oncoming ball at WALKSP + 2 = 6 px a pass, so:
	'
	'   <= 54 px   ONE JUMP CLEARS BOTH -- the arc holds its 14 px apex for
	'              nine passes, which is 54 px of closing distance
	'   >= 168 px  he can LAND BETWEEN them -- the arc is airborne for 28
	'              passes, which is 168 px
	'
	' Anything in between is the dangerous middle: too far to clear together,
	' too close to land between. The gap shipped at 46 px west of the lift and
	' 70 px east of it -- 46 is inside the first window and 70 is squarely in
	' that middle, which is the asymmetry that got reported.
	'
	' The second window does not fit. `stag` is distance from the FAR edge, so
	' a bigger gap moves the second hazard TOWARD the player: at 168 px it
	' starts within 72 px of the wall he walks in through, and at 176 it lands
	' essentially on top of him with no time to read it. That was tried and it
	' is worse than the bug it replaced.
	'
	' So 48 -- inside the one-jump window with margin, uniform on every screen,
	' and it leaves the nearer hazard at least 192 px away at entry. The pair
	' is one obstacle taken with one well-timed jump, which is also what the
	' original's paired hazards read like. assets/checkspace.py checks all of
	' it and checkspace_test.py proves it rejects 70 and 176 alike.
	CONST HAZGAP = 20
	CONST ELDOOR = 15		' frames the doors spend part-open
	CONST ELOPEN = 85		' = ELWAIT - ELDOOR, as a literal: a CONST
					' built from other CONSTs is exactly the
					' folded-constant trap in CLAUDE.md 3A

	' escalator boarding zones, in CENTRE-x pixels
	' ESCALATOR BOARDING ZONES, IN PIXELS, AND THEY TRACK THE ART.
	' The flight is drawn as four rows of two characters stepping two columns
	' per row: west runs cols 1-2 (top) down to 7-8 (foot), east runs 29-30
	' (top) down to 23-24 (foot). These zones ARE those columns x8. When the
	' escalator art changed from a filled triangle to a stepped flight the
	' foot moved, and a boarding zone left where it was would put the player
	' on a staircase that is not under them -- no error, just a floor that
	' teleports you when you walk over an empty patch of it.
	' THESE ARE THE DRAWN STEPS, in screen pixels. The flight is fifteen
	' characters wide: its foot tread sits at x 95-103 (west) and 152-160
	' (east), its head tread at 23-31 and 224-232. An actor rides between
	' those, so the numbers here are the ART's, and moving the art without
	' moving them puts the rider beside the escalator rather than on it.
	' THE RIDER STANDS ON A STEP, and everything about the ride follows from
	' WHICH ONE. The staircase is a straight line -- a step 4 px higher is 8
	' px further along it -- so one number, the step's height above the floor
	' being left, fixes both the rider's x and the rest of the ride:
	'
	'     west  klx = 99 - 2*height        east  klx = 140 + 2*height
	'
	' The bottom step is 4 px up, so a rider walking on boards at klx = 91
	' (west) or 148 (east); the head step is 40 up, so the ride ends at 19 or
	' 220. Those are the ART's numbers -- the foot tread is drawn at x 95-103
	' west and 152-160 east, the head tread at 23-31 and 224-232 -- so moving
	' the art without moving these puts the rider beside the staircase.
	'
	' THE PHASE MATTERS. The steps climb 1 px a frame and the animation runs
	' four 1 px phases, so the bottom step is 4 + escp px up, not 4. Boarding
	' without that term leaves the feet up to 3 px out of register with the
	' tread and the whole ride drifts, which is exactly what "he floats
	' beside the steps" looked like.
	CONST ESCFX = 91		' west foot: rider's x when boarding
	CONST ESCFXE = 148		' east foot
	CONST ESCHX = 19		' west head: rider's x on arrival
	CONST ESCHXE = 220		' east head
	CONST ESCRISE = 40		' floor to floor, and the ride's length

	' TIMER UNITS PER KROOK, AND A UNIT IS NOT A SECOND. Measured off the
	' reference video (DESIGN.md 0m): the original counts 50 down to 0 and a
	' unit lasts 1.99 s, so a round is about 100 seconds. TICKFR below is
	' what makes it so here.
	CONST TIMEL = 50		' timer units per Krook
	' FRAMES PER TIMER UNIT. 120, not 60, and this is not cosmetic -- it is
	' what makes a round finishable. Everything that MOVES in this game is
	' paced per loop PASS, and the loop runs about 25 passes a second, so
	' Kelly's 4 px a pass is ~100 px/s (the reference's Kelly is 102, so the
	' speeds match). The timer, though, is paced by the frame DELTA -- real
	' wall-clock time. At 60 frames a unit the round was 50 real seconds
	' while Kelly's route to the roof takes about 72, so the clock ran out
	' before either of them could get there and every round ended on a
	' timeout. checkchase.py hid it by assuming 60 passes a second; it now
	' models the real rate.
	CONST TICKFR = 120
	' NINE TIMER UNITS -- not ten, and not nine seconds. Every source says a
	' cart, ball or radio costs "9 seconds", and what they mean is the number
	' on the HUD, because that is what the manual calls seconds. So the
	' DISPLAYED count drops by 9. A unit is about two real seconds
	' (DESIGN.md 0m), which makes one careless cart cost roughly eighteen --
	' close to a fifth of the round, and the reason the refractory latch
	' below matters so much.
	CONST HITPEN = 9		' timer units a cart / ball / radio costs
	CONST HITREF = 45		' frames before the SAME obstacle can charge
					' again. See coll_obst -- clearing the latch
					' on the first non-overlapping frame is not
					' enough, because a bouncing ball leaves
					' contact between bounces.

	' ---------------------------------------------------------------- tables
	DIM flry(4)			' floor surface y, by level
	DIM #bdst(4)			' band name-table offset, by level
	DIM #tsrc(15)			' template source offset, by template id
	DIM lv8(4)			' lv*8, so no multiply lands on an index
	DIM jarc(32)			' the jump arc: 30 frames, apex 14
	DIM msk(8)

	' EIGHT obstacle slots -- TWO per band, and that number is forced.
	'
	' The VDP shows four sprites per scanline and DROPS the rest by slot
	' order; it does not flicker them, they simply are not there. Three per
	' band was sized against Kelly alone (1 + 3 = 4) and forgot that HARRY
	' can be on that band too -- and when he is, the fifth sprite on his
	' scanline is the highest-numbered obstacle, which vanishes while still
	' being solid. An invisible thing that costs nine seconds is the worst
	' failure in the game and it only happens when the crook is next to you,
	' which is exactly when you are not looking at the floor.
	'
	' Kelly (slot 0) + Harry (slot 1) + two obstacles = four. Provably never
	' dropped, on any band, in any situation.
	DIM obk(8)			' kind, 0 = empty
	DIM obx(8)			' x within the screen
	DIM obd(8)			' 0 = moving left, 1 = right
	DIM obh(8)			' art-bottom height above the slab
	DIM obc(8)			' cell column, radios only -- they are chars
	DIM obp(8)			' bounce phase, balls only
	DIM obht(8)			' hit refractory, per obstacle -- see coll_obst

	DIM cok(4)			' this screen's collectible, per band
	DIM coc(4)			' its column
	DIM takn(4)			' 32 bits: which bands have been cleaned out

	' ---------------------------------------------------------------- state
	' Kelly
	' klv 0..3 (0 = floor 1, 3 = roof), klsc 0..7, klx 0..255
	' Harry the same. NOTHING in this program is a world coordinate.

	' THE TITLE IS DRAWN AS SOON AS IT CAN BE, NOT WHEN EVERYTHING IS READY.
	'
	' Only the font is needed to put text on screen. The store characters, the
	' store colours, the escalator deck, the radar canvas and eight sprite sets
	' are needed by new_game -- which does not run until the player presses
	' start -- so they have no business standing between the loader and the
	' first thing the player sees. Moving them behind the title does not make
	' the machine do less work; it makes all of it happen while there is
	' something to read, which is the difference between a title that appears
	' and a title that fills in.
	GOSUB setup_font
	GOSUB title_draw
	GOSUB setup_rest
	GOSUB init_tables
	' ONCE PER POWER-ON, NOT ONCE PER GAME. It samples a physical latch, so the
	' answer cannot change while the machine is on -- and re-running it was
	' actively wrong, not merely slow: it used to sit inside the title routine,
	' which `GOTO boot` re-enters after every game over, so a player still
	' holding a direction when the title came back had that direction read as a
	' stuck line and disabled for the whole next game.
	GOSUB alock_cal
	GOTO first_title

boot:
	' Coming back from a game over the store is still on screen, so the title
	' has to be redrawn. First time through it is already up -- drawing it again
	' would be harmless but would undo the point of the order above.
	GOSUB title_draw
first_title:
	GOSUB title_input
	' LET GO OF FIRE BEFORE PLAY BEGINS.
	'
	' title_input returns ON the press, so the button is still down when the
	' round starts and read_input sees it on the very first pass. jrel is
	' supposed to absorb that -- start_krook clears it, so the latch demands a
	' release before the first jump -- and in play it did not, reported twice.
	' Rather than keep reasoning about the order of two latches, this waits
	' for the thing itself: the key that said "start" is not in the buffer any
	' more when the loop begins.
	'
	' CAPPED AT A SECOND, AND THAT IS THE WHOLE POINT OF THE COUNTER. A stuck
	' or shorted fire line would otherwise hang the game on a black screen for
	' ever, which is exactly the mistake the ALPHA LOCK check made in its first
	' version -- refusing to start until a condition cleared that never would.
	' A survivable input quirk must not become a dead game, so after sixty
	' frames it gives up and plays anyway.
	brw = 0
btn_rel:
	WAIT
	brw = brw + 1
	IF brw > 60 THEN GOTO btn_go
	IF cont1.button THEN GOTO btn_rel
btn_go:
	GOSUB new_game
	GOTO main

	' ======================================================================
	' MAIN LOOP -- one WAIT per frame, O(1) per actor, no VDP reads.
	' ======================================================================
main:
	WAIT
	#fd = FRAME - #lf
	#lf = FRAME
	IF #fd > 6 THEN #fd = 6		' a long stall must not teleport anyone
	fdv = #fd
	IF fdv = 0 THEN fdv = 1
	fphs = fphs + 1			' the flash's OWN phase. A timer that
					' decrements by a variable delta has no
					' usable parity.

	GOSUB read_input
	GOSUB radio_tick
	GOSUB move_kelly
	GOSUB upd_elev
	GOSUB upd_obst
	GOSUB move_harry
	GOSUB coll_obst
	GOSUB coll_prize
	GOSUB coll_harry
	GOSUB draw_actors
	GOSUB tick_timer
	GOSUB scan_tick
	GOSUB esc_tick
	GOSUB sfx_tick

	' STATES, NOT JUMPS. Every one of these is reached with no outstanding
	' GOSUB frames; leaving a collision routine by GOTO would never pop its
	' return address -- invisible on the TI's 7 KB of stack, fatal on
	' ColecoVision's 1 KB.
	IF caught = 1 THEN GOTO do_catch
	IF escapd = 1 THEN GOTO do_escape
	IF tout = 1 THEN GOTO do_death
	IF dead = 1 THEN GOTO do_death
	GOTO main

	' ======================================================================
	' ONE-TIME SETUP
	' ======================================================================
setup_font:
	' Flicker stays OFF. CVBasic's is all-or-nothing -- it rotates all 32
	' slots, so Kelly would strobe too, and he is the one thing the player
	' must never lose. He is sprite 0 instead: the VDP drops the
	' HIGHEST-numbered sprites on an over-full scanline, so slot 0 is the
	' one slot that can never disappear.
	SPRITE FLICKER OFF

	' BEFORE ANY READ FROM IT, and never switched again. Bank 0 is the only
	' bank a BANK SELECT may be issued from, and this is the last thing that
	' runs before the DEFINEs below start pulling art out of bank 1.
	#if TI994A
	BANK SELECT 1
	#endif

	DEFINE CHAR 32,59,font_bits
	' Without this the font keeps whatever CVBasic left in the colour table --
	' white on transparent -- which over a green store made the HUD unreadable.
	'
	' THIS WAS A VPOKE LOOP AND IT WAS THE SLOWEST THING IN THE BOOT: 1,416
	' writes of one constant, paced by 24 WAITs, which is what made the title
	' fill in visibly instead of appearing. DEFINE COLOR does the same job in a
	' single call with interrupts off, and it writes all three screen thirds
	' itself -- define_color always takes the LDIRVM3 triple-copy path, which is
	' also why esc_deck_col and floor0_colour below CANNOT use it: they patch
	' one third each.
	'
	' The table is 472 identical bytes (genfont.py emits it beside the glyphs).
	' It reads as waste and is not: it lives in the data bank, which had 860
	' bytes spare, while the loop it replaced cost time in the one place the
	' player is made to wait.
	DEFINE COLOR 32,59,font_col
	RETURN

	' EVERYTHING THE TITLE DOES NOT NEED. Runs after the title is on screen.
setup_rest:
	DEFINE CHAR 96,85,store_pat
	DEFINE COLOR 96,85,store_col
	GOSUB esc_deck_col
	GOSUB scan_colour
	GOSUB floor0_colour

	GOTO after_deck

	' THE ROOF CROSSING, COLOURED FOR SCREEN THIRD 0 ONLY.
	'
	' A flight crossing into the roof shows the grey-and-white DECK behind
	' it; one crossing into a shop floor shows the yellow FLOOR BAR. Same
	' pixels, different surface -- and the two surfaces are never in the same
	' third, because a roof crossing is screen row 5 and a shop one is row 10
	' or 15. So both use the same characters, DEFINE COLOR paints them as the
	' floor bar in all three thirds, and this repaints third 0 as the deck.
	'
	' Worth a loop because those characters ANIMATE: two sets meant rewriting
	' nine patterns a pass on the west screen instead of six, and define_char
	' triples every byte (see esc_tick).
esc_deck_col:
	#eda = VARPTR esc_deck(0)
	FOR edi = 0 TO 5
		edc = PEEK(#eda)
		#eda = #eda + 1
		#edb = 8192			' third 0's colour table
		#edb = #edb + edc * 8.
		FOR edj = 0 TO 7
			edv = PEEK(#eda)
			#eda = #eda + 1
			VPOKE #edb,edv
			#edb = #edb + 1
		NEXT edj
	NEXT edi
	RETURN

after_deck:
	DEFINE SPRITE 0,18,spr_kelly	' 0..68  facing bands x2 + 4 run frames
	DEFINE SPRITE 18,34,spr_harry	' 72..100, two torso frames each way
	DEFINE SPRITE 52,1,spr_cart	' pattern 104
	DEFINE SPRITE 53,1,spr_ball	' pattern 108
	DEFINE SPRITE 54,1,spr_radio	' pattern 112
	DEFINE SPRITE 55,1,spr_radcar
	DEFINE SPRITE 56,1,spr_raddot	' the radar marker, both actors
	DEFINE SPRITE 57,6,spr_plane	' body R/L, then prop A and B, R/L
	RETURN

init_tables:
	' Floor surface y, by level. An actor standing here has its FEET at this
	' pixel, and every 16 px sprite sits at y = flry - 16 - height.
	flry(0) = 160			' floor 1, slab on row 20
	flry(1) = 120			' floor 2, row 15
	flry(2) = 80			' floor 3, row 10
	flry(3) = 40			' roof,    row 5

	' Band destination offsets, name-table relative. Three of the four are
	' over 255, so they live in #vars -- as a CONST each would truncate to
	' its low byte and every band would blit over the top one.
	#bdst(0) = 512			' row 16
	#bdst(1) = 352			' row 11
	#bdst(2) = 192			' row 6
	#bdst(3) = 32			' row 1

	' Template source offsets. A LOOKUP, not `tpl * 160`: reading a 16-bit
	' var straight after a multiply returns the product's high word.
	#tsrc(0) = 0
	#tsrc(1) = 160
	#tsrc(2) = 320
	#tsrc(3) = 480
	#tsrc(4) = 640
	#tsrc(5) = 800
	#tsrc(6) = 960
	#tsrc(7) = 1120
	#tsrc(8) = 1280
	#tsrc(9) = 1440
	' Five more since the roof gained a template per screen (DESIGN.md 13a).
	#tsrc(10) = 1600
	#tsrc(11) = 1760
	#tsrc(12) = 1920
	#tsrc(13) = 2080
	#tsrc(14) = 2240

	lv8(0) = 0
	lv8(1) = 8
	lv8(2) = 16
	lv8(3) = 24

	msk(0) = 1
	msk(1) = 2
	msk(2) = 4
	msk(3) = 8
	msk(4) = 16
	msk(5) = 32
	msk(6) = 64
	msk(7) = 128

	' THE JUMP ARC IS A TABLE, not integration. That makes the 14 px apex a
	' property of the data rather than of a fixed-point velocity that has to
	' be tuned, and it keeps every comparison in the jump 8-bit and unsigned.
	' DESIGN.md 5a depends on the apex being exactly 14.
	'
	' THIRTY FRAMES WITH NINE OF THEM AT THE APEX. The first version was 24
	' frames that touched 14 for only four, which made every jump a timing
	' test rather than a decision -- you had to leave the ground on exactly
	' the right frame or clip the thing you were jumping. Widening the
	' plateau rather than raising the apex keeps the ball arithmetic in
	' DESIGN.md 5a intact (the apex is what that depends on) while making the
	' window forgiving: the player still has to CHOOSE to jump, but no longer
	' has to be frame-perfect about it.
	' THE ARC IS A TABLE, not thirty assignments -- each of those compiled to
	' several bytes of code, and the fixed area is the binding budget.
	#jat = VARPTR jarc_tbl(0)
	FOR ji = 0 TO 29
		#jaa = #jat + ji
		jarc(ji) = PEEK(#jaa)
	NEXT ji

	#stix = VARPTR stor_ix(0)
	#stob = VARPTR stor_ob(0)
	#stco = VARPTR stor_co(0)
	#stes = VARPTR stor_esc(0)
	#stpl = VARPTR stor_pil(0)
	#stac = VARPTR stor_arc(0)
	#stcp = VARPTR esc_cap(0)
	RETURN

	' THE FONT'S COLOUR TABLE WAS 472 BYTES OF ONE REPEATED VALUE, which is a
	' fifth of what the fixed area had left. DEFINE COLOR copies such a table
	' out of ROM into all three screen thirds; writing the constant straight
	' into the colour table does the same job for the price of a loop, and
	' the loop runs once, at boot.
	'
	' The colour table is at >2000 and the VDP mirrors it once per screen
	' third, >800 apart. Both numbers were read out of the GENERATED assembly
	' -- define_color's `ai r0,>2000` and LDIRVM3's `ai r0,>0800` -- rather
	' than assumed, because a wrong base here would paint over the pattern
	' table and the failure would look like corrupt artwork.
	'
	' Paced: a few hundred VDP writes in one frame are silently dropped.
	' THE SCANNER'S COLOURS ARE THREE BLOCKS REPEATED SIXTEEN TIMES EACH, so
	' the table shipped 384 bytes to say 24 bytes' worth. Same trick as the
	' font: write the colour table directly. >2000 is the colour table's base
	' and >800 the stride between screen thirds -- the same layout DEFINE COLOR
	' walks for us in setup_font, which this cannot use because it is cheaper to
	' expand 24 bytes here than to ship 384 in the bank.
	' NOTHING IS UNDER THE GROUND FLOOR, SO NOTHING SHOULD BE GREEN THERE.
	' A floor bar is five pixels of yellow over three of the green air
	' belonging to the floor BELOW it (see SLAB), which is right for three of
	' the four bars and wrong for the last one: below floor 0 there is no
	' floor, only the scanner, and the green read as a strip of shop with
	' nothing in it.
	'
	' NO NEW CHARACTER IS NEEDED, BECAUSE THE COLOUR TABLE HAS THREE COPIES
	' -- one per eight screen rows -- and the bands land such that each bar
	' sits in a different third:
	'
	'     band 0 roof   rows  1-5    bar row  5   third 0
	'     band 1        rows  6-10   bar row 10   third 1
	'     band 2        rows 11-15   bar row 15   third 1
	'     band 3 GROUND rows 16-20   bar row 20   third 2
	'
	' so recolouring SLAB in third 2 alone reaches the ground floor's bar and
	' nothing else. The same third also holds the scanner, but the scanner
	' does not use these characters. This is the same mechanism that once hid
	' a bug for months (CLAUDE.md 3A, the blanked-in-one-third note) used
	' deliberately for once.
	'
	' Only the three bottom lines change, and only their BACKGROUND: SLAB has
	' no ink there and SLABE's brick keeps its grey.
floor0_colour:
	' TWO CHARACTERS, THE SAME THREE SCAN LINES, ONE ROUTINE. Both blocks
	' were written out in full and differed only in which character and which
	' colour byte -- eleven statements twice, including the multiply-by-eight
	' done by doubling (`*` compiles to a real TMS9900 MPY, which clobbers r0,
	' CLAUDE.md 3A).
	f0c = CH_SLAB
	f0v = 177			' LYELL on BLACK -- no ink, so the
	GOSUB f0_rows			' background is all that shows
	f0c = CH_SLABE
	f0v = 225			' GRAY brick on BLACK
	GOSUB f0_rows
	RETURN

	' The last three scan lines of character f0c, in the BOTTOM SCREEN THIRD
	' only -- which is why this cannot be a DEFINE COLOR: that always writes
	' all three thirds (define_color takes the LDIRVM3 path unconditionally).
f0_rows:
	#f0a = 12288			' colour table, bottom screen third
	#f0b = f0c
	#f0b = #f0b + #f0b
	#f0b = #f0b + #f0b
	#f0b = #f0b + #f0b		' f0c * 8
	#f0a = #f0a + #f0b
	#f0a = #f0a + 5			' its last three scan lines
	FOR f0i = 0 TO 2
		VPOKE #f0a,f0v
		#f0a = #f0a + 1
	NEXT f0i
	RETURN

scan_colour:
	#scb = VARPTR scan_col3(0)
	FOR sci = 0 TO 2
		#sca = 8192
		IF sci = 1 THEN #sca = 10240
		IF sci = 2 THEN #sca = 12288
		#sca = #sca + 1664		' char 208, the canvas
		FOR scr = 0 TO 2
			FOR scc = 0 TO 15
				#scs = #scb
				scq = scr + scr
				scq = scq + scq
				scq = scq + scq		' scr * 8
				#scs = #scs + scq
				FOR scl = 0 TO 7
					scv = PEEK(#scs)
					VPOKE #sca,scv
					#sca = #sca + 1
					#scs = #scs + 1
				NEXT scl
			NEXT scc
			WAIT
		NEXT scr
	NEXT sci
	RETURN

	' ======================================================================
	' TITLE
	' ======================================================================
	' DRAWING THE TITLE AND WAITING ON IT ARE TWO ROUTINES, because the boot
	' does something between them: the rest of setup runs while this is on
	' screen. They used to be one, which is why the title could not be shown
	' until everything was ready.
title_draw:
	GOSUB hide_all
	CLS
	PRINT AT 68,"KEYSTONE KAPERS"
	PRINT AT 133,"SOUTHWICKS EMPORIUM"
	PRINT AT 197,"HARRY HOOLIGAN IS LOOSE"

	PRINT AT 294,"STICK    RUN"
	PRINT AT 326,"FIRE     JUMP"
	PRINT AT 358,"DOWN     DUCK"
	PRINT AT 390,"UP       ENTER ELEVATOR"

	PRINT AT 486,"JUMP CARTS AND LOW BALLS"
	PRINT AT 518,"DUCK PLANES AND HIGH ONES"

	PRINT AT 678,"2026 UNHUMAN AND CLAUDE"
	' The NOTICE is redrawn on every title visit even though the MEASUREMENT
	' happens once -- it is information about the machine, and the CLS above
	' just wiped it.
	IF vstuck > 0 THEN PRINT AT 578,"ALPHA LOCK DOWN - IGNORED"
	RETURN

	' ------------------------------------------- ALPHA LOCK, CALIBRATED
	' On the TI, ALPHA LOCK shares a line with the joystick's VERTICAL axis.
	' Latched down it reports a direction that is NEVER RELEASED. Every other
	' game in this repo dodges this by not reading up/down at all; this one
	' cannot, because down is the duck and up is the elevator.
	'
	' THE FIRST VERSION OF THIS REFUSED TO START UNTIL THE AXIS CLEARED, AND
	' THAT WAS THE WRONG CALL. Classic99 defaults to invertcaps=1, so the TI
	' sees ALPHA LOCK DOWN when the host's Caps Lock is UP -- the normal
	' state. The game then sat on its title screen for ever waiting for a
	' condition the player had no reason to suspect, which presents as "the
	' title comes up and it will not start". A check that turns a survivable
	' input quirk into a dead game is worse than no check.
	'
	' So: sample the axis for 40 frames BEFORE any input can reasonably have
	' been given. A direction held for essentially all of them is not a player
	' -- it is the key. Record it, say so, and then IGNORE that direction for
	' the whole game, which makes ALPHA LOCK harmless instead of fatal.
alock_cal:
	alku = 0
	alkd = 0
	alkn = 0
alock_loop:
	WAIT
	alkn = alkn + 1
	IF cont1.up THEN alku = alku + 1
	IF cont1.down THEN alkd = alkd + 1
	IF alkn < 40 THEN GOTO alock_loop
	vstuck = 0
	IF alku > 35 THEN vstuck = 1
	IF alkd > 35 THEN vstuck = 2
	IF vstuck > 0 THEN PRINT AT 578,"ALPHA LOCK DOWN - IGNORED"
	RETURN

title_input:
	' THE PROMPT IS PRINTED HERE, NOT WITH THE REST OF THE TITLE, because
	' this is the moment the game starts listening -- and it is a whole
	' second after the title appears.
	'
	' title_draw runs early on purpose (DESIGN.md 0d-nonies) so the screen
	' arrives instead of filling in, but setup_rest, init_tables and the
	' ALPHA LOCK sample all run AFTER it. For about a second the title is up,
	' finished, and completely deaf. A player types 8-3-8 into that window and
	' the first digit lands in nothing -- then a following 3-8 completes the
	' code, because the 8 they typed second is still standing as state. That
	' is exactly how it was reported, twice, and it is not noise: it is the
	' screen lying about being ready.
	'
	' RallyX and Bust-A-Bobble never showed this because they draw their
	' titles when they are already listening. Keystone cannot -- the whole
	' point of the early draw is that it is early -- so the PROMPT waits
	' instead, and its arrival is the cue that the screen is awake.
	PRINT AT 614,"FIRE TO START"
	tkl = 15
title_wait:
	WAIT
	' Edge-triggered: cont1.key returns the same value on every pass while a
	' key is held, so without this one press would be read as many.
	'
	' NO FRAME FILTER. There was one -- a key had to hold for three passes to
	' count -- added to defend against ALPHA LOCK noise that turned out not to
	' be the problem. It cost real presses instead: 8-3-8 needed a retry and
	' the FIRE button could be missed outright. The diagnosis was wrong and
	' the cure was worse than the disease.
	'
	' The reset below is RallyX's: anything that is not the next digit puts
	' the sequence back to 0, so 8,5,3,8 does not open the page. That is
	' proven code and it is not what was failing here.
	tk = cont1.key
	IF tk <> tkl THEN
		tkl = tk
		IF tk < 10 THEN
			tnx = 0
			IF tk = 8 THEN tnx = 1
			IF t838 = 1 THEN IF tk = 3 THEN tnx = 2
			IF t838 = 2 THEN IF tk = 8 THEN tnx = 3
			t838 = tnx
		END IF
	END IF
	IF t838 = 3 THEN t838 = 0 : GOSUB setup838 : RETURN
	IF cont1.button THEN RETURN
	GOTO title_wait

	' 8-3-8 IS EDGE-TRIGGERED AND ANY STRAY DIGIT RESETS IT (see title_wait).
	'
	' It used to read cont1.key raw every pass and test only for the digit it
	' wanted next. That worked -- but only because 8-3-8 ALTERNATES, so holding
	' 8 cannot advance past the first step. It is an accident of the sequence
	' rather than a design, and it had two costs: 8,5,3,9,8 opened this page as
	' readily as 8,3,8, and a key that READS as held for many frames got a free
	' walk through the state machine.
	'
	' That second one is not hypothetical on this machine. ALPHA LOCK shorts a
	' keyboard line -- and Classic99 defaults to invertcaps, so it reads DOWN
	' with the host's Caps Lock UP -- and this page was reached twice from
	' single keypresses while testing an unrelated change.
	'
	' The reset is the DEFAULT rather than a test for a particular wrong digit:
	' Bust-A-Bobble resets only on a stray 3 and still lets 8,5,3,8 through.
	' ------------------------------------------------------- 838 setup page
setup838:
	CLS
	' ONE PROMPT AT A TIME, NOTHING ELSE ON THE SCREEN, AND NO NUMBERS UNTIL
	' THEY ARE TYPED. There is no heading and no instructions: a page showing
	' exactly one question does not need to explain that one digit answers it,
	' and the second question does not exist until the first is answered.
	'
	' Showing the CURRENT values first was the obvious thing and it cost more
	' than it gave -- two draw routines, a "fire keeps what is shown" escape to
	' make the display mean something, and the defaults had to be applied here
	' as well as in new_game so the page had numbers to show at all. None of it
	' survives: every digit on screen is one the player just typed. Four
	' strings became two, a two-field loop became a straight line, and the page
	' got SMALLER while getting quieter.
	PRINT AT 164,"KOPS 1-9"
	' DEBOUNCE THE 8 THAT OPENED THIS PAGE. cont1.key still reports it on the
	' first pass in here, so the Kops field read it as the answer and the page
	' came up showing 8 before the player had touched anything -- typing 8-3-8
	' set the Kop count to 8 as a side effect of the cheat code. Waiting for the
	' key to be RELEASED is the whole fix, and the same wait sits before every
	' later digit so one held key cannot answer two questions.
	GOSUB su_rel
	GOSUB su_key
	' 0 is not a playable count, so it CLAMPS like the level does rather than
	' being ignored, which would look like a dropped keypress.
	kops0 = sk
	IF kops0 < 1 THEN kops0 = 1
	#sua = 6320			' row 5, col 16 -- beside KOPS
	sud = 48 + kops0
	VPOKE #sua,sud
	GOSUB su_rel
	PRINT AT 228,"LEVEL 01-20"
	' The TENS digit is echoed as it is typed, so the field is never half a
	' number with nothing on screen to say so. 6384 is row 7 column 16 -- the
	' same column as the Kop count above it, so the two values line up.
	GOSUB su_key
	sud1 = sk
	#sua = 6384
	sud = 48 + sk
	VPOKE #sua,sud
	GOSUB su_rel
	GOSUB su_key
	' sud1 * 10 BY ADDITION. `*` compiles to a real TMS9900 MPY, which clobbers
	' r0 and makes the next read of the multiplied variable return the
	' product's high word (CLAUDE.md 3A). Doubling and adding is ten times with
	' none of that, and the largest value it can build is 99 -- inside a byte.
	krk0 = sud1 + sud1
	sud1 = krk0 + krk0
	sud1 = sud1 + sud1
	krk0 = krk0 + sud1
	krk0 = krk0 + sk
	IF krk0 < 1 THEN krk0 = 1
	IF krk0 > 20 THEN krk0 = 20
	' BOTH LEVEL DIGITS ARE REDRAWN, because the clamp may have changed the one
	' already on screen. The clamp is silent by design -- there is no error to
	' dismiss and nothing to retype -- so 80 typed for 08 has to be SEEN landing
	' on 20, or it reads as the page ignoring the second digit. The wait below
	' is what gives it time to be read.
	#sua = 6384
	sut = krk0
	sud = 48
su_tens:
	IF sut < 10 THEN GOTO su_ones
	sut = sut - 10
	sud = sud + 1
	GOTO su_tens
su_ones:
	VPOKE #sua,sud
	#sua = #sua + 1
	sud = 48 + sut
	VPOKE #sua,sud
	FOR sud = 0 TO 40
		WAIT
	NEXT sud
	RETURN

	' TYPING THE LAST DIGIT STARTS THE GAME -- there is no confirm step and no
	' way to back out. Someone who has typed a Kop count and a level has already
	' decided to play, and it means the page is left with KEYS ALONE: fire on
	' the TI is TAB, which Windows may treat as a focus change, and "do not make
	' FIRE the only way out" (CLAUDE.md 3A) applies here as much as on the
	' title. The clamp is what makes that safe -- no typed pair can be refused,
	' so there is no state to be stuck in.
su_rel:
	WAIT
	IF cont1.key <> 15 THEN GOTO su_rel
	RETURN

su_key:
	WAIT
	sk = cont1.key
	IF sk > 9 THEN GOTO su_key
	RETURN

	' ======================================================================
	' A NEW GAME / A NEW KROOK
	' ======================================================================
new_game:
	IF kops0 = 0 THEN kops0 = 4	' one active Kop and three in reserve
	IF krk0 = 0 THEN krk0 = 1
	kops = kops0
	krk = krk0
	#score = 0			' in UNITS OF TEN, with a fixed trailing
					' zero -- the x300 bonus band alone can
					' pay 15,000 for one capture
	#nextk = 1000			' bonus Kop every 10,000 points
	takn(0) = 0
	takn(1) = 0
	takn(2) = 0
	takn(3) = 0
	GOSUB start_krook
	RETURN

start_krook:
	' Kelly starts MID-SCREEN on the first floor's east end. He used to start
	' at x 224, hard against the east wall at 232 -- the far end of the store
	' from floor 1's escalator, which made the climb three full traverses.
	'
	' Standing in the corner is a bad first frame: a quarter of the screen
	' behind him is wall he can never use, and the round opens with the player
	' pinned rather than placed. 120 is the middle of the walkable range
	' (XWALW 8 to XWALL 232), so he starts with room on both sides and the
	' first thing he does is a choice rather than the only move available.
	'
	' It shortens his route by about a hundred pixels, which the chase can
	' afford -- see checkchase.py, and DESIGN.md 0f-quater for the margin.
	klv = 0
	klsc = 7
	klx = 120
	kldir = 0
	entdir = 1			' he starts at the east entrance, so the
					' first floor's traffic comes at him from
					' the west -- the way he has to go
	klst = ST_RUN
	kjf = 0
	kjh = 0
	' THE FIRE THAT STARTED THE ROUND IS NOT ALSO A JUMP. jrel is the jump's
	' release latch -- the button has to come UP between jumps -- and it was
	' never reset when play began, so it carried its value in from whatever
	' happened last. Press FIRE on the title with jrel left at 1 and Kelly
	' jumps on the first frame of the round, having been told to do so by the
	' keypress that only meant "start".
	'
	' It hid on the very first game of a session, because CVBasic zeroes its
	' variables and jrel = 0 already means "wait for a release" -- so it only
	' appeared on the SECOND round onwards, which reads as intermittent.
	'
	' start_krook is the one place worth doing this: new_game, losing a life
	' and advancing a Krook all pass through here, so every entry into play
	' demands a fresh press.
	jrel = 0
	kanim = 0

	' HARRY STARTS ON FLOOR 2 AT THE WEST EDGE OF SCREEN 7, and that is as
	' far left as the clock allows. The research says "the second-floor
	' elevator door", which is screen 3, and it cannot be done:
	'
	'   spawn      escape     round
	'   screen 3   119.9 s    100 s   -- impossible
	'   screen 5   108.1 s    100 s   -- impossible
	'   screen 6   102.3 s    100 s   -- impossible
	'   screen 7    96.4 s    100 s   -- 3.6 s of room
	'
	' HE STARTS AT THE LIFT NOW, AND THAT COST HIM A SPEED CHANGE.
	'
	' His escape route ZIGZAGS -- east along floor 2 to its escalator, WEST
	' along floor 3 to that one, then east again along the roof to the door.
	' From the lift on screen 3 that is 5,120 px against the 4,208 he walked
	' from screen 7, so at his old 1.75 px a pass he needed 105 s of a 100 s
	' round: he could never escape at all, and one of the two loss conditions
	' would quietly have stopped existing. This block used to say exactly that
	' and conclude the lift was impossible. It was impossible AT THAT SPEED.
	'
	' AND QUARTER-PIXELS COULD NOT EXPRESS THE ANSWER. A quarter of a pixel
	' per pass is worth about TEN SECONDS of his route, so the two candidate
	' values straddled the buzzer with nothing in between:
	'
	'   2.00 px/pass   escapes at 102.4 s of a 100 s round   never escapes
	'   2.25 px/pass   escapes at  91.0 s                    nine seconds early
	'
	' Worse, 2.25 was not reachable at all: the accumulator below had two
	' drain steps and therefore a hard ceiling of 2 px a pass, so hsp4 = 9
	' silently delivered 2.00 and he fell two thirds of a screen short of his
	' own escape. See the accumulator comment for the full account.
	'
	' Sixteenths with three drains put the step at about 2.5 s instead of 10,
	' and hsp64 = 35 (2.1875 px/pass) lands him at 96.3 s of the 100 --
	' escaping as the timer expires, which is what was asked for.
	'
	' 35 AND NOT 34, AND THE DIFFERENCE IS THE PLAYER'S OWN SCREEN. Measured
	' in play at 34: standing on an ordinary screen he escaped with one timer
	' unit left, and standing on the ELEVATOR screen he ran out of clock --
	' same route, same constant, decided by where the player happened to be.
	' Everything that moves is paced per loop PASS while the clock is paced in
	' real FRAMES, so a busy screen slows Harry in real time and the clock does
	' not slow with him. A whole round measured 2,335 passes over about 98 s --
	' 23.8 a second, not the 25 the model assumes -- and the heavy screens are
	' slower again. 35 buys the margin that covers the worst of them. The
	' underlying split is recorded in DESIGN.md 0f-ter; this constant only
	' papers over it.
	'
	' The margin
	' that remains is the ROUND's, not the chase's: Kelly still has to get
	' there first, and does. assets/checkchase.py walks both routes out of
	' these constants, models the drain ceiling, and fails the build if the
	' configured speed is one the accumulator cannot deliver.
	hlv = 1
	hsc = 3
	hx = 128
	hdir = 1
	hst = 0
	hsy = 0
	hrun = 0
	hrund = 0

	elvl = 1			' the car starts where Harry does
	elst = 0
	elt = ELWAIT
	eldn = 0

	tsec = TIMEL
	tfr = TICKFR
	tout = 0
	dead = 0
	caught = 0
	escapd = 0
	knock = 0
	tflon = 0
	sct = 0
	fphs = 0

	' Which bounce arc this Krook uses. THE APEX IS THE ONLY THING THAT
	' CHANGES: low balls have to be jumped, high ones cannot be jumped at
	' all and have to be ducked, and the arc is capped below standing height
	' so no ball is ever free to run under. See DESIGN.md 5a.
	' TALL BALLS FROM KROOK 5, which is where the original swaps them in --
	' "levels 1-4 short bouncing balls, level 5 tall" (DESIGN.md 0p). The
	' third arc is ours, and it waits until 10.
	arcs = 0
	IF krk > 4 THEN arcs = 1
	IF krk > 9 THEN arcs = 2
	#arcb = #stac
	IF arcs = 1 THEN #arcb = #arcb + 32
	IF arcs = 2 THEN #arcb = #arcb + 64

	' SPEED IS PER KIND, AND EACH RAMPS ON THE KROOK THE ORIGINAL RAMPS IT
	' (DESIGN.md 0p): carts get faster at 7, biplanes at 8, and the ball's
	' dial is its APEX, not its speed. The base of 2 is measured, not
	' guessed -- carts were tracked in the reference at 0.80 px/frame
	' (48 px/s) and 1.21 (73 px/s), which at this loop's ~25 passes a second
	' is exactly 2 and 3 px per pass. So the two speeds the original uses are
	' the two speeds that were on screen.
	' SIXTY-FOURTHS OF A PIXEL PER FRAME, not whole pixels per loop pass.
	' 2 px a pass at the measured 23.8 passes a second is 47.6 px/s, which is
	' 0.79 px a frame -- 51/64. 3 px a pass is 1.19 px a frame -- 76/64. Same
	' speeds on screen; they simply no longer slow down on a busy screen while
	' the round clock keeps running (DESIGN.md 0f-ter).
	obsp = 51			' beach balls    (was 2 px/pass)
	ocsp = 51			' shopping carts (was 2 px/pass)
	IF krk > 6 THEN ocsp = 76	'                (was 3 px/pass)
	opsp = 51			' biplanes       (was 2 px/pass)
	IF krk > 7 THEN opsp = 76

	' HARRY'S SPEED IS IN QUARTER PIXELS, AND IT DOES NOT RAMP. It used to be
	' 2 px/frame against Kelly's 3, which sounds like a comfortable 1.5x --
	' and Kelly still lost the race to the roof by ELEVEN SECONDS, every
	' round, because the two routes are not the same length. Kelly runs
	' 7,992 px (three traverses plus the roof); Harry runs 4,104, because he
	' spawns beside floor 2's escalator and so skips a traverse. A chase
	' resolves on PATH / SPEED, and Kelly needs to be more than TWICE
	' Harry's speed before he is ahead at all. See DESIGN.md 4a.
	'
	' 1.75, AND THE NUMBER IS MEASURED, NOT GUESSED. Tracked off the
	' reference video (DESIGN.md 4a), the 2600's Kelly covers 0.40 screen
	' widths a second and its Harry 0.193 -- a ratio of 2.07. At 1.5 ours
	' was 2.67 and the crook visibly strolled. 1.75 brings it to 2.29.
	'
	' 2.0 would match the original exactly and still cannot be used, because
	' OUR routes are not the original's: Kelly's is 1.95x Harry's here, so a
	' speed ratio of 2.0 leaves him 5.2 s ahead at the escape edge -- less
	' than one beach ball (9 s). At 1.75 he is 10.1 s ahead, which absorbs a
	' hit. That figure counts the LIFT, which is on his way and carries him
	' two floors; the foot-only route is 5 s worse and is not the route
	' anybody takes.
	'
	' THE PER-KROOK DIAL IS STILL NOT HIS SPEED. It is the obstacles, which
	' is also the only dial the manual names (`obsp` above, and the ball
	' arcs). assets/checkchase.py checks all of this mechanically -- run it
	' if you touch these numbers.
	hsp64 = 57			' 0.891 px per FRAME, every Krook
	hacc = 0
	hspd = 2

	CLS
	GOSUB draw_screen
	GOSUB scan_canvas
	GOSUB hud_all
	#lf = FRAME
	RETURN

	' ======================================================================
	' DRAWING THE STORE -- four blits, once per screen crossing
	' ======================================================================
	' This is the whole cost of the flip, and it is paid on a discrete event
	' rather than every frame. RallyX's pan repaints 576 chars every time the
	' camera moves one cell; this repaints 640 about once every two seconds
	' of running.
	' SPRITES OFF BEFORE THE BLIT, NOT AFTER IT. This routine WAITs between
	' bands -- one band a frame, because a burst of VDP writes past a few
	' dozen in one frame is silently dropped -- so painting the new screen
	' takes several frames, and for all of them the OLD screen's actors and
	' obstacles were still sitting on top of it. Following Harry through a
	' seam showed him and every cart from the floor he had just left,
	' standing on a shop that was assembling itself underneath them.
	'
	' They are put back by the normal draw on the same pass, so the crossing
	' reads as a cut rather than as a dissolve with ghosts in it.
	' EACH BAND IS FINISHED BEFORE THE FRAME IT IS DRAWN IN ENDS, and the
	' bands go TOP DOWN. Both halves of that matter.
	'
	' The blit paints the template -- shelves, pillars and all -- and the
	' radios and prizes then take out the fixtures they stand in. Those two
	' used to be four frames apart: all four bands blitted with a WAIT
	' between them, and only afterwards the clearing. So every screen change
	' showed its counters and beams for several frames and then erased them,
	' which reads as the shop flickering rather than as it being drawn.
	'
	' TOP DOWN because a band's beam tops are stamped into the SLAB ROW OF
	' THE BAND ABOVE. Going bottom-up, band 1's blit would paint over the
	' beam tops band 0 had just put there. Going top-down the band above is
	' always already drawn, so everything a band needs -- its own cells and
	' the row it borrows overhead -- is final by the time its WAIT arrives.
	'
	' `3 - dq` rather than `FOR dlv = 3 TO 0 STEP -1`: dlv is an unsigned
	' byte, so counting down past zero wraps to 255 and the loop never ends
	' (CLAUDE.md 3A).
draw_screen:
	GOSUB hide_play
	GOSUB load_band
	FOR dq = 0 TO 3
		' WAIT FIRST, NOT LAST. A band is blitted and then corrected -- the
		' beam top stamped on, the pillar under a radio taken off -- and the
		' raster does not stop while that happens. Starting the burst in the
		' middle of a frame let the raster pass the band between the blit and
		' the correction, so the uncorrected version was shown for a frame:
		' at round start, after CLS, that reads as a support beam appearing
		' and being rubbed out. Beginning at vblank gives the whole burst a
		' clear run at the rows before the beam reaches them. It also still
		' gives each band its own frame, which is what stops a VDP write
		' burst past a few dozen from being silently dropped.
		WAIT
		dlv = 3 - dq
		dix = lv8(dlv)
		dix = dix + klsc
		#dta = #stix + dix
		dt = PEEK(#dta)
		#dsrc = #tsrc(dt)
		#ddst = #bdst(dlv)
		SCREEN stor_tpl,#dsrc,#ddst,32,5,32
		' finish this band before the frame ends -- see the note above
		bt = dlv
		GOSUB beam_one
		rdall = 1
		rbn = dlv
		GOSUB radio_band
		plv = dlv
		GOSUB prize_one
	NEXT dq
	GOSUB esc_cap_draw
	GOSUB draw_car
	RETURN

	' A SUPPORT BEAM HAS TO REACH THE FLOOR IT HOLDS UP, AND THAT FLOOR IS
	' NOT IN ITS OWN BAND. A beam fills its band's four air rows, so its top
	' pixel sits under the slab row of the band ABOVE -- and a slab row is
	' five pixels of bar over three of green (see SLAB), so the beam stopped
	' three pixels short of the bar on every storey. It read as a beam that
	' misses the floor, which is exactly what it was.
	'
	' It cannot be drawn into either template. The beam belongs to the band
	' below and the row belongs to the band above, and the two templates are
	' chosen independently per screen, so no template knows both. So the
	' band blits go down first and the tops are stamped afterwards, from a
	' per-template column table -- the same shape as the escalator's head cap.
	'
	' Bands 0 and 1 only. Band 2's top row is the ROOF DECK, which is grey
	' over grey with no green to bridge, and the roof itself has no band
	' above it at all.
	' BANDS 0 TO 2 -- ALL THREE SHOPPING FLOORS. It used to stop at 1,
	' because band 2's ceiling is the ROOF DECK and the deck had no green
	' under it: a beam there already ran straight into grey and needed
	' nothing. Giving the roof its three green rows (so the lift shaft stops
	' under it, like every other floor) took that away, and the top floor's
	' beams started falling three pixels short.
	'
	' So the roof gets its own version of the stamp. A beam HOLDS THE ROOF
	' UP and must reach it; the shaft merely stops beneath it.
beam_one:
	IF bt > 2 THEN RETURN		' the roof has no band above it
	bti = lv8(bt)
	bti = bti + klsc
	#bta = #stix + bti
	#btp = #stpl + PEEK(#bta) * 4.
	#btr = #bdst(bt)
	#btr = #btr + 6112		' 6144 - 32: the row ABOVE the band
	FOR btj = 0 TO 3
		btc = PEEK(#btp)
		#btp = #btp + 1
		IF btc > 0 THEN
			' STORED AS COLUMN PLUS ONE. Zero is the terminator and
			' column 0 is a real place -- the west end wall -- so the
			' raw column could not be used for both.
			btc = btc - 1
			#btw = #btr + btc
			' A WALL'S TOP IS BRICK; A PILLAR'S IS SOLID. The end walls
			' are the only beams at the extreme columns, and cutting
			' the brick pattern into the bar above them carries the
			' bond through instead of capping it with a grey block.
			btk = CH_SLABP
			IF bt = 2 THEN btk = CH_ROOFSP
			IF btc = 0 THEN
				btk = CH_SLABE
				IF bt = 2 THEN btk = CH_ROOFSE
			END IF
			IF btc = 31 THEN
				btk = CH_SLABE
				IF bt = 2 THEN btk = CH_ROOFSE
			END IF
			VPOKE #btw,btk
		END IF
	NEXT btj
	RETURN

	' THE HANDRAIL'S TOP TURN BELONGS TO THE FLOOR ABOVE. The staircase fills
	' this band's air; the rail carries on over the top of it, which puts one
	' row of cells in the storey above. It is two or three characters wide and
	' the reference crosses the floor bar in the same place, so the bar losing
	' those few pixels is the picture, not damage.
esc_cap_draw:
	FOR ec = 0 TO 2
		#eca = #stes + ec
		ecs = PEEK(#eca)
		IF ecs < 2 THEN
			ecx = 0
			ecb = 0
			IF ecs = 1 THEN
				ecx = 7
				ecb = 32
			END IF
			' FLOOR 3 CLIMBS TO THE ROOF, which is grey where a shopping
			' floor is green, so its crossing needs its own composites.
			IF ec = 2 THEN ecb = 64
			IF ecx = klsc THEN
				FOR ecr = 0 TO 1
					#ecp = #stcp
					#ecp = #ecp + ecb
					IF ecr = 1 THEN #ecp = #ecp + 16
					ecn = 0
					WHILE ecn < 8
						ecc = PEEK(#ecp)
						#ecp = #ecp + 1
						ecv = PEEK(#ecp)
						#ecp = #ecp + 1
						ecn = ecn + 1
						IF ecc > 0 THEN
							' Row 0 lands on the band above's AIR
							' (its row 3), row 1 on its FLOOR (row
							' 4). Row 1's characters carry the floor
							' colours themselves, so the bar shows
							' through instead of being erased.
							#ecw = 6144
							#ecw = #ecw + #bdst(ec + 1)
							#ecw = #ecw + 96
							IF ecr = 1 THEN #ecw = #ecw + 32
							#ecw = #ecw + ecc
							VPOKE #ecw,ecv
						END IF
					WEND
				NEXT ecr
			END IF
		END IF
	NEXT ec
	RETURN

	' ---------------------------------------------- this screen's obstacles
	' Obstacles belong to a SCREEN BAND, not to the world, and they run only
	' while their screen is shown. That falls straight out of the flip, and
	' it is what keeps the moving-actor count at 14 instead of 96.
load_band:
	FOR llv = 0 TO 3
		lb = llv + llv			' lb = llv*2, two slots per band
		lix = lv8(llv)
		lix = lix + klsc
		#loa = #stob
		' A COMPUTED `FOR 1 TO 0` STILL RUNS ITS BODY ONCE in CVBasic, and lix
		' is 0 for the whole of screen 0 -- which would read every obstacle on
		' it from the NEXT band's entry, silently, on one screen out of eight.
		IF lix > 0 THEN
			FOR lq = 1 TO lix
				#loa = #loa + 6	' 6 bytes per band
			NEXT lq
		END IF
		' Only TWO of the table's three slots are used -- see the DIM
		' comment. The third is still read so the file offset stays right.
		FOR ls = 0 TO 2
			lk = PEEK(#loa)
			#loa = #loa + 1
			lx = PEEK(#loa)
			#loa = #loa + 1
			IF ls = 2 THEN GOTO ld_skip
			li = lb + ls
			' THE HAZARDS ARRIVE ONE PER KROOK, which is the original's
			' progression and not a ramp of one dial (DESIGN.md 0p):
			'
			'   1  short beach balls, and nothing else
			'   2  + radios          5  balls go tall
			'   3  + shopping carts  6  a second hazard per floor
			'   4  + biplanes        7  carts faster   8+ planes faster
			'
			' A hazard that has not arrived yet becomes a BALL rather
			' than nothing, so a floor is never empty and Krook 1 is
			' the "short balls" screen the guides describe. This is
			' also why there are no biplanes on Krook 1: the one thing
			' that costs a whole Kop should not be the first thing a
			' new player meets.
			IF lk = OB_RADIO THEN
				IF krk < 2 THEN lk = OB_BALL
			END IF
			IF lk = OB_CART THEN
				IF krk < 3 THEN lk = OB_BALL
			END IF
			IF lk = OB_PLANE THEN
				IF krk < 4 THEN lk = OB_BALL
			END IF
			' The second one per floor arrives at Krook 6 -- the
			' original's "double radios" level.
			IF ls = 1 THEN
				IF krk < 6 THEN lk = 0
			END IF
			' AND HOW MANY FLOORS CARRY ONE AT ALL. The gates above
			' decide what KIND a hazard is; this decides whether the
			' floor has one.
			'
			' The kind-arrival rule downgrades anything that has not
			' arrived yet to a beach ball rather than leaving the floor
			' empty, so that a floor is never bare -- and the effect on
			' Krook 1 was a ball on all FOUR floors of every populated
			' screen. All four bands are on screen at once, so that is
			' four identical balls in view at all times, which is not
			' what "merely a few beach balls" describes.
			'
			' Per-band count was never the problem: only one slot is
			' live until Krook 6. It is the number of OCCUPIED FLOORS,
			' and it had no ramp at all.
			'
			' Floors 1 and 3 stay clear on Krook 1, floor 1 joins on
			' Krook 2, and the roof on Krook 3. ALTERNATING rather than
			' clearing the top or bottom half, so the empty floors do
			' not stack into a visibly dead region that reads as a bug
			' -- and the ROOF is last, because that is where the round
			' is decided.
			IF krk < 2 THEN
				IF llv = 1 THEN lk = 0
			END IF
			IF krk < 3 THEN
				IF llv = 3 THEN lk = 0
			END IF
			' NO SPRITE HAZARD ON THE FLOOR THE CROOK IS STANDING ON,
			' AND THE DECISION IS MADE HERE -- once, as the screen is
			' drawn, and never revisited while it is on screen.
			'
			' It was a test in the draw loop and another in the
			' collision test, both re-evaluated every frame, so the
			' hazards came and went as Harry walked on and off the
			' screen: run him to the edge and a floor's worth of balls
			' appeared out of nothing behind him. A rule about what
			' this screen CONTAINS cannot be a per-frame question --
			' the answer changes while the player is looking at it.
			'
			' Zeroing the kind here also makes both of those tests
			' unnecessary: an obstacle that was never loaded cannot be
			' drawn and cannot hit anybody.
			'
			' Radios are exempt. They are characters rather than
			' sprites, they do not move, and a fixture the crook runs
			' past is not what this rule is about.
			IF lk <> OB_RADIO THEN
				IF hsc = klsc THEN
					IF hlv = llv THEN lk = 0
				END IF
			END IF
			obk(li) = lk
			' A RADIO NEEDS A CELL, NOT A PIXEL, because it is drawn as
			' characters. Divided by repeated subtraction: `/` compiles
			' to a real TMS9900 DIV (CLAUDE.md 3A), and this runs once
			' per screen where the divide would run per obstacle -- so
			' the loop is the cheaper of the two, and the only one that
			' cannot be got wrong by a rounding rule.
			obc(li) = 0
			' PER KIND, not one global speed (see start_krook).
			' THE SPEED IS A PROPERTY OF THE KIND, and obs() only ever
			' held a copy of it -- set from the kind here, zeroed for a
			' radio below, and read in one place. upd_obst derives it
			' from obk() instead, which is 8 bytes of RAM back and one
			' fewer thing that can disagree with itself.
			' THEY COME FROM THE FAR SIDE. Kelly walked into this screen
			' from one edge, so the obstacles start at the OTHER edge and
			' run toward him. Crossing a seam then always presents an
			' ONCOMING stream, never a set of backs he has to catch up
			' with -- and it means the direction he is travelling is
			' always the direction the danger comes from.
			'
			' The table's x becomes a stagger from that edge rather than
			' an absolute position, and the slot index spreads them out
			' so they arrive in sequence instead of as one wall.
			'
			' THE SECOND ONE IS A FIXED DISTANCE BEHIND THE FIRST, AND
			' THAT DISTANCE IS SET BY THE JUMP.
			'
			' It used to be `(lx AND 63) + 64` -- a masked byte out of
			' the placement table plus a constant -- so the gap between
			' the two hazards was whatever those two bytes happened to
			' differ by. Measured across the five populated screens it
			' came out 46, 46, 70, 70, 70 px. Screens 2 and 4 flank the
			' elevator, so the store had a visibly tighter pair on one
			' side of it than the other, which is exactly how it was
			' reported from play.
			'
			' Both numbers are too small, which is the real fault. Kelly
			' closes on an oncoming hazard at WALKSP + the hazard's own
			' speed = 6 px a pass, and a jump lasts about 30 passes, so
			' a jump eats ~120 px of closing distance. At 46 or 70 there
			' is NO screen where he can land between the two: he clears
			' the first and comes down on the second.
			'
			' HAZGAP is that distance with margin. The first hazard
			' still lands where the table puts it, so the placement
			' variety is unchanged; only the pairing is now a fact about
			' the jump rather than an accident of two bytes.
			' assets/checkspace.py measures it and fails the build.
			' THE SECOND SLOT IS MEASURED FROM THE FIRST, not from its
			' own table byte. Adding HAZGAP to its own `lx AND 63` would
			' still leave the GAP varying by up to 63 px between screens
			' -- the same fault in a politer form, and the reason the two
			' sides of the elevator differed in the first place. Holding
			' slot 0's stagger and adding to that makes the gap exactly
			' HAZGAP on every screen, while slot 0 still lands wherever
			' the table puts it, so the placement variety is untouched.
			stag = lx AND 63
			IF ls = 0 THEN stg0 = stag
			IF ls = 1 THEN stag = stg0 + HAZGAP
			IF ls = 2 THEN stag = stag + 128
			IF entdir = 0 THEN
				obd(li) = 0			' from the EAST, heading west
				obx(li) = 240 - stag
			ELSE
				obd(li) = 1			' from the WEST, heading east
				obx(li) = stag
			END IF
			obh(li) = 0
			' THE BALL IS ON THE GROUND WHEN HE GETS TO IT.
			'
			' The bounce phase used to be `lx AND 31` -- a byte out of
			' the placement table, which is to say arbitrary. Run onto
			' a screen and the first ball might be at the bottom of its
			' arc, where a jump clears it, or at the top, where it has
			' to be ducked, and nothing on the way in told you which.
			' Sometimes you could keep running and jump it; sometimes
			' the same approach at the same speed could not be jumped
			' at all. That is not difficulty, it is a coin toss.
			'
			' So the phase is worked BACKWARDS from the meeting. He
			' closes 4 px a pass and the ball 2, so they meet in
			' (gap / 6) passes; the phase advances one a pass and wraps
			' at 32, so seeding it with the NEGATIVE of that lands it on
			' phase 0 -- the ground -- exactly as they arrive.
			'
			' The gap is the same either way round: he enters at one
			' wall and the ball starts `stag` in from the other, so it
			' is 232 - stag whichever direction the floor runs.
			'
			' It stays forgiving rather than exact. The arc is flat near
			' the bottom, so anything within eight passes either side is
			' still under the jump; and it only holds for an unbroken
			' run, which is the case the player is entitled to read off
			' the screen. Duck, stop or take a hit and everything after
			' is out of step again -- which is the game.
			obp(li) = lx AND 31
			IF lk = OB_BALL THEN
				obg = 232 - stag
				GOSUB ball_phase
				obp(li) = obq
			END IF
			obht(li) = 0
			IF lk = OB_PLANE THEN obh(li) = 16
			IF lk = OB_RADIO THEN
				' PLACED, NOT STAGGERED. A radio does not move, so
				' the oncoming-stream stagger the rolling hazards
				' use says nothing about it -- it just puts a
				' fixture at an arbitrary offset. The original
				' CENTRES a lone one and SPLITS a pair
				' symmetrically about the centre; measured off the
				' reference, two sit at 0.26 and 0.68 of the
				' screen (midpoint 0.47) and one sits near the
				' middle. 56 and 184 put their centres at 64 and
				' 192, whose midpoint is 128 -- dead centre -- and
				' all three are multiples of 8, so each lands on a
				' cell boundary with no rounding.
				obx(li) = 120
				IF krk > 5 THEN
					obx(li) = 56
					IF ls = 1 THEN obx(li) = 184
				END IF
				ocx = obx(li)
				GOSUB rad_col
				obc(li) = ocn
			END IF
ld_skip:
		NEXT ls
	NEXT llv
	RETURN

	' obx / 8, by repeated subtraction. `/` compiles to a real TMS9900 DIV
	' (CLAUDE.md 3A) and this is the only place the game needs one; at most
	' thirty passes, run once per obstacle when a screen loads and never in a
	' frame, so the loop is cheaper than the instruction.
rad_col:
	ocn = 0
rc_loop:
	IF ocx < 8 THEN RETURN
	ocx = ocx - 8
	ocn = ocn + 1
	GOTO rc_loop

	' gap / 6, and then 32 minus it: the phase that will have wrapped to zero
	' by the time they meet. Repeated subtraction because `/` compiles to a
	' real TMS9900 DIV (CLAUDE.md 3A), and this runs once per ball when a
	' screen loads rather than in a frame.
ball_phase:
	obq = 0
bp_loop:
	IF obg < 6 THEN GOTO bp_done
	obg = obg - 6
	obq = obq + 1
	IF obq > 31 THEN obq = 0
	GOTO bp_loop
bp_done:
	IF obq > 0 THEN obq = 32 - obq
	RETURN

	' ------------------------------------------------- collectibles as CHARS
	' Not sprites: a band already carries Kelly plus three obstacles, which is
	' exactly four per scanline, and the VDP drops the fifth outright. A prize
	' that vanishes when the floor gets busy would read as a scoring bug.
prize_one:
	pix = lv8(plv)
	pix = pix + klsc
	#pca = #stco + pix
	#pca = #pca + pix		' 2 bytes per band
	pk = PEEK(#pca)
	#pcb = #pca + 1
	pc = PEEK(#pcb)
	' already collected this Krook?
	pby = plv
	pbi = klsc
	pmk = msk(pbi)
	IF takn(pby) AND pmk THEN pk = 0
	cok(plv) = pk
	coc(plv) = pc
	IF pk > 0 THEN
		' TWO BY TWO, standing on the slab: band rows 2 and 3, the
		' same two the radios use. One character could not say
		' "money bag" rather than "yellow blob", and everything
		' else on the floor is sixteen pixels.
		#pva = 6144
		#pva = #pva + #bdst(plv)
		#pva = #pva + 64		' row 2 of the band
		#pva = #pva + pc
		' AND THE FIXTURE BEHIND IT GOES AWAY, for the same reason
		' a radio's does: a pillar fills all four air rows, so a
		' prize on one would leave its top half hanging above.
		#wca = #pva - 64
		GOSUB wall_clear
		#wca = #wca + 1
		GOSUB wall_clear
		#wca = #pva - 32
		GOSUB wall_clear
		#wca = #wca + 1
		GOSUB wall_clear
		' and the beam top hanging above it
		#bca = #pva - 96
		GOSUB beam_clear
		#bca = #bca + 1
		GOSUB beam_clear
		' and the rest of the counter it stands in
		#wsa = #pva - 1
		wsd = 0
		GOSUB wipe_shelf
		#wsa = #pva + 2
		wsd = 1
		GOSUB wipe_shelf
		pch = CH_BAGTL
		IF pk = 2 THEN pch = CH_CASETL
		VPOKE #pva,pch
		pch = CH_BAGTR
		IF pk = 2 THEN pch = CH_CASETR
		#pvb = #pva + 1
		VPOKE #pvb,pch
		pch = CH_BAGBL
		IF pk = 2 THEN pch = CH_CASEBL
		#pvb = #pva + 32
		VPOKE #pvb,pch
		pch = CH_BAGBR
		IF pk = 2 THEN pch = CH_CASEBR
		#pvc = #pvb + 1
		VPOKE #pvc,pch
	END IF
	RETURN

	' ----------------------------------------------------- the elevator car
	' The car is 4 chars wide and 3 tall -- no sprite here can be that, and
	' it does not need to be, because it only ever occupies whole cells.
draw_car:
	IF klsc <> 3 THEN RETURN
	FOR clv = 0 TO 2
		' 0 shut, 1 part-open, 2 open -- and only ONE floor is ever anything
		' but shut, because there is only one car.
		cst = 0
		IF clv = elvl THEN cst = eldp
		FOR crw = 0 TO 3
			#cva = 6144
			#cva = #cva + #bdst(clv)
			IF crw > 0 THEN #cva = #cva + 32
			IF crw = 2 THEN #cva = #cva + 32
			IF crw = 3 THEN #cva = #cva + 64
			#cva = #cva + ELCOL
			FOR ccl = 0 TO 3
				GOSUB car_cell
				VPOKE #cva,ccw
				#cva = #cva + 1
			NEXT ccl
		NEXT crw
	NEXT clv
	RETURN

	' ONE CELL OF THE DOORWAY, from its column (ccl 0-3), its band row
	' (crw 0-3) and the door state (cst). Four columns and four rows, so
	' sixteen cells, and the three interesting things about a cell are all
	' edges: column 0 and column 3 carry the JAMB, row 0 carries the LINTEL
	' and row 3 the SILL.
	'
	' THE SILL IS REVEALED AS THE DOORS PART, which falls out of this rather
	' than being arranged: shut, every cell is plain door and there is no
	' sill to see; part-open, only the middle two columns show car and sill;
	' open, all four do. A sill sitting under a shut door would be a ledge
	' with nothing behind it.
	'
	' Nested IFs, never `ccl > 0 AND ccl < 3` -- the 9900 backend miscompiles
	' a compare-AND-compare (CLAUDE.md 3A).
car_cell:
	ccw = CH_EDOOR
	' THE SILL IS THERE WHETHER THE DOORS ARE OR NOT. Set before the door
	' states so a shut door gets it, and so do the two OUTER columns of a
	' part-open one -- which the cst=1 branch below never touches. The step
	' is then continuous across all four columns of the opening on every
	' floor, including the three the car is not on. It spans the opening and
	' not the jambs: EJAMBL/EJAMBR sit in the wall column either side and
	' stand on the floor beside the threshold, which is where a door post
	' goes.
	IF crw = 3 THEN ccw = CH_EDOORS
	' PART-OPEN: the middle two columns are car, the outer two are still door.
	' Identical to the open state below except for which columns it covers,
	' which is what a door sliding back into its pockets looks like -- and it
	' is only expressible now that the jambs have moved out into the wall and
	' left all four doorway columns free.
	IF cst = 1 THEN
		IF ccl > 0 THEN
			IF ccl < 3 THEN
				ccw = CH_ECAR
				IF crw = 0 THEN ccw = CH_ECART
				IF crw = 3 THEN ccw = CH_ECARS
			END IF
		END IF
	END IF
	IF cst = 2 THEN
		ccw = CH_ECAR
		IF crw = 0 THEN ccw = CH_ECART
		IF crw = 3 THEN ccw = CH_ECARS
	END IF
	RETURN

	' ======================================================================
	' INPUT
	' ======================================================================
read_input:
	inl = 0
	inr = 0
	inu = 0
	ind = 0
	inb = 0
	IF cont1.left THEN inl = 1
	IF cont1.right THEN inr = 1
	IF cont1.up THEN inu = 1
	IF cont1.down THEN ind = 1
	IF cont1.button THEN inb = 1
	' A direction the title measured as stuck is the ALPHA LOCK key, not the
	' player. Dropping it here rather than at each use means duck, elevator
	' entry and elevator exit all get the same treatment automatically.
	IF vstuck = 1 THEN inu = 0
	IF vstuck = 2 THEN ind = 0
	RETURN

	' ======================================================================
	' KELLY
	' ======================================================================
move_kelly:
	' --- riding: no input, invincible, and the ride finishes itself
	IF klst = ST_ESC THEN
		' HE IS STANDING ON A STEP, so he moves at the STEP's rate: 2 px
		' across and 1 up PER PASS -- the staircase's own slope, and exactly
		' what one phase of esc_tick moves the pattern by.
		'
		' NOT `fdv`, WHICH IS THE WHOLE POINT. Everything else in this loop
		' is paced by the frame delta, and pacing him that way too made him
		' outrun the steps the moment a pass cost more than one frame: his
		' feet started planted on a tread and ended floating above it.
		' Pacing the ANIMATION by fdv instead is worse -- four phases cannot
		' be stepped by 2 or 3 without aliasing, and the staircase runs
		' backwards (see esc_tick). The only arrangement that cannot drift
		' is the one where both are driven by the same fixed step, so the
		' rider is clocked by the pass, like the steps he is standing on.
		'
		' THE FIRST FEW PASSES ARE THE STEP ON. Walking on, his feet are on
		' the floor and the bottom tread is 4 to 7 px above them, so he
		' climbs at 2 px a pass until he catches it (the tread is rising at
		' 1, so the gap closes at 1 a pass) and then rides with it. Jumping
		' on he lands ON a tread, so eson is 0 and this never runs.
		IF esy < eson THEN esy = esy + 1
		esy = esy + 1
		IF esxr = 1 THEN klx = klx + 2 ELSE klx = klx - 2
		IF esy >= ESCRISE THEN
			klv = klv + 1
			klst = ST_RUN
			IF esxr = 1 THEN klx = ESCHXE ELSE klx = ESCHX
		END IF
		RETURN
	END IF
	IF klst = ST_ELEV THEN
		klv = elvl
		IF elst = 0 THEN
			IF ind = 1 THEN
				klst = ST_RUN
				kjh = 0
			END IF
		END IF
		RETURN
	END IF

	' --- knockback from an obstacle: brief, and it does not stun
	IF knock > 0 THEN
		knock = knock - 1
	END IF

	' --- jumping: the arc is a table, so the apex is exactly 14
	IF klst = ST_JUMP THEN
		kjp = kjh
		kjf = kjf + fdv
		IF kjf > 29 THEN
			kjf = 0
			kjh = 0
			klst = ST_RUN
		ELSE
			kjh = jarc(kjf)
		END IF
	END IF

	' --- starting a jump. A RUNNING jump is the same arc with the
	'     horizontal speed kept, which is what the manual describes.
	IF klst = ST_RUN THEN
		IF inb = 1 THEN
			IF jrel = 1 THEN
				' LATCH THE ARC'S DIRECTION HERE, once, and fly
				' it -- see the note over the running block.
				kjdx = 0
				IF inr = 1 THEN kjdx = 1
				IF inl = 1 THEN kjdx = 2
				klst = ST_JUMP
				kjf = 1
				kjh = jarc(1)
				jrel = 0
				sfj = 1
			END IF
		END IF
	END IF
	IF inb = 0 THEN jrel = 1

	' --- ducking. Only from the ground, and it costs horizontal movement --
	'     it is a height change, not a dodge.
	IF klst = ST_RUN THEN
		IF ind = 1 THEN klst = ST_DUCK
	END IF
	IF klst = ST_DUCK THEN
		IF ind = 0 THEN klst = ST_RUN
		RETURN
	END IF

	' --- entering the elevator
	IF klst = ST_RUN THEN
		IF inu = 1 THEN GOSUB try_elev
	END IF
	IF klst = ST_ELEV THEN RETURN

	' --- running
	' THE END WALLS ARE MOVEMENT LIMITS, NOT A CLAMP APPLIED AFTERWARDS.
	'
	' They used to be the latter, and that is the whole bug: on screen 7 Kelly
	' walked on to x = 254, the crossing routine then noticed there was no
	' screen 8 and set him to 232 -- a 22 px snap BACKWARDS. He reached the
	' wall and was thrown off it. Testing the limit BEFORE the step means he
	' arrives at the wall and stays there, which is what a wall does.
	' IN THE AIR HE IS BALLISTIC. The horizontal direction is fixed at
	' take-off and the stick is ignored until he lands: steering in mid-air
	' is not a jump, it is flight, and it also let him flip which way he was
	' facing halfway through an arc. kjdx is 0 for a standing jump, 1 for a
	' running one to the right, 2 to the left.
	IF klst = ST_JUMP THEN
		inl = 0
		inr = 0
		IF kjdx = 1 THEN inr = 1
		IF kjdx = 2 THEN inl = 1
	END IF

	' HIS STEP FOR THIS PASS, IN WHOLE PIXELS. Computed whether or not he is
	' moving: the accumulator drains in the same pass it fills, so standing
	' still banks nothing and he cannot lurch on the first pass of a walk.
	pacc = kacc
	psp64 = KWALK64
	GOSUB pace_step
	kacc = pacc
	kspd = pspd

	kmv = 0
	IF inl = 1 THEN
		kldir = 0
		kmv = 1
		IF klsc = 0 THEN
			IF klx > XWALW THEN
				kroom = klx - XWALW
				IF kroom < kspd THEN klx = XWALW ELSE klx = klx - kspd
			END IF
		ELSE
			IF klx < kspd THEN
				GOSUB cross_west
			ELSE
				klx = klx - kspd
			END IF
		END IF
	END IF
	IF inr = 1 THEN
		kldir = 1
		kmv = 1
		IF klsc = 7 THEN
			IF klx < XWALL THEN
				kroom = XWALL - klx
				IF kroom < kspd THEN klx = XWALL ELSE klx = klx + kspd
			END IF
		ELSE
			kroom = 255 - klx
			IF kroom < kspd THEN
				GOSUB cross_east
			ELSE
				klx = klx + kspd
			END IF
		END IF
	END IF
	IF kmv = 1 THEN
		' THE FIRST STEP OFF THE MARK IS ALWAYS HEARD. sfw is a distance --
		' a step every fifteen pixels -- so a short tap of the stick moved
		' him a few pixels and made NO sound at all. That does not read as
		' a short step, it reads as the controls being ignored, and it is
		' worst exactly where a player taps rather than holds: lining up a
		' jump, or edging around a hazard.
		'
		' Priming the accumulator to the threshold makes the very next pass
		' fire. It does not cheat the RATE: the trigger subtracts fifteen
		' rather than zeroing, so the pixels actually travelled still carry
		' into the following step and a held run comes out at 6.9 a second
		' either way.
		IF kmvl = 0 THEN sfw = 15
		' AN ODOMETER, NOT A CLOCK -- pixels travelled, exactly like
		' Harry's hanim. It counted PASSES once, which made his legs cycle
		' slower on the escalator screens while he still ran at the same
		' speed; that was fixed by counting the frame DELTA instead, which
		' traded one mismatch for another -- his legs then kept wall-clock
		' time while his body still moved once per pass, so his stride
		' slipped against the ground whenever the loop was busy.
		'
		' Distance settles it. A pose per 8 px at any frame rate, and a
		' footstep is a stride rather than a tick.
		kanim = kanim + kspd
		sfw = sfw + kspd
	END IF
	' Whether he moved THIS pass, for the test above to compare against next
	' pass. Set unconditionally and after the block, so a pass spent standing
	' still re-arms the first step for whenever he sets off again.
	kmvl = kmv

	' --- boarding an escalator happens by TOUCHING it, per the manual
	IF klst = ST_RUN THEN GOSUB try_esc
	IF klst = ST_JUMP THEN GOSUB try_esc
	RETURN

	' ---------------------------------------------------- screen crossings
	' EIGHT PIXELS OF HYSTERESIS. Landing on x = 0 after crossing east would
	' put Kelly one step from re-crossing, and the store would re-blit every
	' frame at the seam. Landing on 8 makes the seam four frames of running
	' wide in each direction.
	' THE STORE HAS WALLS. Clamping to 255 put Kelly's 16 px sprite entirely
	' past the right edge of the screen -- he vanished, and since nothing
	' moved him back it read as having walked out of the world and got stuck.
	' 232 leaves him standing against the wall the end templates now draw.
cross_east:
	IF klsc = 7 THEN
		klx = 232
		RETURN
	END IF
	klsc = klsc + 1
	klx = 8
	entdir = 0			' he entered at the WEST edge heading east,
					' so the obstacles come from the east
	GOSUB draw_screen
	RETURN

cross_west:
	IF klsc = 0 THEN
		klx = 8
		RETURN
	END IF
	klsc = klsc - 1
	klx = 247
	entdir = 1			' entered at the EAST edge heading west
	GOSUB draw_screen
	RETURN

	' ------------------------------------------------------------ escalator
	' ONE working escalator per floor, at that floor's alternating end --
	' west, east, west. An escalator drawn where none works would be a step
	' the player runs to and nothing happens.
	' ESCALATORS RUN BOTH WAYS. Stand at the foot and you are carried up;
	' stand at the head of the flight that arrives from the floor below and
	' you are carried down. It is one staircase used from either end, not two
	' -- which is also why the down zone on a floor is the UP zone of the
	' floor beneath it, offset by one band.
	' UP ONLY. Riding down was built at one point and has been taken out
	' again at the reviewer's direction -- these only ever climb.
	'
	' Losing it also removed the re-board lock, which existed solely because
	' stepping off at the head put you inside the zone that rode the same
	' flight back down. With no down ride there is no such zone: a floor's
	' escalator is at the opposite end from the one below it, so arriving at
	' the top of one never lands you on the foot of another.
try_esc:
	IF klv = 3 THEN RETURN			' the roof climbs nowhere
	#esa = #stes + klv
	esd = PEEK(#esa)
	IF esd = 255 THEN RETURN
	kcx = klx + 8
	' HOW FAR ALONG THE FLIGHT HE IS, measured from its head, in the flight's
	' own x. A step's centre sits at 8 x its index, so the bottom step (9)
	' owns 68..76, the one above it 60..68, and so on up. Both directions
	' land on the same numbers because the east flight is the west one
	' mirrored. The `+ escp` terms are the animation: the whole staircase
	' slides 2 px along and 1 px up per phase, and a rider who ignores that
	' boards up to 3 px out of register and drifts for the whole ride.
	IF esd = 0 THEN
		IF klsc <> 0 THEN RETURN
		esw = kcx + escp
		esw = esw + escp
		' left of the head this underflows, which the range tests below
		' catch: it comes out around 240, not around 0
		esw = esw - 27
	ELSE
		IF klsc <> 7 THEN RETURN
		esw = 228
		esw = esw + escp
		esw = esw + escp
		IF kcx > esw THEN RETURN
		esw = esw - kcx
	END IF

	' --- WALKING ON. The whole foot of the flight boards, as it always did,
	'     and it is always the bottom step: he is on the floor, and the
	'     bottom step is the only one his feet can reach from there.
	IF klst = ST_RUN THEN
		IF esw > 86 THEN RETURN
		IF esw < 60 THEN RETURN
		esy0 = 4
		esy0 = esy0 + escp
	ELSE
		' --- COMING DOWN ON IT. The arc is allowed to finish and the
		'     staircase is simply what he lands on. This used to share
		'     the walking path, which boarded the instant he entered
		'     the foot's 24 px zone: that zeroed his height in mid-air
		'     and dropped him at the bottom of the flight, so a jump
		'     aimed at the steps was cut short every time.
		'
		'     Only the bottom three steps are in reach of a 14 px apex
		'     at 4 px a step, so this is a ladder, not a divide.
		IF esw > 76 THEN RETURN
		IF esw < 52 THEN RETURN
		esy0 = 12
		IF esw > 59 THEN esy0 = 8
		IF esw > 67 THEN esy0 = 4
		esy0 = esy0 + escp
		' HE MUST BE COMING DOWN, and at or below the step. Requiring him
		' to CROSS that step's exact height in a single frame was too
		' strict: he covers 4 px a frame, so a given step is under him
		' for about two frames of the descent, and if his height did not
		' happen to pass through that step's own height in those two he
		' sailed clean over the staircase and landed on the floor beyond
		' it. Coming-down-and-at-or-below is the rule a floor uses.
		'
		' Only the bottom three steps are in range (above), so "below a
		' step" can never mean one the arc could not have reached.
		IF kjh > kjp THEN RETURN
		IF kjh > esy0 THEN RETURN
	END IF
	GOSUB esc_ride
	RETURN

	' ------------------------------------------------------ getting on one
	' ONE ROUTINE FOR BOTH WAYS ON, because everything follows from esy0 --
	' the height above this floor of the step being boarded. The staircase is
	' a straight line, so a step 4 px higher is 8 px further along it:
	'
	'     west  klx = 99 - 2*esy0        east  klx = 140 + 2*esy0
	'
	' Walking on, the feet are still on the floor and have to climb onto that
	' step, so the ride starts at 0 and `eson` runs the catch-up. Jumping on,
	' he is already at the step's height, so it starts there with none.
esc_ride:
	kjh = 0
	esy = esy0
	eson = 0
	' WALKING ON is exactly "klst is still ST_RUN", tested before it is
	' changed below -- no separate flag needed.
	IF klst = ST_RUN THEN
		esy = 0
		eson = esy0 + esy0
	END IF
	klst = ST_ESC
	esxr = esd			' esd is already 0 west / 1 east
	klx = 99 - esy0 - esy0
	IF esd = 1 THEN klx = 140 + esy0 + esy0
	RETURN

	' ------------------------------------------------------------- elevator
	' The car serves floors 1-3 and NOT the roof. If it reached the roof it
	' would replace the whole climb and the three traverses would mean
	' nothing. It is the only way DOWN, and the only shortcut.
try_elev:
	IF klsc <> 3 THEN RETURN
	IF klv > 2 THEN RETURN
	IF elst <> 0 THEN RETURN		' doors only open when stopped
	IF klv <> elvl THEN RETURN
	kcx = klx + 8
	IF kcx < ELXL THEN RETURN
	IF kcx > ELXR THEN RETURN
	klst = ST_ELEV
	kjh = 0
	klx = 120
	sfe = 1
	RETURN

	' ======================================================================
	' THE ELEVATOR CAR
	' ======================================================================
upd_elev:
	elt = elt - fdv
	IF elt > 200 THEN elt = 0		' 8-bit underflow guard
	' THE DOORS: 0 shut, 1 part-open, 2 open. Redrawn ONLY when the phase
	' actually changes, so the whole animation costs four short VDP bursts
	' per stop instead of one every frame.
	elph = 0
	IF elst = 0 THEN
		elph = 2
		IF elt < ELDOOR THEN elph = 1
		IF elt > ELOPEN THEN elph = 1
	END IF
	IF elph <> eldp THEN
		eldp = elph
		IF klsc = 3 THEN GOSUB draw_car
	END IF
	IF elt > 0 THEN RETURN
	IF elst = 0 THEN
		elst = 1
		elt = ELMOVE
		IF klsc = 3 THEN GOSUB draw_car
		RETURN
	END IF
	' arrived
	IF eldn = 0 THEN
		elvl = elvl + 1
		IF elvl >= 2 THEN eldn = 1
	ELSE
		elvl = elvl - 1
		IF elvl = 0 THEN eldn = 0
	END IF
	elst = 0
	elt = ELWAIT
	IF klsc = 3 THEN GOSUB draw_car
	RETURN

	' THE VICTROLA, AS CHARACTERS. It never moves, so a sprite spent a
	' scan-line slot on something that can be painted once when the screen is
	' drawn -- and at one 16x16 sprite it could only ever be one colour and
	' one size. Four cells is twice the area for no sprite at all.
	'
	' It stands ON the slab, so it fills the band's rows 2 and 3; row 4 is
	' the floor bar itself and draw_prizes uses row 3 for a collectible,
	' which is why the two never share a screen (genstore keeps prizes off
	' the screens that carry hazards).
	'
	' rdall = 1 paints all four cells, 0 repaints only the top-right one --
	' the pulse. Same address arithmetic either way, so the two cannot drift.
	' A BEAM TOP HANGS OUT OF THE FLOOR ABOVE, and the beam it belongs to has
	' just been taken away. `beam_tops` stamps SLABP -- the floor bar with the
	' support carried up through its lower three pixel rows -- into the slab
	' row above every pillar, and it runs BEFORE the radios and prizes are
	' placed. Clearing a pillar's own cells therefore left three grey pixels
	' dangling from the ceiling with nothing under them.
	'
	' TESTED, NOT ASSUMED: only SLABP is put back to SLAB. The row above the
	' top shopping floor is the ROOF DECK, a different character altogether,
	' and writing a floor bar over it would punch a hole in the roof.
	' A SHELF RUN IS FIVE CELLS WIDE and a radio covers two, so one standing
	' on a counter punched a hole through its middle and left the ends either
	' side -- the same incoherence the dangling pillar had, and worse, because
	' a counter reads as one object. The whole unit goes: walk outward along
	' the band's row 2 while the cell is still a shelf top, clearing it and
	' its bottom half together.
	'
	' Bounded at eight steps. The runs are five, so eight is slack rather
	' than a guess -- and an unbounded walk would run off the end of the row
	' if the name table ever held something unexpected.
wipe_shelf:
	wsn = 8
ws_loop:
	IF wsn = 0 THEN RETURN
	wsv = VPEEK(#wsa)
	IF wsv <> CH_SHELFT THEN RETURN
	wsc = CH_WALL
	VPOKE #wsa,wsc
	#wsb = #wsa + 32
	VPOKE #wsb,wsc
	IF wsd = 0 THEN #wsa = #wsa - 1 ELSE #wsa = #wsa + 1
	wsn = wsn - 1
	GOTO ws_loop

	' A PILLAR'S CAP MAY BE CLEARED; AN END WALL'S MAY NOT. beam_one stamps
	' both into the slab row of the band above, but they mean different
	' things. SLABP is the top of a free-standing pillar: a radio or a prize
	' stands in front of the pillar, so leaving its cap up there hangs a grey
	' stub over the fixture and that is what this routine exists to remove.
	' SLABE and ROOFSE are written ONLY at column 0 and column 31 -- read
	' beam_one, they are the two edge cases -- and there they are the
	' BUILDING'S OUTSIDE WALL, carrying its brick bond up through the floor
	' above. Clearing those took the support out from under the storey above
	' at the very edge of the screen, so the second floor visibly rested on
	' nothing.
	'
	' It could only ever show on the ESCALATOR screens, which is exactly how
	' it was reported -- one side, then mirrored on the other. The flight
	' fills the middle of an escalator band, so that screen's radio or prize
	' is pushed right out against the end wall; on every other screen no
	' fixture sits close enough for the two-cell clear at #bca and #bca+1 to
	' reach column 0 or 31.
beam_clear:
	bcv = VPEEK(#bca)
	IF bcv = CH_SLABP THEN
		bcw = CH_SLAB
		VPOKE #bca,bcw
	END IF
	IF bcv = CH_ROOFSP THEN
		bcw = CH_ROOFS
		VPOKE #bca,bcw
	END IF
	RETURN

	' THE SAME DISTINCTION ONE ROW LOWER. A radio or a prize stands in the
	' bottom half of a band, so the two cells above it have to be cleared or
	' the pillar it covers keeps its top half hanging in the air. That clear
	' used to be an unconditional green VPOKE, which is only correct when the
	' cell really is a pillar: at column 0 and 31 it is the OUTSIDE WALL, and
	' on the roof it is the SKYLINE. Painting green over either punched a
	' two-row hole through the building -- and because the band is blitted and
	' then corrected within the same pass, you could watch it happen at round
	' start: the wall went up and was taken straight back down again.
	'
	' So it tests for the thing it is allowed to remove rather than trusting
	' the position. COUNTR is a pillar or a counter; anything else stays.
wall_clear:
	wcv = VPEEK(#wca)
	IF wcv = CH_COUNTR THEN
		wcw = CH_WALL
		VPOKE #wca,wcw
	END IF
	RETURN

	' ONE BAND'S RADIOS. rbn is the band and its two obstacle slots are
	' rbn*2 and rbn*2+1, so the caller does not have to know the mapping.
radio_band:
	rlo = rbn + rbn
	rhi = rlo + 1
	FOR ri = rlo TO rhi
		IF obk(ri) = OB_RADIO THEN
			#rva = 6144
			#rva = #rva + #bdst(rbn)
			#rva = #rva + 64		' band row 2
			#rva = #rva + obc(ri)
			' BOTH top cells carry the pulse now -- the sound comes
			' out of the crown, so it is symmetric about it.
			rch = CH_RADTL0
			IF rphs = 1 THEN rch = CH_RADTL1
			VPOKE #rva,rch
			#rvb = #rva + 1
			rch = CH_RADTR0
			IF rphs = 1 THEN rch = CH_RADTR1
			VPOKE #rvb,rch
			IF rdall = 1 THEN
				' THE FIXTURE IT STANDS IN FRONT OF GOES AWAY.
				' A pillar fills its band's four air rows and the
				' radio covers only the lower two, so a radio
				' placed on one left the pillar's top half
				' hanging in the air above it -- a grey stub with
				' nothing under it. Shelves are covered outright
				' by the radio's own two rows, so only the rows
				' ABOVE need clearing.
				#wca = #rva - 64
				GOSUB wall_clear
				#wca = #wca + 1
				GOSUB wall_clear
				#wca = #rva - 32
				GOSUB wall_clear
				#wca = #wca + 1
				GOSUB wall_clear
				' and the beam top hanging above it
				#bca = #rva - 96
				GOSUB beam_clear
				#bca = #bca + 1
				GOSUB beam_clear
				' and the rest of the counter it stands in
				#wsa = #rva - 1
				wsd = 0
				GOSUB wipe_shelf
				#wsa = #rva + 2
				wsd = 1
				GOSUB wipe_shelf
				#rvb = #rva + 32
				rch = CH_RADBL
				VPOKE #rvb,rch
				#rvb = #rvb + 1
				rch = CH_RADBR
				VPOKE #rvb,rch
			END IF
		END IF
	NEXT ri
	RETURN

	' THE SOUND PULSE. Driven off fphs, which already ticks once per pass and
	' is immune to the frame delta, and repainted only when the phase BIT
	' actually flips -- otherwise this would be eight VDP writes every pass
	' for a picture that had not changed (CLAUDE.md 3A: bursts past a few
	' dozen a frame are silently dropped).
	' EVERY BAND'S RADIOS -- what the pulse needs, since it repaints the top
	' cells wherever they are.
radio_draw:
	FOR rbn = 0 TO 3
		GOSUB radio_band
	NEXT rbn
	RETURN

	' THE BAND'S HAZARDS COME OFF THE FLOOR AFTER A HIT (do_hit). It lives
	' beside radio_band because the radio half of it is the awkward half.
haz_gone:
	rgi = klv + klv
	GOSUB haz_off
	rgi = rgi + 1
	GOSUB haz_off
	RETURN

	' ONE SLOT OFF THE FLOOR. Zeroing the kind is the whole job for a SPRITE
	' hazard -- a cart, a ball, a biplane -- because the draw pass reads the
	' kind and simply stops putting it anywhere.
	'
	' A RADIO ALSO HAS TO BE UNDRAWN, which is the only reason this is not one
	' line. It is four CHARACTERS in the name table, so zeroing the kind alone
	' stops it hurting you while leaving it sitting there in plain sight.
	' CH_WALL goes back, exactly as it does for a collected prize -- and since
	' the counter or pillar it stood in front of was already cleared to make
	' room for it (radio_band), there is nothing underneath to restore.
haz_off:
	IF obk(rgi) = 0 THEN RETURN
	IF obk(rgi) = OB_RADIO THEN
		w2c = obc(rgi)
		GOSUB wipe_2x2
	END IF
	obk(rgi) = 0
	RETURN

	' ERASING A 2x2 PROP, AND THERE ARE TWO OF THEM: a collected prize and a
	' radio taken off the floor by a hit. Same four cells, same band row, same
	' CH_WALL going back -- the only thing that differs is the column, so the
	' column is the argument and the band is always the player's own.
	'
	' 6208 IS 6144 + 64 FOLDED, which is legal because it is a bare literal
	' rather than a CONST (CLAUDE.md 3A: a CONST over 255 is truncated to its
	' low byte, a literal is not).
wipe_2x2:
	#w2a = 6208				' name table, band row 2
	#w2a = #w2a + #bdst(klv)
	#w2a = #w2a + w2c
	w2w = CH_WALL
	VPOKE #w2a,w2w
	#w2b = #w2a + 1
	VPOKE #w2b,w2w
	#w2b = #w2a + 32
	VPOKE #w2b,w2w
	#w2b = #w2b + 1
	VPOKE #w2b,w2w
	RETURN

radio_tick:
	rnow = 0
	IF fphs AND 8 THEN rnow = 1
	IF rnow <> rphs THEN
		rphs = rnow
		rdall = 0
		GOSUB radio_draw
	END IF
	RETURN

	' ======================================================================
	' OBSTACLES
	' ======================================================================
upd_obst:
	' ONE ACCUMULATOR PER KIND, NOT PER SLOT. Every hazard of a kind moves at
	' that kind's speed, so three calls a pass serve all eight slots.
	'
	' Per-slot would have meant up to eight calls of O(fdv) work every pass --
	' the positive feedback loop CLAUDE.md 3A warns about, where a slow pass is
	' made slower by the very code meant to take the loop rate out of the
	' game's behaviour. It also saves the eight bytes an obacc() would cost,
	' and ColecoVision RAM is the tighter budget.
	pacc = oacb
	psp64 = obsp
	GOSUB pace_step
	oacb = pacc
	ospb = pspd
	pacc = oacc
	psp64 = ocsp
	GOSUB pace_step
	oacc = pacc
	ospc = pspd
	pacc = oacp
	psp64 = opsp
	GOSUB pace_step
	oacp = pacc
	ospp = pspd
	' THE BOUNCE PHASE, ON THE SAME CLOCK AS THE JUMP AND AT ITS OLD PERIOD.
	'
	' The jump has always advanced by the frame delta (`kjf = kjf + fdv`) while
	' the bounce advanced once per PASS -- so whether a jump cleared a ball
	' depended on how busy the screen was, and the frame-by-frame property
	' checkball.py proves was exact only at fdv = 1.
	'
	' Stepping the phase by fdv directly would fix the clock and wreck the
	' game: a 32-phase arc would drop from about 1.35 s to 0.55 s, balls
	' bouncing 2.4x faster everywhere. So it gets a fraction of its own --
	' 25/64 of a phase per frame is 23.4 phases a second, against the 23.8 it
	' runs at today. Same bounce, now the same clock as the thing that has to
	' clear it.
	pacc = obac
	psp64 = BOUNCE64
	GOSUB pace_step
	obac = pacc
	obph = pspd
	FOR ui = 0 TO 7
		uk = obk(ui)
		IF uk > 0 THEN
			us = 0
			IF uk = OB_BALL THEN us = ospb
			IF uk = OB_CART THEN us = ospc
			IF uk = OB_PLANE THEN us = ospp
			IF us > 0 THEN
				' THEY WRAP. They do not turn round at the wall.
				' A bouncing obstacle is a pendulum: it has a near
				' end and a far end, and the player learns to stand
				' at the far one and wait. Wrapping makes the floor
				' a STREAM that keeps arriving from the same side,
				' so standing still is never the answer and the
				' player has to keep moving -- which is the whole
				' shape of the original.
				IF obd(ui) = 0 THEN
					IF obx(ui) < us THEN obx(ui) = obx(ui) + 240
					obx(ui) = obx(ui) - us
				ELSE
					obx(ui) = obx(ui) + us
					IF obx(ui) > 240 THEN obx(ui) = obx(ui) - 240
				END IF
			END IF
			' The bounce. obh is the ART bottom above the slab; the
			' hitbox is the middle 4 px of the 8 px art, which is
			' what opens the three-pixel seam in DESIGN.md 5a.
			IF uk = OB_BALL THEN
				' obph, not 1 -- and the wrap SUBTRACTS 32 rather
				' than zeroing, because a clamped catch-up pass can
				' advance the phase by as much as five and zeroing
				' would quietly restart the arc from its foot.
				up = obp(ui) + obph
				IF up > 31 THEN up = up - 32
				obp(ui) = up
				#uaa = #arcb + up
				obh(ui) = PEEK(#uaa)
			END IF
		END IF
	NEXT ui
	RETURN

	' ONE STEP OF A FRACTIONAL SPEED, FOR WHOEVER IS MOVING.
	'
	' `pacc` in and out, `psp64` in (sixty-fourths of a pixel per FRAME),
	' `pspd` out (whole pixels this pass). CVBasic has no locals, so the caller
	' stages its own accumulator in and takes it back out; that costs four
	' statements against the fourteen this used to be, written out per actor.
	'
	' Harry had the only copy. Kelly, the hazards and the bounce phase all need
	' the same thing -- everything the round clock judges has to advance by
	' ELAPSED FRAMES, or the loop rate becomes a difficulty dial and where the
	' player stands decides the outcome (DESIGN.md 0f-ter).
	'
	' TWO DRAINS CAP THE STEP AT 2 PER FRAME whatever psp64 says (CLAUDE.md
	' 3A: N drains cap the speed at N, and the surplus leaks into a byte that
	' wraps). Every caller is under that: Kelly 102/64 = 1.6, the fastest
	' hazard 76/64 = 1.2, Harry 57/64 = 0.9, the bounce phase 25/64 = 0.4.
	'
	' FIVE FRAMES, AND THREE WAS TOO FEW. At 2 px a frame five frames is 10 px,
	' and to skip a position window an actor must start outside it on one side
	' and land outside on the other, which needs 12. Three was the original bug
	' in miniature: the lift screen runs at almost exactly 20 passes a second,
	' which IS fdv = 3, so every hitch there lost a frame. The clamp exists for
	' a genuine stall and at five it only fires for one.
pace_step:
	pfd = fdv
	IF pfd > 5 THEN pfd = 5
	pspd = 0
	FOR pfi = 1 TO pfd
		pacc = pacc + psp64
		IF pacc > 63 THEN
			pspd = pspd + 1
			pacc = pacc - 64
		END IF
		IF pacc > 63 THEN
			pspd = pspd + 1
			pacc = pacc - 64
		END IF
	NEXT pfi
	RETURN

	' ======================================================================
	' HARRY -- two comparisons, no search
	' ======================================================================
	' Get to this floor's up-point, take it, repeat; on the roof, run east
	' for the edge. He never goes down and he never reconsiders.
move_harry:
	IF hst = 1 THEN
		' HE RIDES IT TOO, and on the steps rather than beside them. He used
		' to hold still for the whole flight and then appear at the top,
		' which read as him teleporting up a floor -- the same fault Kelly
		' had. Same fixed 2-across-per-1-up PER PASS as the player, clocked
		' by the animation for the same reason (see move_kelly).
		IF hsy < hson THEN hsy = hsy + 1
		hsy = hsy + 1
		IF hesd = 0 THEN hx = hx - 2 ELSE hx = hx + 2
		IF hsy >= ESCRISE THEN
			hlv = hlv + 1
			hst = 0
			IF hesd = 0 THEN hx = ESCHX ELSE hx = ESCHXE
		END IF
		RETURN
	END IF

	' GOING DOWN, WHICH KELLY CANNOT DO. An escalator only ever carries you
	' up, so the flight whose TOP lands on this floor is a one-way exit that
	' belongs to the crook alone -- he steps on at the head and rides it the
	' wrong way. Same fixed step per pass as the climb, and the same reason:
	' the steps are the clock (0f).
	IF hst = 2 THEN
		IF hsy < hson THEN hsy = hsy + 1
		hsy = hsy + 1
		IF hesd = 0 THEN hx = hx + 2 ELSE hx = hx - 2
		IF hsy >= ESCRISE THEN
			hlv = hlv - 1
			hst = 0
			hsy = 0
			IF hesd = 0 THEN hx = ESCFX ELSE hx = ESCFXE
			' AND HE KEEPS GOING. A flight's foot IS its boarding
			' point, so landing there put him back on the step he had
			' just ridden down -- next pass he stepped on and climbed
			' straight into the Kop who had chased him off it. The
			' escape was a loop with a free catch at the end.
			'
			' So he runs for the far end and will not board anything
			' while he does. Away from the flight is also away from
			' the Kop, who is still up on the floor above and has to
			' come down after him. It is a FLAG, not a count -- see
			' the two things that clear it, both of which the player
			' can see happen.
			hrun = 1
			hrund = 1
			IF hesd = 1 THEN hrund = 0
		END IF
		RETURN
	END IF

	' WHERE IS HE GOING? Up, always. He runs for this floor's up-point and
	' takes it, floor after floor, and nothing deflects him -- he is not
	' patrolling, he is escaping, and every frame he is not climbing is a
	' frame he is losing.
	IF hlv = 3 THEN
		htsc = 7
		htx = 224			' inside XWALL: a target he cannot reach
		' is a crook who can never escape
	ELSE
		#hea = #stes + hlv
		hesd = PEEK(#hea)
		IF hesd = 0 THEN
			htsc = 0
			htx = ESCFX
		ELSE
			htsc = 7
			htx = ESCFXE
		END IF
	END IF

	' THE ONE THING THAT CHANGES HIS MIND is Kelly arriving on his floor.
	' Then he stops heading for the escalator and simply runs AWAY, because
	' a thief who keeps walking calmly toward a fixed point while a policeman
	' closes on him is not a thief, he is a train.
	'
	' It is still two comparisons, and it costs nothing: the flee direction is
	' just "opposite whichever side Kelly is on", compared screen-first then
	' pixel-within-screen, because there is no world coordinate to subtract.
	'
	' The consequences are all good ones and none of them are special-cased.
	' Fleeing may carry him TOWARD his escalator, in which case he climbs and
	' escapes the floor -- fine, he earned it. It may carry him away from it
	' into a corner, in which case he is trapped against the end wall -- also
	' fine, that is the catch. And it never makes him stop trying, so it does
	' not read as broken AI the way a fleeing ENEMY would
	' (`difficulty-dial-must-not-invert-goal`): running is what this character
	' is FOR.
	hmv = 0
	IF hlv = klv THEN
		hkw = 0
		IF klsc < hsc THEN hkw = 1
		IF klsc > hsc THEN hkw = 2
		IF klsc = hsc THEN
			' A DEAD BAND, or he dithers. Comparing raw positions makes
			' him flip direction every time Kelly crosses his centre by
			' one pixel, which on screen is not fleeing, it is a
			' vibration -- and it reads as the crook being broken
			' rather than as being cornered. 16 px of slack means he
			' commits to a direction and keeps it.
			IF klx + 16 < hx THEN hkw = 1
			IF klx > hx + 16 THEN hkw = 2
		END IF
		IF hkw > 0 THEN
			IF hkw = 1 THEN hfd = 1 ELSE hfd = 2
		END IF
		IF hfd = 0 THEN hfd = 2
		hmv = hfd
	ELSE
		hfd = 0
		IF hsc < htsc THEN hmv = 1
		IF hsc > htsc THEN hmv = 2
		IF hsc = htsc THEN
			IF hx < htx THEN hmv = 1
			IF hx > htx THEN hmv = 2
		END IF
	END IF

	' THE SIXTEENTH-PIXEL ACCUMULATOR. hx is one unsigned byte per screen
	' (2), so there is nowhere to keep a fraction -- the fraction lives here
	' and is spent as whole pixels. THREE IFs, not a loop and not a divide:
	' `%` and `/` both compile to a real TMS9900 DIV (CLAUDE.md 3A) and this
	' runs every pass.
	'
	' THE NUMBER OF DRAINS IS A CEILING ON THE SPEED, AND THAT IS THE WHOLE
	' POINT OF THIS COMMENT. Each IF can spend one whole pixel, so N drains
	' cap hspd at N px per pass NO MATTER WHAT hsp64 SAYS. The invariant is:
	'
	'     hacc is under 16 on entry, and hsp64 is at most 48,
	'     so hacc is under 64 here and three drains always suffice.
	'
	' KEEP hsp64 <= 48. This was quarter-pixels with TWO drains and the same
	' invariant written the same way -- "hsp4 is at most 8, so it can never
	' need a third" -- and it was correct until somebody set hsp4 = 9 without
	' re-reading it. The crook then ran at a flat 2.0 px/pass while every
	' comment, the design table and assets/checkchase.py all said 2.25, and
	' the surplus quarter leaked into hacc and wrapped the byte every 256
	' passes. Nothing failed; he simply arrived two thirds of a screen short
	' of his own escape. checkchase.py now counts these IFs and refuses a
	' speed the drains cannot deliver.
	'
	' 7, NOT 6, AND THE REASON IS MEASURED. Tracked off the reference video
	' (DESIGN.md 4a), the 2600's Kelly covers 0.40 screen widths a second and
	' its Harry 0.193 -- a ratio of 2.07. At hsp4 = 6 ours was 2.67, and the
	' crook visibly strolled. 7 brings it to 2.29. 8 would match the original
	' exactly and cannot be used: Kelly's route here is 1.95x Harry's, so a
	' speed ratio of 2.0 leaves the on-foot chase 0.2 s of slack, which is no
	' chase at all. checkchase.py holds the line.
	' STILL RUNNING FROM THE STAIRS -- and this has to come BEFORE the move,
	' not after it. It sat below the two `IF hmv` blocks, where all it could
	' still reach was the animation counter: he faced the right way, played
	' the run cycle and did not travel a pixel. He stood at the foot of the
	' flight looking busy.
	'
	' TWO THINGS END THE RUN, AND BOTH ARE VISIBLE ON SCREEN.
	'
	' THE KOP ARRIVING ON THIS FLOOR OUTRANKS IT. This used to override the
	' flee as well as the climb, so for the whole of the run he held one
	' heading no matter where Kelly was -- and ran straight into him without
	' appearing to notice he was there. The flee above has already worked out
	' which way is away; clearing the run simply lets it stand.
	'
	' AND REACHING THE END WALL ENDS IT. It used to be a count of passes,
	' which expired somewhere in the middle of a floor and turned him round
	' for no reason the player could see. Running until the wall means every
	' change of direction has something on screen behind it.
	IF hrun > 0 THEN
		IF hlv = klv THEN
			hrun = 0
		ELSE
			hmv = 1
			IF hrund = 0 THEN hmv = 2
			IF hrund = 1 THEN
				IF hsc = 7 THEN
					IF hx >= XWALL THEN hrun = 0
				END IF
			ELSE
				IF hsc = 0 THEN
					IF hx <= XWALW THEN hrun = 0
				END IF
			END IF
		END IF
	END IF

	' HE WALKS BY REAL TIME, NOT BY LOOP PASS -- one accumulate-and-drain per
	' ELAPSED FRAME rather than per pass. Everything that moves here used to be
	' per pass while the CLOCK is paced by the frame delta, so a busy screen
	' slowed Harry in real seconds and the clock did not slow with him: the
	' same uninterrupted escape finished with nine timer units in hand from a
	' light screen and none at all from the lift screen, decided by where the
	' player happened to be standing. Now he covers the same ground per second
	' wherever anybody is (DESIGN.md 0f-ter).
	'
	' A LOOP, NOT A MULTIPLY. `*` compiles to a real TMS9900 MPY, and reading a
	' 16-bit variable straight after one returns the product's HIGH word
	' (CLAUDE.md 3A). fdv is 1..3 here, so this is at most three adds.
	'
	' SIXTY-FOURTHS, AND ONLY TWO DRAINS -- both fall out of accumulating per
	' FRAME instead of per pass. He covers under a pixel a frame, so two drains
	' are ample where the per-pass version needed three; and the finer unit is
	' what makes the speed tunable at all. In sixteenths one step was about six
	' SECONDS of his route, so nothing landed near the buzzer; in sixty-fourths
	' it is about one and a half. Keep hsp64 <= 128: hacc is under 64 on entry,
	' so 64 + 128 stays inside a byte and two drains always suffice.
	'
	' AND THE STEP IS CLAMPED TO THREE FRAMES' WORTH, WHICH IS NOT A DETAIL.
	' Two tests sample his position once a pass and neither interpolates:
	'
	'   ARRIVAL   `hdx < 6` around the escalator or the roof door -- an ELEVEN
	'             pixel window. A step over 10 px can jump clean across it and
	'             he never arrives at all.
	'   THE CATCH `hdd < CATCHR` is 12, a 23-wide band, and Kelly closes 4 of
	'             it himself -- so Harry over ~18 px could pass through the Kop
	'             between two passes without either sample being inside it.
	'
	' The clamp and the drains live in pace_step now, with the reasoning; the
	' numbers above are what sized them. Measured: TIME 02 on the lift screen
	' against TIME 04 on a light one when the clamp was 3, and 00 against 09
	' before any of this.
	'
	' The ESCALATOR RIDE is deliberately untouched: it returns above this,
	' clocked one step per pass to stay locked to the moving staircase. A rider
	' advanced by the frame delta either drifts off the treads or makes the
	' steps run backwards (CLAUDE.md 3A, DESIGN.md 0f). It is about 3% of his
	' journey.
	'
	' `hanim` still advances by hspd and is still an ODOMETER -- pixels
	' travelled, not time -- so the run cycle stays locked to the ground at any
	' rate. A 9 px step moves it exactly one pose of its 8 px beat.
	pacc = hacc
	psp64 = hsp64
	GOSUB pace_step
	hacc = pacc
	hspd = pspd

	IF hmv = 1 THEN
		hdir = 1
		IF hsc = 7 THEN
			' the east wall stops him too -- he does not slide off the
			' edge of the world any more than the player does
			IF hx < XWALL THEN
				hroom = XWALL - hx
				IF hroom < hspd THEN hx = XWALL ELSE hx = hx + hspd
			END IF
		ELSE
			hroom = 255 - hx
			IF hroom < hspd THEN
				hsc = hsc + 1
				hx = 8
			ELSE
				hx = hx + hspd
			END IF
		END IF
	END IF
	IF hmv = 2 THEN
		hdir = 0
		IF hsc = 0 THEN
			IF hx > XWALW THEN
				hroom = hx - XWALW
				IF hroom < hspd THEN hx = XWALW ELSE hx = hx - hspd
			END IF
		ELSE
			IF hx < hspd THEN
				hsc = hsc - 1
				hx = 247
			ELSE
				hx = hx - hspd
			END IF
		END IF
	END IF
	' THE CYCLE ADVANCES BY PIXELS TRAVELLED, NOT BY TIME. This was `+ fdv`,
	' which is a clock -- and Harry's speed is a QUARTER-PIXEL ACCUMULATOR, so
	' hspd is 0 on a third of his frames. On every one of those the legs took
	' another step while the ground did not move, which is precisely what
	' scrubbing your feet looks like. It is the classic foot-slip: the legs
	' and the world running off two different clocks.
	'
	' Advancing by hspd locks the stride to the floor -- he cannot take a step
	' without covering ground, or cover ground without taking one, at any
	' speed, including the frames where the accumulator gives him nothing.
	IF hmv > 0 THEN hanim = hanim + hspd

	' CORNERED, HE DROPS A FLOOR. Running him into an end wall used to be the
	' end of it -- the chase always finished in the same corner, and a crook
	' with nowhere left to go is not much of a chase. The flight coming UP to
	' this floor lands at one of the two ends, and he can ride it back down;
	' Kelly cannot follow, because an escalator only goes up.
	'
	' Only while FLEEING. Left alone he is climbing, and a crook who rode
	' down every stairhead he passed would never reach the roof at all.
	IF hlv > 0 THEN
		IF hlv = klv THEN
			IF hst = 0 THEN
				GOSUB harry_down
			END IF
		END IF
	END IF

	' arrived: board, or go over the edge
	IF hsc = htsc THEN
		hdx = hx - htx
		IF hx < htx THEN hdx = htx - hx
		IF hdx < 6 THEN
			IF hlv = 3 THEN
				escapd = 1
			ELSE
				' not while he is still clearing the stairs --
				' see the note over hrun above. The roof escape
				' is deliberately NOT guarded: that is the round
				' ending, not a boarding.
				IF hrun > 0 THEN RETURN
				' ON THE BOTTOM STEP, not wherever he happened to
				' stop. He walks to within 6 px of the foot, which
				' is not close enough to stand on a tread.
				' ON THE BOTTOM STEP, not wherever he stopped:
				' he walks to within 6 px of the foot, which is
				' not close enough to stand on a tread.
				hst = 1
				hsy = 0
				hson = 8
				hson = hson + escp
				hson = hson + escp
				hx = ESCFX - escp - escp
				IF hesd = 1 THEN hx = ESCFXE + escp + escp
			END IF
		END IF
	END IF
	RETURN

	' Is he standing at the head of the flight that comes UP to his floor?
	' That flight belongs to the floor BELOW, so its side is read one entry
	' back down the table, and 255 there means that floor has none.
harry_down:
	#hda = #stes + hlv
	#hda = #hda - 1
	hdsd = PEEK(#hda)
	IF hdsd > 1 THEN RETURN
	hdsc = 0
	IF hdsd = 1 THEN hdsc = 7
	IF hsc <> hdsc THEN RETURN
	hdtx = ESCHX
	IF hdsd = 1 THEN hdtx = ESCHXE
	IF hx > hdtx THEN hddx = hx - hdtx ELSE hddx = hdtx - hx
	IF hddx > 10 THEN RETURN
	hesd = hdsd
	hst = 2
	hsy = 0
	hson = 8
	hson = hson + escp
	hson = hson + escp
	RETURN

	' ======================================================================
	' COLLISIONS -- pure arithmetic against RAM, no VDP reads
	' ======================================================================
	' Kelly's box is [kfh, kfh + kh) above the slab; an obstacle's is
	' [ohb, oht). The ball's inset hitbox is what makes 8..10 avoidable both
	' ways -- without it there is a height at which the ball can be neither
	' jumped nor ducked, and an unavoidable hazard is not difficulty.
	' ONE HIT PER CONTACT, WITH A REFRACTORY PERIOD.
	'
	' The overlap test is true on every frame the player is touching
	' something, so with no latch at all one clumsy cart charges nine seconds
	' several times over -- and what the player sees is the clock jumping by
	' 27, from which the only available conclusion is that the penalty is
	' broken.
	'
	' A latch that clears on the first non-overlapping frame is still not
	' enough, and the case that breaks it is the BOUNCING BALL: it rises off
	' the player between bounces, which is a genuine loss of contact, so a
	' player standing still under one is taxed on every single bounce while
	' being given no opportunity to do anything about it. Technically two
	' collisions; in play, one situation.
	'
	' So obht() is a countdown, not a flag. A hit sets it to HITREF; it ticks
	' down only while the player is CLEAR, and the same obstacle cannot charge
	' again until it reaches zero. Contact holds the count up, so parking
	' inside something never earns a second penalty either.
coll_obst:
	IF klst = ST_ESC THEN RETURN		' riding is invincible, per the
	IF klst = ST_ELEV THEN RETURN		' manual: "until you step out"
	kfh = kjh
	kh = STANDH
	IF klst = ST_DUCK THEN kh = DUCKH
	ktop = kfh + kh
	kcx = klx + 8

	cb = klv + klv				' two slots per band
	FOR ci = 0 TO 1
		cj = cb + ci
		ck = obk(cj)
		chit = 0
		IF ck > 0 THEN
			ocx = obx(cj) + 8
			IF kcx > ocx THEN cdx = kcx - ocx ELSE cdx = ocx - kcx
			IF cdx < CATCHR THEN
				ohb = 0
				oht = 8
				IF ck = OB_BALL THEN
					ohb = obh(cj) + 2
					oht = ohb + 4
				END IF
				IF ck = OB_PLANE THEN
					' FIVE PIXELS OF DAYLIGHT OVER THE CROUCH,
					' not one. At 12 the plane cleared an 11 px
					' crouch by a single pixel, so a duck that
					' plainly worked still looked like a squeak
					' and a duck a frame late was a hit. 16 is
					' as high as it can go and still catch a
					' 24 px standing Kop, and 14 (the apex) is
					' under it, so it stays unjumpable.
					ohb = 16
					oht = 22
				END IF
				IF kfh < oht THEN
					IF ohb < ktop THEN chit = 1
				END IF
			END IF
		END IF
		IF chit = 1 THEN
			IF obht(cj) = 0 THEN
				IF ck = OB_PLANE THEN
					dead = 1
				ELSE
					GOSUB do_hit
				END IF
				obht(cj) = HITREF
			END IF
		ELSE
			' ticks down only while the player is CLEAR of it
			IF obht(cj) > 0 THEN
				IF obht(cj) > fdv THEN obht(cj) = obht(cj) - fdv ELSE obht(cj) = 0
			END IF
		END IF
	NEXT ci
	RETURN

	' A cart, ball or radio costs NINE SECONDS -- the manual's number, and
	' the reason the clock is the real enemy rather than the obstacles.
do_hit:
	IF tsec > HITPEN THEN tsec = tsec - HITPEN ELSE tsec = 0
	IF tsec = 0 THEN tout = 1
	knock = 20
	' THE FLOOR CLEARS WHEN YOU ARE HIT, and stays clear until you re-enter
	' the screen. Nine seconds is a heavy penalty on a fifty-unit clock, and
	' taking it while still standing among the things that charged it -- with
	' a second hazard 48 px behind the first -- is how one mistake becomes
	' three. Clearing the row makes the penalty a single event you can walk
	' away from.
	'
	' BOTH SLOTS, WHATEVER IS IN THEM. Radios used to be exempt: they are
	' CHARACTERS stamped into the name table rather than sprites, so zeroing
	' the kind would have stopped them colliding while leaving them plainly
	' visible on the shelf, and a fixture that is still there has to still be
	' there. That was a reason to UNDRAW them, not a reason to keep them --
	' and it left the one hazard that cannot leave on its own as the only one
	' the mercy did not cover. haz_off now takes the characters with it.
	'
	' NOTHING RESTORES IT HERE. load_band repopulates the band from the
	' template, and it runs only on a seam crossing or a round start, so
	' "until the screen is re-entered" costs no state and no timer: leave and
	' come back and the hazards are simply placed again.
	GOSUB haz_gone
	' A HIT DOES NOT END A JUMP. This used to force ST_RUN and zero the arc,
	' which dropped him straight down out of mid-air onto whatever he happened
	' to be over -- and since the arc is ballistic and ignores the stick once
	' he is airborne (0l), that read as the game taking the controls away
	' rather than as a hit landing. The penalty is the nine units and the
	' knock flash; where he comes down is still his own arc.
	'
	' A ducking Kop is still stood up, because the crouch is a held pose and
	' there is nothing to interrupt.
	IF klst <> ST_JUMP THEN
		klst = ST_RUN
		kjf = 0
		kjh = 0
	END IF
	sfh = 1
	GOSUB hud_time
	RETURN

	' ------------------------------------------------------- money and cases
coll_prize:
	pk = cok(klv)
	IF pk = 0 THEN RETURN
	kcx = klx + 8
	pcx = coc(klv)
	pcx = pcx + pcx
	pcx = pcx + pcx
	pcx = pcx + pcx				' pcx = column * 8
	pcx = pcx + 4
	IF kcx > pcx THEN pdx = kcx - pcx ELSE pdx = pcx - kcx
	IF pdx > 10 THEN RETURN
	cok(klv) = 0
	' remember it is gone, so it does not come back on the next crossing
	pmk = msk(klsc)
	takn(klv) = takn(klv) OR pmk
	' ALL FOUR CELLS. It erased one, which is what a prize used to be; the
	' other three stayed on screen as three quarters of a money bag that no
	' longer scored anything.
	w2c = coc(klv)
	GOSUB wipe_2x2
	#addv = 5				' 50 points, in units of ten
	GOSUB add_score
	sfp = 1
	RETURN

	' ----------------------------------------------------------- got him
coll_harry:
	IF hlv <> klv THEN RETURN
	IF hsc <> klsc THEN RETURN
	' NO +8 ON EITHER SIDE, AND THAT IS THE FIX RATHER THAN A TIDY-UP. Both
	' centres are the left edge plus eight, so the eight cancels in the
	' difference -- but adding it first OVERFLOWED THE BYTE. Harry walks to
	' x 253 before he crosses a seam, and 253 + 8 wraps to 5, so a Kop
	' standing at the far LEFT of the screen measured five pixels to a crook
	' walking off the far RIGHT and arrested him across the whole store.
	'
	' Nothing warned: both are plain 8-bit variables, the wrap is silent, and
	' the catch it produces looks like a generous hitbox rather than like
	' arithmetic. The obstacle test has the same shape but cannot reach it --
	' obx tops out at 240 and klx at XWALL, so neither sum passes 255.
	IF klx > hx THEN hdd = klx - hx ELSE hdd = hx - klx
	IF hdd < CATCHR THEN caught = 1
	RETURN

	' ======================================================================
	' DRAWING THE ACTORS
	' ======================================================================
draw_actors:
	' RIDING WITH THE DOORS SHUT: HIDE HIM AND DO NOT DRAW HIM AT ALL.
	'
	' This test used to sit AFTER his sprites had been written, so every pass
	' placed him at his old floor and then hid him again. That is not free.
	' CVBasic's SPRITE writes a RAM mirror which the vblank ISR copies to
	' VRAM, so a vblank landing BETWEEN the draw and the hide latches the
	' visible state for a frame -- and draw_actors is long (Kelly, Harry,
	' eight obstacles) while a pass on the lift screen spans two or three
	' frames, so it happened constantly. He flickered at the floor he had
	' just left, which reads as a drawing bug rather than as a journey.
	'
	' Deciding BEFORE drawing costs one test and cannot race the ISR at all:
	' the mirror never holds a position to be caught with.
	IF klst = ST_ELEV THEN
		IF eldp = 0 THEN
			SPRITE 0,SPRHID,0,0,0
			SPRITE 1,SPRHID,0,0,0
			SPRITE 2,SPRHID,0,0,0
			SPRITE 3,SPRHID,0,0,0
			GOTO draw_harry
		END IF
	END IF
	' KELLY FLASHES WHILE HE IS KNOCKED ABOUT. Hitting an obstacle set a
	' 20-frame `knock` and took nine seconds off the clock, and NOTHING on
	' screen said so -- the time simply went. A flash is the arcade's own
	' idiom for "that hit you", costs one variable, and is readable even
	' when the collision happened off the edge of the player's attention.
	kcol = C_KHAT
	IF knock > 0 THEN
		IF fphs AND 2 THEN kcol = 15
	END IF
	' KELLY IS SPRITES 0, 1 AND 2 and nothing else ever is -- the VDP drops
	' the highest-numbered sprites on an over-full scanline, so the lowest
	' slots are the ones that can never disappear, and the player is the one
	' thing that must never disappear.
	'
	' THE BAND SPRITES SHARE A y ON PURPOSE. Slots 0 and 1 both sit at ky and
	' between them cover rows 0-15; slot 2 sits at ky+16. Boxes 0/1 and box 2
	' never share a scanline, so an actor costs at most TWO boxes on any line
	' -- and the VDP counts boxes, not pixels, so an empty overlap would have
	' cost just as much as a full one. Two actors meeting is four, exactly
	' the per-line limit, which is why obstacles are suppressed on Harry's
	' floor rather than merely being a kindness.
	ky = flry(klv)
	ky = ky - STANDH
	ky = ky - kjh
	IF klst = ST_ESC THEN
		' Standing on a step: esy IS the height of that step above the floor
		' he boarded from, so his feet are exactly on its tread. klv is still
		' the band being LEFT until the ride completes.
		ky = flry(klv)
		ky = ky - STANDH
		ky = ky - esy
	END IF

	' RIDING, HE STANDS ON THE STEP. The lip is two pixels proud of the shop
	' floor, so a rider whose feet stayed at floor level would be standing
	' through it. Lifting him is what turns boarding into stepping UP into
	' the car.
	'
	' BY ELRIDE, NOT ELSTEP -- three pixels, not the two the doorway grew.
	' See the constants: the extra one is the VDP's sprite placement, not a
	' fudge, and using the drawn step height directly left him a pixel short
	' of being in the car.
	IF klst = ST_ELEV THEN ky = ky - ELRIDE

	IF klst = ST_DUCK THEN
		' 8 px, one sprite, sitting on the floor. The top half is HIDDEN
		' rather than left where it was -- a forgotten slot keeps drawing
		' its last contents, so Kelly would duck and leave his head behind.
		kdy = flry(klv)
		kdy = kdy - DUCKH
		' HE KEEPS HIS BRIM. Three bands, not two: the flat black brim is
		' the one feature that reads as Kelly at this size, and drawing the
		' crouch as one blue mass threw it away. See the note in genart.py
		' for why a third box is affordable here.
		kp = P_KDHAT
		kf = P_KDFACE
		kb = P_KDBODY
		IF kldir = 0 THEN
			kp = kp + P_KFACING
			kf = kf + P_KFACING
			kb = kb + P_KFACING
		END IF
		SPRITE 0,kdy,klx,kp,kcol
		SPRITE 1,kdy,klx,kf,C_SKIN
		SPRITE 2,kdy,klx,kb,C_KELLY
		SPRITE 3,SPRHID,0,0,0
	ELSE
		' FOUR RUN FRAMES FROM TWO BITS of the animation counter, and no
		' divide -- `/` compiles to a real TMS9900 DIV (CLAUDE.md 3A) and
		' this is per-frame code. Two adjacent bits give 0,4,8,12.
		'
		' KELLY USES BITS 2 AND 3 AND HARRY USES 3 AND 4, because a stride
		' has to cover about a stride's worth of ground or the figure
		' skates. Kelly runs 4 px a frame, so four frames a pose is 16 px;
		' Harry runs 1.75, so eight frames a pose is 14. Matching the two
		' rates to the two speeds is what keeps both looking like running.
		kq = P_KLEG1
		' BITS 3 AND 4, NOT 2 AND 3 -- A POSE EVERY 8 PIXELS, which is
		' Harry's beat (hanim AND 8 / AND 16) and now means the same thing,
		' because both counters hold pixels travelled. On the old 4-count
		' beat an odometer would have flipped his legs every single pass at
		' 4 px a pass, which is a blur rather than a run. checkanim reads
		' these bits out of the source, and fails if two bands of one figure
		' run on different ones -- so the body below moves with them.
		IF kanim AND 8 THEN kq = kq + 4
		IF kanim AND 16 THEN kq = kq + 8
		' IN THE AIR HE HOLDS A POSE. Cycling the legs through a jump reads
		' as running on nothing; the reference holds one stride for the
		' whole arc.
		IF klst = ST_JUMP THEN kq = P_KLEG1
		' The leading arm lifts on the two FULL-STRIDE frames, which are the
		' ones with the low bit clear -- that is the pairing genart.py's
		' preview (assets/previewrun.py) renders, so the two stay in step.
		kp = P_KHAT
		kf = P_KFACE
		kb = P_KBODYB
		IF kanim AND 8 THEN kb = P_KBODY
		IF kldir = 0 THEN
			kp = kp + P_KFACING
			kf = kf + P_KFACING
			kb = kb + P_KFACING
		END IF
		' FOUR BANDS, EACH DRAWN AT ITS OWN y so its 16-row box covers
		' only the rows it uses: hat -13..2, face -10..5, tunic 6..21,
		' trousers 16..31. Splitting the hat off the tunic is what frees
		' the cap rows for Harry's second stripe colour.
		' THE OFFSETS ARE THE BAND BOUNDARIES, and they moved when the
		' figure was redrawn to the reference's proportions: the head is
		' now 42% of his height, so the hat band is rows 0-5, the face 6-9
		' and the tunic 10-15. Each box still covers only its own band --
		' hat -10..5, face -6..9, tunic 10..25 -- which is what keeps Kelly
		' to two boxes on any scanline. genart.py's shift() and these have
		' to agree; assets/checkbands.py reads both and checks they do.
		khy = ky - 10
		SPRITE 0,khy,klx,kp,kcol
		kfy = ky - 5
		SPRITE 1,kfy,klx,kf,C_SKIN
		kby = ky + 11
		SPRITE 2,kby,klx,kb,C_KELLY
		ky2 = ky + 16
		SPRITE 3,ky2,klx,kq,C_KELLY
	END IF

draw_harry:
	' Harry: sprites 3, 4 and 5, banded the same way
	hy = flry(hlv)
	hy = hy - STANDH
	IF hst = 1 THEN
		hy = hy - hsy
	END IF
	IF hst = 2 THEN
		hy = hy + hsy		' going the other way down the same flight
	END IF
	' Same four-frame cycle and the same shared legs as Kelly -- see the note
	' over his, and the constants.
	hq = P_HLEG1
	' BITS 3 AND 4: one pose per 8 px of travel, a 32 px four-beat cycle.
	' `hanim` advances by `hspd`, which is PIXELS MOVED THIS PASS, so a pose
	' is a DISTANCE and not a duration -- it cannot drift with the frame rate
	' or scrub his feet at any speed.
	'
	' HALVING THIS WAS TRIED AND IS WORSE. Bits 4 and 5 put a pose on 16 px
	' and the cycle on 64, which is closer to a real stride for a figure 24 px
	' tall and was rejected on sight. Do not re-derive it from his height; the
	' faster cadence is what the reference reads like at this size.
	IF hanim AND 8 THEN hq = hq + 4
	IF hanim AND 16 THEN hq = hq + 8
	' THE LEG STRIPES AND THE SHOES ARE THE SAME POSE IN BLACK, and they are
	' derived FROM hq rather than reproducing the two IFs. Two copies of the
	' same phase arithmetic is two clocks, and the day one of them changed
	' the shoes would walk half a stride behind the feet.
	hqs = hq - P_HLEG1
	hqs = hqs + P_HLEGS1
	' HIS ARMS SWING, on the same bit of the animation counter that picks the
	' legs -- so the arm that is forward is the one opposite the leading leg,
	' which is what running looks like.
	' THE ARMS SWING ONCE PER FULL LEG CYCLE, ON BIT 16 -- not on bit 8.
	'
	' Bit 8 is one BEAT, and the legs take four of them (bits 8 and 16). So an
	' arm swing keyed to bit 8 completed twice for every one pass of the legs:
	' the top half of him flapping at double the speed of the bottom half.
	' That is the jig. It is not a drawing problem and no amount of redrawing
	' the legs would have touched it.
	'
	' On bit 16 the arms hold through beats 1-2 and swap for 3-4, which is
	' also the right PHASE: beat 1 leads with one leg and beat 3 with the
	' other, so the arm opposite the leading leg is forward in each -- which
	' is what running looks like.
	' THE TORSO RUNS ON THE SAME TWO BITS AS THE LEGS. With four drawn poses
	' the shoulders and arms swing WITH the stride; the old two-frame body had
	' a clock of its own, which is what read as a flap rather than a run.
	hp = P_HBODY
	IF hanim AND 8 THEN hp = hp + 4
	IF hanim AND 16 THEN hp = hp + 8
	hf = P_HFACE
	' THE STRIPES SWING WITH HIM. His bands run shoulder to hem and his arms
	' are those same bands extended sideways, so the stripe drawing changes
	' between frames exactly as the body does -- it is not one shared picture
	' any more (genart.py, over HARRY_STRIPE). Same bit of the counter, so the
	' two can never disagree.
	' Same bit as the body, necessarily -- the stripes ARE the body, drawn in
	' the other colour. Keyed to a different bit they would swing apart from
	' the shirt they belong to.
	' DERIVED FROM hp, not recomputed. The stripe layer IS the body layer in
	' the other colour, so a second copy of the beat arithmetic would be a
	' second clock -- and the day one of them changed, his stripes would swing
	' half a stride behind his shirt. Same reason hqs comes from hq.
	hs = hp - P_HBODY
	hs = hs + P_HSTRIPE
	IF hdir = 0 THEN
		hp = hp + P_HFACING
		hf = hf + P_HFACING
		hs = hs + P_HFACING
		hq = hq + P_HLEGFACING
		hqs = hqs + P_HLEGFACING
	END IF
	' HE IS STRIPED FROM CAP TO HEM. Both stripe colours run the whole upper
	' half, so both boxes span rows 0-15 and neither can be tucked away --
	' affordable only because Kelly's hat moved into a box of its own. His
	' FACE is pushed DOWN instead (hy+3, box 3..18) so it clears the cap
	' rows, where his two stripe boxes plus Kelly's hat and face already
	' make four. Worst line of a meeting: exactly four, nothing dropped.
	' HE RISES A PIXEL ON THE RECOVERY BEATS. A runner is highest at mid-flight
	' and lowest at contact; with the body pinned at a constant y, alternating
	' legs under a motionless torso reads as a dance rather than as travel.
	'
	' One pixel is enough at this size, and it lifts the BODY ONLY -- the legs
	' keep their y, so the planted foot stays on the floor and the figure
	' stretches at the waist instead of hopping. Lifting the legs too would be
	' a jump.
	'
	' Beats 2 and 4 are the recoveries, which is exactly `hanim AND 8` -- the
	' cycle's LOW beat bit. IT MUST MOVE WITH THE BEAT BITS ABOVE IT: on the
	' wrong bit he rises and falls twice per stride, a second clock inside one
	' figure, which is the flapping of DESIGN.md 0j2 in the vertical.
	'
	' Safe because HARRY'S COLLISION HAS NO VERTICAL COMPONENT: he is caught on
	' `same level AND |dx| < CATCHR`. Doing this to Kelly would desynchronise
	' his sprite from the ball and biplane windows in DESIGN.md 5a, which is
	' why it is not done to him.
	' THE WHOLE FIGURE RISES, legs included, rather than the body stretching
	' away from the feet. Two reasons, and the second was not the first plan:
	'
	'   * It is what a run does. Mid-flight BOTH feet are off the ground, so
	'     lifting the legs with the body is the correct pose, not a compromise.
	'   * Lifting the body alone opens a one-pixel gap at the waist, and the
	'     torso's bottom row and the legs' top row do not align across it --
	'     green shows through and he reads as coming apart.
	'
	' It also keeps `hfy = hy - 7` and `hy2 = hy + 16` LITERAL, which is not a
	' cosmetic concern: assets/checkbands.py reads each band's draw offset by
	' parsing those exact expressions. Bobbing a differently-named variable
	' made them unreadable and the gate failed the build -- correctly. A
	' checker that can no longer see what it checks has to fail, not shrug.
	IF hanim AND 8 THEN hy = hy - 1
	IF hsc = klsc THEN
		SPRITE 4,hy,hx,hp,C_HARRY
		' y-7, with the pattern at the BOTTOM of its box. The face occupies
		' figure rows 3-8 either way; what changes is where the BOX reaches,
		' and the VDP counts boxes. Drawn at y+3 it spanned rows 3-18 and put
		' a third Harry box on every torso row -- five on a line with Kelly's
		' two, so the VDP dropped his stripes whenever they were level. Drawn
		' at y-7 the box spans -7..8 and the torso rows carry two boxes.
		hfy = hy - 7
		SPRITE 5,hfy,hx,hf,C_SKIN
		SPRITE 6,hy,hx,hs,C_HSTRIPE
		hy2 = hy + 16
		SPRITE 7,hy2,hx,hq,C_HARRY
		' SLOT 27, AND NOT 8. THE SLOTS ARE ALLOCATED IN BLOCKS: 0-3 Kelly,
		' 4-7 Harry, 8-15 the obstacles, 16-23 their propellers, 24-26 the
		' radar. Slot 8 is the FIRST OBSTACLE, and the obstacle pass runs later
		' in this same routine -- so his leg stripes were written and then
		' overwritten every single frame, and his trousers stayed white with no
		' error anywhere. The free block starts at 27.
		'
		' Being the highest-numbered of his four is also what we want: down on
		' the leg rows he has only these two boxes (the other three are sixteen
		' rows up), so meeting Kelly is two against two, exactly the per-line
		' limit -- and if anything ever does overflow, the VDP keeps the four
		' LOWEST, so what goes is the stripe. He loses his shoes, not his legs.
		SPRITE 27,hy2,hx,hqs,C_HSTRIPE
	ELSE
		SPRITE 4,SPRHID,0,0,0
		SPRITE 5,SPRHID,0,0,0
		SPRITE 6,SPRHID,0,0,0
		SPRITE 7,SPRHID,0,0,0
		SPRITE 27,SPRHID,0,0,0
	END IF

	' Obstacles: slots 8-15, TWO per band. An actor costs two sprite BOXES on
	' any scanline (see the note above), so a line carries at most Kelly 2 +
	' 2 obstacles, or -- on Harry's floor, where obstacles are suppressed --
	' Kelly 2 + Harry 2. Either way four, which is the VDP's limit.
	FOR di = 0 TO 7
		dk = obk(di)
		ds = di + 8			' 0-3 Kelly; 4-7 Harry
		ds8 = ds + 8			' 16-23: propellers, lowest priority
		dbn = 0
		IF di > 1 THEN dbn = 1
		IF di > 3 THEN dbn = 2
		IF di > 5 THEN dbn = 3
		' NO SPRITE HAZARD ON THE FLOOR THE CROOK IS STANDING ON -- but
		' only while he is on THIS SCREEN. Once you are face to face the
		' round is a foot race you can see, and a ball arriving in the
		' middle of it costs nine seconds for reasons that have nothing to
		' do with the chase.
		'
		' THE SCREEN TEST IS WHAT MAKES IT INVISIBLE. Clearing his whole
		' floor regardless of screen meant the cleared band moved with him,
		' so every time he changed storeys one floor's hazards vanished and
		' another's appeared in the same instant -- and with all four bands
		' in view at once that reads as objects hopping between levels. Now
		' it only happens on the screen he is actually on, where the reason
		' for it is standing right there.
		'
		' Radios are unaffected: they are characters, drawn straight into
		' the name table, and a fixture the crook happens to run past is
		' not the thing this rule is about.
		' THE RADIO IS NOT A SPRITE ANY MORE -- it is four characters,
		' stamped by draw_radios after the band blit. Zeroing the local
		' copy hides both its slots; obk() is untouched, so coll_obst
		' still sees it and it still costs nine seconds.
		IF dk = OB_RADIO THEN dk = 0
		IF dk = 0 THEN
			SPRITE ds,SPRHID,0,0,0
			SPRITE ds8,SPRHID,0,0,0
		ELSE
			dy = flry(dbn)
			dy = dy - 16
			dy = dy - obh(di)
			dp = P_CART
			dc = C_CART
			IF dk = OB_BALL THEN dp = P_BALL : dc = C_BALL
			dpr = 0
			IF dk = OB_PLANE THEN
				' THE PROP SPINS, in its own colour and its own
				' sprite. A static arc reads as a decal painted
				' on the nose; two phases alternating between a
				' near-solid disc and broken blades is what makes
				' it a toy that is flying at you. fphs is the
				' existing flash phase -- it ticks once per pass
				' and is already immune to the frame delta.
				IF obd(di) = 0 THEN
					dp = P_PLANEL
					dpr = P_PROPAL
					IF fphs AND 4 THEN dpr = P_PROPBL
				ELSE
					dp = P_PLANE
					dpr = P_PROPA
					IF fphs AND 4 THEN dpr = P_PROPB
				END IF
				dc = C_PLANE
			END IF
			dxx = obx(di)
			SPRITE ds,dy,dxx,dp,dc
			IF dpr > 0 THEN
				SPRITE ds8,dy,dxx,dpr,C_PROP
			ELSE
				SPRITE ds8,SPRHID,0,0,0
			END IF
		END IF
	NEXT di
	RETURN

	' THE PLAYFIELD'S SPRITES ONLY -- 0-23. The radar's three (24-26) belong
	' to the instrument rather than to the screen: blinking them out on every
	' crossing would put a new fault where the old one was, and the radar is
	' the one thing that should be steady while the store changes around it.
hide_play:
	FOR hi = 0 TO 23
		SPRITE hi,SPRHID,0,0,0
	NEXT hi
	' Harry's leg stripes live at 27, outside the 0-23 block, because 8-23
	' belong to the obstacles and their propellers. The loop cannot simply be
	' widened -- 24-26 are the RADAR, which this routine must leave alone.
	SPRITE 27,SPRHID,0,0,0
	RETURN

hide_all:
	GOSUB hide_play
	FOR hi = 24 TO 26
		SPRITE hi,SPRHID,0,0,0
	NEXT hi
	RETURN

	' ======================================================================
	' THE SCANNER
	' ======================================================================
	' Rows 21-23, 16 chars wide, centred: 48 characters whose PATTERNS are
	' poked directly, so a moving dot costs two writes and no name-table
	' traffic. With the flip (DESIGN.md 2a) this is how you know where Harry
	' is at all -- he can be one pixel off-screen and completely invisible.
	'
	' Rows 21-23 all sit in the THIRD screen third, so every scanner pattern
	' is at base 4096 and no third-selection arithmetic is needed.
	'
	' BOTH DOTS ARE WHITE and Kelly's BLINKS. The manual wants Kelly black
	' and Harry white, but this is the TMS9918's two-colours-per-8x1-cell
	' mode: a black dot and a white dot on the same pixel row of the same
	' character cannot both exist. Blinking distinguishes them with one
	' colour, which is what RallyX does with its player dot.
	' THE STEPS MOVE, AND EVERY ESCALATOR ON SCREEN MOVES WITH THEM. A flight
	' is twelve characters -- six per direction, sliced out of a rendered
	' 64x40 bitmap by genart.py -- so rewriting those twelve PATTERNS animates
	' the lot: 96 bytes, no name-table traffic, and the same cost whether one
	' flight is visible or ten. The phases slide the cells ALONG the slope, so
	' the steps travel up the flight rather than drifting sideways.
esc_tick:
	' ONLY SCREENS 0 AND 7 CARRY A FLIGHT, so six screens in eight skip this
	' entirely -- which is what makes rewriting the cells every frame
	' affordable. Nested, not `klsc > 0 AND klsc < 7`: the 9900 backend
	' miscompiles a compare-AND-compare (CLAUDE.md 3A).
	IF klsc > 0 THEN
		IF klsc < 7 THEN RETURN
	END IF
	' ONE PHASE PER PASS, AND NEVER MORE. There are four phases covering an
	' 8 px period, so advancing by the frame delta ALIASES: at fdv 2 the
	' pattern flips between two positions half a period apart and the
	' direction stops being readable, and at fdv 3 the sequence runs 0,3,2,1
	' -- the staircase visibly runs BACKWARDS, carrying its steps down while
	' the rider goes up. That is the wagon-wheel effect, and no amount of
	' phase arithmetic fixes it: a 4-phase cycle can only be stepped by 1.
	'
	' So the ANIMATION is the clock here, and the rider is paced from it --
	' see move_kelly, which advances him by the same fixed 2-and-1 per pass
	' rather than by fdv. Locking the two together is the only way they
	' cannot drift, and it is what "the player moves at the rate the steps
	' carry him" actually means. The cost is that a ride takes 36 passes
	' rather than 36 frames, so it slows down when the loop does -- which is
	' the honest behaviour for a machine that is carrying you.
	escp = escp + 1
	IF escp > 3 THEN escp = 0
	' ONLY THE CELLS THAT MOVE, AND ONLY THIS SCREEN'S. genart.py measures
	' which cells move -- the step cells and the COMPOSITE copies of them
	' that cross a floor -- and groups them WEST then EAST, because only one
	' direction is ever on screen: screen 0 carries a west flight and screen
	' 7 an east one.
	'
	' THIS IS THE ONLY PER-PASS WORK UNIQUE TO THESE TWO SCREENS, and it is
	' `define_char`, which in bitmap mode is LDIRVM3 -- the TRIPLE copy, once
	' per screen third. It therefore costs three times what the character
	' count suggests, which is why these screens run slower than the rest.
	'
	' THE WEST SCREEN USED TO COST HALF AS MUCH AGAIN, because it carries TWO
	' flights: floor 1's crosses into a shop floor and floor 3's into the
	' roof, so it needed both composite sets -- nine characters against the
	' east's six, 216 bytes a pass against 144. It measured 20 passes a
	' second where the east screen managed 24-26. The two sets are
	' PIXEL-IDENTICAL and are never wanted in the same screen THIRD, so they
	' share their characters now and are told apart by the per-third colour
	' table (see esc_deck_col in setup). Six either side.
	'
	' The handrail and the frame sit past the end of both ranges and never
	' move at all.
	IF klsc = 0 THEN
		IF escp = 0 THEN DEFINE CHAR 110,6,esc_phw0
		IF escp = 1 THEN DEFINE CHAR 110,6,esc_phw1
		IF escp = 2 THEN DEFINE CHAR 110,6,esc_phw2
		IF escp = 3 THEN DEFINE CHAR 110,6,esc_phw3
	ELSE
		IF escp = 0 THEN DEFINE CHAR 116,6,esc_phe0
		IF escp = 1 THEN DEFINE CHAR 116,6,esc_phe1
		IF escp = 2 THEN DEFINE CHAR 116,6,esc_phe2
		IF escp = 3 THEN DEFINE CHAR 116,6,esc_phe3
	END IF
	RETURN

scan_canvas:
	' THREE CHAR ROWS, on 21-23, of which the middle sixteen pixel rows
	' carry the instrument and the outer eight are margin -- four above and
	' four below. The canvas has to be three rows because the four levels
	' need four pixel rows each and 16 px does not fit in two; the margin is
	' what is left over, and putting it there rather than at one end is what
	' stops the radar touching the shop floor above and the screen edge
	' below.
	FOR sr = 0 TO 2
		#sva = 6144
		#sva = #sva + 672		' row 21
		IF sr = 1 THEN #sva = #sva + 32
		IF sr = 2 THEN #sva = #sva + 64
		' 208, NOT 160. The store's own characters reached 158 with the
		' scanner starting at 160, which left one code free and no room
		' for a prize worth looking at. The scanner wants 48 contiguous
		' codes and 208..255 is 48 exactly, so it moved to the top and
		' the store got 96..207.
		sc2 = 208
		IF sr = 1 THEN sc2 = 224
		IF sr = 2 THEN sc2 = 240
		' ALL 32 COLUMNS, not just the canvas's 16. The eight cells at each
		' end held the SPACE character, whose colour is black on CYAN --
		' right for the HUD on row 0, wrong here, because it left the radar
		' sitting in a cyan strip. The black margin then stopped at the
		' canvas's own edges and read as a border drawn round a panel
		' rather than as space around an instrument. CH_SCANBK is one blank
		' black cell; the strip is black all the way across now, which is
		' how the original has it.
		FOR sq = 0 TO 31
			sv2 = CH_SCANBK
			IF sq > 7 THEN
				IF sq < 24 THEN sv2 = sc2 + sq - 8
			END IF
			VPOKE #sva,sv2
			#sva = #sva + 1
		NEXT sq
		WAIT
	NEXT sr
	GOSUB scan_wipe
	GOSUB scan_furn
	RETURN

	' ------------------------------------------------- the scanner's furniture
	' Without this the scanner is two dots in a void: you can see THAT Harry is
	' somewhere, but not what he is near, which is the one thing you actually
	' need when he is off-screen. Floor lines say which level, the slashes say
	' where that floor's escalator is, and the bar says where the elevator is --
	' exactly the three things the manual lists.
	'
	' FURNITURE AND DOTS ARE SEGREGATED BY PIXEL ROW ON PURPOSE, and a level
	' band is now FOUR rows, one per colour, because a pixel row carries
	' exactly one colour here:
	'
	'   +0  GREY    escalator head, and the elevator car
	'   +1  GREY    the air of that floor
	'   +2  GREY
	'   +3  YELLOW  the floor line -- and NOTHING else goes here
	'
	' THE FIRST THREE ROWS ARE THE FLOOR'S AIR AND EVERYTHING LIVES IN THEM:
	' the escalator's three-step diagonal, the lift car, and both actors, all
	' three pixels tall. They are grey in the table, and the Kop and the
	' crook recolour their own CHARACTER as they move (scan_mark) -- which is
	' what lets both of them fill the band instead of getting a pixel row
	' each. Eight pixels of this canvas is half a screen of the store, so
	' they are almost never in one character; when they are, they merge.
	'
	' Shrinking from six rows bought eight empty pixel rows, four above the
	' instrument and four below, so it no longer butts against the shop floor
	' above it or the bottom of the screen.
	'
	' The dots are erased by ANDing their bits out, so anything sharing a row
	' with one is rubbed away wherever an actor has passed -- which is why
	' scan_escs and scan_elev redraw every tick rather than once.
scan_furn:
	FOR fl = 0 TO 3
		GOSUB scan_base
		' the floor itself: a full-width line at the bottom of the band
		say = fbase + 3
		FOR fc = 0 TO 15
			sccol = fc
			GOSUB scan_pat
			VPOKE #sda,255
		NEXT fc
		' THE ESCALATOR DIAGONALS USED TO BE DRAWN HERE TOO, and it was dead
		' work: scan_escs runs immediately below and draws the same three rows
		' for the same three floors. Every input is a pure function of fl --
		' scan_base, the side lookup, the masks, scan_pat -- and scan_or1 is an
		' OR, so doing it twice cannot differ from doing it once. Sixteen
		' statements, about 320 bytes, and nine VDP writes a floor that nothing
		' on screen could reflect.
		'
		' It is the shape a routine takes when a feature is split out and the
		' original is left behind -- scan_escs is this block plus the colour
		' write that was added later, and it carried a copy of the explanatory
		' comment as well as the code.
		'
		' A SCREENSHOT COULD NOT HAVE SETTLED IT: the radar is three pixel rows
		' tall and Classic99 clips the bottom of the screen. It was proved by
		' replaying both versions against a model of the pattern table for all
		' eight escalator-side combinations.
		WAIT
	NEXT fl
	GOSUB scan_escs
	RETURN

	' The escalator diagonals, redrawn as a unit. They live on the same pixel
	' rows the moving dots occupy, so every dot erase rubs at them and they
	' have to be put back -- see scan_tick.
scan_escs:
	FOR fl = 0 TO 2
		GOSUB scan_base
		#fea = #stes + fl
		fes = PEEK(#fea)
		' A DIAGONAL, AND IT LEANS THE WAY THE FLIGHT RUNS. The HEAD goes
		' on the upper row and the FOOT on the lower, so a west escalator
		' reads as climbing to the left and an east one to the right --
		' which is what you need when deciding which way to run.
		' THREE STEPS, one per row of the band's air. Two pixels on each
		' of two rows was a lean nobody could read at this size; three
		' rows of two, each two pixels further along, is a diagonal. It
		' stops at band row 2 -- row 3 is the floor line and nothing
		' may touch that.
		IF fes = 0 THEN
			sccol = 0
			fm1 = 192		' x 0-1, head (top row)
			fm2 = 48		' x 2-3
			fm3 = 12		' x 4-5, foot
		ELSE
			sccol = 15
			fm1 = 3			' x 126-127, head
			fm2 = 12		' x 124-125
			fm3 = 48		' x 122-123, foot
		END IF
		say = fbase
		GOSUB scan_pat
		GOSUB scan_or1
		GOSUB scan_escc
		say = fbase + 1
		GOSUB scan_pat
		fm1 = fm2
		GOSUB scan_or1
		GOSUB scan_escc
		say = fbase + 2
		GOSUB scan_pat
		fm1 = fm3
		GOSUB scan_or1
		GOSUB scan_escc
	NEXT fl
	RETURN

	' THE FLIGHT IS BLACK, and it has to be written per character because the
	' colour table only knows rows -- the same reason the two actors carry
	' their own colour (scan_mark).
	'
	' This runs BEFORE the markers every tick, which is the whole ordering
	' the radar needs: the lift car is painted first and the flights next, so
	' a Kop or a crook standing on either of them paints over it. Nothing
	' moves aside to make room -- the pixels are simply ORed together and the
	' last colour written wins, so an actor in the lift shaft shows as an
	' actor rather than shifting anywhere.
scan_escc:
	#sdx = #sda + 8192
	VPOKE #sdx,SC_KOP
	RETURN

	' fbase = the top pixel row of level fl's FOUR px band, without a
	' multiply. Four levels at four rows is 16 of the canvas's 24 pixel
	' rows, and the other eight are deliberately empty -- four above and
	' four below -- so the instrument sits in the black with air around it
	' instead of butting against the shop floor above and the screen edge
	' below. The +4 is that top margin.
scan_base:
	fbase = 3 - fl
	fbase = fbase + fbase
	fbase = fbase + fbase		' (3-fl)*4
	fbase = fbase + 4
	RETURN

scan_or1:
	sva = VPEEK(#sda)
	sva = sva OR fm1
	VPOKE #sda,sva
	RETURN

	' (sccol 0..15, say 0..23) -> pattern address #sda
scan_pat:
	scrow = say / 8
	scpr = say AND 7
	sc3 = 208
	IF scrow = 1 THEN sc3 = 224
	IF scrow = 2 THEN sc3 = 240
	sc3 = sc3 + sccol
	#sda = 4096
	#sda = #sda + sc3 * 8.
	#sda = #sda + scpr
	RETURN

	' Blank the canvas by WRITING zeros rather than copying 384 of them out
	' of ROM. This runs twice a game -- at setup and on a new Krook -- so a
	' loop costs nothing anybody can perceive, and it hands the fixed area
	' back the best part of half a kilobyte, which is the budget that
	' actually binds. Paced in bursts: a few hundred VDP writes in a single
	' frame are silently dropped (CLAUDE.md 3A).
scan_wipe:
	' THIS ADDRESS IS A CHARACTER CODE IN DISGUISE, AND IT WENT STALE.
	' 4096 is the pattern table's BOTTOM THIRD -- rows 16-23, which is
	' band 0 and the radar together -- and the canvas characters begin at
	' genart's SCAN_FIRST, so the base is 4096 + SCAN_FIRST*8. It was
	' written out by hand as 4096 + 160*8 when SCAN_FIRST was 160; art
	' added later moved SCAN_FIRST to 208 and nothing moved this with it,
	' so the wipe zeroed the 48 characters BELOW the canvas and never
	' touched the canvas at all.
	'
	' Two of those forty-eight are STRUCTURE. ENDWALL is the building's
	' outside wall and SLABP is a pillar's cap. Blanking a pattern in ONE
	' THIRD leaves a character that draws correctly everywhere else and
	' falls back to its own background colour here -- so the GROUND FLOOR's
	' outside wall turned into plain green while the identical wall one
	' storey up was perfect, and the ground floor's pillars lost the brick
	' carried up through the bar above them. ENDWALL appears only on
	' screens 0 and 7, which is exactly why it was reported as happening
	' only on the escalator screens, mirrored side to side.
	'
	' The name table was correct the whole time. Probing it said so, four
	' times. It was the GLYPH that was empty, in one third only -- which a
	' probe that copies the character somewhere else to look at it cannot
	' see, because the copy renders from a different third's pattern.
	'
	' renumber.py rewrites this line from genart.SCAN_FIRST, and
	' checkstruct.py fails the build if the two disagree.
	#swa = 5760			' 4096 + SCAN_FIRST*8, the canvas patterns
	FOR swj = 0 TO 5
		FOR swi = 0 TO 63
			VPOKE #swa,0
			#swa = #swa + 1
		NEXT swi
		WAIT
	NEXT swj
	RETURN

	' One actor per tick, at about 10 Hz: erase where it was, draw where it
	' is. Six VDP ops a tick, which is nothing.
scan_tick:
	sct = sct + fdv
	IF sct < 6 THEN RETURN
	sct = 0

	' THE TWO ACTORS ARE SPRITES; EVERYTHING ELSE IS CHARACTERS.
	'
	' That split is what makes the instrument simple. The floor lines, the
	' flights and the lift car do not move relative to the canvas, so they
	' are pixels in the scanner's own characters and cost nothing to keep.
	' The Kop and the crook DO move, and as sprites they need no colour
	' table, no erase and no priority arithmetic -- they draw over the
	' furniture because sprites always do, and nothing shifts to make room.
	'
	' IT ALSO REMOVED THE BLINK. Kelly flashed because a pixel row of this
	' canvas can only carry one colour, so at close range the two markers
	' merged and the blink was the only thing left to tell them apart. Two
	' sprites are two colours wherever they stand.
	'
	' The furniture is drawn ONCE, by scan_furn. It used to be redrawn every
	' tick because erasing a character-based marker ANDed bits out of
	' whatever it was standing on; there is nothing left to rub it away. The
	' car still redraws itself, because the car actually moves.
	' -- the lift car. IT WAS FLICKERING, and the cause was not the drawing
	' but the ERASING: scan_elev cleared its three cells and put them back
	' every tick, whether or not the car had moved, so several times a second
	' there was a window with the pixels off. A sprite has no erase at all --
	' it is placed, and the VDP does the rest -- and slot 26 sits BELOW the
	' two markers, so the Kop and the crook pass over it without either of
	' them having to know the car exists.
	say = 3 - elvl
	say = say + say
	say = say + say				' (3-lv) * 4
	say = say + 4				' the top margin, then band row 0
	sdy = 167
	sdy = sdy + say
	' 118, NOT 120, AND THE TWO HAVE TO BE WORKED OUT THE SAME WAY. A marker
	' is three pixels wide and the car is five, so putting both left edges at
	' the same x leaves their CENTRES two apart -- and an actor standing dead
	' centre in the lift read as standing at its left-hand edge.
	'
	' An actor in the shaft is at store x 120 on screen 3, which is canvas
	' 3*16 + 120/16 = 55, so his three pixels are screen 119-121 and his
	' centre is 120. Five pixels centred on 120 start at 118. The character
	' version had the same two-pixel error (char column 7, bits 248, screen
	' 120-124) and the sprite inherited it.
	SPRITE 26,sdy,118,P_RADCAR,C_RCAR

	' -- the two markers. dotx 0..127 across the store, doty 0..23 down it;
	' the canvas is characters 8-23 of rows 21-23, so screen x is 64 + dotx.
	'
	' ONE DOT, FROM A SCREEN, AN X AND A FLOOR. Kelly and the crook are the
	' same thirteen statements of arithmetic with different inputs, and they
	' were written out twice.
	sdsc = klsc
	sdxp = klx
	sdlv = klv
	GOSUB scan_dot
	SPRITE 24,sdy,sdx,P_RADDOT,C_RKOP
	sdsc = hsc
	sdxp = hx
	sdlv = hlv
	GOSUB scan_dot
	SPRITE 25,sdy,sdx,P_RADDOT,C_RCROOK
	RETURN

	' sdsc/sdxp/sdlv in, sdx/sdy out. The bias and the row meanings that used
	' to be explained twice are explained here once.
	'
	' 167, NOT 168. The VDP puts a sprite's top line at y + 1, so a sprite
	' asked for the canvas's own row lands one pixel low -- which on a
	' three-pixel marker in a three-pixel band means its bottom row sits on the
	' yellow floor line. The character markers this replaced were poked
	' straight into the pattern table and needed no such bias, which is exactly
	' why it was easy to carry the old number across.
scan_dot:
	sax = sdsc
	sax = sax + sax
	sax = sax + sax
	sax = sax + sax
	sax = sax + sax				' screen * 16
	sxf = sdxp / 16
	sax = sax + sxf
	say = 3 - sdlv
	say = say + say
	say = say + say				' (3-lv) * 4
	say = say + 4				' the top margin, then band row 0.
						' Rows 0-2 are that floor's air; row 3
						' is the yellow line and the marker
						' must not touch it.
	sdx = 64
	sdx = sdx + sax
	sdy = 167
	sdy = sdy + say
	RETURN

	' ======================================================================
	' HUD
	' ======================================================================
hud_all:
	' TWO COLUMNS IN FROM THE LEFT. The score line ran hard against the
	' screen edge, which the TI's overscan eats on a real set.
	PRINT AT 2,"SCORE"
	PRINT AT 16,"TIME"
	GOSUB hud_score
	GOSUB hud_time
	GOSUB hud_kops
	RETURN

	' Score is in UNITS OF TEN with a fixed trailing zero, so a 16-bit
	' counter reaches 655,350 -- and the x300 bonus band can pay 15,000 for
	' one capture, which is already past a byte and well on the way to a word.
hud_score:
	#psv = #score
	#psa = 6152
	#psd = 10000
	' BLANK THE LEADING ZEROS. 000050 reads as a six-digit number that happens
	' to be small; 50 reads as a score. Every arcade cabinet this is imitating
	' does the latter.
	'
	' All five digits may be blanked, not four: the fixed trailing zero below
	' is always printed, so a score of nothing still shows a "0" and the field
	' is never empty.
	pszs = 1
	GOSUB prt_digits
	VPOKE #psa,48				' the fixed trailing zero
	RETURN

hud_time:
	#psv = tsec
	#psa = 6165
	#psd = 10
	' THE CLOCK STAYS PADDED. A countdown is a fixed-width field the player
	' glances at -- "05" holds its place where "5" jumps a column, and a
	' number that moves while it falls is harder to read at speed. Only the
	' score is suppressed.
	pszs = 0
	GOSUB prt_digits
	RETURN

	' THE INDICATOR SHOWS SPARES, not total Kops -- CLAUDE.md 7A, and the
	' manual agrees in its own words ("three reserve Kops"). This routine IS
	' called with kops = 0 on the last life, so the subtraction is guarded:
	' a bare kops-1 wraps to 255 and lights every icon exactly when the
	' player has none.
hud_kops:
	spare = 0
	IF kops > 0 THEN spare = kops - 1
	' ONE COLUMN, NOT TWO, AND FIVE CELLS, NOT SIX. The row ends at column
	' 31: six hats from column 27 would run over onto row 1, which is the
	' wrap checklayout.py exists to catch. Five is what fits, so a game set
	' to more than six Kops shows five hats and the rest are implied.
	#pla = 6171
	FOR pli = 0 TO 4
		plv2 = 32
		IF pli < spare THEN plv2 = CH_KOPIC
		VPOKE #pla,plv2
		#pla = #pla + 1
	NEXT pli
	RETURN

	' Repeated subtraction rather than a divide: four steps, cheaper than a
	' DIV on this CPU, and only run when the value actually changes.
prt_digits:
prt_dloop:
	psn = 0
prt_dsub:
	IF #psv < #psd THEN GOTO prt_dout
	#psv = #psv - #psd
	psn = psn + 1
	GOTO prt_dsub
prt_dout:
	psv2 = 48 + psn
	' pszs: 0 = pad, 1 = still blanking leading zeros, 2 = past them. The
	' caller sets 0 or 1 and this walks it to 2 at the first digit that
	' matters, so a zero INSIDE the number (the 0 of 1024) still prints.
	IF pszs = 1 THEN
		IF psn = 0 THEN
			psv2 = 32
		ELSE
			pszs = 2
		END IF
	END IF
	VPOKE #psa,psv2
	#psa = #psa + 1
	IF #psd = 10000 THEN #psd = 1000 : GOTO prt_dloop
	IF #psd = 1000 THEN #psd = 100 : GOTO prt_dloop
	IF #psd = 100 THEN #psd = 10 : GOTO prt_dloop
	IF #psd = 10 THEN #psd = 1 : GOTO prt_dloop
	RETURN

	' #addv (units of ten) into the score, with the bonus Kop check
add_score:
	#score = #score + #addv
	GOSUB hud_score
	IF #score >= #nextk THEN
		#nextk = #nextk + 1000
		IF kops < 4 THEN
			kops = kops + 1
			GOSUB hud_kops
			sfk = 1
		END IF
	END IF
	RETURN

	' ======================================================================
	' THE CLOCK
	' ======================================================================
	' Counted down BY FRAME DELTA, never once per loop pass: a per-pass
	' counter is not a clock, and a warning cue that drifts under load is
	' least reliable exactly when the frame is busiest.
tick_timer:
	IF tfr > fdv THEN
		tfr = tfr - fdv
	ELSE
		tfr = tfr + TICKFR
		tfr = tfr - fdv
		IF tsec = 0 THEN
			tout = 1
			RETURN
		END IF
		tsec = tsec - 1
		GOSUB hud_time
		IF tsec = 0 THEN tout = 1
	END IF
	' falls through to the flash -- no GOTO, so the whole routine stays on
	' one traceable path
	' The flash runs off fphs, its OWN counter. Keying it on the parity of a
	' timer that decrements by a VARIABLE delta would freeze the moment the
	' delta happened to be even -- so the warning would die exactly when the
	' frame is busiest, which is when the player needs it most.
tick_flash:
	IF tsec > 9 THEN
		IF tflon = 0 THEN
			tflon = 1
			PRINT AT 16,"TIME"
			GOSUB hud_time
		END IF
		RETURN
	END IF
	tfl = 0
	IF fphs AND 16 THEN tfl = 1
	IF tfl <> tflon THEN
		tflon = tfl
		' BOTH THE LABEL AND THE NUMBER. Blinking the word alone left the
		' digits sitting there steady, so the thing that was actually
		' running out was the one part of the HUD not asking to be looked
		' at -- and with the beep gone this is the only warning there is.
		'
		' Two writes rather than one seven-character blank across both:
		' the label is columns 16-19 and the number 21-22, and a single
		' string spanning them would overlap what hud_time writes, which
		' is exactly what checklayout.py exists to catch.
		IF tfl = 1 THEN
			PRINT AT 16,"TIME"
			GOSUB hud_time
		ELSE
			PRINT AT 16,"    "
			PRINT AT 21,"  "
		END IF
	END IF
	RETURN

	' ======================================================================
	' OUTCOMES -- all reached by GOTO from the main loop with no GOSUB
	' frames outstanding, and all leaving the same way.
	' ======================================================================
do_catch:
	caught = 0
	' THE SAME BOX THE LOSSES GET. It was one line at row 10 column 11, a
	' different width in a different place from HE GOT AWAY and TIME UP -- so
	' the good outcome and the bad ones did not look like the same kind of
	' announcement, and the odd one out was the one the player earns.
	'
	' Thirteen wide at column 10, blank dark blue above and below: every font
	' character is black on HUD_BG, so a row of spaces is a solid bar and the
	' frame costs two strings and no new characters (see lose_kop).
	PRINT AT 330,"             "
	PRINT AT 362,"  GOT HIM!   "
	PRINT AT 394,"             "
	GOSUB snd_off			' nothing rings on through the count
	' THE CAST STAYS ON SCREEN FOR THE COUNT. Hiding everything first threw
	' away the picture the player had just earned -- Kelly stood over Harry
	' where the catch happened -- and turned the bonus into a separate screen
	' that could have belonged to any round. They stay, the clock empties into
	' the score, and only then does the board clear.
	GOSUB bonus_count
	' A SECOND to read the finished tally, then clear.
	FOR bwi = 1 TO 60
		WAIT
	NEXT bwi
	GOSUB snd_off
	GOSUB hide_all
	krk = krk + 1
	GOSUB start_krook
	GOTO main

	' THE BONUS IS COUNTED OUT, NOT AWARDED. Dropping the whole sum into the
	' score in one frame tells the player a number; ticking the clock down a
	' unit at a time, with the score climbing and a beat under each step,
	' tells them what the number was FOR. It is the pay-off for every second
	' they saved, and every arcade game of this era spends a moment on it.
	'
	' It also costs nothing to get right: the loop already has to run down
	' `tsec`, so the animation IS the calculation, and the repeated-addition
	' note below stops applying -- each step adds one band's worth.
	'
	' x100 for Krooks 1-9, x200 for 10-15, x300 from 16. Two independent
	' sources agree on those bands; the manual's own wording suggests
	' 1-8 / 9-16 / 17+ and DESIGN.md 0 records the disagreement.
	'
	' #bval MUST BE 16-BIT: 300 does not fit in a byte, and a plain variable
	' would silently truncate it to 44 (CLAUDE.md 3A).
bonus_count:
	#bval = 100
	IF krk > 9 THEN #bval = 200
	IF krk > 15 THEN #bval = 300
bn_loop:
	IF tsec = 0 THEN RETURN
	tsec = tsec - 1
	GOSUB hud_time
	#addv = #bval
	GOSUB add_score
	' One tick per unit, with its own note-off. Channel 2, which the effect
	' table uses for the upper voice of a two-note effect, so this cannot
	' cancel a sustained tone on channel 1 (CLAUDE.md 3A: two SOUNDs on one
	' channel back to back just cancel the first).
	SOUND 2,300,13
	FOR bwi = 1 TO 3
		WAIT
	NEXT bwi
	SOUND 2,0,0
	FOR bwi = 1 TO 2
		WAIT
	NEXT bwi
	GOTO bn_loop

	' `calc_bonus` USED TO LIVE HERE and computed the whole sum by repeated
	' addition, to dodge two hazards at once: `tsec * bmul` is an 8-bit
	' product (a 50-unit capture in the x300 band pays 15,000, six times past
	' a byte), and multiplying properly lands on the MPY/r0 hazard where a
	' 16-bit variable read straight after being multiplied returns the
	' product's high word. Counting the bonus out a unit at a time (above)
	' removes the multiply entirely rather than working around it -- the loop
	' the player watches IS the arithmetic.
	'
	' It also fixed the last-tick case for free: `bn_loop` tests `tsec = 0`
	' on entry, where the old `FOR bi = 1 TO tsec` would have run its body
	' once and paid a full multiplier for no time at all (CLAUDE.md 3A).

do_escape:
	escapd = 0
	rsn = 0
	GOTO lose_kop

	' Two ways to lose a Kop here, and the message has to be read BEFORE the
	' flags are cleared -- clearing first made the biplane test dead code and
	' every biplane death say TIME UP.
do_death:
	rsn = 2
	IF dead = 1 THEN rsn = 1
	tout = 0
	dead = 0
lose_kop:
	GOSUB hide_all
	' THE MESSAGE BOX, ON THE GAME SCREEN AND NOT INSTEAD OF IT.
	'
	' It used to CLS before GAME OVER, so the last thing the player saw was
	' the store being deleted and then two words on an empty field -- which
	' reads as the program ending rather than as the game ending. The store
	' stays; the message sits in the middle of it.
	'
	' THE BOX IS THE FONT'S OWN BACKGROUND. Every font character is black on
	' HUD_BG (dark blue), so a row of SPACES is a solid dark blue bar. A blank
	' row above and below the text is a frame for the price of two strings and
	' no new characters, and it reads against the store because nothing else on
	' the playfield is that colour.
	'
	' THIRTEEN WIDE, WHICH IS THE LONGEST MESSAGE PLUS ONE EITHER SIDE.
	' HE GOT AWAY and THE BIPLANE are both eleven. Every string below is padded
	' to exactly thirteen so the box has straight edges, and column 10 puts it
	' at columns 10-22 -- centre 16, the screen's.
	'
	' THE REASON IS ALWAYS ON THE SAME ROW, and that is what lets one layout
	' serve both cases. Losing a life draws three rows around it; losing the
	' last one draws two more ON TOP, so GAME OVER appears above the reason
	' rather than replacing it. Printing the reason at a different row for each
	' case would need `PRINT AT` with a variable, and every other PRINT in this
	' program uses a constant.
	PRINT AT 330,"             "
	IF rsn = 0 THEN PRINT AT 362," HE GOT AWAY "
	IF rsn = 1 THEN PRINT AT 362," THE BIPLANE "
	IF rsn = 2 THEN PRINT AT 362,"  TIME UP!   "
	PRINT AT 394,"             "
	' The reason is read during THIS beat, before anything else happens. It
	' used to be printed ahead of the pause and the pause is what makes it
	' readable, so the box has to be drawn first and the Kop taken away after.
	GOSUB pause_beat
	IF kops > 0 THEN kops = kops - 1
	GOSUB hud_kops
	IF kops = 0 THEN
		PRINT AT 266,"             "
		PRINT AT 298,"  GAME OVER  "
		GOSUB pause_beat
		GOSUB pause_beat
		' 8-3-8 IS FORGOTTEN WHEN THE GAME ENDS. krk0 and kops0 are
		' globals, so a starting Krook or Kop count typed on the setup
		' screen otherwise applied to every game after it -- including one
		' started by somebody who never saw the screen and had no way to
		' know why they began on level 12 with two Kops. Zeroing them lets
		' new_game's own defaults take over; typing 8-3-8 again sets them
		' again, which is the only place they should ever come from.
		krk0 = 0
		kops0 = 0
		GOTO boot
	END IF
	GOSUB start_krook
	GOTO main

	' Silence every channel FIRST. SOUND latches, and the per-channel decay
	' counters are not ticked inside this loop -- a tone still sounding when
	' the pause starts would hang for its whole duration, which is the classic
	' CVBasic sticky-audio failure.
	' EVERY CHANNEL OFF, AND THE DECAY COUNTERS WITH THEM. The counters are
	' ticked by the main loop, so anything still sounding when the loop stops
	' -- for a capture, a death, the bonus count -- sustains for as long as
	' whatever replaced the loop takes. That is where the long beep over the
	' bonus tally came from: not the tally's own note, which turns itself off
	' after every unit, but a footstep or a hit that was still ringing when
	' Harry was caught.
snd_off:
	SOUND 0,0,0
	SOUND 1,0,0
	SOUND 2,0,0
	sot = 0
	sht = 0
	spt = 0
	swt = 0
	' AND THE EFFECTS THAT HAVE NOT HAPPENED YET. A set sf* flag is a sound
	' waiting for the next pass of the main loop -- and between a capture and
	' the next Krook the main loop does not run, so anything latched during
	' the round (a hit as Harry was caught, the bonus Kop the tally just
	' awarded) survived the silence and fired on the first pass of the NEW
	' round. Silencing the channels does not help: the flag plays a fresh
	' note afterwards, with a fresh decay counter, which is why it came out
	' as one long tone over the start of a level that had earned nothing.
	sfj = 0
	sfh = 0
	sfp = 0
	sfe = 0
	sfk = 0
	sfw = 0
	RETURN

pause_beat:
	GOSUB snd_off
	FOR pbi = 0 TO 90
		WAIT
	NEXT pbi
	RETURN

	' ======================================================================
	' SOUND
	' ======================================================================
	' Every effect gets an explicit note-off. SOUND latches -- with no
	' `SOUND ch,f,0` the last tone sustains for ever. And the second argument
	' is a 10-BIT DIVISOR, max 1023: SMALLER IS HIGHER, so a rising sweep is
	' written as a falling number and anything over 1023 is silently masked
	' to an unrelated pitch.
sfx_tick:
	IF sfj = 1 THEN
		sfj = 0
		swf = 0
		swt = 8
	END IF
	IF sfh = 1 THEN
		sfh = 0
		SOUND 1,900,13
		sht = 20
	END IF
	' A PRIZE IS AN ARPEGGIO -- testsounds PICKUP C. C5, E5, G5, then a fade
	' on the top note: it RISES, which is what makes it read as a reward
	' rather than as an event, and it ARRIVES, because a major triad resolves
	' where an arbitrary rise just stops.
	'
	' It was two notes struck together on two channels and held. That needed
	' both channels for one sound, said nothing in particular, and had no
	' shape at all -- a chord is a texture, and this wants to be a phrase.
	'
	' NOT THE MEASURED ONE, ON PURPOSE. The 2600 tops its pickup out at
	' 2543 Hz, and a square wave there is a shriek; TIA's softer timbre
	' carries it and the SN76489's does not. This peaks at 784 Hz. Copying the
	' recording would have been faithful and unpleasant, and the player earns
	' this sound dozens of times a round.
	IF sfp = 1 THEN
		sfp = 0
		spz = 13
	END IF
	' ONE CHANNEL, WALKED THROUGH BY A COUNTDOWN. sfx_tick runs once a pass at
	' about 42 ms, so thirteen passes is the bench's 550 ms; the note and the
	' volume are chosen from the count rather than stored in a table, which
	' for six phases is smaller than the table would be.
	'
	' Divisors: C5 523 Hz = 214, E5 659 = 170, G5 784 = 143.
	IF spz > 0 THEN
		pzd = 143			' G5, the note it lands and fades on
		pzv = 12
		IF spz > 11 THEN pzd = 214	' C5
		IF spz > 9 THEN IF spz < 12 THEN pzd = 170	' E5
		IF spz < 7 THEN pzv = 10
		IF spz < 5 THEN pzv = 7
		IF spz < 3 THEN pzv = 4
		SOUND 2,pzd,pzv
		spz = spz - 1
		IF spz = 0 THEN SOUND 2,0,0
	END IF
	IF sfe = 1 THEN
		sfe = 0
		SOUND 1,400,10
		sht = 16
	END IF
	IF sfk = 1 THEN
		sfk = 0
		SOUND 2,300,13
		spt = 25
	END IF

	' the jump sweep: divisor falling = pitch rising
	' THE JUMP IS A WARBLE, NOT A SWEEP -- testsounds variant A, measured off
	' the 2600 at about 415 Hz alternating with 188 for roughly 280 ms.
	'
	' It used to be a rising sweep, 500 down to 120 in steps of 40. That was
	' invented rather than measured, and it had the wrong SHAPE: a sweep reads
	' as something departing, which is a fine idea and is not what the original
	' does. Eight ticks alternating is four cycles of warble, which is what the
	' recording shows.
	'
	' 270 is 415 Hz and 595 is 188 Hz (divisor = 3579545 / (32 * f), so a
	' SMALLER divisor is a HIGHER note -- the pair reads backwards from how it
	' is written).
	IF swt > 0 THEN
		swt = swt - 1
		swf = 1 - swf
		#swp = 270
		IF swf = 1 THEN #swp = 595
		SOUND 0,#swp,12
		IF swt = 0 THEN SOUND 0,0,0
	END IF

	' THE LOW-TIME WARNING IS SILENT. There was a beep a second under ten, and
	' it was the wrong instrument for the job: the last ten seconds are the
	' busiest part of a round, so a repeating tone arrives exactly when the
	' player most needs to hear the hazards, and it fought the prize arpeggio
	' for channel 2 as well. The flash says the same thing and says it in the
	' place the player is already looking.

	' FOOTSTEPS ARE NOISE, AND ON THE NOISE CHANNEL -- testsounds variant A.
	'
	' They were two alternating TONES on channel 0, which is neither what the
	' original does nor a good use of a channel: the recording says a footstep
	' is a short burst of white noise, and channel 3 was sitting unused while
	' the footsteps and the jump sweep shared channel 0 and had to take turns.
	'
	' TESTSOUNDS RUN D: a SHORT tick at the measured RATE.
	'
	' The two dials are independent and both were tried at the bench. The
	' 2600 plays a 64 ms burst every 165 ms -- six a second -- and variant A
	' copies both. Ten a second was tried on the way here and reads as
	' hurrying rather than running. What D changes is not the cadence but the
	' TICK: two frames rather than four, and a notch louder to carry at half
	' the length. Same six a second, less of it.
	'
	' EIGHT A SECOND, AND THE ACCUMULATOR NOW CARRIES ITS REMAINDER.
	'
	' sfw counted pixels and the trigger did `sfw = 0`, THROWING AWAY whatever
	' was past the threshold. kspd is about four pixels a pass, so a threshold
	' of 17 did not fire at 17 -- it fired at the first multiple past it, about
	' 20, and every rate this was ever set to came out slower than the number
	' said: the "six a second" was 5.2 and the "ten" that read as hurrying was
	' really 8.7. Subtracting the threshold instead keeps the fraction, so the
	' rate is what it claims to be at any walking speed.
	'
	' 104 px/s over 15 px is 6.9 a second -- between the 8.0 that read as
	' slightly hurried and the 6.1 that read as trudging. The dial is this one
	' constant and the subtraction below, which must stay threshold + 1 or the
	' carry is wrong.
	'
	' SOT = 2 IS THE SHORTEST TICK THERE IS, and 1 is SILENCE. The decay block
	' below runs LATER IN THE SAME sfx_tick, so a count of 1 is decremented to
	' zero on the pass that set it and the note-off fires before the sound has
	' lasted any time at all. 2 survives to the next pass, which is one pass of
	' sound -- about 42 ms against the bench's 33, as close as a per-pass timer
	' gets, and the reason the bench and the game cannot sound identical.
	'
	' Register 4 is white noise at the fastest rate.
	'
	' VOLUME 9, WHICH IS UNDER EVERYTHING ELSE ON PURPOSE. The hit, the prize
	' and the jump are 12 and 13, and they happen ONCE; footsteps play for the
	' whole round. At 13 they were level with the events they are supposed to
	' sit beneath, so the effects that carry information had nothing to stand
	' out from. The tone version was 7 for the same reason -- noise does read
	' quieter than a tone at the same number, which is why this is 9 and not
	' back to 7.
	IF sfw > 14 THEN
		sfw = sfw - 15
		' STILL SILENT DURING THE JUMP, but now that is a CHOICE rather than
		' a channel conflict -- he is off the ground, so there is nothing to
		' make a footstep with.
		IF swt = 0 THEN
			SOUND 3,4,9
			sot = 2
		END IF
	END IF

	' per-channel decay. Ticked after EVERY frame, including the ones inside
	' animation pauses, or a tone hangs.
	IF sot > 0 THEN
		sot = sot - 1
		IF sot = 0 THEN SOUND 3,0,0
	END IF
	IF sht > 0 THEN
		sht = sht - 1
		IF sht = 0 THEN SOUND 1,0,0
	END IF
	IF spt > 0 THEN
		spt = spt - 1
		IF spt = 0 THEN SOUND 2,0,0
	END IF
	RETURN

	' EVERYTHING BELOW THIS LINE IS ASSEMBLED INTO BANK 1, so the INCLUDE order
	' is load-bearing and nothing but data may follow it.
	'
	' THE FONT IS NOW IN THE BANK TOO, and it used to be deliberately outside:
	' keeping one readable thing in bank 0 means a bank-selection mistake shows
	' as "text survives, art does not" rather than a uniformly blank screen,
	' which is a genuinely useful thing to have when a bank goes wrong.
	'
	' It was given up for 472 bytes, because the fixed area had 342 left and
	' that diagnostic is worth less than the ability to keep building. Two
	' things make it a fair trade rather than a straight loss:
	'
	'   * `BANK SELECT 1` already runs BEFORE `DEFINE CHAR 32,59,font_bits`
	'     (see setup), so nothing about the read order had to change. If that
	'     ever stops being true the font goes blank at boot, immediately and
	'     unmistakably -- a loud failure, not a subtle one.
	'   * The alternative on the table was banking the 29 PRINT AT literals,
	'     which recovers LESS (about 360 bytes net after the reader routine)
	'     and would blind assets/checklayout.py, whose whole method is parsing
	'     `PRINT AT n,"literal"` to catch a string running past column 31 or
	'     a HUD poke landing inside a label. Trading a diagnostic for bytes is
	'     one thing; trading a build gate for fewer bytes is another.
	#if TI994A
	BANK 1
	#endif
	INCLUDE "font.bas"
	INCLUDE "art.bas"
	INCLUDE "store.bas"
