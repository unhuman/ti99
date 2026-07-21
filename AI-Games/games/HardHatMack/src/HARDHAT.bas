	'
	' Hard Hat Mack -- TI-99/4A + ColecoVision (CVBasic, dual-target)
	'
	' Faithful adaptation of the Apple II classic by Michael Abbot and
	' Matthew Alexander (Electronic Arts, 1983). Three screens: rivet the
	' girder gaps, collect the lunchboxes, feed the riveting machines --
	' while the vandal and the OSHA man hound you.
	'
	' See DESIGN.md for the full element spec and the hard-won CVBasic
	' lessons this source obeys:
	'   - default video mode + DEFINE CHAR/COLOR, never MODE 2
	'   - never <cmp> AND <cmp> in an IF (TI 9900 codegen bug) -- nest them
	'   - all #var comparisons are UNSIGNED -- branch-first deltas
	'   - % compiles to a real DIV -- use AND masks
	'   - 8-bit FOR with bound 255 wraps forever
	'   - array out-of-bounds is Coleco-FATAL -- exact sizes
	'   - TI single-bank cart cap 24,336 B -- build-ti.sh guards it
	'
	' 2026 UNHUMAN AND CLAUDE
	'

	' ---- Tile code bands (collision class = char code band) ----
	' The level painter writes chars straight into the name table and the
	' physics reads them back with VPEEK: VRAM is the collision map (no
	' RAM shadow -- the Coleco only has 1K of RAM).
	' (Reference: the ColecoVision version -- same TMS9918 VDP. Chains
	' are the CLIMBABLE elements; the tall blue columns are support
	' pillars, art only.)
	CONST T_VOID   = 32	' empty screen char
	CONST T_SOLID0 = 128	' 128-151: stand-on-able
	CONST T_GIRD   = 128	'   girder: blue body, red stripe top+bottom
	CONST T_GIRD2  = 129	'   girder variant (level 2)
	CONST T_GIRDO  = 130	'   girder, orange (level 3)
	CONST T_FILLED = 131	'   gap FILLED by a girder piece (plain body)
	CONST T_RIVET  = 132	'   gap RIVETED (bright rivet dots)
	CONST T_GROUND = 133	'   ground strip (levels 2/3)
	CONST T_ELEV   = 135	'   elevator platform chars (reserved)
	CONST T_SPRTOP = 137	'   springboard top plate
	CONST T_SPRBSE = 138	'   springboard coil (solid: you stand in it)
	CONST T_SOLID1 = 151
	CONST T_BUMP1  = 134	' head-bump range end: only girders/ground stop
				' a rising jump -- springboard and elevator chars
				' must let the bounce pass through
	CONST T_LADD0  = 152	' 152-155: climbable
	CONST T_CHAIN  = 152	'   hanging chain (THE climbing element)
	CONST T_LADD1  = 155
	CONST T_CONV0  = 156	' 156-163: conveyor belts (L/R x 2 anim frames)
	CONST T_CONVB  = 156	'   conveyor belt tile (level 2)
	CONST T_CONV1  = 163
	CONST T_HAZ0   = 164	' 164-171: touch = death
	CONST T_HAZ1   = 171
	' 172+: pass-through decoration and pickups
	CONST T_PILLAR = 174	' support pillar (art only -- NOT solid)
	CONST T_PED    = 175	' pedestal base under the bottom girder (art)
	CONST T_MAGNET = 176	' 176-177: electromagnet head (level 2, top of crane)
	CONST T_CABLE  = 178	' 178: thin crane cable (level 2 centre pole, art)
	CONST T_BEAM   = 192	' 192-207: 16 pre-shifted crane-beam girder slices
				'   placed by beam_draw, name-table only (level 2)
	CONST T_LBOXL  = 183	' lunchbox (2 cells, level 2)
	CONST T_LBOXR  = 184
	CONST T_BRICK  = 185	' loose girder piece: 1-cell red brick stack
	CONST T_WRENCH = 186	' bonus wrench (+500)
	CONST T_CAN    = 187	' bonus spray can (+500)
	CONST T_HAT    = 188	' hard hat (HUD lives icon)

	' ---- Level-stream opcodes (see level1_data) ----
	' 0                        end of stream
	' 1 row,col,len,type       horizontal run: type 0 girder, 1 girder2,
	'                          2 ground, 3 orange girder
	' 2 col,top,height         CHAIN (climbable; drawn BEFORE platforms so
	'                          beams cross in front)
	' 3 col,top,height         pillar (art only)
	' 4 col,top,height         pedestal base (art only)
	' 5 type,...               object -- payload varies:
	'    1 row,col             girder gap (4 cells wide, drawn as void by
	'                          the platform runs; this entry is the STATE)
	'    2 row,col             loose girder piece (1-cell brick stack)
	'    3 frow,cmin,cmax      jackhammer patrol, feet on floor frow
	'    4 kind,row,col        bonus pickup: kind 1 wrench, 2 spray can
	'    6 col,rtop,rbot       elevator (16x4 sprite platform)
	'    7 row,col             springboard: coil at row, top at row-1
	'   11 frow,cmin,cmax      vandal patrol on floor frow
	'   12 frow,cmin,cmax      OSHA man patrol on floor frow
	'   13 row,col             Mack spawn (feet on top of floor row)
	'   14 col                 bolt drop column
	'

	CONST MAXITEM = 6	' girder pieces (L1) / lunchboxes (L2) / boxes (L3)
	CONST MAXGAP  = 4
	CONST MAXBOLTC = 4

	DIM gapr(MAXGAP)	' gap -> floor row
	DIM gapc(MAXGAP)	' gap -> left col (4 wide)
	DIM gapst(MAXGAP)	' gap -> 0 open / 1 filled / 2 riveted
	DIM itr(MAXITEM)	' item -> cell row
	DIM itc(MAXITEM)	' item -> cell col (items are 1 cell)
	DIM itst(MAXITEM)	' item -> 0 present / 1 taken
	DIM itk(MAXITEM)	' item -> kind: 0 brick, 1 wrench, 2 spray can
	DIM bcol(MAXBOLTC)	' bolt drop columns
	DIM jtab(15)		' jump arc: 128+dy per step (unsigned-safe)
	' Conveyor belts as pixel SURFACES (bottom pixel x0,y0 -> top pixel x1,y1),
	' so Mack rides a continuous line and never drops into the cell gaps.
	DIM cvx0(3)
	DIM cvy0(3)
	DIM cvx1(3)
	DIM cvy1(3)

	' DEF FN substitutes arguments TEXTUALLY (no implicit parens): an
	' expression argument like VADDR(r + 1,c) would expand to
	' r + 1 * 32 + c without the parens below. Confirmed live: the
	' springboard coil painted at row 2 instead of row 22. Always
	' parenthesize every argument use in a DEF FN body.
	DEF FN CPOS(r,c) = (r) * 32 + (c)
	DEF FN VADDR(r,c) = $1800 + (r) * 32 + (c)
	' Tile under a PIXEL position (px across, py down).
	DEF FN TILE(px,py) = VPEEK($1800 + ((py) / 8) * 32 + (px) / 8)

	' Mack states
	CONST S_WALK  = 0
	CONST S_CLIMB = 1
	CONST S_JUMP  = 2
	CONST S_FALL  = 3
	CONST S_RIDE  = 4	' standing on the elevator platform
	CONST S_DEAD  = 5
	CONST S_TRAMP = 6	' riding the right-side trampoline channel
	CONST FATALFALL = 20	' pixels of drop that break Mack's neck

	'
	' One-time setup. Default video mode (do NOT use MODE 2 -- it renders
	' broken on both targets); per-character colors via DEFINE COLOR.
	'
	CLS
	BORDER 1

	' 16x16 sprite defs, NO magnification (VDP(1)=$E2): Mack is a 16-px
	' figure -- floor rows are 4 cells (32 px) apart, and the original's
	' actors stand about half a floor gap tall. (Structris/Astiroids use
	' $E3 2x-magnify for 32-px pieces; that scale would be wrong here.)
	VDP(1) = $E2
	SPRITE FLICKER OFF

	' Playfield tiles, colored per char (DEFINEs are synchronous on the
	' TI runtime -- verified in cvbasic_9900_prologue.asm).
	DEFINE CHAR T_SOLID0,11,tile_pat
	DEFINE COLOR T_SOLID0,11,tile_col
	DEFINE CHAR T_CHAIN,1,chain_pat
	DEFINE COLOR T_CHAIN,1,chain_col
	DEFINE CHAR T_PILLAR,2,pillar_pat		' 174 pillar, 175 pedestal
	DEFINE COLOR T_PILLAR,2,pillar_col
	DEFINE CHAR T_BRICK,4,item_pat			' 185-188 brick/wrench/can/hat
	DEFINE COLOR T_BRICK,4,item_col
	' Level 2 tiles: lunch pail, incinerator/flame, conveyor belt, magnet.
	DEFINE CHAR T_LBOXL,1,pail_pat
	DEFINE COLOR T_LBOXL,1,pail_col
	DEFINE CHAR T_HAZ0,3,haz_pat
	DEFINE COLOR T_HAZ0,3,haz_col
	DEFINE CHAR T_CONV0,4,conv_pat		' 156-159 belt-lo/belt-hi/drum/post
	DEFINE COLOR T_CONV0,4,conv_col
	DEFINE CHAR T_MAGNET,2,mag_pat
	DEFINE COLOR T_MAGNET,2,mag_col
	DEFINE CHAR T_CABLE,1,cable_pat
	DEFINE COLOR T_CABLE,1,cable_col
	' Crane beam: 16 PRE-SHIFTED girder slices (chars 192-207) -- upper cell
	' 192-199 (bar top at sub-row 0..7), lower cell 200-207. beam_draw just
	' places these in the name table (no per-frame pattern/color rewriting ->
	' no tearing/fragments). DEFINE triple-copies to all 3 bitmap zones so the
	' beam looks identical at any screen height.
	DEFINE CHAR 192,16,beamshift_pat
	DEFINE COLOR 192,16,beamshift_col

	' HUD/text: white on transparent for the whole ASCII range.
	DEFINE COLOR 32,16,txt_white
	WAIT
	DEFINE COLOR 48,16,txt_white
	WAIT
	DEFINE COLOR 64,16,txt_white
	WAIT
	DEFINE COLOR 80,16,txt_white
	WAIT

	DEFINE SPRITE 0,1,mack_bitmap
	DEFINE SPRITE 2,1,elev_bitmap		' elevator platform (16x4 slab)
	DEFINE SPRITE 3,1,vandal_bitmap
	DEFINE SPRITE 4,1,osha_bitmap
	DEFINE SPRITE 5,1,bolt_bitmap
	DEFINE SPRITE 6,1,jack_bitmap		' jackhammer (loose + carried)
	DEFINE SPRITE 7,1,brick_bitmap		' carried girder piece overlay
	DEFINE SPRITE 8,1,mackj_bitmap		' Mack airborne (jump/fall)
	DEFINE SPRITE 9,1,vandal2_bitmap	' vandal walk frame B (frame 36)
	DEFINE SPRITE 10,1,jack2_bitmap		' drill hammer frame B (frame 40)
	DEFINE SPRITE 11,1,mackw_bitmap		' Mack run right B (frame 44)
	DEFINE SPRITE 12,1,mackl_bitmap		' Mack stand left  (frame 48)
	DEFINE SPRITE 13,1,mackl2_bitmap	' Mack run left B  (frame 52)

	' Music player: SIMPLE (channels 0+1) so SOUND 2 stays free for game
	' effects and SOUND 3 (noise) for drills/crashes.
	' PLAY SIMPLE NO DRUMS		' SIZE TEST: temporarily removed

	' Jump arc into RAM (dy = value - 128; 10 px apex, 16 steps).
	RESTORE jump_data
	FOR i = 0 TO 15
		READ BYTE jtab(i)
	NEXT i

	' ---- M1: no title screen yet -- straight into level 1 ----
	lv = 1
	lives = 2
	#score = 0
	#hi = 0
	#bonus = 5000
	GOSUB init_level

