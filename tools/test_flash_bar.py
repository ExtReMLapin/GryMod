"""Tests of lua/grymod/sh_flash_bar.lua, the pure part of the smooth energy bars (needs `pip install lupa`: it carries LuaJIT, the Lua of the game).

Run from the repository root:  python -I tools/test_flash_bar.py

The module has no game global: it turns a value of a bar into a frame, a fraction and the x of the cut line that shows the fraction, with
numbers only. These tests load it in a plain LuaJIT, and the real data of the two converted movies (the suit energy bar of
hud_ammohealthenergysuit.lua, sprite 16, and the night vision bar of hud_nightvision.lua, sprite 12) from the generated Lua files.
"""
import math
import os
import unittest

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # the CI installs lupa
    LuaRuntime = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULE = os.path.join(ROOT, "lua", "grymod", "sh_flash_bar.lua")
SUIT = os.path.join(ROOT, "lua", "grymod", "flash", "hud_ammohealthenergysuit.lua")
NIGHT = os.path.join(ROOT, "lua", "grymod", "flash", "hud_nightvision.lua")

# the sprites that hold the bars: id, frames, value offset (the frame of a value is floor(value + offset))
SUIT_ENERGY, SUIT_HEALTH, NIGHT_BAR = 16, 25, 12


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


