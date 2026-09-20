#!/usr/bin/env python3
"""Conservative, game-local TMS9900 branch relaxation, with assembly verification.

Only `Jcc skip / B @target / skip` in cvb_BOOT..BANK_0_FREE is replaced.
Labels and line numbers survive. Runtime, data banks and unknown conditions
are untouched. Use original addresses for one conservative pass; shortening
four bytes cannot increase a distance within this contiguous segment.
"""
import argparse
import bisect
import json
import re
from pathlib import Path

INVERSE = {'jeq': 'jne', 'jne': 'jeq', 'jhe': 'jl', 'jl': 'jhe'}
OPCODE = {'jeq': 0x1300, 'jne': 0x1600, 'jhe': 0x1400, 'jl': 0x1A00}
LABEL = re.compile(r'(?:cv\d+|cvb_[A-Z_0-9]+)')
ROW = re.compile(r'^\s*(\d+)\s+([0-9A-Fa-f]{4})\s+([0-9A-Fa-f]{4})(?:\s|$)')


def segment(lines):
    clean = [line.split(';')[0].strip() for line in lines]
    starts = [i + 1 for i, s in enumerate(clean) if s == 'cvb_BOOT']
    ends = [i + 1 for i, s in enumerate(clean) if s.startswith('BANK_0_FREE:')]
    if len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
        raise ValueError('expected one cvb_BOOT..BANK_0_FREE segment')
    lo, hi = starts[0], ends[0]
    for s in clean[lo-1:hi-1]:
        if re.search(r'\b(?:aorg|rorg|org|bank|bss|bes|copy|equ)\b|\$|^\.', s, re.I):
            raise ValueError('unsupported layout directive in game segment: ' + s)
    return [(i + 1, s) for i, s in enumerate(clean) if lo <= i + 1 < hi and s]


def addresses(listing, significant):
    lo, hi = significant[0][0], significant[-1][0]
    rows = {}
    for line in listing.splitlines():
        m = ROW.match(line)
        if m and lo <= int(m[1]) <= hi:
            n = int(m[1])
            if n in rows:
                raise ValueError('ambiguous listing line %d' % n)
            rows[n] = (int(m[2], 16), int(m[3], 16))
    labels, pending = {}, []
    for n, s in significant:
        if LABEL.fullmatch(s):
            if s in labels or s in pending:
                raise ValueError('duplicate label ' + s)
            pending.append(s)
        if n in rows:
            addr = rows[n][0]
            if not 0xA000 <= addr < 0xFFFE or addr % 2:
                raise ValueError('game instruction outside aligned fixed window')
            for label in pending:
                labels[label] = addr
            pending = []
    return rows, labels


def relax(source, listing):
    lines = source.splitlines(keepends=True)
    sig = segment(lines)
    rows, labels = addresses(listing, sig)
    changes = []
    for (n, s), (bn, branch), (_, skip) in zip(sig, sig[1:], sig[2:]):
        m = re.fullmatch(r'(jeq|jne|jhe|jl)\s+(cv\d+)', s)
        b = re.fullmatch(r'b\s+@(cv\d+|cvb_[A-Z_0-9]+)', branch)
        if not m or not b or skip != m[2]:
            continue
        if n not in rows or bn not in rows or b[1] not in labels or skip not in labels:
            raise ValueError('candidate missing from listing at line %d' % n)
        addr, word = rows[n]
        if word != OPCODE[m[1]] | 2 or rows[bn] != (addr + 2, 0x0460) or labels[skip] != addr + 6:
            raise ValueError('unexpected long-branch encoding at line %d' % n)
        delta = labels[b[1]] - addr - 2
        if delta % 2 or not -256 <= delta <= 254:
            continue
        inverse = INVERSE[m[1]]
        lines[n-1] = '\t%s %s ; shortened %s / b\n' % (inverse, b[1], m[1])
        lines[bn-1] = '\t; removed long branch (shortbranches.py)\n'
        changes.append({'line': n, 'removed': bn, 'op': inverse, 'target': b[1]})
    return ''.join(lines), changes


def verify(original, before, optimized, after, changes):
    expected, expected_changes = relax(original, before)
    if optimized != expected or changes != expected_changes:
        raise ValueError('optimized source or manifest differs from planned edits')
    old, _ = addresses(before, segment(original.splitlines()))
    new, labels = addresses(after, segment(optimized.splitlines()))
    removed = sorted(c['removed'] for c in changes)
    if set(new) != set(old) - set(removed):
        raise ValueError('unexpected emitted/removed source lines')
    for n, (addr, _) in new.items():
        if addr != old[n][0] - 4 * bisect.bisect_left(removed, n):
            raise ValueError('unexpected layout change at line %d' % n)
    for c in changes:
        addr, word = new[c['line']]
        delta = labels[c['target']] - addr - 2
        if delta % 2 or not -256 <= delta <= 254:
            raise ValueError('shortened jump out of range')
        if word != OPCODE[c['op']] | ((delta // 2) & 255):
            raise ValueError('wrong shortened opcode/destination')
    print('TI short branches: %d verified, %d fixed-area bytes saved' % (len(changes), 4 * len(changes)))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('mode', choices=['rewrite', 'verify'])
    p.add_argument('original')
    p.add_argument('before')
    p.add_argument('optimized')
    p.add_argument('after')
    p.add_argument('manifest')
    a = p.parse_args()
    read = lambda path: Path(path).read_text(encoding='utf-8')
    try:
        if a.mode == 'rewrite':
            source, changes = relax(read(a.original), read(a.before))
            with open(a.optimized, 'w', encoding='utf-8', newline='') as out:
                out.write(source)
            Path(a.manifest).write_text(json.dumps(changes), encoding='utf-8')
        else:
            verify(read(a.original), read(a.before), read(a.optimized), read(a.after), json.loads(read(a.manifest)))
    except (ValueError, KeyError) as e:
        p.exit(1, 'TI short branches: %s\n' % e)


if __name__ == '__main__':
    main()
