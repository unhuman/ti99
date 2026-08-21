#!/usr/bin/env python3
"""
BUST-A-BOBBLE -- generates src/music.bas: the in-game theme and the victory galop.

THE THEME IS READ FROM assets/BobbleMusic.mid, exactly as RALLY-X reads
newrallyx.mid, and for the same reason: it is the only way to be right. It was
first transcribed from an engraving (assets/BobbleMusic.png) by measuring
noteheads against the staff-line ruler -- see score2bars.py, which is kept because
the technique is sound -- and the result was recognisably the tune but wrong in
two ways that matter. Half and whole notes are HOLLOW, so a filled-ink detector
skips them; and since note lengths were derived from horizontal spacing, whatever
survived was stretched to fill its bar. Bar 1 came out

    D5  D5  Eb5 Eb5 Eb5 G5           (transcribed, six notes)
    D5  D5  F5  F5  D#5  F5 F#5 G5   (the MIDI, eight -- both F naturals and
                                      the F# run restored)

Fewer, longer notes at the right tempo is what "too slow" actually sounds like.

THE REPEAT IS DETECTED, NOT ASSUMED. The file is the tune played twice: at an
offset of 19 bars, 709 of 709 notes recur -- a perfect match, which is also the
score's bar count. Only the first pass is emitted.

The galop below is still an ORIGINAL composition written for the victory screen.

    C5   strike this note        -    let the previous note ring

There is no explicit rest: a note rings until the next one on its channel, which is
what the player's "0 = sustain" encoding gives for free.

Run:  python3 genmusic.py
"""

import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "src", "music.bas")
MIDI = os.path.join(HERE, "BobbleMusic.mid")

MEL_TRACKS = (1, 3)          # the lead is SPLIT ACROSS TWO VOICES -- see below
BASS_TRACK = 2               # monophonic, D#2..G4

# WHY TWO MELODY TRACKS. Track 1 alone looks like the lead (monophonic, G4..D#6,
# in from bar 1) and it is -- until bar 16, where it stops for three bars and
# TRACK 3 carries the tune instead, playing the opening figure that ends the loop.
# Reading track 1 only, the melody simply vanished for the last three bars before
# the seam. They are two voices of one line, so the melody is the higher of the
# two wherever both sound.
BASS_MIN = 48                # C3: the PSG bottoms out near 110 Hz, so lift below this

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


def read_midi(path):
    """(ticks-per-quarter, [track][ (start, end, pitch) ]) -- the RALLY-X reader."""
    d = open(path, "rb").read()

    def vlq(i):
        v = 0
        while True:
            b = d[i]
            i += 1
            v = (v << 7) | (b & 0x7F)
            if not (b & 0x80):
                return v, i

    assert d[:4] == b"MThd", "not a MIDI file"
    hlen, fmt, ntrk, div = struct.unpack(">IHHH", d[4:14])
    i = 8 + hlen
    tracks = []
    for _ in range(ntrk):
        assert d[i:i + 4] == b"MTrk"
        tlen = struct.unpack(">I", d[i + 4:i + 8])[0]
        end, j, tick, status = i + 8 + tlen, i + 8, 0, 0
        notes, live = [], {}
        while j < end:
            dt, j = vlq(j)
            tick += dt
            if d[j] & 0x80:
                status = d[j]
                j += 1
            ev = status & 0xF0
            if status == 0xFF:
                j += 1
                ln, j = vlq(j)
                j += ln
            elif status in (0xF0, 0xF7):
                ln, j = vlq(j)
                j += ln
            elif ev in (0x80, 0x90):
                p, v = d[j], d[j + 1]
                j += 2
                if ev == 0x90 and v > 0:
                    live.setdefault(p, []).append(tick)
                elif live.get(p):
                    notes.append((live[p].pop(0), tick, p))
            elif ev in (0xA0, 0xB0, 0xE0):
                j += 2
            elif ev in (0xC0, 0xD0):
                j += 1
            else:
                j += 1
        tracks.append(sorted(notes))
        i = end
    return div, tracks


