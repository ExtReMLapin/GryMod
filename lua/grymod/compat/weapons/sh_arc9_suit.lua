-- ARC9 (shared): what the suit does to an ARC9 weapon's handling and recoil, from the rules of lua/grymod/sh_suit_weapons.lua. Part of the compatibility patches
-- (lua/grymod/compat/, docs/compat.md): it only uses ARC9's own global hooks (sh_0_stats.lua runs hook.Run("ARC9_" .. name, weapon, value) for each stat it reads, "<Stat>Hook",
-- and for each hook point of a weapon, "Hook_..."), answers nothing for a weapon that has no player holding it or that is not ARC9's, and does nothing when ARC9 is not installed
-- (its hooks are never run). No ARC9 file is touched and no function of it is replaced. Read in ARC9's source and tried with real ARC9 weapons (docs/compat.md).
--   * Recoil, strength mode: the stat "Recoil" is the number ARC9 multiplies every up / side value of the kick by (sh_recoil.lua) and the camera kick too (cl_camera.lua), so it
--     is scaled by the rule (x0.375 with a full bar), and "VisualRecoil", the kick of the gun on the screen, with it. Both are read at every tick (ARC9 does not keep them), so
--     the multiplier follows the energy.
--   * Handling, speed mode: ARC9 plays every animation through PlayAnimation(anim, mult), where `mult` is a TIME multiplier (below 1 is faster) that ARC9 also uses for the lock-out
--     times it computes from it, so the weapon is ready when its animation ends. Its hook "Hook_TranslateAnimSpeed" is asked for each animation with its name: the draw, the holster,
--     the raise ("ready"), the sprint exit and the fire mode switch take 1/1.75 of the time. The sights, the inspect, firing and the rest are left alone.
--   * Melee, speed mode: the swing's times and animation are divided by the stat "BashSpeed", so that one is multiplied by 1.5 (and the animation hook leaves the swing alone).
--     ARC9 reads BashSpeed once as static (kept for a minute, ThinkMelee) and once at each swing: the weapons of a player are asked to forget what they kept when his mode changes.
--   * Reload: the stat "ReloadTime" is a time multiplier that ARC9's timers use too (the magazine swap, the dropped magazine), so gry_suit_reload_rate (1 = the original's: no
--     change) divides it, in the speed mode.
-- Every hook answers nil when nothing changes, so that another addon's answer still counts, and runs under pcall: an error here would break the weapon.

local SW = GryMod.SuitWeapons

if not SW then
	return -- sh_suit_weapons.lua is included first (grymod_shared.lua)
end

local KEY = "GryMod compat arc9 suit"

-- The mode and the energy of the player who holds an ARC9 weapon, or nil: a weapon that is not ARC9's, with no player or held by an NPC is not touched.
local function holderOf(weapon)
	if not istable(weapon) and not isentity(weapon) then
		return nil
	end

	if weapon.ARC9 ~= true then
		return nil
	end

	return SW.HolderOf(weapon)
end

-- A hook on a number stat: `scale(ply)` gives the multiplier (nil or 1: nothing), `divide` makes it a divisor (a time multiplier).
local function statHook(stat, scale, divide)
	hook.Add("ARC9_" .. stat .. "Hook", KEY, function(weapon, value)
		if not isnumber(value) then
			return nil
		end

		local ok, answer = pcall(function()
			local ply = holderOf(weapon)

			if not ply then
				return nil
			end

			local factor = scale(ply)

			if not isnumber(factor) or factor == 1 or factor <= 0 then
				return nil
			end

			return divide and value / factor or value * factor
		end)

		return ok and answer or nil
	end)
end

local function recoil(ply)
	return SW.RecoilScale(SW.ModeOf(ply), SW.EnergyOf(ply))
end

statHook("Recoil", recoil)
statHook("VisualRecoil", recoil)
statHook("BashSpeed", function(ply) return SW.Rate(SW.ModeOf(ply), "melee") end)
statHook("ReloadTime", function(ply) return SW.Rate(SW.ModeOf(ply), "reload") end, true)

-- The kind of handling an animation is, from the name ARC9 gives it (after its own translation: a suffix such as "_empty" or "_quick" may follow).
local KIND_OF = {
	{"^draw", "draw"},
	{"^holster", "holster"},
	{"^ready", "ready"},
	{"^exit_sprint", "ready"},
	{"^firemode", "ready"}
}

local function kindOf(anim)
	if not isstring(anim) then
		return nil
	end

	for i = 1, #KIND_OF do
		if string.find(anim, KIND_OF[i][1]) then
			return KIND_OF[i][2]
		end
	end

	return nil
end

hook.Add("ARC9_Hook_TranslateAnimSpeed", KEY, function(weapon, data)
	if not istable(data) then
		return nil
	end

	local kind = kindOf(data.anim)

	if not kind then
		return nil
	end

	local ok, answer = pcall(function()
		local ply = holderOf(weapon)

		if not ply then
			return nil
		end

		local rate = SW.Rate(SW.ModeOf(ply), kind)

		if rate == 1 or not isnumber(rate) or rate <= 0 then
			return nil
		end

		-- the time ARC9 is about to use (the number another addon's hook may have put in Mult, else the one it was asked with), made shorter
		local time = data.Mult or data.mult

		if not isnumber(time) then
			return nil
		end

		data.Mult = time / rate

		return data
	end)

	return ok and answer or nil
end)

-- ARC9 keeps a processed value read as static for a minute (PV_CacheLong): the weapons of a player forget it when his mode changes, and when the setting of the handling does.
local function forget(ply)
	if not istable(ply) and not isentity(ply) then
		return
	end

	local weapons = isfunction(ply.GetWeapons) and ply:GetWeapons()

	if not istable(weapons) then
		return
	end

	for i = 1, #weapons do
		local weapon = weapons[i]

		if istable(weapon) or isentity(weapon) then
			if weapon.ARC9 == true and isfunction(weapon.ClearLongCache) then
				weapon:ClearLongCache()
			end
		end
	end
end

hook.Add("GryMod_ModeChanged", KEY, function(ply)
	pcall(forget, ply)
end)

cvars.AddChangeCallback("gry_suit_handling", function()
	pcall(function()
		for _, ply in ipairs(player.GetAll()) do
			forget(ply)
		end
	end)
end, KEY)
