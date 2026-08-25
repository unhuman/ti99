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

	CONST GRAV = 24			' added to #vy every frame (8.8: 0.09 px/frame^2)
	CONST ACCX = 20			' horizontal acceleration while steering
	CONST FRIC = 10			' horizontal decay when not steering
	CONST NPLAT = 6			' platforms, DIM 0..5
	CONST NKN = 4			' knights, DIM 0..3
	CONST NEGG = 4			' eggs, DIM 0..3
	CONST LAVAY = 168		' feet at or below this pixel row are in the lava
	CONST TOPY = 8			' ceiling: sprite top cannot go above this
	CONST SPRHID = 209		' NOT 208 -- 208 terminates the sprite list
	CONST BLANK = 32
	CONST PLATL = 128
	CONST PLATM = 129
	CONST PLATR = 130
	CONST LAVAA = 131
	CONST LIFECH = 134

	' Velocities are stored BIASED by +32768 so that every comparison stays in
	' unsigned territory: "rising" is #vy < 32768, never #vy < 0. 32768 itself is
	' written as a literal everywhere -- as a CONST it would truncate to 0.

	DIM #plx1(NPLAT)		' platform left edge, pixels
	DIM #plx2(NPLAT)		' platform right edge
	DIM ply(NPLAT)			' platform surface row, pixels (all < 256)

	DIM #kx(NKN)			' knight x, 8.8
	DIM #ky(NKN)			' knight y, 8.8
	DIM #kvx(NKN)			' knight x velocity, biased
	DIM #kvy(NKN)			' knight y velocity, biased
	DIM ktier(NKN)			' 0 bounder, 1 hunter, 2 shadow lord
	DIM kon(NKN)			' 0 dead, 1 mounted, 2 on foot
	DIM kface(NKN)			' 0 right, 1 left
	DIM kfrm(NKN)			' animation frame 0..3
	DIM kflp(NKN)			' frames until this knight may flap again

	DIM #ex(NEGG)			' egg x, 8.8
	DIM #ey(NEGG)			' egg y, 8.8
	DIM #evx(NEGG)			' egg x velocity, biased
	DIM #evy(NEGG)			' egg y velocity, biased
	DIM est(NEGG)			' 0 none, 1 falling, 2 resting, 3 hatching
	DIM etier(NEGG)			' tier of the knight this egg came from
	DIM #etm(NEGG)			' frames until the next state change

	GOSUB setup
	GOTO title_screen

	' ------------------------------------------------------------------ setup
setup:
	SPRITE FLICKER OFF		' all-or-nothing in CVBasic: it would strobe the
					' player too. Instead the player is sprite 0 --
					' highest priority, never the one the VDP drops.
	DEFINE CHAR PLATL,7,chr_plat_l
	DEFINE COLOR PLATL,7,col_chars
	DEFINE SPRITE 0,4,spr_mount_r	' patterns 0,4,8,12  -- facing right
	DEFINE SPRITE 4,4,spr_mount_l	' patterns 16,20,24,28 -- facing left
	DEFINE SPRITE 8,1,spr_egg	' pattern 32
	DEFINE SPRITE 9,1,spr_runner	' pattern 36

	' THE PLATFORMS, in pixels. The floor is two slabs with a LAVA GAP between
	' them -- a full-width floor would make the lava unreachable and remove the
	' hazard the whole game is built around.
	#plx1(0) = 0   : #plx2(0) = 95  : ply(0) = 160	' floor, left
	#plx1(1) = 160 : #plx2(1) = 255 : ply(1) = 160	' floor, right
	#plx1(2) = 16  : #plx2(2) = 79  : ply(2) = 120	' lower left
	#plx1(3) = 176 : #plx2(3) = 239 : ply(3) = 120	' lower right
	#plx1(4) = 56  : #plx2(4) = 119 : ply(4) = 80	' mid left
	#plx1(5) = 144 : #plx2(5) = 207 : ply(5) = 40	' upper right
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
title_wait:
	WAIT
	' RELEASE BEFORE PRESS. Arriving here with fire still held from the last
	' game would otherwise start the next one before the screen was read.
	IF btnr = 0 THEN
		IF cont1.button = 0 THEN btnr = 1
	ELSE
		IF cont1.button THEN GOTO new_game
	END IF
	GOTO title_wait

	' ------------------------------------------------------------- new game