main_loop:
	WAIT
	' Redraw the crane beam FIRST, inside vblank -- its VDP pattern/color
	' writes must land before the scan-out or the bar tears. It uses the
	' position computed on the previous pass (1-frame latency, invisible).
	GOSUB beam_draw
	' Animate the conveyor belts: every 2 frames advance the two belt chars
	' (156/157) by 1 px up through 8 rotation phases, so every belt cell scrolls
	' up the incline together. 8 phases = a full char rotation = a seamless loop
	' (no jump-back "shake").
	IF cvn > 0 THEN
		IF (FRAME AND 1) = 0 THEN
			cvaf = cvaf + 1
			IF cvaf >= 8 THEN cvaf = 0
			' Redefine 3 chars: belt-lo, belt-hi (scroll up) AND the drum (158,
			' a spinning roller) so the WHOLE conveyor -- belt and rollers --
			' moves. The post (159) stays static (it's a support strut).
			IF cvaf = 0 THEN DEFINE CHAR 156,3,belt_anim0
			IF cvaf = 1 THEN DEFINE CHAR 156,3,belt_anim1
			IF cvaf = 2 THEN DEFINE CHAR 156,3,belt_anim2
			IF cvaf = 3 THEN DEFINE CHAR 156,3,belt_anim3
			IF cvaf = 4 THEN DEFINE CHAR 156,3,belt_anim4
			IF cvaf = 5 THEN DEFINE CHAR 156,3,belt_anim5
			IF cvaf = 6 THEN DEFINE CHAR 156,3,belt_anim6
			IF cvaf = 7 THEN DEFINE CHAR 156,3,belt_anim7
		END IF
	END IF
	' FRAME-delta pacing (shared convention with Structris): a missed
	' vblank becomes a catch-up step, not a slowdown. #fd is the number
	' of real frames since the last pass, clamped so a pause can't
	' teleport anything.
	#fd = FRAME - #lf
	#lf = FRAME
	IF #fd > 4 THEN #fd = 4
	' Pace scaling for readable flows: advance movement at 9/8 of the base
	' (0.75x read too slow / player too fast). Accumulate frame_delta*9 and
	' take /8 as the step count; the leftover carries in #hacc. Mack and the
	' characters BOTH step #hd px per pass, so they move at identical speed.
	#hacc = #hacc + #fd * 9
	#hd = #hacc / 8
	#hacc = #hacc - #hd * 8
	' Read the stick once per pass; the 1-px step routine below runs
	' #hd times so heavy frames catch up instead of slowing down.
	jl = cont1.left
	jr = cont1.right
	ju = cont1.up
	jd = cont1.down
	jb = cont1.button
	' Button rising edge (fresh press): a jump fires only on a new press.
	jbe = 0
	IF jb THEN
		IF jbold = 0 THEN jbe = 1
	END IF
	jbold = jb
	' Long HOLD of FIRE (~0.75 s of real frames, pace-independent) drops the
	' carried jackhammer and warps it back to its start with its route reset.
	IF jb THEN
		jbhc = jbhc + 1
	ELSE
		jbhc = 0
	END IF
	IF jbhc = 45 THEN
		IF carry = 2 THEN GOSUB drop_hammer
	END IF
	IF st = S_DEAD THEN
		GOSUB dead_tick
		IF gameov = 1 THEN GOTO game_over
	ELSE
		FOR s8 = 1 TO #hd
			GOSUB mack_step
			GOSUB actors_step
		NEXT s8
		IF #hd > 0 THEN GOSUB actors_move
		GOSUB bolt_move
		IF #hd > 0 THEN GOSUB beam_move
	END IF
	IF #hd > 0 THEN GOSUB elev_move
	IF lvdone = 1 THEN GOTO level_complete
	' Mack: hidden (row 209) while dead-blinking handles its own draw.
	' Airborne states use the spread-legs jump pose.
	' Directional profile: Mack faces the way he's going (mdir 1=right,
	' 0=left), and the running stance alternates while he moves.
	IF mdir = 1 THEN
		mfr = 0
		mstr = 44
	ELSE
		mfr = 48
		mstr = 52
	END IF
	IF st = S_WALK THEN
		mvg = 0
		IF jl THEN mvg = 1
		IF jr THEN mvg = 1
		IF mvg = 1 THEN
			IF FRAME AND 4 THEN mfr = mstr
		END IF
	END IF
	IF st = S_JUMP THEN mfr = 32
	IF st = S_FALL THEN mfr = 32
	IF st = S_TRAMP THEN mfr = 32
	IF st <> S_DEAD THEN SPRITE 0,my - 1,mx,mfr,15
	SPRITE 2,ely - 1,elx,8,15
	' Both a carried brick and the jackhammer are held IN FRONT of Mack,
	' on the side he is facing.
	IF carry = 0 THEN
		SPRITE 1,209,0,0,0
	ELSE
		IF mdir = 1 THEN
			jx2 = mx + 8
		ELSE
			jx2 = mx - 8
		END IF
		IF carry = 1 THEN
			SPRITE 1,my - 1,jx2,28,9
		ELSE
			' Carried jackhammer keeps hammering (alternate frames 24/40),
			' same as when it roams -- it must not freeze in Mack's hands.
			jcf = 24
			IF FRAME AND 8 THEN jcf = 40
			SPRITE 1,my - 1,jx2,jcf,7
		END IF
	END IF
	' Walk-cycle toggle (~every 8 frames) for the drill and vandal.
	anm2 = 0
	IF FRAME AND 8 THEN anm2 = 1
	IF jhtk = 0 THEN
		jfr = 24
		IF anm2 = 1 THEN jfr = 40
		SPRITE 3,jhy - 1,jhx,jfr,7
	ELSE
		SPRITE 3,209,0,0,0
	END IF
	IF von = 1 THEN
		vfr = 12
		IF anm2 = 1 THEN vfr = 36
		SPRITE 4,vy - 1,vx,vfr,3
	ELSE
		SPRITE 4,209,0,0,0
	END IF
	IF oon = 1 THEN
		SPRITE 5,oy - 1,ox,16,11
	ELSE
		SPRITE 5,209,0,0,0
	END IF
	IF bon = 1 THEN
		SPRITE 6,by - 1,bx,20,15
	ELSE
		SPRITE 6,209,0,0,0
	END IF
	' L2 crane beam is rendered with CHARACTERS (pattern-scrolled), see
	' beam_draw -- called from the movement path, not here.
	' SFX timeout counters (music owns ch 0+1; effects live on 2, noise 3).
	IF snd2 > 0 THEN
		snd2 = snd2 - 1
		IF snd2 = 0 THEN SOUND 2,,0
	END IF
	IF snd3 > 0 THEN
		snd3 = snd3 - 1
		IF snd3 = 0 THEN SOUND 3,,0
	END IF
	GOTO main_loop

level_complete:
	' Award the remaining bonus and move on to the next level
	' (level 3 pending: loops back to level 1 for now).
	lvdone = 0
	#score = #score + #bonus
	GOSUB hud_score
	SOUND 2,120,12
	FOR i = 1 TO 90
		WAIT
	NEXT i
	SOUND 2,,0
	IF #score > #hi THEN
		#hi = #score
		PRINT AT CPOS(0,18),<5>#hi
	END IF
	lv = lv + 1
	IF lv > 2 THEN lv = 1
	carry = 0
	GOSUB init_level
	#lf = FRAME
	GOTO main_loop

game_over:
	gameov = 0
	PRINT AT CPOS(11,11),"GAME OVER"
	IF #score > #hi THEN #hi = #score
	FOR i = 1 TO 180
		WAIT
	NEXT i
gover_rel:
	WAIT
	IF cont1.button THEN GOTO gover_rel
gover_wait:
	WAIT
	IF cont1.button = 0 THEN GOTO gover_wait
	#score = 0
	lives = 2
	xlife = 0
	GOSUB init_level
	#lf = FRAME
	GOTO main_loop

	'
	' ---- Mack: one 1-pixel step of the state machine ----
	' Every condition is a single comparison (TI AND/OR codegen bug).
	'
mack_step:
	IF st = S_WALK THEN GOTO st_walk
	IF st = S_CLIMB THEN GOTO st_climb
	IF st = S_JUMP THEN GOTO st_jump
	IF st = S_FALL THEN GOTO st_fall
	IF st = S_RIDE THEN GOTO st_ride
	IF st = S_TRAMP THEN GOTO st_tramp
	RETURN

st_walk:
	IF jbe THEN
		' Jump (carrying the jackhammer or a brick is fine -- FIRE always
		' jumps; a long HOLD of FIRE is what drops the hammer, handled in
		' the input section). Horizontal momentum is fixed at takeoff by the
		' direction HELD: none = straight up-and-down (jhz 1), left = jhz 0,
		' right = jhz 2. So a standing jump lands in place.
		st = S_JUMP
		jix = 0
		spr2 = 0
		bonbeam = 0		' leaving the crane beam -- stop being carried
		jhz = 1
		IF jl THEN jhz = 0
		IF jr THEN jhz = 2
		RETURN
	END IF
	IF ju THEN
		' Grab a chain near the torso or head (one-cell grace each
		' side; the head pass reaches chains that hang short).
		cpy = my + 8
		GOSUB chain_at
		IF cfnd = 0 THEN
			cpy = my + 1
			GOSUB chain_at
		END IF
		IF cfnd = 1 THEN
			st = S_CLIMB
			mx = cc * 8 - 4
			my = my - 1
			RETURN
		END IF
	END IF
	IF jd THEN
		' Descend a chain that continues below this floor.
		cpy = my + 24
		GOSUB chain_at
		IF cfnd = 1 THEN
			st = S_CLIMB
			mx = cc * 8 - 4
			my = my + 1
			RETURN
		END IF
	END IF
	' Walk 1 px/step so Mack moves at the SAME speed as the characters (both
	' advance 1 px per #hd sub-step). Pace is set by the #hd accumulator.
	IF jl THEN
		mdir = 0
		IF mx > 0 THEN mx = mx - 1
	END IF
	IF jr THEN
		mdir = 1
		IF mx < 240 THEN mx = mx + 1
	END IF
	' Still supported? (bonbeam clears here; the beam branch below re-sets it)
	obonb = bonbeam			' were we riding the beam last frame?
	bonbeam = 0
	GOSUB foot_probe
	IF sup = 0 THEN
		' Off the right edge toward the trampoline channel: a generous
		' catch (anything past the floor's end) so the hop onto the
		' trampoline doesn't demand pixel-perfect timing.
		cx = mx + 14
		IF cx >= trx THEN
			GOSUB tramp_in
			RETURN
		END IF
		' Standing on the L2 crane beam? Stay put, carried by beam_move.
		GOSUB beam_sup
		IF bsup = 1 THEN
			bonbeam = 1
			my = bmy - 16
			RETURN
		END IF
		' STICKY: if he was on the beam and his centre is still over its span,
		' keep him on it even though the tight y-check missed (the beam moves
		' 2 px/frame, so a strict y-window drops -- and kills -- him for nothing).
		IF obonb = 1 THEN
			cx = mx + 8
			IF cx >= 88 THEN
				IF cx <= 135 THEN
					bonbeam = 1
					my = bmy - 16
					RETURN
				END IF
			END IF
		END IF
		bonbeam = 0
		' On a conveyor belt? It supports him AND carries him up the incline.
		GOSUB conv_sup
		IF csup = 1 THEN RETURN
		GOSUB elev_sup
		IF esup = 1 THEN
			st = S_RIDE
		ELSE
			st = S_FALL
			fcy = my
			fct = 0
		END IF
		RETURN
	END IF
	' Standing in fire is no way to make a living.
	IF ch >= T_HAZ0 THEN
		IF ch <= T_HAZ1 THEN
			GOSUB mack_die
			RETURN
		END IF
	END IF
	' Conveyor belts drag Mack along.
	IF ch >= T_CONV0 THEN
		IF ch <= T_CONV1 THEN
			IF ch < T_CONV0 + 4 THEN
				IF mx > 0 THEN mx = mx - 1
			ELSE
				IF mx < 240 THEN mx = mx + 1
			END IF
		END IF
	END IF
	' Rivet a FILLED plug the instant Mack stands on it with the drill
	' (the old 6-frame dwell missed constantly now that he walks 2 px/
	' frame and crosses the 8-px plug in ~4 frames).
	IF ch = T_FILLED THEN
		IF carry = 2 THEN GOSUB rivet_gap
	END IF
	' Pickups sit one row above their floor, at Mack's torso; walking
	' into the trampoline pedestal on the ground floor bounces.
	ch = TILE(mx + 8,my + 8)
	IF ch >= T_HAZ0 THEN
		IF ch <= T_HAZ1 THEN
			GOSUB mack_die
			RETURN
		END IF
	END IF
	IF ch = T_SPRTOP THEN GOTO walk_tramp
	IF ch = T_SPRBSE THEN GOTO walk_tramp
	IF ch = T_LBOXL THEN GOSUB take_item
	IF ch = T_BRICK THEN GOSUB take_item
	IF ch = T_WRENCH THEN GOSUB take_item
	IF ch = T_CAN THEN GOSUB take_item
	' Deposit a carried piece when standing at the edge of an open gap.
	IF carry = 1 THEN GOSUB try_fill
	RETURN
