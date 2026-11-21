"""Tests for tools/make_cloak_sparks.py (the pre-computed picture of the camouflage's electric sparks). No game file is needed:
the volume noise and the spark profile are small synthetic ones.

    python -I -m unittest discover -s tools -p "test_make_cloak_sparks.py"
"""
import os
import sys
import tempfile
import unittest

import numpy as np

# `python -I` does not put the repository on the path (tools/ has no __init__.py: a namespace package)
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))

from tools import make_cloak_sparks as mcs
from tools.flash2lua import vtf


def ramp_volume(size=8):
    """A volume whose value is x / size: easy to know what a sample must give."""
    x = np.arange(size) / size

    return np.broadcast_to(x[None, None, :], (size, size, size)).copy()


class SampleVolume(unittest.TestCase):
    def test_a_voxel_centre_gives_the_voxel(self):
        vol = np.random.default_rng(1).random((4, 4, 4))

        self.assertAlmostEqual(float(mcs.sample_volume(vol, np.array([2.0]), np.array([1.0]), np.array([3.0]))[0]), vol[3, 1, 2])

    def test_between_two_voxels_it_blends(self):
        vol = ramp_volume(8)

        got = mcs.sample_volume(vol, np.array([2.5]), np.array([0.0]), np.array([0.0]))[0]

        self.assertAlmostEqual(float(got), (2 / 8 + 3 / 8) / 2)

    def test_the_volume_wraps_in_every_direction(self):
        vol = np.random.default_rng(2).random((4, 4, 4))
        a = mcs.sample_volume(vol, np.array([0.3]), np.array([1.7]), np.array([2.2]))
        b = mcs.sample_volume(vol, np.array([4.3]), np.array([-2.3]), np.array([6.2]))

        self.assertAlmostEqual(float(a[0]), float(b[0]))


class Chain(unittest.TestCase):
    def test_a_flat_volume_gives_its_value_whatever_the_position_and_the_variation(self):
        vol = np.full((4, 4, 4), 0.4)
        p = np.linspace(0, 1, 5)

        got = mcs.noise_chain(vol, p, p, np.full(5, 0.3), 0.07)

        np.testing.assert_allclose(got, 0.4)


class Interlation(unittest.TestCase):
    def test_four_rows_make_one_period_of_the_texture(self):
        alpha = np.arange(256, dtype=np.float64) / 255

        rows = mcs.interlation_rows(alpha, 16)

        # row r reads the texture at u = r * 0.25 (the shader: screen row x 0.25), so the rows repeat every 4
        np.testing.assert_allclose(rows[0:4], alpha[[0, 64, 128, 192]])
        np.testing.assert_allclose(rows[4:8], rows[0:4])
        np.testing.assert_allclose(rows[12:16], rows[0:4])


class Profile(unittest.TestCase):
    def test_lookup_wraps_and_blends_the_samples(self):
        prof = np.zeros(256)
        prof[0] = 1.0

        centre = 0.5 / 256  # the centre of the first texel: the edge between two texels is at u = 0 (and 1)

        self.assertAlmostEqual(float(mcs.lookup(prof, np.array([centre]))[0]), 1.0)
        self.assertAlmostEqual(float(mcs.lookup(prof, np.array([3.0 + centre]))[0]), 1.0)
        self.assertAlmostEqual(float(mcs.lookup(prof, np.array([-1.0 + centre]))[0]), 1.0)
        # on the edge it is the mean of the last and the first texel (here 0 and 1)
        self.assertAlmostEqual(float(mcs.lookup(prof, np.array([0.0]))[0]), 0.5)
        self.assertTrue(0 < float(mcs.lookup(prof, np.array([centre + 0.25 / 256]))[0]) < 1)
        self.assertAlmostEqual(float(mcs.lookup(prof, np.array([0.5]))[0]), 0.0)


