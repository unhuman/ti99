#!/usr/bin/env python3
"""What SHAPE is each effect -- rising, falling, warbling, or steady?

THE SHAPE IS THE DESIGN AND THE PITCH IS THE DETAIL. A reward rises and a penalty
falls, and a player reads that before they read any particular note; get it
backwards and no amount of correct frequencies will save the effect. So this
walks each event and reports where the pitch GOES, rather than where it is.

WHAT A RECORDING CANNOT TELL YOU, and it is worth being blunt about because it
changes how the output should be used: a recording says what the chip did, never
WHY. A falling run recurring every fifteen seconds fits a hit or a prize being
collected equally well, and nothing in the audio distinguishes them. The honest
move is to file an effect by its shape, build BOTH it and its mirror as
candidates, and let someone decide by ear which way round the game wanted it.
That is what games/colecosounds does with its categories 3 and 4.

Run:  python3 sfxshape.py FILE.wav [GATE] [MIN_MS] [LIMIT] [START]

GATE defaults to 2500, which on a typical longplay skips the footsteps and keeps
the effects; lower it to about 1200 to see the steps and ticks as well.

The WAV must be mono. `ffmpeg -i in.m4a -ac 1 -ar 44100 out.wav`.
"""
import audioop
import os
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sfxpitch                                          # noqa: E402

BLOCK = 0.02


def rms_track(path):
    w = wave.open(path, "rb")
    rate, width = w.getframerate(), w.getsampwidth()
    if w.getnchannels() != 1:
        sys.exit("sfxshape: %s is not mono -- convert with ffmpeg -ac 1" % path)
    n = int(rate * BLOCK)
    out, t = [], 0.0
    while True:
        raw = w.readframes(n)
        if len(raw) < n * width:
            break
        out.append((t, audioop.rms(raw, width)))
        t += BLOCK
    w.close()
    return out


def events(track, gate, minlen, maxgap=2):
    """Loud stretches, allowing a couple of quiet blocks inside one effect.

    maxgap matters: a warble dips in level as it changes note, and without a
    little tolerance one effect is reported as four.
    """
    out, run, gap = [], [], 0
    for t, r in track:
        if r > gate:
            run.append((t, r))
            gap = 0
        elif run:
            gap += 1
            if gap > maxgap:
                if len(run) >= minlen:
                    out.append(run)
                run, gap = [], 0
    if len(run) >= minlen:
        out.append(run)
    return out


def shape(divs):
    """One word for where the pitch goes. REMEMBER DIVISORS RUN BACKWARDS:
    a SMALLER divisor is a HIGHER note, so a falling divisor is a rising pitch.
    This repo has been caught by that more than once."""
    if len(divs) < 2:
        return "blip"
    lo, hi = min(divs), max(divs)
    if hi - lo <= max(2, lo // 20):
        return "steady"
    turns = sum(1 for i in range(1, len(divs) - 1)
                if (divs[i] - divs[i - 1]) * (divs[i + 1] - divs[i]) < 0)
    if turns >= 2:
        return "warble"
    return "rising" if divs[-1] < divs[0] else "falling"


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__.strip().split("Run:")[1].strip())
    path = sys.argv[1]
    gate = int(sys.argv[2]) if len(sys.argv) > 2 else 2500
    minms = float(sys.argv[3]) if len(sys.argv) > 3 else 120
    limit = int(sys.argv[4]) if len(sys.argv) > 4 else 30
    skip = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0

    evs = events(rms_track(path), gate, int(minms / 1000.0 / BLOCK))
    print("%d events over %d rms and %.0f ms" % (len(evs), gate, minms))
    shown = 0
    for ev in evs:
        t0 = ev[0][0]
        if t0 < skip:
            continue
        divs = []
        for i in range(len(ev)):
            got = sfxpitch.top_divisors(path, t0 + i * BLOCK, BLOCK, k=1)
            if got:
                divs.append(got[0][0])
        if not divs:
            continue
        print("  t=%7.2f %4.0fms %-7s  divisors %s"
              % (t0, len(ev) * BLOCK * 1000, shape(divs),
                 " ".join(str(d) for d in divs[:14])))
        shown += 1
        if shown >= limit:
            break


if __name__ == "__main__":
    main()
