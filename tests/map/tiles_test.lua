-- Tests of the big map's tiles (lua/grymod/client/map/tiles.lua), GLuaTest format, client realm: where the pictures come from (the map's own store, then
-- the minimap's cache when that very tile is there), how the missing ones are made (the minimap's own render, one capture a frame, never in a frame
-- where the minimap made one) and that the minimap's cache is only ASKED. The cache, the capture, the floors, the settings and the engine's render
-- targets are replaced by stand-ins that record what they are given; everything is put back in afterEach inside a pcall, also when a case fails.

local LEVEL = {id = "open_t256", open = true, zlo = -100, zhi = 256}
local PPM = 4
local RES = 1024

local function T()
	local tiles = GryMod and GryMod.Map and GryMod.Map.Tiles

	expect(tiles ~= nil).to.beTrue()

	return tiles
end

local function cacheKey(ppm, tx, ty)
	return ppm .. ":" .. tx .. ":" .. ty
end

local function install(state)
	local M = GryMod.Minimap
	local Tiles = T()
	local Engine = Tiles.Engine

	state.saved = {Cache = M.Cache, Capture = M.Capture, Floors = M.Floors, Settings = M.Settings, Engine = {}}

	for k, v in pairs(Engine) do
		state.saved.Engine[k] = v
	end

	state.clock = 100
	state.frame = 1
	state.res = RES
	state.may = true
	state.asked = {}
	state.renders = {}
	state.renderResult = true
	state.cache = {} -- "ppm:tx:ty" -> "file" | "empty"
	state.forbidden = {}
	state.loaded = {}
	state.slots = {}

	-- the cache answers three questions and records any other call
	M.Cache = setmetatable({
		Has = function(tile)
			return state.cache[cacheKey(tile.ppm, tile.tx, tile.ty)] ~= nil and tile.level == LEVEL.id and tile.res == state.res
		end,
		IsEmpty = function(tile)
			return state.cache[cacheKey(tile.ppm, tile.tx, tile.ty)] == "empty"
		end,
		Path = function(tile)
			return "grymod/minimap/test/t_" .. tile.level .. "_" .. tile.tx .. "_" .. tile.ty .. "_" .. tile.res .. "_" .. tile.ppm
		end
	}, {
		__index = function(_, name)
			return function()
				state.forbidden[#state.forbidden + 1] = name
			end
		end,
		__newindex = function(_, name)
			state.forbidden[#state.forbidden + 1] = "set " .. tostring(name)
		end
	})

	M.Capture = {
		MayCapture = function(owner)
			state.asked[#state.asked + 1] = owner

			return state.may
		end,
		RenderTo = function(tile, level, dest)
			state.renders[#state.renders + 1] = {tile = tile, level = level, dest = dest}

			if state.renderResult == true then
				return true
			end

			return nil, state.renderResult
		end
	}

	M.Floors = {
		Outside = function()
			return state.level or LEVEL
		end
	}

	M.Settings = setmetatable({TileRes = function() return state.res end}, {__index = state.saved.Settings})

	Engine.RealTime = function() return state.clock end
	Engine.FrameNumber = function() return state.frame end
	Engine.NewSlot = function(res, index)
		local slot = {rt = {name = "rt_" .. res .. "_" .. index}, pic = {mat = "mat_" .. index, fade = "fade_" .. index}}

		state.slots[#state.slots + 1] = {res = res, index = index}

		return slot
	end
	Engine.LoadMaterial = function(path)
		state.loaded[#state.loaded + 1] = path

		return {path = path, IsError = function() return false end}
	end

	Tiles.Reset()
end

local function restore(state)
	local M = GryMod.Minimap

	if state.saved then
		M.Cache, M.Capture, M.Floors, M.Settings = state.saved.Cache, state.saved.Capture, state.saved.Floors, state.saved.Settings

		for k, v in pairs(state.saved.Engine) do
			T().Engine[k] = v
		end
	end

	pcall(function() T().Reset() end)
	pcall(hook.Remove, "PostRender", "GryMod big map tiles")
end

-- the window for plans: the tiles of level PPM around (0, 0), with the mouse at (0, 0)
local function spec(ppm, extra)
	local mpu = GryMod.RadarShared.METRES_PER_UNIT
	local T4 = RES / ppm / mpu
	local s = {
		res = RES, mpu = mpu, target = ppm, coarse = ppm, margin = 0,
		view = {minx = 0.1 * T4, maxx = 0.9 * T4, miny = 0.1 * T4, maxy = 0.9 * T4},
		bounds = {x0 = -10 * T4, x1 = 10 * T4, y0 = -10 * T4, y1 = 10 * T4},
		mouse = {x = 0.5 * T4, y = 0.5 * T4}
	}

	for k, v in pairs(extra or {}) do
		s[k] = v
	end

	return s
end

return {
	groupName = "GryMod big map tiles",
	beforeEach = install,
	afterEach = restore,
	cases = {
		-- fails without Tiles.Lookup
		{
			name = "a tile that is nowhere is nil",
			func = function(state)
				local Tiles = T()

				Tiles.Begin()

				expect(Tiles.Lookup(PPM, 0, 0)).to.beNil()
				expect(Tiles.Has(PPM, 0, 0)).to.beFalse()
				-- a definition that is not a level of the pyramid is no tile
				expect(Tiles.Lookup(3, 0, 0)).to.beNil()
			end
		},
		-- fails when a tile of the minimap's cache is not used (the owner: reuse a tile that already exists at the requested definition)
		{
			name = "a tile the minimap's cache has at that very definition is used: its material is loaded from the cache's path through the map's own table, once",
			func = function(state)
				local Tiles = T()

				state.cache[cacheKey(PPM, 2, 3)] = "file"
				Tiles.Begin()

				local pic = Tiles.Lookup(PPM, 2, 3)

				expect(pic ~= nil).to.beTrue()
				expect(pic.mat == pic.fade).to.beTrue()
				expect(#state.loaded).to.equal(1)
				expect(state.loaded[1]).to.equal("../data/grymod/minimap/test/t_open_t256_2_3_1024_4")

				-- the second look finds it in the map's own table
				expect(Tiles.Lookup(PPM, 2, 3) == pic).to.beTrue()
				expect(#state.loaded).to.equal(1)

				-- another definition of the same place is another tile
				expect(Tiles.Lookup(8, 2, 3)).to.beNil()
			end
		},
		-- fails when an empty tile of the cache is asked for a material or made again
		{
			name = "a tile the cache knows to be all void is EMPTY: it exists, no material is loaded",
			func = function(state)
				local Tiles = T()

				state.cache[cacheKey(PPM, 0, 0)] = "empty"
				Tiles.Begin()

				expect(Tiles.Lookup(PPM, 0, 0) == Tiles.EMPTY).to.beTrue()
				expect(#state.loaded).to.equal(0)
				expect(Tiles.Has(PPM, 0, 0)).to.beTrue()
			end
		},
		-- fails when a material that does not load is asked again at every frame
		{
			name = "a cache tile whose material does not load is nil and is not asked again",
			func = function(state)
				local Tiles = T()

				state.cache[cacheKey(PPM, 1, 1)] = "file"
				Tiles.Engine.LoadMaterial = function(path)
					state.loaded[#state.loaded + 1] = path

					return {IsError = function() return true end}
				end
				Tiles.Begin()

				expect(Tiles.Lookup(PPM, 1, 1)).to.beNil()
				expect(Tiles.Lookup(PPM, 1, 1)).to.beNil()
				expect(#state.loaded).to.equal(1)
			end
		},
		-- fails when the table of the map's own references to the cache's materials grows without a limit
		{
			name = "the map holds at most MAX_MATERIALS of the minimap's materials: the least recently used reference goes",
			func = function(state)
				local Tiles = T()

				Tiles.Begin()

				for tx = 1, Tiles.MAX_MATERIALS + 10 do
					state.cache[cacheKey(PPM, tx, 0)] = "file"
					expect(Tiles.Lookup(PPM, tx, 0) ~= nil).to.beTrue()
				end

				-- the first one was dropped: looking it up loads it again
				local before = #state.loaded

				expect(Tiles.Lookup(PPM, 1, 0) ~= nil).to.beTrue()
				expect(#state.loaded).to.equal(before + 1)
				-- the last one is still there
				before = #state.loaded
				expect(Tiles.Lookup(PPM, Tiles.MAX_MATERIALS + 10, 0) ~= nil).to.beTrue()
				expect(#state.loaded).to.equal(before)
			end
		},
		-- fails when a tile is made with another level, size or definition than the one asked
		{
			name = "a missing tile is made by the minimap's own render: Capture.RenderTo(tile, level, the slot's target), the tile named by the open level, the size of the settings and the definition",
			func = function(state)
				local Tiles = T()

				Tiles.Begin()
				Tiles.SetPlan({{ppm = PPM, tx = 5, ty = -2, d = 0}}, state.clock)
				expect(Tiles.Pending()).to.equal(1)
				Tiles.Step(state.clock)

				expect(#state.renders).to.equal(1)

				local r = state.renders[1]

				expect(r.tile.level).to.equal("open_t256")
				expect(r.tile.tx).to.equal(5)
				expect(r.tile.ty).to.equal(-2)
				expect(r.tile.res).to.equal(RES)
				expect(r.tile.ppm).to.equal(PPM)
				expect(r.level == LEVEL).to.beTrue()
				expect(r.dest.name).to.equal("rt_1024_1")

				-- it is there now, as the slot's picture
				local pic = Tiles.Lookup(PPM, 5, -2)

				expect(pic ~= nil).to.beTrue()
				expect(pic.mat).to.equal("mat_1")
				expect(pic.fade).to.equal("fade_1")
				expect(Tiles.Pending()).to.equal(0)
			end
		},
		-- fails when a Step makes more than one capture
		{
			name = "one tile per Step (one capture a frame), nearest first, and the hook goes away when the plan is done",
			func = function(state)
				local Tiles = T()

				Tiles.Begin()
				Tiles.SetPlan({{ppm = PPM, tx = 0, ty = 0, d = 1}, {ppm = PPM, tx = 1, ty = 0, d = 2}, {ppm = PPM, tx = 2, ty = 0, d = 3}}, state.clock)
				expect(Tiles.Hooked()).to.beTrue()

				Tiles.Step(state.clock)
				expect(#state.renders).to.equal(1)
				expect(state.renders[1].tile.tx).to.equal(0)
				expect(Tiles.Hooked()).to.beTrue()

				state.frame = 2
				Tiles.Begin()
				Tiles.Step(state.clock)
				state.frame = 3
				Tiles.Begin()
				Tiles.Step(state.clock)

				expect(#state.renders).to.equal(3)
				expect(state.renders[3].tile.tx).to.equal(2)
				expect(Tiles.Hooked()).to.beFalse()
			end
		},
		-- fails when the map captures in a frame the arbitration refuses, or asks as another owner
		{
			name = "no capture when the arbitration says no (asked as \"map\"); the plan and the hook stay for the next frame",
			func = function(state)
				local Tiles = T()

				Tiles.Begin()
				Tiles.SetPlan({{ppm = PPM, tx = 0, ty = 0, d = 1}}, state.clock)
				state.may = false
				Tiles.Step(state.clock)

				expect(#state.renders).to.equal(0)
				expect(state.asked[1]).to.equal("map")
				expect(Tiles.Pending()).to.equal(1)
				expect(Tiles.Hooked()).to.beTrue()

				state.may = true
				Tiles.Step(state.clock)
				expect(#state.renders).to.equal(1)
			end
		},
		-- fails when a tile the cache got meanwhile is made again
		{
			name = "a planned tile that exists by the time its turn comes (the minimap's preload made it) costs no capture and counts as arrived",
			func = function(state)
				local Tiles = T()

				Tiles.Begin()
				Tiles.SetPlan({{ppm = PPM, tx = 0, ty = 0, d = 1}, {ppm = PPM, tx = 1, ty = 0, d = 2}}, state.clock)
				state.cache[cacheKey(PPM, 0, 0)] = "file"
				Tiles.Step(state.clock)

				-- the first was taken from the cache, the second was made in the same Step
				expect(#state.renders).to.equal(1)
				expect(state.renders[1].tile.tx).to.equal(1)
				expect(Tiles.Pending()).to.equal(0)

				local mode = GryMod.Map.Fx.Tracker.Look(Tiles.Tracker(), GryMod.Map.Pyramid.Key(GryMod.Map.Pyramid.LevelIndex(PPM), 0, 0), state.clock, 0.3)

				expect(mode).to.equal("arrived")
			end
		},
		-- fails when a failure leaves the slot reserved, retries for ever, or plays an arrival
		{
			name = "a tile that cannot be made gives its slot back, is tried again twice and then given up (it stops waiting and never arrives)",
			func = function(state)
				local Tiles = T()
				local key = GryMod.Map.Pyramid.Key(GryMod.Map.Pyramid.LevelIndex(PPM), 0, 0)

				state.renderResult = "no render context"
				Tiles.Begin()
				Tiles.SetPlan({{ppm = PPM, tx = 0, ty = 0, d = 1}}, state.clock)

				for frame = 1, 3 do
					state.frame = frame
					Tiles.Begin()
					Tiles.Step(state.clock)
				end

				expect(#state.renders).to.equal(Tiles.MAX_TRIES)
				expect(Tiles.Pending()).to.equal(0)
				expect(Tiles.Hooked()).to.beFalse()
				expect(Tiles.Has(PPM, 0, 0)).to.beFalse()
				expect(GryMod.Map.Fx.Tracker.Waiting(Tiles.Tracker())).to.equal(0)
				expect(GryMod.Map.Fx.Tracker.Look(Tiles.Tracker(), key, state.clock, 0.3)).to.beNil()
				expect(Tiles.LastError()).to.equal("no render context")
				-- the slot is free again: a new tile is made at once
				Tiles.SetPlan({{ppm = PPM, tx = 4, ty = 4, d = 1}}, state.clock)
				state.renderResult = true
				state.frame = 9
				Tiles.Begin()
				Tiles.Step(state.clock)
				expect(Tiles.Has(PPM, 4, 4)).to.beTrue()
			end
		},
		-- fails when the plan keeps tiles that are no longer wanted
		{
			name = "a new plan drops the tiles it no longer wants (they stop waiting), asks the new ones, and an empty plan removes the hook",
			func = function(state)
				local Tiles = T()
				local P = GryMod.Map.Pyramid
				local Tracker = GryMod.Map.Fx.Tracker

				Tiles.Begin()
				Tiles.SetPlan({{ppm = PPM, tx = 0, ty = 0, d = 1}, {ppm = PPM, tx = 1, ty = 0, d = 2}}, state.clock)
				expect(Tracker.Waiting(Tiles.Tracker())).to.equal(2)

				Tiles.SetPlan({{ppm = PPM, tx = 1, ty = 0, d = 1}, {ppm = PPM, tx = 7, ty = 7, d = 2}}, state.clock + 1)
				expect(Tracker.Waiting(Tiles.Tracker())).to.equal(2)
				expect(Tracker.Look(Tiles.Tracker(), P.Key(P.LevelIndex(PPM), 0, 0), state.clock + 1, 0.3)).to.beNil()
				expect(Tracker.Look(Tiles.Tracker(), P.Key(P.LevelIndex(PPM), 7, 7), state.clock + 1, 0.3)).to.equal("waiting")

				Tiles.SetPlan({}, state.clock + 2)
				expect(Tiles.Pending()).to.equal(0)
				expect(Tiles.Hooked()).to.beFalse()
				expect(Tracker.Waiting(Tiles.Tracker())).to.equal(0)
			end
		},
		-- fails when Update makes the plan again at every frame, or never
		{
			name = "Update makes a plan from the window, and again only when the tiles needed or the tile under the mouse change (or after a while)",
			func = function(state)
				local Tiles = T()

				Tiles.Begin()

				expect(Tiles.Update(spec(PPM), state.clock)).to.beTrue()
				expect(Tiles.Pending() > 0).to.beTrue()
				expect(Tiles.Update(spec(PPM), state.clock + 0.1)).to.beFalse()

				-- the mouse in another tile
				local s = spec(PPM)

				s.mouse = {x = s.mouse.x + 2 * RES / PPM / s.mpu, y = s.mouse.y}
				expect(Tiles.Update(s, state.clock + 0.2)).to.beTrue()

				-- the same window, much later
				expect(Tiles.Update(s, state.clock + 0.3)).to.beFalse()
				expect(Tiles.Update(s, state.clock + 5)).to.beTrue()
			end
		},
		-- fails when the plan asks tiles that exist
		{
			name = "the plan leaves out the tiles of the cache and of the store",
			func = function(state)
				local Tiles = T()

				state.cache[cacheKey(PPM, 0, 0)] = "file"
				Tiles.Begin()
				Tiles.Update(spec(PPM), state.clock)

				-- the window covers only the tile (0, 0): it is there, so nothing is planned
				expect(Tiles.Pending()).to.equal(0)
			end
		},
		-- fails when a change of tile size keeps the old tiles (their size is not the new one's)
		{
			name = "a new tile size or a new level clears the store and the plan: the tiles of another size are not tiles of this one",
			func = function(state)
				local Tiles = T()

				Tiles.Begin()
				Tiles.SetPlan({{ppm = PPM, tx = 0, ty = 0, d = 1}, {ppm = PPM, tx = 1, ty = 0, d = 2}}, state.clock)
				Tiles.Step(state.clock)
				expect(Tiles.Has(PPM, 0, 0)).to.beTrue()

				state.res = 512
				Tiles.Begin()

				expect(Tiles.Has(PPM, 0, 0)).to.beFalse()
				expect(Tiles.Pending()).to.equal(0)
				expect(Tiles.Hooked()).to.beFalse()
				expect(Tiles.Store().capacity).to.equal(GryMod.Map.Store.CapacityFor(512))

				-- another level (the world's top changed)
				state.res = RES
				Tiles.Begin()
				Tiles.SetPlan({{ppm = PPM, tx = 0, ty = 0, d = 1}}, state.clock)
				state.frame = 5
				Tiles.Begin()
				Tiles.Step(state.clock)
				expect(Tiles.Has(PPM, 0, 0)).to.beTrue()

				state.level = {id = "open", open = true, zlo = -100, zhi = 9999}
				GryMod.Map.Tiles._state.level = nil
				Tiles.Begin()
				expect(Tiles.Has(PPM, 0, 0)).to.beFalse()
			end
		},
		-- fails when the render targets are made again for each tile or not reused after a Clear
		{
			name = "the render targets are made when first needed, one per slot in use, and reused after a Clear",
			func = function(state)
				local Tiles = T()

				Tiles.Begin()
				Tiles.SetPlan({{ppm = PPM, tx = 0, ty = 0, d = 1}, {ppm = PPM, tx = 1, ty = 0, d = 2}}, state.clock)
				Tiles.Step(state.clock)
				state.frame = 2
				Tiles.Begin()
				Tiles.Step(state.clock)

				expect(#state.slots).to.equal(2)

				Tiles.Clear()
				expect(Tiles.Has(PPM, 0, 0)).to.beFalse()

				Tiles.Begin()
				Tiles.SetPlan({{ppm = PPM, tx = 9, ty = 9, d = 1}}, state.clock)
				state.frame = 3
				Tiles.Begin()
				Tiles.Step(state.clock)

				-- slot 1 again: no new target
				expect(#state.slots).to.equal(2)
				expect(state.renders[3].dest.name).to.equal("rt_1024_1")
			end
		},
		-- fails when a full store lets a new tile take a slot that was drawn in this very frame
		{
			name = "when every slot of the store was looked at in this frame nothing is made (no slot is taken from a tile on screen)",
			func = function(state)
				local Tiles = T()
				local Store = GryMod.Map.Store

				Tiles.Begin()
				Store.SetCapacity(Tiles.Store(), 2)

				Tiles.SetPlan({{ppm = PPM, tx = 0, ty = 0, d = 1}, {ppm = PPM, tx = 1, ty = 0, d = 2}}, state.clock)
				Tiles.Step(state.clock)
				state.frame = 2
				Tiles.Begin()
				Tiles.Step(state.clock)

				-- both are looked at (drawn) in frame 3, then a third is wanted in the same frame
				state.frame = 3
				Tiles.Begin()
				expect(Tiles.Lookup(PPM, 0, 0) ~= nil).to.beTrue()
				expect(Tiles.Lookup(PPM, 1, 0) ~= nil).to.beTrue()
				Tiles.SetPlan({{ppm = PPM, tx = 2, ty = 0, d = 1}}, state.clock)

				local before = #state.renders

				Tiles.Step(state.clock)
				expect(#state.renders).to.equal(before)
				expect(Tiles.Pending()).to.equal(1)

				-- the next frame one of them (the least recently used) is replaced
				state.frame = 4
				Tiles.Begin()
				Tiles.Step(state.clock)
				expect(#state.renders).to.equal(before + 1)
				expect(Tiles.Has(PPM, 2, 0)).to.beTrue()
			end
		},
		-- fails when the big map calls anything of the cache but its three questions
		{
			name = "through a whole life (look, plan, make, replace, cancel, clear) the minimap's cache is only asked Has, IsEmpty and Path: nothing is stored, forgotten, cleared, trimmed or loaded in it",
			func = function(state)
				local Tiles = T()

				state.cache[cacheKey(PPM, 3, 3)] = "file"
				state.cache[cacheKey(PPM, 4, 4)] = "empty"
				Tiles.Begin()
				Tiles.Lookup(PPM, 3, 3)
				Tiles.Lookup(PPM, 4, 4)
				Tiles.Update(spec(PPM), state.clock)

				for frame = 1, 4 do
					state.frame = frame
					Tiles.Begin()
					Tiles.Step(state.clock)
				end

				state.res = 512
				Tiles.Begin()
				Tiles.Cancel()
				Tiles.Clear()
				Tiles.Reset()

				expect(#state.forbidden).to.equal(0)
			end
		},
		-- fails when Cancel leaves the hook or the waiting tiles
		{
			name = "Cancel stops the work at once: no hook, no plan, nothing waits; the tiles already made stay for a quick reopening",
			func = function(state)
				local Tiles = T()

				Tiles.Begin()
				Tiles.SetPlan({{ppm = PPM, tx = 0, ty = 0, d = 1}, {ppm = PPM, tx = 1, ty = 0, d = 2}}, state.clock)
				Tiles.Step(state.clock)
				Tiles.Cancel()

				expect(Tiles.Pending()).to.equal(0)
				expect(Tiles.Hooked()).to.beFalse()
				expect(GryMod.Map.Fx.Tracker.Waiting(Tiles.Tracker())).to.equal(0)
				expect(Tiles.Has(PPM, 0, 0)).to.beTrue()
				expect(((hook.GetTable() or {}).PostRender or {})["GryMod big map tiles"]).to.beNil()
			end
		},
		-- fails when the hook is the real thing only in the tests' imagination
		{
			name = "the work hook is a PostRender hook that exists only while tiles wait",
			func = function(state)
				local Tiles = T()
				local function installed()
					return ((hook.GetTable() or {}).PostRender or {})["GryMod big map tiles"] ~= nil
				end

				Tiles.Begin()
				expect(installed()).to.beFalse()
				Tiles.SetPlan({{ppm = PPM, tx = 0, ty = 0, d = 1}}, state.clock)
				expect(installed()).to.beTrue()
				Tiles.SetPlan({}, state.clock)
				expect(installed()).to.beFalse()
			end
		},
		-- fails when the level is not the minimap's open level, or when a missing level is remembered
		{
			name = "the level is the open level of the minimap's floors; with no answer the fallback is used and not remembered",
			func = function(state)
				local Tiles = T()

				expect(Tiles.Level() == LEVEL).to.beTrue()

				Tiles.Reset()
				GryMod.Minimap.Floors = {Outside = function() return nil, "no world bounds" end}
				expect(Tiles.Level() == Tiles.FALLBACK_LEVEL).to.beTrue()

				GryMod.Minimap.Floors = {Outside = function() return LEVEL end}
				expect(Tiles.Level() == LEVEL).to.beTrue()
			end
		}
	}
}
