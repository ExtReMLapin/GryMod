-- Tests of the TFA adapter of the suit's effects (lua/grymod/compat/weapons/sh_tfa_suit.lua and sv_tfa_suit.lua), GLuaTest format, server realm (the settings are replicated: only
-- the server may change them). TFA's own hooks are run with stand-ins for the weapon, the player and the damage, so that the cases need no TFA: they pin what the adapter
-- answers to TFA's questions. The rules themselves are in tests/sh_suit_weapons_test.lua. Each case names the change that makes it fail.

local Modes
local made

-- a stand-in player: answers what the adapter asks
local function fakePlayer(mode, energy)
	local ply = {mode = mode, energy = energy, nw = {}}

	function ply:IsValid() return true end
	function ply:IsPlayer() return true end
	function ply:GetNW2Int(key, default) if key == "GryMode" then return self.mode end return default end
	function ply:GetNW2Float(key, default) if key == "GryEnergy" then return self.energy end return default end
	function ply:SetNW2Float(key, value) if key == "GryEnergy" then self.energy = value end end

	return ply
end

local function weapon(owner, fields)
	local wep = {IsTFAWeapon = true}

	function wep:IsValid() return true end
	function wep:GetOwner() return owner end
	function wep:GetClass() return "test_tfa_weapon" end

	for k, v in pairs(fields or {}) do
		wep[k] = v
	end

	return wep
end

local function damage(attacker, inflictor, amount)
	local info = {amount = amount, force = Vector(10, 0, 0), scaled = nil}

	function info:GetAttacker() return attacker end
	function info:GetInflictor() return inflictor end
	function info:GetDamage() return self.amount end
	function info:ScaleDamage(m) self.amount = self.amount * m self.scaled = m end
	function info:GetDamageForce() return self.force end
	function info:SetDamageForce(v) self.force = v end

	return info
end

-- the adapter's own damage hook, called directly: TFA and GryMod have their own EntityTakeDamage hooks that need a real victim and a real damage
local function hit(info)
	hook.GetTable().EntityTakeDamage["GryMod compat tfa suit"]({}, info)
end

local function withSetting(name, value, fn)
	local convar = GetConVar(name)
	local before = convar:GetString()

	convar:SetString(value)

	local ok, err = pcall(fn)

	convar:SetString(before)

	if not ok then
		error(err, 0)
	end
end

