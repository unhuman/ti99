"""TI-99/4A emulator for A82TI99 carts: the cycle-counting TMS9900 core
from ti99emu_base (DonkeyKong/MsPacFst tools) with the VDP replaced by the
shared vdp.VDP model, so the TI build and the ColecoVision reference
(z80emu.py) compute status, collisions and screenshots the same way.

    t = load('build/RIVERRAID_8.bin'); t.run_frames(600); t.vdp.png('x.png')
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import ti99emu_base as base
from vdp import VDP


class TI(base.TI99):
    def __init__(self, rom, grom, banks):
        super().__init__(rom, grom, banks)
        self.vdp = VDP()
        self.sound_log = []
        self.pc_hooks = {}

    # VDP ports through the shared model
    def rw(self, a):
        a &= 0xFFFE
        if 0x8800 <= a < 0x8C00:
            self.cycles += 4
            if a & 2:
                return self.vdp.read_status() << 8
            return self.vdp.read_data() << 8
        return super().rw(a)

    def ww(self, a, v):
        a &= 0xFFFE
        if 0x8C00 <= a < 0x9000:
            self.cycles += 4
            b = (v >> 8) & 0xFF
            if a & 2:
                self.vdp.write_ctrl(b)
            else:
                self.vdp.write_data(b)
            return
        if 0x8400 <= a < 0x8800:
            self.sound_log.append((self.cycles, (v >> 8) & 0xFF))
        return super().ww(a, v)

    def cru_read(self, bit):
        b = bit & 0xFFF
        if b < 0x400 and (b & 0x1F) == 2:
            return 0 if self.vdp.int_line() else 1
        return super().cru_read(bit)

    def vdp_frame(self):
        self.vdp.vblank()

    def step(self):
        if self.pc_hooks and self.pc in self.pc_hooks:
            self.pc_hooks[self.pc](self)
        # the real VDP interrupt through the console ROM (the CV2TI99 carts poll instead)
        if (self.st & 0xF) >= 1 and self.int_mask9901 and not self.cru_mode and self.vdp.int_line():
            self.context_switch(0x0004)
            self.st &= ~0xF
            self.cycles += 22
            self.nint = getattr(self, 'nint', 0) + 1
        super().step()

    def start_cart(self):
        """Skip the console menu: enter the cart at START (bank 0)."""
        b = self.banks[0]
        prog = (b[6] << 8) | b[7]
        o = prog - 0x6000
        self.pc = (b[o + 2] << 8) | b[o + 3]
        self.wp = 0x8300
        self.st = 0
        self.bank = 0


def start_game(t, key='1', extra=5):
    """Run to the option screen (blue backdrop), press key, release."""
    while t.vdp.reg[7] & 15 != 4:
        t.run_frames(5)
    t.run_frames(extra)
    t.pressed.add(key)
    t.run_frames(10)
    t.pressed.discard(key)


def load(path, romdir):
    data = open(path, 'rb').read()
    banks = [data[i:i + 8192] for i in range(0, len(data), 8192)]
    rom = open(os.path.join(romdir, '994arom.bin'), 'rb').read()
    grom = open(os.path.join(romdir, '994agrom.bin'), 'rb').read()
    t = TI(rom, grom, banks)
    t.start_cart()
    return t


