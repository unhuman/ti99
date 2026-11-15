"""Whole-game lockstep: the TI cart against the reference Atari, one 6502 instruction at a time (A82TI99).

Both machines run the same input script and the same software random numbers.
Interrupts are driven by the harness: once a "frame" (a fixed number of
reference cycles) both take the display-list handler and then the
vertical-blank handler at the same instruction boundary, which is how the TI
runtime orders them.  After every instruction the 6502 program counter must
match and A, X, Y must agree; at every frame the mapped memory must agree.

  run(g, ref, ti, frames, script)  ->  number of frames completed, or raises Diverged
"""
import collections


class Diverged(Exception): pass


FRAME_CYCLES = 20000


class Lock:
    def __init__(self, g, ref, ti, info):
        self.g = g; self.ref = ref; self.ti = ti
        self.at = {}                            # (bank, TI address) -> 6502 instructions that start there
        for pc, (b, a) in sorted(info['insn'].items()):    # (CLC, SEC, CLD ... emit nothing and share the next one's)
            self.at.setdefault((b, a), []).append(int(pc, 16))
        self.pend = []
        self.natives = set(a for a in g.NATIVE if a < 0xC000)
        self.region = {a: e for a, (_, e) in getattr(g, 'REGION', {}).items()}     # loops the TI runs natively: start -> exit
        self.addrs = set(a for _, a in self.at)
        self.codeorg = info['codeorg']
        self.hist = collections.deque(maxlen=24)
        self.n = 0; self.frame = 0
        ti.vdp_frame = lambda: None            # no interrupts of its own: the harness raises them
        self.regions = self.mem_regions()

    def mem_regions(self):
        """(6502 start, end, TI start) runs compared every frame."""
        g = self.g; out = []
        skip = set(getattr(g, 'LOCK_SKIP', ()))
        def add(lo, hi):
            a = lo
            while a < hi:
                if a in skip: a += 1; continue
                b = a; t0 = g.ti_addr(a, 0)
                while b + 1 < hi and b + 1 not in skip and g.ti_addr(b + 1, 0) == t0 + (b + 1 - a): b += 1
                out.append((a, b + 1, t0)); a = b + 1
        add(0x80, 0x100)
        for lo, hi in g.LOCK_RANGES: add(lo, hi)
        for s, e, t in g.ISLANDS: out.append((s, e, t))
        return out

    def ti_byte(self, a):
        t = self.ti
        return t.scratch[a & 0xFF] if 0x8300 <= a < 0x8400 else t.exp[a]

    def ti_run(self):
        """Advance the TI to the start of the next 6502 instruction; return its 6502 address."""
        t = self.ti; at = self.at; addrs = self.addrs
        for _ in range(200000):
            t.step()
            pc = t.pc
            if pc in addrs and t.wp == 0x8300:
                k = (t.bank, pc)
                if k in at: return at[k]
        raise Diverged('the TI ran 200000 instructions without reaching a 6502 instruction (pc %04X bank %d wp %04X)' % (t.pc, t.bank, t.wp))

    def check_regs(self):
        r = self.ref; s = self.ti.scratch
        if s[2] != r.a or s[3] != 0 or s[5] != r.x or s[4] != 0 or s[7] != r.y or s[6] != 0:
            raise Diverged('registers: TI A %02X%02X X %02X%02X Y %02X%02X, 6502 A %02X X %02X Y %02X' % (
                s[2], s[3], s[4], s[5], s[6], s[7], r.a, r.x, r.y))

    def check_mem(self):
        m = self.ref.m; bad = []
        for lo, hi, t0 in self.regions:
            if 0x8300 <= t0 < 0x8400: tb = bytes(self.ti.scratch[(t0 & 0xFF):(t0 & 0xFF) + hi - lo])
            else: tb = bytes(self.ti.exp[t0:t0 + hi - lo])
            if tb != bytes(m[lo:hi]):
                for i in range(hi - lo):
                    if tb[i] != m[lo + i]: bad.append((lo + i, tb[i], m[lo + i]))
        if bad:
            raise Diverged('memory, %d bytes differ; first: %s' % (len(bad), ', '.join('%04X TI %02X / 6502 %02X' % b for b in bad[:8])))

    def step(self):
        r = self.ref
        pc0 = r.pc
        r.step()
        if pc0 in self.region:                  # a native loop: the 6502 runs it to its exit
            while r.pc != self.region[pc0]: r.step()
        while r.pc >= 0xC000: r.step()          # OS services done in Python
        while r.pc in self.natives:             # a routine the TI runs natively: let the 6502 run it to its return
            s0 = r.s; ret = ((r.m[0x101 + s0] | r.m[0x102 + s0] << 8) + 1) & 0xFFFF
            while not (r.pc == ret and r.s == ((s0 + 2) & 255)):
                r.step()
                while r.pc >= 0xC000: r.step()
        self.hist.append(pc0); self.n += 1

    def sync(self, what=''):
        want = self.ref.pc
        if self.pend and self.pend[0] == want: self.pend.pop(0)
        else:
            here = self.ti_run()
            if want not in here:
                raise Diverged('control flow%s: TI at %s, 6502 at %04X' % (what, '/'.join('%04X' % p for p in here), want))
            self.pend = here[here.index(want) + 1:]
        self.check_regs()

    def interrupt(self):
        """Both machines at the same boundary: display-list handler, then vertical blank."""
        r = self.ref; t = self.ti
        nmien = r.hw[0x40E]
        self.pend = []
        t.vdp.status |= 0x80                    # the TI takes its interrupt before its next instruction
        home = r.pc; s0 = r.s
        for bit, vec, vbi in ((0x80, 0x200, False), (0x40, 0x222, True)):
            if not nmien & bit: continue
            r.nmi(r.w16(vec), vbi)
            while r.pc >= 0xC000: r.step()
            if r.pc == home and r.s == s0: continue        # handler was an OS stub
            self.sync(' entering a handler')
            while not (r.pc == home and r.s == s0):
                self.step()
                if r.pc == home and r.s == s0: break
                self.sync(' in a handler')
        self.sync(' after the interrupt')

    def run(self, frames, script):
        """script: {frame: [(kind, value)]}  kind 'key' (Atari key name, TI key name), 'rel', 'stick', 'trig'."""
        r = self.ref
        nxt = r.cyc + FRAME_CYCLES
        try:
            while self.frame < frames:
                self.step(); self.sync()
                if r.cyc >= nxt:
                    nxt += FRAME_CYCLES; self.frame += 1
                    if self.frame % 20 == 0: print("  frame %d, %d instructions, 6502 at %04X" % (self.frame, self.n, r.pc), flush=True)
                    self.check_mem()
                    for ev in script.get(self.frame, ()): self.apply(ev)
                    self.interrupt()
        except Diverged as e:
            raise Diverged('frame %d, instruction %d: %s\n  last 6502 instructions: %s' % (
                self.frame, self.n, e, ' '.join('%04X' % p for p in self.hist)))
        return self.frame

    def apply(self, ev):
        r = self.ref; t = self.ti; kind = ev[0]
        if kind == 'key': r.press(ev[1]); t.pressed.add(ev[2])
        elif kind == 'rel': r.release(); t.pressed.discard(ev[1])
        elif kind == 'stick':                   # Atari PORTA nibble, 0 = pushed: bit 0 up, 1 down, 2 left, 3 right
            r.stick = ev[1]
            for bit, name in ((1, 'J1UP'), (2, 'J1DOWN'), (4, 'J1LEFT'), (8, 'J1RIGHT')):
                (t.pressed.discard if ev[1] & bit else t.pressed.add)(name)
        elif kind == 'trig':
            r.trig = ev[1]; (t.pressed.discard if ev[1] else t.pressed.add)('J1FIRE')
