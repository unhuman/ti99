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
	' Banking is used on BOTH targets: four maps do not fit in Coleco's
	' 32 K flat ROM, and CVBasic supports Opcode's Megacart mapper there.
	BANK ROM 128

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
	' SPEEDS ARE IN 1/16 px PER FRAME. They were 1/8 and everything ran at
	' twice this; against the arcade the game simply played too fast, so the
	' whole fixed-point scale was halved rather than every constant retuned.
	' Doing it at the scale keeps the level-to-level ramp and the
	' player:enemy ratio exactly as they were.
	CONST PSPD = 24		' player speed, 1/16 px per frame (= 1.5 px/f)
	CONST TURNRT = 6	' frames per 45-degree step while turning: a
				' 90-degree turn takes 12 frames, a 180 takes 24.
				' Doubled with the speed halving -- rotation is
				' vehicle speed too, and leaving it at 3 would
				' have made turns twice as cheap relative to
				' driving, i.e. changed the handling rather than
				' just the pace.
	CONST BLINKRT = 30	' frames between radar player-dot colour flips
	' SMOKE, per the arcade rules: ONE button press releases exactly THREE
	' puffs behind the car (it is not a stream you hold down), and each use
	' costs a big slice of fuel -- the strategy guides warn that using it
	' more than about once every 30 s means running dry before all ten
	' flags. 768 fuel is a full tank, so 96 = 8 uses if you never drove.
	CONST SMKPUFF = 3	' puffs released per press
	CONST SMKCOST = 96	' fuel per press (1/8 tank)
	CONST MAXSMK = 6	' puff slots = two deployments in flight
	CONST SMKTTL = 150	' frames a puff lasts (2.5 s) before it clears
	' These two count PIXEL STEPS, not frames, so they are consumed at the
	' car's speed -- halving the speed would have doubled their wall-clock
	' duration. Halved to hold the smoke stun at the same real duration.
	CONST SPINFR = 48	' pixel steps an enemy spins after hitting smoke
	CONST BUMPFR = 32	' shorter spin after bumping another car
	CONST POPFR = 110	' frames the flag-value popup stays up (~2 s)
	CONST ENGCHG = 6	' frames per idle chug (~10 Hz, a lumpy tickover)
	' ROCKS: static, lethal, and the dial that carries difficulty AFTER
	' every other one has maxed out (speed caps at round 9, pursuit at 6,
	' car count at 5). Round R lays the first R-1 of its maze's list, so
	' round 1 has none -- matching the arcade's level-1 rip -- and the count
	' is still climbing at round 17. 16 is what the tightest maze can hold
	' with every flag still reachable; see assets/genrocks.py.
	CONST MAXROCK = 16
	CONST ROCKCH = 24	' 2x2 boulder, chars 24-27 (clear of BANG at 16-23)
	CONST MUSTICK = 7	' frames per step; 2 steps a note = the original tempo
	CONST MUSVOL = 6	' melody volume -- low on purpose, the engine
	CONST MUSBAS = 5	' and the effects have to cut through it

	' flags: slots 0-7 regular, 8 = special S, 9 = lucky L (DESIGN.md 3/7)
	DIM fr(10)		' flag row (bordered logical cell)
	DIM fc(10)		' flag col
	DIM fst(10)		' 0 = live, 1 = taken
	' Flags never move, so their radar dot address and 2-px mask are worked
	' out once at round start instead of being re-derived for all ten flags
	' on every radar tick (that rescan measured ~4 ms per pass).
	DIM #fda(10)		' radar pattern addr of flag i's dot
	DIM fdm(10)		' radar dot mask of flag i
	DIM msktab(4)		' radar 2-px dot masks by (x AND 6)/2

	' enemies (up to 4; nen active this round)
	DIM #ex(4)		' map-pixel x (16 px per cell)
	DIM #ey(4)		' map-pixel y
	DIM edir(4)		' heading 0-3
	DIM eang(4)		' VISUAL heading 0-7 (45 deg steps), eases toward
				' edir*2 so enemies turn instead of snapping
	DIM estn(4)		' stun countdown (smoke hit)
	' Cell coordinates, kept in step with #ex/#ey on every move. probe_free
	' consults these for all four cars on every candidate direction, so
	' deriving them there cost ~24 divisions per AI decision.
	DIM ecra(4)		' cell row  = #ey(i) / 16
	DIM ecca(4)		' cell col  = #ex(i) / 16
	DIM ecmt(4)		' cells left holding a heading after meeting a car
	DIM spr(4)		' this maze's enemy spawn cells
	DIM spc(4)
	DIM rkr(MAXROCK)	' this maze's rock cells, in the order they appear
	DIM rkc(MAXROCK)
	' ROW REJECT: 1 if any live rock sits in that bordered row. probe_free
	' is the hottest path in the game and the rock scan runs inside it, so
	' the common case -- no rock anywhere near this row -- has to cost one
	' array read, not a walk of the whole list. With 8 rocks spread over 58
	' rows this short-circuits ~86% of probes.
	DIM rkrow(58)

	DIM pvbuf(4)		' popup digits, most significant first
	DIM popbuf(32)		' the popup box's four characters, 8 rows each

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

	' SOUND CHANNEL BUDGET -- everything here depends on this split:
	'   0,1  background music (OUR player, see mus_tick)
	'   2    flag blip, round jingle, game-over sting
	'   3    engine buzz, and the crash boom that overrides it
	'
	' We drive the music ourselves rather than using PLAY. CVBasic's PSG
	' music player writes the volume registers FROM ITS OWN TABLES every
	' vblank, so a game cannot turn it down -- and worse, while it is
	' compiled in it keeps writing the channels and drowns anything the game
	' puts there, which is exactly why the engine could not be heard.
	' Removing every PLAY statement is what leaves CVBASIC_MUSIC_PLAYER at 0.
	#musf = VARPTR mus_freq(0)
	#muss = VARPTR mus_song(0)

	BANK SELECT 5		' art / tiles / radar tables / item lists

	DEFINE CHAR 0,16,ovlpat		' flags F/S/L + smoke, 2x2 quadrants
	' Custom art MUST stay below char 32: 32 is SPACE, which CLS fills the
	' screen with and every PRINT pads with. Defining over it turned every
	' blank cell in the panel into rubble.
	DEFINE CHAR 24,4,rockpat	' rock boulder, one 2x2 cell
	DEFINE COLOR 24,4,rockcol
	DEFINE CHAR 16,8,bang_pat	' crash starburst, two 2x2 frames
	DEFINE COLOR 16,8,bang_col
	DEFINE COLOR 140,4,pop_col	' popup box: white on black
	#fontb = VARPTR mini_font(0)
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

	msktab(0) = $C0
	msktab(1) = $30
	msktab(2) = $0C
	msktab(3) = $03

	#hi = 500		' session high score (5000 pts; score unit = 10)
	lives0 = 3		' defaults, overridden by the 838 setup screen
	rnd0 = 1
	' MUSIC IS OFF BY DEFAULT. It shares the ear with the engine note and
	' wins, which made the engine inaudible and the whole mix busy. Press 1
	' on the title to turn it on. Unlike the 838 settings this is a
	' PREFERENCE, so it is set once at boot and survives game over.
	musen = 0

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
	' The viewport is blank whenever we get here: black at boot, and wiped
	' by clear_view on the way out of game_over (which also parks the car
	' sprites). The first draw_view of a new game repaints it away.
title:
	' Title is silent -- music belongs to the round, not the attract screen.
	GOSUB eng_off
	GOSUB mus_off
	SOUND 0,,0
	SOUND 1,,0
	GOSUB t_draw
	tseq = 0
	tkp = 15
t_rel:
	WAIT
	GOSUB t_key
	IF cont1.button THEN GOTO t_rel
t_prs:
	WAIT
	GOSUB t_key
	IF cont1.button = 0 THEN GOTO t_prs
	rnd = rnd0
	' rc3 is the challenging-stage phase: it cycles 0..3 with the round and
	' the stage runs when it is 0 from round 3 on -- i.e. rounds 3, 7, 11,
	' 15, which is the arcade cadence ("the third level and every fourth
	' thereafter"). It used to cycle 0..2 and fire every THIRD round.
	' A start level other than 1 has to land on the right phase, hence the
	' wrap here rather than a plain reset.
	' Phase is (rnd - 3) mod 4, written as (rnd + 1) mod 4 to keep every
	' intermediate POSITIVE -- these are unsigned 8-bit vars, so rnd - 3 at
	' round 1 would wrap to 254 and take 63 trips round the loop below to
	' come back. rnd 1..10 -> 2,3,0,1,2,3,0,1,2,3: round 3 is a stage, then
	' 7, then 11, and rounds 1-2 land on 2 and 3 so the +1 per round walks
	' onto 0 exactly at round 3.
	rc3 = rnd + 1
rc3wrap:
	IF rc3 >= 4 THEN rc3 = rc3 - 4 : GOTO rc3wrap
	' MUST jump: the title's helper subroutines sit between here and
	' game_init, so without this the fall-through walks straight into
	' t_draw and hits its RETURN with nothing on the GOSUB stack -- which
	' took the machine down the moment you pressed fire on the title.
	GOTO game_init

t_draw:
	PRINT AT 359,"* RALLY-X *"
	PRINT AT 424,"PRESS FIRE"
	GOSUB t_mus
	PRINT AT 544,"2026 UNHUMAN AND CLAUDE"
	RETURN

	' Music on/off indicator. Both strings are the same length so the second
	' one fully covers the first -- no trailing "N" left behind by "OFF".
