-- The objectives on the radar and the minimap: a marker source (GryMod.Radar.AddSource, cl_hud_radar_sources.lua) with one marker of the original's type 5
-- (the objective arrow) for each ACTIVE objective that has `radar` on: subtype 0 for a primary objective (a green glow, an arrow on the border of the radar when
-- the objective is beyond it) and 2 for a secondary one (the same in yellow); the original draws it at 75 percent size and alpha, which the radar does by
-- default for type 5. The radar's own window shows the minimap, so the compass radar and the minimap show the same markers (the big map is another display).
--
-- The source exists only while an eligible objective exists: it is added and taken away by the reporting hooks of the objectives (once for each real change) and
-- by the switch gry_hud_radarobjectives; the radar asks nothing when there is none. The player turns it off with gry_hud_radarobjectives (and every marker of
-- every source with gry_hud_radarmarkers).

GryMod = GryMod or {}

local Radar = GryMod.Radar

local OR = GryMod.ObjectivesRadar or {}
GryMod.ObjectivesRadar = OR

if not Radar or not Radar.AddSource or not GryMod.Objectives then
	return -- cl_objectives.lua and cl_hud_radar_sources.lua are included first (grymod_shared.lua)
end

local SwitchConVar = CreateClientConVar("gry_hud_radarobjectives", "1", true, false,
	"Show the objectives on the radar and the minimap (an arrow on the border when the objective is beyond the radar); 0 hides them")

OR.KEY = "objectives"

-- Whether an objective is on the radar: it is active and its `radar` is on. Primary and secondary alike (they differ in colour).
function OR.Eligible(o)
	return o.radar == true and o.state == "active"
end

local markers = {}
local none = {}

-- The markers of the radar for the objectives now (the source function): {pos, type = 5, subtype, id} for each eligible objective. The array and its tables are
-- reused at every call: the radar reads them at once and keeps nothing.
function OR.Source()
	local list = GryMod.Objectives.List()
	local count = 0

	for i = 1, #list do
		local o = list[i]

		if OR.Eligible(o) then
			count = count + 1

			local m = markers[count]

			if not m then
				m = {type = 5}
				markers[count] = m
			end

			m.pos = o.pos
			m.subtype = o.primary and 0 or 2
			m.id = o.id
		end
	end

	for i = #markers, count + 1, -1 do
		markers[i] = nil
	end

	return count > 0 and markers or none
end

local function wanted()
	if not SwitchConVar:GetBool() then
		return false
	end

	local list = GryMod.Objectives.List()

	for i = 1, #list do
		if OR.Eligible(list[i]) then
			return true
		end
	end

	return false
end

-- Adds the source when there is something to show and takes it away when there is not.
function OR.Refresh()
	if wanted() then
		if not Radar.HasSource(OR.KEY) then
			Radar.AddSource(OR.KEY, OR.Source)
		end
	else
		Radar.RemoveSource(OR.KEY)
	end
end

hook.Add("GryMod_ObjectiveAdded", "GryObjectiveRadar", function()
	OR.Refresh()
end)

hook.Add("GryMod_ObjectiveChanged", "GryObjectiveRadar", function()
	OR.Refresh()
end)

hook.Add("GryMod_ObjectiveRemoved", "GryObjectiveRadar", function()
	OR.Refresh()
end)

cvars.AddChangeCallback("gry_hud_radarobjectives", function()
	OR.Refresh()
end, "GryObjectiveRadar")

-- objectives that exist already (a reload of this file, or the file loaded after the first list)
OR.Refresh()
