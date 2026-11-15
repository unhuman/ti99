"""Turn translator items into xas99 text, assemble, and read the result back (A82TI99)."""
import os, re, subprocess, sys, collections
import tms

XDT99 = os.environ.get('XDT99_DIR', '/cygdrive/c/Users/Howie/github.git/endlos99/xdt99')
JINV = {'JEQ': 'JNE', 'JNE': 'JEQ', 'JOC': 'JNC', 'JNC': 'JOC', 'JL': 'JHE', 'JHE': 'JL', 'JH': 'JLE', 'JLE': 'JH'}


def item_size(it, form):
    """Bytes an item assembles to.  form (branches, jumps, calls): 0 short/near, 1 long, 2 far."""
    if isinstance(it, str): return 0 if it.startswith('*') else tms.size(it)
    k = it[0]
    if k == 'LABEL': return 0
    if k == 'JMP': return (2, 4, 8)[form]
    if k == 'CALL': return 8 if form == 2 else 4
    if k == 'RET': return 4
    if k == 'BR':
        tj, fj = it[1], it[2]
        if form == 0: return 2 * len(tj)
        return 2 * len(fj) + (4 if form == 1 else 8)
    raise ValueError(it)


def item_text(it, form, sel=None):
    """xas99 lines for an item.  sel = bank select address for far forms."""
    if isinstance(it, str):
        return [it] if it.startswith('*') else ['       ' + it]
    k = it[0]
    if k == 'LABEL': return ['%s' % it[1]]
    if k == 'JMP':
        if form == 0: return ['       JMP  %s' % it[1]]
        if form == 1: return ['       B    @%s' % it[1]]
        return ['       BL   @FARJ', '       DATA %s,>%04X' % (it[1], sel)]
    if k == 'CALL':
        if form == 2: return ['       BL   @FARC', '       DATA L%04X,>%04X' % (it[1], sel)]
        return ['       BL   @%s' % (it[2] if len(it) > 2 else 'J%04X' % it[1])]
    if k == 'RET':
        return ['       B    @RETF' if it[1] else '       B    @RETN']       # RETF keeps the status register
    if k == 'BR':
        tj, fj, tgt = it[1], it[2], it[3]
        if form == 0: return ['       %-4s %s' % (j, tgt) for j in tj]
        tail = 4 if form == 1 else 8
        out = ['       %-4s $+%d' % (j, 2 * (len(fj) - i) + tail) for i, j in enumerate(fj)]
        return out + (['       B    @%s' % tgt] if form == 1 else ['       BL   @FARJ', '       DATA %s,>%04X' % (tgt, sel)])
    raise ValueError(it)


def assemble(src_path, out_dir=None):
    """Assemble with xas99; return ({bank or None: {addr: byte}}, {symbol: value})."""
    out_dir = out_dir or os.path.dirname(src_path)
    base = os.path.splitext(os.path.basename(src_path))[0]
    lst = os.path.join(out_dir, base + '.lst'); equ = os.path.join(out_dir, base + '.equ')
    cmd = [sys.executable, os.path.join(XDT99, 'xas99.py'), '-R', '-b', '-q', os.path.basename(src_path),
           '-L', lst, '-E', equ, '-o', os.path.join(out_dir, base + '.bin')]
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=os.path.dirname(src_path))
    if r.returncode != 0 or 'rror' in r.stdout + r.stderr:
        print(r.stdout[-6000:]); print(r.stderr[-6000:]); raise SystemExit('xas99 failed on ' + src_path)
    return parse_listing(lst), parse_equ(equ)


LST_RE = re.compile(r'^(?:\d{4,6} | {5})([0-9A-F]{4}) ([0-9A-F]{4}|[0-9A-F]{2}|  [0-9A-F]{2})(?:\s|$)')
BANK_RE = re.compile(r'^\d{4,6}\s+BANK\s+([^\s,]+)', re.I)


def parse_listing(path):
    mem = collections.defaultdict(dict); bank = None
    for line in open(path, encoding='latin-1'):
        line = line.rstrip('\n')
        m = BANK_RE.match(line)
        if m:
            arg = m.group(1); bank = 'ALL' if arg.upper() == 'ALL' else int(arg); continue
        m = LST_RE.match(line)
        if not m: continue
        addr = int(m.group(1), 16); data = m.group(2).strip()
        b = bank if 0x6000 <= addr < 0x8000 else None
        if len(data) == 4: mem[b][addr] = int(data[:2], 16); mem[b][addr + 1] = int(data[2:], 16)
        else: mem[b][addr] = int(data, 16)
    return mem


def parse_equ(path):
    sym = {}; name = None
    for line in open(path, encoding='latin-1'):
        m = re.match(r'^([A-Za-z_$][\w$]*):\s*$', line)
        if m: name = m.group(1).upper(); continue
        m = re.match(r'^\s+equ\s+>([0-9A-Fa-f]+)', line, re.I)
        if m and name: sym[name] = int(m.group(1), 16); name = None
    return sym
