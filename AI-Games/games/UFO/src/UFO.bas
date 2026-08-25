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
	'   * Every #var comparison is UNSIGNED.
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
	' each would silently truncate to its low byte -- all three to 0 -- and the
	' wrap would simply stop happening.

	' ---------------------------------------------------------- FORCE FIELD
	' The whole game is these five numbers. See DESIGN.md 3.
	CONST SHMAX = 15		' ARMED only at full. Full, or vulnerable
	CONST SHFIRE = 5		' a shot costs a third of the field
	CONST SHTICK = 12		' +1 every 12 frames: 0 to full in ~3 seconds
	CONST AIMTICK = 5		' the gun advances one step every 5 frames
	CONST LLIFE = 40		' laser frames before it expires

	' -------------------------------------------------------------- variables
	' shld  force field, 0..SHMAX. Armed ONLY at SHMAX
	' shtk  recharge tick
	' aim   0..15, sixteen 22.5 degree steps, 0 = up, increasing CLOCKWISE
	' amtk  aim tick
	' hdg   the joystick's heading as an aim index, or 255 for "not moving"
	' fbr   fire button released since the last shot (edge trigger)
	' #shx/#shy  ship position, 8.8. X wraps FOR FREE: 256 px x 256 = 65536
	'            overflows 16 bits exactly. Y is the only axis that costs.

	DIM #aox(16),#aoy(16)		' gun-dot offset from the ship, 8.8
	DIM #vlxt(16),#vlyt(16)		' laser velocity, 8.8

	DIM #lx(2),#ly(2)		' laser position, 8.8
	DIM #lvx(2),#lvy(2)		' laser velocity for this shot
	DIM lon(2),llf(2)		' alive flag, frames remaining

	' WHERE THE GUN IS, radius 6.8 px -- the same circle the force-field art is
	' drawn on (assets/genart.py R_OUTER), so the gun dot sits ON the ring
	' rather than near it.
	'
	' ONE TABLE, IN 8.8, and it is the single source of truth for two things:
	' where the gun dot is drawn, and where a bolt is born. Held as whole
	' pixels instead, the laser spawn would need offset * 256 at runtime --
	' and an 8-bit variable times a constant over 255 compiles to a bare CLR
	' (CLAUDE.md 3A), so every shot would have left from the ship's centre
	' with nothing anywhere reporting a problem.
	'
	' Negative components are written as TWO'S COMPLEMENT, as with the laser
	' velocities below: -768 is 64768, -1280 is 64256, -1536 is 64000,
	' -1792 is 63744.
	#aox(0)=0      : #aoy(0)=63744
	#aox(1)=768    : #aoy(1)=64000
	#aox(2)=1280   : #aoy(2)=64256
	#aox(3)=1536   : #aoy(3)=64768
	#aox(4)=1792   : #aoy(4)=0
	#aox(5)=1536   : #aoy(5)=768
	#aox(6)=1280   : #aoy(6)=1280
	#aox(7)=768    : #aoy(7)=1536
	#aox(8)=0      : #aoy(8)=1792
	#aox(9)=64768  : #aoy(9)=1536
	#aox(10)=64256 : #aoy(10)=1280
	#aox(11)=64000 : #aoy(11)=768
	#aox(12)=63744 : #aoy(12)=0
	#aox(13)=64000 : #aoy(13)=64768
	#aox(14)=64256 : #aoy(14)=64256
	#aox(15)=64768 : #aoy(15)=64000

	' LASER VELOCITY, 8.8, magnitude 1024 = 4 px/frame.
	'
	' Negative components are written as their TWO'S COMPLEMENT (65536 - n), so
	' the update is a plain modular add with no bias to take off and no sign to
	' get wrong: -1024 is 64512, -946 is 64590, -724 is 64812, -392 is 65144.
	'
	' PRECOMPUTED, NEVER DERIVED AT RUNTIME. CVBasic's 16-bit divide is
	' UNSIGNED, so working these out on the fly turns every negative component
	' into a huge positive one and every left-going shot flies right.
	#vlxt(0)=0      : #vlyt(0)=64512
	#vlxt(1)=392    : #vlyt(1)=64590
	#vlxt(2)=724    : #vlyt(2)=64812
	#vlxt(3)=946    : #vlyt(3)=65144
	#vlxt(4)=1024   : #vlyt(4)=0
	#vlxt(5)=946    : #vlyt(5)=392
	#vlxt(6)=724    : #vlyt(6)=724
	#vlxt(7)=392    : #vlyt(7)=946
	#vlxt(8)=0      : #vlyt(8)=1024
	#vlxt(9)=65144  : #vlyt(9)=946
	#vlxt(10)=64812 : #vlyt(10)=724
	#vlxt(11)=64590 : #vlyt(11)=392
	#vlxt(12)=64512 : #vlyt(12)=0
	#vlxt(13)=64590 : #vlyt(13)=65144
	#vlxt(14)=64812 : #vlyt(14)=64812
	#vlxt(15)=65144 : #vlyt(15)=64590

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
	shld = SHMAX
	shtk = 0
	aim = 0
	amtk = 0
	fbr = 0
	rphs = 0
	lon(0) = 0
	lon(1) = 0
	lpc = 0
	#lpl = 0

	' ------------------------------------------------------------- main loop
