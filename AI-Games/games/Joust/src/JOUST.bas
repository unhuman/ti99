	' ==========================================================================
	' JOUST -- CVBasic, dual target TI-99/4A + ColecoVision.
	'
	' See DESIGN.md. The rules that shaped this file, all from CLAUDE.md 3A and
	' TRUNCATION.md, because every one of them fails SILENTLY here:
	'
	'   * A plain variable is 8-BIT. Anything over 255 -- a pixel position in
	'     8.8 fixed point, a screen offset past row 7, a frame count -- is a #var.
	'   * A CONST over 255 TRUNCATES. Values above 255 are written as bare
	'     literals at the point of use, never named.
	'   * Every #var comparison is UNSIGNED, so velocities carry a +32768 bias
	'     and no comparison ever crosses zero.
	'   * `<cmp> AND <cmp>` is miscompiled by the 9900 backend. Nested IFs only.
	'   * A sprite at y=208 TERMINATES the sprite list. Hidden sprites go to 209.
	'   * A GOSUB left by GOTO never pops; on ColecoVision's 1 KB that is fatal.
	' ==========================================================================

	CONST GRAV = 44			' added to #vy every frame. Heavier than it looks:
					' Joust's mount FALLS, and the flap has to fight it
	CONST ACCX = 52			' horizontal acceleration while steering
	CONST FRIC = 12			' horizontal decay when not steering
	CONST NPLAT = 10		' islands, DIM 0..9 -- MEASURED, see assets/refmap.py
	CONST NKN = 6			' knights, DIM 0..5 -- SIX. Joust is meant to be crowded
	CONST NEGG = 4			' eggs, DIM 0..3
	CONST LAVAY = 176		' feet at or below this pixel row are in the lava
	CONST TOPY = 8			' ceiling: sprite top cannot go above this
	CONST SPRHID = 209		' NOT 208 -- 208 terminates the sprite list
	CONST MH = 16			' MOUNT HEIGHT. A 12 px figure in the 16 px cell:
					' A FULL-SIZE MOUNT. Shrinking the figure to 12 and
					' then 14 bought headroom by making the birds
					' smaller, which is paying in the wrong currency.
					' Every island moved DOWN 8 px instead, which costs
					' nothing and gives the top ledge 8 px of margin.
	CONST BLANK = 32
	CONST PLATL = 128
	CONST PLATM = 129
	CONST PLATR = 130
	CONST LAVAA = 131
	CONST LIFECH = 134
	CONST PADCH = 135
	CONST ARMCH = 136
	CONST NPAD = 5			' pads, DIM 0..4 -- one is on the BASE
	CONST KDEAD = 0
	CONST KLIVE = 1
	CONST KMATZ = 2		' materialising on a pad
	CONST KFOOT = 3		' hatched, on foot, waiting for a mount

	' Velocities are stored BIASED by +32768 so that every comparison stays in
	' unsigned territory: "rising" is #vy < 32768, never #vy < 0. 32768 itself is
	' written as a literal everywhere -- as a CONST it would truncate to 0.

	DIM #plx1(NPLAT)		' platform left edge, pixels
	DIM #plx2(NPLAT)		' platform right edge
	DIM ply(NPLAT)			' island surface row, pixels (all < 256)
	DIM plon(NPLAT)			' 1 present, 0 burned away -- see erosion, below

	' MATERIALISATION PADS. Nothing simply appears in mid-air in Joust: birds
	' MATERIALISE on marked pads set into the islands. Two rules make them matter
	' rather than being decoration, and both are the player's to exploit:
	'   * a knight may not appear on the pad the PLAYER is standing on or near
	'   * a knight may not appear at all until a pad is FREE
	' So camping a pad denies the wave a spawn point, and standing over the last
	' free one stalls the spawn entirely -- which is a real tactic, not a bug.
	DIM padx(NPAD)			' pad centre x, pixels
	DIM pady(NPAD)			' sprite-top y for something standing on it
	DIM padu(NPAD)			' 0 free, 1 occupied by a materialising actor

	' THE LAVA TROLL (wave 3+). A hand comes out of a pit at a bird flying low over
	' it, and drags it under. Flapping is the escape, and the arcade lengthens the
	' reach and stiffens the grip as the waves pass -- so the pits stop being
	' merely fatal and start being a place you must not loiter.
	'   trst  0 idle, 1 reaching up, 2 has hold of you
	'   tresc flaps banked toward getting free
	'
	' THE PTERODACTYL (wave 8, or any wave that drags). Faster than anything else
	' and INVULNERABLE except to a level lance straight down an open mouth.
	'   ptst  0 absent, 1 flying
	'   ptmo  mouth timer; open on the low half of the cycle

	DIM #kx(NKN)			' knight x, 8.8
	DIM #ky(NKN)			' knight y, 8.8
	DIM #kvx(NKN)			' knight x velocity, biased
	DIM #kvy(NKN)			' knight y velocity, biased
	DIM ktier(NKN)			' 0 bounder, 1 hunter, 2 shadow lord
	DIM kon(NKN)			' 0 dead, 1 mounted, 2 on foot
	DIM kface(NKN)			' 0 right, 1 left
	DIM kfrm(NKN)			' animation frame 0..3
	DIM kflp(NKN)			' frames until this knight may flap again
	DIM kty(NKN)			' target altitude, pixels -- what the AI steers to
	DIM ktx(NKN)			' target x, pixels
	DIM kwan(NKN)			' Bounder wander timer: frames until it re-rolls
	DIM kmat(NKN)			' materialisation countdown, frames
	DIM kfa(NKN)			' flap animation, frames remaining
	DIM kpad(NKN)			' which pad it is materialising on

	' THE RESCUE BIRD. When an egg hatches it produces a MAN ON FOOT, not a mounted
	' knight -- and a riderless buzzard then flies in from the edge, collects him,
	' and the pair resume the attack. That gap is the player's window: a knight on
	' foot is helpless and can be run down for the egg score, so ignoring an egg
	' costs you twice if you also miss the man.
	'
	' One bird at a time, sprite 11. A second hatch waits its turn rather than
	' costing another sprite slot on a machine that drops the 5th on a scanline.

	DIM #ex(NEGG)			' egg x, 8.8
	DIM #ey(NEGG)			' egg y, 8.8
	DIM #evx(NEGG)			' egg x velocity, biased
	DIM #evy(NEGG)			' egg y velocity, biased
	DIM est(NEGG)			' 0 none, 1 falling, 2 resting, 3 hatching
	DIM etier(NEGG)			' tier of the knight this egg came from
	DIM #etm(NEGG)			' frames until the next state change

	stwv = 1			' 838 on the title overrides this
	GOSUB setup
	GOTO title_screen

	' ------------------------------------------------------------------ setup
setup:
	SPRITE FLICKER OFF		' all-or-nothing in CVBasic: it would strobe the
					' player too. Instead the player is sprite 0 --
					' highest priority, never the one the VDP drops.
	' THE ARCADE FACE. Replaces CVBasic's stock 8x8, which is a thin generic ASCII
	' font and reads like a BASIC listing rather than an arcade cabinet -- undoing a
	' good deal of what the sprites are doing. 59 characters, 32-90, contiguous.
	' Colours are left alone: a DEFINE COLOR run this long would cost another 472
	' bytes to say "white" 59 times.
	DEFINE CHAR 32,59,font_bits
	DEFINE CHAR PLATL,9,chr_plat_l
	DEFINE COLOR PLATL,9,col_chars
	DEFINE SPRITE 0,4,spr_mount_r	' patterns 0,4,8,12  -- facing right
	DEFINE SPRITE 4,4,spr_mount_l	' patterns 16,20,24,28 -- facing left
	DEFINE SPRITE 8,1,spr_egg	' pattern 32
	DEFINE SPRITE 9,1,spr_runner	' pattern 36
	DEFINE SPRITE 10,1,spr_egg_x	' pattern 40 -- cracked, about to hatch
	DEFINE SPRITE 11,1,spr_hand	' pattern 44 -- the troll's fist
	DEFINE SPRITE 12,1,spr_pt_s	' pattern 48 -- pterodactyl, mouth shut
	DEFINE SPRITE 13,1,spr_pt_o	' pattern 52 -- mouth OPEN, the only target
	DEFINE SPRITE 14,1,spr_arm	' pattern 56 -- the troll's forearm

	' THE ISLANDS -- MEASURED FROM AN ARCADE SCREENSHOT, not invented. See
	' assets/refmap.py, which classifies every pixel of a reference shot as rock
	' or lava and prints the spans scaled from Williams' 292x240 to our 256x192.
	'
	' !! THE FLOOR IS FULL WIDTH, AND THE LAVA IS AT THE EDGES. The first,
	' hand-written version of this table put the gap in the MIDDLE and had no
	' bridges at all, so the player fell through the centre of the world on wave
	' 1. In the arcade the floor spans the whole screen for waves 1-2; the solid
	' rock beneath it only spans the middle, so when the END sections burn away at
	' wave 3 the lava is exposed at the LEFT AND RIGHT EDGES.
	'
	' The two right-hand ledges deliberately OVERLAP in x: the upper overhangs the
	' lower, and crossing the lower one halts you against it. That is in the
	' arcade and it is what makes the right side awkward to leave.
	' MEASURED FROM THE REFERENCE SHOT the user supplied (assets/refmap.py does
	' the same job on any screenshot: classify every pixel as rock / pad / lava and
	' scale the spans from the shot's size to our 256x192).
	'
	' Ten islands, and the shape is not symmetric -- the left side stacks a high
	' ledge over a lower one, the right side likewise but offset, and a small ledge
	' sits alone at the top right. That asymmetry is the level design; a tidy
	' mirror-image arena would play quite differently.
	' EVERY SURFACE IS 8 PX (one character row) LOWER than the reference measure.
	' The reference has the top ledge at 24, which with a full-size 16 px mount
	' demands a sprite top of 8 -- and 8 is the ceiling limit itself, so the ledge
	' was reachable only by arriving at exactly the altitude the ceiling stops you.
	' Dropping the whole arena a row costs nothing (there is dead space at the top
	' either way) and gives it 8 px of margin.
	#plx1(0) = 40  : #plx2(0) = 207 : ply(0) = 168	' BASE, solid rock beneath
	#plx1(1) = 0   : #plx2(1) = 39  : ply(1) = 168	' bridge left  -- burns wave 3
	#plx1(2) = 208 : #plx2(2) = 255 : ply(2) = 168	' bridge right -- burns wave 3
	#plx1(3) = 0   : #plx2(3) = 55  : ply(3) = 112	' left, middle height
	#plx1(4) = 168 : #plx2(4) = 223 : ply(4) = 104	' right, middle height
	#plx1(5) = 72  : #plx2(5) = 151 : ply(5) = 64	' upper middle, the big one
	#plx1(6) = 88  : #plx2(6) = 143 : ply(6) = 128	' lower middle
	#plx1(7) = 0   : #plx2(7) = 31  : ply(7) = 56	' left, high
	#plx1(8) = 216 : #plx2(8) = 255 : ply(8) = 56	' right, high
	#plx1(9) = 152 : #plx2(9) = 183 : ply(9) = 32	' top right, small

	' FIVE PADS, and one of them is on the BASE -- that is where the player
	' materialises, and it is the pad knights most often find blocked. y is the
	' SPRITE TOP for a bird standing on that surface, i.e. surface - 16.
	padx(0) = 104 : pady(0) = 152		' base            (surface 168)
	padx(1) = 96  : pady(1) = 48		' upper middle    (surface  64)
	padx(2) = 192 : pady(2) = 88		' right, middle   (surface 104)
	padx(3) = 16  : pady(3) = 96		' left, middle    (surface 112)
	padx(4) = 160 : pady(4) = 16		' top right       (surface  32)
	RETURN

	' EROSION. Deterministic, never random -- a player has to be able to learn the
	' layout. The bridges burn at wave 3 and stay gone; from wave 6 one further
	' ledge goes each wave, in a fixed order; and every Egg wave restores the lot,
	' exactly as the arcade does.
