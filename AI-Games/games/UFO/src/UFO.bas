	' ==========================================================================
	' UFO! -- CVBasic, dual target TI-99/4A + ColecoVision.
	'
	' Ed Averett's 1981 Odyssey 2 game (Satellite Attack on Videopac). See
	' DESIGN.md; 0 records the research and where sources disagreed.
	'
	' The rules that shaped this file, all from CLAUDE.md 3A, because every one
	' of them fails SILENTLY here:
	'
	'   * A plain variable is 8-BIT. Anything over 255 -- a position in 8.8
	'     fixed point, a screen offset past row 7, a speed -- is a #var.
	'   * A CONST over 255 TRUNCATES. Values above 255 are written as bare
	'     literals at the point of use, never named.
	'   * Every #var comparison is UNSIGNED. Velocities carry a +32768 bias so
	'     no comparison ever crosses zero.
	'   * `<cmp> AND <cmp>` is miscompiled by the 9900 backend. Nested IFs only.
	'   * A sprite at y=208 TERMINATES the sprite list. Hidden sprites go to 209.
	'   * A GOSUB left by GOTO never pops; on ColecoVision's 1 KB that is fatal.
	'   * MPY clobbers r0, so a 16-bit var read straight after being multiplied
	'     returns the product's HIGH word. Nothing here multiplies into an
	'     address for exactly that reason -- see paint_stars.
	' ==========================================================================

	CONST SPRHID = 209		' NOT 208 -- 208 terminates the sprite list

	' THE PLAY BAND, in sprite TOP-LEFT pixels. Rows 0-1 are the HUD, so the
	' band starts at y 16; it ends at 175 so a 16 px sprite still finishes on
	' screen at 191. Height 160.
	'
	' In 8.8 those are 4096, 45056 (one past the end) and 40960. All three are
	' over 255, so they appear as BARE LITERALS at the point of use. As a CONST
	' each would silently truncate to its low byte -- 4096 to 0, 45056 to 0,
	' 40960 to 0 -- and the wrap would simply stop happening.
	CONST BANDT = 16

	' Ship speed, 8.8. 384 = 1.5 px/frame; the diagonal is 272 per axis so a
	' diagonal is not 1.41x faster than a straight line. Both are over 255 and
	' so are literals, assigned into #sspd.
	'
	' Movement is 8-WAY WITH NO INERTIA -- the ship stops dead when you let go.
	' That is the original (bestretrogames, GameFAQs) and it is NOT Asteroids:
	' there is no turn-and-thrust here and adding drift would change the game.

	' -------------------------------------------------------------- variables
	' Ship position, 8.8 fixed point. X needs NO wrap handling at all: 256
	' pixels x 256 = 65536, which overflows 16 bits EXACTLY, so adding the
	' velocity wraps it for free. Y is the only axis that costs anything.
	' #shx  ship x, 8.8
	' #shy  ship y, 8.8
	' #sspd this frame's speed (384 straight, 272 diagonal)
	' sdx   0 none, 1 left, 2 right
	' sdy   0 none, 1 up,   2 down
	' shx8  ship x in whole pixels, for the sprite
	' shy8  ship y in whole pixels

	' #score  the player's score. FAITHFUL 1/3/10 SCORING, so this stays small:
	'         a strong game reads about 60. That is deliberate -- at these
	'         values a chain reaction is legible, and you can watch it count.
	' #hisc   session high score, kept across games until power-off

	' rphs  force-field rotation phase 0-3 (phase 2 uses it; advanced here so
	'       the ring is already shimmering on the title)

	' lpc/lph/lpv/#lpd/#lpl/#lpa -- TEMPORARY loop-rate probe, see lprate.

	#score = 0
	#hisc = 0
	GOSUB setup
	GOTO title_screen

	' ------------------------------------------------------------------ setup
setup:
	SPRITE FLICKER OFF		' all-or-nothing in CVBasic: it would strobe
					' the player too. Instead the player owns
					' sprites 0-2, which the VDP drops LAST.

	' The arcade face, replacing CVBasic's stock 8x8. 59 characters, 32-90,
	' contiguous -- a gap would shift every letter after it.
	DEFINE CHAR 32,59,font_bits
	DEFINE CHAR 128,3,chr_stars

	DEFINE SPRITE 0,1,spr_ship	' pattern 0
	DEFINE SPRITE 1,4,spr_ring	' patterns 4,8,12,16 -- the 4 rotation phases
	DEFINE SPRITE 5,1,spr_gundot	' pattern 20
	DEFINE SPRITE 6,2,spr_sat	' patterns 24,28 -- the PLUS/CROSS pair
	DEFINE SPRITE 8,2,spr_ufo	' patterns 32,36
	DEFINE SPRITE 10,1,spr_laser	' pattern 40
	DEFINE SPRITE 11,1,spr_missile	' pattern 44
	DEFINE SPRITE 12,3,spr_boom	' patterns 48,52,56
	RETURN

	' ---------------------------------------------------------- title screen