walk_tramp:
	GOSUB tramp_in
	RETURN

chain_at:
	' Find a climb-band cell at pixel row cpy under Mack's left, center,
	' or right -- cfnd/cc report the hit.
	cfnd = 0
	ch = TILE(mx + 4,cpy)
	IF ch >= T_LADD0 THEN
		IF ch <= T_LADD1 THEN
			cc = (mx + 4) / 8
			cfnd = 1
			RETURN
		END IF
	END IF
	ch = TILE(mx + 8,cpy)
	IF ch >= T_LADD0 THEN
		IF ch <= T_LADD1 THEN
			cc = (mx + 8) / 8
			cfnd = 1
			RETURN
		END IF
	END IF
	ch = TILE(mx + 12,cpy)
	IF ch >= T_LADD0 THEN
		IF ch <= T_LADD1 THEN
			cc = (mx + 12) / 8
			cfnd = 1
		END IF
	END IF
	RETURN

tramp_in:
	' Enter the trampoline channel. Remember the floor we came from:
	' the bounce delivers one level HIGHER -- except from the top
	' floor, which rides all the way down to the bottom floor.
	ery = (my + 16) / 8
	GOTO tramp_go
tramp_in2:
	' Entry from a jump/fall: measure from where the arc started.
	ery = (fcy + 16) / 8
tramp_go:
	st = S_TRAMP
	trph = 0
	' Round the entry row DOWN to a real floor row (5/9/13/17/21) --
	' entering off the pedestal top or mid-air must not shift the
	' bounce target off-floor (the "floats away above the 2nd floor"
	' bug).
	ery = ery + ((5 - ery) AND 3)
	IF ery <= 6 THEN
		trgy = 168
	ELSE
		trgy = ery * 8 - 32
	END IF
	' Center Mack in the channel for the ride.
	mx = trx + 4
	RETURN

st_tramp:
	IF trph = 0 THEN
		' Drop down the channel to the trampoline at the bottom -- EVERY
		' entry bounces off it (the top-floor entry no longer sinks
		' without a bounce; its spring target trgy is just the 1st floor).
		my = my + 2
		fy = my + 16
		IF fy >= trby THEN
			my = trby - 16
			trph = 1
			SOUND 2,300,10
			snd2 = 5
		END IF
		RETURN
	END IF
	IF trph = 1 THEN
		' Spring up: one level above the entry floor, or -- for a
		' top-floor entry (trgy = 168) -- only back to the 1st floor.
		my = my - 2
		fy = my + 16
		IF fy <= trgy THEN
			my = trgy - 16
			trph = 2
		END IF
		RETURN
	END IF
	' trph = 2: drift left out of the channel onto the floor. Mack faces the
	' way he is going (left) so he doesn't moon-walk off the trampoline.
	mdir = 0
	mx = mx - 1
	GOSUB foot_probe
	IF sup = 1 THEN st = S_WALK
	RETURN

st_climb:
	IF ju THEN
		ta = TILE(mx + 8,my + 7)
		tb = TILE(mx + 8,my + 15)
		mv = 0
		IF ta >= T_SOLID0 THEN
			IF ta <= T_LADD1 THEN mv = 1
		END IF
		IF tb >= T_SOLID0 THEN
			IF tb <= T_LADD1 THEN mv = 1
		END IF
		IF mv = 1 THEN my = my - 1
	END IF
	IF jd THEN
		tb = TILE(mx + 8,my + 17)
		mv = 0
		IF tb >= T_LADD0 THEN
			IF tb <= T_LADD1 THEN mv = 1
		END IF
		IF tb >= T_SOLID0 THEN
			IF tb <= T_SOLID1 THEN
				' Beam crossing: pass through only if the chain
				' resumes below it, otherwise this is the floor.
				tc = TILE(mx + 8,my + 25)
				IF tc >= T_LADD0 THEN
					IF tc <= T_LADD1 THEN mv = 1
				END IF
				' Arrival: allow the final pixel so the feet
				' settle exactly ON the floor top -- without
				' this the descent halts 1 px short, unaligned,
				' and the dismount check never fires (the
				' "can't get off the chain going down" bug).
				IF mv = 0 THEN
					fy = my + 17
					IF (fy AND 7) = 0 THEN mv = 1
				END IF
			END IF
		END IF
		' Off the chain's end (nothing below): release into a short
		' safe drop onto the floor beneath.
		IF mv = 0 THEN
			IF tb < T_SOLID0 THEN
				st = S_FALL
				fcy = my
				fct = 0
				RETURN
			END IF
		END IF
		IF mv = 1 THEN my = my + 1
	END IF
	' Feet flush on a solid floor: pop off the chain onto the floor
	' UNLESS actively climbing toward more chain in that direction.
	fy = my + 16
	IF (fy AND 7) = 0 THEN
		GOSUB foot_probe
		IF sup = 1 THEN
			stay = 0
			IF jd THEN
				tb = TILE(mx + 8,my + 17)
				IF tb >= T_LADD0 THEN
					IF tb <= T_LADD1 THEN stay = 1
				END IF
				IF tb >= T_SOLID0 THEN
					IF tb <= T_SOLID1 THEN
						tc = TILE(mx + 8,my + 25)
						IF tc >= T_LADD0 THEN
							IF tc <= T_LADD1 THEN stay = 1
						END IF
					END IF
				END IF
			END IF
			IF ju THEN
				ta = TILE(mx + 8,my + 7)
				IF ta >= T_SOLID0 THEN
					IF ta <= T_LADD1 THEN stay = 1
				END IF
			END IF
			IF stay = 0 THEN st = S_WALK
		END IF
	END IF
	RETURN

st_jump:
	' Horizontal drift is committed FIRST -- before the vertical move that
	' may land and RETURN -- so the landing step still contributes its pixel
	' and the span is a full 16 steps x 1 px = 16 px (2 cells). It advances
	' one step per sub-step (same clock as WALK), so sideways speed matches
	' walking and never slows mid-jump.
	' Drift 1 px/step = walk speed. 16 steps => a full 16 px (2 cells).
	IF jhz = 0 THEN
		IF mx > 0 THEN mx = mx - 1
	END IF
	IF jhz = 2 THEN
		IF mx < 240 THEN mx = mx + 1
	END IF
	' dy comes from a table of 128+dy bytes (unsigned-safe).
	v = jtab(jix)
	IF v < 128 THEN
		dv = 128 - v
		IF spr2 = 1 THEN dv = dv * 3
		FOR t8 = 1 TO dv
			' Head-bump: the 12-px art's head is at my+4, so probe my+3
			' (1 px above it). The extra head room lets the arc rise higher.
			ch = TILE(mx + 8,my + 3)
			IF ch >= T_SOLID0 THEN
				IF ch <= T_BUMP1 THEN
					jix = 8
					GOTO jump_adv
				END IF
			END IF
			my = my - 1
		NEXT t8
	ELSE
		dv = v - 128
		IF spr2 = 1 THEN dv = dv * 3
		FOR t8 = 1 TO dv
			my = my + 1
			fy = my + 16
			IF (fy AND 7) = 0 THEN
				GOSUB foot_probe
				IF sup = 1 THEN
					st = S_WALK
					RETURN
				END IF
			END IF
			' The elevator platform sits at arbitrary pixel rows,
			' so its catch runs every pixel (no VPEEK -- cheap).
			GOSUB elev_sup
			IF esup = 1 THEN
				st = S_RIDE
				RETURN
			END IF
			' Landing on the L2 crane beam (a sprite, so pixel-checked).
			GOSUB beam_sup
			IF bsup = 1 THEN
				st = S_WALK
				bonbeam = 1
				my = bmy - 16
				RETURN
			END IF
			' Landing on a conveyor belt -> start riding it up.
			GOSUB conv_sup
			IF csup = 1 THEN
				st = S_WALK
				RETURN
			END IF
		NEXT t8
	END IF
jump_adv:
	jix = jix + 1
	IF jix > 15 THEN
		' Arc exhausted without landing: free fall, measured from here.
		st = S_FALL
		fcy = my
		fct = 0
	END IF
	RETURN

st_fall:
	' Falling into the trampoline channel is a catch, not a death
	' (generous: any part of Mack over the channel counts).
	cx = mx + 14
	IF cx >= trx THEN
		GOSUB tramp_in2
		RETURN
	END IF
	dv = 3
	IF fct < 4 THEN dv = 1
	IF fct >= 4 THEN
		IF fct < 8 THEN dv = 2
	END IF
	fct = fct + 1
	FOR t8 = 1 TO dv
		my = my + 1
		fy = my + 16
		IF fy > 190 THEN
			GOSUB mack_die
			RETURN
		END IF
		IF (fy AND 7) = 0 THEN
			GOSUB foot_probe
			IF sup = 1 THEN
				GOTO fall_land
			END IF
			' Falling into the incinerator's flames.
			IF ch >= T_HAZ0 THEN
				IF ch <= T_HAZ1 THEN
					GOSUB mack_die
					RETURN
				END IF
			END IF
		END IF
		GOSUB elev_sup
		IF esup = 1 THEN GOTO fall_land
		' The L2 crane beam catches a fall too (a safe landing).
		GOSUB beam_sup
		IF bsup = 1 THEN
			my = bmy - 16
			bonbeam = 1
			st = S_WALK
			RETURN
		END IF
		' A conveyor belt catches a fall -> ride up.
		GOSUB conv_sup
		IF csup = 1 THEN
			st = S_WALK
			RETURN
		END IF
	NEXT t8
	RETURN
fall_land:
	fd2 = my - fcy
	IF fd2 > FATALFALL THEN
		GOSUB mack_die
	ELSE
		IF esup = 1 THEN
			st = S_RIDE
		ELSE
			st = S_WALK
		END IF
	END IF
	RETURN

st_ride:
	' No button: the elevator auto-starts the moment Mack is FULLY
	' aboard (centered on the 16px platform) AND it is armed. It then
	' travels non-stop to the opposite end (1st <-> 4th beam), Mack
	' locked aboard. The FAQ's "exit to re-activate" rule: armed on
	' boarding, cleared when a trip starts, re-armed only when he steps
	' off -- so it never immediately reverses.
	IF emov = 1 THEN RETURN
	IF elarm = 1 THEN
		cx = mx + 8
		IF cx >= elx + 6 THEN
			IF cx <= elx + 10 THEN
				mx = elx		' snap fully aboard
				IF ely <= elty THEN
					eld = 1
				ELSE
					eld = 0
				END IF
				emov = 1
				elarm = 0
				RETURN
			END IF
		END IF
	END IF
	' Parked: walk toward center (to board) or off onto the floor.
	IF jl THEN
		IF mx > 0 THEN mx = mx - 1
	END IF
	IF jr THEN
		IF mx < 240 THEN mx = mx + 1
	END IF
	GOSUB elev_sup
	IF esup = 0 THEN
		' Stepped off the platform -- re-arm for the next boarding.
		elarm = 1
		GOSUB foot_probe
		IF sup = 1 THEN
			st = S_WALK
		ELSE
			st = S_FALL
			fcy = my
			fct = 0
		END IF
	END IF
	RETURN

	'
	' ---- Probes ----
	'
foot_probe:
	' ch = tile under Mack's feet; sup = 1 if it holds him up.
	sup = 0
	fy = my + 16
	IF fy > 191 THEN RETURN
	ch = TILE(mx + 8,fy)
	IF ch >= T_SOLID0 THEN
		IF ch <= T_SOLID1 THEN sup = 1
	END IF
	RETURN