set_islands:
	FOR sii = 0 TO NPLAT - 1
		plon(sii) = 1
	NEXT sii
	IF wave < 3 THEN RETURN			' waves 1-2: walk the whole floor
	plon(1) = 0				' the bridges are gone for good
	plon(2) = 0
	sie = wave			' egg wave? then everything is back
	WHILE sie >= 5
		sie = sie - 5
	WEND
	IF sie = 0 THEN
		plon(1) = 1
		plon(2) = 1
		RETURN
	END IF
	IF wave < 6 THEN RETURN
	' one more ledge per wave from 6, cycling 3,4,5,6 so it is learnable
	' Cycle 3,4,5,6 -- the four ledges a player most relies on. The high pair and
	' the top-right sliver stay, so the arena never loses its whole upper half.
	sin = wave - 6
	sin = sin AND 3
	plon(3 + sin) = 0
	RETURN

	' ---------------------------------------------------------- title screen
title_screen:
	GOSUB hide_all
	CLS
	PRINT AT 100,"J O U S T"
	PRINT AT 232,"THE HIGHER LANCE WINS"
	PRINT AT 328,"FIRE     FLAP"
	PRINT AT 392,"LEFT/RIGHT    STEER"
	PRINT AT 520,"PRESS FIRE TO START"
	PRINT AT 680,"2026 UNHUMAN & CLAUDE"
	btnr = 0
	t8 = 0
	' SEED THE EDGE DETECTOR WITH WHAT IS ALREADY HELD. Seeding with 15 ("no key")
	' asserts nothing is down when the title starts, which stops being true the
	' moment anything precedes it -- a key still held would read as a fresh press.
	tkl = cont1.key
title_wait:
	WAIT
	' 8-3-8 OPENS THE WAVE SELECT. Edge triggered on cont1.key, which gives 0-9 on
	' both targets (TI keyboard, Coleco keypad) and 15 for nothing -- and NOT on the
	' joystick, whose vertical axis shares a line with ALPHA LOCK on the TI.
	tk = cont1.key
	IF tk <> tkl THEN
		tkl = tk
		IF tk = 8 THEN
			IF t8 = 2 THEN
				GOSUB setup838
				GOTO new_game
			END IF
			t8 = 1
		ELSE
			IF tk = 3 THEN
				IF t8 = 1 THEN
					t8 = 2
				ELSE
					t8 = 0
				END IF
			ELSE
				IF tk < 15 THEN t8 = 0
			END IF
		END IF
	END IF
	' RELEASE BEFORE PRESS. Arriving here with fire still held from the last
	' game would otherwise start the next one before the screen was read.
	IF btnr = 0 THEN
		IF cont1.button = 0 THEN btnr = 1
	ELSE
		IF cont1.button THEN GOTO new_game
	END IF
	GOTO title_wait

	' ------------------------------------------------------------- new game
	' Wave selector: two digits, echoed as they are typed. Undocumented on screen
	' -- there is no room for a caption -- so it lives in README.md instead.
setup838:
	GOSUB hide_all
	CLS
	PRINT AT 264,"START AT WAVE 01-99"
	PRINT AT 360,"ENTER TWO DIGITS"
	' !! #rdp IS 16-BIT ON PURPOSE. A plain variable is 8-BIT, so 463 would
	' truncate to 207 and the digits would appear at row 6 instead of row 14 --
	' silently, and looking like somebody's odd layout choice (TRUNCATION.md 1a).
	#rdp = 463			' row 14, col 15
	GOSUB rd_dig
	sd1 = tdg
	GOSUB rd_dig
	stwv = sd1 * 10 + tdg
	IF stwv < 1 THEN stwv = 1
	' LET THE SECOND BEEP DECAY BEFORE LEAVING. The first digit's note is silenced
	' by the second call's wait loop; after the second there is no loop left, and
	' nothing between here and the game loop ticks the sound.
	FOR sdw = 0 TO 5
		WAIT
		GOSUB sfx_tick
	NEXT sdw
	RETURN

	' One digit: wait for every key to be RELEASED, then for a digit. Without the
	' release wait the 8 that opened this screen is read as the first digit.
rd_dig:
rd_rel:
	WAIT
	GOSUB sfx_tick
	IF cont1.key <> 15 THEN GOTO rd_rel
rd_get:
	WAIT
	GOSUB sfx_tick
	tdg = cont1.key
	IF tdg > 9 THEN GOTO rd_get
	#rda = #rdp
	#rda = #rda + 6144
	rdv = 48 + tdg
	VPOKE #rda,rdv
	#rdp = #rdp + 1
	SOUND 0,500,9
	sf0 = 3
	RETURN

new_game:
	#score = 0			' stored in TENS of points: every award in
					' Joust is a multiple of 50, so this is exact
					' and 16 bits then reaches 655,350.
	lives = 3
	' 838 sets stwv; new_wave increments, so start one below it.
	wave = stwv - 1
	pover = 0
	GOSUB new_wave
	GOTO main

	' ------------------------------------------------------------- new wave
new_wave:
	wave = wave + 1
	ecoll = 0			' eggs collected this wave -> award ladder
	#wvt = 0			' frames elapsed in this wave (pterodactyl clock)
	trst = 0
	ptst = 0
	' AGGRESSION RISES WITH THE WAVE, not just with the tier. A Bounder in wave 12
	' should not fly like a Bounder in wave 1: same strategy, sharper execution.
	agg = wave
	IF agg > 16 THEN agg = 16
	GOSUB set_islands		' erosion first: draw_field draws what survives
	GOSUB draw_field
	GOSUB spawn_player

	' KNIGHTS PER WAVE, and their tier. Difficulty is flap eagerness and top
	' speed -- never making them flee, which reads as broken AI rather than as
	' an easier game (CLAUDE.md 3A).
	' THREE ON WAVE 1 AND RISING. The arcade gets hectic fast, and a wave that
	' opens with two knights drifting about reads as a screensaver.
	' FOUR ON WAVE ONE. Three left the screen feeling empty -- with pads gating
	' the spawns, a low count reads as the game waiting rather than starting.
	nwk = 3 + wave
	IF nwk > NKN THEN nwk = NKN
	kpend = nwk			' still to materialise this wave
	spwt = 40			' frames until the next one may appear
	FOR nwi = 0 TO NPAD - 1
		padu(nwi) = 0
	NEXT nwi
	FOR nwi = 0 TO NKN - 1
		kon(nwi) = 0
		IF nwi < 0 THEN
			kon(nwi) = 1
			ktier(nwi) = 0
			IF wave > 2 THEN ktier(nwi) = nwi AND 1
			IF wave > 5 THEN ktier(nwi) = 1 + (nwi AND 1)
			kfrm(nwi) = 0
			kflp(nwi) = 10 + nwi * 7
			kfa(nwi) = 0
			kwan(nwi) = nwi * 11	' stagger the first wander roll
			ktx(nwi) = 128
			kty(nwi) = 60
			' spread the spawns across the two upper platforms
			#kx(nwi) = 4096
			IF nwi > 2 THEN #kx(nwi) = 40960
			#kx(nwi) = #kx(nwi) + nwi * 3072
			#ky(nwi) = 8192
			#kvx(nwi) = 32768
			#kvy(nwi) = 32768
			kface(nwi) = 0
		END IF
	NEXT nwi

	FOR nwi = 0 TO NEGG - 1
		est(nwi) = 0
	NEXT nwi
	GOSUB prt_hud
	RETURN

	' --------------------------------------------------------- spawn player
spawn_player:
	' THE PLAYER MATERIALISES ON A PAD as well -- pad 0, on the base, which is
	' also why pad 0 is the one knights most often find blocked.
	#px = padx(0)
	#px = #px * 256
	#py = pady(0)
	#py = #py * 256
	#vx = 32768
	#vy = 32768
	pfrm = 0
	pface = 0
	pgnd = 0
	pdead = 0
	binv = 90			' brief spawn invulnerability, in frames
	' HOLD PAD 0 WHILE MATERIALISING. The player occupies a pad exactly as a
	' knight does, so nothing can arrive on top of him during the one moment he
	' cannot defend himself.
	padu(0) = 1
	RETURN

	' ------------------------------------------------------------ draw field
