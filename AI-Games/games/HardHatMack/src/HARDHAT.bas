	'
	' Hard Hat Mack -- TI-99/4A + ColecoVision (CVBasic, dual-target)
	'
	' Adaptation of the Apple II classic by Michael Abbot and
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
	'   - DIM n(N) is N elements, indices 0..N-1 -- size it to the LARGEST
	'     INDEX PLUS ONE (DIM jtab(15) for a 16-step arc cost days: the last
	'     step of every jump read a neighbouring variable as its dy)
	'   - array out-of-bounds is Coleco-FATAL -- exact sizes
	'   - TI fixed-program cap 24,336 B -- build-ti.sh guards it
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
	CONST T_GIRD   = 128	'   plain girder: blue body, red edges
	CONST T_GIRD2  = 129	'   girder variant (level 2)
	CONST T_GIRDO  = 130	'   girder, orange (level 3)
	CONST T_FILLED = 131	'   gap FILLED by a girder piece (plain body)
	CONST T_RIVET  = 132	'   repaired gap, plain unless girder_mark selects rivets
	CONST T_GIRDR  = 134	' rivet section: recolored for the current site
	CONST T_GROUND = 133	'   ground strip (levels 2/3)
	CONST T_ELEV   = 236	'   parked elevator platform chars
	CONST T_PAD    = 139	'   level-3 trampoline pad: stand on it and be
				'   launched a whole beam upward (spr2 arc)
	CONST T_PAD_R  = 141	' right factory spring: two independent animated halves
	CONST T_SPRTOP = 137	'   animated springboard left half
	CONST T_SPRBSE = 138	'   animated springboard right half
	CONST T_SOLID1 = 151
	CONST T_BUMP1  = 134	' head-bump range end: only girders/ground stop
				' a rising jump -- springboard and elevator chars
				' must let the bounce pass through
	CONST T_LADD0  = 152	' 152-155: climbable
	CONST T_CHAIN  = 152	'   hanging chain (THE climbing element)
	CONST T_PNL    = 153	'   pater-noster shaft, LEFT rail  (level 3)
	CONST T_PNR    = 154	'   pater-noster shaft, RIGHT rail (level 3)
	CONST T_CHAING = 155	'   green chain (level 3); 152 stays cyan for L1
	CONST T_LADD1  = 155
	CONST T_CONV0  = 156	' 156-163: conveyor belts (L/R x 2 anim frames)
	CONST T_CONVB  = 156	'   conveyor belt tile (level 2)
	CONST T_CONVH  = 161	'   FLAT belt tile (level 3's horizontal machine)
	CONST T_MIXBAS = 162	'   cement-mixer stand (decor)
	CONST T_DRUM   = 163	'   oil drum (level 3 ground decor)
				'   162/163 are the last free codes and they sit in
				'   the CONVEYOR band because the decor band is
				'   full. Safe: the belt-drag test only runs when
				'   Mack is STANDING on the probed tile, and only
				'   128-151 support him -- so it cannot reach these.
	CONST T_CONV1  = 163
	CONST T_HAZ0   = 164	' 164-171: touch = death
	CONST T_HAZ1   = 171
	' 172+: pass-through decoration and pickups
	CONST T_PLANK  = 172	' 172: stack of planks (level 2 decor, pass-through)
	CONST T_MACH   = 180	' 180-181: the right-hand machine cabinet (level 2)
	CONST T_DOOR   = 173	' 173: level-3 processor door panel (decor)
	CONST T_STAND  = 179	' 179: trampoline stand under a pad (decor)
	CONST T_PILLAR = 174	' support pillar (art only -- NOT solid)
	CONST T_PED    = 175	' pedestal base under the bottom girder (art)
	CONST T_INM    = 191	' level-3 IN hopper: deliver a steel box here
	CONST T_MAGNET = 176	' 176-177: electromagnet head (level 2, top of crane)
	CONST T_CABLE  = 178	' 178: thin crane cable (level 2 centre pole, art)
	CONST T_BEAM   = 192	' 192-207: 16 pre-shifted crane-beam girder slices
				'   placed by beam_draw, name-table only (level 2)
	CONST T_SBOX   = 182	' level-3 steel box. Deliberately ONE BELOW the
				' lunchbox so the pickup band stays a single
				' contiguous range 182-188.
	CONST T_LBOXL  = 183	' lunchbox (2 cells, level 2)
	CONST T_LBOXR  = 184
	CONST T_BRICK  = 185	' loose girder piece: 1-cell diagonal girder
	CONST T_WRENCH = 186	' bonus wrench (+200)
	CONST T_CAN    = 187	' bonus spray can (+200)
	CONST T_HAT    = 188	' hard hat (HUD lives icon)
	#if TI994A
	CONST HUD_BONUS_COL = 16
	#else
	CONST HUD_BONUS_COL = 21
	#endif

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

	#if TI994A
	BANK ROM 128
	BANK SELECT 1
	#endif

	CONST MAXITEM = 8	' girder pieces (L1) / lunchboxes (L2) / boxes (L3)
	CONST MAXGAP  = 4
	CONST MAXBOLTC = 4

	DIM gapr(MAXGAP)	' gap -> floor row
	DIM gapc(MAXGAP)	' gap -> left col (4 wide)
	DIM gapitem(MAXGAP)
	DIM gapst(MAXGAP)	' gap -> 0 open / 1 filled / 2 riveted
	DIM itr(MAXITEM)	' item -> cell row
	DIM itc(MAXITEM)	' item -> cell col (items are 1 cell)
	DIM itst(MAXITEM)	' item -> 0 present / 1 taken
	DIM itk(MAXITEM)	' item -> kind: 0 brick, 1 wrench, 2 spray can
	DIM bcol(MAXBOLTC)	' bolt drop columns
	' 16 ELEMENTS for 16 arc steps: CVBasic DIM n(N) is indices 0..N-1, so
	' DIM jtab(15) stopped at 14 and the last step of every jump read (and
	' the init loop wrote) one byte past the end -- a neighbouring variable.
	' See the jump-arc note in the header.
	DIM girder_mark(32)
	DIM jtab(16)		' jump arc: 128+dy per step (unsigned-safe)
	' Conveyor belts as pixel SURFACES (bottom pixel x0,y0 -> top pixel x1,y1),
	' so Mack rides a continuous line and never drops into the cell gaps.
	DIM pnxcar(4)
	DIM pnycar(4)
	DIM drillx(18)
	DIM drilly(18)
	DIM cvdir(3)	' 0 = carries right/up, 1 = carries LEFT
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
	' Pixels of drop that break Mack's neck. Must sit BETWEEN two real
	' distances in the level geometry:
	'   22 px = stepping off the top of a conveyor onto the platform that
	'           machine stands on (upper: row 6 -> row 9; lower: row 20 ->
	'           ground). This MUST be survivable -- at 20 it killed you for
	'           riding the lower conveyor to its end, with no other way off.
	'   L2's upper right-hand belt exit is explicitly fatal (upper_belt_edge).
	'   32 px = falling a whole storey (tiers/floors are 4 rows apart). This
	'           MUST stay fatal -- it's the classic Hard Hat Mack hazard.
	CONST FATALFALL = 26

	'
	' One-time setup. Default video mode (do NOT use MODE 2 -- it renders
	' broken on both targets); per-character colors via DEFINE COLOR.
	'
boot:
	CLS
	BORDER 1

	' 16x16 sprite defs, NO magnification (VDP(1)=$E2): Mack is a 16-px
	' figure -- floor rows are 4 cells (32 px) apart, and the original's
	' actors stand about half a floor gap tall. (Structris/Astiroids use
	' $E3 2x-magnify for 32-px pieces; that scale would be wrong here.)
	VDP(1) = $E2
	SPRITE FLICKER OFF

	GOSUB game_chars

	' HUD/text: white on transparent for the whole ASCII range.
	DEFINE COLOR 32,16,txt_white
	WAIT
	DEFINE COLOR 48,16,txt_white
	WAIT
	DEFINE COLOR 64,16,txt_white
	WAIT
	DEFINE COLOR 80,16,txt_white
	DEFINE COLOR 96,16,txt_white
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
	DEFINE SPRITE 15,5,mack_colour
	' Patterns 31-34: right white/purple, left white/purple recovery stride.
	' Dance owns 27-30; sprite slots remain 0 and 8 for both Mack layers.
	DEFINE SPRITE 31,4,mack_run_extra
	GOSUB mack_air_chars
	DEFINE SPRITE 20,1,lift_bitmap
	DEFINE SPRITE 21,1,cage_bitmap
	DEFINE SPRITE 22,1,steel_bitmap
	DEFINE SPRITE 23,1,magnet_bitmap
	DEFINE SPRITE 25,2,slag_bitmap
	DEFINE SPRITE 14,1,cable_bitmap		' crane cable link (frame 56)

	' Four-channel effects; completion fanfare plays between sites.

	' Jump arc into RAM (dy = value - 128; 10 px apex, 16 steps).
	RESTORE jump_data
	FOR i = 0 TO 15
		READ BYTE jtab(i)
	NEXT i

	RESTORE drill_route
	FOR i = 0 TO 17
		READ BYTE drillx(i)
		READ BYTE drilly(i)
	NEXT i

new_game:
	dclean = 0
	title_abort = 0
	lv = 1
	levelno = 1
	lives = 2
	game838 = 0
	#score = 0
	xlife = 0
	#bonus = 5000
	GOSUB title_screen
	IF title_abort THEN GOTO new_game
	' Remove title artwork (and the 838 confirmation screen) before gameplay
	' reuses their character slots. Clearing after DEFINE CHAR visibly corrupts
	' the title while the new patterns are being uploaded.
	CLS
	GOSUB game_chars
	GOSUB init_level

main_loop:
	' Wait only when this update has not already crossed a video frame.
	IF FRAME = #lf THEN WAIT
	' Moving surfaces are drawn after simulation, alongside their riders.
	' FRAME-delta pacing (shared convention with Structris): a missed
	' vblank becomes a catch-up step, not a slowdown. #fd is the number
	' of real frames since the last pass, clamped so a pause can't
	' teleport anything.
	#fd = FRAME - #lf
	#lf = FRAME
	IF #fd > 4 THEN #fd = 4
	' Age sounds from the PREVIOUS pass before this pass starts new effects.
	' Otherwise a busy frame can turn a fresh two-frame sound off immediately.
	GOSUB sound_tick
	GOSUB back_key
	IF backreq THEN GOTO new_game
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
	IF jb THEN
		IF jbhc < 45 THEN
			jbhc = jbhc + #fd
			IF jbhc >= 45 THEN
				jbhc = 45
				IF carry = 2 THEN GOSUB drop_hammer
			END IF
		END IF
	ELSE
		jbhc = 0
	END IF
	IF st = S_DEAD THEN
		GOSUB dead_tick
		IF gameov = 1 THEN GOTO game_over
	ELSE
		FOR s8 = 1 TO #hd
			GOSUB world_step
		NEXT s8
	END IF
	GOSUB beam_draw
	GOSUB lift_draw
	GOSUB site_draw
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
		' Four beats per eight walked pixels: pass, stride, pass, recovery.
		' Passive conveyor motion does not cycle Mack's legs.
		IF jl + jr THEN
			IF steptick AND 2 THEN
				mfr = mstr
				IF steptick AND 4 THEN mfr = mstr + 80
			END IF
		END IF
	END IF
	IF st = S_JUMP THEN mfr = 32
	IF st = S_FALL THEN mfr = 32
	IF st = S_TRAMP THEN mfr = 32
	IF mfr = 32 THEN
		IF mdir = 0 THEN mfr = 140
	END IF
	IF edance THEN mfr = dancebody
	IF st <> S_DEAD THEN
		SPRITE 0,my - 1,mx,mfr,15
		mcf = 60
		IF mfr = 44 THEN mcf = 64
		IF mfr = 48 THEN mcf = 68
		IF mfr = 52 THEN mcf = 72
		IF mfr = 32 THEN mcf = 76
		IF mfr >= 124 THEN mcf = mfr + 4
		IF edance THEN mcf = dancecolour
		SPRITE 8,my - 1,mx,mcf,13
	ELSE
		IF burnfall THEN
			SPRITE 8,my - 1,mx,148,11
		ELSE
			SPRITE 8,209,0,0,0
		END IF
	END IF
	GOSUB elev_draw
	' Crane cable link: bottom edge exactly on the beam, so the rope stays
	' attached at every sub-cell offset instead of snapping between rows.
	IF bmon = 1 THEN
		SPRITE 7,bmy - 17,112,56,5
	ELSE
		SPRITE 7,209,0,0,0
	END IF
	GOSUB inventory_draw
	GOSUB enemy_draw
	IF bon = 1 THEN
		SPRITE 6,by - 1,bx,20,15
	ELSE
		SPRITE 6,209,0,0,0
	END IF
	' L2 crane beam is rendered with CHARACTERS (pattern-scrolled), see
	' beam_draw -- called from the movement path, not here.
	' Finish drawing this frame before freezing the completed site for the
	' bonus tally and fanfare. init_level clears it only after the award.
	IF lvdone = 1 THEN GOTO level_complete
	GOTO main_loop

inventory_draw:
	#if TI994A
	BANK SELECT 3
	#endif
	GOSUB banked_inventory_draw
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

girder_chars:
	#if TI994A
	BANK SELECT 3
	#endif
	GOSUB banked_girder_chars
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

game_chars:
	' Playfield tiles, colored per char (DEFINEs are synchronous on the
	' TI runtime -- verified in cvbasic_9900_prologue.asm).
	DEFINE CHAR 224,1,bell_pat
	DEFINE COLOR 224,1,bell_col
	DEFINE COLOR 238,5,claw_col
	DEFINE CHAR 227,4,cage_bitmap
	DEFINE COLOR 227,4,cage_col
	DEFINE CHAR T_ELEV,2,VARPTR tile_pat(56)
	DEFINE COLOR T_ELEV,2,VARPTR tile_col(56)
	' 225-226 are exclusive to the lower conveyor valve. The thrower owns
	' 232-235 and previously overwrote the valve's right-hand tile.
	DEFINE CHAR 225,2,spigot_pat
	DEFINE COLOR 225,2,spigot_col
	DEFINE CHAR T_SOLID0,11,tile_pat
	DEFINE COLOR T_SOLID0,11,tile_col
	DEFINE CHAR T_CHAIN,1,chain_pat
	DEFINE CHAR T_CHAING,1,chain_pat	' 155 same links, green (level 3)
	DEFINE COLOR T_CHAING,1,chaing_col
	DEFINE COLOR T_CHAIN,1,chain_col
	DEFINE CHAR T_PILLAR,2,pillar_pat		' 174 pillar, 175 pedestal
	DEFINE COLOR T_PILLAR,2,pillar_col
	DEFINE CHAR T_BRICK,4,item_pat			' 185-188 brick/wrench/can/hat
	DEFINE COLOR T_BRICK,4,item_col
	' Level 2 tiles: lunch pail, incinerator/flame, conveyor belt, magnet.
	DEFINE CHAR T_LBOXL,2,pail_pat	' 183 lunch pail, 184 toolbox
	DEFINE COLOR T_LBOXL,2,pail_col
	GOSUB fixture_chars
	DEFINE CHAR T_INM,1,inm_pat	' 191 level-3 IN hopper
	DEFINE COLOR T_INM,1,inm_col
	DEFINE CHAR T_MIXBAS,2,mixb_pat	' 162/163 receiver lower halves
	DEFINE COLOR T_MIXBAS,2,mixb_col
	DEFINE CHAR 208,2,pn_pat	' 153-154 pater-noster shaft rails
	DEFINE COLOR 208,2,pn_col
	DEFINE CHAR T_STAND,1,stand_pat	' 179 trampoline stand
	DEFINE COLOR T_STAND,1,stand_col
	DEFINE CHAR T_SBOX,1,sbox_pat	' 182 level-3 steel box
	DEFINE COLOR T_SBOX,1,sbox_col
	DEFINE CHAR T_PAD,4,pad_pat	' 139 level-3 trampoline pad
	DEFINE COLOR T_PAD,4,pad_col
	DEFINE CHAR T_CONVH,1,convh_pat	' 161 flat conveyor belt
	DEFINE COLOR T_CONVH,1,convh_col
	DEFINE CHAR T_DOOR,1,door_pat	' 182 processor door
	DEFINE COLOR T_DOOR,1,door_col
	DEFINE CHAR T_PLANK,1,plank_pat	' 172 plank stack (level 2 decor)
	DEFINE COLOR T_PLANK,1,plank_col
	DEFINE CHAR T_MACH,2,mach_pat	' 180-181 machine cabinet (level 2)
	DEFINE COLOR T_MACH,2,mach_col
	DEFINE CHAR 189,2,mixer_pat	' cement mixer (decor)
	DEFINE COLOR 189,2,mixer_col
	DEFINE CHAR T_HAZ0,3,haz_pat
	DEFINE COLOR T_HAZ0,3,haz_col
	DEFINE CHAR T_CONV0,5,conv_pat		' 156-160 full/bottom/top/drum/post
	DEFINE COLOR T_CONV0,5,conv_col
	DEFINE CHAR T_MAGNET,2,mag_pat
	DEFINE COLOR T_MAGNET,2,mag_col
	DEFINE CHAR T_CABLE,1,cable_pat
	DEFINE COLOR T_CABLE,1,cable_col
	' Crane beam: 16 PRE-SHIFTED girder slices (chars 192-207) -- upper cell
	' 192-199 (bar top at sub-row 0..7), lower cell 200-207. beam_draw just
	' places these in the name table (no per-frame pattern/color rewriting ->
	' no tearing/fragments). DEFINE triple-copies to all 3 bitmap zones so the
	' beam looks identical at any screen height.

	RETURN

fixture_chars:
	#if TI994A
	BANK SELECT 3
	#endif
	GOSUB banked_fixture_chars
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

mack_air_chars:
	#if TI994A
	BANK SELECT 4
	#endif
	GOSUB banked_mack_air_chars
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

fixture_draw:
	IF lv <> 3 THEN RETURN
	#if TI994A
	BANK SELECT 3
	#endif
	GOSUB banked_fixture_draw
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

factory_output:
	IF boxfall < 2 THEN RETURN
	workfx = 255
	#if TI994A
	BANK SELECT 2
	#endif
	GOSUB banked_factory_output
	#if TI994A
	BANK SELECT 1
	#endif
	IF workfx = 4 THEN GOSUB work_sound
	RETURN

tone_start:
	' Separate reward notes from jump/death so pickups cannot cut a jump short.
	sfxkind = 0
	IF #sndpitch = 600 THEN sfxkind = 1
	IF #sndpitch = 300 THEN sfxkind = 2
	IF #sndpitch = 360 THEN sfxkind = 2
	IF sndkind = 1 THEN
		IF snd2 > 0 THEN RETURN
	END IF
	IF sfxkind = 0 THEN
		#rewardpitch = #sndpitch
		snd0 = sfxlen + 8
		snd0v = sndvol
		SOUND 0,#rewardpitch,snd0v
		RETURN
	END IF
	sndkind = sfxkind
	snd2 = sfxlen
	snd2v = sndvol
	#motionpitch = #sndpitch
	IF sndkind = 1 THEN
		SOUND 0,,0
		SOUND 1,,0
		SOUND 3,6,10
		snd0 = 0
		snd1 = 0
		snd3 = 10
	END IF
	SOUND 2,#motionpitch,snd2v
	RETURN

footstep_sound:
	' Two alternating boot taps; machinery takes priority over the tonal layer.
	IF snd1 = 0 THEN
		stepflip = 1 - stepflip
		#steppitch = 740
		IF stepflip = 1 THEN #steppitch = 900
		SOUND 1,#steppitch,7
		snd1 = 2
	END IF
	IF snd3 = 0 THEN
		SOUND 3,4,7
		snd3 = 2
	END IF
	RETURN

reset_claws:
	' Factory sparks borrow the middle-third hazard cells. Restore them for
	' every site/death before that site's animation paints its own version.
	DEFINE VRAM 3360,16,haz_pat
	DEFINE VRAM 11552,16,haz_col
	clawstep = 0
	clawclock = 0
	clawlast = 255
	presslast = 255
	pressfootlast = 255
	fixturelast = 255
	drivelast = 255
	chainlast = 255
	firelast = 255
	firecolorlast = 255
	sparklast = 255
	firedepth = 0
	RETURN

machine_clack:
	' Metallic ring over a short noise impact; never interrupt death/riveting.
	IF snd3 > 3 THEN RETURN
	SOUND 1,180,10
	snd1 = 6
	SOUND 3,5,8
	snd3 = 3
	RETURN

work_sound:
	' Material/mechanism cues share the short effect channels, leaving jump
	' and reward voices alone. Death and longer metallic impacts have priority.
	IF st = S_DEAD THEN RETURN
	IF snd3 > 3 THEN RETURN
	IF snd1 > 2 THEN RETURN
	#if TI994A
	BANK SELECT 2
	#endif
	GOSUB banked_work_sound
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

sound_tick:
	#if TI994A
	BANK SELECT 2
	#endif
	GOSUB banked_sound_tick
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

completion_music:
	#if TI994A
	BANK SELECT 2
	#endif
	GOSUB banked_completion_music
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

bonus_countdown:
	' Transfer 100 points per audible tick; keep the final partial award exact.
	IF #bonus = 0 THEN RETURN
bonus_count_step:
	#bonus_slice = 100
	IF #bonus < 100 THEN #bonus_slice = #bonus
	#bonus = #bonus - #bonus_slice
	#award = #bonus_slice / 5
	GOSUB add_score
	GOSUB hud_score
	PRINT AT CPOS(0,HUD_BONUS_COL),<.4>#bonus
	' A single WAIT can end almost immediately at the next interrupt.
	' A quiet noise pulse reads as a tick, with at least one full frame on.
	SOUND 3,5,7
	WAIT
	WAIT
	SOUND 3,,0
	WAIT
	WAIT
	IF #bonus > 0 THEN GOTO bonus_count_step
	RETURN

level_complete:
	' Award the remaining bonus and move on to the next level
	' (after level 3, loop back to level 1).
	lvdone = 0
	GOSUB quiet_audio
	GOSUB bonus_countdown
	GOSUB completion_music
	IF #score > #hi THEN
		#hi = #score
		hi838 = game838
	END IF
	levelno = levelno + 1
	lv = lv + 1
	IF lv > 3 THEN lv = 1
	carry = 0
	GOSUB init_level
	#lf = FRAME
	GOTO main_loop

game_over:
	GOSUB quiet_screen
	' The death reset paints the parked cabin as characters. Do not redraw its
	' sprite pair here; the end screen keeps scenery while all gameplay sprites
	' (including a loose/carried jackhammer) remain hidden.
	gameov = 0
	#lastscore = #score
	last838 = game838
	' One blank character around all four sides of the message.
	PRINT AT CPOS(10,10),"           "
	PRINT AT CPOS(11,10)," GAME OVER "
	PRINT AT CPOS(12,10),"           "
	IF #score > #hi THEN
		#hi = #score
		hi838 = game838
	END IF
	' 75 video frames = 1.25 seconds before a fresh Fire; 600 = auto-title.
	GOSUB gameover_wait
	GOTO new_game

gameover_wait:
	#go_start = FRAME
gover_rel:
	WAIT
	GOSUB back_key
	IF backreq THEN RETURN
	#go_age = FRAME - #go_start
	IF #go_age >= 600 THEN RETURN
	IF #go_age < 75 THEN GOTO gover_rel
	IF cont1.button THEN GOTO gover_rel
gover_wait:
	WAIT
	GOSUB back_key
	IF backreq THEN RETURN
	#go_age = FRAME - #go_start
	IF #go_age >= 600 THEN RETURN
	IF cont1.button = 0 THEN GOTO gover_wait
	RETURN

back_key:
	backreq = 0
	#if TI994A
	' KSCAN reports FCTN first, so its 254 code cannot identify REDO/BACK.
	' Read physical FCTN plus the 8/9 row (Keystone's proven TI scanner).
	ASM LIMI 0
	ASM LI R12,>0024
	ASM CLR R0
	ASM LDCR R0,3
	ASM SRC R12,7
	ASM LI R12,>0006
	ASM STCR R2,8
	ASM LI R1,>1000
	ASM CZC R1,R2
	ASM JNE hhm_back_done
	ASM LI R12,>0024
	ASM LI R0,>0100
	ASM LDCR R0,3
	ASM SRC R12,7
	ASM LI R12,>0006
	ASM STCR R2,8
	ASM LI R1,>0800
	ASM CZC R1,R2
	ASM JEQ hhm_back_pressed
	ASM LI R12,>0024
	ASM LI R0,>0200
	ASM LDCR R0,3
	ASM SRC R12,7
	ASM LI R12,>0006
	ASM STCR R2,8
	ASM CZC R1,R2
	ASM JNE hhm_back_done
	ASM hhm_back_pressed:
	ASM LI R0,>0100
	ASM MOVB R0,@cvb_BACKREQ
	ASM hhm_back_done:
	ASM LIMI 2
	' Inline ASM does not invalidate CVBasic's cached R0 value.
	ASM MOVB @cvb_BACKREQ,R0
	#endif
	RETURN

title_screen:
	#if TI994A
	BANK SELECT 3
	#endif
	GOSUB banked_title
	GOSUB quiet_screen
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

	'
	' ---- Mack: one 1-pixel step of the state machine ----
	' Every condition is a single comparison (TI AND/OR codegen bug).
	'
world_step:
	' A single simulation clock for Mack, enemies, hazards and platforms.
	' Stop immediately on death: no later catch can revive him in this tick.
	IF st = S_DEAD THEN RETURN
	GOSUB mack_step
	IF st = S_DEAD THEN RETURN
	GOSUB actors_step
	GOSUB actors_move
	IF st = S_DEAD THEN RETURN
	IF lv = 1 THEN
		GOSUB bolt_move
		IF st = S_DEAD THEN RETURN
		GOSUB elev_move
	ELSE
		GOSUB beam_move
		IF lv = 2 THEN
			GOSUB mag_move
			GOSUB mag_catch
		END IF
	END IF
	GOSUB site_step
	RETURN

mack_step:
	IF st = 8 THEN RETURN
	IF st = 9 THEN RETURN
	IF st = 7 THEN GOTO spring_transfer
	IF st = S_WALK THEN GOTO st_walk
	IF st = S_CLIMB THEN GOTO st_climb
	IF st = S_JUMP THEN GOTO st_air
	IF st = S_FALL THEN GOTO st_air
	IF st = S_RIDE THEN GOTO st_ride
	IF st = S_TRAMP THEN GOTO st_tramp
	RETURN

st_air:
	' Release Fire before grabbing: a jump off a chain must clear it first.
	IF jb = 0 THEN GOSUB grab_chain
	IF st = S_CLIMB THEN RETURN
	IF st = S_JUMP THEN GOTO st_jump
	GOTO st_fall

grab_chain:
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
	RETURN

start_jump:
	' Jump (carrying the jackhammer or a brick is fine -- FIRE always
	' jumps; a long HOLD of FIRE is what drops the hammer, handled in
	' the input section). Horizontal momentum is fixed at takeoff by the
	' direction HELD: none = straight up-and-down (jhz 1), left = jhz 0,
	' right = jhz 2. So a standing jump lands in place.
	jbe = 0
	jhang = 16
	#sndpitch = 360
	sndvol = 8
	sfxlen = 12
	GOSUB tone_start
	st = S_JUMP
	bmp1 = 0	' head-bump allowed once per jump
	jix = 0
	spr2 = 0
	fcy = my		' fall origin: tracks the arc's apex while rising
	bonbeam = 0		' leaving the crane beam -- stop being carried
	jhz = 1
	IF jl THEN
		jhz = 0
		mdir = 0
	END IF
	IF jr THEN
		jhz = 2
		mdir = 1
	END IF
	RETURN

