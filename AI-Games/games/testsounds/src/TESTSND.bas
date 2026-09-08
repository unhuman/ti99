	' ======================================================================
	' TESTSOUNDS -- a bench for Keystone Kapers' sound effects
	' ======================================================================
	' A DIGIT PICKS THE CATEGORY, A LETTER PLAYS THE VARIANT. Press 4 for
	' PICKUP, then C and H and C again -- one key each, and the category stays
	' where it is. The ">" says which one is held.
	'
	' IT USED TO CYCLE, and cycling is fine for hearing a set once and useless
	' for the thing you actually do with it: A/B a PAIR over and over until one
	' of them is obviously right. Cycling makes you walk past everything in
	' between and lose the comparison on the way.
	'
	' LETTERS WORK BECAUSE THE TI RETURNS THEM. cont1.key on the TI-99/4A gives
	' uppercase ASCII from the keyboard as well as the stock 0-9 -- the keypad
	' digits come back as 0-9 and the letters as 65 upwards, so the two ranges
	' cannot collide. This was very nearly built on digits alone in the belief
	' that cont1.key was keypad-only; that is true of the ColecoVision and it
	' is not true here.
	'
	' ON COLECOVISION THERE IS NO KEYBOARD, so FIRE is kept as a way through
	' the variants of the held category. The bench is a TI tool in practice,
	' but a control scheme that silently does nothing on the other target is
	' not one worth shipping.
	'
	' Anything else is IGNORED -- an unknown key, a digit above 6, a letter
	' past the end of the category. Not clamped: a four-variant category does
	' nothing on E-J rather than quietly replaying its last one and leaving you
	' wondering whether you misheard.
	'
	' WHY IT EXISTS. The game's effects were hand-picked divisors that had
	' never been compared with anything. These are measured off an Atari 2600
	' recording (assets/sfxref.md has the workings and the method), and tuning
	' them by editing the game, rebuilding and playing to the right screen is
	' hopeless -- here it is a keypress.
	'
	' VARIANT A OF EVERY CATEGORY IS THE MEASURED ONE. The rest are departures
	' from it, so the reference is always one key away and the comparison is
	' never against memory.
	'
	' WHAT THE REFERENCE SAYS, and the first pass of the analysis got this
	' wrong in a way worth recording. Autocorrelation reported every effect as
	' noise, because the running sound plays underneath all of them and drags
	' the confidence of a pitch estimate down. Direct energy measurement at
	' fixed frequencies says otherwise: only the RUNNING and the TALLY ticks
	' are noise, and the pickup RISES where the hit FALLS -- which is the
	' difference between a reward and a penalty, and the thing the first pass
	' hid by filing both as "noise, about 660 ms".
	'
	' Dual target: TI-99/4A and ColecoVision, same SN76489 either way.

	CONST SILENCE = 255		' a step's channel meaning "everything off"
	CONST NOISE = 3			' SN76489 channel 3 is the noise generator
	CONST ENDTAB = 255		' a step's FRAME count meaning "end of table"
	CONST NOWAIT = 254		' ... and one meaning "set it and carry on"
	CONST NCAT = 6

	DIM stp(4)
	DIM #fxoff(48)			' where each effect starts, in bytes
	DIM catfst(NCAT)		' first effect of each category
	DIM catnum(NCAT)		' how many variants it has
	DIM catcur(NCAT)		' which one plays next

	SOUND 0,,0
	SOUND 1,,0
	SOUND 2,,0
	SOUND 3,,0

	' THE CATEGORY MAP. Effects are numbered in the order they appear in
	' fx_data; these say which run belongs to which key. It is a hand-written
	' index into generated-looking data, so it is the thing most likely to
	' drift -- if a category plays the wrong sound, look here first.
	catfst(0) = 0  : catnum(0) = 10		' 1 RUN
	catfst(1) = 10 : catnum(1) = 4		' 2 JUMP
	catfst(2) = 14 : catnum(2) = 3		' 3 TIME UP
	catfst(3) = 17 : catnum(3) = 10		' 4 PICKUP
	catfst(4) = 27 : catnum(4) = 8		' 5 HIT
	catfst(5) = 35 : catnum(5) = 3		' 6 TALLY

	GOSUB scan_fx
	GOSUB draw_menu

	' WAIT FOR RELEASE BEFORE LISTENING TO ANYTHING. The keypress that chose
	' this cart from the TI menu is still being reported on the first pass in
	' here, so without this the program plays a variant nobody asked for --
	' and worse, ADVANCES that category to B, so the first deliberate press
	' gives the wrong one and every letter after it is off by one.
	'
	' Same fault and same fix as the 838 page in Keystone Kapers, where the
	' final 8 of the cheat code was being typed into the first field.
