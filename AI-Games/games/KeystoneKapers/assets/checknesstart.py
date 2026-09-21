"""Reject a NES review ROM whose round-start coordinates were left altered."""
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent

def check(assembly, rom, basic):
    pattern = bytearray()
    for name, value in (('KLV',0), ('KLSC',7), ('KLX',120)):
        match = re.search(r'^cvb_'+name+r':\s*equ \$([0-9a-fA-F]+)', assembly, re.M)
        if not match:
            raise ValueError('Missing compiled start variable: '+name)
        address = int(match[1],16)
        pattern.extend((0xa9,value))
        pattern.extend((0x85,address) if address < 256 else (0x8d,address&255,address>>8))
    if rom.count(pattern) != 1:
        raise ValueError('NES ROM must start each round on floor 0, screen 7, x=120; review patch or compiler layout change detected')
    for start, end in (('new_game','start_krook'), ('do_catch','bonus_count'), ('lose_kop','snd_off')):
        body = basic.split('\n'+start+':',1)[1].split('\n'+end+':',1)[0]
        if not re.search(r'^\s*GOSUB start_krook\s*$',body,re.M):
            raise ValueError(start+' no longer uses the normal round reset')

if __name__ == '__main__':
    src=HERE.parent/'src'
    try:
        check((src/'keystone_nes.asm').read_text(), (src/'keystone.nes').read_bytes(), (src/'KEYSTONE.bas').read_text())
    except (ValueError, IndexError) as error:
        sys.exit('FAIL: '+str(error))
    print('NES start OK: new game, next level and lost life use floor 0 / screen 7 / x120')