draw_field:
	CLS
	FOR dfi = 0 TO NPLAT - 1
		IF plon(dfi) = 1 THEN
		dfr = ply(dfi) / 8		' surface pixel row -> character row
		dfc = #plx1(dfi) / 8
		dfd = #plx2(dfi) / 8
		#dfa = dfr
		#dfa = #dfa * 32
		#dfa = #dfa + dfc
		GOSUB draw_plat
		END IF
	NEXT dfi

	FOR dfi = 0 TO NPAD - 1
		dfr = pady(dfi) + 16		' the surface the pad sits on
		dfr = dfr / 8
		dfc = padx(dfi) / 8
		#dfa = dfr
		#dfa = #dfa * 32
		#dfa = #dfa + dfc
		#dfa = #dfa + 6144
		VPOKE #dfa,PADCH
		#dfa = #dfa + 1
		VPOKE #dfa,PADCH
	NEXT dfi

	' The lava fills everything below the floor line.
	' ROWS 22-23 ONLY, below the base. It used to start at row 20 -- the base's own
	' row -- and paint over it, so the floor you were standing on was drawn as
	' lava. Collision read the island table and was right; only the picture lied.
	FOR dfi = 0 TO 31
		#dfa = 704 + dfi		' row 22, the lava surface
		#dfa = #dfa + 6144
		VPOKE #dfa,LAVAA
		#dfa = #dfa + 32
		VPOKE #dfa,133
	NEXT dfi
	RETURN

	' ONE PLATFORM. #dfa is the name-table offset of its left cap, dfc..dfd the
	' column span. VPOKE takes a RAW VRAM address and the name table starts at
	' 6144, added as its OWN step -- folded into a constant expression it would
	' truncate (CLAUDE.md 3A).
draw_plat:
	#dpa = #dfa
	#dpa = #dpa + 6144
	VPOKE #dpa,PLATL
	FOR dpi = dfc + 1 TO dfd - 1
		#dpa = #dpa + 1
		VPOKE #dpa,PLATM
	NEXT dpi
	#dpa = #dpa + 1
	VPOKE #dpa,PLATR
	RETURN

	' ---------------------------------------------------------------- HUD
prt_hud:
	PRINT AT 0,"SCORE"
	GOSUB prt_score
	GOSUB prt_lives
	RETURN

	' Six digits, printed from #score which counts TENS, so a zero is appended.
prt_score:
	#psv = #score
	#psd = 10000
	psc = 6
	#psa = 6144 + 6
prt_sloop:
	IF psc = 1 THEN
		psn = 0			' the appended tens digit
	ELSE
		psn = 0
		WHILE #psv >= #psd
			#psv = #psv - #psd
			psn = psn + 1
		WEND
		#psd = #psd / 10
	END IF
	psv2 = 48 + psn
	VPOKE #psa,psv2
	#psa = #psa + 1
	psc = psc - 1
	IF psc > 0 THEN GOTO prt_sloop
	RETURN

	' SPARES, NOT TOTAL. A fresh 3-life game shows TWO icons and the last life
	' shows none (CLAUDE.md 7A). lives is unsigned 8-bit, so the decrement is
	' guarded -- a bare `lives - 1` at zero wraps to 255 and lights every icon
	' exactly when the player has none left.
prt_lives:
	plv = 0
	IF lives > 0 THEN plv = lives - 1
	FOR pli = 0 TO 3
		#pla = 6144 + 26
		#pla = #pla + pli
		plc = BLANK
		IF pli < plv THEN plc = LIFECH
		VPOKE #pla,plc
	NEXT pli
	RETURN

	' ============================================================ main loop
main:
	WAIT
	#wvt = #wvt + 1
	GOSUB lprate			' !! TEMPORARY -- see the note at lprate
	GOSUB p_input
	GOSUB p_move
	GOSUB k_spawn
	GOSUB k_move
	GOSUB rb_move
	GOSUB troll
	GOSUB ptero
	GOSUB e_move
	GOSUB collide
	GOSUB draw
	GOSUB sfx_tick

	' A wave ends only when nothing is left to fight AND nothing left to hatch.
	mnl = 0
	IF kpend > 0 THEN mnl = 1
	FOR mni = 0 TO NKN - 1
		IF kon(mni) > 0 THEN mnl = 1
	NEXT mni
	FOR mni = 0 TO NEGG - 1
		IF est(mni) > 0 THEN mnl = 1
	NEXT mni
	IF mnl = 0 THEN GOSUB new_wave

	IF pdead > 0 THEN GOSUB do_death
	IF pover = 1 THEN GOTO game_over
	GOTO main

	' --------------------------------------------------------------- input
p_input:
	IF binv > 0 THEN
		binv = binv - 1
		IF binv = 0 THEN padu(0) = 0	' materialised: release the pad
	END IF

	' FLAP IS EDGE TRIGGERED -- holding fire must not hover. The released state
	' has to be seen before the next flap counts.
	IF cont1.button THEN
		IF pflp = 0 THEN
			pflp = 1
			IF trst = 2 THEN tresc = tresc + 1
			' ADDITIVE, not a reset. Setting the velocity outright meant the
			' FIRST flap was the whole climb -- full power from a standing
			' start, and further presses added nothing while it decayed. Each
			' beat now adds to what you already have and the climb builds, so
			' a single tap is a nudge and holding a rhythm is what gains
			' height. Clamped so mashing cannot exceed a real climb rate.
			#vy = #vy - 400
			IF #vy < 32768 - 1100 THEN #vy = 32768 - 1100
			pfa = 10			' one press, one beat of the wings
			SOUND 0,700,12
			sf0 = 3
		END IF
	ELSE
		pflp = 0
	END IF

	' LEFT/RIGHT ONLY. Nothing here reads the vertical axis: on the TI it shares
	' a line with ALPHA LOCK and reports a direction that never releases.
	' Bounced off rock: the recoil owns the steering briefly. Flapping still works,
	' so you are never actually helpless -- just carried.
	pin = 0
	IF pbnc > 0 THEN
		pbnc = pbnc - 1
		RETURN
	END IF
	' In the troll's grip the steering does nothing. The flap above still counts --
	' it is the only thing that does, and each one banks toward tearing free.
	IF trst = 2 THEN RETURN
	IF cont1.left THEN
		pin = 1
		pface = 1
		IF #vx > 32768 - 1100 THEN #vx = #vx - ACCX
	END IF
	IF cont1.right THEN
		pin = 1
		pface = 0
		IF #vx < 32768 + 1100 THEN #vx = #vx + ACCX
	END IF
	IF pin = 0 THEN GOSUB p_fric
	RETURN

	' Decay toward the biased zero from whichever side we are on. Written as two
	' one-sided tests because a signed subtraction here would wrap.
p_fric:
	IF #vx > 32768 THEN
		#vx = #vx - FRIC
		IF #vx < 32768 THEN #vx = 32768
	ELSE
		IF #vx < 32768 THEN
			#vx = #vx + FRIC
			IF #vx > 32768 THEN #vx = 32768
		END IF
	END IF
	RETURN

	' ------------------------------------------------------ player movement
p_move:
	#vy = #vy + GRAV
	IF #vy > 32768 + 1180 THEN #vy = 32768 + 1180	' terminal fall speed

	' 16-bit wrap does the signed arithmetic for us: adding (v - 32768) is
	' correct whichever side of the bias v sits on.
	#py = #py + #vy
	#py = #py - 32768
	#px = #px + #vx
	#px = #px - 32768
	' x needs NO wrap handling: 256 pixels x 256 = 65536, so #px wraps by itself.

	py8 = #py / 256
	IF py8 < TOPY THEN
		#py = 2048
		' PUSHED BACK DOWN, not stopped. Parked against the ceiling a bird is
		' unreachable -- nothing can get above it, so it can neither kill nor
		' be killed, and the joust stops being a contest. A gentle downward
		' shove means the top of the screen is a place you pass through.
		#vy = 32768 + 220
	END IF

	GOSUB p_bump
	GOSUB p_land
	GOSUB p_side
	' Same correction for the player: it is the feet that touch the lava, not the
	' rider's head. Measured on the top, you had to be most of a body-length under
	' the surface before it counted.
	IF pdead = 0 THEN
		pfe = py8 + MH
		IF pfe >= LAVAY THEN
			IF pgnd = 0 THEN pdead = 1
		END IF
	END IF

	' Animation: frame follows vertical motion, not a timer.
	' A flap in progress owns the frame; otherwise the pose follows the motion.
	IF pfa > 0 THEN
		pfa = pfa - 1
		pfrm = 2			' wings DOWN, the power stroke
		IF pfa < 7 THEN pfrm = 1	' sweeping back up
		IF pfa < 4 THEN pfrm = 0	' wings UP, recovered
	ELSE
		IF pgnd = 1 THEN
			pfrm = 3
			IF pin = 0 THEN pfrm = 1
		ELSE
			pfrm = 1
			IF #vy < 32768 THEN pfrm = 0
		END IF
	END IF
	RETURN

	' Land on a platform when the FEET cross its surface while falling. Only
	' downward motion lands: rising through a platform is allowed, as in the
	' arcade.
p_land:
	pgnd = 0
	IF #vy < 32768 THEN RETURN
	plf = #py / 256
	plf = plf + MH			' feet
	plc2 = #px / 256
	plc2 = plc2 + 8			' centre x
	FOR pli2 = 0 TO NPLAT - 1
		plt = ply(pli2)			' ONE array read, then reject on it
		IF plf >= plt THEN
			IF plf <= plt + 8 THEN
			IF plon(pli2) = 1 THEN
				IF plc2 >= #plx1(pli2) THEN
					IF plc2 <= #plx2(pli2) THEN
						pgnd = 1
						#py = plt - MH
						#py = #py * 256
						#vy = 32768
					END IF
				END IF
			END IF
		END IF
		END IF
	NEXT pli2
	RETURN

	' PLATFORMS ARE SOLID FROM BELOW TOO. Rising through one was wrong -- in the
	' arcade an island is a wall in every direction, which is exactly why the
	' layout dictates the fight: you must fly AROUND, and a knight above you
	' cannot simply be escaped by rising through the floor he stands on.
	'
	' An island is 8 px thick (one character row), so its underside is ply + 8.
	' The head bumps when the sprite's top crosses that band while rising.
