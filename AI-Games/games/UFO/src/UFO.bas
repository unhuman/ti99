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

	' ------------------------------------------------------------- ENEMIES
	CONST NENE = 8			' enemy slots, DIM 0..7
	CONST ETDRIFT = 1		' random drifter        -- 1 point, ZERO AI
	CONST ETHUNT = 2		' Hunter-Killer         -- 3 points
	CONST ETSHIP = 3		' Light-speed Starship  -- 10 points
	CONST SPAWNT = 90		' frames between spawn attempts
	CONST RAMR = 14			' ram range: the force field's own radius
	CONST HULLR = 9			' hull range: what kills you with no field
	CONST ACQR = 110		' a Hunter this close ACQUIRES you -- and
					' drags one of its own kind in with it
	CONST NMIS = 8			' missile slots, DIM 0..7. EIGHT because a
					' chain reaction spawns three at a time
	CONST MLIFE = 90		' GUIDED missile frames before it burns out
	CONST DLIFE = 32		' DEBRIS frames: 32 x 2 px = 64 px and gone.
					' Shrapnel has a throw; it is not a weapon
					' that follows you across the arena.
	CONST DARM = 12			' frames before debris can hurt the PLAYER.
					' It spawns ON the enemy that died, and if
					' you killed that enemy by RAMMING it you
					' are 14 px away with a field of zero -- so
					' without this, the game's core tactic
					' detonates three warheads in your lap.
					' It can still chain into other enemies
					' from frame one.
	CONST SHIPFT = 70		' Starship frames between shots
	CONST DYINGF = 48		' frames of sparking before the ship goes -- and
					' YOU STILL HAVE CONTROL for all of them

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
	DIM #vlxt(16),#vlyt(16)		' laser velocity, 8.8   (1024 = 4 px/frame)
	DIM #vhxt(16),#vhyt(16)		' Hunter velocity, 8.8  (320  = 1.25)
	DIM #vmxt(16),#vmyt(16)		' missile + Starship    (512  = 2)

	DIM #lx(2),#ly(2)		' laser position, 8.8
	DIM #lvx(2),#lvy(2)		' laser velocity for this shot
	DIM lon(2),llf(2)		' alive flag, frames remaining

	DIM #ex(NENE),#ey(NENE)		' enemy position, 8.8
	DIM #evx(NENE),#evy(NENE)	' enemy velocity, 8.8 two's complement
	DIM ety(NENE)			' 0 dead, or one of the three ET* types
	DIM edir(NENE)			' heading 0..15, for the types that steer
	DIM eaq(NENE)			' Hunter: 1 once it has ACQUIRED the player
	DIM efr(NENE)			' Starship: frames until it fires again

	DIM #mx(NMIS),#my(NMIS)		' missile position, 8.8
	DIM mdir(NMIS)			' heading 0..15 -- velocity is LOOKED UP from
					' it each frame rather than stored, which is
					' what makes a missile steerable for free
	DIM mon(NMIS),mlf(NMIS)		' alive flag, frames remaining
	DIM mgd(NMIS)			' 1 = GUIDED (a Starship fired it and it
					'     steers), 0 = DEBRIS (dead straight)
	DIM marm(NMIS)			' debris: frames until it can hurt you

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

	' HUNTER-KILLER VELOCITY, magnitude 320 = 1.25 px/frame.
	'
	' THAT NUMBER IS THE WHOLE BALANCE OF THE GAME. The player does 1.5
	' px/frame armed and 0.75 recharging, so a Hunter is slower than you while
	' your field is up and FASTER than you the moment you spend it. You can
	' outrun one only by being armed -- which is exactly the thing you have to
	' give up to shoot at it.
	#vhxt(0)=0      : #vhyt(0)=65216
	#vhxt(1)=122    : #vhyt(1)=65240
	#vhxt(2)=226    : #vhyt(2)=65310
	#vhxt(3)=296    : #vhyt(3)=65414
	#vhxt(4)=320    : #vhyt(4)=0
	#vhxt(5)=296    : #vhyt(5)=122
	#vhxt(6)=226    : #vhyt(6)=226
	#vhxt(7)=122    : #vhyt(7)=296
	#vhxt(8)=0      : #vhyt(8)=320
	#vhxt(9)=65414  : #vhyt(9)=296
	#vhxt(10)=65310 : #vhyt(10)=226
	#vhxt(11)=65240 : #vhyt(11)=122
	#vhxt(12)=65216 : #vhyt(12)=0
	#vhxt(13)=65240 : #vhyt(13)=65414
	#vhxt(14)=65310 : #vhyt(14)=65310
	#vhxt(15)=65414 : #vhyt(15)=65240

	' MISSILE AND STARSHIP VELOCITY, magnitude 512 = 2 px/frame -- faster than
	' anything else in the game, which is what makes both of them a problem
	' you solve by not being there rather than by out-running.
	#vmxt(0)=0      : #vmyt(0)=65024
	#vmxt(1)=196    : #vmyt(1)=65063
	#vmxt(2)=362    : #vmyt(2)=65174
	#vmxt(3)=473    : #vmyt(3)=65340
	#vmxt(4)=512    : #vmyt(4)=0
	#vmxt(5)=473    : #vmyt(5)=196
	#vmxt(6)=362    : #vmyt(6)=362
	#vmxt(7)=196    : #vmyt(7)=473
	#vmxt(8)=0      : #vmyt(8)=512
	#vmxt(9)=65340  : #vmyt(9)=473
	#vmxt(10)=65174 : #vmyt(10)=362
	#vmxt(11)=65063 : #vmyt(11)=196
	#vmxt(12)=65024 : #vmyt(12)=0
	#vmxt(13)=65063 : #vmyt(13)=65340
	#vmxt(14)=65174 : #vmyt(14)=65174
	#vmxt(15)=65340 : #vmyt(15)=65063

	#score = 0
	#hisc = 0
	' ONE SHIP, faithful to the cartridge. 838 on the title will give you up
	' to nine, and difficulty 1..9 to start from.
	start_ships = 1
	start_diff = 1
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
	DEFINE CHAR 131,1,chr_life

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

	PRINT AT 108,"U F O !"		' row 3, centred
	PRINT AT 168,"SATELLITE ATTACK"	' row 5, centred
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
	SOUND 0,,0 : SOUND 1,,0 : SOUND 2,,0 : SOUND 3,,0
	btnr = 0
	cst = 0
	tkl = 15
