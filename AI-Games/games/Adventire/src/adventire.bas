	' ============================================================
	' ADVENTIRE - an Atari-2600-Adventure-style action-adventure.
	' Original code, art, and room data throughout (a mechanics
	' homage: layouts and connections are our own adaptation of
	' the game structure documented in published maps/guides).
	'
	' FOUR game variations, chosen on the title screen:
	'   GAME 1  INTRO KINGDOM  - our original 13-room map: a
	'           gentle introduction (3 castles, 3 dragons, bat,
	'           bridge + sealed chamber).
	'   GAME 2  SMALL KINGDOM  - compact kingdom in the spirit of
	'           the cartridge's first game: gold + black castles,
	'           two dragons, no bat, no dark rooms.
	'   GAME 3  FULL KINGDOM   - the big map: 3 castles, corridor
	'           row, blue maze, DARK catacombs and black-castle
	'           maze (fog of war), red maze, magnet, bat, and the
	'           hidden-dot secret room.
	'   GAME 4  RANDOM KINGDOM - the full kingdom with object
	'           locations scrambled each game.
	'
	' Core rules (all games):
	'  - Rooms are 32x24 grids of 8x8-pixel cells (4 bytes/row,
	'    authored as readable BITMAP art); collision is a RAM bit
	'    test, zero per-frame VRAM reads. Thin 8px walls give the
	'    kingdom's mazes their winding, original-cartridge look.
	'  - Dragons ignore walls entirely and PURSUE you from room
	'    to room (a live dragon you escape bursts in ~1.3s later).
	'  - Doorways whose exit leads nowhere in the selected game
	'    are sealed on entry, so collision and visuals agree.
	'  - Carry ONE object (touch = pick up / swap, FIRE = drop);
	'    a carried object keeps the offset where you grabbed it.
	'  - Keys open the matching castle gate on touch; walk up into
	'    the open archway to enter.
	'  - The SWORD slays dragons on contact, carried or lying.
	'  - The BRIDGE: grab by its RAILS, drop across a wall (snaps
	'    to the block grid) and walk through its dark channel.
	'  - The MAGNET (games 3/4) drags every loose object in its
	'    room toward it - even out of sealed chambers.
	'  - The BAT steals objects, even from your hands.
	'  - DARK rooms (games 3/4) reveal walls only near you.
	'  - The invisible DOT (games 3/4) hides in the black castle
	'    maze chamber; bring it + 2 objects to the corridor's east
	'    end and the wall opens to a secret room.
	'  - Swallowed or victorious -> back to the title (game
	'    select); every start is a full reset.
	'
	' Build (ONE source, dual target):
	'   TI-99/4A:     cvbasic --ti994a adventire.bas -> xas99 -> linkticart
	'   ColecoVision: cvbasic adventire.bas -> gasm80 -> adventire.rom
	' Loop is paced to 30Hz (two WAITs) on both machines.
	' ============================================================

	' rooms are 32x24 grids of 8x8-pixel cells ("quarter blocks"):
	' 4 bytes per row x 24 rows = 96 bytes, MSB = leftmost cell
	DIM rm(96), msk(8)
	DIM orm(8), obx(8), oby(8), ocl(8)
	DIM drm(3), ddx(3), ddy(3), dst(3), dcl(3), dsp(3), gop(3), fdl(3)

	BORDER 1
	' 2x sprite magnification: SI=1 (16x16 patterns) + MAG=1 -> sprites
	' render 32x32. VDP()= is CVBasic's portable register write (TI+CV).
	VDP(1) = $E3
	DEFINE CHAR 128, 2, wallchar
	DEFINE COLOR 128, 2, wallcol
	DEFINE SPRITE 0, 13, gsprites

	RESTORE mskdat
	FOR i = 0 TO 7 : READ BYTE msk(i) : NEXT i
	gm = 1

restart:
	GOSUB title

newgame:
	' ---- per-game world state (objects, dragons, bat, start) ----
	IF gm = 1 THEN RESTORE objd1
	IF gm = 2 THEN RESTORE objd2
	IF gm > 2 THEN RESTORE objd3
	FOR i = 0 TO 7
	READ BYTE orm(i) : READ BYTE obx(i) : READ BYTE oby(i)
	NEXT i
	FOR i = 0 TO 2
	READ BYTE drm(i) : READ BYTE ddx(i) : READ BYTE ddy(i) : READ BYTE dcl(i) : READ BYTE dsp(i)
	dst(i) = 0
	NEXT i
	READ BYTE btr : READ BYTE btx : READ BYTE bty
	READ BYTE rn : READ BYTE winrm
	fdl(0) = 0 : fdl(1) = 0 : fdl(2) = 0 : prn = 255
	IF gm = 4 THEN GOSUB rndobj
	ocl(0) = 11 : ocl(1) = 1 : ocl(2) = 15 : ocl(3) = 7
	ocl(4) = 13 : ocl(5) = 15 : ocl(6) = 6 : ocl(7) = 0
	gop(0) = 0 : gop(1) = 0 : gop(2) = 0
	btc = 255 : btcd = 90 : bfx = 0 : bfy = 1
	cr = 255 : pkcd = 0 : btnp = 1 : rmch = 0 : eflag = 0 : tk = 0
	sfx = 0 : sfc = 0 : #crx = 64 : #cry = 64 : eggon = 0
	SOUND 0, , 0 : SOUND 3, , 0
	px = 120 : py = 160
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

	' --- dark rooms: keep the reveal window on the player ---
	IF fon = 1 THEN GOSUB fogupd

	' --- castle gate: open with key / walk in when open ---
	IF gz > 0 THEN GOSUB gatelogic
	IF rmch = 1 THEN rmch = 0 : GOTO drawframe

	' --- drop carried object with FIRE (edge-triggered) ---
	b = cont1.button
	IF b > 0 THEN IF btnp = 0 THEN IF cr < 8 THEN GOSUB dodrop
	btnp = b

	' --- carried object keeps the offset where it was grabbed ---
	IF cr < 8 THEN GOSUB carrypos

	' --- WIN: the chalice is inside the gold castle ---
	IF orm(5) = winrm THEN GOTO winseq

	' --- pick up / swap on touch ---
	IF pkcd = 0 THEN GOSUB trypick

	' --- the magnet drags loose objects in its room ---
	IF orm(6) = rn THEN IF cr <> 6 THEN GOSUB magnetdo

	' --- secret wall: check + flicker (full kingdom only) ---
	IF gm > 2 THEN IF rn = 17 THEN GOSUB eggdo
	IF rn = 18 THEN GOSUB eggtxt

	' --- the bat flies always, everywhere ---
	IF btr < 255 THEN GOSUB batdo

	' --- dragons: pending pursuers arrive, residents chase ---
	FOR d = 0 TO 2
	IF fdl(d) > 0 THEN GOSUB dfollow
	IF drm(d) = rn THEN GOSUB dragondo
	NEXT d
	' swallowed: play the sequence, then back to the title
	IF eflag > 0 THEN GOSUB eatenrt : GOTO restart

drawframe:
	SPRITE 0, py - 1, px, 0, pcol
	' dragons are TWO stacked 32x32 sprites (32x64 shown)
	FOR d = 0 TO 2
	IF drm(d) = rn THEN GOSUB drawdrg ELSE SPRITE 1 + d + d, $d1, 0, 0, 0 : SPRITE 2 + d + d, $d1, 0, 0, 0
	NEXT d
	FOR i = 0 TO 7
	IF orm(i) = rn THEN GOSUB drawobj ELSE SPRITE 7 + i, $d1, 0, 0, 0
	NEXT i
	IF btr = rn THEN SPRITE 15, bty - 1, btx, 32 + ((tk AND 2) * 2), 1 ELSE SPRITE 15, $d1, 0, 0, 0
	' the bridge channel gets a black fill sprite so it reads as
	' an opening in the wall it spans (rails sprite lies on top)
	IF orm(4) = rn THEN SPRITE 16, oby(4) - 1, obx(4), 40, 1 ELSE SPRITE 16, $d1, 0, 0, 0
	GOTO mainloop

	' ------------------------------------------------------------
	' dragon body: def1 (head/neck) above def2 (body/legs);
	' slain dragons collapse to the belly-up def3 at ground level
	' ------------------------------------------------------------
drawdrg: PROCEDURE
	IF dst(d) = 1 THEN SPRITE 1 + d + d, $d1, 0, 0, 0 : SPRITE 2 + d + d, ddy(d) + 31, ddx(d), 12, dcl(d) : RETURN
	SPRITE 1 + d + d, ddy(d) - 1, ddx(d), 4, dcl(d)
	SPRITE 2 + d + d, ddy(d) + 31, ddx(d), 8, dcl(d)
	END

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
	' 10=magnet 11=dot (dot painted in the background colour)
	' ------------------------------------------------------------
drawobj: PROCEDURE
	t = ocl(i)
	f = 16
	IF i = 3 THEN f = 20
	IF i = 4 THEN f = 28
	IF i = 5 THEN f = 24 : t = (FRAME AND 7) + 8
	IF i = 6 THEN f = 44
	IF i = 7 THEN f = 48 : t = cb
	SPRITE 7 + i, oby(i) - 1, obx(i), f, t
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
	IF bf = 1 THEN GOSUB hassist
	IF bf = 0 THEN px = x0
	END

mvright: PROCEDURE
	IF rmch = 1 THEN RETURN
	IF px > 244 THEN GOSUB goeast : RETURN
	x0 = px + 3 : y0 = py : bw = 7 : bh = 7
	GOSUB chkbox
	IF bf = 1 THEN GOSUB brchk : IF brf = 1 THEN bf = 0
	IF bf = 1 THEN GOSUB hassist
	IF bf = 0 THEN px = x0
	END

mvup: PROCEDURE
	IF rmch = 1 THEN RETURN
	IF py < 3 THEN GOSUB gonorth : RETURN
	x0 = px : y0 = py - 3 : bw = 7 : bh = 7
	GOSUB chkbox
	IF bf = 1 THEN GOSUB brchk : IF brf = 1 THEN bf = 0
	IF bf = 1 THEN GOSUB vassist
	IF bf = 0 THEN py = y0
	END

mvdown: PROCEDURE
	IF rmch = 1 THEN RETURN
	IF py > 181 THEN GOSUB gosouth : RETURN
	x0 = px : y0 = py + 3 : bw = 7 : bh = 7
	GOSUB chkbox
	IF bf = 1 THEN GOSUB brchk : IF brf = 1 THEN bf = 0
	IF bf = 1 THEN GOSUB vassist
	IF bf = 0 THEN py = y0
	END

	' ------------------------------------------------------------
	' doorway assist: 3px steps make lining an 8px square up with
	' a 16px gap fiddly, so when a move is blocked we nudge the
	' player (max 4px) onto the cell grid if that clears the way
	' ------------------------------------------------------------
