#!/usr/bin/env python3
"""
BUST-A-BOBBLE -- WINNABILITY CHECK for all 30 rounds, played AS SHIPPED.

A hand-authored level can be lovely and still be impossible: the shot sequence is
FIXED per round (a level is a puzzle, not a slot machine), so unlike a random
game the player cannot wait for the colour they need. If a round's 32 shots
cannot clear its board, no amount of skill fixes it -- and nothing else in the
build would notice.

WHAT MAKES THIS TRUSTWORTHY: it reads src/levels.bas and src/art.bas -- the DATA
BYTE blocks that go into the cartridge -- not assets/levels.txt. So it validates
the bytes the machine will actually execute, and it re-implements the game's own
rules rather than a tidy model of them:

  * the 8.8 fixed-point flight, 5 px/frame, with the two wall planes at 6144 and
    34816 and the unsigned compares CVBasic really emits
  * coltest's 3x3 candidate scan with the PIXEL accept dx*dx+dy*dy < 196
  * do_snap's nearest-free-cell-by-Manhattan tie-breaking, in scan order
  * the ceiling shortcut (bpy <= top*8+16 sticks in row 0 via snap_col, and it
    OVERWRITES whatever is there -- that is what the source does)
  * pick_next's forward walk with substitution over still-present colours
  * the drop clock in FRAMES, drops landing mid-flight, and check_death's
    top + 2*row >= 18
  * odd rows being 7 wide (column 7 excluded)

TIME IS CHARGED IN FULL. The animations used to be free -- the main loop stopped
during them so #dropt did not tick -- and this charged a flat 4 frames a shot on
that basis. The game now runs the clock THROUGH the burst and the orphan fall
(anim_tick), so those frames are real and are charged as such: 6 for a burst,
plus 27 more when orphans fall. Every aiming frame is charged too, since the
launcher turns one step per frame. Nothing here is free that is not free in play.

Search: beam search over aim choices, exact simulation at every node. Finding a
line PROVES a round is winnable. Not finding one does not prove the opposite --
failures are re-run wider and reported as UNPROVEN, with a second no-clock pass
that says whether the obstacle is the geometry/colours or the drop timer.

Run:  python3 solvelevels.py [--beam N] [--jobs N] [--level N]
Exit code 1 if any round is unproven, so it can gate a build.
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src")

NSEQ = 32
DEATHROW = 20
CEILROW = 1
HITD2 = 196             # 14*14 -- collision accept, in pixels
LAUNCHX = 80
LAUNCHY = 184
WALL_LO = 6144          # 24 * 256, left  edge column centre (8.8 fixed)
WALL_HI = 34816         # 136 * 256, right edge column centre
ANIM_FRAMES = 4         # a shot that neither pops nor drops; see the header note
OVERHEAD = 0            # --overhead: extra dead frames per shot, to stress the clock

# WHICH CART IS BEING PROVEN. The three things that differ -- the data file, the
# level count and the ceiling rule -- travel together as ONE selection, because
# three independent switches can disagree and this one cannot. Set by --set.
SETNAME = "arcade"
LEVELS_FILE = "levels.bas"
NLEV = 30
EXPERT = False

DEAD = "DEAD"
WIN = "WIN"


# ---------------------------------------------------------------- ROM data

def read_labelled(path):
    """<label>: -> list of its DATA lines. Mirrors how the assembler sees them."""
    out, cur = {}, None
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if not line.strip():
            continue
        if not line[0].isspace() and line.strip().endswith(":"):
            cur = line.strip()[:-1]
            out[cur] = []
            continue
        s = line.strip()
        if s.startswith("'"):
            continue
        if cur is not None and s.upper().startswith("DATA"):
            body = s.split(None, 1)[1] if len(s.split(None, 1)) > 1 else ""
            if body.upper().startswith("BYTE"):
                body = body[4:]
            body = body.split("'")[0]
            out[cur].append(body)
    return out


def values(lines):
    vals = []
    for body in lines:
        for tok in body.split(","):
            tok = tok.strip()
            if not tok:
                continue
            vals.append(int(tok[1:], 16) if tok.startswith("$") else int(tok))
    return vals


def check_source_drift():
    """This file hard-codes the game's constants, so it can go stale silently -- a
    tuned HITD2 or a moved wall plane would leave it happily validating a game that
    no longer exists. Re-read BUSTABOB.bas and fail loudly if anything moved."""
    src = open(os.path.join(SRC, "BUSTABOB.bas"), encoding="utf-8").read()
    bad = []
    for name, want in (("HITD2", HITD2), ("LAUNCHX", LAUNCHX), ("LAUNCHY", LAUNCHY),
                       ("DEATHROW", DEATHROW), ("CEILROW", CEILROW)):
        got = None
        for line in src.splitlines():
            s = line.strip()
            if s.startswith("CONST " + name):
                got = int(s.split("=")[1].split("'")[0].strip())
        if got != want:
            bad.append("CONST %s is %s in the source, %d here" % (name, got, want))
    # The bare literals -- these are deliberately NOT CONSTs (a CONST > 255
    # compiles to zero on this toolchain), so they can only be checked by text.
    for lit, what in ((str(WALL_LO), "left wall plane"),
                      (str(WALL_HI), "right wall plane"),
                      ("20480", "launch x, 8.8 fixed"),
                      ("47104", "launch y, 8.8 fixed")):
        if lit not in src:
            bad.append("%s (%s) no longer appears in the source" % (lit, what))
    if "#droprl = #droprl * 15" not in src:
        bad.append("droptime is no longer quarter-seconds * 15 frames")
    if "IF #fd > 4 THEN #fd = 4" not in src:
        bad.append("the frame-delta clamp moved; the clock model assumes 4")

    # AND CHECK THE RIGHT CART. The two carts are one source split by #if EXPERT,
    # so without this the guard would happily validate an expert model against the
    # arcade branch -- it would stop guarding rather than fail, which is the worse
    # failure. Anchored on whole stripped lines: a loose substring match buys
    # false confidence.
    lines = [l.strip() for l in src.splitlines()]
    if "#if EXPERT" not in lines:
        bad.append("the source no longer has an #if EXPERT branch; the two carts "
                   "have been split some other way")
    if EXPERT:
        for want, what in (("drop_check:", "the shot-count drop routine"),
                           ("shotn = shotn + 1", "the shot counter in do_fire"),
                           ("shotb = pb_meta(#lvm)", "b read from pb_meta byte 0"),
                           ("ncol0 = nprs", "the round's starting colour count"),
                           ("IF shotn >= thr THEN", "the drop threshold test")):
            if want not in lines:
                bad.append("expert set: %s is gone (%s)" % (want, what))
    else:
        if "IF #dropt = 0 THEN GOSUB do_drop" not in lines:
            bad.append("arcade set: the timer drop trigger is gone")

    if bad:
        sys.stderr.write("error: solvelevels.py is out of date with BUSTABOB.bas\n")
        for b in bad:
            sys.stderr.write("  %s\n" % b)
        sys.exit(2)


def load_rom():
    lv = read_labelled(os.path.join(SRC, LEVELS_FILE))
    art = read_labelled(os.path.join(SRC, "art.bas"))
    rom = {
        "lay": values(lv["pb_lay"]),
        "seq": values(lv["pb_seq"]),
        "meta": values(lv["pb_meta"]),
        "aimdx": values(art["#aimdx"]),
        "aimdy": values(art["#aimdy"]),
    }
    # DERIVE the level count and CROSS-CHECK, rather than asserting a fixed 30.
    # Three independent lengths that must agree is a real check: it catches a
    # half-regenerated table, which a hard-coded count would only catch for one
    # particular size of mistake.
    n = len(rom["meta"]) // 2
    assert len(rom["lay"]) == n * 44, (len(rom["lay"]), n)
    assert len(rom["seq"]) == n * 16, (len(rom["seq"]), n)
    assert n == NLEV, "%s holds %d levels, the %s set expects %d" % (
        LEVELS_FILE, n, SETNAME, NLEV)
    assert len(rom["aimdx"]) == 32 and len(rom["aimdy"]) == 32
    return rom


# ---------------------------------------------------------------- game rules

def hex_neighbours(i):
    """nbmark's six neighbours of flat index i, bounds-checked exactly as it is."""
    r, c = divmod(i, 8)
    p = r & 1
    n = c + p
    out = []
    if c > 0:
        out.append(i - 1)
    if c < 7:
        out.append(i + 1)
    if r > 0:
        u = i - 8
        if n > 0:
            out.append(u + p - 1)
        if n < 8:
            out.append(u + p)
    if r < 11:
        d = i + 8
        if n > 0:
            out.append(d + p - 1)
        if n < 8:
            out.append(d + p)
    return out


