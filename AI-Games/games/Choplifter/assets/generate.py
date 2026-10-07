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
# 12 tank, 13/14 crash flames, 15 jet, 16 drone, 17 shot, 18/19 explosion core
# (BLAST_ART below).
# 47-49 missiles and bomb, 50-56 explosion pieces, 57-58 free (the walking
# people sprites once there are unused: runners are crowd characters).
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
# 16: the air mine, a small spiked ball centred on pixel (7,7).
a = canvas(16, 16)
rect(a, 5, 5, 5, 5); rect(a, 6, 4, 3, 7); rect(a, 4, 6, 7, 3)
for x, y in ((7,3),(7,11),(3,7),(11,7),(4,4),(10,4),(4,10),(10,10)): a[y][x] = 1
SPRITES.append(a)
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
# A tank shell's height on each frame of its lob: launched from the muzzle on
# the foreground plane at y=176, it climbs 32 pixels in 20 frames under
# constant gravity and falls back to the crowd plane, bursting at y=164 on
# frame 36 (SHELL_LAST). Tanks only threaten a helicopter on or just above
# the ground. 38 entries keep the block even.
SHELL_ARC = [176-round(t*(40-t)*2/25) for t in range(38)]
SHELL_LAST = 36
assert min(SHELL_ARC)==144 and SHELL_ARC[SHELL_LAST]==164 and SHELL_ARC[SHELL_LAST-1]<164

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

def row_colors(color):
    """A tile's colour is one byte for all eight rows, or a list of eight."""
    return list(color) if isinstance(color,(list,tuple)) else [color]*8

# Scenery is painted as pixel art, one letter per pixel. The TMS9918 allows
# two colours per 8x1 segment; paint() rejects art that needs a third.
INK={'.':1,'K':1,'W':15,'B':4,'R':6,'G':14,'Y':11}
def paint(rows):
    """(bits, row colours) tiles for 8x8 cells, row by row, left to right."""
    assert len(rows)%8==0 and all(len(row)==len(rows[0]) for row in rows)
    tiles=[]
    for top in range(0,len(rows),8):
        for col in range(0,len(rows[0]),8):
            bits=[];colors=[]
            for row in rows[top:top+8]:
                seg=row[col:col+8]
                inks=sorted({INK[ch] for ch in seg},key=lambda c:(c!=1,c==15,c))
                assert len(inks)<=2,(row,col)
                # Black, then a body colour, is the paper; white is always ink.
                paper=inks[0];ink=inks[1] if len(inks)>1 else 1
                bits.append(sum(128>>x for x,ch in enumerate(seg) if INK[ch]==ink and ink!=paper))
                colors.append(ink*16+paper)
            tiles.append((bits,colors))
    return tiles

# A hostage barrack, after the arcade's: a blue hut with a white roof line, a
# brick chimney at its west end, a dark doorway under the roof's crown, a
# white porch with a ramp and rails below it, and a white footing. Columns are
# camp-2 to camp+1 (the doorway straddles camp-1 and the camp's own column);
# rows 18 (chimney), 19 and 20.
HUT=[
 '................................',
 '................................',
 '................................',
 '....RRRR........................',
 '.....RRR........................',
 '.....RRR........................',
 '.....RRR........................',
 '.....RRR........................',
 '.....RRR........................',
 '.......WWWWWWWWWWWWWWWWWW.......',
 '......BBBBBBBBBBBBBBBBBBBB......',
 '.....BBBBBBBB......BBBBBBBB.....',
 '...BBBBBBBBBB......BBBBBBBBBB...',
 '..BBBBBBBBBBB......BBBBBBBBBBB..',
 '.BBBBBBBBBBBB......BBBBBBBBBBBB.',
 'BBBBBBBBBBBBB......BBBBBBBBBBBBB',
 'BBBBBBBBBBBBB......BBBBBBBBBBBBB',
 'BBBBBBBBBBBBWWWWWWWWWWBBBBBBBBBB',
 'BBBBBBBBBBBWBWBBBBWBBBBBBBBBBBBB',
 'BBBBBBBBBBWBBWBBBBWBBBBBBBBBBBBB',
 'BBBBBBBBBWBBBWBBBBWBBBBBBBBBBBBB',
 'BBBBBBBBWBBBBBBBBBBBBBBBBBBBBBBB',
 'WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW',
 'WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW',
]
HUT_CELLS=paint(HUT)
# Shot open, the hut's middle is blown out: a ragged hole under the roof line
# (row 19, overlay characters 134 and 136) with a fire burning inside on the
# crowd row (126 and 127, two animation frames, see FIRE0/FIRE1).
HUT_OPEN=[
 '................',
 'WWWWWWWWWWWWWWWW',
 'BBBB..BB...BBBBB',
 'BB...........BBB',
 'BB............BB',
 'B..............B',
 'BB.............B',
 'B...............',
]
HUT_OPEN_CELLS=paint(HUT_OPEN)

