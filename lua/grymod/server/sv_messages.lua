-- The text lines of the HUD, server side (the movie is drawn by the client, cl_hud_messages_flash.lua; the shared data is sh_messages.lua).
--   * GryMod.API.ShowMessage(players, text, opts): shows a line on the HUD of these players. It is the HUD event "message" with the data
--     checked first, so it goes through the one net message the HUD events already use (gry_api_hud) and plays the picture and the
--     sound together. Returns what GryMod.API.HUDEvent returns (true and how many clients, or false and why).
--   * The suit's own lines that only the server knows (the client knows the others, see cl_hud_messages_flash.lua):
--       cloak_health   the camouflage is refused because the health is too low. The original does it at 24 health or less; GryMod has no
--                      such rule, so it is a setting of the server, gry_cloak_min_health, off (0) by default. It is a veto of the mode
--                      change like any addon's (the hook GryMod_CanSetMode), not a second path.
--       killed_friend  the player kills an ally (GryMod.API.Relation says "ally": a player of his team, an NPC that likes him). Nothing
--                      is punished: the original can hurt the player, GryMod only says it.
-- Nothing runs by itself: the lines hang on the hooks of the game's own events.

GryMod = GryMod or {}

local API = GryMod.API
local Messages = GryMod.Messages

if not API or not Messages then
	return -- sh_api.lua and sh_messages.lua are included first (grymod_shared.lua)
end

-- Shows a line on the HUD of `players` (a player or a list of them). `opts`: sound, duration, lane (see GryMod.Messages.Build).
function API.ShowMessage(players, text, opts)
	local data, reason = Messages.Build(text, opts)

	if not data then
		return false, reason
	end

	return API.HUDEvent(players, "message", data)
end

-- One of the suit's own lines (a key of GryMod.Messages.Lines) on the HUD of a player. The player's own setting for that line is read on
-- his side, so a client that turned it off shows nothing.
function Messages.SendLine(ply, key)
	if not Messages.Lines[key] or not IsValid(ply) or not ply:IsPlayer() then
		return false, "invalid line or player"
	end

	return API.HUDEvent(ply, "message", {line = key})
end

-- ---------------------------------------------------------------------------------------------------------
-- The camouflage refused at low health
-- ---------------------------------------------------------------------------------------------------------

-- The health at which the camouflage is refused (the original's: 24 of its 100), and under which the player may not put it on. 0 = no rule.
local minHealth = CreateConVar("gry_cloak_min_health", "0", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"The camouflage is refused when the health is this or less (the original game: 24); 0: no such rule", 0, 100)

-- Whether the camouflage is refused for this health (a field so that a test can say it).
function Messages.CloakRefusedAt(health)
	local limit = minHealth:GetInt()

	return limit > 0 and health <= limit
end

-- The veto: GryMod_CanSetMode(ply, mode) is asked when a mode is asked (not for armor, not for the mode the suit already has). False
-- refuses it, the client is told the real mode, and the line says why.
hook.Add("GryMod_CanSetMode", "GryMessagesCloakHealth", function(ply, mode)
	if mode ~= GryMod.Modes.CLOAK or not IsValid(ply) then
		return
	end

	if Messages.CloakRefusedAt(ply:Health()) then
		Messages.SendLine(ply, "cloak_health")

		return false
	end
end)

-- ---------------------------------------------------------------------------------------------------------
-- "You killed a friendly"
-- ---------------------------------------------------------------------------------------------------------

-- The player who is told, when `attacker` killed `victim`: the attacker when it is a player and the victim is an ally of his (never
-- himself). nil when nobody is told. A field so that a test can run it without the engine.
function Messages.FriendlyKiller(attacker, victim)
	if not IsValid(attacker) or not attacker:IsPlayer() or not IsValid(victim) or attacker == victim then
		return nil
	end

	if API.Relation(attacker, victim) ~= "ally" then
		return nil
	end

	return attacker
end

local function killed(victim, attacker)
	local killer = Messages.FriendlyKiller(attacker, victim)

	if killer then
		Messages.SendLine(killer, "killed_friend")
	end
end

hook.Add("OnNPCKilled", "GryMessagesFriendly", function(npc, attacker)
	killed(npc, attacker)
end)

hook.Add("PlayerDeath", "GryMessagesFriendly", function(victim, _, attacker)
	killed(victim, attacker)
end)
