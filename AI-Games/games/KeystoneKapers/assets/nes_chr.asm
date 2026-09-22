; ---------------------------------------------------------------------------
; nes_chr.asm -- what DEFINE would have done, for the one machine that has no
; DEFINE.
;
; CVBasic's NES target implements NO form of DEFINE (cvbasic.c: `if (machine ==
; NES) emit_error("DEFINE isn't implemented for NES")`), and the usual reading
; of that -- "patterns live in CHR, which is cartridge ROM, so there is nothing
; to compile it to" -- is only half true. An iNES header whose CHR-bank count is
; ZERO asks the console for 8 KB of CHR-*RAM* instead, and that is the header
; CVBasic emits whenever the program uses no BITMAP/CHRROM statement:
; NES_CHR_BANKS is written from chrrom_size, which stays 0. Keystone Kapers'
; --nes build has always had a writable pattern table; nothing was writing to
; it.
;
; So the pattern table here is ordinary VRAM behind PPUADDR/PPUDATA, which is
; all DEFINE CHAR ever was. This file is the port's whole video layer:
;
;   nes_chrup   convert/upload TMS patterns, rendering off
;   nes_chrraw  upload native NES 2bpp static tiles, rendering off
;   nes_chrq    upload patterns through the NMI queue, for the escalator
;   nes_oam2    the right-hand half of every 16x16 actor
;   nes_bgbank  put background patterns at $1000 so sprites can have $0000
;   nes_apuon   enable the APU, once, whatever the game plays
;
; ---------------------------------------------------------------------------
; COLOUR, AND WHY IT COMES OUT OF THE GAME'S OWN COLOUR TABLE
;
; A TMS9918 cell selects foreground/background colours for each 8-pixel
; row. NES tiles encode two bitplanes; each 16x16 attribute quadrant selects
; one of four palettes. The uploader converts each row's colours into indices:
;
;   0  shared grey during gameplay <- TMS transparent, dark red, grey
;   1  regional paper              <- greens, blues, light reds, magenta
;   2  regional alternate          <- black, cyan
;   3  gold highlights             <- yellows, white
;
; gennescolor.py preconverts static store tiles and supplies screen attributes.
; Shared grey preserves the structure while counters get a blue alternate.
; Black fixture outlines need P0; HUD reserve hats use a sprite palette.
;
; PER-SCAN-LINE COLOUR IS **NOT** LOST, and the note that used to sit here
; saying it was is what flattened the floor bars for a session. An NES tile is
; eight rows of two bits per pixel, so each ROW chooses its own pair out of the
; four entries -- the same shape as the TMS's eight colour bytes. What is
; actually lost is per-scan-line colour beyond FOUR indices. The masks are
; therefore rebuilt once per row (nes_chrinkrow), not once per character; read
; the note there before changing it, because several characters carry ALL their
; shape in the colour table and none in the art.
;
; Sprites keep one bitplane (index 1) and take their colour from the OAM
; attribute byte instead, which is per sprite -- so the layered-sprite idiom
; the TMS version uses survives unchanged.
; ---------------------------------------------------------------------------
;
; nes_chrup -- copy `ncnt` 8-byte patterns from `#nsrc` to tile `nchr`.
;
; Inputs, all ordinary CVBasic variables the caller sets first:
;   #nsrc  VARPTR of the DATA BYTE label holding the art
;   nchr   first tile number
;   ncnt   how many tiles
;   ntab   0 = sprite pattern table ($0000), 1 = background table ($1000)
;   #ncol  VARPTR of the matching 8-bytes-per-character colour table, or 0
;   nink   the ink index to use when #ncol is 0 (3 for text, 1 for sprites)
;
; IT WAITS FOR VBLANK AND TURNS RENDERING OFF, and neither is optional. The PPU
; address register is shared with the rendering fetch, so a write during a
; visible frame lands somewhere unpredictable; and the NMI handler drives
; PPUADDR itself, so it would step on this copy mid-tile. NMI therefore goes off
; FIRST, before the wait -- otherwise the vblank being waited for is the one the
; handler takes. Both registers are restored from the shadows the prologue
; keeps, so the next NMI puts the real values back.
;
; That costs a frame per call, which is nothing at setup and too much in the
; main loop -- see nes_chrq, which the escalator uses instead.
; ---------------------------------------------------------------------------
nes_chrup:
	LDA #0
	STA PPUCTRL		; NMI off -- it drives PPUADDR itself
	STA PPUMASK		; rendering off -- see the note above
	BIT PPUSTATUS		; drop a stale flag, then wait for a real vblank
