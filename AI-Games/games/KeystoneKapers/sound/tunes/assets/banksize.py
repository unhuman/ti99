#!/usr/bin/env python3
"""Report how much of the TI fixed area a build actually uses.

`linkticart` SILENTLY DISCARDS anything past the cap -- the symptom is missing
data at the top of the image, not a build error -- so every build has to be
measured. How to measure it depends on whether the build is banked, and the
obvious measure is wrong for one of the two:

  * UNBANKED, the raw -b image is exactly the program: it starts at >6000 and
    the program at >A000, so the used size is the file length minus 16384.
  * BANKED, the assembler PADS the whole >A000..>FFFF window to 24,576 bytes
    with >FF and puts a two-byte bank trailer at >FFFE. Length minus 16384 is
    therefore 24,576 for every banked build, over the 24,336 cap, whatever the
    program actually contains -- which reads as a 240-byte overflow on a build
    with four kilobytes to spare.

So for a banked image this walks back from the trailer over the >FF fill and
reports the last byte that is really content. Undercounting by a few bytes is
possible if a data table genuinely ends in >FF, and it does not matter: the
FAILURE test is not the count, it is whether any content at all lands at or
past the cap, which is exactly the condition linkticart truncates on.

Run:  python3 banksize.py <image> <cap>     exits non-zero if it overflows
"""

import os
import sys

WINDOW = 0xA000          # where the RAM-resident program starts
RAWBASE = 0x6000         # where the raw -b image starts
TRAILER = 2              # the >FFFE bank-switch word


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: banksize.py <image> <cap>")
    path, cap = sys.argv[1], int(sys.argv[2])
    data = open(path, "rb").read()
    off = WINDOW - RAWBASE
    if len(data) <= off:
        sys.exit("banksize: %s is only %d bytes, shorter than the >A000 window"
                 % (path, len(data)))
    win = data[off:]
    banked = os.path.basename(path).endswith("_b0.bin")

    if not banked:
        used = len(data) - off
    else:
        body = win[:-TRAILER] if len(win) > TRAILER else win
        used = len(body)
        while used > 0 and body[used - 1] == 0xFF:
            used -= 1

    if used > cap:
        print("FAIL: %d bytes of fixed area used, %d OVER the %d-byte cap -- "
              "linkticart has silently discarded the top of it"
              % (used, used - cap, cap))
        return 1
    print("Fixed area:  %d / %d bytes   (%d free)%s"
          % (used, cap, cap - used, "   [banked]" if banked else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
