"""Tests of the backward jump of the Flash player (lua/grymod/client/cl_flash.lua, Clip:_goto), run outside the game
(needs `pip install lupa`: it carries LuaJIT, the Lua of the game).

Run from the repository root:  python -m unittest tools.test_flash_goto

A clip that goes back to an earlier frame used to be emptied and rebuilt from its first frame: every object of its
display list and every clip inside it was made again (about 10 KB of garbage for one step of the energy bar, 150 KB for
the biggest sprites). The new path keeps what is the same at both frames and only puts the moves, the colours, the
morph ratios and the blend modes of the target frame back. It is only taken when the result cannot be told from the old
path, otherwise the old path runs ("fallback").

These tests check that, with the real converted movies of the addon (lua/grymod/flash/*.lua):
  * for pairs of frames (from, to) of every sprite and of every movie's main timeline, the whole tree of clips after
    the jump (display lists, matrices, colours, ratios, names, frames, clocks, versions, text, extra fields...) is the
    same with the new path as with the old one, also after the clips were moved, made invisible, advanced, cut or
    written to directly (the writes the other files of the addon make);
  * the new path really is taken where it should (the energy bars) and the fallback where it must be;
  * the bytes allocated by a step back of the energy bars, of sprite 216 and of sprite 241.

The set of pairs is every pair for sprites of 20 frames or less, and for the longer ones the frames next to the
frames that place or remove something plus a spread of others; GOTO_EXHAUSTIVE=1 runs every pair of every sprite (slow).
"""
import glob
import os
import unittest

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # the CI installs lupa
    LuaRuntime = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLASH = os.path.join(ROOT, "lua", "grymod", "flash")
EXHAUSTIVE = os.environ.get("GOTO_EXHAUSTIVE") == "1"

STUBS = r"""
local REPO = ...

function include(path)
	local f = io.open(REPO .. "/lua/" .. path, "rb")
	if not f then return nil end
	local src = f:read("*a")
	f:close()
	return assert(loadstring(src, "@" .. path))()
end

file = {Exists = function(path)
	local f = io.open(REPO .. "/lua/" .. path, "rb")
	if f then f:close() return true end
	return false
end}

function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function istable(v) return type(v) == "table" end
function math.Clamp(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end

GryMod = {}
include("grymod/client/cl_flash.lua")
Flash = GryMod.Flash

THEME = {Line = {68, 99, 62}, Over = {215, 140, 16}, Text = {189, 0, 161}}
"""

