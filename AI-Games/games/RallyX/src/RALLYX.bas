	'
	' RALLY-X -- Namco arcade clone (CVBasic, dual-target TI-99/4A + ColecoVision)
	'
	' Drive the maze, grab the flags, dodge the red cars, watch the radar.
	' Maze transcribed at the cell grid from the arcade Rally-X map rip
	' (assets/transcribe2.py); see DESIGN.md for the full element spec.
	'
	' The world renders at 2x2 CHARACTERS PER MAZE CELL (16-px roads), so
	' the 16x16 car exactly fills a lane and the 24x24-char viewport shows
	' a 12x12-cell window of the 32x56 maze -- the radar earns its keep.
	' Two map encodings: map1 (34x58 logical bytes, collision/AI/radar,
	' TI bank 0 so gameplay PEEKs never bank-switch) and map2 (68x116
	' pre-edged chars, stride 68, TI bank 1 for the SCREEN blits). The
	' camera pans in 1-char (8-px) steps for smoothness.
	'
	' Milestones: M1 world + driving, M2 flags/fuel/score/HUD/radar,
	' M3 enemies/smoke/crash, M4 title/rounds/challenge/jingles.
	'
	' 2026 UNHUMAN AND CLAUDE
	'

	' TI-99: the fixed cart area caps at 24,336 bytes. Bank layout:
	' bank 0 = code + logical map, bank 1 = map2 char map (selected during
	' gameplay), bank 2 = art/tiles/radar tables/item lists (selected only
	' during init and round setup). ColecoVision fits flat in 32K -- every
	' BANK statement is inside #if TI994A (unhuman/CVBasic fork).
#if TI994A
	BANK ROM 128
#endif

	CONST MAPW = 34		' bordered logical map width (32 maze + tree ring)
	CONST MAPH = 58		' bordered logical map height
	CONST CAMMAXC = 44	' map2 chars 68 - viewport 24
	CONST CAMMAXR = 92	' map2 chars 116 - viewport 24
	CONST ROADCH = 113	' logical codes >= ROADCH are drivable (wall 96,
				' tree 112 -- one compare tells wall from road)
	CONST SMOKECH = 12	' overlay chars: F 0-3, S 4-7, L 8-11, smoke 12-15
	' fuel max is 768 (~51 s at 1 unit / 4 frames) -- written as a literal
	' at the init site because "CONST FUELMAX = 768" assigned to a 16-bit
	' var compiles to CLR (a CONST > 255 truncates to 8 bits -- same
	' family as the dotted-constant folding bug, verified in RALLYX.a99)
	CONST PSPD = 24		' player speed, 1/8 px per frame (24 = 3 px/f
				' = same cells/second as before the 2x scale)
	CONST TURNRT = 3	' frames per 45-degree step while turning: a
				' 90-degree turn takes 6 frames, a 180 takes 12
	CONST BLINKRT = 30	' frames between radar player-dot colour flips

	' flags: slots 0-7 regular, 8 = special S, 9 = lucky L (DESIGN.md 3/7)
	DIM fr(10)		' flag row (bordered logical cell)
	DIM fc(10)		' flag col
	DIM fst(10)		' 0 = live, 1 = taken
	DIM msktab(4)		' radar 2-px dot masks by (x AND 6)/2

	' enemies (up to 4; nen active this round)
	DIM #ex(4)		' map-pixel x (16 px per cell)
	DIM #ey(4)		' map-pixel y
	DIM edir(4)		' heading 0-3
	DIM eang(4)		' VISUAL heading 0-7 (45 deg steps), eases toward
				' edir*2 so enemies turn instead of snapping
	DIM estn(4)		' stun countdown (smoke hit)

	' smoke puffs (circular list, oldest reused)
	DIM sr(6)
	DIM sc(6)
	DIM st(6)		' ttl in frames; 0 = free

	' radar mover dots: 0 = player, 1-4 = enemies; one updated per tick
	DIM #mpa(5)		' previous dot pattern addr
	DIM mpm(5)		' previous dot erase mask (NOT dotmask)
	DIM mpv(5)		' 1 = dot currently plotted

	' --- one-time setup ---------------------------------------------------
	' Default video mode (never MODE 2 -- renders broken on both targets).
	CLS
	BORDER 1
	VDP(1) = $E2		' 16x16 sprites, no magnification
	SPRITE FLICKER OFF

#if TI994A
	BANK SELECT 2		' art/tiles/radar tables live in bank 2
#endif

	DEFINE CHAR 0,16,ovlpat		' flags F/S/L + smoke, 2x2 quadrants
	DEFINE CHAR 96,16,wallpat	' wall quadrants, 4 per corner
	DEFINE CHAR 112,2,misc_chars	' 112 tree, 113 road
	DEFINE CHAR 120,9,fuel_chars	' fuel bar fill 0-8 px
	DEFINE CHAR 129,1,live_char	' lives icon
	DEFINE COLOR 0,16,ovlcol
	DEFINE COLOR 96,16,wallcol
	DEFINE COLOR 112,2,misc_colors
	DEFINE COLOR 120,9,fuel_colors
	DEFINE COLOR 129,1,live_color
	DEFINE SPRITE 0,8,car_bitmaps	' defs 0-7 = car headings N,NE,E,SE,
					' S,SW,W,NW (enemies reuse them, red)
	DEFINE SPRITE 8,2,expl_bitmaps	' defs 8-9 = crash explosion
	DEFINE SPRITE 10,1,flag_sprite	' def 10 = flag pennant (slots 5-14)

	#mapbase = VARPTR map1(0)
	msktab(0) = $C0
	msktab(1) = $30
	msktab(2) = $0C
	msktab(3) = $03

	#hi = 500		' session high score (5000 pts; score unit = 10)

	' panel text (col 24+): 1UP/score, HI/hi, FUEL label, round.
	' VDP writes are BUFFERED and applied at vblank -- pace bursts with
	' WAIT or the buffer overflows and writes are silently dropped.
	PRINT AT 24,"1UP"
	PRINT AT 88,"HI"
	WAIT
	PRINT AT 664,"FUEL"
	WAIT
	GOSUB prt_hi
	WAIT

	' radar canvas: chars 144-255 on rows 5-18, cols 24-31. Patterns and
	' base colors come from ROM tables via DEFINE (synchronous on TI);
	' only the name-table mapping is poked here, one row per frame.
	DEFINE CHAR 144,112,radar_zero
	WAIT
	DEFINE COLOR 144,112,radar_base
	WAIT
	FOR rr = 0 TO 13
	rw = 5 + rr
	#va = $1800 + rw * 32.
	#va = #va + 24
	t2 = 144 + rr * 8
	FOR j = 0 TO 7
	#vb = #va + j
	t = t2 + j
	VPOKE #vb,t
	NEXT j
	WAIT
	NEXT rr

	' --- title ------------------------------------------------------------
	' Printed over the viewport (black at boot, stale maze after game
	' over); the first draw_view repaints it away.