new_game:
	#score = 0			' stored in TENS of points: every award in
					' Joust is a multiple of 50, so this is exact
					' and 16 bits then reaches 655,350.
	lives = 3
	wave = 0
	pover = 0
	GOSUB new_wave
	GOTO main

	' ------------------------------------------------------------- new wave
new_wave:
	wave = wave + 1
	ecoll = 0			' eggs collected this wave -> award ladder
	GOSUB draw_field
	GOSUB spawn_player

	' KNIGHTS PER WAVE, and their tier. Difficulty is flap eagerness and top
	' speed -- never making them flee, which reads as broken AI rather than as
	' an easier game (CLAUDE.md 3A).
	nwk = 2 + wave
	IF nwk > NKN THEN nwk = NKN
	FOR nwi = 0 TO NKN - 1
		kon(nwi) = 0
		IF nwi < nwk THEN
			kon(nwi) = 1
			ktier(nwi) = 0
			IF wave > 2 THEN ktier(nwi) = nwi AND 1
			IF wave > 5 THEN ktier(nwi) = 1 + (nwi AND 1)
			kfrm(nwi) = 0
			kflp(nwi) = 10 + nwi * 7
			' spread the spawns across the two upper platforms
			#kx(nwi) = 4096
			IF nwi > 1 THEN #kx(nwi) = 45056
			#kx(nwi) = #kx(nwi) + nwi * 2048
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
	#px = 16384			' x = 64, in 8.8
	#py = 20480			' y = 80
	#vx = 32768
	#vy = 32768
	pfrm = 0
	pface = 0
	pgnd = 0
	pdead = 0
	binv = 90			' brief spawn invulnerability, in frames
	RETURN

	' ------------------------------------------------------------ draw field
draw_field:
	CLS
	FOR dfi = 0 TO NPLAT - 1
		dfr = ply(dfi) / 8		' surface pixel row -> character row
		dfc = #plx1(dfi) / 8
		dfd = #plx2(dfi) / 8
		#dfa = dfr
		#dfa = #dfa * 32
		#dfa = #dfa + dfc
		GOSUB draw_plat
	NEXT dfi

	' The lava fills everything below the floor line.
	FOR dfi = 0 TO 31
		#dfa = 640 + dfi		' row 20
		#dfa = #dfa + 6144
		VPOKE #dfa,LAVAA
		#dfa = #dfa + 32
		VPOKE #dfa,133
		#dfa = #dfa + 32
		VPOKE #dfa,133
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
	GOSUB p_input
	GOSUB p_move
	GOSUB k_move
	GOSUB e_move
	GOSUB collide
	GOSUB draw
	GOSUB sfx_tick

	' A wave ends only when nothing is left to fight AND nothing left to hatch.
	mnl = 0
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
	IF binv > 0 THEN binv = binv - 1

	' FLAP IS EDGE TRIGGERED -- holding fire must not hover. The released state
	' has to be seen before the next flap counts.
	IF cont1.button THEN
		IF pflp = 0 THEN
			pflp = 1
			#vy = 32768 - 660
			pfrm = 2
			SOUND 0,700,12
			sf0 = 3
		END IF
	ELSE
		pflp = 0
	END IF

	' LEFT/RIGHT ONLY. Nothing here reads the vertical axis: on the TI it shares
	' a line with ALPHA LOCK and reports a direction that never releases.
	pin = 0
	IF cont1.left THEN
		pin = 1
		pface = 1
		IF #vx > 32768 - 512 THEN #vx = #vx - ACCX
	END IF
	IF cont1.right THEN
		pin = 1
		pface = 0
		IF #vx < 32768 + 512 THEN #vx = #vx + ACCX
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
	IF #vy > 32768 + 700 THEN #vy = 32768 + 700	' terminal fall speed

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
		#vy = 32768			' bonk the ceiling, stop rising
	END IF

	GOSUB p_land
	IF pdead = 0 THEN
		IF py8 >= LAVAY THEN
			IF pgnd = 0 THEN pdead = 1
		END IF
	END IF

	' Animation: frame follows vertical motion, not a timer.
	IF pgnd = 1 THEN
		pfrm = 3
		IF pin = 0 THEN pfrm = 1
	ELSE
		IF #vy < 32768 THEN
			pfrm = 0
		ELSE
			pfrm = 1
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
	plf = plf + 16			' feet
	plc2 = #px / 256
	plc2 = plc2 + 8			' centre x
	FOR pli2 = 0 TO NPLAT - 1
		IF plf >= ply(pli2) THEN
			IF plf <= ply(pli2) + 8 THEN
				IF plc2 >= #plx1(pli2) THEN
					IF plc2 <= #plx2(pli2) THEN
						pgnd = 1
						#py = ply(pli2) - 16
						#py = #py * 256
						#vy = 32768
					END IF
				END IF
			END IF
		END IF
	NEXT pli2
	RETURN

	' ----------------------------------------------------- knight movement
