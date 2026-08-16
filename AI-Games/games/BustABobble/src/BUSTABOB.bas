	'
	' BUST-A-BOBBLE -- TI-99/4A + ColecoVision (CVBasic, dual-target)
	'
	' Clone of Taito's Puzzle Bobble / Bust-A-Move (1994). See DESIGN.md.
	'
	' The load-bearing decision (DESIGN.md section 2): every bubble is 2x2
	' CHARACTERS and stays character-aligned in every state the field can
	' reach -- 16 px pitch, 8 px (one char) hex stagger, and an 8 px (one
	' char) ceiling descent. So the field translates as a rigid body and
	' shake / drop / round-clear slide are all the SAME SCREEN blit at a
	' different destination offset.
	'
	' 2026 UNHUMAN AND CLAUDE
	'

	CONST NROWS    = 12	' grid rows (11 come from level data, 12th is headroom)
	CONST WELLCOL  = 1	' first character column inside the well
	CONST CEILROW  = 1	' character row of grid row 0 when top = 0
	CONST DEATHROW = 20	' a bubble whose BOTTOM reaches this row ends the round
	CONST BLANK    = 32
	CONST WALLCH   = 160	' solid block: walls + ceiling bar
	CONST DASHCH   = 161	' death-line dash

	CONST LAUNCHX  = 80	' launcher muzzle, well-pixel space
	CONST LAUNCHY  = 176
	CONST BXMIN    = 16	' ball CENTRE range; radius 8 inside an 8..151 well
	CONST BXMAX    = 144
	CONST HITD2    = 196	' collision accept: dx*dx + dy*dy < 14*14

	' !! NO `CONST` ABOVE 255 -- IT SILENTLY BECOMES ZERO.
	' The 8.8 fixed-point positions (launcher 80*256 = 20480, 176*256 = 45056;
	' wall planes 16*256 = 4096, 144*256 = 36864) were CONSTs and every one
	' compiled to `clr` / `ci r0,0`: the ball launched from 0,0 and neither wall
	' bounced. They are written as BARE LITERALS at each use site below, which
	' compiles correctly (`SOUND 0,300` -> `li r0,300`). This is the CVBasic
	' hazard in CLAUDE.md 3A; the distinction is CONST vs literal, not the value.
	CONST WARNLD   = 80	' frames before the drop at which the ALARM starts --
				' a full second ahead of the shake, so the player is
				' warned early enough to change the shot they are lining up
	CONST WARNGAP  = 15	' frames between alarm beeps (4 per second)
	CONST SHAKELD  = 20	' frames before the drop at which the telegraph starts
	CONST SHAKEN   = 2	' shake PHASES: out and back ONCE. The telegraph is
				' carried by the WARNING TONE (see the shake block);
				' the wiggle is just a visual accent, so it stays
				' short and costs the loop almost nothing.

	' HUD is LEFT-JUSTIFIED on COLUMN 22 -- the column the 9-digit score and high
	' score already start at, so every label's left edge lines up with them.
	' Offsets are row*32 + col.
	CONST SCPOS    = 54	' score,  9 digits, row 1  cols 22-30
	CONST HIPOS    = 150	' hi,     9 digits, row 4  cols 22-30
	' Round number sits one char in from the label's left edge (col 23), which
	' centres it under "ROUND" at px 192 -- the same centre as the NEXT bubble.
	CONST RNDPOS   = 247	' round,  2 digits, row 7  cols 23-24
	' "NEXT" is 4 chars from col 22 = px 176-207, so its centre is px 192; a
	' 16-px bubble centres under it at left edge 184, not flush at 176.
	CONST NEXTX    = 184
	CONST NEXTY    = 88

	DIM grid(96)		' 8 cols x 12 rows. bits 0-3 colour (0 = empty), bit 6 mark
	' 20 chars x 2 rows. THE WALLS LIVE IN THIS BUFFER TOO (at shkb and
	' shkb+17), so they shake with the field for free -- no separate wall
	' redraw, no vacated column to erase. That is what lets the field span the
	' full well and lets bubbles touch the walls.
	DIM rowbuf(40)
	DIM sc(8)		' score, BCD digits, sc(0) most significant
	DIM hs(8)		' high score
	DIM ad(6)		' 6-digit BCD addend fed to add_score
	DIM pres(9)		' pres(k) = 1 if colour k is still on the field

	'
	' ---------------------------------------------------------------- setup
	'
	CLS
	BORDER 1
	VDP(1) = $E2		' 16x16 sprites, NOT magnified (a bubble is 16 px)
	SPRITE FLICKER OFF	' all-or-nothing in CVBasic; we stay under 4 per line

	' All eight bubble colours share ONE 2x2 pattern; only DEFINE COLOR
	' differs. Eight calls against the same 32 bytes (see assets/genart.py).
	DEFINE CHAR 128,4,bub_pat
	DEFINE CHAR 132,4,bub_pat
	DEFINE CHAR 136,4,bub_pat
	DEFINE CHAR 140,4,bub_pat
	DEFINE CHAR 144,4,bub_pat
	DEFINE CHAR 148,4,bub_pat
	DEFINE CHAR 152,4,bub_pat
	DEFINE CHAR 156,4,bub_pat
	DEFINE COLOR 128,32,bub_col

	DEFINE CHAR 160,2,wall_pat
	DEFINE COLOR 160,2,wall_col
	DEFINE COLOR 32,16,txt_col
	DEFINE COLOR 48,16,txt_col
	DEFINE COLOR 64,16,txt_col
	DEFINE COLOR 80,16,txt_col

	' 16 bubble patterns: 2k = colour k+1's cap, 2k+1 its body. Each colour has
	' its own highlight size (genart.py), so they cannot share one pair.
	DEFINE SPRITE 0,16,spr_bub
	DEFINE SPRITE 16,1,spr_dot

	' Sprite colours are NOT declared here any more. They used to be a hand-kept
	' copy of the palette in genart.py, and when that palette changed this copy
	' did not: the flying bubble drew white-on-cyan while the landed one drew
	' cyan-on-light-blue. draw_sprites now reads bub_base/bub_lit, the tables
	' genart.py emits from the same data as the character colours.

	FOR i = 0 TO 7
		sc(i) = 0
		hs(i) = 0
	NEXT i

	GOTO title_screen

