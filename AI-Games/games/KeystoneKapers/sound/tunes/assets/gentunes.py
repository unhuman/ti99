#!/usr/bin/env python3
"""Generate src/songs.bas -- the MUSIC tables for the tunes bench.

A tune is written as BARS: a chord symbol and one melody token per
eighth note (8 a bar, or 6 for a waltz). It writes the other voices from the chord:

    bass   the tune's 'style' (walk, stride, gallop, tremolo, lament, waltz)
           decides the pattern (voice 3, the Z "bass" instrument)
    comp   a chord-tone pattern (voice 2); see patterns() for each style
    drums  strong on 1 and 3, tap on 2 and 4, a roll into each section end

so a variation is a new list of bars, not three hand-aligned columns.

Melody tokens: a note (`D5`, `Bb4`, `F#5`), `S` to sustain, `-` for rest.
Flats are spelled here for readability and converted to CVBasic's sharps.

CVBasic's MUSIC range is C2..B6 plus C7. The Z instrument sounds TWO OCTAVES
DOWN, and the SN76489's lowest pitch is ~109 Hz (divisor 1023), i.e. A2 -- so
bass roots are written in A4..G#5 (sounding A2..G#3) or they go silent.
"""
import os
import sys

NOTES = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']

# chord quality -> (third, fifth, colour tone for the second stab), semitones
QUALITIES = {
    '':     (4, 7, 9),    # plain major comps with the 6th: period-correct
    'm':    (3, 7, 10),
    '7':    (4, 7, 10),
    'm7':   (3, 7, 10),
    'm7b5': (3, 6, 10),
    'dim':  (3, 6, 9),     # a diminished SEVENTH: the silent-film villain chord
    '6':    (4, 7, 9),
}


def pitch(tok):
    """'Bb4' / 'F#5' / 'D5' -> MIDI-style number (C4 = 48 here, any origin)."""
    n = NOTES[tok[0]]
    i = 1
    if tok[i] in '#b':
        n += 1 if tok[i] == '#' else -1
        i += 1
    octave = int(tok[i:])
    return octave * 12 + n


def name(p):
    octave, n = divmod(p, 12)
    s = NAMES[n]
    # CVBasic wants letter, octave, then '#'
    out = s[0] + str(octave) + s[1:]
    if not (2 * 12 <= p <= 7 * 12):
        sys.exit('gentunes: %s is outside MUSIC range C2..C7' % out)
    return out


def chord(sym):
    root = sym[0]
    i = 1
    if i < len(sym) and sym[i] in '#b':
        root += sym[i]
        i += 1
    q = sym[i:]
    if q not in QUALITIES:
        sys.exit('gentunes: unknown chord quality %r in %r' % (q, sym))
    r = NOTES[root[0]] + (1 if root[1:] == '#' else -1 if root[1:] == 'b' else 0)
    return r % 12, QUALITIES[q]


BASS_LO = pitch('A4')     # sounds A2, the chip's floor with the Z drop


def bass_root(pc):
    p = 4 * 12 + pc
    while p < BASS_LO:
        p += 12
    while p >= BASS_LO + 12:
        p -= 12
    return p


def comp_note(pc, iv):
    """A chord tone in the D4..C#5 window, under the melody."""
    p = 4 * 12 + (pc + iv) % 12
    if p < pitch('D4'):
        p += 12
    return p


def patterns(style, meter, bi, pc, q, bars, bass_lo):
    """Bass and comp rows for one bar, from the chord and the tune's style.

    walk     two-beat walk: root, third, fifth, half step into the next root
    stride   ragtime oom-pah: bass on 1 and 3, chord tone on 2 and 4
    gallop   the chase "hurry": bass pumping root/fifth, comp on every off-beat
    tremolo  the villain: bass held, comp shaking between two chord tones
    lament   held half-note chords under a slow tune
    tango    habanera bass in 3+3+2, chord stabs between
    pizz     the tiptoe: stride's pattern plucked short, every note one row
    waltz    3/4 (meter 6): bass on 1 (root, fifth on alternate bars), chord on 2 and 3
    """
    third, fifth, colour = q
    root = bass_root(pc)
    c1 = comp_note(pc, third)
    c2 = comp_note(pc, colour)
    if style == 'walk':
        nroot = bass_root(chord(bars[(bi + 1) % len(bars)][0])[0])
        approach = nroot - 1 if nroot - 1 >= bass_lo else nroot + 1
        bass = [root, 'S', root + third, 'S', root + fifth, 'S', approach, 'S']
        comp = ['-', c1, 'S', '-', '-', c2, 'S', '-']
    elif style == 'stride':
        bass = [root, 'S', '-', '-', root + fifth, 'S', '-', '-']
        comp = ['-', '-', c1, 'S', '-', '-', c2, 'S']
    elif style == 'gallop':
        bass = [root, '-', root + fifth, '-', root, '-', root + fifth, '-']
        comp = ['-', c1, '-', c1, '-', c2, '-', c2]
    elif style == 'tremolo':
        bass = [root] + ['S'] * 7
        comp = [c1, c2] * 4
    elif style == 'lament':
        bass = [root, 'S', 'S', 'S', root + fifth, 'S', 'S', 'S']
        comp = [c1, 'S', 'S', 'S', c2, 'S', 'S', 'S']
    elif style == 'tango':
        bass = [root, 'S', 'S', root + fifth, 'S', 'S', root, 'S']
        comp = ['-', c1, '-', '-', c2, '-', '-', c1]
    elif style == 'pizz':
        bass = [root, '-', '-', '-', root + fifth, '-', '-', '-']
        comp = ['-', '-', c1, '-', '-', '-', c2, '-']
    elif style == 'waltz':
        b = root + fifth if bi % 2 else root
        bass = [b, 'S', '-', '-', '-', '-']
        comp = ['-', '-', c1, 'S', c2, 'S']
    else:
        sys.exit('gentunes: unknown style %r' % style)
    if len(bass) != meter:
        sys.exit('gentunes: style %s is %d rows a bar, tune says %d'
                 % (style, len(bass), meter))
    return bass, comp


def render(tune):
    bars = tune['bars']
    meter = tune.get('meter', 8)
    style = tune.get('style', 'walk')
    drums_on = tune.get('drums', True)
    rows = []
    roll = set(tune.get('rolls', ()))
    for bi, (sym, mel) in enumerate(bars):
        toks = mel.split()
        if len(toks) != meter:
            sys.exit('gentunes: %s bar %d has %d tokens, not %d'
                     % (tune['label'], bi + 1, len(toks), meter))
        pc, q = chord(sym)
        bass, comp = patterns(style, meter, bi, pc, q, bars, BASS_LO)
        if not drums_on:
            drums = ['-'] * meter
        elif bi in roll:
            drums = ['M1', '-', 'M2', '-', 'M3', 'M3', 'M3', 'M3']
        else:
            drums = ['M1', '-', 'M2', '-', 'M1', '-', 'M2', '-']
        for r in range(meter):
            m = toks[r]
            if m not in ('S', '-'):
                m = pitch(m)
            rows.append([m, comp[r], bass[r], drums[r]])

    first = [True, True, True]
    inst = tune['instruments']
    out = []
    for row in rows:
        cells = []
        for v in range(3):
            x = row[v]
            if isinstance(x, int):
                s = name(x)
                if first[v]:
                    s += inst[v]
                    first[v] = False
                cells.append(s)
            else:
                cells.append(x)
        cells.append(row[3])
        out.append('\tMUSIC ' + ','.join(cells))
    return out


