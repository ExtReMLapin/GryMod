"""Tests for tools/extract_cloak_textures.py (the DDS decoder and the conversion to VTF). No game file is needed:
the DDS files and the archive are built here.

    python -I -m unittest discover -s tools -p "test_extract_cloak_textures.py"
"""
import contextlib
import io
import json
import os
import struct
import sys
import tempfile
import unittest
import zipfile

import numpy as np

# `python -I` does not put the repository on the path (tools/ has no __init__.py: a namespace package)
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))

from tools import extract_cloak_textures as ect
from tools.flash2lua import vtf

DDSD_MIPMAPCOUNT = 0x20000
DDSD_DEPTH = 0x800000


def make_dds(width, height, pixel_format, payload, mips=0, depth=0):
    """A DDS file: pixel_format = (flags, fourcc, bit count, r, g, b, a masks)."""
    flags = 0x1007
    if mips:
        flags |= DDSD_MIPMAPCOUNT
    if depth:
        flags |= DDSD_DEPTH
    fl, fourcc, bits, rm, gm, bm, am = pixel_format
    header = struct.pack("<4sI", b"DDS ", 124)
    header += struct.pack("<IIIIII", flags, height, width, 0, depth, mips)
    header += b"\0" * 44
    header += struct.pack("<II4sIIIII", 32, fl, fourcc, bits, rm, gm, bm, am)
    header += struct.pack("<IIII", 0x1000, 0, 0, 0) + b"\0" * 4
    assert len(header) == 128, len(header)
    return header + payload


ARGB = (0x41, b"", 32, 0xFF0000, 0xFF00, 0xFF, 0xFF000000)
RGB24 = (0x40, b"", 24, 0xFF0000, 0xFF00, 0xFF, 0)
A8 = (0x2, b"", 8, 0, 0, 0, 0xFF)
L8 = (0x20000, b"", 8, 0xFF, 0, 0, 0)
DXT1 = (0x4, b"DXT1", 0, 0, 0, 0, 0)
DXT3 = (0x4, b"DXT3", 0, 0, 0, 0, 0)
DXT5 = (0x4, b"DXT5", 0, 0, 0, 0, 0)
ATI2 = (0x4, b"ATI2", 0, 0, 0, 0, 0)


def gradient(w, h):
    img = np.zeros((h, w, 4), dtype=np.uint8)
    img[:, :, 0] = np.linspace(0, 255, w).astype(np.uint8)[None, :]
    img[:, :, 1] = np.linspace(255, 0, h).astype(np.uint8)[:, None]
    img[:, :, 2] = (np.arange(w)[None, :] * 7 + np.arange(h)[:, None] * 3) % 256
    img[:, :, 3] = np.linspace(10, 250, w).astype(np.uint8)[None, :]
    return img


class ParseTest(unittest.TestCase):
    def test_sizes_mips_and_formats(self):
        cases = [(ARGB, "ARGB8888", 4 * 4 * 2), (RGB24, "RGB888", 3 * 4 * 2), (A8, "A8", 4 * 2), (L8, "L8", 4 * 2),
                 (DXT1, "DXT1", 8 * 1), (DXT3, "DXT3", 16), (DXT5, "DXT5", 16), (ATI2, "ATI2", 16)]
        for fmt, name, size in cases:
            info = ect.parse_dds(make_dds(4, 2, fmt, b"\0" * size))
            self.assertEqual(info.format, name)
            self.assertEqual((info.width, info.height, info.depth, info.mips), (4, 2, 1, 1), name)
            self.assertFalse(info.is_volume)

    def test_mip_count_is_read_only_when_the_flag_is_set(self):
        info = ect.parse_dds(make_dds(4, 4, A8, b"\0" * 16, mips=3))
        self.assertEqual(info.mips, 3)
        # a count of 5 in a header without the flag is garbage: one level
        raw = bytearray(make_dds(4, 4, A8, b"\0" * 16))
        struct.pack_into("<I", raw, 28, 5)
        self.assertEqual(ect.parse_dds(bytes(raw)).mips, 1)

    def test_volume(self):
        info = ect.parse_dds(make_dds(2, 2, A8, b"\0" * 8, mips=1, depth=2))
        self.assertTrue(info.is_volume)
        self.assertEqual((info.width, info.height, info.depth), (2, 2, 2))

    def test_not_a_dds(self):
        with self.assertRaises(ValueError):
            ect.parse_dds(b"RIFF" + b"\0" * 200)

    def test_unknown_fourcc_is_refused(self):
        with self.assertRaises(ValueError):
            ect.parse_dds(make_dds(4, 4, (0x4, b"DX10", 0, 0, 0, 0, 0), b"\0" * 16))

    def test_short_data_is_refused(self):
        with self.assertRaises(ValueError):
            ect.decode_dds(make_dds(4, 4, ARGB, b"\0" * 10))


