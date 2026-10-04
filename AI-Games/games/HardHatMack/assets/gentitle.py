"""Editable pixel title; --write regenerates its TMS9918 tiles and name table."""
import argparse
from pathlib import Path
import re

SOURCE = Path(__file__).resolve().parent.parent / 'src/HARDHAT.bas'
FONT = {
    'H': ['10001','10001','10001','11111','10001','10001','10001'],
    'A': ['01110','11011','11011','11111','11011','11011','11011'],
    'R': ['11110','11011','11011','11110','11100','11010','11011'],
    'D': ['11110','11011','11011','11011','11011','11011','11110'],
    'T': ['11111','11111','00100','00100','00100','00100','00100'],
    'M': ['10001','11011','11111','10101','10001','10001','10001'],
    'C': ['01111','11000','11000','11000','11000','11000','01111'],
    'K': ['11011','11010','11100','11100','11110','11011','11011'],
}
COMPACT = {
    'H':['101','101','101','111','101','101','101'],
    'A':['010','101','101','111','101','101','101'],
    'R':['110','101','101','110','101','101','101'],
    'D':['110','101','101','101','101','101','110'],
    'T':['111','010','010','010','010','010','010'],
}


def artwork():
    px = [[1]*256 for _ in range(192)]
    def dot(x,y,c):
        assert 0<=x<256 and 0<=y<192
        px[y][x]=c
    def box(x,y,w,h,c):
        for yy in range(y,y+h):
            for xx in range(x,x+w):dot(xx,yy,c)
    def word(text,y,height,palette,font,positions,width=8):
        for char,x in zip(text,positions):
            for row,line in enumerate(font[char]):
                for col,bit in enumerate(line):
                    if bit=='1':
                        for dy in range(height):
                            for dx in range(width):
                                xx=x+col*width+dx
                                dot(xx,y+row*height+dy,palette(xx,row*height+dy))
    # Matching gold gradients on both lines, with strong black counters.
    def shade(x,y,upper,lower,start,span=6):
        # Ordered dither gives the broad lettering a gradual metallic shade.
        if y<start:return upper
        if y>=start+span:return lower
        threshold=((0,8,2,10),(12,4,14,6),(3,11,1,9),(15,7,13,5))[y&3][x&3]
        return lower if threshold*span<16*(y-start) else upper
    word('HARDHAT',40,4,lambda x,y:shade(x,y,15,11,0,13) if y<13 else shade(x,y,11,10,13,14),
         COMPACT,(16,48,80,112,152,184,216))
    word('MACK',76,5,lambda x,y:shade(x,y,15,11,0,17) if y<17 else shade(x,y,11,10,17,17),
         FONT,(70,100,130,160),width=5)
    # Restore MACK's original 115x35 outline. Edge cells need black as one
    # of their two inks; keep their silhouette and choose the dominant shade.
    # Fully filled scanlines retain the two-ink ordered yellow dither.
    for y in range(76,111):
        for x in range(64,192,8):
            line=px[y][x:x+8]
            if 1 in line and len(set(line))>2:
                inks=set(line)-{1}
                ink=max(sorted(inks),key=line.count)
                px[y][x:x+8]=[1 if c==1 else ink for c in line]
    # Steel cap, side scaffold, and a riveted girder supporting Mack's sprite.
    box(16,25,224,1,14)
    for x in (8,240):
        box(x,40,2,88,4);box(x+5,40,2,88,4)
        for y in range(44,124,16):
            for step in range(6):dot(x+step,y+step,4)
    for y,color in ((128,15),(129,11),(130,10),(131,10),(132,10),(133,10),(134,4),(135,4)):
        box(16,y,224,1,color)
    # Same paired rivet columns as level one, with plain stretches between.
    for column in (4,5,11,12,17,18,24,25):box(column*8+3,131,2,2,1)
    # Hanging hook and a stack of steel blocks, clear of the title lettering.
    box(144,40,1,29,14)
    box(141,68,1,5,14);box(141,72,7,1,14);box(147,67,1,6,14)
    for y,x,w in ((120,184,24),(112,192,16)):
        box(x,y,w,1,15);box(x,y+1,w,5,6)
        for xx in range(x+3,x+w,8):box(xx,y+3,2,1,1)
    return px


