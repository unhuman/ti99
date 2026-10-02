"""Check the TI data bank's bounds and exact preservation in the packed cart."""
from pathlib import Path
import re

SRC = Path(__file__).resolve().parent.parent / 'src'


def check(bank, cart, marker):
    assert len(bank) == 8192, 'data bank must occupy exactly one 8K page'
    assert len(cart) == 32768, 'expected three loader pages and one data page'
    assert cart[24576:32768] == bank, 'packed data bank differs from assembly'
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
    # Negative cases: truncation, oversized bank and damaged packed data.
    for bad_bank, bad_cart in [(bank[:-2], cart), (bank + b'xx', cart),
                               (bank, cart[:24576] + bytes(8192))]:
        try:
            check(bad_bank, bad_cart, marker)
        except AssertionError:
            continue
        raise AssertionError('bank checker accepted corrupted output')
    print('TI data bank: exact packed match; %d bytes free; negative cases rejected' % free)
