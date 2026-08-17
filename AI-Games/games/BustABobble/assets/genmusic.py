#!/usr/bin/env python3
"""
BUST-A-BOBBLE -- generates src/music.bas: the in-game tune.

ORIGINAL COMPOSITION, not a transcription. Taito's Puzzle Bobble music is theirs;
this is a cheerful major-key chip tune written for the game, in the same spirit.

The tune is written below as READABLE BARS -- one line per bar, sixteen tokens per
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
# 12 bars, 4/4. Chords cycle C - Am - F - G three times. Bars 1-4 state an
# arpeggio hook, 5-8 repeat it and run back down, 9-12 answer with a stepwise
# melody so the ear gets a rest from arpeggios, then it loops -- bar 12 ends on D5
# and bar 1 opens on C5, which resolves.
#
# It was 16 bars; the last four repeated 1-4 bar their final cadence, and their 128
# bytes bought the on-screen music toggle. Repetition was the cheapest thing here
# to give up.
MELODY = [
    "C5 -  E5 -  G5 -  -  -  E5 -  G5 -  C6 -  -  - ",   # 1
    "A4 -  C5 -  E5 -  -  -  C5 -  E5 -  A5 -  -  - ",   # 2
    "F4 -  A4 -  C5 -  -  -  A4 -  C5 -  F5 -  -  - ",   # 3
    "G4 -  B4 -  D5 -  -  -  D5 -  B4 -  G4 -  -  - ",   # 4
    "C5 -  E5 -  G5 -  -  -  E5 -  G5 -  C6 -  -  - ",   # 5
    "A4 -  C5 -  E5 -  -  -  C5 -  E5 -  A5 -  -  - ",   # 6
    "F4 -  A4 -  C5 -  -  -  A4 -  C5 -  F5 -  -  - ",   # 7
    "G4 -  B4 -  D5 -  G5 -  F5 -  E5 -  D5 -  C5 - ",   # 8
    "E5 -  -  -  D5 -  C5 -  D5 -  -  -  E5 -  G5 - ",   # 9
    "A5 -  -  -  G5 -  E5 -  C5 -  -  -  D5 -  E5 - ",   # 10
    "F5 -  -  -  E5 -  D5 -  C5 -  -  -  A4 -  C5 - ",   # 11
    "G5 -  -  -  F5 -  E5 -  D5 -  -  -  -  -  -  - ",   # 12
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
CHORDS = ["C", "Am", "F", "G"] * 3
BASS = [BASSLINE[c] for c in CHORDS]

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
    if len(mel) != len(bas):
        raise SystemExit("melody is %d steps, bass %d" % (len(mel), len(bas)))
    steps = len(mel)

    used = []
    for n in mel + bas:
        if n is not None and n not in used:
            used.append(n)
    used.sort(key=divider, reverse=True)          # low notes first, tidier to read
    index = dict((n, i + 1) for i, n in enumerate(used))   # 0 is reserved: sustain

    L = []
    w = L.append
    w("\t' BUST-A-BOBBLE in-game music -- GENERATED by assets/genmusic.py")
    w("\t' Do not edit. Edit the bars in genmusic.py and regenerate.")
    w("\t'")
    w("\t' ORIGINAL COMPOSITION. %d steps of a sixteenth each at %d frames"
      % (steps, MUSTICK))
    w("\t' = %d BPM, %d bars, about %.1f seconds a time round."
      % (900 // MUSTICK, steps // STEPS_PER_BAR, steps * MUSTICK / 60.0))
    w("\t'")
    w("\t' Note 0 means SUSTAIN -- write nothing, let the channel ring. That is what")
    w("\t' keeps this to two bytes a step and why the tune needs no rests.")
    w("")
    w("mus_freq:")
    w("\tDATA BYTE $00,$00\t' 0 = sustain (writes nothing)")
    for n in used:
        d = divider(n)
        w("\tDATA BYTE $%02X,$%02X\t' %-4s %7.1f Hz" % (d >> 8, d & 255, n, freq(n)))
    w("")
    w("mus_song:\t' one line per step: melody note, bass note")
    for b in range(steps // STEPS_PER_BAR):
        w("\t' bar %d  (%s)" % (b + 1, CHORDS[b]))
        for s in range(STEPS_PER_BAR):
            i = b * STEPS_PER_BAR + s
            m = index[mel[i]] if mel[i] else 0
            t = index[bas[i]] if bas[i] else 0
            w("\tDATA BYTE %d,%d" % (m, t))
    w("")

    # CHECK THE PLAYER'S LOOP-BACK LITERAL MATCHES THIS TUNE.
    #
    # The length has to be a bare literal in BUSTABOB.bas, which means it can drift
    # from the tune -- so it is verified here instead of trusted. Two attempts to
    # make it a CONST both failed as the SAME silent symptom, the song replaying its
    # first note for ever: above 255 a CONST compiles to zero, and a CONST emitted
    # into this file is a FORWARD REFERENCE (music.bas is INCLUDEd after all the
    # code -- levels.bas follows it, in the TI ROM bank), which
    # CVBasic accepts as an undefined variable holding zero. A literal plus this
    # check is the only arrangement that fails loudly.
    # A MISSING SOURCE IS A FAILURE, NOT A SKIP. `if os.path.exists(...)` here first,
    # and the check quietly passed when the path resolved wrong -- which is the very
    # thing it exists to prevent. A guard that can silently not run is not a guard.
    want = "IF #mup >= %d THEN #mup = 0" % steps
    bas = os.path.join(HERE, "..", "src", "BUSTABOB.bas")
    if not os.path.exists(bas):
        sys.stderr.write("error: cannot find %s to verify the loop-back literal\n"
                         % os.path.normpath(bas))
        return 1
    if want not in open(bas, encoding="utf-8").read():
        sys.stderr.write(
            "error: the tune is %d steps but src/BUSTABOB.bas does not loop back\n"
            "       at %d. mus_step needs exactly:\n"
            "           %s\n"
            "       A mismatch plays part of the tune, or reads past the table\n"
            "       into whatever follows it.\n" % (steps, steps, want))
        return 1

    outdir = os.path.dirname(os.path.abspath(OUT))
    if not os.path.isdir(outdir):
        os.makedirs(outdir)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(L) + "\n")

    data = (len(used) + 1) * 2 + steps * 2
    print("wrote %s" % os.path.normpath(OUT))
    print("  %d steps (%d bars), %d distinct notes" %
          (steps, steps // STEPS_PER_BAR, len(used)))
    print("  %d BPM, loops every %.1f s" % (900 // MUSTICK, steps * MUSTICK / 60.0))
    print("  freq table %d B + song %d B = %d B" %
          ((len(used) + 1) * 2, steps * 2, data))
    print("  range: %s (%d) .. %s (%d)  [divider: smaller is higher]"
          % (used[0], divider(used[0]), used[-1], divider(used[-1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