vassist: PROCEDURE
	t = (px + 4) AND 248
	IF t = px THEN RETURN
	IF t > px THEN t2 = t - px ELSE t2 = px - t
	IF t2 > 4 THEN RETURN
	x0 = t
	GOSUB chkbox
	IF bf = 1 THEN x0 = px : RETURN
	px = t
	END

hassist: PROCEDURE
	t = (py + 4) AND 248
	IF t = py THEN RETURN
	IF t > py THEN t2 = t - py ELSE t2 = py - t
	IF t2 > 4 THEN RETURN
	y0 = t
	GOSUB chkbox
	IF bf = 1 THEN y0 = py : RETURN
	py = t
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
	IF pw = 255 THEN RETURN
	rn = pw : px = 244 : rmch = 1
	GOSUB enterroom
	ax = 1
	GOSUB arrsnap
	END

goeast: PROCEDURE
	IF pe = 255 THEN RETURN
	rn = pe : px = 4 : rmch = 1
	GOSUB enterroom
	ax = 1
	GOSUB arrsnap
	END

gonorth: PROCEDURE
	IF pn = 255 THEN RETURN
	rn = pn : py = 180 : rmch = 1
	GOSUB enterroom
	ax = 0
	GOSUB arrsnap
	END

gosouth: PROCEDURE
	' leaving a castle hall puts you just below its (open) gate
	IF rn = 2 THEN rn = 0 : GOTO gsw
	IF rn = 9 THEN rn = 8 : GOTO gsw
	IF rn = 12 THEN rn = 11 : GOTO gsw
	IF rn = 14 THEN rn = 13 : GOTO gsw
	IF rn = 25 THEN rn = 24 : GOTO gsw
	IF rn = 33 THEN rn = 32 : GOTO gsw
	IF ps = 255 THEN RETURN
	rn = ps : py = 4 : rmch = 1
	GOSUB enterroom
	ax = 0
	GOSUB arrsnap
	RETURN
gsw:
	px = 120 : py = 66 : rmch = 1
	GOSUB enterroom
	END

	' ------------------------------------------------------------
	' arrival snap: screens deliberately do NOT line up (multiple,
	' offset gaps per edge, like the original) - if the arrival
	' spot is walled, slide along the edge to the NEAREST opening.
	' ax=0: slide px (N/S arrivals); ax=1: slide py (E/W arrivals)
	' ------------------------------------------------------------
arrsnap: PROCEDURE
	x0 = px : y0 = py : bw = 7 : bh = 7
	GOSUB chkbox
	IF bf = 0 THEN RETURN
	IF ax = 0 THEN snb = (px + 4) AND 248 ELSE snb = (py + 4) AND 248
	FOR sfd = 8 TO 240 STEP 8
	GOSUB artry
	IF bf = 0 THEN GOTO arrs2
	NEXT sfd
arrs2:
	' the snap moved us after fogenter drew - recentre the lamp
	IF fon = 1 THEN GOSUB fogwipe : GOSUB fogenter
	END

artry: PROCEDURE
	IF snb >= sfd THEN GOSUB artrym : IF bf = 0 THEN RETURN
	GOSUB artryp
	END

artrym: PROCEDURE
	t2 = snb - sfd
	IF ax = 0 THEN x0 = t2 ELSE y0 = t2
	GOSUB chkbox
	IF bf = 1 THEN RETURN
	IF ax = 0 THEN px = t2 ELSE py = t2
	END

artryp: PROCEDURE
	#aw = snb + sfd
	IF ax = 0 THEN IF #aw > 240 THEN RETURN
	IF ax = 1 THEN IF #aw > 176 THEN RETURN
	t2 = snb + sfd
	IF ax = 0 THEN x0 = t2 ELSE y0 = t2
	GOSUB chkbox
	IF bf = 1 THEN RETURN
	IF ax = 0 THEN px = t2 ELSE py = t2
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
	gop(gz - 1) = 1
	' the portcullis RISES: the opening appears at the bottom and
	' grows upward, one row at a time, with a rising clank per row
	' (the gate stays solid until it is fully up)
	FOR r = 7 TO 4 STEP -1
	VPOKE $1800 + r * 32 + 14, 32 : VPOKE $1800 + r * 32 + 15, 32
	VPOKE $1800 + r * 32 + 16, 32 : VPOKE $1800 + r * 32 + 17, 32
	SOUND 0, 200 + r * 60, 11
	FOR i = 1 TO 7 : WAIT : NEXT i
	NEXT r
	SOUND 0, , 0
	gopn = 1
	RETURN
gwarp:
	IF py > 34 THEN RETURN
	IF px < 106 THEN RETURN
	IF px > 138 THEN RETURN
	IF rn = 0 THEN rn = 2 : GOTO gwin
	IF rn = 8 THEN rn = 9 : GOTO gwin
	IF rn = 11 THEN rn = 12 : GOTO gwin
	IF rn = 13 THEN rn = 14 : GOTO gwin
	IF rn = 24 THEN rn = 25 : GOTO gwin
	rn = 33
gwin:
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
	FOR i = 0 TO 7
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
	IF i = 7 THEN sfx = 0
	' remember which side it was grabbed on
	#crx = obx(i) + 64 - px : #cry = oby(i) + 64 - py
	' snatched back from the bat
	IF i = btc THEN btc = 255 : btcd = 150
	END

adiff: PROCEDURE
	IF #ax > #bx THEN #cx = #ax - #bx ELSE #cx = #bx - #ax
	END

	' ------------------------------------------------------------
	' magnet: every loose object in the magnet's room creeps 1px
	' per tick toward it (straight line, through walls) until it
	' rests beside it - the classic tool for retrieving objects
	' from unreachable spots
	' ------------------------------------------------------------
magnetdo: PROCEDURE
	FOR o = 0 TO 7
	IF o <> 6 THEN IF o <> cr THEN IF o <> btc THEN IF orm(o) = rn THEN GOSUB magpull
	NEXT o
	END

magpull: PROCEDURE
	#ax = obx(o) : #bx = obx(6)
	GOSUB adiff
	#dx = #cx
	#ax = oby(o) : #bx = oby(6)
	GOSUB adiff
	IF #dx + #cx <= 12 THEN RETURN
	IF obx(o) < obx(6) THEN obx(o) = obx(o) + 1
	IF obx(o) > obx(6) THEN obx(o) = obx(o) - 1
	IF oby(o) < oby(6) THEN oby(o) = oby(o) + 1
	IF oby(o) > oby(6) THEN oby(o) = oby(o) - 1
	END

	' ------------------------------------------------------------
	' the secret wall (room 17, east end of the corridor row):
	' with the dot here plus 2 or more other objects, the east
	' wall flickers and lets you through to the secret room
	' ------------------------------------------------------------
eggdo: PROCEDURE
	IF eggon = 0 THEN GOSUB eggchk
	IF eggon = 0 THEN RETURN
	t = 32 : IF (tk AND 1) = 1 THEN t = 128
	FOR r = 10 TO 13
	VPOKE $1800 + r * 32 + 30, t : VPOKE $1800 + r * 32 + 31, t
	NEXT r
	END

eggchk: PROCEDURE
	IF orm(7) <> 17 THEN RETURN
	e2 = 0
	FOR i = 0 TO 6
	IF orm(i) = 17 THEN e2 = e2 + 1
	NEXT i
	IF e2 < 2 THEN RETURN
	eggon = 1
	END

	' secret room: ripple one glyph's colour per tick
eggtxt: PROCEDURE
	i2 = tk AND 15
	RESTORE eggch
	WHILE i2 > 0 : READ BYTE t : i2 = i2 - 1 : WEND
	READ BYTE t
	c3 = ((tk / 4) AND 7) + 8
	#ad = $2800 + t * 8
	FOR i2 = 0 TO 7 : VPOKE #ad + i2, c3 * 16 + 14 : NEXT i2
	END

	' ------------------------------------------------------------
	' bat: simulated every tick in whatever room it occupies.
	' Flies through walls; drifts between rooms via the exit
	' links. Steals/swaps objects on touch - even yours.
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
	IF btc < 8 THEN orm(btc) = btr : obx(btc) = btx + 8 : oby(btc) = bty + 10
	IF btcd = 0 THEN GOSUB batgrab
	END

batleft: PROCEDURE
	IF btx >= 10 THEN btx = btx - 2 : RETURN
	lkr = btr
	GOSUB getlnk
	IF lkw = 255 THEN bfx = 1 : RETURN
	IF lkw = 18 THEN bfx = 1 : RETURN
	btr = lkw : btx = 224
	END

batright: PROCEDURE
	IF btx <= 222 THEN btx = btx + 2 : RETURN
	lkr = btr
	GOSUB getlnk
	IF lke = 255 THEN bfx = 0 : RETURN
	IF lke = 18 THEN bfx = 0 : RETURN
	btr = lke : btx = 12
	END

batnorth: PROCEDURE
	lkr = btr
	GOSUB getlnk
	IF lkn = 255 THEN bfy = 1 : RETURN
	IF lkn = 18 THEN bfy = 1 : RETURN
	btr = lkn : bty = 144
	END

batsouth: PROCEDURE
	lkr = btr
	GOSUB getlnk
	IF lks = 255 THEN bfy = 0 : RETURN
	IF lks = 18 THEN bfy = 0 : RETURN
	btr = lks : bty = 14
	END

batgrab: PROCEDURE
	FOR i = 0 TO 6
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
	' never take the bridge out of a chamber room (6/28/35), and
	' never swap-drop a carried object inside a sealed chamber
	IF i = 4 THEN IF (btr = 6) OR (btr = 28) OR (btr = 35) THEN RETURN
	IF btc < 8 THEN IF (btr = 6) OR (btr = 28) OR (btr = 35) THEN IF obx(i) > 160 THEN IF obx(i) < 216 THEN IF oby(i) < 64 THEN RETURN
	' steal it out of the player's hands if need be
	IF i = cr THEN cr = 255 : pkcd = 10
	t = btc : btc = i
	IF t < 8 THEN orm(t) = btr : obx(t) = obx(i) : oby(t) = oby(i)
	btcd = 150 : sfx = 6 : sfc = 10
	END

	' ------------------------------------------------------------
	' dragon: greedy chase (prefer the longer axis, slide on the
	' other), sword check, then bite check. Fast flag (dsp=1)
	' marks the red dragon. Shown 32x32; wall box = central 8x16.
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
	' bite: dragon centre (32x64 shown) vs player centre
	#ax = ddx(d) + 16 : #bx = px + 4
	GOSUB adiff
	IF #cx > 14 THEN RETURN
	#ax = ddy(d) + 32 : #bx = py + 4
	GOSUB adiff
	IF #cx > 24 THEN RETURN
	eflag = d + 1
	END

	' dragons glide OVER walls, like the cartridge's - the maze
	' never protects you, only the sword does
