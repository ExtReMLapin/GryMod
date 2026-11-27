-- ZBase (client). (1) The player who controls a ZBase NPC sees through the NPC's camera (ZBase's own CalcView): another camera has the view, so GryMod's zoom and the binoculars must not take it
-- (GryMod.API.AddCameraOwner). (2) The use key on an allied ZBase NPC makes it follow the player (or stop following him): the prompt says so, FOLLOW or STOP FOLLOWING. Part of the compatibility
-- patches (lua/grymod/compat/, docs/compat.md): nothing happens when ZBase is not installed. Read from ZBase's source (zbase/controller/cl.lua, zbase/sh_hooks.lua "ZBaseUse", npc_base/init.lua
-- CanFollowPlayers): ZBase needs a library that is not available here, so this was tried with stand-ins only.

local API = GryMod.API

if not API or not API.AddCameraOwner or not API.RegisterUsable then
	return -- cl_api.lua and sh_api_usable.lua are included first (grymod_shared.lua)
end

local KEY = "compat.zbase"

API.AddCameraOwner(KEY, function(ply)
	return IsValid(ply:GetNWEntity("ZBASE_ControllerCamEnt", NULL))
end)

-- Whether this NPC of ZBase can follow a player (its definition says so, ZBase's setting zbase_followplayers is on).
local function canFollow(ent)
	local npcs = _G.ZBaseNPCs

	if not istable(npcs) then
		return false
	end

	local name = ent:GetNWString("ZBASE_CustomClass", "")

	if name == "" then
		name = ent:GetClass()
	end

	local def = npcs[name]

	if not istable(def) or def.CanFollowPlayers ~= true then
		return false
	end

	local setting = GetConVar("zbase_followplayers")

	return setting == nil or setting:GetBool()
end

local function following(ent, ply)
	local list = ply.ZBaseFollowHaloEnts

	if not istable(list) then
		return false
	end

	for i = 1, #list do
		if list[i] == ent then
			return true
		end
	end

	return false
end

local ok, reason = API.RegisterUsable(KEY .. ".follow", {
	match = function(ent)
		return _G.ZBaseInstalled ~= nil and ent:GetNWBool("IsZBaseNPC", false) and API.ClientRelation(ent) == "ally" and canFollow(ent)
	end,
	icon = "use",
	text = function(ent, ply)
		return following(ent, ply) and "STOP FOLLOWING" or "FOLLOW"
	end,
	use = "repeat",
	priority = -50
})

if not ok then
	MsgN("GryMod: the ZBase use entry was refused: " .. tostring(reason))
end