title_wait:
	WAIT
	GOSUB spin_ring

	' 8-3-8 OPENS THE SETUP SCREEN, edge-triggered on cont1.key, which gives
	' 0-9 on both targets and 15 for nothing. It is NOT captioned on the
	' title: there is no room, and it is in the README.
	tk = cont1.key
	IF tk <> tkl THEN
		tkl = tk
		IF tk <> 15 THEN
			IF cst = 0 THEN
				IF tk = 8 THEN cst = 1
			END IF
			IF cst = 1 THEN
				IF tk = 3 THEN cst = 2
			END IF
			IF cst = 2 THEN
				IF tk = 8 THEN GOTO setup838
			END IF
		END IF
	END IF

	IF cont1.button = 0 THEN btnr = 1
	IF btnr = 0 THEN GOTO title_wait
	IF cont1.button THEN GOTO new_game
	GOTO title_wait

	' ------------------------------------------------------- 8 3 8 SETUP
	' NUMBER KEYS, one per field, with the key printed beside it. NOT a
	' cursor: on the TI the joystick's vertical axis shares a line with ALPHA
	' LOCK, so an up/down menu boots pinned to one entry and cannot be moved
	' off it (CLAUDE.md 3A). Left/right would work and is its own trap --
	' players press up and down anyway.
setup838:
	CLS
	GOSUB paint_stars
	PRINT AT 73,"8 3 8   SETUP"	' row 2, centred
	PRINT AT 194,"1     SHIPS"
	PRINT AT 258,"2     DIFFICULTY"
	PRINT AT 386,"PRESS A NUMBER TO CHANGE IT"
	PRINT AT 482,"PRESS FIRE TO START"
	PRINT AT 610,"ONE SHIP IS THE ORIGINAL"
	skl = 15
	sbr = 0
su_loop:
	WAIT
	GOSUB su_draw
	sk = cont1.key
	IF sk <> skl THEN
		skl = sk
		IF sk = 1 THEN
			start_ships = start_ships + 1
			IF start_ships > 9 THEN start_ships = 1
		END IF
		IF sk = 2 THEN
			start_diff = start_diff + 1
			IF start_diff > 9 THEN start_diff = 1
		END IF
	END IF
	IF cont1.button = 0 THEN sbr = 1
	IF sbr = 1 THEN
		IF cont1.button THEN GOTO new_game
	END IF
	GOTO su_loop

su_draw:
	#sua = 6356			' row 6, column 20 -- CLEAR of the labels.
					' Column 16 is inside the word DIFFICULTY
					' on the row below, which reads as a typo
					' in the label rather than a stray value.
	suv = 48 + start_ships
	VPOKE #sua,suv
	#sua = 6420			' row 8, column 20
	suv = 48 + start_diff
	VPOKE #sua,suv
	RETURN

	' -------------------------------------------------------------- new game
