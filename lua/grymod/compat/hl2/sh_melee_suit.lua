-- The stock melee weapons of Garry's Mod (shared): what the suit's strength and speed modes do to the fists, the crowbar and the stun baton, with the rules of
-- lua/grymod/sh_suit_weapons.lua. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md); the server half is sv_melee_suit.lua (the damage, the price of a
-- blow, the speed of the two weapons written in C++).
--
-- The fists (weapon_fists) are a SWEP written in Lua, and its attack code runs on both sides. Its attack, its draw and its damage function are decorated here, once, in the
-- weapon's registered table (weapons.GetStored) and in the weapons that already exist:
--   * PrimaryAttack (the left click, and the right click that calls it): the price of the blow is taken BEFORE the weapon's own code (server only: the energy that is left
--     decides the strength of the blow, as in the original), and in the speed mode the time before the next blow, the time before the hit lands and the view model's animation
--     go 1.5 times faster (the draw 1.75 times).
--   * DealDamage: the push the weapon applies by itself to what it hits (a prop) follows the strength rule too, by a value put back at once. The damage and the push of a hit
--     on something that takes damage are scaled in sv_melee_suit.lua, by the damage hook, like for the two other weapons.
-- The crowbar and the stun baton are written in C++: their code cannot be touched, so sv_melee_suit.lua works from the outside.
--
-- This file is the ONE place that names these three classes. Everything else asks SM.Kind(class).

local API = GryMod.API
local SW = GryMod.SuitWeapons

if not API or not SW then
	return -- sv_api.lua / cl_api.lua and sh_suit_weapons.lua are included first (grymod_shared.lua)
end

GryMod.StockMelee = GryMod.StockMelee or {}

local SM = GryMod.StockMelee

-- "lua": a SWEP of Lua (decorated here); "engine": written in C++ (watched from the outside by sv_melee_suit.lua).
local CLASSES = {
	weapon_fists = "lua",
	weapon_crowbar = "engine",
	weapon_stunstick = "engine"
}

function SM.Kind(class)
	return isstring(class) and CLASSES[class] or nil
end

function SM.Classes()
	local list = {}

	for class in pairs(CLASSES) do
		list[#list + 1] = class
	end

	table.sort(list)

	return list
end

-- Calls fn(weapon, ...) with the push the weapon applies itself (HitForceScale) multiplied by the strength rule of its holder; the weapon's own value is put back even when fn
-- raises an error.
function SM.CallScaled(weapon, fn, ...)
	local ply = SW.HolderOf(weapon)
	local base = weapon.HitForceScale
	local scale = ply and SW.MeleeScale(SW.ModeOf(ply), SW.EnergyOf(ply)) or 1

	if scale == 1 or not isnumber(base) then
		return fn(weapon, ...)
	end

	weapon.HitForceScale = base * scale

	local ok, answer = pcall(fn, weapon, ...)

	weapon.HitForceScale = base

	if not ok then
		error(answer, 0)
	end

	return answer
end

-- The weapon was just given its times by its own code (a blow, a draw): the times that are still ahead go `rate` times faster, and so does the view model's animation. Called
-- right after the weapon's function, so that nothing piles up: the next call starts again from the weapon's own numbers.
local function quicken(weapon, ply, rate)
	local now = CurTime()

	for _, name in ipairs({"NextPrimaryFire", "NextSecondaryFire", "NextMeleeAttack"}) do
		local get, set = weapon["Get" .. name], weapon["Set" .. name]

		if isfunction(get) and isfunction(set) then
			local t = get(weapon)

			if t > now then
				set(weapon, now + (t - now) / rate)
			end
		end
	end

	local vm = ply:GetViewModel()

	if IsValid(vm) then
		vm:SetPlaybackRate(vm:GetPlaybackRate() * rate)
	end

	-- the weapon's idle animation starts when the animation ends: it reads the view model's rate
	if isfunction(weapon.UpdateNextIdle) then
		weapon:UpdateNextIdle()
	end
end

-- The wrapped function: the original runs first (or after the price), then the speed. Never an error into the weapon's code: the speed part is under pcall.
local function wrapAttack(original)
	return function(weapon, ...)
		local ply = SW.HolderOf(weapon)

		if not ply then
			return original(weapon, ...)
		end

		if SERVER and SM.PayBlow then
			pcall(SM.PayBlow, ply)
		end

		local answer = original(weapon, ...)

		pcall(function()
			local rate = SW.Rate(SW.ModeOf(ply), "melee")

			if rate ~= 1 then
				quicken(weapon, ply, rate)
			end
		end)

		return answer
	end
end

local function wrapDeploy(original)
	return function(weapon, ...)
		local answer = original(weapon, ...)
		local ply = SW.HolderOf(weapon)

		if ply then
			pcall(function()
				local rate = SW.Rate(SW.ModeOf(ply), "draw")

				if rate ~= 1 then
					quicken(weapon, ply, rate)
				end
			end)
		end

		return answer
	end
end

local function wrapDealDamage(original)
	return function(weapon, ...)
		return SM.CallScaled(weapon, original, ...)
	end
end

local DECORATIONS = {
	PrimaryAttack = wrapAttack,
	Deploy = wrapDeploy,
	DealDamage = wrapDealDamage
}

-- Decorates a table that holds the weapon's functions (the registered table, or a weapon that exists). The original is kept in a field of the table itself, so that running
-- this file again (a hot reload) wraps the ORIGINAL again instead of a wrapper.
function SM.Decorate(tbl)
	if not istable(tbl) then
		return false
	end

	for name, wrap in pairs(DECORATIONS) do
		local keep = "GryStockMelee_" .. name
		local original = rawget(tbl, keep) or rawget(tbl, name)

		if isfunction(original) then
			rawset(tbl, keep, original)
			rawset(tbl, name, wrap(original))
		end
	end

	return true
end

-- The fists of the registered weapons, and the ones that already exist (given before this file ran again).
function SM.DecorateAll()
	for _, class in ipairs(SM.Classes()) do
		if SM.Kind(class) == "lua" then
			local stored = weapons.GetStored(class)

			if stored then
				SM.Decorate(stored)

				for _, weapon in ipairs(ents.FindByClass(class)) do
					local source = rawget(stored, "GryStockMelee_PrimaryAttack") and stored or nil

					if source then
						for name in pairs(DECORATIONS) do
							rawset(weapon:GetTable(), name, rawget(stored, name))
						end
					end
				end
			end
		end
	end
end

SM.DecorateAll()

-- The weapons may be registered after this file ran (the autorun files come first): the same again when the game is ready. Both are cheap, run once, and decorating twice is
-- harmless.
hook.Add("InitPostEntity", "GryMod compat stock melee", SM.DecorateAll)
