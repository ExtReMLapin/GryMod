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
			end
		},
		{
			name = "gry_hud_style switches the paint hook without duplicates and falls back to the classic HUD",
			func = function(state)
				local style = GetConVar("gry_hud_style")
				local hudOn = GetConVar("gry_hud"):GetString()
				local saved = style:GetString()
				GetConVar("gry_hud"):SetString("1")
				style:SetString("crysis")
				GryMod.ApplyHUD()
				GryMod.ApplyHUD()
				expect(hook.GetTable().HUDPaint["GRYFLASHHUD"]).to.exist()
				expect(hook.GetTable().HUDPaint["HUDBASECRY"]).to.beNil()
				style:SetString("classic")
				GryMod.ApplyHUD()
				expect(hook.GetTable().HUDPaint["GRYFLASHHUD"]).to.beNil()
				expect(hook.GetTable().HUDPaint["HUDBASECRY"]).to.exist()
				style:SetString(saved)
				GetConVar("gry_hud"):SetString(hudOn)
				GryMod.ApplyHUD()
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
