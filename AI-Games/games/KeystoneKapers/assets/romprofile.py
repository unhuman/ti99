#!/usr/bin/env python3
"""Where the TI fixed area actually goes -- bytes per routine, measured.

THE FIXED AREA IS THE ONLY SCARCE ROM BUDGET (CLAUDE.md 3A): all code, plus any
data read during a frame, capped at 24,336 bytes. Guessing which routine is fat
has been wrong every time it has been tried in this repo, so this measures it
instead.

It reads the xas99 LISTING (src/KEYSTONE.txt, produced by build-ti.sh's `-L`),
which carries a real address for every emitted word. Each CVBasic label becomes a
`cvb_NAME` line in the assembly, so a routine's size is the distance from its
first emitted address to the next label's -- attributed from ADDRESSES rather
than counted from source lines, which would weight comments and blanks equally
with code.

A LABEL LINE IN THE LISTING HAS NO ADDRESS COLUMN of its own (xas99 prints an
address only for lines that emit bytes), so the label is bound to the first
emitted address that follows it. That is the whole trick, and getting it wrong
silently attributes every byte to `<runtime>`.

Runtime support (SETRD, WRTVRM, the music player, ...) has no `cvb_` label and is
reported as one lump, so the game's own share is not flattered.

Usage:
    python3 romprofile.py [-n 40] [listing]
"""

import os
import re
import sys

# "3408               cvb_TITLE_DRAW"  -- line number, no address, a bare label
LABEL = re.compile(r"^\s*\d+\s{2,}([A-Za-z_][A-Za-z0-9_]*)\s*$")
# "2559 AA04 B084     \tdata cvb_TITLE_DRAW"  -- line number, address, word
EMIT = re.compile(r"^\s*\d+\s+([0-9A-Fa-f]{4})\s+([0-9A-Fa-f]{4})\s")

WINDOW = 0xA000         # the cart's RAM-resident window; below this is setup


def collect(path):
    """[(address, label)] -- each label bound to its first emitted address.

    ONLY `cvb_` LABELS ARE BOUND, and that is the point rather than a filter.
    CVBasic emits its own internal labels between the named ones -- one per
    jump target, several per routine -- so binding every label would credit a
    routine with only the bytes up to its first `IF`. Ignoring them lets each
    span run from one named routine to the next, which is what a routine costs.
    """
    out = []
    pending = None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = LABEL.match(line)
            if m:
                if m.group(1).startswith("cvb_"):
                    pending = m.group(1)
                continue
            m = EMIT.match(line)
            if not m:
                continue
            addr = int(m.group(1), 16)
            if addr < WINDOW:
                continue
            if pending is not None:
                out.append((addr, pending))
                pending = None
            elif not out:
                out.append((addr, "<runtime>"))
    return out


def main():
    args = list(sys.argv[1:])
    top = 40
    if "-n" in args:
        i = args.index("-n")
        top = int(args[i + 1])
        del args[i:i + 2]
    here = os.path.dirname(os.path.abspath(__file__))
    path = args[0] if args else os.path.join(here, "..", "src", "KEYSTONE.txt")
    if not os.path.exists(path):
        sys.exit("no listing at %s -- run build-ti.sh first" % path)

    marks = collect(path)
    if not marks:
        sys.exit("no labelled addresses found -- is this an xas99 listing?")

    # ONE PASS THROUGH THE WINDOW ONLY. Banked data assembles into the same
    # >A000 window, so stop at the first backwards jump -- that is the bank
    # boundary, and counting past it would add the bank to the fixed area.
    seq = []
    prev = -1
    for addr, label in marks:
        if addr < prev:
            break
        seq.append((addr, label))
        prev = addr

    sizes = {}
    for i, (addr, label) in enumerate(seq):
        end = seq[i + 1][0] if i + 1 < len(seq) else addr
        if end > addr:
            sizes[label] = sizes.get(label, 0) + (end - addr)

    game = {k: v for k, v in sizes.items() if k.startswith("cvb_")}
    other = {k: v for k, v in sizes.items() if not k.startswith("cvb_")}
    gtot, otot = sum(game.values()), sum(other.values())

    print("Attributed %d bytes between >%04X and >%04X"
          % (gtot + otot, seq[0][0], seq[-1][0]))
    print("  runtime + support (no cvb_ label): %6d  in %d labels"
          % (otot, len(other)))
    print("  the game's own routines:           %6d  in %d labels"
          % (gtot, len(game)))
    print()
    print("%-32s %7s  %5s" % ("routine", "bytes", "share"))
    print("-" * 48)
    for name, n in sorted(game.items(), key=lambda kv: -kv[1])[:top]:
        print("%-32s %7d  %4.1f%%" % (name[4:].lower(), n, 100.0 * n / gtot))
    print()
    print("%-32s %7d" % ("(the other %d routines)" % max(0, len(game) - top),
                         gtot - sum(sorted(game.values(), reverse=True)[:top])))


if __name__ == "__main__":
    main()
