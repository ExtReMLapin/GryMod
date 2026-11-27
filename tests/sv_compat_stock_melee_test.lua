-- Tests of what the suit does to the three stock melee weapons (the fists, the crowbar, the stun baton): lua/grymod/compat/hl2/sh_melee_suit.lua (the list, the decoration of
-- the fists' SWEP) and sv_melee_suit.lua (the damage, the price of a blow, the speed of a blow of the weapons written in C++), GLuaTest format, server realm (the settings are
-- replicated: only the server may change them). The rules themselves (x9.2, 20 and 10 of the bar, x1.5) are in tests/sh_suit_weapons_test.lua. Stand-ins for the weapons and the
-- commands; the player is the real one (the energy API only takes a real player) and its mode and energy are put back. Each case names the change that makes it fail.

local Modes
local SM
local ply
local saved

local KEY = "GryMod compat stock melee"

-- a stand-in weapon of the given class held by the player: its next fire times are the ones the engine would keep
local function weapon(class, owner, fields)
	local wep = {class = class, owner = owner, nextPrimary = 0, nextSecondary = 0, nextMelee = 0}

	function wep:IsValid() return true end
	function wep:GetClass() return self.class end
	function wep:GetOwner() return self.owner end
	function wep:GetNextPrimaryFire() return self.nextPrimary end
	function wep:SetNextPrimaryFire(t) self.nextPrimary = t end
	function wep:GetNextSecondaryFire() return self.nextSecondary end
	function wep:SetNextSecondaryFire(t) self.nextSecondary = t end

	for k, v in pairs(fields or {}) do
		wep[k] = v
	end

	return wep
end

local function command(buttons)
	local cmd = {}

	function cmd:GetButtons() return buttons end

	return cmd
end

local function damage(inflictor, amount)
	local info = {amount = amount, force = Vector(10, 0, 0)}

	function info:GetAttacker() return ply end
	function info:GetInflictor() return inflictor end
	function info:GetDamage() return self.amount end
	function info:ScaleDamage(m) self.amount = self.amount * m end
	function info:GetDamageForce() return self.force end
	function info:SetDamageForce(v) self.force = v end

	return info
end

local function hit(info)
	hook.GetTable().EntityTakeDamage[KEY]({}, info)
end

local function suit(mode, energy)
	ply:SetNW2Int("GryMode", mode)
	ply:SetNW2Float("GryEnergy", energy)
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

local function untrackAll()
	if SM and SM.Untrack and ply then
		SM.Untrack(ply)
	end
end

