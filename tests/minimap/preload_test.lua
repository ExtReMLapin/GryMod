-- Tests of GryMod.Minimap.Preload (lua/grymod/client/minimap/preload.lua), GLuaTest format, client realm. The preload makes the list of tiles to prepare in advance from
-- the in/out map's boxes (the outdoor ones, the open level) and from the definitions the automatic rule can reach from the player's zoom ranges.
-- Everything here is pure: the engine's parts (the ray of Floors.OpenAt, the tile size of Cache, the cache's Has) are stand-ins given in `opts`, and the one real
-- part is the rule of Settings.AutoDefinitionFor (the definitions are found with it, the numbers below were worked out by hand from its rule).

local function P()
	return GryMod.Minimap.Preload or {}
end

-- a box as the in/out map gives it: layer, x1, y1, x2, y2 (cells of 128 units, inclusive), state (1 outdoor, 2 indoor), ceiling class
local function box(layer, x1, y1, x2, y2, state)
	return {layer = layer, x1 = x1, y1 = y1, x2 = x2, y2 = y2, state = state or 1, ceil = 0}
end

local function level(id)
	return {id = id, open = true, zlo = -100, zhi = 5000}
end

-- the options of a plan: tiles of 256 units whatever the definition, one level for every place unless `levelAt` is given
local function options(extra)
	local opts = {
		definitions = {2},
		res = 1024,
		tileUnits = function() return 256 end,
		levelAt = function() return level("open_t960") end,
		has = function() return false end,
		origin = {0, 0}
	}

	for k, v in pairs(extra or {}) do
		opts[k] = v
	end

	return opts
end

-- the whole list a job makes, stepped in as many pieces as asked
local function run(boxes, opts, perStep)
	local job = P().NewJob(boxes, opts)

	while not job.Done() do
		job.Step(perStep or 1000)
	end

	return job.Entries(), job
end

-- tables are compared by reference by the framework: lists are compared as text
local function text(list)
	local out = {}

	for i, v in ipairs(list) do
		out[i] = tostring(v)
	end

	return table.concat(out, " ")
end

local function ids(entries)
	local out = {}

	for i, e in ipairs(entries) do
		out[i] = e.tile.level .. ":" .. e.tile.tx .. "," .. e.tile.ty .. "@" .. e.tile.ppm
	end

	table.sort(out)

	return out
end

