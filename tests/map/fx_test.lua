-- Tests of the big map's loading looks (lua/grymod/client/map/fx.lua), GLuaTest format, client realm. The game knows only three things while the map
-- loads: it started, a tile arrived, it ended. So a tile has exactly two looks: "waiting" (a loop on its own clock, over the coarse picture) and
-- "arrived" (a short effect started by the arrival, never delayed), and at the very end one brief rim flash. Nothing is tied to a global progress.
-- The looks are entries of a registry; the default one is the glitch (the tile trembles in bands, then tears in red and cyan and settles). The
-- drawing is done through a small drawer (Fill, Slice, Rim) that these tests replace by a recorder: no engine call here.

local function Fx()
	local fx = GryMod and GryMod.Map and GryMod.Map.Fx

	expect(fx ~= nil).to.beTrue()

	return fx
end

-- a drawer that records what it is asked to draw
local function recorder()
	local d = {calls = {}}

	function d.Fill(x, y, w, h, r, g, b, a)
		d.calls[#d.calls + 1] = {"fill", x, y, w, h, r, g, b, a}
	end

	function d.Slice(pic, x, y, w, h, f0, f1, dx, r, g, b, a, additive)
		d.calls[#d.calls + 1] = {"slice", pic, x, y, w, h, f0, f1, dx, r, g, b, a, additive}
	end

	function d.Rim(x, y, w, h, thickness, r, g, b, a)
		d.calls[#d.calls + 1] = {"rim", x, y, w, h, thickness, r, g, b, a}
	end

	return d
end

local CELL = {x = 100, y = 50, w = 300, h = 240, tx = 3, ty = -2, coarse = "COARSE", sharp = "SHARP"}

local function slices(d, pic)
	local list = {}

	for _, c in ipairs(d.calls) do
		if c[1] == "slice" and c[2] == pic then
			list[#list + 1] = c
		end
	end

	return list
end

return {
	groupName = "GryMod big map loading looks",
	afterEach = function()
		pcall(function()
			GryMod.Map.Fx.Unregister("test_look")
		end)
	end,
	cases = {
		-- fails without Fx.Hash
		{
			name = "the hash is the same for the same numbers, is between 0 and 1 and differs from one input to another",
			func = function()
				local fx = Fx()

				expect(fx.Hash(3, 4)).to.equal(fx.Hash(3, 4))

				local different = false

				for i = 1, 20 do
					local h = fx.Hash(i, i * 7)

					expect(h >= 0 and h < 1).to.beTrue()
					different = different or h ~= fx.Hash(1, 7)
				end

				expect(different).to.beTrue()
			end
		},
		-- fails when the glitch is not registered by default
		{
			name = "the glitch is registered, it is the default look and an unknown name falls back on it",
			func = function()
				local fx = Fx()

				expect(fx.Get("glitch") ~= nil).to.beTrue()
				expect(fx.DEFAULT).to.equal("glitch")
				expect(fx.Resolve("glitch")).to.equal(fx.Get("glitch"))
				expect(fx.Resolve("no such look")).to.equal(fx.Get("glitch"))
				expect(fx.Resolve(nil)).to.equal(fx.Get("glitch"))
			end
		},
		-- fails when a developer cannot add a look
		{
			name = "a developer registers a look by a name with its two functions, lists it and removes it; a bad definition is refused",
			func = function()
				local fx = Fx()
				local def = {label = "Test", waiting = function() end, arrived = function() end}

				expect(fx.Register("test_look", def)).to.beTrue()
				expect(fx.Get("test_look")).to.equal(def)
				expect(fx.Resolve("test_look")).to.equal(def)

				local listed = false

				for _, name in ipairs(fx.List()) do
					listed = listed or name == "test_look"
				end

				expect(listed).to.beTrue()
				expect(fx.ArriveSeconds(def)).to.equal(0.3)
				expect(fx.RimSeconds(def)).to.equal(0.35)
				expect(fx.Unregister("test_look")).to.beTrue()
				expect(fx.Get("test_look")).to.beNil()

				local ok, why = fx.Register("test_look", {label = "x"})

				expect(ok).to.beFalse()
				expect(type(why)).to.equal("string")
				expect(fx.Register("bad name!", def)).to.beFalse()
				expect(fx.Register(nil, def)).to.beFalse()
			end
		},
		-- fails when the glitch's waiting look is not a dark veil plus six trembling bands of the coarse picture
		{
			name = "waiting: a dark veil and six bands of the coarse picture, each shifted sideways by a small amount, translucent",
			func = function()
				local fx = Fx()
				local d = recorder()

				fx.Get("glitch").waiting(d, CELL, 1.234)

				expect(d.calls[1][1]).to.equal("fill")
				expect(d.calls[1][9]).to.aboutEqual(77, 1)

				local bands = slices(d, "COARSE")

				expect(#bands).to.equal(6)

				local top = 0

				for i, c in ipairs(bands) do
					expect(c[7]).to.aboutEqual((i - 1) / 6, 1e-9)
					expect(c[8]).to.aboutEqual(i / 6, 1e-9)
					expect(math.abs(c[9]) <= 12 + 1e-6).to.beTrue()
					expect(c[13] >= 127 and c[13] <= 205).to.beTrue()
					expect(c[14] == true or c[14] == false).to.beTrue()
					top = top + 1
				end

				expect(top).to.equal(6)
			end
		},
		-- fails when the waiting look is not a loop on its own clock
		{
			name = "waiting loops: the same moment gives the same picture, the bands change about every 80 ms, and nothing depends on a progress",
			func = function()
				local fx = Fx()
				local a, b, c = recorder(), recorder(), recorder()

				fx.Get("glitch").waiting(a, CELL, 5.0)
				fx.Get("glitch").waiting(b, CELL, 5.01)
				fx.Get("glitch").waiting(c, CELL, 5.0 + 0.5)

				local function shifts(d)
					local list = {}

					for _, call in ipairs(slices(d, "COARSE")) do
						list[#list + 1] = call[9]
					end

					return table.concat(list, ",")
				end

				expect(shifts(a)).to.equal(shifts(b))
				expect(shifts(a) ~= shifts(c)).to.beTrue()
			end
		},
		-- fails when a cell without a coarse picture draws a slice of nothing
		{
			name = "a cell that has no coarse picture yet still trembles: the veil is drawn, no band of a missing picture",
			func = function()
				local fx = Fx()
				local d = recorder()
				local cell = {x = 0, y = 0, w = 100, h = 100, tx = 0, ty = 0}

				fx.Get("glitch").waiting(d, cell, 2)

				expect(d.calls[1][1]).to.equal("fill")

				for _, call in ipairs(d.calls) do
					expect(call[1] == "slice").to.beFalse()
				end
			end
		},
		-- fails when the arrival is not a tear of the sharp tile in bands and in red and cyan that settles
		{
			name = "arrived: six bands of the sharp tile shifted and a red and a cyan copy added on either side, all shrinking to nothing at the end",
			func = function()
				local fx = Fx()
				local look = fx.Get("glitch")
				local start, finish = recorder(), recorder()

				look.arrived(start, CELL, 0, 0.0)
				look.arrived(finish, CELL, 1, 0.3)

				local bands = slices(start, "SHARP")

				-- six plain bands, plus the red copy and the cyan copy
				expect(#bands).to.equal(8)

				local red, cyan
				local plain = 0

				for _, c in ipairs(bands) do
					if c[14] == true then
						if c[10] == 255 and c[11] < 100 then
							red = c
						elseif c[10] < 100 and c[12] == 255 then
							cyan = c
						end
					else
						plain = plain + 1
					end
				end

				expect(plain).to.equal(6)
				expect(red ~= nil).to.beTrue()
				expect(cyan ~= nil).to.beTrue()
				expect(red[9] > 0).to.beTrue() -- the red copy goes right
				expect(cyan[9] < 0).to.beTrue() -- the cyan copy goes left
				-- 55 percent of the alpha at the start
				expect(red[13]).to.aboutEqual(140, 2)
				-- the whole tile for each copy
				expect(red[7]).to.equal(0)
				expect(red[8]).to.equal(1)

				-- at the end nothing is left to draw: the tile is plain
				expect(#finish.calls).to.equal(0)
			end
		},
		-- fails when the tear does not get smaller as the arrival goes on
		{
			name = "the tear shrinks as the arrival goes on: the red copy's shift at the middle is smaller than at the start",
			func = function()
				local fx = Fx()
				local look = fx.Get("glitch")
				local a, b = recorder(), recorder()

				look.arrived(a, CELL, 0, 0)
				look.arrived(b, CELL, 0.5, 0.15)

				local function redShift(d)
					for _, c in ipairs(slices(d, "SHARP")) do
						if c[14] == true and c[10] == 255 and c[11] < 100 then
							return c[9]
						end
					end
				end

				expect(redShift(b) < redShift(a)).to.beTrue()
				expect(redShift(b) > 0).to.beTrue()
			end
		},
		-- fails when the rim is not the brief accent frame that fades
		{
			name = "the rim at the very end is a frame of the accent colour that fades out: full at the start, nothing at the end",
			func = function()
				local fx = Fx()
				local look = fx.Get("glitch")
				local a, b = recorder(), recorder()

				look.finish(a, {x = 10, y = 20, w = 400, h = 300}, 0)
				look.finish(b, {x = 10, y = 20, w = 400, h = 300}, 1)

				expect(#a.calls).to.equal(1)
				expect(a.calls[1][1]).to.equal("rim")
				expect(a.calls[1][7]).to.equal(154)
				expect(a.calls[1][8]).to.equal(214)
				expect(a.calls[1][9]).to.equal(90)
				expect(a.calls[1][10]).to.aboutEqual(255, 1)
				expect(#b.calls).to.equal(0)
			end
		},
		-- fails when the tracker does not know a request, an arrival and the end
		{
			name = "the tracker knows only three things: a tile was asked, a tile arrived, no tile is left; the look of a tile follows from them",
			func = function()
				local fx = Fx()
				local t = fx.Tracker.New()

				expect(fx.Tracker.Look(t, 1, 10, 0.3)).to.beNil()

				fx.Tracker.Request(t, 1, 10)
				fx.Tracker.Request(t, 2, 10.1)
				fx.Tracker.Request(t, 2, 10.2) -- asked twice: one tile

				expect(fx.Tracker.Waiting(t)).to.equal(2)

				local mode, since = fx.Tracker.Look(t, 1, 10.5, 0.3)

				expect(mode).to.equal("waiting")
				expect(since).to.aboutEqual(0.5, 1e-9)

				fx.Tracker.Arrive(t, 1, 10.6)

				local mode2, p = fx.Tracker.Look(t, 1, 10.75, 0.3)

				expect(mode2).to.equal("arrived")
				expect(p).to.aboutEqual(0.5, 1e-9)
				expect(fx.Tracker.Waiting(t)).to.equal(1)
				-- the other is still waiting, and no rim yet
				expect(fx.Tracker.Look(t, 2, 10.75, 0.3)).to.equal("waiting")
				expect(fx.Tracker.Rim(t, 10.75, 0.35)).to.beNil()

				-- the arrival look is over after its time
				expect(fx.Tracker.Look(t, 1, 11, 0.3)).to.beNil()

				fx.Tracker.Arrive(t, 2, 11.2)

				-- the end: the rim starts when the last tile arrived and lasts its time
				expect(fx.Tracker.Rim(t, 11.2, 0.35)).to.aboutEqual(0, 1e-9)
				expect(fx.Tracker.Rim(t, 11.375, 0.35)).to.aboutEqual(0.5, 1e-9)
				expect(fx.Tracker.Rim(t, 11.6, 0.35)).to.beNil()
			end
		},
		-- fails when an arrival of a tile nobody waited for plays a look
		{
			name = "a tile that arrives without a request (a tile the cache had) has no look, and a loading that never began has no rim",
			func = function()
				local fx = Fx()
				local t = fx.Tracker.New()

				fx.Tracker.Arrive(t, 5, 1)

				expect(fx.Tracker.Look(t, 5, 1.1, 0.3)).to.beNil()
				expect(fx.Tracker.Rim(t, 1.1, 0.35)).to.beNil()
			end
		},
		-- fails when dropped requests leave a tile waiting for ever or flash a rim for nothing
		{
			name = "a request that is dropped (the player zoomed away) stops waiting; with no arrival in the batch there is no rim, with one there is",
			func = function()
				local fx = Fx()
				local t = fx.Tracker.New()

				fx.Tracker.Request(t, 1, 0)
				fx.Tracker.Drop(t, 1, 1)

				expect(fx.Tracker.Waiting(t)).to.equal(0)
				expect(fx.Tracker.Look(t, 1, 1, 0.3)).to.beNil()
				expect(fx.Tracker.Rim(t, 1.1, 0.35)).to.beNil()

				fx.Tracker.Request(t, 1, 2)
				fx.Tracker.Request(t, 2, 2)
				fx.Tracker.Arrive(t, 1, 2.5)
				fx.Tracker.Drop(t, 2, 3)

				expect(fx.Tracker.Rim(t, 3.1, 0.35)).to.exist()
			end
		},
		-- fails when Prune keeps the old arrivals for ever
		{
			name = "Prune forgets the arrivals whose look is over, so the table does not grow for ever",
			func = function()
				local fx = Fx()
				local t = fx.Tracker.New()

				for key = 1, 50 do
					fx.Tracker.Request(t, key, 0)
					fx.Tracker.Arrive(t, key, 0.1)
				end

				expect(fx.Tracker.Arrivals(t)).to.equal(50)
				fx.Tracker.Prune(t, 10, 0.3)
				expect(fx.Tracker.Arrivals(t)).to.equal(0)
			end
		},
		-- fails when Reset leaves a tile waiting
		{
			name = "Reset forgets everything: a new map starts clean",
			func = function()
				local fx = Fx()
				local t = fx.Tracker.New()

				fx.Tracker.Request(t, 1, 0)
				fx.Tracker.Reset(t)

				expect(fx.Tracker.Waiting(t)).to.equal(0)
				expect(fx.Tracker.Look(t, 1, 1, 0.3)).to.beNil()
			end
		}
	}
}
