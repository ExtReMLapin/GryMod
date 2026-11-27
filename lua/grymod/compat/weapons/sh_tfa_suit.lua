-- TFA (shared): what the suit does to a TFA weapon's handling and recoil, from the rules of lua/grymod/sh_suit_weapons.lua. Part of the compatibility patches
-- (lua/grymod/compat/, docs/compat.md): it only uses TFA's documented hooks, answers nothing for a weapon that has no player holding it, and does nothing when TFA is not
-- installed (its hooks are never run).
--   * TFA_GetStat: the three kick stats are multiplied by the strength mode's recoil rule. TFA caches a stat BEFORE this hook (stat.lua), so the multiplier follows the
--     energy at every read.
--   * TFA_AnimationRate: the speed mode plays the draw, the holster, the raise and a melee swing faster, like the original game. TFA asks it for the viewmodel animation
--     AND for the lock-out times, on both sides, so the weapon is ready when its animation ends. A reload is only changed by gry_suit_reload_rate (1 = the original's),
--     for the weapons that reload through an activity: a reload that is a sequence index is not an activity and is left alone.
-- Both answer nil when nothing changes, so that another addon's answer still counts (TFA takes the first answer that is not nil).

local SW = GryMod.SuitWeapons

if not SW then
	return -- sh_suit_weapons.lua is included first (grymod_shared.lua)
end

local KEY = "GryMod compat tfa suit"

local KICK = {
	["Primary.KickUp"] = true,
	["Primary.KickDown"] = true,
	["Primary.KickHorizontal"] = true
}

-- The activity of a viewmodel animation -> the kind of handling it is. An activity the game does not have is skipped.
local KIND = {}

local function add(kind, names)
	for _, name in ipairs(names) do
		local act = _G[name]

		if isnumber(act) then
			KIND[act] = kind
		end
	end
end

add("draw", {"ACT_VM_DRAW", "ACT_VM_DRAW_EMPTY", "ACT_VM_DRAW_SILENCED", "ACT_VM_DRAW_DEPLOYED"})
add("holster", {"ACT_VM_HOLSTER", "ACT_VM_HOLSTER_EMPTY"})
add("ready", {"ACT_VM_SPRINT_LEAVE"})
add("melee", {"ACT_VM_HITLEFT", "ACT_VM_HITLEFT2", "ACT_VM_HITRIGHT", "ACT_VM_HITRIGHT2", "ACT_VM_HITCENTER", "ACT_VM_HITCENTER2",
	"ACT_VM_MISSLEFT", "ACT_VM_MISSLEFT2", "ACT_VM_MISSRIGHT", "ACT_VM_MISSRIGHT2", "ACT_VM_MISSCENTER", "ACT_VM_MISSCENTER2"})
add("reload", {"ACT_VM_RELOAD", "ACT_VM_RELOAD_EMPTY", "ACT_VM_RELOAD_SILENCED", "ACT_VM_RELOAD_DEPLOYED", "ACT_SHOTGUN_RELOAD_START", "ACT_SHOTGUN_RELOAD_FINISH"})

-- TFA runs these from the weapon's own code: an error here would break the weapon, so the answers are computed under pcall.
hook.Add("TFA_GetStat", KEY, function(weapon, stat, value)
	if not KICK[stat] or not isnumber(value) then
		return nil
	end

	local ok, answer = pcall(function()
		local ply = SW.HolderOf(weapon)

		if not ply then
			return nil
		end

		local scale = SW.RecoilScale(SW.ModeOf(ply), SW.EnergyOf(ply))

		return scale ~= 1 and value * scale or nil
	end)

	return ok and answer or nil
end)

hook.Add("TFA_AnimationRate", KEY, function(weapon, act, rate)
	local kind = isnumber(act) and KIND[act]

	if not kind or not isnumber(rate) then
		return nil
	end

	local ok, answer = pcall(function()
		local ply = SW.HolderOf(weapon)

		if not ply then
			return nil
		end

		local multiplier = SW.Rate(SW.ModeOf(ply), kind)

		return multiplier ~= 1 and rate * multiplier or nil
	end)

	return ok and answer or nil
end)
