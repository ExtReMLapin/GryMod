"""Tests for the VTF writer and the DXT5 encoder (no FFDec needed)."""
import os
import struct
import tempfile
import unittest

import numpy as np
from PIL import Image

from tools.flash2lua import vtf


def gradient(w, h, seed=1):
    rng = np.random.default_rng(seed)
    img = np.zeros((h, w, 4), dtype=np.uint8)
    img[:, :, 0] = np.linspace(0, 255, w).astype(np.uint8)[None, :]
    img[:, :, 1] = np.linspace(255, 0, h).astype(np.uint8)[:, None]
    img[:, :, 2] = rng.integers(0, 4, size=(h, w)) * 8
    img[:, :, 3] = 255
    return img


class Dxt5Test(unittest.TestCase):
    def test_size_is_one_byte_per_pixel(self):
        data = vtf.encode_dxt5(gradient(64, 32))
        self.assertEqual(len(data), 64 * 32)

    def test_flat_colour_block_is_almost_exact(self):
        img = np.zeros((8, 8, 4), dtype=np.uint8)
        img[:, :] = (200, 100, 50, 255)
        back = vtf.decode_dxt5(vtf.encode_dxt5(img), 8, 8)
        # the colour goes through RGB565: at most the 565 quantisation step
        self.assertLessEqual(np.abs(back[:, :, :3].astype(int) - img[:, :, :3]).max(), 8)
        self.assertTrue((back[:, :, 3] == 255).all())

    def test_flat_colour_uses_the_thirds_between_the_endpoints(self):
        img = np.zeros((8, 8, 4), dtype=np.uint8)
        img[:, :] = (95, 191, 127, 255)  # not a multiple of the 565 steps in any channel
        back = vtf.decode_dxt5(vtf.encode_dxt5(img), 8, 8)
        self.assertLessEqual(np.abs(back[:, :, :3].astype(int) - img[:, :, :3]).max(), 2)

    def test_white_is_exact(self):
        img = np.zeros((16, 16, 4), dtype=np.uint8)
        img[:, :, :3] = 255
        img[4:12, 4:12, 3] = 255
        img[2, 2, 3] = 100
        back = vtf.decode_dxt5(vtf.encode_dxt5(img), 16, 16)
        self.assertTrue((back[:, :, :3] == 255).all())
        self.assertTrue((back[4:12, 4:12, 3] == 255).all())
        self.assertTrue((back[0:2, 0:2, 3][0, 0] == 0))

    def test_alpha_endpoints_stay_exact_with_the_six_level_mode(self):
        img = np.zeros((4, 4, 4), dtype=np.uint8)
        img[:, :, :3] = 255
        img[:, :2, 3] = 255
        img[0, 2, 3] = 128
        back = vtf.decode_dxt5(vtf.encode_dxt5(img), 4, 4)
        self.assertTrue((back[:, :2, 3] == 255).all())
        self.assertTrue((back[1:, 2:, 3] == 0).all())
        self.assertLessEqual(abs(int(back[0, 2, 3]) - 128), 26)

    def test_two_colour_edge_block_keeps_both_colours(self):
        img = np.zeros((4, 4, 4), dtype=np.uint8)
        img[:, :2] = (255, 0, 0, 255)
        img[:, 2:] = (0, 0, 255, 255)
        back = vtf.decode_dxt5(vtf.encode_dxt5(img), 4, 4).astype(int)
        self.assertLessEqual(np.abs(back - img).max(), 10)

    def test_transparent_pixels_do_not_drag_the_colour(self):
        img = np.zeros((4, 4, 4), dtype=np.uint8)
        img[:, :] = (0, 255, 0, 0)  # hidden colour: whatever
        img[:2, :2] = (255, 128, 0, 255)
        back = vtf.decode_dxt5(vtf.encode_dxt5(img), 4, 4).astype(int)
        self.assertLessEqual(np.abs(back[:2, :2, :3] - np.array([255, 128, 0])).max(), 9)

    def test_gradient_error_is_small(self):
        img = gradient(64, 64)
        back = vtf.decode_dxt5(vtf.encode_dxt5(img), 64, 64).astype(int)
        err = np.abs(back[:, :, :3] - img[:, :, :3])
        self.assertLess(err.mean(), 3.0)

    def test_size_not_a_multiple_of_four_is_padded(self):
        data = vtf.encode_dxt5(gradient(2, 2))
        self.assertEqual(len(data), 16)


