-- The big map: its own store of tiles (GryMod.Map.Store). A short-lived, in-memory pool of slots with a least-recently-used rule. In the game a slot is a
-- render target (map/tiles.lua owns them); here a slot is only a number, so the rules can be tested without a render context.
--
-- It is apart from the minimap's cache on purpose, and nothing in this file knows that cache: the big map changes its definition with the zoom, and a
-- tile it makes must never replace, evict or invalidate a tile the radar's circular preload made. Nothing is written to the disk.
--
-- The tiles are known by a number (Pyramid.Key), so a lookup in a frame makes no garbage. A store belongs to one level (the open level of the map) and
-- one tile size: Scope clears it when either changes.

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}
GryMod.Map.Store = GryMod.Map.Store or {}

local Store = GryMod.Map.Store

local floor = math.floor

-- The memory the pool may use for its tiles (4 bytes a pixel): 128 MB. A window shows one to three tiles across at the level its zoom needs, so 32 tiles of 1024
-- pixels hold the window with a tile of margin and the tiles that were just left.
Store.BYTES = 128 * 1024 * 1024
Store.MIN_CAPACITY = 4
Store.MAX_CAPACITY = 64

-- How many tiles of `res` pixels the pool holds: the memory over the size of a tile, between MIN_CAPACITY and MAX_CAPACITY.
function Store.CapacityFor(res)
	if type(res) ~= "number" or res ~= res or res <= 0 then
		return Store.MIN_CAPACITY
	end

	local n = floor(Store.BYTES / (res * res * 4))

	if n < Store.MIN_CAPACITY then
		return Store.MIN_CAPACITY
	end

	if n > Store.MAX_CAPACITY then
		return Store.MAX_CAPACITY
	end

	return n
end

-- A store of `capacity` slots (a whole number, at least 1).
function Store.New(capacity)
	if type(capacity) ~= "number" or capacity ~= capacity or capacity < 1 then
		capacity = 1
	end

	return {
		capacity = floor(capacity),
		slotOf = {}, -- key -> slot
		keyOf = {}, -- slot -> key
		ready = {}, -- slot -> true once the picture is there
		stamp = {}, -- slot -> a counter that goes up at every use (the least recently used has the smallest)
		used = {}, -- slot -> the frame it was last looked at in (a tile in use is not evicted in that frame)
		at = {}, -- slot -> the time its picture arrived
		tick = 0,
		count = 0,
		scopeLevel = nil,
		scopeRes = nil
	}
end

function Store.Capacity(s)
	return s.capacity
end

-- The tiles that are there (a reservation is not a tile).
function Store.Count(s)
	return s.count
end

local function drop(s, slot)
	local key = s.keyOf[slot]

	if key ~= nil then
		s.slotOf[key] = nil
		s.keyOf[slot] = nil

		if s.ready[slot] then
			s.count = s.count - 1
		end
	end

	s.ready[slot], s.stamp[slot], s.used[slot], s.at[slot] = nil, nil, nil, nil
end

-- Forgets every tile and every reservation.
function Store.Clear(s)
	for slot = 1, s.capacity do
		drop(s, slot)
	end

	s.slotOf, s.keyOf = {}, {}
	s.count = 0
end

-- The level and the tile size this store works for. A change of either clears it. Returns true when it changed (the first call included).
function Store.Scope(s, levelId, res)
	if s.scopeLevel == levelId and s.scopeRes == res then
		return false
	end

	Store.Clear(s)
	s.scopeLevel, s.scopeRes = levelId, res

	return true
end

function Store.Has(s, key)
	local slot = s.slotOf[key]

	return slot ~= nil and s.ready[slot] == true
end

-- The slot of a tile that is there, or nil. Looking at it counts as a use in `frame`.
function Store.Slot(s, key, frame)
	local slot = s.slotOf[key]

	if slot == nil or not s.ready[slot] then
		return nil
	end

	s.tick = s.tick + 1
	s.stamp[slot] = s.tick
	s.used[slot] = frame

	return slot
end

function Store.ArrivedAt(s, key)
	local slot = s.slotOf[key]

	return slot ~= nil and s.at[slot] or nil
end

-- A slot for the tile `key`, to be filled and then committed. A tile that is already there keeps its slot. Otherwise a free slot, else the least recently
-- used tile that was not used in `frame` (a reservation not committed yet is never taken). nil when every slot is in use.
function Store.Reserve(s, key, frame)
	local own = s.slotOf[key]

	if own ~= nil then
		return own
	end

	local choice, best

	for slot = 1, s.capacity do
		if s.keyOf[slot] == nil then
			choice = slot

			break
		end

		if s.ready[slot] and s.used[slot] ~= frame and (best == nil or s.stamp[slot] < best) then
			choice, best = slot, s.stamp[slot]
		end
	end

	if choice == nil then
		return nil
	end

	drop(s, choice)
	s.slotOf[key], s.keyOf[choice] = choice, key
	s.tick = s.tick + 1
	s.stamp[choice] = s.tick

	return choice
end

-- The picture of a reserved tile is there (`now` is the time of its arrival).
function Store.Commit(s, key, now)
	local slot = s.slotOf[key]

	if slot == nil or s.ready[slot] then
		return false
	end

	s.ready[slot] = true
	s.at[slot] = now
	s.count = s.count + 1
	s.tick = s.tick + 1
	s.stamp[slot] = s.tick

	return true
end

-- A reservation that came to nothing (the render failed): the slot is free again.
function Store.Release(s, key)
	local slot = s.slotOf[key]

	if slot ~= nil and not s.ready[slot] then
		drop(s, slot)
	end
end

-- A new capacity. A slot is a render target of the game, so a tile cannot move from one slot to another: a smaller capacity forgets the tiles that are in the
-- slots past the new end (nothing is copied), and a bigger one only makes room.
function Store.SetCapacity(s, capacity)
	if type(capacity) ~= "number" or capacity ~= capacity or capacity < 1 then
		return s.capacity
	end

	capacity = floor(capacity)

	for slot = capacity + 1, s.capacity do
		drop(s, slot)
	end

	s.capacity = capacity

	return capacity
end