# ---------------------------------------------------------------------------
# THE TUNES
# ---------------------------------------------------------------------------
# RITZ -- an ORIGINAL tune in the manner of a 1929 Broadway strut: a minor
# verse over a bass that walks down by half steps, a hook in 3+3+2 eighths
# (the accent lands against the beat twice in every bar), a climbing
# syncopated break, and a brighter middle in the relative major. It borrows
# the STYLE of that era's novelty numbers, not any one song's melody.
RITZ = {
    'label': 'tune_ritz',
    'ticks': 9,                   # per eighth note; ~150 bpm swing-era strut
    'instruments': ('W', 'X', 'Z'),
    'rolls': (7, 15, 23, 39),
    'bars': [
        # --- A: the strut, G minor, bass sliding down by half steps
        ('Gm',    'D5 S  S  Bb4 S  S  G4  S'),
        ('D7',    'A4 S  S  C5  S  S  D5  S'),
        ('Gm7',   'D5 S  C5 S   Bb4 S A4  S'),
        ('Em7b5', 'G4 S  S  S   -  -  -   -'),
        ('Eb',    'Eb5 S S  D5  S  S  C5  S'),
        ('D7',    'F#4 S A4 S   C5 S  Eb5 S'),
        ('Gm',    'D5 S  S  Bb4 S  S  G4  S'),
        ('D7',    'A4 S  F#4 S  G4 S  S   -'),
        # --- A': the break, climbing in 3+3+2 against the beat
        ('Cm',    'C5 S  S  Eb5 S  S  G5  S'),
        ('Cm',    'S  F5 S  Eb5 S  D5 S   C5'),
        ('Gm',    'Bb4 S S  D5  S  S  G5  S'),
        ('A7',    'S  F#5 S E5  S  C#5 S  A4'),
        ('Eb',    'G5 S  S  S   F5 S  Eb5 S'),
        ('D7',    'D5 S  C5 S   A4 S  F#4 S'),
        ('Gm',    'G4 S  -  Bb4 -  D5 -   G5'),
        ('Gm',    'S  S  S  S   -  -  -   -'),
        # --- B: the middle, B-flat major, swinging up the arpeggio
        ('Bb',    'F5 S  D5 S   Bb4 S D5  F5'),
        ('Gm',    'S  S  G5 S   F5 S  D5  S'),
        ('Cm7',   'Eb5 S C5 S   G4 S  C5  Eb5'),
        ('F7',    'S  S  F5 S   Eb5 S A4  S'),
        ('Bb',    'D5 S  S  F5  S  S  Bb5 S'),
        ('Eb',    'S  G5 S  Eb5 S  Bb4 S  G4'),
        ('Am7b5', 'C5 S  A4 S   F#4 S A4  C5'),
        ('D7',    'S  S  S  S   D5 -  -   -'),
        # --- A: the strut again
        ('Gm',    'D5 S  S  Bb4 S  S  G4  S'),
        ('D7',    'A4 S  S  C5  S  S  D5  S'),
        ('Gm7',   'D5 S  C5 S   Bb4 S A4  S'),
        ('Em7b5', 'G4 S  S  S   -  -  -   -'),
        ('Eb',    'Eb5 S S  D5  S  S  C5  S'),
        ('D7',    'F#4 S A4 S   C5 S  Eb5 S'),
        ('Gm',    'D5 S  S  Bb4 S  S  G4  S'),
        ('D7',    'A4 S  F#4 S  G4 S  S   -'),
        # --- tag: the break once more, ending up top with a stinger
        ('Cm',    'C5 S  S  Eb5 S  S  G5  S'),
        ('Cm',    'S  F5 S  Eb5 S  D5 S   C5'),
        ('Gm',    'Bb4 S S  D5  S  S  G5  S'),
        ('A7',    'S  F#5 S E5  S  C#5 S  A4'),
        ('Eb',    'G5 S  S  S   F5 S  Eb5 S'),
        ('D7',    'D5 S  C5 S   A4 S  F#4 S'),
        ('Gm',    'G5 -  D5 -   Bb4 - G4  -'),
        ('Gm',    'G4 S  S  S   S  S  -   -'),
    ],
}

# ---------------------------------------------------------------------------
# SILENT-FILM CUES. A cinema pianist in the 1910s-20s worked from a small
# library of MOODS -- a hurry for chases, a misterioso for the villain, a
# waltz for the lovers, a rag for the comedy, a lament for the sad scene --
# and switched between them as the picture changed. These are ORIGINAL cues
# in each of those stock styles, played as solo piano (no drums): what a
# Keystone Kops reel would actually have had under it.
# ---------------------------------------------------------------------------

# CHASE -- the "hurry". E minor, running eighths over a pumping bass,
# chromatic neighbour notes for panic, a climbing second half in the
# relative major's orbit. The one cue that keeps a light snare, because the
# chase is the game's own scene.
CHASE = {
    'label': 'tune_chase',
    'ticks': 6,
    'style': 'gallop',
    'instruments': ('W', 'W', 'Z'),
    'rolls': (7, 15),
    'bars': [
        ('Em', 'E5 D#5 E5 F#5 G5 F#5 G5 A5'),
        ('B7', 'B5 A5 G5 F#5 D#5 E5 F#5 D#5'),
        ('Em', 'E5 D#5 E5 F#5 G5 F#5 G5 A5'),
        ('B7', 'B5 S  F#5 S  D#5 S  B4 S'),
        ('Am', 'C5 B4 C5 D5 E5 D#5 E5 F#5'),
        ('Em', 'G5 F#5 E5 D5 B4 C5 B4 G4'),
        ('B7', 'A4 B4 D#5 F#5 A5 S F#5 D#5'),
        ('Em', 'E5 S  B4 S  E4 S  -  -'),
        ('C',  'G4 C5 E5 G5 E5 C5 G4 C5'),
        ('G',  'B4 D5 G5 B5 G5 D5 B4 D5'),
        ('Am', 'C5 E5 A5 C6 B5 A5 G5 F#5'),
        ('B7', 'D#5 F#5 A5 B5 A5 F#5 D#5 B4'),
        ('Em', 'E5 G5 B5 G5 E5 G5 B5 G5'),
        ('Am', 'A5 C6 A5 E5 C5 E5 A5 E5'),
        ('B7', 'F#5 A5 B5 A5 F#5 D#5 B4 D#5'),
        ('Em', 'E5 S  S  S  E4 S  -  -'),
    ],
}