# Rough blue mountains between the camps, up to 16 pixels tall: a jagged
# range of snow-capped peaks of different heights with valleys between and
# a few rocks. A flank on the crowd row at each end, a body between (133),
# and above the inner columns a small peak, the tall summit, a middling peak
# and another small one. Any of the 4-, 5- and 6-wide selections joins up,
# so a range can be 4, 5 or 6 wide. (Snow sits on rows of its own above the
# blue: a row segment cannot hold sky, snow and rock at once.)
MOUND_TOP=[
 '...........W....................',
 '..........WWW...................',
 '.........WWWWW......W...........',
 '....W...BBBBBBB....WWW......W...',
 '...BBB.BBBBBBBBB..BBBBB....WWW..',
 '..BBBBBBBBBBBBBBBBBBBBBB..BBBBB.',
 '.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
 'BBBBBBBBBBBBWBBBBBBBBBBBBBBBBBBB',
]
def ground_rise(heights,rocks=()):
    """Crowd-row art from column heights (pixels above the ground, 0-8), with
    white rocks at (x, y) where the row is solid rock."""
    rows=[''.join('B' if 8-h <= y else '.' for h in heights) for y in range(8)]
    for x,y in rocks:
        rows[y]=rows[y][:x]+'W'+rows[y][x+1:]
    return rows
# Crowd row: the west flank (142), the body (133) and the east flank (143).
# The flanks rise only from 5 to 8 px; foothills (FOOT) carry the slope down
# to the ground over one or two more characters on each side, so a range
# climbs gradually over 2-3 characters before its peaks.
MOUND_LOW=ground_rise([5,5,6,6,6,7,8,8, 8,8,8,8,8,8,8,8, 8,8,7,6,6,6,5,5],
                      rocks=((3,5),(10,2),(14,5),(21,4)))
MOUND_TOP_CELLS=paint(MOUND_TOP)
MOUND_CELLS=paint(MOUND_LOW)
# Foothills, outer to inner on the west (121, 122) and inner to outer on the
# east (123, 124). They live beside the pad-fence character (120) in the
# bottom screen third only, uploaded with it (low_art, low_colors).
FOOT=paint(ground_rise([0,1,1,1,2,1,2,2, 3,2,3,3,4,4,4,5, 5,4,4,3,3,3,2,3, 2,2,1,2,1,1,0,0]))
FOOT_WEST=[121,122]
FOOT_EAST=[123,124]

