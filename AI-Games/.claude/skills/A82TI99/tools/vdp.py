"""TMS9918A model shared by the Z80 (ColecoVision) and TMS9900 (TI) emulators.

Only what a game can observe through the ports is modelled exactly:
VRAM, registers, the address latch, the read-ahead buffer and the status
register (frame flag, fifth-sprite flag and number, coincidence flag),
evaluated once per frame at vblank.  render() paints a 256x192 RGB image
(graphics I/II, sprites) for screenshots.
"""

PALETTE = [
    (0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
    (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
    (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
    (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255),
]


class VDP:
    def __init__(self):
        self.vram = bytearray(16384)
        self.reg = [0] * 8
        self.addr = 0
        self.latch = None
        self.status = 0
        self.readbuf = 0
        self.log = None          # optional list of ('reg', r, v)

    # ---------------------------------------------------------- ports
    def write_data(self, v):
        self.vram[self.addr] = v
        self.readbuf = v
        self.addr = (self.addr + 1) & 0x3FFF
        self.latch = None

    def read_data(self):
        v = self.readbuf
        self.readbuf = self.vram[self.addr]
        self.addr = (self.addr + 1) & 0x3FFF
        self.latch = None
        return v

    def write_ctrl(self, v):
        # MAME tms9928a: the first byte lands in the low address byte at once
        if self.latch is None:
            self.latch = v
            self.addr = (self.addr & 0x3F00) | v
            return
        lo = self.latch
        self.latch = None
        self.addr = ((v & 0x3F) << 8) | lo
        if v & 0x80:
            r = v & 7
            self.reg[r] = lo
            if self.log is not None:
                self.log.append(('reg', r, lo))
        elif not (v & 0x40):
            self.readbuf = self.vram[self.addr]
            self.addr = (self.addr + 1) & 0x3FFF

    def read_status(self):
        v = self.status
        self.status &= 0x1F
        self.latch = None
        return v

    def int_line(self):
        return bool((self.status & 0x80) and (self.reg[1] & 0x20))

    # ---------------------------------------------------------- frame
    def vblank(self):
        """End of the active display: set F, evaluate 5S/C as the frame drew."""
        five, coinc, num = self.sprite_scan()
        st = self.status
        if not (st & 0x40):
            st = (st & 0xE0) | (num & 0x1F)
            if five:
                st |= 0x40
        if coinc:
            st |= 0x20
        self.status = st | 0x80

    def sprite_scan(self):
        """Return (fifth_sprite_seen, coincidence, sprite number)."""
        if not (self.reg[1] & 0x40):
            return False, False, 31
        sat = (self.reg[5] & 0x7F) << 7
        spg = (self.reg[6] & 7) << 11
        size16 = bool(self.reg[1] & 2)
        mag = bool(self.reg[1] & 1)
        h = (16 if size16 else 8) * (2 if mag else 1)
        sprites = []
        last = 31
        for i in range(32):
            y = self.vram[sat + i * 4]
            if y == 0xD0:
                last = i
                break
            sprites.append(i)
        else:
            last = 31
        vr = self.vram
        lines = {}
        fifth = None
        coinc = False
        rows = []
        for i in sprites:
            y = vr[sat + i * 4]
            y = (y + 1) if y < 0xE0 else (y - 255)
            rows.append((i, y))
        for line in range(192):
            on = [i for (i, y) in rows if y <= line < y + h]
            if len(on) > 4:
                if fifth is None:
                    fifth = on[4]
                on = on[:4]
            if len(on) > 1 and not coinc:
                coinc = self._coinc_line(on, line, sat, spg, size16, mag)
        if fifth is not None:
            return True, coinc, fifth
        return False, coinc, last

    def _coinc_line(self, on, line, sat, spg, size16, mag):
        vr = self.vram
        masks = []
        for i in on:
            y = vr[sat + i * 4]
            y = (y + 1) if y < 0xE0 else (y - 255)
            x = vr[sat + i * 4 + 1]
            name = vr[sat + i * 4 + 2]
            ec = vr[sat + i * 4 + 3] & 0x80
            if ec:
                x -= 32
            row = line - y
            if mag:
                row >>= 1
            if size16:
                name &= 0xFC
                b0 = vr[spg + name * 8 + row]
                b1 = vr[spg + name * 8 + 16 + row]
                bits = (b0 << 8) | b1
                w = 16
            else:
                bits = vr[spg + name * 8 + row]
                w = 8
            m = 0
            for k in range(w):
                if bits & (1 << (w - 1 - k)):
                    if mag:
                        for q in (2 * k, 2 * k + 1):
                            px = x + q
                            if 0 <= px < 256:
                                m |= 1 << px
                    else:
                        px = x + k
                        if 0 <= px < 256:
                            m |= 1 << px
            masks.append(m)
        acc = 0
        for m in masks:
            if acc & m:
                return True
            acc |= m
        return False

    # ---------------------------------------------------------- render
    def render(self):
        """256x192 list of palette indices (row-major)."""
        r = self.reg
        out = bytearray(256 * 192)
        backdrop = r[7] & 15
        if not (r[1] & 0x40):
            for i in range(len(out)):
                out[i] = backdrop
            return out
        m1 = bool(r[1] & 0x10)
        m2 = bool(r[1] & 0x08)
        m3 = bool(r[0] & 0x02)
        vr = self.vram
        nt = (r[2] & 0x0F) << 10
        if m3:
            ct = (r[3] & 0x80) << 6
            pg = (r[4] & 0x04) << 11
            cmask = ((r[3] & 0x7F) << 3) | 7
            pmask = ((r[4] & 3) << 8) | 0xFF
        else:
            ct = r[3] << 6
            pg = (r[4] & 7) << 11
        for row in range(24):
            for col in range(32):
                ch = vr[nt + row * 32 + col]
                for line in range(8):
                    if m1:
                        continue
                    if m3:
                        third = (row // 8) << 8
                        idx = (ch + third) & pmask
                        pat = vr[pg + idx * 8 + line]
                        cidx = (ch + third) & cmask
                        col_b = vr[ct + cidx * 8 + line]
                    else:
                        pat = vr[pg + ch * 8 + line]
                        col_b = vr[ct + (ch >> 3)]
                    fg = col_b >> 4
                    bg = col_b & 15
                    if fg == 0:
                        fg = backdrop
                    if bg == 0:
                        bg = backdrop
                    base = (row * 8 + line) * 256 + col * 8
                    for k in range(8):
                        out[base + k] = fg if pat & (0x80 >> k) else bg
        # sprites
        sat = (r[5] & 0x7F) << 7
        spg = (r[6] & 7) << 11
        size16 = bool(r[1] & 2)
        mag = bool(r[1] & 1)
        h = (16 if size16 else 8) * (2 if mag else 1)
        sprites = []
        for i in range(32):
            y = vr[sat + i * 4]
            if y == 0xD0:
                break
            sprites.append(i)
        drawn = [[] for _ in range(192)]
        for i in sprites:
            y = vr[sat + i * 4]
            y = (y + 1) if y < 0xE0 else (y - 255)
            for line in range(max(0, y), min(192, y + h)):
                drawn[line].append(i)
        for line in range(192):
            on = drawn[line][:4]
            for i in reversed(on):
                y = vr[sat + i * 4]
                y = (y + 1) if y < 0xE0 else (y - 255)
                x = vr[sat + i * 4 + 1]
                name = vr[sat + i * 4 + 2]
                cb = vr[sat + i * 4 + 3]
                if cb & 0x80:
                    x -= 32
                c = cb & 15
                if c == 0:
                    continue
                row = line - y
                if mag:
                    row >>= 1
                if size16:
                    name &= 0xFC
                    bits = (vr[spg + name * 8 + row] << 8) | vr[spg + name * 8 + 16 + row]
                    w = 16
                else:
                    bits = vr[spg + name * 8 + row]
                    w = 8
                for k in range(w):
                    if bits & (1 << (w - 1 - k)):
                        for q in ((2 * k, 2 * k + 1) if mag else (k,)):
                            px = x + q
                            if 0 <= px < 256:
                                out[line * 256 + px] = c
        return out

    def png(self, path, scale=2):
        from PIL import Image
        pix = self.render()
        im = Image.new('RGB', (256, 192))
        im.putdata([PALETTE[p] for p in pix])
        if scale != 1:
            im = im.resize((256 * scale, 192 * scale), Image.NEAREST)
        im.save(path)
