"""The NES in-round tune plays under the effects instead of stopping for them.

nes_mus_simple (nes_apu.asm) is EXECUTED here, frame by frame, against the
shim the effects write through, and the source is checked for the orderings
the vblank-time ownership test depends on. Each property has a mutation that
restores the defect and must be rejected.
"""
from pathlib import Path
import re
import unittest

from looptiming_test import platform_source
from nesapu_test import Apu, SOURCE
import musicown

HERE = Path(__file__).parent
BASIC = HERE.parent.joinpath('src/KEYSTONE.bas').read_text()
PROLOGUE = Path('/cygdrive/c/Users/Howie/github.git/unhuman/CVBasic/cvbasic_nes_prologue.asm')

P1 = range(0x4000, 0x4004)
P2 = range(0x4004, 0x4008)
NAMES = {'cvb_SHT': 0x3B6, 'cvb_SPZ': 0x3D1,
         'audio_freq1': 0x42, 'audio_freq2': 0x44, 'audio_vol1': 0x48,
         'audio_vol2': 0x49, 'music_counter_1': 0x39, 'music_counter_2': 0x3C}


class Nes(Apu):
    """nesapu_test's interpreter plus the few opcodes the player adds."""

    def __init__(self, source=SOURCE):
        super().__init__(source)
        self.names.update(NAMES)

    def run(self, entry, a=0, x=0, y=0):
        if entry != 'nes_mus_simple':
            return super().run(entry, a, x, y)
        r = {'A': a, 'Y': y}
        carry, zero, pc = 0, False, self.labels[entry]
        def address(arg):
            name, *offset = arg.split('+')
            return self.names[name] + (int(offset[0]) if offset else 0)
        def value(arg):
            if arg.startswith('#'):
                return int(arg[1:].replace('$', '0x'), 0)
            return self.mem.get(address(arg), 0)
        for _ in range(100):
            op, *args = self.code[pc]
            arg = args[0] if args else ''
            pc += 1
            if op == 'RTS':
                return
            if op in ('LDA', 'ORA', 'AND'):
                v = value(arg)
                r['A'] = v if op == 'LDA' else (r['A'] | v if op == 'ORA' else r['A'] & v)
                zero = r['A'] == 0
            elif op == 'STA':
                addr = address(arg)
                self.mem[addr] = r['A']
                if addr >= 0x4000:
                    self.writes.append((addr, r['A']))
            elif op == 'CMP':
                zero = r['A'] == value(arg)
            elif op in ('BEQ', 'BNE'):
                if zero == (op == 'BEQ'):
                    pc = self.labels[arg]
            elif op == 'LSR' and arg == 'A':
                carry = r['A'] & 1
                r['A'] >>= 1
            elif op == 'ROR' and arg == 'A':
                r['A'], carry = (r['A'] >> 1) | (carry << 7), r['A'] & 1
            elif op == 'TAY':
                r['Y'] = r['A']
            elif op == 'TYA':
                r['A'] = r['Y']
                zero = r['A'] == 0
            else:
                raise AssertionError('Unmodelled opcode ' + op)
        raise AssertionError('nes_mus_simple failed to return')

    def tune(self, melody, bass, counter, vol=0xd9, bass_vol=0x99):
        """Set the music player's state for one frame."""
        self.mem[0x42], self.mem[0x43] = melody & 255, melody >> 8
        self.mem[0x44], self.mem[0x45] = bass & 255, bass >> 8
        self.mem[0x48], self.mem[0x49] = vol, bass_vol
        self.mem[0x39] = self.mem[0x3C] = counter

    def frame(self, sht=0, spz=0):
        self.mem[0x3B6], self.mem[0x3D1] = sht, spz
        start = len(self.writes)
        self.run('nes_mus_simple')
        return self.writes[start:]

    def pulse2(self):
        return self.mem.get(0x4006, 0) | (self.mem.get(0x4007, 0) & 7) << 8