p_bump:
	IF #vy >= 32768 THEN RETURN		' only while rising
	pbh = #py / 256				' the head is the sprite's top edge
	pbb = pbh + MH - 1			' and this is the feet
	pbc = #px / 256
	pbc = pbc + 8				' centre x
	FOR pbi = 0 TO NPLAT - 1
		pbt = ply(pbi)
		' BODY overlap, not head-only: the head can clear an 8 px band in one
		' 4 px step while the body is still inside it, and head-only lets the
		' player slide up through solid rock.
		IF pbh <= pbt + 7 THEN
			IF pbb >= pbt THEN
			IF plon(pbi) = 1 THEN
				IF pbc >= #plx1(pbi) THEN
					IF pbc <= #plx2(pbi) THEN
						#py = pbt + 8
						#py = #py * 256
						' BOUNCED OFF, not stopped. Same rule as the
						' ceiling: parked under a ledge you are as
						' unreachable as parked on the roof, and the
						' joust stops being a contest. A shove
						' downward makes the underside a thing you
						' glance off rather than hang from.
						#vy = 32768 + 220
					END IF
				END IF
			END IF
		END IF
		END IF
	NEXT pbi
	RETURN

	' --------------------------------------------------------- materialising
	' A knight appears on a PAD, never in mid-air, and only when one is free and
	' the player is not standing on it. Camping the last free pad therefore stalls
	' the wave -- that is the arcade's behaviour and it is a tactic worth having.
k_spawn:
	IF kpend = 0 THEN RETURN
	IF spwt > 0 THEN
		spwt = spwt - 1
		RETURN
	END IF
	ksl = 255
	FOR ksi = 0 TO NKN - 1
		IF kon(ksi) = 0 THEN ksl = ksi
	NEXT ksi
	IF ksl = 255 THEN RETURN		' every slot busy; try again next frame
	ksp = 255
	kspx = #px / 256
	FOR ksi = 0 TO NPAD - 1
		IF padu(ksi) = 0 THEN
			ksd = kspx - padx(ksi)
			IF kspx < padx(ksi) THEN ksd = padx(ksi) - kspx
			IF ksd > 28 THEN ksp = ksi
		END IF
	NEXT ksi
	IF ksp = 255 THEN RETURN		' no free pad clear of the player: WAIT

	padu(ksp) = 1
	kon(ksl) = 2				' 2 = materialising, not yet solid
	kpad(ksl) = ksp
	kmat(ksl) = 44
	#kx(ksl) = padx(ksp)
	#kx(ksl) = #kx(ksl) * 256
	#ky(ksl) = pady(ksp)
	#ky(ksl) = #ky(ksl) * 256
	#kvx(ksl) = 32768
	#kvy(ksl) = 32768
	kface(ksl) = 0
	kfrm(ksl) = 1
	kflp(ksl) = 8
	kfa(ksl) = 0
	kwan(ksl) = 0
	ktx(ksl) = 128
	kty(ksl) = 60
	ktier(ksl) = 0
	IF wave > 3 THEN ktier(ksl) = kpend AND 1
	IF wave > 15 THEN ktier(ksl) = 2
	kpend = kpend - 1
	spwt = 26
	SOUND 2,600,10
	sf2 = 4
	RETURN

	' A KNIGHT ON FOOT. He falls to the nearest surface and walks, and he is
	' HELPLESS -- worth running down before his ride arrives.
k_foot:
	#kvy(kni) = #kvy(kni) + GRAV
	IF #kvy(kni) > 33768 THEN #kvy(kni) = 33768
	#ky(kni) = #ky(kni) + #kvy(kni)
	#ky(kni) = #ky(kni) - 32768
	kmy = #ky(kni) / 256
	kmx = #kx(kni) / 256
	IF #kvy(kni) >= 32768 THEN
		kf = kmy + MH
		FOR knj = 0 TO NPLAT - 1
			kpt = ply(knj)
			IF kf >= kpt THEN
				IF kf <= kpt + 8 THEN
				IF plon(knj) = 1 THEN
					kc = kmx + 8
					IF kc >= #plx1(knj) THEN
						IF kc <= #plx2(knj) THEN
							#ky(kni) = kpt - MH
							#ky(kni) = #ky(kni) * 256
							#kvy(kni) = 32768
							' HE STANDS STILL, lance up, waiting for his
							' ride. A knight jogging along a ledge reads
							' as an enemy doing something; standing still
							' reads as one waiting to be dealt with,
							' which is exactly what he is.
						END IF
					END IF
				END IF
				END IF
			END IF
		NEXT knj
	END IF
	IF kmy > LAVAY THEN kon(kni) = KDEAD	' he fell in; no rescue
	kfrm(kni) = 0
	RETURN

	' THE RIDERLESS BUZZARD. Flies in from the nearer screen edge, straight at the
	' man on foot, collects him, and the pair go back on the attack.
rb_move:
	IF rbon = 0 THEN GOSUB rb_launch
	IF rbon = 0 THEN RETURN
	' HIS MAN IS GONE -- collected, or fell in the lava. The bird does not vanish
	' mid-air: it carries on across the screen and leaves. It cannot kill, cannot
	' be killed, and does not wrap -- it simply exits and is done.
	IF kon(rbt) <> KFOOT THEN
		IF rbon = 1 THEN rbon = 2
	END IF
	IF rbon = 2 THEN GOSUB rb_flyby
	IF rbon <> 1 THEN RETURN
	rgx = #kx(rbt) / 256
	rgy = #ky(rbt) / 256
	IF rbx < rgx THEN
		rbx = rbx + 3
		rbf = 0
	ELSE
		rbx = rbx - 3
		rbf = 1
	END IF
	IF rby < rgy THEN rby = rby + 2
	IF rby > rgy THEN rby = rby - 2
	GOSUB rb_clear
	rdx = rbx - rgx
	IF rbx < rgx THEN rdx = rgx - rbx
	rdy = rby - rgy
	IF rby < rgy THEN rdy = rgy - rby
	IF rdx < 7 THEN
		IF rdy < 7 THEN
			' MOUNTED. He is dangerous again, and moving.
			kon(rbt) = KLIVE
			#kvx(rbt) = 32768
			#kvy(rbt) = 32768 - 400
			kflp(rbt) = 6
			kwan(rbt) = 0
			rbon = 0
			SOUND 1,420,11
			sf1 = 4
		END IF
	END IF
	RETURN

	' Flying off. Straight on in the direction it was already going, no wrap: once
	' it is past the edge it is gone.
rb_flyby:
	IF rbf = 0 THEN
		IF rbx > 248 THEN
			rbon = 0
			RETURN
		END IF
		rbx = rbx + 3
	ELSE
		IF rbx < 6 THEN
			rbon = 0
			RETURN
		END IF
		rbx = rbx - 3
	END IF
	GOSUB rb_clear
	RETURN

	' THE BIRD DOES NOT FLY THROUGH ROCK. If its box has ended up inside an
	' island it climbs until it is clear, which reads as hopping the obstacle.
rb_clear:
	rbz = 0
	FOR rbj = 0 TO NPLAT - 1
		rpt = ply(rbj)
		IF rby + 15 >= rpt THEN
			IF rby <= rpt + 7 THEN
			IF plon(rbj) = 1 THEN
				rbc = rbx + 8
				IF rbc >= #plx1(rbj) THEN
					IF rbc <= #plx2(rbj) THEN
						rbz = 1
					END IF
				END IF
			END IF
			END IF
		END IF
	NEXT rbj
	IF rbz = 1 THEN
		IF rby > 10 THEN rby = rby - 3
	END IF
	RETURN

	' Find a man with no bird on the way, and send one from the nearer edge.
rb_launch:
	FOR rbi = 0 TO NKN - 1
		IF rbon = 0 THEN
			IF kon(rbi) = KFOOT THEN
				rbt = rbi
				rbon = 1
				rgx = #kx(rbi) / 256
				rbx = 0
				IF rgx > 128 THEN rbx = 255
				' COME IN ON HIS LAYER. Launching from a fixed altitude
				' meant the bird had to descend through whatever was in
				' the way and would hang up on a ledge; entering level
				' with him turns the trip into a straight run.
				rby = #ky(rbi) / 256
				rbf = 0
			END IF
		END IF
	NEXT rbi
	RETURN

	' NO ENTERING AN ISLAND FROM THE SIDE.
	'
	' p_land catches feet coming down and p_bump catches the head coming up, but
	' NEITHER fires on something arriving horizontally: fly level into the end of a
	' ledge and you slid straight into the rock, because the only x test was
	' whether the CENTRE had reached the span -- by which time half the bird was
	' already inside it.
	'
	' This runs AFTER both, so a landing or a bump has already snapped y clear of
	' the band and cannot be undone here. What is left is the genuinely embedded
	' case, and it is pushed back out the way it came.
p_side:
	psh = #py / 256
	psb = psh + MH - 1
	psl = #px / 256
	psr = psl + MH - 1
	FOR psi = 0 TO NPLAT - 1
		pst = ply(psi)
		IF psb >= pst THEN
			IF psh <= pst + 7 THEN
			IF plon(psi) = 1 THEN
				IF psr >= #plx1(psi) THEN
					IF psl <= #plx2(psi) THEN
						' embedded: leave by the nearer face
						#psc = psl
						#psc = #psc + 8
						#psm = #plx1(psi)
						#psm = #psm + #plx2(psi)
						#psm = #psm / 2
						IF #psc < #psm THEN
							#psx = #plx1(psi)
							IF #psx > 16 THEN
								#px = #psx - 16
								#px = #px * 256
							END IF
						ELSE
							#psx = #plx2(psi)
							IF #psx < 254 THEN
								#px = #psx + 1
								#px = #px * 256
							END IF
						END IF
						' BOUNCE, exactly like glancing off a
						' knight. Stopping dead against rock is
						' unreadable -- you cannot tell whether you
						' hit something or the controls dropped an
						' input. Reversing the momentum and taking
						' the steering away for a moment MAKES the
						' collision an event you can feel.
						#vx = 65536 - #vx
						pbnc = 12
						SOUND 1,620,10
						sf1 = 3
					END IF
				END IF
			END IF
			END IF
		END IF
	NEXT psi
	RETURN

	' ----------------------------------------------------- knight movement
	' THINKING IS HALVED. Target choice, separation and routing are DECISIONS: they
	' write ktx/kty, which persist between frames. Running them for every knight
	' every frame is redundant, so half the knights decide on even frames and half
	' on odd. Movement stays per-frame and perfectly smooth; a knight simply
	' re-aims 30 times a second instead of 60, which is not a difference anybody
	' can see -- and it halves the most expensive part of the loop.