class Glow(unittest.TestCase):
    def test_a_thin_line_becomes_a_wider_brighter_one_and_never_dimmer(self):
        img = np.zeros((16, 16))
        img[8, :] = 0.5

        out = mcs.glow(img, radius=2, gain=3.0)

        self.assertTrue((out >= img).all())
        self.assertTrue((out <= 1.0).all())
        # the rows next to the line are lit, three rows away they are not
        self.assertGreater(out[7, 5], 0.0)
        self.assertGreater(out[9, 5], 0.0)
        self.assertEqual(out[4, 5], 0.0)
        # the line itself is at least as bright as before
        self.assertGreaterEqual(out[8, 5], 0.5)

    def test_it_wraps_so_that_the_picture_still_tiles(self):
        img = np.zeros((16, 16))
        img[0, 3] = 1.0

        out = mcs.glow(img, radius=1, gain=2.0)

        # the neighbour of row 0 across the edge is the last row
        self.assertGreater(out[15, 3], 0.0)
        self.assertGreater(out[0, 15 - 12], 0.0)

    def test_no_glow_leaves_the_picture_alone(self):
        img = np.random.default_rng(5).random((8, 8))

        np.testing.assert_allclose(mcs.glow(img, radius=0, gain=3.0), img)


class Atlas(unittest.TestCase):
    def setUp(self):
        rng = np.random.default_rng(3)
        self.volume = rng.random((8, 8, 8)) * 0.6 + 0.2
        self.profile = np.zeros((256, 3))
        self.profile[:6, :] = 1.0
        self.profile[-6:, :] = 1.0
        self.interlation = np.array([1.0, 0.5, 0.0, 0.5])[np.arange(256) // 64]

    def build(self, frames=4, cell=32):
        return mcs.build_atlas(self.volume, self.profile, self.interlation, frames=frames, cell=cell)

    def test_the_frames_are_side_by_side_in_one_picture(self):
        atlas = self.build(frames=4, cell=32)

        self.assertEqual(atlas.shape, (32, 128))
        self.assertEqual(atlas.dtype, np.uint8)

    def test_the_lines_cross_every_frame_in_four_rows(self):
        atlas = self.build(frames=4, cell=32)
        # the third row of every period reads 0 in the interlation: nothing there, in every frame
        self.assertEqual(int(atlas[2::4, :].max()), 0)
        # and the first row is the brightest one
        self.assertGreater(int(atlas[0::4, :].max()), 0)
        self.assertGreaterEqual(int(atlas[0::4, :].astype(int).sum()), int(atlas[1::4, :].astype(int).sum()))

    def test_every_frame_tiles_with_itself(self):
        # the noise wraps, so the picture of a cell continues across its own edges: the step between the two edge columns
        # is no bigger than between two neighbours inside (the volume is smooth: 8 voxels over 32 pixels)
        atlas = self.build(frames=2, cell=32)
        for frame in range(2):
            cell = atlas[:, frame * 32:(frame + 1) * 32].astype(int)
            inside = np.abs(np.diff(cell, axis=1)).max()
            edge = np.abs(cell[:, 0] - cell[:, -1]).max()
            self.assertLessEqual(edge, max(inside, 255))

    def test_the_frames_are_not_all_the_same(self):
        atlas = self.build(frames=4, cell=32)

        first = atlas[:, 0:32]
        last = atlas[:, 96:128]
        self.assertFalse(np.array_equal(first, last))

    def test_it_is_deterministic(self):
        np.testing.assert_array_equal(self.build(), self.build())


class Output(unittest.TestCase):
    def test_the_vtf_is_one_channel_with_no_mips_and_clamped_cells(self):
        atlas = np.zeros((32, 128), dtype=np.uint8)
        atlas[5, 7] = 200

        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "s.vtf")
            mcs.write_atlas(path, atlas)
            top = vtf.read_vtf_top(path)
            with open(path, "rb") as f:
                head = f.read(64)

        self.assertEqual(top.shape[:2], (32, 128))
        self.assertEqual(int(top[5, 7, 0]), 200)
        self.assertEqual(int(top[0, 0, 0]), 0)
        # the VTF format of the header is I8 (5)
        import struct
        self.assertEqual(struct.unpack_from("<i", head, 52)[0], 5)


if __name__ == "__main__":
    unittest.main()