elev_sup:
	' esup = 1 if Mack's feet rest on the elevator platform (and if so,
	' snap him to its top). Platform top = ely, 16 px wide at elx.
	esup = 0
	cx = mx + 8
	IF cx >= elx THEN
		IF cx <= elx + 15 THEN
			fy = my + 16
			IF fy >= ely THEN
				IF fy <= ely + 3 THEN
					esup = 1
					my = ely - 16
				END IF
			END IF
		END IF
	END IF
	RETURN

	'
	' ---- Elevator: a 16x4 sprite platform shuttling its shaft ----
	'
elev_move:
	' Moves only after being boarded (emov), then parks at the far end.
	' Full speed: 1 px/frame (a shaft run takes ~2 seconds).
	IF emov = 0 THEN RETURN
	IF eld = 0 THEN
		ely = ely - 1
		IF ely <= elty THEN
			ely = elty
			emov = 0
		END IF
	ELSE
		ely = ely + 1
		IF ely >= elby THEN
			ely = elby
			emov = 0
		END IF
	END IF
	IF st = S_RIDE THEN my = ely - 16
	RETURN

	'
	' ---- Level 2: the crane BEAM that rides SMOOTHLY up and down ----
	' Rendered with CHARACTERS (not sprites): the beam is chars 179/180 at
	' cols 11-16, and beam_draw pattern-scrolls their bitmaps 1 px at a time
	' (pattern table is at VDP >0000; each 8-px bitmap zone is 2048 B). Mack
	' rides via the pixel checks (beam_sup / bonbeam) so his ride is smooth
	' too; he gets on/off by JUMPING across the 1-cell gaps to the side tiers.
	' Surface pixel-y bmy travels 48 (row 6) .. 160 (row 20).
	'
beam_move:
	IF bmon = 0 THEN RETURN
	' Advance 2 px/pass -- brisk but still smooth (beam_draw pattern-scrolls
	' the two beam chars to match). Range rows 6..21 (48..168): the lower beam
	' cell stays above the ground row (23) so it never blanks the grass.
	IF bmd = 0 THEN
		bmy = bmy - 2
		IF bmy <= 48 THEN
			bmy = 48
			bmd = 1
		END IF
	ELSE
		bmy = bmy + 2
		IF bmy >= 168 THEN
			bmy = 168
			bmd = 0
		END IF
	END IF
	IF bonbeam = 1 THEN my = bmy - 16
	RETURN

beam_sup:
	' bsup = 1 if Mack's feet rest on the beam surface and his centre is over
	' its 48-px span (cols 11-16 => pixels 88..135).
	bsup = 0
	IF bmon = 0 THEN RETURN
	fy = my + 16
	' +-4 px window: the beam moves 2 px/frame and Mack falls up to 3, so a
	' tighter window can be skipped in one step (falling THROUGH the beam).
	IF fy >= bmy - 4 THEN
		IF fy <= bmy + 4 THEN
			cx = mx + 8
			IF cx >= 88 THEN
				IF cx <= 135 THEN bsup = 1
			END IF
		END IF
	END IF
	RETURN

conv_sup:
	' csup = 1 if Mack's feet rest on a conveyor belt SURFACE. Each belt is a
	' pixel line from (cvx0,cvy0) up to (cvx1,cvy1); we test his foot against
	' that line (no tile probing, so the staggered cell gaps can't drop him),
	' snap him to it, and carry him up-and-right. Ride to the top, FIRE to jump
	' off onto the crane beam.
	csup = 0
	IF cvn = 0 THEN RETURN
	fx = mx + 8
	fy = my + 16
	FOR ci = 0 TO cvn - 1
		kx0 = cvx0(ci)
		kx1 = cvx1(ci)
		IF fx >= kx0 THEN
			IF fx <= kx1 THEN
				ky0 = cvy0(ci)
				kdy = ky0 - cvy1(ci)
				kdx = kx1 - kx0
				#cvt = fx - kx0
				#cvt = #cvt * kdy
				#cvt = #cvt / kdx
				srf = ky0 - #cvt
				IF fy >= srf - 4 THEN
					IF fy <= srf + 5 THEN
						csup = 1
						IF mx < 240 THEN mx = mx + 1
						fx = mx + 8
						#cvt = fx - kx0
						#cvt = #cvt * kdy
						#cvt = #cvt / kdx
						srf = ky0 - #cvt
						my = srf - 16
						RETURN
					END IF
				END IF
			END IF
		END IF
	NEXT ci
	RETURN

beam_draw:
	' GLITCH-FREE character beam: the bar is 16 pre-defined girder slices
	' (chars 192-207); moving it is pure NAME-TABLE placement -- no pattern or
	' color-table writes at runtime, so nothing can spill past vblank and tear.
	' The bar top sits at sub-row boff: place upper slice (192+boff) on cell
	' row brow and lower slice (200+boff) on brow+1, uniform across cols 11-16.
	IF bmon = 0 THEN RETURN
	IF bmy = bmyd THEN RETURN		' parked -- nothing to redraw
	bmyd = bmy
	boff = bmy AND 7
	brow = bmy / 8
	br3 = brow + 1
	uc = 192 + boff
	lc = 200 + boff
	' On a cell-row change, blank the two rows the beam just vacated first.
	IF brow <> bprow THEN
		#va = VADDR(bprow,11)
		FOR i = 1 TO 6
			VPOKE #va,32
			#va = #va + 1
		NEXT i
		bpr2 = bprow + 1
		#va = VADDR(bpr2,11)
		FOR i = 1 TO 6
			VPOKE #va,32
			#va = #va + 1
		NEXT i
		bprow = brow
	END IF
	' Draw the two beam rows.
	#va = VADDR(brow,11)
	FOR i = 1 TO 6
		VPOKE #va,uc
		#va = #va + 1
	NEXT i
	#va = VADDR(br3,11)
	FOR i = 1 TO 6
		VPOKE #va,lc
		#va = #va + 1
	NEXT i
	RETURN

	'
	' ---- Level 1 objective: pieces, gaps, riveting ----
	'
take_item:
	' Torso cell hit a pickup char. Bricks need free hands; wrench and
	' spray can are instant bonus points.
	r2 = (my + 8) / 8
	c2 = (mx + 8) / 8
	FOR i = 0 TO MAXITEM - 1
		IF itst(i) = 0 THEN
			IF itr(i) = r2 THEN
				IF itc(i) = c2 THEN
					IF itk(i) = 0 THEN
						IF carry <> 0 THEN RETURN
						carry = 1
						cidx = i
						SOUND 2,400,10
						snd2 = 6
					ELSEIF itk(i) = 3 THEN
						' Lunchbox: the level-2 objective.
						#score = #score + 300
						GOSUB hud_score
						SOUND 2,180,10
						snd2 = 8
						nlbr = nlbr - 1
						IF nlbr = 0 THEN lvdone = 1
					ELSE
						' Bonus tool (wrench/spray can): +200.
						#score = #score + 200
						GOSUB hud_score
						SOUND 2,180,10
						snd2 = 8
					END IF
					itst(i) = 1
					#va = VADDR(r2,c2)
					ch = T_VOID
					VPOKE #va,ch
					RETURN
				END IF
			END IF
		END IF
	NEXT i
	RETURN

try_fill:
	' Standing at either lip of an OPEN 1-cell hole on this floor drops
	' the carried plug in.
	r2 = (my + 16) / 8
	c2 = (mx + 8) / 8
	FOR i = 0 TO MAXGAP - 1
		IF gapst(i) = 0 THEN
			IF gapr(i) = r2 THEN
				hit = 0
				IF c2 + 1 = gapc(i) THEN hit = 1
				IF c2 = gapc(i) + 1 THEN hit = 1
				IF hit = 1 THEN
					gapst(i) = 1
					carry = 0
					#va = VADDR(r2,gapc(i))
					ch = T_FILLED
					VPOKE #va,ch
					#score = #score + 100
					GOSUB hud_score
					SOUND 2,200,12
					snd2 = 8
					RETURN
				END IF
			END IF
		END IF
	NEXT i
	RETURN

rivet_gap:
	' A few drill-steps crossing a FILLED plug rivet it down.
	rvt = 0
	r2 = (my + 16) / 8
	c2 = (mx + 8) / 8
	FOR i = 0 TO MAXGAP - 1
		IF gapst(i) = 1 THEN
			IF gapr(i) = r2 THEN
				IF gapc(i) = c2 THEN
					gapst(i) = 2
					#va = VADDR(r2,c2)
					ch = T_RIVET
					VPOKE #va,ch
					#score = #score + 200
					GOSUB hud_score
					SOUND 3,5,10
					snd3 = 10
					nriv = nriv + 1
					IF nriv >= ngap THEN lvdone = 1
					RETURN
				END IF
			END IF
		END IF
	NEXT i
	RETURN

	'
	' ---- Actors: jackhammer, vandal, OSHA man, bolt ----
	' Moved once per main-loop pass (not per catch-up step) -- patrol
	' speed is not pace-critical. All collisions are 12x12 boxes with
	' branch-first deltas (unsigned) and nested single-compare IFs.
	'
actors_step:
	' Per-#hd-sub-step MOVEMENT only (called once per sub-step, like
	' mack_step) so the characters advance at exactly Mack's speed. The
	' drill and the L1 vandal walk their serpentine routes here; collision
	' and the bonus clock live in actors_move (once per pass).
	IF jhtk = 0 THEN GOSUB route_drill
	IF von = 1 THEN
		IF vroute = 1 THEN GOSUB route_vand
	END IF
	RETURN

actors_move:
	atg = atg + 1
	' Jackhammer/drill: NON-LETHAL -- touch it empty-handed to catch it for
	' good, then rivet the filled gaps. (Movement is in actors_step.)
	IF jhtk = 0 THEN
		IF carry = 0 THEN
			' Grabbing the jackhammer is deliberately generous.
			ex = jhx
			ey = jhy
			hbw = 10
			hbh = 12
			GOSUB mack_hit
			IF hit = 1 THEN
				jhtk = 1
				carry = 2
				SOUND 2,150,12
				snd2 = 10
			END IF
		END IF
	END IF
	' Vandal: lethal on contact. On L1 it walks route_vand (in actors_step);
	' the old dumb patrol here stays for L2 (deferred, vroute = 0).
	IF von = 1 THEN
		IF vroute = 0 THEN
			IF vps > 0 THEN
				vps = vps - 1
			ELSE
				IF RANDOM(128) = 0 THEN vps = 25
				IF (atg AND 1) = 1 THEN
					IF vd = 1 THEN
						vx = vx + 1
						IF vx >= vmx THEN vd = 0
					ELSE
						vx = vx - 1
						IF vx <= vmn THEN vd = 1
					END IF
				END IF
			END IF
		END IF
		ex = vx
		ey = vy
		hbw = 8
		hbh = 10
		GOSUB mack_hit
		IF hit = 1 THEN GOSUB mack_die
	END IF
	' OSHA man: patrols, but stalks Mack when he is on his floor band.
	IF oon = 1 THEN
		hom = 0
		IF my >= oy THEN
			d2 = my - oy
			IF d2 <= 8 THEN hom = 1
		ELSE
			d2 = oy - my
			IF d2 <= 8 THEN hom = 1
		END IF
		IF (atg AND 1) = 1 THEN
			IF hom = 1 THEN
				' Step toward Mack, clamped to the patrol beat.
				IF mx > ox THEN
					ox = ox + 1
					IF ox >= omx THEN ox = omx
				END IF
				IF mx < ox THEN
					ox = ox - 1
					IF ox <= omn THEN ox = omn
				END IF
			ELSE
				IF od = 1 THEN
					ox = ox + 1
					IF ox >= omx THEN od = 0
				ELSE
					ox = ox - 1
					IF ox <= omn THEN od = 1
				END IF
			END IF
		END IF
		ex = ox
		ey = oy
		hbw = 8
		hbh = 10
		GOSUB mack_hit
		IF hit = 1 THEN GOSUB mack_die
	END IF
	' (Rivet fall is handled by bolt_move, called every frame at FULL speed
	' -- it is NOT scaled by the 3/4 pace so it drops as fast as it used to.)
	' Bonus ticks down while the clock runs; reaching zero kills Mack
	' (authentic). Respawn refills it to 5000 (per-life, see dead_tick).
	btk = btk - 1
	IF btk = 0 THEN
		btk = 120
		IF #bonus >= 100 THEN
			#bonus = #bonus - 100
			PRINT AT CPOS(0,2),<5>#bonus
		ELSE
			#bonus = 0
			PRINT AT CPOS(0,2),<5>#bonus
			GOSUB mack_die
		END IF
	END IF
	RETURN