st_walk:
	' A normal floor approach may use both springs. Only a fall directly
	' off a rotating panel keeps the fatal centreward spring route.
	IF lv = 3 THEN
		IF bonbeam = 0 THEN springfatal = 0
	END IF
	IF jbe THEN GOTO start_jump
	GOSUB grab_chain
	IF st = S_CLIMB THEN RETURN
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
	walkx = mx
	IF jl THEN
		mdir = 0
		IF mx > 0 THEN mx = mx - 1
	END IF
	IF jr THEN
		mdir = 1
		IF mx < 240 THEN mx = mx + 1
	END IF
	GOSUB upper_belt_edge
	IF st = S_DEAD THEN RETURN
	' A short shoe scuff every eight pixels of active walking. Rivets retain
	' priority on the noise channel; passive belt travel makes no footsteps.
	IF mx <> walkx THEN
		steptick = (steptick + 1) AND 7
		IF steptick = 0 THEN
			GOSUB footstep_sound
		END IF
	END IF
	' Still supported? (bonbeam clears here; the beam branch below re-sets it)
	obonb = bonbeam			' were we riding the beam last frame?
	bonbeam = 0
	GOSUB foot_probe
	IF sup = 0 THEN
		' NOTE: walking off the right edge is NOT a free ride to the
		' trampoline. There is no catch here -- he simply falls, and st_fall
		' decides whether he was far enough out to land on the pad. Reaching
		' the trampoline is a JUMP you can miss.
		' Standing on the L2 crane beam? Stay put, carried by beam_move.
		GOSUB beam_sup
		IF bsup = 1 THEN
			bonbeam = 1
			my = bmy - 16
			RETURN
		END IF
		' STICKY: if he was on the beam and his art still overlaps its span,
		' keep him on it even though the tight y-check missed (the beam moves
		' 2 px/frame, so a strict y-window drops -- and kills -- him for nothing).
		' Same overlap rule as beam_sup, or he would slide off the edge he is
		' allowed to land on.
		IF lv = 3 THEN
			IF obonb = 1 THEN springfatal = 1
			obonb = 0
		END IF
		IF obonb = 1 THEN
			cx = mx + 13
			IF cx >= 96 THEN
				cx = mx + 2
				IF cx <= 135 THEN
					bonbeam = 1
					my = bmy - 16
					RETURN
				END IF
			END IF
		END IF
		bonbeam = 0
		' On a conveyor belt? It supports him AND carries him along it. The
		' belt path returns early, so the torso checks that the normal walk
		' does further down have to happen HERE too -- otherwise level 3's
		' grinder at the end of the belt could not kill and the box riding
		' the belt could not be picked up.
		GOSUB conv_sup
		IF st = S_DEAD THEN RETURN
		IF csup = 1 THEN
			ch = TILE(mx + 8,my + 8)
			IF ch >= T_HAZ0 THEN
				IF ch <= T_HAZ1 THEN GOSUB mack_die
			END IF
			IF ch >= T_SBOX THEN
				IF ch <= T_HAT THEN GOSUB take_item
			END IF
			RETURN
		END IF
		GOSUB elev_sup
		IF esup = 1 THEN
			st = S_RIDE
		ELSE
			st = S_FALL
			fcy = my
			fct = 0
			jhz = 1
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
	' Factory pads use the same compression/rebound as the level-one spring.
	' Normalize their separate graphics codes before testing foot contact.
	IF ch <> T_PAD THEN padok = 1	' stepped off: the pads are live again
	IF ch = T_PAD THEN
		IF lv = 3 THEN GOTO spring_begin
		IF padok = 0 THEN RETURN	' already bounced off this one
		padok = 0
		st = S_JUMP
		bmp1 = 0
		jix = 0
		spr2 = 1
		fcy = my
		jhz = 1
		IF jl THEN jhz = 0
		IF jr THEN jhz = 2
		#sndpitch = 300
		sndvol = 10
		sfxlen = 5
		GOSUB tone_start
		RETURN
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
	IF lv = 3 THEN GOSUB deliver_zone
	' Any char in the pickup band 183-188 is collectable. This used to be four
	' separate equality tests (183/185/186/187), which silently left out the
	' TOOLBOX (184) and the HARD HAT (188) -- two of level 2's six prizes could
	' be walked over forever and the level could never be cleared. A range test
	' cannot drift out of step with the prize table the way a list can.
	IF ch >= T_SBOX THEN
		IF ch <= T_HAT THEN GOSUB take_item
	END IF
	' Deposit a carried piece when standing at the edge of an open gap.
	IF carry = 1 THEN GOSUB try_fill
	RETURN
walk_tramp:
	' Walked onto the trampoline cap itself: bounce from the row he is
	' standing on (tramp_in2 measures the entry floor from fcy).
	fcy = my
	GOSUB tramp_in2
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

tramp_in2:
	' Landed on the trampoline. The bounce delivers one floor HIGHER than the
	' one he left, so measure from where the arc started (fcy holds the apex
	' for a jump, the floor row for a plain fall) -- except from the top
	' floor, which rides all the way down to the bottom floor.
	ery = (fcy + 16) / 8
tramp_go:
	st = S_TRAMP
	trph = 0
	trpose = 0
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
	mx = trx
	RETURN

st_tramp:
	#if TI994A
	BANK SELECT 3
	#endif
	GOSUB banked_tramp_step
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

st_climb:
	IF jbe THEN GOTO start_jump
	climby = my
	IF ju THEN
		ta = TILE(mx + 8,my + 7)
		tb = TILE(mx + 8,my + 15)
		tc = TILE(mx + 8,my + 1)
		mv = 0
		' Head-only grabs must remain climbable on the following step.
		IF tc >= T_LADD0 THEN
			IF tc <= T_LADD1 THEN mv = 1
		END IF
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
				jhz = 1
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
	IF my <> climby THEN
		IF (my AND 7) = 0 THEN
			IF snd1 = 0 THEN
				SOUND 1,240,7
				snd1 = 4
			END IF
		END IF
	END IF
	RETURN

st_jump:
	' Factory pads first lift Mack clear of the ledge's underside, then
	' carry him outward. Drifting immediately would hit the beam from below.
	IF spr2 = 1 THEN
		IF lv = 3 THEN
			' Raised pads clear the underside after three ascent steps.
			IF jix < 3 THEN GOTO jump_vertical
		END IF
	END IF
	' Horizontal drift is committed FIRST -- before the vertical move that
	' may land and RETURN -- so the landing step still contributes its pixel.
	' Including the apex hold, a normal jump spans 32 px. It advances
	' one step per sub-step (same clock as WALK), so sideways speed matches
	' walking and never slows mid-jump.
	' Drift 1 px/step = walk speed, including the apex hold.
	IF jhz = 0 THEN
		IF mx > 0 THEN mx = mx - 1
	END IF
	IF jhz = 2 THEN
		IF mx < 240 THEN mx = mx + 1
	END IF
jump_vertical:
	' dy comes from a table of 128+dy bytes (unsigned-safe).
	' Low ceilings cap height at 11 px; allow time to clear an enemy.
	' The spring arc keeps its original timing.
	IF spr2 = 0 THEN
		IF jix = 8 THEN
			IF jhang > 0 THEN
				jhang = jhang - 1
				RETURN
			END IF
		END IF
	END IF
	v = jtab(jix)
	IF v < 128 THEN
		dv = 128 - v
		IF spr2 = 1 THEN dv = dv * 5
		FOR t8 = 1 TO dv
			' Head-bump: the 12-px art's head is at my+4, so probe my+3
			' (1 px above it). The extra head room lets the arc rise higher.
			' It ends the ASCENT and hands over to the descent -- it must never
			' REWIND jix (an earlier 'jix = 8' restarted the arc near its apex,
			' so a bump could keep re-arming itself), and it fires at most once
			' per jump (bmp1) so a head still touching the beam cannot re-trigger.
			ch = TILE(mx + 8,my + 3)
			IF ch >= T_SOLID0 THEN
				IF ch <= T_BUMP1 THEN
					IF bmp1 = 0 THEN
						bmp1 = 1
						' Keep horizontal clearance time under a low ceiling.
						' jump_adv advances 7 to the apex exactly once.
						IF jix < 8 THEN jix = 7
					END IF
					GOTO jump_adv
				END IF
			END IF
			my = my - 1
			fcy = my	' rising: hold the fall origin at the apex
		NEXT t8
	ELSE
		dv = v - 128
		IF spr2 = 1 THEN dv = dv * 5
		FOR t8 = 1 TO dv
			my = my + 1
			fy = my + 16
			IF (fy AND 7) = 0 THEN
				GOSUB foot_probe
				IF sup = 1 THEN
					' A jump landing is judged by the SAME rule as any
					' other fall: drop measured from the arc's APEX (fcy).
					' Without this, jumping off a high ledge was always
					' safe while merely walking off a low one was fatal --
					' the inconsistency at the conveyor.
					fd2 = 0
					IF my > fcy THEN fd2 = my - fcy
					' A pad launch rises ~55 px, so coming back down on
					' one would read as a fatal drop. Pads bounce.
					IF ch = T_PAD THEN fd2 = 0
					IF fd2 > FATALFALL THEN
						GOSUB mack_die
					ELSE
						st = S_WALK
					END IF
					RETURN
				END IF
			END IF
			' The elevator platform sits at arbitrary pixel rows,
			' so its catch runs every pixel (no VPEEK -- cheap).
			GOSUB elev_sup
			IF esup = 1 THEN
				GOSUB land_chk
				IF st <> S_DEAD THEN st = S_RIDE
				RETURN
			END IF
			' Landing on the L2 crane beam (a sprite, so pixel-checked).
			GOSUB beam_sup
			IF bsup = 1 THEN
				my = bmy - 16
				GOSUB land_chk
				IF st <> S_DEAD THEN
					st = S_WALK
					bonbeam = 1
				END IF
				RETURN
			END IF
			' Landing on a conveyor belt -> start riding it up.
			GOSUB conv_sup
			IF csup = 1 THEN
				GOSUB land_chk
				IF st <> S_DEAD THEN st = S_WALK
				RETURN
			END IF
		NEXT t8
	END IF
jump_adv:
	' 'bounces up and down forever with no button held'.
	jix = jix + 1
	IF jix > 15 THEN
		' Arc exhausted without landing: keep falling. fcy still holds the
		' arc's APEX, so the drop is measured from the true high point.
		st = S_FALL
		fct = 0
	END IF
	RETURN

st_fall:
	IF lv = 3 THEN
		IF my >= 152 THEN
			cx = mx + 8
			IF cx >= 76 THEN
				IF cx <= 103 THEN GOTO spring_begin
			END IF
			IF cx >= 148 THEN
				IF cx <= 175 THEN GOTO spring_begin
			END IF
		END IF
	END IF
	' Only a deliberate jump carries horizontal momentum into a fall.
	' Walking off a ledge, chain or parked elevator starts a vertical drop.
	IF jhz = 0 THEN
		IF mx > 0 THEN mx = mx - 1
	END IF
	IF jhz = 2 THEN
		IF mx < 240 THEN mx = mx + 1
	END IF
	' The trampoline catches a fall -- but you have to actually REACH it.
	'   x  -- Mack's art (mx+2..mx+13) must overlap the pad, allowing 4 px of
	'         grace (trxl = trx-4). Walking off the beam edge leaves him well
	'         short, so getting to the trampoline is a JUMP, taken late enough,
	'         and jumping too early misses it and kills you. An earlier version
	'         caught him anywhere in the channel, which made the whole right
	'         side risk-free.
	'   y  -- only once he is genuinely below the bottom beam (trmy). Without
	'         it, a jump arc passing over the channel got captured mid-air and
	'         snapped to the pad with steering locked, which read as a second,
	'         uncontrollable jump bolted onto the first.
	IF tron = 1 THEN
		fy = my + 16
		IF fy > trmy THEN
			cx = mx + 13
			IF cx >= trxl THEN
				GOSUB tramp_in2
				RETURN
			END IF
		END IF
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
			GOSUB land_chk
			IF st <> S_DEAD THEN
				bonbeam = 1
				st = S_WALK
			END IF
			RETURN
		END IF
		' A conveyor belt catches a fall -> ride up.
		GOSUB conv_sup
		IF csup = 1 THEN
			GOSUB land_chk
			IF st <> S_DEAD THEN st = S_WALK
			RETURN
		END IF
	NEXT t8
	RETURN
fall_land:
	esup = 0
	GOSUB elev_sup
	' Same unsigned guard as land_chk: a catch that snaps Mack UPWARD
	' (elevator rising into him) would otherwise wrap the subtraction.
	fd2 = 0
	IF my > fcy THEN fd2 = my - fcy
	IF ch = T_PAD THEN fd2 = 0	' pads bounce, they never break your legs
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
	IF edance THEN RETURN
	' A newly boarded armed elevator centers Mack and starts its trip. On
	' arrival, left/right now walk him off the parked platform; they must not
	' send the cabin straight back the other way.
	IF emov = 1 THEN RETURN
	IF jbe THEN GOTO start_jump
	IF elarm = 1 THEN
		GOSUB elev_sup
		IF esup = 1 THEN
			mx = elx		' any supported boarding snaps fully into the cabin
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
	IF jr THEN mx = mx + 1
	IF jl THEN
		IF mx > 0 THEN mx = mx - 1
	END IF
	IF jr THEN GOTO ride_step_off
	IF jl THEN GOTO ride_step_off
	RETURN
ride_step_off:
	GOSUB elev_sup
	IF esup = 0 THEN
		' Re-arm only after Mack actually leaves the parked cabin.
		elarm = 1
		GOSUB foot_probe
		IF sup = 1 THEN
			st = S_WALK
		ELSE
			st = S_FALL
			fcy = my
			fct = 0
			jhz = 1
		END IF
	END IF
	RETURN

	'
	' ---- Probes ----
	'
mag_move:
	#if TI994A
	BANK SELECT 2
	#endif
	GOSUB banked_mag_move
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

mag_catch:
	#if TI994A
	BANK SELECT 2
	#endif
	GOSUB banked_mag_catch
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

land_chk:
	' ONE landing rule for EVERY surface. A landing reached from a jump or a
	' fall is fatal when the drop from the apex (fcy) exceeds FATALFALL --
	' solid girder, crane beam, conveyor, elevator alike. Only plain solid
	' ground used to be checked, so a long fall onto the moving girder or a
	' belt was a free save from ANY height.
	' UNSIGNED GUARD (CVBasic has no negative math): landing HIGHER than
	' the apex -- jumping UP onto a conveyor/beam from beside or below --
	' makes my < fcy, and my - fcy wraps to a huge value that sails past
	' FATALFALL. That killed every upward landing on the belt.
	IF my > fcy THEN
		fd2 = my - fcy
		IF fd2 > FATALFALL THEN GOSUB mack_die
	END IF
	RETURN

foot_probe:
	' ch = tile under Mack's feet; sup = 1 if it holds him up.
	sup = 0
	fy = my + 16
	IF fy > 191 THEN RETURN
	ch = TILE(mx + 8,fy)
	IF ch >= T_PAD THEN
		IF ch <= T_PAD_R + 1 THEN ch = T_PAD
	END IF
	IF ch >= T_SOLID0 THEN
		IF ch <= T_SOLID1 THEN sup = 1
	END IF
	' A shoe still on the crane-side ledge is supported, even when the
	' sprite midpoint hangs over its lip. This makes the right waiting spot
	' usable after leaving the rising crane; do not add invisible floor.
	IF lv = 2 THEN
		IF sup = 0 THEN
			IF fy = 136 THEN
				ch = TILE(mx + 5,fy)
				IF ch >= T_SOLID0 THEN
					IF ch <= T_SOLID1 THEN sup = 1
				END IF
			END IF
		END IF
	END IF
	RETURN

