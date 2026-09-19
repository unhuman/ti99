#!/usr/bin/env python3
"""No array may run off the end of the NES's internal RAM.

The NES has 2 KB at $0000-$07FF and the address space MIRRORS: $0800 reads and
writes $0000, which is the zero page. So an array that overruns $07FF does not
fault and does not touch unused memory -- it quietly overwrites CVBasic's own
pointers, and the machine dies before it draws anything.

CVBASIC DOES NOT CATCH THIS. It reports a byte count against a notional total
("1567 RAM bytes used of 1838 available") and keeps allocating past the end of
the physical RAM. Adding a 32-byte array to Keystone Kapers pushed the tail of
`nesb` five bytes over, and the only symptom was a BLACK SCREEN AT BOOT -- no
compiler error, no assembler error, no bad exit status, and a ROM of exactly the
right size. It cost a bisection over several build cycles because a black screen
says nothing about which of four changes caused it.

The tell is that the failure appears when you ADD storage, not when you use it:
the array that breaks is whichever one the allocator happens to place last, not
the one you introduced.

So: read the array addresses out of the generated assembly and their sizes out
of the DIMs, and fail on anything whose last byte is above $07FF.

Run:  python3 checknesram.py [KEYSTONE.bas] [keystone_nes.asm]
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BAS = (sys.argv[1] if len(sys.argv) > 1
       else os.path.join(HERE, "..", "src", "KEYSTONE.bas"))
ASM = (sys.argv[2] if len(sys.argv) > 2
       else os.path.join(HERE, "..", "src", "keystone_nes.asm"))

RAM_TOP = 0x07FF                        # last byte of the NES's internal RAM


def dim_sizes(path):
    """name -> element count, from every DIM in the source.

    Taken from the SOURCE rather than from a table here: a second copy of the
    sizes is a second thing to go stale, and this check exists precisely
    because nobody notices storage growing.
    """
    out = {}
    for m in re.finditer(r"^\s*DIM\s+(\w+)\s*\(\s*(\d+)\s*\)",
                         open(path, encoding="utf-8", errors="replace").read(),
                         re.M):
        out[m.group(1).upper()] = int(m.group(2))
    return out


def arrays(path):
    """name -> base address, from the generated assembly."""
    out = {}
    for m in re.finditer(r"^array_(\w+):\s*equ\s*\$([0-9a-fA-F]+)",
                         open(path, encoding="utf-8", errors="replace").read(),
                         re.M):
        out[m.group(1).upper()] = int(m.group(2), 16)
    return out


def main():
    if not os.path.exists(ASM):
        print("checknesram: %s not found -- run the NES build first" % ASM)
        return 0
    sizes, base = dim_sizes(BAS), arrays(ASM)
    if not base:
        print("checknesram: no array_* symbols in the assembly; nothing to check")
        return 0

    bad, rows = [], []
    for name in sorted(base, key=lambda n: base[n]):
        n = sizes.get(name)
        if n is None:
            # An array the assembly has and the source does not DIM is either a
            # rename or a compiler temp. Say so rather than skip it silently.
            rows.append((name, base[name], None, None))
            continue
        end = base[name] + n - 1
        rows.append((name, base[name], n, end))
        if end > RAM_TOP:
            bad.append((name, base[name], n, end))

    for name, b, n, end in rows:
        if n is None:
            print("  array_%-8s $%04X   (no DIM found in the source)" % (name, b))
        else:
            print("  array_%-8s $%04X .. $%04X  %4d bytes%s"
                  % (name, b, end, n,
                     "   *** PAST $%04X ***" % RAM_TOP if end > RAM_TOP else ""))

    if bad:
        print()
        for name, b, n, end in bad:
            print("FAIL %s ends at $%04X, which is %d byte(s) past the end of "
                  "RAM. $0800 mirrors $0000, so those bytes land in the ZERO "
                  "PAGE and overwrite the runtime's pointers -- the symptom is "
                  "a black screen at boot with no error anywhere."
                  % (name, end, end - RAM_TOP))
        print("Shrink an array, or stage in one that is already there and idle "
              "at that moment.")
        return 1

    free = RAM_TOP - max(b + (sizes.get(n0) or 1) - 1
                         for n0, b in base.items())
    print("OK -- every array ends inside RAM, %d byte(s) to spare above the "
          "last one" % free)
    return 0


if __name__ == "__main__":
    sys.exit(main())
