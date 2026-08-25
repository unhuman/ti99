#!/usr/bin/env python3
"""Measure the arcade Joust playfield from a reference screenshot.

The layout was NOT eyeballed and must not be. This downloads a real arcade
screenshot, classifies every pixel as rock / lava / other by colour, and prints
both an ASCII map and the platform spans -- scaled from Williams' native 292x240
to our 256x192.

Getting this wrong is not subtle but it IS easy: the first hand-written table put
the floor gap in the MIDDLE, when in the arcade the floor is FULL WIDTH for waves
1-2 and the lava is exposed at the LEFT AND RIGHT EDGES when the end sections burn
away at wave 3. A player fell straight through the middle of the world.

The screenshot is fetched on demand rather than committed -- it is someone else's
copyrighted image, and the measurement, not the picture, is what this repo needs.

Run:  python3 refmap.py            print the map and the measured spans
"""

import os
import subprocess
import sys

URL = ("https://pixelatedarcade.s3.us-east-005.dream.io/screenshots/109/1788/"
       "screenshot_187-joust-prepare-to-joust-buzzard-bait.png")
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_ref.png")

NATIVE_W, NATIVE_H = 292, 240
OUR_W, OUR_H = 256, 192

ROCK = {(81, 38, 0), (137, 81, 0), (174, 118, 95)}
LAVA = {(255, 118, 0)}


def fetch():
    if os.path.isfile(CACHE):
        return
    subprocess.check_call(["curl", "-sL", "-o", CACHE, URL])


def main():
    try:
        from PIL import Image
    except ImportError:
        sys.stderr.write("needs Pillow\n")
        return 2
    fetch()
    im = Image.open(CACHE).convert("RGB")
    W, H = im.size
    sx, sy = W // NATIVE_W, H // NATIVE_H       # the shot is an integer upscale
    px = im.load()

    def cell(nx, ny):
        rock = lava = 0
        for dy in range(sy):
            for dx in range(sx):
                c = px[min(nx * sx + dx, W - 1), min(ny * sy + dy, H - 1)]
                if c in ROCK:
                    rock += 1
                elif c in LAVA:
                    lava += 1
        return rock, lava

    print("=== arcade playfield, 1 char per 2 native px ===")
    solid = []
    for ny in range(0, NATIVE_H, 2):
        row = ""
        run = []
        for nx in range(0, NATIVE_W, 2):
            r, l = cell(nx, ny)
            r2, l2 = cell(min(nx + 1, NATIVE_W - 1), ny)
            hit = (r + r2) >= 3
            row += "#" if hit else ("~" if (l + l2) >= 2 else ".")
            run.append(hit)
        if "#" in row:
            print("%3d %s" % (ny, row))
        solid.append((ny, run))

    # Rows where a lot of the width is rock are SURFACES; report their spans.
    print()
    print("=== candidate surfaces (>= 8 native px of rock), scaled to %dx%d ==="
          % (OUR_W, OUR_H))
    prev = None
    for ny, run in solid:
        spans, s = [], None
        for i, hit in enumerate(run + [False]):
            if hit and s is None:
                s = i
            elif not hit and s is not None:
                if (i - s) >= 4:
                    spans.append((s * 2, i * 2 - 1))
                s = None
        if spans and spans != prev:
            out = []
            for a, b in spans:
                out.append("%d-%d" % (a * OUR_W // NATIVE_W, b * OUR_W // NATIVE_W))
            print("  y%3d (ours y%3d):  %s"
                  % (ny, ny * OUR_H // NATIVE_H, "  ".join(out)))
            prev = spans
    return 0


if __name__ == "__main__":
    sys.exit(main())
