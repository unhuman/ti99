"""Headless Atari 400/800 reference machine for the A82TI99 pipeline.

Not a full emulator: it models what a translated game has to reproduce on the
TI.  The 6502 is exact for documented opcodes; ANTIC is modelled per scan line
(display list, DMA cycle stealing, VCOUNT, WSYNC, DLI and VBI); GTIA, POKEY and
PIA are register files with the inputs a game reads.  The OS ROM is NOT
needed: the OS services a game reaches (the VBI stages, XITVBV, warm start,
SIO) are done in Python at trap addresses.  Anything else in ROM stops the run
with the address, which is how you find the next service to add.
"""
import zlib, struct
from m6502 import CPU, Halt

MODE_LINES = {2: 8, 3: 10, 4: 8, 5: 16, 6: 8, 7: 16, 8: 8, 9: 4, 10: 4, 11: 2, 12: 1, 13: 2, 14: 1, 15: 1}
MODE_BYTES = {2: 40, 3: 40, 4: 40, 5: 40, 6: 20, 7: 20, 8: 10, 9: 10, 10: 20, 11: 20, 12: 20, 13: 40, 14: 40, 15: 40}
KEY = dict(A=0x3F, B=0x15, C=0x12, D=0x3A, E=0x2A, F=0x38, G=0x3D, H=0x39, I=0x0D, J=0x01, K=0x05, L=0x00,
           M=0x25, N=0x23, O=0x08, P=0x0A, Q=0x2F, R=0x28, S=0x3E, T=0x2D, U=0x0B, V=0x10, W=0x2E, X=0x16,
           Y=0x2B, Z=0x17, SPACE=0x21, RETURN=0x0C, ESC=0x1C)
KEY.update({'0': 0x32, '1': 0x1F, '2': 0x1E, '3': 0x1A, '4': 0x18, '5': 0x1D, '6': 0x1B, '7': 0x33, '8': 0x35, '9': 0x30})
# XL OS addresses a frozen snapshot may still hold in its vectors, mapped to the published entries
ALIAS = {0xC0E2: 0xE45F, 0xC28A: 0xE462, 0xC0CE: 0xFFFE, 0xC0CD: 0xFFFE}


def poly17_bytes():
    """POKEY's 17-bit polynomial counter as the byte RANDOM returns at each cycle."""
    reg = 0x1FFFF; out = bytearray(131071)
    for i in range(131071):
        out[i] = (reg >> 9) & 255 ^ 255
        reg = ((((reg >> 5) ^ reg) & 1) << 16) | (reg >> 1)
    return out