k_move:
	kthf = FRAME
	kthf = kthf AND 1
	FOR kni = 0 TO NKN - 1
		IF kon(kni) > 0 THEN GOSUB k_one
	NEXT kni
	RETURN

k_one:
	IF kon(kni) = KFOOT THEN GOSUB k_foot
	IF kon(kni) = KFOOT THEN RETURN
	IF kon(kni) = 2 THEN
		kmat(kni) = kmat(kni) - 1
		IF kmat(kni) = 0 THEN
			kon(kni) = 1
			padu(kpad(kni)) = 0	' the pad is free again
		END IF
		RETURN
	END IF
	kpx = #px / 256
	kpy = #py / 256
	kmx = #kx(kni) / 256
	kmy = #ky(kni) / 256
	' !! 16-BIT, AND MULTIPLIED VIA A SEPARATE VARIABLE. As a plain `ktop` the 400
	' truncated to 144, so the tiers came out 144 / 234 / 324-and-wrapped-to-68 --
	' THE SHADOW LORD WOULD HAVE BEEN THE SLOWEST ENEMY IN THE GAME, the exact
	' inversion that shipped in RALLY-X. tools/bigvar.py caught it before the build.
	' The multiply reads #ktp2, not #ktop: on the 9900 MPY leaves the high word in
	' r0 and reading back the variable just multiplied returns 0 (CLAUDE.md 3A).
	#ktp2 = ktier(kni)
	#ktop = #ktp2 * 140
	#ktop = #ktop + 860
	#kagg = agg
	#kagg = #kagg * 9
	#ktop = #ktop + #kagg	' faster every wave, on top of the tier
	#kfast = 32768 + #ktop
	#kslow = 32768 - #ktop

	' THE THREE TIERS FLY DIFFERENTLY. This is the whole character of the game and
	' it is not one homing rule with the speed turned up:
	'
	'   Bounder     wanders the arena, only OCCASIONALLY reacting to the player.
	'   Hunter      seeks the player, trying to collide.
	'   Shadow Lord fast, hugs the top of the screen, and deliberately flies
	'               HIGHER as it closes -- because altitude is what decides the
	'               joust, so climbing IS its attack.
	'
	' Each knight steers toward a TARGET (ktx, kty) rather than at the player
	' directly. Only the choice of target differs per tier, so the flight code
	' below is shared and stays O(1).
	kth = kni AND 1
	IF kth = kthf THEN
		IF ktier(kni) = 0 THEN GOSUB k_wander
		IF ktier(kni) = 1 THEN GOSUB k_hunt
		IF ktier(kni) = 2 THEN GOSUB k_lord
	END IF
	IF kth = kthf THEN

	' SEPARATION -- they avoid each other on the way in. Without it every knight
	' flies the same line to the same point, they stack into a single silhouette,
	' and what should be four attackers reads as one fat one that you can beat with
	' a single well-timed climb. Nudging targets apart makes them arrive from
	' different angles and at different moments, which is what makes the attack
	' feel deliberate rather than herd-like.
	'
	' The push is applied to the TARGET, not the velocity: steering away is subtle
	' and keeps the attack going, whereas shoving the velocity looks like a
	' collision they are not supposed to have (knights pass through each other).
	' Only against knights LATER in the list. Each pair still gets checked once a
	' frame -- checking both ways round doubled the cost to reach the same answer.
	FOR ksj = kni + 1 TO NKN - 1
		IF ksj <> kni THEN
			IF kon(ksj) = KLIVE THEN
				ksox = #kx(ksj) / 256
				ksdx = kmx - ksox
				IF kmx < ksox THEN ksdx = ksox - kmx
				IF ksdx < 24 THEN
					ksoy = #ky(ksj) / 256
					ksdy = kmy - ksoy
					IF kmy < ksoy THEN ksdy = ksoy - kmy
					IF ksdy < 20 THEN
						' OVERLAPPING -- shove them apart in POSITION, not
						' just in intent. Steering alone cannot stop two
						' knights sharing a square: a hatched man collected
						' where another knight already is starts inside him,
						' and no amount of target-nudging separates two
						' bodies that are already coincident.
						IF ksdx < 10 THEN
							IF ksdy < 10 THEN
								IF kmx < ksox THEN
									#kx(kni) = #kx(kni) - 256
								ELSE
									#kx(kni) = #kx(kni) + 256
								END IF
							END IF
						END IF
						' and aim to pass on the far side of him,
						' off his altitude so the lances differ
						IF kmx < ksox THEN
							IF ktx(kni) > 28 THEN ktx(kni) = ktx(kni) - 28
						ELSE
							IF ktx(kni) < 227 THEN ktx(kni) = ktx(kni) + 28
						END IF
						IF kmy < ksoy THEN
							IF kty(kni) > 10 THEN kty(kni) = kty(kni) - 10
						ELSE
							IF kty(kni) < 140 THEN kty(kni) = kty(kni) + 10
						END IF
					END IF
				END IF
			END IF
		END IF
	NEXT ksj
	END IF

	' ROUTE AROUND ROCK.
	'
	' Steering straight at the player is useless when an island is in the way. A
	' knight above one has no way to descend through it, so it hovers over the
	' obstacle, drifts, flaps, and circles -- which is exactly what "the enemy
	' cannot find him and just keeps going over and around" looks like from the
	' outside. The player standing on the bottom-middle platform was unreachable.
	'
	' The fix is not a search. If an island lies BETWEEN my altitude and my
	' target's, and my x is over it, I aim at the nearer END of that island
	' instead. One pass, no state, and it composes with everything else because it
	' only rewrites the target.

	' Climb toward the target altitude. Flapping is on a cooldown, which is what
	' makes a tier feel eager or lazy without changing the rule.
	IF kflp(kni) > 0 THEN
		kflp(kni) = kflp(kni) - 1
	ELSE
		IF kmy > kty(kni) THEN
			kfa(kni) = 10		' they beat their wings too
			' 820, NOT 420. A knight flaps once per cooldown while gravity
			' collects 44 every frame in between: at the Bounder's 14-frame
			' cooldown that is 616 of sink against 420 of lift, so EVERY
			' TIER SANK. They drifted to the floor and stayed there -- the
			' "enemies get stuck at the bottom" report. They were trying and
			' losing to arithmetic. A player never hit this because a player
			' can tap every frame; a knight cannot.
			#kvy(kni) = #kvy(kni) - 820
			IF #kvy(kni) < 32768 - 1150 THEN #kvy(kni) = 32768 - 1150
			' EAGERER EVERY WAVE TOO, floored so it stays a flap and not
			' a hover. Same strategy per tier, sharper execution.
			kfc = 14 - ktier(kni) * 4
			kfw = agg / 4
			IF kfc > kfw THEN
				kfc = kfc - kfw
			ELSE
				kfc = 3
			END IF
			IF kfc < 3 THEN kfc = 3
			kflp(kni) = kfc
		END IF
	END IF

	' Steer toward the target x THE SHORTER WAY ROUND THE WRAP -- chasing across
	' the middle when the edge is nearer is the tell of an AI that does not know
	' the screen wraps.
	IF ktx(kni) > kmx THEN
		kdd = ktx(kni) - kmx
		IF kdd < 128 THEN GOSUB k_right ELSE GOSUB k_left
	ELSE
		kdd = kmx - ktx(kni)
		IF kdd < 128 THEN GOSUB k_left ELSE GOSUB k_right
	END IF

	#kvy(kni) = #kvy(kni) + GRAV
	IF #kvy(kni) > 33468 THEN #kvy(kni) = 33468

	#ky(kni) = #ky(kni) + #kvy(kni)
	#ky(kni) = #ky(kni) - 32768
	#kx(kni) = #kx(kni) + #kvx(kni)
	#kx(kni) = #kx(kni) - 32768

	kmy = #ky(kni) / 256
	IF kmy < TOPY THEN
		#ky(kni) = 2048
		#kvy(kni) = 32768 + 220	' knights are pushed off the ceiling too
	END IF

	' Knights obey the same solid islands the player does -- an enemy that can
	' rise through a platform the player cannot is the kind of asymmetry that
	' reads as cheating.

	' Land, and never sink into the lava: a knight that reaches the floor line
	' over the gap simply flaps back out.
	' ================= ONE PASS OVER THE ISLANDS =================
	' This used to be THREE separate loops over all ten islands -- routing,
	' head-bump and landing -- run for every knight, every frame. At six knights
	' that is 180 iterations a frame of nothing but array reads, and it is why the
	' game bogged down as the screen filled.
	'
	' All three ask the same first question ("is my centre over this island?"), so
	' they are now one loop that asks it once: 60 iterations instead of 180. The
	' behaviour is unchanged; only the number of times ply() is fetched is not.
	kf = kmy + MH			' feet
	kc = kmx + 8			' centre x
	krt = 0
	IF kth = kthf THEN
		IF kty(kni) > kmy + 12 THEN krt = 1
	END IF
	IF krt = 2 THEN krt = 1	' target below: routing may apply
	FOR knj = 0 TO NPLAT - 1
		kpt = ply(knj)
		' Y-GATE, on the one value already fetched. Nine islands in ten fail
		' here and cost nothing further.
		kok = 0
		IF kf >= kpt THEN
			IF kf <= kpt + 8 THEN kok = 1		' feet in the band
		END IF
		IF kmy <= kpt + 7 THEN
			IF kmy >= kpt THEN kok = 1		' head in the band, ANY direction
		END IF
		IF krt = 1 THEN
			IF kpt > kmy + 8 THEN
				IF kpt <= kty(kni) + 8 THEN kok = 1
			END IF
		END IF
		IF kok = 1 THEN
		IF plon(knj) = 1 THEN
			IF kc >= #plx1(knj) THEN
				IF kc <= #plx2(knj) THEN
					IF #kvy(kni) >= 32768 THEN
						' falling: land on the surface
						IF kf >= kpt THEN
							IF kf <= kpt + 8 THEN
								#ky(kni) = kpt - MH
								#ky(kni) = #ky(kni) * 256
								#kvy(kni) = 32768
							END IF
						END IF
					END IF
					' HEAD INSIDE THE ROCK -- pushed out downward whatever the
					' knight was doing. Gating this on "rising" left one that
					' had been shoved sideways into a ledge, or nudged there by
					' the separation push, with its head embedded and no rule
					' able to get it out again.
					IF kmy >= kpt THEN
						IF kmy <= kpt + 7 THEN
							#ky(kni) = kpt + 8
							#ky(kni) = #ky(kni) * 256
							#kvy(kni) = 32768 + 220
						END IF
					END IF
					' and route around it if it is between me and my target
					IF krt = 1 THEN
						IF kpt > kmy + 8 THEN
							IF kpt <= kty(kni) + 8 THEN
								#kbl = kc
								#kbl = #kbl - #plx1(knj)
								#kbr = #plx2(knj)
								#kbr = #kbr - kc
								IF #kbl < #kbr THEN
									#kbx = #plx1(knj)
									IF #kbx > 22 THEN
										ktx(kni) = #kbx - 22
									ELSE
										ktx(kni) = 0
									END IF
								ELSE
									#kbx = #plx2(knj)
									IF #kbx < 233 THEN
										ktx(kni) = #kbx + 22
									ELSE
										ktx(kni) = 255
									END IF
								END IF
							END IF
						END IF
					END IF
				END IF
			END IF
		END IF
		END IF
	NEXT knj
	IF #kvy(kni) >= 32768 THEN
		' NOTHING FLIES BELOW THE GROUND -- AND THE LINE IS THE FEET.
		'
		' The clamp was already here and still let knights swim through the
		' lava, because it compared and set the sprite's TOP. Pinning the top
		' to the lava line puts the whole 16 px body BELOW it: feet at 192,
		' the bottom of the screen, entirely inside the lava rows. The clamp
		' was working perfectly and holding them in exactly the place it was
		' supposed to keep them out of.
		'
		' It is the FEET that must not pass the line, so the top clamps to
		' LAVAY - MH and the test measures feet too.
		kfe = kmy + MH
		IF kfe > LAVAY THEN
			#ky(kni) = LAVAY - MH
			#ky(kni) = #ky(kni) * 256
			#kvy(kni) = 32768 - 620
		END IF
	END IF

	IF kfa(kni) > 0 THEN
		kfa(kni) = kfa(kni) - 1
		kfrm(kni) = 2
		IF kfa(kni) < 7 THEN kfrm(kni) = 1
		IF kfa(kni) < 4 THEN kfrm(kni) = 0
	ELSE
		kfrm(kni) = 1
		IF #kvy(kni) < 32768 THEN kfrm(kni) = 0
	END IF
	RETURN

	' BOUNDER -- wanders. A fresh destination every second or two, and only one
	' roll in four is the player, so it reads as a creature going about its
	' business that sometimes notices you. Never a patrol: pacing a platform
	' back and forth is what makes an enemy look like furniture.
