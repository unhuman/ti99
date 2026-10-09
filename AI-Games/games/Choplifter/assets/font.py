"""Read the editable 8x8 font sheet as CVBasic glyph bytes (ASCII 32-127)."""
from pathlib import Path
import struct
import zlib

FONT_PNG = Path(__file__).with_name('font.png')
# Small display corrections to the supplied sheet. The title's brackets are
# blank in the PNG. Place each bracket one pixel clear of its content and keep
# both at the font's seven-pixel height. The period sits at the baseline on the
# left edge of its cell, leaving one blank pixel after a seven-pixel letter.
GLYPH_TOUCHUPS = {
    46: bytes((0, 0, 0, 0, 0, 0, 0xC0, 0xC0)),
    91: bytes((0x1E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x1E, 0)),
    93: bytes((0x78, 0x18, 0x18, 0x18, 0x18, 0x18, 0x78, 0)),
}


def glyphs(path=FONT_PNG):
    data = Path(path).read_bytes()
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('Font must be a PNG')
    pos = 8
    pixels = b''
    while pos < len(data):
        size = struct.unpack_from('>I', data, pos)[0]
        kind = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+size]
        crc = struct.unpack_from('>I', data, pos+8+size)[0]
        if zlib.crc32(kind+chunk) != crc:
            raise ValueError(f'Bad PNG {kind!r} checksum')
        pos += 12+size
        if kind == b'IHDR':
            if struct.unpack('>IIBBBBB', chunk) != (64, 256, 8, 6, 0, 0, 0):
                raise ValueError('Font sheet must be a 64x256, RGBA8 PNG')
        elif kind == b'IDAT':
            pixels += chunk
        elif kind == b'IEND':
            break
    raw = zlib.decompress(pixels)
    stride = 64*4
    rows = []
    previous = bytearray(stride)
    offset = 0
    for y in range(256):
        mode = raw[offset]
        row = bytearray(raw[offset+1:offset+1+stride])
        offset += stride+1
        if len(row) != stride or mode > 4:
            raise ValueError('Invalid font PNG row')
        for i in range(stride):
            left = row[i-4] if i >= 4 else 0
            above = previous[i]
            upper_left = previous[i-4] if i >= 4 else 0
            if mode == 1:
                row[i] = (row[i]+left)&255
            elif mode == 2:
                row[i] = (row[i]+above)&255
            elif mode == 3:
                row[i] = (row[i]+((left+above)//2))&255
            elif mode == 4:
                predictor = left+above-upper_left
                distances = (abs(predictor-left),abs(predictor-above),abs(predictor-upper_left))
                preferred = (left,above,upper_left)[distances.index(min(distances))]
                row[i] = (row[i]+preferred)&255
        previous = row
        rows.append(row)
    if offset != len(raw):
        raise ValueError('Unexpected font PNG data after final row')
    result = []
    for code in range(32,128):
        cell_x = (code%8)*8
        cell_y = (code//8)*8
        for y in range(cell_y,cell_y+8):
            bits = 0
            for x in range(cell_x,cell_x+8):
                pixel = rows[y][x*4:x*4+4]
                if pixel == b'\x00\x00\x00\xff':
                    bits |= 128>>(x-cell_x)
                elif pixel != b'\xff\xff\xff\xff':
                    raise ValueError(f'Font pixel ({x},{y}) must be opaque black or white')
            result.append(bits)
    bitmap = bytearray(result)
    for code, adjusted in GLYPH_TOUCHUPS.items():
        start = (code-32)*8
        bitmap[start:start+8] = adjusted
    return bytes(bitmap)