new_round:
	GOSUB load_level
	' scan_present MUST run before draw_field: it computes maxr, and draw_field
	' uses maxr to decide which rows to rebuild. With a stale maxr the level's
	' bubbles were simply not drawn until the first shot forced a rescan.
	GOSUB scan_present
	GOSUB draw_frame
	IF reveal = 1 THEN
		GOSUB do_reveal
	ELSE
		GOSUB draw_field
	END IF
	GOSUB prt_hud
	GOSUB pick_next
	curk = nxtk
	GOSUB pick_next
	aim = 31
	flying = 0
	btnr = 0
	reveal = 0

	'
	' ------------------------------------------------------------- main loop
	'
	' One pass per vblank, so the drop timer is counted in real frames and
	' needs no calibration on either target. The timer NEVER pauses during
	' play -- the game stays playable through the shake (DESIGN.md 8), which
	' is what makes that possible.
	'
game_loop:
	WAIT
	' Sprites FIRST, right at vblank. The flying bubble is two overlaid sprites
	' (base body + lit cap); updating them at the END of the loop, after the
	' collision work, let the retrace land between the two writes, so the cap
	' lagged the body by a frame and the ball in flight did not look like the
	' loaded and landed ones. Both writes now happen together at the top.
	GOSUB draw_sprites
	GOSUB sfx_tick

	' Frames elapsed since the last pass. Everything that moves scales by this,
	' so a pass that overran its frame (a shake redraw) does not slow the game.
	#fd = FRAME
	#fd = #fd - #lf
	#lf = FRAME
	IF #fd > 4 THEN #fd = 4
	IF #fd < 1 THEN #fd = 1
	fd = #fd

	IF #dropt > fd THEN
		#dropt = #dropt - fd
	ELSE
		#dropt = 0
	END IF

	' TWO-TONE ALARM -- the real telegraph, starting a full second before the
	' shake. Audio costs the loop nothing, so the warning can be long and clear
	' while the shake stays a single nudge (every shake phase is a full field
	' redraw, so its cost scales with how long it lasts -- the alarm's does not).
	' Counted down in FRAMES via fd, so the beep rate is steady even when a pass
	' overruns; a plain per-pass counter would slow the alarm exactly when the
	' loop got busy.
	IF #dropt <= WARNLD THEN
		IF warnon = 0 THEN
			warnon = 1
			warnt = 0
			warnf = 0
		END IF
		IF warnt > fd THEN
			warnt = warnt - fd
		ELSE
			warnt = WARNGAP
			warnf = 1 - warnf
			IF warnf = 0 THEN
				SOUND 1,180,12
			ELSE
				SOUND 1,135,12
			END IF
			sf1 = 7
		END IF
	ELSE
		warnon = 0
	END IF

	' Shake telegraph. Render-only: shkb feeds draw_row and NOTHING else, so
	' collision always uses the rest position and a shot fired just before a
	' shake lands exactly where it was aimed.
	' It settles CENTRED when the count runs out, so the board is at rest on the
	' frame the ceiling drops.
	' The shake is a fixed number of PHASES, not a parity of #dropt. Now that
	' #dropt decrements by fd, `#dropt AND 1` would hold the same parity every
	' pass whenever fd was even -- the board would stop wiggling altogether.
	' A phase counter also makes the nudge count exact and tunable (SHAKEN).
	IF #dropt > SHAKELD THEN
		shkb = 1
		shking = 0
	ELSE
		IF shking = 0 THEN
			shking = 1
			shkn = SHAKEN
		END IF
		IF shkn > 0 THEN shkn = shkn - 1
		' RIGHT / CENTRE wiggle: the board nudges to one side and back.
		' Left/right travelled two characters and read as a jump in both
		' directions; this halves the travel to the 8-px minimum a
		' char-aligned field can move at all.
		shkb = shkn AND 1
		shkb = shkb + 1
	END IF
	IF shkb <> shkbo THEN
		shkbo = shkb
		GOSUB draw_ceiling	' the ceiling slides with the walls it sits on
		GOSUB draw_field
	END IF
	IF #dropt = 0 THEN GOSUB do_drop

	GOSUB do_aim

	IF flying = 0 THEN
		IF btnr = 0 THEN
			IF cont1.button = 0 THEN btnr = 1
		ELSE
			IF cont1.button THEN GOSUB do_fire
		END IF
	END IF

	IF flying = 1 THEN GOSUB do_flight

	GOTO game_loop

	'
	' ------------------------------------------------------------------ aim
	'
	' aim runs 0..62 with 31 = straight up. am = distance from centre indexes
	' the table; bdir carries the sign, because CVBasic compiles every #var
	' comparison UNSIGNED and a signed velocity would break at every test.
	'
do_aim:
	IF cont1.left THEN
		IF aim > 0 THEN aim = aim - 1
	END IF
	IF cont1.right THEN
		IF aim < 62 THEN aim = aim + 1
	END IF
	IF aim >= 31 THEN
		am = aim - 31
		adir = 1
	ELSE
		am = 31 - aim
		adir = 0
	END IF
	RETURN

do_fire:
	flying = 1
	btnr = 0
	#bx = 20480		' LAUNCHX * 256 -- bare literal, see the note at the top
	#by = 45056		' LAUNCHY * 256
	bpx = LAUNCHX
	bpy = LAUNCHY
	#bdx = #aimdx(am)
	#bdy = #aimdy(am)
	bdir = adir
	SOUND 0,300,12
	sf0 = 4
	RETURN

	'
	' Every effect is ONE tone plus a decay countdown. Without the note-off the
	' last tone sustains forever ("sticky" sound); and two SOUND calls on the
	' same channel back to back just cancel the first, so effects that want two
	' notes get two channels, not two calls.
	' Called after EVERY WAIT in the program, including inside the animations.
	'
sfx_tick:
	IF sf0 > 0 THEN
		sf0 = sf0 - 1
		IF sf0 = 0 THEN SOUND 0,1000,0
	END IF
	IF sf1 > 0 THEN
		sf1 = sf1 - 1
		IF sf1 = 0 THEN SOUND 1,1000,0
	END IF
	RETURN

	'
	' -------------------------------------------------------------- flight
	'
	' Speed is 5 px/frame and the hit radius is 14 px, so one test per frame
	' cannot tunnel through a bubble -- no sub-stepping needed.
	'
	' Movement is paced by ELAPSED FRAMES, not by loop passes. A shake phase
	' carries a full field redraw, so during a shake a pass takes 2-3 frames --
	' and a ball advanced once per pass simply slowed down whenever the board
	' shook. Stepping fd times instead keeps real-world speed constant.
	' Each sub-step is a move plus one collision test (~9 cells), which is cheap
	' next to a redraw, so this does NOT become the RALLY-X feedback loop where
	' per-delta work makes a slow pass slower still.
