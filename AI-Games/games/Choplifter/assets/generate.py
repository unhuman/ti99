"""Original editable pixel art and ROM scenery. Run from the project root."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Sparse far-sky layer: one star per row avoids overlap during wrapped scroll.
# A sparse, irregular sky: three far stars (rows 3-6), two middle (7-11) and
# three near (12-16), on uneven rows and spread across the width.
STAR_X=[31,158,212,97,236,9,129,183]
STAR_ROW=[3,5,6,8,10,12,13,15]
# Each star owns its sky row: stars_draw clears a star's old cell without
# checking for a neighbour, which is only safe while no two stars share a row.
assert len(STAR_X)==len(STAR_ROW) and len(set(STAR_ROW))==len(STAR_ROW)
assert all(3<=row<=16 for row in STAR_ROW)
STAR_BITS=[]
for kind in range(2):
    for phase in range(8):
        rows=[0]*8
        rows[2 if kind else 5]=128>>phase
        STAR_BITS.extend(rows)
STAR_COLORS=[0xE1]*64+[0xF1]*64

def canvas(w, h):
    return [[0] * w for _ in range(h)]

def rect(a, x, y, w, h, ink=1):
    for row in range(y, y+h):
        for col in range(x, x+w):
            a[row][col] = ink

def sprite_bytes(a):
    assert len(a) == 16 and all(len(r) == 16 for r in a)
    return [sum(a[y][x+b] << (7-b) for b in range(8))
            for x in (0, 8) for y in range(16)]

def heli(front=False, beat=0):
    a = canvas(32, 16)
    rect(a, 3 if beat == 0 else 8, 1, 26 if beat == 0 else 15, 1)
    rect(a, 17, 2, 1, 3)
    if front:
        rect(a, 12, 5, 10, 7)
        rect(a, 10, 7, 14, 4)
        rect(a, 13, 6, 3, 3, 0)
        rect(a, 18, 6, 3, 3, 0)
        rect(a, 12, 12, 2, 2)
        rect(a, 20, 12, 2, 2)
        rect(a, 9, 14, 7, 1)
        rect(a, 18, 14, 7, 1)
    else:
        rect(a, 13, 5, 12, 7)
        rect(a, 11, 7, 17, 4)
        rect(a, 24, 7, 5, 3)
        rect(a, 21, 6, 4, 3, 0)
        rect(a, 14, 7, 3, 4, 0)
        rect(a, 3, 8, 10, 2)
        rect(a, 2, 8, 2, 2)
        if beat == 0:
            rect(a,0,6,7,1);rect(a,3,3,1,7)
        else:
            for n in range(5):
                a[4+n][1+n]=1
                a[4+n][5-n]=1
        rect(a, 15, 12, 1, 2)
        rect(a, 24, 12, 1, 2)
        rect(a, 11, 14, 18, 1)
    return a

SPRITES = []
for facing in ('right', 'left', 'front'):
    for beat in range(2):
        a = heli(facing == 'front', beat)
        if facing == 'left':
            a = [r[::-1] for r in a]
        SPRITES.extend([([r[:16] for r in a]), ([r[16:] for r in a])])
# 12 tank, 13/14 crash flames, 15 jet, 16 drone, 17 shot, 18/19 blast.
# Boarding people use patterns 47..58; the two former runner slots are free.
a = canvas(16, 16)
rect(a, 1, 7, 14, 5); rect(a, 4, 4, 8, 4); rect(a, 0, 4, 8, 1)
for x in (3, 7, 11): rect(a, x, 10, 2, 1, 0)
SPRITES.append(a)
CRASH_FLAMES=[
    [0x0100,0x0180,0x1180,0x1984,0x198c,0x3bdc,0x3ffc,0x7ffc,
     0x7ffe,0xf7fe,0xeffe,0xdfbc,0xfffc,0x7ff8,0x3ff0,0],
    [0x0040,0x0840,0x0860,0x1860,0x3864,0x79ec,0x7dfc,0xfffc,
     0xfefe,0xfdfe,0xfbde,0xef7e,0x7ffc,0x7ff8,0x3ff0,0],
]
CRASH_EMBERS=[[0]*11+[0x0200,0x1220,0x3bb8,0x7ffc,0],
              [0]*11+[0x0080,0x0890,0x1dd8,0x3ff0,0]]
def fire_sprite(rows):
    return [[(bits>>(15-x))&1 for x in range(16)] for bits in rows]
SPRITES.extend(fire_sprite(rows) for rows in CRASH_FLAMES)
a = canvas(16, 16)
rect(a, 0, 7, 16, 3); rect(a, 6, 3, 3, 10); rect(a, 13, 4, 2, 7)
rect(a, 3, 6, 9, 1); SPRITES.append(a)
a = canvas(16, 16)
rect(a, 4, 4, 8, 8); rect(a, 2, 6, 12, 4)
rect(a, 6, 2, 4, 12); rect(a, 6, 6, 4, 4, 0); SPRITES.append(a)
a = canvas(16, 16); rect(a, 0, 0, 3, 3); SPRITES.append(a)
for beat in range(2):
    a = canvas(16, 16)
    for y in range(16):
        for x in range(16):
            d = abs(x-7) + abs(y-7)
            if (3+beat*2 <= d <= 7+beat*3) and (x+y*3) % 4 != 0: a[y][x] = 1
    SPRITES.append(a)

def banked(a, tilt):
    """Pitch the complete 32-pixel craft; keep rotor and skids in 16 rows."""
    out=canvas(len(a[0]),16)
    for y,row in enumerate(a):
        for x,pixel in enumerate(row):
            if pixel:
                ny=2+(y*3)//4+((x-len(row)//2)*tilt)//8
                assert 0 <= ny < 16
                out[ny][x]=1
    return out

# 20..31 travel-right banks, 32..43 travel-left banks. Same facing/rotor
# offsets as the level craft. Facing and movement are intentionally independent.
for tilt in (1,-1):
    for facing in ('right','left','front'):
        for beat in range(2):
            a=heli(facing=='front',beat)
            if facing=='left': a=[r[::-1] for r in a]
            a=banked(a,tilt)
            SPRITES.extend([[r[:16] for r in a],[r[16:] for r in a]])
# 44 right-facing jet, 45/46 banking jet silhouettes.
SPRITES.append([r[::-1] for r in SPRITES[15]])
SPRITES.append(banked(SPRITES[15],1))
SPRITES.append(banked(SPRITES[44],-1))
JET_ARC = [0,3,6,9,12,14,15,16,16,15,14,12,9,6,3,0]

def person(kind, walking, pose):
    """Three silhouettes, four staggered poses; waiting people wave, not march."""
    a=canvas(8,8)
    head_y=1 if kind==2 else 0
    head_w=2 if kind==1 else 3
    rect(a,3,head_y,head_w,2)
    rect(a,4,head_y+2,1,3-head_y)
    if kind==1:rect(a,3,3,3,2)
    if walking:
        arms=((2,5),(3,6),(1,5),(3,5))[pose]
        line(a,arms[0],3,arms[1],4)
        legs=(((2,7),(6,7)),((3,7),(5,6)),((3,6),(6,7)),((4,7),(5,7)))[pose]
    else:
        line(a,2,3,6,3)
        if pose in (1,2):line(a,6,3,7,1)
        legs=((3,7),(5,7))
    for x,y in legs:line(a,4,4,x,y)
    return a

# Characters 128..150. Eight explicit colour bytes per character.
TILES = [
    ([0]*8, 0x1E),                    # 128 ground at horizon
    ([0]*8, 0x1E),                    # 129 foreground ground
    ([1,3,7,15,31,63,127,255],0x41),   # 130 hill rising
    ([128,192,224,240,248,252,254,255],0x41),
    ([255]*8,0x41),                    # 132 hill fill
    ([255,129,189,165,165,189,129,255],0xE1), # 133 wall
    ([255,0,255,0,255,0,255,0],0x61),   # 134 roof
    ([126,66,66,66,66,66,66,126],0xB1), # 135 closed door
    ([255,129,129,129,129,129,129,255],0xE1), # 136 open
    ([255,0,0,0,0,0,0,0],0xF1),       # 137 pad
    ([129,129,129,255,129,129,129,0],0xF1), # 138 H
    ([8,8,8,8,8,8,8,8],0xB1),        # 139 border
    ([0,126,24,63,127,24,126,0],0xF1), # 140 spare
    ([24,24,126,24,24,36,66,0],0xB1), # 141 queue
    ([0,0,0,0,0,0,0,0],0x11),        # 142 dark
    ([0,24,60,126,255,126,60,24],0xA1), # 143 beacon
    ([213,162,213,162,255,255,255,255],0xF4), # 144 flag canton/stripes (colours below)
    ([254,254,252,252,254,254,248,248],0xF1), # 145 flag fly edge
    ([128]*8,0xF1),                   # 146 flagpole
    ([128,128,255,146,146,255,128,128],0xE1), # 147 distant fence post
    ([0,0,255,18,18,255,0,0],0xE1),  # 148 distant wire
    ([192,192,255,210,204,255,192,192],0xF2), # 149 near fence post
    ([0,0,255,18,12,255,0,0],0xF2),  # 150 near wire
]
FLAG0 = TILES[16][0] + TILES[17][0]
FLAG1 = TILES[16][0] + [248,248,254,254,252,252,254,254]
# White stars on blue canton, then red/white stripes. Right tile: stripes on black.
FLAG_COLORS = [0xF4]*4 + [0x81,0xF1,0x81,0xF1] + [0x81,0xF1]*4

# Burning roof caps, with yellow tips and red roots. They use no sprites.
FIRE0 = [0x10,0x18,0x1a,0x3e,0x7f,0x7f,0xff,0xff,
         0x02,0x22,0x26,0x7e,0xfe,0xff,0xff,0xff]
FIRE1 = [0x04,0x44,0x4c,0x7c,0xfe,0xff,0xff,0xff,
         0x20,0x30,0xb0,0xf8,0xfc,0xfe,0xff,0xff]
FIRE_COLORS = [0xb1,0xb1,0xa1,0xa1,0x91,0x91,0x81,0x81]*2

# 151..158: a long, low post office, with a red roof, cream walls/windows,
# an inset door and a blue apron. The four sign glyphs share the roof line.
TILES.append(([255,255,0,255,255,255,255,255],0x6F))
for glyph in ([7,5,7,4,4],[7,5,5,5,7],[7,4,7,1,7],[7,2,2,2,2]):
    TILES.append(([255,255,0]+[v<<2 for v in glyph],0x1F))
TILES.append(([255,0,119,85,85,119,0,255],0x6F))
TILES.append(([255,129,129,129,145,129,129,255],0x1F))
TILES.append(([255]*8,0x41))
TILES.append(([0]*8,0x1E)) # 159 padding before fence patterns

def line(a,x0,y0,x1,y1):
    steps=max(abs(x1-x0),abs(y1-y0))
    for i in range(steps+1):
        x=round(x0+(x1-x0)*i/max(steps,1))
        y=round(y0+(y1-y0)*i/max(steps,1))
        a[y][x]=1

PERSON_ROWS=[]
for kind in range(3):
    for walking in (False,True):
        for pose in range(4):
            a=person(kind,walking,pose)
            PERSON_ROWS.extend(sum(pixel<<(7-x) for x,pixel in enumerate(row)) for row in a)
            if walking:
                sprite=canvas(16,16)
                for y,row in enumerate(a):sprite[y][:8]=row
                SPRITES.append(sprite)
# Yellow, white and tan clothing; terrain-compatible palettes for overlap.
PERSON_COLORS=[c for c in (0xB1,0xF1,0xA1,0x1F,0xB4,0xF4,0xA4,0xBE,0xFE,0xAE,0x1E,0x6F) for _ in range(8)]

# A 32x16 tank, with hull/tracks grounded on the same row in all three views.
# Reuse old tank slot 12; the five remaining halves fill slots 59..63.
def tank(facing):
    a=canvas(32,16)
    rect(a,3,9,26,6);rect(a,5,7,22,4)
    for x in (6,11,16,21,26):rect(a,x,12,2,2,0)
    rect(a,10,4,12,5);rect(a,12,2,8,3)
    if facing=='front':
        rect(a,6,9,3,5,0);rect(a,23,9,3,5,0)
        rect(a,15,3,3,8);rect(a,16,8,1,2,0)
    else:
        rect(a,0,4,13,2)
        if facing=='right':a=[row[::-1] for row in a]
    return a

TANKS=[tank(facing) for facing in ('left','right','front')]
SPRITES[12]=[r[:16] for r in TANKS[0]]
SPRITES.append([r[16:] for r in TANKS[0]])
for a in TANKS[1:]:
    SPRITES.extend([[r[:16] for r in a],[r[16:] for r in a]])

# 160..239: eight perspective fence stamps, each 5 columns by 2 rows.
# A fence is one connected object from the horizon into the foreground.
# Its near end projects 25% farther from the screen centre; both rails and
# every post share that projection. Tile quantisation never detaches a rail.
FENCES=[]
for shape in range(8):
    lean=(shape-4)*8
    a=canvas(40,16)
    far=max(-lean,0)
    near=far+lean
    line(a,far,1,near,10);line(a,far,3,near,13)
    for depth in range(4):
        x=round(far+lean*depth/3)
        top=depth*3
        line(a,x,top,x,top+3+depth)
    FENCES.append(a)
    for row in range(2):
        for col in range(5):
            bits=[sum(a[row*8+y][col*8+x]<<(7-x) for x in range(8)) for y in range(8)]
            TILES.append((bits,0xFE))

# Eight screens: two extra screens between the camps and the enemy fence.
# The demilitarized zone itself remains 320 pixels wide.
MAP = [[32]*256 for _ in range(5)]
MAP[4] = [128]*256
for c in range(192):
    phase = c % 18
    if phase in (0,1,2,3):
        MAP[2][c] = 130 if phase < 2 else 131
        MAP[3][c] = 132
for camp in (16,48,80,112):
    for c in range(camp-3, camp+3):
        MAP[1][c] = 134
        MAP[2][c] = 133
        MAP[3][c] = 133
    MAP[2][camp] = 135; MAP[3][camp] = 135
for c in range(245,255):
    MAP[2][c]=151
    MAP[3][c]=156
    MAP[4][c]=158
for col,ch in enumerate(range(152,156),248):MAP[2][col]=ch
MAP[3][249]=157
for c in range(238,245):MAP[4][c]=137
MAP[4][242]=138

# Transparent fence stamps must leave the landing pad beneath them intact.
# Most stamps lie on plain gray ground; one upper-row cell of the home fence
# crosses the pad. Precompose that cell instead of painting a gray rectangle.
FENCE_CODES=[160+i if any(bits) else 0 for i,(bits,_) in enumerate(TILES[32:112])]
HOME_FENCE_CODES=FENCE_CODES.copy()
PAD_FENCE_ART=[]
PAD_FENCE_COLORS=[]
for shape in range(8):
    for col in range(5):
        index=shape*10+col
        if not FENCE_CODES[index]:continue
        world_col=1888//8+col-max(4-shape,0)
        under=MAP[4][world_col]
        if under not in (137,138):continue
        base,color=TILES[under-128]
        bits,_=TILES[32+index]
        assert color>>4==15 # same white ink as the fence
        HOME_FENCE_CODES[index]=120+len(PAD_FENCE_ART)//8
        PAD_FENCE_ART.extend(a|b for a,b in zip(base,bits))
        PAD_FENCE_COLORS.extend([color]*8)
assert len(PAD_FENCE_ART)==8 # one reserved bottom-third character, code 120

# CVBasic/TMS font @.._: restore the borrowed bottom-third back buffer on menus.
MENU_FONT=[112, 136, 152, 168, 152, 128, 112, 0, 32, 80, 136, 136, 248, 136, 136, 0, 240, 136, 136, 240, 136, 136, 240, 0, 112, 136, 128, 128, 128, 136, 112, 0, 240, 136, 136, 136, 136, 136, 240, 0, 248, 128, 128, 240, 128, 128, 248, 0, 248, 128, 128, 240, 128, 128, 128, 0, 112, 136, 128, 184, 136, 136, 112, 0, 136, 136, 136, 248, 136, 136, 136, 0, 112, 32, 32, 32, 32, 32, 112, 0, 8, 8, 8, 8, 136, 136, 112, 0, 136, 144, 160, 192, 160, 144, 136, 0, 128, 128, 128, 128, 128, 128, 248, 0, 136, 216, 168, 168, 136, 136, 136, 0, 136, 200, 200, 168, 152, 152, 136, 0, 112, 136, 136, 136, 136, 136, 112, 0, 240, 136, 136, 240, 128, 128, 128, 0, 112, 136, 136, 136, 136, 168, 144, 104, 240, 136, 136, 240, 160, 144, 136, 0, 112, 136, 128, 112, 8, 136, 112, 0, 248, 32, 32, 32, 32, 32, 32, 0, 136, 136, 136, 136, 136, 136, 112, 0, 136, 136, 136, 136, 80, 80, 32, 0, 136, 136, 136, 168, 168, 216, 136, 0, 136, 136, 80, 32, 80, 136, 136, 0, 136, 136, 136, 112, 32, 32, 32, 0, 248, 8, 16, 32, 64, 128, 248, 0, 120, 96, 96, 96, 96, 96, 120, 0, 0, 128, 64, 32, 16, 8, 0, 0, 240, 48, 48, 48, 48, 48, 240, 0, 32, 80, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 248, 0]

def emit(label, data):
    assert len(data) % 2 == 0, label
    return label + ':\n' + ''.join('    DATA BYTE '+','.join(str(v) for v in data[i:i+16])+'\n' for i in range(0,len(data),16))

def generate():
    text = "' Generated by assets/generate.py; edit the generator.\n"
    # The second label aliases slots 13/14 inside the contiguous 64-sprite bank.
    # A fresh crash restores their full flames after the preceding ember phase.
    text += emit('sprite_art', [b for a in SPRITES[:13] for b in sprite_bytes(a)])
    text += emit('crash_flames', [b for a in SPRITES[13:15] for b in sprite_bytes(a)])
    text += emit('sprite_art_tail', [b for a in SPRITES[15:] for b in sprite_bytes(a)])
    text += emit('crash_embers', [b for rows in CRASH_EMBERS for b in sprite_bytes(fire_sprite(rows))])
    text += emit('tile_art', [b for bits,_ in TILES for b in bits])
    text += emit('tile_colors', [c for _,c in TILES for _ in range(8)])
    text += emit('office_sign_colors', ([0x6F,0x6F,0x6F]+[0x1F]*5)*4)
    text += emit('world_map', [c for r in MAP for c in r])
    text += emit('ground_row', [129]*32)
    text += emit('fence_codes',FENCE_CODES)
    text += emit('home_fence_codes',HOME_FENCE_CODES)
    text += emit('pad_fence_art',PAD_FENCE_ART)
    text += emit('pad_fence_colors',PAD_FENCE_COLORS)
    text += emit('flag_frame0', FLAG0)
    text += emit('flag_frame1', FLAG1)
    text += emit('flag_colors', FLAG_COLORS)
    text += emit('jet_arc', JET_ARC)
    text += emit('fire_frame0', FIRE0)
    text += emit('fire_frame1', FIRE1)
    text += emit('fire_colors', FIRE_COLORS)
    text += emit('person_rows',PERSON_ROWS+[v>>4 for v in PERSON_ROWS]+[(v<<4)&255 for v in PERSON_ROWS])
    text += emit('crowd_bases',[0]*8+[255-v for v in TILES[5][0]]+TILES[28][0]+TILES[29][0])
    # The bottom-third menu font lives in the data bank; its colours (all
    # white on black) are filled at run time, not stored as 256 equal bytes.
    text += emit('menu_font',MENU_FONT)
    text += emit('person_colors',PERSON_COLORS)
    text += emit('camp_bits',[1,2,4,8])
    text += emit('person_kind',[i%3 for i in range(64)])
    text += emit('waiting_kind',[96+(i%3)*4 for i in range(64)])
    standing=[b for kind in range(3) for b in PERSON_ROWS[kind*64:kind*64+32]]
    text += emit('waiting_art',standing*2)
    text += emit('waiting_colors',[v for paper in (1,4) for ink in (11,15,10) for v in [ink*16+paper]*32])
    text += emit('star_x',STAR_X)
    # Row 0 ends the list (both renderers stop there); the second 0 keeps the
    # DATA BYTE block even so later word tables stay aligned.
    text += emit('star_row',STAR_ROW+[0,0])
    text += emit('star_bits',STAR_BITS)
    text += emit('star_colors',STAR_COLORS)
    (ROOT/'src/assets.bas').write_text(text, encoding='utf-8', newline='\n')
    print(f'Assets: {len(SPRITES)} sprites, {len(TILES)} tiles, {sum(map(len,MAP))} map bytes')

if __name__ == '__main__': generate()
