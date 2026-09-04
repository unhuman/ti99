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
	CONST WALKSP = 4		' px per frame
	CONST XWALL = 232		' furthest left edge at the store's east wall
	CONST XWALW = 8			' nearest left edge at the west wall
	CONST STANDH = 24		' Kelly standing -- TWO SPRITES tall
	CONST DUCKH = 8			' Kelly ducked
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
	CONST P_KHAT = 0		' Kelly RIGHT: hat, black
	CONST P_KFACE = 4		'              face, skin
	CONST P_KBODY = 8		'              tunic, blue
	CONST P_KLEG1 = 12		'              trousers, blue
	CONST P_KLEG2 = 16
	CONST P_KDHAT = 20		'              ducked: hat + body
	CONST P_KDFACE = 24		'              ducked: face
	CONST P_KLHAT = 28		' Kelly LEFT
	CONST P_KLFACE = 32
	CONST P_KLBODY = 36
	CONST P_KLLEG1 = 40
	CONST P_KLLEG2 = 44
	CONST P_KLDHAT = 48
	CONST P_KLDFACE = 52
	CONST P_HBODY = 56		' Harry RIGHT: cap + body, white
	CONST P_HFACE = 60		'              face, skin
	CONST P_HSTRIPE = 64		'              the stripes, cap to hem
	CONST P_HLEG1 = 68
	CONST P_HLEG2 = 72
	CONST P_HLBODY = 76		' Harry LEFT
	CONST P_HLFACE = 80
	CONST P_HLSTRIPE = 84
	CONST P_HLLEG1 = 88
	CONST P_HLLEG2 = 92
	CONST P_CART = 96
	CONST P_BALL = 100
	CONST P_RADIO = 104
	CONST P_PLANE = 108
	CONST P_PLANEL = 112
	CONST P_PLANE2 = 116		' propeller phase 2, right / left
	CONST P_PLANEL2 = 120

	CONST C_KELLY = 4		' the Kop's blue trousers
	' THE HAT IS BLACK AGAIN, as the reference has it. It went blue because
	' it shared a sprite with the tunic and the elevator shaft was black, so
	' the Kop vanished in the one place the game most wants you to go. Both
	' halves of that are now fixed: the hat has its own sprite, and the shaft
	' is GREY -- the reference's dark green is indistinguishable from the
	' store's medium green on this VDP, so it needed replacing anyway.
	CONST C_KHAT = 1
	CONST C_SKIN = 11		' the one skin band, both actors
	CONST C_HSTRIPE = 1		' Harry's stripes -- the sprite that is
					' allowed to drop when he is level with Kelly
	CONST C_HARRY = 15		' white -- and the white dot on the scanner
	CONST C_CART = 14
	' RED, measured off gameplay video (DESIGN.md 0b) -- it was light yellow,
	' which came from a static screenshot. Red also happens to be the most
	' legible choice on the green store, and this is the obstacle whose right
	' answer changes in mid-air, so it is the one the player most needs to see.
	CONST C_BALL = 8
	CONST C_RADIO = 10
	' THE ONE THING THAT KILLS GETS ITS OWN COLOUR. Everything else in the
	' store costs nine seconds; the biplane costs a Kop, and a player has no
	' way to learn that except by losing one. Red says it before they do.
	' LIGHT GREEN, from gameplay video (DESIGN.md 0b) -- it was light red. The
	' original's plane is DARK green with a light green propeller arc, which a
	' one-colour TMS9918 sprite cannot do; see the note over PLANE_R in
	' genart.py for why a second sprite is not affordable. Light green keeps
	' the hue and keeps the killer visible.
	CONST C_PLANE = 3

	' store chars
	CONST CH_SLAB = 96
	CONST CH_ECAR = 100
	CONST CH_EDOOR = 99
	CONST CH_WALL = 148
	CONST CH_KOPIC = 149
	CONST CH_EDHALF = 154
	CONST CH_SCANBK = 156		' blank black, the strip either side of the radar
	CONST CH_BAG = 151
	' NAMED, because this was the literal 113 and the escalator rework
	' renumbered the character table underneath it. 113 became EXITC, so
	' the second collectible quietly drew an EXIT DOOR in the aisle -- a
	' plausible-looking box, no error, and nothing to connect it to a
	' change made somewhere else entirely.
	CONST CH_CASE = 152

	' the elevator doorway, in pixels and columns
	CONST ELXL = 112
	CONST ELXR = 143
	CONST ELCOL = 14		' first of 4 doorway columns
	CONST ELWAIT = 100		' frames stopped at a floor
	CONST ELMOVE = 45		' frames in transit between floors
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

	CONST TIMEL = 50		' seconds per Krook
	CONST HITPEN = 9		' seconds a cart / ball / radio costs
	CONST HITREF = 45		' frames before the SAME obstacle can charge
					' again. See coll_obst -- clearing the latch
					' on the first non-overlapping frame is not
					' enough, because a bouncing ball leaves
					' contact between bounces.

	' ---------------------------------------------------------------- tables
	DIM flry(4)			' floor surface y, by level
	DIM #bdst(4)			' band name-table offset, by level
	DIM #tsrc(10)			' template source offset, by template id
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
	DIM obs(8)			' speed
	DIM obh(8)			' art-bottom height above the slab
	DIM obp(8)			' bounce phase, balls only
	DIM obht(8)			' hit refractory, per obstacle -- see coll_obst

	DIM cok(4)			' this screen's collectible, per band
	DIM coc(4)			' its column
	DIM takn(4)			' 32 bits: which bands have been cleaned out

	' ---------------------------------------------------------------- state
	' Kelly
	' klv 0..3 (0 = floor 1, 3 = roof), klsc 0..7, klx 0..255
	' Harry the same. NOTHING in this program is a world coordinate.

	GOSUB setup
	GOSUB init_tables

