	' ============================================================
	' ADVENTIRE - an Atari-2600-Adventure-style action-adventure.
	' Original code, art and map (mechanics homage; nothing copied).
	'
	' Quest: open the GOLD castle, take the SWORD, win the WHITE
	' key from the red dragon's maze, fetch the BRIDGE from the
	' white castle, bridge into the sealed cave chamber for the
	' BLACK key, brave the black castle, and carry the CHALICE
	' home inside the gold castle - alive.
	'
	'  - 13 rooms, each a 16x12 grid of 16x16-pixel blocks (one
	'    DATA byte pair per row); collision is a pure RAM bit test,
	'    zero per-frame VRAM reads.
	'  - THREE castles (gold/black/white) with key-matched gates;
	'    THREE dragons (yellow/green/red - red is faster).
	'  - You carry ONE object at a time (touch = pick up / swap,
	'    FIRE = drop). A picked-up object stays at the offset where
	'    you grabbed it (grab the sword on your left, it fights on
	'    your left).
	'  - The BRIDGE (32x32): drop it across a wall and walk through
	'    its channel. It is the only way into the sealed chamber.
	'    You grab it by its RAILS only (walking the channel must
	'    not re-pick it), its Y snaps to the block grid on drop so
	'    it always spans whole wall rows, and a second BLACK sprite
	'    fills the channel so the passage reads as an opening.
	'  - The BAT roams the whole map (through walls), stealing and
	'    swapping objects - even out of your hands. Snatch back!
	'  - Touched by a dragon without the sword = swallowed; FIRE
	'    then starts a FRESH game (full reset).
	'  - Sprites use 2x magnification (VDP R1 = $E3): 16x16 art
	'    renders 32x32 (4x4 characters) - towering dragons and a
	'    player-spanning bridge. The player square stays 8x8 so it
	'    can thread the 16px maze corridors.
	'
	' Build (ONE source, dual target):
	'   TI-99/4A:     cvbasic --ti994a adventire.bas -> xas99 -> linkticart
	'   ColecoVision: cvbasic adventire.bas -> gasm80 -> adventire.rom
	' Loop is paced to 30Hz (two WAITs) on both machines.
	' ============================================================

	DIM rm(24), msk(8)
	DIM lnn(13), lne(13), lns(13), lnw(13), rcol(13)
	DIM orm(6), obx(6), oby(6), ocl(6)
	DIM drm(3), ddx(3), ddy(3), dst(3), dcl(3), dsp(3), gop(3)

	BORDER 1
	' 2x sprite magnification: SI=1 (16x16 patterns) + MAG=1 -> sprites
	' render 32x32. VDP()= is CVBasic's portable register write (TI+CV).
	VDP(1) = $E3
	DEFINE CHAR 128, 2, wallchar
	DEFINE COLOR 128, 2, wallcol
	DEFINE SPRITE 0, 10, gsprites

	RESTORE mskdat
	FOR i = 0 TO 7 : READ BYTE msk(i) : NEXT i
	RESTORE lnkdat
	FOR i = 0 TO 12
	READ BYTE lnn(i) : READ BYTE lne(i) : READ BYTE lns(i) : READ BYTE lnw(i)
	NEXT i
	RESTORE coldat
	FOR i = 0 TO 12 : READ BYTE rcol(i) : NEXT i
	ocl(0) = 11 : ocl(1) = 14 : ocl(2) = 15 : ocl(3) = 7 : ocl(4) = 13 : ocl(5) = 15

	GOSUB title

newgame:
	RESTORE objdat
	FOR i = 0 TO 5
	READ BYTE orm(i) : READ BYTE obx(i) : READ BYTE oby(i)
	NEXT i
	RESTORE drgdat
	FOR i = 0 TO 2
	READ BYTE drm(i) : READ BYTE ddx(i) : READ BYTE ddy(i) : READ BYTE dcl(i) : READ BYTE dsp(i)
	dst(i) = 0
	NEXT i
	gop(0) = 0 : gop(1) = 0 : gop(2) = 0
	btr = 5 : btx = 120 : bty = 60 : btc = 255 : btcd = 90 : bfx = 0 : bfy = 1
	cr = 255 : pkcd = 0 : btnp = 1 : rmch = 0 : eflag = 0 : tk = 0
	sfx = 0 : sfc = 0 : #crx = 64 : #cry = 64
	SOUND 0, , 0 : SOUND 3, , 0
	rn = 0 : px = 120 : py = 160
	GOSUB enterroom