t_mus:
	IF musen = 1 THEN PRINT AT 486,"1 MUSIC ON " ELSE PRINT AT 486,"1 MUSIC OFF"
	RETURN

	' --- "838 mode": type 8, 3, 8 on the title for the setup screen -------
	' CONT1.KEY gives 0-9 on both targets (Coleco keypad, TI keyboard) and
	' 15 for nothing pressed, so this is portable. Edge-triggered: the key
	' has to be released between digits or one press reads as many.
t_key:
	tk = cont1.key
	IF tk = tkp THEN RETURN
	tkp = tk
	IF tk = 15 THEN RETURN
	' 1 toggles the music. Not part of the 838 sequence, so it cannot
	' interfere with it -- but it DOES break a partial sequence, same as any
	' other stray digit, which is handled by the tseq = 0 below.
	IF tk = 1 THEN musen = 1 - musen : GOSUB t_mus
	IF tseq = 2 THEN IF tk = 8 THEN GOSUB setup838 : tseq = 0 : RETURN
	IF tseq = 1 THEN IF tk = 3 THEN tseq = 2 : RETURN
	tseq = 0
	IF tk = 8 THEN tseq = 1
	RETURN

	' Two questions, each a single digit with 0 meaning 10.
setup838:
	GOSUB clear_view
	PRINT AT 100,"838 SETUP"
	PRINT AT 196,"CARS  1-10, 0=10"
	GOSUB t_digit
	lives0 = tdg
	IF lives0 = 0 THEN lives0 = 10
	PRINT AT 228,"CARS  ="
	PRINT AT 236,lives0," "
	PRINT AT 292,"LEVEL 1-10, 0=10"
	GOSUB t_digit
	rnd0 = tdg
	IF rnd0 = 0 THEN rnd0 = 10
	PRINT AT 324,"LEVEL ="
	PRINT AT 332,rnd0," "
	FOR i = 1 TO 90
	WAIT
	NEXT i
	GOSUB clear_view
	GOSUB t_draw
	tkp = 15
	RETURN

	' wait for release, then for a digit 0-9
t_digit:
	WAIT
	IF cont1.key <> 15 THEN GOTO t_digit
td_wait:
	WAIT
	tdg = cont1.key
	IF tdg > 9 THEN GOTO td_wait
	tkp = tdg
	RETURN

	' --- new game ---------------------------------------------------------
game_init:
	#score = 0
	lives = lives0
	olg = 0
	GOSUB prt_score
	GOSUB draw_lives
	GOSUB prt_rd

	' --- round start ------------------------------------------------------
round_init:
	' FOUR MAZES, cycling with the round. mz also selects the ROM bank the
	' char map lives in (bank 1 + mz) and which map2_n the SCREEN blits and
	' probe use.
	mz = rnd - 1
	mz = mz AND 3
	' Item lists live in bank 5 with the art; gameplay needs the maze's own
	' bank for the blits and for probe's PEEKs.
	BANK SELECT 5
	' items.bas holds the four mazes back to back, 30 bytes each (10 flag
	' cells, the start, four spawns), so skipping mz blocks lands on ours.
	' The skip is guarded: a computed FOR 1 TO 0 still runs its body once.
	RESTORE flag_data_1
	IF mz > 0 THEN GOSUB skip_items
	FOR i = 0 TO 9
	READ BYTE t
	fr(i) = t
	READ BYTE t
	fc(i) = t
	fst(i) = 0
	NEXT i
	READ BYTE sr0		' player start cell for this maze
	READ BYTE sc0
	FOR i = 0 TO 3		' and its four enemy spawns
	READ BYTE t
	spr(i) = t
	READ BYTE t
	spc(i) = t
	NEXT i
	' Rocks for this maze, from the same bank. Round R lays the first R-1;
	' the list is ORDERED and every prefix of it was checked at generation
	' time to leave all ten flags reachable, so no round can be rocked into
	' being unwinnable. Challenging stages keep their rocks -- the arcade
	' ends the stage if you hit one.
	nrk = 0
	IF rnd > 1 THEN nrk = rnd - 1
	IF nrk > MAXROCK THEN nrk = MAXROCK
	RESTORE rock_data_1
	IF mz > 0 THEN GOSUB skip_rocks
	FOR i = 0 TO 57
	rkrow(i) = 0
	NEXT i
	FOR i = 0 TO MAXROCK - 1
	READ BYTE t
	rkr(i) = t
	t2rk = t
	READ BYTE t
	rkc(i) = t
	IF i < nrk THEN rkrow(t2rk) = 1
	NEXT i
	' WIPE THE RADAR before this round's flags are baked. The canvas was
	' only zeroed once at boot, so every round inherited the previous
	' round's flag dots -- and since each round is a DIFFERENT maze with
	' different flag cells, those stale dots looked like flags you could
	' collect but never needed. Done here while bank 5 is still selected,
	' because the blank canvas and its colours live with the art.
	DEFINE CHAR 144,112,radar_zero
	WAIT
	DEFINE COLOR 144,112,radar_base
	WAIT
	GOSUB sel_maze
	nfl = 0
	' Roll which flag is S and which is L. Positions are fixed (arcade
	' map); the ROLES move each round so the route is not memorised.
	sidx = RANDOM(10)
lroll:
	lidx = RANDOM(10)
	IF lidx = sidx THEN GOTO lroll
	' DIFFICULTY RAMP. Round 1 used to open with three chasers at 83% of the
	' player's speed all beelining from a 3-second head start,
	' which is brutal before you know the maze. Three dials now ramp
	' together instead:
	'   count  3 cars (the ARCADE count -- both Rally-X and New Rally-X run
	'          three chasers from the start) -> a 4th from round 5. Opening
	'          with 2 made round 1 read as under-populated rather than easy;
	'          the mercy in round 1 comes from the speed dial, not from
	'          leaving a car out.
	'   speed  0.875 px/f at round 1, +0.125 a round, capping at 1.875
	'          (these are 1/16-px units: espd 14 -> 30. Halved with
	'          everything else; the RAMP is unchanged, just at half scale)
	'   smarts eagg = chance in 8 that a car actually pursues on a given
	'          decision; 3/8 at round 1 up to 8/8 (always) from round 6, so
	'          early packs wander and give you room instead of converging.
	' Round 3 and every 4th thereafter is a CHALLENGING STAGE (see below).
	nen = 3
	IF rnd >= 5 THEN nen = 4
	' CHALLENGING STAGE (arcade rule, researched rather than assumed): the
	' red cars are present but DO NOT MOVE -- "the red cars remain idle and
	' will not chase the player unless their fuel is empty". Run the tank
	' dry and they wake up, which is the time pressure that stops the stage
	' being a free lap.
	'
	' `chal` gates their MOVEMENT ONLY. It used to gate their collision too,
	' making a parked car scenery you could drive straight through -- that is
	' wrong: an idle red car still kills you. Only the pursuit is switched
	' off, never the hitbox.
	chal = 0
	IF rnd >= 3 THEN IF rc3 = 0 THEN chal = 1
	espd = 12 + rnd * 2
	IF espd > 30 THEN espd = 30
	' eagg = chances in 8 that a car pursues on a given decision. The floor
	' was 3/8, i.e. it deliberately headed AWAY five times in eight -- which
	' does not read as "easier", it reads as the cars being broken. 5/8 at
	' round 1 still gives you room while looking like a chase.
	eagg = 2 + rnd
	IF eagg > 8 THEN eagg = 8
	' head start before they turn on you: 5 s at round 1 down to 2 s
	scti = 300 - rnd * 30
	IF scti < 120 THEN scti = 120
	GOSUB rehome
	FOR j = 0 TO MAXSMK - 1
	st(j) = 0
	NEXT j
	nsm = 0
	nsmk = 0		' live puffs; 0 lets the main loop skip smoke ageing
	pvt = 0			' no flag-value popup pending
	smkq = 0
	btnp = 1		' ignore a button still held from the title screen
	blink = 0
	rdt = 0
	fdt = 0
	sfxt = 0
	rdmover = 0
	' mover dots went with the canvas wipe above; just forget where they were
	FOR mi = 0 TO 4
	mpv(mi) = 0
	NEXT mi
	GOSUB radar_flags
	IF chal = 1 THEN PRINT AT 389,"CHALLENGING STAGE" : FOR i = 1 TO 90 : WAIT : NEXT i
	GOSUB mus_start		' music runs during the round only, not the title

	' Arcade start (see the reference shot): the player faces UP a clear
	' corridor with the chasers lined up in a row BEHIND him. Player is
	' bordered cell (35,22); the enemies sit 3 rows south, spread across
	' cols 19/22/25 (espawn_data), all able to drive north at him.
restart:
	' start cell for THIS maze (sr0,sc0), loaded in round_init
	#px = sc0 * 16.
	#py = sr0 * 16.
	dir = 0
	qdir = 0
	ang = 0			' visual heading 0-7; 0 = North, matches dir = 0
	turning = 0
	blocked = 0
	lcr = sr0
	lcc = sc0
	pqd = 255		' force the first at_center to probe
	pdr = 255
	' A NEW CAR STARTS THE STAGE FRESH -- arcade rule, verified against the
	' Rally-X references: losing a life resets the fuel gauge, sends the
	' next flag back to 100, and cancels the special's doubling. Collected
	' flags stay collected (nfl is untouched); it is the SCORING that
	' resets, which is why vstep is separate from nfl.
	' round_init falls through to here, so these cover a new round too.
	#fuel = 768
	plvl = 255		' force the fuel bar to redraw at the new level
	vstep = 0		' flag values start again at 100
	sgot = 0		' and the special's doubling is lost
	' Cancel any smoke still owed. A deployment queues SMKPUFF puffs that are
	' laid one per cell as the car drives on, so dying mid-deployment used to
	' carry the remainder over and the respawned car trailed smoke it never
	' asked for. btnp = 1 likewise ignores a fire button still held from the
	' crash, so smoke only ever starts on a fresh press.
	smkq = 0
	btnp = 1
	#ucx = 65535		' impossible position: force the first camera update
	#ucy = 65535
	' camera in map2 CHAR units: centre the car (char = cell*2) in the
	' 24-char window, then clamp to the map edges
	camc = 0
	IF sc0 > 6 THEN camc = sc0 + sc0 - 12
	IF camc > CAMMAXC THEN camc = CAMMAXC
	camr = 0
	IF sr0 > 6 THEN camr = sr0 + sr0 - 12
	IF camr > CAMMAXR THEN camr = CAMMAXR
	#acc = 0
	#eacc = 0
	GOSUB draw_view
	#lf = FRAME

	' --- main loop --------------------------------------------------------