title:
	PRINT AT 359,"* RALLY-X *"
	PRINT AT 424,"PRESS FIRE"
	PRINT AT 512,"2026 UNHUMAN AND CLAUDE"
t_rel:
	WAIT
	IF cont1.button THEN GOTO t_rel
t_prs:
	WAIT
	IF cont1.button = 0 THEN GOTO t_prs
	rnd = 1
	rc3 = 0

	' --- new game ---------------------------------------------------------
game_init:
	#score = 0
	lives = 3
	olg = 0
	GOSUB prt_score
	GOSUB draw_lives
	GOSUB prt_rd

	' --- round start ------------------------------------------------------
round_init:
	' item lists live in bank 2; gameplay needs bank 1 (map2 blits)
#if TI994A
	BANK SELECT 2
#endif
	RESTORE flag_data
	FOR i = 0 TO 9
	READ BYTE t
	fr(i) = t
	READ BYTE t
	fc(i) = t
	fst(i) = 0
	NEXT i
#if TI994A
	BANK SELECT 1
#endif
	nfl = 0
	sgot = 0
	' difficulty: 3 chasers, 4 from round 4; speed ramps with the round.
	' Every 3rd round (rc3 = 2) is a CHALLENGE stage: no enemies, all
	' flags, completion bonus.
	nen = 3
	IF rnd >= 4 THEN nen = 4
	IF rc3 = 2 THEN nen = 0
	espd = 18 + rnd * 2
	IF espd > 30 THEN espd = 30
	GOSUB rehome
	FOR j = 0 TO 5
	st(j) = 0
	NEXT j
	nsm = 0
	#fuel = 768
	plvl = 255
	blink = 0
	rdt = 0
	fdt = 0
	sfxt = 0
	rdmover = 0
	' clear any stale radar mover dots, then plot this round's flags
	FOR mi = 0 TO 4
	IF mpv(mi) = 1 THEN GOSUB rd_erase
	mpv(mi) = 0
	WAIT
	NEXT mi
	GOSUB radar_flags
	IF rc3 = 2 THEN PRINT AT 389,"CHALLENGING STAGE" : FOR i = 1 TO 90 : WAIT : NEXT i

	' Player start cell (23,15) bordered, heading right (the start corridor
	' is horizontal -- walls sit directly above and below); camera centered.
restart:
	#px = 240		' 15 * 16 (map-pixel, cell = 16 px)
	#py = 368		' 23 * 16
	dir = 1
	qdir = 1
	ang = 2			' visual heading 0-7; 2 = East, matches dir = 1
	turning = 0
	blocked = 0
	lcr = 23
	lcc = 15
	GOSUB set_dir
	camc = 18		' camera in map2 CHAR units (car char - 12)
	camr = 34
	#acc = 0
	#eacc = 0
	GOSUB draw_view
	#lf = FRAME

	' --- main loop --------------------------------------------------------
game_loop:
	WAIT
	' FRAME-delta pacing (Structris pattern): a missed vblank becomes a
	' catch-up step, so TI-99 and ColecoVision run the same real speed.
	#fd = FRAME - #lf
	#lf = FRAME
	IF #fd > 4 THEN #fd = 4

	' stick sets the queued direction
	IF cont1.up THEN qdir = 0
	IF cont1.right THEN qdir = 1
	IF cont1.down THEN qdir = 2
	IF cont1.left THEN qdir = 3
	' A REVERSE is a turn, not a flip: the car never snaps from up to down.
	' It can start anywhere (the cell behind is by definition open), unlike
	' a 90-degree turn which waits for a cell centre (see at_center).
	IF turning = 0 THEN IF qdir = ((dir + 2) AND 3) THEN GOSUB start_turn

	' While turning the car rotates IN PLACE and does not advance -- this
	' is the Rally-X handling model. Driving resumes when ang reaches tang.
	IF turning = 1 THEN GOSUB turn_step ELSE GOSUB drive_step

	GOSUB update_cam

	x = #px - camc * 8.
	y = #py - camr * 8.
	SPRITE 0, y - 1, x, ang * 4, 5

	' enemies: same pixel-walk scheme, shared accumulator
	IF sct > 0 THEN sct = sct - 1
	pcr = #py / 16
	pcc = #px / 16
	#eacc = #eacc + espd * #fd
	esteps = #eacc / 8
	#eacc = #eacc AND 7
	IF esteps = 0 THEN GOTO eskip
	FOR k = 1 TO esteps
	FOR i = 0 TO 3
	IF i < nen THEN GOSUB emove1
	NEXT i
	NEXT k