# VILLAIN -- the misterioso. D minor, a slow creeping line over a held bass
# and a left-hand TREMOLO between two chord tones, diminished sevenths at
# the cadences, then a staccato tiptoe as he sneaks up.
VILLAIN = {
    'label': 'tune_villain',
    'ticks': 7,
    'style': 'tremolo',
    'drums': False,
    'instruments': ('W', 'W', 'Z'),
    'bars': [
        ('Dm',   'A4 S  S  S  S  S  Bb4 A4'),
        ('Dm',   'G#4 S S  S  A4 S  S  S'),
        ('Ddim', 'D5 S  S  C5 S  S  B4 S'),
        ('A7',   'C#5 S S  S  -  -  -  -'),
        ('Gm',   'Bb4 S S  S  S  S  C5 Bb4'),
        ('Gm',   'A4 S  S  S  Bb4 S S  S'),
        ('C#dim','E5 S  S  D5 S  S  C#5 S'),
        ('Dm',   'D5 S  S  S  -  -  -  -'),
        ('Dm',   'D4 -  F4 -  A4 -  D5 -'),
        ('C#dim','C#5 - A#4 - G4 -  E4 -'),
        ('Dm',   'F4 -  A4 -  D5 -  F5 -'),
        ('A7',   'E5 -  C#5 - A4 -  G4 -'),
        ('Bb',   'F4 -  Bb4 - D5 -  F5 -'),
        ('Edim', 'G5 -  E5 -  C#5 - A#4 -'),
        ('A7',   'A4 S  C#5 S E5 S  G5 S'),
        ('Dm',   'D5 S  S  S  S  S  -  -'),
    ],
}

# SWEETHEART -- the love-scene waltz. F major in 3/4 (six eighths a bar),
# a long-breathed tune rising to its high point in bar 12, bass on the
# downbeat and the chord on beats two and three.
SWEETHEART = {
    'label': 'tune_waltz',
    'ticks': 8,
    'meter': 6,
    'style': 'waltz',
    'drums': False,
    'instruments': ('W', 'W', 'Z'),
    'bars': [
        ('F',   'A4 S  S  S  C5 S'),
        ('F',   'F5 S  S  S  E5 S'),
        ('Gm7', 'D5 S  S  S  Bb4 S'),
        ('C7',  'G4 S  S  S  S  S'),
        ('C7',  'Bb4 S S  S  E5 S'),
        ('C7',  'G5 S  S  S  F5 S'),
        ('F',   'E5 S  D5 S  C5 S'),
        ('F',   'A4 S  S  S  S  S'),
        ('Dm',  'A4 S  S  S  D5 S'),
        ('Dm',  'F5 S  S  S  E5 S'),
        ('Bb',  'D5 S  S  S  F5 S'),
        ('Bb',  'Bb5 S S  S  A5 S'),
        ('F',   'A5 S  S  S  G5 S'),
        ('C7',  'F5 S  E5 S  D5 S'),
        ('C7',  'E5 S  G4 S  Bb4 S'),
        ('F',   'F5 S  S  S  -  -'),
    ],
}

# PRATFALL -- the comedy rag. C major stride: oom on 1 and 3, pah on 2 and
# 4, and a right hand that ties across the beat (short-long-short) the way
# ragtime does. A diminished passing chord in bar 10 for the wobble.
PRATFALL = {
    'label': 'tune_rag',
    'ticks': 8,
    'style': 'stride',
    'drums': False,
    'instruments': ('W', 'W', 'Z'),
    'bars': [
        ('C',    'G4 C5 S  E5 S  G5 E5 C5'),
        ('C',    'D5 E5 S  C5 S  -  G4 -'),
        ('G7',   'F4 B4 S  D5 S  G5 F5 D5'),
        ('G7',   'E5 F5 S  D5 S  -  B4 -'),
        ('C',    'C5 E5 S  G5 S  C6 S  A5'),
        ('F',    'S  A5 G5 F5 S  E5 F5 S'),
        ('C',    'G5 E5 S  C5 D5 E5 S  G5'),
        ('G7',   'S  F5 D5 B4 G4 -  -  -'),
        ('F',    'A4 C5 S  F5 S  A5 S  F5'),
        ('Fdim', 'S  G#5 S F5 D5 B4 G#4 -'),
        ('C',    'G4 C5 S  E5 S  G5 S  E5'),
        ('A7',   'S  C#5 E5 G5 S A5 S  -'),
        ('D7',   'F#5 A5 S F#5 D5 C5 S A4'),
        ('G7',   'B4 D5 S  F5 S  G5 S  F5'),
        ('C',    'E5 G5 C6 G5 E5 C5 G4 E4'),
        ('C',    'C5 S  G4 S  C5 S  -  -'),
    ],
}

# SORROW -- the lament, for the heroine alone in the snow. A minor, slow,
# held chords, sighing appoggiaturas that lean onto the chord tone.
SORROW = {
    'label': 'tune_sorrow',
    'ticks': 11,
    'style': 'lament',
    'drums': False,
    'instruments': ('W', 'W', 'Z'),
    'bars': [
        ('Am', 'E5 S  S  S  A5 S  G5 S'),
        ('Am', 'F5 S  E5 S  S  S  -  -'),
        ('Dm', 'F5 S  S  S  D5 S  E5 S'),
        ('E7', 'G#4 S S  S  -  -  -  -'),
        ('Am', 'C5 S  S  S  E5 S  A5 S'),
        ('F',  'C6 S  B5 S  A5 S  S  S'),
        ('E7', 'B5 S  G#5 S E5 S  D5 S'),
        ('Am', 'C5 S  S  S  -  -  -  -'),
        ('F',  'A5 S  S  S  C6 S  A5 S'),
        ('C',  'G5 S  S  S  E5 S  S  S'),
        ('Dm', 'F5 S  S  S  A5 S  F5 S'),
        ('E7', 'E5 S  S  S  D5 S  B4 S'),
        ('Am', 'C5 S  E5 S  A5 S  C6 S'),
        ('Dm', 'B5 S  A5 S  F5 S  D5 S'),
        ('E7', 'E5 S  S  S  G#4 S B4 S'),
        ('Am', 'A4 S  S  S  S  S  -  -'),
    ],
}

# ---------------------------------------------------------------------------
# SECOND BATCH: more of the silent-film pianist's library. All ORIGINAL.
# The last two are EVENT cues (loop False): they play once and stop, which
# is the shape a game needs for a capture or a lost life.
# ---------------------------------------------------------------------------

# MARCH -- the Kops set off. B-flat major, oom-pah with a snare, a
# bugle-call opening arpeggio and a chromatic diminished passing chord.
MARCH = {
    'label': 'tune_march',
    'ticks': 7,
    'style': 'stride',
    'instruments': ('W', 'W', 'Z'),
    'rolls': (7, 15),
    'bars': [
        ('Bb',   'F4 S  Bb4 S  D5 S  F5 S'),
        ('Bb',   'D5 S  S  Bb4 F5 S  S  -'),
        ('F7',   'Eb5 S C5 S   A4 S  F4 S'),
        ('Bb',   'D5 S  Bb4 S  F4 S  -  -'),
        ('Eb',   'G5 S  S  G5  G5 S  F5 Eb5'),
        ('Bb',   'D5 S  S  D5  D5 S  C5 Bb4'),
        ('C7',   'C5 S  E5 S   G5 S  Bb5 S'),
        ('F7',   'A5 S  F5 S   C5 S  -  -'),
        ('Bb',   'F4 S  Bb4 S  D5 S  F5 S'),
        ('Bb',   'Bb5 S S  A5  G5 S  F5 S'),
        ('Eb',   'G5 S  Eb5 S  Bb4 S G5 S'),
        ('Edim', 'G5 S  E5 S   C#5 S Bb4 S'),
        ('Bb',   'F5 S  D5 S   Bb4 S D5 S'),
        ('F7',   'C5 S  Eb5 S  A5 S  C6 S'),
        ('Bb',   'Bb5 S F5 S   D5 S  F5 S'),
        ('Bb',   'Bb5 S Bb4 S  S  -  -  -'),
    ],
}