new_game:
	CLS
	GOSUB paint_stars
	PRINT AT 0,"SCORE"
	PRINT AT 23,"HI"
	#score = 0
	lives = start_ships
	diff = start_diff
	#dfk = 0
	GOSUB set_rate
	GOSUB prt_score
	GOSUB prt_hi
	GOSUB prt_lives

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
	FOR ni = 0 TO NENE - 1
		ety(ni) = 0
	NEXT ni
	FOR ni = 0 TO NMIS - 1
		mon(ni) = 0
	NEXT ni
	dead = 0
	dying = 0
	sptk = 0
	satt = 0
	sf0 = 0 : sf1 = 0 : sf2 = 0 : sf3 = 0
	SOUND 0,,0 : SOUND 1,,0 : SOUND 2,,0 : SOUND 3,,0
	lpc = 0
	#lpl = 0

	' ------------------------------------------------------------- respawn
	' Missiles are cleared, satellites are NOT. Wiping the arena would make
	' every death a free reset; leaving the missiles would make it a lottery,
	' because a guided missile already in the air cannot be dodged from a
	' standing start in the middle of the screen.
respawn:
	#shx = 30720
	#shy = 22528
	shld = SHMAX
	shtk = 0
	aim = 0
	amtk = 0
	fbr = 0
	dead = 0
	dying = 0
	lon(0) = 0
	lon(1) = 0
	SPRITE 3,SPRHID,0,0,0
	SPRITE 4,SPRHID,0,0,0
	FOR ni = 0 TO NMIS - 1
		mon(ni) = 0
		SPRITE 13 + ni,SPRHID,0,0,0
	NEXT ni
	GOSUB prt_lives
	GOTO main

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
	GOSUB spawn_try
	GOSUB upd_enemies
	GOSUB upd_missiles
	GOSUB draw_ship
	GOSUB tick_diff
	GOSUB sfx_tick
	GOSUB lprate

	' DEATH IS A STATE, NOT A JUMP. Collision detection sets `dead` and the
	' main loop acts on it here, at the top level. Jumping out of the
	' collision GOSUB directly would never pop its return address -- invisible
	' on the TI's 7 KB of stack, fatal on ColecoVision's 1 KB.
	'
	' AND YOU KEEP FLYING WHILE IT HAPPENS. The original lets the player go on
	' steering through the whole sparking, colour-cycling destruction, and it
	' is a surprising amount of what gives the death its character -- you are
	' not watching a cutscene, you are watching your own ship come apart
	' underneath you while you still have the stick.
	IF dead = 1 THEN
		IF dying = 0 THEN
			dying = DYINGF
			#dsw = 150		' the sweep starts high and falls
			sf0 = 0
		END IF
		dead = 0
	END IF
	IF dying > 0 THEN
		dying = dying - 1
		SOUND 0,#dsw,13
		#dsw = #dsw + 16
		IF #dsw > 1000 THEN #dsw = 1000
		IF dying = 0 THEN GOTO do_death
	END IF
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
	' ARMED AGAIN -- and it is announced, because the player is watching
	' enemies rather than their own ring, and this is the moment the rules
	' change back. A rising two-note: the second note is set by sfx_tick,
	' since two SOUNDs on one channel back to back would just cancel.
	IF shld = SHMAX THEN
		SOUND 2,500,9
		sf2 = 12
	END IF
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

	' Published here rather than in draw_ship because collision detection runs
	' first and needs them. srl r0,8 -- no DIV, free.
	shx8 = #shx / 256
	shy8 = #shy / 256
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
	SOUND 0,180,12 : sf0 = 4

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
	' Sparking: the hull cycles colours furiously while it is dying, which is
	' the cue that the next few seconds are already lost however well you fly.
	shc = 15
	IF dying > 0 THEN
		shc = dying AND 7
		shc = shc + 2
	END IF
	SPRITE 0,shy8,shx8,0,shc	' shx8/shy8 set in move_ship

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

	' ----------------------------------------------------------- difficulty
	' One step every 1800 frames (30 s), to a ceiling of 9. It buys a faster
	' spawn rate and a nastier MIX -- never a bigger arena and never a nerf to
	' the player. Per CLAUDE.md 3A a difficulty dial must not invert the goal:
	' enemies always visibly attack, Hunters just get commoner.
tick_diff:
	#dfk = #dfk + 1
	IF #dfk < 1800 THEN RETURN
	#dfk = 0
	IF diff >= 9 THEN RETURN
	diff = diff + 1
	GOSUB set_rate
	RETURN

	' Spawn interval, 100 - diff*8: 92 frames at difficulty 1 down to 28 at 9.
	' THREE DOUBLINGS, not `diff * 8` -- see to88 for why a multiply into an
	' 8-bit variable is not worth the risk when three adds cost nothing.
set_rate:
	spint = diff + diff
	spint = spint + spint
	spint = spint + spint
	spint = 100 - spint
	RETURN

	' ------------------------------------------------------------ spawn try
	' Drifters arrive on the FAR SIDE of the wrap: x is the player's own
	' column plus 96 to 159, which in 8-bit arithmetic wraps by itself and so
	' is always most of a screen away. Spawning at a uniformly random point
	' and rejecting the near ones would sometimes reject several in a row and
	' leave the arena empty for no reason the player can see.
