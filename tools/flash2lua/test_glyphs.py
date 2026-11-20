"""Tests for the glyph atlas built from the HUD font. Need FFDec and the demo's Localized/english.pak."""
import os
import tempfile
import unittest

from PIL import Image

from tools.flash2lua import glyphs

FFDEC = os.environ.get("FFDEC", r"D:\dev\crysis-hud-research\ffdec\ffdec-cli.exe")
LOCALIZED_PAK = os.environ.get(
    "CRYSIS_LOCALIZED_PAK",
    r"C:\Program Files (x86)\Electronic Arts\Crytek\Crysis SP Demo\Game\Localized\english.pak")


@unittest.skipUnless(os.path.exists(FFDEC) and os.path.exists(LOCALIZED_PAK), "FFDec / demo english.pak not available")
class GlyphAtlasTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = tempfile.mkdtemp()
        cls.font = glyphs.build_font_atlas(LOCALIZED_PAK, "HUD_Font_LocFont.swf", FFDEC, cls.out, "font_test")

    def test_digits_and_compass_letters_have_bitmaps(self):
        for ch in "0123456789NESW|/x":
            g = self.font["glyphs"][ord(ch)]
            self.assertGreater(g["w"], 0, ch)
            self.assertGreater(g["h"], 0, ch)
            self.assertGreater(g["adv"], 0, ch)

    def test_space_has_an_advance_and_no_bitmap(self):
        g = self.font["glyphs"][32]
        self.assertGreater(g["adv"], 0)
        self.assertEqual((g["w"], g["h"]), (0, 0))

    def test_metrics_are_in_pixels_at_the_atlas_em_size(self):
        em = self.font["em"]
        self.assertEqual(em, glyphs.EM)
        self.assertAlmostEqual(self.font["glyphs"][ord("0")]["adv"] / em, 74 / 160, delta=0.03)
        self.assertGreater(self.font["asc"], 0)
        self.assertGreater(self.font["desc"], 0)

    def test_digit_sits_on_the_baseline(self):
        g = self.font["glyphs"][ord("0")]
        self.assertLess(g["oy"], 0)  # the top of a digit is above the baseline
        self.assertAlmostEqual(g["oy"] + g["h"], 0, delta=3)  # and its bottom is on it

    def test_atlas_is_a_png_with_the_glyph_pixels(self):
        g = self.font["glyphs"][ord("N")]
        atlas = Image.open(os.path.join(self.out, self.font["atlas"])).convert("RGBA")
        crop = atlas.crop((g["x"], g["y"], g["x"] + g["w"], g["y"] + g["h"]))
        opaque = sum(1 for p in crop.getdata() if p[3] > 200)
        self.assertGreater(opaque, 100)
        self.assertLessEqual(max(atlas.size), 4096)

    def test_unknown_font_file_is_an_error(self):
        with self.assertRaises(KeyError):
            glyphs.build_font_atlas(LOCALIZED_PAK, "Nope.swf", FFDEC, self.out, "x")


if __name__ == "__main__":
    unittest.main()
