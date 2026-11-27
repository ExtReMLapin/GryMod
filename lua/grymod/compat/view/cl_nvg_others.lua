-- Other night visions (client): when another addon's night vision is on, GryMod's key must not switch a second one on over it (two green amplifiers, two colour passes in an order
-- the game does not fix). This patch refuses GryMod's switch on through the veto `GryMod_CanUseView("nightvision", reason)` (docs/api.md "The view"); a night vision that is already on is
-- not touched. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): nothing happens when no other night vision is on, and it only runs when GryMod asks to switch on.
--
-- What it knows how to read (public source; none is installed here, the checks are made with stand-ins, tests/cl_compat_view_parts_test.lua):
--   NVScript ("Night Vision", Workshop 224378049, about 210 thousand subscribers; READ in two forks of its code, not in the addon itself: HaloArmory cl_night_vision.lua:182,526, SandEv-Legacy
--     cl_nightvision.lua:11): its effect is a hook "NV_FX" on RenderScreenspaceEffects or on HUDPaintBackground that exists only while it is on.
--   JMod (cl_hud.lua:270-292): the armor's effects ply.EZarmor.effects.nightVision or .nightVisionWP, and not a dead device (ply.EZarmor.blackvision).
-- NOT read: Modern Warfare NVGs (Workshop 2532012185, 209 thousand) and Arctic's night vision GCAL (2389553185, 103 thousand): they have no public source and are not installed here. A
-- reader for one goes in `N.Sources` (a table of key -> function(ply) returning true while it is on), or is another addon's own `GryMod_CanUseView` handler.

GryMod = GryMod or {}

local N = GryMod.CompatOtherNV or {}
GryMod.CompatOtherNV = N

local function hooked(event, id)
	local hooks = hook.GetTable()[event]

	return hooks ~= nil and hooks[id] ~= nil
end

N.Sources = {
	nvscript = function()
		return hooked("RenderScreenspaceEffects", "NV_FX") or hooked("HUDPaintBackground", "NV_FX")
	end,
	jmod = function(ply)
		local armor = ply.EZarmor
		local effects = istable(armor) and armor.effects

		if not istable(effects) or armor.blackvision then
			return false
		end

		return effects.nightVision == true or effects.nightVisionWP == true
	end
}

-- The key of the first other night vision that is on, or nil.
function N.Active(ply)
	if not IsValid(ply) then
		return nil
	end

	for key, source in pairs(N.Sources) do
		local ok, active = pcall(source, ply)

		if ok and active == true then
			return key
		end
	end

	return nil
end

-- The handler of GryMod_CanUseView: false refuses the night vision.
function N.Veto(kind, reason)
	if kind ~= "nightvision" then
		return nil
	end

	if N.Active(LocalPlayer()) ~= nil then
		return false
	end

	return nil
end

hook.Add("GryMod_CanUseView", "GryMod compat other night vision", N.Veto)