mainloop:
	WAIT
	WAIT
	tk = tk + 1
	GOSUB dosfx
	IF pkcd > 0 THEN pkcd = pkcd - 1

	' --- player movement (X and Y independent => wall sliding) ---
	IF cont1.left THEN GOSUB mvleft
	IF cont1.right THEN GOSUB mvright
	IF cont1.up THEN GOSUB mvup
	IF cont1.down THEN GOSUB mvdown
	IF rmch = 1 THEN rmch = 0 : GOTO drawframe

	' --- castle gate: open with key / walk in when open ---
	IF gz > 0 THEN GOSUB gatelogic
	IF rmch = 1 THEN rmch = 0 : GOTO drawframe

	' --- drop carried object with FIRE (edge-triggered) ---
	b = cont1.button
	IF b > 0 THEN IF btnp = 0 THEN IF cr < 6 THEN GOSUB dodrop
	btnp = b

	' --- carried object keeps the offset where it was grabbed ---
	IF cr < 6 THEN GOSUB carrypos

	' --- WIN: the chalice is inside the gold castle ---
	IF orm(5) = 2 THEN GOTO winseq

	' --- pick up / swap on touch ---
	IF pkcd = 0 THEN GOSUB trypick

	' --- the bat flies always, everywhere ---
	GOSUB batdo

	' --- dragons ---
	FOR d = 0 TO 2
	IF drm(d) = rn THEN GOSUB dragondo
	NEXT d
	' swallowed: play the sequence, then a FRESH game (full reset)
	IF eflag > 0 THEN GOSUB eatenrt : GOTO newgame

drawframe:
	SPRITE 0, py - 1, px, 0, 15
	FOR d = 0 TO 2
	IF drm(d) = rn THEN SPRITE 1 + d, ddy(d) - 1, ddx(d), 4 + dst(d) * 4, dcl(d) ELSE SPRITE 1 + d, $d1, 0, 0, 0
	NEXT d
	FOR i = 0 TO 5
	IF orm(i) = rn THEN GOSUB drawobj ELSE SPRITE 4 + i, $d1, 0, 0, 0
	NEXT i
	IF btr = rn THEN SPRITE 10, bty - 1, btx, 28 + ((tk AND 2) * 2), 14 ELSE SPRITE 10, $d1, 0, 0, 0
	' the bridge channel gets a black fill sprite so it reads as
	' an opening in the wall it spans (rails sprite lies on top)
	IF orm(4) = rn THEN SPRITE 11, oby(4) - 1, obx(4), 36, 1 ELSE SPRITE 11, $d1, 0, 0, 0
	GOTO mainloop

	' ------------------------------------------------------------
	' drop: the bridge snaps to the 16px block grid vertically so
	' its channel always covers whole wall rows
	' ------------------------------------------------------------
dodrop: PROCEDURE
	IF cr = 4 THEN oby(4) = (oby(4) + 8) AND 240
	cr = 255 : pkcd = 10 : sfx = 2 : sfc = 4
	END

	' ------------------------------------------------------------
	' object sprite: defs 3=key 4=sword 5=chalice 6=bridge
	' ------------------------------------------------------------
drawobj: PROCEDURE
	t = ocl(i)
	f = 12
	IF i = 3 THEN f = 16
	IF i = 4 THEN f = 24
	IF i = 5 THEN f = 20 : t = (FRAME AND 7) + 8
	SPRITE 4 + i, oby(i) - 1, obx(i), f, t
	END

	' ------------------------------------------------------------
	' movement: 3px steps, screen-edge exits, box-vs-wall test,
	' bridge channel exemption
	' ------------------------------------------------------------
mvleft: PROCEDURE
	IF rmch = 1 THEN RETURN
	IF px < 3 THEN GOSUB gowest : RETURN
	x0 = px - 3 : y0 = py : bw = 7 : bh = 7
	GOSUB chkbox
	IF bf = 1 THEN GOSUB brchk : IF brf = 1 THEN bf = 0
	IF bf = 0 THEN px = x0
	END

mvright: PROCEDURE
	IF rmch = 1 THEN RETURN
	IF px > 244 THEN GOSUB goeast : RETURN
	x0 = px + 3 : y0 = py : bw = 7 : bh = 7
	GOSUB chkbox
	IF bf = 1 THEN GOSUB brchk : IF brf = 1 THEN bf = 0
	IF bf = 0 THEN px = x0
	END

mvup: PROCEDURE
	IF rmch = 1 THEN RETURN
	IF py < 3 THEN GOSUB gonorth : RETURN
	x0 = px : y0 = py - 3 : bw = 7 : bh = 7
	GOSUB chkbox
	IF bf = 1 THEN GOSUB brchk : IF brf = 1 THEN bf = 0
	IF bf = 0 THEN py = y0
	END

mvdown: PROCEDURE
	IF rmch = 1 THEN RETURN
	IF py > 181 THEN GOSUB gosouth : RETURN
	x0 = px : y0 = py + 3 : bw = 7 : bh = 7
	GOSUB chkbox
	IF bf = 1 THEN GOSUB brchk : IF brf = 1 THEN bf = 0
	IF bf = 0 THEN py = y0
	END

brchk: PROCEDURE
	' bridge passage: the target box lies inside the channel of the
	' bridge (lying in this room, not carried, never over a gate)
	brf = 0
	IF orm(4) <> rn THEN RETURN
	IF cr = 4 THEN RETURN
	IF gz > 0 THEN RETURN
	' passage keeps a 2px margin off the rails so walking through
	' never counts as touching (= grabbing) them
	IF x0 < obx(4) + 6 THEN RETURN
	#ax = obx(4) + 25
	IF x0 + 7 > #ax THEN RETURN
	IF y0 + 7 < oby(4) THEN RETURN
	#ax = oby(4) + 31
	IF y0 > #ax THEN RETURN
	brf = 1
	END

