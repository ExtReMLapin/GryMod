-- The big map: its tiles (GryMod.Map.Tiles). Where the pictures of the map come from, and how the missing ones are made.
--
-- THE TWO SOURCES. A tile of the map (a level, two indices, a size and a definition in pixels per metre) is found in this order:
--   1. the map's OWN store (map/store.lua): a short-lived pool of render targets in memory, filled by this file. Nothing is written to the disk;
--   2. the minimap's cache, ONLY when a tile of that very level and definition is already there (Cache.Has): its file is read through a small table of
--      materials of this file's own. The minimap's cache is only ASKED: nothing here stores, forgets, clears, trims or loads a material in it, so the big
--      map's zoom (which changes the definition) can never evict or invalidate what the radar's preload made.
-- A tile that is in neither is made by the SAME render as the minimap's (Capture.RenderTo, which shares everything with Capture.Render) into a slot of
-- the store: no compression, no file. One capture a frame at most, and none in a frame where the minimap's generator made one (Capture.MayCapture); the
-- hook that does the work exists only while tiles wait.
--
-- A picture is a table {mat, fade}: `mat` draws it opaque, `fade` draws it with the vertex alpha (the loading looks fade a tile). A tile of the store has both;
-- a tile of the cache has only its own material, for both. EMPTY stands for a tile the cache knows to be all void: it exists, there is nothing to draw.

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}
GryMod.Map.Tiles = GryMod.Map.Tiles or {}

local Tiles = GryMod.Map.Tiles

Tiles.HOOK_EVENT = "PostRender"
Tiles.HOOK_NAME = "GryMod big map tiles"
Tiles.MAX_TRIES = 3 -- a tile that fails is asked again twice, then given up
Tiles.REPLAN_SECONDS = 1.5 -- the plan is made again at least this often while the map is open (a tile of the store may have been evicted)
Tiles.MAX_MATERIALS = 48 -- the materials of the minimap's tiles kept by this file
Tiles.EMPTY = {empty = true}

-- the level used when the minimap's floors cannot say (no world bounds known): the whole height of a Source world
Tiles.FALLBACK_LEVEL = {id = "open_map", open = true, zlo = -16384, zhi = 16384}

local Pyramid, Store, Fx

local function modules()
	Pyramid, Store, Fx = GryMod.Map.Pyramid, GryMod.Map.Store, GryMod.Map.Fx
end

-- the engine, behind a table so that a test can replace it ---------------------------------------------------------------------------------------
Tiles.Engine = Tiles.Engine or {}

local Engine = Tiles.Engine

function Engine.RealTime()
	return RealTime()
end

function Engine.FrameNumber()
	return FrameNumber()
end

