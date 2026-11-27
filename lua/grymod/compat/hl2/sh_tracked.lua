-- The Half-Life 2 entities of the registry of tracked entities, registered as DATA through the public API (GryMod.API.RegisterTracked),
-- exactly as an addon would do it: no private table, no special path. The radar reads the icons of the NPC classes here (the
-- machines, the flying units, the big ones) and the grenade warning reads the dangerous projectiles here (what to call them, which
-- ones the player fires, how the server knows that one is armed). Shared: both realms run the same declarations; the `armed`
-- readers only ever run on the server (the client cannot read the engine's internal variables: it is told through the networked
-- bool GryArmed, see server/sv_grenade.lua) and the radar fields only matter to the server's radar (docs/api.md).
--
-- The entries have a low priority: an entry registered by an addon for the same class beats them, whatever the order of loading.

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.RegisterTracked then
	return -- sh_api.lua and sh_api_tracked.lua are included first (grymod_shared.lua)
end

local STOCK = -100

local function register(key, def)
	def.priority = STOCK

	local ok, reason = API.RegisterTracked(key, def)

	if not ok then
		MsgN("GryMod: the stock entry '" .. key .. "' of the tracked registry was refused: " .. tostring(reason))
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- The icons of the radar: 1 infantry (the default), 2 helicopters and flying units, 3 other vehicles and machines; `size = "big"`
-- draws it twice the size (the original doubles the Hunter and the Alien warrior). The big machines come first: the first entry
-- that matches wins.
-- ---------------------------------------------------------------------------------------------------------

-- The strider and the hunter are heavy machines (heavy: a hit of theirs that breaks the armor puts the suit down) and keep a camouflaged
-- player in mind (cloakBlind: the cloak makes them forget him, see server/sv_cloak_ai.lua).
register("hl2_machines_big", {class = {"npc_strider", "npc_hunter"}, type = "machine", size = "big", heavy = true, cloakBlind = true})

-- The gunship and the helicopter: heavy machines too, drawn as the other flying units. Before hl2_flying, which would take them first.
register("hl2_flying_heavy", {class = {"npc_combinegunship", "npc_helicopter"}, type = "flying", heavy = true})

-- The manhack is the third unit that keeps a camouflaged player in mind.
register("hl2_flying_manhack", {class = "npc_manhack", type = "flying", cloakBlind = true})

register("hl2_flying", {
	class = {"npc_combinedropship", "npc_cscanner", "npc_clawscanner"},
	type = "flying"
})

register("hl2_machines", {
	class = {"npc_turret_floor", "npc_turret_ceiling", "npc_turret_ground", "npc_rollermine", "npc_combine_camera"},
	type = "machine"
})

-- The vehicles: the rectangle icons of the radar, once the binoculars have scanned them (radar = "scan"), in the colour of their driver
-- (the relation of the driver, GryMod's Radar.Describe). The Buggy and the Jalopy are both prop_vehicle_jeep. A seat of the spawn menu
-- is prop_vehicle_prisoner_pod and is not here on purpose: another addon registers its own vehicles through the API.
register("hl2_vehicles", {
	class = {"prop_vehicle_jeep", "prop_vehicle_airboat", "prop_vehicle_apc", "prop_vehicle_crane"},
	type = "machine", radar = "scan"
})

register("hl2_antlion_guards", {class = {"npc_antlionguard", "npc_antlionguardian"}, size = "big"})

-- ---------------------------------------------------------------------------------------------------------
-- The dangerous projectiles of the grenade warning (client: cl_hud_grenade_flash.lua, server: sv_grenade.lua). The server marks
-- each one with the networked bool "GryArmed": true while it is ACTIVE, that is really a danger coming (a grenade whose fuse runs,
-- a mine in the air, a rocket in flight...), false for an inert one lying around (the spawn menu makes them inert, a Half-Life 2
-- grenade is only armed when thrown or picked up). What "active" means for each class was measured on live entities, see
-- docs/superpowers/plans/2026-11-21-grenade-entities.md. A projectile held in the player's hands (or by the gravity gun) is never
-- active, whatever the reader says: the server checks that itself.
-- ---------------------------------------------------------------------------------------------------------

-- Units a second under which a projectile counts as at rest.
local MOVING = 50
local FALLING = 300 -- a bomb that is not ticking yet but falls this fast is coming at someone
local HOPPING = 100 -- a mine in the air (its hop is 300 and more, the clicking before it under 40)

local function speed(ent)
	return ent:GetVelocity():Length()
end

-- npc_grenade_frag: the fuse runs. detonate = m_flDetonateTime, the seconds left before the explosion: the engine tells minus the
-- game time of an unarmed grenade. Measured: a grenade made at rest has -CurTime(), SetTimer 3 gives 3 counting down, a pick-up
-- by the player arms it with 1.5.
register("hl2_frag", {
	class = "npc_grenade_frag",
	danger = {
		label = "FRAG GRENADE", type = "grenade",
		armed = function(ent)
			return (ent:GetInternalVariable("m_flDetonateTime") or 0) > 0
		end
	}
})

-- grenade_ar2 and rpg_missile are fired live (m_bIsLive is true from their creation) and have no other state: in flight. A player
-- fires them: they never warn that player (ownMissile).
register("hl2_rifle_grenade", {
	class = "grenade_ar2",
	danger = {
		label = "RIFLE GRENADE", type = "grenade", ownMissile = true,
		armed = function(ent)
			return speed(ent) > MOVING
		end
	}
})

register("hl2_missile", {
	class = "rpg_missile",
	danger = {
		label = "MISSILE", type = "missile", ownMissile = true,
		armed = function(ent)
			return speed(ent) > MOVING
		end
	}
})

-- grenade_helicopter: m_bActivated turns on at the first impact and the 5 seconds count down; before it, a bomb that falls fast
-- is coming
register("hl2_bomb", {
	class = "grenade_helicopter",
	danger = {
		label = "BOMB", type = "bomb",
		armed = function(ent)
			return ent:GetInternalVariable("m_bActivated") == true or speed(ent) > FALLING
		end
	}
})

-- combine_mine: m_iMineState 1 on the ground, 3 armed (a foe is near), 4 triggered (it clicks, then jumps)
-- It is also a radar contact once scanned: the type 4 icon (a rectangle with a disc, never produced by the original's HUD code).
register("hl2_mine", {
	class = "combine_mine",
	type = "device", radar = "scan",
	-- hostile, until the player has taken it with the gravity gun and put it down: then it is his (m_bPlacedByPlayer)
	relation = function(ply, ent)
		return ent:GetInternalVariable("m_bPlacedByPlayer") == true and "ally" or "hostile"
	end,
	danger = {
		label = "MINE", type = "mine",
		armed = function(ent)
			return ent:GetInternalVariable("m_iMineState") == 4 and speed(ent) > HOPPING
		end
	}
})

-- prop_combine_ball: m_bLaunched from the weapon's fire or a launcher, m_bHeld by a gravity gun (then it is not a danger coming,
-- the player has it). Electric: a hit of it is always a strong shock for the suit (shock, see server/sv_mechanics.lua).
register("hl2_energy_ball", {
	class = "prop_combine_ball",
	shock = "strong",
	danger = {
		label = "ENERGY BALL", type = "energy", ownMissile = true,
		armed = function(ent)
			return ent:GetInternalVariable("m_bLaunched") == true and ent:GetInternalVariable("m_bHeld") ~= true
		end
	}
})