do_flight:
	FOR fsi = 1 TO fd
		IF flying = 1 THEN GOSUB flight_step
	NEXT fsi
	RETURN

flight_step:
	#by = #by - #bdy
	IF bdir = 1 THEN
		#bx = #bx + #bdx
	ELSE
		#bx = #bx - #bdx
	END IF

	' Wall planes as BARE LITERALS: 16*256 and 144*256. As CONSTs these compiled
	' to `ci r0,0` and neither wall ever bounced. The compare is unsigned (`jl`),
	' which is why 36864 works despite being above 32767.
	' Wall planes are now the EDGE COLUMN CENTRES: 24*256 and 136*256. The field
	' spans the full well, so a bubble against a wall sits exactly in column 0
	' or column 7 -- bubbles touch the walls, as they should. (They used to
	' bounce 8 px short of the wall because the well was 2 chars wider than the
	' field to make room for the shake; the walls shake with the field now.)
	IF bdir = 0 THEN
		IF #bx < 6144 THEN
			#bx = 6144
			bdir = 1
			SOUND 0,150,10
			sf0 = 3
		END IF
	ELSE
		IF #bx > 34816 THEN
			#bx = 34816
			bdir = 0
			SOUND 0,150,10
			sf0 = 3
		END IF
	END IF

	bpx = #bx / 256
	bpy = #by / 256

	' Ceiling: grid row 0's centre sits at 16 + top*8.
	ct8 = top * 8
	ctc0 = ct8 + 16
	IF bpy <= ctc0 THEN
		strr = 0
		GOSUB snap_col
		GOSUB do_stick
		RETURN
	END IF

	GOSUB coltest
	IF cthit = 1 THEN GOSUB do_snap
	RETURN

	'
	' Nearest cell to the ball, then a PIXEL test against the 3x3 block of
	' cells around it. The cell index only picks candidates; the accept is
	' dx*dx + dy*dy < 14*14. A cell-occupancy test would read clean while
	' bubbles visibly overlap (a 16 px actor on a 16 px grid straddles two
	' cells for its whole traverse) -- assert on what you can see.
	'
coltest:
	cthit = 0
	gy = bpy - ct8			' grid-relative y keeps every term inside 8 bits
	IF gy < 16 THEN
		ctr = 0
	ELSE
		ctr = gy - 8
		ctr = ctr / 16
	END IF
	IF ctr > 11 THEN ctr = 11
	ctp = ctr AND 1
	ctx = 16 + ctp * 8
	IF bpx <= ctx THEN
		ctc = 0
	ELSE
		ctc = bpx - ctx
		ctc = ctc / 16
	END IF
	IF ctc > 7 THEN ctc = 7

	FOR ctdr = 0 TO 2
		ctok = 1
		IF ctdr = 0 THEN
			IF ctr = 0 THEN ctok = 0
			ctrr = ctr - 1
		END IF
		IF ctdr = 1 THEN ctrr = ctr
		IF ctdr = 2 THEN
			ctrr = ctr + 1
			IF ctrr > 11 THEN ctok = 0
		END IF
		IF ctok = 1 THEN
			ctpp = ctrr AND 1
			ctcy = 16 + ctrr * 16
			ctbs = ctrr * 8
			FOR ctdc = 0 TO 2
				ctk2 = 1
				IF ctdc = 0 THEN
					IF ctc = 0 THEN ctk2 = 0
					ctcc = ctc - 1
				END IF
				IF ctdc = 1 THEN ctcc = ctc
				IF ctdc = 2 THEN
					ctcc = ctc + 1
					IF ctcc > 7 THEN ctk2 = 0
				END IF
				IF ctpp = 1 THEN
					IF ctcc > 6 THEN ctk2 = 0
				END IF
				IF ctk2 = 1 THEN
					ctg = grid(ctbs + ctcc) AND 15
					IF ctg <> 0 THEN
						ctcx = 24 + ctcc * 16
						ctcx = ctcx + ctpp * 8
						IF bpx >= ctcx THEN
							ctdx = bpx - ctcx
						ELSE
							ctdx = ctcx - bpx
						END IF
						IF gy >= ctcy THEN
							ctdy = gy - ctcy
						ELSE
							ctdy = ctcy - gy
						END IF
						#c1 = ctdx
						#c1 = #c1 * #c1
						#c2 = ctdy
						#c2 = #c2 * #c2
						#c1 = #c1 + #c2
						IF #c1 < HITD2 THEN cthit = 1
					END IF
				END IF
			NEXT ctdc
		END IF
	NEXT ctdr
	RETURN

	'
	' Snap to the nearest FREE cell in the same 3x3 block, ranked by Manhattan
	' distance (enough to order 7 candidates, and it needs no multiply).
	'
do_snap:
	snb = 255
	snf = 0
	FOR sndr = 0 TO 2
		snok = 1
		IF sndr = 0 THEN
			IF ctr = 0 THEN snok = 0
			snrr = ctr - 1
		END IF
		IF sndr = 1 THEN snrr = ctr
		IF sndr = 2 THEN
			snrr = ctr + 1
			IF snrr > 11 THEN snok = 0
		END IF
		IF snok = 1 THEN
			snpp = snrr AND 1
			sncy = 16 + snrr * 16
			snbs = snrr * 8
			FOR sndc = 0 TO 2
				snk2 = 1
				IF sndc = 0 THEN
					IF ctc = 0 THEN snk2 = 0
					sncc = ctc - 1
				END IF
				IF sndc = 1 THEN sncc = ctc
				IF sndc = 2 THEN
					sncc = ctc + 1
					IF sncc > 7 THEN snk2 = 0
				END IF
				IF snpp = 1 THEN
					IF sncc > 6 THEN snk2 = 0
				END IF
				IF snk2 = 1 THEN
					IF (grid(snbs + sncc) AND 15) = 0 THEN
						sncx = 24 + sncc * 16
						sncx = sncx + snpp * 8
						IF bpx >= sncx THEN
							sndx = bpx - sncx
						ELSE
							sndx = sncx - bpx
						END IF
						IF gy >= sncy THEN
							sndy = gy - sncy
						ELSE
							sndy = sncy - gy
						END IF
						snd = sndx + sndy
						IF snd < snb THEN
							snb = snd
							strr = snrr
							stcc = sncc
							snf = 1
						END IF
					END IF
				END IF
			NEXT sndc
		END IF
	NEXT sndr
	IF snf = 0 THEN
		' Nowhere to go (shouldn't happen): drop the shot rather than wedge.
		flying = 0
		GOSUB next_shot
		RETURN
	END IF
	GOSUB do_stick
	RETURN

	' Ceiling landing picks the column directly.
