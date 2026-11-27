-- Tests of the rules of what the suit does to a weapon (lua/grymod/sh_suit_weapons.lua), GLuaTest format, shared. The numbers are the original game's, read from its code
-- (the study of 2026-11-27): the strength mode multiplies a melee hit by (1 + 0.01 S) x (1 + 0.036 S) and the kick of a shot by (1 - 0.25 S / 100) x min(0.9, 1 - K x energy),
-- S being the strength slot of the mode at the energy (100 in the strength mode, 50 in the speed and cloak modes, 25 in the armor mode, each scaled by the energy); the speed
-- mode plays the draw, the holster and the raise of a weapon at x1.75 and a melee swing at x1.5, and does NOT change a reload. Each case names the change that makes it fail.

local SW
local Modes

local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 0.001)
end

return {
	groupName = "GryMod suit effects on weapons: the rules",
	beforeEach = function()
		SW = GryMod.SuitWeapons
		Modes = GryMod.Modes
	end,
	cases = {
		{
			-- fails when the module or a function is missing
			name = "the module exists with its rules",
			func = function()
				expect(SW ~= nil).to.beTrue()
				expect(isfunction(SW.MeleeMultiplier)).to.beTrue()
				expect(isfunction(SW.RecoilMultiplier)).to.beTrue()
				expect(isfunction(SW.HandlingRate)).to.beTrue()
				expect(isfunction(SW.ShotCost)).to.beTrue()
			end
		},
		{
			-- fails when the strength is not the product of the two original terms (x9.2 at full energy), when it is not proportional to the energy, or when a mode other than
			-- the strength mode hits harder
			name = "MeleeMultiplier: x9.2 at full energy in the strength mode, x4.2 at half, x1 when empty, and x1 in every other mode",
			func = function()
				expect(near(SW.MeleeMultiplier(Modes.STRENGTH, 1), 9.2)).to.beTrue()
				expect(near(SW.MeleeMultiplier(Modes.STRENGTH, 0.5), 4.2)).to.beTrue()
				expect(near(SW.MeleeMultiplier(Modes.STRENGTH, 0), 1)).to.beTrue()

				for _, mode in ipairs({Modes.ARMOR, Modes.SPEED, Modes.CLOAK}) do
					expect(SW.MeleeMultiplier(mode, 1)).to.equal(1)
				end
			end
		},
		{
			-- fails when a bad energy (nil, NaN, over 1, under 0) gives a multiplier that is not one of the range
			name = "MeleeMultiplier: an energy out of range or not a number is cut to 0 to 1",
			func = function()
				expect(near(SW.MeleeMultiplier(Modes.STRENGTH, 5), 9.2)).to.beTrue()
				expect(near(SW.MeleeMultiplier(Modes.STRENGTH, -2), 1)).to.beTrue()
				expect(near(SW.MeleeMultiplier(Modes.STRENGTH, nil), 1)).to.beTrue()
				expect(near(SW.MeleeMultiplier(Modes.STRENGTH, 0 / 0), 1)).to.beTrue()
			end
		},
		{
			-- fails when the recoil of the strength mode at full energy is not x0.375 (0.75 x 0.5) for a weapon that has no factor of its own, when the empty bar does not give back
			-- 90 percent of the kick, or when the other modes' small reductions (x0.9375 armor, x0.875 speed and cloak) are wrong
			name = "RecoilMultiplier: x0.375 at full energy in the strength mode, x0.656 at half, x0.9 when empty; the other modes only lose a little",
			func = function()
				expect(near(SW.RecoilMultiplier(Modes.STRENGTH, 1), 0.375)).to.beTrue()
				expect(near(SW.RecoilMultiplier(Modes.STRENGTH, 0.5), 0.65625)).to.beTrue()
				expect(near(SW.RecoilMultiplier(Modes.STRENGTH, 0), 0.9)).to.beTrue()
				expect(near(SW.RecoilMultiplier(Modes.ARMOR, 1), 0.9375)).to.beTrue()
				expect(near(SW.RecoilMultiplier(Modes.SPEED, 1), 0.875)).to.beTrue()
				expect(near(SW.RecoilMultiplier(Modes.CLOAK, 1), 0.875)).to.beTrue()
				expect(near(SW.RecoilMultiplier(Modes.ARMOR, 0), 1)).to.beTrue()
			end
		},
		{
			-- fails when a weapon's own factor K is ignored, or when a large K makes the kick negative (a kick that pushes the aim the wrong way)
			name = "RecoilMultiplier: the weapon's own factor changes the strength mode's part, and the result never goes under 0",
			func = function()
				expect(near(SW.RecoilMultiplier(Modes.STRENGTH, 1, 0.25), 0.75 * 0.75)).to.beTrue()
				expect(SW.RecoilMultiplier(Modes.STRENGTH, 1, 5) >= 0).to.beTrue()
				expect(near(SW.RecoilMultiplier(Modes.STRENGTH, 1, 0), 0.675)).to.beTrue() -- no factor of its own: the cap of 0.9 and the slot's 0.75
			end
		},
		{
			-- fails when the speed mode does not play the draw, the holster and the raise at x1.75 and a melee swing at x1.5, when it changes a reload by itself, or when another
			-- mode changes any of them
			name = "HandlingRate: speed mode x1.75 for the draw, holster and raise, x1.5 for a melee swing, x1 for a reload; the other modes change nothing",
			func = function()
				expect(SW.HandlingRate(Modes.SPEED, "draw")).to.equal(1.75)
				expect(SW.HandlingRate(Modes.SPEED, "holster")).to.equal(1.75)
				expect(SW.HandlingRate(Modes.SPEED, "ready")).to.equal(1.75)
				expect(SW.HandlingRate(Modes.SPEED, "melee")).to.equal(1.5)
				expect(SW.HandlingRate(Modes.SPEED, "reload")).to.equal(1)
				expect(SW.HandlingRate(Modes.SPEED, "unknown")).to.equal(1)

				for _, mode in ipairs({Modes.ARMOR, Modes.CLOAK, Modes.STRENGTH}) do
					for _, kind in ipairs({"draw", "holster", "ready", "melee", "reload"}) do
						expect(SW.HandlingRate(mode, kind)).to.equal(1)
					end
				end
			end
		},
		{
			-- fails when the cost of a shot is not taken in the strength mode only (15 of the original's 200 = 7.5 of 100), is not nothing in the other modes, or ignores the setting
			name = "ShotCost: 7.5 of the bar for a shot in the strength mode, nothing in the other modes, and the setting changes it (0 = free)",
			func = function()
				local convar = GetConVar("gry_suit_shot_cost")

				expect(convar ~= nil).to.beTrue()

				local before = convar:GetString()
				local ok, err = pcall(function()
					convar:SetString(convar:GetDefault())
					expect(SW.ShotCost(Modes.STRENGTH)).to.equal(7.5)
					expect(SW.ShotCost(Modes.SPEED)).to.equal(0)
					expect(SW.ShotCost(Modes.ARMOR)).to.equal(0)
					expect(SW.ShotCost(Modes.CLOAK)).to.equal(0)

					convar:SetString("0")
					expect(SW.ShotCost(Modes.STRENGTH)).to.equal(0)
				end)

				convar:SetString(before)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails when the cost of a shot does not follow the calibre (the kind of ammunition): a pistol or SMG round must cost less than a rifle round, a magnum, a sniper round and
			-- buckshot more; an ammunition the table does not know costs the plain price; the setting at 0 gives the flat price of the original game for every weapon
			name = "ShotCost: follows the calibre (pistol and SMG rounds cost less than rifle rounds, magnum, sniper and buckshot more), an unknown ammunition costs the plain price, and gry_suit_shot_cost_by_ammo 0 is the original's flat price",
			func = function()
				local cost = GetConVar("gry_suit_shot_cost")
				local by = GetConVar("gry_suit_shot_cost_by_ammo")

				expect(by ~= nil).to.beTrue()

				local before, beforeBy = cost:GetString(), by:GetString()
				local ok, err = pcall(function()
					cost:SetString("7.5")
					by:SetString("1")
					expect(SW.ShotCost(Modes.STRENGTH, "ar2")).to.equal(7.5)
					expect(near(SW.ShotCost(Modes.STRENGTH, "smg1"), 7.5 * 0.75)).to.beTrue()
					expect(near(SW.ShotCost(Modes.STRENGTH, "pistol"), 7.5 * 0.6)).to.beTrue()
					expect(near(SW.ShotCost(Modes.STRENGTH, "357"), 7.5 * 1.5)).to.beTrue()
					expect(near(SW.ShotCost(Modes.STRENGTH, "SniperRound"), 7.5 * 2)).to.beTrue() -- the case of the name does not matter
					expect(SW.ShotCost(Modes.STRENGTH, "some_modded_ammo")).to.equal(7.5)
					expect(SW.ShotCost(Modes.STRENGTH, nil)).to.equal(7.5)
					expect(SW.ShotCost(Modes.STRENGTH, 5)).to.equal(7.5)
					expect(SW.ShotCost(Modes.SPEED, "357")).to.equal(0)

					by:SetString("0")
					expect(SW.ShotCost(Modes.STRENGTH, "357")).to.equal(7.5)
					expect(SW.ShotCost(Modes.STRENGTH, "pistol")).to.equal(7.5)
				end)

				cost:SetString(before)
				by:SetString(beforeBy)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails when a melee blow is free (the owner saw a knife in the strength mode cost nothing), when the price is not the original's (10 of 100 in the strength mode, 7.5 in the speed
			-- mode: 20 and 15 of its 200), when another mode pays, or when the setting does not scale it (0 = free)
			name = "MeleeCost: 10 of the bar for a blow in the strength mode, 7.5 in the speed mode, nothing in the other modes, scaled by gry_suit_melee_cost (0 = free)",
			func = function()
				local convar = GetConVar("gry_suit_melee_cost")

				expect(convar ~= nil).to.beTrue()

				local before = convar:GetString()
				local ok, err = pcall(function()
					convar:SetString("1")
					expect(SW.MeleeCost(Modes.STRENGTH)).to.equal(10)
					expect(SW.MeleeCost(Modes.SPEED)).to.equal(7.5)
					expect(SW.MeleeCost(Modes.ARMOR)).to.equal(0)
					expect(SW.MeleeCost(Modes.CLOAK)).to.equal(0)

					convar:SetString("2")
					expect(SW.MeleeCost(Modes.STRENGTH)).to.equal(20)

					convar:SetString("0")
					expect(SW.MeleeCost(Modes.STRENGTH)).to.equal(0)
					expect(SW.MeleeCost(Modes.SPEED)).to.equal(0)
				end)

				convar:SetString(before)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails when an effect cannot be switched off (everything is optional) or a default is not on: the original's behaviour is the default, a reload that the original does
			-- not speed up stays at x1
			name = "every effect has its setting, the original's behaviour is the default, and an effect that is off changes nothing",
			func = function()
				for _, name in ipairs({"gry_suit_handling", "gry_suit_strength_melee", "gry_suit_strength_recoil", "gry_suit_shot_cost", "gry_suit_shot_cost_by_ammo", "gry_suit_melee_cost", "gry_suit_reload_rate"}) do
					expect(GetConVar(name) ~= nil).to.beTrue()
				end

				expect(GetConVar("gry_suit_reload_rate"):GetDefault()).to.equal("1")

				local melee = GetConVar("gry_suit_strength_melee")
				local before = melee:GetString()
				local ok, err = pcall(function()
					melee:SetString("0")
					expect(SW.MeleeScale(Modes.STRENGTH, 1)).to.equal(1)
					melee:SetString("1")
					expect(near(SW.MeleeScale(Modes.STRENGTH, 1), 9.2)).to.beTrue()
				end)

				melee:SetString(before)

				if not ok then
					error(err, 0)
				end
			end
		}
	}
}
