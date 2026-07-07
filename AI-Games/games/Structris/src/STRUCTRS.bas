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
	CONST MOVE_DELAY = 6	' frames of debounce between player steps

	DIM H(11)		' column heights, index 1..W (0 unused)

	DIM GSTART(16)		' shape table: group -> first variant index
	DIM GCOUNT(16)		' shape table: group -> variant count
	DIM VBL(27)		' shape table: variant -> left column delta
	DIM VB0(27)		' shape table: variant -> center column delta
	DIM VBR(27)		' shape table: variant -> right column delta
	DIM VCI(27)		' shape table: variant -> color index

	' The falling piece is RIGID: its up-to-3 bars share ONE fall counter
	' (plead) and land together the moment the center bar reaches its
	' column's surface. Each side bar rides baroff rows higher -- exactly
	' its column's height advantage, which the shape table selected the
	' piece to fit -- so at landing every bar is flush with its own
	' column's surface simultaneously. No per-bar landing, no "compacting".
	DIM barcol(3)		' active falling bar -> column (0 = inactive)
	DIM barht(3)		' active falling bar -> height (1-3)
	DIM baroff(3)		' active falling bar -> rows ABOVE the piece bottom (0-3)

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

	DEFINE CHAR 128,1,filled_bitmap		' char 128 = piece color 1
	DEFINE CHAR 129,1,filled_bitmap		' char 129 = piece color 2
	DEFINE CHAR 130,1,filled_bitmap		' ...
	DEFINE CHAR 131,1,filled_bitmap
	DEFINE CHAR 132,1,filled_bitmap
	DEFINE CHAR 133,1,filled_bitmap
	DEFINE CHAR 134,1,filled_bitmap		' char 134 = piece color 7
	DEFINE CHAR 135,1,filled_bitmap		' char 135 = border/floor
	DEFINE COLOR 128,8,tile_colors

	DEFINE SPRITE 0,1,player_bitmap

	GOSUB setup_shapes

title_screen:
	SPRITE 0,$D1,0,0,0
	CLS
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
title_rel:
	WAIT
	IF cont1.button THEN GOTO title_rel
title_wait:
	WAIT
	IF cont1.button = 0 THEN GOTO title_wait

new_game:
	LV = 1
	RD = 0
	GOSUB init_level

main_loop:
	WAIT
	GOSUB handle_input
	GOSUB advance_pieces
	IF gameend = 1 THEN GOTO game_over
	IF gameend = 2 THEN GOTO win_screen
	SPRITE 0,PROW * 8 - 1,(ML + PCOL) * 8 - 1,0,15
	' Sound effects stay on for a few frames, then these counters
	' silence them (a SOUND ...,,0 in the same frame would be inaudible).
	IF snd0 > 0 THEN
		snd0 = snd0 - 1
		IF snd0 = 0 THEN SOUND 0,,0
	END IF
	IF snd1 > 0 THEN
		snd1 = snd1 - 1
		IF snd1 = 0 THEN SOUND 1,,0
	END IF
	IF snd2 > 0 THEN
		snd2 = snd2 - 1
		IF snd2 = 0 THEN SOUND 2,,0
	END IF
	GOTO main_loop

	'
	' ---- Level setup ----
	'
init_level:
	W = 11 - LV
	IF W < 5 THEN W = 5
	ML = (32 - W) / 2
	RG = 4 + LV
	' Clear the whole screen (not just the shaft rows) so title/game-over
	' text in the message rows 18-23 doesn't linger into the new level.
	FOR r = 0 TO 23
		FOR cx = 0 TO 31
			VPOKE $1800 + r * 32 + cx,32
		NEXT cx
	NEXT r
	FOR cc = 1 TO W
		H(cc) = 0
	NEXT cc
	FOR i = 0 TO 2
		barcol(i) = 0
	NEXT i
	spawn_timer = 20
	fall_cd = 1
	move_cd = 0
	gameend = 0
	PCOL = W / 2
	IF PCOL < 1 THEN PCOL = 1
	PROW = SHAFT_H
	GOSUB draw_borders
	GOSUB draw_hud
	RETURN

