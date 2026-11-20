import os
import tempfile
import unittest

from PIL import Image

from tools.flash2lua import compare_pixels


def save(color_rows, path):
    h, w = len(color_rows), len(color_rows[0])
    im = Image.new("RGB", (w, h))
    im.putdata([c for row in color_rows for c in row])
    im.save(path)


class ComparePixelsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.bg = (51, 51, 51)

    def pair(self, ref_rows, got_rows):
        ref, got = os.path.join(self.tmp, "ref.png"), os.path.join(self.tmp, "got.png")
        save(ref_rows, ref)
        save(got_rows, got)
        return ref, got

    def test_identical_images_have_no_difference(self):
        rows = [[self.bg, (255, 0, 0)], [(255, 0, 0), self.bg]]
        ref, got = self.pair(rows, rows)
        result = compare_pixels.compare(ref, got, self.bg)
        self.assertEqual(result["different"], 0)
        self.assertEqual(result["content"], 2)

    def test_a_missing_shape_counts_against_the_content(self):
        ref, got = self.pair([[self.bg, (255, 0, 0)]], [[self.bg, self.bg]])
        result = compare_pixels.compare(ref, got, self.bg)
        self.assertEqual((result["different"], result["content"]), (1, 1))
        self.assertEqual(result["fraction"], 1.0)

    def test_small_colour_differences_are_within_tolerance(self):
        ref, got = self.pair([[(100, 100, 100)]], [[(110, 95, 100)]])
        self.assertEqual(compare_pixels.compare(ref, got, self.bg, tolerance=16)["different"], 0)
        self.assertEqual(compare_pixels.compare(ref, got, self.bg, tolerance=4)["different"], 1)

    def test_size_mismatch_is_an_error(self):
        ref, got = self.pair([[self.bg]], [[self.bg, self.bg]])
        with self.assertRaises(ValueError):
            compare_pixels.compare(ref, got, self.bg)

    def test_diff_image_is_written(self):
        ref, got = self.pair([[self.bg, (255, 0, 0)]], [[self.bg, self.bg]])
        out = os.path.join(self.tmp, "diff.png")
        compare_pixels.compare(ref, got, self.bg, diff_path=out)
        self.assertTrue(os.path.exists(out))


if __name__ == "__main__":
    unittest.main()
