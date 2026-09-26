#!/usr/bin/env python3
"""LZSS for the TI: the compressor, a reference decoder, and a .bas table reader.

THE FORMAT IS WHAT THE 9900 DECODER READS (lz_unpack in KEYSTONE.bas), so the
two must change together:

  a FLAG byte governs the next 8 items, least significant bit first;
  flag bit 1 -> one LITERAL byte;
  flag bit 0 -> a MATCH in two bytes, big-endian: offset (12 bits, 1..4095
               back into the OUTPUT) << 4 | (length - 3) (4 bits, so 3..18).

The decoder is told the output length and stops there, so the final flag
byte's unused bits are never read. Matches may overlap their own output (an
offset shorter than the length repeats a run), which is how long runs of one
value cost two bytes.

Greedy longest match over the whole 4 KB window. The compressor runs at build
time and can be slow; only the decoder has to be small.
"""
import re
import sys

WINDOW, MINM, MAXM = 4095, 3, 18


def compress(src):
    src = bytes(src)
    out = bytearray()
    i, n = 0, len(src)
    while i < n:
        flagpos = len(out)
        out.append(0)
        flags = 0
        for bit in range(8):
            if i >= n:
                break
            best_len, best_off = 0, 0
            for j in range(max(0, i - WINDOW), i):
                k = 0
                while k < MAXM and i + k < n and src[j + k] == src[i + k]:
                    k += 1
                if k > best_len:
                    best_len, best_off = k, i - j
                    if k == MAXM:
                        break
            if best_len >= MINM:
                v = (best_off << 4) | (best_len - MINM)
                out += bytes([v >> 8, v & 255])
                i += best_len
            else:
                flags |= 1 << bit
                out.append(src[i])
                i += 1
        out[flagpos] = flags
    return bytes(out)


def decompress(buf, n):
    """The reference decoder -- line for line what lz_unpack does."""
    out = bytearray()
    p = 0
    while len(out) < n:
        flags = buf[p]
        p += 1
        for bit in range(8):
            if len(out) >= n:
                break
            if flags >> bit & 1:
                out.append(buf[p])
                p += 1
            else:
                v = buf[p] << 8 | buf[p + 1]
                p += 2
                off, ln = v >> 4, (v & 15) + MINM
                for _ in range(ln):
                    out.append(out[-off])
    return bytes(out)


def checksums(data):
    """(s1, s2): a Fletcher-style pair, 16 bits each, as lz_verify computes it.
    s1 catches a wrong byte; s2 (the running sum of s1) catches a misplaced one."""
    s1 = s2 = 0
    for b in data:
        s1 = (s1 + b) & 0xFFFF
        s2 = (s2 + s1) & 0xFFFF
    return s1, s2


def _num(tok):
    tok = tok.strip()
    if tok.startswith('$'):
        return int(tok[1:], 16)
    return int(tok, 0)


def read_tables(path, target='TI994A'):
    """label -> bytes, from a CVBasic source's DATA / DATA BYTE blocks, keeping
    only the lines `target` compiles (#if NES / TI994A / COLECOVISION / #else).
    `DATA` words are stored big-endian, as the 9900 lays them out."""
    tables, cur = {}, None
    live = []
    for raw in open(path, encoding='utf-8', errors='replace'):
        line = raw.split("'", 1)[0].rstrip()
        st = line.strip()
        if st.startswith('#if'):
            live.append(st[3:].strip() == target)
            continue
        if st.startswith('#else'):
            if live:
                live[-1] = not live[-1]
            continue
        if st.startswith('#endif'):
            if live:
                live.pop()
            continue
        if not all(live):
            continue
        m = re.match(r'^(#?[A-Za-z_][A-Za-z0-9_]*):\s*$', line)
        if m:
            cur = m.group(1)
            tables[cur] = bytearray()
            continue
        if cur is None:
            continue
        m = re.match(r'^\s*DATA\s+BYTE\s+(.*)$', line, re.I)
        if m:
            tables[cur] += bytes(_num(t) & 255 for t in m.group(1).split(',') if t.strip())
            continue
        m = re.match(r'^\s*DATA\s+(.*)$', line, re.I)
        if m:
            for t in m.group(1).split(','):
                if t.strip():
                    v = _num(t) & 0xFFFF
                    tables[cur] += bytes([v >> 8, v & 255])
            continue
        if st and not re.match(r'^(DATA|BITMAP)\b', st, re.I):
            cur = None                      # code ends a table
    return {k: bytes(v) for k, v in tables.items()}


def emit_bytes(fh, label, data, comment=''):
    """A DATA BYTE block, PADDED TO AN EVEN LENGTH: an odd block leaves the
    location counter odd and misaligns every word table after it (CLAUDE.md 3A).
    The pad byte is never read -- the decoder stops at its output length."""
    data = bytes(data) + (b'\0' if len(data) % 2 else b'')
    fh.write('%s:%s\n' % (label, ("\t' " + comment) if comment else ''))
    for i in range(0, len(data), 16):
        fh.write('\tDATA BYTE %s\n' % ','.join(str(b) for b in data[i:i + 16]))


if __name__ == '__main__':
    import random
    random.seed(1)
    for n in (0, 1, 7, 8, 9, 100, 4000):
        for kind in ('rand', 'runs', 'text'):
            if kind == 'rand':
                d = bytes(random.randrange(256) for _ in range(n))
            elif kind == 'runs':
                d = bytes((i // 37) % 5 for i in range(n))
            else:
                d = (b'KEYSTONE KAPERS ' * (n // 16 + 1))[:n]
            c = compress(d)
            assert decompress(c, len(d)) == d, (n, kind)
    print('lzss self-test OK')
    sys.exit(0)