# Home: a low brick building with white roof edge, window bands either side
# of a dark door, and a white footing. Columns 247-251; the flag pole stands
# on the roof of the last column (x=2008).
HOME=[
 '................................W.......',
 '................................W.......',
 '................................W.......',
 'WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW',
 'RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR',
 'RWWWWWWRRWWWWWWRRRRRRRRRRWWWWWWRRWWWWWWR',
 'RKKKKKKRRKKKKKKRRKKKKKKRRKKKKKKRRKKKKKKR',
 'RKKKKKKRRKKKKKKRRKKKKKKRRKKKKKKRRKKKKKKR',
 'RKKKKKKRRKKKKKKRRKKKKKKRRKKKKKKRRKKKKKKR',
 'RWWWWWWRRWWWWWWRRKKKKKKRRWWWWWWRRWWWWWWR',
 'RRRRRRRRRRRRRRRRRKKKKKKRRRRRRRRRRRRRRRRR',
 'RRRRRRRRRRRRRRRRRKKKKKKRRRRRRRRRRRRRRRRR',
 'RRRRRRRRRRRRRRRRRKKKKKKRRRRRRRRRRRRRRRRR',
 'RRRRRRRRRRRRRRRRRKKKKKKRRRRRRRRRRRRRRRRR',
 'WWWWWWWWWWWWWWWWWKKKKKKWWWWWWWWWWWWWWWWW',
 'WWWWWWWWWWWWWWWWWKKKKKKWWWWWWWWWWWWWWWWW',
]
HOME_CELLS=paint(HOME)
# The ground is dark blue. The landing pad is a gray slab seven characters
# wide (columns 240-246, x 1920-1975) right against the building's west
# wall: a white rim, an H in the middle, yellow lights at both ends and a
# dark shadow under its front edge. A helicopter unloads only when all of
# its 32 pixels are on it (1920 <= x <= 1944).
GROUND=0x14
PAD_ART=paint([
 'Y'+'W'*54+'Y',
 'W'+'G'*23+'GWGGGGWG'+'G'*23+'W',
 'W'+'G'*23+'GWGGGGWG'+'G'*23+'W',
 'W'+'G'*23+'GWWWWWWG'+'G'*23+'W',
 'W'+'G'*23+'GWGGGGWG'+'G'*23+'W',
 'W'+'G'*23+'GWGGGGWG'+'G'*23+'W',
 'W'*56,
 'K'*56,
])
# Plain rows get white ink (their bits are clear): a fence stamp crossing the
# pad draws white over any of its rows.
PAD_ART=[(bits,[c if b else 0xF0|c&15 for b,c in zip(bits,colors)]) for bits,colors in PAD_ART]
assert PAD_ART[1]==PAD_ART[2]==PAD_ART[4]==PAD_ART[5]
PAD_COLUMNS=range(240,247)
PAD_LEFT,PAD_RIGHT=240*8,247*8

# Characters 128..159. Each colour is one byte for all eight rows or a list.
TILES = [
    ([0]*8, GROUND),                  # 128 ground at horizon
    ([0]*8, GROUND),                  # 129 foreground ground
    HUT_CELLS[4],                      # 130 hut roof, west slope, chimney foot
    HUT_CELLS[7],                      # 131 hut roof, east slope
    HUT_CELLS[8],                      # 132 hut wall (crowd row)
    MOUND_CELLS[1],                    # 133 hill body (crowd row)
    HUT_OPEN_CELLS[0],                 # 134 blown-out hut, west half (row 19)
    HUT_CELLS[5],                      # 135 hut, west of the doorway (row 19)
    HUT_OPEN_CELLS[1],                 # 136 blown-out hut, east half (row 19)
    PAD_ART[1],                        # 137 landing pad
    PAD_ART[3],                        # 138 landing pad, H
    HOME_CELLS[4],                     # 139 home window under the flag pole
    ([0,126,24,63,127,24,126,0],0xF1), # 140 spare
    PAD_ART[6],                        # 141 landing pad, east end
    MOUND_CELLS[0],                    # 142 hill, west flank (crowd row)
    MOUND_CELLS[2],                    # 143 hill, east flank (crowd row)
    ([213,162,213,162,255,255,255,255],0xF4), # 144 flag canton/stripes (colours below)
    ([254,254,252,252,254,254,248,248],0xF1), # 145 flag fly edge
    ([128]*8,0xF1),                   # 146 flagpole
    HUT_CELLS[10],                     # 147 hut porch, east (crowd row)
    MOUND_TOP_CELLS[0],                # 148 hill top, rising (row 19)
    MOUND_TOP_CELLS[1],                # 149 hill top, lumpy (row 19)
    MOUND_TOP_CELLS[3],                # 150 hill top, falling (row 19)
]
FLAG0 = TILES[16][0] + TILES[17][0]
FLAG1 = TILES[16][0] + [248,248,254,254,252,252,254,254]
# White stars on blue canton, then red/white stripes. Right tile: stripes on black.
FLAG_COLORS = [0xF4]*4 + [0x81,0xF1,0x81,0xF1] + [0x81,0xF1]*4

