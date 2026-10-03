"""Editable TMS9918 scenery. Every eight-pixel row uses at most two inks."""
from pathlib import Path
import re
import argparse

SOURCE = Path(__file__).resolve().parent.parent / 'src/HARDHAT.bas'


def canvas(w, h, color=1):
    return [[color]*w for _ in range(h)]


def rect(im, x0, y0, x1, y1, color):
    for y in range(y0, y1+1):
        for x in range(x0, x1+1): im[y][x] = color


def encode(im):
    pat, col = [], []
    for ty in range(0, len(im), 8):
        for tx in range(0, len(im[0]), 8):
            for y in range(ty, ty+8):
                row = im[y][tx:tx+8]
                inks = sorted(set(row))
                assert len(inks)<=2, ('three inks in character row',tx,y,row)
                bg, fg = (inks[0], inks[-1]) if len(inks)==2 else (1,inks[0])
                pat.append(sum(128>>x for x,c in enumerate(row) if c==fg))
                col.append(fg*16+bg)
    return pat,col


def tables():
    out={}
    # Blue cabinet, white perimeter, a gridded window and framed red door.
    cabinet=canvas(32,32,4)
    rect(cabinet,0,0,31,0,15);rect(cabinet,0,31,31,31,15)
    rect(cabinet,0,0,0,31,15);rect(cabinet,31,0,31,31,15)
    rect(cabinet,8,3,23,10,15);rect(cabinet,9,4,22,9,4)
    for x in (12,16,20):rect(cabinet,x,4,x,9,15)
    rect(cabinet,9,7,22,7,15)
    rect(cabinet,8,13,23,29,15);rect(cabinet,9,14,22,28,6)
    rect(cabinet,20,20,21,21,15)
    bucket=canvas(16,8)
    # Single broad bucket: white rim, magenta walls, open dark interior.
    rect(bucket,1,0,14,0,15);rect(bucket,0,1,0,5,15);rect(bucket,15,1,15,5,15)
    rect(bucket,1,2,1,5,15);rect(bucket,14,2,14,5,15)
    rect(bucket,2,2,13,5,13);rect(bucket,1,6,14,6,15);rect(bucket,2,7,13,7,13)
    # Keep the outside portions black; edge scanlines have white/black only.
    for y in range(2,6):
        bucket[y]=[15,15]+[13]*12+[15,15]
    axle=canvas(16,16)
    for y,span in enumerate((None,(5,10),(3,12),(2,13),(1,14),(1,14),(1,14),(1,14),
                             (1,14),(1,14),(1,14),(1,14),(2,13),(3,12),(5,10),None)):
        if span:
            lo,hi=span
            for x in range(lo,hi+1):axle[y][x]=15 if y in (2,3,12,13) else 13
    for y in range(5,11):
        axle[y]=[1,15,15]+[1]*10+[15,15,1]
        for x in range(5,11):axle[y][x]=15
    # Twelve-pixel lunch pail, occupying two character rows. Bottom remains
    # at the original floor so its enlargement cannot eat the supporting beam.
    pail=canvas(16,16)
    rect(pail,6,4,9,4,15);rect(pail,5,5,5,6,15);rect(pail,10,5,10,6,15)
    rect(pail,1,7,14,7,15);rect(pail,0,8,15,8,15)
    for y in range(9,15):pail[y]=[15]+[6]*14+[15]
    rect(pail,0,15,15,15,15)
    beat=[]
    for depth in range(4):
        im=canvas(16,16)
        rect(im,3,0,12,1,15)
        rect(im,7,2,8,6+depth,15)
        rect(im,2,7+depth,13,8+depth,15)
        rect(im,3,12,12,13,3);rect(im,1,14,14,15,15)
        beat.append(im)
    label=canvas(16,16)
    letters=('111001001','010001101','010001011','010001001','111001001')
    for y,row in enumerate(letters):
        for x,c in enumerate(row,3):
            if c=='1':label[y][x]=15
    rect(label,7,7,8,10,15)
    for y,lo,hi in ((10,4,11),(11,5,10),(12,6,9),(13,7,8)):rect(label,lo,y,hi,y,15)
    # 96-111 cabinet, 112-113 bucket, 114-117 axle, 118-119 pail top,
    # 120-123 beating machine, 124-127 flashing IN and down-arrow.
    parts=[cabinet,bucket,axle,pail[:8],beat[0],label]
    out['fixture_pat']=[];out['fixture_col']=[]
    for im in parts:
        p,c=encode(im);out['fixture_pat']+=p;out['fixture_col']+=c
    out['pail_pat'],out['pail_col']=encode(pail[8:])
    out['beat_pat']=[]
    for im in beat:out['beat_pat']+=encode(im)[0]
    # Beat changes both art and color: head whites follow its displacement.
    out['beat_col']=[]
    for im in beat:out['beat_col']+=encode(im)[1]
    out['inflash_pat']=encode(label)[0]+[0]*32
    # Restore the title credit's three lowercase glyphs after scenery used
    # their codes. These are the compiler font's original a/d/n patterns.
    out['credit_pat']=[0,0,0x68,0x98,0x88,0x98,0x68,0,
                      8,8,0x68,0x98,0x88,0x98,0x68,0,
                      0,0,0xb0,0xc8,0x88,0x88,0x88,0]
    out['credit_col']=[0xf1]*8
    # Closed oval processors: no lettering or fake opening painted on the body.
    machine=canvas(40,16)
    bounds=[(14,25),(9,30),(6,33),(4,35),(2,37),(1,38),(0,39),(0,39),
            (0,39),(0,39),(1,38),(2,37),(4,35),(6,33),(9,30),(14,25)]
    for y,(lo,hi) in enumerate(bounds):
        for x in range(lo,hi+1):machine[y][x]=15 if y<2 or y>13 or x<lo+2 or x>hi-2 else 3
        # Edge cells retain a clean white outline against black, using two inks.
        for tx in range(0,40,8):
            if len(set(machine[y][tx:tx+8]))>2:
                for x in range(tx,tx+8):
                    if machine[y][x]==3:machine[y][x]=15
    out['machine_art'],out['machine_col']=encode(machine)
    # Block fill/outline layers share the exact eight-by-eight silhouette.
    for name,outline in (('brick_bitmap',False),('brick_edge',True)):
        out[name]=[''.join('X' if (4<=x<12 and 4<=y<12 and
                     ((x in (4,11) or y in (4,11))==outline)) else '.'
                     for x in range(16)) for y in range(16)]
    return out


