	' ============================================================
	' ASTIROIDS — CVBasic, TI-99/4A cartridge ROM
	' cvbasic --ti994a src/ASTIROIDS.bas build/ASTIROIDS.a99
	' ============================================================

	' Enable 2x sprite magnification: VDP R1 = >E3 (SI=1=16x16 + MAG=1), so
	' sprites render as 32x32 (center offset 16). VDP()= is CVBasic's portable
	' register write -- works on both TI-99 (--ti994a) and ColecoVision (default
	' target), so this stays target-agnostic (was TMS9900-only inline ASM).
	VDP(1) = $E3

	BORDER 1
	' CVBasic's built-in flicker rotates ALL 32 sprites (the ship too). We want
	' the ship pinned as top priority, so turn it OFF (VDP then honors slot order:
	' ship=slot 0 is always drawn) and run our OWN flicker on just the asteroid
	' pool by rotating their slot assignments each frame (see render / astrot).
	SPRITE FLICKER OFF

	' Sprite pattern definitions (see DESIGN.md sprite-table)
	DEFINE SPRITE 0,16,ship_sprites
	DEFINE SPRITE 16,2,thrust_sprites
	DEFINE SPRITE 18,1,bullet_sprite
	DEFINE SPRITE 19,3,ast_large_sprites
	DEFINE SPRITE 22,2,ast_medium_sprites
	DEFINE SPRITE 24,1,ast_small_sprite
	DEFINE SPRITE 25,1,ufo_large_sprite
	DEFINE SPRITE 26,1,ufo_small_sprite
	DEFINE SPRITE 27,4,explosion_sprites
	DEFINE SPRITE 31,1,extra_life_sprite

	DEFINE CHAR 128,1,ship_icon_char
	DEFINE COLOR 128,1,ship_icon_color

	' 16-bit arrays (positions x64, velocities)
	' NOTE: CVBasic DIM x(N) allocates N elements 0..N-1. Add 1 so max index N is in bounds.
	DIM #ax(25),#ay(25),#avx(25),#avy(25)
	DIM #bx(5),#by(5),#bvx(5),#bvy(5)
	DIM #sin_t(16),#cos_t(16),#bvl_t(16),#bvs_t(16)
	DIM #fdx_t(16),#fdy_t(16)

	' 8-bit arrays
	DIM asiz(25),aact(25),afr(25),aft(25)
	DIM bact(5),blife(5)
	DIM acolor(4)

	' sin/cos x64, clockwise, angle 0 = ship pointing UP
	#sin_t(0)=0   : #sin_t(1)=25  : #sin_t(2)=45  : #sin_t(3)=57
	#sin_t(4)=64  : #sin_t(5)=57  : #sin_t(6)=45  : #sin_t(7)=25
	#sin_t(8)=0   : #sin_t(9)=-25 : #sin_t(10)=-45: #sin_t(11)=-57
	#sin_t(12)=-64: #sin_t(13)=-57: #sin_t(14)=-45: #sin_t(15)=-25
	#cos_t(0)=64  : #cos_t(1)=57  : #cos_t(2)=45  : #cos_t(3)=25
	#cos_t(4)=0   : #cos_t(5)=-25 : #cos_t(6)=-45 : #cos_t(7)=-57
	#cos_t(8)=-64 : #cos_t(9)=-57 : #cos_t(10)=-45: #cos_t(11)=-25
	#cos_t(12)=0  : #cos_t(13)=25 : #cos_t(14)=45 : #cos_t(15)=57

	' UFO-bullet velocity tables (signed, whole px/frame), one per saucer size:
	' large peaks at 5, small at 7 (small shoots faster). Position is in whole
	' pixels; NEVER derive these as #sin_t*N/64 at runtime -- CVBasic's 16-bit
	' divide is UNSIGNED, so a negative component becomes a huge positive.
	#bvl_t(0)=0  : #bvl_t(1)=2  : #bvl_t(2)=4  : #bvl_t(3)=4
	#bvl_t(4)=5  : #bvl_t(5)=4  : #bvl_t(6)=4  : #bvl_t(7)=2
	#bvl_t(8)=0  : #bvl_t(9)=-2 : #bvl_t(10)=-4: #bvl_t(11)=-4
	#bvl_t(12)=-5: #bvl_t(13)=-4: #bvl_t(14)=-4: #bvl_t(15)=-2
	#bvs_t(0)=0  : #bvs_t(1)=3  : #bvs_t(2)=5  : #bvs_t(3)=6
	#bvs_t(4)=7  : #bvs_t(5)=6  : #bvs_t(6)=5  : #bvs_t(7)=3
	#bvs_t(8)=0  : #bvs_t(9)=-3 : #bvs_t(10)=-5: #bvs_t(11)=-6
	#bvs_t(12)=-7: #bvs_t(13)=-6: #bvs_t(14)=-5: #bvs_t(15)=-3

	' Thrust-flame offset from the ship center (px), per rotation frame, placing
	' the flame just behind that frame's actual rear edge (engine) and on the
	' ship's axis. Precomputed from the art (tools/flame_offsets.py); re-run it if
	' the ship art changes. A single distance can't work: the pivot-to-tail gap
	' varies per frame, so a fixed offset floats on some frames and embeds on
	' others.
	#fdx_t(0)=1  : #fdx_t(1)=-6 : #fdx_t(2)=-7 : #fdx_t(3)=-9
	#fdx_t(4)=-8 : #fdx_t(5)=-9 : #fdx_t(6)=-7 : #fdx_t(7)=-6
	#fdx_t(8)=-1 : #fdx_t(9)=6  : #fdx_t(10)=7 : #fdx_t(11)=9
	#fdx_t(12)=8 : #fdx_t(13)=9 : #fdx_t(14)=7 : #fdx_t(15)=6
	#fdy_t(0)=8  : #fdy_t(1)=9  : #fdy_t(2)=7  : #fdy_t(3)=6
	#fdy_t(4)=1  : #fdy_t(5)=-6 : #fdy_t(6)=-7 : #fdy_t(7)=-9
	#fdy_t(8)=-8 : #fdy_t(9)=-9 : #fdy_t(10)=-7: #fdy_t(11)=-6
	#fdy_t(12)=-1: #fdy_t(13)=6 : #fdy_t(14)=7 : #fdy_t(15)=9

	acolor(1)=6 : acolor(2)=11 : acolor(3)=15

	' Score + session high score (persist across games; shown on the title).
	#score=0 : #hiscore=0
	' Sound engine state (see sfx_t): noise channel free, thrust not playing.
	noi_t=0 : thr_was=0 : award=1
	' Stall-watchdog clocks and the start-of-game settings (overridden by the
	' 838 setup screen; default to 3 ships / level 1).
	#wage=0 : #nokill=0 : start_lives=3 : start_wave=1

	GOTO title

	' ============================================================
	' TITLE SCREEN
	' ============================================================
