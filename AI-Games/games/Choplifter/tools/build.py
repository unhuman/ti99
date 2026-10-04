"""Sequential reproducible CVBasic build, invoked under Cygwin or native Python."""
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CYG = sys.platform == 'cygwin'
PREFIX = '/cygdrive/c' if CYG else 'C:'
CV = Path(os.environ.get('CVBASIC_DIR', PREFIX+'/Users/Howie/github.git/unhuman/CVBasic'))
XD = Path(os.environ.get('XDT99_DIR', PREFIX+'/Users/Howie/github.git/endlos99/xdt99'))
GASM = Path(os.environ.get('GASM80', PREFIX+'/Users/Howie/github.git/nanochess/gasm80/gasm80.exe'))

def run(*args, cwd=ROOT):
    print('+', ' '.join(map(str,args)), flush=True)
    subprocess.run(list(map(str,args)), cwd=cwd, check=True)

def main():
    target=sys.argv[1]
    out=ROOT/'build'/target
    out.mkdir(parents=True,exist_ok=True)
    run(sys.executable,'-B','assets/generate.py')
    run(sys.executable,'-B','tools/check.py')
    for gate in ('bigvar.py','bigconst.py','gosubtrace.py'):
        run(sys.executable,ROOT.parents[1]/'tools'/gate,ROOT/'src/CHOPLIFT.bas')
    # Copy build inputs, preserving the source INCLUDES and leaving sources clean.
    for f in (ROOT/'src').glob('*.bas'):
        (out/f.name).write_bytes(f.read_bytes())
    if target == 'ti':
        # Delete only this build's known assembler output bank files.
        for f in out.glob('CHOPLIFT_b*.bin'): f.unlink()
        run(CV/'cvbasic.exe','--ti994a','CHOPLIFT.bas','CHOPLIFT.a99',str(CV)+'/',cwd=out)
        run(sys.executable,XD/'xas99.py','-b','-R','CHOPLIFT.a99','-L','CHOPLIFT.lst',cwd=out)
        raw=(out/'CHOPLIFT_b0.bin').read_bytes()
        used=len(raw[16384:-2].rstrip(b'\xff'))
        if used > 24336: raise RuntimeError(f'Fixed area overflow: {used}/24336')
        bank=(out/'CHOPLIFT_b3.bin').read_bytes()
        if len(bank) != 8192: raise RuntimeError(f'Unexpected data-bank size {len(bank)}')
        run(sys.executable,CV/'linkticart.py','CHOPLIFT_b0.bin','CHOPLIFT_8.bin','CHOPLIFTER',cwd=out)
        cartpath=out/'CHOPLIFT_8.bin'
        cart=bytearray(cartpath.read_bytes())
        if len(cart) != 32768: raise RuntimeError('Expected a 32 KB cart')
        if cart[24576:] != bank: raise RuntimeError('Packed data bank does not match assembly')
        hdr=bytes(cart[:80])
        for off in (8192,16384):
            if cart[off:off+80] == hdr: cart[off]=0
        cartpath.write_bytes(cart)
        bank_used=len(bank[:-2].rstrip(b'\xff'))
        print(f'TI fixed: {used}/24336; data bank: {bank_used}/8190; cart: {len(cart)} bytes')
        # The single multiply in flight must store the low word, then reload at a label.
        asm=(out/'CHOPLIFT.a99').read_text()
        assert re.search(r'mpy\s+r1,r0\s+mov\s+r1,@cvb__MOVE',asm,re.I)
        assert re.search(r'^cvb_MOVE_HELI\s*$',asm,re.M)
        assert re.search(r'cvb_MOVE_HELI\s.*?mov @cvb__MOVE,r0',asm,re.S)
    else:
        run(CV/'cvbasic.exe','CHOPLIFT.bas','CHOPLIFT.asm',str(CV)+'/',cwd=out)
        run(GASM,'CHOPLIFT.asm','-o','choplift.rom',cwd=out)
        print(f'Coleco ROM: {(out/"choplift.rom").stat().st_size} bytes')
    print('Build OK:',out)

if __name__ == '__main__': main()