def repeat_bars(tracks, bar):
    """How long the tune is before it starts again, measured not assumed."""
    notes = set()
    for t in tracks:
        for t0, _, p in t:
            notes.add((t0, p))
    last = max(t0 for t0, _ in notes)
    best = (0, 0.0)
    for n in range(4, 33):
        off = n * bar
        src = [(t0, p) for (t0, p) in notes if t0 + off <= last]
        if len(src) < 40:
            continue
        hit = sum(1 for (t0, p) in src if (t0 + off, p) in notes)
        r = hit / float(len(src))
        if r > best[1]:
            best = (n, r)
    return best


def to_steps(notes, nbars, bar, lift):
    """Quantise one monophonic track onto the sixteenth grid.

    Where two notes land on the same step -- the 32nd-note run in bar 1 does --
    the LATER one wins, so a run keeps the note it is heading for rather than the
    grace note before it."""
    per = bar // STEPS_PER_BAR
    out = [None] * (nbars * STEPS_PER_BAR)
    for t0, t1, p in notes:
        k = int(round(t0 / float(per)))
        if 0 <= k < len(out):
            while p < lift:
                p += 12
            out[k] = p
    return out


MEL_OCTAVE_MIDI = -12        # the melody drops an octave, as the old tune did
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


def midi_name(p):
    return NAMES[p % 12] + str(p // 12 - 1)


def main():
    div, tracks = read_midi(MIDI)
    bar = div * 4
    nbars, ratio = repeat_bars(tracks, bar)
    if ratio < 0.98:
        sys.stderr.write("error: no clean repeat found in %s (best %d bars, %.0f%%)\n"
                         % (os.path.basename(MIDI), nbars, 100 * ratio))
        return 1
    mel_p = [None] * (nbars * STEPS_PER_BAR)
    for tn in MEL_TRACKS:
        part = to_steps(tracks[tn], nbars, bar, 0)
        for i, p in enumerate(part):
            if p and (mel_p[i] is None or p > mel_p[i]):
                mel_p[i] = p
    bas_p = to_steps(tracks[BASS_TRACK], nbars, bar, BASS_MIN)
    mel = [midi_name(p + MEL_OCTAVE_MIDI) if p else None for p in mel_p]
    bas = [midi_name(p) if p else None for p in bas_p]

    # DROP A BAR THAT MERELY REPEATS THE ONE BEFORE IT.
    #
    # This MIDI has two byte-identical bars back to back near the end (17 and 18),
    # so the loop said the same phrase twice and then began again -- audible as a
    # stutter at the seam. The engraving does NOT do that: bars 16, 17 and 18 open
    # with the same figure but end on G5, C5 and Bb5, so the doubling looks like a
    # sequencer copy-paste rather than the composition.
    #
    # Detected rather than hard-coded, so swapping the MIDI cannot silently
    # reintroduce it -- and CONSECUTIVE only: bars 1-3 and 5-7 are also identical
    # to each other, but that is the tune's own structure and must stay.
    S = STEPS_PER_BAR
    keep_m, keep_b, dropped = [], [], []
    for b in range(len(mel) // S):
        m = mel[b * S:(b + 1) * S]
        d = bas[b * S:(b + 1) * S]
        if keep_m and m == keep_m[-S:] and d == keep_b[-S:]:
            dropped.append(b + 1)
            continue
        keep_m += m
        keep_b += d
    if dropped:
        print("  dropped bar(s) %s -- identical to the bar before"
              % ", ".join(str(x) for x in dropped))
    mel, bas = keep_m, keep_b
    vmel = parse(VICTORY, "victory melody", MEL_OCTAVE)
    vbas = parse(VIC_BASS, "victory bass")
    if len(vmel) != len(vbas):
        raise SystemExit("victory melody is %d steps, bass %d" % (len(vmel), len(vbas)))
    steps, vsteps = len(mel), len(vmel)
    print("  theme: %d bars from %s (repeat matched %.0f%% at that offset)"
          % (nbars, os.path.basename(MIDI), 100 * ratio))

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

    # Bar labels for the listing: the bass note each bar opens on, which is the
    # closest thing to a chord symbol without doing harmonic analysis.
    labels = []
    for b in range(steps // STEPS_PER_BAR):
        lab = "-"
        for k in range(b * STEPS_PER_BAR, (b + 1) * STEPS_PER_BAR):
            if bas[k]:
                lab = bas[k]
                break
        labels.append(lab)
    emit("mus_song", mel, bas, labels, "the Puzzle Bobble theme, from the MIDI")
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