# The fire inside a blown-out hut: characters 126 (west) and 127 (east) on
# the crowd row, two frames that crowd_draw swaps every 8 frames. Each row has
# one ink for both frames and both characters (one colour table): yellow tips,
# orange, red, a red bed of embers and rubble on the white footing.
FIRE_INK={'B':4,'Y':11,'O':10,'L':9,'M':8,'R':6,'W':15,'.':1}
FIRE_ROWS=[('B','.'),('Y','.'),('Y','.'),('O','.'),('L','.'),('M','.'),('R','W'),('R','W')]
FIRE_ART=[
 ['B..............B',
  '..Y.......Y.....',
  '..YY..Y...YY..Y.',
  '.OOO.OOO.OOOO.OO',
  'LLLLLLL.LLLLLLLL',
  'MMMMMMMMMMMMMMMM',
  'WRRWWWRRWWRRRWWW',
  'WWWWWWWWWWWWWWWW'],
 ['B..............B',
  '.....Y.......Y..',
  '.Y...YY..Y...YY.',
  '.OO.OOOO.OOO.OOO',
  'LLLL.LLLLLLL.LLL',
  'MMMMMMMMMMMMMMMM',
  'WWRRWWWRRWWWRRWW',
  'WWWWWWWWWWWWWWWW']]
def fire_frame(rows):
    out=[]
    for col in (0,8):
        for (ink,paper),row in zip(FIRE_ROWS,rows):
            seg=row[col:col+8]
            assert set(seg)<={ink,paper},(seg,ink,paper)
            out.append(sum(128>>x for x,ch in enumerate(seg) if ch==ink))
    return out
FIRE0,FIRE1=(fire_frame(rows) for rows in FIRE_ART)
FIRE_COLORS=[FIRE_INK[ink]*16+FIRE_INK[paper] for ink,paper in FIRE_ROWS]*2

TILES += [
    HOME_CELLS[0],                     # 151 home window, upper
    HOME_CELLS[2],                     # 152 home door, upper
    HUT_CELLS[6],                      # 153 hut, east of the doorway (row 19)
    HUT_CELLS[9],                      # 154 hut porch, west (crowd row)
    HUT_CELLS[0],                      # 155 hut chimney (row 18)
    HOME_CELLS[5],                     # 156 home window, lower (crowd row)
    HOME_CELLS[7],                     # 157 home door, lower (crowd row)
    MOUND_TOP_CELLS[2],                # 158 hill top, lumpy (row 19)
    PAD_ART[0],                        # 159 landing pad, west end
]
# Every column of the home's two rows is one of three upper and two lower
# characters; check the building reuses them rather than needing more.
assert HOME_CELLS[1]==HOME_CELLS[0] and HOME_CELLS[3]==HOME_CELLS[0]
assert HOME_CELLS[6]==HOME_CELLS[5] and HOME_CELLS[8]==HOME_CELLS[5] and HOME_CELLS[9]==HOME_CELLS[5]
assert HUT_CELLS[11]==HUT_CELLS[8]
assert HUT_CELLS[1]==HUT_CELLS[2]==HUT_CELLS[3]==([0]*8,[0x11]*8)

# Crowd-row cells that keep their scenery under a walker (crowd_background and
# compose_cell): an 8-byte base pattern each, and palettes in PERSON_COLORS.
# A person is drawn in each row's ink, so rows that would need a third colour
# give way: a window pane's brick edges go dark. The hill body keeps its rocks.
WINDOW_BASE=[0,TILES[28][0][1],0,0,0,0,0,0]
CROWD_BASES=[0]*8+TILES[5][0]+WINDOW_BASE+[0]*8

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
# The runner sprites (47-58) are unused since runners became crowd
# characters. 47/48: a jet's missile pointing east (x 0-10) and west (x 5-15),
# swept fins at the tail, rows 0-2; 49: a jet's bomb, fins up, x 0-3, rows 0-5.
MISSILE=[[1,1,0,0,0,0,0,0,0,0,0],[0,1,1,1,1,1,1,1,1,1,1],[1,1,0,0,0,0,0,0,0,0,0]]
for flip in (False,True):
    a=canvas(16,16)
    for y,row in enumerate(MISSILE):
        for x,pixel in enumerate(row):
            if pixel:a[y][15-x if flip else x]=1
    SPRITES[47+flip]=a
