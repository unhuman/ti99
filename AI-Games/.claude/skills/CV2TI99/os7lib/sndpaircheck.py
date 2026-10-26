"""An arriving frame must not split foreground PLAY_SONGS/SOUND_MAN eligibility.

Run their assembled scheduling prefixes with no debt and a pending frame.
The two native bodies are observed and returned from: this tests eligibility,
while sndtempo.py and the BIOS routine comparisons test real playback.
"""
import argparse
from pathlib import Path
import routest


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--bin',default=str(Path(routest.ROOT)/'build/CARNIVAL_8.bin'))
    ap.add_argument('--mutate',action='store_true')
    a=ap.parse_args();side=routest.TISide(str(Path(a.bin).resolve().parent));t=side.t;e=side.eq
    for name,value in [('PACE',1),('SNDVB',1),('SNDDUE',0),('SNDAGE',0),('SNDBSY',0),
                       ('SNDIN',0),('SNDWP',0),('NMILAT',0),('FRAMEC',0),
                       ('QHEAD',e['QBUF']),('QPTR',e['QBUF']),('QCMT',e['QBUF'])]:
        t.ww(e[name],value)
    t.exp[0xA3C4]=0xC0;t.vdp.reg[1]=0xE0;t.vdp.status=0x80
    t.wp=e['MAINWS'];t.ww(t.wp+24,0);t.st=0
    counts={'PSREAL':0,'FSMAN':0}
    for entry in ('N_PLAYSNG','N_027F'):
        t.pc=e[entry];t.ww(t.wp+22,routest.STOP)
        for _ in range(2000):
            if t.pc==routest.STOP:break
            body=next((name for name in counts if t.pc==e[name]),None)
            if body:
                if not(a.mutate and body=='PSREAL'):counts[body]+=1
                t.pc=t.reg(11)
            else:t.step()
        else:raise AssertionError('sound prefix failed to return')
    valid=counts=={'PSREAL':1,'FSMAN':1} and t.rw(e['SNDDUE'])==0 and t.rw(e['FRAMEC'])==1
    if a.mutate:
        assert not valid,'missing PLAY_SONGS half was not detected'
        print('PASS: missing sound-pair half rejected',counts)
    else:
        assert valid,('frame service split the sound pair',counts,t.rw(e['SNDDUE']))
        print('PASS: pending frame plays both sound halves exactly once')


if __name__=='__main__':main()