return {
	groupName = "GryMod minimap preload (client)",
	cases = {
		{
			-- the numbers come from Settings.AutoDefinitionFor (smallest level of at least 0.7 times the density, the level in use kept between 0.6 and 1.6 times it) with
			-- k = 130 (the radar's pixels per metre times the screen's, for a 4K screen: the density at a range r is k / r).
			-- breaks if: the level in use is forgotten, a level shared by two ranges is listed twice, a range gets a level other than the rule's, or a slider value that is
			-- not a level of the pyramid gets into the list
			name = "Definitions: the level in use plus the level of each zoom range, shared ones once (100 / 75 / 25 m on 4K give 2 and 4; 100 / 40 / 10 m give 2, 4 and 16)",
			func = function()
				expect(isfunction(P().Definitions)).to.beTrue()

				-- the owner's three ranges: the 100 and the 75 give the same level, the 25 another
				expect(text(P().Definitions(130, {100, 75, 25}, 4))).to.equal("2 4")

				-- three ranges, three levels (the 40 m would stay at 2 only up to a density of 3.2, it is 3.25)
				expect(text(P().Definitions(130, {100, 40, 10}, 4))).to.equal("2 4 16")

				-- one range: its own level, and the level in use (the radar draws it under the new one while it is made)
				expect(text(P().Definitions(130, {25}, 4))).to.equal("4")
				expect(text(P().Definitions(130, {25}, 2))).to.equal("2 4")

				-- a level in use that the pyramid does not have (the slider's value) is not a level of the rule: not in the list
				expect(text(P().Definitions(130, {25}, 15))).to.equal("4")

				-- nothing usable: no density constant, or no range
				expect(text(P().Definitions(nil, {25}, 4))).to.equal("")
				expect(text(P().Definitions(130, {}, 4))).to.equal("")
			end
		},
		{
			-- breaks if: an indoor box is asked for an open level, a tile is listed twice (four sub-areas of a box fall in two tiles), or the tile range is off by one
			name = "NewJob: the tiles that cover the outdoor boxes (an indoor box is left out, a tile is listed once), by hand: 4 x 2 cells of 128 units are 2 tiles of 256",
			func = function()
				local asked = 0
				local entries = run({box(0, 0, 0, 3, 1), box(0, 10, 10, 12, 12, 2)}, options({
					levelAt = function()
						asked = asked + 1

						return level("open_t960")
					end
				}))

				-- the box covers x 0..512 and y 0..256: tiles (0,0) and (1,0)
				expect(text(ids(entries))).to.equal("open_t960:0,0@2 open_t960:1,0@2")
				expect(entries[1].level.id).to.equal("open_t960")

				-- 4 x 2 cells are split in 3 x 2 areas (at most 3 along an axis, never more than the cells): six rays, none for the indoor box
				expect(asked).to.equal(6)
			end
		},
		{
			-- breaks if: the list is not the nearest tiles first (the preload would start far from the player), or a tile the cache already has is made again
			name = "NewJob: nearest to the player first; a tile the cache has is left out",
			func = function()
				local boxes = {box(0, 0, 0, 7, 0)} -- x 0..1024, one row: tiles 0, 1, 2, 3 (of 256)
				local entries = run(boxes, options({origin = {900, 50}}))

				-- the tile of x 768..1024 is the nearest to (900, 50), then 512..768, then 256..512, then 0..256
				expect(#entries).to.equal(4)
				expect(entries[1].tile.tx).to.equal(3)
				expect(entries[2].tile.tx).to.equal(2)
				expect(entries[4].tile.tx).to.equal(0)

				local has = function(tile) return tile.tx == 3 end
				local rest = run(boxes, options({origin = {900, 50}, has = has}))

				expect(#rest).to.equal(3)
				expect(rest[1].tile.tx).to.equal(2)
			end
		},
		{
			-- breaks if: a place under a roof (no open level) makes tiles, or two heights in one tile are mixed into a single level (the camera of one of them is wrong)
			name = "NewJob: a place with no open level makes no tile; two levels over one tile make two tiles",
			func = function()
				-- left half of the box under a roof, right half open at 960
				local entries = run({box(0, 0, 0, 1, 0)}, options({
					levelAt = function(x)
						if x < 128 then
							return nil, "roofed"
						end

						return level("open_t960")
					end
				}))

				expect(text(ids(entries))).to.equal("open_t960:0,0@2")

				-- the left half under a piece at 2944, the right half open at 960: the same tile (0,0), two levels
				local mixed = run({box(0, 0, 0, 1, 0)}, options({
					levelAt = function(x)
						return level(x < 128 and "open_t2944" or "open_t960")
					end
				}))

				expect(text(ids(mixed))).to.equal("open_t2944:0,0@2 open_t960:0,0@2")
			end
		},
		{
			-- breaks if: every definition does not get its own tiles (a tile of another size covers another area), or the cap is not on the nearest tiles
			name = "NewJob: every definition has its own tiles, and a plan over the cap keeps the nearest ones and says it was cut",
			func = function()
				-- definition 2 has tiles of 256 units, definition 4 of 128
				local opts = options({
					definitions = {2, 4},
					tileUnits = function(_, ppm) return ppm == 2 and 256 or 128 end
				})
				local entries = run({box(0, 0, 0, 1, 0)}, opts) -- x 0..256, y 0..128

				expect(text(ids(entries))).to.equal("open_t960:0,0@2 open_t960:0,0@4 open_t960:1,0@4")

				local capped, job = run({box(0, 0, 0, 7, 0)}, options({origin = {0, 0}, maxTiles = 2}))

				expect(#capped).to.equal(2)
				expect(capped[1].tile.tx).to.equal(0)
				expect(capped[2].tile.tx).to.equal(1)
				expect(job.Truncated()).to.beTrue()
				expect(job.Total()).to.equal(4)
			end
		},
		{
			-- breaks if: a step does all the work whatever the count asked (a frame would freeze on a map with thousands of boxes), or the job never says it is done
			name = "NewJob: a step does at most the number of boxes asked, the job says when it is done, and the result is the same in any number of steps",
			func = function()
				local boxes = {}

				for i = 0, 9 do
					boxes[#boxes + 1] = box(0, i * 3, 0, i * 3 + 1, 0)
				end

				local job = P().NewJob(boxes, options())

				expect(job.Done()).to.beFalse()
				expect(job.Step(3)).to.equal(3)
				expect(job.Done()).to.beFalse()
				expect(job.Step(3)).to.equal(3)
				expect(job.Step(3)).to.equal(3)
				expect(job.Step(3)).to.equal(1) -- ten boxes in all
				expect(job.Done()).to.beTrue()
				expect(job.Step(3)).to.equal(0)

				local whole = run(boxes, options(), 1000)
				local pieces = run(boxes, options(), 1)

				expect(text(ids(pieces))).to.equal(text(ids(whole)))
			end
		}
	}
}