main:
	WAIT
	GOSUB spin_ring
	GOSUB read_stick
	GOSUB charge
	GOSUB move_ship
	GOSUB drift_aim
	GOSUB fire_check
	GOSUB upd_lasers
	GOSUB draw_ship
	GOSUB lprate
	GOTO main

	' ------------------------------------------------------------ read stick
	' 8-way, no inertia. NOTE the nested IFs: `cont1.left AND cont1.up` would
	' be miscompiled by the 9900 backend (stale-register AND), and it compiles
	' clean, so there would be no warning of any kind.
	'
	' hdg is the heading as an AIM INDEX (even values only -- the stick has 8
	' directions, the gun has 16), or 255 when the stick is centred.
read_stick:
	sdx = 0
	sdy = 0
	hdg = 255
	IF cont1.left THEN sdx = 1
	IF cont1.right THEN sdx = 2
	IF cont1.up THEN sdy = 1
	IF cont1.down THEN sdy = 2

	IF sdy = 1 THEN
		hdg = 0
		IF sdx = 2 THEN hdg = 2
		IF sdx = 1 THEN hdg = 14
	END IF
	IF sdy = 0 THEN
		IF sdx = 2 THEN hdg = 4
		IF sdx = 1 THEN hdg = 12
	END IF
	IF sdy = 2 THEN
		hdg = 8
		IF sdx = 2 THEN hdg = 6
		IF sdx = 1 THEN hdg = 10
	END IF
	RETURN

	' ---------------------------------------------------------------- charge
	' +1 every SHTICK frames, so an empty field is back to ARMED in about
	' three seconds -- and you are vulnerable for every one of them, not just
	' until it is "mostly" charged.
charge:
	IF shld >= SHMAX THEN RETURN
	shtk = shtk + 1
	IF shtk < SHTICK THEN RETURN
	shtk = 0
	shld = shld + 1
	RETURN

	' ------------------------------------------------------------- move ship
	' HALF SPEED WHILE RECHARGING. This is the rule that makes spending the
	' field hurt twice: you are not merely mortal for three seconds, you are
	' also too slow to run away. It is straight from the manual summary and it
	' is what stops "fire at everything" from being a strategy.
move_ship:
	#sspd = 384
	IF shld < SHMAX THEN #sspd = 192
	IF sdx <> 0 THEN
		IF sdy <> 0 THEN
			' Diagonal, scaled so it is not 1.41x faster than straight
			#sspd = 272
			IF shld < SHMAX THEN #sspd = 136
		END IF
	END IF

	IF sdx = 1 THEN #shx = #shx - #sspd
	IF sdx = 2 THEN #shx = #shx + #sspd
	IF sdy = 1 THEN #shy = #shy - #sspd
	IF sdy = 2 THEN #shy = #shy + #sspd

	' X WRAPS FOR FREE -- 256 px x 256 = 65536 overflows 16 bits exactly.
	'
	' Y is the only axis that costs anything, because the band is 160 px, not
	' 256. Low test FIRST: the largest step is 384 and the band floor in 8.8
	' is 4096, so #shy can never underflow past zero and both compares stay
	' safely unsigned.
	IF #shy < 4096 THEN #shy = #shy + 40960
	IF #shy >= 45056 THEN #shy = #shy - 40960
	RETURN

	' ------------------------------------------------------------- drift aim
	' THE GUN ONLY EVER TURNS CLOCKWISE.
	'
	' Sources disagree on this and DESIGN.md 0 records the disagreement: two
	' say the aiming dot rotates TOWARD the heading, one says it rotates
	' CLOCKWISE. Clockwise-only is the literal reading and the harsher one --
	' a heading one step anticlockwise of the gun costs FIFTEEN steps, about
	' 1.2 seconds, and the gun sweeps past everything else on the way.
	'
	' That is not an annoyance to be tuned out. It is the reason the force
	' field, not the laser, is the weapon you learn to use.
	'
	' The gun also only moves WHILE THE SHIP IS MOVING -- park, and it settles
	' where it is.
