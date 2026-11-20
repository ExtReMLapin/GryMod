"""Tests of the frame script classifier (no FFDec needed: it works on the ActionScript text)."""
import unittest

from tools.flash2lua import swfmodel


class ClassifyScriptTest(unittest.TestCase):
    def test_stop_and_play_at_the_top_level(self):
        self.assertEqual(swfmodel.classify_script("stop();"), [{"do": "stop"}])
        self.assertEqual(swfmodel.classify_script("play();"), [{"do": "play"}])

    def test_stop_before_other_calls_is_kept(self):
        text = "stop();\n_root.updateAmmoMode();\n_root.setHealth(_root.m_fHealth);\n"
        self.assertEqual(swfmodel.classify_script(text), [{"do": "stop"}])

    def test_goto_with_a_label_or_a_frame(self):
        self.assertEqual(swfmodel.classify_script('gotoAndStop("on2");'),
                         [{"do": "stop"}, {"do": "goto", "label": "on2"}])
        self.assertEqual(swfmodel.classify_script("gotoAndPlay(1);"),
                         [{"do": "play"}, {"do": "goto", "frame": 1}])

    def test_a_call_on_a_named_child_clip(self):
        text = 'this.Player.gotoAndPlay("malfunction");\n'
        self.assertEqual(swfmodel.classify_script(text),
                         [{"do": "child", "name": "Player", "play": True, "label": "malfunction"}])
        text = "this.Heading.gotoAndStop(3);"
        self.assertEqual(swfmodel.classify_script(text),
                         [{"do": "child", "name": "Heading", "play": False, "frame": 3}])

    def test_statements_inside_blocks_are_not_top_level(self):
        text = 'if(_root.SkipSequence == true)\n{\n   gotoAndStop("on2");\n   stop();\n}\n'
        self.assertIsNone(swfmodel.classify_script(text))

    def test_a_return_makes_later_play_and_goto_unreliable_but_not_stop(self):
        text = 'if(a)\n{\n   return undefined;\n}\nplay();\n'
        self.assertIsNone(swfmodel.classify_script(text))
        text = 'stop();\nif(a)\n{\n   return undefined;\n}\nplay();\n'
        self.assertEqual(swfmodel.classify_script(text), [{"do": "stop"}])

    def test_the_colour_script_still_works_with_a_stop_after_it(self):
        text = ("var color1 = new Color(_root.Text.Colorset);\nvar color2 = new Color(this.NumberText);\n"
                "color2.setRGB(color1.getRGB());\nif(updateColor)\n{\n   updateColor();\n}\nstop();\n")
        self.assertEqual(swfmodel.classify_script(text),
                         [{"do": "color", "theme": "Text", "target": "NumberText"}, {"do": "stop"}])

    def test_function_definitions_and_other_code_are_not_actions(self):
        self.assertIsNone(swfmodel.classify_script("setHealth = function(v)\n{\n   stop();\n};\n"))
        self.assertIsNone(swfmodel.classify_script("_root.Malfunction = 0;\n"))

    def test_text_in_strings_and_comments_does_not_count(self):
        self.assertIsNone(swfmodel.classify_script('var s = "stop();";\n// play();\n'))


if __name__ == "__main__":
    unittest.main()
