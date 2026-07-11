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

	CONST SHAFT_H = 16	' playable rows at LEVEL 1. The game lives on a
				' STAGE (checkered platform, per the original)
				' that rises half a character per level -- tiles
				' can't hold half-row stacks, so the playable
				' floor (variable sh) drops a full row every
				' second level, and on even levels the visible
				' stage top is a half-checker tile. mh = sh - 3
				' is the per-level "topped out" threshold.
	CONST PSPD = 2		' player speed, pixels per frame per axis
	CONST MAXP = 6		' max pieces in flight at once (the stream)
	CONST PGAP = 11		' clear PIXELS between one piece's top and the
				' next piece's bottom. The original emits pieces 4
				' scan lines apart with 3 scan lines per cell row =
				' 1.33 rows; at 8 px/row that's ~11 px.

	DIM H(16)		' SETTLED column heights, index 1..W (0 unused; W<=15)
	DIM HF(16)		' FORECAST heights: settled + booked in-flight
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
	DIM sh1(16)		' column -> settled surface pixel, (sh-H)*8 (index 1..W, W<=15)

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

	' Chars 128-136 are ALL the same solid 8x8 tile (piece colors 1-7 =
	' 128-134, border/floor = 135, shaft-interior black = 136); their
	' colors come from DEFINE COLOR 128,11,tile_colors below. One call
	' defines all nine from the existing solid_ff table (reused by the
	' pair tiles 139-194) -- cheaper than nine separate DEFINE CHARs, and
	' filled_bitmap is no longer needed.
	DEFINE CHAR 128,9,solid_ff
	DEFINE CHAR 137,2,stage_bitmap		' 137 = stage checker, 138 = half
	DEFINE COLOR 128,11,tile_colors
	' HALF-SHIFTED STACK tiles for even levels (the stage has risen an
	' extra half character, so every settled cell straddles two char
	' rows). Chars 139-194: solid "pair" tiles, top half color A (0 =
	' empty/black, 1-7 = piece colors) over bottom half color B (1-7);
	' code = 139 + A*7 + (B-1), so the char code itself encodes both
	' cell colors (decoded with VPEEK -- no RAM mirror). Chars 195-201:
	' stage-seam tiles, top half color 1-7 over the checker's top half.
	DEFINE CHAR 139,16,solid_ff
	DEFINE CHAR 155,16,solid_ff
	DEFINE CHAR 171,16,solid_ff
	DEFINE CHAR 187,8,solid_ff
	DEFINE CHAR 195,7,bnd_pat
	' pcc1..pcc4 are one contiguous 56-entry table, so one call colours all of
	' chars 139-194 (was four calls).
	DEFINE COLOR 139,56,pcc1
	DEFINE COLOR 195,7,bnd_colors
	' Wall-seam tile (202): white top half over the checker's bottom
	' half. On even levels the floor sits half a character low, so the
	' white walls end 4 px into the stage's top row -- this tile fills
	' that half so the wall meets the checker with no black gap.
	DEFINE CHAR 202,1,bnd_pat
	DEFINE COLOR 202,1,wallseam_col

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
	colv(7) = 13

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
	' The 838 starting-level choice lasts for ONE game only: every return
	' to the title resets it, so the next FIRE starts at level 1 unless
	' 838 is entered again.
	stlv = 1
	GOSUB hide_sprites
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
	PRINT AT CPOS(4,2),"MARTIN HAYE, UNHUMAN, CLAUDE"
	PRINT AT CPOS(7,3),"THE MACHINE BUILDS THE"
	PRINT AT CPOS(8,3),"STRUCTURE.  YOU DODGE IT."
	PRINT AT CPOS(11,3),"JOYSTICK: MOVE ALONG THE"
	PRINT AT CPOS(12,3),"SKYLINE OF BLOCKS. UP TO"
	PRINT AT CPOS(13,3),"CLIMB, DOWN TO DUCK INTO"
	PRINT AT CPOS(14,3),"A GAP. DON'T GET BURIED."
	PRINT AT CPOS(17,3),"CLEAR ENOUGH ROWS TO REACH"
	PRINT AT CPOS(18,3),"THE NEXT LEVEL -- SHORTER,"
	PRINT AT CPOS(19,3),"NARROWER, MEANER."
	PRINT AT CPOS(22,4),"FIRE TO BEGIN THE TORTURE"
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
	' Ready? 3-2-1 countdown with beeps, then the tune starts and the
	' piece stream begins on the next main-loop pass.
	GOSUB countdown
	GOSUB start_music

main_loop:
	WAIT
	' TIME-based pacing shared by the player and the falling pieces: heavy
	' frames (spawn compose, landing paint, row-clear shift) can make the
	' TMS9900 miss a vblank; #fd = elapsed FRAME count turns a missed frame
	' into a catch-up step instead of a slowdown, so both the cursor and the
	' pieces run the same real-world speed as ColecoVision (where #fd is
	' always 1). Clamped so a long pause (level banner) can't teleport.
	#fd = FRAME - #lf
	#lf = FRAME
	IF #fd > 4 THEN #fd = 4
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
	' Row-clear crunch tail: switch noise type mid-decay for a rougher
	' texture, then silence.
	IF snd3 > 0 THEN
		snd3 = snd3 - 1
		IF snd3 = 3 THEN SOUND 3,6,9
		IF snd3 = 0 THEN SOUND 3,,0
	END IF
	GOTO main_loop

	'
	' ---- Level geometry (pure function of LV) ----
	' Shaft width/margin, playable height, top-out threshold, even-level
	' half-shift, row goal. Called by init_level AND by the level-up wall
	' animation, which needs the NEW level's geometry to draw the raised
	' stage as the walls open.
	'
calc_geom:
	' Shaft interior width: 15 columns at level 1, one narrower per level,
	' down to 6 at level 10 (never below 6). ML centers it on the screen.
	W = 16 - LV
	IF W < 6 THEN W = 6
	ML = (32 - W) / 2
	' The stage rises half a character per level: the playable height sh
	' loses a full row on each EVEN level (16 at level 1, 15 at 2-3, 14
	' at 4-5, ... 11 at 10); even levels also drop the visible stage top
	' a half character (hoff = 4 px), so landed cells render as split
	' "pair" tiles straddling two char rows and the floor/player clamps
	' shift down 4 px.
	sh = SHAFT_H - LV / 2
	mh = sh - 3
	hoff = 0
	IF (LV AND 1) = 0 THEN hoff = 4
	' Rows required: 7 at level 1, +2 per level (25 at level 10).
	RG = 5 + LV * 2
	RETURN

	'
	' ---- Level setup ----
	'
init_level:
	GOSUB calc_geom
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
	GOSUB fill_interior
	FOR cc = 1 TO W
		H(cc) = 0
		HF(cc) = 0
		sh1(cc) = sh * 8 + hoff
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
	' Fall speed is CONSTANT across all levels (8 px = one row every fpr=8
	' frames, spread 1 px at a time by the accumulator in advance_pieces =
	' 1 px/frame). Speed progression is DELIBERATELY disabled: the game
	' gets harder only through the rising row requirement (RG) and the
	' narrowing shaft -- ramping the fall speed made high levels literally
	' impossible (pieces dropping faster than the player can escape).
	fpr = 8
	acc = 0
	#lf = FRAME
	move_cd = 0
	gameend = 0
	' Player position is free pixels: PX = bar left edge, PY = bar top.
	' Start the 4-px bar centered between the walls (midpoint of its X
	' travel range), one cell (8 px) up off the floor.
	PX = (2 * ML + W + 1) * 4 + 2
	PY = sh * 8 + hoff - 10
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
	' Music is started by the caller (start_music, per-level tune) AFTER
	' the game-start countdown -- not here -- so the 3-2-1 beeps play
	' over silence and the tune kicks in exactly when gameplay begins.
	RETURN

	' ---- Get-ready countdown (game start only) ----
	' A "3", "2", "1" over the middle of the SHAFT (the game window, not
	' the whole screen), one second each with a rising beep; when the "1"
	' clears, gameplay + music begin. The player bar is shown so its start
	' position reads before pieces fall. cdc = the cell holding the tower's
	' pixel center (walls at ML and ML+W+1) -- (2*ML+W+2)*4 / 8 -- so the
	' digit sits dead-centre between the walls at any shaft width instead
	' of a fixed screen column (which drifted a column left on some levels).
	' cdr centers it vertically in the shaft.