bolt_move:
	' Rivet: thrown from above at Mack's position, it drifts only LEFT
	' (never right, never re-aims), bounces ONCE on each floor it meets,
	' then passes THROUGH that floor to keep descending. Called every frame
	' (ungated by the 3/4 pace) so it falls at its original full speed.
	IF bon = 0 THEN
		btm = btm - 1
		IF btm = 0 THEN
			bon = 1
			bx = mx + 48
			IF bx > 224 THEN bx = 224
			by = 16
			bph = 0
			bnx = 0
		END IF
	ELSE
		IF bx > 4 THEN
			bx = bx - 1
		ELSE
			bon = 0
			btm = 200
		END IF
		IF bph = 0 THEN
			by = by + 2
			fy = by + 16
			IF fy > 180 THEN
				bon = 0
				btm = 200
			ELSE
				' Collision is armed only below the floor it last
				' bounced on (bnx), so each level rings ONCE.
				IF fy >= bnx THEN
					ch = TILE(bx + 8,fy)
					IF ch >= T_SOLID0 THEN
						IF ch <= T_SOLID1 THEN
							bph = 1
							bct = 6
							bnx = fy + 10
						END IF
					END IF
				END IF
			END IF
		ELSE
			' The single hop off the girder.
			by = by - 2
			bct = bct - 1
			IF bct = 0 THEN bph = 0
		END IF
		' The rivet's visible art is tiny: the tightest box of all.
		ex = bx
		ey = by
		hbw = 6
		hbh = 8
		GOSUB mack_hit
		IF hit = 1 THEN GOSUB mack_die
	END IF
	RETURN

	'
	' ---- Shared route interpreter (drill + monster) ----
	' Both roam the whole building on a FIXED PREDEFINED serpentine (they
	' do NOT home on Mack -- authentic, ASchultz FAQ). Generic actor state
	' in r-vars; route_drill/route_vand copy their own state in and out.
	'   rx = pixel x, ry = sprite-top y, rb = beam 1(bottom)..5(top),
	'   rp = 0 walking / 1 climbing, rd = 1 going up / 0 going down,
	'   rf = facing (0 left / 1 right, for the walk animation).
	' Feet-on-beam b => ry = 184 - 32*b. Climb via the beam-gap chain:
	' gap g between beam g and g+1 has its chain at column chaincol(g)
	' = {1:3, 2:26, 3:3, 4:21} -- matching level1_data's edge chains.
	'
route_step:
	' rd = 2: SURVEYING a terminal beam -- walk it end to end a couple of
	' times (rsv legs). Used at BOTH the top (survey the top level, then
	' descend) and the 1st floor (walk across it, then climb back up) --
	' both are part of the authentic pattern.
	IF rd = 2 THEN
		IF rf = 1 THEN
			tcx = 208
		ELSE
			tcx = 48
		END IF
		IF rx < tcx THEN
			rx = rx + 1
		ELSE
			IF rx > tcx THEN
				rx = rx - 1
			ELSE
				IF rf = 1 THEN
					rf = 0
				ELSE
					rf = 1
				END IF
				rsv = rsv - 1
				IF rsv = 0 THEN
					IF rb >= 5 THEN
						rd = 0		' top surveyed -> descend
					ELSE
						rd = 1		' 1st floor walked -> climb
					END IF
				END IF
			END IF
		END IF
		RETURN
	END IF
	IF rd = 1 THEN
		g = rb
	ELSE
		g = rb - 1
	END IF
	' Chain columns per lower beam g (must match level1_data): beams 1 & 3
	' hang on the LEFT edge (col 3); beam 2 on the RIGHT edge (col 26);
	' beam 4->5 is the exception chain at col 21.
	cc2 = 3
	IF g = 2 THEN cc2 = 26
	IF g = 4 THEN cc2 = 21
	tcx = cc2 * 8
	IF rp = 0 THEN
		' Walk along the current beam toward the chain column.
		IF rx < tcx THEN
			rx = rx + 1
			rf = 1
		ELSE
			IF rx > tcx THEN
				rx = rx - 1
				rf = 0
			ELSE
				rp = 1
			END IF
		END IF
	ELSE
		' Climb the chain to the next beam.
		IF rd = 1 THEN
			ry = ry - 1
			tb2 = rb + 1
			tgy = 32 * tb2
			tgy = 184 - tgy
			IF ry <= tgy THEN
				ry = tgy
				rb = tb2
				rp = 0
				IF rb >= 5 THEN
					rd = 2		' reached the top -> survey it
					rsv = 4		' 4 legs = 2 round trips
					rf = 0
				END IF
			END IF
		ELSE
			ry = ry + 1
			tb2 = rb - 1
			tgy = 32 * tb2
			tgy = 184 - tgy
			IF ry >= tgy THEN
				ry = tgy
				rb = tb2
				rp = 0
				IF rb <= 1 THEN
					rd = 2		' reached 1st floor -> walk it
					rsv = 2		' 2 legs = ONCE across and back
					rf = 1
				END IF
			END IF
		END IF
	END IF
	RETURN

route_drill:
	rx = jhx
	ry = jhy
	rb = jhb
	rp = jhp
	rd = jhd
	rf = jhf
	rsv = jhsv
	GOSUB route_step
	jhx = rx
	jhy = ry
	jhb = rb
	jhp = rp
	jhd = rd
	jhf = rf
	jhsv = rsv
	RETURN

route_vand:
	rx = vx
	ry = vy
	rb = vb
	rp = vp
	rd = vdr
	rf = vf
	rsv = vsv
	GOSUB route_step
	vx = rx
	vy = ry
	vb = rb
	vp = rp
	vdr = rd
	vf = rf
	vsv = rsv
	RETURN

drop_hammer:
	' Release the jackhammer on a long FIRE hold: warp it back to its
	' original spawn with its serpentine route pattern reset, and free
	' Mack's hands so he can carry bricks again.
	carry = 0
	jhtk = 0
	jhx = jhx0
	jhy = jhy0
	jhb = jhb0
	jhp = 0
	jhd = 1
	jhf = 1
	jhsv = 0
	SOUND 2,200,8
	snd2 = 6
	RETURN

mack_hit:
	' hit = 1 if the actor at (ex,ey) overlaps Mack. The box is set by
	' the caller (hbw/hbh) and sized to the VISIBLE art, not the 16x16
	' sprite cell -- deaths must need real pixel contact.
	hit = 0
	IF st = S_DEAD THEN RETURN
	IF ex > mx THEN
		d2 = ex - mx
	ELSE
		d2 = mx - ex
	END IF
	IF d2 >= hbw THEN RETURN
	IF ey > my THEN
		d2 = ey - my
	ELSE
		d2 = my - ey
	END IF
	IF d2 >= hbh THEN RETURN
	hit = 1
	RETURN

hud_score:
	PRINT AT CPOS(0,10),<5>#score
	' One-time extra life at 10,000.
	IF xlife = 0 THEN
		IF #score >= 10000 THEN
			xlife = 1
			lives = lives + 1
			GOSUB hud_lives
			SOUND 2,140,12
			snd2 = 12
		END IF
	END IF
	RETURN

	'
	' ---- Death and respawn ----
	'
mack_die:
	IF st = S_DEAD THEN RETURN
	st = S_DEAD
	dtm = 40
	SOUND 2,600,12
	snd2 = 14
	RETURN

dead_tick:
	' Blink Mack fast while the death pause runs, then respawn at the
	' level spawn point with all level state intact.
	dtm = dtm - 1
	IF (dtm AND 4) = 0 THEN
		SPRITE 0,209,0,0,15
	ELSE
		SPRITE 0,my - 1,mx,0,6
	END IF
	IF dtm = 0 THEN
		IF lives = 0 THEN
			gameov = 1
			RETURN
		END IF
		lives = lives - 1
		GOSUB hud_lives
		' Items are NOT retained on death -- whatever Mack carried
		' returns to where it originally was.
		IF carry = 1 THEN
			' Brick: back on its original cell.
			itst(cidx) = 0
			#va = VADDR(itr(cidx),itc(cidx))
			ch = T_BRICK
			VPOKE #va,ch
		END IF
		IF carry = 2 THEN
			' Jackhammer: back to its original roaming start.
			jhtk = 0
			jhb = jhb0
			jhx = jhx0
			jhy = jhy0
			jhp = 0
			jhd = 1
			jhf = 1
		END IF
		carry = 0
		' Fresh life: the bonus clock refills to 5000 (authentic).
		#bonus = 5000
		PRINT AT CPOS(0,2),<5>#bonus
		mx = msc * 8 - 4
		my = msr * 8 - 16
		st = S_WALK
	END IF
	RETURN

	'
	' ---- Level init: paint the level and load its object tables ----
	'
init_level:
	CLS
	' BONUS starts at 5000 every level/life (authentic, ASchultz FAQ);
	' reaching zero kills Mack (see the bonus tick in actors_move).
	#bonus = 5000
	lvdone = 0
	nlbr = 0
	' No elevator/trampoline unless this level's data defines them.
	ely = 209
	emov = 0
	elx = 0
	elarm = 1		' elevator armed for its first boarding
	' HUD row 0. Only the digits are repainted in play; lives show as
	' hard hats at the right edge, like the original.
	PRINT AT CPOS(0,0),"B:"
	PRINT AT CPOS(0,8),"S:"
	PRINT AT CPOS(0,16),"H:"
	PRINT AT CPOS(0,24),"L"
	GOSUB hud_all
	' Reset per-level tables.
	FOR i = 0 TO MAXGAP - 1
		gapst(i) = 0
	NEXT i
	FOR i = 0 TO MAXITEM - 1
		itst(i) = 1
	NEXT i
	ngap = 0
	nitem = 0
	nboltc = 0
	nriv = 0
	np = 0
	carry = 0
	rvt = 0
	von = 0
	oon = 0
	bmon = 0		' crane beam off unless this level's data arms it
	bonbeam = 0
	bprow = 99		' force beam_draw to place the beam on its first pass
	bmyd = 255		' last-drawn beam y (!= any real bmy -> draw on 1st pass)
	convtog = 0		' conveyor-belt 2:1 rise toggle
	cvn = 0			' number of conveyor belts this level
	cvaf = 0		' belt animation frame toggle
	vroute = 0
	jhtk = 1
	bon = 0
	btm = 240
	btk = 120
	emov = 0
	trx = 240
	trby = 184
	IF lv = 2 THEN
		RESTORE level2_data
	ELSE
		RESTORE level1_data
	END IF