spawn_try:
	sptk = sptk + 1
	IF sptk < spint THEN RETURN
	sptk = 0

	si = 255
	FOR ssi = 0 TO NENE - 1
		IF ety(ssi) = 0 THEN si = ssi
	NEXT ssi
	IF si = 255 THEN RETURN		' every slot busy

	t8 = shx8 + 96
	t8 = t8 + RANDOM(64)
	GOSUB to88
	#ex(si) = #t88
	t8 = 16 + RANDOM(160)
	GOSUB to88
	#ey(si) = #t88

	' WHICH KIND. Drifters are the bulk of the sky, Hunters are the threat,
	' and a Starship is an event. Phase 8 tilts these with difficulty.
	edir(si) = RANDOM(16)
	eaq(si) = 0
	efr(si) = SHIPFT
	' THE MIX SHIFTS, THE STARSHIP DOES NOT. Drifters thin out from 13 in 20
	' down to 5 and Hunters take their place, but a Starship stays a flat 2 in
	' 20 at every difficulty -- it is meant to be an event, and an event that
	' happens constantly is just weather.
	sr = RANDOM(20)
	sdt = 14 - diff
	sht = sdt + 4
	sht = sht + diff
	IF sr < sdt THEN
		ety(si) = ETDRIFT
		GOSUB rnd_vel
		#evx(si) = #rv
		GOSUB rnd_vel
		#evy(si) = #rv
		' A satellite with no velocity at all just sits there looking broken.
		IF #evx(si) = 0 THEN
			IF #evy(si) = 0 THEN #evx(si) = 96
		END IF
		RETURN
	END IF
	IF sr < sht THEN
		ety(si) = ETHUNT
		#evx(si) = #vhxt(edir(si))
		#evy(si) = #vhyt(edir(si))
		RETURN
	END IF
	ety(si) = ETSHIP
	#evx(si) = #vmxt(edir(si))
	#evy(si) = #vmyt(edir(si))
	RETURN

	' -------------------------------------------------------- random velocity
	' Five speeds per axis, picked from an IF ladder rather than scaled from
	' the 16-direction table. Scaling would need a divide, and CVBasic's
	' 16-bit divide is UNSIGNED -- every negative component would come back
	' as a huge positive one and every satellite would drift the same way.
	'
	' Twenty-five combinations is plenty for what the sources call a
	' "semi-random, circular" drift, and it costs no table.
rnd_vel:
	rv = RANDOM(5)
	#rv = 0
	IF rv = 0 THEN #rv = 65344	' -192, i.e. -0.75 px/frame
	IF rv = 1 THEN #rv = 65440	' -96
	IF rv = 3 THEN #rv = 96
	IF rv = 4 THEN #rv = 192
	RETURN

	' ------------------------------------------------- whole pixels to 8.8
	' EIGHT DOUBLINGS, NOT `t8 * 256`. An 8-bit variable times a constant over
	' 255 compiles to a bare CLR (CLAUDE.md 3A), so every enemy would spawn at
	' x=0, y=0 -- in the corner, on top of each other, with nothing reporting
	' a problem. Only called at spawn, so the eight adds cost nothing.
to88:
	#t88 = t8
	#t88 = #t88 + #t88
	#t88 = #t88 + #t88
	#t88 = #t88 + #t88
	#t88 = #t88 + #t88
	#t88 = #t88 + #t88
	#t88 = #t88 + #t88
	#t88 = #t88 + #t88
	#t88 = #t88 + #t88
	RETURN

	' -------------------------------------------------------- update enemies
upd_enemies:
	satt = satt + 1
	FOR ei = 0 TO NENE - 1
		IF ety(ei) <> 0 THEN
			#ex(ei) = #ex(ei) + #evx(ei)
			#ey(ei) = #ey(ei) + #evy(ei)
			IF #ey(ei) < 4096 THEN #ey(ei) = #ey(ei) + 40960
			IF #ey(ei) >= 45056 THEN #ey(ei) = #ey(ei) - 40960
			ex8 = #ex(ei) / 256
			ey8 = #ey(ei) / 256

			' THE ORIGINAL'S OWN TRICK: flip between a PLUS and a
			' CROSS and the shape appears to spin, because a plus
			' turned 45 degrees IS a multiply sign. The + ei staggers
			' the slots so they do not all flip on the same frame,
			' which would read as the whole screen blinking.
			eap = satt + ei
			eap = eap AND 4
			epn = 24
			IF eap <> 0 THEN epn = 28
			ecl = 3			' drifter: light green

			IF ety(ei) = ETHUNT THEN
				' Same PLUS/CROSS body in a hotter colour: the
				' thing chasing you is recognisably the same
				' species as the thing drifting past, which is
				' how the original reads.
				ecl = 13		' magenta: drifting, unaware
				IF eaq(ei) = 1 THEN ecl = 9	' light red: LOCKED ON
				GOSUB hunt_think
			END IF
			IF ety(ei) = ETSHIP THEN
				epn = 32
				IF eap <> 0 THEN epn = 36
				ecl = 10		' amber -- its own colour
				GOSUB ship_think
			END IF
			SPRITE 5 + ei,ey8,ex8,epn,ecl

			GOSUB coll_player
			GOSUB coll_lasers
		END IF
	NEXT ei
	RETURN

	' ----------------------------------------------------------- hunt think
	' Two comparisons and a table lookup, on alternate frames. NO SEARCH --
	' the Ms. Pac-Man trap in CLAUDE.md 5A is N actors each pathfinding every
	' frame, and this is the opposite of it.
	'
	' LINKING. The manual says a Hunter-Killer that detects you "links with
	' another of the same type". So the first one to get within ACQR drags a
	' second in with it: kill one and the pair is already committed, which is
	' what makes Hunters feel co-ordinated without any of them thinking.