countdown:
	cdc = ML + (W + 2) / 2
	cdr = sh / 2
	SPRITE 0,PY - 1,PX,0,15
	PRINT AT CPOS(cdr,cdc),"3"
	cdf = 400
	GOSUB cd_beat
	PRINT AT CPOS(cdr,cdc),"2"
	cdf = 500
	GOSUB cd_beat
	PRINT AT CPOS(cdr,cdc),"1"
	cdf = 640
	GOSUB cd_beat
	' Clear the digit back to the black interior tile (char 136, not a
	' space) so the shaft stays black under the win/lose recolors.
	VPOKE $1800 + CPOS(cdr,cdc),136
	' Reset the fall pacer's frame stamp so the first gameplay pass sees a
	' 1-frame delta (not the whole 3-second countdown, which would clamp
	' to a single 4-px catch-up jump).
	#lf = FRAME
	RETURN

	' One countdown second: a short beep (channel 2 -- the music player
	' owns channels 0+1) then silence for the rest of ~60 frames.
cd_beat:
	SOUND 2,cdf,13
	FOR cdi = 1 TO 10
		WAIT
	NEXT cdi
	SOUND 2,,0
	FOR cdi = 1 TO 50
		WAIT
	NEXT cdi
	RETURN

	' ---- Per-level background tune ----
	' Each level has its own tune (tune1..tune10); PLAY needs a constant
	' label, so select with a single-comparison IF chain (called once per
	' level, never per frame).
start_music:
	IF LV = 1 THEN PLAY tune1
	IF LV = 2 THEN PLAY tune2
	IF LV = 3 THEN PLAY tune3
	IF LV = 4 THEN PLAY tune4
	IF LV = 5 THEN PLAY tune5
	IF LV = 6 THEN PLAY tune6
	IF LV = 7 THEN PLAY tune7
	IF LV = 8 THEN PLAY tune8
	IF LV = 9 THEN PLAY tune9
	IF LV = 10 THEN PLAY tune10
	RETURN

draw_borders:
	' Shaft row r renders at screen row r-1: the ceiling is the screen
	' top, so a piece sprite slides in from above the display ($E0-$FF
	' Y band) instead of popping out from under a text row.
	FOR r = 1 TO sh
		VPOKE $1800 + (r - 1) * 32 + ML,135
		VPOKE $1800 + (r - 1) * 32 + ML + W + 1,135
	NEXT r
	GOSUB draw_stage
	RETURN

	' THE STAGE: the checkered MOUNTAIN everything stands on. It flares
	' OUTWARD one column per side on EVERY row as it descends -- narrow at
	' the top (one lip column beyond each wall) down to a wide base at the
	' floor (row 17), a full triangular mountain. As the shaft shortens
	' each level (sh rises) the mountain GROWS TALLER (and its base wider),
	' filling the space below instead of floating up as a thin pedestal
	' with black beneath it. The level-up wing-erase and reveal span are
	' driven by the same per-row flare (17 - sh cols beyond the lip at the
	' base), so they track this width at any level. On even levels the top
	' row sits a half character low: it uses the half-checker tile (138),
	' and the two wall-base columns use the wall-seam tile (202, white top
	' over checker) so the white walls meet the checker with no black gap.
draw_stage:
	' Draw the flared mountain column-by-column via the per-column `scol`
	' (which the wall animation already uses) instead of duplicating the flare
	' logic here -- scol(vc) draws column vc from its flared top row down to the
	' floor, so looping it over the whole width paints the identical mountain.
	FOR vc = 1 TO 30
		GOSUB scol
	NEXT vc
	RETURN

