"""Static recursive-descent tracer for 6502 images (shared by the survey tools and the translator)."""
import collections
from m6502 import OPS, LEN, STORES, RMW


class Trace:
    def __init__(self, mem, lo=0x0200, hi=0xC000):
        self.m = mem; self.lo = lo; self.hi = hi
        self.code = {}                 # pc -> length
        self.labels = set()            # branch/jump/call targets and entries
        self.subs = set()              # JSR targets
        self.refs = collections.defaultdict(list)   # address -> [(pc, 'r'|'w'|'rw', mode)]
        self.ind = []                  # (pc, vector) for JMP (ind)
        self.bad = []                  # traced into an undefined opcode
        self.out = collections.Counter()            # control transfers that leave [lo, hi)

    def run(self, seeds, stops=()):
        m = self.m; todo = list(seeds); self.labels.update(seeds)
        while todo:
            pc = todo.pop()
            while True:
                if not self.lo <= pc < self.hi: self.out[pc] += 1; break
                if pc in self.code or pc in stops: break
                op = m[pc]
                if op not in OPS: self.bad.append(pc); break
                mn, am = OPS[op]; n = LEN[am]; self.code[pc] = n
                v = m[pc + 1] | (m[pc + 2] << 8 if n == 3 else 0)
                if am in ('abs', 'abx', 'aby', 'zp', 'zpx', 'zpy', 'izx', 'izy') and mn not in ('JMP', 'JSR'):
                    self.refs[v].append((pc, 'w' if mn in STORES else 'rw' if mn in RMW else 'r', am))
                if mn == 'JSR': todo.append(v); self.labels.add(v); self.subs.add(v)
                elif mn == 'JMP':
                    if am == 'ind': self.ind.append((pc, v))
                    else: todo.append(v); self.labels.add(v)
                    break
                elif am == 'rel':
                    d = m[pc + 1]; t = (pc + 2 + (d - 256 if d > 127 else d)) & 0xffff
                    todo.append(t); self.labels.add(t)
                elif mn in ('RTS', 'RTI', 'BRK'): break
                pc += n
        return self

    def code_bytes(self):
        return set(a + k for a, n in self.code.items() for k in range(n))
