"""The final routine, continuation words and padding must be accounted for."""
import tempfile
import unittest
from pathlib import Path
from romprofile import collect


class ProfileTest(unittest.TestCase):
    def test_final_routine_and_bank_padding(self):
        listing = ("   1 A000 1234     data 1\n"
                   "   2               cvb_LAST\n"
                   "   3 A002 C800     mov r0,@foo\n"
                   "     A004 2100\n"
                   "   4      5FF8     BANK_0_FREE: EQU >fffe-$\n"
                   "   5 A006 FFFF     data >ffff\n"
                   "   6               cvb_BANK\n"
                   "   7 A100 1234     data 1\n")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'listing.txt'
            path.write_text(listing)
            self.assertEqual(collect(path), [(0xA000, '<runtime>'),
                                             (0xA002, 'cvb_LAST'),
                                             (0xA006, '<end>')])


if __name__ == '__main__':
    unittest.main()
