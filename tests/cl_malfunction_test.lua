-- Tests of the HUD side of the suit malfunctions, GLuaTest format, client realm: the state the server replicates
-- (GryMalfunction, GryFlicker) gives the HUD status (an empty bar is no malfunction, as in the original: leaving the
-- camouflage by firing empties the bar; gry_malfunction_empty 1 brings the old GryMod rule back), the HUD reboots when
-- the suit restarts even though the bar is still empty, a flicker is not a reboot, and the quick menu refuses
-- choices while the suit is down. Server rules: tests/sv_malfunction_test.lua.

local HUD, Boot, Menu
local played
local realPlay, realOption

return {
	groupName = "GryMod HUD malfunction state",
	beforeAll = function(state)
		HUD, Boot, Menu = GryMod.FlashHUD, GryMod.FlashBoot, GryMod.FlashMenu
	end,
	beforeEach = function(state)
		played = {}
		realPlay = GryMod.PlaySound
		GryMod.PlaySound = function(path)
			played[#played + 1] = path

			return true
		end

		GetConVar("gry_hud_boot"):SetString("1")
		Boot.Reset()
	end,
	afterEach = function(state)
		GryMod.PlaySound = realPlay
		Boot.Reset()
	end,
	cases = {
		{
			name = "a suit that the server says is down gives status 1 whatever the energy",
			func = function(state)
				expect(HUD.StatusFor(100, 0, true, false, false)).to.equal(1)
				expect(HUD.StatusFor(0, 1, true, false, false)).to.equal(1)
				expect(HUD.StatusFor(nil, 0, true, false, true)).to.equal(1) -- no flicker over a malfunction
			end
		},
		{
			name = "with the server state up, an empty bar is no malfunction (leaving the camouflage by firing empties it, in the original too)",
			func = function(state)
				expect(HUD.StatusFor(0, 0, false, false, false)).to.equal(0)
				expect(HUD.StatusFor(0, 1, false, false, false)).to.equal(0)
				expect(HUD.StatusFor(5, 1, false, false, false)).to.equal(0)
				expect(HUD.StatusFor(0, 0, false, false, true)).to.equal(2) -- a flicker is still shown
			end
		},
		{
			name = "gry_malfunction_empty 1: the old rule, an empty bar is a malfunction, with its hysteresis",
			func = function(state)
				expect(HUD.StatusFor(0, 0, false, false, false, true)).to.equal(1)
				expect(HUD.StatusFor(5, 1, false, false, false, true)).to.equal(1)
				expect(HUD.StatusFor(10, 1, false, false, false, true)).to.equal(0)
				expect(HUD.StatusFor(50, 0, false, false, false, true)).to.equal(0)
				expect(HUD.StatusFor(0, 1, false, true, false, true)).to.equal(0) -- the restart still wins
			end
		},
		{
			name = "gry_malfunction_empty exists, off by default (it is created with CreateClientConVar(..., true): saved)",
			func = function(state)
				local convar = GetConVar("gry_malfunction_empty")
				expect(convar).to.exist()
				expect(convar:GetDefault()).to.equal("0")
			end
		},
		{
			name = "the HUD options panel has the switch of the old rule",
			func = function(state)
				local found = false
				local panel = vgui.Create("ControlPanel")
				GryMod.GryHUDOptions(panel)

				local function walk(p)
					if p.ClassName == "DCheckBoxLabel" and p.Button and p.Button.m_strConVar == "gry_malfunction_empty" then
						found = true
					end

					for _, child in ipairs(p:GetChildren()) do
						walk(child)
					end
				end

				walk(panel)
				panel:Remove()
				expect(found).to.beTrue()
			end
		},
		{
			name = "right after the suit restarts the HUD reboots although the bar is still empty",
			func = function(state)
				expect(HUD.StatusFor(0, 1, false, true, false)).to.equal(0)
				expect(HUD.StatusFor(0, 0, false, true, false)).to.equal(0)
			end
		},
		{
			name = "the restart hold lasts until the bar is above 0, and a malfunction starts it",
			func = function(state)
				expect(HUD.RestartHold(false, true, 0)).to.beTrue() -- down: the hold is armed
				expect(HUD.RestartHold(true, false, 0)).to.beTrue() -- restarted, still empty
				expect(HUD.RestartHold(true, false, 0.2)).to.beFalse() -- the bar has begun to recharge
				expect(HUD.RestartHold(false, false, 0)).to.beFalse() -- an empty bar alone does not arm it
				expect(HUD.RestartHold(true, true, 50)).to.beTrue() -- down again
			end
		},
		{
			name = "a flicker gives status 2 when nothing else is wrong, and never replaces a malfunction",
			func = function(state)
				expect(HUD.StatusFor(80, 0, false, false, true)).to.equal(2)
				expect(HUD.StatusFor(80, 2, false, false, false)).to.equal(0) -- over: back to normal
				expect(HUD.StatusFor(0, 0, false, false, true, true)).to.equal(1) -- the old rule: an empty bar is a malfunction, the flicker does not replace it
			end
		},
		{
			name = "a flicker is not a reboot: the boot sequences ignore status 2",
			func = function(state)
				Boot.OnStatus(1)
				expect(Boot.IsLost()).to.beTrue()
				Boot.OnStatus(2)
				expect(Boot.IsLost()).to.beTrue()
				Boot.OnStatus(0)
				expect(Boot.Current()).to.equal("reboot")

				Boot.Reset()
				Boot.OnStatus(2)
				expect(Boot.Current()).to.beNil()
			end
		},
		{
			name = "the quick menu's sounds are the game's: modification_menu_appear / disappear, preset_navigation_beep, temperature_beep, suit_usage_error",
			func = function(state)
				local s = Menu.Sounds
				expect(s.open).to.equal(Sound("grymod/menu/modification_menu_appear.wav"))
				expect(s.close).to.equal(Sound("grymod/menu/modification_menu_dissapear.wav"))
				expect(s.hover).to.equal(Sound("grymod/menu/preset_navigation_beep_02.wav"))
				expect(s.same).to.equal(Sound("grymod/menu/temperature_beep.wav"))
				expect(s.error).to.equal(Sound("grymod/suit/suit_usage_error.wav"))
				expect(s.select).to.beNil()
			end
		},
		{
			name = "the menu opens with the appear sound; a release on the current mode plays the disappear sound then the temperature beep (mode already active)",
			func = function(state)
				local ply = LocalPlayer()
				local before = ply.NanosuitMode
				ply.NanosuitMode = GryMod.Modes.SPEED
				local ok, err = pcall(function()
					expect(Menu.Begin()).to.beTrue()
					expect(played[#played]).to.equal(Sound("grymod/menu/modification_menu_appear.wav"))
					played = {}
					Menu.Finish()
					expect(#played).to.equal(2)
					expect(played[1]).to.equal(Sound("grymod/menu/modification_menu_dissapear.wav"))
					expect(played[2]).to.equal(Sound("grymod/menu/temperature_beep.wav"))
				end)
				ply.NanosuitMode = before
				Menu.Cancel()
				assert(ok, err)
			end
		},
		{
			name = "choosing another mode plays the disappear sound (no select sound) and asks for the mode",
			func = function(state)
				local ply = LocalPlayer()
				local before = ply.NanosuitMode
				local meta = FindMetaTable("Player")
				local realSet = meta.SetNanosuitMode
				local asked = {}
				meta.SetNanosuitMode = function(self, mode, networked) asked[#asked + 1] = mode end
				ply.NanosuitMode = GryMod.Modes.SPEED
				local ok, err = pcall(function()
					expect(Menu.Begin()).to.beTrue()
					ply.NanosuitMode = GryMod.Modes.ARMOR -- the pointer stays on Speed: the choice differs from the mode
					played = {}
					Menu.Finish()
					expect(#played).to.equal(1)
					expect(played[1]).to.equal(Sound("grymod/menu/modification_menu_dissapear.wav"))
					expect(asked[1]).to.equal(GryMod.Modes.SPEED)
				end)
				meta.SetNanosuitMode = realSet
				ply.NanosuitMode = before
				Menu.Cancel()
				assert(ok, err)
			end
		},
		{
			name = "the quick menu beeps instead of choosing while the suit is down",
			func = function(state)
				local ply = LocalPlayer()
				local before = ply.NanosuitMode
				ply.NanosuitMode = GryMod.Modes.SPEED -- the menu opens on the current mode: a change would be asked
				Boot.OnStatus(1)
				played = {}
				local ok, err = pcall(function()
					expect(Menu.Begin()).to.beTrue()
					Menu.Finish()
					expect(played[#played]).to.equal(Sound("grymod/suit/suit_usage_error.wav"))
					expect(ply.NanosuitMode).to.equal(GryMod.Modes.SPEED)
				end)
				ply.NanosuitMode = before
				assert(ok, err)
			end
		}
	}
}
