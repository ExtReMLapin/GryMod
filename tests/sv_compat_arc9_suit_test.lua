-- Tests of the ARC9 adapters of the suit's effects (lua/grymod/compat/weapons/sh_arc9_suit.lua, sv_arc9_suit.lua and sv_arc9.lua), GLuaTest format, server realm (the settings are
-- replicated: only the server may change them). ARC9 runs a global hook for each stat it reads and each hook point of its weapons (hook.Run("ARC9_" .. name, weapon, value),
-- sh_0_stats.lua): the cases run those hooks with stand-ins for the weapon, the player and the damage, so that they need no ARC9: they pin what the adapters answer and what they
-- call. The rules themselves are in tests/sh_suit_weapons_test.lua; one case runs against a real ARC9 weapon when ARC9 is installed. Each case names the change that makes it fail.

local Modes
local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

-- a stand-in player: answers what the adapters ask
local function fakePlayer(mode, energy)
	local ply = {mode = mode, energy = energy, energyAdded = 0, weapons = {}}

	function ply:IsValid() return true end
	function ply:IsPlayer() return true end
	function ply:GetNW2Int(key, default) if key == "GryMode" then return self.mode end return default end
	function ply:GetNW2Float(key, default) if key == "GryEnergy" then return self.energy end return default end
	function ply:GetWeapons() return self.weapons end

	return ply
end