k_move:
	FOR kni = 0 TO NKN - 1
		IF kon(kni) > 0 THEN GOSUB k_one
	NEXT kni
	RETURN

k_one:
	' AI, two comparisons. No search, no path: the whole of the difficulty is
	' how eagerly a tier flaps and how fast it may travel.
	IF kflp(kni) > 0 THEN
		kflp(kni) = kflp(kni) - 1
	ELSE
		kpy = #py / 256
		kmy = #ky(kni) / 256
		IF kpy < kmy THEN
			#kvy(kni) = 32768 - 620
			kflp(kni) = 26 - ktier(kni) * 7
		END IF
	END IF

	' Steer toward the player. Compared in screen pixels so the wrap is handled
	' by choosing the shorter way round.
	kpx = #px / 256
	kmx = #kx(kni) / 256
	ktop = 400 + ktier(kni) * 90
	IF kpx > kmx THEN
		kdd = kpx - kmx
		IF kdd < 128 THEN GOSUB k_right ELSE GOSUB k_left
	ELSE
		kdd = kmx - kpx
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
		#kvy(kni) = 32768
	END IF

	' Land, and never sink into the lava: a knight that reaches the floor line
	' over the gap simply flaps back out.
	IF #kvy(kni) >= 32768 THEN
		kf = kmy + 16
		FOR knj = 0 TO NPLAT - 1
			IF kf >= ply(knj) THEN
				IF kf <= ply(knj) + 8 THEN
					kc = kmx + 8
					IF kc >= #plx1(knj) THEN
						IF kc <= #plx2(knj) THEN
							#ky(kni) = ply(knj) - 16
							#ky(kni) = #ky(kni) * 256
							#kvy(kni) = 32768
						END IF
					END IF
				END IF
			END IF
		NEXT knj
		IF kmy > LAVAY THEN
			#kvy(kni) = 32768 - 620
		END IF
	END IF

	kfrm(kni) = 1
	IF #kvy(kni) < 32768 THEN kfrm(kni) = 0
	RETURN

k_right:
	kface(kni) = 0
	IF #kvx(kni) < 32768 + ktop THEN #kvx(kni) = #kvx(kni) + 14
	RETURN

k_left:
	kface(kni) = 1
	IF #kvx(kni) > 32768 - ktop THEN #kvx(kni) = #kvx(kni) - 14
	RETURN

	' --------------------------------------------------------- egg movement
e_move:
	FOR egi = 0 TO NEGG - 1
		IF est(egi) > 0 THEN GOSUB e_one
	NEXT egi
	RETURN

