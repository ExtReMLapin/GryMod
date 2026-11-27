-- LVS (the "LUA Vehicle System" framework of SpaxscE, github.com/SpaxscE/lvs_base, and the packs built on it: cars, planes, helicopters, tanks, Star Wars...). Shared: both
-- realms run it. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): it uses only the public API and does NOTHING when LVS is not installed (the
-- registrations are made when the `LVS` table exists: at load when LVS came first, else when LVS announces itself with its hook "LVS:Initialize", else at InitPostEntity).
--
-- What was read in LVS's code (nothing of it is changed or copied; see docs/compat.md for the list of what was only read and not tried in a game):
--   * a vehicle is a scripted entity, `ENT.LVS == true`, based on `lvs_base` (`lvs_base_wheeldrive`, `lvs_tank_wheeldrive`, `lvs_base_fighterplane`, `lvs_base_helicopter`,
--     `lvs_base_starfighter`, ...). It is not an NPC, not a nextbot, and `IsVehicle()` is false: only its SEATS are `prop_vehicle_prisoner_pod`. `Player:GetVehicle()` answers
--     the seat; `Player:lvsGetVehicle()` answers the vehicle.
--   * `ent:GetDriver()`, `GetAITEAM()` (0 friendly to everyone, 1 and 2 teams, 3 hostile to everyone), `GetHP()` are networked; `GetEveryone()` lists the occupants;
--     `GetVehicleType()` says "car", "tank", "plane", "helicopter", "starfighter", "boat"...; `IsDestroyed()` and `_LastAITarget` (the target of an AI vehicle) are server fields.
--   * the projectiles that are entities: `lvs_missile` (+ `lvs_protontorpedo`, `lvs_concussionmissile`) and `lvs_bomb` (+ `lvs_helicopter_combine_bomb`). `GetActive()` and
--     `GetNWTarget()` are networked, `GetAttacker()` is a server method.
--
-- What it registers (all with the keys "lvs..."): the vehicle provider (the vehicle of a player, its driver, air / ground / water), the radar entries (the icon, the relation
-- by LVS team, a wreck is no contact, the occupants, the heading, what an AI vehicle knows of the player), the grenade warning for the missiles and the bombs, the use prompt of
-- a vehicle, the icon of LVS's tools. The server half (hit filter, shots) is sv_lvs.lua, the client half (camera, locked vehicles) cl_lvs.lua.

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.RegisterTracked or not API.AddVehicleProvider then
	return -- sh_api.lua, sh_api_tracked.lua and sh_api_vehicles.lua are included first (grymod_shared.lua)
end

local L = GryMod.CompatLVS or {}
GryMod.CompatLVS = L

-- The classes of the projectiles that are entities (LVS and its packs: all of them are one of these five).
L.MISSILES = {"lvs_missile", "lvs_protontorpedo", "lvs_concussionmissile"}
L.BOMBS = {"lvs_bomb", "lvs_helicopter_combine_bomb"}

-- The vehicle types that fly, and the one that floats (GetVehicleType of the base classes).
local AIR = {plane = true, helicopter = true, starfighter = true}
local WATER = {boat = true}

-- A projectile that has no target is a danger to the player it flies at, within this cosine of the angle between its heading and the way to him (about 25 degrees).
L.HEADING_COSINE = 0.9

-- Whether LVS is installed (its table exists: lvs_init.lua creates it before anything of the framework runs).
function L.Present()
	return istable(LVS)
end

-- Whether the entity is an LVS vehicle (the marker `ENT.LVS` of lvs_base; a seat, a wheel or a player never has it).
function L.IsVehicle(ent)
	return (isentity(ent) or istable(ent)) and IsValid(ent) and ent.LVS == true
end

-- ---------------------------------------------------------------------------------------------------------
-- The vehicle of a player
-- ---------------------------------------------------------------------------------------------------------

-- The LVS vehicle the player sits in (driver, passenger or gunner), or nil. `Player:GetVehicle()` is the invisible seat, `lvsGetVehicle` is the parent of the seat that has the marker.
function L.VehicleOf(ply)
	if not (isentity(ply) or istable(ply)) or not IsValid(ply) or not isfunction(ply.lvsGetVehicle) then
		return nil
	end

	local vehicle = ply:lvsGetVehicle()

	if IsValid(vehicle) then
		return vehicle
	end

	return nil
end

-- The player at the wheel (not the passengers), or nil. Only for an LVS vehicle: the engine's own vehicles also have a GetDriver and are not ours to answer for.
function L.DriverOf(vehicle)
	if not L.IsVehicle(vehicle) or not isfunction(vehicle.GetDriver) then
		return nil
	end

	local driver = vehicle:GetDriver()

	if IsValid(driver) then
		return driver
	end

	return nil
end

