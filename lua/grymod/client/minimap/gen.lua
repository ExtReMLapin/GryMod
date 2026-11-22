-- GryMod minimap: module gen. Filled by its owner agent (see docs/superpowers/specs/2026-11-21-minimap-design.md).
GryMod = GryMod or {}
GryMod.Minimap = GryMod.Minimap or {}
GryMod.Minimap.Gen = GryMod.Minimap.Gen or {}

-- The budgeted tile generator. The radar asks, at every draw, for the tiles around the player (Request, cheap when nothing changed); the work is done
-- by a PostRender hook that exists only while there is something to make:
--   * one tile at a time, in the order of the distance to the point asked for;
--   * a tile goes through three phases: capture (Capture.Render, needs the render context of the hook), compression (DXT1.CompressRows, CHUNK_ROWS
--     block rows per call) and storage (Cache.Store). Each call of those is one "unit of work";
--   * Step does at least one unit, then stops as soon as the time spent since `now` reaches Settings.BudgetMs(); it makes at most one capture per call
--     (a capture costs about 7 ms by itself and needs a frame of its own);
--   * the BGRA string of a tile (a megabyte or more) is dropped as soon as the last chunk is compressed, and the compressed chunks as soon as the tile is stored.
-- The other modules (Capture, DXT1, Cache, Settings) are always reached through GryMod.Minimap.<Module> at call time, so a test may replace them.
--   * a request may also ask for the floor BELOW the main level (same tile range, res and definition): its tiles are queued after every tile of the main
--     level and never counted in the main level's numbers. A below tile that was only started (not captured yet) gives way to a new main tile;
--   * it may also ask for the OUTSIDE (the open level of the map, the whole height of the world): same range, made after the main level and the floor
--     below, counted apart (outsideDone, outsideTotal, outsideFailed), and never in the main level's numbers;
--   * every tile is compressed with the 1-bit alpha option and stored in the DXT1A format (20): the void of a floor is transparent.
--   * the opaque black the engine draws for "nothing" ((0, 0, 0, 255), see Capture.IsBlackOpaque) is turned into void before the compression, in the tiles of every set
--     (a solid black erased the passes behind it, and the cache gives one file to a level whatever its role): see voidTheFill and Gen.VOID_FILL_SETS.
-- The three SETS of tiles (main, below, outside) are handled by the same code: S.sets[name] = {level, queue, done, total, failed, ...}, and SET_ORDER
-- is the order in which their queues are emptied.
-- Events (hook.Run), all about the MAIN level only except the last two: GryMod_MinimapProgress(done, total) once per change of those two numbers,
-- GryMod_MinimapReady() once per request when every wanted tile of the main level exists, GryMod_MinimapBelowReady() once per request when the
-- below level was asked for and its wanted tiles all exist, GryMod_MinimapOutsideReady() the same for the outside.
-- When the work is over (the three queues are empty, nothing is in progress: the hook goes away) and in Cancel, Cache.Flush() is called (the index of
-- the cache is written when it is dirty; the empty tiles exist only in the index). It is called under pcall and only when the function exists.

local Gen = GryMod.Minimap.Gen

Gen.HOOK_EVENT = "PostRender"
Gen.HOOK_NAME = "GryMod minimap generator"
Gen.CHUNK_ROWS = 32 -- block rows (of 4 pixel rows) handed to DXT1.CompressRows per call
Gen.MAX_RETRIES = 2 -- new attempts after a failure; the tile is abandoned after the last one
Gen.TRIM_EVERY = 64 -- tiles stored with success between two calls of Cache.Trim
Gen.RETRY_FAILED_AFTER = 30 -- seconds (RealTime) after which an identical request asks again for the tiles that were abandoned
Gen.DEFAULT_MAX_TILES = 400 -- the limit of the number of tiles of a request when GryMod.Minimap.View.MAX_TILES does not exist

local CHUNK_ROWS = Gen.CHUNK_ROWS
local MAX_RETRIES = Gen.MAX_RETRIES

local PHASE_CAPTURE, PHASE_COMPRESS, PHASE_STORE = 1, 2, 3

