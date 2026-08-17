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

	' TI-99 ONLY: the level data lives in a ROM BANK, not in the fixed area.
	'
	' The fixed area -- all code plus any data read DURING a frame -- caps at
	' 24,336 bytes and had 68 left. The 1,860 bytes of level data qualify for a
	' bank because they are read only at round start and when a shot is taken,
	' never from the vblank ISR. The music tables do NOT qualify and stay put:
	' the player refills the sound chip from the ISR, where bank switching is
	' unsafe. So the levels move and the music stays.
	'
	' The cart does not grow. Pages = 3 loader + one per bank, rounded UP to a
	' power of two: 3 + 1 = 4 pages = 32 KB, which is what it already was. A
	' SECOND bank would make 5 pages, which rounds to 8 = 64 KB -- so anything
	' banked later belongs in bank 1 beside the levels (it has ~6 KB spare),
	' not in a bank of its own. That mistake doubled RALLY-X's cart.
	'
	' ColecoVision does not bank: its Z80 build is 16 KB against a flat 32 KB
	' budget, and turning banking on there would switch it to a Megacart image
	' for no gain. Hence the #if -- the two targets now differ in where the
	' level data sits, so BOTH builds have to be run on every data change.
	'
	' THE 128 IS NOT THE CART SIZE. `BANK ROM` only accepts 128, 256, 512 or
	' 1024 (it sizes ColecoVision's Megacart mapper; `BANK ROM 32` is rejected
	' outright). On TI the cart size comes from the number of bank FILES the
	' assembler emits, so one bank gives a 32 KB cart despite the 128 here --
	' RALLY-X declares 128 too and packs to 64 KB with its five banks.
#if TI994A
	BANK ROM 128
#endif

	CONST NROWS    = 12	' grid rows (11 come from level data, 12th is headroom)
	CONST WELLCOL  = 1	' first character column inside the well
	CONST CEILROW  = 1	' character row of grid row 0 when top = 0
	CONST DEATHROW = 20	' a bubble whose BOTTOM reaches this row ends the round
	CONST BLANK    = 32
	CONST WALLCH   = 160	' solid block: walls + ceiling bar
	CONST DASHCH   = 161	' death-line dash

	CONST LAUNCHX  = 80	' launcher muzzle, well-pixel space
	' LAUNCHY moved DOWN one character row, 176 -> 184. Every trajectory in the game
	' changes with it: the ray starts 8 px lower, so each aim step now reaches a
	' slightly different cell and the bank patterns off the walls shift. All 30
	' rounds were re-proven winnable with solvelevels.py afterwards -- a launcher
	' move is a GEOMETRY change, not a cosmetic one.
	CONST LAUNCHY  = 184
	CONST BXMIN    = 16	' ball CENTRE range; radius 8 inside an 8..151 well
	CONST BXMAX    = 144
	CONST HITD2    = 196	' collision accept: dx*dx + dy*dy < 14*14

	' !! NO `CONST` ABOVE 255 -- IT SILENTLY BECOMES ZERO.
	' The 8.8 fixed-point positions (launcher 80*256 = 20480, 184*256 = 47104;
	' wall planes 16*256 = 4096, 144*256 = 36864) were CONSTs and every one
	' compiled to `clr` / `ci r0,0`: the ball launched from 0,0 and neither wall
	' bounced. They are written as BARE LITERALS at each use site below, which
	' compiles correctly (`SOUND 0,300` -> `li r0,300`). This is the CVBasic
	' hazard in CLAUDE.md 3A; the distinction is CONST vs literal, not the value.
	' MUSIC. Two voices at a deliberately low volume so the effects stay on top.
	' MELODY IS ON CHANNEL 2 AND BASS ON CHANNEL 1, which is not arbitrary: every
	' sound effect in this game lives on channels 0 and 1, so putting the melody on
	' the one channel nothing else touches means the tune is never chopped. The bass
	' is interrupted now and then by the alarm, a pop or a drop, and simply resumes
	' at its next note -- a gap of at most an eighth, which reads as the effect
	' ducking the music rather than as the music breaking.
	CONST MUSTICK  = 6	' frames per sixteenth -> 900/6 = 150 BPM
	' Music sits WELL under the effects, which run 8-13. At 10/8 it was level with
	CONST MUSVOL   = 7	' them and drowned the pop, which is the sound that
	CONST MUSBAS   = 5	' actually carries information.
	' !! THE SONG LENGTH IS A BARE LITERAL, AND IT HAS TO BE. It has now broken TWICE
	' as the identical symptom -- the tune playing its first note for ever, sounding
	' like one long beep with nothing visibly wrong:
	'   1. `CONST MUSLEN = 256`. A CONST above 255 compiles to ZERO here.
	'   2. `CONST MUSLEN = 192` emitted into music.bas, which is INCLUDEd after all
	'      of the code. CVBasic accepted the forward reference as an UNDEFINED
	'      8-BIT VARIABLE holding zero -- `movb @cvb_MUSLEN,r0` in the listing.
	' Either way `#mup >= MUSLEN` became `>= 0`, always true unsigned, so the song
	' reset every tick. genmusic.py now reads this file and fails if the literal
	' below does not match the tune it just generated.
	' exactly like the fixed-point wall planes at the top of this file. As a CONST it
	' made `IF #mup >= MUSLEN` read `>= 0`, which is always true on an unsigned
	' compare, so the song reset to step 0 every tick and played its first note
	' forever. It sounded like one long beep and nothing else looked wrong.
	' The literal 256 is written at its use site in mus_step instead.
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
	' Orphans falling away after a drop, animated as SPRITES (slots 8..31).
	' Sprites cost ONE call each per frame and the VDP erases them for us; the
	' character equivalent would be 8 VPOKEs each per frame, which is well past
	' what a frame will carry.
	' CAP RAISED 12 -> 24, which is every sprite slot left after the flying bubble
	' (0-1), the next bubble (2-3) and the aim dots (4-6). At 12 the overflow did
	' not merely skip the animation -- those bubbles VANISHED on the spot while
	' their neighbours fell. And because drop_orphans walks the grid top-down, the
	' ones that vanished were always the LOWEST, which is exactly where the eye
	' is: reported as "the gray balls didn't drop, they disappeared" on round 10,
	' whose greys sit in the bottom row.
	DIM ofr(24)		' grid row
	DIM ofcl(24)		' grid column
	DIM ofk(24)		' colour
	DIM ofxx(24)		' pixel x (fixed for the whole fall)
		DIM ofyy(24)		' pixel y, advanced per frame

	' The two title-screen creatures, one array slot each. Arrays rather than two
	' sets of scalars so the behaviour is written ONCE and simply runs twice -- with
	' CVBasic having no locals or parameters, duplicated code is how these drift
	' apart. Each guy owns his position, direction, step and leg phase, his state
	' (0 walking, 1 waving), his countdown to the next state change, his wave phase,
	' and his own patrol bounds.
	DIM twx(2)
	DIM twdir(2)
	DIM twt(2)
	DIM twf(2)
	DIM twst(2)
	DIM twtm(2)
	DIM twwf(2)
	DIM twlo(2)
	DIM twhi(2)
	DIM twside(2)

	'
	' ---------------------------------------------------------------- setup
	'
	' SELECT THE LEVEL BANK ONCE, HERE, AND NEVER SWITCH AGAIN.
	'
	' Bank 1 holds pb_lay / pb_seq / pb_meta and nothing else, so there is no
	' reason to ever page it out -- and every reason not to. `pb_seq` is read on
	' every shot (pick_next) and `pb_lay` at every round start, so a scheme that
	' switched back and forth would need a select before each of those reads and
	' would silently return bytes from the wrong page if one were missed. There is
	' no compile-time or run-time error for that. One select, at startup, removes
	' the whole class of bug.
	'
	' IF A SECOND BANK IS EVER ADDED: every read of pb_lay / pb_seq / pb_meta
	' must then be preceded by `BANK SELECT 1`, and none of it may happen inside
	' the vblank ISR (mus_tick), where bank switching is unsafe.