hunt_think:
	hth = satt AND 1
	IF hth <> 0 THEN RETURN

	IF eaq(ei) = 0 THEN
		' Not yet acquired: is the player inside the detection radius?
		cdx = ex8 - shx8
		IF cdx > 127 THEN cdx = 0 - cdx
		IF cdx >= ACQR THEN RETURN
		IF ey8 >= shy8 THEN
			cdy = ey8 - shy8
		ELSE
			cdy = shy8 - ey8
		END IF
		IF cdy > 80 THEN cdy = 160 - cdy
		IF cdy >= ACQR THEN RETURN
		eaq(ei) = 1
		' ...and link the FIRST unacquired Hunter to the same target.
		' A flag, not `hli = NENE` -- breaking out by mutating a FOR
		' variable is not something CVBasic promises anything about.
		hlk = 0
		FOR hli = 0 TO NENE - 1
			IF hlk = 0 THEN
				IF ety(hli) = ETHUNT THEN
					IF eaq(hli) = 0 THEN
						eaq(hli) = 1
						hlk = 1	' one partner, not all
					END IF
				END IF
			END IF
		NEXT hli
		RETURN
	END IF

	px8 = ex8
	py8 = ey8
	GOSUB dir_to_player
	IF gdir = 255 THEN RETURN
	GOSUB step_toward
	edir(ei) = sdir
	#evx(ei) = #vhxt(sdir)
	#evy(ei) = #vhyt(sdir)
	RETURN

	' ----------------------------------------------------------- ship think
	' The Starship does not steer -- it crosses, fast, and fires GUIDED
	' missiles as it goes. Nothing about it reacts to the player except the
	' thing it launches, which is why it reads as a bomber rather than a
	' chaser and why it is worth ten points.
ship_think:
	IF efr(ei) > 0 THEN
		efr(ei) = efr(ei) - 1
		RETURN
	END IF
	efr(ei) = SHIPFT
	px8 = ex8
	py8 = ey8
	GOSUB dir_to_player
	IF gdir = 255 THEN RETURN
	mfd = gdir
	mfx8 = ex8
	mfy8 = ey8
	mfg = 1				' GUIDED -- this one hunts you
	GOSUB fire_missile
	RETURN

	' -------------------------------------------------- direction to player
	' Takes px8/py8, returns gdir 0..15 (even values -- eight directions), or
	' 255 when the actor is sitting on top of the player and there is no
	' meaningful direction at all.
	'
	' No trigonometry and no divide: compare the two magnitudes, and let an
	' axis that is more than twice the other zero the smaller one. That turns
	' four quadrants into the eight compass points.
dir_to_player:
	sgx = 0
	mgx = shx8 - px8
	IF mgx <> 0 THEN
		IF mgx < 128 THEN
			sgx = 1			' player is to the RIGHT
		ELSE
			sgx = 2			' to the LEFT
			mgx = 0 - mgx
		END IF
	END IF
	' Clamp before doubling: mgx can reach 128 and 128+128 wraps to 0 in
	' 8 bits, which would invert the comparison at exactly the far distances.
	IF mgx > 100 THEN mgx = 100

	IF shy8 >= py8 THEN
		mgy = shy8 - py8
		sgy = 2				' player is BELOW
	ELSE
		mgy = py8 - shy8
		sgy = 1				' ABOVE
	END IF
	IF mgy > 80 THEN
		' The short way round is through the wrap seam, so the direction
		' is the opposite of the one the raw comparison gave.
		mgy = 160 - mgy
		IF sgy = 1 THEN
			sgy = 2
		ELSE
			sgy = 1
		END IF
	END IF
	IF mgy = 0 THEN sgy = 0

	IF mgx > mgy + mgy THEN sgy = 0
	IF mgy > mgx + mgx THEN sgx = 0

	gdir = 255
	IF sgy = 1 THEN
		gdir = 0
		IF sgx = 1 THEN gdir = 2
		IF sgx = 2 THEN gdir = 14
	END IF
	IF sgy = 0 THEN
		IF sgx = 1 THEN gdir = 4
		IF sgx = 2 THEN gdir = 12
	END IF
	IF sgy = 2 THEN
		gdir = 8
		IF sgx = 1 THEN gdir = 6
		IF sgx = 2 THEN gdir = 10
	END IF
	RETURN

	' -------------------------------------------------------- step toward
	' One notch of edir(ei) toward gdir, THE SHORT WAY. These are guided
	' weapons and homing enemies -- unlike the player's gun, which is
	' deliberately clumsy and may only ever turn clockwise (drift_aim).
