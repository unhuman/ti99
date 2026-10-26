"""A sound poll must not re-enter the workspace of its frame-service caller."""
import argparse
from pathlib import Path
import routest


def check(side,background,mutate):
    t=side.t;L=side.eq;t.exp[:]=side.exp0;t.scratch[:]=side.scr0;t.next_frame=1<<60
    t.ww(L['PACE'],1);t.ww(L['SNDVB'],0);t.ww(L['SNDWP'],L['GLUEWS'] if background and not mutate else 0)
    t.ww(L['FRAMEC'],0);t.ww(L['QCMT'],L['QBUF']);t.ww(L['QHEAD'],L['QBUF'])
    t.exp[0xA3C4]=0;t.vdp.reg[1]|=0x20;t.vdp.status=0x80
    t.wp=L['MAINWS'];t.ww(t.wp+24,0);t.pc=L['FSEND']
    g=L['GLUEWS']&255
    t.scratch[g+26:g+32]=b'\x83\x00\x12\x34\x24\x00'
    saved=bytes(t.scratch[g+26:g+32])
    stop=L.get('SNDPS',L['SNDPOL']+8)
    for _ in range(200):
        if t.pc==stop:break
        t.step()
    else:raise AssertionError('sound poll did not return')
    if background:
        assert bytes(t.scratch[g+26:g+32])==saved,'sound poll overwrote active GLUE return context'
        assert t.rw(L['FRAMEC'])==0 and t.vdp.int_line(),'background sound consumed its caller interrupt'
    else:
        assert t.rw(L['FRAMEC'])==1,'ordinary game sound did not service pending frame'


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--bin');ap.add_argument('--mutate',action='store_true')
    a=ap.parse_args();side=routest.TISide(str(Path(a.bin).resolve().parent) if a.bin else None)
    try:check(side,True,a.mutate)
    except AssertionError:
        if a.mutate:
            print('PASS: nested sound poll mutation rejected');return
        raise
    assert not a.mutate,'mutation survived'
    check(side,False,False)
    print('PASS: background sound preserves GLUE context; game sound services pending frame')


if __name__=='__main__':main()