HARNESS = r"""
-- ---- a canonical text of a whole tree of clips ------------------------------------------------------------------------------------------

local function num(v) return string.format("%.17g", v) end

local function plain(value, out)
	local t = type(value)

	if t == "number" then
		out[#out + 1] = num(value)
	elseif t == "table" then
		out[#out + 1] = "{"
		local keys = {}

		for k in pairs(value) do keys[#keys + 1] = k end

		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

		for _, k in ipairs(keys) do
			out[#out + 1] = tostring(k) .. "="
			plain(value[k], out)
			out[#out + 1] = ","
		end

		out[#out + 1] = "}"
	else
		out[#out + 1] = tostring(value)
	end
end

-- keys that hold other clips, back links or drawing caches (the caches are what the drawing derives, not state of the player)
local SKIP = {clip = true, cache = true, cacheB = true, parent = true, entry = true, movie = true, frames = true, labels = true, list = true, names = true, sorted = true, theme = true}

local function serialise(clip, out, depth)
	out[#out + 1] = string.rep(" ", depth) .. "clip"
	local keys = {}

	for k in pairs(clip) do
		if not SKIP[k] then keys[#keys + 1] = k end
	end

	table.sort(keys)

	for _, k in ipairs(keys) do
		out[#out + 1] = " " .. k .. "="
		plain(clip[k], out)
	end

	out[#out + 1] = " theme=" .. tostring(clip.theme and (clip.theme.Line[1] .. "/" .. clip.theme.Over[2]) or nil)
	local named = {}

	for name, entry in pairs(clip.names) do named[#named + 1] = name .. "@" .. entry.depth end

	table.sort(named)
	out[#out + 1] = " names=" .. table.concat(named, ",") .. "\n"

	local listed = 0

	for _ in pairs(clip.list) do listed = listed + 1 end

	out[#out + 1] = string.rep(" ", depth) .. " listed=" .. listed .. "\n"

	for _, entry in ipairs(clip:Entries()) do
		out[#out + 1] = string.rep(" ", depth + 1) .. "entry " .. entry.depth
		local ekeys = {}

		for k in pairs(entry) do
			if not SKIP[k] then ekeys[#ekeys + 1] = k end
		end

		table.sort(ekeys)

		for _, k in ipairs(ekeys) do
			out[#out + 1] = " " .. k .. "="
			plain(entry[k], out)
		end

		if entry.clip then
			out[#out + 1] = " linked=" .. tostring(entry.clip.parent == clip and entry.clip.entry == entry) .. "\n"
			serialise(entry.clip, out, depth + 2)
		else
			out[#out + 1] = "\n"
		end
	end
end

function Canon(clip)
	local out = {}
	serialise(clip, out, 0)

	return table.concat(out)
end

-- ---- things done to a tree before it jumps back (the same on both) ----------------------------------------------------------------

local function eachClip(clip, fn)
	for _, entry in ipairs(clip:Entries()) do
		if entry.clip then
			fn(entry.clip, entry)
			eachClip(entry.clip, fn)
		end
	end
end

Mutations = {
	function(clip) end,
	function(clip) clip:Advance(0.04) end,
	function(clip) eachClip(clip, function(c, e) c:SetX(e.m[5] + 1.5) end) end,
	function(clip) local done; eachClip(clip, function(c) if not done then done = true c:SetAlpha(40) end end) end,
	function(clip) eachClip(clip, function(c) c:SetVisible(false) end) end,
	function(clip) local done; eachClip(clip, function(c) if not done then done = true c:SetCut(1, 2, 1, nil) end end) end,
	function(clip)
		-- what other files of the addon write without a method: a blend, a colour, a field of their own
		local first = clip:Entries()[1]
		if first then first.compassName = "x" end
		eachClip(clip, function(c) local e = c:Entries()[1] if e then e.blend = 8 e.cx = {1, 1, 1, 0.5, 0, 0, 0, 0} end end)
	end,
	function(clip)
		local function texts(c) for _, e in ipairs(c:Entries()) do if e.kind == "text" then e.text = "zz" c:_touch() end end end
		texts(clip)
		eachClip(clip, texts)
	end
}

-- ---- which pairs of frames ------------------------------------------------------------------------------------------------------------

local function frameSet(frames, n, exhaustive)
	local set, list = {}, {}

	local function add(f)
		if f >= 1 and f <= n and not set[f] then set[f] = true list[#list + 1] = f end
	end

	if exhaustive or n <= 20 then
		for f = 1, n do add(f) end
	else
		for f = 1, 3 do add(f) end
		for f = n - 2, n do add(f) end

		-- the frames next to the ones that place or remove something (at most 6 of those, evenly spread)
		local placing = {}

		for index, frame in ipairs(frames) do
			for _, op in ipairs(frame) do
				if op.rm or op.c then
					placing[#placing + 1] = index
					break
				end
			end
		end

		local step = math.max(1, math.ceil(#placing / 6))

		for k = 1, #placing, step do
			add(placing[k] - 1) add(placing[k]) add(placing[k] + 1)
		end

		for k = 1, 4 do add(math.floor(n * k / 5)) end
	end

	table.sort(list)

	return list
end

-- The jump F -> T on a tree built by the same steps, once with the old path, once with the new one. Returns the number of pairs, how many took the
-- new path, and the list of mismatches.
function ComparePairs(movie, make, n, frames, exhaustive, mutations)
	local set = frameSet(frames, n, exhaustive)
	local pairsDone, fast, bad = 0, 0, {}
	local stats = Flash.RewindStats

	for _, F in ipairs(set) do
		for _, T in ipairs(set) do
			if T < F then
				pairsDone = pairsDone + 1
				local mutation = Mutations[(pairsDone % mutations) + 1]
				local old, new = make(), make()
				old:GotoAndStop(F)
				new:GotoAndStop(F)
				mutation(old)
				mutation(new)

				Flash.NoFastRewind = true
				old:GotoAndStop(T)
				Flash.NoFastRewind = false
				local before = stats and stats.fast or 0
				new:GotoAndStop(T)

				if stats and stats.fast > before then fast = fast + 1 end

				local a, b = Canon(old), Canon(new)

				if a ~= b then
					bad[#bad + 1] = string.format("%d -> %d (mutation %d)", F, T, (pairsDone % mutations) + 1)

					if #bad >= 3 then return pairsDone, fast, bad end
				end
			end
		end
	end

	return pairsDone, fast, bad
end

-- Bytes allocated by `fn`, the collector stopped for the whole series (a collection shrinks the Lua stack and the next deep call grows it again: that is not
-- the call's); the median of a few runs after one to warm up.
function Bytes(setup, fn, runs)
	local samples = {}
	jit.off()
	collectgarbage("collect")
	collectgarbage("stop")

	for i = 0, runs do
		local arg = setup()
		local before = collectgarbage("count")
		fn(arg)
		local after = collectgarbage("count")

		if i > 0 then samples[#samples + 1] = (after - before) * 1024 end
	end

	collectgarbage("restart")
	table.sort(samples)

	return samples[math.ceil(#samples / 2)]
end
"""


