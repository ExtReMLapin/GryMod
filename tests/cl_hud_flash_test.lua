-- Tests of the Crysis HUD driven by the original Flash movie (GryMod.FlashHUD), GLuaTest format, client realm.
--
-- The expected values follow the original ActionScript of HUD_AmmoHealthEnergySuit (setHealth, setEnergy,
-- setMode, setAmmo, updateTextColor, destroy). Needs the converted movie lua/grymod/flash/.

local function newHud()
	local movie = GryMod.Flash.Load("hud_ammohealthenergysuit")
	return GryMod.FlashHUD.New(movie), movie
end

local function field(hud, path, name)
	return hud.root:Find(path):Child(name).text
end

local function health(hud)
	local p = "Root.Texts.HealthEnergy.Colorset"
	return field(hud, p, "HealthText1") .. field(hud, p, "HealthText2") .. field(hud, p, "HealthText3")
end

local function energy(hud)
	local p = "Root.Texts.HealthEnergy.Colorset"
	return field(hud, p, "EnergyText1") .. field(hud, p, "EnergyText2") .. field(hud, p, "EnergyText3")
end

return {
	groupName = "GryMod Crysis HUD (Flash)",
	cases = {
		{
			name = "the HUD starts on the steady frames of the original (SkipSequence)",
			func = function(state)
				local hud = newHud()
				expect(hud.root:Find("Root"):CurrentLabel()).to.equal("on2")
				expect(hud.root:Find("Root.Player"):CurrentLabel()).to.equal("on2")
				expect(hud.root:Find("Root.Player").visible).to.beTrue()
				expect(hud.root:Find("Root.Tank").visible).to.beFalse()
				expect(hud.root:Find("Root.VTOL").visible).to.beFalse()
				expect(hud.root:Find("Root.EmptyHUD").visible).to.beFalse()
			end
		},
		{
			name = "full health: the engine sends percent + 1, the bar is on its last frame and the digits read 100",
			func = function(state)
				local hud = newHud()
				hud:SetHealth(101)
				expect(hud.root:Find("Root.HealthBar"):CurrentFrame()).to.equal(100)
				expect(health(hud)).to.equal("100")
			end
		},
		{
			name = "half health: frame 50 and the digits 050",
			func = function(state)
				local hud = newHud()
				hud:SetHealth(51)
				expect(hud.root:Find("Root.HealthBar"):CurrentFrame()).to.equal(50)
				expect(health(hud)).to.equal("050")
			end
		},
		{
			name = "zero and negative health show an empty bar and 000",
			func = function(state)
				local hud = newHud()
				hud:SetHealth(0)
				expect(hud.root:Find("Root.HealthBar"):CurrentFrame()).to.equal(1)
				expect(health(hud)).to.equal("000")
				hud:SetHealth(-40)
				expect(hud.root:Find("Root.HealthBar"):CurrentFrame()).to.equal(1)
				expect(health(hud)).to.equal("000")
			end
		},
		{
			name = "over 100 keeps the bar full and NaN does not raise an error",
			func = function(state)
				local hud = newHud()
				hud:SetHealth(251)
				expect(hud.root:Find("Root.HealthBar"):CurrentFrame()).to.equal(100)
				expect(health(hud)).to.equal("250")
				hud:SetHealth(0 / 0)
				expect(health(hud)).to.equal("000")
			end
		},
		{
			name = "energy follows the same rules on its own bar and digits",
			func = function(state)
				local hud = newHud()
				hud:SetEnergy(101)
				expect(hud.root:Find("Root.EnergyBar"):CurrentFrame()).to.equal(100)
				expect(energy(hud)).to.equal("100")
				hud:SetEnergy(36)
				expect(hud.root:Find("Root.EnergyBar"):CurrentFrame()).to.equal(35)
				expect(energy(hud)).to.equal("035")
			end
		},
		{
			name = "the suit mode picks the icon frame: Cloak 1, Speed 2, Strength 3, Armor 4",
			func = function(state)
				local hud = newHud()
				local icons = hud.root:Find("Root.SuitModeIcons")
				for frame, mode in ipairs({"Cloak", "Speed", "Strength", "Armor"}) do
					hud:SetMode(mode)
					expect(icons:CurrentFrame()).to.equal(frame)
				end
				hud:SetMode("Nothing")
				expect(icons:CurrentFrame()).to.equal(4)
			end
		},
		{
			name = "ammo: 31 in the magazine of 40, 71 in reserve, 7 grenades",
			func = function(state)
				local hud = newHud()
				hud:SetAmmo(31, 71, 40, 7, "explosivegrenade")
				local primary = hud.root:Find("Root.Player.AmmoTexts.PrimaryAmmo")
				expect(primary:Child("ObjNumber1"):Find("NumberText"):Child("NumberText").text).to.equal("0")
				expect(primary:Child("ObjNumber2"):Find("NumberText"):Child("NumberText").text).to.equal("3")
				expect(primary:Child("ObjNumber3"):Find("NumberText"):Child("NumberText").text).to.equal("1")
				-- leading digits are dim ("low"), the last one is not
				expect(primary:Child("ObjNumber1"):CurrentLabel()).to.equal("lowgreen")
				expect(primary:Child("ObjNumber2"):CurrentLabel()).to.equal("green")
				expect(primary:Child("ObjNumber3"):CurrentLabel()).to.equal("green")
				-- the hundreds digit exists only for magazines over 100 rounds
				expect(primary:Child("ObjNumber1").visible).to.beFalse()
				expect(primary:Child("ObjNumber2").visible).to.beTrue()
				local small = hud.root:Find("Root.Player.AmmoTexts.MagAmmo.Colorset")
				expect(small:Child("MagAmmo").text).to.equal("71")
				expect(small:Child("GrenadeAmmo").text).to.equal("7")
			end
		},
		{
			name = "ammo turns red at a third of the magazine",
			func = function(state)
				local hud = newHud()
				hud:SetAmmo(10, 71, 40, 0, "explosivegrenade")
				local primary = hud.root:Find("Root.Player.AmmoTexts.PrimaryAmmo")
				expect(primary:Child("ObjNumber2"):CurrentLabel()).to.equal("red")
				expect(primary:Child("ObjNumber3"):CurrentLabel()).to.equal("red")
				expect(primary:Child("ObjNumber1"):CurrentLabel()).to.equal("lowred")
			end
		},
		{
			name = "no ammo system (-1) shows the infinity icon",
			func = function(state)
				local hud = newHud()
				hud:SetAmmo(-1, -1, -1, 0, "explosivegrenade")
				expect(hud.root:Find("Root.Player.AmmoTexts.PrimaryInfinityIcon").visible).to.beTrue()
				hud:SetAmmo(12, 30, 30, 0, "explosivegrenade")
				expect(hud.root:Find("Root.Player.AmmoTexts.PrimaryInfinityIcon").visible).to.beFalse()
			end
		},
		{
			name = "ammo with a nil or odd value does not raise an error",
			func = function(state)
				local hud = newHud()
				hud:SetAmmo(nil, nil, nil, nil, nil)
				hud:SetAmmo(0 / 0, 1e9, 30, -3, "unknown type")
			end
		},
		{
			name = "malfunction and reboot play the original labels",
			func = function(state)
				local hud = newHud()
				hud:Destroy(1)
				expect(hud.root:Find("Root"):CurrentLabel()).to.equal("malfunction")
				hud:Destroy(0)
				-- "normal" jumps straight back to the steady frames (SkipSequence), with the values shown again
				expect(hud.root:Find("Root"):CurrentLabel()).to.equal("on2")
				hud:Destroy(2)
				expect(hud.root:Find("Root"):CurrentLabel()).to.equal("flickering")
			end
		},
		{
			name = "a malfunction plays its animation and stays on the malfunction frames, the ammo block malfunctions too",
			func = function(state)
				local hud = newHud()
				hud:Destroy(1)
				expect(hud.root:Find("Root.Player"):CurrentLabel()).to.equal("malfunction")
				for _ = 1, 90 do hud:Update(1 / 30) end -- 3 seconds
				expect(hud.root:Find("Root"):CurrentLabel()).to.equal("malfunctionOn")
				expect(hud.root:Find("Root").playing).to.beFalse()
				-- and it stays there
				for _ = 1, 30 do hud:Update(1 / 30) end
				expect(hud.root:Find("Root"):CurrentLabel()).to.equal("malfunctionOn")
			end
		},
		{
			name = "a mode change during a malfunction leaves a single icon, in its malfunction animation",
			func = function(state)
				local hud = newHud()
				hud:Destroy(1)
				hud:SetMode("Speed")
				local icons = hud.root:Find("Root.SuitModeIcons")
				expect(icons:CurrentFrame()).to.equal(2)
				expect(icons:Child("Speed"):CurrentLabel()).to.equal("malfunction")
				expect(icons:Child("Cloak")).to.beNil()
			end
		},
		{
			name = "an empty energy bar malfunctions the HUD, and it reboots once the energy is back above a tenth",
			func = function(state)
				local M = GryMod.FlashHUD
				expect(M.MalfunctionFor(0, 0)).to.equal(1)
				expect(M.MalfunctionFor(-3, 0)).to.equal(1)
				expect(M.MalfunctionFor(0.5, 1)).to.equal(1) -- stays down while the bar refills
				expect(M.MalfunctionFor(9.9, 1)).to.equal(1)
				expect(M.MalfunctionFor(10, 1)).to.equal(0)
				expect(M.MalfunctionFor(0.5, 0)).to.equal(0) -- a low bar alone does not trigger it
				expect(M.MalfunctionFor(100, 0)).to.equal(0)
				expect(M.MalfunctionFor(nil, 0)).to.equal(0)
				expect(M.MalfunctionFor(0 / 0, 1)).to.equal(1) -- no information: the state stays
			end
		},
		{
			name = "GryMod suit modes map to the movie's names (the parachute shows the armor icon)",
			func = function(state)
				local M = GryMod.FlashHUD
				expect(M.ModeName(GryMod.Modes.ARMOR)).to.equal("Armor")
				expect(M.ModeName(GryMod.Modes.SPEED)).to.equal("Speed")
				expect(M.ModeName(GryMod.Modes.CLOAK)).to.equal("Cloak")
				expect(M.ModeName(GryMod.Modes.STRENGTH)).to.equal("Strength")
				expect(M.ModeName(GryMod.Modes.DROP)).to.equal("Armor")
				expect(M.ModeName(nil)).to.equal("Armor")
			end
		},
		{
			name = "the values the engine sends are the percentage plus one",
			func = function(state)
				local M = GryMod.FlashHUD
				expect(M.HealthValue(100, 100)).to.equal(101)
				expect(M.HealthValue(50, 100)).to.equal(51)
				expect(M.HealthValue(150, 200)).to.equal(76)
				expect(M.HealthValue(0, 100)).to.equal(1)
				expect(M.HealthValue(10, 0)).to.equal(M.HealthValue(10, 100)) -- a zero maximum does not divide by zero
				expect(M.EnergyValue(100)).to.equal(101)
				expect(M.EnergyValue(0)).to.equal(1)
				expect(M.EnergyValue(-5)).to.equal(1)
			end
		},
		{
			name = "ammo from a weapon: magazine, reserve, capacity, grenades and fire mode",
			func = function(state)
				local M = GryMod.FlashHUD
				local weapon = {
					Primary = {Automatic = true},
					Clip1 = function() return 12 end,
					GetMaxClip1 = function() return 30 end,
					GetPrimaryAmmoType = function() return 4 end
				}
				local ply = {
					GetAmmoCount = function(_, type) return type == 4 and 90 or type == "Grenade" and 3 or 0 end
				}
				local mag, reserve, size, grenades, mode = M.AmmoFor(ply, weapon)
				expect(mag).to.equal(12)
				expect(reserve).to.equal(90)
				expect(size).to.equal(30)
				expect(grenades).to.equal(3)
				expect(mode).to.equal("Auto")
				weapon.Primary.Automatic = false
				expect(select(5, M.AmmoFor(ply, weapon))).to.equal("Single")
			end
		},
		{
			name = "the stock Half-Life 2 and Garry's Mod weapons have their own fire mode icon",
			func = function(state)
				local M = GryMod.FlashHUD
				local function icon(class)
					return M.FireModeFor({GetClass = function() return class end})
				end

				expect(icon("weapon_smg1")).to.equal("Auto")
				expect(icon("weapon_ar2")).to.equal("Auto")
				expect(icon("weapon_pistol")).to.equal("Single")
				expect(icon("weapon_357")).to.equal("Single")
				expect(icon("weapon_shotgun")).to.equal("Shotgun")
				expect(icon("weapon_rpg")).to.equal("Missle")
				expect(icon("weapon_frag")).to.equal("Grenade")
				expect(icon("weapon_slam")).to.equal("Mine")
				expect(icon("weapon_medkit")).to.equal("Repairkit")
				expect(icon("weapon_crowbar")).to.equal("NoGun")
				expect(icon("weapon_physgun")).to.equal("NoGun")
				expect(M.FireModeFor(nil)).to.equal("NoGun")
			end
		},
		{
			name = "a scripted weapon is automatic when its Primary says so, else single shot",
			func = function(state)
				local M = GryMod.FlashHUD
				local function weapon(automatic)
					return {GetClass = function() return "some_addon_gun" end, Primary = {Automatic = automatic}}
				end

				expect(M.FireModeFor(weapon(true))).to.equal("Auto")
				expect(M.FireModeFor(weapon(false))).to.equal("Single")
				expect(M.FireModeFor({GetClass = function() return "some_addon_gun" end})).to.equal("Single")
			end
		},
		{
			name = "a weapon base can register its own way to read the fire mode, which wins over the generic rule",
			func = function(state)
				local M = GryMod.FlashHUD
				local remove = M.AddFireModeResolver(function(weapon)
					if weapon.Base == "test_base" then
						return weapon.mode
					end
				end)

				local function gun(mode)
					return {GetClass = function() return "test_gun" end, Base = "test_base", Primary = {Automatic = true}, mode = mode}
				end

				expect(M.FireModeFor(gun("Burst"))).to.equal("Burst")
				expect(M.FireModeFor(gun(nil))).to.equal("Auto") -- the resolver has no answer: the generic rule
				remove()
				expect(M.FireModeFor(gun("Burst"))).to.equal("Auto")
			end
		},
		{
			name = "ARC9: Mode below 0 is automatic, 0 and 1 single shot, above 1 a burst, the grenade launcher shows grenades",
			func = function(state)
				local M = GryMod.FlashHUD
				local function gun(mode, launcher)
					return {ARC9 = true, GetClass = function() return "arc9_x" end, Primary = {Automatic = true},
						GetCurrentFiremode = function() return mode end, GetUBGL = function() return launcher end}
				end

				expect(M.FireModeFor(gun(-1))).to.equal("Auto")
				expect(M.FireModeFor(gun(1))).to.equal("Single")
				expect(M.FireModeFor(gun(0))).to.equal("Single")
				expect(M.FireModeFor(gun(3))).to.equal("Burst")
				expect(M.FireModeFor(gun(-1, true))).to.equal("Grenade")
			end
		},
		{
			name = "ArcCW reads the opposite way: 2 or more is automatic, 1 single shot, negative a burst",
			func = function(state)
				local M = GryMod.FlashHUD
				local function gun(mode, launcher)
					return {ArcCW = true, GetClass = function() return "arccw_x" end, Primary = {Automatic = true},
						GetCurrentFiremode = function() return {Mode = mode} end, GetInUBGL = function() return launcher end}
				end

				expect(M.FireModeFor(gun(2))).to.equal("Auto")
				expect(M.FireModeFor(gun(1))).to.equal("Single")
				expect(M.FireModeFor(gun(0))).to.equal("Single")
				expect(M.FireModeFor(gun(-3))).to.equal("Burst")
				expect(M.FireModeFor(gun(2, true))).to.equal("Grenade")
			end
		},
		{
			name = "TFA reads the name of the current mode in its FireModes list",
			func = function(state)
				local M = GryMod.FlashHUD
				local function gun(index)
					return {IsTFAWeapon = true, GetClass = function() return "tfa_x" end, Primary = {Automatic = false},
						FireModes = {"Automatic", "3Burst", "Single", "Safe"}, GetFireMode = function() return index end}
				end

				expect(M.FireModeFor(gun(1))).to.equal("Auto")
				expect(M.FireModeFor(gun(2))).to.equal("Burst")
				expect(M.FireModeFor(gun(3))).to.equal("Single")
				expect(M.FireModeFor(gun(4))).to.equal("Single") -- the safety
				expect(M.FireModeFor(gun(99))).to.equal("Single") -- an index that is not in the list
			end
		},
		{
			name = "M9K: GetAutomatic says whether it fires automatically, its shotguns keep the shotgun icon",
			func = function(state)
				local M = GryMod.FlashHUD
				local function gun(base, automatic)
					return {Base = base, GetClass = function() return "m9k_x" end, Primary = {Automatic = not automatic},
						GetAutomatic = function() return automatic end}
				end

				expect(M.FireModeFor(gun("bobs_gun_base", true))).to.equal("Auto")
				expect(M.FireModeFor(gun("bobs_gun_base", false))).to.equal("Single")
				expect(M.FireModeFor(gun("bobs_scoped_base", true))).to.equal("Auto")
				expect(M.FireModeFor(gun("bobs_shotty_base", false))).to.equal("Shotgun")
			end
		},
		{
			name = "CW 2.0 and FA:S 2.0 keep the mode as a string",
			func = function(state)
				local M = GryMod.FlashHUD
				local function cw(mode)
					return {CW20Weapon = true, GetClass = function() return "cw_x" end, Primary = {Automatic = true}, FireMode = mode}
				end

				local function fas(mode)
					return {IsFAS2Weapon = true, GetClass = function() return "fas2_x" end, Primary = {Automatic = true}, FireMode = mode}
				end

				for _, make in ipairs({cw, fas}) do
					expect(M.FireModeFor(make("auto"))).to.equal("Auto")
					expect(M.FireModeFor(make("semi"))).to.equal("Single")
					expect(M.FireModeFor(make("3burst"))).to.equal("Burst")
					expect(M.FireModeFor(make("bolt"))).to.equal("Single")
					expect(M.FireModeFor(make("safe"))).to.equal("Single")
					expect(M.FireModeFor(make(nil))).to.equal("Single") -- not received from the server yet
				end
			end
		},
		{
			name = "a player without a weapon (the NULL entity) shows the no-gun icon instead of raising an error",
			func = function(state)
				local M = GryMod.FlashHUD
				local ply = {GetAmmoCount = function() return 2 end}
				local mag, reserve, size, grenades, mode = M.AmmoFor(ply, NULL)
				expect(mag).to.equal(-1)
				expect(grenades).to.equal(2)
				expect(mode).to.equal("NoGun")
				expect(M.FireModeFor(NULL)).to.equal("NoGun")
			end
		},
		{
			name = "a resolver that errors or answers with an unknown icon is ignored",
			func = function(state)
				local M = GryMod.FlashHUD
				local removeBad = M.AddFireModeResolver(function() error("broken base") end)
				local removeUnknown = M.AddFireModeResolver(function() return "NoSuchIcon" end)
				local gun = {GetClass = function() return "x" end, Primary = {Automatic = false}}
				expect(M.FireModeFor(gun)).to.equal("Single")
				removeBad()
				removeUnknown()
			end
		},
		{
			name = "ammo without a magazine counts the reserve, and no weapon or no ammo shows infinity",
			func = function(state)
				local M = GryMod.FlashHUD
				local ply = {GetAmmoCount = function() return 7 end}
				local noClip = {Clip1 = function() return -1 end, GetMaxClip1 = function() return -1 end, GetPrimaryAmmoType = function() return 8 end}
				local mag, reserve, size = M.AmmoFor(ply, noClip)
				expect(mag).to.equal(7)
				expect(reserve).to.equal(0)
				expect(size).to.equal(7)
				local noAmmo = {Clip1 = function() return -1 end, GetMaxClip1 = function() return -1 end, GetPrimaryAmmoType = function() return -1 end}
				expect((M.AmmoFor(ply, noAmmo))).to.equal(-1)
				expect((M.AmmoFor(ply, nil))).to.equal(-1)
				expect(select(5, M.AmmoFor(ply, nil))).to.equal("NoGun")
			end
		},
		{
			name = "gry_hud adds and removes the paint hook, without duplicates, and nothing is drawn without the movie",
			func = function(state)
				local hudOn = GetConVar("gry_hud"):GetString()
				GetConVar("gry_hud"):SetString("1")
				GryMod.ApplyHUD()
				GryMod.ApplyHUD()
				expect(hook.GetTable().HUDPaint["GRYFLASHHUD"]).to.exist()
				GetConVar("gry_hud"):SetString("0")
				expect(hook.GetTable().HUDPaint["GRYFLASHHUD"]).to.beNil()
				GetConVar("gry_hud"):SetString(hudOn)
				GryMod.ApplyHUD()
			end
		},
		{
			name = "the colour themes are the four the original game offers, from its integer colour values",
			func = function(state)
				local M = GryMod.FlashHUD
				-- hud_colorLine / hud_colorOver / hud_colorText as 0xRRGGBB integers read from the game
				expect(M.ColourFromInt(4481854)[1]).to.equal(68)
				expect(M.ColourFromInt(4481854)[2]).to.equal(99)
				expect(M.ColourFromInt(4481854)[3]).to.equal(62)
				expect(M.Themes.blue.Line[1]).to.equal(77)
				expect(M.Themes.blue.Line[2]).to.equal(131)
				expect(M.Themes.blue.Line[3]).to.equal(179)
				expect(M.Themes.blue.Over[2]).to.equal(156)
				expect(M.Themes.blue.Text[3]).to.equal(185)
				expect(M.Themes.default.Text[1]).to.equal(188)
				expect(M.Themes.white.Text[1]).to.equal(255)
				expect(M.Themes.orange.Line[1]).to.equal(192)
			end
		},
		{
			name = "choosing a theme changes the colours of the next HUD, an unknown name gives the blue one",
			func = function(state)
				local M = GryMod.FlashHUD
				local saved = GetConVar("gry_hud_theme"):GetString()
				M.SetTheme("default")
				expect(M.Theme.Line[1]).to.equal(68)
				M.SetTheme("nothing")
				expect(M.Theme.Line[1]).to.equal(77)
				M.SetTheme(saved)
			end
		},
		{
			name = "a theme change rebuilds every piece of the interface, not only the HUD",
			func = function(state)
				local M = GryMod.FlashHUD
				local others = {GryMod.FlashMenu, GryMod.FlashBinoculars, GryMod.FlashGrenade}
				local calls, saved = 0, {}

				for i, module in ipairs(others) do
					saved[i] = module.Reset
					module.Reset = function() calls = calls + 1 end
				end

				M.ResetAll()

				for i, module in ipairs(others) do
					module.Reset = saved[i]
				end

				expect(calls).to.equal(3)
			end
		},
		{
			name = "a colour setting is three numbers 0 to 255 written as 'r g b'; anything else is refused",
				func = function(state)
					local M = GryMod.FlashHUD
					local c = M.ParseColour("10 20 30")
					expect(c[1]).to.equal(10)
					expect(c[2]).to.equal(20)
					expect(c[3]).to.equal(30)
					c = M.ParseColour("300 -5 12.7")
					expect(c[1]).to.equal(255)
					expect(c[2]).to.equal(0)
					expect(c[3]).to.equal(13)
					expect(M.ParseColour("10 20")).to.beNil()
					expect(M.ParseColour("a b c")).to.beNil()
					expect(M.ParseColour("")).to.beNil()
					expect(M.ParseColour(nil)).to.beNil()
				end
			},
			{
				name = "the custom theme takes its three colours from the gry_hud_color_* settings, the blue ones where a setting is invalid",
				func = function(state)
					local M = GryMod.FlashHUD
					local line, over, text = GetConVar("gry_hud_color_line"), GetConVar("gry_hud_color_over"), GetConVar("gry_hud_color_text")
					local saved = {line:GetString(), over:GetString(), text:GetString(), GetConVar("gry_hud_theme"):GetString()}
					line:SetString("1 2 3")
					over:SetString("nonsense")
					text:SetString("250 251 252")
					M.SetTheme("custom")
					expect(M.Theme.Line[1]).to.equal(1)
					expect(M.Theme.Line[3]).to.equal(3)
					expect(M.Theme.Over[1]).to.equal(M.Themes.blue.Over[1])
					expect(M.Theme.Over[3]).to.equal(M.Themes.blue.Over[3])
					expect(M.Theme.Text[2]).to.equal(251)
					line:SetString(saved[1])
					over:SetString(saved[2])
					text:SetString(saved[3])
					M.SetTheme(saved[4])
				end
			},
			{
				name = "changing a custom colour while the custom theme is on rebuilds the interface with it, and does nothing under another theme",
				func = function(state)
					local M = GryMod.FlashHUD
					local line = GetConVar("gry_hud_color_line")
					local themeVar = GetConVar("gry_hud_theme")
					local saved = {line:GetString(), themeVar:GetString()}
					local calls, original = 0, M.ResetAll
					M.ResetAll = function() calls = calls + 1 end
					themeVar:SetString("custom")
					calls = 0
					line:SetString("9 8 7")
					expect(calls).to.equal(1)
					expect(M.Theme.Line[1]).to.equal(9)
					themeVar:SetString("white")
					calls = 0
					line:SetString("90 80 70")
					M.ResetAll = original
					expect(calls).to.equal(0)
					line:SetString(saved[1])
					themeVar:SetString(saved[2])
				end
			},
			{
				name = "a missing movie gives no HUD instead of an error",
			func = function(state)
				expect(GryMod.FlashHUD.New(nil)).to.beNil()
			end
		}
	}
}