draw_hud:
	' HUD is a LEFT SIDEBAR: labels/values sit in columns 1-5, and the
	' shaft is centered (left wall at ML = 8 at the widest level-1 width),
	' so the sidebar never collides with it. Score in the top-left corner,
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
	' Player step scales with #fd so the cursor keeps ColecoVision real-time
	' speed when the TMS9900 drops a frame -- but the delta is capped at 2
	' (step <= 4 px) so a heavy-load frame never teleports the bar a whole
	' cell past a piece. Single destination rect_test as before -- no
	' per-pixel loop, so no added per-frame load.
	pfd = #fd
	IF pfd > 2 THEN pfd = 2
	pmv = PSPD * pfd
	IF cont1.left THEN
		qx = PX - pmv
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
		qx = PX + pmv
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
		IF PY < pmv THEN
			qy = 0
		ELSE
			qy = PY - pmv
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
		qy = PY + pmv
		IF qy > sh * 8 + hoff - 2 THEN qy = sh * 8 + hoff - 2
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
	IF HF(x) < mh THEN found = 1
	' Nested single-condition IFs throughout: the CVBasic 0.9.2 TI-99
	' backend miscompiles comparison-AND-comparison (see DESIGN.md).
	IF found = 0 THEN
		FOR d = 1 TO W
			IF found = 0 THEN
				t = xo + d
				IF t <= W THEN
					IF HF(t) < mh THEN
						x = t
						found = 1
					END IF
				END IF
			END IF
			IF found = 0 THEN
				IF xo > d THEN
					t = xo - d
					IF HF(t) < mh THEN
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
		' A negative diff (neighbor column is LOWER than the target) has no
		' flush-resting side bar; clamp to 3 -- the hl=3 shape group carries
		' a 0 delta on that side, i.e. no left bar. WITHOUT this clamp g goes
		' negative and GSTART(g)/GCOUNT(g)/VCI(pick) read out of bounds, which
		' yields garbage shapes ("bars fill the screen") and VCI=0 -> char 127
		' bowtie corruption. (CVBasic vars are unsigned; the OOB result also
		' shifts with unrelated code, which is why it looked like a memory bug.)
		IF hl < 0 THEN hl = 3
	ELSE
		hl = 3
	END IF
	IF x < W THEN
		hr = HF(x + 1) - h0
		IF hr > 3 THEN hr = 3
		IF hr < 0 THEN hr = 3
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
			IF HF(x - 1) > sh THEN HF(x - 1) = sh
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
			IF HF(x + 1) > sh THEN HF(x + 1) = sh
			n2 = n2 + 1
		END IF
	END IF
	WHILE n2 < 3
		barcol(j + n2) = 0
		n2 = n2 + 1
	WEND
	ppy(s) = 0
	ptpx(s) = (sh - HF(x)) * 8 + hoff
	HF(x) = HF(x) + pb0
	IF HF(x) > sh THEN HF(x) = sh
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
	nland = 0
	' #fd (elapsed-frame count) is computed once per pass in main_loop and
	' shared by both the player (handle_input) and the fall below, so they
	' scale identically when the TMS9900 misses a vblank.
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
							' mc/pcp hoist the column address base and the
							' piece color index (both reused many times below).
							mc = ML + cc
							pcp = pci(p)
							hold = H(cc)
							H(cc) = H(cc) + barht(j)
							IF H(cc) > sh THEN H(cc) = sh
							sh1(cc) = (sh - H(cc)) * 8 + hoff
							IF H(cc) > hold THEN
								IF hoff THEN
									' Half-shifted level: cells straddle two
									' char rows. Paint the upper seam (empty
									' over color), the interior pairs, and
									' the lower seam (color over the old top
									' decoded from its char, or the stage).
									r1 = sh - H(cc) + 1
									r2 = sh - hold
									VPOKE $1800 + (r1 - 1) * 32 + mc,139 + pcp - 1
									IF r2 > r1 THEN
										FOR r = r1 TO r2 - 1
											VPOKE $1800 + r * 32 + mc,139 + pcp * 7 + pcp - 1
										NEXT r
									END IF
									IF r2 = sh THEN
										VPOKE $1800 + sh * 32 + mc,195 + pcp - 1
									ELSE
										c2 = VPEEK($1800 + r2 * 32 + mc)
										b2 = c2 - 139
										b2 = b2 - (b2 / 7) * 7 + 1
										VPOKE $1800 + r2 * 32 + mc,139 + pcp * 7 + b2 - 1
									END IF
								ELSE
									FOR r = sh - H(cc) + 1 TO sh - hold
										VPOKE $1800 + (r - 1) * 32 + mc,128 + pcp - 1
									NEXT r
								END IF
							END IF
							barcol(j) = 0
						END IF
					NEXT b
					pact(p) = 0
					nact = nact - 1
					SPRITE 1 + p,$D1,0,0,0
					landed = 1
					' Scoring: 1 point per landed piece -- but DEFERRED (see
					' below): only banked once check_player confirms the
					' player survived the pass, so a piece that crushes them
					' against the base as it lands awards nothing.
					nland = nland + 1
				ELSE
					' Sprite top = piece bottom - 32 (bottom-aligned art
					' in a 32px box); the VDP Y arg is one less, and the
					' 8-bit wrap puts small ppy in the $E0-$FF "above the
					' screen top" band for a smooth entry.
					SPRITE 1 + p,ppy(p) - 33,psx(p),pfr(p),pcv(p)
				END IF
			END IF
		NEXT p
	END IF

	GOSUB check_player
	' A piece only truly LANDS -- banking its point, its blip, and a
	' row-clear scan -- once check_player confirms the player SURVIVED the
	' pass. If a landing piece crushed them against the base, gameend is now
	' set and the piece awards nothing and makes no sound (it "never landed"
	' from the player's point of view). Row clears can only happen when a
	' piece just landed, so they stay gated on that.
	IF gameend = 0 THEN
		IF landed THEN
			#score = #score + nland
			SOUND 2,600,12
			snd2 = 4
			GOSUB draw_hud
			GOSUB check_rowclear
		END IF
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
	IF rbb > sh * 8 + hoff - 2 THEN
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
			sh1(cc) = (sh - H(cc)) * 8 + hoff
		NEXT cc
		' Completed rows fall away: shift each column's OCCUPIED band
		' down m rows on screen (VPEEK preserves each cell's per-piece
		' color), then blank the m vacated rows above it. Only rows that
		' hold cells move -- shifting the full shaft height was a
		' visible multi-frame hitch on the TI-99. Loops guarded: CVBasic
		' FOR checks its limit at the BOTTOM.
		FOR cc = 1 TO W
			mc = ML + cc
			IF hoff THEN
				' Half-shifted level: char row j shows (cell j over
				' cell j+1), so a plain char copy shifts everything
				' EXCEPT the stage-seam row, which is rebuilt from the
				' new bottom cell's color (decoded from the char that
				' lands there -- read BEFORE the copy clobbers it).
				c2 = VPEEK($1800 + (sh - m) * 32 + mc)
				IF H(cc) > 0 THEN
					FOR r = sh - 1 TO sh - H(cc) STEP -1
						code = VPEEK($1800 + (r - m) * 32 + mc)
						VPOKE $1800 + r * 32 + mc,code
					NEXT r
				END IF
				k = sh - H(cc)
				FOR r = k - m TO k - 1
					VPOKE $1800 + r * 32 + mc,136
				NEXT r
				IF c2 = 136 THEN
					VPOKE $1800 + sh * 32 + mc,138
				ELSE
					b2 = (c2 - 139) / 7
					IF b2 = 0 THEN
						VPOKE $1800 + sh * 32 + mc,138
					ELSE
						VPOKE $1800 + sh * 32 + mc,195 + b2 - 1
					END IF
				END IF
			ELSE
				IF H(cc) > 0 THEN
					FOR r = sh TO sh - H(cc) + 1 STEP -1
						code = VPEEK($1800 + (r - m - 1) * 32 + mc)
						VPOKE $1800 + (r - 1) * 32 + mc,code
					NEXT r
				END IF
				k = sh - H(cc)
				FOR r = k - m + 1 TO k
					VPOKE $1800 + (r - 1) * 32 + mc,136
				NEXT r
			END IF
		NEXT cc
		' Every piece still falling now has m more rows to travel.
		k = m * 8
		FOR p = 0 TO MAXP - 1
			IF pact(p) <> 0 THEN ptpx(p) = ptpx(p) + k
		NEXT p
		RD = RD + m
		' CRUNCH: rows collapsing = a low thump (ch 2) under a white-
		' noise burst (ch 3, free during gameplay with NO DRUMS). The
		' snd3 countdown roughens the tail by switching noise type
		' mid-decay.
		SOUND 2,140,13
		snd2 = 6
		SOUND 3,5,13
		snd3 = 7
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
	PRINT AT CPOS(19,12),"LEVEL UP!"
	' The landing thud / row-clear crunch counters don't tick inside
	' this sequence (main_loop is paused) -- give them their natural
	' ring, then hard-silence channels 2+3 before the wall animation.
	FOR i = 1 TO 8
		WAIT
	NEXT i
	SOUND 2,,0
	SOUND 3,,0
	snd2 = 0
	snd3 = 0
	FOR i = 1 TO 22
		WAIT
	NEXT i
	LV = LV + 1
	IF LV > 10 THEN
		gameend = 2
		RETURN
	END IF
	GOSUB flush_level
	GOSUB wall_anim
	PRINT AT CPOS(19,12),"         "
	RD = 0
	GOSUB init_level
	' New level, new tune (no countdown between levels -- the wall
	' animation already gives the "get ready" beat).
	GOSUB start_music
	RETURN

	'
	' ---- Level-up wall animation + ditty ----
	' The finished level's walls CLOSE to the center with a rising run of
	' notes (old geometry); then the play band is wiped, calc_geom
	' switches to the NEW level, and the walls OPEN back out to the new
	' (narrower, re-centered) positions with a second rising run and a
	' two-note ta-da. As the walls open, the NEW raised stage is drawn
	' column by column behind the growing gap -- so the new layer eases
	' in instead of snapping when init_level repaints it afterward.
	'
wall_anim:
	GOSUB hide_sprites
	' Conditional compilation: build-ti.sh passes -DTI994A=1 so TI994A is a
	' defined non-zero constant on the TI build; build-coleco.sh passes no -D
	' so TI994A is undefined (0) there. Requires the forked cvbasic at
	' unhuman/CVBasic (it implements #if/#else/#endif); the stock nanochess
	' v0.9.2 does NOT -- it errors here, treating #if as a #-prefixed variable.
	' Clear the old flared mountain WINGS (the angled cells OUTSIDE the
	' walls) up front, before the collapse: the close phase only tracks the
	' lip as the walls march in, so without this the wings sat there as
	' leftover artifacts during the collapse. The mountain flares one column
	' per row, so the wings form a triangle (widest at the floor) -- walk
	' li/ri outward per row exactly like draw_stage. Stage rows only
	' (sh..17), and the triangle is narrow at the top, so the sidebar HUD
	' is untouched.
	li = ML - 2
	ri = ML + W + 3
	FOR r = sh TO 17
		lo = li
		IF lo < 1 THEN lo = 1
		FOR cx = lo TO ML - 2
			VPOKE $1800 + r * 32 + cx,32
		NEXT cx
		ro = ri
		IF ro > 30 THEN ro = 30
		FOR cx = ML + W + 3 TO ro
			VPOKE $1800 + r * 32 + cx,32
		NEXT cx
		li = li - 1
		ri = ri + 1
	NEXT r
	' --- CLOSE (old geometry) ---
	vsh = sh
	GOSUB fill_interior
	' Both walls march inward until they meet in the middle; the stage
	' lip is erased as each wall passes. Each step plays a short
	' ARTICULATED note on channel 2 (silenced mid-step, or the run
	' smears into one long beep).
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
		' Vacated columns are OUTSIDE the shaft now: erase with SPACE
		' (32), not the black interior tile -- 136 stays black under the
		' win/game-over recolors and left visible artifacts there.
		vch = 32
		vc = ML + d - 1
		GOSUB vcol
		vc = ML + d - 2
		GOSUB scol0
		vc = ML + W + 2 - d
		GOSUB vcol
		vc = ML + W + 3 - d
		GOSUB scol0
		#fq = 400 + d * 80
		SOUND 2,#fq,9
	NEXT d
	WAIT
	WAIT
	SOUND 2,,0
	FOR i = 1 TO 8
		WAIT
	NEXT i

	' Wipe the old play band to space, then switch to the NEW level's
	' geometry. The open phase redraws stage + walls from scratch, so
	' nothing outside the new band lingers as an artifact on a later
	' win/lose screen. Two loops: the tower column band (rows 0..17), and
	' the old stage's flared wings (stage rows only, so the HUD in the top
	' rows is never touched by the wider erase).
	oML = ML
	oW = W
	osh = sh
	FOR r = 0 TO 17
		FOR cx = oML - 1 TO oML + oW + 2
			VPOKE $1800 + r * 32 + cx,32
		NEXT cx
	NEXT r
	li = oML - 2
	ri = oML + oW + 3
	FOR r = osh TO 17
		lo = li
		IF lo < 1 THEN lo = 1
		FOR cx = lo TO oML - 2
			VPOKE $1800 + r * 32 + cx,32
		NEXT cx
		ro = ri
		IF ro > 30 THEN ro = 30
		FOR cx = oML + oW + 3 TO ro
			VPOKE $1800 + r * 32 + cx,32
		NEXT cx
		li = li - 1
		ri = ri + 1
	NEXT r
	GOSUB calc_geom
	vsh = sh
	' --- OPEN (new geometry): walls march OUT to the new border columns;
	' the new mountain is revealed column by column behind the growing span.
	' The span reaches wdep + 1 columns beyond each wall (wdep = 17 - sh is
	' the mountain's flare depth at the floor) so the full triangular wings
	' reveal with the walls: scol draws the flared stage under every column
	' (and no-ops past the flare tip), walls sit at lc/rc, black interior
	' fills between, and the lips/wings are left clear above the stage. ---
	wdep = 17 - sh + 1
	lc = oML + oW / 2
	rc = oML + oW + 1 - oW / 2
	ml2 = ML
	mr2 = ML + W + 1
	cnt2 = 0
	moved2 = 1
	WHILE moved2
		moved2 = 0
		WAIT
		WAIT
		SOUND 2,,0
		WAIT
		IF lc > ml2 THEN
			lc = lc - 1
			moved2 = 1
		END IF
		IF rc < mr2 THEN
			rc = rc + 1
			moved2 = 1
		END IF
		lo2 = lc - wdep
		IF lo2 < 1 THEN lo2 = 1
		ro2 = rc + wdep
		IF ro2 > 30 THEN ro2 = 30
		FOR cx = lo2 TO ro2
			vc = cx
			GOSUB scol
			IF cx = lc THEN
				vch = 135
				GOSUB vcol
			ELSEIF cx = rc THEN
				vch = 135
				GOSUB vcol
			ELSEIF cx > lc THEN
				IF cx < rc THEN
					vch = 136
					GOSUB vcol
				END IF
			END IF
		NEXT cx
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

	' Paint char vch down the shaft height (rows 1..vsh) at column vc.
vcol:
	FOR r = 1 TO vsh
		VPOKE $1800 + (r - 1) * 32 + vc,vch
	NEXT r
	RETURN

	' Erase a stage column (space) down the OLD stage rows (vsh..17) at
	' column vc -- used while the old shaft narrows in the close phase.
scol0:
	FOR r = vsh TO 17
		VPOKE $1800 + r * 32 + vc,32
	NEXT r
	RETURN

	' Paint the whole shaft interior (rows 1..sh, cols 1..W) with the black
	' interior tile 136. Shared by init_level and the wall_anim CLOSE phase.
fill_interior:
	FOR r = 1 TO sh
		FOR cx = 1 TO W
			VPOKE $1800 + (r - 1) * 32 + ML + cx,136
		NEXT cx
	NEXT r
	RETURN

	' Hide every sprite (player + all piece slots). Shared by title_screen
	' and the wall_anim level transition.
hide_sprites:
	FOR i = 0 TO MAXP
		SPRITE i,$D1,0,0,0
	NEXT i
	RETURN

	' ---- Level-complete FLUSH ----
	' Runs at level_up, before the wall animation switches geometry, on the
	' COMPLETED level's geometry (W/ML/sh not yet re-run through calc_geom).
	' Hide the player + pieces, then drain the shaft down and out the bottom
	' just above the mountain until it is empty. ColecoVision additionally BAKES
	' the still-falling pieces into tiles first (#if NOT TI994A) so they drain
	' with the stack; the TI-99 omits that (~414 B it can't spare) -- its
	' in-flight pieces simply vanish and only the settled stack drains.