return {
	groupName = "GryMod suit effects on the stock melee weapons",
	beforeAll = function()
		Modes = GryMod.Modes
		SM = GryMod.StockMelee
		ply = player.GetAll()[1]
		saved = ply and {mode = ply:GetNW2Int("GryMode", Modes.ARMOR), energy = ply:GetNW2Float("GryEnergy")}
	end,
	afterEach = function()
		untrackAll()
	end,
	afterAll = function()
		untrackAll()

		if ply and saved then
			suit(saved.mode, saved.energy)
		end
	end,
	cases = {
		{
			-- fails when the module is not there, or when the three classes are not known as what they are (the fists are a SWEP written in Lua, the crowbar and the stun baton are
			-- written in C++), or when another weapon is taken for one of them. The classes are named in this one place only
			name = "the module knows the three stock melee weapons, and no other weapon",
			func = function()
				expect(SM).to.exist()
				expect(SM.Kind("weapon_fists")).to.equal("lua")
				expect(SM.Kind("weapon_crowbar")).to.equal("engine")
				expect(SM.Kind("weapon_stunstick")).to.equal("engine")
				expect(SM.Kind("weapon_pistol")).to.beNil()
				expect(SM.Kind("tfa_knife_base")).to.beNil()
				expect(SM.Kind(nil)).to.beNil()
			end
		},
		{
			-- fails when a class of the module is not described by the weapon registry (the HUD, the camouflage and this module must agree on what these weapons are)
			name = "every weapon of the module is in the weapon registry as a weapon with no fire mode",
			func = function()
				for _, class in ipairs(SM.Classes()) do
					local def = GryMod.API.ResolveWeapon(class)

					expect(def).to.exist()
					expect(def.fire).to.equal("none")
				end

				expect(#SM.Classes()).to.equal(3)
			end
		},
		{
			-- fails when the hits of these weapons are not multiplied by the rule (x9.2 with a full bar, damage and push), when a hit of another weapon of the same player is, when
			-- another mode is, or when a weapon with no player is
			name = "EntityTakeDamage: a hit of the fists, the crowbar or the stun baton of a strength mode player is multiplied; a bullet, another mode, no player are not",
			func = function()
				suit(Modes.STRENGTH, 100)

				for _, class in ipairs({"weapon_fists", "weapon_crowbar", "weapon_stunstick"}) do
					local info = damage(weapon(class, ply), 15)

					hit(info)
					expect(math.abs(info.amount - 15 * 9.2) < 0.01).to.beTrue()
					expect(math.abs(info.force.x - 10 * 9.2) < 0.01).to.beTrue()
				end

				-- a pistol's bullet, the player himself as the inflictor, a weapon of an addon
				for _, other in ipairs({weapon("weapon_pistol", ply), ply, weapon("tfa_knife_base", ply)}) do
					local info = damage(other, 15)

					hit(info)
					expect(info.amount).to.equal(15)
				end

				-- no player (an NPC with a crowbar, a dropped weapon)
				local npc = {IsValid = function() return true end, IsPlayer = function() return false end}
				local info = damage(weapon("weapon_crowbar", npc), 15)

				hit(info)
				expect(info.amount).to.equal(15)

				-- the other modes
				for _, mode in ipairs({Modes.ARMOR, Modes.SPEED, Modes.CLOAK}) do
					suit(mode, 100)

					local plain = damage(weapon("weapon_crowbar", ply), 15)

					hit(plain)
					expect(plain.amount).to.equal(15)
				end
			end
		},
		{
			-- fails when the hit does not follow the energy that is left (x4.2 with half a bar, x1 with none) or when the setting does not switch the effect off
			name = "EntityTakeDamage: the multiplier follows the energy, and gry_suit_strength_melee at 0 switches it off",
			func = function()
				suit(Modes.STRENGTH, 50)

				local half = damage(weapon("weapon_crowbar", ply), 10)

				hit(half)
				expect(math.abs(half.amount - 42) < 0.01).to.beTrue()

				suit(Modes.STRENGTH, 0)

				local empty = damage(weapon("weapon_crowbar", ply), 10)

				hit(empty)
				expect(empty.amount).to.equal(10)

				suit(Modes.STRENGTH, 100)
				withSetting("gry_suit_strength_melee", "0", function()
					local off = damage(weapon("weapon_crowbar", ply), 10)

					hit(off)
					expect(off.amount).to.equal(10)
				end)
			end
		},
		{
			-- fails when a blow of the crowbar does not take its price when the swing starts (20 of the bar in the strength mode, 10 in the speed mode, nothing in the others), when
			-- a click that starts no blow (the weapon is not ready, no attack key, the right click that does nothing) takes energy, or when the bar goes under 0
			name = "OnCommand: the blow of a tracked crowbar takes 20 in the strength mode and 10 in the speed mode when it starts; nothing for a click that starts no blow",
			func = function()
				local crowbar = weapon("weapon_crowbar", ply)

				local function paid(mode, buttons, w, now)
					suit(mode, 100)
					SM.Track(ply, w, now)
					SM.OnCommand(ply, command(buttons), w, now)
					SM.Untrack(ply)

					return 100 - ply:GetNW2Float("GryEnergy")
				end

				expect(paid(Modes.STRENGTH, IN_ATTACK, crowbar, 10)).to.equal(20)
				expect(paid(Modes.SPEED, IN_ATTACK, crowbar, 10)).to.equal(10)
				expect(paid(Modes.ARMOR, IN_ATTACK, crowbar, 10)).to.equal(0)
				expect(paid(Modes.CLOAK, IN_ATTACK, crowbar, 10)).to.equal(0)

				expect(paid(Modes.STRENGTH, 0, crowbar, 10)).to.equal(0) -- no key
				expect(paid(Modes.STRENGTH, IN_ATTACK2, crowbar, 10)).to.equal(0) -- the right click of these weapons does nothing (measured)
				expect(paid(Modes.STRENGTH, IN_JUMP + IN_DUCK, crowbar, 10)).to.equal(0)

				crowbar.nextPrimary = 10.5 -- the weapon is being drawn or recovering from a blow: the key starts nothing
				expect(paid(Modes.STRENGTH, IN_ATTACK, crowbar, 10)).to.equal(0)

				-- never under 0
				suit(Modes.STRENGTH, 4)
				crowbar.nextPrimary = 0
				SM.Track(ply, crowbar, 10)
				SM.OnCommand(ply, command(IN_ATTACK), crowbar, 10)
				SM.Untrack(ply)
				expect(ply:GetNW2Float("GryEnergy")).to.equal(0)
			end
		},
		{
			-- fails when a held click is paid for each command instead of for each blow: the first command starts the blow (the engine moves the next fire time), the next ones find
			-- the weapon not ready; the blow after the cooldown is paid again
			name = "OnCommand: a held click pays each blow once, not each command",
			func = function()
				local crowbar = weapon("weapon_crowbar", ply)

				suit(Modes.STRENGTH, 100)
				SM.Track(ply, crowbar, 10)

				SM.OnCommand(ply, command(IN_ATTACK), crowbar, 10)
				expect(ply:GetNW2Float("GryEnergy")).to.equal(80)
				crowbar.nextPrimary = 10.5 -- what the engine does with the blow

				for i = 1, 10 do
					SM.OnCommand(ply, command(IN_ATTACK), crowbar, 10 + i * 0.015)
				end

				expect(ply:GetNW2Float("GryEnergy")).to.equal(80)

				SM.OnCommand(ply, command(IN_ATTACK), crowbar, 10.51) -- the weapon is ready again: second blow
				expect(ply:GetNW2Float("GryEnergy")).to.equal(60)
			end
		},
		{
			-- fails when the price ignores its setting (0 = free), or is taken while the armor is infinite
			name = "OnCommand: gry_suit_melee_cost scales the price, and an infinite armor pays nothing",
			func = function()
				local crowbar = weapon("weapon_stunstick", ply)

				withSetting("gry_suit_melee_cost", "0", function()
					suit(Modes.STRENGTH, 100)
					SM.Track(ply, crowbar, 10)
					SM.OnCommand(ply, command(IN_ATTACK), crowbar, 10)
					expect(ply:GetNW2Float("GryEnergy")).to.equal(100)
				end)

				withSetting("gry_suit_melee_cost", "2", function()
					suit(Modes.STRENGTH, 100)
					crowbar.nextPrimary = 0
					SM.OnCommand(ply, command(IN_ATTACK), crowbar, 10)
					expect(ply:GetNW2Float("GryEnergy")).to.equal(60)
				end)

				local infinite = GryMod.Config.InfiniteArmor

				GryMod.Config.InfiniteArmor = true

				local ok, err = pcall(function()
					suit(Modes.STRENGTH, 100)
					crowbar.nextPrimary = 0
					SM.OnCommand(ply, command(IN_ATTACK), crowbar, 10)
					expect(ply:GetNW2Float("GryEnergy")).to.equal(100)
				end)

				GryMod.Config.InfiniteArmor = infinite

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails when the speed mode does not shorten the time before the next blow of a crowbar to 1/1.5 of what the engine set (0.5 s becomes 0.333 s), when it is shortened
			-- again at every command (the rate would pile up), or when it happens in another mode or with gry_suit_handling at 0
			name = "OnCommand: in the speed mode the time before the next blow is shortened once, by 1.5",
			func = function()
				local crowbar = weapon("weapon_crowbar", ply)

				suit(Modes.SPEED, 100)
				SM.Track(ply, crowbar, 10)
				SM.OnCommand(ply, command(IN_ATTACK), crowbar, 10)
				crowbar.nextPrimary = 10.5 -- the engine: the blow, a cooldown of 0.5 s
				crowbar.nextSecondary = 10.5

				SM.OnCommand(ply, command(IN_ATTACK), crowbar, 10.015)
				expect(math.abs(crowbar.nextPrimary - (10 + 0.5 / 1.5)) < 0.0001).to.beTrue()
				expect(math.abs(crowbar.nextSecondary - (10 + 0.5 / 1.5)) < 0.0001).to.beTrue()

				local once = crowbar.nextPrimary

				for i = 2, 6 do
					SM.OnCommand(ply, command(IN_ATTACK), crowbar, 10 + i * 0.015)
				end

				expect(crowbar.nextPrimary).to.equal(once) -- not shortened again

				-- another mode, and the setting
				for _, case in ipairs({{Modes.STRENGTH, "1"}, {Modes.ARMOR, "1"}, {Modes.SPEED, "0"}}) do
					withSetting("gry_suit_handling", case[2], function()
						local w = weapon("weapon_crowbar", ply)

						suit(case[1], 100)
						SM.Track(ply, w, 20)
						SM.OnCommand(ply, command(IN_ATTACK), w, 20)
						w.nextPrimary = 20.5
						SM.OnCommand(ply, command(IN_ATTACK), w, 20.015)
						expect(w.nextPrimary).to.equal(20.5)
					end)
				end
			end
		},
		{
			-- fails when the draw of the engine weapons is not played at x1.75 in the speed mode (the time before the first blow is the draw's), or when it is changed in another mode
			name = "OnSwitch: the draw of a crowbar is shortened by 1.75 in the speed mode only",
			func = function()
				local crowbar = weapon("weapon_crowbar", ply)

				suit(Modes.SPEED, 100)
				SM.OnSwitch(ply, nil, crowbar, 30)
				crowbar.nextPrimary = 31 -- the engine: a draw of 1 s
				crowbar.nextSecondary = 31
				SM.OnCommand(ply, command(0), crowbar, 30.015)
				expect(math.abs(crowbar.nextPrimary - (30 + 1 / 1.75)) < 0.0001).to.beTrue()

				local other = weapon("weapon_stunstick", ply)

				suit(Modes.STRENGTH, 100)
				SM.OnSwitch(ply, crowbar, other, 40)
				other.nextPrimary = 41
				SM.OnCommand(ply, command(0), other, 40.015)
				expect(other.nextPrimary).to.equal(41)
			end
		},
		{
			-- fails when the commands of a player are watched without a reason: the hook is added when a stock engine melee weapon comes into a hand and removed when none is
			-- left (no permanent hook: the owner's rule), when the fists (a SWEP of Lua) or another weapon are tracked, or when a weapon put away leaves the player tracked
			name = "OnSwitch: the StartCommand hook exists only while a crowbar or a stun baton is in a hand",
			func = function()
				local hooks = function() return hook.GetTable().StartCommand and hook.GetTable().StartCommand[KEY] end
				local crowbar = weapon("weapon_crowbar", ply)

				expect(SM.Tracked()).to.equal(0)
				expect(hooks()).to.beNil()

				SM.OnSwitch(ply, nil, weapon("weapon_pistol", ply))
				SM.OnSwitch(ply, nil, weapon("weapon_fists", ply)) -- written in Lua: decorated, not tracked
				expect(SM.Tracked()).to.equal(0)
				expect(hooks()).to.beNil()

				SM.OnSwitch(ply, nil, crowbar)
				expect(SM.Tracked()).to.equal(1)
				expect(hooks()).to.exist()

				SM.OnSwitch(ply, crowbar, weapon("weapon_pistol", ply)) -- put away
				expect(SM.Tracked()).to.equal(0)
				expect(hooks()).to.beNil()
			end
		},
		{
			-- fails when a player whose weapon is no longer in hand (died, stripped, another weapon selected by a way that has no switch event) stays watched and keeps paying
			name = "OnCommand: a player who no longer holds the weapon stops being tracked and pays nothing",
			func = function()
				local crowbar = weapon("weapon_crowbar", ply)

				suit(Modes.STRENGTH, 100)
				SM.Track(ply, crowbar, 10)
				SM.OnCommand(ply, command(IN_ATTACK), weapon("weapon_pistol", ply), 10)
				expect(ply:GetNW2Float("GryEnergy")).to.equal(100)
				expect(SM.Tracked()).to.equal(0)
				expect(hook.GetTable().StartCommand[KEY]).to.beNil()
			end
		},
		{
			-- fails when the fists' attack is not decorated: a blow takes the price when it starts (20 of the bar in the strength mode), the cooldown is shortened by 1.5 in the speed
			-- mode (0.9 s becomes 0.6 s), and in the other modes it is the game's own 0.9 s. REAL fists of the real player, its real attack function
			name = "the real fists: a blow takes its price when it starts, and is 1.5 times quicker in the speed mode",
			func = function()
				ply:StripWeapon("weapon_fists")

				local given = ply:Give("weapon_fists")

				expect(IsValid(given)).to.beTrue()
				suit(Modes.STRENGTH, 100)
				given:PrimaryAttack()
				expect(ply:GetNW2Float("GryEnergy")).to.equal(80)
				expect(math.abs(given:GetNextPrimaryFire() - CurTime() - 0.9) < 0.001).to.beTrue()

				suit(Modes.SPEED, 100)
				given:PrimaryAttack()
				expect(ply:GetNW2Float("GryEnergy")).to.equal(90)
				expect(math.abs(given:GetNextPrimaryFire() - CurTime() - 0.6) < 0.001).to.beTrue()
				expect(math.abs(given:GetNextSecondaryFire() - CurTime() - 0.6) < 0.001).to.beTrue()
				expect(math.abs(given:GetNextMeleeAttack() - CurTime() - 0.2 / 1.5) < 0.001).to.beTrue()
				expect(math.abs(ply:GetViewModel():GetPlaybackRate() - 1.5) < 0.001).to.beTrue()

				-- the right click is the other hand: the same
				suit(Modes.SPEED, 100)
				given:SecondaryAttack()
				expect(ply:GetNW2Float("GryEnergy")).to.equal(90)

				-- back to normal: the armor mode plays the game's own timing and the view model's rate is back to 1
				suit(Modes.ARMOR, 100)
				given:PrimaryAttack()
				expect(ply:GetNW2Float("GryEnergy")).to.equal(100)
				expect(math.abs(given:GetNextPrimaryFire() - CurTime() - 0.9) < 0.001).to.beTrue()
				expect(math.abs(ply:GetViewModel():GetPlaybackRate() - 1) < 0.001).to.beTrue()

				given:Remove()
			end
		},
		{
			-- fails when the push of the fists on a prop (a force the weapon applies itself, not through the damage) does not follow the rule, or when the value is not put back
			-- (a leak would multiply it again at every blow)
			name = "the real fists: the push applied by the weapon follows the strength rule, and the weapon's own value is put back",
			func = function()
				ply:StripWeapon("weapon_fists")

				local given = ply:Give("weapon_fists")
				local seen = {}
				local original = given.HitForceScale

				-- a stand-in for the weapon's own function: it reads the value the weapon has at that moment
				local function spy(self)
					seen[#seen + 1] = self.HitForceScale
				end

				suit(Modes.STRENGTH, 100)
				SM.CallScaled(given, spy)
				expect(math.abs(seen[1] - original * 9.2) < 0.01).to.beTrue()
				expect(given.HitForceScale).to.equal(original)

				suit(Modes.ARMOR, 100)
				SM.CallScaled(given, spy)
				expect(seen[2]).to.equal(original)

				-- an error in the weapon's function does not leave the value changed
				suit(Modes.STRENGTH, 100)
				pcall(SM.CallScaled, given, function() error("boom") end)
				expect(given.HitForceScale).to.equal(original)

				given:Remove()
			end
		}
	}
}
