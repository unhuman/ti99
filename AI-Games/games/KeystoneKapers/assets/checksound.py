#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""snd_off must silence every channel sfx_tick writes and clear every latch it reads.

WHY THIS EXISTS
---------------
`snd_off` is the "stop everything" routine, called between a capture and the next
Krook, on a death, and around the bonus tally. It is a HAND-WRITTEN LIST of
channels and variables, and a hand-written list of things that were added over
time is a list that goes stale silently.

It did, twice, and both shipped:

* The footstep moved from a pair of tones on channel 0 to a burst on the NOISE
  channel when the effects were re-measured off the 2600. `snd_off` still named
  only channels 0, 1 and 2, so a step ringing when Harry was caught hissed
  through the entire bonus tally and stopped only when the next round's first
  footstep happened to reset it.
* The prize arpeggio's counter `spz` was added later than the list and never
  joined it, so a prize collected in the last moments of a round played its
  remaining notes on the first pass of the NEXT round -- a ding over a level
  that had just been drawn.

Neither produced an error, and neither is visible by reading `snd_off`: the
routine looks complete, because nothing in it says what the complete set is.

WHAT IT CHECKS
--------------
Both halves are derived FROM `sfx_tick`, not from a table kept here -- a table
here would go stale exactly like the list it is checking.

1. Every channel `sfx_tick` writes with `SOUND n,...` must appear in `snd_off`
   as an explicit `SOUND n,0,0`.

   Zeroing a decay counter is NOT a substitute and the checker does not accept
   one: the counters emit their note-off only on the pass they reach zero, so
   assigning zero by hand skips the write that would have stopped the sound.

2. Every variable `sfx_tick` tests in a top-level `IF` -- the latches and the
   decay counters, which are exactly the state that can make a sound on a LATER
   pass -- must be assigned zero in `snd_off`.

Run standalone for a report; it exits non-zero on a failure, and both build
scripts run it.
"""

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, os.pardir, 'src', 'KEYSTONE.bas')

# Read inside a top-level IF but not latched state: `swf` is the warble's phase
# and is rewritten from itself every pass it is used. It is cleared anyway (a
# jump after a round break should start on a known note), so this list is
# currently empty -- it exists so that a future genuine per-pass temp can be
# named and reasoned about rather than silently dropped by a loosened rule.
NOT_LATCHED = set()


def routine(lines, name, seen=None):
    """The body of `name:` up to its closing RETURN at statement indent.

    THIS FOLLOWS FALL-THROUGH, and it has to. A routine that runs into the next
    label WITHOUT having returned continues into it at run time -- ordinary
    control flow in CVBasic, not a trick -- and `snd_off` is built on it: it
    silences the channels, zeroes the counters, and falls into `snd_pend`,
    which clears the pending latches. `snd_pend` has its own label so that
    pause_beat can GOSUB just that half.

    Stopping at the label instead reported `snd_off` as never clearing six
    flags it does clear on every call: a FAILURE THAT IS NOT THERE. That is the
    mirror of a check whose scope is narrower than the bug, and it costs the
    same trust -- the dead-label sweep that called `tick_flash` unreachable made
    exactly this mistake, for exactly this reason (CLAUDE.md 3A).

    An unconditional `GOTO` at statement indent does NOT fall through, so that
    ends the body instead.
    """
    seen = set() if seen is None else seen
    if name in seen:
        sys.exit('checksound: fall-through loops back to %s' % name)
    seen.add(name)
    try:
        start = next(i for i, l in enumerate(lines)
                     if l.strip() == name + ':')
    except StopIteration:
        sys.exit('checksound: no routine named %s' % name)
    body = []
    for l in lines[start + 1:]:
        stripped = l.strip()
        if stripped.endswith(':') and not stripped.startswith("'"):
            # Reached the next label with no RETURN -- so control carries on
            # into it. Unless the last thing done was an unconditional jump.
            last = next((s for s in reversed([b.strip() for b in body]) if s
                         and not s.startswith("'")), '')
            if last.startswith('GOTO '):
                break
            return body + routine(lines, stripped[:-1], seen)
        body.append(l)
        if stripped == 'RETURN':
            break
    return body


def strip_comment(line):
    """Drop a trailing comment, respecting quotes. BASIC comments start at '."""
    out = []
    in_str = False
    for ch in line:
        if ch == '"':
            in_str = not in_str
        if ch == "'" and not in_str:
            break
        out.append(ch)
    return ''.join(out)


def main():
    lines = io.open(SRC, encoding='utf-8').read().split('\n')
    tick = [strip_comment(l) for l in routine(lines, 'sfx_tick')]
    off = [strip_comment(l) for l in routine(lines, 'snd_off')]

    # --- 1. channels -------------------------------------------------------
    written = set()
    for l in tick:
        for m in re.finditer(r'\bSOUND\s+(\d+)\s*,', l):
            written.add(int(m.group(1)))

    silenced = set()
    for l in off:
        for m in re.finditer(r'\bSOUND\s+(\d+)\s*,\s*0\s*,\s*0\b', l):
            silenced.add(int(m.group(1)))

    # --- 2. latched state --------------------------------------------------
    # Anything sfx_tick tests in an IF is state it consults on a later pass.
    latched = set()
    for l in tick:
        for m in re.finditer(r'\bIF\s+([a-z][a-z0-9]*)\s*[<>=]', l):
            latched.add(m.group(1))
    latched -= NOT_LATCHED

    cleared = set()
    for l in off:
        m = re.match(r'\s*([a-z][a-z0-9]*)\s*=\s*0\s*$', l)
        if m:
            cleared.add(m.group(1))

    bad = []
    for ch in sorted(written):
        if ch not in silenced:
            bad.append('channel %d is written by sfx_tick and never '
                       'SOUND %d,0,0 in snd_off' % (ch, ch))
    for v in sorted(latched):
        if v not in cleared:
            bad.append('`%s` is tested by sfx_tick and never zeroed in '
                       'snd_off' % v)

    print('checksound: sfx_tick writes channels %s' %
          ', '.join(str(c) for c in sorted(written)))
    print('            snd_off silences channels %s' %
          ', '.join(str(c) for c in sorted(silenced)))
    print('            sfx_tick latches %d variables: %s' %
          (len(latched), ' '.join(sorted(latched))))
    print('            snd_off clears %d of them' %
          len(latched & cleared))

    if bad:
        print('')
        for b in bad:
            print('  FAIL  %s' % b)
        print('')
        print('  A sound that outlives its round is either a channel nobody')
        print('  turned off or a counter nobody reset. snd_off has to name')
        print('  both, and it cannot know what to name unless this list is')
        print('  kept beside sfx_tick.')
        return 1

    print('            OK -- nothing sfx_tick starts can outlive snd_off')
    return 0


if __name__ == '__main__':
    sys.exit(main())
