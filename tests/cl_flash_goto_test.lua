-- Tests of the backward jump of the Flash player (Clip:_goto, cl_flash.lua), GLuaTest format, client realm. Going back to an earlier frame used to empty the clip
-- and replay it from its first frame (every object and every clip inside it made again: about 10 KB for one step of the energy bar). It now keeps the objects
-- that are the same at both frames and only puts the matrix, colour, morph ratio and blend mode of the target frame back, when the result cannot be told from the
-- rebuild's (otherwise it rebuilds). The big comparison with every sprite of every real movie is tools/test_flash_goto.py (outside the game); here the rules are
-- pinned on a small movie, and the real energy bars are compared in the game's own Lua.

local I = {1, 0, 0, 1, 0, 0}

local function movie()
	return {
		w = 1024, h = 768, fps = 30, atlases = {},
		chars = {
			[1] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 1, dh = 1},
			[2] = {k = "text", t = "hello", w = 40, h = 10, fh = 10, f = 1},
			-- a clip that stays as it is (one frame), with a clip inside that takes its colour from the theme
			[5] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "Dot", m = I}, a = {{"color", "Line", "Dot"}}}}},
			[3] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 5, n = "Inner", m = I}}}},
			-- a clip with a timeline of its own, playing in a loop
			[4] = {k = "sprite", n = 3, labels = {}, frames = {{{d = 1, c = 1, m = I}}, {{d = 1, mv = true, m = {1, 0, 0, 1, 5, 0}}}, {{d = 1, mv = true, m = {1, 0, 0, 1, 9, 0}}}}},
			-- the bar: moves only from frame 2 to 5, places something at 6 and takes it away at 7
			[10] = {k = "sprite", n = 7, labels = {}, frames = {
				{{d = 1, c = 1, m = I}, {d = 2, c = 3, n = "Fixed", m = {1, 0, 0, 1, 7, 0}}, {d = 4, c = 1, n = "Named", m = I, cx = {1, 1, 1, 1, 0, 0, 0, 0}}, a = {{"stop"}}},
				{{d = 1, mv = true, m = {1, 0, 0, 1, 10, 0}}},
				{{d = 1, mv = true, r = 5, cx = {0.5, 0.5, 0.5, 1, 0, 0, 0, 0}}, {d = 4, mv = true, bl = 8}},
				{{d = 1, mv = true, m = {2, 0, 0, 2, 10, 0}}},
				{{d = 4, mv = true, m = {1, 0, 0, 1, 3, 3}, r = 9}},
				{{d = 6, c = 1, m = I}},
				{{rm = 6}}
			}},
			-- a bar with a looping clip inside, and one with a text
			[11] = {k = "sprite", n = 3, labels = {}, frames = {{{d = 1, c = 4, n = "Loop"}}, {{d = 1, mv = true, m = {1, 0, 0, 1, 1, 1}}}, {{d = 1, mv = true, m = {1, 0, 0, 1, 2, 2}}}}},
			[12] = {k = "sprite", n = 3, labels = {}, frames = {{{d = 1, c = 2, n = "Label"}}, {{d = 1, mv = true, m = {1, 0, 0, 1, 1, 1}}}, {{d = 1, mv = true, m = {1, 0, 0, 1, 2, 2}}}}}
		},
		root = {{{d = 1, c = 10, n = "Bar"}}}
	}
end

local function theme()
	return {Line = {68, 99, 62}, Over = {215, 140, 16}, Text = {189, 0, 161}}
end

-- ---- a canonical text of a whole tree of clips: every field of every clip and entry except the drawing's caches and the links up -----------------------

local SKIP = {clip = true, cache = true, cacheB = true, parent = true, entry = true, movie = true, frames = true, labels = true, list = true, names = true, sorted = true, theme = true}