nes_chrup_vb:
	BIT PPUSTATUS
	BPL nes_chrup_vb

	JSR nes_chraddr
	LDA temp+1
	STA PPUADDR
	LDA temp
	STA PPUADDR
	JSR nes_chrinit

nes_chrup_char:
	LDY #0
nes_chrup_p0:
	JSR nes_chrinkrow	; this ROW's colours, not the character's
	JSR nes_chrp0
	STA PPUDATA
	INY
	CPY #8
	BNE nes_chrup_p0
	LDY #0
nes_chrup_p1:
	JSR nes_chrinkrow
	JSR nes_chrp1
	STA PPUDATA
	INY
	CPY #8
	BNE nes_chrup_p1
	JSR nes_chrnext
	BNE nes_chrup_char

	LDA ppu_ctrl
	STA PPUCTRL
	LDA ppu_mask
	STA PPUMASK
	RTS

; Native 2bpp upload for NES-specific static art. Same destination inputs as
; nes_chrup, but #nsrc contains 16 bytes per tile. Rendering/NMI stay off for
; the entire copy, including source page crossings; no game RAM is added.
nes_chrraw:
	LDA #0
	STA PPUCTRL
	STA PPUMASK
	BIT PPUSTATUS
nes_chrraw_vb:
	BIT PPUSTATUS
	BPL nes_chrraw_vb
	JSR nes_chraddr
	LDA temp+1
	STA PPUADDR
	LDA temp
	STA PPUADDR
	LDA cvb_#NSRC
	STA pointer
	LDA cvb_#NSRC+1
	STA pointer+1
	LDA cvb_NCNT
	STA temp2
nes_chrraw_tile:
	LDY #0
nes_chrraw_byte:
	LDA (pointer),Y
	STA PPUDATA
	INY
	CPY #16
	BNE nes_chrraw_byte
	CLC
	LDA pointer
	ADC #16
	STA pointer
	BCC nes_chrraw_next
	INC pointer+1
nes_chrraw_next:
	DEC temp2
	BNE nes_chrraw_tile
	LDA ppu_ctrl
	STA PPUCTRL
	LDA ppu_mask
	STA PPUMASK
	RTS

; ---------------------------------------------------------------------------
; nes_chrq -- the same upload, but queued for the NMI to flush.
;
; THE ESCALATOR REWRITES SIX CHARACTERS EVERY PASS, and putting that through
; nes_chrup cost a whole frame each time: NMI goes off, the routine waits for a
; vblank the handler therefore never services, and the game's own WAIT then
; waits for the one after. On an escalator screen -- the busiest in the store --
; that was the difference between a loop that keeps up and one that visibly
; does not.
;
; Six characters is 96 bytes of pattern table and they are CONTIGUOUS, so they
; go as ONE of the NMI queue's copy descriptors: five bytes in PPUBUF, no
; rendering turned off, no frame lost. The transform cannot be done from ROM in
; the handler, so the colour-mapped bytes are built into a RAM buffer first --
; which is what `#nesb` points at, and why it must be at least ncnt*16 bytes.
;
; Inputs: as nes_chrup, plus #nesb.
; ---------------------------------------------------------------------------
nes_chrq:
	LDA cursor		; borrowed below, and it belongs to PRINT
	PHA
	LDA cursor+1
	PHA
	JSR nes_chrinit
	LDA cvb_#NESB		; cursor walks the RAM buffer
	STA cursor
	LDA cvb_#NESB+1
	STA cursor+1

nes_chrq_char:
	LDY #0
nes_chrq_p0:
	JSR nes_chrinkrow	; this ROW's colours, not the character's
	JSR nes_chrp0
	STA (cursor),Y
	INY
	CPY #8
	BNE nes_chrq_p0