boot:
	GOSUB title_screen
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
setup:
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
	' Without this the font keeps whatever CVBasic left in the colour table,
	' which over a green store made the HUD unreadable.
	GOSUB font_colour
	DEFINE CHAR 96,61,store_pat
	DEFINE COLOR 96,61,store_col
	GOSUB scan_colour

	DEFINE SPRITE 0,14,spr_kelly	' 0..52  four bands x two facings
	DEFINE SPRITE 14,10,spr_harry	' 56..92
	DEFINE SPRITE 24,1,spr_cart	' pattern 96
	DEFINE SPRITE 25,1,spr_ball	' pattern 100
	DEFINE SPRITE 26,1,spr_radio	' pattern 104
	DEFINE SPRITE 27,4,spr_plane	' 108/112 right/left, 116/120 phase 2
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
	' font: write the colour table directly. See font_colour for where >2000
	' and the >800 mirror stride come from.
scan_colour:
	#scb = VARPTR scan_col3(0)
	FOR sci = 0 TO 2
		#sca = 8192
		IF sci = 1 THEN #sca = 10240
		IF sci = 2 THEN #sca = 12288
		#sca = #sca + 1280		' char 160, the canvas
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

font_colour:
	FOR fci = 0 TO 2
		#fca = 8192
		IF fci = 1 THEN #fca = 10240
		IF fci = 2 THEN #fca = 12288
		#fca = #fca + 256		' char 32, the first the font uses
		FOR fcj = 0 TO 7
			FOR fck = 0 TO 58
				VPOKE #fca,23	' BLACK on CYAN
				#fca = #fca + 1
			NEXT fck
			WAIT
		NEXT fcj
	NEXT fci
	RETURN

	' ======================================================================
	' TITLE
	' ======================================================================
title_screen:
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

	PRINT AT 614,"FIRE OR 1 TO START"
	PRINT AT 678,"2026 UNHUMAN AND CLAUDE"

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
	alku = 0
	alkd = 0
	alkn = 0
alock_cal:
	WAIT
	alkn = alkn + 1
	IF cont1.up THEN alku = alku + 1
	IF cont1.down THEN alkd = alkd + 1
	IF alkn < 40 THEN GOTO alock_cal
	vstuck = 0
	IF alku > 35 THEN vstuck = 1
	IF alkd > 35 THEN vstuck = 2
	IF vstuck > 0 THEN PRINT AT 578,"ALPHA LOCK DOWN - IGNORED"

title_wait:
	WAIT
	' 8-3-8 opens the setup screen. cont1.key rather than a cursor: the
	' vertical axis is exactly what ALPHA LOCK poisons, so a menu built on
	' up/down would boot pinned to one entry.
	tk = cont1.key
	IF tk = 8 THEN
		IF t838 = 0 THEN t838 = 1
		IF t838 = 2 THEN t838 = 3
	END IF
	IF tk = 3 THEN
		IF t838 = 1 THEN t838 = 2
	END IF
	IF t838 = 3 THEN t838 = 0 : GOSUB setup838 : GOTO title_screen
	' FIRE **or** 1. On the TI, joystick fire is TAB, which is neither
	' guessable nor forgiving -- Windows treats a stray TAB as a focus change
	' and moves the whole window away. Accepting a plain digit as well costs
	' one line and removes the only way to be stuck on this screen.
	IF cont1.button THEN RETURN
	IF tk = 1 THEN RETURN
	GOTO title_wait

	' ------------------------------------------------------- 838 setup page
setup838:
	CLS
	PRINT AT 68,"SETUP"
	PRINT AT 164,"1 KOPS"
	PRINT AT 228,"2 START KROOK"
	PRINT AT 356,"FIRE WHEN READY"
	PRINT AT 420,"PRESS 1 OR 2 TO CHANGE"
su_loop:
	WAIT
	GOSUB su_draw
	sk = cont1.key
	IF sk = 1 THEN
		IF sur = 0 THEN
			kops0 = kops0 + 1
			IF kops0 > 9 THEN kops0 = 1
			sur = 12
		END IF
	END IF
	IF sk = 2 THEN
		IF sur = 0 THEN
			krk0 = krk0 + 1
			IF krk0 > 20 THEN krk0 = 1
			sur = 12
		END IF
	END IF
	IF sk = 15 THEN sur = 0
	IF sur > 0 THEN sur = sur - 1
	IF cont1.button THEN RETURN
	GOTO su_loop

	' The digits go at a COLUMN CHOSEN NOT TO LAND IN THE LABEL. UFO shipped
	' its difficulty digit into the middle of the word DIFFICULTY, which
	' reads as a typo in the label rather than as a misplaced value --
	' assets/checklayout.py now fails the build on it.