eskip:

	' enemy sprites: slots 1-4 rotated every frame so a 5-on-a-scanline
	' pileup degrades to flicker (never SPRITE FLICKER -- it rotates the
	' player too)
	rot = rot + 1
	IF rot >= 4 THEN rot = 0
	FOR i = 0 TO 3
	sl = 1 + ((i + rot) AND 3)
	vis = 0
	IF i < nen THEN GOSUB evis
	IF vis = 1 THEN SPRITE sl, y2 - 1, x2, eang(i) * 4, 9 ELSE SPRITE sl, 209, 0, 0, 0
	NEXT i

	' enemy turning animation: eang eases 45 degrees at a time toward the
	' logical heading. Unlike the player they keep moving while they turn
	' (their AI only ever picks a 90-degree change, so a visible sweep is
	' enough -- stopping them dead would make them trivial to escape).
	eat = eat + #fd
	IF eat >= TURNRT THEN eat = 0 : GOSUB eang_step

	' flag sprites (slots 5-14): F yellow, S red, L white. They sit above
	' the chars, so camera-pan blits never flicker them; the 4-per-scanline
	' rule favors low sprite numbers, so gameplay actors always win.
	FOR fi = 0 TO 9
	sl = 5 + fi
	vis = 0
	IF fst(fi) = 0 THEN GOSUB fvis
	IF vis = 1 THEN SPRITE sl, y2 - 1, x2, 24, fcol ELSE SPRITE sl, 209, 0, 0, 0
	NEXT fi

	' player vs enemy collision (12-px boxes; lanes are 16 px apart, so
	' adjacent lanes can never false-positive)
	hitf = 0
	FOR i = 0 TO 3
	IF i < nen THEN GOSUB ckhit
	NEXT i
	IF hitf = 1 THEN GOTO crash

	' smoke ttl
	FOR j = 0 TO 5
	IF st(j) > 0 THEN st(j) = st(j) - 1 : IF st(j) = 0 THEN GOSUB smk_off
	NEXT j

	' fuel drain: 1 unit per 4 frames (frame-delta safe: drain on ticks)
	fdt = fdt + #fd
	IF fdt >= 4 THEN fdt = fdt - 4 : IF #fuel > 0 THEN #fuel = #fuel - 1
	GOSUB fuel_bar

	' radar movers refresh: one of the 5 dots per tick (~10 Hz ticks)
	rdt = rdt + #fd
	IF rdt >= 6 THEN rdt = 0 : GOSUB radar_tick

	' player-dot colour flip, every BLINKRT frames
	blt = blt + #fd
	IF blt >= BLINKRT THEN blt = 0 : blink = 1 - blink

	' flag-blip envelope
	IF sfxt > 0 THEN GOSUB sfx_tick

	IF nfl >= 10 THEN GOTO round_done
	GOTO game_loop

	' --- round complete ---------------------------------------------------
round_done:
	PRINT AT 395,"ROUND"
	PRINT AT 427,"CLEAR"
	IF rc3 = 2 THEN #score = #score + 1000 : GOSUB prt_score
	' (stale mover radar dots are erased by round_init's mpv/rd_erase pass;
	' the old loop here relied on the player dot skipping its replot when
	' blink flipped to 0, which no longer happens now that it always draws)
	' clear jingle: rising sweep
	FOR i = 1 TO 90
	WAIT
	#sf = 400 - i * 3
	SOUND 0,#sf,12
	NEXT i
	SOUND 0,,0
	FOR i = 1 TO 60
	WAIT
	NEXT i
	rnd = rnd + 1
	rc3 = rc3 + 1
	IF rc3 >= 3 THEN rc3 = 0
	GOSUB prt_rd
	GOTO round_init

	' --- crash: explosion, lose a life ------------------------------------
crash:
	FOR j = 1 TO 48
	WAIT
	t = j AND 8
	IF t = 0 THEN t2 = 32 ELSE t2 = 36	' explosion defs 8/9 -> names 32/36
	SPRITE 0, y - 1, x, t2, 10
	#sf = 150 + j * 12
	SOUND 0,#sf,13
	NEXT j
	SOUND 0,,0
	lives = lives - 1
	GOSUB draw_lives
	IF lives = 0 THEN GOTO game_over
	GOSUB rehome
	GOTO restart

game_over:
	PRINT AT 396,"GAME"
	PRINT AT 428,"OVER"
	' descending sting, then back to the title
	FOR i = 1 TO 120
	WAIT
	#sf = 200 + i * 4
	SOUND 0,#sf,11
	NEXT i
	SOUND 0,,0
	FOR i = 1 TO 120
	WAIT
	NEXT i
	GOTO title

	' reset enemies to their spawn cells, scattered (spawn list is in
	' bank 2; gameplay runs with bank 1 selected)
rehome:
#if TI994A
	BANK SELECT 2
#endif
	RESTORE espawn_data
	FOR i = 0 TO 3
	READ BYTE t
	#ey(i) = t * 16.
	READ BYTE t
	#ex(i) = t * 16.
	edir(i) = 2
	eang(i) = 4		' visual heading matches edir 2 (South)
	estn(i) = 0
	NEXT i
#if TI994A
	BANK SELECT 1
#endif
	sct = 180
	RETURN

	' --- player driving / turning -----------------------------------------
	' speed: 3 px/f, 2.25 under 25% fuel, 1.5 when empty
drive_step:
	spd = PSPD
	IF #fuel < 192 THEN spd = 18
	IF #fuel = 0 THEN spd = 12
	' accumulate 1/8-px units, then walk whole pixels one at a time
	#acc = #acc + spd * #fd
	steps = #acc / 8
	#acc = #acc AND 7
	IF steps > 0 THEN FOR i = 1 TO steps : GOSUB move1px : NEXT i
	RETURN

	' Begin rotating toward qdir. Takes the SHORT way round; a 180 goes
	' clockwise (there is no short way), so a reverse visibly sweeps
	' through the 90-degree heading instead of flipping.
