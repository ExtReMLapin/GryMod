-- Tests of the minimap's budgeted tile generator (lua/grymod/client/minimap/gen.lua), GLuaTest format, client realm.
-- The generator works with four modules written by other people (Capture, DXT1, Cache, Settings): here they are replaced by stand-ins that keep
-- their calls in memory (a capture needs a render context, the compressor and the disk are not what is tested), and the clock of the generator
-- is replaced by one that advances by a fixed time at each reading, so the budget cuts the work at an exact place. Everything replaced is put
-- back in afterEach inside a pcall, also when a case failed.
--
-- Numbers used by the hand cases: a tile is 1000 units wide (the stand-in of Cache.TileUnits), tile (tx, ty) covers x in [tx*1000, (tx+1)*1000)
-- and y in [ty*1000, (ty+1)*1000), its centre is ((tx+0.5)*1000, (ty+0.5)*1000).
--   BIG  = Request(level, 1500, 500, 600): x covers 900..2100 (tx 0..2), y covers -100..1100 (ty -1..1), plus one tile of margin: tx -1..3, ty -2..2 = 25 tiles
--   SMALL = Request(level, 500, 500, 100): tx 0 and ty 0, plus the margin: tx -1..1, ty -1..1 = 9 tiles

local HOOK_EVENT = "PostRender"
local HOOK_NAME = "GryMod minimap generator"
local LISTENER = "gry_gen_test_listener"

local BELOW = {id = "a0", zlo = -200, zhi = -40} -- the floor below LEVEL

-- the only reason that Capture.Render gives for "not now" (the menu is open): such a capture is tried again without being counted as a failure
local UNAVAILABLE = "capture unavailable"

local LEVEL = {id = "a1", zlo = 0, zhi = 160}

-- the outside (the open level of the map: the whole height of the world), generated after the floor below
local OUTSIDE = {id = "open", open = true, zlo = -500, zhi = 900}

local saved = nil -- the originals, kept outside `state` so that afterEach always finds them

local function gen()
	return GryMod.Minimap and GryMod.Minimap.Gen
end

local function tkey(tile)
	return tile.tx .. "," .. tile.ty
end

local function join(list)
	return table.concat(list, " ")
end

-- the tile that the stand-in cache holds, for a given (tx, ty) at the current res / ppm of the stand-in settings
local function cacheKey(tile)
	return tile.level .. "|" .. tile.tx .. "," .. tile.ty .. "|" .. tile.res .. "|" .. tile.ppm
end

