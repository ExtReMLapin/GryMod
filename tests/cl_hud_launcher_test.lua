-- Tests of the grenade slot of the Crysis HUD (GryMod.FlashHUD), GLuaTest format, client realm. A weapon with a
-- grenade launcher (the SMG's secondary fire) shows the 40 mm grenade icon of the weapon slot and its own grenade
-- count in the grenade slot, instead of the hand grenades; the hand grenade weapon shows the hand grenade icon.

local function newHud()
	return GryMod.FlashHUD.New(GryMod.Flash.Load("hud_ammohealthenergysuit"))
end

local function slot(hud, name)
	return hud.player.names[name]
end

local function launcherWeapon(ammoName)
	return {
		GetSecondaryAmmoType = function() return game.GetAmmoID(ammoName) end
	}
end

local function player(count)
	return {
		GetAmmoCount = function(_, type) return count end
	}
end

-- the ids of the two icon sets in the movie: the hand grenades (4 frames) and the weapon slot (21 icons)
local function ids(movie)
	local hand, mode
	for id, definition in pairs(movie.chars) do
		if definition.k == "sprite" and definition.labels then
			if definition.labels.explosivegrenade then hand = id end
			if definition.labels.Claymore then mode = id end
		end
	end

	return hand, mode
end

return {
	groupName = "GryMod HUD grenade slot (Flash)",
	cases = {
		{
			name = "a weapon with a grenade launcher gives the number of grenades it holds, other secondary fires and no secondary give nothing",
			func = function(state)
				local M = GryMod.FlashHUD
				expect(M.LauncherFor(player(4), launcherWeapon("SMG1_Grenade"))).to.equal(4)
				expect(M.LauncherFor(player(0), launcherWeapon("SMG1_Grenade"))).to.equal(0)
				expect(M.LauncherFor(player(4), launcherWeapon("AR2AltFire"))).to.beNil()
				expect(M.LauncherFor(player(4), {GetSecondaryAmmoType = function() return -1 end})).to.beNil()
				expect(M.LauncherFor(player(4), nil)).to.beNil()
				expect(M.LauncherFor(player(4), NULL)).to.beNil()
			end
		},
		{
			name = "the hand grenade weapon has the hand grenade icon, not the launcher one",
			func = function(state)
				expect(GryMod.FlashHUD.FireModeFor({GetClass = function() return "weapon_frag" end})).to.equal("HandGrenade")
			end
		},
		{
			name = "with a launcher the grenade slot shows the 40 mm icon and the launcher's count, without it the hand grenades again",
			func = function(state)
				local hud = newHud()
				local hand, mode = ids(GryMod.Flash.Load("hud_ammohealthenergysuit"))
				expect(hand ~= nil and mode ~= nil).to.beTrue()
				local small = "Root.Player.AmmoTexts.MagAmmo.Colorset"

				hud:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto")
				expect(slot(hud, "GrenadeMode").id).to.equal(hand)
				expect(hud.root:Find(small):Child("GrenadeAmmo").text).to.equal("2")

				hud:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto", 5)
				expect(slot(hud, "GrenadeMode").id).to.equal(mode)
				expect(slot(hud, "GrenadeMode").clip:CurrentLabel()).to.equal("Grenade")
				expect(hud.root:Find(small):Child("GrenadeAmmo").text).to.equal("5")
				-- the weapon slot keeps its own icon
				expect(slot(hud, "AmmoMode").id).to.equal(mode)
				expect(slot(hud, "AmmoMode").clip:CurrentLabel()).to.equal("Auto")

				hud:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto")
				expect(slot(hud, "GrenadeMode").id).to.equal(hand)
				expect(slot(hud, "GrenadeMode").clip:CurrentLabel()).to.equal("explosivegrenade")
			end
		},
		{
			name = "holding hand grenades the weapon slot shows the hand grenade icon, and goes back to the weapon icons after",
			func = function(state)
				local hud = newHud()
				local hand, mode = ids(GryMod.Flash.Load("hud_ammohealthenergysuit"))

				hud:SetAmmo(3, 0, 3, 3, "explosivegrenade", "HandGrenade")
				expect(slot(hud, "AmmoMode").id).to.equal(hand)
				expect(slot(hud, "AmmoMode").clip:CurrentLabel()).to.equal("explosivegrenade")

				hud:SetAmmo(30, 90, 45, 3, "explosivegrenade", "Single")
				expect(slot(hud, "AmmoMode").id).to.equal(mode)
				expect(slot(hud, "AmmoMode").clip:CurrentLabel()).to.equal("Single")
			end
		},
		{
			name = "the icons stay while the movie rebuilds its clips (a malfunction and its reboot)",
			func = function(state)
				local hud = newHud()
				local _, mode = ids(GryMod.Flash.Load("hud_ammohealthenergysuit"))
				hud:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto", 5)
				hud:Destroy(1)

				for _ = 1, 60 do
					hud:Update(1 / 30)
				end

				hud:Destroy(0)

				for _ = 1, 90 do
					hud:Update(1 / 30)
				end

				expect(slot(hud, "GrenadeMode").id).to.equal(mode)
				expect(hud.root:Find("Root.Player.AmmoTexts.MagAmmo.Colorset"):Child("GrenadeAmmo").text).to.equal("5")
			end
		}
	}
}
