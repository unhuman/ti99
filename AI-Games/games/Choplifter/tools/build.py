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

def check_sortie_title_reload(asm):
    """TI inline ASM changes r0, but CVBasic caches the previous value of ini.
    The title SCREEN must receive a fresh ini value after the bar copy."""
    title=re.search(r'(?m)^[ \t]*; SCREEN sortie_titles,ini,361,14,1[ \t]*$',asm)
    copies=list(re.finditer(r'(?m)^[ \t]*; ASM data CPYBLK[ \t]*$',asm))
    if not title or not copies:
        raise RuntimeError('Cannot find TI sortie bar copy and title SCREEN')
    copy=max((m for m in copies if m.end()<title.start()),key=lambda m:m.start(),default=None)
    if copy is None:
        raise RuntimeError('Cannot find TI sortie bar copy before title SCREEN')
    section=asm[copy.end():title.start()]
    instructions=[line.strip() for line in section.splitlines()
                  if line.strip() and not line.lstrip().startswith(';')]
    if instructions!=['data CPYBLK','movb @cvb_INI,r0']:
        raise RuntimeError(f'TI sortie title uses stale r0 after bar copy: {instructions}')
    return copy.end(),title.start()

def build_ti(out, name, title):
    """Compile, assemble, shorten branches, check budgets and pack a 32 KB cart.
    Returns (fixed bytes used, unoptimised fixed bytes, data-bank bytes used)."""
    run(CV/'cvbasic.exe','--ti994a',f'{name}.bas',f'{name}.a99',str(CV)+'/',cwd=out)
    asm=(out/f'{name}.a99').read_text()
    start,end=check_sortie_title_reload(asm)
    bad_section=re.sub(r'(?m)^[ \t]*movb @cvb_INI,r0[ \t]*\n','',asm[start:end],count=1)
    if bad_section==asm[start:end]:
        raise RuntimeError('TI sortie reload self-test could not remove the reload')
    try:
        check_sortie_title_reload(asm[:start]+bad_section+asm[end:])
    except RuntimeError:
        pass
    else:
        raise RuntimeError('TI sortie reload check accepts missing reload')
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
    # BANK 1 (physical 3) is the data bank, selected for good at start-up;
    # BANK 2 (physical 4) holds art uploaded only at power-on.
    if (out/f'{name}_b5.bin').exists(): raise RuntimeError('Unexpected third bank')
    banks=[(out/f'{name}_b{n}.bin').read_bytes() for n in (3,4)]
    for n,bank in zip((3,4),banks):
        if len(bank) != 8192: raise RuntimeError(f'Unexpected bank {n} size {len(bank)}')
    run(sys.executable,CV/'linkticart.py',f'{name}_b0.bin',f'{name}_8.bin',title,cwd=out)
    cartpath=out/f'{name}_8.bin'
    cart=bytearray(cartpath.read_bytes())
    if len(cart) != 65536: raise RuntimeError('Expected a 64 KB cart')
    for page,bank in zip((3,4),banks):
        if cart[page*8192:(page+1)*8192] != bank: raise RuntimeError(f'Packed bank {page} does not match assembly')
    # One TI menu entry: blank the copied headers on the loader and padding pages.
    hdr=bytes(cart[:80])
    for off in range(8192,len(cart),8192):
        if cart[off:off+80] == hdr: cart[off]=0
    cartpath.write_bytes(cart)
    return used, unopt, [len(bank[:-2].rstrip(b'\xff')) for bank in banks]

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
        used,unopt,(data_used,boot_used)=build_ti(out,'CHOPLIFT','CHOPLIFTER')
        print(f'TI fixed: {used}/{FIXED_CAP} (unoptimised {unopt}); data bank: {data_used}/8190;'
              f' boot bank: {boot_used}/8190; cart: 65536 bytes')
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
