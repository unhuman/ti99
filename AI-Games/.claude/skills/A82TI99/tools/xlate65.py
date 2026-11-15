"""Static 6502 -> TMS9900 translator (A82TI99).

Register model (workspace >8300):
  R0  scratch / computed 6502 address     R1  A in the high byte, low byte 0
  R2  X zero-extended (low byte)          R3  Y zero-extended (low byte)
  R4  scratch                             R5  byte temp, low byte always 0
  R6  byte temp, low byte always 1        R7  6502 data stack (PHA/PLA), bytes, grows down
  R9  constant >0100                      R10 return stack (words, grows down)
  R11 link                                R13 constant >8300 (for RTWP)
  R14, R15 used by the status-preserving sequences (STST R15 ... RTWP)

Flags: N, Z and C live in the TMS9900 status register, and only when a later
instruction can read them (liveness, across calls).  C after CLC/SEC is
tracked as a known constant until something needs it in the status register.
A sequence that would destroy a live flag is wrapped in STST R15 ... RTWP,
which restores the whole status register.

Memory: every static 6502 address is mapped at translate time (game.ti_addr);
computed addresses (indirect,Y and self-modified operands) are mapped per
site: 'D' = main region (TI = 6502 + K), 'S' = screen shadow, 'M' = decided at
run time.  Screen stores go through SCRST / PTRST so the picture reaches VRAM.

Output: chunks of items for build65.py -- text lines, ('LABEL', name),
('BR', true_jumps, false_jumps, target), ('JMP', target), ('CALL', target),
('RET', keep_flags).
"""
import collections
from m6502 import OPS, LEN, STORES, RMW, disasm
from trace65 import Trace

NZDEF = {'LDA', 'LDX', 'LDY', 'TAX', 'TAY', 'TXA', 'TYA', 'TSX', 'ADC', 'SBC', 'AND', 'ORA', 'EOR', 'CMP', 'CPX', 'CPY',
         'INC', 'DEC', 'INX', 'INY', 'DEX', 'DEY', 'ASL', 'LSR', 'ROL', 'ROR', 'PLA', 'BIT'}
CDEF = {'ADC', 'SBC', 'CMP', 'CPX', 'CPY', 'ASL', 'LSR', 'ROL', 'ROR', 'CLC', 'SEC'}
CUSE = {'ADC', 'SBC', 'ROL', 'ROR', 'BCC', 'BCS'}
BRUSE = dict(BEQ='Z', BNE='Z', BMI='N', BPL='N', BCC='C', BCS='C', BVC='V', BVS='V')
BRJ = dict(BEQ=(['JEQ'], ['JNE']), BNE=(['JNE'], ['JEQ']), BCS=(['JOC'], ['JNC']), BCC=(['JNC'], ['JOC']),
           BMI=(['JLT'], ['JGT', 'JEQ']), BPL=(['JGT', 'JEQ'], ['JLT']))
BRJ_CMP = dict(BCS=(['JHE'], ['JL']), BCC=(['JL'], ['JHE']))
REGB = dict(A='R1', X='@XLB', Y='@YLB')


class XError(Exception): pass


