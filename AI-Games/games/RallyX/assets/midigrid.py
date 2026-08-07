"""Work out what grid the MIDI actually uses before quantizing to it."""
import sys
sys.argv = ['x', 'newrallyx.mid']
exec(open('midiscan.py').read().split('for us in tempos')[0])
from collections import Counter

DIV = div
for ti in (1, 2):
    name, notes = tracks[ti]
    notes.sort()
    print("track %d: %d notes" % (ti, len(notes)))
    # where do note starts fall inside a beat?
    pos = Counter(n[0] % DIV for n in notes)
    print("  start offsets within a beat (of %d ticks):" % DIV)
    for off, c in sorted(pos.items()):
        frac = off / float(DIV)
        print("     %4d (%.3f beat) x%d" % (off, frac, c))
    durs = Counter(n[1] - n[0] for n in notes)
    print("  durations:", ", ".join("%d(x%d)" % (d, c) for d, c in sorted(durs.items())[:8]))
    print()