lv_parse:
	READ BYTE op
	IF op = 0 THEN RETURN
	IF op = 1 THEN
		' Horizontal platform run.
		READ BYTE r
		READ BYTE c
		READ BYTE n
		READ BYTE t
		IF t = 0 THEN ch = T_GIRD
		IF t = 1 THEN ch = T_GIRD2
		IF t = 2 THEN ch = T_GROUND
		IF t = 3 THEN ch = T_GIRDO
		IF t = 4 THEN ch = T_HAZ0
		IF t = 5 THEN ch = T_HAZ0 + 2
		#va = VADDR(r,c)
		FOR i = 1 TO n
			VPOKE #va,ch
			#va = #va + 1
		NEXT i
		GOTO lv_parse
	END IF
	IF op = 2 THEN
		ch = T_CHAIN
		GOTO lv_vrun
	END IF
	IF op = 3 THEN
		ch = T_PILLAR
		GOTO lv_vrun
	END IF
	IF op = 4 THEN
		ch = T_PED
		GOTO lv_vrun
	END IF
	IF op = 7 THEN
		ch = T_CABLE
		GOTO lv_vrun
	END IF
	IF op = 6 THEN
		' Conveyor MACHINE, up-right at a shallow 2:1 slope: a cyan roller drum
		' at the bottom-left, n belt cells rising 1 row every 2 cells (belt-lo
		' then belt-hi), a cyan drum at the top-right, and a yellow support post
		' from under the top drum down to the platform. r,c = bottom drum cell.
		READ BYTE r
		READ BYTE c
		READ BYTE n
		#va = VADDR(r,c)
		ch = 158			' bottom roller drum
		VPOKE #va,ch
		rr = r
		cc = c
		FOR i = 1 TO n
			cc = cc + 1
			IF (i AND 1) = 1 THEN
				ch = 156		' belt-lo (first of the pair)
			ELSE
				ch = 157		' belt-hi (second, then step up)
			END IF
			#va = VADDR(rr,cc)
			VPOKE #va,ch
			IF (i AND 1) = 0 THEN
				rr = rr - 1
				' The belt steps up a row here; fill the corner cell above this
				' column with belt-lo so the diagonal band has NO empty gap at
				' the staircase step (and it animates like the rest).
				#va = VADDR(rr,cc)
				VPOKE #va,156
			END IF
		NEXT i
		cc = cc + 1
		#va = VADDR(rr,cc)
		ch = 158			' top roller drum
		VPOKE #va,ch
		' Yellow support post down to the platform the bottom drum stands on.
		FOR pr = rr + 1 TO r
			#va = VADDR(pr,cc)
			ch = 159
			VPOKE #va,ch
		NEXT pr
		' Record the belt as a pixel SURFACE line: bottom (at the low drum) to
		' top (at the high drum). conv_sup rides this line -- no cell gaps.
		cvx0(cvn) = c * 8
		cvy0(cvn) = r * 8 + 2
		cvx1(cvn) = cc * 8 + 7
		cvy1(cvn) = rr * 8 + 2
		cvn = cvn + 1
		GOTO lv_parse
	END IF
	' op = 5: object entry. Dispatched with ON GOTO -- a long ELSEIF
	' chain here miscompiled on the TI backend (the parse died at a
	' build-address-dependent entry; see DESIGN.md).
	READ BYTE t
	' CVBasic ON GOTO is 0-BASED (value 0 = first label).
	t = t - 1
	ON t GOTO ob_gap,ob_brick,ob_jack,ob_bonus,lv_parse,ob_elev,ob_sprng,ob_pail,ob_magnet,ob_beam,ob_vand,ob_osha,ob_spawn,ob_bolt
	GOTO lv_parse

ob_beam:
	' Crane beam (level 2): a 48-px SPRITE platform (3 sprites, cols 11-16)
	' that rides SMOOTHLY up and down the shaft (1 px/frame). bmy = its
	' surface pixel-y; Mack jumps on/off across the 1-cell side gaps.
	READ BYTE r
	bmy = r * 8		' surface pixel-y (feet rest here)
	bmd = 0			' 0 = rising, 1 = falling
	bmon = 1
	GOTO lv_parse

ob_magnet:
	' Electromagnet head at the top of the crane (level 2). Two chars wide;
	' its cell is remembered (mgr/mgc) for the endgame lift.
	READ BYTE r
	READ BYTE c
	mgr = r
	mgc = c
	#va = VADDR(r,c)
	ch = T_MAGNET
	VPOKE #va,ch
	#va = #va + 1
	ch = T_MAGNET + 1
	VPOKE #va,ch
	GOTO lv_parse

ob_pail:
	' Lunchbox (level 2): a 1-cell pickup; collecting all of them
	' clears the level.
	READ BYTE r
	READ BYTE c
	itr(nitem) = r
	itc(nitem) = c
	itst(nitem) = 0
	itk(nitem) = 3
	nitem = nitem + 1
	nlbr = nlbr + 1
	#va = VADDR(r,c)
	ch = T_LBOXL
	VPOKE #va,ch
	GOTO lv_parse

ob_gap:
	READ BYTE r
	READ BYTE c
	gapr(ngap) = r
	gapc(ngap) = c
	ngap = ngap + 1
	GOTO lv_parse

	' NOTE (TI landmine): VPOKE operands must be PLAIN VARIABLES.
	' An expression operand compiles to a push/pop on the r10 stack
	' around the VDP call, and that window randomly loses a race
	' against the vblank ISR -- the return stack corrupts and the
	' program jumps wild at the next RETURN. Precompute into #va/ch.
ob_brick:
	READ BYTE r
	READ BYTE c
	itr(nitem) = r
	itc(nitem) = c
	itst(nitem) = 0
	itk(nitem) = 0
	nitem = nitem + 1
	#va = VADDR(r,c)
	ch = T_BRICK
	VPOKE #va,ch
	GOTO lv_parse

ob_bonus:
	READ BYTE k
	READ BYTE r
	READ BYTE c
	itr(nitem) = r
	itc(nitem) = c
	itst(nitem) = 0
	itk(nitem) = k
	nitem = nitem + 1
	#va = VADDR(r,c)
	ch = T_BRICK + k
	VPOKE #va,ch
	GOTO lv_parse

ob_jack:
	' Drill start on the serpentine route: r = beam row, c = start col
	' (n unused -- kept for stream layout). Beam = (25-r)/4.
	READ BYTE r
	READ BYTE c
	READ BYTE n
	jhy = r * 8 - 16
	jhx = c * 8
	jhb = (25 - r) / 4
	' Remember the drill's original start so death returns it here.
	jhy0 = jhy
	jhx0 = jhx
	jhb0 = jhb
	jhp = 0
	jhd = 1
	jhf = 1
	jhtk = 0
	GOTO lv_parse

ob_elev:
	' Elevator: a 16x4 sprite platform (not chars) shuttling between
	' rtop and rbot; starts at the bottom.
	READ BYTE elc
	READ BYTE elrt
	READ BYTE elrb
	elx = elc * 8
	elty = elrt * 8
	elby = elrb * 8
	ely = elby
	eld = 0
	GOTO lv_parse

ob_sprng:
	' Trampoline: ONE character tall (a low cap a 1st-floor player can
	' jump over), 2 cols wide at the base of the right-side channel.
	' Payload: r = cap row, c = left column. trx/trby drive the
	' S_TRAMP ride.
	READ BYTE r
	READ BYTE c
	trx = c * 8
	trby = r * 8
	#va = VADDR(r,c)
	ch = T_SPRTOP
	VPOKE #va,ch
	#va = #va + 1
	VPOKE #va,ch
	GOTO lv_parse

ob_vand:
	READ BYTE r
	READ BYTE c
	READ BYTE n
	' L2 patrol vars (used only when vroute = 0).
	vy = r * 8 - 16
	vx = c * 8
	vmn = c * 8
	vmx = n * 8
	vd = 1
	von = 1
	' L1 serpentine route vars: beam from row, start walking up.
	vb = (25 - r) / 4
	vp = 0
	vdr = 1
	vf = 1
	IF lv = 1 THEN
		vroute = 1
	ELSE
		vroute = 0
	END IF
	GOTO lv_parse

ob_osha:
	READ BYTE r
	READ BYTE c
	READ BYTE n
	oy = r * 8 - 16
	ox = c * 8
	omn = c * 8
	omx = n * 8
	od = 1
	oon = 1
	GOTO lv_parse

ob_spawn:
	' Feet sit on top of floor row r: 16-px sprite top = r*8-16,
	' sprite x centers the 16-px box on cell c.
	READ BYTE msr
	READ BYTE msc
	my = msr * 8 - 16
	mx = msc * 8 - 4
	st = S_WALK
	GOTO lv_parse

ob_bolt:
	READ BYTE c
	bcol(nboltc) = c
	nboltc = nboltc + 1
	GOTO lv_parse

lv_vrun:
	' Vertical run of char ch: col, top row, height.
	READ BYTE c
	READ BYTE r
	READ BYTE n
	#va = VADDR(r,c)
	FOR i = 1 TO n
		VPOKE #va,ch
		#va = #va + 32
	NEXT i
	GOTO lv_parse

	'
	' ---- HUD ----
	'
hud_all:
	PRINT AT CPOS(0,2),<5>#bonus
	PRINT AT CPOS(0,10),<5>#score
	PRINT AT CPOS(0,18),<5>#hi
	PRINT AT CPOS(0,25),lv
	GOSUB hud_lives
	RETURN

hud_lives:
	' Remaining lives as hard-hat icons, cols 28-30.
	#va = VADDR(0,28)
	FOR i = 0 TO 2
		IF i < lives THEN
			ch = T_HAT
		ELSE
			ch = T_VOID
		END IF
		VPOKE #va,ch
		#va = #va + 1
	NEXT i
	RETURN

	'
	' ---- Level 1: "Beams and Bolts" -- the building framework ----
	' Per the ColecoVision reference (assets/HHM-CV-Level1.png) plus the
	' user's mechanics notes:
	' (Whole layout is shifted 1 col right vs. the original transcription.)
	' - 5 girder floors rows 5/9/13/17/21, spanning cols 3-26. Cols 27-28 =
	'   a 2-cell JUMPABLE GAP; cols 29-30 = the trampoline channel (bounce =
	'   one level up; from the top floor it rides all the way to the bottom).
	' - 4 one-cell HOLES to plug, STACKED on the left at col 11 for beams
	'   1/2/3 (rows 21/17/13) plus beam 4's hole at col 18 (row 9); 4 brick
	'   stacks at col 9 (beams 2/3/4) and col 21 (beam 1).
	' - Chains (climbable) hang from the girder EDGES: beam1<->2 and
	'   beam3<->4 on the LEFT (col 3), beam2<->3 on the RIGHT (col 26);
	'   beam4<->5 is the exception at col 21. Braces cols 6/23 = art.
	' - Elevator cols 1-2: boarded at bottom or top floor, it travels
	'   the FULL shaft to the other end and parks.
	'
level1_data:
	' Whole layout shifted 1 col RIGHT vs. the transcription (elevator at
	' cols 1-2, building cols 3-26). Chains (climbable) and braces first:
	' floors paint over them, so beams cross in front and the crossing cell
	' stays solid. Chains hang 2 cells from the upper girder's underside and
	' do NOT touch the girder below (climb off the end with a short drop).
	DATA BYTE 2, 3,18,2		' chain beam1<->beam2 (left edge, col 3)
	DATA BYTE 2, 26,14,2		' chain beam2<->beam3 (right edge, col 26)
	DATA BYTE 2, 3,10,2		' chain beam3<->beam4 (left edge, col 3)
	DATA BYTE 2, 21,6,2		' chain beam4<->beam5 (exception: col 21)
	DATA BYTE 3, 6,6,15		' support braces (art only): left col 6,
	DATA BYTE 3, 23,6,15		'   right col 23
	' Pedestal bases under the bottom girder (art only), under the braces.
	DATA BYTE 4, 6,22,2
	DATA BYTE 4, 14,22,2
	DATA BYTE 4, 23,22,2
	' Floors span cols 3-26. Beams 1-4 each carry a 1-cell hole; the TOP
	' beam (row 5) is solid. Holes on beams 1/2/3 stack at col 11; beam 4's
	' hole is at col 18.
	DATA BYTE 1, 5,3,24,0		' top beam (solid, cols 3-26)
	DATA BYTE 1, 9,3,15,0		' beam4 left  (cols 3-17, hole at 18)
	DATA BYTE 1, 9,19,8,0		' beam4 right (cols 19-26)
	DATA BYTE 1, 13,3,8,0		' beam3 left  (cols 3-10, hole at 11)
	DATA BYTE 1, 13,12,15,0		' beam3 right (cols 12-26)
	DATA BYTE 1, 17,3,8,0		' beam2 left  (cols 3-10, hole at 11)
	DATA BYTE 1, 17,12,15,0		' beam2 right (cols 12-26)
	DATA BYTE 1, 21,3,8,0		' 1st floor left  (cols 3-10, hole at 11)
	DATA BYTE 1, 21,12,15,0		' 1st floor right (cols 12-26; 0-2 = pit)
	' Objects. FOUR holes + FOUR bricks (any brick fills any hole); the
	' drill and the vandal roam fixed serpentine routes (no OSHA on L1 --
	' a second enemy is deferred difficulty progression).
	DATA BYTE 5,13, 21,23		' Mack spawn: right side of the bottom beam
	DATA BYTE 5,7, 23,29		' trampoline: bottom (row 23), cols 29-30
	DATA BYTE 5,1, 21,11		' hole: 1st floor (beam 1)
	DATA BYTE 5,1, 9,18		' hole: beam 4
	DATA BYTE 5,1, 13,11		' hole: beam 3
	DATA BYTE 5,1, 17,11		' hole: beam 2
	DATA BYTE 5,2, 8,9		' brick: beam 4 (torso row 8)
	DATA BYTE 5,2, 12,9		' brick: beam 3
	DATA BYTE 5,2, 16,9		' brick: beam 2
	DATA BYTE 5,2, 20,21		' brick: 1st floor (torso row 20)
	DATA BYTE 5,4,1, 4,21		' bonus wrench: top beam (torso row 4)
	DATA BYTE 5,4,2, 20,25		' bonus spray can: 1st floor (clear of braces)
	DATA BYTE 5,3, 21,4,25		' drill starts bottom-left (beam 1)
	DATA BYTE 5,6, 1,9,21		' elevator: cols 1-2, 4th beam..1st beam
	DATA BYTE 5,11, 13,6,13		' vandal starts on beam 3 (col 6)
	DATA BYTE 0

	'
	' ---- Level 2: "Lunch Break" -- the construction site ----
	' Transcribed from assets/HHM-CV-Level2.png: a central CRANE POLE down
	' the middle (col 16) with the ELECTROMAGNET on top (row 2), stepped
	' girder platforms left/right on tiers 5/9/13/17/21 (ground row 23), two
	' diagonal CONVEYORS (upper-right escalator, lower-left belt), a right-
	' side CHAIN, and the INCINERATOR pot bottom-center. Collect all 6 lunch
	' pails to clear (magnet endgame is a later pass).
	'
