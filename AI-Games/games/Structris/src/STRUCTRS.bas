	'
	' Structris -- TI-99/4A port (CVBasic, --ti994a)
	'
	' "Inverted Tetris": the machine builds the structure and throws pieces
	' at YOU. Climb, duck, and dodge along the skyline of a growing stack of
	' blocks; don't get buried.
	'
	' Original concept, piece catalog and targeting AI: Martin Haye, 2010
	' (Apple II / Applesoft BASIC), github.com/martinhaye/structris.
	' This TI-99 port reinterprets the renderer for a plain tile grid; see
	' DESIGN.md for what's ported verbatim vs. reinterpreted.
	'
	' 2026 UNHUMAN AND CLAUDE
	'

	CONST SHAFT_H = 16	' playable rows, 1 (ceiling) .. SHAFT_H (floor-adjacent)
	CONST MH = SHAFT_H - 3	' a column at/above this height is "topped out"
	CONST PSPD = 2		' player speed, pixels per frame per axis
	CONST MAXP = 6		' max pieces in flight at once (the stream)
	CONST PGAP = 11		' clear PIXELS between one piece's top and the
				' next piece's bottom. The original emits pieces 4
				' scan lines apart with 3 scan lines per cell row =
				' 1.33 rows; at 8 px/row that's ~11 px.

	DIM H(15)		' SETTLED column heights, index 1..W (0 unused)
	DIM HF(15)		' FORECAST heights: settled + booked in-flight
				' pieces. Targeting/shape selection uses HF, so a
				' later piece aims and fits correctly even while an
				' earlier piece is still falling beneath it (the
				' original books heights at emission time the same
				' way). Landing moves a booking from HF into H.

	DIM GSTART(16)		' shape table: group -> first variant index
	DIM GCOUNT(16)		' shape table: group -> variant count
	DIM VBL(27)		' shape table: variant -> left column delta
	DIM VB0(27)		' shape table: variant -> center column delta
	DIM VBR(27)		' shape table: variant -> right column delta
	DIM VCI(27)		' shape table: variant -> color index

	' Up to MAXP rigid pieces fall at once, all moving the same number of
	' pixels per frame, so their vertical separation never changes. Each
	' piece is ONE 2x-magnified 16x16 sprite (32x32 on screen = 4x4 cells;
	' every shape in the catalog fits a 3x3-cell box, baroff+barht <= 3),
	' composed into sprite def 1+p at spawn and converted to background
	' characters when it lands. Each piece p owns bar slots p*3 .. p*3+2;
	' its bars share ONE pixel fall position (ppy(p) = piece bottom) and
	' land together when it reaches the center column's booked surface.
	' Each side bar rides baroff rows higher -- exactly its column's
	' height advantage, which the shape table selected the piece to fit --
	' so every bar lands flush simultaneously.
	' TI-99 performance: the TMS9900 backend is slow enough that per-frame
	' multiplies/rescans here missed vblank (the game ran ~20% slow and
	' stuttered while ColecoVision was fine). Everything a hot loop needs
	' is therefore PRECOMPUTED at spawn/landing into the arrays below;
	' rect_test and the per-frame piece loop do compares/adds only.
	DIM barcol(18)		' bar -> column (0 = inactive)
	DIM barht(18)		' bar -> height (1-3)
	DIM baroff(18)		' bar -> rows ABOVE its piece's bottom (0-3)
	DIM bpx0(18)		' bar -> baroff*8 (pixel gap below the bar)
	DIM bpx1(18)		' bar -> (baroff+barht)*8 (pixel top offset)
	DIM pact(6)		' piece -> active flag
	DIM ppy(6)		' piece -> pixel Y of piece bottom (shaft top = 0)
	DIM ptpx(6)		' piece -> landing pixel of the piece bottom
	DIM pci(6)		' piece -> color index (1-7)
	DIM pgate(6)		' piece -> spawn-gate pixel: entry extent*8 + PGAP
	DIM psx(6)		' piece -> sprite X (left-neighbor column edge)
	DIM pfr(6)		' piece -> sprite frame arg, (1+p)*4
	DIM pcv(6)		' piece -> VDP sprite color (colv(pci) at spawn)
	DIM colv(8)		' color index -> VDP sprite color
	DIM sh1(15)		' column -> settled surface pixel, (SHAFT_H-H)*8

	DEF FN CPOS(r,c) = r * 32 + c

	'
	' One-time setup
	'
	' Default video mode (like every CVBasic game in this repo -- do NOT use
	' MODE 2: its half-configured bitmap trick renders blank/garbage on real
	' targets even though it compiles). Colors are per-character here, so the
	' block tiles are 8 consecutive chars 128-135, colored via DEFINE COLOR.
	'
	CLS
	BORDER 1

	' 2x sprite magnification: 16x16 defs render 32x32 on screen (4x4
	' cells), so one sprite holds any piece. Same setup as Astiroids.
	VDP(1) = $E3
	SPRITE FLICKER OFF

	DEFINE CHAR 128,1,filled_bitmap		' char 128 = piece color 1
	DEFINE CHAR 129,1,filled_bitmap		' char 129 = piece color 2
	DEFINE CHAR 130,1,filled_bitmap		' ...
	DEFINE CHAR 131,1,filled_bitmap
	DEFINE CHAR 132,1,filled_bitmap
	DEFINE CHAR 133,1,filled_bitmap
	DEFINE CHAR 134,1,filled_bitmap		' char 134 = piece color 7
	DEFINE CHAR 135,1,filled_bitmap		' char 135 = border/floor
	DEFINE CHAR 136,1,filled_bitmap		' char 136 = shaft-interior BLACK
	DEFINE COLOR 128,9,tile_colors

	DEFINE SPRITE 0,1,player_bitmap
	DEFINE SPRITE 7,4,expl_bitmap		' death explosion: defs 7-10 =
						' 4-frame expansion animation

	' Piece color index -> VDP sprite color (same hues as tile_colors).
	colv(1) = 8
	colv(2) = 3
	colv(3) = 10
	colv(4) = 7
	colv(5) = 5
	colv(6) = 6
	colv(7) = 14

	' Background music: CVBasic's interrupt-driven player in SIMPLE
	' mode (channels 0+1 only) with NO DRUMS, leaving SOUND 2 for the
	' gameplay effects and SOUND 3 (noise) for explosions/fireworks.
	PLAY SIMPLE NO DRUMS

	GOSUB setup_shapes
	stlv = 1