class Translator:
    def __init__(self, g):
        self.g = g; self.m = g.MEM
        self.ijmp = g.IJMP
        seeds = list(g.SEEDS) + [t for v in self.ijmp.values() for t in v]
        self.t = Trace(self.m, g.CODE[0], g.CODE[1]).run(seeds, stops=set(g.NATIVE))
        self.code = self.t.code
        self.codeb = self.t.code_bytes()
        self.labels = set(self.t.labels) | set(seeds) | set(e for _, e in getattr(g, "REGION", {}).values())     # native loops jump to their exits
        self.subs = set(self.t.subs)
        self.smc = self.find_smc()
        self.uid = 0
        self.succ = {}; self.build_cfg()
        self.live = self.liveness()
        self.warn = []

    # ---- analysis ----------------------------------------------------------
    def find_smc(self):
        """Instructions whose operand bytes are written: {pc: (lo cell, hi cell)}."""
        out = {}
        written = set(a for a, rs in self.t.refs.items() if any('w' in k for _, k, _ in rs))
        written |= set(getattr(self.g, 'SMC_EXTRA', ()))
        for pc, n in self.code.items():
            if n == 3 and (pc + 1 in written or pc + 2 in written) and pc not in self.g.SMC_IGNORE:
                mn, am = OPS[self.m[pc]]
                if mn in ('JMP', 'JSR'): raise XError('self-modified %s at %04X: annotate it' % (mn, pc))
                out[pc] = (pc + 1, pc + 2)
        return out

    def ins(self, pc): return OPS[self.m[pc]]

    def operand(self, pc):
        n = self.code[pc]
        return self.m[pc + 1] | (self.m[pc + 2] << 8 if n == 3 else 0)

    def build_cfg(self):
        m = self.m
        for pc, n in self.code.items():
            mn, am = self.ins(pc); nx = pc + n; s = []
            if pc in self.g.NATIVE: self.succ[pc] = []; continue
            if mn == 'JMP':
                s = [self.operand(pc)] if am == 'abs' else list(self.ijmp.get(self.operand(pc), []))
            elif mn in ('RTS', 'RTI', 'BRK'): s = []
            elif am == 'rel':
                d = m[pc + 1]; s = [nx, (pc + 2 + (d - 256 if d > 127 else d)) & 0xffff]
            else: s = [nx]
            self.succ[pc] = [a for a in s if a in self.code or a in self.g.NATIVE]

    def liveness(self):
        """Flags (N, Z, C) that may be read after each instruction.  JSR is transparent
        (live before = live after + callee's needs); RTS takes the union over its callers."""
        code = self.code
        # which subroutine entries reach each RTS
        reach = collections.defaultdict(set)
        for sub in self.subs:
            seen = set(); todo = [sub]
            while todo:
                pc = todo.pop()
                if pc in seen or pc not in code: continue
                seen.add(pc)
                if self.ins(pc)[0] == 'RTS': reach[pc].add(sub)
                todo += self.succ[pc]
        callers = collections.defaultdict(list)
        for pc in code:
            if self.ins(pc)[0] == 'JSR': callers[self.operand(pc)].append(pc)
        after = {pc: frozenset() for pc in code}; before = {pc: frozenset() for pc in code}
        natlive = self.g.NATIVE_LIVEIN if hasattr(self.g, 'NATIVE_LIVEIN') else {}
        order = sorted(code, reverse=True); changed = True
        while changed:
            changed = False
            for pc in order:
                mn, am = self.ins(pc)
                if mn == 'RTS':
                    a = frozenset().union(*[after[c] for s in reach[pc] for c in callers[s]]) if reach[pc] else frozenset()
                elif mn == 'JSR':
                    tgt = self.operand(pc)
                    a = after[pc]            # placeholder, recomputed below from the successor
                    nx = pc + 3
                    a = before.get(nx, frozenset())
                else:
                    a = frozenset().union(*[before[s] if s in before else frozenset(natlive.get(s, ())) for s in self.succ[pc]]) if self.succ[pc] else frozenset()
                b = set(a)
                if mn == 'JSR':
                    tgt = self.operand(pc)
                    b |= before[tgt] if tgt in before else set(natlive.get(tgt, ()))
                else:
                    if mn in NZDEF: b -= {'N', 'Z'}
                    if mn in CDEF: b.discard('C')
                    if mn in CUSE and mn not in BRUSE: b.add('C')
                    if mn in BRUSE: b.add(BRUSE[mn])
                b = frozenset(b)
                if a != after[pc] or b != before[pc]:
                    after[pc] = a; before[pc] = b; changed = True
        self.before = before
        return after

    # ---- operand mapping ---------------------------------------------------
    def lab(self, a): return 'L%04X' % a

    def local(self):
        self.uid += 1; return 'T%d' % self.uid

    def cell(self, a, pc):
        """TMS operand for a static 6502 byte address."""
        return '@>%04X' % self.g.ti_addr(a, pc)

    def resolve(self, pc, store=False):
        """-> (kind, prep, S, mode).  kind: imm | mem | ptr | hw.  prep computes R0 for ptr."""
        g = self.g; mn, am = self.ins(pc); v = self.operand(pc)
        if am == 'imm': return 'imm', [], v, None
        if pc in self.smc:
            lo, hi = self.smc[pc]
            prep = ['MOVB %s,R4' % self.cell(hi, pc), 'MOVB %s,@R4LB' % self.cell(lo, pc)]
            if am == 'abx': prep.append('A    R2,R4')
            elif am == 'aby': prep.append('A    R3,R4')
            elif am != 'abs': raise XError('self-modified %s operand at %04X' % (am, pc))
            return self.ptr(pc, prep)
        if am in ('zp', 'abs'):
            if g.is_hw(v): return 'hw', [], v, None
            if g.in_screen(v) and store: return self.ptr(pc, ['LI   R4,>%04X' % v], 'S')
            return 'mem', [], self.cell(v, pc), None
        if am in ('zpx', 'zpy', 'abx', 'aby'):
            r = 'R2' if am[2] == 'x' else 'R3'
            if am[0] == 'z':     # zero-page index wraps at $FF (DEX/BPL loops leave X = $FF): map at run time
                return 'ptr', ['MOV  %s,R4' % r, 'AI   R4,%d' % v, 'BL   @ZPMAP'], '*R4', 'D'
            if g.is_hw(v):
                if not store: raise XError('indexed hardware read at %04X' % pc)
                return 'hwx', [], v, r
            if g.in_screen(v) and store: return self.ptr(pc, ['LI   R4,>%04X' % v, 'A    %s,R4' % r], 'S')
            return 'mem', [], '%s(%s)' % (self.cell(v, pc), r), None
        if am == 'izy':
            prep = ['MOVB %s,R4' % self.cell((v + 1) & 255, pc), 'MOVB %s,@R4LB' % self.cell(v, pc), 'A    R3,R4']
            return self.ptr(pc, prep)
        if am == 'izx':
            if self.g.IZX_X0:      # the game only uses (zp,X) with X = 0 (checked by the reference run)
                return self.ptr(pc, ['MOVB %s,R4' % self.cell((v + 1) & 255, pc), 'MOVB %s,@R4LB' % self.cell(v, pc)])
        raise XError('addressing mode %s at %04X' % (am, pc))

    def ptr(self, pc, prep, mode=None):
        mode = mode or self.g.PTR.get(pc, getattr(self.g, "PTR_DEFAULT", "M"))
        if mode == 'D': return 'ptr', prep, '@>%04X(R4)' % self.g.K, 'D'
        if mode == 'S': return 'ptr', prep, '@>%04X(R4)' % self.g.KS, 'S'
        if mode != 'M':            # 'F' font, 'I:xxxx' one island: a fixed offset, treated like the main region
            return 'ptr', prep, '@>%04X(R4)' % self.g.region_k(mode), 'D'
        return 'ptr', prep, '*R4', 'M'

    # ---- emission helpers ----------------------------------------------------
    @staticmethod
    def protect(lines):
        return ['STST R15'] + lines + ['LI   R14,$+6', 'RTWP']

    def flush_c(self, out, needed):
        """Put a known carry (after CLC/SEC) into the status register if someone will read it."""
        if self.ck is not None and needed:
            out += ['STST R15', 'ORI  R15,>1000' if self.ck else 'ANDI R15,>EFFF', 'LI   R14,$+6', 'RTWP']
        self.ck = None

    def translate(self):
        g = self.g; chunks = []; cur = None
        self.nzsrc = None; self.ck = None; self.cmpform = 0
        pcs = sorted(self.code); nextpc = {a: b for a, b in zip(pcs, pcs[1:])}
        dead = getattr(g, 'DEAD', ())            # bodies of loops a native replaced (g.PATCH at their heads)
        for pc in pcs:
            if pc in dead: cur = None; continue
            n = self.code[pc]; mn, am = self.ins(pc)
            if cur is None: cur = (pc, []); chunks.append(cur)
            out = cur[1]
            if pc in self.labels:
                self.nzsrc = None; self.cmpform = 0
                if self.ck is not None: raise XError('pending carry into label %04X' % pc)
            if pc in self.subs:
                if out and self.falls_in(pc, pcs): out.append(('JMP', self.lab(pc)))
                out.append(('LABEL', 'J%04X' % pc))
                pro = ['DECT R10', 'MOV  @CURBNK,*R10', 'DECT R10', 'MOV  R11,*R10']     # frame = return address, bank
                out += self.protect(pro) if self.before[pc] else pro
            if pc in self.labels: out.append(('LABEL', self.lab(pc)))
            out.append('* %04X %s' % (pc, disasm(self.m, pc)[1]))
            if pc in g.NATIVE:
                out.append('B    @%s' % g.NATIVE[pc]); cur = None; continue
            if pc in g.PATCH: out += g.PATCH[pc]
            else: self.xl(pc, out)
            nx = pc + n
            ends = mn in ('JMP', 'RTS', 'RTI', 'BRK')
            if not ends:
                if nx not in self.code and nx not in g.NATIVE:
                    raise XError('falls off traced code after %04X' % pc)
                if nx in self.labels or nx in g.NATIVE: self.flush_c(out, 'C' in self.live[pc])
                if nx in g.NATIVE: out += [("CALL", nx, g.NATIVE[nx]), ("RET", True)]; cur = None
                elif nextpc.get(pc) != nx: out.append(('JMP', self.lab(nx))); cur = None
            else: cur = None
        return chunks

    def falls_in(self, pc, pcs):
        """True if the instruction just before pc in memory can fall through into it."""
        for back in (1, 2, 3):
            p = pc - back
            if p in self.code and p + self.code[p] == pc:
                return self.ins(p)[0] not in ('JMP', 'RTS', 'RTI', 'BRK')
        return False

    # ---- one instruction -------------------------------------------------------
    def xl(self, pc, out):
        g = self.g; mn, am = self.ins(pc); live = self.live[pc]
        LNZ = bool(live & {'N', 'Z'}); LC = 'C' in live
        cmpform = self.cmpform; self.cmpform = max(0, cmpform - 1)

        if mn in BRUSE:
            tgt = pc + 2 + ((self.m[pc + 1] ^ 128) - 128)
            if mn in ('BVC', 'BVS'): raise XError('V flag branch at %04X' % pc)
            if mn in ('BCC', 'BCS') and self.ck is not None and not cmpform:
                taken = (mn == 'BCS') == bool(self.ck)
                self.flush_c(out, LC)
                if taken: out.append(('JMP', self.lab(tgt)))
                return
            self.flush_c(out, LC or mn in ('BCC', 'BCS'))
            tj, fj = (BRJ_CMP if cmpform and mn in BRJ_CMP else BRJ)[mn]
            out.append(('BR', tj, fj, self.lab(tgt)))
            return
        if mn == 'JMP':
            self.flush_c(out, bool(self.before.get(self.operand(pc), ())) if am == 'abs' else True)
            if am == "abs" and self.operand(pc) in g.NATIVE:
                out += [("CALL", self.operand(pc), g.NATIVE[self.operand(pc)]), ("RET", True)]
            elif am == "abs": out.append(("JMP", self.lab(self.operand(pc))))
            else: out.append('B    @IJ%04X' % self.operand(pc))
            return
        if mn == 'JSR':
            self.flush_c(out, 'C' in self.before[pc])
            tg = self.operand(pc)
            out.append(("CALL", tg, g.NATIVE[tg]) if tg in g.NATIVE else ("CALL", tg)); self.nzsrc = None
            return
        if mn == 'RTS':
            self.flush_c(out, LC)
            out.append(('RET', bool(live))); return
        if mn == 'RTI': out.append('B    @IRET'); return
        if mn in ('CLC', 'SEC'): self.ck = int(mn == 'SEC'); return
        if mn in ('CLD', 'NOP', 'CLI', 'SEI') or (mn == 'TXS' and pc in g.SKIP): return
        if mn in ('SED', 'BRK', 'PHP', 'PLP', 'TSX', 'TXS', 'CLV'): raise XError('%s at %04X is not supported' % (mn, pc))

        # --- implied register instructions
        if mn in ('TAX', 'TAY', 'TXA', 'TYA'):
            out.append('MOVB %s,%s' % (REGB[mn[1]], REGB[mn[2]])); self.nzsrc = mn[2]; return
        if mn in ('INX', 'INY', 'DEX', 'DEY'):
            r = REGB[mn[2]]; core = ['%s R9,%s' % ('AB  ' if mn[0] == 'I' else 'SB  ', r)]
            if LC and self.ck is None: out += self.protect(core) + (['MOVB %s,%s' % (r, r)] if LNZ else [])
            else: out += core
            self.nzsrc = mn[2]; return
        if mn == 'PHA':
            core = ['DEC  R7', 'MOVB R1,*R7']
            out += self.protect(core) if (LNZ or (LC and self.ck is None)) else core
            return
        if mn == 'PLA': out.append('MOVB *R7+,R1'); self.nzsrc = 'A'; return
        if am == 'acc':
            self.shift(mn, 'R1', None, out, LNZ); self.nzsrc = 'A'; return

        kind, prep, S, mode = self.resolve(pc, store=mn in STORES or mn in RMW)
        clob = bool(prep)                     # address computation destroys NZ and C

        # --- stores
        if mn in STORES:
            reg = mn[2]; src = REGB[reg]
            if kind == 'hw' or kind == 'hwx':
                core = g.hw_write(S, src, mode, pc); plain = False
            elif kind == 'ptr' and mode in ('S', 'M'):
                core = prep + ['MOVB %s,R5' % src, 'BL   @%s' % ('SCRST' if mode == 'S' else 'PTRST')]; plain = False
            else:
                core = prep + ['MOVB %s,%s' % (src, S)]; plain = not clob
            bad_nz = LNZ and not (plain and self.nzsrc == reg)
            bad_c = LC and self.ck is None and not plain
            out += self.protect(core) if (bad_nz or bad_c) else core
            if not (bad_nz or bad_c) and not plain: self.nzsrc = None
            return

        # --- hardware reads: the hook returns the byte in R0's high byte
        if kind == 'hw':
            rd = g.hw_read(S, pc)
            keepc = (mn in CUSE or (LC and mn not in CDEF)) and self.ck is None
            out += self.protect(rd) if keepc else rd
            kind, prep, S, clob = 'mem', [], 'R0', False
        if kind == 'ptr' and mode == 'M': prep = prep + ['BL   @PTRMAP']
        usec = mn in CUSE and self.ck is None
        if clob:
            keepc = usec or (LC and mn not in CDEF and self.ck is None)
            out += self.protect(prep) if keepc else prep

        if mn in ('LDA', 'LDX', 'LDY'):
            r = mn[2]
            if kind == 'imm':
                out.append('LI   %s,>%04X' % (dict(A='R1', X='R2', Y='R3')[r], S << 8 if r == 'A' else S))
                if r != 'A' and S >= 128 and 'N' in live: out.append('MOVB %s,%s' % (REGB[r], REGB[r]))
            else: out.append('MOVB %s,%s' % (S, REGB[r]))
            self.nzsrc = r; return
        if mn == 'ORA':
            out.append('ORI  R1,>%04X' % (S << 8) if kind == 'imm' else 'SOCB %s,R1' % S); self.nzsrc = 'A'; return
        if mn == 'AND':
            out += ['ANDI R1,>%04X' % (S << 8)] if kind == 'imm' else ['MOVB %s,R0' % S, 'INV  R0', 'SZCB R0,R1']
            self.nzsrc = 'A'; return
        if mn == 'EOR':
            out += ['LI   R5,>%04X' % (S << 8) if kind == 'imm' else 'MOVB %s,R5' % S, 'XOR  R5,R1']
            self.nzsrc = 'A'; return
        if mn in ('ADC', 'SBC'):
            add = mn == 'ADC'; ck = self.ck; self.ck = None; self.nzsrc = 'A'
            src = '@BTAB+%d' % S if kind == 'imm' else S
            if ck is not None and ck == (0 if add else 1):
                if add: out.append('AI   R1,>%04X' % (S << 8) if kind == 'imm' else 'AB   %s,R1' % S)
                else: out.append('SB   %s,R1' % src)
                return
            a = self.local(); b = self.local()
            carry_path = (['ORI  R1,>00FF', 'MOVB %s,R6' % src, 'A    R6,R1'] if add else
                          ['MOVB %s,R6' % src, 'S    R6,R1', 'ANDI R1,>FF00'])
            plain_path = ['AB   %s,R1' % src] if add else ['SB   %s,R1' % src]
            if ck is not None:                 # known carry of the "other" sense: SEC/ADC or CLC/SBC
                out += carry_path; return
            first, second = (plain_path, carry_path) if add else (carry_path, plain_path)
            out += ['JOC  %s' % a] + first + ['JMP  %s' % b, ('LABEL', a)] + second + [('LABEL', b)]
            return
        if mn in ('CMP', 'CPX', 'CPY'):
            r = dict(CMP='A', CPX='X', CPY='Y')[mn]; self.ck = None; self.nzsrc = None
            k = self.fusable(pc)
            if k:
                if kind == 'imm': out.append('CI   R1,>%04X' % (S << 8) if r == 'A' else 'CI   %s,%d' % ('R2' if r == 'X' else 'R3', S))
                else: out.append('CB   %s,%s' % (REGB[r], S))
                self.cmpform = k; return
            out += ['MOVB %s,R5' % REGB[r], 'SB   %s,R5' % ('@BTAB+%d' % S if kind == 'imm' else S)]
            return
        if mn == 'BIT':
            self.nzsrc = None
            want = live & {'N', 'Z'}
            if want == {'N'} or not want: out.append('MOVB %s,R5' % S)
            elif want == {'Z'}: out += ['MOV  R1,R0', 'INV  R0', 'MOVB %s,R5' % S, 'SZCB R0,R5']
            else: raise XError('BIT at %04X needs both N and Z' % pc)
            return
        if mn in ('INC', 'DEC'):
            core = ['%s R9,%s' % ('AB  ' if mn == 'INC' else 'SB  ', S)]
            if kind == 'ptr' and mode != 'D': raise XError('read-modify-write on the screen at %04X' % pc)
            if LC and self.ck is None: out += self.protect(core) + (['MOVB %s,R5' % S] if LNZ else [])
            else: out += core
            self.nzsrc = None; return
        if mn in RMW:
            if kind == 'ptr' and mode != 'D': raise XError('shift on the screen at %04X' % pc)
            self.shift(mn, 'R5', S, out, LNZ); self.nzsrc = None; return
        raise XError('%s %s at %04X' % (mn, am, pc))

    def shift(self, mn, r, S, out, LNZ):
        """ASL/LSR/ROL/ROR on the high byte of register r (R1 = A, or R5 loaded from memory S)."""
        if mn in ('ROL', 'ROR'): self.flush_c(out, True)
        self.ck = None
        if S: out.append('MOVB %s,%s' % (S, r))
        if mn == 'ASL': out.append('SLA  %s,1' % r)
        elif mn == 'LSR': out += ['SRL  %s,9' % r, 'SWPB %s' % r]
        elif mn == 'ROL':
            a = self.local(); out += ['JNC  %s' % a, 'ORI  %s,>0080' % r, ('LABEL', a), 'SLA  %s,1' % r]
        elif mn == 'ROR':
            a = self.local(); b = self.local()
            out += ['JNC  %s' % a, 'SRL  %s,9' % r, 'ORI  %s,>0080' % r, 'JMP  %s' % b, ('LABEL', a), 'SRL  %s,9' % r,
                    ('LABEL', b), 'SWPB %s' % r]
            if not S: out.append('MOVB R1,R1')
        if S: out.append('MOVB %s,%s' % (r, S))

    def fusable(self, pc):
        """A compare whose flags are only read by the conditional branches right after it:
        returns how many branches follow in compare form (CB/CI + JL/JHE), or 0."""
        p = pc + self.code[pc]; k = 0
        while p in self.code and self.ins(p)[0] in BRUSE and p not in self.labels:
            mn = self.ins(p)[0]
            if mn in ('BMI', 'BPL', 'BVC', 'BVS'): return 0
            tgt = p + 2 + ((self.m[p + 1] ^ 128) - 128)
            if tgt not in self.before or self.before[tgt] & {'C', 'N'}: return 0
            k += 1; p += 2
        if k == 0 or p not in self.code or self.before[p] & {'C', 'N'}: return 0
        return k

    # ---- indirect jump tables ----------------------------------------------------
    def ijmp_items(self):
        out = []
        for vec, tg in sorted(self.ijmp.items()):
            out.append((vec, sorted(set(tg))))
        return out
