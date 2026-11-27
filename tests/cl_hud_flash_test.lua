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
	afterEach = function(state)
		GryMod.API.UnregisterWeapon("t_firemode")
	end,
	cases = {
		{
			name = "the jump of a heavy hit moves the panels by whole screen pixels, so that their cached images are only moved (cl_flash_draw.lua)",
			func = function(state)
				local M = GryMod.FlashHUD
				expect(M.JumpPixels(0, 2.8)).to.equal(0)
				expect(M.JumpPixels(1, 1)).to.equal(1)
				expect(M.JumpPixels(-1, 1)).to.equal(-1)
				expect(M.JumpPixels(1.4, 1)).to.equal(1)
				expect(M.JumpPixels(1.6, 1)).to.equal(2)
				expect(M.JumpPixels(-1.6, 1)).to.equal(-2)
				-- the stage pixels are scaled to the screen first: 3.1 stage pixels at 2.8 are 8.68 screen pixels
				expect(M.JumpPixels(3.1, 2.8)).to.equal(9)

				for _ = 1, 200 do
					local jump = (math.random() - 0.5) * 12
					local scale = 0.4 + math.random() * 3
					local pixels = M.JumpPixels(jump, scale)
					expect(pixels).to.equal(math.floor(pixels))
					expect(math.abs(pixels - jump * scale)).to.beLessThan(0.5000001)
				end
			end
		},
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
			-- Fails without the "blink all digits" rule in HUD:SetAmmo (cl_hud_flash.lua): only the digit whose value changed blinked.
			-- The original updateTextColor runs updateColor on every digit at every setAmmo, and updateColor always plays the blink.
			name = "every visible ammo digit blinks at each ammo update, not only the digit that changed (updateColor)",
			func = function(state)
				local hud = newHud()
				local primary = hud.root:Find("Root.Player.AmmoTexts.PrimaryAmmo")
				local function blink(name) return primary:Child(name):Child("NumberText_blink") end
				local function settle() for _ = 1, 60 do hud:Update(1 / 30) end end

				hud:SetAmmo(31, 71, 40, 7, "explosivegrenade")
				settle()
				expect(blink("ObjNumber2") ~= nil).to.beTrue()
				expect(blink("ObjNumber3") ~= nil).to.beTrue()
				expect(blink("ObjNumber2").playing).to.beFalse()
				expect(blink("ObjNumber3").playing).to.beFalse()

				-- 31 -> 30: only the units changed, the tens blink too
				hud:SetAmmo(30, 71, 40, 7, "explosivegrenade")
				expect(blink("ObjNumber3").playing).to.beTrue()
				expect(blink("ObjNumber2").playing).to.beTrue()
				settle()
				expect(blink("ObjNumber2").playing).to.beFalse()

				-- same magazine, the reserve changed: the original blinks the digits anyway
				hud:SetAmmo(30, 70, 40, 7, "explosivegrenade")
				expect(blink("ObjNumber2").playing).to.beTrue()
				expect(blink("ObjNumber3").playing).to.beTrue()
			end
		},
		{
			-- Fails if _refresh (the values put back at a refresh) played the blinks: only a real ammo update does. (A rebuild of the
			-- clips after a malfunction runs the original setAmmo again, so it blinks on its own, as in the original.)
			name = "putting the same values back (a refresh) does not blink the ammo digits",
			func = function(state)
				local hud = newHud()
				local primary = hud.root:Find("Root.Player.AmmoTexts.PrimaryAmmo")
				hud:SetAmmo(31, 71, 40, 7, "explosivegrenade")
				for _ = 1, 60 do hud:Update(1 / 30) end
				hud:_refresh()
				expect(primary:Child("ObjNumber2"):Child("NumberText_blink").playing).to.beFalse()
				expect(primary:Child("ObjNumber3"):Child("NumberText_blink").playing).to.beFalse()
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
			name = "when a malfunction ends the icon of the current mode plays its reboot animation (frames 43 to 49) and stays on its last frame",
			func = function(state)
				local hud = newHud()
				hud:SetMode("Speed")
				hud:Destroy(1)
				-- a mode change during the malfunction: the reboot is the icon of the mode now shown
				hud:SetMode("Cloak")
				hud:Destroy(0)
				local icon = hud.icons:Child("Cloak")
				expect(icon:CurrentLabel()).to.equal("reboot")
				expect(icon:CurrentFrame()).to.equal(43)
				expect(icon.playing).to.beTrue()
				hud:Update(1 / 30)
				hud:Update(1 / 30)
				expect(icon:CurrentFrame()).to.equal(45)

				for _ = 1, 10 do hud:Update(1 / 30) end -- a refresh must not restart it, and it ends by itself (0.23 s)

				expect(icon:CurrentFrame()).to.equal(49)
				expect(icon.playing).to.beFalse()
			end
		},
		{
			name = "the reboot animation plays only after a malfunction: not at the first normal state, not after a flicker",
			func = function(state)
				local hud = newHud()
				hud:SetMode("Speed")
				hud:Destroy(0)
				expect(hud.icons:Child("Speed"):CurrentLabel()).to.equal("normal")
				hud:Destroy(2)
				hud:Destroy(0)
				expect(hud.icons:Child("Speed"):CurrentLabel()).to.equal("normal")
				hud:Destroy(1)
				hud:Destroy(2) -- a flicker in the middle of the malfunction: the previous state is not the malfunction any more
				hud:Destroy(0)
				expect(hud.icons:Child("Speed"):CurrentLabel()).to.equal("normal")
			end
		},
		{
			name = "gry_icon_reboot 0 brings back the old behaviour (no reboot animation); the switch is saved, on by default, with a check box",
			func = function(state)
				local convar = GetConVar("gry_icon_reboot")
				expect(convar:GetDefault()).to.equal("1")
				local saved = convar:GetString()
				convar:SetString("0")
				local ok, err = pcall(function()
					local hud = newHud()
					hud:SetMode("Speed")
					hud:Destroy(1)
					hud:Destroy(0)
					expect(hud.icons:Child("Speed"):CurrentLabel()).to.equal("normal")
				end)
				convar:SetString(saved)

				if not ok then
					error(err, 0)
				end

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok2, err2 = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok2 then
					error(err2, 0)
				end

				expect(found["gry_icon_reboot"]).to.beTrue()
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
			name = "the old empty-bar rule (gry_malfunction_empty 1): an empty energy bar malfunctions the HUD, and it reboots once the energy is back above a tenth",
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
			name = "changing the fire mode of the weapon plays the blink of its icon (switchFireMode), the first display does not",
			func = function(state)
				local hud = newHud()
				local function blink() return hud.player:Child("AmmoMode"):Child("Blink") end
				hud:SetAmmo(30, 90, 30, 3, "explosivegrenade", "Single")
				expect(blink().playing).to.beFalse()
				expect(blink():CurrentFrame()).to.equal(1)
				hud:SetAmmo(30, 90, 30, 3, "explosivegrenade", "Auto")
				-- the movie's "play" label, and the icon is the new one
				expect(blink():CurrentFrame()).to.equal(2)
				expect(blink().playing).to.beTrue()
				expect(hud.player:Child("AmmoMode"):CurrentLabel()).to.equal("Auto")
				-- it runs to its end and stops, the icon still on the right frame
				for _ = 1, 30 do hud:Update(1 / 30) end
				expect(blink().playing).to.beFalse()
				expect(blink():CurrentFrame()).to.equal(1)
				expect(hud.player:Child("AmmoMode"):CurrentLabel()).to.equal("Auto")
			end
		},
		{
			name = "the blink is not played again while the fire mode stays, nor restarted by a change of the numbers",
			func = function(state)
				local hud = newHud()
				local function blink() return hud.player:Child("AmmoMode"):Child("Blink") end
				hud:SetAmmo(30, 90, 30, 3, "explosivegrenade", "Single")
				hud:SetAmmo(30, 90, 30, 3, "explosivegrenade", "Burst")
				hud:Update(1 / 30)
				hud:Update(1 / 30)
				local frame = blink():CurrentFrame()
				expect(frame > 2).to.beTrue()
				-- a shot: the magazine changes, the fire mode does not
				hud:SetAmmo(29, 90, 30, 3, "explosivegrenade", "Burst")
				expect(blink():CurrentFrame()).to.equal(frame)
				expect(blink().playing).to.beTrue()
				-- once it has ended, the same fire mode again does not play it
				for _ = 1, 30 do hud:Update(1 / 30) end
				hud:SetAmmo(28, 90, 30, 3, "explosivegrenade", "Burst")
				expect(blink().playing).to.beFalse()
			end
		},
		{
			name = "a weapon change does not blink, even if its fire mode icon is another one",
			func = function(state)
				local hud = newHud()
				local function blink() return hud.player:Child("AmmoMode"):Child("Blink") end
				hud:SetAmmo(30, 90, 30, 3, "explosivegrenade", "Single")
				hud:SetAmmo(6, 24, 6, 3, "explosivegrenade", "Shotgun", nil, true)
				expect(blink().playing).to.beFalse()
				expect(hud.player:Child("AmmoMode"):CurrentLabel()).to.equal("Shotgun")
				-- the next change on that weapon blinks
				hud:SetAmmo(6, 24, 6, 3, "explosivegrenade", "Auto")
				expect(blink().playing).to.beTrue()
			end
		},
		{
			name = "the hand grenade icon in the weapon slot (it has no blink clip) is shown without an error, and the icons come back",
			func = function(state)
				local hud = newHud()
				hud:SetAmmo(3, 0, 3, 3, "explosivegrenade", "Single")
				hud:SetAmmo(3, 0, 3, 3, "explosivegrenade", "HandGrenade")
				expect(hud.player:Child("AmmoMode"):CurrentLabel()).to.equal("explosivegrenade")
				hud:SetAmmo(30, 90, 30, 3, "explosivegrenade", "Single")
				expect(hud.player:Child("AmmoMode"):CurrentLabel()).to.equal("Single")
				expect(hud.player:Child("GrenadeMode"):CurrentLabel()).to.equal("explosivegrenade")
			end
		},
		{
			name = "changing the type of grenade plays the grenade icon's animation (switchGrenades), not at the first display nor while it stays",
			func = function(state)
				local hud = newHud()
				local function grenade() return hud.player:Child("GrenadeMode"):Child("Grenade") end
				hud:SetAmmo(30, 90, 30, 3, "explosivegrenade", "Single")
				expect(grenade().playing).to.beFalse()
				hud:SetAmmo(29, 90, 30, 3, "explosivegrenade", "Single")
				expect(grenade().playing).to.beFalse()
				hud:SetAmmo(29, 90, 30, 3, "flashbang", "Single")
				expect(grenade():CurrentFrame()).to.equal(2)
				expect(grenade().playing).to.beTrue()
				expect(hud.player:Child("GrenadeMode"):CurrentLabel()).to.equal("flashbang")
				for _ = 1, 40 do hud:Update(1 / 30) end
				expect(grenade().playing).to.beFalse()
				hud:SetAmmo(28, 90, 30, 3, "flashbang", "Single")
				expect(grenade().playing).to.beFalse()
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
			-- Fails without the 6th result of Module.AmmoFor and without the `grenade` field: the feed always sent "explosivegrenade",
			-- so the other icons and the grenade blink were unreachable.
			name = "the weapon registry chooses the hand grenade kind of the grenade slot, and a grenade weapon counts its own ammo there",
			func = function(state)
				local M = GryMod.FlashHUD
				local ply = {
					GetAmmoCount = function(_, type) return type == 7 and 5 or type == "Grenade" and 3 or 0 end
				}
				local function gun(class, extra)
					local weapon = {
						GetClass = function() return class end,
						Clip1 = function() return -1 end,
						GetMaxClip1 = function() return -1 end,
						GetPrimaryAmmoType = function() return 7 end
					}

					for key, value in pairs(extra or {}) do weapon[key] = value end

					return weapon
				end

				-- no `grenade` declared: the explosive grenade and the count of the hand grenades
				local _, _, _, grenades, _, kind = M.AmmoFor(ply, gun("t_firemode"))
				expect(grenades).to.equal(3)
				expect(kind).to.equal("explosivegrenade")

				-- a flash grenade weapon: its icon, and its own ammo (the 5 it holds) instead of the frags
				GryMod.API.RegisterWeapon("t_firemode", {grenade = "flashbang", slotIcon = "HandGrenade"})
				_, _, _, grenades, _, kind = M.AmmoFor(ply, gun("t_firemode"))
				expect(kind).to.equal("flashbang")
				expect(grenades).to.equal(5)

				-- the weapon with no primary ammo of its own keeps the hand grenades count
				_, _, _, grenades, _, kind = M.AmmoFor(ply, gun("t_firemode", {GetPrimaryAmmoType = function() return -1 end}))
				expect(kind).to.equal("flashbang")
				expect(grenades).to.equal(3)

				-- nothing in hand: the explosive grenades
				_, _, _, grenades, _, kind = M.AmmoFor(ply, nil)
				expect(kind).to.equal("explosivegrenade")

				-- the stock frag grenade says it in the registry
				_, _, _, _, _, kind = M.AmmoFor(ply, gun("weapon_frag"))
				expect(kind).to.equal("explosivegrenade")
			end
		},
		{
			-- Fails without HUD:SetHeat (cl_hud_flash.lua): the bar of the movie is hidden for good, nothing can show it
			name = "the overheat bar: hidden by default, SetHeat shows it on the frame of the heat (1 to 100), 0 hides it, and it comes back after a malfunction",
			func = function(state)
				local hud = newHud()
				local function bar() return hud.player:Child("OverheatBar") end
				expect(bar().visible).to.beFalse()
				hud:SetHeat(50)
				expect(bar().visible).to.beTrue()
				expect(bar():CurrentFrame()).to.equal(50)
				hud:SetHeat(100)
				expect(bar():CurrentFrame()).to.equal(100)
				hud:SetHeat(0)
				expect(bar().visible).to.beFalse()

				hud:SetHeat(30)
				hud:Destroy(1)
				hud:Destroy(0)
				expect(bar().visible).to.beTrue()
				expect(bar():CurrentFrame()).to.equal(30)
				hud:SetHeat(nil)
				expect(bar().visible).to.beFalse()
			end
		},
		{
			name = "HeatFrame turns a heat of 0 to 1 into a frame of the bar: 0 is hidden, anything above 0 is at least frame 1, junk is hidden",
			func = function(state)
				local M = GryMod.FlashHUD
				expect(M.HeatFrame(0)).to.equal(0)
				expect(M.HeatFrame(nil)).to.equal(0)
				expect(M.HeatFrame(-1)).to.equal(0)
				expect(M.HeatFrame(0 / 0)).to.equal(0)
				expect(M.HeatFrame("hot")).to.equal(0)
				expect(M.HeatFrame(0.001)).to.equal(1)
				expect(M.HeatFrame(0.5)).to.equal(50)
				expect(M.HeatFrame(1)).to.equal(100)
				expect(M.HeatFrame(7)).to.equal(100)
			end
		},
		{
			-- Fails without Module.HeatSourceFor / HeatOf: nothing reads the registry's `heat`. The switch gry_hud_overheat comes from the
			-- HUD options list (an element "overheat").
			name = "only a weapon that declares a heat source shows the bar; a broken source shows nothing and never raises; gry_hud_overheat turns it off",
			func = function(state)
				local M = GryMod.FlashHUD
				local weapon = {GetClass = function() return "t_firemode" end}
				local convar = GetConVar("gry_hud_overheat")
				local saved = convar:GetString()
				local value = 0.4

				local ok, err = pcall(function()
					convar:SetString("1")
					expect(M.HeatSourceFor(weapon)).to.beNil()
					expect(M.HeatOf(weapon, nil)).to.equal(0)

					GryMod.API.RegisterWeapon("t_firemode", {heat = function(wep) return value end})
					local source = M.HeatSourceFor(weapon)
					expect(isfunction(source)).to.beTrue()
					expect(M.HeatOf(weapon, source)).to.equal(40)
					value = 1
					expect(M.HeatOf(weapon, source)).to.equal(100)

					-- a weapon that says it itself
					expect(isfunction(M.HeatSourceFor({GetClass = function() return "t_other" end, GryHUD = {heat = function() return 1 end}}))).to.beTrue()

					-- an error is caught, and the bar is hidden
					GryMod.API.RegisterWeapon("t_firemode", {heat = function() error("broken heat") end})
					expect(M.HeatOf(weapon, M.HeatSourceFor(weapon))).to.equal(0)
					GryMod.API.RegisterWeapon("t_firemode", {heat = function() return "hot" end})
					expect(M.HeatOf(weapon, M.HeatSourceFor(weapon))).to.equal(0)

					-- no weapon in hand
					expect(M.HeatSourceFor(nil)).to.beNil()

					-- the option off: no source
					GryMod.API.RegisterWeapon("t_firemode", {heat = function() return 1 end})
					convar:SetString("0")
					expect(M.HeatSourceFor(weapon)).to.beNil()
				end)

				convar:SetString(saved)
				GryMod.API.SafeCallReset("weapon:t_firemode/heat")

				if not ok then
					error(err, 0)
				end
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
				expect(icon("weapon_frag")).to.equal("HandGrenade")
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
			-- The icons are read from the weapon registry (nothing in the HUD knows a class): an addon's weapon registered with
			-- RegisterWeapon, or declaring SWEP.GryHUD, picks its icon the same way the stock weapons do.
			name = "a weapon registered through RegisterWeapon gets its icon from the registry: icon, else slotIcon, else the fire mode",
			func = function(state)
				local M = GryMod.FlashHUD
				local API = GryMod.API
				local function gun(automatic)
					return {GetClass = function() return "t_firemode" end, Primary = {Automatic = automatic}}
				end

				API.RegisterWeapon("t_firemode", {icon = "Claymore", slotIcon = "Mine", fire = "burst"})
				expect(M.FireModeFor(gun(true))).to.equal("Claymore")
				API.RegisterWeapon("t_firemode", {slotIcon = "Mine", fire = "burst"})
				expect(M.FireModeFor(gun(true))).to.equal("Mine")
				API.RegisterWeapon("t_firemode", {fire = "burst"})
				expect(M.FireModeFor(gun(true))).to.equal("Burst")
				API.RegisterWeapon("t_firemode", {fire = "semi"})
				expect(M.FireModeFor(gun(true))).to.equal("Single") -- the registry wins over Primary.Automatic
				API.RegisterWeapon("t_firemode", {fire = "auto"})
				expect(M.FireModeFor(gun(false))).to.equal("Auto")
				API.RegisterWeapon("t_firemode", {fire = "none"})
				expect(M.FireModeFor(gun(true))).to.equal("NoGun")
			end
		},
		{
			name = "the 12 Crysis icons nothing chose before are shown when a weapon picks them (registry or SWEP.GryHUD)",
			func = function(state)
				local M = GryMod.FlashHUD

				for _, label in ipairs({"Incendiary", "Tranquilizer", "infinity", "Narrow", "Moac", "Moar", "TACCannon", "C4", "Gauss", "Gunner", "Mounted", "Claymore"}) do
					GryMod.API.RegisterWeapon("t_firemode", {icon = label})
					expect(M.FireModeFor({GetClass = function() return "t_firemode" end})).to.equal(label)
					expect(M.FireModeFor({GetClass = function() return "t_other" end, GryHUD = {icon = label}})).to.equal(label)
				end
			end
		},
		{
			name = "a declared fire mode wins over a base's resolver, which wins over Primary.Automatic",
			func = function(state)
				local M = GryMod.FlashHUD
				local remove = M.AddFireModeResolver(function(weapon) return weapon.resolverSays end)
				local gun = {GetClass = function() return "t_firemode" end, Primary = {Automatic = true}, resolverSays = "Burst"}

				expect(M.FireModeFor(gun)).to.equal("Burst")
				GryMod.API.RegisterWeapon("t_firemode", {fire = "semi"})
				expect(M.FireModeFor(gun)).to.equal("Single")
				remove()
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
			-- fails when a resolver file that is loaded twice (a hot reload, an addon that includes it again) is asked twice and the list piles up, or when a key does not
			-- replace the earlier resolver of the same key, or two different keys do not both stay
			name = "AddFireModeResolver with a key: the same key replaces the earlier resolver (a reloaded file does not pile up), another key adds one, the returned function takes it away",
			func = function(state)
				local M = GryMod.FlashHUD
				local calls = {first = 0, second = 0, other = 0}
				local function resolver(name)
					return function(weapon)
						calls[name] = calls[name] + 1

						return weapon.says
					end
				end

				local gun = {GetClass = function() return "t_keyed" end, says = "Burst"}
				local removeFirst = M.AddFireModeResolver(resolver("first"), "test.key")
				local removeSecond = M.AddFireModeResolver(resolver("second"), "test.key")
				local removeOther = M.AddFireModeResolver(resolver("other"), "test.other")

				expect(M.FireModeFor(gun)).to.equal("Burst")
				expect(calls.first).to.equal(0) -- replaced
				expect(calls.second).to.equal(1)
				expect(calls.other).to.equal(0) -- the first one that answers wins

				-- taking the second away leaves the other key's
				removeSecond()
				expect(M.FireModeFor(gun)).to.equal("Burst")
				expect(calls.other).to.equal(1)

				-- the old remover of a replaced resolver does nothing to the new one
				removeFirst()
				removeOther()
				expect(M.FireModeFor(gun)).to.equal("Single")
			end
		},
		{
			-- fails when the way a text mode ("auto", "3burst", "Safe"...) becomes an icon is not public: an addon's resolver would have to copy it
			name = "FireModeFromName: a mode kept as text becomes an icon label (burst, auto, anything else a single shot, a value that is no text a single shot)",
			func = function()
				local M = GryMod.FlashHUD

				expect(M.FireModeFromName("auto")).to.equal("Auto")
				expect(M.FireModeFromName("Automatic")).to.equal("Auto")
				expect(M.FireModeFromName("3burst")).to.equal("Burst")
				expect(M.FireModeFromName("BURST")).to.equal("Burst")
				expect(M.FireModeFromName("semi")).to.equal("Single")
				expect(M.FireModeFromName("Safe")).to.equal("Single")
				expect(M.FireModeFromName(nil)).to.equal("Single")
				expect(M.FireModeFromName(5)).to.equal("Single")
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
			name = "choosing a theme changes the colours of the next HUD, an unknown name gives the game's own default (military green)",
			func = function(state)
				local M = GryMod.FlashHUD
				local saved = GetConVar("gry_hud_theme"):GetString()
				M.SetTheme("blue")
				expect(M.Theme.Line[1]).to.equal(77)
				M.SetTheme("nothing")
				expect(M.Theme.Line[1]).to.equal(68)
				M.SetTheme(saved)
			end
		},
		{
			name = "the default colour set is the game's own, military green (hud_colorLine/Over/Text 4481854 / 14125840 / 12386209 in its shipped profile and in its code)",
			func = function(state)
				local M = GryMod.FlashHUD
				expect(GetConVar("gry_hud_theme"):GetDefault()).to.equal("default")
				expect(M.Themes.default.Line[1]).to.equal(68)
				expect(M.Themes.default.Over[1]).to.equal(215)
				expect(M.Themes.default.Text[2]).to.equal(255)
				expect(M.DefaultTheme).to.equal(M.Themes.default)
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
				name = "the custom theme takes its three colours from the gry_hud_color_* settings, the default ones where a setting is invalid",
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
					expect(M.Theme.Over[1]).to.equal(M.Themes.default.Over[1])
					expect(M.Theme.Over[3]).to.equal(M.Themes.default.Over[3])
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