class NesPlayer(unittest.TestCase):
    def test_tune_alone_melody_on_pulse_2_bass_on_triangle(self):
        nes = Nes()
        nes.tune(0x1AB, 0x2CD, 1)
        writes = dict(nes.frame())
        self.assertEqual(nes.pulse2(), 0x1AB)
        self.assertEqual(writes[0x4007] & 0xF8, 0x08)
        self.assertEqual(writes[0x4004], 0xd9)
        self.assertEqual(writes[0x4008], 0xff)
        self.assertEqual(writes[0x4015], 0x0f)        # the title may have left it off
        self.assertEqual(writes[0x400a] | (writes[0x400b] & 7) << 8, 0x2CD >> 1)
        nes.tune(0x1AB, 0x2CD, 2)                      # not a note's first frame
        writes = dict(nes.frame())
        self.assertNotIn(0x4007, writes)               # no restart mid-note
        self.assertNotIn(0x400b, writes)
        nes.tune(0x1AB, 0x2CD, 3, bass_vol=0x10)        # a rest in the bass
        self.assertEqual(dict(nes.frame())[0x4008], 0x80)

    def test_pulse_1_is_never_the_tunes(self):
        nes = Nes()
        for counter in (1, 2, 1):
            nes.tune(0x123, 0x234, counter)
            self.assertFalse([a for a, _ in nes.frame() if a in P1])

    def test_an_effect_on_pulse_2_keeps_it_and_the_bass_plays_on(self):
        for owner in ({'sht': 20}, {'spz': 13}):
            nes = Nes()
            nes.tune(0x123, 0x234, 1)
            writes = nes.frame(**owner)
            self.assertFalse([a for a, _ in writes if a in P2])
            self.assertIn(0x400a, dict(writes))

    def returned_pitch(self, source):
        nes = Nes(source)
        nes.tune(0x0F0, 0x200, 1)
        nes.frame()                                     # melody note starts
        nes.tune(0x0F0, 0x200, 5)
        nes.run('sn76489_vol', a=13, x=0xb0)            # the hit, through the shim
        nes.run('sn76489_freq', a=0x2c, y=0x02, x=0xa0)
        nes.frame(sht=20)
        nes.run('sn76489_freq', a=0, y=0, x=0xa0)       # its note-off
        nes.run('sn76489_vol', a=0, x=0xb0)
        nes.tune(0x0F0, 0x200, 9)                       # mid-note, not its start
        nes.frame()
        return nes.pulse2(), nes.mem[0x4004]

    def test_returned_channel_comes_back_in_tune(self):
        self.assertEqual(self.returned_pitch(SOURCE), (0x0F0, 0xd9))

    def test_mutation_without_resync_comes_back_out_of_tune(self):
        broken = SOURCE.replace('\tSTA nes_p2sync\t\t; A is nonzero', '\tSTA temp\t\t;')
        self.assertNotEqual(broken, SOURCE)
        self.assertNotEqual(self.returned_pitch(broken)[0], 0x0F0)

    def test_mutation_without_owner_test_overwrites_the_effect(self):
        broken = SOURCE.replace('\tBNE nes_mus_bass\t; an effect has pulse 2', '\tAND #0\t;')
        self.assertNotEqual(broken, SOURCE)
        nes = Nes(broken)
        nes.tune(0x123, 0x234, 1)
        self.assertTrue([a for a, _ in nes.frame(sht=20) if a in P2])


class Hook(unittest.TestCase):
    def test_patch_jumps_simple_mode_and_refuses_a_changed_runtime(self):
        out = musicown.patch(musicown.HEAD + '\tLDA audio_vol2\n\nnes_mus_simple:\n')
        self.assertIn('JMP nes_mus_simple', out)
        self.assertNotIn('BCC .9', out)
        with self.assertRaises(ValueError):
            musicown.patch(musicown.HEAD.replace('BCC .9', 'BCC .8') + 'nes_mus_simple:\n')
        with self.assertRaises(ValueError):
            musicown.patch(musicown.HEAD)

    def test_hook_matches_the_runtime_it_patches(self):
        if not PROLOGUE.exists():
            self.skipTest('CVBasic checkout not at ' + str(PROLOGUE))
        self.assertEqual(PROLOGUE.read_text().count(musicown.HEAD), 1)