title_screen:
	' Hide the player AND any piece sprites left frozen by a game-over/
	' win screen, and restore the normal text colors (the win screen
	' repaints the ASCII set white-on-dark-green).
	FOR i = 0 TO MAXP
		SPRITE i,$D1,0,0,0
	NEXT i
	DEFINE COLOR 32,16,txt_white
	WAIT
	DEFINE COLOR 48,16,txt_white
	WAIT
	DEFINE COLOR 64,16,txt_white
	WAIT
	DEFINE COLOR 80,16,txt_white
	WAIT
	CLS
	' The last score lives in the top-left corner, digits only (00000
	' on the initial title; #score isn't reset until a game starts).
	' The session high score sits top-right, right-justified.
	PRINT AT CPOS(0,0),<5>#score
	PRINT AT CPOS(0,24),"HI ",<5>#hi
	PRINT AT CPOS(2,8),"S T R U C T R I S"
	PRINT AT CPOS(5,3),"THE MACHINE BUILDS THE"
	PRINT AT CPOS(6,3),"STRUCTURE.  YOU DODGE IT."
	PRINT AT CPOS(9,3),"JOYSTICK: MOVE ALONG THE"
	PRINT AT CPOS(10,3),"SKYLINE OF BLOCKS. UP TO"
	PRINT AT CPOS(11,3),"CLIMB, DOWN TO DUCK INTO"
	PRINT AT CPOS(12,3),"A GAP. DON'T GET BURIED."
	PRINT AT CPOS(15,3),"CLEAR ENOUGH ROWS TO REACH"
	PRINT AT CPOS(16,3),"THE NEXT LEVEL -- FASTER,"
	PRINT AT CPOS(17,3),"NARROWER, MEANER."
	PRINT AT CPOS(20,4),"FIRE TO BEGIN THE TORTURE"
	PRINT AT CPOS(23,2),"BY MARTIN HAYE, TI-99 PORT"
	code_st = 0
	lastk = 15
title_rel:
	WAIT
	IF cont1.button THEN GOTO title_rel
title_wait:
	WAIT
	' Secret setup: type 8,3,8 (CONT1.KEY: digit = value, 15 = none;
	' same convention as Astiroids). Debounced on key-down. Nested
	' single-comparison IFs only -- see the DESIGN.md header.
	k = cont1.key
	IF k <> 15 THEN
		IF k <> lastk THEN
			IF k = 8 THEN
				IF code_st = 2 THEN GOTO setup838
				code_st = 1
			ELSEIF k = 3 THEN
				IF code_st = 1 THEN
					code_st = 2
				ELSE
					code_st = 0
				END IF
			ELSE
				code_st = 0
			END IF
		END IF
	END IF
	lastk = k
	IF cont1.button = 0 THEN GOTO title_wait

new_game:
	LV = stlv
	RD = 0
	#score = 0
	frsh = 1
	GOSUB init_level

main_loop:
	WAIT
	GOSUB handle_input
	GOSUB advance_pieces
	IF gameend = 1 THEN GOTO game_over
	IF gameend = 2 THEN GOTO win_screen
	' Player: a 4x2-px bar (2x1 def px, magnified) at free pixel position
	' (PX,PY) -- it moves as smoothly as the falling pieces and, being
	' only 2 px tall, can squeeze through the ~11-px gaps between them.
	SPRITE 0,PY - 1,PX,0,15
	' Sound effects (all on channel 2 -- the music owns 0+1) stay on
	' for a few frames, then this counter silences them (a SOUND ...,,0
	' in the same frame would be inaudible).
	IF snd2 > 0 THEN
		snd2 = snd2 - 1
		IF snd2 = 0 THEN SOUND 2,,0
	END IF
	GOTO main_loop

	'
	' ---- Level setup ----
	'
init_level:
	W = 15 - LV
	IF W < 5 THEN W = 5
	ML = (32 - W) / 2
	' Rows required: 7 at level 1, +2 per level (25 at level 10).
	RG = 5 + LV * 2
	' Full-screen clear only for a FRESH game (title text lingers in
	' the message rows). Between levels the wall animation has already
	' left the screen in exactly the right state -- borders, floor and
	' a black interior at the NEW positions, sidebars untouched -- so
	' skipping the clear avoids a full-screen flicker. The interior
	' fill uses the dedicated black tile (136), not space, so the
	' playfield background stays black under the win/game-over text
	' recolors.
	IF frsh THEN
		FOR r = 0 TO 23
			FOR cx = 0 TO 31
				VPOKE $1800 + r * 32 + cx,32
			NEXT cx
		NEXT r
	END IF
	frsh = 0
	FOR r = 1 TO SHAFT_H
		FOR cx = 1 TO W
			VPOKE $1800 + (r - 1) * 32 + ML + cx,136
		NEXT cx
	NEXT r
	FOR cc = 1 TO W
		H(cc) = 0
		HF(cc) = 0
		sh1(cc) = SHAFT_H * 8
	NEXT cc
	FOR p = 0 TO MAXP - 1
		pact(p) = 0
		SPRITE 1 + p,$D1,0,0,0
	NEXT p
	FOR i = 0 TO MAXP * 3 - 1
		barcol(i) = 0
	NEXT i
	nact = 0
	pnew = 0
	spawn_timer = 20
	' Fall speed: 8 px (one row) every fpr frames, spread 1 px at a time
	' by an accumulator in advance_pieces (LV 1: fpr = 8 -> 1 px/frame).
	fpr = 8 - LV / 2
	IF fpr < 2 THEN fpr = 2
	acc = 0
	#lf = FRAME
	move_cd = 0
	gameend = 0
	' Player position is free pixels: PX = bar left edge, PY = bar top.
	' Start centered on the floor (bar rows 126-127, flush on the floor).
	PX = (ML + W / 2) * 8 + 2
	PY = SHAFT_H * 8 - 2
	GOSUB draw_borders
	' Sidebar labels (values are refreshed by draw_hud). The HIGH
	' block mirrors SCORE on the RIGHT side of the shaft (right-
	' aligned, inset one column from the screen edge); #hi only
	' changes at a game over/win, so its value is printed here once.
	PRINT AT CPOS(1,1),"SCORE"
	PRINT AT CPOS(1,27),"HIGH"
	PRINT AT CPOS(2,26),<5>#hi
	PRINT AT CPOS(4,1),"LEVEL"
	PRINT AT CPOS(7,1),"CLEAR"
	GOSUB draw_hud
	' Gameplay music (re)starts from the top each level.
	PLAY game_tune
	RETURN

draw_borders:
	' Shaft row r renders at screen row r-1: the ceiling is the screen
	' top, so a piece sprite slides in from above the display ($E0-$FF
	' Y band) instead of popping out from under a text row.
	FOR r = 1 TO SHAFT_H
		VPOKE $1800 + (r - 1) * 32 + ML,135
		VPOKE $1800 + (r - 1) * 32 + ML + W + 1,135
	NEXT r
	FOR cx = ML TO ML + W + 1
		VPOKE $1800 + SHAFT_H * 32 + cx,135
	NEXT cx
	RETURN

draw_hud:
	' HUD is a LEFT SIDEBAR (the shaft is centered, so columns 0-8 are
	' free even at the level-1 width): score in the top-left corner,
	' LEVEL and CLEAR blocks below it. Labels are printed once by
	' init_level; this refreshes only the values.
	PRINT AT CPOS(2,1),<5>#score
	PRINT AT CPOS(5,2),<2>LV
	PRINT AT CPOS(8,1),<2>RD,"/",<2>RG
	RETURN

	'
	' ---- Shape table ----
	'