elev_sup:
	' esup = 1 if Mack's feet rest on the elevator platform (and if so,
	' snap him to its top). Board by Mack's center being within the platform
	' span. Sprite-edge overlap alone is not enough: the adjacent level-one
	' chain must remain climbable without accidentally boarding the elevator.
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
elev_draw:
	' Elevator platform. The parked/absent value is ely = 209, and writing
	' ely-1 puts **208** in the sprite's y byte -- which on the TMS9918 is the
	' SPRITE LIST TERMINATOR ($D0), not an off-screen row. On every level
	' without an elevator (2 and 3) that silently killed all 29 sprites after
	' this one: the level-2 vandal never appeared, and any sprite added later
	' was invisible for no visible reason. Hide it with a literal 209 instead.
	IF ely > 200 THEN
		SPRITE 2,209,0,0,0
		SPRITE 9,209,0,0,0
	ELSE
		SPRITE 2,ely - 1,elx,8,15
		SPRITE 9,ely - 17,elx,84,15
	END IF
	RETURN

elev_back:
	' Parked cabin AND floor live in the name table, immune to sprite overflow.
	' The moving elevator keeps its sprites; game-over redraws that frozen pair.
	IF emov = 0 THEN
		IF elpaint = 1 THEN RETURN
		#elback = (ely / 8 - 2) * 32 + elx / 8
		#elback = #elback + 6144
		elpaint = 1
	ELSE
		IF elpaint = 0 THEN RETURN
		elpaint = 0
	END IF
	#va = #elback
	FOR elcell = 0 TO 5
		ch = T_VOID
		IF elpaint = 1 THEN
			ch = 227 + elcell / 2 + (elcell AND 1) * 2
			IF elcell >= 4 THEN ch = T_ELEV + elcell - 4
		END IF
		VPOKE #va,ch
		#va = #va + 1
		IF elcell AND 1 THEN #va = #va + 30
	NEXT elcell
	RETURN

elev_reset:
	' Fixed-bank reset preserves the caller's cartridge bank.
	emov = 1
	GOSUB elev_back
	ely = elby
	emov = 0
	eld = 0
	elarm = 1
	GOSUB elev_back
	RETURN

elev_move:
	' Moves only after being boarded (emov), then parks at the far end.
	' One pixel per world step, sharing Mack's catch-up clock.
	IF st = S_DEAD THEN RETURN
	IF emov = 0 THEN RETURN
	IF (ely AND 7) = 0 THEN
		workfx = 1
		GOSUB work_sound
	END IF
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
	IF emov = 0 THEN SOUND 0,,0
	IF st = S_RIDE THEN
		my = ely - 16
		IF emov = 0 THEN
			edance = 32
			dancebody = 0
			dancecolour = 60
		END IF
	END IF
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
	IF lv = 3 THEN GOTO lift_move
	IF st = S_DEAD THEN RETURN
	IF bmon = 0 THEN RETURN
	IF bmactive = 0 THEN
		IF bonbeam = 0 THEN RETURN
		bmactive = 1
	END IF
	' Advance 1 px/world step. At 2 px/pass the beam travelled 120 px/s -- faster than
	' Mack falls -- so a beam on its way UP outran his descent and slipped
	' through the +-4 px catch window: jumping across from the conveyor's top
	' roller only worked if you happened to meet the beam coming DOWN. At 1 px
	' the window is twice as forgiving in both directions and the ride reads
	' better besides.
	' Range 48..167. The bar is TWO cell rows tall, drawn at brow and brow+1,
	' and vacated cells are blanked -- so the bottom limit has to keep brow+1
	' off the bottom-row machinery. 167 puts brow at 20 and the lower cell at
	' 21; 168 tips brow to 21 and the lower cell wipes row 22, which chewed
	' half the bin off the end of the conveyor. It still comes down level with
	' the belt's top roller (y 163), which is what the jump across needs.
	bmold = bmy
	IF bmd = 0 THEN
		bmy = bmy - 1
		IF bmy <= 48 THEN
			bmy = 48
			bmd = 1
		END IF
	ELSE
		bmy = bmy + 1
		IF bmy >= 167 THEN
			bmy = 167
			bmd = 0
		END IF
	END IF
	IF bonbeam = 1 THEN
		my = bmy - 16
		RETURN
	END IF
	' The rising surface can meet Mack during the apex hold, when st_jump
	' performs no vertical movement. Catch this swept contact now, before
	' the beam passes through him. Never catch a head-bump from underneath.
	IF st = S_JUMP THEN
		IF jix < 8 THEN RETURN
	ELSE
		IF st <> S_FALL THEN RETURN
	END IF
	fy = my + 16
	IF fy > bmold THEN RETURN
	IF fy < bmy THEN RETURN
	GOSUB beam_sup
	IF bsup = 1 THEN
		my = bmy - 16
		GOSUB land_chk
		IF st <> S_DEAD THEN
			st = S_WALK
			bonbeam = 1
		END IF
	END IF
	RETURN

beam_sup:
	IF lv = 3 THEN GOTO lift_sup
	' bsup = 1 if Mack's feet rest on the beam surface and any part of his ART
	' overlaps its 40-px span (cols 12-16 => pixels 96..135). The art is 12 px
	' wide inside the 16-px box, so it runs mx+2 .. mx+13.
	' OVERLAP, not centre: requiring his midpoint to clear x=96 left the jump
	' from the lower conveyor's top roller exactly ONE pixel short. Landing on
	' a platform's edge is what a player expects anyway.
	bsup = 0
	IF bmon = 0 THEN RETURN
	fy = my + 16
	' +-4 px window: the beam moves 2 px/frame and Mack falls up to 3, so a
	' tighter window can be skipped in one step (falling THROUGH the beam).
	IF fy >= bmy - 4 THEN
		IF fy <= bmy + 4 THEN
			cx = mx + 13		' his right edge must reach the beam
			IF cx >= 96 THEN
				cx = mx + 2	' his left edge must not be past it
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
	' At the flat belt's right roller, use the supported pre-walk foot:
	' right input and left transport cancel before any walk-off can occur.
	IF lv = 3 THEN
		IF st = S_WALK THEN
			IF jr THEN fx = walkx + 8
		END IF
	END IF
	fy = my + 16
	FOR ci = 0 TO cvn - 1
		kx0 = cvx0(ci)
		kx1 = cvx1(ci)
		IF fx >= kx0 THEN
			IF fx <= kx1 THEN
				ky0 = cvy0(ci)
				kdy = ky0 - cvy1(ci)
				GOSUB belt_surface
				IF fy >= srf - 4 THEN
					IF fy <= srf + 5 THEN
						csup = 1
						' The belt runs THROUGH its rollers and off the end --
						' it never parks him. Ride to the top and jump off, or
						' be tipped over the roller into the bins below. An
						' earlier version stopped him dead at the top, which
						' made the whole ride passive and safe.
						' Factory belt matches walking: right input cancels drift.
						cvdrag = hzphase AND 1
						IF lv = 3 THEN cvdrag = 1
						IF cvdrag THEN
						IF cvdir(ci) = 0 THEN
							IF mx < 240 THEN mx = mx + 1
						ELSE
							IF mx > 0 THEN mx = mx - 1
						END IF
						END IF
						fx = mx + 8
						IF fx > kx1 THEN fx = kx1
						IF fx < kx0 THEN fx = kx0
						GOSUB belt_surface
						my = srf - 16
						GOSUB upper_belt_edge
						RETURN
					END IF
				END IF
			END IF
		END IF
	NEXT ci
	RETURN

upper_belt_edge:
	' The upper site's right-hand belt exit always ignites Mack, even when
	' the furnace plume is retracted. Jump before the last roller to catch
	' the magnet; walking or riding over it starts the full burning fall.
	IF lv <> 2 THEN RETURN
	IF my > cvy1(0) - 16 THEN RETURN
	cx = mx + 8
	IF cx <= cvx1(0) THEN RETURN
	GOSUB mack_burn
	RETURN

belt_surface:
	#cvt = 0
	IF kdy > 0 THEN
		IF fx > kx0 + 3 THEN #cvt = (fx - kx0 - 3) / 2
		IF #cvt > kdy THEN #cvt = kdy
	END IF
	srf = ky0 - #cvt
	RETURN

lift_move:
	pnoldx = pnxcar(pnside)
	pnphase = pnphase + 1
	IF pnphase >= 224 THEN pnphase = 0
	IF (pnphase AND 31) = 0 THEN
		workfx = 1
		GOSUB work_sound
	END IF
	GOSUB lift_positions
	IF bonbeam = 1 THEN
		bmy = pnycar(pnside)
		mx = mx + pnxcar(pnside) - pnoldx
		my = bmy - 16
	END IF
	RETURN

lift_positions:
	#if TI994A
	BANK SELECT 4
	#endif
	GOSUB banked_lift_positions
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

lift_sup:
	bsup = 0
	fx = mx + 8
	FOR pns = 0 TO 3
		bmy = pnycar(pns)
		pnx = pnxcar(pns)
		GOSUB lift_height
		IF bsup = 1 THEN
			pnside = pns
			RETURN
		END IF
	NEXT pns
	RETURN

lift_height:
	IF fx < pnx THEN RETURN
	IF fx > pnx + 15 THEN RETURN
	fy = my + 16
	IF fy >= bmy - 3 THEN
		IF fy <= bmy + 3 THEN bsup = 1
	END IF
	RETURN

lift_draw:
	IF lv <> 3 THEN RETURN
	FOR pndraw = 0 TO 3
		SPRITE 10 + pndraw,pnycar(pndraw) - 1,pnxcar(pndraw),80,3
	NEXT pndraw
	RETURN

beam_draw:
	' GLITCH-FREE character beam: the bar is 16 pre-defined girder slices
	' (chars 192-207); moving it is pure NAME-TABLE placement -- no pattern or
	' color-table writes at runtime, so nothing can spill past vblank and tear.
	' The bar top sits at sub-row boff: place upper slice (192+boff) on cell
	' row brow and lower slice (200+boff) on brow+1. The middle cell uses
	' plain slices 96-111, separating the two pairs of rivets.
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
		' Vacated cells go back to EMPTY. Col 14 is the cable, and the cable
		' is what the beam HANGS FROM: it exists only ABOVE the beam, so a
		' vacated row gets cable if it is now above the bar and nothing if it
		' is below. (Restoring it unconditionally drew rope under the beam,
		' which is not how a crane works.)
		cbu = 32
		IF bprow < brow THEN cbu = T_CABLE
		#va = VADDR(bprow,12)
		FOR i = 1 TO 5
			bc9 = 32
			IF i = 3 THEN bc9 = cbu
			VPOKE #va,bc9
			#va = #va + 1
		NEXT i
		bpr2 = bprow + 1
		cbu = 32
		IF bpr2 < brow THEN cbu = T_CABLE
		#va = VADDR(bpr2,12)
		FOR i = 1 TO 5
			bc9 = 32
			IF i = 3 THEN bc9 = cbu
			VPOKE #va,bc9
			#va = #va + 1
		NEXT i
		bprow = brow
	END IF
	' Draw the two beam rows.
	#va = VADDR(brow,12)
	FOR i = 1 TO 5
		bc9 = uc
		IF i = 3 THEN bc9 = 96 + boff
		VPOKE #va,bc9
		#va = #va + 1
	NEXT i
	#va = VADDR(br3,12)
	FOR i = 1 TO 5
		bc9 = lc
		IF i = 3 THEN bc9 = 104 + boff
		VPOKE #va,bc9
		#va = #va + 1
	NEXT i
	RETURN

	'
	' ---- Level 1 objective: pieces, gaps, riveting ----
	'
deliver_zone:
	IF carry <> 1 THEN RETURN
	IF boxfall THEN RETURN
	IF my <> 120 THEN RETURN
	cx = mx + 8
	boxx = 0
	IF cx >= 32 THEN
		IF cx <= 39 THEN boxx = 40
	END IF
	IF cx >= 56 THEN
		IF cx <= 63 THEN boxx = 40
	END IF
	IF cx >= 192 THEN
		IF cx <= 199 THEN boxx = 200
	END IF
	IF cx >= 216 THEN
		IF cx <= 223 THEN boxx = 200
	END IF
	IF boxx = 0 THEN RETURN
	carry = 0
	boxfall = 1
	boxy = 128
	#award = 5
	GOSUB add_score
	GOSUB hud_score
	RETURN

deliver_box:
	boxfall = 2
	outputside = 0
	IF boxx > 128 THEN outputside = 1
	outputtick = 0
	nbox = nbox - 1
	#award = 5
	GOSUB add_score
	GOSUB hud_score
	#sndpitch = 140
	sndvol = 12
	sfxlen = 8
	GOSUB tone_start
	workfx = 3
	GOSUB work_sound
	RETURN

take_item:
	' Torso cell hit a pickup char. Bricks need free hands; wrench and
	' spray can are instant bonus points.
	r2 = (my + 8) / 8
	c2 = (mx + 8) / 8
	IF ch = T_LBOXR THEN c2 = c2 - 1
	FOR i = 0 TO MAXITEM - 1
		IF itst(i) = 0 THEN
			IF itr(i) = r2 THEN
				IF itc(i) = c2 THEN
					IF itk(i) = 0 THEN
						IF carry <> 0 THEN RETURN
						carry = 1
						IF lv = 1 THEN
							#award = 2
							GOSUB add_score
						END IF
						IF lv = 3 THEN
							#award = 5
							GOSUB add_score
						END IF
						GOSUB hud_score
						cidx = i
						#sndpitch = 400
						sndvol = 10
						sfxlen = 6
						GOSUB tone_start
					ELSEIF itk(i) = 3 THEN
						' Lunchbox: the level-2 objective.
						#award = 5
						GOSUB add_score
						GOSUB hud_score
						#sndpitch = 180
						sndvol = 10
						sfxlen = 8
						GOSUB tone_start
						nlbr = nlbr - 1
						' All six pails arm the already moving magnet.
						' Catching it starts the final ride to the crane top.
						IF mgon = 1 THEN
							IF nlbr = 0 THEN mgarm = 1
						END IF
					ELSE
						' Bonus tool (wrench/spray can): +200.
						#award = 40
						GOSUB add_score
						GOSUB hud_score
						#sndpitch = 180
						sndvol = 10
						sfxlen = 8
						GOSUB tone_start
					END IF
					itst(i) = 1
					#va = VADDR(r2,c2)
					ch = T_VOID
					VPOKE #va,ch
					IF itk(i) = 3 THEN
						#va = #va + 1
						VPOKE #va,ch
						#va = #va - 32
						VPOKE #va,ch
						#va = #va - 1
						VPOKE #va,ch
					END IF
					RETURN
				END IF
			END IF
		END IF
	NEXT i
	RETURN

try_fill:
	IF lv <> 1 THEN RETURN
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
					gapitem(i) = cidx
					carry = 0
					#va = VADDR(r2,gapc(i))
					ch = T_FILLED
					VPOKE #va,ch
					#award = 5
					GOSUB add_score
					GOSUB hud_score
					#sndpitch = 200
					sndvol = 12
					sfxlen = 8
					GOSUB tone_start
					workfx = 0
					GOSUB work_sound
					RETURN
				END IF
			END IF
		END IF
	NEXT i
	RETURN

rivet_gap:
	' A few drill-steps crossing a FILLED plug rivet it down.
	r2 = (my + 16) / 8
	c2 = (mx + 8) / 8
	FOR i = 0 TO MAXGAP - 1
		IF gapst(i) = 1 THEN
			IF gapr(i) = r2 THEN
				IF gapc(i) = c2 THEN
					gapst(i) = 2
					#va = VADDR(r2,c2)
					ch = T_RIVET
					IF girder_mark(gapc(i)) THEN ch = T_GIRDR
					VPOKE #va,ch
					#award = 7
					GOSUB add_score
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
	' All movement and collisions run on world_step's clock.
	' Hitboxes use branch-first unsigned deltas and nested IFs.
	'
actors_step:
	' Per-#hd-sub-step MOVEMENT only (called once per sub-step, like
	' mack_step) so the characters advance at exactly Mack's speed. The
	' drill and the L1 vandal walk their serpentine routes here; collision
	' and the bonus clock live in actors_move (once per world step).
	IF jhtk = 0 THEN GOSUB route_drill
	IF von = 1 THEN
		IF vroute = 1 THEN GOSUB route_vand
	END IF
	RETURN

actors_move:
	#if TI994A
	BANK SELECT 2
	#endif
	GOSUB banked_actors_move
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

bolt_move:
	' Rivet: thrown left from the fixed upper-right launcher, drifting LEFT
	' (never right, never re-aims), bounces ONCE on each floor it meets,
	' then passes THROUGH that floor to keep descending. Once per world step.
	' Level 1 only -- see bolon in init_level.
	IF bolon = 0 THEN RETURN
	IF bon = 0 THEN
		btm = btm - 1
		IF btm = 0 THEN
			bon = 1
			bx = 216
			bkind = RANDOM(4)
			bvel = 1 + (bkind AND 1)
			by = 27
			bph = 0
			bnx = 0
		END IF
	ELSE
		IF bx > 4 THEN
			bx = bx - bvel
		ELSE
			bon = 0
			btm = 200
		END IF
		IF bph = 0 THEN
			by = by + 2
			fy = by + 9
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
							GOSUB machine_clack
							bct = 4 + bkind * 2
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
		ey = by - 4
		hbw = 4
		hbh = 7
		GOSUB hazard_hit
	END IF
	RETURN

	'
	' ---- Shared route interpreter (drill + monster) ----
	' The vandal roams the building on a FIXED PREDEFINED serpentine (it
	' does not home on Mack). The drill uses its own waypoint circuit. Actor state
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

site_route:
	' Walk each tier out and back, then use its actual edge chain.
	' rp 1 descends, 2 ascends; rf is horizontal facing.
	IF (atg AND 1) = 0 THEN RETURN
	rlo = 168
	rhi = 232
	rtop = 88
	rbot = 120
	IF rx < 128 THEN
		rlo = 16
		rhi = 72
	END IF
	IF lv = 2 THEN
		rlo = 112
		IF ry = 120 THEN rlo = 144
		rhi = 204
		rtop = 120
		rbot = 168
	END IF
	IF rp = 1 THEN
		ry = ry + 1
		IF ry = rbot THEN
			rp = 0
			rf = 0
		END IF
		RETURN
	END IF
	IF rp = 2 THEN
		ry = ry - 1
		IF ry = rtop THEN
			rp = 0
			rf = 0
		END IF
		RETURN
	END IF
	IF rf = 0 THEN
		rx = rx - 1
		IF rx <= rlo THEN rf = 1
	ELSE
		rx = rx + 1
		IF rx >= rhi THEN
			rx = rhi
			rp = 1
			IF ry = rbot THEN rp = 2
		END IF
	END IF
	RETURN

route_drill:
	tcx = drillx(jhway)
	tgy = drilly(jhway)
	IF jhx < tcx THEN jhx = jhx + 1
	IF jhx > tcx THEN jhx = jhx - 1
	IF jhy < tgy THEN jhy = jhy + 1
	IF jhy > tgy THEN jhy = jhy - 1
	IF jhx = tcx THEN
		IF jhy = tgy THEN
			jhway = jhway + 1
			IF jhway >= 18 THEN jhway = 0
		END IF
	END IF
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
	jhlock = 1
	jhx = jhx0
	jhy = jhy0
	jhway = 0
	#sndpitch = 200
	sndvol = 8
	sfxlen = 6
	GOSUB tone_start
	RETURN

hazard_hit:
	GOSUB mack_hit
	IF hit = 1 THEN GOSUB mack_die
	RETURN

mack_hit:
	' hit = 1 if the actor at (ex,ey) overlaps Mack. The box is set by
	' caller supplies center-distance limits, NOT sprite-cell dimensions.
	' ex/ey must first align the hazard's visible center to Mack's torso.
	' Lethal bounds are checked against the editable art by checkphysics.py.
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

add_score:
	' Scores are units of five; saturate at 327675 points without wrapping.
	#score_room = 65535 - #score
	IF #award > #score_room THEN
		#score = 65535
	ELSE
		#score = #score + #award
	END IF
	RETURN

score_print:
	#if TI994A
	BANK SELECT 3
	#endif
	GOSUB banked_hud_score
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

hud_score:
	#scvalue = #score
	#scpos = 0
	GOSUB score_print
	' One-time extra life at 7,000.
	IF xlife = 0 THEN
		IF #score >= 1400 THEN
			xlife = 1
			lives = lives + 1
			GOSUB hud_lives
			#sndpitch = 140
			sndvol = 12
			sfxlen = 12
			GOSUB tone_start
		END IF
	END IF
	RETURN

	'
	' ---- Death and respawn ----
	'
mack_die:
	IF st = S_DEAD THEN RETURN
	edance = 0
	burnfall = 0
	dclean = 1
	st = S_DEAD
	bonbeam = 0
	dtm = 40
	#sndpitch = 600
	sndvol = 12
	sfxlen = 14
	GOSUB tone_start
	RETURN

mack_burn:
	IF st = S_DEAD THEN RETURN
	GOSUB mack_die
	burnfall = 1
	dtm = 12
	RETURN

death_cleanup:
	#if TI994A
	BANK SELECT 2
	#endif
	GOSUB banked_death_cleanup
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

dead_tick:
	' Keep the site and inventory intact throughout the death animation.
	' Resolve them only once the blink or burning-ground pause has finished.
	IF burnfall THEN
		' Ground starts at row 23 (y=184); Mack's sixteen-pixel body stops
		' with his feet on it. Keep BOTH burning sprite layers visible while
		' falling and during the short ground pause; skip the usual death blink.
		IF my < 168 THEN
			my = my + #fd * 3
			IF my > 168 THEN my = 168
		ELSE
			IF dtm > #fd THEN
				dtm = dtm - #fd
			ELSE
				dtm = 0
			END IF
		END IF
		burnink = 8
		IF FRAME AND 4 THEN burnink = 9
		SPRITE 0,my - 1,mx,0,burnink
		IF dtm > 0 THEN RETURN
		burnfall = 0
		GOTO dead_resolve
	END IF
	IF dtm > #fd THEN
		dtm = dtm - #fd
	ELSE
		dtm = 0
	END IF
	IF (dtm AND 4) = 0 THEN
		SPRITE 0,209,0,0,15
	ELSE
		SPRITE 0,my - 1,mx,0,6
	END IF
dead_resolve:
	IF dtm = 0 THEN
		IF dclean = 1 THEN
			GOSUB death_cleanup
			dclean = 0
			' Spring art may have been compressed at the fatal contact.
			GOSUB machinery_draw
		END IF
		IF lives = 0 THEN
			gameov = 1
			RETURN
		END IF
		lives = lives - 1
		GOSUB hud_lives
		' The level resets around him: both roamers go back to their opening
		' mark (a vandal parked on the spawn point killed the fresh life
		' instantly), and whatever Mack carried returns to where it was.
		vx = vx0
		vy = vy0
		vb = vb0
		vp = 0
		vdr = 2
		vsv = 2
		vf = 1
		vd = 1
		opath = 0
		ob = 2
		odr = 0
		osv = 2
		ox = ox0
		oy = oy0
		od = 1
		IF lv = 1 THEN
			FOR resetgap = 0 TO ngap - 1
				IF gapst(resetgap) = 1 THEN
					gapst(resetgap) = 0
					#va = VADDR(gapr(resetgap),gapc(resetgap))
					ch = T_VOID
					VPOKE #va,ch
					resetitem = gapitem(resetgap)
					itst(resetitem) = 0
					#va = VADDR(itr(resetitem),itc(resetitem))
					ch = T_BRICK
					VPOKE #va,ch
				END IF
			NEXT resetgap
		END IF
		' Fresh life: the bonus clock refills to 5000 (authentic).
		#bonus = 5000
		PRINT AT CPOS(0,HUD_BONUS_COL),<.4>#bonus
		mx = msc * 8 - 4
		my = msr * 8 - 16
		st = S_WALK
		' Clear every ride/fall flag: a stale one (still "on the beam", or a
		' fall origin from the previous life) makes the fresh life die
		' instantly "for no reason".
		bonbeam = 0
		obonb = 0
		csup = 0
		fcy = my
		fct = 0
		burnfall = 0
	END IF
	RETURN

	'
	' ---- Level init: paint the level and load its object tables ----
	'
	'
	' ---- HUD ----
	'
spring_begin:
	st = 7
	springhit = 0
	bonbeam = 0
	springtick = 0
	springphase = 0
	trtick = 0
	trpose = 0
	springdir = 1
	IF mx >= 128 THEN springdir = 0
	springpad = 1 - springdir
	trby = 176
	mx = 80
	IF springdir = 0 THEN mx = 152
	IF my > 160 THEN my = 160
	RETURN

spring_transfer:
	#if TI994A
	BANK SELECT 3
	#endif
	GOSUB banked_spring_transfer
	#if TI994A
	BANK SELECT 1
	#endif
	IF springhit THEN GOTO mack_die
	RETURN

furnace_step:
	#if TI994A
	BANK SELECT 2
	#endif
	GOSUB banked_furnace_step
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

site_step:
	hzphase = hzphase + 1
	IF hzphase >= 128 THEN hzphase = 0
	IF carry = 2 THEN
		IF (hzphase AND 7) = 0 THEN GOSUB machine_clack
	END IF
	IF lv = 1 THEN GOTO bell_step
	IF lv = 3 THEN GOTO factory_step
	GOSUB furnace_step
	' The vat below the lower belt is lethal.
	cx = mx + 8
	IF my >= 160 THEN
		IF cx >= 80 THEN
			IF cx <= 95 THEN GOSUB mack_die
		END IF
	END IF
	' Paired jaws slide inward/outward across the lower-left ledge.
	#slagclock = #slagclock + 1
	IF #slagclock >= 317 THEN #slagclock = 0
	clawclock = clawclock + 1
	IF (clawclock AND 15) = 15 THEN clawclock = clawclock + 1
	IF clawclock >= 96 THEN clawclock = 0
	IF clawclock = 48 THEN GOSUB machine_clack
	clawstep = clawclock / 3
	IF clawstep > 16 THEN clawstep = 32 - clawstep
	ey = 123
	' Body contact is lethal; a one-pixel shoe/edge graze during a jump is not.
	hbw = 4
	hbh = 6
	clawshift = clawstep
	ex = 26 + clawshift
	GOSUB hazard_hit
	ex = 62 - clawshift
	GOSUB hazard_hit
	' Quicker downstroke; retain the impact beat and 1 px/step return.
	' Delay release at the top rather than lengthening the bottom dwell.
	pressy = 105
	IF hzphase < 32 THEN
		IF hzphase >= 21 THEN
			pressstep = hzphase - 20
			presspart = pressstep / 2
			pressy = 105 + pressstep
			pressy = pressy + pressstep
			pressy = pressy + presspart
		END IF
		IF pressy > 124 THEN pressy = 124
	END IF
	IF hzphase >= 32 THEN
		IF hzphase < 64 THEN
			pressy = 160 - hzphase
			IF pressy > 124 THEN pressy = 124
		END IF
	END IF
	' Park fully visible below the mounting beam; never retract into it.
	IF pressy < 105 THEN pressy = 105
	IF hzphase = 28 THEN GOSUB machine_clack
	ex = 184
	ey = pressy
	hbw = 8
	hbh = 8
	' The head stays exposed; its own hitbox excludes the harmless shaft.
	GOSUB hazard_hit
	' Slag emerges from the visible nozzle, drops onto the upper belt
	' surface, rides to the roller, then makes a small arc into the vat.
	slagphase = #slagclock / 2
	IF #slagclock = 120 THEN
		workfx = 2
		GOSUB work_sound
	END IF
	IF slagphase >= 60 THEN RETURN
	blobx = 44
	bloby = 149 + slagphase
	IF slagphase >= 16 THEN
		blobx = 28 + slagphase
		bloby = 165 - (slagphase - 16) / 2
	END IF
	IF slagphase >= 44 THEN
		' The receiver mouth is x=83..90: center the falling blob in it.
		IF blobx > 80 THEN blobx = 80
		bloby = 153 - (slagphase - 44)
		IF slagphase >= 50 THEN bloby = 147 + (slagphase - 50) * 2
	END IF
	ex = blobx
	ey = bloby - 4
	hbw = 5
	hbh = 7
	GOSUB hazard_hit
	RETURN

factory_step:
	IF boxfall = 1 THEN
		boxy = boxy + 1
		IF boxy >= 168 THEN GOSUB deliver_box
	ELSE
		GOSUB factory_output
	END IF
	' A descending pounder guards the conveyor. Its box stays stationary
	' on the moving belt in the reference; only Mack is carried leftward.
	' Down 1 px/step, up 1 px per two steps; keep the impact beat at phase 44.
	pressy = 40
	IF hzphase < 48 THEN
		pressy = 41
		IF hzphase >= 26 THEN
			pressstep = hzphase - 26
			presspart = pressstep / 6
			pressy = 41 + pressstep
			pressy = pressy + presspart
		END IF
		IF pressy > 62 THEN pressy = 62
	END IF
	IF hzphase >= 48 THEN
		IF hzphase < 96 THEN
			pressy = 88 - hzphase / 2
			IF pressy > 62 THEN pressy = 62
		END IF
	END IF
	IF pressy < 41 THEN pressy = 41
	IF hzphase = 44 THEN GOSUB machine_clack
	ex = 56
	ey = pressy
	hbw = 8
	hbh = 8
	GOSUB hazard_hit
	IF st = 7 THEN RETURN
	' Stay aboard too low over the central toilet and Mack falls into it.
	cx = mx + 8
	IF my >= 140 THEN
		IF cx >= 112 THEN
			IF cx <= 143 THEN GOSUB mack_die
		END IF
	END IF
	IF st = S_JUMP THEN
		IF spr2 = 1 THEN RETURN
	END IF
	IF my >= 152 THEN
		IF cx >= 76 THEN
			IF cx <= 103 THEN
				GOSUB spring_begin
				RETURN
			END IF
		END IF
		IF cx >= 148 THEN
			IF cx <= 175 THEN
				GOSUB spring_begin
				RETURN
			END IF
		END IF
		IF my >= 160 THEN GOSUB mack_die
	END IF
	RETURN

bell_step:
	IF st <> S_JUMP THEN
		bellheld = 0
		RETURN
	END IF
	IF bellheld = 1 THEN RETURN
	IF my > 16 THEN RETURN
	cx = mx + 8
	IF cx < 40 THEN RETURN
	IF cx > 64 THEN RETURN
	bellheld = 1
	eld = 0
	IF ely <= elty THEN eld = 1
	emov = 1
	#award = 2
	GOSUB add_score
	GOSUB hud_score
	#sndpitch = 120
	sfxlen = 10
	sndvol = 10
	GOSUB tone_start
	RETURN

site_draw:
	IF cvn > 0 THEN
		cvaf = (hzphase / 2) AND 7
		IF lv = 3 THEN cvaf = (8 - (hzphase AND 7)) AND 7
		' Consecutive 48-byte phases; no loop-rate-dependent animation clock.
		IF lv = 3 THEN
			' The flat belt and both rollers occupy only the middle screen third.
			DEFINE VRAM 3320,24,VARPTR belt_anim0(cvaf * 48 + 24)
		ELSE
			DEFINE CHAR 156,4,VARPTR belt_anim0(cvaf * 48)
		END IF
	END IF
	IF lv = 1 THEN
		GOSUB elev_back
		GOSUB machinery_draw
		SPRITE 17,23,240,16,13
		RETURN
	END IF
	SPRITE 14,209,0,0,0
	GOSUB machinery_draw
	GOSUB fixture_draw
	IF lv = 2 THEN
		IF slagphase < 60 THEN
			blobpat = 100
			IF slagphase AND 4 THEN blobpat = 104
			SPRITE 15,bloby - 1,blobx,blobpat,15
		ELSE
			SPRITE 15,209,0,0,0
		END IF
		SPRITE 16,mgr * 8 - 1,mgx,92,15
	ELSE
		IF boxfall = 1 THEN
			SPRITE 15,boxy - 1,boxx,88,15
		ELSEIF boxfall = 3 THEN
			SPRITE 15,boxy - 1,boxx,20,15
		ELSE
			SPRITE 15,209,0,0,0
		END IF
	END IF
	RETURN

machinery_draw:
	#if TI994A
	BANK SELECT 4
	#endif
	GOSUB animated_machines
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

enemy_draw:
	#if TI994A
	BANK SELECT 2
	#endif
	GOSUB banked_enemy_draw
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

enemy_setup:
	#if TI994A
	BANK SELECT 2
	#endif
	GOSUB banked_enemy_setup
	#if TI994A
	BANK SELECT 1
	#endif
	RETURN

quiet_screen:
	edance = 0
	FOR qslot = 0 TO 31
		SPRITE qslot,209,0,0,0
	NEXT qslot
	' Flush every hardware slot, including the carried block's low-priority
	' outline in slot 31, before end screens or banked title art.
	WAIT
	SPRITE 0,209,0,0,0
	GOSUB quiet_audio
	steptick = 0
	RETURN

quiet_audio:
	SOUND 0,,0
	SOUND 1,,0
	SOUND 2,,0
	SOUND 3,,0
	snd0 = 0
	snd1 = 0
	snd2 = 0
	snd3 = 0
	RETURN

hud_all:
	#if TI994A
	BANK SELECT 2
	GOSUB banked_hud_all
	BANK SELECT 1
	#scvalue = #score
	#scpos = 0
	GOSUB score_print
	#else
	PRINT AT CPOS(0,15),"BONUS "
	PRINT AT CPOS(0,21),<.4>#bonus
	#scvalue = #score
	#scpos = 0
	GOSUB score_print
	PRINT AT CPOS(0,25),"       "
	IF levelno < 10 THEN PRINT AT CPOS(0,25),"LEVEL ",levelno
	IF levelno >= 10 THEN
		IF levelno < 100 THEN PRINT AT CPOS(0,26),"LVL ",levelno
	END IF
	IF levelno >= 100 THEN PRINT AT CPOS(0,26),"LV ",levelno
	GOSUB hud_lives
	#endif
	RETURN

hud_lives:
	#if TI994A
	BANK SELECT 2
	#endif
	GOSUB banked_hud_lives
	#if TI994A
	BANK SELECT 1
	#endif
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
	#if TI994A
	BANK 1
	#endif

init_level:
	GOSUB quiet_screen
	CLS
	' BONUS starts at 5000 every level/life (authentic, ASchultz FAQ);
	' reaching zero kills Mack (see the bonus tick in actors_move).
	#bonus = 5000
	lvdone = 0
	nlbr = 0
	' No elevator/trampoline unless this level's data defines them.
	ely = 209
	elpaint = 0
	emov = 0
	elx = 0
	elarm = 1		' elevator armed for its first boarding
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
	carry = 0
	von = 0
	oon = 0
	pnphase = 0
	pnside = 0
	GOSUB lift_positions
	bmon = 0		' crane beam off unless this level's data arms it
	bmactive = 0	' first boarding starts the crane
	bonbeam = 0
	bprow = 99		' force beam_draw to place the beam on its first pass
	bmyd = 255		' last-drawn beam y (!= any real bmy -> draw on 1st pass)
	mgon = 0		' electromagnet present on this level?
	mgarm = 0		' catches Mack once all six pails are claimed
	mgtk = 0
	mgd = 1			' magnet travel direction
	cvn = 0			' number of conveyor belts this level
	cvaf = 0		' belt animation phase (0-7)
	nbox = 0		' level-3 steel boxes still to deliver
	vroute = 0
	jhtk = 1
	jhway = 0
	jhlock = 0
	boxfall = 0
	burnfall = 0
	hzphase = 0
	#slagclock = 0
	slagphase = 0
	GOSUB reset_claws
	bellheld = 0
	bon = 0
	btm = 240
	btk = 120
	' Thrown rivets belong to the girder-framing screen only. Levels 2 and 3
	' have their own hazards and nobody up top to throw them.
	bolon = 0
	IF lv = 1 THEN bolon = 1
	padok = 1		' level-3 trampoline pads start armed
	springfatal = 0
	emov = 0
	trx = 240
	trxl = 236	' trampoline pad left edge, less 4 px of grace
	trmy = 176	' committed-to-the-channel depth
	trby = 184
	trpose = 0
	trlast = 255
	trrightlast = 255
	tron = 0		' no trampoline unless this level's data defines one
	GOSUB girder_chars
	IF lv = 3 THEN
		RESTORE level3_data
	ELSE
		IF lv = 2 THEN
			RESTORE level2_data
		ELSE
			RESTORE level1_data
		END IF
	END IF
lv_parse:
	READ BYTE op
	IF op = 0 THEN
		GOSUB enemy_setup
		#hacc = 0
		#lf = FRAME
		jbold = cont1.button
		jbhc = 0
		esup = 0
		' Give the map writes a frame to settle before painting score and hats.
		WAIT
		GOSUB hud_all
		RETURN
	END IF
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
	IF t = 6 THEN ch = 189		' cement mixer, left half (decor)
	IF t = 7 THEN ch = 190		' cement mixer, right half (decor)
	IF t = 8 THEN ch = T_INM	' level-3 IN hopper (delivery zone)
	IF t = 9 THEN ch = T_MIXBAS	' cement-mixer stand
	IF t = 10 THEN ch = T_DRUM	' oil drum
		IF t < 2 THEN
			GOSUB paint_girder
			GOTO lv_parse
		END IF
		IF t = 3 THEN
			GOSUB paint_girder
			GOTO lv_parse
		END IF
		#va = VADDR(r,c)
		FOR i = 1 TO n
			VPOKE #va,ch
			#va = #va + 1
		NEXT i
		GOTO lv_parse
	END IF
	IF op = 10 THEN
		' Raw VERTICAL character run: col, row, count, CHAR CODE. The mirror
		' of op 8, for shafts and rails that are not the standard chain.
		READ BYTE c
		READ BYTE r
		READ BYTE n
		READ BYTE ch
		#va = VADDR(r,c)
		FOR i = 1 TO n
			VPOKE #va,ch
			#va = #va + 32
		NEXT i
		GOTO lv_parse
	END IF
	IF op = 9 THEN
		' FLAT conveyor: row, col, length, direction (0 = right, 1 = LEFT).
		' Level 3's top-left machine is horizontal and runs INTO the grinder,
		' which the diagonal op-6 machine cannot express.
		READ BYTE r
		READ BYTE c
		READ BYTE n
		READ BYTE t
		#va = VADDR(r,c)
		ch = 159		' left roller
		VPOKE #va,ch
		#va = #va + 1
		ch = T_CONVH
		FOR i = 2 TO n - 1
			VPOKE #va,ch
			#va = #va + 1
		NEXT i
		ch = 159		' right roller
		VPOKE #va,ch
		' Flat surface line: cvy0 = cvy1, so conv_sup's slope term is zero.
		cvx0(cvn) = c * 8
		cvy0(cvn) = r * 8 + 2
		tc = c + n
		tc = tc - 1
		cvx1(cvn) = tc * 8 + 7
		cvy1(cvn) = r * 8 + 2
		cvdir(cvn) = t
		cvn = cvn + 1
		GOTO lv_parse
	END IF
	IF op = 8 THEN
		' Raw character run: row, col, count, CHAR CODE. For decor that needs
		' no collision class of its own -- the code IS the payload, so props
		' can be placed without adding a type number for each one.
		READ BYTE r
		READ BYTE c
		READ BYTE n
		READ BYTE ch
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
		' Conveyor MACHINE at TRUE 2:1: bottom roller drum (r,c), belt rising h
		' rows over exactly 2h cols to a top drum at (r-h, c+2h) -- so the drums
		' are 2h cols / h rows apart = 1 up per 2 right, matching the reference.
		' Each belt cell is placed on the EXACT 2:1 line (band-centre pixel yb),
		' picking belt-hi (band high) or belt-lo (band low) by its sub-cell
		' offset, so the belt lines up with both drums (no drift, no gaps). A
		' yellow support post drops from the top drum to the platform.
		READ BYTE r
		READ BYTE c
		READ BYTE h
		#va = VADDR(r,c)
		ch = 159			' bottom roller drum
		VPOKE #va,ch
		ne = h + h
		ne = ne - 1
		FOR i = 1 TO ne
			col = c + i
			yb = r * 8
			yb = yb + 4
			ic = i * 4
			yb = yb - ic		' band-centre pixel on the 2:1 line
			cr = yb / 8
			su = yb AND 7
			IF su = 4 THEN
				' Band sits wholly inside this cell.
				#va = VADDR(cr,col)
				VPOKE #va,156
			ELSE
				' Band straddles the boundary above this cell: draw BOTH
				' halves so nothing is clipped (this was the gap).
				cr2 = cr - 1
				#va = VADDR(cr2,col)
				VPOKE #va,157		' upper half, along that cell's bottom
				#va = VADDR(cr,col)
				VPOKE #va,158		' lower half, along this cell's top
			END IF
		NEXT i
		tr = r - h
		tc = c + ne
		tc = tc + 1			' top drum col = c + 2h
		#va = VADDR(tr,tc)
		ch = 159			' top roller drum
		VPOKE #va,ch
		' Yellow support post down to the platform the bottom drum stands on.
		FOR pr = tr + 1 TO r
			#va = VADDR(pr,tc)
			ch = 160
			VPOKE #va,ch
		NEXT pr
		' Record the belt as a pixel SURFACE line for conv_sup (drum to drum).
		cvx0(cvn) = c * 8
		cvy0(cvn) = r * 8 + 2
		cvx1(cvn) = tc * 8 + 7
		cvy1(cvn) = tr * 8 + 2
		cvdir(cvn) = 0		' the diagonal machines carry up-and-RIGHT
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

paint_girder:
	girder_base = ch
	#va = VADDR(r,c)
	FOR i = 1 TO n
		ch = girder_base
		IF girder_mark(c) THEN ch = T_GIRDR
		VPOKE #va,ch
		#va = #va + 1
		c = c + 1
	NEXT i
	RETURN

ob_beam:
	' Crane beam (level 2): a 40-px platform (cols 12-16), centred on the
	' cable at col 14 exactly as the reference draws it
	' that rides SMOOTHLY up and down the shaft (1 px/frame). bmy = its
	' surface pixel-y; Mack jumps on/off across the 1-cell side gaps.
	READ BYTE r
	bmy = r * 8		' surface pixel-y (feet rest here)
	bprow = r		' the cable is pre-drawn down to here; track from it
	bmd = 0			' 0 = rising, 1 = falling
	bmon = 1
	GOTO lv_parse

ob_magnet:
	' Electromagnet head at the top of the crane (level 2). Two chars wide;
	' its cell is remembered (mgr/mgc) for the endgame lift.
	READ BYTE r
	READ BYTE c
	mgr = r
	mgon = 1
	mgx = c * 8
	GOTO lv_parse

ob_pail:
	' Level-2 PRIZE: a 16x12-pixel pickup that sits ON TOP of a beam, never IN it.
	' Drawing it into the beam row punched a hole in the girder *and* put it
	' one row below take_item's torso probe, so it could never be collected.
	' Every beam carries a lunch pail; the legacy kind byte remains in the stream.
	READ BYTE r
	READ BYTE c
	READ BYTE k
	itr(nitem) = r
	itc(nitem) = c
	itst(nitem) = 0
	itk(nitem) = 3
	nitem = nitem + 1
	nlbr = nlbr + 1
	ch = T_LBOXL			' every objective is a lunch pail
	#va = VADDR(r,c)
	VPOKE #va,ch
	#va = #va + 1
	ch = T_LBOXL + 1
	VPOKE #va,ch
	#va = #va - 33
	ch = 118
	VPOKE #va,ch
	#va = #va + 1
	ch = 119
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
	nbox = nbox + 1	' level 3 counts these as steel boxes to deliver
	itr(nitem) = r
	itc(nitem) = c
	itst(nitem) = 0
	itk(nitem) = 0
	nitem = nitem + 1
	#va = VADDR(r,c)
	' Level 3's boxes are steel crates, not level 1's brick stacks.
	ch = T_BRICK
	IF lv = 3 THEN ch = T_SBOX
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
	' Remember the drill's original start so death returns it here.
	jhy0 = jhy
	jhx0 = jhx
	jhtk = 0
	GOTO lv_parse

ob_elev:
	' Elevator: a 16x4 platform (characters while parked) shuttling between
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
	' Catch line: the trampoline pad's OWN left edge, less 4 px of grace --
	' deliberately not the whole channel, so the jump can be missed.
	trxl = trx - 4
	trmy = trby - 8
	tron = 1
	#va = VADDR(r,c)
	ch = T_SPRTOP
	VPOKE #va,ch
	#va = #va + 1
	ch = T_SPRBSE
	VPOKE #va,ch
	GOTO lv_parse

ob_vand:
	READ BYTE r
	READ BYTE c
	READ BYTE n
	' L2 patrol vars (used only when vroute = 0).
	vy = r * 8 - 16
	vx = c * 8
	' Opening mark, so a death can put the vandal back where he began.
	vy0 = vy
	vx0 = vx
	vd = 1
	von = 1
	' L1 serpentine route vars: beam from row, start walking up.
	vb = (25 - r) / 4
	vp = 0
	vdr = 2
	vsv = 2
	vf = 1
	vb0 = vb
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
	ox0 = ox
	oy0 = oy
	opath = 0
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

level1_data:
	DATA BYTE 8, 1,6,1,224
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
	' Each footing is one continuous two-row drawing, not two repeated feet.
	DATA BYTE 8, 22,6,1,120
	DATA BYTE 8, 23,6,1,121
	DATA BYTE 8, 22,14,1,120
	DATA BYTE 8, 23,14,1,121
	DATA BYTE 8, 22,23,1,120
	DATA BYTE 8, 23,23,1,121
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
	' drill and first-tour vandal use fixed routes. Repeat tours add a second
	' independently chosen roamer in enemy_setup.
	DATA BYTE 5,13, 21,25		' Mack spawn: two cells right of middle pedestal
	DATA BYTE 5,7, 23,29		' trampoline: bottom (row 23), cols 29-30
	DATA BYTE 5,1, 21,11		' hole: 1st floor (beam 1)
	DATA BYTE 5,1, 9,18		' hole: beam 4
	DATA BYTE 5,1, 13,11		' hole: beam 3
	DATA BYTE 5,1, 17,11		' hole: beam 2
	DATA BYTE 5,2, 8,9		' brick: beam 4 (torso row 8)
	DATA BYTE 5,2, 12,22		' brick: beam 3
	DATA BYTE 5,2, 16,25		' brick: beam 2
	DATA BYTE 5,2, 20,5		' brick: 1st floor (torso row 20)
	DATA BYTE 5,4,1, 4,21		' bonus wrench: top beam (torso row 4)
	DATA BYTE 5,4,2, 20,16		' bonus spray can: two cells right of middle pedestal
	' Fixed left-facing rivet launcher at the upper-right beam.
	DATA BYTE 8, 3,28,1,232
	DATA BYTE 8, 3,29,1,233
	DATA BYTE 8, 4,28,1,234
	DATA BYTE 8, 4,29,1,235
	DATA BYTE 5,3, 21,4,25		' drill starts bottom-left (beam 1)
	DATA BYTE 5,6, 1,9,21		' elevator: cols 1-2, 4th beam..1st beam
	DATA BYTE 5,11, 21,3,26		' vandal starts on the bottom beam
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
	DATA BYTE 8, 14,23,1,243
	DATA BYTE 8, 14,24,1,244
	DATA BYTE 8, 15,23,1,245
	DATA BYTE 8, 15,24,1,246
	DATA BYTE 8, 16,23,1,247
	DATA BYTE 8, 16,24,1,248
	' Keep sixteen clear pixels on the right for the crane-side waiting spot.
	DATA BYTE 8, 16,4,1,238
	DATA BYTE 8, 16,5,1,239
	DATA BYTE 8, 16,6,1,240
	DATA BYTE 8, 16,7,1,241
	DATA BYTE 8, 16,8,1,242
	' Transcribed cell-for-cell from assets/HHM-CV-Level2.png (32x24 grid,
	' dominant colour per cell). Reference coordinates, verified:
	'   tier beams       rows 9/13/17, cols 2-10 (left) and 18-26 (right)
	'   top platform     row 5, cols 11-13 and 15-17 (split by the cable)
	'   crane cable      col 14, rows 3-19; the beam rides it, cols 12-16
	'   conveyors        drums (8,22)->(6,26) and (22,5)->(20,9), both 2:1
	'   chain            col 26, rows 18-21
	'   ground           row 23, cols 2-29
	DATA BYTE 7, 14,3,17		' crane cable, col 14 rows 3-19: down to the beam's
				' opening row and NO FURTHER -- the beam hangs
				' from it, so there is no rope below the bar.
				' beam_draw pays it out and reels it in; a sprite
				' carries the last few pixels to the bar itself.
	DATA BYTE 1, 5,11,3,1		' top crane platform, LEFT half (cols 11-13)
	DATA BYTE 1, 5,15,3,1		' top crane platform, RIGHT half (cols 15-17)
	DATA BYTE 1, 9,2,9,1		' upper-left tier  (cols 2-10)
	DATA BYTE 1, 9,18,9,1		' upper-right tier (cols 18-26)
	DATA BYTE 1, 13,2,9,1		' mid-left tier    (cols 2-10)
	DATA BYTE 1, 13,18,9,1		' mid-right tier   (cols 18-26)
	DATA BYTE 1, 17,2,9,1		' lower-left tier  (cols 2-10)
	DATA BYTE 1, 17,18,9,1		' lower-right tier (cols 18-26)
	' Clear floor approach to the chain; the decorative pump is removed.
	DATA BYTE 2, 26,18,4		' chain at the platform's right edge
	DATA BYTE 1, 23,2,28,2		' ground (cols 2-29)
	' Conveyor MACHINES (op 6: bottom-drum row,col, ROWS-to-rise h). True 2:1:
	' drums 2h cols apart, belt drawn on the exact line between them.
	DATA BYTE 6, 8,22,2		' right conveyor: drum (8,22) -> top drum (6,26)
	' The repaired jump reaches the crane from the reference's original position.
	DATA BYTE 6, 22,5,2		' left conveyor: drum (22,5) -> top drum (20,9)
	' Supported furnace: left-facing outlet, flame curls upward as it extends.
	DATA BYTE 8, 3,26,1,124
	DATA BYTE 8, 3,27,1,125
	DATA BYTE 8, 4,26,1,126
	DATA BYTE 8, 4,27,1,127
	DATA BYTE 8, 4,28,1,120
	DATA BYTE 8, 4,29,1,121
	DATA BYTE 8, 5,28,1,122
	DATA BYTE 8, 5,29,1,123
	DATA BYTE 8, 6,28,2,134		' centered rivets across the furnace support
	' The ground stack is scenery; the six-pixel crate on the mid-left tier
	' is hazardous on contact but short enough to clear with a normal jump.
	' The stack under the
	' lower-left tier used to be painted as a girder, which handed the player
	' a whole extra platform the reference does not have.
	DATA BYTE 8, 18,2,4,225
	DATA BYTE 8, 18,6,1,226		' downward spigot over lower conveyor
	DATA BYTE 8, 12,7,1,167		' two-cell low crate, mid-left tier
	DATA BYTE 8, 12,8,1,168
	' Moving electromagnet above the shaft; crane starts near the ground.
	DATA BYTE 5,9, 2,16		' overhead electromagnet
	DATA BYTE 5,10, 20		' crane beam, starts near the lower conveyor
	' One open-mouthed receiver beside the lower conveyor. No duplicate
	' machine to the right of the crane's moving girder.
	DATA BYTE 1, 21,10,1,6		' receiver upper left
	DATA BYTE 1, 21,11,1,7		' receiver upper right
	DATA BYTE 8, 22,10,1,162		' lower left, collar and foot
	DATA BYTE 8, 22,11,1,163		' lower right and side outlet
	' Six LUNCH PAILS, ONE PER TIER END (legacy kind payload retained). They sit
	' one row ABOVE the beam (rows 8/12/16) so they rest ON the girder instead
	' of punching a hole in it -- and so take_item's torso probe can reach them.
	DATA BYTE 5,8, 8,6,0		' upper-left tier   (reference cols 6-7)
	DATA BYTE 5,8, 22,19,5		' ground pail
	DATA BYTE 5,8, 12,3,1		' mid-left tier     (one cell left for clearance)
	DATA BYTE 5,8, 12,24,2		' mid-right tier    (reference cols 19-20)
	DATA BYTE 5,8, 16,2,3		' lower-left tier   (reference cols 2-3)
	DATA BYTE 5,8, 16,19,4		' lower-right tier  (reference cols 19-20)
	' Vandal patrols ground and lower-right tier via the chain.
	DATA BYTE 5,11, 23,22,28
	' Mack spawns on the GROUND at the bottom left, where the reference puts
	' him: walk right onto the lower conveyor, ride it up to its top drum, and
	' jump across to the crane beam.
	DATA BYTE 5,4,1, 4,12
	DATA BYTE 5,4,2, 22,16
	' Ground hazard stays LEFT of the chain, leaving a clear climbing approach.
	DATA BYTE 8, 22,21,1,166
	DATA BYTE 5,13, 23,3
	DATA BYTE 0

	'
	' ---- LEVEL 3: "Rivet Works" -------------------------------------
	' Transcribed from assets/HHM-Level3.png at its cell grid. Beams are
	' ORANGE here (type 3). Two moving paddles circulate around the green
	' centre shaft; the shaft itself is pass-through scenery.
	' Drop six steel boxes from the lower-floor openings into the IN hoppers.
	'
level3_data:
	DATA BYTE 8, 6,7,1,243
	DATA BYTE 8, 6,8,1,244
	DATA BYTE 8, 7,7,1,245
	DATA BYTE 8, 7,8,1,246
	DATA BYTE 8, 8,7,1,247
	DATA BYTE 8, 8,8,1,248
	' Transcribed from assets/HHM-Level3.png at the 32x24 cell grid (playfield
	' rect x 98..1086, y 41..708 of the 1280x720 capture; beams land on rows
	' 5/9/13/17 with the ground at 23, exactly like levels 1 and 2). Measured:
	'   top beam        row 5, cols 2-29 (full width)
	'   flat conveyor   row 9, cols 2-11, running LEFT into the grinder
	'   grinder         cols 2-3, at torso height over the belt's end
	'   upper-right     row 9, cols 21-29
	'   mid beams       row 13, cols 2-10 and 21-29
	'   lower beams     row 17, cols 2-4, 7-10, 21-24, 27-29
	'   pater-noster    cols 15-16, with step-off stubs at rows 10/12/14/16
	'   ground          row 23, cols 2-29
	'   IN machines     cols 3-7 and 24-28; door cols 14-17; pads cols 11 & 20
	DATA BYTE 1, 5,2,28,3		' top beam (cols 2-29)
	DATA BYTE 1, 9,21,9,3		' upper-right beam (cols 21-29)
	DATA BYTE 1, 13,2,9,3		' mid-left beam  (cols 2-10)
	DATA BYTE 1, 13,21,9,3		' mid-right beam (cols 21-29)
	DATA BYTE 1, 17,2,3,3		' lower-left  A (cols 2-4)
	DATA BYTE 1, 17,7,4,3		' lower-left  B (cols 7-10)
	DATA BYTE 1, 17,21,4,3		' lower-right A (cols 21-24)
	DATA BYTE 1, 17,27,3,3		' lower-right B (cols 27-29)
	DATA BYTE 1, 23,2,28,2		' ground (cols 2-29)
	' Shaft scenery. Springboards reach the circulating paddles; Fire exits.
	DATA BYTE 10, 15,8,10,208	' left rail, rows 8-17
	DATA BYTE 10, 16,8,10,209	' right rail, rows 8-17
	DATA BYTE 8, 7,15,1,114
	DATA BYTE 8, 7,16,1,115
	DATA BYTE 8, 8,15,1,116
	DATA BYTE 8, 8,16,1,117
	DATA BYTE 8, 17,15,1,114
	DATA BYTE 8, 17,16,1,115
	DATA BYTE 8, 18,15,1,116
	DATA BYTE 8, 18,16,1,117
	DATA BYTE 8, 19,4,1,124
	DATA BYTE 8, 19,5,1,125
	DATA BYTE 8, 20,4,1,126
	DATA BYTE 8, 20,5,1,127
	DATA BYTE 8, 19,25,1,124
	DATA BYTE 8, 19,26,1,125
	DATA BYTE 8, 20,25,1,126
	DATA BYTE 8, 20,26,1,127
	' Flat belt carries Mack LEFT into the wall's continuous spark discharge.
	DATA BYTE 9, 9,2,10,1		' row 9, cols 2-11, direction 1 = left
	' Shared belt surface plus the last two pixels of the smasher stroke.
	DATA BYTE 8, 9,7,1,249
	DATA BYTE 8, 9,8,1,250
	DATA BYTE 8, 8,2,1,164		' wall spark emitter, left half
	DATA BYTE 8, 8,3,1,165		' outward spark trails, right half
	' Chains, where the reference hangs them.
	DATA BYTE 10, 4,6,2,155		' top beam -> conveyor, the ESCAPE chain (col 4)
	' No right-end shortcut: enter the conveyor from the lift and escape left.
	DATA BYTE 10, 24,6,2,155	' top beam -> upper-right beam (col 24)
	DATA BYTE 10, 9,14,3,155	' mid-left -> lower-left  (col 9)
	DATA BYTE 10, 29,14,3,155	' mid-right -> lower-right (col 29)
	' Ground machinery. The two IN hoppers eat the steel boxes; the processor
	' toilet in the centre is lethal. Pads bounce Mack across to the opposite
	' pad, then upward onto the opposite lower platform.
	DATA BYTE 8, 21,3,1,210
	DATA BYTE 8, 21,4,1,211
	DATA BYTE 8, 21,5,1,212
	DATA BYTE 8, 21,6,1,213
	DATA BYTE 8, 21,7,1,120	' discharge nozzle facing the left bucket
	DATA BYTE 8, 22,3,1,215
	DATA BYTE 8, 22,4,1,216
	DATA BYTE 8, 22,5,1,217
	DATA BYTE 8, 22,6,1,218
	DATA BYTE 8, 22,7,1,219
	DATA BYTE 8, 21,24,1,121	' discharge nozzle facing the right bucket
	DATA BYTE 8, 21,25,1,211
	DATA BYTE 8, 21,26,1,212
	DATA BYTE 8, 21,27,1,213
	DATA BYTE 8, 21,28,1,214
	DATA BYTE 8, 22,24,1,215
	DATA BYTE 8, 22,25,1,216
	DATA BYTE 8, 22,26,1,217
	DATA BYTE 8, 22,27,1,218
	DATA BYTE 8, 22,28,1,219
	DATA BYTE 8, 19,14,1,96
	DATA BYTE 8, 19,15,1,97
	DATA BYTE 8, 19,16,1,98
	DATA BYTE 8, 19,17,1,99
	DATA BYTE 8, 20,14,1,100
	DATA BYTE 8, 20,15,1,101
	DATA BYTE 8, 20,16,1,102
	DATA BYTE 8, 20,17,1,103
	DATA BYTE 8, 21,14,1,104
	DATA BYTE 8, 21,15,1,105
	DATA BYTE 8, 21,16,1,106
	DATA BYTE 8, 21,17,1,107
	DATA BYTE 8, 22,14,1,108
	DATA BYTE 8, 22,15,1,109
	DATA BYTE 8, 22,16,1,110
	DATA BYTE 8, 22,17,1,111
	' Two-character springs sit one row ABOVE the ground, inside the site.
	DATA BYTE 8, 22,10,1,139
	DATA BYTE 8, 22,11,1,140
	DATA BYTE 8, 22,19,1,141
	DATA BYTE 8, 22,20,1,142
	' One broad rivet-collection bucket per side.
	DATA BYTE 8, 22,8,1,112
	DATA BYTE 8, 22,9,1,113
	DATA BYTE 8, 22,21,1,112
	DATA BYTE 8, 22,22,1,113

	' Six steel boxes, one per beam, each resting ON the girder (one row above
	' it) so the torso probe can reach them. The conveyor one rides at belt
	' height and stays put; the conveyor carries Mack toward the grinder.
	DATA BYTE 5,2, 4,12		' on the top beam
	DATA BYTE 5,2, 8,6		' on the flat conveyor, one cell left of the smasher
	DATA BYTE 5,2, 12,4		' mid-left beam
	DATA BYTE 5,2, 12,28		' mid-right beam
	DATA BYTE 5,2, 16,8		' lower-left beam B
	DATA BYTE 5,2, 16,22		' lower-right beam A
	' Enemies guard the mid beams, as the reference draws them.
	DATA BYTE 5,11, 13,21,29		' vandal on the right middle/lower beams
	DATA BYTE 5,12, 13,2,10	' OSHA on the left middle/lower beams
	DATA BYTE 5,4,1, 4,11
	DATA BYTE 5,13, 9,27		' Mack starts on the upper-right beam
	DATA BYTE 0

jump_data:
	' 128+dy: a ROUND parabola, apex 11 px (the ceiling max now the
	' characters are 12 px -- head at my+4, probe my+3 clears row 18). Steep
	' at launch and landing, flat over the top, for a rounded curve. 8 up
	' then 8 down; normal jumps add a 16-step apex hold in st_jump.
	' Total normal span 32 px; spring launches still use just these 16 steps.
	' dy = -2,-2,-2,-1,-1,-1,-1,-1,+1,+1,+1,+1,+1,+2,+2,+2
	DATA BYTE 126,126,126,127,127,127,127,127,129,129,129,129,129,130,130,130

	'
	' ---- Tile patterns and colors ----
	' Colors are 8 bytes per char (fg<<4|bg per pixel row); background 1
	' (black) everywhere so sprites pass in front cleanly.
	'
tile_pat:
	' Generated by assets/genfixtures.py (spring halves also genconveyors.py).
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$00
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$81,$81,$81,$81,$81,$81,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$00
	DATA BYTE $FF,$FF,$FF,$FF,$00,$00,$00,$00
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$92,$FF,$00,$00,$00,$00
	DATA BYTE $FF,$FF,$49,$FF,$00,$00,$00,$00
	' 137/138 springboard idle halves; generated by assets/genconveyors.py.
	DATA BYTE $7F,$7F,$02,$04,$02,$04,$1F,$1F
	DATA BYTE $FE,$FE,$40,$20,$40,$20,$F8,$F8
tile_col:
	' Generated by assets/genfixtures.py (spring halves also genconveyors.py).
	DATA BYTE $61,$41,$41,$41,$41,$41,$61,$11
	DATA BYTE $41,$31,$31,$34,$34,$31,$31,$41
	DATA BYTE $A1,$A1,$51,$51,$51,$51,$A1,$A1
	DATA BYTE $F1,$F6,$F6,$F6,$F6,$F6,$F6,$F1
	DATA BYTE $61,$41,$41,$41,$41,$41,$61,$11
	DATA BYTE $31,$31,$A1,$A1,$11,$11,$11,$11
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$F1,$F1,$F1,$11,$11,$11,$11
	DATA BYTE $F1,$F1,$F1,$F1,$11,$11,$11,$11
	' 137/138 springboard idle halves; generated by assets/genconveyors.py.
	DATA BYTE $F1,$D1,$31,$D1,$31,$D1,$31,$31
	DATA BYTE $F1,$D1,$31,$D1,$31,$D1,$31,$31
chain_pat:
	' Hanging chain, climbable (cyan links)
	DATA BYTE $18,$3C,$24,$3C,$18,$3C,$24,$3C
chain_col:
	DATA BYTE $71,$71,$71,$71,$71,$71,$71,$71
pillar_pat:
	' 174 support pillar: dotted box column (art only)
	DATA BYTE $BD,$BD,$A5,$BD,$BD,$BD,$A5,$BD
	' 175 pedestal base under the bottom girder (art only)
	DATA BYTE $3C,$3C,$3C,$3C,$3C,$7E,$FF,$FF
pillar_col:
	' white outside rails and green core with bolt holes
	DATA BYTE $3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F
	' pedestal: white with red foot
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$61,$61,$61
item_pat:
	' Generated by assets/genfixtures.py (spring halves also genconveyors.py).
	DATA BYTE $FF,$81,$81,$81,$81,$81,$81,$FF
	DATA BYTE $00,$63,$63,$3E,$1C,$38,$70,$60
	DATA BYTE $10,$3C,$18,$3C,$3C,$3C,$3C,$3C
	DATA BYTE $00,$18,$3C,$7E,$7E,$FF,$00,$00
item_col:
	' Generated by assets/genfixtures.py (spring halves also genconveyors.py).
	DATA BYTE $F1,$F6,$F6,$F6,$F6,$F6,$F6,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
pail_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $3F,$FE,$FE,$C3,$C3,$C3,$C3,$FF
	DATA BYTE $FC,$7F,$7F,$33,$03,$03,$03,$FF
pail_col:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $F1,$F6,$F6,$F6,$F6,$F6,$F6,$F1
	DATA BYTE $F1,$F6,$F6,$F6,$F6,$F6,$F6,$F1
mixb_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $5F,$5F,$3F,$3F,$1F,$0F,$7F,$7F
	DATA BYTE $FB,$FB,$FE,$F0,$E0,$C0,$F8,$F8
mixb_col:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $F1,$F1,$F1,$F1,$D1,$D1,$31,$31
	DATA BYTE $F1,$F1,$F1,$F1,$D1,$D1,$31,$31
pn_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $30,$78,$48,$48,$48,$78,$30,$30
	DATA BYTE $0C,$1E,$12,$12,$12,$1E,$0C,$0C
pn_col:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $31,$F1,$31,$31,$31,$31,$31,$31
	DATA BYTE $31,$F1,$31,$31,$31,$31,$31,$31
chaing_col:
	' the reference draws level 3's chains green
	DATA BYTE $31,$31,$31,$31,$31,$31,$31,$31
stand_pat:
	' 179 the pinched stand under a trampoline pad (decor only)
	DATA BYTE $00,$7E,$3C,$18,$18,$3C,$7E,$00
stand_col:
	DATA BYTE $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
sbox_pat:
	' 182 steel box: a white crate with a green lid and a magenta face --
	' the reference's box, not level 1's red brick stack.
	DATA BYTE $00,$7E,$FF,$3C,$3C,$FF,$7E,$00
sbox_col:
	DATA BYTE $11,$31,$F1,$DF,$DF,$F1,$F1,$11
pad_pat:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $7F,$7F,$02,$04,$02,$04,$1F,$1F
	DATA BYTE $FE,$FE,$40,$20,$40,$20,$F8,$F8
	DATA BYTE $7F,$7F,$02,$04,$02,$04,$1F,$1F
	DATA BYTE $FE,$FE,$40,$20,$40,$20,$F8,$F8
pad_col:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $F1,$D1,$31,$D1,$31,$D1,$31,$31
	DATA BYTE $F1,$D1,$31,$D1,$31,$D1,$31,$31
	DATA BYTE $F1,$D1,$31,$D1,$31,$D1,$31,$31
	DATA BYTE $F1,$D1,$31,$D1,$31,$D1,$31,$31
convh_pat:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$00,$FF,$C0,$C0,$C0,$FF,$00
convh_col:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $11,$11,$F1,$31,$31,$31,$F1,$11
door_pat:
	' 182 the processor door under the pater-noster: a blue frame around a
	' dark-yellow panel.
	DATA BYTE $FF,$FF,$3C,$3C,$3C,$3C,$FF,$FF
door_col:
	DATA BYTE $51,$51,$A5,$A5,$A5,$A5,$51,$51
plank_pat:
	' 172 stack of planks: white boards banded with the light-blue shadow
	' between them. Decor band, so it is pass-through -- in the reference
	' this is a pile of lumber under the beam, NOT another girder.
	DATA BYTE $00,$FF,$00,$FF,$00,$FF,$00,$FF
plank_col:
	DATA BYTE $11,$F5,$F5,$F5,$F5,$F5,$F5,$F5
mach_pat:
	' 180/181 the machine cabinet standing at the top right of level 2:
	' a red cap, a white readout panel, then a blue body with two lamps.
	DATA BYTE $FF,$00,$7E,$5A,$7E,$00,$00,$00
	DATA BYTE $00,$66,$66,$00,$00,$66,$66,$00
mach_col:
	DATA BYTE $95,$F5,$F5,$F5,$F5,$F5,$F5,$F5
	DATA BYTE $F5,$F5,$F5,$F5,$F5,$F5,$F5,$F5
inm_pat:
	' 191 IN hopper (level 3): a wide chute mouth -- walk in carrying a
	' steel box to feed the machine. Decor band, so it is pass-through.
	DATA BYTE $FF,$81,$42,$24,$18,$18,$18,$3C
inm_col:
	' white rim over a green throat
	DATA BYTE $F1,$F1,$31,$31,$31,$31,$31,$31
mixer_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $1F,$20,$60,$60,$60,$60,$5F,$5F
	DATA BYTE $E0,$10,$18,$18,$18,$18,$F8,$FF
mixer_col:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
haz_pat:
	' 164 GRINDER (level 3, at the end of the belt): a toothed wheel throwing
	' sparks. It was a plain block, which read as scenery rather than as the
	' thing that eats you.
	DATA BYTE $99,$5A,$3C,$FF,$FF,$3C,$5A,$99
	' 165 spare
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	' 166 flame
	DATA BYTE $10,$54,$38,$7C,$BA,$FE,$7C,$38
haz_col:
	DATA BYTE $91,$91,$E1,$E1,$E1,$E1,$91,$91
	DATA BYTE $61,$61,$61,$61,$61,$61,$61,$61
	DATA BYTE $B1,$91,$91,$B1,$91,$B1,$91,$61
conv_pat:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$03,$0C,$30,$C3,$CC,$F0,$C0
	DATA BYTE $00,$00,$00,$00,$00,$03,$0C,$30
	DATA BYTE $C3,$CC,$F0,$C0,$00,$00,$00,$00
	DATA BYTE $3C,$6E,$C3,$99,$99,$C3,$66,$3C
	DATA BYTE $18,$18,$18,$18,$18,$18,$18,$7E
conv_col:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
belt_anim0:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$03,$0C,$30,$C3,$CC,$F0,$C0
	DATA BYTE $00,$00,$00,$00,$00,$03,$0C,$30
	DATA BYTE $C3,$CC,$F0,$C0,$00,$00,$00,$00
	DATA BYTE $3C,$6E,$C3,$99,$99,$C3,$66,$3C
	DATA BYTE $18,$18,$18,$18,$18,$18,$18,$7E
	DATA BYTE $00,$00,$FF,$C0,$C0,$C0,$FF,$00
belt_anim1:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$03,$0C,$30,$E3,$6C,$70,$C0
	DATA BYTE $00,$00,$00,$00,$00,$03,$0C,$30
	DATA BYTE $E3,$6C,$70,$C0,$00,$00,$00,$00
	DATA BYTE $3C,$66,$C7,$99,$99,$C3,$66,$3C
	DATA BYTE $18,$18,$18,$18,$18,$18,$18,$7E
	DATA BYTE $00,$00,$FF,$60,$60,$60,$FF,$00
belt_anim2:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$03,$0C,$30,$F3,$3C,$30,$C0
	DATA BYTE $00,$00,$00,$00,$00,$03,$0C,$30
	DATA BYTE $F3,$3C,$30,$C0,$00,$00,$00,$00
	DATA BYTE $3C,$66,$C3,$99,$9B,$C3,$66,$3C
	DATA BYTE $18,$18,$18,$18,$18,$18,$18,$7E
	DATA BYTE $00,$00,$FF,$30,$30,$30,$FF,$00
belt_anim3:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$03,$0C,$38,$DB,$1C,$30,$C0
	DATA BYTE $00,$00,$00,$00,$00,$03,$0C,$38
	DATA BYTE $DB,$1C,$30,$C0,$00,$00,$00,$00
	DATA BYTE $3C,$66,$C3,$99,$99,$C7,$66,$3C
	DATA BYTE $18,$18,$18,$18,$18,$18,$18,$7E
	DATA BYTE $00,$00,$FF,$18,$18,$18,$FF,$00
belt_anim4:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$03,$0C,$3C,$CF,$0C,$30,$C0
	DATA BYTE $00,$00,$00,$00,$00,$03,$0C,$3C
	DATA BYTE $CF,$0C,$30,$C0,$00,$00,$00,$00
	DATA BYTE $3C,$66,$C3,$99,$99,$C3,$76,$3C
	DATA BYTE $18,$18,$18,$18,$18,$18,$18,$7E
	DATA BYTE $00,$00,$FF,$0C,$0C,$0C,$FF,$00
belt_anim5:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$03,$0E,$36,$C7,$0C,$30,$C0
	DATA BYTE $00,$00,$00,$00,$00,$03,$0E,$36
	DATA BYTE $C7,$0C,$30,$C0,$00,$00,$00,$00
	DATA BYTE $3C,$66,$C3,$99,$99,$E3,$66,$3C
	DATA BYTE $18,$18,$18,$18,$18,$18,$18,$7E
	DATA BYTE $00,$00,$FF,$06,$06,$06,$FF,$00
belt_anim6:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$03,$0F,$33,$C3,$0C,$30,$C0
	DATA BYTE $00,$00,$00,$00,$00,$03,$0F,$33
	DATA BYTE $C3,$0C,$30,$C0,$00,$00,$00,$00
	DATA BYTE $3C,$66,$C3,$D9,$99,$C3,$66,$3C
	DATA BYTE $18,$18,$18,$18,$18,$18,$18,$7E
	DATA BYTE $00,$00,$FF,$03,$03,$03,$FF,$00
belt_anim7:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$03,$0D,$31,$C3,$8C,$B0,$C0
	DATA BYTE $00,$00,$00,$00,$00,$03,$0D,$31
	DATA BYTE $C3,$8C,$B0,$C0,$00,$00,$00,$00
	DATA BYTE $3C,$66,$E3,$99,$99,$C3,$66,$3C
	DATA BYTE $18,$18,$18,$18,$18,$18,$18,$7E
	DATA BYTE $00,$00,$FF,$81,$81,$81,$FF,$00
mag_pat:
	' 176/177 electromagnet: a HORSESHOE (U) magnet, arch on top, two legs
	' hanging down to grab Mack -- matches the reference's white/red magnet.
	DATA BYTE $1F,$3F,$3C,$38,$38,$38,$38,$3C
	DATA BYTE $F8,$FC,$3C,$1C,$1C,$1C,$1C,$3C
mag_col:
	' white arch, red pole tips (classic horseshoe magnet)
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$61,$61
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$61,$61
cable_bitmap:
	' The last stretch of crane cable, as a SPRITE so it can meet the beam at
	' any pixel offset. Char cells can only end on an 8-px boundary, so the
	' rope used to visibly detach from the bar between cell rows; this hangs
	' from the bottom of the char cable and its bottom edge sits exactly on
	' the beam, travelling with it.
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
	BITMAP "...XX..........."
cable_pat:
	' 178 thin crane cable: a 2-px centered vertical line
	DATA BYTE $18,$18,$18,$18,$18,$18,$18,$18
cable_col:
	' light-blue cable
	DATA BYTE $51,$51,$51,$51,$51,$51,$51,$51
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
	' Generated by assets/genfixtures.py; edit the generator.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXXX...."
	BITMAP ".......XX.XX...."
	BITMAP ".......XXX......"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".....X.....X...."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".....XXX.XXX...."
mackw_bitmap:
	' Generated by assets/genfixtures.py; edit the generator.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXXX...."
	BITMAP ".......XX.XX...."
	BITMAP ".......XXX......"
	BITMAP "................"
	BITMAP "...........XX..."
	BITMAP "....X..........."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "..XXX.....XXX..."
mackl_bitmap:
	' Generated by assets/genfixtures.py; edit the generator.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXXX......"
	BITMAP "....XXXXXXX....."
	BITMAP "....XX.XX......."
	BITMAP "......XXX......."
	BITMAP "................"
	BITMAP "................"
	BITMAP "....X.....X....."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "....XXX.XXX....."
mackl2_bitmap:
	' Generated by assets/genfixtures.py; edit the generator.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXXX......"
	BITMAP "....XXXXXXX....."
	BITMAP "....XX.XX......."
	BITMAP "......XXX......."
	BITMAP "................"
	BITMAP "...XX..........."
	BITMAP "...........X...."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "...XXX.....XXX.."
mackj_bitmap:
	' Generated by assets/genfixtures.py; edit the generator.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXXX...."
	BITMAP ".......XX.XX...."
	BITMAP ".X.....XXX..X..."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
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
	' Generated by assets/genfixtures.py; edit the generator.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".....XXXXXX....."
	BITMAP ".....XXXXXX....."
	BITMAP ".....XXXXXX....."
	BITMAP ".....XXXXXX....."
	BITMAP ".....XXXXXX....."
	BITMAP ".....XXXXXX....."
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

mack_colour:
	' Generated by assets/genfixtures.py; edit the generator.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".....XX........."
	BITMAP "......X........."
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXX....."
	BITMAP "......XXXXX....."
	BITMAP "......XXXX......"
	BITMAP "......XXXX......"
	BITMAP "......XX.XX....."
	BITMAP "......XX.XX....."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".....XX........."
	BITMAP "......X........."
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXX....."
	BITMAP ".....XXXXX......"
	BITMAP ".....XXXXX......"
	BITMAP ".....XX.XXX....."
	BITMAP "....XX...XX....."
	BITMAP "...XX.....XX...."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".........XX....."
	BITMAP ".........X......"
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXX....."
	BITMAP ".....XXXXX......"
	BITMAP "......XXXX......"
	BITMAP "......XXXX......"
	BITMAP ".....XX.XX......"
	BITMAP ".....XX.XX......"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".........XX....."
	BITMAP ".........X......"
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXX....."
	BITMAP "......XXXXX....."
	BITMAP "......XXXXX....."
	BITMAP ".....XXX.XX....."
	BITMAP ".....XX...XX...."
	BITMAP "....XX.....XX..."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".....XX........."
	BITMAP "......X........."
	BITMAP ".XX.XXXXXX.XX..."
	BITMAP "..XXXXXXXXXX...."
	BITMAP ".....XXXXXX....."
	BITMAP "....XXXXXXXX...."
	BITMAP "...XXX....XXX..."
	BITMAP "..XXX......XXX.."
	BITMAP "................"
	BITMAP "................"
mack_run_extra:
	' Generated by assets/genfixtures.py; edit the generator.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXXX...."
	BITMAP ".......XX.XX...."
	BITMAP ".......XXX......"
	BITMAP "................"
	BITMAP "...XX..........."
	BITMAP "...........X...."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "..XX............"
	BITMAP "........XXX....."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".....XX........."
	BITMAP "......X........."
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXX....."
	BITMAP ".....XXXXX......"
	BITMAP "......XXXX......"
	BITMAP "....XXX.XX......"
	BITMAP "...XX...XX......"
	BITMAP "........XX......"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXXX......"
	BITMAP "....XXXXXXX....."
	BITMAP "....XX.XX......."
	BITMAP "......XXX......."
	BITMAP "................"
	BITMAP "...........XX..."
	BITMAP "....X..........."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "............XX.."
	BITMAP ".....XXX........"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".........XX....."
	BITMAP ".........X......"
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXX....."
	BITMAP "......XXXXX....."
	BITMAP "......XXXX......"
	BITMAP "......XX.XXX...."
	BITMAP "......XX...XX..."
	BITMAP "......XX........"
	BITMAP "................"
lift_bitmap:
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
	BITMAP "................"
cage_bitmap:
	BITMAP "XXXXXXXXXXXXXXXX"
	BITMAP "X..............X"
	BITMAP "X..............X"
	BITMAP "X..............X"
	BITMAP "X..............X"
	BITMAP "X..............X"
	BITMAP "X..............X"
	BITMAP "X..............X"
	BITMAP "X..............X"
	BITMAP "X..............X"
	BITMAP "X..............X"
	BITMAP "X..............X"
	BITMAP "X..............X"
	BITMAP "X..............X"
	BITMAP "X..............X"
	BITMAP "X..............X"

drill_route:
	DATA BYTE 88,152,88,120,208,120,208,88,24,88,24,56,168,56,168,24,208,24
	DATA BYTE 208,56,24,56,24,88,208,88,208,120,88,120,88,152,24,152,24,152
steel_bitmap:
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "....XXXXXXXX...."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "...XX....XXXX..."
	BITMAP "...XX....XXXX..."
	BITMAP "...XXXXXXXXXX..."
	BITMAP "....XXXXXXXX...."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
magnet_bitmap:
	BITMAP ".......XX......."
	BITMAP ".......XX......."
	BITMAP ".......XX......."
	BITMAP ".......XX......."
	BITMAP ".......XX......."
	BITMAP ".......XX......."
	BITMAP ".......XX......."
	BITMAP ".......XX......."
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXX....."
	BITMAP ".....XX..XX....."
	BITMAP ".....XX..XX....."
	BITMAP "....XXX..XXX...."
	BITMAP "....XXX..XXX...."
	BITMAP "................"
	BITMAP "................"
bell_pat:
	DATA BYTE $18,$3C,$3C,$3C,$7E,$FF,$18,$00
bell_col:
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$D1,$F1,$11

claw_col:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $11,$11,$F1,$F1,$F1,$31,$31,$F1
	DATA BYTE $11,$11,$F1,$F1,$F1,$31,$31,$F1
	DATA BYTE $11,$11,$F1,$F1,$F1,$31,$31,$F1
	DATA BYTE $11,$11,$F1,$F1,$F1,$31,$31,$F1
	DATA BYTE $11,$11,$F1,$F1,$F1,$31,$31,$F1
cage_col:
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1

spigot_pat:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $FF,$FF,$FF,$FF,$00,$00,$00,$00
	DATA BYTE $FF,$FF,$FE,$7E,$7E,$7E,$7E,$7E
spigot_col:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $51,$F1,$51,$51,$11,$11,$11,$11
	DATA BYTE $51,$F1,$51,$51,$91,$91,$91,$91
slag_bitmap:
	' Two tumbling six-pixel slag lumps; visible bottom is y+8.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXX....."
	BITMAP ".....XX.XXX....."
	BITMAP ".....XXX.XX....."
	BITMAP ".....XXXXXX....."
	BITMAP "......XXXX......"
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
	BITMAP "......XXXX......"
	BITMAP ".....XXXXXX....."
	BITMAP ".....XXX.XX....."
	BITMAP ".....XX.XXX....."
	BITMAP ".....XXXXXX....."
	BITMAP "......XXXX......"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"


asset_end:
	DATA BYTE 72,72,77,65,67,75,26,1

	#if TI994A
	BANK 2
	#endif

crate_pat:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$FF,$81,$BD,$BD,$81,$FF,$00
	DATA BYTE $00,$FF,$81,$BD,$BD,$81,$FF,$00
crate_col:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $F1,$F1,$71,$71,$71,$71,$F1,$F1
	DATA BYTE $F1,$F1,$71,$71,$71,$71,$F1,$F1
burn_bitmap:
	BITMAP "....X...X......."
	BITMAP "...XX..XXX......"
	BITMAP "..XXX.XXXX......"
	BITMAP "...X...XX......."
	BITMAP "..XX...X...X...."
	BITMAP ".XXX...X..XX...."
	BITMAP "..X......XXX...."
	BITMAP ".XX......XX....."
	BITMAP "..X.......X....."
	BITMAP ".....X....XX...."
	BITMAP ".....XX...X....."
	BITMAP "......X..XX....."
	BITMAP "......X...X....."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
banked_hud_all:
	PRINT AT CPOS(0,10),"BONUS "
	' The mid-left Level-2 crate art is stored in this bank to preserve the
	' fixed/fixture-bank budgets; upload it while its source page is selected.
	DEFINE CHAR 167,2,crate_pat
	DEFINE COLOR 167,2,crate_col
	DEFINE SPRITE 37,1,burn_bitmap
	WAIT
	PRINT AT CPOS(0,HUD_BONUS_COL),<.4>#bonus
	PRINT AT CPOS(0,29),"   "
	IF levelno < 10 THEN PRINT AT CPOS(0,30),"L",levelno
	IF levelno >= 10 THEN
		IF levelno < 100 THEN PRINT AT CPOS(0,29),"L",levelno
	END IF
	' A three-digit level fills the last three cells; all eight reserve hats fit.
	IF levelno >= 100 THEN PRINT AT CPOS(0,29),levelno
	GOSUB banked_hud_lives
	RETURN

banked_actors_move:
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
			' A released hammer must leave Mack's reach before it can be caught.
			IF hit = 0 THEN jhlock = 0
			IF jhlock = 1 THEN hit = 0
			IF hit = 1 THEN
				jhtk = 1
				carry = 2
				jbhc = 0
				#sndpitch = 150
				sndvol = 12
				sfxlen = 10
				GOSUB tone_start
			END IF
		END IF
	END IF
	' Vandal: lethal on contact; each site has its own walk/climb route.
	IF von = 1 THEN
		IF vroute = 0 THEN
			rx = vx
			ry = vy
			rf = vd
			rp = vp
			GOSUB site_route
			vx = rx
			vy = ry
			vd = rf
			vp = rp
		END IF
		ex = vx
		ey = vy
		hbw = 8
		hbh = 12
		GOSUB hazard_hit
	END IF
	' OSHA man: patrols the left factory tiers via their edge chain.
	IF oon = 1 THEN
		rx = ox
		ry = oy
		rf = od
		rp = opath
		IF vroute = 1 THEN
			rb = ob
			rd = odr
			rsv = osv
			GOSUB route_step
			ob = rb
			odr = rd
			osv = rsv
		ELSE
			GOSUB site_route
		END IF
		ox = rx
		oy = ry
		od = rf
		opath = rp
		ex = ox
		ey = oy
		hbw = 8
		hbh = 12
		GOSUB hazard_hit
	END IF
	' Rivets share this world clock through bolt_move.
	' Bonus ticks down while the clock runs; reaching zero kills Mack
	' (authentic). Respawn refills it to 5000 (per-life, see dead_tick).
	btk = btk - 1
	IF btk = 0 THEN
		btk = 120
		IF #bonus >= 100 THEN
			#bonus = #bonus - 100
		ELSE
			#bonus = 0
		END IF
		PRINT AT CPOS(0,HUD_BONUS_COL),<.4>#bonus
		IF #bonus = 0 THEN GOSUB mack_die
	END IF
	RETURN

banked_enemy_setup:
	' First tour retains the original site cast; repeat tours choose each
	' roamer independently. Two vandals or two inspectors are both valid.
	vkind = 0
	okind = 1
	IF levelno < 4 THEN RETURN
	vkind = RANDOM(2)
	okind = RANDOM(2)
	oon = 1
	IF lv = 1 THEN
		ox = 208
		oy = 120
		ob = 2
		odr = 0
		osv = 2
	END IF
	IF lv = 2 THEN
		ox = 144
		oy = 120
	END IF
	ox0 = ox
	oy0 = oy
	opath = 0
	od = 1
	RETURN

banked_enemy_draw:
	IF von = 1 THEN
		vfr = 12
		IF anm2 = 1 THEN vfr = 36
		enemycolor = 3
		IF vkind = 1 THEN
			vfr = 16
			enemycolor = 11
		END IF
		SPRITE 4,vy - 1,vx,vfr,enemycolor
	ELSE
		SPRITE 4,209,0,0,0
	END IF
	IF oon = 1 THEN
		vfr = 16
		enemycolor = 11
		IF okind = 0 THEN
			vfr = 12
			IF anm2 = 1 THEN vfr = 36
			enemycolor = 3
		END IF
		SPRITE 5,oy - 1,ox,vfr,enemycolor
	ELSE
		SPRITE 5,209,0,0,0
	END IF
	RETURN

banked_work_sound:
	#workpitch = 550
	workvol = 8
	snd1 = 6
	IF workfx = 1 THEN
		#workpitch = 860
		workvol = 5
		snd1 = 2
		IF lv = 1 THEN
			IF emov = 1 THEN
				' A smaller PSG divisor sounds higher. Bottom is the lowest
				' valid 10-bit note; the caller steps every eight pixels.
				#elevpitch = 351 + (ely - elty) * 7
				SOUND 0,#elevpitch,10
			END IF
		END IF
	END IF
	IF workfx = 2 THEN
		#workpitch = 700
		workvol = 7
		snd1 = 3
	END IF
	IF workfx = 3 THEN
		#workpitch = 240
		workvol = 9
		snd1 = 5
	END IF
	IF workfx = 4 THEN
		#workpitch = 120
		' SOUND attenuation increases with the volume value; 13 is about
		' half the former amplitude while preserving the jackhammer texture.
		workvol = 13
		snd1 = 8
	END IF
	SOUND 1,#workpitch,workvol
	IF workfx = 4 THEN RETURN
	snd3 = 2
	SOUND 3,5,workvol
	RETURN

banked_death_cleanup:
	' Runs from the fixed-bank death tick, after collision callers unwind.
	IF lv = 1 THEN GOSUB elev_reset
	IF carry = 1 THEN
		IF lives > 0 THEN
			itst(cidx) = 0
			#va = VADDR(itr(cidx),itc(cidx))
			ch = T_BRICK
			IF lv = 3 THEN ch = T_SBOX
			VPOKE #va,ch
		END IF
	END IF
	IF carry = 2 THEN jhtk = 0
	carry = 0
	jhx = jhx0
	jhy = jhy0
	jhway = 0
	jhlock = 0
	RETURN

banked_sound_tick:
	' Age each envelope against video frames, even on a busy three-frame pass.
	FOR sfstep = 1 TO #fd
		IF snd0 > 0 THEN
			snd0 = snd0 - 1
			IF snd0 = 0 THEN
				SOUND 0,,0
			ELSE
				IF snd0 = 8 THEN #rewardpitch = #rewardpitch - #rewardpitch / 4
				IF snd0 = 4 THEN #rewardpitch = #rewardpitch / 2
				IF snd0v > 4 THEN snd0v = snd0v - 1
				SOUND 0,#rewardpitch,snd0v
			END IF
		END IF
		IF snd1 > 0 THEN
			snd1 = snd1 - 1
			IF snd1 = 0 THEN SOUND 1,,0
			IF snd1 = 3 THEN SOUND 1,330,6
		END IF
		IF snd2 > 0 THEN
			snd2 = snd2 - 1
			IF snd2 = 0 THEN
				SOUND 2,,0
			ELSE
				IF sndkind = 1 THEN #motionpitch = #motionpitch + 24
				IF sndkind = 2 THEN #motionpitch = #motionpitch - 12
				IF snd2v > 3 THEN snd2v = snd2v - 1
				SOUND 2,#motionpitch,snd2v
			END IF
		END IF
		IF snd3 > 0 THEN
			snd3 = snd3 - 1
			IF snd3 = 0 THEN SOUND 3,,0
			IF snd3 = 5 THEN SOUND 3,5,6
		END IF
		IF edance THEN GOSUB banked_dance_frame
	NEXT sfstep
	RETURN

banked_dance_frame:
	' C64 reference 38.92-39.45: two quick squash/rise cycles after arrival.
	' Advance once per VIDEO frame, not once per accelerated world step.
	IF edance = 32 THEN
		DEFINE SPRITE 27,4,dance_bitmap
		dancelast = 255
		snd0 = 0
	END IF
	dancepose = ((32 - edance) / 4) AND 3
	dancebody = 108
	dancecolour = 112
	IF dancepose = 1 THEN
		dancebody = 116
		dancecolour = 120
	END IF
	IF dancepose = 3 THEN
		dancebody = 0
		dancecolour = 60
	END IF
	' Reference spectrum alternates approximately 400 and 250 Hz.
	' PSG periods preserve the two-tone gesture, without the SID timbre.
	dancenote = (32 - edance) / 5
	IF dancenote <> dancelast THEN
		dancelast = dancenote
		#dancepitch = 280
		IF dancenote AND 1 THEN #dancepitch = 447
		SOUND 0,#dancepitch,10
	END IF
	edance = edance - 1
	IF edance = 0 THEN SOUND 0,,0
	RETURN

dance_bitmap:
	' Editable 16x16 pairs: white hat/skin/boots, then purple clothes.
	' Half crouch: arms out, knees bent, soles still on the cabin floor.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".....XXXXX......"
	BITMAP "....XXXXXXX....."
	BITMAP "...XXXXXXXXX...."
	BITMAP ".....XXXXX......"
	BITMAP "......XXX......."
	BITMAP "..XX.......XX..."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "...XXX...XXX...."
	BITMAP "...XXX...XXX...."
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
	BITMAP "....XXXXXXX....."
	BITMAP "....XXXXXXX....."
	BITMAP "....XX...XX....."
	BITMAP "...XX.....XX...."
	BITMAP "................"
	BITMAP "................"
	' Deep crouch, widened stance; the body compresses instead of floating.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".....XXXXX......"
	BITMAP "....XXXXXXX....."
	BITMAP "...XXXXXXXXX...."
	BITMAP ".....XXXXX......"
	BITMAP "..XX.......XX..."
	BITMAP "................"
	BITMAP "..XXXX...XXXX..."
	BITMAP "..XXXX...XXXX..."
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
	BITMAP "....XXXXXXX....."
	BITMAP "...XXX...XXX...."
	BITMAP "................"
	BITMAP "................"

banked_completion_music:
	' Original port fanfare: twelve articulated notes, harmony and bass.
	' Four bytes per event keep the following data word-aligned.
	GOSUB quiet_audio
	IF lv = 1 THEN RESTORE victory_music1
	IF lv = 2 THEN RESTORE victory_music2
	IF lv = 3 THEN RESTORE victory_music3
	FOR songi = 0 TO 11
		READ BYTE songlead
		READ BYTE songlow
		READ BYTE songchord
		READ BYTE songlen
		#songpitch = songlead
		#songbass = songlow * 4
		#songharm = songchord * 2
		SOUND 0,#songpitch,11
		SOUND 1,#songharm,6
		SOUND 2,#songbass,8
		IF (songi AND 3) = 0 THEN SOUND 3,4,6
		FOR songwait = 1 TO songlen
			WAIT
			IF songwait = 2 THEN SOUND 3,,0
			IF songwait = 4 THEN
				SOUND 0,,8
				SOUND 2,,5
			END IF
		NEXT songwait
		SOUND 0,,0
		SOUND 1,,0
		SOUND 2,,0
		WAIT
	NEXT songi
	GOSUB quiet_audio
	RETURN

victory_music1:
	' Beams: bright C-major call/response. Lead, bass /4, harmony /2, frames.
	DATA BYTE 214,214,170,6
	DATA BYTE 170,214,143,6
	DATA BYTE 143,214,170,10
	DATA BYTE 107,214,143,14
	DATA BYTE 127,160,127,6
	DATA BYTE 143,160,160,6
	DATA BYTE 160,160,127,10
	DATA BYTE 143,143,113,14
	DATA BYTE 170,143,143,6
	DATA BYTE 143,143,113,6
	DATA BYTE 113,143,143,10
	DATA BYTE 107,214,170,24

victory_music2:
	' Lunch break: rising answer to the same C-major theme.
	DATA BYTE 214,214,170,6
	DATA BYTE 190,214,143,6
	DATA BYTE 170,214,143,6
	DATA BYTE 143,214,170,10
	DATA BYTE 127,160,127,10
	DATA BYTE 143,160,160,6
	DATA BYTE 160,160,127,6
	DATA BYTE 170,214,143,10
	DATA BYTE 190,143,113,6
	DATA BYTE 143,143,113,10
	DATA BYTE 113,143,143,10
	DATA BYTE 107,214,170,24

victory_music3:
	' Factory: higher register, broader rhythm, longer final tonic.
	DATA BYTE 143,214,170,8
	DATA BYTE 107,214,143,8
	DATA BYTE 85,214,107,12
	DATA BYTE 95,143,113,8
	DATA BYTE 107,214,170,8
	DATA BYTE 143,214,170,8
	DATA BYTE 127,160,127,8
	DATA BYTE 143,143,113,8
	DATA BYTE 170,214,143,8
	DATA BYTE 143,143,113,8
	DATA BYTE 113,143,143,12
	DATA BYTE 107,214,170,28

banked_factory_output:
	IF boxfall < 2 THEN RETURN
	outputtick = outputtick + 1
	IF boxfall = 2 THEN
		IF outputtick = 10 THEN
			boxfall = 3
			outputtick = 0
			' Visible rivet pixels (x+6..8,y+4..8) begin inside the nozzle.
			boxy = 168
			boxx = 52
			' Delivery side is saved from the input, not Mack's later position.
			IF outputside = 1 THEN boxx = 189
			GOSUB machine_clack
		END IF
		RETURN
	END IF
	IF outputside = 0 THEN
		boxx = boxx + 1
	ELSE
		boxx = boxx - 1
	END IF
	' Shoot diagonally out of the tilted mouth, then arc into the bucket.
	IF outputtick <= 8 THEN
		boxy = boxy - 1
	ELSE
		boxy = boxy + 2
	END IF
	IF outputtick = 16 THEN
		boxfall = 0
		workfx = 4
		IF nbox = 0 THEN lvdone = 1
	END IF
	RETURN

banked_mag_catch:
	' Only an armed magnet can catch airborne Mack beneath its two-cell span.
	IF mgon = 0 THEN RETURN
	IF mgarm = 0 THEN RETURN
	IF st = 8 THEN RETURN
	IF st = 9 THEN RETURN
	IF st = S_WALK THEN RETURN
	IF st = S_DEAD THEN RETURN
	hy = my + 4
	mgy = mgr * 8
	mgy = mgy + 12
	IF hy <= mgy THEN
		cx = mx + 8
		mgl = mgx
		mgq = mgl + 15
		IF cx >= mgl THEN
			IF cx <= mgq THEN
				st = 8
				my = 24
				mx = mgx
			END IF
		END IF
	END IF
	RETURN

banked_mag_move:
	IF mgon = 0 THEN RETURN
	IF mgarm = 0 THEN RETURN
	IF st = 9 THEN
		' Mack stands on the crane top while the empty magnet retreats.
		IF mgx < 157 THEN mgx = mgx + 1
		IF mgx = 157 THEN lvdone = 1
		RETURN
	END IF
	IF st = 8 THEN
		IF mgx > 112 THEN mgx = mgx - 1
		IF mgx < 112 THEN mgx = mgx + 1
		mx = mgx
		my = 24
		IF mgx = 112 THEN
			mx = 120	' place Mack one character right, onto the crane top
			st = 9
		END IF
		RETURN
	END IF
	mgtk = mgtk + 1
	IF mgtk < 2 THEN RETURN
	mgtk = 0
	IF mgd = 0 THEN
		mgx = mgx - 1
		IF mgx <= 96 THEN mgd = 1
	ELSE
		mgx = mgx + 1
		IF mgx >= 208 THEN mgd = 0
	END IF
	RETURN

banked_furnace_step:
	' Extend left one pixel per two steps, curling up beyond the outlet.
	firedepth = (hzphase / 2) AND 31
	IF firedepth > 16 THEN firedepth = 32 - firedepth
	' Cabinet contact, then test the actual flame columns across Mack's torso.
	IF mx + 10 >= 225 THEN
		IF mx + 5 <= 238 THEN
			IF my + 4 <= 47 THEN
				IF my + 15 >= 34 THEN
					GOSUB mack_burn
					RETURN
				END IF
			END IF
		END IF
	END IF
	IF firedepth = 0 THEN RETURN
	fireleft = 224 - firedepth
	IF mx + 10 < fireleft THEN RETURN
	IF mx + 5 > 223 THEN RETURN
	firelo = mx + 5
	IF firelo < fireleft THEN firelo = fireleft
	firehi = mx + 10
	IF firehi > 223 THEN firehi = 223
	IF firelo > firehi THEN RETURN
	FOR firepx = firelo TO firehi
		firecalc = 223 - firepx
		firecenter = 14 - (firecalc * 7 / 15)
		IF firecalc < 2 THEN firewidth = 1
		IF firecalc >= 2 THEN
			IF firecalc < 8 THEN firewidth = 1 + firecalc / 2
		END IF
		IF firecalc >= 8 THEN
			IF firecalc < 11 THEN firewidth = 3
		END IF
		IF firecalc >= 11 THEN
			firewidth = 3 - (firecalc - 10) / 2
			IF firewidth < 0 THEN firewidth = 0
		END IF
		fireflick = (firepx - 208 + firedepth) AND 3
		IF fireflick = 0 THEN firewidth = firewidth + 1
		IF fireflick = 2 THEN firecenter = firecenter - 1
		IF fireflick = 3 THEN firecenter = firecenter + 1
		firetop = 24 + firecenter - firewidth
		firebottom = 24 + firecenter + firewidth
		IF my + 4 <= firebottom THEN
			IF my + 15 >= firetop THEN
				GOSUB mack_burn
				RETURN
			END IF
		END IF
	NEXT firepx
	RETURN

banked_hud_lives:
	' Eight reserve hats follow the centered bonus and precede the level.
	#if TI994A
	#va = VADDR(0,21)
	#else
	#va = VADDR(0,7)
	#endif
	FOR hl_slot = 0 TO 7
		IF hl_slot + lives > 7 THEN
			ch = T_HAT
		ELSE
			ch = T_VOID
		END IF
		VPOKE #va,ch
		#va = #va + 1
	NEXT hl_slot
	RETURN

animation_end:
	DATA BYTE 72,72,77,65,78,73,77,2

	#if TI994A
	BANK 3
	#endif

banked_inventory_draw:
	' Both a carried brick and the jackhammer are held IN FRONT of Mack,
	' on the side he is facing.
	' The white outline is cosmetic: slot 31 lets a roaming jackhammer retain
	' its earlier scanline priority even when Mack carries a brick.
	SPRITE 31,209,0,0,0
	IF carry = 0 THEN
		SPRITE 1,209,0,0,0
	ELSE
		IF mdir = 1 THEN
			jx2 = mx + 8
		ELSE
			jx2 = mx - 8
		END IF
		IF carry = 1 THEN
			IF lv = 3 THEN
				SPRITE 1,my - 1,jx2,88,15
			ELSE
				SPRITE 1,my - 1,jx2,28,6
				SPRITE 31,my - 1,jx2,96,15
			END IF
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
	SPRITE 3,209,0,0,0
	IF jhtk = 0 THEN
		' A loose drill can pace Mack at the same speed. Occlude it behind
		' his occupied hands so it never looks like a second carried item.
		hit = 0
		IF carry = 1 THEN
			ex = jhx
			ey = jhy
			hbw = 18
			hbh = 12
			GOSUB mack_hit
		END IF
		IF hit = 0 THEN
			jfr = 24
			IF anm2 = 1 THEN jfr = 40
			SPRITE 3,jhy - 1,jhx,jfr,7
		END IF
	END IF
	RETURN

banked_girder_chars:
	' Codes 120-123 are site-specific scenery; restore on every level/death.
	IF lv = 1 THEN
		DEFINE CHAR 120,2,support_pat
		DEFINE COLOR 120,2,support_col
	ELSEIF lv = 3 THEN
		DEFINE CHAR 120,2,eject_pat
		DEFINE COLOR 120,2,eject_col
	END IF
	girder_offset = (lv - 1) * 8
	DEFINE CHAR T_GIRDR,1,VARPTR girder_dot_pat(girder_offset)
	DEFINE COLOR T_GIRDR,1,VARPTR girder_dot_col(girder_offset)
	DEFINE CHAR 96,16,fixture_pat
	DEFINE COLOR 96,16,fixture_col
	IF lv = 2 THEN
		DEFINE CHAR 96,16,beamplain_pat
		DEFINE COLOR 96,16,beamshift_col
	END IF
	RESTORE girder_marks
	FOR girder_index = 1 TO lv
		FOR girder_column = 0 TO 31
			READ BYTE girder_mark(girder_column)
		NEXT girder_column
	NEXT girder_index
	RETURN

banked_fixture_chars:
	' 96-127 are unused lowercase glyphs during play; title restores its art.
	DEFINE CHAR 96,32,fixture_pat
	DEFINE COLOR 96,32,fixture_col
	DEFINE CHAR 210,10,machine_art
	DEFINE COLOR 210,10,machine_col
	DEFINE CHAR 232,4,thrower_pat
	DEFINE COLOR 232,4,thrower_col
	DEFINE SPRITE 24,1,brick_edge
	DEFINE CHAR 192,16,beamshift_pat
	DEFINE COLOR 192,16,beamshift_col
	RETURN

banked_fixture_draw:
	IF lv = 3 THEN
		' The drive shares the paddle phase: left down, right up, both wheels CCW.
		chainpose = pnphase AND 7
		IF chainpose <> chainlast THEN
			chainlast = chainpose
			DEFINE VRAM 3712,16,VARPTR drivechain_pat(chainpose * 16)
			DEFINE VRAM 5760,16,VARPTR drivechain_pat(chainpose * 16)
			DEFINE VRAM 11904,16,VARPTR drivechain_col(chainpose * 16)
			DEFINE VRAM 13952,16,VARPTR drivechain_col(chainpose * 16)
		END IF
		drivepose = (pnphase / 4) AND 7
		IF drivepose <> drivelast THEN
			drivelast = drivepose
			DEFINE VRAM 912,16,VARPTR wheel_anim_pat(drivepose * 32)
			DEFINE VRAM 2976,16,VARPTR wheel_anim_pat(drivepose * 32 + 16)
			DEFINE VRAM 5008,32,VARPTR wheel_anim_pat(drivepose * 32)
		END IF
		fixturepose = (hzphase / 32) AND 1
		IF fixturepose <> fixturelast THEN
			fixturelast = fixturepose
			DEFINE VRAM 5088,32,VARPTR inflash_pat(fixturepose * 32)
		END IF
	END IF
	RETURN



eject_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $FF,$FF,$30,$38,$44,$42,$81,$82
	DATA BYTE $FF,$FF,$0C,$1C,$22,$42,$81,$41
eject_col:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $11,$11,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $11,$11,$F1,$F1,$F1,$F1,$F1,$F1
support_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $7E,$7E,$3C,$18,$18,$18,$18,$18
	DATA BYTE $18,$18,$18,$3C,$3C,$7E,$FF,$FF
support_col:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $F1,$F1,$F1,$D1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$D1,$F1,$F1,$F1,$F1,$F1
wheel_anim_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $FF,$07,$0F,$18,$30,$60,$60,$61
	DATA BYTE $FF,$E0,$F0,$18,$8C,$06,$86,$86
	DATA BYTE $61,$60,$60,$30,$18,$0F,$07,$FF
	DATA BYTE $86,$06,$06,$0C,$18,$F0,$E0,$FF
	DATA BYTE $FF,$07,$0F,$18,$38,$64,$62,$61
	DATA BYTE $FF,$E0,$F0,$18,$0C,$06,$06,$86
	DATA BYTE $61,$60,$60,$30,$18,$0F,$07,$FF
	DATA BYTE $86,$06,$06,$0C,$18,$F0,$E0,$FF
	DATA BYTE $FF,$07,$0F,$18,$30,$60,$60,$61
	DATA BYTE $FF,$E0,$F0,$18,$0C,$06,$06,$86
	DATA BYTE $6B,$60,$60,$30,$18,$0F,$07,$FF
	DATA BYTE $86,$06,$06,$0C,$18,$F0,$E0,$FF
	DATA BYTE $FF,$07,$0F,$18,$30,$60,$60,$61
	DATA BYTE $FF,$E0,$F0,$18,$0C,$06,$06,$86
	DATA BYTE $61,$62,$64,$38,$18,$0F,$07,$FF
	DATA BYTE $86,$06,$06,$0C,$18,$F0,$E0,$FF
	DATA BYTE $FF,$07,$0F,$18,$30,$60,$60,$61
	DATA BYTE $FF,$E0,$F0,$18,$0C,$06,$06,$86
	DATA BYTE $61,$60,$60,$30,$18,$0F,$07,$FF
	DATA BYTE $86,$06,$86,$0C,$98,$F0,$E0,$FF
	DATA BYTE $FF,$07,$0F,$18,$30,$60,$60,$61
	DATA BYTE $FF,$E0,$F0,$18,$0C,$06,$06,$86
	DATA BYTE $61,$60,$60,$30,$18,$0F,$07,$FF
	DATA BYTE $86,$46,$26,$1C,$18,$F0,$E0,$FF
	DATA BYTE $FF,$07,$0F,$18,$30,$60,$60,$61
	DATA BYTE $FF,$E0,$F0,$18,$0C,$06,$06,$86
	DATA BYTE $61,$60,$60,$30,$18,$0F,$07,$FF
	DATA BYTE $AE,$06,$06,$0C,$18,$F0,$E0,$FF
	DATA BYTE $FF,$07,$0F,$18,$30,$60,$60,$61
	DATA BYTE $FF,$E0,$F0,$18,$1C,$26,$46,$86
	DATA BYTE $61,$60,$60,$30,$18,$0F,$07,$FF
	DATA BYTE $86,$06,$06,$0C,$18,$F0,$E0,$FF
drivechain_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $30,$78,$48,$48,$48,$78,$30,$30
	DATA BYTE $0C,$1E,$12,$12,$12,$1E,$0C,$0C
	DATA BYTE $30,$30,$78,$48,$48,$48,$78,$30
	DATA BYTE $1E,$12,$12,$12,$1E,$0C,$0C,$0C
	DATA BYTE $30,$30,$30,$78,$48,$48,$48,$78
	DATA BYTE $12,$12,$12,$1E,$0C,$0C,$0C,$1E
	DATA BYTE $78,$30,$30,$30,$78,$48,$48,$48
	DATA BYTE $12,$12,$1E,$0C,$0C,$0C,$1E,$12
	DATA BYTE $48,$78,$30,$30,$30,$78,$48,$48
	DATA BYTE $12,$1E,$0C,$0C,$0C,$1E,$12,$12
	DATA BYTE $48,$48,$78,$30,$30,$30,$78,$48
	DATA BYTE $1E,$0C,$0C,$0C,$1E,$12,$12,$12
	DATA BYTE $48,$48,$48,$78,$30,$30,$30,$78
	DATA BYTE $0C,$0C,$0C,$1E,$12,$12,$12,$1E
	DATA BYTE $78,$48,$48,$48,$78,$30,$30,$30
	DATA BYTE $0C,$0C,$1E,$12,$12,$12,$1E,$0C
drivechain_col:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $31,$F1,$31,$31,$31,$31,$31,$31
	DATA BYTE $31,$F1,$31,$31,$31,$31,$31,$31
	DATA BYTE $31,$31,$F1,$31,$31,$31,$31,$31
	DATA BYTE $F1,$31,$31,$31,$31,$31,$31,$31
	DATA BYTE $31,$31,$31,$F1,$31,$31,$31,$31
	DATA BYTE $31,$31,$31,$31,$31,$31,$31,$F1
	DATA BYTE $31,$31,$31,$31,$F1,$31,$31,$31
	DATA BYTE $31,$31,$31,$31,$31,$31,$F1,$31
	DATA BYTE $31,$31,$31,$31,$31,$F1,$31,$31
	DATA BYTE $31,$31,$31,$31,$31,$F1,$31,$31
	DATA BYTE $31,$31,$31,$31,$31,$31,$F1,$31
	DATA BYTE $31,$31,$31,$31,$F1,$31,$31,$31
	DATA BYTE $31,$31,$31,$31,$31,$31,$31,$F1
	DATA BYTE $31,$31,$31,$F1,$31,$31,$31,$31
	DATA BYTE $F1,$31,$31,$31,$31,$31,$31,$31
	DATA BYTE $31,$31,$F1,$31,$31,$31,$31,$31
machine_art:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $FF,$FF,$0C,$1C,$22,$42,$81,$41
	DATA BYTE $0F,$FF,$FF,$FF,$FF,$0F,$FF,$AA
	DATA BYTE $FF,$FF,$7E,$3C,$FF,$FF,$FF,$AA
	DATA BYTE $F0,$FF,$FF,$FF,$FF,$F0,$FF,$AA
	DATA BYTE $FF,$FF,$30,$38,$44,$42,$81,$82
	DATA BYTE $22,$1C,$0C,$18,$30,$60,$C0,$FF
	DATA BYTE $55,$AA,$55,$AA,$55,$AA,$55,$FF
	DATA BYTE $55,$AA,$55,$AA,$55,$AA,$55,$FF
	DATA BYTE $55,$AA,$55,$AA,$55,$AA,$55,$FF
	DATA BYTE $44,$38,$30,$18,$0C,$06,$03,$FF
machine_col:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $11,$11,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$11,$11,$11,$11,$F1,$F1,$61
	DATA BYTE $F1,$F1,$F1,$F1,$41,$F1,$F1,$41
	DATA BYTE $F1,$11,$11,$11,$11,$F1,$F1,$61
	DATA BYTE $11,$11,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $61,$61,$61,$61,$61,$61,$61,$F1
	DATA BYTE $41,$41,$41,$41,$41,$41,$41,$F1
	DATA BYTE $61,$61,$61,$61,$61,$61,$61,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
thrower_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $01,$01,$03,$07,$3F,$C0,$C0,$80
	DATA BYTE $80,$80,$C0,$E0,$FC,$03,$7F,$C3
	DATA BYTE $80,$F0,$C0,$C0,$C0,$3F,$FF,$FF
	DATA BYTE $C3,$C3,$C3,$C3,$7F,$FC,$FF,$FF
thrower_col:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$FD,$FD,$FD
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$FD,$FD,$DA
	DATA BYTE $FD,$FD,$FD,$FD,$FD,$F1,$11,$11
	DATA BYTE $DA,$DA,$DA,$DA,$FD,$F1,$11,$11
fixture_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $FF,$80,$80,$80,$80,$80,$80,$80
	DATA BYTE $FF,$FF,$FF,$FF,$88,$88,$88,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$89,$89,$89,$FF
	DATA BYTE $FF,$01,$01,$01,$01,$01,$01,$01
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$80
	DATA BYTE $88,$88,$FF,$FF,$FF,$FF,$80,$80
	DATA BYTE $89,$89,$FF,$FF,$FF,$FF,$01,$01
	DATA BYTE $01,$01,$01,$01,$01,$01,$01,$01
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$80
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$0D,$0D,$01,$01
	DATA BYTE $01,$01,$01,$01,$01,$01,$01,$01
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$FF
	DATA BYTE $80,$80,$80,$80,$80,$FF,$FF,$FF
	DATA BYTE $01,$01,$01,$01,$01,$FF,$FF,$FF
	DATA BYTE $01,$01,$01,$01,$01,$01,$01,$FF
	DATA BYTE $7F,$80,$C0,$C0,$C0,$C0,$7F,$3F
	DATA BYTE $FE,$01,$03,$03,$03,$03,$FE,$FC
	DATA BYTE $FF,$07,$0F,$18,$30,$60,$60,$61
	DATA BYTE $FF,$E0,$F0,$18,$8C,$06,$86,$86
	DATA BYTE $61,$60,$60,$30,$18,$0F,$07,$FF
	DATA BYTE $86,$06,$06,$0C,$18,$F0,$E0,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$03,$02,$02,$0F
	DATA BYTE $FF,$FF,$FF,$FF,$C0,$40,$40,$F0
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $01,$FF,$FF,$FF,$01,$FF,$FF,$FF
	DATA BYTE $C9,$8D,$8B,$89,$C9,$FF,$FF,$18
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $18,$18,$FF,$7E,$3C,$18,$FF,$FF
fixture_col:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $F1,$F4,$F4,$F4,$F4,$F4,$F4,$F4
	DATA BYTE $F1,$41,$41,$F1,$F4,$F4,$F4,$F1
	DATA BYTE $F1,$41,$41,$F1,$F4,$F4,$F4,$F1
	DATA BYTE $F1,$F4,$F4,$F4,$F4,$F4,$F4,$F4
	DATA BYTE $F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4
	DATA BYTE $F4,$F4,$F1,$41,$41,$F1,$F6,$F6
	DATA BYTE $F4,$F4,$F1,$41,$41,$F1,$F6,$F6
	DATA BYTE $F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4
	DATA BYTE $F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F6,$F6,$F6
	DATA BYTE $F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4
	DATA BYTE $F4,$F4,$F4,$F4,$F4,$F4,$F4,$F1
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F1,$41,$F1
	DATA BYTE $F6,$F6,$F6,$F6,$F6,$F1,$41,$F1
	DATA BYTE $F4,$F4,$F4,$F4,$F4,$F4,$F4,$F1
	DATA BYTE $F1,$F1,$FD,$FD,$FD,$FD,$F1,$D1
	DATA BYTE $F1,$F1,$FD,$FD,$FD,$FD,$F1,$D1
	DATA BYTE $11,$D1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $11,$D1,$F1,$F1,$F1,$F1,$F1,$F1
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$D1,$11
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$D1,$11
	DATA BYTE $11,$11,$11,$11,$F1,$F1,$F1,$F1
	DATA BYTE $11,$11,$11,$11,$F1,$F1,$F1,$F1
	DATA BYTE $11,$11,$11,$11,$11,$11,$11,$11
	DATA BYTE $11,$11,$11,$11,$11,$11,$11,$11
	DATA BYTE $11,$11,$11,$11,$11,$11,$11,$11
	DATA BYTE $11,$11,$11,$11,$11,$11,$11,$11
	DATA BYTE $F1,$11,$11,$11,$F1,$11,$11,$11
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$11,$11,$F1
	DATA BYTE $11,$11,$11,$11,$11,$11,$11,$11
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$11,$11
inflash_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $01,$FF,$FF,$FF,$01,$FF,$FF,$FF
	DATA BYTE $C9,$8D,$8B,$89,$C9,$FF,$FF,$18
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $18,$18,$FF,$7E,$3C,$18,$FF,$FF
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
beamshift_pat:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $FF,$FF,$FF,$E7,$E7,$FF,$FF,$FF
	DATA BYTE $00,$FF,$FF,$FF,$E7,$E7,$FF,$FF
	DATA BYTE $00,$00,$FF,$FF,$FF,$E7,$E7,$FF
	DATA BYTE $00,$00,$00,$FF,$FF,$FF,$E7,$E7
	DATA BYTE $00,$00,$00,$00,$FF,$FF,$FF,$E7
	DATA BYTE $00,$00,$00,$00,$00,$FF,$FF,$FF
	DATA BYTE $00,$00,$00,$00,$00,$00,$FF,$FF
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$FF
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $FF,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $FF,$FF,$00,$00,$00,$00,$00,$00
	DATA BYTE $FF,$FF,$FF,$00,$00,$00,$00,$00
	DATA BYTE $E7,$FF,$FF,$FF,$00,$00,$00,$00
	DATA BYTE $E7,$E7,$FF,$FF,$FF,$00,$00,$00
	DATA BYTE $FF,$E7,$E7,$FF,$FF,$FF,$00,$00
	DATA BYTE $FF,$FF,$E7,$E7,$FF,$FF,$FF,$00
beamshift_col:
	' Generated by assets/genfixtures.py (spring halves also genconveyors.py).
	DATA BYTE $41,$31,$31,$34,$34,$31,$31,$41
	DATA BYTE $11,$41,$31,$31,$34,$34,$31,$31
	DATA BYTE $11,$11,$41,$31,$31,$34,$34,$31
	DATA BYTE $11,$11,$11,$41,$31,$31,$34,$34
	DATA BYTE $11,$11,$11,$11,$41,$31,$31,$34
	DATA BYTE $11,$11,$11,$11,$11,$41,$31,$31
	DATA BYTE $11,$11,$11,$11,$11,$11,$41,$31
	DATA BYTE $11,$11,$11,$11,$11,$11,$11,$41
	DATA BYTE $11,$11,$11,$11,$11,$11,$11,$11
	DATA BYTE $41,$11,$11,$11,$11,$11,$11,$11
	DATA BYTE $31,$41,$11,$11,$11,$11,$11,$11
	DATA BYTE $31,$31,$41,$11,$11,$11,$11,$11
	DATA BYTE $34,$31,$31,$41,$11,$11,$11,$11
	DATA BYTE $34,$34,$31,$31,$41,$11,$11,$11
	DATA BYTE $31,$34,$34,$31,$31,$41,$11,$11
	DATA BYTE $31,$31,$34,$34,$31,$31,$41,$11
girder_dot_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $FF,$FF,$FF,$E7,$E7,$FF,$FF,$00
	DATA BYTE $FF,$FF,$FF,$E7,$E7,$FF,$FF,$FF
	DATA BYTE $FF,$FF,$FF,$E7,$E7,$FF,$FF,$FF
girder_dot_col:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $61,$41,$41,$41,$41,$41,$61,$11
	DATA BYTE $41,$31,$31,$34,$34,$31,$31,$41
	DATA BYTE $A1,$A1,$51,$51,$51,$51,$A1,$A1
girder_marks:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $00,$00,$00,$00,$01,$01,$00,$00
	DATA BYTE $00,$00,$00,$01,$01,$00,$00,$00
	DATA BYTE $00,$01,$01,$00,$00,$00,$00,$00
	DATA BYTE $01,$01,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$01,$01,$00,$00,$00
	DATA BYTE $01,$01,$00,$00,$01,$01,$00,$01
	DATA BYTE $01,$00,$00,$01,$01,$00,$00,$00
	DATA BYTE $01,$01,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$01,$01,$00,$00,$00
	DATA BYTE $01,$01,$00,$00,$00,$01,$01,$00
	DATA BYTE $00,$00,$01,$01,$00,$00,$00,$01
	DATA BYTE $01,$00,$00,$01,$01,$00,$00,$00
beamplain_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $00,$00,$FF,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $00,$00,$00,$FF,$FF,$FF,$FF,$FF
	DATA BYTE $00,$00,$00,$00,$FF,$FF,$FF,$FF
	DATA BYTE $00,$00,$00,$00,$00,$FF,$FF,$FF
	DATA BYTE $00,$00,$00,$00,$00,$00,$FF,$FF
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$FF
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $FF,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $FF,$FF,$00,$00,$00,$00,$00,$00
	DATA BYTE $FF,$FF,$FF,$00,$00,$00,$00,$00
	DATA BYTE $FF,$FF,$FF,$FF,$00,$00,$00,$00
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$00,$00,$00
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$00,$00
	DATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$00
brick_edge:
	' Generated by assets/genfixtures.py; edit the generator.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "....XXXXXXXX...."
	BITMAP "....X......X...."
	BITMAP "....X......X...."
	BITMAP "....X......X...."
	BITMAP "....X......X...."
	BITMAP "....X......X...."
	BITMAP "....X......X...."
	BITMAP "....XXXXXXXX...."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
credit_pat:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $00,$00,$68,$98,$88,$98,$68,$00
	DATA BYTE $08,$08,$68,$98,$88,$98,$68,$00
	DATA BYTE $00,$00,$B0,$C8,$88,$88,$88,$00
credit_col:
	' Generated by assets/genfixtures.py; edit the generator.
	DATA BYTE $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
banked_score_print:
	' Split five-point units into a five-digit quotient and a final 0 or 5.
	' Never multiply the full score into an overflowing 16-bit temporary.
	#sctens = #scvalue / 2
	' Keep the mask word-sized: TI's IF word-AND-byte can read the high byte.
	#scodd = #scvalue AND 1
	sclast = 0
	IF #scodd THEN sclast = 5
	IF #sctens THEN
		PRINT AT #scpos,<.5>#sctens,sclast
	ELSE
		PRINT AT #scpos,"     ",sclast
	END IF
	RETURN

banked_spring_transfer:
	IF springphase <> 1 THEN
		' Finish falling onto the cap before it takes Mack's weight.
		IF my < 160 THEN
			my = my + 2
			IF my > 160 THEN my = 160
			RETURN
		END IF
		GOSUB banked_tramp_press
		IF trtick = 8 THEN
			IF springphase = 0 THEN
				springphase = 1
			ELSE
				st = S_JUMP
				jix = 0
				spr2 = 1
				bmp1 = 0
				fcy = my
				jhz = 0
				IF springdir = 1 THEN jhz = 2
				mdir = springdir
			END IF
		END IF
		RETURN
	END IF
	springtick = springtick + 1
	IF springdir = 1 THEN
		mx = mx + 2
	ELSE
		mx = mx - 2
	END IF
	IF springtick <= 18 THEN
		my = my - 3
	ELSE
		my = my + 3
	END IF
	' A floor-to-floor spring transfer clears the centre. Falling off a
	' rotating panel commits Mack to the hazardous cabinet instead.
	IF springfatal THEN
		IF mx + 16 >= 112 THEN
			IF mx < 144 THEN
				IF my + 16 >= 152 THEN
					IF my < 184 THEN
						springhit = 1
						RETURN
					END IF
				END IF
			END IF
		END IF
	END IF
	IF springtick = 36 THEN
		springphase = 2
		springpad = 1 - springpad
		trtick = 0
	END IF
	RETURN

banked_tramp_press:
	' Both sites share the cap displacement, rider position and release sound.
	trtick = trtick + 1
	trpose = trtick
	IF trtick > 4 THEN trpose = 8 - trtick
	my = trby + trpose - 16
	IF trtick = 8 THEN
		#sndpitch = 300
		sndvol = 10
		sfxlen = 5
		GOSUB tone_start
	END IF
	RETURN

banked_tramp_step:
	IF trph = 0 THEN
		' Drop down the channel to the trampoline at the bottom -- EVERY
		' entry bounces off it (the top-floor entry no longer sinks
		' without a bounce; its spring target trgy is just the 1st floor).
		my = my + 2
		fy = my + 16
		IF fy >= trby THEN
			my = trby - 16
			trph = 3
			trtick = 0
		END IF
		RETURN
	END IF
	IF trph = 3 THEN
		GOSUB banked_tramp_press
		IF trtick = 8 THEN trph = 1
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
	' way he is going (left) so he doesn't moon-walk off the trampoline. If
	' that step leaves the floor, switch to falling instead of continuing to
	' subtract from the 8-bit x coordinate until it wraps offscreen.
	mdir = 0
	mx = mx - 1
	GOSUB foot_probe
	IF sup = 1 THEN st = S_WALK
	IF sup = 0 THEN
		' The trampoline exit may cross an unsupported gap while reaching
		' the floor, but must stop before byte-sized x can wrap offscreen.
		IF mx = 0 THEN
			st = S_FALL
			fcy = my
			fct = 0
			jhz = 1
		END IF
	END IF
	RETURN

banked_hud_score:
	#if TI994A
	' Leave a left margin, right-align six score digits, and reserve column 7
	' for the assisted-game marker. The title uses banked_score_left below.
	PRINT AT CPOS(0,1),"       "
	#scpos = 1
	GOSUB banked_score_print
	#else
	GOSUB banked_score_left
	#endif
	IF game838 THEN PRINT "*"
	RETURN

banked_score_left:
	' Clear trailing digits and the old marker, without indenting the number.
	PRINT AT #scpos,"       "
	#sctens = #scvalue / 2
	' Keep the mask word-sized: TI's IF word-AND-byte can read the high byte.
	#scodd = #scvalue AND 1
	sclast = 0
	IF #scodd THEN sclast = 5
	IF #sctens THEN
		PRINT AT #scpos,#sctens,sclast
	ELSE
		PRINT AT #scpos,sclast
	END IF
	RETURN

banked_title:
	' Gameplay fixtures borrow lowercase slots; preserve the existing credit.
	DEFINE CHAR 97,1,credit_pat
	DEFINE CHAR 100,1,VARPTR credit_pat(8)
	DEFINE CHAR 110,1,VARPTR credit_pat(16)
	DEFINE COLOR 97,1,credit_col
	DEFINE COLOR 100,1,credit_col
	DEFINE COLOR 110,1,credit_col
	GOSUB quiet_screen
	CLS
	DEFINE CHAR 128,83,title_pat
	DEFINE COLOR 128,83,title_col
	SCREEN title_map
	PRINT AT CPOS(0,2),"LAST SCORE"
	PRINT AT CPOS(0,20),"HIGH SCORE"
	#scvalue = #lastscore
	#scpos = 34
	GOSUB banked_score_left
	IF last838 THEN PRINT "*"
	#scvalue = #hi
	#scpos = 56
	GOSUB banked_score_print
	IF hi838 THEN PRINT AT CPOS(1,30),"*"
	PRINT AT CPOS(23,7),"PRESS FIRE TO START"
	PRINT AT CPOS(20,3),"STICK MOVE  UP/DOWN CLIMB"
	PRINT AT CPOS(21,2),"FIRE JUMP / HOLD DROP HAMMER"
	PRINT AT CPOS(18,5),"2026 UNHUMAN and C&C AI"
	SPRITE 0,111,40,0,15
	SPRITE 8,111,40,60,13
	SPRITE 1,111,56,24,7
title_release:
	WAIT
	IF cont1.button THEN GOTO title_release
	titleheld = cont1.key
	titlecode = 0
title_loop:
	WAIT
	IF cont1.button THEN RETURN
	GOSUB menu_key
	IF title_abort THEN RETURN
	IF setupkey < 10 THEN
		titlenext = 0
		IF setupkey = 8 THEN titlenext = 1
		IF titlecode = 1 THEN
			IF setupkey = 3 THEN titlenext = 2
		END IF
		IF titlecode = 2 THEN
			IF setupkey = 8 THEN GOTO setup838
		END IF
		titlecode = titlenext
	END IF
	GOTO title_loop

setup838:
	game838 = 1
	GOSUB quiet_screen
	CLS
	PRINT AT CPOS(8,10),"LIVES 1-9"
setup_lives:
	WAIT
	GOSUB menu_key
	IF title_abort THEN RETURN
	IF setupkey < 1 THEN GOTO setup_lives
	IF setupkey > 9 THEN GOTO setup_lives
	lives = setupkey - 1
	PRINT AT CPOS(8,20),setupkey
	PRINT AT CPOS(11,10),"LEVEL 1-6"
setup_level:
	WAIT
	GOSUB menu_key
	IF title_abort THEN RETURN
	IF setupkey < 1 THEN GOTO setup_level
	IF setupkey > 6 THEN GOTO setup_level
	levelno = setupkey
	lv = setupkey
	IF lv > 3 THEN lv = lv - 3
	PRINT AT CPOS(11,20),setupkey
	FOR setupwait = 1 TO 45
		WAIT
		GOSUB back_key
		IF backreq THEN
			title_abort = 1
			RETURN
		END IF
	NEXT setupwait
	RETURN

menu_key:
	GOSUB back_key
	IF backreq THEN
		title_abort = 1
		setupkey = 15
		RETURN
	END IF
	' A held digit is consumed once, including the final 8 and equal answers.
	setupkey = cont1.key
	IF setupkey = 15 THEN
		titleheld = 15
		RETURN
	END IF
	IF titleheld <> 15 THEN
		setupkey = 15
		RETURN
	END IF
	titleheld = setupkey
	RETURN

title_pat:
	' Generated by assets/gentitle.py; edit the generator.
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00,$C6,$C6,$C6,$C6,$C6,$C6,$E6,$D6
	DATA BYTE $00,$00,$DD,$00,$55,$AA,$55,$AA,$00,$00,$00,$00,$55,$AA,$55,$AA
	DATA BYTE $00,$00,$DD,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$80,$80
	DATA BYTE $CE,$C6,$C6,$C6,$C6,$C6,$C6,$C6,$11,$AA,$00,$88,$00,$00,$DD,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$DD,$00,$11,$AA,$00,$88,$00,$00,$00,$00
	DATA BYTE $55,$BB,$55,$EE,$55,$AA,$44,$AA,$00,$22,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$04,$04,$04,$04,$80,$80,$80,$90,$90,$10,$10,$10
	DATA BYTE $00,$00,$00,$00,$03,$03,$03,$03,$00,$00,$00,$00,$E0,$E0,$E0,$E0
	DATA BYTE $00,$00,$00,$00,$3E,$3E,$3E,$3E,$00,$00,$00,$00,$7F,$7F,$7F,$7F
	DATA BYTE $00,$00,$00,$00,$00,$00,$DD,$00,$00,$00,$00,$00,$01,$01,$01,$01
	DATA BYTE $07,$00,$00,$00,$00,$00,$DD,$00,$F0,$00,$00,$00,$00,$00,$DD,$00
	DATA BYTE $00,$00,$00,$00,$C1,$C1,$C1,$C1,$00,$00,$00,$00,$80,$80,$80,$80
	DATA BYTE $03,$03,$03,$03,$03,$03,$03,$03,$E0,$BB,$55,$EE,$55,$AA,$44,$AA
	DATA BYTE $00,$07,$07,$07,$07,$07,$44,$AA,$3E,$FE,$FE,$FE,$FE,$FE,$FE,$FE
	DATA BYTE $00,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$7F,$FC,$FC,$FC,$FC,$FC,$FC,$FC
	DATA BYTE $55,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$00,$F8,$F8,$F8,$F8,$F8,$F8,$F8
	DATA BYTE $01,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$55,$F0,$F0,$F0,$F0,$F0,$F0,$F0
	DATA BYTE $55,$00,$00,$00,$00,$00,$00,$00,$E0,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $55,$BB,$55,$EE,$55,$AA,$44,$AA,$C1,$C1,$C1,$C1,$C1,$C1,$FE,$FE
	DATA BYTE $55,$F0,$F0,$F0,$F0,$F0,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $03,$03,$03,$03,$03,$03,$03,$03,$00,$22,$00,$E0,$E0,$E0,$E0,$E0
	DATA BYTE $00,$22,$00,$F8,$F8,$F8,$F8,$F8,$FE,$FE,$FE,$3E,$3E,$3E,$3E,$3E
	DATA BYTE $0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$FC,$FC,$FC,$88,$00,$00,$00,$00
	DATA BYTE $1F,$1F,$1F,$88,$00,$00,$00,$00,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8
	DATA BYTE $3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
	DATA BYTE $00,$22,$00,$88,$00,$00,$00,$00,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
	DATA BYTE $03,$03,$03,$03,$03,$03,$03,$03,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
	DATA BYTE $3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F
	DATA BYTE $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F
	DATA BYTE $F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F
	DATA BYTE $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$55,$00,$55,$EE,$55,$AA,$55,$AA
	DATA BYTE $55,$00,$55,$EE,$55,$C1,$C1,$C1,$F0,$F0,$F0,$F0,$F0,$AA,$55,$AA
	DATA BYTE $00,$00,$00,$00,$00,$80,$80,$80,$03,$03,$03,$03,$03,$03,$03,$00
	DATA BYTE $E0,$E0,$E0,$E0,$E0,$E0,$E0,$00,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$00
	DATA BYTE $0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$FC,$FC,$FC,$FC,$FC,$FC,$FC,$00
	DATA BYTE $1F,$1F,$1F,$1F,$1F,$1F,$1F,$00,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$00
	DATA BYTE $3F,$3F,$01,$01,$01,$01,$01,$00,$F0,$F0,$00,$88,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$88,$00,$00,$00,$00,$00,$00,$E0,$E0,$E0,$E0,$E0,$00
	DATA BYTE $00,$AA,$00,$88,$00,$00,$00,$00,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$00
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$00,$00,$00,$00,$E7,$00,$00,$00,$00
	DATA BYTE $C6,$C6,$C6,$C6,$C6,$C6,$C6,$C6,$00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$E7,$E7,$00,$00,$00
title_col:
	' Generated by assets/gentitle.py; edit the generator.
	DATA BYTE $11,$EE,$11,$11,$11,$11,$11,$11,$41,$41,$41,$41,$41,$41,$41,$41
	DATA BYTE $FF,$FF,$FB,$FF,$FB,$FB,$FB,$FB,$11,$11,$11,$11,$FB,$FB,$FB,$FB
	DATA BYTE $FF,$FF,$FB,$FF,$11,$11,$11,$11,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $41,$41,$41,$41,$41,$41,$41,$41,$FB,$FB,$BB,$FB,$BB,$BB,$BA,$BB
	DATA BYTE $11,$11,$11,$11,$BB,$BB,$BA,$BB,$FB,$FB,$BB,$FB,$11,$11,$11,$11
	DATA BYTE $BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$AA,$BA,$AA,$AA,$11,$11,$11,$11
	DATA BYTE $11,$11,$11,$11,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $11,$11,$11,$11,$F1,$F1,$B1,$F1,$11,$11,$11,$11,$F1,$F1,$F1,$F1
	DATA BYTE $11,$11,$11,$11,$F1,$F1,$F1,$F1,$11,$11,$11,$11,$F1,$F1,$F1,$F1
	DATA BYTE $11,$11,$11,$11,$FF,$FF,$FB,$FF,$11,$11,$11,$11,$F1,$F1,$F1,$F1
	DATA BYTE $E1,$11,$11,$11,$FF,$FF,$FB,$FF,$E1,$11,$11,$11,$FF,$FF,$FB,$FF
	DATA BYTE $11,$11,$11,$11,$F1,$F1,$F1,$F1,$11,$11,$11,$11,$F1,$F1,$F1,$F1
	DATA BYTE $B1,$F1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$FB,$FB,$FB,$FB,$FB,$FB,$FB
	DATA BYTE $11,$F1,$F1,$F1,$F1,$B1,$FB,$FB,$B1,$F1,$B1,$F1,$B1,$F1,$B1,$F1
	DATA BYTE $11,$F1,$B1,$F1,$B1,$B1,$B1,$B1,$F1,$F1,$B1,$F1,$B1,$B1,$B1,$B1
	DATA BYTE $FB,$F1,$F1,$F1,$F1,$B1,$B1,$B1,$11,$F1,$B1,$F1,$B1,$F1,$B1,$F1
	DATA BYTE $F1,$F1,$B1,$F1,$B1,$B1,$B1,$B1,$FB,$F1,$B1,$F1,$B1,$B1,$B1,$B1
	DATA BYTE $FB,$11,$11,$11,$11,$11,$11,$11,$B1,$11,$11,$11,$11,$11,$11,$11
	DATA BYTE $FB,$FB,$FB,$FB,$FB,$FB,$FB,$FB,$F1,$F1,$F1,$F1,$F1,$B1,$B1,$F1
	DATA BYTE $FB,$F1,$B1,$F1,$B1,$B1,$11,$11,$B1,$11,$11,$11,$11,$11,$11,$11
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$BB,$FB,$BB,$B1,$B1,$B1,$B1,$B1
	DATA BYTE $BB,$FB,$BB,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$FB,$BB,$BB,$BB,$BB
	DATA BYTE $B1,$B1,$B1,$FB,$BB,$BB,$BB,$BB,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
	DATA BYTE $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
	DATA BYTE $BB,$FB,$BB,$FB,$BB,$BB,$BB,$BB,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
	DATA BYTE $A1,$B1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$B1,$A1,$B1,$A1,$B1,$A1,$B1
	DATA BYTE $A1,$B1,$A1,$B1,$A1,$B1,$A1,$B1,$A1,$B1,$A1,$B1,$A1,$A1,$A1,$A1
	DATA BYTE $A1,$B1,$A1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$B1,$A1,$B1,$A1
	DATA BYTE $A1,$B1,$A1,$B1,$A1,$B1,$A1,$B1,$A1,$B1,$A1,$B1,$A1,$A1,$A1,$A1
	DATA BYTE $A1,$B1,$A1,$B1,$A1,$A1,$A1,$A1,$BA,$BB,$BA,$BA,$BA,$BA,$BA,$BA
	DATA BYTE $BA,$BB,$BA,$BA,$BA,$A1,$B1,$A1,$A1,$B1,$A1,$B1,$A1,$BA,$BA,$BA
	DATA BYTE $11,$11,$11,$11,$11,$B1,$A1,$B1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$11
	DATA BYTE $A1,$B1,$A1,$A1,$A1,$A1,$A1,$11,$A1,$B1,$A1,$A1,$A1,$A1,$A1,$11
	DATA BYTE $A1,$A1,$A1,$A1,$A1,$A1,$A1,$11,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$11
	DATA BYTE $A1,$A1,$A1,$A1,$A1,$A1,$A1,$11,$A1,$B1,$A1,$A1,$A1,$A1,$A1,$11
	DATA BYTE $A1,$A1,$A1,$A1,$A1,$A1,$A1,$11,$A1,$A1,$AA,$BA,$AA,$AA,$AA,$11
	DATA BYTE $11,$11,$AA,$BA,$AA,$AA,$AA,$11,$11,$11,$A1,$A1,$A1,$A1,$A1,$11
	DATA BYTE $AA,$BA,$AA,$BA,$AA,$AA,$AA,$11,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$11
	DATA BYTE $A1,$B1,$A1,$B1,$A1,$A1,$A1,$11,$FF,$66,$66,$61,$66,$66,$11,$11
	DATA BYTE $41,$41,$41,$41,$41,$41,$41,$41,$FF,$BB,$AA,$AA,$AA,$AA,$44,$44
	DATA BYTE $FF,$BB,$AA,$A1,$A1,$AA,$44,$44
title_map:
	' Generated by assets/gentitle.py; edit the generator.
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$81,$82,$20,$82,$20,$83,$84,$83,$20,$82,$84,$83,$20,$82,$84
	DATA BYTE $83,$20,$85,$82,$20,$82,$20,$83,$84,$83,$20,$84,$82,$84,$81,$20
	DATA BYTE $20,$86,$87,$88,$87,$20,$87,$88,$87,$20,$87,$88,$89,$20,$87,$20
	DATA BYTE $87,$20,$85,$87,$88,$87,$20,$87,$88,$87,$20,$20,$87,$20,$86,$20
	DATA BYTE $20,$81,$8A,$20,$8A,$20,$8A,$20,$8A,$20,$8A,$20,$8A,$20,$8A,$20
	DATA BYTE $8A,$20,$85,$8A,$20,$8A,$20,$8A,$20,$8A,$20,$20,$8A,$20,$81,$20
	DATA BYTE $20,$86,$8B,$20,$8B,$20,$8B,$20,$8B,$20,$8B,$20,$8B,$20,$8B,$8B
	DATA BYTE $20,$8C,$8D,$8B,$20,$8B,$20,$8B,$20,$8B,$20,$20,$8B,$20,$86,$20
	DATA BYTE $20,$81,$20,$20,$20,$20,$20,$20,$8E,$8F,$20,$90,$20,$91,$92,$20
	DATA BYTE $93,$94,$95,$8F,$92,$96,$92,$97,$20,$20,$20,$20,$20,$20,$81,$20
	DATA BYTE $20,$86,$20,$20,$20,$20,$20,$20,$98,$99,$9A,$9B,$9C,$9D,$9E,$9F
	DATA BYTE $A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$20,$20,$20,$20,$20,$20,$86,$20
	DATA BYTE $20,$81,$20,$20,$20,$20,$20,$20,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF
	DATA BYTE $B0,$B1,$20,$20,$B2,$B3,$20,$20,$20,$20,$20,$20,$20,$20,$81,$20
	DATA BYTE $20,$86,$20,$20,$20,$20,$20,$20,$B4,$B5,$20,$B6,$B7,$B8,$B9,$BA
	DATA BYTE $BB,$BC,$20,$20,$BD,$BE,$BF,$C0,$20,$20,$20,$20,$20,$20,$86,$20
	DATA BYTE $20,$81,$20,$20,$20,$20,$20,$20,$C1,$C2,$20,$C3,$C4,$C5,$C6,$C7
	DATA BYTE $C8,$C9,$CA,$CB,$CC,$CD,$CC,$CE,$20,$20,$20,$20,$20,$20,$81,$20
	DATA BYTE $20,$86,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$CF,$CF,$20,$20,$20,$20,$86,$20
	DATA BYTE $20,$D0,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$CF,$CF,$CF,$20,$20,$20,$20,$D0,$20
	DATA BYTE $20,$20,$D1,$D1,$D2,$D2,$D1,$D1,$D1,$D1,$D1,$D2,$D2,$D1,$D1,$D1
	DATA BYTE $D1,$D2,$D2,$D1,$D1,$D1,$D1,$D1,$D2,$D2,$D1,$D1,$D1,$D1,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
	DATA BYTE $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
title_end:
	DATA BYTE 72,72,77,84,73,84,76,3

	#if TI994A
	BANK 4
	#endif

banked_mack_air_chars:
	DEFINE SPRITE 35,2,mack_jump_left
	RETURN
mack_jump_left:
	' Generated by assets/genfixtures.py; edit the generator.
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "......XXXX......"
	BITMAP "....XXXXXXX....."
	BITMAP "....XX.XX......."
	BITMAP "...X..XXX.....X."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "..XX........XX.."
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP "................"
	BITMAP ".........XX....."
	BITMAP ".........X......"
	BITMAP "...XX.XXXXXX.XX."
	BITMAP "....XXXXXXXXXX.."
	BITMAP ".....XXXXXX....."
	BITMAP "....XXXXXXXX...."
	BITMAP "...XXX....XXX..."
	BITMAP "..XXX......XXX.."
	BITMAP "................"
	BITMAP "................"
banked_lift_positions:
	' Direct slots avoid an indexed loop and four route calculations per pixel.
	#pnlookup = pnphase
	pnxcar(0) = PEEK(VARPTR lift_x(#pnlookup + 0))
	pnycar(0) = PEEK(VARPTR lift_y(#pnlookup + 0))
	pnxcar(1) = PEEK(VARPTR lift_x(#pnlookup + 56))
	pnycar(1) = PEEK(VARPTR lift_y(#pnlookup + 56))
	pnxcar(2) = PEEK(VARPTR lift_x(#pnlookup + 112))
	pnycar(2) = PEEK(VARPTR lift_y(#pnlookup + 112))
	pnxcar(3) = PEEK(VARPTR lift_x(#pnlookup + 168))
	pnycar(3) = PEEK(VARPTR lift_y(#pnlookup + 168))
	RETURN

lift_x:
	' Generated by assets/genmotion.py.
	DATA BYTE 104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104
	DATA BYTE 104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104
	DATA BYTE 104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104
	DATA BYTE 104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104
	DATA BYTE 104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104
	DATA BYTE 104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119
	DATA BYTE 120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135
	DATA BYTE 136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136
	DATA BYTE 136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136
	DATA BYTE 136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136
	DATA BYTE 136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136
	DATA BYTE 136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136
	DATA BYTE 136,135,134,133,132,131,130,129,128,127,126,125,124,123,122,121
	DATA BYTE 120,119,118,117,116,115,114,113,112,111,110,109,108,107,106,105
	DATA BYTE 104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104
	DATA BYTE 104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104
	DATA BYTE 104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104
	DATA BYTE 104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104
	DATA BYTE 104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104
	DATA BYTE 104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119
	DATA BYTE 120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135
	DATA BYTE 136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136
	DATA BYTE 136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136
	DATA BYTE 136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136
	DATA BYTE 136,136,136,136,136,136,136,136
lift_y:
	' Generated by assets/genmotion.py.
	DATA BYTE 64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79
	DATA BYTE 80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95
	DATA BYTE 96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111
	DATA BYTE 112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127
	DATA BYTE 128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143
	DATA BYTE 144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144
	DATA BYTE 144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144
	DATA BYTE 144,143,142,141,140,139,138,137,136,135,134,133,132,131,130,129
	DATA BYTE 128,127,126,125,124,123,122,121,120,119,118,117,116,115,114,113
	DATA BYTE 112,111,110,109,108,107,106,105,104,103,102,101,100,99,98,97
	DATA BYTE 96,95,94,93,92,91,90,89,88,87,86,85,84,83,82,81
	DATA BYTE 80,79,78,77,76,75,74,73,72,71,70,69,68,67,66,65
	DATA BYTE 64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64
	DATA BYTE 64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64
	DATA BYTE 64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79
	DATA BYTE 80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95
	DATA BYTE 96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111
	DATA BYTE 112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127
	DATA BYTE 128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143
	DATA BYTE 144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144
	DATA BYTE 144,144,144,144,144,144,144,144,144,144,144,144,144,144,144,144
	DATA BYTE 144,143,142,141,140,139,138,137,136,135,134,133,132,131,130,129
	DATA BYTE 128,127,126,125,124,123,122,121,120,119,118,117,116,115,114,113
	DATA BYTE 112,111,110,109,108,107,106,105,104,103,102,101,100,99,98,97
	DATA BYTE 96,95,94,93,92,91,90,89
animated_machines:
	IF lv = 2 THEN
		firecolor = (hzphase / 8) AND 3
		IF firelast = 255 THEN
			DEFINE VRAM 960,32,furnace_pat
			DEFINE VRAM 9152,32,furnace_col
			DEFINE VRAM 9184,32,VARPTR fire_col(firecolor * 32)
			firecolorlast = firecolor
		END IF
		IF firecolor <> firecolorlast THEN
			firecolorlast = firecolor
			DEFINE VRAM 9184,32,VARPTR fire_col(firecolor * 32)
		END IF
		IF firedepth <> firelast THEN
			firelast = firedepth
			DEFINE VRAM 992,32,VARPTR fire_pat(firedepth * 32)
		END IF
	END IF
	IF lv = 1 THEN
		IF st <> S_TRAMP THEN
			IF dclean = 0 THEN trpose = 0
		END IF
		IF trpose <> trlast THEN
			trlast = trpose
			DEFINE VRAM 5192,16,VARPTR tramp_pat(trpose * 16)
			DEFINE VRAM 13384,16,VARPTR tramp_col(trpose * 16)
		END IF
		RETURN
	END IF
	IF lv = 3 THEN
		GOSUB factory_springs_draw
		' One two-cell spark stream, advancing outward from the wall.
		sparkpose = (hzphase / 2) AND 7
		IF sparklast = 255 THEN DEFINE VRAM 11552,16,spark_col
		IF sparkpose <> sparklast THEN
			sparklast = sparkpose
			DEFINE VRAM 3360,16,VARPTR spark_pat(sparkpose * 16)
		END IF
		' The head reaches y=73, directly above the belt rail at y=74.
		pressfoot = 0
		IF pressy = 61 THEN pressfoot = 1
		IF pressy >= 62 THEN pressfoot = 2
		pressfoot = pressfoot * 8 + cvaf
		IF pressfoot <> pressfootlast THEN
			pressfootlast = pressfoot
			DEFINE VRAM 4040,16,VARPTR pressfoot_pat(pressfoot * 16)
			DEFINE VRAM 12232,16,VARPTR pressfoot_col((pressfoot / 8) * 16)
		END IF
		' The conveyor box is left of the piston, in its own character cell.
	END IF
	IF clawstep <> clawlast THEN
		clawlast = clawstep
		DEFINE VRAM 6000,40,VARPTR claw_pat(clawstep * 40)
	END IF
	IF pressy <> presslast THEN
		presslast = pressy
		presspose = pressy - 96
		IF lv = 3 THEN presspose = pressy - 32
		#presszone = 0
		IF lv = 2 THEN #presszone = 2048
		DEFINE VRAM #presszone + 1944,32,VARPTR press_pat(presspose * 48)
		DEFINE VRAM #presszone + 4024,16,VARPTR press_pat(presspose * 48 + 32)
		DEFINE VRAM #presszone + 10136,32,VARPTR press_col(presspose * 48)
		DEFINE VRAM #presszone + 12216,16,VARPTR press_col(presspose * 48 + 32)
	END IF
	RETURN

factory_springs_draw:
	IF dclean = 1 THEN RETURN
	trleft = 0
	trright = 0
	IF st = 7 THEN
		IF springpad = 0 THEN
			trleft = trpose
		ELSE
			trright = trpose
		END IF
	END IF
	IF trleft <> trlast THEN
		trlast = trleft
		DEFINE VRAM 5208,16,VARPTR tramp_pat(trleft * 16)
		DEFINE VRAM 13400,16,VARPTR tramp_col(trleft * 16)
	END IF
	IF trright <> trrightlast THEN
		trrightlast = trright
		DEFINE VRAM 5224,16,VARPTR tramp_pat(trright * 16)
		DEFINE VRAM 13416,16,VARPTR tramp_col(trright * 16)
	END IF
	RETURN

tramp_pat:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $7F,$7F,$02,$04,$02,$04,$1F,$1F
	DATA BYTE $FE,$FE,$40,$20,$40,$20,$F8,$F8
	DATA BYTE $00,$7F,$7F,$04,$02,$04,$1F,$1F
	DATA BYTE $00,$FE,$FE,$20,$40,$20,$F8,$F8
	DATA BYTE $00,$00,$7F,$7F,$02,$04,$1F,$1F
	DATA BYTE $00,$00,$FE,$FE,$40,$20,$F8,$F8
	DATA BYTE $00,$00,$00,$7F,$7F,$04,$1F,$1F
	DATA BYTE $00,$00,$00,$FE,$FE,$20,$F8,$F8
	DATA BYTE $00,$00,$00,$00,$7F,$7F,$1F,$1F
	DATA BYTE $00,$00,$00,$00,$FE,$FE,$F8,$F8
tramp_col:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $F1,$D1,$31,$D1,$31,$D1,$31,$31
	DATA BYTE $F1,$D1,$31,$D1,$31,$D1,$31,$31
	DATA BYTE $31,$F1,$D1,$D1,$31,$D1,$31,$31
	DATA BYTE $31,$F1,$D1,$D1,$31,$D1,$31,$31
	DATA BYTE $31,$D1,$F1,$D1,$31,$D1,$31,$31
	DATA BYTE $31,$D1,$F1,$D1,$31,$D1,$31,$31
	DATA BYTE $31,$D1,$31,$F1,$D1,$D1,$31,$31
	DATA BYTE $31,$D1,$31,$F1,$D1,$D1,$31,$31
	DATA BYTE $31,$D1,$31,$D1,$F1,$D1,$31,$31
	DATA BYTE $31,$D1,$31,$D1,$F1,$D1,$31,$31
pressfoot_pat:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$00,$FF,$C0,$C0,$C0,$FF,$00
	DATA BYTE $00,$00,$FF,$C0,$C0,$C0,$FF,$00
	DATA BYTE $00,$00,$FF,$60,$60,$60,$FF,$00
	DATA BYTE $00,$00,$FF,$60,$60,$60,$FF,$00
	DATA BYTE $00,$00,$FF,$30,$30,$30,$FF,$00
	DATA BYTE $00,$00,$FF,$30,$30,$30,$FF,$00
	DATA BYTE $00,$00,$FF,$18,$18,$18,$FF,$00
	DATA BYTE $00,$00,$FF,$18,$18,$18,$FF,$00
	DATA BYTE $00,$00,$FF,$0C,$0C,$0C,$FF,$00
	DATA BYTE $00,$00,$FF,$0C,$0C,$0C,$FF,$00
	DATA BYTE $00,$00,$FF,$06,$06,$06,$FF,$00
	DATA BYTE $00,$00,$FF,$06,$06,$06,$FF,$00
	DATA BYTE $00,$00,$FF,$03,$03,$03,$FF,$00
	DATA BYTE $00,$00,$FF,$03,$03,$03,$FF,$00
	DATA BYTE $00,$00,$FF,$81,$81,$81,$FF,$00
	DATA BYTE $00,$00,$FF,$81,$81,$81,$FF,$00
	DATA BYTE $7F,$00,$FF,$C0,$C0,$C0,$FF,$00
	DATA BYTE $FE,$00,$FF,$C0,$C0,$C0,$FF,$00
	DATA BYTE $7F,$00,$FF,$60,$60,$60,$FF,$00
	DATA BYTE $FE,$00,$FF,$60,$60,$60,$FF,$00
	DATA BYTE $7F,$00,$FF,$30,$30,$30,$FF,$00
	DATA BYTE $FE,$00,$FF,$30,$30,$30,$FF,$00
	DATA BYTE $7F,$00,$FF,$18,$18,$18,$FF,$00
	DATA BYTE $FE,$00,$FF,$18,$18,$18,$FF,$00
	DATA BYTE $7F,$00,$FF,$0C,$0C,$0C,$FF,$00
	DATA BYTE $FE,$00,$FF,$0C,$0C,$0C,$FF,$00
	DATA BYTE $7F,$00,$FF,$06,$06,$06,$FF,$00
	DATA BYTE $FE,$00,$FF,$06,$06,$06,$FF,$00
	DATA BYTE $7F,$00,$FF,$03,$03,$03,$FF,$00
	DATA BYTE $FE,$00,$FF,$03,$03,$03,$FF,$00
	DATA BYTE $7F,$00,$FF,$81,$81,$81,$FF,$00
	DATA BYTE $FE,$00,$FF,$81,$81,$81,$FF,$00
	DATA BYTE $7F,$7F,$FF,$C0,$C0,$C0,$FF,$00
	DATA BYTE $FE,$FE,$FF,$C0,$C0,$C0,$FF,$00
	DATA BYTE $7F,$7F,$FF,$60,$60,$60,$FF,$00
	DATA BYTE $FE,$FE,$FF,$60,$60,$60,$FF,$00
	DATA BYTE $7F,$7F,$FF,$30,$30,$30,$FF,$00
	DATA BYTE $FE,$FE,$FF,$30,$30,$30,$FF,$00
	DATA BYTE $7F,$7F,$FF,$18,$18,$18,$FF,$00
	DATA BYTE $FE,$FE,$FF,$18,$18,$18,$FF,$00
	DATA BYTE $7F,$7F,$FF,$0C,$0C,$0C,$FF,$00
	DATA BYTE $FE,$FE,$FF,$0C,$0C,$0C,$FF,$00
	DATA BYTE $7F,$7F,$FF,$06,$06,$06,$FF,$00
	DATA BYTE $FE,$FE,$FF,$06,$06,$06,$FF,$00
	DATA BYTE $7F,$7F,$FF,$03,$03,$03,$FF,$00
	DATA BYTE $FE,$FE,$FF,$03,$03,$03,$FF,$00
	DATA BYTE $7F,$7F,$FF,$81,$81,$81,$FF,$00
	DATA BYTE $FE,$FE,$FF,$81,$81,$81,$FF,$00
pressfoot_col:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $11,$11,$F1,$31,$31,$31,$F1,$11
	DATA BYTE $11,$11,$F1,$31,$31,$31,$F1,$11
	DATA BYTE $F1,$11,$F1,$31,$31,$31,$F1,$11
	DATA BYTE $F1,$11,$F1,$31,$31,$31,$F1,$11
	DATA BYTE $F1,$F1,$F1,$31,$31,$31,$F1,$11
	DATA BYTE $F1,$F1,$F1,$31,$31,$31,$F1,$11
claw_pat:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$00,$30,$30,$30,$F0,$F0,$F0
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$0C,$0C,$0C,$0F,$0F,$0F
	DATA BYTE $00,$00,$18,$18,$18,$78,$78,$78
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$18,$18,$18,$1E,$1E,$1E
	DATA BYTE $00,$00,$0C,$0C,$0C,$3C,$3C,$3C
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$30,$30,$30,$3C,$3C,$3C
	DATA BYTE $00,$00,$06,$06,$06,$1E,$1E,$1E
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$60,$60,$60,$78,$78,$78
	DATA BYTE $00,$00,$03,$03,$03,$0F,$0F,$0F
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$C0,$C0,$C0,$F0,$F0,$F0
	DATA BYTE $00,$00,$01,$01,$01,$07,$07,$07
	DATA BYTE $00,$00,$80,$80,$80,$80,$80,$80
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$01,$01,$01,$01,$01,$01
	DATA BYTE $00,$00,$80,$80,$80,$E0,$E0,$E0
	DATA BYTE $00,$00,$00,$00,$00,$03,$03,$03
	DATA BYTE $00,$00,$C0,$C0,$C0,$C0,$C0,$C0
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$03,$03,$03,$03,$03,$03
	DATA BYTE $00,$00,$00,$00,$00,$C0,$C0,$C0
	DATA BYTE $00,$00,$00,$00,$00,$01,$01,$01
	DATA BYTE $00,$00,$60,$60,$60,$E0,$E0,$E0
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$06,$06,$06,$07,$07,$07
	DATA BYTE $00,$00,$00,$00,$00,$80,$80,$80
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$30,$30,$30,$F0,$F0,$F0
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$0C,$0C,$0C,$0F,$0F,$0F
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$18,$18,$18,$78,$78,$78
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$18,$18,$18,$1E,$1E,$1E
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$0C,$0C,$0C,$3C,$3C,$3C
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$30,$30,$30,$3C,$3C,$3C
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$06,$06,$06,$1E,$1E,$1E
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$60,$60,$60,$78,$78,$78
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$03,$03,$03,$0F,$0F,$0F
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$C0,$C0,$C0,$F0,$F0,$F0
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$01,$01,$01,$07,$07,$07
	DATA BYTE $00,$00,$81,$81,$81,$81,$81,$81
	DATA BYTE $00,$00,$80,$80,$80,$E0,$E0,$E0
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$03,$03,$03
	DATA BYTE $00,$00,$C3,$C3,$C3,$C3,$C3,$C3
	DATA BYTE $00,$00,$00,$00,$00,$C0,$C0,$C0
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$01,$01,$01
	DATA BYTE $00,$00,$66,$66,$66,$E7,$E7,$E7
	DATA BYTE $00,$00,$00,$00,$00,$80,$80,$80
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$3C,$3C,$3C,$FF,$FF,$FF
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
press_pat:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $0F,$0F,$00,$00,$00,$00,$00,$00
	DATA BYTE $F0,$F0,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$00,$00,$00,$00,$00,$00
	DATA BYTE $F0,$F0,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$00,$00,$00,$00,$00,$00
	DATA BYTE $F0,$F0,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$00,$00,$00,$00,$00,$00
	DATA BYTE $F0,$F0,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$00,$00,$00,$00,$00,$00
	DATA BYTE $F0,$F0,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $7F,$0F,$00,$00,$00,$00,$00,$00
	DATA BYTE $FE,$F0,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $7F,$7F,$00,$00,$00,$00,$00,$00
	DATA BYTE $FE,$FE,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $6F,$7F,$7F,$00,$00,$00,$00,$00
	DATA BYTE $F6,$FE,$FE,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $7F,$6F,$7F,$7F,$00,$00,$00,$00
	DATA BYTE $FE,$F6,$FE,$FE,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $7F,$7F,$6F,$7F,$7F,$00,$00,$00
	DATA BYTE $FE,$FE,$F6,$FE,$FE,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$7F,$7F,$6F,$7F,$7F,$00,$00
	DATA BYTE $F0,$FE,$FE,$F6,$FE,$FE,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$7F,$7F,$6F,$7F,$7F,$00
	DATA BYTE $F0,$F0,$FE,$FE,$F6,$FE,$FE,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$7F,$7F,$6F,$7F,$7F
	DATA BYTE $F0,$F0,$80,$FE,$FE,$F6,$FE,$FE
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$7F,$7F,$6F,$7F
	DATA BYTE $F0,$F0,$80,$80,$FE,$FE,$F6,$FE
	DATA BYTE $7F,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $FE,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$7F,$7F,$6F
	DATA BYTE $F0,$F0,$80,$80,$80,$FE,$FE,$F6
	DATA BYTE $7F,$7F,$00,$00,$00,$00,$00,$00
	DATA BYTE $FE,$FE,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$7F,$7F
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$FE,$FE
	DATA BYTE $6F,$7F,$7F,$00,$00,$00,$00,$00
	DATA BYTE $F6,$FE,$FE,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$7F
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$FE
	DATA BYTE $7F,$6F,$7F,$7F,$00,$00,$00,$00
	DATA BYTE $FE,$F6,$FE,$FE,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $7F,$7F,$6F,$7F,$7F,$00,$00,$00
	DATA BYTE $FE,$FE,$F6,$FE,$FE,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$7F,$7F,$6F,$7F,$7F,$00,$00
	DATA BYTE $80,$FE,$FE,$F6,$FE,$FE,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$7F,$7F,$6F,$7F,$7F,$00
	DATA BYTE $80,$80,$FE,$FE,$F6,$FE,$FE,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$7F,$7F,$6F,$7F,$7F
	DATA BYTE $80,$80,$80,$FE,$FE,$F6,$FE,$FE
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$7F,$7F,$6F,$7F
	DATA BYTE $80,$80,$80,$80,$FE,$FE,$F6,$FE
	DATA BYTE $7F,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $FE,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$01,$7F,$7F,$6F
	DATA BYTE $80,$80,$80,$80,$80,$FE,$FE,$F6
	DATA BYTE $7F,$7F,$00,$00,$00,$00,$00,$00
	DATA BYTE $FE,$FE,$00,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$01,$01,$7F,$7F
	DATA BYTE $80,$80,$80,$80,$80,$80,$FE,$FE
	DATA BYTE $6F,$7F,$7F,$00,$00,$00,$00,$00
	DATA BYTE $F6,$FE,$FE,$00,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$01,$01,$01,$7F
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$FE
	DATA BYTE $7F,$6F,$7F,$7F,$00,$00,$00,$00
	DATA BYTE $FE,$F6,$FE,$FE,$00,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$01,$01,$01,$01
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$80
	DATA BYTE $7F,$7F,$6F,$7F,$7F,$00,$00,$00
	DATA BYTE $FE,$FE,$F6,$FE,$FE,$00,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$01,$01,$01,$01
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$7F,$7F,$6F,$7F,$7F,$00,$00
	DATA BYTE $80,$FE,$FE,$F6,$FE,$FE,$00,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$01,$01,$01,$01
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$7F,$7F,$6F,$7F,$7F,$00
	DATA BYTE $80,$80,$FE,$FE,$F6,$FE,$FE,$00
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$01,$01,$01,$01
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$7F,$7F,$6F,$7F,$7F
	DATA BYTE $80,$80,$80,$FE,$FE,$F6,$FE,$FE
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$01,$01,$01,$01
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$7F,$7F,$6F,$7F
	DATA BYTE $80,$80,$80,$80,$FE,$FE,$F6,$FE
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$01,$01,$01,$01
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$01,$7F,$7F,$6F
	DATA BYTE $80,$80,$80,$80,$80,$FE,$FE,$F6
	DATA BYTE $0F,$0F,$01,$01,$01,$01,$01,$01
	DATA BYTE $F0,$F0,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$01,$01,$01,$01
	DATA BYTE $80,$80,$80,$80,$80,$80,$80,$80
	DATA BYTE $01,$01,$01,$01,$01,$01,$7F,$7F
	DATA BYTE $80,$80,$80,$80,$80,$80,$FE,$FE
press_col:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$F1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$F1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$F1,$F1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$F1,$F1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$E1,$F1,$F1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$E1,$F1,$F1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$F1,$E1,$F1,$F1,$E1,$E1,$E1
	DATA BYTE $F1,$F1,$E1,$F1,$F1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$F1,$F1,$E1,$F1,$F1,$E1,$E1
	DATA BYTE $E1,$F1,$F1,$E1,$F1,$F1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$F1,$F1,$E1,$F1,$F1,$E1
	DATA BYTE $E1,$E1,$F1,$F1,$E1,$F1,$F1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$F1,$F1,$E1,$F1,$F1
	DATA BYTE $E1,$E1,$E1,$F1,$F1,$E1,$F1,$F1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$F1,$F1,$E1,$F1
	DATA BYTE $E1,$E1,$E1,$E1,$F1,$F1,$E1,$F1
	DATA BYTE $F1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$F1,$F1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$F1,$F1,$E1
	DATA BYTE $F1,$F1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$F1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$F1,$F1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$F1,$F1
	DATA BYTE $E1,$F1,$F1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$F1,$F1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$F1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$F1
	DATA BYTE $F1,$E1,$F1,$F1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$E1,$F1,$F1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$F1,$E1,$F1,$F1,$E1,$E1,$E1
	DATA BYTE $F1,$F1,$E1,$F1,$F1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$F1,$F1,$E1,$F1,$F1,$E1,$E1
	DATA BYTE $E1,$F1,$F1,$E1,$F1,$F1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$F1,$F1,$E1,$F1,$F1,$E1
	DATA BYTE $E1,$E1,$F1,$F1,$E1,$F1,$F1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$F1,$F1,$E1,$F1,$F1
	DATA BYTE $E1,$E1,$E1,$F1,$F1,$E1,$F1,$F1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$F1,$F1,$E1,$F1
	DATA BYTE $E1,$E1,$E1,$E1,$F1,$F1,$E1,$F1
	DATA BYTE $F1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$F1,$F1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$F1,$F1,$E1
	DATA BYTE $F1,$F1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$F1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$F1,$F1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$F1,$F1
	DATA BYTE $E1,$F1,$F1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$F1,$F1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$F1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$F1
	DATA BYTE $F1,$E1,$F1,$F1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$E1,$F1,$F1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $F1,$F1,$E1,$F1,$F1,$E1,$E1,$E1
	DATA BYTE $F1,$F1,$E1,$F1,$F1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$F1,$F1,$E1,$F1,$F1,$E1,$E1
	DATA BYTE $E1,$F1,$F1,$E1,$F1,$F1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$F1,$F1,$E1,$F1,$F1,$E1
	DATA BYTE $E1,$E1,$F1,$F1,$E1,$F1,$F1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$F1,$F1,$E1,$F1,$F1
	DATA BYTE $E1,$E1,$E1,$F1,$F1,$E1,$F1,$F1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$F1,$F1,$E1,$F1
	DATA BYTE $E1,$E1,$E1,$E1,$F1,$F1,$E1,$F1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$F1,$F1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$F1,$F1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$F1,$F1
	DATA BYTE $E1,$E1,$E1,$E1,$E1,$E1,$F1,$F1
furnace_pat:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $1C,$1C,$7F,$40,$5F,$50,$DF,$C0
	DATA BYTE $38,$38,$FE,$02,$FA,$0A,$FA,$02
	DATA BYTE $40,$5F,$40,$5C,$5C,$40,$7F,$00
	DATA BYTE $02,$FA,$02,$3A,$3A,$02,$FE,$00
furnace_col:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $31,$31,$D1,$FD,$FD,$F1,$FD,$FD
	DATA BYTE $31,$31,$D1,$FD,$FD,$F1,$FD,$FD
	DATA BYTE $FD,$FD,$FD,$FD,$FD,$FD,$D1,$41
	DATA BYTE $FD,$FD,$FD,$FD,$FD,$FD,$D1,$41
spark_pat:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $C0,$C0,$80,$F1,$F0,$80,$C0,$C0
	DATA BYTE $00,$00,$00,$80,$00,$0C,$00,$00
	DATA BYTE $C0,$C0,$8C,$F0,$F0,$80,$C0,$C0
	DATA BYTE $00,$00,$00,$60,$00,$00,$03,$00
	DATA BYTE $C0,$C0,$83,$F0,$F0,$80,$C0,$C0
	DATA BYTE $00,$00,$00,$18,$00,$00,$00,$00
	DATA BYTE $C0,$C0,$80,$F0,$F0,$80,$C0,$C0
	DATA BYTE $00,$00,$C0,$06,$00,$00,$00,$00
	DATA BYTE $C0,$C0,$80,$F0,$FC,$80,$C0,$C0
	DATA BYTE $00,$30,$00,$01,$00,$00,$00,$00
	DATA BYTE $C0,$C0,$80,$F0,$F3,$80,$C0,$C0
	DATA BYTE $00,$0C,$00,$00,$00,$00,$00,$00
	DATA BYTE $C0,$C0,$80,$F8,$F0,$80,$C0,$C0
	DATA BYTE $03,$00,$00,$00,$C0,$00,$00,$00
	DATA BYTE $C0,$C0,$80,$F6,$F0,$80,$C0,$C0
	DATA BYTE $00,$00,$00,$00,$00,$30,$00,$00
spark_col:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $E1,$91,$B1,$F1,$F1,$B1,$91,$E1
	DATA BYTE $E1,$91,$B1,$F1,$F1,$B1,$91,$E1
fire_pat:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$01,$01,$01,$01
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$02,$03,$03,$03
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$04,$05,$07,$07,$06
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$08,$08,$0E,$0E,$0F,$0D
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$10,$10,$1C,$1D,$1D,$1F,$1F
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $20,$20,$38,$38,$3A,$3F,$3F,$37
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$40
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $40,$70,$70,$74,$7D,$7F,$7F,$7E
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $00,$00,$00,$00,$00,$00,$80,$80
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$00
	DATA BYTE $E0,$E0,$E8,$F8,$FE,$FE,$FF,$DD
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$01
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$C0
	DATA BYTE $01,$01,$01,$01,$01,$01,$01,$01
	DATA BYTE $C0,$D0,$F0,$FC,$FD,$FD,$FF,$FF
	DATA BYTE $00,$00,$00,$00,$00,$00,$02,$02
	DATA BYTE $00,$00,$00,$00,$00,$00,$80,$80
	DATA BYTE $03,$03,$03,$03,$03,$03,$03,$00
	DATA BYTE $A0,$E0,$F8,$F8,$FA,$FF,$FF,$77
	DATA BYTE $00,$00,$00,$00,$00,$00,$04,$07
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$40
	DATA BYTE $07,$07,$07,$07,$07,$07,$04,$00
	DATA BYTE $C0,$F0,$F0,$F4,$FD,$FF,$FF,$FE
	DATA BYTE $00,$00,$00,$00,$00,$08,$0A,$0E
	DATA BYTE $00,$00,$00,$00,$00,$00,$80,$80
	DATA BYTE $0E,$0F,$0F,$0F,$0F,$0D,$01,$01
	DATA BYTE $E0,$E0,$E8,$F8,$FE,$FE,$FF,$DD
	DATA BYTE $00,$00,$00,$00,$00,$00,$1C,$1D
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$C0
	DATA BYTE $1F,$1F,$1F,$1F,$1F,$03,$03,$01
	DATA BYTE $C0,$D0,$F0,$FC,$FD,$FD,$FF,$FF
	DATA BYTE $00,$00,$00,$00,$00,$28,$2A,$3A
	DATA BYTE $00,$00,$00,$00,$00,$00,$80,$80
	DATA BYTE $3F,$3F,$3F,$3F,$07,$07,$07,$00
	DATA BYTE $A0,$E0,$F8,$F8,$FA,$FF,$FF,$77
	DATA BYTE $00,$00,$00,$00,$00,$00,$74,$7F
	DATA BYTE $00,$00,$00,$00,$00,$00,$00,$40
	DATA BYTE $7F,$7F,$7F,$0F,$0F,$0F,$04,$00
	DATA BYTE $C0,$F0,$F0,$F4,$FD,$FF,$FF,$FE
	DATA BYTE $00,$00,$00,$00,$00,$A8,$AA,$EE
	DATA BYTE $00,$00,$00,$00,$00,$00,$80,$80
	DATA BYTE $FE,$FF,$1F,$1F,$1F,$0D,$01,$01
	DATA BYTE $E0,$E0,$E8,$F8,$FE,$FE,$FF,$DD
fire_col:
	' Generated by assets/genconveyors.py; edit the generator.
	DATA BYTE $71,$71,$91,$91,$A1,$C1,$A1,$91
	DATA BYTE $71,$91,$91,$A1,$C1,$F1,$A1,$91
	DATA BYTE $71,$71,$91,$91,$A1,$C1,$A1,$91
	DATA BYTE $71,$91,$91,$A1,$C1,$F1,$A1,$91
	DATA BYTE $71,$91,$91,$A1,$B1,$C1,$A1,$91
	DATA BYTE $91,$91,$A1,$B1,$C1,$F1,$B1,$A1
	DATA BYTE $71,$91,$91,$A1,$B1,$C1,$A1,$91
	DATA BYTE $91,$91,$A1,$B1,$C1,$F1,$B1,$A1
	DATA BYTE $71,$91,$A1,$B1,$C1,$A1,$91,$71
	DATA BYTE $91,$A1,$B1,$C1,$F1,$C1,$A1,$91
	DATA BYTE $71,$91,$A1,$B1,$C1,$A1,$91,$71
	DATA BYTE $91,$A1,$B1,$C1,$F1,$C1,$A1,$91
	DATA BYTE $71,$71,$91,$A1,$C1,$F1,$A1,$91
	DATA BYTE $71,$91,$A1,$C1,$F1,$C1,$A1,$91
	DATA BYTE $71,$71,$91,$A1,$C1,$F1,$A1,$91
	DATA BYTE $71,$91,$A1,$C1,$F1,$C1,$A1,$91
motion_end:
	DATA BYTE 72,72,77,77,79,84,78,4