game_loop:
	WAIT
	' FRAME-delta pacing (Structris pattern): a missed vblank becomes a
	' catch-up step, so TI-99 and ColecoVision run the same real speed.
	'
	' The clamp DISCARDS real elapsed time, so it must be loose enough never
	' to fire in normal play. At 4 it fired constantly: the loop was slow
	' enough that #fd wanted to be 7-8, so the world advanced at roughly half
	' real time whenever the loop was busy and at full speed whenever it was
	' not -- which is why the enemies visibly sped up while the player was
	' parked and the screen was not scrolling. Everything that moves is now
	' O(cells crossed) rather than O(pixels travelled) (drive_step, emove_n),
	' so a large delta is cheap AND safe -- both walk cell boundary to cell
	' boundary, testing walls at each one, so nothing tunnels no matter how
	' big the jump. 16 is a quarter second: it still bounds the one huge
	' delta after a round card or a crash pause, but ordinary play never
	' reaches it, so game speed no longer depends on frame rate.
	#fd = FRAME - #lf
	#lf = FRAME
	IF #fd > 16 THEN #fd = 16

	' stick sets the queued direction
	IF cont1.up THEN qdir = 0
	IF cont1.right THEN qdir = 1
	IF cont1.down THEN qdir = 2
	IF cont1.left THEN qdir = 3
	' Smoke fires on the button's RISING EDGE and queues SMKPUFF puffs,
	' which are then laid in the next cells the car leaves -- that is what
	' produces the arcade's short trail behind the car. Holding the button
	' does nothing extra; you pay the fuel per press.
	btn = 0
	IF cont1.button THEN btn = 1
	IF btn = 1 THEN IF btnp = 0 THEN GOSUB smoke_fire
	btnp = btn

	' A REVERSE is a turn, not a flip: the car never snaps from up to down.
	' It can start anywhere (the cell behind is by definition open), unlike
	' a 90-degree turn which waits for a cell centre (see at_center).
	IF turning = 0 THEN IF qdir = ((dir + 2) AND 3) THEN GOSUB start_turn

	' Cleared BEFORE anything moves: both movement loops sample collisions
	' as they go and set it, and the pass acts on it once at the end.
	hitf = 0

	' While turning the car rotates IN PLACE and does not advance -- this
	' is the Rally-X handling model. Driving resumes when ang reaches tang.
	IF turning = 1 THEN GOSUB turn_step ELSE GOSUB drive_step

	GOSUB update_cam

	' Camera origin in PIXELS, worked out once. evis re-derived both of
	' these for every enemy every pass, so this was eight multiplies a pass
	' to compute two values that cannot change in between.
	#cx8 = camc * 8.
	#cy8 = camr * 8.

	x = #px - #cx8
	y = #py - #cy8
	SPRITE 0, y - 1, x, ang * 4, 5

	' enemies: same pixel-walk scheme, shared accumulator
	' Scatter timer counts REAL frames, not loop passes. Decrementing it by
	' 1 per pass made the scatter phase last as long as the loop was slow --
	' one of two timers whose duration drifted with the frame rate.
	IF sct > 0 THEN GOSUB sct_tick
	pcr = #py / 16
	pcc = #px / 16
	#eacc = #eacc + espd * #fd
	esteps = #eacc / 16
	#eacc = #eacc AND 15
	IF esteps = 0 THEN GOTO eskip
	' frozen for the whole challenging stage until the tank runs dry
	IF chal = 1 THEN IF #fuel > 0 THEN GOTO eskip
	FOR i = 0 TO 3
	IF i < nen THEN GOSUB emove_n
	NEXT i
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

	' (flags are CHARACTERS, drawn by draw_view -- see the note there)

	' Act on any collision the movement loops found (12-px boxes; lanes are
	' 16 px apart, so adjacent lanes can never false-positive). The scan
	' that used to live here only sampled the END of the pass, which is
	' what let a fast pair tunnel through each other -- see ckhit.
	IF hitf = 1 THEN GOTO crash

	' Smoke ttl -- skipped entirely while no puff is in flight, which is most
	' of the time. An expiring puff now restores just its own 2x2 block
	' straight from the map (cell_restore) instead of repainting the whole
	' window: the full draw_view was a 576-byte blit with interrupts off,
	' i.e. a whole frame's stall, up to six times per smoke deployment.
	' Age by the FRAME DELTA, not a flat 1 per pass: the loop does not run
	' at a steady 60 Hz (a heavy frame does more than one frame's worth of
	' work), so a flat decrement made the lifetime drift wildly -- measured
	' ~30 ticks in 4 seconds, i.e. clouds hanging around ~8x too long.
	' #fd is already clamped by the pacing code above.
	IF nsmk > 0 THEN GOSUB smk_tick

	' Fuel drain: 1 unit per 8 frames (frame-delta safe: drain on ticks).
	' Was 1 per 4. Fuel is really a RANGE, not a clock -- it has to last ten
	' flags -- so halving the car's speed without halving the drain would
	' have left every tank covering half the ground and made rounds
	' unfinishable. Same distance per tank as before, just taken slower.
	fdt = fdt + #fd
	IF fdt >= 8 THEN fdt = fdt - 8 : IF #fuel > 0 THEN #fuel = #fuel - 1
	GOSUB fuel_bar

	' radar movers refresh: one of the 5 dots per tick (~10 Hz ticks)
	rdt = rdt + #fd
	IF rdt >= 6 THEN rdt = 0 : GOSUB radar_tick

	' player-dot colour flip, every BLINKRT frames
	blt = blt + #fd
	IF blt >= BLINKRT THEN blt = 0 : blink = 1 - blink

	' flag-value popup: redrawn every frame so it rides the scrolling maze
	IF pvt > 0 THEN GOSUB pop_tick

	' flag-blip envelope
	IF sfxt > 0 THEN GOSUB sfx_tick

	' engine note follows the car's state
	GOSUB eng_tick

	' background music, one step every MUSTICK frames
	GOSUB mus_tick

	IF nfl >= 10 THEN GOTO round_done
	GOTO game_loop

	' --- round complete ---------------------------------------------------
round_done:
	' The round is over: stop the music and the engine so the bonus tally
	' and the jingle have the sound chip to themselves. round_init starts
	' the music again for the next round.
	GOSUB mus_off
	SOUND 0,,0
	SOUND 1,,0
	GOSUB eng_off
	PRINT AT 395,"ROUND"
	PRINT AT 427,"CLEAR"
	IF chal = 1 THEN #score = #score + 1000 : GOSUB prt_score
	' FUEL BONUS for finishing the round, scaled by what is left in the tank
	' -- the arcade pays one, on the same scale as the lucky flag (fuel-bar
	' pixels x 10, so a full tank is worth 640). #score is in units of 10.
	'
	' It is TALLIED, not handed over in a lump: one unit at a time moves out
	' of the gauge and into the score, the bar visibly empties as it goes,
	' and each tick blips at a falling pitch. A full tank takes about two
	' seconds to count over.
	#fb = #fuel / 12
	PRINT AT 459,"FUEL BONUS"
	PRINT AT 491,#fb,"0   "
	FOR i = 1 TO 30
	WAIT
	NEXT i
fb_tally:
	IF #fb = 0 THEN GOTO fb_done
	#fb = #fb - 1
	#score = #score + 1
	#fuel = #fuel - 12	' cannot underflow: 12 * #fb <= #fuel by construction
	GOSUB prt_score
	PRINT AT 491,#fb,"0   "
	GOSUB fuel_bar
	' one crisp tick per unit -- on for a frame, off for a frame, pitch
	' falling as the gauge empties. A held tone just smears into a siren.
	#sf = 300 + #fb * 6
	SOUND 2,#sf,13
	WAIT
	SOUND 2,,0
	WAIT
	GOTO fb_tally
fb_done:
	SOUND 2,,0
	' (stale mover radar dots are erased by round_init's mpv/rd_erase pass;
	' the old loop here relied on the player dot skipping its replot when
	' blink flipped to 0, which no longer happens now that it always draws)
	' clear jingle: rising sweep (channel 2 -- the tally has finished)
	FOR i = 1 TO 90
	WAIT
	#sf = 400 - i * 3
	SOUND 2,#sf,12
	NEXT i
	SOUND 2,,0
	FOR i = 1 TO 60
	WAIT
	NEXT i
	rnd = rnd + 1
	rc3 = rc3 + 1
	IF rc3 >= 4 THEN rc3 = 0
	GOSUB prt_rd
	GOTO round_init

	' --- crash: BOTH cars destroyed, explosion, lose a life ---------------
	' The old sequence cycled two frames on the player's sprite alone with a
	' tone sweep, and was easy to miss in a busy screen. Now: both cars
	' vanish, BANG is stamped on the wreck, two blasts flash out of the
	' collision point, the border strobes, and it is a noise-channel boom
	' rather than a tone.
