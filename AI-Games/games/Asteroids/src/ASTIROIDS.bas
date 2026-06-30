	' ============================================================
	' ASTIROIDS — CVBasic, TI-99/4A cartridge ROM
	' cvbasic --ti994a src/ASTIROIDS.bas build/ASTIROIDS.a99
	' ============================================================

	' Enable 2x sprite magnification: VDP R1 bit 0 = MAG.
	' CVBasic sets R1=>E2 (SI=1=16x16, MAG=0); we add MAG=1 -> >E3.
	' Sprites render as 32x32 pixels. Center offset = 16.
	ASM LI   R0,>E381
	ASM MOVB R0,@>8C02
	ASM SWPB R0
	ASM MOVB R0,@>8C02

	BORDER 1
	SPRITE FLICKER ON

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
	DIM #sin_t(16),#cos_t(16)

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

	acolor(1)=6 : acolor(2)=11 : acolor(3)=15

	' Score + session high score (persist across games; shown on the title).
	#score=0 : #hiscore=0

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
	PRINT AT 5*32+7,"TI-99/4A  CVBASIC"
	PRINT AT 9*32+6,"ROTATE : LEFT/RIGHT"
	PRINT AT 10*32+6,"THRUST : UP"
	PRINT AT 11*32+6,"FIRE   : BUTTON"
	PRINT AT 12*32+6,"HYPER  : DOWN"
	PRINT AT 15*32+10,"2026 UNHUMAN"
	PRINT AT 23*32+6,"PRESS FIRE TO BEGIN"
	hbeat_rate=120 : hbeat_timer=120 : hbeat_step=0
	sfx0=0 : sfx1=0 : sfx2=0 : sfx3=0
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
	GOSUB hbeat
	GOSUB sfx_t
	IF cont1.button THEN GOTO game_init
	GOTO title_loop

	' ============================================================
	' GAME INIT
	' ============================================================
game_init:
	GOSUB scr_clear
	' Note: #hiscore is NOT reset here -- it persists across games this session.
	lives=3 : wave=1 : #score=0 : last_extra=0
	FOR ti=0 TO 31
		SPRITE ti,$d1,0,0,0
	NEXT ti
	utype=0 : #utimer=600 : ubact=0 : uexp=0
	thr_on=0 : uw_ph=0 : rot_cd=0 : wave_gap=0
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
	WHILE 1
		WAIT
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
					#utimer=600 : utype=0 : ubact=0 : uexp=0
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
			IF sfx3=0 THEN SOUND 3,3,6 : sfx3=4
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
						' ~8 px/frame * 25 = ~200 px before expiring
						blife(fi)=25
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
						SOUND 1,900,12 : sfx1=8
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
		' POPS to the opposite edge (no straddle / gradual slide-in). The box
		' top-left must stay 0..224 (X) and 0..160 (Y), so the center is kept
		' in X 16..240 (#spx 1024..15360) and Y 16..176 (#spy 1024..11264).
		IF #spx>=32768 THEN
			#spx=#spx+14336
		ELSE
			IF #spx<1024 THEN
				#spx=#spx+14336
			ELSE
				IF #spx>=15360 THEN #spx=#spx-14336
			END IF
		END IF
		IF #spy>=32768 THEN
			#spy=#spy+10240
		ELSE
			IF #spy<1024 THEN
				#spy=#spy+10240
			ELSE
				IF #spy>=11264 THEN #spy=#spy-10240
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
	' Exploding: cycle explosion frames 27-30 in place, then clear the UFO.
	IF uexp>0 THEN
		uexp=uexp-1
		uefr=(27+(20-uexp)/5)*4
		IF uefr>120 THEN uefr=120
		IF uexp=0 THEN utype=0 : SPRITE 6,$d1,0,0,0
	ELSE
	IF utype=0 THEN
		IF #utimer>0 THEN
			#utimer=#utimer-1
		ELSE
			IF wave<4 THEN
				utype=1
			ELSE
				IF random(10)<4 THEN utype=2 ELSE utype=1
			END IF
			IF random(2)=0 THEN ux=16 : uvx=2 ELSE ux=239 : uvx=-2
			uy=random(160)+20
			uvy=0 : ufire=90 : uwarble=0 : ubact=0
			IF wave<4 THEN #utimer=1200 ELSE #utimer=900
		END IF
	ELSE
		ux=ux+uvx
		uwarble=uwarble+1
		IF uwarble>=20 THEN
			uwarble=0
			IF uy<36 THEN uvy=1
			IF uy>170 THEN uvy=-1
			IF random(4)=0 THEN uvy=random(3)-1
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
			ufire=ufire-1
			IF ufire=0 THEN
				ubact=1 : ublife=120 : ubx=ux : uby=uy
				IF utype=2 THEN
					dx=#spx/64-ux : dy=#spy/64-uy
					GOSUB ufo_aim
				ELSE
					aim_ang=random(16)
					ubvx=#sin_t(aim_ang)*4/64
					ubvy=-#cos_t(aim_ang)*4/64
				END IF
				IF utype=1 THEN ufire=90 ELSE ufire=60
				SOUND 2,500,10 : sfx2=6
			END IF
			IF ubact=1 THEN
				ubx=ubx+ubvx : uby=uby+ubvy
				ublife=ublife-1
				IF ublife=0 OR ubx<0 OR ubx>255 OR uby<0 OR uby>191 THEN ubact=0
			END IF
		END IF
	END IF
	END IF