gowest: PROCEDURE
	t = lnw(rn) : IF t = 255 THEN RETURN
	rn = t : px = 244 : rmch = 1
	GOSUB enterroom
	END

goeast: PROCEDURE
	t = lne(rn) : IF t = 255 THEN RETURN
	rn = t : px = 4 : rmch = 1
	GOSUB enterroom
	END

gonorth: PROCEDURE
	t = lnn(rn) : IF t = 255 THEN RETURN
	rn = t : py = 180 : rmch = 1
	GOSUB enterroom
	END

gosouth: PROCEDURE
	' leaving a castle hall puts you just below its (open) gate
	IF rn = 2 THEN rn = 0 : px = 120 : py = 66 : rmch = 1 : GOSUB enterroom : RETURN
	IF rn = 9 THEN rn = 8 : px = 120 : py = 66 : rmch = 1 : GOSUB enterroom : RETURN
	IF rn = 12 THEN rn = 11 : px = 120 : py = 66 : rmch = 1 : GOSUB enterroom : RETURN
	t = lns(rn) : IF t = 255 THEN RETURN
	rn = t : py = 4 : rmch = 1
	GOSUB enterroom
	END

	' ------------------------------------------------------------
	' gate: closed = touch it while carrying the matching key
	' (generous window: 3px steps can leave you at py=66-70);
	' open = walking deep into the archway warps inside the castle
	' ------------------------------------------------------------
gatelogic: PROCEDURE
	IF gopn = 1 THEN GOTO gwarp
	IF cr <> gz - 1 THEN RETURN
	IF px < 100 THEN RETURN
	IF px > 148 THEN RETURN
	IF py > 70 THEN RETURN
	gop(gz - 1) = 1 : gopn = 1
	FOR r = 4 TO 7
	FOR c2 = 14 TO 17 : VPOKE $1800 + r * 32 + c2, 32 : NEXT c2
	NEXT r
	sfx = 3 : sfc = 24 : #sfq = 700
	RETURN
gwarp:
	IF py > 34 THEN RETURN
	IF px < 106 THEN RETURN
	IF px > 138 THEN RETURN
	IF rn = 0 THEN rn = 2
	IF rn = 8 THEN rn = 9
	IF rn = 11 THEN rn = 12
	px = 120 : py = 156 : rmch = 1
	GOSUB enterroom
	END

	' ------------------------------------------------------------
	' carried object rides at its grab offset (#crx/#cry are the
	' object-minus-player offset, biased +64 to stay unsigned)
	' ------------------------------------------------------------
carrypos: PROCEDURE
	orm(cr) = rn
	#ax = px + #crx
	IF #ax < 64 THEN #ax = 64
	IF #ax > 304 THEN #ax = 304
	obx(cr) = #ax - 64
	#ax = py + #cry
	IF #ax < 64 THEN #ax = 64
	IF #ax > 240 THEN #ax = 240
	oby(cr) = #ax - 64
	END

	' ------------------------------------------------------------
	' pick up on touch (swap drops the old object on the spot)
	' ------------------------------------------------------------
trypick: PROCEDURE
	FOR i = 0 TO 5
	IF i <> cr THEN IF orm(i) = rn THEN GOSUB pchk
	NEXT i
	END

pchk: PROCEDURE
	IF i = 4 THEN GOSUB pbrchk : RETURN
	#ax = obx(i) + 8 : #bx = px + 4
	GOSUB adiff
	IF #cx > 11 THEN RETURN
	#ax = oby(i) + 6 : #bx = py + 4
	GOSUB adiff
	IF #cx > 10 THEN RETURN
	GOSUB dopick
	END

pbrchk: PROCEDURE
	' bridge: grabbed by its RAILS only - walking the channel (or
	' standing where you just dropped it) must NOT re-pick it up.
	' Also never while standing inside a wall - that would seal
	' you in.
	IF py + 7 < oby(i) THEN RETURN
	#ax = oby(i) + 31
	IF py > #ax THEN RETURN
	hit = 0
	#ax = obx(i) + 4
	IF px <= #ax THEN IF px + 7 >= obx(i) THEN hit = 1
	#ax = obx(i) + 27
	IF px + 7 >= #ax THEN IF px <= obx(i) + 31 THEN hit = 1
	IF hit = 0 THEN RETURN
	x0 = px : y0 = py : bw = 7 : bh = 7
	GOSUB chkbox
	IF bf = 1 THEN RETURN
	GOSUB dopick
	END

dopick: PROCEDURE
	cr = i : pkcd = 10 : sfx = 1 : sfc = 4
	' remember which side it was grabbed on
	#crx = obx(i) + 64 - px : #cry = oby(i) + 64 - py
	' snatched back from the bat
	IF i = btc THEN btc = 255 : btcd = 150
	END

adiff: PROCEDURE
	IF #ax > #bx THEN #cx = #ax - #bx ELSE #cx = #bx - #ax
	END

	' ------------------------------------------------------------
	' bat: simulated every tick in whatever room it occupies.
	' Flies through walls; drifts between rooms via the exit links
	' (halls/dungeon have no inbound links, so it never enters a
	' castle). Steals/swaps objects on touch - even yours.
	' ------------------------------------------------------------
