	' THE TI CART IS BANKED: the program runs from the 24,336-byte fixed area
	' copied into RAM, and ALL ITS DATA -- art, font, flame frames, tables --
	' lives in bank 1, which is selected here and never deselected, so every
	' DEFINE and every table read finds it without a switch. ColecoVision's
	' 32 KB window holds it all unbanked.
#if TI994A
	BANK ROM 128
	BANK SELECT 1
#endif
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

	' ALL MOTION IS PER PASS, and a pass is one 30 Hz tick (see main_tick). These
	' were tuned when the loop managed ~15 passes a second; at 30 every velocity
	' and impulse below is HALF the old figure, every acceleration a QUARTER, and
	' every pass-counted timer DOUBLE, so the game moves at the speed it was tuned
	' at -- only twice as smoothly.
	CONST GRAV = 11			' added to #vy every pass. Heavier than it looks:
					' Joust's mount FALLS, and the flap has to fight it
	CONST ACCX = 13			' horizontal acceleration while steering
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
	CONST LAVAA = 131		' lava surface, flames -- two out-of-step
	CONST LAVAB = 132		' characters, animated by lava_tick
	CONST LAVAC = 133		' lava body
	CONST SFX_FLAP = 1
	CONST SFX_STEP = 2
	CONST SFX_SKID = 3
	CONST SFX_CLANK = 4
	CONST SFX_UNHORSE = 6
	CONST SFX_EGGGET = 7
	CONST SFX_SPAWN = 8
	CONST SFX_RESCUE = 9
	CONST SFX_BUMP = 10
	CONST SFX_HATCH = 11
	CONST SFX_GRAB = 13
	CONST SFX_ESCAPE = 14
	CONST SFX_PTERO = 15
	CONST SFX_PTKILL = 16
	CONST SFX_XLIFE = 17
	CONST SFX_SURV = 18
	CONST SFX_DIGIT = 19
	CONST SFX_DIE = 20
	CONST LIFECH = 134
	CONST PADCH = 135
	CONST ROCKCH = 136		' the base's body, below its surface
	CONST EGGCH = 137		' an egg waiting on a ledge (Egg waves)
	CONST ROCKL = 138		' ... its sloping left end
	CONST ROCKR = 139		' ... and right end
	' SPRITE PATTERNS (pattern number = 16x16 sprite index x 4; see setup).
	CONST P_OST = 0			' ostrich, 8 frames right then 8 left
	CONST P_BUZ = 64		' buzzard, the same layout
	CONST P_RIDER = 128		' rider, right then left
	CONST P_EGG = 136
	CONST P_EGGX = 140		' cracked
	CONST P_RUN = 144		' knight on foot, right then left
	CONST P_HAND = 152
	CONST P_ARM = 156
	CONST P_PT = 160		' pterodactyl: shut, open right; shut, open left
	' MOUNT FRAMES, as pattern offsets within one facing.
	CONST F_STAND = 0
	CONST F_SKID = 20
	CONST F_UP = 24			' wings up
	CONST F_DOWN = 28		' wings down
	' SPRITE SLOTS. Every figure is TWO sprites, rider over mount, so the slots
	' are handed out in blocks -- grep here before taking one:
	'   0-1 player (rider, mount)   2-13 knights (2 + 2*kni rider, +1 mount)
	'   14-17 eggs   18 rescue bird   19 troll hand   20 troll arm
	'   21 pterodactyl   22-31 unused, held hidden
	CONST NTEG = 12			' Egg wave: eggs on the ledges, DIM 0..11
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

	' ROW -> ISLAND index. THE SINGLE BIGGEST PERFORMANCE STRUCTURE IN THE GAME.
	'
	' Every actor used to test its y against all ten islands EVERY FRAME. Even with
	' a y-gate that is ~60 instructions x 10 islands = ~600 per actor, and with six
	' knights, four eggs (twice each), the player (three times) and the rescue bird
	' that is ~180 island iterations a frame -- comfortably more than a TI-99
	' frame's entire instruction budget. It was measured, not guessed: k_body alone
	' was 44% of the frame, and almost all of k_body was this loop.
	'
	' EVERY ply() IS A MULTIPLE OF 8, so an island's surface lies in exactly one
	' character row, and at most three islands share a row (the base and both
	' bridges all sit on row 21). So a row indexes straight to its islands and the
	' scan becomes three array reads instead of ten gated ones.
	'
	' This is EXACT, not an approximation -- every action inside the loop body
	' re-tests its own band, so the old kok gate was purely an early-out and
	' replacing it changes no behaviour. That distinction matters: the earlier
	' attempt to halve this cost by testing on alternate frames was NOT exact, and
	' it let knights fall through ledges.
	'
	' 255 means "no island". DIMmed to 32 rows, not 24: feet at kmy + MH reach
	' y 192+, which is row 24 and would be a one-past-end read.
	DIM ir1(32)			' first island whose surface row is this row, or 255
	DIM ir2(32)			' second (rows 7 and 21 have more than one)
	DIM ir3(32)			' third  (row 21: base + both bridges)

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

	' THE ISLAND EACH PAD STANDS ON. A pad is not free-floating scenery -- it is
	' painted on an island's surface and actors materialise standing on it, so when
	' erosion takes the island the pad has to go with it. Without this a pad is
	' drawn hanging in empty air and, worse, k_spawn will happily materialise a
	' knight on it -- standing on nothing, in the middle of the sky.
	'
	' Three of the five pads sit on erodible ledges, so this is not a corner case:
	' pad 3 goes at waves 6, 10, 14...; pad 2 at 7, 11, 15...; pad 1 at 8, 12, 16...
	' Pads 0 (the base) and 4 (the top-right sliver) are on islands that never
	' erode, which is what guarantees k_spawn always has somewhere to put a knight.
	DIM padi(NPAD)			' index into plon() -- 255 would mean "always present"

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

	' KNIGHT TOP SPEED, per tier, for this wave (biased: 32768 +/- top). Set by
	' set_ktop at every wave start; k_body only reads it.
	DIM #kfastt(3)
	DIM #kslowt(3)

	' THE EGG WAVE'S TWELVE EGGS wait on the ledges as CHARACTERS (EGGCH), at the
	' fixed spots in teg_col/teg_row. There are only four egg sprites, so an egg becomes
	' a sprite only when it starts to hatch (teg_tick); until then it costs one
	' byte here and nothing on any scanline.
	DIM tegon(NTEG)			' 1 still waiting on its ledge

	stwv = 1			' 838 on the title overrides this
	GOSUB setup
	GOTO title_screen

	' ------------------------------------------------------------------ setup
setup:
	' FLICKER ON. Two sprites a figure means two birds side by side already fill
	' a scanline's four, and the fifth is simply not drawn. Rotating the slots
	' turns that into flicker shared round everybody, the player included, which
	' players read as busy rather than as an invisible enemy (CLAUDE.md 7A's
	' Choplifter lesson). Rider and mount never share a pixel, so it does not
	' matter which of the two the rotation puts on top.
	SPRITE FLICKER ON
	' THE VBLANK HANDLER IS TRIMMED BY tools/isrpatch.py (TI only). It copies
	' the sprites only when told: sprok 2 = every frame (menus), 1 = once, at the
	' end of a game pass, so a half-drawn pass is never shown. kbscan turns the
	' keyboard scan on for the screens that read keys. Both are plain variables
	' on ColecoVision too, where nothing reads them.
	FOR hai = 0 TO 31
		SPRITE hai,SPRHID,0,0,0
	NEXT hai
	sprok = 2
	kbscan = 1
	' THE ARCADE FACE. Replaces CVBasic's stock 8x8, which is a thin generic ASCII
	' font and reads like a BASIC listing rather than an arcade cabinet -- undoing a
	' good deal of what the sprites are doing. 59 characters, 32-90, contiguous.
	' Colours are left alone: a DEFINE COLOR run this long would cost another 472
	' bytes to say "white" 59 times.
	DEFINE CHAR 32,59,font_bits
	' Characters 128-139 and their colours, generated together (genart.py).
	DEFINE CHAR PLATL,12,chr_plat_l
	DEFINE COLOR PLATL,12,col_chars
	DEFINE SPRITE 0,8,spr_ost_r	' P_OST
	DEFINE SPRITE 8,8,spr_ost_l
	DEFINE SPRITE 16,8,spr_buz_r	' P_BUZ
	DEFINE SPRITE 24,8,spr_buz_l
	DEFINE SPRITE 32,2,spr_rider	' P_RIDER
	DEFINE SPRITE 34,1,spr_egg	' P_EGG
	DEFINE SPRITE 35,1,spr_egg_x	' P_EGGX
	DEFINE SPRITE 36,2,spr_runner	' P_RUN
	DEFINE SPRITE 38,1,spr_hand	' P_HAND
	DEFINE SPRITE 39,1,spr_arm	' P_ARM
	DEFINE SPRITE 40,4,spr_pt	' P_PT

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
	padi(0) = 0				' BASE            -- never erodes
	padi(1) = 5				' upper middle    -- goes at waves 8, 12, 16...
	padi(2) = 4				' right, middle   -- goes at waves 7, 11, 15...
	padi(3) = 3				' left, middle    -- goes at waves 6, 10, 14...
	padi(4) = 9				' top right       -- never erodes
	RETURN

	' EROSION. Deterministic, never random -- a player has to be able to learn the
	' layout. The bridges burn at wave 3 and stay gone; from wave 6 one further
	' ledge goes each wave, in a fixed order; and every Egg wave restores the lot,
	' exactly as the arcade does.
set_islands:
	GOSUB set_isl_on
	' REBUILD THE ROW TABLE. Must run after every erosion change, and set_isl_on is
	' the only place plon() is written, so this is the one correct place for it.
	FOR sii = 0 TO 31
		ir1(sii) = 255
		ir2(sii) = 255
		ir3(sii) = 255
	NEXT sii
	FOR sii = 0 TO NPLAT - 1
		IF plon(sii) = 1 THEN
			sir = ply(sii) / 8
			IF ir1(sir) = 255 THEN
				ir1(sir) = sii
			ELSE
				IF ir2(sir) = 255 THEN
					ir2(sir) = sii
				ELSE
					ir3(sir) = sii
				END IF
			END IF
		END IF
	NEXT sii
	RETURN

	' the erosion rules themselves -- several early RETURNs, which is why the table
	' rebuild above wraps this rather than living inside it