local function plain(value, out)
	if type(value) == "table" then
		local keys = {}

		for k in pairs(value) do keys[#keys + 1] = k end

		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		out[#out + 1] = "{"

		for _, k in ipairs(keys) do
			out[#out + 1] = tostring(k) .. "="
			plain(value[k], out)
			out[#out + 1] = ","
		end

		out[#out + 1] = "}"
	elseif type(value) == "number" then
		out[#out + 1] = string.format("%.17g", value)
	else
		out[#out + 1] = tostring(value)
	end
end

local function canon(clip, out, depth)
	local keys = {}

	for k in pairs(clip) do
		if not SKIP[k] then keys[#keys + 1] = k end
	end

	table.sort(keys)
	out[#out + 1] = string.rep(" ", depth) .. "clip"

	for _, k in ipairs(keys) do
		out[#out + 1] = " " .. k .. "="
		plain(clip[k], out)
	end

	local named = {}

	for name, entry in pairs(clip.names) do named[#named + 1] = name .. "@" .. entry.depth end

	table.sort(named)
	out[#out + 1] = " names=" .. table.concat(named, ",") .. "\n"

	for _, entry in ipairs(clip:Entries()) do
		local ekeys = {}

		for k in pairs(entry) do
			if not SKIP[k] then ekeys[#ekeys + 1] = k end
		end

		table.sort(ekeys)
		out[#out + 1] = string.rep(" ", depth + 1) .. "entry " .. entry.depth

		for _, k in ipairs(ekeys) do
			out[#out + 1] = " " .. k .. "="
			plain(entry[k], out)
		end

		out[#out + 1] = " linked=" .. tostring(entry.clip == nil or (entry.clip.parent == clip and entry.clip.entry == entry)) .. "\n"

		if entry.clip then
			canon(entry.clip, out, depth + 2)
		end
	end
end

local function tree(clip)
	local out = {}
	canon(clip, out, 0)

	return table.concat(out)
end

-- Makes two equal clips with `make`, brings both to `from`, does `change` to both, then goes to `to`: once with the rebuild, once with the new path.
-- Returns whether the new path was taken, whether the two trees are the same, and the two clips.
local function compare(make, from, to, change)
	local F = GryMod.Flash
	local old, new = make(), make()
	old:GotoAndStop(from)
	new:GotoAndStop(from)

	if change then
		change(old)
		change(new)
	end

	F.NoFastRewind = true
	local ok, err = pcall(old.GotoAndStop, old, to)
	F.NoFastRewind = false
	assert(ok, err)
	local fast = F.RewindStats.fast
	new:GotoAndStop(to)

	return F.RewindStats.fast > fast, tree(old) == tree(new), old, new
end

local function barOf(m, id)
	return function() return GryMod.Flash.NewClip(m, id or 10, theme()) end
end

-- the bytes allocated by `fn` with the collector stopped, whatever happens in it
local function bytesOf(fn)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	local ok, err = pcall(fn)
	local after = collectgarbage("count")
	collectgarbage("restart")
	assert(ok, err)

	return (after - before) * 1024
end

return {
	groupName = "GryMod Flash player: going back",
	afterEach = function(state)
		GryMod.Flash.NoFastRewind = false
	end,
	cases = {
		{
			name = "going back over frames that only move things keeps the objects and gives what the rebuild gives",
			func = function(state)
				local m = movie()
				local clip = GryMod.Flash.NewClip(m, 10, theme())
				clip:GotoAndStop(5)
				local before = {}

				for _, entry in ipairs(clip:Entries()) do before[entry.depth] = entry end

				local fast, same = compare(barOf(m), 5, 2)
				expect(fast).to.beTrue()
				expect(same).to.beTrue()
				clip:GotoAndStop(2)

				for _, entry in ipairs(clip:Entries()) do
					expect(entry == before[entry.depth]).to.beTrue()
				end

				expect(clip:Child("Fixed")).to.exist()
				expect(clip:CurrentFrame()).to.equal(2)
				expect(clip.version > 0).to.beTrue()
			end
		},
		{
			name = "a property that a later frame changed goes back to the first frames' value (matrix, colour, ratio, blend), also all the way to the first frame",
			func = function(state)
				local m = movie()

				for _, pair in ipairs({{5, 4}, {5, 3}, {5, 2}, {5, 1}, {4, 1}, {3, 2}, {3, 1}, {2, 1}}) do
					local fast, same = compare(barOf(m), pair[1], pair[2])
					expect(fast).to.beTrue()
					expect(same).to.beTrue()
				end

				local clip = GryMod.Flash.NewClip(m, 10, theme())
				clip:GotoAndStop(5)
				clip:GotoAndStop(1)
				local named = clip:Child("Named")
				expect(named.blend).to.beNil()
				expect(named.ratio).to.beNil()
				expect(named.m[5]).to.equal(0)
				expect(named.cx[1]).to.equal(1)
			end
		},
		{
			name = "a step back across a frame that places or removes something is rebuilt",
			func = function(state)
				local m = movie()

				for _, pair in ipairs({{6, 5}, {7, 5}, {7, 6}, {6, 1}, {7, 2}}) do
					local fast, same = compare(barOf(m), pair[1], pair[2])
					expect(fast).to.beFalse()
					expect(same).to.beTrue()
				end
			end
		},
		{
			name = "a clip inside that was changed is rebuilt, not kept as it is (moved, hidden, faded, written to, cut)",
			func = function(state)
				local m = movie()
				local changes = {
					["matrix written"] = function(c) c:Child("Fixed"):Child("Inner").entry.m = {1, 0, 0, 1, 99, 0} end,
					["SetX"] = function(c) c:Child("Fixed"):Child("Inner"):SetX(3) end,
					["alpha"] = function(c) c:Child("Fixed"):Child("Inner"):SetAlpha(30) end,
					["hidden"] = function(c) c:Child("Fixed"):SetVisible(false) end,
					["cut"] = function(c) c:Child("Fixed"):SetCut(1, 2, 1, nil) end,
					["stopped"] = function(c) c:Child("Fixed"):Stop() end,
					["blend written"] = function(c) c:Child("Fixed"):Child("Inner").entry.blend = 8 end,
					["own field"] = function(c) c:Child("Fixed"):Child("Inner").entry.compassName = "N" end,
					["own clip field"] = function(c) c:Child("Fixed").mine = true end
				}

				-- nothing changed: kept
				local fast, same = compare(barOf(m), 5, 2)
				expect(fast).to.beTrue()
				expect(same).to.beTrue()

				for name, change in pairs(changes) do
					fast, same = compare(barOf(m), 5, 2, change)
					expect(fast).to.beFalse()
					expect(same).to.beTrue()
				end
			end
		},
		{
			name = "a clip inside with a timeline that has moved is rebuilt; one that has not moved is kept",
			func = function(state)
				local m = movie()
				local fast, same = compare(barOf(m, 11), 3, 2)
				expect(fast).to.beTrue()
				expect(same).to.beTrue()
				fast, same = compare(barOf(m, 11), 3, 2, function(c) c:Advance(0.2) end)
				expect(fast).to.beFalse()
				expect(same).to.beTrue()
			end
		},
		{
			name = "a clip with a text field is rebuilt, and so is one whose display list got an object from outside",
			func = function(state)
				local m = movie()
				local fast, same = compare(barOf(m, 12), 3, 2)
				expect(fast).to.beFalse()
				expect(same).to.beTrue()

				-- what cl_hud_radar_units.lua does: an entry put in a list by hand
				fast, same = compare(barOf(m), 5, 2, function(c)
					local entry = {depth = 99, id = 1, kind = "shape", m = I, name = "Extra"}
					c.list[99] = entry
					c.names.Extra = entry
					c.count = c.count + 1
					c.sorted = nil
				end)
				expect(fast).to.beFalse()
				expect(same).to.beTrue()
			end
		},
		{
			name = "a changed colour theme is not mistaken for the old one",
			func = function(state)
				local m = movie()
				local shared = theme()
				local function make() return GryMod.Flash.NewClip(m, 10, shared) end

				local fast, same = compare(make, 5, 2)
				expect(fast).to.beTrue()
				expect(same).to.beTrue()
				-- the same table with other colours, after the clips were made: they are not the clips a rebuild would make now
				fast, same = compare(make, 5, 2, function() shared.Line[1] = 1 end)
				expect(fast).to.beFalse()
				expect(same).to.beTrue()
			end
		},
		{
			name = "the counters say which path ran",
			func = function(state)
				local m = movie()
				local stats = GryMod.Flash.RewindStats
				local clip = GryMod.Flash.NewClip(m, 10, theme())
				clip:GotoAndStop(5)
				local fast, slow = stats.fast, stats.slow
				clip:GotoAndStop(4)
				expect(stats.fast).to.equal(fast + 1)
				clip:GotoAndStop(7)
				clip:GotoAndStop(6)
				expect(stats.slow).to.equal(slow + 1)
				-- going forward is neither
				fast, slow = stats.fast, stats.slow
				clip:GotoAndStop(7)
				expect(stats.fast).to.equal(fast)
				expect(stats.slow).to.equal(slow)
			end
		},
		{
			name = "every step back of the suit's energy bar, the health bar and the night vision bar gives what the rebuild gives (real movies)",
			timing = true,
			func = function(state)
				local F = GryMod.Flash
				local suit, night = F.Load("hud_ammohealthenergysuit"), F.Load("hud_nightvision")
				local themeTable = theme()
				local checked, took = 0, 0

				for _, bar in ipairs({{suit, 16, 100}, {suit, 25, 100}, {night, 12, 102}}) do
					local m, id, n = bar[1], bar[2], bar[3]
					local function make() return F.NewClip(m, id, themeTable) end

					for _, from in ipairs({2, 3, 19, 20, 21, 22, 50, 99, n - 1, n}) do
						for to = 1, from - 1 do
							local fast, same = compare(make, from, to)
							checked = checked + 1
							took = took + (fast and 1 or 0)
							expect(same).to.beTrue()
						end
					end
				end

				-- the bars move only the mask from frame 21 on: the pairs that do not reach frame 20 or 100 take the new path
				expect(took > checked / 4).to.beTrue()
			end
		},
		{
			name = "a step back of the energy bar allocates next to nothing (it made about 10 KB, the whole bar again)",
			timing = true, -- no count hook: under it the interpreter allocates for its own sake
			func = function(state)
				local F = GryMod.Flash
				local m = F.Load("hud_ammohealthenergysuit")
				local clip = F.NewClip(m, 16, theme())
				clip:GotoAndStop(100)
				clip:GotoAndStop(99)
				clip:GotoAndStop(98)
				local fast = F.RewindStats.fast
				local steps = 60

				-- the first steps make the templates and warm the compiler: measured after
				local rebuilt = bytesOf(function()
					F.NoFastRewind = true

					for f = 97, 97 - steps + 1, -1 do clip:GotoAndStop(f) end

					F.NoFastRewind = false
				end)

				clip:GotoAndStop(98)
				local kept = bytesOf(function()
					for f = 97, 97 - steps + 1, -1 do clip:GotoAndStop(f) end
				end)

				expect(F.RewindStats.fast - fast >= steps).to.beTrue()
				-- per step: the rebuild made thousands of bytes, the new path none (a little room for the engine)
				expect(rebuilt / steps > 3000).to.beTrue()
				expect(kept / steps < 100).to.beTrue()
			end
		}
	}
}