crash:
	SOUND 2,,0
	GOSUB eng_off
	' Wreck position in SCREEN pixels. Recomputed from the camera here
	' rather than reusing the main loop's x/y: the collision is detected
	' mid-movement, so x/y can be a pass out of date.
	#cx8 = camc * 8.
	#cy8 = camr * 8.
	bpx = #px - #cx8
	bpy = #py - #cy8
	GOSUB hide_spr
	bgx = bpx / 8
	bgy = bpy / 8
	FOR j = 1 TO 44
	WAIT
	' Alternate the two burst frames. This is a CHARACTER animation: four
	' VPOKEs swap which frame's codes sit on the name table. It used to be
	' two explosion SPRITES, which is wrong for something that belongs to
	' the roadway -- a sprite is positioned in screen pixels, so it slid out
	' of register with the maze as soon as anything scrolled.
	t = j AND 8
	bfr = 16
	IF t = 0 THEN bfr = 20
	GOSUB draw_bang
	cbl = 11				' light yellow / light red strobe
	IF t = 0 THEN cbl = 9
	' border strobes for the first fifth of a second, then settles
	IF j < 12 THEN BORDER cbl
	IF j = 12 THEN BORDER 1
	t3 = 13 - j / 4				' 13 -> 2, never wraps (j <= 44)
	SOUND 3,5,t3
	NEXT j
	SOUND 3,,0
	BORDER 1
	GOSUB hide_spr
	lives = lives - 1
	GOSUB draw_lives
	IF lives = 0 THEN GOTO game_over
	GOSUB rehome
	GOTO restart

game_over:
	' Cars off the screen before GAME OVER shows -- the player's wreck and
	' the chasers used to sit there frozen underneath it.
	GOSUB hide_spr
	' engine and music both stop -- the sting should land in silence
	GOSUB eng_off
	GOSUB mus_off
	SOUND 0,,0
	SOUND 1,,0
	PRINT AT 396,"GAME"
	PRINT AT 428,"OVER"
	' descending sting, then back to the title
	FOR i = 1 TO 120
	WAIT
	#sf = 200 + i * 4
	SOUND 2,#sf,11
	NEXT i
	SOUND 2,,0
	FOR i = 1 TO 120
	WAIT
	NEXT i
	' 838 settings last for ONE game only -- back to 3 cars from round 1.
	lives0 = 3
	rnd0 = 1
	' and wipe the maze, so the title is not printed over a stale playfield
	GOSUB clear_view
	GOTO title

	' --- flag score popup -------------------------------------------------
	' Builds the glyph run once at pickup: the value, then "x2" when the
	' special is doubling it, e.g. 500 x2. Digits come out by repeated
	' SUBTRACTION rather than division -- values are only ever 100..1000, so
	' this is a handful of iterations and costs no divide.
	' Glyph codes: 130 + digit, and 140 = 'x'. They sit ABOVE the font,
	' in the gap between the lives icon (129) and the radar (144+):
	' below 32 there is no longer room for these AND the burst.
pop_build:
	' Clear the four characters of the box (4 chars x 8 rows).
	FOR pb = 0 TO 31
	popbuf(pb) = 0
	NEXT pb
	' Digits of #pvv, most significant first. Repeated SUBTRACTION rather
	' than division -- the value is only ever 100..1000.
	pvn = 0
	pvz = 0
	#pw = #pvv
	#pdv = 1000
pop_loop:
	pvd = 0
pop_sub:
	IF #pw >= #pdv THEN #pw = #pw - #pdv : pvd = pvd + 1 : GOTO pop_sub
	IF pvd > 0 THEN pvz = 1
	IF pvz = 1 THEN pvbuf(pvn) = pvd : pvn = pvn + 1
	IF #pdv = 1 THEN GOTO pop_done
	#pdv = #pdv / 10
	GOTO pop_loop
pop_done:
	' value across the TOP half, one 3x5 glyph per 4-px slot
	prow = 1
	FOR pb = 0 TO pvn - 1
	pgl = pvbuf(pb)
	pdx = pb
	GOSUB pop_glyph
	NEXT pb
	' "x2" across the BOTTOM half when the special is doubling this flag
	IF pvm = 1 THEN GOSUB pop_mult
	DEFINE CHAR 140,4,VARPTR popbuf(0)
	RETURN

pop_mult:
	prow = 9
	pgl = 10		' 'x'
	pdx = 1
	GOSUB pop_glyph
	pgl = 2			' '2'
	pdx = 2
	GOSUB pop_glyph
	RETURN

	' Blit 3x5 glyph pgl into slot pdx (0-3, i.e. x = 0,4,8,12) at pixel row
	' prow. Slots never straddle a character boundary, which is the whole
	' reason for the 4-px pitch: even slots use the font byte as stored
	' (pixels already in bits 7-5), odd slots just shift right by 4.
	' Buffer layout is char-major: char = (row/8)*2 + half, 8 bytes each.
