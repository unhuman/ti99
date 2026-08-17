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
# EVERY BUBBLE IS ONE COLOUR, DITHERED. A two-tone ball is identified by a PAIR
# of colours, and this palette does not have eight well-separated pairs -- red
# (medium red / light red) and "orange" (dark red / light red) shared a cap and
# differed only in body shade, which made them the same ball in play: four
# touching "reds" that would not pop, because two of them were the other colour.
# One hue per ball removes the whole failure mode -- there is nothing to confuse
# but the hue itself -- and dithering supplies the shading that the second colour
# used to. The eight are one per HUE FAMILY the TMS9918 offers, in their
# brightest variant, because dithering darkens.
# style: 0 = solid two-tone, 1 = LIGHT dither, 2 = NORMAL, 3 = HEAVY.
# Dither density IS apparent brightness -- more pixels lit reads brighter -- so it
# is the knob that separates two colours the palette puts close together. White
# and grey are only 51 levels apart per channel (255 vs 204) and at the same
# density they read as the same ball; running white LIGHT and grey HEAVY pulls
# them apart far more than their hues ever could.
BUBBLE = [
    (9, 9, 5, 2),   # 1 red
    (3, 3, 5, 2),   # 2 green
    (5, 5, 5, 2),   # 3 blue
    (11, 11, 5, 2), # 4 yellow
    (7, 7, 5, 2),   # 5 cyan
    (13, 13, 5, 2), # 6 magenta
    (14, 14, 5, 3), # 7 grey    heavy dither -> reads darkest
    (15, 15, 5, 1), # 8 white   light dither -> reads brightest
]