flush_level:
	' Hide the player and every piece sprite up front (both targets).
	GOSUB hide_sprites
#if TI994A
	' TI-99: the drain does a full VPEEK row-shift of the WHOLE shaft every frame
	' (~sh*sh*W VDP round-trips) -- too slow on the TMS9900, it crawls. So TI runs
	' a cheap WIPE instead: blank the interior one row at a time from the TOP
	' downward (no shift, no VPEEK) under the same descending tone. In-flight
	' pieces just vanish (hidden above). The foundation is untouched.
	wodd = 0
	FOR f = 1 TO sh
		#fq = 200 + (sh - f) * 50
		SOUND 2,#fq,10
		FOR cx = 1 TO W
			VPOKE $1800 + (f - 1) * 32 + ML + cx,136
		NEXT cx
		' Hold each cleared row 4 or 5 frames (alternating, avg 4.5) -- 50%
		' longer than the flat 3-frame hold. wodd toggles the extra frame.
		FOR wt = 1 TO 4
			WAIT
		NEXT wt
		wodd = 1 - wodd
		IF wodd = 0 THEN WAIT
	NEXT f
#else
	' ColecoVision: BAKE each still-falling piece into solid piece-colour tiles
	' (128 + colour - 1) where it hangs so it drains WITH the stack, then DRAIN
	' the shaft down and out (fast enough on the Z80). No H() update -- these are
	' throwaway decorations the drain carries off.
	FOR p = 0 TO MAXP - 1
		IF pact(p) <> 0 THEN
			pcp = pci(p)
			' Bottom pixel of the bottom-aligned sprite art is ppy-1; the
			' char row it lands in bakes the piece onto the grid.
			pbb = (ppy(p) - 1) / 8
			FOR b = 0 TO 2
				j = p * 3 + b
				IF barcol(j) <> 0 THEN
					mc = ML + barcol(j)
					' Guard an 8-bit unsigned UNDERFLOW that hard-freezes the
					' Coleco at level-up: a piece still HIGH in the shaft (small
					' pbb) with a side bar riding baroff rows up makes
					' r2 = pbb - baroff wrap to ~255. FOR r = r1 TO 255 then
					' NEVER exits (r wraps 255->0, never exceeds 255) -- an
					' infinite loop that first smears the piece colour up the
					' whole column (a tall bar) then locks up. Only bake a bar
					' whose bottom sits at/below the shaft top; one above it has
					' nothing visible to draw. (The old IF r >= 0 was a no-op --
					' r is unsigned, never negative.)
					IF pbb >= baroff(j) THEN
						r2 = pbb - baroff(j)
						r1 = r2 - barht(j) + 1
						FOR r = r1 TO r2
							IF r <= sh - 1 THEN VPOKE $1800 + r * 32 + mc,128 + pcp - 1
						NEXT r
					END IF
				END IF
			NEXT b
			pact(p) = 0
		END IF
	NEXT p
	' DRAIN (ColecoVision): shift the shaft interior above the mountain (cols ML+1..ML+W, rows
	' 0..sh-1) down one row per step; the bottom interior row (sh-1) is
	' overwritten each step, so content disappears just above the mountain top
	' (row sh). The foundation (rows sh..17) is never touched. Black interior
	' (136) feeds in at the top until the shaft is empty.
	FOR f = 1 TO sh
		' Descending tone as the stack drains (channel 2 -- music is OFF here):
		' pitch steps DOWN one notch per drained row.
		#fq = 200 + (sh - f) * 50
		SOUND 2,#fq,10
		FOR r = sh - 1 TO 1 STEP -1
			FOR cx = 1 TO W
				VPOKE $1800 + r * 32 + ML + cx,VPEEK($1800 + (r - 1) * 32 + ML + cx)
			NEXT cx
		NEXT r
		FOR cx = 1 TO W
			VPOKE $1800 + ML + cx,136
		NEXT cx
		WAIT
	NEXT f