title:
	GOSUB scr_clear
	' Score + high score at the top, exactly like the in-game HUD.
	GOSUB hud_draw
	' Centered layout. Control labels padded to 6 chars so the colons line up.
	PRINT AT 3*32+5,"* * * ASTIROIDS * * *"
	PRINT AT 9*32+6,"ROTATE : LEFT/RIGHT"
	PRINT AT 10*32+6,"THRUST : UP"
	PRINT AT 11*32+6,"FIRE   : BUTTON"
	PRINT AT 12*32+6,"HYPER  : DOWN"
	PRINT AT 15*32+10,"2026 UNHUMAN"
	PRINT AT 23*32+6,"PRESS FIRE TO BEGIN"
	hbeat_rate=120 : hbeat_timer=120 : hbeat_step=0
	' The title screen is silent: kill every channel + mixer state and don't
	' tick the heartbeat/sfx mixer in the loop below.
	GOSUB snd_off
	' Default start settings; the 8-3-8 code (below) opens the setup screen.
	start_lives=3 : start_wave=1 : code_st=0 : lastk=15
	ship_st=3 : utype=0 : ubact=0 : uexp=0 : thr_on=0
	FOR ti=1 TO 4
		bact(ti)=0
	NEXT ti
	FOR ti=0 TO 31
		SPRITE ti,$d1,0,0,0
	NEXT ti
	' A field of asteroids drifting randomly behind the text.
	FOR ti=1 TO 24
		aact(ti)=0
	NEXT ti
	ast_count=6
	FOR ti=1 TO 6
		aact(ti)=1
		asiz(ti)=random(3)+1
		#ax(ti)=random(14336)+1024
		#ay(ti)=random(10240)+1024
		IF random(2) THEN #avx(ti)=random(128)+24 ELSE #avx(ti)=-(random(128)+24)
		IF random(2) THEN #avy(ti)=random(128)+24 ELSE #avy(ti)=-(random(128)+24)
		IF asiz(ti)=1 THEN afr(ti)=76
		IF asiz(ti)=2 THEN afr(ti)=88
		IF asiz(ti)=3 THEN afr(ti)=96
		aft(ti)=random(15)
	NEXT ti
title_loop:
	WAIT
	GOSUB upd_ast
	GOSUB render
	' Secret setup: type 8,3,8 on the keyboard (CONT1.KEY: digit=value,
	' 15=none). Debounced on key-down so a held key registers once.
	k=cont1.key
	IF k<>15 THEN
		IF k<>lastk THEN
			IF k=8 THEN
				IF code_st=2 THEN GOTO setup838
				code_st=1
			ELSE
				IF k=3 AND code_st=1 THEN
					code_st=2
				ELSE
					code_st=0
				END IF
			END IF
		END IF
	END IF
	lastk=k
	IF cont1.button THEN GOTO game_init
	GOTO title_loop

	' ============================================================
	' 838 SETUP SCREEN (silent): pick ships + starting level
	' ============================================================
setup838:
	GOSUB snd_off
	GOSUB scr_clear
	ship_st=3 : utype=0 : ubact=0 : uexp=0 : thr_on=0
	set_lives=3 : set_wave=1 : field=0 : lastk=15 : btn_rel=0
	PRINT AT 3*32+11,"838 SETUP"
	PRINT AT 7*32+9,"SHIPS:"
	PRINT AT 9*32+9,"LEVEL:"
	PRINT AT 13*32+8,"NUMBER KEYS"
	PRINT AT 14*32+8,"SET 1-9"
	PRINT AT 17*32+6,"PRESS FIRE TO BEGIN"
	GOSUB setup_draw
	' Debounce: the '8' that opened this screen may still be held. Wait for all
	' keys to be released before reading input, or that 8 is eaten as the ship
	' count. (The asteroid field keeps drifting while we wait.)
setup_drain:
	WAIT
	GOSUB upd_ast
	GOSUB render
	IF cont1.key<>15 THEN GOTO setup_drain
	lastk=15
setup_loop:
	WAIT
	GOSUB upd_ast
	GOSUB render
	' First number key sets SHIPS (cursor moves to LEVEL); the next sets LEVEL.
	k=cont1.key
	IF k<>15 THEN
		IF k<>lastk THEN
			IF k>=1 THEN
				IF k<=9 THEN
					IF field=0 THEN
						set_lives=k : field=1
					ELSE
						set_wave=k
					END IF
					GOSUB setup_draw
				END IF
			END IF
		END IF
	END IF
	lastk=k
	' Require FIRE to be released once so a held button can't auto-start.
	IF cont1.button=0 THEN btn_rel=1
	IF cont1.button THEN
		IF btn_rel THEN
			start_lives=set_lives : start_wave=set_wave
			GOTO game_init
		END IF
	END IF
	GOTO setup_loop

	' ============================================================
	' GAME INIT
	' ============================================================
game_init:
	GOSUB scr_clear
	' Note: #hiscore is NOT reset here -- it persists across games this session.
	' lives/wave come from start_lives/start_wave (set to 3/1 normally, or by
	' the 838 setup screen). Clamp to the supported 1..9 range.
	lives=start_lives : wave=start_wave : #score=0 : last_extra=0
	IF wave<1 THEN wave=1
	IF wave>9 THEN wave=9
	IF lives<1 THEN lives=1
	IF lives>9 THEN lives=9
	FOR ti=0 TO 31
		SPRITE ti,$d1,0,0,0
	NEXT ti
	utype=0 : #utimer=450 : ubact=0 : uexp=0
	thr_on=0 : uw_ph=0 : rot_cd=0 : wave_gap=0 : #wage=0 : #nokill=0
	FOR ti=1 TO 4
		bact(ti)=0
	NEXT ti
	FOR ti=1 TO 24
		aact(ti)=0
	NEXT ti
	ast_count=0
	GOSUB hud_draw

new_wave:
	FOR ti=1 TO 24
		aact(ti)=0
	NEXT ti
	ast_count=0
	GOSUB spawn_wave
	GOSUB ready_scr

	' ============================================================
	' MAIN LOOP
	' ============================================================
