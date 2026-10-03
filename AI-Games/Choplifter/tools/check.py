"""Structural gates plus executable rescue-state regression tests.

The small interpreter executes selected routines directly from the game source.
Unknown statements fail, so tests cannot silently turn into a separate model.
"""
from pathlib import Path
import re
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/CHOPLIFT.bas').read_text(encoding='utf-8')

def structure(source):
    for line in source.splitlines():
        code=line.split("'")[0]
        for m in re.finditer(r'PRINT AT (\d+),"([^"]*)"',code):
            offset=int(m[1])
            if offset//32 >= 24 or offset%32+len(m[2]) > 32:
                raise ValueError('Text crosses screen edge: '+line)
        if re.search(r'\bIF\b.*[<>=].*\b(?:AND|OR)\b.*[<>=]',code,re.I):
            raise ValueError('Unsafe compound comparison: '+line)
    if 'DIM camp_left(4)' not in source: raise ValueError('Missing four-camp array')
    if 'DIM #shot_x(2)' not in source: raise ValueError('Missing two-shot pool')
    hud=source.split('\nhud:\n',1)[1].split('\ndigits:\n',1)[0]
    template=re.search(r'PRINT AT 0,"([^"]+)"',source)[1]
    fields=[int(x)-6144 for x in re.findall(r'#digit_pos=(\d+)',hud)]
    if fields != [m.start() for m in re.finditer('00',template)]:
        raise ValueError('HUD digits must replace the three 00 placeholders')

class Basic:
    """Strict subset used by accounting routines; CVBasic byte/word wrapping."""
    def __init__(self, source=SOURCE):
        self.v={}; self.a={}; self.r={}
        self.v.update(capacity=16,landed=152)
        lines=source.splitlines()
        name=None
        for line in lines:
            m=re.match(r'^(\w+):\s*$',line)
            if m: name=m[1]; self.r[name]=[]
            elif name:
                code=line.split("'")[0].strip()
                if code:self.r[name].append(code)
    def expr(self,s):
        s=s.strip()
        s=re.sub(r'\bAND\b','&',s,flags=re.I)
        s=re.sub(r'(#?[a-z_]\w*)\(([^()]+)\)',lambda m:str(self.a[m[1]][self.expr(m[2])]),s,flags=re.I)
        s=re.sub(r'#?[a-z_]\w*(?:\.\w+)?',lambda m:str(self.v.get(m[0].lower(),0)),s,flags=re.I)
        s=s.replace('<>','!=')
        s=re.sub(r'(?<![<>=!])=(?!=)','==',s)
        if not re.fullmatch(r'[\d\s+*/%<>=!()&\-]+',s):raise ValueError('Expression '+s)
        return int(eval(s,{'__builtins__':{}},{}))
    def call(self,name):
        self.execute(self.r[name])
    def execute(self,lines):
        pc=0
        while pc<len(lines):
            line=lines[pc];pc+=1
            if line.startswith('IF '):
                cond,tail=line[3:].split(' THEN',1)
                if tail.strip():
                    halves=tail.strip().split(' ELSE ',1)
                    chosen=halves[0] if self.expr(cond) else (halves[1] if len(halves)>1 else '')
                    if chosen:
                        flow=self.statements(chosen)
                        if flow:return flow
                else:
                    depth=1; start=pc; mid=None
                    while pc<len(lines):
                        if re.match(r'IF .* THEN$',lines[pc]):depth+=1
                        if lines[pc]=='END IF':depth-=1
                        if lines[pc]=='ELSE' and depth==1:mid=pc
                        if depth==0:break
                        pc+=1
                    if depth:raise ValueError('Unterminated IF')
                    yes=lines[start:mid if mid is not None else pc]
                    no=lines[mid+1:pc] if mid is not None else []
                    flow=self.execute(yes if self.expr(cond) else no)
                    if flow:return flow
                    pc+=1
            elif line.startswith('FOR '):
                m=re.fullmatch(r'FOR (\w+)=(.+) TO (.+)',line)
                if not m:raise ValueError(line)
                start=pc
                while pc<len(lines) and not lines[pc].startswith('NEXT '):pc+=1
                if pc==len(lines):raise ValueError('Missing NEXT')
                for n in range(self.expr(m[2]),self.expr(m[3])+1):
                    self.v[m[1]]=n
                    result=self.execute(lines[start:pc])
                    if result=='exit':break
                    if result:return result
                pc+=1
            else:
                flow=self.statements(line)
                if flow:return flow
        return False
    def statements(self,line):
        for part in line.split(':'):
            part=part.strip()
            if not part:continue
            if part=='RETURN':return 'return'
            if part=='EXIT FOR':return 'exit'
            if part.startswith('GOSUB '):self.call(part[6:]);continue
            if part.startswith('SOUND '):continue
            if part.startswith('IF '):
                flow=self.execute([part])
                if flow:return flow
                continue
            m=re.fullmatch(r'(#?\w+)(?:\((.+)\))?=(.+)',part)
            if not m:raise ValueError('Unsupported statement: '+part)
            value=self.expr(m[3]) & (65535 if m[1].startswith('#') else 255)
            if m[2] is not None:self.a[m[1]][self.expr(m[2])]=value
            else:self.v[m[1].lower()]=value
        return False