# TIPTOE -- somebody sneaking about. C minor, every note plucked and short,
# two careful steps then a pause, a chromatic creep up on the second phrase.
TIPTOE = {
    'label': 'tune_tiptoe',
    'ticks': 8,
    'style': 'pizz',
    'drums': False,
    'instruments': ('W', 'W', 'Z'),
    'bars': [
        ('Cm',   'C5 -  -  D5  Eb5 - -  -'),
        ('Cm',   'G4 -  -  Ab4 G4 -  -  -'),
        ('Fm',   'F4 -  -  Ab4 C5 -  -  F5'),
        ('G7',   'D5 -  B4 -   G4 -  -  -'),
        ('Cm',   'C5 -  -  D5  Eb5 - -  -'),
        ('Cm',   'G5 -  -  Ab5 G5 -  -  -'),
        ('Ddim', 'F5 -  D5 -   B4 -  G#4 -'),
        ('G7',   'G4 -  -  -   -  -  -  -'),
        ('Ab',   'C5 -  Eb5 -  Ab5 - -  G5'),
        ('Fm',   '-  F5 -  Eb5 -  D5 -  C5'),
        ('Cm',   'Eb5 - G5 -   C6 -  -  Bb5'),
        ('Ab',   '-  Ab5 - G5  -  F5 -  Eb5'),
        ('Fm',   'D5 -  F5 -   Ab5 - -  -'),
        ('G7',   'G5 -  F5 -   D5 -  B4 -'),
        ('Cm',   'C5 -  Eb5 -  G4 -  -  -'),
        ('Cm',   'G4 -  -  B4  C5 -  -  -'),
    ],
}

# AGITATO -- panic: everything going wrong at once. G minor, fast, the
# left hand shaking under scale runs that turn back on themselves, then
# leaping arpeggios.
AGITATO = {
    'label': 'tune_agitato',
    'ticks': 5,
    'style': 'tremolo',
    'drums': False,
    'instruments': ('W', 'W', 'Z'),
    'bars': [
        ('Gm',    'G4 A4 Bb4 C5 D5 C5 Bb4 A4'),
        ('D7',    'F#4 A4 C5 Eb5 D5 C5 A4 F#4'),
        ('Gm',    'Bb4 C5 D5 Eb5 F5 Eb5 D5 C5'),
        ('F#dim', 'A4 C5 Eb5 F#5 A5 F#5 Eb5 C5'),
        ('Cm',    'C5 D5 Eb5 F5 G5 F5 Eb5 D5'),
        ('Gm',    'D5 Eb5 F5 G5 A5 G5 F5 Eb5'),
        ('A7',    'E5 G5 A5 C#6 A5 G5 E5 C#5'),
        ('D7',    'D5 S  F#5 S  A5 S  C6 S'),
        ('Gm',    'G5 S  D5 S   Bb4 S G5 S'),
        ('Eb',    'G5 S  Eb5 S  Bb4 S G5 S'),
        ('Cm',    'Eb5 S C5 S   G4 S  Eb5 S'),
        ('D7',    'D5 S  A4 S   F#4 S D5 S'),
        ('Gm',    'Bb5 A5 G5 F#5 G5 A5 Bb5 C6'),
        ('D7',    'C6 Bb5 A5 G5 F#5 G5 A5 F#5'),
        ('D7',    'D5 F#5 A5 C6 D6 C6 A5 F#5'),
        ('Gm',    'G5 S  D5 S   G4 S  -  -'),
    ],
}

# TWO-STEP -- a jaunty dance for a happy moment. G major, oom-pah with a
# snare, a tune that bounces up the chord and skips back down.
TWOSTEP = {
    'label': 'tune_twostep',
    'ticks': 7,
    'style': 'stride',
    'instruments': ('W', 'W', 'Z'),
    'rolls': (15,),
    'bars': [
        ('G',  'B4 S  D5 S   G5 S  D5 S'),
        ('G',  'E5 D5 S  B4  S  -  G4 -'),
        ('D7', 'A4 S  C5 S   F#5 S E5 S'),
        ('D7', 'D5 C5 S  A4  S  -  F#4 -'),
        ('G',  'G4 B4 D5 G5  S  F#5 G5 S'),
        ('C',  'E5 S  S  C5  E5 S  G5 S'),
        ('A7', 'G5 F#5 E5 C#5 S A4 S  -'),
        ('D7', 'F#5 S E5 D5  S  -  -  -'),
        ('G',  'B4 S  D5 S   G5 S  D5 S'),
        ('E7', 'G#5 S E5 S   B4 S  D5 S'),
        ('Am', 'C5 S  E5 S   A5 S  S  G5'),
        ('D7', 'F#5 S A5 S   C6 S  A5 S'),
        ('G',  'B5 S  G5 S   D5 S  B4 S'),
        ('C',  'C5 E5 G5 S   E5 C5 S  -'),
        ('D7', 'D5 S  F#5 S  A5 S  C6 S'),
        ('G',  'B5 S  G5 S   G4 S  -  -'),
    ],
}

# DIRGE -- a life lost. EVENT cue: eight slow bars of C minor that sink
# to the tonic and stop.
DIRGE = {
    'label': 'tune_dirge',
    'ticks': 12,
    'style': 'lament',
    'drums': False,
    'loop': False,
    'instruments': ('W', 'W', 'Z'),
    'bars': [
        ('Cm', 'G5 S  S  S  Eb5 S S  S'),
        ('Ab', 'C5 S  S  S  Eb5 S D5 S'),
        ('Fm', 'C5 S  S  S  Ab4 S S  S'),
        ('G7', 'B4 S  S  S  D5 S  S  S'),
        ('Cm', 'Eb5 S D5 S  C5 S  G4 S'),
        ('Fm', 'Ab4 S S  S  F4 S  S  S'),
        ('G7', 'G4 S  S  S  B4 S  S  S'),
        ('Cm', 'C5 S  S  S  S  S  -  -'),
    ],
}

# FANFARE -- the crook is caught. EVENT cue: a bugle-call pickup, a climb
# through D major and a held top note under a drum roll.
FANFARE = {
    'label': 'tune_fanfare',
    'ticks': 6,
    'style': 'lament',
    'loop': False,
    'instruments': ('W', 'W', 'Z'),
    'rolls': (4,),
    'bars': [
        ('D',  'A4 -  A4 -   D5 S  S  A4'),
        ('D',  'D5 -  F#5 S  S  D5 F#5 -'),
        ('G',  'G5 -  G5 -   B5 S  S  G5'),
        ('A7', 'A5 S  S  S   C#6 S S  S'),
        ('D',  'D6 S  S  S   S  S  S  S'),
        ('D',  'S  S  S  S   -  -  -  -'),
    ],
}

# ---------------------------------------------------------------------------
# THIRD BATCH: filling the cart. All ORIGINAL. Written compactly with tune();
# every tune carries its own menu line ('menu'), 21 characters at most.
# ---------------------------------------------------------------------------


def tune(label, menu, ticks, style, bars, drums=False, loop=True, rolls=(),
         meter=8):
    return {'label': label, 'menu': menu, 'ticks': ticks, 'style': style,
            'drums': drums, 'loop': loop, 'rolls': rolls, 'meter': meter,
            'instruments': ('W', 'W', 'Z'), 'bars': bars}