setup_shapes:
	RESTORE shape_data
	idx = 0
	FOR g = 0 TO 15
		READ BYTE cnt
		GSTART(g) = idx
		GCOUNT(g) = cnt
		FOR k = 1 TO cnt
			READ BYTE VBL(idx)
			READ BYTE VB0(idx)
			READ BYTE VBR(idx)
			READ BYTE VCI(idx)
			idx = idx + 1
		NEXT k
	NEXT g
	RETURN

	'
	' ---- Player input ----
	'
handle_input:
	' Smooth pixel movement, PSPD px per frame per axis; horizontal and
	' vertical are independent so the player can slide along a surface.
	' A move happens only if the destination rect is free (settled stack
	' and falling pieces block, PIXEL-exact -- the 2-px-tall bar fits
	' through the ~11-px gaps between pieces in the stream).
	moved = 0
	IF cont1.left THEN
		qx = PX - PSPD
		IF qx < (ML + 1) * 8 THEN qx = (ML + 1) * 8
		IF qx <> PX THEN
			qy = PY
			GOSUB rect_test
			IF qf = 0 THEN
				PX = qx
				moved = 1
			END IF
		END IF
	ELSEIF cont1.right THEN
		qx = PX + PSPD
		IF qx > (ML + W) * 8 + 4 THEN qx = (ML + W) * 8 + 4
		IF qx <> PX THEN
			qy = PY
			GOSUB rect_test
			IF qf = 0 THEN
				PX = qx
				moved = 1
			END IF
		END IF
	END IF
	IF cont1.up THEN
		IF PY < PSPD THEN
			qy = 0
		ELSE
			qy = PY - PSPD
		END IF
		IF qy <> PY THEN
			qx = PX
			GOSUB rect_test
			IF qf = 0 THEN
				PY = qy
				moved = 1
			END IF
		END IF
	ELSEIF cont1.down THEN
		qy = PY + PSPD
		IF qy > SHAFT_H * 8 - 2 THEN qy = SHAFT_H * 8 - 2
		IF qy <> PY THEN
			qx = PX
			GOSUB rect_test
			IF qf = 0 THEN
				PY = qy
				moved = 1
			END IF
		END IF
	END IF
	' Move blip, throttled (continuous movement would retrigger the
	' sound every frame and turn it into a buzz).
	IF move_cd > 0 THEN move_cd = move_cd - 1
	IF moved THEN
		IF move_cd = 0 THEN
			' Channel 2: the only tone channel free of the music.
			SOUND 2,224,10
			snd2 = 2
			move_cd = 8
		END IF
	END IF
	RETURN

	'
	' ---- Pixel-rect occupancy for the 4x2 player bar at (qx,qy) ----
	' Sets qf = 1 if the rect hits the settled stack or any falling bar,
	' and rbb = the deepest bottom pixel of any overlapping falling bar
	' (0 = none) -- check_player uses rbb to push the player down.
	'
rect_test:
	' HOT PATH (up to 4 calls/frame): compares, adds and precomputed
	' array reads only -- no multiplies (bpx0/bpx1 were computed at
	' spawn, sh1 at landing/rowclear). Recomputing these here is what
	' made the TI-99 miss vblank.
	qf = 0
	rbb = 0
	qc1 = qx / 8 - ML
	qc2 = (qx + 3) / 8 - ML
	IF qy + 1 >= sh1(qc1) THEN qf = 1
	IF qc2 <> qc1 THEN
		IF qy + 1 >= sh1(qc2) THEN qf = 1
	END IF
	' A falling bar (off,ht) of piece p occupies shaft pixels
	' [ppy-bpx1, ppy-bpx0). Overlap with the player's two pixel rows
	' [qy, qy+1]. Unsigned-safe: each subtract is guarded by the IF
	' just above it.
	j = 0
	FOR p = 0 TO MAXP - 1
		IF pact(p) <> 0 THEN
			py1 = ppy(p)
			FOR b = 0 TO 2
				hit = 0
				IF barcol(j) = qc1 THEN hit = 1
				IF barcol(j) = qc2 THEN hit = 1
				IF hit THEN
					k = bpx0(j)
					IF py1 > k THEN
						bb = py1 - k
						k = bpx1(j)
						IF py1 > k THEN
							bt = py1 - k
						ELSE
							bt = 0
						END IF
						IF qy < bb THEN
							IF qy + 2 > bt THEN
								qf = 1
								IF bb > rbb THEN rbb = bb
							END IF
						END IF
					END IF
				END IF
				j = j + 1
			NEXT b
		ELSE
			j = j + 3
		END IF
	NEXT p
	RETURN

	'
	' ---- Piece targeting + shape pick (ported from Structris.asb) ----
	'
	' Spawns into a free piece slot. All height reads here use HF (the
	' forecast), so a piece spawned while others are mid-flight aims at
	' and fits the surface as it WILL be, and the booking is applied to
	' HF immediately -- the original updates its H() at emission time
	' for exactly this reason.
	'
