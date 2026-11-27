-- Prop protection (Falco's Prop Protection, NADMOD PP): no use prompt on what the player may not use. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): it
-- uses GryMod's public GryMod.API.AddUsableFilter and what the prop protections already keep on the client, and does nothing when none is installed. Read in the public code of
-- FPP (github.com/FPtje/Falcos-Prop-protection, lua/fpp/) and NADMOD PP (github.com/Nebual/NadmodPP), NOT tried in a game (neither was installed when this was written).
--
-- A prop protection refuses the use key on what another player owns, ON THE SERVER (the hook PlayerUse): the prompt of GryMod would promise a use that does nothing. The client
-- knows the answer:
--   * FPP sends the touchability of each entity to the client; FPP.canTouchEnt(ent, "PlayerUse") reads its bit (nil while it has not arrived). The server only refuses when the setting
--     FPP_PLAYERUSE1.toggle is on (it is OFF by default, so most FPP servers refuse nothing here), and that setting is replicated to the client (FPP.Settings);
--   * NADMOD has NADMOD.PlayerCanTouch(ply, ent) on the client, and its setting NADMOD.PPConfig.use. A prop it knows no owner for is not refused: a map's props are the world's, which
--     its server hook lets through, and the client's own PlayerCanTouch says no for them.
-- The filter only takes a prompt away (false); it never adds one.

local API = GryMod.API

if not API or not API.AddUsableFilter then
	return -- cl_api.lua is included first (grymod_shared.lua)
end

local function fppRefuses(ent)
	if not istable(FPP) or not isfunction(FPP.canTouchEnt) or not istable(FPP.Settings) then
		return false
	end

	local setting = FPP.Settings.FPP_PLAYERUSE1

	if not istable(setting) or not tobool(setting.toggle) then
		return false
	end

	return FPP.canTouchEnt(ent, "PlayerUse") == false
end

local function nadmodRefuses(ent, ply)
	if not istable(NADMOD) or not isfunction(NADMOD.PlayerCanTouch) or not istable(NADMOD.PPConfig) or not tobool(NADMOD.PPConfig.use) then
		return false
	end

	local owners = NADMOD.PropOwners

	if not istable(owners) or owners[ent:EntIndex()] == nil then
		return false
	end

	return NADMOD.PlayerCanTouch(ply, ent) == false
end

API.AddUsableFilter("prop_protection", function(ent, ply)
	local ok, refuses = pcall(function()
		return fppRefuses(ent) or nadmodRefuses(ent, ply)
	end)

	if ok and refuses then
		return false
	end

	return nil
end)