dmovx: PROCEDURE
	IF ddx(d) = tpx THEN RETURN
	IF tpx > ddx(d) THEN t = ddx(d) + ds ELSE t = ddx(d) - ds
	IF t < 4 THEN RETURN
	IF t > 220 THEN RETURN
	ddx(d) = t : m = 1
	END

dmovy: PROCEDURE
	IF ddy(d) = tpy THEN RETURN
	IF tpy > ddy(d) THEN t = ddy(d) + ds ELSE t = ddy(d) - ds
	IF t < 4 THEN RETURN
	IF t > 124 THEN RETURN
	ddy(d) = t : m = 1
	END

	' a live dragon left behind bursts into your room a beat later
dfollow: PROCEDURE
	fdl(d) = fdl(d) - 1
	IF fdl(d) > 0 THEN RETURN
	IF dst(d) = 1 THEN RETURN
	drm(d) = rn : ddx(d) = 108 : ddy(d) = 64
	sfx = 5 : sfc = 20
	END

swordchk: PROCEDURE
	' the sword (object 3) slays on contact, carried OR lying
	IF orm(3) <> drm(d) THEN RETURN
	#ax = obx(3) + 12 : #bx = ddx(d) + 16
	GOSUB adiff
	IF #cx > 17 THEN RETURN
	#ax = oby(3) + 7 : #bx = ddy(d) + 32
	GOSUB adiff
	IF #cx > 26 THEN RETURN
	dst(d) = 1 : sfx = 4 : sfc = 14
	END

	' ------------------------------------------------------------
	' swallowed: wail + player shown in the dragon's belly, then
	' FIRE returns to the caller (back to the title screen)
	' ------------------------------------------------------------
eatenrt: PROCEDURE
	e = eflag - 1 : eflag = 0
	sfx = 0 : SOUND 3, , 0
	FOR i = 1 TO 56
	WAIT
	SOUND 0, 200 + i * 14, 13
	GOSUB eatflash
	NEXT i
	SOUND 0, , 0
ewt1:	WAIT
	GOSUB eatflash
	IF cont1.button > 0 THEN GOTO ewt1
ewt2:	WAIT
	GOSUB eatflash
	IF cont1.button = 0 THEN GOTO ewt2
	END

	' in the belly: flash black/white so the player is visible
	' whatever colour the dragon (or the room) happens to be
eatflash: PROCEDURE
	t2 = 1
	IF (FRAME AND 8) > 0 THEN t2 = 15
	SPRITE 0, ddy(e) + 27, ddx(e) + 11, 0, t2
	END

	' ------------------------------------------------------------
	' point-vs-wall: RAM bitmap test + closed-gate special case
	' + the secret wall once it is open
	' ------------------------------------------------------------
chkpt: PROCEDURE
	' 8px cells: row 0-23, col 0-31; byte = row*4 + col/8
	r = ty / 8 : c2 = tx / 8
	wf = rm(r * 4 + (c2 / 8)) AND msk(c2 AND 7)
	IF wf = 0 THEN GOTO ckgate
	' the flickering secret wall is passable
	IF eggon = 0 THEN RETURN
	IF rn <> 17 THEN RETURN
	IF c2 < 30 THEN RETURN
	IF r < 10 THEN RETURN
	IF r > 13 THEN RETURN
	wf = 0
	RETURN
ckgate:
	IF gz = 0 THEN RETURN
	IF gopn = 1 THEN RETURN
	IF r < 4 THEN RETURN
	IF r > 7 THEN RETURN
	IF c2 < 14 THEN RETURN
	IF c2 > 17 THEN RETURN
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
	' link + colour lookup: tables live in ROM, read on demand
	' (lkr in -> lkn/lke/lks/lkw). Game 1 = custom map table;
	' game 2 = small kingdom; games 3/4 = full kingdom.
	' ------------------------------------------------------------
getlnk: PROCEDURE
	IF gm = 1 THEN RESTORE lnkc
	IF gm = 2 THEN RESTORE lnkb
	IF gm > 2 THEN RESTORE lnka
	i2 = lkr : IF gm > 1 THEN i2 = lkr - 13
	WHILE i2 > 0
	READ BYTE t : READ BYTE t : READ BYTE t : READ BYTE t
	i2 = i2 - 1
	WEND
	READ BYTE lkn : READ BYTE lke : READ BYTE lks : READ BYTE lkw
	END

	' ------------------------------------------------------------
	' room entry: load bitmap, colours (wall,bg,dark), redraw,
	' gate, fog window, secret-room text, dragons
	' ------------------------------------------------------------
enterroom: PROCEDURE
	FOR i = 1 TO 16 : SPRITE i, $d1, 0, 0, 0 : NEXT i
	' any live dragon in the room we just left will pursue
	IF prn < 255 THEN IF prn <> rn THEN GOSUB dchase
	prn = rn
	' room bitmap: 96 bytes, dispatched by label (skip-reading
	' rn*96 bytes would stall room entry)
	ON rn GOTO rb0, rb1, rb2, rb3, rb4, rb5, rb6, rb7, rb8, rb9, rb10, rb11, rb12, rb13, rb14, rb15, rb16, rb17, rb18, rb19, rb20, rb21, rb22, rb23, rb24, rb25, rb26, rb27, rb28, rb29, rb30, rb31, rb32, rb33, rb34, rb35, rb36, rb37, rb38
rb0:	RESTORE rd0
	GOTO rbl
rb1:	RESTORE rd1
	GOTO rbl
rb2:	RESTORE rd2
	GOTO rbl
rb3:	RESTORE rd3
	GOTO rbl
rb4:	RESTORE rd4
	GOTO rbl
rb5:	RESTORE rd5
	GOTO rbl
rb6:	RESTORE rd6
	GOTO rbl
rb7:	RESTORE rd7
	GOTO rbl
rb8:	RESTORE rd8
	GOTO rbl
rb9:	RESTORE rd9
	GOTO rbl
rb10:	RESTORE rd10
	GOTO rbl
rb11:	RESTORE rd11
	GOTO rbl
rb12:	RESTORE rd12
	GOTO rbl
rb13:	RESTORE rd13
	GOTO rbl
rb14:	RESTORE rd14
	GOTO rbl
rb15:	RESTORE rd15
	GOTO rbl
rb16:	RESTORE rd16
	GOTO rbl
rb17:	RESTORE rd17
	GOTO rbl
rb18:	RESTORE rd18
	GOTO rbl
rb19:	RESTORE rd19
	GOTO rbl
rb20:	RESTORE rd20
	GOTO rbl
rb21:	RESTORE rd21
	GOTO rbl
rb22:	RESTORE rd22
	GOTO rbl
rb23:	RESTORE rd23
	GOTO rbl
rb24:	RESTORE rd24
	GOTO rbl
rb25:	RESTORE rd25
	GOTO rbl
rb26:	RESTORE rd26
	GOTO rbl
rb27:	RESTORE rd27
	GOTO rbl
rb28:	RESTORE rd28
	GOTO rbl
rb29:	RESTORE rd29
	GOTO rbl
rb30:	RESTORE rd30
	GOTO rbl
rb31:	RESTORE rd31
	GOTO rbl
rb32:	RESTORE rd32
	GOTO rbl
rb33:	RESTORE rd33
	GOTO rbl
rb34:	RESTORE rd34
	GOTO rbl
rb35:	RESTORE rd35
	GOTO rbl
rb36:	RESTORE rd36
	GOTO rbl
rb37:	RESTORE rd37
	GOTO rbl
rb38:	RESTORE rd38
rbl:
	FOR i = 0 TO 95 : READ BYTE rm(i) : NEXT i
	' colours: (wall, bg, dark) per room
	IF gm = 1 THEN RESTORE colc ELSE RESTORE cola
	i2 = rn : IF gm > 1 THEN i2 = rn - 13
	WHILE i2 > 0
	READ BYTE t : READ BYTE t : READ BYTE t
	i2 = i2 - 1
	WEND
	READ BYTE cw : READ BYTE cb : READ BYTE drk
	' wall char 128: fg=wall, bg=room bg;
	' portcullis 129: castle doors are always BLACK
	t = cw * 16 + cb
	t2 = 16 + cb
	FOR i = 0 TO 7
	VPOKE $2400 + i, t : VPOKE $2C00 + i, t : VPOKE $3400 + i, t
	VPOKE $2408 + i, t2 : VPOKE $2C08 + i, t2 : VPOKE $3408 + i, t2
	NEXT i
	' the player square wears the room's wall colour, exactly
	' like the original avatar (walls always contrast with the
	' background, so it stays visible everywhere)
	pcol = cw
	' empty cells (char 32) show the background colour
	FOR i = 0 TO 7
	VPOKE $2100 + i, cb : VPOKE $2900 + i, cb : VPOKE $3100 + i, cb
	NEXT i
	BORDER cb
	' player links cached for the exit routines
	lkr = rn
	GOSUB getlnk
	pn = lkn : pe = lke : ps = lks : pw = lkw
	' seal any doorway whose exit leads nowhere in THIS game, so
	' collision and visuals agree (game 2 shares screens with the
	' full kingdom but links fewer of them)
	IF pn = 255 THEN rm(0) = 255 : rm(1) = 255 : rm(2) = 255 : rm(3) = 255
	IF ps = 255 THEN rm(92) = 255 : rm(93) = 255 : rm(94) = 255 : rm(95) = 255
	IF pe = 255 THEN FOR i = 0 TO 23 : rm(i * 4 + 3) = rm(i * 4 + 3) OR 3 : NEXT i
	IF pw = 255 THEN FOR i = 0 TO 23 : rm(i * 4) = rm(i * 4) OR $C0 : NEXT i
	CLS
	fon = 0
	IF drk = 1 THEN GOSUB fogenter ELSE GOSUB drawroom
	gz = 0 : gopn = 0
	IF rn = 0 THEN gz = 1
	IF rn = 13 THEN gz = 1
	IF rn = 8 THEN gz = 2
	IF rn = 24 THEN gz = 2
	IF rn = 11 THEN gz = 3
	IF rn = 32 THEN gz = 3
	IF gz > 0 THEN gopn = gop(gz - 1)
	IF gz > 0 THEN IF gopn = 0 THEN GOSUB drawgate
	IF rn = 18 THEN PRINT AT 32 * 10 + 11, "ADVENTIRE" : PRINT AT 32 * 13 + 4, "2026 UNHUMAN AND CLAUDE"
	FOR d = 0 TO 2
	IF drm(d) = rn THEN IF dst(d) = 0 THEN GOSUB dsafe : sfx = 5 : sfc = 20
	NEXT d
	END

