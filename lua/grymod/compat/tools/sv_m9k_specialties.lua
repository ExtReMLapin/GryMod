-- M9K Specialties (server): what the suit's camouflage means for its proximity mine, and the attacks of its grenade and rocket weapons, which are not bullets. Part of the
-- compatibility patches (lua/grymod/compat/, docs/compat.md): it uses M9K's own hook and GryMod's public API (CloakLevel, ReportAttack, GetDanger), does nothing when M9K is not
-- installed (its hook is never run, none of its entities is made) and never raises an error into M9K's code or the game's. Read in the public code of M9K
-- (github.com/CFC-Servers/m9k_monorepo), not tried in a game.
--
-- 1. The proximity mine (entities/m9k_proxy.lua:38) asks the hook M9k_ProxyMineCanTrigger(mine, target, owner) for each player or NPC in its box. GryMod does not answer: a mine
--    goes off under the feet, and the camouflage hides from the visible light only.
-- 2. A grenade thrown (weapons/bobs_nade_base.lua, SWEP:Throw), a 40 mm grenade or a rocket (weapons/m9k_m79gl.lua...) is made by the weapon with ents.Create, owned by the player
--    (SetOwner, after the creation) and spawned: no bullet, so nothing ended the camouflage. The patch looks at the entities that carry the danger entries of sh_m9k_specialties.lua
--    for the thrown grenades and the launched projectiles, one tick after their creation (the owner is set by then), and tells GryMod the player attacked. The things laid on the
--    ground (the mine, the C4) are not attacks.

local API = GryMod.API

if not API or not API.CloakLevel or not API.ReportAttack or not API.GetDanger then
	return -- sv_api.lua and the registries are included first (grymod_shared.lua)
end

local KEY = "GryMod compat m9k"
local HALF = 0.5

-- the keys of the entries of sh_m9k_specialties.lua for what a weapon throws or launches
local ATTACKS = {m9k_grenades = true, m9k_launched_grenades = true, m9k_rockets = true}

local function cloakRuleOn()
	local var = GetConVar("gry_cloak_ai")

	return var == nil or var:GetBool()
end

-- (the proximity mine is not asked about: it goes off under the feet, and the camouflage hides from the visible light only)

-- The player who owns the projectile now: the engine's owner, or the field M9K's grenades also keep.
local function shooterOf(ent)
	local owner = ent:GetOwner()

	if owner == nil or not IsValid(owner) then
		owner = ent._m9kOwner
	end

	if owner ~= nil and IsValid(owner) and isfunction(owner.IsPlayer) and owner:IsPlayer() then
		return owner
	end

	return nil
end

hook.Add("OnEntityCreated", KEY, function(ent)
	local ok, entry = pcall(API.GetDanger, ent)

	if not ok or not entry or not ATTACKS[entry.key] then
		return
	end

	timer.Simple(0, function()
		pcall(function()
			if not IsValid(ent) then
				return
			end

			local shooter = shooterOf(ent)

			if shooter then
				API.ReportAttack(shooter, false)
			end
		end)
	end)
end)
