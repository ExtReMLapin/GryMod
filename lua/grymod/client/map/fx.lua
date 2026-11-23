-- The big map: the loading looks (GryMod.Map.Fx). While tiles are made, the map shows that it is intentional. THE RULE (the owner's): the game knows
-- only three things, that a loading began, that a tile arrived and that nothing is left; it knows no progress. So a tile has exactly two looks:
--   * "waiting": a loop on its own clock, drawn over the coarse picture (the previous zoom level's picture scaled, never an empty cell);
--   * "arrived": a short effect (about 0.3 s) that starts the moment the tile arrives and is never delayed;
-- and at the very end, one brief rim flash. Nothing here is tied to a share of work done.
--
-- A look is an entry of a registry, so a developer can add or swap one (GryMod.Map.Fx.Register) and the player picks it with the convar
-- `gry_map_loading_fx` (default "glitch", the owner's pick among the mock-ups). A look is a table:
--   label    the name in the menu
--   waiting  function(d, cell, t): draws the waiting look of a cell; `t` is the seconds this cell has been waiting
--   arrived  function(d, cell, p, t): draws the arrival look; `p` goes from 0 to 1 over `arrive` seconds, `t` is the seconds since the arrival
--   finish   function(d, rect, p): optional, the rim flash of the end; `p` goes from 0 to 1 over `rim` seconds
--   arrive   seconds of the arrival look (0.3 by default); rim: seconds of the rim flash (0.35 by default)
-- `cell` is {x, y, w, h, tx, ty, coarse, sharp}: where the tile is on the screen and its two pictures (nil when there is none); a picture is whatever the
-- panel gave: the look only hands it back to the drawer `d`, which has three functions:
--   d.Fill(x, y, w, h, r, g, b, a)
--   d.Slice(pic, x, y, w, h, f0, f1, dx, r, g, b, a, additive)   the horizontal band f0..f1 (fractions of the cell's height) of the picture, shifted by dx pixels
--   d.Rim(x, y, w, h, thickness, r, g, b, a)                      a frame
-- The base of the cell (the coarse picture, or the sharp one when the tile is there and settled) is drawn by the panel; the look draws over it.

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}
GryMod.Map.Fx = GryMod.Map.Fx or {}

local Fx = GryMod.Map.Fx

Fx.DEFAULT = "glitch"
Fx.ARRIVE_SECONDS = 0.3
Fx.RIM_SECONDS = 0.35

-- the looks by name, kept through a reload of this file
Fx.looks = Fx.looks or {}

local floor, sin = math.floor, math.sin

-- A number between 0 and 1 from two numbers: the same inputs, the same answer.
function Fx.Hash(a, b)
	local x = sin(a * 12.9898 + b * 78.233) * 43758.5453

	return x - floor(x)
end

local hash = Fx.Hash

-- The accent colour of the interface (the original's green).
local ACC_R, ACC_G, ACC_B = 154, 214, 90

local function clamp(n, low, high)
	if n < low then
		return low
	elseif n > high then
		return high
	end

	return n
end

-- the registry --------------------------------------------------------------------------------------------------------------------------------

-- Adds or replaces a look. Returns true, or false and why.
function Fx.Register(name, look)
	if type(name) ~= "string" or not string.find(name, "^[%w_]+$") or #name > 32 then
		return false, "invalid name"
	end

	if type(look) ~= "table" or type(look.waiting) ~= "function" or type(look.arrived) ~= "function" then
		return false, "a look needs a waiting and an arrived function"
	end

	Fx.looks[name] = look

	return true
end

function Fx.Unregister(name)
	if Fx.looks[name] == nil then
		return false
	end

	Fx.looks[name] = nil

	return true
end

function Fx.Get(name)
	return Fx.looks[name]
end

-- The names of the looks, sorted.
function Fx.List()
	local names = {}

	for name in pairs(Fx.looks) do
		names[#names + 1] = name
	end

	table.sort(names)

	return names
end

-- The look of that name; the default look for a name nobody registered (a look removed while it was chosen).
function Fx.Resolve(name)
	return Fx.looks[name] or Fx.looks[Fx.DEFAULT]
end

function Fx.ArriveSeconds(look)
	return look and tonumber(look.arrive) or Fx.ARRIVE_SECONDS
end

function Fx.RimSeconds(look)
	return look and tonumber(look.rim) or Fx.RIM_SECONDS
end

-- the glitch ----------------------------------------------------------------------------------------------------------------------------------
-- Waiting: the tile trembles in bands: a dark veil, and six bands of the coarse picture, each thrown sideways by its own random amount that changes
-- about twelve times a second. Arrived: the tile tears, the same six bands of the sharp picture shifted, plus a red copy and a cyan copy added on either
-- side, everything shrinking to nothing in 0.3 s; then the plain tile. The end: a rim of the accent colour that fades.

local BANDS = 6

Fx.Register("glitch", {
	label = "Glitch",
	arrive = 0.3,
	rim = 0.35,

	waiting = function(d, cell, t)
		local seed = floor(t / 0.08)
		local salt = cell.tx * 13 + cell.ty
		local amplitude = clamp(cell.w * 0.04, 3, 24)

		d.Fill(cell.x, cell.y, cell.w, cell.h, 0, 0, 0, 77)

		if cell.coarse == nil then
			return
		end

		local alpha = floor((0.5 + 0.3 * hash(seed, cell.tx + cell.ty * 9)) * 255 + 0.5)

		for s = 0, BANDS - 1 do
			d.Slice(cell.coarse, cell.x, cell.y, cell.w, cell.h, s / BANDS, (s + 1) / BANDS, (hash(seed + s, salt) - 0.5) * amplitude, 255, 255, 255, alpha, false)
		end
	end,

	arrived = function(d, cell, p, t)
		if p >= 1 or cell.sharp == nil then
			return
		end

		local seed = floor(t / 0.07)
		local k = 1 - p
		local salt = cell.tx * 13 + cell.ty
		local amplitude = clamp(cell.w * 0.1, 4, 40) * k
		local split = clamp(cell.w * 0.03, 2, 18) * k

		for s = 0, BANDS - 1 do
			d.Slice(cell.sharp, cell.x, cell.y, cell.w, cell.h, s / BANDS, (s + 1) / BANDS, (hash(seed + s, salt) - 0.5) * amplitude, 255, 255, 255, 255, false)
		end

		local alpha = floor(0.55 * k * 255 + 0.5)

		d.Slice(cell.sharp, cell.x, cell.y, cell.w, cell.h, 0, 1, split, 255, 58, 58, alpha, true)
		d.Slice(cell.sharp, cell.x, cell.y, cell.w, cell.h, 0, 1, -split, 58, 255, 255, alpha, true)
	end,

	finish = function(d, rect, p)
		if p >= 1 then
			return
		end

		d.Rim(rect.x, rect.y, rect.w, rect.h, math.max(3, floor(math.min(rect.w, rect.h) / 100)), ACC_R, ACC_G, ACC_B, floor((1 - p) * 255 + 0.5))
	end
})

-- the tracker ---------------------------------------------------------------------------------------------------------------------------------
-- What the map knows of its loading: which tiles were asked and are not there yet, when the others arrived, and when the last one did. Keys are the
-- numbers of Pyramid.Key. Pure: the clock is given.

Fx.Tracker = Fx.Tracker or {}

local Tracker = Fx.Tracker

function Tracker.New()
	return {waiting = {}, arrived = {}, nWaiting = 0, nArrived = 0, arrivedInBatch = false, endAt = nil}
end

function Tracker.Reset(t)
	t.waiting, t.arrived = {}, {}
	t.nWaiting, t.nArrived = 0, 0
	t.arrivedInBatch, t.endAt = false, nil
end

function Tracker.Waiting(t)
	return t.nWaiting
end

function Tracker.Arrivals(t)
	return t.nArrived
end

-- A tile was asked for (a tile asked twice is one).
function Tracker.Request(t, key, now)
	if t.waiting[key] == nil then
		t.waiting[key] = now
		t.nWaiting = t.nWaiting + 1
	end
end

-- The end of a batch: nothing waits any more. The rim flashes only when something arrived in it.
local function settle(t, now)
	if t.nWaiting == 0 then
		if t.arrivedInBatch then
			t.endAt = now
		end

		t.arrivedInBatch = false
	end
end

-- A tile arrived. One nobody waited for (the cache had it) has no look.
function Tracker.Arrive(t, key, now)
	if t.waiting[key] == nil then
		return
	end

	t.waiting[key] = nil
	t.nWaiting = t.nWaiting - 1

	if t.arrived[key] == nil then
		t.nArrived = t.nArrived + 1
	end

	t.arrived[key] = now
	t.arrivedInBatch = true
	settle(t, now)
end

-- A request that came to nothing (the window moved on): the tile stops waiting.
function Tracker.Drop(t, key, now)
	if t.waiting[key] == nil then
		return
	end

	t.waiting[key] = nil
	t.nWaiting = t.nWaiting - 1
	settle(t, now)
end

-- The look of a tile now: "waiting", the seconds it has waited | "arrived", p (0 to 1), the seconds since the arrival | nil (nothing to draw over the tile).
function Tracker.Look(t, key, now, arriveSeconds)
	local since = t.waiting[key]

	if since ~= nil then
		return "waiting", now - since
	end

	local at = t.arrived[key]

	if at ~= nil then
		local p = (now - at) / arriveSeconds

		if p >= 0 and p < 1 then
			return "arrived", p, now - at
		end
	end

	return nil
end

-- The rim at the end: p from 0 to 1 over `seconds`, or nil when there is none.
function Tracker.Rim(t, now, seconds)
	if t.endAt == nil then
		return nil
	end

	local p = (now - t.endAt) / seconds

	if p >= 0 and p < 1 then
		return p
	end

	return nil
end

-- Forgets the arrivals whose look is over.
function Tracker.Prune(t, now, arriveSeconds)
	for key, at in pairs(t.arrived) do
		if now - at >= arriveSeconds then
			t.arrived[key] = nil
			t.nArrived = t.nArrived - 1
		end
	end
end