set_isl_on:
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
	sprok = 2
	kbscan = 1
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
	sfn = SFX_DIGIT : GOSUB sfx_play
	RETURN

new_game:
	kbscan = 0			' no keys read in play: the scan is skipped
	#score = 0			' stored in TENS of points: every award in
					' Joust is a multiple of 50, so this is exact
					' and 16 bits then reaches 655,350.
	lives = 3
	#nxtb = 2000			' next extra bird: 20,000, in tens
	' 838 sets stwv; new_wave increments, so start one below it.
	wave = stwv - 1
	pover = 0
	wsurv = 0			' no wave has been played, so none is owed a bonus
	GOSUB new_wave
	GOTO main

	' ------------------------------------------------------------- new wave
new_wave:
	' THE SURVIVAL BONUS for the wave just finished: 3000 if it was a Survival
	' wave and no bird was lost in it. Paid here, between waves, with the screen
	' still showing the arena it was earned in.
	' A bird lost on the very pass the wave ended has not been counted yet
	' (do_death runs after this), hence pdead as well as wlost.
	IF wsurv = 1 THEN
		IF wlost = 0 THEN
			IF pdead = 0 THEN GOSUB surv_bonus
		END IF
	END IF
	wave = wave + 1
	ecoll = 0			' eggs collected this wave -> award ladder
	wlost = 0
	' WAVE TYPE. Egg waves are 5, 10, 15...; Survival waves are 2 and then every
	' 5th from 10, so from wave 10 on the two coincide (DESIGN.md 9).
	wm5 = wave
	WHILE wm5 >= 5
		wm5 = wm5 - 5
	WEND
	wegg = 0
	IF wm5 = 0 THEN wegg = 1
	wsurv = wegg
	IF wave < 10 THEN wsurv = 0
	IF wave = 2 THEN wsurv = 1
	#wvt = 0			' frames elapsed in this wave (pterodactyl clock)
	trst = 0
	ptst = 0
	' AGGRESSION RISES WITH THE WAVE, not just with the tier. A Bounder in wave 12
	' should not fly like a Bounder in wave 1: same strategy, sharper execution.
	agg = wave
	IF agg > 16 THEN agg = 16
	GOSUB set_ktop
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
	IF wegg = 1 THEN nwk = 0	' Egg wave: the eggs ARE the knights
	kpend = nwk			' still to materialise this wave
	spwt = 80			' passes until the next one may appear
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
		END IF
	NEXT nwi

	FOR nwi = 0 TO NEGG - 1
		est(nwi) = 0
	NEXT nwi
	' THE EGG WAVE'S EGGS, on the ledges. Every island is back on an Egg wave
	' (set_isl_on), so every spot in the table has rock under it.
	tegn = 0
	FOR nwi = 0 TO NTEG - 1
		tegon(nwi) = wegg
		IF wegg = 1 THEN
			tegi = nwi
			tegc = EGGCH
			GOSUB teg_put
			tegn = tegn + 1
		END IF
	NEXT nwi
	tegi = 0
	tegt = 150			' five seconds before the first one stirs
	GOSUB prt_hud
	' THE WAVE BANNER, two rows of open sky in the middle of the arena. It is
	' background, so the knights fly over it; main clears it after 3 seconds.
	PRINT AT 332,"WAVE ",wave
	IF wegg = 1 THEN
		IF wsurv = 1 THEN
			PRINT AT 360,"EGG AND SURVIVAL"
		ELSE
			PRINT AT 364,"EGG WAVE"
		END IF
	ELSE
		IF wsurv = 1 THEN PRINT AT 361,"SURVIVAL WAVE"
	END IF
	wbnr = 90
	RETURN

	' 3000 POINTS, shown between waves. The loop WAITs, so the sprite copy runs
	' every frame and the sound is ticked every frame (CLAUDE.md 3A).
surv_bonus:
	#score = #score + 300
	GOSUB prt_score
	sprok = 2
	GOSUB hide_all
	PRINT AT 358,"SURVIVAL BONUS 3000"
	sfn = SFX_SURV : GOSUB sfx_play
	FOR sbi = 0 TO 120
		WAIT
		GOSUB sfx_tick
	NEXT sbi
	RETURN

	' ONE LEDGE EGG, drawn or cleared: tegi is the spot, tegc the character.
teg_put:
	#tega = teg_row(tegi)
	#tega = #tega * 32
	#tega = #tega + teg_col(tegi)
	#tega = #tega + 6144
	VPOKE #tega,tegc
	RETURN

	' THE TIER SPEEDS for this wave: 430 + 70 x tier, plus 4.5 per aggression step.
	' !! 16-BIT, AND MULTIPLIED VIA SEPARATE VARIABLES. As a plain variable the
	' 860 truncates (TRUNCATION.md 1a); and on the 9900 MPY leaves the high word
	' in r0, so the statement after a multiply must not read the multiplier back
	' (CLAUDE.md 3A). Shadow Lord fastest -- the RALLY-X inversion is the bug
	' this layout exists to avoid.