#endif
	SOUND 2,,0
	RETURN

	' Draw ONE new-stage column vc, flared like draw_stage: inside the top
	' (lip) width it runs from row sh; a column e steps beyond the lip
	' starts e rows lower (sh + e) so the mountain fans out one column per
	' row, and every column fills down to the floor (row 17). Even-level
	' half top / wall-seam handling matches draw_stage.
scol:
	e = 0
	IF vc < ML - 1 THEN e = ML - 1 - vc
	IF vc > ML + W + 2 THEN e = vc - ML - W - 2
	topr = sh + e
	botr = 17
	IF topr <= botr THEN
		FOR r = topr TO botr
			code = 137
			IF r = sh THEN
				IF hoff THEN
					code = 138
					IF vc = ML THEN code = 202
					IF vc = ML + W + 1 THEN code = 202
				END IF
			END IF
			VPOKE $1800 + r * 32 + vc,code
		NEXT r
	END IF
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
	snd2 = 0
	snd3 = 0
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
	PRINT AT CPOS(19,9),"OOPS!  BURIED!"
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
	' (Solid 8x8 tile chars 128-136 reuse the solid_ff table below, so no
	' separate filled_bitmap is needed.)

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

	' Stage checker: 4x4-px alternating white/black squares. Char 137 =
	' full tile; char 138 = HALF tile (top 4 px empty) for the visible
	' half-character stage rise on even levels -- its lower half is
	' phase-opposed so the checker continues into the full tile below.
stage_bitmap:
	BITMAP "XXXX...."
	BITMAP "XXXX...."
	BITMAP "XXXX...."
	BITMAP "XXXX...."
	BITMAP "....XXXX"
	BITMAP "....XXXX"
	BITMAP "....XXXX"
	BITMAP "....XXXX"
	BITMAP "........"
	BITMAP "........"
	BITMAP "........"
	BITMAP "........"
	BITMAP "....XXXX"
	BITMAP "....XXXX"
	BITMAP "....XXXX"
	BITMAP "....XXXX"

	' Solid 8x8 pattern shared by all 56 "pair" tiles (139-194) -- the
	' split colors come entirely from each char's per-row color bytes.
solid_ff:
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

	' Wall-seam tile (202): solid white top half over the checker's
	' bottom-half phase (matches the half-stage tile 138), so on even
	' levels the white wall continues 4 px down to meet the checker.
	' (char 202's pattern is the same $FF..$0F seam row as bnd_pat below,
	' so char 202 reads bnd_pat -- no separate wallseam_pat needed.)
wallseam_col:
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1

	' Stage-seam tiles (195-201): solid top half over the checker's
	' top-half phase (matches the half-stage tile 138).
bnd_pat:
	DATA BYTE $FF,$FF,$FF,$FF,$0F,$0F,$0F,$0F
	DATA BYTE $FF,$FF,$FF,$FF,$0F,$0F,$0F,$0F
	DATA BYTE $FF,$FF,$FF,$FF,$0F,$0F,$0F,$0F
	DATA BYTE $FF,$FF,$FF,$FF,$0F,$0F,$0F,$0F
	DATA BYTE $FF,$FF,$FF,$FF,$0F,$0F,$0F,$0F
	DATA BYTE $FF,$FF,$FF,$FF,$0F,$0F,$0F,$0F
	DATA BYTE $FF,$FF,$FF,$FF,$0F,$0F,$0F,$0F

	' Pair-tile colors: for A = 0..7 (0 = black, then the 7 piece
	' colors) and B = 1..7, rows 0-3 = A's color byte, rows 4-7 = B's.
	' Color bytes: black $11, then $81,$31,$A1,$71,$51,$61,$D1 (last =
	' magenta, the "straight bar" piece color 7).
pcc1:
	DATA BYTE $11,$11,$11,$11,$81,$81,$81,$81
	DATA BYTE $11,$11,$11,$11,$31,$31,$31,$31
	DATA BYTE $11,$11,$11,$11,$A1,$A1,$A1,$A1
	DATA BYTE $11,$11,$11,$11,$71,$71,$71,$71
	DATA BYTE $11,$11,$11,$11,$51,$51,$51,$51
	DATA BYTE $11,$11,$11,$11,$61,$61,$61,$61
	DATA BYTE $11,$11,$11,$11,$D1,$D1,$D1,$D1
	DATA BYTE $81,$81,$81,$81,$81,$81,$81,$81
	DATA BYTE $81,$81,$81,$81,$31,$31,$31,$31
	DATA BYTE $81,$81,$81,$81,$A1,$A1,$A1,$A1
	DATA BYTE $81,$81,$81,$81,$71,$71,$71,$71
	DATA BYTE $81,$81,$81,$81,$51,$51,$51,$51
	DATA BYTE $81,$81,$81,$81,$61,$61,$61,$61
	DATA BYTE $81,$81,$81,$81,$D1,$D1,$D1,$D1
	DATA BYTE $31,$31,$31,$31,$81,$81,$81,$81
	DATA BYTE $31,$31,$31,$31,$31,$31,$31,$31
