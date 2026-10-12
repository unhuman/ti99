"""Route the NES in-round tune through nes_mus_simple (assets/nes_apu.asm).

CVBasic's NES music_hardware plays PLAY SIMPLE's two voices on the two pulse
channels, and every Keystone effect plays on a pulse as well, so the game used
to stop the tune for each one (music_duck). This makes the SIMPLE path jump to
nes_mus_simple instead, which puts the bass on the triangle (no effect uses it
in a round) and the melody on pulse 2, lent to an effect while one sounds.
PLAY FULL -- the title -- keeps the stock code.

Patches this game's generated assembly only, never the shared compiler, and
fails if the runtime text it hooks has changed.
"""
from pathlib import Path
import sys

HEAD = ('music_hardware:\n'
        '\tLDA music_mode\n'
        '\tCMP #4\t\t; PLAY SIMPLE?\n'
        '\tBCC .9\t\t; Yes, jump.\n')

HOOKED = ('music_hardware:\n'
          '\tLDA music_mode\n'
          '\tCMP #4\t\t; PLAY SIMPLE?\n'
          '\tBCS .kk_full\n'
          '\tJMP nes_mus_simple\t; Keystone: assets/musicown.py\n'
          '.kk_full:\n')


def patch(source):
    if source.count(HEAD) != 1:
        raise ValueError('NES music_hardware changed; cannot safely hook it')
    if 'nes_mus_simple:' not in source:
        raise ValueError('nes_mus_simple (assets/nes_apu.asm) is not in the assembly')
    return source.replace(HEAD, HOOKED, 1)


if __name__ == '__main__':
    path = Path(sys.argv[1])
    path.write_text(patch(path.read_text()))
