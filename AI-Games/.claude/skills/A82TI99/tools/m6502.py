"""6502 reference CPU for the A82TI99 pipeline: documented opcodes, cycle counts, disassembler.

The interpreter is generated: one small Python function per opcode, so the
reference machine runs fast enough for lockstep and benchmark work.  Memory
outside the hardware window ($D000-$D7FF) is a plain bytearray; the window goes
through hwr()/hww(), which the machine model overrides.  An undefined opcode
calls trap(pc): the Atari model fills the OS ROM area with $02 and uses the
trap for its high-level OS services.
"""
import struct

T = """00 BRK imp|01 ORA izx|05 ORA zp|06 ASL zp|08 PHP imp|09 ORA imm|0A ASL acc|0D ORA abs|0E ASL abs
10 BPL rel|11 ORA izy|15 ORA zpx|16 ASL zpx|18 CLC imp|19 ORA aby|1D ORA abx|1E ASL abx
20 JSR abs|21 AND izx|24 BIT zp|25 AND zp|26 ROL zp|28 PLP imp|29 AND imm|2A ROL acc|2C BIT abs|2D AND abs|2E ROL abs
30 BMI rel|31 AND izy|35 AND zpx|36 ROL zpx|38 SEC imp|39 AND aby|3D AND abx|3E ROL abx
40 RTI imp|41 EOR izx|45 EOR zp|46 LSR zp|48 PHA imp|49 EOR imm|4A LSR acc|4C JMP abs|4D EOR abs|4E LSR abs
50 BVC rel|51 EOR izy|55 EOR zpx|56 LSR zpx|58 CLI imp|59 EOR aby|5D EOR abx|5E LSR abx
60 RTS imp|61 ADC izx|65 ADC zp|66 ROR zp|68 PLA imp|69 ADC imm|6A ROR acc|6C JMP ind|6D ADC abs|6E ROR abs
70 BVS rel|71 ADC izy|75 ADC zpx|76 ROR zpx|78 SEI imp|79 ADC aby|7D ADC abx|7E ROR abx
81 STA izx|84 STY zp|85 STA zp|86 STX zp|88 DEY imp|8A TXA imp|8C STY abs|8D STA abs|8E STX abs
90 BCC rel|91 STA izy|94 STY zpx|95 STA zpx|96 STX zpy|98 TYA imp|99 STA aby|9A TXS imp|9D STA abx
A0 LDY imm|A1 LDA izx|A2 LDX imm|A4 LDY zp|A5 LDA zp|A6 LDX zp|A8 TAY imp|A9 LDA imm|AA TAX imp|AC LDY abs|AD LDA abs|AE LDX abs
B0 BCS rel|B1 LDA izy|B4 LDY zpx|B5 LDA zpx|B6 LDX zpy|B8 CLV imp|B9 LDA aby|BA TSX imp|BC LDY abx|BD LDA abx|BE LDX aby
C0 CPY imm|C1 CMP izx|C4 CPY zp|C5 CMP zp|C6 DEC zp|C8 INY imp|C9 CMP imm|CA DEX imp|CC CPY abs|CD CMP abs|CE DEC abs
D0 BNE rel|D1 CMP izy|D5 CMP zpx|D6 DEC zpx|D8 CLD imp|D9 CMP aby|DD CMP abx|DE DEC abx
E0 CPX imm|E1 SBC izx|E4 CPX zp|E5 SBC zp|E6 INC zp|E8 INX imp|E9 SBC imm|EA NOP imp|EC CPX abs|ED SBC abs|EE INC abs
F0 BEQ rel|F1 SBC izy|F5 SBC zpx|F6 INC zpx|F8 SED imp|F9 SBC aby|FD SBC abx|FE INC abx"""
OPS = {}
for _e in T.replace('\n', '|').split('|'):
    _o, _m, _a = _e.split(); OPS[int(_o, 16)] = (_m, _a)
LEN = dict(imp=1, acc=1, imm=2, zp=2, zpx=2, zpy=2, izx=2, izy=2, rel=2, abs=3, abx=3, aby=3, ind=3)
FMT = dict(imp='', acc='A', imm='#$%02X', zp='$%02X', zpx='$%02X,X', zpy='$%02X,Y', izx='($%02X,X)',
           izy='($%02X),Y', abs='$%04X', abx='$%04X,X', aby='$%04X,Y', ind='($%04X)')