class Tests(unittest.TestCase):
    def state(self):
        b=Basic();b.v.update(saved=0,lost=0,aboard=0,lives=3,dt=2,hy=152,old_y=152)
        b.a['camp_left']=[16]*4;b.a['camp_open']=[1]*4;b.a['#camp_x']=[128,384,640,896]
        b.v.update({'#hx':160,'#runner_x':172,'runner_on':1,'runner_camp':0})
        return b
    def total(self,b):
        return sum(b.a['camp_left'])+sum(b.v[x] for x in ('saved','lost','aboard'))
    def test_structure(self):structure(SOURCE)
    def test_reject_bad_cases(self):
        for bad in ('PRINT AT 31,"XX"','IF a = 1 AND b = 2 THEN a=0'):
            with self.assertRaises(ValueError):structure(SOURCE+'\n'+bad)
        with self.assertRaises(ValueError):Basic().execute(['MYSTERY 1'])
        with self.assertRaises(ValueError):structure(SOURCE.replace('#digit_pos=6161','#digit_pos=6160'))
    def test_board_and_capacity(self):
        b=self.state();b.call('people_tick')
        self.assertEqual((b.v['aboard'],b.a['camp_left'][0],b.v['runner_on']),(1,15,0))
        self.assertEqual(self.total(b),64)
        b=self.state();b.v['aboard']=16;b.a['camp_left'][1]=0
        b.call('people_tick');self.assertEqual(b.v['aboard'],16);self.assertEqual(self.total(b),64)
    def test_unload_only_at_pad(self):
        for x,want in ((1160,0),(1192,1),(1240,0)):
            b=self.state();b.v.update({'#hx':x,'aboard':16,'runner_on':0,'transfer_timer':0})
            b.a['camp_left']=[0,16,16,16]
            b.call('people_tick');self.assertEqual(b.v['saved'],want);self.assertEqual(self.total(b),64)
    def test_crash_and_repeated_collision(self):
        b=self.state();b.v.update(aboard=9,invuln=0,crash_timer=0);b.a['camp_left'][0]=7
        b.call('crash');b.call('crash')
        self.assertEqual((b.v['lost'],b.v['aboard'],b.v['lives']),(9,0,2))
        self.assertEqual(self.total(b),64)
    def test_landing_casualty(self):
        b=self.state();b.v['old_y']=150;b.call('people_tick')
        self.assertEqual((b.v['lost'],b.v['aboard']),(1,0));self.assertEqual(self.total(b),64)
    def test_all_64_can_be_saved(self):
        b=self.state()
        for camp in range(4):
            for person in range(16):
                b.v.update({'#hx':160,'#runner_x':172,'runner_on':1,'runner_camp':camp,'transfer_timer':0})
                b.call('people_tick');self.assertEqual(self.total(b),64)
            self.assertEqual(b.v['aboard'],16)
            b.v.update({'#hx':1192,'runner_on':0})
            for person in range(16):
                b.v['transfer_timer']=0;b.call('people_tick');self.assertEqual(self.total(b),64)
        self.assertEqual((b.v['saved'],b.v['lost'],b.v['aboard']),(64,0,0))
    def test_accounting_mutation_fails(self):
        bad=SOURCE.replace('aboard=aboard+1','aboard=aboard+2')
        b=self.state();b.r=Basic(bad).r;b.call('people_tick')
        self.assertNotEqual(self.total(b),64)
    def test_camp_lookup_and_spawn(self):
        b=self.state();self.assertEqual(b.expr('#camp_x(1)'),384)
        b.v.update({'#hx':400,'runner_on':0,'transfer_timer':0})
        b.call('people_tick')
        self.assertEqual((b.v['runner_on'],b.v['runner_camp'],b.v['#runner_x']),(1,1,396))
    def test_tank_rate_across_frame_deltas(self):
        for dt in (1,2,3,4,6):
            b=self.state();b.v.update({'#hx':500,'#tank_x':100,'#tank_wait':60000,'#elapsed':dt,'dt':dt})
            for _ in range(60//dt):b.call('tank_tick')
            self.assertEqual(b.v['#tank_x'],115)
    def test_flight_rate_and_braking(self):
        for dt in (1,2,3,4,6):
            b=self.state();b.v.update({'#hx':500,'hy':100,'dt':dt,'hspeed':3,'hdir':0,'cont1.right':1})
            for _ in range(60//dt):b.call('fly')
            self.assertEqual(b.v['#hx'],680)
            b.v['cont1.right']=0
            for _ in range(4):b.call('fly')
            self.assertEqual((b.v['hspeed'],b.v['face']),(0,2))
    def test_open_barrack_and_destroy_tank(self):
        b=self.state();b.a.update({'#shot_x':[128,0],'shot_y':[144,0],'shot_dir':[2,0],'shot_on':[1,0]})
        b.a['camp_open']=[0]*4
        b.call('move_shot')
        self.assertEqual((b.a['camp_open'][0],b.a['shot_on'][0]),(1,0))
        b.v.update({'tank_on':1,'#tank_x':128,'runner_on':0})
        b.a['shot_on'][0]=1;b.a['shot_y'][0]=152
        b.call('move_shot')
        self.assertEqual((b.v['tank_on'],b.a['shot_on'][0]),(0,0))
    def test_ground_and_world_limits(self):
        for x,control,expected in ((17,'cont1.left',16),(1239,'cont1.right',1240)):
            b=self.state();b.v.update({'#hx':x,'hy':100,'dt':6,'hspeed':3,'hdir':int('left' in control),control:1})
            b.call('fly');self.assertEqual(b.v['#hx'],expected)
        b=self.state();b.v.update({'hy':151,'cont1.down':1,'cont1.right':1,'hspeed':3})
        b.call('fly');self.assertEqual((b.v['hy'],b.v['hspeed'],b.v['#hx']),(152,0,160))
    def test_assets(self):
        sys.path.insert(0,str(ROOT/'assets'))
        import generate as art
        self.assertEqual(len(art.SPRITES),20)
        self.assertEqual([len(art.sprite_bytes(a)) for a in art.SPRITES],[32]*20)
        self.assertEqual(len(art.TILES),16)
        self.assertTrue(all(len(bits)==8 for bits,_ in art.TILES))
        self.assertEqual([len(row) for row in art.MAP],[160]*5)
        for col in (16,48,80,112):self.assertEqual(art.MAP[3][col],135)
        self.assertEqual(art.MAP[4][151],138)
        self.assertNotEqual(art.SPRITES[0],art.SPRITES[2])

if __name__=='__main__':unittest.main()