#if TI994A
	BANK SELECT 1
#endif
	CLS
	BORDER 1
	VDP(1) = $E2		' 16x16 sprites, NOT magnified (a bubble is 16 px)
	SPRITE FLICKER OFF	' all-or-nothing in CVBasic; we stay under 4 per line

	' Bubble characters are PER COLOUR now (32 chars in one call): cyan and
	' magenta are dithered, which needs their own pixels, not just their own
	' colour -- a two-colours-per-line display can only shade by pixel density.
	DEFINE CHAR 128,32,bub_pat
	DEFINE COLOR 128,32,bub_col

	DEFINE CHAR 160,2,wall_pat
	DEFINE COLOR 160,2,wall_col
	DEFINE CHAR 164,12,bur_pat	' 3 pop frames x 4 chars
	DEFINE COLOR 164,12,bur_col
	' Drop-timer gauge (9 fill widths) and the spare-life creature.
	DEFINE CHAR 176,9,bar_pat
	barw = 0
	GOSUB set_bar_col
	' Bubbles carrying the death line through their middle (see draw_row).
	DEFINE CHAR 186,32,bub_patx
	DEFINE COLOR 186,32,bub_colx
	DEFINE CHAR 185,1,life_pat
	DEFINE COLOR 185,1,life_col
	' Text is white-on-black for every printable character, so ONE 8-byte row does
	' for all 64 of them. It used to be a 128-byte table (16 chars' worth) issued
	' four times -- 120 bytes of the same eight values repeated, which is a lot of
	' ROM to spend saying "white" sixteen times.
	FOR i = 32 TO 95
		DEFINE COLOR i,1,txt_col
	NEXT i

	' 16 bubble patterns: 2k = colour k+1's cap, 2k+1 its body. Each colour has
	' its own highlight size (genart.py), so they cannot share one pair.
	' ONE sprite pattern per bubble colour (0-7), not three. The cap/body pair that
	' used to sit either side of the full ball existed so the flying bubble could be
	' two overlaid sprites in a lit shade and a base shade -- and the dither rewrite
	' made every ball a SINGLE hue, so those two sprites became the same colour
	' drawn twice. 512 bytes of pattern table, recovered.
	DEFINE SPRITE 0,8,spr_bub
	DEFINE SPRITE 8,1,spr_dot
	' 25-26 = the creature at 2x, two walk frames; 27-28 = his waving arm.
	DEFINE SPRITE 9,2,spr_walk
	DEFINE SPRITE 11,4,spr_wave

	' Sprite colours are NOT declared here any more. They used to be a hand-kept
	' copy of the palette in genart.py, and when that palette changed this copy
	' did not: the flying bubble drew white-on-cyan while the landed one drew
	' cyan-on-light-blue. draw_sprites now reads bub_base/bub_lit, the tables
	' genart.py emits from the same data as the character colours.

	FOR i = 0 TO 7
		sc(i) = 0
		hs(i) = 0
	NEXT i

	' Base addresses of the music tables, resolved once.
	#musf = VARPTR mus_freq(0)
	#muss = VARPTR mus_song(0)
	mut = 0				' player stopped until a round starts
	musen = 1			' music on by default; the title toggles it with 1

	GOTO title_screen

new_round:
	' Clear every slot first. A bubble is one sprite now, so the round only ever
	' uses 0 (flying), 2 (next) and 4-6 (aim dots) -- and the title screen leaves
	' its creatures in 1 and 3, which would otherwise stand there through the game.
	GOSUB hide_sprites
	GOSUB mus_start			' the tune belongs to the round, not the title
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
	musdin = fd
	GOSUB mus_tick

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
				SOUND 1,330,12
			ELSE
				SOUND 1,260,12
			END IF
			sf1 = 7
		END IF
	ELSE
		warnon = 0
	END IF

	GOSUB tick_bar

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
	' --------------------------------------------------------- drop-timer bar
	'
	' The drop clock was completely invisible: the HUD printed a "TIME" label
	' with nothing under it, so the only warning was the alarm 1.3 s out. The
	' gauge is 8 characters wide and drains RIGHT TO LEFT in 64 steps -- each
	' character carries nine fill widths (0-8 px), so it creeps rather than
	' jumping in eighths.
	'
	' Redrawn only when the pixel count actually changes: at most 64 times per
	' drop cycle instead of 8 VPOKEs every frame.
	'
tick_bar:
	#tbx = #dropt
	#tbx = #tbx / #bstep
	tbpx = #tbx
	IF tbpx > 64 THEN tbpx = 64
	' Fill turns RED for the last QUARTER of the gauge, not for the last second.
	' Keying it to the alarm instead (`warnon`) put the colour change 1.3 s out,
	' by which point only ~4 of the 64 pixels are still lit -- there was almost no
	' bar left to be red, so the cue was invisible. A quarter is 5 s at round 1
	' and 3 s at round 30, and it comfortably contains both the alarm and the
	' board shake. DEFINE COLOR is re-issued only on the transition.
	tbwant = 0
	IF tbpx < 17 THEN tbwant = 1
	IF tbwant <> barw THEN
		barw = tbwant
		GOSUB set_bar_col
	END IF
	IF tbpx <> barlast THEN
		barlast = tbpx
		GOSUB draw_bar
	END IF
	RETURN

	' Paint all nine gauge characters from one 8-byte row -- green normally, red
	' once barw is set. Called only on a transition (twice a drop cycle), so nine
	' DEFINE COLORs cost nothing next to the 128 bytes of duplicated table they
	' replace.
set_bar_col:
	FOR bci = 176 TO 184
		IF barw = 1 THEN
			DEFINE COLOR bci,1,bar_colw
		ELSE
			DEFINE COLOR bci,1,bar_col
		END IF
	NEXT bci
	RETURN

	' Row 16, columns 22-29 -- directly under the "TIME" label on column 22.
	' 534 = 16*32 + 22 is written as a BARE LITERAL: a CONST above 255 silently
	' compiles to zero on this toolchain (see the note at the top of the file).
draw_bar:
	tbf = barlast / 8		' whole cells filled
	tbr = barlast - tbf * 8		' leftover pixels in the next cell
	#tba = 534
	#tba = #tba + 6144
	FOR tbi = 0 TO 7
		IF tbi < tbf THEN
			tbv = 184
		ELSEIF tbi = tbf THEN
			tbv = 176 + tbr
		ELSE
			tbv = 176
		END IF
		VPOKE #tba,tbv
		#tba = #tba + 1
	NEXT tbi
	RETURN

	'
	' SPARE LIVES -- the little green creature, one per life IN RESERVE.
	' Repo convention (CLAUDE.md 7A): the indicator shows SPARES, excluding the
	' life being played, so a fresh 3-life game shows TWO and the last life shows
	' none. `lives` is unsigned and do_dead decrements it BEFORE this redraws, so
	' the guard matters: a bare `lives - 1` at zero wraps to 255 and would light
	' every slot exactly when the player has none.
	'
