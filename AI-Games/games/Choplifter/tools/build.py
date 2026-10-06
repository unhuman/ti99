"""Sequential reproducible CVBasic build, invoked under Cygwin or native Python."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CYG = sys.platform == 'cygwin'
PREFIX = '/cygdrive/c' if CYG else 'C:'
CV = Path(os.environ.get('CVBASIC_DIR', PREFIX+'/Users/Howie/github.git/unhuman/CVBasic'))
XD = Path(os.environ.get('XDT99_DIR', PREFIX+'/Users/Howie/github.git/endlos99/xdt99'))
GASM = Path(os.environ.get('GASM80', PREFIX+'/Users/Howie/github.git/nanochess/gasm80/gasm80.exe'))
# The shared, verified TMS9900 long-branch shortener (also used by Hard Hat Mack).
SHORT = ROOT.parent/'KeystoneKapers'/'assets'/'shortbranches.py'
FIXED_CAP = 24336

def run(*args, cwd=ROOT):
    print('+', ' '.join(map(str,args)), flush=True)
    subprocess.run(list(map(str,args)), cwd=cwd, check=True)

def fixed_used(out, name):
    raw=(out/f'{name}_b0.bin').read_bytes()
    return len(raw[16384:-2].rstrip(b'\xff'))

def assemble(out, name):
    for f in out.glob(f'{name}_b*.bin'): f.unlink()
    run(sys.executable,XD/'xas99.py','-b','-R',f'{name}.a99','-L',f'{name}.lst','-E',f'{name}.equ',cwd=out)

def build_ti(out, name, title):
    """Compile, assemble, shorten branches, check budgets and pack a 32 KB cart.
    Returns (fixed bytes used, unoptimised fixed bytes, data-bank bytes used)."""
    run(CV/'cvbasic.exe','--ti994a',f'{name}.bas',f'{name}.a99',str(CV)+'/',cwd=out)
    assemble(out, name)
    unopt=fixed_used(out, name)
    # xas99's first pass rejects short jumps straddling >FFFF, so the
    # unoptimised image must still fit below >FFFE (CLAUDE.md section 3A).
    if unopt > 0xFFFE-0xA000:
        raise RuntimeError(f'Unoptimised fixed code {unopt} reaches >FFFE: bank something first')
    if os.environ.get('TI_SHORT_BRANCHES','1') == '1':
        for ext in ('a99','lst'):
            shutil.copyfile(out/f'{name}.{ext}', out/f'{name}.unopt.{ext}')
        files=[f'{name}.unopt.a99',f'{name}.unopt.lst',f'{name}.a99',f'{name}.lst',f'{name}.branches.json']
        run(sys.executable,SHORT,'rewrite',*files,cwd=out)
        assemble(out, name)
        run(sys.executable,SHORT,'verify',*files,cwd=out)
    used=fixed_used(out, name)
    if used > FIXED_CAP: raise RuntimeError(f'Fixed area overflow: {used}/{FIXED_CAP}')
    bank=(out/f'{name}_b3.bin').read_bytes()
    if len(bank) != 8192: raise RuntimeError(f'Unexpected data-bank size {len(bank)}')
    run(sys.executable,CV/'linkticart.py',f'{name}_b0.bin',f'{name}_8.bin',title,cwd=out)
    cartpath=out/f'{name}_8.bin'
    cart=bytearray(cartpath.read_bytes())
    if len(cart) != 32768: raise RuntimeError('Expected a 32 KB cart')
    if cart[24576:] != bank: raise RuntimeError('Packed data bank does not match assembly')
    # One TI menu entry: blank the copied headers on loader pages 1 and 2.
    hdr=bytes(cart[:80])
    for off in (8192,16384):
        if cart[off:off+80] == hdr: cart[off]=0
    cartpath.write_bytes(cart)
    return used, unopt, len(bank[:-2].rstrip(b'\xff'))

def word_tables_even(out, name):
    """Every word table the code indexes (ai r0,label / mov *r0) must start on
    an even address: the TMS9900 ignores bit 0, so an odd table reads shifted
    by a byte with no error (CLAUDE.md section 3A, odd DATA BYTE blocks).
    The label's value comes from xas99's symbol file: xas99 pads the DATA
    itself to an even address, but a label on its own line keeps the odd
    location, so the next emitted address in the listing looks fine."""
    asm=(out/f'{name}.a99').read_text()
    symbols={k.lower():int(v,16) for k,v in
             re.findall(r'^(\S+):\s*\n\s+equ\s+>([0-9A-Fa-f]+)',(out/f'{name}.equ').read_text(),re.M)}
    tables=set(re.findall(r'ai r0,(cvb__\w+)\s*\n\s*mov \*r0',asm))
    if not tables: raise RuntimeError('word-table check found no indexed word tables')
    for label in sorted(tables):
        addr=symbols[label.lower()]
        if addr%2: raise RuntimeError(f'word table {label} at odd address >{addr:04X}')
    print('Word tables on even addresses:',', '.join(sorted(tables)))

def main():
    target=sys.argv[1]
    out=ROOT/'build'/target
    out.mkdir(parents=True,exist_ok=True)
    run(sys.executable,'-B','assets/generate.py')
    # The source-executing tests are target-independent: build.ps1 All runs
    # them with the first target only (CHOP_TESTS_DONE=1 for the rest).
    if os.environ.get('CHOP_TESTS_DONE') != '1':
        run(sys.executable,'-B','tools/check.py')
    for gate in ('bigvar.py','bigconst.py','gosubtrace.py'):
        run(sys.executable,ROOT.parents[1]/'tools'/gate,ROOT/'src/CHOPLIFT.bas')
    # Copy build inputs, preserving the source INCLUDES and leaving sources clean.
    for f in (ROOT/'src').glob('*.bas'):
        (out/f.name).write_bytes(f.read_bytes())
    if target == 'ti':
        used,unopt,bank_used=build_ti(out,'CHOPLIFT','CHOPLIFTER')
        print(f'TI fixed: {used}/{FIXED_CAP} (unoptimised {unopt}); data bank: {bank_used}/8190; cart: 32768 bytes')
        # The single multiply in flight must store the low word, then reload at a label.
        asm=(out/'CHOPLIFT.a99').read_text()
        assert re.search(r'mpy\s+r1,r0\s+mov\s+r1,@cvb__MOVE',asm,re.I)
        assert re.search(r'^cvb_MOVE_HELI\s*$',asm,re.M)
        assert re.search(r'cvb_MOVE_HELI\s.*?mov @cvb__MOVE,r0',asm,re.S)
        # The sprite-bit table must be read as words (#label), never bytes.
        assert re.search(r'sla r0,1\s+ai r0,cvb__SPRITE_BIT\s+mov \*r0',asm)
        assert not re.search(r'ai r0,cvb_SPRITE_BIT\b',asm)
        word_tables_even(out,'CHOPLIFT')
    else:
        run(CV/'cvbasic.exe','CHOPLIFT.bas','CHOPLIFT.asm',str(CV)+'/',cwd=out)
        run(GASM,'CHOPLIFT.asm','-o','choplift.rom',cwd=out)
        print(f'Coleco ROM: {(out/"choplift.rom").stat().st_size} bytes')
    print('Build OK:',out)

if __name__ == '__main__': main()