nes_chrq_p1:
	TYA			; Y is 8 here, and plane 1 wants the pattern
	SEC			; byte eight BACK -- so index the source with
	SBC #8			; Y-8 while the destination runs 8..15.
	TAY
	JSR nes_chrinkrow	; Y is the row again here, so the colours match
	JSR nes_chrp1
	PHA
	TYA
	CLC
	ADC #8
	TAY
	PLA
	STA (cursor),Y
	INY
	CPY #16
	BNE nes_chrq_p1
	LDA cursor		; sixteen bytes on
	CLC
	ADC #16
	STA cursor
	BCC nes_chrq_nc
	INC cursor+1
nes_chrq_nc:
	JSR nes_chrnext
	BNE nes_chrq_char

	JSR nes_chraddr	; pointer = the VRAM address LDIRVM wants
	LDA temp
	STA pointer
	LDA temp+1
	STA pointer+1
	LDA cvb_#NESB		; temp = the RAM buffer
	STA temp
	LDA cvb_#NESB+1
	STA temp+1
	LDA cvb_NCNT		; temp2 = ncnt * 16 bytes
	ASL A
	ASL A
	ASL A
	ASL A
	STA temp2
	JSR LDIRVM
	PLA
	STA cursor+1
	PLA
	STA cursor
	RTS

; ------------------------------------------------- the pieces both of them use

	; temp = the PPU address of tile `nchr` in table `ntab`.
nes_chraddr:
	LDA cvb_NCHR
	STA temp
	LDA #0
	STA temp+1
	ASL temp
	ROL temp+1
	ASL temp
	ROL temp+1
	ASL temp
	ROL temp+1
	ASL temp
	ROL temp+1
	LDA cvb_NTAB
	BEQ nes_chraddr_spr
	LDA temp+1
	ORA #$10
	STA temp+1
nes_chraddr_spr:
	RTS

	; pointer = the art, read_pointer = the colour table, temp2 = the count.
nes_chrinit:
	LDA cvb_#NSRC
	STA pointer
	LDA cvb_#NSRC+1
	STA pointer+1
	LDA cvb_#NCOL
	STA read_pointer
	LDA cvb_#NCOL+1
	STA read_pointer+1
	LDA cvb_NCNT
	STA temp2
	RTS

	; THE MASKS FOR ONE SCAN LINE. Y is the row on the way in, and Y is still
	; the row on the way out.
	;
	; PER-SCANLINE COLOUR IS NOT LOST ON THIS MACHINE, AND BELIEVING IT WAS IS
	; WHAT FLATTENED THE FLOOR BARS. A TMS character carries EIGHT colour
	; bytes, one per scan line. An NES tile is eight rows of two bits per
	; pixel, so every ROW picks its own pair out of the four palette entries,
	; independently of the rows above and below. The two are the same shape.
	; What the NES cannot do is per-scanline colour beyond FOUR indices -- not
	; per-scanline colour as such.
	;
	; Reading ONE byte for the whole character threw that away, and the floor
	; bar is where it showed. CH_SLAB's pattern sets 8 of its 64 pixels -- a
	; single row -- because the bar's five yellow rows over three green ones
	; live entirely in the COLOUR table and not in the art at all. Collapsed
	; to one pair, the floor became a one-pixel line, and the end wall then
	; stopped meeting the storey above it: reported as the building's support
	; having a gap in it, which is a colour bug wearing a structural costume.
	;
	; So this is called once per ROW. read_pointer stays put; the CHARACTER
	; advances it, in nes_chrnext.
	;
	; result = plane-0 ink mask, result+1 = plane-0 paper mask,
	; temp   = plane-1 ink mask, temp+1   = plane-1 paper mask.
nes_chrinkrow:
	TYA
	PHA			; the row index, handed back at the end
	LDA read_pointer
	ORA read_pointer+1
	BNE nes_chrinkrow_tbl
	LDX cvb_NINK		; no table: ink `nink` on the backdrop
	LDY #0
	JMP nes_chrinkrow_set
