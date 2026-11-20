"""Tests for shape rasterisation / atlas packing. Need FFDec and the demo SWF (see test_swfmodel)."""
import os
import tempfile
import unittest

from PIL import Image

from tools.flash2lua import rasterize, swfmodel

FFDEC = os.environ.get("FFDEC", r"D:\dev\crysis-hud-research\ffdec\ffdec-cli.exe")
SWF_DIR = os.environ.get("SWF_DIR", r"D:\dev\crysis-hud-research\extracted\Libs\UI")
SWF = os.path.join(SWF_DIR, "HUD_AmmoHealthEnergySuit.swf")


@unittest.skipUnless(os.path.exists(FFDEC) and os.path.exists(SWF), "FFDec / demo SWF not available")
class RasterizeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        xml = os.path.join(cls.tmp, "hud.xml")
        swfmodel.swf_to_xml(FFDEC, SWF, xml)
        cls.movie = swfmodel.parse_swf_xml(xml)
        cls.out = os.path.join(cls.tmp, "atlas")
        cls.rects = rasterize.rasterize_movie(cls.movie, SWF, cls.out, FFDEC, prefix="ahes")
        cls.shape_ids = {i for i, c in cls.movie.characters.items() if c.kind == "shape"}

    def test_every_shape_gets_a_rect(self):
        self.assertEqual(set(self.rects), self.shape_ids)

    def test_rect_size_matches_bounds_times_zoom(self):
        for cid, r in self.rects.items():
            x0, y0, x1, y1 = self.movie.characters[cid].bounds
            if max(x1 - x0, y1 - y0) * 4 <= rasterize.MAX_SIDE:
                self.assertAlmostEqual(r["w"], (x1 - x0) * 4, delta=2, msg=f"shape {cid}")
                self.assertAlmostEqual(r["h"], (y1 - y0) * 4, delta=2, msg=f"shape {cid}")
            else:  # backdrops are downscaled to MAX_SIDE
                self.assertAlmostEqual(max(r["w"], r["h"]), rasterize.MAX_SIDE, delta=1, msg=f"shape {cid}")
            self.assertAlmostEqual(r["ox"], x0, places=3)
            self.assertAlmostEqual(r["oy"], y0, places=3)
            self.assertAlmostEqual(r["dw"], x1 - x0, places=3)
            self.assertAlmostEqual(r["dh"], y1 - y0, places=3)

    def test_atlas_not_larger_than_4096(self):
        names = {r["atlas"] for r in self.rects.values()}
        self.assertTrue(names)
        for name in names:
            w, h = Image.open(os.path.join(self.out, name)).size
            self.assertLessEqual(max(w, h), 4096)

    def test_no_overlap_with_two_pixel_padding(self):
        by_atlas = {}
        for r in self.rects.values():
            by_atlas.setdefault(r["atlas"], []).append(r)
        for rects in by_atlas.values():
            for i, a in enumerate(rects):
                for b in rects[i + 1:]:
                    apart = (a["x"] + a["w"] + 2 <= b["x"] or b["x"] + b["w"] + 2 <= a["x"]
                             or a["y"] + a["h"] + 2 <= b["y"] or b["y"] + b["h"] + 2 <= a["y"])
                    self.assertTrue(apart, f"{a} overlaps {b}")

    def test_atlas_pixels_are_the_shape_pixels(self):
        cid = 100
        r = self.rects[cid]
        atlas = Image.open(os.path.join(self.out, r["atlas"])).convert("RGBA")
        crop = atlas.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"]))
        opaque = [p for p in crop.getdata() if p[3] == 255]
        self.assertTrue(opaque, "the shape has opaque pixels")
        self.assertEqual(opaque[0][:3], (255, 255, 255))

    def test_atlas_colours_are_srgb_encoded(self):
        """The engine decodes PNG textures as sRGB when it samples them; the atlas stores the encoded colour so
        that the shader sees the original one (Flash blends the plain 0-255 values)."""
        def encode(v):
            x = v / 255
            return round(255 * (12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055))

        r = self.rects[32]  # fills (204, 102, 51) and (255, 0, 0)
        atlas = Image.open(os.path.join(self.out, r["atlas"])).convert("RGBA")
        colours = {}
        for p in atlas.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])).getdata():
            if p[3] == 255:
                colours[p[:3]] = colours.get(p[:3], 0) + 1
        self.assertIn((encode(204), encode(102), encode(51)), colours)
        self.assertIn((255, 0, 0), colours)
        self.assertNotIn((204, 102, 51), colours)

    def test_transparent_pixels_carry_the_neighbour_colour(self):
        """Bilinear filtering must not pull black from transparent pixels into the edge."""
        r = self.rects[100]
        atlas = Image.open(os.path.join(self.out, r["atlas"])).convert("RGBA")
        black_transparent = 0
        for p in atlas.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])).getdata():
            if p[3] == 0 and p[:3] == (0, 0, 0):
                black_transparent += 1
        self.assertEqual(black_transparent, 0)


if __name__ == "__main__":
    unittest.main()