END

ufo_aim: PROCEDURE
	mag=ABS(dx)+ABS(dy)
	IF mag=0 THEN
		aim_ang=random(16)
	ELSE
		IF mag>64 THEN
			dx=dx*64/mag
			dy=dy*64/mag
		END IF
		best_a=0 : best_d=-32000
		FOR aa=0 TO 15
			td=dx*#sin_t(aa)/64-dy*#cos_t(aa)/64
			IF td>best_d THEN best_d=td : best_a=aa
		NEXT aa
		aim_ang=best_a
	END IF
	ubvx=#sin_t(aim_ang)*4/64
	ubvy=-#cos_t(aim_ang)*4/64
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
							GOSUB ast_hit
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
						SOUND 0,300,12 : sfx0=20
						SOUND 3,3,12  : sfx3=15
						bi=5
					END IF
				END IF
			END IF
		NEXT bi
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
						GOSUB ast_hit
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
	END IF
END

	' ============================================================
	' ASTEROID HIT (global ai = pool index)
	' ============================================================
ast_hit: PROCEDURE
	IF asiz(ai)=1 THEN #score=#score+2
	IF asiz(ai)=2 THEN #score=#score+5
	IF asiz(ai)=3 THEN #score=#score+10
	GOSUB hud_draw
	IF asiz(ai)=1 THEN SOUND 3,3,12 : sfx3=20
	IF asiz(ai)=2 THEN SOUND 3,3,10 : sfx3=12
	IF asiz(ai)=3 THEN SOUND 3,3,8  : sfx3=6
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
	' Consume a ship now (at death) so the HUD reserve count is correct
	' through the explosion; game-over is decided when the explosion ends.
	lives=lives-1
	GOSUB lives_draw
	SOUND 0,300,14 : sfx0=30
	SOUND 1,150,12 : sfx1=25
	SOUND 3,3,14   : sfx3=30
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
		SOUND 0,500,13 : sfx0=8
		SOUND 1,400,13 : sfx1=6
		GOSUB lives_draw
	END IF
END

	' ============================================================
	' HEARTBEAT (tempo driven by asteroid count)
	' ============================================================
hbeat: PROCEDURE
	IF hbeat_timer>0 THEN
		hbeat_timer=hbeat_timer-1
	ELSE
		IF hbeat_step=0 THEN
			SOUND 0,1100,8 : sfx0=8
			hbeat_step=1
		ELSE
			SOUND 0,860,8 : sfx0=8
			hbeat_step=0
		END IF
		hbeat_rate=120-ast_count*4
		IF hbeat_rate<30 THEN hbeat_rate=30
		hbeat_timer=hbeat_rate
	END IF
END

	' ============================================================
	' SFX TICK
	' ============================================================