class UncompressedTest(unittest.TestCase):
    def test_argb_channel_order(self):
        # bytes in the file: B, G, R, A
        data = make_dds(2, 1, ARGB, bytes([10, 20, 30, 40, 50, 60, 70, 80]))
        info, img = ect.decode_dds(data)
        self.assertEqual(img.shape, (1, 1, 2, 4))
        self.assertEqual(img[0, 0, 0].tolist(), [30, 20, 10, 40])
        self.assertEqual(img[0, 0, 1].tolist(), [70, 60, 50, 80])

    def test_rgb24_is_opaque(self):
        info, img = ect.decode_dds(make_dds(2, 1, RGB24, bytes([1, 2, 3, 4, 5, 6])))
        self.assertEqual(img[0, 0, 0].tolist(), [3, 2, 1, 255])
        self.assertEqual(img[0, 0, 1].tolist(), [6, 5, 4, 255])

    def test_a8_becomes_opaque_grey(self):
        info, img = ect.decode_dds(make_dds(3, 1, A8, bytes([0, 128, 255])))
        self.assertEqual(img[0, 0].tolist(), [[0, 0, 0, 255], [128, 128, 128, 255], [255, 255, 255, 255]])
        self.assertTrue(info.alpha_only)

    def test_a8_written_with_the_alpha_pixels_flag_only(self):
        # Crytek's own files: flags 0x1 (ALPHAPIXELS), 8 bits, alpha mask 0xFF, no colour mask (the 3D noise)
        crytek = (0x1, b"", 8, 0, 0, 0, 0xFF)
        info, img = ect.decode_dds(make_dds(2, 1, crytek, bytes([3, 250])))
        self.assertEqual(info.format, "A8")
        self.assertEqual(img[0, 0].tolist(), [[3, 3, 3, 255], [250, 250, 250, 255]])

    def test_l8(self):
        info, img = ect.decode_dds(make_dds(2, 1, L8, bytes([7, 200])))
        self.assertEqual(img[0, 0].tolist(), [[7, 7, 7, 255], [200, 200, 200, 255]])

    def test_other_masks_are_scaled_to_eight_bits(self):
        r5g6b5 = (0x40, b"", 16, 0xF800, 0x07E0, 0x001F, 0)
        data = make_dds(2, 1, r5g6b5, struct.pack("<HH", 0xF800, 0x07FF))
        info, img = ect.decode_dds(data)
        self.assertEqual(img[0, 0, 0].tolist(), [255, 0, 0, 255])
        self.assertEqual(img[0, 0, 1].tolist(), [0, 255, 255, 255])

    def test_only_the_first_mip_level_is_decoded(self):
        payload = bytes([9, 8, 7, 6]) + bytes([1])  # 2x2 then 1x1
        info, img = ect.decode_dds(make_dds(2, 2, A8, payload, mips=2))
        self.assertEqual(info.mips, 2)
        self.assertEqual(img[0, :, :, 0].tolist(), [[9, 8], [7, 6]])

    def test_volume_slices(self):
        payload = bytes(range(8))  # 2 x 2 x 2
        info, img = ect.decode_dds(make_dds(2, 2, A8, payload, mips=1, depth=2))
        self.assertEqual(img.shape, (2, 2, 2, 4))
        self.assertEqual(img[0, :, :, 0].tolist(), [[0, 1], [2, 3]])
        self.assertEqual(img[1, :, :, 0].tolist(), [[4, 5], [6, 7]])


