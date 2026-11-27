-- What the suit does to a weapon (shared): the rules, with the original game's numbers (read from its code, the study of 2026-11-27: numbers and behaviours only). They
-- are pure functions of the suit mode and the energy, so that a weapon base's adapter (lua/grymod/compat/weapons/) only has to ask. Every effect is optional (a setting
-- each, the original's behaviour is the default); the adapters do nothing for a weapon that is not of their base and nothing when the base is not installed.
--   * Strength mode, melee: a hit is multiplied by (1 + 0.01 S) x (1 + 0.036 S), S = 100 x energy: x9.2 at full energy, x4.2 at half, x1 when empty.
--   * Strength mode, recoil: the kick of a shot is multiplied by (1 - 0.25 S / 100) x min(0.9, 1 - K x energy), S being the strength slot of the mode at that energy
--     (100 in the strength mode, 50 in the speed and cloak modes, 25 in the armor mode) and K the weapon's own factor (0.5 by default): x0.375 at full energy in the
--     strength mode, back to x0.9 when the bar is empty. The other modes only lose a little (x0.9375, x0.875).
--   * Strength mode, each shot takes 15 of the original's 200 (7.5 of our 100).
--   * Speed mode: the draw, the holster and the raise of a weapon play at x1.75 and a melee swing at x1.5. A reload is NOT faster in the original; gry_suit_reload_rate
--     (1 = the original's) lets an owner change that.

GryMod = GryMod or {}

local SW = GryMod.SuitWeapons or {}
GryMod.SuitWeapons = SW

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local handling = CreateConVar("gry_suit_handling", "1", flags, "Speed mode: the draw, the holster and the raise of a weapon x1.75 and a melee swing x1.5, like the original game (0 = off)", 0, 1)
local reloadRate = CreateConVar("gry_suit_reload_rate", "1", flags, "Speed mode: the speed of a reload. 1 = the original game's (a reload is not faster in the original)", 0.5, 3)
local strengthMelee = CreateConVar("gry_suit_strength_melee", "1", flags, "Strength mode: the damage and the push of a melee hit grow with the energy, up to x9.2 (0 = off)", 0, 1)
local strengthRecoil = CreateConVar("gry_suit_strength_recoil", "1", flags, "Strength mode: the kick of a shot is smaller, up to x0.375 with a full bar (0 = off)", 0, 1)
local shotCost = CreateConVar("gry_suit_shot_cost", "7.5", flags, "Strength mode: the energy each shot takes (of 100; the original's 15 of 200). 0 = free", 0, 50)

local shotCostByAmmo = CreateConVar("gry_suit_shot_cost_by_ammo", "1", flags, "Strength mode: a shot costs more energy with a bigger calibre (pistol and SMG rounds less, magnum, sniper and buckshot more). 0 = the same price for every weapon, like the original game", 0, 1)

local meleeCost = CreateConVar("gry_suit_melee_cost", "1", flags, "The energy a melee blow takes in the strength mode (10 of the bar) and in the speed mode (7.5), like the original game. This is a multiplier of those prices: 0 = free, 2 = double", 0, 4)

-- The weight of a kind of ammunition (its calibre) in the price of a shot, by the name of the game's ammunition. The plain price is the rifle's; an ammunition that is not here
-- (a modded one) costs the plain price.
local AMMO_WEIGHT = {
	pistol = 0.6,
	smg1 = 0.75,
	ar2 = 1,
	["357"] = 1.5,
	buckshot = 1.5,
	xbowbolt = 1.5,
	sniperround = 2,
	sniperpenetratedround = 2
}

-- The strength slot of each mode with a full bar (0 to 100): the weight the mode gives the strength.
local STRENGTH_SLOT = {}

local function slot(mode)
	local Modes = GryMod.Modes

	STRENGTH_SLOT[Modes.ARMOR] = 25
	STRENGTH_SLOT[Modes.STRENGTH] = 100
	STRENGTH_SLOT[Modes.SPEED] = 50
	STRENGTH_SLOT[Modes.CLOAK] = 50

	return STRENGTH_SLOT[mode] or 25
end

-- The weapon's own factor of the strength mode's recoil, and the speed of the original's handling animations.
SW.DEFAULT_RECOIL_FACTOR = 0.5
SW.DRAW_RATE = 1.75
SW.MELEE_RATE = 1.5

local function fraction(energy)
	if not isnumber(energy) or energy ~= energy then
		return 0
	end

	return math.Clamp(energy, 0, 1)
end

-- The multiplier of a melee hit of a player in `mode` with `energy` (0 to 1 of the bar).
function SW.MeleeMultiplier(mode, energy)
	if mode ~= GryMod.Modes.STRENGTH then
		return 1
	end

	local s = 100 * fraction(energy)

	return (1 + 0.01 * s) * (1 + 0.036 * s)
end

-- The multiplier of the kick of a shot. `factor` is the weapon's own K (0.5 when it has none).
function SW.RecoilMultiplier(mode, energy, factor)
	local e = fraction(energy)
	local multiplier = 1 - 0.25 * (slot(mode) * e) / 100

	if mode == GryMod.Modes.STRENGTH then
		multiplier = multiplier * math.min(0.9, 1 - (isnumber(factor) and factor or SW.DEFAULT_RECOIL_FACTOR) * e)
	end

	return math.max(multiplier, 0)
end

-- The speed of a kind of animation ("draw", "holster", "ready", "melee", "reload") in `mode`: the original's.
function SW.HandlingRate(mode, kind)
	if mode ~= GryMod.Modes.SPEED then
		return 1
	end

	if kind == "draw" or kind == "holster" or kind == "ready" then
		return SW.DRAW_RATE
	elseif kind == "melee" then
		return SW.MELEE_RATE
	end

	return 1
end

-- The energy a shot takes in `mode` (of 100): the setting, times the weight of the weapon's ammunition (`ammo`, the name of the kind of ammunition, when the setting follows the
-- calibre).
function SW.ShotCost(mode, ammo)
	if mode ~= GryMod.Modes.STRENGTH then
		return 0
	end

	local cost = math.max(shotCost:GetFloat(), 0)

	if shotCostByAmmo:GetBool() and isstring(ammo) then
		cost = cost * (AMMO_WEIGHT[string.lower(ammo)] or 1)
	end

	return cost