-- A slot of the pool: a render target and the two materials that show it.
function Engine.NewSlot(res, index)
	local name = "gry_map_tile_" .. res .. "_" .. index
	local rt = GetRenderTargetEx(name, res, res, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGBA8888)

	if not rt then
		return nil
	end

	local texture = rt:GetName()
	local opaque = CreateMaterial(name .. "_o1", "UnlitGeneric", {["$basetexture"] = texture, ["$vertexcolor"] = 1, ["$clamps"] = 1, ["$clampt"] = 1, ["$nolod"] = 1})
	local fade = CreateMaterial(name .. "_f1", "UnlitGeneric", {["$basetexture"] = texture, ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$translucent"] = 1, ["$clamps"] = 1, ["$clampt"] = 1, ["$nolod"] = 1})

	return {rt = rt, pic = {mat = opaque, fade = fade}}
end

function Engine.LoadMaterial(path)
	return Material(path)
end

-- the state ------------------------------------------------------------------------------------------------------------------------------------

local S = Tiles._state

if not S then
	S = {}
	Tiles._state = S
end

local function freshState()
	modules()

	S.store = Store.New(Store.CapacityFor(1024))
	S.tracker = Fx.Tracker.New()
	S.pool = {} -- res -> {slot, slot, ...}: render targets cannot be freed; the engine gives the same one back for the same name, so a new pool is cheap
	S.pending = {} -- the plan: {ppm, tx, ty, key}, nearest first
	S.pendingKeys = {}
	S.tries = {}
	S.mats = {} -- key -> {pic, stamp}: the materials of the minimap's tiles
	S.matCount = 0
	S.matTick = 0
	S.bad = {} -- key -> true: a tile of the cache whose material did not load
	S.level, S.levelMap = nil, nil
	S.res = nil
	S.hooked = false
	S.sig1, S.sig2, S.sig3, S.sig4, S.sig5, S.sig6, S.sig7 = nil, nil, nil, nil, nil, nil, nil
	S.planAt = -math.huge
	S.frame = 0
	S.scratch = {level = "", tx = 0, ty = 0, res = 0, ppm = 0}
	S.lastError = nil
end

freshState()

-- Everything back to the start (a hot reload, the tests). The render targets are not freed (the engine cannot): the next pool asks for them by name again.
function Tiles.Reset()
	pcall(hook.Remove, Tiles.HOOK_EVENT, Tiles.HOOK_NAME)
	freshState()
end

-- a hot reload: the hook of the old copy goes away
pcall(hook.Remove, Tiles.HOOK_EVENT, Tiles.HOOK_NAME)

function Tiles.Tracker()
	return S.tracker
end

function Tiles.Store()
	return S.store
end

function Tiles.LastError()
	return S.lastError
end

-- the level -----------------------------------------------------------------------------------------------------------------------------------

-- The level the big map shows: the open level of the map (the whole height of the world cut at the sky: terrain, rocks, roofs, what a satellite sees),
-- the same table the minimap's floors give for "the outside", so the tiles the radar's preload made for it are the very tiles of this level. Once per map.
function Tiles.Level()
	local map = game.GetMap()

	if S.level and S.levelMap == map then
		return S.level
	end

	local M = GryMod.Minimap
	local Floors = M and M.Floors
	local level

	if Floors and type(Floors.Outside) == "function" then
		local ok, found = pcall(Floors.Outside, {})

		if ok and type(found) == "table" then
			level = found
		end
	end

	-- not remembered when the floors had no answer yet (the world's bounds may come later)
	if not level then
		return Tiles.FALLBACK_LEVEL
	end

	S.level, S.levelMap = level, map

	return level
end

-- Starts a frame of the map: the level, the tile size of the settings and the capacity that goes with it; the store is cleared when the level or the size
-- changed (a plan is dropped with it). Returns the level and the size.
function Tiles.Begin()
	modules()

	local M = GryMod.Minimap
	local res = M and M.Settings and M.Settings.TileRes() or 1024
	local level = Tiles.Level()

	if Store.Scope(S.store, level.id, res) then
		Store.SetCapacity(S.store, Store.CapacityFor(res))
		Tiles.CancelPlan()
		S.mats, S.matCount, S.bad = {}, 0, {}
		Fx.Tracker.Reset(S.tracker)
	end

	S.res = res
	S.frame = Engine.FrameNumber()

	return level, res
end

-- looking tiles up -------------------------------------------------------------------------------------------------------------------------------

local function levelIndex(ppm)
	return Pyramid.LevelIndex(ppm)
end

-- The minimap's tile as a picture: its material, loaded through a table of this file's own. nil when it does not load.
local function cachePic(Cache, key, tile)
	local entry = S.mats[key]

	if entry then
		S.matTick = S.matTick + 1
		entry.stamp = S.matTick

		return entry.pic
	end

	if S.bad[key] then
		return nil
	end

	local ok, path = pcall(Cache.Path, tile)

	if not ok or type(path) ~= "string" then
		S.bad[key] = true

		return nil
	end

	local okm, mat = pcall(Engine.LoadMaterial, "../data/" .. path)

	if not okm or not mat or (mat.IsError and mat:IsError()) then
		S.bad[key] = true

		return nil
	end

	-- a full table drops the least recently used material (only the reference: the engine owns the texture, and the minimap's own table is not touched)
	if S.matCount >= Tiles.MAX_MATERIALS then
		local oldest, best

		for k, e in pairs(S.mats) do
			if best == nil or e.stamp < best then
				oldest, best = k, e.stamp
			end
		end

		if oldest ~= nil then
			S.mats[oldest] = nil
			S.matCount = S.matCount - 1
		end
	end

	S.matTick = S.matTick + 1
	S.mats[key] = {pic = {mat = mat, fade = mat}, stamp = S.matTick}
	S.matCount = S.matCount + 1

	return S.mats[key].pic
end

-- The picture of the tile (tx, ty) at definition `ppm`: the pic of the map's own store, else the minimap's when its cache has that very tile, else EMPTY for a
-- tile the cache knows to be all void, else nil. Looking counts as a use for the store's rule. Only asks the cache (Has, IsEmpty, Path).
function Tiles.Lookup(ppm, tx, ty)
	local index = levelIndex(ppm)

	if not index then
		return nil
	end

	local key = Pyramid.Key(index, tx, ty)
	local slot = Store.Slot(S.store, key, S.frame)

	if slot then
		local entry = S.pool[S.res] and S.pool[S.res][slot]

		return entry and entry.pic or nil
	end

	local M = GryMod.Minimap
	local Cache = M and M.Cache

	if not Cache or S.res == nil then
		return nil
	end

	local tile = S.scratch

	tile.level, tile.tx, tile.ty, tile.res, tile.ppm = S.store.scopeLevel, tx, ty, S.res, ppm

	if not Cache.Has(tile) then
		return nil
	end

	if Cache.IsEmpty(tile) then
		return Tiles.EMPTY
	end

	return cachePic(Cache, key, tile)
end

-- Whether the tile exists in either source (what the plan leaves out).
function Tiles.Has(ppm, tx, ty)
	return Tiles.Lookup(ppm, tx, ty) ~= nil
end

-- making tiles --------------------------------------------------------------------------------------------------------------------------------

local function hookFunction()
	Tiles.Step(Engine.RealTime())
end

local function addHook()
	if not S.hooked then
		hook.Add(Tiles.HOOK_EVENT, Tiles.HOOK_NAME, hookFunction)
		S.hooked = true
	end
end

local function removeHook()
	if S.hooked then
		hook.Remove(Tiles.HOOK_EVENT, Tiles.HOOK_NAME)
		S.hooked = false
	end
end

function Tiles.Pending()
	return #S.pending
end

function Tiles.Hooked()
	return S.hooked
end

-- The slot i of the pool of this size, made when it is first needed.
local function poolSlot(res, i)
	local list = S.pool[res]

	if not list then
		list = {}
		S.pool[res] = list
	end

	local slot = list[i]

	if not slot then
		slot = Engine.NewSlot(res, i)
		list[i] = slot or nil
	end

	return slot
end

-- Drops the plan: every tile that waited stops waiting (no arrival look for it) and the hook goes away.
function Tiles.CancelPlan()
	local now = Engine.RealTime()

	for i = 1, #S.pending do
		Fx.Tracker.Drop(S.tracker, S.pending[i].key, now)
	end

	S.pending, S.pendingKeys, S.tries = {}, {}, {}
	removeHook()
end

-- A new plan (Pyramid.Plan: {{ppm, tx, ty, d}, ...}, the coarse level first, each nearest to the mouse first). A tile that was waiting and is no longer in the
-- plan is dropped (the player zoomed away), one that is new is asked (it starts to wait). The order is the plan's.
function Tiles.SetPlan(plan, now)
	modules()

	local keys, list = {}, {}

	for i = 1, #plan do
		local e = plan[i]
		local index = levelIndex(e.ppm)

		if index then
			local key = Pyramid.Key(index, e.tx, e.ty)

			if not keys[key] then
				keys[key] = true
				list[#list + 1] = {ppm = e.ppm, tx = e.tx, ty = e.ty, key = key}
			end
		end
	end

	for i = 1, #S.pending do
		local key = S.pending[i].key

		if not keys[key] then
			Fx.Tracker.Drop(S.tracker, key, now)
			S.tries[key] = nil
		end
	end

	for i = 1, #list do
		Fx.Tracker.Request(S.tracker, list[i].key, now)
	end

	S.pending, S.pendingKeys = list, keys

	if #list > 0 then
		addHook()
	else
		removeHook()
	end
end

-- Makes the plan for the window described by `spec` (see Pyramid.Plan) when the tiles it needs changed, or every REPLAN_SECONDS; the work is the hook's.
function Tiles.Update(spec, now)
	modules()

	local s1, s2, s3, s4, s5, s6, s7 = Pyramid.Signature(spec)

	if s1 == S.sig1 and s2 == S.sig2 and s3 == S.sig3 and s4 == S.sig4 and s5 == S.sig5 and s6 == S.sig6 and s7 == S.sig7 and now - S.planAt < Tiles.REPLAN_SECONDS then
		return false
	end

	S.sig1, S.sig2, S.sig3, S.sig4, S.sig5, S.sig6, S.sig7 = s1, s2, s3, s4, s5, s6, s7
	S.planAt = now
	Tiles.SetPlan(Pyramid.Plan(spec, Tiles.Has), now)

	return true
end

-- A tile that cannot be made: tried again later, then given up (it stops waiting, with no arrival look).
local function failed(entry, now, why)
	S.lastError = tostring(why)

	local tries = (S.tries[entry.key] or 0) + 1

	S.tries[entry.key] = tries

	if tries >= Tiles.MAX_TRIES then
		Fx.Tracker.Drop(S.tracker, entry.key, now)
		S.pendingKeys[entry.key] = nil
		S.tries[entry.key] = nil
	else
		S.pending[#S.pending + 1] = entry
	end
end

-- The body of the hook: makes at most ONE tile (one capture), the nearest one that is not there yet. A tile that exists meanwhile (the minimap's preload made
-- it) counts as arrived at once and costs nothing. Nothing is made in a frame where the arbitration (Capture.MayCapture) says no, or when every slot of the
-- store is in use this frame.
function Tiles.Step(now)
	modules()

	local M = GryMod.Minimap
	local Capture = M and M.Capture
	local level = Tiles.Level()
	local frame = Engine.FrameNumber()

	while #S.pending > 0 do
		local entry = S.pending[1]

		if Tiles.Has(entry.ppm, entry.tx, entry.ty) then
			table.remove(S.pending, 1)
			S.pendingKeys[entry.key] = nil
			Fx.Tracker.Arrive(S.tracker, entry.key, now)
		else
			if not Capture or type(Capture.RenderTo) ~= "function" then
				break
			end

			if type(Capture.MayCapture) == "function" and Capture.MayCapture("map") == false then
				break
			end

			local slot = Store.Reserve(S.store, entry.key, frame)

			if not slot then
				break -- every slot was looked at in this frame
			end

			local target = poolSlot(S.res, slot)

			table.remove(S.pending, 1)

			if not target then
				Store.Release(S.store, entry.key)
				failed(entry, now, "no render target")
			else
				local tile = {level = level.id, tx = entry.tx, ty = entry.ty, res = S.res, ppm = entry.ppm}
				local ok, rendered, why = pcall(Capture.RenderTo, tile, level, target.rt)

				if ok and rendered == true then
					Store.Commit(S.store, entry.key, now)
					S.pendingKeys[entry.key] = nil
					Fx.Tracker.Arrive(S.tracker, entry.key, now)
				else
					Store.Release(S.store, entry.key)
					failed(entry, now, ok and why or rendered)
				end
			end

			break -- one capture
		end
	end

	if #S.pending == 0 then
		removeHook()
	end
end

-- The map closes: nothing is made any more. The tiles stay in the store for a while (a quick reopening finds them).
function Tiles.Cancel()
	Tiles.CancelPlan()
	S.sig1 = nil
end

-- Forgets every tile of the store and the minimap's tiles this file holds a reference to (a long time after the map was closed, a new map).
function Tiles.Clear()
	Tiles.CancelPlan()
	Store.Clear(S.store)
	S.mats, S.matCount, S.bad = {}, 0, {}
	Fx.Tracker.Reset(S.tracker)
	S.sig1 = nil
end
