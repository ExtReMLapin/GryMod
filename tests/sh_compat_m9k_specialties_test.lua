-- Tests of the M9K Specialties patch, the shared part (lua/grymod/compat/tools/sh_m9k_specialties.lua), GLuaTest format, runs in the server AND in the client realm. M9K was not
-- installed when this was written: the cases use stand-ins with what the patch reads in its public code (github.com/CFC-Servers/m9k_monorepo, the code of the Workshop item):
-- the thrown grenades (entities/m9k_thrown_m61.lua: always live, `_m9kOwner`, SetOwner), the launched projectiles (m9k_launched_projectile_base.lua, SetOwner by the weapon), the
-- proximity mine (m9k_proxy.lua: `TimeLeft`, `ProxyBombOwner`), the C4 (m9k_mad_c4.lua: `BombOwner`) and the ammo boxes (m9k_ammo_base.lua). Each case names the change whose
-- absence makes it fail.

local API

local function ent(class, fields)
	local e = {
		IsValid = function() return true end,
		GetClass = function() return class end,
		GetSpawnFlags = function() return 0 end
	}

	for key, value in pairs(fields or {}) do
		e[key] = value
	end

	return e
end

local function player()
	return {IsValid = function() return true end, IsPlayer = function() return true end}
end

return {
	groupName = "GryMod compat: M9K Specialties (shared)",
	beforeEach = function()
		API = GryMod.API
		include("grymod/compat/tools/sh_m9k_specialties.lua")
	end,
	cases = {
		{
			-- fails when a thrown grenade of M9K does not warn, or needs a state it does not have (it is live from the moment it exists)
			name = "the thrown grenades of M9K are dangers as soon as they exist, with the owner they keep",
			func = function()
				local me = player()

				for _, class in ipairs({"m9k_thrown_m61", "m9k_thrown_nitrox", "m9k_nervegasnade"}) do
					local entry = API.GetDanger(ent(class))

					expect(entry ~= nil).to.beTrue()
					expect(entry.danger.label).to.equal("GRENADE")
					expect(entry.danger.armed).to.beNil()
					expect(entry.danger.ownerOf(ent(class, {_m9kOwner = me}))).to.equal(me)
					expect(entry.danger.ownerOf(ent(class))).to.beNil()
				end
			end
		},
		{
			-- fails when the 40 mm grenades (the base the launchers' projectiles share) or the rockets (no common base) are not dangers, or when the player's own shot warns him
			name = "the launched grenades (by their base) and the rockets (by class) are dangers the shooter is never warned of",
			func = function()
				for _, class in ipairs({"m9k_launched_m79", "m9k_milkor_nade"}) do
					local entry = API.GetDanger(ent(class, {Base = "m9k_launched_projectile_base"}))

					expect(entry ~= nil).to.beTrue()
					expect(entry.danger.label).to.equal("GRENADE")
					expect(entry.danger.ownMissile).to.beTrue()
				end

				for _, class in ipairs({"m9k_m202_rocket", "m9k_gdcwa_rpg_heat", "m9k_gdcwa_matador_90mm", "m9k_launched_davycrockett"}) do
					local entry = API.GetDanger(ent(class))

					expect(entry ~= nil).to.beTrue()
					expect(entry.danger.label).to.equal("MISSILE")
					expect(entry.danger.ownMissile).to.beTrue()
				end
			end
		},
		{
			-- fails when the thrown knives and the harpoon (no explosion) warn like grenades
			name = "the thrown knives and the harpoon are not dangers of the grenade warning",
			func = function()
				expect(API.GetDanger(ent("m9k_thrown_knife"))).to.beNil()
				expect(API.GetDanger(ent("m9k_thrown_harpoon"))).to.beNil()
			end
		},
		{
			-- fails when the proximity mine warns while its three seconds are not over (it does not detect yet), or never, or without its owner
			name = "the proximity mine warns once its arming time is over (TimeLeft), at a short distance, with the owner it keeps (ProxyBombOwner)",
			func = function()
				local me = player()
				local entry = API.GetDanger(ent("m9k_proxy"))

				expect(entry ~= nil).to.beTrue()
				expect(entry.danger.armed(ent("m9k_proxy", {TimeLeft = CurTime() - 1}))).to.beTrue()
				expect(entry.danger.armed(ent("m9k_proxy", {TimeLeft = CurTime() + 2}))).to.beFalse()
				expect(entry.danger.armed(ent("m9k_proxy"))).to.beFalse()
				expect(entry.danger.range).to.equal(6)
				expect(entry.danger.ownerOf(ent("m9k_proxy", {ProxyBombOwner = me}))).to.equal(me)
			end
		},
		{
			-- fails when the proximity mine is not a radar contact once scanned, or the player's own is hostile to him
			name = "the proximity mine is a radar contact once scanned: an ally when the player laid it, hostile otherwise",
			func = function()
				local me, other = player(), player()
				local entry = API.GetTrackedByClass("m9k_proxy")

				expect(entry.radar).to.equal("scan")
				expect(entry.relation(me, ent("m9k_proxy", {ProxyBombOwner = me}))).to.equal("ally")
				expect(entry.relation(me, ent("m9k_proxy", {ProxyBombOwner = other}))).to.equal("hostile")
			end
		},
		{
			-- fails when a planted C4 does not warn (its countdown runs from the moment it exists), or loses its owner
			name = "the C4 is a danger from the moment it is planted, with its BombOwner",
			func = function()
				local me = player()
				local entry = API.GetDanger(ent("m9k_mad_c4"))

				expect(entry ~= nil).to.beTrue()
				expect(entry.danger.label).to.equal("C4")
				expect(entry.danger.armed).to.beNil()
				expect(entry.danger.ownerOf(ent("m9k_mad_c4", {BombOwner = me}))).to.equal(me)
			end
		},
		{
			-- fails when the ammo boxes (the base and every box built on it) have no prompt, or the ones of other addons get one
			name = "the ammo boxes have the TAKE AMMO prompt, what is not M9K's does not",
			func = function()
				local frags = ent("m9k_ammo_frags", {Base = "m9k_ammo_base"})

				expect(API.GetUsable(frags).text).to.equal("TAKE AMMO")
				expect(API.GetUsable(frags).icon).to.equal("pickup")
				expect(API.GetUsable(ent("m9k_ammo_base")) ~= nil).to.beTrue()
				expect(API.GetUsable(ent("some_other_ammo_box"))).to.beNil()
			end
		},
		{
			-- fails when an entry uses a match function
			name = "no entry uses a match function",
			func = function()
				expect(API.GetDanger(ent("m9k_proxy")).match).to.beNil()
				expect(API.GetUsable(ent("m9k_ammo_base")).match).to.beNil()
			end
		}
	}
}