dchase: PROCEDURE
	' schedule pursuit for live dragons in the abandoned room
	FOR d = 0 TO 2
	IF drm(d) = prn THEN IF dst(d) = 0 THEN fdl(d) = 40
	NEXT d
	END

drawroom: PROCEDURE
	' one char per 8px cell (CLS already blanked the screen)
	FOR r = 0 TO 23
	#ad = $1800 + r * 32
	FOR t2 = 0 TO 3
	t = rm(r * 4 + t2)
	FOR i = 0 TO 7
	IF (t AND msk(i)) > 0 THEN VPOKE #ad, 128
	#ad = #ad + 1
	NEXT i
	NEXT t2
	NEXT r
	END

drawgate: PROCEDURE
	FOR r = 4 TO 7
	FOR c2 = 14 TO 17 : VPOKE $1800 + r * 32 + c2, 129 : NEXT c2
	NEXT r
	END

	' ------------------------------------------------------------
	' fog of war (dark rooms): only wall blocks within 2 blocks
	' of the player are drawn; window is redrawn when the player
	' crosses a block boundary
	' ------------------------------------------------------------
fogenter: PROCEDURE
	fon = 1
	fpr = (py + 4) / 8 : fpc = (px + 4) / 8
	GOSUB fogdraw
	END

fogupd: PROCEDURE
	' differential update: the player crosses at most one cell
	' boundary per axis per tick, so only the trailing edge is
	' erased and the leading edge drawn (a full window wipe+draw
	' every crossing dragged the TI-99 below 30Hz in dark rooms)
	t = (py + 4) / 8 : t2 = (px + 4) / 8
	IF t2 <> fpc THEN GOSUB foghz
	IF t <> fpr THEN GOSUB fogvt
	END

foghz: PROCEDURE
	IF t2 > fpc THEN fc = fpc - 5 : fl = t2 + 5 ELSE fc = fpc + 5 : fl = t2 - 5
	GOSUB fogecol
	fpc = t2
	fc = fl
	GOSUB fogdcol
	END

fogvt: PROCEDURE
	IF t > fpr THEN fc = fpr - 5 : fl = t + 5 ELSE fc = fpr + 5 : fl = t - 5
	GOSUB fogerow
	fpr = t
	fc = fl
	GOSUB fogdrow
	END

fogecol: PROCEDURE
	IF fc > 31 THEN RETURN
	r0f = 0 : IF fpr > 5 THEN r0f = fpr - 5
	r1f = fpr + 5 : IF r1f > 23 THEN r1f = 23
	#ad = $1800 + r0f * 32 + fc
	FOR r = r0f TO r1f
	VPOKE #ad, 32
	#ad = #ad + 32
	NEXT r
	END

fogdcol: PROCEDURE
	IF fc > 31 THEN RETURN
	r0f = 0 : IF fpr > 5 THEN r0f = fpr - 5
	r1f = fpr + 5 : IF r1f > 23 THEN r1f = 23
	i2 = fc / 8 : f = msk(fc AND 7)
	#ad = $1800 + r0f * 32 + fc
	FOR r = r0f TO r1f
	IF (rm(r * 4 + i2) AND f) > 0 THEN VPOKE #ad, 128
	#ad = #ad + 32
	NEXT r
	END

fogerow: PROCEDURE
	IF fc > 23 THEN RETURN
	c0f = 0 : IF fpc > 5 THEN c0f = fpc - 5
	c1f = fpc + 5 : IF c1f > 31 THEN c1f = 31
	#ad = $1800 + fc * 32 + c0f
	FOR c2 = c0f TO c1f
	VPOKE #ad, 32
	#ad = #ad + 1
	NEXT c2
	END

fogdrow: PROCEDURE
	IF fc > 23 THEN RETURN
	c0f = 0 : IF fpc > 5 THEN c0f = fpc - 5
	c1f = fpc + 5 : IF c1f > 31 THEN c1f = 31
	i2 = fc * 4
	#ad = $1800 + fc * 32 + c0f
	FOR c2 = c0f TO c1f
	IF (rm(i2 + (c2 / 8)) AND msk(c2 AND 7)) > 0 THEN VPOKE #ad, 128
	#ad = #ad + 1
	NEXT c2
	END

fogwipe: PROCEDURE
	' blank the whole window (room entry / arrival snaps only)
	GOSUB fogbnd
	FOR r = r0f TO r1f
	#ad = $1800 + r * 32 + c0f
	FOR c2 = c0f TO c1f
	VPOKE #ad, 32
	#ad = #ad + 1
	NEXT c2
	NEXT r
	END

fogdraw: PROCEDURE
	GOSUB fogbnd
	FOR r = r0f TO r1f
	#ad = $1800 + r * 32 + c0f
	FOR c2 = c0f TO c1f
	IF (rm(r * 4 + (c2 / 8)) AND msk(c2 AND 7)) > 0 THEN VPOKE #ad, 128
	#ad = #ad + 1
	NEXT c2
	NEXT r
	END

fogbnd: PROCEDURE
	' 5-cell radius = 40px lamplight
	r0f = 0 : IF fpr > 5 THEN r0f = fpr - 5
	r1f = fpr + 5 : IF r1f > 23 THEN r1f = 23
	c0f = 0 : IF fpc > 5 THEN c0f = fpc - 5
	c1f = fpc + 5 : IF c1f > 31 THEN c1f = 31
	END

dsafe: PROCEDURE
	' never let a dragon camp the doorway you enter through
	#ax = ddx(d) : #bx = px
	GOSUB adiff
	IF #cx > 40 THEN RETURN
	#ax = ddy(d) : #bx = py
	GOSUB adiff
	IF #cx > 40 THEN RETURN
	ddx(d) = 108 : ddy(d) = 64
	END

	' ------------------------------------------------------------
	' game 4: scramble the objects across the open kingdom.
	' The white key must not land inside the white castle's own
	' red maze (rooms 34/35) - that would seal it away. The BLACK
	' key (o=1) is never scrambled: it stays sealed in the red-maze
	' chamber so the bridge is always required.
	' ------------------------------------------------------------
rndobj: PROCEDURE
	FOR o = 0 TO 6
	IF o = 1 THEN GOTO rnxt
rrty:	t2 = RANDOM(16)
	RESTORE rndrm
	WHILE t2 > 0 : READ BYTE t : t2 = t2 - 1 : WEND
	READ BYTE t
	IF o = 2 THEN IF (t = 34) OR (t = 35) THEN GOTO rrty
	orm(o) = t : obx(o) = 96 + o * 8 : oby(o) = 88
rnxt:
	NEXT o
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
	END

	' ------------------------------------------------------------
	' win: colour-cycling walls + fanfare, then back to the title
	' ------------------------------------------------------------
winseq:
	FOR i = 0 TO 95
	WAIT
	t = (i AND 15) * 16 + cb
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
	GOTO restart

	' ------------------------------------------------------------
	' title + game select (UP/DOWN choose, FIRE start)
	' ------------------------------------------------------------
title: PROCEDURE
	CLS
	' clear every sprite left over from the game just played
	FOR i = 0 TO 16 : SPRITE i, $d1, 0, 0, 0 : NEXT i
	BORDER 1
	t = 11 * 16 + 1
	FOR i = 0 TO 7
	VPOKE $2400 + i, t : VPOKE $2C00 + i, t : VPOKE $3400 + i, t
	VPOKE $2100 + i, 1 : VPOKE $2900 + i, 1 : VPOKE $3100 + i, 1
	NEXT i
	' undo any secret-room glyph colour cycling (middle third)
	RESTORE eggch
	FOR i2 = 0 TO 15
	READ BYTE t
	#ad = $2800 + t * 8
	FOR i = 0 TO 7 : VPOKE #ad + i, $F0 : NEXT i
	NEXT i2
	PRINT AT 32 * 2 + 7, "A D V E N T I R E"
	PRINT AT 32 * 5 + 10, "\128\128 \128\128 \128\128 \128\128"
	PRINT AT 32 * 6 + 10, "\128\128\128\128\128\128\128\128\128\128\128"
	PRINT AT 32 * 7 + 10, "\128\128\128\128\129\129\129\128\128\128\128"
	PRINT AT 32 * 8 + 10, "\128\128\128\128\129\129\129\128\128\128\128"
	PRINT AT 32 * 11 + 7, "GAME 1  INTRO KINGDOM"
	PRINT AT 32 * 13 + 7, "GAME 2  SMALL KINGDOM"
	PRINT AT 32 * 15 + 7, "GAME 3  FULL KINGDOM"
	PRINT AT 32 * 17 + 7, "GAME 4  RANDOM KINGDOM"
	PRINT AT 32 * 21 + 6, "PRESS FIRE TO START"
	' debounce: the press that ended the last game must not start
	' the next one - require the button quiet for ~2/3 second
	udl = 0 : t2 = 20
tdb:	WAIT
	IF cont1.button > 0 THEN t2 = 20 : GOTO tdb
	t2 = t2 - 1
	IF t2 > 0 THEN GOTO tdb
tsel:
	WAIT
	IF udl > 0 THEN udl = udl - 1
	FOR i = 0 TO 3
	IF i = gm - 1 THEN PRINT AT 32 * (11 + i * 2) + 5, ">" ELSE PRINT AT 32 * (11 + i * 2) + 5, " "
	NEXT i
	IF udl = 0 THEN IF cont1.up THEN IF gm > 1 THEN gm = gm - 1 : udl = 8
	IF udl = 0 THEN IF cont1.down THEN IF gm < 4 THEN gm = gm + 1 : udl = 8
	IF cont1.button = 0 THEN GOTO tsel
tw2:	WAIT : IF cont1.button > 0 THEN GOTO tw2
	btnp = 1
	END

	' ============================================================
	' DATA
	' ============================================================