boot_rel:
	WAIT
	IF cont1.key <> 15 THEN GOTO boot_rel

main:
	WAIT
	' FIRE steps through the held category's variants -- the ColecoVision way
	' in, where there is no keyboard to type a letter on. Edge-triggered, or
	' holding it would run through the whole set in a tenth of a second.
	b = 0
	IF cont1.button THEN b = 1
	IF b <> blast THEN
		blast = b
		IF b = 1 THEN
			v = catcur(cat) + 1
			IF v >= catnum(cat) THEN v = 0
			GOSUB play_one
		END IF
	END IF
	' EDGE-TRIGGERED. cont1.key returns the same value on every pass while a
	' key is held, so without this one press would replay for as long as a
	' finger is on it.
	k = cont1.key
	IF k = klast THEN GOTO main
	klast = k

	' --- a digit 1-6 HOLDS a category. It plays nothing: picking what to
	' --- listen to and listening to it are separate acts, and merging them
	' --- means every category change costs you a sound you did not ask for.
	IF k >= 1 THEN
		IF k <= NCAT THEN
			GOSUB clear_mark
			cat = k - 1
			GOSUB show_mark
			GOTO main
		END IF
	END IF

	' --- a letter A-J plays that variant of the held category. 65 is "A".
	IF k >= 65 THEN
		IF k <= 74 THEN
			v = k - 65
			IF v < catnum(cat) THEN GOSUB play_one
		END IF
	END IF
	GOTO main

	' One variant of the held category, and remember it as the current one so
	' FIRE carries on from wherever the last letter left off.
play_one:
	catcur(cat) = v
	fx = catfst(cat)
	fx = fx + v
	GOSUB show_variant
	GOSUB play_fx
	GOSUB show_ready
	RETURN

	' ----------------------------------------------------------------------
	' THE TABLE
	' ----------------------------------------------------------------------
	' An effect is a run of FOUR-BYTE STEPS: frames to hold, which channel, a
	' value, and a volume. A step of 0 frames ends the effect; a step of 255
	' frames ends the whole table.
	'
	'     channel 0-2   a TONE. The value is the divisor over four, because a
	'                   divisor runs to 1023 and a DATA BYTE stops at 255.
	'                   Pitch is 3579545 / (32 * divisor), so a SMALLER
	'                   divisor is a HIGHER note -- sweeps read backwards from
	'                   how they are written, which has caught this repo out.
	'     channel 3     NOISE. The value is the register, 0-7: 0-3 periodic
	'                   ("buzzy", nearly pitched), 4-7 white, and within each
	'                   the rate falls as the number rises. 3 and 7 clock the
	'                   noise from tone channel 2 instead, making it tunable.
	'     channel 255   silence, for the gaps in a cadence.
	'
	' EFFECTS USED TO BE A FIXED EIGHT STEPS, so the player could skip to one
	' by multiplying. That meant padding every short effect with zero-frame
	' steps, and getting the count wrong made every later effect play somebody
	' else's data -- silently, because the bytes were all valid. Scanning the
	' table once at boot to record where each effect starts costs a few
	' hundred bytes of a cart with twenty thousand free, removes the trap
	' entirely, and is what lets the tally run for ten counts instead of four.
scan_fx:
	RESTORE fx_data
	nfx = 0
	#cnt = 0
	#fxoff(0) = 0