batdo: PROCEDURE
	IF btcd > 0 THEN btcd = btcd - 1
	IF bfx = 1 THEN GOSUB batright ELSE GOSUB batleft
	IF bfy = 1 THEN bty = bty + 1 ELSE bty = bty - 1
	IF bty < 12 THEN GOSUB batnorth
	IF bty > 150 THEN GOSUB batsouth
	IF (tk AND 31) = 0 THEN bfy = 1 - bfy
	IF (tk AND 63) = 0 THEN IF RANDOM(2) = 1 THEN bfx = 1 - bfx
	' its loot dangles underneath
	IF btc < 6 THEN orm(btc) = btr : obx(btc) = btx + 8 : oby(btc) = bty + 10
	IF btcd = 0 THEN GOSUB batgrab
	END

batleft: PROCEDURE
	IF btx >= 10 THEN btx = btx - 2 : RETURN
	t = lnw(btr)
	IF t = 255 THEN bfx = 1 : RETURN
	btr = t : btx = 224
	END

batright: PROCEDURE
	IF btx <= 222 THEN btx = btx + 2 : RETURN
	t = lne(btr)
	IF t = 255 THEN bfx = 0 : RETURN
	btr = t : btx = 12
	END

batnorth: PROCEDURE
	t = lnn(btr)
	IF t = 255 THEN bfy = 1 : RETURN
	btr = t : bty = 144
	END

batsouth: PROCEDURE
	t = lns(btr)
	IF t = 255 THEN bfy = 0 : RETURN
	btr = t : bty = 14
	END

batgrab: PROCEDURE
	FOR i = 0 TO 5
	IF i <> btc THEN IF orm(i) = btr THEN GOSUB bgchk
	NEXT i
	END

bgchk: PROCEDURE
	#ax = obx(i) + 8 : #bx = btx + 16
	GOSUB adiff
	IF #cx > 12 THEN RETURN
	#ax = oby(i) + 6 : #bx = bty + 8
	GOSUB adiff
	IF #cx > 10 THEN RETURN
	' anti-softlock guards:
	' never take the bridge out of the chamber room, and never
	' swap-drop a carried object inside the sealed chamber
	IF i = 4 THEN IF btr = 6 THEN RETURN
	IF btc < 6 THEN IF btr = 6 THEN IF obx(i) > 160 THEN IF obx(i) < 216 THEN IF oby(i) < 64 THEN RETURN
	' steal it out of the player's hands if need be
	IF i = cr THEN cr = 255 : pkcd = 10
	t = btc : btc = i
	IF t < 6 THEN orm(t) = btr : obx(t) = obx(i) : oby(t) = oby(i)
	btcd = 150 : sfx = 6 : sfc = 10
	END

	' ------------------------------------------------------------
	' dragon: greedy chase (prefer the longer axis, slide on the
	' other), sword check, then bite check. The red dragon (dsp=1)
	' is faster. Shown 32x32; the wall box is its central 8x16.
	' ------------------------------------------------------------
dragondo: PROCEDURE
	IF dst(d) = 1 THEN RETURN
	tpx = px : IF tpx > 12 THEN tpx = tpx - 12
	tpy = py : IF tpy > 12 THEN tpy = tpy - 12
	ds = 2 + (tk AND 1)
	IF dsp(d) = 1 THEN ds = 3
	#ax = ddx(d) : #bx = tpx
	GOSUB adiff
	#dx = #cx
	#ax = ddy(d) : #bx = tpy
	GOSUB adiff
	m = 0
	IF #dx >= #cx THEN GOSUB dmovx ELSE GOSUB dmovy
	IF m = 0 THEN IF #dx >= #cx THEN GOSUB dmovy ELSE GOSUB dmovx
	GOSUB swordchk
	IF dst(d) = 1 THEN RETURN
	' bite: dragon centre (32x32 shown) vs player centre
	#ax = ddx(d) + 16 : #bx = px + 4
	GOSUB adiff
	IF #cx > 14 THEN RETURN
	#ax = ddy(d) + 16 : #bx = py + 4
	GOSUB adiff
	IF #cx > 16 THEN RETURN
	eflag = d + 1
	END

dmovx: PROCEDURE
	IF ddx(d) = tpx THEN RETURN
	IF tpx > ddx(d) THEN t = ddx(d) + ds ELSE t = ddx(d) - ds
	IF t < 4 THEN RETURN
	IF t > 220 THEN RETURN
	x0 = t + 12 : y0 = ddy(d) + 8 : bw = 7 : bh = 15
	GOSUB chkbox
	IF bf = 0 THEN ddx(d) = t : m = 1
	END

dmovy: PROCEDURE
	IF ddy(d) = tpy THEN RETURN
	IF tpy > ddy(d) THEN t = ddy(d) + ds ELSE t = ddy(d) - ds
	IF t < 4 THEN RETURN
	IF t > 156 THEN RETURN
	x0 = ddx(d) + 12 : y0 = t + 8 : bw = 7 : bh = 15
	GOSUB chkbox
	IF bf = 0 THEN ddy(d) = t : m = 1
	END