level2_data:
	' Positions measured from the ColecoVision reference (32x24 cell grid).
	' Platforms are cols 2-9 (left) and 18-25 (right) on tiers rows 9/13/17,
	' a top crane platform cols 11-17 (r5), ground r23. The CENTRE is the
	' moving CRANE BEAM (op 5 sub 10, cols 11-16) that rides up and down --
	' Mack JUMPS on and off it to reach the side tiers (NO chains). A short
	' cable + the magnet sit above it.
	DATA BYTE 7, 14,3,2		' cable stub col 14, rows 3-4 (holds the magnet)
	DATA BYTE 1, 5,11,7,1		' top crane platform (cols 11-17)
	DATA BYTE 1, 9,2,8,1		' left  upper (cols 2-9)
	DATA BYTE 1, 9,18,8,1		' right upper (cols 18-25)
	DATA BYTE 1, 13,2,8,1		' left  mid   (cols 2-9)
	DATA BYTE 1, 13,18,8,1		' right mid   (cols 18-25)
	DATA BYTE 1, 17,2,8,1		' left  lower (cols 2-9)
	DATA BYTE 1, 17,18,8,1		' right lower (cols 18-25)
	DATA BYTE 1, 23,2,28,2		' ground (cols 2-29, type 2)
	' Conveyor MACHINES (op 6: bottom-drum row,col, belt-cell count). Shallow
	' 2:1 up-right belt with cyan drums at both ends + a yellow support post.
	DATA BYTE 6, 8,19,5		' right conveyor: drum (8,19) -> top drum ~(6,25)
	DATA BYTE 6, 22,5,4		' left conveyor: drum (22,5) -> top drum ~(20,10),
					' delivering up-right to the beam shaft (cols 11-16)
	' Electromagnet head above the shaft; moving crane beam starts at r13.
	DATA BYTE 5,9, 2,13
	DATA BYTE 5,10, 13		' crane beam, starts on the middle tier (r13)
	' Incinerator pot on the ground, off the beam's column path (hazard).
	DATA BYTE 1, 22,19,2,4
	' Six lunch pails on the side tiers.
	DATA BYTE 5,8, 9,4
	DATA BYTE 5,8, 9,20
	DATA BYTE 5,8, 13,4
	DATA BYTE 5,8, 13,20
	DATA BYTE 5,8, 17,4
	DATA BYTE 5,8, 17,20
	' Vandal patrols the right mid tier.
	DATA BYTE 5,11, 13,18,25
	' Mack spawns on the GROUND, below the beam's shaft; the beam rides down
	' to row 22 (1 cell up) so he can jump aboard from the ground.
	DATA BYTE 5,13, 23,7
	DATA BYTE 0

jump_data:
	' 128+dy: a ROUND parabola, apex 11 px (the ceiling max now the
	' characters are 12 px -- head at my+4, probe my+3 clears row 18). Steep
	' at launch and landing, flat over the top, for a rounded curve. 8 up
	' then 8 down = 16 steps; 1 px/step drift => a full 16 px (2 cells).
	' dy = -2,-2,-2,-1,-1,-1,-1,-1,+1,+1,+1,+1,+1,+2,+2,+2
	DATA BYTE 126,126,126,127,127,127,127,127,129,129,129,129,129,130,130,130

	'
	' ---- Tile patterns and colors ----
	' Colors are 8 bytes per char (fg<<4|bg per pixel row); background 1
	' (black) everywhere so sprites pass in front cleanly.
	'
tile_pat:
	' 128 girder: red stripe top AND bottom, blue body with black dash
	' holes (the ColecoVision look)
	DATA BYTE $FF,$FF,$DB,$FF,$DB,$FF,$FF,$00
	' 129 girder variant (level 2): SOLID full-height bar (reference is a solid
	' red/blue/red girder, no dash-holes, fills the whole cell)
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	' 130 girder orange (level 3; colors differ)
	DATA BYTE $FF,$FF,$DB,$FF,$DB,$FF,$FF,$00
	' 131 FILLED gap: plain body, no rivet holes yet
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$00
	' 132 RIVETED gap: bright rivet dots
	DATA BYTE $FF,$FF,$A5,$FF,$A5,$FF,$FF,$00
	' 133 ground strip (levels 2/3): solid grass band (top 4 px), black below
	DATA BYTE $FF,$FF,$FF,$FF,$00,$00,$00,$00
	' 134 (spare solid)
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	' 135/136 elevator platform chars (reserved; the L1 elevator is a sprite)
	DATA BYTE $FF,$FF,$C0,$C0,$00,$00,$00,$00
	DATA BYTE $FF,$FF,$03,$03,$00,$00,$00,$00
	' 137 springboard top plate (red cap)
	DATA BYTE $7E,$FF,$FF,$3C,$3C,$3C,$3C,$3C
	' 138 springboard coil (striped pedestal)
	DATA BYTE $3C,$3C,$3C,$3C,$3C,$3C,$7E,$FF
tile_col:
	' 128: red stripes, dark-blue body
	DATA BYTE $61,$41,$41,$41,$41,$41,$61,$11
	' 129 (L2): 2px red top edge, 4px blue body, 2px red bottom edge -- the
	' measured reference girder (red a9433f / blue 706bdf)
	DATA BYTE $61,$61,$51,$51,$51,$51,$61,$61
	' 130: white stripes, dark-red body (L3)
	DATA BYTE $F1,$61,$61,$61,$61,$61,$F1,$11
	' 131 FILLED: all dark-blue
	DATA BYTE $41,$41,$41,$41,$41,$41,$41,$11
	' 132 RIVETED: red stripes, white rivet dots punch the body
	DATA BYTE $61,$F1,$F1,$F1,$F1,$F1,$61,$11
	' 133 ground: green grass (top 2 px) over yellow-olive dirt (measured
	' reference: 3aaf40 green / a0a94a olive)
	DATA BYTE $31,$31,$A1,$A1,$11,$11,$11,$11
	' 134 spare: gray
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	' 135/136 elevator chars: white
	DATA BYTE $F1,$F1,$F1,$F1,$11,$11,$11,$11
	DATA BYTE $F1,$F1,$F1,$F1,$11,$11,$11,$11
	' 137 springboard cap: red over white column
	DATA BYTE $61,$61,$61,$F1,$F1,$F1,$F1,$F1
	' 138 springboard pedestal: white, red flare at the foot
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$61,$61
chain_pat:
	' Hanging chain, climbable (cyan links)
	DATA BYTE $18,$3C,$24,$3C,$18,$3C,$24,$3C
chain_col:
	DATA BYTE $71,$71,$71,$71,$71,$71,$71,$71
pillar_pat:
	' 174 support pillar: dotted box column (art only)
	DATA BYTE $7E,$5A,$7E,$7E,$5A,$7E,$7E,$5A
	' 175 pedestal base under the bottom girder (art only)
	DATA BYTE $3C,$3C,$3C,$3C,$3C,$7E,$FF,$FF
pillar_col:
	' pillar: dark blue like the girders
	DATA BYTE $41,$41,$41,$41,$41,$41,$41,$41
	' pedestal: white with red foot
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$61,$61,$61
item_pat:
	' 185 brick stack (girder piece)
	DATA BYTE $00,$7E,$5A,$7E,$5A,$7E,$5A,$7E
	' 186 wrench
	DATA BYTE $00,$63,$63,$3E,$1C,$38,$70,$60
	' 187 spray can
	DATA BYTE $10,$3C,$18,$3C,$3C,$3C,$3C,$3C
	' 188 hard hat (HUD lives icon)
	DATA BYTE $00,$18,$3C,$7E,$7E,$FF,$00,$00
item_col:
	' brick stack: dark red
	DATA BYTE $61,$61,$61,$61,$61,$61,$61,$61
	' wrench: white
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	' spray can: magenta
	DATA BYTE $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
	' hat: yellow
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
pail_pat:
	' Lunch pail (from the reference): domed white lid, latch band, red body,
	' white base -- a stout lunchbox.
	DATA BYTE $3C,$7E,$FF,$FF,$FF,$FF,$FF,$7E
pail_col:
	' white dome+lid, gray latch band, red body, red base
	DATA BYTE $F1,$F1,$F1,$F1,$E1,$61,$61,$61
haz_pat:
	' 164 incinerator pot (white outline)
	DATA BYTE $FF,$81,$81,$81,$81,$81,$FF,$7E
	' 165 spare
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	' 166 flame
	DATA BYTE $10,$54,$38,$7C,$BA,$FE,$7C,$38
haz_col:
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $61,$61,$61,$61,$61,$61,$61,$61
	DATA BYTE $B1,$91,$91,$B1,$91,$B1,$91,$61
conv_pat:
	' Conveyor MACHINE (4 chars, 156-159), matched to the reference: a shallow
	' 2:1 white belt with dark oval holes, cyan roller drums at both ends, and
	' a yellow support post. op 6 assembles these into the escalator.
	' 156 belt-low: the belt is TWO thin white rails (top+bottom edge) with a
	' dark interior and a white centre DOT -- the reference's ladder-like belt.
	' Lower half of the cell, rising 2:1.
	DATA BYTE $00,$03,$0C,$30,$D3,$0C,$30,$C0
	' 157 belt-high: same two-rail belt 4 px higher (with its own centre dot) so
	' the pair tiles into one continuous belt at the 2:1 slope.
	DATA BYTE $D3,$0C,$30,$C0,$00,$03,$0C,$30
	' 158 roller drum: a big cyan cylinder end-cap (fills the cell -- the
	' reference drums are large, prominent cylinders, not small dots)
	DATA BYTE $3C,$7E,$FF,$FF,$FF,$FF,$7E,$3C
	' 159 support post: a vertical yellow strut
	DATA BYTE $18,$18,$18,$18,$18,$18,$18,$18
conv_col:
	' belt white, belt white, drum cyan, post yellow
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $71,$71,$71,$71,$71,$71,$71,$71
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
	' Belt scroll phases 0-7: three chars each -- belt-lo, belt-hi (conv_pat's
	' two belt chars ROTATED up 0..7 px, both by the same amount so they keep
	' tiling) AND the roller drum (158) with a spoke rotated to the matching
	' phase. Cycling 0->1->...->7->0 scrolls the belt up 1 px/step and spins the
	' rollers; 8 phases = one full rotation, so it loops seamlessly (no shake).
belt_anim0:
	DATA BYTE $00,$03,$0C,$30,$D3,$0C,$30,$C0
	DATA BYTE $D3,$0C,$30,$C0,$00,$03,$0C,$30
	DATA BYTE $18,$7E,$7E,$00,$00,$7E,$7E,$18
belt_anim1:
	DATA BYTE $03,$0C,$30,$D3,$0C,$30,$C0,$00
	DATA BYTE $0C,$30,$C0,$00,$03,$0C,$30,$D3
	DATA BYTE $18,$7E,$1E,$07,$E0,$78,$7E,$18