step_toward:
	sdir = edir(ei)
	IF sdir = gdir THEN RETURN
	stp = gdir - sdir
	stp = stp AND 15
	IF stp < 8 THEN
		sdir = sdir + 1
	ELSE
		sdir = sdir - 1
	END IF
	sdir = sdir AND 15
	RETURN

	' ------------------------------------------------------- enemy vs player
	' TWO RANGES, AND WHICH ONE APPLIES IS THE WHOLE GAME:
	'
	'   ARMED  -- the FIELD touches it first (RAMR), the enemy dies, and the
	'             field is spent. This is the tactic the original rewards.
	'   NOT    -- there is no field, so only the HULL (HULLR) is in play, and
	'             touching anything kills you.
	'
	' So an unarmed player can slip past at a distance that would have been a
	' kill a moment earlier. That asymmetry is what makes the recharge tense
	' rather than merely inconvenient.
	'
	' X folds mod 256 because the world genuinely is 256 wide. Y CANNOT: the
	' band is 160, so an 8-bit difference of 97 is ambiguous between +97 and
	' -159. It is ordered instead, then folded over the band.
coll_player:
	IF dying > 0 THEN RETURN	' already coming apart; nothing to add
	cdx = ex8 - shx8
	IF cdx > 127 THEN cdx = 0 - cdx
	IF cdx >= RAMR THEN RETURN
	IF ey8 >= shy8 THEN
		cdy = ey8 - shy8
	ELSE
		cdy = shy8 - ey8
	END IF
	IF cdy > 80 THEN cdy = 160 - cdy
	IF cdy >= RAMR THEN RETURN

	IF shld = SHMAX THEN
		shld = 0
		shtk = 0
		SOUND 1,600,13 : sf1 = 10
		GOSUB kill_enemy
		RETURN
	END IF
	IF cdx >= HULLR THEN RETURN
	IF cdy >= HULLR THEN RETURN
	dead = 1
	RETURN

	' ------------------------------------------------------- enemy vs lasers
coll_lasers:
	FOR ci = 0 TO 1
		IF ety(ei) <> 0 THEN
			IF lon(ci) = 1 THEN
				clx = #lx(ci) / 256
				cly = #ly(ci) / 256
				cdx = ex8 - clx
				IF cdx > 127 THEN cdx = 0 - cdx
				IF cdx < 10 THEN
					IF ey8 >= cly THEN
						cdy = ey8 - cly
					ELSE
						cdy = cly - ey8
					END IF
					IF cdy > 80 THEN cdy = 160 - cdy
					IF cdy < 10 THEN
						lon(ci) = 0
						SPRITE 3 + ci,SPRHID,0,0,0
						GOSUB kill_enemy
					END IF
				END IF
			END IF
		END IF
	NEXT ci
	RETURN

	' ----------------------------------------------------------- kill enemy
	' THE CHAIN REACTION LIVES HERE. Every enemy that dies throws three
	' missiles out on diverging headings, and those missiles kill enemies,
	' which throw three more. It is the scoring engine of the game and the
	' reason the missile pool is eight rather than four.
	'
	' At 1/3/10 points a chain is LEGIBLE -- the score ticks up one kill at a
	' time and you can watch the cascade travel. A x100 scale would have made
	' the same event an unreadable blur of zeroes.
kill_enemy:
	kt = ety(ei)
	ety(ei) = 0
	SPRITE 5 + ei,SPRHID,0,0,0

	kp = 1
	IF kt = ETHUNT THEN kp = 3
	IF kt = ETSHIP THEN kp = 10
	#score = #score + kp
	GOSUB prt_score
	SOUND 3,5,12 : sf3 = 8

	' Three headings, five notches apart, from a random start -- so debris
	' fans out rather than firing the same three ways every time.
	kd = RANDOM(16)
	mfx8 = ex8
	mfy8 = ey8
	mfg = 0				' DEBRIS -- straight, short, and it does
					' not chase anybody
	FOR kci = 0 TO 2
		mfd = kd
		GOSUB fire_missile
		kd = kd + 5
		kd = kd AND 15
	NEXT kci
	RETURN

	' --------------------------------------------------------- fire missile
	' mfd = heading, mfx8/mfy8 = where from, mfg = 1 GUIDED / 0 DEBRIS.
	' Silently does nothing when the pool is full, which is correct: eight
	' missiles in the air is already a bigger cascade than the screen can show.
	'
	' THE TWO KINDS ARE NOT THE SAME OBJECT, and the first version of this
	' treating them as one was the worst bug in the game: chain debris
	' inherited the Starship's guidance, so every kill launched three HOMING
	' missiles from point-blank range. Ramming -- the tactic the whole design
	' is built around -- became a reliable way to die.
