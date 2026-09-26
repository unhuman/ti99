#!/usr/bin/env python3
"""Generate src/titlemusic.bas -- the game's music (TI, ColecoVision and NES).

The tunes are not written here. They come from the tunes bench
(sound/tunes), rendered by that bench's own generator, so the game plays
exactly what was auditioned there and an edit in
sound/tunes/assets/gentunes.py reaches the game on its next build.

    title_tune  TITLE_PICK, full three voices + drums (PLAY FULL)
    game_tune   GAME_PICK, cut to TWO voices, melody and bass, no drums, for
                PLAY SIMPLE NO DRUMS during play. That mode owns channels 0
                and 1 only, which leaves channel 2 (prizes, lives, tally) and
                noise (footsteps) to the effects; jumps (ch 0) and hits
                (ch 1) duck the music instead -- see music_duck.

The labels are fixed so KEYSTONE.bas never names a bench tune; to change a
tune, change its PICK.

Each block is 1 tick byte + 4 bytes a row + 1 REPEAT byte, which is EVEN --
asserted below, because an odd-length block misaligns every word table after
it in the bank (CLAUDE.md 3A).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'sound', 'tunes', 'assets'))
import gentunes  # noqa: E402

TITLE_PICK = 'tune_street'
GAME_PICK = 'tune_chase'


def pick(label):
    tune = [t for t in gentunes.TUNES if t['label'] == label]
    if len(tune) != 1:
        sys.exit('genmusic: %s not found in sound/tunes/assets/gentunes.py' % label)
    if not tune[0].get('loop', True):
        sys.exit('genmusic: %s plays once; a screen needs a looping tune' % label)
    return tune[0]


def two_voice(rows):
    """MUSIC mel,comp,bass,drum -> MUSIC mel,bass.

    PLAY SIMPLE plays the first two voices, so the bass has to move up to
    second place and the comping goes. The bass keeps its Z (it is on its
    first note) and the melody its W.
    """
    out = []
    for r in rows:
        head, args = r.split('MUSIC ', 1)
        a = args.split(',')
        if len(a) != 4:
            sys.exit('genmusic: unexpected MUSIC row %r' % r)
        out.append('%sMUSIC %s,%s' % (head, a[0], a[2]))
    return out


# ---------------------------------------------------------------------------
# THE BYTES `MUSIC` COMPILES TO, exactly (cvbasic.c, the MUSIC statement), so
# the TI can carry the tunes LZSS-compressed in RAM (DESIGN.md section 56)
# while the ColecoVision and NES keep compiling the MUSIC statements.
#   a row is four bytes, voice 0 first; a voice is 0 for `-`, >3F for `S`, a
#   drum (voice 3) M1..M3 as 1..3, or a note: C..B + (octave-2)*12 + 1 (+1 for
#   #; C7 is 61) OR its instrument, >00 W, >40 X, >80 Y, >C0 Z. A note with no
#   letter takes its voice's last instrument -- and CVBasic keeps that in a
#   `static` array for the WHOLE COMPILE, so it carries from tune to tune in
#   source order; encode() takes and returns it.
#   MUSIC REPEAT is FOUR bytes, >FD,0,0,0 (STOP >FE,0,0,0), so a tune is
#   1 + 4*rows + 4 bytes: ODD. It is read a byte at a time, which is fine, but
#   nothing word-aligned may follow it unpadded.
_NOTE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
_INST = {'W': 0x00, 'X': 0x40, 'Y': 0x80, 'Z': 0xC0}


def _voice(tok, arg, prev):
    tok = tok.strip()
    if tok == '-':
        return 0
    if tok == 'S':
        return 0x3F
    if arg == 3:
        if len(tok) == 2 and tok[0] == 'M' and tok[1] in '123':
            return int(tok[1])
        sys.exit('genmusic: bad drum %r' % tok)
    n = _NOTE[tok[0]]
    octave = int(tok[1])
    if octave == 7:
        if n != 0:
            sys.exit('genmusic: only C7 exists above octave 6, not %r' % tok)
        n += 60
    else:
        n += (octave - 2) * 12
    n += 1
    rest = tok[2:]
    if rest.startswith('#'):
        n += 1
        rest = rest[1:]
    if rest:
        prev[arg] = _INST[rest]
    return n | prev[arg]


def encode(ticks, rows, end, prev):
    """The bytes a `DATA BYTE ticks` + `MUSIC` rows + MUSIC REPEAT/STOP compile to."""
    out = bytearray([ticks & 0xFF])
    for r in rows:
        args = r.split('MUSIC ', 1)[1].split(',')
        v = [0, 0, 0, 0]
        for a, tok in enumerate(args):
            v[a] = _voice(tok, a, prev)
        out += bytes(v)
    out += bytes([0xFD if end == 'REPEAT' else 0xFE, 0, 0, 0])
    return bytes(out)


def tune_bytes():
    """label -> the TI's tune bytes, in source order (title_tune, game_tune),
    with CVBasic's carried instrument state. The TI never takes the NES cut."""
    prev = [0, 0, 0, 0]
    title = pick(TITLE_PICK)
    game = pick(GAME_PICK)
    return {
        'title_tune': encode(title['ticks'], gentunes.render(title), 'REPEAT', prev),
        'game_tune': encode(game['ticks'], two_voice(gentunes.render(game)), 'REPEAT', prev),
    }