title_screen:
	GOSUB hide_all
	CLS
	GOSUB paint_stars

	PRINT AT 98,"U F O !"
	PRINT AT 162,"SATELLITE ATTACK"
	PRINT AT 291,"THE FIELD IS YOUR ARMOUR,"
	PRINT AT 323,"YOUR AMMUNITION AND YOUR"
	PRINT AT 355,"BEST WEAPON. YOU GET ONE."
	PRINT AT 451,"FIRE     LASER"
	PRINT AT 483,"RAM      WITH A FULL FIELD"
	PRINT AT 580,"PRESS FIRE TO START"
#if TI994A
	' THE ALPHA LOCK KEY SHARES A LINE WITH THE JOYSTICK'S VERTICAL AXIS.
	' Latched down it reports an up or down direction that is NEVER released,
	' so the ship flies off on its own and nothing the player does stops it.
	' Every other game here dodges this by not reading the vertical axis at
	' all -- a multidirectional shooter cannot, so it gets said out loud.
	PRINT AT 644,"TI-99: ALPHA LOCK MUST BE UP"
#endif
	PRINT AT 708,"2026 UNHUMAN AND CLAUDE"

	' Wait for the button to be RELEASED first, so the press that ended the
	' last game does not immediately start the next one.
	btnr = 0
title_wait:
	WAIT
	GOSUB spin_ring
	IF cont1.button = 0 THEN btnr = 1
	IF btnr = 0 THEN GOTO title_wait
	IF cont1.button THEN GOTO new_game
	GOTO title_wait

	' -------------------------------------------------------------- new game
new_game:
	CLS
	GOSUB paint_stars
	PRINT AT 0,"SCORE"
	PRINT AT 23,"HI"
	#score = 0
	GOSUB prt_score
	GOSUB prt_hi

	' Centre of the play band: x 120 (so the 16 px sprite straddles 128),
	' y 88. In 8.8 that is 30720 and 22528 -- literals, see the header.
	#shx = 30720
	#shy = 22528
	rphs = 0
	lpc = 0
	#lpl = 0

	' ------------------------------------------------------------- main loop
main:
	WAIT
	GOSUB spin_ring
	GOSUB read_stick
	GOSUB move_ship
	GOSUB draw_ship
	GOSUB lprate
	GOTO main

	' ------------------------------------------------------------ read stick
	' 8-way, no inertia. NOTE the nested IFs: `cont1.left AND cont1.up` would
	' be miscompiled by the 9900 backend (stale-register AND), and it compiles
	' clean, so there would be no warning of any kind.
read_stick:
	sdx = 0
	sdy = 0
	IF cont1.left THEN sdx = 1
	IF cont1.right THEN sdx = 2
	IF cont1.up THEN sdy = 1
	IF cont1.down THEN sdy = 2
	RETURN

	' ------------------------------------------------------------- move ship
move_ship:
	#sspd = 384
	IF sdx <> 0 THEN
		IF sdy <> 0 THEN #sspd = 272
	END IF

	IF sdx = 1 THEN #shx = #shx - #sspd
	IF sdx = 2 THEN #shx = #shx + #sspd
	IF sdy = 1 THEN #shy = #shy - #sspd
	IF sdy = 2 THEN #shy = #shy + #sspd

	' X WRAPS FOR FREE -- 256 px x 256 = 65536 overflows 16 bits exactly, so
	' there is nothing to do here and nothing to pay for.
	'
	' Y is the only axis that costs anything, because the band is 160 px, not
	' 256. Low test FIRST: the largest step is 384, and the band floor in 8.8
	' is 4096, so #shy can never underflow past zero and both compares stay
	' safely unsigned.
	IF #shy < 4096 THEN #shy = #shy + 40960
	IF #shy >= 45056 THEN #shy = #shy - 40960
	RETURN

	' ------------------------------------------------------------- draw ship
	' Three sprites share one position and therefore one set of scanlines:
	' ship, force field and (from phase 3) the gun dot. That is three of the
	' VDP's four sprites-per-scanline, which is why the enemies get a slot
	' rotation from phase 4 -- otherwise the one at the player's height is the
	' one that vanishes.