main_loop:
	#pacef = FRAME
	WHILE 1
		WAIT
		' Frame-pace to 20Hz (3 VDP frames per step) -- measured, not guessed: an
		' on-screen loop counter showed the TI-99 naturally runs this loop at 20fps
		' (the heavy per-frame sprite work spills past two 60Hz frames), while
		' ColecoVision (faster Z80) held a solid 60fps -- 3x too fast uncapped.
		' Capping both to 20Hz makes Coleco match the TI's real speed exactly.
		IF (FRAME - #pacef) < 3 THEN WAIT
		#pacef = FRAME
		GOSUB handle_in
		GOSUB upd_ship
		GOSUB upd_bull
		GOSUB upd_ast
		GOSUB upd_ufo
		GOSUB chk_coll
		GOSUB ship_tick
		GOSUB xlife_chk
		GOSUB hbeat
		GOSUB sfx_t
		GOSUB render
		IF ast_count=0 THEN
			IF wave_gap>0 THEN
				' Free-flight gap: the ship is NOT reset, so the player can
				' fly toward the middle before the next wave's rocks appear.
				wave_gap=wave_gap-1
				IF wave_gap=0 THEN
					wave=wave+1
					IF wave>9 THEN wave=9
					SOUND 0,,0 : SOUND 1,,0 : SOUND 2,,0 : SOUND 3,,0
					sfx0=0 : sfx1=0 : sfx2=0 : noi_t=0 : thr_was=0
					#utimer=450 : utype=0 : ubact=0 : uexp=0
					FOR ti=1 TO 4
						bact(ti)=0
					NEXT ti
					FOR ti=1 TO 24
						aact(ti)=0
					NEXT ti
					ast_count=0
					GOSUB spawn_wave
					GOSUB hud_draw
				END IF
			ELSE
				' Wave just cleared (only start the gap if the ship is alive)
				IF ship_st<2 THEN wave_gap=150
			END IF
		END IF
	WEND

	' ============================================================
	' CLEAR SCREEN
	' ============================================================
scr_clear: PROCEDURE
	FOR ti=0 TO 23
		PRINT AT ti*32,"                                "
	NEXT ti
END

	' ============================================================
	' SPAWN WAVE
	' ============================================================
spawn_wave: PROCEDURE
	' New wave -> reset the stall watchdog clocks (see upd_ufo).
	#wage=0 : #nokill=0
	num_lg=wave+2
	IF num_lg>6 THEN num_lg=6
	slot=1
	FOR si=1 TO num_lg
		WHILE aact(slot)<>0
			slot=slot+1
			IF slot>24 THEN slot=1
		WEND
		aact(slot)=1
		asiz(slot)=1
		ast_count=ast_count+1
		' Spawn at visible-zone edges (spx/spy 16..239/191) so no render-guard pop-in
		IF si AND 1 THEN
			' Left or right screen edge (spx=16 or 239)
			IF si AND 2 THEN #ax(slot)=1024 ELSE #ax(slot)=15296
			#ay(slot)=random(11264)+1024
		ELSE
			' Top or bottom screen edge (spy=16 or 191)
			#ax(slot)=random(14336)+1024
			IF si AND 2 THEN #ay(slot)=1024 ELSE #ay(slot)=12224
		END IF
		' Speed: 64=1px/fr base, +12 per wave, cap 160
		spd=64+wave*12
		IF spd>160 THEN spd=160
		IF random(2) THEN
			#avx(slot)=random(spd)+64
		ELSE
			#avx(slot)=-(random(spd)+64)
		END IF
		IF random(2) THEN
			#avy(slot)=random(spd)+64
		ELSE
			#avy(slot)=-(random(spd)+64)
		END IF
		afr(slot)=76
		aft(slot)=random(15)
		slot=slot+1
		IF slot>24 THEN slot=1
	NEXT si
END

	' ============================================================
	' READY SCREEN
	' ============================================================
ready_scr: PROCEDURE
	' Clear any leftover sprites (e.g. an exploding-ship ghost from the
	' previous game/life) so only the fresh asteroids show under GET READY.
	FOR ti=0 TO 31
		SPRITE ti,$d1,0,0,0
	NEXT ti
	ship_st=3 : thr_on=0 : ubact=0
	GOSUB lives_draw
	GOSUB render
	PRINT AT 11*32+11,"GET READY"
	FOR ti=1 TO 120
		WAIT : GOSUB hbeat : GOSUB sfx_t
	NEXT ti
	PRINT AT 11*32+11,"         "
	#spx=8192 : #spy=6144
	#svx=0 : #svy=0
	sangle=0 : ship_st=1 : ship_tmr=90
	thr_on=0 : thr_frame=64 : fire_cd=0 : rot_cd=0
	GOSUB lives_draw
	GOSUB render
END

	' ============================================================
	' INPUT HANDLER
	' ============================================================
handle_in: PROCEDURE
	IF ship_st<2 THEN
		' Rotation: alternate 2/3 frames per step (avg 2.5 = ~25% slower)
		IF rot_cd>0 THEN rot_cd=rot_cd-1
		IF rot_cd=0 THEN
			IF cont1.left THEN
				sangle=(sangle+15) AND 15
				rot_cd=2 : IF rot_alt THEN rot_cd=3
				rot_alt=rot_alt XOR 1
			END IF
			IF cont1.right THEN
				sangle=(sangle+1) AND 15
				rot_cd=2 : IF rot_alt THEN rot_cd=3
				rot_alt=rot_alt XOR 1
			END IF
		END IF
		' Thrust: accumulate velocity; released = inertial drift
		thr_on=0
		IF cont1.up THEN
			thr_on=1
			' Slower ramp = apply full thrust every OTHER frame. Do NOT divide
			' the signed sin/cos by 2: CVBasic's 16-bit divide is UNSIGNED and
			' turns a negative component into a huge positive (wrong heading).
			thr_acc=thr_acc XOR 1
			IF thr_acc THEN
				#svx=#svx+#sin_t(sangle)
				#svy=#svy-#cos_t(sangle)
				' Speed cap: +/-294 (~15% above the previous 256). Unsigned
				' compares -> split at 32767 to use each correct half-range.
				IF #svx>32767 THEN
					IF #svx<-294 THEN #svx=-294
				ELSE
					IF #svx>294 THEN #svx=294
				END IF
				IF #svy>32767 THEN
					IF #svy<-294 THEN #svy=-294
				ELSE
					IF #svy>294 THEN #svy=294
				END IF
			END IF
		END IF
		' Hyperspace (debounced so a held DOWN can't spam-teleport)
		IF hyp_cd>0 THEN hyp_cd=hyp_cd-1
		IF cont1.down THEN
			IF hyp_cd=0 THEN
				#spx=random(13312)+1536
				#spy=random(10240)+1024
				#svx=0 : #svy=0
				' No invincibility after a jump: you reappear live and
				' vulnerable (classic hyperspace risk).
				ship_st=0
				hyp_cd=45
			END IF
		END IF
		' Fire: bullet spawns at ship nose (~6 px ahead of center)
		IF fire_cd>0 THEN fire_cd=fire_cd-1
		IF cont1.button THEN
			IF fire_cd=0 THEN
				fi=1
				WHILE fi<=4
					IF bact(fi)=0 THEN
						bact(fi)=1
						' ~8 px/frame * 20 = ~160 px before expiring (20% shorter)
						blife(fi)=20
						' Art nose at row 4 of 16x16 frame; at 2x magnification
						' that's 8px above center.  Spawn 9px out to clear hull.
						#bx(fi)=#spx+9*#sin_t(sangle)
						#by(fi)=#spy-9*#cos_t(sangle)
						' Bullet ~8 px/frame in the facing direction PLUS the
						' ship's current velocity (inertia): forward shots are
						' faster, shots fired backward while moving are slower.
						#bvx(fi)=#sin_t(sangle)*8+#svx
						#bvy(fi)=-#cos_t(sangle)*8+#svy
						fire_cd=12
						' "Pew" = fast descending zap on channel 1.
						#f1=1400 : #d1=-180 : v1=13 : sfx1=7
						fi=5
					END IF
					fi=fi+1
				WEND
			END IF
		END IF
	END IF
