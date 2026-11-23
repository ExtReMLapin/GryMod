-- The objectives demo: ONE command, gry_objectives_demo, that switches three sample objectives on and off so that the displays of the objectives (the markers
-- on the screen, the radar, the minimap, the banner and its sounds) can be seen without writing a line of Lua:
--   * a PRIMARY objective at a point 50 metres in front of the player who ran it, on the ground he faces;
--   * a SECONDARY objective at a point 200 metres in front of him;
--   * an objective that FOLLOWS the nearest NPC (onRemove = "complete": kill the NPC, or remove it, and the objective is finished, with its banner and sound).
-- Run it again to take them away. Only the administrators may (the host of a listen server and the single player are): the same rule as the administrators'
-- settings (GryMod.MayConfigure). It is also a button of the effects test window (cl_debug_window.lua), through the registry of its real commands
-- (GryMod.API.RegisterDebugCommand), so nothing in the window knows about it. It uses only the public objectives API (docs/api.md, "Objectives"). Nothing runs
-- by itself: everything happens when the command is run.

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.RegisterObjective then
	return -- sh_api.lua and sv_objectives.lua are included first (grymod_shared.lua)
end

local Demo = GryMod.ObjectivesDemo or {}
GryMod.ObjectivesDemo = Demo

Demo.IDS = {primary = "gry_demo_primary", secondary = "gry_demo_secondary", follow = "gry_demo_follow"}
Demo.PRIMARY_METRES, Demo.SECONDARY_METRES = 50, 200

local METRES_PER_UNIT = 0.01905
local CHEST = Vector(0, 0, 48) -- the points float at the height of the player's chest

-- A point `metres` in front of `origin` on the flat, for a player facing `yaw` degrees, a little above the ground.
function Demo.PointAhead(origin, yaw, metres)
	local radians = math.rad(yaw)
	local units = metres / METRES_PER_UNIT

	return origin + CHEST + Vector(math.cos(radians) * units, math.sin(radians) * units, 0)
end

-- The nearest valid entity of `candidates` to `pos`, or nil.
function Demo.Nearest(pos, candidates)
	local best, bestDistance

	for i = 1, #candidates do
		local ent = candidates[i]

		if IsValid(ent) then
			local distance = pos:DistToSqr(ent:GetPos())

			if not bestDistance or distance < bestDistance then
				best, bestDistance = ent, distance
			end
		end
	end

	return best
end

-- The NPCs of the map that are alive (replaced by the tests).
function Demo.FindNPCs()
	local found = {}

	for _, ent in ipairs(ents.GetAll()) do
		if ent:IsNPC() and ent:Health() > 0 then
			found[#found + 1] = ent
		end
	end

	return found
end

-- Whether the demo's objectives are on now.
function Demo.Active()
	for _, id in pairs(Demo.IDS) do
		if API.GetObjective(id) then
			return true
		end
	end

	return false
end

local function tell(ply, text)
	print("[GryMod] " .. text)

	if IsValid(ply) then
		ply:ChatPrint("[GryMod] " .. text)
	end
end

-- Takes the demo's objectives away. Returns how many there were.
function Demo.Stop()
	local count = 0

	for _, id in pairs(Demo.IDS) do
		if API.GetObjective(id) and API.RemoveObjective(id) then
			count = count + 1
		end
	end

	return count
end

-- Puts the demo's objectives on for `ply`. Returns true, or false and why (nothing was registered).
function Demo.Start(ply)
	if not IsValid(ply) then
		return false, "a player is needed: the points are in front of him"
	end

	local origin, yaw = ply:GetPos(), ply:EyeAngles().y

	local ok, reason = API.RegisterObjective(Demo.IDS.primary, {
		title = "Demo: primary objective",
		description = "A primary objective " .. Demo.PRIMARY_METRES .. " metres in front of you when you ran the demo.",
		primary = true,
		pos = Demo.PointAhead(origin, yaw, Demo.PRIMARY_METRES)
	})

	if not ok then
		return false, reason
	end

	API.RegisterObjective(Demo.IDS.secondary, {
		title = "Demo: secondary objective",
		description = "A secondary objective " .. Demo.SECONDARY_METRES .. " metres in front of you when you ran the demo.",
		primary = false,
		pos = Demo.PointAhead(origin, yaw, Demo.SECONDARY_METRES)
	})

	API.SetMainObjective(Demo.IDS.primary)

	local npc = Demo.Nearest(origin, Demo.FindNPCs())

	if npc then
		API.RegisterObjective(Demo.IDS.follow, {
			title = "Demo: follow the NPC",
			description = "This objective follows the nearest NPC. Kill it, or remove it: the objective is finished (onRemove = complete).",
			primary = true,
			ent = npc,
			onRemove = "complete"
		})
	else
		tell(ply, "Objectives demo: no NPC on the map, the third objective is left out (npc_create npc_citizen, then run the command twice)")
	end

	return true
end

-- Starts the demo, or stops it when it is on. Returns "started", "stopped", or nil and why.
function Demo.Toggle(ply)
	if Demo.Active() then
		Demo.Stop()
		tell(ply, "Objectives demo: off")

		return "stopped"
	end

	local ok, reason = Demo.Start(ply)

	if not ok then
		tell(ply, "Objectives demo: " .. tostring(reason))

		return nil, reason
	end

	tell(ply, "Objectives demo: on (run gry_objectives_demo again to stop it)")

	return "started"
end

-- The command: administrators only (the console has no position: it is refused too).
function Demo.Command(ply)
	if not IsValid(ply) then
		print("[GryMod] gry_objectives_demo: run it as a player (the points are put in front of him)")

		return nil, "no player"
	end

	if not GryMod.MayConfigure(ply) then
		tell(ply, "Objectives demo: administrators only")

		return nil, "denied"
	end

	return Demo.Toggle(ply)
end

concommand.Add("gry_objectives_demo", function(ply)
	Demo.Command(ply)
end, nil, "Toggles three sample objectives (a primary, a secondary, one that follows the nearest NPC) to see the objective displays. Administrators only.")

-- a button of the effects test window (its administrators' section is a loop over this registry)
if API.RegisterDebugCommand then
	API.RegisterDebugCommand("objectives_demo", {
		label = "Objectives demo (on / off)",
		run = function(ply)
			Demo.Toggle(ply)
		end
	})
end