local function weapon(owner, fields)
	local wep = {ARC9 = true, cleared = 0}

	function wep:IsValid() return true end
	function wep:GetOwner() return owner end
	function wep:GetClass() return "test_arc9_weapon" end
	function wep:ClearLongCache() self.cleared = self.cleared + 1 end

	for k, v in pairs(fields or {}) do
		wep[k] = v
	end

	if owner and owner.weapons then
		owner.weapons[#owner.weapons + 1] = wep
	end

	return wep
end

local function damage(amount)
	local info = {amount = amount, force = Vector(10, 0, 0)}

	function info:ScaleDamage(m) self.amount = self.amount * m end
	function info:GetDamageForce() return self.force end
	function info:SetDamageForce(v) self.force = v end

	return info
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

local function near(a, b)
	return a ~= nil and math.abs(a - b) < 0.001
end

return {
	groupName = "GryMod suit effects on ARC9 weapons",
	beforeEach = function()
		Modes = GryMod.Modes
	end,
	afterEach = function()
		for i = #saved, 1, -1 do
			saved[i][1][saved[i][2]] = saved[i][3]
		end

		saved = {}
	end,
	cases = {
		{
			-- fails when the recoil of a strength mode player is not scaled by the rules' multiplier (x0.375 with a full bar) in the two stats ARC9 reads for the kick of a shot (Recoil: the
			-- view kick, every up / side value is multiplied by it; VisualRecoil: the kick of the gun on the screen), when another stat is touched, or when a value that is no number is changed
			name = "ARC9_RecoilHook and ARC9_VisualRecoilHook: scaled in the strength mode (x0.375 with a full bar); no other stat, no other value type",
			func = function()
				local wep = weapon(fakePlayer(Modes.STRENGTH, 100))

				expect(near(hook.Run("ARC9_RecoilHook", wep, 2), 0.75)).to.beTrue()
				expect(near(hook.Run("ARC9_VisualRecoilHook", wep, 2), 0.75)).to.beTrue()
				expect(hook.Run("ARC9_DamageMaxHook", wep, 30)).to.beNil()
				expect(hook.Run("ARC9_RecoilHook", wep, "text")).to.beNil()
				expect(hook.Run("ARC9_RecoilHook", wep, nil)).to.beNil()
			end
		},
		{
			-- fails when the effect is applied to a weapon with no player (an NPC, a dropped weapon) or to a weapon that is not ARC9's, or does not follow the mode and the energy of the
			-- holder, or when the setting gry_suit_strength_recoil does not switch it off
			name = "recoil: nothing for a weapon without a player or that is not ARC9's, the answer follows the holder's mode and energy, and gry_suit_strength_recoil 0 switches it off",
			func = function()
				local npc = {IsValid = function() return true end, IsPlayer = function() return false end}

				expect(hook.Run("ARC9_RecoilHook", weapon(npc), 2)).to.beNil()
				expect(hook.Run("ARC9_RecoilHook", weapon(nil), 2)).to.beNil()
				expect(hook.Run("ARC9_RecoilHook", weapon(fakePlayer(Modes.STRENGTH, 100), {ARC9 = false}), 2)).to.beNil()

				-- the armor mode keeps almost all of the kick, an empty strength bar gives back 90 percent
				expect(near(hook.Run("ARC9_RecoilHook", weapon(fakePlayer(Modes.ARMOR, 100)), 2), 2 * 0.9375)).to.beTrue()
				expect(near(hook.Run("ARC9_RecoilHook", weapon(fakePlayer(Modes.STRENGTH, 0)), 2), 1.8)).to.beTrue()

				withSetting("gry_suit_strength_recoil", "0", function()
					expect(hook.Run("ARC9_RecoilHook", weapon(fakePlayer(Modes.STRENGTH, 100)), 2)).to.beNil()
				end)
			end
		},
		{
			-- fails when the draw, the holster, the raise after a sprint and the fire mode switch are not played x1.75 in the speed mode (ARC9's anim speed is a TIME multiplier: x1/1.75),
			-- when the lock-out (which ARC9 computes from the same number) would not follow, when the animations the original does not speed up are touched (sights, inspect, firing), or
			-- when a number another addon's hook already put in .Mult is lost
			name = "ARC9_Hook_TranslateAnimSpeed: draw, holster, ready, sprint exit and fire mode switch take 1/1.75 of the time in the speed mode; the others are left alone",
			func = function()
				local wep = weapon(fakePlayer(Modes.SPEED, 100))

				for _, anim in ipairs({"draw", "draw_empty", "draw_quick", "holster", "holster_quick", "ready", "exit_sprint", "firemode", "firemode_2"}) do
					local data = {mult = 1, anim = anim}
					local answer = hook.Run("ARC9_Hook_TranslateAnimSpeed", wep, data)

					expect(answer ~= nil and near(answer.Mult, 1 / 1.75)).to.beTrue()
				end

				-- a draw that is already faster (DeployTime 0.5): the rule goes on the time it has
				expect(near(hook.Run("ARC9_Hook_TranslateAnimSpeed", wep, {mult = 0.5, anim = "draw"}).Mult, 0.5 / 1.75)).to.beTrue()

				-- the number another addon's hook already put in Mult is the one scaled
				expect(near(hook.Run("ARC9_Hook_TranslateAnimSpeed", wep, {mult = 1, Mult = 0.8, anim = "draw"}).Mult, 0.8 / 1.75)).to.beTrue()

				for _, anim in ipairs({"idle", "fire", "enter_sights", "exit_sights", "enter_sprint", "enter_inspect", "inspect", "bash", "bash2", "backstab", "impact", "reload", "reload_empty", "cycle", "dryfire", "switchsights"}) do
					expect(hook.Run("ARC9_Hook_TranslateAnimSpeed", wep, {mult = 1, anim = anim})).to.beNil()
				end

				expect(hook.Run("ARC9_Hook_TranslateAnimSpeed", wep, {mult = 1})).to.beNil()
				expect(hook.Run("ARC9_Hook_TranslateAnimSpeed", wep, nil)).to.beNil()
			end
		},
		{
			-- fails when the handling is faster in a mode that is not the speed mode, when gry_suit_handling does not switch it off, or when a weapon with no player is changed
			name = "handling: only the speed mode, only with gry_suit_handling on, only for a weapon a player holds",
			func = function()
				for _, mode in ipairs({Modes.ARMOR, Modes.STRENGTH, Modes.CLOAK}) do
					expect(hook.Run("ARC9_Hook_TranslateAnimSpeed", weapon(fakePlayer(mode, 100)), {mult = 1, anim = "draw"})).to.beNil()
				end

				expect(hook.Run("ARC9_Hook_TranslateAnimSpeed", weapon(nil), {mult = 1, anim = "draw"})).to.beNil()

				withSetting("gry_suit_handling", "0", function()
					expect(hook.Run("ARC9_Hook_TranslateAnimSpeed", weapon(fakePlayer(Modes.SPEED, 100)), {mult = 1, anim = "draw"})).to.beNil()
					expect(hook.Run("ARC9_BashSpeedHook", weapon(fakePlayer(Modes.SPEED, 100)), 1)).to.beNil()
				end)
			end
		},
		{
			-- fails when the melee swing is not x1.5 in the speed mode through ARC9's BashSpeed (the number it divides the swing's times and its animation by: the lock-out and the moment
			-- of the hit follow), when the animation hook speeds the swing up as well (twice), or when another mode changes it
			name = "ARC9_BashSpeedHook: the melee swing is x1.5 in the speed mode only, and the animation hook leaves the swing's animations to it",
			func = function()
				expect(near(hook.Run("ARC9_BashSpeedHook", weapon(fakePlayer(Modes.SPEED, 100)), 1), 1.5)).to.beTrue()
				expect(near(hook.Run("ARC9_BashSpeedHook", weapon(fakePlayer(Modes.SPEED, 100)), 2), 3)).to.beTrue()
				expect(hook.Run("ARC9_BashSpeedHook", weapon(fakePlayer(Modes.STRENGTH, 100)), 1)).to.beNil()
				expect(hook.Run("ARC9_BashSpeedHook", weapon(fakePlayer(Modes.SPEED, 100)), "x")).to.beNil()
			end
		},
		{
			-- fails when the reload is faster than gry_suit_reload_rate says (the original does not speed it up: 1), when the setting is not a divisor of ARC9's ReloadTime (a TIME
			-- multiplier that its timers use too: the magazine swap, the dropped magazine), or when another mode changes it
			name = "ARC9_ReloadTimeHook: the reload follows gry_suit_reload_rate in the speed mode (1 = the original's: nothing), as a time multiplier",
			func = function()
				local wep = weapon(fakePlayer(Modes.SPEED, 100))

				expect(hook.Run("ARC9_ReloadTimeHook", wep, 1)).to.beNil() -- the original does not speed a reload up

				withSetting("gry_suit_reload_rate", "2", function()
					expect(near(hook.Run("ARC9_ReloadTimeHook", wep, 1), 0.5)).to.beTrue()
					expect(near(hook.Run("ARC9_ReloadTimeHook", wep, 0.8), 0.4)).to.beTrue()
					expect(hook.Run("ARC9_ReloadTimeHook", weapon(fakePlayer(Modes.STRENGTH, 100)), 1)).to.beNil()
				end)
			end
		},
		{
			-- fails when ARC9's long cache (a processed value read as static is kept for a minute: BashSpeed is read that way) keeps the old mode's number: the weapons of the player have to
			-- be asked to forget it when the mode changes, and only the weapons of that player, and only ARC9's
			name = "a change of mode (GryMod_ModeChanged) clears the long cache of the player's ARC9 weapons and of no other weapon",
			func = function()
				local ply = fakePlayer(Modes.SPEED, 100)
				local a, b = weapon(ply), weapon(ply)
				local other = weapon(ply, {ARC9 = false})
				local elsewhere = weapon(fakePlayer(Modes.SPEED, 100))

				-- the adapter's own listener, called directly (the other listeners of the hook need a real player)
				hook.GetTable().GryMod_ModeChanged["GryMod compat arc9 suit"](ply, Modes.ARMOR, Modes.SPEED, 0)

				expect(a.cleared).to.equal(1)
				expect(b.cleared).to.equal(1)
				expect(other.cleared).to.equal(0)
				expect(elsewhere.cleared).to.equal(0)
			end
		},
		{
			-- fails when a melee hit (the bash of a gun, the swing of a knife) is not multiplied in the strength mode, damage and push, from ARC9's own hook before the damage is applied; when
			-- it is also multiplied in another mode; or when gry_suit_strength_melee does not switch it off
			name = "ARC9_Hook_BashHit: the damage and the push of a hit are multiplied by the energy in the strength mode (x9.2 with a full bar), only there, only with gry_suit_strength_melee on",
			func = function()
				local function hit(ply, scaleSetting)
					local info = damage(10)

					hook.Run("ARC9_Hook_BashHit", weapon(ply), {tr = {}, dmg = info})

					return info
				end

				local full = hit(fakePlayer(Modes.STRENGTH, 100))

				expect(near(full.amount, 92)).to.beTrue()
				expect(near(full.force.x, 92)).to.beTrue()

				local half = hit(fakePlayer(Modes.STRENGTH, 50))

				expect(near(half.amount, 42)).to.beTrue()

				for _, mode in ipairs({Modes.ARMOR, Modes.SPEED, Modes.CLOAK}) do
					expect(hit(fakePlayer(mode, 100)).amount).to.equal(10)
				end

				expect(hit(fakePlayer(Modes.STRENGTH, 0)).amount).to.equal(10)

				withSetting("gry_suit_strength_melee", "0", function()
					expect(hit(fakePlayer(Modes.STRENGTH, 100)).amount).to.equal(10)
				end)

				-- nothing for a weapon with no player, nor for what is no hit
				local info = damage(10)

				hook.Run("ARC9_Hook_BashHit", weapon(nil), {tr = {}, dmg = info})
				hook.Run("ARC9_Hook_BashHit", weapon(fakePlayer(Modes.STRENGTH, 100)), nil)
				hook.Run("ARC9_Hook_BashHit", weapon(fakePlayer(Modes.STRENGTH, 100)), {})
				expect(info.amount).to.equal(10)
			end
		},
		{
			-- fails when a shot does not take the energy of the rule in the strength mode (7.5 of 100 by default), takes it in another mode, goes under 0, takes it while the armor is
			-- infinite, or is counted for a weapon with no player
			name = "ARC9_Hook_PrimaryAttack: each shot takes the energy of the rule in the strength mode, nothing in the other modes or with an infinite armor",
			func = function()
				local added = {}

				stub(GryMod.API, "AddEnergy", function(ply, amount) added[#added + 1] = {ply = ply, amount = amount} end)

				local ply = fakePlayer(Modes.STRENGTH, 100)

				hook.Run("ARC9_Hook_PrimaryAttack", weapon(ply))
				expect(#added).to.equal(1)
				expect(added[1].ply).to.equal(ply)
				expect(near(added[1].amount, -7.5)).to.beTrue()

				for _, mode in ipairs({Modes.ARMOR, Modes.SPEED, Modes.CLOAK}) do
					hook.Run("ARC9_Hook_PrimaryAttack", weapon(fakePlayer(mode, 100)))
				end

				hook.Run("ARC9_Hook_PrimaryAttack", weapon(nil))
				expect(#added).to.equal(1)

				withSetting("gry_suit_shot_cost", "15", function()
					hook.Run("ARC9_Hook_PrimaryAttack", weapon(ply))
					expect(near(added[2].amount, -15)).to.beTrue()
				end)

				stub(GryMod.Config, "InfiniteArmor", true)
				hook.Run("ARC9_Hook_PrimaryAttack", weapon(ply))
				expect(#added).to.equal(2)
			end
		},
		{
			-- fails when a bash (a knife swing, the stab, the butt stroke) costs nothing in the strength and speed modes: 10 and 7.5 of the bar
			name = "ARC9_Hook_Bash: a blow takes the melee price in the strength and speed modes, nothing in the others",
			func = function()
				local added = {}

				stub(GryMod.API, "AddEnergy", function(ply, amount) added[#added + 1] = amount end)

				hook.GetTable().ARC9_Hook_Bash["GryMod compat arc9 suit"](weapon(fakePlayer(Modes.STRENGTH, 100)), {})
				hook.GetTable().ARC9_Hook_Bash["GryMod compat arc9 suit"](weapon(fakePlayer(Modes.SPEED, 100)), {})
				hook.GetTable().ARC9_Hook_Bash["GryMod compat arc9 suit"](weapon(fakePlayer(Modes.ARMOR, 100)), {})
				expect(#added).to.equal(2)
				expect(near(added[1], -10)).to.beTrue()
				expect(near(added[2], -7.5)).to.beTrue()
			end
		},
		{
			-- fails when the calibre is not read from ARC9's ammunition (its Primary.Ammo, set from the weapon's Ammo): a magnum round must cost 1.5 times the plain price, an SMG round 0.75
			name = "ARC9_Hook_PrimaryAttack: the price of a shot follows the calibre of the weapon's ammunition",
			func = function()
				local added = {}

				stub(GryMod.API, "AddEnergy", function(ply, amount) added[#added + 1] = amount end)

				local ply = fakePlayer(Modes.STRENGTH, 100)

				hook.Run("ARC9_Hook_PrimaryAttack", weapon(ply, {Primary = {Ammo = "357"}}))
				hook.Run("ARC9_Hook_PrimaryAttack", weapon(ply, {Primary = {Ammo = "smg1"}}))
				hook.Run("ARC9_Hook_PrimaryAttack", weapon(ply, {Primary = {}}))
				expect(near(added[1], -7.5 * 1.5)).to.beTrue()
				expect(near(added[2], -7.5 * 0.75)).to.beTrue()
				expect(near(added[3], -7.5)).to.beTrue() -- no ammunition name: the plain price
			end
		},
		{
			-- fails when a bash (the swing of a knife, the stab, the butt stroke of a gun) does not end the camouflage, through ARC9's own hook at the moment of the blow, as a left click attack
			name = "ARC9_Hook_Bash: a blow is reported as an attack (not the right click)",
			func = function()
				local reports = {}

				stub(GryMod.API, "ReportAttack", function(ply, right) reports[#reports + 1] = {ply = ply, right = right} end)

				local ply = fakePlayer(Modes.CLOAK, 100)

				hook.Run("ARC9_Hook_Bash", weapon(ply), {})
				expect(#reports).to.equal(1)
				expect(reports[1].ply).to.equal(ply)
				expect(reports[1].right).to.beFalse()

				hook.Run("ARC9_Hook_Bash", weapon(nil), {})
				hook.Run("ARC9_Hook_Bash", weapon(ply, {ARC9 = false}), {})
				expect(#reports).to.equal(1)
			end
		},
		{
			-- fails when the launcher under the barrel or a weapon that shoots an entity (a rocket, a grenade) does not end the camouflage (they fire no bullet: the server does not see
			-- them), or when a gun that fires bullets reports twice (its bullets are seen by the server already)
			name = "ARC9_Hook_PrimaryAttack: a shot of the launcher or of an entity-firing weapon is reported as an attack, a plain gun's is not (its bullets are seen)",
			func = function()
				local reports = {}

				stub(GryMod.API, "ReportAttack", function(ply, right) reports[#reports + 1] = {ply = ply, right = right} end)
				stub(GryMod.API, "AddEnergy", function() end)

				local ply = fakePlayer(Modes.CLOAK, 100)

				hook.Run("ARC9_Hook_PrimaryAttack", weapon(ply)) -- a gun
				hook.Run("ARC9_Hook_PrimaryAttack", weapon(ply, {GetUBGL = function() return false end, GetProcessedValue = function() return nil end}))
				expect(#reports).to.equal(0)

				hook.Run("ARC9_Hook_PrimaryAttack", weapon(ply, {GetUBGL = function() return true end}))
				expect(#reports).to.equal(1)

				hook.Run("ARC9_Hook_PrimaryAttack", weapon(ply, {GetUBGL = function() return false end, GetProcessedValue = function(_, name) return name == "ShootEnt" and "arc9_rocket" or nil end}))
				expect(#reports).to.equal(2)
				expect(reports[2].right).to.beFalse()
			end
		},
		{
			-- fails when a thrown grenade does not end the camouflage
			name = "ARC9_Hook_GrenadeThrown: a throw is reported as an attack",
			func = function()
				local reports = {}

				stub(GryMod.API, "ReportAttack", function(ply, right) reports[#reports + 1] = {ply = ply, right = right} end)

				local ply = fakePlayer(Modes.CLOAK, 100)

				hook.Run("ARC9_Hook_GrenadeThrown", weapon(ply), {})
				expect(#reports).to.equal(1)
				expect(reports[1].right).to.beFalse()

				hook.Run("ARC9_Hook_GrenadeThrown", weapon(nil), {})
				expect(#reports).to.equal(1)
			end
		},
		{
			-- fails when a hook raises an error into ARC9's own code (an error there breaks the weapon): the answers are computed under pcall, whatever the weapon and the player are
			name = "never an error into ARC9: odd weapons, players and values are answered with nothing",
			func = function()
				local broken = {ARC9 = true, IsValid = function() return true end, GetOwner = function() error("boom") end}

				for _, name in ipairs({"ARC9_RecoilHook", "ARC9_VisualRecoilHook", "ARC9_BashSpeedHook", "ARC9_ReloadTimeHook", "ARC9_Hook_TranslateAnimSpeed", "ARC9_Hook_BashHit", "ARC9_Hook_PrimaryAttack", "ARC9_Hook_Bash", "ARC9_Hook_GrenadeThrown"}) do
					local ok = pcall(hook.Run, name, broken, 1)

					expect(ok).to.beTrue()
					expect(pcall(hook.Run, name, nil, 1)).to.beTrue()
					expect(pcall(hook.Run, name, {}, {})).to.beTrue()
					expect(pcall(hook.Run, name, 5, "x")).to.beTrue()
				end

				expect(pcall(hook.GetTable().GryMod_ModeChanged["GryMod compat arc9 suit"], {}, 0, 1, 0)).to.beTrue()
			end
		}
	}
}
