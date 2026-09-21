"""Add guarded forced-blank writes to this game's generated NES runtime only."""
from pathlib import Path
import sys


def patch(source):
    def once(old, new):
        nonlocal source
        if source.count(old) != 1:
            raise ValueError('NES runtime changed; cannot safely hook ' + repr(old))
        source = source.replace(old, new, 1)

    once('WRTVRM:\n', 'WRTVRM:\n\tBIT mode\n\tBMI.L nes_fast_poke\n')
    once('LDIRVM:\n', 'LDIRVM:\n\tBIT mode\n\tBMI.L nes_fast_copy\n')
    once('\nwait:\n', '\nwait:\n\tBIT mode\n\tBPL .normal\n\tRTS\n.normal:\n')
    once('\t; Load sprites\n', '\tBIT mode\n\tBMI.L .fast_skip\n\t; Load sprites\n')
    once('\t; Read controllers\n', '.fast_skip:\n\t; Read controllers\n')
    return source


if __name__ == '__main__':
    path = Path(sys.argv[1])
    source = patch(path.read_text())
    shim = Path(__file__).with_name('nes_fast.asm').read_text()
    if source.count('rom_end:\n') != 1:
        raise ValueError('Missing NES shim insertion point')
    path.write_text(source.replace('rom_end:\n', shim + '\nrom_end:\n'))