draw_borders:
	FOR r = 1 TO SHAFT_H
		VPOKE $1800 + r * 32 + ML,135
		VPOKE $1800 + r * 32 + ML + W + 1,135
	NEXT r
	FOR cx = ML TO ML + W + 1
		VPOKE $1800 + (SHAFT_H + 1) * 32 + cx,135
	NEXT cx
	RETURN

draw_hud:
	PRINT AT 0,"LV",<2>LV,"  CLR",<2>RD,"/",<2>RG,"   "
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
	IF move_cd > 0 THEN
		move_cd = move_cd - 1
		RETURN
	END IF
	moved = 0
	IF cont1.left AND PCOL > 1 THEN
		IF PROW <= SHAFT_H - H(PCOL - 1) THEN
			PCOL = PCOL - 1
			moved = 1
		END IF
	ELSEIF cont1.right AND PCOL < W THEN
		IF PROW <= SHAFT_H - H(PCOL + 1) THEN
			PCOL = PCOL + 1
			moved = 1
		END IF
	ELSEIF cont1.up AND PROW > 1 THEN
		PROW = PROW - 1
		moved = 1
	ELSEIF cont1.down THEN
		IF PROW < SHAFT_H - H(PCOL) THEN
			PROW = PROW + 1
			moved = 1
		END IF
	END IF
	IF moved THEN
		move_cd = MOVE_DELAY
		SOUND 0,224,10
		snd0 = 2
	END IF
	RETURN

	'
	' ---- Piece targeting + shape pick (ported from Structris.asb) ----
	'
choose_piece:
	x = PCOL
	IF x < 1 THEN x = 1
	IF x > W THEN x = W
	xo = x
	found = 0
	IF H(x) < MH THEN found = 1
	' Nested single-condition IFs throughout: the CVBasic 0.9.2 TI-99
	' backend miscompiles comparison-AND-comparison (see DESIGN.md).
	IF found = 0 THEN
		FOR d = 1 TO W
			IF found = 0 THEN
				t = xo + d
				IF t <= W THEN
					IF H(t) < MH THEN
						x = t
						found = 1
					END IF
				END IF
			END IF
			IF found = 0 THEN
				IF xo > d THEN
					t = xo - d
					IF H(t) < MH THEN
						x = t
						found = 1
					END IF
				END IF
			END IF
		NEXT d
	END IF

	h0 = H(x)
	IF x > 1 THEN
		hl = H(x - 1) - h0
		IF hl > 3 THEN hl = 3
	ELSE
		hl = 3
	END IF
	IF x < W THEN
		hr = H(x + 1) - h0
		IF hr > 3 THEN hr = 3
	ELSE
		hr = 3
	END IF
	g = hl * 4 + hr
	pick = GSTART(g) + RANDOM(GCOUNT(g))
	pbl = VBL(pick)
	pb0 = VB0(pick)
	pbr = VBR(pick)
	barci = VCI(pick)

	' A bar only exists on a side whose true height difference is 0-3
	' (larger/negative differences were clamped to 3, and every hl/hr=3
	' table entry has a 0 delta on that side) -- so hl/hr IS the side
	' bar's ride-height, and the whole rigid piece lands flush.
	n2 = 0
	IF x > 1 THEN
		IF pbl > 0 THEN
			barcol(n2) = x - 1
			barht(n2) = pbl
			baroff(n2) = hl
			n2 = n2 + 1
		END IF
	END IF
	IF pb0 > 0 THEN
		barcol(n2) = x
		barht(n2) = pb0
		baroff(n2) = 0
		n2 = n2 + 1
	END IF
	IF x < W THEN
		IF pbr > 0 THEN
			barcol(n2) = x + 1
			barht(n2) = pbr
			baroff(n2) = hr
			n2 = n2 + 1
		END IF
	END IF
	WHILE n2 < 3
		barcol(n2) = 0
		n2 = n2 + 1
	WEND
	plead = 0
	ptarget = SHAFT_H - H(x)
	RETURN

	'
	' ---- Per-frame piece spawn / fall / land ----
	'