sfx_t: PROCEDURE
	IF sfx0>0 THEN sfx0=sfx0-1 : IF sfx0=0 THEN SOUND 0,,0
	IF sfx1>0 THEN sfx1=sfx1-1 : IF sfx1=0 THEN SOUND 1,,0
	IF sfx2>0 THEN sfx2=sfx2-1 : IF sfx2=0 THEN SOUND 2,,0
	IF sfx3>0 THEN sfx3=sfx3-1 : IF sfx3=0 THEN SOUND 3,,0
END

	' ============================================================
	' RENDER ALL SPRITES
	' ============================================================
render: PROCEDURE
	' All sprites render as 32x32 (16x16 art at 2x magnification).
	' Center offset = 16. Valid position range: spy 16..207, spx 16..271.
	' Ship (slot 0) and thrust flame (slot 1)
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
			SPRITE 1,$d1,0,0,0
		ELSE
			SPRITE 0,spy-16,spx-16,sangle*4,15
			IF thr_on THEN
				' Flame 8px behind ship center (rear wings ~5px from center at 2x)
				fpy=spy+#cos_t(sangle)*8/64
				fpx=spx-#sin_t(sangle)*8/64
				thr_frame=thr_frame XOR 4
				SPRITE 1,fpy-16,fpx-16,thr_frame,11
			ELSE
				SPRITE 1,$d1,0,0,0
			END IF
		END IF
	ELSE
		IF ship_st=2 THEN
			spx=#spx/64 : spy=#spy/64
			exp_fr=27+(60-ship_tmr)/15
			IF exp_fr>30 THEN exp_fr=30
			SPRITE 0,spy-16,spx-16,exp_fr*4,15
			SPRITE 1,$d1,0,0,0
		ELSE
			SPRITE 0,$d1,0,0,0
			SPRITE 1,$d1,0,0,0
		END IF
	END IF
	' Bullets (slots 2-5): positions in x64 units; 32x32 rendered at 2x
	FOR bi=1 TO 4
		IF bact(bi) THEN
			bpy=#by(bi)/64 : bpx=#bx(bi)/64
			IF bpy<16 OR bpx<16 OR bpx>239 THEN
				SPRITE bi+1,$d1,0,0,0
			ELSE
				SPRITE bi+1,bpy-16,bpx-16,72,15
			END IF
		ELSE
			SPRITE bi+1,$d1,0,0,0
		END IF
	NEXT bi
	' UFO (slot 6): ux,uy are screen pixel coords
	IF uexp>0 THEN
		SPRITE 6,uy-16,ux-16,uefr,15
	ELSE
		IF utype>0 THEN
			IF utype=1 THEN
				SPRITE 6,uy-16,ux-16,100,9
			ELSE
				SPRITE 6,uy-16,ux-16,104,13
			END IF
			uw_ph=uw_ph+1
			IF uw_ph>=15 THEN
				uw_ph=0
				IF utype=1 THEN
					SOUND 2,600,7 : sfx2=16
				ELSE
					SOUND 2,1200,7 : sfx2=16
				END IF
			END IF
		ELSE
			SPRITE 6,$d1,0,0,0
		END IF
	END IF
	' UFO bullet (slot 7): ubx,uby are screen pixel coords
	IF ubact THEN
		SPRITE 7,uby-16,ubx-16,72,9
	ELSE
		SPRITE 7,$d1,0,0,0
	END IF
	' Asteroids (slots 8-31 = pool 1-24)
	FOR ai=1 TO 24
		IF aact(ai)>0 THEN
			apx=#ax(ai)/64 : apy=#ay(ai)/64
			' Render guard: hide near edges to prevent VDP dead-zone glitch
			IF apy>=16 AND apx>=16 AND apx<=239 THEN
				IF aact(ai)=2 THEN
					SPRITE ai+7,apy-16,apx-16,afr(ai),15
				ELSE
					SPRITE ai+7,apy-16,apx-16,afr(ai),acolor(asiz(ai))
				END IF
			ELSE
				SPRITE ai+7,$d1,0,0,0
			END IF
		ELSE
			SPRITE ai+7,$d1,0,0,0
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
	' GAME OVER
	' ============================================================
game_over: PROCEDURE
	SOUND 0,,0 : SOUND 1,,0 : SOUND 2,,0 : SOUND 3,,0
	FOR ti=0 TO 31
		SPRITE ti,$d1,0,0,0
	NEXT ti
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
