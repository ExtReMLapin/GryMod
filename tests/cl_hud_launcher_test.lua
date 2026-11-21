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
			-- The weapon slot of the movie is drawn with the blend mode "add" (its icons shine on what is behind), the grenade
			-- slot is not, and its hand grenade icons are added by themselves. The 40 mm icon moved to the grenade slot has to
			-- be added too, or it is a dark blue shape on a bright background.
			name = "the 40 mm icon of the grenade slot is added like the hand grenade icon and the weapon slot icons, whatever the theme",
			func = function(state)
				local M = GryMod.FlashHUD
				local movie = GryMod.Flash.Load("hud_ammohealthenergysuit")
				local BLEND_ADD = 8

				for name, colours in pairs(M.Themes) do
					local hud = M.New(movie, colours)

					hud:SetAmmo(3, 0, 3, 3, "explosivegrenade", "Auto")
					local hand = slot(hud, "GrenadeMode").clip.list[1]
					expect(hand.blend).to.equal(BLEND_ADD)

					hud:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto", 5)
					local icon = slot(hud, "GrenadeMode").clip.list[1]
					expect(icon.id ~= hand.id).to.beTrue()
					expect(icon.blend).to.equal(BLEND_ADD)

					-- the tint is the theme's outline colour, the one of the hand grenade and of the weapon slot icons
					local tint = icon.clip.names.Colorset.cx
					for part = 1, 3 do expect(tint[4 + part]).to.equal(colours.Line[part]) end
					local weapon = slot(hud, "AmmoMode")
					expect(weapon.blend).to.equal(BLEND_ADD)
					local weaponTint = weapon.clip.list[1].clip.names.Colorset.cx
					for part = 1, 3 do expect(weaponTint[4 + part]).to.equal(colours.Line[part]) end
				end
			end
		},
		{
			name = "the blend of the 40 mm icon follows the launcher: back to the hand grenades the icon is the hand grenade one, again with the launcher it is added again",
			func = function(state)
				local hud = newHud()
				local BLEND_ADD = 8

				hud:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto", 5)
				hud:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto")
				expect(slot(hud, "GrenadeMode").clip.list[1].blend).to.equal(BLEND_ADD)
				expect(slot(hud, "GrenadeMode").clip:CurrentLabel()).to.equal("explosivegrenade")

				hud:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto", 5)
				expect(slot(hud, "GrenadeMode").clip.list[1].blend).to.equal(BLEND_ADD)
				expect(slot(hud, "GrenadeMode").clip:CurrentLabel()).to.equal("Grenade")
			end
		},
		{
			name = "the 40 mm icon stays added while the movie rebuilds its clips, and with a new theme",
			func = function(state)
				local M = GryMod.FlashHUD
				local hud = newHud()
				hud:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto", 5)
				hud:Destroy(1)

				for _ = 1, 60 do
					hud:Update(1 / 30)
				end

				hud:Destroy(0)

				for _ = 1, 90 do
					hud:Update(1 / 30)
				end

				local icon = slot(hud, "GrenadeMode").clip.list[1]
				expect(slot(hud, "GrenadeMode").clip:CurrentLabel()).to.equal("Grenade")
				expect(icon.blend).to.equal(8)

				-- a new theme builds a new HUD: the launcher's icon is added there too, in the new colour
				local other = M.New(GryMod.Flash.Load("hud_ammohealthenergysuit"), M.Themes.default)
				other:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto", 5)
				local tinted = slot(other, "GrenadeMode").clip.list[1]
				expect(tinted.blend).to.equal(8)
				expect(tinted.clip.names.Colorset.cx[5]).to.equal(M.Themes.default.Line[1])
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