mskdat:
	DATA BYTE $80, $40, $20, $10, $08, $04, $02, $01

	' secret-room glyphs whose colours ripple (16 codes)
eggch:
	DATA BYTE 65, 68, 86, 69, 78, 84, 73, 82
	DATA BYTE 50, 48, 54, 85, 72, 77, 67, 76

	' game 4 scatter rooms (16 open/maze/corridor rooms)
rndrm:
	DATA BYTE 15, 16, 17, 19, 20, 21, 22, 23
	DATA BYTE 29, 30, 31, 34, 35, 36, 37, 38

	' ------------------------------------------------------------
	' links: N,E,S,W per room (255 = none). Castle halls have no
	' inbound edge links (gate warps only), so the bat can never
	' carry loot into a locked castle.
	' ------------------------------------------------------------
lnkc:	' game 1 - custom intro map, rooms 0-12
	DATA BYTE 255, 255, 1, 255
	DATA BYTE 0, 3, 4, 11
	DATA BYTE 255, 255, 0, 255
	DATA BYTE 255, 5, 255, 1
	DATA BYTE 1, 6, 255, 255
	DATA BYTE 255, 255, 7, 3
	DATA BYTE 255, 7, 255, 4
	DATA BYTE 5, 8, 255, 6
	DATA BYTE 255, 255, 255, 7
	DATA BYTE 255, 10, 8, 255
	DATA BYTE 255, 255, 255, 9
	DATA BYTE 255, 1, 255, 255
	DATA BYTE 255, 255, 11, 255

lnkb:	' game 2 - small kingdom (rooms 13-38; sealed = 255)
	DATA BYTE 255, 255, 16, 255	' 13 gold grounds
	DATA BYTE 255, 255, 13, 255	' 14 gold hall
	DATA BYTE 255, 16, 255, 19	' 15 corridor W
	DATA BYTE 13, 17, 255, 15	' 16 corridor mid
	DATA BYTE 255, 255, 255, 16	' 17 corridor E (dead end here)
	DATA BYTE 255, 255, 255, 255	' 18 secret (absent)
	DATA BYTE 20, 15, 255, 21	' 19 blue maze
	DATA BYTE 23, 21, 19, 21	' 20 blue maze
	DATA BYTE 22, 20, 19, 20	' 21 blue maze
	DATA BYTE 23, 23, 21, 255	' 22 blue maze
	DATA BYTE 24, 20, 20, 22	' 23 blue maze top
	DATA BYTE 255, 255, 23, 255	' 24 black grounds
	DATA BYTE 255, 255, 24, 255	' 25 black hall (chalice+magnet)
	DATA BYTE 255, 255, 255, 255	' 26
	DATA BYTE 255, 255, 255, 255	' 27
	DATA BYTE 255, 255, 255, 255	' 28
	DATA BYTE 255, 255, 255, 255	' 29
	DATA BYTE 255, 255, 255, 255	' 30
	DATA BYTE 255, 255, 255, 255	' 31
	DATA BYTE 255, 255, 255, 255	' 32
	DATA BYTE 255, 255, 255, 255	' 33
	DATA BYTE 255, 255, 255, 255	' 34
	DATA BYTE 255, 255, 255, 255	' 35
	DATA BYTE 255, 255, 255, 255	' 36
	DATA BYTE 255, 255, 255, 255	' 37
	DATA BYTE 255, 255, 255, 255	' 38

lnka:	' games 3/4 - full kingdom (rooms 13-38)
	DATA BYTE 255, 255, 16, 255	' 13 gold grounds
	DATA BYTE 255, 255, 13, 255	' 14 gold hall (WIN)
	DATA BYTE 255, 16, 255, 19	' 15 corridor W -> blue maze
	DATA BYTE 13, 17, 255, 15	' 16 corridor mid (N to castle)
	DATA BYTE 255, 18, 29, 16	' 17 corridor E (egg wall E, catacombs S)
	DATA BYTE 255, 255, 255, 17	' 18 SECRET room
	DATA BYTE 20, 15, 255, 21	' 19 blue maze
	DATA BYTE 23, 21, 19, 21	' 20 blue maze (hyperspace W)
	DATA BYTE 22, 20, 19, 20	' 21 blue maze
	DATA BYTE 23, 23, 21, 255	' 22 blue maze (hyperspace E)
	DATA BYTE 24, 20, 20, 22	' 23 blue maze top -> black castle
	'   (23 E goes to 20, whose west edge is open; 22's west
	'   edge is walled, so an E-link into it would trap you)
	DATA BYTE 255, 255, 23, 255	' 24 black grounds
	DATA BYTE 255, 26, 24, 255	' 25 black hall -> dark maze
	DATA BYTE 27, 27, 255, 25	' 26 black maze (dark)
	DATA BYTE 28, 26, 26, 26	' 27 black maze (dark)
	DATA BYTE 255, 255, 27, 27	' 28 black maze + dot chamber (dark)
	DATA BYTE 17, 30, 30, 31	' 29 catacombs (dark)
	DATA BYTE 29, 31, 31, 29	' 30 catacombs (dark)
	DATA BYTE 30, 36, 255, 32	' 31 catacombs (dark)
	DATA BYTE 255, 31, 255, 255	' 32 white grounds
	DATA BYTE 255, 34, 32, 255	' 33 white hall -> red maze
	DATA BYTE 35, 35, 255, 33	' 34 red maze
	DATA BYTE 255, 255, 34, 34	' 35 red maze end (black key)
	DATA BYTE 255, 255, 37, 31	' 36 purple side room
	DATA BYTE 36, 255, 38, 255	' 37 cyan side room
	DATA BYTE 37, 255, 255, 255	' 38 rose side room

	' ------------------------------------------------------------
	' colours: (wall, background, dark) per room
	' ------------------------------------------------------------
colc:	' game 1 custom map: coloured walls on GRAY (so the black
	' bat reads everywhere); its black castle is black too
	DATA BYTE 11, 14, 0
	DATA BYTE 2, 14, 0
	DATA BYTE 10, 14, 0
	DATA BYTE 8, 14, 0
	DATA BYTE 3, 14, 0
	DATA BYTE 5, 14, 0
	DATA BYTE 13, 14, 0
	DATA BYTE 4, 14, 0
	DATA BYTE 1, 14, 0
	DATA BYTE 1, 14, 0
	DATA BYTE 6, 14, 0
	DATA BYTE 15, 14, 0
	DATA BYTE 15, 14, 0

cola:	' rooms 13-38: coloured walls on GRAY, except the dark
	' mazes (gray walls on black) - the black castle is BLACK
	DATA BYTE 11, 14, 0	' 13 gold grounds
	DATA BYTE 10, 14, 0	' 14 gold hall
	DATA BYTE 12, 14, 0	' 15 corridor W (olive)
	DATA BYTE 2, 14, 0	' 16 corridor mid (green)
	DATA BYTE 11, 14, 0	' 17 corridor E (yellow)
	DATA BYTE 13, 14, 0	' 18 secret room (purple)
	DATA BYTE 4, 14, 0	' 19 blue maze
	DATA BYTE 4, 14, 0	' 20
	DATA BYTE 4, 14, 0	' 21
	DATA BYTE 4, 14, 0	' 22
	DATA BYTE 4, 14, 0	' 23
	DATA BYTE 1, 14, 0	' 24 BLACK castle on gray
	DATA BYTE 1, 14, 0	' 25 black hall
	DATA BYTE 14, 1, 1	' 26 black maze: dark
	DATA BYTE 14, 1, 1	' 27
	DATA BYTE 14, 1, 1	' 28
	DATA BYTE 14, 1, 1	' 29 catacombs: dark
	DATA BYTE 14, 1, 1	' 30
	DATA BYTE 14, 1, 1	' 31
	DATA BYTE 15, 14, 0	' 32 white castle
	DATA BYTE 15, 14, 0	' 33 white hall
	DATA BYTE 8, 14, 0	' 34 red maze
	DATA BYTE 8, 14, 0	' 35
	DATA BYTE 13, 14, 0	' 36 purple room
	DATA BYTE 7, 14, 0	' 37 cyan room
	DATA BYTE 9, 14, 0	' 38 rose room

	' ------------------------------------------------------------
	' per-game world: 8 objects (room,x,y) in order gold key,
	' black key, white key, sword, bridge, chalice, magnet, dot;
	' then 3 dragons (room,x,y,colour,fast); bat (room,x,y);
	' start room; win room. room 255 = not in this game.
	' ------------------------------------------------------------
objd1:	' GAME 1 custom intro map
	DATA BYTE 4, 180, 120
	DATA BYTE 6, 180, 20
	DATA BYTE 7, 120, 88
	DATA BYTE 3, 120, 24
	DATA BYTE 12, 96, 80
	DATA BYTE 10, 120, 88
	DATA BYTE 255, 0, 0
	DATA BYTE 255, 0, 0
	DATA BYTE 8, 36, 80, 11, 0
	DATA BYTE 6, 140, 72, 2, 0
	DATA BYTE 7, 104, 40, 8, 1
	DATA BYTE 5, 120, 60
	DATA BYTE 0, 2

objd2:	' GAME 2 small kingdom: two castles, two dragons, no bat
	DATA BYTE 15, 60, 88
	DATA BYTE 21, 180, 108
	DATA BYTE 255, 0, 0
	DATA BYTE 14, 120, 120
	DATA BYTE 255, 0, 0
	DATA BYTE 25, 180, 120
	DATA BYTE 25, 60, 120
	DATA BYTE 255, 0, 0
	DATA BYTE 23, 104, 72, 11, 0
	DATA BYTE 24, 48, 88, 2, 0
	DATA BYTE 255, 0, 0, 8, 1
	DATA BYTE 255, 0, 0
	DATA BYTE 13, 14

objd3:	' GAMES 3/4 full kingdom
	DATA BYTE 30, 116, 88
	DATA BYTE 35, 184, 32
	DATA BYTE 21, 36, 40
	DATA BYTE 16, 60, 88
	DATA BYTE 31, 180, 88
	DATA BYTE 28, 60, 88
	DATA BYTE 27, 116, 152
	DATA BYTE 28, 184, 24
	DATA BYTE 17, 48, 88, 11, 0
	DATA BYTE 29, 104, 64, 2, 0
	DATA BYTE 20, 104, 60, 8, 1
	DATA BYTE 19, 120, 60
	DATA BYTE 13, 14

	' ------------------------------------------------------------
	' rooms: 24 rows x 32 cells, 4 bytes/row (MSB = leftmost).
	' Rooms 0-12 (custom intro map) are the old block layouts
	' mechanically doubled to the fine grid - game 1 is pixel-
	' identical. Rooms 13-38 are fine-grid originals (BITMAP art,
	' two 16-cell halves per row).
	' ------------------------------------------------------------