scan_loop:
	READ BYTE b0
	IF b0 = ENDTAB THEN RETURN
	' the other three bytes of the step are consumed and DISCARDED -- this
	' pass only wants to know where each effect begins. Read into the same
	' scratch the player uses rather than three named variables nothing ever
	' reads, which the compiler rightly complains about.
	READ BYTE sb
	READ BYTE sb
	READ BYTE sb
	#cnt = #cnt + 4
	IF b0 = 0 THEN
		nfx = nfx + 1
		IF nfx < 48 THEN #fxoff(nfx) = #cnt
	END IF
	GOTO scan_loop

	' ----------------------------------------------------------------------
	' THE PLAYER
	' ----------------------------------------------------------------------
play_fx:
	RESTORE fx_data
	#skip = #fxoff(fx)
	IF #skip > 0 THEN
		' A COMPUTED `FOR 1 TO 0` STILL RUNS ITS BODY ONCE in CVBasic, so
		' effect 0 needs the guard or it skips four bytes into itself.
		FOR #si = 1 TO #skip
			READ BYTE sb
		NEXT #si
	END IF
step_loop:
	FOR pb = 0 TO 3
		READ BYTE sb
		stp(pb) = sb
	NEXT pb
	IF stp(0) = 0 THEN GOTO fx_done
	IF stp(0) = ENDTAB THEN GOTO fx_done
	IF stp(1) = SILENCE THEN
		SOUND 0,,0
		SOUND 3,,0
	ELSE
		IF stp(1) = NOISE THEN
			SOUND 3,stp(2),stp(3)
		ELSE
			' back to a real divisor, in a 16-bit variable -- a plain
			' one is 8-bit and would wrap at 255
			#div = stp(2)
			#div = #div + #div
			#div = #div + #div
			' THE CHANNEL IS A LITERAL IN EVERY CVBasic SOUND, so this
			' dispatches rather than passing stp(1) through. It used to
			' write channel 0 whatever the step said, which was fine
			' while nothing layered and silently wrong the moment
			' something did.
			IF stp(1) = 0 THEN SOUND 0,#div,stp(3)
			IF stp(1) = 1 THEN SOUND 1,#div,stp(3)
			IF stp(1) = 2 THEN SOUND 2,#div,stp(3)
		END IF
	END IF
	' A BED IS SET AND LEFT RUNNING. NOWAIT steps do not hold up the
	' sequence, so a low sustained tone can be started on channel 1 and the
	' ticks then play OVER it on channel 3 -- which is the only way to layer
	' when every step otherwise waits for itself.
	'
	' SILENCE above deliberately kills only channels 0 and 3, the tick
	' channels, so a bed survives it and stops at fx_done with everything else.
	IF stp(0) = NOWAIT THEN GOTO step_loop
	FOR pw = 1 TO stp(0)
		WAIT
	NEXT pw
	GOTO step_loop
fx_done:
	' EVERY EFFECT NEEDS AN EXPLICIT NOTE-OFF. SOUND latches, so without this
	' the last step plays until the next keypress -- and a BED would outlive
	' its effect entirely, which is why all four channels are named here and
	' not just the two an effect usually touches.
	SOUND 0,,0
	SOUND 1,,0
	SOUND 2,,0
	SOUND 3,,0
	RETURN

	' ----------------------------------------------------------------------
	' THE SCREEN
	' ----------------------------------------------------------------------
draw_menu:
	CLS
	PRINT AT 34,"TESTSOUNDS"
	PRINT AT 66,"DIGIT PICKS LETTER PLAYS"
	PRINT AT 98,"1 RUN      10"
	PRINT AT 130,"2 JUMP      4"
	PRINT AT 162,"3 TIME UP   3"
	PRINT AT 194,"4 PICKUP   10"
	PRINT AT 226,"5 HIT       8"
	PRINT AT 258,"6 TALLY     3"
	PRINT AT 322,"FIRE STEPS THROUGH THEM"
	PRINT AT 354,"A IS THE MEASURED ONE"
	PRINT AT 418,"MEASURED FROM THE 2600"
	GOSUB show_mark