pop_glyph:
	FOR pgr = 0 TO 4
	#pfa = #fontb + pgl * 5.
	#pfa = #pfa + pgr
	pgb = PEEK(#pfa)
	IF pdx = 1 THEN pgb = pgb / 16
	IF pdx = 3 THEN pgb = pgb / 16
	pry = prow + pgr
	pbi = pry AND 7
	IF pry > 7 THEN pbi = pbi + 16
	IF pdx > 1 THEN pbi = pbi + 8
	popbuf(pbi) = popbuf(pbi) OR pgb
	NEXT pgr
	RETURN

	' Redrawn every frame while it is up (the pan blit repaints over it), and
	' anchored to the CAR, two rows above it.
	'
	' It used to be pinned to the flag's map cell, which is where the flag
	' was -- but you are driving away from that cell at 3 px a frame, so it
	' scrolled out of the window and vanished after about 0.4 s of its 2 s.
	' Riding above the car keeps the whole value on screen for its full life.
pop_draw:
	' Anchored to the FLAG's map cell -- it is part of the roadway, so it
	' scrolls with the maze and stays put while the car drives on. (Pinning
	' it to the car instead kept it on screen longer but made it drift over
	' the road, which is exactly what was not wanted.)
	bbt = pvr + pvr
	bby = bbt - camr
	IF bby >= 23 THEN RETURN
	bbt = pvc + pvc
	bbx = bbt - camc
	IF bbx >= 23 THEN RETURN
	bbn = 140
	FOR bbr = 0 TO 1
	bbt = bby + bbr
	#bva = bbt * 32.
	#bva = #bva + 6144
	#bva = #bva + bbx
	FOR bbc = 0 TO 1
	#bvb = #bva + bbc
	VPOKE #bvb,bbn
	bbn = bbn + 1
	NEXT bbc
	NEXT bbr
	RETURN

	' age it; when it lapses the window is repainted to wipe the glyphs.
	' draw_view (a full blit) rather than a targeted restore because the
	' popup can straddle flags and smoke, which draw_view repaints too. It
	' costs about one frame and happens at most ten times a round.
pop_tick:
	pvs = #fd
	IF pvt > pvs THEN pvt = pvt - pvs : GOSUB pop_draw : RETURN
	pvt = 0
	GOSUB draw_view
	RETURN

	' --- crash starburst: one 2x2 cell, frame base in bfr ---------------
	' Sits EXACTLY on the wreck. bgx/bgy are the car's TOP-LEFT screen
	' character and the car is itself 2x2, so the burst's origin is that
	' character -- an earlier -1 here pushed the whole graphic half a cell
	' up and left of where the car actually died.
draw_bang:
	bbx = bgx
	IF bbx > 22 THEN bbx = 22
	bby = bgy
	IF bby > 22 THEN bby = 22
	bbn = bfr
	FOR bbr = 0 TO 1
	bbt = bby + bbr
	#bva = bbt * 32.
	#bva = #bva + 6144		' $1800 name table; folded consts truncate
	#bva = #bva + bbx
	FOR bbc = 0 TO 1
	#bvb = #bva + bbc
	VPOKE #bvb,bbn
	bbn = bbn + 1
	NEXT bbc
	NEXT bbr
	RETURN

	' park all five car sprites off screen. y = 209, NEVER 208: 208 is the
	' sprite-list terminator and would blank every sprite after it too.
hide_spr:
	FOR hs = 0 TO 4
	SPRITE hs, 209, 0, 0, 0
	NEXT hs
	RETURN

	' blank the 24x24 viewport (cols 0-23), leaving the panel alone. One row
	' per frame: 24 chars is already a sizeable buffered write burst, and
	' bursts past the per-frame budget are dropped silently.
clear_view:
	FOR cvr = 0 TO 23
	WAIT
	#cva = cvr * 32.
	PRINT AT #cva,"                        "
	NEXT cvr
	RETURN

	' reset enemies to their spawn cells, scattered (spawn list is in
	' bank 2; gameplay runs with bank 1 selected)
	' Spawns come from spr/spc, read once in round_init -- rehome is called
	' again after every crash and no longer touches a bank to do it.
rehome:
	FOR i = 0 TO 3
	t = spr(i)
	#ey(i) = t * 16.
	ecra(i) = t
	t = spc(i)
	#ex(i) = t * 16.
	ecca(i) = t
	edir(i) = 2
	eang(i) = 4		' visual heading matches edir 2 (South)
	estn(i) = 0
	ecmt(i) = 0
	NEXT i
	sct = scti
	RETURN

	' skip mz whole item blocks (30 bytes each) to reach this maze's
skip_items:
	FOR i = 1 TO mz
	FOR j = 1 TO 30
	READ BYTE t
	NEXT j
	NEXT i
	RETURN

	' same shape for rocks.bas: MAXROCK cells x 2 bytes per maze
skip_rocks:
	FOR i = 1 TO mz
	FOR j = 1 TO MAXROCK
	READ BYTE t
	READ BYTE t
	NEXT j
	NEXT i
	RETURN

	' select the maze's ROM bank and point probe at its char map
sel_maze:
	IF mz = 0 THEN BANK SELECT 1 : #mapbase = VARPTR map2_1(0)
	IF mz = 1 THEN BANK SELECT 2 : #mapbase = VARPTR map2_2(0)
	IF mz = 2 THEN BANK SELECT 3 : #mapbase = VARPTR map2_3(0)
	IF mz = 3 THEN BANK SELECT 4 : #mapbase = VARPTR map2_4(0)
	RETURN

sct_tick:
	scta = #fd
	IF sct > scta THEN sct = sct - scta ELSE sct = 0
	RETURN

	' --- player driving / turning -----------------------------------------
	' speed: 1.5 px/f, 1.125 under 25% fuel, 0.75 when empty
drive_step:
	spd = PSPD
	IF #fuel < 192 THEN spd = 18
	IF #fuel = 0 THEN spd = 12
	' Accumulate 1/16-px units, then walk to the next CELL BOUNDARY in one
	' step rather than a subroutine call per pixel (same change as the
	' enemies' emove_n, and for the same reason: per-pixel work is O(#fd),
	' which is the shape that feeds the pacing runaway -- see DESIGN.md §1a).
	' Every decision the car makes -- turns, walls, flags, laying a puff --
	' happens on a cell centre, so nothing is lost by jumping the gaps.
	#acc = #acc + spd * #fd
	steps = #acc / 16
	#acc = #acc AND 15
pm_top:
	IF steps = 0 THEN RETURN
	IF (#px AND 15) = 0 THEN IF (#py AND 15) = 0 THEN GOSUB at_center
	' blocked is only ever set on a centre, so the car is parked there
	IF blocked = 1 THEN RETURN
	' pmk = pixels to the next boundary along dir
	IF dir = 0 THEN pmk = #py AND 15
	IF dir = 1 THEN pmk = 16 - (#px AND 15)
	IF dir = 2 THEN pmk = 16 - (#py AND 15)
	IF dir = 3 THEN pmk = #px AND 15
	IF pmk = 0 THEN pmk = 16		' sitting on a centre, heading away
	IF pmk > steps THEN pmk = steps
	IF dir = 0 THEN #py = #py - pmk
	IF dir = 1 THEN #px = #px + pmk
	IF dir = 2 THEN #py = #py + pmk
	IF dir = 3 THEN #px = #px - pmk
	' sample collisions every chunk, not once at the end of the pass
	GOSUB ckhit_all
	IF hitf = 1 THEN RETURN
	steps = steps - pmk
	GOTO pm_top

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
	RETURN

at_center:
	cr = #py / 16
	cc = #px / 16
	' Per-CELL work (flag pickup, laying a puff) runs only when the car has
	' actually entered a NEW cell. It used to run on every aligned pixel
	' step, and a car held against a wall stays aligned forever -- so the
	' ten-flag scan re-ran on every pixel step of every frame and measured
	' ~12 ms per pass, about a quarter of the whole loop.
	smkf = 0
	IF lcr <> cr THEN smkf = 1
	IF lcc <> cc THEN smkf = 1
	IF smkf = 1 THEN GOSUB enter_cell
	' The two probes below depend only on (cell, dir, qdir). A car pinned
	' against a wall stays cell-aligned forever, so those inputs stop
	' changing while the player holds a dead direction -- a very common
	' state in this game -- and re-probing on every pixel step was pure
	' waste. blocked/turning simply keep the values the last probe gave
	' them, which is exactly right while nothing has changed.
	IF smkf = 0 THEN IF qdir = pqd THEN IF dir = pdr THEN RETURN
	pqd = qdir
	pdr = dir
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
	' ROCK AHEAD? Checked on the cell the car is about to ENTER (probe has
	' just left it in tr/tc), never on the cell it has arrived in.
	'
	' The first cut tested on arrival, in enter_cell. That only fires once
	' the car is fully ON the cell -- a whole 16 px, most of a second at
	' this speed -- so the car visibly drove into the boulder and sat on it
	' before exploding. Reported as "it's detected, but it's delayed".
	' Testing ahead means the car never enters the cell at all and the burst
	' lands where the car actually is, against the rock.
	IF blocked = 0 THEN IF nrk > 0 THEN GOSUB rock_ahead
	RETURN

	' is the cell at (tr,tc) rocked? -> crash. Runs once per cell boundary
	' crossed, not per frame, so the 16-entry scan costs nothing measurable.
rock_ahead:
	IF rkrow(tr) = 0 THEN RETURN
	FOR rki = 0 TO nrk - 1
	IF rkr(rki) = tr THEN IF rkc(rki) = tc THEN hitf = 1
	NEXT rki
	IF hitf = 0 THEN RETURN
	' PUT THE CAR ON THE ROCK. `probe` left the rock's cell in tr/tc, so the
	' car is snapped onto it before the crash runs -- `crash` derives the
	' burst position from #px/#py, so the explosion then lands squarely on
	' the boulder instead of in the empty cell beside it. The car is only
	' there for the single pass it takes to reach `crash`, which hides the
	' sprites anyway; what is seen is the burst covering the rock.
	#px = tc * 16.
	#py = tr * 16.
	blocked = 1
	RETURN

	' First arrival in cell (cr,cc). smoke_lay must run BEFORE lcr/lcc are
	' updated: a puff is dropped in the cell just LEFT BEHIND, which is what
	' smoke_put reads out of lcr/lcc.
enter_cell:
	FOR fi = 0 TO 9
	IF fst(fi) = 0 THEN IF fr(fi) = cr THEN IF fc(fi) = cc THEN GOSUB take_flag
	NEXT fi
	IF smkq > 0 THEN GOSUB smoke_lay
	lcr = cr
	lcc = cc
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
	' Cell type comes from map2's TOP-LEFT quadrant: road cells are plain
	' ROAD in all four, trees TREE, walls the edged 96..111 -- so the same
	' ">= ROADCH" test works and no separate logical map is needed. Stride
	' is 68 chars and each cell is 2x2, hence row*136 + col*2.
	#t = #mapbase + tr * 136.
	#t = #t + tc
	#t = #t + tc
	t = PEEK(#t)
	RETURN

	' --- enemy: advance esteps pixels, stopping at every cell centre ------
	' The AI (and the stun countdown) only ever needs to act on a 16-px
	' boundary, so the pixels in between are added in ONE step instead of
	' one subroutine call each. The old per-pixel version ran up to 30
	' dispatches per pass and measured ~14 ms -- the single biggest item in
	' the loop. Enemies now also complete a whole frame's travel one at a
	' time rather than interleaved pixel-by-pixel; probe_free still compares
	' CELL coordinates, and a car occupies its cell for many pixels, so the
	' no-overlap guarantee is unchanged.
emove_n:
	emn = esteps
emn_top:
	IF emn = 0 THEN RETURN
	IF estn(i) > 0 THEN GOSUB emn_stun : GOTO emn_top
	IF (#ex(i) AND 15) = 0 THEN IF (#ey(i) AND 15) = 0 THEN GOSUB eai
	' eai can stun this car (it drove into smoke); spend the rest there
	IF estn(i) > 0 THEN GOTO emn_top
	d = edir(i)
	' emk = pixels left until the next cell boundary along d
	IF d = 0 THEN emk = #ey(i) AND 15
	IF d = 1 THEN emk = 16 - (#ex(i) AND 15)
	IF d = 2 THEN emk = 16 - (#ey(i) AND 15)
	IF d = 3 THEN emk = #ex(i) AND 15
	IF emk = 0 THEN emk = 16		' sitting on a centre, heading away
	IF emk > emn THEN emk = emn
	IF d = 0 THEN #ey(i) = #ey(i) - emk
	IF d = 1 THEN #ex(i) = #ex(i) + emk
	IF d = 2 THEN #ey(i) = #ey(i) + emk
	IF d = 3 THEN #ex(i) = #ex(i) - emk
	' The cached cell is this car's ANCHOR, and it only moves when the car
	' has fully ARRIVED on a boundary -- not every pixel.
	'
	' It used to be recomputed from the raw pixels on every chunk, which is
	' ASYMMETRIC. A car moving UP or LEFT crosses into the next cell's pixel
	' range after ONE pixel of travel, so it reported the new cell while its
	' 16-px body still covered nearly all of the old one. That released the
	' old cell to another car and the two visibly sat on top of each other --
	' and the cell-overlap probe read a clean 0 the whole time, because
	' logically they WERE in different cells. Measuring cells was measuring
	' the wrong thing; a PIXEL-overlap probe caught it (see DESIGN.md 1a).
	'
	' Holding the anchor until arrival makes a car in transit reserve both
	' the cell it is leaving (this) and the one it is entering (pf_ahead) --
	' which is what its body actually covers. Two cars cannot double-book the
	' destination either: they decide one at a time inside the FOR i loop,
	' so the second one sees the first already holding it.
	IF (#ex(i) AND 15) = 0 THEN IF (#ey(i) AND 15) = 0 THEN ecra(i) = #ey(i) / 16 : ecca(i) = #ex(i) / 16
	' this car against the player, every chunk (see ckhit)
	GOSUB ckhit
	IF hitf = 1 THEN RETURN
	emn = emn - emk
	GOTO emn_top

	' burn stun frames in bulk -- estn counts pixel steps, as it always did
emn_stun:
	IF estn(i) > emn THEN estn(i) = estn(i) - emn : emn = 0 : RETURN
	emn = emn - estn(i)
	estn(i) = 0
	RETURN

	' reactive pursuit: prefer the axis with the larger gap to the player
	' if open, else the other, else keep going, else any open non-reverse,
	' else reverse (dead end). Scatter inverts the preferences.
eai:
	ecr = ecra(i)
	ecc = ecca(i)
	' probe/probe_free read the cell to test FROM out of cr/cc, so they must
	' be this car's cell before ANY probe below runs. They used to be set
	' further down, after the pursuit maths -- which left eai_commit probing
	' from whatever cr/cc the last caller happened to leave behind, usually
	' the PLAYER's cell via at_center. That validated an unrelated cell, so
	' the commit almost always "succeeded": cars held a post-meeting heading
	' instead of chasing, and the move they held was never really checked,
	' which let two of them share a cell.
	cr = ecr
	cc = ecc
	' smoke check -- skipped outright when no puff is live, which is the
	' normal case (this ran six array reads on every AI decision)
	IF nsmk > 0 THEN GOSUB eai_smoke
	IF estn(i) > 0 THEN RETURN
	' still driving off a meeting? hold the heading while it stays clear
	IF ecmt(i) > 0 THEN GOSUB eai_commit : IF ecmf = 1 THEN RETURN
	#g = pcc
	#g = #g - ecc
	hd = 1
	IF #g >= 32768 THEN hd = 3 : #g = 0 - #g
	#g2 = pcr
	#g2 = #g2 - ecr
	vd = 2
	IF #g2 >= 32768 THEN vd = 0 : #g2 = 0 - #g2
	' Scatter -- the timed head start at the top of a round -- inverts the
	' preferences outright, so the cars genuinely drive away. That is
	' deliberate and time-boxed.
	einv = 0
	IF sct > 0 THEN einv = 1
	IF einv = 1 THEN hd = (hd + 2) AND 3 : vd = (vd + 2) AND 3
	p1 = hd
	p2 = vd
	IF #g2 > #g THEN p1 = vd : p2 = hd
	' DIFFICULTY DIAL (eagg). This used to reuse the scatter inversion: below
	' full aggression the car turned round and drove AWAY from the player for
	' that decision. It does not read as "easier", it reads as the cars being
	' broken and refusing to chase -- which is exactly the complaint.
	'
	' A slack decision now closes on the SHORTER axis instead of the longer
	' one. The car still comes at you every single time; it just takes the
	' less direct line, which loses ground in the open and is much easier to
	' shake around a corner. The real early-round mercy is the speed ramp
	' (espd: 0.875 px/f at round 1 against the player's 1.5), not fleeing.
	IF eagg < 8 THEN IF RANDOM(8) >= eagg THEN eswp = p1 : p1 = p2 : p2 = eswp
	rv = (edir(i) + 2) AND 3
	' Every candidate must be open road AND not already claimed by another
	' enemy (probe_free) -- two cars must never stack on one cell. The car
	' that would have moved in is the one that turns away, because this
	' test runs when IT picks its direction.
	'
	' A car being in the way is NOT by itself a collision: the pack all
	' chases the same target, so first choices clash constantly. An earlier
	' version bumped (and mutually stunned) both cars the moment a first
	' choice was refused, and the pack spent its whole time spinning at
	' itself instead of hunting. Now every alternative is tried first and a
	' refusal is only remembered (ecb); the bump happens further down, when
	' the car has genuinely run out of road.
	ecb = 0
	d = p1
	IF d <> rv THEN GOSUB probe_free : IF pfok = 1 THEN edir(i) = d : RETURN
	IF pfcar = 1 THEN ecb = 1
	d = p2
	IF d <> rv THEN GOSUB probe_free : IF pfok = 1 THEN edir(i) = d : RETURN
	IF pfcar = 1 THEN ecb = 1
	d = edir(i)
	GOSUB probe_free
	IF pfok = 1 THEN RETURN
	IF pfcar = 1 THEN ecb = 1
	' Last resort. p1 and p2 (one horizontal, one vertical) and rv have all
	' just been tried and failed, and the four headings are two horizontal
	' plus two vertical -- so exactly ONE direction here is actually new.
	' Without these two skips this loop re-probed p1 and p2, taking the
	' worst case from 4 probes to 7, and a car boxed in by the other cars
	' hits that worst case constantly.
	fnd = 0
	FOR j = 0 TO 3
	IF fnd = 0 THEN IF j <> rv THEN IF j <> p1 THEN IF j <> p2 THEN d = j : GOSUB probe_free : IF pfok = 1 THEN edir(i) = j : fnd = 1
	NEXT j
	IF fnd = 1 THEN RETURN
	' Dead end: reverse -- but VALIDATED. This used to be an unconditional
	' `edir(i) = rv`, on the assumption that the cell you came from is
	' always open. That holds for walls but not for cars: another one can
	' have moved in behind, and driving into it put two cars in one cell.
	d = rv
	GOSUB probe_free
	IF pfok = 1 THEN GOSUB eai_back : RETURN
	' Boxed in on every side -- spin on the spot and re-decide once someone
	' moves. This is the "cornered by the others and the walls" case; the
	' cars that still have room drive off on their own next decision, which
	' frees this one.
	estn(i) = BUMPFR
	RETURN

	' Turning back the way it came.
	'
	' NO SPIN. Spinning here looked dramatic in isolation but wrecked the
	' chase: cars meet often, and every meeting parked one of them for 64
	' steps, so the pack read as "going crazy and not chasing". A car that
	' meets another now simply turns and keeps driving -- the only stuns
	' left are smoke (intended) and being boxed in on all four sides (rare).
	'
	' Instead it COMMITS to the new heading for a few cells. Without that it
	' re-aims at the player at the very next cell, walks straight back into
	' the same car, and the two of them jitter on the spot.
eai_back:
	edir(i) = rv
	IF ecb = 1 THEN ecmt(i) = 3
	RETURN

	' Holding a post-meeting heading: keep going while the way is clear.
	' Falls through to the normal chase logic the moment it is not.
eai_commit:
	ecmf = 0
	ecmt(i) = ecmt(i) - 1
	d = edir(i)
	GOSUB probe_free
	IF pfok = 1 THEN ecmf = 1 : RETURN
	ecmt(i) = 0
	RETURN

	' is this cell smoked? (only reached while a puff is actually live)
eai_smoke:
	FOR j = 0 TO MAXSMK - 1
	IF st(j) > 0 THEN IF sr(j) = ecr THEN IF sc(j) = ecc THEN estn(i) = SPINFR
	NEXT j
	RETURN

	' probe direction d from (cr,cc): pfok = 1 only if it is road AND no
	' other active enemy occupies that cell
probe_free:
	GOSUB probe
	pfok = 0
	pfcar = 0
	IF t < ROADCH THEN RETURN
	' ROCKS COUNT AS WALLS FOR THE CARS TOO. They used to phase straight
	' through, which was not just inaccurate but UNFAIR: every boulder was a
	' shortcut the pack could take and the player could not, so each round
	' the maze got more lopsided in their favour -- and rocks are the main
	' late-game dial, so it compounded exactly where the game is hardest.
	'
	' Refused like a WALL, not like a car: pfcar stays 0, so a rock never
	' sets the `ecb` "met another car" flag and never triggers the
	' post-meeting heading commitment. Cheap because probes only happen when
	' a car reaches a cell boundary -- about a tenth of a frame's work per
	' car -- not every frame.
	' pfrk is CLEARED HERE, not inside pf_rock: there are no locals, so on a
	' round with no rocks (round 1) the guarded call would leave whatever
	' the last rocked round put there and every probe would read as blocked.
	pfrk = 0
	IF nrk > 0 THEN GOSUB pf_rock
	IF pfrk = 1 THEN RETURN
	pfo = 0
	FOR pfe = 0 TO 3
	IF pfe <> i THEN IF pfe < nen THEN GOSUB pf_chk
	NEXT pfe
	IF pfo = 0 THEN pfok = 1 ELSE pfcar = 1
	RETURN
	' Reads the cached cell rather than dividing both pixel coordinates.
	' This runs up to 4 times per candidate direction and up to 6 directions
	' per AI decision, so it was doing ~24 divisions per decision.
	' A cell is unavailable if another car is IN it, or is DRIVING INTO it.
	' The second half matters: a car only starts occupying a cell once it
	' fully arrives, so two cars approaching the same empty cell from
	' opposite sides were both cleared to enter and ended up sharing it.
	' Treating the cell ahead of a moving car as reserved closes that race.
	' A stunned car is not moving, so it reserves nothing.
	' is (tr,tc) rocked? -> pfrk
pf_rock:
	pfrk = 0
	IF rkrow(tr) = 0 THEN RETURN
	FOR pfr = 0 TO nrk - 1
	IF rkr(pfr) = tr THEN IF rkc(pfr) = tc THEN pfrk = 1
	NEXT pfr
	RETURN
pf_chk:
	IF ecra(pfe) <> tr THEN GOTO pf_ahead
	IF ecca(pfe) <> tc THEN GOTO pf_ahead
	pfo = 1
	RETURN
pf_ahead:
	IF estn(pfe) > 0 THEN RETURN
	pfr2 = ecra(pfe)
	pfc2 = ecca(pfe)
	pfd = edir(pfe)
	IF pfd = 0 THEN pfr2 = pfr2 - 1
	IF pfd = 1 THEN pfc2 = pfc2 + 1
	IF pfd = 2 THEN pfr2 = pfr2 + 1
	IF pfd = 3 THEN pfc2 = pfc2 - 1
	IF pfr2 <> tr THEN RETURN
	IF pfc2 <> tc THEN RETURN
	pfo = 1
	RETURN


	' step every enemy's visual heading one notch toward its real one
eang_step:
	FOR ea = 0 TO 3
	IF ea < nen THEN GOSUB eang1
	NEXT ea
	RETURN
eang1:
	' A smoked car SPINS: while its stun counter runs it just keeps
	' rotating one notch per tick, so it whirls through several full turns
	' (SPINFR 96 / TURNRT 3 = 32 notches = 4 revolutions) before its
	' heading settles and it drives on. emove_n keeps it parked meanwhile.
	IF estn(ea) > 0 THEN eang(ea) = (eang(ea) + 1) AND 7 : RETURN
	eat2 = edir(ea) + edir(ea)
	IF eang(ea) = eat2 THEN RETURN
	eat3 = eat2 - eang(ea)
	eat3 = eat3 AND 7
	IF eat3 > 4 THEN eang(ea) = (eang(ea) + 7) AND 7 ELSE eang(ea) = (eang(ea) + 1) AND 7
	RETURN

	' enemy i on-screen? -> vis, x2, y2 (char units; the 16-px car spans
	' 2 chars, so hide at the edges to avoid coordinate wrap)
evis:
	' Screen pixel offset first; the char-unit visibility test then comes
	' from it with a shift instead of a second pair of divides, and the
	' camera-origin multiplies are hoisted into the main loop (#cx8/#cy8).
	#gx = #ex(i) - #cx8
	#gy = #ey(i) - #cy8
	t = #gx / 8
	IF t = 0 THEN RETURN
	IF t >= 22 THEN RETURN
	t2 = #gy / 8
	IF t2 = 0 THEN RETURN
	IF t2 >= 22 THEN RETURN
	x2 = #gx
	y2 = #gy
	vis = 1
	RETURN

	' All active cars against the player. Used from the PLAYER's movement
	' chunk loop; clobbering i is safe there (the main loop's own FOR i
	' loops all run later in the pass).
ckhit_all:
	FOR ckn = 0 TO 3
	IF ckn < nen THEN i = ckn : GOSUB ckhit
	NEXT ckn
	RETURN

	' player-enemy overlap test for enemy i -> hitf
	' Called from INSIDE both movement loops, after every chunk, not once
	' per pass at the end. Detection needs |dx| < 12 on both axes -- a 24-px
	' window -- and the pair can close 1.5 + 1.875 px per frame, so a single
	' end-of-pass sample let them jump straight through each other whenever
	' #fd spiked. That is the "player drove through an enemy" bug.
ckhit:
	' NO challenge-stage exemption. A parked red car is still a car: the
	' arcade lets an idle one kill you, and driving through one looked like
	' a bug anyway. `chal` switches off their PURSUIT, never their hitbox.
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
	' one press = SMKPUFF puffs, charged up front. No fuel, no smoke.
smoke_fire:
	IF #fuel < SMKCOST THEN RETURN
	#fuel = #fuel - SMKCOST
	smkq = SMKPUFF
	RETURN

smoke_lay:
	smkq = smkq - 1
smoke_put:
	' recycling a still-live slot: wipe its old block first, otherwise the
	' active count would double-count this slot
	IF st(nsm) = 0 THEN nsmk = nsmk + 1
	IF st(nsm) > 0 THEN er2 = sr(nsm) : ec2 = sc(nsm) : GOSUB cell_restore
	sr(nsm) = lcr
	sc(nsm) = lcc
	st(nsm) = SMKTTL
	or2 = lcr
	oc2 = lcc
	ob = SMOKECH
	GOSUB put_cell
	nsm = nsm + 1
	IF nsm >= MAXSMK THEN nsm = 0
	RETURN

	' age every live puff by #fd frames; an expired one wipes its own block
smk_tick:
	FOR j = 0 TO MAXSMK - 1
	IF st(j) > 0 THEN GOSUB smk_age
	NEXT j
	RETURN
smk_age:
	smka = #fd
	IF st(j) > smka THEN st(j) = st(j) - smka : RETURN
	st(j) = 0
	nsmk = nsmk - 1
	er2 = sr(j)
	ec2 = sc(j)
	GOSUB cell_restore
	RETURN

	' --- restore logical cell (er2,ec2) to its true map art ---------------
	' A 2x2 SCREEN blit straight out of map2, so edged road cells next to
	' walls come back correctly -- poking ROADCH into all four quadrants
	' (what put_cell does) flattened that edging. Off-window cells are
	' simply skipped: nothing of them is on screen, and the next pan calls
	' draw_view, which only ever paints puffs that are still live.
cell_restore:
	crr = er2 + er2
	crc = ec2 + ec2
	crsr = crr - camr
	IF crsr >= 23 THEN RETURN
	crsc = crc - camc
	IF crsc >= 23 THEN RETURN
	#crs = crr * 68.
	#crs = #crs + crc
	#crd = crsr * 32.
	#crd = #crd + crsc
	IF mz = 0 THEN SCREEN map2_1, #crs, #crd, 2, 2, 68
	IF mz = 1 THEN SCREEN map2_2, #crs, #crd, 2, 2, 68
	IF mz = 2 THEN SCREEN map2_3, #crs, #crd, 2, 2, 68
	IF mz = 3 THEN SCREEN map2_4, #crs, #crd, 2, 2, 68
	RETURN

	' --- flag pickup (fi = slot, car at its cell) -------------------------
	' Values 100,200..1000 by pickup order; after S everything doubles;
	' L additionally pays fuel-bar-px x 10. #score is in units of 10 pts.
take_flag:
	fst(fi) = 1
	nfl = nfl + 1		' flags left to finish the round
	vstep = vstep + 1	' value progression -- resets on death
	#val = vstep * 10
	IF #val > 100 THEN #val = 100
	' Base points before any doubling (score is kept in units of 10), and
	' whether the special is already doubling THIS flag -- sgot is updated
	' just below, so it has to be read first.
	#pvb = #val * 10
	pvm0 = sgot
	IF sgot = 1 THEN #val = #val * 2
	IF fi = sidx THEN sgot = 1
	IF fi = lidx THEN #val = #val + #fuel / 12
	' Popup. Normally the base value with "x2" when the special is doubling
	' it, so it reads "500x2" rather than a bare 1000. The LUCKY flag is the
	' exception: its fuel bonus is added after the doubling and is not
	' itself doubled, so base-and-multiplier cannot express what it paid --
	' it shows the plain total. (It used to show the base either way, which
	' understated the lucky flag by up to 640 points.)
	#pvv = #pvb
	pvm = pvm0
	IF fi = lidx THEN #pvv = #val * 10 : pvm = 0
	pvt = POPFR
	pvr = fr(fi)
	pvc = fc(fi)
	GOSUB pop_build
	#score = #score + #val
	IF #score > #hi THEN #hi = #score : GOSUB prt_hi
	GOSUB prt_score
	IF olg = 0 THEN IF #score >= 2000 THEN olg = 1 : lives = lives + 1 : GOSUB draw_lives
	' restore its cell from the map (not a flat ROADCH poke -- that dropped
	' the edging on road cells that sit against a wall), then clear its
	' radar dot
	er2 = fr(fi)
	ec2 = fc(fi)
	GOSUB cell_restore
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

	' SHOW SPARES, NOT TOTAL CARS. The icons are the cars held in RESERVE,
	' excluding the one currently being driven -- so a fresh 3-car game
	' shows TWO icons, and the last car shows none. Drawing `lives` itself
	' is the anti-convention: every arcade game of this era counts reserves,
	' so an icon that vanishes the instant you start a life reads as though
	' you had already crashed. See CLAUDE.md -- this is a repo-wide rule.
	'
	' The guard matters: draw_lives IS called with lives = 0 (crash decrements
	' then redraws before testing for game over), and these are unsigned, so
	' a bare `lives - 1` would wrap to 255 and light every icon at the exact
	' moment the player has none.
draw_lives:
	lvsp = 0
	IF lives > 0 THEN lvsp = lives - 1
	FOR li = 0 TO 3
	t2 = 32
	IF li < lvsp THEN t2 = 129
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
	' The camera is a pure function of the car's position, so when the car
	' has not moved -- every frame it spends parked against a wall, mid-turn,
	' or stunned -- the whole clamp below recomputes an answer it already
	' has. Two compares replace ~24 statements.
	IF #px = #ucx THEN IF #py = #ucy THEN RETURN
	#ucx = #px
	#ucy = #py
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
	' Flags and smoke are CHARACTERS again (sprites made them read as cars
	' and sit badly against the road). The original char flicker came from
	' the WAIT that used to sit between the blit and these overlay pokes:
	' the blit landed one frame and the overlays the next, so at ~3 pans a
	' second the flags strobed. With NO wait, both go into the same frame's
	' buffered batch and are applied at the same vblank -- no flicker.
draw_view:
	#voff = camr * 68.
	#voff = #voff + camc
	IF mz = 0 THEN SCREEN map2_1, #voff, 0, 24, 24, 68
	IF mz = 1 THEN SCREEN map2_2, #voff, 0, 24, 24, 68
	IF mz = 2 THEN SCREEN map2_3, #voff, 0, 24, 24, 68
	IF mz = 3 THEN SCREEN map2_4, #voff, 0, 24, 24, 68
	FOR oi = 0 TO 9
	IF fst(oi) = 0 THEN GOSUB ov_flag
	NEXT oi
	IF nrk > 0 THEN GOSUB ov_rocks
	FOR j = 0 TO MAXSMK - 1
	IF st(j) > 0 THEN GOSUB ov_smoke
	NEXT j
	RETURN
ov_flag:
	or2 = fr(oi)
	oc2 = fc(oi)
	ob = 0			' F = chars 0-3
	IF oi = sidx THEN ob = 4	' S = chars 4-7
	IF oi = lidx THEN ob = 8	' L = chars 8-11
	GOSUB put_cell
	RETURN
	' Safe to run 0 TO nrk-1 unguarded only because the caller checked
	' nrk > 0 -- a computed FOR 1 TO 0 still executes its body once here.
ov_rocks:
	FOR oi = 0 TO nrk - 1
	GOSUB ov_rock
	NEXT oi
	RETURN
ov_rock:
	or2 = rkr(oi)
	oc2 = rkc(oi)
	' OFF-WINDOW REJECT, one test instead of four put_char calls. Rocks are
	' spread over a 34x58 maze and the window shows 12x12 cells, so most of
	' them are nowhere near the screen on any given pan -- and put_cell
	' unconditionally called put_char four times for each. This is what made
	' the first cut cost 18% of the loop rate. Unsigned wrap does the
	' negative side for free: a cell above/left of the camera underflows to
	' a large value and trips the same >= 24 test (put_char's own trick).
	t = or2 + or2
	t = t - camr
	IF t >= 24 THEN RETURN
	t2 = oc2 + oc2
	t2 = t2 - camc
	IF t2 >= 24 THEN RETURN
	ob = ROCKCH
	GOSUB put_cell
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
	' cache this flag's dot address + mask for rd_erase (flags never move)
	#fda(fi) = #da
	fdm(fi) = dmsk
	a = VPEEK(#da)
	a = a OR dmsk
	VPOKE #da,a
	#db = #da + 1
	a = VPEEK(#db)
	a = a OR dmsk
	VPOKE #db,a
	#db = #da + $2000
	a = $B4
	IF fi = sidx THEN a = $84
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
	' Only flags sharing this pattern byte need re-baking. The address test
	' now uses the cached #fda() instead of running dot_addr ten times per
	' radar tick, which is where most of that ~4 ms went.
	FOR fi = 0 TO 9
	IF fst(fi) = 0 THEN IF #fda(fi) = #mpa(mi) THEN GOSUB rt_rebake
	NEXT fi
	RETURN
rt_rebake:
	#da = #fda(fi)
	dmsk = fdm(fi)
	a = VPEEK(#da)
	a = a OR dmsk
	VPOKE #da,a
	#pb = #da + 1
	a = VPEEK(#pb)
	a = a OR dmsk
	VPOKE #pb,a
	#pb = #da + $2000
	a2 = $B4
	IF fi = sidx THEN a2 = $84
	VPOKE #pb,a2
	#pb = #pb + 1
	VPOKE #pb,a2
	RETURN

	' --- flag-blip sound envelope ----------------------------------------
	' Also frame-delta paced, so the blip is the same length whatever the
	' loop is doing (see sct_tick).
sfx_tick:
	sfxa = #fd
	IF sfxt > sfxa THEN sfxt = sfxt - sfxa ELSE sfxt = 0
	IF sfxt = 0 THEN SOUND 2,,0 : RETURN
	#sf = 100 + sfxt * 30
	SOUND 2,#sf,12
	RETURN

	' --- music --------------------------------------------------------------
	' Two voices on channels 0 and 1 at a FIXED, deliberately low volume so
	' the engine and the effects stay on top. 64 steps at MUSTICK frames is
	' about ten seconds before it comes round again.
mus_start:
	mup = 0
	mut = 1
	' switched off on the title? then the player never starts
	IF musen = 0 THEN mut = 0
	RETURN
mus_off:
	mut = 0
	SOUND 0,,0
	SOUND 1,,0
	RETURN
mus_tick:
	IF mut = 0 THEN RETURN		' stopped
	mut = mut - 1
	IF mut > 0 THEN RETURN
	mut = MUSTICK
	#mua = #muss + mup + mup
	mun = PEEK(#mua)
	#mua = #mua + 1
	mub = PEEK(#mua)
	IF mun > 0 THEN musv = MUSVOL : GOSUB mus_mel
	IF mub > 0 THEN musv = MUSBAS : GOSUB mus_bas
	mup = mup + 1
	IF mup >= 64 THEN mup = 0
	RETURN
	' note index -> 16-bit divider (stored hi,lo), then sound it
mus_mel:
	#mua = #musf + mun + mun
	mhi = PEEK(#mua)
	#mua = #mua + 1
	mlo = PEEK(#mua)
	GOSUB mus_word
	SOUND 0,#mf,musv
	RETURN
mus_bas:
	#mua = #musf + mub + mub
	mhi = PEEK(#mua)
	#mua = #mua + 1
	mlo = PEEK(#mua)
	GOSUB mus_word
	SOUND 1,#mf,musv
	RETURN

	' Rebuild the 16-bit divider from the table's hi/lo bytes WITHOUT a
	' constant multiply. "#mf = mhi * 256." compiles to a plain CLR on this
	' backend -- confirmed by reading the generated .a99 -- so every note
	' came out as just its low byte: pitches wrong, anything over 255
	' wrapping, and the tune unrecognisable. Eight doublings are exact and
	' cost nothing at seven notes a second.
	' NOTE: the repo hazard list said this truncation starts at 2048. It
	' does not -- 256 is already broken.
mus_word:
	#mf = mhi
	#mf = #mf + #mf
	#mf = #mf + #mf
	#mf = #mf + #mf
	#mf = #mf + #mf
	#mf = #mf + #mf
	#mf = #mf + #mf
	#mf = #mf + #mf
	#mf = #mf + #mf
	#mf = #mf + mlo
	RETURN

	' --- engine ------------------------------------------------------------
	' Channel 3 in PERIODIC mode (control 0-3) is a buzz rather than a hiss,
	' which reads as an engine. Re-issued only when the state changes, so
	' the hot loop pays two compares: rolling = higher, faster buzz; parked
	' against a wall or mid-turn = lower and quieter; dry tank = idling.
eng_tick:
	engc = 1
	IF blocked = 1 THEN engc = 2
	IF turning = 1 THEN engc = 2
	IF #fuel = 0 THEN engc = 2
	IF engc <> engp THEN GOSUB eng_set
	IF engc = 2 THEN GOSUB eng_idle
	RETURN

	' A STOPPED CAR STILL HAS AN ENGINE. White noise here was a hiss, which
	' is not an engine at all -- an idling motor is the SAME motor, just
	' turning over slowly and unevenly. So the idle keeps the driving note
	' (periodic rate 2) and becomes LUMPY instead: it chugs between two low
	' volumes about ten times a second. Pitch cannot go lower -- rate 2 is
	' already the floor for periodic noise, and rate 3 clocks the noise from
	' channel 2, which is the SFX channel -- so "quieter" is what carries
	' the drop. Mind the SCALE though: SN76489 volume is LOGARITHMIC, about
	' 2 dB a step. A first cut chugged 5/2 against a driving 11, i.e. 12-18
	' dB down, which is not "quiet", it is inaudible -- and that is exactly
	' how it came back: "there is no sound". 9/6 is 4-10 dB down: clearly
	' under the driving note, clearly still an engine. Settled at 10/7 --
	' one step louder again, i.e. 2-8 dB under driving.
eng_idle:
	engt = engt + #fd
	IF engt < ENGCHG THEN RETURN
	engt = 0
	engv = 1 - engv
	IF engv = 1 THEN SOUND 3,2,10 ELSE SOUND 3,2,7
	RETURN
	' Channel 3 control: bit 2 picks the source (0-3 PERIODIC, 4-7 white
	' noise) and the low 2 bits pick the shift rate (0 = clk/512, 1 =
	' clk/1024, 2 = clk/2048; 3 follows channel 2, which is the SFX channel,
	' so it is unusable here -- the engine would change pitch under every
	' flag blip).
	'
	' Periodic noise repeats every 15 shifts, so the audible pitch is
	' clk/(rate x 15): rate 1 is ~233 Hz and rate 2 is ~116 Hz. Driving used
	' rate 1, and 233 Hz of constant buzz is a whine, not a motor. Rate 2 --
	' the lowest periodic pitch the chip offers without borrowing channel 2 --
	' is an octave down and reads as an engine.
	'
	' Both states use the SAME note -- it is one car with one engine. What
	' separates them is loudness and steadiness: driving is a steady 11,
	' idling chugs quietly between 5 and 2 (see eng_idle). An earlier cut
	' gave the stopped state WHITE noise to keep it clear of the driving
	' note, which distinguished them fine but stopped sounding like an
	' engine at all -- it was a hiss.
eng_set:
	engp = engc
	engt = 0
	engv = 0
	IF engc = 1 THEN SOUND 3,2,11 ELSE SOUND 3,2,7
	RETURN
eng_off:
	engp = 0
	SOUND 3,,0
	RETURN

	' --- data -------------------------------------------------------------
	' TI bank 0: the logical map (gameplay PEEKs, always visible)
	INCLUDE "minifont.bas"

	INCLUDE "music.bas"

	' TI bank 1: the doubled char map (SCREEN blits during gameplay)
	BANK 1
	INCLUDE "map2_1.bas"
	BANK 2
	INCLUDE "map2_2.bas"
	BANK 3
	INCLUDE "map2_3.bas"
	BANK 4
	INCLUDE "map2_4.bas"

	' TI bank 2: art, tiles, radar tables, item lists (init / round setup)
	BANK 5
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

	' tree (112) + road (113) tiles and their per-row colors
misc_chars:
	DATA BYTE $3C,$7E,$FF,$FF,$FF,$7E,$3C,$00	' tree blob
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00	' road (solid bg)
misc_colors:
	DATA BYTE $3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C	' light green on dark green
	DATA BYTE $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA	' tan on tan

	' lives icon (129): the car silhouette at 8x8 -- four wheels sticking
	' out, body, rear wing -- in yellow, matching the arcade's little cars
live_char:
	DATA BYTE $42,$3C,$7E,$3C,$3C,$7E,$42,$7E
live_color:
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1	' light yellow on black

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

	INCLUDE "tiles.bas"
	' crash starburst + score-popup glyphs (assets/genbang.py)
	INCLUDE "bang.bas"
	' per-maze flag cells / start / spawns (assets/genmaps4.py)
	INCLUDE "items.bas"

	INCLUDE "rocks.bas"
