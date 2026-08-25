#!/usr/bin/env python3
"""Post-build TI-99 ROM audit for BUST-A-BOBBLE: fail LOUDLY on silent truncation.

linkticart carries the program image (>A000..>FFFF) in three loader pages of
8112 bytes = 24,336 bytes, and DISCARDS any excess without a word from any tool
in the chain. The symptom is missing DATA at the top of RAM -- not a build
error -- so this has to be measured, every build.

The raw xas99 `-b` image starts at >6000, so the program image begins 16,384
bytes in. A `.bin` bigger than 24,336 is therefore NOT automatically over the
cap; subtract the >6000..>9FFF part first. (Getting that wrong reads as a
5,964-byte overflow on a build with 10 KB free.)

HANDLES BOTH BUILD SHAPES. A flat build leaves one `BUSTABOB.bin`; a build that
uses `BANK` leaves `BUSTABOB_b0.bin` (the >6000..>FFFF image), two small stub
pages b1/b2, and one file per bank from b3 up. build-ti.sh's own size guard only
covers the flat path -- in RALLY-X the banked path had no check at all, and that
is exactly how 229 bytes were cut off the end of the music with every tool in the
chain reporting success. So this script must work on whichever shape it finds,
and must never quietly skip.

THREE SEPARATE BUDGETS, per CLAUDE.md 3A:
  1. the 24,336-byte FIXED AREA -- all code, plus any data read during a frame
     (the music tables: the player refills the sound chip from the vblank ISR,
     where bank switching is not safe). This is the only scarce one.
  2. BANKS -- 8 KB each, typically half empty.
  3. CART SIZE -- 3 loader pages + one page per bank, rounded UP to a power of
     two. The first bank is free (we round to 4 pages either way); a second one
     takes us to 5 pages, which rounds to 8 = 64 KB. So banked data belongs in
     the bank that already exists, not in a new one.

Run:  python3 romcheck.py     Exit code is non-zero if anything overflowed.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src")

FIXED_CAP = 24336           # 3 loader pages x 8112 bytes
BANK_SIZE = 8192
RAM_BASE = 0xA000           # where the program image is assembled
CART_BASE = 0x6000          # where the raw xas99 image starts
SKIP = RAM_BASE - CART_BASE  # 16384

# Which cart to audit. BUSTABOB is the arcade set, BUSTAB2 the expert one; they
# are separate cartridges built from the same source, so each has its own bank
# files and its own packed image to check.
_args = [a for a in sys.argv[1:] if not a.startswith("-")]
NAME = _args[0] if _args else "BUSTABOB"

# Blocks worth naming individually. Truncation always eats the END of the program
# image, so what matters for a fixed-area block is not "is it there" but "does it
# END inside the cap" -- which is checked by offset, not by searching the cart.
# NOTHING IS REQUIRED IN THE FIXED AREA ANY MORE. The music tables used to be
# listed here and asserted to END inside the cap, because the vblank ISR reads them
# and bank switching in an ISR is unsafe. They now live in the bank with everything
# else data-shaped: the hazard is bank SWITCHING, and this cart selects bank 1 once
# at startup and never switches, so bank 1 is permanently mapped.
#
# The guard INVERTS rather than disappears. What has to be checked now is the
# premise: that there is exactly ONE bank. With two, the ISR could fire while the
# other page is selected and read its notes out of the wrong ROM, intermittently,
# and nothing else in the chain would notice.
FIXED_BLOCKS = ()

# WHICH LEVEL FILE THIS CART CARRIES. The two carts are the same engine over
# different data, so checking BUSTAB2 against levels.bas reports every block as
# truncated -- correctly, in the sense that those bytes really are absent, and
# uselessly, in the sense that they were never supposed to be there. Defaults to
# the arcade set; --expert switches to levels2.bas.
LEVELS = "levels.bas"
if "--expert" in sys.argv:
    LEVELS = "levels2.bas"
elif "--both" in sys.argv:
    LEVELS = "levels12.bas"   # the combined cart: one table of 80
BANKED_BLOCKS = ((LEVELS, "pb_lay"), (LEVELS, "pb_seq"), (LEVELS, "pb_meta"),
                 ("music.bas", "mus_song"), ("music.bas", "mus_freq"))


def strip_fill(d):
    """index after the last byte that is not 0xFF fill"""
    i = len(d)
    while i > 0 and d[i - 1] == 0xFF:
        i -= 1
    return i


def page_content(d):
    """Real content of a linkticart page image. Every page ends with a 2-byte
    trailer (the bank-switch address word, e.g. >6006) sitting past the 0xFF
    fill, so stripping fill alone reports a page as full to the last byte."""
    return strip_fill(d[:-2]) if len(d) > 2 else len(d)


def data_block(path, label):
    """a DATA BYTE block from a source file, as bytes"""
    full = os.path.join(SRC, path)
    if not os.path.isfile(full):
        return None
    t = open(full, encoding="utf-8").read()
    # A label may carry a trailing comment ("mus_song:  ' one line per step") --
    # anchoring on `label:\s*$` silently found nothing and the block was skipped
    # without a word, which is the one thing an audit must never do.
    m = re.search(r"^%s:[ \t]*(?:'.*)?$" % re.escape(label), t, re.M)
    if not m:
        sys.stderr.write("warning: label %s: not found in src/%s\n" % (label, path))
        return None
    vals = []
    for line in t[m.end():].split("\n"):
        s = line.strip()
        if not s or s.startswith("'"):
            continue
        if not s.upper().startswith("DATA"):
            break
        body = s.split(None, 1)[1]
        if body.upper().startswith("BYTE"):
            body = body[4:]
        for v in body.split("'")[0].split(","):
            v = v.strip()
            if v:
                vals.append(int(v[1:], 16) if v.startswith("$") else int(v))
    return bytes(vals)


def misaligned_word_tables(name):
    """Word-indexed tables that resolved to an ODD address.

    THE TMS9900 SILENTLY IGNORES THE LOW BIT OF A WORD ADDRESS. `mov *r0,@dst`
    from an odd address reads the word BELOW it -- no fault, no warning -- so a
    word table on an odd address reads back shifted one byte, for ever.

    A table lands odd when an odd-length `DATA BYTE` block precedes it: CVBasic
    emits `even` after its own string literals but not after a hand-written byte
    run. A 33-byte marquee table did exactly this and put #aimdx on >68FB, so
    #aimdx(0) read 3840 instead of 0 -- the aim guide dots landed 60px apart
    across the HUD and a "vertical" shot left at a severe angle and the wrong
    speed. Nothing in cvbasic -> xas99 -> linkticart said a word.

    Rather than guess which blocks are odd, this finds the reads that actually
    matter -- `ai r0,<label>` immediately followed by `mov *r0`, which is how the
    compiler indexes a word table -- and takes each label's RESOLVED address out
    of the assembler listing. No heuristics and no false positives: an even
    address is correct by construction, an odd one is always this bug.
    """
    path = os.path.join(SRC, "%s.txt" % name)
    if not os.path.isfile(path):
        return None
    lines = open(path, encoding="latin-1").read().split("\n")
    bad, seen = {}, set()
    for i, line in enumerate(lines):
        m = re.search(r"ai\s+r0,(cvb_+\w+)", line)
        if not m:
            continue
        # the operand word is on the continuation line that follows
        if i + 1 >= len(lines):
            continue
        w = re.match(r"\s+([0-9A-Fa-f]{4})\s+([0-9A-Fa-f]{4})", lines[i + 1])
        if not w:
            continue
        # and the next instruction must be the word-indexed read itself
        nxt = " ".join(lines[i + 2:i + 4])
        if "mov *r0" not in nxt:
            continue
        label, addr = m.group(1), int(w.group(2), 16)
        seen.add(label)
        if addr % 2:
            bad[label] = addr
    return sorted(bad.items()), len(seen)


def main():
    fail = []
    banked = os.path.isfile(os.path.join(SRC, "%s_b0.bin" % NAME))
    first = "%s_b0.bin" % NAME if banked else "%s.bin" % NAME
    path = os.path.join(SRC, first)
    if not os.path.isfile(path):
        sys.stderr.write("error: neither %s.bin nor %s_b0.bin in src/ -- "
                         "run build-ti.sh first\n" % (NAME, NAME))
        return 2

    raw = open(path, "rb").read()
    if len(raw) <= SKIP:
        sys.stderr.write("error: %s is only %d bytes, entirely below >A000. The "
                         "build did not produce a program image.\n" % (first, len(raw)))
        return 2
    image = raw[SKIP:]
    used = page_content(image) if banked else strip_fill(image)
    free = FIXED_CAP - used

    print("%s -- TI-99/4A ROM audit   (%s build, from %s)"
          % (NAME, "BANKED" if banked else "flat", first))
    print()
    print("FIXED AREA  (all code + music + font; copied to RAM at >%04X)" % RAM_BASE)
    print("  used        %6d B   of %d   (%.1f%%)" % (used, FIXED_CAP,
                                                      100.0 * used / FIXED_CAP))
    print("  free        %6d B" % free)

    if used > FIXED_CAP:
        dropped = image[FIXED_CAP:]
        live = sum(1 for b in dropped if b != 0xFF)
        fail.append("the fixed area is %d bytes OVER the cap -- linkticart has "
                    "silently discarded the top of the program image (whatever the "
                    "assembler placed nearest >FFFF, usually the last DATA block); "
                    "%d non-padding bytes sit in the discarded region"
                    % (used - FIXED_CAP, live))

    # Name the fixed-area blocks and prove each ENDS inside the cap. This is the
    # question that matters -- a block can be present in the image and still have
    # its tail in the region linkticart throws away.
    print()
    print("  blocks that must stay in the fixed area (music: read from the ISR)")
    for src, label in FIXED_BLOCKS:
        blk = data_block(src, label)
        if not blk:
            continue
        off = image.find(blk)
        if off < 0:
            fail.append("%s is not in the program image at all -- it may have been "
                        "moved into a BANK, which would break the music player: it "
                        "runs in the vblank ISR, where bank switching is unsafe"
                        % label)
            print("    %-9s %4d B   NOT FOUND in the fixed area" % (label, len(blk)))
            continue
        end = off + len(blk)
        ok = end <= FIXED_CAP
        print("    %-9s %4d B   ends at %5d of %d   %s"
              % (label, len(blk), end, FIXED_CAP, "ok" if ok else "PAST THE CAP"))
        if not ok:
            fail.append("%s ends at %d, past the %d-byte cap: its last %d bytes are "
                        "discarded" % (label, end, FIXED_CAP, end - FIXED_CAP))

    # --- banks ---------------------------------------------------------------
    nb = 0
    if banked:
        print()
        print("BANKS  (8 KB each; only data NOT read during a frame belongs here)")
        while True:
            p = os.path.join(SRC, "%s_b%d.bin" % (NAME, nb + 3))
            if not os.path.isfile(p):
                break
            d = open(p, "rb").read()
            c = page_content(d)
            print("  BANK %d      used %5d / %d   free %5d"
                  % (nb + 1, c, BANK_SIZE, BANK_SIZE - c))
            nb += 1
        # THE ONE-BANK PREMISE, checked because the music now depends on it.
        # mus_song/mus_freq live in the bank, and that is only safe while bank 1 is
        # selected once at startup and never switched -- with a second bank the
        # vblank ISR could fire while the other page is mapped and read its note
        # tables out of the wrong ROM. Intermittent, unreproducible, and invisible
        # to every other tool in the chain. A second bank is not a size decision
        # any more.
        if nb > 1:
            fail.append("this build has %d banks. The music tables live in bank 1 "
                        "and the vblank ISR reads them, which is only safe while "
                        "there is exactly ONE bank permanently mapped. Move "
                        "music.bas back above the BANK directive (and find the "
                        "fixed area 660 bytes) before shipping this." % nb)
        if nb == 0:
            fail.append("the build emitted %s_b0.bin (a banked layout) but no bank "
                        "files from b3 up -- the BANK data went nowhere" % NAME)

    pages = 3 + nb
    size = 4
    while size < pages:
        size *= 2
    print()
    print("CART        %d pages (3 loader + %d bank%s)  ->  %d KB"
          % (pages, nb, "" if nb == 1 else "s", size * 8))
    if pages < size:
        print("            %d page(s) of pure padding -- room for %d more bank(s) "
              "before the cart doubles to %d KB."
              % (size - pages, size - pages, size * 16))

    # --- did the banked data actually survive into the packed cart? ----------
    cart_path = os.path.join(SRC, "%s_8.bin" % NAME)
    if banked and os.path.isfile(cart_path):
        cart = open(cart_path, "rb").read()
        print()
        print("CONTENT CHECK  (banked blocks, searched in the packed cart)")
        for src, label in BANKED_BLOCKS:
            blk = data_block(src, label)
            if not blk:
                continue
            # Bank pages are packed whole, so a banked block is contiguous in the
            # cart file and a plain search is sound. (It would NOT be for a
            # fixed-area block: those are split across loader pages, which is why
            # those are checked by offset above instead.)
            ok = cart.find(blk) >= 0
            print("    %-9s %4d B   %s" % (label, len(blk),
                                           "present" if ok else "TRUNCATED"))
            if not ok:
                kept = 0
                for n in range(len(blk) - 8, 0, -8):
                    if cart.find(blk[:n]) >= 0:
                        kept = n
                        break
                fail.append("%s does not round-trip into the cart: %d of %d bytes "
                            "survive" % (label, kept, len(blk)))

    # --- word tables on odd addresses (read shifted, silently) ---------------
    res = misaligned_word_tables(NAME)
    if res is not None:
        bad, total = res
        print()
        print("ALIGNMENT  (word-indexed tables; an odd address reads shifted one byte)")
        if bad:
            for label, addr in bad:
                print("    %-16s >%04X  ODD" % (label, addr))
            fail.append("%d word table(s) resolved to an ODD address. The TMS9900 "
                        "ignores the low bit of a word address, so `mov *r0` reads "
                        "the word BELOW each entry -- the whole table comes back "
                        "shifted one byte, with no error from any tool. The cause is "
                        "an odd-length DATA BYTE block earlier in the same segment "
                        "(CVBasic emits no `even` after one). Pad it to even."
                        % len(bad))
        else:
            print("    all %d word-indexed table(s) on even addresses" % total)

    print()
    if fail:
        print("FAILED:")
        for f in fail:
            print("  * %s" % f)
        return 1
    print("OK -- nothing truncated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