END

	' ============================================================
	' UPDATE SHIP (signed-safe wrap: x in 0..16383, y in 0..12287)
	' ============================================================
upd_ship: PROCEDURE
	IF ship_st<2 THEN
		#spx=#spx+#svx
		#spy=#spy+#svy
		' Wrap the ship so its 32px sprite box is ALWAYS fully on-screen and
		' POPS to the opposite edge (no straddle / gradual slide-in). The ship
		' art is anchored toward the cell's top-left (sprites.bas, shifted -2,-2)
		' and rendered at offset 11 (pivot at cell 5.5 = box 11), so the hardware
		' sprite coord (center-11) stays >=0 at the top/left edges -- no negative
		' coord, no VDP vertical dead zone -- and the empty box margin hangs off
		' the harmless bottom-right. Center kept in X 11..245 (#spx 704..15680,
		' band 14976) and Y 11..181 (#spy 704..11584, band 10880); the nose then
		' grazes screen y=0 at the top and y=192 at the bottom.
		IF #spx>=32768 THEN
			#spx=#spx+14976
		ELSE
			IF #spx<704 THEN
				#spx=#spx+14976
			ELSE
				IF #spx>=15680 THEN #spx=#spx-14976
			END IF
		END IF
		IF #spy>=32768 THEN
			#spy=#spy+10880
		ELSE
			IF #spy<704 THEN
				#spy=#spy+10880
			ELSE
				IF #spy>=11584 THEN #spy=#spy-10880
			END IF
		END IF
	END IF
END

	' ============================================================
	' UPDATE BULLETS
	' ============================================================
upd_bull: PROCEDURE
	FOR bi=1 TO 4
		IF bact(bi) THEN
			#bx(bi)=#bx(bi)+#bvx(bi)
			#by(bi)=#by(bi)+#bvy(bi)
			' Signed-safe wrap (see upd_ship): unsigned >= catches both ends.
			IF #bx(bi)>=32768 THEN
				#bx(bi)=#bx(bi)+16384
			ELSE
				IF #bx(bi)>=16384 THEN #bx(bi)=#bx(bi)-16384
			END IF
			IF #by(bi)>=32768 THEN
				#by(bi)=#by(bi)+12288
			ELSE
				IF #by(bi)>=12288 THEN #by(bi)=#by(bi)-12288
			END IF
			blife(bi)=blife(bi)-1
			IF blife(bi)=0 THEN bact(bi)=0
		END IF
	NEXT bi
END

	' ============================================================
	' UPDATE ASTEROIDS
	' ============================================================
upd_ast: PROCEDURE
	FOR ai=1 TO 24
		IF aact(ai)=2 THEN
			aft(ai)=aft(ai)-1
			IF aft(ai)=0 THEN
				aact(ai)=0
			ELSE
				afr(ai)=(27+(20-aft(ai))/5)*4
				IF afr(ai)>120 THEN afr(ai)=120
			END IF
		END IF
		IF aact(ai)=1 THEN
			#ax(ai)=#ax(ai)+#avx(ai)
			#ay(ai)=#ay(ai)+#avy(ai)
			' Signed-safe wrap (see upd_ship): unsigned >= catches both ends.
			IF #ax(ai)>=32768 THEN
				#ax(ai)=#ax(ai)+16384
			ELSE
				IF #ax(ai)>=16384 THEN #ax(ai)=#ax(ai)-16384
			END IF
			IF #ay(ai)>=32768 THEN
				#ay(ai)=#ay(ai)+12288
			ELSE
				IF #ay(ai)>=12288 THEN #ay(ai)=#ay(ai)-12288
			END IF
			aft(ai)=aft(ai)+1
			IF aft(ai)>=12 THEN
				aft(ai)=0
				IF asiz(ai)=1 THEN
					afr(ai)=afr(ai)+4
					IF afr(ai)>84 THEN afr(ai)=76
				END IF
				IF asiz(ai)=2 THEN
					afr(ai)=afr(ai)+4
					IF afr(ai)>92 THEN afr(ai)=88
				END IF
			END IF
		END IF
	NEXT ai
END

	' ============================================================
	' UPDATE UFO
	' ============================================================
