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

-- a weapon of this class whose secondary ammo is the given type (the class is what the registry knows it by)
local function classWeapon(class, ammoName)
	return {
		GetClass = function() return class end,
		GetSecondaryAmmoType = function() return ammoName and game.GetAmmoID(ammoName) or -1 end
	}
end

return {
	groupName = "GryMod HUD grenade slot (Flash)",
	afterEach = function(state)
		GryMod.API.UnregisterWeapon("t_launcher")
		GryMod.API.UnregisterWeapon("t_noicon")
	end,
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
			-- The AR2's secondary is the energy ball: its ammo is what the grenade slot counts (the registry says so, the HUD does
			-- not know the class). A weapon we have no class for keeps the old rule, so AR2AltFire without a class stays nothing.
			name = "the AR2's secondary (the energy ball, AR2AltFire) is counted in the slot, the SMG's grenade too, the other stock weapons give nothing",
			func = function(state)
				local M = GryMod.FlashHUD
				expect(M.LauncherFor(player(4), classWeapon("weapon_ar2", "AR2AltFire"))).to.equal(4)
				expect(M.LauncherFor(player(0), classWeapon("weapon_ar2", "AR2AltFire"))).to.equal(0)
				expect(M.LauncherFor(player(4), classWeapon("weapon_smg1", "SMG1_Grenade"))).to.equal(4)

				for _, class in ipairs({"weapon_shotgun", "weapon_crossbow", "weapon_pistol", "weapon_357", "weapon_rpg", "weapon_frag", "weapon_physcannon", "weapon_crowbar", "weapon_stunstick"}) do
					expect(M.LauncherFor(player(4), classWeapon(class, nil))).to.beNil()
				end
			end
		},
		{
			name = "what a registered weapon says about its secondary decides: a registered class that says none shows no launcher even with grenade ammo",
			func = function(state)
				GryMod.API.RegisterWeapon("t_noicon", {alt = "zoom"})
				expect(GryMod.FlashHUD.LauncherFor(player(4), classWeapon("t_noicon", "SMG1_Grenade"))).to.beNil()
			end
		},
		{
			-- the icon and the label the registry gives to the secondary; nil when the weapon has no launcher
			name = "LauncherLookFor gives the icon and the label of the secondary: the SMG's 40 mm grenade, the AR2's energy ball, nothing for the others",
			func = function(state)
				local M = GryMod.FlashHUD
				local icon, label = M.LauncherLookFor(classWeapon("weapon_smg1", "SMG1_Grenade"))
				expect(icon).to.equal(GryMod.API.WeaponValue("weapon_smg1", "altIcon"))
				expect(label).to.equal("40mm")

				icon, label = M.LauncherLookFor(classWeapon("weapon_ar2", "AR2AltFire"))
				expect(icon).to.equal(GryMod.API.WeaponValue("weapon_ar2", "altIcon"))
				expect(label).to.equal(GryMod.API.WeaponValue("weapon_ar2", "altLabel"))
				expect(label ~= "40mm").to.beTrue()

				expect(M.LauncherLookFor(classWeapon("weapon_crossbow", nil))).to.beNil()
				expect(M.LauncherLookFor(nil)).to.beNil()
				expect(M.LauncherLookFor(NULL)).to.beNil()

				-- a launcher that says nothing about its icon gets the 40 mm grenade one
				GryMod.API.RegisterWeapon("t_noicon", {alt = "grenade", altAmmo = "SMG1_Grenade"})
				icon, label = M.LauncherLookFor(classWeapon("t_noicon", "SMG1_Grenade"))
				expect(icon).to.equal("Grenade")
				expect(label).to.beNil()
			end
		},
		{
			-- dogfooding: the SMG, the AR2 and the weapon of an addon go through the same path, from the registry to the slot
			name = "a third-party weapon registered with RegisterWeapon is shown by the same path as the SMG and the AR2: count, icon in the slot, label",
			func = function(state)
				local M = GryMod.FlashHUD
				local API = GryMod.API

				expect(API.RegisterWeapon("t_launcher", {alt = "energy", altAmmo = "AR2AltFire", altIcon = "Gauss", altLabel = "PLASMA"})).to.beTrue()

				for _, case in ipairs({{"weapon_smg1", "SMG1_Grenade"}, {"weapon_ar2", "AR2AltFire"}, {"t_launcher", "AR2AltFire"}}) do
					local weapon = classWeapon(case[1], case[2])
					local count = M.LauncherFor(player(7), weapon)
					local icon, label = M.LauncherLookFor(weapon)
					expect(count).to.equal(7)
					expect(icon).to.equal(API.WeaponValue(case[1], "altIcon"))

					local hud = newHud()
					hud:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto", count, false, icon, label)
					expect(slot(hud, "GrenadeMode").clip:CurrentLabel()).to.equal(icon)
					expect(hud.root:Find("Root.Player.AmmoTexts.MagAmmo.Colorset"):Child("GrenadeAmmo").text).to.equal("7")
					expect(hud:GetLauncherLabel()).to.equal(label)
				end

				expect(M.LauncherLookFor(classWeapon("t_launcher", "AR2AltFire"))).to.equal("Gauss")
			end
		},
		{
			name = "the launcher icon follows the weapon: another icon, then the default one, then the hand grenades again",
			func = function(state)
				local hud = newHud()
				local hand, mode = ids(GryMod.Flash.Load("hud_ammohealthenergysuit"))

				hud:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto", 5, false, "Gauss", "PLASMA")
				expect(slot(hud, "GrenadeMode").id).to.equal(mode)
				expect(slot(hud, "GrenadeMode").clip:CurrentLabel()).to.equal("Gauss")
				expect(slot(hud, "GrenadeMode").clip.list[1].blend).to.equal(8)
				expect(hud:GetLauncherLabel()).to.equal("PLASMA")

				hud:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto", 5)
				expect(slot(hud, "GrenadeMode").clip:CurrentLabel()).to.equal("Grenade") -- no icon given: the 40 mm one, as before
				expect(hud:GetLauncherLabel()).to.beNil()

				hud:SetAmmo(30, 90, 45, 2, "explosivegrenade", "Auto")
				expect(slot(hud, "GrenadeMode").id).to.equal(hand)
				expect(slot(hud, "GrenadeMode").clip:CurrentLabel()).to.equal("explosivegrenade")
				expect(hud:GetLauncherLabel()).to.beNil()
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