pcc2:
	DATA BYTE $31,$31,$31,$31,$A1,$A1,$A1,$A1
	DATA BYTE $31,$31,$31,$31,$71,$71,$71,$71
	DATA BYTE $31,$31,$31,$31,$51,$51,$51,$51
	DATA BYTE $31,$31,$31,$31,$61,$61,$61,$61
	DATA BYTE $31,$31,$31,$31,$D1,$D1,$D1,$D1
	DATA BYTE $A1,$A1,$A1,$A1,$81,$81,$81,$81
	DATA BYTE $A1,$A1,$A1,$A1,$31,$31,$31,$31
	DATA BYTE $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
	DATA BYTE $A1,$A1,$A1,$A1,$71,$71,$71,$71
	DATA BYTE $A1,$A1,$A1,$A1,$51,$51,$51,$51
	DATA BYTE $A1,$A1,$A1,$A1,$61,$61,$61,$61
	DATA BYTE $A1,$A1,$A1,$A1,$D1,$D1,$D1,$D1
	DATA BYTE $71,$71,$71,$71,$81,$81,$81,$81
	DATA BYTE $71,$71,$71,$71,$31,$31,$31,$31
	DATA BYTE $71,$71,$71,$71,$A1,$A1,$A1,$A1
	DATA BYTE $71,$71,$71,$71,$71,$71,$71,$71
pcc3:
	DATA BYTE $71,$71,$71,$71,$51,$51,$51,$51
	DATA BYTE $71,$71,$71,$71,$61,$61,$61,$61
	DATA BYTE $71,$71,$71,$71,$D1,$D1,$D1,$D1
	DATA BYTE $51,$51,$51,$51,$81,$81,$81,$81
	DATA BYTE $51,$51,$51,$51,$31,$31,$31,$31
	DATA BYTE $51,$51,$51,$51,$A1,$A1,$A1,$A1
	DATA BYTE $51,$51,$51,$51,$71,$71,$71,$71
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51
	DATA BYTE $51,$51,$51,$51,$61,$61,$61,$61
	DATA BYTE $51,$51,$51,$51,$D1,$D1,$D1,$D1
	DATA BYTE $61,$61,$61,$61,$81,$81,$81,$81
	DATA BYTE $61,$61,$61,$61,$31,$31,$31,$31
	DATA BYTE $61,$61,$61,$61,$A1,$A1,$A1,$A1
	DATA BYTE $61,$61,$61,$61,$71,$71,$71,$71
	DATA BYTE $61,$61,$61,$61,$51,$51,$51,$51
	DATA BYTE $61,$61,$61,$61,$61,$61,$61,$61
pcc4:
	DATA BYTE $61,$61,$61,$61,$D1,$D1,$D1,$D1
	DATA BYTE $D1,$D1,$D1,$D1,$81,$81,$81,$81
	DATA BYTE $D1,$D1,$D1,$D1,$31,$31,$31,$31
	DATA BYTE $D1,$D1,$D1,$D1,$A1,$A1,$A1,$A1
	DATA BYTE $D1,$D1,$D1,$D1,$71,$71,$71,$71
	DATA BYTE $D1,$D1,$D1,$D1,$51,$51,$51,$51
	DATA BYTE $D1,$D1,$D1,$D1,$61,$61,$61,$61
	DATA BYTE $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1

	' Stage-seam colors: piece color over white-on-black checker rows.
bnd_colors:
	DATA BYTE $81,$81,$81,$81,$F1,$F1,$F1,$F1
	DATA BYTE $31,$31,$31,$31,$F1,$F1,$F1,$F1
	DATA BYTE $A1,$A1,$A1,$A1,$F1,$F1,$F1,$F1
	DATA BYTE $71,$71,$71,$71,$F1,$F1,$F1,$F1
	DATA BYTE $51,$51,$51,$51,$F1,$F1,$F1,$F1
	DATA BYTE $61,$61,$61,$61,$F1,$F1,$F1,$F1
	DATA BYTE $D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1

	' Per-row colors (fg*16+bg) for chars 128-138: the 7 piece colors
	' (red, lt green, yellow, cyan, blue, dk red, magenta), the white
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
	DATA BYTE $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $11,$11,$11,$11,$11,$11,$11,$11
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1

	'
	' Per-level background tunes (tune1..tune10). Each is an ORIGINAL loop
	' for PLAY SIMPLE (two channels: melody + bass Z, which sounds two
	' octaves down); a MUSIC row is one eighth note, 8 rows per bar. The
	' tunes get faster and darker as the levels climb (start_music picks
	' one by LV). tune1 is the level-1 A-minor folk-dance loop; tune2..10
	' are shorter distinct loops generated from chord progressions.
	'
	' tune1 -- level 1: A minor, brisk folk-dance, 16 bars, ~150 BPM.
tune1:
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

	' tune2 -- level 2: D minor, folk lilt.
tune2:
	DATA BYTE 10
	MUSIC D4Y,D5Z
	MUSIC F4,S
	MUSIC A4,A5
	MUSIC D5,S
	MUSIC A4,D5
	MUSIC F4,S
	MUSIC D4,A5
	MUSIC S,S
	MUSIC A4#,A5#
	MUSIC F5,S
	MUSIC D5,F6
	MUSIC A5#,S
	MUSIC S,A5#
	MUSIC F5,S
	MUSIC D5,F6
	MUSIC A4#,S
	MUSIC F4,F5
	MUSIC A4,S
	MUSIC C5,C6
	MUSIC F5,S
	MUSIC C5,F5
	MUSIC A4,S
	MUSIC F4,C6
	MUSIC S,S
	MUSIC A4,A5
	MUSIC -,S
	MUSIC E5,E6
	MUSIC -,S
	MUSIC A5,A5
	MUSIC E5,S
	MUSIC C5,E6
	MUSIC S,S
	MUSIC D4,D5
	MUSIC F4,S
	MUSIC A4,A5
	MUSIC D5,S
	MUSIC A4,D5
	MUSIC F4,S
	MUSIC D4,A5
	MUSIC S,S
	MUSIC A4#,A5#
	MUSIC F5,S
	MUSIC D5,F6
	MUSIC A5#,S
	MUSIC S,A5#
	MUSIC F5,S
	MUSIC D5,F6
	MUSIC A4#,S
	MUSIC C4,C5
	MUSIC E4,S
	MUSIC G4,G5
	MUSIC C5,S
	MUSIC G4,C5
	MUSIC E4,S
	MUSIC C4,G5
	MUSIC S,S
	MUSIC D4,D5
	MUSIC -,S
	MUSIC A4,A5
	MUSIC -,S
	MUSIC D5,D5
	MUSIC A4,S
	MUSIC F4,A5
	MUSIC S,S
	MUSIC REPEAT

	' tune3 -- level 3: E phrygian, brooding.