nes_chrinkrow_tbl:
	LDA (read_pointer),Y	; THIS row's own colour byte
	PHA
	LSR A
	LSR A
	LSR A
	LSR A
	TAY
	LDA nes_inkmap,Y
	TAX			; X = the ink index
	PLA
	AND #$0F
	TAY
	LDA nes_inkmap,Y
	TAY			; Y = the paper index
nes_chrinkrow_set:
	LDA nes_m0,X
	STA result
	LDA nes_m1,X
	STA temp
	TYA
	TAX
	LDA nes_m0,X
	STA result+1
	LDA nes_m1,X
	STA temp+1
	PLA
	TAY			; the row index again, for the pattern fetch
	RTS

	; One byte of plane 0 / plane 1 for source row Y, ink where the art has
	; a bit and paper where it has not.
nes_chrp0:
	LDA (pointer),Y
	AND result
	STA temp2+1
	LDA (pointer),Y
	EOR #$FF
	AND result+1
	ORA temp2+1
	RTS
nes_chrp1:
	LDA (pointer),Y
	AND temp
	STA temp2+1
	LDA (pointer),Y
	EOR #$FF
	AND temp+1
	ORA temp2+1
	RTS

	; Advance to the next character; Z set when there are none left.
nes_chrnext:
	LDA pointer
	CLC
	ADC #8
	STA pointer
	BCC nes_chrnext_nc
	INC pointer+1
nes_chrnext_nc:
	; AND THE COLOUR TABLE WITH IT -- eight bytes a character, one per scan
	; line. This used to be done inside the mask lookup, which was called once
	; per character; the lookup now runs once per ROW and must not move the
	; pointer, so the step belongs here beside the pattern's.
	;
	; ZERO MEANS "NO COLOUR TABLE" AND MUST STAY ZERO. nink is used instead in
	; that case, and the test for it is `read_pointer == 0` -- so advancing it
	; blindly would turn the second character of every text upload into a read
	; from address 8.
	LDA read_pointer
	ORA read_pointer+1
	BEQ nes_chrnext_dec
	LDA read_pointer
	CLC
	ADC #8
	STA read_pointer
	BCC nes_chrnext_dec
	INC read_pointer+1
nes_chrnext_dec:
	DEC temp2
	RTS

	; TMS colour -> NES index. Gameplay shares GREY at index 0, freeing
	; one palette entry in every region. Black maps to index 2: black in
	; P0/P2, pink in P1, blue in P3. Green/blue paper maps to index 1;
	; gold/white highlights map to 3. Per-row NES colour data distinguishes
	; counters and skyline from the TMS art (assets/gennescolor.py).
	; HUD hats use the separate black sprite palette, not P1's pink entry.
	; Fixtures switch their quadrants to P0 to retain black outlines.
nes_inkmap:
	;              0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15
	DB 0,2,1,1,1,1,0,2,1,1,3,3,1,1,0,3

	; THE THREE PAIRS THAT MATTER, and they are not obvious:
	;
	;   WHITE must differ from MAGENTA and LRED, or the partial buildings
	;   standing against the sunset (characters 152 and 153) collapse to a
	;   SOLID WHITE BLOCK on the roof -- which is what was reported from play
	;   as "the floor beyond the top of the escalators is a white block".
	;
	;   WHITE must differ from GRAY, or the store's floor bars stop reading
	;   against its pillars.
	;
	;   CYAN must differ from LBLUE, or the counter top (character 99) goes
	;   solid. An earlier version of this table merged them and assets/
	;   checkink.py caught it before it was built.
	;
	; Three characters still collapse and all three are MEANT to -- 100 and
	; 107 are a flat counter column, 179 is the black strip beside the radar.
	; They are solid by design and have no second colour to lose.

	; index -> "is bit 0 set" / "is bit 1 set", as a byte mask.
nes_m0:	DB $00,$FF,$00,$FF
nes_m1:	DB $00,$00,$FF,$FF

