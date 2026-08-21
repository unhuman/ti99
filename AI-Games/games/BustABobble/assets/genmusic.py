#!/usr/bin/env python3
"""
BUST-A-BOBBLE -- generates src/music.bas: the in-game tune.

ORIGINAL COMPOSITION, not a transcription. Taito's Puzzle Bobble music is theirs;
this is a cheerful major-key chip tune written for the game, in the same spirit.

The tune is 24 bars in three sections (A-B-A'), written below as READABLE BARS -- one line per bar, sixteen tokens per
line, one token per sixteenth note. That is the point of generating it: the thing a
person edits is a tune, and the thing the ROM gets is a byte table, and neither has
to be maintained by hand.

    C5   strike this note        -    let the previous note ring
    .    same as '-' (spacer, purely so the beat is easy to count)

There is no explicit rest: a note rings until the next one on its channel, which is
what the player's "0 = sustain" encoding gives for free and what keeps the table at
two bytes a step.

Run:  python3 genmusic.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "src", "music.bas")

PSG_CLOCK = 3579545          # TI-99/4A SN76489 clock
STEPS_PER_BAR = 16           # sixteenth-note grid

# Equal temperament, A4 = 440. Only the notes the tune uses get emitted.
NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def freq(name):
    step = NAMES.index(name[:-1])
    octave = int(name[-1])
    n = step + 12 * (octave - 4) - 9          # semitones from A4
    return 440.0 * (2.0 ** (n / 12.0))


def divider(name):
    """SN76489 10-bit divider. SMALLER IS HIGHER -- see CLAUDE.md 3A."""
    d = int(round(PSG_CLOCK / (32.0 * freq(name))))
    if not 1 <= d <= 1023:
        raise SystemExit("%s -> divider %d, outside the 10-bit field. The PSG "
                         "bottoms out near 110 Hz; transpose it up an octave."
                         % (name, d))
    return d


# --- the tune -------------------------------------------------------------------
# 24 bars, 4/4, in three eight-bar sections: A - B - A'.
#
# It was 12 bars of C-Am-F-G three times over, which is a loop rather than a tune:
# with one idea repeated it announces its own seam every 19 seconds. This has
# somewhere to go and somewhere to come back to.
#
#   A  (1-8)   the arpeggio hook over C-Am-F-G twice, the second time running back
#              down instead of leaping -- so the section ends by falling into B.
#   B  (9-16)  the contrast: half the harmonic rhythm (two bars a chord), a
#              STEPWISE singing line where A leaps, and it sits higher. Long notes
#              give the ear a rest from sixteenth arpeggios, which is the thing
#              that made the old loop tiring.
#   A' (17-24) the hook returns, then a real cadence -- F, G, C -- so the loop
#              point lands on a resolution rather than mid-phrase.
#
# Bar 24 holds C and bar 1 opens on C an octave down, which is why it can loop at
# all without sounding like a tape splice.
MELODY = [
    # -- A ---------------------------------------------------------------------
    "C5 -  E5 -  G5 -  -  -  E5 -  G5 -  C6 -  -  - ",   # 1  C
    "A4 -  C5 -  E5 -  -  -  C5 -  E5 -  A5 -  -  - ",   # 2  Am
    "F4 -  A4 -  C5 -  -  -  A4 -  C5 -  F5 -  -  - ",   # 3  F
    "G4 -  B4 -  D5 -  -  -  D5 -  B4 -  G4 -  -  - ",   # 4  G
    "C5 -  E5 -  G5 -  -  -  E5 -  G5 -  C6 -  -  - ",   # 5  C
    "A4 -  C5 -  E5 -  -  -  C5 -  E5 -  A5 -  -  - ",   # 6  Am
    "F4 -  A4 -  C5 -  -  -  A4 -  C5 -  F5 -  -  - ",   # 7  F
    "G4 -  B4 -  D5 -  G5 -  F5 -  E5 -  D5 -  C5 - ",   # 8  G  (runs down into B)
    # -- B ---------------------------------------------------------------------
    "E5 -  -  -  A5 -  -  -  G5 -  E5 -  D5 -  -  - ",   # 9  Am
    "C5 -  D5 -  E5 -  -  -  A4 -  -  -  -  -  -  - ",   # 10 Am
    "F5 -  -  -  A5 -  -  -  G5 -  F5 -  E5 -  -  - ",   # 11 F
    "D5 -  E5 -  F5 -  -  -  C5 -  -  -  -  -  -  - ",   # 12 F
    "G5 -  -  -  C6 -  -  -  B5 -  G5 -  E5 -  -  - ",   # 13 C
    "D5 -  E5 -  G5 -  -  -  C5 -  -  -  -  -  -  - ",   # 14 C
    "D5 -  F5 -  G5 -  -  -  B5 -  G5 -  D5 -  -  - ",   # 15 G
    "B4 -  D5 -  G5 -  -  -  F5 -  -  -  D5 -  -  - ",   # 16 G  (leading tone, back to A)
    # -- A' --------------------------------------------------------------------
    "C5 -  E5 -  G5 -  -  -  E5 -  G5 -  C6 -  -  - ",   # 17 C
    "A4 -  C5 -  E5 -  -  -  C5 -  E5 -  A5 -  -  - ",   # 18 Am
    "F4 -  A4 -  C5 -  -  -  A4 -  C5 -  F5 -  -  - ",   # 19 F
    "G4 -  B4 -  D5 -  -  -  D5 -  B4 -  G4 -  -  - ",   # 20 G
    "C5 -  E5 -  G5 -  C6 -  -  -  G5 -  E5 -  C5 - ",   # 21 C  (the hook, inverted)
    "F5 -  -  -  E5 -  D5 -  C5 -  -  -  A4 -  C5 - ",   # 22 F
    "G4 -  B4 -  D5 -  G5 -  F5 -  D5 -  B4 -  G4 - ",   # 23 G
    "C5 -  -  -  E5 -  G5 -  C6 -  -  -  -  -  -  - ",   # 24 C  (cadence, holds)
]

# Bouncing root-fifth eighths under each chord. Everything sits in octave 3 or
# above because the PSG's 10-bit divider bottoms out around 110 Hz -- a "proper"
# bass an octave down would alias rather than simply sound quiet.
# F and G take the fifth BELOW rather than above (C3 not C4, D3 not D4) so the
# whole bass stays inside one octave, C3-A3. With the melody dropped an octave it
# would otherwise poke up through the tune's lower notes and the two voices would
# swap places mid-bar.
BASSLINE = {
    "C":  "C3 -  G3 -  C3 -  G3 -  C3 -  G3 -  C3 -  G3 - ",
    "Am": "A3 -  E3 -  A3 -  E3 -  A3 -  E3 -  A3 -  E3 - ",
    "F":  "F3 -  C3 -  F3 -  C3 -  F3 -  C3 -  F3 -  C3 - ",
    "G":  "G3 -  D3 -  G3 -  D3 -  G3 -  D3 -  G3 -  D3 - ",
}
CHORDS = ["C", "Am", "F", "G", "C", "Am", "F", "G",
          "Am", "Am", "F", "F", "C", "C", "G", "G",
          "C", "Am", "F", "G", "C", "F", "G", "C"]
BASS = [BASSLINE[c] for c in CHORDS]

# --- the victory tune -----------------------------------------------------------
# Eight bars of circus galop for the screen you get for beating round 30. Also an
# ORIGINAL composition -- "Entry of the Gladiators" is what everyone hears in their
# head for this, and it is out of copyright, but the rest of this game's music is
# written rather than transcribed and this matches it.
#
# What makes it read as circus rather than as more of the in-game tune: it opens
# on a rising fanfare through the chord instead of a hook, it is relentlessly
# on-the-beat where the main tune syncopates, and the bass is the same root-fifth
# oom-pah the galop lives on. It is deliberately SHORT -- eight bars, 12.8 s --
# because it plays under a screen the player is looking at, not one they are
# working in.
VICTORY = [
    "G4 -  C5 -  E5 -  G5 -  C6 -  -  -  G5 -  -  - ",   # 1  C  fanfare up
    "E5 -  G5 -  C6 -  -  -  G5 -  E5 -  C5 -  -  - ",   # 2  C  ...and back down
    "D5 -  F5 -  G5 -  B5 -  D6 -  -  -  B5 -  -  - ",   # 3  G
    "G5 -  B5 -  D6 -  -  -  B5 -  G5 -  D5 -  -  - ",   # 4  G
    "E5 -  G5 -  C6 -  -  -  C6 -  B5 -  A5 -  G5 - ",   # 5  C
    "F5 -  A5 -  C6 -  -  -  A5 -  F5 -  C5 -  -  - ",   # 6  F
    "G4 -  B4 -  D5 -  G5 -  B5 -  D6 -  B5 -  G5 - ",   # 7  G  the run up
    "C6 -  -  -  G5 -  E5 -  C5 -  -  -  -  -  -  - ",   # 8  C  cadence
]
VIC_CHORDS = ["C", "C", "G", "G", "C", "F", "G", "C"]

# The galop gets its OWN bass rather than reusing BASSLINE's plain root-fifth.
# It is still oom-pah -- that is the sound of the thing -- but it WALKS into the
# two cadences (bars 4 and 7), which is what a circus band does to tell you the
# tune is about to turn round. Same 16 steps a bar, so it costs no extra bytes.
VIC_BASS = [
    "C3 -  G3 -  C3 -  G3 -  C3 -  G3 -  C3 -  G3 - ",   # 1  C
    "C3 -  G3 -  C3 -  G3 -  C3 -  G3 -  E3 -  G3 - ",   # 2  C
    "G3 -  D3 -  G3 -  D3 -  G3 -  D3 -  G3 -  D3 - ",   # 3  G
    "G3 -  D3 -  G3 -  A3 -  B3 -  -  -  D3 -  -  - ",   # 4  G  walk-up
    "C3 -  G3 -  C3 -  G3 -  C3 -  G3 -  C3 -  G3 - ",   # 5  C
    "F3 -  C3 -  F3 -  C3 -  F3 -  C3 -  F3 -  C3 - ",   # 6  F
    "G3 -  D3 -  G3 -  A3 -  B3 -  D3 -  G3 -  B3 - ",   # 7  G  walk-up
    "C3 -  G3 -  C3 -  -  -  -  C3 -  -  -  -  -  - ",   # 8  C  two hits and out
]

MUSTICK = 6                  # frames per sixteenth -> 900/6 = 150 BPM

# The melody is written above in the octave it is easiest to read and then dropped
# by this many octaves. It was first pitched an octave higher and was simply shrill
# -- a square wave up at C6 is 1 kHz of unrelieved buzz, which is tiring within a
# round, never mind for twenty-five seconds on a loop.
#
# ONLY THE MELODY CAN MOVE. The bass already sits near the PSG's floor: its divider
# is 10 bits, so the lowest note it can play at all is about 110 Hz, and C2 would
# need 1710. Transposing the bass down as well would silently alias rather than
# sound low -- which is why divider() refuses to emit an out-of-range note instead
# of letting it wrap.
MEL_OCTAVE = -1


def octave_shift(name, by):
    return name[:-1] + str(int(name[-1]) + by)


def parse(bars, what, shift=0):
    out = []
    for i, bar in enumerate(bars):
        toks = bar.split()
        if len(toks) != STEPS_PER_BAR:
            raise SystemExit("%s bar %d has %d tokens, need %d"
                             % (what, i + 1, len(toks), STEPS_PER_BAR))
        for t in toks:
            out.append(None if t in ("-", ".") else octave_shift(t, shift))
    return out


def main():
    mel = parse(MELODY, "melody", MEL_OCTAVE)
    bas = parse(BASS, "bass")
    vmel = parse(VICTORY, "victory melody", MEL_OCTAVE)
    vbas = parse(VIC_BASS, "victory bass")
    if len(mel) != len(bas):
        raise SystemExit("melody is %d steps, bass %d" % (len(mel), len(bas)))
    if len(vmel) != len(vbas):
        raise SystemExit("victory melody is %d steps, bass %d" % (len(vmel), len(vbas)))
    steps, vsteps = len(mel), len(vmel)

    # ONE frequency table for both tunes: the victory galop reuses most of the
    # in-game tune's notes, and a second table would be 30-odd bytes of the fixed
    # area to say the same thing twice.
    used = []
    for n in mel + bas + vmel + vbas:
        if n is not None and n not in used:
            used.append(n)
    used.sort(key=divider, reverse=True)          # low notes first, tidier to read
    index = dict((n, i + 1) for i, n in enumerate(used))   # 0 is reserved: sustain

    L = []
    w = L.append
    w("\t' BUST-A-BOBBLE music -- GENERATED by assets/genmusic.py")
    w("\t' Do not edit. Edit the bars in genmusic.py and regenerate.")
    w("\t'")
    w("\t' TWO ORIGINAL TUNES sharing one note table: the in-game loop (%d steps,"
      % steps)
    w("\t' %d bars) and the victory galop (%d steps, %d bars). %d BPM, a sixteenth"
      % (steps // STEPS_PER_BAR, vsteps, vsteps // STEPS_PER_BAR, 900 // MUSTICK))
    w("\t' each at %d frames." % MUSTICK)
    w("\t'")
    w("\t' Note 0 means SUSTAIN -- write nothing, let the channel ring. That is what")
    w("\t' keeps this to two bytes a step and why neither tune needs rests.")
    w("")
    w("mus_freq:")
    w("\tDATA BYTE $00,$00\t' 0 = sustain (writes nothing)")
    for n in used:
        d = divider(n)
        w("\tDATA BYTE $%02X,$%02X\t' %-4s %7.1f Hz" % (d >> 8, d & 255, n, freq(n)))
    w("")

    def emit(label, m, b, chords, title):
        w("%s:\t' %s -- melody note, bass note per step" % (label, title))
        for bar in range(len(m) // STEPS_PER_BAR):
            w("\t' bar %d  (%s)" % (bar + 1, chords[bar]))
            for st in range(STEPS_PER_BAR):
                i = bar * STEPS_PER_BAR + st
                w("\tDATA BYTE %d,%d" % (index[m[i]] if m[i] else 0,
                                          index[b[i]] if b[i] else 0))
        w("")

    emit("mus_song", mel, bas, CHORDS, "the in-game loop")
    emit("vic_song", vmel, vbas, VIC_CHORDS, "the victory galop")

    # CHECK THE PLAYER'S LENGTH LITERALS MATCH THESE TUNES.
    #
    # Both lengths are bare literals in BUSTABOB.bas, which means they can drift
    # from the tunes -- so they are verified here instead of trusted. Two attempts
    # to make the first one a CONST both failed as the SAME silent symptom, the
    # song replaying its first note for ever: above 255 a CONST compiles to zero,
    # and a CONST emitted into this file is a FORWARD REFERENCE (music.bas is
    # INCLUDEd after the code), which CVBasic accepts as an undefined variable
    # holding zero. A literal plus this check is the only arrangement that fails
    # loudly. A MISSING SOURCE IS A FAILURE, NOT A SKIP.
    bas_path = os.path.join(HERE, "..", "src", "BUSTABOB.bas")
    if not os.path.exists(bas_path):
        sys.stderr.write("error: cannot find %s to verify the length literals\n"
                         % os.path.normpath(bas_path))
        return 1
    src = open(bas_path, encoding="utf-8").read()
    for want, what in (("#muslen = %d" % steps, "in-game tune"),
                       ("#muslen = %d" % vsteps, "victory galop")):
        if want not in src:
            sys.stderr.write(
                "error: src/BUSTABOB.bas does not set the %s length. It needs\n"
                "           %s\n"
                "       A mismatch plays part of a tune, or reads past its table\n"
                "       into whatever follows it.\n" % (what, want))
            return 1

    outdir = os.path.dirname(os.path.abspath(OUT))
    if not os.path.isdir(outdir):
        os.makedirs(outdir)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(L) + "\n")

    data = (len(used) + 1) * 2 + (steps + vsteps) * 2
    print("wrote %s" % os.path.normpath(OUT))
    print("  in-game %d steps (%d bars), victory %d steps (%d bars), %d notes"
          % (steps, steps // STEPS_PER_BAR, vsteps, vsteps // STEPS_PER_BAR,
             len(used)))
    print("  %d BPM; loops every %.1f s / %.1f s"
          % (900 // MUSTICK, steps * MUSTICK / 60.0, vsteps * MUSTICK / 60.0))
    print("  freq table %d B + songs %d B = %d B"
          % ((len(used) + 1) * 2, (steps + vsteps) * 2, data))
    return 0


if __name__ == "__main__":
    sys.exit(main())