start_turn:
	tang = qdir + qdir
	IF tang = ang THEN RETURN
	rstep = 1
	trn = tang - ang
	trn = trn AND 7
	IF trn > 4 THEN rstep = 7	' 7 == -1 (mod 8): rotate anticlockwise
	turning = 1
	trot = 0
	RETURN

	' One 45-degree step every TURNRT frames; arriving commits the heading
turn_step:
	trot = trot + #fd
	IF trot < TURNRT THEN RETURN
	trot = 0
	ang = ang + rstep
	ang = ang AND 7
	IF ang <> tang THEN RETURN
	turning = 0
	dir = tang / 2
	blocked = 0
	GOSUB set_dir
	RETURN

	' --- player: move one pixel (turns/walls only at cell alignment) ------
move1px:
	IF (#px AND 15) = 0 THEN IF (#py AND 15) = 0 THEN GOSUB at_center
	IF blocked = 0 THEN #px = #px + #dx : #py = #py + #dy
	RETURN

at_center:
	cr = #py / 16
	cc = #px / 16
	' flag pickup: car cell == a live flag's cell
	FOR fi = 0 TO 9
	IF fst(fi) = 0 THEN IF fr(fi) = cr THEN IF fc(fi) = cc THEN GOSUB take_flag
	NEXT fi
	' smoke: button held while entering a fresh cell drops a puff behind
	smkf = 0
	IF lcr <> cr THEN smkf = 1
	IF lcc <> cc THEN smkf = 1
	IF smkf = 1 THEN IF cont1.button THEN GOSUB smoke_put
	lcr = cr
	lcc = cc
	' a 90-degree turn is taken at a cell centre when that way is open --
	' it starts a rotation (start_turn), it does not snap the heading
	IF qdir <> dir THEN d = qdir : GOSUB probe : IF t >= ROADCH THEN GOSUB start_turn
	' blocked = 1 pins the car on the cell centre for the rest of THIS
	' frame's pixel steps. Without it the leftover steps kept moving it in
	' the OLD direction, so the turn finished 1-3 px off the grid -- and
	' since the cross-axis coordinate then never hit a multiple of 16
	' again, at_center never ran, `blocked` stayed 0, and the car drove
	' straight through every wall. turn_step clears it when the turn ends.
	IF turning = 1 THEN blocked = 1 : RETURN
	d = dir
	GOSUB probe
	IF t < ROADCH THEN blocked = 1 ELSE blocked = 0
	RETURN

	' logical-map code of the cell next to (cr,cc) in direction d -> t
	' (map1 lives in TI bank 0 -- always visible, no bank switch)
probe:
	tr = cr
	tc = cc
	IF d = 0 THEN tr = cr - 1
	IF d = 1 THEN tc = cc + 1
	IF d = 2 THEN tr = cr + 1
	IF d = 3 THEN tc = cc - 1
	#t = #mapbase + tr * 34.
	#t = #t + tc
	t = PEEK(#t)
	RETURN

set_dir:
	IF dir = 0 THEN #dx = 0 : #dy = -1
	IF dir = 1 THEN #dx = 1 : #dy = 0
	IF dir = 2 THEN #dx = 0 : #dy = 1
	IF dir = 3 THEN #dx = -1 : #dy = 0
	RETURN

	' --- enemy: move one pixel (AI only at cell alignment) ----------------
emove1:
	IF estn(i) > 0 THEN estn(i) = estn(i) - 1 : RETURN
	IF (#ex(i) AND 15) = 0 THEN IF (#ey(i) AND 15) = 0 THEN GOSUB eai
	d = edir(i)
	IF d = 0 THEN #ey(i) = #ey(i) - 1
	IF d = 1 THEN #ex(i) = #ex(i) + 1
	IF d = 2 THEN #ey(i) = #ey(i) + 1
	IF d = 3 THEN #ex(i) = #ex(i) - 1
	RETURN

	' reactive pursuit: prefer the axis with the larger gap to the player
	' if open, else the other, else keep going, else any open non-reverse,
	' else reverse (dead end). Scatter inverts the preferences.
eai:
	ecr = #ey(i) / 16
	ecc = #ex(i) / 16
	' smoke check
	FOR j = 0 TO 5
	IF st(j) > 0 THEN IF sr(j) = ecr THEN IF sc(j) = ecc THEN estn(i) = 90
	NEXT j
	IF estn(i) > 0 THEN RETURN
	#g = pcc
	#g = #g - ecc
	hd = 1
	IF #g >= 32768 THEN hd = 3 : #g = 0 - #g
	#g2 = pcr
	#g2 = #g2 - ecr
	vd = 2
	IF #g2 >= 32768 THEN vd = 0 : #g2 = 0 - #g2
	IF sct > 0 THEN hd = (hd + 2) AND 3 : vd = (vd + 2) AND 3
	p1 = hd
	p2 = vd
	IF #g2 > #g THEN p1 = vd : p2 = hd
	rv = (edir(i) + 2) AND 3
	cr = ecr
	cc = ecc
	' Every candidate must be open road AND not already claimed by another
	' enemy (probe_free) -- two cars must never stack on one cell. The car
	' that would have moved in is the one that turns away, because this
	' test runs when IT picks its direction.
	d = p1
	IF d <> rv THEN GOSUB probe_free : IF pfok = 1 THEN edir(i) = d : RETURN
	d = p2
	IF d <> rv THEN GOSUB probe_free : IF pfok = 1 THEN edir(i) = d : RETURN
	d = edir(i)
	GOSUB probe_free
	IF pfok = 1 THEN RETURN
	fnd = 0
	FOR j = 0 TO 3
	IF fnd = 0 THEN IF j <> rv THEN d = j : GOSUB probe_free : IF pfok = 1 THEN edir(i) = j : fnd = 1
	NEXT j
	IF fnd = 0 THEN edir(i) = rv
	RETURN

	' probe direction d from (cr,cc): pfok = 1 only if it is road AND no
	' other active enemy occupies that cell
probe_free:
	GOSUB probe
	pfok = 0
	IF t < ROADCH THEN RETURN
	pfo = 0
	FOR pfe = 0 TO 3
	IF pfe <> i THEN IF pfe < nen THEN GOSUB pf_chk
	NEXT pfe
	IF pfo = 0 THEN pfok = 1
	RETURN
pf_chk:
	pfr = #ey(pfe) / 16
	IF pfr <> tr THEN RETURN
	pfc = #ex(pfe) / 16
	IF pfc <> tc THEN RETURN
	pfo = 1
	RETURN

	' step every enemy's visual heading one notch toward its real one
eang_step:
	FOR ea = 0 TO 3
	IF ea < nen THEN GOSUB eang1
	NEXT ea
	RETURN
eang1:
	eat2 = edir(ea) + edir(ea)
	IF eang(ea) = eat2 THEN RETURN
	eat3 = eat2 - eang(ea)
	eat3 = eat3 AND 7
	IF eat3 > 4 THEN eang(ea) = (eang(ea) + 7) AND 7 ELSE eang(ea) = (eang(ea) + 1) AND 7
	RETURN

	' enemy i on-screen? -> vis, x2, y2 (char units; the 16-px car spans
	' 2 chars, so hide at the edges to avoid coordinate wrap)
evis:
	t = #ex(i) / 8 - camc
	IF t = 0 THEN RETURN
	IF t >= 22 THEN RETURN
	t2 = #ey(i) / 8 - camr
	IF t2 = 0 THEN RETURN
	IF t2 >= 22 THEN RETURN
	x2 = #ex(i) - camc * 8.
	y2 = #ey(i) - camr * 8.
	vis = 1
	RETURN

	' flag fi on-screen? -> vis, x2, y2, fcol (char units; hidden at the
	' edges so the sprite never bleeds into the panel, and skipping row 0
	' keeps "y2 - 1" from wrapping to 255. The compares are unsigned, so an
	' off-window flag underflows to a huge value and fails them -- correct.)
fvis:
	t = fr(fi) + fr(fi)
	t = t - camr
	IF t = 0 THEN RETURN
	IF t >= 23 THEN RETURN
	t2 = fc(fi) + fc(fi)
	t2 = t2 - camc
	IF t2 >= 23 THEN RETURN
	y2 = t * 8
	x2 = t2 * 8
	fcol = 11
	IF fi = 8 THEN fcol = 8
	IF fi = 9 THEN fcol = 15
	vis = 1
	RETURN

	' player-enemy overlap test for enemy i -> hitf
ckhit:
	#g = #px
	#g = #g - #ex(i)
	IF #g >= 32768 THEN #g = 0 - #g
	IF #g >= 12 THEN RETURN
	#g = #py
	#g = #g - #ey(i)
	IF #g >= 32768 THEN #g = 0 - #g
	IF #g >= 12 THEN RETURN
	hitf = 1
	RETURN

	' --- 2x2 overlay draw: logical cell (or2,oc2) as chars ----------------
	' ob = quadrant base (overlay chars < 96 use ob+0..3 TL TR BL BR;
	' ob = ROADCH paints plain road in all four quadrants)
put_cell:
	tcr = or2 + or2
	tcc = oc2 + oc2
	q = 0
	GOSUB put_char
	tcc = tcc + 1
	q = 1
	GOSUB put_char
	tcr = tcr + 1
	q = 3
	GOSUB put_char
	tcc = tcc - 1
	q = 2
	GOSUB put_char
	RETURN
put_char:
	t = tcr - camr
	IF t >= 24 THEN RETURN
	t2 = tcc - camc
	IF t2 >= 24 THEN RETURN
	ch = ob
	IF ob < 96 THEN ch = ob + q
	#va = $1800 + t * 32.
	#va = #va + t2
	VPOKE #va,ch
	RETURN

	' --- smoke ------------------------------------------------------------
	' drop a puff at the just-exited cell (lcr,lcc); costs 8 fuel
smoke_put:
	IF #fuel < 8 THEN RETURN
	#fuel = #fuel - 8
	IF st(nsm) > 0 THEN or2 = sr(nsm) : oc2 = sc(nsm) : ob = ROADCH : GOSUB put_cell
	sr(nsm) = lcr
	sc(nsm) = lcc
	st(nsm) = 180
	or2 = lcr
	oc2 = lcc
	ob = SMOKECH
	GOSUB put_cell
	nsm = nsm + 1
	IF nsm >= 6 THEN nsm = 0
	RETURN

	' erase expired puff j from the viewport
smk_off:
	or2 = sr(j)
	oc2 = sc(j)
	ob = ROADCH
	GOSUB put_cell
	RETURN

	' --- flag pickup (fi = slot, car at its cell) -------------------------
	' Values 100,200..1000 by pickup order; after S everything doubles;
	' L additionally pays fuel-bar-px x 10. #score is in units of 10 pts.
take_flag:
	fst(fi) = 1
	nfl = nfl + 1
	#val = nfl * 10
	IF #val > 100 THEN #val = 100
	IF sgot = 1 THEN #val = #val * 2
	IF fi = 8 THEN sgot = 1
	IF fi = 9 THEN #val = #val + #fuel / 12
	#score = #score + #val
	IF #score > #hi THEN #hi = #score : GOSUB prt_hi
	GOSUB prt_score
	IF olg = 0 THEN IF #score >= 2000 THEN olg = 1 : lives = lives + 1 : GOSUB draw_lives
	' no viewport erase needed -- the flag is a sprite, and the per-frame
	' sprite loop hides it now that fst() is 1. Clear its radar dot.
	tr2 = fr(fi)
	tc2 = fc(fi)
	GOSUB dot_addr
	nm = NOT dmsk
	a = VPEEK(#da)
	a = a AND nm
	VPOKE #da,a
	#db = #da + 1
	a = VPEEK(#db)
	a = a AND nm
	VPOKE #db,a
	sfxt = 10
	RETURN

	' Blank the 8-char panel field BEFORE printing. CVBasic prints numbers
	' with no fixed width, so a value needing fewer digits than the last
	' draw (e.g. #score back to 0 on a new game) left the old value's
	' right-hand digits on screen -- a garbled score/high score.
prt_score:
	PRINT AT 56,"        "
	PRINT AT 56,#score,"0"
	RETURN
prt_hi:
	PRINT AT 120,"        "
	PRINT AT 120,#hi,"0"
	RETURN
prt_rd:
	PRINT AT 760,"RD "
	PRINT AT 763,rnd," "
	RETURN

draw_lives:
	FOR li = 0 TO 3
	t2 = 32
	IF li < lives THEN t2 = 129
	' 6872 = $1800 + 22*32 + 24 (row 22 col 24); dotted-constant folds
	' truncate to 8 bits on this compiler, so the value is written out
	#va = 6872
	#va = #va + li
	VPOKE #va,t2
	NEXT li
	RETURN

	' --- camera (char units): dead zone keeps the car's screen char in
	' cols/rows 10-13; pans 1 char (8 px) per step for smoothness --------
	' Computed as a CLAMP, not a +/-1 nudge: on a pan frame the blit stalls
	' the loop 2-3 frames and FRAME-delta catch-up can move the car up to
	' 12 px while a 1-step camera moves only 8, so the car slowly outran
	' the window -- then the UNSIGNED dead-zone compare wrapped, the camera
	' ran the wrong way, and the sprite wrapped to the far edge (the "car
	' left the map and died" bug). Snapping any distance in one step keeps
	' the car inside the window no matter how far it jumped, and comparing
	' 16-bit char positions before subtracting keeps it wrap-safe.
	' Expressed as an allowed RANGE for the camera rather than a nudge:
	' the car's screen char must land in 10..13, so
	'   camc must be within [carchar-13, carchar-10]
	' and we snap to whichever bound is violated. Two properties matter:
	'  * lo <= hi always, so the two tests are MUTUALLY EXCLUSIVE. (The
	'    first cut reused one variable for both the car char and the new
	'    camera value, so the second test compared the camera against
	'    itself+10, always fired, and dragged the camera 10 chars back --
	'    the camera then ran away from a parked car and shoved the sprite
	'    off the right edge. Separate lo/hi/snapshot vars prevent that.)
	'  * subtraction is clamped at 0 BEFORE use, because these are
	'    unsigned: near the left/top edge the car char is as low as 2, and
	'    "carchar - 13" would wrap to ~65525.
	' Snapping the whole distance in one step (rather than +/-1) is what
	' keeps the car inside the window even when a pan-frame stall lets
	' FRAME-delta catch-up move it 12 px while the camera moves 8.
update_cam:
	dirty = 0
	' NOTE: these bounds are #cblo/#cbhi, NOT #lo/#hi -- `#hi` is the HIGH
	' SCORE, and the first version of this routine used it as the camera's
	' upper-bound scratch, clobbering the high score every single frame.
	#cch = #px / 8			' car's map2 char column
	#cblo = 0
	IF #cch > 13 THEN #cblo = #cch - 13
	#cbhi = 0
	IF #cch > 10 THEN #cbhi = #cch - 10
	IF #cblo > CAMMAXC THEN #cblo = CAMMAXC
	IF #cbhi > CAMMAXC THEN #cbhi = CAMMAXC
	#cs = camc
	IF #cs < #cblo THEN camc = #cblo : dirty = 1
	IF #cs > #cbhi THEN camc = #cbhi : dirty = 1
	#cch = #py / 8			' car's map2 char row
	#cblo = 0
	IF #cch > 13 THEN #cblo = #cch - 13
	#cbhi = 0
	IF #cch > 10 THEN #cbhi = #cch - 10
	IF #cblo > CAMMAXR THEN #cblo = CAMMAXR
	IF #cbhi > CAMMAXR THEN #cbhi = CAMMAXR
	#cs = camr
	IF #cs < #cblo THEN camr = #cblo : dirty = 1
	IF #cs > #cbhi THEN camr = #cbhi : dirty = 1
	IF dirty THEN GOSUB draw_view
	RETURN

	' --- viewport blit + smoke overlay ------------------------------------
	' The WAIT between the SCREEN blit and the overlay pokes keeps the
	' overlay out of the same frame's write budget (bursts drop silently).
	' Flags are NOT redrawn here -- they're sprites (slots 5-14), which is
	' what stopped them flickering: a char flag had to be re-poked after
	' every pan blit, and the poke landed a frame late.
draw_view:
	#voff = camr * 68.
	#voff = #voff + camc
	SCREEN map2, #voff, 0, 24, 24, 68
	WAIT
	FOR j = 0 TO 5
	IF st(j) > 0 THEN GOSUB ov_smoke
	NEXT j
	RETURN
ov_smoke:
	or2 = sr(j)
	oc2 = sc(j)
	ob = SMOKECH
	GOSUB put_cell
	RETURN

	' --- fuel bar (8 chars, row 21, redrawn only when the level changes) --
fuel_bar:
	lvl = #fuel / 12
	IF lvl = plvl THEN RETURN
	plvl = lvl
	FOR i = 0 TO 7
	t = i * 8
	n = 0
	IF lvl > t THEN n = lvl - t
	IF n > 8 THEN n = 8
	t2 = 120 + n
	' 6840 = $1800 + 21*32 + 24 (row 21 col 24); see draw_lives note
	#va = 6840
	#va = #va + i
	VPOKE #va,t2
	NEXT i
	RETURN

	' --- radar ------------------------------------------------------------
	' dot_addr: logical cell (tr2,tc2) -> pattern addr #da (first of 2
	' rows) and 2-px mask dmsk. Radar canvas = codes 144+, 2 px per cell,
	' per-third pattern tables (third = screen row / 8).
dot_addr:
	rx = tc2 - 1
	rx = rx + rx
	ry = tr2 - 1
	ry = ry + ry
	t = ry / 8
	th = (5 + t) / 8
	t2 = 144 + t * 8 + rx / 8
	' NOTE: "#da = th * 2048." miscompiles on the TMS9900 backend --
	' 8-bit var times a constant >= 2048 emits a plain CLR (verified in
	' RALLYX.a99). IF-ladder instead (th is only ever 0-2).
	#da = 0
	IF th = 1 THEN #da = 2048
	IF th = 2 THEN #da = 4096
	#da = #da + t2 * 8.
	#da = #da + (ry AND 7)
	dmsk = msktab((rx AND 6) / 2)
	RETURN

	' plot all live flags (round start): dot + yellow color rows
	' (one flag per frame -- 8 buffered VDP ops each, keep under the cap)
radar_flags:
	FOR fi = 0 TO 9
	WAIT
	tr2 = fr(fi)
	tc2 = fc(fi)
	GOSUB dot_addr
	a = VPEEK(#da)
	a = a OR dmsk
	VPOKE #da,a
	#db = #da + 1
	a = VPEEK(#db)
	a = a OR dmsk
	VPOKE #db,a
	#db = #da + $2000
	a = $B4
	IF fi = 8 THEN a = $84
	VPOKE #db,a
	#db = #db + 1
	VPOKE #db,a
	NEXT fi
	RETURN

	' one mover dot per tick: 0 = player (white, blinking), 1-4 = enemies
	' (red). Erase restores base color and re-bakes any flag dot that
	' shared the same two pattern rows.
radar_tick:
	mi = rdmover
	rdmover = rdmover + 1
	IF rdmover >= 5 THEN rdmover = 0
	IF mpv(mi) = 1 THEN GOSUB rd_erase
	mpv(mi) = 0
	IF mi = 0 THEN GOTO rt_ply
	t = mi - 1
	IF t >= nen THEN RETURN
	tr2 = #ey(t) / 16
	tc2 = #ex(t) / 16
	cv = $84
	GOTO rt_put
	' The player dot is ALWAYS drawn and cycles white/black instead of
	' blinking on and off -- a dot that vanishes half the time is hard to
	' pick out, while a flashing white/black one reads instantly. The
	' colour flips on BLINKRT (30) frames, driven by its own counter in the
	' main loop rather than by this routine's 5-mover round-robin.
rt_ply:
	tr2 = #py / 16
	tc2 = #px / 16
	cv = $F4			' white on dark blue
	IF blink = 0 THEN cv = $14	' black on dark blue
rt_put:
	GOSUB dot_addr
	a = VPEEK(#da)
	a = a OR dmsk
	VPOKE #da,a
	#pb = #da + 1
	a = VPEEK(#pb)
	a = a OR dmsk
	VPOKE #pb,a
	#pb = #da + $2000
	VPOKE #pb,cv
	#pb = #pb + 1
	VPOKE #pb,cv
	#mpa(mi) = #da
	mpm(mi) = NOT dmsk
	mpv(mi) = 1
	RETURN
rd_erase:
	nm = mpm(mi)
	#pb = #mpa(mi)
	a = VPEEK(#pb)
	a = a AND nm
	VPOKE #pb,a
	#pb = #pb + 1
	a = VPEEK(#pb)
	a = a AND nm
	VPOKE #pb,a
	#pb = #mpa(mi) + $2000
	a = $F4
	VPOKE #pb,a
	#pb = #pb + 1
	VPOKE #pb,a
	FOR fi = 0 TO 9
	IF fst(fi) = 0 THEN GOSUB rt_rebake
	NEXT fi
	RETURN
rt_rebake:
	tr2 = fr(fi)
	tc2 = fc(fi)
	GOSUB dot_addr
	IF #da <> #mpa(mi) THEN RETURN
	a = VPEEK(#da)
	a = a OR dmsk
	VPOKE #da,a
	#pb = #da + 1
	a = VPEEK(#pb)
	a = a OR dmsk
	VPOKE #pb,a
	#pb = #da + $2000
	a2 = $B4
	IF fi = 8 THEN a2 = $84
	VPOKE #pb,a2
	#pb = #pb + 1
	VPOKE #pb,a2
	RETURN

	' --- flag-blip sound envelope ----------------------------------------
sfx_tick:
	sfxt = sfxt - 1
	IF sfxt = 0 THEN SOUND 0,,0 : RETURN
	#sf = 100 + sfxt * 30
	SOUND 0,#sf,12
	RETURN

	' --- data -------------------------------------------------------------
	' TI bank 0: the logical map (gameplay PEEKs, always visible)
	INCLUDE "map0.bas"

	' TI bank 1: the doubled char map (SCREEN blits during gameplay)
#if TI994A
	BANK 1
#endif
	INCLUDE "map2.bas"

	' TI bank 2: art, tiles, radar tables, item lists (init / round setup)
#if TI994A
	BANK 2
#endif
	' 16x16 top-down F1 car, 4 rotations (assets/gencar.py; sprite order =
	' left half rows 0-15, then right half rows 0-15): narrow nose, four
	' protruding wheels, wide midsection, rear wing -- 16 px wheel-to-wheel,
	' exactly filling a lane. The 'up' art is left-right SYMMETRIC so its
	' 90-degree rotations stay readable (an asymmetric first cut rotated
	' into a ragged edge column); the wheels correctly come out 2x4 when
	' travelling vertically and 4x2 horizontally.
car_bitmaps:
	' N
	DATA BYTE $00,$00,$01,$39,$39,$3B,$03,$03,$03,$03,$3B,$3B,$3F,$0F,$00,$00
	DATA BYTE $00,$00,$80,$9C,$9C,$DC,$C0,$C0,$C0,$C0,$DC,$DC,$FC,$F0,$00,$00
	' NE
	DATA BYTE $00,$03,$03,$03,$00,$01,$73,$77,$7F,$3F,$1F,$0F,$07,$03,$01,$00
	DATA BYTE $00,$80,$80,$80,$30,$F0,$E0,$EE,$EE,$CE,$80,$00,$C0,$C0,$C0,$00
	' E
	DATA BYTE $00,$00,$1C,$1C,$3C,$30,$3F,$3F,$3F,$3F,$30,$3C,$1C,$1C,$00,$00
	DATA BYTE $00,$00,$38,$38,$38,$00,$E0,$FC,$FC,$E0,$00,$38,$38,$38,$00,$00
	' SE
	DATA BYTE $00,$01,$03,$07,$0F,$1F,$3F,$7F,$77,$73,$01,$00,$03,$03,$03,$00
	DATA BYTE $00,$C0,$C0,$C0,$00,$80,$CE,$EE,$EE,$E0,$F0,$30,$80,$80,$80,$00
	' S
	DATA BYTE $00,$00,$0F,$3F,$3B,$3B,$03,$03,$03,$03,$3B,$39,$39,$01,$00,$00
	DATA BYTE $00,$00,$F0,$FC,$DC,$DC,$C0,$C0,$C0,$C0,$DC,$9C,$9C,$80,$00,$00
	' SW
	DATA BYTE $00,$03,$03,$03,$00,$01,$73,$77,$77,$07,$0F,$0C,$01,$01,$01,$00
	DATA BYTE $00,$80,$C0,$E0,$F0,$F8,$FC,$FE,$EE,$CE,$80,$00,$C0,$C0,$C0,$00
	' W
	DATA BYTE $00,$00,$1C,$1C,$1C,$00,$07,$3F,$3F,$07,$00,$1C,$1C,$1C,$00,$00
	DATA BYTE $00,$00,$38,$38,$3C,$0C,$FC,$FC,$FC,$FC,$0C,$3C,$38,$38,$00,$00
	' NW
	DATA BYTE $00,$01,$01,$01,$0C,$0F,$07,$77,$77,$73,$01,$00,$03,$03,$03,$00
	DATA BYTE $00,$C0,$C0,$C0,$00,$80,$CE,$EE,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00

	' 16x16 flag pennant (sprite def 10) -- viewport flags are SPRITES so
	' camera-pan blits can't flicker them (chars get repainted a frame
	' after the blit; sprites ride on top untouched)
flag_sprite:
	DATA BYTE $1F,$1F,$1F,$1F,$1F,$18,$18,$18,$18,$18,$18,$18,$18,$18,$00,$00
	DATA BYTE $C0,$F8,$FE,$F8,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

	' crash explosion, 2 frames (defs 8-9)
expl_bitmaps:
	DATA BYTE $00,$10,$44,$01,$20,$04,$49,$02,$24,$09,$40,$12,$04,$41,$10,$00
	DATA BYTE $00,$08,$22,$80,$04,$20,$92,$40,$24,$90,$02,$48,$20,$82,$08,$00
	DATA BYTE $10,$02,$28,$85,$02,$50,$15,$4A,$21,$54,$0A,$A8,$41,$14,$40,$08
	DATA BYTE $08,$40,$14,$A1,$40,$0A,$A8,$52,$84,$2A,$50,$15,$82,$28,$02,$10

	' tree (112) + road (113) tiles and their per-row colors
misc_chars:
	DATA BYTE $3C,$7E,$FF,$FF,$FF,$7E,$3C,$00	' tree blob
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00	' road (solid bg)
misc_colors:
	DATA BYTE $3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C	' light green on dark green
	DATA BYTE $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA	' tan on tan

	' lives icon (129): mini car
live_char:
	DATA BYTE $00,$18,$7E,$5A,$7E,$5A,$18,$00
live_color:
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51	' light blue on black

	' fuel bar 120-128: n pixels lit from the left, rows 2-5
fuel_chars:
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$80,$80,$80,$80,$00,$00
	DATA BYTE $00,$00,$C0,$C0,$C0,$C0,$00,$00
	DATA BYTE $00,$00,$E0,$E0,$E0,$E0,$00,$00
	DATA BYTE $00,$00,$F0,$F0,$F0,$F0,$00,$00
	DATA BYTE $00,$00,$F8,$F8,$F8,$F8,$00,$00
	DATA BYTE $00,$00,$FC,$FC,$FC,$FC,$00,$00
	DATA BYTE $00,$00,$FE,$FE,$FE,$FE,$00,$00
	DATA BYTE $00,$00,$FF,$FF,$FF,$FF,$00,$00
fuel_colors:
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1

	' round 1 flag cells (bordered coords, from the transcription):
	' 8 regular, then S, then L (DESIGN.md 3)
flag_data:
	DATA BYTE 13,13
	DATA BYTE 18,23
	DATA BYTE 23,18
	DATA BYTE 28,8
	DATA BYTE 36,14
	DATA BYTE 39,7
	DATA BYTE 39,29
	DATA BYTE 46,4
	DATA BYTE 8,28
	DATA BYTE 54,22

	' enemy spawn cells (bordered row,col): the transcribed car-blob cells
	' sat on wall cells (the sprite covered the cell in the rip), so each
	' spawn is the adjacent road cell instead
espawn_data:
	DATA BYTE 7,24
	DATA BYTE 22,30
	DATA BYTE 28,17
	DATA BYTE 36,3

	INCLUDE "tiles.bas"
