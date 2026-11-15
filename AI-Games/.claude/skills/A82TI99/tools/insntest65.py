"""Instruction-level check of xlate65: random 6502 snippets on the reference CPU against their translation
on the TMS9900 emulator.   insntest65.py [rounds] [seed] [workdir]      exits nonzero on any mismatch."""
import sys, os, random, collections
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from m6502 import CPU, OPS, LEN, disasm
import xlate65, asm65, ti99emu_base as base

ORG6 = 0x4000; TIORG = 0xA000
SKIPMN = {'BRK', 'RTI', 'PHP', 'PLP', 'TSX', 'TXS', 'SED', 'CLV', 'BVC', 'BVS', 'JMP', 'JSR', 'RTS', 'CLI', 'SEI', 'CLD', 'NOP', 'BIT'}
BR = {'BEQ': 0xF0, 'BNE': 0xD0, 'BMI': 0x30, 'BPL': 0x10, 'BCS': 0xB0, 'BCC': 0x90}


class G:
    CODE = (ORG6, 0x6000); IJMP = {}; NATIVE = {}; SMC_IGNORE = set(); PATCH = {}; SKIP = set()
    PTR = {}; PTR_DEFAULT = "D"; K = 0x2000; KS = 0; IZX_X0 = False

    def __init__(s, mem, seeds): s.MEM = mem; s.SEEDS = seeds
    def is_hw(s, a): return False
    def in_screen(s, a): return False

    def ti_addr(s, a, pc):
        if 0x80 <= a < 0x100: return 0x82A0 + a
        if 0x200 <= a < 0x2000: return a + 0x2000
        if ORG6 <= a < 0x6000: return a - ORG6 + 0xE000
        raise xlate65.XError('test address %04X at %04X' % (a, pc))


def rand_insn(rnd):
    while True:
        op = rnd.choice(list(OPS)); mn, am = OPS[op]
        if mn in SKIPMN or mn in BR or am == 'izx': continue
        if am in ('zp', 'zpx', 'zpy'): arg = [rnd.randint(0xE0, 0xEF)]
        elif am == 'izy': arg = [rnd.choice(range(0x80, 0xDE, 2))]
        elif am == 'imm': arg = [rnd.choice((0, 1, 0x7F, 0x80, 0xFF, rnd.randint(0, 255)))]
        elif am in ('abs', 'abx', 'aby'):
            a = rnd.randint(0x300, 0x1B00); arg = [a & 255, a >> 8]
        else: arg = []
        return bytes([op] + arg)


def jmp(a): return bytes([0x4C, a & 255, a >> 8])


def build(rnd, count):
    mem = bytearray(65536); pc = ORG6; tests = []
    while len(tests) < count and pc < 0x5F00:
        parts = []; dirty = False
        for _ in range(rnd.choice((1, 1, 2, 3, 4))):
            while True:
                i = rand_insn(rnd); mn, am = OPS[i[0]]
                if not (dirty and am in ("zpx", "zpy")): break      # zero-page index wrap is not modelled
            parts.append(i)
            if mn in ("LDX", "LDY", "TAX", "TAY", "INX", "INY", "DEX", "DEY"): dirty = True
        seq = b"".join(parts)
        if rnd.random() < 0.25: seq = bytes([rnd.choice((0x18, 0x38))]) + seq           # CLC / SEC first
        use_sub = rnd.random() < 0.15
        obs = rnd.choice(list(BR) + [None])
        start = pc
        tail = (2 + 12) if obs else 6
        if use_sub:        # JSR S / observer ... S: seq / RTS
            body = pc + 3 + tail
            code = bytes([0x20, body & 255, body >> 8])
        else:
            code = seq
        p = pc + len(code)
        if obs:
            e0 = p + 8; e1 = p + 11
            code += bytes([BR[obs], 3]) + jmp(e0) + jmp(e1) + jmp(e0) + jmp(e1); ends = (e0, e1)
        else:
            e0 = p + 3
            code += jmp(e0) + jmp(e0); ends = (e0,)
        if use_sub: code += seq + b'\x60'
        mem[pc:pc + len(code)] = code; pc += len(code)
        tests.append((start, ends, seq, obs, use_sub))
    return mem, tests


