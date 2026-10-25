"""TI-only fast paths against the generic routine they shortcut.

    fastpath.py [--frames 1500] [--seed 1] [--samples 300] [--pair FAST:GENERIC ...]

Lockstep runs with PACE off, so TI-only shortcuts (os7obj's QW: a name
row straight into the deferred queue; PVSPR's PVF: a sprite entry
straight into the sprite-table shadow) never run there.  This plays the
cart with PACE on (cspeed's input), and at each visit of FAST takes a
copy of the machine: one copy runs on from FAST, the other from GENERIC
(N_WRVRAM, the same registers), each until the routine returns (R11 as
at FAST).  RAM (less N_WRVRAM's own scratch VRET/TMP1), VRAM and the VDP
registers must then be the same.  Exits nonzero on any difference.
Mutation self-test: --mutate drops the fast copy's byte writes to the
queue and the shadow; it must report differences (exit 0 only then).
"""
import os
import re
import sys
import copy
import argparse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import tiemu
import cspeed

PAIRS = ['QW:N_WRVRAM', 'QW1:N_WRVRAM', 'PVF:N_WRVRAM']


def labels(build):
    labs = {}
    txt = open(os.path.join(build, 'cv_gen.equ')).read()
    for m in re.finditer(r'^(\w+):\s*\n\s*equ\s+>([0-9a-fA-F]{4})', txt, re.M):
        labs[m.group(1).upper()] = int(m.group(2), 16)
    return labs


def run_to(t, ret, limit=400000):
    c0 = t.cycles
    while not (t.pc == ret and t.wp == 0x8300):
        t.step()
        if t.cycles - c0 > limit:
            raise RuntimeError('no return to %04X' % ret)


def state(t, skip):
    ram = bytes(t.exp[a] if a not in skip else 0 for a in range(0xA000, 0x10000))
    v = getattr(t, 'vdp', None)
    vram = bytes(v.vram) if v is not None else bytes(t.vram)
    regs = tuple(v.reg[:8]) if v is not None else tuple(t.vreg)
    return ram, vram, regs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--frames', type=int, default=1500)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--samples', type=int, default=300)
    ap.add_argument('--pair', action='append')
    ap.add_argument('--bin', default=os.path.join(ROOT, 'build', 'CARNIVAL_8.bin'))
    ap.add_argument('--mutate', action='store_true')
    args = ap.parse_args()
    build = os.path.dirname(os.path.abspath(args.bin))
    labs = labels(build)
    skip = set()
    for n in ('VRET', 'TMP1'):
        skip |= {labs[n], labs[n] + 1}
    t = tiemu.load(args.bin)
    tiemu.start_game(t, '1')
    drv = cspeed.Driver(args.seed)
    tb, ta = cspeed.ti_tick_addr(build)

    def tick(m):
        drv.tick()
        d, f = drv.state()
        for k in ('J1LEFT', 'J1RIGHT', 'J1FIRE'):
            m.pressed.discard(k)
        if d == 'left':
            m.pressed.add('J1LEFT')
        if d == 'right':
            m.pressed.add('J1RIGHT')
        if f:
            m.pressed.add('J1FIRE')
    stats = {}
    bad = [0]
    every = {}
    for pr in (args.pair or PAIRS):
        fast, gen = pr.split(':')
        fa, ga = labs[fast], labs[gen]
        stats[fast] = [0, 0, 0]

        def hook(m, fast=fast, fa=fa, ga=ga):
            st = stats[fast]
            st[0] += 1
            if st[1] >= args.samples or st[0] % every.setdefault(fast, 3):
                return
            st[1] += 1
            ret = m.reg(11)
            hooks = m.pc_hooks
            m.pc_hooks = {}
            try:
                a = copy.deepcopy(m)
                b = copy.deepcopy(m)
            finally:
                m.pc_hooks = hooks
            if args.mutate:
                orig = a.wb

                def wb(addr, v, orig=orig):
                    if 0xAC00 <= addr < 0xAF80:      # the queue and the shadow
                        return
                    orig(addr, v)
                a.wb = wb
            run_to(a, ret)
            b.pc = ga
            run_to(b, ret)
            sa, sb = state(a, skip), state(b, skip)
            if sa != sb:
                st[2] += 1
                bad[0] += 1
                if st[2] <= 3:
                    for i, (x, y) in enumerate(zip(sa[0], sb[0])):
                        if x != y:
                            print('%s: RAM >%04X fast %02X generic %02X' % (fast, 0xA000 + i, x, y))
                            break
                    if sa[1] != sb[1]:
                        print('%s: VRAM differs' % fast)
                    if sa[2] != sb[2]:
                        print('%s: VDP registers differ' % fast)
        t.pc_hooks[fa] = hook
    old = t.pc_hooks.get(ta)
    t.pc_hooks[ta] = (lambda m: (old(m) if old else None, tick(m)))
    t.run_frames(args.frames)
    for k, (n, tested, diff) in stats.items():
        print('%-6s %6d visits, %4d tested, %d differ' % (k, n, tested, diff))
    if args.mutate:
        sys.exit(0 if bad[0] else 1)
    if not any(v[1] for v in stats.values()):
        print('nothing tested')
        sys.exit(1)
    sys.exit(1 if bad[0] else 0)


if __name__ == '__main__':
    main()
