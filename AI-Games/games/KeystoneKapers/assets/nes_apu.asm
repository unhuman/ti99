	;
	; SN76489 -> NES 2A03 APU shim for CVBasic's --nes target.
	;
	; CVBasic's 6502 code generator emits `JSR sn76489_freq/_vol/_control`
	; for every SOUND statement, and cvbasic_6502_prologue.asm defines those
	; three -- for a 6502 machine with a REAL SN76489 wired to it. The NES
	; prologue does not, because the NES has a 2A03 APU instead, so an --nes
	; build of anything that uses SOUND ends with undefined labels. In
	; Keystone Kapers that was 36 of the 40 errors.
	;
	; This defines them against the APU. The calling convention is taken
	; from nanochess's own 6502 versions rather than invented:
	;
	;   sn76489_freq     A = divisor low, Y = divisor high, X = latch byte
	;   sn76489_vol      A = volume 0-15 (15 loudest), X = latch byte
	;   sn76489_control  A = noise control, bits 0-1 rate, bit 2 white
	;
	; and the latch byte's bits 6-5 are the channel: $80 ch0, $A0 ch1,
	; $C0 ch2, $E0 noise.
	;
	; THE PITCH MATHS IS ALMOST EXACT, BY LUCK. The NES CPU runs at
	; 1.789773 MHz, which is very nearly half the SN76489's 3.579545 MHz:
	;
	;   SN    f = 3579545 / (32 * divisor)  =  111860 / divisor
	;   NES   f = 1789773 / (16 * (t + 1))
	;   so    t + 1 = 1789773 * divisor / 1789760  =  divisor  (to 1 part in
	;                                                           137,000)
	;
	; so the APU timer is simply divisor - 1 and no division is needed. A
	; divisor is 10 bits and the APU timer is 11, so nothing clips.
	;
	; WHAT IS LOST, STATED PLAINLY:
	;
	; o THE TRIANGLE HAS NO VOLUME. Channel 2 maps to it because the APU
	;   has only two pulse channels, and the triangle is on or off -- so
	;   channel 2 keeps its pitch and loses its fades. In this game that is
	;   the prize arpeggio and the bonus tally, both of which are written as
	;   discrete notes rather than as decays, so they survive; a channel-2
	;   fade elsewhere would simply stop being a fade.
	;
	; o THE TRIANGLE IS AN OCTAVE OFF IF LEFT ALONE. It divides by 32 rather
	;   than 16, so it takes half the period for the same note. Halved here.
	;
	; o NOISE IS APPROXIMATE. The SN76489 picks a shift rate; the APU picks
	;   from a 16-entry period table. The mapping below is by ear-less
	;   judgement and is the one part of this worth re-tuning on hardware.
	;
	; NONE OF THIS IS TESTED ON A NES. It assembles and the arithmetic is
	; checked, but nobody has heard it.
	;

APU_P1CTL:	EQU $4000
APU_P1SWP:	EQU $4001
APU_P1LO:	EQU $4002
APU_P1HI:	EQU $4003
APU_P2CTL:	EQU $4004
APU_P2SWP:	EQU $4005
APU_P2LO:	EQU $4006
APU_P2HI:	EQU $4007
APU_TRICTL:	EQU $4008
APU_TRILO:	EQU $400a
APU_TRIHI:	EQU $400b
APU_NSVOL:	EQU $400c
APU_NSPER:	EQU $400e
APU_STATUS:	EQU $4015

	;
	; Set a channel's pitch.  A/Y = divisor, X = latch byte.
	;
sn76489_freq:
	STA temp
	STY temp+1
	TXA
	AND #$60		; $00 ch0, $20 ch1, $40 ch2
	STA temp2
	LDA temp		; t = divisor - 1
	SEC
	SBC #$01
	STA temp
	LDA temp+1
	SBC #$00
	STA temp+1
	LDA temp2
	CMP #$40
	BEQ nesapu_ftri
	CMP #$20
	BEQ nesapu_fp2
	LDA temp
	STA APU_P1LO
	LDA temp+1
	AND #$07
	STA APU_P1HI
	RTS
nesapu_fp2:
	LDA temp
	STA APU_P2LO
	LDA temp+1
	AND #$07
	STA APU_P2HI
	RTS
nesapu_ftri:
	LSR temp+1		; half the period -- see the octave note above
	ROR temp
	LDA temp
	STA APU_TRILO
	LDA temp+1
	AND #$07
	STA APU_TRIHI
	RTS

	;
	; Set a channel's volume.  A = 0-15 with 15 loudest, X = latch byte.
	;
	; The SN76489 takes ATTENUATION and nanochess's version inverts for it;
	; the APU takes volume directly, so no inversion happens here. Volume 0
	; is silence on both, which is what every note-off in the game writes.
	;
sn76489_vol:
	STA temp2
	LDA #$0f		; enable all four channels; volume 0 is the mute
	STA APU_STATUS
	LDA #$08		; sweep units off, or a pulse silences itself
	STA APU_P1SWP
	STA APU_P2SWP
	TXA
	AND #$60
	CMP #$40
	BEQ nesapu_vtri
	CMP #$60
	BEQ nesapu_vns
	CMP #$20
	BEQ nesapu_vp2
	LDA temp2
	AND #$0f
	ORA #$b0		; 50% duty, length halted, constant volume
	STA APU_P1CTL
	RTS
nesapu_vp2:
	LDA temp2
	AND #$0f
	ORA #$b0
	STA APU_P2CTL
	RTS
nesapu_vns:
	LDA temp2
	AND #$0f
	ORA #$30		; length halted, constant volume
	STA APU_NSVOL
	RTS
nesapu_vtri:
	LDA temp2		; on or off, and nothing between
	AND #$0f
	BEQ nesapu_vtoff
	LDA #$ff		; control set, reload $7f -- runs until halted
	STA APU_TRICTL
	RTS
nesapu_vtoff:
	LDA #$00
	STA APU_TRICTL
	RTS

	;
	; Noise control.  A = SN76489 noise byte: bits 0-1 rate, bit 2 white.
	;
sn76489_control:
	STA temp2
	AND #$03
	TAY
	LDA nesapu_nper,Y
	STA temp
	LDA temp2
	AND #$04		; set = white, clear = periodic
	BNE nesapu_cwhite
	LDA temp
	ORA #$80		; short (periodic) mode
	STA APU_NSPER
	RTS
nesapu_cwhite:
	LDA temp
	STA APU_NSPER
	RTS

	; SN rates 0,1,2 are N/512, N/1024, N/2048 -- each an octave down --
	; and rate 3 takes its pitch from channel 2, which the APU cannot do.
	; Three APU period indices two apart are the nearest honest equivalent;
	; rate 3 gets the lowest of them rather than silence.
nesapu_nper:
	DB $04,$06,$08,$0a
