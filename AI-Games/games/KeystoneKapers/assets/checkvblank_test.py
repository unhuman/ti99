#!/usr/bin/env python3
"""checkvblank.py, run against the code that actually shipped the flash.

A CHECK THAT HAS NEVER FAILED IS NOT KNOWN TO BE A CHECK. This one passes on the
current source, which proves nothing on its own -- the first version of
checklayout.py passed on the very bug it was written for, and CLAUDE.md keeps
that as a standing warning. So the two forms that were on the machine when the
screen was flashing are typed out here and fed to it, and the run is only
believed if it REJECTS both.

  1. esc_tick with no WAIT in front of its upload. This is what shipped for
     months: 96 bytes queued behind the pass's radar and HUD writes, all flushed
     in one vblank, the copy running past the end of it.

  2. esc_stand going through nes_def during play. This is the older form, which
     turned rendering off on every mount and dismount.

Run:  python3 checkvblank_test.py
"""

import os
import sys
import tempfile

import checkvblank as cv


def run(text):
    fd, path = tempfile.mkstemp(suffix=".bas", text=True)
    os.close(fd)
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        return cv.main(path, quiet=True)
    finally:
        os.unlink(path)


SHELL = """\
main:
\tWAIT
\tGOSUB scan_tick
\tGOSUB esc_tick
\tGOTO main

scan_tick:
\tVPOKE #sda,1
\tRETURN

nes_def:
\tASM JSR nes_chrup
\tRETURN

nes_escd:
\tASM JSR nes_chrq
\tRETURN

esc_tick:
%s
\tRETURN
"""

GOOD = SHELL % (
    "\tWAIT\n"
    "\tnchr = 110\n"
    "\tncnt = 6\n"
    "\tGOSUB nes_escd\n"
)

NO_WAIT = SHELL % (
    "\tnchr = 110\n"
    "\tncnt = 6\n"
    "\tGOSUB nes_escd\n"
)

BLANKING = SHELL % (
    "\tnchr = 110\n"
    "\tncnt = 6\n"
    "\tGOSUB nes_def\n"
)

# AND THE SPLIT THAT IS NOT A FIX. Halving the upload but leaving both halves in
# the same pass with no WAIT between them is the change a reader reaches for
# first, and it does not help: PPUBUF accumulates for the whole pass, so the two
# descriptors flush together and cost what one 96-byte descriptor cost.
FAKE_SPLIT = SHELL % (
    "\tWAIT\n"
    "\tnchr = 110\n"
    "\tncnt = 3\n"
    "\tGOSUB nes_escd\n"
    "\tnchr = 113\n"
    "\tncnt = 3\n"
    "\tGOSUB nes_escd\n"
)


def main():
    ok = True
    cases = [
        ("the shipped shape -- upload behind its own WAIT", GOOD, 0),
        ("no WAIT: the pass's pokes flush with the upload", NO_WAIT, 1),
        ("nes_def during play: rendering off for two frames", BLANKING, 1),
    ]
    for label, text, want in cases:
        got = run(text)
        mark = "ok  " if got == want else "FAIL"
        if got != want:
            ok = False
        print("%s: %-52s  want %d, got %d" % (mark, label, want, got))

    # This one is a REPORT, not an assertion: the checker measures each
    # descriptor on its own, so it cannot see two small ones sharing a vblank.
    # Naming the limit here is what stops a later reader believing it can.
    got = run(FAKE_SPLIT)
    print("note: two 48-byte halves in one pass are NOT caught (got %d) -- the "
          "model is per descriptor, and the halves still share a vblank" % got)

    if not ok:
        print("checkvblank did not reject a form that shipped the flash")
        return 1
    print("checkvblank rejects both defective forms and accepts the current one")
    return 0


if __name__ == "__main__":
    sys.exit(main())
