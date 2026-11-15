"""TMS9900 instruction facts used by the translator: size and status bits.

Lines are plain xas99 text: 'MOVB R1,@>A192' etc.  size(line) is exact for
everything the translator emits; status(line) is the set of status bits
the instruction can change (L A E C O P = L>, A>, EQ, C, OV, OP).
"""
import re

TWO_OP = {'A', 'AB', 'C', 'CB', 'S', 'SB', 'SOC', 'SOCB', 'SZC', 'SZCB', 'MOV', 'MOVB'}
REG_SRC = {'COC', 'CZC', 'XOR', 'MPY', 'DIV', 'LDCR', 'STCR'}      # general src, register dst
ONE_OP = {'B', 'BL', 'BLWP', 'CLR', 'SETO', 'INV', 'NEG', 'ABS', 'SWPB', 'INC', 'INCT', 'DEC', 'DECT', 'X'}
IMM = {'LI', 'AI', 'ANDI', 'ORI', 'CI'}
IMM_ONLY = {'LWPI', 'LIMI'}
REG_ONLY = {'STST', 'STWP'}
SHIFT = {'SLA', 'SRA', 'SRC', 'SRL'}
JUMP = {'JMP', 'JEQ', 'JNE', 'JOC', 'JNC', 'JL', 'JLE', 'JH', 'JHE', 'JLT', 'JGT', 'JNO', 'JOP'}
CRU = {'SBO', 'SBZ', 'TB'}
NOARG = {'RTWP', 'IDLE', 'RSET', 'CKON', 'CKOF', 'LREX', 'NOP'}
DIRECTIVES = {'DATA', 'BYTE', 'TEXT', 'BSS', 'EVEN', 'AORG', 'EQU', 'END', 'DEF', 'REF', 'COPY', 'RT'}

ALLST = frozenset('LAECOP')
STATUS = {
    'A': 'LAECO', 'AB': 'LAECOP', 'S': 'LAECO', 'SB': 'LAECOP',
    'C': 'LAE', 'CB': 'LAEP', 'SOC': 'LAE', 'SOCB': 'LAEP', 'SZC': 'LAE', 'SZCB': 'LAEP',
    'MOV': 'LAE', 'MOVB': 'LAEP', 'COC': 'E', 'CZC': 'E', 'XOR': 'LAE', 'MPY': '', 'DIV': 'O',
    'LDCR': 'LAEP', 'STCR': 'LAEP',
    'B': '', 'BL': '', 'BLWP': '', 'CLR': '', 'SETO': '', 'INV': 'LAE', 'NEG': 'LAECO',
    'ABS': 'LAECO', 'SWPB': '', 'INC': 'LAECO', 'INCT': 'LAECO', 'DEC': 'LAECO', 'DECT': 'LAECO',
    'X': 'LAECOP',
    'LI': 'LAE', 'AI': 'LAECO', 'ANDI': 'LAE', 'ORI': 'LAE', 'CI': 'LAE',
    'LWPI': '', 'LIMI': '', 'STST': '', 'STWP': '',
    'SLA': 'LAECO', 'SRA': 'LAEC', 'SRC': 'LAEC', 'SRL': 'LAEC',
    'SBO': '', 'SBZ': '', 'TB': 'E', 'RTWP': 'LAECOP', 'NOP': '',
}
for _j in JUMP:
    STATUS[_j] = ''


def operand_words(op):
    op = op.strip()
    if op.startswith('@'):
        return 1
    return 0


def split_operands(s):
    out = []
    depth = 0
    cur = ''
    for ch in s:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur)
            cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return [x.strip() for x in out]


LINE_RE = re.compile(r'^(?:(?P<label>[A-Za-z_$][\w$]*)\s+)?\s*(?P<op>[A-Z]+)\s*(?P<args>[^;*]*)')


def parse(line):
    """Return (opcode, [operands]) for an instruction line without label."""
    t = line.strip()
    if not t or t.startswith('*') or t.startswith(';'):
        return None, []
    parts = t.split(None, 1)
    op = parts[0].upper()
    args = parts[1] if len(parts) > 1 else ''
    # strip trailing comment (two or more spaces then text, or ';')
    if ';' in args:
        args = args[:args.index(';')]
    args = re.split(r'\s{2,}', args.strip())[0] if args.strip() else ''
    return op, split_operands(args) if args else []


def size(line):
    op, args = parse(line)
    if op is None:
        return 0
    if op in TWO_OP or op in REG_SRC:
        return 2 + 2 * sum(operand_words(a) for a in args)
    if op in ONE_OP:
        return 2 + 2 * operand_words(args[0])
    if op in IMM:
        return 4
    if op in IMM_ONLY:
        return 4
    if op in REG_ONLY or op in SHIFT or op in JUMP or op in CRU or op in NOARG:
        return 2
    if op == 'DATA':
        return 2 * len(args)
    if op == 'BYTE':
        return len(args)
    if op == 'EVEN':
        return 0
    raise ValueError('size: ' + line)


def status(line):
    op, args = parse(line)
    if op is None or op in DIRECTIVES:
        return ''
    return STATUS[op]