swordchk: PROCEDURE
	' the sword (object 3) slays on contact, carried OR lying
	IF orm(3) <> drm(d) THEN RETURN
	#ax = obx(3) + 12 : #bx = ddx(d) + 16
	GOSUB adiff
	IF #cx > 17 THEN RETURN
	#ax = oby(3) + 7 : #bx = ddy(d) + 16
	GOSUB adiff
	IF #cx > 16 THEN RETURN
	dst(d) = 1 : sfx = 4 : sfc = 14
	END

	' ------------------------------------------------------------
	' swallowed: wail + player shown in the dragon's belly, then
	' FIRE returns to the caller, which restarts a FRESH game
	' ------------------------------------------------------------
eatenrt: PROCEDURE
	e = eflag - 1 : eflag = 0
	sfx = 0 : SOUND 3, , 0
	FOR i = 1 TO 56
	WAIT
	SOUND 0, 200 + i * 14, 13
	SPRITE 0, ddy(e) + 15, ddx(e) + 11, 0, 15
	NEXT i
	SOUND 0, , 0
ewt1:	WAIT : IF cont1.button > 0 THEN GOTO ewt1
ewt2:	WAIT : IF cont1.button = 0 THEN GOTO ewt2
	END

	' ------------------------------------------------------------
	' point-vs-wall: RAM bitmap test + closed-gate special case
	' ------------------------------------------------------------
chkpt: PROCEDURE
	r = ty / 16 : c2 = tx / 16
	IF c2 > 7 THEN wf = rm(r + r + 1) AND msk(c2 AND 7) ELSE wf = rm(r + r) AND msk(c2)
	IF wf > 0 THEN RETURN
	IF gz = 0 THEN RETURN
	IF gopn = 1 THEN RETURN
	IF r < 2 THEN RETURN
	IF r > 3 THEN RETURN
	IF c2 < 7 THEN RETURN
	IF c2 > 8 THEN RETURN
	wf = 1
	END

chkbox: PROCEDURE
	' blocks are 16px and boxes are <=16px, so 4 corners suffice
	bf = 1
	tx = x0 : ty = y0
	GOSUB chkpt
	IF wf > 0 THEN RETURN
	tx = x0 + bw
	GOSUB chkpt
	IF wf > 0 THEN RETURN
	ty = y0 + bh
	GOSUB chkpt
	IF wf > 0 THEN RETURN
	tx = x0
	GOSUB chkpt
	IF wf > 0 THEN RETURN
	bf = 0
	END

	' ------------------------------------------------------------
	' room entry: load bitmap, tint walls, redraw, gate, dragons
	' ------------------------------------------------------------
enterroom: PROCEDURE
	FOR i = 1 TO 11 : SPRITE i, $d1, 0, 0, 0 : NEXT i
	ON rn GOTO er0, er1, er2, er3, er4, er5, er6, er7, er8, er9, er10, er11, er12
er0:	RESTORE rd0
	GOTO erld
er1:	RESTORE rd1
	GOTO erld
er2:	RESTORE rd2
	GOTO erld
er3:	RESTORE rd3
	GOTO erld
er4:	RESTORE rd4
	GOTO erld
er5:	RESTORE rd5
	GOTO erld
er6:	RESTORE rd6
	GOTO erld
er7:	RESTORE rd7
	GOTO erld
er8:	RESTORE rd8
	GOTO erld
er9:	RESTORE rd9
	GOTO erld
er10:	RESTORE rd10
	GOTO erld
er11:	RESTORE rd11
	GOTO erld
er12:	RESTORE rd12
erld:
	FOR i = 0 TO 23 : READ BYTE rm(i) : NEXT i
	' wall colour, all three screen thirds (colour table $2000)
	t = rcol(rn) * 16 + 1
	FOR i = 0 TO 7
	VPOKE $2400 + i, t : VPOKE $2C00 + i, t : VPOKE $3400 + i, t
	NEXT i
	CLS
	FOR r = 0 TO 11
	#ad = $1800 + r * 64
	FOR c2 = 0 TO 15
	i = r + r : IF c2 > 7 THEN i = i + 1
	IF (rm(i) AND msk(c2 AND 7)) > 0 THEN VPOKE #ad, 128 : VPOKE #ad + 1, 128 : VPOKE #ad + 32, 128 : VPOKE #ad + 33, 128
	#ad = #ad + 2
	NEXT c2
	NEXT r
	gz = 0 : gopn = 0
	IF rn = 0 THEN gz = 1
	IF rn = 8 THEN gz = 2
	IF rn = 11 THEN gz = 3
	IF gz > 0 THEN gopn = gop(gz - 1)
	IF gz > 0 THEN IF gopn = 0 THEN GOSUB drawgate
	FOR d = 0 TO 2
	IF drm(d) = rn THEN IF dst(d) = 0 THEN GOSUB dsafe : sfx = 5 : sfc = 20
	NEXT d
	END