upd_ufo: PROCEDURE
	' Stall watchdog clocks (capped well under the 32768 unsigned boundary):
	' #wage = frames since this wave started, #nokill = frames since a rock
	' was last destroyed. Both pull the next saucer in sooner (see below).
	IF #wage<30000 THEN #wage=#wage+1
	IF #nokill<30000 THEN #nokill=#nokill+1
	' Exploding: cycle explosion frames 27-30 in place, then clear the UFO.
	IF uexp>0 THEN
		uexp=uexp-1
		uefr=(27+(20-uexp)/5)*4
		IF uefr>120 THEN uefr=120
		IF uexp=0 THEN utype=0 : SPRITE 6,$d1,0,0,0 : SOUND 2,,0 : sfx2=0
	ELSE
	IF utype=0 THEN
		IF #utimer>0 THEN
			' Count down faster while the player is stalling: no rock destroyed
			' for ~7 s, or the wave uncleared for ~30 s -> saucers ~4x sooner.
			udec=1
			IF #nokill>420 THEN udec=4
			IF #wage>1800 THEN udec=4
			IF #utimer>udec THEN #utimer=#utimer-udec ELSE #utimer=0
		ELSE
			IF wave<4 THEN
				utype=1
			ELSE
				IF random(10)<4 THEN utype=2 ELSE utype=1
			END IF
			' Small saucers move faster across the screen than large ones.
			IF random(2)=0 THEN udir=1 ELSE udir=-1
			IF utype=2 THEN uspd=3 ELSE uspd=2
			IF udir=1 THEN ux=16 : uvx=uspd ELSE ux=239 : uvx=0-uspd
			uy=random(160)+20
			uvy=0 : ufire=14 : uwarble=0 : ubact=0
			IF wave<4 THEN #utimer=900 ELSE #utimer=600
		END IF
	ELSE
		ux=ux+uvx
		uwarble=uwarble+1
		' Small saucers change heading more often and by more (jumpier).
		IF utype=2 THEN uwthr=12 ELSE uwthr=20
		IF uwarble>=uwthr THEN
			uwarble=0
			IF uy<36 THEN uvy=1
			IF uy>170 THEN uvy=-1
			IF utype=2 THEN
				uvy=random(5)-2
			ELSE
				IF random(4)=0 THEN uvy=random(3)-1
			END IF
		END IF
		uy=uy+uvy
		IF uy<16 THEN uy=16
		IF uy>191 THEN uy=191
		' Despawn after crossing the screen. ux is 8-bit, so the old
		' <0 / >255 tests never fired -> the UFO never left and blocked
		' every later spawn. Check the edge it is heading toward instead.
		IF uvx>0 THEN
			IF ux>=240 THEN utype=0 : ubact=0 : SPRITE 6,$d1,0,0,0 : SPRITE 7,$d1,0,0,0
		ELSE
			IF ux<=16 THEN utype=0 : ubact=0 : SPRITE 6,$d1,0,0,0 : SPRITE 7,$d1,0,0,0
		END IF
		IF utype>0 THEN
			' One bullet at a time: only reload once the previous shot has cleared
			' (ubact=0), so each bullet flies its FULL life across the screen
			' instead of being reset mid-flight (which cut it short). ufire is the
			' post-clear reload delay, not a fixed refire cadence.
			IF ubact=0 THEN
				ufire=ufire-1
				IF ufire=0 THEN
					' Large aims at the ship 20% of the time, small 40%; else random.
					ubact=1 : ublife=40 : ubx=ux : uby=uy
					IF utype=1 THEN aimpct=2 ELSE aimpct=4
					IF random(10)<aimpct THEN
						#dx=#spx/64-ux : #dy=#spy/64-uy
						GOSUB ufo_aim
					ELSE
						aim_ang=random(16)
					END IF
					' Velocity from the per-size speed table (small shoots faster).
					IF utype=1 THEN
						ubvx=#bvl_t(aim_ang) : ubvy=0-#bvl_t((aim_ang+4) AND 15)
					ELSE
						ubvx=#bvs_t(aim_ang) : ubvy=0-#bvs_t((aim_ang+4) AND 15)
					END IF
					IF utype=1 THEN ufire=6 ELSE ufire=4
					' UFO shot "pew" (small saucer = higher pitch), over the hum.
					IF utype=1 THEN
						#f2=700 : #d2=-110 : v2=13 : sfx2=5
					ELSE
						#f2=1600 : #d2=-220 : v2=13 : sfx2=5
					END IF
				END IF
			END IF
			IF ubact=1 THEN
				ubx=ubx+ubvx : uby=uby+ubvy
				' Wrap around the screen instead of dying at the edges. ubx is
				' 8-bit so X wraps at 256 (= screen width) for free; wrap uby
				' into 0..191: after a small step (up to +/-7) a value >=224
				' underflowed past the top, else 192..198 ran off the bottom.
				IF uby>=224 THEN
					uby=uby-64
				ELSE
					IF uby>=192 THEN uby=uby-192
				END IF
				ublife=ublife-1
				IF ublife=0 THEN ubact=0
			END IF
		END IF
	END IF
	END IF
END

ufo_aim: PROCEDURE
	' Target vector (ship - ufo) arrives in #dx,#dy as signed 16-bit pixels.
	' Reduce its magnitude SIGN-SAFELY (halving, not unsigned divide) so the
	' per-angle dot products below can't overflow 16 bits.
	#adx=#dx : IF #adx>=32768 THEN #adx=0-#adx
	#ady=#dy : IF #ady>=32768 THEN #ady=0-#ady
	WHILE #adx>63 OR #ady>63
		#adx=#adx/2 : #ady=#ady/2
	WEND
	IF #dx>=32768 THEN #dx=0-#adx ELSE #dx=#adx
	IF #dy>=32768 THEN #dy=0-#ady ELSE #dy=#ady
	' Pick the 16-step heading whose unit vector best matches (dx,-dy).
	' +16384 keeps every dot product positive so the unsigned > behaves
	' like a signed compare (all CVBasic compares are unsigned).
	best_a=0 : #best_d=0
	FOR aa=0 TO 15
		#td=#dx*#sin_t(aa)-#dy*#cos_t(aa)+16384
		IF #td>#best_d THEN #best_d=#td : best_a=aa
	NEXT aa
	' Return only the heading; the caller sets velocity from the per-size table.
	aim_ang=best_a
END

	' ============================================================
	' COLLISION DETECTION
	' ============================================================
