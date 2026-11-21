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

local LEVEL = {id = "a1", zlo = 0, zhi = 160}

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

	saved = {
		Capture = M.Capture,
		DXT1 = M.DXT1,
		Cache = M.Cache,
		Settings = M.Settings,
		clock = G and G._clock,
		hasClock = G ~= nil
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

	M.Settings = {
		Enabled = function() return true end,
		Definition = function() return st.ppm end,
		TileRes = function() return st.res end,
		Rotate = function() return false end,
		BudgetMs = function() return st.budget end
	}

	M.Cache = {
		TileUnits = function(res, ppm) return st.tileUnits end,
		TileOf = function(x, y, res, ppm) return math.floor(x / st.tileUnits), math.floor(y / st.tileUnits) end,
		Has = function(tile)
			st.hasCalls = st.hasCalls + 1

			return st.stored[cacheKey(tile)] == true
		end,
		Store = function(tile, data)
			st.storeCalls = st.storeCalls + 1

			if st.onStore then
				local ok, err = st.onStore(tile, st.storeCalls)

				if not ok then
					return false, err or "store refused"
				end
			end

			st.stores[#st.stores + 1] = {tile = tile, data = data}
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
		CompressRows = function(bgra, w, h, first, last)
			st.compress[#st.compress + 1] = {bgra = bgra, w = w, h = h, first = first, last = last}

			return "[" .. first .. "-" .. last .. "]"
		end
	}

	if G then
		G._clock = function()
			st.t = st.t + st.dt

			return st.t
		end
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
	end,
	afterEach = function(state)
		pcall(hook.Remove, "GryMod_MinimapProgress", LISTENER)
		pcall(hook.Remove, "GryMod_MinimapReady", LISTENER)
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
						return nil, "no render"
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
				state.onCapture = function() return nil end
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
		}
	}
}
