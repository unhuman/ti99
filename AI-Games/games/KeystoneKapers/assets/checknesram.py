#!/usr/bin/env python3
"""No array may run off the end of the NES's internal RAM.

The NES has 2 KB at $0000-$07FF and the address space MIRRORS: $0800 reads and
writes $0000, which is the zero page. So an array that overruns $07FF does not
fault and does not touch unused memory -- it quietly overwrites CVBasic's own
pointers.

CVBASIC DOES NOT CATCH THIS. It reports a byte count against a notional total
("1567 RAM bytes used of 1838 available") and keeps allocating past the end of
the physical RAM. Adding a 32-byte array to Keystone Kapers pushed the tail of
`nesb` five bytes over, and the only symptom was a BLACK SCREEN AT BOOT -- no
compiler error, no assembler error, no bad exit status, and a ROM of exactly the
right size.

The tell is that the failure appears when you ADD storage, not when you use it:
the array that breaks is whichever one the allocator happens to place last, not
the one you introduced.

THE OVERRUN IS NOT ALWAYS A BLACK SCREEN, AND THE SECOND SHAPE IS WORSE.
------------------------------------------------------------------------
The overrun that prompted this file landed on something the runtime needs to
boot, so it died immediately and obviously. The next one landed on a zero-page
byte the program only touches occasionally, and the game ran: `#tsrc`, the table
of template source offsets the store's band blit reads, had its last entry
sharing a byte with the zero page. The result was one screen whose top and
bottom bands blitted their NAME TABLE from the wrong address -- a field of
unrelated characters, on that screen only, band 1 perfectly correct, every other
screen perfectly correct.

**It was reported as "the NES display is all corrupted", and it looked like an
art or a blit bug.** Nothing about it suggested storage. So: this check is not
about black screens, it is about the allocator, and it has to be believed even
when the machine seems fine.

AND THE REASON IT MISSED THAT ONE IS WORTH MORE THAN THE CHECK
---------------------------------------------------------------
Both of this file's regexes used `\\w+`, and **`\\w` does not match `#`**. Every
16-bit array in the program is named `#something`, so `DIM #tsrc(15)` and
`array_#TSRC: equ $07e3` were both invisible: the gate printed OK while reading
none of them. It is the same slip as grepping for `NSRC` in the generated
assembly, where the symbol is `cvb_#NSRC`.

A 16-bit array is also **TWO BYTES AN ELEMENT**, so `DIM #tsrc(15)` is 30 bytes,
not 15. Missing that would have under-reported the very array that broke.

**An array in the assembly with no DIM in the source is now a FAILURE, not a
note.** Skipping it is how a gate reports success on the thing it is for.

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


def width(name):
    """Bytes per element. A CVBasic name starting `#` is 16-bit."""
    return 2 if name.startswith("#") else 1


def dim_sizes(path):
    """name -> element count, from every DIM in the source.

    Taken from the SOURCE rather than from a table here: a second copy of the
    sizes is a second thing to go stale, and this check exists precisely
    because nobody notices storage growing.
    """
    out = {}
    for m in re.finditer(r"^\s*DIM\s+(#?\w+)\s*\(\s*(\d+)\s*\)",
                         open(path, encoding="utf-8", errors="replace").read(),
                         re.M):
        out[m.group(1).upper()] = int(m.group(2))
    return out


def arrays(path):
    """name -> base address, from the generated assembly."""
    out = {}
    for m in re.finditer(r"^array_(#?\w+):\s*equ\s*\$([0-9a-fA-F]+)",
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

    bad, unknown, rows, ends = [], [], [], []
    for name in sorted(base, key=lambda n: base[n]):
        n = sizes.get(name)
        if n is None:
            unknown.append((name, base[name]))
            rows.append((name, base[name], None, None))
            continue
        nbytes = n * width(name)
        end = base[name] + nbytes - 1
        ends.append(end)
        rows.append((name, base[name], nbytes, end))
        if end > RAM_TOP:
            bad.append((name, base[name], nbytes, end))

    for name, b, nbytes, end in rows:
        if nbytes is None:
            print("  array_%-8s $%04X   (NO DIM FOUND IN THE SOURCE)" % (name, b))
        else:
            print("  array_%-8s $%04X .. $%04X  %4d bytes%s"
                  % (name, b, end, nbytes,
                     "   *** PAST $%04X ***" % RAM_TOP if end > RAM_TOP else ""))

    if unknown:
        print()
        for name, b in unknown:
            print("FAIL array_%s is at $%04X and the source has no `DIM %s(...)` "
                  "-- its size is unknown, so it cannot be checked. An array this "
                  "file cannot measure is exactly the one that overruns; fix the "
                  "name or the pattern rather than letting it through."
                  % (name, b, name.lower()))
    if bad:
        print()
        for name, b, nbytes, end in bad:
            print("FAIL %s ends at $%04X, which is %d byte(s) past the end of "
                  "RAM. $0800 mirrors $0000, so those bytes land in the ZERO "
                  "PAGE and share memory with the runtime's own pointers. That "
                  "is sometimes a black screen at boot and sometimes a single "
                  "table entry reading back wrong -- in this game a corrupted "
                  "`#tsrc` blitted one screen's bands from the wrong address and "
                  "was reported as corrupt artwork."
                  % (name, end, end - RAM_TOP))
        print("Shrink an array, or spend no new scratch VARIABLES: three bytes "
              "of scalars is enough to push the last array over.")
    if bad or unknown:
        return 1

    free = RAM_TOP - max(ends)
    print("OK -- all %d arrays end inside RAM (16-bit ones counted at two bytes "
          "an element), %d byte(s) to spare above the last one"
          % (len(ends), free))
    return 0


if __name__ == "__main__":
    sys.exit(main())
