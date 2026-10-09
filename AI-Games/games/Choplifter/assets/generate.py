"""Original editable pixel art and ROM scenery. Run from the project root."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Sparse far-sky layer: one star per row avoids overlap during wrapped scroll.
# A sparse, irregular sky: one far star (rows 3-6), three middle (7-11) and
# four near (12-16), on uneven rows and spread across the width. Rows 5-7
# belong to the moon (MOON_ROW) and row 4 to PAUSED, so no star crosses them.
STAR_X=[31,158,212,97,236,9,129,183]
STAR_ROW=[3,9,16,8,10,12,13,15]
MOON_ROW,MOON_COL=5,26           # its top-left character, fixed on screen
# Each star owns its sky row: stars_draw clears a star's old cell without
# checking for a neighbour, which is only safe while no two stars share a row.
assert len(STAR_X)==len(STAR_ROW) and len(set(STAR_ROW))==len(STAR_ROW)
assert all(3<=row<=16 for row in STAR_ROW)
assert not set(STAR_ROW)&{4,MOON_ROW,MOON_ROW+1,MOON_ROW+2}
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
# 47-49 missiles and bomb, 50-58 explosion pieces (the walking
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
def burn_down(rows,height,trim):
    """A flame sprite burned lower: squashed to `height` rows, still standing
    on row 14, and `trim` columns narrower on each side."""
    mask=((1<<(16-2*trim))-1)<<trim
    out=[0]*16
    for y in range(15-height,15):
        out[y]=rows[round((y-(15-height))*14/(height-1))]&mask
    return out
# A landed wreck burns down in stages (crash_tick redefines sprites 13/14):
# full flames, then lower and narrower ones (crash_burn2, crash_burn3), then
# the embers, each smaller than the last (never less than half of it: no
# jump from a big fire to a few pixels), all standing on row 14.
CRASH_STAGES=[CRASH_FLAMES,[burn_down(r,9,2) for r in CRASH_FLAMES],
              [burn_down(r,6,3) for r in CRASH_FLAMES],CRASH_EMBERS]

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
INK={'.':1,'K':1,'W':15,'B':4,'R':6,'G':14,'Y':11,'D':10,'C':7,'O':8}
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

# The home end of the world (after the SG-1000 version's base): the post
# office five characters wide at columns 243-247 (x 1944-1983), with 64 px of
# land east of it to the world's end; in front of it a gray sidewalk, and a
# wide dark-red landing pad in perspective with a yellow octagon where a new
# helicopter stands. The home-side DMZ fence is at x 1808. The game uses these
# as literals (CVBasic CONSTs over 255 truncate); the tests compare them.
HOME_COL=243
HOME_X=HOME_COL*8                     # 1944, the building's west wall
HOME_DOOR_X=HOME_X+16                 # 1960, where walkers go in (the door)
WAVE_X=HOME_X-12                      # 1932, a waver stands here (arm 4 px short)
FLAG_X=HOME_X+32                      # 1976, the pole on the last roof character
ENEMY_FENCE_X=1488
HOME_FENCE_X=1808
SPAWN_X=1888                          # a new helicopter stands on the octagon
FIREWORKS_X=1904                      # on the pad, with the view at its east end
UNLOAD_MIN,UNLOAD_MAX=1872,HOME_X-32  # all 32 px on the pad, west of the building

# Home: a low brick building with white roof edge, window bands either side
# of a dark door, and a white footing. Columns HOME_COL..HOME_COL+4; the flag
# pole stands on the roof of the last column (FLAG_X).
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
# The ground is dark blue. The landing pad (after the SG-1000 version's) is a
# dark-red apron seen in perspective on rows 21 and 22: its back edge runs
# x 1872-2007 under the building's footing and each line nearer is 2 px wider
# at both ends, so its ends step out to x 1842-2037 at the front. A gray
# sidewalk lies in front of the building on row 21 (x 1936-1991 at the back,
# 1 px wider each line), and a flattened yellow octagon (x 1884-1923, lines
# 2-11) marks where a new helicopter stands (SPAWN_X). PAD_PIXELS paints both
# rows; pad_cells() cuts them into characters (reusing the plain ground ones).
GROUND=0x14
# The foothill tiles replace the ordinary horizon cell. Keep the lower four
# rows' paper blue even where a slope has no ink, or black notches appear
# between a mountain and the newly raised ground line.
FOOT=[(bits,colors[:4]+[(color&0xF0)|(GROUND&15) for color in colors[4:]])
      for bits,colors in FOOT]
HORIZON_TILE=125                   # free bottom-third code, before fire 126-127
HORIZON_ART=[0]*8
HORIZON_COLORS=[0x11]*4+[GROUND]*4  # sky above, blue ground below
PAD_COL0=228                                 # x 1824: the pad's art from here
PAD_BACK=(1872,2007)
SIDEWALK_BACK=(HOME_X-8,HOME_X+47)
OCTAGON_X=SPAWN_X+16                         # its centre, under the helicopter
def pad_pixel(x,y):
    left,right=PAD_BACK[0]-2*y,PAD_BACK[1]+2*y
    if not left<=x<=right:return 'B'
    if y<8 and SIDEWALK_BACK[0]-y<=x<=SIDEWALK_BACK[1]+y:return 'G'
    d=x-OCTAGON_X
    edges={2:[(-12,11)],3:[(-16,-13),(12,15)],4:[(-20,-17),(16,19)],
           5:[(-20,-19),(18,19)],6:[(-20,-19),(18,19)],7:[(-20,-19),(18,19)],
           8:[(-20,-19),(18,19)],9:[(-20,-17),(16,19)],10:[(-16,-13),(12,15)],
           11:[(-12,11)]}
    if any(a<=d<=b for a,b in edges.get(y,())):return 'D'
    return 'R'
PAD_PIXELS=[''.join(pad_pixel(x,y) for x in range(PAD_COL0*8,2048)) for y in range(16)]
assert UNLOAD_MIN>=PAD_BACK[0] and UNLOAD_MAX+31<HOME_X and UNLOAD_MIN<=SPAWN_X<=UNLOAD_MAX
assert UNLOAD_MIN<=FIREWORKS_X<=UNLOAD_MAX and FIREWORKS_X>=1904   # the view at its east end
assert OCTAGON_X+19<SIDEWALK_BACK[0]-7      # the octagon is clear of the sidewalk

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
    ([0]*8, GROUND),                   # 137 free (was the old pad)
    ([0]*8, GROUND),                   # 138 free (was the old pad)
    HOME_CELLS[4],                     # 139 home window under the flag pole
    ([0,126,24,63,127,24,126,0],0xF1), # 140 spare-helicopter HUD icon
    ([0]*8, GROUND),                   # 141 free (was the old pad)
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
    ([0]*8, GROUND),                   # 159 free (was the old pad)
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
# the fireball, then its broken, spreading ring; 50 a firework rocket (a
# rising gray smoke puff once ended each burst there, and read as a second,
# white explosion popping up); 51-53 sparks
# spreading apart (tight, wider, widest); 54 embers; 55 dirt clods; 56 the
# small burst's flash; 57 the tiny burst's puff; 58 an air burst's chunk
# falling with a trail of sparks above it. No sprite pattern is free.
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
 'spark1':dots([(7,7),(8,7),(7,8),(8,8),(6,6),(9,6),(6,9),(9,9)]),
 'spark2':dots([(7,7),(8,8),(4,6),(11,5),(5,10),(10,11),(7,3),(9,12)]),
 'spark3':dots([(2,7),(13,6),(7,1),(8,13),(4,3),(11,11)]),
 'ember':dots([(6,8),(9,7),(8,10)]),
 'dirt':dots([(5,6),(6,6),(9,5),(9,6),(7,9),(8,9),(4,10),(11,9)]),
 'flash':bitmap(['................','................','................','................',
                 '.......#........','.....#.#.#......','......###.......','....#######.....',
                 '......###.......','.....#.#.#......','.......#........','................',
                 '................','................','................','................']),
 'drop':bitmap(['................','................','................','........#.......',
                '................','................','.......#........','................',
                '................','........#.......','................','.......##.......',
                '......####......','.......##.......','................','................']),
 'puff':bitmap(['................','................','................','................',
                '................','......#.#.......','.......#........','.....#####......',
                '.......#........','......#.#.......','................','................',
                '................','................','................','................']),
}
# A rocket's bright head; its trail is three ember sprites along its path.
BLAST_ART['rocket']=dots([(7,7),(8,7),(7,8),(8,8),(6,7),(9,8)])
BLAST_SLOT={'fire':18,'ring':19,'rocket':50,'spark1':51,'spark2':52,'spark3':53,
            'ember':54,'dirt':55,'flash':56,'puff':57,'drop':58}
for name,slot in BLAST_SLOT.items():SPRITES[slot]=BLAST_ART[name]

# Burst timelines, one row per two frames: blast_draw reads row
# (blast_end - blast_timer) / 2. Air bursts are rows 0-17 (blast_end 36),
# ground bursts 18-35 (72), small bursts 36-45 (92), small core-only bursts
# 46-55 (112), tiny bursts 56-61 (124) and tiny core-only ones 62-67 (136):
# a smaller blast_end is a bigger burst, which a smaller one never cuts
# short. A small or tiny burst that hits something (a person) throws its
# spray of debris; one on bare ground with no target plays only its core,
# the same flash fading out, without the spray. Per row: the core's pattern,
# colour and rise (all 0 now: nothing rises), the debris clusters' pattern and colour
# (pattern 0: none, blast_draw hides them), and each of the three clusters'
# offset from the burst. Debris flies ballistically; on the ground it comes
# down at the burst's level and lies there. Offsets are stored +64.
BLAST_KINDS=(('air',36,18),('ground',72,18),('small',92,10),('small_core',112,10),
             ('tiny',124,6),('tiny_core',136,6))
# Every core fades out where it burst, through red to dark red, then (big
# bursts) is gone (colour 0) while the last embers fall: nothing rises.
BIG_CORE=([('fire',15)]*2+[('fire',11)]*2+[('ring',11)]*2+[('ring',10)]*2
          +[('ring',9)]*2+[('ring',8)]*2+[('ring',6)]*4+[('ring',0)]*2)
BIG_RISE=[0]*18
BIG_DEBRIS=([('spark1',15)]*4+[('spark2',11)]*4+[('spark2',10)]*4+[('spark3',9)]*3
            +[('ember',8)]*2+[('ember',6)])
SMALL_CORE=[('flash',15)]*2+[('flash',11)]*2+[('flash',9)]*2+[('flash',8)]*2+[('flash',6)]*2
SMALL_RISE=[0]*10
SMALL_DEBRIS=[('spark1',15)]*2+[('dirt',11)]*3+[('dirt',10)]*3+[('ember',6)]*2
TINY_CORE=[('puff',15),('puff',11),('puff',9),('puff',8),('puff',6),('puff',6)]
TINY_RISE=[0]*6
TINY_DEBRIS=[('ember',15),('ember',11),('ember',11),('ember',9),('ember',8),('ember',6)]
BIG_THROW=((-1.6,-1.8),(0.3,-2.4),(1.7,-1.4))
SMALL_THROW=((-0.9,-1.6),(0.2,-2.0),(1.0,-1.4))
TINY_THROW=((-0.6,-1.1),(0.1,-1.4),(0.7,-1.0))
# Each kind's (core, rise, debris, throw, gravity in px per frame squared).
BLAST_TIMELINES={'air':(BIG_CORE,BIG_RISE,BIG_DEBRIS,BIG_THROW,0.12),
                 'ground':(BIG_CORE,BIG_RISE,BIG_DEBRIS,BIG_THROW,0.12),
                 'small':(SMALL_CORE,SMALL_RISE,SMALL_DEBRIS,SMALL_THROW,0.18),
                 'tiny':(TINY_CORE,TINY_RISE,TINY_DEBRIS,TINY_THROW,0.22)}
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
    core_only=kind.endswith('_core')
    core,rise,debris,throw,g=BLAST_TIMELINES[kind[:-5] if core_only else kind]
    paths=[flight(vx,vy,g,rows,kind!='air') for vx,vy in throw]
    assert len(core)==len(rise)==len(debris)==rows and end==2*len(BLAST_ROWS)+2*rows
    for row in range(rows):
        if core_only:
            spray=(0,0,[(0,0)]*3)
        else:
            spray=(BLAST_SLOT[debris[row][0]]*4,debris[row][1],[p[row] for p in paths])
        BLAST_ROWS.append((BLAST_SLOT[core[row][0]]*4,core[row][1],rise[row])+spray)
# An air burst also drops a burning chunk straight down (slot 16), so it
# reads as a burst in the sky: blast_fall is how far it has fallen at each
# of the air rows (0-17), starting at 1 px/frame and pulled down at 0.18 px
# per frame squared, no further than 120 px; blast_fpat and blast_fcol its
# pattern and colour.
AIR_ROWS=dict((k,(e,n)) for k,e,n in BLAST_KINDS)['air'][1]
BLAST_FALL=[min(120,round((2*r+1)*1.0+0.09*(2*r+1)**2)) for r in range(AIR_ROWS)]
BLAST_FPAT=[BLAST_SLOT['drop']*4]*AIR_ROWS
BLAST_FCOL=[15,15,11,11,11,10,10,10,9,9,9,8,8,8,6,6,6,6]
assert len(BLAST_FCOL)==AIR_ROWS and BLAST_FALL==sorted(BLAST_FALL)
# Pattern 0 means "no spray": no debris art may use it.
assert all(r[3] for r in BLAST_ROWS if r[4]) and min(BLAST_SLOT.values())>0
# blast_draw steps through the clusters' rows by this stride (di=di+68).
BLAST_STRIDE=len(BLAST_ROWS)
assert BLAST_STRIDE==68
assert all(-64<=v<64 for r in BLAST_ROWS for xy in r[5] for v in xy)
# Person palettes, eight rows each, by crowd_cells offset: yellow, white and
# tan clothing against sky above the low blue horizon (0-23); the home doorway (24); the three kinds in
# front of a hut wall, dark feet on its white footing (32-55); spare (56-79);
# the hill body (80); a home window (88). See CROWD_BASES.
INKS=(11,15,10)
PERSON_COLORS=([v for ink in INKS for v in [ink*16+1]*4+[ink*16+4]*4]+[0xF1]*8
               +[v for ink in INKS for v in [ink*16+4]*6+[0x1F]*2]
               +[v for ink in INKS for v in [ink*16+14]*8]
               +[0xF4]*8
               +[0xF1]+[0xF6]*5+[0x1F]*2)
assert len(PERSON_COLORS)==96

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
# A stamp cell without ink is never drawn: its code is free for the pad.
FENCE_CODES=[160+i if any(bits) else 0 for i,(bits,_) in enumerate(TILES[32:112])]

# Eight screens: two extra screens between the camps and the enemy fence.
# The demilitarized zone between the two fences is 320 pixels wide.
assert HOME_FENCE_X-ENEMY_FENCE_X==320
MAP = [[32]*256 for _ in range(6)]
MAP[3] = [HORIZON_TILE]*256          # row 20, horizon behind people and buildings
MAP[4] = [128]*256                   # row 21, solid ground below the low horizon
MAP[5] = [129]*256                   # row 22, the foreground ground
CAMPS=(16,48,80,112)
# Hills sit in the gaps between the crowds (the people run about from 11
# columns west to 12 east of a camp, ROAM_GOALS), never under them. (start, width):
# a width-w hill has its flanks and body on the crowd row and w-2 tops above.
# (start, width, west foothills, east foothills): the range's own columns
# start..start+width-1, with one or two foothill characters on each side.
MOUNDS=((0,4,0,1),(31,4,2,2),(62,5,1,2),(95,4,2,2),(130,6,2,1),(145,4,1,2),
        (160,5,2,2),(176,6,2,2),(188,4,1,1),(204,5,2,2),(218,4,2,2))
HILL_TOPS={4:[148,150],5:[148,149,150],6:[148,149,158,150]}
for start,width,west,east in MOUNDS:
    MAP[3][start-west:start]=FOOT_WEST[2-west:]
    MAP[3][start:start+width]=[142]+[133]*(width-2)+[143]
    MAP[3][start+width:start+width+east]=FOOT_EAST[:east]
    MAP[2][start+1:start+width-1]=HILL_TOPS[width]
    first,end=start-west,start+width+east
    assert first>=0 and end<=HOME_FENCE_X//8   # clear of the home fence
    for camp in CAMPS:
        assert end<=camp-11 or first>camp+12,(start,camp)
for camp in CAMPS:
    MAP[1][camp-2]=155
    MAP[2][camp-2:camp+2]=[130,135,153,131]
    MAP[3][camp-2:camp+2]=[132,154,147,132]
# Hostages running about outside a burning barrack, as in the Apple II
# original: each heads for a goal on the camp's open ground (x offsets from
# the camp: the mounds leave -88..+96), stands a while, then heads for the
# next. Even-numbered people (index i in the camp) use the first eight goals
# and odd-numbered the other eight, interleaved 12 px apart, so the two never
# share a spot; goal n of person i is cycle[(n + 3*(i//2)) % 8], the next one
# every 128 frames from its phase ROAM_PHASE[i], so they do not move in step,
# and people of one parity whose clocks agree aim at least 24 px apart. Each
# cycle steps 24 or 48 px: a short dash, then a pause of a second or more.
# Goals may be in front of the hut (its walls, hole and door), as in the
# original.
ROAM_GOALS=(-88,-40,8,56,80,32,-16,-64, -76,-28,20,68,92,44,-4,-52)
ROAM_PHASE=[(i*37)%128 for i in range(16)]
assert len(set(ROAM_GOALS))==16 and all(v%4==0 and -88<=v<=96 for v in ROAM_GOALS)
for half in (ROAM_GOALS[:8],ROAM_GOALS[8:]):
    assert all(abs(half[i]-half[i-1]) in (24,48) for i in range(8))
    assert min(b-a for a,b in zip(sorted(half),sorted(half)[1:]))>=24
assert min(b-a for a,b in zip(sorted(ROAM_GOALS),sorted(ROAM_GOALS)[1:]))>=12
assert len(set(ROAM_PHASE))==16 and max(ROAM_PHASE)<128
def roam_goal_index(i,clock):
    """Which ROAM_GOALS entry person i (0-15) heads for at crowd_clock."""
    return ((clock+ROAM_PHASE[i])//128+3*(i//2))%8+8*(i%2)
for camp in CAMPS:
    for v in ROAM_GOALS:
        for col in {camp+v//8,camp+(v+7)//8}:
            assert MAP[3][col] in (HORIZON_TILE,132,154,147),(camp,v)
# As stored (roam_goal): each +128.
ROAM_TABLE=[v+128 for v in ROAM_GOALS]
FIRST_OUT=[ROAM_TABLE[roam_goal_index(i,0)] for i in range(6)]
assert min(b-a for a,b in zip(sorted(FIRST_OUT),sorted(FIRST_OUT)[1:]))>=12
MAP[2][HOME_COL:HOME_COL+5]=[151,151,152,151,139]
MAP[3][HOME_COL:HOME_COL+5]=[156,156,157,156,156]
assert MAP[3][HOME_DOOR_X//8]==157 and MAP[3][WAVE_X//8]==HORIZON_TILE and MAP[3][(WAVE_X+8)//8]==HORIZON_TILE

def pad_cells():
    """Cut the pad's two rows into characters: plain ground keeps 128/129,
    every other distinct cell takes a free code (the old pad's, then blank
    fence stamp cells). Returns {code: (bits, colours)}."""
    free=[137,138,141,159]+[160+i for i,c in enumerate(FENCE_CODES) if not c]
    cells={}
    for row in range(2):
        rows=PAD_PIXELS[row*8:row*8+8]
        for k,(bits,colors) in enumerate(paint(rows)):
            if not any(bits) and colors==[GROUND]*8:
                code=128+row
            else:
                key=(tuple(bits),tuple(colors))
                code=next((c for c,v in cells.items() if v==key),None)
                if code is None:
                    code=free.pop(0);cells[code]=key
            MAP[4+row][PAD_COL0+k]=code
    return cells
PAD_TILES=pad_cells()
for code,(bits,colors) in PAD_TILES.items():
    TILES[code-128]=(list(bits),list(colors))
PAD_CODES=tuple(sorted(PAD_TILES))
PAD_COLUMNS=range(PAD_COL0,256)

# Transparent fence stamps must leave the landing pad beneath them intact. A
# stamp cell that landed on a pad character would be precomposed as code 120;
# the home fence (HOME_FENCE_X) keeps clear of the pad at every lean.
HOME_FENCE_CODES=FENCE_CODES.copy()
PAD_FENCE_ART=[]
PAD_FENCE_COLORS=[]
for shape in range(8):
    for col in range(5):
        index=shape*10+col
        if not FENCE_CODES[index]:continue
        world_col=HOME_FENCE_X//8+col-max(4-shape,0)
        under=MAP[4+index//5%2][world_col]
        if under not in PAD_CODES:continue
        base,color=TILES[under-128]
        bits,_=TILES[32+index]
        assert all(c>>4==15 for c in row_colors(color)) # same white ink as the fence
        HOME_FENCE_CODES[index]=120+len(PAD_FENCE_ART)//8
        PAD_FENCE_ART.extend(a|b for a,b in zip(base,bits))
        PAD_FENCE_COLORS.extend(row_colors(color))
# At most one composed cell, code 120 (none for the current pad: the home
# fence's stamps end at column 229). Code 120 stays reserved either way, so
# the foothills that follow it in low_art keep their codes (121-124).
assert len(PAD_FENCE_ART)==0
PAD_FENCE_ART+=[0]*(8-len(PAD_FENCE_ART))
PAD_FENCE_COLORS+=[0x11]*(8-len(PAD_FENCE_COLORS))

# The moon, fixed in the sky (after the Apple II version's): a banded white
# orb with cyan and orange-red streaks and two dark specks, transcribed from
# the reference at its own pixel grid (22 x 20) and centred in three
# characters by three. A character row segment can hold two colours: inside
# the orb that is white and one streak colour; at its rim, the black sky and
# one. Characters 14-22 of the TOP screen third only (rows MOON_ROW..+2 are
# there), which nothing else uses: the HUD has 1-13 and the crowd and fire
# codes 14-31 are bottom-third ones.
MOON=[
 '........................',
 '........................',
 '.........WWWWWWW........',
 '.........WWWWWWW........',
 '.....WWWCCCWWWCCCCC.....',
 '.....WWWCCOCCOCCCCCC....',
 '....WWWWWWCCCCCCWWWWW...',
 '...WWWWWWWCCCCCCWWWWW...',
 '..OOOOOOWOOOOWWWWWWWWW..',
 '..WWWWWWCCCCCWWWWWWWWWW.',
 '.WWWWWWWWWCCCCCWCCCCCCC.',
 '.WWWWW..WWCCCCCWCCCCCCC.',
 '.OOOOOOOWWWOOOOOOOOOOOO.',
 '.WWWWWWWCCCCCCCCCCCCCCC.',
 '.WWWWWWWWOOOOOOWWWWWWWW.',
 '..CCCCCCCCCCCWWWWWWWWW..',
 '..WWWWWWOOOOWWWOOOOOOO..',
 '...CCCCCWWCCCCCCCCCCC...',
 '....OOOOWWWOWWWW.OOO....',
 '.....WWWCCCCCCCCCCCC....',
 '......WWWOOOOOWWOOO.....',
 '.........WWWWWWW........',
 '........................',
 '........................',
]
MOON_CELLS=paint(MOON)
MOON_CODE=14
assert MOON_ROW+2<8 and MOON_CODE+len(MOON_CELLS)-1<=31

# CVBasic/TMS font @.._: restore the borrowed bottom-third back buffer on menus.
MENU_FONT=[112, 136, 152, 168, 152, 128, 112, 0, 32, 80, 136, 136, 248, 136, 136, 0, 240, 136, 136, 240, 136, 136, 240, 0, 112, 136, 128, 128, 128, 136, 112, 0, 240, 136, 136, 136, 136, 136, 240, 0, 248, 128, 128, 240, 128, 128, 248, 0, 248, 128, 128, 240, 128, 128, 128, 0, 112, 136, 128, 184, 136, 136, 112, 0, 136, 136, 136, 248, 136, 136, 136, 0, 112, 32, 32, 32, 32, 32, 112, 0, 8, 8, 8, 8, 136, 136, 112, 0, 136, 144, 160, 192, 160, 144, 136, 0, 128, 128, 128, 128, 128, 128, 248, 0, 136, 216, 168, 168, 136, 136, 136, 0, 136, 200, 200, 168, 152, 152, 136, 0, 112, 136, 136, 136, 136, 136, 112, 0, 240, 136, 136, 240, 128, 128, 128, 0, 112, 136, 136, 136, 136, 168, 144, 104, 240, 136, 136, 240, 160, 144, 136, 0, 112, 136, 128, 112, 8, 136, 112, 0, 248, 32, 32, 32, 32, 32, 32, 0, 136, 136, 136, 136, 136, 136, 112, 0, 136, 136, 136, 136, 80, 80, 32, 0, 136, 136, 136, 168, 168, 216, 136, 0, 136, 136, 80, 32, 80, 136, 136, 0, 136, 136, 136, 112, 32, 32, 32, 0, 248, 8, 16, 32, 64, 128, 248, 0, 120, 96, 96, 96, 96, 96, 120, 0, 0, 128, 64, 32, 16, 8, 0, 0, 240, 48, 48, 48, 48, 48, 240, 0, 32, 80, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 248, 0]

# The HUD (rows 0-2), after the arcade's: a magenta band with four black
# capsules, pointed at both ends and 10 pixels tall (y 7-16, centred in the
# band): left to right the dead (a red dot), those on board (cyan) and the
# saved (bright green), each with two white digits, then the spare
# helicopters (up to four icons, right-justified). Its characters 1-13 are
# uploaded to the TOP screen third only (DEFINE VRAM), where codes below 32
# are otherwise unused; the digits are the font's and the icon is 140.
HUD_MAGENTA,HUD_BLACK=13,1
def hud_band(bits):
    return (bits,[HUD_BLACK*16+HUD_MAGENTA]*8)
HUD_DOT=[0,0x38,0x7C,0x7C,0x7C,0x38,0,0]
HUD_CHARS={'band':hud_band([0]*8),'top':hud_band([0]*7+[255]),'bottom':hud_band([255]+[0]*7),
           'left_top':hud_band([0]*7+[0x07]),
           'left':hud_band([0x1F,0x3F,0x7F,0xFF,0xFF,0x7F,0x3F,0x1F]),
           'left_bottom':hud_band([0x07]+[0]*7),
           'right_top':hud_band([0]*7+[0xE0]),
           'right':hud_band([0xF8,0xFC,0xFE,0xFF,0xFF,0xFE,0xFC,0xF8]),
           'right_bottom':hud_band([0xE0]+[0]*7),
           # Dots: medium red 8, cyan 7, light green 3, on the capsule's black.
           'dead':(HUD_DOT,[0x81]*8),'aboard':(HUD_DOT,[0x71]*8),'saved':(HUD_DOT,[0x31]*8),
           # A practice (838) game's star, white on the band, after the saved box.
           'practice':([80,32,248,32,80,0,0,0],[0xF0|HUD_MAGENTA]*8)}
HUD_CODE={name:i+1 for i,name in enumerate(HUD_CHARS)}
assert max(HUD_CODE.values())<14   # 14-31 are reserved (see CHOPLIFT.bas boot)
# (first column, dot, inner cells): the count boxes are cap, dot, two
# digits, cap; the spares box cap, four icons, cap.
HUD_BOXES=((2,'dead',3),(9,'aboard',3),(16,'saved',3),(24,None,4))
HUD_PRACTICE_COLUMN=21
def hud_rows():
    rows=[[HUD_CODE['band']]*32 for _ in range(3)]
    for first,dot,inner in HUD_BOXES:
        last=first+inner+1
        for row,end in ((0,'_top'),(1,''),(2,'_bottom')):
            rows[row][first]=HUD_CODE['left'+end];rows[row][last]=HUD_CODE['right'+end]
        for col in range(first+1,last):
            rows[0][col]=HUD_CODE['top'];rows[2][col]=HUD_CODE['bottom'];rows[1][col]=32
        if dot:
            rows[1][first+1]=HUD_CODE[dot];rows[1][first+2]=rows[1][first+3]=48
    assert rows[1][HUD_PRACTICE_COLUMN]==HUD_CODE['band']
    return sum(rows,[])
HUD_ROWS=hud_rows()

# HUD's first character is eight blank pattern rows. Colour only the middle
# two backgrounds orange, so one reused pattern draws a solid two-pixel bar.
SORTIE_BAR_COLORS=[0x11]*3+[0x19]*2+[0x11]*3
SORTIE_BAR_CELLS=[23]*10
SORTIE_TITLES=[ord(c) for line in (' FIRST SORTIE   ','SECOND SORTIE   ',
                                  ' THIRD SORTIE   ','   SORTIE 0     ')
               for c in line]
SORTIE_TITLES=SORTIE_TITLES[:-2]  # the final SCREEN copies only 14 bytes
assert len(SORTIE_TITLES)==62

# Fireworks for a perfect rescue (and the title's HOWIE code), over the
# home with the view at its east end (camera 1792). A script of rockets,
# each with a start frame, launch column and burst column (screen x of its
# 16x16 sprite), climb length, kind and colour scheme. Every rocket rises
# from behind the home's roof (y FW_LAUNCH_Y, x over the building) and flies
# a straight, slanted path to its burst point, slowing as it climbs (FW_CLIMB
# of the climb length): some nearly straight up, most fanning out west over
# the sky. Its trail is three ember sprites at its earlier positions, so the
# trail follows the angle. Every rocket climbs the same curve, so its height
# on each frame is one shared table (FW_RISE) and only its x is stored per
# rocket. Then it bursts: a core and five spark clusters, one row per two
# frames for 32 frames, from tables like the explosions' (no RAM per
# particle). Each firework draws in a group of six sprite slots
# (FW_SLOT, 2-31 in five groups), and a group is never reused while it is
# still busy, so up to five burst at once and flicker shares the crowded
# lines.
FW_ROWS=16
FW_CLIMB=[round(118*(1-(1-p/34)**2)) for p in range(35)]
FW_LAUNCH_Y=145            # sprite top: the head at the roof line (y 152)
FW_HOME_X=(146,174)        # launch columns: the head over the home's roof
FW_RAMPS={'gold':(15,11,10,6),'red':(15,9,8,6),'green':(15,3,12,12),'blue':(15,7,5,4),
          'magenta':(15,13,13,6),'silver':(15,15,14,14)}
FW_RAMP_INDEX={name:i*4 for i,name in enumerate(FW_RAMPS)}
FW_KIND_INDEX={'peony':0,'willow':FW_ROWS,'ring':2*FW_ROWS}
# (start frame, launch x, burst x, climb frames, kind, colours): ten
# openers one at a time, then the finale: a quickening salvo of five, a
# triple and a pair, another triple and pair, and a crescendo of five at
# once. Each wave waits for the groups the last one frees (fw_slots checks).
FW_SCRIPT=((0,164,176,21,'peony','gold'),(40,158,128,16,'willow','gold'),
           (70,168,186,25,'ring','blue'),(100,154,96,14,'peony','red'),
           (125,162,150,29,'peony','green'),(150,150,70,18,'ring','magenta'),
           (178,160,206,12,'willow','silver'),(205,156,118,23,'peony','blue'),
           (232,166,160,20,'ring','red'),(258,152,84,16,'willow','gold'),
           # The salvo.
           (290,154,196,25,'peony','red'),(300,160,140,20,'peony','green'),
           (310,154,100,14,'peony','blue'),(322,164,160,21,'ring','gold'),
           (334,158,124,18,'willow','silver'),
           # A triple, then a pair.
           (366,150,72,18,'peony','magenta'),(366,168,180,23,'ring','green'),
           (368,160,128,14,'willow','gold'),
           (394,166,198,20,'peony','blue'),(394,154,104,25,'peony','red'),
           # Another triple and pair.
           (430,158,150,27,'peony','silver'),(430,172,206,12,'willow','red'),
           (432,148,64,22,'ring','blue'),
           (458,162,112,16,'peony','gold'),(462,154,170,23,'peony','magenta'),
           # The crescendo.
           (528,158,128,29,'ring','gold'),(528,166,186,22,'peony','red'),
           (530,150,72,20,'peony','blue'),(530,172,206,14,'willow','silver'),
           (532,154,98,25,'peony','green'))
def fw_path(x0,bx,climb):
    """(x, y) of the rocket's sprite on each frame of its climb and, last,
    the burst point."""
    top=FW_CLIMB[climb]
    return [(round(x0+(bx-x0)*FW_CLIMB[p]/top),FW_LAUNCH_Y-FW_CLIMB[p]) for p in range(climb+1)]
FW_PATHS=[fw_path(x0,bx,climb) for _,x0,bx,climb,_,_ in FW_SCRIPT]
FW_PATH_START=[sum(len(path) for path in FW_PATHS[:k]) for k in range(len(FW_PATHS))]
FW_RISE=[FW_LAUNCH_Y-c for c in FW_CLIMB[:max(f[3] for f in FW_SCRIPT)+1]]
assert all(y==FW_RISE[p] for path in FW_PATHS for p,(_,y) in enumerate(path))
FW_TRAIL=[0,11,9,6]        # the trail's three embers, nearest first
FW_END=630        # frames: the last burst is over by then
FW_DONE=80        # frames after its start by which any firework is over and hidden
import math
def fw_burst(kind):
    """Per row: core pattern (0 none), core shade, debris pattern, debris
    shade, and five (dx, dy) offsets of the clusters from the burst."""
    rows=[]
    for row in range(FW_ROWS):
        t=2*row+1
        if kind=='peony':
            reach,g,flat,turn=40*(1-math.exp(-t/9)),0.02,1.0,90
            core=('flash',0) if row<2 else ('ring',0) if row<4 else ('ring',1) if row<6 else None
            part=('spark1' if row<3 else 'spark2' if row<9 else 'spark3' if row<13 else 'ember',
                  0 if row<3 else 1 if row<8 else 2 if row<12 else 3)
        elif kind=='willow':
            reach,g,flat,turn=30*(1-math.exp(-t/7)),0.035,1.0,90
            core=('flash',0) if row<2 else None
            part=('spark2' if row<4 else 'spark3' if row<8 else 'drop',
                  0 if row<2 else 1 if row<6 else 2 if row<11 else 3)
        else:
            reach,g,flat,turn=46*(1-math.exp(-t/8)),0.01,0.35,0
            core=('ring',0) if row<4 else ('ring',1) if row<8 else None
            part=('spark1' if row<4 else 'spark2' if row<10 else 'ember',
                  0 if row<4 else 1 if row<9 else 2 if row<13 else 3)
        offsets=[]
        for q in range(5):
            a=math.radians(turn+72*q)
            offsets.append((round(reach*math.cos(a)),round(-flat*reach*math.sin(a)+g*t*t)))
        rows.append((BLAST_SLOT[core[0]]*4 if core else 0,core[1] if core else 0,
                     BLAST_SLOT[part[0]]*4,part[1],offsets))
    return rows
FW_BURST=fw_burst('peony')+fw_burst('willow')+fw_burst('ring')
def fw_slots():
    """Each firework's first sprite slot: the first group of six (2, 8, ...
    26) free from its launch until 8 frames after its burst ends."""
    busy=[-1]*5;slots=[]
    for start,x0,bx,climb,kind,ramp in FW_SCRIPT:
        group=next(g for g in range(5) if busy[g]<start)
        busy[group]=start+climb+2*FW_ROWS+8
        slots.append(2+group*6)
    return slots
FW_SLOT=fw_slots()
for (start,x0,bx,climb,kind,ramp),path in zip(FW_SCRIPT,FW_PATHS):
    assert 0<climb<len(FW_CLIMB) and start+climb+2*FW_ROWS+8<FW_END
    assert climb+2*FW_ROWS+8<=FW_DONE
    assert FW_HOME_X[0]<=x0<=FW_HOME_X[1]          # it rises from behind the home
    x,y=path[-1]
    assert 25<=y<=80 and all(0<=px<=239 for px,_ in path)
    for r in FW_BURST[FW_KIND_INDEX[kind]:FW_KIND_INDEX[kind]+FW_ROWS]:
        for dx,dy in r[4]:
            assert 0<=x+dx<=239 and 0<y+dy<175,(start,x+dx,y+dy)
# Various angles: from nearly straight up to well over to the west.
FW_LEANS=sorted(round(math.degrees(math.atan2(x0-bx,FW_CLIMB[climb]))) for _,x0,bx,climb,_,_ in FW_SCRIPT)
assert FW_LEANS[0]<=-2 and FW_LEANS[-1]>=30 and len(set(FW_LEANS))>=10
assert all(-64<=v<64 for r in FW_BURST for xy in r[4] for v in xy)

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
    # Bottom-third characters 120-125: pad-fence cell, foothills, then horizon.
    boot += emit('low_art',PAD_FENCE_ART+[b for bits,_ in FOOT for b in bits]+HORIZON_ART)
    boot += emit('low_colors',PAD_FENCE_COLORS+[v for _,c in FOOT for v in row_colors(c)]+HORIZON_COLORS)
    boot += emit('fire_colors', FIRE_COLORS)
    boot += emit('star_bits',STAR_BITS)
    # The moon's characters, uploaded to the top screen third only.
    boot += emit('moon_art',[b for bits,_ in MOON_CELLS for b in bits])
    boot += emit('moon_colors',[c for _,colors in MOON_CELLS for c in colors])
    boot += emit('star_colors',STAR_COLORS)
    boot += emit('hud_art',[b for bits,_ in HUD_CHARS.values() for b in bits])
    boot += emit('hud_colors',[c for _,colors in HUD_CHARS.values() for c in colors])
    # A continuous orange line in character 23 of the middle screen third.
    # The title overlay uses the same ten cells above and below its text.
    boot += emit('sortie_bar_colors',SORTIE_BAR_COLORS)
    boot += emit('sortie_bar_cells',SORTIE_BAR_CELLS)
    boot += emit('sortie_titles',SORTIE_TITLES)
    boot += emit('sortie_blank_cells',[32]*14)
    # The fireworks run with the boot bank selected (their code is there too).
    FW_PAD=[0]*(len(FW_SCRIPT)%2)   # per-firework byte tables, padded even
    boot += emit('fw_climb_len',[f[3] for f in FW_SCRIPT]+FW_PAD)
    boot += emit('fw_kind',[FW_KIND_INDEX[f[4]] for f in FW_SCRIPT]+FW_PAD)
    boot += emit('fw_ramp',[FW_RAMP_INDEX[f[5]] for f in FW_SCRIPT]+FW_PAD)
    boot += emit('fw_slot',FW_SLOT+FW_PAD)
    # Every rocket's path x, one after another (#fw_path: where each begins;
    # the last point of each is its burst); y by frame is fw_rise, shared.
    pad=[0] if sum(map(len,FW_PATHS))%2 else []
    boot += emit('fw_px',[x for path in FW_PATHS for x,_ in path]+pad)
    boot += emit('fw_rise',FW_RISE+[0]*(len(FW_RISE)%2))
    boot += emit('fw_trail',FW_TRAIL)
    boot += emit('fw_colors',[c for ramp in FW_RAMPS.values() for c in ramp])
    boot += emit('fw_cpat',[r[0] for r in FW_BURST])
    boot += emit('fw_cshade',[r[1] for r in FW_BURST])
    boot += emit('fw_ppat',[r[2] for r in FW_BURST])
    boot += emit('fw_pshade',[r[3] for r in FW_BURST])
    # Five clusters per row, one after another (row*5+q), stored +64.
    boot += emit('fw_dx',[r[4][q][0]+64 for r in FW_BURST for q in range(5)])
    boot += emit('fw_dy',[r[4][q][1]+64 for r in FW_BURST for q in range(5)])
    for label,words in (('#fw_start',[f[0] for f in FW_SCRIPT]),('#fw_path',FW_PATH_START)):
        boot += label+':\n' + ''.join('    DATA '+','.join(str(v) for v in words[i:i+8])+'\n'
                                      for i in range(0,len(words),8))
    text = head
    # A crash redefines slots 13/14 as flames, then embers; a fresh crash
    # restores the full flames after the preceding ember phase.
    text += emit('crash_flames', [b for a in SPRITES[13:15] for b in sprite_bytes(a)])
    text += emit('flag_colors',FLAG_COLORS)
    for label,stage in (('crash_burn2',CRASH_STAGES[1]),('crash_burn3',CRASH_STAGES[2])):
        text += emit(label, [b for rows in stage for b in sprite_bytes(fire_sprite(rows))])
    text += emit('crash_embers', [b for rows in CRASH_EMBERS for b in sprite_bytes(fire_sprite(rows))])
    text += emit('world_map', [c for r in MAP for c in r])
    text += emit('ground_row', [129]*32)
    # The moon's 3x3 block of characters, row by row (+ a pad byte).
    text += emit('moon_cells',[MOON_CODE+i for i in range(9)]+[0])
    text += emit('fence_codes',FENCE_CODES)
    text += emit('home_fence_codes',HOME_FENCE_CODES)
    text += emit('flag_frame0', FLAG0)
    text += emit('flag_frame1', FLAG1)
    for label,field in (('blast_cpat',0),('blast_ccol',1),('blast_dpat',3),('blast_dcol',4)):
        text += emit(label,[r[field] for r in BLAST_ROWS])
    text += emit('blast_cdy',[r[2]+64 for r in BLAST_ROWS])
    text += emit('blast_fall',BLAST_FALL)
    text += emit('blast_fpat',BLAST_FPAT)
    text += emit('blast_fcol',BLAST_FCOL)
    # The three clusters' rows one after another, BLAST_STRIDE apart.
    text += emit('blast_dx',[r[5][p][0]+64 for p in range(3) for r in BLAST_ROWS])
    text += emit('blast_dy',[r[5][p][1]+64 for p in range(3) for r in BLAST_ROWS])
    text += emit('jet_arc', JET_ARC)
    text += emit('shell_arc', SHELL_ARC)
    text += emit('fire_frame0', FIRE0)
    text += emit('fire_frame1', FIRE1)
    text += emit('person_rows',PERSON_ROWS+[v>>4 for v in PERSON_ROWS]+[(v<<4)&255 for v in PERSON_ROWS])
    text += emit('crowd_bases',CROWD_BASES)
    # The bottom-third menu font lives in the boot bank (menu_restore selects
    # it around the upload); its colours (all white on black) are filled at
    # run time, not stored as 256 equal bytes.
    boot += emit('menu_font',MENU_FONT)
    text += emit('person_colors',PERSON_COLORS)
    text += emit('camp_bits',[1,2,4,8])
    text += emit('person_kind',[i%3 for i in range(64)])
    # Where the people run about (ROAM_GOALS, +128) and each one's phase.
    text += emit('roam_goal',ROAM_TABLE)
    text += emit('roam_phase',ROAM_PHASE)
    text += emit('first_out',FIRST_OUT)
    text += emit('hud_rows',HUD_ROWS)
    text += emit('star_x',STAR_X)
    # Row 0 ends the list (both renderers stop there); the second 0 keeps the
    # DATA BYTE block even so later word tables stay aligned.
    text += emit('star_row',STAR_ROW+[0,0])
    (ROOT/'src/assets.bas').write_text(text, encoding='utf-8', newline='\n')
    (ROOT/'src/assets_boot.bas').write_text(boot, encoding='utf-8', newline='\n')
    print(f'Assets: {len(SPRITES)} sprites, {len(TILES)} tiles, {sum(map(len,MAP))} map bytes')

if __name__ == '__main__': generate()
