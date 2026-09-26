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
    native_blanking = BLANKING.replace('nes_def', 'nes_def_raw').replace('nes_chrup', 'nes_chrraw')
    cases = [
        ("native tile upload during play blanks rendering", native_blanking, 1),
        ("the shipped shape -- upload behind its own WAIT", GOOD, 0),
        ("no WAIT: the pass's pokes flush with the upload", NO_WAIT, 1),
        ("nes_def during play: rendering off for two frames", BLANKING, 1),
    ]
    # A ROUTINE WHOSE LAST LINE IS A DIRECTIVE. Keystone's title_setup ends
    # `#if NES / GOTO ... / #else / GOTO ... / #endif`; reading `#endif` as a
    # statement that can complete walked it into setup_font and failed the build
    # on a nes_def that no frame reaches. The second case keeps the fix honest:
    # when the NES branch really does complete, the fall-through is real.
    def tail(nes_branch):
        return GOOD.replace("\tGOSUB esc_tick\n", "\tGOSUB esc_tick\n\tGOSUB tailr\n") + (
            "\ntailr:\n#if NES\n%s\n#else\n\tGOTO main\n#endif\n"
            "boot_only:\n\tGOSUB nes_def\n\tRETURN\n" % nes_branch)
    cases.extend([
        ("#endif after a GOTO does not fall through", tail("\tGOTO main"), 0),
        ("#endif after a completing NES branch does", tail("\tx = 1"), 1),
    ])
    cases.extend([
        ("looped elevator batch fits", SHELL %
         "\tWAIT\n\tFOR clv = 0 TO 2\n\tSCREEN tiles,0,0,4,4,4\n\tNEXT clv\n\tWAIT\n", 0),
        ("four looped doors exceed vblank", SHELL %
         "\tWAIT\n\tFOR clv = 0 TO 3\n\tSCREEN tiles,0,0,4,4,4\n\tNEXT clv\n\tWAIT\n", 1),
        ("row descriptor overhead must count", SHELL %
         "\tWAIT\n\tSCREEN tiles,0,0,4,12,4\n\tSCREEN tiles,0,0,16,1,16\n", 0),
        ("extra row descriptor pushes batch over budget", SHELL %
         "\tWAIT\n\tSCREEN tiles,0,0,4,12,4\n\tSCREEN tiles,0,0,28,1,28\n", 1),
    ])
    for label, text, want in cases:
        got = run(text)
        mark = "ok  " if got == want else "FAIL"
        if got != want:
            ok = False
        print("%s: %-52s  want %d, got %d" % (mark, label, want, got))

    # Two 48-byte copies actually fit: 2*(50+48*14) = 1444 cycles.
    # Three do not, and the region model must reject that aggregate.
    for text, want in [(FAKE_SPLIT, 0),
                       (FAKE_SPLIT.replace('\tRETURN',
                        '\tncnt = 3\n\tGOSUB nes_escd\n\tRETURN'), 1)]:
        got = run(text)
        if got != want:
            ok = False
            print('FAIL: aggregate upload budget: want %d, got %d' % (want, got))

    if not ok:
        print("checkvblank did not reject a form that shipped the flash")
        return 1
    print("checkvblank rejects both defective forms and accepts the current one")
    return 0


if __name__ == "__main__":
    sys.exit(main())
