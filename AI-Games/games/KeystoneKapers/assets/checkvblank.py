#!/usr/bin/env python3
"""No NES vblank may be asked to copy more than it can finish.

THE WHOLE-SCREEN FLASH THIS FILE EXISTS TO PREVENT
--------------------------------------------------
CVBasic's NES runtime does not write video memory when the program asks it to.
`VPOKE`, `PRINT` and `SCREEN` append a DESCRIPTOR to `PPUBUF`, and the NMI
handler empties the whole buffer at the next vblank. Two consequences, and the
second is the one that bites:

  * PPUBUF ACCUMULATES FOR A WHOLE LOOP PASS. Every poke the radar makes, every
    HUD digit and any pattern upload all land in the SAME vblank, however far
    apart they are in the source. Only a `WAIT` divides them.

  * THE HANDLER'S COPY LOOP DOES NOT STOP WHEN VBLANK ENDS. Its inner loop is a
    flat `LDA (ppu_source),Y / STA PPUDATA / INY / BNE`, and it runs to the end
    of the descriptor whatever the raster is doing. Worse than the dropped
    PPUDATA writes -- which is the failure CLAUDE.md already records -- is what
    comes AFTER the copy: `nmi_handler` finishes by writing PPUADDR twice and
    both PPUSCROLL bytes. Done mid-frame, that re-points the PPU's own render
    address and the rest of the frame is drawn from somewhere else.

On screen that is not a missing tile. It is the ENTIRE PICTURE jumping for one
frame, and it was reported over several sessions as "the screen flashes when
Harry gets on and off the escalator" -- which sounds like a sprite or a pattern
bug and is neither. The escalator is simply the one place that queues 96 bytes
every pass.

THE BUDGET, FROM THE PROLOGUE'S OWN INSTRUCTIONS
------------------------------------------------
Cycle counts read off cvbasic_nes_prologue.asm (`nmi_handler`), NTSC:

    vblank                     2273    20 scanlines x 113.667 CPU cycles
    entry + flicker test         ~30    IRQ latency, three pushes, the AND #4
    OAM DMA                      519    LDX/STX SPRRAM plus the 513-cycle DMA
    ppu_pointer test               5
    scroll/PPUCTRL restore        ~40    what must still land inside vblank
    -------------------------------
    left for copying            ~1679

    copy descriptor header        50    .0 through the three INXes at .4
    per byte copied               14    LDA (zp),Y 5 + STA abs 4 + INY 2 + BNE 3
    single-byte descriptor        43    header to .7, then the store and the CPX

So one 96-byte upload is 50 + 96*14 = 1394 cycles and leaves about 285 -- six
single-byte pokes -- for everything else the pass queued. The radar beats that
whenever a dot moves.

WHAT IS CHECKED
---------------
1. NO `GOSUB nes_def` IS REACHABLE FROM `main`. nes_def turns rendering off and
   waits for a vblank the NMI therefore never services, costing about two frames
   with the picture switched off. That is a flash of its own and is only free at
   setup. Harry's standing pose used to go through it on every mount.

2. EVERY LARGE QUEUED UPLOAD HAS A `WAIT` IN FRONT OF IT, so the pass's ordinary
   traffic is flushed first and the upload gets a vblank of its own. "Large" is
   anything over RESERVE cycles short of the budget -- see LARGE_BYTES below.

3. THE SUM OF EVERYTHING QUEUED BETWEEN TWO `WAIT`s FITS IN ONE VBLANK. Rule 2
   measures one descriptor at a time and that is not enough: PPUBUF accumulates,
   so four 64-byte chunks with no WAIT between them cost exactly what one
   256-byte call cost. The self-test used to record this as a known blind spot
   -- "two 48-byte halves in one pass are NOT caught" -- and then `nes_swp16`
   was written, which is four chunks in a row and depends entirely on its WAITs.
   A blind spot stops being acceptable the moment something relies on it.

Reachability is computed from `main` over GOSUB, GOTO and FALL-THROUGH, because
a label whose predecessor can complete is entered without any jump naming it
(CLAUDE.md records a dead-label sweep that called live code dead for exactly
this reason).

Run:  python3 checkvblank.py        exits non-zero if a vblank is overcommitted
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")

VBLANK = 2273
NMI_FIXED = 30 + 519 + 5 + 40
COPY_HEADER = 50
COPY_PER_BYTE = 14
POKE_CYCLES = 43

# HOW MUCH OF THE BUDGET THE REST OF A PASS MAY NEED. A pass that moves the
# radar's two dots, repaints a HUD digit and nudges a sprite queues on the order
# of ten single-byte descriptors; 430 cycles is ten of them. An upload that
# cannot coexist with that has to be given its own vblank.
RESERVE = 10 * POKE_CYCLES
BUDGET = VBLANK - NMI_FIXED
LARGE_BYTES = (BUDGET - RESERVE - COPY_HEADER) // COPY_PER_BYTE

IF_RE = re.compile(r"^\s*IF\b.*\bTHEN\s*$", re.I)
ELSE_RE = re.compile(r"^\s*ELSE\s*$", re.I)
ENDIF_RE = re.compile(r"^\s*END IF\s*$", re.I)

LABEL_RE = re.compile(r"^([a-z_][a-z0-9_]*):")
GOSUB_RE = re.compile(r"\bGOSUB\s+([a-z_][a-z0-9_]*)", re.I)
GOTO_RE = re.compile(r"\bGOTO\s+([a-z_][a-z0-9_]*)", re.I)
NCNT_RE = re.compile(r"^\s*ncnt\s*=\s*(\d+)")
SCREEN_RE = re.compile(
    r"^\s*SCREEN\s+[^,]+,[^,]+,[^,]+,\s*(\d+)\s*,\s*(\d+)\s*,", re.I)
TERMINAL_RE = re.compile(r"^\s*(RETURN|END|GOTO\b)", re.I)


def nes_lines(src):
    """The set of line indices this target actually compiles.

    A CHECKER THAT MODELS ONE MACHINE MUST SKIP THE OTHER'S BRANCHES. The TI
    blits a band in ONE `SCREEN ...,32,5,32` because its VDP takes the write
    synchronously; read literally that is 160 bytes in a vblank that cannot hold
    them, and the first run of this file failed on it. It is not a defect and it
    is not on this machine. Only `#if NES` and unconditional code count.
    """
    out = set()
    branch = []
    for i, ln in enumerate(src):
        st = ln.strip()
        if st.startswith("#if "):
            branch.append("NES" if st[4:].strip() == "NES" else "NOT_NES")
            continue
        if st.startswith("#elif"):
            branch[-1] = "NES" if st[5:].strip() == "NES" else "NOT_NES"
            continue
        if st.startswith("#else"):
            if branch:
                branch[-1] = "NOT_NES" if branch[-1] == "NES" else "NES"
            continue
        if st.startswith("#endif"):
            if branch:
                branch.pop()
            continue
        if "NOT_NES" not in branch:
            out.add(i)
    return out


def statements(src, live_lines):
    """(index, stripped text) for every line this target compiles."""
    for i, ln in enumerate(src):
        if i not in live_lines:
            continue
        st = ln.strip()
        if st and not st.startswith("'"):
            yield i, st


def routines(src):
    """label -> (first line index, last line index) over the whole file."""
    marks = [(i, m.group(1)) for i, ln in enumerate(src)
             for m in [LABEL_RE.match(ln)] if m]
    out = {}
    for n, (i, name) in enumerate(marks):
        end = marks[n + 1][0] if n + 1 < len(marks) else len(src)
        out[name] = (i, end)
    return out, marks


def reachable(src, rts, marks):
    """Labels reachable from `main` over GOSUB, GOTO and fall-through."""
    order = [name for _i, name in marks]
    nxt = dict(zip(order, order[1:]))
    seen = set()
    stack = ["main"]
    while stack:
        name = stack.pop()
        if name in seen or name not in rts:
            continue
        seen.add(name)
        a, b = rts[name]
        last = None
        for i in range(a, b):
            st = src[i].strip()
            if not st or st.startswith("'"):
                continue
            last = st
            for m in GOSUB_RE.finditer(st):
                stack.append(m.group(1))
            for m in GOTO_RE.finditer(st):
                stack.append(m.group(1))
        # FALL-THROUGH. A routine whose last statement can complete simply runs
        # into the label below it -- ordinary control flow in CVBasic, and the
        # only way tick_flash is ever entered.
        if last is not None and not TERMINAL_RE.match(last) and name in nxt:
            stack.append(nxt[name])
    return seen


def owner(rts, i):
    for name, (a, b) in rts.items():
        if a <= i < b:
            return name
    return "<before any label>"


def wait_before(src, rts, i):
    """Is there a WAIT between this line and the top of its routine?

    Only a WAIT clears PPUBUF, so what matters is whether one stands between
    the pass's other traffic and this upload. Searching within the routine is
    the conservative reading: a WAIT further up the call chain would also do,
    but requiring a local one keeps the guarantee where the upload is.
    """
    name = owner(rts, i)
    a = rts.get(name, (0, 0))[0]
    for j in range(i - 1, a - 1, -1):
        if src[j].strip().upper() == "WAIT":
            return True
    return False


def ncnt_before(src, rts, i):
    name = owner(rts, i)
    a = rts.get(name, (0, 0))[0]
    for j in range(i - 1, a - 1, -1):
        m = NCNT_RE.match(src[j])
        if m:
            return int(m.group(1))
    return None


def cycles(nbytes):
    return COPY_HEADER + COPY_PER_BYTE * nbytes


def region_cost(region, prefix=()):
    """Sequential costs add; the arms of one IF take the largest."""
    direct = sum(cycles(nb) for _i, _k, nb, p in region if p == prefix)
    n = len(prefix)
    arms = {}
    for _i, _k, nb, p in region:
        if len(p) > n and p[:n] == prefix:
            arms.setdefault(p[n][0], set()).add(p[n][1])
    for this_if, branches in arms.items():
        direct += max(region_cost(region, prefix + ((this_if, br),))
                      for br in branches)
    return direct


def report_region(name, region, bad):
    if len(region) < 2:
        return                          # one descriptor is rule 2's business
    total = region_cost(region)
    if total > BUDGET:
        nb = sum(b for _i, _k, b, _p in region)
        bad.append(
            "line %d (%s): %d queued uploads share one vblank -- %d bytes, %d "
            "cycles against the %d available. PPUBUF is not flushed until the "
            "NMI runs, so splitting an upload buys nothing unless a WAIT goes "
            "between the pieces."
            % (region[0][0] + 1, name, len(region), nb, total, BUDGET))


def main(path=None, quiet=False):
    src = open(path or BAS, encoding="utf-8").read().split("\n")
    rts, marks = routines(src)
    live_lines = nes_lines(src)
    live = reachable(src, rts, marks)
    bad = []
    sites = []

    for i, st in statements(src, live_lines):
        name = owner(rts, i)
        if name not in live:
            continue

        if re.match(r"^GOSUB\s+nes_def(?:_raw)?\b", st):
            bad.append(
                "line %d (%s): GOSUB nes_def is reachable from main. It turns "
                "rendering OFF and waits for a vblank the NMI never services -- "
                "about two frames of blank screen, every time it runs. Queue it "
                "with nes_escd instead, or make the art resident."
                % (i + 1, name))
            continue

        if re.match(r"^GOSUB\s+nes_escd\b", st):
            n = ncnt_before(src, rts, i)
            if n is None:
                bad.append("line %d (%s): GOSUB nes_escd with no `ncnt = ` above "
                           "it in the same routine -- the size cannot be checked"
                           % (i + 1, name))
                continue
            nbytes = n * 16          # two bitplanes: a tile is 16 bytes, not 8
            sites.append((i, name, "nes_escd", nbytes))
            continue

        if st == 'ASM JSR nes_attrs_put':
            # Read the actual copy length from the shim, not a second constant.
            with open(os.path.join(HERE, 'nes_chr.asm'), encoding='utf-8') as f:
                body = f.read().split('nes_attrs_put:', 1)[1]
            count = re.search(r'LDA #(\d+)\s+STA temp2\s+JSR LDIRVM', body)
            if count is None:
                bad.append('cannot resolve nes_attrs_put copy length')
            else:
                sites.append((i, name, 'attributes', int(count.group(1))))
            continue

        m = SCREEN_RE.match(st)
        if m:
            nbytes = int(m.group(1)) * int(m.group(2))
            sites.append((i, name, "SCREEN", nbytes))

    # REGIONS: everything queued between two WAITs, per routine -- and
    # ALTERNATIVES DO NOT ADD.
    #
    # esc_tick queues six characters in its west branch and six more in its
    # east one; only ever one of them runs, so summing both is a model error,
    # not a defect. The first version of this rule did exactly that and failed
    # working code. Each site therefore carries the branch path it sits on, and
    # a region's cost takes the MAX across the arms of an IF and the SUM of
    # everything sequential.
    for name in sorted(set(n for _i, n, _k, _b in sites)):
        a0, b0 = rts[name]
        path, ifid, paths = [], 0, {}
        waits = []
        for j in range(a0, b0):
            if j not in live_lines:
                continue
            st = src[j].strip()
            if not st or st.startswith("'"):
                continue
            if IF_RE.match(st):
                ifid += 1
                path.append((ifid, 0))
            elif ELSE_RE.match(st) and path:
                path[-1] = (path[-1][0], path[-1][1] + 1)
            elif ENDIF_RE.match(st) and path:
                path.pop()
            elif st.upper() == "WAIT":
                waits.append(j)
            paths[j] = tuple(path)

        items = [(i, k, nb) for i, n, k, nb in sites if n == name]
        region, start = [], a0
        for i, kind, nbytes in items:
            if any(start < w < i for w in waits):
                report_region(name, region, bad)
                region, start = [], i
            region.append((i, kind, nbytes, paths.get(i, ())))
        report_region(name, region, bad)

    for i, name, kind, nbytes in sites:
        c = cycles(nbytes)
        big = nbytes > LARGE_BYTES
        if big and not wait_before(src, rts, i):
            bad.append(
                "line %d (%s): %s queues %d bytes (%d cycles of a %d-cycle "
                "vblank) with no WAIT in front of it. Whatever else the pass "
                "queued flushes in the same vblank, the copy runs past the end "
                "of it, and the scroll restore that follows re-points the PPU "
                "mid-frame -- the whole picture jumps for a frame."
                % (i + 1, name, kind, nbytes, c, VBLANK))
        if c > BUDGET:
            bad.append(
                "line %d (%s): %s queues %d bytes = %d cycles, past the %d "
                "available after OAM DMA even with a vblank to itself. Split it "
                "across frames."
                % (i + 1, name, kind, nbytes, c, BUDGET))

    if quiet:
        return 1 if bad else 0

    print("NES vblank budget: %d cycles, %d spent before the first byte is "
          "copied, %d left" % (VBLANK, NMI_FIXED, BUDGET))
    print("a queued upload is LARGE above %d bytes (%d cycles reserved for the "
          "pass's own pokes)" % (LARGE_BYTES, RESERVE))
    for i, name, kind, nbytes in sorted(sites, key=lambda s: -s[3]):
        print("  line %-5d %-12s %-8s %4d bytes  %5d cycles  %s%s"
              % (i + 1, name, kind, nbytes, cycles(nbytes),
                 "LARGE " if nbytes > LARGE_BYTES else "      ",
                 "WAIT ok" if wait_before(src, rts, i) else "no WAIT"))

    if bad:
        for b in bad:
            print("FAIL: " + b)
        return 1
    print("vblank OK -- %d queued uploads reachable from main, none can overrun "
          "its vblank, and no rendering-off upload runs during play"
          % len(sites))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else None))