a=canvas(16,16)
for y,row in enumerate(('#..#','.##.','####','####','####','.##.')):
    for x,ch in enumerate(row):
        if ch=='#':a[y][x]=1
SPRITES[49]=a

# Explosions (blast_draw): a core sprite and three debris clusters, each a
# few separate pixels, so four sprites read as a spray of particles. 18/19:
# the fireball, then its broken, spreading ring; 50 smoke; 51-53 sparks
# spreading apart (tight, wider, widest); 54 embers; 55 dirt clods; 56 the
# small burst's flash. 57 and 58 are free.
def bitmap(rows):
    assert len(rows)==16 and all(len(r)==16 and set(r)<=set('.#') for r in rows)
    return [[int(ch=='#') for ch in r] for r in rows]
def dots(points):
    a=canvas(16,16)
    for x,y in points:a[y][x]=1
    return a
BLAST_ART={
 'fire':bitmap(['................','................','................','.......#........',
                '.....#.##.#.....','....########....','...#########....','..###########...',
                '...##########...','....#########...','...#.#######....','......##.##.....',
                '.......#........','................','................','................']),
 'ring':bitmap(['................','......#...#.....','...#..##.###....','....######.##.#.',
                '..####...####...','.###.......###..','..##........##..','.###.........##.',
                '..##........###.','.###.......##...','..####....####..','...#.######.#...',
                '....#..##..#....','......#..#......','................','................']),
 'smoke':bitmap(['................','................','......#.#.......','....#.###.#.....',
                 '.....#####......','...#.#.#.#.#....','....#######.....','...#.#.#.#.#....',
                 '....#.###.#.....','......#.#.......','................','................',
                 '................','................','................','................']),
 'spark1':dots([(7,7),(8,7),(7,8),(8,8),(6,6),(9,6),(6,9),(9,9)]),
 'spark2':dots([(7,7),(8,8),(4,6),(11,5),(5,10),(10,11),(7,3),(9,12)]),
 'spark3':dots([(2,7),(13,6),(7,1),(8,13),(4,3),(11,11)]),
 'ember':dots([(6,8),(9,7),(8,10)]),
 'dirt':dots([(5,6),(6,6),(9,5),(9,6),(7,9),(8,9),(4,10),(11,9)]),
 'flash':bitmap(['................','................','................','................',
                 '.......#........','.....#.#.#......','......###.......','....#######.....',
                 '......###.......','.....#.#.#......','.......#........','................',
                 '................','................','................','................']),
}
BLAST_SLOT={'fire':18,'ring':19,'smoke':50,'spark1':51,'spark2':52,'spark3':53,
            'ember':54,'dirt':55,'flash':56}
for name,slot in BLAST_SLOT.items():SPRITES[slot]=BLAST_ART[name]

# Burst timelines, one row per two frames: blast_draw reads row
# (blast_end - blast_timer) / 2. Air bursts are rows 0-17 (blast_end 36),
# ground bursts 18-35 (72) and small ground bursts 36-45 (92). Per row: the
# core's pattern, colour and rise (smoke drifts up), the debris clusters'
# pattern and colour, and each of the three clusters' offset from the
# burst. Debris flies ballistically; on the ground it comes down at the
# burst's level and lies there. Offsets are stored +64.
BLAST_KINDS=(('air',36,18),('ground',72,18),('small',92,10))
BIG_CORE=([('fire',15)]*2+[('fire',11)]*2+[('ring',11)]*2+[('ring',10)]*2
          +[('ring',9)]*2+[('ring',8)]*2+[('smoke',14)]*6)
BIG_RISE=[0]*12+[-2,-4,-6,-8,-10,-12]
BIG_DEBRIS=([('spark1',15)]*4+[('spark2',11)]*4+[('spark2',10)]*4+[('spark3',9)]*3
            +[('ember',8)]*2+[('ember',6)])
