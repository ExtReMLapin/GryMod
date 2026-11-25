-- Tests of the big map's markers (lua/grymod/client/map/markers.lua), GLuaTest format, client realm: the registry of marker sources for third parties
-- (GryMod.Map.AddMarkerSource, the same record as GryMod.Radar.AddSource), what an objective becomes on the map, the 8 x 8 grid with its letters and
-- numbers, the size of an icon at a zoom and the pin of a marker that is off the window. Pure: positions are plain tables {x, y}.

local function M()
	local markers = GryMod and GryMod.Map and GryMod.Map.Markers

	expect(markers ~= nil).to.beTrue()

	return markers
end

local function objective(extra)
	local o = {id = "o1", title = "Find the key", description = "d", primary = true, main = false, state = "active", pos = {x = 100, y = 200, z = 0}, radar = true, marker = true}

	for k, v in pairs(extra or {}) do
		o[k] = v
	end

	return o
end

local function cleanup()
	pcall(function()
		local m = GryMod.Map.Markers

		m.RemoveSource("test_a")
		m.RemoveSource("test_b")
		m.RemoveSource("test_bad")
	end)
end

return {
	groupName = "GryMod big map markers",
	beforeEach = cleanup,
	afterEach = cleanup,
	cases = {
		-- fails without AddSource
		{
			name = "a source is added by a key with a function, replaced by the same key keeping its place, listed and removed; a bad one is refused",
			func = function()
				local m = M()

				expect(m.AddSource("test_a", function() return {} end)).to.beTrue()
				expect(m.AddSource("test_b", function() return {} end)).to.beTrue()
				expect(m.HasSource("test_a")).to.beTrue()

				local f2 = function() return {} end

				m.AddSource("test_a", f2)

				local keys = m.Sources()
				local at = {}

				for i, key in ipairs(keys) do
					at[key] = i
				end

				expect(at.test_a < at.test_b).to.beTrue()

				local ok, why = m.AddSource("test_a", "not a function")

				expect(ok).to.beFalse()
				expect(type(why)).to.equal("string")
				expect(m.AddSource(nil, f2)).to.beFalse()
				expect(m.RemoveSource("test_a")).to.beTrue()
				expect(m.RemoveSource("test_a")).to.beFalse()
				expect(m.HasSource("test_a")).to.beFalse()
			end
		},
		-- fails when the markers of the sources are not collected in the order of the sources
		{
			name = "Collect gathers the markers of every source in order, into a reused buffer, and clears what the buffer held past them",
			func = function()
				local m = M()

				m.AddSource("test_a", function() return {{pos = {x = 1, y = 1, z = 0}, type = 5, id = "a1"}, {pos = {x = 2, y = 2, z = 0}, type = 7, id = "a2"}} end)
				m.AddSource("test_b", function() return {{pos = {x = 3, y = 3, z = 0}, type = 1, id = "b1"}} end)

				local buffer = {"old1", "old2", "old3", "old4", "old5"}
				local count = m.Collect(buffer)

				expect(count).to.equal(3)
				expect(buffer[1].id).to.equal("a1")
				expect(buffer[3].id).to.equal("b1")
				expect(buffer[4]).to.beNil()
				expect(buffer[5]).to.beNil()
			end
		},
		-- fails when a source that raises stops the others or stays for ever
		{
			name = "a source that raises is skipped, and removed after three errors in a row; the others go on",
			func = function()
				local m = M()
				local calls = 0

				m.AddSource("test_bad", function()
					calls = calls + 1
					error("boom")
				end)
				m.AddSource("test_a", function() return {{pos = {x = 1, y = 1, z = 0}, type = 5}} end)

				local buffer = {}

				expect(m.Collect(buffer)).to.equal(1)
				expect(m.HasSource("test_bad")).to.beTrue()
				m.Collect(buffer)
				m.Collect(buffer)
				expect(m.HasSource("test_bad")).to.beFalse()
				expect(calls).to.equal(3)
				expect(m.Collect(buffer)).to.equal(1)
			end
		},
		-- fails when the number of markers is not limited
		{
			name = "no more than MAX_MARKERS markers are collected",
			func = function()
				local m = M()

				m.AddSource("test_a", function()
					local list = {}

					for i = 1, m.MAX_MARKERS + 50 do
						list[i] = {pos = {x = i, y = i, z = 0}, type = 1}
					end

					return list
				end)

				expect(m.Collect({})).to.equal(m.MAX_MARKERS)
			end
		},
		-- fails when an objective is not turned into a type 5 marker with the right subtype
		{
			name = "an active primary objective is a type 5 marker of subtype 0 with its title as the label, a secondary one has subtype 2, the main one is marked",
			func = function()
				local m = M()
				local list = {objective(), objective({id = "o2", title = "Second", primary = false}), objective({id = "o3", title = "Main", main = true})}
				local out = {}
				local n = m.FromObjectives(list, false, out)

				expect(n).to.equal(3)
				expect(out[1].type).to.equal(5)
				expect(out[1].subtype).to.equal(0)
				expect(out[1].label).to.equal("Find the key")
				expect(out[1].id).to.equal("o1")
				expect(out[1].main).to.beFalse()
				expect(out[1].pos.x).to.equal(100)
				expect(out[2].subtype).to.equal(2)
				expect(out[3].main).to.beTrue()
			end
		},
		-- fails when finished objectives are drawn when they must be hidden, or not greyed when shown
		{
			name = "a done or failed objective is hidden by default, and drawn greyed (no ring, half alpha) when the player asks for it",
			func = function()
				local m = M()
				local list = {objective({state = "done", main = true}), objective({id = "o2", state = "failed"}), objective({id = "o3"})}
				local out = {}

				expect(m.FromObjectives(list, false, out)).to.equal(1)
				expect(out[1].id).to.equal("o3")

				expect(m.FromObjectives(list, true, out)).to.equal(3)
				expect(out[1].finished).to.beTrue()
				expect(out[1].main).to.beFalse()
				expect(out[1].alpha).to.aboutEqual(0.45, 1e-9)
				expect(out[3].finished).to.beFalse()
			end
		},
		-- fails when an objective that asked not to be on the radar and map is drawn, or one without a position
		{
			name = "an objective with radar false, or with no position, is left out",
			func = function()
				local m = M()
				local list = {objective({radar = false}), objective({id = "o2", pos = false}), objective({id = "o3", pos = {x = 0 / 0, y = 1, z = 0}}), objective({id = "o4"})}
				local out = {}

				expect(m.FromObjectives(list, false, out)).to.equal(1)
				expect(out[1].id).to.equal("o4")
			end
		},
		-- fails when the grid is not 8 x 8 over the bounds, letters down and numbers across
		{
			name = "the grid is 8 x 8 over the bounds: the number counts across the screen (toward -Y), the letter down the screen (toward -X), A1 is the top left",
			func = function()
				local m = M()
				local b = {x0 = 0, x1 = 800, y0 = 0, y1 = 800}

				-- top left of the screen = largest X, largest Y
				local letter, number, text = m.GridRef(b, 799, 799)

				expect(letter).to.equal("A")
				expect(number).to.equal(1)
				expect(text).to.equal("A1")

				-- bottom right = smallest X, smallest Y
				letter, number, text = m.GridRef(b, 1, 1)
				expect(text).to.equal("H8")

				-- x = 450 is the 4th row from the top (x from 800 down: 800-700 A, 700-600 B, 600-500 C, 500-400 D), y = 250 is the 6th column from the left
				letter, number = m.GridRef(b, 450, 250)
				expect(letter).to.equal("D")
				expect(number).to.equal(6)

				-- outside the bounds the cell is the nearest one
				local _, n2 = m.GridRef(b, 400, -500)

				expect(n2).to.equal(8)
				expect(m.GridRef(nil, 1, 1)).to.beNil()
			end
		},
		-- fails when the grid lines are not at the edges of the cells
		{
			name = "the grid lines: nine lines each way at a multiple of an eighth of the bounds",
			func = function()
				local m = M()
				local xs, ys = m.GridLines({x0 = 0, x1 = 800, y0 = 100, y1 = 900})

				expect(#xs).to.equal(9)
				expect(#ys).to.equal(9)
				expect(xs[1]).to.equal(0)
				expect(xs[9]).to.equal(800)
				expect(ys[2]).to.equal(200)
				expect(ys[9]).to.equal(900)
			end
		},
		-- fails when icons do not grow with the zoom the way the original's do
		{
			name = "an icon grows slowly with the zoom: (zoom + 2) * 0.25 times its own size, a scale in percent applies",
			func = function()
				local m = M()

				expect(m.IconSize(1, 20, 100)).to.aboutEqual(15, 1e-9)
				expect(m.IconSize(8, 20, 100)).to.aboutEqual(50, 1e-9)
				-- an icon stops growing at zoom 8, whatever the zoom of a big map
				expect(m.IconSize(60, 20, 100)).to.aboutEqual(50, 1e-9)
				expect(m.IconSize(1000, 20, 50)).to.aboutEqual(25, 1e-9)
				expect(m.IconSize(2, 20, 50)).to.aboutEqual(10, 1e-9)
				-- a scale that is no number is 100 percent
				expect(m.IconSize(2, 20, nil)).to.aboutEqual(20, 1e-9)
				expect(m.IconSize(2, 20, -5)).to.aboutEqual(20, 1e-9)
			end
		},
		-- fails when a marker off the window is not pinned to its edge
		{
			name = "a marker off the window is pinned to the edge, with a margin; one inside stays where it is",
			func = function()
				local m = M()
				local rect = {x = 100, y = 100, w = 400, h = 300}
				local x, y, pinned = m.Pin(300, 200, rect, 10)

				expect(x).to.equal(300)
				expect(y).to.equal(200)
				expect(pinned).to.beFalse()

				x, y, pinned = m.Pin(900, 50, rect, 10)
				expect(x).to.equal(490)
				expect(y).to.equal(110)
				expect(pinned).to.beTrue()

				x, y, pinned = m.Pin(-40, 1000, rect, 10)
				expect(x).to.equal(110)
				expect(y).to.equal(390)
			end
		},
		-- fails when the colours of the objectives are not the radar's (green primary, yellow secondary)
		{
			name = "the style: a primary objective is green, a secondary one yellow, a finished one grey; units are dots, an explosion ring is a ring, a team mate is blue",
			func = function()
				local m = M()
				local shape, r, g, b = m.Style({type = 5, subtype = 0})

				expect(shape).to.equal("diamond")
				expect(g > r and g > b).to.beTrue()

				shape, r, g, b = m.Style({type = 5, subtype = 2})
				expect(r > 200 and g > 150 and b < 100).to.beTrue()

				shape, r, g, b = m.Style({type = 5, subtype = 0, finished = true})
				expect(r == g and g == b).to.beTrue()

				expect((m.Style({type = 1}))).to.equal("dot")
				expect((m.Style({type = 6}))).to.equal("ring")

				shape, r, g, b = m.Style({type = 7})
				expect(shape).to.equal("dot")
				expect(b > r).to.beTrue()

				-- an unknown type is a dot
				expect((m.Style({type = 99}))).to.equal("dot")
				expect((m.Style({}))).to.equal("dot")
			end
		},
		{
			-- fails when FromObjectives drops the own flag (the big map could not tell the player's points from the missions) or Style gives them the mission colours
			name = "an own objective (a point the player put on the map) keeps its flag in its marker and is drawn blue; finished, it is grey like any other",
			func = function()
				local m = M()
				local out = {}
				local list = {
					{id = "gry_user_1", title = "Camp", primary = false, state = "active", pos = Vector(1, 2, 3), radar = true, own = true},
					{id = "m", title = "Mission", primary = true, state = "active", pos = Vector(4, 5, 6), radar = true}
				}

				expect(m.FromObjectives(list, false, out)).to.equal(2)
				expect(out[1].own).to.beTrue()
				expect(out[2].own).to.beFalse()

				local shape, r, g, b = m.Style(out[1])

				expect(shape).to.equal("diamond")
				expect(b > r and b > g).to.beTrue()

				shape, r, g, b = m.Style(out[2])
				expect(g > b).to.beTrue()

				shape, r, g, b = m.Style({type = 5, subtype = 2, own = true, finished = true})
				expect(r == g and g == b).to.beTrue()
			end
		}
	}
}