spawn_piece:
	s = 255
	FOR p = 0 TO MAXP - 1
		IF pact(p) = 0 THEN s = p
	NEXT p
	IF s = 255 THEN RETURN

	' Target the column under the player bar's center pixel.
	x = (PX + 2) / 8 - ML
	IF x < 1 THEN x = 1
	IF x > W THEN x = W
	xo = x
	found = 0
	IF HF(x) < MH THEN found = 1
	' Nested single-condition IFs throughout: the CVBasic 0.9.2 TI-99
	' backend miscompiles comparison-AND-comparison (see DESIGN.md).
	IF found = 0 THEN
		FOR d = 1 TO W
			IF found = 0 THEN
				t = xo + d
				IF t <= W THEN
					IF HF(t) < MH THEN
						x = t
						found = 1
					END IF
				END IF
			END IF
			IF found = 0 THEN
				IF xo > d THEN
					t = xo - d
					IF HF(t) < MH THEN
						x = t
						found = 1
					END IF
				END IF
			END IF
		NEXT d
	END IF
	IF found = 0 THEN RETURN

	h0 = HF(x)
	IF x > 1 THEN
		hl = HF(x - 1) - h0
		IF hl > 3 THEN hl = 3
	ELSE
		hl = 3
	END IF
	IF x < W THEN
		hr = HF(x + 1) - h0
		IF hr > 3 THEN hr = 3
	ELSE
		hr = 3
	END IF
	g = hl * 4 + hr
	pick = GSTART(g) + RANDOM(GCOUNT(g))
	pbl = VBL(pick)
	pb0 = VB0(pick)
	pbr = VBR(pick)

	' A bar only exists on a side whose true height difference is 0-3
	' (larger/negative differences were clamped to 3, and every hl/hr=3
	' table entry has a 0 delta on that side) -- so hl/hr IS the side
	' bar's ride-height, and the whole rigid piece lands flush.
	j = s * 3
	n2 = 0
	e = 0
	IF x > 1 THEN
		IF pbl > 0 THEN
			barcol(j + n2) = x - 1
			barht(j + n2) = pbl
			baroff(j + n2) = hl
			bpx0(j + n2) = hl * 8
			bpx1(j + n2) = (hl + pbl) * 8
			IF hl + pbl > e THEN e = hl + pbl
			HF(x - 1) = HF(x - 1) + pbl
			IF HF(x - 1) > SHAFT_H THEN HF(x - 1) = SHAFT_H
			n2 = n2 + 1
		END IF
	END IF
	IF pb0 > 0 THEN
		barcol(j + n2) = x
		barht(j + n2) = pb0
		baroff(j + n2) = 0
		bpx0(j + n2) = 0
		bpx1(j + n2) = pb0 * 8
		IF pb0 > e THEN e = pb0
		n2 = n2 + 1
	END IF
	IF x < W THEN
		IF pbr > 0 THEN
			barcol(j + n2) = x + 1
			barht(j + n2) = pbr
			baroff(j + n2) = hr
			bpx0(j + n2) = hr * 8
			bpx1(j + n2) = (hr + pbr) * 8
			IF hr + pbr > e THEN e = hr + pbr
			HF(x + 1) = HF(x + 1) + pbr
			IF HF(x + 1) > SHAFT_H THEN HF(x + 1) = SHAFT_H
			n2 = n2 + 1
		END IF
	END IF
	WHILE n2 < 3
		barcol(j + n2) = 0
		n2 = n2 + 1
	WEND
	ppy(s) = 0
	ptpx(s) = (SHAFT_H - HF(x)) * 8
	HF(x) = HF(x) + pb0
	IF HF(x) > SHAFT_H THEN HF(x) = SHAFT_H
	pci(s) = VCI(pick)
	pgate(s) = e * 8 + PGAP
	pfr(s) = (1 + s) * 4
	pcv(s) = colv(VCI(pick))
	pact(s) = 1
	nact = nact + 1
	pnew = s
	' Compose the whole piece into sprite def 1+s (32 bytes at
	' $3800 + (1+s)*32). In def space one cell = 4 def px (2x magnified
	' to 8 screen px): columns x-1/x/x+1 sit at def-x 0-3/4-7/8-11 (left
	' byte = $F0/$0F nibbles, right byte = $F0), art bottom-aligned so a
	' bar (off,ht) covers def rows 16-(off+ht)*4 .. 15-off*4. Every
	' shape fits (baroff+barht <= 3 across the whole catalog).
	c0f = 0
	c2f = 0
	IF x > 1 THEN
		IF pbl > 0 THEN
			c0f = 1
			c0t = 16 - (hl + pbl) * 4
			c0b = 15 - hl * 4
		END IF
	END IF
	IF x < W THEN
		IF pbr > 0 THEN
			c2f = 1
			c2t = 16 - (hr + pbr) * 4
			c2b = 15 - hr * 4
		END IF
	END IF
	FOR k = 0 TO 15
		b1 = 0
		b2 = 0
		IF c0f THEN
			IF k >= c0t THEN
				IF k <= c0b THEN b1 = $F0
			END IF
		END IF
		IF pb0 > 0 THEN
			IF k >= 16 - pb0 * 4 THEN b1 = b1 OR $0F
		END IF
		IF c2f THEN
			IF k >= c2t THEN
				IF k <= c2b THEN b2 = $F0
			END IF
		END IF
		VPOKE $3800 + (1 + s) * 32 + k,b1
		VPOKE $3800 + (1 + s) * 32 + 16 + k,b2
	NEXT k
	' Sprite X: the def's left cell is column x-1, so the sprite sits
	' one column left of the target (transparent there when x = 1).
	psx(s) = (ML + x - 1) * 8
	RETURN

	'
	' ---- Per-frame piece spawn / fall / land ----
	'
advance_pieces:
	landed = 0
	' TIME-based pacing: heavy frames (spawn compose, landing paint,
	' row-clear shift) can make the TMS9900 miss a vblank; scaling the
	' fall by the elapsed FRAME count turns a missed frame into a 1-px
	' catch-up step instead of a slowdown, so the TI-99 runs the same
	' real-world speed as ColecoVision. Clamped so a long pause (level
	' banner) can't teleport pieces.
	#fd = FRAME - #lf
	#lf = FRAME
	IF #fd > 4 THEN #fd = 4
	' Spawning: the shaft carries a continuous STREAM. The first piece of
	' a lull waits out spawn_timer; after that a new piece spawns as soon
	' as the newest one has fully entered plus PGAP clear pixels -- so up
	' to MAXP pieces fall at once with a constant navigation gap between
	' them, like the original's back-to-back emission. nact is maintained
	' by spawn_piece (+1) and landing (-1), never rescanned.
	IF nact = 0 THEN
		IF spawn_timer > 0 THEN
			spawn_timer = spawn_timer - 1
		ELSE
			GOSUB spawn_piece
			spawn_timer = 12
		END IF
	ELSE
		IF nact < MAXP THEN
			IF ppy(pnew) >= pgate(pnew) THEN
				GOSUB spawn_piece
			END IF
		END IF
	END IF

	IF nact > 0 THEN
		' Smooth fall: 8 px (one row) every fpr frames, spread 1 px at a
		' time by an accumulator -- the same average speed as the old
		' one-row-per-fpr-frames step. All pieces advance by the same dy,
		' so their separation never changes. Each rigid piece lands as a
		' unit when its bottom pixel reaches its booked surface, and only
		' THEN touches the tile grid (falling pieces are pure sprites).
		acc = acc + 8 * #fd
		dy = 0
		WHILE acc >= fpr
			dy = dy + 1
			acc = acc - fpr
		WEND
		FOR p = 0 TO MAXP - 1
			IF pact(p) <> 0 THEN
				ppy(p) = ppy(p) + dy
				IF ppy(p) >= ptpx(p) THEN
					FOR b = 0 TO 2
						j = p * 3 + b
						IF barcol(j) <> 0 THEN
							cc = barcol(j)
							' Settle: paint only the newly-added cells so
							' settled cells keep their piece colors. Loop
							' guarded: CVBasic FOR checks at the BOTTOM,
							' so an empty range would still run once.
							hold = H(cc)
							H(cc) = H(cc) + barht(j)
							IF H(cc) > SHAFT_H THEN H(cc) = SHAFT_H
							sh1(cc) = (SHAFT_H - H(cc)) * 8
							IF H(cc) > hold THEN
								FOR r = SHAFT_H - H(cc) + 1 TO SHAFT_H - hold
									VPOKE $1800 + (r - 1) * 32 + ML + cc,128 + pci(p) - 1
								NEXT r
							END IF
							barcol(j) = 0
						END IF
					NEXT b
					pact(p) = 0
					nact = nact - 1
					SPRITE 1 + p,$D1,0,0,0
					landed = 1
					' Scoring: 1 point per landed piece.
					#score = #score + 1
				ELSE
					' Sprite top = piece bottom - 32 (bottom-aligned art
					' in a 32px box); the VDP Y arg is one less, and the
					' 8-bit wrap puts small ppy in the $E0-$FF "above the
					' screen top" band for a smooth entry.
					SPRITE 1 + p,ppy(p) - 33,psx(p),pfr(p),pcv(p)
				END IF
			END IF
		NEXT p
		IF landed THEN
			SOUND 2,600,12
			snd2 = 4
			GOSUB draw_hud
		END IF
	END IF

	GOSUB check_player
	' Row clears can only happen when a piece has just landed -- don't
	' rescan every column every frame (TI-99 frame budget).
	IF gameend = 0 THEN
		IF landed THEN GOSUB check_rowclear
	END IF
	RETURN

	'
	' ---- Push-or-die collision ----
	'
