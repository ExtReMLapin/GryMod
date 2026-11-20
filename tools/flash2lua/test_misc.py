"""Small converter checks that need neither FFDec nor the demo."""
import unittest

from tools.flash2lua import convert, emit_lua, swfmodel

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


class HtmlTextTest(unittest.TestCase):
    def test_tags_are_removed_and_alignment_and_colour_are_read(self):
        html = ('<p align="center"><font face="Agency FB" size="11" color="#5fbf7f" letterSpacing="0.000000" '
                'kerning="1"><b>X02 &amp; more</b></font></p>')
        text, align, color = swfmodel.parse_html_text(html)
        self.assertEqual(text, "X02 & more")
        self.assertEqual(align, 2)
        self.assertEqual(color, (0x5f, 0xbf, 0x7f, 255))

    def test_an_empty_paragraph_and_plain_text(self):
        self.assertEqual(swfmodel.parse_html_text('<p align="left"></p>'), ("", 0, None))
        self.assertEqual(swfmodel.parse_html_text("plain"), ("plain", None, None))
        self.assertEqual(swfmodel.parse_html_text(""), ("", None, None))

    def test_a_line_break_tag_becomes_a_line_break(self):
        text, _, _ = swfmodel.parse_html_text("<p>one<br>two</p>")
        self.assertEqual(text, "one" + chr(10) + "two")


if __name__ == "__main__":
    unittest.main()