class MipsTest(unittest.TestCase):
    def test_chain_goes_down_to_one_pixel(self):
        mips = vtf.mip_chain(gradient(64, 16))
        self.assertEqual([m.shape[:2] for m in mips],
                         [(16, 64), (8, 32), (4, 16), (2, 8), (1, 4), (1, 2), (1, 1)])

    def test_mip_averages_in_linear_light_when_srgb(self):
        img = np.zeros((2, 2, 4), dtype=np.uint8)
        img[:, :, 3] = 255
        img[0, :, :3] = 255
        mips = vtf.mip_chain(img, srgb=True)
        # half white, half black: linear 0.5 is sRGB 188, not 128
        self.assertAlmostEqual(int(mips[1][0, 0, 0]), 188, delta=2)
        mips = vtf.mip_chain(img, srgb=False)
        self.assertAlmostEqual(int(mips[1][0, 0, 0]), 128, delta=2)


class WriterTest(unittest.TestCase):
    def test_header_and_sizes(self):
        img = gradient(32, 16)
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "t.vtf")
            vtf.write_vtf(path, img, "dxt5", srgb=True)
            with open(path, "rb") as source:
                raw = source.read()
        self.assertEqual(raw[:4], b"VTF\0")
        self.assertEqual(struct.unpack_from("<II", raw, 4), (7, 2))
        self.assertEqual(struct.unpack_from("<I", raw, 12)[0], 80)
        width, height, flags = struct.unpack_from("<HHI", raw, 16)
        self.assertEqual((width, height), (32, 16))
        self.assertTrue(flags & 0x40)  # SRGB
        self.assertTrue(flags & 0x4 and flags & 0x8)  # clamp S and T
        self.assertEqual(struct.unpack_from("<H", raw, 24)[0], 1)  # frames
        self.assertEqual(struct.unpack_from("<i", raw, 52)[0], 15)  # DXT5
        self.assertEqual(raw[56], 6)  # 32x16 -> 6 levels
        self.assertEqual(struct.unpack_from("<i", raw, 57)[0], -1)  # no low resolution image
        self.assertEqual(struct.unpack_from("<H", raw, 63)[0], 1)  # depth
        # data: 1x1 .. 32x16, smallest first
        sizes = [max(1, (max(1, 32 >> m) + 3) // 4) * max(1, (max(1, 16 >> m) + 3) // 4) * 16 for m in range(6)]
        self.assertEqual(len(raw), 80 + sum(sizes))

    def test_biggest_mip_comes_last(self):
        img = np.zeros((8, 8, 4), dtype=np.uint8)
        img[:, :] = (255, 255, 255, 255)
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "t.vtf")
            vtf.write_vtf(path, img, "bgra8888", srgb=False)
            with open(path, "rb") as source:
                raw = source.read()
        self.assertEqual(len(raw), 80 + sum((8 >> m or 1) ** 2 * 4 for m in range(4)))
        self.assertEqual(raw[-4:], bytes([255, 255, 255, 255]))
        self.assertEqual(struct.unpack_from("<i", raw, 52)[0], 12)

    def test_no_mips(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "t.vtf")
            vtf.write_vtf(path, gradient(16, 16), "dxt5", srgb=False, mips=False)
            with open(path, "rb") as source:
                raw = source.read()
        self.assertEqual(raw[56], 1)
        self.assertTrue(struct.unpack_from("<I", raw, 20)[0] & 0x100)  # NOMIP
        self.assertEqual(len(raw), 80 + 256)

    def test_vmt_text(self):
        text = vtf.vmt_text("grymod/flash/hud_x_1")
        self.assertIn('"$basetexture" "grymod/flash/hud_x_1"', text)
        self.assertIn('"UnlitGeneric"', text)

    def test_read_back(self):
        img = gradient(16, 16)
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "t.vtf")
            vtf.write_vtf(path, img, "bgra8888", srgb=False)
            back = vtf.read_vtf_top(path)
        self.assertTrue((back == img).all())
        smooth = gradient(64, 64)
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "t.vtf")
            vtf.write_vtf(path, smooth, "dxt5", srgb=False)
            back = vtf.read_vtf_top(path).astype(int)
        self.assertLess(np.abs(back[:, :, :3] - smooth[:, :, :3]).mean(), 3.0)