k_wander:
	IF kwan(kni) > 0 THEN
		kwan(kni) = kwan(kni) - 1
		RETURN
	END IF
	kwan(kni) = 22 + RANDOM(30)	' re-target often -- a Bounder that commits
					' to one heading for two seconds looks asleep
	' HALF ITS ROLLS ARE THE PLAYER NOW, not a quarter. A Bounder that wanders
	' three times out of four is scenery: it has to threaten often enough that you
	' cannot ignore it while dealing with something else.
	' ... and it hunts more often the deeper you are: by the late waves a Bounder
	' is barely wandering at all, which is the difficulty curve doing its work
	' without changing what a Bounder IS.
	krn = 2
	IF agg > 6 THEN krn = 3
	kr = RANDOM(krn)
	IF kr > 0 THEN kr = 1
	IF agg > 10 THEN kr = 0
	IF kr = 0 THEN
		ktx(kni) = kpx
		kty(kni) = kpy - 4
		IF kpy < 4 THEN kty(kni) = 0
	ELSE
		ktx(kni) = RANDOM(255)
		kty(kni) = 24 + RANDOM(112)
	END IF
	RETURN

	' HUNTER -- seeks. Aims at the player, and one notch above him: level flight
	' into a joust is a coin toss, so it wants the high side of the contact.
k_hunt:
	ktx(kni) = kpx
	kty(kni) = kpy - 4
	IF kpy < 4 THEN kty(kni) = 0
	RETURN

	' SHADOW LORD -- fast, high, and higher still as it closes. It lives in the
	' top third and CLIMBS when near, because altitude decides the joust: the
	' climb is the attack, not a retreat from it.
k_lord:
	ktx(kni) = kpx
	kty(kni) = kpy - 12
	IF kpy < 12 THEN kty(kni) = 0
	klx = kpx - kmx
	IF kmx > kpx THEN klx = kmx - kpx
	IF klx < 48 THEN
		kty(kni) = kpy - 30
		IF kpy < 30 THEN kty(kni) = 0
	END IF
	IF kty(kni) > 96 THEN kty(kni) = 96	' it belongs near the ceiling
	RETURN

k_right:
	kface(kni) = 0
	IF #kvx(kni) < #kfast THEN #kvx(kni) = #kvx(kni) + 36
	RETURN

k_left:
	kface(kni) = 1
	IF #kvx(kni) > #kslow THEN #kvx(kni) = #kvx(kni) - 36
	RETURN

	' --------------------------------------------------------- egg movement
e_move:
	FOR egi = 0 TO NEGG - 1
		IF est(egi) > 0 THEN GOSUB e_one
	NEXT egi
	RETURN

e_one:
	IF est(egi) = 1 THEN
		IF #etm(egi) > 0 THEN #etm(egi) = #etm(egi) - 1
		#evy(egi) = #evy(egi) + GRAV
		IF #evy(egi) > 33468 THEN #evy(egi) = 33468
		#ey(egi) = #ey(egi) + #evy(egi)
		#ey(egi) = #ey(egi) - 32768
		#ex(egi) = #ex(egi) + #evx(egi)
		#ex(egi) = #ex(egi) - 32768
		egy = #ey(egi) / 256
		egx = #ex(egi) / 256
		egf = egy + 16
		FOR egj = 0 TO NPLAT - 1
			ept = ply(egj)
			IF egf >= ept THEN
				IF egf <= ept + 8 THEN
				IF plon(egj) = 1 THEN	' y-gated above: 1 read to reject
					egc = egx + 8
					IF egc >= #plx1(egj) THEN
						IF egc <= #plx2(egj) THEN
							#ey(egi) = ept - 16
							#ey(egi) = #ey(egi) * 256
							est(egi) = 2
							#etm(egi) = 240	' now the REST timer
							' KEEP THE SIDEWAYS MOMENTUM. An egg that
							' stops dead the instant it touches rock
							' looks glued on; it should skid and
							' settle. e_rest below bleeds it off.
						END IF
					END IF
				END IF
			END IF
			END IF
		NEXT egj
		' An egg that falls into the gap is simply gone.
		IF egy > LAVAY THEN est(egi) = 0
		RETURN
	END IF

	' Resting: still sliding, bleeding off speed, and possibly skidding clean off
	' the edge of the island it landed on.
	IF est(egi) = 2 THEN GOSUB e_rest
	' Resting, then cracking, then a fresh knight one tier higher.
	IF #etm(egi) > 0 THEN
		#etm(egi) = #etm(egi) - 1
		IF #etm(egi) = 90 THEN
			est(egi) = 3
			SOUND 2,300,10
			sf2 = 6
		END IF
		RETURN
	END IF
	GOSUB e_hatch
	RETURN

	' FRICTION ON THE GROUND. The egg slides, slows, and stops -- and if it slides
	' off the end of its island it falls again, which is the arcade's behaviour and
	' makes a ledge a bad place to leave one.
e_rest:
	IF #evx(egi) > 32768 THEN
		#evx(egi) = #evx(egi) - 14
		IF #evx(egi) < 32768 THEN #evx(egi) = 32768
	ELSE
		IF #evx(egi) < 32768 THEN
			#evx(egi) = #evx(egi) + 14
			IF #evx(egi) > 32768 THEN #evx(egi) = 32768
		END IF
	END IF
	IF #evx(egi) = 32768 THEN RETURN	' come to rest
	#ex(egi) = #ex(egi) + #evx(egi)
	#ex(egi) = #ex(egi) - 32768
	' still supported?
	egx = #ex(egi) / 256
	egy = #ey(egi) / 256
	egc = egx + 8
	egf = egy + 16
	ergs = 0
	FOR egj = 0 TO NPLAT - 1
		ept = ply(egj)
		IF egf >= ept THEN
			IF egf <= ept + 8 THEN
			IF plon(egj) = 1 THEN	' y-gated above: 1 read to reject
				IF egc >= #plx1(egj) THEN
					IF egc <= #plx2(egj) THEN
						ergs = 1
					END IF
				END IF
			END IF
			END IF
		END IF
	NEXT egj
	IF ergs = 0 THEN
		est(egi) = 1			' skidded off: falling again
		#evy(egi) = 32768
	END IF
	RETURN

	' Hatch into the first free knight slot, one tier up. If every slot is busy
	' the egg simply waits and tries again next frame.
e_hatch:
	ehd = 0				' done? -- set instead of returning early
	FOR ehj = 0 TO NKN - 1
		IF ehd = 0 THEN
		IF kon(ehj) = 0 THEN
			' ON FOOT, not mounted. The bird comes for him separately.
			kon(ehj) = KFOOT
			' THE TIER CYCLES: Bounder -> Hunter -> Shadow Lord -> Bounder.
			' It does NOT cap at Shadow Lord -- capping would let a late wave
			' settle into a stable top tier, and the arcade deliberately keeps
			' turning the wheel so an ignored egg is always an escalation.
			ktier(ehj) = etier(egi) + 1
			IF ktier(ehj) > 2 THEN ktier(ehj) = 0
			#kx(ehj) = #ex(egi)
			#ky(ehj) = #ey(egi)
			#kvx(ehj) = 32768
			#kvy(ehj) = 32768
			kflp(ehj) = 20
			kface(ehj) = 0
			est(egi) = 0
			ehd = 1
		END IF
		END IF
	NEXT ehj
	' No free slot: wait and try again shortly rather than losing the hatch.
	IF ehd = 0 THEN #etm(egi) = 30
	RETURN

	' ----------------------------------------------------------- collisions
