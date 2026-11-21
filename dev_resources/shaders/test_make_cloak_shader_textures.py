"""Tests of dev_resources/shaders/make_cloak_shader_textures.py: the two textures the camouflage's pixel shader reads (the noise volume and the spark profile)."""
import os
import struct
import tempfile
import unittest

import numpy as np

import make_cloak_shader_textures as mcs
from tools.flash2lua import vtf


def noise_volume():
    rng = np.random.default_rng(3)
    vol = np.zeros((8, 4, 16, 4), dtype=np.uint8)
    vol[..., 0] = rng.integers(0, 256, size=(8, 4, 16))
    vol[..., 3] = 255

    return vol


class NoiseVolumeTest(unittest.TestCase):
    def test_the_volume_is_written_as_one_8_bit_channel_with_its_depth(self):
        raw = mcs.noise_volume_bytes(noise_volume())
        self.assertEqual(struct.unpack_from("<HH", raw, 16), (16, 4))
        self.assertEqual(struct.unpack_from("<H", raw, 63)[0], 8)
        self.assertEqual(struct.unpack_from("<i", raw, 52)[0], vtf.FORMATS["i8"])
        self.assertEqual(len(raw), 80 + 8 * 4 * 16)

    def test_the_slices_keep_their_order_and_their_values(self):
        vol = noise_volume()
        raw = mcs.noise_volume_bytes(vol)
        data = np.frombuffer(raw[80:], dtype=np.uint8).reshape(8, 4, 16)
        self.assertTrue((data == vol[..., 0]).all())

    def test_the_noise_repeats_on_every_axis_and_is_data_not_a_colour(self):
        flags = struct.unpack_from("<I", mcs.noise_volume_bytes(noise_volume()), 20)[0]
        self.assertFalse(flags & (vtf.FLAG_CLAMPS | vtf.FLAG_CLAMPT))
        self.assertFalse(flags & vtf.FLAG_SRGB)
        self.assertTrue(flags & vtf.FLAG_NOMIP)


class SparkProfileTest(unittest.TestCase):
    def profile(self):
        p = np.zeros((1, 256, 4), dtype=np.uint8)
        p[0, :, 0] = np.arange(256)
        p[0, :, 1] = 255 - np.arange(256)
        p[0, :, 2] = 7
        p[0, :, 3] = 255

        return p

    def test_the_profile_is_one_row_of_256_colours_that_repeats_along_it(self):
        raw = mcs.spark_profile_bytes(self.profile())
        self.assertEqual(struct.unpack_from("<HH", raw, 16), (256, 1))
        flags = struct.unpack_from("<I", raw, 20)[0]
        self.assertFalse(flags & vtf.FLAG_CLAMPS)
        self.assertTrue(flags & vtf.FLAG_CLAMPT)
        self.assertFalse(flags & vtf.FLAG_SRGB)

    def test_the_three_channels_keep_their_own_peaks_where_and_as_high_as_they_were(self):
        profile = np.zeros((1, 256, 4), dtype=np.uint8)
        profile[0, 40, 0] = 200
        profile[0, 120, 1] = 150
        profile[0, 200, 2] = 90
        profile[0, :, 3] = 255
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "p.vtf")
            with open(path, "wb") as out:
                out.write(mcs.spark_profile_bytes(profile))
            back = vtf.read_vtf_top(path)
        self.assertEqual(back[0, 40, 0], 200)
        self.assertEqual(back[0, 120, 1], 150)
        self.assertEqual(back[0, 200, 2], 90)
        self.assertEqual(back[0, 40, 1], 0)
        self.assertEqual(back[0, 40, 2], 0)
        self.assertTrue((back[0, :, 3] == 255).all())


class GlowTest(unittest.TestCase):
    """The original's sparks are thin and its HDR output and bloom make them glow; here the peaks of the profile are widened in the data."""

    def peak(self, at=100, value=0.5):
        profile = np.zeros((256, 3))
        profile[at, :] = value

        return profile

    def test_a_peak_gets_wider_and_brighter_by_the_radius(self):
        out = mcs.glow_profile(self.peak(), radius=2, gain=2.0)
        self.assertTrue((out[98:103] > 0).all())
        self.assertEqual(out[96, 0], 0)
        self.assertEqual(out[104, 0], 0)
        self.assertGreater(out[100, 0], 0.5 - 1e-9)

    def test_never_dimmer_than_the_input_and_never_above_one(self):
        rng = np.random.default_rng(5)
        profile = rng.random((256, 3)) ** 8
        out = mcs.glow_profile(profile, radius=3, gain=4.0)
        self.assertTrue((out >= profile - 1e-12).all())
        self.assertLessEqual(out.max(), 1.0)

    def test_the_profile_repeats_so_the_glow_wraps_round_its_ends(self):
        out = mcs.glow_profile(self.peak(at=0), radius=2, gain=2.0)
        self.assertGreater(out[255, 0], 0)
        self.assertGreater(out[254, 0], 0)
        self.assertGreater(out[2, 0], 0)

    def test_each_channel_is_widened_on_its_own(self):
        profile = np.zeros((256, 3))
        profile[50, 0] = 0.4
        profile[150, 2] = 0.6
        out = mcs.glow_profile(profile, radius=2, gain=2.0)
        self.assertGreater(out[51, 0], 0)
        self.assertEqual(out[51, 1], 0)
        self.assertEqual(out[51, 2], 0)
        self.assertGreater(out[151, 2], 0)

    def test_radius_zero_leaves_the_profile_as_it_is(self):
        profile = self.peak()
        self.assertTrue((mcs.glow_profile(profile, radius=0, gain=3.0) == profile).all())

    def test_the_written_profile_carries_the_glow(self):
        profile = np.zeros((1, 256, 4), dtype=np.uint8)
        profile[0, 100, :3] = 100
        profile[0, :, 3] = 255
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "p.vtf")
            with open(path, "wb") as out:
                out.write(mcs.spark_profile_bytes(profile))
            back = vtf.read_vtf_top(path)
        self.assertGreater(back[0, 99, 0], 0)
        self.assertGreater(back[0, 101, 0], 0)


if __name__ == "__main__":
    unittest.main()