def block(label, source, t, rows, note):
    size = 1 + 4 * len(rows) + 4           # MUSIC REPEAT is four bytes
    lines = [
        "\t' %s: the tunes bench's %s, %s. %d bars, %d rows, %d bytes."
        % (label, source, note, len(t['bars']), len(rows), size),
        '%s:' % label,
        '\tDATA BYTE %d' % t['ticks'],
    ]
    lines.extend(rows)
    lines.append('\tMUSIC REPEAT')
    lines.append('')
    return lines, size


# AN NES-ONLY CUT OF THE TITLE TUNE, if its PRG ever runs short again. With both
# 16-bar tunes it once came out 56 bytes over (Keystone DESIGN.md section 50)
# and the NES title played STREET's first 8 bars (its first half ends on its C7
# and turns cleanly back to the top) until section 51 found the bytes. None =
# no cut: one copy of both tunes for every target. A number emits the cut under
# #if NES and the full tunes under #else, so the TI and ColecoVision never change.
NES_TITLE_BARS = None


def first_bars(t, n):
    short = dict(t)
    short['bars'] = t['bars'][:n]
    return short


def both(title, game, note):
    tl, ts = block('title_tune', TITLE_PICK, title, gentunes.render(title),
                   'three voices and drums' + note)
    gl, gs = block('game_tune', GAME_PICK, game, two_voice(gentunes.render(game)),
                   'melody and bass only' + note)
    return tl + gl, ts, gs


def main():
    title = pick(TITLE_PICK)
    game = pick(GAME_PICK)
    out = ["\t' GENERATED by assets/genmusic.py -- edit sound/tunes/assets/gentunes.py,",
           "\t' not this.", '']
    # THE TI COMPILES NONE OF THIS: it carries the same bytes (tune_bytes)
    # LZSS-compressed in its play stream, unpacked into RAM, with `PLAY
    # title_tune` following an EQU there (assets/genlzss.py, DESIGN.md 56).
    # #if cannot nest, so each target that does compile the tunes gets its own
    # block.
    full, ts, gs = both(title, game, '')
    if NES_TITLE_BARS is None:
        out += ['#if TI994A', '#else'] + full + ['#endif', '']
        nts, ngs = ts, gs
    else:
        nes, nts, ngs = both(first_bars(title, NES_TITLE_BARS), game,
                             ' (NES: title first %d bars)' % NES_TITLE_BARS)
        out += (['#if NES'] + nes + ['#endif'] +
                ['#if COLECOVISION'] + full + ['#endif', ''])
    with open(os.path.join(HERE, '..', 'src', 'titlemusic.bas'), 'w', newline='\n') as f:
        f.write('\n'.join(out))
    print('genmusic: %s -> title_tune (%d B; NES %d B), %s -> game_tune (%d B; NES %d B)'
          % (TITLE_PICK, ts, nts, GAME_PICK, gs, ngs))


if __name__ == '__main__':
    main()
