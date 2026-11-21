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
-- Events (hook.Run): GryMod_MinimapProgress(done, total) once per change of those two numbers, GryMod_MinimapReady() once per request when every
-- wanted tile exists.

local Gen = GryMod.Minimap.Gen

Gen.HOOK_EVENT = "PostRender"
Gen.HOOK_NAME = "GryMod minimap generator"
Gen.CHUNK_ROWS = 32 -- block rows (of 4 pixel rows) handed to DXT1.CompressRows per call
Gen.MAX_RETRIES = 2 -- new attempts after a failure; the tile is abandoned after the last one
Gen.MAX_TILES = 2500 -- a request that would need more tiles than this is refused (a wrong extent, not a real demand)

local CHUNK_ROWS = Gen.CHUNK_ROWS
local MAX_RETRIES = Gen.MAX_RETRIES

local PHASE_CAPTURE, PHASE_COMPRESS, PHASE_STORE = 1, 2, 3

-- the clock of the budget, replaceable by the tests
Gen._clock = SysTime

-- a hot reload: the hook of the old copy goes away, and the state starts again
pcall(hook.Remove, Gen.HOOK_EVENT, Gen.HOOK_NAME)

local S = {}
Gen._state = S -- exposed for the tests only (they check that no BGRA string stays in it)

local function resetState()
	S.sig = nil -- signature of the last request
	S.level = nil -- the level table of the last request
	S.queue = {} -- entries {tile =, key =, d =} still to do, nearest first
	S.current = nil -- the tile in progress: {tile =, key =, phase =, row =, nrows =, bgra =, chunks =, tries =}
	S.wanted = {} -- key -> true for every tile of the request that is not in the cache yet (the tile in progress included)
	S.done = 0
	S.total = 0
	S.failed = 0
	S.firedDone = nil -- the (done, total) of the last Progress event
	S.firedTotal = nil
	S.readyFired = false
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
	if S.firedDone ~= S.done or S.firedTotal ~= S.total then
		S.firedDone, S.firedTotal = S.done, S.total
		hook.Run("GryMod_MinimapProgress", S.done, S.total)
	end
end

local function fireReady()
	if S.total > 0 and S.done >= S.total and not S.readyFired then
		S.readyFired = true
		hook.Run("GryMod_MinimapReady")
	end
end

-- ---------------------------------------------------------------------------------------------------------------------------------------
-- request

local function tileKey(tx, ty)
	return tx .. "," .. ty
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