drift_aim:
	IF hdg = 255 THEN RETURN
	IF aim = hdg THEN RETURN
	amtk = amtk + 1
	IF amtk < AIMTICK THEN RETURN
	amtk = 0
	aim = aim + 1
	aim = aim AND 15		' AND, not MOD -- % compiles to a real DIV
	RETURN

	' ------------------------------------------------------------ fire check
	' EDGE TRIGGERED. Held down, an auto-repeat would empty the field in three
	' frames and leave the player wondering what happened; each shot has to be
	' a decision, because each shot costs a third of the only defence there is.
fire_check:
	IF cont1.button = 0 THEN
		fbr = 1
		RETURN
	END IF
	IF fbr = 0 THEN RETURN		' still held from the last shot
	IF shld < SHFIRE THEN RETURN	' not enough field left to spend

	fi = 255
	IF lon(0) = 0 THEN fi = 0
	IF lon(1) = 0 THEN fi = 1
	IF fi = 255 THEN RETURN		' both barrels already in flight

	fbr = 0
	shld = shld - SHFIRE
	shtk = 0			' a shot restarts the recharge clock

	' The bolt starts AT THE GUN DOT, not at the ship's centre -- it has to
	' leave from the thing the player has been watching drift into place.
	lon(fi) = 1
	llf(fi) = LLIFE
	#lx(fi) = #shx + #aox(aim)
	#ly(fi) = #shy + #aoy(aim)
	#lvx(fi) = #vlxt(aim)
	#lvy(fi) = #vlyt(aim)
	RETURN

	' ----------------------------------------------------------- update lasers
upd_lasers:
	FOR ui = 0 TO 1
		IF lon(ui) = 1 THEN
			llf(ui) = llf(ui) - 1
			IF llf(ui) = 0 THEN
				lon(ui) = 0
				SPRITE 3 + ui,SPRHID,0,0,0
			ELSE
				' Velocities are stored as two's complement, so
				' this is a plain modular add -- and x wraps for
				' free out of the same overflow.
				#lx(ui) = #lx(ui) + #lvx(ui)
				#ly(ui) = #ly(ui) + #lvy(ui)
				IF #ly(ui) < 4096 THEN #ly(ui) = #ly(ui) + 40960
				IF #ly(ui) >= 45056 THEN #ly(ui) = #ly(ui) - 40960
				ulx = #lx(ui) / 256
				uly = #ly(ui) / 256
				SPRITE 3 + ui,uly,ulx,40,11
			END IF
		END IF
	NEXT ui
	RETURN

	' ------------------------------------------------------------- draw ship
	' Three sprites share one position and therefore one set of scanlines:
	' ship, force field and gun dot. That is three of the VDP's four
	' sprites-per-scanline, which is why the enemies get a slot rotation from
	' phase 4 -- otherwise the one at the player's height is the one that
	' vanishes, exactly when it matters most.
draw_ship:
	shx8 = #shx / 256		' compiles to srl r0,8 -- no DIV, free
	shy8 = #shy / 256
	SPRITE 0,shy8,shx8,0,15		' hull, white

	' THE FIELD'S COLOUR IS THE GAUGE. Black when empty climbing to blue is
	' the manual's own description; the flash at full charge is ours, and it
	' earns its place -- ARMED is a binary state with lethal consequences and
	' the player is watching enemies, not their own ring.
	IF shld = 0 THEN
		SPRITE 1,SPRHID,0,0,0
	ELSE
		rgp = rphs * 4
		rgp = rgp + 4		' patterns 4,8,12,16
		rgc = 4			' dark blue -- barely there
		IF shld > 5 THEN rgc = 5	' light blue -- coming back
		IF shld > 10 THEN rgc = 7	' cyan -- almost
		IF shld = SHMAX THEN
			rgc = 7
			IF rphs < 2 THEN rgc = 15	' ARMED: flashing white
		END IF
		SPRITE 1,shy8,shx8,rgp,rgc
	END IF

	' The gun dot rides the same circle the field art is drawn on. Yellow
	' when there is enough field to fire, dark red when there is not -- so
	' "can I shoot?" is answered without doing arithmetic in your head.
	#gtx = #shx + #aox(aim)
	#gty = #shy + #aoy(aim)
	gdx = #gtx / 256
	gdy = #gty / 256
	gdc = 11
	IF shld < SHFIRE THEN gdc = 6
	SPRITE 2,gdy,gdx,20,gdc
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
	' next line reads back zero and every star lands in row 0. Walking the
	' address down a row at a time avoids the multiply entirely.
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
	' a long chain-reaction game can, and a score that wrapped at 99 would
	' look broken rather than authentic.
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
	' call, which gosubtrace.py recognises and correctly does not flag.
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
	' Next power of ten down. Repeated subtraction rather than a divide --
	' four steps, cheaper than the DIV, and only called when the score
	' actually changes.
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