tune3:
	DATA BYTE 9
	MUSIC E4X,E5Z
	MUSIC -,S
	MUSIC B4,B5
	MUSIC -,S
	MUSIC E5,E5
	MUSIC B4,S
	MUSIC G4,B5
	MUSIC S,S
	MUSIC F4,F5
	MUSIC A4,S
	MUSIC C5,C6
	MUSIC S,S
	MUSIC F5,F5
	MUSIC C5,S
	MUSIC S,C6
	MUSIC A4,S
	MUSIC D4,D5
	MUSIC -,S
	MUSIC A4,A5
	MUSIC -,S
	MUSIC D5,D5
	MUSIC A4,S
	MUSIC F4,A5
	MUSIC S,S
	MUSIC E4,E5
	MUSIC G4,S
	MUSIC B4,B5
	MUSIC E5,S
	MUSIC B4,E5
	MUSIC G4,S
	MUSIC E4,B5
	MUSIC S,S
	MUSIC C4,C5
	MUSIC -,S
	MUSIC G4,G5
	MUSIC -,S
	MUSIC C5,C5
	MUSIC G4,S
	MUSIC E4,G5
	MUSIC S,S
	MUSIC F4,F5
	MUSIC A4,S
	MUSIC C5,C6
	MUSIC S,S
	MUSIC F5,F5
	MUSIC C5,S
	MUSIC S,C6
	MUSIC A4,S
	MUSIC B4,B5
	MUSIC -,S
	MUSIC F5,F6
	MUSIC -,S
	MUSIC B5,B5
	MUSIC F5,S
	MUSIC D5,F6
	MUSIC S,S
	MUSIC E4,E5
	MUSIC G4,S
	MUSIC B4,B5
	MUSIC E5,S
	MUSIC B4,E5
	MUSIC G4,S
	MUSIC E4,B5
	MUSIC S,S
	MUSIC REPEAT

	' tune4 -- level 4: G major, bright drive.
tune4:
	DATA BYTE 9
	MUSIC G4W,G4Z
	MUSIC D5,S
	MUSIC B4,D5
	MUSIC G5,S
	MUSIC S,G4
	MUSIC D5,S
	MUSIC B4,D5
	MUSIC G4,S
	MUSIC D4,D4
	MUSIC F4#,S
	MUSIC A4,A4
	MUSIC D5,S
	MUSIC A4,D4
	MUSIC F4#,S
	MUSIC D4,A4
	MUSIC S,S
	MUSIC E4,E4
	MUSIC B4,S
	MUSIC G4,B4
	MUSIC E5,S
	MUSIC S,E4
	MUSIC B4,S
	MUSIC G4,B4
	MUSIC E4,S
	MUSIC C4,C4
	MUSIC E4,S
	MUSIC G4,G4
	MUSIC S,S
	MUSIC C5,C4
	MUSIC G4,S
	MUSIC S,G4
	MUSIC E4,S
	MUSIC A4,A4
	MUSIC E5,S
	MUSIC C5,E5
	MUSIC A5,S
	MUSIC S,A4
	MUSIC E5,S
	MUSIC C5,E5
	MUSIC A4,S
	MUSIC D4,D4
	MUSIC F4#,S
	MUSIC A4,A4
	MUSIC D5,S
	MUSIC A4,D4
	MUSIC F4#,S
	MUSIC D4,A4
	MUSIC S,S
	MUSIC G4,G4
	MUSIC D5,S
	MUSIC B4,D5
	MUSIC G5,S
	MUSIC S,G4
	MUSIC D5,S
	MUSIC B4,D5
	MUSIC G4,S
	MUSIC D4,D4
	MUSIC F4#,S
	MUSIC A4,A4
	MUSIC S,S
	MUSIC D5,D4
	MUSIC A4,S
	MUSIC S,A4
	MUSIC F4#,S
	MUSIC REPEAT

	' tune5 -- level 5: C dorian, groovy.
tune5:
	DATA BYTE 8
	MUSIC C4Y,C5Z
	MUSIC D4#,S
	MUSIC G4,G5
	MUSIC C5,S
	MUSIC G4,C5
	MUSIC D4#,S
	MUSIC C4,G5
	MUSIC S,S
	MUSIC F4,F5
	MUSIC -,S
	MUSIC C5,C6
	MUSIC -,S
	MUSIC F5,F5
	MUSIC C5,S
	MUSIC A4,C6
	MUSIC S,S
	MUSIC A4#,A5#
	MUSIC F5,S
	MUSIC D5,F6
	MUSIC A5#,S
	MUSIC S,A5#
	MUSIC F5,S
	MUSIC D5,F6
	MUSIC A4#,S
	MUSIC G4,C5
	MUSIC D4#,S
	MUSIC C4,G5
	MUSIC D4#,S
	MUSIC G4,C5
	MUSIC C5,S
	MUSIC G4,G5
	MUSIC S,S
	MUSIC A4,A5
	MUSIC C5,S
	MUSIC D5#,D6#
	MUSIC A5,S
	MUSIC D5#,A5
	MUSIC C5,S
	MUSIC A4,D6#
	MUSIC S,S
	MUSIC F4,F5
	MUSIC -,S
	MUSIC C5,C6
	MUSIC -,S
	MUSIC F5,F5
	MUSIC C5,S
	MUSIC A4,C6
	MUSIC S,S
	MUSIC G4,G5
	MUSIC D5,S
	MUSIC A4#,D6
	MUSIC G5,S
	MUSIC S,G5
	MUSIC D5,S
	MUSIC A4#,D6
	MUSIC G4,S
	MUSIC G4,C5
	MUSIC D4#,S
	MUSIC C4,G5
	MUSIC D4#,S
	MUSIC G4,C5
	MUSIC C5,S
	MUSIC G4,G5
	MUSIC S,S
	MUSIC REPEAT

	' tune6 -- level 6: A harmonic minor, tense.
tune6:
	DATA BYTE 8
	MUSIC A4X,A5Z
	MUSIC C5,S
	MUSIC E5,E6
	MUSIC S,S
	MUSIC A5,A5
	MUSIC E5,S
	MUSIC S,E6
	MUSIC C5,S
	MUSIC E4,E5
	MUSIC -,S
	MUSIC B4,B5
	MUSIC -,S
	MUSIC E5,E5
	MUSIC B4,S
	MUSIC G4#,B5
	MUSIC S,S
	MUSIC F4,F5
	MUSIC A4,S
	MUSIC C5,C6
	MUSIC F5,S
	MUSIC C5,F5
	MUSIC A4,S
	MUSIC F4,C6
	MUSIC S,S
	MUSIC E4,E5
	MUSIC B4,S
	MUSIC G4#,B5
	MUSIC E5,S
	MUSIC S,E5
	MUSIC B4,S
	MUSIC G4#,B5
	MUSIC E4,S
	MUSIC A4,A5
	MUSIC C5,S
	MUSIC E5,E6
	MUSIC S,S
	MUSIC A5,A5
	MUSIC E5,S
	MUSIC S,E6
	MUSIC C5,S
	MUSIC D4,D5
	MUSIC -,S
	MUSIC A4,A5
	MUSIC -,S
	MUSIC D5,D5
	MUSIC A4,S
	MUSIC F4,A5
	MUSIC S,S
	MUSIC G4#,G5#
	MUSIC B4,S
	MUSIC D5,D6
	MUSIC G5#,S
	MUSIC D5,G5#
	MUSIC B4,S
	MUSIC G4#,D6
	MUSIC S,S
	MUSIC A4,A5
	MUSIC E5,S
	MUSIC C5,E6
	MUSIC A5,S
	MUSIC S,A5
	MUSIC E5,S
	MUSIC C5,E6
	MUSIC A4,S
	MUSIC REPEAT

	' tune7 -- level 7: F# minor, urgent.