draw_ship:
	shx8 = #shx / 256		' compiles to srl r0,8 -- no DIV, free
	shy8 = #shy / 256
	SPRITE 0,shy8,shx8,0,15		' hull, white
	rgp = rphs * 4
	rgp = rgp + 4			' patterns 4,8,12,16
	SPRITE 1,shy8,shx8,rgp,5	' field -- colour carries charge in phase 2
	RETURN

	' ------------------------------------------------------------- spin ring
	' The field shimmers whether or not anything else is happening, including
	' on the title screen. One phase every 4 frames: at 60 Hz that carries the
	' ring through a full dot position (45 degrees) in about a quarter second.
spin_ring:
	rgt = rgt + 1
	IF rgt < 4 THEN RETURN
	rgt = 0
	rphs = rphs + 1
	rphs = rphs AND 3		' AND, not MOD -- % compiles to a real DIV
	RETURN

	' -------------------------------------------------------------- hide all
hide_all:
	FOR hai = 0 TO 20
		SPRITE hai,SPRHID,0,0,0
	NEXT hai
	RETURN

	' ----------------------------------------------------------- paint stars
	' The starfield is CHARACTERS, painted once, never touched again -- so it
	' costs nothing per frame. It is not decoration: with nothing fixed to see
	' it against, a ship crossing the wrap seam just looks like it teleported.
	'
	' NO MULTIPLICATION. The obvious `#a = row * 32 : #a = #a + col` walks
	' straight into the MPY hazard -- the 9900 leaves the product's HIGH word
	' in r0 and the compiler keeps believing r0 holds the variable, so the very
	' next line reads back zero. Walking the address down a row at a time
	' avoids the multiply entirely and is faster besides.
paint_stars:
	#sfa = 6208			' 6144 (name table) + 64 (row 2, column 0)
	FOR sfr = 2 TO 23
		FOR sfk = 0 TO 1
			#sfb = #sfa + RANDOM(32)
			sfv = 128 + RANDOM(3)
			VPOKE #sfb,sfv	' both operands are plain vars: VPOKE with
					' an expression races the vblank ISR
		NEXT sfk
		#sfa = #sfa + 32
	NEXT sfr
	RETURN

	' ----------------------------------------------------------- print score
	' Four digits. FAITHFUL 1/3/10 SCORING means this rarely passes two, but
	' a long chain-reaction game can, and a score that wraps at 99 would look
	' broken rather than authentic.
prt_score:
	#psv = #score
	#psa = 6150			' 6144 + 6: row 0, column 6
	#psd = 1000
	GOTO prt_digits

prt_hi:
	#psv = #hisc
	#psa = 6170			' 6144 + 26: row 0, column 26
	#psd = 1000
	GOTO prt_digits

	' Shared tail. Entered by GOTO from two callers that were themselves
	' entered by GOSUB, so the RETURN below returns to THEIR caller -- a tail
	' call, which gosubtrace.py recognises and does not flag.
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
	' Next power of ten down, by repeated subtraction rather than a divide.
	' Four steps, so this is cheaper than the DIV would be and it is only
	' called when the score actually changes.
	IF #psd = 1000 THEN #psd = 100 : GOTO prt_dloop
	IF #psd = 100 THEN #psd = 10 : GOTO prt_dloop
	IF #psd = 10 THEN #psd = 1 : GOTO prt_dloop
	RETURN

	' ------------------------------------------------- TEMPORARY loop probe
	' Two digits at row 0, column 20: measured main-loop passes per second.
	' The whole performance argument for this game (DESIGN.md 1) is a
	' PREDICTION -- ~2400 instructions a frame against Joust's measured 11200
	' -- and predictions about this toolchain have been wrong before. This
	' reads the real number.
	'
	' REMOVE THIS before the game is called done.
lprate:
	lpc = lpc + 1
	#lpd = FRAME
	#lpd = #lpd - #lpl
	IF #lpd < 60 THEN RETURN
	#lpl = FRAME
	lph = lpc / 10
	' 6144 is the name table base and 20 the column, added as SEPARATE steps.
	' Folded into one constant expression the addend truncates and the write
	' lands outside the name table: nothing appears, and nothing complains.
	#lpa = 20
	#lpa = #lpa + 6144
	lpv = 48 + lph
	VPOKE #lpa,lpv
	#lpa = #lpa + 1
	lpv = lph * 10
	lpv = lpc - lpv
	lpv = 48 + lpv
	VPOKE #lpa,lpv
	lpc = 0
	RETURN

	INCLUDE "art.bas"
	INCLUDE "font.bas"
