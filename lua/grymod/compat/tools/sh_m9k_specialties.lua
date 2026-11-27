-- M9K Specialties (the explosives, the launchers and the mines of the M9K weapon packs): the grenade warning for its thrown grenades, launched projectiles, proximity mine and C4,
-- the radar contact of its proximity mine, and the prompt of its ammo boxes. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): data and small readers through
-- the public API (RegisterTracked, RegisterUsable), nothing when M9K is not there (an entry for a class that does not exist matches nothing). The server part is
-- sv_m9k_specialties.lua. GryMod already has compat/weapons/cl_m9k.lua for the guns' fire mode.
--
-- Read in the public code of M9K (github.com/CFC-Servers/m9k_monorepo, the code of the Workshop item 144982052, entities/ and weapons/), NOT tried in a game (not installed when
-- this was written): the tests use stand-ins. What matters:
--   * a thrown grenade (bobs_nade_base.lua, SWEP:Throw) and a launched projectile (the launchers' weapons) get the engine's owner (SetOwner) from the weapon, and the grenades also
--     keep it in `_m9kOwner`: GryMod's own reading of the owner works. The planted things keep it in a field of their own: ProxyBombOwner (the proximity mine), BombOwner (the C4);
--   * a grenade or a projectile only exists live (it is made when thrown, with a fuse of 3 seconds or in flight): no `armed` reader, it is a danger from its creation;
--   * the explosions are util.BlastDamage + effects (no env_explosion): GryMod's own wrap of util.BlastDamage (docs/api.md) rings the radar for them, nothing to do here.
-- Entries are by class, and by base where M9K has one (the 40 mm projectiles share m9k_launched_projectile_base; the rockets share nothing). No match function. The priority is above
-- the stock entries (-100) and below the default (0).

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.RegisterUsable or not API.RegisterTracked then
	return -- sh_api.lua, sh_api_tracked.lua and sh_api_usable.lua are included first (grymod_shared.lua)
end

local PRIORITY = -50

-- The player who laid or threw it, from a field of the entity, or nil.
local function playerIn(ent, field)
	local owner = ent[field]

	if owner ~= nil and IsValid(owner) and isfunction(owner.IsPlayer) and owner:IsPlayer() then
		return owner
	end

	return nil
end

-- (sv_m9k_specialties.lua knows the keys "m9k_grenades", "m9k_launched_grenades" and "m9k_rockets" of the projectiles a player leaves in the hands of a weapon.)

local function tracked(key, def)
	def.priority = PRIORITY

	local ok, reason = API.RegisterTracked(key, def)

	if not ok then
		MsgN("GryMod: the M9K entry '" .. key .. "' of the tracked registry was refused: " .. tostring(reason))
	end
end

-- The grenades the player throws (bobs_nade_base.lua: the frag, the nitro-X, the nerve gas): live at once, the fuse of m9k_thrown_m61 is 3 seconds.
tracked("m9k_grenades", {
	class = {"m9k_thrown_m61", "m9k_thrown_nitrox", "m9k_nervegasnade"},
	danger = {
		label = "GRENADE", type = "grenade",
		ownerOf = function(ent)
			return playerIn(ent, "_m9kOwner")
		end
	}
})

-- The 40 mm grenades of the launchers (the M79, the EX41, the Milkor: m9k_launched_projectile_base) and the rockets (the M202, the RPG and the Matador, the Davy Crockett).
-- The shooter is never warned of his own (ownMissile).
tracked("m9k_launched_grenades", {
	base = "m9k_launched_projectile_base",
	danger = {label = "GRENADE", type = "grenade", ownMissile = true}
})

tracked("m9k_rockets", {
	class = {"m9k_m202_rocket", "m9k_gdcwa_rpg_heat", "m9k_gdcwa_matador_90mm", "m9k_launched_davycrockett"},
	danger = {label = "MISSILE", type = "missile", ownMissile = true}
})

-- The proximity mine (m9k_proxy.lua): it detects from `TimeLeft` on (3 seconds after it was laid) within a box of 100 units, so it warns only then, and only from close by (6 m).
-- It is a radar contact once scanned, like the Combine mine: an ally when the player laid it (ProxyBombOwner), hostile otherwise.
tracked("m9k_proxy_mine", {
	class = "m9k_proxy",
	type = "device", radar = "scan",
	relation = function(ply, ent)
		return playerIn(ent, "ProxyBombOwner") == ply and "ally" or "hostile"
	end,
	danger = {
		label = "PROXIMITY MINE", type = "mine", range = 6,
		armed = function(ent)
			return isnumber(ent.TimeLeft) and ent.TimeLeft < CurTime()
		end,
		ownerOf = function(ent)
			return playerIn(ent, "ProxyBombOwner")
		end
	}
})

-- The C4 (m9k_mad_c4.lua): its countdown runs from the moment it is planted and ends in a blast of 500 units. Its owner is BombOwner.
tracked("m9k_c4", {
	class = "m9k_mad_c4",
	danger = {
		label = "C4", type = "bomb",
		ownerOf = function(ent)
			return playerIn(ent, "BombOwner")
		end
	}
})

-- The ammo boxes (m9k_ammo_base.lua, SIMPLE_USE): +use gives the ammunition (and the weapon, for the explosives' boxes) and removes the box.
local ok, reason = API.RegisterUsable("m9k_ammo_boxes", {base = "m9k_ammo_base", icon = "pickup", text = "TAKE AMMO", use = "once", priority = PRIORITY})

if not ok then
	MsgN("GryMod: the M9K entry 'm9k_ammo_boxes' of the usable registry was refused: " .. tostring(reason))
end
