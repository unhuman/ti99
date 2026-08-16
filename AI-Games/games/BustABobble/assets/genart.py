#!/usr/bin/env python3
"""
BUST-A-BOBBLE - generates src/art.bas: bubble patterns, colours, sprite defs,
the aim table, and the drop-score BCD table.

Everything here is derived, not hand-typed, so the numbers in the ROM and the
numbers in assets/prevlevels.py cannot drift apart.

Run:  python3 genart.py
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "src", "art.bas")

# --- the 16x16 bubble ------------------------------------------------------------------
# Per-pixel-row inset from each side. Rows 0..5 take the LIT shade, 6..15 the BASE shade,
# so every character scan line is one bubble shade on black -- never three colours.
# Same table as prevlevels.py: change both together.
INSET = [4, 3, 2, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 2, 3, 4]
LITROWS = 6

# bubble colour k (1..8) -> (base, lit, litrows). DESIGN.md section 4.
#
# litrows is how many of the sphere's 16 pixel rows take the LIT shade, i.e. how
# big the highlight is, and it is PER COLOUR because the palette is not
# symmetric -- some colours have a good light/dark pair in hardware and some
# do not.
#
# style 0 = TWO-TONE: solid sphere, lit shade over base shade, split at litrows.
# style 1 = DITHERED: ONE colour throughout, and the shading comes from PIXEL
#           DENSITY instead -- solid at the top, then checks that thin out going
#           down, with the outline always solid so the circle stays crisp. This
#           is the only way to get a gradient out of a two-colours-per-line
#           display, and it means the colour needs its own character pattern
#           rather than sharing the common one.
BUBBLE = [
    (8, 9, 6, 0),   # 1 red      medium red  / light red
    (12, 3, 6, 0),  # 2 green    dark green  / light green
    (4, 5, 6, 0),   # 3 blue     dark blue   / light blue
    (10, 11, 6, 0), # 4 yellow   dark yellow / light yellow
    (7, 7, 5, 1),   # 5 cyan     dithered: solid cyan cap, cyan/black checks below
    (13, 13, 5, 1), # 6 magenta  dithered, same as cyan
    (14, 14, 5, 1), # 7 grey     dithered -- this is what "light and dark grey"
                    #            actually wants: the TMS9918 has ONE grey, but
                    #            solid grey against grey/black checks reads as
                    #            two tones of it. Better than the white glint
                    #            that was standing in for it.
    (6, 9, 6, 0),   # 8 orange   dark red    / light red
]
WELLBG = 1                      # black behind every bubble


def sphere():
    m = [[False] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(INSET[y], 16 - INSET[y]):
            m[y][x] = True
    return m


def bubble_mask(style):
    """The 16x16 pixel mask for one bubble style."""
    m = sphere()
    if style == 0:
        return m
    # Outline: any set pixel with an unset (or off-cell) 4-neighbour. Kept solid
    # so the dithered ball still reads as a circle rather than a cloud.
    out = [[False] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            if not m[y][x]:
                continue
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if not (0 <= ny < 16 and 0 <= nx < 16) or not m[ny][nx]:
                    out[y][x] = True
    d = [[False] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            if not m[y][x]:
                continue
            if out[y][x] or y < 5:
                d[y][x] = True                      # outline, and a solid cap
            elif y < 9:
                d[y][x] = ((x + y) & 1) == 0        # half density
            else:
                d[y][x] = ((x + y) & 3) == 0        # quarter density
    return d


def mask_bytes(m):
    """mask -> (left byte, right byte) per pixel row"""
    rows = []
    for y in range(16):
        left = right = 0
        for x in range(16):
            if not m[y][x]:
                continue
            if x < 8:
                left |= 1 << (7 - x)
            else:
                right |= 1 << (15 - x)
        rows.append((left, right))
    return rows

NAIM = 32                       # aim steps, 0 = straight up .. 31 = 80 degrees
AIMSPD = 5.0                    # pixels per frame
AIMMAX = 80.0                   # degrees from vertical at full deflection
NDROP = 17                      # drop-score table entries (capped at 17, per the arcade)


def rowbits(y):
    """(left byte, right byte) of the sphere at pixel row y."""
    lo, hi = INSET[y], 16 - INSET[y]        # pixels lo..hi-1 are set
    left = right = 0
    for x in range(lo, hi):
        if x < 8:
            left |= 1 << (7 - x)
        else:
            right |= 1 << (15 - x)
    return left, right


def hexrow(vals):
    return ",".join("$%02X" % v for v in vals)


def main():
    L = [rowbits(y)[0] for y in range(16)]
    R = [rowbits(y)[1] for y in range(16)]

    out = []
    w = out.append

    w("\t' BUST-A-BOBBLE art + tables -- GENERATED by assets/genart.py")
    w("\t' Do not edit. Regenerate instead.")
    w("")

    # --- character patterns: one 2x2 stamp, shared by all 8 colours -------------------
    w("\t' The 16x16 bubble as four 8x8 characters (TL,TR,BL,BR), PER COLOUR --")
    w("\t' 32 chars in one DEFINE CHAR. They used to share one pattern, but a")
    w("\t' dithered colour needs its own pixels: on a two-colours-per-line display")
    w("\t' a gradient can only come from pixel density, not from more colours.")
    w("bub_pat:")
    for k, (base, lit, lrows, style) in enumerate(BUBBLE):
        rows = mask_bytes(bubble_mask(style))
        BL = [r[0] for r in rows]
        BR = [r[1] for r in rows]
        w("\t' colour %d%s" % (k + 1, "  DITHERED" if style else ""))
        w("\tDATA BYTE %s\t' TL" % hexrow(BL[0:8]))
        w("\tDATA BYTE %s\t' TR" % hexrow(BR[0:8]))
        w("\tDATA BYTE %s\t' BL" % hexrow(BL[8:16]))
        w("\tDATA BYTE %s\t' BR" % hexrow(BR[8:16]))
    w("")

    # --- burst: three dissolve frames for a popping bubble -----------------------------
    # The sphere breaking up: solid, then holed on a checker, then sparse specks.
    # ONE set shared by all colours (12 chars, not 8 x 12) -- a pop is a bright flash
    # and reads fine without carrying the bubble's own hue.
    w("\t' Pop animation: 3 frames x 4 chars (TL,TR,BL,BR), chars 164-175.")
    w("\t' Shared by every colour: the burst flashes white/yellow/grey rather than")
    w("\t' inheriting the bubble's hue, which would cost 8 times the characters.")
    w("bur_pat:")
    for f in range(3):
        rows = []
        for y in range(16):
            lo, hi = INSET[y], 16 - INSET[y]
            left = right = 0
            for x in range(lo, hi):
                if f == 1 and ((x + y) & 1):
                    continue
                if f == 2 and ((x + y) & 3):
                    continue
                if x < 8:
                    left |= 1 << (7 - x)
                else:
                    right |= 1 << (15 - x)
            rows.append((left, right))
        w("\t' frame %d" % f)
        w("\tDATA BYTE %s\t' TL" % hexrow([rows[y][0] for y in range(8)]))
        w("\tDATA BYTE %s\t' TR" % hexrow([rows[y][1] for y in range(8)]))
        w("\tDATA BYTE %s\t' BL" % hexrow([rows[y][0] for y in range(8, 16)]))
        w("\tDATA BYTE %s\t' BR" % hexrow([rows[y][1] for y in range(8, 16)]))
    w("bur_col:\t' white flash -> yellow -> grey, one colour per frame")
    for c in (15, 11, 14):
        for _ in range(4):
            w("\tDATA BYTE %s" % hexrow([c * 16 + WELLBG] * 8))
    w("")

    # --- character colours: 8 colours x 4 chars x 8 rows ------------------------------
    w("\t' Per-scan-line colours for chars 128..159 (8 colours x TL,TR,BL,BR).")
    w("\t' fg*16+bg; bg is always black. The TOP chars switch from lit to base at")
    w("\t' pixel row %d; the BOTTOM chars are all base." % LITROWS)
    w("bub_col:")
    for k, (base, lit, lrows, style) in enumerate(BUBBLE):
        b = base * 16 + WELLBG
        t = lit * 16 + WELLBG
        if style:
            # Dithered: ONE colour on every line. The shading is in the pixels,
            # so a second colour here would fight it.
            top = bot = [t] * 8
        else:
            top = [t if y < lrows else b for y in range(8)]
            bot = [t if (y + 8) < lrows else b for y in range(8)]
        w("\t' colour %d  base=%-2d lit=%-2d litrows=%d%s"
          % (k + 1, base, lit, lrows, "  DITHERED" if style else ""))
        w("\tDATA BYTE %s\t' TL" % hexrow(top))
        w("\tDATA BYTE %s\t' TR" % hexrow(top))
        w("\tDATA BYTE %s\t' BL" % hexrow(bot))
        w("\tDATA BYTE %s\t' BR" % hexrow(bot))
    w("")

    # --- sprites ----------------------------------------------------------------------
    # CVBasic 16x16 sprite pattern = 16 bytes left column, then 16 bytes right column.
    w("\t' Flying bubble = TWO overlaid 16x16 sprites so it is pixel-identical to the")
    w("\t' same bubble once it sticks and becomes characters (a sprite is one colour).")
    w("\t' 16 bytes left column then 16 bytes right column -- NOT sequential scan lines.")
    w("\t' THREE patterns per colour: 3k = cap, 3k+1 = body, 3k+2 = FULL ball.")
    w("\t' cap/body are per colour because litrows is -- the flying bubble must")
    w("\t' split at the same row its character form does or it stops matching the")
    w("\t' moment it lands. FULL is for falling debris: one sprite instead of two,")
    w("\t' which halves the slots used AND keeps them off each other's scanlines")
    w("\t' (only four sprites show per line). Drawing debris with the body pattern")
    w("\t' alone is what made the falling bubbles look like bottom halves.")
    w("spr_bub:")
    for k, (base, lit, lrows, style) in enumerate(BUBBLE):
        rows = mask_bytes(bubble_mask(style))
        BL = [r[0] for r in rows]
        BR = [r[1] for r in rows]
        w("\t' colour %d cap (rows 0-%d)" % (k + 1, lrows - 1))
        w("\tDATA BYTE %s" % hexrow(BL[:lrows] + [0] * (16 - lrows)))
        w("\tDATA BYTE %s" % hexrow(BR[:lrows] + [0] * (16 - lrows)))
        w("\t' colour %d body (rows %d-15)" % (k + 1, lrows))
        w("\tDATA BYTE %s" % hexrow([0] * lrows + BL[lrows:]))
        w("\tDATA BYTE %s" % hexrow([0] * lrows + BR[lrows:]))
        w("\t' colour %d full" % (k + 1))
        w("\tDATA BYTE %s" % hexrow(BL))
        w("\tDATA BYTE %s" % hexrow(BR))
    # SPRITE colours, emitted from the SAME table the character colours come from.
    # These used to be hand-written as colv()/litv() in the .bas, i.e. a second
    # copy of this data -- and the moment the palette changed here, the flying
    # bubble and the landed bubble disagreed: a shot looked white-and-cyan and
    # became cyan-and-blue when it stuck. One table, no copies.
    w("bub_base:\t' body colour per bubble colour 1..8")
    w("\tDATA BYTE %s" % hexrow([b for (b, l, r, s) in BUBBLE]))
    w("bub_lit:\t' cap colour per bubble colour 1..8")
    w("\tDATA BYTE %s" % hexrow([l for (b, l, r, s) in BUBBLE]))
    w("")

    dotl = [0] * 6 + [0x03] * 4 + [0] * 6
    dotr = [0] * 6 + [0xC0] * 4 + [0] * 6
    w("spr_dot:\t' 4x4 aim-guide dot, centred in the 16x16 cell")
    w("\tDATA BYTE %s" % hexrow(dotl))
    w("\tDATA BYTE %s" % hexrow(dotr))
    w("")

    # --- aim table --------------------------------------------------------------------
    w("\t' Aim table: %d steps from vertical to %g degrees, speed %g px/frame, 8.8 fixed" %
      (NAIM, AIMMAX, AIMSPD))
    w("\t' point. BOTH MAGNITUDES ARE POSITIVE -- direction is a separate flag, because")
    w("\t' CVBasic compiles every #var comparison UNSIGNED (a signed velocity would")
    w("\t' silently misbehave at every sign test).")
    dxs, dys = [], []
    for am in range(NAIM):
        th = math.radians(am * AIMMAX / (NAIM - 1))
        dxs.append(int(round(AIMSPD * math.sin(th) * 256)))
        dys.append(int(round(AIMSPD * math.cos(th) * 256)))
    w("#aimdx:")
    for i in range(0, NAIM, 8):
        w("\tDATA %s" % ",".join(str(v) for v in dxs[i:i + 8]))
    w("#aimdy:")
    for i in range(0, NAIM, 8):
        w("\tDATA %s" % ",".join(str(v) for v in dys[i:i + 8]))
    w("")

    # --- drop-score table -------------------------------------------------------------
    # The i-th dropped bubble is worth 20 * 2^(i-1) points = 2^i UNITS OF 10.
    # Capped at i=17 -> 131072 units = 1,310,720 points, the documented arcade maximum.
    w("\t' Drop score. The i-th dropped bubble is worth 20 * 2^(i-1) POINTS, which is")
    w("\t' exactly 2^i UNITS OF 10. Capped at i=%d -> %d units = %s points," %
      (NDROP, 2 ** NDROP, "{:,}".format(2 ** NDROP * 10)))
    w("\t' the documented arcade maximum for one drop.")
    w("\t' Stored as 6 BCD digits, most significant first, so adding into the score is")
    w("\t' a digit-wise add with carry -- no division, no 32-bit arithmetic, no overflow.")
    w("dropbcd:")
    for i in range(1, NDROP + 1):
        u = 2 ** i
        digs = [int(c) for c in "%06d" % u]
        w("\tDATA BYTE %s\t' %2d bubbles: %6d units = %s pts"
          % (hexrow(digs), i, u, "{:,}".format(u * 10)))
    w("")

    outdir = os.path.dirname(os.path.abspath(OUT))
    if not os.path.isdir(outdir):
        os.makedirs(outdir)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")

    nspr = (len(BUBBLE) * 3 + 1) * 32
    total = 32 + 8 * 4 * 8 + nspr + NAIM * 4 + NDROP * 6
    print("wrote %s" % os.path.normpath(OUT))
    print("  patterns 32 B  colours %d B  sprites %d B  aim %d B  dropbcd %d B  = %d B"
          % (8 * 4 * 8, nspr, NAIM * 4, NDROP * 6, total))
    print("  aim step 0 = (%d,%d)  step 31 = (%d,%d)  [8.8 fixed]"
          % (dxs[0], dys[0], dxs[-1], dys[-1]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