advance_pieces:
	busy = 0
	FOR i = 0 TO 2
		IF barcol(i) <> 0 THEN busy = 1
	NEXT i

	IF busy = 0 THEN
		IF spawn_timer > 0 THEN
			spawn_timer = spawn_timer - 1
		ELSE
			GOSUB choose_piece
			ticks = 70 - LV * 5
			IF ticks < 20 THEN ticks = 20
			spawn_timer = ticks
			fpr = 8 - LV / 2
			IF fpr < 2 THEN fpr = 2
			fall_cd = fpr
			busy = 1
		END IF
	END IF

	IF busy THEN
		fall_cd = fall_cd - 1
		IF fall_cd <= 0 THEN
			fpr = 8 - LV / 2
			IF fpr < 2 THEN fpr = 2
			fall_cd = fpr
			' The rigid piece advances as ONE unit: a single shared fall
			' counter, and all bars land together when the piece bottom
			' (the center bar) reaches the center column's surface. Each
			' side bar rides baroff rows higher and is, by the shape
			' table's construction, flush with its own column's surface
			' at that same instant.
			plead = plead + 1
			IF plead >= ptarget THEN
				FOR i = 0 TO 2
					IF barcol(i) <> 0 THEN
						cc = barcol(i)
						' Land. Blank the whole empty region above the NEW
						' stack top first (erases the bar's last animation
						' frame), then paint only the newly-added cells so
						' settled cells keep their piece colors. Each loop
						' guarded: CVBasic FOR checks at the BOTTOM, so an
						' empty range would still run its body once.
						hold = H(cc)
						H(cc) = H(cc) + barht(i)
						IF H(cc) > SHAFT_H THEN H(cc) = SHAFT_H
						IF H(cc) < SHAFT_H THEN
							FOR r = 1 TO SHAFT_H - H(cc)
								VPOKE $1800 + r * 32 + ML + cc,32
							NEXT r
						END IF
						IF H(cc) > hold THEN
							FOR r = SHAFT_H - H(cc) + 1 TO SHAFT_H - hold
								VPOKE $1800 + r * 32 + ML + cc,128 + barci - 1
							NEXT r
						END IF
						barcol(i) = 0
					END IF
				NEXT i
				SOUND 1,600,12
				snd1 = 4
			ELSE
				FOR i = 0 TO 2
					IF barcol(i) <> 0 THEN
						' This bar's bottom row; it hasn't entered the
						' shaft yet while plead <= baroff (unsigned math,
						' so guard before subtracting).
						IF plead > baroff(i) THEN
							cc = barcol(i)
							thi = plead - baroff(i)
							IF thi < barht(i) THEN
								tlo = 1
							ELSE
								tlo = thi - barht(i) + 1
							END IF
							' Repaint only the EMPTY region above the settled
							' stack (settled cells keep their piece colors).
							FOR r = 1 TO SHAFT_H - H(cc)
								code = 32
								IF r >= tlo THEN
									IF r <= thi THEN code = 128 + barci - 1
								END IF
								VPOKE $1800 + r * 32 + ML + cc,code
							NEXT r
						END IF
					END IF
				NEXT i
			END IF
		END IF
	END IF

	GOSUB check_player
	IF gameend = 0 THEN GOSUB check_rowclear
	RETURN

	'
	' ---- Push-or-die collision ----
	'
