#!/usr/bin/env python3
"""Post-build TI-99 ROM audit for BUST-A-BOBBLE: fail LOUDLY on silent truncation.

linkticart carries the program image (>A000..>FFFF) in three loader pages of
8112 bytes = 24,336 bytes, and DISCARDS any excess without a word from any tool
in the chain. The symptom is missing DATA at the top of RAM -- not a build
error -- so this has to be measured, every build.

The raw xas99 `-b` image starts at >6000, so the program image begins 16,384
bytes in. A `.bin` bigger than 24,336 is therefore NOT automatically over the
cap; subtract the >6000..>9FFF part first. (Getting that wrong reads as a
5,964-byte overflow on a build with 10 KB free.)

Run:  python3 romcheck.py     Exit code is non-zero if anything overflowed.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src")

FIXED_CAP = 24336           # 3 loader pages x 8112 bytes
RAM_BASE = 0xA000           # where the program image is assembled
CART_BASE = 0x6000          # where the raw xas99 image starts
SKIP = RAM_BASE - CART_BASE  # 16384


def content_len(d):
    i = len(d)
    while i > 0 and d[i - 1] == 0xFF:
        i -= 1
    return i


def main():
    path = os.path.join(SRC, "BUSTABOB.bin")
    if not os.path.isfile(path):
        sys.stderr.write("error: %s not found -- run build-ti.sh first\n" % path)
        return 2

    raw = open(path, "rb").read()
    if len(raw) <= SKIP:
        print("image is entirely below >A000 (%d bytes) -- nothing to check" % len(raw))
        return 0

    image = raw[SKIP:]
    used = content_len(image)
    free = FIXED_CAP - used

    print("BUST-A-BOBBLE -- TI-99/4A fixed area (all code + data read during a frame)")
    print("  raw image   %6d B   (starts at >%04X)" % (len(raw), CART_BASE))
    print("  >A000 up    %6d B" % len(image))
    print("  used        %6d B   of %d   (%.1f%%)" % (used, FIXED_CAP,
                                                      100.0 * used / FIXED_CAP))
    print("  free        %6d B" % free)

    if used > FIXED_CAP:
        dropped = image[FIXED_CAP:]
        live = sum(1 for b in dropped if b != 0xFF)
        print()
        print("FAIL: %d bytes OVER the cap. linkticart has silently discarded the top"
              % (used - FIXED_CAP))
        print("      of the program image -- whatever the assembler put nearest >FFFF,")
        print("      usually the last DATA block. %d non-padding bytes are in the" % live)
        print("      discarded region. Move data into BANKs (levels + music together).")
        return 1

    print()
    print("OK -- nothing truncated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