belt_anim2:
	DATA BYTE $0C,$30,$D3,$0C,$30,$C0,$00,$03
	DATA BYTE $30,$C0,$00,$03,$0C,$30,$D3,$0C
	DATA BYTE $18,$1E,$0E,$C7,$E3,$70,$78,$18
belt_anim3:
	DATA BYTE $30,$D3,$0C,$30,$C0,$00,$03,$0C
	DATA BYTE $C0,$00,$03,$0C,$30,$D3,$0C,$30
	DATA BYTE $08,$4E,$4E,$E7,$E7,$72,$72,$10
belt_anim4:
	DATA BYTE $D3,$0C,$30,$C0,$00,$03,$0C,$30
	DATA BYTE $00,$03,$0C,$30,$D3,$0C,$30,$C0
	DATA BYTE $00,$66,$66,$E7,$E7,$66,$66,$00
belt_anim5:
	DATA BYTE $0C,$30,$C0,$00,$03,$0C,$30,$D3
	DATA BYTE $03,$0C,$30,$D3,$0C,$30,$C0,$00
	DATA BYTE $10,$72,$72,$E7,$E7,$4E,$4E,$08
belt_anim6:
	DATA BYTE $30,$C0,$00,$03,$0C,$30,$D3,$0C
	DATA BYTE $0C,$30,$D3,$0C,$30,$C0,$00,$03
	DATA BYTE $18,$78,$70,$E3,$C7,$0E,$1E,$18
belt_anim7:
	DATA BYTE $C0,$00,$03,$0C,$30,$D3,$0C,$30
	DATA BYTE $30,$D3,$0C,$30,$C0,$00,$03,$0C
	DATA BYTE $18,$7E,$78,$E0,$07,$1E,$7E,$18
mag_pat:
	' 176/177 electromagnet: a HORSESHOE (U) magnet, arch on top, two legs
	' hanging down to grab Mack -- matches the reference's white/red magnet.
	DATA BYTE $1F,$3F,$3C,$38,$38,$38,$38,$3C
	DATA BYTE $F8,$FC,$3C,$1C,$1C,$1C,$1C,$3C
mag_col:
	' white arch, red pole tips (classic horseshoe magnet)
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$61,$61
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$61,$61
cable_pat:
	' 178 thin crane cable: a 2-px centered vertical line
	DATA BYTE $18,$18,$18,$18,$18,$18,$18,$18
cable_col:
	' light-blue cable
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51
beamshift_pat:
	' 8 UPPER-cell slices (192-199): a solid girder bar whose TOP is at sub-row
	' boff (0..7); rows above the bar are empty.
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF	' 192 boff0 (full girder)
	DATA BYTE $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF	' 193 boff1
	DATA BYTE $00,$00,$FF,$FF,$FF,$FF,$FF,$FF	' 194 boff2
	DATA BYTE $00,$00,$00,$FF,$FF,$FF,$FF,$FF	' 195 boff3
	DATA BYTE $00,$00,$00,$00,$FF,$FF,$FF,$FF	' 196 boff4
	DATA BYTE $00,$00,$00,$00,$00,$FF,$FF,$FF	' 197 boff5
	DATA BYTE $00,$00,$00,$00,$00,$00,$FF,$FF	' 198 boff6
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$FF	' 199 boff7
	' 8 LOWER-cell slices (200-207): the bottom boff rows of the bar spill into
	' the cell below; rest empty. 200 (boff0) is blank.
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00	' 200 boff0 (blank)
	DATA BYTE $FF,$00,$00,$00,$00,$00,$00,$00	' 201 boff1
	DATA BYTE $FF,$FF,$00,$00,$00,$00,$00,$00	' 202 boff2
	DATA BYTE $FF,$FF,$FF,$00,$00,$00,$00,$00	' 203 boff3
	DATA BYTE $FF,$FF,$FF,$FF,$00,$00,$00,$00	' 204 boff4
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$00,$00,$00	' 205 boff5
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$00,$00	' 206 boff6
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$00	' 207 boff7
beamshift_col:
	' Girder banding red($61) top2 / blue($51) mid4 / red top2, sliced to match
	' each pattern so the bands travel WITH the bar. $11 = black (empty rows).
	DATA BYTE $61,$61,$51,$51,$51,$51,$61,$61	' 192
	DATA BYTE $11,$61,$61,$51,$51,$51,$51,$61	' 193
	DATA BYTE $11,$11,$61,$61,$51,$51,$51,$51	' 194
	DATA BYTE $11,$11,$11,$61,$61,$51,$51,$51	' 195
	DATA BYTE $11,$11,$11,$11,$61,$61,$51,$51	' 196
	DATA BYTE $11,$11,$11,$11,$11,$61,$61,$51	' 197
	DATA BYTE $11,$11,$11,$11,$11,$11,$61,$61	' 198
	DATA BYTE $11,$11,$11,$11,$11,$11,$11,$61	' 199
	DATA BYTE $11,$11,$11,$11,$11,$11,$11,$11	' 200 (blank)
	DATA BYTE $61,$11,$11,$11,$11,$11,$11,$11	' 201
	DATA BYTE $61,$61,$11,$11,$11,$11,$11,$11	' 202
	DATA BYTE $51,$61,$61,$11,$11,$11,$11,$11	' 203
	DATA BYTE $51,$51,$61,$61,$11,$11,$11,$11	' 204
	DATA BYTE $51,$51,$51,$61,$61,$11,$11,$11	' 205
	DATA BYTE $51,$51,$51,$51,$61,$61,$11,$11	' 206
	DATA BYTE $61,$51,$51,$51,$51,$61,$61,$11	' 207
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

	'
	' ---- Sprites ----
	'
mack_bitmap:
	' Mack in profile facing RIGHT, standing (frame 0). Art is 12 px tall,
	' bottom-anchored (top 4 rows blank) so his head clears the floor above
	' and the jump can arc higher; feet stay on row 15 for exact floor math.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXX....."
	BITMAP "......XXXX.X...."
	BITMAP ".......XXX......"
	BITMAP ".....XXXXXX....."
	BITMAP ".....XXXXXX....."
	BITMAP "......XXXXX....."
	BITMAP "......XXXX......"
	BITMAP ".....XX.XX......"
	BITMAP ".....X...X......"
	BITMAP "....XX...XX....."
	BITMAP "...XXX...XXX...."

mackw_bitmap:
	' Mack facing RIGHT, running stride (frame 44). 12 px, bottom-anchored.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXX....."
	BITMAP "......XXXX.X...."
	BITMAP ".......XXX......"
	BITMAP "....XXXXXXX....."
	BITMAP "...X.XXXXXX.X..."
	BITMAP "......XXXXX....."
	BITMAP "......XXXX......"
	BITMAP ".....XXXX......."
	BITMAP "....XX..XX......"
	BITMAP "...XX....XXX...."
	BITMAP "..XX.......XX..."

mackl_bitmap:
	' Mack facing LEFT, standing (frame 48) -- mirror. 12 px, bottom-anchored.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXX....."
	BITMAP "....X.XXXX......"
	BITMAP "......XXX......."
	BITMAP ".....XXXXXX....."
	BITMAP ".....XXXXXX....."
	BITMAP ".....XXXXX......"
	BITMAP "......XXXX......"
	BITMAP "......XX.XX....."
	BITMAP "......X...X....."
	BITMAP ".....XX...XX...."
	BITMAP "....XXX...XXX..."

mackl2_bitmap:
	' Mack facing LEFT, running stride (frame 52) -- mirror. 12 px, anchored.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXX....."
	BITMAP "....X.XXXX......"
	BITMAP "......XXX......."
	BITMAP ".....XXXXXXX...."
	BITMAP "...X.XXXXXX.X..."
	BITMAP ".....XXXXX......"
	BITMAP "......XXXX......"
	BITMAP ".......XXXX....."
	BITMAP "......XX..XX...."
	BITMAP "....XXX....XX..."
	BITMAP "...XX.......XX.."

mackj_bitmap:
	' Mack airborne: arms out, legs spread mid-leap. 12 px, bottom-anchored.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".....XXXXXX....."
	BITMAP "....XXXXXXXX...."
	BITMAP "....X.XXXX.X...."
	BITMAP ".X...XXXX...X..."
	BITMAP ".XX.XXXXXX.XX..."
	BITMAP "..XXXXXXXXXX...."
	BITMAP ".....XXXXXX....."
	BITMAP "....XXXXXXXX...."
	BITMAP "...XXX....XXX..."
	BITMAP "..XXX......XXX.."
	BITMAP "..XX........XX.."
	BITMAP "................"

elev_bitmap:
	' Elevator platform: a 16x4 slab (rest transparent).
	BITMAP "XXXXXXXXXXXXXXXX"
	BITMAP "XXXXXXXXXXXXXXXX"
	BITMAP "X..X..X..X..X..X"
	BITMAP "XXXXXXXXXXXXXXXX"
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

vandal_bitmap:
	' The vandal: wild mohawk, arms out. 12 px, bottom-anchored.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "....X.X.X.X....."
	BITMAP ".....XXXXX......"
	BITMAP ".....X.X.X......"
	BITMAP "....XXXXXXX....."
	BITMAP "..XX.XXXXX.XX..."
	BITMAP ".....XXXXX......"
	BITMAP "......XXX......."
	BITMAP ".....XX.XX......"
	BITMAP ".....X...X......"
	BITMAP ".....X...X......"
	BITMAP "....XX...XX....."
	BITMAP "....X.....X....."

osha_bitmap:
	' The OSHA man: hat, coat, clipboard. 12 px, bottom-anchored.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".....XXXXX......"
	BITMAP "....XXXXXXX....."
	BITMAP ".....X.X.X......"
	BITMAP "....XXXXXXX....."
	BITMAP "...X.XXXXX.XXX.."
	BITMAP "...X.XXXXX.XXX.."
	BITMAP "....XXXXXXX....."
	BITMAP ".....XXXXX......"
	BITMAP ".....XX.XX......"
	BITMAP ".....X...X......"
	BITMAP "....XX...XX....."
	BITMAP "....X.....X....."

bolt_bitmap:
	' A falling bolt (small -- most of the box is transparent).
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXX......."
	BITMAP ".......X........"
	BITMAP "......XXX......."
	BITMAP ".......X........"
	BITMAP "......XXX......."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"

jack_bitmap:
	' The jackhammer: T-handle, body, bit. 12 px, bottom-anchored to match
	' the shortened characters (and so the carried tool doesn't tower over
	' Mack's head).
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "....XXXXXXX....."
	BITMAP "....X..X..X....."
	BITMAP ".....XXXXX......"
	BITMAP ".....XXXXX......"
	BITMAP ".....XXXXX......"
	BITMAP ".....XXXXX......"
	BITMAP "......XXX......."
	BITMAP "......XXX......."
	BITMAP ".......X........"
	BITMAP ".......X........"
	BITMAP "......XXX......."
	BITMAP "................"

brick_bitmap:
	' Carried girder piece: the brick stack, held overhead.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "....XXXXXXXX...."
	BITMAP "....X.XX.XX....."
	BITMAP "....XXXXXXXX...."
	BITMAP "....XX.XX.X....."
	BITMAP "....XXXXXXXX...."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"

vandal2_bitmap:
	' The vandal, walk frame B: legs togetherish. 12 px, bottom-anchored.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "....X.X.X.X....."
	BITMAP ".....XXXXX......"
	BITMAP ".....X.X.X......"
	BITMAP "....XXXXXXX....."
	BITMAP "...X.XXXXX.X...."
	BITMAP ".....XXXXX......"
	BITMAP "......XXX......."
	BITMAP "......XXX......."
	BITMAP "......X.X......."
	BITMAP "......X.X......."
	BITMAP ".....XX.XX......"
	BITMAP ".....X...X......"

jack2_bitmap:
	' The jackhammer, frame B: bit driven down (impact). 12 px, anchored.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "....XXXXXXX....."
	BITMAP "....X..X..X....."
	BITMAP ".....XXXXX......"
	BITMAP ".....XXXXX......"
	BITMAP ".....XXXXX......"
	BITMAP "......XXX......."
	BITMAP "......XXX......."
	BITMAP ".......X........"
	BITMAP ".......X........"
	BITMAP ".......X........"
	BITMAP ".......X........"
	BITMAP "......XXX......."