check_player:
	' A piece descending into the player forces them DOWN, pixel-exact:
	' the player's top snaps to the deepest overlapping bar's bottom. If
	' the pushed bar no longer fits -- past the floor, into the settled
	' stack, or into another piece -- they are SMASHED: game over. This
	' is the original's rule (Structris.asb lines 125-135: cell filled ->
	' below filled means death, else CY = CY + 1), but because the player
	' is only 2 px tall, riding down inside a stream gap is survivable
	' until the gap closes -- being confined leaves room to slip out
	' sideways.
	qx = PX
	qy = PY
	GOSUB rect_test
	IF rbb = 0 THEN
		' Not under a falling bar -- but if the rect overlaps SETTLED
		' cells, a fast piece (dy >= 2 at level 2+) just landed ON the
		' player: it converted to tiles in the same step that would
		' have pushed them. Buried in the stack is death, not a safe
		' hole (this was the "trapped forever, wins for free" bug).
		IF qf <> 0 THEN gameend = 1
		RETURN
	END IF
	IF rbb > SHAFT_H * 8 - 2 THEN
		gameend = 1
		RETURN
	END IF
	PY = rbb
	qx = PX
	qy = PY
	GOSUB rect_test
	IF qf <> 0 THEN gameend = 1
	RETURN

	'
	' ---- Row clear / leveling ----
	'
check_rowclear:
	m = H(1)
	FOR cc = 2 TO W
		IF H(cc) < m THEN m = H(cc)
	NEXT cc
	IF m > 0 THEN
		FOR cc = 1 TO W
			H(cc) = H(cc) - m
			HF(cc) = HF(cc) - m
			sh1(cc) = (SHAFT_H - H(cc)) * 8
		NEXT cc
		' Completed rows fall away: shift each column's OCCUPIED band
		' down m rows on screen (VPEEK preserves each cell's per-piece
		' color), then blank the m vacated rows above it. Only rows that
		' hold cells move -- shifting the full shaft height was a
		' visible multi-frame hitch on the TI-99. Loops guarded: CVBasic
		' FOR checks its limit at the BOTTOM.
		FOR cc = 1 TO W
			IF H(cc) > 0 THEN
				FOR r = SHAFT_H TO SHAFT_H - H(cc) + 1 STEP -1
					code = VPEEK($1800 + (r - m - 1) * 32 + ML + cc)
					VPOKE $1800 + (r - 1) * 32 + ML + cc,code
				NEXT r
			END IF
			k = SHAFT_H - H(cc)
			FOR r = k - m + 1 TO k
				VPOKE $1800 + (r - 1) * 32 + ML + cc,136
			NEXT r
		NEXT cc
		' Every piece still falling now has m more rows to travel.
		k = m * 8
		FOR p = 0 TO MAXP - 1
			IF pact(p) <> 0 THEN ptpx(p) = ptpx(p) + k
		NEXT p
		RD = RD + m
		' Scoring: line-clear bonus by SIMULTANEOUS rows -- 10 for 1,
		' 50 for 2, 100 for 3. m can never exceed 3: clears run after
		' every landing, so m is capped by what the LOWEST column can
		' gain in one frame -- one bar, height <= 3. (A second piece's
		' bar in the same column always lands >= PGAP px of travel
		' later -- the stream gap is constant and >= 11 px > max dy --
		' so same-column same-frame landings are impossible. The >= is
		' just belt-and-braces.)
		IF m = 1 THEN #score = #score + 10
		IF m = 2 THEN #score = #score + 50
		IF m >= 3 THEN #score = #score + 100
		GOSUB draw_hud
		SOUND 2,300,12
		snd2 = 8
		IF RD >= RG THEN GOSUB level_up
	END IF
	RETURN

level_up:
	' Stop the tune. NOTE: once PLAY SIMPLE is selected, the interrupt
	' player rewrites channels 0+1 EVERY frame forever (even after
	' PLAY OFF) -- direct SOUND 0/1 writes get stomped into a stuck
	' tone. All effect sounds therefore live on channel 2 (and noise
	' on 3), which SIMPLE mode leaves alone.
	PLAY OFF
	PRINT AT CPOS(19,10),"LEVEL UP!"
	FOR i = 1 TO 30
		WAIT
	NEXT i
	LV = LV + 1
	IF LV > 10 THEN
		gameend = 2
		RETURN
	END IF
	GOSUB wall_anim
	PRINT AT CPOS(19,10),"         "
	RD = 0
	GOSUB init_level
	RETURN

	'
	' ---- Level-up wall animation + ditty ----
	' The cleared shaft's walls CLOSE to the center with a rising run
	' of notes, then OPEN back out to the next level's (narrower,
	' re-centered) positions with a second rising run and a two-note
	' ta-da -- the walls visibly move in for the new level. Sprites
	' are hidden first; init_level redraws the fresh level over the
	' animation's end state, so the hand-off is seamless.
	'
wall_anim:
	FOR i = 0 TO MAXP
		SPRITE i,$D1,0,0,0
	NEXT i
	FOR r = 1 TO SHAFT_H
		FOR cx = 1 TO W
			VPOKE $1800 + (r - 1) * 32 + ML + cx,136
		NEXT cx
	NEXT r
	' Close: both walls march inward until they meet in the middle.
	' The FLOOR tracks the walls -- its end cells are wiped as each
	' wall passes, so the floor is never wider than the shaft and
	' nothing snaps when init_level redraws the new level. Each step
	' plays a short ARTICULATED note on channel 2 (silenced mid-step,
	' or the run smears into one long beep).
	dmax = W / 2
	FOR d = 1 TO dmax
		WAIT
		WAIT
		SOUND 2,,0
		WAIT
		WAIT
		vch = 135
		vc = ML + d
		GOSUB vcol
		vc = ML + W + 1 - d
		GOSUB vcol
		vch = 136
		vc = ML + d - 1
		GOSUB vcol
		VPOKE $1800 + SHAFT_H * 32 + ML + d - 1,32
		vc = ML + W + 2 - d
		GOSUB vcol
		VPOKE $1800 + SHAFT_H * 32 + ML + W + 2 - d,32
		#fq = 400 + d * 80
		SOUND 2,#fq,9
	NEXT d
	WAIT
	WAIT
	SOUND 2,,0
	FOR i = 1 TO 8
		WAIT
	NEXT i
	' Open: the walls march back OUT to the next level's border
	' columns (width W-1, re-centered), continuing the rising run.
	lc = ML + dmax
	rc = ML + W + 1 - dmax
	ml2 = (32 - W + 1) / 2
	mr2 = ml2 + W
	cnt2 = 0
	moved2 = 1
	WHILE moved2
		moved2 = 0
		WAIT
		WAIT
		SOUND 2,,0
		WAIT
		IF lc > ml2 THEN
			vch = 135
			vc = lc - 1
			GOSUB vcol
			VPOKE $1800 + SHAFT_H * 32 + lc - 1,135
			vch = 136
			vc = lc
			GOSUB vcol
			VPOKE $1800 + SHAFT_H * 32 + lc,135
			lc = lc - 1
			moved2 = 1
		END IF
		IF rc < mr2 THEN
			vch = 135
			vc = rc + 1
			GOSUB vcol
			VPOKE $1800 + SHAFT_H * 32 + rc + 1,135
			vch = 136
			vc = rc
			GOSUB vcol
			VPOKE $1800 + SHAFT_H * 32 + rc,135
			rc = rc + 1
			moved2 = 1
		END IF
		IF moved2 THEN
			cnt2 = cnt2 + 1
			#fq = 600 + cnt2 * 70
			SOUND 2,#fq,9
		END IF
	WEND
	' Ta-da! (channel 2 only -- see the note at level_up)
	SOUND 2,659,10
	FOR i = 1 TO 8
		WAIT
	NEXT i
	SOUND 2,880,9
	FOR i = 1 TO 16
		WAIT
	NEXT i
	SOUND 2,,0
	RETURN

	' Paint char vch down the full shaft height at absolute column vc.
vcol:
	FOR r = 1 TO SHAFT_H
		VPOKE $1800 + (r - 1) * 32 + vc,vch
	NEXT r
	RETURN

	'
	' ---- Terminal screens ----
	'
game_over:
	PLAY OFF
	IF #score > #hi THEN #hi = #score
	' The smashed player stays on screen, BLINKING at the spot where
	' they were buried (don't hide the sprite -- it marks the death).
	' Defeat theme, the mirror of the win banner's green: the ASCII set
	' goes white-on-DARK-RED, so the HUD/message area (and every empty
	' cell) turns red while the final board keeps its piece colors. The
	' title screen restores the normal colors.
	SOUND 0,,0
	SOUND 1,,0
	SOUND 2,,0
	' EXPLOSION first: the player vanishes in a noise blast as four
	' debris sprites (slots 7-10, shared def 7, 2x-magnified shrapnel)
	' fly outward diagonally, flashing white -> yellow -> red -> dark
	' red. Only THEN does the screen turn red. Sprites 1-6 (frozen
	' pieces) are untouched; the blinking buried marker resumes after.
	SPRITE 0,$D1,0,0,0
	' Anchor the 32x32 debris boxes so their CENTERS start on the
	' player (box center = +16,+16 from the sprite origin).
	ex0 = PX - 14
	IF PY >= 15 THEN
		ey0 = PY - 15
	ELSE
		ey0 = 0
	END IF
	SOUND 3,5,13
	' 40 frames. The EXPANSION is the 4-frame def animation (defs
	' 7-10, one every 10 frames: tight nucleus -> small burst -> mid
	' spread -> full shrapnel); the four sprites themselves barely
	' drift (1 px every 5 frames, 8 px total) so the cloud stays in
	' place and reads as ONE cohesive explosion.
	FOR i = 1 TO 40
		WAIT
		k = i / 5
		ef = 28 + ((i - 1) / 10) * 4
		IF i < 10 THEN
			ec = 15
		ELSEIF i < 20 THEN
			ec = 11
		ELSEIF i < 30 THEN
			ec = 8
		ELSE
			ec = 6
		END IF
		IF ey0 >= k THEN
			SPRITE 7,ey0 - k - 1,ex0 + k,ef,ec
			SPRITE 8,ey0 - k - 1,ex0 - k,ef,ec
		ELSE
			SPRITE 7,$D1,0,0,0
			SPRITE 8,$D1,0,0,0
		END IF
		SPRITE 9,ey0 + k - 1,ex0 + k,ef,ec
		SPRITE 10,ey0 + k - 1,ex0 - k,ef,ec
		IF i = 14 THEN SOUND 3,6,11
		IF i = 28 THEN SOUND 3,7,8
	NEXT i
	SOUND 3,,0
	SPRITE 7,$D1,0,0,0
	SPRITE 8,$D1,0,0,0
	SPRITE 9,$D1,0,0,0
	SPRITE 10,$D1,0,0,0
	DEFINE COLOR 32,16,txt_red
	WAIT
	DEFINE COLOR 48,16,txt_red
	WAIT
	DEFINE COLOR 64,16,txt_red
	WAIT
	DEFINE COLOR 80,16,txt_red
	WAIT
	PRINT AT CPOS(18,13),"OOPS!"
	PRINT AT CPOS(20,7),"BURIED AT LEVEL ",LV
	PRINT AT CPOS(22,11),"PRESS FIRE"
	blink = 0
	' Audible descending "you died" tone (channel 2 -- see the note at
	' level_up; sound must persist across frames, an immediate
	' SOUND ...,,0 in the same frame is silent).
	FOR i = 1 TO 30
		SOUND 2,400 + i * 20,13
		WAIT
		GOSUB blink_player
	NEXT i
	SOUND 2,,0
	' Require fire to be released first, so a press held from gameplay
	' doesn't instantly restart.
game_over_rel:
	WAIT
	GOSUB blink_player
	IF cont1.button THEN GOTO game_over_rel
game_over_wait:
	WAIT
	GOSUB blink_player
	IF cont1.button = 0 THEN GOTO game_over_wait
	GOTO title_screen

	' ~half-second blink: visible for 16 frames, hidden for 16. Single
	' comparison only (never <cmp> AND <cmp> -- see the DESIGN.md header).
blink_player:
	blink = blink + 1
	IF (blink AND 16) = 0 THEN
		SPRITE 0,PY - 1,PX,0,15
	ELSE
		SPRITE 0,$D1,0,0,0
	END IF
	RETURN

win_screen:
	PLAY OFF
	IF #score > #hi THEN #hi = #score
	' Victory: first FIREWORKS over the right side of the (still black)
	' screen -- five rockets, each a rising white spark that pops into
	' the 4-frame expansion animation (reusing the death-explosion defs
	' 7-10) in its own color, with a rising launch whistle and a noise
	' pop. Only then the banner: repaint the ASCII set white-on-DARK-
	' GREEN and clear the board (the old version printed over leftover
	' playfield tiles and read as garbage). The title screen restores
	' the normal text colors before anything else is printed. The
	' player's sprite stays visible, steady -- they survived.
	SOUND 0,,0
	SOUND 1,,0
	SOUND 2,,0
	' Rockets alternate RIGHT and LEFT of the shaft. The 32-px burst
	' boxes (plus their +/-3 px sprite offsets) are clamped clear of
	' the shaft borders -- fireworks may overlap the sidebar/HUD but
	' NEVER the game area (bounds computed from this level's ML/W).
	rx = (ML + W + 2) * 8 + 3
	lx = ML * 8 - 35
	FOR fw = 1 TO 6
		IF (fw AND 1) THEN
			bx = rx + RANDOM(221 - rx)
		ELSE
			bx = 3 + RANDOM(lx - 2)
		END IF
		' Burst height: at least 60% up the screen (by <= 77) and high
		' enough that the whole 32-px burst box keeps an 8-px margin
		' from the screen top (box top = by-4, so by >= 12).
		by = 12 + RANDOM(66)
		IF fw = 1 THEN ec = 11
		IF fw = 2 THEN ec = 3
		IF fw = 3 THEN ec = 9
		IF fw = 4 THEN ec = 5
		IF fw = 5 THEN ec = 15
		IF fw = 6 THEN ec = 7
		' Launch: the spark climbs from below the floor line to the
		' burst point with a rising whistle (channel 2 -- see the note
		' at level_up).
		k = 150
		WHILE k > by
			WAIT
			SPRITE 7,k - 1,bx,28,15
			#fq = k
			#fq = 900 - #fq * 4
			SOUND 2,#fq,9
			k = k - 3
		WEND
		SOUND 2,,0
		SOUND 3,5,12
		' Pop: same 4-frame expansion as the death explosion, four
		' tightly-overlapped sprites so the burst reads as one shell.
		FOR i = 1 TO 28
			WAIT
			ef = 28 + ((i - 1) / 7) * 4
			SPRITE 7,by - 4,bx + 3,ef,ec
			SPRITE 8,by - 4,bx - 3,ef,ec
			SPRITE 9,by + 2,bx + 3,ef,ec
			SPRITE 10,by + 2,bx - 3,ef,ec
			IF i = 20 THEN SOUND 3,6,7
		NEXT i
		SOUND 3,,0
		SPRITE 7,$D1,0,0,0
		SPRITE 8,$D1,0,0,0
		SPRITE 9,$D1,0,0,0
		SPRITE 10,$D1,0,0,0
	NEXT fw
	FOR p = 0 TO MAXP - 1
		SPRITE 1 + p,$D1,0,0,0
	NEXT p
	DEFINE COLOR 32,16,txt_green
	WAIT
	DEFINE COLOR 48,16,txt_green
	WAIT
	DEFINE COLOR 64,16,txt_green
	WAIT
	DEFINE COLOR 80,16,txt_green
	WAIT
	CLS
	PRINT AT CPOS(9,8),"CONGRATULATIONS!"
	PRINT AT CPOS(12,3),"YOU SURVIVED ALL 10 LEVELS."
	PRINT AT CPOS(14,5),"THE MACHINE GIVES UP."
	PRINT AT CPOS(16,10),"SCORE ",<5>#score
	PRINT AT CPOS(19,11),"PRESS FIRE"