show_ready:
	PRINT AT 482,"PRESS A DIGIT     "
	RETURN

	' The variant letter goes beside its own line. VPOKE rather than PRINT AT
	' because the row is computed: PRINT AT wants a constant everywhere else
	' in this program and there is no reason to make an exception.
	' The ">" against whichever category FIRE has landed on. Two routines
	' rather than a redraw of the block: the variant letters written beside
	' each line have to survive a category change, and redrawing the menu
	' would wipe the record of what has already been tried.
show_mark:
	mk = 62				' ">"
	GOTO mark_put
clear_mark:
	mk = 32				' a space
mark_put:
	#ma = 6144
	#ma = #ma + 96			' row 3, col 0 -- the RUN line
	mr = cat
	mr = mr + mr
	mr = mr + mr
	mr = mr + mr
	mr = mr + mr
	mr = mr + mr			' cat * 32, one screen row
	#ma = #ma + mr
	VPOKE #ma,mk
	RETURN

show_variant:
	#va = 6144
	#va = #va + 98			' row 3, col 2 -- the RUN line
	vr = cat
	vr = vr + vr
	vr = vr + vr
	vr = vr + vr
	vr = vr + vr
	vr = vr + vr			' cat * 32, one screen row
	#va = #va + vr
	#va = #va + 16			' out past the longest label
	vc = 65
	vc = vc + catcur(cat)		' A, B, C, D
	VPOKE #va,vc
	PRINT AT 482,"PLAYING           "
	RETURN

	' ----------------------------------------------------------------------
	' THE EFFECTS -- frames, channel, value, volume
	' ----------------------------------------------------------------------
	' 60 frames a second, so a frame is about 17 ms. Divisors over four:
	'   188 Hz = 595 -> 149    415 Hz = 270 -> 68
	'   235 Hz = 476 -> 119    523 Hz = 214 -> 54
	'   264 Hz = 424 -> 106    659 Hz = 170 -> 42
	'   295 Hz = 379 ->  95   1028 Hz = 109 -> 27
	'   371 Hz = 301 ->  75   1568 Hz =  71 -> 18
	'                         2543 Hz =  44 -> 11
