#!/usr/bin/env python3
"""Trim CVBasic's TI-99 vblank interrupt for JOUST, on the generated assembly.

The stock handler copies all 128 bytes of the sprite mirror to the VDP and
scans the whole keyboard EVERY frame. Measured in the headless profiler that is
~18,500 cycles a frame -- 37% of the TMS9900 -- in a game that uses 15 sprites
and reads no keys during play. This rewrites two spots of the handler:

  * sprite copy (the SPRITE FLICKER rotating one): only when the game says so
    (`sprok`: 0 hold, 1 copy once, 2 copy every frame). Holding the copy
    until a pass has finished drawing means the screen never shows half of
    one update and half of the next, and the flicker rotates once per pass.
  * keyboard scan: only while `kbscan` is non-zero (title and 838 screens).

Joystick, fire and FCTN-= handling are untouched. Usage: isrpatch.py in.a99 out.a99
"""
import sys

src = open(sys.argv[1]).read()

def swap(old, new):
    global src
    if src.count(old) != 1:
        sys.exit("isrpatch: expected exactly one match for:\n" + old)
    src = src.replace(old, new)

for name in ("cvb_SPROK", "cvb_KBSCAN"):
    if name not in src:
        sys.exit("isrpatch: %s is not defined -- the BASIC must use it" % name)

# Sprite copy, gated on sprok. JOUST runs SPRITE FLICKER ON, so the rotating
# copy (start slot +1 each time, all 32 slots) is the one that runs; the
# straight copy stays stock. Rotating only when a finished pass is published
# keeps one rotation per game frame.
swap("""!4
    movb @flicker,r11   ; here we write it rotated every frame
""", """!4
    movb @cvb_SPROK,r11 ; JOUST: 0 hold, 1 copy once, 2 copy every frame
    jeq !5
    ci r11,>0100
    jne !8
    sb r11,@cvb_SPROK   ; copy-once: published, back to hold
!8
    movb @flicker,r11   ; here we write it rotated every frame
""")

swap("""; key1 - this is a very simple read with no modifiers, it just gives access to the letters and numbers
    clr r11         ; column
""", """; key1 - this is a very simple read with no modifiers, it just gives access to the letters and numbers
    movb @cvb_KBSCAN,r11    ; JOUST: scan only on the title and 838 screens
    jne !kbon
    li r11,>0f00
    movb r11,@key1_data     ; report "no key"
    jmp !key4
!kbon
    clr r11         ; column
""")

open(sys.argv[2], "w").write(src)