-- the sets of tiles of a request, in the order of their queues: the main level, the floor below, the outside. The event of a set (nil for the main
-- level, whose events are Progress and Ready) fires once when all its tiles exist, and only after the main level's own Ready.
local SET_ORDER = {"main", "below", "outside"}
local SET_EVENT = {below = "GryMod_MinimapBelowReady", outside = "GryMod_MinimapOutsideReady"}

local FORMAT_DXT1A = 20 -- VTF format of DXT1 with one bit of alpha
local COMPRESS_OPTS = {alpha = true} -- read by DXT1.CompressRows, never modified

-- the clock of the budget, replaceable by the tests
Gen._clock = SysTime
Gen._realTime = RealTime
Gen._frameTime = FrameTime -- the duration of the last frame, seconds (the preload waits while frames are slow)

-- The preload (tiles made in advance) must not freeze the game: when only preload tiles wait it works within this budget instead of the settings' (a capture
-- still costs a few ms by itself, and there is at least one unit per call), and not at all in a frame that follows a frame slower than PRELOAD_MAX_FRAME.
Gen.PRELOAD_BUDGET_MS = 2
Gen.PRELOAD_MAX_FRAME = 0.025

-- a hot reload: the hook of the old copy goes away, and the state starts again
pcall(hook.Remove, Gen.HOOK_EVENT, Gen.HOOK_NAME)

local S = {}
Gen._state = S -- exposed for the tests only (they check that no BGRA string stays in it)

S.prunedMap = nil -- the map whose old cache directories were already pruned (kept by resetState)
S.storedSinceTrim = 0 -- tiles stored with success since the last Trim (kept by resetState)

local function newSet()
	-- level = the level table of the last request (nil: this set is not wanted), queue = entries {tile =, key =, d =} nearest first
	return {level = nil, queue = {}, done = 0, total = 0, failed = 0, readyFired = false}
end

local function resetState()
	S.sigSet = false -- true once a request was accepted: the fields below describe it (numbers and ids, no string is built to compare)
	S.sigLevel, S.sigBelow, S.sigOutside = nil, nil, nil -- the ids of its levels
	S.sigTx0, S.sigTx1, S.sigTy0, S.sigTy1, S.sigRes, S.sigPpm = 0, 0, 0, 0, 0, 0
	S.wanted = {} -- scratch: the level tables of a request by set (written and cleared inside Request, so that a request makes no table for them)
	-- the below queue is made only after the main queue is empty, the outside's after both; the preload's (Gen.SetPreload, not in SET_ORDER: a request never touches it)
	-- after the three
	S.sets = {main = newSet(), below = newSet(), outside = newSet(), preload = newSet()}
	S.current = nil -- the tile in progress: {tile =, key =, set =, phase =, row =, nrows =, bgra =, chunks =, tries =}; set is "main", "below" or "outside"
	S.failedAt = nil -- RealTime of the last abandoned tile of the request (they are asked for again 30 s later)
	S.firedDone = nil -- the (done, total) of the last Progress event
	S.firedTotal = nil
	S.hooked = false
	S.lastError = nil
end

resetState()

-- ---------------------------------------------------------------------------------------------------------------------------------------
-- the work hook

local function onPostRender()
	Gen.Step(Gen._clock())
end

local function addHook()
	if not S.hooked then
		hook.Add(Gen.HOOK_EVENT, Gen.HOOK_NAME, onPostRender)
		S.hooked = true
	end
end

local function removeHook()
	if S.hooked then
		hook.Remove(Gen.HOOK_EVENT, Gen.HOOK_NAME)
		S.hooked = false
	end
end

-- ---------------------------------------------------------------------------------------------------------------------------------------
-- events

local function fireProgress()
	local main = S.sets.main

	if S.firedDone ~= main.done or S.firedTotal ~= main.total then
		S.firedDone, S.firedTotal = main.done, main.total
		pcall(hook.Run, "GryMod_MinimapProgress", main.done, main.total) -- a handler that raises an error must not stop anything
	end
end

local function fireReady()
	local sets = S.sets
	local main = sets.main

	if main.total > 0 and main.done >= main.total and not main.readyFired then
		main.readyFired = true
		pcall(hook.Run, "GryMod_MinimapReady")
	end

	-- the main level always speaks first, then the floor below, then the outside
	if main.readyFired then
		for i = 2, #SET_ORDER do
			local name = SET_ORDER[i]
			local set = sets[name]

			if set.total > 0 and set.done >= set.total and not set.readyFired then
				set.readyFired = true
				pcall(hook.Run, SET_EVENT[name])
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------------------------------------------------
-- request