snap_col:
	sccx = 16
	IF bpx <= sccx THEN
		stcc = 0
	ELSE
		stcc = bpx - sccx
		stcc = stcc / 16
	END IF
	IF stcc > 7 THEN stcc = 7
	RETURN

do_stick:
	flying = 0
	' Park the in-flight sprites IMMEDIATELY. after_stick runs the flood fills
	' and a full redraw with NO WAIT in between, so the sprite would otherwise
	' sit on top of the character bubble it just became for those frames --
	' reading as a doubled bubble that lingers after the ball lands.
	SPRITE 0,209,0,4,0
	SPRITE 1,209,0,0,0
	grid(strr * 8 + stcc) = curk
	IF strr > maxr THEN maxr = strr		' draw_field runs before scan_present
	SOUND 0,250,10
	sf0 = 3
	GOSUB draw_field
	GOSUB after_stick
	RETURN

	'
	' ------------------------------------------------- match, orphans, score
	'
after_stick:
	GOSUB clr_marks
	grid(strr * 8 + stcc) = curk OR 64
	pgcol = curk
	GOSUB propag
	GOSUB count_marks
	IF mkn >= 3 THEN
		GOSUB pop_marks
		ad(0) = 0 : ad(1) = 0 : ad(2) = 0 : ad(3) = 0
		ad(4) = mkn / 10
		ad(5) = mkn - ad(4) * 10
		GOSUB add_score
		GOSUB drop_orphans
	END IF
	GOSUB draw_field
	GOSUB scan_present
	GOSUB prt_hud
	IF nleft = 0 THEN
		GOSUB do_clear
		RETURN
	END IF
	GOSUB check_death
	IF dead = 1 THEN
		GOSUB do_dead
		RETURN
	END IF
	GOSUB next_shot
	RETURN

next_shot:
	curk = nxtk
	GOSUB pick_next
	RETURN

clr_marks:
	FOR cmi = 0 TO 95
		grid(cmi) = grid(cmi) AND 15
	NEXT cmi
	RETURN

count_marks:
	mkn = 0
	FOR cmi = 0 TO 95
		IF (grid(cmi) AND 64) <> 0 THEN mkn = mkn + 1
	NEXT cmi
	RETURN

pop_marks:
	FOR cmi = 0 TO 95
		IF (grid(cmi) AND 64) <> 0 THEN grid(cmi) = 0
	NEXT cmi
	SOUND 0,120,12
	sf0 = 5
	SOUND 1,90,10
	sf1 = 8
	RETURN

	'
	' Mark propagation, used for BOTH fills. No queue: repeat a full scan,
	' marking any cell adjacent to a marked one, until a pass changes nothing.
	' A worst-case queue would be ~96 bytes and ColecoVision has ~781 free, so
	' the scan buys the RAM back at a cost paid once per shot.
	'   pgcol <> 0 -> only cells of that colour   (the match group)
	'   pgcol  = 0 -> any occupied cell           (connected-to-ceiling)
	'
propag:
	pgloop = 1
	WHILE pgloop
		pgloop = 0
		FOR pgr = 0 TO 11
			pgb = pgr * 8
			FOR pgc = 0 TO 7
				pgi = pgb + pgc
				pgv = grid(pgi)
				IF (pgv AND 15) <> 0 THEN
					IF (pgv AND 64) = 0 THEN
						pgok = 1
						IF pgcol <> 0 THEN
							IF (pgv AND 15) <> pgcol THEN pgok = 0
						END IF
						IF pgok = 1 THEN
							GOSUB nbmark
							IF pgf = 1 THEN
								grid(pgi) = pgv OR 64
								pgloop = 1
							END IF
						END IF
					END IF
				END IF
			NEXT pgc
		NEXT pgr
	WEND
	RETURN

	'
	' pgf = 1 if any of (pgr,pgc)'s six hex neighbours carries the mark bit.
	' Offset-row layout: the two same-row neighbours are always c-1/c+1; the
	' four vertical ones are at columns c+p-1 and c+p, where p = r AND 1.
	' Every index is bounds-checked BEFORE it touches grid() -- a one-past-end
	' write is silent on TI and black-screens ColecoVision.
	'
nbmark:
	pgf = 0
	pgp = pgr AND 1
	pgn = pgc + pgp
	IF pgc > 0 THEN
		IF (grid(pgi - 1) AND 64) <> 0 THEN pgf = 1
	END IF
	IF pgc < 7 THEN
		IF (grid(pgi + 1) AND 64) <> 0 THEN pgf = 1
	END IF
	IF pgr > 0 THEN
		pgu = pgi - 8
		IF pgn > 0 THEN
			IF (grid(pgu + pgp - 1) AND 64) <> 0 THEN pgf = 1
		END IF
		IF pgn < 8 THEN
			IF (grid(pgu + pgp) AND 64) <> 0 THEN pgf = 1
		END IF
	END IF
	IF pgr < 11 THEN
		pgd = pgi + 8
		IF pgn > 0 THEN
			IF (grid(pgd + pgp - 1) AND 64) <> 0 THEN pgf = 1
		END IF
		IF pgn < 8 THEN
			IF (grid(pgd + pgp) AND 64) <> 0 THEN pgf = 1
		END IF
	END IF
	RETURN

	'
	' Anything that lost its anchor falls. The i-th dropped bubble is worth
	' 20 * 2^(i-1) POINTS = exactly 2^i UNITS OF 10, capped at i = 17
	' (131072 units = 1,310,720 points, the documented arcade maximum).
	'