-- Wants the tiles that cover the square of half-side `extentUnits` around (cx, cy), plus one tile of margin, for `level` ({id, zlo, zhi}), at the
-- resolution and definition of the settings. Returns true when the wanted set changed, false when the request is the same as the previous one
-- (nothing is done then), nil and a reason when it is not valid.
function Gen.Request(level, cx, cy, extentUnits)
	if type(level) ~= "table" or type(level.id) ~= "string" then
		return nil, "level must be a table with an id"
	end

	if not isNumber(cx) or not isNumber(cy) or not isNumber(extentUnits) or extentUnits < 0 then
		return nil, "cx, cy and extentUnits must be finite numbers"
	end

	local M = GryMod.Minimap
	local Cache, Settings = M.Cache, M.Settings

	if not Cache or not Settings then
		return nil, "Cache and Settings are required"
	end

	local res, ppm = Settings.TileRes(), Settings.Definition()
	local tx0, ty0 = Cache.TileOf(cx - extentUnits, cy - extentUnits, res, ppm)
	local tx1, ty1 = Cache.TileOf(cx + extentUnits, cy + extentUnits, res, ppm)

	-- one tile of margin on every side
	tx0, ty0, tx1, ty1 = tx0 - 1, ty0 - 1, tx1 + 1, ty1 + 1

	local sig = level.id .. "|" .. tx0 .. "," .. tx1 .. "," .. ty0 .. "," .. ty1 .. "|" .. res .. "|" .. ppm

	if sig == S.sig then
		return false
	end

	if (tx1 - tx0 + 1) * (ty1 - ty0 + 1) > Gen.MAX_TILES then
		return nil, "too many tiles"
	end

	local T = Cache.TileUnits(res, ppm)
	local levelId = level.id
	local queue, wanted = {}, {}
	local cur = S.current
	local done, total = 0, 0
	local keepCurrent = false

	for tx = tx0, tx1 do
		for ty = ty0, ty1 do
			total = total + 1

			local tile = {level = levelId, tx = tx, ty = ty, res = res, ppm = ppm}
			local key = tileKey(tx, ty)

			if cur and cur.key == key and cur.tile.level == levelId and cur.tile.res == res and cur.tile.ppm == ppm then
				-- the tile in progress is still needed: it stays (and is not queued a second time)
				keepCurrent = true
				wanted[key] = true
			elseif Cache.Has(tile) then
				done = done + 1
			else
				local dx, dy = (tx + 0.5) * T - cx, (ty + 0.5) * T - cy

				queue[#queue + 1] = {tile = tile, key = key, d = dx * dx + dy * dy}
				wanted[key] = true
			end
		end
	end

	table.sort(queue, byDistance)

	if cur and not keepCurrent then
		S.current = nil -- not needed any more: its image and chunks are left to the garbage collector
	end

	S.sig = sig
	S.level = level
	S.queue = queue
	S.wanted = wanted
	S.done = done
	S.total = total
	S.failed = 0
	S.readyFired = false

	fireProgress()

	if #queue > 0 or S.current then
		addHook()
	else
		removeHook()
		fireReady()
	end

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
		S.failed = S.failed + 1
		S.wanted[cur.key] = nil
		S.current = nil
	else
		cur.phase = PHASE_CAPTURE
	end
end

local function nextTile()
	local entry = table.remove(S.queue, 1)

	if not entry then
		return nil
	end

	S.current = {tile = entry.tile, key = entry.key, phase = PHASE_CAPTURE, row = 0, nrows = entry.tile.res / 4, bgra = nil, chunks = nil, tries = 0}

	return S.current
end

-- the work of one unit; returns "capture" when a capture was attempted (success or not), "retry" when the capture gave nothing and must be retried
-- at the next Step, nil otherwise
local function work(cur)
	local M = GryMod.Minimap

	if cur.phase == PHASE_CAPTURE then
		local C = M.Capture
		local ok, bgra, err = pcall(C and C.Render, cur.tile, S.level)

		if not ok then
			fail(cur, bgra)
		elseif bgra == nil then
			S.lastError = tostring(err) -- no render context now (menu open): not a failure, the next Step tries again

			return "retry"
		elseif type(bgra) ~= "string" then
			fail(cur, "capture returned a " .. type(bgra))
		else
			cur.bgra, cur.chunks, cur.row, cur.phase = bgra, {}, 0, PHASE_COMPRESS
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

		local ok, data, err = pcall(D and D.CompressRows, cur.bgra, res, res, first, last)

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
	local ok, stored, err = pcall(K and K.Store, cur.tile, table.concat(cur.chunks))

	if ok and stored then
		cur.chunks = nil
		S.current = nil
		S.wanted[cur.key] = nil
		S.done = S.done + 1
		fireProgress()
		fireReady()
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

	if not S.current and #S.queue == 0 then
		removeHook()
	end
end

-- ---------------------------------------------------------------------------------------------------------------------------------------
-- state

-- {done, total, percent (0..100, whole), active, failed} for the current request
function Gen.Progress()
	local total = S.total
	local percent = 0

	if total > 0 then
		percent = math.floor(S.done * 100 / total)
	end

	return {done = S.done, total = total, percent = percent, active = S.current ~= nil or #S.queue > 0, failed = S.failed}
end

-- how many tiles are left to make (the one in progress included)
function Gen.Pending()
	return #S.queue + (S.current and 1 or 0)
end

-- forgets the request, the queue and the tile in progress, and removes the hook
function Gen.Cancel()
	removeHook()
	resetState()
end