drawgate: PROCEDURE
	FOR r = 4 TO 7
	FOR c2 = 14 TO 17 : VPOKE $1800 + r * 32 + c2, 129 : NEXT c2
	NEXT r
	END

dsafe: PROCEDURE
	' never let a dragon camp the doorway you enter through
	#ax = ddx(d) : #bx = px
	GOSUB adiff
	IF #cx > 40 THEN RETURN
	#ax = ddy(d) : #bx = py
	GOSUB adiff
	IF #cx > 40 THEN RETURN
	ddx(d) = 108 : ddy(d) = 72
	END

	' ------------------------------------------------------------
	' one-channel sound effect driver (1=pickup 2=drop 3=gate
	' 4=slay-noise 5=dragon roar 6=bat squeak); swallow/win inline
	' ------------------------------------------------------------
dosfx: PROCEDURE
	IF sfx = 0 THEN RETURN
	IF sfx = 1 THEN SOUND 0, 90, 12
	IF sfx = 2 THEN SOUND 0, 320, 10
	IF sfx = 3 THEN SOUND 0, #sfq, 11 : #sfq = #sfq - 25
	IF sfx = 4 THEN SOUND 3, 5, sfc
	IF sfx = 5 THEN SOUND 0, 880 + ((sfc AND 2) * 30), 10
	IF sfx = 6 THEN SOUND 0, 60 + ((sfc AND 2) * 6), 9
	sfc = sfc - 1
	IF sfc = 0 THEN sfx = 0 : SOUND 0, , 0 : SOUND 3, , 0
	RETURN
	END

	' ------------------------------------------------------------
	' win: colour-cycling walls + fanfare, then play again
	' ------------------------------------------------------------
winseq:
	FOR i = 0 TO 95
	WAIT
	t = (i AND 15) * 16 + 1
	FOR r = 0 TO 7
	VPOKE $2400 + r, t : VPOKE $2C00 + r, t : VPOKE $3400 + r, t
	NEXT r
	t = i AND 3
	IF t = 0 THEN SOUND 0, 214, 12
	IF t = 1 THEN SOUND 0, 170, 12
	IF t = 2 THEN SOUND 0, 143, 12
	IF t = 3 THEN SOUND 0, 107, 12
	NEXT i
	SOUND 0, , 0
	PRINT AT 32 * 13 + 10, "THE CHALICE"
	PRINT AT 32 * 14 + 10, "  IS HOME! "
	PRINT AT 32 * 16 + 7, "PRESS FIRE TO PLAY"
ww1:	WAIT : IF cont1.button > 0 THEN GOTO ww1
ww2:	WAIT : IF cont1.button = 0 THEN GOTO ww2
	GOTO newgame

	' ------------------------------------------------------------
	' title
	' ------------------------------------------------------------
title: PROCEDURE
	CLS
	t = 11 * 16 + 1
	FOR i = 0 TO 7
	VPOKE $2400 + i, t : VPOKE $2C00 + i, t : VPOKE $3400 + i, t
	NEXT i
	PRINT AT 32 * 3 + 7, "A D V E N T I R E"
	PRINT AT 32 * 7 + 10, "\128\128 \128\128 \128\128 \128\128"
	PRINT AT 32 * 8 + 10, "\128\128\128\128\128\128\128\128\128\128\128"
	PRINT AT 32 * 9 + 10, "\128\128\128\128\128\128\128\128\128\128\128"
	PRINT AT 32 * 10 + 10, "\128\128\128\128\129\129\129\128\128\128\128"
	PRINT AT 32 * 11 + 10, "\128\128\128\128\129\129\129\128\128\128\128"
	PRINT AT 32 * 14 + 5, "THREE CASTLES. THREE"
	PRINT AT 32 * 15 + 5, "DRAGONS. ONE CHALICE."
	PRINT AT 32 * 17 + 5, "AND MIND THE BAT."
	PRINT AT 32 * 20 + 6, "PRESS FIRE TO START"
tw1:	WAIT : IF cont1.button > 0 THEN GOTO tw1
tw2:	WAIT : IF cont1.button = 0 THEN GOTO tw2
	btnp = 1
	END

	' ============================================================
	' DATA
	' ============================================================

mskdat:
	DATA BYTE $80, $40, $20, $10, $08, $04, $02, $01

	' room links: N,E,S,W per room (255 = no exit that way).
	' Halls (2,9,12) and the dungeon (10) have NO inbound links -
	' they are entered only via gate warps, which the bat never
	' uses, so the bat can never carry loot into a locked castle.
lnkdat:
	DATA BYTE 255, 255, 1, 255	' R0 gold castle grounds
	DATA BYTE 0, 3, 4, 11		' R1 north meadow
	DATA BYTE 255, 255, 0, 255	' R2 gold castle hall (S special)
	DATA BYTE 255, 5, 255, 1	' R3 red corridor
	DATA BYTE 1, 6, 255, 255	' R4 south meadow
	DATA BYTE 255, 255, 7, 3	' R5 blue maze north
	DATA BYTE 255, 7, 255, 4	' R6 purple cave (sealed chamber)
	DATA BYTE 5, 8, 255, 6		' R7 blue maze south
	DATA BYTE 255, 255, 255, 7	' R8 black castle grounds
	DATA BYTE 255, 10, 8, 255	' R9 black castle hall (S special)
	DATA BYTE 255, 255, 255, 9	' R10 dungeon
	DATA BYTE 255, 1, 255, 255	' R11 white castle grounds
	DATA BYTE 255, 255, 11, 255	' R12 white castle hall (S special)

	' wall colour per room (VDP colour 0-15)