end

-- The energy a melee blow (a swing of a melee weapon, the quick melee of a gun) takes in `mode` (of 100): the original's 20 of 200 in the strength mode and 15 of 200 in the speed mode
-- (the retail game's numbers; the demo's are twice that), times the setting. The other modes take nothing here (a blow ends the camouflage, see the attack reports).
local MELEE_COST = {}

function SW.MeleeCost(mode)
	local Modes = GryMod.Modes

	MELEE_COST[Modes.STRENGTH] = 10
	MELEE_COST[Modes.SPEED] = 7.5

	return (MELEE_COST[mode] or 0) * math.max(meleeCost:GetFloat(), 0)
end

-- The same rules, with the settings: what an adapter asks.
function SW.MeleeScale(mode, energy)
	return strengthMelee:GetBool() and SW.MeleeMultiplier(mode, energy) or 1
end

function SW.RecoilScale(mode, energy, factor)
	return strengthRecoil:GetBool() and SW.RecoilMultiplier(mode, energy, factor) or 1
end

function SW.Rate(mode, kind)
	if kind == "reload" then
		return mode == GryMod.Modes.SPEED and reloadRate:GetFloat() or 1
	end

	return handling:GetBool() and SW.HandlingRate(mode, kind) or 1
end

-- The player who holds a weapon (any base), or nil (no one, an NPC, a weapon that is gone).
function SW.HolderOf(weapon)
	if not IsValid(weapon) or not isfunction(weapon.GetOwner) then
		return nil
	end

	local owner = weapon:GetOwner()

	if IsValid(owner) and isfunction(owner.IsPlayer) and owner:IsPlayer() then
		return owner
	end

	return nil
end

-- The mode and the energy (0 to 1) of a player, as both sides know them (the mode is a networked value: the server sets it with the mode, SetNanosuitMode).
function SW.ModeOf(ply)
	return IsValid(ply) and ply:GetNW2Int("GryMode", GryMod.Modes.ARMOR) or GryMod.Modes.ARMOR
end

function SW.EnergyOf(ply)
	return IsValid(ply) and math.Clamp(ply:GetNW2Float("GryEnergy", 0) / 100, 0, 1) or 0
end