chk_coll: PROCEDURE
	' Bullet vs asteroids.
	' Deltas computed in 16-bit (#) so ABS sees a signed value. In 8-bit,
	' bpx-apx underflows when bpx<apx and ABS can't recover it (collision
	' would only fire in one quadrant).
	FOR bi=1 TO 4
		IF bact(bi) THEN
			#bpx=#bx(bi)/64 : #bpy=#by(bi)/64
			FOR ai=1 TO 24
				IF aact(ai)=1 THEN
					' bullet half=3 + asteroid half(12/8/5) = combined threshold
					IF asiz(ai)=1 THEN hradius=15
					IF asiz(ai)=2 THEN hradius=11
					IF asiz(ai)=3 THEN hradius=8
					#cdx=#bpx-#ax(ai)/64
					#cdy=#bpy-#ay(ai)/64
					IF ABS(#cdx)<hradius THEN
						IF ABS(#cdy)<hradius THEN
							bact(bi)=0
							award=1 : GOSUB ast_hit
							' One bullet hits one thing: stop scanning so it
							' can't also strike the just-spawned child pieces.
							ai=25
						END IF
					END IF
				END IF
			NEXT ai
		END IF
	NEXT bi
	' Bullet vs UFO (not while it's already exploding)
	IF utype>0 THEN
	IF uexp=0 THEN
		FOR bi=1 TO 4
			IF bact(bi) THEN
				#cdx=#bx(bi)/64-ux
				#cdy=#by(bi)/64-uy
				IF ABS(#cdx)<12 THEN
					IF ABS(#cdy)<8 THEN
						bact(bi)=0
						IF utype=1 THEN #score=#score+20 ELSE #score=#score+100
						GOSUB hud_draw
						' Start the UFO explosion (cleared in upd_ufo).
						uexp=20 : uefr=108 : ubact=0
						SPRITE 7,$d1,0,0,0
						' Explosion: descending thump + noise burst.
						#f0=420 : #d0=-9 : v0=12 : sfx0=24
						noi_n=4 : noi_v=14 : noi_t=18 : noi_dv=1
						bi=5
					END IF
				END IF
			END IF
		NEXT bi
	END IF
	END IF
	' UFO bullet can shatter asteroids too (no points to the player).
	IF ubact=1 THEN
		ai=1
		WHILE ai<=24
			IF aact(ai)=1 THEN
				IF asiz(ai)=1 THEN hradius=15
				IF asiz(ai)=2 THEN hradius=11
				IF asiz(ai)=3 THEN hradius=8
				#cdx=ubx-#ax(ai)/64
				#cdy=uby-#ay(ai)/64
				IF ABS(#cdx)<hradius THEN
					IF ABS(#cdy)<hradius THEN
						ubact=0 : SPRITE 7,$d1,0,0,0
						award=0 : GOSUB ast_hit
						ai=25
					END IF
				END IF
			END IF
			ai=ai+1
		WEND
	END IF
	' UFO can crash into an asteroid: both destroyed, no player points.
	IF utype>0 THEN
	IF uexp=0 THEN
		ai=1
		WHILE ai<=24
			IF aact(ai)=1 THEN
				IF asiz(ai)=1 THEN sradius=18
				IF asiz(ai)=2 THEN sradius=14
				IF asiz(ai)=3 THEN sradius=11
				#cdx=ux-#ax(ai)/64
				#cdy=uy-#ay(ai)/64
				IF ABS(#cdx)<sradius THEN
					IF ABS(#cdy)<sradius THEN
						uexp=20 : uefr=108 : ubact=0
						SPRITE 7,$d1,0,0,0
						#f0=420 : #d0=-9 : v0=12 : sfx0=24
						noi_n=4 : noi_v=13 : noi_t=16 : noi_dv=1
						award=0 : GOSUB ast_hit
						ai=25
					END IF
				END IF
			END IF
			ai=ai+1
		WEND
	END IF
	END IF
	' Ship-vs-* only when the ship is live and vulnerable (ship_st=0).
	' Bullet collisions above always run, incl. during spawn invincibility.
	IF ship_st=0 THEN
		' Ship vs asteroids: ship half(7) + asteroid half(12/8/5)
		ai=1
		WHILE ai<=24
			IF aact(ai)=1 THEN
				IF asiz(ai)=1 THEN sradius=19
				IF asiz(ai)=2 THEN sradius=15
				IF asiz(ai)=3 THEN sradius=12
				#cdx=#spx/64-#ax(ai)/64
				#cdy=#spy/64-#ay(ai)/64
				IF ABS(#cdx)<sradius THEN
					IF ABS(#cdy)<sradius THEN
						award=1 : GOSUB ast_hit
						GOSUB ship_die
						ai=25
					END IF
				END IF
			END IF
			ai=ai+1
		WEND
		' Ship vs UFO bullet
		IF ubact=1 THEN
			#cdx=#spx/64-ubx
			#cdy=#spy/64-uby
			IF ABS(#cdx)<8 THEN
				IF ABS(#cdy)<8 THEN GOSUB ship_die
			END IF
		END IF
		' Ship vs UFO body: you can crash into the saucer (both destroyed).
		IF utype>0 THEN
		IF uexp=0 THEN
			#cdx=#spx/64-ux
			#cdy=#spy/64-uy
			' Kill-box trimmed to the narrower large-UFO art (skirt now 10px
			' wide) so you don't die ~2px before visually touching the saucer.
			IF ABS(#cdx)<12 THEN
				IF ABS(#cdy)<12 THEN
					uexp=20 : uefr=108 : ubact=0
					SPRITE 7,$d1,0,0,0
					GOSUB ship_die
				END IF
			END IF
		END IF
		END IF
	END IF
END

	' ============================================================
	' ASTEROID HIT (global ai = pool index)
	' ============================================================
ast_hit: PROCEDURE
	' A rock just died -> reset the "no kill" stall clock (see upd_ufo).
	#nokill=0
	' award=0 when something other than the player's shot breaks the rock
	' (UFO shot/crash), so no points are credited.
	IF award THEN
		IF asiz(ai)=1 THEN #score=#score+2
		IF asiz(ai)=2 THEN #score=#score+5
		IF asiz(ai)=3 THEN #score=#score+10
		GOSUB hud_draw
	END IF
	' Explosion = white-noise burst (channel 3) with a fast volume decay,
	' louder/longer for bigger rocks (see sfx_t for the envelope).
	IF asiz(ai)=1 THEN noi_n=4 : noi_v=14 : noi_t=16 : noi_dv=1
	IF asiz(ai)=2 THEN noi_n=4 : noi_v=12 : noi_t=12 : noi_dv=1
	IF asiz(ai)=3 THEN noi_n=4 : noi_v=9  : noi_t=8  : noi_dv=1
	ast_count=ast_count-1
	old_siz=asiz(ai)
	aact(ai)=2 : afr(ai)=108 : aft(ai)=20
	IF old_siz<3 THEN
		kids=0
		FOR ci=1 TO 24
			IF aact(ci)=0 THEN
				kids=kids+1
				aact(ci)=1
				asiz(ci)=old_siz+1
				ast_count=ast_count+1
				#ax(ci)=#ax(ai) : #ay(ci)=#ay(ai)
				IF old_siz=1 THEN ckick=96 ELSE ckick=128
				IF kids=1 THEN
					#avx(ci)=#avx(ai)+ckick : #avy(ci)=#avy(ai)-ckick/2
				ELSE
					#avx(ci)=#avx(ai)-ckick : #avy(ci)=#avy(ai)+ckick/2
				END IF
				' Signed cap (same split-at-32767 fix as thrust cap)
				IF #avx(ci)>32767 THEN
					IF #avx(ci)<-256 THEN #avx(ci)=-256
				ELSE
					IF #avx(ci)>256 THEN #avx(ci)=256
				END IF
				IF #avy(ci)>32767 THEN
					IF #avy(ci)<-256 THEN #avy(ci)=-256
				ELSE
					IF #avy(ci)>256 THEN #avy(ci)=256
				END IF
				IF asiz(ci)=2 THEN afr(ci)=88 ELSE afr(ci)=96
				aft(ci)=0
				IF kids=2 THEN ci=25
			END IF
		NEXT ci
	END IF
END

	' ============================================================
	' SHIP DIE
	' ============================================================
ship_die: PROCEDURE
	ship_st=2 : ship_tmr=60
	#svx=0 : #svy=0
	' Stop thrusting: handle_in won't run while dead (ship_st>=2), so without
	' this thr_on stays 1 and the channel-3 hiss resumes once the death-explosion
	' noise fades. Clearing it lets the thrust branch silence the channel instead.
	thr_on=0
	' Consume a ship now (at death) so the HUD reserve count is correct
	' through the explosion; game-over is decided when the explosion ends.
	lives=lives-1
	GOSUB lives_draw
	' Death = long descending tone (ch0) over a big noise rumble (ch3).
	#f0=500 : #d0=-11 : v0=13 : sfx0=44
	noi_n=4 : noi_v=15 : noi_t=24 : noi_dv=1
END

	' ============================================================
	' SHIP STATE TICK
	' ============================================================
ship_tick: PROCEDURE
	IF ship_st=1 THEN
		ship_tmr=ship_tmr-1
		IF ship_tmr=0 THEN ship_st=0
	END IF
	IF ship_st=2 THEN
		ship_tmr=ship_tmr-1
		IF ship_tmr=0 THEN
			' Explosion finished: kill any lingering death/explosion sound so
			' nothing keeps playing through the respawn/reset.
			GOSUB snd_off
			' lives already decremented in ship_die
			IF lives=0 THEN
				GOSUB game_over
			ELSE
				ship_st=3 : ship_tmr=90
			END IF
		END IF
	END IF
	IF ship_st=3 THEN
		ship_tmr=ship_tmr-1
		IF ship_tmr=0 THEN
			#spx=8192 : #spy=6144
			#svx=0 : #svy=0
			sangle=0 : ship_st=1 : ship_tmr=90
			GOSUB lives_draw
		END IF
	END IF
END

	' ============================================================
	' EXTRA LIFE CHECK
	' ============================================================
xlife_chk: PROCEDURE
	IF #score/1000>last_extra THEN
		last_extra=last_extra+1
		lives=lives+1
		' Rising chime on channel 0.
		#f0=600 : #d0=40 : v0=12 : sfx0=12
		GOSUB lives_draw
	END IF
END

	' ============================================================
	' HEARTBEAT (tempo driven by asteroid count)
	' ============================================================
hbeat: PROCEDURE
	' Silent during the ship-death explosion so it doesn't fight that sound.
	IF ship_st<>2 THEN
		IF hbeat_timer>0 THEN
			hbeat_timer=hbeat_timer-1
		ELSE
			IF hbeat_step=0 THEN
				#f0=1100 : #d0=0 : v0=8 : sfx0=8
				hbeat_step=1
			ELSE
				#f0=860 : #d0=0 : v0=8 : sfx0=8
				hbeat_step=0
			END IF
			hbeat_rate=120-ast_count*4
			IF hbeat_rate<30 THEN hbeat_rate=30
			hbeat_timer=hbeat_rate
		END IF
	END IF
END

	' ============================================================
	' SFX TICK
	' ============================================================
	' ============================================================
	' SILENCE EVERYTHING (channels + all mixer state)
	' ============================================================
snd_off: PROCEDURE
	SOUND 0,,0 : SOUND 1,,0 : SOUND 2,,0 : SOUND 3,,0
	sfx0=0 : sfx1=0 : sfx2=0 : noi_t=0 : thr_was=0
END

	' Each tone channel (0,1,2) plays a frequency-sweep envelope: #fN is the
	' current frequency, #dN the per-frame step (0 = steady tone), vN the
	' volume, sfxN the frames left. Channel 3 (noise) plays explosion bursts
	' with a volume decay, and hisses the thrust rocket when otherwise free.
	' Sweep clamp note: CVBasic compares are UNSIGNED, so a descending sweep
	' that underflows past 0 wraps to ~65000 -- catch that (>=32768) FIRST and
	' pin to the 90 Hz floor before the ordinary range checks.
sfx_t: PROCEDURE
	IF sfx0>0 THEN
		#f0=#f0+#d0
		IF #f0>=32768 THEN #f0=90
		IF #f0>8000 THEN #f0=8000
		IF #f0<90 THEN #f0=90
		sfx0=sfx0-1
		IF sfx0=0 THEN SOUND 0,,0 ELSE SOUND 0,#f0,v0
	END IF
	IF sfx1>0 THEN
		#f1=#f1+#d1
		IF #f1>=32768 THEN #f1=90
		IF #f1>8000 THEN #f1=8000
		IF #f1<90 THEN #f1=90
		sfx1=sfx1-1
		IF sfx1=0 THEN SOUND 1,,0 ELSE SOUND 1,#f1,v1
	END IF
	IF sfx2>0 THEN
		#f2=#f2+#d2
		IF #f2>=32768 THEN #f2=90
		IF #f2>8000 THEN #f2=8000
		IF #f2<90 THEN #f2=90
		sfx2=sfx2-1
		IF sfx2=0 THEN SOUND 2,,0 ELSE SOUND 2,#f2,v2
	END IF
	' Channel 3: explosions own it (with a fading volume); thrust uses it when
	' free. noi_v underflow past 0 wraps high in 8-bit -> guard with >15.
	IF noi_t>0 THEN
		noi_t=noi_t-1
		noi_v=noi_v-noi_dv
		IF noi_v>15 THEN noi_v=0
		IF noi_t=0 THEN SOUND 3,,0 ELSE SOUND 3,noi_n,noi_v
	ELSE
		IF thr_on THEN
			SOUND 3,6,8
		ELSE
			IF thr_was THEN SOUND 3,,0
		END IF
		thr_was=thr_on
	END IF
END

	' ============================================================
	' RENDER ALL SPRITES
	' ============================================================
render: PROCEDURE
	' All sprites render as 32x32 (16x16 art at 2x magnification).
	' OUR OWN FLICKER (CVBasic's global flicker is OFF): the ship is pinned to
	' slot 0 (always drawn); EVERY other sprite's physical slot is rotated by srot
	' each frame -- p = L + srot wrapped into 1..31 (a bijection, so no two sprites
	' collide on a slot). When >4 share a scanline the VDP then drops a different
	' sprite each frame (flicker) instead of the same ones losing every time.
	srot=srot+1
	IF srot>=31 THEN srot=0
	fslot=1+srot
	uslot=6+srot : IF uslot>31 THEN uslot=uslot-31
	ubslot=7+srot : IF ubslot>31 THEN ubslot=ubslot-31
	IF ship_st=0 OR ship_st=1 THEN
		spx=#spx/64 : spy=#spy/64
		' Always draw the ship. X wraps via the VDP's horizontal sprite wrap;
		' Y is held in the visible band by upd_ship. Only the invincibility
		' blink hides it.
		shide=0
		IF ship_st=1 THEN
			IF ship_tmr AND 4 THEN shide=1
		END IF
		IF shide THEN
			SPRITE 0,$d1,0,0,0
			SPRITE fslot,$d1,0,0,0
		ELSE
			' Ship art is top-left-anchored: render at offset 11, not 16.
			SPRITE 0,spy-11,spx-11,sangle*4,15
			IF thr_on THEN
				' Flame placed by the per-frame offset table (engine-anchored,
				' on the ship axis). spx/spy are the visual center; the flame art
				' centers on cell col 7 row 8, so render at x-14, y-16.
				fpx=spx+#fdx_t(sangle)
				fpy=spy+#fdy_t(sangle)
				thr_frame=thr_frame XOR 4
				SPRITE fslot,fpy-16,fpx-14,thr_frame,11
			ELSE
				SPRITE fslot,$d1,0,0,0
			END IF
		END IF
	ELSE
		IF ship_st=2 THEN
			spx=#spx/64 : spy=#spy/64
			exp_fr=27+(60-ship_tmr)/15
			IF exp_fr>30 THEN exp_fr=30
			SPRITE 0,spy-16,spx-16,exp_fr*4,15
			SPRITE fslot,$d1,0,0,0
		ELSE
			SPRITE 0,$d1,0,0,0
			SPRITE fslot,$d1,0,0,0
		END IF
	END IF
	' Bullets (slots 2-5): positions in x64 units; 32x32 rendered at 2x
	FOR bi=1 TO 4
		bslot=bi+1+srot
		IF bslot>31 THEN bslot=bslot-31
		IF bact(bi) THEN
			bpy=#by(bi)/64 : bpx=#bx(bi)/64
			IF bpy<4 OR bpy>188 THEN
				SPRITE bslot,$d1,0,0,0
			ELSE
				SPRITE bslot,bpy-16,bpx-16,72,15
			END IF
		ELSE
			SPRITE bslot,$d1,0,0,0
		END IF
	NEXT bi
	' UFO (slot 6): ux,uy are screen pixel coords
	IF uexp>0 THEN
		SPRITE uslot,uy-16,ux-16,uefr,15
	ELSE
		IF utype>0 THEN
			IF utype=1 THEN
				SPRITE uslot,uy-16,ux-16,100,9
			ELSE
				SPRITE uslot,uy-16,ux-16,104,13
			END IF
			' Engine warble on channel 2: two alternating tones. Only re-issued
			' when channel 2 is free (sfx2=0) so a UFO fire "pew" plays over it.
			uw_ph=uw_ph+1
			IF uw_ph>=15 THEN
				uw_ph=0
				IF sfx2=0 THEN
					uw_tog=uw_tog XOR 1
					IF utype=1 THEN
						IF uw_tog THEN #f2=560 ELSE #f2=470
					ELSE
						IF uw_tog THEN #f2=1050 ELSE #f2=900
					END IF
					#d2=0 : v2=6 : sfx2=16
				END IF
			END IF
		ELSE
			SPRITE uslot,$d1,0,0,0
		END IF
	END IF
	' UFO bullet (slot 7): ubx,uby are screen pixel coords
	IF ubact THEN
		SPRITE ubslot,uby-16,ubx-16,72,9
	ELSE
		SPRITE ubslot,$d1,0,0,0
	END IF
	' Asteroids (pool 1-24). Physical slot rotated by the same srot as everything
	' else (see render top), so rocks share the one flicker rotation with the
	' bullets/UFO and never collide with them on a slot.
	FOR ai=1 TO 24
		aslot=ai+7+srot
		IF aslot>31 THEN aslot=aslot-31
		IF aact(ai)>0 THEN
			apx=#ax(ai)/64 : apy=#ay(ai)/64
			' Render guard: hide only in the top/bottom dead band (4 px) so
			' rocks stay drawn right out to the left/right edges. Symmetric
			' top<->bottom: hidden when apy<4 or apy>188.
			IF apy>=4 AND apy<=188 THEN
				IF aact(ai)=2 THEN
					SPRITE aslot,apy-16,apx-16,afr(ai),15
				ELSE
					SPRITE aslot,apy-16,apx-16,afr(ai),acolor(asiz(ai))
				END IF
			ELSE
				SPRITE aslot,$d1,0,0,0
			END IF
		ELSE
			SPRITE aslot,$d1,0,0,0
		END IF
	NEXT ai
END

	' ============================================================
	' HUD DRAW
	' ============================================================
hud_draw: PROCEDURE
	' Score at top-left (no label). Lives icons are drawn by lives_draw.
	PRINT AT 0,"      "
	PRINT AT 0,#score,"0"
	PRINT AT 20,"HI:"
	PRINT AT 23,#hiscore,"0  "
	IF #score>#hiscore THEN #hiscore=#score
END

	' ============================================================
	' LIVES ICONS (reserve ships shown at top, after the score)
	' ============================================================
lives_draw: PROCEDURE
	' Reserve = lives, minus the one in play (when a ship is on screen).
	lvshow=lives
	IF ship_st<2 THEN lvshow=lives-1
	IF lvshow>6 THEN lvshow=6
	PRINT AT 7,"      "
	IF lvshow>0 THEN
		li=1
		WHILE li<=lvshow
			PRINT AT 6+li,CHR$(128)
			li=li+1
		WEND
	END IF
END

	' ============================================================
	' 838 SETUP FIELD DRAW (value + active-field cursor)
	' ============================================================
setup_draw: PROCEDURE
	PRINT AT 7*32+16,<1>set_lives
	PRINT AT 9*32+16,<1>set_wave
	IF field=0 THEN
		PRINT AT 7*32+7,">"
		PRINT AT 9*32+7," "
	ELSE
		PRINT AT 7*32+7," "
		PRINT AT 9*32+7,">"
	END IF
END

	' ============================================================
	' GAME OVER
	' ============================================================
game_over: PROCEDURE
	SOUND 0,,0 : SOUND 1,,0 : SOUND 2,,0 : SOUND 3,,0
	sfx0=0 : sfx1=0 : sfx2=0 : noi_t=0 : thr_was=0
	' Leave the sprites frozen on screen behind the GAME OVER text -- the title
	' routine clears all 32 and rebuilds its own field when we return there.
	PRINT AT 11*32+11,"GAME OVER"
	FOR ti=1 TO 180
		WAIT
	NEXT ti
	PRINT AT 11*32+11,"         "
	GOTO title
END

	' ============================================================
	' LIFE ICON CHARACTER (char 128)
	' ============================================================
ship_icon_char:
	BITMAP "...X...."
	BITMAP "...X...."
	BITMAP "..XXX..."
	BITMAP "..XXX..."
	BITMAP ".XXXXX.."
	BITMAP ".XX.XX.."
	BITMAP "........"
	BITMAP "........"

	' Bitmap mode: one color byte PER ROW (8 per char). All white-on-black,
	' else the unset rows render with garbage colors (green).
ship_icon_color:
	DATA BYTE $f1,$f1,$f1,$f1,$f1,$f1,$f1,$f1

	INCLUDE "../assets/sprites.bas"