fire_missile:
	fmi = 255
	FOR fmj = 0 TO NMIS - 1
		IF mon(fmj) = 0 THEN fmi = fmj
	NEXT fmj
	IF fmi = 255 THEN RETURN
	mon(fmi) = 1
	mgd(fmi) = mfg
	IF mfg = 1 THEN
		mlf(fmi) = MLIFE
		marm(fmi) = 0		' fired from a Starship, already far away
	ELSE
		mlf(fmi) = DLIFE
		marm(fmi) = DARM
	END IF
	mdir(fmi) = mfd
	t8 = mfx8
	GOSUB to88
	#mx(fmi) = #t88
	t8 = mfy8
	GOSUB to88
	#my(fmi) = #t88
	RETURN

	' -------------------------------------------------------- update missiles
	' Velocity is LOOKED UP from mdir every frame rather than stored, which is
	' what makes a missile steerable at no cost: change the heading and the
	' velocity follows. Two array reads per missile per frame.
upd_missiles:
	FOR mi = 0 TO NMIS - 1
		IF mon(mi) = 1 THEN
			mlf(mi) = mlf(mi) - 1
			IF mlf(mi) = 0 THEN
				mon(mi) = 0
				SPRITE 13 + mi,SPRHID,0,0,0
			ELSE
				#mx(mi) = #mx(mi) + #vmxt(mdir(mi))
				#my(mi) = #my(mi) + #vmyt(mdir(mi))
				IF #my(mi) < 4096 THEN #my(mi) = #my(mi) + 40960
				IF #my(mi) >= 45056 THEN #my(mi) = #my(mi) - 40960
				mx8 = #mx(mi) / 256
				my8 = #my(mi) / 256

				' Colour says which kind it is, because they
				' behave completely differently and the player
				' has to know which one to respect: WHITE hunts
				' you, GREY is thrown wreckage.
				mcl = 14
				IF mgd(mi) = 1 THEN mcl = 15
				SPRITE 13 + mi,my8,mx8,44,mcl

				IF marm(mi) > 0 THEN marm(mi) = marm(mi) - 1

				' ONLY A STARSHIP'S MISSILE STEERS, and only every
				' fourth frame, so it curves rather than snapping
				' onto you. Debris flies dead straight -- it is
				' shrapnel, and shrapnel does not aim.
				IF mgd(mi) = 1 THEN
					mth = satt AND 3
					IF mth = 0 THEN
						px8 = mx8
						py8 = my8
						GOSUB dir_to_player
						IF gdir <> 255 THEN
							GOSUB step_toward_m
							mdir(mi) = sdir
						END IF
					END IF
				END IF

				' Debris can chain into another enemy from frame
				' one, but cannot touch the PLAYER until it has
				' cleared the wreck it came out of.
				IF marm(mi) = 0 THEN GOSUB coll_mis_player
				GOSUB coll_mis_enemy
			END IF
		END IF
	NEXT mi
	RETURN

	' step_toward reads edir(ei); missiles keep their heading in mdir, so this
	' entry point takes it in sdir directly rather than borrowing an enemy
	' slot. Kept separate because ei is live in the enemy loop.
step_toward_m:
	sdir = mdir(mi)
	IF sdir = gdir THEN RETURN
	stp = gdir - sdir
	stp = stp AND 15
	IF stp < 8 THEN
		sdir = sdir + 1
	ELSE
		sdir = sdir - 1
	END IF
	sdir = sdir AND 15
	RETURN

	' ----------------------------------------------------- missile vs player
	' The same two-radius rule as an enemy body: an ARMED field eats the
	' missile and is spent; without one, the hull is all there is.
coll_mis_player:
	IF dying > 0 THEN RETURN
	cdx = mx8 - shx8
	IF cdx > 127 THEN cdx = 0 - cdx
	IF cdx >= RAMR THEN RETURN
	IF my8 >= shy8 THEN
		cdy = my8 - shy8
	ELSE
		cdy = shy8 - my8
	END IF
	IF cdy > 80 THEN cdy = 160 - cdy
	IF cdy >= RAMR THEN RETURN

	IF shld = SHMAX THEN
		shld = 0
		shtk = 0
		SOUND 1,600,13 : sf1 = 10
		mon(mi) = 0
		SPRITE 13 + mi,SPRHID,0,0,0
		RETURN
	END IF
	IF cdx >= HULLR THEN RETURN
	IF cdy >= HULLR THEN RETURN
	dead = 1
	RETURN

	' ----------------------------------------------------- missile vs enemy
	' What makes a chain a chain. Tested x-first so the common case -- a
	' missile nowhere near this enemy -- costs a subtract and a compare.
