"""Assembled sound return must restore the interrupted hardware/software bank."""
import argparse
from pathlib import Path
import routest


def check(side,caller,bank,mutate):
    t=side.t;L=side.eq;t.exp[:]=side.exp0;t.scratch[:]=side.scr0;t.next_frame=1<<60
    t.bank=(bank+1)%len(t.banks)
    t.ww(L['CURBNK'],0x6000+2*t.bank)
    t.ww(L.get('SNDBNK',0xF042),0x6000+2*bank)
    t.ww(L['SNDWP'],caller);t.ww(L['SNDIN'],0xFFFF)
    t.wp=L['MAINWS']
    for i in range(16):t.setreg(i,0x1400+i*37)
    t.ww(caller+22,0x1234)
    before=bytes(t.scratch[:32]);t.pc=L['SNRWP']
    if mutate:
        def skip(m):m.pc+=10
        t.pc_hooks[L['SNRX']]=skip
    for _ in range(40):
        if t.pc==0x1234:break
        t.step()
    else:raise AssertionError('sound return did not reach caller')
    assert t.bank==bank and t.rw(L['CURBNK'])==0x6000+2*bank,'sound return lost caller ROM bank'
    assert t.wp==caller and bytes(t.scratch[:32])==before,'caller workspace or game registers changed'
    assert t.rw(L['SNDWP'])==0 and t.rw(L['SNDIN'])==0,'sound activity markers remain set'


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--bin');ap.add_argument('--mutate',action='store_true')
    a=ap.parse_args();side=routest.TISide(str(Path(a.bin).resolve().parent) if a.bin else None)
    if 'SNDBNK' in side.eq:
        assert side.eq['BSTKT']<=side.eq['SNDBNK']<0xF060 and side.eq['SNDBNK']%2==0,'sound bank word overlaps runtime storage'
    if a.mutate:
        try:check(side,side.eq['GLUEWS'],0,True)
        except AssertionError as e:
            assert 'bank' in str(e);print('PASS: missing sound bank restoration rejected');return
        raise AssertionError('bank restoration mutation survived')
    for caller in (side.eq['GLUEWS'],side.eq['SNDEWS']):
        for bank in range(len(side.t.banks)):check(side,caller,bank,False)
    print('PASS: both sound callers restore all 16 banks, workspaces and game registers')


if __name__=='__main__':main()