win_rel:
	WAIT
	IF cont1.button THEN GOTO win_rel
win_wait:
	WAIT
	IF cont1.button = 0 THEN GOTO win_wait
	GOTO title_screen

	'
	' ---- 838 setup: pick the starting level (typed 8,3,8 on the title) ----
	' Room here for more options later; today a single digit picks the
	' level and starts the game immediately.
	'
setup838:
	CLS
	PRINT AT CPOS(4,11),"838 SETUP"
	PRINT AT CPOS(9,3),"PRESS 1-9 FOR START LEVEL"
	PRINT AT CPOS(11,3),"OR 0 TO START AT LEVEL 10"
	PRINT AT CPOS(15,3),"THE GAME BEGINS AT ONCE"
	' Drain: the 8 that opened this screen may still be held -- require
	' all keys released before reading the level digit.
setup_drain:
	WAIT
	IF cont1.key <> 15 THEN GOTO setup_drain
setup_wait:
	WAIT
	k = cont1.key
	IF k = 15 THEN GOTO setup_wait
	IF k > 9 THEN GOTO setup_wait
	stlv = k
	IF stlv = 0 THEN stlv = 10
	GOTO new_game

	'
	' ---- Graphics data ----
	'
filled_bitmap:
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"

	' 16x16 sprite (CVBasic sprites are always 32 bytes); the player is
	' a 2x1-def-px bar in the top-left corner -- 4x2 screen px under the
	' 2x magnification -- the rest is transparent.
