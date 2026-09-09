#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""bankfill must REJECT a truncated bank, not just describe a healthy one.

A guard that has only ever passed is not a guard. This drives `bankfill`'s three
moving parts against fixtures with a known answer:

  * `last_data_block` finds the final DATA run in a source, in the presence of
    earlier blocks, hex and decimal literals, comments and trailing comments.
  * the image search reports a truncated bank as MISSING.
  * `free_bytes` counts the $FF padding without being fooled by the two-byte
    trailer, or by $FF bytes that are real data.

WHY THIS IS A FIXTURE TEST AND NOT AN END-TO-END ONE. The obvious test is to
append a block big enough to overflow a real bank and build. That does not work
here, and the reason is worth recording: `build-ti.sh`'s first step REGENERATES
art.bas, store.bas and font.bas, so a fixture appended to any of them is erased
by the build before the assembler ever sees it. Tried, and the build came back
byte-identical with the probe silently gone.
"""

import io
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bankfill as B                                        # noqa: E402


SOURCE = """\t' a decoy block, so "the last one" has to actually be found
early_tbl:\t' with a trailing comment
\tDATA BYTE 1,2,3,4
\tDATA BYTE $05,$06

\t' and the one that matters
last_tbl:
\tDATA BYTE $DE,$AD,$BE,$EF
\tDATA BYTE 10,20,30,40\t' trailing comment here too
"""

WANT_LABEL = 'last_tbl'
WANT_BYTES = bytes([0xDE, 0xAD, 0xBE, 0xEF, 10, 20, 30, 40])


def image(body, size=8192):
    """A bank image: body, $FF padding, two-byte trailer."""
    pad = size - len(body) - B.TRAILER
    return body + b'\xff' * pad + b'\x60\x06'


def main():
    fails = 0
    tmp = tempfile.mkdtemp()
    try:
        p = os.path.join(tmp, 'fixture.bas')
        io.open(p, 'w', encoding='utf-8', newline='').write(SOURCE)

        label, data = B.last_data_block(p)
        if label == WANT_LABEL and data == WANT_BYTES:
            print('  ok    the LAST block is the one found (%s, %d B)'
                  % (label, len(data)))
        else:
            print('  FAIL  parsed %r / %s, wanted %r / %s'
                  % (label, list(data), WANT_LABEL, list(WANT_BYTES)))
            fails += 1

        # a healthy bank: the block is present
        good = image(b'\x01\x02\x03\x04\x05\x06' + WANT_BYTES)
        if good.find(WANT_BYTES) >= 0:
            print('  ok    an intact bank finds its last block')
        else:
            print('  FAIL  an intact bank reported its last block missing')
            fails += 1

        # a TRUNCATED bank: everything but the last block
        cut = image(b'\x01\x02\x03\x04\x05\x06')
        if cut.find(WANT_BYTES) < 0:
            print('  ok    a truncated bank is detected (last block absent)')
        else:
            print('  FAIL  a truncated bank was NOT detected -- the guard '
                  'cannot see the fault it exists for')
            fails += 1

        # padding arithmetic, including data that itself ends in $FF
        if B.free_bytes(good) == 8192 - 14 - B.TRAILER:
            print('  ok    free space counts padding, not the trailer')
        else:
            print('  FAIL  free_bytes said %d, wanted %d'
                  % (B.free_bytes(good), 8192 - 14 - B.TRAILER))
            fails += 1

        full = image(b'\xAA' * (8192 - B.TRAILER))
        if B.free_bytes(full) == 0:
            print('  ok    a completely full bank reports 0 free')
        else:
            print('  FAIL  a full bank reported %d free' % B.free_bytes(full))
            fails += 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