@unittest.skipUnless(LuaRuntime, "lupa is not installed")
class FlashBar(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = LuaRuntime(unpack_returned_tuples=True)
        cls.load = cls.lua.eval("function(src, name) local f = assert(loadstring(src, name)) return f() end")
        cls.bar = cls.load(read(MODULE), "sh_flash_bar.lua")
        cls.suit = cls.load(read(SUIT), "suit")
        cls.night = cls.load(read(NIGHT), "night")

    def edges(self, movie, sprite):
        return self.bar.Edges(movie.chars[sprite], movie.chars)

    # ---- the module itself ------------------------------------------------------------------------------------------------------------

    def test_the_module_uses_no_game_global(self):
        env = self.lua.eval("function(src) local env = setmetatable({}, {__index = function(_, k) if k == 'math' or k == 'type' or k == 'pairs' or k == 'ipairs' or k == 'tonumber' then return _G[k] end error('global ' .. tostring(k)) end, __newindex = function(_, k) error('sets global ' .. tostring(k)) end}) local f = assert(loadstring(src)) setfenv(f, env) return f() end")
        self.assertIsNotNone(env(read(MODULE)))

    # ---- Split: a position of a bar is a frame and a fraction -------------------------------------------------------------------

    def test_split_whole_steps_have_no_fraction(self):
        for n in (100, 102):
            for frame in range(1, n + 1):
                f, t = self.bar.Split(float(frame), n)
                self.assertEqual((f, t), (frame, 0))

    def test_split_midpoints_and_quarters(self):
        f, t = self.bar.Split(50.5, 100)
        self.assertEqual(f, 50)
        self.assertAlmostEqual(t, 0.5)
        f, t = self.bar.Split(50.25, 100)
        self.assertEqual(f, 50)
        self.assertAlmostEqual(t, 0.25)

    def test_split_clamps_and_survives_nan(self):
        n = 100
        self.assertEqual(tuple(self.bar.Split(0, n)), (1, 0))
        self.assertEqual(tuple(self.bar.Split(-5, n)), (1, 0))
        self.assertEqual(tuple(self.bar.Split(1e9, n)), (n, 0))
        self.assertEqual(tuple(self.bar.Split(float("inf"), n)), (n, 0))
        self.assertEqual(tuple(self.bar.Split(float("-inf"), n)), (1, 0))
        self.assertEqual(tuple(self.bar.Split(float("nan"), n)), (1, 0))
        self.assertEqual(tuple(self.bar.Split(None, n)), (1, 0))
        self.assertEqual(tuple(self.bar.Split("50.5", n))[0], 1)  # a string is not a number: the first frame
        # the last frame has no next one: no fraction
        self.assertEqual(tuple(self.bar.Split(99.5, n))[0], 99)
        self.assertEqual(tuple(self.bar.Split(100.0, n)), (100, 0))

    # ---- Position: the value of a bar to its position on the frames ------------------------------------------------------------

    def test_position_of_the_suit_energy(self):
        # the original: frame floor(energy), the frames 1 to 100 (0 and 1 are both the first one)
        P = self.bar.Position
        self.assertEqual(P(0, 0, 100), 1)
        self.assertEqual(P(1, 0, 100), 1)
        self.assertEqual(P(50, 0, 100), 50)
        self.assertEqual(P(100, 0, 100), 100)
        self.assertEqual(P(150, 0, 100), 100)
        self.assertEqual(P(-3, 0, 100), 1)
        self.assertEqual(P(float("nan"), 0, 100), 1)
        self.assertAlmostEqual(P(50.5, 0, 100), 50.5)

    def test_position_of_the_night_vision_bar(self):
        # the movie's setNightVisionBar: frame floor(value) + 1, the frames 1 to 102
        P = self.bar.Position
        self.assertEqual(P(0, 1, 102), 1)
        self.assertEqual(P(50, 1, 102), 51)
        self.assertEqual(P(100, 1, 102), 101)
        self.assertEqual(P(101, 1, 102), 102)
        self.assertEqual(P(500, 1, 102), 102)
        self.assertEqual(P(float("nan"), 1, 102), 1)
        self.assertAlmostEqual(P(50.25, 1, 102), 51.25)

    def test_the_whole_step_is_what_the_original_drew(self):
        # for every whole value the frame is the one the original picks: floor(value) for the suit, floor(value) + 1 for the night vision
        for value in range(0, 101):
            f, t = self.bar.Split(self.bar.Position(float(value), 0, 100), 100)
            self.assertEqual(f, min(max(value, 1), 100))
            self.assertEqual(t, 0)
            f, t = self.bar.Split(self.bar.Position(float(value), 1, 102), 102)
            self.assertEqual(f, value + 1)
            self.assertEqual(t, 0)

    # ---- Subdivisions and Quantise: no work when a step is under a pixel, a grid of half a pixel otherwise ----------------------------

    def test_subdivisions(self):
        S = self.bar.Subdivisions
        self.assertEqual(S(0.5), 1)
        self.assertEqual(S(1.0), 1)  # one pixel or less: drawn as today
        self.assertEqual(S(1.22), 3)
        self.assertEqual(S(1.83), 4)
        self.assertEqual(S(3.66), 8)
        self.assertEqual(S(1000), 16)  # a limit
        self.assertEqual(S(float("nan")), 1)
        self.assertEqual(S(None), 1)

    def test_quantise_keeps_whole_steps_and_snaps_to_the_grid(self):
        Q = self.bar.Quantise
        for k in (1, 3, 8, 16):
            for frame in (1, 2, 50, 99, 100, 101):
                self.assertEqual(Q(float(frame), k), frame)
        self.assertEqual(Q(50.9, 1), 50)  # a grid of 1 is today's drawing: the floor
        self.assertAlmostEqual(Q(50.3, 4), 50.25)
        self.assertAlmostEqual(Q(50.4, 4), 50.5)
        self.assertEqual(Q(float("nan"), 4), 1)

    # ---- Edges: the x of the fill's edge on each frame, from the movie's own mask ----------------------------------------------------

    def test_edges_of_the_suit_energy_bar(self):
        e = self.edges(self.suit, SUIT_ENERGY)
        self.assertIsNotNone(e)
        self.assertEqual(e.n, 100)
        # the fill grows towards the left from the right end of the bar: the edge goes down
        self.assertEqual(e.side, 1)
        edge = [e.edge[i] for i in range(1, e.n + 1)]
        self.assertAlmostEqual(edge[0], 133.65, places=2)  # the sliver of the first frame (the mask's start outline)
        self.assertLess(edge[-1], 3.0)  # the whole bar at the last one (the movie's last ratio is 99 % of the way to the end outline 1.5)
        for a, b in zip(edge, edge[1:]):
            self.assertLessEqual(b, a + 1e-9)  # never goes back
            self.assertLess(a - b, 2.0)  # no jump
        # a step of the original is 1.32 local pixels, 1.29 stage pixels once the bar's matrix (0.97525) is applied
        self.assertAlmostEqual((edge[0] - edge[-1]) / 99, 1.3214, places=3)
        self.assertAlmostEqual(e.step, 1.3214, places=3)

    def test_edges_of_the_health_bar_are_those_of_the_energy_bar_shape(self):
        e = self.edges(self.suit, SUIT_HEALTH)
        self.assertIsNotNone(e)
        self.assertEqual(e.n, 100)
        self.assertEqual(e.side, 1)
        self.assertAlmostEqual(e.step, 1.32, places=1)

    def test_edges_of_the_night_vision_bar(self):
        e = self.edges(self.night, NIGHT_BAR)
        self.assertIsNotNone(e)
        self.assertEqual(e.n, 102)
        self.assertEqual(e.side, 1)
        edge = [e.edge[i] for i in range(1, e.n + 1)]
        self.assertAlmostEqual(edge[0], 120.15, places=2)
        self.assertLess(edge[-1], -28.0)
        for a, b in zip(edge, edge[1:]):
            self.assertLessEqual(b, a + 1e-9)
            self.assertLess(a - b, 2.0)
        self.assertAlmostEqual(e.step, 1.4754, places=3)

    def test_edges_of_a_clip_without_a_mask_is_nil(self):
        self.assertIsNone(self.bar.Edges(self.night.chars[30], self.night.chars))

    # ---- Cut: the x of the line for a fraction -----------------------------------------------------------------------------------------

    def test_cut_is_the_edge_of_the_frame_on_a_whole_step_and_between_otherwise(self):
        for movie, sprite in ((self.suit, SUIT_ENERGY), (self.suit, SUIT_HEALTH), (self.night, NIGHT_BAR)):
            e = self.edges(movie, sprite)
            for f in range(1, e.n):
                lo, hi = e.edge[f], e.edge[f + 1]
                self.assertEqual(self.bar.Cut(e, f, 0), lo)
                self.assertAlmostEqual(self.bar.Cut(e, f, 1), hi)
                self.assertAlmostEqual(self.bar.Cut(e, f, 0.5), (lo + hi) / 2)
                # the cut of a position that is 0.25 is a quarter of the way
                self.assertAlmostEqual(self.bar.Cut(e, f, 0.25), lo + (hi - lo) * 0.25)
            # the last frame has no next one
            self.assertEqual(self.bar.Cut(e, e.n, 0.5), e.edge[e.n])

    def test_the_fill_follows_the_value_monotonically_and_without_a_jump(self):
        for movie, sprite, offset in ((self.suit, SUIT_ENERGY, 0), (self.suit, SUIT_HEALTH, 0), (self.night, NIGHT_BAR, 1)):
            e = self.edges(movie, sprite)
            previous = None
            value = 0.0

            while value <= 100.0:
                f, t = self.bar.Split(self.bar.Position(value, offset, e.n), e.n)
                x = self.bar.Cut(e, f, t)

                if previous is not None:
                    self.assertLessEqual(x, previous + 1e-9, (sprite, value))
                    self.assertLess(previous - x, 0.2 * e.step * 2 + 1e-9)  # a tenth of a step of value moves at most 0.2 of a step
                previous = x
                value += 0.1

    def test_the_ends(self):
        e = self.edges(self.suit, SUIT_ENERGY)
        f, t = self.bar.Split(self.bar.Position(0, 0, e.n), e.n)
        self.assertEqual(self.bar.Cut(e, f, t), e.edge[1])
        f, t = self.bar.Split(self.bar.Position(100, 0, e.n), e.n)
        self.assertEqual(self.bar.Cut(e, f, t), e.edge[e.n])
        e = self.edges(self.night, NIGHT_BAR)
        f, t = self.bar.Split(self.bar.Position(0, 1, e.n), e.n)
        self.assertEqual(self.bar.Cut(e, f, t), e.edge[1])
        # 100 is the frame 101 of 102: the original's bar is not quite full at 100 and the smooth one is not either
        f, t = self.bar.Split(self.bar.Position(100, 1, e.n), e.n)
        self.assertEqual((f, t), (101, 0))

    # ---- the colour and the other things that change from frame to frame stay the frame's: the clip is drawn at an integer frame ------

    def test_the_mask_is_the_only_thing_the_cut_needs_and_the_edge_matches_its_ratio(self):
        # the edge of a frame is the x of the mask polygon at the ratio the frame gives it: check against the movie's own numbers
        e = self.edges(self.night, NIGHT_BAR)
        mask = self.night.chars[9]  # the morph the sprite 12 masks with (depth 3)
        frames = self.night.chars[NIGHT_BAR].frames
        ratio = 0

        for f in range(1, e.n + 1):
            frame = frames[f]

            for i in range(1, len(frame) + 1):
                op = frame[i]

                if op.d == 3 and op.r is not None:
                    ratio = op.r

            t = ratio / 65535.0
            left = min(mask.p[k] + (mask.pe[k] - mask.p[k]) * t for k in range(1, 9, 2))
            self.assertAlmostEqual(e.edge[f], left, places=6, msg=f)

    # ---- the pairs of frames the colour changes in: the integer frames carry the colour, nothing is blended ----------------------------

    def test_the_cut_never_reads_a_colour(self):
        # Edges has no colour field: whatever the cx of the movie does (the red of the low night vision energy, the transition to the theme's
        # colour), it is the colour of the integer frame that is drawn
        e = self.edges(self.night, NIGHT_BAR)
        for key in ("cx", "colour", "color", "m"):
            self.assertIsNone(e[key])


if __name__ == "__main__":
    unittest.main()
