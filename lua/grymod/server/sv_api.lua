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
	return isentity(ply) and IsValid(ply) and ply:IsPlayer()
end

-- ---------------------------------------------------------------------------------------------------------
-- The energy
-- ---------------------------------------------------------------------------------------------------------

-- The energy of the suit, 0 to 100 (nil for a player that is not valid).
function API.GetEnergy(ply)
	if not isPlayer(ply) then
		return nil
	end

	return ply:GetNW2Float("GryEnergy")
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

	ply:SetNW2Float("GryEnergy", math.Clamp(amount, 0, 100))
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

	return API.SetEnergy(ply, ply:GetNW2Float("GryEnergy") + amount)
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

	if ply:GetNW2Float("GryEnergy") <= 0 then
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

-- The modes a command may ask for
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

	return ply:SetNanosuitMode(mode, true, GryMod.ModeReasons.API)
end

-- ---------------------------------------------------------------------------------------------------------
-- The suit on or off (for an addon where the suit is not on the player's body yet)
-- ---------------------------------------------------------------------------------------------------------

function API.IsSuitEnabled(ply)
	if not isPlayer(ply) then
		return false
	end

	return not ply:GetNW2Bool("GryDisabled", false)
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

	ply:SetNW2Bool("GryDisabled", not enabled)

	if not enabled and ply.Nanosuit_mode ~= Modes.ARMOR then
		ply:SetNanosuitMode(Modes.ARMOR, true, GryMod.ModeReasons.DISABLED)
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

-- ---------------------------------------------------------------------------------------------------------
-- Attacks that are not bullets
-- ---------------------------------------------------------------------------------------------------------

-- The camouflage ends when the player attacks. The server sees every BULLET (the hook EntityFireBullets, sv_system.lua), so the weapons that fire bullets need nothing.
-- What it cannot see is an attack that is not a bullet: a swing of a knife, a thrown or launched grenade, a beam. A weapon that knows it just made one (or a patch for a
-- weapon base, lua/grymod/compat/) tells it here. `rightClick` is true when the attack came from the secondary fire: the player may have turned that rule off
-- (gry_cloak_altfire), and then it does not count. Returns true when the player was camouflaged (his client is told and ends the camouflage), or false and why not
-- ("invalid player", "not camouflaged"). Nothing is raised, whatever is given.
function API.ReportAttack(ply, rightClick)
	if not isPlayer(ply) then
		return false, "invalid player"
	end

	if ply.Nanosuit_mode ~= Modes.CLOAK then
		return false, "not camouflaged"
	end

	net.Start("gry_cloak_shot")
	net.WriteBool(rightClick == true)
	net.Send(ply)

	return true
end

API.AddFeature("attackreport")

-- ---------------------------------------------------------------------------------------------------------
-- Relation: ally, neutral or hostile, decided in ONE place
-- ---------------------------------------------------------------------------------------------------------

-- Order of the chain:
--   1. the relation providers of other addons (AddRelationProvider), the higher priority first, called through SafeCall;
--   2. the `relation` field of the registry of tracked entities (sh_api_tracked.lua: API._TrackedRelation);
--   3. the built-in rule (GryMod.Friendly.BuiltinRelation: the NPC's real attitude).
-- A provider returns "ally", "neutral" or "hostile", or nil for no opinion; anything else is ignored.
local VALID_RELATION = {ally = true, neutral = true, hostile = true}

local providers = {} -- sorted: higher priority first, then in the order of registration
local providerSeq = 0

local function sortProviders()
	table.sort(providers, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end

		return a.seq < b.seq
	end)
end

-- Adds (or replaces, with the same id) a provider: fn(ply, ent) -> "ally" | "neutral" | "hostile" | nil. The default
-- priority is 0. Returns true, or false and why not.
function API.AddRelationProvider(id, fn, priority)
	if not isstring(id) or id == "" then
		return false, "invalid id"
	end

	if not isfunction(fn) then
		return false, "invalid function"
	end

	if priority ~= nil and (not isnumber(priority) or priority ~= priority) then
		return false, "invalid priority"
	end

	API.RemoveRelationProvider(id)
	API.SafeCallReset("provider:" .. id) -- registering it again re-arms a provider that was disabled

	providerSeq = providerSeq + 1
	providers[#providers + 1] = {id = id, fn = fn, priority = priority or 0, seq = providerSeq, callId = "provider:" .. id}
	sortProviders()

	return true
end

-- Removes a provider; returns whether there was one.
function API.RemoveRelationProvider(id)
	for i, provider in ipairs(providers) do
		if provider.id == id then
			table.remove(providers, i)

			return true
		end
	end

	return false
end

-- An entity, or a table (a stand-in with an IsValid method): IsValid raises an error on a number, and a number is junk.
local function isobject(value)
	return isentity(value) or istable(value)
end

-- The hook point of the registry of tracked entities: sh_api_tracked.lua replaces it (its `relation` field, or nil). This stub
-- only answers while that file is not loaded.
API._TrackedRelation = API._TrackedRelation or function() return nil end

-- What the entity is to the player: "ally", "neutral" or "hostile". The only place that decides it (the crosshair's cross, the
-- radar's colour, the binoculars). Server only: the client asks (gry_friendly_ask).
function API.Relation(ply, ent)
	-- an invalid player or entity is nobody's friend and nobody's enemy, and no provider is asked about it
	if not isobject(ply) or not isobject(ent) or not IsValid(ply) or not IsValid(ent) then
		return "neutral"
	end

	-- the usual case, quick: no provider is registered
	if providers[1] then
		for i = 1, #providers do
			local provider = providers[i]
			local ok, relation = API.SafeCall(provider.callId, provider.fn, ply, ent)

			if ok and VALID_RELATION[relation] then
				return relation
			end
		end
	end

	local tracked = API._TrackedRelation(ply, ent)

	if tracked then
		return tracked
	end

	return GryMod.Friendly.BuiltinRelation(ply, ent)
end

-- ---------------------------------------------------------------------------------------------------------
-- HUD events: the server asks a client to play a HUD effect (the client side is cl_api.lua)
-- ---------------------------------------------------------------------------------------------------------

util.AddNetworkString("gry_api_hud")

-- Plays the HUD event `name` on the clients of `players` (a player, or a list of players; what is not a valid player is left
-- out). `data` is nil or a small table of numbers, strings and booleans (see GryMod.API.HUDEventLimits). The events that exist
-- are the built-in ones (boot, reboot, lost, malfunction) and the ones other addons register on the client. Returns true and
-- how many clients were asked, or false and why not.
function API.HUDEvent(players, name, data)
	local ok, reason = API.CheckHUDEvent(name, data)

	if not ok then
		return false, reason
	end

	local recipients = {}

	if isPlayer(players) then
		recipients[1] = players
	elseif istable(players) then
		for _, ply in ipairs(players) do
			if isPlayer(ply) then
				recipients[#recipients + 1] = ply
			end
		end
	end

	if #recipients == 0 then
		return false, "no valid recipient"
	end

	net.Start("gry_api_hud")
	API.WriteHUDEvent(name, data)
	net.Send(recipients)

	return true, #recipients
end
