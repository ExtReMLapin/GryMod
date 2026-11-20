"""Small converter checks that need neither FFDec nor the demo."""
import unittest

from tools.flash2lua import convert, emit_lua

BACKSLASH = chr(92)


class EmitStringTest(unittest.TestCase):
    def test_line_breaks_and_quotes_are_escaped(self):
        value = 'a"b' + chr(10) + "c" + chr(13) + "d" + BACKSLASH + "e"
        text = emit_lua._str(value)
        self.assertNotIn(chr(10), text)
        self.assertNotIn(chr(13), text)
        expected = '"a' + BACKSLASH + '"b' + BACKSLASH + "nc" + BACKSLASH + "rd" + BACKSLASH * 2 + 'e"'
        self.assertEqual(text, expected)


class MovieNameTest(unittest.TestCase):
    def test_a_movie_name_cannot_leave_the_output_folders(self):
        for bad in ("../x", ".." + BACKSLASH + "x", "a/b", "", "x.swf", "x y"):
            with self.assertRaises(ValueError, msg=bad):
                convert.check_movie_name(bad)
        self.assertEqual(convert.check_movie_name("HUD_AmmoHealthEnergySuit"), "HUD_AmmoHealthEnergySuit")


if __name__ == "__main__":
    unittest.main()
