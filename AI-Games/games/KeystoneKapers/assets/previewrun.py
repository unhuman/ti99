#!/usr/bin/env python3
"""Render the run cycle as a strip -- the only way to judge a walk cycle.

Draws the whole figure the way the VDP will: each band as its own sprite, at
its own y offset, in its own colour, for every frame of the cycle and both
facings.

Run:  python3 previewrun.py [out.png]
"""
import os
import sys

import genart as g

HERE = os.path.dirname(os.path.abspath(__file__))
PAL = [(0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
       (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
       (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
       (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255)]
BG = (33, 200, 66)          # the store's green

C_KELLY, C_SKIN, C_HARRY, C_STRIPE = 4, 11, 15, 1
C_HAT = 1        # the game draws Kelly's hat BLACK, in its own sprite


def rows(art):
    return [r for r in art.strip("\n").split("\n")]


def paint(px, art, ox, oy, colour):
    for y, line in enumerate(rows(art)):
        for x, ch in enumerate(line):
            if ch == "#":
                px[oy + y][ox + x] = PAL[colour]


def figure(bands, w=16, h=44):
    """bands = [(art, y offset, colour)] -- offsets are the game's SPRITE ys."""
    px = [[BG] * w for _ in range(h)]
    for art, dy, col in bands:
        paint(px, art, 0, 13 + dy, col)
    return px


def kelly(leg, swing, left):
    top = g.KELLY_TOP_B if swing else g.KELLY_TOP
    hat = g.shift(g.band(top, g.HAT), 10)
    face = g.shift(g.band(top, g.FACE), 5)
    body = g.shift(g.band(top, g.TORSO), -11)
    parts = [(hat, -10, C_HAT), (face, -5, C_SKIN),
             (body, 11, C_KELLY), (leg, 16, C_KELLY)]
    if left:
        parts = [(g.mirror(a), d, c) for a, d, c in parts]
    return figure(parts)


def duck(left):
    """The crouch: two bands, hat+body blue and the face skin, at FLOORY-8."""
    parts = [(g.KELLY_DBODY, 13, C_KELLY), (g.KELLY_DHAT, 13, C_HAT),
             (g.KELLY_DFACE, 13, C_SKIN)]
    if left:
        parts = [(g.mirror(a), d, c) for a, d, c in parts]
    return figure(parts)


def harry(leg, legs, body, stripe, left):
    """FIVE sprites, at the game's own y offsets. Keep these in step with
    draw_actors -- this preview drifted out of date and then blamed the art.

    It had the face at +4 when the game moved it to -7 (the box was lifted so
    it stops reaching down through the torso rows), and it never drew the leg
    stripes at all. The result was a Harry with his head in his chest and no
    shoes, which reads as broken ART -- and the art was fine. A preview that
    lags the thing it previews is worse than no preview: it does not just fail
    to help, it actively accuses the wrong file.

        body     +0    stripe   +0    face  -7
        legs    +16    legs stripe  +16

    ALL FIVE BANDS MIRROR, legs included -- draw_actors adds P_HFACING to the
    torso, stripes and face and P_HLEGFACING to the two leg sprites. The legs
    used to be shared between the facings and this preview is what showed why
    they cannot be: with the sheet's full-width stride, an unmirrored left run
    puts his back foot in front of him.
    """
    parts = [(body, 0, C_HARRY), (stripe, 0, C_STRIPE),
             (g.HARRY_FACE, -7, C_SKIN),
             (leg, 16, C_HARRY), (legs, 16, C_STRIPE)]
    if left:
        parts = [(g.mirror(a), d, c) for a, d, c in parts]
    return figure(parts)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "run.png")
    A, B = g.KELLY_LEG1, g.KELLY_LEG2
    # HARRY'S FOUR BEATS, exactly as the game clocks them. Every band now steps
    # on the SAME two bits of hanim, so beat n is leg n with body n -- no
    # second clock. (It used to be four legs against two alternating torsos,
    # which is what made him look like he was flapping rather than running.)
    HFRAMES = [(g.HARRY_LEG1, g.HARRY_LEG1S, g.HARRY_BODY, g.HARRY_STRIPE),
               (g.HARRY_LEG2, g.HARRY_LEG2S, g.HARRY_BODY2, g.HARRY_STRIPE2),
               (g.HARRY_LEG3, g.HARRY_LEG3S, g.HARRY_BODY3, g.HARRY_STRIPE3),
               (g.HARRY_LEG4, g.HARRY_LEG4S, g.HARRY_BODY4, g.HARRY_STRIPE4)]
    # the cycle the game plays: A, B, mirror(A), mirror(B)
    kr = [kelly(A, True, False), kelly(B, False, False),
          kelly(g.mirror(A), True, False), kelly(g.mirror(B), False, False)]
    kl = [kelly(g.mirror(A), True, True), kelly(g.mirror(B), False, True),
          kelly(A, True, True), kelly(B, False, True)]
    hr = [harry(l, ls, b, st, False) for l, ls, b, st in HFRAMES]
    hl = [harry(l, ls, b, st, True) for l, ls, b, st in HFRAMES]

    # the crouch, both ways, beside a standing frame for scale
    dk = [duck(False), kelly(A, True, False), duck(True), kelly(A, True, True)]
    rowsets = [kr, kl, hr, hl, dk]
    W, H = 16, 40
    try:
        from PIL import Image
    except ImportError:
        sys.exit("previewrun needs PIL")
    im = Image.new("RGB", ((W + 2) * 4, (H + 2) * 5), (255, 0, 255))
    for r, rs in enumerate(rowsets):
        for c, fr in enumerate(rs):
            for y in range(H):
                for x in range(W):
                    im.putpixel((c * (W + 2) + x, r * (H + 2) + y), fr[y][x])
    im.resize((im.width * 12, im.height * 12), Image.NEAREST).save(out)
    print("wrote %s -- rows: Kelly right, Kelly left, Harry right, Harry "
          "left, then the crouch (right, standing, left, standing)"
          % os.path.normpath(out))


if __name__ == "__main__":
    main()