def tables():
    px=artwork();tiles=[];screen=[]
    for row in range(24):
        for col in range(32):
            patterns=[];colors=[]
            for y in range(row*8,row*8+8):
                line=px[y][col*8:col*8+8]
                inks=set(line)
                assert len(inks)<=2, ('more than two colors per cell row',row,col,y,inks)
                bg=1 if 1 in inks else min(inks)
                fg=next(iter(inks-{bg}),bg)
                patterns.append(sum(128>>x for x,c in enumerate(line) if c==fg and c!=bg))
                colors.append(fg*16+bg)
            if not any(patterns) and all(c==17 for c in colors):screen.append(32);continue
            tile=tuple(patterns+colors)
            if tile not in tiles:tiles.append(tile)
            screen.append(128+tiles.index(tile))
    assert 1<=len(tiles)<=128, ('title exceeds character budget',len(tiles))
    return {'title_pat':[b for tile in tiles for b in tile[:8]],
            'title_col':[b for tile in tiles for b in tile[8:]],'title_map':screen}


def rewrite(source):
    data=tables()
    for kind in ('CHAR','COLOR'):
        source,n=re.subn(r'DEFINE '+kind+r' 128,\d+,title_',
                         'DEFINE '+kind+' 128,%d,title_'%(len(data['title_pat'])//8),source)
        assert n==1
    for label,values in data.items():
        lines=[label+':',"\t' Generated by assets/gentitle.py; edit the generator."]
        for i in range(0,len(values),16):
            lines.append('\tDATA BYTE '+','.join('$%02X'%v for v in values[i:i+16]))
        source,n=re.subn(r'^'+label+r':\n.*?(?=^\w+:)',lambda m:'\n'.join(lines)+'\n',source,flags=re.M|re.S)
        assert n==1, 'missing/duplicate title data '+label
    return source


def check(source):
    assert rewrite(source)==source, 'title art stale; run gentitle.py --write'
    data=tables();count=len(data['title_pat'])//8
    assert len(data['title_col'])==count*8 and len(data['title_map'])==768
    assert all(v==32 or 128<=v<128+count for v in data['title_map'])
    px=artwork()
    marked={c for c in range(2,30) if 1 in px[131][c*8:c*8+8]}
    assert marked=={4,5,11,12,17,18,24,25}, 'title girder lost spaced rivet pairs'
    # Preserve the earlier 5x5-scaled MACK outline, independently of coloring.
    expected={(x+col*5+dx,76+row*5+dy)
              for char,x in zip('MACK',(70,100,130,160))
              for row,line in enumerate(FONT[char]) for col,bit in enumerate(line)
              if bit=='1' for dx in range(5) for dy in range(5)}
    actual={(x,y) for y in range(76,111) for x in range(16,240) if px[y][x]!=1}
    assert actual==expected, 'MACK title outline resized or damaged'
    assert {px[y][x] for x,y in actual}=={15,11,10}, 'MACK lost the gold gradient'
    assert any(len(set(px[y][x:x+8]))==2 and 1 not in px[y][x:x+8]
               for y in range(76,111) for x in range(64,192,8)), 'MACK lost its two-ink dithering'
    # Score and control rows must stay blank until text is drawn there.
    for row in (0,1,18,20,21,23):
        assert data['title_map'][row*32:(row+1)*32]==[32]*32
    broken=source.replace('title_pat:\n','title_pat:\n\tDATA BYTE 0\n',1)
    assert rewrite(broken)!=broken, 'stale title data accepted'


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--write',action='store_true')
    args=ap.parse_args();source=SOURCE.read_text(encoding='utf-8')
    if args.write:
        source=rewrite(source)
        with SOURCE.open('w',encoding='utf-8',newline='\n') as out:out.write(source)
    check(source)
    print('Title: generated art matches; %d/128 characters; clear score/controls; corruption rejected'%(len(tables()['title_pat'])//8))
