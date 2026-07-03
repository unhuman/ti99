	' ============================================================
	' Ms. Pac-Man  -  CVBasic, faithful 1-shot port of the XB256
	' game (games/mspacman/src/MSPAC.ti99). Maze DATA reused verbatim.
	'
	' Translation notes:
	'  - XB M$() wall cache  -> VPEEK/VPOKE of the screen (VRAM $1800).
	'  - CALL LOCATE/SPRITE  -> SPRITE n, sy-2, sx-1, frame, colour.
	'  - TI colour N         -> CVBasic colour N-1.
	'  - Ghost target distance: XB used SG*dist with a signed compare;
	'    here a flee flag picks max (frightened) vs min (chase) distance,
	'    and (a-b)*(a-b) is computed in 16-bit (correct mod 65536).
	'  - Sound, title animation, the 8-3-8 cheat, the pellet blink and the
	'    death/level shrink animations are SIMPLIFIED (noted inline).
	'  - Sprite art is redrawn for CVBasic (the maze layouts are the
	'    faithful part). Coordinates keep the XB sx/sy math 1:1.
	'
	' Build (ONE source, dual target):
	'   TI-99/4A:     cvbasic --ti994a mspac.bas mspac.a99 -> xas99 -> linkticart
	'   ColecoVision: cvbasic mspac.bas mspac.asm          -> gasm80 -> mspac.rom
	' The maze lives only in VRAM (VPEEK/VPOKE); NO RAM mirror, so it fits the
	' ColecoVision's 1KB RAM. Same TMS9918A VDP + SN76489 sound as the TI-99.
	' ============================================================

	DEF FN scr(r, c) = $1800 + (r - 1) * 32 + (c - 1)

	' ============================================================
	' CROSS-PLATFORM SPEED: `hz` is the current machine's measured native main-
	' loop rate in ticks/sec -- REQUIRED at compile time (-Dhz=24 for TI-99,
	' -Dhz=60 for ColecoVision; see build.sh / build-coleco.sh). It is NEVER
	' declared with CONST in this source (that would collide with -D and fail
	' to compile) -- a build that forgets the flag fails LOUDLY at the first
	' cdN formula below ("not a constant expression in CONST"), not silently
	' at runtime.
	'
	' TI-99 measured 24fps (stable, after the DIV-to-AND pass below); Coleco
	' measured a full uncapped 60fps. Rather than throttle Coleco DOWN to
	' match the TI (the earlier approach), each machine now ticks at its own
	' native rate, and every duration originally tuned assuming hz=24 (the TI
	' reference) is rescaled: cdN = (N*hz+12)/24 -- MORE ticks needed to cover
	' the same real time at a faster tick rate. Exact identity at hz=24 (24
	' cancels), so the TI build is unaffected. Movement (Pac's sub-stepping,
	' ghost speed) isn't a simple duration -- see the accumulators in main:
	' and ghost: below.
	CONST cd90=(90*hz+12)/24         : CONST #cd150=(150*hz+12)/24
	CONST #cd210=(210*hz+12)/24      : CONST #cd200=(200*hz+12)/24
	CONST cd16fb=(16*hz+12)/24       : CONST cd40=(40*hz+12)/24
	CONST cd8pew=(8*hz+12)/24        : CONST #cd800=(800*hz+12)/24
	CONST #cd400=(400*hz+12)/24      : CONST cd6=(6*hz+12)/24
	CONST cd1=(1*hz+12)/24           : CONST cd2=(2*hz+12)/24
	CONST #cd180=(180*hz+12)/24

	DEFINE CHAR 128,16,wall_tiles
	DEFINE CHAR 144,1,dot_tile
	DEFINE CHAR 152,1,pellet_tile
	DEFINE CHAR 160,1,door_tile
	DEFINE CHAR 168,1,cross_tile
	DEFINE COLOR 128,16,wall_color
	DEFINE COLOR 144,1,white_color
	DEFINE COLOR 152,1,white_color
	DEFINE COLOR 160,1,white_color
	DEFINE COLOR 168,1,wall_color
	DEFINE SPRITE 0,11,game_sprites		' 0-9 Pac/ghost/eyes/fruit; 10 = ghost walk frame 2

	DIM gx(5), gy(5), gd(5), op(5), rt(5), gs(5), gc(5), sp(5), sr(5), sc(5), gcl(5)
	DIM #spcd(5)	' 16-bit: rate-accumulator values reach into the thousands at hz=60
	DIM #tm(5)		' widened to 16-bit: rescaled Coleco values (up to ~525) exceed 8-bit
	DIM #ds(5)
	DIM spc(5)		' per-ghost speed caps (fixed Blinky>Pinky>Inky>Clyde ranking)

	BORDER 1
	SPRITE FLICKER ON		' rotate sprites so >4 on a scanline degrade gracefully (no full vanish)
	gc(1) = 6 : gc(2) = 13 : gc(3) = 7 : gc(4) = 10	' needed by the title too
	spc(1) = 40 : spc(2) = 16 : spc(3) = 12 : spc(4) = 10	' caps: Blinky 100%, Pinky ~94%, Inky ~92%, Clyde ~90%

	GOSUB title

boot:
	' XB 157
	sx = 121 : sy = 141 : dd = 0 : #pt = 0 : ec = 0 : rg = 0 : nx = 0 : bg = 0
	SOUND 0, , 0 : SOUND 1, , 0 : SOUND 2, , 0 : sfx = 0	' silence any leftover sound on (re)start
	GOSUB pickmaze
	GOSUB drawmaze

	' XB 165-170 ghost / state init
	gx(1) = 121 : gy(1) = 77 : gd(1) = 4
	gx(2) = 121 : gy(2) = 93 : gd(2) = 4
	gx(3) = 105 : gy(3) = 93 : gd(3) = 4
	gx(4) = 137 : gy(4) = 93 : gd(4) = 4
	rt(1) = 0 : rt(2) = 8 : rt(3) = 16 : rt(4) = 24
	sp(1) = 9 : sp(2) = 8 : sp(3) = 7 : sp(4) = 6	' base speeds, distinct ranking (capped per ghost by spc())
	#spcd(1) = 0 : #spcd(2) = 0 : #spcd(3) = 0 : #spcd(4) = 0
	cd = 3 : hd = 3
	#tm(1) = 0 : #tm(2) = cd90 : #tm(3) = #cd150 : #tm(4) = #cd210 : #fc = 0
	gc(1) = 6 : gc(2) = 13 : gc(3) = 7 : gc(4) = 10	' TI 7,14,8,11 -> CV 6,13,7,10
	#ft = 0 : eg = 0 : dg = 0 : fa = 0 : fn = 0 : #fb = #cd180 : mo = 0 : #mt = #cd150
	GOSUB fruitdef
	FOR j = 1 TO 4
		sp(j) = sp(j) + (le - 1) * 4
		IF sp(j) > spc(j) THEN sp(j) = spc(j)	' per-ghost cap (Blinky reaches 40=100%, others lower)
	NEXT j
	' Force 16-bit: (le-1)*cd16fb can reach ~800 at hz=60, which would
	' silently truncate if computed as an 8-bit multiply (le and cd16fb both
	' fit 8 bits individually) -- assign to a 16-bit scratch var FIRST so the
	' multiply itself runs in 16-bit space (same pattern used for #dd1/#dd2
	' elsewhere in this file).
	#dd1 = le - 1 : #dd1 = #dd1 * cd16fb
	#fb = #cd200 - #dd1		' fright shrinks per level (rescaled)
	IF #fb < cd40 THEN #fb = cd40
	sr(1) = 1 : sc(1) = 30 : sr(2) = 1 : sc(2) = 3
	sr(3) = 26 : sc(3) = 30 : sr(4) = 26 : sc(4) = 3
	GOSUB hud
	GOSUB startjingle
	GOSUB ready

