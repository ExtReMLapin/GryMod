"""Tests for the SWF model parser. They need FFDec and the demo's HUD SWF files:
set FFDEC and SWF_DIR, or keep the research dump at its default place. Skipped otherwise."""
import os
import subprocess
import tempfile
import unittest

from tools.flash2lua import swfmodel

FFDEC = os.environ.get("FFDEC", r"D:\dev\crysis-hud-research\ffdec\ffdec-cli.exe")
SWF_DIR = os.environ.get("SWF_DIR", r"D:\dev\crysis-hud-research\extracted\Libs\UI")
SWF = os.path.join(SWF_DIR, "HUD_AmmoHealthEnergySuit.swf")


def find_named(movie, name):
    """Depth-first search of the first placed child with this instance name."""
    seen = set()

    def walk(timeline):
        for frame in timeline.frames:
            for op in frame.ops:
                if op["op"] != "place":
                    continue
                if op["name"] == name:
                    return op["char"]
                ch = movie.characters.get(op["char"]) if op["char"] else None
                if ch is not None and ch.kind == "sprite" and ch.id not in seen:
                    seen.add(ch.id)
                    found = walk(ch.timeline)
                    if found:
                        return found
        return None

    return find_named_result(movie, walk(movie.root))


def find_named_result(movie, char_id):
    return movie.characters.get(char_id) if char_id else None


@unittest.skipUnless(os.path.exists(FFDEC) and os.path.exists(SWF), "FFDec / demo SWF not available")
class SwfModelTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        xml = os.path.join(cls.tmp, "hud.xml")
        swfmodel.swf_to_xml(FFDEC, SWF, xml)
        scripts = os.path.join(cls.tmp, "scripts")
        swfmodel.export_scripts(FFDEC, SWF, scripts)
        cls.movie = swfmodel.parse_swf_xml(xml, scripts)

    def test_stage_is_1024x768_30fps(self):
        self.assertEqual(self.movie.width_px, 1024)
        self.assertEqual(self.movie.height_px, 768)
        self.assertEqual(self.movie.frame_rate, 30.0)

    def test_root_places_clip_241_named_Root(self):
        op = self.movie.root.frames[0].ops[0]
        self.assertEqual((op["op"], op["depth"], op["char"], op["name"]), ("place", 1, 241, "Root"))
        a, b, c, d, tx, ty = op["matrix"]
        self.assertAlmostEqual(a, 0.79889, places=4)
        self.assertAlmostEqual(d, 0.79999, places=4)
        self.assertAlmostEqual(b, 0.04187, places=4)
        self.assertAlmostEqual(tx, 16146 / 20)
        self.assertAlmostEqual(ty, 12333 / 20)

    def test_sprite_6_has_one_frame_with_char_5_at_depth_2(self):
        sprite = self.movie.characters[6]
        self.assertEqual(sprite.kind, "sprite")
        self.assertEqual(len(sprite.timeline.frames), 1)
        op = sprite.timeline.frames[0].ops[0]
        self.assertEqual((op["depth"], op["char"]), (2, 5))
        self.assertEqual(op["matrix"], (1.0, 0.0, 0.0, 1.0, 0.0, 0.0))

    def test_shape_5_has_bounds_in_pixels(self):
        shape = self.movie.characters[5]
        self.assertEqual(shape.kind, "shape")
        self.assertEqual(shape.bounds, (-56 / 20, 144 / 20, 4828 / 20, 2732 / 20))

    def test_labels_found(self):
        cloak = self.movie.characters[38]
        labels = [f.label for f in cloak.timeline.frames if f.label]
        self.assertIn("normal", labels)
        self.assertEqual(cloak.timeline.frames[0].label, "normal")

    def test_bar_sprites_have_100_frames(self):
        self.assertEqual(len(find_named(self.movie, "HealthBar").timeline.frames), 100)
        self.assertEqual(len(find_named(self.movie, "EnergyBar").timeline.frames), 100)

    def test_colour_transform_mult_terms_are_fractions(self):
        cloak = self.movie.characters[38]
        cx = [op["cxform"] for f in cloak.timeline.frames for op in f.ops
              if op["op"] == "place" and op["cxform"]]
        self.assertTrue(cx)
        self.assertAlmostEqual(cx[0][3], 228 / 256)  # alpha multiplier
        self.assertEqual(cx[0][:3], (1.0, 1.0, 1.0))

    def test_remove_object_op(self):
        removes = [op for ch in self.movie.characters.values() if ch.kind == "sprite"
                   for f in ch.timeline.frames for op in f.ops if op["op"] == "remove"]
        self.assertTrue(removes)
        self.assertIn("depth", removes[0])

    def test_simple_actions_are_decoded(self):
        cloak = self.movie.characters[38]
        self.assertEqual(cloak.timeline.frames[0].actions, [{"do": "play"}])

    def test_unknown_action_is_flagged_not_dropped(self):
        flagged = [a for ch in self.movie.characters.values() if ch.kind == "sprite"
                   for f in ch.timeline.frames for a in f.actions if "unsupported" in a]
        for a in flagged:
            self.assertIsInstance(a["unsupported"], str)

    def test_rectangle_shape_has_a_polygon(self):
        shape = self.movie.characters[15]
        px = lambda *v: tuple(c / 20 for c in v)
        self.assertEqual(shape.polygon, [px(29, -58), px(29, 318), px(2829, 318), px(2829, -58)])

    def test_curved_shape_has_no_polygon(self):
        self.assertIsNone(self.movie.characters[100].polygon)

    def test_morph_shape_has_start_and_end_polygons(self):
        morph = self.movie.characters[8]
        px = lambda *v: tuple(c / 20 for c in v)
        self.assertEqual(morph.polygon, [px(2673, -73), px(2687, -73), px(2687, 303), px(2673, 303)])
        self.assertEqual(morph.end_polygon, [px(30, -58), px(2790, -58), px(2790, 318), px(30, 318)])

    def test_colour_scripts_become_actions(self):
        # sprite 102 sets the colour of its Colorset child from the Line theme colour when it starts
        actions = self.movie.characters[102].timeline.frames[0].actions
        self.assertIn({"do": "color", "theme": "Line", "target": "Colorset"}, actions)

    def test_digit_scripts_colour_the_number_and_stop(self):
        actions = self.movie.characters[91].timeline.frames[0].actions
        self.assertIn({"do": "color", "theme": "Text", "target": "NumberText"}, actions)
        self.assertIn({"do": "stop"}, actions)

    def test_the_root_script_keeps_only_its_top_level_stop(self):
        """The root script is mostly function definitions and _root calls (ported by hand); only its stop() is an action."""
        self.assertEqual(self.movie.root.frames[0].actions, [{"do": "stop"}])

    def test_imported_font_is_recorded(self):
        self.assertEqual(self.movie.imports[63], ("HUD_Font_LocFont.swf", "Font_Body"))

    def test_edit_text_fields(self):
        text = self.movie.characters[64]
        self.assertEqual(text.kind, "text")
        self.assertEqual(text.font_height, 360 / 20)
        self.assertEqual(text.initial_text, "0")
        self.assertEqual(text.color, (255, 255, 255, 255))


if __name__ == "__main__":
    unittest.main()
