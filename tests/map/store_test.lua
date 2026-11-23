-- Tests of the big map's own store of tiles (lua/grymod/client/map/store.lua), GLuaTest format, client realm: a short-lived, in-memory pool of slots
-- (each slot is a render target in the game) with a least-recently-used rule. It is apart from the minimap's cache on purpose: nothing here knows
-- the cache, so a tile of the big map can never push a tile of the minimap out. Pure bookkeeping: a slot is only a number here.

local function S()
	local store = GryMod and GryMod.Map and GryMod.Map.Store

	expect(store ~= nil).to.beTrue()

	return store
end

-- reserves and commits a tile; returns its slot
local function put(store, s, key, frame)
	local slot = store.Reserve(s, key, frame)

	expect(slot ~= nil).to.beTrue()
	store.Commit(s, key, 100 + key)

	return slot
end

return {
	groupName = "GryMod big map store",
	cases = {
		-- fails without Store.New
		{
			name = "a new store holds nothing and keeps the capacity it was given (at least 1)",
			func = function()
				local store = S()
				local s = store.New(5)

				expect(store.Capacity(s)).to.equal(5)
				expect(store.Count(s)).to.equal(0)
				expect(store.Has(s, 1)).to.beFalse()
				expect(store.Slot(s, 1, 1)).to.beNil()
				expect(store.Capacity(store.New(0))).to.equal(1)
				expect(store.Capacity(store.New("x"))).to.equal(1)
			end
		},
		-- fails when a reserved tile can be seen before it is committed
		{
			name = "a tile is there only once it is committed: a reserved slot is not a picture yet",
			func = function()
				local store = S()
				local s = store.New(4)
				local slot = store.Reserve(s, 7, 1)

				expect(slot ~= nil).to.beTrue()
				expect(store.Has(s, 7)).to.beFalse()
				expect(store.Slot(s, 7, 1)).to.beNil()
				expect(store.Count(s)).to.equal(0)

				store.Commit(s, 7, 55.5)

				expect(store.Has(s, 7)).to.beTrue()
				expect(store.Slot(s, 7, 1)).to.equal(slot)
				expect(store.Count(s)).to.equal(1)
				expect(store.ArrivedAt(s, 7)).to.equal(55.5)
			end
		},
		-- fails when a release does not give the slot back
		{
			name = "a reservation that failed is released and the slot is free again",
			func = function()
				local store = S()
				local s = store.New(1)

				store.Reserve(s, 1, 1)
				store.Release(s, 1)

				expect(store.Reserve(s, 2, 1) ~= nil).to.beTrue()
				expect(store.Has(s, 1)).to.beFalse()
			end
		},
		-- fails when the rule is not "least recently used"
		{
			name = "when the store is full the least recently used tile is the one that goes",
			func = function()
				local store = S()
				local s = store.New(3)

				put(store, s, 1, 1)

				local slot2 = put(store, s, 2, 1)

				put(store, s, 3, 1)

				-- 1 is looked at in a later frame: 2 is now the oldest
				expect(store.Slot(s, 1, 2) ~= nil).to.beTrue()

				put(store, s, 4, 3)

				expect(store.Has(s, 2)).to.beFalse()
				expect(store.Has(s, 1)).to.beTrue()
				expect(store.Has(s, 3)).to.beTrue()
				expect(store.Has(s, 4)).to.beTrue()
				-- the new tile took the slot of the old one
				expect(store.Slot(s, 4, 3)).to.equal(slot2)
				expect(store.Count(s)).to.equal(3)
			end
		},
		-- fails when a tile that was drawn in this very frame can be evicted
		{
			name = "a tile drawn in the current frame is never evicted for a new one: with every slot in use the reservation says no",
			func = function()
				local store = S()
				local s = store.New(2)

				put(store, s, 1, 5)
				put(store, s, 2, 5)
				store.Slot(s, 1, 5)
				store.Slot(s, 2, 5)

				expect(store.Reserve(s, 3, 5)).to.beNil()
				expect(store.Has(s, 1)).to.beTrue()
				expect(store.Has(s, 2)).to.beTrue()

				-- the next frame they can be replaced
				expect(store.Reserve(s, 3, 6) ~= nil).to.beTrue()
			end
		},
		-- fails when a tile that is already there is made twice
		{
			name = "reserving a tile that is already there gives its own slot and keeps its picture",
			func = function()
				local store = S()
				local s = store.New(3)
				local slot = put(store, s, 9, 1)

				expect(store.Reserve(s, 9, 2)).to.equal(slot)
				expect(store.Has(s, 9)).to.beTrue()
				expect(store.Count(s)).to.equal(1)
			end
		},
		-- fails when a slot in the middle of a render is taken for another tile
		{
			name = "a reserved slot that is not committed yet is never taken for another tile",
			func = function()
				local store = S()
				local s = store.New(2)

				put(store, s, 1, 1)

				local pendingSlot = store.Reserve(s, 2, 2)
				local other = store.Reserve(s, 3, 3)

				-- slot of tile 1 is the only one that can go
				expect(other ~= pendingSlot).to.beTrue()
				expect(store.Has(s, 1)).to.beFalse()
			end
		},
		-- fails when Clear leaves tiles behind
		{
			name = "Clear forgets every tile and every reservation",
			func = function()
				local store = S()
				local s = store.New(3)

				put(store, s, 1, 1)
				store.Reserve(s, 2, 1)
				store.Clear(s)

				expect(store.Count(s)).to.equal(0)
				expect(store.Has(s, 1)).to.beFalse()
				expect(store.Reserve(s, 5, 1) ~= nil).to.beTrue()
				expect(store.Reserve(s, 6, 1) ~= nil).to.beTrue()
				expect(store.Reserve(s, 7, 1) ~= nil).to.beTrue()
			end
		},
		-- fails when the scope is not checked
		{
			name = "the store belongs to one level and one tile size: asking for another clears it, asking for the same changes nothing",
			func = function()
				local store = S()
				local s = store.New(3)

				expect(store.Scope(s, "open", 1024)).to.beTrue() -- the first scope is a change from nothing
				put(store, s, 1, 1)
				expect(store.Scope(s, "open", 1024)).to.beFalse()
				expect(store.Has(s, 1)).to.beTrue()
				expect(store.Scope(s, "open_t512", 1024)).to.beTrue()
				expect(store.Has(s, 1)).to.beFalse()
				put(store, s, 1, 1)
				expect(store.Scope(s, "open_t512", 512)).to.beTrue()
				expect(store.Has(s, 1)).to.beFalse()
			end
		},
		-- fails when a smaller capacity keeps more than it holds
		{
			name = "a smaller capacity forgets the tiles of the slots past the new end (a slot is a render target and cannot move); a bigger one only makes room",
			func = function()
				local store = S()
				local s = store.New(4)

				for key = 1, 4 do
					put(store, s, key, key)
				end

				store.SetCapacity(s, 2)

				expect(store.Count(s)).to.equal(2)
				expect(store.Has(s, 1)).to.beTrue()
				expect(store.Has(s, 2)).to.beTrue()
				expect(store.Has(s, 3)).to.beFalse()
				expect(store.Has(s, 4)).to.beFalse()
				-- no slot past the end is handed out any more
				expect(store.Reserve(s, 9, 50)).to.equal(1)

				store.SetCapacity(s, 5)
				expect(store.Capacity(s)).to.equal(5)
				expect(store.Count(s)).to.equal(1)
			end
		},
		-- fails when the capacity does not follow the tile size
		{
			name = "the capacity follows the size of a tile: 160 megabytes of tiles, at least 4, at most 64",
			func = function()
				local store = S()

				expect(store.CapacityFor(1024)).to.equal(40)
				expect(store.CapacityFor(2048)).to.equal(10)
				expect(store.CapacityFor(512)).to.equal(64)
				expect(store.CapacityFor(4096)).to.equal(4)
				expect(store.CapacityFor("x")).to.equal(4)
			end
		},
		-- fails when the module knows the minimap's cache
		{
			name = "the store never touches the minimap's cache: a full store of the big map leaves a recording cache untouched",
			func = function()
				local M = GryMod.Minimap
				local created = M == nil

				GryMod.Minimap = M or {}

				local saved = GryMod.Minimap.Cache
				local calls = 0
				local recorder = setmetatable({}, {__index = function() return function() calls = calls + 1 end end, __newindex = function() calls = calls + 1 end})

				GryMod.Minimap.Cache = recorder

				local ok, err = pcall(function()
					local store = S()
					local s = store.New(2)

					for key = 1, 6 do
						store.Reserve(s, key, key)
						store.Commit(s, key, key)
						store.Slot(s, key, key)
					end

					store.Clear(s)
					store.SetCapacity(s, 1)
					expect(calls).to.equal(0)
				end)

				GryMod.Minimap.Cache = saved

				if created then
					GryMod.Minimap = nil
				end

				if not ok then
					error(err, 0)
				end
			end
		}
	}
}
