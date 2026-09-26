#!/usr/bin/env python3
"""Generate src/lzss_play.bas: the TI's tables, LZSS-compressed into two streams.

TI ONLY (the ColecoVision and NES builds never include the file, and compile
the tables from store/art/title/font/titlefont/scancol/titledl.bas exactly as
before). The TI single-bank work is Keystone DESIGN.md sections 53-55.

    lz_play   the tables read DURING PLAY (and the title's display list and
              the jump arc, which are read after setup): unpacked into lzbuf
              at power-on, after setup, and resident from then on
    lz_sdat   the tables read only at SETUP (store and sprite art, the fonts,
              their colour tables, the radar colours): unpacked into lzbuf at
              the very start of boot, uploaded by setup, then overwritten
    #lz_meta / #lz_smeta   words: table count, total bytes, then per table
              length, s1, s2 (lzss.checksums), checked on the TI after unpacking

Every table's symbol becomes `cvb_NAME: EQU array_LZBUF+offset`, so the game's
own statements (SCREEN, DEFINE, VARPTR, indexed reads) read RAM unchanged, and
exclude_from_ti() takes the ROM copies out of the TI's view.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lzss  # noqa: E402

SRC = os.path.join(HERE, '..', 'src')
FILES = ('store.bas', 'art.bas', 'title.bas', 'font.bas', 'titlefont.bas',
         'scancol.bas', 'titledl.bas')

# Read during play on the TI (DESIGN.md section 53), plus two read after setup:
# title_tbl (title_draw, on every return to the title) and jarc_tbl (init_jarc).
PLAY = ['stor_tpl', 'stor_lvl', 'stor_arc', 'esc_cap', 'stor_co', 'stor_pil',
        'stor_ix', 'stor_esc', 'spr_hstand', 'spr_hstandl', 'spr_hbod4',
        'msg_away', 'msg_gothim', 'msg_over', 'msg_plane', 'msg_timeup',
        'bulb_lit', 'bulb_off'] + ['esc_ph%s%d' % (s, p) for p in range(4) for s in 'we'] + [
        'title_tbl', 'jarc_tbl']

# Read only at SETUP (DESIGN.md section 55). The one-value colour tables ride
# along: they compress to almost nothing, and DEFINE COLOR keeps working.
SETUP = ['store_pat', 'store_col', 'spr_harry', 'spr_kelly', 'spr_plane',
         'spr_cart', 'spr_ball', 'spr_radio', 'spr_radcar', 'spr_raddot',
         'esc_deck', 'font_bits', 'font_col', 'tfont_pat0', 'tfont_col0',
         'tfont_pat1', 'tfont_col1', 'scan_cols']


def exclude_from_ti(path, labels):
    """Take `labels`' DATA blocks out of the TI's view, in place, idempotently.

    * a table outside any #if:        #if TI994A / #else / table / #endif
    * a table in the #else of #if NES: that block's #else becomes
      `#endif` + `#if COLECOVISION` (#if cannot nest), so the NES keeps its
      branch, the ColecoVision keeps the TMS one, and the TI gets neither. Every
      table in such a branch must be one the TI no longer needs.
    Tables already wrapped (#if TI994A) or split (#if COLECOVISION), and the NES
    copies in an #if NES branch, are left alone.
    """
    lines = open(path, encoding='utf-8').read().split('\n')
    stack = []                  # [cond, in_else, index_of_else]
    wrap, split = [], set()
    branch_labels = {}          # index_of_else -> labels in that else branch
    for i, ln in enumerate(lines):
        st = ln.strip()
        if st.startswith('#if'):
            stack.append([st[3:].strip(), False, None])
            continue
        if st.startswith('#else'):
            stack[-1][1] = True
            stack[-1][2] = i
            continue
        if st.startswith('#endif'):
            stack.pop()
            continue
        name = ln.split(':', 1)[0] if ':' in ln and not ln.startswith(('\t', ' ', '#', "'")) else None
        if name is None:
            continue
        if stack and stack[-1][1] and stack[-1][0] == 'NES':
            branch_labels.setdefault(stack[-1][2], []).append(name)
        if name not in labels:
            continue
        if not stack:
            wrap.append(i)
        elif stack[-1][0] == 'NES' and stack[-1][1]:
            split.add(stack[-1][2])
        elif stack[-1][0] in ('TI994A', 'COLECOVISION') or (stack[-1][0] == 'NES' and not stack[-1][1]):
            pass                # already excluded, or the NES's own copy
        else:
            sys.exit('genlzss: %s in %s sits in an #if %s block it cannot be taken out of'
                     % (name, os.path.basename(path), stack[-1][0]))
    for e in split:
        stray = [n for n in branch_labels.get(e, []) if n not in labels]
        if stray:
            sys.exit('genlzss: splitting %s line %d would also drop %s from the TI'
                     % (os.path.basename(path), e + 1, stray))
    out = []
    i = 0
    while i < len(lines):
        if i in split:
            out += ['#endif', '#if COLECOVISION']
            i += 1
            continue
        if i in wrap:
            j = i + 1
            while j < len(lines) and lines[j].lstrip().upper().startswith('DATA'):
                j += 1
            out += ['#if TI994A', '#else'] + lines[i:j] + ['#endif']
            i = j
            continue
        out.append(lines[i])
        i += 1
    open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))


def stream(tables, names, label, corrupt=False):
    raw = b''.join(tables[t] for t in names)
    comp = lzss.compress(raw)
    if lzss.decompress(comp, len(raw)) != raw:
        sys.exit('genlzss: %s does not round-trip' % label)
    # MUTATION TEST ONLY: KK_LZ_CORRUPT=1 flips the first literal of the play
    # stream AFTER the round-trip check, so the TI's self-test must report it.
    if corrupt:
        comp = bytearray(comp)
        comp[1] ^= 0x55
        comp = bytes(comp)
        print('genlzss: KK_LZ_CORRUPT=1 -- %s is DELIBERATELY corrupted' % label)
    meta = [len(names), len(raw)]
    for t in names:
        meta += [len(tables[t])] + list(lzss.checksums(tables[t]))
    return raw, comp, meta


def main():
    tables = {}
    # The COLECOVISION view: the same bytes as the TI's, and still present
    # after exclude_from_ti has taken them out of the TI's view.
    for f in FILES:
        tables.update(lzss.read_tables(os.path.join(SRC, f), target='COLECOVISION'))
    missing = [t for t in PLAY + SETUP if not tables.get(t)]
    if missing:
        sys.exit('genlzss: tables not found in the generated sources: %s' % missing)
    corrupt = os.environ.get('KK_LZ_CORRUPT') == '1'
    praw, pcomp, pmeta = stream(tables, PLAY, 'lz_play', corrupt)
    sraw, scomp, smeta = stream(tables, SETUP, 'lz_sdat')
    size = max(len(praw), len(sraw))
    with open(os.path.join(SRC, 'lzss_play.bas'), 'w', newline='\n') as fh:
        fh.write("\t' GENERATED by assets/genlzss.py -- do not edit. TI only.\n")
        fh.write("\t' lz_play: %d tables, %d B -> %d B.  lz_sdat: %d tables, %d B -> %d B.\n"
                 % (len(PLAY), len(praw), len(pcomp), len(SETUP), len(sraw), len(scomp)))
        # sized from the streams here, never typed: a CONST over 255 truncates
        fh.write('\tDIM lzbuf(%d)\t\t\' the larger of the two streams, unpacked\n' % size)
        lzss.emit_bytes(fh, 'lz_play', pcomp, 'LZSS -- see assets/lzss.py')
        lzss.emit_bytes(fh, 'lz_sdat', scomp, 'LZSS -- setup tables')
        for label, meta in (('#lz_meta', pmeta), ('#lz_smeta', smeta)):
            fh.write('%s:\n' % label)
            for i in range(0, len(meta), 12):
                fh.write('\tDATA %s\n' % ','.join(str(v) for v in meta[i:i + 12]))
        # EVERY TABLE'S SYMBOL IS AN ADDRESS IN lzbuf. THE COLON AFTER THE
        # SYMBOL IS LOAD-BEARING: CVBasic writes an ASM line at column 1 only
        # when its FIRST WORD ends in ':', and an indented `cvb_X EQU` is read
        # by xas99 as the mnemonic CVB_X (CLAUDE.md 3A). build-ti.sh moves
        # these after the RAM declarations: xas99 cannot resolve a forward EQU.
        for group, names in (('play', PLAY), ('setup', SETUP)):
            fh.write("\t' The %s tables' symbols, pointed into lzbuf.\n" % group)
            off = 0
            for t in names:
                fh.write('\tASM cvb_%s: EQU array_LZBUF+%d\n' % (t.upper(), off))
                off += len(tables[t])
    want = set(PLAY) | set(SETUP)
    for f in FILES:
        exclude_from_ti(os.path.join(SRC, f), want)
    print('genlzss: play %d B -> %d B, setup %d B -> %d B, lzbuf %d B'
          % (len(praw), len(pcomp), len(sraw), len(scomp), size))


if __name__ == '__main__':
    main()
