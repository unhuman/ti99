"""Execute the NES sound shim and check hardware note-on/note-off writes."""
from pathlib import Path
import re
import unittest

SOURCE = Path(__file__).with_name('nes_apu.asm').read_text()

class Apu:
    def __init__(self, source=SOURCE):
        source = re.sub(r'(\w+:)\s*\n\s*(DB )', r'\1 \2', source)
        self.mem = {0x4015: 15}
        self.length = {0x4003:0, 0x4007:0, 0x400b:0, 0x400f:0}
        self.writes = []
        self.linear = 0
        self.reload = False
        self.names = {'temp':0x10, 'temp2':0x12}
        self.labels, self.code = {}, []
        for line in source.splitlines():
            line = line.split(';')[0].strip()
            if not line:
                continue
            if ':' in line:
                name, line = line.split(':', 1)
                line = line.strip()
                if line.startswith('EQU '):
                    self.names[name] = int(line.split()[1].replace('$','0x'), 0)
                    continue
                if line.startswith('DB '):
                    self.names[name] = 0x100
                    for i, v in enumerate(line[3:].split(',')):
                        self.mem[0x100+i] = int(v.replace('$','0x'), 0)
                    continue
                self.labels[name] = len(self.code)
            if line:
                self.code.append(line.split(maxsplit=1))

    def quarter_frame(self):
        control = self.mem.get(0x4008, 0)
        if self.reload:
            self.linear = control & 127
        elif self.linear:
            self.linear -= 1
        if not control & 128:
            self.reload = False

    def run(self, entry, a=0, x=0, y=0):
        r = {'A':a, 'X':x, 'Y':y}
        carry, zero, pc = 0, False, self.labels[entry]
        def address(arg):
            base, *index = arg.split(',')
            name, *offset = base.split('+')
            return self.names[name] + (int(offset[0]) if offset else 0) + (r[index[0]] if index else 0)
        def value(arg):
            return int(arg[1:].replace('$','0x'),0) if arg.startswith('#') else self.mem.get(address(arg),0)
        def write(addr, val):
            self.mem[addr] = val
            if addr >= 0x4000:
                self.writes.append((addr,val))
            if addr == 0x400b:
                self.reload = True
            if addr in self.length:
                channel = {0x4003:0, 0x4007:1, 0x400b:2, 0x400f:3}[addr]
                if self.mem.get(0x4015,0) & (1 << channel):
                    self.length[addr] = 254 if val & 0xf8 == 8 else 10
        for _ in range(150):
            op, *args = self.code[pc]; arg = args[0] if args else ''; pc += 1
            if op == 'RTS':
                return
            if op in ('LDA','LDX','LDY'):
                r[op[-1]] = value(arg); zero = r[op[-1]] == 0
            elif op in ('STA','STY'):
                write(address(arg),r[op[-1]])
            elif op in ('TXA','TAY'):
                r[op[2]] = r[op[1]]; zero = r[op[2]] == 0
            elif op == 'AND':
                r['A'] &= value(arg); zero = r['A'] == 0
            elif op == 'ORA':
                r['A'] |= value(arg); zero = r['A'] == 0
            elif op == 'CMP':
                zero = r['A'] == value(arg)
            elif op == 'SEC':
                carry = 1
            elif op == 'SBC':
                n = r['A'] - value(arg) - (1-carry); carry = int(n >= 0)
                r['A'] = n & 255; zero = r['A'] == 0
            elif op in ('LSR','ROR'):
                addr = address(arg); n = self.mem.get(addr,0)
                write(addr,(n >> 1) | ((carry << 7) if op == 'ROR' else 0)); carry = n & 1
            elif op == 'JMP':
                pc = self.labels[arg]
            elif op in ('BEQ','BNE'):
                if zero == (op == 'BEQ'): pc = self.labels[arg]
            else:
                raise AssertionError('Unmodelled opcode '+op)
        raise AssertionError('Sound routine failed to return')