collide:
	IF pdead > 0 THEN RETURN
	cpx = #px / 256
	cpy = #py / 256

	FOR cni = 0 TO NKN - 1
		IF kon(cni) = 1 THEN GOSUB c_knight
		IF kon(cni) = KFOOT THEN GOSUB c_foot
	NEXT cni

	FOR cni = 0 TO NEGG - 1
		IF est(cni) > 0 THEN GOSUB c_egg
	NEXT cni
	RETURN

	' Boxes overlap, then ALTITUDE decides. Written as nested single tests --
	' `a AND b` on comparisons is miscompiled by the 9900 backend.
c_knight:
	ckx = #kx(cni) / 256
	cky = #ky(cni) / 256
	cdx = cpx - ckx
	IF cpx < ckx THEN cdx = ckx - cpx
	' TIGHTER THAN IT WAS. At 11 px a "collision" started while the birds were
	' still visibly apart, and the resulting duel felt unearned.
	IF cdx > 9 THEN RETURN
	cdy = cpy - cky
	IF cpy < cky THEN cdy = cky - cpy
	IF cdy > 9 THEN RETURN

	' AND THE TIE WINDOW IS ONE PIXEL, not four. A bounce means the lances met
	' dead level -- it should be the rare, surprising outcome, not the usual one.
	' At +/-3 px it was seven pixels wide out of a nine-pixel box, so MOST
	' contacts ended in a bounce and the altitude rule barely decided anything.
	IF cpy + 2 <= cky THEN
		' the player's lance is higher: unhorse the knight
		GOSUB k_unhorse
		RETURN
	END IF
	IF cky + 2 <= cpy THEN
		IF binv = 0 THEN pdead = 1
		RETURN
	END IF
	' level lances: both bounce, nobody dies
	#kvx(cni) = 65536 - #kvx(cni)
	#vx = 65536 - #vx
	SOUND 1,500,11
	sf1 = 4
	RETURN

k_unhorse:
	kon(cni) = 0
	kus = 50 + ktier(cni) * 25		' 500 / 750 / 1250, in tens
	#score = #score + kus
	SOUND 0,400,13
	sf0 = 5
	' Drop an egg carrying the knight's momentum.
	kud = 0				' egg placed? -- a flag, never an early RETURN
	FOR kuj = 0 TO NEGG - 1
		IF kud = 0 THEN
		IF est(kuj) = 0 THEN
			est(kuj) = 1
			#ex(kuj) = #kx(cni)
			#ey(kuj) = #ky(cni)
			#evx(kuj) = #kvx(cni)
			' POP UPWARD out of the joust, keeping the knight's sideways
			' momentum. An egg that simply drops from where he died is on
			' top of the player and reads as no egg at all.
			#evy(kuj) = 32768 - 520
			etier(kuj) = ktier(cni)
			' GRACE: about a quarter second (16 frames). Half a second sounded
			' right and was not -- a popped egg is often back on the rock
			' inside 30 frames, so the window where it was both AIRBORNE and
			' collectable could be nothing at all. It only has to last long
			' enough for the egg to leave the joust that produced it.
			' Without ANY grace the egg loop -- which runs later in this
			' very frame -- eats the egg where it was laid, since it is
			' created within collision range of the player by definition.
			' Half a second is long enough that the egg visibly leaves the
			' joust before it counts, and short enough that a deliberate
			' mid-air catch is still on.
			#etm(kuj) = 16
			kud = 1
		END IF
		END IF
	NEXT kuj
	GOSUB prt_score
	RETURN

	' RUNNING DOWN A MAN ON FOOT. He is helpless, and worth the same as the egg he
	' came out of -- the arcade lets you collect a hatched knight before his ride
	' arrives, and that window is the reward for watching the eggs.
c_foot:
	cfx = #kx(cni) / 256
	cfy = #ky(cni) / 256
	cdx = cpx - cfx
	IF cpx < cfx THEN cdx = cfx - cpx
	IF cdx > 11 THEN RETURN
	cdy = cpy - cfy
	IF cpy < cfy THEN cdy = cfy - cpy
	IF cdy > 11 THEN RETURN
	kon(cni) = KDEAD
	ecoll = ecoll + 1
	ceg = ecoll
	IF ceg > 4 THEN ceg = 4
	#score = #score + ceg * 25
	SOUND 1,250,13
	sf1 = 5
	GOSUB prt_score
	RETURN

	' 250, 500, 750, then 1000 -- in tens, and capped.
c_egg:
	' An egg still in its grace period has not left the joust yet.
	IF est(cni) = 1 THEN
		IF #etm(cni) > 0 THEN RETURN
	END IF
	' CENTRE TO CENTRE. The egg is 8x9 drawn in the LOWER part of its cell, so its
	' middle sits 11 px below its sprite origin while the bird's sits 8 below its
	' own. Comparing the origins measured a distance three pixels off, which near
	' the edge of the box is the difference between a catch and a miss -- and it
	' erred toward missing, which is exactly what "touched it and did not get it"
	' feels like.
	cex = #ex(cni) / 256
	cex = cex + 7			' art occupies columns 3-10, so the middle is +7
	cey = #ey(cni) / 256
	cey = cey + 11
	cpx2 = cpx + 8
	cpy2 = cpy + 8
	cdx = cpx2 - cex
	IF cpx2 < cex THEN cdx = cex - cpx2
	IF cdx > 10 THEN RETURN
	cdy = cpy2 - cey
	IF cpy2 < cey THEN cdy = cey - cpy2
	IF cdy > 10 THEN RETURN
	est(cni) = 0
	ecoll = ecoll + 1
	ceg = ecoll
	IF ceg > 4 THEN ceg = 4
	#score = #score + ceg * 25
	SOUND 1,250,13
	sf1 = 5
	GOSUB prt_score
	RETURN

	' ---------------------------------------------------------------- death
do_death:
	FOR ddi = 0 TO 30
		WAIT
		SOUND 0,200 + ddi * 20,13
		SPRITE 0,SPRHID,0,0,0
		GOSUB draw_knights
	NEXT ddi
	SOUND 0,800,0
	IF lives > 0 THEN lives = lives - 1
	GOSUB prt_lives
	' SET A FLAG AND RETURN. Leaving a GOSUB by GOTO never pops its return
	' address; on ColecoVision that walks the stack down into the variables after
	' a few dozen deaths (CLAUDE.md 3A). Main dispatches on pover instead.
	IF lives = 0 THEN
		pover = 1
		RETURN
	END IF
	GOSUB spawn_player
	pdead = 0
	RETURN

game_over:
	GOSUB hide_all
	PRINT AT 300,"GAME OVER"
	FOR ddi = 0 TO 120
		WAIT
	NEXT ddi
	GOTO title_screen

	' ----------------------------------------------------------- rendering
draw:
	' The player is sprite 0 on purpose: with flicker off the VDP drops the
	' HIGHEST-numbered sprites on a crowded scanline, so slot 0 can never be the
	' one that disappears.
	drp = pface * 16
	drp = drp + pfrm * 4
	dry = #py / 256
	drx = #px / 256
	drc = 11
	IF binv > 0 THEN
		drc = 1
		IF binv AND 4 THEN drc = 11
	END IF
	SPRITE 0,dry,drx,drp,drc
	GOSUB draw_knights
	GOSUB draw_eggs
	IF rbon = 1 THEN
		rbp = rbf * 16
		rbp = rbp + 4
		SPRITE 11,rby,rbx,rbp,7
	ELSE
		SPRITE 11,SPRHID,0,0,0
	END IF
	RETURN

draw_knights:
	FOR dki = 0 TO NKN - 1
		IF kon(dki) = 0 THEN
			SPRITE 1 + dki,SPRHID,0,0,0
		ELSE
			IF kon(dki) = KFOOT THEN
				dky = #ky(dki) / 256
				dkx = #kx(dki) / 256
				' THE MAN WEARS THE COLOUR HE WILL BECOME -- red, grey or
				' blue, the same lookup the mounted knights use below. He
				' already carries that tier (e_hatch set it when the egg
				' cracked), so the colour is free, and it is the only
				' warning you get of what is about to be flying at you:
				' a blue man on a ledge means a Shadow Lord in a moment.
				dkc = 8
				IF ktier(dki) = 1 THEN dkc = 14
				IF ktier(dki) = 2 THEN dkc = 5
				SPRITE 1 + dki,dky,dkx,36,dkc
			ELSE
			IF kon(dki) = 2 THEN
				' materialising: flash, and draw nothing on alternate
				' frames so it reads as arriving rather than lurking
				dkc = 0
				IF kmat(dki) AND 2 THEN dkc = 15
				dky = #ky(dki) / 256
				dkx = #kx(dki) / 256
				SPRITE 1 + dki,dky,dkx,4,dkc
			ELSE
			dkp = kface(dki) * 16
			dkp = dkp + kfrm(dki) * 4
			dky = #ky(dki) / 256
			dkx = #kx(dki) / 256
			dkc = 8
			IF ktier(dki) = 1 THEN dkc = 14
			IF ktier(dki) = 2 THEN dkc = 5
			SPRITE 1 + dki,dky,dkx,dkp,dkc
			END IF
			END IF
		END IF
	NEXT dki
	RETURN

