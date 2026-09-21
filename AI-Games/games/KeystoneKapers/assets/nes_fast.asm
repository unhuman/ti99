; Full redraw transaction. Runtime mode bit 7 is reserved by this local shim;
; bit 2 remains the compiler's sprite-flicker setting. No new RAM is allocated.
; NMI keeps controllers/frame alive but must not touch PPU during direct writes.
nes_fast_begin:
 BIT mode
 BMI nes_fast_return
 JSR wait
 LDA mode
 ORA #$80
 STA mode
 LDA #0
 STA PPUMASK
 LDA #$3F
 STA PPUADDR
 LDA #0
 STA PPUADDR
 LDA #$0F
 STA PPUDATA
 JMP nes_fast_park
nes_fast_return:
 RTS

nes_fast_end:
 ; Return to queued updates. NMI restores the grey palette and rendering
 ; together on the next vblank, never exposing a partly built screen.
 LDA mode
 AND #$7F
 STA mode
 LDA #0
 LDY #$3F
 LDX #$10
 JSR WRTVRM
 JMP wait

nes_fast_poke:
 ; WRTVRM input: A/Y address, X value. Keep backdrop black until commit.
 STY PPUADDR
 STA PPUADDR
 CPY #$3F
 BNE nes_fast_store
 CMP #0
 BNE nes_fast_store
 LDX #$0F
nes_fast_store:
 TXA
 STA PPUDATA
nes_fast_park:
 ; A palette-space PPU address can colour the entire forced-blank display.
 LDA #0
 STA PPUADDR
 STA PPUADDR
 RTS

nes_fast_copy:
 TYA
 PHA
 LDA pointer+1
 STA PPUADDR
 LDA pointer
 STA PPUADDR
 LDY #0
nes_fast_bytes:
 LDA (temp),Y
 STA PPUDATA
 INY
 CPY temp2
 BNE nes_fast_bytes
 PLA
 TAY
 JMP nes_fast_park

; Radar initialization: shadow plus CHR, three pages while forced blank.
nes_scan_clear:
 LDA #array_NSC%256
 STA temp
 LDA #array_NSC/256
 STA temp+1
 LDA cvb_#NSB
 STA pointer
 LDA cvb_#NSB+1
 STA pointer+1
 LDA #0
 STA temp2
 LDA #3
 STA temp2+1
nes_scan_page:
 LDY #0
nes_scan_fill:
 TYA
 AND #8
 BEQ nes_scan_green
 LDA #0
 BEQ nes_scan_byte
nes_scan_green:
 LDA #255
nes_scan_byte:
 STA (temp),Y
 INY
 BNE nes_scan_fill
 JSR LDIRVM
 INC temp+1
 INC pointer+1
 DEC temp2+1
 BNE nes_scan_page
 RTS
