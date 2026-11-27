-- Glide (StyledStrike's vehicle base, https://github.com/StyledStrike/gmod-glide): what the registries of GryMod need to know about its vehicles and its missiles. Shared: both
-- realms run these declarations (the radar and the grenade warning read them on the server, the binoculars and the warning's drawing on the client).
--
-- Glide is a vehicle base made of scripted entities. A vehicle is NOT an engine vehicle: `ent:IsVehicle()` is false, and the player sits on a separate seat (a
-- `prop_vehicle_prisoner_pod` child of the vehicle), so `ply:GetVehicle()` answers the seat. Glide gives `ply:GlideGetVehicle()` (lua/glide/sh_player.lua), `ent.IsGlideVehicle`,
-- `ent.VehicleType` (autorun/sh_glide.lua: CAR 1, MOTORCYCLE 2, HELICOPTER 3, PLANE 4, TANK 5, BOAT 6), `ent:GetDriver()` (the first seat only), `ent:GetAllPlayers()` (server),
-- `ent:GetChassisHealth()`, `ent:GetIsLocked()`; a missile is the class `glide_missile` (or one built on it) with its shooter in the field `attacker` (server).
-- Everything here was READ in Glide's code (lua/entities/base_glide/*, lua/entities/glide_missile/*); the API functions are in its wiki, its hooks are not.
--
-- Public API only (docs/compat.md): the vehicle providers, the registry of tracked entities and the registry of usable things. The file does nothing when Glide is not there: a
-- player Glide does not know has no vehicle, and no entity is built on a class of Glide. The server part (the respawn, the lock-on, the attacks) is sv_glide.lua, the client part
-- (the camera, the name tag, the dashboard, the key) cl_glide.lua.

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.AddVehicleProvider or not API.RegisterTracked or not API.RegisterUsable then
	return -- sh_api.lua, sh_api_tracked.lua, sh_api_vehicles.lua and sh_api_usable.lua are included first (grymod_shared.lua)
end

-- What the adapter keeps for its other files and for the tests (a field the tests may replace).
local Compat = GryMod.GlideCompat or {}
GryMod.GlideCompat = Compat

-- ---------------------------------------------------------------------------------------------------------
-- The vehicle of a player, its driver, its kind
-- ---------------------------------------------------------------------------------------------------------

local VEHICLE_HELICOPTER, VEHICLE_PLANE, VEHICLE_BOAT = 3, 4, 6

-- "air" for the helicopters and the planes, "water" for the boats, "ground" for the rest (cars, motorcycles, tanks).
function Compat.KindOf(vehicle)
	local kind = vehicle.VehicleType

	if kind == VEHICLE_HELICOPTER or kind == VEHICLE_PLANE then
		return "air"
	end

	if kind == VEHICLE_BOAT then
		return "water"
	end

	return "ground"
end

-- The vehicle (not the seat) the player sits in, or nil: Glide's own function.
function Compat.VehicleOf(ply)
	local fn = ply.GlideGetVehicle

	if not isfunction(fn) then
		return nil
	end

	return fn(ply)
end

-- The player at the wheel: the first seat's driver, for a Glide vehicle only (another vehicle is left to the next provider and to the entity's own GetDriver).
function Compat.DriverOf(vehicle)
	if vehicle.IsGlideVehicle ~= true or not isfunction(vehicle.GetDriver) then
		return nil
	end

	return vehicle:GetDriver()
end

API.AddVehicleProvider("glide", {ofPlayer = Compat.VehicleOf, driver = Compat.DriverOf, kind = Compat.KindOf})

-- ---------------------------------------------------------------------------------------------------------
-- The registry of tracked entities: the vehicles on the radar, the heavy ones, the missiles of the grenade warning
-- ---------------------------------------------------------------------------------------------------------

-- A wreck is not a contact: the chassis has no health left (a vehicle that can explode is removed by Glide at that moment).
local function dead(ent)
	if ent.hasExploded == true then
		return true
	end

	return isfunction(ent.GetChassisHealth) and ent:GetChassisHealth() <= 0
end

-- The players in all the seats, for the colour of the vehicle (the server only has the list: ENT:GetAllPlayers).
local function crew(ent)
	if isfunction(ent.GetAllPlayers) then
		return ent:GetAllPlayers() or nil
	end

	return nil
end

-- A Glide vehicle faces +X (its forward speed is the X of its local velocity), not the +90 degrees of the engine's vehicles.
local function facing(ent)
	if isfunction(ent.GetForward) then
		return ent:GetForward()
	end

	return nil
end

local function register(key, def)
	local ok, reason = API.RegisterTracked(key, def)

	if not ok then
		MsgN("GryMod: the Glide entry '" .. key .. "' of the tracked registry was refused: " .. tostring(reason))
	end
end

-- The more special classes first (the priority): the first entry that matches wins. All of them are above the stock entries (-100).
-- A trailer has no seat and nobody in it: never a contact, but a heavy thing that crushes.
register("glide_trailers", {base = "base_glide_trailer", radar = "never", heavy = true, priority = 30})

-- A motorcycle is a contact, not a heavy machine.
register("glide_motorcycles", {base = "base_glide_motorcycle", type = "machine", radar = "scan", priority = 20, dead = dead, crew = crew, facing = facing})

-- Helicopters and planes: the flying unit's icon.
register("glide_aircraft", {base = "base_glide_aircraft", type = "flying", radar = "scan", heavy = true, priority = 10, dead = dead, crew = crew, facing = facing})

-- Cars, tanks, boats and every vehicle of another addon built on base_glide: the rectangle, once the binoculars scanned it.
register("glide_vehicles", {base = "base_glide", type = "machine", radar = "scan", heavy = true, priority = 0, dead = dead, crew = crew, facing = facing})

-- The missile (glide_missile and every missile an addon builds on it): the player who fired it is in the field `attacker` (the engine's owner is the vehicle, or the
-- player's hands). It flies from its creation, so it is armed at once. A missile that follows a target is only a danger for the one it follows: the server leaves the target on the
-- entity (the networked entity GryGlideTarget, the armed reader runs five times a second for each missile), the client's `warnFor` compares it with the player and his vehicle.
local function armed(ent)
	local target = ent.target

	if IsValid(target) and isfunction(ent.SetNW2Entity) then
		if not isfunction(ent.GetNW2Entity) or ent:GetNW2Entity("GryGlideTarget") ~= target then
			ent:SetNW2Entity("GryGlideTarget", target)
		end
	end

	return true
end

local function ownerOf(ent)
	return ent.attacker
end

local function warnFor(ent, ply)
	if not isfunction(ent.GetNW2Entity) then
		return true
	end

	local target = ent:GetNW2Entity("GryGlideTarget")

	if not IsValid(target) then
		-- not known: a rocket that follows nothing warns whoever is near, one that follows somebody we cannot see (out of view) is not for us
		return not (isfunction(ent.GetHasTarget) and ent:GetHasTarget() == true)
	end

	if target == ply then
		return true
	end

	local mine = API.GetVehicleOf(ply)

	if IsValid(mine) and target == mine then
		return true
	end

	local seat = isfunction(ply.GetVehicle) and ply:GetVehicle() or nil

	return IsValid(seat) and target == seat
end

register("glide_missiles", {
	base = "glide_missile",
	danger = {label = "MISSILE", type = "missile", ownMissile = true, armed = armed, ownerOf = ownerOf, warnFor = warnFor}
})

-- ---------------------------------------------------------------------------------------------------------
-- The use prompt: ENTER VEHICLE
-- ---------------------------------------------------------------------------------------------------------

-- The use key acts on the vehicle itself (ENT:Use), the seats are not solid. A trailer has no seat. A locked vehicle is dimmed (the key does nothing for a stranger), unless the
-- server lets everybody into locked vehicles (Glide's convar glide_always_can_enter_locked_vehicles).
local function isTrailer(ent)
	local ok, based = pcall(scripted_ents.IsBasedOn, ent:GetClass(), "base_glide_trailer")

	return ok and based == true
end

local function enterable(ent)
	return ent.IsGlideVehicle == true and not isTrailer(ent)
end

local function ready(ent)
	if not isfunction(ent.GetIsLocked) or not ent:GetIsLocked() then
		return true
	end

	local always = GetConVar("glide_always_can_enter_locked_vehicles")

	return always ~= nil and always:GetBool()
end

do
	local ok, reason = API.RegisterUsable("glide_enter", {match = enterable, icon = "enter", text = "ENTER VEHICLE", use = "once", ready = ready})

	if not ok then
		MsgN("GryMod: the Glide entry of the usable registry was refused: " .. tostring(reason))
	end
end
