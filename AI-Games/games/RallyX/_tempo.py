"""Patch RALLYX.bas to a given music tempo, for the A/B experiment ROMs.

MUSTICK is frames per SIXTEENTH, so the tune's BPM is 900/MUSTICK and only whole
frames are available: 6 -> 150, 5 -> 180, 4 -> 225. Those are big jumps. The
half-frame tempi in between come the way Bust-A-Bobble got them -- ALTERNATE the
tick between two lengths and let the average be the tempo. 5,6,5,6 averages 5.5,
which is 164 BPM. An integer tempo is the degenerate case where both halves are
equal, so one mechanism covers every variant.
"""
import re
import sys

first, pair = int(sys.argv[1]), int(sys.argv[2])
P = "src/RALLYX.bas"
s = open(P, encoding="utf-8").read()

s = s.replace(
    "	CONST MUSTICK = 6	' frames per step = one sixteenth at 151 BPM",
    "	CONST MUSTICK = %d	' EXPERIMENT: first half of the tick pair\n"
    "	CONST MUSPAIR = %d	' the two halves sum to this -- average %.1f frames"
    % (first, pair, pair / 2.0), 1)

# The tick alternates, so it lives in a variable that mus_start seeds.
old = "	#mup = 0\n	mut = 1\n"
assert old in s
s = s.replace(old, "	#mup = 0\n	mut = 1\n	mustk = MUSTICK\n", 1)

old = "	mut = MUSTICK\n	GOSUB mus_step"
assert old in s
s = s.replace(old, "	mut = mustk\n	mustk = MUSPAIR - mustk\n	GOSUB mus_step", 1)

open(P, "w", encoding="utf-8", newline="\n").write(s)
print("  tempo -> %d/%d frames, average %.1f = %d BPM"
      % (first, pair - first, pair / 2.0, round(1800.0 / pair)))