def rewrite(source):
    for label,data in tables().items():
        if label in ('brick_bitmap','brick_edge'):
            body=''.join('\tBITMAP "'+r+'"\n' for r in data)
        else:
            body=''.join('\tDATA BYTE '+','.join('$%02X'%v for v in data[i:i+8])+'\n'
                         for i in range(0,len(data),8))
        body=label+":\n\t' Generated by assets/genfixtures.py; edit the generator.\n"+body
        source,n=re.subn(r'^'+label+r':\n.*?(?=^\w+:)',lambda m:body,source,flags=re.M|re.S)
        assert n==1, 'missing/duplicate '+label
    # Shared block and riveted/ordinary girder appearances, from one definition.
    for label in ('tile_pat','tile_col','item_pat','item_col','beamshift_col'):
        m=re.search(r'^'+label+r':\n.*?(?=^\w+:)',source,re.M|re.S)
        lines=[line.split("'")[0] for line in m[0].splitlines()]
        data=[int(v[1:],16) for v in re.findall(r'\$[0-9A-F]{2}','\n'.join(lines))]
        if label=='tile_pat':
            data[:40]=([255,255,255,231,231,255,255,0]+[255,255,255,231,231,255,255,255]*2+
                       [255,129,129,129,129,129,129,255]+[255,255,255,231,231,255,255,0])
        elif label=='tile_col':
            data[8:16]=[0x41,0x31,0x31,0x34,0x34,0x31,0x31,0x41]
            data[24:32]=[0xf1]+[0xf6]*6+[0xf1]
            data[32:40]=data[:8]
        elif label=='item_pat':data[:8]=[255,129,129,129,129,129,129,255]
        elif label=='item_col':data[:8]=[0xf1]+[0xf6]*6+[0xf1]
        else:
            beam=[0x41,0x31,0x31,0x34,0x34,0x31,0x31,0x41];data=[]
            for lower in (False,True):
                for offset in range(8):
                    shifted=[0x11]*offset+beam+[0x11]*(8-offset)
                    data+=shifted[8:] if lower else shifted[:8]
        body=label+":\n\t' Generated by assets/genfixtures.py (spring halves also genconveyors.py).\n"
        for i in range(0,len(data),8):
            if label in ('tile_pat','tile_col') and i==72:
                body+="\t' 137/138 springboard idle halves; generated by assets/genconveyors.py.\n"
            body+='\tDATA BYTE '+','.join('$%02X'%v for v in data[i:i+8])+'\n'
        source=source[:m.start()]+body+source[m.end():]
    return source


def check(source):
    assert rewrite(source)==source,'fixture art stale; run genfixtures.py --write'
    assert len(tables()['fixture_pat'])==32*8
    broken=source.replace('machine_art:\n','machine_art:\n\tDATA BYTE 0\n',1)
    assert rewrite(broken)!=broken,'corrupt fixture table accepted'


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--write',action='store_true')
    args=parser.parse_args();source=SOURCE.read_text(encoding='utf-8')
    if args.write:
        source=rewrite(source);SOURCE.write_bytes(source.encode('utf-8'))
    check(source)
    print('Fixtures: two-ink rows, shared blocks/girders and generated data verified')