class Atari(CPU):
    LINES = 262; VBI_LINE = 248

    def __init__(self, image, rng='poly', seed=1):
        CPU.__init__(self)
        m = self.m
        m[:len(image)] = image
        for a in list(range(0xC000, 0xD000)) + list(range(0xD800, 0x10000)): m[a] = 0x02
        self.hw = bytearray(0x800)
        self.line = 0; self.frame = 0; self.line_end = 0
        self.kbcode = 0xFF; self.keydown = False; self.consol = 7; self.stick = 0x0F; self.trig = 1
        self.rng = rng; self.poly = poly17_bytes() if rng == 'poly' else None; self.lfsr = seed or 1
        self.scan = {}; self.linecol = {}; self.capture = False
        self.snd = []           # (frame, line, register, value) for POKEY and the console speaker
        self.sio = []
        self.nrand = 0

    # ---- hardware window -------------------------------------------------
    def hwr(self, a):
        if a < 0xD100:
            r = a & 0x1F
            if r == 0x10: return self.trig
            if r in (0x11, 0x12, 0x13): return 1
            if r == 0x1F: return self.consol
            return 0x0F if r >= 0x14 else 0
        if 0xD200 <= a < 0xD300:
            r = a & 0x0F
            if r == 0x0A:
                self.nrand += 1
                if self.rng == 'poly': return self.poly[self.cyc % 131071]
                return self.soft_random()
            if r == 0x09: return self.kbcode
            if r == 0x0F: return 0xFB if self.keydown else 0xFF
            if r == 0x0E: return 0xFF
            return 228 if r < 8 else 0xFF
        if 0xD300 <= a < 0xD400:
            r = a & 3
            return (0xF0 | self.stick) if r == 0 else 0xFF if r == 1 else self.hw[a - 0xD000]
        if 0xD400 <= a < 0xD500:
            r = a & 0x0F
            if r == 0x0B: return self.line >> 1
            if r == 0x0F: return 0x5F if self.line >= self.VBI_LINE else 0x1F
            return 0xFF
        return 0xFF

    def soft_random(self):
        """The software generator a TI port uses in place of POKEY RANDOM (x = x * 25173 + 13849, high byte; RDRAND in runtime65.a99)."""
        r = self.lfsr = (self.lfsr * 25173 + 13849) & 0xFFFF
        return r >> 8

    def hww(self, a, v):
        self.hw[a - 0xD000] = v
        if 0xD400 <= a < 0xD500:
            if a & 0x0F == 0x0A and self.cyc < self.line_end: self.cyc = self.line_end
        elif 0xD200 <= a < 0xD300:
            if a & 0x0F < 9: self.snd.append((self.frame, self.line, a & 0x0F, v))
        elif a < 0xD100 and a & 0x1F == 0x1F:
            self.snd.append((self.frame, self.line, 0x1F, v & 8))

    # ---- OS services -------------------------------------------------------
    def w16(self, a): return self.m[a] | self.m[a + 1] << 8

    def trap(self, pc):
        m = self.m; pc = ALIAS.get(pc, pc)
        if pc == 0xE45F:                               # SYSVBV: OS immediate VBI stage
            m[0x14] = (m[0x14] + 1) & 255
            if m[0x14] == 0:
                m[0x13] = (m[0x13] + 1) & 255
                if m[0x13] == 0: m[0x12] = (m[0x12] + 1) & 255
            if m[0x42] or m[0x104 + self.s] & 4:       # CRITIC, or the interrupted code had I set
                return self.trap(0xE462)
            hw = self.hw
            hw[0x402] = m[0x230]; hw[0x403] = m[0x231]; hw[0x400] = m[0x22F]; hw[0x1B] = m[0x26F]
            hw[0x12:0x1B] = m[0x2C0:0x2C9]; hw[0x409] = m[0x2F4]; hw[0x401] = m[0x2F3]
            m[0x278] = self.stick; m[0x279] = 0x0F; m[0x284] = self.trig; m[0x285] = 1
            return self.w16(0x224)                     # deferred stage vector
        if pc == 0xE462:                               # XITVBV
            self.y = self.pop(); self.x = self.pop(); self.a = self.pop()
            self.setp(self.pop()); lo = self.pop(); return lo | self.pop() << 8
        if pc == 0xFFFE:                               # bare RTI (default DLI/break vectors)
            self.setp(self.pop()); lo = self.pop(); return lo | self.pop() << 8
        if pc == 0xE474:                               # WARMSV
            self.hw[0x40E] = 0x40; self.i = 0; self.d = 0; self.s = 0xFF
            m[0x2FC] = 0xFF; m[0x42] = 0; m[0x22F] = 0x22
            self.push(0xFF); self.push(0xEF)           # DOSINI returns to $FFF0
            return self.w16(0x0C)
        if pc == 0xFFF0: return self.w16(0x0A)         # then the OS jumps through DOSVEC
        if pc == 0xE459:                               # SIOV: record the request, report success
            self.sio.append(bytes(m[0x300:0x30C])); m[0x303] = 1; self.y = self.zr = self.ng = 1
            lo = self.pop(); return ((lo | self.pop() << 8) + 1) & 0xffff
        raise Halt('unhandled ROM entry/opcode %02X at %04X (frame %d line %d)' % (m[pc], pc, self.frame, self.line))

    def nmi(self, vector, vbi):
        self.push(self.pc >> 8); self.push(self.pc & 255); self.push(self.getp() & 0xEF)
        self.i = 1; self.cyc += 7
        if vbi:                                        # the OS NMI handler saves A, X, Y first
            self.push(self.a); self.push(self.x); self.push(self.y); self.cyc += 20
        self.pc = vector

    # ---- keyboard: what the OS keyboard IRQ would do -------------------------
    def press(self, name):
        self.kbcode = KEY[name] if isinstance(name, str) else name
        self.keydown = True; self.m[0x2FC] = self.kbcode

    def release(self): self.keydown = False

    # ---- video ---------------------------------------------------------------
    def parse_dl(self):
        """Map scan line -> (mode, row within mode line, memory address, DLI on this line)."""
        m = self.m; hw = self.hw; scan = {}
        if not hw[0x400] & 0x20: return scan
        pc = hw[0x402] | hw[0x403] << 8; line = 8; mem = 0; guard = 0
        while line < 248 and guard < 300:
            guard += 1
            op = m[pc]; pc = (pc & 0xFC00) | ((pc + 1) & 0x3FF); mode = op & 15
            if mode == 0:
                n = ((op >> 4) & 7) + 1
                if op & 0x80: scan[line + n - 1] = (0, 0, 0, True)
                line += n
            elif mode == 1:
                tgt = m[pc] | m[(pc & 0xFC00) | ((pc + 1) & 0x3FF)] << 8
                if op & 0x40: break
                pc = tgt; line += 1
            else:
                if op & 0x40:
                    mem = m[pc] | m[(pc & 0xFC00) | ((pc + 1) & 0x3FF)] << 8
                    pc = (pc & 0xFC00) | ((pc + 2) & 0x3FF)
                n = MODE_LINES[mode]
                for r in range(n):
                    scan[line + r] = (mode, r, mem, bool(op & 0x80) and r == n - 1)
                mem = (mem & 0xF000) | ((mem + MODE_BYTES[mode]) & 0xFFF); line += n
        return scan

    def run_frame(self):
        hw = self.hw; scan = self.scan
        for line in range(self.LINES):
            self.line = line
            if line == 8: scan = self.scan = self.parse_dl()
            info = scan.get(line)
            steal = 9 if not info or not info[0] else (49 if info[1] or info[0] >= 8 else 49 + MODE_BYTES[info[0]])
            self.line_end = max(self.cyc, self.line_end) + 114 - steal
            self.run(self.line_end)
            if self.capture: self.linecol[line] = bytes(hw[0x16:0x1B])
            if info and info[3] and hw[0x40E] & 0x80: self.nmi(self.w16(0x200), False)
            if line == self.VBI_LINE and hw[0x40E] & 0x40: self.nmi(self.w16(0x222), True)
        self.frame += 1

    def frames(self, n):
        for _ in range(n): self.run_frame()

    def picture(self):
        """Render the last frame as (width, height, rows of RGB bytes).  Needs capture=True."""
        m = self.m; rows = []
        chb = self.hw[0x409] << 8
        for line in range(8, 248):
            info = self.scan.get(line); col = self.linecol.get(line, bytes(5))
            pf0, pf1, pf2, pf3, bak = (rgb(c) for c in col)
            row = bytearray()
            if not info or not info[0]:
                row = bytearray(bak * 320)
            else:
                mode, r, mem, _ = info
                if mode == 15:
                    fg = rgb((col[2] & 0xF0) | (col[1] & 0x0F))
                    for b in m[mem:mem + 40]:
                        for k in range(7, -1, -1): row += fg if b >> k & 1 else pf2
                elif mode in (14, 13):
                    pal = (bak, pf0, pf1, pf2)
                    for b in m[mem:mem + 40]:
                        for k in (6, 4, 2, 0): row += pal[b >> k & 3] * 2
                elif mode == 2:
                    fg = rgb((col[2] & 0xF0) | (col[1] & 0x0F))
                    for ch in m[mem:mem + 40]:
                        g = m[chb + (ch & 127) * 8 + r] if chb < 0xC000 else (0x7E if ch & 127 else 0)
                        if ch & 128: g ^= 255
                        for k in range(7, -1, -1): row += fg if g >> k & 1 else pf2
                else:
                    row = bytearray(pf0 * 320)
            rows.append(bytes(row[:960]).ljust(960, b'\0'))
        return 320, len(rows), rows


def rgb(c):
    import math
    lum = (c & 15) / 15.0; hue = c >> 4
    y = 0.08 + 0.92 * lum
    if hue == 0: i = q = 0.0
    else:
        ang = math.radians((hue - 1) * 25.7 + 100); i = 0.20 * math.cos(ang); q = 0.20 * math.sin(ang)
    r = y + 0.956 * i + 0.621 * q; g = y - 0.272 * i - 0.647 * q; b = y - 1.106 * i + 1.703 * q
    return bytes(max(0, min(255, int(v * 255))) for v in (r, g, b))


def write_png(path, w, h, rows, scale=2):
    raw = bytearray()
    for row in rows:
        line = b''.join(row[i:i + 3] * scale for i in range(0, w * 3, 3))
        raw += (b'\0' + line) * scale

    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w * scale, h * scale, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(bytes(raw), 6)) + chunk(b'IEND', b''))
