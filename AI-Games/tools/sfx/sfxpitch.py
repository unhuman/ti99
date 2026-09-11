#!/usr/bin/env python3
"""Read SN76489 REGISTER VALUES out of a recording of a game that used one.

THE TRICK THIS REPO KEEPS RE-LEARNING: if the reference machine has the SAME
SOUND CHIP as the target, its effects can be RECOVERED rather than imitated.
The ColecoVision, the SG-1000 and the BBC Micro all carry a TI SN76489, and so
does the TI-99/4A. At the usual 3.579545 MHz:

    freq = 3579545 / (32 * divisor)        divisor = 111860 / freq

An Atari 2600 recording gives you none of this -- the TIA is a 5-bit divider with
its own waveform table, so every number taken from it has to be re-imagined as an
SN76489 setting and the result is a judgement rather than a measurement. Given a
choice of reference recordings, TAKE THE ONE WITH YOUR CHIP IN IT.

WHY GOERTZEL AND NOT AN FFT PEAK. An FFT peak-pick answers "what frequency is
this?", and then you round to the nearest divisor and hope. This asks the better
question -- "of the divisors the chip can actually PLAY, which one is present?" --
by running one filter per candidate. The answer is the register value itself. It
also needs no numpy, which this machine does not have, and only wants a hundred
bins rather than two thousand.

THE LIMIT, WHICH MUST BE STATED WHEREVER THE NUMBERS ARE USED. Adjacent divisors
sit about freq/divisor apart in hertz, so the resolution you need depends on the
note:

    divisor  40   2797 Hz   ~70 Hz apart    15 ms of audio resolves it
    divisor 108   1035 Hz   ~10 Hz apart   100 ms -- usually fine
    divisor 212    527 Hz   ~2.5 Hz apart  420 ms -- longer than most effects

So a short low note comes back as "somewhere around 212", with 211 and 210
scoring identically, and the printed relative scores say so. READ A HIGH NOTE AS
A REGISTER VALUE AND A LOW ONE AS A NEIGHBOURHOOD. A draft of this tool claimed
the winner simply IS the byte the game wrote; that is true only at the top of the
range, and the overclaim survived into a commit message before being caught.

And a recording carries music and several channels at once, so a reading is the
LOUDEST thing in its window, not necessarily the effect you were aiming at.

Run:  python3 sfxpitch.py FILE.wav T0 [DURATION] [STEP] [COUNT]

      python3 sfxpitch.py kk.wav 8.15 0.04 0.04 10
          walks ten 40 ms windows from t=8.15 and prints the divisor of each,
          which is how a sweep or a warble is read off.

The WAV must be mono. `ffmpeg -i in.m4a -ac 1 -ar 44100 out.wav`.
"""
import math
import struct
import sys
import wave

CLOCK = 3579545.0

# The divisors worth testing. Below ~16 the tones are above 7 kHz, where a lossy
# recording has usually thrown the energy away; above ~600 they are under 190 Hz
# and sit in whatever music is playing.
DIVISORS = list(range(16, 601))


def freq_of(n):
    return CLOCK / (32.0 * n)


def divisor_of(freq):
    return int(round(CLOCK / (32.0 * freq))) if freq > 0 else 0


def goertzel(samples, rate, freq):
    """Energy at one frequency. Textbook second-order form, no numpy."""
    n = len(samples)
    k = int(0.5 + (n * freq) / rate)
    w = (2.0 * math.pi / n) * k
    coeff = 2.0 * math.cos(w)
    s1 = s2 = 0.0
    for x in samples:
        s0 = x + coeff * s1 - s2
        s2, s1 = s1, s0
    return s1 * s1 + s2 * s2 - coeff * s1 * s2


def read(path, t0, dur):
    w = wave.open(path, "rb")
    rate = w.getframerate()
    if w.getnchannels() != 1:
        sys.exit("sfxpitch: %s is not mono -- convert with ffmpeg -ac 1" % path)
    w.setpos(min(int(t0 * rate), w.getnframes() - 1))
    raw = w.readframes(int(dur * rate))
    w.close()
    return struct.unpack("<%dh" % (len(raw) // 2), raw), rate


def top_divisors(path, t0, dur, k=4):
    """The k best-scoring divisors: [(divisor, freq, score relative to best)]."""
    s, rate = read(path, t0, dur)
    if not s:
        return []
    scored = [(goertzel(s, rate, freq_of(n)), n) for n in DIVISORS]
    scored.sort(reverse=True)
    peak = scored[0][0] or 1.0
    return [(n, freq_of(n), e / peak) for e, n in scored[:k]]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__.strip().split("Run:")[1].strip())
    path = sys.argv[1]
    t0 = float(sys.argv[2])
    dur = float(sys.argv[3]) if len(sys.argv) > 3 else 0.06
    step = float(sys.argv[4]) if len(sys.argv) > 4 else dur
    count = int(sys.argv[5]) if len(sys.argv) > 5 else 1

    print("t        divisor  /4   freq Hz   runners-up (score vs best)")
    for i in range(count):
        t = t0 + i * step
        got = top_divisors(path, t, dur)
        if not got:
            break
        n, f, _ = got[0]
        rest = "  ".join("%d(%.2f)" % (a, c) for a, _b, c in got[1:])
        # "/4" is what a CVBasic DATA BYTE can hold: a divisor runs to 1023 and
        # a byte stops at 255, so every table in this repo stores divisor/4.
        print("%6.2f   %5d %4d   %7.0f   %s" % (t, n, n // 4, f, rest))


if __name__ == "__main__":
    main()