class CompressedTest(unittest.TestCase):
    def test_dxt1_four_colour_mode(self):
        # c0 red, c1 blue, indices 0 1 2 3 in every row
        block = struct.pack("<HHI", 0xF800, 0x001F, 0xE4E4E4E4)
        info, img = ect.decode_dds(make_dds(4, 4, DXT1, block))
        row = img[0, 0].tolist()
        self.assertEqual(row, [[255, 0, 0, 255], [0, 0, 255, 255], [170, 0, 85, 255], [85, 0, 170, 255]])
        self.assertTrue((img[0, 3] == img[0, 0]).all())

    def test_dxt1_three_colour_mode_has_a_transparent_texel(self):
        block = struct.pack("<HHI", 0x001F, 0xF800, 0xE4E4E4E4)  # c0 <= c1
        info, img = ect.decode_dds(make_dds(4, 4, DXT1, block))
        row = img[0, 0].tolist()
        self.assertEqual(row[0], [0, 0, 255, 255])
        self.assertEqual(row[1], [255, 0, 0, 255])
        for got, want in zip(row[2], [127, 0, 127, 255]):
            self.assertAlmostEqual(got, want, delta=1)
        self.assertEqual(row[3], [0, 0, 0, 0])

    def test_dxt3_explicit_alpha(self):
        alpha = bytes([0x50, 0xFA]) + bytes(6)  # first row: 0, 5, 10, 15 (4 bits each)
        colour = struct.pack("<HHI", 0xF800, 0xF800, 0)
        info, img = ect.decode_dds(make_dds(4, 4, DXT3, alpha + colour))
        self.assertEqual(img[0, 0, :, 3].tolist(), [0, 85, 170, 255])
        self.assertEqual(img[0, 0, 0, :3].tolist(), [255, 0, 0])
        self.assertEqual(img[0, 1, :, 3].tolist(), [0, 0, 0, 0])

    def test_dxt5_matches_the_encoder_of_vtf_py(self):
        img = gradient(16, 8)
        data = vtf.encode_dxt5(img)
        info, got = ect.decode_dds(make_dds(16, 8, DXT5, data))
        self.assertTrue((got[0] == vtf.decode_dxt5(data, 16, 8)).all())

    def test_bc4_blocks_match_the_alpha_of_dxt5(self):
        # an alpha ramp makes the encoder use both the eight-level and the six-level modes
        img = gradient(16, 8)
        img[:4, :4, 3] = np.array([0, 255, 255, 0] * 4).reshape(4, 4)
        img[4:, 4:8, 3] = np.array([3, 60, 200, 254] * 4).reshape(4, 4)
        data = vtf.encode_dxt5(img)
        blocks = np.frombuffer(data, dtype=np.uint8).reshape(-1, 16)
        mine = ect.decode_bc4_blocks(np.ascontiguousarray(blocks[:, :8]))
        want = vtf.decode_dxt5(data, 16, 8)[:, :, 3]
        got = mine.reshape(2, 4, 4, 4).transpose(0, 2, 1, 3).reshape(8, 16)
        self.assertEqual(np.abs(got.astype(int) - want).max(), 0)

    def test_ati2_normal_map_rebuilds_z(self):
        flat = struct.pack("<BB6B", 128, 128, 0, 0, 0, 0, 0, 0)  # every texel 128
        info, img = ect.decode_dds(make_dds(4, 4, ATI2, flat + flat))
        r, g, b, a = img[0, 0, 0].tolist()
        self.assertEqual((r, g), (128, 128))
        self.assertAlmostEqual(b, 255, delta=1)  # x and y are almost 0: the normal points out
        self.assertEqual(a, 255)

    def test_ati2_full_x_has_no_z(self):
        xs = struct.pack("<BB6B", 255, 255, 0, 0, 0, 0, 0, 0)
        ys = struct.pack("<BB6B", 128, 128, 0, 0, 0, 0, 0, 0)
        info, img = ect.decode_dds(make_dds(4, 4, ATI2, xs + ys))
        r, g, b, a = img[0, 0, 0].tolist()
        self.assertEqual(r, 255)
        self.assertAlmostEqual(b, 128, delta=1)  # z = 0 -> 0.5