check_player:
	pushes = 0
	WHILE pushes <= SHAFT_H
		filled = 0
		IF PROW > SHAFT_H - H(PCOL) THEN filled = 1
		' Compound comparisons (a >= x AND a <= y) are miscompiled by the
		' CVBasic 0.9.2 TI-99 backend (stale-register AND) -- keep every
		' condition single and nest instead. See DESIGN.md sec. "CVBasic
		' TI-99 codegen bug".
		FOR i = 0 TO 2
			IF barcol(i) = PCOL THEN
				IF plead > baroff(i) THEN
					thi = plead - baroff(i)
					IF thi < barht(i) THEN
						tlo = 1
					ELSE
						tlo = thi - barht(i) + 1
					END IF
					IF PROW >= tlo THEN
						IF PROW <= thi THEN filled = 1
					END IF
				END IF
			END IF
		NEXT i
		IF filled = 0 THEN
			RETURN
		END IF
		IF PROW <= 1 THEN
			gameend = 1
			RETURN
		END IF
		PROW = PROW - 1
		pushes = pushes + 1
	WEND
	gameend = 1
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
		NEXT cc
		' Completed rows fall away: shift every column's cells down m rows
		' on screen (VPEEK preserves each cell's per-piece color), blank
		' the vacated top rows.
		FOR cc = 1 TO W
			IF m < SHAFT_H THEN
				FOR r = SHAFT_H TO m + 1 STEP -1
					code = VPEEK($1800 + (r - m) * 32 + ML + cc)
					VPOKE $1800 + r * 32 + ML + cc,code
				NEXT r
			END IF
			FOR r = 1 TO m
				VPOKE $1800 + r * 32 + ML + cc,32
			NEXT r
		NEXT cc
		' A piece still falling now has m more rows to travel (harmless
		' no-op when nothing is in flight -- choose_piece resets ptarget).
		ptarget = ptarget + m
		RD = RD + m
		GOSUB draw_hud
		SOUND 2,300,12
		snd2 = 8
		IF RD >= RG THEN GOSUB level_up
	END IF
	RETURN

level_up:
	PRINT AT CPOS(19,10),"LEVEL UP!"
	FOR i = 1 TO 60
		WAIT
	NEXT i
	PRINT AT CPOS(19,10),"         "
	LV = LV + 1
	IF LV > 10 THEN
		gameend = 2
		RETURN
	END IF
	RD = 0
	GOSUB init_level
	RETURN

	'
	' ---- Terminal screens ----
	'
game_over:
	SPRITE 0,$D1,0,0,0
	SOUND 0,,0
	SOUND 1,,0
	SOUND 2,,0
	PRINT AT CPOS(19,13),"OOPS!"
	PRINT AT CPOS(21,7),"BURIED AT LEVEL ",LV
	PRINT AT CPOS(23,6),"FIRE FOR A NEW GAME"
	' Audible descending "you died" tone (sound must persist across
	' frames -- an immediate SOUND ...,,0 in the same frame is silent).
	FOR i = 1 TO 30
		SOUND 0,400 + i * 20,13
		WAIT
	NEXT i
	SOUND 0,,0
	' Require fire to be released first, so a press held from gameplay
	' doesn't instantly restart.
game_over_rel:
	WAIT
	IF cont1.button THEN GOTO game_over_rel
game_over_wait:
	WAIT
	IF cont1.button = 0 THEN GOTO game_over_wait
	GOTO new_game

win_screen:
	SPRITE 0,$D1,0,0,0
	SOUND 0,,0
	SOUND 1,,0
	SOUND 2,,0
	PRINT AT CPOS(10,4),"CONGRATULATIONS!"
	PRINT AT CPOS(12,2),"YOU SURVIVED ALL 10 LEVELS"
	PRINT AT CPOS(14,3),"THANKS FOR PLAYING STRUCTRIS"
	PRINT AT CPOS(23,6),"FIRE FOR A NEW GAME"
win_rel:
	WAIT
	IF cont1.button THEN GOTO win_rel
win_wait:
	WAIT
	IF cont1.button = 0 THEN GOTO win_wait
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

	' 16x16 sprite (CVBasic sprites are always 32 bytes); the little
	' climber lives in the top-left 8x8, the rest is transparent.
player_bitmap:
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "..XXXX.........."
	BITMAP ".XXXXXX........."
	BITMAP "...XX..........."
	BITMAP "..X..X.........."
	BITMAP "..X..X.........."
	BITMAP ".X....X........."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"

	' Per-row colors (fg*16+bg) for chars 128-135: the 7 piece colors
	' (red, lt green, yellow, cyan, blue, dk red, gray) then the white
	' border/floor tile. Solid tiles, so all 8 rows of each are the same.
tile_colors:
	DATA BYTE $81,$81,$81,$81,$81,$81,$81,$81
	DATA BYTE $31,$31,$31,$31,$31,$31,$31,$31
	DATA BYTE $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
	DATA BYTE $71,$71,$71,$71,$71,$71,$71,$71
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51
	DATA BYTE $61,$61,$61,$61,$61,$61,$61,$61
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1

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