class SoundTest(unittest.TestCase):
    def test_triangle_restarts_across_frame_clock(self):
        # A quarter-frame may land between pitch and volume writes.
        # Reproduce the old mute as a negative control using the same sequence.
        for old_mute in (False, True):
            source = SOURCE
            source = source.replace('LDA #$80\n\tSTA APU_TRICTL',
                                    'LDA #$00\n\tSTA APU_TRICTL') if old_mute else source
            apu = Apu(source)
            apu.run('sn76489_vol', a=0, x=0xd0)
            for divisor in (108, 108, 214, 170, 143, 300):
                apu.run('sn76489_freq', a=divisor&255, y=divisor>>8, x=0xc0)
                apu.quarter_frame()
                apu.run('sn76489_vol', a=12, x=0xd0)
                apu.quarter_frame()
                self.assertEqual(apu.linear > 0, not old_mute)
                apu.run('sn76489_freq', a=0, x=0xc0)
                apu.run('sn76489_vol', a=0, x=0xd0)
                for _ in range(8):
                    apu.quarter_frame()
                self.assertEqual(apu.linear, 0)

    def test_nes_notes_set_volume_before_pitch(self):
        source = Path(__file__).parents[1].joinpath('src/KEYSTONE.bas').read_text()
        for channel, pitch, volume in [('1', '270', '12'), ('1', 'pzd', 'pzv')]:
            pattern = r'SOUND ' + channel + ',,' + volume + r'\s+SOUND ' + channel + ',' + pitch + r'\s+(?:END IF\s+)?#else'
            self.assertRegex(source, pattern)

    def test_jump_and_prize_channels_are_independent(self):
        apu = Apu()
        for channel, divisor in ((0, 270), (1, 214), (0, 595), (1, 170), (1, 143)):
            before = dict(apu.mem)
            start = len(apu.writes)
            apu.run('sn76489_vol', a=12, x=0x90+channel*32)
            apu.run('sn76489_freq', a=divisor&255, y=divisor>>8, x=0x80+channel*32)
            self.assertTrue(all(0x4000+4*channel <= addr <= 0x4003+4*channel
                                for addr, value in apu.writes[start:]))
            other = 0x4004 if channel == 0 else 0x4000
            for addr in range(other, other+4):
                self.assertEqual(apu.mem.get(addr), before.get(addr))
        jump = {addr: apu.mem.get(addr) for addr in range(0x4000, 0x4004)}
        apu.run('sn76489_vol', a=0, x=0xb0)
        self.assertEqual(jump, {addr: apu.mem.get(addr) for addr in jump})
        source = Path(__file__).parents[1].joinpath('src/KEYSTONE.bas').read_text()
        self.assertIn('IF sht > 0 THEN spz = 0', source)
        self.assertIn('IF spz = 0 THEN SOUND 1,0,0', source)

    def test_redraw_mutes_jump_and_footstep_before_wait(self):
        source = Path(__file__).parents[1].joinpath('src/KEYSTONE.bas').read_text()
        body = source.split('draw_screen:', 1)[1].split('\n\tWAIT', 1)[0]
        self.assertIn('SOUND 0,,0', body)
        self.assertNotRegex(body, r'(?m)^\s*sw[tf]\s*=')
        self.assertIn('SOUND 3,0,0', body)
        self.assertIn('sot = 0', body)

    def test_footstep_noise_starts_and_stops(self):
        for control in range(8):
            apu = Apu()
            apu.run('sn76489_control',a=control)
            apu.run('sn76489_vol',a=9,x=0xf0)
            self.assertGreater(apu.length[0x400f],0)
            self.assertEqual(apu.mem[0x400c],0x39)
            self.assertEqual(apu.mem[0x400e], [4,6,8,10][control&3] | (0 if control&4 else 128))
            apu.run('sn76489_vol',a=0,x=0xf0)
            self.assertEqual(apu.mem[0x400c]&15,0)

    def test_old_missing_trigger_is_silent(self):
        apu = Apu(SOURCE.replace('STA APU_NSLEN','STA temp'))
        apu.run('sn76489_control',a=4)
        apu.run('sn76489_vol',a=9,x=0xf0)
        self.assertEqual(apu.length[0x400f],0)

    def test_tones_keep_pitch_volume_and_note_off(self):
        for channel, divisor in ((0,269),(1,168),(2,214),(2,170),(2,143)):
            apu = Apu()
            apu.run('sn76489_vol',a=12,x=0x90+channel*32)
            apu.run('sn76489_freq',a=divisor&255,y=divisor>>8,x=0x80+channel*32)
            base = 0x4000+channel*4
            self.assertGreater(apu.length[base+3],0)
            control_pos = max(i for i, (addr, _) in enumerate(apu.writes) if addr == base)
            trigger_pos = max(i for i, (addr, _) in enumerate(apu.writes) if addr == base+3)
            self.assertGreater(trigger_pos, control_pos)
            self.assertEqual(apu.mem[base+3]&0xf8, 8)
            actual = apu.mem[base+2] | (apu.mem[base+3]&7)*256
            self.assertEqual(actual,(divisor-1)//(2 if channel==2 else 1))
            self.assertEqual(apu.mem[base],0xff if channel==2 else 0xbc)
            apu.run('sn76489_vol',a=0,x=0x90+channel*32)
            self.assertEqual(apu.mem[base],0x80 if channel==2 else 0xb0)

if __name__ == '__main__':
    unittest.main()
