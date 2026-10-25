"""The deferred VDP queue against a reference model of its entries.

    qcheck.py [--frames 1500] [--seed 1] [--mutate]

The queue (runtime.a99: QBUF from QHEAD to QPTR) and the sprite shadow
are TI-only (PACE), so lockstep never runs them.  This plays the cart with
PACE on (cspeed's input) and checks the two places that turn queued data
into VRAM:

- every QFLUSH: the entries from QHEAD up to R9 are applied by this
  model (count + address + bytes; >2000|count + address + a pointer to
  the bytes; >4000|count + address + fill byte;
  >8r00|value: register r) to a copy of VRAM and the VDP registers; after
  the real QFLUSH returns, VRAM and the registers must equal the model,
  and the queue that is left (QHEAD..QPTR, its bytes) must be what was
  past R9;
- every SATCK (the sprite shadow's changes into the queue): the entry it
  appends must hold the shadow's bytes SHLO..SHHI for the table at SATB.

--mutate drops every fourth byte the flush sends: it must be reported.
"""
import os
import sys
import argparse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import tiemu
import cspeed
import fastpath

QBUF = 0xAC80


def entries(m, lo, hi):
    """[(kind, addr, data)] for the queue bytes lo..hi."""
    out = []
    p = lo
    while p < hi:
        c = m.rw(p)
        if c & 0x8000:
            out.append(('reg', (c >> 8) & 7, c & 0xFF))
            p += 2
            continue
        a = m.rw(p + 2)
        if c & 0x4000:
            out.append(('fill', a & 0x3FFF, (c & 0x3FFF, m.rb(p + 4))))
            p += 6
            continue
        if c & 0x2000:                      # a reference: TI pointer to the bytes
            c &= 0xFF
            src = m.rw(p + 4)
            out.append(('data', a & 0x3FFF, bytes(m.rb(src + i) for i in range(c))))
            p += 6
            continue
        out.append(('data', a & 0x3FFF, bytes(m.rb(p + 4 + i) for i in range(c))))
        p += 4 + c + (c & 1)
    return out, p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--frames', type=int, default=1500)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--bin', default=os.path.join(ROOT, 'build', 'CARNIVAL_8.bin'))
    ap.add_argument('--mutate', action='store_true')
    args = ap.parse_args()
    build = os.path.dirname(os.path.abspath(args.bin))
    labs = fastpath.labels(build)
    t = tiemu.load(args.bin)
    tiemu.start_game(t, '1')
    drv = cspeed.Driver(args.seed)
    tb, ta = cspeed.ti_tick_addr(build)
    st = {'flush': 0, 'bad': 0, 'sat': 0, 'pend': None, 'satp': None, 'n': 0}
    v = t.vdp

    def report(msg):
        st['bad'] += 1
        if st['bad'] <= 5:
            print(msg)

    def flush_in(m):
        head = m.rw(labs['QHEAD'])
        r9 = m.reg(9)
        qp = m.rw(labs['QPTR'])
        ents, end = entries(m, head, r9)
        if end != r9:
            report('flush: entries end at %04X, R9 %04X' % (end, r9))
        vram = bytearray(v.vram)
        regs = list(v.reg[:8])
        for k, a, d in ents:
            if k == 'reg':
                regs[a] = d
            elif k == 'fill':
                n, b = d
                for i in range(n):
                    vram[(a + i) & 0x3FFF] = b
            else:
                for i, b in enumerate(d):
                    vram[(a + i) & 0x3FFF] = b
        left = bytes(m.rb(a) for a in range(r9, qp))
        st['pend'] = (vram, regs, left, m.reg(10) if False else None)
        st['ret'] = m.pc  # QFLUSH returns through R10 (B *R10)
        st['wp'] = m.wp

    def flush_out(m):
        if st['pend'] is None:
            return
        vram, regs, left, _ = st['pend']
        st['pend'] = None
        st['flush'] += 1
        if bytes(v.vram) != bytes(vram):
            d = [a for a in range(16384) if v.vram[a] != vram[a]]
            report('flush %d: VRAM differs at %d bytes (first %04X)' % (st['flush'], len(d), d[0]))
        if list(v.reg[:8]) != regs:
            report('flush %d: VDP registers differ' % st['flush'])
        head = m.rw(labs['QHEAD'])
        qp = m.rw(labs['QPTR'])
        now = bytes(m.rb(a) for a in range(head, qp))
        if now != left:
            report('flush %d: the queue left %d bytes, expected %d' % (st['flush'], len(now), len(left)))

    def sat_in(m):
        if m.rw(labs['SHST']) != 2:
            return
        lo, hi = m.rw(labs['SHLO']), m.rw(labs['SHHI'])
        if hi <= lo:
            return
        satb = m.rw(labs['SATB'])
        shad = labs['SHAD']
        st['satp'] = (satb + lo, bytes(m.rb(shad + i) for i in range(lo, hi)), m.wp)

    def sat_out(m):
        if st['satp'] is None:
            return
        a, data, wp = st['satp']
        st['satp'] = None
        st['sat'] += 1
        qp = m.rw(labs['QPTR'])
        p = qp - (4 + len(data) + (len(data) & 1))
        c, va = m.rw(p), m.rw(p + 2)
        got = bytes(m.rb(p + 4 + i) for i in range(len(data)))
        if c != len(data) or va != a or got != data:
            report('SATCK %d: queued %04X bytes at %04X, expected %d at %04X' % (st['sat'], c, va, len(data), a))

    if args.mutate:
        orig = t.wb
        cnt = [0]

        def wb(addr, val, orig=orig):
            if addr == 0x8C00:
                cnt[0] += 1
                if cnt[0] % 4 == 0:
                    return
            orig(addr, val)
        t.wb = wb

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
    t.pc_hooks[labs['QFLUSH']] = flush_in
    # QFLUSH's exits: B *R10 at the end of each path
    for lab in ('QFX',):
        if lab in labs:
            t.pc_hooks[labs[lab]] = flush_out
    t.pc_hooks[labs['SATCK']] = sat_in
    t.pc_hooks[labs['SATC3']] = sat_out
    old = t.pc_hooks.get(ta)
    t.pc_hooks[ta] = (lambda m: (old(m) if old else None, tick(m)))
    t.run_frames(args.frames)
    print('%d flushes, %d sprite-shadow commits checked, %d differ' % (st['flush'], st['sat'], st['bad']))
    if not st['flush'] or not st['sat']:
        sys.exit(1)
    if args.mutate:
        sys.exit(0 if st['bad'] else 1)
    sys.exit(1 if st['bad'] else 0)


if __name__ == '__main__':
    main()
