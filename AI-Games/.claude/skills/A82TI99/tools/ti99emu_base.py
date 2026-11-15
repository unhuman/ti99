"""Minimal cycle-counting TI-99/4A emulator for profiling cartridge code.

TMS9900 core + TMS9918A VDP + GROM + 9901 keyboard/interrupt, with the
4-cycle wait state on every 8-bit-bus access (everything except console
ROM >0000->1FFF and scratchpad >8000->83FF).  Non-inverted bank switching
(write to >6000+2n selects bank n).
"""
import struct

ST_LGT, ST_AGT, ST_EQ, ST_C, ST_OV, ST_OP, ST_X = 0x8000, 0x4000, 0x2000, 0x1000, 0x0800, 0x0400, 0x0200

FRAME_CYCLES = 50050          # 3.0 MHz / 59.94 Hz

# keyboard matrix: name -> (column, row)
KEYS = {
    '=': (0, 0), ' ': (0, 1), 'ENTER': (0, 2), 'FCTN': (0, 4), 'SHIFT': (0, 5), 'CTRL': (0, 6),
    '.': (1, 0), 'L': (1, 1), 'O': (1, 2), '9': (1, 3), '2': (1, 4), 'S': (1, 5), 'W': (1, 6), 'X': (1, 7),
    ',': (2, 0), 'K': (2, 1), 'I': (2, 2), '8': (2, 3), '3': (2, 4), 'D': (2, 5), 'E': (2, 6), 'C': (2, 7),
    'M': (3, 0), 'J': (3, 1), 'U': (3, 2), '7': (3, 3), '4': (3, 4), 'F': (3, 5), 'R': (3, 6), 'V': (3, 7),
    'N': (4, 0), 'H': (4, 1), 'Y': (4, 2), '6': (4, 3), '5': (4, 4), 'G': (4, 5), 'T': (4, 6), 'B': (4, 7),
    '/': (5, 0), ';': (5, 1), 'P': (5, 2), '0': (5, 3), '1': (5, 4), 'A': (5, 5), 'Q': (5, 6), 'Z': (5, 7),
    'J1FIRE': (6, 0), 'J1LEFT': (6, 1), 'J1RIGHT': (6, 2), 'J1DOWN': (6, 3), 'J1UP': (6, 4),
    'J2FIRE': (7, 0), 'J2LEFT': (7, 1), 'J2RIGHT': (7, 2), 'J2DOWN': (7, 3), 'J2UP': (7, 4),
}


def parity(b):
    b &= 0xFF
    b ^= b >> 4
    b ^= b >> 2
    b ^= b >> 1
    return b & 1