prt_lives:
	plv = 0
	IF lives > 0 THEN plv = lives - 1
	' Row 18, column 22 -- two rows under the gauge. DESIGN.md originally put this
	' on row 23; that is the last row on the screen, which sits in TV overscan on
	' real hardware and was clipped entirely in Classic99, so the one HUD element
	' that tells you how much game is left was the one you could not see.
	#pla = 598			' 18*32 + 22, bare literal for the same reason
	#pla = #pla + 6144
	FOR pli = 0 TO 4
		IF pli < plv THEN
			plc = 185
		ELSE
			plc = BLANK
		END IF
		VPOKE #pla,plc
		#pla = #pla + 2		' a blank column between creatures
	NEXT pli
	RETURN

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
	#by = 47104		' LAUNCHY * 256
	bpx = LAUNCHX
	bpy = LAUNCHY
	#bdx = #aimdx(am)
	#bdy = #aimdy(am)
	bdir = adir
	SOUND 0,480,10
	sf0 = 4
	RETURN

	'
	' Every effect is ONE tone plus a decay countdown. Without the note-off the
	' last tone sustains forever ("sticky" sound); and two SOUND calls on the
	' same channel back to back just cancel the first, so effects that want two
	' notes get two channels, not two calls.
	' Called after EVERY WAIT in the program, including inside the animations.
	'
	'
	' The tick used INSIDE the animations (burst, orphan fall). Those loops run
	' their own WAITs with the main loop stopped, so the drop clock used to stand
	' still for their whole duration -- 6 frames for a burst plus 27 for a fall,
	' better than half a second of free time on every popping shot, which is most
	' of them. The clock is the game's only pressure, so pausing it whenever the
	' player did something good was exactly backwards.
	'
	' The DROP ITSELF is deliberately not fired here, only the countdown: a drop
	' mid-animation would move the field out from under a burst that is painted at
	' fixed cells. #dropt is allowed to reach 0 and sit there; the main loop's
	' `IF #dropt = 0 THEN GOSUB do_drop` fires on the next pass, so the drop is
	' deferred by at most the rest of the animation, never lost.
	'
	' #lf is restamped every frame so the main loop does not then ALSO charge its
	' clamped catch-up (#fd up to 4) for time already counted here.
	'
anim_tick:
	GOSUB sfx_tick
	musdin = 1			' the music keeps time through the animations too
	GOSUB mus_tick
	IF #dropt > 1 THEN
		#dropt = #dropt - 1
	ELSE
		#dropt = 0
	END IF
	#lf = FRAME
	GOSUB tick_bar
	RETURN

	'
	' ------------------------------------------------------------------ music
	'
	' Driven here rather than with CVBasic's PLAY: PLAY writes the volume registers
	' from its own tables every frame, which would fight every sound effect in the
	' game for the channels they share.
	'
mus_start:
	#mup = 0
	mut = 1
	IF musen = 0 THEN mut = 0		' switched off on the title
	RETURN

	' Only the state word is reprinted, not the whole line -- "1=MUSIC" is static.
prt_musen:
	IF musen = 1 THEN
		PRINT AT 626,"ON "
	ELSE
		PRINT AT 626,"OFF"
	END IF
	RETURN

mus_off:
	mut = 0
	SOUND 1,,0
	SOUND 2,,0
	RETURN

	' Caller sets musdin to the frames elapsed since it last called.
	'
	' COUNT FRAMES, NOT PASSES, and DO NOT DROP THE REMAINDER. Both are RALLY-X's
	' scars (its DESIGN.md 17): a per-pass counter halves the tempo the moment a
	' pass takes two frames, and resetting the counter instead of spending the whole
	' delta makes the music LOSE TIME exactly when the loop is busy -- which here
	' would be during a burst or an orphan fall, so the tune would drag whenever the
	' player did something good.
mus_tick:
	IF mut = 0 THEN RETURN
	musd = musdin
mus_adv:
	IF mut > musd THEN mut = mut - musd : RETURN
	musd = musd - mut
	mut = MUSTICK
	GOSUB mus_step
	GOTO mus_adv

