"""End-to-end test of the converter CLI function. Needs FFDec and the demo's GameData.pak."""
import os
import tempfile
import unittest

from dev_resources.flash2lua import convert

FFDEC = os.environ.get("FFDEC", r"D:\dev\crysis-hud-research\ffdec\ffdec-cli.exe")
PAK = os.environ.get("CRYSIS_GAMEDATA_PAK",
                     r"C:\Program Files (x86)\Electronic Arts\Crytek\Crysis SP Demo\Game\GameData.pak")


@unittest.skipUnless(os.path.exists(FFDEC) and os.path.exists(PAK), "FFDec / demo GameData.pak not available")
class ConvertTest(unittest.TestCase):
    def test_converts_a_movie_from_the_pak(self):
        tmp = tempfile.mkdtemp()
        lua_dir, mat_dir = os.path.join(tmp, "lua"), os.path.join(tmp, "materials")
        convert.convert_movie(PAK, "HUD_AmmoHealthEnergySuit", FFDEC, lua_dir, mat_dir)
        lua_file = os.path.join(lua_dir, "hud_ammohealthenergysuit.lua")
        self.assertTrue(os.path.exists(lua_file))
        text = open(lua_file, encoding="utf8").read()
        self.assertIn('"grymod/flash/hud_ammohealthenergysuit_1"', text)
        self.assertTrue(os.path.exists(os.path.join(mat_dir, "hud_ammohealthenergysuit_1.vtf")))
        self.assertTrue(os.path.exists(os.path.join(mat_dir, "hud_ammohealthenergysuit_1.vmt")))
        self.assertTrue(os.path.exists(os.path.join(mat_dir, "hud_ammohealthenergysuit_1_w.vtf")))
        self.assertFalse(any(f.endswith(".png") for f in os.listdir(mat_dir)))

    def test_png_option_keeps_the_png_atlases(self):
        tmp = tempfile.mkdtemp()
        lua_dir, mat_dir = os.path.join(tmp, "lua"), os.path.join(tmp, "materials")
        convert.convert_movie(PAK, "HUD_AmmoHealthEnergySuit", FFDEC, lua_dir, mat_dir, png=True)
        text = open(os.path.join(lua_dir, "hud_ammohealthenergysuit.lua"), encoding="utf8").read()
        self.assertIn("grymod/flash/hud_ammohealthenergysuit_1.png", text)
        self.assertTrue(os.path.exists(os.path.join(mat_dir, "hud_ammohealthenergysuit_1.png")))

    def test_converts_the_imported_font_too(self):
        tmp = tempfile.mkdtemp()
        convert.convert_movie(PAK, "HUD_AmmoHealthEnergySuit", FFDEC, os.path.join(tmp, "lua"), os.path.join(tmp, "m"))
        with open(os.path.join(tmp, "lua", "hud_ammohealthenergysuit.lua"), encoding="utf8") as f:
            text = f.read()
        self.assertIn("fonts={", text)
        self.assertIn("grymod/flash/hud_font", text)
        self.assertTrue(os.path.exists(os.path.join(tmp, "m", "hud_font.vtf")))

    def test_second_run_is_byte_identical(self):
        outs = []
        for _ in range(2):
            tmp = tempfile.mkdtemp()
            convert.convert_movie(PAK, "HUD_SuitModeOverlay", FFDEC, os.path.join(tmp, "l"), os.path.join(tmp, "m"))
            with open(os.path.join(tmp, "l", "hud_suitmodeoverlay.lua"), "rb") as f:
                outs.append(f.read())
        self.assertEqual(outs[0], outs[1])

    def test_unknown_movie_is_an_error(self):
        with self.assertRaises(KeyError):
            convert.convert_movie(PAK, "HUD_DoesNotExist", FFDEC, tempfile.mkdtemp(), tempfile.mkdtemp())


if __name__ == "__main__":
    unittest.main()