BATCH3 = [
    # a strutting dance contest: F major, syncopated, drums
    tune('tune_cakewalk', 'CAKEWALK STRUTTING', 7, 'stride', [
        ('F',  'A4 C5 S  F5 S  A5 S  F5'),
        ('F',  'G5 F5 S  D5 S  C5 S  -'),
        ('C7', 'G4 Bb4 S C5 S  E5 S  G5'),
        ('C7', 'Bb5 A5 S G5 S  E5 S  -'),
        ('F',  'F5 A5 S  C6 S  A5 F5 S'),
        ('Bb', 'D5 F5 S  Bb5 S F5 D5 S'),
        ('G7', 'B4 D5 F5 G5 S  F5 D5 B4'),
        ('C7', 'C5 S  E5 S  G5 S  -  -'),
        ('F',  'A4 C5 S  F5 S  A5 S  F5'),
        ('D7', 'F#5 A5 S C6 S  A5 F#5 S'),
        ('Gm', 'G5 Bb5 S G5 S  D5 S  Bb4'),
        ('C7', 'C5 E5 S  G5 S  Bb5 S G5'),
        ('F',  'A5 S  F5 S  C5 S  A4 S'),
        ('Bb', 'Bb4 D5 F5 Bb5 S F5 D5 S'),
        ('C7', 'C6 Bb5 G5 E5 C5 E5 G5 E5'),
        ('F',  'F5 S  C5 S  F4 S  -  -'),
    ], drums=True, rolls=(7, 15)),

    # wind and rain: E minor arpeggios over a shaking left hand
    tune('tune_storm', 'STORM    WIND + RAIN', 5, 'tremolo', [
        ('Em',    'E4 G4 B4 E5 G5 E5 B4 G4'),
        ('Em',    'E4 G4 B4 E5 G5 B5 G5 E5'),
        ('Am',    'A4 C5 E5 A5 C6 A5 E5 C5'),
        ('B7',    'B4 D#5 F#5 A5 B5 A5 F#5 D#5'),
        ('Em',    'G5 F#5 E5 D#5 E5 F#5 G5 A5'),
        ('C',     'G5 E5 C5 E5 G5 C6 G5 E5'),
        ('F#dim', 'A5 F#5 Eb5 C5 Eb5 F#5 A5 C6'),
        ('B7',    'B5 S  F#5 S  D#5 S B4 S'),
        ('Em',    'E5 S  S  S   G5 S  S  S'),
        ('Am',    'A5 S  S  S   C6 S  S  S'),
        ('Em',    'B5 S  S  G5  E5 S  S  B4'),
        ('B7',    'D#5 S S  F#5 A5 S  S  F#5'),
        ('C',     'E5 G5 C6 G5 E5 G5 C6 G5'),
        ('Am',    'C5 E5 A5 E5 C5 E5 A5 E5'),
        ('B7',    'B4 D#5 F#5 A5 B5 A5 F#5 D#5'),
        ('Em',    'E5 S  B4 S  E4 S  -  -'),
    ]),

    # an empty house at night: slow B minor
    tune('tune_midnight', 'MIDNIGHT EMPTY HOUSE', 10, 'lament', [
        ('Bm',    'F#5 S S  S  D5 S  B4 S'),
        ('Bm',    'C#5 S D5 S  S  S  -  -'),
        ('Em',    'G5 S  S  S  E5 S  B4 S'),
        ('F#7',   'A#4 S S  S  C#5 S S  S'),
        ('Bm',    'D5 S  S  S  F#5 S B5 S'),
        ('G',     'B5 S  A5 S  G5 S  S  S'),
        ('C#dim', 'G5 S  E5 S  C#5 S A#4 S'),
        ('F#7',   'F#5 S S  S  -  -  -  -'),
        ('G',     'D5 S  S  S  G5 S  B5 S'),
        ('D',     'A5 S  S  S  F#5 S D5 S'),
        ('Em',    'E5 S  G5 S  B5 S  G5 S'),
        ('F#7',   'F#5 S S  S  E5 S  C#5 S'),
        ('Bm',    'D5 S  F#5 S B5 S  S  S'),
        ('Em',    'G5 S  F#5 S E5 S  D5 S'),
        ('F#7',   'C#5 S S  S  A#4 S C#5 S'),
        ('Bm',    'B4 S  S  S  S  S  -  -'),
    ]),

    # custard pies: a fast comic galop in C
    tune('tune_slapstick', 'SLAPSTICK PIE FIGHT', 5, 'gallop', [
        ('C',  'G5 S  E5 S  G5 S  E5 S'),
        ('C',  'G5 A5 G5 F5 E5 D5 C5 S'),
        ('G7', 'F5 S  D5 S  F5 S  D5 S'),
        ('G7', 'F5 G5 F5 E5 D5 C5 B4 S'),
        ('C',  'C5 E5 G5 C6 S  G5 E5 C5'),
        ('F',  'F5 A5 C6 A5 F5 C5 A4 C5'),
        ('G7', 'D5 F5 G5 B5 S  G5 F5 D5'),
        ('C',  'C5 S  G4 S  C5 S  -  -'),
        ('A7', 'C#5 S E5 S  A5 S  E5 S'),
        ('Dm', 'F5 E5 D5 E5 F5 A5 S  -'),
        ('G7', 'B4 S  D5 S  G5 S  D5 S'),
        ('C',  'E5 D5 C5 D5 E5 G5 S  -'),
        ('F',  'A5 S  F5 S  C5 S  F5 S'),
        ('C',  'G5 S  E5 S  C5 S  E5 S'),
        ('G7', 'D5 E5 F5 G5 A5 B5 C6 D6'),
        ('C',  'C6 S  G5 S  C5 S  -  -'),
    ], drums=True, rolls=(7, 15)),

    # the vamp and the cad: D minor, bass in 3+3+2
    tune('tune_tango', 'TANGO    THE VAMP', 8, 'tango', [
        ('Dm', 'D5 S  S  A4  S  S  D5 E5'),
        ('Dm', 'F5 S  S  E5  D5 S  -  -'),
        ('A7', 'C#5 S S  E5  S  S  G5 F5'),
        ('A7', 'E5 S  S  S   -  -  -  -'),
        ('Gm', 'G5 S  S  D5  S  S  G5 A5'),
        ('Dm', 'Bb5 S S  A5  F5 S  -  -'),
        ('E7', 'G#5 S S  E5  S  S  D5 B4'),
        ('A7', 'C#5 S S  S   A4 S  -  -'),
        ('Dm', 'D5 S  F5 S   A5 S  S  S'),
        ('Bb', 'Bb5 S A5 S   G5 S  F5 S'),
        ('Gm', 'G5 S  Bb5 S  D6 S  S  S'),
        ('A7', 'C#6 S Bb5 S  A5 S  G5 S'),
        ('Dm', 'F5 S  S  A5  S  S  D6 S'),
        ('Gm', 'D6 S  S  Bb5 S  S  G5 S'),
        ('A7', 'E5 S  G5 S   Bb5 S C#6 S'),
        ('Dm', 'D6 S  S  S   D5 S  -  -'),
    ]),

    # a barn dance: G major fiddle figures
    tune('tune_hoedown', 'HOEDOWN  BARN DANCE', 5, 'gallop', [
        ('G',  'G5 G5 B5 G5 D5 G5 B5 G5'),
        ('D7', 'A5 F#5 D5 F#5 A5 C6 A5 F#5'),
        ('G',  'G5 G5 B5 G5 D5 G5 B5 D6'),
        ('D7', 'C6 A5 F#5 D5 A5 S  -  -'),
        ('C',  'E5 G5 C6 G5 E5 G5 C6 G5'),
        ('G',  'D5 G5 B5 G5 D5 G5 B5 G5'),
        ('A7', 'E5 A5 C#6 A5 E5 A5 C#6 A5'),
        ('D7', 'D6 C6 A5 F#5 D5 S -  -'),
        ('G',  'B4 D5 G5 D5 B4 D5 G5 D5'),
        ('C',  'C5 E5 G5 E5 C5 E5 G5 E5'),
        ('G',  'D5 G5 B5 G5 D5 G5 B5 G5'),
        ('D7', 'C5 D5 F#5 A5 C6 A5 F#5 D5'),
        ('G',  'G5 S  B5 S  D6 S  B5 S'),
        ('C',  'C6 S  G5 S  E5 S  C5 S'),
        ('D7', 'D5 F#5 A5 C6 A5 F#5 D5 F#5'),
        ('G',  'G5 S  D5 S  G4 S  -  -'),
    ], drums=True, rolls=(7, 15)),

    # the baby asleep: slow C major waltz
    tune('tune_lullaby', 'LULLABY  CRADLE', 10, 'waltz', [
        ('C',  'E5 S  S  S  G5 S'),
        ('C',  'E5 S  S  S  C5 S'),
        ('F',  'F5 S  S  S  A5 S'),
        ('C',  'G5 S  S  S  S  S'),
        ('Dm', 'F5 S  S  S  D5 S'),
        ('G7', 'B4 S  S  S  D5 S'),
        ('C',  'C5 S  E5 S  G5 S'),
        ('G7', 'D5 S  S  S  S  S'),
        ('C',  'E5 S  S  S  G5 S'),
        ('Am', 'C6 S  S  S  A5 S'),
        ('F',  'A5 S  S  S  F5 S'),
        ('C',  'G5 S  S  S  E5 S'),
        ('Dm', 'F5 S  S  S  A4 S'),
        ('G7', 'B4 S  S  S  D5 S'),
        ('G7', 'F5 S  S  S  B4 S'),
        ('C',  'C5 S  S  S  -  -'),
    ], meter=6),

    # a boat on the water: A major barcarolle rocking in 6/8
    tune('tune_seaside', 'SEASIDE  ROWBOAT', 8, 'waltz', [
        ('A',   'C#5 S E5 S  A5 S'),
        ('A',   'G#5 S S  S  E5 S'),
        ('D',   'F#5 S A5 S  D6 S'),
        ('A',   'C#6 S S  S  S  S'),
        ('E7',  'B5 S  G#5 S E5 S'),
        ('E7',  'D5 S  E5 S  G#5 S'),
        ('A',   'A5 S  E5 S  C#5 S'),
        ('E7',  'B4 S  S  S  S  S'),
        ('F#m', 'A5 S  S  S  F#5 S'),
        ('D',   'F#5 S A5 S  D6 S'),
        ('A',   'C#6 S S  S  A5 S'),
        ('E7',  'B5 S  G#5 S E5 S'),
        ('A',   'E5 S  A5 S  C#6 S'),
        ('D',   'D6 S  C#6 S B5 S'),
        ('E7',  'B5 S  S  S  G#5 S'),
        ('A',   'A5 S  S  S  -  -'),
    ], meter=6),

    # the safe-crackers at work: A minor, plucked, careful
    tune('tune_heist', 'HEIST    SAFECRACKER', 7, 'pizz', [
        ('Am', 'A4 -  C5 -  E5 -  -  -'),
        ('Am', 'D#5 - E5 -  -  -  A4 -'),
        ('Dm', 'D5 -  F5 -  A5 -  -  -'),
        ('E7', 'G#5 - E5 -  D5 -  B4 -'),
        ('Am', 'C5 -  -  -  E5 -  -  A5'),
        ('F',  '-  A5 -  F5 -  C5 -  A4'),
        ('E7', 'B4 -  D5 -  E5 -  G#5 -'),
        ('Am', 'A5 -  -  -  -  -  -  -'),
        ('F',  'F5 -  E5 -  F5 -  A5 -'),
        ('C',  'G5 -  F5 -  E5 -  C5 -'),
        ('Dm', 'D5 -  C#5 - D5 -  F5 -'),
        ('E7', 'E5 -  D5 -  B4 -  G#4 -'),
        ('Am', 'A4 -  -  C5 E5 -  -  A5'),
        ('Dm', 'F5 -  -  D5 A4 -  -  D5'),
        ('E7', 'B4 -  D5 -  G#5 - B5 -'),
        ('Am', 'A5 -  E5 -  A4 -  -  -'),
    ]),

    # the circus parade: E-flat major, brassy, drums
    tune('tune_bigtop', 'BIG TOP  CIRCUS', 6, 'stride', [
        ('Eb',  'Bb4 S Eb5 S  G5 S  Bb5 S'),
        ('Eb',  'G5 Ab5 G5 F5 Eb5 S Bb4 S'),
        ('Bb7', 'Ab4 S D5 S   F5 S  Ab5 S'),
        ('Bb7', 'F5 G5 F5 Eb5 D5 S  Bb4 S'),
        ('Eb',  'Eb5 S G5 S   Bb5 S G5 S'),
        ('Ab',  'C6 S  Ab5 S  Eb5 S C5 S'),
        ('F7',  'A4 C5 Eb5 F5 A5 F5 Eb5 C5'),
        ('Bb7', 'Bb4 S D5 S   F5 S  -  -'),
        ('Eb',  'Bb4 S Eb5 S  G5 S  Bb5 S'),
        ('C7',  'Bb5 A5 G5 E5 C5 S  G4 S'),
        ('Fm',  'Ab4 S C5 S   F5 S  Ab5 S'),
        ('Bb7', 'Ab5 G5 F5 D5 Bb4 S D5 S'),
        ('Eb',  'G5 S  Bb5 S  Eb6 S Bb5 S'),
        ('Ab',  'C6 S  Ab5 S  Eb5 S Ab5 S'),
        ('Bb7', 'F5 Ab5 G5 F5 D5 F5 Ab5 F5'),
        ('Eb',  'Eb5 S Bb4 S  Eb4 S -  -'),
    ], drums=True, rolls=(7, 15)),

    # a vehicle out of control: A minor, relentless
    tune('tune_runaway', 'RUNAWAY  NO BRAKES', 5, 'gallop', [
        ('Am', 'A4 B4 C5 D5 E5 D5 C5 B4'),
        ('Am', 'A4 C5 E5 A5 G#5 A5 E5 C5'),
        ('Dm', 'D5 E5 F5 G5 A5 G5 F5 E5'),
        ('E7', 'D5 E5 G#5 B5 D6 B5 G#5 E5'),
        ('Am', 'A5 G#5 A5 B5 C6 B5 A5 G5'),
        ('F',  'F5 E5 F5 G5 A5 G5 F5 E5'),
        ('E7', 'D5 C5 B4 C5 D5 E5 G#5 B5'),
        ('Am', 'A5 S  E5 S  A4 S  -  -'),
        ('C',  'E5 G5 C6 G5 E5 G5 C6 G5'),
        ('G',  'D5 G5 B5 G5 D5 G5 B5 G5'),
        ('F',  'C5 F5 A5 F5 C5 F5 A5 F5'),
        ('E7', 'B4 E5 G#5 E5 B4 E5 G#5 B5'),
        ('Am', 'C6 B5 A5 G#5 A5 E5 C5 A4'),
        ('Dm', 'D5 F5 A5 D6 C6 A5 F5 D5'),
        ('E7', 'E5 G#5 B5 D6 B5 G#5 E5 D5'),
        ('Am', 'C5 S  A4 S  A5 S  -  -'),
    ], drums=True, rolls=(7, 15)),

    # tea at the mansion: a genteel G major waltz
    tune('tune_parlor', 'PARLOR   HIGH SOCIETY', 7, 'waltz', [
        ('G',  'D5 S  G5 S  B5 S'),
        ('G',  'A5 S  G5 S  D5 S'),
        ('C',  'E5 S  G5 S  C6 S'),
        ('G',  'B5 S  S  S  S  S'),
        ('Am', 'C6 S  B5 S  A5 S'),
        ('D7', 'F#5 S A5 S  C6 S'),
        ('G',  'B5 S  A5 S  G5 S'),
        ('D7', 'A5 S  S  S  S  S'),
        ('G',  'D5 S  G5 S  B5 S'),
        ('E7', 'G#5 S B5 S  D6 S'),
        ('Am', 'C6 S  S  S  A5 S'),
        ('C',  'G5 S  E5 S  C5 S'),
        ('G',  'D5 S  G5 S  B5 S'),
        ('D7', 'A5 S  S  S  F#5 S'),
        ('D7', 'C5 S  E5 S  F#5 S'),
        ('G',  'G5 S  S  S  -  -'),
    ], meter=6),

    # a twelve-bar blues in B-flat, walking bass and brushes
    tune('tune_blues', 'BLUES    BACK ALLEY', 10, 'walk', [
        ('Bb7', 'F5 S  S  Db5 D5 S  Bb4 S'),
        ('Bb7', 'F4 S  G4 S   Bb4 S S  -'),
        ('Bb7', 'F5 S  S  Db5 D5 S  Bb4 S'),
        ('Bb7', 'Ab4 S Bb4 S  D5 S  F5 S'),
        ('Eb7', 'G5 S  S  Gb5 F5 S  Eb5 S'),
        ('Eb7', 'Db5 S Eb5 S  G5 S  S  -'),
        ('Bb7', 'F5 S  S  Db5 D5 S  Bb4 S'),
        ('Bb7', 'G4 S  Bb4 S  S  S  -  -'),
        ('F7',  'C5 S  Eb5 S  F5 S  A5 S'),
        ('Eb7', 'G5 S  Gb5 S  F5 S  Eb5 S'),
        ('Bb7', 'D5 S  Db5 S  Bb4 S F4 S'),
        ('F7',  'A4 S  C5 S   Eb5 S F5 S'),
    ], drums=True, rolls=(11,)),

    # something moves in the dark: slow F minor tremolo
    tune('tune_shadows', 'SHADOWS  WHO IS THERE', 9, 'tremolo', [
        ('Fm',   'C5 S  S  S  Db5 S C5 S'),
        ('Fm',   'Ab4 S S  S  F4 S  S  S'),
        ('Bbm',  'Db5 S S  S  F5 S  Db5 S'),
        ('C7',   'E4 S  S  S  G4 S  S  S'),
        ('Fm',   'F4 S  Ab4 S C5 S  F5 S'),
        ('Db',   'F5 S  Eb5 S Db5 S S  S'),
        ('Edim', 'Db5 S Bb4 S G4 S  E4 S'),
        ('C7',   'C5 S  S  S  -  -  -  -'),
        ('Fm',   'F5 S  S  S  Ab5 S S  S'),
        ('Bbm',  'Db6 S S  S  Bb5 S S  S'),
        ('Fm',   'C6 S  Ab5 S F5 S  C5 S'),
        ('C7',   'E5 S  G5 S  Bb5 S S  S'),
        ('Db',   'Ab5 S F5 S  Db5 S F5 S'),
        ('Bbm',  'Bb5 S F5 S  Db5 S Bb4 S'),
        ('C7',   'C5 S  E5 S  G5 S  Bb5 S'),
        ('Fm',   'F5 S  S  S  F4 S  -  -'),
    ]),

    # the hero wins: C major, broad, drums
    tune('tune_victory', 'VICTORY  THE HERO', 7, 'stride', [
        ('C',  'C5 S  E5 S  G5 S  C6 S'),
        ('C',  'S  S  G5 S  C6 S  S  -'),
        ('F',  'A5 S  S  F5 C6 S  A5 S'),
        ('C',  'G5 S  S  S  E5 S  -  -'),
        ('Dm', 'F5 S  S  F5 A5 S  F5 S'),
        ('G7', 'D5 S  S  D5 G5 S  F5 S'),
        ('C',  'E5 S  G5 S  C6 S  E6 S'),
        ('G7', 'D6 S  S  S  B5 S  -  -'),
        ('C',  'C5 S  E5 S  G5 S  C6 S'),
        ('A7', 'C#6 S S  A5 E5 S  C#5 S'),
        ('Dm', 'D5 S  F5 S  A5 S  D6 S'),
        ('F',  'C6 S  A5 S  F5 S  C5 S'),
        ('C',  'E5 S  G5 S  C6 S  S  S'),
        ('G7', 'B5 S  D6 S  F6 S  D6 S'),
        ('G7', 'B5 S  G5 S  F5 S  D5 S'),
        ('C',  'C6 S  G5 S  C5 S  -  -'),
    ], drums=True, rolls=(7, 15)),

    # a letter that brings bad news: E minor
    tune('tune_heartache', 'HEARTACHE BAD NEWS', 11, 'lament', [
        ('Em', 'B4 S  S  S  E5 S  G5 S'),
        ('Em', 'F#5 S S  S  E5 S  S  S'),
        ('Am', 'C6 S  S  S  B5 S  A5 S'),
        ('B7', 'D#5 S S  S  F#5 S S  S'),
        ('Em', 'G5 S  S  S  F#5 S E5 S'),
        ('C',  'E5 S  S  S  D5 S  C5 S'),
        ('B7', 'B4 S  S  S  A4 S  F#4 S'),
        ('Em', 'E4 S  S  S  -  -  -  -'),
        ('C',  'G5 S  S  S  E5 S  C5 S'),
        ('G',  'D5 S  S  S  B4 S  G4 S'),
        ('Am', 'A4 S  C5 S  E5 S  A5 S'),
        ('B7', 'B5 S  S  S  A5 S  F#5 S'),
        ('Em', 'G5 S  E5 S  B4 S  E5 S'),
        ('Am', 'C5 S  E5 S  A5 S  C6 S'),
        ('B7', 'B5 S  S  S  D#5 S F#5 S'),
        ('Em', 'E5 S  S  S  S  S  -  -'),
    ]),

    # traffic and crowds: a bustling F major walk
    tune('tune_street', 'STREET   RUSH HOUR', 7, 'walk', [
        ('F',   'C5 S  F5 S  A5 S  S  G5'),
        ('Dm',  'F5 S  S  D5 S  S  A4 S'),
        ('Gm7', 'Bb4 S D5 S  F5 S  S  E5'),
        ('C7',  'D5 S  S  C5 S  S  G4 S'),
        ('F',   'A4 C5 F5 A5 S  G5 F5 S'),
        ('Bb',  'D5 F5 Bb5 S A5 F5 D5 S'),
        ('G7',  'B4 D5 F5 S  E5 D5 B4 S'),
        ('C7',  'C5 S  S  S  -  -  -  -'),
        ('Am',  'E5 S  A5 S  C6 S  S  B5'),
        ('Dm',  'A5 S  S  F5 S  S  D5 S'),
        ('Gm7', 'Bb4 S D5 S  G5 S  S  F5'),
        ('C7',  'E5 S  S  C5 S  S  Bb4 S'),
        ('F',   'A4 S  C5 S  F5 S  A5 S'),
        ('Bb',  'Bb5 S A5 S  G5 S  F5 S'),
        ('C7',  'E5 S  G5 S  C6 S  Bb5 S'),
        ('F',   'A5 S  F5 S  F4 S  -  -'),
    ], drums=True, rolls=(7, 15)),

    # a quiet morning: gentle G major
    tune('tune_daybreak', 'DAYBREAK MORNING', 10, 'lament', [
        ('G',  'D5 S  S  S  G5 S  B5 S'),
        ('C',  'C6 S  S  S  B5 S  A5 S'),
        ('G',  'B5 S  S  S  G5 S  D5 S'),
        ('D7', 'A5 S  S  S  S  S  -  -'),
        ('Em', 'G5 S  S  S  B5 S  E5 S'),
        ('C',  'E5 S  G5 S  C6 S  S  S'),
        ('D7', 'A5 S  F#5 S D5 S  C5 S'),
        ('G',  'B4 S  S  S  -  -  -  -'),
        ('C',  'E5 S  S  S  G5 S  C6 S'),
        ('G',  'B5 S  S  S  D5 S  G5 S'),
        ('Am', 'A5 S  C6 S  E6 S  S  S'),
        ('D7', 'D6 S  C6 S  A5 S  F#5 S'),
        ('G',  'G5 S  B5 S  D6 S  S  S'),
        ('C',  'C6 S  B5 S  A5 S  G5 S'),
        ('D7', 'F#5 S A5 S  D5 S  F#5 S'),
        ('G',  'G5 S  S  S  S  S  -  -'),
    ]),

    # --- EVENT cues: play once, short, sized for the game itself
    tune('tune_extralife', 'EXTRA    BONUS LIFE', 5, 'lament', [
        ('C',  'C5 E5 G5 C6 E6 S  S  S'),
        ('G7', 'D6 S  B5 S  G5 S  S  S'),
        ('C',  'C6 S  S  S  -  -  -  -'),
    ], loop=False),

    tune('tune_ready', 'READY    ROUND START', 6, 'stride', [
        ('G',  'D5 -  D5 -  G5 S  S  -'),
        ('D7', 'F#5 - F#5 - A5 S  S  -'),
        ('G',  'B5 S  A5 S  G5 S  D5 S'),
        ('D7', 'A5 S  S  S  S  S  S  -'),
    ], drums=True, loop=False, rolls=(3,)),

    tune('tune_timeup', 'TIME UP  TOO LATE', 8, 'lament', [
        ('C',  'G5 S  S  S  F#5 S S  S'),
        ('Fm', 'F5 S  S  S  E5 S  S  S'),
        ('G7', 'Eb5 S S  S  D5 S  S  S'),
        ('Cm', 'C5 S  S  S  S  S  -  -'),
    ], loop=False),
]