# Per style: list of (up_to_row, modulus). A pixel at (x,y) is kept when
# (x + y) % modulus == 0, so modulus 1 is solid, 2 is half, 4 a quarter.
DITHER = {
    1: [(11, 1), (16, 2)],              # light:  solid to row 10, then half
    2: [(5, 1), (9, 2), (16, 4)],       # normal: solid, half, quarter
    3: [(3, 1), (7, 4), (16, 8)],       # heavy:  solid, quarter, eighth
}
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
    ramp = DITHER[style]
    d = [[False] * 16 for _ in range(16)]
    for y in range(16):
        mod = next(m2 for (upto, m2) in ramp if y < upto)
        for x in range(16):
            if not m[y][x]:
                continue
            # The outline is ALWAYS solid, whatever the density -- it is what
            # keeps a sparse ball reading as a circle instead of a cloud.
            d[y][x] = out[y][x] or ((x + y) % mod) == 0
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

    # --- bubbles with the death line running THROUGH them ----------------------------
    # A bubble sitting on the death-line row hides the line behind it, and once the
    # stack is deep that is most of the line -- so the flash the player is supposed to
    # read is exactly the part covered up.
    #
    # These 32 characters (186-217) are the same bubbles carrying the line themselves.
    # The trick is that the VDP colours a character PER SCAN LINE: the dash lives on
    # scan lines 3-4, so the variant clears scan lines 2 and 5 to black (the 1px
    # spacers) and lets 3-4 keep the ball's own silhouette, while the colour table
    # paints just those two lines in the line colour and leaves the rest the bubble's.
    # The line therefore spans the ball's full width at that height, and flashing it
    # is one DEFINE COLOR -- no second set of patterns.
    #
    # Four per colour, because a bubble straddling the line has either its TOP pair or
    # its BOTTOM pair on that row, depending on the ceiling's parity.
    LINE_Y = 11 * 16 + WELLBG      # light yellow  -- must match dash_col in BUSTABOB.bas
    LINE_R = 9 * 16 + WELLBG       # light red     -- must match dash_colf

    # The death-line dash itself: $3C on its two scan lines, i.e. 4 lit pixels of 8,
    # centred in the character. MUST match wall_pat's second character in
    # BUSTABOB.bas -- the line inside the bubbles and the line between them are one
    # line, and they only read as one if they share the dash.
    DASH_BITS = 0x3C

    def crossed(b8, solid8):
        """One quadrant with the line cut through it.

        Scan lines 3-4 carry the DASH PATTERN, not the ball's own pixels and not a
        solid bar. Two earlier tries were wrong: the ball's dithered pixels made
        grey's line a row of stray dots (only every eighth pixel is lit at that
        density), and a solid bar read as a different line from the dashed one
        either side of the bubble. Using the dash keeps one continuous dashed line
        across the whole well.

        The dash lands in phase for free, because bubbles are character-aligned --
        the load-bearing decision in section 2. The dash is per character and the
        bubble occupies whole characters, so its dashes cannot drift against the
        ones outside it.

        `solid8` bounds it to the ball: at these scan lines the sphere spans the
        character anyway, so the mask is a no-op today, but it keeps the line from
        poking outside the bubble if INSET is ever retuned.
        """
        v = list(b8)
        v[2] = 0                   # 1px black spacer above the line
        v[5] = 0                   # and below it
        v[3] = DASH_BITS & solid8[3]
        v[4] = DASH_BITS & solid8[4]
        return v

    w("\t' Bubbles WITH the death line through them, chars 186-217 (4 per colour).")
    w("\t' Scan lines 2 and 5 are cleared to black -- the spacers; 3-4 keep the ball's")
    w("\t' silhouette and are recoloured by bub_colx/bub_colxf.")
    w("bub_patx:")
    for k, (base, lit, lrows, style) in enumerate(BUBBLE):
        rows = mask_bytes(bubble_mask(style))
        BL = [r[0] for r in rows]
        BR = [r[1] for r in rows]
        w("\t' colour %d" % (k + 1))
        w("\tDATA BYTE %s\t' TL" % hexrow(crossed(BL[0:8], L[0:8])))
        w("\tDATA BYTE %s\t' TR" % hexrow(crossed(BR[0:8], R[0:8])))
        w("\tDATA BYTE %s\t' BL" % hexrow(crossed(BL[8:16], L[8:16])))
        w("\tDATA BYTE %s\t' BR" % hexrow(crossed(BR[8:16], R[8:16])))
    w("")

    for lab, linec, what in (("bub_colx", LINE_Y, "at rest: yellow line"),
                             ("bub_colxf", LINE_R, "death flash: red line")):
        w("\t' %s -- scan lines 3-4 are the line, the rest is the bubble." % what)
        w("%s:" % lab)
        for k, (base, lit, lrows, style) in enumerate(BUBBLE):
            b = base * 16 + WELLBG
            t = lit * 16 + WELLBG
            if style:
                top = bot = [t] * 8
            else:
                top = [t if y < lrows else b for y in range(8)]
                bot = [t if (y + 8) < lrows else b for y in range(8)]
            top = [linec if y in (3, 4) else v for y, v in enumerate(top)]
            bot = [linec if y in (3, 4) else v for y, v in enumerate(bot)]
            w("\t' colour %d" % (k + 1))
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

    # --- the creature: 8x8 HUD life icon, and its 2x walking twin for the title ---------
    # ONE shape, two sizes. The 16x16 is the 8x8 with every pixel doubled -- not a
    # redrawn bigger creature -- so the guy walking on the title screen and the guy
    # counting your spare lives cannot drift apart. (Repo rule: scale art, never
    # redesign it at a new size.)
    #
    # Frame A is the life icon exactly; frame B differs only in the last two rows,
    # legs together instead of apart. Two frames is all a walk cycle needs at this
    # size, and keeping the body identical means only the legs read as moving.
    CREATURE_A = [0x3C, 0x7E, 0xDB, 0xFF, 0xFF, 0x7E, 0x66, 0xE7]   # legs apart
    CREATURE_B = [0x3C, 0x7E, 0xDB, 0xFF, 0xFF, 0x7E, 0x18, 0x3C]   # legs together

    def dbl(row8):
        """One 8-pixel row -> 16 pixels, each doubled. Returns (left, right)."""
        v = 0
        for i in range(8):
            if row8 & (0x80 >> i):
                v |= 3 << (14 - 2 * i)
        return (v >> 8) & 0xFF, v & 0xFF

    w("\t' The spare-life creature, 8x8. Eyes are UNLIT pixels -- a character is one")
    w("\t' colour per scan line, so holes are how you draw a face at this size.")
    w("life_pat:")
    w("\tDATA BYTE %s" % hexrow(CREATURE_A))
    w("life_col:")
    w("\tDATA BYTE %s" % hexrow([3 * 16 + WELLBG] * 8))
    w("")
    w("\t' The same creature at 2x as a 16x16 SPRITE, two walk frames, for the title")
    w("\t' screen. 16 bytes left column then 16 bytes right column -- NOT scan lines.")
    w("spr_walk:")
    for name, src in (("A  legs apart", CREATURE_A), ("B  legs together", CREATURE_B)):
        rows = [dbl(r) for r in src]
        left, right = [], []
        for (l, r) in rows:
            left += [l, l]                  # each source row is two pixel rows
            right += [r, r]
        w("\t' frame %s" % name)
        w("\tDATA BYTE %s" % hexrow(left))
        w("\tDATA BYTE %s" % hexrow(right))
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