coldat:
	DATA BYTE 11, 2, 10, 8, 3, 5, 13, 4, 14, 14, 6, 15, 15

	' objects: room, x, y   (0 gold key, 1 black key, 2 white key,
	'                        3 sword, 4 bridge, 5 chalice)
objdat:
	DATA BYTE 4, 180, 120
	DATA BYTE 6, 180, 20
	DATA BYTE 7, 120, 88
	DATA BYTE 3, 120, 24
	DATA BYTE 12, 96, 80
	DATA BYTE 10, 120, 88

	' dragons: room, x, y, colour, fast-flag
	' (0 yellow guards the black castle, 1 green guards the cave,
	'  2 red - the fast one - prowls the maze around the white key)
drgdat:
	DATA BYTE 8, 36, 80, 11, 0
	DATA BYTE 6, 140, 72, 2, 0
	DATA BYTE 7, 104, 40, 8, 1

	' ------------------------------------------------------------
	' rooms: 12 rows x 16 block columns, 2 bytes/row (MSB = col 0)
	' ------------------------------------------------------------
rd0:	' gold castle grounds: towers, wall band, gate slot, S exit
	DATA BYTE $FF, $FF
	DATA BYTE $B0, $0D
	DATA BYTE $FE, $7F
	DATA BYTE $FE, $7F
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $FE, $7F

rd1:	' north meadow: N, E, S, W exits (crossroads)
	DATA BYTE $FE, $7F
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $00, $00
	DATA BYTE $00, $00
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $FE, $7F

rd2:	' gold castle hall: pillars, S doorway (WIN room)
	DATA BYTE $FF, $FF
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $98, $19
	DATA BYTE $98, $19
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $FE, $7F

rd3:	' red corridor: W and E exits, two bars (sword here)
	DATA BYTE $FF, $FF
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $8F, $F1
	DATA BYTE $80, $01
	DATA BYTE $00, $00
	DATA BYTE $00, $00
	DATA BYTE $80, $01
	DATA BYTE $8F, $F1
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $FF, $FF

rd4:	' south meadow: N and E exits, pond (gold key here)
	DATA BYTE $FE, $7F
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $00
	DATA BYTE $80, $00
	DATA BYTE $80, $01
	DATA BYTE $87, $E1
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $FF, $FF

rd5:	' blue maze north: W and S exits, ring walls
	DATA BYTE $FF, $FF
	DATA BYTE $80, $01
	DATA BYTE $BE, $7D
	DATA BYTE $82, $41
	DATA BYTE $B2, $4D
	DATA BYTE $02, $41
	DATA BYTE $02, $41
	DATA BYTE $B2, $4D
	DATA BYTE $82, $41
	DATA BYTE $BE, $7D
	DATA BYTE $80, $01
	DATA BYTE $FE, $7F

rd6:	' purple cave: W and E exits; SEALED chamber top-right
	' (interior block cols 11-12, rows 1-2; bottom wall row 3 -
	' only the bridge crosses it; the black key waits inside)
	DATA BYTE $FF, $FF
	DATA BYTE $80, $25
	DATA BYTE $80, $25
	DATA BYTE $80, $3D
	DATA BYTE $80, $01
	DATA BYTE $00, $00
	DATA BYTE $00, $00
	DATA BYTE $80, $01
	DATA BYTE $87, $E1
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $FF, $FF

rd7:	' blue maze south: N, W, E exits, post field (white key)
	DATA BYTE $FE, $7F
	DATA BYTE $80, $01
	DATA BYTE $9E, $79
	DATA BYTE $92, $49
	DATA BYTE $92, $49
	DATA BYTE $12, $48
	DATA BYTE $12, $48
	DATA BYTE $92, $49
	DATA BYTE $92, $49
	DATA BYTE $9E, $79
	DATA BYTE $80, $01
	DATA BYTE $FF, $FF

rd8:	' black castle grounds: towers, wall band, gate slot, W exit
	DATA BYTE $FF, $FF
	DATA BYTE $B0, $0D
	DATA BYTE $FE, $7F
	DATA BYTE $FE, $7F
	DATA BYTE $80, $01
	DATA BYTE $00, $01
	DATA BYTE $00, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $FF, $FF

rd9:	' black castle hall: pillars, E exit, S doorway
	DATA BYTE $FF, $FF
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $98, $19
	DATA BYTE $98, $19
	DATA BYTE $80, $00
	DATA BYTE $80, $00
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $FE, $7F