drop_orphans:
	GOSUB clr_marks
	FOR doc = 0 TO 7
		IF (grid(doc) AND 15) <> 0 THEN grid(doc) = grid(doc) OR 64
	NEXT doc
	pgcol = 0
	GOSUB propag
	don = 0
	FOR doi = 0 TO 95
		IF (grid(doi) AND 15) <> 0 THEN
			IF (grid(doi) AND 64) = 0 THEN
				grid(doi) = 0
				don = don + 1
				dobi = don
				IF dobi > 17 THEN dobi = 17
				#dob = dobi - 1
				#dob = #dob * 6
				ad(0) = dropbcd(#dob)
				ad(1) = dropbcd(#dob + 1)
				ad(2) = dropbcd(#dob + 2)
				ad(3) = dropbcd(#dob + 3)
				ad(4) = dropbcd(#dob + 4)
				ad(5) = dropbcd(#dob + 5)
				GOSUB add_score
			END IF
		END IF
	NEXT doi
	IF don > 0 THEN
		SOUND 1,400,12
		sf1 = 12
	END IF
	RETURN

	'
	' sc() is 8 BCD digits shown with a literal trailing 0 -- every award in
	' this game is a multiple of 10, so the score is stored in UNITS OF 10.
	' A single capped drop award is 131072 units, already past a 16-bit
	' variable, so this is structural and not a nicety. Carry off the top
	' CLAMPS at 999,999,990 rather than rolling to zero.
	'
add_score:
	ascy = 0
	FOR asj = 0 TO 5
		asi = 5 - asj
		ast = sc(asi + 2) + ad(asi) + ascy
		IF ast > 9 THEN
			ast = ast - 10
			ascy = 1
		ELSE
			ascy = 0
		END IF
		sc(asi + 2) = ast
	NEXT asj
	FOR asj = 0 TO 1
		asi = 1 - asj
		IF ascy = 1 THEN
			ast = sc(asi) + 1
			IF ast > 9 THEN
				ast = 0
				ascy = 1
			ELSE
				ascy = 0
			END IF
			sc(asi) = ast
		END IF
	NEXT asj
	IF ascy = 1 THEN
		FOR asj = 0 TO 7
			sc(asj) = 9
		NEXT asj
	END IF
	FOR asj = 0 TO 7
		IF sc(asj) > hs(asj) THEN
			GOSUB copy_hi
			asj = 8
		ELSEIF sc(asj) < hs(asj) THEN
			asj = 8
		END IF
	NEXT asj
	RETURN

copy_hi:
	FOR chi = 0 TO 7
		hs(chi) = sc(chi)
	NEXT chi
	RETURN

	'
	' -------------------------------------------------------- level / rounds
	'
load_level:
	#lvb = lvl - 1
	#lvb = #lvb * 44
	FOR lli = 0 TO 95
		grid(lli) = 0
	NEXT lli
	FOR llr = 0 TO 10
		#llo = llr
		#llo = #llo * 4
		#llo = #llo + #lvb
		llbs = llr * 8
		FOR llc = 0 TO 7
			llh = llc / 2
			llv = pb_lay(#llo + llh)
			IF (llc AND 1) = 0 THEN
				llk = llv / 16
			ELSE
				llk = llv AND 15
			END IF
			grid(llbs + llc) = llk
		NEXT llc
	NEXT llr
	#lvm = lvl - 1
	#lvm = #lvm + #lvm
	ncol = pb_meta(#lvm)
	#droprl = pb_meta(#lvm + 1)
	#droprl = #droprl * 15		' quarter-seconds -> frames (60 Hz both targets)
	#dropt = #droprl
	#seqb = lvl - 1
	#seqb = #seqb * 16
	si = 0
	top = 0
	shkb = 1
	shkbo = 1
	shking = 0		' a round can end mid-shake; do not inherit the phase
	RETURN

	' Also tracks maxr, the lowest occupied grid row -- draw_field uses it to
	' skip rebuilding the identical empty rows beneath the field (see there).
	' Walked by row/column rather than a flat index so maxr needs no division.
scan_present:
	FOR spi = 1 TO 8
		pres(spi) = 0
	NEXT spi
	nleft = 0
	maxr = 0
	FOR spr = 0 TO 11
		spb = spr * 8
		FOR spc = 0 TO 7
			spk = grid(spb + spc) AND 15
			IF spk <> 0 THEN
				pres(spk) = 1
				nleft = nleft + 1
				maxr = spr
			END IF
		NEXT spc
	NEXT spr
	RETURN

	'
	' The shot sequence is FIXED per level -- a level is a puzzle, not a slot
	' machine. If the next entry's colour has left the field, walk FORWARD to
	' the first entry that is still present: deterministic, so the round still
	' replays identically, and it can never hand out a dead bubble.
	'
pick_next:
	pnf = 0
	FOR pni = 0 TO 31
		IF pnf = 0 THEN
			pnj = si + pni
			pnj = pnj AND 31
			#pnb = #seqb
			pnh = pnj / 2
			#pnb = #pnb + pnh
			pnv = pb_seq(#pnb)
			IF (pnj AND 1) = 0 THEN
				pnk = pnv / 16
			ELSE
				pnk = pnv AND 15
			END IF
			IF pnk > 0 THEN
				IF pres(pnk) = 1 THEN
					si = pnj + 1
					si = si AND 31
					nxtk = pnk
					pnf = 1
				END IF
			END IF
		END IF
	NEXT pni
	IF pnf = 0 THEN
		FOR pni = 1 TO 8
			IF pnf = 0 THEN
				IF pres(pni) = 1 THEN
					nxtk = pni
					pnf = 1
				END IF
			END IF
		NEXT pni
	END IF
	IF pnf = 0 THEN nxtk = 1
	RETURN

check_death:
	dead = 0
	FOR cdr = 0 TO 11
		cdw = CEILROW + top + cdr + cdr + 1
		IF cdw >= DEATHROW THEN
			cdb = cdr * 8
			FOR cdc = 0 TO 7
				IF (grid(cdb + cdc) AND 15) <> 0 THEN dead = 1
			NEXT cdc
		END IF
	NEXT cdr
	RETURN

	'
	' Ceiling drop: one CHARACTER row (8 px), half a bubble row. The field
	' stays character-aligned, so this is a pure translation -- no pattern
	' rebuild, no shifted variants.
	'
	' Settle the board back to CENTRE *first*. The drop fires while the shake is
	' still mid-phase, so shkb can be 2 here: filling the vacated row before the
	' reset drew that brick row at the shaken offset, and repainting only the
	' field left the whole ceiling skewed one character right -- draw_field no
	' longer repaints the ceiling (that is the shake's job), so nothing put it
	' back. Reset, then fill, then repaint BOTH.
do_drop:
	shkb = 1
	shkbo = 1
	shking = 0
	warnon = 0		' rearm the alarm for the next cycle
	bar = CEILROW + top
	GOSUB brick_at
	top = top + 1
	GOSUB draw_ceiling
	GOSUB draw_field
	SOUND 0,900,13
	sf0 = 12
	#dropt = #droprl
	GOSUB check_death
	IF dead = 1 THEN GOSUB do_dead
	RETURN

	'
	' Round clear: the last group popped, so everything left lost its anchor.
	' Slide the whole field down and off the bottom -- the same blit, walked
	' down one character row at a time.
	'
do_clear:
	' Same hazard as do_drop: the round can clear mid-shake, and the whole
	' closing animation would then run one character off-centre.
	shkb = 1
	shkbo = 1
	shking = 0
	GOSUB draw_ceiling
	' TWO character rows per step, 14 steps -- the wall closes at the same pace
	' the reveal opens (12 frames). One row per step was 27 frames AND each step
	' carried a growing ceiling repaint, so it crawled.
	FOR dcs = 0 TO 13
		bar = CEILROW + top
		GOSUB brick_at
		bar = bar + 1
		GOSUB brick_at
		top = top + 2
		GOSUB draw_field
		' DESCENDING sweep, one step per row-pair: the wall coming down.
		' Re-set every step, and sf1 is kept above zero so sfx_tick never
		' silences it mid-sweep; it decays on its own after the loop.
		#dct = dcs
		#dct = #dct * 60
		#dcf = 120
		#dcf = #dcf + #dct
		SOUND 1,#dcf,12
		sf1 = 3
		WAIT
		GOSUB sfx_tick
	NEXT dcs
	lvl = lvl + 1
	IF lvl > 30 THEN
		mrow = 11
		mcol = 10
		mlen = 12
		GOSUB msg_box
		PRINT AT 362,"ALL 30 CLEAR"
		FOR dcw = 0 TO 180
			WAIT
			GOSUB sfx_tick
		NEXT dcw
		GOTO title_screen
	END IF
	reveal = 1		' screen is solid brick now -- lift it to show the level
	GOTO new_round

do_dead:
	SOUND 0,800,13
	sf0 = 40
	FOR ddi = 0 TO 90
		WAIT
		GOSUB sfx_tick
	NEXT ddi
	IF lives > 0 THEN lives = lives - 1
	IF lives = 0 THEN
		mrow = 11
		mcol = 11
		mlen = 9
		GOSUB msg_box
		PRINT AT 363,"GAME OVER"
		FOR ddi = 0 TO 120
			WAIT
			GOSUB sfx_tick
		NEXT ddi
		GOTO title_screen
	END IF
	GOTO new_round

	'
	' ------------------------------------------------------------ rendering
	'
	' ONE primitive. draw_row builds a 18x2 character buffer for one grid
	' row-pair and blits it; shake varies the buffer offset, drop and slide
	' vary the destination row. A full field redraw is 12 x 36 = 432 bytes of
	' VDP in one frame -- under the 576 RALLY-X already blits per frame.
	'
	' A shake phase is one FULL redraw, so this routine's cost sets how fast the
	' board can shake. Rebuilding all 12 row-pairs took 2-3 frames per phase and
	' the shake visibly dragged. Rows BELOW the lowest bubble are identical to
	' each other (walls + blanks), so the buffer is built once and re-blitted --
	' only rows 0..maxr and the death-line row are rebuilt. Level 1 goes from 12
	' builds to 5. Removing the WAIT instead would just tear the field.
	' NOTE: this does NOT redraw the ceiling. Only the shake needs the ceiling
	' repainted (it slides with the walls); a drop or a slide has already filled
	' the newly vacated rows via brick_at, and repainting the whole ceiling every
	' step made the closing wall get slower the further down it got -- the
	' ceiling grows as it descends, so the per-step cost grew with it.
draw_field:
	dfe = 0
	FOR dfr = 0 TO 11
		drr = dfr
		drw = CEILROW + top + dfr + dfr
		dfn = 0
		IF dfr <= maxr THEN dfn = 1
		IF drw = DEATHROW THEN dfn = 1
		IF drw + 1 = DEATHROW THEN dfn = 1
		IF dfn = 1 THEN
			GOSUB draw_row
			dfe = 0
		ELSE
			IF dfe = 0 THEN
				GOSUB build_empty
				dfe = 1
			END IF
			GOSUB blit_row
		END IF
	NEXT dfr
	RETURN

	' Round transition, the mirror of do_clear: the closing wall has filled the
	' screen with brick, so the next level is revealed by lifting that wall --
	' uncover one row-pair per frame from the BOTTOM up, and the brick above
	' each uncovered pair is simply what has not been painted over yet. Row 0
	' stays brick throughout: it is the ceiling.
do_reveal:
	GOSUB fill_brick
	FOR rvi = 0 TO 23
		#rvd = rvi
		#rvd = #rvd * 32
		SCREEN rowbuf,0,#rvd,20,1,20
	NEXT rvi
	FOR rvi = 0 TO 11
		drr = 11 - rvi
		GOSUB draw_row
		' RISING sweep, the mirror of the closing wall's descent.
		#rvt = rvi
		#rvt = #rvt * 70
		#rvf = 960
		#rvf = #rvf - #rvt
		SOUND 1,#rvf,12
		sf1 = 4
		WAIT			' two frames a step -- the reveal is the level
		GOSUB sfx_tick		' being introduced, so it wants a little more
		WAIT			' room than the close, which is a dismissal
		GOSUB sfx_tick
	NEXT rvi
	RETURN

	' Walls and blanks only -- what every row below the field looks like.
build_empty:
	FOR dri = 0 TO 39
		rowbuf(dri) = BLANK
	NEXT dri
	rowbuf(shkb) = WALLCH
	rowbuf(shkb + 17) = WALLCH
	rowbuf(shkb + 20) = WALLCH
	rowbuf(shkb + 37) = WALLCH
	RETURN

	' One row-pair, walls included, blitted at screen column 0 across 20 chars.
	' Wall columns are shkb and shkb+17; the field starts one char inside the
	' left wall at shkb+1. So the ENTIRE assembly -- walls and bubbles together
	' -- slides as one unit and nothing outside it ever needs erasing.
	' The death line is painted as the row FILL rather than drawn separately,
	' because these blits pass straight over row DEATHROW.
draw_row:
	drw = CEILROW + top + drr + drr
	GOSUB build_empty
	' The death line is painted only BETWEEN the walls (buffer shkb+1..shkb+16).
	' Filling the whole 20-char row with it left dashes sticking out past both
	' walls, which then slid around during the shake.
	IF drw = DEATHROW THEN
		FOR dri = 1 TO 16
			rowbuf(shkb + dri) = DASHCH
		NEXT dri
	END IF
	drv = drw + 1
	IF drv = DEATHROW THEN
		FOR dri = 21 TO 36
			rowbuf(shkb + dri) = DASHCH
		NEXT dri
	END IF
	drp = drr AND 1
	drb = drr * 8
	FOR drc = 0 TO 7
		drk = grid(drb + drc) AND 15
		IF drk <> 0 THEN
			drx = shkb + 1 + drc + drc + drp
			drh = 124 + drk * 4
			rowbuf(drx) = drh
			rowbuf(drx + 1) = drh + 1
			rowbuf(drx + 20) = drh + 2
			rowbuf(drx + 21) = drh + 3
		END IF
	NEXT drc
blit_row:
	IF drw < 23 THEN
		#drd = drw
		#drd = #drd * 32
		SCREEN rowbuf,0,#drd,20,2,20
	ELSEIF drw = 23 THEN
		#drd = drw
		#drd = #drd * 32
		SCREEN rowbuf,0,#drd,20,1,20
	END IF
	RETURN

	' The ceiling is SOLID BRICK and grows downward as it descends: the row the
	' field just vacated is filled in, not blanked, so the wall visibly closes in
	' from the top rather than leaving a gap.
	' The ceiling is exactly as wide as the walls below it (18 chars, cols
	' shkb..shkb+17) and shakes with them -- it used to be a fixed 20 wide,
	' which left a brick nub sticking out past each wall. Blanks fill the rest
	' of the 20-char blit so the vacated column is cleared as it slides.
brick_at:
	IF bar > 23 THEN RETURN
	GOSUB fill_brick
	#bad = bar
	#bad = #bad * 32
	SCREEN rowbuf,0,#bad,20,1,20
	RETURN

fill_brick:
	FOR bai = 0 TO 19
		rowbuf(bai) = BLANK
	NEXT bai
	FOR bai = 0 TO 17
		rowbuf(shkb + bai) = WALLCH
	NEXT bai
	RETURN

	' Every brick row from the screen top down to just above grid row 0.
draw_ceiling:
	dcn = CEILROW + top
	IF dcn > 24 THEN dcn = 24
	GOSUB fill_brick
	FOR dcr = 0 TO dcn - 1
		#dcd = dcr
		#dcd = #dcd * 32
		SCREEN rowbuf,0,#dcd,20,1,20
	NEXT dcr
	RETURN

	' HUD labels, right-justified to end at column 30 (one char of space at the
	' right edge). The walls are NOT drawn here any more -- draw_row owns them.
draw_frame:
	' CLEAR THE WHOLE SCREEN FIRST. Every playfield blit is 20 characters wide at
	' column 0, so nothing in the normal draw path ever touches the HUD panel
	' (columns 20-31) -- and the title screen writes well into it (the credit line
	' reaches column 26, the bubble rows column 25). Without this, title text sat
	' in the panel for the whole game. The reveal repaints its own brick right
	' after, so there is no flash.
	CLS
	GOSUB draw_ceiling
	' All on column 22, aligned with the score digits below each one.
	PRINT AT 22,"1UP"
	PRINT AT 118,"HI"
	PRINT AT 214,"ROUND"
	PRINT AT 342,"NEXT"		' row 10, so the bubble sits directly beneath it
	PRINT AT 502,"TIME"
	RETURN

	' !! VPOKE TAKES A RAW VRAM ADDRESS -- THE NAME TABLE IS AT $1800 (6144).
	' Writing 0..767 goes into the PATTERN table instead, which corrupts the
	' character set: it showed as a field of dots over the whole screen, missing
	' walls, and garbled digits. 6144 is added as its OWN step, never folded into
	' a constant expression (a folded constant truncates -- CLAUDE.md 3A).
	' SCREEN is different: its target offset IS name-table-relative.
prt_hud:
	FOR psi = 0 TO 7
		#psa = SCPOS + psi
		#psa = #psa + 6144
		psv = 48 + sc(psi)
		VPOKE #psa,psv
		#psa = HIPOS + psi
		#psa = #psa + 6144
		psv = 48 + hs(psi)
		VPOKE #psa,psv
	NEXT psi
	#psa = SCPOS + 8
	#psa = #psa + 6144
	psv = 48
	VPOKE #psa,psv
	#psa = HIPOS + 8
	#psa = #psa + 6144
	VPOKE #psa,psv
	psh = lvl / 10
	#psa = RNDPOS
	#psa = #psa + 6144
	psv = 48 + psh
	VPOKE #psa,psv
	#psa = RNDPOS + 1
	#psa = #psa + 6144
	psv = lvl - psh * 10
	psv = 48 + psv
	VPOKE #psa,psv
	RETURN

	'
	' Sprites: flying bubble (body + lit cap, so it is pixel-identical to the
	' same bubble once it sticks and becomes characters), the next bubble, and
	' three aim-guide dots placed along the ray with the SAME table the shot
	' uses -- no rotated-arrow artwork.
	'
draw_sprites:
	IF flying = 1 THEN
		dsx = bpx - 8
		dsy = bpy - 9
	ELSE
		dsx = LAUNCHX - 8
		dsy = LAUNCHY - 9
	END IF
	' Pattern frame = def * 4, and colour k uses defs 2(k-1) and 2(k-1)+1, so the
	' cap frame is (k-1)*8 and the body frame is that + 4.
	dsf = curk - 1
	dsf = dsf * 8
	dsc = bub_base(curk - 1)
	dsl = bub_lit(curk - 1)
	SPRITE 0,dsy,dsx,dsf + 4,dsc
	SPRITE 1,dsy,dsx,dsf,dsl
	dsf = nxtk - 1
	dsf = dsf * 8
	dsc = bub_base(nxtk - 1)
	dsl = bub_lit(nxtk - 1)
	SPRITE 2,NEXTY - 1,NEXTX,dsf + 4,dsc
	SPRITE 3,NEXTY - 1,NEXTX,dsf,dsl
	IF flying = 0 THEN
		#gux = #aimdx(am)
		#gux = #gux * 4
		#gux = #gux / 256
		gux = #gux
		#guy = #aimdy(am)
		#guy = #guy * 4
		#guy = #guy / 256
		guy = #guy
		FOR gi = 1 TO 3
			gdd = gux * gi
			IF adir = 1 THEN
				gpx = LAUNCHX + gdd
			ELSE
				gpx = LAUNCHX - gdd
			END IF
			gpy = guy * gi
			gpy = LAUNCHY - gpy
			SPRITE 3 + gi,gpy - 9,gpx - 8,64,15
		NEXT gi
	ELSE
		SPRITE 4,209,0,64,0
		SPRITE 5,209,0,64,0
		SPRITE 6,209,0,64,0
	END IF
	RETURN

	'
	' ---------------------------------------------------------- title screen
	'
	' Fire starts a game. Typing 8 3 8 opens a round selector -- the same secret
	' the other games in this repo use, and deliberately not advertised on screen.
	' The chosen round lasts ONE game: coming back here always resets to round 1.
	'
title_screen:
	stlv = 1
	GOSUB hide_sprites
	CLS
	' Two decorative rows showing all eight bubble colours, built in the same
	' row buffer the playfield uses.
	tby = 3
	GOSUB title_bubbles
	tby = 15
	GOSUB title_bubbles
	PRINT AT 265,"BUST-A-BOBBLE"
	PRINT AT 356,"2026 UNHUMAN AND CLAUDE"
	PRINT AT 678,"PRESS FIRE TO START"
	t8 = 0
	tkl = 15
	btnr = 0

title_wait:
	WAIT
	GOSUB sfx_tick
	' Edge-triggered 8-3-8. cont1.key gives 0-9 on both targets (TI keyboard,
	' Coleco keypad) and 15 for nothing, so this is portable.
	tk = cont1.key
	IF tk <> tkl THEN
		tkl = tk
		IF tk = 8 THEN
			IF t8 = 2 THEN
				GOSUB setup838
				GOTO title_go
			END IF
			t8 = 1
		END IF
		IF tk = 3 THEN
			IF t8 = 1 THEN
				t8 = 2
			ELSE
				t8 = 0
			END IF
		END IF
	END IF
	' Require a RELEASE before the press, so a button still held from the
	' previous game cannot skip straight past the title.
	IF btnr = 0 THEN
		IF cont1.button = 0 THEN btnr = 1
	ELSE
		IF cont1.button THEN GOTO title_go
	END IF
	GOTO title_wait

title_go:
	lvl = stlv
	lives = 3
	FOR tgi = 0 TO 7
		sc(tgi) = 0
	NEXT tgi
	reveal = 0
	GOTO new_round

	' One row-pair of all eight bubble colours, centred, at character row tby.
title_bubbles:
	FOR tbi = 0 TO 39
		rowbuf(tbi) = BLANK
	NEXT tbi
	FOR tbi = 0 TO 7
		tbc = 128 + tbi * 4
		tbx = tbi + tbi + 2
		rowbuf(tbx) = tbc
		rowbuf(tbx + 1) = tbc + 1
		rowbuf(tbx + 20) = tbc + 2
		rowbuf(tbx + 21) = tbc + 3
	NEXT tbi
	#tbd = tby
	#tbd = #tbd * 32
	#tbd = #tbd + 6
	SCREEN rowbuf,0,#tbd,20,2,20
	RETURN

	' Blank a rectangle one character bigger than the message on every side, so
	' the text sits in a clean black box instead of on top of the bubble field.
	' Caller sets mrow / mcol / mlen, then PRINTs the message itself.
msg_box:
	FOR mbi = 0 TO 39
		rowbuf(mbi) = BLANK
	NEXT mbi
	mbw = mlen + 2
	FOR mbr = 0 TO 2
		#mba = mrow - 1 + mbr
		#mba = #mba * 32
		#mba = #mba + mcol - 1
		SCREEN rowbuf,0,#mba,mbw,1,mbw
	NEXT mbr
	RETURN

hide_sprites:
	FOR hsi = 0 TO 8
		SPRITE hsi,209,0,0,0
	NEXT hsi
	RETURN

	' Round selector: two digits, 01-30, echoed as they are typed.
setup838:
	CLS
	PRINT AT 266,"SELECT ROUND"
	PRINT AT 360,"ENTER TWO DIGITS"
	rdp = 463
	GOSUB rd_dig
	sd1 = tdg
	GOSUB rd_dig
	stlv = sd1 * 10 + tdg
	IF stlv < 1 THEN stlv = 1
	IF stlv > 30 THEN stlv = 30
	RETURN

rd_dig:
rd_rel:
	WAIT
	IF cont1.key <> 15 THEN GOTO rd_rel
rd_get:
	WAIT
	tdg = cont1.key
	IF tdg > 9 THEN GOTO rd_get
	#rda = rdp
	#rda = #rda + 6144
	rdv = 48 + tdg
	VPOKE #rda,rdv
	rdp = rdp + 1
	SOUND 0,250,10
	sf0 = 3
	RETURN

	'
	' -------------------------------------------------------------- art data
	'
	' 160 = BRICK, running bond: a mortar course every 4 rows with the vertical
	' joints offset between courses. Used for the walls AND the ceiling, so the
	' ceiling filling in as it descends reads as the wall closing in.
	' 161 = death-line dash.
wall_pat:
	DATA BYTE $00,$EE,$EE,$EE,$00,$BB,$BB,$BB
	DATA BYTE $00,$00,$00,$3C,$3C,$00,$00,$00
	' Grey brick face over black mortar; dark red dash on black.
wall_col:
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $61,$61,$61,$61,$61,$61,$61,$61
	' DEFINE COLOR takes EIGHT bytes per character (one per scan line), so
	' `DEFINE COLOR 32,16,txt_col` reads 16 x 8 = 128 bytes. Supplying only 16
	' made it read 112 bytes of whatever followed in ROM as colour data --
	' the text came out in random colours. Same shape as Structris's txt_white.
txt_col:
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

	INCLUDE "art.bas"
	INCLUDE "levels.bas"