SMALL_CORE=[('flash',15)]*2+[('flash',11)]*2+[('flash',9)]*2+[('smoke',14)]*4
SMALL_RISE=[0]*6+[-1,-2,-3,-4]
SMALL_DEBRIS=[('spark1',15)]*2+[('dirt',11)]*3+[('dirt',10)]*3+[('ember',6)]*2
BIG_THROW=((-1.6,-1.8),(0.3,-2.4),(1.7,-1.4))
SMALL_THROW=((-0.9,-1.6),(0.2,-2.0),(1.0,-1.4))
def flight(vx,vy,g,rows,grounded):
    """Offsets at the middle of each two-frame row; grounded debris stops
    where it comes back down to the burst's level."""
    out=[]
    for row in range(rows):
        t=row*2+1
        if grounded and vy*t+g*t*t/2>0:t=-2*vy/g
        out.append((round(vx*t),round(vy*t+g*t*t/2)))
    return out
BLAST_ROWS=[]   # (core pattern, colour, rise, debris pattern, colour, 3 offsets)
for kind,end,rows in BLAST_KINDS:
    core,rise,debris=(SMALL_CORE,SMALL_RISE,SMALL_DEBRIS) if kind=='small' else (BIG_CORE,BIG_RISE,BIG_DEBRIS)
    throw,g=(SMALL_THROW,0.18) if kind=='small' else (BIG_THROW,0.12)
    paths=[flight(vx,vy,g,rows,kind!='air') for vx,vy in throw]
    assert len(core)==len(rise)==len(debris)==rows and end==2*len(BLAST_ROWS)+2*rows
    for row in range(rows):
        BLAST_ROWS.append((BLAST_SLOT[core[row][0]]*4,core[row][1],rise[row],
                           BLAST_SLOT[debris[row][0]]*4,debris[row][1],[p[row] for p in paths]))
assert len(BLAST_ROWS)==46
assert all(-64<=v<64 for r in BLAST_ROWS for xy in r[5] for v in xy)
# Person palettes, eight rows each, by crowd_cells offset: yellow, white and
# tan clothing on the night (0-23); the home doorway (24); the three kinds in
# front of a hut wall, dark feet on its white footing (32-55); spare (56-79);
# the hill body (80); a home window (88). See CROWD_BASES.
INKS=(11,15,10)
PERSON_COLORS=([v for ink in INKS for v in [ink*16+1]*8]+[0xF1]*8
               +[v for ink in INKS for v in [ink*16+4]*6+[0x1F]*2]
               +[v for ink in INKS for v in [ink*16+14]*8]
               +[0xF4]*8
               +[0xF1]+[0xF6]*5+[0x1F]*2)
assert len(PERSON_COLORS)==96
# Standing characters 96-107 on the night and 108-119 for a hut wall (the
# waiting_scan +12): yellow, white, tan, four poses each.
WAITING_COLORS=([v for ink in INKS for v in [ink*16+1]*32]
                +[v for ink in INKS for _ in range(4) for v in [ink*16+4]*6+[0x1F]*2])

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
        # Shells are lobbed, so the side views raise the barrel about 25 degrees.
        line(a,11,4,1,0);line(a,11,5,1,1);line(a,12,5,2,1)
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
            TILES.append((bits,0xF0|GROUND&15))

# Eight screens: two extra screens between the camps and the enemy fence.
# The demilitarized zone itself remains 320 pixels wide.
MAP = [[32]*256 for _ in range(5)]
MAP[4] = [128]*256
CAMPS=(16,48,80,112)
# Hills sit in the gaps between the crowds (waiting spots reach 11 columns
# west and 12 east of a camp), never under a settled crowd. (start, width):
# a width-w hill has its flanks and body on the crowd row and w-2 tops above.
# (start, width, west foothills, east foothills): the range's own columns
# start..start+width-1, with one or two foothill characters on each side.
MOUNDS=((0,4,0,1),(31,4,2,2),(62,5,1,2),(95,4,2,2),(130,6,2,1),(145,4,1,2),
        (160,5,2,2),(176,6,2,2),(188,4,1,1),(204,5,2,2),(222,4,2,2))