rd0:	' --- 0 gold castle grounds ---
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $CF, $00, $00, $F3
	DATA BYTE $CF, $00, $00, $F3
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
rd1:	' --- 1 north meadow ---
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $00, $00, $00, $00
	DATA BYTE $00, $00, $00, $00
	DATA BYTE $00, $00, $00, $00
	DATA BYTE $00, $00, $00, $00
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
rd2:	' --- 2 gold castle hall (custom WIN) ---
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C3, $C0, $03, $C3
	DATA BYTE $C3, $C0, $03, $C3
	DATA BYTE $C3, $C0, $03, $C3
	DATA BYTE $C3, $C0, $03, $C3
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
rd3:	' --- 3 red corridor ---
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $FF, $FF, $03
	DATA BYTE $C0, $FF, $FF, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $00, $00, $00, $00
	DATA BYTE $00, $00, $00, $00
	DATA BYTE $00, $00, $00, $00
	DATA BYTE $00, $00, $00, $00
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $FF, $FF, $03
	DATA BYTE $C0, $FF, $FF, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
rd4:	' --- 4 south meadow ---
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $00
	DATA BYTE $C0, $00, $00, $00
	DATA BYTE $C0, $00, $00, $00
	DATA BYTE $C0, $00, $00, $00
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $3F, $FC, $03
	DATA BYTE $C0, $3F, $FC, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
rd5:	' --- 5 blue maze north ---
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $CF, $FC, $3F, $F3
	DATA BYTE $CF, $FC, $3F, $F3
	DATA BYTE $C0, $0C, $30, $03
	DATA BYTE $C0, $0C, $30, $03
	DATA BYTE $CF, $0C, $30, $F3
	DATA BYTE $CF, $0C, $30, $F3
	DATA BYTE $00, $0C, $30, $03
	DATA BYTE $00, $0C, $30, $03
	DATA BYTE $00, $0C, $30, $03
	DATA BYTE $00, $0C, $30, $03
	DATA BYTE $CF, $0C, $30, $F3
	DATA BYTE $CF, $0C, $30, $F3
	DATA BYTE $C0, $0C, $30, $03
	DATA BYTE $C0, $0C, $30, $03
	DATA BYTE $CF, $FC, $3F, $F3
	DATA BYTE $CF, $FC, $3F, $F3
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
rd6:	' --- 6 purple cave + sealed chamber ---
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $C0, $00, $0C, $33
	DATA BYTE $C0, $00, $0C, $33
	DATA BYTE $C0, $00, $0C, $33
	DATA BYTE $C0, $00, $0C, $33
	DATA BYTE $C0, $00, $0F, $F3
	DATA BYTE $C0, $00, $0F, $F3
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $00, $00, $00, $00
	DATA BYTE $00, $00, $00, $00
	DATA BYTE $00, $00, $00, $00
	DATA BYTE $00, $00, $00, $00
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $3F, $FC, $03
	DATA BYTE $C0, $3F, $FC, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
rd7:	' --- 7 blue maze south ---
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C3, $FC, $3F, $C3
	DATA BYTE $C3, $FC, $3F, $C3
	DATA BYTE $C3, $0C, $30, $C3
	DATA BYTE $C3, $0C, $30, $C3
	DATA BYTE $C3, $0C, $30, $C3
	DATA BYTE $C3, $0C, $30, $C3
	DATA BYTE $03, $0C, $30, $C0
	DATA BYTE $03, $0C, $30, $C0
	DATA BYTE $03, $0C, $30, $C0
	DATA BYTE $03, $0C, $30, $C0
	DATA BYTE $C3, $0C, $30, $C3
	DATA BYTE $C3, $0C, $30, $C3
	DATA BYTE $C3, $0C, $30, $C3
	DATA BYTE $C3, $0C, $30, $C3
	DATA BYTE $C3, $FC, $3F, $C3
	DATA BYTE $C3, $FC, $3F, $C3
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
rd8:	' --- 8 black castle grounds (custom) ---
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $CF, $00, $00, $F3
	DATA BYTE $CF, $00, $00, $F3
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $00, $00, $00, $03
	DATA BYTE $00, $00, $00, $03
	DATA BYTE $00, $00, $00, $03
	DATA BYTE $00, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
rd9:	' --- 9 black castle hall (custom) ---
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C3, $C0, $03, $C3
	DATA BYTE $C3, $C0, $03, $C3
	DATA BYTE $C3, $C0, $03, $C3
	DATA BYTE $C3, $C0, $03, $C3
	DATA BYTE $C0, $00, $00, $00
	DATA BYTE $C0, $00, $00, $00
	DATA BYTE $C0, $00, $00, $00
	DATA BYTE $C0, $00, $00, $00
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
rd10:	' --- 10 dungeon (custom) ---
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $CF, $C0, $03, $F3
	DATA BYTE $CF, $C0, $03, $F3
	DATA BYTE $C0, $C0, $03, $03
	DATA BYTE $C0, $C0, $03, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $00, $00, $00, $03
	DATA BYTE $00, $00, $00, $03
	DATA BYTE $00, $00, $00, $03
	DATA BYTE $00, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $C0, $03, $03
	DATA BYTE $C0, $C0, $03, $03
	DATA BYTE $CF, $C0, $03, $F3
	DATA BYTE $CF, $C0, $03, $F3
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
rd11:	' --- 11 white castle grounds (custom) ---
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $CF, $00, $00, $F3
	DATA BYTE $CF, $00, $00, $F3
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $00
	DATA BYTE $C0, $00, $00, $00
	DATA BYTE $C0, $00, $00, $00
	DATA BYTE $C0, $00, $00, $00
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
rd12:	' --- 12 white castle hall (custom) ---
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $FF, $FF, $FF, $FF
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C3, $C0, $03, $C3
	DATA BYTE $C3, $C0, $03, $C3
	DATA BYTE $C3, $C0, $03, $C3
	DATA BYTE $C3, $C0, $03, $C3
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $C0, $00, $00, $03
	DATA BYTE $FF, $FC, $3F, $FF
	DATA BYTE $FF, $FC, $3F, $FF
rd13:	' --- 13 gold castle grounds (kingdom): crenellated keep ---
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $9B, $6C, $36, $D9	' X__XX_XX_XX_XX____XX_XX_XX_XX__X
	DATA BYTE $9F, $FF, $FF, $F9	' X__XXXXXXXXXXXXXXXXXXXXXXXXXX__X
	DATA BYTE $9F, $FC, $3F, $F9	' X__XXXXXXXXXXX____XXXXXXXXXXX__X
	DATA BYTE $9F, $FC, $3F, $F9	' X__XXXXXXXXXXX____XXXXXXXXXXX__X
	DATA BYTE $9F, $FC, $3F, $F9	' X__XXXXXXXXXXX____XXXXXXXXXXX__X
	DATA BYTE $9F, $FC, $3F, $F9	' X__XXXXXXXXXXX____XXXXXXXXXXX__X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
rd14:	' --- 14 gold castle hall (kingdom WIN) ---
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $83, $C0, $03, $C1	' X_____XXXX____________XXXX_____X
	DATA BYTE $83, $C0, $03, $C1	' X_____XXXX____________XXXX_____X
	DATA BYTE $83, $C0, $03, $C1	' X_____XXXX____________XXXX_____X
	DATA BYTE $83, $C0, $03, $C1	' X_____XXXX____________XXXX_____X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
rd15:	' --- 15 corridor west (open E/W) ---
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
rd16:	' --- 16 corridor mid (N gap to the gold castle) ---
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $00, $00, $00, $00	' ________________________________
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
rd17:	' --- 17 corridor east (secret wall E, catacombs S) ---
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $00, $00, $00, $03	' ______________________________XX
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
rd18:	' --- 18 SECRET room ---
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
rd19:	' --- 19 blue maze SE (N/E/W; twin N gaps, dead-end nook) ---
	DATA BYTE $FC, $FF, $FF, $F3	' XXXXXX__XXXXXXXXXXXXXXXXXXXX__XX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $F3, $F3, $FF	' XXXXXXXXXXXX__XXXXXX__XXXXXXXXXX
	DATA BYTE $84, $00, $00, $01	' X____X_________________________X
	DATA BYTE $84, $00, $00, $01	' X____X_________________________X
	DATA BYTE $CF, $CF, $FF, $FF	' XX__XXXXXX__XXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $FF, $FF, $FC, $FF	' XXXXXXXXXXXXXXXXXXXXXX__XXXXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $FF, $3F, $FF, $FF	' XXXXXXXX__XXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $10, $40, $01	' X__________X_____X_____________X
	DATA BYTE $80, $10, $40, $01	' X__________X_____X_____________X
	DATA BYTE $FF, $FC, $FF, $FF	' XXXXXXXXXXXXXX__XXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $F3, $FF, $FF, $CF	' XXXX__XXXXXXXXXXXXXXXXXXXX__XXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $40, $01, $01	' X________X_____________X_______X
	DATA BYTE $80, $40, $01, $01	' X________X_____________X_______X
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
rd20:	' --- 20 blue maze mid (all sides; twin W doors, twin S gaps) ---
	DATA BYTE $FF, $CF, $FF, $FF	' XXXXXXXXXX__XXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FC, $FF, $FF, $3F	' XXXXXX__XXXXXXXXXXXXXXXX__XXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $FF, $FC, $FF, $FF	' XXXXXXXXXXXXXX__XXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $09	' X___________________________X__X
	DATA BYTE $80, $00, $00, $09	' X___________________________X__X
	DATA BYTE $CF, $FF, $FF, $F3	' XX__XXXXXXXXXXXXXXXXXXXXXXXX__XX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $81, $00, $00, $81	' X______X________________X______X
	DATA BYTE $FF, $F3, $F3, $FF	' XXXXXXXXXXXX__XXXXXX__XXXXXXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $F3, $FF, $FF, $FF	' XXXX__XXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $21	' X_________________________X____X
	DATA BYTE $80, $00, $00, $21	' X_________________________X____X
	DATA BYTE $FF, $FF, $F3, $F3	' XXXXXXXXXXXXXXXXXXXX__XXXXXX__XX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $81, $80, $03, $01	' X______XX_____________XX_______X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FC, $FF, $FF, $CF	' XXXXXX__XXXXXXXXXXXXXXXXXX__XXXX
