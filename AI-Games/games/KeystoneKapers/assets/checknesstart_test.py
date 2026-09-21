import unittest
import checknesstart as gate

class StartTest(unittest.TestCase):
    def test_production_and_review_starts(self):
        assembly = 'cvb_KLV: equ $6e\ncvb_KLSC: equ $034d\ncvb_KLX: equ $6f\n'
        basic = ''.join('\n'+start+':\n GOSUB start_krook\n'+end+':\n' for start,end in
                        (('new_game','start_krook'),('do_catch','bonus_count'),('lose_kop','snd_off')))
        rom = bytes.fromhex('a900856ea9078d4d03a978856f')
        gate.check(assembly,rom,basic)
        for index, value in ((1,1),(5,5),(10,0)):
            bad=bytearray(rom);bad[index]=value
            with self.assertRaises(ValueError): gate.check(assembly,bad,basic)
        for label in ('new_game','do_catch','lose_kop'):
            bad=basic.replace(label+':\n GOSUB start_krook',label+':\n GOSUB review_start')
            with self.assertRaises(ValueError): gate.check(assembly,rom,bad)

if __name__ == '__main__':
    unittest.main()