STORES = ('STA', 'STX', 'STY')
RMW = ('ASL', 'LSR', 'ROL', 'ROR', 'INC', 'DEC')
BRANCH = dict(BPL='not c.ng & 128', BMI='c.ng & 128', BVC='not c.v', BVS='c.v', BCC='not c.c', BCS='c.c',
              BNE='c.zr', BEQ='not c.zr')


def cycles(mn, am):
    """Base cycle count (page-cross and branch-taken penalties are added at run time)."""
    if mn in BRANCH: return 2
    if mn == 'JSR': return 6
    if mn == 'JMP': return 3 if am == 'abs' else 5
    if mn in ('RTS', 'RTI'): return 6
    if mn == 'BRK': return 7
    if mn in ('PHA', 'PHP'): return 3
    if mn in ('PLA', 'PLP'): return 4
    if am in ('imp', 'acc'): return 2
    if mn in RMW: return dict(zp=5, zpx=6, abs=6, abx=7)[am]
    if mn in STORES: return dict(zp=3, zpx=4, zpy=4, abs=4, abx=5, aby=5, izx=6, izy=6)[am]
    return dict(imm=2, zp=3, zpx=4, zpy=4, abs=4, abx=4, aby=4, izx=6, izy=5)[am]


def disasm(mem, pc):
    op = mem[pc]
    if op not in OPS: return 1, '.byte $%02X' % op
    m, a = OPS[op]; n = LEN[a]
    if a == 'rel':
        d = mem[(pc + 1) & 0xffff]; d -= 256 if d > 127 else 0
        return 2, '%s $%04X' % (m, (pc + 2 + d) & 0xffff)
    v = mem[(pc + 1) & 0xffff] | (mem[(pc + 2) & 0xffff] << 8 if n == 3 else 0)
    return n, (m + ' ' + (FMT[a] % v if '%' in FMT[a] else FMT[a])).strip()


def xex_segments(x):
    """Yield (load address, bytes) for each segment of an Atari DOS binary file."""
    i = 0
    while i < len(x):
        if x[i:i + 2] == b'\xff\xff': i += 2
        s, e = struct.unpack('<HH', x[i:i + 4]); i += 4
        yield s, x[i:i + e - s + 1]; i += e - s + 1


class Halt(Exception): pass


_RD = '(m[ea] if ea < 0xD000 or ea >= 0xD800 else c.hwr(ea))'
_PUSH = 'm[256 + c.s] = %s; c.s = (c.s - 1) & 255'
_POP = 'c.s = (c.s + 1) & 255; %s = m[256 + c.s]'