def sfx_routines(code):
    return code.split('\nsfx_tick:', 1)[1].split('\nlife_finish:', 1)[0]


def unowned_pulse2_writes(code):
    """SOUND 1 statements reached with neither sht nor spz set or tested."""
    bad, stack = [], []
    for line in sfx_routines(code).splitlines():
        if re.match(r'IF .* THEN$', line):
            stack.append([line, set()])
        elif line == 'END IF':
            stack.pop()
        else:
            m = re.match(r'(\w+) = ', line)
            if m and stack:
                stack[-1][1].add(m[1])
            if 'SOUND 1' in line:
                said = ' '.join(c for c, _ in stack) + line
                owned = re.search(r'\b(sht|spz)\b', said) or any(
                    {'sht', 'spz'} & set_ for _, set_ in stack)
                if not owned:
                    bad.append(line)
    return bad


class Source(unittest.TestCase):
    NES = platform_source(BASIC, 'NES')

    def test_nes_never_ducks_the_tune(self):
        body = self.NES.split('\nmusic_duck:', 1)[1].split('\nRETURN', 1)[0]
        self.assertNotIn('PLAY NONE', body)
        self.assertIn('PLAY SIMPLE NO DRUMS', body)

    def test_every_pulse_2_effect_owns_it_before_its_first_note(self):
        self.assertEqual(unowned_pulse2_writes(self.NES), [])

    def test_mutation_note_before_owner_is_rejected(self):
        old = 'sht = HITSND\nshf = 1\nSOUND 1,168,13'
        self.assertIn(old, self.NES)
        broken = self.NES.replace(old, 'SOUND 1,168,13\nsht = HITSND\nshf = 1')
        self.assertEqual(unowned_pulse2_writes(broken), ['SOUND 1,168,13'])

    def test_triangle_is_the_tunes_alone_in_a_round(self):
        self.assertNotRegex(sfx_routines(self.NES), r'SOUND 2\b')
        stop = self.NES.split('\nmusic_stop:', 1)[1].split('\nRETURN', 1)[0]
        self.assertIn('SOUND 2,,0', stop)

    def test_simple_mode_never_has_drums(self):
        # nes_mus_simple has no drum path, so SIMPLE WITH drums would lose them.
        for m in re.finditer(r'PLAY SIMPLE[^\n:]*', self.NES):
            self.assertEqual(m[0].strip(), 'PLAY SIMPLE NO DRUMS')

    def test_nes_buttons(self):
        title = self.NES.split('\ntitle_wait:', 1)[1].split('\ntitle_setup:', 1)[0]
        self.assertIn('IF cont1.key = 10 THEN', title)       # SELECT: music
        self.assertNotRegex(title, r'IF cont1\.button2 THEN\nIF nai')
        self.assertIn('IF cont1.key = 11 THEN RETURN', title)  # START
        self.assertIn('IF cont1.button2 THEN RETURN', title)   # A
        self.assertIn('IF cont1.button THEN RETURN', title)    # B
        read = self.NES.split('\nread_input:', 1)[1].split('\nRETURN', 1)[0]
        self.assertIn('IF cont1.button THEN inb = 1', read)
        self.assertIn('IF cont1.button2 THEN inb = 1', read)
        rel = self.NES.split('\nbtn_rel:', 1)[1].split('\nbtn_go:', 1)[0]
        self.assertIn('IF cont1.button2 THEN GOTO btn_rel', rel)
        for platform in ('TI994A', 'COLECOVISION'):
            code = platform_source(BASIC, platform)
            self.assertNotIn('cont1.button2', code)


if __name__ == '__main__':
    unittest.main()