rd21:	' --- 21 blue maze cross (all sides; twin N gaps, twin E doors) ---
	DATA BYTE $F3, $FF, $FF, $3F	' XXXX__XXXXXXXXXXXXXXXXXX__XXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $3F, $F3, $FF	' XXXXXXXX__XXXXXXXXXX__XXXXXXXXXX
	DATA BYTE $80, $02, $00, $01	' X_____________X________________X
	DATA BYTE $80, $02, $00, $01	' X_____________X________________X
	DATA BYTE $CF, $FF, $FF, $CF	' XX__XXXXXXXXXXXXXXXXXXXXXX__XXXX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $FF, $F3, $FC, $FF	' XXXXXXXXXXXX__XXXXXXXX__XXXXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $F3, $FF, $FF, $F3	' XXXX__XXXXXXXXXXXXXXXXXXXXXX__XX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $CF, $CF, $FF	' XXXXXXXXXX__XXXXXX__XXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $FC, $FF, $FF, $FF	' XXXXXX__XXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $20, $08, $01	' X_________X_________X__________X
	DATA BYTE $80, $20, $08, $01	' X_________X_________X__________X
	DATA BYTE $80, $20, $08, $01	' X_________X_________X__________X
	DATA BYTE $FF, $FF, $CF, $FF	' XXXXXXXXXXXXXXXXXX__XXXXXXXXXXXX
rd22:	' --- 22 blue maze W branch (N/E/S; twin N gaps, pockets) ---
	DATA BYTE $FF, $3F, $FC, $FF	' XXXXXXXX__XXXXXXXXXXXX__XXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $F3, $FF, $FF, $CF	' XXXX__XXXXXXXXXXXXXXXXXXXX__XXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $CF, $FF, $FF	' XXXXXXXXXX__XXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $08, $01	' X___________________X__________X
	DATA BYTE $80, $00, $08, $01	' X___________________X__________X
	DATA BYTE $FF, $FC, $FF, $3F	' XXXXXXXXXXXXXX__XXXXXXXX__XXXXXX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $CF, $FF, $FF, $FF	' XX__XXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $F3, $FF, $FF	' XXXXXXXXXXXX__XXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $02, $01	' X_____________________X________X
	DATA BYTE $80, $00, $02, $01	' X_____________________X________X
	DATA BYTE $FC, $FF, $FF, $CF	' XXXXXX__XXXXXXXXXXXXXXXXXX__XXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $F3, $FF, $FF	' XXXXXXXXXXXX__XXXXXXXXXXXXXXXXXX
rd23:	' --- 23 blue maze top (all sides; N to the black castle) ---
	DATA BYTE $F3, $FF, $FF, $3F	' XXXX__XXXXXXXXXXXXXXXXXX__XXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $3F, $F3, $FF	' XXXXXXXX__XXXXXXXXXX__XXXXXXXXXX
	DATA BYTE $80, $02, $00, $01	' X_____________X________________X
	DATA BYTE $80, $02, $00, $01	' X_____________X________________X
	DATA BYTE $CF, $FF, $FF, $CF	' XX__XXXXXXXXXXXXXXXXXXXXXX__XXXX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $FF, $F3, $FC, $FF	' XXXXXXXXXXXX__XXXXXXXX__XXXXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $F3, $FF, $FF, $F3	' XXXX__XXXXXXXXXXXXXXXXXXXXXX__XX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $CF, $CF, $FF	' XXXXXXXXXX__XXXXXX__XXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $FC, $FF, $FF, $FF	' XXXXXX__XXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $20, $08, $01	' X_________X_________X__________X
	DATA BYTE $80, $20, $08, $01	' X_________X_________X__________X
	DATA BYTE $80, $20, $08, $01	' X_________X_________X__________X
	DATA BYTE $FF, $FF, $CF, $FF	' XXXXXXXXXXXXXXXXXX__XXXXXXXXXXXX
rd24:	' --- 24 BLACK castle grounds (S to the blue maze) ---
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $9B, $6C, $36, $D9	' X__XX_XX_XX_XX____XX_XX_XX_XX__X
	DATA BYTE $9F, $FF, $FF, $F9	' X__XXXXXXXXXXXXXXXXXXXXXXXXXX__X
	DATA BYTE $9F, $FC, $3F, $F9	' X__XXXXXXXXXXX____XXXXXXXXXXX__X
	DATA BYTE $9F, $FC, $3F, $F9	' X__XXXXXXXXXXX____XXXXXXXXXXX__X
	DATA BYTE $9F, $FC, $3F, $F9	' X__XXXXXXXXXXX____XXXXXXXXXXX__X
	DATA BYTE $9F, $FC, $3F, $F9	' X__XXXXXXXXXXX____XXXXXXXXXXX__X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
rd25:	' --- 25 black castle hall (E to the dark maze) ---
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $83, $C0, $03, $C1	' X_____XXXX____________XXXX_____X
	DATA BYTE $83, $C0, $03, $C1	' X_____XXXX____________XXXX_____X
	DATA BYTE $83, $C0, $03, $C0	' X_____XXXX____________XXXX______
	DATA BYTE $83, $C0, $03, $C0	' X_____XXXX____________XXXX______
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
rd26:	' --- 26 black maze (dark; N/E/W) ---
	DATA BYTE $FC, $FF, $FF, $F3	' XXXXXX__XXXXXXXXXXXXXXXXXXXX__XX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $F3, $F3, $FF	' XXXXXXXXXXXX__XXXXXX__XXXXXXXXXX
	DATA BYTE $84, $00, $00, $01	' X____X_________________________X
	DATA BYTE $84, $00, $00, $01	' X____X_________________________X
	DATA BYTE $CF, $CF, $FF, $FF	' XX__XXXXXX__XXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $FF, $FF, $FC, $FF	' XXXXXXXXXXXXXXXXXXXXXX__XXXXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $FF, $3F, $FF, $FF	' XXXXXXXX__XXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $10, $40, $01	' X__________X_____X_____________X
	DATA BYTE $80, $10, $40, $01	' X__________X_____X_____________X
	DATA BYTE $FF, $FC, $FF, $FF	' XXXXXXXXXXXXXX__XXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $F3, $FF, $FF, $CF	' XXXX__XXXXXXXXXXXXXXXXXXXX__XXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $40, $01, $01	' X________X_____________X_______X
	DATA BYTE $80, $40, $01, $01	' X________X_____________X_______X
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
rd27:	' --- 27 black maze (dark; all sides) ---
	DATA BYTE $FF, $CF, $FF, $FF	' XXXXXXXXXX__XXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FC, $FF, $FF, $3F	' XXXXXX__XXXXXXXXXXXXXXXX__XXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $FF, $FC, $FF, $FF	' XXXXXXXXXXXXXX__XXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $09	' X___________________________X__X
	DATA BYTE $80, $00, $00, $09	' X___________________________X__X
	DATA BYTE $CF, $FF, $FF, $F3	' XX__XXXXXXXXXXXXXXXXXXXXXXXX__XX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $81, $00, $00, $81	' X______X________________X______X
	DATA BYTE $FF, $F3, $F3, $FF	' XXXXXXXXXXXX__XXXXXX__XXXXXXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $F3, $FF, $FF, $FF	' XXXX__XXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $21	' X_________________________X____X
	DATA BYTE $80, $00, $00, $21	' X_________________________X____X
	DATA BYTE $FF, $FF, $F3, $F3	' XXXXXXXXXXXXXXXXXXXX__XXXXXX__XX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $81, $80, $03, $01	' X______XX_____________XX_______X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FC, $FF, $FF, $CF	' XXXXXX__XXXXXXXXXXXXXXXXXX__XXXX
rd28:	' --- 28 black maze end: sealed DOT chamber (dark; S/W) ---
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $0F, $F1	' X___________________XXXXXXXX___X
	DATA BYTE $80, $00, $08, $11	' X___________________X______X___X
	DATA BYTE $90, $00, $08, $11	' X__X________________X______X___X
	DATA BYTE $90, $00, $08, $11	' X__X________________X______X___X
	DATA BYTE $90, $00, $08, $11	' X__X________________X______X___X
	DATA BYTE $80, $00, $0F, $F1	' X___________________XXXXXXXX___X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $3F, $F3, $FF	' XXXXXXXX__XXXXXXXXXX__XXXXXXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $FF, $FC, $FF, $3F	' XXXXXXXXXXXXXX__XXXXXXXX__XXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $82, $00, $00, $41	' X_____X__________________X_____X
	DATA BYTE $82, $00, $00, $41	' X_____X__________________X_____X
	DATA BYTE $F3, $FF, $FF, $CF	' XXXX__XXXXXXXXXXXXXXXXXXXX__XXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $F3, $FF, $3F	' XXXXXXXXXXXX__XXXXXXXXXX__XXXXXX
	DATA BYTE $80, $00, $02, $01	' X_____________________X________X
	DATA BYTE $80, $00, $02, $01	' X_____________________X________X
	DATA BYTE $80, $00, $02, $01	' X_____________________X________X
	DATA BYTE $FC, $FF, $FF, $FF	' XXXXXX__XXXXXXXXXXXXXXXXXXXXXXXX
rd29:	' --- 29 catacombs (dark; all sides) ---
	DATA BYTE $F3, $FF, $FF, $3F	' XXXX__XXXXXXXXXXXXXXXXXX__XXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $3F, $F3, $FF	' XXXXXXXX__XXXXXXXXXX__XXXXXXXXXX
	DATA BYTE $80, $02, $00, $01	' X_____________X________________X
	DATA BYTE $80, $02, $00, $01	' X_____________X________________X
	DATA BYTE $CF, $FF, $FF, $CF	' XX__XXXXXXXXXXXXXXXXXXXXXX__XXXX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $FF, $F3, $FC, $FF	' XXXXXXXXXXXX__XXXXXXXX__XXXXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $F3, $FF, $FF, $F3	' XXXX__XXXXXXXXXXXXXXXXXXXXXX__XX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $CF, $CF, $FF	' XXXXXXXXXX__XXXXXX__XXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $FC, $FF, $FF, $FF	' XXXXXX__XXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $20, $08, $01	' X_________X_________X__________X
	DATA BYTE $80, $20, $08, $01	' X_________X_________X__________X
	DATA BYTE $80, $20, $08, $01	' X_________X_________X__________X
	DATA BYTE $FF, $FF, $CF, $FF	' XXXXXXXXXXXXXXXXXX__XXXXXXXXXXXX
