#!/usr/bin/env python3
"""Find the sound EVENTS in a long recording, so you know where to listen.

A longplay is ten to twenty minutes and an effect is a fifth of a second. Before
anything can be measured, the handful of moments that matter have to be separated
from the hours that do not -- and from the footsteps, which in a running game
outnumber every real effect by twenty to one.

THIS IS THE CHEAP PASS, deliberately. `audioop.rms` is C speed, so a whole
recording is a few seconds' work, and that is what makes it reasonable to sweep
the lot rather than guess at timestamps. Take the times it prints into
sfxpitch.py (what note) or sfxshape.py (what shape) for the expensive pass.

WHY audioop AND NOT numpy: there is no numpy on this machine, and 30 million
samples in pure Python is minutes per pass. `audioop.rms` and `audioop.cross`
are in the standard library and run at C speed. (audioop is deprecated from
Python 3.11 and gone in 3.13 -- the Cygwin python here is 3.9. If it disappears,
the replacement is `array` plus a block sum, at some cost in speed.)

ZERO CROSSINGS ARE A FREE FIRST GUESS AT PITCH. A square wave crosses zero
exactly twice per period, and the SN76489's tones are square, so the crossing
rate IS the frequency for a clean tone. It is only a guess: it collapses the
moment two channels sound together, and noise crosses far more often and
irregularly -- which is itself the useful part, because it is what separates a
percussive step from a note without measuring anything.

Run:  python3 sfxscan.py FILE.wav [START] [LIMIT]

The WAV must be mono. `ffmpeg -i in.m4a -ac 1 -ar 44100 out.wav`.
"""
import audioop
import sys
import wave

BLOCK_MS = 10
CLOCK = 3579545.0


def divisor(freq):
    return int(round(CLOCK / (32.0 * freq))) if freq > 0 else 0


def blocks(path):
    w = wave.open(path, "rb")
    rate, width = w.getframerate(), w.getsampwidth()
    if w.getnchannels() != 1:
        sys.exit("sfxscan: %s is not mono -- convert with ffmpeg -ac 1" % path)
    n = int(rate * BLOCK_MS / 1000)
    out, t = [], 0.0
    while True:
        raw = w.readframes(n)
        if len(raw) < n * width:
            break
        # crossings -> a frequency estimate: two per period for a square wave
        freq = audioop.cross(raw, width) * (1000.0 / BLOCK_MS) / 2.0
        out.append((t, audioop.rms(raw, width), freq))
        t += BLOCK_MS / 1000.0
    w.close()
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__.strip().split("Run:")[1].strip())
    path = sys.argv[1]
    start = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else 40

    b = blocks(path)
    # THE GATE IS DERIVED, NOT TYPED. Recordings differ by twenty decibels, and a
    # hard threshold that suits one is silence or noise on the next. The 55th
    # percentile of block loudness is close enough to "room tone" for anything
    # with more quiet than sound in it, which a longplay is.
    loud = sorted(r for _t, r, _f in b)
    floor = loud[int(len(loud) * 0.55)]
    gate = max(floor * 3, 400)
    print("%d blocks of %d ms; floor ~%d, gate %d"
          % (len(b), BLOCK_MS, floor, gate))

    events, run = [], []
    for t, rms, freq in b:
        if rms > gate:
            run.append((t, rms, freq))
        else:
            if len(run) >= 2:
                events.append(run)
            run = []
    if len(run) >= 2:
        events.append(run)
    print("%d candidate events" % len(events))

    shown = 0
    for ev in events:
        if ev[0][0] < start:
            continue
        dur = (ev[-1][0] - ev[0][0]) + BLOCK_MS / 1000.0
        fs = [f for _t, _r, f in ev]
        print("  t=%7.2f  %5.0f ms  freq %5.0f..%5.0f Hz  divisor %4d..%-4d  "
              "peak %5d" % (ev[0][0], dur * 1000, min(fs), max(fs),
                            divisor(max(fs)), divisor(min(fs)),
                            max(r for _t, r, _f in ev)))
        shown += 1
        if shown >= limit:
            break


if __name__ == "__main__":
    main()
