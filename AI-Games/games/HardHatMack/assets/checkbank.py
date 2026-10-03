"""Check the TI data bank's bounds and exact preservation in the packed cart."""
from pathlib import Path
import re

SRC = Path(__file__).resolve().parent.parent / 'src'


def check(bank, cart, marker, page=3):
    assert len(bank) == 8192, 'data bank must occupy exactly one 8K page'
    assert len(cart) == 65536, 'expected padded 64K cart with three data/code banks'
    assert cart[page*8192:(page+1)*8192] == bank, 'packed bank differs from assembly'
    assert bank.count(marker) == 1, 'end-of-assets marker lost or duplicated'
    end = bank.index(marker) + len(marker)
    assert bank[end:8190] == b'\xff' * (8190 - end), 'unexpected bytes beyond assets'
    return 8190 - end


if __name__ == '__main__':
    text = (SRC / 'HARDHAT.bas').read_text(encoding='utf-8')
    data = re.search(r'asset_end:\s+DATA BYTE ([\d,]+)', text).group(1)
    marker = bytes(map(int, data.split(',')))
    bank = (SRC / 'HARDHAT_b3.bin').read_bytes()
    cart = (SRC / 'HARDHAT_8.bin').read_bytes()
    free = check(bank, cart, marker)
    animation_marker=bytes(map(int,re.search(r'animation_end:\s+DATA BYTE ([\d,]+)',text).group(1).split(',')))
    animation_bank=(SRC / 'HARDHAT_b4.bin').read_bytes()
    animation_free=check(animation_bank,cart,animation_marker,4)
    title_marker=bytes(map(int,re.search(r'title_end:\s+DATA BYTE ([\d,]+)',text).group(1).split(',')))
    title_bank=(SRC / 'HARDHAT_b5.bin').read_bytes()
    title_free=check(title_bank,cart,title_marker,5)
    for damaged in (cart[:40960],cart[:40960]+bytes(8192)+cart[49152:]):
        try:check(title_bank,damaged,title_marker,5)
        except AssertionError:pass
        else:raise AssertionError('accepted missing/corrupted title bank')
    for damaged in (cart[:32768],cart[:32768]+bytes(8192)+cart[40960:]):
        try:check(animation_bank,damaged,animation_marker,4)
        except AssertionError:pass
        else:raise AssertionError('accepted missing/corrupted animation bank')
    # Negative cases: truncation, oversized bank and damaged packed data.
    for bad_bank, bad_cart in [(bank[:-2], cart), (bank + b'xx', cart),
                               (bank, cart[:24576] + bytes(8192)+cart[32768:])]:
        try:
            check(bad_bank, bad_cart, marker)
        except AssertionError:
            continue
        raise AssertionError('bank checker accepted corrupted output')
    print('TI data bank: exact packed match; %d bytes free; negative cases rejected' % free)
    print('TI animation bank: exact packed match; %d bytes free; negative cases rejected' % animation_free)
    print('TI title bank: exact packed match; %d bytes free; negative cases rejected' % title_free)