-- "air", "water" or "ground" from the type the base class declares.
function L.KindOf(vehicle)
	local kind = isfunction(vehicle.GetVehicleType) and vehicle:GetVehicleType() or nil

	if AIR[kind] then
		return "air"
	end

	if WATER[kind] then
		return "water"
	end

	return "ground"
end

-- ---------------------------------------------------------------------------------------------------------
-- Teams
-- ---------------------------------------------------------------------------------------------------------

-- The LVS team a player belongs to now: the one of the vehicle he sits in, else his own (`lvsGetAITeam`, which the vehicle he left gave him). 0 when LVS cannot say.
function L.TeamOfPlayer(ply)
	local vehicle = L.VehicleOf(ply)

	if vehicle and isfunction(vehicle.GetAITEAM) then
		return vehicle:GetAITEAM()
	end

	if isfunction(ply.lvsGetAITeam) then
		return ply:lvsGetAITeam()
	end

	return 0
end

-- The relation of two LVS teams, from LVS's own rules for who shoots whom (lvs_base/sv_ai.lua): a team 0 is friendly to everyone and is never a target, a team 3 is hostile to
-- everyone, 1 and 2 are teams. nil when one of them is 0: LVS has no opinion (the occupants decide, see `crew`).
function L.TeamRelation(mine, theirs)
	if not isnumber(mine) or not isnumber(theirs) or mine == 0 or theirs == 0 then
		return nil
	end

	if mine == 3 or theirs == 3 then
		return "hostile"
	end

	if mine == theirs then
		return "ally"
	end

	return "hostile"
end