mus_step:
	#mua = #muss + #mup
	#mua = #mua + #mup
	mun = PEEK(#mua)
	#mua = #mua + 1
	mub = PEEK(#mua)
	IF mun > 0 THEN GOSUB mus_mel
	IF mub > 0 THEN GOSUB mus_bas
	#mup = #mup + 1
	IF #mup >= 192 THEN #mup = 0	' SONG LENGTH -- genmusic.py verifies this
	RETURN

mus_mel:
	#mua = #musf + mun
	#mua = #mua + mun
	mhi = PEEK(#mua)
	#mua = #mua + 1
	mlo = PEEK(#mua)
	GOSUB mus_word
	SOUND 2,#mf,MUSVOL
	RETURN

mus_bas:
	#mua = #musf + mub
	#mua = #mua + mub
	mhi = PEEK(#mua)
	#mua = #mua + 1
	mlo = PEEK(#mua)
	GOSUB mus_word
	SOUND 1,#mf,MUSBAS
	RETURN

	' Rebuild the 16-bit divider from the table's hi/lo bytes by DOUBLING, never
	' `mhi * 256`: that compiles to a bare CLR on this backend (CLAUDE.md 3A), so
	' every note would come out as just its low byte -- pitches wrong, anything over
	' 255 wrapping, the tune unrecognisable and no error anywhere.
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

sfx_tick:
	IF sf0 > 0 THEN
		sf0 = sf0 - 1
		IF sf0 = 0 THEN SOUND 0,1000,0
	END IF
	IF sf1 > 0 THEN
		sf1 = sf1 - 1
		IF sf1 = 0 THEN SOUND 1,1000,0
	END IF
	' Channel 3 is the NOISE generator, used only by the pop.
	IF sf3 > 0 THEN
		sf3 = sf3 - 1
		IF sf3 = 0 THEN SOUND 3,,0
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
			SOUND 0,360,8
			sf0 = 3
		END IF
	ELSE
		IF #bx > 34816 THEN
			#bx = 34816
			bdir = 0
			SOUND 0,360,8
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
	SPRITE 0,209,0,0,0
	SPRITE 1,209,0,0,0
	grid(strr * 8 + stcc) = curk
	IF strr > maxr THEN maxr = strr		' draw_field runs before scan_present
	' LANDING IS A FAST BLIP, NOT A BEEP. At 186 Hz over three frames it read as a
	' distinct low note, and since a landing is usually followed a frame later by the
	' pop, that note sat on top of the pop and muddied it. Now shaped like the wall
	' bounce -- two frames, same register -- so landing and bouncing are recognisably
	' kin, with the landing a little lower so they are still distinguishable.
	SOUND 0,430,9
	sf0 = 2
	GOSUB draw_field
	GOSUB after_stick
	RETURN

	'
	' ------------------------------------------------- match, orphans, score
	'
after_stick:
	GOSUB clr_fill			' clr_marks would wipe the scenery flags (bit 5)
	grid(strr * 8 + stcc) = grid(strr * 8 + stcc) OR 64
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
	' Field is now drawn WITHOUT the orphans, so they can fall over a clean board.
	IF ofn > 0 THEN GOSUB fall_orphans
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

	' Clear the FILL mark (bit 6) but keep the anchor flag (bit 5) and colour.
clr_fill:
	FOR cmi = 0 TO 95
		grid(cmi) = grid(cmi) AND 47
	NEXT cmi
	RETURN

	'
	' Bit 5 = STATIC SCENERY: a bubble the LEVEL placed that was not hanging from
	' the ceiling to begin with. Set once at load, never on a bubble the player
	' shoots. Scenery acts as an anchor, exactly like the ceiling does.
	'
	' Why this exists. Puzzle Bobble drops anything that loses its connection to
	' the ceiling, and a global "reachable from row 0" check is the obvious way to
	' do it -- but four of the transcribed arcade layouts contain pieces that were
	' never attached in the first place (rounds 9, 10, 15, 20; round 10 is 90%
	' detached, because the FAQ's ASCII diagrams do not preserve hex adjacency at
	' the row ends -- section 7a). A global check collapsed all of that on the
	' first pop anywhere, whether or not it touched the popped group. It reads as
	' the match logic being broken, and was reported as exactly that.
	'
	' The first attempt keyed off "was it anchored BEFORE this shot", which fixed
	' the collapse but broke the opposite case: a bubble shot ONTO the scenery is
	' never ceiling-anchored, so it could never fall -- clear everything under it
	' and it just hung there. Anchoring on the scenery ITSELF fixes both, because
	' a shot bubble is not scenery and is not an anchor:
	'
	'   ceiling + surviving scenery = anchors;  anything that cannot reach one falls
	'
	' Scenery that gets popped stops being an anchor with it, so whatever was
	' resting on it then falls. On a well-formed field there is no scenery at all
	' and this is precisely the stock rule, so 26 of the 30 rounds are untouched.
	'
mark_scenery:
	FOR sai = 0 TO 95
		grid(sai) = grid(sai) AND 15
	NEXT sai
	FOR sai = 0 TO 7
		IF (grid(sai) AND 15) <> 0 THEN grid(sai) = grid(sai) OR 64
	NEXT sai
	pgcol = 0
	GOSUB propag
	FOR sai = 0 TO 95
		IF (grid(sai) AND 15) <> 0 THEN
			IF (grid(sai) AND 64) = 0 THEN grid(sai) = grid(sai) OR 32
		END IF
		grid(sai) = grid(sai) AND 47
	NEXT sai
	RETURN

count_marks:
	mkn = 0
	FOR cmi = 0 TO 95
		IF (grid(cmi) AND 64) <> 0 THEN mkn = mkn + 1
	NEXT cmi
	RETURN

	' The matched group bursts before it clears: three dissolve frames painted
	' over the marked cells (white flash -> yellow -> grey specks), two frames
	' each. Only the marked cells are touched, so this is a handful of VPOKEs
	' rather than a field redraw.
pop_marks:
	FOR pbf = 0 TO 2
		GOSUB draw_burst
		WAIT
		GOSUB anim_tick
		WAIT
		GOSUB anim_tick
	NEXT pbf
	FOR cmi = 0 TO 95
		IF (grid(cmi) AND 64) <> 0 THEN grid(cmi) = 0
	NEXT cmi
	' A BUBBLE BURSTING IS A NOISE TRANSIENT, NOT A TONE. Channel 3 is the noise
	' generator, and type 7 is white noise whose shift rate is taken from CHANNEL 2 --
	' the music melody. That coupling is what puts the little swipe on the tail of the
	' burst, and it is why 7 was chosen over the fixed rates of 4-6 after hearing all
	' eight side by side. Two tuned square waves never made a pop, however low they
	' were pitched.
	'
	' !! IT DOES MEAN THE POP FOLLOWS THE TUNE, and that with music switched off
	' channel 2 is never written -- so the swipe depends on whatever last set that
	' register. Worth listening to with 1=MUSIC OFF before trusting it.
	'
	' It also gets the pop OFF CHANNEL 1, which is the music's bass -- so pops no
	' longer duck the tune. Channel 3 is used by nothing else in the game, so this
	' effect never collides with anything.
	SOUND 3,7,13
	sf3 = 4
	SOUND 0,700,10
	sf0 = 4
	RETURN

	'
	' Paint burst frame pbf over every marked cell. Cell (r,c) is at character
	' row CEILROW+top+2r and column shkb+1+2c+(r AND 1) -- the same arithmetic
	' draw_row uses, because the burst has to land exactly where the bubble was.
draw_burst:
	pbc = 164 + pbf * 4
	FOR pbr = 0 TO 11
		pbrow = CEILROW + top + pbr + pbr
		IF pbrow < 23 THEN
			pbp = pbr AND 1
			pbb = pbr * 8
			FOR pbi = 0 TO 7
				IF (grid(pbb + pbi) AND 64) <> 0 THEN
					pbx = shkb + 1 + pbi + pbi + pbp
					#pba = pbrow
					#pba = #pba * 32
					#pba = #pba + pbx
					#pba = #pba + 6144
					pbv = pbc
					VPOKE #pba,pbv
					#pba = #pba + 1
					pbv = pbc + 1
					VPOKE #pba,pbv
					#pba = #pba + 31
					pbv = pbc + 2
					VPOKE #pba,pbv
					#pba = #pba + 1
					pbv = pbc + 3
					VPOKE #pba,pbv
				END IF
			NEXT pbi
		END IF
	NEXT pbr
	RETURN

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
	GOSUB clr_fill			' keep bit 5 -- the scenery flags are the anchors
	FOR doc = 0 TO 7
		IF (grid(doc) AND 15) <> 0 THEN grid(doc) = grid(doc) OR 64
	NEXT doc
	' Seed from the level's own static scenery as well as from the ceiling. A
	' scenery bubble that has been popped is gone from the grid and so stops
	' anchoring, which is what makes anything resting on it fall.
	FOR doc = 0 TO 95
		IF (grid(doc) AND 32) <> 0 THEN grid(doc) = grid(doc) OR 64
	NEXT doc
	pgcol = 0
	GOSUB propag
	don = 0
	ofn = 0
	' The i-th dropped bubble is worth 2^i UNITS OF 10, so the award is just the
	' previous one doubled -- dbl_ad, the same routine the round-clear bonus uses.
	' This replaced a 102-byte dropbcd table of seventeen six-digit entries AND the
	' `* 6` index multiply that read it. Starts at 2 units = 20 points.
	ad(0) = 0 : ad(1) = 0 : ad(2) = 0
	ad(3) = 0 : ad(4) = 0 : ad(5) = 2
	' Walked by row/column, not flat index, so the orphan's grid position is known
	' without a division -- fall_orphans needs it to place the sprite.
	FOR dor = 0 TO 11
		dob8 = dor * 8
		FOR docc = 0 TO 7
			doi = dob8 + docc
		IF (grid(doi) AND 15) <> 0 THEN
			' Unreachable from the ceiling OR from surviving scenery: it falls.
			' No bit-5 test here -- scenery seeds the fill above, so it is already
			' marked and cannot reach this branch while it still exists.
			IF (grid(doi) AND 64) = 0 THEN
				IF ofn < 24 THEN
					ofr(ofn) = dor
					ofcl(ofn) = docc
					ofk(ofn) = grid(doi) AND 15
					ofn = ofn + 1
				END IF
				grid(doi) = 0
				don = don + 1
				GOSUB add_score
				' Capped at the 17th bubble (131,072 units = 1,310,720 points, the
				' documented arcade maximum): past that the award simply stops
				' doubling, so every further bubble pays the same top rate -- which
				' is exactly what the old table's `IF dobi > 17` clamp did.
				IF don < 17 THEN GOSUB dbl_ad
			END IF
		END IF
		NEXT docc
	NEXT dor
	IF don > 0 THEN
		SOUND 1,820,12
		sf1 = 12
	END IF
	RETURN

	' The orphans drop away as sprites, at slightly different speeds so a row of
	' them spreads out instead of moving as a slab -- which also keeps them off
	' each other's scanlines, where only four sprites can show at once.
	' Called AFTER the field has been redrawn without them.
fall_orphans:
	FOR ofi = 0 TO ofn - 1
		ofp = ofr(ofi)
		ofq = ofp AND 1
		ofv = CEILROW + top + ofp + ofp
		ofyy(ofi) = ofv * 8
		ofv = shkb + 1 + ofcl(ofi) + ofcl(ofi) + ofq
		ofxx(ofi) = ofv * 8
	NEXT ofi
	FOR off = 0 TO 26
		FOR ofi = 0 TO ofn - 1
			IF ofyy(ofi) < 200 THEN
				ofs = 6 + (ofi AND 3)
				ofyy(ofi) = ofyy(ofi) + ofs
				IF ofyy(ofi) > 199 THEN
					SPRITE 8 + ofi,209,0,0,0
				ELSE
					ofj = ofk(ofi) - 1
					ofj = ofj * 4
					ofc2 = bub_base(ofk(ofi) - 1)
					ofw = ofyy(ofi) - 1
					SPRITE 8 + ofi,ofw,ofxx(ofi),ofj,ofc2
				END IF
			END IF
		NEXT ofi
		WAIT
		GOSUB anim_tick
	NEXT off
	FOR ofi = 0 TO 23
		SPRITE 8 + ofi,209,0,0,0
	NEXT ofi
	ofn = 0
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

	' Double the 6-digit BCD addend in place -- ad() + ad() with carry, the same
	' digit-wise shape as add_score. Doubling BCD by adding it to itself avoids
	' both a multiply (the 9900's MPY clobbers r0, CLAUDE.md 3A) and a lookup
	' table. Overflow past six digits cannot happen here: the bonus tops out at
	' 51,200 points = 5,120 units, four digits.
dbl_ad:
	dacy = 0
	FOR daj = 0 TO 5
		dai = 5 - daj
		dat = ad(dai) + ad(dai) + dacy
		IF dat > 9 THEN
			dat = dat - 10
			dacy = 1
		ELSE
			dacy = 0
		END IF
		ad(dai) = dat
	NEXT daj
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
	GOSUB mark_scenery		' flag the level's own detached pieces, once
	GOSUB calc_bstep
	barlast = 255			' force the first tick_bar to draw
	barw = 0
	#seqb = lvl - 1
	#seqb = #seqb * 16
	si = 0
	top = 0
	shkb = 1
	shkbo = 1
	shking = 0		' a round can end mid-shake; do not inherit the phase
	RETURN

	'
	' Frames per pixel of the 64-step gauge. Computed once per round.
	'
	' !! THIS MUST STAY IN ITS OWN ROUTINE. Written inline right after
	' `#droprl = #droprl * 15` it silently produced ZERO, because on the TMS9900
	' `MPY` returns a 32-bit product in r0:r1 -- the LOW word (the answer) goes to
	' r1 and r0 is overwritten with the HIGH word. CVBasic stores r1 correctly and
	' then goes on believing r0 still holds #droprl, so the very next
	' `#bstep = #droprl` compiled to `mov r0,@cvb__BSTEP` and stored the high word,
	' which is 0 for any product under 65536:
	'
	'     li r1,15
	'     mpy r1,r0             ; r0 = high word, r1 = low word
	'     mov r1,@cvb__DROPRL   ; correct
	'     mov r0,@cvb__BSTEP    ; WRONG -- stores 0
	'
	' `IF #bstep < 1 THEN #bstep = 1` then clamped it to 1, so the gauge read
	' `px = #dropt` clamped at 64 and sat FULL until the last second instead of
	' draining. No error at compile or run time; the only symptom was a bar that
	' never moved. A label is a branch target, so the compiler cannot assume
	' anything about r0 here and emits a real load. The same trap applies to ANY
	' read of a 16-bit variable immediately after multiplying it -- verify the
	' generated .a99 whenever a multiply is involved (CLAUDE.md section 3A).
	'
calc_bstep:
	#bstep = #droprl
	#bstep = #bstep / 64
	IF #bstep < 1 THEN #bstep = 1
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
	GOSUB mus_off			
	' Same hazard as do_drop: the round can clear mid-shake, and the whole
	' closing animation would then run one character off-centre.
	shkb = 1
	shkbo = 1
	shking = 0
	GOSUB draw_ceiling
	' TWO character rows per step, 14 steps -- the wall closes at the same pace
	' the reveal opens (12 frames). One row per step was 27 frames AND each step
	' carried a growing ceiling repaint, so it crawled.
	' CLEAR BONUS, paid as the wall comes down: 100 for the first row and double
	' for each row after it, stopping at the death line. Rows below the line pay
	' nothing -- the bonus is for the board you cleared, and the wall carrying on
	' past the line is just the animation finishing.
	'
	' Each step of this loop closes a ROW-PAIR, which is one bubble row, and that
	' is what counts as "a row" here. Ten of them fit above the line from a fresh
	' ceiling, so the last pays 51,200 and the whole bonus is 102,300 -- worth
	' chasing next to a good drop, without dwarfing it.
	'
	' Held in ad() as BCD and doubled in place, rather than as a lookup table: the
	' score is already 8 BCD digits (section 11a) and a table of 14 six-digit
	' entries would cost 84 bytes we do not have.
	dcaw = 1
	ad(0) = 0 : ad(1) = 0 : ad(2) = 0
	ad(3) = 0 : ad(4) = 1 : ad(5) = 0	' 10 units = 100 points
	FOR dcs = 0 TO 13
		bar = CEILROW + top
		IF bar > DEATHROW THEN dcaw = 0
		GOSUB brick_at
		bar = bar + 1
		GOSUB brick_at
		top = top + 2
		GOSUB draw_field
		IF dcaw = 1 THEN
			GOSUB add_score
			GOSUB prt_hud		' the score ticks up a row at a time
			GOSUB dbl_ad
		END IF
		' DESCENDING sweep, one step per row-pair: the wall coming down.
		' Re-set every step, and sf1 is kept above zero so sfx_tick never
		' silences it mid-sweep; it decays on its own after the loop.
		#dct = dcs
		#dct = #dct * 50
		#dcf = 300
		#dcf = #dcf + #dct
		SOUND 1,#dcf,12
		sf1 = 3
		WAIT
		GOSUB sfx_tick
	NEXT dcs
	lvl = lvl + 1
	' Beating round 30 gets its own screen (victory:), not a message box. The
	' message box that used to say ALL 30 CLEAR for three seconds is gone with it.
	IF lvl > 30 THEN GOTO victory
	reveal = 1		' screen is solid brick now -- lift it to show the level
	GOTO new_round

	'
	' A bubble crossed the death line. The 1.5 s pause here was a tone over a
	' frozen board with nothing to say WHY the round ended, so THE DEATH LINE
	' flashes RED against its normal yellow for that whole 1.5 s (90 frames at
	' 60 Hz, toggling every 8 -- just under 4 flashes a second). The line is the
	' rule that was broken, so the line is what the eye should be pulled to, and
	' yellow -> red says which rule without a word of text.
	'
	' It is character 161's colour that alternates, nothing else. Flashing the
	' BUBBLES was tried first and was wrong twice over: it draws attention to the
	' wrong thing, and recolouring all 32 bubble characters white leaves the ones
	' already white or grey unchanged, so only *some* of the balls appear to blink.
	' One character, one DEFINE COLOR of 8 bytes per flip.
	'
do_dead:
	GOSUB mus_off			
	' Clear the launcher deck FIRST. The loaded ball and the three aim dots are
	' pointing at a shot that will never be taken, and they sit right under the
	' death line -- exactly where the eye is about to be sent. Parked before the
	' flash starts so the line is the only thing moving. Sprites 2/3 (the NEXT
	' bubble) stay: that is a HUD readout, not the aiming device.
	SPRITE 0,209,0,0,0
	SPRITE 1,209,0,0,0
	SPRITE 4,209,0,32,0
	SPRITE 5,209,0,32,0
	SPRITE 6,209,0,32,0
	SOUND 0,800,13
	sf0 = 40
	ddf = 0
	FOR ddi = 0 TO 90
		IF (ddi AND 7) = 0 THEN
			ddf = 1 - ddf
			' Both halves of the line together: the bare dash where it is
			' visible, and the line inside any bubble sitting on that row.
			IF ddf = 1 THEN
				DEFINE COLOR 161,1,dash_colf
				DEFINE COLOR 186,32,bub_colxf
			ELSE
				DEFINE COLOR 161,1,dash_col
				DEFINE COLOR 186,32,bub_colx
			END IF
		END IF
		WAIT
		GOSUB sfx_tick
	NEXT ddi
	DEFINE COLOR 161,1,dash_col	' always leave the line its normal colour
	DEFINE COLOR 186,32,bub_colx
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
		#rvt = #rvt * 55
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
	' A bubble sitting ON the death-line row would hide the line behind it, and
	' with a deep stack that is most of the line -- so the flash the player is
	' meant to read is exactly the part covered up. Bubbles on that row are drawn
	' from the variant set instead (chars 186-217), which carries the line through
	' its own middle with a 1px black spacer either side. Which PAIR gets it
	' depends on the ceiling's parity: the row-pair's top char row may be the death
	' row, or its bottom one.
	drp = drr AND 1
	drb = drr * 8
	dlt = 0
	dlb = 0
	IF drw = DEATHROW THEN dlt = 1
	IF drv = DEATHROW THEN dlb = 1
	FOR drc = 0 TO 7
		drk = grid(drb + drc) AND 15
		IF drk <> 0 THEN
			drx = shkb + 1 + drc + drc + drp
			drh = 124 + drk * 4
			drhx = 182 + drk * 4
			IF dlt = 1 THEN
				rowbuf(drx) = drhx
				rowbuf(drx + 1) = drhx + 1
			ELSE
				rowbuf(drx) = drh
				rowbuf(drx + 1) = drh + 1
			END IF
			IF dlb = 1 THEN
				rowbuf(drx + 20) = drhx + 2
				rowbuf(drx + 21) = drhx + 3
			ELSE
				rowbuf(drx + 20) = drh + 2
				rowbuf(drx + 21) = drh + 3
			END IF
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
	' THE PANEL IS BUILT ONCE, NOT ONCE A ROUND.
	'
	' Every playfield blit is 20 characters wide at column 0, so nothing in the
	' normal draw path can touch the HUD panel in columns 20-31. Only the TITLE
	' screen reaches in there (its credit line runs to column 26, the bubble rows to
	' 25) and the GAME OVER / ALL 30 CLEAR box, which is on its way to the title
	' anyway. So the panel needs clearing and relabelling exactly when the game has
	' come FROM the title -- and never between rounds, where wiping it and printing
	' it straight back is a visible flicker of a HUD that was already right.
	'
	' hudok says whether the panel on screen is ours. title_screen clears it; this
	' sets it once the labels are down.
draw_frame:
	IF hudok = 0 THEN
		CLS
		' All on column 22, aligned with the score digits below each one.
		PRINT AT 22,"1UP"
		PRINT AT 118,"HI"
		PRINT AT 214,"ROUND"
		PRINT AT 342,"NEXT"	' row 10, the bubble sits directly beneath it
		PRINT AT 502,"TIME"
		hudok = 1
	END IF
	GOSUB draw_ceiling
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
	GOSUB prt_lives
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
	' One sprite each now: pattern k-1, frame (k-1)*4. Sprites 1 and 3 are no longer
	' used in play -- new_round hides them, so nothing of the title screen's
	' creatures is left behind in those slots.
	dsf = curk - 1
	dsf = dsf * 4
	dsc = bub_base(curk - 1)
	SPRITE 0,dsy,dsx,dsf,dsc
	dsf = nxtk - 1
	dsf = dsf * 4
	dsc = bub_base(nxtk - 1)
	SPRITE 2,NEXTY - 1,NEXTX,dsf,dsc
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
			SPRITE 3 + gi,gpy - 9,gpx - 8,32,15
		NEXT gi
	ELSE
		SPRITE 4,209,0,32,0
		SPRITE 5,209,0,32,0
		SPRITE 6,209,0,32,0
	END IF
	RETURN

	'
	' ---------------------------------------------------------- title screen
	'
	' Fire starts a game. Typing 8 3 8 opens a round selector -- the same secret
	' the other games in this repo use, and deliberately not advertised on screen.
	' The chosen round lasts ONE game: coming back here always resets to round 1.
	'
	'
	' ------------------------------------------------------- victory screen
	'
	' Beating round 30. Scores across the top exactly as the title screen lays
	' them out (same routines), CONGRATULATIONS! under them, the creature standing
	' in the lower middle JUGGLING all eight bubble colours, and PRESS FIRE at the
	' bottom to leave. The music keeps playing -- mus_off is not called until
	' title_screen, which is where fire sends us.
	'
	' THE JUGGLE IS ONE TABLE AND ONE COUNTER. All eight balls walk the same
	' 64-step closed loop (juggle.bas, generated) at a phase offset of 8 steps
	' each, so ball i is at step (jt + 8*i) AND 63. Eight independent arcs would
	' have meant eight tables and eight sets of state; this is 128 bytes.
	'
	' !! THE FOUR-SPRITE LIMIT IS THE WHOLE DESIGN CONSTRAINT HERE. Eleven sprites
	' are on screen -- eight balls, his body, and his two arms -- and the TMS9918
	' draws only FOUR per scanline, silently dropping the rest (SPRITE FLICKER is
	' off in this game, so nothing rotates them into view). Body and arms are three
	' sprites on the same rows by necessity: the arm art's shoulder is drawn for
	' the body's own y, and lifting it 8 px puts the arm root straight on his eye.
	' That leaves room for exactly ONE ball down there, which is why the loop's
	' shape is not a free choice -- genjuggle.py sweeps it and proves no scanline
	' ever exceeds four, over all 64 phases. It comes out at exactly four on his
	' top row. So there is NO margin: adding any sprite to this screen, or nudging
	' the creature's y, needs genjuggle.py re-run or balls will start vanishing.
	'
	' The two hands rock in OPPOSITE phase (one up while the other is down), which
	' is what sells it as juggling rather than two arms waving in unison.
	'
victory:
	GOSUB hide_sprites
	CLS
	' Same top row as the title: SCORE flush left, HI flush right.
	PRINT AT 0,"SCORE"
	PRINT AT 20,"HI"
	tsp = 6
	GOSUB title_num_sc
	tsp = 23
	GOSUB title_num_hi
	PRINT AT 104,"CONGRATULATIONS!"	' row 3, col 8 -- 16 chars, centred
	PRINT AT 715,"PRESS FIRE"	' row 22, col 11. NOT row 23: that row is
					' overscan on real hardware and clipped in
					' Classic99 (same reason the lives moved).
	jt = 0
	jts = 0
	btnr = 0			' a fire still held from the last shot must
					' not skip the screen before it is seen

victory_wait:
	WAIT
	GOSUB sfx_tick
	GOSUB jug_draw
	' HALF SPEED: one step every OTHER frame, so a full 64-step revolution takes
	' 2.1 s rather than 1.1. At one step per frame the balls whipped round faster
	' than a person could juggle. The hands still rock off `jt`, so they slow with
	' the balls and stay in time with them.
	jts = 1 - jts
	IF jts = 0 THEN
		jt = jt + 1
		jt = jt AND 63
	END IF
	IF btnr = 0 THEN
		IF cont1.button = 0 THEN btnr = 1
	ELSE
		IF cont1.button THEN GOTO title_screen
	END IF
	GOTO victory_wait

	' Body on sprite 0, right arm on 1, left arm on 2, the eight balls on 3-10.
	' Lower sprite numbers win on this VDP, so his hands draw OVER the ball at the
	' bottom of the loop -- which is what makes it look held rather than behind him.
jug_draw:
	SPRITE 0,143,120,36,3		' pattern 9 (legs apart), green, screen centre
	jphs = jt AND 15
	jh = 44				' right hand, its two rock frames
	IF jphs > 7 THEN jh = 48
	SPRITE 1,143,128,jh,3
	jh2 = 56			' left hand, deliberately the OPPOSITE frame
	IF jphs > 7 THEN jh2 = 52
	SPRITE 2,143,112,jh2,3
	FOR jbi = 0 TO 7
		jp = jbi * 8
		jp = jp + jt
		jp = jp AND 63
		jf = jbi * 4		' bubble colour jbi+1's sprite frame
		jc = bub_base(jbi)
		SPRITE 3 + jbi,jug_y(jp),jug_x(jp),jf,jc
	NEXT jbi
	RETURN

title_screen:
	GOSUB mus_off
	hudok = 0			' the title writes into the HUD panel; rebuild it
	stlv = 1
	GOSUB hide_sprites
	CLS
	' Two decorative rows showing all eight bubble colours, built in the same
	' row buffer the playfield uses.
	'
	' LAYOUT, top to bottom: score/hi on row 0, bubbles on 3-4, the name on 8 (with
	' the creatures pacing either side of it), TWO clear rows, bubbles again on
	' 11-12, the credit on 17, and PRESS FIRE on 21.
	'
	' The credit on row 17 sits exactly between them: rows 13-21 are free between
	' the lower bubbles and PRESS FIRE on 22, leaving four clear rows above it and
	' four below. (It was chosen as a deliberate skew toward PRESS FIRE when that
	' sat on row 21 and the gap was odd; moving PRESS FIRE down one row made the
	' same position land dead centre, so the skew is no longer needed.)
	tby = 3
	GOSUB title_bubbles
	tby = 11
	GOSUB title_bubbles
	' Last score and high score across the top row: "SCORE" then the 9 digits,
	' "HI" then its 9. Row 0 is cols 0-31, so SCORE occupies 0-14 and HI 17-31.
	' SCORE is flush LEFT (label col 0, digits 6-14); HI is flush RIGHT (digits
	' 23-31, label just before it) so the two blocks bracket the row evenly.
	PRINT AT 0,"SCORE"
	PRINT AT 20,"HI"
	tsp = 6
	GOSUB title_num_sc
	tsp = 23
	GOSUB title_num_hi
	PRINT AT 265,"BUST-A-BOBBLE"
	PRINT AT 548,"2026 UNHUMAN AND CLAUDE"	' row 17, col 4
	PRINT AT 618,"1=MUSIC"			' row 19, col 10
	GOSUB prt_musen
	PRINT AT 710,"PRESS FIRE TO START"	' row 22, col 6
	t8 = 0
	tkl = 15
	btnr = 0
	' Two creatures, deliberately out of step from the first frame: different
	' starting positions, directions, step phases and countdowns. They never sync
	' up because the countdowns are re-rolled at random each time.
	'
	' The patrols are ASYMMETRIC on purpose. Both run from just clear of the title
	' outward, but "BUST-A-BOBBLE" is not centred on the screen -- it spans px
	' 72-175, so there is more empty screen on the right than the left. The left
	' guy roams 14-51 (2 chars further out than he used to), the right 179-224
	' (3 chars), which uses the room that is actually there and still leaves both
	' about 15 px of margin at the screen edge, arm included.
	twx(0) = 30 : twdir(0) = 0 : twt(0) = 0 : twf(0) = 0
	twst(0) = 0 : twtm(0) = 40 : twwf(0) = 0
	twlo(0) = 14 : twhi(0) = 51
	twx(1) = 195 : twdir(1) = 1 : twt(1) = 2 : twf(1) = 2
	twst(1) = 0 : twtm(1) = 95 : twwf(1) = 0
	twlo(1) = 179 : twhi(1) = 224

title_wait:
	WAIT
	GOSUB sfx_tick
	GOSUB title_walk
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
		IF tk = 1 THEN
			musen = 1 - musen
			GOSUB prt_musen
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

	' The two 9-digit numbers on the title's top row. Same trailing-zero
	' convention as the HUD: 8 stored BCD digits shown with a literal 0.
title_num_sc:
	FOR tni = 0 TO 7
		#tna = tsp + tni
		#tna = #tna + 6144
		tnv = 48 + sc(tni)
		VPOKE #tna,tnv
	NEXT tni
	#tna = tsp + 8
	#tna = #tna + 6144
	tnv = 48
	VPOKE #tna,tnv
	RETURN

title_num_hi:
	FOR tni = 0 TO 7
		#tna = tsp + tni
		#tna = #tna + 6144
		tnv = 48 + hs(tni)
		VPOKE #tna,tnv
	NEXT tni
	#tna = tsp + 8
	#tna = #tna + 6144
	tnv = 48
	VPOKE #tna,tnv
	RETURN

	'
	' Two of the creature pacing either side of the title, at 2x.
	'
	' ONE variable drives both: the right-hand one is mirrored about the screen
	' centre (240 - twx), so they walk toward each other and back together. That
	' costs nothing extra and reads better than two independent wanderers.
	'
	' "BUST-A-BOBBLE" is 13 characters at row 8 columns 9-21, i.e. pixels 72-175,
	' whose centre is 123.5 -- NOT the screen centre of 128. So the right-hand one
	' is mirrored about the TEXT (231 - twx), not about the screen; mirroring about
	' the screen left the two clearances 2 px and 11 px, which looked lopsided.
	'
	' The patrol stops at 52 because the creature is 16 px WIDE: at 52 its right
	' edge is 68, four clear of the "B" at 72. Bounding the left edge instead let it
	' walk over the first letter.
	'
	' y = 59 straddles the text row (sprite y reads one low on this VDP, so 59 puts
	' the 16 px creature over pixel rows 60-75, centred on the 8 px text at 64-71).
	'
	' The body is identical between frames and only the legs change, so the walk
	' cycle reads as legs moving rather than the whole guy twitching.
	'
	' The state countdowns tick every 8 FRAMES, not every frame. That is not a
	' nicety: these are 8-bit array slots, and a countdown in frames long enough to
	' be "every once in a while" does not fit -- `240 + RANDOM(240)` wraps past 255
	' and comes out a small number, which is precisely why the first version waved
	' almost constantly. In eighths, 12-24 seconds is 90-180, comfortably in range.
title_walk:
	twtick = twtick + 1
	twtick = twtick AND 7
	FOR twi = 0 TO 1
		IF twtick = 0 THEN
			IF twtm(twi) > 0 THEN twtm(twi) = twtm(twi) - 1
		END IF
		IF twst(twi) = 0 THEN GOSUB tw_walk
		IF twst(twi) = 1 THEN GOSUB tw_wave
		GOSUB tw_draw
	NEXT twi
	RETURN

	' WALKING. A step every 4th frame (15 px/s, an amble), legs swapping every two
	' steps. When his countdown runs out he stops where he is and waves -- with
	' whichever hand the coin says, decided once per wave.
tw_walk:
	IF twtm(twi) = 0 THEN
		twst(twi) = 1
		twtm(twi) = 12 + RANDOM(8)	' wave for 1.6-2.5 s
		twwf(twi) = 0
		twside(twi) = RANDOM(2)		' 0 = right hand, 1 = left
		RETURN
	END IF
	twt(twi) = twt(twi) + 1
	IF twt(twi) < 4 THEN RETURN
	twt(twi) = 0
	IF twdir(twi) = 0 THEN
		twx(twi) = twx(twi) + 1
		IF twx(twi) >= twhi(twi) THEN twdir(twi) = 1
	ELSE
		twx(twi) = twx(twi) - 1
		IF twx(twi) <= twlo(twi) THEN twdir(twi) = 0
	END IF
	twf(twi) = twf(twi) + 1
	twf(twi) = twf(twi) AND 3
	RETURN

	' WAVING. He stands still and rocks his hand. The next walk lasts a fresh
	' random 4-8 s, which is why the two never fall into step with each other.
tw_wave:
	IF twtm(twi) = 0 THEN
		twst(twi) = 0
		twtm(twi) = 90 + RANDOM(90)	' walk 12-24 s before the next one
		RETURN
	END IF
	twwf(twi) = twwf(twi) + 1
	twwf(twi) = twwf(twi) AND 15	' hand rocks every 8 frames
	RETURN

	' Body on sprite 0/1, arm on 2/3. The arm is parked off screen unless he is
	' actually waving -- sprite y 209, not 208, which would end the sprite list and
	' take everything after it with it.
tw_draw:
	twpx = twx(twi)
	twp = 36			' pattern 9 -> frame 9*4; legs apart
	IF twst(twi) = 0 THEN
		IF twf(twi) > 1 THEN twp = 40
	END IF
	SPRITE twi,59,twpx,twp,3
	IF twst(twi) = 1 THEN
		' Right hand = patterns 27/28 laid 8 px right; left hand = 29/30 laid 8 px
		' left. Same y as the body, so the shoulder meets him at shoulder height
		' and the arm stays clear of his eyes.
		IF twside(twi) = 0 THEN
			twh = 44
			IF twwf(twi) > 7 THEN twh = 48
			twpx = twpx + 8
		ELSE
			twh = 52
			IF twwf(twi) > 7 THEN twh = 56
			twpx = twpx - 8
		END IF
		SPRITE 2 + twi,59,twpx,twh,3
	ELSE
		SPRITE 2 + twi,209,0,44,0
	END IF
	RETURN

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
	FOR hsi = 0 TO 31
		SPRITE hsi,209,0,0,0
	NEXT hsi
	RETURN

	' Round selector: two digits, 01-30, echoed as they are typed.
setup838:
	CLS
	PRINT AT 266,"SELECT ROUND"
	PRINT AT 360,"ENTER TWO DIGITS"
	' !! #rdp IS 16-BIT ON PURPOSE. Written `rdp = 463` -- a PLAIN variable, which is
	' 8-BIT -- the 463 silently truncated to 207, and the typed digits appeared at
	' row 6 col 15, ABOVE "SELECT ROUND", instead of row 14 below the prompt. No
	' error at build or run time; the position just looked like someone's odd
	' layout choice. Same family as the CONST > 255 hazard in CLAUDE.md 3A: any
	' screen offset past row 7 needs a # variable.
	#rdp = 463			' row 14, col 15 -- centred under the prompt
	GOSUB rd_dig
	sd1 = tdg
	GOSUB rd_dig
	stlv = sd1 * 10 + tdg
	IF stlv < 1 THEN stlv = 1
	IF stlv > 30 THEN stlv = 30
	' LET THE SECOND DIGIT'S BEEP DECAY BEFORE LEAVING. The first digit's note is
	' silenced by the wait loops of the second call to rd_dig -- but after the
	' SECOND digit there is no loop left, and nothing between here and the main loop
	' calls sfx_tick: not title_go, not load_level, not draw_frame. So the note held
	' all the way through round setup and only stopped once the game loop began,
	' which sounded like a beep running until the music started.
	FOR sdw = 0 TO 5
		WAIT
		GOSUB sfx_tick
	NEXT sdw
	RETURN

rd_dig:
	' THESE TWO LOOPS MUST TICK THE SOUND. They are the only WAIT loops in the game
	' that did not, and the digit beep sets sf0 for its note-off exactly like every
	' other effect -- so the countdown never ran and the note simply held, for as
	' long as the player took to type the second digit. It is the "every effect
	' needs an explicit note-off" hazard from CLAUDE.md 3A arriving by the back
	' door: the note-off existed, nothing was calling it.
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
	' Grey brick face over black mortar; YELLOW dash on black for the death line.
	' dash_col is a label INSIDE this table, not a copy: `DEFINE COLOR 160,2,wall_col`
	' still reads all 16 bytes straight through, while `DEFINE COLOR 161,1,dash_col`
	' addresses just the death-line dash so it can be recoloured on its own.
	'
	' Yellow at rest, RED when crossed -- the line changes meaning at that moment,
	' from a boundary you are approaching to the rule you just broke, so it changes
	' colour rather than merely blinking. It was dark red at rest, which both read
	' as already-alarming and left nowhere for the alarm state to go.
wall_col:
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
dash_col:
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1	' light yellow on black
	' Death-line flash: light red on black, swapped in and out by do_dead.
dash_colf:
	DATA BYTE $91,$91,$91,$91,$91,$91,$91,$91

	' 176-184 = the drop-timer gauge: the same cell at nine fill widths, 0 to 8
	' pixels from the LEFT. Eight of these side by side give a 64-step bar.
	' The unfilled pixels are left CLEAR on purpose -- they show the character's
	' BACKGROUND colour, which is the grey track, so fill and track come out of
	' one character instead of needing two.
bar_pat:
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00	' 0 px -- empty track
	DATA BYTE $00,$80,$80,$80,$80,$80,$80,$00	' 1
	DATA BYTE $00,$C0,$C0,$C0,$C0,$C0,$C0,$00	' 2
	DATA BYTE $00,$E0,$E0,$E0,$E0,$E0,$E0,$00	' 3
	DATA BYTE $00,$F0,$F0,$F0,$F0,$F0,$F0,$00	' 4
	DATA BYTE $00,$F8,$F8,$F8,$F8,$F8,$F8,$00	' 5
	DATA BYTE $00,$FC,$FC,$FC,$FC,$FC,$FC,$00	' 6
	DATA BYTE $00,$FE,$FE,$FE,$FE,$FE,$FE,$00	' 7
	DATA BYTE $00,$FF,$FF,$FF,$FF,$FF,$FF,$00	' 8 -- full

	' Per-scan-line colour is what gives the gauge a defined top and bottom:
	' lines 0 and 7 are black-on-black, so the bar reads as 6 px tall inside an
	' 8 px cell. Lines 1-6 are green on GREY -- lit pixels are the fill, unlit
	' are the track. Nine characters x 8 lines.
	' ONE row each, applied to all nine gauge characters by set_bar_col. They were
	' nine copies apiece -- 128 bytes of ROM restating that the bar is green and
	' that the warning is red.
bar_col:
	DATA BYTE $11,$3E,$3E,$3E,$3E,$3E,$3E,$11
	' The same character in RED, swapped in for the last quarter of the gauge.
bar_colw:
	DATA BYTE $11,$9E,$9E,$9E,$9E,$9E,$9E,$11

	' 185 = the spare-life creature. A bubble would have been wrong here: the field
	' is made of bubbles, so a bubble in the HUD reads as ammunition, not as a life.
	' life_pat / life_col and the title screen's 2x walking version (spr_walk) are
	' now BOTH generated by genart.py from one 8x8 definition, so the little guy
	' counting your lives and the one pacing about on the title cannot drift apart.
	' DEFINE COLOR takes EIGHT bytes per character (one per scan line), so
	' `DEFINE COLOR 32,16,txt_col` reads 16 x 8 = 128 bytes. Supplying only 16
	' made it read 112 bytes of whatever followed in ROM as colour data --
	' the text came out in random colours. Same shape as Structris's txt_white.
txt_col:
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1

	INCLUDE "art.bas"
	' The juggling path is read EVERY FRAME on the victory screen, so it belongs in
	' the fixed area with the aim table -- above the BANK directive below, never in
	' a bank.
	INCLUDE "juggle.bas"
	INCLUDE "music.bas"
	' LEVELS COME LAST, and on TI everything after `BANK 1` is assembled into that
	' bank. The order matters for exactly that reason: music.bas used to be last,
	' and if it still were, `BANK 1` would sweep the music tables into the bank
	' too -- where the vblank ISR could not safely read them. Nothing may be
	' INCLUDEd or defined after this point unless it also belongs in bank 1.
#if TI994A
	BANK 1
#endif
	INCLUDE "levels.bas"
