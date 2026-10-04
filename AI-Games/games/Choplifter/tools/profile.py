"""Build an isolated 32-update scrolling benchmark; never alter production source.

Run with Cygwin Python. Load build/profile/PROFILE_8.bin in a separate Classic99
instance at Normal CPU speed. Three numbers are elapsed video frames (lower is
better): empty world, 64 off-screen waiting people, visible waiting crowd.
This measures people/camera/crowd/sprite work, not the entire gameplay loop.
"""
import argparse
import sys
from pathlib import Path
from build import ROOT, CV, XD, run

BENCH = '''
GOTO bench_start
bench_start:
FOR bench_case=0 TO 2
    FOR ini=0 TO 63
        person_state(ini)=0
    NEXT ini
    FOR ini=0 TO 3
        camp_open(ini)=0:camp_released(ini)=16
    NEXT ini
    IF bench_case THEN
        FOR ep=0 TO 63
            person_state(ep)=1
            ec=ep/16
            #person_x(ep)=#camp_x(ec)
            crowd_step=100
            GOSUB escape_walk
        NEXT ep
        FOR ini=0 TO 3
            camp_open(ini)=1
        NEXT ini
    END IF
    #hx=2012
    IF bench_case = 2 THEN #hx=384
    hy=80:old_y=80:runner_on=0:hspeed=3:dt=2
    GOSUB camera_tick
    GOSUB crowd_draw
    #bench_start=FRAME
    FOR bench_i=0 TO 31
        #hx=#hx-8
        anim=anim+2
        GOSUB people_tick
        GOSUB camera_tick
        GOSUB crowd_draw
        GOSUB draw_actors
    NEXT bench_i
    #bench_time=FRAME-#bench_start
    PRINT AT bench_case*32,"CASE ",bench_case,": ",#bench_time
NEXT bench_case
bench_done:
WAIT
GOTO bench_done
'''

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=ROOT/'src/CHOPLIFT.bas')
    parser.add_argument('--assets',type=Path,default=ROOT/'src/assets.bas')
    args=parser.parse_args()
    source=args.source.read_text(encoding='utf-8')
    bench=BENCH
    if 'DIM camp_active(4)' in source:
        bench=bench.replace('camp_open(ini)=0:camp_released(ini)=16',
            'camp_open(ini)=0:camp_released(ini)=16:camp_active(ini)=0')
        bench=bench.replace('IF bench_case THEN','''IF bench_case THEN
        FOR ini=0 TO 3
            camp_active(ini)=16
        NEXT ini''')
    source=source.replace('GOTO title\n','start_lives=3\nGOTO new_game\n',1)
    source=source.replace('\nmain_loop:\n',bench+'\nmain_loop:\n',1)
    # Remove the unused setup UI so instrumentation fits the fixed-code budget.
    first=source.index('\ntitle:\n');last=source.index('\nnew_game:\n',first)
    source=source[:first]+'\ntitle:\nGOTO new_game\n'+source[last:]
    out=ROOT/'build/profile';out.mkdir(parents=True,exist_ok=True)
    (out/'CHOPLIFT.bas').write_text(source,encoding='utf-8',newline='\n')
    (out/'assets.bas').write_bytes(args.assets.read_bytes())
    if 'INCLUDE "menu_font.bas"' in source:
        (out/'menu_font.bas').write_bytes(args.assets.with_name('menu_font.bas').read_bytes())
    run(CV/'cvbasic.exe','--ti994a','CHOPLIFT.bas','CHOPLIFT.a99',str(CV)+'/',cwd=out)
    run(sys.executable,XD/'xas99.py','-b','-R','CHOPLIFT.a99','-L','CHOPLIFT.lst',cwd=out)
    fixed=(out/'CHOPLIFT_b0.bin').read_bytes()
    if len(fixed[16384:-2].rstrip(b'\xff'))>24336:raise RuntimeError('Benchmark code overflow')
    bank=(out/'CHOPLIFT_b3.bin').read_bytes()
    if len(bank)!=8192:raise RuntimeError('Benchmark data-bank overflow')
    run(sys.executable,CV/'linkticart.py','CHOPLIFT_b0.bin','PROFILE_8.bin','CHOP PROFILE',cwd=out)
    path=out/'PROFILE_8.bin';cart=bytearray(path.read_bytes());header=bytes(cart[:80])
    if len(cart)!=32768 or cart[24576:]!=bank:raise RuntimeError('Invalid benchmark cart')
    for offset in (8192,16384):
        if cart[offset:offset+80]==header:cart[offset]=0
    path.write_bytes(cart)
    print('Benchmark only; restore the production cartridge after capture:',path)

if __name__=='__main__':main()
