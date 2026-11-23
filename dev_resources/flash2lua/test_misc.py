"""Small converter checks that need neither FFDec nor the demo."""
import unittest

from dev_resources.flash2lua import convert, emit_lua, swfmodel

BACKSLASH = chr(92)


class EmitStringTest(unittest.TestCase):
    def test_line_breaks_and_quotes_are_escaped(self):
        value = 'a"b' + chr(10) + "c" + chr(13) + "d" + BACKSLASH + "e"
        text = emit_lua._str(value)
        self.assertNotIn(chr(10), text)
        self.assertNotIn(chr(13), text)
        expected = '"a' + BACKSLASH + '"b' + BACKSLASH + "nc" + BACKSLASH + "rd" + BACKSLASH * 2 + 'e"'
        self.assertEqual(text, expected)


class ScriptEdgeTest(unittest.TestCase):
    def test_this_is_the_clip_itself_not_a_child(self):
        from dev_resources.flash2lua import scripts
        self.assertEqual(scripts.classify_script('this.stop();'), [{"do": "stop"}])
        self.assertEqual(scripts.classify_script('this.gotoAndStop("a");'), [{"do": "stop"}, {"do": "goto", "label": "a"}])
        self.assertEqual(scripts.classify_script('Mover.gotoAndPlay("a");'),
                         [{"do": "child", "name": "Mover", "play": True, "label": "a"}])

    def test_a_nul_before_a_digit_cannot_be_read_as_another_byte(self):
        text = emit_lua._str(chr(0) + "1")
        self.assertEqual(text, '"' + chr(92) + "000" + '1"')


class EmitChildActionTest(unittest.TestCase):
    """A frame script that plays or stops a NAMED child clip (`this.mask_02.gotoAndPlay("on")`) must be written as a "child" action.
    Written as a plain {"gotol", label} it would jump the clip's OWN timeline to a label of the same name (HUD_PDA_Map: the
    `malfunction` frame jumped to its `on` frame), or do nothing when the label is not its own."""

    def test_a_child_call_is_emitted_as_a_child_action(self):
        self.assertEqual(emit_lua._action({"do": "child", "name": "mask_02", "play": True, "label": "on"}), '{"child","mask_02",true,"on"}')
        self.assertEqual(emit_lua._action({"do": "child", "name": "Heading", "play": False, "frame": 3}), '{"child","Heading",false,3}')

    def test_the_clip_s_own_goto_is_unchanged(self):
        self.assertEqual(emit_lua._action({"do": "goto", "label": "a"}), '{"gotol","a"}')
        self.assertEqual(emit_lua._action({"do": "goto", "frame": 4}), '{"goto",4}')


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

    def test_paragraphs_are_separate_lines(self):
        text, _, _ = swfmodel.parse_html_text("<p>one</p><p>two</p>")
        self.assertEqual(text, "one" + chr(10) + "two")

    def test_a_line_break_tag_becomes_a_line_break(self):
        text, _, _ = swfmodel.parse_html_text("<p>one<br>two</p>")
        self.assertEqual(text, "one" + chr(10) + "two")


class EditTextLayoutTest(unittest.TestCase):
    """The layout attributes of a text field (multiline, word wrap, auto size, leading) are read from the SWF and
    written to the Lua data: without them the player cannot wrap or clip a text (no FFDec needed)."""
    XML = (
        '<swf frameRate="30"><displayRect Xmin="0" Xmax="20480" Ymin="0" Ymax="15360"/><tags>'
        '<item type="DefineEditTextTag" characterID="1" align="0" autoSize="false" fontHeight="240" fontId="9" '
        'html="false" initialText="a b" leading="40" multiline="true" wordWrap="true" variableName="">'
        '<bounds Xmin="-40" Xmax="2300" Ymin="-40" Ymax="740"/><textColor alpha="255" blue="255" green="255" red="255"/></item>'
        '<item type="DefineEditTextTag" characterID="2" align="2" autoSize="false" fontHeight="440" fontId="9" '
        'html="false" initialText="one" leading="0" multiline="false" wordWrap="false" variableName="">'
        '<bounds Xmin="-40" Xmax="4400" Ymin="-40" Ymax="600"/><textColor alpha="255" blue="255" green="255" red="255"/></item>'
        '<item type="DefineEditTextTag" characterID="3" align="0" autoSize="true" fontHeight="240" fontId="9" '
        'html="false" initialText="x" leading="0" multiline="false" wordWrap="false" variableName="">'
        '<bounds Xmin="0" Xmax="400" Ymin="0" Ymax="400"/><textColor alpha="255" blue="255" green="255" red="255"/></item>'
        '</tags></swf>')

    @classmethod
    def setUpClass(cls):
        import os
        import tempfile
        cls.dir = tempfile.mkdtemp()
        path = os.path.join(cls.dir, "m.xml")
        with open(path, "w", encoding="utf8") as out:
            out.write(cls.XML)
        cls.movie = swfmodel.parse_swf_xml(path)

    def test_the_attributes_are_read(self):
        wrapped, single, auto = (self.movie.characters[i] for i in (1, 2, 3))
        self.assertEqual((wrapped.multiline, wrapped.word_wrap, wrapped.auto_size, wrapped.leading), (True, True, False, 2))
        self.assertEqual((single.multiline, single.word_wrap, single.auto_size, single.leading), (False, False, False, 0))
        self.assertTrue(auto.auto_size)

    def test_only_what_matters_is_written(self):
        from dev_resources.flash2lua import lua_literal
        data = lua_literal.parse(emit_lua.emit_lua(self.movie, {}, "grymod/flash"))["chars"]
        self.assertEqual((data[1].get("ml"), data[1].get("ww"), data[1].get("ld"), data[1].get("as")), (True, True, 2, None))
        self.assertEqual((data[2].get("ml"), data[2].get("ww"), data[2].get("ld"), data[2].get("as")), (None, None, None, None))
        self.assertEqual(data[3].get("as"), True)


if __name__ == "__main__":
    unittest.main()