; ---------------------------------------------------------------------------
; nes_oam2 -- the right-hand half of every actor, in one call.
;
; A TMS9918 sprite is 16x16 and an NES sprite is 8x16, so each of this game's
; actors needs TWO OAM entries. The alternative to this routine was a second
; `SPRITE` statement beside each of the twenty-eight existing ones, every one of
; them a place for the two halves to drift apart.
;
; THE ART NEEDS NO REPACKING, which is the piece of luck the whole port turns
; on. A 16x16 TMS pattern is four 8-byte tiles in the order
; left-top, left-bottom, right-top, right-bottom -- and an NES 8x16 sprite is a
; tile pair, top then bottom, at an EVEN index. So tiles (p, p+1) are already
; exactly the left half and (p+2, p+3) exactly the right half. Every pattern
; number in this game is a multiple of four, so both are even, and bit 0 of the
; OAM tile byte -- which selects the pattern table in 8x16 mode -- is 0, i.e.
; $0000. That is why nes_bgbank moves the BACKGROUND to $1000 instead.
;
; Slots 0-27 are the game's; 28-55 are their right halves; 56-63 hold the HUD hats; hidden hats are parked at
; y=$F0 by the prologue's clear_sprites. Hidden sprites copy across as hidden,
; so nothing has to know which slots are live.
; ---------------------------------------------------------------------------
NES_OAM_PAIRS:	EQU 28
NES_OAM_STEP:	EQU NES_OAM_PAIRS*4

; THE X IS DONE FIRST, AND THAT IS THE WHOLE POINT OF THE ORDERING.
;
; An NES sprite's x is ONE BYTE. The right half is the left half plus eight, so
; any actor at x >= 248 wraps: 250 + 8 is 2, and the half lands at the FAR LEFT
; while the other half is still at the right edge. On screen the player is at
; both edges of the store at once, which reads as a sprite bug and is really a
; byte overflowing.
;
; The TMS9918 has the same one-byte x and does not do this, because there a
; 16-wide sprite is ONE entry that the VDP clips at the edge. Splitting it into
; two 8-wide entries is what exposes the arithmetic, so this is a hazard the
; port introduced rather than one it inherited.
;
; Hiding the half costs nothing: those eight columns are off the right of the
; screen anyway. At x=247 the add does not carry and the half still shows its
; one visible column, so the cut is exactly at the point where there is nothing
; left to draw.
nes_oam2:
	LDX #0
nes_oam2_loop:
	LDA $0203,X			; x -- eight pixels right
	CLC
	ADC #8
	STA $0203+NES_OAM_STEP,X
	BCC nes_oam2_y
	LDA #$F0			; wrapped: park it off-screen, as the
	STA $0200+NES_OAM_STEP,X	; prologue's own clear_sprites does
	JMP nes_oam2_tile
nes_oam2_y:
	LDA $0200,X			; y -- same row
	STA $0200+NES_OAM_STEP,X
