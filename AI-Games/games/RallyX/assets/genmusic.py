#!/usr/bin/env python3
"""Generate src/music.bas -- the in-game tune for our own tiny player.

Why not CVBasic's PLAY: its PSG music player writes the volume registers
itself, from envelope tables baked into the shared prologue, so a game
cannot turn it down. The tune has to sit UNDER the engine and the effects,
so we drive two channels ourselves and set the volume explicitly.

SOURCE: the piano arrangement supplied by the user (Rally-X, arr. Beaulan
Turner) -- A major, 4/4, quarter = 150, with a "Default theme" and a
"Challenge theme".

  *** THE NOTE DATA BELOW IS A READING OF A RENDERED SCORE IMAGE, NOT an
  *** import of the source file. The rhythm and structure are read directly
  *** (bar lengths, where the long notes fall, the eighth-note bass
  *** ostinato); individual PITCHES are the least certain part -- noteheads
  *** are a few pixels tall in the image and A major puts most of them on
  *** ledger-free lines that are easy to misread by a step.
  ***
  *** Every bar is written as plain note names precisely so this is easy to
  *** correct by ear: fix a name, re-run, rebuild. A MIDI or MusicXML export
  *** of the arrangement would let this be generated exactly instead.

Timing: at 150 BPM an eighth note is 0.2 s = 12 frames, so ONE STEP IS ONE
EIGHTH and MUSTICK is 12. The previous tune ran two steps per note.

Layout emitted:
  mus_freq   16-bit SN76489 dividers, hi byte then lo, one per note index.
             Index 0 is a rest / sustain (writes nothing, so the previous
             note keeps ringing).
  mus_song   two bytes per step: melody note index, bass note index.
  mus_len    number of steps in the default theme, then the total.

SN76489 divider: N = 3579545 / (32 * f). Smaller N = higher pitch.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
CLOCK = 3579545.0

# Chromatic, because A major needs F#, C# and G# and the arrangement adds
# naturals against them.
SEMI = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6,
        "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def freq(name):
    """'F#4' / 'A3' -> Hz, A4 = 440."""
    letter = name[:-1]
    octv = int(name[-1])
    n = SEMI[letter] + 12 * (octv + 1)          # MIDI number
    return 440.0 * (2.0 ** ((n - 69) / 12.0))


def divider(name):
    d = int(round(CLOCK / (32.0 * freq(name))))
    # The tone divider is 10 bits. 1023 is the deepest note the chip has,
    # about 109 Hz -- anything written below that would alias to a wrong
    # pitch rather than just being quiet, so it is clamped and reported.
    if d > 1023:
        print("  ! %s (%.1f Hz) is below the chip floor -- clamped" % (name, freq(name)))
        d = 1023
    if d < 1:
        d = 1
    return d


# --------------------------------------------------------------- the tune
# One string per BAR, eight slots = eight eighth notes. "." holds the
# previous note (a rest writes nothing, so it sustains); names are absolute
# so the key signature never has to be applied in the head.
#
# The bass is the driving eighth-note ostinato that runs under the whole
# piece -- that part IS clearly readable in the score: a low root alternating
# with the note a fifth above, shifting with the harmony.

DEFAULT_MEL = [
    "A4 . B4 C#5 D5 . C#5 B4",      # 1
    "A4 . E5 . D5 . C#5 B4",        # 2
    "A4 . B4 C#5 D5 E5 F#5 G5",     # 3
    "F#5 E5 D5 C#5 B4 . A4 .",      # 4
    "E5 . F#5 G5 A5 . G5 F#5",      # 5
    "E5 . D5 . C#5 . B4 .",         # 6
    "A4 . B4 C#5 D5 . E5 .",        # 7
    "C#5 . B4 A4 B4 . . .",         # 8
    "A4 . B4 C#5 D5 . C#5 B4",      # 9
    "A4 . E5 . D5 . C#5 B4",        # 10
    "A4 . B4 C#5 D5 E5 F#5 G5",     # 11
    "F#5 . . . E5 . . .",           # 12  (long notes)
    "D5 . C#5 B4 A4 . B4 C#5",      # 13
    "D5 . E5 . F#5 . E5 D5",        # 14
    "C#5 . B4 . A4 . B4 C#5",       # 15
    "A4 . . . . . . .",             # 16  (held)
]
DEFAULT_BASS = [
    "A2 A3 A2 A3 A2 A3 A2 A3",
    "A2 A3 A2 A3 A2 A3 A2 A3",
    "D3 A3 D3 A3 D3 A3 D3 A3",
    "E3 B3 E3 B3 A2 A3 A2 A3",
    "A2 A3 A2 A3 A2 A3 A2 A3",
    "E3 B3 E3 B3 E3 B3 E3 B3",
    "D3 A3 D3 A3 D3 A3 D3 A3",
    "E3 B3 E3 B3 E3 B3 E3 B3",
    "A2 A3 A2 A3 A2 A3 A2 A3",
    "A2 A3 A2 A3 A2 A3 A2 A3",
    "D3 A3 D3 A3 D3 A3 D3 A3",
    "E3 B3 E3 B3 E3 B3 E3 B3",
    "D3 A3 D3 A3 A2 A3 A2 A3",
    "D3 A3 D3 A3 E3 B3 E3 B3",
    "A2 A3 A2 A3 E3 B3 E3 B3",
    "A2 A3 A2 A3 A2 A3 A2 A3",
]

# The challenge theme is the shorter, more urgent section from bar 17.
CHAL_MEL = [
    "E5 F#5 G5 F#5 E5 . D5 .",      # 17
    "C#5 D5 E5 D5 C#5 . B4 .",      # 18
    "A4 B4 C#5 D5 E5 . F#5 .",      # 19
    "E5 . . . D5 . . .",            # 20
    "E5 F#5 G5 F#5 E5 . D5 .",      # 21
    "C#5 D5 E5 D5 C#5 . B4 .",      # 22
    "D5 . C#5 B4 A4 . B4 C#5",      # 23
    "A4 . . . . . . .",             # 24
]
CHAL_BASS = [
    "E3 B3 E3 B3 E3 B3 E3 B3",
    "A2 A3 A2 A3 A2 A3 A2 A3",
    "D3 A3 D3 A3 D3 A3 D3 A3",
    "E3 B3 E3 B3 E3 B3 E3 B3",
    "E3 B3 E3 B3 E3 B3 E3 B3",
    "A2 A3 A2 A3 A2 A3 A2 A3",
    "D3 A3 D3 A3 E3 B3 E3 B3",
    "A2 A3 A2 A3 A2 A3 A2 A3",
]


def flatten(bars, what):
    out = []
    for i, bar in enumerate(bars):
        slots = bar.split()
        assert len(slots) == 8, \
            "%s bar %d has %d slots, want 8 (one per eighth note)" % (what, i + 1, len(slots))
        out += slots
    return out


mel = flatten(DEFAULT_MEL, "default melody") + flatten(CHAL_MEL, "challenge melody")
bass = flatten(DEFAULT_BASS, "default bass") + flatten(CHAL_BASS, "challenge bass")
assert len(mel) == len(bass)
DEFAULT_STEPS = len(DEFAULT_MEL) * 8
TOTAL_STEPS = len(mel)

# every distinct pitch used, index 1..n (0 = sustain/rest)
names = []
for n in mel + bass:
    if n != "." and n not in names:
        names.append(n)
names.sort(key=freq)
IDX = {n: i + 1 for i, n in enumerate(names)}
IDX["."] = 0

lines = ["\t' GENERATED by assets/genmusic.py -- do not hand-edit.",
         "\t' Rally-X, arr. Beaulan Turner: A major, 4/4, quarter = 150.",
         "\t' ONE STEP = ONE EIGHTH NOTE = 12 frames (MUSTICK).",
         "\t' Default theme %d steps, challenge theme %d, %d total."
         % (DEFAULT_STEPS, TOTAL_STEPS - DEFAULT_STEPS, TOTAL_STEPS),
         "\t' Note data is a READING of the score image -- see genmusic.py.",
         ""]

print("notes used (%d):" % len(names))
lines.append("mus_freq:")
lines.append("\tDATA BYTE $00,$00\t' 0 = sustain")
for n in names:
    d = divider(n)
    lines.append("\tDATA BYTE $%02X,$%02X\t' %-4s %6.1f Hz" % (d >> 8, d & 0xFF, n, freq(n)))
print("   " + " ".join(names))

lines.append("mus_song:")
for i in range(TOTAL_STEPS):
    if i % 8 == 0:
        lines.append("\t' bar %d" % (i // 8 + 1))
    lines.append("\tDATA BYTE %d,%d" % (IDX[mel[i]], IDX[bass[i]]))

open(os.path.join(HERE, "..", "src", "music.bas"), "w").write("\n".join(lines) + "\n")
print("\nwrote src/music.bas: %d notes, %d steps (default %d + challenge %d)"
      % (len(names), TOTAL_STEPS, DEFAULT_STEPS, TOTAL_STEPS - DEFAULT_STEPS))
print("song length = %.1f s at 12 frames/step" % (TOTAL_STEPS * 12 / 60.0))
