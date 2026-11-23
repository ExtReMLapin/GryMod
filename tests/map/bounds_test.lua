-- Tests of the big map's bounds (lua/grymod/client/map/bounds.lua), GLuaTest format, client realm: where the picture of the map stops (the hard limit
-- of the pan). Pure: the ground nodes of the AI graph, the boxes of the in/out map and the box of the world are given as plain tables.

local function B()
	local bounds = GryMod and GryMod.Map and GryMod.Map.Bounds

	expect(bounds ~= nil).to.beTrue()

	return bounds
end

-- n ground nodes (type 2) spread over x0..x1, y0..y1
local function nodes(n, x0, x1, y0, y1)
	local list = {}

	for i = 1, n do
		local t = (i - 1) / (n - 1)

		list[i] = {x = x0 + (x1 - x0) * t, y = y0 + (y1 - y0) * t, z = 0, type = 2}
	end

	return list
end

return {
	groupName = "GryMod big map bounds",
	cases = {
		-- fails without Bounds.Compute
		{
			name = "the bounds of a map with a node graph are the box of its ground nodes plus a margin of 5 percent (at least 1024 units)",
			func = function()
				local b = B().Compute({nodes = nodes(10, 0, 20000, -5000, 5000)})

				expect(b.source).to.equal("nodes")
				-- 5 percent of 20000 is 1000, under the minimum of 1024
				expect(b.x0).to.aboutEqual(-1024, 1e-6)
				expect(b.x1).to.aboutEqual(21024, 1e-6)
				expect(b.y0).to.aboutEqual(-6024, 1e-6)
				expect(b.y1).to.aboutEqual(6024, 1e-6)

				-- a big map: 5 percent of the long side, 2000
				local big = B().Compute({nodes = nodes(10, 0, 40000, 0, 20000)})

				expect(big.x0).to.aboutEqual(-2000, 1e-6)
				expect(big.x1).to.aboutEqual(42000, 1e-6)
				expect(big.y0).to.aboutEqual(-2000, 1e-6)
				expect(big.y1).to.aboutEqual(22000, 1e-6)
			end
		},
		-- fails when other node types or too few nodes count
		{
			name = "only ground nodes count, and fewer than 8 of them are not a graph: the next source is used",
			func = function()
				local list = nodes(10, 0, 1000, 0, 1000)

				for i = 1, 10 do
					list[i].type = 3 -- climb nodes
				end

				local b = B().Compute({nodes = list, world = {x0 = -3000, x1 = 3000, y0 = -3000, y1 = 3000}})

				expect(b.source).to.equal("world")

				b = B().Compute({nodes = nodes(7, 0, 1000, 0, 1000), world = {x0 = -3000, x1 = 3000, y0 = -3000, y1 = 3000}})
				expect(b.source).to.equal("world")
			end
		},
		-- fails when the cells of the in/out map are not turned into world units (a cell is 128 units, x2 and y2 are the LAST cell)
		{
			name = "the boxes of the in/out map give their cells' world rectangle, in the list form and in the named form",
			func = function()
				local b = B().Compute({boxes = {{0, -2, 1, 3, 4, 1, 0}, {layer = 1, x1 = 10, y1 = 10, x2 = 70, y2 = 70, state = 1, ceil = 0}}})

				expect(b.source).to.equal("zones")
				-- x from -256 to (70 + 1) * 128 = 9088, y from 128 to 9088, plus the minimum margin of 1024
				expect(b.x0).to.aboutEqual(-256 - 1024, 1e-6)
				expect(b.x1).to.aboutEqual(9088 + 1024, 1e-6)
				expect(b.y0).to.aboutEqual(128 - 1024, 1e-6)
				expect(b.y1).to.aboutEqual(9088 + 1024, 1e-6)
			end
		},
		-- fails when the two sources are not joined
		{
			name = "the nodes and the boxes are joined: the bounds hold both",
			func = function()
				local b = B().Compute({nodes = nodes(10, 0, 10000, 0, 10000), boxes = {{0, 100, 100, 120, 120}}})

				-- the boxes reach x = 121 * 128 = 15488 past the nodes' 10000
				expect(b.x1 >= 15488).to.beTrue()
				expect(b.x0 <= 0).to.beTrue()
			end
		},
		-- fails when the bounds can leave the world
		{
			name = "the bounds are cut at the world's box when that leaves a usable map",
			func = function()
				local b = B().Compute({nodes = nodes(10, 0, 20000, 0, 20000), world = {x0 = -500, x1 = 20500, y0 = 500, y1 = 30000}})

				expect(b.x0).to.aboutEqual(-500, 1e-6)
				expect(b.x1).to.aboutEqual(20500, 1e-6)
				expect(b.y0).to.aboutEqual(500, 1e-6)
				expect(b.y1 <= 30000).to.beTrue()

				-- a world box that would leave nothing is ignored
				local c = B().Compute({nodes = nodes(10, 0, 20000, 0, 20000), world = {x0 = 90000, x1 = 91000, y0 = 90000, y1 = 91000}})

				expect(c.x0 <= 0).to.beTrue()
				expect(c.x1 >= 20000).to.beTrue()
			end
		},
		-- fails when a map with no graph has no bounds
		{
			name = "no graph and no boxes: the world's box; no world either: a square around the player; nothing at all: a square around the origin",
			func = function()
				local b = B().Compute({world = {x0 = -1000, x1 = 9000, y0 = -2000, y1 = 4000}})

				expect(b.source).to.equal("world")
				expect(b.x0).to.aboutEqual(-1000, 1e-6)
				expect(b.y1).to.aboutEqual(4000, 1e-6)

				local p = B().Compute({player = {x = 3000, y = -4000}})

				expect(p.source).to.equal("player")
				expect(p.x0).to.aboutEqual(3000 - B().FALLBACK_HALF, 1e-6)
				expect(p.y1).to.aboutEqual(-4000 + B().FALLBACK_HALF, 1e-6)

				local d = B().Compute({})

				expect(d.source).to.equal("default")
				expect(d.x0).to.aboutEqual(-B().FALLBACK_HALF, 1e-6)
				expect(d.x1).to.aboutEqual(B().FALLBACK_HALF, 1e-6)
			end
		},
		-- fails when a tiny graph gives a map too small to look at
		{
			name = "a map smaller than 100 m a side is widened around its middle",
			func = function()
				local b = B().Compute({nodes = nodes(10, 1000, 1500, 2000, 2400)})
				local min = B().MIN_SIDE

				expect(b.x1 - b.x0 >= min - 1e-6).to.beTrue()
				expect(b.y1 - b.y0 >= min - 1e-6).to.beTrue()
				-- the middle stays where it was (the margin is the same on both sides)
				expect((b.x0 + b.x1) / 2).to.aboutEqual(1250, 1e-6)
				expect((b.y0 + b.y1) / 2).to.aboutEqual(2200, 1e-6)
			end
		},
		-- fails when the player can be outside the map
		{
			name = "the player is always inside the bounds, even when he stands where the graph does not reach",
			func = function()
				local b = B().Compute({nodes = nodes(10, 0, 10000, 0, 10000), player = {x = 30000, y = -20000}})

				expect(b.x1 >= 30000).to.beTrue()
				expect(b.y0 <= -20000).to.beTrue()
			end
		},
		-- fails when a bad input raises
		{
			name = "bad inputs never raise: not-a-table entries, NaN and infinity are skipped",
			func = function()
				local list = nodes(10, 0, 1000, 0, 1000)

				list[2] = "x"
				list[3] = {x = 0 / 0, y = 5, type = 2}
				list[4] = {x = math.huge, y = 5, type = 2}

				local ok, b = pcall(B().Compute, {nodes = list, boxes = {"a", {}, {0, 0 / 0, 1, 2, 3}}, world = {x0 = "a"}, player = {x = 0 / 0, y = 1}})

				expect(ok).to.beTrue()
				expect(type(b.x0)).to.equal("number")
				expect(b.x0 == b.x0).to.beTrue()
				expect(b.x1 > b.x0).to.beTrue()
				expect(B().Compute(nil).source).to.equal("default")
			end
		},
		-- fails when the span in metres is not computed with the unit of the game
		{
			name = "the span of the bounds in metres is the long side times 0.01905",
			func = function()
				local span = B().SpanMetres({x0 = 0, x1 = 10000, y0 = 0, y1 = 20000})

				expect(span).to.aboutEqual(20000 * 0.01905, 1e-6)
				expect(B().SpanMetres(nil)).to.equal(0)
			end
		}
	}
}
