"""Frame service must retain every sound update while sound cannot re-enter."""
import argparse
from pathlib import Path
import routest


def check(side, blocker, mutate):
    t=side.t;L=side.eq;t.exp[:]=side.exp0;t.scratch[:]=side.scr0;t.next_frame=1<<60
    t.ww(L['SNDVB'],0xFFFF);t.ww(L['SNDAGE'],0);t.ww(L['SNDDUE'],0)
    t.ww(L['SNDIN'],0);t.ww(L['SNDBSY'],0);t.ww(L[blocker],1)
    t.wp=L['GLUEWS'];t.setreg(11,routest.STOP)
    if mutate:
        def clamp(m):
            m.ww(L['SNDDUE'],min(2,m.rw(L['SNDDUE'])))
        t.pc_hooks[L['SNV3']]=clamp
    for owed in range(1,7):
        t.pc=L['SNDVBL']
        for _ in range(40):
            if t.pc==routest.STOP:break
            t.step()
        else:raise AssertionError('busy sound re-entered instead of returning')
        assert t.rw(L['SNDDUE'])==owed,'sound frame debt was discarded'
        if owed>=2:assert t.rw(L['SNDPND']),'busy sound was not marked pending'
    t.pc_hooks.pop(L['SNV3'],None)


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--bin');ap.add_argument('--mutate',action='store_true')
    a=ap.parse_args();side=routest.TISide(str(Path(a.bin).resolve().parent) if a.bin else None)
    if a.mutate:
        try:check(side,'SNDIN',True)
        except AssertionError as e:
            assert 'discarded' in str(e);print('PASS: discarded sound debt mutation rejected');return
        raise AssertionError('sound debt mutation survived')
    for blocker in ('SNDIN','SNDBSY'):check(side,blocker,False)
    print('PASS: six owed updates retained for both active sound and PLAY_IT')


if __name__=='__main__':main()
