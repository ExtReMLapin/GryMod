"""Tests for the Lua data writer. Need FFDec and the demo SWF (see test_swfmodel)."""
import os
import tempfile
import unittest

from tools.flash2lua import emit_lua, lua_literal, rasterize, swfmodel

FFDEC = os.environ.get("FFDEC", r"D:\dev\crysis-hud-research\ffdec\ffdec-cli.exe")
SWF_DIR = os.environ.get("SWF_DIR", r"D:\dev\crysis-hud-research\extracted\Libs\UI")
SWF = os.path.join(SWF_DIR, "HUD_AmmoHealthEnergySuit.swf")


@unittest.skipUnless(os.path.exists(FFDEC) and os.path.exists(SWF), "FFDec / demo SWF not available")
class EmitLuaTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        xml = os.path.join(cls.tmp, "hud.xml")
        swfmodel.swf_to_xml(FFDEC, SWF, xml)
        scripts = os.path.join(cls.tmp, "scripts")
        swfmodel.export_scripts(FFDEC, SWF, scripts)
        cls.movie = swfmodel.parse_swf_xml(xml, scripts)
        cls.rects = rasterize.rasterize_movie(cls.movie, SWF, os.path.join(cls.tmp, "atlas"), FFDEC, prefix="ahes")
        cls.text = emit_lua.emit_lua(cls.movie, cls.rects, "grymod/flash/ahes")
        cls.data = lua_literal.parse(cls.text)

    def test_emit_is_deterministic(self):
        self.assertEqual(self.text, emit_lua.emit_lua(self.movie, self.rects, "grymod/flash/ahes"))

    def test_stage_header(self):
        self.assertEqual((self.data["w"], self.data["h"], self.data["fps"]), (1024, 768, 30))

    def test_atlas_paths_use_the_given_prefix(self):
        self.assertTrue(self.data["atlases"][1].startswith("grymod/flash/ahes"))
        self.assertTrue(self.data["atlases"][1].endswith(".png"))

    def test_shape_char_has_atlas_rect_and_draw_size(self):
        shape = self.data["chars"][5]
        self.assertEqual(shape["k"], "shape")
        for key in ("a", "x", "y", "w", "h", "ox", "oy", "dw", "dh"):
            self.assertIn(key, shape)
        self.assertAlmostEqual(shape["dw"], (4828 + 56) / 20, places=3)

    def test_sprite_frames_ops_and_labels(self):
        cloak = self.data["chars"][38]
        self.assertEqual(cloak["k"], "sprite")
        self.assertEqual(cloak["n"], len(self.movie.characters[38].timeline.frames))
        self.assertEqual(cloak["labels"]["normal"], 1)
        first = cloak["frames"][1]
        place = first[1]
        self.assertEqual(place["d"], 1)
        self.assertEqual(place["c"], 31)
        self.assertEqual(place["m"][5], 8069 / 20)
        self.assertEqual(first["a"][1][1], "play")

    def test_root_places_Root(self):
        place = self.data["root"][1][1]
        self.assertEqual((place["d"], place["c"], place["n"]), (1, 241, "Root"))

    def test_colour_transform_and_remove_ops(self):
        found_cx = found_rm = False
        for char in self.data["chars"].values():
            if char["k"] != "sprite":
                continue
            for frame in char["frames"].values():
                for key, op in frame.items():
                    if isinstance(key, int):
                        found_cx = found_cx or "cx" in op
                        found_rm = found_rm or "rm" in op
        self.assertTrue(found_cx and found_rm)

    def test_text_char(self):
        text = self.data["chars"][64]
        self.assertEqual((text["k"], text["t"], text["fh"]), ("text", "0", 18))
        self.assertEqual(text["col"][1], 255)

    def test_stop_in_a_composite_script_is_kept(self):
        """Root frame 1 is "stop(); _root.updateAmmoMode();": the stop must survive."""
        first = self.data["chars"][241]["frames"][1]
        self.assertEqual(first["a"][1][1], "stop")
        malfunction_on = self.data["chars"][241]["frames"][45]
        self.assertEqual(malfunction_on["a"][1][1], "stop")

    def test_colour_actions_are_emitted(self):
        first = self.data["chars"][102]["frames"][1]
        self.assertEqual([first["a"][1][1], first["a"][1][2], first["a"][1][3]], ["color", "Line", "Colorset"])

    def test_shape_atlases_are_flagged_as_having_a_white_twin_and_font_atlases_not(self):
        self.assertTrue(self.data["white"][1])
        font = {"atlas": "ahes_font.png", "em": 128, "asc": 136, "desc": 20,
                "glyphs": {48: {"x": 3, "y": 4, "w": 60, "h": 90, "ox": 2, "oy": -95, "adv": 74.0}}}
        data = lua_literal.parse(emit_lua.emit_lua(self.movie, self.rects, "grymod/flash", {63: font}))
        index = data["fonts"][63]["a"]
        self.assertNotIn(index, data["white"])

    def test_polygons_are_emitted_for_masks(self):
        self.assertEqual([self.data["chars"][15]["p"][i] for i in range(1, 9)],
                         [29 / 20, -58 / 20, 29 / 20, 318 / 20, 2829 / 20, 318 / 20, 2829 / 20, -58 / 20])
        morph = self.data["chars"][8]
        self.assertEqual(morph["k"], "morph")
        self.assertEqual(len(morph["p"]), 8)
        self.assertEqual(len(morph["pe"]), 8)
        self.assertNotIn("p", self.data["chars"][100])

    def test_fonts_are_emitted_with_their_atlas(self):
        font = {"atlas": "ahes_font.png", "em": 128, "asc": 136, "desc": 20,
                "glyphs": {48: {"x": 3, "y": 4, "w": 60, "h": 90, "ox": 2, "oy": -95, "adv": 74.0},
                           32: {"x": 0, "y": 0, "w": 0, "h": 0, "ox": 0, "oy": 0, "adv": 30.0}}}
        text = emit_lua.emit_lua(self.movie, self.rects, "grymod/flash", {63: font})
        data = lua_literal.parse(text)
        emitted = data["fonts"][63]
        self.assertEqual((emitted["em"], emitted["asc"], emitted["desc"]), (128, 136, 20))
        self.assertTrue(data["atlases"][emitted["a"]].endswith("ahes_font.png"))
        self.assertEqual(emitted["g"][48]["adv"], 74)
        self.assertEqual(emitted["g"][48]["oy"], -95)

    def test_file_size_is_reasonable(self):
        self.assertLess(len(self.text.encode("utf8")), 1_000_000)




@unittest.skipUnless(os.path.exists(FFDEC) and os.path.exists(SWF), "FFDec / demo SWF not available")
class EmitLuaRealRuntimeTest(unittest.TestCase):
    def test_output_loads_in_luajit_and_matches_the_model(self):
        try:
            from lupa.luajit21 import LuaRuntime
        except ImportError:
            self.skipTest("lupa (LuaJIT) not installed")
        tmp = tempfile.mkdtemp()
        xml = os.path.join(tmp, "hud.xml")
        swfmodel.swf_to_xml(FFDEC, SWF, xml)
        movie = swfmodel.parse_swf_xml(xml)
        rects = rasterize.rasterize_movie(movie, SWF, os.path.join(tmp, "atlas"), FFDEC, prefix="ahes")
        text = emit_lua.emit_lua(movie, rects, "grymod/flash")
        lua = LuaRuntime()
        data = lua.execute(text)
        self.assertEqual(data["fps"], 30)
        self.assertEqual(data["chars"][38].n, len(movie.characters[38].timeline.frames))
        self.assertEqual(data["root"][1][1].n, "Root")


if __name__ == "__main__":
    unittest.main()