def run_round(rnd, count, cases, work):
    mem, tests = build(rnd, count)
    g = G(bytes(mem), [t[0] for t in tests])
    x = xlate65.Translator(g); chunks = x.translate()
    lines = ['XLB    EQU  >8305', 'YLB    EQU  >8307', 'R4LB   EQU  >8309', '       AORG >%04X' % TIORG]
    for _, items in chunks:
        for it in items: lines += asm65.item_text(it, 1)
    lines += ['CURBNK EQU  >3FF8', 'RETF   STST R15', '       MOV  *R10+,R14', '       MOV  *R10+,R0', '       RTWP',
              'RETN   MOV  *R10+,R11', '       MOV  *R10+,R0', '       B    *R11']
    lines += ['ZPMAP  ANDI R4,>00FF', '       AI   R4,>82A0', '       RT']
    lines += ['IRET   JMP  IRET', 'PTRMAP JMP  PTRMAP', 'PTRST  JMP  PTRST', 'SCRST  JMP  SCRST', 'BTAB']
    lines += ['       BYTE ' + ','.join('>%02X' % v for v in range(i, i + 16)) for i in range(0, 256, 16)]
    lines.append('       END')
    src = os.path.join(work, 'insn.a99'); open(src, 'w').write('\n'.join(lines) + '\n')
    img, sym = asm65.assemble(src)
    code = img[None]
    assert max(code) < 0xE000, 'test code too large'
    fails = 0
    for start, ends, seq, obs, use_sub in tests:
        for _ in range(cases):
            c = CPU(); c.m[:] = mem
            t = base.TI99(bytes(8192), b'', [bytearray(8192)])
            for a, v in code.items(): t.exp[a] = v
            for a in range(ORG6, 0x6000): t.exp[a - ORG6 + 0xE000] = mem[a]
            for a in range(0x80, 0x100): c.m[a] = t.scratch[0x20 + a - 0x80] = rnd.randint(0, 255)
            for a in range(0x80, 0xE0, 2):                       # pointers into the data area
                p = rnd.randint(0x300, 0x1A00); c.m[a] = p & 255; c.m[a + 1] = p >> 8
                t.scratch[0x20 + a - 0x80] = p & 255; t.scratch[0x21 + a - 0x80] = p >> 8
            for a in range(0x200, 0x1E00): c.m[a] = t.exp[a + 0x2000] = rnd.randint(0, 255)
            for a in range(0x1E0, 0x200): c.m[a] = t.exp[0x3F00 + a - 0x1E0] = rnd.randint(0, 255)
            A = rnd.choice((0, 1, 0x7F, 0x80, 0xFF, rnd.randint(0, 255))); X = rnd.randint(0, 0x10); Y = rnd.randint(0, 0x10)
            C = rnd.randint(0, 1); nz = rnd.choice((A, X, Y))     # N/Z describe one of the registers
            c.a, c.x, c.y, c.c, c.zr, c.ng = A, X, Y, C, nz, nz; c.s = 0xEF; c.pc = start
            t.wp = 0x8300; t.pc = sym['L%04X' % start]
            t.st = (0x1000 if C else 0) | (0x2000 if nz == 0 else 0x8000 if nz >= 128 else 0xC000)
            regs = {1: A << 8, 2: X, 3: Y, 5: 0, 6: 1, 7: 0x3F10, 9: 0x0100, 10: 0x3FE0, 13: 0x8300}
            for r, v in regs.items(): t.scratch[2 * r] = v >> 8; t.scratch[2 * r + 1] = v & 255
            n = 0
            try:
                while c.pc not in ends and n < 200: c.step(); n += 1
            except Exception: continue
            if c.pc not in ends: continue                         # unbalanced PHA/PLA inside a subroutine
            tends = [sym['L%04X' % e] for e in ends]; n = 0
            while t.pc not in tends and n < 4000: t.step(); n += 1
            R = lambda r: t.scratch[2 * r] << 8 | t.scratch[2 * r + 1]
            bad = []
            if t.pc not in tends: bad.append('TI did not finish (pc %04X)' % t.pc)
            elif tends.index(t.pc) != ends.index(c.pc): bad.append('exit %d, 6502 took %d' % (tends.index(t.pc), ends.index(c.pc)))
            if R(1) != c.a << 8: bad.append('A %04X vs %02X' % (R(1), c.a))
            if R(2) != c.x: bad.append('X %04X vs %02X' % (R(2), c.x))
            if R(3) != c.y: bad.append('Y %04X vs %02X' % (R(3), c.y))
            if R(5) & 255: bad.append('R5 low byte %04X' % R(5))
            if R(6) & 255 != 1: bad.append('R6 low byte %04X' % R(6))
            if R(7) - 0x3F10 != c.s - 0xEF: bad.append('stack %04X vs S %02X' % (R(7), c.s))
            if R(10) != 0x3FE0: bad.append('return stack %04X' % R(10))
            for a in range(0x80, 0x100):
                if c.m[a] != t.scratch[0x20 + a - 0x80]:
                    bad.append('zp %02X: %02X vs %02X' % (a, t.scratch[0x20 + a - 0x80], c.m[a])); break
            if bytes(c.m[0x200:0x1E00]) != bytes(t.exp[0x2200:0x3E00]):
                a = next(a for a in range(0x200, 0x1E00) if c.m[a] != t.exp[a + 0x2000])
                bad.append('mem %04X: %02X vs %02X' % (a, t.exp[a + 0x2000], c.m[a]))
            if not use_sub and bytes(c.m[0x1E0:0x1F0]) != bytes(t.exp[0x3F00:0x3F10]): bad.append('pushed bytes differ')
            if bad:
                fails += 1
                p = 0; txt = []; pad = seq + b'\0\0'
                while p < len(seq):
                    k, s = disasm(pad, p); txt.append(s); p += k
                print('FAIL %04X [%s] obs=%s sub=%s A=%02X X=%02X Y=%02X C=%d nz=%02X: %s' % (
                    start, '; '.join(txt), obs, use_sub, A, X, Y, C, nz, '; '.join(bad)))
                break
    return len(tests), fails


if __name__ == '__main__':
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    work = sys.argv[3] if len(sys.argv) > 3 else os.path.join(HERE, '_insn')
    os.makedirs(work, exist_ok=True)
    rnd = random.Random(seed); total = bad = 0
    for _ in range(rounds):
        n, f = run_round(rnd, 200, 12, work); total += n; bad += f
    print('%d snippets, %d failed' % (total, bad))
    sys.exit(1 if bad else 0)