class TI99:
    def __init__(self, rom, grom, banks):
        self.rom = bytearray(rom)
        self.grom = bytearray(65536)
        self.grom[:len(grom)] = grom
        self.banks = [bytearray(b) for b in banks]
        self.nbanks = len(self.banks)
        self.bank = 0
        self.scratch = bytearray(256)
        self.exp = bytearray(65536)        # >2000->3FFF and >A000->FFFF
        self.exp_used = set()
        self.vram = bytearray(16384)
        self.vreg = [0] * 8
        self.vaddr = 0
        self.vlatch = None
        self.vstatus = 0
        self.vreadbuf = 0
        self.gaddr = 0
        self.glatch = None
        self.gread_hi = True
        self.cru_mode = 0
        self.clk_reg = 0; self.clk_start = 0; self.clk_latch = 0     # 9901 timer: 3 MHz / 64, counts down
        self.int_mask9901 = 0
        self.kbd_col = 0
        self.alpha = 1
        self.pressed = set()
        self.cycles = 0
        self.next_frame = FRAME_CYCLES
        self.frame = 0
        self.pc = 0
        self.wp = 0
        self.st = 0
        self.prof = None           # dict (bank,pc) -> cycles
        self.pcnt = None           # dict (bank,pc) -> executions (with prof)
        self.icount = 0
        self.sound_writes = 0
        self.trace = None
        self.on_frame = None
        self.reset()

    # ------------------------------------------------------------ memory
    def reset(self):
        self.wp = self.rom_word(0)
        self.pc = self.rom_word(2)
        self.st = 0

    def rom_word(self, a):
        return (self.rom[a] << 8) | self.rom[a + 1]

    def slow(self, a):
        return not (a < 0x2000 or 0x8000 <= a < 0x8400)

    def rw(self, a):
        """Read a word (CPU access, with side effects)."""
        a &= 0xFFFE
        if a < 0x2000:
            return (self.rom[a] << 8) | self.rom[a + 1]
        self.cycles += 4
        if a < 0x4000:
            self.exp_used.add(a)
            return (self.exp[a] << 8) | self.exp[a + 1]
        if a < 0x6000:
            return 0
        if a < 0x8000:
            b = self.banks[self.bank]
            o = a - 0x6000
            return (b[o] << 8) | b[o + 1]
        if a < 0x8400:
            self.cycles -= 4
            o = a & 0xFF
            return (self.scratch[o] << 8) | self.scratch[o + 1]
        if a < 0x8800:
            return 0
        if a < 0x8C00:
            if a & 2:
                v = self.vstatus
                self.vstatus &= 0x1F
                self.vlatch = None
                return v << 8
            v = self.vreadbuf
            self.vreadbuf = self.vram[self.vaddr]
            self.vaddr = (self.vaddr + 1) & 0x3FFF
            self.vlatch = None
            return v << 8
        if a < 0x9000:
            return 0
        if a < 0x9800:
            return 0
        if a < 0x9C00:
            if a & 2:
                if self.gread_hi:
                    self.gread_hi = False
                    return ((self.gaddr + 1) & 0xFF00)
                self.gread_hi = True
                return ((self.gaddr + 1) & 0xFF) << 8
            v = self.grom[self.gaddr]
            self.gaddr = (self.gaddr & 0xE000) | ((self.gaddr + 1) & 0x1FFF)
            self.glatch = None
            return v << 8
        if a < 0xA000:
            return 0
        self.exp_used.add(a)
        return (self.exp[a] << 8) | self.exp[a + 1]

    def touch(self, a):
        """Read-before-write cycle cost, no device side effects."""
        if self.slow(a & 0xFFFE):
            self.cycles += 4

    def ww(self, a, v):
        a &= 0xFFFE
        v &= 0xFFFF
        if a < 0x2000:
            return
        self.cycles += 4
        if a < 0x4000:
            self.exp_used.add(a)
            self.exp[a] = v >> 8
            self.exp[a + 1] = v & 0xFF
            return
        if a < 0x6000:
            return
        if a < 0x8000:
            self.bank = (a >> 1) % self.nbanks
            return
        if a < 0x8400:
            self.cycles -= 4
            o = a & 0xFF
            self.scratch[o] = v >> 8
            self.scratch[o + 1] = v & 0xFF
            return
        if a < 0x8800:
            self.sound_writes += 1
            self.cycles += 24          # sound chip READY hold-off
            return
        if a < 0x8C00:
            return
        if a < 0x9000:
            b = v >> 8
            if a & 2:
                if self.vlatch is None:
                    self.vlatch = b
                else:
                    lo = self.vlatch
                    self.vlatch = None
                    if b & 0x80:
                        self.vreg[b & 7] = lo
                    else:
                        self.vaddr = ((b & 0x3F) << 8) | lo
                        if not (b & 0x40):
                            self.vreadbuf = self.vram[self.vaddr]
                            self.vaddr = (self.vaddr + 1) & 0x3FFF
            else:
                self.vram[self.vaddr] = b
                self.vreadbuf = b
                self.vaddr = (self.vaddr + 1) & 0x3FFF
                self.vlatch = None
            return
        if a < 0x9800:
            return
        if a < 0x9C00:
            return
        if a < 0xA000:
            b = v >> 8
            if a & 2:
                if self.glatch is None:
                    self.glatch = b
                else:
                    self.gaddr = (self.glatch << 8) | b
                    self.glatch = None
                self.gread_hi = True
            return
        self.exp_used.add(a)
        self.exp[a] = v >> 8
        self.exp[a + 1] = v & 0xFF

    def rb(self, a):
        w = self.rw(a)
        return (w >> 8) if not (a & 1) else (w & 0xFF)

    def wb(self, a, b):
        """Byte write: TMS9900 writes the whole word; only the addressed byte changes."""
        a &= 0xFFFF
        if a >= 0x8400 and a < 0xA000:
            # memory-mapped device: only the high byte matters
            self.ww(a & 0xFFFE, (b & 0xFF) << 8)
            return
        if 0x6000 <= a < 0x8000:
            self.ww(a, 0)
            return
        # plain memory: read the word without side effects
        ea = a & 0xFFFE
        if ea < 0x2000:
            return
        if 0x8000 <= ea < 0x8400:
            self.scratch[a & 0xFF] = b & 0xFF
            return
        self.cycles += 4
        self.exp_used.add(ea)
        self.exp[a] = b & 0xFF

    # ------------------------------------------------------------ CRU
    def cru_read(self, bit):
        bit &= 0xFFF
        if bit < 0x400 and (bit & 0x1F) < 32:
            b = bit & 0x1F
            if b == 0:
                return self.cru_mode
            if self.cru_mode and 1 <= b <= 14:          # clock mode: the decrementer, latched on entry
                return (self.clk_latch >> (b - 1)) & 1
            if b == 2:
                return 0 if (self.vstatus & 0x80 and self.vreg[1] & 0x20) else 1
            if 3 <= b <= 10:
                row = b - 3
                col = self.kbd_col
                for k in self.pressed:
                    c, r = KEYS[k]
                    if c == col and r == row:
                        return 0
                if col == 0 and row == 7:   # unused
                    return 1
                return 1
            return 1
        return 1

    def cru_write(self, bit, v):
        bit &= 0xFFF
        if bit < 0x400:
            b = bit & 0x1F
            if b == 0:
                if v and not self.cru_mode: self.clk_latch = self.clk_now()
                self.cru_mode = v
            elif self.cru_mode and 1 <= b <= 14:        # clock mode: load the clock register, restart
                m = 1 << (b - 1)
                self.clk_reg = (self.clk_reg | m) if v else (self.clk_reg & ~m)
                self.clk_start = self.cycles
            elif b == 2:
                self.int_mask9901 = v
            elif 18 <= b <= 20:
                sh = b - 18
                self.kbd_col = (self.kbd_col & ~(1 << sh)) | (v << sh)
            elif b == 21:
                self.alpha = v

    def clk_now(self):
        """The 9901 decrementer: from the clock register down to 0 and again, one step per 64 cycles."""
        if not self.clk_reg: return 0
        return self.clk_reg - ((self.cycles - self.clk_start) // 64) % (self.clk_reg + 1)

    # ------------------------------------------------------------ helpers
    def reg(self, n):
        return self.rw(self.wp + 2 * n)

    def setreg(self, n, v):
        self.ww(self.wp + 2 * n, v)

    def fetch(self):
        v = self.rw(self.pc)
        self.pc = (self.pc + 2) & 0xFFFF
        return v

    def ea(self, T, r, byte):
        if T == 0:
            return (self.wp + 2 * r) & 0xFFFF
        if T == 1:
            self.cycles += 4
            return self.rw(self.wp + 2 * r)
        if T == 2:
            self.cycles += 8
            d = self.fetch()
            if r:
                d = (d + self.rw(self.wp + 2 * r)) & 0xFFFF
            return d
        ra = self.wp + 2 * r
        v = self.rw(ra)
        self.ww(ra, v + (1 if byte else 2))
        self.cycles += 6 if byte else 8
        return v

    def cmp0w(self, v):
        st = self.st & ~(ST_LGT | ST_AGT | ST_EQ)
        if v == 0:
            st |= ST_EQ
        else:
            st |= ST_LGT
            if v < 0x8000:
                st |= ST_AGT
        self.st = st

    def cmp0b(self, v):
        st = self.st & ~(ST_LGT | ST_AGT | ST_EQ | ST_OP)
        if v == 0:
            st |= ST_EQ
        else:
            st |= ST_LGT
            if v < 0x80:
                st |= ST_AGT
        if parity(v):
            st |= ST_OP
        self.st = st

    def add_flags(self, a, b, r, byte):
        """a + b = r (unmasked)."""
        if byte:
            rm = r & 0xFF
            self.cmp0b(rm)
            if r & 0x100:
                self.st |= ST_C
            else:
                self.st &= ~ST_C
            if (~(a ^ b) & (a ^ rm)) & 0x80:
                self.st |= ST_OV
            else:
                self.st &= ~ST_OV
            return rm
        rm = r & 0xFFFF
        self.cmp0w(rm)
        if r & 0x10000:
            self.st |= ST_C
        else:
            self.st &= ~ST_C
        if (~(a ^ b) & (a ^ rm)) & 0x8000:
            self.st |= ST_OV
        else:
            self.st &= ~ST_OV
        return rm

    def sub_flags(self, d, s, byte):
        """d - s."""
        if byte:
            r = (d - s) & 0xFF
            self.cmp0b(r)
            self.st = (self.st | ST_C) if d >= s else (self.st & ~ST_C)
            if ((d ^ s) & (d ^ r)) & 0x80:
                self.st |= ST_OV
            else:
                self.st &= ~ST_OV
            return r
        r = (d - s) & 0xFFFF
        self.cmp0w(r)
        self.st = (self.st | ST_C) if d >= s else (self.st & ~ST_C)
        if ((d ^ s) & (d ^ r)) & 0x8000:
            self.st |= ST_OV
        else:
            self.st &= ~ST_OV
        return r

    def compare(self, a, b, byte):
        """C a,b : flags from a vs b (a is source)."""
        st = self.st & ~(ST_LGT | ST_AGT | ST_EQ | ST_OP)
        if a == b:
            st |= ST_EQ
        else:
            if a > b:
                st |= ST_LGT
            if byte:
                sa = a - 0x100 if a & 0x80 else a
                sb = b - 0x100 if b & 0x80 else b
            else:
                sa = a - 0x10000 if a & 0x8000 else a
                sb = b - 0x10000 if b & 0x8000 else b
            if sa > sb:
                st |= ST_AGT
        if byte and parity(a):
            st |= ST_OP
        self.st = st

    def jcond(self, op):
        st = self.st
        if op == 0x10: return True
        if op == 0x11: return not (st & ST_AGT) and not (st & ST_EQ)
        if op == 0x12: return (not (st & ST_LGT)) or bool(st & ST_EQ)
        if op == 0x13: return bool(st & ST_EQ)
        if op == 0x14: return bool(st & ST_LGT) or bool(st & ST_EQ)
        if op == 0x15: return bool(st & ST_AGT)
        if op == 0x16: return not (st & ST_EQ)
        if op == 0x17: return not (st & ST_C)
        if op == 0x18: return bool(st & ST_C)
        if op == 0x19: return not (st & ST_OV)
        if op == 0x1A: return not (st & ST_LGT) and not (st & ST_EQ)
        if op == 0x1B: return bool(st & ST_LGT) and not (st & ST_EQ)
        if op == 0x1C: return bool(st & ST_OP)
        return False

    def context_switch(self, vec):
        nwp = self.rw(vec)
        npc = self.rw(vec + 2)
        owp, opc, ost = self.wp, self.pc, self.st
        self.wp = nwp
        self.setreg(13, owp)
        self.setreg(14, opc)
        self.setreg(15, ost)
        self.pc = npc

    # ------------------------------------------------------------ VDP frame
    def vdp_frame(self):
        st = self.vstatus | 0x80
        # sprite coincidence / fifth sprite
        sat = (self.vreg[5] & 0x7F) << 7
        spg = (self.vreg[6] & 7) << 11
        size16 = bool(self.vreg[1] & 2)
        mag = bool(self.vreg[1] & 1)
        sz = (16 if size16 else 8) * (2 if mag else 1)
        lines = {}
        fifth = None
        sprites = []
        for i in range(32):
            y = self.vram[sat + 4 * i]
            if y == 0xD0:
                break
            x = self.vram[sat + 4 * i + 1]
            ec = self.vram[sat + 4 * i + 3] & 0x80
            if ec:
                x -= 32
            yy = (y + 1) if y < 0xE0 else (y + 1 - 256)
            sprites.append((i, x, yy))
        if not (st & 0x40):
            for i, x, yy in sprites:
                for ln in range(max(0, yy), min(192, yy + sz)):
                    n = lines.get(ln, 0) + 1
                    lines[ln] = n
                    if n == 5 and fifth is None:
                        fifth = i
            if fifth is not None:
                st = (st & 0xE0) | 0x40 | fifth
            else:
                st = (st & 0xE0) | (len(sprites) if len(sprites) < 32 else 31)
        if not (st & 0x20) and len(sprites) > 1:
            masks = []
            for i, x, yy in sprites:
                masks.append(self.sprite_mask(i, x, yy, size16, mag, spg, sat))
            for a in range(len(masks)):
                for b in range(a + 1, len(masks)):
                    if masks[a] and masks[b] and self.overlap(masks[a], masks[b]):
                        st |= 0x20
                        break
                if st & 0x20:
                    break
        self.vstatus = st

    def sprite_mask(self, i, x, yy, size16, mag, spg, sat):
        pat = self.vram[sat + 4 * i + 2]
        if size16:
            pat &= 0xFC
        rows = {}
        n = 16 if size16 else 8
        m = 2 if mag else 1
        base = spg + pat * 8
        for r in range(n):
            if size16:
                bits = (self.vram[base + r] << 8) | self.vram[base + 16 + r]
                w = 16
            else:
                bits = self.vram[base + r]
                w = 8
            if not bits:
                continue
            row = 0
            for c in range(w):
                if bits & (1 << (w - 1 - c)):
                    for k in range(m):
                        row |= 1 << (c * m + k)
            for k in range(m):
                ln = yy + r * m + k
                if 0 <= ln < 192:
                    rows[ln] = (row, x)
        return rows

    @staticmethod
    def overlap(ma, mb):
        for ln, (ra, xa) in ma.items():
            v = mb.get(ln)
            if v is None:
                continue
            rb_, xb = v
            # bit c => pixel x + c
            if xa <= xb:
                if (ra >> (xb - xa)) & rb_:
                    # make sure pixel is on screen
                    return True
            else:
                if (rb_ >> (xa - xb)) & ra:
                    return True
        return False

    # ------------------------------------------------------------ execute
    def run_until(self, cycle_target):
        while self.cycles < cycle_target:
            self.step()

    def run_frames(self, n):
        target = self.frame + n
        while self.frame < target:
            self.step()

    def step(self):
        if self.cycles >= self.next_frame:
            self.next_frame += FRAME_CYCLES
            self.frame += 1
            self.vdp_frame()
            if self.on_frame:
                self.on_frame(self)
        # interrupt?
        if (self.st & 0xF) >= 1 and (self.vstatus & 0x80) and (self.vreg[1] & 0x20) and self.int_mask9901 and not self.cru_mode:
            self.context_switch(0x0004)
            self.st &= ~0xF
            self.cycles += 22
        pc0 = self.pc
        c0 = self.cycles
        bank = self.bank if 0x6000 <= pc0 < 0x8000 else -1
        self.execute(self.fetch())
        if self.prof is not None:
            k = (bank, pc0)
            self.prof[k] = self.prof.get(k, 0) + (self.cycles - c0)
            if self.pcnt is not None:
                self.pcnt[k] = self.pcnt.get(k, 0) + 1
        self.icount += 1

    def execute(self, op):
        hi = op >> 12
        if hi >= 4:
            self.fmt1(op)
            return
        if hi >= 2:
            self.fmt3(op)
            return
        if hi == 1:
            self.jumps(op)
            return
        if op >= 0x0800:
            self.shift(op)
            return
        if op >= 0x0400:
            self.single(op)
            return
        if op >= 0x0200:
            self.imm(op)
            return
        self.cycles += 6       # illegal

    def fmt1(self, op):
        code = op >> 13
        byte = bool(op & 0x1000)
        Td = (op >> 10) & 3
        D = (op >> 6) & 0xF
        Ts = (op >> 4) & 3
        S = op & 0xF
        self.cycles += 14
        sa = self.ea(Ts, S, byte)
        if byte:
            sv = self.rb(sa)
        else:
            sv = self.rw(sa)
        da = self.ea(Td, D, byte)
        # code: 2 SZC, 3 S, 4 C, 5 A, 6 MOV, 7 SOC
        if code == 4:
            dv = self.rb(da) if byte else self.rw(da)
            self.compare(sv, dv, byte)
            return
        if code == 6:
            self.touch(da)
            if byte:
                self.cmp0b(sv)
                self.wb(da, sv)
            else:
                self.cmp0w(sv)
                self.ww(da, sv)
            return
        if byte:
            dv = self.rb(da)
        else:
            dv = self.rw(da)
        if code == 2:
            r = dv & ~sv
            r &= 0xFF if byte else 0xFFFF
            (self.cmp0b if byte else self.cmp0w)(r)
        elif code == 7:
            r = dv | sv
            (self.cmp0b if byte else self.cmp0w)(r)
        elif code == 5:
            r = self.add_flags(dv, sv, dv + sv, byte)
        else:  # 3: S
            r = self.sub_flags(dv, sv, byte)
        if byte:
            self.wb(da, r)
        else:
            self.ww(da, r)

    def fmt3(self, op):
        code = op >> 10
        D = (op >> 6) & 0xF
        Ts = (op >> 4) & 3
        S = op & 0xF
        if code == 0x08 or code == 0x09:      # COC, CZC
            self.cycles += 14
            sv = self.rw(self.ea(Ts, S, False))
            dv = self.reg(D)
            if code == 0x08:
                ok = (sv & dv) == sv
            else:
                ok = (sv & dv) == 0
            self.st = (self.st | ST_EQ) if ok else (self.st & ~ST_EQ)
            return
        if code == 0x0A:                      # XOR
            self.cycles += 14
            sv = self.rw(self.ea(Ts, S, False))
            r = self.reg(D) ^ sv
            self.cmp0w(r)
            self.setreg(D, r)
            return
        if code == 0x0B:                      # XOP
            self.cycles += 36
            sa = self.ea(Ts, S, False)
            self.context_switch(0x40 + 4 * D)
            self.setreg(11, sa)
            self.st |= ST_X
            return
        if code == 0x0C or code == 0x0D:      # LDCR / STCR
            cnt = D or 16
            byte = cnt <= 8
            sa = self.ea(Ts, S, byte)
            base = (self.reg(12) >> 1) & 0xFFF
            if code == 0x0C:
                self.cycles += 20 + 2 * cnt
                v = self.rb(sa) if byte else self.rw(sa)
                if byte:
                    self.cmp0b(v)
                else:
                    self.cmp0w(v)
                for i in range(cnt):
                    self.cru_write(base + i, (v >> i) & 1)
            else:
                self.cycles += 42 if cnt < 8 else (44 if cnt == 8 else (58 if cnt < 16 else 60))
                v = 0
                for i in range(cnt):
                    v |= self.cru_read(base + i) << i
                if byte:
                    self.cmp0b(v)
                    self.wb(sa, v)
                else:
                    self.cmp0w(v)
                    self.ww(sa, v)
            return
        if code == 0x0E:                      # MPY
            self.cycles += 52
            sv = self.rw(self.ea(Ts, S, False))
            r = sv * self.reg(D)
            self.setreg(D, r >> 16)
            self.setreg((D + 1) & 15, r & 0xFFFF)
            return
        if code == 0x0F:                      # DIV
            sv = self.rw(self.ea(Ts, S, False))
            hi = self.reg(D)
            if sv <= hi:
                self.cycles += 16
                self.st |= ST_OV
                return
            self.cycles += 108
            lo = self.reg((D + 1) & 15)
            n = (hi << 16) | lo
            self.setreg(D, n // sv)
            self.setreg((D + 1) & 15, n % sv)
            self.st &= ~ST_OV
            return

    def jumps(self, op):
        code = op >> 8
        disp = op & 0xFF
        if disp & 0x80:
            disp -= 0x100
        if code <= 0x1C:
            if self.jcond(code):
                self.cycles += 10
                self.pc = (self.pc + 2 * disp) & 0xFFFF
            else:
                self.cycles += 8
            return
        self.cycles += 12
        bit = ((self.reg(12) >> 1) + disp) & 0xFFF
        if code == 0x1D:
            self.cru_write(bit, 1)
        elif code == 0x1E:
            self.cru_write(bit, 0)
        else:
            v = self.cru_read(bit)
            self.st = (self.st | ST_EQ) if v else (self.st & ~ST_EQ)

    def shift(self, op):
        code = op >> 8
        cnt = (op >> 4) & 0xF
        W = op & 0xF
        if cnt == 0:
            cnt = self.reg(0) & 0xF or 16
            self.cycles += 8
        self.cycles += 12 + 2 * cnt
        v = self.reg(W)
        c = 0
        ov = 0
        if code == 0x08:      # SRA
            for _ in range(cnt):
                c = v & 1
                v = (v >> 1) | (v & 0x8000)
        elif code == 0x09:    # SRL
            for _ in range(cnt):
                c = v & 1
                v >>= 1
        elif code == 0x0A:    # SLA
            for _ in range(cnt):
                c = (v >> 15) & 1
                nv = (v << 1) & 0xFFFF
                if (nv ^ v) & 0x8000:
                    ov = 1
                v = nv
        else:                 # SRC
            for _ in range(cnt):
                c = v & 1
                v = (v >> 1) | (c << 15)
        self.cmp0w(v)
        self.st = (self.st | ST_C) if c else (self.st & ~ST_C)
        if code == 0x0A:
            self.st = (self.st | ST_OV) if ov else (self.st & ~ST_OV)
        self.setreg(W, v)

    def single(self, op):
        code = op >> 6
        Ts = (op >> 4) & 3
        S = op & 0xF
        if code == 0x10:      # BLWP
            self.cycles += 26
            a = self.ea(Ts, S, False)
            self.context_switch(a)
            return
        if code == 0x11:      # B
            self.cycles += 8
            self.pc = self.ea(Ts, S, False)
            return
        if code == 0x12:      # X
            self.cycles += 8
            a = self.ea(Ts, S, False)
            self.execute(self.rw(a))
            return
        if code == 0x1A:      # BL
            self.cycles += 12
            a = self.ea(Ts, S, False)
            self.setreg(11, self.pc)
            self.pc = a
            return
        a = self.ea(Ts, S, False)
        if code == 0x13:      # CLR
            self.cycles += 10
            self.touch(a)
            self.ww(a, 0)
            return
        if code == 0x1C:      # SETO
            self.cycles += 10
            self.touch(a)
            self.ww(a, 0xFFFF)
            return
        v = self.rw(a)
        if code == 0x14:      # NEG
            self.cycles += 12
            r = self.sub_flags(0, v, False)
            self.st = (self.st | ST_C) if v == 0 else (self.st & ~ST_C)
            self.ww(a, r)
        elif code == 0x15:    # INV
            self.cycles += 10
            r = (~v) & 0xFFFF
            self.cmp0w(r)
            self.ww(a, r)
        elif code == 0x16:    # INC
            self.cycles += 10
            self.ww(a, self.add_flags(v, 1, v + 1, False))
        elif code == 0x17:    # INCT
            self.cycles += 10
            self.ww(a, self.add_flags(v, 2, v + 2, False))
        elif code == 0x18:    # DEC
            self.cycles += 10
            self.ww(a, self.sub_flags(v, 1, False))
        elif code == 0x19:    # DECT
            self.cycles += 10
            self.ww(a, self.sub_flags(v, 2, False))
        elif code == 0x1B:    # SWPB
            self.cycles += 10
            self.ww(a, ((v << 8) | (v >> 8)) & 0xFFFF)
        elif code == 0x1D:    # ABS
            self.cmp0w(v)
            if v & 0x8000:
                self.cycles += 14
                self.st = (self.st | ST_OV) if v == 0x8000 else (self.st & ~ST_OV)
                self.ww(a, (-v) & 0xFFFF)
            else:
                self.cycles += 12
                self.st &= ~ST_OV
                self.ww(a, v)

    def imm(self, op):
        code = op >> 5
        r = op & 0xF
        if code == 0x10:      # LI
            self.cycles += 12
            v = self.fetch()
            self.cmp0w(v)
            self.setreg(r, v)
        elif code == 0x11:    # AI
            self.cycles += 14
            v = self.fetch()
            d = self.reg(r)
            self.setreg(r, self.add_flags(d, v, d + v, False))
        elif code == 0x12:    # ANDI
            self.cycles += 14
            v = self.fetch() & self.reg(r)
            self.cmp0w(v)
            self.setreg(r, v)
        elif code == 0x13:    # ORI
            self.cycles += 14
            v = self.fetch() | self.reg(r)
            self.cmp0w(v)
            self.setreg(r, v)
        elif code == 0x14:    # CI
            self.cycles += 14
            v = self.fetch()
            self.compare(self.reg(r), v, False)
        elif code == 0x15:    # STWP
            self.cycles += 8
            self.setreg(r, self.wp)
        elif code == 0x16:    # STST
            self.cycles += 8
            self.setreg(r, self.st)
        elif code == 0x17:    # LWPI
            self.cycles += 10
            self.wp = self.fetch()
        elif code == 0x18:    # LIMI
            self.cycles += 16
            self.st = (self.st & ~0xF) | (self.fetch() & 0xF)
        elif code == 0x1C:    # RTWP
            self.cycles += 14
            st = self.reg(15)
            pc = self.reg(14)
            wp = self.reg(13)
            self.st, self.pc, self.wp = st, pc, wp
        else:                 # IDLE, RSET, CKON, CKOF, LREX
            self.cycles += 12

    # ------------------------------------------------------------ video
    PALETTE = [(0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120), (84, 85, 237), (125, 118, 252),
               (212, 82, 77), (66, 235, 245), (252, 85, 84), (255, 121, 120), (212, 193, 84),
               (230, 206, 128), (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255)]

    def render(self):
        from PIL import Image
        img = Image.new('RGB', (256, 192))
        px = img.load()
        bd = self.vreg[7] & 0xF
        r0, r1 = self.vreg[0], self.vreg[1]
        nt = (self.vreg[2] & 0xF) << 10
        if not (r1 & 0x40):
            for y in range(192):
                for x in range(256):
                    px[x, y] = self.PALETTE[bd]
            return img
        bitmap = bool(r0 & 2)
        text = bool(r1 & 0x10)
        if text:
            pg = (self.vreg[4] & 7) << 11
            fg = self.vreg[7] >> 4
            for y in range(192):
                for x in range(256):
                    px[x, y] = self.PALETTE[bd]
            for row in range(24):
                for col in range(40):
                    ch = self.vram[nt + row * 40 + col]
                    for ln in range(8):
                        bits = self.vram[pg + ch * 8 + ln]
                        for b in range(6):
                            c = fg if bits & (0x80 >> b) else bd
                            px[8 + col * 6 + b, row * 8 + ln] = self.PALETTE[c or bd]
            return img
        for row in range(24):
            for col in range(32):
                ch = self.vram[nt + row * 32 + col]
                for ln in range(8):
                    if bitmap:
                        third = (row // 8) * 2048
                        pg = ((self.vreg[4] & 4) << 11) + third
                        ctb = ((self.vreg[3] & 0x80) << 6) + third
                        bits = self.vram[pg + ch * 8 + ln]
                        colr = self.vram[ctb + ch * 8 + ln]
                    else:
                        pg = (self.vreg[4] & 7) << 11
                        ctb = self.vreg[3] << 6
                        bits = self.vram[pg + ch * 8 + ln]
                        colr = self.vram[ctb + (ch >> 3)]
                    f, b_ = colr >> 4, colr & 0xF
                    for b in range(8):
                        c = f if bits & (0x80 >> b) else b_
                        if c == 0:
                            c = bd
                        px[col * 8 + b, row * 8 + ln] = self.PALETTE[c]
        # sprites
        sat = (self.vreg[5] & 0x7F) << 7
        spg = (self.vreg[6] & 7) << 11
        size16 = bool(r1 & 2)
        mag = bool(r1 & 1)
        n = 16 if size16 else 8
        m = 2 if mag else 1
        spr = []
        for i in range(32):
            y = self.vram[sat + 4 * i]
            if y == 0xD0:
                break
            spr.append(i)
        linecount = [0] * 192
        drawn = [[False] * 256 for _ in range(192)]
        for i in spr:
            y, x, pat, ec = self.vram[sat + 4 * i:sat + 4 * i + 4]
            colr = ec & 0xF
            if ec & 0x80:
                x -= 32
            yy = y + 1 if y < 0xE0 else y + 1 - 256
            if size16:
                pat &= 0xFC
            for r in range(n * m):
                ln = yy + r
                if not (0 <= ln < 192):
                    continue
                linecount[ln] += 1
                if linecount[ln] > 4:
                    continue
                sr = r // m
                if size16:
                    bits = (self.vram[spg + pat * 8 + sr] << 8) | self.vram[spg + pat * 8 + 16 + sr]
                    w = 16
                else:
                    bits = self.vram[spg + pat * 8 + sr]
                    w = 8
                for c in range(w * m):
                    if bits & (1 << (w - 1 - c // m)):
                        xx = x + c
                        if 0 <= xx < 256 and not drawn[ln][xx] and colr:
                            px[xx, ln] = self.PALETTE[colr]
                            drawn[ln][xx] = True
        return img