su_draw:
	#sua = 6308
	#sua = #sua + 12
	sud = 48 + kops0
	VPOKE #sua,sud
	#sua = 6372
	#sua = #sua + 18
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
	' Kelly starts at the FIRST-FLOOR EAST ENTRANCE -- the far end of the
	' store from floor 1's escalator, which is what makes the climb to the
	' roof three full traverses rather than two.
	klv = 0
	klsc = 7
	klx = 224
	kldir = 0
	entdir = 1			' he starts at the east entrance, so the
					' first floor's traffic comes at him from
					' the west -- the way he has to go
	klst = ST_RUN
	kjf = 0
	kjh = 0
	kanim = 0

	' HARRY STARTS ON THE PLAYER'S SCREEN, one floor up. The research says
	' "the second-floor elevator door", which is screen 3 -- but the arcade
	' shows you the crook the moment the round begins, and it cannot do that
	' if he is four screens away. On a scrolling display those two facts are
	' compatible; with a flipped view (DESIGN.md 2a) they are not, and being
	' able to SEE what you are chasing wins. He is still on floor 2.
	hlv = 1
	hsc = 7
	hx = 120
	hdir = 1
	hst = 0
	hsy = 0

	elvl = 1			' the car starts where Harry does
	elst = 0
	elt = ELWAIT
	eldn = 0

	tsec = TIMEL
	tfr = 60
	tout = 0
	dead = 0
	caught = 0
	escapd = 0
	knock = 0
	sold = 0
	tflon = 0
	sct = 0
	fphs = 0

	' Which bounce arc this Krook uses. THE APEX IS THE ONLY THING THAT
	' CHANGES: low balls have to be jumped, high ones cannot be jumped at
	' all and have to be ducked, and the arc is capped below standing height
	' so no ball is ever free to run under. See DESIGN.md 5a.
	arcs = 0
	IF krk > 3 THEN arcs = 1
	IF krk > 8 THEN arcs = 2
	#arcb = #stac
	IF arcs = 1 THEN #arcb = #arcb + 32
	IF arcs = 2 THEN #arcb = #arcb + 64

	' Obstacle speed rises with the Krook -- the one dial the manual names.
	obsp = 1
	IF krk > 4 THEN obsp = 2
	IF krk > 9 THEN obsp = 3

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
	hsp4 = 7			' 1.75 px/frame, every Krook
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
draw_screen:
	FOR dlv = 0 TO 3
		dix = lv8(dlv)
		dix = dix + klsc
		#dta = #stix + dix
		dt = PEEK(#dta)
		#dsrc = #tsrc(dt)
		#ddst = #bdst(dlv)
		SCREEN stor_tpl,#dsrc,#ddst,32,5,32
		WAIT			' VDP writes are buffered per frame and a
					' burst past a few dozen is silently
					' dropped -- one band per frame
	NEXT dlv
	GOSUB esc_cap_draw
	GOSUB load_band
	GOSUB draw_prizes
	GOSUB draw_car
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
			' The second one arrives at Krook 2.
			IF ls = 1 THEN
				IF krk < 2 THEN lk = 0
			END IF
			obk(li) = lk
			obs(li) = obsp
			' THEY COME FROM THE FAR SIDE. Kelly walked into this screen
			' from one edge, so the obstacles start at the OTHER edge and
			' run toward him. Crossing a seam then always presents an
			' ONCOMING stream, never a set of backs he has to catch up
			' with -- and it means the direction he is travelling is
			' always the direction the danger comes from.
			'
			' The table's x becomes a stagger from that edge rather than
			' an absolute position, and the slot index spreads the three
			' of them a screen-third apart so they arrive in sequence
			' instead of as one wall.
			stag = lx AND 63
			IF ls = 1 THEN stag = stag + 64
			IF ls = 2 THEN stag = stag + 128
			IF entdir = 0 THEN
				obd(li) = 0			' from the EAST, heading west
				obx(li) = 240 - stag
			ELSE
				obd(li) = 1			' from the WEST, heading east
				obx(li) = stag
			END IF
			obh(li) = 0
			obp(li) = lx AND 31
			obht(li) = 0
			IF lk = OB_PLANE THEN obh(li) = 10
			IF lk = OB_RADIO THEN obs(li) = 0
ld_skip:
		NEXT ls
	NEXT llv
	RETURN

	' ------------------------------------------------- collectibles as CHARS
	' Not sprites: a band already carries Kelly plus three obstacles, which is
	' exactly four per scanline, and the VDP drops the fifth outright. A prize
	' that vanishes when the floor gets busy would read as a scoring bug.
draw_prizes:
	FOR plv = 0 TO 3
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
			' the air row directly above the slab
			#pva = 6144
			#pva = #pva + #bdst(plv)
			#pva = #pva + 96		' row 3 of the band
			#pva = #pva + pc
			pch = CH_BAG
			IF pk = 2 THEN pch = CH_CASE
			VPOKE #pva,pch
		END IF
	NEXT plv
	RETURN

	' ----------------------------------------------------- the elevator car
	' The car is 4 chars wide and 3 tall -- no sprite here can be that, and
	' it does not need to be, because it only ever occupies whole cells.
draw_car:
	IF klsc <> 3 THEN RETURN
	FOR clv = 0 TO 2
		cch = CH_EDOOR
		IF clv = elvl THEN
			IF eldp = 2 THEN cch = CH_ECAR
			IF eldp = 1 THEN cch = CH_EDHALF
		END IF
		FOR crw = 1 TO 3
			#cva = 6144
			#cva = #cva + #bdst(clv)
			#cva = #cva + 32
			IF crw = 2 THEN #cva = #cva + 32
			IF crw = 3 THEN #cva = #cva + 64
			#cva = #cva + ELCOL
			FOR ccl = 0 TO 3
				VPOKE #cva,cch
				#cva = #cva + 1
			NEXT ccl
		NEXT crw
	NEXT clv
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
	kmv = 0
	IF inl = 1 THEN
		kldir = 0
		kmv = 1
		IF klsc = 0 THEN
			IF klx > XWALW THEN
				kroom = klx - XWALW
				IF kroom < WALKSP THEN klx = XWALW ELSE klx = klx - WALKSP
			END IF
		ELSE
			IF klx < WALKSP THEN
				GOSUB cross_west
			ELSE
				klx = klx - WALKSP
			END IF
		END IF
	END IF
	IF inr = 1 THEN
		kldir = 1
		kmv = 1
		IF klsc = 7 THEN
			IF klx < XWALL THEN
				kroom = XWALL - klx
				IF kroom < WALKSP THEN klx = XWALL ELSE klx = klx + WALKSP
			END IF
		ELSE
			kroom = 255 - klx
			IF kroom < WALKSP THEN
				GOSUB cross_east
			ELSE
				klx = klx + WALKSP
			END IF
		END IF
	END IF
	IF kmv = 1 THEN
		kanim = kanim + 1
		sfw = sfw + 1
	END IF

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
		' HE MUST CROSS IT, not merely be under it. Without the
		' previous height he would board on the way UP -- and standing
		' beneath the high end of a staircase, on the floor below,
		' counts as "below a step" all day long. It is also what keeps
		' him off a step the arc cannot reach: kjp never exceeds the
		' apex, so a step above it is never crossed and no separate
		' reach test is needed.
		IF kjp <= esy0 THEN RETURN
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
	sfe = 1
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

	' ======================================================================
	' OBSTACLES
	' ======================================================================
upd_obst:
	FOR ui = 0 TO 7
		uk = obk(ui)
		IF uk > 0 THEN
			us = obs(ui)
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
				up = obp(ui) + 1
				IF up > 31 THEN up = 0
				obp(ui) = up
				#uaa = #arcb + up
				obh(ui) = PEEK(#uaa)
			END IF
		END IF
	NEXT ui
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

	' THE QUARTER-PIXEL ACCUMULATOR. hx is one unsigned byte per screen (2),
	' so there is nowhere to keep a fraction -- the fraction lives here and
	' is spent as whole pixels. hsp4 = 6 walks 1,2,1,2 (1.5 px/frame); 7
	' walks 1,2,2,2 over four frames (1.75); 8 is a flat 2. Two IFs, not a
	' loop and not a divide: hacc is under 4 on entry and hsp4 is at most 8,
	' so it can never need a third. `%` and `/` both compile to a real
	' TMS9900 DIV (CLAUDE.md 3A) and this runs every frame.
	'
	' 7, NOT 6, AND THE REASON IS MEASURED. Tracked off the reference video
	' (DESIGN.md 4a), the 2600's Kelly covers 0.40 screen widths a second and
	' its Harry 0.193 -- a ratio of 2.07. At hsp4 = 6 ours was 2.67, and the
	' crook visibly strolled. 7 brings it to 2.29. 8 would match the original
	' exactly and cannot be used: Kelly's route here is 1.95x Harry's, so a
	' speed ratio of 2.0 leaves the on-foot chase 0.2 s of slack, which is no
	' chase at all. checkchase.py holds the line.
	hacc = hacc + hsp4
	hspd = 0
	IF hacc > 3 THEN
		hspd = 1
		hacc = hacc - 4
	END IF
	IF hacc > 3 THEN
		hspd = 2
		hacc = hacc - 4
	END IF

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
	IF hmv > 0 THEN hanim = hanim + 1

	' arrived: board, or go over the edge
	IF hsc = htsc THEN
		hdx = hx - htx
		IF hx < htx THEN hdx = htx - hx
		IF hdx < 6 THEN
			IF hlv = 3 THEN
				escapd = 1
			ELSE
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
	' Harry's level carries no obstacles -- see the matching note in the
	' draw loop. Nothing is drawn there, so nothing may hit you there.
	IF klv = hlv THEN RETURN

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
					ohb = 10
					oht = 16
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
	klst = ST_RUN
	kjf = 0
	kjh = 0
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
	#pva = 6144
	#pva = #pva + #bdst(klv)
	#pva = #pva + 96
	#pva = #pva + coc(klv)
	VPOKE #pva,CH_WALL
	#addv = 5				' 50 points, in units of ten
	GOSUB add_score
	sfp = 1
	RETURN

	' ----------------------------------------------------------- got him
coll_harry:
	IF hlv <> klv THEN RETURN
	IF hsc <> klsc THEN RETURN
	kcx = klx + 8
	hcx = hx + 8
	IF kcx > hcx THEN hdd = kcx - hcx ELSE hdd = hcx - kcx
	IF hdd < CATCHR THEN caught = 1
	RETURN

	' ======================================================================
	' DRAWING THE ACTORS
	' ======================================================================
draw_actors:
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

	IF klst = ST_DUCK THEN
		' 8 px, one sprite, sitting on the floor. The top half is HIDDEN
		' rather than left where it was -- a forgotten slot keeps drawing
		' its last contents, so Kelly would duck and leave his head behind.
		kdy = flry(klv)
		kdy = kdy - DUCKH
		' Ducked he is 8 px -- too shallow to band three ways, so the
		' crouch is drawn BLUE with a skin face and no separate hat.
		IF kldir = 1 THEN
			kp = P_KDHAT
			kf = P_KDFACE
		ELSE
			kp = P_KLDHAT
			kf = P_KLDFACE
		END IF
		SPRITE 0,kdy,klx,kp,C_KELLY
		SPRITE 1,kdy,klx,kf,C_SKIN
		SPRITE 2,SPRHID,0,0,0
		SPRITE 3,SPRHID,0,0,0
	ELSE
		IF kldir = 1 THEN
			kp = P_KHAT
			kf = P_KFACE
			kb = P_KBODY
			kq = P_KLEG1
			IF kanim AND 8 THEN kq = P_KLEG2
		ELSE
			kp = P_KLHAT
			kf = P_KLFACE
			kb = P_KLBODY
			kq = P_KLLEG1
			IF kanim AND 8 THEN kq = P_KLLEG2
		END IF
		' FOUR BANDS, EACH DRAWN AT ITS OWN y so its 16-row box covers
		' only the rows it uses: hat -13..2, face -10..5, tunic 6..21,
		' trousers 16..31. Splitting the hat off the tunic is what frees
		' the cap rows for Harry's second stripe colour.
		khy = ky - 13
		SPRITE 0,khy,klx,kp,kcol
		kfy = ky - 10
		SPRITE 1,kfy,klx,kf,C_SKIN
		kby = ky + 6
		SPRITE 2,kby,klx,kb,C_KELLY
		ky2 = ky + 16
		SPRITE 3,ky2,klx,kq,C_KELLY
	END IF

	' WITH THE DOORS SHUT, KELLY IS NOT ON SCREEN. He used to ride the lift
	' in plain sight, standing over the shaft art with the doors closed in
	' front of him, which reads as a drawing bug rather than as a journey.
	IF klst = ST_ELEV THEN
		IF eldp = 0 THEN
			SPRITE 0,SPRHID,0,0,0
			SPRITE 1,SPRHID,0,0,0
			SPRITE 2,SPRHID,0,0,0
			SPRITE 3,SPRHID,0,0,0
		END IF
	END IF

	' Harry: sprites 3, 4 and 5, banded the same way
	hy = flry(hlv)
	hy = hy - STANDH
	IF hst = 1 THEN
		hy = hy - hsy
	END IF
	IF hdir = 1 THEN
		hp = P_HBODY
		hf = P_HFACE
		hs = P_HSTRIPE
		hq = P_HLEG1
		IF hanim AND 8 THEN hq = P_HLEG2
	ELSE
		hp = P_HLBODY
		hf = P_HLFACE
		hs = P_HLSTRIPE
		hq = P_HLLEG1
		IF hanim AND 8 THEN hq = P_HLLEG2
	END IF
	' HE IS STRIPED FROM CAP TO HEM. Both stripe colours run the whole upper
	' half, so both boxes span rows 0-15 and neither can be tucked away --
	' affordable only because Kelly's hat moved into a box of its own. His
	' FACE is pushed DOWN instead (hy+3, box 3..18) so it clears the cap
	' rows, where his two stripe boxes plus Kelly's hat and face already
	' make four. Worst line of a meeting: exactly four, nothing dropped.
	IF hsc = klsc THEN
		SPRITE 4,hy,hx,hp,C_HARRY
		hfy = hy + 3
		SPRITE 5,hfy,hx,hf,C_SKIN
		SPRITE 6,hy,hx,hs,C_HSTRIPE
		hy2 = hy + 16
		SPRITE 7,hy2,hx,hq,C_HARRY
	ELSE
		SPRITE 4,SPRHID,0,0,0
		SPRITE 5,SPRHID,0,0,0
		SPRITE 6,SPRHID,0,0,0
		SPRITE 7,SPRHID,0,0,0
	END IF

	' Obstacles: slots 8-15, TWO per band. An actor costs two sprite BOXES on
	' any scanline (see the note above), so a line carries at most Kelly 2 +
	' 2 obstacles, or -- on Harry's floor, where obstacles are suppressed --
	' Kelly 2 + Harry 2. Either way four, which is the VDP's limit.
	FOR di = 0 TO 7
		dk = obk(di)
		ds = di + 8			' 0-3 Kelly; 4-7 Harry
		dbn = 0
		IF di > 1 THEN dbn = 1
		IF di > 3 THEN dbn = 2
		IF di > 5 THEN dbn = 3
		' THE CROOK'S OWN LEVEL IS ALWAYS CLEAR. Once you are on Harry's
		' floor the round is a foot race you can actually see, and a biplane
		' arriving in the middle of it takes the Kop away for reasons that
		' have nothing to do with the chase. Clearing the band is done HERE,
		' by suppressing the draw, and again in coll_obst by refusing the
		' collision -- both, because a hidden sprite that can still hit you
		' is the worst version of this.
		IF dbn = hlv THEN dk = 0
		IF dk = 0 THEN
			SPRITE ds,SPRHID,0,0,0
		ELSE
			dy = flry(dbn)
			dy = dy - 16
			dy = dy - obh(di)
			dp = P_CART
			dc = C_CART
			IF dk = OB_BALL THEN dp = P_BALL : dc = C_BALL
			IF dk = OB_RADIO THEN dp = P_RADIO : dc = C_RADIO
			IF dk = OB_PLANE THEN
				' THE PROP SPINS. A static arc reads as a decal
				' painted on the nose; two frames alternating
				' between a broken arc and a solid disc is what
				' makes it a toy that is flying at you. fphs is
				' the existing flash phase -- it ticks once per
				' pass and is already immune to the frame delta.
				IF obd(di) = 0 THEN
					dp = P_PLANEL
					IF fphs AND 4 THEN dp = P_PLANEL2
				ELSE
					dp = P_PLANE
					IF fphs AND 4 THEN dp = P_PLANE2
				END IF
				dc = C_PLANE
			END IF
			dxx = obx(di)
			SPRITE ds,dy,dxx,dp,dc
		END IF
	NEXT di
	RETURN

hide_all:
	FOR hi = 0 TO 15
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
	' ONLY THE CELLS THAT MOVE, AND ALL OF THEM. genart.py measures which
	' those are -- the six step cells and the nine COMPOSITE copies of them
	' that cross a floor -- and orders them first so one DEFINE CHAR covers
	' exactly the run. It used to be "everything but the head cap", which was
	' wrong twice over: twelve motionless cells were rewritten sixty times a
	' second, and the composites, being separate character codes, were left
	' out -- so the top steps of every staircase stood still while the rest
	' of the flight climbed past them. The handrail and the frame still sit
	' past the end of the range and still never move.
	IF escp = 0 THEN DEFINE CHAR 101,15,esc_ph0
	IF escp = 1 THEN DEFINE CHAR 101,15,esc_ph1
	IF escp = 2 THEN DEFINE CHAR 101,15,esc_ph2
	IF escp = 3 THEN DEFINE CHAR 101,15,esc_ph3
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
		sc2 = 160
		IF sr = 1 THEN sc2 = 176
		IF sr = 2 THEN sc2 = 192
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
	'   +1  BLACK   Kelly -- and the escalator's FOOT, which the manual
	'               draws black anyway, so the diagonal spans both rows
	'   +2  WHITE   Harry
	'   +3  YELLOW  the floor line
	'
	' Four is the floor: the Kop, the crook, the furniture and the floor
	' lines are four different colours and none of them can share. Shrinking
	' from six bought eight empty pixel rows, four above the instrument and
	' four below, so it no longer butts against the shop floor above it or
	' the bottom of the screen.
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
		' this floor's UP escalator, at whichever end it lives
		IF fl < 3 THEN
			#fea = #stes + fl
			fes = PEEK(#fea)
			' A DIAGONAL, AND IT LEANS THE WAY THE FLIGHT RUNS. The
			' HEAD goes on the upper row and the FOOT on the lower,
			' so a west escalator reads as climbing to the left and
			' an east one to the right -- which is the thing you
			' actually need to know when deciding which way to run.
			IF fes = 0 THEN
				sccol = 0
				fm1 = 192		' x 0-1, head (upper row)
				fm2 = 48		' x 2-3, foot (lower row)
			ELSE
				sccol = 15
				fm1 = 3			' x 126-127, head
				fm2 = 12		' x 124-125, foot
			END IF
			say = fbase
			GOSUB scan_pat
			GOSUB scan_or1
			say = fbase + 1
			GOSUB scan_pat
			fm1 = fm2
			GOSUB scan_or1
		END IF
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
		IF fes = 0 THEN
			sccol = 0
			fm1 = 192		' x 0-1, head (upper row)
			fm2 = 48		' x 2-3, foot (lower row)
		ELSE
			sccol = 15
			fm1 = 3			' x 126-127, head
			fm2 = 12		' x 124-125, foot
		END IF
		say = fbase
		GOSUB scan_pat
		GOSUB scan_or1
		say = fbase + 1
		GOSUB scan_pat
		fm1 = fm2
		GOSUB scan_or1
	NEXT fl
	RETURN

	' THE ELEVATOR MARKER TRACKS THE CAR, which is the whole point of it. It
	' used to be a static bar on all three shopping floors -- that says where
	' the shaft is, which never changes and which the player already knows,
	' and says nothing about the one fact that matters: whether the car is
	' where you are. Erase, move, redraw, exactly like an actor's dot.
	' ONE ROW NOW, AND WIDER FOR IT. The band is four pixel rows and each
	' one carries a single colour, so the car's grey row is the same row the
	' escalator heads use; spending a second row on it would put half the
	' car on Kelly's BLACK row, where it would read as the Kop. Five pixels
	' across at a fixed centre column tells it from a three-pixel actor dot
	' without needing the height.
scan_elev:
	IF selo = 1 THEN
		#sda = #sela
		sdm = 248
		GOSUB scan_clr1
	END IF
	fl = elvl
	GOSUB scan_base
	sccol = 7
	fm1 = 248				' x 56-60
	say = fbase
	GOSUB scan_pat
	#sela = #sda
	GOSUB scan_or1
	selo = 1
	RETURN

	' One row, for the elevator bar. The actors' erase is three rows deep.
scan_clr1:
	svn = NOT sdm
	sva = VPEEK(#sda)
	sva = sva AND svn
	VPOKE #sda,sva
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
	sc3 = 160
	IF scrow = 1 THEN sc3 = 176
	IF scrow = 2 THEN sc3 = 192
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
	#swa = 5376			' 4096 + 160*8, the canvas patterns
	FOR swj = 0 TO 5
		FOR swi = 0 TO 63
			VPOKE #swa,0
			#swa = #swa + 1
		NEXT swi
		WAIT
	NEXT swj
	sold = 0
	RETURN

	' One actor per tick, at about 10 Hz: erase where it was, draw where it
	' is. Six VDP ops a tick, which is nothing.
scan_tick:
	sct = sct + 1
	IF sct < 6 THEN RETURN
	sct = 0

	' -- erase both old dots
	' Erase with the mask each dot was DRAWN with, not whatever sdm happens
	' to hold now. Using the current mask clears a bit the dot never set and
	' leaves the real one lit, so the scanner slowly fills with a trail of
	' stale dots -- which reads as the radar being broken rather than as an
	' off-by-one in a variable.
	IF sold = 1 THEN
		#sda = #skoa
		sdm = skom
		GOSUB scan_clr
		#sda = #shoa
		sdm = shom
		GOSUB scan_clr
	END IF
	' THE DOTS NOW FILL THE BAND, so they sit on top of the furniture rather
	' than beside it, and erasing one takes a bite out of whatever it was
	' standing on. Putting the escalators and the car back every tick is far
	' cheaper than tracking which pixels belonged to whom.
	GOSUB scan_escs
	GOSUB scan_elev

	' -- Kelly. dotx 0..127 across the store, doty 0..23 down it.
	sax = klsc
	sax = sax + sax
	sax = sax + sax
	sax = sax + sax
	sax = sax + sax				' screen * 16
	sxf = klx / 16
	sax = sax + sxf
	say = 3 - klv
	say = say + say
	say = say + say				' (3-lv) * 4
	say = say + 5				' the 4 px top margin, then row +1:
						' KELLY IS ROW +1 AND HARRY IS ROW +2, and
						' they cannot share one: a pixel row carries
						' exactly one colour, and the whole point is
						' that the Kop reads black and the crook
						' white. One row each, three pixels wide.
	GOSUB scan_addr
	#skoa = #sda
	skom = sdm
	' Kelly BLINKS -- that is what tells him from Harry with one colour
	IF fphs AND 16 THEN
		GOSUB scan_set
	END IF

	' -- Harry
	sax = hsc
	sax = sax + sax
	sax = sax + sax
	sax = sax + sax
	sax = sax + sax
	sxf = hx / 16
	sax = sax + sxf
	say = 3 - hlv
	say = say + say
	say = say + say
	say = say + 6				' margin + row +2
	GOSUB scan_addr
	#shoa = #sda
	shom = sdm
	GOSUB scan_set
	sold = 1
	RETURN

	' (sax 0..127, say 0..23) -> pattern address #sda + bit mask sdm
scan_addr:
	sccol = sax / 8
	scrow = say / 8
	scpr = say AND 7
	sc3 = 160
	IF scrow = 1 THEN sc3 = 176
	IF scrow = 2 THEN sc3 = 192
	sc3 = sc3 + sccol
	#sda = 4096
	#sda = #sda + sc3 * 8.
	#sda = #sda + scpr
	' TWO PIXELS WIDE, AND NOTE THE `7 -`. In a pattern byte 0x80 is the
	' LEFTMOST pixel, so an x offset has to be subtracted from 7 rather than
	' used as the shift directly. It was used directly, which MIRRORED every
	' dot inside its own character -- a silent error of up to 7 px that reads
	' as the radar being approximate rather than as being wrong.
	' THREE pixels wide now, not two: the dot lost a row when the furniture
	' took two, so it gets the ink back sideways.
	sbx = sax AND 7
	IF sbx > 5 THEN sbx = 5
	sdm = msk(7 - sbx)
	sdm = sdm + msk(6 - sbx)
	sdm = sdm + msk(5 - sbx)
	RETURN

	' ONE ROW EACH. Kelly is band row +1 and Harry +2, because a pixel row
	' carries exactly one colour and the two have to be told apart by colour
	' -- black Kop, white crook -- rather than by blinking. One pixel on a
	' 128x24 canvas is a speck rather than a marker, so what the dot cannot
	' have in height it takes in width: three pixels across.
scan_set:
	sva = VPEEK(#sda)
	sva = sva OR sdm
	VPOKE #sda,sva
	RETURN

scan_clr:
	svn = NOT sdm
	sva = VPEEK(#sda)
	sva = sva AND svn
	VPOKE #sda,sva
	RETURN

	' ======================================================================
	' HUD
	' ======================================================================
hud_all:
	PRINT AT 0,"SCORE"
	PRINT AT 14,"TIME"
	GOSUB hud_score
	GOSUB hud_time
	GOSUB hud_kops
	RETURN

	' Score is in UNITS OF TEN with a fixed trailing zero, so a 16-bit
	' counter reaches 655,350 -- and the x300 bonus band can pay 15,000 for
	' one capture, which is already past a byte and well on the way to a word.
hud_score:
	#psv = #score
	#psa = 6150
	#psd = 10000
	GOSUB prt_digits
	VPOKE #psa,48				' the fixed trailing zero
	RETURN

hud_time:
	#psv = tsec
	#psa = 6163
	#psd = 10
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
	#pla = 6170
	FOR pli = 0 TO 5
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
		tfr = tfr + 60
		tfr = tfr - fdv
		IF tsec = 0 THEN
			tout = 1
			RETURN
		END IF
		tsec = tsec - 1
		GOSUB hud_time
		IF tsec = 0 THEN tout = 1
		IF tsec < 10 THEN sfl = 1
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
			PRINT AT 14,"TIME"
		END IF
		RETURN
	END IF
	tfl = 0
	IF fphs AND 16 THEN tfl = 1
	IF tfl <> tflon THEN
		tflon = tfl
		IF tfl = 1 THEN PRINT AT 14,"TIME" ELSE PRINT AT 14,"    "
	END IF
	RETURN

	' ======================================================================
	' OUTCOMES -- all reached by GOTO from the main loop with no GOSUB
	' frames outstanding, and all leaving the same way.
	' ======================================================================
do_catch:
	caught = 0
	GOSUB hide_all
	PRINT AT 331,"  GOT HIM!  "
	' Capture bonus: seconds remaining x 100 / 200 / 300 by Krook band.
	' 1-8 / 9-16 / 17+ is the manual's split; a secondary source says
	' 1-9 / 10-15 / 16+ and DESIGN.md 0 records the disagreement.
	bmul = 10				' units of ten -> 100 points
	IF krk > 8 THEN bmul = 20
	IF krk > 16 THEN bmul = 30
	GOSUB calc_bonus
	#addv = #bonus
	GOSUB add_score
	GOSUB pause_beat
	krk = krk + 1
	GOSUB start_krook
	GOTO main

	' REPEATED ADDITION, not a multiply, and deliberately so. Two separate
	' hazards meet on this one line: `tsec * bmul.` is invalid because the `.`
	' suffix marks a 16-bit CONSTANT and both of these are variables, and a
	' plain `tsec * bmul` would be an 8-bit product -- a 50-second capture in
	' the x300 band pays 15,000, which is six times past a byte. Multiplying
	' properly would then land on the MPY/r0 hazard, where a 16-bit var read
	' straight after being multiplied returns the product's HIGH word.
	'
	' At most 50 adds, once per capture. Nothing about this is a hot path.
	'
	' The guard matters: a COMPUTED `FOR 1 TO 0` still runs its body once in
	' CVBasic, so catching Harry on the very last tick would pay a full
	' multiplier instead of nothing.
calc_bonus:
	#bonus = 0
	IF tsec > 0 THEN
		FOR bi = 1 TO tsec
			#bonus = #bonus + bmul
		NEXT bi
	END IF
	RETURN

do_escape:
	escapd = 0
	GOSUB hide_all
	PRINT AT 331," HE GOT AWAY "
	GOTO lose_kop

	' Two ways to lose a Kop here, and the message has to be read BEFORE the
	' flags are cleared -- clearing first made the biplane test dead code and
	' every biplane death say TIME UP.
do_death:
	GOSUB hide_all
	IF dead = 1 THEN
		PRINT AT 331," THE BIPLANE "
	ELSE
		PRINT AT 331,"  TIME UP!   "
	END IF
	tout = 0
	dead = 0
lose_kop:
	GOSUB pause_beat
	IF kops > 0 THEN kops = kops - 1
	GOSUB hud_kops
	IF kops = 0 THEN
		GOSUB hide_all
		CLS
		PRINT AT 331,"   GAME OVER   "
		GOSUB pause_beat
		GOSUB pause_beat
		GOTO boot
	END IF
	GOSUB start_krook
	GOTO main

	' Silence every channel FIRST. SOUND latches, and the per-channel decay
	' counters are not ticked inside this loop -- a tone still sounding when
	' the pause starts would hang for its whole duration, which is the classic
	' CVBasic sticky-audio failure.
pause_beat:
	SOUND 0,0,0
	SOUND 1,0,0
	SOUND 2,0,0
	sot = 0
	sht = 0
	spt = 0
	swt = 0
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
		#swp = 500
		swt = 8
	END IF
	IF sfh = 1 THEN
		sfh = 0
		SOUND 1,900,13
		sht = 20
	END IF
	IF sfp = 1 THEN
		sfp = 0
		SOUND 2,200,13			' two notes need two channels --
		SOUND 1,160,11			' back to back on one just cancels
		spt = 12
		sht = 12
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
	IF swt > 0 THEN
		swt = swt - 1
		#swp = #swp - 40
		IF #swp < 120 THEN #swp = 120
		SOUND 0,#swp,12
		IF swt = 0 THEN SOUND 0,0,0
	END IF

	' one beep per second under ten, off its own phase counter
	IF sfl = 1 THEN
		sfl = 0
		SOUND 2,700,12
		spt = 8
	END IF

	' footsteps
	IF sfw > 6 THEN
		sfw = 0
		IF swt = 0 THEN
			stf = 1 - stf
			#stp = 800
			IF stf = 1 THEN #stp = 860
			SOUND 0,#stp,7
			sot = 2
		END IF
	END IF

	' per-channel decay. Ticked after EVERY frame, including the ones inside
	' animation pauses, or a tone hangs.
	IF sot > 0 THEN
		sot = sot - 1
		IF sot = 0 THEN SOUND 0,0,0
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

	' The font stays in bank 0: it is small, and keeping one readable thing
	' unbanked makes a bank-selection mistake obvious (text survives, art does
	' not) instead of producing a uniformly blank screen.
	INCLUDE "font.bas"

	' EVERYTHING BELOW THIS LINE IS ASSEMBLED INTO BANK 1, so the INCLUDE order
	' is load-bearing and nothing but data may follow it. Putting the directive
	' above font.bas would sweep the font in too.
	#if TI994A
	BANK 1
	#endif
	INCLUDE "art.bas"
	INCLUDE "store.bas"