-- What an LVS vehicle is to the player: by teams (the player's own team being the one of his vehicle when he sits in one). nil when a team is 0.
function L.VehicleRelation(ply, vehicle)
	if not isfunction(vehicle.GetAITEAM) then
		return nil
	end

	return L.TeamRelation(L.TeamOfPlayer(ply), vehicle:GetAITEAM())
end

-- The occupants of a vehicle (a list of players), for the colour of the vehicle when its team has no opinion.
function L.CrewOf(vehicle)
	if isfunction(vehicle.GetEveryone) then
		return vehicle:GetEveryone()
	end

	return {}
end

-- Whether a vehicle is a wreck (server: IsDestroyed is a method of the server's entity; the client does not know).
function L.IsWreck(vehicle)
	return isfunction(vehicle.IsDestroyed) and vehicle:IsDestroyed() == true
end

-- The world forward vector of the vehicle (lvs: the front of the model is +X, the same as GetForward, for a car, a plane and a helicopter).
function L.Facing(vehicle)
	return vehicle:GetForward()
end

-- What an AI vehicle knows of a player: LVS has no alert level, only a target. An AI vehicle whose target (`_LastAITarget`, chosen every two seconds, only when it can see it) is
-- this player, or the vehicle he sits in, is fighting him (level 2, exposure 1, seen); anything else is calm (level 0). A vehicle that nobody pilots by AI knows nothing.
function L.Awareness(vehicle, ply)
	if not isfunction(vehicle.GetAI) or vehicle:GetAI() ~= true then
		return 0, 0, false, false
	end

	local target = vehicle._LastAITarget

	if not IsValid(target) then
		return 0, 0, false, false
	end

	if target == ply or target == L.VehicleOf(ply) then
		return 2, 1, true, false
	end

	return 0, 0, false, false
end

-- ---------------------------------------------------------------------------------------------------------
-- Projectiles
-- ---------------------------------------------------------------------------------------------------------

-- Whether a missile or a bomb is a danger to THIS player: a missile that locked something (GetNWTarget) is a danger to the player who is that thing, or sits in it; a projectile
-- with no target (a bomb, a missile that was not guided) is one to the player it flies at. The player's own vehicle counts as himself.
function L.AimedAt(projectile, ply)
	local target = isfunction(projectile.GetNWTarget) and projectile:GetNWTarget() or nil

	if IsValid(target) then
		return target == ply or target == L.VehicleOf(ply)
	end

	if not isfunction(projectile.GetVelocity) or not isfunction(projectile.GetPos) then
		return false
	end

	local velocity = projectile:GetVelocity()
	local speed = velocity:Length()

	if speed < 1 then
		return false
	end

	local subject = L.VehicleOf(ply) or ply
	local center = isfunction(subject.WorldSpaceCenter) and subject:WorldSpaceCenter() or subject:GetPos()
	local way = center - projectile:GetPos()
	local distance = way:Length()

	if distance < 1 then
		return true
	end

	return velocity:Dot(way) / (speed * distance) >= L.HEADING_COSINE
end

-- The player who fired it (the attacker LVS keeps on the server), or nil: an AI vehicle's missile has the vehicle as its attacker.
function L.OwnerOf(projectile)
	if not isfunction(projectile.GetAttacker) then
		return nil
	end

	local attacker = projectile:GetAttacker()

	if IsValid(attacker) and isfunction(attacker.IsPlayer) and attacker:IsPlayer() then
		return attacker
	end

	return nil
end

-- Whether the projectile is in flight: LVS turns `Active` on when it launches it (before that it hangs under its vehicle).
function L.IsFlying(projectile)
	return isfunction(projectile.GetActive) and projectile:GetActive() == true
end

-- ---------------------------------------------------------------------------------------------------------
-- The use prompt
-- ---------------------------------------------------------------------------------------------------------

-- Whether the key would do nothing for this player (a locked vehicle, a wreck, a team the server keeps out): no prompt. The same rules as lvs_base's IsUseAllowed, on what the client
-- can read.
function L.UseRefused(vehicle, ply)
	if not L.IsVehicle(vehicle) then
		return false
	end

	if isfunction(vehicle.GetlvsLockedStatus) and vehicle:GetlvsLockedStatus() == true then
		return true
	end

	if isfunction(vehicle.GetHP) and vehicle:GetHP() <= 0 then
		return true
	end

	if istable(LVS) and LVS.TeamPassenger and isfunction(vehicle.GetAITEAM) and isfunction(ply.lvsGetAITeam) then
		local mine, theirs = ply:lvsGetAITeam(), vehicle:GetAITEAM()

		if theirs ~= mine and mine ~= 0 and theirs ~= 0 then
			return true
		end
	end

	return false
end

-- ---------------------------------------------------------------------------------------------------------
-- The registrations
-- ---------------------------------------------------------------------------------------------------------

local KEY = "lvs"

-- LVS's tools and placers (repair, fuel, mines, spike strips): they have no gun.
local WEAPON_TOOLS = {"weapon_lvsrepair", "weapon_lvsfuelfiller", "weapon_lvsmines", "weapon_lvsspikestrip"}

-- The fields the radar entries share.
local function radarEntry(bases, icon)
	return {
		base = bases,
		type = icon,
		radar = "hostile",
		relation = function(ply, vehicle) return L.VehicleRelation(ply, vehicle) end,
		dead = L.IsWreck,
		crew = L.CrewOf,
		facing = L.Facing,
		awareness = L.Awareness
	}
end

local function dangerEntry(classes, base, label, kind)
	return {
		class = classes,
		base = base,
		danger = {
			label = label,
			type = kind,
			armed = L.IsFlying,
			ownerOf = L.OwnerOf,
			ownMissile = true,
			warnFor = L.AimedAt
		}
	}
end

-- Registers everything of this file. Idempotent (a second call replaces what the first made); false when LVS is not installed, and then nothing is registered.
function L.Install()
	if not L.Present() then
		return false
	end

	API.AddVehicleProvider(KEY, {ofPlayer = L.VehicleOf, driver = L.DriverOf, kind = L.KindOf})

	-- the flying ones first: the first entry that matches wins
	API.RegisterTracked("lvs_air", radarEntry({"lvs_base_fighterplane", "lvs_base_helicopter", "lvs_base_starfighter"}, "flying"))
	API.RegisterTracked("lvs_vehicles", radarEntry("lvs_base", "machine"))

	API.RegisterTracked("lvs_missiles", dangerEntry(L.MISSILES, "lvs_missile", "MISSILE", "missile"))
	API.RegisterTracked("lvs_bombs", dangerEntry(L.BOMBS, "lvs_bomb", "BOMB", "bomb"))

	API.RegisterUsable("lvs_vehicle", {base = "lvs_base", icon = "enter", text = "ENTER VEHICLE", use = "repeat"})

	-- LVS's own tools (repair, fuel) and its placers have no gun: no fire mode icon
	for _, class in ipairs(WEAPON_TOOLS) do
		API.RegisterWeapon(class, {fire = "none"})
	end

	return true
end

-- Takes everything of this file's registrations away (tests, or an addon that wants LVS handled its own way); the hooks stay, they only ask Install again when LVS announces itself.
function L.Uninstall()
	API.RemoveVehicleProvider(KEY)

	for _, key in ipairs({"lvs_air", "lvs_vehicles", "lvs_missiles", "lvs_bombs"}) do
		API.UnregisterTracked(key)
	end

	API.UnregisterUsable("lvs_vehicle")

	for _, class in ipairs(WEAPON_TOOLS) do
		API.UnregisterWeapon(class)
	end
end

-- LVS before GryMod: its table is already there. LVS after GryMod: it announces itself (the hook runs at the end of its framework's load), and InitPostEntity is the net under that.
if L.Present() then
	L.Install()
end

hook.Add("LVS:Initialize", "GryMod compat LVS", function()
	L.Install()
end)

hook.Add("InitPostEntity", "GryMod compat LVS", function()
	L.Install()
end)
