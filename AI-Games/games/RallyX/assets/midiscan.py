"""Minimal MIDI reader -- no external libraries. Dumps structure so the
arrangement can be understood before anything is generated from it."""
import struct, sys

path = sys.argv[1]
d = open(path, 'rb').read()

def rd_vlq(i):
    v = 0
    while True:
        b = d[i]; i += 1
        v = (v << 7) | (b & 0x7F)
        if not (b & 0x80):
            return v, i

assert d[:4] == b'MThd', "not a MIDI file"
hlen, fmt, ntrk, div = struct.unpack('>IHHH', d[4:14])
print("format %d, %d tracks, division %d ticks/quarter" % (fmt, ntrk, div))

i = 8 + hlen
tracks = []
tempos = []
for t in range(ntrk):
    assert d[i:i+4] == b'MTrk', "bad track %d" % t
    tlen = struct.unpack('>I', d[i+4:i+8])[0]
    end = i + 8 + tlen
    j = i + 8
    tick = 0
    status = 0
    notes = []          # (tick_on, tick_off, pitch, velocity, channel)
    live = {}
    name = ""
    while j < end:
        dt, j = rd_vlq(j)
        tick += dt
        b = d[j]
        if b & 0x80:
            status = b; j += 1
        ev = status & 0xF0
        ch = status & 0x0F
        if status == 0xFF:
            mt = d[j]; j += 1
            ln, j = rd_vlq(j)
            data = d[j:j+ln]; j += ln
            if mt == 0x51:
                tempos.append((tick, struct.unpack('>I', b'\0' + data)[0]))
            elif mt == 0x03:
                name = data.decode('latin-1', 'replace')
        elif status in (0xF0, 0xF7):
            ln, j = rd_vlq(j)
            j += ln
        elif ev in (0x80, 0x90):
            p = d[j]; v = d[j+1]; j += 2
            if ev == 0x90 and v > 0:
                live.setdefault((ch, p), []).append((tick, v))
            else:
                k = (ch, p)
                if live.get(k):
                    on, vel = live[k].pop(0)
                    notes.append((on, tick, p, vel, ch))
        elif ev in (0xA0, 0xB0, 0xE0):
            j += 2
        elif ev in (0xC0, 0xD0):
            j += 1
        else:
            j += 1
    tracks.append((name, notes))
    i = end

for us in tempos[:4]:
    print("tempo at tick %d: %d us/quarter = %.1f BPM" % (us[0], us[1], 60000000.0 / us[1]))
print()
for t, (name, notes) in enumerate(tracks):
    if not notes:
        print("track %d %-20s (no notes)" % (t, name)); continue
    ps = [n[2] for n in notes]
    last = max(n[1] for n in notes)
    chans = sorted({n[4] for n in notes})
    print("track %d %-20s %4d notes  pitch %3d..%-3d  ch %s  ends tick %d (%.1f bars)"
          % (t, name, len(notes), min(ps), max(ps), chans, last, last / float(div * 4)))