HILL_TOPS={4:[148,150],5:[148,149,150],6:[148,149,158,150]}
for start,width,west,east in MOUNDS:
    MAP[3][start-west:start]=FOOT_WEST[2-west:]
    MAP[3][start:start+width]=[142]+[133]*(width-2)+[143]
    MAP[3][start+width:start+width+east]=FOOT_EAST[:east]
    MAP[2][start+1:start+width-1]=HILL_TOPS[width]
    first,end=start-west,start+width+east
    assert first>=0 and end<=1888//8   # clear of the home fence
    for camp in CAMPS:
        assert end<=camp-11 or first>camp+12,(start,camp)
for camp in CAMPS:
    MAP[1][camp-2]=155
    MAP[2][camp-2:camp+2]=[130,135,153,131]
    MAP[3][camp-2:camp+2]=[132,154,147,132]
MAP[2][247:252]=[151,151,152,151,139]
MAP[3][247:252]=[156,156,157,156,156]
MAP[4][240:247]=[159,137,137,138,137,137,141]
PAD_CODES=(159,137,138,141)

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
        if under not in PAD_CODES:continue
        base,color=TILES[under-128]
        bits,_=TILES[32+index]
        assert all(c>>4==15 for c in row_colors(color)) # same white ink as the fence
        HOME_FENCE_CODES[index]=120+len(PAD_FENCE_ART)//8
        PAD_FENCE_ART.extend(a|b for a,b in zip(base,bits))
        PAD_FENCE_COLORS.extend(row_colors(color))
# At most one composed cell, code 120 (none for the current pad: the home
# fence's stamps end at column 238). Code 120 stays reserved either way, so
# the foothills that follow it in low_art keep their codes (121-124).
assert len(PAD_FENCE_ART) in (0,8)
PAD_FENCE_ART+=[0]*(8-len(PAD_FENCE_ART))
PAD_FENCE_COLORS+=[0x11]*(8-len(PAD_FENCE_COLORS))

# CVBasic/TMS font @.._: restore the borrowed bottom-third back buffer on menus.
MENU_FONT=[112, 136, 152, 168, 152, 128, 112, 0, 32, 80, 136, 136, 248, 136, 136, 0, 240, 136, 136, 240, 136, 136, 240, 0, 112, 136, 128, 128, 128, 136, 112, 0, 240, 136, 136, 136, 136, 136, 240, 0, 248, 128, 128, 240, 128, 128, 248, 0, 248, 128, 128, 240, 128, 128, 128, 0, 112, 136, 128, 184, 136, 136, 112, 0, 136, 136, 136, 248, 136, 136, 136, 0, 112, 32, 32, 32, 32, 32, 112, 0, 8, 8, 8, 8, 136, 136, 112, 0, 136, 144, 160, 192, 160, 144, 136, 0, 128, 128, 128, 128, 128, 128, 248, 0, 136, 216, 168, 168, 136, 136, 136, 0, 136, 200, 200, 168, 152, 152, 136, 0, 112, 136, 136, 136, 136, 136, 112, 0, 240, 136, 136, 240, 128, 128, 128, 0, 112, 136, 136, 136, 136, 168, 144, 104, 240, 136, 136, 240, 160, 144, 136, 0, 112, 136, 128, 112, 8, 136, 112, 0, 248, 32, 32, 32, 32, 32, 32, 0, 136, 136, 136, 136, 136, 136, 112, 0, 136, 136, 136, 136, 80, 80, 32, 0, 136, 136, 136, 168, 168, 216, 136, 0, 136, 136, 80, 32, 80, 136, 136, 0, 136, 136, 136, 112, 32, 32, 32, 0, 248, 8, 16, 32, 64, 128, 248, 0, 120, 96, 96, 96, 96, 96, 120, 0, 0, 128, 64, 32, 16, 8, 0, 0, 240, 48, 48, 48, 48, 48, 240, 0, 32, 80, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 248, 0]

def emit(label, data):
    assert len(data) % 2 == 0, label
    return label + ':\n' + ''.join('    DATA BYTE '+','.join(str(v) for v in data[i:i+16])+'\n' for i in range(0,len(data),16))

