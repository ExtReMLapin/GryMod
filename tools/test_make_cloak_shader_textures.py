"""Tests of tools/make_cloak_shader_textures.py: the two textures the camouflage's pixel shader reads (the noise volume and the spark profile)."""
import os
import struct
import tempfile
import unittest

import numpy as np

from tools import make_cloak_shader_textures as mcs
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

    def test_the_three_channels_survive_the_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "p.vtf")
            with open(path, "wb") as out:
                out.write(mcs.spark_profile_bytes(self.profile()))
            back = vtf.read_vtf_top(path)
        self.assertTrue((back[:, :, :3] == self.profile()[:, :, :3]).all())


if __name__ == "__main__":
    unittest.main()
