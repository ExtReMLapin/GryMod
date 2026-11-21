-- Tests of the HUD side of the suit malfunctions, GLuaTest format, client realm: the state the server replicates
-- (GryMalfunction, GryFlicker) gives the HUD status in addition to the old "empty bar" rule, the HUD reboots when
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
			name = "with the server state up the old rule stays: an empty bar is a malfunction, with its hysteresis",
			func = function(state)
				expect(HUD.StatusFor(0, 0, false, false, false)).to.equal(1)
				expect(HUD.StatusFor(5, 1, false, false, false)).to.equal(1)
				expect(HUD.StatusFor(10, 1, false, false, false)).to.equal(0)
				expect(HUD.StatusFor(50, 0, false, false, false)).to.equal(0)
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
				expect(HUD.StatusFor(0, 0, false, false, true)).to.equal(1)
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
					expect(played[#played]).to.equal(Sound("cry_error.wav"))
					expect(ply.NanosuitMode).to.equal(GryMod.Modes.SPEED)
				end)
				ply.NanosuitMode = before
				assert(ok, err)
			end
		}
	}
}