tune7:
	DATA BYTE 7
	MUSIC F4#W,F4#Z
	MUSIC C5#,S
	MUSIC A4,C5#
	MUSIC F5#,S
	MUSIC S,F4#
	MUSIC C5#,S
	MUSIC A4,C5#
	MUSIC F4#,S
	MUSIC B4,E4
	MUSIC G4#,S
	MUSIC E4,B4
	MUSIC G4#,S
	MUSIC B4,E4
	MUSIC E5,S
	MUSIC B4,B4
	MUSIC S,S
	MUSIC D4,D4
	MUSIC -,S
	MUSIC A4,A4
	MUSIC -,S
	MUSIC D5,D4
	MUSIC A4,S
	MUSIC F4#,A4
	MUSIC S,S
	MUSIC C4#,C4#
	MUSIC E4,S
	MUSIC G4#,G4#
	MUSIC C5#,S
	MUSIC G4#,C4#
	MUSIC E4,S
	MUSIC C4#,G4#
	MUSIC S,S
	MUSIC B4,B4
	MUSIC F5#,S
	MUSIC D5,F5#
	MUSIC B5,S
	MUSIC S,B4
	MUSIC F5#,S
	MUSIC D5,F5#
	MUSIC B4,S
	MUSIC B4,E4
	MUSIC G4#,S
	MUSIC E4,B4
	MUSIC G4#,S
	MUSIC B4,E4
	MUSIC E5,S
	MUSIC B4,B4
	MUSIC S,S
	MUSIC F4#,F4#
	MUSIC -,S
	MUSIC C5#,C5#
	MUSIC -,S
	MUSIC F5#,F4#
	MUSIC C5#,S
	MUSIC A4,C5#
	MUSIC S,S
	MUSIC C4#,C4#
	MUSIC E4,S
	MUSIC G4#,G4#
	MUSIC C5#,S
	MUSIC G4#,C4#
	MUSIC E4,S
	MUSIC C4#,G4#
	MUSIC S,S
	MUSIC REPEAT

	' tune8 -- level 8: B phrygian, ominous.
tune8:
	DATA BYTE 7
	MUSIC B4Y,B5Z
	MUSIC -,S
	MUSIC F5#,F6#
	MUSIC -,S
	MUSIC B5,B5
	MUSIC F5#,S
	MUSIC D5,F6#
	MUSIC S,S
	MUSIC C4,C5
	MUSIC E4,S
	MUSIC G4,G5
	MUSIC C5,S
	MUSIC G4,C5
	MUSIC E4,S
	MUSIC C4,G5
	MUSIC S,S
	MUSIC A4,A5
	MUSIC C5,S
	MUSIC E5,E6
	MUSIC S,S
	MUSIC A5,A5
	MUSIC E5,S
	MUSIC S,E6
	MUSIC C5,S
	MUSIC G4,G5
	MUSIC D5,S
	MUSIC B4,D6
	MUSIC G5,S
	MUSIC S,G5
	MUSIC D5,S
	MUSIC B4,D6
	MUSIC G4,S
	MUSIC B4,B5
	MUSIC -,S
	MUSIC F5#,F6#
	MUSIC -,S
	MUSIC B5,B5
	MUSIC F5#,S
	MUSIC D5,F6#
	MUSIC S,S
	MUSIC C4,C5
	MUSIC E4,S
	MUSIC G4,G5
	MUSIC C5,S
	MUSIC G4,C5
	MUSIC E4,S
	MUSIC C4,G5
	MUSIC S,S
	MUSIC F4#,F5#
	MUSIC A4,S
	MUSIC C5,C6
	MUSIC S,S
	MUSIC F5#,F5#
	MUSIC C5,S
	MUSIC S,C6
	MUSIC A4,S
	MUSIC B4,B5
	MUSIC F5#,S
	MUSIC D5,F6#
	MUSIC B5,S
	MUSIC S,B5
	MUSIC F5#,S
	MUSIC D5,F6#
	MUSIC B4,S
	MUSIC REPEAT

	' tune9 -- level 9: E harmonic minor, frantic.
tune9:
	DATA BYTE 6
	MUSIC B4X,E5Z
	MUSIC G4,S
	MUSIC E4,B5
	MUSIC G4,S
	MUSIC B4,E5
	MUSIC E5,S
	MUSIC B4,B5
	MUSIC S,S
	MUSIC B4,B5
	MUSIC D5#,S
	MUSIC F5#,F6#
	MUSIC S,S
	MUSIC B5,B5
	MUSIC F5#,S
	MUSIC S,F6#
	MUSIC D5#,S
	MUSIC D4#,D5#
	MUSIC -,S
	MUSIC A4,A5
	MUSIC -,S
	MUSIC D5#,D5#
	MUSIC A4,S
	MUSIC F4#,A5
	MUSIC S,S
	MUSIC B4,B5
	MUSIC D5#,S
	MUSIC F5#,F6#
	MUSIC B5,S
	MUSIC F5#,B5
	MUSIC D5#,S
	MUSIC B4,F6#
	MUSIC S,S
	MUSIC B4,E5
	MUSIC G4,S
	MUSIC E4,B5
	MUSIC G4,S
	MUSIC B4,E5
	MUSIC E5,S
	MUSIC B4,B5
	MUSIC S,S
	MUSIC C4,C5
	MUSIC E4,S
	MUSIC G4,G5
	MUSIC S,S
	MUSIC C5,C5
	MUSIC G4,S
	MUSIC S,G5
	MUSIC E4,S
	MUSIC A4,A5
	MUSIC -,S
	MUSIC E5,E6
	MUSIC -,S
	MUSIC A5,A5
	MUSIC E5,S
	MUSIC C5,E6
	MUSIC S,S
	MUSIC B4,B5
	MUSIC D5#,S
	MUSIC F5#,F6#
	MUSIC B5,S
	MUSIC F5#,B5
	MUSIC D5#,S
	MUSIC B4,F6#
	MUSIC S,S
	MUSIC REPEAT

	' tune10 -- level 10: A minor, breakneck.
tune10:
	DATA BYTE 6
	MUSIC A4W,A4Z
	MUSIC E5,S
	MUSIC C5,E5
	MUSIC A5,S
	MUSIC S,A4
	MUSIC E5,S
	MUSIC C5,E5
	MUSIC A4,S
	MUSIC G4,G4
	MUSIC B4,S
	MUSIC D5,D5
	MUSIC S,S
	MUSIC G5,G4
	MUSIC D5,S
	MUSIC S,D5
	MUSIC B4,S
	MUSIC C5,F4
	MUSIC A4,S
	MUSIC F4,C5
	MUSIC A4,S
	MUSIC C5,F4
	MUSIC F5,S
	MUSIC C5,C5
	MUSIC S,S
	MUSIC G4,G4
	MUSIC -,S
	MUSIC D5,D5
	MUSIC -,S
	MUSIC G5,G4
	MUSIC D5,S
	MUSIC B4,D5
	MUSIC S,S
	MUSIC A4,A4
	MUSIC E5,S
	MUSIC C5,E5
	MUSIC A5,S
	MUSIC S,A4
	MUSIC E5,S
	MUSIC C5,E5
	MUSIC A4,S
	MUSIC E4,E4
	MUSIC G4,S
	MUSIC B4,B4
	MUSIC S,S
	MUSIC E5,E4
	MUSIC B4,S
	MUSIC S,B4
	MUSIC G4,S
	MUSIC A4,D4
	MUSIC F4,S
	MUSIC D4,A4
	MUSIC F4,S
	MUSIC A4,D4
	MUSIC D5,S
	MUSIC A4,A4
	MUSIC S,S
	MUSIC E4,E4
	MUSIC -,S
	MUSIC B4,B4
	MUSIC -,S
	MUSIC E5,E4
	MUSIC B4,S
	MUSIC G4,B4
	MUSIC S,S
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
