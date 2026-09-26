#!/usr/bin/env python3
"""Generate src/lzss_play.bas: the TI's play tables, LZSS-compressed.

TI ONLY (the ColecoVision and NES builds never include it). This is step 1 of
the TI single-bank work (Keystone DESIGN.md section 53): the tables the game
reads DURING PLAY -- store templates, level and store tables, escalator
phases, Harry's swap poses, the message boxes, the marquee lamps -- taken from
the generated sources exactly as the ROM holds them today, concatenated in
PLAY order, compressed, and checked here by decoding them back.

    lz_play     the compressed stream (padded to an even length)
    #lz_meta    words: table count, total bytes, then per table
                length, s1, s2 (lzss.checksums), which lz_verify checks after
                the 9900 unpacks the stream into RAM
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lzss  # noqa: E402

SRC = os.path.join(HERE, '..', 'src')

# Read during play on the TI (DESIGN.md section 53 has the classification).
PLAY = ['stor_tpl', 'stor_lvl', 'stor_arc', 'esc_cap', 'stor_co', 'stor_pil',
        'stor_ix', 'stor_esc', 'spr_hstand', 'spr_hstandl', 'spr_hbod4',
        'msg_away', 'msg_gothim', 'msg_over', 'msg_plane', 'msg_timeup',
        'bulb_lit', 'bulb_off'] + ['esc_ph%s%d' % (s, p) for p in range(4) for s in 'we']


# STEP-1 PROBE: bank 2 has room for the decoder test but not yet for the whole
# stream (the tables only LEAVE bank 1 in step 2). This subset covers every
# kind of data in the stream -- long runs (templates), sparse level data,
# message text, escalator pattern art and a sprite -- 3,092 bytes -> ~802.
PROBE = ['stor_tpl', 'stor_lvl', 'msg_away', 'msg_gothim', 'esc_phw0',
         'esc_phe0', 'spr_hstand']


def exclude_from_ti(path, labels):
    """Take `labels`' DATA blocks out of the TI build, in place and idempotently.

    On the TI these tables live in RAM (lzbuf, unpacked at power-on) and their
    symbols are EQUs into it, so a ROM copy would be a duplicate symbol. The
    ColecoVision and NES compile them exactly as before.
      * a plain block becomes  #if TI994A / #else / block / #endif
      * title.bas's `#if NES / msg / #else / msg / #endif` pairs become
        `#if NES / msg / #endif` + `#if COLECOVISION / msg / #endif`
        (#if cannot nest, so the TMS copy gets its own block)
    """
    if os.path.basename(path) == 'title.bas':
        # Every table here already sits in an `#if NES / #else` pair; wrapping
        # it again would nest (#if cannot), so only the pair is split.
        text = open(path, encoding='utf-8').read()
        text = text.replace('\n#else\n', '\n#endif\n#if COLECOVISION\n')
        open(path, 'w', encoding='utf-8', newline='\n').write(text)
        return
    lines = open(path, encoding='utf-8').read().split('\n')
    out, i = [], 0
    while i < len(lines):
        ln = lines[i]
        name = ln.split(':', 1)[0] if ':' in ln and not ln.startswith(('\t', ' ', '#', "'")) else None
        if name in labels:
            if out[-2:] == ['#if TI994A', '#else']:
                out.append(ln)                      # already excluded
                i += 1
                continue
            j = i + 1
            while j < len(lines) and lines[j].lstrip().upper().startswith('DATA'):
                j += 1
            out += ['#if TI994A', '#else'] + lines[i:j] + ['#endif']
            i = j
            continue
        out.append(ln)
        i += 1
    open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))


def main():
    global PLAY
    probe = '--probe' in sys.argv
    if probe:
        PLAY = PROBE
    tables = {}
    # The COLECOVISION view: the same bytes as the TI's, and still present
    # after exclude_from_ti has taken them out of the TI's view.
    for f in ('store.bas', 'art.bas', 'title.bas'):
        tables.update(lzss.read_tables(os.path.join(SRC, f), target='COLECOVISION'))
    missing = [t for t in PLAY if t not in tables or not tables[t]]
    if missing:
        sys.exit('genlzss: tables not found in the generated sources: %s' % missing)
    raw = b''.join(tables[t] for t in PLAY)
    comp = lzss.compress(raw)
    if lzss.decompress(comp, len(raw)) != raw:
        sys.exit('genlzss: the play stream does not round-trip')
    # MUTATION TEST ONLY: KK_LZ_CORRUPT=1 flips one literal byte AFTER the
    # round-trip check, so a build carries a stream the TI must reject. Used to
    # prove the on-machine verification can fail; never set in a real build.
    if os.environ.get('KK_LZ_CORRUPT') == '1':
        comp = bytearray(comp)
        comp[1] ^= 0x55          # byte 0 is a flag; byte 1 is the first literal
        comp = bytes(comp)
        print('genlzss: KK_LZ_CORRUPT=1 -- the stream is DELIBERATELY corrupted')
    meta = [len(PLAY), len(raw)]
    for t in PLAY:
        s1, s2 = lzss.checksums(tables[t])
        meta += [len(tables[t]), s1, s2]
    with open(os.path.join(SRC, 'lzss_play.bas'), 'w', newline='\n') as fh:
        fh.write("\t' GENERATED by assets/genlzss.py -- do not edit.\n")
        fh.write("\t' TI only. %d play tables, %d bytes, compressed to %d.\n"
                 % (len(PLAY), len(raw), len(comp)))
        fh.write("\t' Order: %s\n" % ', '.join(PLAY))
        lzss.emit_bytes(fh, 'lz_play', comp, 'LZSS -- see assets/lzss.py')
        fh.write('#lz_meta:\n')
        for i in range(0, len(meta), 12):
            fh.write('\tDATA %s\n' % ','.join(str(v) for v in meta[i:i + 12]))
        if not probe:
            # EVERY TABLE'S SYMBOL IS AN ADDRESS IN THE RAM BUFFER. The game's
            # own statements -- SCREEN stor_tpl, DEFINE CHAR ...,esc_phw0,
            # VARPTR stor_lvl(0) -- compile to references to cvb_<NAME>, so
            # defining that symbol here moves every reader to RAM without
            # touching a single call site.
            #
            # THE COLON AFTER THE SYMBOL IS LOAD-BEARING. CVBasic writes an ASM
            # line at column 1 only when its FIRST WORD ends in ':' (that is how
            # it recognises a label; cvbasic.c, the ASM statement) and indents
            # every other one -- and an indented `cvb_X EQU ...` is read by
            # xas99 as the mnemonic CVB_X. xas99 takes `label: EQU value`.
            fh.write("\t' Each play table's symbol, pointed into lzbuf (TI only).\n")
            off = 0
            for t in PLAY:
                fh.write('\tASM cvb_%s: EQU array_LZBUF+%d\n' % (t.upper(), off))
                off += len(tables[t])
    if not probe:
        want = set(PLAY)
        for f in ('store.bas', 'art.bas', 'title.bas'):
            exclude_from_ti(os.path.join(SRC, f), want)
    print('genlzss: %d play tables, %d B -> %d B' % (len(PLAY), len(raw), len(comp)))


if __name__ == '__main__':
    main()
