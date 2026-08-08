#!/usr/bin/env python3
"""Post-build ROM audit for the TI-99 cart: fail LOUDLY on silent truncation.

WHY THIS EXISTS. linkticart builds the cart as three loader pages, each
carrying 8112 bytes of the program image that gets copied to RAM, and then
"any excess is discarded" -- silently, with no warning from any tool in the
chain. The program image spans >A000..>FFFF (24,576 bytes) but only 24,336
of those can be carried, so a program that grows past the cap loses whatever
sits at the top of RAM and nothing says a word.

That is not hypothetical: a change that moved 3.6 KB of colour tables out of
a bank and into ~400 bytes of code cut 229 bytes off the END OF THE MUSIC.
The cart built, the game ran, and the last seven bars played from
uninitialised RAM. The total ROM went DOWN while the build broke.

The lesson the numbers teach: **ROM is not one pool.** The banks have
kilobytes free and cost nothing to fill; the 24,336-byte fixed area holds
every line of code plus the music and font data, and has a couple of hundred
bytes spare. Only the second number is worth optimising, and only code and
gameplay-time data live there.

Cart size is a THIRD, separate thing: pages = 3 loader + one per bank,
rounded UP to a power of two. Nine pages rounds to 128 KB, eight fits 64 KB,
so an almost-empty bank can double the cart on its own.

Run from assets/:  C:\\cygwin64\\bin\\python3.9.exe romcheck.py
Exit code is non-zero if anything was truncated, so a build script can gate
on it.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src")

FIXED_CAP = 24336           # 3 loader pages x 8112 bytes
BANK_SIZE = 8192
RAM_BASE = 0xA000           # the program image is assembled here


def content_len(d):
    """bytes before the trailing 0xFF fill; the last 2 bytes are the bank trailer"""
    i = len(d) - 2
    while i > 0 and d[i - 1] == 0xFF:
        i -= 1
    return i


def data_block(path, label):
    """a DATA BYTE block from a source file, as bytes"""
    t = open(path).read()
    m = re.search(r"^%s:\s*$" % re.escape(label), t, re.M)
    if not m:
        return None
    vals = []
    for line in t[m.end():].split("\n"):
        s = line.strip()
        if not s or s.startswith("'"):
            continue
        if not s.upper().startswith("DATA BYTE"):
            break
        for v in s[len("DATA BYTE"):].split("'")[0].split(","):
            v = v.strip()
            if v:
                vals.append(int(v[1:], 16) if v.startswith("$") else int(v))
    return bytes(vals)


fail = []
b0 = open(os.path.join(SRC, "RALLYX_b0.bin"), "rb").read()
image = b0[16384:]                       # >A000 upward
used = content_len(image)

print("FIXED AREA  (all code + music + font; copied to RAM, cap %d)" % FIXED_CAP)
print("   used %5d   free %5d   (%.1f%%)" % (used, FIXED_CAP - used,
                                             100.0 * used / FIXED_CAP))
if used > FIXED_CAP:
    fail.append("fixed area is %d bytes OVER the cap -- linkticart has silently "
                "discarded the top %d bytes of the program image (whatever the "
                "assembler placed nearest >FFFF: usually the last DATA block)"
                % (used - FIXED_CAP, used - FIXED_CAP))

# anything real in the discarded tail is proof, not inference
dropped = image[FIXED_CAP:]
live = sum(1 for b in dropped if b != 0xFF)
if live > 2:                             # 2 = the bank trailer word
    fail.append("%d non-padding bytes sit in the DISCARDED region >%04X..>FFFF"
                % (live, RAM_BASE + FIXED_CAP))

print()
print("BANKS")
nb = 0
while True:
    p = os.path.join(SRC, "RALLYX_b%d.bin" % (nb + 3))
    if not os.path.isfile(p):
        break
    d = open(p, "rb").read()
    print("   BANK %d   used %5d / %d   free %5d"
          % (nb + 1, content_len(d), BANK_SIZE, BANK_SIZE - content_len(d)))
    nb += 1

pages = 3 + nb
size = 4
while size < pages:
    size *= 2
print()
print("   %d pages (3 loader + %d banks)  ->  cart %d KB" % (pages, nb, size * 8))
if pages < size:
    print("   NOTE: %d page(s) of pure padding. Merging a thinly-used bank into"
          % (size - pages))
    print("         another would drop the cart to %d KB." % (size * 4))

# the data most at risk is whatever the linker put last: verify it round-trips
cart = open(os.path.join(SRC, "RALLYX_8.bin"), "rb").read()
print()
print("CONTENT CHECK (blocks that live in the fixed area)")
for path, label in (("music.bas", "mus_song"), ("music.bas", "mus_freq"),
                    ("minifont.bas", "mini_font")):
    blk = data_block(os.path.join(SRC, path), label)
    if not blk:
        continue
    ok = cart.find(blk) >= 0
    print("   %-10s %4d bytes  %s" % (label, len(blk), "present" if ok else "TRUNCATED"))
    if not ok:
        kept = 0
        for n in range(len(blk), 0, -8):
            if cart.find(blk[:n]) >= 0:
                kept = n
                break
        fail.append("%s is cut short in the cart: only %d of %d bytes survive"
                    % (label, kept, len(blk)))

print()
if fail:
    print("FAILED:")
    for f in fail:
        print("  * %s" % f)
    sys.exit(1)
print("OK -- nothing truncated.")