def _gen(op, mn, am):
    L = ['x[pc] += 1', 'c.cyc += %d' % cycles(mn, am)]
    n = LEN[am]; pen = mn not in STORES and mn not in RMW
    if am == 'imm': L.append('v = m[pc + 1]')
    elif am == 'acc': L.append('v = c.a')
    elif am == 'zp': L.append('ea = m[pc + 1]')
    elif am == 'zpx': L.append('ea = (m[pc + 1] + c.x) & 255')
    elif am == 'zpy': L.append('ea = (m[pc + 1] + c.y) & 255')
    elif am in ('abs', 'ind'): L.append('ea = m[pc + 1] | m[pc + 2] << 8')
    elif am in ('abx', 'aby'):
        r = am[2]
        L.append('ea = (m[pc + 1] | m[pc + 2] << 8) + c.%s' % r)
        if pen: L.append('if (ea ^ (ea - c.%s)) & 256: c.cyc += 1' % r)
        L.append('ea &= 0xffff')
    elif am == 'izx': L += ['z = (m[pc + 1] + c.x) & 255', 'ea = m[z] | m[(z + 1) & 255] << 8']
    elif am == 'izy':
        L += ['z = m[pc + 1]', 'ea = (m[z] | m[(z + 1) & 255] << 8) + c.y']
        if pen: L.append('if (ea ^ (ea - c.y)) & 256: c.cyc += 1')
        L.append('ea &= 0xffff')
    zp = am in ('zp', 'zpx', 'zpy')
    mem = am not in ('imp', 'acc', 'imm', 'rel', 'ind')
    reads = mem and mn not in STORES and mn not in ('JMP', 'JSR')
    if reads: L += ['r[ea] = 1', 'v = m[ea]' if zp else 'v = ' + _RD]

    def put(e):
        if am == 'acc': return ['c.a = ' + e]
        if zp: return ['m[ea] = ' + e, 'w[ea] = 1']
        return ['if ea < 0xD000 or ea >= 0xD800:', ' m[ea] = ' + e, ' w[ea] = 1', 'else: c.hww(ea, %s)' % e]
    nxt = 'return pc + %d' % n
    if mn in BRANCH:
        L += ['if %s:' % BRANCH[mn], ' d = m[pc + 1]; c.cyc += 1', ' return (pc + 2 + (d - 256 if d > 127 else d)) & 0xffff']
    elif mn == 'LDA': L.append('c.a = c.zr = c.ng = v')
    elif mn == 'LDX': L.append('c.x = c.zr = c.ng = v')
    elif mn == 'LDY': L.append('c.y = c.zr = c.ng = v')
    elif mn == 'STA': L += put('c.a')
    elif mn == 'STX': L += put('c.x')
    elif mn == 'STY': L += put('c.y')
    elif mn == 'ADC': L.append('c.adc(v)')
    elif mn == 'SBC': L.append('c.sbc(v)')
    elif mn == 'AND': L.append('c.a = c.zr = c.ng = c.a & v')
    elif mn == 'ORA': L.append('c.a = c.zr = c.ng = c.a | v')
    elif mn == 'EOR': L.append('c.a = c.zr = c.ng = c.a ^ v')
    elif mn in ('CMP', 'CPX', 'CPY'):
        r = dict(CMP='a', CPX='x', CPY='y')[mn]
        L += ['t = c.%s - v' % r, 'c.c = 1 if t >= 0 else 0', 'c.zr = c.ng = t & 255']
    elif mn == 'BIT': L += ['c.zr = c.a & v', 'c.ng = v', 'c.v = v >> 6 & 1']
    elif mn == 'ASL': L += ['c.c = v >> 7', 'v = v << 1 & 255', 'c.zr = c.ng = v'] + put('v')
    elif mn == 'LSR': L += ['c.c = v & 1', 'v >>= 1', 'c.zr = c.ng = v'] + put('v')
    elif mn == 'ROL': L += ['t = (v << 1 | c.c) & 255', 'c.c = v >> 7', 'c.zr = c.ng = t'] + put('t')
    elif mn == 'ROR': L += ['t = v >> 1 | c.c << 7', 'c.c = v & 1', 'c.zr = c.ng = t'] + put('t')
    elif mn == 'INC': L += ['v = (v + 1) & 255', 'c.zr = c.ng = v'] + put('v')
    elif mn == 'DEC': L += ['v = (v - 1) & 255', 'c.zr = c.ng = v'] + put('v')
    elif mn in ('INX', 'INY', 'DEX', 'DEY'):
        r = mn[2].lower(); L.append('c.%s = c.zr = c.ng = (c.%s %s 1) & 255' % (r, r, '+' if mn[0] == 'I' else '-'))
    elif mn in ('TAX', 'TAY', 'TXA', 'TYA', 'TSX'):
        L.append('c.%s = c.zr = c.ng = c.%s' % (mn[2].lower(), mn[1].lower()))
    elif mn == 'TXS': L.append('c.s = c.x')
    elif mn == 'PHA': L.append(_PUSH % 'c.a')
    elif mn == 'PHP': L.append(_PUSH % 'c.getp()')
    elif mn == 'PLA': L += [_POP % 'v', 'c.a = c.zr = c.ng = v']
    elif mn == 'PLP': L += [_POP % 'v', 'c.setp(v)']
    elif mn in ('CLC', 'SEC'): L.append('c.c = %d' % (mn == 'SEC'))
    elif mn in ('CLI', 'SEI'): L.append('c.i = %d' % (mn == 'SEI'))
    elif mn in ('CLD', 'SED'): L.append('c.d = %d' % (mn == 'SED'))
    elif mn == 'CLV': L.append('c.v = 0')
    elif mn == 'NOP': pass
    elif mn == 'JMP':
        nxt = 'return ea' if am == 'abs' else 'return m[ea] | m[(ea & 0xff00) | ((ea + 1) & 255)] << 8'
    elif mn == 'JSR':
        L += ['t = pc + 2', _PUSH % 't >> 8', _PUSH % 't & 255']; nxt = 'return ea'
    elif mn == 'RTS':
        L += [_POP % 'lo', _POP % 'hi']; nxt = 'return ((lo | hi << 8) + 1) & 0xffff'
    elif mn == 'RTI':
        L += [_POP % 'v', 'c.setp(v)', _POP % 'lo', _POP % 'hi']; nxt = 'return lo | hi << 8'
    elif mn == 'BRK': nxt = 'return c.trap(pc)'
    else: raise ValueError(mn)
    L.append(nxt)
    return 'def op_%02X(c, pc):\n' % op + ''.join('    %s\n' % s for s in L)