rd10:	' dungeon: W exit, corner brackets (chalice here)
	DATA BYTE $FF, $FF
	DATA BYTE $80, $01
	DATA BYTE $B8, $1D
	DATA BYTE $88, $11
	DATA BYTE $80, $01
	DATA BYTE $00, $01
	DATA BYTE $00, $01
	DATA BYTE $80, $01
	DATA BYTE $88, $11
	DATA BYTE $B8, $1D
	DATA BYTE $80, $01
	DATA BYTE $FF, $FF

rd11:	' white castle grounds: towers, wall band, gate slot, E exit
	DATA BYTE $FF, $FF
	DATA BYTE $B0, $0D
	DATA BYTE $FE, $7F
	DATA BYTE $FE, $7F
	DATA BYTE $80, $01
	DATA BYTE $80, $00
	DATA BYTE $80, $00
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $FF, $FF

rd12:	' white castle hall: pillars, S doorway (bridge here)
	DATA BYTE $FF, $FF
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $98, $19
	DATA BYTE $98, $19
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $80, $01
	DATA BYTE $FE, $7F

	' ------------------------------------------------------------
	' characters 128 (solid wall) and 129 (portcullis)
	' ------------------------------------------------------------
wallchar:
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "XXXXXXXX"
	BITMAP "X_X_X_X_"
	BITMAP "X_X_X_X_"
	BITMAP "XXXXXXXX"
	BITMAP "X_X_X_X_"
	BITMAP "X_X_X_X_"
	BITMAP "XXXXXXXX"
	BITMAP "X_X_X_X_"

wallcol:
	DATA BYTE $B1, $B1, $B1, $B1, $B1, $B1, $B1, $B1
	DATA BYTE $E1, $E1, $E1, $E1, $E1, $E1, $E1, $E1

	' ------------------------------------------------------------
	' sprites (16x16 art, shown 32x32 = 4x4 characters):
	' 0 player (kept 8x8 on screen), 1 dragon, 2 slain dragon,
	' 3 key, 4 sword, 5 chalice, 6 bridge, 7 bat A, 8 bat B
	' ------------------------------------------------------------
gsprites:
	BITMAP "XXXX____________"
	BITMAP "XXXX____________"
	BITMAP "XXXX____________"
	BITMAP "XXXX____________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"

	BITMAP "____XX__________"
	BITMAP "___XXXX_________"
	BITMAP "___XX_X_________"
	BITMAP "___XXXX_________"
	BITMAP "____XX_____X____"
	BITMAP "____XX____XX____"
	BITMAP "___XXXXX__XX____"
	BITMAP "__XXXXXXXXXX____"
	BITMAP "_XXXXXXXXXXX____"
	BITMAP "XX_XXXXXXXXX____"
	BITMAP "X__XXXXXXXX_____"
	BITMAP "___XXXXXXXX_____"
	BITMAP "__XXX__XXXX_____"
	BITMAP "__XX____XX______"
	BITMAP "__XX____XX______"
	BITMAP "_XXX____XXX_____"

	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "__XX___XX___XX__"
	BITMAP "__XX___XX___XX__"
	BITMAP "__X____X_____X__"
	BITMAP "_XXXXXXXXXXXXXX_"
	BITMAP "XXXXXXXXXXXXXXXX"
	BITMAP "XX_XXXXXXXXXX_XX"

	BITMAP "________________"
	BITMAP "________________"
	BITMAP "_XX_____________"
	BITMAP "X_XXXXXX________"
	BITMAP "_XX__X_X________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"

	BITMAP "________________"
	BITMAP "________________"
	BITMAP "__X_____________"
	BITMAP "XXXXXXXXXXXX____"
	BITMAP "__X_____________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"

	BITMAP "______XXXX______"
	BITMAP "_____XXXXXX_____"
	BITMAP "____XXXXXXXX____"
	BITMAP "____X______X____"
	BITMAP "____X______X____"
	BITMAP "_____X____X_____"
	BITMAP "______XXXX______"
	BITMAP "_______XX_______"
	BITMAP "_______XX_______"
	BITMAP "_______XX_______"
	BITMAP "______XXXX______"
	BITMAP "_____XXXXXX_____"
	BITMAP "____XXXXXXXX____"
	BITMAP "___XXXXXXXXXX___"
	BITMAP "________________"
	BITMAP "________________"

	BITMAP "XXX__________XXX"
	BITMAP "XX____________XX"
	BITMAP "XX____________XX"
	BITMAP "XX____________XX"
	BITMAP "XX____________XX"
	BITMAP "XX____________XX"
	BITMAP "XX____________XX"
	BITMAP "XX____________XX"
	BITMAP "XX____________XX"
	BITMAP "XX____________XX"
	BITMAP "XX____________XX"
	BITMAP "XX____________XX"
	BITMAP "XX____________XX"
	BITMAP "XX____________XX"
	BITMAP "XX____________XX"
	BITMAP "XXX__________XXX"

	BITMAP "________________"
	BITMAP "________________"
	BITMAP "X______XX______X"
	BITMAP "XX_____XX_____XX"
	BITMAP "_XXX__XXXX__XXX_"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "____XX_XX_XX____"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"

	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "____X_XXXX_X____"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "_XXX__XXXX__XXX_"
	BITMAP "X______XX______X"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"

	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
	BITMAP "__XXXXXXXXXXXX__"