player_bitmap:
	BITMAP "XX.............."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"

	' Death-explosion debris: FOUR 16x16 defs (2x-magnified), a real
	' expansion animation played in sequence -- the particles start as
	' a tight nucleus and spread further apart in each frame. The four
	' sprites barely move; the animation IS the explosion.
	' Frame 1 (def 7): solid nucleus.
expl_bitmap:
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XX........"
	BITMAP ".....XXXX......."
	BITMAP ".....XXXX......."
	BITMAP "......XX........"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	' Frame 2 (def 8): small burst, particles just separating.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......X.X......."
	BITMAP ".....X...X......"
	BITMAP "....X..X..X....."
	BITMAP "......X.X......."
	BITMAP ".....X...X......"
	BITMAP "....X..X..X....."
	BITMAP "......X.X......."
	BITMAP ".....X.X........"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	' Frame 3 (def 9): mid spread.
	BITMAP "................"
	BITMAP "................"
	BITMAP "....X.....X....."
	BITMAP "..X....X........"
	BITMAP ".....X......X..."
	BITMAP "...X....X......."
	BITMAP ".X........X....."
	BITMAP "......X......X.."
	BITMAP "...X.....X......"
	BITMAP ".X....X.....X..."
	BITMAP ".....X....X....."
	BITMAP "..X......X......"
	BITMAP "....X..X....X..."
	BITMAP "..X.....X......."
	BITMAP "................"
	BITMAP "................"
	' Frame 4 (def 10): full shrapnel field.
	BITMAP "X......X........"
	BITMAP "....X.......X..."
	BITMAP ".X........X....."
	BITMAP "......X........X"
	BITMAP "...X.......X...."
	BITMAP "X.....X........."
	BITMAP ".........X....X."
	BITMAP "..X.....X......."
	BITMAP ".......X....X..."
	BITMAP "X...X..........X"
	BITMAP "......X..X......"
	BITMAP "...X.......X...."
	BITMAP ".X.....X......X."
	BITMAP "....X......X...."
	BITMAP "X........X......"
	BITMAP "......X......X.."

	' Per-row colors (fg*16+bg) for chars 128-136: the 7 piece colors
	' (red, lt green, yellow, cyan, blue, dk red, gray), the white
	' border/floor tile, then the black-on-black shaft-interior tile
	' (char 136: empty playfield cells use it instead of space, so the
	' shaft background stays BLACK when the win/game-over themes recolor
	' the ASCII set). Solid tiles, so all 8 rows of each are the same.
	' Text (ASCII 32-95) color tables, applied 16 chars per DEFINE COLOR
	' (the repo's proven runtime-recolor size; 4 calls with WAITs cover
	' the set). Every row byte is the same, so ONE 128-byte table serves
	' all four 16-char chunks. txt_white = white on black (gameplay/
	' title); txt_green = white on dark green (the win banner).