class CPU:
    def __init__(self):
        self.m = bytearray(65536)
        self.wmap = bytearray(65536)     # 1 = written since reset of the map
        self.xmap = [0] * 65536          # times executed as an opcode
        self.a = self.x = self.y = 0; self.s = 0xff; self.pc = 0; self.cyc = 0
        self.c = self.i = self.d = self.v = 0; self.zr = 1; self.ng = 0
        self.rmap = bytearray(65536)     # 1 = read as data
        ns = dict(m=self.m, w=self.wmap, x=self.xmap, r=self.rmap)
        exec(''.join(_gen(op, *OPS[op]) for op in OPS), ns)
        self.ops = [ns.get('op_%02X' % op, lambda c, pc: c.trap(pc)) for op in range(256)]

    # hardware window and traps: overridden by the machine model
    def hwr(self, a): return self.m[a]
    def hww(self, a, v): self.m[a] = v
    def trap(self, pc): raise Halt('trap/undefined opcode %02X at %04X' % (self.m[pc], pc))

    def getp(self):
        return self.c | (0 if self.zr else 2) | self.i << 2 | self.d << 3 | 0x30 | self.v << 6 | (self.ng & 128)

    def setp(self, p):
        self.c = p & 1; self.zr = 0 if p & 2 else 1; self.i = p >> 2 & 1; self.d = p >> 3 & 1
        self.v = p >> 6 & 1; self.ng = p & 128

    def push(self, v): self.m[256 + self.s] = v; self.s = (self.s - 1) & 255
    def pop(self): self.s = (self.s + 1) & 255; return self.m[256 + self.s]

    def adc(self, v):
        a = self.a
        if self.d:
            lo = (a & 15) + (v & 15) + self.c; hi = (a >> 4) + (v >> 4)
            if lo > 9: lo += 6; hi += 1
            self.zr = (a + v + self.c) & 255; self.ng = hi << 4 & 128
            self.v = int(((a ^ v) & 0x80) == 0 and ((a ^ (hi << 4)) & 0x80) != 0)
            if hi > 9: hi += 6
            self.c = int(hi > 15); self.a = (hi << 4 | lo & 15) & 255
        else:
            t = a + v + self.c
            self.v = 1 if (~(a ^ v) & (a ^ t) & 0x80) else 0
            self.c = t >> 8; self.a = self.zr = self.ng = t & 255

    def sbc(self, v):
        if self.d:
            a = self.a; b = 1 - self.c
            t = a - v - b; lo = (a & 15) - (v & 15) - b; hi = (a >> 4) - (v >> 4)
            if lo < 0: lo -= 6; hi -= 1
            if hi < 0: hi -= 6
            self.v = 1 if ((a ^ v) & (a ^ t) & 0x80) else 0
            self.c = int(t >= 0); self.zr = self.ng = t & 255
            self.a = (hi << 4 | lo & 15) & 255
        else:
            self.adc(v ^ 255)

    def step(self):
        self.pc = self.ops[self.m[self.pc]](self, self.pc)

    def run(self, limit):
        """Execute until the cycle counter reaches limit."""
        ops = self.ops; m = self.m
        while self.cyc < limit:
            self.pc = ops[m[self.pc]](self, self.pc)