local function install(st)
	local M = GryMod.Minimap
	local G = M.Gen

	-- The radar of the game may have a real request under way (its tile in progress, its hook): every case starts from an empty generator. The
	-- radar asks again at its next draw, and since Cancel forgets the last request it is not taken for a repeat.
	if G and G.Cancel then
		pcall(G.Cancel)
	end

	saved = {
		Capture = M.Capture,
		DXT1 = M.DXT1,
		Cache = M.Cache,
		Settings = M.Settings,
		clock = G and G._clock,
		hasClock = G ~= nil,
		prunedMap = G and G._state and G._state.prunedMap,
		sinceTrim = G and G._state and G._state.storedSinceTrim,
		View = M.View,
		realTime = G and G._realTime,
		frameTime = G and G._frameTime,
		getMap = game.GetMap,
		-- the sets that Gen changes pixel by pixel: a case may switch one off, afterEach puts all three back
		fillSets = G and type(G.VOID_FILL_SETS) == "table" and {main = G.VOID_FILL_SETS.main, below = G.VOID_FILL_SETS.below, outside = G.VOID_FILL_SETS.outside} or nil
	}

	st.res = 512
	st.ppm = 2
	st.budget = 1000 -- milliseconds: by default no limit that matters
	st.tileUnits = 1000
	st.t = 0 -- the fake clock, seconds
	st.dt = 0 -- seconds added by each reading of the clock
	st.renders = {} -- {tx, ty, level (id string), levelTable, res, ppm}
	st.bgras = {} -- every string the capture stand-in returned
	st.compress = {} -- {bgra, w, h, first, last}
	st.stores = {} -- {tile, data}
	st.stored = {} -- cache key -> true
	st.hasCalls = 0
	st.onCapture = nil -- function(tile, n) -> value; replaces the default capture
	st.onStore = nil -- function(tile, n) -> true | false, err
	st.storeCalls = 0
	st.prunes = 0
	st.calls = {} -- "prune" and "trim", in the order of the calls
	st.trims = {} -- the argument of each Trim
	st.onTrim = nil -- function() called by the Trim stand-in (it may raise)
	st.cacheBytes = 123456
	st.trimRemoved = 0 -- what the Trim stand-in answers: the number of tiles it removed
	st.rt = 1000 -- the fake RealTime, seconds
	st.isVoid = function(bgra, w, h) return false end -- the stand-in of DXT1.IsAllVoid: no void tile by default
	st.voidCalls = {} -- {bgra, w, h}
	st.empties = {} -- the tiles given to Cache.StoreEmpty
	st.onStoreEmpty = nil -- function(tile) -> true | false, err; replaces the default (stores nothing, answers true)
	st.flushes = {} -- one entry per Cache.Flush call: {pending = tiles left, hooked = the work hook is still there}
	st.onFlush = nil -- function() called by the Flush stand-in (it may raise)

	if G and G._state then
		G._state.storedSinceTrim = 0 -- the counter of the module starts from zero in each case
	end
	st.onPrune = nil -- function() called by the Prune stand-in (it may raise)

	M.Settings = {
		Enabled = function() return true end,
		Definition = function() return st.ppm end,
		TileRes = function() return st.res end,
		Rotate = function() return false end,
		BudgetMs = function() return st.budget end,
		CacheBytes = function() return st.cacheBytes end
	}

	M.Cache = {
		TileUnits = function(res, ppm) return st.tileUnits end,
		TileOf = function(x, y, res, ppm) return math.floor(x / st.tileUnits), math.floor(y / st.tileUnits) end,
		Prune = function()
			st.prunes = st.prunes + 1
			st.calls[#st.calls + 1] = "prune"

			if st.onPrune then
				st.onPrune()
			end
		end,
		Flush = function()
			st.flushes[#st.flushes + 1] = {pending = G and G.Pending() or -1, hooked = (hook.GetTable()[HOOK_EVENT] or {})[HOOK_NAME] ~= nil}

			if st.onFlush then
				st.onFlush()
			end

			return true
		end,
		StoreEmpty = function(tile)
			st.empties[#st.empties + 1] = tile

			if st.onStoreEmpty then
				local ok, err = st.onStoreEmpty(tile)

				if not ok then
					return false, err or "refused"
				end
			end

			st.stored[cacheKey(tile)] = true

			return true
		end,
		Trim = function(bytes)
			st.trims[#st.trims + 1] = bytes
			st.calls[#st.calls + 1] = "trim"

			if st.onTrim then
				st.onTrim()
			end

			if st.trimAnswersTable then
				-- the shape of the real Cache.Trim: {removed = n, bytes = bytes left}
				return {removed = st.trimRemoved, bytes = 0}
			end

			return st.trimRemoved
		end,
		Has = function(tile)
			st.hasCalls = st.hasCalls + 1

			return st.stored[cacheKey(tile)] == true
		end,
		Store = function(tile, data, format)
			st.storeCalls = st.storeCalls + 1

			if st.onStore then
				local ok, err = st.onStore(tile, st.storeCalls)

				if not ok then
					return false, err or "store refused"
				end
			end

			st.stores[#st.stores + 1] = {tile = tile, data = data, format = format}
			st.stored[cacheKey(tile)] = true

			return true
		end
	}

	M.Capture = {
		IsCapturing = function() return false end,
		Render = function(tile, level)
			st.renders[#st.renders + 1] = {tx = tile.tx, ty = tile.ty, level = tile.level, levelTable = level, res = tile.res, ppm = tile.ppm}

			if st.onCapture then
				return st.onCapture(tile, #st.renders)
			end

			local s = "BGRA-IMAGE-DATA-" .. tkey(tile)
			st.bgras[#st.bgras + 1] = s

			return s
		end
	}

	M.DXT1 = {
		IsAllVoid = function(bgra, w, h)
			st.voidCalls[#st.voidCalls + 1] = {bgra = bgra, w = w, h = h}

			return st.isVoid(bgra, w, h)
		end,
		CompressRows = function(bgra, w, h, first, last, opts)
			st.compress[#st.compress + 1] = {bgra = bgra, w = w, h = h, first = first, last = last, opts = opts}

			return "[" .. first .. "-" .. last .. "]"
		end
	}

	if G then
		G._clock = function()
			st.t = st.t + st.dt

			return st.t
		end

		G._realTime = function() return st.rt end
		-- the duration of the last frame: a fast one by default (the real one is slow while the tests run, and the preload waits after a slow frame)
		G._frameTime = function() return 0.005 end
	end
end

local function restore()
	local M = GryMod.Minimap

	if not saved then
		return
	end

	local G = M.Gen

	if G and G.Cancel then
		pcall(G.Cancel)
	end

	M.Capture, M.DXT1, M.Cache, M.Settings = saved.Capture, saved.DXT1, saved.Cache, saved.Settings

	if G and saved.hasClock then
		G._clock = saved.clock
		G._realTime = saved.realTime
		G._frameTime = saved.frameTime

		if G._state then
			G._state.prunedMap = saved.prunedMap
			G._state.storedSinceTrim = saved.sinceTrim
		end
	end

	game.GetMap = saved.getMap
	M.View = saved.View

	if saved.fillSets and G and type(G.VOID_FILL_SETS) == "table" then
		G.VOID_FILL_SETS.main, G.VOID_FILL_SETS.below, G.VOID_FILL_SETS.outside = saved.fillSets.main, saved.fillSets.below, saved.fillSets.outside
	end

	saved = nil
end

-- stands for the radar's calls: run Step until nothing is left (a limit stops a generator that never ends)
local function stepAll(st, limit)
	local G = gen()
	local steps = 0

	while G.Pending() > 0 and steps < (limit or 200) do
		G.Step(st.t)
		steps = steps + 1
	end

	return steps
end

local function renderOrder(st)
	local out = {}

	for i = 1, #st.renders do
		out[i] = st.renders[i].tx .. "," .. st.renders[i].ty
	end

	return out
end

-- a snapshot of every hook: "event|name" -> function
local function hookSnapshot()
	local snap = {}

	for event, list in pairs(hook.GetTable()) do
		for name, fn in pairs(list) do
			snap[event .. "|" .. tostring(name)] = fn
		end
	end

	return snap
end

local function request25(st)
	return gen().Request(LEVEL, 1500, 500, 600)
end

local function request9(st)
	return gen().Request(LEVEL, 500, 500, 100)
end

-- The pictures of the "opaque black" cases: 64 x 64 pixels. FILL_K is what the engine draws for "nothing" in the slab of a floor below (exactly (0, 0, 0, 255)); the picture
-- also holds one coloured opaque pixel, three pixels of black geometry (alpha 1) and one pixel of alpha 0 that carries a colour (its blue channel is tx + 10, so that the
-- tiles differ), all of which are solid.
local FILL_K, FILL_V = "\0\0\0\255", "\0\0\0\0"

local function fillPicture(tx, k)
	k = k or FILL_K

	return string.rep(k, 100) .. "\9\8\7\255" .. string.rep("\0\0\0\1", 3) .. string.rep(k, 200) .. string.char(tx + 10, 0, 0, 0) .. string.rep(k, 64 * 64 - 305)
end

-- the same picture once the opaque black is void
local function fillExpected(tx)
	return fillPicture(tx, FILL_V)
end

-- the real functions of the rule in the stand-in Capture (the stand-in of install has only Render and IsCapturing)
local function useFill(st)
	for _, name in ipairs({"BackgroundToVoid", "IsAllBackground", "FindBackground"}) do
		expect(type(saved.Capture[name])).to.equal("function")

		GryMod.Minimap.Capture[name] = saved.Capture[name]
	end
end

-- the background of a map whose sky is blue (gm_boreas: (139, 181, 227), drifting with the time): the picture of fillPicture with that colour as the fill, plus one black pixel of
-- alpha 255 at pixel 5 (a dark edge pixel of translucent geometry: it is NOT the fill of that map and must stay), and its expected result
local BLUE_K = "\227\181\139\255"
local BLACK_STRAY = "\0\0\0\255"

local function withStray(s)
	return s:sub(1, 5 * 4) .. BLACK_STRAY .. s:sub(5 * 4 + 5)
end

local function bluePicture(tx)
	return withStray(fillPicture(tx, BLUE_K))
end

local function blueExpected(tx)
	return withStray(fillPicture(tx, FILL_V))
end

-- the expected order of the 25 tiles of BIG, worked out by hand: distance from the point (1500, 500) to the tile centre, then tx, then ty
local BIG_ORDER = "1,0 " ..
	"0,0 1,-1 1,1 2,0 " .. -- 1000 away
	"0,-1 0,1 2,-1 2,1 " .. -- 1414 away
	"-1,0 1,-2 1,2 3,0 " .. -- 2000 away
	"-1,-1 -1,1 0,-2 0,2 2,-2 2,2 3,-1 3,1 " .. -- 2236 away
	"-1,-2 -1,2 3,-2 3,2" -- 2828 away

-- the expected order of the 9 tiles of SMALL
local SMALL_ORDER = "0,0 -1,0 0,-1 0,1 1,0 -1,-1 -1,1 1,-1 1,1"

return {
	groupName = "GryMod minimap generator (client)",
	beforeEach = function(state)
		saved = nil
		install(state)
		state.events = {}

		hook.Add("GryMod_MinimapProgress", LISTENER, function(done, total)
			state.events[#state.events + 1] = "P " .. tostring(done) .. " " .. tostring(total)
		end)

		hook.Add("GryMod_MinimapReady", LISTENER, function()
			state.events[#state.events + 1] = "R"
		end)

		hook.Add("GryMod_MinimapBelowReady", LISTENER, function()
			state.events[#state.events + 1] = "B"
		end)

		hook.Add("GryMod_MinimapOutsideReady", LISTENER, function()
			state.events[#state.events + 1] = "O"
		end)
	end,
	afterEach = function(state)
		pcall(hook.Remove, "GryMod_MinimapProgress", LISTENER)
		pcall(hook.Remove, "GryMod_MinimapReady", LISTENER)
		pcall(hook.Remove, "GryMod_MinimapBelowReady", LISTENER)
		pcall(hook.Remove, "GryMod_MinimapOutsideReady", LISTENER)

		for _, name in ipairs({"GryMod_MinimapProgress", "GryMod_MinimapReady", "GryMod_MinimapBelowReady", "GryMod_MinimapOutsideReady"}) do
			pcall(hook.Remove, name, LISTENER .. "_raiser")
		end

		pcall(collectgarbage, "restart")
		pcall(jit.on)
		pcall(restore)
	end,
	cases = {
		-- fails if the module is missing or lacks one of the functions of the contract
		{
			name = "the module and its public functions exist; CHUNK_ROWS is 32",
			func = function()
				local G = gen()

				expect(G ~= nil).to.beTrue()
				expect(G.Request).to.beA("function")
				expect(G.Step).to.beA("function")
				expect(G.Progress).to.beA("function")
				expect(G.Cancel).to.beA("function")
				expect(G.Pending).to.beA("function")
				expect(G.CHUNK_ROWS).to.equal(32)
			end
		},
		-- fails if the margin is not one tile, if the distance sort is wrong, or if the tile fields are not those of the settings
		{
			name = "Request: the 25 tiles of a hand case, in order of distance from the point, with one tile of margin",
			func = function(state)
				local G = gen()

				request25(state)
				expect(G.Pending()).to.equal(25)

				stepAll(state)

				expect(join(renderOrder(state))).to.equal(BIG_ORDER)

				for i = 1, #state.renders do
					local r = state.renders[i]

					expect(r.level).to.equal("a1")
					expect(r.res).to.equal(512)
					expect(r.ppm).to.equal(2)
					expect(r.levelTable).to.equal(LEVEL)
				end
			end
		},
		-- fails if a tile that Cache.Has reports is queued again, or if the tiles that exist are not counted as done
		{
			name = "Request ignores the tiles the cache already has",
			func = function(state)
				local G = gen()

				state.stored["a1|1,0|512|2"] = true
				state.stored["a1|0,0|512|2"] = true
				state.stored["a1|3,2|512|2"] = true -- a corner of the margin

				request25(state)

				expect(G.Pending()).to.equal(22)

				local p = G.Progress()

				expect(p.total).to.equal(25)
				expect(p.done).to.equal(3)

				stepAll(state)

				local order = join(renderOrder(state))

				expect((" " .. order .. " "):find(" 1,0 ", 1, true)).to.beNil()
				expect(#state.renders).to.equal(22)
				expect(order:sub(1, 8)).to.equal("1,-1 1,1")
			end
		},
		-- fails if a second identical request redoes the work (it recounts Cache.Has), adds a second hook or fires the events again
		{
			name = "two identical Requests in a row: nothing is redone, whatever the point is inside the same tiles",
			func = function(state)
				local G = gen()

				expect(request25(state)).to.beTrue()

				local fn = hook.GetTable()[HOOK_EVENT][HOOK_NAME]

				expect(fn).to.beA("function")
				stepAll(state, 1)

				local has = state.hasCalls
				local events = #state.events

				expect(request25(state)).to.beFalse()
				expect(G.Request(LEVEL, 1500, 500, 600)).to.beFalse()
				-- the point moves, but the square still covers the same tiles (x 800..2000 = tx 0..2, y -150..1050 = ty -1..1)
				expect(G.Request(LEVEL, 1400, 450, 600)).to.beFalse()

				expect(state.hasCalls).to.equal(has)
				expect(#state.events).to.equal(events)
				expect(hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.equal(fn)
				expect(G.Pending()).to.equal(24)
			end
		},
		-- fails if the comparison forgets one of: level id, res, ppm, tile range
		{
			name = "a Request that differs by level, res, ppm or tile range is not ignored",
			func = function(state)
				local G = gen()

				request25(state)

				local has = state.hasCalls

				G.Request({id = "a2", zlo = 200, zhi = 360}, 1500, 500, 600)
				expect(state.hasCalls > has).to.beTrue()
				has = state.hasCalls

				state.res = 1024
				G.Request({id = "a2", zlo = 200, zhi = 360}, 1500, 500, 600)
				expect(state.hasCalls > has).to.beTrue()
				has = state.hasCalls

				state.ppm = 4
				G.Request({id = "a2", zlo = 200, zhi = 360}, 1500, 500, 600)
				expect(state.hasCalls > has).to.beTrue()
				has = state.hasCalls

				G.Request({id = "a2", zlo = 200, zhi = 360}, 3500, 500, 600)
				expect(state.hasCalls > has).to.beTrue()
			end
		},
		-- fails if a new Request adds to the old set instead of replacing it, or throws away the tile in progress although the new set needs it
		{
			name = "a different Request replaces the wanted set and keeps the tile in progress when the new set still needs it",
			func = function(state)
				local G = gen()

				request25(state)
				state.budget = 1
				state.dt = 0.004
				G.Step(state.t) -- one capture of tile (1,0), then the budget is gone
				expect(#state.renders).to.equal(1)
				expect(tkey(state.renders[1])).to.equal("1,0")

				-- B: tx 0..4 (with margin), ty -2..2: still contains (1,0), no longer (-1,0)
				G.Request(LEVEL, 2500, 500, 600)
				expect(G.Pending()).to.equal(25)

				state.budget = 1000
				state.dt = 0
				stepAll(state)

				local order = join(renderOrder(state))
				local count10 = 0

				for i = 1, #state.renders do
					if tkey(state.renders[i]) == "1,0" then
						count10 = count10 + 1
					end

					expect(state.renders[i].tx >= 0).to.beTrue()
				end

				expect(count10).to.equal(1) -- the capture already made was kept, not redone
				expect(#state.renders).to.equal(25)
				expect(order:find("4,2", 1, true) ~= nil).to.beTrue()

				-- the work done on (1,0) (its bgra) is what the compressor received
				expect(state.compress[1].bgra).to.equal("BGRA-IMAGE-DATA-1,0")
			end
		},
		-- fails if a tile in progress that the new request does not need is still finished and stored
		{
			name = "a Request that no longer needs the tile in progress drops it",
			func = function(state)
				local G = gen()

				request25(state)
				state.budget = 1
				state.dt = 0.004
				G.Step(state.t)
				state.budget = 1000
				state.dt = 0

				G.Request(LEVEL, 50500, 500, 600)
				expect(G.Pending()).to.equal(25)
				stepAll(state)

				for i = 1, #state.stores do
					expect(tkey(state.stores[i].tile)).notTo.equal("1,0")
				end

				expect(#state.renders).to.equal(26) -- the one before, plus the 25 of the new request
				expect(#state.stores).to.equal(25)
			end
		},
		-- fails if a Step makes two captures, if the chunks are not 32 block rows exact and contiguous, or if Store does not get their concatenation
		{
			name = "Step: one capture per call, CompressRows in contiguous chunks of 32 block rows, Store gets the concatenation",
			func = function(state)
				local G = gen()

				request9(state)
				G.Step(state.t)

				expect(#state.renders).to.equal(1)
				expect(tkey(state.renders[1])).to.equal("0,0")
				-- 512 / 4 = 128 block rows = 4 chunks
				expect(#state.compress).to.equal(math.ceil(512 / 4 / 32))

				local ranges = {}

				for i = 1, #state.compress do
					local c = state.compress[i]

					ranges[i] = c.first .. "-" .. c.last
					expect(c.bgra).to.equal("BGRA-IMAGE-DATA-0,0")
					expect(c.w).to.equal(512)
					expect(c.h).to.equal(512)
				end

				expect(join(ranges)).to.equal("0-31 32-63 64-95 96-127")
				expect(#state.stores).to.equal(1)
				expect(tkey(state.stores[1].tile)).to.equal("0,0")
				expect(state.stores[1].data).to.equal("[0-31][32-63][64-95][96-127]")
				expect(G.Pending()).to.equal(8)

				-- the next call captures the next tile, once
				G.Step(state.t)
				expect(#state.renders).to.equal(2)
				expect(#state.stores).to.equal(2)
			end
		},
		-- fails if the last chunk is not shortened to the rows left, or if a size other than 512 is mishandled
		{
			name = "Step: the number of chunks follows the tile size (2048: 16 chunks; 576: a short last chunk; 64: one chunk of 16 rows)",
			func = function(state)
				local G = gen()
				local function ranges()
					local out = {}

					for i = 1, #state.compress do
						out[i] = state.compress[i].first .. "-" .. state.compress[i].last
					end

					return join(out)
				end

				state.res = 2048
				request9(state)
				G.Step(state.t)
				expect(#state.compress).to.equal(16)
				expect(state.compress[16].first .. "-" .. state.compress[16].last).to.equal("480-511")
				G.Cancel()

				state.compress = {}
				state.res = 576 -- 144 block rows = 4 chunks of 32 and one of 16
				request9(state)
				G.Step(state.t)
				expect(ranges()).to.equal("0-31 32-63 64-95 96-127 128-143")
				G.Cancel()

				state.compress = {}
				state.res = 64 -- 16 block rows
				request9(state)
				G.Step(state.t)
				expect(ranges()).to.equal("0-15")
			end
		},
		-- fails if the budget is not read from Settings.BudgetMs, if the clock is read before the first unit of work, or if the stop is not after the unit that used it up
		{
			name = "budget: 4 ms per clock reading and 6 ms of budget stop each Step after 2 units of work (capture, compress chunks, store)",
			func = function(state)
				local G = gen()

				state.budget = 6
				state.dt = 0.004
				request9(state)

				-- units of one tile: capture, 4 chunks, store = 6 units, so 3 Steps; each Step starts with elapsed 0 (now = the fake clock's value)
				state.t = 0
				G.Step(0) -- reads 4 ms (less than 6): second unit; reads 8 ms: stop
				expect(#state.renders).to.equal(1)
				expect(#state.compress).to.equal(1)
				expect(#state.stores).to.equal(0)

				state.t = 0
				G.Step(0)
				expect(#state.compress).to.equal(3)
				expect(#state.stores).to.equal(0)

				state.t = 0
				G.Step(0) -- chunk 4 then Store
				expect(#state.compress).to.equal(4)
				expect(#state.stores).to.equal(1)
				expect(#state.renders).to.equal(1)

				state.t = 0
				G.Step(0)
				expect(#state.renders).to.equal(2) -- the next tile starts: capture, chunk
				expect(#state.compress).to.equal(5)
			end
		},
		-- fails if a Step may do nothing when the budget is smaller than one unit (the generator would never finish), or if `now` is ignored
		{
			name = "budget: always at least one unit per Step; the `now` given is the start of the elapsed time",
			func = function(state)
				local G = gen()

				state.budget = 1
				state.dt = 0.004
				request9(state)

				G.Step(state.t)
				expect(#state.renders).to.equal(1)
				expect(#state.compress).to.equal(0)
				G.Step(state.t)
				expect(#state.compress).to.equal(1)

				-- the clock does not move: all the tile fits in 6 ms, unless `now` says that the Step started long ago
				G.Cancel()
				state.renders, state.compress, state.stores = {}, {}, {}
				state.budget = 6
				state.dt = 0
				request9(state)
				G.Step(state.t - 10)
				expect(#state.renders).to.equal(1)
				expect(#state.compress).to.equal(0) -- 10 s already elapsed: one unit (the capture), then stop
				G.Step(state.t)
				-- fresh start: the rest of the tile fits, and so does the next tile (this call has not made a capture yet)
				expect(#state.stores).to.equal(2)
				expect(#state.renders).to.equal(2)
			end
		},
		-- fails if a capture that returns nil (menu open) counts as a failure, or moves on to another tile
		{
			name = "a capture that returns nil is retried at the next Step, without any failure counted",
			func = function(state)
				local G = gen()
				local nils = 5

				state.onCapture = function(tile, n)
					if n <= nils then
						return nil, UNAVAILABLE
					end

					return "BGRA-IMAGE-DATA-" .. tkey(tile)
				end

				request9(state)

				for i = 1, nils do
					G.Step(state.t)
					expect(G.Progress().failed).to.equal(0)
					expect(#state.compress).to.equal(0)
				end

				expect(#state.renders).to.equal(nils) -- exactly one attempt per Step
				expect(G.Pending()).to.equal(9)

				for i = 1, nils do
					expect(tkey(state.renders[i])).to.equal("0,0")
				end

				G.Step(state.t)
				expect(#state.stores).to.equal(1)
				expect(tkey(state.stores[1].tile)).to.equal("0,0")
			end
		},
		-- fails if an error of Capture is not caught, if the tile is tried more or less than 3 times in all, or if the queue stops at the failed tile
		{
			name = "a capture that raises an error: 2 new attempts, then the tile is abandoned, counted in `failed`, and the queue goes on",
			func = function(state)
				local G = gen()

				state.onCapture = function(tile, n)
					if tile.tx == 0 and tile.ty == 0 then
						error("boom")
					end

					return "BGRA-IMAGE-DATA-" .. tkey(tile)
				end

				request9(state)
				G.Step(state.t)
				G.Step(state.t)
				expect(G.Progress().failed).to.equal(0)
				G.Step(state.t)

				expect(#state.renders).to.equal(3)
				expect(G.Progress().failed).to.equal(1)
				expect(G.Pending()).to.equal(8)
				expect(#state.stores).to.equal(0)

				G.Step(state.t)
				expect(#state.renders).to.equal(4)
				expect(tkey(state.renders[4])).to.equal("-1,0")

				stepAll(state)

				local p = G.Progress()

				expect(p.failed).to.equal(1)
				expect(p.done).to.equal(8)
				expect(p.total).to.equal(9)
				expect(p.active).to.beFalse()
				expect(#state.renders).to.equal(3 + 8)
				expect(join(state.events):find("R", 1, true)).to.beNil() -- everything wanted does not exist: no Ready
			end
		},
		-- fails if a first failure is final, or if a refused Store is not an attempt that goes back to the capture
		{
			name = "a tile that fails once is tried again and stored without being a failure; a refused Store is retried from the capture",
			func = function(state)
				local G = gen()

				state.onCapture = function(tile, n)
					if n <= 1 then
						error("flaky")
					end

					local s = "BGRA-IMAGE-DATA-" .. tkey(tile)

					state.bgras[#state.bgras + 1] = s

					return s
				end

				state.onStore = function(tile, n)
					if n == 1 then
						return false, "disk full"
					end

					return true
				end

				request9(state)
				G.Step(state.t) -- error: attempt 1
				expect(#state.renders).to.equal(1)
				G.Step(state.t) -- capture, compress, the store is refused: attempt 2
				expect(G.Progress().failed).to.equal(0)
				expect(#state.stores).to.equal(0)
				expect(state.storeCalls).to.equal(1)
				expect(#state.compress).to.equal(4)

				G.Step(state.t) -- another capture (the first image was thrown away), then the store succeeds
				expect(#state.renders).to.equal(3)
				expect(G.Progress().failed).to.equal(0)
				expect(#state.stores).to.equal(1)
				expect(tkey(state.stores[1].tile)).to.equal("0,0")
				expect(#state.compress).to.equal(8)
			end
		},
		-- fails if Progress is not what the contract says, before, during and after a request
		{
			name = "Progress: nothing before the first Request; done / total / percent / active during and after",
			func = function(state)
				local G = gen()
				local p = G.Progress()

				expect(p.done).to.equal(0)
				expect(p.total).to.equal(0)
				expect(p.active).to.beFalse()
				expect(p.failed).to.equal(0)

				state.stored["a1|0,0|512|2"] = true
				request9(state)

				p = G.Progress()
				expect(p.done).to.equal(1)
				expect(p.total).to.equal(9)
				expect(p.percent).to.equal(11) -- floor(100 / 9)
				expect(p.active).to.beTrue()
				expect(p.failed).to.equal(0)

				G.Step(state.t)
				p = G.Progress()
				expect(p.done).to.equal(2)
				expect(p.percent).to.equal(22)
				expect(math.floor(p.percent)).to.equal(p.percent) -- an integer

				stepAll(state)
				p = G.Progress()
				expect(p.done).to.equal(9)
				expect(p.total).to.equal(9)
				expect(p.percent).to.equal(100)
				expect(p.active).to.beFalse()
			end
		},
		-- fails if the Progress hook fires at every Step instead of at every change, if Ready fires more than once, or if the order is wrong
		{
			name = "hooks: Progress once per change of (done, total), then Ready once, in that order",
			func = function(state)
				local G = gen()

				state.stored["a1|0,0|512|2"] = true
				request9(state)
				expect(join(state.events)).to.equal("P 1 9")

				-- a Step that changes nothing (a nil capture) fires nothing
				state.onCapture = function() return nil, UNAVAILABLE end
				G.Step(state.t)
				G.Step(state.t)
				expect(join(state.events)).to.equal("P 1 9")

				state.onCapture = nil
				stepAll(state)
				expect(join(state.events)).to.equal("P 1 9 P 2 9 P 3 9 P 4 9 P 5 9 P 6 9 P 7 9 P 8 9 P 9 9 R")

				-- the same request again, once everything exists: nothing more
				request9(state)
				G.Step(state.t)
				expect(#state.events).to.equal(10)
			end
		},
		-- fails if a request whose tiles all exist does not announce itself, or if it still adds the work hook
		{
			name = "a Request whose tiles are all in the cache fires Progress and Ready at once and adds no hook; a new request fires Ready again",
			func = function(state)
				local G = gen()
				local before = hookSnapshot()

				for tx = -1, 1 do
					for ty = -1, 1 do
						state.stored["a1|" .. tx .. "," .. ty .. "|512|2"] = true
					end
				end

				request9(state)

				expect(join(state.events)).to.equal("P 9 9 R")
				expect(G.Pending()).to.equal(0)
				expect(G.Progress().percent).to.equal(100)

				local after = hookSnapshot()

				for k in pairs(after) do
					expect(before[k] ~= nil).to.beTrue()
				end

				-- another set, also complete
				for tx = 2, 4 do
					for ty = -1, 1 do
						state.stored["a1|" .. tx .. "," .. ty .. "|512|2"] = true
					end
				end

				G.Request(LEVEL, 3500, 500, 100)
				expect(join(state.events)).to.equal("P 9 9 R R") -- (done, total) did not change: no second Progress, but a request has its Ready
			end
		},
		-- fails if the work hook is permanent, added twice, or if another hook is added
		{
			name = "the PostRender hook is added by the first Request, removed when the queue is empty, and nothing else is added",
			func = function(state)
				local G = gen()
				local before = hookSnapshot()

				expect(before[HOOK_EVENT .. "|" .. HOOK_NAME]).to.beNil()

				request9(state)

				local during = hookSnapshot()
				local added = {}

				for k in pairs(during) do
					if before[k] == nil then
						added[#added + 1] = k
					end
				end

				for k in pairs(before) do
					expect(during[k] ~= nil).to.beTrue() -- nothing removed either
				end

				expect(join(added)).to.equal(HOOK_EVENT .. "|" .. HOOK_NAME)

				-- a second, different request does not add a second one
				G.Request(LEVEL, 5500, 500, 100)

				local during2 = hookSnapshot()

				for k, fn in pairs(during) do
					expect(during2[k]).to.equal(fn)
				end

				for k in pairs(during2) do
					expect(during[k] ~= nil).to.beTrue()
				end

				stepAll(state)

				local after = hookSnapshot()

				for k in pairs(after) do
					expect(before[k] ~= nil).to.beTrue()
				end

				for k in pairs(before) do
					expect(after[k]).to.equal(before[k])
				end

				expect(G.Pending()).to.equal(0)
			end
		},
		-- fails if the hook function does not drive Step (the work would never run)
		{
			name = "the hook function runs Step with the clock: calling it does the work",
			func = function(state)
				local G = gen()

				request9(state)

				local fn = hook.GetTable()[HOOK_EVENT][HOOK_NAME]

				expect(fn).to.beA("function")
				fn()
				expect(#state.renders).to.equal(1)
				expect(#state.stores).to.equal(1)
			end
		},
		-- fails if Cancel leaves tiles, the work in progress, the hook or the memory of the previous request
		{
			name = "Cancel empties the queue, removes the hook and leaves a clean state; Pending counts the tiles left",
			func = function(state)
				local G = gen()

				request25(state)
				expect(G.Pending()).to.equal(25)
				G.Step(state.t)
				expect(G.Pending()).to.equal(24)

				state.budget = 1
				state.dt = 0.004
				G.Step(state.t) -- a capture is now in progress
				state.budget = 1000
				state.dt = 0

				local renders = #state.renders

				G.Cancel()

				expect(G.Pending()).to.equal(0)
				expect(hook.GetTable()[HOOK_EVENT] and hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beNil()

				local p = G.Progress()

				expect(p.done).to.equal(0)
				expect(p.total).to.equal(0)
				expect(p.active).to.beFalse()
				expect(p.failed).to.equal(0)

				G.Step(state.t) -- nothing to do
				expect(#state.renders).to.equal(renders)

				-- the same request again is not taken for a repeat
				state.events = {}
				expect(request25(state)).to.beTrue()
				expect(G.Pending() > 0).to.beTrue()
				expect(hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beA("function")
				expect(state.events[1]).to.equal("P 1 25") -- the tile stored before the Cancel is in the cache
				G.Cancel()
				G.Cancel() -- twice: no error
			end
		},
		-- fails if the module keeps the BGRA string of a tile after it is compressed (a megabyte or more per tile)
		{
			name = "no memory builds up: after 3 tiles nothing in the module state holds a BGRA string (nor any long string)",
			func = function(state)
				local G = gen()

				state.res = 64
				state.onCapture = function(tile, n)
					local s = string.rep("b", 64 * 64 * 4 - 40) .. string.format("%-40s", "tile " .. tkey(tile))

					state.bgras[#state.bgras + 1] = s

					return s
				end

				request9(state)
				G.Step(state.t)
				G.Step(state.t)
				G.Step(state.t)

				expect(#state.stores).to.equal(3)
				expect(#state.bgras).to.equal(3)

				local captured = {}

				for i = 1, #state.bgras do
					captured[state.bgras[i]] = true
				end

				local seen = {}
				local found = {}

				local function scan(v, path, depth)
					if depth > 12 then
						return
					end

					if type(v) == "string" then
						if #v >= 1000 or captured[v] then
							found[#found + 1] = path
						end
					elseif type(v) == "table" and not seen[v] then
						seen[v] = true

						for k, x in pairs(v) do
							scan(k, path .. ".<key>", depth + 1)
							scan(x, path .. "." .. tostring(k), depth + 1)
						end
					end
				end

				scan(G, "Gen", 0)

				expect(join(found)).to.equal("")
			end
		},
		-- fails if the floor below is queued before the main tiles, not sorted by distance, or made with the wrong level
		{
			name = "below: the tiles of the level below come after every main tile, sorted by distance in each level, with their own level",
			func = function(state)
				local G = gen()

				expect(G.Request(LEVEL, 500, 500, 100, BELOW)).to.beTrue()
				expect(G.Pending()).to.equal(18)
				stepAll(state)

				local main, below = {}, {}

				for i = 1, #state.renders do
					local r = state.renders[i]

					if i <= 9 then
						main[#main + 1] = r.tx .. "," .. r.ty
						expect(r.level).to.equal("a1")
						expect(r.levelTable).to.equal(LEVEL)
					else
						below[#below + 1] = r.tx .. "," .. r.ty
						expect(r.level).to.equal("a0")
						expect(r.levelTable).to.equal(BELOW)
						expect(r.res).to.equal(512)
						expect(r.ppm).to.equal(2)
					end
				end

				expect(#state.renders).to.equal(18)
				expect(join(main)).to.equal(SMALL_ORDER)
				expect(join(below)).to.equal(SMALL_ORDER)
			end
		},
		-- fails if the main level loses its priority when a new request comes while below tiles are waiting
		{
			name = "below: the main level stays first when a new request arrives",
			func = function(state)
				local G = gen()

				G.Request(LEVEL, 500, 500, 100, BELOW)
				stepAll(state, 11) -- the 9 main tiles and 2 below tiles

				expect(#state.renders).to.equal(11)

				G.Request(LEVEL, 2500, 500, 100, BELOW) -- tx 1..3: tiles (2..3, y) are new for both levels

				state.renders = {}
				stepAll(state)

				local seenBelow = false

				for i = 1, #state.renders do
					if state.renders[i].level == "a0" then
						seenBelow = true
					else
						expect(seenBelow).to.beFalse() -- no main tile after a below tile
					end
				end

				expect(seenBelow).to.beTrue()
			end
		},
		-- fails if the level below is not part of the comparison of two requests
		{
			name = "below: deduplication also compares the id of the level below (none, same, other)",
			func = function(state)
				local G = gen()

				expect(request9(state)).to.beTrue()
				expect(request9(state)).to.beFalse()
				expect(G.Request(LEVEL, 500, 500, 100, nil)).to.beFalse()
				expect(G.Request(LEVEL, 500, 500, 100, BELOW)).to.beTrue()

				local has = state.hasCalls

				expect(G.Request(LEVEL, 500, 500, 100, BELOW)).to.beFalse()
				expect(G.Request(LEVEL, 500, 500, 100, {id = "a0", zlo = -300, zhi = -100})).to.beFalse() -- same id: same request
				expect(state.hasCalls).to.equal(has)
				expect(G.Request(LEVEL, 500, 500, 100, {id = "z5", zlo = 0, zhi = 1})).to.beTrue()
				expect(G.Request(LEVEL, 500, 500, 100)).to.beTrue()
				expect(G.Request(LEVEL, 500, 500, 100)).to.beFalse()
				expect(G.Request(LEVEL, 500, 500, 100, "nope")).to.beNil()
			end
		},
		-- fails if the main numbers include the level below, or if belowDone / belowTotal are wrong
		{
			name = "below: Progress describes the main level only, and gives belowDone, belowTotal, belowFailed",
			func = function(state)
				local G = gen()

				state.stored["a0|0,0|512|2"] = true
				state.stored["a0|1,1|512|2"] = true
				G.Request(LEVEL, 500, 500, 100, BELOW)

				local p = G.Progress()

				expect(p.done).to.equal(0)
				expect(p.total).to.equal(9)
				expect(p.percent).to.equal(0)
				expect(p.active).to.beTrue()
				expect(p.failed).to.equal(0)
				expect(p.belowDone).to.equal(2)
				expect(p.belowTotal).to.equal(9)
				expect(p.belowFailed).to.equal(0)

				stepAll(state, 9) -- the main level is done
				p = G.Progress()
				expect(p.done).to.equal(9)
				expect(p.percent).to.equal(100)
				expect(p.active).to.beFalse() -- the main level has nothing left, whatever the level below does
				expect(p.belowDone < 9).to.beTrue()
				expect(G.Pending() > 0).to.beTrue()

				stepAll(state)
				p = G.Progress()
				expect(p.belowDone).to.equal(9)
				expect(p.belowTotal).to.equal(9)
				expect(p.done).to.equal(9)

				-- without below
				G.Cancel()
				request9(state)
				p = G.Progress()
				expect(p.belowDone).to.equal(0)
				expect(p.belowTotal).to.equal(0)
				expect(p.belowFailed).to.equal(0)
			end
		},
		-- fails if the events concern the level below, or if BelowReady is missing, repeated or before Ready
		{
			name = "below: Progress and Ready are about the main level, BelowReady comes after Ready, once",
			func = function(state)
				local G = gen()

				G.Request(LEVEL, 500, 500, 100, BELOW)
				expect(join(state.events)).to.equal("P 0 9")

				stepAll(state)
				expect(join(state.events)).to.equal("P 0 9 P 1 9 P 2 9 P 3 9 P 4 9 P 5 9 P 6 9 P 7 9 P 8 9 P 9 9 R B")

				G.Request(LEVEL, 500, 500, 100, BELOW) -- the same request, nothing changed
				expect(#state.events).to.equal(12)

				-- everything is in the cache at once: Progress, Ready, BelowReady, in that order
				for tx = 2, 4 do
					for ty = -1, 1 do
						state.stored["a1|" .. tx .. "," .. ty .. "|512|2"] = true
						state.stored["a0|" .. tx .. "," .. ty .. "|512|2"] = true
					end
				end

				G.Cancel()
				state.events = {}
				G.Request(LEVEL, 3500, 500, 100, BELOW)
				expect(join(state.events)).to.equal("P 9 9 R B")
			end
		},
		-- fails if the tiles are compressed without the alpha option or stored without the format 20
		{
			name = "below: CompressRows gets {alpha = true} and Store gets 20, for both levels",
			func = function(state)
				local G = gen()

				G.Request(LEVEL, 500, 500, 100, BELOW)
				stepAll(state)

				expect(#state.compress).to.equal(18 * 4)

				for i = 1, #state.compress do
					expect(type(state.compress[i].opts)).to.equal("table")
					expect(state.compress[i].opts.alpha).to.beTrue()
				end

				expect(#state.stores).to.equal(18)

				for i = 1, #state.stores do
					expect(state.stores[i].format).to.equal(20)
				end
			end
		},
		-- fails if a new request without below leaves the tiles of the floor below in the queue
		{
			name = "below: a new Request without below removes the tiles of the level below that were waiting",
			func = function(state)
				local G = gen()

				G.Request(LEVEL, 500, 500, 100, BELOW)
				stepAll(state, 12) -- 9 main, 3 below

				expect(G.Pending()).to.equal(6)

				G.Request(LEVEL, 500, 500, 100)
				expect(G.Pending()).to.equal(0)
				expect(hook.GetTable()[HOOK_EVENT] and hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beNil()

				local p = G.Progress()

				expect(p.belowTotal).to.equal(0)
				expect(p.belowDone).to.equal(0)

				local renders = #state.renders

				G.Step(state.t)
				expect(#state.renders).to.equal(renders)
			end
		},
		-- fails if a tile of the floor below that has captured nothing yet stops the main level, or if a tile of it that is under way is thrown away
		{
			name = "below: a below tile not captured yet gives way to a new main tile; one under way is kept",
			func = function(state)
				local G = gen()

				for tx = -1, 1 do
					for ty = -1, 1 do
						state.stored["a1|" .. tx .. "," .. ty .. "|512|2"] = true
					end
				end

				-- 1) the capture gives nothing (menu): the below tile (0,0) is current, not captured
				state.onCapture = function() return nil, UNAVAILABLE end
				G.Request(LEVEL, 500, 500, 100, BELOW)
				G.Step(state.t)
				expect(G._state.current ~= nil and G._state.current.set).to.equal("below")

				state.onCapture = nil
				G.Request(LEVEL, 1500, 500, 100, BELOW) -- tiles tx 0..2: tx 2 is new for the main level, (0,0) is still wanted
				expect(G._state.current).to.beNil()

				G.Step(state.t)
				expect(state.renders[#state.renders].level).to.equal("a1") -- a main tile first
				G.Cancel()

				-- 2) a below tile already captured stays
				state.renders = {}

				for tx = 2, 4 do
					for ty = -1, 1 do
						state.stored["a1|" .. tx .. "," .. ty .. "|512|2"] = true
					end
				end

				G.Request(LEVEL, 500, 500, 100, BELOW)
				state.budget = 1
				state.dt = 0.004
				G.Step(state.t) -- captured, then the budget is gone
				state.budget = 1000
				state.dt = 0
				expect(#state.renders).to.equal(1)
				expect(G._state.current.set).to.equal("below")

				G.Request(LEVEL, 1500, 500, 100, BELOW)
				expect(G._state.current ~= nil and G._state.current.set).to.equal("below")
				stepAll(state)

				local count = 0

				for i = 1, #state.renders do
					if state.renders[i].level == "a0" and tkey(state.renders[i]) == "0,0" then
						count = count + 1
					end
				end

				expect(count).to.equal(1)
			end
		},
		-- fails if a failure of the level below is counted in the main level's `failed`, or stops the queue
		{
			name = "below: a failing below tile counts in belowFailed, not in failed, and the queue goes on",
			func = function(state)
				local G = gen()

				state.onCapture = function(tile, n)
					if tile.level == "a0" and tile.tx == 0 and tile.ty == 0 then
						error("boom")
					end

					return "BGRA-IMAGE-DATA-" .. tile.level .. tkey(tile)
				end

				G.Request(LEVEL, 500, 500, 100, BELOW)
				stepAll(state)

				local p = G.Progress()

				expect(p.failed).to.equal(0)
				expect(p.done).to.equal(9)
				expect(p.belowFailed).to.equal(1)
				expect(p.belowDone).to.equal(8)
				expect(p.belowTotal).to.equal(9)
				expect(#state.renders).to.equal(9 + 3 + 8)
				expect(join(state.events):find("R", 1, true) ~= nil).to.beTrue() -- the main level is ready
				expect(join(state.events):find("B", 1, true)).to.beNil() -- the level below is not
			end
		},
		-- fails if Prune is not called, called at every Request, or not called again for another map
		{
			name = "Prune: called once per map, again after the map name changes",
			func = function(state)
				local G = gen()

				game.GetMap = function() return "gen_test_map_one" end
				G.Request(LEVEL, 500, 500, 100)
				expect(state.prunes).to.equal(1)
				G.Request(LEVEL, 5500, 500, 100)
				request9(state)
				expect(state.prunes).to.equal(1)

				G.Cancel()
				G.Request(LEVEL, 500, 500, 100) -- a Cancel does not forget the map
				expect(state.prunes).to.equal(1)

				game.GetMap = function() return "gen_test_map_two" end
				G.Request(LEVEL, 500, 500, 100)
				expect(state.prunes).to.equal(2)
				G.Request(LEVEL, 9500, 500, 100)
				expect(state.prunes).to.equal(2)
			end
		},
		-- fails if an error in Prune stops the request, or if a Cache without Prune raises
		{
			name = "Prune: an error in it does not stop the request; a Cache without Prune is fine",
			func = function(state)
				local G = gen()

				game.GetMap = function() return "gen_test_map_three" end
				state.onPrune = function() error("prune failed") end

				expect(request9(state)).to.beTrue()
				expect(state.prunes).to.equal(1)
				expect(G.Pending()).to.equal(9)
				expect(hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beA("function")

				G.Cancel()
				game.GetMap = function() return "gen_test_map_four" end
				GryMod.Minimap.Cache.Prune = nil
				expect(request9(state)).to.beTrue()
				expect(G.Pending()).to.equal(9)
			end
		},
		-- fails if Trim is not called after Prune, is called without the limit of Settings, or is called again for the same map
		{
			name = "Trim: called with Settings.CacheBytes() right after Prune at the first Request of a map, and not again for that map",
			func = function(state)
				local G = gen()

				game.GetMap = function() return "gen_test_map_trim" end
				state.cacheBytes = 777000
				G.Request(LEVEL, 500, 500, 100)

				expect(join(state.calls)).to.equal("prune trim")
				expect(#state.trims).to.equal(1)
				expect(state.trims[1]).to.equal(777000)

				G.Request(LEVEL, 5500, 500, 100)
				request9(state)
				expect(join(state.calls)).to.equal("prune trim")

				game.GetMap = function() return "gen_test_map_trim_two" end
				G.Request(LEVEL, 500, 500, 100)
				expect(join(state.calls)).to.equal("prune trim prune trim")
			end
		},
		-- fails if the trim every 64 stored tiles is missing, counts a refused Store, or does not start the count again after each Trim
		{
			name = "Trim: again after every 64 tiles stored with success, the count starting again at each Trim",
			func = function(state)
				local G = gen()

				game.GetMap = function() return "gen_test_map_count" end
				G.Request(LEVEL, 500, 500, 3000) -- 9 x 9 = 81 tiles
				expect(G.Pending()).to.equal(81)
				expect(#state.trims).to.equal(1) -- the one of the first request of the map

				stepAll(state, 63)
				expect(#state.stores).to.equal(63)
				expect(#state.trims).to.equal(1)

				G.Step(state.t)
				expect(#state.stores).to.equal(64)
				expect(#state.trims).to.equal(2)
				expect(state.trims[2]).to.equal(123456)

				stepAll(state)
				expect(#state.stores).to.equal(81)
				expect(#state.trims).to.equal(2)

				-- 81 more, the same map: the count started again at the 64th tile, so the next Trim comes at the 128th (162 in all: no third one)
				G.Request(LEVEL, 20500, 500, 3000)
				stepAll(state)
				expect(#state.stores).to.equal(162)
				expect(#state.trims).to.equal(3)
			end
		},
		-- fails if a Store that is refused counts towards the 64
		{
			name = "Trim: a refused Store does not count",
			func = function(state)
				local G = gen()

				game.GetMap = function() return "gen_test_map_refused" end
				state.onStore = function() return false, "disk full" end
				G.Request(LEVEL, 500, 500, 3000)
				stepAll(state, 400)

				expect(#state.stores).to.equal(0)
				expect(state.storeCalls > 64).to.beTrue()
				expect(#state.trims).to.equal(1)
			end
		},
		-- fails if an error in Trim stops the request or the generation
		{
			name = "Trim: an error in it stops nothing, at the first request or after 64 tiles",
			func = function(state)
				local G = gen()

				game.GetMap = function() return "gen_test_map_trim_error" end
				state.onTrim = function() error("trim failed") end

				expect(G.Request(LEVEL, 500, 500, 3000)).to.beTrue()
				expect(G.Pending()).to.equal(81)
				stepAll(state)

				expect(#state.stores).to.equal(81)
				expect(#state.trims).to.equal(2)
				expect(G.Progress().failed).to.equal(0)
				expect(G.Progress().done).to.equal(81)
			end
		},
		-- fails if a Cache without Trim, or a Settings without CacheBytes, raises or is trimmed anyway
		{
			name = "Trim: a Cache without Trim or a Settings without CacheBytes is fine, and nothing is trimmed",
			func = function(state)
				local G = gen()

				game.GetMap = function() return "gen_test_map_no_trim" end
				GryMod.Minimap.Cache.Trim = nil
				expect(G.Request(LEVEL, 500, 500, 3000)).to.beTrue()
				stepAll(state)
				expect(#state.stores).to.equal(81)
				expect(#state.trims).to.equal(0)
				G.Cancel()

				GryMod.Minimap.Cache.Trim = function(bytes)
					state.trims[#state.trims + 1] = bytes
				end

				GryMod.Minimap.Settings.CacheBytes = nil
				game.GetMap = function() return "gen_test_map_no_bytes" end
				expect(G.Request(LEVEL, 20500, 500, 3000)).to.beTrue()
				stepAll(state)
				expect(#state.stores).to.equal(162)
				expect(#state.trims).to.equal(0)
			end
		},
		-- fails if an identical Request builds anything (the signature string of the first version made 80 bytes of garbage per call)
		{
			name = "an identical Request allocates nothing: 1000 of them leave the memory where it was (less than 1 KB)",
			func = function(state)
				local G = gen()

				request25(state)
				G.Request(LEVEL, 1500, 500, 600, BELOW)

				-- The compiler is off during the measure: compiled code can leave out the strings it builds and does not use twice, and the
				-- interpreter makes every one of them, so only a Request that builds nothing passes. (jit.on again right after, and in afterEach.)
				pcall(jit.off)

				-- a first round: the interpreter's own first-use allocations (tables that grow once) are not the generator's garbage
				for i = 1, 4000 do
					G.Request(LEVEL, 1500, 500, 600, BELOW)
				end

				collectgarbage("collect")
				collectgarbage("stop")

				local before = collectgarbage("count")

				for i = 1, 1000 do
					G.Request(LEVEL, 1500, 500, 600, BELOW)
				end

				local mid = collectgarbage("count")

				for i = 1, 1000 do
					G.Request(LEVEL, 1520, 480, 600, BELOW) -- the same tiles, another point
				end

				local after = collectgarbage("count")

				collectgarbage("restart")
				pcall(jit.on)

				expect(mid - before).to.beLessThan(1)
				expect(after - mid).to.beLessThan(1)
				expect(G.Request(LEVEL, 1500, 500, 600, BELOW)).to.beFalse()
				expect(G.Request(LEVEL, 1500, 500, 600)).to.beTrue() -- and the comparison still sees a difference
			end
		},
		-- fails if a tile that is all void is compressed and stored, or if StoreEmpty is not called, or if it does not count as done
		{
			name = "empty tiles: StoreEmpty instead of CompressRows and Store; the tile counts as done and fires the events",
			func = function(state)
				local G = gen()

				state.onCapture = function(tile)
					local s = "VOID-" .. tkey(tile)

					state.bgras[#state.bgras + 1] = s

					return s
				end

				state.isVoid = function(bgra) return bgra:sub(1, 5) == "VOID-" end

				request9(state)
				stepAll(state)

				expect(#state.empties).to.equal(9)
				expect(#state.compress).to.equal(0)
				expect(#state.stores).to.equal(0)
				expect(state.storeCalls).to.equal(0)
				expect(#state.voidCalls).to.equal(9)
				expect(state.voidCalls[1].bgra).to.equal("VOID-0,0")
				expect(state.voidCalls[1].w).to.equal(512)
				expect(state.voidCalls[1].h).to.equal(512)

				local t = state.empties[1]

				expect(t.level).to.equal("a1")
				expect(t.tx .. "," .. t.ty).to.equal("0,0")
				expect(t.res).to.equal(512)
				expect(t.ppm).to.equal(2)

				local p = G.Progress()

				expect(p.done).to.equal(9)
				expect(p.percent).to.equal(100)
				expect(p.active).to.beFalse()
				expect(join(state.events)).to.equal("P 0 9 P 1 9 P 2 9 P 3 9 P 4 9 P 5 9 P 6 9 P 7 9 P 8 9 P 9 9 R")
				expect(G.Pending()).to.equal(0)
				expect(hook.GetTable()[HOOK_EVENT] and hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beNil()

				-- the BGRA of the empty tile is not kept
				local seen, found = {}, {}

				local function scan(v, depth)
					if depth > 12 then
						return
					end

					if type(v) == "string" then
						if v:sub(1, 5) == "VOID-" then
							found[#found + 1] = v
						end
					elseif type(v) == "table" and not seen[v] then
						seen[v] = true

						for k, x in pairs(v) do
							scan(k, depth + 1)
							scan(x, depth + 1)
						end
					end
				end

				scan(G, 0)
				expect(join(found)).to.equal("")
			end
		},
		-- fails if the choice is not made tile by tile (a tile with one solid pixel must be stored like before)
		{
			name = "empty tiles: a tile with a solid pixel takes the normal path; the choice is made tile by tile",
			func = function(state)
				local G = gen()

				state.isVoid = function(bgra) return bgra == "BGRA-IMAGE-DATA-0,0" or bgra == "BGRA-IMAGE-DATA--1,0" end

				request9(state)
				stepAll(state)

				expect(#state.empties).to.equal(2)
				expect(#state.stores).to.equal(7)
				expect(#state.compress).to.equal(7 * 4)
				expect(G.Progress().done).to.equal(9)
				expect(G.Progress().failed).to.equal(0)

				for i = 1, #state.stores do
					local key = tkey(state.stores[i].tile)

					expect(key ~= "0,0" and key ~= "-1,0").to.beTrue()
					expect(state.stores[i].format).to.equal(20)
				end
			end
		},
		-- fails if a missing IsAllVoid or StoreEmpty raises or loses the tile
		{
			name = "empty tiles: without DXT1.IsAllVoid, or without Cache.StoreEmpty, the normal path",
			func = function(state)
				local G = gen()

				state.isVoid = function() return true end -- everything would be void
				GryMod.Minimap.DXT1.IsAllVoid = nil
				request9(state)
				stepAll(state)
				expect(#state.stores).to.equal(9)
				expect(#state.empties).to.equal(0)
				expect(G.Progress().done).to.equal(9)
				G.Cancel()

				state.stores, state.compress = {}, {}
				state.stored = {}
				GryMod.Minimap.DXT1.IsAllVoid = function(bgra, w, h) return true end
				GryMod.Minimap.Cache.StoreEmpty = nil
				request9(state)
				stepAll(state)
				expect(#state.stores).to.equal(9)
				expect(G.Progress().done).to.equal(9)
				expect(G.Progress().failed).to.equal(0)
			end
		},
		-- fails if an error in IsAllVoid, or a StoreEmpty that fails, loses the tile or counts a failure
		{
			name = "empty tiles: IsAllVoid that raises, or StoreEmpty that raises or refuses, falls back to the normal path",
			func = function(state)
				local G = gen()

				state.isVoid = function() error("no") end
				request9(state)
				stepAll(state)
				expect(#state.stores).to.equal(9)
				expect(#state.empties).to.equal(0)
				expect(G.Progress().failed).to.equal(0)
				G.Cancel()

				state.stores, state.compress, state.stored = {}, {}, {}
				state.isVoid = function() return true end
				state.onStoreEmpty = function() error("disk") end
				request9(state)
				stepAll(state)
				expect(#state.empties).to.equal(9) -- tried each time
				expect(#state.stores).to.equal(9)
				expect(G.Progress().failed).to.equal(0)
				expect(G.Progress().done).to.equal(9)
				G.Cancel()

				state.stores, state.compress, state.stored, state.empties = {}, {}, {}, {}
				state.onStoreEmpty = function() return false, "refused" end
				request9(state)
				stepAll(state)
				expect(#state.empties).to.equal(9)
				expect(#state.stores).to.equal(9)
				expect(G.Progress().failed).to.equal(0)
			end
		},
		-- fails if the level below does not get the same treatment, or if its empty tiles count as done of the main level
		{
			name = "empty tiles: the level below is handled the same way (belowDone, BelowReady)",
			func = function(state)
				local G = gen()

				state.onCapture = function(tile)
					local s = (tile.level == "a0" and "VOID-" or "BGRA-") .. tkey(tile)

					return s
				end

				state.isVoid = function(bgra) return bgra:sub(1, 5) == "VOID-" end

				G.Request(LEVEL, 500, 500, 100, BELOW)
				stepAll(state)

				expect(#state.empties).to.equal(9)

				for i = 1, #state.empties do
					expect(state.empties[i].level).to.equal("a0")
				end

				expect(#state.stores).to.equal(9)

				local p = G.Progress()

				expect(p.done).to.equal(9)
				expect(p.belowDone).to.equal(9)
				expect(p.belowTotal).to.equal(9)
				expect(p.failed).to.equal(0)
				expect(p.belowFailed).to.equal(0)
				expect(join(state.events):sub(-9)).to.equal("P 9 9 R B")
			end
		},
		-- fails if the maintenance counter counts the empty tiles
		{
			name = "empty tiles do not count for the Trim every 64 stored tiles",
			func = function(state)
				local G = gen()

				game.GetMap = function() return "gen_test_map_empty_trim" end

				state.isVoid = function(bgra) return bgra:find(",%-3$") ~= nil or bgra:find(",%-4$") ~= nil end

				G.Request(LEVEL, 500, 500, 3000) -- 81 tiles, 18 of them in the two rows ty = -4 and -3
				stepAll(state)

				expect(#state.empties).to.equal(18)
				expect(#state.stores).to.equal(63)
				expect(#state.trims).to.equal(1) -- only the first one: 63 real Stores are not 64
				expect(G.Progress().done).to.equal(81)
			end
		},
		-- fails if a permanent capture error is retried for ever as if the menu were open
		{
			name = "capture nil with another reason than \"capture unavailable\": 3 attempts, then `failed`, the queue goes on and the hook goes away",
			func = function(state)
				local G = gen()

				state.onCapture = function(tile)
					if tile.tx == 0 and tile.ty == 0 then
						return nil, "render target unavailable"
					end

					return "BGRA-IMAGE-DATA-" .. tkey(tile)
				end

				request9(state)
				G.Step(state.t)
				G.Step(state.t)
				expect(G.Progress().failed).to.equal(0)
				G.Step(state.t)

				expect(#state.renders).to.equal(3)
				expect(G.Progress().failed).to.equal(1)
				expect(G.Pending()).to.equal(8)

				stepAll(state)

				local p = G.Progress()

				expect(p.failed).to.equal(1)
				expect(p.done).to.equal(8)
				expect(#state.renders).to.equal(3 + 8)
				expect(G.Pending()).to.equal(0)
				expect(hook.GetTable()[HOOK_EVENT] and hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beNil()

				-- no reason at all is not "unavailable" either
				G.Cancel()
				state.renders = {}
				state.stored = {}
				state.onCapture = function() return nil end
				request9(state)
				stepAll(state, 40)
				expect(G.Pending()).to.equal(0)
				expect(G.Progress().failed).to.equal(9)
			end
		},
		-- fails if an error in a handler of the events stops the generation or the sticking of the hook
		{
			name = "an error in a handler of Progress, Ready or BelowReady does not stop the generation",
			func = function(state)
				local G = gen()

				hook.Add("GryMod_MinimapProgress", LISTENER .. "_raiser", function() error("handler of Progress") end)
				hook.Add("GryMod_MinimapReady", LISTENER .. "_raiser", function() error("handler of Ready") end)
				hook.Add("GryMod_MinimapBelowReady", LISTENER .. "_raiser", function() error("handler of BelowReady") end)

				expect(G.Request(LEVEL, 500, 500, 100, BELOW)).to.beTrue()
				expect(hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beA("function")
				expect(G.Pending()).to.equal(18)

				stepAll(state)

				local p = G.Progress()

				expect(p.done).to.equal(9)
				expect(p.belowDone).to.equal(9)
				expect(#state.stores).to.equal(18)
				expect(G.Pending()).to.equal(0)
				expect(G.Request(LEVEL, 500, 500, 100, BELOW)).to.beFalse() -- the request was recorded
			end
		},
		-- fails if the limit of the number of tiles is Gen's own, or if a refused request changes the previous one
		{
			name = "too many tiles: the limit is View.MAX_TILES (400 without View); the request is refused and the previous one stays",
			func = function(state)
				local G = gen()

				GryMod.Minimap.View = {MAX_TILES = 30}
				expect(request25(state)).to.beTrue()

				local ok, err = G.Request(LEVEL, 500, 500, 3000) -- 81 tiles

				expect(ok).to.beNil()
				expect(err).to.equal("too many tiles")
				expect(G.Pending()).to.equal(25)
				expect(G.Progress().total).to.equal(25)
				expect(request25(state)).to.beFalse() -- the previous request is still the one in force
				expect(G.Request(LEVEL, 500, 500, 3000)).to.beNil() -- and the refused one is not remembered

				G.Cancel()
				GryMod.Minimap.View = nil -- the limit is then 400: 19 x 19 = 361 tiles pass, 21 x 21 = 441 do not
				expect(G.Request(LEVEL, 500, 500, 8000)).to.beTrue()
				expect(G.Progress().total).to.equal(361)
				ok, err = G.Request(LEVEL, 500, 500, 9000)
				expect(ok).to.beNil()
				expect(err).to.equal("too many tiles")
				expect(G.Progress().total).to.equal(361)
			end
		},
		-- fails if a Trim that removed tiles does not make the next request count the tiles again
		{
			name = "a Trim that removed something makes the next identical Request recount; a Trim that removed nothing does not",
			func = function(state)
				local G = gen()

				game.GetMap = function() return "gen_test_map_trim_removed" end
				G.Request(LEVEL, 500, 500, 3000)
				stepAll(state, 63)
				expect(#state.trims).to.equal(1)

				state.trimRemoved = 0
				G.Step(state.t) -- the 64th tile: Trim removes nothing
				expect(#state.trims).to.equal(2)
				expect(G.Request(LEVEL, 500, 500, 3000)).to.beFalse()

				stepAll(state) -- the 81 tiles are done
				expect(#state.stores).to.equal(81)

				-- 81 more tiles in another place: the next Trim comes at the 128th tile in all
				expect(G.Request(LEVEL, 20500, 500, 3000)).to.beTrue()
				stepAll(state, 46)
				expect(#state.stores).to.equal(127)
				expect(#state.trims).to.equal(2)
				state.trimRemoved = 7
				G.Step(state.t)
				expect(#state.trims).to.equal(3)
				state.stored["a1|20,0|512|2"] = nil -- the Trim removed this one from the disk
				state.hasCalls = 0
				expect(G.Request(LEVEL, 20500, 500, 3000)).to.beTrue()
				expect(state.hasCalls > 0).to.beTrue()
				expect(G.Pending() >= 1).to.beTrue()
				expect(G.Request(LEVEL, 20500, 500, 3000)).to.beFalse() -- recounted once, then the same again
			end
		},
		-- fails if the answer of the real Cache.Trim ({removed = n, bytes = n}, not a number) is not understood: the next request would not recount the tiles the Trim removed
		{
			name = "a Trim that answers like the real one ({removed, bytes}) makes the next identical Request recount when it removed tiles, and not when it removed none",
			func = function(state)
				local G = gen()

				state.trimAnswersTable = true
				game.GetMap = function() return "gen_test_map_trim_table" end
				G.Request(LEVEL, 500, 500, 3000)
				stepAll(state, 63)
				expect(#state.trims).to.equal(1)

				state.trimRemoved = 0
				G.Step(state.t) -- the 64th tile: Trim removes nothing
				expect(G.Request(LEVEL, 500, 500, 3000)).to.beFalse()

				stepAll(state) -- the 81 tiles are done
				expect(G.Request(LEVEL, 20500, 500, 3000)).to.beTrue()
				stepAll(state, 46)
				state.trimRemoved = 7
				G.Step(state.t) -- the 128th tile: Trim removes 7
				state.stored["a1|20,0|512|2"] = nil
				expect(G.Request(LEVEL, 20500, 500, 3000)).to.beTrue()
				expect(G.Request(LEVEL, 20500, 500, 3000)).to.beFalse()
			end
		},
		-- fails if the preload keeps making tiles after the cache began to throw tiles away (the cache is full): each tile made would push another one out, and the generator would
		-- work at every frame for nothing (seen on gm_boreas with a limit of 256 MB: 7 ms a frame for ever)
		{
			name = "preload: a Trim that removed tiles ends the preload (the cache is full) and says so; a Trim that removed nothing does not",
			func = function(state)
				local G = gen()
				local P1 = {id = "open_t960", open = true, zlo = -100, zhi = 960}
				local entries = {}

				state.trimAnswersTable = true
				game.GetMap = function() return "gen_test_map_preload_full" end

				for i = 1, 200 do
					entries[i] = {tile = {level = P1.id, tx = i, ty = 0, res = 512, ppm = 2}, level = P1, d = i}
				end

				G.SetPreload(entries)
				expect(G.PreloadProgress().cut).to.beFalse()

				-- 63 tiles, then the 64th: the Trim removes nothing, the preload goes on
				state.trimRemoved = 0
				stepAll(state, 64)
				expect(#state.trims >= 1).to.beTrue()
				expect(G.PreloadProgress().cut).to.beFalse()
				expect(G.Pending() > 0).to.beTrue()

				-- the next Trim removes tiles: the rest of the preload is dropped, nothing waits any more, and the progress says it was cut
				state.trimRemoved = 5
				stepAll(state, 64)
				expect(G.PreloadProgress().cut).to.beTrue()
				expect(G.Pending()).to.equal(0)
				expect(#state.stores < 200).to.beTrue()
			end
		},
		-- fails if an abandoned tile is never tried again, or is tried again at once
		{
			name = "an abandoned tile is tried again by a changed request, or by an identical one 30 seconds after the failure",
			func = function(state)
				local G = gen()
				local fails = true

				state.onCapture = function(tile)
					if fails and tile.tx == 0 and tile.ty == 0 then
						error("boom")
					end

					return "BGRA-IMAGE-DATA-" .. tkey(tile)
				end

				request9(state)
				stepAll(state)
				expect(G.Progress().failed).to.equal(1)
				expect(G.Progress().done).to.equal(8)

				-- at once, or 29 seconds later: nothing
				expect(request9(state)).to.beFalse()
				state.rt = state.rt + 29
				expect(request9(state)).to.beFalse()
				expect(G.Pending()).to.equal(0)

				-- 30 seconds after the failure: the tile is asked for again, and this time it works
				fails = false
				state.rt = state.rt + 1
				expect(request9(state)).to.beTrue()
				expect(G.Pending()).to.equal(1)
				stepAll(state)
				expect(G.Progress().done).to.equal(9)
				expect(G.Progress().failed).to.equal(0)
				expect(request9(state)).to.beFalse()
				state.rt = state.rt + 100
				expect(request9(state)).to.beFalse() -- nothing failed this time: no periodic redo

				-- a changed request also asks again
				G.Cancel()
				state.stored = {}
				fails = true
				request9(state)
				stepAll(state)
				expect(G.Progress().failed).to.equal(1)
				fails = false
				expect(G.Request(LEVEL, 500, 600, 100)).to.beFalse() -- same tiles: same request
				expect(G.Request(LEVEL, 1500, 500, 100)).to.beTrue()
				expect(G.Pending() >= 3).to.beTrue() -- the new column, and the tile (0,0) is still wanted
				stepAll(state)
				expect(G.Progress().failed).to.equal(0)
				expect(state.stored["a1|0,0|512|2"]).to.beTrue()
			end
		},
		-- fails if a missing or absurd tile size raises or is accepted
		{
			name = "no tile size: TileUnits that gives nil, 0, a negative, infinity or NaN makes Request answer nil, \"no tile size\"",
			func = function(state)
				local G = gen()

				for _, bad in ipairs({"nil", 0, -5, math.huge, 0 / 0}) do
					state.tileUnits = bad ~= "nil" and bad or nil
					GryMod.Minimap.Cache.TileUnits = function() return state.tileUnits end

					local ok, err = G.Request(LEVEL, 500, 500, 100)

					expect(ok).to.beNil()
					expect(err).to.equal("no tile size")
					expect(G.Pending()).to.equal(0)
					expect(hook.GetTable()[HOOK_EVENT] and hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beNil()
				end
			end
		},
		-- fails if the outside is queued before the floor below or before a main tile, not sorted by distance, or made with the wrong level
		{
			name = "outside: its tiles come after every main tile and every below tile, sorted by distance, with their own level",
			func = function(state)
				local G = gen()

				expect(G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)).to.beTrue()
				expect(G.Pending()).to.equal(27)
				stepAll(state)

				local order, outside = {}, {}

				for i = 1, #state.renders do
					local r = state.renders[i]

					order[i] = r.level

					if r.level == "open" then
						outside[#outside + 1] = r.tx .. "," .. r.ty
						expect(r.levelTable).to.equal(OUTSIDE)
						expect(r.res).to.equal(512)
						expect(r.ppm).to.equal(2)
					end
				end

				expect(#state.renders).to.equal(27)
				expect(join(order)).to.equal(string.rep("a1 ", 9) .. string.rep("a0 ", 9) .. string.rep("open ", 8) .. "open")
				expect(join(outside)).to.equal(SMALL_ORDER)
			end
		},
		-- fails if the outside needs a floor below, or is dropped when there is none
		{
			name = "outside: without a floor below the outside comes right after the main level",
			func = function(state)
				local G = gen()

				expect(G.Request(LEVEL, 500, 500, 100, nil, OUTSIDE)).to.beTrue()
				expect(G.Pending()).to.equal(18)
				stepAll(state)

				for i = 1, 18 do
					expect(state.renders[i].level).to.equal(i <= 9 and "a1" or "open")
				end

				local p = G.Progress()

				expect(p.belowTotal).to.equal(0)
				expect(p.outsideTotal).to.equal(9)
				expect(p.outsideDone).to.equal(9)
			end
		},
		-- fails if the id of the outside is not part of the comparison of two requests, or an outside of the same id as another level is kept
		{
			name = "outside: deduplication compares the id of the outside (none, same, other); an outside with the id of the main level or of the floor below is no outside",
			func = function(state)
				local G = gen()

				expect(G.Request(LEVEL, 500, 500, 100, BELOW)).to.beTrue()
				expect(G.Request(LEVEL, 500, 500, 100, BELOW, nil)).to.beFalse()
				expect(G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)).to.beTrue()

				local has = state.hasCalls

				expect(G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)).to.beFalse()
				expect(G.Request(LEVEL, 500, 500, 100, BELOW, {id = "open", zlo = 1, zhi = 2})).to.beFalse() -- same id: same request
				expect(state.hasCalls).to.equal(has)
				expect(G.Request(LEVEL, 500, 500, 100, BELOW, {id = "z9", zlo = 0, zhi = 1})).to.beTrue()
				expect(G.Request(LEVEL, 500, 500, 100, BELOW)).to.beTrue() -- the outside goes away: another request
				expect(G.Request(LEVEL, 500, 500, 100, BELOW)).to.beFalse()

				-- the same id as the main level, or as the floor below: no outside at all
				G.Cancel()
				expect(G.Request(LEVEL, 500, 500, 100, BELOW, {id = "a1", zlo = 0, zhi = 1})).to.beTrue()
				expect(G.Progress().outsideTotal).to.equal(0)
				expect(G.Pending()).to.equal(18)
				expect(G.Request(LEVEL, 500, 500, 100, BELOW, {id = "a0", zlo = 0, zhi = 1})).to.beFalse()
				expect(G.Progress().outsideTotal).to.equal(0)
				expect(G.Request(LEVEL, 500, 500, 100, BELOW)).to.beFalse() -- the very same request

				-- a bad outside is refused and changes nothing
				for _, bad in ipairs({"nope", 5, {}, {id = 7}}) do
					local ok, err = G.Request(LEVEL, 500, 500, 100, BELOW, bad)

					expect(ok).to.beNil()
					expect(isstring(err)).to.beTrue()
				end

				expect(G.Request(LEVEL, 500, 500, 100, BELOW)).to.beFalse()
			end
		},
		-- fails if Progress mixes the outside with the main level, or lacks outsideDone / outsideTotal / outsideFailed
		{
			name = "outside: Progress describes the main level only, and gives outsideDone, outsideTotal, outsideFailed (0 without outside)",
			func = function(state)
				local G = gen()

				state.stored["open|0,0|512|2"] = true
				state.stored["open|1,1|512|2"] = true
				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)

				local p = G.Progress()

				expect(p.done).to.equal(0)
				expect(p.total).to.equal(9)
				expect(p.percent).to.equal(0)
				expect(p.failed).to.equal(0)
				expect(p.belowDone).to.equal(0)
				expect(p.belowTotal).to.equal(9)
				expect(p.outsideDone).to.equal(2)
				expect(p.outsideTotal).to.equal(9)
				expect(p.outsideFailed).to.equal(0)

				stepAll(state, 18) -- the main level and the floor below
				p = G.Progress()
				expect(p.done).to.equal(9)
				expect(p.active).to.beFalse()
				expect(p.belowDone).to.equal(9)
				expect(p.outsideDone).to.equal(2)
				expect(G.Pending()).to.equal(7)

				stepAll(state)
				p = G.Progress()
				expect(p.done).to.equal(9)
				expect(p.total).to.equal(9)
				expect(p.outsideDone).to.equal(9)
				expect(p.outsideTotal).to.equal(9)

				G.Cancel()
				request9(state)
				p = G.Progress()
				expect(p.outsideDone).to.equal(0)
				expect(p.outsideTotal).to.equal(0)
				expect(p.outsideFailed).to.equal(0)
			end
		},
		-- fails if the event of the outside is missing, repeated, before Ready, or if it changes the other events
		{
			name = "outside: Progress and Ready are about the main level, then BelowReady, then OutsideReady once, in that order",
			func = function(state)
				local G = gen()

				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)
				expect(join(state.events)).to.equal("P 0 9")

				stepAll(state)
				expect(join(state.events)).to.equal("P 0 9 P 1 9 P 2 9 P 3 9 P 4 9 P 5 9 P 6 9 P 7 9 P 8 9 P 9 9 R B O")

				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE) -- the same request
				expect(#state.events).to.equal(13)

				-- everything is in the cache at once
				for tx = 2, 4 do
					for ty = -1, 1 do
						for _, id in ipairs({"a1", "a0", "open"}) do
							state.stored[id .. "|" .. tx .. "," .. ty .. "|512|2"] = true
						end
					end
				end

				G.Cancel()
				state.events = {}
				G.Request(LEVEL, 3500, 500, 100, BELOW, OUTSIDE)
				expect(join(state.events)).to.equal("P 9 9 R B O")

				-- an outside without a floor below
				G.Cancel()
				state.events = {}
				state.stored = {}
				G.Request(LEVEL, 500, 500, 100, nil, OUTSIDE)
				stepAll(state)
				expect(join(state.events):sub(-9)).to.equal("P 9 9 R O")
			end
		},
		-- fails if the tiles of the outside are not compressed with the alpha option and stored in the format 20
		{
			name = "outside: CompressRows gets {alpha = true} and Store gets 20 for the three levels",
			func = function(state)
				local G = gen()

				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)
				stepAll(state)

				expect(#state.compress).to.equal(27 * 4)

				for i = 1, #state.compress do
					expect(state.compress[i].opts.alpha).to.beTrue()
				end

				expect(#state.stores).to.equal(27)

				for i = 1, #state.stores do
					expect(state.stores[i].format).to.equal(20)
				end
			end
		},
		-- fails if a new request without outside leaves its tiles in the queue
		{
			name = "outside: a new Request without outside removes the tiles of the outside that were waiting",
			func = function(state)
				local G = gen()

				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)
				stepAll(state, 21) -- 9 main, 9 below, 3 outside

				expect(G.Pending()).to.equal(6)

				G.Request(LEVEL, 500, 500, 100, BELOW)
				expect(G.Pending()).to.equal(0)
				expect(hook.GetTable()[HOOK_EVENT] and hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beNil()
				expect(G.Progress().outsideTotal).to.equal(0)
				expect(G.Progress().outsideDone).to.equal(0)

				local renders = #state.renders

				G.Step(state.t)
				expect(#state.renders).to.equal(renders)
			end
		},
		-- fails if a new main tile has to wait for an outside tile that has not been captured yet, or an outside tile under way is thrown away
		{
			name = "outside: an outside tile not captured yet gives way to a new main tile and to a below tile; one under way is kept",
			func = function(state)
				local G = gen()

				for tx = -1, 1 do
					for ty = -1, 1 do
						state.stored["a1|" .. tx .. "," .. ty .. "|512|2"] = true
						state.stored["a0|" .. tx .. "," .. ty .. "|512|2"] = true
					end
				end

				-- 1) the capture gives nothing (menu): the outside tile (0,0) is current, not captured
				state.onCapture = function() return nil, UNAVAILABLE end
				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)
				G.Step(state.t)
				expect(G._state.current ~= nil and G._state.current.set).to.equal("outside")

				state.onCapture = nil
				G.Request(LEVEL, 1500, 500, 100, BELOW, OUTSIDE) -- tx 0..2: tx 2 is new for the three levels, (0,0) is still wanted
				expect(G._state.current).to.beNil()

				G.Step(state.t)
				expect(state.renders[#state.renders].level).to.equal("a1") -- a main tile first
				G.Cancel()

				-- 2) an outside tile already captured stays
				state.renders = {}

				for tx = 2, 4 do
					for ty = -1, 1 do
						state.stored["a1|" .. tx .. "," .. ty .. "|512|2"] = true
						state.stored["a0|" .. tx .. "," .. ty .. "|512|2"] = true
					end
				end

				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)
				state.budget = 1
				state.dt = 0.004
				G.Step(state.t) -- captured, then the budget is gone
				state.budget = 1000
				state.dt = 0
				expect(#state.renders).to.equal(1)
				expect(G._state.current.set).to.equal("outside")

				G.Request(LEVEL, 1500, 500, 100, BELOW, OUTSIDE)
				expect(G._state.current ~= nil and G._state.current.set).to.equal("outside")
				stepAll(state)

				local count = 0

				for i = 1, #state.renders do
					if state.renders[i].level == "open" and tkey(state.renders[i]) == "0,0" then
						count = count + 1
					end
				end

				expect(count).to.equal(1)
			end
		},
		-- fails if a failure of the outside is counted in `failed` or `belowFailed`, stops the queue, or fires OutsideReady
		{
			name = "outside: a failing outside tile counts in outsideFailed only, the queue goes on, and OutsideReady is not fired",
			func = function(state)
				local G = gen()

				state.onCapture = function(tile)
					if tile.level == "open" and tile.tx == 0 and tile.ty == 0 then
						error("boom")
					end

					return "BGRA-IMAGE-DATA-" .. tile.level .. tkey(tile)
				end

				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)
				stepAll(state)

				local p = G.Progress()

				expect(p.failed).to.equal(0)
				expect(p.belowFailed).to.equal(0)
				expect(p.done).to.equal(9)
				expect(p.belowDone).to.equal(9)
				expect(p.outsideFailed).to.equal(1)
				expect(p.outsideDone).to.equal(8)
				expect(p.outsideTotal).to.equal(9)
				expect(#state.renders).to.equal(9 + 9 + 3 + 8)
				expect(join(state.events):find("B", 1, true) ~= nil).to.beTrue()
				expect(join(state.events):find("O", 1, true)).to.beNil()
				expect(G.Pending()).to.equal(0)
				expect(hook.GetTable()[HOOK_EVENT] and hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beNil()

				-- 30 seconds later an identical request asks for the abandoned tile again
				state.onCapture = nil
				state.rt = state.rt + 30
				expect(G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)).to.beTrue()
				expect(G.Pending()).to.equal(1)
				stepAll(state)
				expect(G.Progress().outsideDone).to.equal(9)
				expect(G.Progress().outsideFailed).to.equal(0)
				expect(join(state.events):sub(-5)).to.equal("R B O")
			end
		},
		-- fails if the empty tiles of the outside are compressed and stored, or do not count in outsideDone
		{
			name = "outside: empty tiles are handled the same way (StoreEmpty, outsideDone, OutsideReady)",
			func = function(state)
				local G = gen()

				state.onCapture = function(tile)
					return (tile.level == "open" and "VOID-" or "BGRA-") .. tkey(tile)
				end

				state.isVoid = function(bgra) return bgra:sub(1, 5) == "VOID-" end

				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)
				stepAll(state)

				expect(#state.empties).to.equal(9)

				for i = 1, #state.empties do
					expect(state.empties[i].level).to.equal("open")
				end

				expect(#state.stores).to.equal(18)

				local p = G.Progress()

				expect(p.done).to.equal(9)
				expect(p.outsideDone).to.equal(9)
				expect(p.outsideFailed).to.equal(0)
				expect(join(state.events):sub(-11)).to.equal("P 9 9 R B O")
			end
		},
		-- the background of the engine for "nothing" (alpha 255; black here: (0, 0, 0, 255) where the slab of the floor below or of the outside is inside solid earth) -------
		-- Pictures of 64 x 64 pixels (st.res = 64), one 16-row chunk per tile: the real Capture.FindBackground / BackgroundToVoid / IsAllBackground and the real DXT1.IsAllVoid run on them.
		-- fails if the opaque black of a tile is compressed as it is (a tile is stored under the name of its level, whatever set asked for it first: the main level of today is the
		-- floor below of tomorrow, and its black would be drawn as a solid wall over the outside), or if a coloured pixel, a pixel of black geometry (alpha 1) is touched
		{
			name = "background (black fill): the tiles of the main level, of the floor below and of the outside get their opaque black turned into void before the compression",
			func = function(state)
				local G = gen()

				useFill(state)
				state.res = 64

				state.onCapture = function(tile)
					local s = fillPicture(tile.tx)

					state.bgras[#state.bgras + 1] = s

					return s
				end

				G.Request(LEVEL, 500, 500, 100, BELOW)
				stepAll(state)

				expect(#state.compress).to.equal(18)

				for i = 1, #state.renders do
					local r = state.renders[i]
					local sent = state.compress[i].bgra

					expect(r.level == "a1" or r.level == "a0").to.beTrue()
					expect(sent == fillExpected(r.tx)).to.beTrue() -- the main level as well as the floor below
					expect(sent == fillPicture(r.tx)).to.beFalse()
				end

				expect(#state.empties).to.equal(0)
				expect(G.Progress().belowDone).to.equal(9)
				expect(G.Progress().done).to.equal(9)
			end
		},
		-- fails if the outside is left out of the rule (it is drawn under everything: its opaque black would hide nothing less than the whole picture)
		{
			name = "background (black fill): the tiles of the outside get the same treatment (all three sets, the outside included)",
			func = function(state)
				local G = gen()

				useFill(state)
				state.res = 64

				state.onCapture = function(tile)
					return fillPicture(tile.tx)
				end

				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)
				stepAll(state)

				expect(#state.compress).to.equal(27)

				for i = 1, #state.renders do
					expect(state.compress[i].bgra == fillExpected(state.renders[i].tx)).to.beTrue()
				end

				expect(G.Progress().outsideDone).to.equal(9)
			end
		},
		-- the fill of a map is not always black (gm_boreas: a sky blue that drifts with the time, read from the picture): its colour is void, the other opaque pixels stay
		-- fails if only black is turned into void (the blue stays a solid wall over what is behind), or if the dark opaque pixel that is not the fill is erased too
		{
			name = "background: a tile whose fill is blue gets that blue turned into void in the three sets; an opaque black pixel that is not the fill stays",
			func = function(state)
				local G = gen()

				useFill(state)
				state.res = 64

				state.onCapture = function(tile)
					return bluePicture(tile.tx)
				end

				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)
				stepAll(state)

				expect(#state.compress).to.equal(27)

				for i = 1, #state.renders do
					local sent = state.compress[i].bgra

					expect(sent == blueExpected(state.renders[i].tx)).to.beTrue()
					expect(sent == bluePicture(state.renders[i].tx)).to.beFalse()
				end

				expect(#state.empties).to.equal(0)
			end
		},
		-- fails if a tile that is nothing but a blue fill is stored as a file, in a set that is changed pixel by pixel or in one that is left out
		{
			name = "background: a tile that is nothing but the blue fill is an empty tile (StoreEmpty, no compression); also in a set left out of VOID_FILL_SETS",
			func = function(state)
				local G = gen()

				useFill(state)
				state.res = 64
				state.isVoid = function(bgra, w, h) return saved.DXT1.IsAllVoid(bgra, w, h) end

				state.onCapture = function(tile)
					if tile.level == "a1" and tile.tx == 0 and tile.ty == 0 then
						return bluePicture(tile.tx) -- some content
					end

					return string.rep(BLUE_K, 64 * 64)
				end

				G.VOID_FILL_SETS.main = false -- the main level is compressed as it is, except a tile of nothing but the fill
				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)
				stepAll(state)

				expect(#state.empties).to.equal(26)
				expect(#state.compress).to.equal(1)
				expect(state.compress[1].bgra == bluePicture(0)).to.beTrue()
				expect(G.Progress().done).to.equal(9)
				expect(G.Progress().belowDone).to.equal(9)
				expect(G.Progress().outsideDone).to.equal(9)
			end
		},
		-- fails if a picture that has no fill (nothing found: FindBackground gives nil) is left as it is instead of getting the rule with the black, which the engine's black needs
		{
			name = "background: when FindBackground finds no fill the black is the fill, as before (a black tile with a few other pixels)",
			func = function(state)
				local G = gen()

				useFill(state)
				state.res = 64

				-- 3 pixels of the fill and nothing else: below the minimum of samples, so FindBackground says nil
				local few = string.rep("\0\0\0\1", 64 * 64 - 3) .. string.rep(FILL_K, 3)

				expect(saved.Capture.FindBackground(few)).to.beNil()

				state.onCapture = function()
					return few
				end

				request9(state)
				stepAll(state)
				expect(#state.compress).to.equal(9)
				expect(state.compress[1].bgra == string.rep("\0\0\0\1", 64 * 64 - 3) .. string.rep(FILL_V, 3)).to.beTrue()
			end
		},
		-- fails if a tile of the floor below that is only opaque black is stored as a file (the whole picture is "nothing": it is an empty tile), or if it is not counted as done
		{
			name = "background (black fill): a tile of the floor below or of the outside that is all opaque black is an empty tile (StoreEmpty, no compression), counted as done",
			func = function(state)
				local G = gen()

				useFill(state)
				state.res = 64
				state.isVoid = function(bgra, w, h) return saved.DXT1.IsAllVoid(bgra, w, h) end

				state.onCapture = function(tile)
					if tile.level == "a1" then
						return fillPicture(tile.tx) -- the main level has some content
					end

					return string.rep(FILL_K, 64 * 64)
				end

				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)
				stepAll(state)

				expect(#state.empties).to.equal(18)

				for i = 1, #state.empties do
					expect(state.empties[i].level == "a0" or state.empties[i].level == "open").to.beTrue()
				end

				expect(#state.stores).to.equal(9)
				expect(#state.compress).to.equal(9)

				local p = G.Progress()

				expect(p.done).to.equal(9)
				expect(p.belowDone).to.equal(9)
				expect(p.outsideDone).to.equal(9)
				expect(join(state.events):sub(-11)).to.equal("P 9 9 R B O")
			end
		},
		-- fails if a main tile that is only opaque black is stored as a file, or if a main tile with a single other pixel is emptied, or loses that pixel
		{
			name = "background (black fill): a tile of the main level that is entirely opaque black is an empty tile; one other pixel keeps it a normal tile with that pixel",
			func = function(state)
				local G = gen()

				useFill(state)
				state.res = 64
				state.isVoid = function(bgra, w, h) return saved.DXT1.IsAllVoid(bgra, w, h) end

				local almost = string.rep(FILL_K, 64 * 64 - 1) .. "\0\0\0\1" -- one pixel of black geometry (alpha 1)

				state.onCapture = function(tile)
					if tile.tx == 0 and tile.ty == 0 then
						return almost
					end

					return string.rep(FILL_K, 64 * 64)
				end

				request9(state)
				stepAll(state)

				expect(#state.empties).to.equal(8)
				expect(#state.stores).to.equal(1)
				expect(#state.compress).to.equal(1)
				expect(state.compress[1].bgra == string.rep(FILL_V, 64 * 64 - 1) .. "\0\0\0\1").to.beTrue() -- the black geometry stays, the rest is void
				expect(G.Progress().done).to.equal(9)
				expect(G.Progress().failed).to.equal(0)
			end
		},
		-- fails if the table of the sets is not read (the main level is changed pixel by pixel whatever it says), or if the all-opaque-black tile of a set that is left out is kept as a file
		{
			name = "background (black fill): Gen.VOID_FILL_SETS decides which sets are changed pixel by pixel; a set left out is compressed as it is, except a tile that is nothing but opaque black",
			func = function(state)
				local G = gen()

				useFill(state)
				state.res = 64
				state.isVoid = function(bgra, w, h) return saved.DXT1.IsAllVoid(bgra, w, h) end

				expect(type(G.VOID_FILL_SETS)).to.equal("table")
				expect(G.VOID_FILL_SETS.main).to.equal(true)
				expect(G.VOID_FILL_SETS.below).to.equal(true)
				expect(G.VOID_FILL_SETS.outside).to.equal(true)

				G.VOID_FILL_SETS.main = false

				state.onCapture = function(tile)
					if tile.tx == 0 and tile.ty == 0 then
						return fillPicture(tile.tx) -- some content: stays as it is in the main level
					end

					return string.rep(FILL_K, 64 * 64)
				end

				G.Request(LEVEL, 500, 500, 100, BELOW)
				stepAll(state)

				-- the main level: 8 tiles of nothing but opaque black are empty, the one with content is compressed untouched
				-- the floor below: the same pictures, every opaque black pixel is void (8 empty tiles, one compressed with its content changed)
				expect(#state.empties).to.equal(16)
				expect(#state.compress).to.equal(2)

				for i = 1, #state.renders do
					if state.renders[i].tx == 0 and state.renders[i].ty == 0 then
						local sent = state.compress[state.renders[i].level == "a1" and 1 or 2].bgra

						if state.renders[i].level == "a1" then
							expect(sent == fillPicture(0)).to.beTrue()
						else
							expect(sent == fillExpected(0)).to.beTrue()
						end
					end
				end
			end
		},
		-- fails if the picture before the change, or the one after it, is kept in the state of the generator once the tile is stored (a megabyte per tile)
		{
			name = "background (black fill): nothing of the picture stays in the module's state after the tile is stored",
			func = function(state)
				local G = gen()

				useFill(state)
				state.res = 64
				state.onCapture = function(tile)
					return fillPicture(tile.tx)
				end

				G.Request(LEVEL, 500, 500, 100, BELOW)
				stepAll(state)

				local seen, found = {}, 0

				local function scan(v, depth)
					if depth > 12 then
						return
					end

					if type(v) == "string" then
						if #v >= 64 * 64 * 4 then
							found = found + 1
						end
					elseif type(v) == "table" and not seen[v] then
						seen[v] = true

						for k, x in pairs(v) do
							scan(k, depth + 1)
							scan(x, depth + 1)
						end
					end
				end

				scan(G._state, 0)
				expect(found).to.equal(0)
			end
		},
		-- fails if a Capture without the two functions, or a function that raises or answers something else, loses the tile or counts a failure
		{
			name = "background: without the functions, or with ones that raise or give nothing usable, the picture takes the normal path and nothing fails",
			func = function(state)
				local G = gen()

				state.res = 64
				state.onCapture = function(tile)
					return fillPicture(tile.tx)
				end

				-- the stand-in Capture of this file has no BackgroundToVoid, no IsAllBackground and no FindBackground
				G.Request(LEVEL, 500, 500, 100, BELOW)
				stepAll(state)
				expect(#state.compress).to.equal(18)

				for i = 1, #state.renders do
					expect(state.compress[i].bgra == fillPicture(state.renders[i].tx)).to.beTrue()
				end

				expect(G.Progress().belowDone).to.equal(9)
				G.Cancel()

				for _, how in ipairs({"raise", "nil", "number"}) do
					state.compress, state.renders, state.stores, state.stored = {}, {}, {}, {}

					GryMod.Minimap.Capture.BackgroundToVoid = function()
						if how == "raise" then
							error("BackgroundToVoid broke")
						elseif how == "nil" then
							return nil, "no"
						end

						return 5
					end

					GryMod.Minimap.Capture.FindBackground = function()
						error("FindBackground broke")
					end

					GryMod.Minimap.Capture.IsAllBackground = function()
						error("IsAllBackground broke")
					end

					G.Request(LEVEL, 500, 500, 100, BELOW)
					stepAll(state)

					expect(#state.compress).to.equal(18)

					for i = 1, #state.renders do
						expect(state.compress[i].bgra == fillPicture(state.renders[i].tx)).to.beTrue()
					end

					expect(G.Progress().belowDone).to.equal(9)
					expect(G.Progress().belowFailed).to.equal(0)
					expect(G.Progress().failed).to.equal(0)
					G.Cancel()
				end
			end
		},
		-- fails if an error in the handler of OutsideReady stops the generation
		{
			name = "outside: an error in a handler of OutsideReady does not stop anything",
			func = function(state)
				local G = gen()

				hook.Add("GryMod_MinimapOutsideReady", LISTENER .. "_raiser", function() error("handler of OutsideReady") end)

				expect(G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)).to.beTrue()
				stepAll(state)
				expect(G.Progress().outsideDone).to.equal(9)
				expect(#state.stores).to.equal(27)
				expect(G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)).to.beFalse()
			end
		},
		-- fails if the request of the outside allocates (the signature built as a string, a table per request)
		{
			name = "outside: an identical Request with a floor below and an outside allocates nothing (less than 1 KB for 2000)",
			func = function(state)
				local G = gen()

				G.Request(LEVEL, 1500, 500, 600, BELOW, OUTSIDE)
				pcall(jit.off)

				for i = 1, 4000 do
					G.Request(LEVEL, 1500, 500, 600, BELOW, OUTSIDE)
				end

				collectgarbage("collect")
				collectgarbage("stop")

				local before = collectgarbage("count")

				for i = 1, 1000 do
					G.Request(LEVEL, 1500, 500, 600, BELOW, OUTSIDE)
				end

				local mid = collectgarbage("count")

				for i = 1, 1000 do
					G.Request(LEVEL, 1520, 480, 600, BELOW, OUTSIDE)
				end

				local after = collectgarbage("count")

				collectgarbage("restart")
				pcall(jit.on)

				expect(mid - before).to.beLessThan(1)
				expect(after - mid).to.beLessThan(1)
				expect(G.Request(LEVEL, 1500, 500, 600, BELOW, OUTSIDE)).to.beFalse()
			end
		},
		-- fails if the limit of tiles is not checked for the outside range (the same range as the others: one count)
		{
			name = "outside: too many tiles refuses the whole request, outside included",
			func = function(state)
				local G = gen()

				GryMod.Minimap.View = {MAX_TILES = 30}
				expect(G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)).to.beTrue()

				local ok, err = G.Request(LEVEL, 500, 500, 3000, BELOW, OUTSIDE)

				expect(ok).to.beNil()
				expect(err).to.equal("too many tiles")
				expect(G.Progress().outsideTotal).to.equal(9)
				expect(G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)).to.beFalse()
			end
		},
		-- fails if Cache.Flush is not called when the three queues are empty and the work hook goes away (the empty tiles live only in the index)
		{
			name = "Flush: Cache.Flush is called once, when the three queues are empty and the hook is removed, not before",
			func = function(state)
				local G = gen()

				G.Request(LEVEL, 500, 500, 100, BELOW, OUTSIDE)
				expect(#state.flushes).to.equal(0)

				stepAll(state, 26)
				expect(#state.flushes).to.equal(0)
				expect(G.Pending()).to.equal(1)

				G.Step(state.t)
				expect(G.Pending()).to.equal(0)
				expect(#state.flushes).to.equal(1)
				expect(state.flushes[1].pending).to.equal(0)
				expect(state.flushes[1].hooked).to.beFalse() -- the hook is already gone: the work is over

				-- nothing left, no hook: a Step that does nothing does not flush again
				G.Step(state.t)
				expect(#state.flushes).to.equal(1)
			end
		},
		-- fails if the index is not written when a request leaves the generator idle after a hook was there
		{
			name = "Flush: a request that finds everything in the cache while the hook is on also flushes; an idle request does not",
			func = function(state)
				local G = gen()

				request9(state)
				expect(hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beA("function")

				-- everything the new request wants exists: no tile to make, the hook goes away
				for tx = 2, 4 do
					for ty = -1, 1 do
						state.stored["a1|" .. tx .. "," .. ty .. "|512|2"] = true
					end
				end

				G.Request(LEVEL, 3500, 500, 100)
				expect(G.Pending()).to.equal(0)
				expect(#state.flushes).to.equal(1)

				-- no hook was there: nothing to flush
				G.Request(LEVEL, 3500, 3500, 100)
				stepAll(state)
				local n = #state.flushes
				G.Request(LEVEL, 3500, 500, 100)
				expect(#state.flushes).to.equal(n)
			end
		},
		-- fails if Cancel does not write the index
		{
			name = "Flush: Cancel calls Cache.Flush (also when nothing was running), after the hook is gone",
			func = function(state)
				local G = gen()

				G.Cancel()
				expect(#state.flushes).to.equal(1)

				request9(state)
				G.Cancel()
				expect(#state.flushes).to.equal(2)
				expect(state.flushes[2].hooked).to.beFalse()
				expect(hook.GetTable()[HOOK_EVENT] and hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beNil()
			end
		},
		-- fails if a Cache without Flush, or a Flush that raises, stops the generation, Cancel or the removal of the hook
		{
			name = "Flush: a Cache without Flush, or a Flush that raises, is fine (the error is kept, nothing is raised)",
			func = function(state)
				local G = gen()

				GryMod.Minimap.Cache.Flush = nil
				request9(state)
				stepAll(state)
				expect(G.Progress().done).to.equal(9)
				expect(hook.GetTable()[HOOK_EVENT] and hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beNil()
				expect(pcall(G.Cancel)).to.beTrue()

				state.flushes = {}
				state.stored = {} -- the tiles of the first round are made again
				GryMod.Minimap.Cache.Flush = function()
					state.flushes[#state.flushes + 1] = true
					error("flush failed")
				end

				request9(state)
				stepAll(state)
				expect(#state.flushes).to.equal(1)
				expect(G.Progress().done).to.equal(9)
				expect(hook.GetTable()[HOOK_EVENT] and hook.GetTable()[HOOK_EVENT][HOOK_NAME]).to.beNil()
				expect(pcall(G.Cancel)).to.beTrue()
				expect(#state.flushes).to.equal(2)
			end
		},
		-- The preload (the tiles made in advance, from the in/out map): a fourth set, made after the main level, the floor below and the outside, and never wiped by a request.
		-- fails if a preload tile is made before a tile somebody is waiting for, or with another level than its own, or if the hook is not there while only preload tiles wait
		{
			name = "preload: the tiles come after every tile of the main, below and outside sets, each with its own level table, in the order given; the hook is there only while something waits",
			func = function(state)
				local G = gen()
				local P1 = {id = "open_t960", open = true, zlo = -100, zhi = 960}
				local entries = {}

				for i = 1, 3 do
					entries[i] = {tile = {level = P1.id, tx = i, ty = 0, res = 512, ppm = 2}, level = P1, d = i}
				end

				expect(isfunction(G.SetPreload)).to.beTrue()
				G.SetPreload(entries)
				expect(G.Pending()).to.equal(3)
				expect((hook.GetTable()[HOOK_EVENT] or {})[HOOK_NAME] ~= nil).to.beTrue()

				request9(state) -- nine main tiles, asked after the preload
				expect(G.Pending()).to.equal(12)
				stepAll(state)

				expect(#state.renders).to.equal(12)

				for i = 1, 9 do
					expect(state.renders[i].level).to.equal("a1")
				end

				for i = 1, 3 do
					local r = state.renders[9 + i]

					expect(r.level).to.equal("open_t960")
					expect(r.levelTable).to.equal(P1)
					expect(r.tx).to.equal(i)
				end

				expect(#state.stores).to.equal(12)
				expect(state.stores[12].format).to.equal(20)
				expect((hook.GetTable()[HOOK_EVENT] or {})[HOOK_NAME]).to.beNil()
			end
		},
		-- fails if a request (the radar makes one at every draw) wipes the preload queue, or if the preload tile that a new request pushes aside is lost
		{
			name = "preload: a Request does not wipe the queue, and the preload tile in progress that a new request pushes aside is made later, not lost",
			func = function(state)
				local G = gen()
				local P1 = {id = "open_t960", open = true, zlo = -100, zhi = 960}
				local entries = {}

				for i = 1, 3 do
					entries[i] = {tile = {level = P1.id, tx = i, ty = 0, res = 512, ppm = 2}, level = P1, d = i}
				end

				G.SetPreload(entries)
				G.Step(state.t) -- the first tile is made, the second one is in progress (not captured yet)
				expect(#state.stores).to.equal(1)

				request9(state) -- the main tiles take the lead; the tile in progress is not needed by the request
				expect(request9(state)).to.beFalse() -- the same request again: nothing is redone

				stepAll(state)

				-- nine main tiles and the three preload tiles, each made once
				expect(#state.renders).to.equal(12)

				local seen = {}

				for i = 1, #state.renders do
					local r = state.renders[i]
					local key = r.level .. "|" .. r.tx .. "," .. r.ty

					expect(seen[key]).to.beNil()
					seen[key] = true
				end

				expect(seen["open_t960|1,0"] and seen["open_t960|2,0"] and seen["open_t960|3,0"]).to.beTrue()
			end
		},
		-- fails if the preload shows in the veil (Progress is about the main level only) or has no numbers of its own
		{
			name = "preload: Progress (the veil) is about the main level only; PreloadProgress gives done, total and failed",
			func = function(state)
				local G = gen()
				local P1 = {id = "open_t960", open = true, zlo = -100, zhi = 960}
				local entries = {}

				for i = 1, 3 do
					entries[i] = {tile = {level = P1.id, tx = i, ty = 0, res = 512, ppm = 2}, level = P1, d = i}
				end

				G.SetPreload(entries)

				local p = G.Progress()

				expect(p.total).to.equal(0)
				expect(p.active).to.beFalse()

				local before = G.PreloadProgress()

				expect(before.done).to.equal(0)
				expect(before.total).to.equal(3)

				stepAll(state)

				local after = G.PreloadProgress()

				expect(after.done).to.equal(3)
				expect(after.total).to.equal(3)
				expect(after.failed).to.equal(0)
				expect(G.Progress().total).to.equal(0)
			end
		},
		-- fails if a tile the cache has (made meanwhile by a request, or there from the start) is made again
		{
			name = "preload: a tile the cache has is left out when the preload is set, and one it got meanwhile is not made again (it still counts as done)",
			func = function(state)
				local G = gen()
				local P1 = {id = "open_t960", open = true, zlo = -100, zhi = 960}
				local entries = {}

				for i = 1, 3 do
					entries[i] = {tile = {level = P1.id, tx = i, ty = 0, res = 512, ppm = 2}, level = P1, d = i}
				end

				state.stored[cacheKey(entries[1].tile)] = true -- there from the start
				G.SetPreload(entries)
				expect(G.PreloadProgress().total).to.equal(2)

				state.stored[cacheKey(entries[3].tile)] = true -- made by somebody else while it waited
				stepAll(state)

				expect(#state.renders).to.equal(1)
				expect(state.renders[1].tx).to.equal(2)
				expect(G.PreloadProgress().done).to.equal(2)
			end
		},
		-- fails if Cancel keeps the preload queue (the radar cancels when the minimap is switched off)
		{
			name = "preload: Cancel forgets the queue and removes the hook; the preload tiles get the same black-to-void treatment as the main ones",
			func = function(state)
				local G = gen()
				local P1 = {id = "open_t960", open = true, zlo = -100, zhi = 960}

				G.SetPreload({{tile = {level = P1.id, tx = 1, ty = 0, res = 512, ppm = 2}, level = P1, d = 1}})
				expect(G.Pending()).to.equal(1)
				G.Cancel()
				expect(G.Pending()).to.equal(0)
				expect(G.PreloadProgress().total).to.equal(0)
				expect((hook.GetTable()[HOOK_EVENT] or {})[HOOK_NAME]).to.beNil()

				-- a tile is stored under the name of its level, not of its role: the content must not depend on who asked first
				expect(G.VOID_FILL_SETS.preload).to.equal(true)
			end
		},
		-- The preload must not freeze the game: when nothing else is asked for it works with a smaller budget than the tiles somebody waits for, and it waits while the
		-- frames are slow. fails if the preload uses the full budget, or keeps working when the last frame was slow
		{
			name = "preload: with nothing else asked it works within its own small budget (2 ms) and not the settings' (6 ms); a request's tiles keep the settings' budget",
			func = function(state)
				local G = gen()
				local P1 = {id = "open_t960", open = true, zlo = -100, zhi = 960}
				local entries = {}

				for i = 1, 3 do
					entries[i] = {tile = {level = P1.id, tx = i, ty = 0, res = 512, ppm = 2}, level = P1, d = i}
				end

				state.budget = 6
				state.dt = 0.001 -- every reading of the clock is 1 ms later
				G._frameTime = function() return 0.005 end

				expect(G.PRELOAD_BUDGET_MS).to.equal(2)

				-- a request's tile: 6 units (capture, four chunks of 32 rows, store) in the 6 ms of the settings
				request9(state)
				G.Step(state.t)
				expect(#state.stores).to.equal(1)
				G.Cancel()

				-- a preload tile: two units in 2 ms (the capture, one chunk), no store yet
				state.stores, state.compress = {}, {}
				G.SetPreload(entries)
				G.Step(state.t)
				expect(#state.stores).to.equal(0)
				expect(#state.compress).to.equal(1)
			end
		},
		{
			name = "preload: no work in a frame that follows a slow frame (over 25 ms); it goes on when the frames are fast again",
			func = function(state)
				local G = gen()
				local P1 = {id = "open_t960", open = true, zlo = -100, zhi = 960}

				G.SetPreload({{tile = {level = P1.id, tx = 1, ty = 0, res = 512, ppm = 2}, level = P1, d = 1}})

				G._frameTime = function() return 0.05 end
				G.Step(state.t)
				expect(#state.renders).to.equal(0)
				expect(G.Pending()).to.equal(1)
				expect((hook.GetTable()[HOOK_EVENT] or {})[HOOK_NAME] ~= nil).to.beTrue()

				G._frameTime = function() return 0.01 end
				stepAll(state)
				expect(#state.renders).to.equal(1)

				-- the tiles of a request are not held back by a slow frame (somebody is waiting for them)
				request9(state)
				G._frameTime = function() return 0.05 end
				G.Step(state.t)
				expect(#state.renders >= 2).to.beTrue()
			end
		}
	}
}