coll_mis_enemy:
	mhit = 0
	FOR mj = 0 TO NENE - 1
		IF mhit = 0 THEN
		IF ety(mj) <> 0 THEN
			IF mon(mi) = 1 THEN
				mex = #ex(mj) / 256
				cdx = mex - mx8
				IF cdx > 127 THEN cdx = 0 - cdx
				IF cdx < 11 THEN
					mey = #ey(mj) / 256
					IF mey >= my8 THEN
						cdy = mey - my8
					ELSE
						cdy = my8 - mey
					END IF
					IF cdy > 80 THEN cdy = 160 - cdy
					IF cdy < 11 THEN
						mhit = 1
						mon(mi) = 0
						SPRITE 13 + mi,SPRHID,0,0,0
						' kill_enemy works on ei/ex8/ey8.
						' Clobbering ei is safe here: the
						' enemy loop has already finished
						' for this frame.
						ei = mj
						ex8 = mex
						ey8 = mey
						GOSUB kill_enemy
					END IF
				END IF
			END IF
		END IF
		END IF
	NEXT mj
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

	' ---------------------------------------------------------------- death
	' Reached by GOTO from the main loop with NO GOSUB frames outstanding, and
	' it leaves by GOTO to the title the same way. Phase 7 replaces this with
	' the original's sparking colour-cycle, which keeps the player in control
	' while the ship comes apart.
do_death:
	SOUND 0,,0
	SPRITE 1,SPRHID,0,0,0		' the field goes first
	SPRITE 2,SPRHID,0,0,0
	SPRITE 3,SPRHID,0,0,0
	SPRITE 4,SPRHID,0,0,0
	SOUND 3,6,13
	ddp = 48
	FOR ddi = 0 TO 2
		SPRITE 0,shy8,shx8,ddp,9
		FOR ddj = 0 TO 7
			WAIT
		NEXT ddj
		ddp = ddp + 4
	NEXT ddi
	SPRITE 0,SPRHID,0,0,0
	SOUND 3,,0
	FOR ddj = 0 TO 39
		WAIT
	NEXT ddj

	lives = lives - 1
	IF lives > 0 THEN GOTO respawn

	GOSUB prt_lives			' redraw an empty reserve row
	IF #score > #hisc THEN
		#hisc = #score
		GOSUB prt_hi
	END IF
	PRINT AT 293,"  G A M E   O V E R  "	' row 9 col 5: 21 chars, ends col 25
	FOR ddj = 0 TO 149
		WAIT
	NEXT ddj
	GOTO title_screen

	' -------------------------------------------------------------- sfx tick
	' EVERY latched channel needs an explicit note-off or the tone sustains
	' for ever. Ticked once per frame from the main loop.
	'
	' Channel 2 carries the two-note ARMED cue: the second, higher note is
	' fired from inside the countdown, because two SOUNDs on one channel back
	' to back simply cancel the first (CLAUDE.md 3A). Smaller divisor = higher
	' note, so 500 -> 375 rises.
sfx_tick:
	IF sf0 > 0 THEN
		sf0 = sf0 - 1
		IF sf0 = 0 THEN SOUND 0,,0
	END IF
	IF sf1 > 0 THEN
		sf1 = sf1 - 1
		IF sf1 = 0 THEN SOUND 1,,0
	END IF
	IF sf2 > 0 THEN
		sf2 = sf2 - 1
		IF sf2 = 6 THEN SOUND 2,375,9
		IF sf2 = 0 THEN SOUND 2,,0
	END IF
	IF sf3 > 0 THEN
		sf3 = sf3 - 1
		IF sf3 = 0 THEN SOUND 3,,0
	END IF
	RETURN

	' ---------------------------------------------------------- print lives
	' SPARES -- the reserves, EXCLUDING the life being flown. A fresh 3-ship
	' game shows two icons and the last ship shows none (CLAUDE.md 7A). At the
	' default of ONE ship the row is simply empty from the start, which is
	' correct and needs no special case.
	'
	' GUARD THE UNDERFLOW: this is called with lives = 0 on the last death,
	' and a bare `lives - 1` wraps to 255 in eight bits -- lighting every icon
	' at the exact moment the player has none.
prt_lives:
	spr = 0
	IF lives > 0 THEN spr = lives - 1
	#pla = 6176			' row 1, column 0
	FOR pli = 0 TO 8
		plv = 32
		IF pli < spr THEN plv = 131
		VPOKE #pla,plv
		#pla = #pla + 1
	NEXT pli
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