rd30:	' --- 30 catacombs (dark; all sides) ---
	DATA BYTE $FF, $CF, $FF, $FF	' XXXXXXXXXX__XXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FC, $FF, $FF, $3F	' XXXXXX__XXXXXXXXXXXXXXXX__XXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $FF, $FC, $FF, $FF	' XXXXXXXXXXXXXX__XXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $09	' X___________________________X__X
	DATA BYTE $80, $00, $00, $09	' X___________________________X__X
	DATA BYTE $CF, $FF, $FF, $F3	' XX__XXXXXXXXXXXXXXXXXXXXXXXX__XX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $81, $00, $00, $81	' X______X________________X______X
	DATA BYTE $FF, $F3, $F3, $FF	' XXXXXXXXXXXX__XXXXXX__XXXXXXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $F3, $FF, $FF, $FF	' XXXX__XXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $21	' X_________________________X____X
	DATA BYTE $80, $00, $00, $21	' X_________________________X____X
	DATA BYTE $FF, $FF, $F3, $F3	' XXXXXXXXXXXXXXXXXXXX__XXXXXX__XX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $81, $80, $03, $01	' X______XX_____________XX_______X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FC, $FF, $FF, $CF	' XXXXXX__XXXXXXXXXXXXXXXXXX__XXXX
rd31:	' --- 31 catacombs south (dark; W white castle, E side rooms) ---
	DATA BYTE $FC, $FF, $FF, $F3	' XXXXXX__XXXXXXXXXXXXXXXXXXXX__XX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $F3, $F3, $FF	' XXXXXXXXXXXX__XXXXXX__XXXXXXXXXX
	DATA BYTE $84, $00, $00, $01	' X____X_________________________X
	DATA BYTE $84, $00, $00, $01	' X____X_________________________X
	DATA BYTE $CF, $CF, $FF, $FF	' XX__XXXXXX__XXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $FF, $FF, $FC, $FF	' XXXXXXXXXXXXXXXXXXXXXX__XXXXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $FF, $3F, $FF, $FF	' XXXXXXXX__XXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $10, $40, $01	' X__________X_____X_____________X
	DATA BYTE $80, $10, $40, $01	' X__________X_____X_____________X
	DATA BYTE $FF, $FC, $FF, $FF	' XXXXXXXXXXXXXX__XXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $F3, $FF, $FF, $CF	' XXXX__XXXXXXXXXXXXXXXXXXXX__XXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $40, $01, $01	' X________X_____________X_______X
	DATA BYTE $80, $40, $01, $01	' X________X_____________X_______X
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
rd32:	' --- 32 white castle grounds (E to catacombs) ---
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $9B, $6C, $36, $D9	' X__XX_XX_XX_XX____XX_XX_XX_XX__X
	DATA BYTE $9F, $FF, $FF, $F9	' X__XXXXXXXXXXXXXXXXXXXXXXXXXX__X
	DATA BYTE $9F, $FC, $3F, $F9	' X__XXXXXXXXXXX____XXXXXXXXXXX__X
	DATA BYTE $9F, $FC, $3F, $F9	' X__XXXXXXXXXXX____XXXXXXXXXXX__X
	DATA BYTE $9F, $FC, $3F, $F9	' X__XXXXXXXXXXX____XXXXXXXXXXX__X
	DATA BYTE $9F, $FC, $3F, $F9	' X__XXXXXXXXXXX____XXXXXXXXXXX__X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
rd33:	' --- 33 white castle hall (E to the red maze) ---
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $83, $C0, $03, $C1	' X_____XXXX____________XXXX_____X
	DATA BYTE $83, $C0, $03, $C1	' X_____XXXX____________XXXX_____X
	DATA BYTE $83, $C0, $03, $C0	' X_____XXXX____________XXXX______
	DATA BYTE $83, $C0, $03, $C0	' X_____XXXX____________XXXX______
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
rd34:	' --- 34 red maze (N/E/W) ---
	DATA BYTE $FC, $FF, $FF, $F3	' XXXXXX__XXXXXXXXXXXXXXXXXXXX__XX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $F3, $F3, $FF	' XXXXXXXXXXXX__XXXXXX__XXXXXXXXXX
	DATA BYTE $84, $00, $00, $01	' X____X_________________________X
	DATA BYTE $84, $00, $00, $01	' X____X_________________________X
	DATA BYTE $CF, $CF, $FF, $FF	' XX__XXXXXX__XXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $80, $00, $00, $00	' X_______________________________
	DATA BYTE $FF, $FF, $FC, $FF	' XXXXXXXXXXXXXXXXXXXXXX__XXXXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $FF, $3F, $FF, $FF	' XXXXXXXX__XXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $10, $40, $01	' X__________X_____X_____________X
	DATA BYTE $80, $10, $40, $01	' X__________X_____X_____________X
	DATA BYTE $FF, $FC, $FF, $FF	' XXXXXXXXXXXXXX__XXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $F3, $FF, $FF, $CF	' XXXX__XXXXXXXXXXXXXXXXXXXX__XXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $40, $01, $01	' X________X_____________X_______X
	DATA BYTE $80, $40, $01, $01	' X________X_____________X_______X
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
rd35:	' --- 35 red maze end: BLACK KEY sealed in a chamber (S/W) ---
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $0F, $F1	' X___________________XXXXXXXX___X
	DATA BYTE $80, $00, $08, $11	' X___________________X______X___X
	DATA BYTE $90, $00, $08, $11	' X__X________________X______X___X
	DATA BYTE $90, $00, $08, $11	' X__X________________X______X___X
	DATA BYTE $90, $00, $08, $11	' X__X________________X______X___X
	DATA BYTE $80, $00, $0F, $F1	' X___________________XXXXXXXX___X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $3F, $F3, $FF	' XXXXXXXX__XXXXXXXXXX__XXXXXXXXXX
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $FF, $FC, $FF, $3F	' XXXXXXXXXXXXXX__XXXXXXXX__XXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $82, $00, $00, $41	' X_____X__________________X_____X
	DATA BYTE $82, $00, $00, $41	' X_____X__________________X_____X
	DATA BYTE $F3, $FF, $FF, $CF	' XXXX__XXXXXXXXXXXXXXXXXXXX__XXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $F3, $FF, $3F	' XXXXXXXXXXXX__XXXXXXXXXX__XXXXXX
	DATA BYTE $80, $00, $02, $01	' X_____________________X________X
	DATA BYTE $80, $00, $02, $01	' X_____________________X________X
	DATA BYTE $80, $00, $02, $01	' X_____________________X________X
	DATA BYTE $FC, $FF, $FF, $FF	' XXXXXX__XXXXXXXXXXXXXXXXXXXXXXXX
rd36:	' --- 36 purple side room ---
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $00, $00, $00, $01	' _______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
rd37:	' --- 37 cyan side room ---
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $83, $C0, $03, $C1	' X_____XXXX____________XXXX_____X
	DATA BYTE $83, $C0, $03, $C1	' X_____XXXX____________XXXX_____X
	DATA BYTE $83, $C0, $03, $C1	' X_____XXXX____________XXXX_____X
	DATA BYTE $83, $C0, $03, $C1	' X_____XXXX____________XXXX_____X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
rd38:	' --- 38 rose side room ---
	DATA BYTE $FF, $FC, $3F, $FF	' XXXXXXXXXXXXXX____XXXXXXXXXXXXXX
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $3F, $FC, $01	' X_________XXXXXXXXXXXX_________X
	DATA BYTE $80, $3F, $FC, $01	' X_________XXXXXXXXXXXX_________X
	DATA BYTE $80, $3F, $FC, $01	' X_________XXXXXXXXXXXX_________X
	DATA BYTE $80, $3F, $FC, $01	' X_________XXXXXXXXXXXX_________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $80, $00, $00, $01	' X______________________________X
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	DATA BYTE $FF, $FF, $FF, $FF	' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

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
	' 0 player (kept 8x8 on screen), 1 dragon top half (head/
	' neck), 2 dragon bottom half (body/legs) - together 32x64,
	' 3 slain dragon, 4 key, 5 sword, 6 chalice, 7 bridge,
	' 8 bat A, 9 bat B, 10 bridge channel fill, 11 magnet, 12 dot
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

	BITMAP "_____XXX________"
	BITMAP "____XXXXX_______"
	BITMAP "____XX_XX_______"
	BITMAP "____XXXXX_______"
	BITMAP "____XXX_________"
	BITMAP "_____XX_________"
	BITMAP "_____XX_________"
	BITMAP "_____XXX________"
	BITMAP "_____XXX________"
	BITMAP "____XXXX____X___"
	BITMAP "____XXXX___XX___"
	BITMAP "___XXXXX__XXX___"
	BITMAP "___XXXXXX_XX____"
	BITMAP "__XXXXXXXXXX____"
	BITMAP "__XXXXXXXXXX____"
	BITMAP "_XXXXXXXXXXX____"

	BITMAP "_XXXXXXXXXX_____"
	BITMAP "XXXXXXXXXXX_____"
	BITMAP "XX_XXXXXXXX_____"
	BITMAP "X__XXXXXXX______"
	BITMAP "___XXXXXXX______"
	BITMAP "___XXXXXXX______"
	BITMAP "__XXXXXXXX______"
	BITMAP "__XXX__XXXX_____"
	BITMAP "__XX____XX______"
	BITMAP "__XX____XX______"
	BITMAP "__XX____XX______"
	BITMAP "_XXX____XXX_____"
	BITMAP "_XX______XX_____"
	BITMAP "XXX______XXX____"
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

	BITMAP "_XX__________XX_"
	BITMAP "_XX__________XX_"
	BITMAP "_XX__________XX_"
	BITMAP "_XX__________XX_"
	BITMAP "___XX______XX___"
	BITMAP "___XX______XX___"
	BITMAP "_____XXXXXX_____"
	BITMAP "_____XXXXXX_____"
	BITMAP "_______XX_______"
	BITMAP "_______XX_______"
	BITMAP "_______XX_______"
	BITMAP "_______XX_______"
	BITMAP "___XXXXXXXXXX___"
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

	BITMAP "_XXX______XXX___"
	BITMAP "_XXX______XXX___"
	BITMAP "_XXX______XXX___"
	BITMAP "_XXX______XXX___"
	BITMAP "_XXX______XXX___"
	BITMAP "_XXXX____XXXX___"
	BITMAP "__XXXXXXXXXX____"
	BITMAP "___XXXXXXXX_____"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"
	BITMAP "________________"

	BITMAP "X_______________"
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
	BITMAP "________________"
	BITMAP "________________"
