-- ZBase (shared): what GryMod needs to know about a ZBase NPC. ZBase NPCs are real engine NPCs wrapped in Lua, so the relation and the alert state are the engine's and need nothing. Three
-- things need a word. (1) ZBase REPLACES Entity:GetClass (with its option zbase_custom_class, on by default): a ZBase hunter answers "zb_hunter", and every table of GryMod that is keyed by class
-- (the icon, the heavy machines, the use prompt's talkers) would not know it: the class provider gives the real class back (the flag ZBASE_SkipClassNameWrapper, ZBase's own way to read it).
-- (2) When ZBase replaces an NPC it leaves the ORIGINAL one in the world, invisible, with FL_NOTARGET and no thinking but with its health (ZBaseNPCCopy_DullState): it must never be a
-- contact of the radar, never be scanned and never be a hostile in the binoculars' hologram. (3) The rocket and the mortar of the ZBase NPCs are dangers for the grenade warning.
-- Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): nothing happens when ZBase is not installed (its global ZBaseInstalled is not there), and no function raises an
-- error. READ IN ZBase'S SOURCE ONLY (zbase/npc_base/sh_classname.lua, zbase/sh_globals_pri.lua, entities/zb_rocket.lua): ZBase was not installed when this was written, it needs the library
-- of its author which is not available here: tried with stand-ins only.

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.RegisterTracked or not API.AddClassProvider then
	return -- sh_api.lua, sh_api_tracked.lua and sh_api_class.lua are included first (grymod_shared.lua)
end

local KEY = "compat.zbase"

-- The real class of a ZBase NPC. Nothing (nil) for everything else, and at once when ZBase is not installed: it is asked for every entity that GryMod looks up.
API.AddClassProvider(KEY, function(ent)
	if _G.ZBaseInstalled == nil or not isfunction(ent.GetNWBool) or not ent:GetNWBool("IsZBaseNPC", false) then
		return nil
	end

	local before = _G.ZBASE_SkipClassNameWrapper

	_G.ZBASE_SkipClassNameWrapper = true

	local ok, class = pcall(ent.GetClass, ent)

	_G.ZBASE_SkipClassNameWrapper = before

	if ok and isstring(class) and class ~= "" then
		return class
	end

	return nil
end)

-- The copy ZBase leaves of an NPC it replaced. Priority well above the stock entries: whatever the class of the original says (a Combine soldier, hostile to the player), it is nothing.
local ok, reason = API.RegisterTracked(KEY .. ".dull", {
	match = function(ent)
		return _G.ZBaseInstalled ~= nil and isfunction(ent.GetNWBool) and ent:GetNWBool("ZBaseNPCCopy_DullState", false) == true
	end,
	radar = "never",
	scan = false,
	relation = "neutral",
	priority = 500
})

if not ok then
	MsgN("GryMod: the ZBase entry of the tracked registry was refused: " .. tostring(reason))
end

-- The projectiles of the ZBase NPCs that hurt (the spit is small and falls at once: no warning). They are physics entities, in flight while they move; the rocket also carries a real
-- rpg_missile that never moves of itself (the warning's stock entry for the missile reads it as at rest, so only the rocket warns).
local MOVING = 50

local function moving(ent)
	return ent:GetVelocity():Length() > MOVING
end

for class, label in pairs({zb_rocket = "ROCKET", zb_mortar = "MORTAR"}) do
	local registered, why = API.RegisterTracked(KEY .. "." .. class, {
		class = class,
		priority = -50,
		danger = {label = label, type = class == "zb_rocket" and "missile" or "bomb", armed = moving}
	})

	if not registered then
		MsgN("GryMod: the ZBase entry '" .. class .. "' of the tracked registry was refused: " .. tostring(why))
	end
end