class RepeatAndGreyTest(unittest.TestCase):
    """Textures that must repeat (noise, interference) and 8-bit grey data (a volume cut into tiles)."""

    def flags_of(self, **kwargs):
        raw = vtf.vtf_bytes(gradient(16, 4), "bgra8888", srgb=False, mips=False, **kwargs)
        return struct.unpack_from("<I", raw, 20)[0]

    def test_clamps_both_axes_by_default(self):
        flags = self.flags_of()
        self.assertTrue(flags & vtf.FLAG_CLAMPS and flags & vtf.FLAG_CLAMPT)

    def test_clamp_can_be_taken_off_per_axis(self):
        flags = self.flags_of(clamp="")
        self.assertFalse(flags & (vtf.FLAG_CLAMPS | vtf.FLAG_CLAMPT))
        flags = self.flags_of(clamp="t")
        self.assertFalse(flags & vtf.FLAG_CLAMPS)
        self.assertTrue(flags & vtf.FLAG_CLAMPT)
        flags = self.flags_of(clamp="s")
        self.assertTrue(flags & vtf.FLAG_CLAMPS)
        self.assertFalse(flags & vtf.FLAG_CLAMPT)

    def test_clamp_rejects_unknown_axes(self):
        with self.assertRaises(ValueError):
            vtf.vtf_bytes(gradient(4, 4), "bgra8888", clamp="x")

    def test_i8_is_one_byte_per_pixel_and_reads_back_as_grey(self):
        img = gradient(16, 8)
        raw = vtf.vtf_bytes(img, "i8", srgb=False, mips=False, clamp="")
        self.assertEqual(struct.unpack_from("<i", raw, 52)[0], 5)  # IMAGE_FORMAT_I8
        self.assertEqual(len(raw), 80 + 16 * 8)
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "t.vtf")
            with open(path, "wb") as out:
                out.write(raw)
            back = vtf.read_vtf_top(path)
        self.assertTrue((back[:, :, 0] == img[:, :, 0]).all())
        self.assertTrue((back[:, :, 1] == back[:, :, 0]).all() and (back[:, :, 2] == back[:, :, 0]).all())
        self.assertTrue((back[:, :, 3] == 255).all())

    def test_a_texture_one_texel_high_is_allowed(self):
        img = gradient(256, 1)
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "t.vtf")
            vtf.write_vtf(path, img, "bgra8888", srgb=False, mips=False, clamp="")
            back = vtf.read_vtf_top(path)
        self.assertEqual(back.shape, (1, 256, 4))
        self.assertTrue((back == img).all())

    def test_read_back_with_mips_of_a_flat_texture(self):
        img = gradient(256, 8)
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "t.vtf")
            vtf.write_vtf(path, img, "bgra8888", srgb=False, mips=True, clamp="")
            back = vtf.read_vtf_top(path)
        self.assertTrue((back == img).all())


class VolumeTest(unittest.TestCase):
    """A volume texture (the depth field of the header above 1): the slices follow one another, no mip levels."""

    def volume(self, depth=4, h=8, w=16):
        vol = np.zeros((depth, h, w, 4), dtype=np.uint8)
        for k in range(depth):
            vol[k, :, :, :3] = k * 60 + 10
            vol[k, :, :, 3] = 255

        return vol

    def test_the_header_carries_the_depth_and_the_size_is_the_slices_one_after_the_other(self):
        raw = vtf.vtf_bytes(self.volume(), "i8", srgb=False, mips=False, clamp="")
        self.assertEqual(struct.unpack_from("<H", raw, 63)[0], 4)
        self.assertEqual(struct.unpack_from("<HH", raw, 16), (16, 8))
        self.assertEqual(len(raw), 80 + 4 * 16 * 8)

    def test_slice_k_is_the_k_th_block_of_the_data(self):
        raw = vtf.vtf_bytes(self.volume(), "i8", srgb=False, mips=False, clamp="")
        for k in range(4):
            block = raw[80 + k * 16 * 8:80 + (k + 1) * 16 * 8]
            self.assertEqual(set(block), {k * 60 + 10})

    def test_a_flat_texture_keeps_a_depth_of_one(self):
        raw = vtf.vtf_bytes(gradient(16, 8), "i8", srgb=False, mips=False, clamp="")
        self.assertEqual(struct.unpack_from("<H", raw, 63)[0], 1)

    def test_the_other_formats_stack_the_slices_too(self):
        raw = vtf.vtf_bytes(self.volume(2, 4, 4), "bgra8888", srgb=False, mips=False, clamp="")
        self.assertEqual(len(raw), 80 + 2 * 4 * 4 * 4)
        self.assertEqual(struct.unpack_from("<H", raw, 63)[0], 2)

    def test_a_volume_has_no_mip_levels(self):
        with self.assertRaises(ValueError):
            vtf.vtf_bytes(self.volume(), "i8", srgb=False, mips=True)

    def test_the_depth_is_a_power_of_two(self):
        with self.assertRaises(ValueError):
            vtf.vtf_bytes(self.volume(3), "i8", srgb=False, mips=False)


if __name__ == "__main__":
    unittest.main()