def generate():
    """Write src/assets.bas (read while playing: the TI's permanently selected
    data bank) and src/assets_boot.bas (only uploaded at power-on: the TI's
    boot bank, selected around the uploads in boot:)."""
    head = "' Generated by assets/generate.py; edit the generator.\n"
    boot = head
    # All 64 sprites, contiguous for the one DEFINE SPRITE at power-on.
    boot += emit('sprite_art', [b for a in SPRITES for b in sprite_bytes(a)])
    boot += emit('tile_art', [b for bits,_ in TILES for b in bits])
    boot += emit('tile_colors', [v for _,c in TILES for v in row_colors(c)])
    # Bottom-third characters 120-124: the pad-fence cell, then the foothills.
    boot += emit('low_art',PAD_FENCE_ART+[b for bits,_ in FOOT for b in bits])
    boot += emit('low_colors',PAD_FENCE_COLORS+[v for _,c in FOOT for v in row_colors(c)])
    boot += emit('flag_colors', FLAG_COLORS)
    boot += emit('fire_colors', FIRE_COLORS)
    standing=[b for kind in range(3) for b in PERSON_ROWS[kind*64:kind*64+32]]
    boot += emit('waiting_art',standing*2)
    boot += emit('waiting_colors',WAITING_COLORS)
    boot += emit('star_bits',STAR_BITS)
    boot += emit('star_colors',STAR_COLORS)
    text = head
    # A crash redefines slots 13/14 as flames, then embers; a fresh crash
    # restores the full flames after the preceding ember phase.
    text += emit('crash_flames', [b for a in SPRITES[13:15] for b in sprite_bytes(a)])
    text += emit('crash_embers', [b for rows in CRASH_EMBERS for b in sprite_bytes(fire_sprite(rows))])
    text += emit('world_map', [c for r in MAP for c in r])
    text += emit('ground_row', [129]*32)
    text += emit('fence_codes',FENCE_CODES)
    text += emit('home_fence_codes',HOME_FENCE_CODES)
    text += emit('flag_frame0', FLAG0)
    text += emit('flag_frame1', FLAG1)
    for label,field in (('blast_cpat',0),('blast_ccol',1),('blast_dpat',3),('blast_dcol',4)):
        text += emit(label,[r[field] for r in BLAST_ROWS])
    text += emit('blast_cdy',[r[2]+64 for r in BLAST_ROWS])
    # The three clusters' rows one after another, 46 apart.
    text += emit('blast_dx',[r[5][p][0]+64 for p in range(3) for r in BLAST_ROWS])
    text += emit('blast_dy',[r[5][p][1]+64 for p in range(3) for r in BLAST_ROWS])
    text += emit('jet_arc', JET_ARC)
    text += emit('shell_arc', SHELL_ARC)
    text += emit('fire_frame0', FIRE0)
    text += emit('fire_frame1', FIRE1)
    text += emit('person_rows',PERSON_ROWS+[v>>4 for v in PERSON_ROWS]+[(v<<4)&255 for v in PERSON_ROWS])
    text += emit('crowd_bases',CROWD_BASES)
    # The bottom-third menu font lives in the data bank; its colours (all
    # white on black) are filled at run time, not stored as 256 equal bytes.
    text += emit('menu_font',MENU_FONT)
    text += emit('person_colors',PERSON_COLORS)
    text += emit('camp_bits',[1,2,4,8])
    text += emit('person_kind',[i%3 for i in range(64)])
    text += emit('waiting_kind',[96+(i%3)*4 for i in range(64)])
    text += emit('star_x',STAR_X)
    # Row 0 ends the list (both renderers stop there); the second 0 keeps the
    # DATA BYTE block even so later word tables stay aligned.
    text += emit('star_row',STAR_ROW+[0,0])
    (ROOT/'src/assets.bas').write_text(text, encoding='utf-8', newline='\n')
    (ROOT/'src/assets_boot.bas').write_text(boot, encoding='utf-8', newline='\n')
    print(f'Assets: {len(SPRITES)} sprites, {len(TILES)} tiles, {sum(map(len,MAP))} map bytes')

if __name__ == '__main__': generate()
