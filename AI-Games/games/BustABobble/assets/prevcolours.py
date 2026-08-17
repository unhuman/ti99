#!/usr/bin/env python3
"""All eight bubble colours side by side, straight from genart's mask + palette.

The point of this sheet is the pair a level rarely shows together. White and grey
are only 51 levels apart per channel, so whether they read as different balls is
a question about DITHER DENSITY, not hue -- and that is impossible to judge from
a level render where they seldom appear side by side.

Run:  python3 prevcolours.py   ->  colours.png
"""
import os
import sys

from PIL import Image, ImageDraw

import genart
from prevlevels import TMS, SCALE

HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = ["red", "green", "blue", "yellow", "cyan", "magenta", "grey", "white"]
CELL, PAD = 16, 4


def main():
    n = len(genart.BUBBLE)
    img = Image.new("RGB", (n * (CELL + PAD) + PAD, CELL + 2 * PAD), TMS[1])
    px = img.load()
    for k, (base, lit, lrows, style) in enumerate(genart.BUBBLE):
        m = genart.bubble_mask(style)
        x0 = PAD + k * (CELL + PAD)
        for y in range(16):
            for x in range(16):
                if m[y][x]:
                    px[x0 + x, PAD + y] = TMS[lit]

    big = img.resize((img.width * SCALE * 2, img.height * SCALE * 2), Image.NEAREST)
    d = ImageDraw.Draw(big)
    for k, name in enumerate(NAMES):
        style = genart.BUBBLE[k][3]
        lit = sum(1 for y in range(16) for x in range(16)
                  if genart.bubble_mask(style)[y][x])
        d.text(((PAD + k * (CELL + PAD)) * SCALE * 2, 2),
               "%d %s\nsty%d %dpx" % (k + 1, name, style, lit), fill=(255, 255, 255))
    out = os.path.join(HERE, "colours.png")
    big.save(out)
    print("wrote %s" % os.path.basename(out))
    for k, name in enumerate(NAMES):
        style = genart.BUBBLE[k][3]
        m = genart.bubble_mask(style)
        lit = sum(1 for y in range(16) for x in range(16) if m[y][x])
        rgb = TMS[genart.BUBBLE[k][1]]
        # crude apparent brightness: lit fraction x colour luminance
        lum = 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]
        print("  %-8s style %d  %3d px  luma %5.1f  apparent %5.1f"
              % (name, style, lit, lum, lum * lit / 256.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
