-- The extension API, server side (GryMod.API, see sh_api.lua and docs/api.md): the suit commands and events, the relation
-- chain and the HUD events sent to the clients. Design: docs/superpowers/specs/2026-11-21-extension-api-design.md.
--
-- The commands WRAP the existing code, they do not copy it: Player:SetNanosuitMode (sv_system.lua), the energy networked
-- float with the GryUseEnergy hook, GryMod.Malfunction (sv_malfunction.lua). Commands are functions (do this: they return
-- true, or false and a reason), events are hooks (this happened: GryMod_<Event>), a veto is a hook that can answer false.

GryMod = GryMod or {}

local API = GryMod.API

if not API then
	return -- sh_api.lua is included first (grymod_shared.lua)
end

local Modes = GryMod.Modes

local function isPlayer(ply)
	return IsValid(ply) and ply:IsPlayer()
end

-- ---------------------------------------------------------------------------------------------------------
-- The energy
-- ---------------------------------------------------------------------------------------------------------

-- The energy of the suit, 0 to 100 (nil for a player that is not valid).
function API.GetEnergy(ply)
	if not isPlayer(ply) then
		return nil
	end

	return ply:GetNWFloat("GryEnergy")
end

-- Sets the energy (clamped to 0..100). It counts as a use of the energy, like a drain: the recharge delay starts again
-- from the new value (the GryUseEnergy hook, which also gives the events below).
function API.SetEnergy(ply, amount)
	if not isPlayer(ply) then
		return false, "invalid player"
	end

	if not isnumber(amount) or amount ~= amount then
		return false, "invalid amount"
	end

	ply:SetNWFloat("GryEnergy", math.Clamp(amount, 0, 100))
	hook.Run("GryUseEnergy", ply)

	return true
end

-- Adds energy (a negative amount takes some), clamped to 0..100.
function API.AddEnergy(ply, amount)
	if not isPlayer(ply) then
		return false, "invalid player"
	end

	if not isnumber(amount) or amount ~= amount then
		return false, "invalid amount"
	end

	return API.SetEnergy(ply, ply:GetNWFloat("GryEnergy") + amount)
end

function API.RefillEnergy(ply)
	return API.SetEnergy(ply, 100)
end

function API.EmptyEnergy(ply)
	return API.SetEnergy(ply, 0)
end

-- GryMod_EnergyUsed(ply): the new name of the GryUseEnergy hook (which keeps firing). GryMod_EnergyEmpty(ply): the bar
-- has just reached 0 (fired once: not again until the bar has been above 0 at a use).
hook.Add("GryUseEnergy", "GryMod API energy", function(ply)
	hook.Run("GryMod_EnergyUsed", ply)

	if ply:GetNWFloat("GryEnergy") <= 0 then
		if not ply.gryApiEnergyEmpty then
			ply.gryApiEnergyEmpty = true
			hook.Run("GryMod_EnergyEmpty", ply)
		end
	else
		ply.gryApiEnergyEmpty = false
	end
end)

-- a new life starts with a full bar (sv_system.lua): the next time it empties is a new event
hook.Add("PlayerSpawn", "GryMod API energy", function(ply)
	ply.gryApiEnergyEmpty = false
end)

-- ---------------------------------------------------------------------------------------------------------
-- The mode
-- ---------------------------------------------------------------------------------------------------------

-- The modes a command may ask for (DROP is not a mode: it only drops the weapon)
local selectable = {
	[Modes.ARMOR] = true,
	[Modes.SPEED] = true,
	[Modes.CLOAK] = true,
	[Modes.STRENGTH] = true
}

function API.GetMode(ply)
	if not isPlayer(ply) then
		return nil
	end

	return ply.Nanosuit_mode or Modes.ARMOR
end

-- Puts the suit in a mode (Modes.ARMOR, SPEED, CLOAK, STRENGTH) and tells the player's client. Returns true, or false and
-- why it did not: "invalid player", "invalid mode", "dead", "malfunction" (the suit is down: armor), "disabled" (the suit is
-- off: armor), "vetoed" (a GryMod_CanSetMode handler said no). The rules are the ones of Player:SetNanosuitMode.
function API.SetMode(ply, mode)
	if not isPlayer(ply) then
		return false, "invalid player"
	end

	if not isnumber(mode) or not selectable[mode] then
		return false, "invalid mode"
	end

	return ply:SetNanosuitMode(mode, true)
end

-- ---------------------------------------------------------------------------------------------------------
-- The suit on or off (for an addon where the suit is not on the player's body yet)
-- ---------------------------------------------------------------------------------------------------------

function API.IsSuitEnabled(ply)
	if not isPlayer(ply) then
		return false
	end

	return not ply:GetNWBool("GryDisabled", false)
end

-- Switches the suit off (false) or on (true). Off: the mode is armor and cannot change, the armor takes no hit, the energy
-- neither drains nor recharges, the suit cannot go down in a malfunction, and the HUD is hidden on that client. It is a flag,
-- not a malfunction; it stays through death and respawn. Events: GryMod_SuitDisabled(ply), GryMod_SuitEnabled(ply), fired
-- when the state changes.
function API.SetSuitEnabled(ply, enabled)
	if not isPlayer(ply) then
		return false, "invalid player"
	end

	if not isbool(enabled) then
		return false, "invalid value"
	end

	local was = API.IsSuitEnabled(ply)

	if was == enabled then
		return true
	end

	ply:SetNWBool("GryDisabled", not enabled)

	if not enabled and ply.Nanosuit_mode ~= Modes.ARMOR then
		ply:SetNanosuitMode(Modes.ARMOR, true)
	end

	hook.Run(enabled and "GryMod_SuitEnabled" or "GryMod_SuitDisabled", ply)

	return true
end

-- ---------------------------------------------------------------------------------------------------------
-- Malfunctions
-- ---------------------------------------------------------------------------------------------------------

-- The suit goes down for `seconds` (the reason, a short text, goes to the GryMod_MalfunctionStart hook). Returns true, or false
-- and why not ("invalid player", "refused": dead, infinite armor, malfunctions off, suit off).
function API.StartMalfunction(ply, seconds, reason)
	if not isPlayer(ply) then
		return false, "invalid player"
	end

	if not GryMod.Malfunction.Start(ply, seconds, isstring(reason) and reason or "api") then
		return false, "refused"
	end

	return true
end

-- An EMP at a position: every living player within `radius` units (the default radius of gry_emp) goes down for `seconds`
-- (the game's 10 by default). Returns how many suits went down.
function API.EMP(pos, radius, seconds)
	if not isvector(pos) then
		return 0, "invalid position"
	end

	return GryMod.Malfunction.EMP(pos, radius, seconds)
end
