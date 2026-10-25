"""The vblank sound run must leave the game's workspace as it found it.

    sndruncheck.py [--frames 1500] [--seed 1] [--mutate]

SNDRUN (os7.a99) runs the sound engine on the game's workspace at a
vblank, TI only (PACE), so lockstep never executes it.  It saves only the
registers the sound closure can change (sndclose.py proves the rest are
never written).  This plays the cart with PACE on (cspeed's input) and at
every run compares all 16 MAINWS registers at SNDRUN's entry with their
values at the LWPI back (SNRWP), and the caller's workspace pointer after
it.  --mutate corrupts R9 (BC') in the middle of each run: it must be
reported.
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
    st = {'runs': 0, 'bad': 0, 'regs': None, 'wp': None}
    MAIN = 0x8300

    def regs(m):
        return [m.rw(MAIN + 2 * i) for i in range(16)]

    def enter(m):
        st['regs'] = regs(m)
        st['wp'] = m.wp

    def mid(m):
        if args.mutate and st['regs'] is not None:
            m.ww(MAIN + 18, (m.rw(MAIN + 18) ^ 0x5A5A) & 0xFFFF)

    def back(m):
        if st['regs'] is None:
            return
        st['runs'] += 1
        now = regs(m)
        if now != st['regs']:
            st['bad'] += 1
            if st['bad'] <= 3:
                d = [i for i in range(16) if now[i] != st['regs'][i]]
                print('run %d: R%s changed' % (st['runs'], ','.join(map(str, d))))
        st['regs'] = None

    def after(m):
        if st['wp'] is not None and m.wp != st['wp']:
            st['bad'] += 1
            print('caller workspace %04X, back in %04X' % (st['wp'], m.wp))
        st['wp'] = None

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
    t.pc_hooks[labs['SNDRUN']] = enter
    t.pc_hooks[labs['FSMAN']] = mid
    t.pc_hooks[labs['SNRWP']] = back
    t.pc_hooks[labs['SNRWP'] + 4] = after
    old = t.pc_hooks.get(ta)
    t.pc_hooks[ta] = (lambda m: (old(m) if old else None, tick(m)))
    t.run_frames(args.frames)
    print('%d vblank sound runs, %d left a register changed' % (st['runs'], st['bad']))
    if not st['runs']:
        sys.exit(1)
    if args.mutate:
        sys.exit(0 if st['bad'] else 1)
    sys.exit(1 if st['bad'] else 0)


if __name__ == '__main__':
    main()
