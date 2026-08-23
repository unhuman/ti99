#!/usr/bin/env python3
"""Find CVBasic CONSTs over 255 -- they are silently truncated to 8 bits.

`CONST RNDPOS = 311` compiles to `li r0,55`. Not an error, not a warning: 311 AND
255. The same value written inline compiles correctly, so the fix is always to
drop the CONST and use a bare literal (or a 16-bit variable).

What makes it worth a sweep rather than a rule: a CONST can be SAFE FOR YEARS AND
THEN BREAK WITHOUT BEING TOUCHED. Bust-A-Bobble's round-number offset sat at 247
while ROUND was on row 7; moving the label down two rows made it 311, and the
digits silently began landing on the score. The edit that breaks it is a layout
change, and the value it breaks is one nobody was looking at.

Note the failure is truncation, not zeroing -- 311 became 55, a perfectly
plausible screen offset. Only values whose low byte is 0 compile to `clr`.

Run:  python3 tools/bigconst.py
"""
import glob
import os
import re
import sys

hits = 0
for path in sorted(glob.glob(os.path.join("games", "*", "src", "*.bas"))):
    for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        m = re.match(r"\s*CONST\s+(\w+)\s*=\s*(\d+)\s*$", line.split("'")[0].rstrip())
        if m and int(m.group(2)) > 255:
            v = int(m.group(2))
            print("  %s:%d  CONST %s = %d  ->  compiles as %d"
                  % (path, n, m.group(1), v, v & 255))
            hits += 1
print("  %d CONST(s) over 255" % hits)
sys.exit(1 if hits else 0)
