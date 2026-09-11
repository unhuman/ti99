	' ======================================================================
	' COLECO SOUNDS -- a SECOND bench for Keystone Kapers' sound effects
	' ======================================================================
	' A separate app from `testsounds`, on purpose, so the two can be run
	' against each other. That one's candidates were measured off an ATARI
	' 2600 recording; these are measured off a COLECOVISION one.
	'
	' WHY THAT MATTERS MORE THAN IT SOUNDS. The ColecoVision runs the same
	' sound chip as this target -- a TI SN76489 at 3.579545 MHz -- so a
	' frequency read off the recording converts straight back to the register
	' the game wrote: divisor = 111860 / freq. The 2600's TIA is a different
	' chip with a 5-bit divider and its own waveform table, so every number
	' taken from it had to be re-imagined rather than translated. Here the
	' arithmetic is exact wherever the pitch is high enough to resolve.
	'
	' See games/KeystoneKapers/assets/sfx/sfxref-coleco.md for the measurements.
	'
	' A DIGIT PICKS THE CATEGORY, A LETTER PLAYS THE VARIANT. Press 3 for
	' FALL, then A and C and A again -- one key each, and the category stays
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
	' WHY IT EXISTS. Tuning an effect by editing the game, rebuilding, and
	' playing to the screen where it fires is hopeless; here it is a keypress,
	' and the two SOURCES can be A/Bed rather than argued about.
	'
	' VARIANT A OF EVERY CATEGORY IS THE MEASURED ONE. The rest are departures
	' from it, so the reference is always one key away and the comparison is
	' never against memory.
	'
	' HOW THE NUMBERS WERE GOT. `audioop.rms` over 10-20 ms blocks to find where
	' something happens, then a GOERTZEL FILTER PER CANDIDATE DIVISOR to say
	' what pitch it is. That asks a better question than an FFT peak-pick: not
	' "what frequency is this" but "of the divisors the chip can actually play,
	' which one is present", and the answer is the register value itself.
	'
	' AND THE LIMIT, WHICH MATTERS. Adjacent divisors sit about freq/divisor
	' apart, so at divisor 40 they are 70 Hz apart and trivially separated,
	' while at 212 they are 2.5 Hz apart and a 400 ms effect cannot resolve
	' them at all. Read a high note as a register value and a low one as a
	' neighbourhood. The recording also carries music and several channels at
	' once, so a reading is the LOUDEST thing in its window, not necessarily
	' the effect.
	'
	' WHAT THE RECORDING CANNOT SAY is which game event a sound belongs to. A
	' falling run recurs every fifteen to twenty seconds and fits a hit or a
	' prize equally well, so it is filed by SHAPE as category 3 and its exact
	' mirror is category 4. That pair is the one to judge: a fall and a rise are
	' the difference between a penalty and a reward.
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
	catfst(0) = 0  : catnum(0) = 4		' 1 RUN
	catfst(1) = 4  : catnum(1) = 4		' 2 JUMP
	catfst(2) = 8  : catnum(2) = 4		' 3 FALL
	catfst(3) = 12 : catnum(3) = 4		' 4 RISE
	catfst(4) = 16 : catnum(4) = 4		' 5 TALLY
	catfst(5) = 20 : catnum(5) = 4		' 6 ROUND

	' NOTHING HERE IS ZERO UNTIL IT IS SET. TI RAM comes up holding whatever
	' it held, and CVBasic does not clear variables at startup -- so `cat`,
	' `catcur()`, `klast` and `blast` all began as garbage. Three
	' consecutive boots opened on PICKUP, on TALLY/B and on TALLY/D, none of
	' which anybody chose.
	'
	' It is worse than a wrong marker. A garbage `klast` equal to the first
	' key pressed SWALLOWS that key, because the reader is edge-triggered;
	' and a garbage `catcur` means FIRE starts stepping from the middle of a
	' set. On a bench whose whole job is to say which variant you just heard,
	' state nobody set is state that can lie about the answer.
	'
	' 15 is cont1.key's "nothing", so the first real press is an edge.
	cat = 0
	klast = 15
	blast = 0
	FOR ci = 0 TO NCAT - 1
		catcur(ci) = 0
	NEXT ci

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
	PRINT AT 34,"COLECO SOUNDS"
	PRINT AT 66,"DIGIT PICKS LETTER PLAYS"
	PRINT AT 98,"1 RUN       4"
	PRINT AT 130,"2 JUMP      4"
	PRINT AT 162,"3 FALL      4"
	PRINT AT 194,"4 RISE      4"
	PRINT AT 226,"5 TALLY     4"
	PRINT AT 258,"6 ROUND     4"
	PRINT AT 322,"FIRE STEPS THROUGH THEM"
	PRINT AT 354,"A IS THE MEASURED ONE"
	PRINT AT 418,"FROM THE COLECOVISION"
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
	' ======================================================================
	' MEASURED OFF THE COLECOVISION RECORDING, NOT THE 2600 ONE.
	' ======================================================================
	' The ColecoVision runs the SAME CHIP as our TI target -- a TI SN76489 at
	' 3.579545 MHz -- so a frequency read off the recording converts straight
	' back to the register the game wrote:
	'
	'     freq = 3579545 / (32 * divisor)      divisor = 111860 / freq
	'
	' The 2600's TIA is a different chip with a 5-bit divider and its own
	' waveform table, so every number taken from it had to be re-imagined.
	' Here the arithmetic is exact -- WHERE THE PITCH IS HIGH ENOUGH. Adjacent
	' divisors sit about freq/divisor apart, so at divisor 40 they are 70 Hz
	' apart and easily told apart, while at 213 they are 2.5 Hz apart and a
	' 400 ms effect cannot resolve them. Read the low notes as a neighbourhood.
	'
	' Divisors over four, as the table stores them:
	'     divisor 512 -> 128    218 Hz       divisor 144 -> 36    777 Hz
	'     divisor 496 -> 124    226 Hz       divisor 120 -> 30    932 Hz
	'     divisor 236 -> 59     474 Hz       divisor 108 -> 27   1035 Hz
	'     divisor 212 -> 53     527 Hz       divisor  84 -> 21   1332 Hz
	'     divisor 192 -> 48     582 Hz       divisor  72 -> 18   1553 Hz
	'     divisor 176 -> 44     635 Hz
	'
	' A IS ALWAYS THE MEASURED ONE. The others are deliberate departures from
	' it, so that what is being compared is a decision rather than a guess.

	' ================= 1 RUN =================
	' A -- MEASURED. Onsets every 0.130 s across a twelve-second run: 7.7 a
	' second, which is EIGHT FRAMES apart at 60 Hz. The 2600-derived bench put
	' this at six a second, so the crook's feet were running slow.
	DATA BYTE 2,3,4,12,  6,255,0,0
	DATA BYTE 2,3,4,12,  6,255,0,0
	DATA BYTE 2,3,4,12,  6,255,0,0
	DATA BYTE 2,3,4,12,  6,255,0,0
	DATA BYTE 2,3,4,12,  6,255,0,0
	DATA BYTE 2,3,4,12,  6,255,0,0
	DATA BYTE 0,0,0,0

	' B -- the measured cadence with a heavier step: a slower noise rate reads
	' as more weight on the foot.
	DATA BYTE 2,3,6,12,  6,255,0,0
	DATA BYTE 2,3,6,12,  6,255,0,0
	DATA BYTE 2,3,6,12,  6,255,0,0
	DATA BYTE 2,3,6,12,  6,255,0,0
	DATA BYTE 2,3,6,12,  6,255,0,0
	DATA BYTE 2,3,6,12,  6,255,0,0
	DATA BYTE 0,0,0,0

	' C -- the OLD cadence, ten frames apart, for the comparison. This is what
	' the game ships today; against A it is audibly a jog rather than a run.
	DATA BYTE 2,3,4,12,  8,255,0,0
	DATA BYTE 2,3,4,12,  8,255,0,0
	DATA BYTE 2,3,4,12,  8,255,0,0
	DATA BYTE 2,3,4,12,  8,255,0,0
	DATA BYTE 2,3,4,12,  8,255,0,0
	DATA BYTE 0,0,0,0

	' D -- PERIODIC noise instead of white, at the measured cadence. Periodic
	' is nearly pitched, so the step gets a tone to it rather than a hiss.
	DATA BYTE 2,3,0,12,  6,255,0,0
	DATA BYTE 2,3,0,12,  6,255,0,0
	DATA BYTE 2,3,0,12,  6,255,0,0
	DATA BYTE 2,3,0,12,  6,255,0,0
	DATA BYTE 2,3,0,12,  6,255,0,0
	DATA BYTE 2,3,0,12,  6,255,0,0
	DATA BYTE 0,0,0,0

	' ================= 2 JUMP =================
	' A -- MEASURED. A 400 ms warble that rises and comes back:
	' divisor 212 -> 192 -> 176 -> 192 -> 212, about 527 -> 635 -> 527 Hz.
	' It is the commonest effect in the recording after the footsteps.
	DATA BYTE 5,0,53,13
	DATA BYTE 5,0,48,13
	DATA BYTE 5,0,44,13
	DATA BYTE 5,0,48,13
	DATA BYTE 5,0,53,13
	DATA BYTE 0,0,0,0

	' B -- the same shape at half the length: brighter, less of a swoop.
	DATA BYTE 3,0,53,13
	DATA BYTE 3,0,48,13
	DATA BYTE 3,0,44,13
	DATA BYTE 3,0,48,13
	DATA BYTE 3,0,53,13
	DATA BYTE 0,0,0,0

	' C -- the rise WITHOUT the return. A jump that ends high reads as
	' unfinished, which is the argument for the measured shape.
	DATA BYTE 6,0,53,13
	DATA BYTE 6,0,48,13
	DATA BYTE 8,0,44,13
	DATA BYTE 0,0,0,0

	' D -- a wider warble, 236 down to 176 and back: the same gesture over a
	' bigger interval.
	DATA BYTE 5,0,59,13
	DATA BYTE 5,0,53,13
	DATA BYTE 5,0,44,13
	DATA BYTE 5,0,53,13
	DATA BYTE 5,0,59,13
	DATA BYTE 0,0,0,0

	' ================= 3 FALL =================
	' A -- MEASURED. A 240 ms run DOWN in pitch, divisor 108 -> 120 -> 144 ->
	' 176 -> 212, with one bright accent at divisor 72 partway through. It
	' recurs every fifteen to twenty seconds of play.
	'
	' WHICH GAME EVENT THIS IS CANNOT BE HEARD. A recording says what the chip
	' did, not why; a falling run at that spacing fits either a hit or a prize
	' being taken. So it is filed by its SHAPE, and category 4 is its mirror --
	' which is the comparison worth making, because a fall and a rise are the
	' difference between a penalty and a reward.
	DATA BYTE 3,0,27,13
	DATA BYTE 3,0,30,13
	DATA BYTE 3,0,36,13
	DATA BYTE 2,0,18,13
	DATA BYTE 3,0,44,13
	DATA BYTE 4,0,53,13
	DATA BYTE 0,0,0,0

	' B -- the same run with the accent taken out, to hear what the accent is
	' doing. Smooth, and duller.
	DATA BYTE 3,0,27,13
	DATA BYTE 3,0,30,13
	DATA BYTE 3,0,36,13
	DATA BYTE 3,0,44,13
	DATA BYTE 4,0,53,13
	DATA BYTE 0,0,0,0

	' C -- more steps over the same span: a slide rather than a stair.
	DATA BYTE 2,0,27,13
	DATA BYTE 2,0,30,13
	DATA BYTE 2,0,33,13
	DATA BYTE 2,0,36,13
	DATA BYTE 2,0,40,13
	DATA BYTE 2,0,44,13
	DATA BYTE 2,0,48,13
	DATA BYTE 3,0,53,13
	DATA BYTE 0,0,0,0

	' D -- the measured run, but carried further down to divisor 128. A deeper
	' bottom reads as a worse outcome.
	DATA BYTE 3,0,27,13
	DATA BYTE 3,0,36,13
	DATA BYTE 2,0,18,13
	DATA BYTE 3,0,53,13
	DATA BYTE 6,0,128,13
	DATA BYTE 0,0,0,0

	' ================= 4 RISE =================
	' A -- the measured fall PLAYED BACKWARDS. Same notes, same holds, nothing
	' invented: if 3A is the hit then this is what the prize should sound
	' like, and the pair can be judged together.
	DATA BYTE 4,0,53,13
	DATA BYTE 3,0,44,13
	DATA BYTE 2,0,18,13
	DATA BYTE 3,0,36,13
	DATA BYTE 3,0,30,13
	DATA BYTE 3,0,27,13
	DATA BYTE 0,0,0,0

	' B -- the rise without the accent.
	DATA BYTE 4,0,53,13
	DATA BYTE 3,0,44,13
	DATA BYTE 3,0,36,13
	DATA BYTE 3,0,30,13
	DATA BYTE 3,0,27,13
	DATA BYTE 0,0,0,0

	' C -- a smooth rise, more notes over the same span.
	DATA BYTE 3,0,53,13
	DATA BYTE 2,0,48,13
	DATA BYTE 2,0,44,13
	DATA BYTE 2,0,40,13
	DATA BYTE 2,0,36,13
	DATA BYTE 2,0,33,13
	DATA BYTE 2,0,30,13
	DATA BYTE 3,0,27,13
	DATA BYTE 0,0,0,0

	' D -- the rise carried up past the measured top, to divisor 72.
	DATA BYTE 3,0,53,13
	DATA BYTE 3,0,44,13
	DATA BYTE 3,0,36,13
	DATA BYTE 3,0,27,13
	DATA BYTE 5,0,18,13
	DATA BYTE 0,0,0,0

	' ================= 5 TALLY =================
	' A -- MEASURED. The short blips that punctuate the quiet stretches sit at
	' divisor 496, about 226 Hz, two frames long. As a counting tick.
	DATA BYTE 2,0,124,13
	DATA BYTE 2,255,0,0
	DATA BYTE 2,0,124,13
	DATA BYTE 2,255,0,0
	DATA BYTE 2,0,124,13
	DATA BYTE 2,255,0,0
	DATA BYTE 2,0,124,13
	DATA BYTE 2,255,0,0
	DATA BYTE 2,0,124,13
	DATA BYTE 2,255,0,0
	DATA BYTE 0,0,0,0

	' B -- the same tick twice as fast: a tally that hurries.
	DATA BYTE 1,0,124,13
	DATA BYTE 1,255,0,0
	DATA BYTE 1,0,124,13
	DATA BYTE 1,255,0,0
	DATA BYTE 1,0,124,13
	DATA BYTE 1,255,0,0
	DATA BYTE 1,0,124,13
	DATA BYTE 1,255,0,0
	DATA BYTE 1,0,124,13
	DATA BYTE 1,255,0,0
	DATA BYTE 1,0,124,13
	DATA BYTE 1,255,0,0
	DATA BYTE 0,0,0,0

	' C -- a high tick, divisor 72, which separates it from the timer's own
	' low tock rather than doubling it.
	DATA BYTE 2,0,18,13
	DATA BYTE 2,255,0,0
	DATA BYTE 2,0,18,13
	DATA BYTE 2,255,0,0
	DATA BYTE 2,0,18,13
	DATA BYTE 2,255,0,0
	DATA BYTE 2,0,18,13
	DATA BYTE 2,255,0,0
	DATA BYTE 2,0,18,13
	DATA BYTE 2,255,0,0
	DATA BYTE 0,0,0,0

	' D -- a noise tick instead of a tone: a counter rather than a note.
	DATA BYTE 2,3,4,13
	DATA BYTE 2,255,0,0
	DATA BYTE 2,3,4,13
	DATA BYTE 2,255,0,0
	DATA BYTE 2,3,4,13
	DATA BYTE 2,255,0,0
	DATA BYTE 2,3,4,13
	DATA BYTE 2,255,0,0
	DATA BYTE 2,3,4,13
	DATA BYTE 2,255,0,0
	DATA BYTE 0,0,0,0

	' ================= 6 ROUND =================
	' A -- MEASURED. Twice in the recording, roughly forty-six seconds apart
	' and so almost certainly the round boundary, a tone HOLDS at divisor 108
	' (about 1035 Hz) for two full seconds.
	DATA BYTE 60,0,27,13
	DATA BYTE 60,0,27,13
	DATA BYTE 0,0,0,0

	' B -- the held tone with ticks OVER it. NOWAIT sets the bed on channel 1
	' and carries on, so the ticks on channel 0 play across it; SILENCE kills
	' only the tick channels, so the bed survives to the end of the effect.
	DATA BYTE 254,1,27,11
	DATA BYTE 3,0,18,13
	DATA BYTE 5,255,0,0
	DATA BYTE 3,0,18,13
	DATA BYTE 5,255,0,0
	DATA BYTE 3,0,18,13
	DATA BYTE 5,255,0,0
	DATA BYTE 3,0,18,13
	DATA BYTE 5,255,0,0
	DATA BYTE 0,0,0,0

	' C -- half as long. Two seconds is a long time to hold one note, and the
	' question is whether the recording's length is the effect or the pause
	' after it.
	DATA BYTE 30,0,27,13
	DATA BYTE 0,0,0,0

	' D -- two notes rather than one held: the same duration, with a step down
	' in the middle so it resolves instead of simply stopping.
	DATA BYTE 40,0,27,13
	DATA BYTE 40,0,36,13
	DATA BYTE 0,0,0,0

	' END OF TABLE
	DATA BYTE 255,0,0,0