txt_white:
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
txt_red:
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
txt_green:
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC

tile_colors:
	DATA BYTE $81,$81,$81,$81,$81,$81,$81,$81
	DATA BYTE $31,$31,$31,$31,$31,$31,$31,$31
	DATA BYTE $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
	DATA BYTE $71,$71,$71,$71,$71,$71,$71,$71
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51
	DATA BYTE $61,$61,$61,$61,$61,$61,$61,$61
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $11,$11,$11,$11,$11,$11,$11,$11

	'
	' Background tune: an ORIGINAL 16-bar loop in A minor -- a brisk
	' Slavic-folk-dance feel in the spirit of (but not copying) the
	' Tetris tradition. Two channels (PLAY SIMPLE): piano melody (W)
	' over a pumping root-fifth bass (Z, sounds two octaves down).
	' Each MUSIC row is an eighth note at 10 ticks (~150 BPM), 8 rows
	' per bar. Form: A phrase, answer, B lift, resolve -- then REPEAT.
	'
game_tune:
	DATA BYTE 10
	MUSIC A4W,A5Z
	MUSIC S,S
	MUSIC C5,E5
	MUSIC S,S
	MUSIC E5,A5
	MUSIC S,S
	MUSIC D5,E5
	MUSIC C5,S
	MUSIC B4,G5
	MUSIC S,S
	MUSIC D5,D5
	MUSIC S,S
	MUSIC G4,G5
	MUSIC S,S
	MUSIC B4,D5
	MUSIC S,S
	MUSIC A4,A5
	MUSIC S,S
	MUSIC C5,E5
	MUSIC S,S
	MUSIC E5,A5
	MUSIC S,S
	MUSIC G5,E5
	MUSIC E5,S
	MUSIC D5,E5
	MUSIC C5,S
	MUSIC B4,B5
	MUSIC S,S
	MUSIC A4,A5
	MUSIC S,S
	MUSIC S,E5
	MUSIC S,S
	MUSIC C5,C5
	MUSIC S,S
	MUSIC E5,G5
	MUSIC S,S
	MUSIC A5,C5
	MUSIC S,S
	MUSIC G5,G5
	MUSIC E5,S
	MUSIC F5,F5
	MUSIC S,S
	MUSIC E5,C6
	MUSIC S,S
	MUSIC D5,F5
	MUSIC S,S
	MUSIC C5,C6
	MUSIC S,S
	MUSIC B4,G5
	MUSIC S,S
	MUSIC D5,D5
	MUSIC S,S
	MUSIC F5,G5
	MUSIC S,S
	MUSIC E5,D5
	MUSIC D5,S
	MUSIC C5,A5
	MUSIC B4,S
	MUSIC A4,E5
	MUSIC S,S
	MUSIC A4,A5
	MUSIC S,S
	MUSIC S,E5
	MUSIC S,S
	MUSIC E5,C5
	MUSIC S,S
	MUSIC E5,G5
	MUSIC D5,S
	MUSIC C5,C5
	MUSIC S,S
	MUSIC C5,G5
	MUSIC B4,S
	MUSIC A4,A5
	MUSIC S,S
	MUSIC A4,E5
	MUSIC S,S
	MUSIC B4,A5
	MUSIC S,S
	MUSIC C5,E5
	MUSIC D5,S
	MUSIC E5,C5
	MUSIC S,S
	MUSIC E5,G5
	MUSIC D5,S
	MUSIC C5,C5
	MUSIC S,S
	MUSIC E5,G5
	MUSIC S,S
	MUSIC A5,A5
	MUSIC S,S
	MUSIC G5,E5
	MUSIC E5,S
	MUSIC D5,A5
	MUSIC C5,S
	MUSIC B4,E5
	MUSIC S,S
	MUSIC C5,A5
	MUSIC S,S
	MUSIC A4,E5
	MUSIC S,S
	MUSIC E5,A5
	MUSIC S,S
	MUSIC C5,E5
	MUSIC S,S
	MUSIC D5,G5
	MUSIC S,S
	MUSIC B4,D5
	MUSIC S,S
	MUSIC G5,G5
	MUSIC S,S
	MUSIC D5,D5
	MUSIC S,S
	MUSIC C5,A5
	MUSIC D5,S
	MUSIC E5,E5
	MUSIC C5,S
	MUSIC A4,A5
	MUSIC B4,S
	MUSIC C5,E5
	MUSIC A4,S
	MUSIC A4,A5
	MUSIC S,S
	MUSIC S,E5
	MUSIC S,S
	MUSIC -,A5
	MUSIC -,S
	MUSIC -,-
	MUSIC -,-
	MUSIC REPEAT

	'
	' Shape catalog: for each of the 16 (HL,HR) buckets (index = HL*4+HR),
	' a variant count followed by that many (BL,B0,BR,CI) tuples. Ported
	' from Structris.asb lines 1200-1645 (see DESIGN.md sec. 5).
	'
shape_data:
	DATA BYTE 4, 1,1,2,1, 2,1,1,2, 1,2,1,6, 1,1,1,7
	DATA BYTE 1, 1,2,1,4
	DATA BYTE 1, 0,3,1,2
	DATA BYTE 3, 3,1,0,1, 1,3,0,2, 2,2,0,3
	DATA BYTE 1, 1,2,1,5
	DATA BYTE 1, 1,2,1,6
	DATA BYTE 2, 2,2,0,4, 1,3,0,6
	DATA BYTE 2, 2,2,0,4, 1,3,0,6
	DATA BYTE 1, 1,3,0,1
	DATA BYTE 1, 1,3,0,1
	DATA BYTE 2, 1,3,0,1, 0,3,1,2
	DATA BYTE 1, 1,3,0,1
	DATA BYTE 3, 0,3,1,1, 0,1,3,2, 0,2,2,3
	DATA BYTE 2, 0,2,2,5, 0,3,1,6
	DATA BYTE 1, 0,3,1,2
	DATA BYTE 1, 0,3,0,7