def movie_files():
    return sorted(p for p in glob.glob(os.path.join(FLASH, "*.lua")) if "strings" not in os.path.basename(p))


@unittest.skipUnless(LuaRuntime, "lupa is not installed")
class FlashGoto(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = LuaRuntime(unpack_returned_tuples=True)
        cls.lua.eval("function(src, repo) return assert(loadstring(src, '@stubs'))(repo) end")(STUBS, ROOT.replace("\\", "/"))
        cls.lua.execute(HARNESS)
        cls.movies = {}
        loader = cls.lua.eval("function(path) local f = assert(io.open(path, 'rb')) local s = f:read('*a') f:close() return assert(loadstring(s, '@' .. path))() end")

        for path in movie_files():
            cls.movies[os.path.basename(path)] = loader(path.replace("\\", "/"))

    def compare_movie(self, name, theme="THEME"):
        compare = self.lua.eval("ComparePairs")
        make_sprite = self.lua.eval("function(movie, id) return function() return Flash.NewClip(movie, id, %s) end end" % theme)
        make_root = self.lua.eval("function(movie) return function() return Flash.NewRoot(movie, %s) end end" % theme)
        movie = self.movies[name]
        totals = {"pairs": 0, "fast": 0}

        sprites = sorted((int(k), v) for k, v in movie.chars.items() if v.k == "sprite")

        for sprite_id, definition in sprites:
            done, fast, bad = compare(movie, make_sprite(movie, sprite_id), definition.n, definition.frames, EXHAUSTIVE, 8)
            totals["pairs"] += done
            totals["fast"] += fast
            self.assertEqual(len(bad), 0, "%s sprite %d differs after: %s" % (name, sprite_id, list(bad.values())))

        root = movie.root
        done, fast, bad = compare(movie, make_root(movie), len(root), root, EXHAUSTIVE, 8)
        totals["pairs"] += done
        totals["fast"] += fast
        self.assertEqual(len(bad), 0, "%s main timeline differs after: %s" % (name, list(bad.values())))

        return totals

    # ---- the state after a jump back is the same with the new path and with the old one ----------------------------------------------

    def test_the_tree_after_a_jump_back_is_the_same_in_every_movie(self):
        grand = {"pairs": 0, "fast": 0}

        for name in self.movies:
            with self.subTest(movie=name):
                totals = self.compare_movie(name)
                grand["pairs"] += totals["pairs"]
                grand["fast"] += totals["fast"]

        print("\n[flash goto] %d pairs of frames compared, %d took the new path" % (grand["pairs"], grand["fast"]))
        self.assertGreater(grand["pairs"], 1000)
        self.assertGreater(grand["fast"], 0, "the new path never ran: Flash.RewindStats says nothing was taken")

    def test_the_same_with_no_colour_theme(self):
        totals = self.compare_movie("hud_ammohealthenergysuit.lua", theme="nil")
        self.assertGreater(totals["pairs"], 100)

    # ---- the new path is taken where it should be ------------------------------------------------------------------------------------------

    def step_back(self, movie_name, sprite, start, steps):
        """Takes `steps` single steps back from `start` on a bar sprite; returns how many took the new path."""
        movie = self.movies[movie_name]
        self.lua.globals().movie_under_test = movie
        run = self.lua.eval(
            """function(sprite, start, steps)
                local clip = Flash.NewClip(movie_under_test, sprite, THEME)
                clip:GotoAndStop(start)
                local before = Flash.RewindStats and Flash.RewindStats.fast or -1
                local slow = Flash.RewindStats and Flash.RewindStats.slow or -1
                for f = start - 1, start - steps, -1 do clip:GotoAndStop(f) end
                local stats = Flash.RewindStats
                return stats and (stats.fast - before) or -1, stats and (stats.slow - slow) or -1
            end"""
        )

        return run(sprite, start, steps)

    def test_the_energy_bar_steps_back_without_a_rebuild(self):
        # frames 21..99 of the bars only move the mask: nothing is placed or removed there
        fast, slow = self.step_back("hud_ammohealthenergysuit.lua", 16, 98, 70)
        self.assertEqual((fast, slow), (70, 0))
        fast, slow = self.step_back("hud_ammohealthenergysuit.lua", 25, 98, 70)
        self.assertEqual((fast, slow), (70, 0))

    def test_the_night_vision_bar_steps_back_without_a_rebuild(self):
        fast, slow = self.step_back("hud_nightvision.lua", 12, 100, 90)
        self.assertEqual(slow, 0)
        self.assertEqual(fast, 90)

    def test_a_step_across_a_placement_falls_back(self):
        # frame 100 of the energy bar removes the bar's depth 2 and places another clip there: one step back from it rebuilds
        fast, slow = self.step_back("hud_ammohealthenergysuit.lua", 16, 100, 1)
        self.assertEqual((fast, slow), (0, 1))

    def test_a_clip_that_was_changed_falls_back_instead_of_keeping_the_change(self):
        run = self.lua.eval(
            """function(movie)
                local clip = Flash.NewClip(movie, 16, THEME)
                clip:GotoAndStop(90)
                local child = clip:Entries()[4].clip -- the clip placed at depth 5 by frame 20
                child:Entries()[1].clip:SetX(5)
                local fast = Flash.RewindStats.fast
                clip:GotoAndStop(89)
                local took = Flash.RewindStats.fast > fast
                local x = clip:Entries()[4].clip:Entries()[1].clip.entry.m[5]
                return took, x
            end"""
        )
        took, x = run(self.movies["hud_ammohealthenergysuit.lua"])
        self.assertFalse(took)
        self.assertEqual(x, 0)

    # ---- what a step back allocates ------------------------------------------------------------------------------------------------------

    def bytes_for(self, movie_name, sprite, start, target, fast):
        movie = self.movies[movie_name]
        self.lua.globals().movie_under_test = movie
        measure = self.lua.eval(
            """function(sprite, start, target, fast)
                return Bytes(function()
                    local clip = Flash.NewClip(movie_under_test, sprite, THEME)
                    clip:GotoAndStop(start)
                    Flash.NoFastRewind = not fast
                    return clip
                end, function(clip) clip:GotoAndStop(target) end, 9)
            end"""
        )
        try:
            return measure(sprite, start, target, fast)
        finally:
            self.lua.execute("Flash.NoFastRewind = false")

    def test_a_step_back_of_the_energy_bar_allocates_next_to_nothing(self):
        old = self.bytes_for("hud_ammohealthenergysuit.lua", 16, 60, 59, False)
        new = self.bytes_for("hud_ammohealthenergysuit.lua", 16, 60, 59, True)
        print("\n[flash goto] energy bar 60 -> 59: old path %d bytes, new path %d bytes" % (old, new))
        self.assertGreater(old, 9000)
        self.assertLess(new, 200)

    def test_a_step_back_of_the_night_vision_bar_allocates_next_to_nothing(self):
        old = self.bytes_for("hud_nightvision.lua", 12, 60, 59, False)
        new = self.bytes_for("hud_nightvision.lua", 12, 60, 59, True)
        print("\n[flash goto] night vision bar 60 -> 59: old path %d bytes, new path %d bytes" % (old, new))
        self.assertGreater(old, 6000)
        self.assertLess(new, 200)

    def test_the_big_sprites_never_cost_more(self):
        for sprite, start, target in ((216, 25, 24), (216, 6, 5), (241, 40, 39)):
            old = self.bytes_for("hud_ammohealthenergysuit.lua", sprite, start, target, False)
            new = self.bytes_for("hud_ammohealthenergysuit.lua", sprite, start, target, True)
            print("\n[flash goto] sprite %d %d -> %d: old path %d bytes, new path %d bytes" % (sprite, start, target, old, new))
            self.assertLessEqual(new, old * 1.02 + 200)


if __name__ == "__main__":
    unittest.main()