NB = [hex_neighbours(i) for i in range(96)]
# Cell centres in "well pixel" space; y is CEILING-RELATIVE (the game's gy).
CX = [24 + (i % 8) * 16 + ((i // 8) & 1) * 8 for i in range(96)]
CY = [16 + (i // 8) * 16 for i in range(96)]


class Round(object):
    __slots__ = ("grid", "top", "dropt", "droprl", "si", "curk", "nxtk",
                 "aim", "frames", "shots", "path", "ovw", "score", "ev", "scenery",
                 # expert cart only: the shot-count ceiling rule
                 "shotb", "shotn", "ncol0")

    def clone(self):
        r = Round()
        r.grid = self.grid[:]
        r.top = self.top
        r.dropt = self.dropt
        r.droprl = self.droprl
        r.si = self.si
        r.curk = self.curk
        r.nxtk = self.nxtk
        r.aim = self.aim
        r.frames = self.frames
        r.shots = self.shots
        r.path = self.path
        r.ovw = self.ovw
        r.score = self.score
        r.ev = self.ev
        r.scenery = self.scenery
        r.shotb = self.shotb
        r.shotn = self.shotn
        r.ncol0 = self.ncol0
        return r

    def key(self):
        # shotn is part of the STATE on the expert cart: two boards that look
        # identical but sit at different points in the drop interval are not the
        # same position, and collapsing them would let the search find a line the
        # player cannot follow.
        if EXPERT:
            return (bytes(self.grid), self.top, self.si, self.curk, self.nxtk,
                    self.shotn)
        return (bytes(self.grid), self.top, self.si, self.curk, self.nxtk)


def present(grid):
    p = [0] * 9
    n = 0
    for v in grid:
        k = v & 15
        if k:
            p[k] = 1
            n += 1
    return p, n


def pick_next(seq, si, pres):
    """The game's forward walk with substitution. Returns (nxtk, si)."""
    for d in range(32):
        j = (si + d) & 31
        k = seq[j]
        if k > 0 and pres[k]:
            return k, (j + 1) & 31
    for k in range(1, 9):
        if pres[k]:
            return k, si
    return 1, si


def check_death(grid, top):
    """check_death: bottom char row of grid row r is 1+top+2r+1; >= 20 is fatal."""
    for r in range(12):
        if top + 2 * r >= 18:
            b = r * 8
            for c in range(8):
                if grid[b + c] & 15:
                    return True
    return False


def load_round(rom, lvl):
    st = Round()
    base = (lvl - 1) * 44
    g = [0] * 96
    for r in range(11):
        o = base + r * 4
        b = r * 8
        for c in range(8):
            v = rom["lay"][o + (c >> 1)]
            g[b + c] = (v >> 4) if (c & 1) == 0 else (v & 15)
    st.grid = g
    st.top = 0
    st.droprl = rom["meta"][(lvl - 1) * 2 + 1] * 15
    st.dropt = st.droprl
    # Expert cart: byte 0 is the base shot count b, and the clock above becomes
    # the anti-idle fallback rather than the trigger. ncol0 is the round's
    # STARTING colour count, which the engine captures in new_round for the same
    # reason it is taken here -- after the grid is loaded, not before.
    st.shotb = rom["meta"][(lvl - 1) * 2] if EXPERT else 0
    st.shotn = 0
    st.ncol0 = sum(present(st.grid)[0]) if EXPERT else 0
    st.si = 0
    st.aim = 31
    st.frames = 0
    st.shots = 0
    st.path = ()
    st.ovw = 0
    st.score = 0
    st.ev = None
    # mark_scenery: cells the LEVEL placed that are not chained to the ceiling.
    anch = anchored(g)
    st.scenery = frozenset(i for i in range(96) if (g[i] & 15) and i not in anch)

    seq = []
    sb = (lvl - 1) * 16
    for j in range(NSEQ):
        v = rom["seq"][sb + (j >> 1)]
        seq.append((v >> 4) if (j & 1) == 0 else (v & 15))

    pres, _ = present(g)
    st.nxtk, st.si = pick_next(seq, st.si, pres)
    st.curk = st.nxtk
    st.nxtk, st.si = pick_next(seq, st.si, pres)
    return st, seq


def coltest(grid, bpx, gy):
    """Returns (hit, ctr, ctc) -- the candidate cell plus whether anything was hit."""
    ctr = 0 if gy < 16 else (gy - 8) // 16
    if ctr > 11:
        ctr = 11
    ctp = ctr & 1
    ctx = 16 + ctp * 8
    ctc = 0 if bpx <= ctx else (bpx - ctx) // 16
    if ctc > 7:
        ctc = 7
    hit = False
    for rr in (ctr - 1, ctr, ctr + 1):
        if rr < 0 or rr > 11:
            continue
        pp = rr & 1
        base = rr * 8
        for cc in (ctc - 1, ctc, ctc + 1):
            if cc < 0 or cc > 7:
                continue
            if pp == 1 and cc > 6:
                continue
            i = base + cc
            if grid[i] & 15:
                dx = bpx - CX[i]
                if dx < 0:
                    dx = -dx
                dy = gy - CY[i]
                if dy < 0:
                    dy = -dy
                if dx * dx + dy * dy < HITD2:
                    hit = True
    return hit, ctr, ctc


def do_snap(grid, bpx, gy, ctr, ctc):
    """Nearest FREE cell in the 3x3 by Manhattan; ties go to the first in scan order."""
    best = 255
    found = None
    for rr in (ctr - 1, ctr, ctr + 1):
        if rr < 0 or rr > 11:
            continue
        pp = rr & 1
        base = rr * 8
        for cc in (ctc - 1, ctc, ctc + 1):
            if cc < 0 or cc > 7:
                continue
            if pp == 1 and cc > 6:
                continue
            i = base + cc
            if grid[i] & 15:
                continue
            dx = bpx - CX[i]
            if dx < 0:
                dx = -dx
            dy = gy - CY[i]
            if dy < 0:
                dy = -dy
            d = dx + dy
            if d < best:
                best = d
                found = (rr, cc)
    return found


def match_group(grid, start, colour):
    """propag with pgcol = colour: same-colour flood fill from the landed cell."""
    seen = {start}
    stack = [start]
    while stack:
        i = stack.pop()
        for j in NB[i]:
            if j not in seen and (grid[j] & 15) == colour:
                seen.add(j)
                stack.append(j)
    return seen


def anchored(grid):
    """The set connected to grid row 0 -- propag with pgcol = 0, seeded from row 0."""
    seen = set()
    stack = []
    for c in range(8):
        if grid[c] & 15:
            seen.add(c)
            stack.append(c)
    while stack:
        i = stack.pop()
        for j in NB[i]:
            if j not in seen and (grid[j] & 15):
                seen.add(j)
                stack.append(j)
    return seen


def orphans(grid, scenery):
    """Bubbles that fall: those that cannot reach the ceiling OR surviving scenery.

    `scenery` is the set the LEVEL placed detached from the ceiling (mark_scenery in
    BUSTABOB.bas), which acts as an anchor exactly like the ceiling. A shot bubble is
    never scenery, so it obeys gravity normally; and scenery that gets popped is gone
    from the grid and stops anchoring, so whatever rested on it falls. On a
    well-formed field there is no scenery and this is precisely the stock rule.
    """
    seeds = [c for c in range(8) if grid[c] & 15]
    seeds += [i for i in scenery if grid[i] & 15]
    reach = set(seeds)
    stack = list(seeds)
    while stack:
        i = stack.pop()
        for j in NB[i]:
            if j not in reach and (grid[j] & 15):
                reach.add(j)
                stack.append(j)
    return [i for i in range(96) if (grid[i] & 15) and i not in reach]


def play_shot(st, seq, aim, use_clock=True):
    """One complete shot at aim 0..62. Returns a new Round, DEAD, or (WIN, round)."""
    s = st.clone()
    grid = s.grid
    # THE SHOT IS COUNTED AS IT LEAVES, mirroring do_fire. Every path below has
    # already spent it, including the one where the bubble sticks nowhere.
    s.shotn += 1

    if aim >= 31:
        am, bdir = aim - 31, 1
    else:
        am, bdir = 31 - aim, 0

    def tick():
        """One main-loop pass of clock: returns False if the drop killed the player."""
        if not use_clock:
            return True
        if s.dropt > 1:
            s.dropt -= 1
            return True
        s.dropt = 0
        # do_drop
        s.top += 1
        s.dropt = s.droprl
        return not check_death(grid, s.top)

    travel = abs(aim - st.aim)
    for _ in range(travel):
        if not tick():
            return DEAD
    s.aim = aim
    s.frames += travel

    # do_fire, then do_flight in the SAME pass -- the clock ticks first.
    if not tick():
        return DEAD
    s.frames += 1
    bx, by = 20480, 47104
    bdx, bdy = AIMDX[am], AIMDY[am]

    landed = None
    bounce_l = bounce_r = 0
    shotk = s.curk
    for _ in range(400):
        by = (by - bdy) & 0xFFFF
        bx = (bx + bdx if bdir else bx - bdx) & 0xFFFF
        if bdir == 0:
            if bx < WALL_LO:
                bx, bdir = WALL_LO, 1
                bounce_l += 1
        else:
            if bx > WALL_HI:
                bx, bdir = WALL_HI, 0
                bounce_r += 1
        bpx = (bx >> 8) & 0xFF
        bpy = (by >> 8) & 0xFF

        ct8 = s.top * 8
        if bpy <= ct8 + 16:
            # Ceiling: snap_col picks the column outright and OVERWRITES.
            stcc = 0 if bpx <= 16 else (bpx - 16) // 16
            if stcc > 7:
                stcc = 7
            # The source does NOT check the cell is free here, so a ceiling
            # landing can overwrite an occupied row-0 cell. Counted, because a
            # "win" that leans on it is leaning on a quirk, not on play.
            if grid[stcc] & 15:
                s.ovw += 1
            landed = stcc
            break

        gy = (bpy - ct8) & 0xFF
        hit, ctr, ctc = coltest(grid, bpx, gy)
        if hit:
            cell = do_snap(grid, bpx, gy, ctr, ctc)
            if cell is None:
                landed = -1          # snf = 0: the shot is discarded
            else:
                landed = cell[0] * 8 + cell[1]
            break

        s.frames += 1
        if not tick():
            return DEAD
    else:
        landed = -1

    s.shots += 1
    s.path = st.path + (aim,)

    def charge(n):
        """Run the clock for n frames of between-shot time (drops still fire)."""
        for _ in range(n):
            if not tick():
                return False
            s.frames += 1
        return True

    if landed == -1:
        pres, n = present(grid)
        s.ev = {"k": shotk, "aim": aim, "bl": bounce_l, "br": bounce_r,
                "cell": None, "pop": 0, "drop": 0, "pts": 0, "left": n}
        s.curk = s.nxtk
        s.nxtk, s.si = pick_next(seq, s.si, pres)
        if not charge(ANIM_FRAMES + OVERHEAD):
            return DEAD
        return s

    grid[landed] = s.curk

    # ------ after_stick
    # mark_scenery is per LEVEL, not per shot -- st.scenery carries it.
    animated = False
    npop = ndrop = pts = 0
    group = match_group(grid, landed, s.curk)
    if len(group) >= 3:
        animated = True
        npop = len(group)
        pts = 10 * npop                 # 10 a bubble for the popped group
        for i in group:
            grid[i] = 0
        fell = orphans(grid, s.scenery)
        ndrop = len(fell)
        for j in range(ndrop):          # i-th dropped bubble: 20 * 2^(i-1), i capped at 17
            pts += 20 * (2 ** (min(j + 1, 17) - 1))
        for i in fell:
            grid[i] = 0

    pres, n = present(grid)
    s.score += pts
    s.ev = {"k": shotk, "aim": aim, "bl": bounce_l, "br": bounce_r,
            "cell": landed, "pop": npop, "drop": ndrop, "pts": pts, "left": n}
    if n == 0:
        return (WIN, s)         # do_clear fires immediately; the clock is moot
    if check_death(grid, s.top):
        return DEAD
    s.curk = s.nxtk
    s.nxtk, s.si = pick_next(seq, s.si, pres)
    # The clock now runs THROUGH the animations (anim_tick), so charge what they
    # really cost: 6 frames for the burst, plus 27 more if orphans fall.
    if animated:
        cost = 6
        if ndrop:
            cost = cost + 27
    else:
        cost = 2
    if not charge(cost + OVERHEAD):
        return DEAD

    # THE EXPERT CART'S CEILING RULE -- drop_check, mirrored exactly.
    #
    # Placed here for the same reason it sits at the end of after_stick: after the
    # win test and the death test, so a round just cleared or just lost does not
    # also drop. The no-stick path returns earlier and never reaches this, which
    # matches the engine -- that path calls next_shot directly and skips
    # after_stick, so the shot is COUNTED but the threshold is not tested until
    # the next shot that does stick.
    if EXPERT:
        mis = s.ncol0 - sum(pres)
        if mis < 0:
            mis = 0
        thr = s.shotb - mis
        if thr < 1:
            thr = 1
        if s.shotn >= thr:
            s.shotn = 0
            s.top += 1
            s.dropt = s.droprl        # a shot-triggered drop rearms the fallback
            if check_death(grid, s.top):
                return DEAD

    return s


AIMDX = AIMDY = None


# ---------------------------------------------------------------- search

def score(st):
    """Beam ordering. Fewer bubbles first; then colours that still need feeding,
    then how far down the field reaches (the thing that actually kills you)."""
    counts = [0] * 9
    maxr = 0
    for i, v in enumerate(st.grid):
        k = v & 15
        if k:
            counts[k] += 1
            r = i >> 3
            if r > maxr:
                maxr = r
    n = sum(counts)
    need = sum(3 - c for c in counts[1:] if 0 < c < 3)
    return (n + 2 * need, st.top + 2 * maxr, st.frames)


def solve(rom, lvl, beam, maxdepth, use_clock=True):
    st, seq = load_round(rom, lvl)
    droprl = st.droprl
    frontier = [st]
    seen = set()
    for depth in range(maxdepth):
        nxt = {}
        for cur in frontier:
            landings = {}
            for aim in range(63):
                r = play_shot(cur, seq, aim, use_clock)
                if r is DEAD:
                    continue
                if isinstance(r, tuple):
                    return {"win": True, "shots": r[1].shots, "frames": r[1].frames,
                            "top": r[1].top, "path": r[1].path, "depth": depth + 1,
                            "ovw": r[1].ovw, "droprl": droprl}
                k = r.key()
                old = landings.get(k)
                if old is None or r.frames < old.frames:
                    landings[k] = r
            for k, r in landings.items():
                if k in seen:
                    continue
                old = nxt.get(k)
                if old is None or r.frames < old.frames:
                    nxt[k] = r
        if not nxt:
            return {"win": False, "reason": "no surviving shot", "depth": depth}
        ranked = sorted(nxt.values(), key=score)[:beam]
        for r in ranked:
            seen.add(r.key())
        frontier = ranked
    best = min(frontier, key=score)
    _, n = present(best.grid)
    return {"win": False, "reason": "depth limit (%d shots), best left %d bubbles"
            % (maxdepth, n), "depth": maxdepth}


def board(grid, top):
    """The field as the player sees it, with the death line where the game puts it."""
    out = []
    for r in range(12):
        p = r & 1
        row = [" "] * 17
        for c in range(8 - p):
            k = grid[r * 8 + c] & 15
            if k:
                row[c * 2 + p] = str(k)
        drow = CEILROW + top + 2 * r
        tag = "  <== DEATH LINE" if drow + 1 >= DEATHROW else ""
        out.append("   |" + "".join(row) + "|" + tag)
    return out


def replay(rom, lvl, path):
    """Re-run a winning line shot by shot, checking the invariants the game relies on."""
    global AIMDX, AIMDY
    AIMDX, AIMDY = rom["aimdx"], rom["aimdy"]
    st, seq = load_round(rom, lvl)
    print("round %d -- %d bubbles, droptime %.2f s, %d shots" %
          (lvl, present(st.grid)[1], st.droprl / 60.0, len(path)))
    print("   sequence " + "".join(str(k) for k in seq))
    for line in board(st.grid, st.top):
        print(line)
    problems = []
    for n, aim in enumerate(path):
        before = st.grid[:]
        curk = st.curk
        r = play_shot(st, seq, aim)
        assert r is not DEAD, "replay diverged: shot %d killed" % (n + 1)
        win = isinstance(r, tuple)
        s = r[1] if win else r
        placed = [i for i in range(96) if (s.grid[i] & 15) and not (before[i] & 15)]
        gone = [i for i in range(96) if (before[i] & 15) and not (s.grid[i] & 15)]
        where = "cell %d,%d" % (placed[0] // 8, placed[0] % 8) if placed else "(absorbed)"
        if placed:
            i = placed[0]
            anchored = i < 8 or any(before[j] & 15 for j in NB[i])
            if not anchored:
                problems.append("shot %d landed at %s with no neighbour" % (n + 1, where))
        print("  shot %2d  aim %2d  colour %d  -> %-12s  cleared %2d  left %2d%s"
              % (n + 1, aim, curk, where, len(gone), present(s.grid)[1],
                 "   TOP DROPPED" if s.top != st.top else ""))
        st = s
    for line in board(st.grid, st.top):
        print(line)
    for p in problems:
        print("  ! " + p)
    print("  final bubbles %d, ceiling drops %d, %d frames (%.1f s)"
          % (present(st.grid)[1], st.top, st.frames, st.frames / 60.0))
    return problems


# Names come from genart.py's BUBBLE table -- what the ROM actually draws.
# There is no orange ball: 7 is grey (heavy dither), 8 is white (light dither).
CNAME = {1: "red", 2: "green", 3: "blue", 4: "yellow",
         5: "cyan", 6: "magenta", 7: "grey", 8: "white"}
CHEX = {1: "#e05c4a", 2: "#5cc85c", 3: "#5a5aec", 4: "#ded46a",
        5: "#5ad4e0", 6: "#c85ac8", 7: "#cccccc", 8: "#ffffff"}


def aim_text(aim, bl, br):
    """The launcher in words. aim 0..62, 31 = straight up, full deflection = 80 deg."""
    d = aim - 31
    deg = abs(d) * 80.0 / 31.0
    if d == 0:
        s = "straight up"
    else:
        s = "%s %d (%.0f%s)" % ("right" if d > 0 else "left", abs(d), deg, "°")
    n = bl + br
    if n == 1:
        s += ", bank off the %s wall" % ("left" if bl else "right")
    elif n > 1:
        s += ", %d banks" % n
    return s


def effect_text(ev):
    if ev["cell"] is None:
        return "no contact"
    if ev["pop"] == 0:
        return "sticks"
    bits = ["pops %d" % ev["pop"]]
    if ev["drop"]:
        bits.append("drops %d" % ev["drop"])
    return "%s  (+%s)" % (", ".join(bits), "{:,}".format(ev["pts"]))


def collect(rom, lvl, beam, maxdepth):
    """Solve a round and replay it, returning everything a walkthrough needs.

    Runs a LADDER of beam widths and keeps the SHORTEST line. A wider beam is not
    reliably better here: it explores a different region, so round 3 came out at
    45 shots at beam 48, 73 at beam 150 and 37 at beam 400, while round 5 went
    41 -> 17. Length is what a reader has to sit through, so it is worth paying
    for -- and any line the ladder finds is equally a proof of winnability.
    """
    best = None
    for b in (beam, beam * 3, beam * 9):
        res = solve(rom, lvl, b, maxdepth, True)
        if res["win"] and (best is None or res["shots"] < best["shots"]):
            best = res
    res = best
    if res is None:
        return {"lvl": lvl, "win": False,
                "reason": "no line found at beam %d/%d/%d" % (beam, beam * 3, beam * 9)}
    st, seq = load_round(rom, lvl)
    out = {"lvl": lvl, "win": True, "seq": seq,
           "droprl": st.droprl, "start": st.grid[:],
           "bubbles": present(st.grid)[1],
           "colours": sorted(set(v & 15 for v in st.grid if v & 15)),
           "shots": []}
    for aim in res["path"]:
        r = play_shot(st, seq, aim)
        s = r[1] if isinstance(r, tuple) else r
        ev = dict(s.ev)
        ev["top"] = s.top
        ev["score"] = s.score
        out["shots"].append(ev)
        st = s
    out["frames"] = st.frames
    out["score"] = st.score
    out["top"] = st.top
    return out


def anchor_audit(rom, levels):
    """Which levels ship bubbles that are ALREADY unanchored from the ceiling?

    Only grid row 0 hangs from the ceiling; everything else has to chain up to it.
    The game never checks this at load -- drop_orphans runs only after a pop -- so a
    detached layout sits there looking solid until the first match, and then a large
    part of the board falls at once whether or not it touched the popped group.
    That reads as a bug in the pop logic (it was reported as exactly that), but the
    logic is right and the LAYOUT is wrong.
    """
    print("BUST-A-BOBBLE -- ceiling-anchor audit")
    print("Only grid row 0 hangs from the ceiling. Bubbles not chained to it are")
    print("detached from the start; since the fix they no longer collapse on the")
    print("round's first pop, but they can ONLY be cleared by matching them.\n")
    bad = []
    for lvl in levels:
        st, _ = load_round(rom, lvl)
        total = present(st.grid)[1]
        anch = anchored(st.grid)
        loose = [i for i in range(96) if (st.grid[i] & 15) and i not in anch]
        if loose:
            bad.append((lvl, total, len(loose)))
            print("  round %-2d  %3d bubbles, %3d UNANCHORED (%d%%)"
                  % (lvl, total, len(loose), round(100.0 * len(loose) / total)))
    if not bad:
        print("  every round is fully anchored.")
    else:
        print("\n  %d of %d rounds ship unanchored bubbles." % (len(bad), len(levels)))
    return 1 if bad else 0


def board_lines(grid):
    """The field as the player sees it: even rows 8 wide, odd rows 7 and indented."""
    lines = []
    for r in range(12):
        p = r & 1
        cells = []
        for c in range(8 - p):
            k = grid[r * 8 + c] & 15
            cells.append(str(k) if k else ".")
        row = ("  " if p else "") + " ".join(cells)
        lines.append(row)
    while lines and lines[-1].strip(".  ") == "":
        lines.pop()
    return lines


def write_report(rom, levels, beam, maxdepth, mdpath, jsonpath):
    import json
    data = []
    for lvl in levels:
        d = collect(rom, lvl, beam, maxdepth)
        data.append(d)
        if d["win"]:
            print("  round %-2d  %2d shots  %s pts" %
                  (lvl, len(d["shots"]), "{:,}".format(d["score"])))
        else:
            print("  round %-2d  NO LINE FOUND (%s)" % (lvl, d["reason"]))
        sys.stdout.flush()

    with open(jsonpath, "w", encoding="utf-8") as fh:
        json.dump([{k: (list(v) if isinstance(v, list) else v)
                    for k, v in d.items()} for d in data], fh, indent=1)

    L = []
    w = L.append
    w("# BUST-A-BOBBLE — how to clear all 30 rounds")
    w("")
    w("GENERATED by `assets/solvelevels.py --report`. Do not hand-edit.")
    w("")
    w("Every line below was found by simulating the **shipped** ROM data")
    w("(`src/levels.bas`, `src/art.bas`) under the game's own rules, so each is a")
    w("real, playable solution rather than a sketch. Each round's bubble sequence is")
    w("fixed, so the balls you are dealt are exactly the ones listed.")
    w("")
    w("These are *a* way to clear each round, not the only way and not always the")
    w("highest-scoring one — the search stops at the first solution it finds with the")
    w("fewest shots, and big scores come from setting up one huge drop instead.")
    w("")
    w("**Aim** is the launcher's step count from straight up: the launcher has 63")
    w("positions, 31 either side, and one step is `80/31` ≈ 2.6°. It moves one step")
    w("per frame while you hold the stick, and it **stays where you left it between")
    w("shots**, so the counts below are absolute, not relative to the last shot.")
    w("")
    w("Colours: " + ", ".join("**%d** %s" % (k, CNAME[k]) for k in range(1, 9)) + ".")
    w("")
    for d in data:
        w("---")
        w("")
        if not d["win"]:
            w("## Round %d — no line found" % d["lvl"])
            w("")
            w(d["reason"])
            w("")
            continue
        w("## Round %d" % d["lvl"])
        w("")
        w("%d bubbles, %s in play, ceiling drops every %.2f s."
          % (d["bubbles"], " / ".join(CNAME[c] for c in d["colours"]),
             d["droprl"] / 60.0))
        w("")
        w("```")
        for line in board_lines(d["start"]):
            w(line)
        w("```")
        w("")
        # The RAW sequence, in the same digits as the board above. Initials would
        # be ambiguous -- green and grey both start with G.
        w("Fixed shot sequence (wraps after 32): `%s`"
          % "".join(str(k) for k in d["seq"]))
        w("")
        w("A colour that is no longer on the field is skipped, so the balls you are")
        w("actually handed can differ from the raw sequence — the Ball column is what")
        w("you get.")
        w("")
        w("| # | Ball | Aim | Lands | Result | Bubbles left |")
        w("|--:|---|---|---|---|--:|")
        for i, ev in enumerate(d["shots"]):
            cell = ("row %d, col %d" % (ev["cell"] // 8, ev["cell"] % 8)
                    if ev["cell"] is not None else "—")
            w("| %d | %s | %s | %s | %s | %d |"
              % (i + 1, CNAME[ev["k"]], aim_text(ev["aim"], ev["bl"], ev["br"]),
                 cell, effect_text(ev), ev["left"]))
        w("")
        w("Cleared in **%d shots**, %.1f s, %s points%s."
          % (len(d["shots"]), d["frames"] / 60.0, "{:,}".format(d["score"]),
             "" if d["top"] == 0 else
             " — the ceiling drops %d time%s along the way"
             % (d["top"], "" if d["top"] == 1 else "s")))
        w("")
    with open(mdpath, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(L) + "\n")
    print("\nwrote %s" % os.path.normpath(mdpath))
    print("wrote %s" % os.path.normpath(jsonpath))
    return 0 if all(d["win"] for d in data) else 1


def run_level(args):
    rom, lvl, beam, maxdepth, overhead = args
    global AIMDX, AIMDY, OVERHEAD
    AIMDX, AIMDY = rom["aimdx"], rom["aimdy"]
    OVERHEAD = overhead
    res = solve(rom, lvl, beam, maxdepth, True)
    if not res["win"]:
        res2 = solve(rom, lvl, beam * 4, maxdepth, True)
        if res2["win"]:
            res = res2
        else:
            res["noclock"] = solve(rom, lvl, beam * 4, maxdepth, False)
    return lvl, res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--beam", type=int, default=48)
    ap.add_argument("--depth", type=int, default=90)
    ap.add_argument("--level", type=int, default=0)
    ap.add_argument("--jobs", type=int, default=0)
    ap.add_argument("--replay", action="store_true",
                    help="print the winning line shot by shot (needs --level)")
    ap.add_argument("--probe", type=int, default=0,
                    help="print where every aim lands the round's next shot")
    ap.add_argument("--prefix", default="",
                    help="comma-separated aims to play before probing")
    ap.add_argument("--anchors", action="store_true",
                    help="report levels shipping bubbles not chained to the ceiling")
    ap.add_argument("--report", action="store_true",
                    help="write WALKTHROUGH.md + walkthrough.json for every round")
    ap.add_argument("--overhead", type=int, default=0,
                    help="extra dead frames charged per shot, to stress the drop clock")
    ap.add_argument("--set", dest="cartset", choices=("arcade", "expert"),
                    default="arcade",
                    help="which cart to prove: arcade (30 rounds, timer drop) "
                         "or expert (50 levels, shot-count drop)")
    a = ap.parse_args()

    global OVERHEAD, SETNAME, LEVELS_FILE, NLEV, EXPERT
    OVERHEAD = a.overhead
    SETNAME = a.cartset
    if SETNAME == "expert":
        LEVELS_FILE, NLEV, EXPERT = "levels2.bas", 50, True

    check_source_drift()
    rom = load_rom()
    global AIMDX, AIMDY
    AIMDX, AIMDY = rom["aimdx"], rom["aimdy"]

    if a.anchors:
        return anchor_audit(rom, [a.level] if a.level else list(range(1, NLEV + 1)))

    if a.report:
        levels = [a.level] if a.level else list(range(1, NLEV + 1))
        print("BUST-A-BOBBLE -- walkthrough for %d round(s), beam %d\n"
              % (len(levels), a.beam))
        return write_report(rom, levels, a.beam, a.depth,
                            os.path.join(HERE, "WALKTHROUGH.md"),
                            os.path.join(HERE, "walkthrough.json"))

    if a.probe:
        # Where does each aim put the FIRST shot of a round? This is the cheapest
        # thing to check against the real game: boot the round, press left/right
        # the stated number of times, fire, and see if the bubble lands here.
        st, seq = load_round(rom, a.probe)
        for pa in [int(x) for x in a.prefix.split(",") if x.strip()]:
            r = play_shot(st, seq, pa)
            st = r[1] if isinstance(r, tuple) else r
            print("  (prefix shot at aim %d -> now holding colour %d, next %d)"
                  % (pa, st.curk, st.nxtk))
        print("round %d, next shot is colour %d, NEXT shows %d "
              "(char cell = row 1+top+2r, col 2+2c+(r AND 1))"
              % (a.probe, st.curk, st.nxtk))
        for aim in range(63):
            r = play_shot(st, seq, aim)
            s = r[1] if isinstance(r, tuple) else r
            if r is DEAD:
                print("  aim %2d (%s %2d) -> dies" % (aim, "R" if aim > 31 else "L",
                                                      abs(aim - 31)))
                continue
            placed = [i for i in range(96)
                      if (s.grid[i] & 15) and not (st.grid[i] & 15)]
            if placed:
                gr, gc = placed[0] // 8, placed[0] % 8
                cell = "row %d col %d   char cell r%-2d c%-2d" % (
                    gr, gc, CEILROW + s.top + 2 * gr, 2 + 2 * gc + (gr & 1))
            else:
                cell = "popped on contact"
            print("  aim %2d (%s %2d) -> %s" %
                  (aim, "right" if aim > 31 else ("left " if aim < 31 else "  -  "),
                   abs(aim - 31), cell))
        return 0

    if a.replay:
        if not a.level:
            sys.stderr.write("error: --replay needs --level N\n")
            return 2
        res = solve(rom, a.level, a.beam, a.depth, True)
        if not res["win"]:
            print("round %d: no line found (%s)" % (a.level, res["reason"]))
            return 1
        return 1 if replay(rom, a.level, res["path"]) else 0

    levels = [a.level] if a.level else list(range(1, NLEV + 1))
    work = [(rom, n, a.beam, a.depth, a.overhead) for n in levels]

    print("BUST-A-BOBBLE -- winnability check (src/levels.bas as shipped)")
    print("beam %d, depth %d, clock charged in frames + %d/shot + %d overhead\n"
          % (a.beam, a.depth, ANIM_FRAMES, a.overhead))

    results = {}
    if a.jobs and a.jobs > 1:
        import multiprocessing
        pool = multiprocessing.Pool(a.jobs)
        for lvl, res in pool.imap_unordered(run_level, work):
            results[lvl] = res
        pool.close()
        pool.join()
    else:
        for w in work:
            lvl, res = run_level(w)
            results[lvl] = res
            r = res
            if r["win"]:
                print("  round %-2d  WINNABLE  %2d shots  %5.1f s of %4.1f s to the "
                      "first drop  ceiling dropped %d%s"
                      % (lvl, r["shots"], r["frames"] / 60.0, r["droprl"] / 60.0,
                         r["top"],
                         "   [%d ceiling overwrites]" % r["ovw"] if r["ovw"] else ""))
            else:
                print("  round %-2d  UNPROVEN   %s" % (lvl, r["reason"]))
            sys.stdout.flush()

    if a.jobs and a.jobs > 1:
        for lvl in sorted(results):
            r = results[lvl]
            if r["win"]:
                print("  round %-2d  WINNABLE  %2d shots  %5.1f s of %4.1f s to the "
                      "first drop  ceiling dropped %d%s"
                      % (lvl, r["shots"], r["frames"] / 60.0, r["droprl"] / 60.0,
                         r["top"],
                         "   [%d ceiling overwrites]" % r["ovw"] if r["ovw"] else ""))
            else:
                print("  round %-2d  UNPROVEN   %s" % (lvl, r["reason"]))

    bad = [n for n in sorted(results) if not results[n]["win"]]
    print("")
    print("  %d of %d rounds proven winnable" % (len(results) - len(bad), len(results)))
    for n in bad:
        r = results[n]
        nc = r.get("noclock")
        if nc is not None:
            if nc["win"]:
                print("  round %-2d: clearable with the clock OFF in %d shots -- "
                      "the DROP TIMER is the obstacle" % (n, nc["shots"]))
            else:
                print("  round %-2d: not clearable even with the clock off -- "
                      "the LAYOUT/SEQUENCE is the obstacle (%s)" % (n, nc["reason"]))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