fx_data:
	' ================= 1 RUN =================
	' A -- measured: a 64 ms white-noise burst every 165 ms.
	DATA BYTE 4,3,4,12,  6,255,0,0
	DATA BYTE 4,3,4,12,  6,255,0,0
	DATA BYTE 4,3,4,12,  6,255,0,0
	DATA BYTE 4,3,4,12,  6,255,0,0
	DATA BYTE 4,3,4,12,  6,255,0,0
	DATA BYTE 4,3,4,12,  6,255,0,0
	DATA BYTE 0,0,0,0

	' B -- the same cadence at a slower noise rate: heavier, more of a thud.
	DATA BYTE 4,3,6,12,  6,255,0,0
	DATA BYTE 4,3,6,12,  6,255,0,0
	DATA BYTE 4,3,6,12,  6,255,0,0
	DATA BYTE 4,3,6,12,  6,255,0,0
	DATA BYTE 4,3,6,12,  6,255,0,0
	DATA BYTE 4,3,6,12,  6,255,0,0
	DATA BYTE 0,0,0,0

	' C -- PERIODIC noise instead of white. Nearly a pitch, so it reads as a
	' shoe on a hard floor rather than as a hiss.
	DATA BYTE 4,3,1,12,  6,255,0,0
	DATA BYTE 4,3,1,12,  6,255,0,0
	DATA BYTE 4,3,1,12,  6,255,0,0
	DATA BYTE 4,3,1,12,  6,255,0,0
	DATA BYTE 4,3,1,12,  6,255,0,0
	DATA BYTE 4,3,1,12,  6,255,0,0
	DATA BYTE 0,0,0,0

	' D -- a crisper tick: 2 frames on, 8 off. Same 6 a second, less of it.
	DATA BYTE 2,3,4,13,  8,255,0,0
	DATA BYTE 2,3,4,13,  8,255,0,0
	DATA BYTE 2,3,4,13,  8,255,0,0
	DATA BYTE 2,3,4,13,  8,255,0,0
	DATA BYTE 2,3,4,13,  8,255,0,0
	DATA BYTE 2,3,4,13,  8,255,0,0
	DATA BYTE 0,0,0,0

	' E -- THE TALLY'S TICK, at about ten a second. Two frames on rather than
	' four, which is half the burst -- and a short tick can be repeated much
	' faster before it smears into a drone. This is what the game plays now.
	DATA BYTE 2,3,4,12,  4,255,0,0
	DATA BYTE 2,3,4,12,  4,255,0,0
	DATA BYTE 2,3,4,12,  4,255,0,0
	DATA BYTE 2,3,4,12,  4,255,0,0
	DATA BYTE 2,3,4,12,  4,255,0,0
	DATA BYTE 2,3,4,12,  4,255,0,0
	DATA BYTE 2,3,4,12,  4,255,0,0
	DATA BYTE 2,3,4,12,  4,255,0,0
	DATA BYTE 0,0,0,0

	' F -- the same tick at fifteen a second, which is the rate the old TONE
	' footsteps fired at. Worth hearing: the rate was never the whole problem,
	' the tone was, and this says how much of it was which.
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 0,0,0,0

	' G -- VERY FAST, BARE. One frame on, two off: twenty a second, and about
	' as short as a tick can be and still exist. This is the tick-tick-tick on
	' its own, so the pad variants below can be judged against it.
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 0,0,0,0

	' H -- the same ticks over a LOW SUSTAINED PAD, 188 Hz at volume 4 on
	' channel 1. The pad is set once and left running; the ticks play over it
	' on the noise channel. Quiet enough to be felt rather than heard, which
	' is the point -- it gives the ticks something to sit on instead of
	' rattling in silence.
	DATA BYTE 254,1,149,4
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 0,0,0,0

	' I -- ticks over a pad that BREATHES, 188 Hz against 235 every eight
	' frames. A flat pad can turn into a drone the ear stops hearing; a slow
	' one keeps suggesting effort without ever asking for attention.
	DATA BYTE 254,1,149,4
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 254,1,119,4
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 254,1,149,4
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 254,1,119,4
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 254,1,149,4
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 0,0,0,0

	' J -- TICK-TOCK rather than tick-tick: the noise rate alternates between
	' registers 4 and 6, so one foot lands brighter than the other. Two feet,
	' not a ratchet -- and it costs nothing but a second value.
	DATA BYTE 254,1,149,4
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,6,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,6,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,6,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,6,12,  2,255,0,0
	DATA BYTE 1,3,4,12,  2,255,0,0
	DATA BYTE 1,3,6,12,  2,255,0,0
	DATA BYTE 0,0,0,0

	' ================= 2 JUMP =================
	' A -- measured: 415 Hz warbling against 188, about 280 ms.
	DATA BYTE 2,0,68,12,  2,0,149,12
	DATA BYTE 2,0,68,12,  2,0,149,12
	DATA BYTE 2,0,68,12,  2,0,149,12
	DATA BYTE 2,0,68,12,  2,0,149,12
	DATA BYTE 0,0,0,0

	' B -- the same warble twice as fast: more urgent, less of a wobble.
	DATA BYTE 1,0,68,12,  1,0,149,12
	DATA BYTE 1,0,68,12,  1,0,149,12
	DATA BYTE 1,0,68,12,  1,0,149,12
	DATA BYTE 1,0,68,12,  1,0,149,12
	DATA BYTE 1,0,68,12,  1,0,149,12
	DATA BYTE 1,0,68,12,  1,0,149,12
	DATA BYTE 1,0,68,12,  1,0,149,12
	DATA BYTE 1,0,68,12,  1,0,149,12
	DATA BYTE 0,0,0,0

	' C -- a rising sweep instead of a warble: reads as leaving the ground.
	DATA BYTE 3,0,149,12
	DATA BYTE 3,0,106,12
	DATA BYTE 3,0,75,12
	DATA BYTE 3,0,54,12
	DATA BYTE 5,0,42,12
	DATA BYTE 0,0,0,0

	' D -- a short noise burst, no pitch at all. The cheapest option, and
	' worth hearing before deciding the warble is necessary.
	DATA BYTE 17,3,5,12
	DATA BYTE 0,0,0,0

	' ================= 3 TIME UP =================
	' A -- measured: a warble wandering 235-371 Hz for about 430 ms.
	DATA BYTE 4,0,119,12
	DATA BYTE 4,0,106,12
	DATA BYTE 4,0,75,12
	DATA BYTE 4,0,106,12
	DATA BYTE 4,0,119,12
	DATA BYTE 4,0,106,12
	DATA BYTE 0,0,0,0

	' B -- a two-tone alarm on the same pitches, slower and even. More
	' deliberate: this is the sound that ends a round.
	DATA BYTE 8,0,119,13
	DATA BYTE 8,0,75,13
	DATA BYTE 8,0,119,13
	DATA BYTE 8,0,75,13
	DATA BYTE 0,0,0,0

	' C -- a long fall. Reads as running down rather than as an alarm.
	DATA BYTE 5,0,75,13
	DATA BYTE 5,0,95,12
	DATA BYTE 6,0,106,12
	DATA BYTE 7,0,119,11
	DATA BYTE 9,0,149,10
	DATA BYTE 0,0,0,0

	' ================= 4 PICKUP =================
	' HIGH IS NOT THE SAME AS HAPPY. The 2600 tops its pickup out at 2543 Hz,
	' and copying that was a mistake: TIA's timbre is soft enough to carry it,
	' and an SN76489 square at 2543 Hz is a shriek. A reward the player earns
	' fifty times a round must not be the most piercing thing on the machine.
	'
	' So A is kept as the MEASURED one -- this bench's whole convention is that
	' A is the reference -- and B onwards top out between 523 and 784 Hz, which
	' is where a square wave still sounds like a note rather than a whistle.
	'
	' They are built on INTERVALS rather than on measurements. A rise reads as
	' positive, but an arbitrary rise reads as a sweep; a major arpeggio reads
	' as an arrival, and arriving is what collecting something is. Divisors:
	'   C4 262 Hz = 107   G4 392 = 71    E5 659 = 42
	'   E4 330 Hz =  85   A4 440 = 64    G5 784 = 36
	'   F4 349 Hz =  80   C5 523 = 54

	' A -- MEASURED, and kept only as the reference. 295 Hz then 2543. This is
	' the one the complaint is about.
	DATA BYTE 7,0,95,12
	DATA BYTE 26,0,11,12
	DATA BYTE 0,0,0,0

	' B -- a C major arpeggio, C4 E4 G4, landing on C5 and holding. Tops at
	' 523 Hz. The hold is what makes it an arrival rather than a blip.
	DATA BYTE 6,0,107,12
	DATA BYTE 6,0,85,12
	DATA BYTE 6,0,71,12
	DATA BYTE 15,0,54,12
	DATA BYTE 0,0,0,0

	' C -- the same shape an octave up, C5 E5 G5, topping at 784 Hz and fading
	' out rather than stopping. Brighter than B without ever getting shrill.
	DATA BYTE 6,0,54,12
	DATA BYTE 6,0,42,12
	DATA BYTE 8,0,36,12
	DATA BYTE 5,0,36,10
	DATA BYTE 4,0,36,7
	DATA BYTE 4,0,36,4
	DATA BYTE 0,0,0,0

	' D -- two intervals only: C4 up a fourth to F4, then up to C5. Fewer
	' notes, more weight on each. Tops at 523 Hz.
	DATA BYTE 8,0,107,12
	DATA BYTE 8,0,80,12
	DATA BYTE 17,0,54,12
	DATA BYTE 0,0,0,0

	' E -- the simplest thing that can read as a reward: G4 up a fourth to C5,
	' held. Two notes, 392 to 523 Hz. Hard to get lost under the footsteps and
	' hard to grow tired of.
	DATA BYTE 12,0,71,12
	DATA BYTE 21,0,54,12
	DATA BYTE 0,0,0,0

	' F -- B's arpeggio taken quickly, then a long fading hold on top. The
	' quick part is the pickup and the hold is the satisfaction.
	DATA BYTE 4,0,107,12
	DATA BYTE 4,0,85,12
	DATA BYTE 4,0,71,12
	DATA BYTE 10,0,54,12
	DATA BYTE 6,0,54,10
	DATA BYTE 5,0,54,7
	DATA BYTE 0,0,0,0

	' G -- the WARMEST option, and it never leaves the middle: E4 G4 A4, tops
	' at 440 Hz. Worth hearing against B to find out how low a reward can sit
	' and still read as one.
	DATA BYTE 8,0,85,12
	DATA BYTE 8,0,71,12
	DATA BYTE 17,0,64,12
	DATA BYTE 0,0,0,0

	' H -- rise and SETTLE: C5 E5 G5 then back to E5. It resolves instead of
	' stopping at the top, which is the difference between a phrase and a
	' fragment -- and the drop at the end keeps the last thing heard low.
	DATA BYTE 6,0,54,12
	DATA BYTE 6,0,42,12
	DATA BYTE 8,0,36,12
	DATA BYTE 13,0,42,12
	DATA BYTE 0,0,0,0

	' C ENDS TOO HIGH, AND THERE ARE TWO WAYS TO SAY SO. C rises C5 E5 G5 and
	' fades on G5 at 784 Hz. Either the whole phrase is too high, or only the
	' note it is left sitting on is -- these are the two answers, because they
	' are different fixes and only one of them can be right.

	' I -- THE WHOLE PHRASE, A THIRD LOWER. Same shape, same fade, built on
	' A4 C5 E5 instead: it tops out at 659 Hz rather than 784 and lands there.
	' Choose this one if C was bright all the way through.
	DATA BYTE 6,0,64,12
	DATA BYTE 6,0,54,12
	DATA BYTE 8,0,42,12
	DATA BYTE 5,0,42,10
	DATA BYTE 4,0,42,7
	DATA BYTE 4,0,42,4
	DATA BYTE 0,0,0,0

	' J -- ONLY THE ENDING. C's exact climb, C5 E5 G5, but it does not STAY on
	' the top note: it settles back to E5 and fades there. The peak still
	' happens, so the phrase keeps its lift, and the last thing left ringing
	' is 659 Hz instead of 784. Choose this one if C was fine until it stopped.
	DATA BYTE 6,0,54,12
	DATA BYTE 6,0,42,12
	DATA BYTE 6,0,36,12
	DATA BYTE 5,0,42,11
	DATA BYTE 5,0,42,8
	DATA BYTE 5,0,42,5
	DATA BYTE 0,0,0,0

	' ================= 5 HIT =================
	' A -- measured: the jump's warble, then a tail FALLING to 235 Hz and
	' holding. About 650 ms. The fall is what separates it from the jump.
	DATA BYTE 2,0,68,13,  2,0,149,13
	DATA BYTE 2,0,68,13,  2,0,149,13
	DATA BYTE 2,0,68,13,  2,0,149,13
	DATA BYTE 5,0,106,12
	DATA BYTE 18,0,119,10
	DATA BYTE 0,0,0,0

	' B -- a smooth fall, no warble. The mirror of PICKUP B, and the pair
	' should be obvious with eyes shut.
	DATA BYTE 4,0,42,13
	DATA BYTE 4,0,68,13
	DATA BYTE 5,0,95,12
	DATA BYTE 6,0,119,11
	DATA BYTE 8,0,149,10
	DATA BYTE 0,0,0,0

	' C -- noise into a falling tone: an impact, then the consequence.
	DATA BYTE 6,3,6,13
	DATA BYTE 6,0,106,12
	DATA BYTE 8,0,119,11
	DATA BYTE 12,0,149,9
	DATA BYTE 0,0,0,0

	' D -- a low buzz on periodic noise. No pitch to argue with, and it does
	' not compete with the music the way a held tone does.
	DATA BYTE 30,3,2,13
	DATA BYTE 8,3,2,9
	DATA BYTE 0,0,0,0

	' E -- THE MEASURED SHAPE AT THE MEASURED LENGTH. The 415/188 warble, then
	' a tail falling to 235 and holding, over the full 660 ms the recording
	' shows -- the warble is the impact and the fall is the consequence.
	DATA BYTE 2,0,68,13,  2,0,149,13
	DATA BYTE 2,0,68,13,  2,0,149,13
	DATA BYTE 2,0,68,13,  2,0,149,13
	DATA BYTE 2,0,68,13,  2,0,149,13
	DATA BYTE 4,0,95,12
	DATA BYTE 6,0,106,12
	DATA BYTE 20,0,119,11
	DATA BYTE 0,0,0,0

	' F -- a TWO-STAGE fall: quick at first, then slow. Things that drop do
	' not fall at a constant rate, and the ear knows it.
	DATA BYTE 3,0,42,13
	DATA BYTE 3,0,54,13
	DATA BYTE 4,0,68,12
	DATA BYTE 6,0,95,12
	DATA BYTE 9,0,119,11
	DATA BYTE 14,0,149,10
	DATA BYTE 0,0,0,0

	' G -- a noise ATTACK and then the fall. The collision and the aftermath
	' as two separate sounds, which is what a crash actually is.
	DATA BYTE 5,3,6,13
	DATA BYTE 3,0,68,13
	DATA BYTE 5,0,95,12
	DATA BYTE 8,0,119,11
	DATA BYTE 18,0,149,9
	DATA BYTE 0,0,0,0

	' H -- the warble WITHOUT the fall, held low and long. Nine seconds is a
	' heavy penalty and a sound that just sits there says so; worth hearing
	' against E to decide whether the fall is doing any work.
	DATA BYTE 2,0,119,13,  2,0,149,13
	DATA BYTE 2,0,119,13,  2,0,149,13
	DATA BYTE 2,0,119,13,  2,0,149,13
	DATA BYTE 2,0,119,13,  2,0,149,13
	DATA BYTE 2,0,119,13,  2,0,149,13
	DATA BYTE 2,0,119,13,  2,0,149,13
	DATA BYTE 16,0,149,11
	DATA BYTE 0,0,0,0

	' ================= 6 TALLY =================
	' TEN COUNTS, not four. A tally is judged over a RUN of them -- whether it
	' nags, whether it drags -- and four ticks tells you nothing about that.
	'
	' A -- measured: a 67 ms tick against the 2600's 64, ten times, ending on
	' the longer accent it plays at the end of a group.
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 7,3,4,13
	DATA BYTE 0,0,0,0

	' B -- the same ten as a TONE blip rather than noise. Reads as counting
	' rather than as ratcheting.
	DATA BYTE 2,0,27,12,  2,255,0,0
	DATA BYTE 2,0,27,12,  2,255,0,0
	DATA BYTE 2,0,27,12,  2,255,0,0
	DATA BYTE 2,0,27,12,  2,255,0,0
	DATA BYTE 2,0,27,12,  2,255,0,0
	DATA BYTE 2,0,27,12,  2,255,0,0
	DATA BYTE 2,0,27,12,  2,255,0,0
	DATA BYTE 2,0,27,12,  2,255,0,0
	DATA BYTE 2,0,27,12,  2,255,0,0
	DATA BYTE 2,0,27,12,  2,255,0,0
	DATA BYTE 8,0,11,13
	DATA BYTE 0,0,0,0

	' C -- ten ticks that ACCELERATE, ending on the accent. A tally that
	' speeds up says "nearly done" without a number.
	DATA BYTE 2,3,4,12,  5,255,0,0
	DATA BYTE 2,3,4,12,  5,255,0,0
	DATA BYTE 2,3,4,12,  4,255,0,0
	DATA BYTE 2,3,4,12,  4,255,0,0
	DATA BYTE 2,3,4,12,  3,255,0,0
	DATA BYTE 2,3,4,12,  3,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  2,255,0,0
	DATA BYTE 2,3,4,12,  1,255,0,0
	DATA BYTE 2,3,4,12,  1,255,0,0
	DATA BYTE 9,3,4,13
	DATA BYTE 0,0,0,0

	' END OF TABLE
	DATA BYTE 255,0,0,0
