#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Each ROM bank's last block must survive into the packed cart.

WHY THIS EXISTS
---------------
`build-ti.sh` guards the FIXED AREA and nothing else. The data banks had no
guard at all, and a bank overflow is **completely silent**: `xas99` and
`linkticart` say nothing, the excess is simply dropped, and what goes missing is
whatever sits nearest the end of the bank -- normally a `DATA` block, not code.
The symptom is a table that reads as garbage, months later, in whatever feature
happened to use it.

Bank 1 reached SIX spare bytes of 8,192 before anyone noticed, and the only
reason nothing had been lost was luck. That was checked by hand once. This does
it on every build.

WHAT IT CHECKS
--------------
For each bank, the **last DATA block of the last INCLUDE** in it -- the block
nearest the end, i.e. the one an overflow eats first -- is extracted from the
source and searched for, byte for byte, in that bank's packed image. Absent
means truncated.

It also reports free space, measured as the run of `$FF` padding before the
two-byte trailer each bank image carries. That number is the early warning: a
bank at six bytes free is one edit from silently losing something.

WHICH FILE IS WHICH BANK
------------------------
CVBasic's `BANK n` is PHYSICAL bank n+2 on the TI (banks 0-2 are the
RAM-resident program, copied to >A000 and run from there), so `BANK 1` is
`NAME_b3.bin` and `BANK 2` is `NAME_b4.bin`. The mapping is derived from the
`BANK`/`INCLUDE` order in the source rather than hardcoded, so adding a bank
does not silently leave it unchecked.

Usage:
    python3 bankfill.py [source.bas] [--warn N]
"""

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, os.pardir, 'src')

# Below this many free bytes a bank is reported as a WARNING -- not a failure,
# because a full bank that has not actually lost anything is still a working
# build, and a gate that fails on "nearly" is a gate people start ignoring.
WARN_BELOW = 64

TRAILER = 2                 # the two bytes each bank image ends with


def banks_from_source(path):
    """{bank number: [include filenames]} in source order."""
    cur = None
    out = {}
    for line in io.open(path, encoding='utf-8'):
        t = line.strip()
        if t.startswith("'"):
            continue
        m = re.match(r'^BANK\s+(\d+)\s*$', t)
        if m:
            cur = int(m.group(1))
            out.setdefault(cur, [])
            continue
        m = re.match(r'^INCLUDE\s+"([^"]+)"', t)
        if m and cur is not None:
            out[cur].append(m.group(1))
    return out


def last_data_block(path):
    """(label, bytes) of the final DATA BYTE run in a source file."""
    label = None
    best_label = None
    vals = []
    cur = []
    for line in io.open(path, encoding='utf-8'):
        t = line.strip()
        m = re.match(r'^([A-Za-z_]\w*):', t)
        if m:
            if cur:
                vals, best_label = cur, label
            label = m.group(1)
            cur = []
            t = t[m.end():].strip()
        if t.startswith("'") or 'DATA BYTE' not in t:
            continue
        body = t.split('DATA BYTE', 1)[1].split("'")[0]
        for tok in body.split(','):
            tok = tok.strip()
            if not tok:
                continue
            cur.append(int(tok[1:], 16) if tok.startswith('$') else int(tok))
    if cur:
        vals, best_label = cur, label
    return best_label, bytes(vals)


def free_bytes(img):
    """The run of $FF padding before the trailer."""
    i = len(img) - TRAILER
    n = 0
    while i > 0 and img[i - 1] == 0xFF:
        i -= 1
        n += 1
    return n


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    src = args[0] if args else os.path.join(SRC, 'KEYSTONE.bas')
    name = os.path.splitext(os.path.basename(src))[0]

    banks = banks_from_source(src)
    if not banks:
        print('bankfill: no BANK directives -- nothing to check')
        return 0

    bad, warn = [], []
    for n in sorted(banks):
        includes = banks[n]
        if not includes:
            continue
        img_path = os.path.join(SRC, '%s_b%d.bin' % (name, n + 2))
        if not os.path.exists(img_path):
            bad.append('bank %d: no %s -- build it first'
                       % (n, os.path.basename(img_path)))
            continue
        img = io.open(img_path, 'rb').read()

        last_inc = includes[-1]
        label, data = last_data_block(os.path.join(SRC, last_inc))
        free = free_bytes(img)

        if not data:
            print('bank %d (%s): %s has no DATA -- not checked'
                  % (n, os.path.basename(img_path), last_inc))
            continue

        found = img.find(data) >= 0
        print('bank %d -> %s: %5d of %5d used, %4d free   last block `%s` '
              '(%d B in %s) %s'
              % (n, os.path.basename(img_path), len(img) - free, len(img),
                 free, label, len(data), last_inc,
                 'intact' if found else 'MISSING'))
        if not found:
            bad.append('bank %d: `%s` -- the last block of %s -- is not in the '
                       'packed image. The bank overflowed and it was silently '
                       'discarded.' % (n, label, last_inc))
        elif free < WARN_BELOW:
            warn.append('bank %d has only %d bytes free' % (n, free))

    for w in warn:
        print('  WARN  %s -- one edit from losing something' % w)
    if bad:
        print('')
        for b in bad:
            print('  FAIL  %s' % b)
        print('')
        print('  Nothing in cvbasic -> xas99 -> linkticart reports this.')
        print('  Move a block to another bank, or add one.')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