# Menu lines for the first two batches, which predate the 'menu' field.
MENU = {
    'tune_ritz': 'RITZ     1929 STRUT',
    'tune_chase': 'CHASE    THE HURRY',
    'tune_villain': 'VILLAIN  MISTERIOSO',
    'tune_waltz': 'WALTZ    SWEETHEART',
    'tune_rag': 'RAG      PRATFALL',
    'tune_sorrow': 'SORROW   LAMENT',
    'tune_march': 'MARCH    KOPS SET OFF',
    'tune_tiptoe': 'TIPTOE   SNEAKING',
    'tune_agitato': 'AGITATO  PANIC',
    'tune_twostep': 'TWOSTEP  JAUNTY',
    'tune_dirge': 'DIRGE    LIFE LOST',
    'tune_fanfare': 'FANFARE  CAUGHT HIM',
}

TUNES = [RITZ, CHASE, VILLAIN, SWEETHEART, PRATFALL, SORROW,
         MARCH, TIPTOE, AGITATO, TWOSTEP, DIRGE, FANFARE] + BATCH3

PAGESZ = 12               # keys 1-9 then A-C on each page
KEYS = '123456789ABC'
MENUW = 21                # a menu line after "k " -- fits cols 4..24


def emit_code(lines):
    """The list-dependent CODE: count, play dispatch, menu pages.

    Generated rather than hand-kept because three hand lists (labels,
    menu text, PLAY lines) drift apart; this way a tune is added in one
    place. PLAY takes a constant label, hence one IF per tune.
    """
    n = len(TUNES)
    npage = (n + PAGESZ - 1) // PAGESZ
    lines.append('song_init:')
    lines.append('\tntune = %d' % n)
    lines.append('\tnpage = %d' % npage)
    lines.append('\tRETURN')
    lines.append('')
    lines.append('play_cur:')
    for i, t in enumerate(TUNES):
        lines.append('\tIF cur = %d THEN PLAY %s' % (i, t['label']))
    lines.append('\tRETURN')
    lines.append('')
    lines.append('draw_page:')
    for p in range(npage):
        lines.append('\tIF pg = %d THEN GOSUB menu_p%d' % (p, p))
    lines.append('\tRETURN')
    for p in range(npage):
        lines.append('')
        lines.append('menu_p%d:' % p)
        lines.append('\tPRINT AT 66,"PAGE %d OF %d        "' % (p + 1, npage))
        for s in range(PAGESZ):
            i = p * PAGESZ + s
            at = (4 + s) * 32      # col 0: the line also wipes the ">" column
            if i < n:
                t = TUNES[i]
                m = t.get('menu') or MENU[t['label']]
                if len(m) > MENUW:
                    sys.exit('gentunes: menu line %r is over %d chars' % (m, MENUW))
                text = '  %s %s' % (KEYS[s], m)
            else:
                text = ''
            lines.append('\tPRINT AT %d,"%s"' % (at, text.ljust(MENUW + 4)))
        lines.append('\tRETURN')
    lines.append('')


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    dst = os.path.join(here, '..', 'src', 'songs.bas')
    lines = ["\t' GENERATED by assets/gentunes.py -- edit that, not this.", '']
    emit_code(lines)
    labels = [t['label'] for t in TUNES]
    if len(set(labels)) != len(labels):
        sys.exit('gentunes: duplicate tune label')
    for t in TUNES:
        body = render(t)
        lines.append("\t' %s: %d bars, %d rows of %d ticks"
                     % (t['label'], len(t['bars']), len(body), t['ticks']))
        lines.append('%s:' % t['label'])
        lines.append('\tDATA BYTE %d' % t['ticks'])
        lines.extend(body)
        # A cue for an EVENT (a capture, a lost life) plays once; a scene
        # cue loops until the picture changes.
        lines.append('\tMUSIC REPEAT' if t.get('loop', True) else '\tMUSIC STOP')
        lines.append('')
    with open(dst, 'w', newline='\n') as f:
        f.write('\n'.join(lines))
    print('gentunes: %d tune(s) -> src/songs.bas' % len(TUNES))


if __name__ == '__main__':
    main()
