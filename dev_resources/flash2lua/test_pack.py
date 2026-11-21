"""Tests for the rectangle packer (no FFDec needed)."""
import random
import unittest

from dev_resources.flash2lua import pack


def overlaps(a, b):
    return not (a[0] + a[2] <= b[0] or b[0] + b[2] <= a[0] or a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1])


class PackTest(unittest.TestCase):
    def test_everything_is_inside_and_apart(self):
        rng = random.Random(3)
        items = [(i, rng.randint(8, 300), rng.randint(8, 300)) for i in range(60)]
        w, h, placed = pack.pack_pow2(items, gap=2)
        self.assertEqual(set(placed), {i for i, _, _ in items})
        rects = []
        for key, iw, ih in items:
            x, y = placed[key]
            self.assertGreaterEqual(x, 0)
            self.assertGreaterEqual(y, 0)
            self.assertLessEqual(x + iw, w)
            self.assertLessEqual(y + ih, h)
            rects.append((x, y, iw + 2, ih + 2))
        for i, a in enumerate(rects):
            for b in rects[i + 1:]:
                self.assertFalse(overlaps(a, b))

    def test_sheet_is_a_power_of_two_and_the_smallest_that_fits(self):
        w, h, _ = pack.pack_pow2([(1, 30, 30), (2, 30, 30)], gap=2)
        self.assertEqual(w & (w - 1), 0)
        self.assertEqual(h & (h - 1), 0)
        self.assertLessEqual(w * h, 128 * 64)

    def test_a_big_shape_forces_a_big_sheet(self):
        w, h, placed = pack.pack_pow2([(1, 1000, 1000)], gap=2)
        self.assertGreaterEqual(w, 1024)
        self.assertGreaterEqual(h, 1024)

    def test_too_much_raises(self):
        with self.assertRaises(ValueError):
            pack.pack_pow2([(i, 1000, 1000) for i in range(30)])

    def test_tighter_than_a_shelf_for_a_quarter_filled_sheet(self):
        # 3.86 M pixels of shapes used to need a 4096 x 4096 sheet (16.7 M)
        items = [(i, 400, 400) for i in range(22)]
        w, h, _ = pack.pack_pow2(items, gap=2)
        self.assertLessEqual(w * h, 2048 * 2048)


class SheetsTest(unittest.TestCase):
    def test_two_small_sheets_beat_one_big_one(self):
        # 8 shapes of 1000 x 500: 4 M pixels, which a 2048 x 4096 sheet (8.4 M) held for lack of a better fit
        items = [(i, 1000, 500) for i in range(8)]
        sheets, placed = pack.pack_sheets(items, gap=2)
        self.assertLessEqual(sum(w * h for w, h in sheets), 2048 * 2048 + 2048 * 1024)

    def test_every_shape_is_inside_its_sheet_and_apart(self):
        rng = random.Random(5)
        items = [(i, rng.randint(8, 400), rng.randint(8, 400)) for i in range(50)]
        sheets, placed = pack.pack_sheets(items, gap=2)
        by_sheet = {}
        for key, w, h in items:
            sheet, x, y = placed[key]
            sw, sh = sheets[sheet]
            self.assertLessEqual(x + w, sw)
            self.assertLessEqual(y + h, sh)
            by_sheet.setdefault(sheet, []).append((x, y, w + 2, h + 2))
        for rects in by_sheet.values():
            for i, a in enumerate(rects):
                for b in rects[i + 1:]:
                    self.assertFalse(overlaps(a, b))

    def test_a_single_shape_gets_a_single_sheet(self):
        sheets, placed = pack.pack_sheets([(1, 100, 100)])
        self.assertEqual(len(sheets), 1)
        self.assertLessEqual(sheets[0][0] * sheets[0][1], 128 * 128)


if __name__ == "__main__":
    unittest.main()