set_ktop:
	#sko = agg
	#sko = #sko * 9
	#sko = #sko / 2
	FOR skt = 0 TO 2
		#skv = skt
		#skv = #skv * 70
		#skv = #skv + 430
		#skv = #skv + #sko
		#kfastt(skt) = 32768 + #skv
		#kslowt(skt) = 32768 - #skv
	NEXT skt
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
	' LET GO. trst was only ever cleared at the START OF A WAVE, so a player
	' killed BY the hand respawned still held: the new bird appeared on the pad in
	' the middle of the arena and the hand -- which had been following the player's
	' x -- came up through the solid floor to hold it there. Death has to release
	' the grip, or the death repeats forever.
	trst = 0
	binv = 180			' brief spawn invulnerability, in passes
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

	' NO PAD WITHOUT ITS ISLAND -- see the padi() comment at the DIMs.
	FOR dfi = 0 TO NPAD - 1
		IF plon(padi(dfi)) = 1 THEN
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
		END IF
	NEXT dfi

	' The lava fills everything below the floor line.
	' ROWS 22-23 ONLY, below the base. It used to start at row 20 -- the base's own
	' row -- and paint over it, so the floor you were standing on was drawn as
	' lava. Collision read the island table and was right; only the picture lied.
	' ROWS 22-23: THE BASE STANDS IN THE LAVA. Under the base's span (columns
	' 5-25) its rock goes down to the bottom of the screen, sloping in at each
	' end, and the score is cut into it; either side is the pit, flames on top.
	FOR dfi = 0 TO 31
		#dfa = 6848 + dfi		' row 22 = 704, plus the name table's 6144
		dfc = LAVAA
		IF dfi AND 1 THEN dfc = LAVAB
		dfd = LAVAC
		IF dfi >= 5 THEN
			IF dfi <= 25 THEN
				dfc = ROCKCH
				IF dfi = 5 THEN dfc = ROCKL
				IF dfi = 25 THEN dfc = ROCKR
				dfd = dfc
			END IF
		END IF
		VPOKE #dfa,dfc
		#dfa = #dfa + 32
		VPOKE #dfa,dfd
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
	' THE SCORE IS IN THE BASE, as in the arcade: row 22, columns 9-14, with the
	' spare birds at columns 17-20. The top of the screen is all sky.
prt_hud:
	GOSUB prt_score
	GOSUB prt_lives
	RETURN

	' Six digits, printed from #score which counts TENS, so a zero is appended.
prt_score:
	' AN EXTRA BIRD EVERY 20,000. Checked here because every award ends by
	' printing the score. #nxtb stops at 65535 rather than wrapping, which would
	' award a bird on every point from then on.
	IF #score >= #nxtb THEN
		IF lives < 9 THEN lives = lives + 1
		IF #nxtb > 63535 THEN
			#nxtb = 65535
		ELSE
			#nxtb = #nxtb + 2000
		END IF
		sfn = SFX_XLIFE : GOSUB sfx_play
		GOSUB prt_lives
	END IF
	#psv = #score
	#psd = 10000
	psc = 6
	#psa = 6857			' row 22 col 9: 704 + 9 + 6144
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
	' RIGHT-JUSTIFIED, so the last icon always sits in column 29 and the row
	' empties from the left (CLAUDE.md 7A). Tested as slot + spares > 3, never
	' as slot >= 4 - spares: spares is unsigned and can exceed 4 with extra birds.
	FOR pli = 0 TO 3
		#pla = 6865			' row 22 col 17: 704 + 17 + 6144
		#pla = #pla + pli
		plc = BLANK
		IF pli + plv > 3 THEN plc = LIFECH
		VPOKE #pla,plc
	NEXT pli
	RETURN

	' ============================================================ main loop
main:
	#tkf = FRAME			' this pass's tick starts now
	tpar = tpar XOR 1		' tick parity: alternate-tick work, half-pixel steps
	#wvt = #wvt + 1
	GOSUB p_input
	GOSUB p_move
	GOSUB k_spawn
	' A wave ends only when nothing is left to fight AND nothing left to hatch.
	' Counted on the way through k_move and e_move rather than by two more loops
	' over the same arrays: anything alive sets mnl.
	mnl = kpend
	GOSUB k_move			' moves, jousts and draws every knight
	GOSUB rb_move
	GOSUB troll
	GOSUB ptero
	GOSUB e_move			' moves, collects and draws every egg
	IF tegn > 0 THEN GOSUB teg_tick	' Egg wave: the eggs still on the ledges
	IF wbnr > 0 THEN
		wbnr = wbnr - 1
		IF wbnr = 0 THEN
			PRINT AT 332,"        "
			PRINT AT 360,"                "
		END IF
	END IF
	GOSUB draw
	GOSUB sfx_tick
	lavt = lavt + 1
	IF lavt >= 5 THEN GOSUB lava_tick
	sprok = 1			' publish this pass's sprites at the next vblank
	IF mnl = 0 THEN GOSUB new_wave

	IF pdead > 0 THEN GOSUB do_death
	IF pover = 1 THEN GOTO game_over

	' THE FIXED TICK: one pass every TWO frames, 30 a second, never faster. Every
	' speed, gravity and timer in this file is per PASS, so a loop that ran as fast
	' as the work allowed made the whole game slow down as the arena filled (15
	' passes a second on wave 1, 10 by wave 12). With the work now inside two
	' frames on every wave, the pass rate -- and so the game speed -- is constant.
main_tick:
	#tkd = FRAME
	#tkd = #tkd - #tkf
	IF #tkd < 2 THEN
		WAIT
		GOTO main_tick
	END IF
	GOTO main

	' --------------------------------------------------------------- input
p_input:
	IF binv > 0 THEN
		binv = binv - 1
		IF binv = 0 THEN padu(0) = 0	' materialised: release the pad
	END IF

	' FLAP IS EDGE TRIGGERED -- holding fire must not hover. The released state
	' has to be seen before the next flap counts.
	pflnow = 0
	IF cont1.button THEN
		IF pflp = 0 THEN
			pflp = 1
			pflnow = 1			' this pass's beat steers, below
			IF trst = 2 THEN tresc = tresc + 1
			' ADDITIVE, not a reset. Setting the velocity outright meant the
			' FIRST flap was the whole climb -- full power from a standing
			' start, and further presses added nothing while it decayed. Each
			' beat now adds to what you already have and the climb builds, so
			' a single tap is a nudge and holding a rhythm is what gains
			' height. Clamped so mashing cannot exceed a real climb rate.
			#vy = #vy - 200
			IF #vy < 32768 - 550 THEN #vy = 32768 - 550
			pfa = 20			' one press, one beat of the wings
			sfn = SFX_FLAP : GOSUB sfx_play
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
	' THE ARCADE'S CONTROLS. Momentum is KEPT: letting go of the stick does not
	' slow the bird, on the ground or in the air -- it runs or glides on until you
	' do something about it. On the ground the stick is the throttle, and pushing
	' AGAINST the run is a skid, braking hard with the feet out, before the bird
	' turns. In the air the stick only turns you round: speed comes from the wings,
	' so a flap with the stick held is what pushes you that way.
	pskd = 0
	pdir = 0
	IF cont1.left THEN pdir = 1
	IF cont1.right THEN pdir = 2
	IF pdir = 0 THEN RETURN
	pin = 1
	IF pgnd = 1 THEN
		IF pdir = 2 THEN
			IF #vx < 32768 - 40 THEN
				pskd = 1		' running left, pushing right
				#vx = #vx + 30
			ELSE
				pface = 0
				IF #vx < 32768 + 550 THEN #vx = #vx + ACCX
			END IF
		ELSE
			IF #vx > 32768 + 40 THEN
				pskd = 1
				#vx = #vx - 30
			ELSE
				pface = 1
				IF #vx > 32768 - 550 THEN #vx = #vx - ACCX
			END IF
		END IF
		RETURN
	END IF
	pface = pdir AND 1		' 1 left, 0 right
	IF pflnow = 1 THEN
		IF pdir = 2 THEN
			#vx = #vx + 120
			IF #vx > 32768 + 550 THEN #vx = 32768 + 550
		ELSE
			#vx = #vx - 120
			IF #vx < 32768 - 550 THEN #vx = 32768 - 550
		END IF
	END IF
	RETURN

	' ------------------------------------------------------ player movement
p_move:
	#vy = #vy + GRAV
	IF #vy > 32768 + 590 THEN #vy = 32768 + 590	' terminal fall speed

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
		#vy = 32768 + 110
	END IF

	GOSUB p_isls
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
	' pfrm is a pattern offset within one facing (F_* and the run beats 4-16).
	IF pfa > 0 THEN
		pfa = pfa - 1
		pfrm = F_DOWN			' the power stroke
		IF pfa < 10 THEN pfrm = F_UP	' recovered
	ELSE
		IF pgnd = 1 THEN
			IF pskd = 1 THEN
				pfrm = F_SKID
				IF tpar THEN GOSUB sfx_skid
			ELSE
				#pspd = #vx - 32768
				IF #vx < 32768 THEN #pspd = 32768 - #vx
				IF #pspd < 40 THEN
					pfrm = F_STAND
				ELSE
					' FOUR BEATS, faster as the bird does: the legs are the
					' speedometer. A footfall on the two striding beats.
					prun = prun + 1
					IF #pspd > 300 THEN prun = prun + 1
					prb = prun / 4
					prb = prb AND 3
					prb = prb * 4
					prb = prb + 4
					IF prb <> pfrm THEN
						IF prb = 4 THEN GOSUB sfx_step
						IF prb = 12 THEN GOSUB sfx_step
					END IF
					pfrm = prb
				END IF
			END IF
		ELSE
			pfrm = F_UP			' falling: wings raised
			IF #vy < 32768 THEN pfrm = F_DOWN
		END IF
	END IF
	RETURN

	' THE PLAYER AGAINST THE ISLANDS -- through the row table, like the knights.
	'
	' This used to be three loops over all ten islands (head bump, landing, side
	' push), every pass, for ~9% of the whole frame. An island can only matter if
	' its surface row is within reach of the body: from 7 px above the head (the
	' underside band) to the feet + 8 (the landing band), which is at most four
	' character rows. The row table holds only islands that are PRESENT, so the
	' old plon() test goes too.
	'
	' Each candidate island gets bump, then land, then side, on the current #py.
	' The three used to run as three separate passes over all islands; no two
	' islands sit close enough, in x and y, for the order to matter.
p_isls:
	pgnd = 0
	prw = #py / 256
	IF prw >= 7 THEN
		prw = prw - 7
	ELSE
		prw = 0
	END IF
	prw = prw / 8
	prl = #py / 256
	prl = prl + MH
	prl = prl / 8
	WHILE prw <= prl
		pj = ir1(prw)
		IF pj < 255 THEN		' ir1 empty means the whole row is
			GOSUB p_isl
			pj = ir2(prw)
			IF pj < 255 THEN GOSUB p_isl
			pj = ir3(prw)
			IF pj < 255 THEN GOSUB p_isl
		END IF
		prw = prw + 1
	WEND
	RETURN

p_isl:
	pjt = ply(pj)
	#pjl = #plx1(pj)
	#pjr = #plx2(pj)
	pjh = #py / 256			' head: the sprite's top edge
	pjc = #px / 256
	pjc = pjc + 8			' centre x

	' PLATFORMS ARE SOLID FROM BELOW TOO. In the arcade an island is a wall in
	' every direction, which is exactly why the layout dictates the fight: you
	' must fly AROUND, and a knight above you cannot simply be escaped by rising
	' through the floor he stands on. The island is 8 px thick, so its underside
	' is ply + 8, and the bump is a BODY overlap, not head-only: the head can
	' clear an 8 px band in one step while the body is still inside it.
	IF #vy < 32768 THEN
		IF pjh <= pjt + 7 THEN
			pjb = pjh + MH - 1
			IF pjb >= pjt THEN
				IF pjc >= #pjl THEN
					IF pjc <= #pjr THEN
						#py = pjt + 8
						#py = #py * 256
						' BOUNCED OFF, not stopped. Parked under a ledge
						' you are as unreachable as parked on the roof,
						' and the joust stops being a contest.
						#vy = 32768 + 110
						pjh = pjt + 8
					END IF
				END IF
			END IF
		END IF
	END IF

	' Land when the FEET cross the surface while falling.
	IF #vy >= 32768 THEN
		pjf = pjh + MH			' feet
		IF pjf >= pjt THEN
			IF pjf <= pjt + 8 THEN
				IF pjc >= #pjl THEN
					IF pjc <= #pjr THEN
						pgnd = 1
						#py = pjt - MH
						#py = #py * 256
						#vy = 32768
						pjh = pjt - MH
					END IF
				END IF
			END IF
		END IF
	END IF

	' NO ENTERING AN ISLAND FROM THE SIDE. Landing catches feet coming down and
	' the bump catches the head coming up, but neither fires on something
	' arriving horizontally, so the genuinely embedded case is pushed back out
	' the way it came.
	psh = pjh
	psb = psh + MH - 1
	IF psb >= pjt THEN
		IF psh <= pjt + 7 THEN
			psl = #px / 256
			psr = psl + MH - 1
			IF psr >= #pjl THEN
				IF psl <= #pjr THEN GOSUB p_side1
			END IF
		END IF
	END IF
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
		' AND ITS ISLAND MUST STILL BE THERE. Nested, not `AND` -- CVBasic's 9900
		' backend miscompiles <cmp> AND <cmp> (CLAUDE.md 3A). Pads 0 and 4 are on
		' islands that never erode, so this can never starve the spawner.
		IF plon(padi(ksi)) = 1 THEN
			ksd = kspx - padx(ksi)
			IF kspx < padx(ksi) THEN ksd = padx(ksi) - kspx
			IF ksd > 28 THEN ksp = ksi
		END IF
		END IF
	NEXT ksi
	IF ksp = 255 THEN RETURN		' no free pad clear of the player: WAIT

	padu(ksp) = 1
	kon(ksl) = 2				' 2 = materialising, not yet solid
	kpad(ksl) = ksp
	kmat(ksl) = 120			' two seconds of flashing, no more
	#kx(ksl) = padx(ksp)
	#kx(ksl) = #kx(ksl) * 256
	#ky(ksl) = pady(ksp)
	#ky(ksl) = #ky(ksl) * 256
	#kvx(ksl) = 32768
	#kvy(ksl) = 32768
	kflp(ksl) = 16
	kfa(ksl) = 0
	kwan(ksl) = 0
	ktx(ksl) = 128
	kty(ksl) = 60
	ktier(ksl) = 0
	IF wave > 3 THEN ktier(ksl) = kpend AND 1
	' SHADOW LORDS ARRIVE ONE MORE PER WAVE from 16: the last knight of wave 16,
	' the last two of wave 17, and so on until every one is a Lord.
	IF wave > 15 THEN
		ksv = wave - 15
		IF kpend <= ksv THEN ktier(ksl) = 2
	END IF
	kpend = kpend - 1
	spwt = 52
	sfn = SFX_SPAWN : GOSUB sfx_play
	RETURN

	' A KNIGHT ON FOOT. He falls to the nearest surface and walks, and he is
	' HELPLESS -- worth running down before his ride arrives.
k_foot:
	#cvy = #cvy + GRAV
	IF #cvy > 33268 THEN #cvy = 33268
	#cy = #cy + #cvy
	#cy = #cy - 32768
	kmy = #cy / 256
	kmx = #cx / 256
	IF #cvy >= 32768 THEN
		kf = kmy + MH
		FOR knj = 0 TO NPLAT - 1
			kpt = ply(knj)
			IF kf >= kpt THEN
				IF kf <= kpt + 8 THEN
				IF plon(knj) = 1 THEN
					kc = kmx + 8
					IF kc >= #plx1(knj) THEN
						IF kc <= #plx2(knj) THEN
							#cy = kpt - MH
							#cy = #cy * 256
							#cvy = 32768
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
	IF kmy > LAVAY THEN con = KDEAD	' he fell in; no rescue
	cfrm = 0
	RETURN

	' THE RIDERLESS BUZZARD. Flies in from the nearer screen edge, straight at the
	' man on foot, collects him, and the pair go back on the attack.
rb_move:
	' rb_launch scans every knight, so it runs only when a man may be waiting:
	' after a hatch (e_hatch) or when the bird has just finished a run.
	IF rbon = 0 THEN
		IF rbreq THEN GOSUB rb_launch
		IF rbon = 0 THEN RETURN
	END IF
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
	rbs = 1 + tpar			' 1.5 px a pass: 1 and 2 on alternate ticks
	IF rbx < rgx THEN
		rbx = rbx + rbs
		rbf = 0
	ELSE
		rbx = rbx - rbs
		rbf = 1
	END IF
	IF rby < rgy THEN rby = rby + 1
	IF rby > rgy THEN rby = rby - 1
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
			#kvy(rbt) = 32768 - 200
			kflp(rbt) = 12
			kwan(rbt) = 0
			rbon = 0
			rbreq = 1
			sfn = SFX_RESCUE : GOSUB sfx_play
		END IF
	END IF
	RETURN

	' Flying off. Straight on in the direction it was already going, no wrap: once
	' it is past the edge it is gone.
rb_flyby:
	IF rbf = 0 THEN
		IF rbx > 248 THEN
			rbon = 0
			rbreq = 1
			RETURN
		END IF
		rbx = rbx + 1 + tpar
	ELSE
		IF rbx < 6 THEN
			rbon = 0
			rbreq = 1
			RETURN
		END IF
		rbx = rbx - 1 - tpar
	END IF
	GOSUB rb_clear
	RETURN

	' THE BIRD DOES NOT FLY THROUGH ROCK. If its box has ended up inside an
	' island it climbs until it is clear, which reads as hopping the obstacle.
rb_clear:
	rbz = 0
	FOR rbj = 0 TO NPLAT - 1
		rpt = ply(rbj)
		' y first, on the value already fetched -- plon and the x span are three
		' more array reads that almost never matter.
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
		IF rby > 10 THEN rby = rby - 1 - tpar
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
	IF rbon = 0 THEN rbreq = 0		' nobody waiting: stop looking
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
	' embedded in island pj from the side: leave by the nearer face
p_side1:
	#psc = psl
	#psc = #psc + 8
	#psm = #pjl
	#psm = #psm + #pjr
	#psm = #psm / 2
	IF #psc < #psm THEN
		IF #pjl > 16 THEN
			#px = #pjl - 16
			#px = #px * 256
		END IF
	ELSE
		IF #pjr < 254 THEN
			#px = #pjr + 1
			#px = #px * 256
		END IF
	END IF
	' BOUNCE, exactly like glancing off a knight. Stopping dead against rock is
	' unreadable -- you cannot tell whether you hit something or the controls
	' dropped an input. Reversing the momentum and taking the steering away for
	' a moment MAKES the collision an event you can feel.
	#vx = 65536 - #vx
	pbnc = 24
	sfn = SFX_BUMP : GOSUB sfx_play
	RETURN

	' ----------------------------------------------------- knight movement
	' THINKING IS HALVED. Target choice, separation and routing are DECISIONS: they
	' write ktx/kty, which persist between frames. Running them for every knight
	' every frame is redundant, so half the knights decide on even frames and half
	' on odd. Movement stays per-frame and perfectly smooth; a knight simply
	' re-aims 30 times a second instead of 60, which is not a difference anybody
	' can see -- and it halves the most expensive part of the loop.
k_move:
	' THINKING RUNS ON ONE TICK IN FOUR per knight (target choice, separation,
	' routing): decisions that persist, so re-aiming 7.5 times a second is not
	' something anybody can see, and it spreads the cost -- knights 0 and 4 think
	' on tick 0, 1 and 5 on tick 1, and so on. Movement is every tick.
	tcnt = tcnt + 1
	kthf = tcnt AND 3
	cpx = #px / 256			' the player, for the jousts below
	cpy = #py / 256
	FOR kni = 0 TO NKN - 1
		IF kon(kni) > 0 THEN
			GOSUB k_one
		ELSE
			dks = kni * 2
	SPRITE dks + 2,SPRHID,0,0,0
	SPRITE dks + 3,SPRHID,0,0,0
		END IF
	NEXT kni
	RETURN

	' ============ THE CURRENT KNIGHT LIVES IN SCALARS WHILE WE WORK ON IT ======
	'
	' This is the real cost of the whole loop, and it was never the island tests.
	' The per-knight code touched its arrays 115 times, and on the 9900 EVERY
	' array element is about eight instructions -- load the index, shift it, scale
	' it, add the base, dereference. That is ~920 instructions per knight, ~5,500
	' for six of them, and a 60 Hz frame on this machine buys only about 5,000
	' instructions in total once wait states are counted. The loop could not fit
	' in a frame no matter how the tests were ordered.
	'
	' So the knight is COPIED INTO SCALARS once, the whole body runs on those at
	' one instruction each, and the changed ones are written back once. Fifteen
	' loads plus thirteen stores replaces a hundred and fifteen indexed accesses.
	'
	' ktier and kpad are read-only in here, so they are loaded and not stored.
	' Anything indexed by ksj (another knight) or knj (an island) stays an array:
	' those are genuinely different objects, not this one.
k_one:
	' THE COPY IN. In BASIC each of these is ~130 cycles on the 9900 -- index
	' load, shift, add, dereference, store, for every field -- and with the copy
	' out it was the single largest cost left in the pass. On the TI it is one
	' indexed MOVB/MOV per field instead. The label after it is not decoration:
	' inline ASM does not invalidate the compiler's register cache, and a branch
	' target forces the next statement to load from memory (CLAUDE.md 3A).
#if TI994A
	ASM movb @cvb_KNI,r1
	ASM srl r1,8
	ASM movb @array_KON(r1),@cvb_CON
	ASM movb @array_KTIER(r1),@cvb_CTIER
	ASM movb @array_KTX(r1),@cvb_CTX
	ASM movb @array_KTY(r1),@cvb_CTY
	ASM movb @array_KFLP(r1),@cvb_CFLP
	ASM movb @array_KFA(r1),@cvb_CFA
	ASM sla r1,1
	ASM mov @array__KX(r1),@cvb__CX
	ASM mov @array__KY(r1),@cvb__CY
	ASM mov @array__KVX(r1),@cvb__CVX
	ASM mov @array__KVY(r1),@cvb__CVY
#else
	con = kon(kni)
	ctier = ktier(kni)
	ctx = ktx(kni)
	cty = kty(kni)
	cflp = kflp(kni)
	cfa = kfa(kni)
	#cx = #kx(kni)
	#cy = #ky(kni)
	#cvx = #kvx(kni)
	#cvy = #kvy(kni)
#endif
k_one_in:
	' MATERIALISING: nothing moves. kmat and kpad are only ever needed here.
	IF con = 2 THEN
		cmat = kmat(kni) - 1
		kmat(kni) = cmat
		IF cmat = 0 THEN
			con = KLIVE
			kon(kni) = KLIVE
			padu(kpad(kni)) = 0	' the pad is free again
		END IF
		mnl = 1
		GOSUB k_draw
		RETURN
	END IF
	GOSUB k_body
	' THE JOUST AND THE DRAW RUN HERE, ON THE SCALARS. They used to be two more
	' loops over the arrays (collide, draw_knights) re-reading everything this
	' routine has just written back.
	' The horizontal reject is done here, inline: most knights are nowhere near
	' the player, and a GOSUB costs more than the test.
	dky = #cy / 256
	dkx = #cx / 256
	IF pdead = 0 THEN
		cdx = cpx - dkx
		IF cpx < dkx THEN cdx = dkx - cpx
		IF cdx < 12 THEN
			IF con = KLIVE THEN GOSUB c_knight
			IF con = KFOOT THEN GOSUB c_foot
		END IF
	END IF
	' DRAWN HERE, from the scalars. A man on foot wears the colour he will
	' become -- red, grey or blue -- which is the only warning you get of what
	' is about to be flying at you: a blue man on a ledge means a Shadow Lord in
	' a moment.
	' Two slots per knight: dks the rider, dks + 1 the mount (see the slot map).
	dks = kni * 2
	dks = dks + 2
	IF con = 0 THEN
		SPRITE dks,SPRHID,0,0,0
		SPRITE dks + 1,SPRHID,0,0,0
	ELSE
		mnl = 1
		dkc = tiercol(ctier)
		IF con = KFOOT THEN
			SPRITE dks,SPRHID,0,0,0
			dkp = cface / 8		' 0 or 4: the runner faces like the rider
			dkp = dkp + P_RUN
			SPRITE dks + 1,dky,dkx,dkp,dkc
		ELSE
			dkp = cface + cfrm	' both already pattern offsets
			dkp = dkp + P_BUZ
			SPRITE dks + 1,dky,dkx,dkp,12
			dkp = cface / 8
			dkp = dkp + P_RIDER
			dky = dky - 4
			SPRITE dks,dky,dkx,dkp,dkc
		END IF
	END IF
	' Written back: only what k_body can change. The frame and the facing are
	' recomputed every pass and only k_draw reads them, so they never leave the
	' scalars; the target only changes on a think tick.
	' THE COPY OUT, the same way. The frame and the facing are recomputed every
	' pass and only the draw above reads them, so they never leave the scalars.
#if TI994A
	ASM movb @cvb_KNI,r1
	ASM srl r1,8
	ASM movb @cvb_CON,@array_KON(r1)
	ASM movb @cvb_CTX,@array_KTX(r1)
	ASM movb @cvb_CTY,@array_KTY(r1)
	ASM movb @cvb_CFLP,@array_KFLP(r1)
	ASM movb @cvb_CFA,@array_KFA(r1)
	ASM sla r1,1
	ASM mov @cvb__CX,@array__KX(r1)
	ASM mov @cvb__CY,@array__KY(r1)
	ASM mov @cvb__CVX,@array__KVX(r1)
	ASM mov @cvb__CVY,@array__KVY(r1)
#else
	kon(kni) = con
	ktx(kni) = ctx
	kty(kni) = cty
	kflp(kni) = cflp
	kfa(kni) = cfa
	#kx(kni) = #cx
	#ky(kni) = #cy
	#kvx(kni) = #cvx
	#kvy(kni) = #cvy
#endif
	RETURN

k_body:
	' ONE test, not two. Written as two, a man who fell in the lava during k_foot
	' cleared his own KFOOT state and then FELL THROUGH into the mounted-knight
	' code below -- flying, jousting and being drawn as a dead slot.
	kth = kni AND 3			' this knight's think tick (see k_move)
	IF con = KFOOT THEN
		GOSUB k_foot
		RETURN
	END IF
	kmx = #cx / 256
	kmy = #cy / 256
	' !! 16-BIT, AND MULTIPLIED VIA A SEPARATE VARIABLE. As a plain `ktop` the 400
	' truncated to 144, so the tiers came out 144 / 234 / 324-and-wrapped-to-68 --
	' THE SHADOW LORD WOULD HAVE BEEN THE SLOWEST ENEMY IN THE GAME, the exact
	' inversion that shipped in RALLY-X. tools/bigvar.py caught it before the build.
	' The multiply reads #ktp2, not #ktop: on the 9900 MPY leaves the high word in
	' r0 and reading back the variable just multiplied returns 0 (CLAUDE.md 3A).
	' Per tier, per wave: computed once in new_wave (set_ktop), not per knight per
	' pass -- it was two multiplies for every knight on every frame.

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
	IF kth = kthf THEN
		IF ctier = 0 THEN GOSUB k_wander
		IF ctier = 1 THEN GOSUB k_hunt
		IF ctier = 2 THEN GOSUB k_lord

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
									#cx = #cx - 256
								ELSE
									#cx = #cx + 256
								END IF
							END IF
						END IF
						' and aim to pass on the far side of him,
						' off his altitude so the lances differ
						IF kmx < ksox THEN
							IF ctx > 28 THEN ctx = ctx - 28
						ELSE
							IF ctx < 227 THEN ctx = ctx + 28
						END IF
						IF kmy < ksoy THEN
							IF cty > 10 THEN cty = cty - 10
						ELSE
							IF cty < 140 THEN cty = cty + 10
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
	IF cflp > 0 THEN
		cflp = cflp - 1
	ELSE
		IF kmy > cty THEN
			cfa = 20		' they beat their wings too
			' 820, NOT 420. A knight flaps once per cooldown while gravity
			' collects 44 every frame in between: at the Bounder's 14-frame
			' cooldown that is 616 of sink against 420 of lift, so EVERY
			' TIER SANK. They drifted to the floor and stayed there -- the
			' "enemies get stuck at the bottom" report. They were trying and
			' losing to arithmetic. A player never hit this because a player
			' can tap every frame; a knight cannot.
			#cvy = #cvy - 410
			IF #cvy < 32768 - 575 THEN #cvy = 32768 - 575
			' EAGERER EVERY WAVE TOO, floored so it stays a flap and not
			' a hover. Same strategy per tier, sharper execution.
			kfc = 28 - ctier * 8
			kfw = agg / 2
			IF kfc > kfw THEN
				kfc = kfc - kfw
			ELSE
				kfc = 6
			END IF
			IF kfc < 6 THEN kfc = 6
			cflp = kfc
		END IF
	END IF

	' Steer toward the target x THE SHORTER WAY ROUND THE WRAP -- chasing across
	' the middle when the edge is nearer is the tell of an AI that does not know
	' the screen wraps.
	kgo = 0				' 0 steer right, 1 steer left
	IF ctx > kmx THEN
		kdd = ctx - kmx
		IF kdd >= 128 THEN kgo = 1
	ELSE
		kdd = kmx - ctx
		IF kdd < 128 THEN kgo = 1
	END IF
	cface = kgo * 32		' facing, as a pattern offset: 0 right, 32 left
	IF kgo = 0 THEN
		IF #cvx < #kfastt(ctier) THEN #cvx = #cvx + 9
	ELSE
		IF #cvx > #kslowt(ctier) THEN #cvx = #cvx - 9
	END IF

	#cvy = #cvy + GRAV
	IF #cvy > 33118 THEN #cvy = 33118

	#cy = #cy + #cvy
	#cy = #cy - 32768
	#cx = #cx + #cvx
	#cx = #cx - 32768

	kmy = #cy / 256
	IF kmy < TOPY THEN
		#cy = 2048
		#cvy = 32768 + 110	' knights are pushed off the ceiling too
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
	' !! COLLISION RUNS EVERY FRAME. It was briefly moved to alternate frames on
	' the argument that a knight moves ~3 px a frame and cannot cross an 8 px band
	' in two. THE NUMBER WAS WRONG: the vertical clamp is 1150 in 8.8, which is
	' 4.5 px a frame, so 9 px between checks against an 8 px band -- knights could
	' and did pass straight through ledges. Thinking may be halved because a stale
	' TARGET is harmless; collision may not, because a missed test is a knight
	' inside solid rock. Reverted.
	kf = kmy + MH			' feet
	kc = kmx + 8			' centre x
	cgnd = 0			' k_isl sets it on landing
	krt = 0
	IF kth = kthf THEN
		IF cty > kmy + 12 THEN krt = 1
	END IF
	' ISLAND TESTS -- O(1) via the row table, not O(10) over every island.
	'
	' This loop was 44% of the whole frame. It is now three array reads per row
	' the knight occupies. THE BEHAVIOUR IS UNCHANGED: k_isl re-tests each band
	' itself, so the old per-island y-gate was only ever an early-out.
	'
	' Two rows are consulted -- the head's and the feet's -- plus, only when the
	' feet sit exactly on a row boundary, the row above. That last case is not
	' optional: the landing band is [kpt, kpt+8], nine values, and a nine-wide
	' band straddles two rows precisely when kf is a multiple of 8. Dropping it
	' would silently narrow the band and put knights through ledges again.
	' ir1 is filled first, so ir1 = 255 means the whole row is empty: most rows
	' are, and an empty one now costs one read instead of a GOSUB and three.
	krw = kmy / 8
	IF ir1(krw) < 255 THEN GOSUB k_isl3
	krw = kf / 8
	kbw = krw * 8
	IF kf = kbw THEN
		IF krw > 0 THEN
			krw = krw - 1
			IF ir1(krw) < 255 THEN GOSUB k_isl3
			krw = krw + 1
		END IF
	END IF
	IF ir1(krw) < 255 THEN GOSUB k_isl3
	' ROUTING IS THE ONE CASE THE ROW TABLE CANNOT SERVE: it wants every island
	' BETWEEN the knight and its target, which is a range, not a row. So it keeps
	' its own scan AND its own y-gate -- without the gate it would be slower than
	' the loop this whole change replaced, because k_isl below deliberately has no
	' gate of its own (the row lookup is its gate). It runs only on a think frame
	' with the target below, so it is rare.
	IF krt = 1 THEN GOSUB k_route
	IF #cvy >= 32768 THEN
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
			#cy = LAVAY - MH
			#cy = #cy * 256
			#cvy = 32768 - 310
		END IF
	END IF

	' The frame, as a pattern offset (F_* and the run beats 4-16), as the player.
	IF cfa > 0 THEN
		cfa = cfa - 1
		cfrm = F_DOWN
		IF cfa < 10 THEN cfrm = F_UP
	ELSE
		IF cgnd = 1 THEN
			cfrm = F_STAND
			IF #cvx > 32768 + 60 THEN cgnd = 2
			IF #cvx < 32768 - 60 THEN cgnd = 2
			IF cgnd = 2 THEN
				cfrm = tcnt + kni
				cfrm = cfrm / 2
				cfrm = cfrm AND 3
				cfrm = cfrm * 4
				cfrm = cfrm + 4
			END IF
		ELSE
			cfrm = F_UP
			IF #cvy < 32768 THEN cfrm = F_DOWN
		END IF
	END IF
	RETURN

	' BOUNDER -- wanders. A fresh destination every second or two, and only one
	' roll in four is the player, so it reads as a creature going about its
	' business that sometimes notices you. Never a patrol: pacing a platform
	' back and forth is what makes an enemy look like furniture.


	' ROUTING -- islands between the knight and a target BELOW it.
	'
	' The one island test the row table cannot serve: this wants a RANGE of rows,
	' not a row, so it keeps the classic scan and its own y-gate. The gate is not
	' optional here -- k_isl deliberately has none (the row lookup IS its gate),
	' so calling k_isl ten times from here would have been slower than the loop
	' this whole change replaced.
	'
	' Steer around the NEARER edge: whichever side of the island the knight is
	' already closer to, aim 22 px past it. Aiming at the far edge makes a knight
	' cross the obstacle it is trying to avoid.
k_route:
	FOR knj = 0 TO NPLAT - 1
		kpt = ply(knj)
		IF kpt > kmy + 8 THEN
			IF kpt <= cty + 8 THEN
			IF plon(knj) = 1 THEN
				IF kc >= #plx1(knj) THEN
					IF kc <= #plx2(knj) THEN
						#kbl = kc
						#kbl = #kbl - #plx1(knj)
						#kbr = #plx2(knj)
						#kbr = #kbr - kc
						IF #kbl < #kbr THEN
							#kbx = #plx1(knj)
							IF #kbx > 22 THEN
								ctx = #kbx - 22
							ELSE
								ctx = 0
							END IF
						ELSE
							#kbx = #plx2(knj)
							IF #kbx < 233 THEN
								ctx = #kbx + 22
							ELSE
								ctx = 255
							END IF
						END IF
					END IF
				END IF
			END IF
			END IF
		END IF
	NEXT knj
	RETURN

	' the up-to-three islands whose surface lies in character row krw
k_isl3:
	knj = ir1(krw)
	IF knj < 255 THEN GOSUB k_isl
	knj = ir2(krw)
	IF knj < 255 THEN GOSUB k_isl
	knj = ir3(krw)
	IF knj < 255 THEN GOSUB k_isl
	RETURN

	' ONE island against one knight. Every branch re-tests its own band, so this
	' is safe to call for any island -- which is what lets the row table replace
	' the old scan without changing a single outcome.
k_isl:
	kpt = ply(knj)
	IF plon(knj) = 1 THEN
		IF kc >= #plx1(knj) THEN
			IF kc <= #plx2(knj) THEN
				IF #cvy >= 32768 THEN
					' falling: land on the surface
					IF kf >= kpt THEN
						IF kf <= kpt + 8 THEN
							#cy = kpt - MH
							#cy = #cy * 256
							#cvy = 32768
							cgnd = 1
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
						#cy = kpt + 8
						#cy = #cy * 256
						#cvy = 32768 + 110
					END IF
				END IF
			END IF
		END IF
	END IF
	RETURN

k_wander:
	cwan = kwan(kni)
	IF cwan > 0 THEN
		kwan(kni) = cwan - 1
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
		ctx = cpx
		cty = cpy - 4
		IF cpy < 4 THEN cty = 0
	ELSE
		ctx = RANDOM(255)
		cty = 24 + RANDOM(112)
	END IF
	RETURN

	' HUNTER -- seeks. Aims at the player, and one notch above him: level flight
	' into a joust is a coin toss, so it wants the high side of the contact.
k_hunt:
	ctx = cpx
	cty = cpy - 4
	IF cpy < 4 THEN cty = 0
	RETURN

	' SHADOW LORD -- fast, high, and higher still as it closes. It lives in the
	' top third and CLIMBS when near, because altitude decides the joust: the
	' climb is the attack, not a retreat from it.
k_lord:
	ctx = cpx
	cty = cpy - 12
	IF cpy < 12 THEN cty = 0
	klx = cpx - kmx
	IF kmx > cpx THEN klx = kmx - cpx
	IF klx < 56 THEN
		' CLOSING -- commit to the attack. Aim above him, wherever he is.
		cty = cpy - 24
		IF cpy < 24 THEN cty = 0
	ELSE
		' FAR OFF -- prefer height while crossing, but only as a preference.
		'
		' !! THIS CLAMP USED TO APPLY ALWAYS, and it made wave 16 onward
		' unplayable in the other direction: every knight is a Shadow Lord from
		' there, the clamp pinned every target to y=96, and a player standing on
		' the base at y=152 was 56 px BELOW anything the AI would ever aim at.
		' Nothing came down. The pterodactyl still did, which is exactly what
		' was reported -- it does not use this routine.
		'
		' A Shadow Lord flies high because it aims further ABOVE THE PLAYER than
		' the other tiers do, not because it refuses to leave the ceiling.
		IF cty > 100 THEN cty = 100
	END IF
	RETURN

	' --------------------------------------------------------- egg movement
e_move:
	FOR egi = 0 TO NEGG - 1
		IF est(egi) > 0 THEN
			GOSUB e_one
		ELSE
			SPRITE 14 + egi,SPRHID,0,0,0
		END IF
	NEXT egi
	RETURN

	' The egg lives in scalars while we work on it, exactly as the knight does --
	' same reason, same saving. gtier is read-only here so it is loaded, not stored.
e_one:
#if TI994A
	ASM movb @cvb_EGI,r1
	ASM srl r1,8
	ASM movb @array_EST(r1),@cvb_GST
	ASM movb @array_ETIER(r1),@cvb_GTIER
	ASM sla r1,1
	ASM mov @array__EX(r1),@cvb__GX
	ASM mov @array__EY(r1),@cvb__GY
	ASM mov @array__EVX(r1),@cvb__GVX
	ASM mov @array__EVY(r1),@cvb__GVY
	ASM mov @array__ETM(r1),@cvb__GTM
#else
	#gx = #ex(egi)
	#gy = #ey(egi)
	#gvx = #evx(egi)
	#gvy = #evy(egi)
	gst = est(egi)
	#gtm = #etm(egi)
	gtier = etier(egi)
#endif
e_one_in:
	GOSUB e_body
	' Collected and drawn here, on the scalars -- see k_one.
	IF gst > 0 THEN
		mnl = 1
		IF pdead = 0 THEN GOSUB c_egg
	END IF
	GOSUB e_draw
#if TI994A
	ASM movb @cvb_EGI,r1
	ASM srl r1,8
	ASM movb @cvb_GST,@array_EST(r1)
	ASM sla r1,1
	ASM mov @cvb__GX,@array__EX(r1)
	ASM mov @cvb__GY,@array__EY(r1)
	ASM mov @cvb__GVX,@array__EVX(r1)
	ASM mov @cvb__GVY,@array__EVY(r1)
	ASM mov @cvb__GTM,@array__ETM(r1)
#else
	#ex(egi) = #gx
	#ey(egi) = #gy
	#evx(egi) = #gvx
	#evy(egi) = #gvy
	est(egi) = gst
	#etm(egi) = #gtm
#endif
	RETURN

e_body:
	IF gst = 1 THEN
		IF #gtm > 0 THEN #gtm = #gtm - 1
		#gvy = #gvy + GRAV
		IF #gvy > 33118 THEN #gvy = 33118
		#gy = #gy + #gvy
		#gy = #gy - 32768
		#gx = #gx + #gvx
		#gx = #gx - 32768
		egy = #gy / 256
		egx = #gx / 256
		egf = egy + 16
		' ISLAND TEST -- O(1) row lookup, not a scan of all ten. See the ir1/ir2/ir3
		' comment at the DIMs: every ply() is a multiple of 8, so an island sits in one
		' character row. 		 re-tests the band itself, so this is exact.
		' The row above is consulted only when the feet land exactly on a boundary --
		' the band is nine values wide and straddles two rows precisely then.
		erw = egf / 8
		GOSUB e_isl3
		ebw = erw * 8
		IF egf = ebw THEN
			IF erw > 0 THEN
				erw = erw - 1
				GOSUB e_isl3
			END IF
		END IF
		' An egg that falls into the gap is simply gone.
		IF egy > LAVAY THEN gst = 0
		RETURN
	END IF

	' Resting: still sliding, bleeding off speed, and possibly skidding clean off
	' the edge of the island it landed on.
	IF gst = 2 THEN GOSUB e_rest
	' Resting, then cracking, then a fresh knight one tier higher.
	IF #gtm > 0 THEN
		#gtm = #gtm - 1
		IF #gtm = 180 THEN
			gst = 3
			sfn = SFX_HATCH : GOSUB sfx_play
		END IF
		RETURN
	END IF
	GOSUB e_hatch
	RETURN

	' FRICTION ON THE GROUND. The egg slides, slows, and stops -- and if it slides
	' off the end of its island it falls again, which is the arcade's behaviour and
	' makes a ledge a bad place to leave one.
e_rest:
	egfr = 3 + tpar			' 3.5 a pass: 3 and 4 on alternate ticks
	IF #gvx > 32768 THEN
		#gvx = #gvx - egfr
		IF #gvx < 32768 THEN #gvx = 32768
	ELSE
		IF #gvx < 32768 THEN
			#gvx = #gvx + egfr
			IF #gvx > 32768 THEN #gvx = 32768
		END IF
	END IF
	IF #gvx = 32768 THEN RETURN	' come to rest
	#gx = #gx + #gvx
	#gx = #gx - 32768
	' still supported?
	egx = #gx / 256
	egy = #gy / 256
	egc = egx + 8
	egf = egy + 16
	ergs = 0
	' ISLAND TEST -- O(1) row lookup, not a scan of all ten. See the ir1/ir2/ir3
	' comment at the DIMs: every ply() is a multiple of 8, so an island sits in one
	' character row. 	 re-tests the band itself, so this is exact.
	' The row above is consulted only when the feet land exactly on a boundary --
	' the band is nine values wide and straddles two rows precisely then.
	erw = egf / 8
	GOSUB e_rst3
	ebw = erw * 8
	IF egf = ebw THEN
		IF erw > 0 THEN
			erw = erw - 1
			GOSUB e_rst3
		END IF
	END IF
	IF ergs = 0 THEN
		gst = 1			' skidded off: falling again
		#gvy = 32768
	END IF
	RETURN

	' the up-to-three islands whose surface lies in character row erw --
	' landing, then support. Two separate bodies because they do different work.
e_isl3:
	egj = ir1(erw)
	IF egj < 255 THEN GOSUB e_isl
	egj = ir2(erw)
	IF egj < 255 THEN GOSUB e_isl
	egj = ir3(erw)
	IF egj < 255 THEN GOSUB e_isl
	RETURN

e_isl:
		ept = ply(egj)
		IF egf >= ept THEN
			IF egf <= ept + 8 THEN
			IF plon(egj) = 1 THEN	' y-gated above: 1 read to reject
				egc = egx + 8
				IF egc >= #plx1(egj) THEN
					IF egc <= #plx2(egj) THEN
						#gy = ept - 16
						#gy = #gy * 256
						gst = 2
						#gtm = 480	' now the REST timer
						' KEEP THE SIDEWAYS MOMENTUM. An egg that
						' stops dead the instant it touches rock
						' looks glued on; it should skid and
						' settle. e_rest below bleeds it off.
					END IF
				END IF
			END IF
		END IF
		END IF
	RETURN

e_rst3:
	egj = ir1(erw)
	IF egj < 255 THEN GOSUB e_rst
	egj = ir2(erw)
	IF egj < 255 THEN GOSUB e_rst
	egj = ir3(erw)
	IF egj < 255 THEN GOSUB e_rst
	RETURN

e_rst:
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
			ktier(ehj) = gtier + 1
			IF ktier(ehj) > 2 THEN ktier(ehj) = 0
			#kx(ehj) = #gx
			#ky(ehj) = #gy
			#kvx(ehj) = 32768
			#kvy(ehj) = 32768
			kflp(ehj) = 40
			gst = 0
			ehd = 1
			mnl = 1			' k_move has run: count him here
			rbreq = 1		' a man is waiting: rb_launch, look
		END IF
		END IF
	NEXT ehj
	' No free slot: wait and try again shortly rather than losing the hatch.
	IF ehd = 0 THEN #gtm = 60
	RETURN

	' ----------------------------------------------------------- collisions
	' Boxes overlap, then ALTITUDE decides. Written as nested single tests --
	' `a AND b` on comparisons is miscompiled by the 9900 backend. Called from
	' k_one on the CURRENT KNIGHT'S SCALARS (#cx, #cy, con...), which k_one
	' writes back afterwards; cpx/cpy are the player, set at the top of k_move.
c_knight:
	ckx = #cx / 256
	cky = #cy / 256
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
	#cvx = 65536 - #cvx
	#vx = 65536 - #vx
	sfn = SFX_CLANK : GOSUB sfx_play
	RETURN

k_unhorse:
	con = KDEAD
	kus = 50 + ctier * 25		' 500 / 750, in tens
	IF ctier = 2 THEN kus = 150	' Shadow Lord 1500
	#score = #score + kus
	sfn = SFX_UNHORSE : GOSUB sfx_play
	' Drop an egg carrying the knight's momentum.
	kud = 0				' egg placed? -- a flag, never an early RETURN
	FOR kuj = 0 TO NEGG - 1
		IF kud = 0 THEN
		IF est(kuj) = 0 THEN
			est(kuj) = 1
			#ex(kuj) = #cx
			#ey(kuj) = #cy
			#evx(kuj) = #cvx
			' POP UPWARD out of the joust, keeping the knight's sideways
			' momentum. An egg that simply drops from where he died is on
			' top of the player and reads as no egg at all.
			#evy(kuj) = 32768 - 260
			etier(kuj) = ctier
			' GRACE: about a quarter second (16 frames). Half a second sounded
			' right and was not -- a popped egg is often back on the rock
			' inside 30 frames, so the window where it was both AIRBORNE and
			' collectable could be nothing at all. It only has to last long
			' enough for the egg to leave the joust that produced it.
			' Without ANY grace the egg loop -- which runs later in this
			' very frame -- eats the egg where it was laid, since it is
			' created within collision range of the player by definition.
			#etm(kuj) = 32
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
	cfx = #cx / 256
	cfy = #cy / 256
	cdx = cpx - cfx
	IF cpx < cfx THEN cdx = cfx - cpx
	IF cdx > 11 THEN RETURN
	cdy = cpy - cfy
	IF cpy < cfy THEN cdy = cfy - cpy
	IF cdy > 11 THEN RETURN
	con = KDEAD
	GOSUB egg_award
	RETURN

c_egg:
	' Called from e_one on the CURRENT EGG'S SCALARS (#gx, #gy, gst, #gtm).
	' An egg still in its grace period has not left the joust yet.
	IF gst = 1 THEN
		IF #gtm > 0 THEN RETURN
	END IF
	' CENTRE TO CENTRE. The egg is 8x9 drawn in the LOWER part of its cell, so its
	' middle sits 11 px below its sprite origin while the bird's sits 8 below its
	' own. Comparing the origins measured a distance three pixels off, which near
	' the edge of the box is the difference between a catch and a miss -- and it
	' erred toward missing, which is exactly what "touched it and did not get it"
	' feels like.
	cex = #gx / 256
	cex = cex + 7			' art occupies columns 3-10, so the middle is +7
	cey = #gy / 256
	cey = cey + 11
	cpx2 = cpx + 8
	cpy2 = cpy + 8
	cdx = cpx2 - cex
	IF cpx2 < cex THEN cdx = cex - cpx2
	IF cdx > 10 THEN RETURN
	cdy = cpy2 - cey
	IF cpy2 < cey THEN cdy = cey - cpy2
	IF cdy > 10 THEN RETURN
	' CAUGHT IN MID-AIR: +500 on top of the ladder. gst is still 1 (airborne)
	' here; the grace period was dealt with above, so this is a real catch.
	IF gst = 1 THEN #score = #score + 50
	gst = 0
	GOSUB egg_award
	RETURN

	' THE EGG WAVE'S LEDGE EGGS. Collected by touch, exactly like a sprite egg and
	' on the same award ladder. Every few seconds, while an egg sprite is free, the
	' next one STIRS: its character goes and a resting sprite egg takes its place,
	' cracking almost at once and hatching six seconds later into a Bounder on
	' foot. So the wave is a race -- collect them before they wake.
	' While any are left the wave is not over (mnl).
teg_tick:
	mnl = 1
	IF pdead = 0 THEN
		tpcx = #px / 256
		tpcx = tpcx + 8
		tpcy = #py / 256
		tpcy = tpcy + 8
		FOR tgi = 0 TO NTEG - 1
			IF tegon(tgi) = 1 THEN
				tgx = teg_col(tgi) * 8
				tgx = tgx + 4
				tgd = tpcx - tgx
				IF tpcx < tgx THEN tgd = tgx - tpcx
				IF tgd < 11 THEN
					tgy = teg_row(tgi) * 8
					tgy = tgy + 4
					tgd = tpcy - tgy
					IF tpcy < tgy THEN tgd = tgy - tpcy
					IF tgd < 11 THEN
						tegon(tgi) = 0
						tegn = tegn - 1
						tegi = tgi
						tegc = BLANK
						GOSUB teg_put
						GOSUB egg_award
					END IF
				END IF
			END IF
		NEXT tgi
	END IF
	IF tegn = 0 THEN RETURN
	IF tegt > 0 THEN
		tegt = tegt - 1
		RETURN
	END IF
	tegt = 30			' no free egg sprite: look again in a second
	tgs = 255
	FOR tgi = 0 TO NEGG - 1
		IF est(tgi) = 0 THEN tgs = tgi
	NEXT tgi
	IF tgs = 255 THEN RETURN
	' The next waiting egg, round-robin from where the last one was taken.
	' tegn > 0 here, so the search ends.
	WHILE tegon(tegi) = 0
		tegi = tegi + 1
		IF tegi = NTEG THEN tegi = 0
	WEND
	tegon(tegi) = 0
	tegn = tegn - 1
	tegc = BLANK
	GOSUB teg_put
	' Sprite egg in the same place: the cell's art sits in sprite columns 3-10
	' and its bottom row on the sprite's bottom row, so x = col*8 - 3 and the
	' sprite top is one cell above the egg's own row.
	#ex(tgs) = teg_col(tegi) * 8
	#ex(tgs) = #ex(tgs) - 3
	#ex(tgs) = #ex(tgs) * 256
	#ey(tgs) = teg_row(tegi) * 8
	#ey(tgs) = #ey(tgs) - 8
	#ey(tgs) = #ey(tgs) * 256
	#evx(tgs) = 32768
	#evy(tgs) = 32768
	etier(tgs) = 2			' the tier wheel turns 2 -> 0: a Bounder
	#etm(tgs) = 200			' cracks at 180, hatches at 0
	est(tgs) = 2
	tegt = 120 - wave
	IF wave > 60 THEN tegt = 60
	RETURN

	' THE EGG AWARD LADDER: 250, 500, 750, then 1000 for every egg after that in
	' the wave -- in tens, and capped. Shared by sprite eggs, ledge eggs and a man
	' run down on foot.
egg_award:
	ecoll = ecoll + 1
	ceg = ecoll
	IF ceg > 4 THEN ceg = 4
	#score = #score + ceg * 25
	sfn = SFX_EGGGET : GOSUB sfx_play
	GOSUB prt_score
	RETURN

	' ---------------------------------------------------------------- death
do_death:
	sprok = 2			' this loop WAITs per frame: copy every frame
	SPRITE 0,SPRHID,0,0,0
	SPRITE 1,SPRHID,0,0,0
	sf0 = 0				' the loop below owns channel 0
	sfn = SFX_DIE : GOSUB sfx_play
	FOR ddi = 0 TO 30
		WAIT
		SOUND 0,200 + ddi * 20,13
		GOSUB sfx_tick
	NEXT ddi
	SOUND 0,800,0
	wlost = 1			' no Survival bonus for this wave
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
	sprok = 2
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
	' THE PLAYER: a white-armoured rider on the yellow ostrich. pfrm is already a
	' pattern offset within one facing; a facing is 8 frames, 32 patterns.
	drp = pface * 32
	drp = drp + pfrm
	dry = #py / 256
	drx = #px / 256
	drc = 11
	dkc = 15
	IF binv > 0 THEN
		IF binv AND 8 THEN
			drc = 1
			dkc = 1
		END IF
	END IF
	dkp = pface * 4
	dkp = dkp + P_RIDER
	dky = dry - 4
	SPRITE 0,dky,drx,dkp,dkc
	SPRITE 1,dry,drx,drp,drc
	' knights and eggs are drawn by k_one and e_one as they are moved
	' THE RESCUE BIRD: a riderless buzzard, beating its wings as it comes.
	IF rbon > 0 THEN
		rbp = rbf * 32
		rbp = rbp + P_BUZ + F_UP
		IF tcnt AND 4 THEN rbp = rbp + 4
		SPRITE 18,rby,rbx,rbp,12
	ELSE
		SPRITE 18,SPRHID,0,0,0
	END IF
	RETURN

	' A MATERIALISING knight, from k_one: flash, and draw nothing on alternate
	' beats so it reads as arriving rather than lurking.
k_draw:
	dky = #cy / 256
	dkx = #cx / 256
	dkc = 0
	IF cmat AND 4 THEN dkc = 15
	dks = kni * 2
	dks = dks + 2
	SPRITE dks + 1,dky,dkx,P_BUZ,dkc
	dky = dky - 4
	SPRITE dks,dky,dkx,P_RIDER,dkc
	RETURN

	' THE CURRENT EGG, from e_one's scalars.
e_draw:
	IF gst = 0 THEN
		SPRITE 14 + egi,SPRHID,0,0,0
		RETURN
	END IF
	dey = #gy / 256
	dex = #gx / 256
	dec = 15
	dep = P_EGG
	' NOT YET COLLECTABLE -> drawn GREY rather than white. The grace period was
	' invisible, so an egg you touched and did not get looked like a missed
	' collision or a dropped input rather than a rule.
	IF gst = 1 THEN
		IF #gtm > 0 THEN dec = 14
	END IF
	IF gst = 3 THEN
		' CRACKED, and flashing. The pattern change is the real warning; the
		' flash only draws the eye to it.
		dep = P_EGGX
		IF #gtm AND 8 THEN dec = 9
	END IF
	SPRITE 14 + egi,dey,dex,dep,dec
	RETURN

hide_all:
	FOR hai = 0 TO 21
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
		SPRITE 19,SPRHID,0,0,0
		SPRITE 20,SPRHID,0,0,0
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
				sfn = SFX_GRAB : GOSUB sfx_play
			END IF
		END IF
		SPRITE 19,SPRHID,0,0,0
		SPRITE 20,SPRHID,0,0,0
		RETURN
	END IF

	IF trst = 1 THEN
		' rising. It tracks sideways slowly -- you can outrun it, but not by
		' much, and not while still climbing out of the pit.
		IF trhy > 184 - trr THEN trhy = trhy - 1 - tpar	' 1.5 px a pass
		IF tpar THEN			' sideways at half a pixel a pass
			IF trx < tpx THEN trx = trx + 1
			IF trx > tpx THEN trx = trx - 1
		END IF
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
	' THE HAND DOES NOT TRAVEL. It grabbed at a pit and it holds you over that
	' pit; tracking the player's x let it drag itself across the arena and up
	' through the base, which is solid rock. Your horizontal movement is stopped
	' anyway (see p_input), so there is nothing for it to follow.
	#vx = 32768
	#py = #py + 100
	#vy = 32768
	trhy = tpy + 14
	GOSUB tr_draw
	IF tresc >= trneed THEN
		trst = 0
		#vy = 32768 - 600		' torn free, and thrown clear
		sfn = SFX_ESCAPE : GOSUB sfx_play
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
	SPRITE 19,trhy,trx,P_HAND,9
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
		SPRITE 20,SPRHID,0,0,0
	ELSE
		SPRITE 20,tay,trx,P_ARM,6
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
		IF #wvt > 1200 THEN ptw = 1	' 40 seconds: stop hiding
		IF ptw = 1 THEN
			IF #wvt > 300 THEN
				ptst = 1
				pty = #py / 256
				ptx = 0
				ptf = 0
				IF #px > 32768 THEN
					ptx = 255
					ptf = 1
				END IF
				ptmo = 0
				sfn = SFX_PTERO : GOSUB sfx_play
			END IF
		END IF
		SPRITE 21,SPRHID,0,0,0
		RETURN
	END IF

	ptmo = ptmo + 1
	ptmo = ptmo AND 63
	pgx = #px / 256
	pgy = #py / 256
	IF ptx < pgx THEN
		ptx = ptx + 2
		ptf = 0
	ELSE
		ptx = ptx - 2
		ptf = 1
	END IF
	IF pty < pgy THEN pty = pty + 1
	IF pty > pgy THEN pty = pty - 1

	ptp = ptf * 8			' facing: 0 right, 8 left
	ptp = ptp + P_PT
	ptop = 0
	IF ptmo < 24 THEN ptop = 1	' mouth open on the low part of the cycle
	IF ptop = 1 THEN ptp = ptp + 4
	SPRITE 21,pty,ptx,ptp,13

	IF pdead > 0 THEN RETURN
	ptdx = pgx - ptx
	IF pgx < ptx THEN ptdx = ptx - pgx
	IF ptdx > 11 THEN RETURN
	ptdy = pgy - pty
	IF pgy < pty THEN ptdy = pty - pgy
	IF ptdy > 11 THEN RETURN

	' THE ONLY WAY TO KILL IT: mouth open, lances level, and you facing it.
	IF ptop = 1 THEN
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
				sfn = SFX_PTKILL : GOSUB sfx_play
				GOSUB prt_score
				SPRITE 21,SPRHID,0,0,0
				RETURN
			END IF
		END IF
	END IF
	IF binv = 0 THEN pdead = 1
	RETURN

	' THE PIT BURNS. Two flame characters, out of step, re-uploaded from four
	' frames: 16 bytes of pattern instead of rewriting every lava cell.
lava_tick:
	lavt = 0
	lavf = lavf + 1
	lavf = lavf AND 3
	IF lavf = 0 THEN
		DEFINE CHAR LAVAA,1,flame0
		DEFINE CHAR LAVAB,1,flame2
	END IF
	IF lavf = 1 THEN
		DEFINE CHAR LAVAA,1,flame1
		DEFINE CHAR LAVAB,1,flame3
	END IF
	IF lavf = 2 THEN
		DEFINE CHAR LAVAA,1,flame2
		DEFINE CHAR LAVAB,1,flame0
	END IF
	IF lavf = 3 THEN
		DEFINE CHAR LAVAA,1,flame3
		DEFINE CHAR LAVAB,1,flame1
	END IF
	RETURN

sfx_step:
	sfn = SFX_STEP
	GOTO sfx_play
sfx_skid:
	sfn = SFX_SKID
	GOTO sfx_play

	' ------------------------------------------------------------ sound effects
	' EVERY EFFECT IS A ROW OF #sfxt (bank 1 on the TI): channel, start divisor,
	' per-pass change, volume, passes, volume drop per pass, and the effect to
	' start alongside it. A sweep is what makes these read as the arcade's
	' chirps, clanks and dives instead of beeps: the egg pickup climbs, a
	' defeated knight's note falls away, the flap is a burst of noise. The
	' divisor is SMALLER for a HIGHER note, so a rising chirp has a negative
	' step (stored as 65536 - n; the add wraps). Channel 3 is noise and its
	' "divisor" is the noise type. Every one is stopped by sfx_tick.
sfx_play:
	#sfi = sfn * 7
sfx_row:					' a label here: the TI must not read #sfi back from r0
	sfc = #sfxt(#sfi)
	#sfp = #sfxt(#sfi + 1)
	#sfd = #sfxt(#sfi + 2)
	sfv = #sfxt(#sfi + 3)
	sft = #sfxt(#sfi + 4)
	sfk = #sfxt(#sfi + 5)
	sfn = #sfxt(#sfi + 6)
	IF sfc = 0 THEN
		#sq0 = #sfp : #sw0 = #sfd : sv0 = sfv : sf0 = sft : sk0 = sfk
		SOUND 0,#sq0,sv0
	ELSEIF sfc = 1 THEN
		#sq1 = #sfp : #sw1 = #sfd : sv1 = sfv : sf1 = sft : sk1 = sfk
		SOUND 1,#sq1,sv1
	ELSEIF sfc = 2 THEN
		#sq2 = #sfp : #sw2 = #sfd : sv2 = sfv : sf2 = sft : sk2 = sfk
		SOUND 2,#sq2,sv2
	ELSE
		snz = #sfp : sv3 = sfv : sf3 = sft : sk3 = sfk
		SOUND 3,snz,sv3
	END IF
	IF sfn > 0 THEN GOTO sfx_play
	RETURN

	' ------------------------------------------------------------ sound tick
	' EVERY latched channel needs an explicit note-off or the tone sustains for
	' ever. Ticked once a pass, and after every WAIT in the loops that stop the
	' game (death, banners).
sfx_tick:
	IF sf0 > 0 THEN
		sf0 = sf0 - 1
		IF sf0 = 0 THEN
			SOUND 0,800,0
		ELSE
			#sq0 = #sq0 + #sw0
			IF sv0 > sk0 THEN sv0 = sv0 - sk0
			SOUND 0,#sq0,sv0
		END IF
	END IF
	IF sf1 > 0 THEN
		sf1 = sf1 - 1
		IF sf1 = 0 THEN
			SOUND 1,800,0
		ELSE
			#sq1 = #sq1 + #sw1
			IF sv1 > sk1 THEN sv1 = sv1 - sk1
			SOUND 1,#sq1,sv1
		END IF
	END IF
	IF sf2 > 0 THEN
		sf2 = sf2 - 1
		IF sf2 = 0 THEN
			SOUND 2,800,0
		ELSE
			#sq2 = #sq2 + #sw2
			IF sv2 > sk2 THEN sv2 = sv2 - sk2
			SOUND 2,#sq2,sv2
		END IF
	END IF
	IF sf3 > 0 THEN
		sf3 = sf3 - 1
		IF sf3 = 0 THEN
			SOUND 3,4,0
		ELSE
			IF sv3 > sk3 THEN sv3 = sv3 - sk3
			SOUND 3,,sv3		' volume only: rewriting the type restarts the noise
		END IF
	END IF
	RETURN

	' -------------------------------------------- DATA: bank 1 on the TI
#if TI994A
	BANK 1
#endif
	INCLUDE "art.bas"

	' Sound effect rows -- see sfx_play: channel, divisor, step, volume,
	' passes, volume drop, chained effect.
#sfxt:
	DATA 0,0,0,0,0,0,0
	DATA 3,6,0,13,3,4,0
	DATA 3,5,0,7,1,0,0
	DATA 0,70,3,9,3,2,0
	DATA 1,45,2,13,5,2,5
	DATA 3,4,0,14,3,4,0
	DATA 0,180,30,14,10,1,5
	DATA 1,340,65506,13,9,1,0
	DATA 2,500,65491,9,9,0,0
	DATA 1,150,20,11,8,1,0
	DATA 1,600,60,11,4,2,0
	DATA 3,5,0,12,2,4,12
	DATA 2,250,65516,10,6,1,0
	DATA 2,850,10,13,12,0,0
	DATA 1,500,65496,13,10,1,0
	DATA 2,70,3,13,20,0,0
	DATA 0,60,35,15,24,0,5
	DATA 2,400,65524,12,30,0,0
	DATA 1,200,65532,12,40,0,0
	DATA 0,500,0,9,3,0,0
	DATA 3,6,0,15,8,2,0

	INCLUDE "font.bas"

	' Character colours, EIGHT BYTES PER CHARACTER (one per scan line) -- supply
	' fewer and DEFINE COLOR reads whatever follows in ROM as colour data.
	' 7 chars x 8 = 56 bytes, an even run.
	' Mount colour per tier: red Bounder, grey Hunter, blue Shadow Lord. Four
	' bytes, an even run.
	' THE EGG WAVE'S TWELVE SPOTS: character column and row, each in the row
	' directly above a ledge's surface, clear of every pad (nothing materialises
	' on top of an egg) and of the banner rows 10-11. Twelve entries each: even.
teg_col:
	DATA BYTE 7,19,24,2,29,5,22,10,16,13,2,29
teg_row:
	DATA BYTE 20,20,20,20,20,13,12,7,7,15,6,6

tiercol:
	DATA BYTE 8,14,5,0

