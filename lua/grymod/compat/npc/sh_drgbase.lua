-- DrGBase (shared): what GryMod needs to know about a DrGBase nextbot. A nextbot of DrGBase is not an NPC for the engine (no IsNPC, no NPC state, no conditions) and keeps its own
-- relations (ENT:GetRelationship) and its own awareness (GetEnemy, HasSpotted, IsInSight), so the radar, the crosshair's friend cross and the binoculars' hologram would never know it.
-- This patch says it through the public API only: a creature provider (a nextbot is a living creature), one registry entry for every class built on `drgbase_nextbot` (its relation, its
-- awareness, whether it is dead) and the grenades of DrGBase for the grenade warning. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): the entries are low
-- priority data, every function answers nil for what is not DrGBase's, and nothing happens when DrGBase is not installed (no entity of that base ever exists).
--
-- Read from DrGBase's source (drgbase_nextbot/relationships.lua, awareness.lua, detection.lua, status.lua; proj_drg_grenade.lua), not documented elsewhere: the relation is asked as an ABSOLUTE one
-- (GetRelationship(ply, true)) because DrGBase answers "neutral" for a player with FL_NOTARGET (the camouflage), and the radar would drop every nextbot the moment the player cloaks.

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.RegisterTracked or not API.AddCreatureProvider then
	return -- sh_api.lua, sh_api_tracked.lua and sh_api_class.lua are included first (grymod_shared.lua)
end

local KEY = "compat.drgbase"
local STOCK = -50

API.AddCreatureProvider(KEY, function(ent)
	return ent.IsDrGNextbot == true
end)

-- What the nextbot is to the player, in the words of GryMod. Fear is no friendship and no hostility for the radar (the original game's rule for an NPC that is afraid).
-- (Server only in use: the registry's `relation` is asked by the server's relation chain; the client asks the server.)
local function relation(ply, ent)
	if not isfunction(ent.GetRelationship) then
		return nil
	end

	local disposition = ent:GetRelationship(ply, true)

	if disposition == D_LI then
		return "ally"
	end

	if disposition == D_HT then
		return "hostile"
	end

	return "neutral"
end

-- What it knows of the player: fighting (2) when he is its enemy, alerted (1) when it has spotted him (it heard or saw him, DrGBase remembers 30 seconds) and is not ignoring
-- him (a camouflaged player is ignored: DrGBase keeps the memory but cannot act on it), calm (0) otherwise. `exposure` follows: full when it sees him, half when it only knows
-- where he was.
local function awareness(ent, ply)
	local enemy = isfunction(ent.GetEnemy) and ent:GetEnemy() or nil
	local fighting = enemy ~= nil and enemy == ply
	local ignored = isfunction(ent.IsIgnored) and ent:IsIgnored(ply) == true
	local alerted = not fighting and not ignored and isfunction(ent.HasSpotted) and ent:HasSpotted(ply) == true

	if not fighting and not alerted then
		return 0, 0, false, false -- (the sight, a trace, is only asked for a nextbot that knows the player)
	end

	local seen = isfunction(ent.IsInSight) and ent:IsInSight(ply) == true or false

	if fighting then
		return 2, 1, seen, false
	end

	return 1, seen and 1 or 0.5, seen, not seen
end

-- A nextbot that is dying or dead (health 0 while its ragdoll is made, a downed one that gets up is "down", not dead) is not a contact.
local function dead(ent)
	return isfunction(ent.IsDead) and ent:IsDead() == true
end

local ok, reason = API.RegisterTracked(KEY, {
	base = "drgbase_nextbot",
	priority = STOCK,
	relation = relation,
	awareness = awareness,
	dead = dead
})

if not ok then
	MsgN("GryMod: the DrGBase entry of the tracked registry was refused: " .. tostring(reason))
end

-- ---------------------------------------------------------------------------------------------------------
-- The grenades of DrGBase (proj_drg_grenade and what packs build on it). The pin is out while the networked boolean DrGBaseUnpined is true, and the grenade is over once
-- DrGBaseDetonated is. The smoke grenade is no danger (it only makes smoke); the flash grenade is one that blinds, so it has its own label.
-- ---------------------------------------------------------------------------------------------------------

local GRENADE, FLASH, SMOKE = "proj_drg_grenade", "proj_drg_flashbang", "proj_drg_smoke_grenade"

-- Whether the entity is of the class `base` or built on it.
local function builtOn(ent, base)
	local class = API.ClassOf and API.ClassOf(ent) or ent:GetClass()

	if class == base or ent.Base == base then
		return true
	end

	if scripted_ents.IsBasedOn then
		local isBased, based = pcall(scripted_ents.IsBasedOn, class, base)

		return isBased and based == true
	end

	return false
end

local function armed(ent)
	return ent:GetNW2Bool("DrGBaseUnpined") == true and ent:GetNW2Bool("DrGBaseDetonated") ~= true
end

local function register(key, def)
	def.priority = STOCK

	local registered, why = API.RegisterTracked(key, def)

	if not registered then
		MsgN("GryMod: the DrGBase entry '" .. key .. "' of the tracked registry was refused: " .. tostring(why))
	end
end

register(KEY .. ".flash", {
	match = function(ent)
		return ent.IsDrGGrenade == true and builtOn(ent, FLASH)
	end,
	danger = {label = "FLASHBANG", type = "grenade", armed = armed}
})

register(KEY .. ".grenade", {
	match = function(ent)
		return ent.IsDrGGrenade == true and not builtOn(ent, SMOKE) and not builtOn(ent, FLASH)
	end,
	danger = {label = "GRENADE", type = "grenade", armed = armed}
})