local function tileKey(levelId, tx, ty, res, ppm)
	return levelId .. "|" .. tx .. "," .. ty .. "," .. res .. "," .. ppm
end

local function byDistance(a, b)
	if a.d ~= b.d then
		return a.d < b.d
	end

	if a.tile.tx ~= b.tile.tx then
		return a.tile.tx < b.tile.tx
	end

	return a.tile.ty < b.tile.ty
end

local function isNumber(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Cache.Trim(Settings.CacheBytes()): keeps the cache under its size limit. Called after Prune at the first request of a map, then after every
-- TRIM_EVERY tiles stored, so that a long game does not go over the limit. Only when both functions exist; an error is kept and ignored.
local function trimCache()
	local M = GryMod.Minimap
	local Cache, Settings = M.Cache, M.Settings

	S.storedSinceTrim = 0

	if not Cache or not Settings or type(Cache.Trim) ~= "function" or type(Settings.CacheBytes) ~= "function" then
		return
	end

	local ok, bytes = pcall(Settings.CacheBytes)

	if not ok or type(bytes) ~= "number" then
		return
	end

	local ok2, removed = pcall(Cache.Trim, bytes)

	if not ok2 then
		S.lastError = tostring(removed)
	elseif type(removed) == "number" and removed > 0 then
		S.sigSet = false -- the disk changed: the next request counts the tiles again, whether or not it is the same as the last one
	end
end

-- Cache.Flush(): the index of the cache is written when it was changed (the cache writes it every few tiles; the empty tiles live only in it). Called
-- when the work is over and by Cancel; only when the function exists, under pcall: an error is kept and ignored.
local function flushCache()
	local Cache = GryMod.Minimap.Cache

	if type(Cache) ~= "table" or type(Cache.Flush) ~= "function" then
		return
	end

	local ok, err = pcall(Cache.Flush)

	if not ok then
		S.lastError = tostring(err)
	end
end

-- Cache.Prune (the old cache directories of this map: a key of a former version, a map that changed size) once per map: the first request after the
-- name of the map changed. The name is kept in the state, which a Cancel does not reset. An error in Prune never stops the request.
local function pruneOnce(Cache)
	local map = game.GetMap()

	if type(map) ~= "string" or map == S.prunedMap then
		return
	end

	S.prunedMap = map

	if type(Cache.Prune) == "function" then
		local ok, err = pcall(Cache.Prune)

		if not ok then
			S.lastError = tostring(err)
		end
	end

	trimCache()
end

-- Makes the queue of one level over the tile range tx0..tx1, ty0..ty1 (the tiles the cache already has are counted as done and not queued).
-- `cur` is the tile in progress: when it is one of this level's tiles and still worth keeping, it is not queued again, its set is changed to `set`
-- ("main", "below" or "outside") and the third result is true. Returns queue, done, keptCurrent. total = the number of tiles of the range.
local function makeQueue(Cache, levelId, set, tx0, ty0, tx1, ty1, res, ppm, T, cx, cy, cur)
	local queue, done, kept = {}, 0, false

	for tx = tx0, tx1 do
		for ty = ty0, ty1 do
			local tile = {level = levelId, tx = tx, ty = ty, res = res, ppm = ppm}
			local key = tileKey(levelId, tx, ty, res, ppm)

			-- the tile in progress stays when it is needed again; a tile of the floor below or of the outside that has not been captured yet has
			-- cost nothing, so it does not keep a main tile waiting
			if cur and cur.key == key and (set == "main" or cur.phase ~= PHASE_CAPTURE) then
				cur.set = set
				kept = true
			elseif Cache.Has(tile) then
				done = done + 1
			else
				local dx, dy = (tx + 0.5) * T - cx, (ty + 0.5) * T - cy

				queue[#queue + 1] = {tile = tile, key = key, d = dx * dx + dy * dy}
			end
		end
	end

	table.sort(queue, byDistance)

	return queue, done, kept
end

-- Wants the tiles that cover the square of half-side `extentUnits` around (cx, cy), plus one tile of margin, for `level` ({id, zlo, zhi}), at the
-- resolution and definition of the settings; `below` (optional, a level table) asks for the same tiles of the floor below, made after the main ones;
-- `outside` (optional, a level table: the open level of the map) asks for them once more, made after the floor below. An outside with the id of the
-- main level or of the floor below is ignored (the same tiles twice).
-- Returns true when the wanted set changed, false when the request is the same as the previous one (nothing is done then), nil and a reason when it
-- is not valid. A refused request ("too many tiles": more than View.MAX_TILES, 400 without View; "no tile size") changes nothing: the previous
-- request stays in force. An identical request is not ignored when a Trim removed tiles (the disk changed) or when tiles were abandoned more than
-- RETRY_FAILED_AFTER seconds ago: they are asked for again.
function Gen.Request(level, cx, cy, extentUnits, below, outside)
	if type(level) ~= "table" or type(level.id) ~= "string" then
		return nil, "level must be a table with an id"
	end

	if below ~= nil and (type(below) ~= "table" or type(below.id) ~= "string") then
		return nil, "below must be a table with an id"
	end

	if outside ~= nil and (type(outside) ~= "table" or type(outside.id) ~= "string") then
		return nil, "outside must be a table with an id"
	end

	if below and below.id == level.id then
		below = nil -- the same floor twice is one floor
	end

	if outside and (outside.id == level.id or (below and outside.id == below.id)) then
		outside = nil
	end

	if not isNumber(cx) or not isNumber(cy) or not isNumber(extentUnits) or extentUnits < 0 then
		return nil, "cx, cy and extentUnits must be finite numbers"
	end

	local M = GryMod.Minimap
	local Cache, Settings = M.Cache, M.Settings

	if not Cache or not Settings then
		return nil, "Cache and Settings are required"
	end

	pruneOnce(Cache)

	local res, ppm = Settings.TileRes(), Settings.Definition()
	local T = Cache.TileUnits(res, ppm)

	if not isNumber(T) or T <= 0 then
		return nil, "no tile size"
	end

	local tx0, ty0 = Cache.TileOf(cx - extentUnits, cy - extentUnits, res, ppm)
	local tx1, ty1 = Cache.TileOf(cx + extentUnits, cy + extentUnits, res, ppm)

	-- one tile of margin on every side
	tx0, ty0, tx1, ty1 = tx0 - 1, ty0 - 1, tx1 + 1, ty1 + 1

	-- the same request as the previous one (the radar asks at every draw): compared field by field, nothing is allocated
	local belowId = below and below.id or nil
	local outsideId = outside and outside.id or nil

	if S.sigSet and level.id == S.sigLevel and belowId == S.sigBelow and outsideId == S.sigOutside and tx0 == S.sigTx0 and tx1 == S.sigTx1 and ty0 == S.sigTy0
		and ty1 == S.sigTy1 and res == S.sigRes and ppm == S.sigPpm then
		if not S.failedAt or Gen._realTime() - S.failedAt < Gen.RETRY_FAILED_AFTER then
			return false
		end
	end

	local count = (tx1 - tx0 + 1) * (ty1 - ty0 + 1)
	local View = M.View
	local maxTiles = View and View.MAX_TILES

	if type(maxTiles) ~= "number" then
		maxTiles = Gen.DEFAULT_MAX_TILES
	end

	if count > maxTiles then
		return nil, "too many tiles"
	end

	local cur = S.current
	local wanted = S.wanted
	local kept = false
	local pending = false

	-- one queue per set, in SET_ORDER; a set that is not asked for is empty (total 0)
	wanted.main, wanted.below, wanted.outside = level, below, outside

	for i = 1, #SET_ORDER do
		local name = SET_ORDER[i]
		local set = S.sets[name]
		local want = wanted[name]

		if want then
			local queue, done, keptHere = makeQueue(Cache, want.id, name, tx0, ty0, tx1, ty1, res, ppm, T, cx, cy, cur)

			set.level, set.queue, set.done, set.total = want, queue, done, count
			kept = kept or keptHere
			pending = pending or #queue > 0
		else
			set.level, set.queue, set.done, set.total = nil, {}, 0, 0
		end

		set.failed = 0
		set.readyFired = false
	end

	wanted.main, wanted.below, wanted.outside = nil, nil, nil

	-- the preload is made after everything that is asked for, and is never lost: a preload tile not captured yet gives way and goes back to the front of its queue,
	-- one that is under way (its image is being compressed) is finished first
	if cur and not kept and cur.set == "preload" then
		if cur.phase == PHASE_CAPTURE then
			table.insert(S.sets.preload.queue, 1, {tile = cur.tile, key = cur.key, level = cur.level, d = 0})
			S.current = nil
		end
	elseif cur and not kept then
		S.current = nil -- not needed any more: its image and chunks are left to the garbage collector
	end

	pending = pending or #S.sets.preload.queue > 0

	S.failedAt = nil

	fireProgress()

	if pending or S.current then
		addHook()
	elseif S.hooked then
		removeHook()
		flushCache() -- the work is over
	end

	-- the request is recorded only now: whatever happened above, a request that did not get its hook is not taken for done
	S.sigSet, S.sigLevel, S.sigBelow, S.sigOutside = true, level.id, belowId, outsideId
	S.sigTx0, S.sigTx1, S.sigTy0, S.sigTy1, S.sigRes, S.sigPpm = tx0, tx1, ty0, ty1, res, ppm

	fireReady()

	return true
end

-- ---------------------------------------------------------------------------------------------------------------------------------------
-- work

-- a failed attempt on the tile in progress: another try from the capture, or abandoned after MAX_RETRIES new attempts
local function fail(cur, why)
	S.lastError = tostring(why)
	cur.tries = cur.tries + 1
	cur.bgra, cur.chunks = nil, nil

	if cur.tries > MAX_RETRIES then
		local set = S.sets[cur.set]

		set.failed = set.failed + 1
		S.failedAt = Gen._realTime()
		S.current = nil
	else
		cur.phase = PHASE_CAPTURE
	end
end

-- the number of tiles waiting in the three queues (the one in progress is not counted)
local function queued()
	local sets = S.sets

	return #sets.main.queue + #sets.below.queue + #sets.outside.queue + #sets.preload.queue
end

local function nextTile()
	local set, entry

	-- the main queue first, then the floor below, then the outside
	for i = 1, #SET_ORDER do
		set = SET_ORDER[i]
		entry = table.remove(S.sets[set].queue, 1)

		if entry then
			break
		end
	end

	if not entry then
		-- the preload, last of all. A tile the cache got meanwhile (a request made it) is counted as done and skipped.
		local pre = S.sets.preload
		local Cache = GryMod.Minimap.Cache

		while #pre.queue > 0 do
			local candidate = table.remove(pre.queue, 1)

			if Cache and type(Cache.Has) == "function" and Cache.Has(candidate.tile) then
				pre.done = pre.done + 1
			else
				entry, set = candidate, "preload"

				break
			end
		end
	end

	if not entry then
		return nil
	end

	-- `level` is the preload tile's own level table (a preload makes tiles of many levels); the other sets use the level of their request
	S.current = {tile = entry.tile, key = entry.key, set = set, level = entry.level, phase = PHASE_CAPTURE, row = 0, nrows = entry.tile.res / 4, bgra = nil, chunks = nil, tries = 0}

	return S.current
end

-- the tile in progress is now in the cache: it counts as done and fires the events of its level
local function finishTile(cur)
	cur.chunks = nil
	cur.bgra = nil
	S.current = nil

	local set = S.sets[cur.set]

	set.done = set.done + 1

	if cur.set == "main" then
		fireProgress()
	end

	fireReady()
end

-- A tile that is all void (no floor in it: the capture of a corner of the map) is not compressed nor stored as a file: Cache.StoreEmpty(tile)
-- remembers it in the index. Returns true when that was done. Without DXT1.IsAllVoid or Cache.StoreEmpty, or when one of them raises an error or
-- says no, it returns false and the tile takes the normal path.
local function storeIfEmpty(cur, bgra)
	local M = GryMod.Minimap
	local D, K = M.DXT1, M.Cache

	if not D or not K or type(D.IsAllVoid) ~= "function" or type(K.StoreEmpty) ~= "function" then
		return false
	end

	local res = cur.tile.res
	local ok, void = pcall(D.IsAllVoid, bgra, res, res)

	if not ok or void ~= true then
		return false
	end

	local ok2, stored = pcall(K.StoreEmpty, cur.tile)

	if ok2 and stored == true then
		finishTile(cur)

		return true
	end

	return false
end

-- The opaque black of "nothing" (see Capture.IsBlackOpaque): the engine draws exactly (0, 0, 0, 255) where the slab of a level has nothing to show (inside earth, a sky
-- brush). By the void rule that is a solid pixel, so a tile drawn over what is behind it would be a black wall hiding it.
--   * every pixel (0, 0, 0, 255) of the tile becomes void (transparent) before the compression, whichever set asked for the tile. A tile is stored under the name of its level
--     and not of its role: the main level of today is the floor below or the outside of tomorrow, and the cache hands the same file to all of them, so the content of a
--     tile must not depend on who asked for it first. Black geometry (alpha 1) and every coloured pixel stay as they are. A tile that has nothing else is then an empty tile
--     (storeIfEmpty);
--   * Gen.VOID_FILL_SETS says which sets get that treatment. A set left out is compressed as it is, except that a tile that is nothing but opaque black is a picture of
--     nothing and becomes all void, hence an empty tile (before the main level followed that rule alone).
-- Without the functions of Capture, or when one of them raises or gives something that is not a picture of the same size, the picture is used as it is.
Gen.VOID_FILL_SETS = {main = true, below = true, outside = true, preload = true}

local function voidTheFill(set, bgra)
	local C = GryMod.Minimap.Capture

	if type(C) ~= "table" then
		return bgra
	end

	if Gen.VOID_FILL_SETS[set] ~= true then
		if type(C.IsAllBlackOpaque) ~= "function" then
			return bgra
		end

		local ok, all = pcall(C.IsAllBlackOpaque, bgra)

		if ok and all == true then
			return string.rep("\0", #bgra)
		end

		return bgra
	end

	if type(C.BlackOpaqueToVoid) ~= "function" then
		return bgra
	end

	local ok, out = pcall(C.BlackOpaqueToVoid, bgra)

	if ok and type(out) == "string" and #out == #bgra then
		return out
	end

	return bgra
end

-- the work of one unit; returns "capture" when a capture was attempted (success or not), "retry" when the capture gave nothing and must be retried
-- at the next Step, nil otherwise
local function work(cur)
	local M = GryMod.Minimap

	if cur.phase == PHASE_CAPTURE then
		local C = M.Capture
		local ok, bgra, err = pcall(C and C.Render, cur.tile, cur.level or S.sets[cur.set].level)

		if not ok then
			fail(cur, bgra)
		elseif bgra == nil then
			-- Capture.Render says "capture unavailable" when there is no render context now (menu open): not a failure, the next Step tries
			-- again. Any other reason (no render target, bad level, wrong size, an error in RenderView) is permanent: an attempt that counts.
			if err == "capture unavailable" then
				S.lastError = err

				return "retry"
			end

			fail(cur, err or "capture returned nothing")
		elseif type(bgra) ~= "string" then
			fail(cur, "capture returned a " .. type(bgra))
		else
			bgra = voidTheFill(cur.set, bgra)

			if not storeIfEmpty(cur, bgra) then
				cur.bgra, cur.chunks, cur.row, cur.phase = bgra, {}, 0, PHASE_COMPRESS
			end
		end

		return "capture"
	end

	if cur.phase == PHASE_COMPRESS then
		local D = M.DXT1
		local first = cur.row
		local last = first + CHUNK_ROWS - 1
		local res = cur.tile.res

		if last > cur.nrows - 1 then
			last = cur.nrows - 1
		end

		local ok, data, err = pcall(D and D.CompressRows, cur.bgra, res, res, first, last, COMPRESS_OPTS)

		if not ok or type(data) ~= "string" then
			fail(cur, ok and err or data)

			return nil
		end

		local chunks = cur.chunks

		chunks[#chunks + 1] = data
		cur.row = last + 1

		if cur.row >= cur.nrows then
			cur.bgra = nil -- the image is not needed any more
			cur.phase = PHASE_STORE
		end

		return nil
	end

	-- PHASE_STORE
	local K = M.Cache
	local ok, stored, err = pcall(K and K.Store, cur.tile, table.concat(cur.chunks), FORMAT_DXT1A)

	if ok and stored then
		finishTile(cur)

		S.storedSinceTrim = S.storedSinceTrim + 1

		if S.storedSinceTrim >= Gen.TRIM_EVERY then
			trimCache()
		end
	else
		fail(cur, ok and err or stored)
	end

	return nil
end

-- The body of the hook. `now` is the clock's value (SysTime(), seconds) at the start of the frame's work.
function Gen.Step(now)
	local Settings = GryMod.Minimap.Settings
	local budget = (Settings and tonumber(Settings.BudgetMs()) or 6) / 1000
	local clock = Gen._clock
	local captured = false

	now = tonumber(now) or clock()

	-- only preload tiles wait (nothing asked for by the radar): the small budget, and nothing at all after a slow frame (the hook stays, the work comes back)
	local sets = S.sets

	if #sets.main.queue + #sets.below.queue + #sets.outside.queue == 0 and (not S.current or S.current.set == "preload") then
		local last = Gen._frameTime and Gen._frameTime() or 0

		if type(last) == "number" and last > Gen.PRELOAD_MAX_FRAME then
			return
		end

		budget = math.min(budget, Gen.PRELOAD_BUDGET_MS / 1000)
	end

	while true do
		local cur = S.current or nextTile()

		if not cur then
			break
		end

		if cur.phase == PHASE_CAPTURE and captured then
			break -- one capture per call
		end

		local r = work(cur)

		if r == "retry" then
			break
		end

		if r == "capture" then
			captured = true
		end

		if clock() - now >= budget then
			break
		end
	end

	if not S.current and queued() == 0 then
		if S.hooked then
			removeHook()
			flushCache() -- the work is over: the index of the cache is written
		end
	end
end

-- ---------------------------------------------------------------------------------------------------------------------------------------
-- state

-- {done, total, percent (0..100, whole), active, failed} for the MAIN level of the current request, plus belowDone, belowTotal and belowFailed
-- for the floor below, and outsideDone, outsideTotal and outsideFailed for the outside (0 when there is none)
function Gen.Progress()
	local sets = S.sets
	local main, below, outside = sets.main, sets.below, sets.outside
	local total = main.total
	local percent = 0

	if total > 0 then
		percent = math.floor(main.done * 100 / total)
	end

	local cur = S.current

	return {
		done = main.done,
		total = total,
		percent = percent,
		active = #main.queue > 0 or (cur ~= nil and cur.set == "main"),
		failed = main.failed,
		belowDone = below.done,
		belowTotal = below.total,
		belowFailed = below.failed,
		outsideDone = outside.done,
		outsideTotal = outside.total,
		outsideFailed = outside.failed
	}
end

-- SetPreload(entries): the tiles to make in advance, nearest first, each {tile = {level, tx, ty, res, ppm}, level = the level table (its heights are the
-- camera's), d = the order key}. They are made after every tile of the main level, the floor below and the outside, never show in Progress (no veil), and are not
-- wiped by a request. A tile the cache has is left out. Replaces the previous preload. Returns true, or false for something that is not a list.
function Gen.SetPreload(entries)
	local pre = S.sets.preload

	pre.queue, pre.done, pre.total, pre.failed = {}, 0, 0, 0

	if type(entries) ~= "table" then
		return false
	end

	local Cache = GryMod.Minimap.Cache

	for i = 1, #entries do
		local e = entries[i]

		if type(e) == "table" and type(e.tile) == "table" and type(e.level) == "table" and not (Cache and type(Cache.Has) == "function" and Cache.Has(e.tile)) then
			local t = e.tile

			pre.queue[#pre.queue + 1] = {tile = t, key = tileKey(t.level, t.tx, t.ty, t.res, t.ppm), level = e.level, d = e.d or 0}
		end
	end

	pre.total = #pre.queue

	if pre.total > 0 then
		addHook()
	end

	return true
end

-- {done, total, failed} of the preload (the tiles that were already there when a turn came count as done)
function Gen.PreloadProgress()
	local pre = S.sets.preload

	return {done = pre.done, total = pre.total, failed = pre.failed}
end

-- how many tiles are left to make (the one in progress and those of the floor below, of the outside and of the preload included)
function Gen.Pending()
	return queued() + (S.current and 1 or 0)
end

-- forgets the request, the queue and the tile in progress, removes the hook, and writes the index of the cache if it was changed
function Gen.Cancel()
	removeHook()
	resetState()
	flushCache()
end