return {
	groupName = "GryMod suit effects on TFA weapons",
	beforeEach = function()
		Modes = GryMod.Modes
	end,
	cases = {
		{
			-- fails when the recoil stats of a strength mode player are not scaled by the rules' multiplier (the kick x0.375 with a full bar), when another stat is touched, or when a
			-- value that is not a number is changed
			name = "TFA_GetStat: the three kick stats are scaled in the strength mode; no other stat, no other value type, no other answer",
			func = function()
				local ply = fakePlayer(Modes.STRENGTH, 100)
				local wep = weapon(ply)

				for _, stat in ipairs({"Primary.KickUp", "Primary.KickDown", "Primary.KickHorizontal"}) do
					local answer = hook.Run("TFA_GetStat", wep, stat, 2)

					expect(answer ~= nil and math.abs(answer - 0.75) < 0.001).to.beTrue() -- 2 x 0.375
				end

				expect(hook.Run("TFA_GetStat", wep, "Primary.Damage", 30)).to.beNil()
				expect(hook.Run("TFA_GetStat", wep, "Primary.KickUp", "text")).to.beNil()
				expect(hook.Run("TFA_GetStat", wep, "Primary.KickUp", nil)).to.beNil()
			end
		},
		{
			-- fails when the effect is applied to a weapon with no player (an NPC, a dropped weapon), or does not follow the mode and the energy of the holder
			name = "TFA_GetStat: nothing for a weapon without a player, and the answer follows the holder's mode and energy",
			func = function()
				local npc = {IsValid = function() return true end, IsPlayer = function() return false end}

				expect(hook.Run("TFA_GetStat", weapon(npc), "Primary.KickUp", 2)).to.beNil()
				expect(hook.Run("TFA_GetStat", weapon(nil), "Primary.KickUp", 2)).to.beNil()

				-- the armor mode keeps almost all of the kick, an empty strength bar gives back 90 percent
				local armor = hook.Run("TFA_GetStat", weapon(fakePlayer(Modes.ARMOR, 100)), "Primary.KickUp", 2)

				expect(math.abs(armor - 2 * 0.9375) < 0.001).to.beTrue()

				local empty = hook.Run("TFA_GetStat", weapon(fakePlayer(Modes.STRENGTH, 0)), "Primary.KickUp", 2)

				expect(math.abs(empty - 1.8) < 0.001).to.beTrue()
			end
		},
		{
			-- fails when the setting does not switch the recoil effect off (everything is optional)
			name = "TFA_GetStat: with gry_suit_strength_recoil at 0 the stats are left alone",
			func = function()
				withSetting("gry_suit_strength_recoil", "0", function()
					expect(hook.Run("TFA_GetStat", weapon(fakePlayer(Modes.STRENGTH, 100)), "Primary.KickUp", 2)).to.beNil()
				end)
			end
		},
		{
			-- fails when the speed mode does not play the draw at x1.75 and a melee swing at x1.5 (the rate TFA passes is multiplied, not replaced), when another mode does, or when a
			-- reload is changed by the speed mode alone
			name = "TFA_AnimationRate: draw x1.75 and melee swing x1.5 in the speed mode, a reload untouched, nothing in the other modes",
			func = function()
				local speed = fakePlayer(Modes.SPEED, 100)
				local wep = weapon(speed)

				expect(hook.Run("TFA_AnimationRate", wep, ACT_VM_DRAW, 1)).to.equal(1.75)
				expect(hook.Run("TFA_AnimationRate", wep, ACT_VM_DRAW, 2)).to.equal(3.5)
				expect(hook.Run("TFA_AnimationRate", wep, ACT_VM_HOLSTER, 1)).to.equal(1.75)
				expect(hook.Run("TFA_AnimationRate", wep, ACT_VM_HITCENTER, 1)).to.equal(1.5)
				expect(hook.Run("TFA_AnimationRate", wep, ACT_VM_RELOAD, 1)).to.beNil()
				expect(hook.Run("TFA_AnimationRate", wep, ACT_VM_PRIMARYATTACK, 1)).to.beNil()
				expect(hook.Run("TFA_AnimationRate", wep, -1, 1)).to.beNil()
				expect(hook.Run("TFA_AnimationRate", wep, nil, 1)).to.beNil()

				for _, mode in ipairs({Modes.ARMOR, Modes.CLOAK, Modes.STRENGTH}) do
					expect(hook.Run("TFA_AnimationRate", weapon(fakePlayer(mode, 100)), ACT_VM_DRAW, 1)).to.beNil()
				end
			end
		},
		{
			-- fails when the reload setting is ignored (the original's reload is not faster: a setting is how an owner changes that) or when it changes a reload outside the speed mode
			name = "TFA_AnimationRate: a reload follows gry_suit_reload_rate in the speed mode only",
			func = function()
				withSetting("gry_suit_reload_rate", "2", function()
					expect(hook.Run("TFA_AnimationRate", weapon(fakePlayer(Modes.SPEED, 100)), ACT_VM_RELOAD, 1)).to.equal(2)
					expect(hook.Run("TFA_AnimationRate", weapon(fakePlayer(Modes.ARMOR, 100)), ACT_VM_RELOAD, 1)).to.beNil()
				end)
			end
		},
		{
			-- fails when the handling setting does not switch the speed mode's animations off
			name = "TFA_AnimationRate: with gry_suit_handling at 0 nothing changes",
			func = function()
				withSetting("gry_suit_handling", "0", function()
					expect(hook.Run("TFA_AnimationRate", weapon(fakePlayer(Modes.SPEED, 100)), ACT_VM_DRAW, 1)).to.beNil()
				end)
			end
		},
		{
			-- fails when a melee hit of a strength mode player is not multiplied by the rule (x9.2 with a full bar, the push too), when a bullet of the same weapon is, or when a
			-- weapon that is not TFA's is
			name = "EntityTakeDamage: a TFA melee hit of a strength mode player is multiplied, a shot or a weapon that is not TFA's is not",
			func = function()
				local ply = fakePlayer(Modes.STRENGTH, 100)
				local knife = weapon(ply, {IsMelee = true})
				local info = damage(ply, knife, 25)

				hit(info)
				expect(math.abs(info.amount - 25 * 9.2) < 0.01).to.beTrue()
				expect(math.abs(info.force.x - 10 * 9.2) < 0.01).to.beTrue()

				-- a gun's bullet (not a melee weapon, not bashing)
				local gun = weapon(ply, {IsMelee = false})
				local bullet = damage(ply, gun, 25)

				hit(bullet)
				expect(bullet.amount).to.equal(25)

				-- a weapon of another base (no TFA marker)
				local other = weapon(ply, {IsTFAWeapon = false, IsMelee = true})
				local alien = damage(ply, other, 25)

				hit(alien)
				expect(alien.amount).to.equal(25)
			end
		},
		{
			-- fails when the quick melee (the bash) of a gun is not multiplied: it is a melee hit that goes through the gun
			name = "EntityTakeDamage: the bash of a gun counts as a melee hit",
			func = function()
				local ply = fakePlayer(Modes.STRENGTH, 50)
				local gun = weapon(ply, {IsMelee = false, GetBashingStrict = function() return true end})
				local info = damage(ply, gun, 25)

				hit(info)
				expect(math.abs(info.amount - 25 * 4.2) < 0.01).to.beTrue()
			end
		},
		{
			-- fails when the other modes hit harder, or when the setting does not switch it off
			name = "EntityTakeDamage: no change outside the strength mode, and none with gry_suit_strength_melee at 0",
			func = function()
				local armor = fakePlayer(Modes.ARMOR, 100)
				local info = damage(armor, weapon(armor, {IsMelee = true}), 25)

				hit(info)
				expect(info.amount).to.equal(25)

				withSetting("gry_suit_strength_melee", "0", function()
					local strong = fakePlayer(Modes.STRENGTH, 100)
					local off = damage(strong, weapon(strong, {IsMelee = true}), 25)

					hit(off)
					expect(off.amount).to.equal(25)
				end)
			end
		},
		{
			-- fails when a melee swing costs nothing (a knife, the right click of a melee weapon, the quick melee of a gun): the strength mode takes 20 of the bar and the speed mode 10 for
			-- each blow, the other modes nothing; a gun's right click that is only the sights costs nothing
			name = "a melee blow costs energy: the swing of a melee weapon, its right click and the bash of a gun pay the melee price in the strength and speed modes only",
			func = function()
				local ply = player.GetAll()[1]

				if not IsValid(ply) then
					return
				end

				local mode, energy = ply:GetNW2Int("GryMode", Modes.ARMOR), ply:GetNW2Float("GryEnergy")
				local ok, err = pcall(function()
					local knife = weapon(ply, {IsMelee = true})
					local gun = weapon(ply, {IsMelee = false})

					local function paid(hookName, w)
						ply:SetNW2Float("GryEnergy", 100)
						hook.Run(hookName, w)

						return 100 - ply:GetNW2Float("GryEnergy")
					end

					ply:SetNW2Int("GryMode", Modes.STRENGTH)
					expect(paid("TFA_PostPrimaryAttack", knife)).to.equal(20)
					expect(paid("TFA_PostSecondaryAttack", knife)).to.equal(20)
					expect(paid("TFA_PostBash", gun)).to.equal(20)
					expect(paid("TFA_PostSecondaryAttack", gun)).to.equal(0) -- the sights of a gun are not a blow

					ply:SetNW2Int("GryMode", Modes.SPEED)
					expect(paid("TFA_PostPrimaryAttack", knife)).to.equal(10)
					expect(paid("TFA_PostBash", gun)).to.equal(10)

					ply:SetNW2Int("GryMode", Modes.ARMOR)
					expect(paid("TFA_PostPrimaryAttack", knife)).to.equal(0)
					expect(paid("TFA_PostBash", gun)).to.equal(0)

					-- never under 0
					ply:SetNW2Int("GryMode", Modes.STRENGTH)
					ply:SetNW2Float("GryEnergy", 4)
					hook.Run("TFA_PostPrimaryAttack", knife)
					expect(ply:GetNW2Float("GryEnergy")).to.equal(0)
				end)

				ply:SetNW2Int("GryMode", mode)
				ply:SetNW2Float("GryEnergy", energy)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails when a shot of a strength mode player does not take the energy the rule says (7.5 of the bar) through the public energy API, when a melee weapon pays it,
			-- when another mode pays, or when the bar goes under 0. A real player: the energy API only takes a real one
			name = "TFA_PostPrimaryAttack: a gun's shot takes the energy in the strength mode only, never under 0 and nothing for a melee weapon",
			func = function()
				local ply = player.GetAll()[1]

				if not IsValid(ply) then
					return -- no player on this server: nothing to check
				end

				local mode, energy = ply:GetNW2Int("GryMode", Modes.ARMOR), ply:GetNW2Float("GryEnergy")
				local ok, err = pcall(function()
					ply:SetNW2Int("GryMode", Modes.STRENGTH)
					ply:SetNW2Float("GryEnergy", 100)

					local gun = weapon(ply)

					hook.Run("TFA_PostPrimaryAttack", gun)
					expect(ply:GetNW2Float("GryEnergy")).to.equal(92.5)

					-- the calibre: an SMG round costs 0.75 of the rifle's price, a magnum round 1.5
					ply:SetNW2Float("GryEnergy", 100)
					hook.Run("TFA_PostPrimaryAttack", weapon(ply, {GetStatL = function(_, stat) if stat == "Primary.Ammo" then return "smg1" end end}))
					expect(math.abs(ply:GetNW2Float("GryEnergy") - (100 - 7.5 * 0.75)) < 0.001).to.beTrue()
					ply:SetNW2Float("GryEnergy", 100)
					hook.Run("TFA_PostPrimaryAttack", weapon(ply, {GetStatL = function(_, stat) if stat == "Primary.Ammo" then return "357" end end}))
					expect(math.abs(ply:GetNW2Float("GryEnergy") - (100 - 7.5 * 1.5)) < 0.001).to.beTrue()
					ply:SetNW2Float("GryEnergy", 100)
					hook.Run("TFA_PostPrimaryAttack", gun)

					ply:SetNW2Float("GryEnergy", 3)
					hook.Run("TFA_PostPrimaryAttack", gun)
					expect(ply:GetNW2Float("GryEnergy")).to.equal(0)

					-- a melee weapon's swing pays the melee price (20 in the strength mode), not the price of a shot
					ply:SetNW2Float("GryEnergy", 100)
					hook.Run("TFA_PostPrimaryAttack", weapon(ply, {IsMelee = true}))
					expect(ply:GetNW2Float("GryEnergy")).to.equal(80)

					ply:SetNW2Float("GryEnergy", 100)
					ply:SetNW2Int("GryMode", Modes.SPEED)
					hook.Run("TFA_PostPrimaryAttack", gun)
					expect(ply:GetNW2Float("GryEnergy")).to.equal(100)
				end)

				ply:SetNW2Int("GryMode", mode)
				ply:SetNW2Float("GryEnergy", energy)

				if not ok then
					error(err, 0)
				end
			end
		}
	}
}