nes_oam2_tile:
	LDA $0201,X			; tile -- two on is the right-hand column
	CLC
	ADC #2
	STA $0201+NES_OAM_STEP,X
	LDA $0202,X			; colour -- see nes_spal
	AND #$0F
	TAY
	LDA nes_spal,Y
	STA $0202,X			; and back into the left half as well
	STA $0202+NES_OAM_STEP,X
	TXA				; on to the next entry, four bytes along
	CLC
	ADC #4
	TAX
	CPX #NES_OAM_STEP
	BNE nes_oam2_loop
	RTS

	; TMS COLOUR -> ONE OF THE FOUR SPRITE PALETTES.
	;
	; The SPRITE statements all over the game pass a TMS colour 0-15, and the
	; NES reads only the low two bits of that byte as a palette number -- so
	; without this, C_SKIN (11) and C_HARRY (15) both landed on palette 3 and
	; the crook's face was the same white as his shirt. This maps properly:
	;
	;   0  blue    <- 4 5 dark and light blue, 7 cyan   (Kelly's trousers)
	;   1  black   <- 1                                 (hats, stripes, the Kop dot)
	;   2  skin    <- 6 8 9 reds, 10 11 yellows, 13     (faces, the plane, the ball)
	;   3  white   <- 2 3 12 greens, 14 grey, 15 white  (Harry, carts, the lift)
	;
	; IT IS APPLIED IN PLACE, to the game's own slot as well as to the mirror,
	; because a slot the game did not rewrite this pass would otherwise be
	; mapped twice. That is safe only because the table is IDEMPOTENT --
	; nes_spal(nes_spal(c)) = nes_spal(c) for every c -- which is why entry 2
	; is 3 and entries 0, 1 and 3 are themselves.
	; AND IT MUST BE IDEMPOTENT, WHICH IT WAS NOT -- ENTRY 2 SAID 3.
	;
	; nes_oam2 applies this map IN PLACE, every frame, to slots the game did
	; not rewrite. So the map's own OUTPUTS are fed back into it, and each of
	; 0..3 has to map to itself or the colour WALKS. Entry 2 mapped to 3, so
	; anything that landed on palette 2 became palette 3 on the very next
	; frame: skin turned white.
	;
	; It read as a FLASH rather than as a wrong colour, because the game keeps
	; rewriting the slot. The lift car on the radar is redrawn every sixth
	; frame by scan_tick, so it showed one frame of its real colour and five
	; of white, over and over. Measured, not guessed: the marker was present in
	; all twelve sampled frames and only its COLOUR alternated.
	;
	; Every actor whose colour maps to palette 2 had it -- C_SKIN (both faces),
	; the biplane, the beach ball -- so the faces were white for five frames in
	; six as well. Entry 2 is TMS medium green, which no sprite in this game
	; uses, so pointing it at itself costs nothing.
	; ENTRY 14 IS THE LIFT CAR, AND IT HAS TO AGREE WITH ITS OWN LOW BITS.
	; The PPU reads only bits 0-1 of the attribute byte, so a slot that still
	; holds the RAW TMS colour renders as `colour AND 3`. Grey is 14, whose low
	; bits are 2 -- but this table used to send it to 3, so the car rendered
	; ORANGE on the frame scan_tick wrote it and WHITE once nes_oam2 had been
	; over it. Sending 14 to 2 makes the two readings the same value, so there
	; is no frame where it disagrees with itself. Grey is the car's colour and
	; nothing else's, so this costs no other sprite.
nes_spal:
	DB 0,1,2,3,0,0,2,0,2,2,2,2,3,2,2,3

; ---------------------------------------------------------------------------
; nes_bgbank -- background patterns at $1000, sprite patterns at $0000.
;
; CVBasic boots with ppu_ctrl = $A8: NMI on, 8x16 sprites, background at $0000.
; In 8x16 mode the sprite pattern table is chosen by bit 0 of each OAM tile byte
; and the PPUCTRL sprite bit is ignored -- and every pattern number in this game
; is a multiple of four, so that bit is always 0 and the sprites are nailed to
; $0000. Setting bit 4 here moves the BACKGROUND out of their way instead.
;
; It also happens to put the background patterns at address 4096, which is
; exactly where they sat in the TMS bitmap mode's third screen third -- so the
; radar, which writes pixel rows straight into pattern memory, needs a stride
; and nothing else.
; ---------------------------------------------------------------------------
nes_bgbank:
	LDA #$B8
	STA ppu_ctrl
	STA PPUCTRL
	RTS

; ---------------------------------------------------------------------------
; nes_apuon -- enable the APU once, rather than hoping a note does it.
;
; This routine owns channel enable and sweep setup. Individual sound writes
; must not touch the global enable register or another channel's sweep.
; The frame counter at $4017 also matters: the
; power-on value is the 4-step mode with its IRQ enabled, which is not what this
; wants. Both are cheap to nail down here and then never think about.
; ---------------------------------------------------------------------------
nes_apuon:
	LDA #$40		; 4-step sequence, no IRQ
	STA $4017
	LDA #$0F		; pulse 1, pulse 2, triangle, noise all enabled
	STA $4015
	LDA #$08		; sweep units off -- a sweep with shift 0 can mute
	STA $4001
	STA $4005
	RTS


; Attribute staging borrows the 96-byte CHR buffer during draw_screen only.
; begin follows WAIT (old CHR descriptor consumed); put is followed by WAIT
; before the main loop may overwrite the buffer for escalator animation.
nes_attrs_begin:
	LDA cvb_KLSC
	LSR A
	LSR A
	CLC
	ADC #cvb_NES_ATTRS/256
	STA pointer+1
	LDA cvb_KLSC
	ASL A
	ASL A
	ASL A
	ASL A
	ASL A
	ASL A
	CLC
	ADC #cvb_NES_ATTRS%256
	STA pointer
	BCC nes_attrs_nocarry
	INC pointer+1
nes_attrs_nocarry:
	LDY #63
nes_attrs_copy:
	LDA (pointer),Y
	STA array_NESB,Y
	DEY
	BPL nes_attrs_copy
	RTS

; Reset each quadrant touched by a two-by-two prize/radio to P0. Unlike
; clearing a whole attribute byte, this preserves neighbouring blue counters.
nes_fixture_pal:
	LDX #0
nes_fixture_cell:
	TXA
	PHA
	LDA nes_fixture_offsets,X
	CLC
	ADC cvb_#PVA
	STA pointer
	LDA cvb_#PVA+1
	ADC #0
	AND #3
	ASL A
	ASL A
	ASL A
	ASL A
	STA temp
	LDA pointer
	LSR A
	LSR A
	LSR A
	LSR A
	AND #$38
	ORA temp
	STA temp
	LDA pointer
	LSR A
	LSR A
	AND #7
	ORA temp
	TAX
	LDA pointer
	AND #$40
	LSR A
	LSR A
	LSR A
	LSR A
	LSR A
	STA temp
	LDA pointer
	AND #2
	LSR A
	ORA temp
	TAY
	LDA array_NESB,X
	AND nes_fixture_masks,Y
	STA array_NESB,X
	PLA
	TAX
	INX
	CPX #4
	BNE nes_fixture_cell
	RTS
nes_fixture_offsets: DB 0,1,32,33
nes_fixture_masks: DB $FC,$F3,$CF,$3F

nes_attrs_put:
	LDX #3
nes_message_attrs:
	LDA array_NESB+26,X
	AND #15
	STA array_NMSG,X
	LDA array_NESB+34,X
	AND #240
	ORA array_NMSG,X
	STA array_NMSG,X
	DEX
	BPL nes_message_attrs
	LDA #$C0
	STA pointer
	LDA #$23
	STA pointer+1
	LDA #array_NESB%256
	STA temp
	LDA #array_NESB/256
	STA temp+1
	LDA #64
	STA temp2
	JSR LDIRVM
	RTS

; Reserve hats use black palette 1 and OAM 56..63, outside actor pairs.
; Five hats at most; six or more reserves show one hat followed by xN.
; Tile 199 selects CHR $1000, pair 198/199 (hat, transparent bottom).
nes_hats:
	LDX #28
	LDY cvb_SPARE
	CPY #6
	BCC nes_hats_loop
	LDY #1
nes_hats_loop:
	LDA #$F0
	CPY #0
	BEQ nes_hats_y
	LDA #15
	DEY
nes_hats_y:
	STA $02E0,X
	LDA #199
	STA $02E1,X
	LDA #1
	STA $02E2,X
	LDA cvb_SPARE
	CMP #6
	BCC nes_hats_margin
	TXA
	ASL A
	CLC
	ADC #160
	JMP nes_hats_x
nes_hats_margin:
	TXA
	ASL A
	CLC
	ADC #176
nes_hats_x:
	STA $02E3,X
	DEX
	DEX
	DEX
	DEX
	BPL nes_hats_loop
	RTS
nes_hats_hide:
	LDA #$F0
	STA $02E0
	STA $02E4
	STA $02E8
	STA $02EC
	STA $02F0
	STA $02F4
	STA $02F8
	STA $02FC
	RTS

; NES-only replacement for the keypad setup. Reuse the BASIC menu scratch
; variables; no new RAM. CVBasic joy bits: U=1 R=2 D=4 L=8 B=$40 A=$80.
; Full releases re-arm input. Wrong directions/diagonals reset the code;
; another LEFT starts a fresh attempt. A held direction advances only once.
nes_title_code:
	LDA joy1_data
	AND #$CF
	CMP cvb_TKL
	BEQ nes_title_return
	STA cvb_TKL
	CMP #0
	BEQ nes_title_return
	LDY cvb_T838
	CMP nes_title_sequence,Y
	BEQ nes_title_next
	LDY #0
	CMP #8
	BNE nes_title_reset
	INY
nes_title_reset:
	STY cvb_T838
	RTS
nes_title_next:
	INC cvb_T838
nes_title_return:
	RTS
nes_title_sequence:
	DB 8,2,1,4

; SK=current value, SUT=maximum, #SUA=two-digit name-table destination.
; Up/right increase, down/left decrease, clamped. Either fire button confirms;
; directions repeat every 15 frames (one quarter of a second at 60 Hz). NINK/TKL/NAI
; are existing NES/title scratch bytes. Release before returning prevents
; the same press confirming the next field or jumping at the start of play.
nes_choose:
	JSR nes_choose_draw
	JSR nes_menu_release
	LDA #0
	STA cvb_TKL
	STA cvb_NAI
nes_choose_wait:
	JSR wait
	LDA joy1_data
	AND #$CF
	STA cvb_NINK
	CMP cvb_TKL
	BNE nes_choose_new
	LDA cvb_NAI
	BEQ nes_choose_wait
	DEC cvb_NAI
	BNE nes_choose_wait
nes_choose_new:
	LDA cvb_NINK
	STA cvb_TKL
	LDX #15
	STX cvb_NAI
	CMP #$80
	BEQ nes_choose_done
	CMP #$40
	BEQ nes_choose_done
	CMP #1
	BEQ nes_choose_up
	CMP #2
	BEQ nes_choose_up
	CMP #4
	BEQ nes_choose_down
	CMP #8
	BNE nes_choose_wait
nes_choose_down:
	LDA cvb_SK
	CMP #1
	BEQ nes_choose_wait
	DEC cvb_SK
	JMP nes_choose_redraw
nes_choose_up:
	LDA cvb_SK
	CMP cvb_SUT
	BEQ nes_choose_wait
	INC cvb_SK
nes_choose_redraw:
	JSR nes_choose_draw
	JMP nes_choose_wait
nes_choose_done:
	JMP nes_menu_release
nes_menu_release:
	JSR wait
	LDA joy1_data
	AND #$CF
	BNE nes_menu_release
	RTS
nes_choose_draw:
	LDA cvb_SK
	LDY #48
nes_choose_tens:
	CMP #10
	BCC nes_choose_digits
	SBC #10
	INY
	JMP nes_choose_tens
nes_choose_digits:
	STA cvb_SUD
	TYA
	TAX
	LDA cvb_#SUA
	LDY cvb_#SUA+1
	JSR WRTVRM
	LDA cvb_SUD
	CLC
	ADC #48
	TAX
	LDA cvb_#SUA
	CLC
	ADC #1
	LDY cvb_#SUA+1
	JMP WRTVRM

; Brown suitcase outlines overlay their existing black-filled background tiles.
; OAM 44..51 are unused right halves of retired propeller slots 16..23.
; Called AFTER nes_oam2 during draw_actors; hide_play clears them through that
; existing mirror path. These entries follow the main actor halves; the
; auxiliary Harry stripe remains at 55. Hats and radar entries are untouched.
nes_suitcases:
	LDX #0
	LDY #0
nes_suitcase_loop:
	LDA #$F0
	STA $02B0,X
	STA $02B4,X
	LDA array_COK,Y
	CMP #2
	BNE nes_suitcase_next
	LDA array_FLRY,Y
	SEC
	SBC #17
	STA $02B0,X
	STA $02B4,X
	LDA #93
	STA $02B1,X
	LDA #95
	STA $02B5,X
	LDA #1
	STA $02B2,X
	STA $02B6,X
	LDA array_COC,Y
	ASL A
	ASL A
	ASL A
	STA $02B3,X
	CLC
	ADC #8
	STA $02B7,X
	BCC nes_suitcase_next
	LDA #$F0
	STA $02B4,X
nes_suitcase_next:
	TXA
	CLC
	ADC #8
	TAX
	INY
	CPY #4
	BNE nes_suitcase_loop
	RTS
