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
;   nes_chrup   upload patterns, rendering off   (DEFINE CHAR / DEFINE SPRITE)
;   nes_chrq    upload patterns through the NMI queue, for the escalator
;   nes_oam2    the right-hand half of every 16x16 actor
;   nes_bgbank  put background patterns at $1000 so sprites can have $0000
;   nes_apuon   enable the APU, once, whatever the game plays
;
; ---------------------------------------------------------------------------
; COLOUR, AND WHY IT COMES OUT OF THE GAME'S OWN COLOUR TABLE
;
; A TMS9918 cell in this mode is one bit per pixel with a foreground and a
; background colour PER CHARACTER PER SCAN LINE -- which is why DEFINE COLOR
; wants eight bytes a character. The NES has no such thing: a tile is TWO
; bitplanes giving four colour indices, and which four colours those are is
; chosen by the attribute table in 16x16-pixel BLOCKS. Walls, pillars and floor
; bars sit next to each other inside a single block all over this store, so the
; attribute table cannot separate them and there is no point pretending.
;
; The second BITPLANE can, though. Writing the art into both planes with a
; per-character pair of indices gives every character its own ink and its own
; paper out of one palette of three colours plus the backdrop -- which is
; exactly the shape of the data DEFINE COLOR was already being handed. So the
; uploader reads store_col and maps each TMS colour to one of four indices:
;
;   0  the backdrop               <- TMS 0 transparent, 1 black, 7 cyan
;   1  the region's base          <- TMS 2 3 12 greens, 4 5 blues, 8 9 reds, 13
;   2  structure                  <- TMS 6 dark red, 14 grey
;   3  the region's light         <- TMS 10 11 yellows, 15 white
;
; An index is a ROLE, not a colour: the attribute table gives the store, the HUD
; and the two halves of the sky their own palette, so the same character comes
; out green-on-gold in the shop and blue-on-grey in the sky. See nes_attr.
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

	; TMS COLOUR -> ONE OF THE FOUR INDICES, BY ROLE RATHER THAN BY HUE.
	;
	; There are four background palettes now (see nes_attr in KEYSTONE.bas),
	; and a character's bitplanes fix its INDICES while the attribute table
	; picks which palette those indices come out of. So an index has to mean
	; the same THING everywhere, not the same colour:
	;
	;   0  the backdrop, black
	;   1  THE REGION'S BASE   -- store green, HUD blue, sky blue
	;   2  STRUCTURE           -- grey, in every region
	;   3  HIGHLIGHT           -- store white, sky warm
	;
	; That is what lets one encoding of one character be recoloured per
	; region for free. The store's own mapping is UNCHANGED by this table --
	; DGREEN 1, GRAY 2, WHITE 3, BLACK 0 are exactly what they were -- so the
	; shop looks as it did and only the HUD and the roof band move.
	;
	; The blues left index 2 and the warm colours gathered on 3, which is what
	; turns the sunset from one flat shade into blue over orange behind grey
	; buildings.
	; CYAN GOES TO THE BACKDROP, NOT TO GREY, AND THAT IS WHAT MAKES THE LIFT
	; DOORS AND THE SHELVES VISIBLE AGAIN. Three store characters have an
	; EMPTY pattern (CH_EDOOR, CH_ECAR, CH_ECART are 0 of 64 pixels), so each
	; renders as a flat block of its PAPER: grey for the door, cyan for the
	; car. With cyan mapped to grey those were the same colour and the doors
	; could not be seen at all. The same collision hid the shelves --
	; CH_SHELFT is a SOLID 64/64 block of cyan and CH_COUNTR a solid block of
	; grey, so the shelf and the counter it stands on were one grey mass.
	; Sending cyan to index 0 costs nothing (the backdrop is already there)
	; and separates both pairs at once.
	;
	; WHITE STAYS ON INDEX 3, WHICH IS NOW GOLD, AND THAT IS A REAL LOSS RATHER
	; THAN AN OVERSIGHT. The store band has three inks and the picture wants
	; four: green, structure, gold and white. Gold has to win it -- the money
	; bags and the floor bars are both YELLOW on the TI and both land here, so
	; a white index 3 turned the prizes into pale blobs and the bars into thin
	; grey lines, which is what was reported.
	;
	; Moving white to index 2 to free index 3 does not work, and checkink.py
	; says so: CH_EDOOR and CH_EDOORS are WHITE ink on GREY paper, so they
	; collapse into a featureless block the moment the two share an index. The
	; lift doors would go invisible to make the radio's dots white -- trading
	; one of the reported faults for another. So the radio's dots come out gold
	; on its black body instead of white: visible and legible, and the only
	; way to have them truly white is a fourth ink, which needs the attribute
	; table to split the store band the way it already splits the sky.
	; DARK RED GOES TO STRUCTURE, NOT TO GOLD, SO THE BRIEFCASE IS NOT A SECOND
	; MONEY BAG. The two prizes are drawn in different colours on the TI --
	; the bag light yellow, the case dark red -- and both were landing on the
	; light index, so making that index gold made the case gold too. Grey is
	; the only one of the three inks left that is not the bag's and not the
	; air's; a dark-red case cannot be had without a fourth.
	; THE DISPLAY COUNTERS ARE TWO CHARACTERS AND THEY WERE FAILING IN OPPOSITE
	; DIRECTIONS. The counter FACE (char 100) is light blue on light blue, and
	; light blue sat on index 1 -- the air's green -- so the body dissolved
	; into the floor behind it. Its TOP (CH_SHELFT) is a SOLID 64/64 block of
	; cyan, and cyan sat on the backdrop, so the top was a black line with
	; nothing under it: "just black floating lines".
	;
	; On the TI the unit is a light-blue body under a cyan lip, the blue
	; deliberately lighter than the Kop's uniform. THAT CANNOT BE REPRODUCED
	; HERE and it is worth saying why rather than quietly approximating: the
	; store band has three inks plus the backdrop, and green (air), grey
	; (structure) and gold (bars and prizes) are all load-bearing. Blue and
	; cyan would be a fourth and a fifth. The attribute table is the only way
	; to buy more, and it cannot help HERE -- a counter shares its 16x16 block
	; with the wall behind it, and the bands are five rows apart while the
	; blocks are two, so the counter rows land on a block boundary on only two
	; floors out of four.
	;
	; LIGHT BLUE BELONGS TO THE SKY, NOT TO THE COUNTERS. Sending it to
	; structure grey made the counter face visible and put a GREY STRIPE
	; ACROSS THE SUNSET, because SKYGRAD's first row is four scan lines of
	; dark blue over four of LIGHT blue and BLDG_BODY is GRAY -- so the sky's
	; second band came out the same colour as the buildings standing in it.
	; One TMS colour cannot be two things through one global map.
	;
	; The counters get their own upload instead (setup_rest re-sends chars 99
	; and 100 with #ncol = 0 and an explicit nink), which is exactly what that
	; path is for: both are SOLID patterns, so an ink alone decides them and
	; no colour table is consulted. That leaves light blue free to be sky.
	;
	; The lip is still not cyan, and cyan has no index open to it:
	;
	;   grey  -- CH_EDOOR and CH_ECAR both have EMPTY patterns and render as
	;            flat paper, grey and cyan; share an index and the lift doors
	;            disappear into the car
	;   light -- CH_ECAR and CH_ECARS are WHITE ink on CYAN paper, so they
	;            collapse to a featureless block (checkink.py rejects it)
	;   base  -- the lip is a horizontal line against the air; green puts it
	;            back where it started, invisible
	;
	; which leaves the backdrop. Verified by the gate, not by eye.
	; THE SUNSET IS TWO BANDS AND CANNOT BE MORE, AND THIS WAS TRIED. SKYGRAD
	; is six colours; five of them land on index 1, so the gradient is really
	; one base colour per sky palette -- blue above, orange below -- plus the
	; lit windows. Index 2 belongs to the buildings and index 3 to the windows,
	; so the only free entry a sky row could spend is the BACKDROP.
	;
	; Sending DARK BLUE there does buy a fourth band, and it is faithful: the
	; TI's HUD_BG and SKYGRAD's first band are the same dark blue, which is how
	; the score line avoids ending on a hard edge. IT IS STILL NOT WORTH IT.
	; The backdrop is global and everything drawn in black rides on it, so the
	; escalator, the radar ground and every outline in the store turned dark
	; blue with it -- one more sky band bought with the store's whole line
	; work. Measured on screen, not reasoned about; do not re-try it without
	; looking at the escalator.
nes_inkmap:
	;              0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15
	DB 0,0,1,1,1,1,2,0,1,1,3,3,1,1,2,3

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
; Slots 0-27 are the game's; 28-55 are their right halves; 56-63 stay parked at
; y=$F0 by the prologue's clear_sprites. Hidden sprites copy across as hidden,
; so nothing has to know which slots are live.
; ---------------------------------------------------------------------------
NES_OAM_PAIRS:	EQU 28
NES_OAM_STEP:	EQU NES_OAM_PAIRS*4

nes_oam2:
	LDX #0
nes_oam2_loop:
	LDA $0200,X			; y -- same row
	STA $0200+NES_OAM_STEP,X
	INX
	LDA $0200,X			; tile -- two on is the right-hand column
	CLC
	ADC #2
	STA $0200+NES_OAM_STEP,X
	INX
	LDA $0200,X			; colour -- see nes_spal
	AND #$0F
	TAY
	LDA nes_spal,Y
	STA $0200,X			; and back into the left half as well
	STA $0200+NES_OAM_STEP,X
	INX
	LDA $0200,X			; x -- eight pixels right
	CLC
	ADC #8
	STA $0200+NES_OAM_STEP,X
	INX
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
nes_spal:
	DB 0,1,3,3,0,0,2,0,2,2,2,2,3,2,3,3

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
; assets/nes_apu.asm writes $4015 inside sn76489_vol, so nothing sounds until
; the first volume is set and anything that sets a pitch before its volume is
; writing into a disabled channel. The frame counter at $4017 also matters: the
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
