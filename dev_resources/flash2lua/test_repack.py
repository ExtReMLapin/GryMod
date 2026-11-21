"""Tests for the PNG -> VTF migration of the atlases (no FFDec needed)."""
import os
import re
import tempfile
import unittest

import numpy as np
from PIL import Image

from dev_resources.flash2lua import repack, vtf


def make_movie(tmp, shapes, font=True):
    """A movie with two shape atlases (shapes: {id: (atlas, x, y, picture)}) and a glyph atlas; returns the lua dir,
    the png dir."""
    lua_dir, png_dir = os.path.join(tmp, "lua"), os.path.join(tmp, "png")
    os.makedirs(lua_dir)
    os.makedirs(png_dir)
    sheets = {1: np.zeros((256, 256, 4), np.uint8), 2: np.zeros((128, 128, 4), np.uint8)}
    lines = []
    for cid, (atlas, x, y, picture) in shapes.items():
        h, w = picture.shape[:2]
        sheets[atlas][y - 1:y + h + 1, x - 1:x + w + 1] = np.pad(picture, ((1, 1), (1, 1), (0, 0)), mode="edge")
        lines.append('\t[%d]={k="shape",a=%d,x=%d,y=%d,w=%d,h=%d,ox=0,oy=0,dw=%g,dh=%g}' % (cid, atlas, x, y, w, h, w / 4, h / 4))
    for atlas, sheet in sheets.items():
        Image.fromarray(sheet, "RGBA").save(os.path.join(png_dir, "m_%d.png" % atlas))
    glyphs = np.zeros((64, 64, 4), np.uint8)
    glyphs[:, :, :3] = 255
    Image.fromarray(glyphs, "RGBA").save(os.path.join(png_dir, "m_font.png"))
    text = ('-- Generated\nreturn {\n\tw=1024,h=768,fps=30,\n\tatlases={"grymod/flash/m_1.png","grymod/flash/m_2.png","grymod/flash/m_font.png"},\n'
            '\twhite={[1]=true,[2]=true},\n\tfonts={\n\t\t[9]={a=3,em=128,asc=1,desc=1,g={[33]={x=1,y=1,w=4,h=4}}}\n\t},\n\tchars={\n%s\n\t},\n\troot={}\n}\n'
            % ",\n".join(lines))
    with open(os.path.join(lua_dir, "m.lua"), "w", newline="\n") as out:
        out.write(text)

    return lua_dir, png_dir


def noisy(h, w, seed):
    rng = np.random.default_rng(seed)
    pic = rng.integers(0, 256, size=(h, w, 4)).astype(np.uint8)
    pic[:, :, 3] = 255
    return pic


class ShrinkTest(unittest.TestCase):
    def test_a_flat_shape_shrinks_a_lot(self):
        flat = np.zeros((512, 512, 4), np.uint8)
        flat[:, :] = (10, 20, 30, 255)
        small = repack.shrink_picture(flat)
        self.assertLessEqual(small.shape[0] * small.shape[1], 32 * 32)
        self.assertTrue((np.abs(small[:, :, :3].astype(int) - np.array([10, 20, 30])) <= 1).all())

    def test_a_shape_with_sharp_edges_stays(self):
        sharp = np.zeros((128, 128, 4), np.uint8)
        sharp[:, :, :3] = 255
        sharp[::2, :, 3] = 255  # one line out of two
        self.assertEqual(repack.shrink_picture(sharp).shape, sharp.shape)

    def test_noise_stays(self):
        pic = noisy(64, 64, 1)
        self.assertEqual(repack.shrink_picture(pic).shape, pic.shape)

    def test_a_smooth_gradient_shrinks_without_visible_change(self):
        ramp = np.zeros((256, 256, 4), np.uint8)
        ramp[:, :, :3] = np.linspace(40, 200, 256).astype(np.uint8)[None, :, None]
        ramp[:, :, 3] = 255
        small = repack.shrink_picture(ramp)
        self.assertLess(small.shape[1], 256)
        back = np.asarray(Image.fromarray(small).resize((256, 256), Image.BILINEAR)).astype(int)
        self.assertLessEqual(np.abs(back[:, 8:-8, :3] - ramp[:, 8:-8, :3]).max(), 6)


class RepackTest(unittest.TestCase):
    def test_every_shape_gets_a_place_and_the_picture_follows(self):
        with tempfile.TemporaryDirectory() as tmp:
            shapes = {1: (1, 10, 10, noisy(40, 50, 1)), 2: (1, 100, 10, noisy(30, 30, 2)), 3: (2, 10, 10, noisy(20, 60, 3))}
            lua_dir, png_dir = make_movie(tmp, shapes)
            out = os.path.join(tmp, "out")
            text = repack.repack_movie("m", lua_dir, png_dir, out, fmt="bgra8888")
            self.assertIn('atlases={"grymod/flash/m_1","grymod/flash/hud_font"}', text)
            self.assertIn("white={[1]=true", text)
            self.assertIn("[9]={a=2,em=128", text)  # the glyph atlas is the second one now
            sheet = vtf.read_vtf_top(os.path.join(out, "m_1.vtf"))
            twin = vtf.read_vtf_top(os.path.join(out, "m_1_w.vtf"))
            self.assertTrue(os.path.exists(os.path.join(out, "m_1.vmt")))
            self.assertTrue(os.path.exists(os.path.join(out, "hud_font.vtf")))
            for cid, (atlas, x, y, picture) in shapes.items():
                m = re.search(r'\[%d\]=\{k="shape",a=(\d+),x=(\d+),y=(\d+),w=(\d+),h=(\d+)' % cid, text)
                a, nx, ny, w, h = (int(v) for v in m.groups())
                self.assertEqual(a, 1)  # three small shapes: one sheet
                got = sheet[ny:ny + h, nx:nx + w]
                self.assertTrue((got == picture).all(), "shape %d" % cid)
                white = twin[ny:ny + h, nx:nx + w]
                self.assertTrue((white[:, :, :3] == 255).all())
                self.assertTrue((white[:, :, 3] == picture[:, :, 3]).all())

    def test_the_glyph_atlas_is_shared_between_movies(self):
        with tempfile.TemporaryDirectory() as tmp:
            lua_dir, png_dir = make_movie(tmp, {1: (1, 10, 10, noisy(20, 20, 1))})
            shared = {}
            first = repack.repack_movie("m", lua_dir, png_dir, os.path.join(tmp, "out"), "bgra8888", shared)
            second = repack.repack_movie("m", lua_dir, png_dir, os.path.join(tmp, "out2"), "bgra8888", shared)
            self.assertIn("hud_font", first)
            self.assertIn("hud_font", second)
            self.assertEqual(len(shared), 1)
            self.assertFalse(os.path.exists(os.path.join(tmp, "out2", "hud_font.vtf")))

    def test_the_sheet_is_a_power_of_two_and_smaller_than_the_old_ones(self):
        with tempfile.TemporaryDirectory() as tmp:
            lua_dir, png_dir = make_movie(tmp, {1: (1, 10, 10, noisy(40, 50, 1)), 2: (2, 10, 10, noisy(20, 60, 3))})
            out = os.path.join(tmp, "out")
            repack.repack_movie("m", lua_dir, png_dir, out, "bgra8888")
            sheet = vtf.read_vtf_top(os.path.join(out, "m_1.vtf"))
            h, w = sheet.shape[:2]
            self.assertEqual((w & (w - 1), h & (h - 1)), (0, 0))
            self.assertLessEqual(w * h, 128 * 128)


if __name__ == "__main__":
    unittest.main()
