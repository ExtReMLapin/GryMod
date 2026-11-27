-- VManip (client): a library of view model animations (1.2 million subscribers; the base of the flashlight, quick grenade and other addons' hands). It does its work in PostDrawViewModel
-- (cl_vmanip.lua:403) and gives the camera an angle of its own (CalcView "VManip_Cam", :604). While GryMod's binoculars are up the view model is not drawn (gry_binoculars_hide_weapon:
-- the hook PreDrawViewModel answers true, and PostDrawViewModel does not come then), so an animation that starts, or one that is playing, would freeze on one frame, its camera angle
-- with it. This patch asks VManip not to start an animation while the binoculars are up (its hook VManipPrePlayAnim, :263: an answer of false cancels it; documented in its code and used by
-- its own ArcCW and MW Base fixes, :668-685) and ends the one that plays when they go up (VManip:Remove()). Part of the compatibility patches (lua/grymod/compat/, docs/compat.md):
-- nothing happens without VManip, no Think, nothing is written. The state comes from the hook GryMod_BinocularsToggled(wanted) (docs/events.md), so it follows both zooms.
--
-- Not done here, on purpose: VManip's CalcView rebuilds a view with the field of view it was given (:617-625), which would cancel the binoculars' zoom for the length of an animation;
-- with no animation allowed while the binoculars are up that cannot happen, and GryMod's CalcView ignores the nested call of VManip (its `znear` is `true`, see docs/api.md).

GryMod = GryMod or {}

local V = GryMod.CompatVManip or {}
GryMod.CompatVManip = V

local up = false

-- the hook of VManip: false cancels the animation, nothing leaves it as it is
function V.PrePlay(name)
	if up then
		return false
	end

	return nil
end

function V.OnBinoculars(wanted)
	up = wanted == true

	if not up then
		return
	end

	if istable(VManip) and isfunction(VManip.IsActive) and VManip:IsActive() and isfunction(VManip.Remove) then
		pcall(VManip.Remove, VManip)
	end
end

function V.Reset()
	up = false
end

hook.Add("VManipPrePlayAnim", "GryMod compat vmanip", V.PrePlay)

hook.Add("GryMod_BinocularsToggled", "GryMod compat vmanip", function(wanted)
	V.OnBinoculars(wanted)
end)
