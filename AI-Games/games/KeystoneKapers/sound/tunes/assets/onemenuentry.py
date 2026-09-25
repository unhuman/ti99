#!/usr/bin/env python3
"""Leave exactly ONE entry for this cart in the TI title menu.

WHY THERE WERE FOUR. linkticart.py writes the 80-byte cartridge header at the
start of EVERY 8 KB loader page:

    fo.write(hdr); fo.write(ram[0:8112])
    fo.write(hdr); fo.write(ram[8112:16224])
    fo.write(hdr); fo.write(ram[16224:24336])

and then pads the image up to a power-of-two page count, which copies the
header once more. The console scans each page it can see for the >AA magic at
the top, finds four identical headers, and lists the program four times.

THAT IS NOT MERELY UGLY -- ONLY THE FIRST ONE IS A REAL ENTRY POINT. Pages 1..3
hold the second and third slices of the program image (and padding); their
headers were copied wholesale and point into the middle of data. Selecting one
of them runs from a bogus address, which is why some of the four menu lines did
nothing or hung. A menu offering four things where three are broken is worse
than a menu offering one.

A banked build does not have this problem, which is the whole reason
Bust-A-Bobble lists once and this cart listed four times: with real bank
switching the console only ever sees bank 0 during its power-up scan.

THE FIX is to blank the >AA magic byte at the top of every page after the
first. The console's scan requires >AA and skips any page without it, so only
page 0 is listed. Nothing else reads that byte: the loader on page 0 walks the
later pages as DATA at a fixed 80-byte-per-page offset and never looks for a
signature, so the bytes it consumes are unchanged.

Run:  python3 onemenuentry.py ../src/KEYSTONE_8.bin
"""

import os
import sys

PAGE = 8192
MAGIC = 0xAA


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    data = bytearray(open(path, "rb").read())
    if len(data) < PAGE:
        print("FAIL: %s is only %d bytes -- not a cart image" % (path, len(data)))
        return 1
    if data[0] != MAGIC:
        print("FAIL: page 0 of %s has no >AA header (found >%02X) -- refusing to "
              "touch it, because the one entry we must KEEP is missing"
              % (path, data[0]))
        return 1

    # ONLY clear a page whose first 80 bytes are a byte-for-byte COPY of page
    # 0's header. Testing just the >AA magic would happily zero the first byte
    # of a ROM bank that legitimately starts with >AA -- silent data corruption
    # in exchange for a cosmetic menu fix, which is a terrible trade.
    hdr = bytes(data[0:80])
    cleared = []
    for off in range(PAGE, len(data), PAGE):
        if data[off] == MAGIC and bytes(data[off:off + 80]) == hdr:
            data[off] = 0x00
            cleared.append(off)

    open(path, "wb").write(data)
    print("menu: 1 entry (page 0 kept); cleared decoy headers at %s"
          % (", ".join(str(o) for o in cleared) if cleared else "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
