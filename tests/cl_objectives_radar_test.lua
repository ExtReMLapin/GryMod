-- Tests of the objectives on the radar and the minimap (GryMod.ObjectivesRadar, lua/grymod/client/cl_objectives_radar.lua), GLuaTest format, client realm.
-- The radar's marker source API (GryMod.Radar.AddSource, cl_hud_radar_sources.lua) draws what a source returns: here one marker of type 5 for each ACTIVE
-- objective that has `radar` on, subtype 0 for a primary one (green) and 2 for a secondary one (yellow); the radar itself puts the arrow on the border of
-- the radar when the objective is beyond it. The minimap is the radar's own window: the same markers are on both. The engine is replaced where a case needs it
-- and put back in afterEach inside a pcall. Each case names the production change whose absence makes it fail.

local OR = GryMod.ObjectivesRadar
local Radar = GryMod.Radar -- the public API: AddSource, RemoveSource, HasSource
local Feed = GryMod.FlashRadar -- the radar's own placement and collection

local saved = {}
local convarsSaved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function setConVar(name, value)
	local convar = GetConVar(name)

	if convarsSaved[name] == nil then
		convarsSaved[name] = convar:GetString()
	end

	convar:SetString(value)
end

local function restore()
	for i = #saved, 1, -1 do
		local entry = saved[i]
		entry[1][entry[2]] = entry[3]
	end

	saved = {}

	for name, value in pairs(convarsSaved) do
		GetConVar(name):SetString(value)
	end

	convarsSaved = {}
end

local function objective(id, extra)
	local o = {id = id, title = "Title " .. id, description = "", primary = true, main = false, state = "active", pos = Vector(100, 200, 300), radar = true, marker = true}

	for k, v in pairs(extra or {}) do
		o[k] = v
	end

	return o
end

local function listOf(...)
	local list = {...}

	stub(GryMod.Objectives, "List", function() return list end)

	return list
end