e_one:
	IF est(egi) = 1 THEN
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
			IF egf >= ply(egj) THEN
				IF egf <= ply(egj) + 8 THEN
					egc = egx + 8
					IF egc >= #plx1(egj) THEN
						IF egc <= #plx2(egj) THEN
							#ey(egi) = ply(egj) - 16
							#ey(egi) = #ey(egi) * 256
							est(egi) = 2
							#etm(egi) = 500
							#evx(egi) = 32768
						END IF
					END IF
				END IF
			END IF
		NEXT egj
		' An egg that falls into the gap is simply gone.
		IF egy > LAVAY THEN est(egi) = 0
		RETURN
	END IF

	' Resting, then cracking, then a fresh knight one tier higher.
	IF #etm(egi) > 0 THEN
		#etm(egi) = #etm(egi) - 1
		IF #etm(egi) = 120 THEN
			est(egi) = 3
			SOUND 2,300,10
			sf2 = 6
		END IF
		RETURN
	END IF
	GOSUB e_hatch
	RETURN

	' Hatch into the first free knight slot, one tier up. If every slot is busy
	' the egg simply waits and tries again next frame.
e_hatch:
	FOR ehj = 0 TO NKN - 1
		IF kon(ehj) = 0 THEN
			kon(ehj) = 1
			ktier(ehj) = etier(egi) + 1
			IF ktier(ehj) > 2 THEN ktier(ehj) = 2
			#kx(ehj) = #ex(egi)
			#ky(ehj) = #ey(egi)
			#kvx(ehj) = 32768
			#kvy(ehj) = 32768 - 500
			kflp(ehj) = 20
			kface(ehj) = 0
			est(egi) = 0
			RETURN
		END IF
	NEXT ehj
	#etm(egi) = 30
	RETURN

	' ----------------------------------------------------------- collisions
collide:
	IF pdead > 0 THEN RETURN
	cpx = #px / 256
	cpy = #py / 256

	FOR cni = 0 TO NKN - 1
		IF kon(cni) > 0 THEN GOSUB c_knight
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
	IF cdx > 11 THEN RETURN
	cdy = cpy - cky
	IF cpy < cky THEN cdy = cky - cpy
	IF cdy > 11 THEN RETURN

	IF cpy + 4 <= cky THEN
		' the player's lance is higher: unhorse the knight
		GOSUB k_unhorse
		RETURN
	END IF
	IF cky + 4 <= cpy THEN
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
	FOR kuj = 0 TO NEGG - 1
		IF est(kuj) = 0 THEN
			est(kuj) = 1
			#ex(kuj) = #kx(cni)
			#ey(kuj) = #ky(cni)
			#evx(kuj) = #kvx(cni)
			#evy(kuj) = 32768
			etier(kuj) = ktier(cni)
			GOSUB prt_score
			RETURN
		END IF
	NEXT kuj
	GOSUB prt_score
	RETURN

	' 250, 500, 750, then 1000 -- in tens, and capped.
c_egg:
	cex = #ex(cni) / 256
	cey = #ey(cni) / 256
	cdx = cpx - cex
	IF cpx < cex THEN cdx = cex - cpx
	IF cdx > 11 THEN RETURN
	cdy = cpy - cey
	IF cpy < cey THEN cdy = cey - cpy
	IF cdy > 11 THEN RETURN
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
	RETURN

draw_knights:
	FOR dki = 0 TO NKN - 1
		IF kon(dki) = 0 THEN
			SPRITE 1 + dki,SPRHID,0,0,0
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
	NEXT dki
	RETURN

draw_eggs:
	FOR dei = 0 TO NEGG - 1
		IF est(dei) = 0 THEN
			SPRITE 5 + dei,SPRHID,0,0,0
		ELSE
			dey = #ey(dei) / 256
			dex = #ex(dei) / 256
			dec = 15
			IF est(dei) = 3 THEN
				dec = 15
				IF #etm(dei) AND 4 THEN dec = 9
			END IF
			SPRITE 5 + dei,dey,dex,32,dec
		END IF
	NEXT dei
	RETURN

hide_all:
	FOR hai = 0 TO 9
		SPRITE hai,SPRHID,0,0,0
	NEXT hai
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
