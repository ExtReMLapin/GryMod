-- Tests of the shotgun icon of the weapon slot (GryMod.FlashHUD.IsShotgun and FireModeFor, lua/grymod/client/cl_hud_flash.lua), GLuaTest format, client realm. The movie has a Shotgun icon; the
-- stock shotgun shows it, but the weapons of the other bases showed the single shot icon of a rifle. A shotgun is told by what is the same in every base, not by a name: it fires several pellets
-- at once (ARC9 and ArcCW: SWEP.Num, TFA: Primary.NumShots) or it uses a shotgun ammunition (the name of its primary ammunition: buckshot, a gauge...). Only a weapon that would show the single shot
-- icon is changed: an automatic one keeps its Auto icon (its fire rate is what the icon tells), a burst its Burst. Each case names the change that makes it fail.

local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

-- a weapon stand-in of a base: its markers, its fire mode answer, its pellets and ammunition
local function weapon(fields)
	local w = {IsValid = function() return true end, GetPrimaryAmmoType = function() return -1 end}

	for k, v in pairs(fields or {}) do
		w[k] = v
	end

	return w
end

return {
	groupName = "GryMod HUD: the shotgun icon",
	afterEach = function()
		for i = #saved, 1, -1 do
			pcall(function() saved[i][1][saved[i][2]] = saved[i][3] end)
		end

		saved = {}
	end,
	cases = {
		{
			-- fails when the function does not exist; when a weapon that fires several pellets is not a shotgun (the Firearms 2 shotgun of the owner: SWEP.Num = 12); when a rifle (one bullet) is
			name = "IsShotgun: several pellets for a trigger pull (Num of ARC9 and ArcCW, Primary.NumShots of TFA), not one bullet",
			func = function()
				local M = GryMod.FlashHUD

				expect(isfunction(M.IsShotgun)).to.beTrue()

				expect(M.IsShotgun(weapon({Num = 12}))).to.beTrue()
				expect(M.IsShotgun(weapon({Num = 8}))).to.beTrue()
				expect(M.IsShotgun(weapon({Primary = {NumShots = 9}}))).to.beTrue()

				expect(M.IsShotgun(weapon({Num = 1}))).to.beFalse()
				expect(M.IsShotgun(weapon({Primary = {NumShots = 1}}))).to.beFalse()
				expect(M.IsShotgun(weapon())).to.beFalse()
				expect(M.IsShotgun(weapon({Num = "twelve"}))).to.beFalse() -- a value that is no number is no information
			end
		},
		{
			-- fails when a weapon of a base that does not say its pellets (the stock-like ones, CW 2.0, FA:S 2.0) but uses a shotgun ammunition is not told by that ammunition, or when a rifle's is
			name = "IsShotgun: the name of the primary ammunition (buckshot, a gauge, a shotgun shell), whatever the base",
			func = function()
				local M = GryMod.FlashHUD
				local names = {[7] = "Buckshot", [8] = "12gauge", [9] = "12 Gauge", [10] = "5.56x45MM", [11] = "Pistol"}

				stub(game, "GetAmmoName", function(id) return names[id] end)

				expect(M.IsShotgun(weapon({GetPrimaryAmmoType = function() return 7 end}))).to.beTrue()
				expect(M.IsShotgun(weapon({GetPrimaryAmmoType = function() return 8 end}))).to.beTrue()
				expect(M.IsShotgun(weapon({GetPrimaryAmmoType = function() return 9 end}))).to.beTrue()
				expect(M.IsShotgun(weapon({GetPrimaryAmmoType = function() return 10 end}))).to.beFalse()
				expect(M.IsShotgun(weapon({GetPrimaryAmmoType = function() return 11 end}))).to.beFalse()
				expect(M.IsShotgun(weapon({GetPrimaryAmmoType = function() return -1 end}))).to.beFalse() -- no ammunition
				expect(M.IsShotgun(weapon({GetPrimaryAmmoType = function() error("no such method answer") end}))).to.beFalse()
			end
		},
		{
			-- fails when a pump or semi-automatic shotgun of a base shows the single shot icon of a rifle, when an automatic shotgun loses its Auto icon, or when a rifle is turned into a shotgun
			name = "FireModeFor: a shotgun that would show Single shows the Shotgun icon; Auto and Burst stay; a rifle stays Single",
			func = function()
				local M = GryMod.FlashHUD

				local function arc9(fields)
					local w = weapon({ARC9 = true, GetCurrentFiremode = function() return 1 end, GetUBGL = function() return false end, GetSafe = function() return false end})

					for k, v in pairs(fields or {}) do w[k] = v end

					return w
				end

				expect(M.FireModeFor(arc9({Num = 8}))).to.equal("Shotgun") -- a pump shotgun (one shot at a time)
				expect(M.FireModeFor(arc9({Num = 8, GetCurrentFiremode = function() return -1 end}))).to.equal("Auto") -- an automatic one keeps Auto
				expect(M.FireModeFor(arc9({Num = 8, GetCurrentFiremode = function() return 2 end}))).to.equal("Burst")
				expect(M.FireModeFor(arc9({Num = 1}))).to.equal("Single") -- a rifle

				-- TFA: the fire modes are names
				local function tfa(fields)
					local w = weapon({IsTFAWeapon = true, FireModes = {"Semi"}, GetFireMode = function() return 1 end})

					for k, v in pairs(fields or {}) do w[k] = v end

					return w
				end

				expect(M.FireModeFor(tfa({Primary = {NumShots = 9}}))).to.equal("Shotgun")
				expect(M.FireModeFor(tfa({Primary = {NumShots = 1}}))).to.equal("Single")
			end
		}
	}
}