return {
	groupName = "GryMod objectives on the radar",
	beforeEach = function()
		setConVar("gry_hud_radarobjectives", "1")
		Radar.RemoveSource(OR.KEY)
	end,
	afterEach = function()
		pcall(function()
			Radar.RemoveSource(OR.KEY)
		end)
		pcall(restore)
		pcall(OR.Refresh)
	end,
	cases = {
		{
			-- fails without OR.Eligible: only an active objective with `radar` on is on the radar (the original takes a finished or failed one off the map)
			name = "Eligible: active with radar on; done, failed or radar off are not",
			func = function()
				expect(OR.Eligible(objective("a"))).to.beTrue()
				expect(OR.Eligible(objective("a", {primary = false}))).to.beTrue()
				expect(OR.Eligible(objective("a", {state = "done"}))).to.beFalse()
				expect(OR.Eligible(objective("a", {state = "failed"}))).to.beFalse()
				expect(OR.Eligible(objective("a", {radar = false}))).to.beFalse()
			end
		},
		{
			-- fails without OR.Source: type 5, subtype 0 for a primary objective (green) and 2 for a secondary one (yellow), the position and the id of the objective
			name = "Source: one type 5 marker for each eligible objective, subtype 0 primary and 2 secondary",
			func = function()
				listOf(objective("a"), objective("b", {primary = false, pos = Vector(1, 2, 3)}), objective("c", {state = "done"}), objective("d", {radar = false}))

				local markers = OR.Source()
				expect(#markers).to.equal(2)
				expect(markers[1].type).to.equal(5)
				expect(markers[1].subtype).to.equal(0)
				expect(markers[1].id).to.equal("a")
				expect(markers[1].pos == Vector(100, 200, 300)).to.beTrue()
				expect(markers[2].type).to.equal(5)
				expect(markers[2].subtype).to.equal(2)
				expect(markers[2].id).to.equal("b")
				expect(markers[2].pos == Vector(1, 2, 3)).to.beTrue()
			end
		},
		{
			-- fails without the reuse in OR.Source: the radar asks every frame, the source must not build new tables for nothing
			name = "Source: the same array and the same marker tables at every call",
			func = function()
				listOf(objective("a"))

				local first = OR.Source()
				local marker = first[1]
				local second = OR.Source()

				expect(first == second).to.beTrue()
				expect(second[1] == marker).to.beTrue()

				listOf()
				expect(#OR.Source()).to.equal(0)
			end
		},
		{
			-- fails without the shape the radar needs: its own placement accepts the markers of the source (type 5 inside the radar, on its border outside it)
			name = "the markers go through the radar's own placement: type 5 inside is the glow frame 25 (primary) or 27 (secondary), beyond the radar the arrow 26 or 28",
			func = function()
				listOf(objective("near"), objective("nearSecondary", {primary = false}))

				local markers = OR.Source()
				local near = {markers[1], markers[2]}
				-- the player is at the origin: a point 1 m away is inside, one 5 km away is beyond
				near[1].pos = Vector(50, 0, 0)
				near[2].pos = Vector(50, 0, 0)

				local placed = Feed.MarkerEntries(Vector(0, 0, 0), 0, near, 2, nil, nil)
				expect(placed[1].frame).to.equal(25)
				expect(placed[2].frame).to.equal(27)

				near[1].pos = Vector(100000, 0, 0)
				near[2].pos = Vector(100000, 0, 0)
				placed = Feed.MarkerEntries(Vector(0, 0, 0), 0, near, 2, nil, nil)
				expect(placed[1].frame).to.equal(26)
				expect(placed[2].frame).to.equal(28)
			end
		},
		{
			-- fails without OR.Refresh: the source is added with the first eligible objective and taken away with the last, so that the radar asks nothing for no objective
			name = "Refresh: the source exists only while an objective is eligible, and only with the option on",
			func = function()
				local list = listOf()

				OR.Refresh()
				expect(Radar.HasSource(OR.KEY)).to.beFalse()

				list[1] = objective("a")
				OR.Refresh()
				expect(Radar.HasSource(OR.KEY)).to.beTrue()

				list[1].state = "done"
				OR.Refresh()
				expect(Radar.HasSource(OR.KEY)).to.beFalse()

				list[1].state = "active"
				OR.Refresh()
				expect(Radar.HasSource(OR.KEY)).to.beTrue()

				setConVar("gry_hud_radarobjectives", "0")
				OR.Refresh()
				expect(Radar.HasSource(OR.KEY)).to.beFalse()
			end
		},
		{
			-- fails without the reporting hooks in the module
			name = "the objective hooks call Refresh: the first objective adds the source, the removal of the last takes it away",
			func = function()
				local list = listOf()
				local added = hook.GetTable()["GryMod_ObjectiveAdded"]["GryObjectiveRadar"]
				local removed = hook.GetTable()["GryMod_ObjectiveRemoved"]["GryObjectiveRadar"]
				local changed = hook.GetTable()["GryMod_ObjectiveChanged"]["GryObjectiveRadar"]

				expect(added).to.exist()
				expect(removed).to.exist()
				expect(changed).to.exist()

				list[1] = objective("a")
				added("a", list[1])
				expect(Radar.HasSource(OR.KEY)).to.beTrue()

				list[1] = nil
				removed("a", {}, "removed")
				expect(Radar.HasSource(OR.KEY)).to.beFalse()
			end
		},
		{
			-- fails without the entry of the radar settings: the switch exists, on by default
			name = "gry_hud_radarobjectives is a setting of the player, on by default",
			func = function()
				expect(GetConVar("gry_hud_radarobjectives")).to.exist()
				expect(GetConVar("gry_hud_radarobjectives"):GetDefault()).to.equal("1")
			end
		},
		{
			-- fails without Radar.CollectMarkers reading the source: the radar's own collection returns what OR.Source gives
			name = "the radar's collection returns the markers of the objectives once the source is added",
			func = function()
				listOf(objective("a"))
				OR.Refresh()

				local buffer = {}
				local count = Feed.CollectMarkers(buffer)
				local found = false

				for i = 1, count do
					if buffer[i].id == "a" and buffer[i].type == 5 then
						found = true
					end
				end

				expect(found).to.beTrue()
			end
		}
	}
}
