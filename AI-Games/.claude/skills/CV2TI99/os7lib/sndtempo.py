"""The os7 vblank sound plays exactly once a vblank (TI only, PACE).

    sndtempo.py [--frames 1500] [--seed 1] [--mutate]

With the vblank sound on (os7.a99 SNDDUE), each vblank's sound is played
either by the game's own SOUND_MAN / PLAY_SONGS call (when one is due)
or by the vblank itself (SNDRUN, when a long tick left two due).  The
music keeps the ColecoVision's tempo only if the engine runs once a
vblank: this counts the real SOUND_MAN runs (FSMAN) and PLAY_SONGS runs
(PSREAL) against the vblanks that owe one (SNV0: the game has called
SOUND_MAN within 12 vblanks), and fails if either drifts by more than 2.  --mutate skips every tenth
SOUND_MAN run: it must fail.
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
    st = {'f0': None, 'sm': 0, 'ps': 0, 'worst': 0, 'skip': 0, 'vb': 0}

    def on(m):
        return m.rw(labs['SNDVB']) != 0

    def fsman(m):
        if not on(m):
            return
        if st['f0'] is None:
            st['f0'] = 1
        st['skip'] += 1
        if args.mutate and st['skip'] % 10 == 0:
            m.pc = m.reg(11)          # skip the run
            return
        st['sm'] += 1

    def psreal(m):
        if on(m) and st['f0'] is not None:
            st['ps'] += 1

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
        if st['f0'] is not None:
            vb = st['vb']
            st['worst'] = max(st['worst'], abs(vb - st['sm']), abs(vb - st['ps']))
    t.pc_hooks[labs['FSMAN']] = fsman
    t.pc_hooks[labs['PSREAL']] = psreal

    def owed(m):
        if st['f0'] is not None:
            st['vb'] += 1
    t.pc_hooks[labs['SNV0']] = owed
    old = t.pc_hooks.get(ta)
    t.pc_hooks[ta] = (lambda m: (old(m) if old else None, tick(m)))
    t.run_frames(args.frames)
    vb = st['vb']
    print('vblanks %d, SOUND_MAN runs %d, PLAY_SONGS runs %d, worst drift %d' % (vb, st['sm'], st['ps'], st['worst']))
    bad = st['f0'] is None or st['worst'] > 2
    if args.mutate:
        sys.exit(0 if bad else 1)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