class VolumeAtlasTest(unittest.TestCase):
    def test_tiles_are_laid_out_row_by_row(self):
        vol = np.zeros((6, 2, 3, 4), dtype=np.uint8)
        for k in range(6):
            vol[k, :, :, 0] = k + 1
        atlas, cols, rows = ect.volume_atlas(vol, columns=4)
        self.assertEqual((cols, rows), (4, 2))
        self.assertEqual(atlas.shape, (4, 12, 4))
        self.assertEqual(atlas[0, 0, 0], 1)
        self.assertEqual(atlas[0, 3, 0], 2)  # slice 1 is the second tile of the first row
        self.assertEqual(atlas[2, 0, 0], 5)  # slice 4 starts the second row
        self.assertEqual(atlas[2, 9, 0], 0)  # the unused tiles stay black

    def test_default_layout_of_a_128_cube(self):
        vol = np.zeros((128, 128, 128, 4), dtype=np.uint8)
        atlas, cols, rows = ect.volume_atlas(vol)
        self.assertEqual((cols, rows), (16, 8))
        self.assertEqual(atlas.shape, (1024, 2048, 4))

    def test_atlas_is_lossless(self):
        rng = np.random.default_rng(3)
        vol = rng.integers(0, 256, size=(8, 4, 4, 4), dtype=np.uint8)
        atlas, cols, rows = ect.volume_atlas(vol, columns=4)
        for k in range(8):
            y, x = divmod(k, cols)
            self.assertTrue((atlas[y * 4:(y + 1) * 4, x * 4:(x + 1) * 4] == vol[k]).all())


class PakTest(unittest.TestCase):
    def test_reads_entries_whatever_the_case_and_separator(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "T.pak")
            with zipfile.ZipFile(path, "w") as z:
                z.writestr("Textures/Defaults/Noise3D.dds", b"abc")
            self.assertEqual(ect.read_pak_entry(path, "textures\\defaults\\noise3d.dds"), b"abc")
            with self.assertRaises(KeyError):
                ect.read_pak_entry(path, "textures/defaults/nothing.dds")


class ConvertTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.game = os.path.join(self.tmp.name, "Game")
        os.makedirs(self.game)
        self.out = os.path.join(self.tmp.name, "out")

    def pak(self, name, entries):
        with zipfile.ZipFile(os.path.join(self.game, name), "w") as z:
            for entry, data in entries.items():
                z.writestr(entry, data)

    def test_a_small_lookup_texture_keeps_its_four_channels_and_does_not_clamp(self):
        argb = gradient(256, 1)
        payload = argb[:, :, [2, 1, 0, 3]].tobytes()  # BGRA in the file
        self.pak("Textures.pak", {"textures/defaults/palette/t.dds": make_dds(256, 1, ARGB, payload)})
        spec = ect.Spec("t", "Textures.pak", "textures/defaults/palette/t.dds", "bgra8888", mips=False, clamp="s")
        entry = ect.convert(spec, self.game, self.out)
        path = os.path.join(self.out, "t.vtf")
        self.assertTrue(os.path.isfile(path))
        self.assertTrue((vtf.read_vtf_top(path) == argb).all())
        with open(path, "rb") as source:
            flags = struct.unpack_from("<I", source.read(), 20)[0]
        self.assertTrue(flags & vtf.FLAG_CLAMPS)
        self.assertFalse(flags & vtf.FLAG_CLAMPT)
        self.assertFalse(flags & vtf.FLAG_SRGB)
        self.assertEqual(entry["width"], 256)
        self.assertEqual(entry["height"], 1)
        self.assertEqual(entry["dds_format"], "ARGB8888")
        self.assertEqual(entry["dds_mips"], 1)
        self.assertFalse(entry["volume"])

    def test_a_volume_becomes_an_atlas_of_its_slices(self):
        vol = (np.arange(8 * 4 * 4, dtype=np.uint32) * 5 % 256).astype(np.uint8)
        self.pak("Textures.pak", {"v.dds": make_dds(4, 4, A8, vol.tobytes(), mips=1, depth=8)})
        spec = ect.Spec("v", "Textures.pak", "v.dds", "i8", mips=False, clamp="", atlas_columns=4)
        entry = ect.convert(spec, self.game, self.out)
        back = vtf.read_vtf_top(os.path.join(self.out, "v.vtf"))
        self.assertEqual(back.shape, (8, 16, 4))
        self.assertEqual(back[0, 0, 0], vol[0])
        self.assertEqual(back[4, 0, 0], vol[4 * 4 * 4])  # slice 4: second row of tiles
        self.assertTrue(entry["volume"])
        self.assertEqual(entry["depth"], 8)
        self.assertEqual(entry["atlas"], {"columns": 4, "rows": 2, "tile": [4, 4]})

    def test_round_trip_is_checked_and_a_mismatch_is_reported(self):
        self.pak("Textures.pak", {"a.dds": make_dds(4, 4, ARGB, gradient(4, 4)[:, :, [2, 1, 0, 3]].tobytes())})
        spec = ect.Spec("a", "Textures.pak", "a.dds", "bgra8888", mips=True, clamp="st")
        entry = ect.convert(spec, self.game, self.out)
        self.assertEqual(entry["round_trip_max_error"], 0)
        # a lossy format cannot be exact: the error is reported, not hidden
        spec = ect.Spec("b", "Textures.pak", "a.dds", "dxt5", mips=False, clamp="st")
        entry = ect.convert(spec, self.game, self.out)
        self.assertGreater(entry["round_trip_max_error"], 0)

    def test_the_png_of_a_texture_is_what_the_dds_holds(self):
        from PIL import Image
        self.pak("Textures.pak", {"a.dds": make_dds(4, 1, A8, bytes([0, 64, 128, 255]))})
        spec = ect.Spec("a", "Textures.pak", "a.dds", "bgra8888", mips=False, clamp="")
        png_dir = os.path.join(self.tmp.name, "png")
        ect.convert(spec, self.game, self.out, png_dir=png_dir)
        img = Image.open(os.path.join(png_dir, "a.png"))
        self.assertEqual(img.size, (4, 1))
        self.assertEqual(list(np.asarray(img.convert("L"))[0]), [0, 64, 128, 255])

    def test_a_missing_entry_names_the_archive(self):
        self.pak("Textures.pak", {})
        spec = ect.Spec("a", "Textures.pak", "nope.dds", "bgra8888", mips=False, clamp="")
        with self.assertRaises(KeyError) as ctx:
            ect.convert(spec, self.game, self.out)
        self.assertIn("Textures.pak", str(ctx.exception))

    def test_the_list_is_only_original_names_and_valid_formats(self):
        names = [spec.name for spec in ect.SPECS]
        self.assertEqual(len(names), len(set(names)))
        for spec in ect.SPECS:
            self.assertIn(spec.vtf_format, vtf.FORMATS)
            self.assertTrue(spec.path.endswith(".dds"), spec.path)
        # the textures the shader CloakLayer.cfx reads
        for needed in ("cloak_interlation", "cloak_sparks", "cloak_palette", "cloak_transition", "noise3d"):
            self.assertIn(needed, names)

    def test_main_writes_every_texture_and_the_manifest(self):
        entries = {}
        for spec in ect.SPECS:
            entries.setdefault(spec.pak, {})
        # a tiny stand-in for each texture of the list
        for spec in ect.SPECS:
            entries[spec.pak][spec.path] = make_dds(4, 4, ARGB, gradient(4, 4)[:, :, [2, 1, 0, 3]].tobytes())
        for pak, content in entries.items():
            self.pak(pak, content)
        manifest = os.path.join(self.tmp.name, "m.json")
        code = ect.main([self.game, "--out", self.out, "--manifest", manifest], quiet=True)
        self.assertEqual(code, 0)
        for spec in ect.SPECS:
            self.assertTrue(os.path.isfile(os.path.join(self.out, spec.name + ".vtf")), spec.name)
        with open(manifest, encoding="utf8") as f:
            data = json.load(f)
        self.assertEqual({e["name"] for e in data["textures"]}, {s.name for s in ect.SPECS})

    def test_nothing_of_the_game_is_written_in_a_materials_folder(self):
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            ect.main([self.game, "--out", os.path.join(self.tmp.name, "x", "materials", "grymod")], quiet=True)

    def test_main_reports_a_missing_game_folder(self):
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            ect.main([os.path.join(self.tmp.name, "nothing"), "--out", self.out], quiet=True)


if __name__ == "__main__":
    unittest.main()