main:
	WHILE 1
		WAIT
		' No artificial pacing cap: each machine ticks at whatever its own
		' hardware naturally sustains for this workload -- TI-99 lands at a
		' measured, stable 24fps (its own per-frame cost, not a throttle);
		' ColecoVision (faster Z80) hits a full uncapped 60fps. Earlier
		' revisions capped Coleco down to match the TI's rate; now every
		' frame-counted duration/movement rate is instead rescaled from `hz`
		' (see the CONST block and the pacacc/gtacc/#spcd accumulators below)
		' so real-world game speed matches while Coleco keeps its own native,
		' smoother tick rate.
		' TMS9900 has no fast divide: CVBasic compiles EVERY "%" (even by a
		' constant power of 2) to a real DIV instruction, one of the slowest
		' ops on this CPU -- there's no compiler-side AND-conversion. #fc%8
		' was being recomputed via DIV up to 5x/tick (Pac's chomp frame, plus
		' once per ghost's walk-cycle check) for the SAME #fc value (unchanged
		' until the increment near the end of this tick). Compute it ONCE
		' here as a cheap AND and reuse below.
		fc8 = #fc AND 7
		' Ghost "half speed" rate (tunnel throttle + Cruise Elroy bonus pass)
		' was "fire when #fc is even" -- a flat 50%-of-ticks rate, correct
		' only at the TI's reference 24Hz. Same phase-accumulator idea as
		' Pac's sub-stepping above, but computed ONCE per tick (not per ghost,
		' or it would drift 4x faster) and shared by both call sites below,
		' matching the original design where every ghost read the SAME
		' tick-global fc2 signal. Target rate = 12/sec (half of 24) at any hz.
		gtacc = gtacc + 12
		gtslow = 0
		IF gtacc >= hz THEN gtacc = gtacc - hz : gtslow = 1
		FOR dk = ng + 1 TO 4 : SPRITE dk, $d1, 0, 0, 0 : NEXT dk	' hide ghosts above ng (set via 8-3-8)
		ea = 0

		' --- input (joystick) ---
		IF cont1.up THEN dd = 1
		IF cont1.down THEN dd = 2
		IF cont1.left THEN dd = 3
		IF cont1.right THEN dd = 4

		' instant reverse (XB 311)
		IF ((cd=1) AND (dd=2)) OR ((cd=2) AND (dd=1)) OR ((cd=3) AND (dd=4)) OR ((cd=4) AND (dd=3)) THEN cd = dd

		' Was "always run 2 pacstep (1px) sub-steps every tick" -- fine on the
		' TI (24 ticks/sec * 2 = 48 sub-steps/sec, matching Pac's classic
		' speed), but on Coleco's 60 ticks/sec that would make Pac move 2.5x
		' too fast. Rather than THROTTLE Coleco down to 24 ticks/sec (which
		' would just reproduce the TI's 2px-every-~2.5-ticks choppiness at a
		' technically higher rate -- no real smoothness gain), a phase
		' accumulator spreads the SAME 48 sub-steps/sec across however many
		' ticks/sec this machine actually has: acc+=48 each tick, fire one
		' pacstep (1px) per hz consumed. At hz=24 this fires exactly twice
		' every tick (48>=24 twice), reproducing the original TI behavior
		' exactly. At hz=60 it fires ~0.8 times/tick (mostly 1 sub-step per
		' tick, occasionally 0) -- same 48px/sec average speed, but genuinely
		' smoother 1px-at-a-time motion instead of TI's 2px hops.
		pacacc = pacacc + 48
		WHILE pacacc >= hz
			pacacc = pacacc - hz
			GOSUB pacstep
		WEND

		' tunnel wrap (XB 411-412)
		IF sx < 13 THEN sx = 229
		IF sx > 229 THEN sx = 13

		IF cd <> 0 THEN hd = cd

		' Pac frame (XB 421-424)
		pf = 0
		IF hd = 1 THEN pf = 8
		IF hd = 2 THEN pf = 12
		IF hd = 3 THEN pf = 4
		chmp = 0
		IF cd <> 0 THEN IF fc8 >= 4 THEN chmp = 1
		IF chmp = 1 THEN pf = 16			' closed (right/down)
		IF (chmp = 1) AND (hd = 3) THEN pf = 32		' left-closed (bow stays)
		IF (chmp = 1) AND (hd = 1) THEN pf = 36		' up-closed (bow stays at bottom)
		SPRITE 0, sy - 2, sx - 1, pf, 11		' Pac, TI 12 -> CV 11

		pr = (sy + 11) / 8 : pc = (sx + 11) / 8

		' ghosts (ne is set inside the routine if any ghost is 'eyes')
		ne = 0
		FOR gi = 1 TO ng
			GOSUB ghost
		NEXT gi

		' dead-ghost eyes return to the pen at double speed -- only run when some exist
		IF ne = 1 THEN
			xp = 2
			FOR gi = 1 TO ng
				IF gs(gi) = 2 THEN GOSUB ghost
			NEXT gi
			xp = 0
		END IF

		' ghost overdrive: extra move pass at high levels (faster than Ms. Pac-Man)
		IF le > 9 THEN
			ov = ov + (le - 9) * 2
			IF ov >= 16 THEN
				ov = 0
				xp = 1
				FOR gi = 1 TO ng : GOSUB ghost : NEXT gi
				xp = 0
			END IF
		END IF

		' Cruise Elroy: Blinky (ghost 1) closes in as the maze empties
		IF dt < 30 THEN
			xp = 1
			gi = 1
			IF dt < 10 THEN
				GOSUB ghost
			ELSE
				IF gtslow = 1 THEN GOSUB ghost
			END IF
			xp = 0
		END IF

		' Pac <-> ghost collision is now folded into the ghost routine (see gh_draw)

		' bonus life at 1000 pts (XB 430; PT is /10)
		IF #pt >= 1000 THEN IF bg = 0 THEN GOSUB bonuslife	' extra life at 10000 points

		IF #fc < 30000 THEN #fc = #fc + 1
		' transient sound-effect timer (CVBasic SOUND plays until silenced)
		IF sfx > 0 THEN
			sfx = sfx - 1
			IF sfx = 0 THEN SOUND 0, , 0
		END IF
		' eye 'pew' sweep on channel 1
		IF pew > 0 THEN
			pew = pew - 1
			IF pew = 0 THEN SOUND 1, , 0 ELSE SOUND 1, 40 + (8 - pew) * 15, 11
		END IF
		IF #ft > 0 THEN #ft = #ft - 1
		' blink the energizers (power pellets, char 152). #fc was JUST
		' incremented above, so this reads the post-increment value (a fresh
		' AND, not fc8/fc2 from the top of the tick, which are pre-increment)
		' -- same DIV-avoidance, exact original phase preserved.
		fc16b = #fc AND 15
		IF fc16b = 0 THEN DEFINE CHAR 152,1,pellet_tile
		IF fc16b = 8 THEN DEFINE CHAR 152,1,blank_tile

		' roaming fruit (XB 433-434)
		IF fa = 1 THEN IF (#fc % 3) = 0 THEN GOSUB movefruit
		IF fa = 1 THEN
			SPRITE 5, fwb, fx - 1, 28, ffl		' re-issue every frame so it doesn't strobe
			IF sx >= fx THEN dx = sx - fx ELSE dx = fx - sx
			IF sy >= fy THEN dy = sy - fy ELSE dy = fy - sy
			IF dx < 8 THEN IF dy < 8 THEN IF (dx + dy) < 8 THEN GOSUB eatfruit
		END IF

		IF rg = 1 THEN GOTO boot
		IF nx = 1 THEN GOSUB nextlevel

		' scatter / chase mode timer (XB 439)
		IF #mt > 0 THEN
			#mt = #mt - 1
		ELSE
			GOSUB modeswitch
		END IF
	WEND

	' ============================================================
	' Ms. Pac-Man one 1px sub-step (XB 350-392), with cornering.
	' ============================================================
pacstep:	PROCEDURE
	ax = sx + 3 : ay = sy + 3
	xc = ax AND 7 : yc = ay AND 7
	IF xc = 0 THEN IF yc = 0 THEN GOTO ps_aligned
	GOTO ps_corner

ps_aligned:
	c = (sx + 11) / 8 : r = (sy + 11) / 8
	GOSUB eat
	tr = r : tc = c
	IF dd = 1 THEN tr = r - 1
	IF dd = 2 THEN tr = r + 1
	IF dd = 3 THEN tc = c - 1
	IF dd = 4 THEN tc = c + 1
	IF dd <> 0 THEN
		GOSUB wallchk
		IF wl = 0 THEN cd = dd
	END IF
	tr = r : tc = c
	IF cd = 1 THEN tr = r - 1
	IF cd = 2 THEN tr = r + 1
	IF cd = 3 THEN tc = c - 1
	IF cd = 4 THEN tc = c + 1
	IF cd <> 0 THEN
		GOSUB wallchk
		IF wl = 1 THEN cd = 0
	END IF
	GOTO ps_move

ps_corner:
	prp = 0
	IF ((cd=3) OR (cd=4)) AND ((dd=1) OR (dd=2)) THEN prp = 1
	IF ((cd=1) OR (cd=2)) AND ((dd=3) OR (dd=4)) THEN prp = 1
	IF prp = 0 THEN GOTO ps_move
	jd = 8 - xc
	IF cd = 3 THEN jd = xc
	IF cd = 1 THEN jd = yc
	IF cd = 2 THEN jd = 8 - yc
	IF jd < 1 THEN GOTO ps_move
	IF jd > 2 THEN GOTO ps_move
	sxc = sx : syc = sy
	IF cd = 4 THEN sxc = sx + jd
	IF cd = 3 THEN sxc = sx - jd
	IF cd = 2 THEN syc = sy + jd
	IF cd = 1 THEN syc = sy - jd
	rc = (syc + 11) / 8 : cc = (sxc + 11) / 8
	tr = rc : tc = cc
	IF dd = 1 THEN tr = rc - 1
	IF dd = 2 THEN tr = rc + 1
	IF dd = 3 THEN tc = cc - 1
	IF dd = 4 THEN tc = cc + 1
	GOSUB wallchk
	IF wl = 1 THEN GOTO ps_move
	c = cc : r = rc
	GOSUB eat
	ea = 0
	IF cd = 4 THEN sx = sx + jd
	IF cd = 3 THEN sx = sx - jd
	IF cd = 2 THEN sy = sy + jd
	IF cd = 1 THEN sy = sy - jd
	IF dd = 1 THEN sy = sy - jd
	IF dd = 2 THEN sy = sy + jd
	IF dd = 3 THEN sx = sx - jd
	IF dd = 4 THEN sx = sx + jd
	cd = dd
	RETURN

ps_move:
	IF ea = 1 THEN RETURN
	IF cd = 0 THEN RETURN
	IF cd = 1 THEN sy = sy - 1
	IF cd = 2 THEN sy = sy + 1
	IF cd = 3 THEN sx = sx - 1
	IF cd = 4 THEN sx = sx + 1
	END

	' --- wall check incl. pen rows (XB 700) : in tr,tc out wl ---
wallchk:	PROCEDURE
	wl = 0
	IF tc < 1 THEN wl = 1
	IF tc > 32 THEN wl = 1
	IF tr < 1 THEN wl = 1
	IF tr > 24 THEN wl = 1
	IF wl = 1 THEN RETURN
	g = VPEEK(scr(tr, tc))
	IF g > 127 THEN IF g < 144 THEN wl = 1
	IF tr = 12 THEN IF tc > 15 THEN IF tc < 18 THEN wl = 1
	IF tr = 13 THEN IF tc > 13 THEN IF tc < 20 THEN wl = 1
	END

	' --- wall check for ghosts (XB 760) ---
wallchk2:	PROCEDURE
	wl = 0
	IF tc < 1 THEN wl = 1
	IF tc > 32 THEN wl = 1
	IF tr < 1 THEN wl = 1
	IF tr > 24 THEN wl = 1
	IF wl = 1 THEN RETURN
	g = VPEEK(scr(tr, tc))
	IF g > 127 THEN IF g < 144 THEN wl = 1
	IF tr = 12 THEN IF tc > 15 THEN IF tc < 18 THEN wl = 1
	END

	' --- openness mask at r,c, read from VRAM (was om[]; XB wallchk2 rule) ---
openmask:	PROCEDURE
	mk = 0
	g = VPEEK(scr(r, c))
	IF (g < 128) OR (g > 143) THEN
		g = VPEEK(scr(r - 1, c))
		IF (g < 128) OR (g > 143) THEN
			IF (r <> 13) OR (c <= 15) OR (c >= 18) THEN mk = 1
		END IF
		g = VPEEK(scr(r + 1, c))
		IF (g < 128) OR (g > 143) THEN
			IF (r <> 11) OR (c <= 15) OR (c >= 18) THEN mk = mk + 2
		END IF
		g = VPEEK(scr(r, c - 1))
		IF (g < 128) OR (g > 143) THEN
			IF (r <> 12) OR (c <= 16) OR (c >= 19) THEN mk = mk + 4
		END IF
		g = VPEEK(scr(r, c + 1))
		IF (g < 128) OR (g > 143) THEN
			IF (r <> 12) OR (c <= 14) OR (c >= 17) THEN mk = mk + 8
		END IF
	END IF
	END

	' --- eat dot/pellet on cell r,c (XB 750) ---
eat:	PROCEDURE
	g = VPEEK(scr(r, c))
	IF g <> 144 THEN IF g <> 152 THEN RETURN
	ea = 1
	#pt = #pt + 1
	ec = ec + 1
	IF g = 152 THEN
		#pt = #pt + 4
		GOSUB frighten
	END IF
	VPOKE scr(r, c), 32
	dt = dt - 1
	IF g = 144 THEN
		wk = 1 - wk
		IF wk = 0 THEN SOUND 0, 150, 9 ELSE SOUND 0, 200, 9
		sfx = cd1
	END IF
	IF fa = 0 THEN IF fn < 2 THEN IF (dt = 154) OR (dt = 54) THEN GOSUB spawnfruit
	IF dt = 0 THEN nx = 1
	GOSUB hud			' refresh score only when it changes
	END

	' --- power pellet: frighten ghosts (XB 774-779) ---
frighten:	PROCEDURE
	FOR gj = 1 TO 4
		' reverse ghosts in chase/scatter (not already scared, not eyes)
		IF (gs(gj) = 0) AND (gx(gj) <> 121) AND (gy(gj) <> 77) THEN
			IF gd(gj)=1 THEN gd(gj)=2 ELSE IF gd(gj)=2 THEN gd(gj)=1 ELSE IF gd(gj)=3 THEN gd(gj)=4 ELSE gd(gj)=3
		END IF
		IF gs(gj) <> 2 THEN gs(gj) = 1
	NEXT gj
	#ft = #fb
	eg = 0
	' power-pellet 'power up' rising sweep
	FOR dr = 1 TO 10
		SOUND 0, 210 - dr * 11, 13
		WAIT
	NEXT dr
	SOUND 0, , 0
	END

	' --- one ghost (XB 999-1052) : gi global ---
ghost:	PROCEDURE
	IF rg = 1 THEN RETURN		' game over: don't move/draw ghosts (sprites stay cleared)
	gsi = gs(gi)			' load this ghost's state into a scalar ONCE; hot path reads gsi, not gs(gi)
	IF (dg = gi) AND (gsi <> 0) THEN dg = 0
	IF (gsi = 1) AND (#ft = 0) THEN gs(gi) = 0 : gsi = 0

	bx = gx(gi) : by = gy(gi) : bd = gd(gi)
	' overdrive extra pass: only chasing ghosts in the open (not fright/eyes/tunnel)
	IF xp = 1 THEN
		IF gsi <> 0 THEN GOTO gh_draw_only
		IF ((by = ty1) OR (by = ty2)) AND ((bx < 45) OR (bx > 197)) THEN GOTO gh_draw_only
	END IF
	' speed throttle (XB 1006-1007): half-speed in fright/tunnel. gtslow
	' reuses the tick-global rate flag computed once at the top of the tick
	' (see main:) -- fires at 12/sec regardless of hz, replacing the old flat
	' "#fc even" check that only gave 12/sec at the TI's reference 24Hz.
	IF (gsi = 1) OR (((by=ty1) OR (by=ty2)) AND ((bx<45) OR (bx>197))) THEN
		IF gtslow = 0 THEN GOTO gh_draw_only
	END IF
	' Was "IF (#fc % sp(gi)) = 0 THEN skip" -- move on (sp(gi)-1) ticks out of
	' every sp(gi), i.e. real-world speed = 24*(sp(gi)-1)/sp(gi) at the TI's
	' reference 24Hz. Naive fixes both fail: (a) a DIV by sp(gi) (a runtime
	' variable, can't become an AND) is one of the slowest TMS9900 ops, done
	' up to 3x/tick; (b) just scaling sp(gi) by hz/24 barely moves the skip
	' FRACTION (already close to 1) while the raw tick rate itself already
	' tripled -- verified by hand this leaves Coleco's ghosts far too fast
	' (e.g. sp=8: 21 moves/sec intended vs ~57 actual with naive scaling).
	' Correct fix: a per-ghost rate accumulator with NUM=24*(sp(gi)-1),
	' DEN=hz*sp(gi) -- algebraically NUM/DEN=(sp(gi)-1)/sp(gi) exactly at
	' hz=24 (the 24 cancels), so this is an EXACT identity on the TI; at any
	' other hz it reproduces the SAME real-world moves/sec by construction.
	' #gn/#gd are computed via 16-bit-forced multiplies (cheap MPY, not a
	' slow DIV) fresh each check -- sp(gi) rarely changes (once per level),
	' so this is far cheaper than the division it replaces either way. (The
	' original had a "sp(gi)<40 skip the check entirely" bypass at the
	' 100%-speed cap, purely to dodge the DIV it no longer needs to dodge --
	' removed so max-speed Blinky is ALSO correctly hz-scaled on Coleco;
	' the accumulator's 39/40 fire rate at sp=40 is indistinguishable from
	' the old "always move" bypass on the TI anyway.)
	IF gsi = 0 THEN
		#gn = sp(gi) : #gn = (#gn - 1) * 24
		#gd = sp(gi) : #gd = #gd * hz
		#spcd(gi) = #spcd(gi) + #gn
		IF #spcd(gi) < #gd THEN
			GOTO gh_draw_only
		ELSE
			#spcd(gi) = #spcd(gi) - #gd
		END IF
	END IF

	' pen entry / exit (XB 1008-1011) -- only ever fires on the two pen rows
	IF (by = 77) OR (by = 93) THEN
		rl = 0
		IF ec >= rt(gi) THEN rl = 1
		IF #fc >= #tm(gi) THEN rl = 1
		IF (bx=121) AND (by=93) THEN
			IF (gsi=2) OR ((rl=1) AND (gsi=0) AND ((dg=0) OR (dg=gi))) THEN GOTO gh_pen
		END IF
		IF (rl=1) AND ((gsi=0) OR (dg=gi)) AND (bx=121) AND (by=77) AND (bd=1) THEN
			bd = RANDOM(2) + 3
			dg = 0
			GOTO gh_move
		END IF
		IF (gsi=2) AND (bx=121) AND (by=77) THEN bd = 2 : GOTO gh_move
		IF (gsi=2) AND (bx=117) AND (by=77) THEN bd = 4 : GOTO gh_move
	END IF

	ax = bx + 3 : ay = by + 3
	IF (ax AND 7) <> 0 THEN GOTO gh_move
	IF (ay AND 7) <> 0 THEN GOTO gh_move

	' choose direction toward target (XB 1015-1035)
	c = (bx + 11) / 8 : r = (by + 11) / 8
	rev = 0
	IF bd = 1 THEN rev = 2
	IF bd = 2 THEN rev = 1
	IF bd = 3 THEN rev = 4
	IF bd = 4 THEN rev = 3
	GOSUB gtarget
	ct = 0
	IF flee = 0 THEN #bs = 60000 ELSE #bs = 0
	GOSUB openmask		' openness mask: 1 read replaces 4 wallchk2 calls
	bv = 1					' bit value for the current dr (1,2,4,8); doubles each pass
	FOR dr = 1 TO 4
		IF dr <> rev THEN
			tr = r : tc = c
			IF dr = 1 THEN tr = r - 1
			IF dr = 2 THEN tr = r + 1
			IF dr = 3 THEN tc = c - 1
			IF dr = 4 THEN tc = c + 1
			wl = 1
			IF (mk AND bv) <> 0 THEN wl = 0
			IF wl = 0 THEN
				#dd1 = tr - #tgr : #dd2 = tc - #tgc
				#qd = #dd1 * #dd1 + #dd2 * #dd2		' squared Euclidean
				IF flee = 0 THEN
					IF #qd < #bs THEN #bs = #qd : bd = dr : ct = 1
				ELSE
					IF #qd > #bs THEN #bs = #qd : bd = dr : ct = 1
				END IF
			END IF
		END IF
		bv = bv * 2
	NEXT dr
	' dead-end: only non-reverse option blocked -> reverse (chase only)
	IF (ct = 0) AND (rev > 0) AND (flee = 0) THEN
		bvr = 1
		IF rev = 2 THEN bvr = 2
		IF rev = 3 THEN bvr = 4
		IF rev = 4 THEN bvr = 8
		IF (mk AND bvr) <> 0 THEN bd = rev : ct = 1
	END IF
	IF ct = 0 THEN bd = 0

gh_move:
	IF bd = 1 THEN by = by - 2 ELSE IF bd = 2 THEN by = by + 2 ELSE IF bd = 3 THEN bx = bx - 2 ELSE IF bd = 4 THEN bx = bx + 2
	IF bx < 13 THEN bx = 229
	IF bx > 229 THEN bx = 13
	IF bx = 121 THEN
		IF (gsi <> 1) OR (dg = gi) THEN
			IF (bd=1) AND (by<77) THEN by = 77 : bd = 2		' normal/eyes/exiter: climb to the door
		ELSE
			IF (bd=1) AND (by<89) THEN by = 89 : bd = 2		' frightened waiter: bounce low, in the pen
		END IF
		IF (bd=2) AND (by>93) THEN by = 93 : bd = 1
	END IF
	IF (gsi = 2) AND (bd <> gd(gi)) THEN pew = cd8pew	' eye changed direction -> 'pew'
	gx(gi) = bx : gy(gi) = by : gd(gi) = bd
	GOTO gh_draw

gh_pen:
	IF gsi = 2 THEN gs(gi) = 0 : gsi = 0
	dg = gi : bd = 1
	GOTO gh_move

gh_draw_only:
	bx = gx(gi) : by = gy(gi)
gh_draw:
	' colour + frame from state
	gcx = gc(gi) : gfr = 20
	IF fc8 >= 4 THEN gfr = 40		' ghost walk-cycle: alternate frame (fc8 reused from top of tick)
	IF gsi = 1 THEN
		gcx = 4
		IF #ft <= 48 THEN IF (#ft AND 7) < 4 THEN gcx = 15
	END IF
	IF gsi = 2 THEN gcx = 15 : gfr = 24 : ne = 1	' ne flags that eyes exist this frame
	SPRITE gi, by - 2, bx - 1, gfr, gcx
	' Pac <-> ghost collision, folded in here (normal pass only; uses bx/by scalars)
	IF xp = 0 THEN
		IF sx >= bx THEN dx = sx - bx ELSE dx = bx - sx
		IF sy >= by THEN dy = sy - by ELSE dy = by - sy
		IF dx < 8 THEN IF dy < 8 THEN IF (dx + dy) < 8 THEN GOSUB collide
	END IF
	END

	' --- ghost target tile (XB 1180-1194) : out #tgr,#tgc,flee ---
gtarget:	PROCEDURE
	flee = 0
	#tgr = pr : #tgc = pc
	IF gsi = 1 THEN flee = 1 : RETURN
	IF gsi = 2 THEN #tgr = 11 : #tgc = 16 : RETURN
	IF mo = 0 THEN #tgr = sr(gi) : #tgc = sc(gi) : RETURN
	IF (gi=2) AND (cd=1) THEN #tgr = pr - 4
	IF (gi=2) AND (cd=2) THEN #tgr = pr + 4
	IF (gi=2) AND (cd=3) THEN #tgc = pc - 4
	IF (gi=2) AND (cd=4) THEN #tgc = pc + 4
	IF gi = 4 THEN
		#dd1 = r : #dd1 = #dd1 - pr : #dd2 = c : #dd2 = #dd2 - pc
		IF (#dd1*#dd1 + #dd2*#dd2) <= 64 THEN #tgr = sr(4) : #tgc = sc(4)
	END IF
	IF gi <> 3 THEN RETURN
	r2 = pr : c2 = pc
	IF cd = 1 THEN r2 = pr - 2
	IF cd = 2 THEN r2 = pr + 2
	IF cd = 3 THEN c2 = pc - 2
	IF cd = 4 THEN c2 = pc + 2
	#tgr = 2 * r2 - (gy(1) + 11) / 8
	#tgc = 2 * c2 - (gx(1) + 11) / 8
	END

	' --- Pac caught / ate ghost dispatch (XB 780-782) ---
collide:	PROCEDURE
	IF gs(gi) = 0 THEN
		c = (sx + 11) / 8 : r = (sy + 11) / 8
		IF VPEEK(scr(r, c)) = 152 THEN GOSUB eat
	END IF
	IF gs(gi) = 1 THEN
		GOSUB eatghost
	ELSE
		IF gs(gi) = 0 THEN GOSUB pacdies
	END IF
	END

	' --- eat a frightened ghost (XB 790-798) ---
eatghost:	PROCEDURE
	IF eg = 0 THEN #pt = #pt + 20
	IF eg = 1 THEN #pt = #pt + 40
	IF eg = 2 THEN #pt = #pt + 80
	IF eg = 3 THEN #pt = #pt + 160
	eg = eg + 1
	gs(gi) = 2
	GOSUB hud
	FOR dr = 1 TO 8			' descending "ate a ghost" sweep
		SOUND 0, 60 + dr * 14, 13
		WAIT : WAIT
	NEXT dr
	SOUND 0, , 0
	END

	' --- bonus life (XB 785-787) ---
bonuslife:	PROCEDURE
	bg = 1
	lv = lv + 1
	GOSUB hud
	FOR i = 1 TO 3				' three bells for the extra life
		SOUND 0, 96, 13
		FOR dr = 1 TO 5 : WAIT : NEXT dr
		SOUND 0, , 0
		FOR dr = 1 TO 3 : WAIT : NEXT dr
	NEXT i
	END

	' --- Pac dies (XB 1100-1118) ; simplified animation ---
pacdies:	PROCEDURE
	' capture: silence sound, freeze ~1s showing the actors, THEN run the death sequence
	SOUND 0, , 0 : SOUND 1, , 0 : SOUND 2, , 0
	GOSUB ready
	' death: hide the ghosts, spin Ms. Pac-Man with a descending tone, vanish
	FOR j = 1 TO 4 : SPRITE j, $d1, 0, 0, 0 : NEXT j
	FOR dr = 0 TO 23
		WAIT : WAIT
		pf = 0
		m = dr % 4
		IF m = 1 THEN pf = 12
		IF m = 2 THEN pf = 4
		IF m = 3 THEN pf = 8
		SPRITE 0, sy - 2, sx - 1, pf, 11
		SOUND 0, 120 + dr * 24, 13
	NEXT dr
	SOUND 0, , 0
	SPRITE 0, $d1, 0, 0, 0
	IF fa = 1 THEN gosub killfruit
	lv = lv - 1
	IF lv > 0 THEN GOTO pd_respawn

	' game over
	PRINT AT 10 * 32 + 10, "           "
	PRINT AT 11 * 32 + 10, " GAME OVER "
	PRINT AT 12 * 32 + 10, "           "
	#c = FRAME
	DO
		WAIT
	LOOP WHILE FRAME - #c < 180
	GOSUB title
	rg = 1
	RETURN

pd_respawn:
	gx(1) = 121 : gy(1) = 77 : gx(2) = 121 : gy(2) = 93
	gx(3) = 105 : gy(3) = 93 : gx(4) = 137 : gy(4) = 93
	FOR j = 1 TO 4
		gs(j) = 0 : gd(j) = 4 : #spcd(j) = 0
	NEXT j
	sx = 121 : sy = 141 : dd = 0 : cd = 3 : hd = 3
	#ft = 0 : eg = 0 : ec = 0 : #fc = 0 : dg = 0
	GOSUB hud
	GOSUB ready
	END

killfruit:	PROCEDURE
	SPRITE 5, $d1, 0, 28, 0
	fa = 0
	END

	' --- advance to next level (XB 1130-1145) ; simplified ---
nextlevel:	PROCEDURE
	nx = 0
	le = le + 1
	SOUND 0, , 0 : SOUND 1, , 0 : SOUND 2, , 0 : sfx = 0	' kill any ongoing sound (no beep during the flash)
	IF fa = 1 THEN GOSUB killfruit
	GOSUB clearsprites		' remove all sprites before the flash
	' flash the cleared maze walls (white <-> normal) a few times
	FOR dr = 1 TO 4
		DEFINE COLOR 128,16,wall_white
		FOR j = 1 TO 8 : WAIT : NEXT j
		GOSUB setwc
		FOR j = 1 TO 8 : WAIT : NEXT j
	NEXT dr
	FOR j = 1 TO 4
		sp(j) = sp(j) + 4
		IF sp(j) > spc(j) THEN sp(j) = spc(j)	' per-ghost cap (Blinky reaches 40=100%, others lower)
	NEXT j
	' Force 16-bit: (le-1)*cd16fb can reach ~800 at hz=60, which would
	' silently truncate if computed as an 8-bit multiply (le and cd16fb both
	' fit 8 bits individually) -- assign to a 16-bit scratch var FIRST so the
	' multiply itself runs in 16-bit space (same pattern used for #dd1/#dd2
	' elsewhere in this file).
	#dd1 = le - 1 : #dd1 = #dd1 * cd16fb
	#fb = #cd200 - #dd1		' fright shrinks per level (rescaled)
	IF #fb < cd40 THEN #fb = cd40
	GOSUB fruitdef
	GOSUB pickmaze
	GOSUB drawmaze
	gx(1) = 121 : gy(1) = 77 : gx(2) = 121 : gy(2) = 93
	gx(3) = 105 : gy(3) = 93 : gx(4) = 137 : gy(4) = 93
	FOR j = 1 TO 4
		gs(j) = 0 : gd(j) = 4 : #spcd(j) = 0
	NEXT j
	sx = 121 : sy = 141 : dd = 0 : cd = 3 : hd = 3
	#ft = 0 : eg = 0 : ec = 0 : #fc = 0 : dg = 0 : fa = 0 : fn = 0 : mo = 0 : #mt = #cd150
	GOSUB hud
	END

	' --- scatter/chase toggle + reverse (XB 1170-1176) ---
modeswitch:	PROCEDURE
	mo = 1 - mo
	#mt = #cd800
	IF mo = 0 THEN #mt = #cd150
	FOR j = 1 TO 4
		IF (gs(j)=0) AND (gx(j)<>121) AND (gy(j)<>77) THEN
			IF gd(j)=1 THEN gd(j)=2 ELSE IF gd(j)=2 THEN gd(j)=1 ELSE IF gd(j)=3 THEN gd(j)=4 ELSE gd(j)=3
		END IF
	NEXT j
	END

	' --- spawn roaming fruit (XB 720-726) ---
spawnfruit:	PROCEDURE
	fn = fn + 1 : fa = 1 : #fw = 0
	IF RANDOM(2) = 1 THEN fy = ty2 : tg = ty1 ELSE fy = ty1 : tg = ty2
	IF RANDOM(2) = 1 THEN fx = 229 : fd = 3 : ftc = 3 ELSE fx = 13 : fd = 4 : ftc = 30
	ftr = (tg + 11) / 8
	fwb = fy - 2				' init draw-Y so the per-frame draw is valid pre-move
	SPRITE 5, fy - 2, fx - 1, 28, ffl
	END

	' --- move roaming fruit (XB 730-743) ---
movefruit:	PROCEDURE
	#fw = #fw + 1
	IF (#fw % cd6) = 0 THEN
		SOUND 0, 186, 7			' soft blip as the fruit roams
		sfx = cd2
	END IF
	bx = fx : by = fy : bd = fd
	ax = bx + 3 : ay = by + 3
	IF (ax AND 7) <> 0 THEN GOTO mf_step
	IF (ay AND 7) <> 0 THEN GOTO mf_step
	c = (bx + 11) / 8 : r = (by + 11) / 8
	rev = 0
	IF bd = 1 THEN rev = 2
	IF bd = 2 THEN rev = 1
	IF bd = 3 THEN rev = 4
	IF bd = 4 THEN rev = 3
	nb = 0 : #bs = 60000
	GOSUB openmask		' same openness mask as the ghosts (fruit shares wallchk2 rules)
	bv = 1
	FOR dr = 1 TO 4
		tr = r : tc = c
		IF dr = 1 THEN tr = r - 1
		IF dr = 2 THEN tr = r + 1
		IF dr = 3 THEN tc = c - 1
		IF dr = 4 THEN tc = c + 1
		wl = 1
		IF (mk AND bv) <> 0 THEN wl = 0
		IF (wl=0) AND (dr<>rev) THEN
			nb = nb + 1
			#dd1 = tr : #dd1 = #dd1 - ftr : #dd2 = tc : #dd2 = #dd2 - ftc
			#qd = #dd1*#dd1 + #dd2*#dd2
			IF #qd < #bs THEN #bs = #qd : bd = dr
		END IF
		bv = bv * 2
	NEXT dr
	IF nb = 0 THEN bd = rev
mf_step:
	IF bd = 1 THEN by = by - 2
	IF bd = 2 THEN by = by + 2
	IF bd = 3 THEN bx = bx - 2
	IF bd = 4 THEN bx = bx + 2
	IF (bx<13) OR (bx>229) OR (#fw>#cd400) THEN GOSUB killfruit : RETURN
	fx = bx : fy = by : fd = bd
	' vertical bob while moving horizontally (XB WB), kept non-negative
	fwb = fy - 2
	IF (bd = 3) OR (bd = 4) THEN
		m = #fw AND 7
		IF m >= 4 THEN fwb = fy - 4 + (m - 4) ELSE fwb = fy - 4 + (4 - m)
	END IF
	SPRITE 5, fwb, fx - 1, 28, ffl		' fruit on slot 5 (lowest priority, after ghosts)
	END

	' --- eat fruit (XB 770-772) ---
eatfruit:	PROCEDURE
	#pt = #pt + ffp
	GOSUB killfruit
	GOSUB hud
	SOUND 0, 214, 13			' fruit chime (523 Hz then 659 Hz)
	FOR dr = 1 TO 6 : WAIT : NEXT dr
	SOUND 0, 170, 13
	FOR dr = 1 TO 6 : WAIT : NEXT dr
	SOUND 0, , 0
	END

	' --- short start jingle, played once when a game begins (C-E-G-C arpeggio) ---
startjingle:	PROCEDURE
	RESTORE jingle_data
	FOR i = 1 TO 12
		READ BYTE v
		READ BYTE h1
		READ BYTE h2
		READ BYTE dn
		SOUND 0, v, 13			' melody
		SOUND 1, h1, 10			' harmony
		SOUND 2, h2, 8			' bass
		FOR dr = 1 TO dn : WAIT : NEXT dr
	NEXT i
	SOUND 0, , 0 : SOUND 1, , 0 : SOUND 2, , 0
	END

	' Original 3-voice jingle: melody(ch0), harmony(ch1), bass(ch2), duration(frames).
	' Triads over the progression  C  C  F  G  C  Am  G  C.
jingle_data:
	DATA BYTE 143,170,214,8
	DATA BYTE 107,143,170,8
	DATA BYTE 127,160,214,8
	DATA BYTE 113,143,191,8
	DATA BYTE 107,143,170,8
	DATA BYTE 85,107,127,8
	DATA BYTE 95,113,143,8
	DATA BYTE 107,143,170,8
	DATA BYTE 127,160,214,8
	DATA BYTE 113,143,191,8
	DATA BYTE 95,113,143,8
	DATA BYTE 107,143,214,18

	' --- 'get ready' pause: show the actors in place, hold ~1 second ---
ready:	PROCEDURE
	DEFINE CHAR 152,1,pellet_tile		' energizers solid during the pause
	SPRITE 0, sy - 2, sx - 1, 16, 11
	FOR j = 1 TO 4 : SPRITE j, gy(j) - 2, gx(j) - 1, 20, gc(j) : NEXT j
	FOR dr = 1 TO 60 : WAIT : NEXT dr
	END

	' --- fruit shape + value for the level (XB 1160-1169) ---
fruitdef:	PROCEDURE
	fl = le
	IF le >= 8 THEN fl = RANDOM(7) + 1
	IF fl = 1 THEN
		DEFINE SPRITE 7,1,fruit_cherry
		ffl = 8 : ffp = 10		' 100 pts
	END IF
	IF fl = 2 THEN
		DEFINE SPRITE 7,1,fruit_straw
		ffl = 8 : ffp = 20		' 200 pts
	END IF
	IF fl = 3 THEN
		DEFINE SPRITE 7,1,fruit_orange
		ffl = 10 : ffp = 50		' 500 pts
	END IF
	IF fl = 4 THEN
		DEFINE SPRITE 7,1,fruit_pretzel
		ffl = 6 : ffp = 70		' 700 pts
	END IF
	IF fl = 5 THEN
		DEFINE SPRITE 7,1,fruit_apple
		ffl = 8 : ffp = 100		' 1000 pts
	END IF
	IF fl = 6 THEN
		DEFINE SPRITE 7,1,fruit_pear
		ffl = 2 : ffp = 200		' 2000 pts
	END IF
	IF fl >= 7 THEN
		DEFINE SPRITE 7,1,fruit_banana
		ffl = 11 : ffp = 500		' 5000 pts
	END IF
	END

	' --- pick the maze for this level (XB 1155-1157) ---
pickmaze:	PROCEDURE
	mz = 1
	IF le >= 3 THEN mz = 2
	IF le >= 6 THEN mz = 3
	IF le >= 10 THEN mz = 4
	IF le >= 14 THEN mz = RANDOM(4) + 1
	END

	' --- draw maze + colours + count dots (XB 800-832) ---
drawmaze:	PROCEDURE
	CLS
	GOSUB setwc			' colour first, so walls paint in the right colour (no recolour flash)
	IF mz = 1 THEN RESTORE maze1
	IF mz = 2 THEN RESTORE maze2
	IF mz = 3 THEN RESTORE maze3
	IF mz = 4 THEN RESTORE maze4
	dt = 0 : ty1 = 0 : ty2 = 0
	FOR mr = 1 TO 22
		FOR i = 1 TO 28
			READ BYTE p
			cc = 32
			IF p = 46 THEN cc = 144 : dt = dt + 1		' "."
			IF p = 79 THEN cc = 152 : dt = dt + 1		' "O"
			IF p = 68 THEN cc = 160				' "D"
			IF p = 43 THEN cc = 168				' "+"
			IF p >= 97 THEN cc = 128 + p - 97		' "a".."p"
			IF (i = 1) AND (p = 32) THEN
				IF ty1 = 0 THEN ty1 = (mr + 1) * 8 - 3 ELSE ty2 = (mr + 1) * 8 - 3
			END IF
			VPOKE $1800 + (mr + 1) * 32 + (i + 1), cc
		NEXT i
	NEXT mr
	IF ty2 = 0 THEN ty2 = ty1
	END

	' per-maze wall + cross colour, copied from the XB original (WC: 14,6,10,5 -> CV 13,5,9,4)
setwc:	PROCEDURE
	IF mz = 1 THEN DEFINE COLOR 128,16,wall_c1 : DEFINE COLOR 168,1,wall_c1
	IF mz = 2 THEN DEFINE COLOR 128,16,wall_color : DEFINE COLOR 168,1,wall_color
	IF mz = 3 THEN DEFINE COLOR 128,16,wall_c3 : DEFINE COLOR 168,1,wall_c3
	IF mz = 4 THEN DEFINE COLOR 128,16,wall_c4 : DEFINE COLOR 168,1,wall_c4
	END

	' --- HUD (XB 708-709) ---
hud:	PROCEDURE
	PRINT AT 0, "SCORE ", <5>#pt, "0"
	PRINT AT 32, "LIVES ", lv, " LEVEL ", le
	END

	' --- animated title (XB 1200-1218; 8-3-8 cheat enabled) ---
title:	PROCEDURE
	GOSUB clearsprites		' avoid pollution from a finished game
	SOUND 0, , 0 : SOUND 1, , 0 : SOUND 2, , 0 : sfx = 0	' silence any leftover game sound
	CLS
	le = 1 : lv = 3 : ng = 4		' ng = ghost count (4); 8-3-8 can override
	PRINT AT 0, "SCORE ", <5>#pt, "0"		' last/most-recent score
	PRINT AT 6 * 32 + 10, "MS. PAC-MAN"
	PRINT AT 8 * 32 + 9, "2026  UNHUMAN"
	PRINT AT 15 * 32 + 4, "EAT DOTS - DODGE GHOSTS"
	PRINT AT 18 * 32 + 6, "JOYSTICK 1 TO MOVE"
	PRINT AT 21 * 32 + 6, "PRESS FIRE TO BEGIN"
	#za = 228 : #zb = 20 : #zc = 52 : #zd = 84 : #ze = 116
	zdir = 0 : gdir = 1 : af = 0 : ac = 0 : cs = 0 : ck = 15 : ts = 0
tt_loop:
	WAIT
	ts = ts + 1
	IF ts >= 4 THEN ts = 0		' skip 1 frame in 4 -> title motion 25% slower
	IF ts <> 0 THEN
		IF zdir = 0 THEN #za = #za - 2 ELSE #za = #za + 2
		IF #za < 5 THEN zdir = 1 : #za = 5
		IF #za > 243 THEN zdir = 0 : #za = 243
		IF gdir = 1 THEN
			#zb = #zb + 2 : #zc = #zc + 2 : #zd = #zd + 2 : #ze = #ze + 2
		ELSE
			#zb = #zb - 2 : #zc = #zc - 2 : #zd = #zd - 2 : #ze = #ze - 2
		END IF
		IF #ze > 243 THEN gdir = 0
		IF #zb < 5 THEN gdir = 1
	END IF
	ac = ac + 1
	IF ac >= 3 THEN ac = 0 : af = 1 - af
	pf = 0
	IF zdir = 0 THEN pf = 4		' moving left -> left-facing
	IF af = 1 THEN pf = 16		' chomp closed (right)
	IF (af = 1) AND (zdir = 0) THEN pf = 32	' left-closed (bow stays)
	SPRITE 0, 19, #za - 1, pf, 11
	SPRITE 1, 87, #zb - 1, 20, gc(1)
	SPRITE 2, 87, #zc - 1, 20, gc(2)
	SPRITE 3, 87, #zd - 1, 20, gc(3)
	SPRITE 4, 87, #ze - 1, 20, gc(4)
	' 8-3-8 cheat -> level/lives select
	k = cont1.key
	IF k <> ck THEN
		ck = k
		IF (k = 8) AND (cs = 2) THEN GOTO cheat_sel
		IF (k = 8) AND (cs = 0) THEN cs = 1
		IF (k = 3) AND (cs = 1) THEN cs = 2
		IF (k <> 8) AND (k <> 3) AND (k <> 15) THEN cs = 0
	END IF
	IF cont1.button THEN GOTO tt_done
	GOTO tt_loop
cheat_sel:
	GOSUB clearsprites
	CLS
	PRINT AT 12 * 32 + 10, "LEVEL 1-0"
	GOSUB readdig
	le = dg
	IF le = 0 THEN le = 10
	CLS
	PRINT AT 12 * 32 + 10, "LIVES 1-9"
	GOSUB readdig
	lv = dg
	IF lv = 0 THEN lv = 1
	CLS
	PRINT AT 12 * 32 + 10, "GHOSTS 1-4"
	GOSUB readdig
	ng = dg
	IF (ng < 1) OR (ng > 4) THEN ng = 4
	CLS
	' fall through into tt_done (shared exit; avoids a 2nd END in this PROCEDURE)
tt_done:
	GOSUB clearsprites
	CLS
	END

	' wait for a released key, then return the next digit (0-9) in dg
readdig:	PROCEDURE
	DO : WAIT : LOOP WHILE cont1.key <> 15
	DO : WAIT : dg = cont1.key : LOOP WHILE dg > 9
	END

	' hide sprites 0-5 (Y in the invisible range)
clearsprites:	PROCEDURE
	FOR i = 0 TO 5
		SPRITE i, $d1, 0, 0, 0
	NEXT i
	END

	' ============================================================
	' Tile + sprite data
	' ============================================================

	' 16 wall autotiles (verbatim from the XB CHAR2 defs; mask 15 solid).
wall_tiles:
	DATA BYTE $00,$00,$3C,$3C,$3C,$3C,$00,$00
	DATA BYTE $3C,$3C,$3C,$3C,$3C,$3C,$00,$00
	DATA BYTE $00,$00,$3F,$3F,$3F,$3F,$00,$00
	DATA BYTE $3C,$3C,$3F,$3F,$3F,$3F,$00,$00
	DATA BYTE $00,$00,$3C,$3C,$3C,$3C,$3C,$3C
	DATA BYTE $3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C
	DATA BYTE $00,$00,$3F,$3F,$3F,$3F,$3C,$3C
	DATA BYTE $3C,$3C,$3F,$3F,$3F,$3F,$3C,$3C
	DATA BYTE $00,$00,$FC,$FC,$FC,$FC,$00,$00
	DATA BYTE $3C,$3C,$FC,$FC,$FC,$FC,$00,$00
	DATA BYTE $00,$00,$FF,$FF,$FF,$FF,$00,$00
	DATA BYTE $3C,$3C,$FF,$FF,$FF,$FF,$00,$00
	DATA BYTE $00,$00,$FC,$FC,$FC,$FC,$3C,$3C
	DATA BYTE $3C,$3C,$FC,$FC,$FC,$FC,$3C,$3C
	DATA BYTE $00,$00,$FF,$FF,$FF,$FF,$3C,$3C
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

dot_tile:
	DATA BYTE $00,$00,$00,$18,$18,$00,$00,$00
pellet_tile:
	DATA BYTE $00,$3C,$7E,$7E,$7E,$7E,$3C,$00
blank_tile:
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
door_tile:
	DATA BYTE $00,$00,$00,$FF,$FF,$00,$00,$00
cross_tile:
	DATA BYTE $3C,$3C,$FF,$FF,$FF,$FF,$3C,$3C

	' DEFINE COLOR 128,16 needs 16 chars x 8 rows = 128 colour bytes.
	' All wall tiles: blue (5) on black (1).  (Per-maze colour is a TODO.)
wall_color:
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51
white_color:
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	' 16 wall chars x 8 rows, all white -- used for the level-clear flash
wall_white:
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1

	' maze1 walls: magenta (XB WC=14 -> CV 13) on black
wall_c1:
	DATA BYTE $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
	DATA BYTE $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
	DATA BYTE $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
	DATA BYTE $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
	DATA BYTE $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
	DATA BYTE $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
	DATA BYTE $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
	DATA BYTE $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
	' maze3 walls: light red (XB WC=10 -> CV 9) on black
wall_c3:
	DATA BYTE $91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91
	DATA BYTE $91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91
	DATA BYTE $91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91
	DATA BYTE $91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91
	DATA BYTE $91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91
	DATA BYTE $91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91
	DATA BYTE $91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91
	DATA BYTE $91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91
	' maze4 walls: dark blue (XB WC=5 -> CV 4) on black
wall_c4:
	DATA BYTE $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
	DATA BYTE $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
	DATA BYTE $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
	DATA BYTE $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
	DATA BYTE $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
	DATA BYTE $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
	DATA BYTE $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
	DATA BYTE $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41

	' Sprites (16x16) as BITMAP (CVBasic arranges them into VRAM order).
	' Real TI art, from the XB CALL CHAR quadrant hex rebuilt as visual rows.
	' Order: 0 R, 1 L, 2 U, 3 D, 4 closed, 5 ghost, 6 eyes, 7 fruit.
game_sprites:
	' Pac right
	BITMAP "................"
	BITMAP "....X..X........"
	BITMAP "....XXXX........"
	BITMAP "....XXXXXXX....."
	BITMAP "....XXXXXXXX...."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "...XXXXXXXX....."
	BITMAP "...XXXXX........"
	BITMAP "...XXXXX........"
	BITMAP "...XXXXXXXX....."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "....XXXXXXXX...."
	BITMAP ".....XXXXXX....."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	' Pac left
	BITMAP "................"
	BITMAP "........X..X...."
	BITMAP "........XXXX...."
	BITMAP ".....XXXXXXX...."
	BITMAP "....XXXXXXXX...."
	BITMAP "...XXXXXXXXXX..."
	BITMAP ".....XXXXXXXX..."
	BITMAP "........XXXXX..."
	BITMAP "........XXXXX..."
	BITMAP ".....XXXXXXXX..."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "....XXXXXXXX...."
	BITMAP ".....XXXXXX....."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	' Pac up
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "....XXXX........"
	BITMAP "...XXXX.XXX....."
	BITMAP "...XXXXXXXXX...."
	BITMAP "..XXXX...XXXX..."
	BITMAP "..XXX.....XXX..."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "...XXXXXXXX....."
	BITMAP "....XXXXXX......"
	BITMAP "...XXXX........."
	BITMAP "...X..X........."
	BITMAP "................"
	' Pac down
	BITMAP "................"
	BITMAP "...X..X........."
	BITMAP "...XXXX........."
	BITMAP "....XXXXXX......"
	BITMAP "...XXXXXXXX....."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "..XXX.....XXX..."
	BITMAP "..XXXX...XXXX..."
	BITMAP "...XXXXXXXXX...."
	BITMAP "...XXXX.XXX....."
	BITMAP "....XXXX........"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	' Pac closed
	BITMAP "................"
	BITMAP "....X..X........"
	BITMAP "....XXXX........"
	BITMAP ".....XXXXXX....."
	BITMAP "....XXXXXXXX...."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "....XXXXXXXX...."
	BITMAP ".....XXXXXX....."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	' ghost
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".....XXXX......."
	BITMAP "...XXXXXXXX....."
	BITMAP "..XX.XX.XX.XX..."
	BITMAP "..XX.XX.XX.XX..."
	BITMAP "..XXXXXXXXXXXX.."
	BITMAP "..XXXXXXXXXXXX.."
	BITMAP "..XXXXXXXXXXXX.."
	BITMAP "..XXXXXXXXXXXX.."
	BITMAP "..XXXXXXXXXXXX.."
	BITMAP "..XX.XX.XX.XX..."
	BITMAP "...X..X..X..X..."
	BITMAP "................"
	BITMAP "................"
	' eyes
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "...XX....XX....."
	BITMAP "..XXXX..XXXX...."
	BITMAP "..XXXX..XXXX...."
	BITMAP "..XXXX..XXXX...."
	BITMAP "...XX....XX....."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	' fruit
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".........XX....."
	BITMAP "........XX......"
	BITMAP ".......XX......."
	BITMAP "......XX........"
	BITMAP ".....XXXX......."
	BITMAP "....XXXXXX......"
	BITMAP "...XXXXXXXX....."
	BITMAP "...XXXXXXXX....."
	BITMAP "....XXXXXX......"
	BITMAP ".....XXXX......."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	' Pac left-closed (def 8, f=32) -- keeps the bow on the back when chomping left
	BITMAP "................"
	BITMAP "........X..X...."
	BITMAP "........XXXX...."
	BITMAP ".....XXXXXX....."
	BITMAP "....XXXXXXXX...."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "....XXXXXXXX...."
	BITMAP ".....XXXXXX....."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	' Pac up-closed (def 9, f=36) -- up-open with the mouth filled, bow at bottom
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "....XXXX........"
	BITMAP "...XXXX.XXX....."
	BITMAP "...XXXXXXXXX...."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "...XXXXXXXX....."
	BITMAP "....XXXXXX......"
	BITMAP "...XXXX........."
	BITMAP "...X..X........."
	BITMAP "................"
	' ghost frame 2 (def 10, f=40) -- walk cycle: body 1px taller, feet 1px lower
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".....XXXX......."
	BITMAP "...XXXXXXXX....."
	BITMAP "..XX.XX.XX.XX..."
	BITMAP "..XX.XX.XX.XX..."
	BITMAP "..XXXXXXXXXXXX.."
	BITMAP "..XXXXXXXXXXXX.."
	BITMAP "..XXXXXXXXXXXX.."
	BITMAP "..XXXXXXXXXXXX.."
	BITMAP "..XXXXXXXXXXXX.."
	BITMAP "..XXXXXXXXXXXX.."
	BITMAP "..XX.XX.XX.XX..."
	BITMAP "...X..X..X..X..."
	BITMAP "................"

	' ============================================================
	' Maze data (verbatim from games/mspacman, lines 9001-9322).
	' a-p = wall masks (->128-143), . dot, O pellet, D door, + cross.
	' ============================================================
maze1:
	DATA BYTE "gkkkkkkookkkkkkkkkkookkkkkkm"
	DATA BYTE "f......hn..........hn......f"
	DATA BYTE "f.ckki.dj.ckkkkkki.dj.ckki.f"
	DATA BYTE "fO........................Of"
	DATA BYTE "hom.gm.gooom.gm.gooom.gm.gon"
	DATA BYTE "dlj.hn.dlllj.hn.dlllj.hn.dlj"
	DATA BYTE "   .hn.......hn.......hn.   "
	DATA BYTE "gom.dlkki ckkllkki ckklj.gom"
	DATA BYTE "hpn.                    .hpn"
	DATA BYTE "hpn.gokki gkiDDckm ckkom.hpn"
	DATA BYTE "hpn.hn    f      f    hn.hpn"
	DATA BYTE "dlj.dj gm dkkkkkkj gm dj.dlj"
	DATA BYTE "   .   hn          hn   .   "
	DATA BYTE "gom.ckkllkki gm ckkllkki.gom"
	DATA BYTE "hpn.......   hn   .......hpn"
	DATA BYTE "hlj.ckkki.ckkllkki.ckkki.dln"
	DATA BYTE "f..........................f"
	DATA BYTE "fOgoom.gokki.gm.ckkom.goomOf"
	DATA BYTE "f.hppn.hn....hn....hn.hppn.f"
	DATA BYTE "f.dllj.dj.ckkllkki.dj.dllj.f"
	DATA BYTE "f..........................f"
	DATA BYTE "dkkkkkkkkkkkkkkkkkkkkkkkkkkj"

maze2:
	DATA BYTE "ckkkkkkookkkkkkkkkkookkkkkki"
	DATA BYTE "       hn..........hn       "
	DATA BYTE "gkkkki dj.ckkookki.dj ckkkkm"
	DATA BYTE "fO...........hn...........Of"
	DATA BYTE "f.gokkkki.gm.hn.gm.ckkkkom.f"
	DATA BYTE "f.hn......hn.dj.hn......hn.f"
	DATA BYTE "f.hn.goom hn....hn goom.hn.f"
	DATA BYTE "f.dj.dl+n dlkkkklj h+lj.dj.f"
	DATA BYTE "f......hn          hn......f"
	DATA BYTE "hkkkki.hn gkiDDckm hn.ckkkkn"
	DATA BYTE "f......dj f      f dj......f"
	DATA BYTE "f.ckom.   dkkkkkkj   .goki.f"
	DATA BYTE "f...hn.gm          gm.hn...f"
	DATA BYTE "hom.dj.dlki gkkm cklj.dj.gon"
	DATA BYTE "hpn.........f  f.........hpn"
	DATA BYTE "dlj.ckkooki.dkkj.ckookki.dlj"
	DATA BYTE "   ....hn..........hn....   "
	DATA BYTE "gki.gm.dj.ckkookki.dj.gm.ckm"
	DATA BYTE "fO..hn.......hn.......hn..Of"
	DATA BYTE "f.cklj.ckkki.dj.ckkki.dlki.f"
	DATA BYTE "f..........................f"
	DATA BYTE "dkkkkkkkkkkkkkkkkkkkkkkkkkkj"

maze3:
	DATA BYTE "gkkkkkkkkkookkkkookkkkkkkkkm"
	DATA BYTE "f.........hn....hn.........f"
	DATA BYTE "fOgokkkki.dj.gm.dj.ckkkkomOf"
	DATA BYTE "f.dj.........hn.........dj.f"
	DATA BYTE "f....gm.goom.hn.goom.gm....f"
	DATA BYTE "dkki.hn.dllj.dj.dllj.hn.ckkj"
	DATA BYTE " ....hn..............hn.... "
	DATA BYTE "e.gm.dlki.ckkkkkki.cklj.gm.e"
	DATA BYTE "f.hn.....          .....hn.f"
	DATA BYTE "f.dlki.gm gkiDDckm gm.cklj.f"
	DATA BYTE "f......hn f      f hn......f"
	DATA BYTE "f.gm.cklj dkkkkkkj dlki.gm.f"
	DATA BYTE "f.hn.....          .....hn.f"
	DATA BYTE "f.dlki.gokki.gm.ckkom.cklj.f"
	DATA BYTE "f......hn....hn....hn......f"
	DATA BYTE "hki.gm.dj.ckkllkki.dj.gm.ckn"
	DATA BYTE "f...hn................hn...f"
	DATA BYTE "f.cklj.gokki.gm.ckkom.dlki.f"
	DATA BYTE "fO.....hn....hn....hn.....Of"
	DATA BYTE "f.ckki.hn.ckkllkki.hn.ckki.f"
	DATA BYTE "f......hn..........hn......f"
	DATA BYTE "dkkkkkkllkkkkkkkkkkllkkkkkkj"

maze4:
	DATA BYTE "gkkkkkkkkkkkkkkkkkkkkkkkkkkm"
	DATA BYTE "f..........................f"
	DATA BYTE "f.gm.goom.gokkkkom.goom.gm.f"
	DATA BYTE "fOhn.dllj.hn....hn.dllj.hnOf"
	DATA BYTE "f.hn......hn.gm.hn......hn.f"
	DATA BYTE "f.dlki.gm.dj.hn.dj.gm.cklj.f"
	DATA BYTE "f......hn....hn....hn......f"
	DATA BYTE "hom.ckk++kki dj ckk++kki.gon"
	DATA BYTE "hpn....hn          hn....hpn"
	DATA BYTE "dlj gm.hn gkiDDckm hn.gm dlj"
	DATA BYTE "    hn.dj f      f dj.hn    "
	DATA BYTE "ckkk+n.   dkkkkkkj   .h+kkki"
	DATA BYTE "    hn.gm          gm.hn    "
	DATA BYTE "gom dj.dlkki gm ckklj.dj gom"
	DATA BYTE "hpn..........hn..........hpn"
	DATA BYTE "hlj.ckkki.gm.dj.gm.ckkki.dln"
	DATA BYTE "f.........hn....hn.........f"
	DATA BYTE "f.goki.gm.dlkkkklj.gm.ckom.f"
	DATA BYTE "fOhn...hn..........hn...hnOf"
	DATA BYTE "f.dj.ckllkki.gm.ckkllki.dj.f"
	DATA BYTE "f............hn............f"
	DATA BYTE "dkkkkkkkkkkkkllkkkkkkkkkkkkj"

	' ============================================================
	' Per-level fruit shapes (16x16), loaded into sprite 7 by fruitdef.
	' ============================================================
fruit_cherry:
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".........XX....."
	BITMAP "........XX......"
	BITMAP ".......XX......."
	BITMAP "......XX........"
	BITMAP ".....XXXX......."
	BITMAP "....XXXXXX......"
	BITMAP "...XXXXXXXX....."
	BITMAP "...XXXXXXXX....."
	BITMAP "....XXXXXX......"
	BITMAP ".....XXXX......."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
fruit_straw:
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "....XXXXXX......"
	BITMAP "...XXXXXXXX....."
	BITMAP "...XXXXXXXX....."
	BITMAP "...XXXXXXXX....."
	BITMAP "....XXXXXX......"
	BITMAP "....XXXXXX......"
	BITMAP ".....XXXX......."
	BITMAP "......XX........"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
fruit_orange:
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XX........"
	BITMAP "....XXXXXX......"
	BITMAP "...XXXXXXXX....."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "...XXXXXXXX....."
	BITMAP "....XXXXXX......"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
fruit_pretzel:
	BITMAP "................"
	BITMAP "................"
	BITMAP "...XX....XX....."
	BITMAP "..XXXX..XXXX...."
	BITMAP "..X..XXXX..X...."
	BITMAP "..X.X....X.X...."
	BITMAP "..X..XXXX..X...."
	BITMAP "..XXXX..XXXX...."
	BITMAP "...XX....XX....."
	BITMAP "....XXXXXX......"
	BITMAP ".....XXXX......."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
fruit_apple:
	BITMAP "................"
	BITMAP "................"
	BITMAP ".......X........"
	BITMAP ".....XX........."
	BITMAP "...XX.XXXX......"
	BITMAP "..XXXXXXXXXX...."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "..XXXXXXXXXX...."
	BITMAP "...XXXXXXXX....."
	BITMAP "....XXXXXX......"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
fruit_pear:
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XX........"
	BITMAP ".....XX........."
	BITMAP ".....XXX........"
	BITMAP "....XXXXX......."
	BITMAP "...XXXXXXX......"
	BITMAP "..XXXXXXXX......"
	BITMAP "..XXXXXXXX......"
	BITMAP "..XXXXXXXX......"
	BITMAP "...XXXXXX......."
	BITMAP "....XXXX........"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
fruit_banana:
	BITMAP "................"
	BITMAP "................"
	BITMAP ".........XX....."
	BITMAP ".......XXXX....."
	BITMAP "......XXXX......"
	BITMAP ".....XXXX......."
	BITMAP ".....XXX........"
	BITMAP ".....XXX........"
	BITMAP ".....XXXX......."
	BITMAP "......XXXX......"
	BITMAP ".......XXXX....."
	BITMAP ".........XX....."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