draw_eggs:
	FOR dei = 0 TO NEGG - 1
		IF est(dei) = 0 THEN
			SPRITE 7 + dei,SPRHID,0,0,0
		ELSE
			dey = #ey(dei) / 256
			dex = #ex(dei) / 256
			dec = 15
			dep = 32
			' NOT YET COLLECTABLE -> drawn GREY rather than white. The grace
			' period was invisible, so an egg you touched and did not get
			' looked like a missed collision or a dropped input rather than a
			' rule. A rule the player cannot see is indistinguishable from a
			' bug, and this one costs a single colour to show.
			IF est(dei) = 1 THEN
				IF #etm(dei) > 0 THEN dec = 14
			END IF
			IF est(dei) = 3 THEN
				' CRACKED, and flashing. The pattern change is the real
				' warning; the flash only draws the eye to it.
				dep = 40
				IF #etm(dei) AND 4 THEN dec = 9
			END IF
			SPRITE 7 + dei,dey,dex,dep,dec
		END IF
	NEXT dei
	RETURN

hide_all:
	FOR hai = 0 TO 14
		SPRITE hai,SPRHID,0,0,0
	NEXT hai
	RETURN

	' --------------------------------------------------------------- the troll
	' A hand out of the lava, from wave 3. It reaches for a bird flying low over a
	' PIT -- the ground either side of the base, where the bridges burned away --
	' and once it has hold, only flapping gets you out. Reach and grip both grow
	' with the wave, which is what turns the pits from scenery into territory.
troll:
	IF wave < 3 THEN
		SPRITE 12,SPRHID,0,0,0
		SPRITE 14,SPRHID,0,0,0
		RETURN
	END IF
	trw = agg
	trr = 44 + trw * 4		' how high it can reach above the lava
	tpy = #py / 256
	tpx = #px / 256

	IF trst = 0 THEN
		' only over a pit, and only if you are low enough to be worth grabbing
		tover = 0
		IF tpx < 40 THEN tover = 1
		IF tpx > 207 THEN tover = 1
		IF tover = 1 THEN
			ttop = 184 - trr
			IF tpy > ttop THEN
				trst = 1
				trx = tpx
				trhy = 184
				SOUND 2,900,11
				sf2 = 6
			END IF
		END IF
		SPRITE 12,SPRHID,0,0,0
		SPRITE 14,SPRHID,0,0,0
		RETURN
	END IF

	IF trst = 1 THEN
		' rising. It tracks sideways slowly -- you can outrun it, but not by
		' much, and not while still climbing out of the pit.
		IF trhy > 184 - trr THEN trhy = trhy - 3
		IF trx < tpx THEN trx = trx + 1
		IF trx > tpx THEN trx = trx - 1
		GOSUB tr_draw
		' caught?
		tdy = tpy + 16
		IF tdy >= trhy THEN
			tdx = tpx - trx
			IF tpx < trx THEN tdx = trx - tpx
			IF tdx < 12 THEN
				IF binv = 0 THEN
					trst = 2
					tresc = 0
					trneed = 7 + trw
				END IF
			END IF
		END IF
		' gone high or gone away: let go
		IF tpy < 184 - trr THEN trst = 0
		tover = 0
		IF tpx < 46 THEN tover = 1
		IF tpx > 201 THEN tover = 1
		IF tover = 0 THEN trst = 0
		RETURN
	END IF

	' HELD. Dragged down, steering ignored, and only flaps count. This is the one
	' place the flap is not about height -- it is about how many you can manage.
	' HELD. The grip stops you dead horizontally -- being dragged toward the lava
	' while still flying across the arena made the hand look like a suggestion.
	' Steering is ignored (see p_input) and the sideways momentum is killed, so
	' the ONLY thing that answers is the flap.
	trx = tpx
	#vx = 32768
	#py = #py + 200
	#vy = 32768
	trhy = tpy + 14
	GOSUB tr_draw
	IF tresc >= trneed THEN
		trst = 0
		#vy = 32768 - 1200		' torn free, and thrown clear
		SOUND 1,300,13
		sf1 = 6
		RETURN
	END IF
	IF tpy + 16 >= 190 THEN
		pdead = 1			' pulled under
		trst = 0
	END IF
	RETURN

	' THE FIST, AND THE ARM BEHIND IT. A hand hanging in mid-air over the lava
	' reads as a floating object, not as something reaching OUT of the pit -- the
	' arm is what makes it a troll. Sprite 14 is a second, CONNECTED segment held
	' 14 px below the fist, so the two move as one limb and the reach stays
	' visually anchored to the pit it comes from.
tr_draw:
	SPRITE 12,trhy,trx,44,9
	' The arm is ITS OWN sprite -- an angled forearm, not a second fist. Two hands
	' stacked read as two trolls, which is the opposite of the one long limb the
	' effect needs.
	' THE ARM STAYS IN THE PIT. Drawn at a fixed offset below the fist it rose out
	' of the lava with it, and a whole troll climbing free of the pit is not what
	' this is -- it is a limb reaching UP out of one. The forearm is therefore
	' pinned near the lava line and only the FIST travels; the arm covers the gap
	' between them and is hidden when the hand is close enough not to need it.
	tay = 176
	IF trhy > 162 THEN
		SPRITE 14,SPRHID,0,0,0
	ELSE
		SPRITE 14,tay,trx,56,6
	END IF
	RETURN

	' ---------------------------------------------------------- pterodactyl
	' Wave 8 onward, and on ANY wave that drags -- the arcade's answer to camping.
	' Faster than every knight, and invulnerable except to a level lance straight
	' down an OPEN mouth, which is why its two frames differ so much: you have to
	' be able to call the shot at speed.
ptero:
	IF ptst = 0 THEN
		ptw = 0
		IF wave >= 8 THEN ptw = 1
		IF #wvt > 2400 THEN ptw = 1	' 40 seconds: stop hiding
		IF ptw = 1 THEN
			IF #wvt > 600 THEN
				ptst = 1
				pty = #py / 256
				ptx = 0
				ptf = 0
				IF #px > 32768 THEN
					ptx = 255
					ptf = 1
				END IF
				ptmo = 0
				SOUND 2,200,12
				sf2 = 10
			END IF
		END IF
		SPRITE 13,SPRHID,0,0,0
		RETURN
	END IF

	ptmo = ptmo + 1
	ptmo = ptmo AND 31
	pgx = #px / 256
	pgy = #py / 256
	IF ptx < pgx THEN
		ptx = ptx + 4
		ptf = 0
	ELSE
		ptx = ptx - 4
		ptf = 1
	END IF
	IF pty < pgy THEN pty = pty + 2
	IF pty > pgy THEN pty = pty - 2

	ptp = 48
	IF ptmo < 12 THEN ptp = 52	' mouth open on the low part of the cycle
	SPRITE 13,pty,ptx,ptp,10

	IF pdead > 0 THEN RETURN
	ptdx = pgx - ptx
	IF pgx < ptx THEN ptdx = ptx - pgx
	IF ptdx > 11 THEN RETURN
	ptdy = pgy - pty
	IF pgy < pty THEN ptdy = pty - pgy
	IF ptdy > 11 THEN RETURN

	' THE ONLY WAY TO KILL IT: mouth open, lances level, and you facing it.
	IF ptp = 52 THEN
		IF ptdy < 5 THEN
			ptc = 0
			IF pface = 0 THEN
				IF pgx < ptx THEN ptc = 1
			ELSE
				IF pgx > ptx THEN ptc = 1
			END IF
			IF ptc = 1 THEN
				ptst = 0
				#score = #score + 100
				SOUND 0,180,13
				sf0 = 12
				GOSUB prt_score
				SPRITE 13,SPRHID,0,0,0
				RETURN
			END IF
		END IF
	END IF
	IF binv = 0 THEN pdead = 1
	RETURN

	' ====================== TEMPORARY: LOOP RATE PROBE ======================
	' Two digits at row 0, column 20: LOOP PASSES PER SECOND.
	'
	' There is a WAIT at the top of the main loop, so every pass costs at least
	' one vblank and the achievable rates are quantised: 60, 30, 20, 15. That
	' makes this number diagnostic rather than merely informative --
	'
	'   60  the loop finishes inside one frame. Any remaining sluggishness is
	'       the EMULATOR, or the physics constants, and not the code.
	'   30  the body overruns one frame and WAIT costs a whole second one. The
	'       fix is to make the body cheaper, and HALF a frame of work is enough
	'       to get back to 60 -- there is no partial credit.
	'   20  it is overrunning two.
	'
	' Three optimisation passes have been made on the strength of counted array
	' reads. This measures the thing itself, so the next pass is aimed rather
	' than guessed -- and it tells us when to STOP, which counting never did.
	'
	' Remove this routine, its GOSUB and its variables once the answer is known.
lprate:
	lpc = lpc + 1
	#lpd = FRAME
	#lpd = #lpd - #lpl
	IF #lpd < 60 THEN RETURN
	#lpl = FRAME
	lph = lpc / 10
	#lpa = 6164			' row 0, column 20
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

	' ------------------------------------------------------------ sound tick
	' EVERY latched channel needs an explicit note-off or the tone sustains for
	' ever. Ticked after every WAIT, including inside the death animation.
sfx_tick:
	IF sf0 > 0 THEN
		sf0 = sf0 - 1
		IF sf0 = 0 THEN SOUND 0,800,0
	END IF
	IF sf1 > 0 THEN
		sf1 = sf1 - 1
		IF sf1 = 0 THEN SOUND 1,800,0
	END IF
	IF sf2 > 0 THEN
		sf2 = sf2 - 1
		IF sf2 = 0 THEN SOUND 2,800,0
	END IF
	RETURN

	INCLUDE "art.bas"
	INCLUDE "font.bas"

	' Character colours, EIGHT BYTES PER CHARACTER (one per scan line) -- supply
	' fewer and DEFINE COLOR reads whatever follows in ROM as colour data.
	' 7 chars x 8 = 56 bytes, an even run.
col_chars:
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1	' platform left, grey on black
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1	' platform middle
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1	' platform right
	DATA BYTE $A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8	' lava surface a, yellow on red
	DATA BYTE $A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8	' lava surface b
	DATA BYTE $88,$88,$88,$88,$88,$88,$88,$88	' lava body, solid red
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1	' spare-life icon
	DATA BYTE $71,$71,$71,$71,$71,$71,$71,$71	' spawn pad, CYAN -- it has to
						' read as a pad against grey rock
	DATA BYTE $81,$81,$81,$81,$81,$81,$81,$81	' troll arm, red -- it is lava
