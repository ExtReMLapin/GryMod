-- GryMod client-side tests, GLuaTest format (run with gmod-mcp: tests_run realm=client).
-- Needs a loaded map (singleplayer is enough).

local realRunConsoleCommand = RunConsoleCommand
local realEmit
local savedConVars = {}
local conVarNames = {"gry_hud", "gry_sounds", "gry_xadd", "gry_xdist"}

local function conVarOrNil(name)
	return GetConVar(name)
end

return {
	groupName = "GryMod client",
	beforeAll = function(state)
		for _, name in ipairs(conVarNames) do
			local cv = conVarOrNil(name)
			savedConVars[name] = cv and cv:GetString() or nil
		end
	end,
	-- nothing is played by these tests: the mix's single exit for sounds is replaced (and the mode voices, that wait half a
	-- second, are cancelled before it is put back)
	beforeEach = function(state)
		realEmit = realEmit or GryMod.SoundMix.Emit
		GryMod.SoundMix.Emit = function() end
	end,
	afterEach = function(state)
		RunConsoleCommand = realRunConsoleCommand

		if state.realCreate then
			CreateClientConVar = state.realCreate
			state.realCreate = nil
		end

		if state.realGetHands then
			FindMetaTable("Player").GetHands = state.realGetHands
			state.realGetHands = nil
		end

		if IsValid(state.panel) then
			state.panel:Remove()
		end

		-- put everything back where the user had it
		for name, value in pairs(savedConVars) do
			local cv = conVarOrNil(name)
			if cv then cv:SetString(value) end
		end

		-- back to Armor, icon included (the early return of SetNanosuitMode needs a different mode first)
		LocalPlayer().NanosuitMode = -1
		GryMod.ApplyServerMode(GryMod.Modes.ARMOR)
		timer.Remove("GryModModeVoice")
		GryMod.SoundMix.Emit = realEmit
	end,
	cases = {
		{
			-- ConVar:GetFlags() does not report FCVAR_ARCHIVE for Lua-created convars in this build, so
			-- the test watches how the convars are created (shouldsave = true adds FCVAR_ARCHIVE).
			name = "the settings are created to be saved between sessions",
			func = function(state)
				local created = {}
				state.realCreate = CreateClientConVar
				CreateClientConVar = function(name, default, shouldsave, ...)
					created[name] = shouldsave

					return state.realCreate(name, default, shouldsave, ...)
				end

				include("grymod/client/cl_hud.lua")
				CreateClientConVar = state.realCreate

				for _, name in ipairs(conVarNames) do
					expect(created[name]).to.beTrue()
				end
			end
		},
		{
			name = "opening the options panel does not reset a setting",
			func = function(state)
				local sounds = GetConVar("gry_sounds")
				sounds:SetInt(0)
				local writes = {}
				RunConsoleCommand = function(name, value)
					writes[#writes + 1] = tostring(name):lower() .. "=" .. tostring(value)
				end
				state.panel = vgui.Create("ControlPanel")
				GryMod.GryOptionschute(state.panel)
				expect(sounds:GetInt()).to.equal(0)
				expect(table.HasValue(writes, "gry_sounds=1")).to.beFalse()
			end
		},
		{
			name = "the HUD can be turned off and the choice is remembered",
			func = function(state)
				GryMod.SetHUDEnabled(false)
				expect(GetConVar("gry_hud"):GetBool()).to.beFalse()
				expect(hook.GetTable().HUDPaint.GRYFLASHHUD).to.beNil()
				expect(hook.GetTable().HUDShouldDraw["How to: HUD Example HUD hider"]).to.beNil()
				-- the quick menu is not part of the HUD: it stays usable
				expect(GryMod.FlashMenu.Enabled()).to.beTrue()

				GryMod.SetHUDEnabled(true)
				expect(GetConVar("gry_hud"):GetBool()).to.beTrue()
				expect(hook.GetTable().HUDPaint.GRYFLASHHUD ~= nil).to.beTrue()
				expect(hook.GetTable().HUDShouldDraw["How to: HUD Example HUD hider"] ~= nil).to.beTrue()
				GryMod.ApplyHUD()
			end
		},
		{
			name = "the vanilla HUD stays when the Crysis HUD cannot be drawn (missing movie)",
			func = function(state)
				local realApply = GryMod.FlashHUD.Apply
				GryMod.FlashHUD.Apply = function() return false end
				GryMod.SetHUDEnabled(true)
				expect(hook.GetTable().HUDShouldDraw["How to: HUD Example HUD hider"]).to.beNil()
				GryMod.FlashHUD.Apply = realApply
				GryMod.SetHUDEnabled(true)
				expect(hook.GetTable().HUDShouldDraw["How to: HUD Example HUD hider"] ~= nil).to.beTrue()
			end
		},
		{
			name = "the radar update counts the NPCs near without error, for the stealth bar of the compass panel",
			func = function(state)
				GryMod.RadarCount = nil
				local ok, err = pcall(GryMod.UpdateRadar)
				expect(ok).to.beTrue()
				expect(type(GryMod.RadarCount)).to.equal("number")
			end
		},
		{
			name = "the radar timer exists once, even after the file is loaded again",
			func = function(state)
				GryMod.StartRadar()
				GryMod.StartRadar()
				expect(timer.Exists("GryModRadar")).to.beTrue()
			end
		},
		{
			name = "sounds can be switched off",
			func = function(state)
				local played = 0
				GryMod.SoundMix.Emit = function() played = played + 1 end
				GetConVar("gry_sounds"):SetInt(1)
				GryMod.PlaySound("suit/suit_maximum_armor.mp3")
				expect(played).to.equal(1)
				GetConVar("gry_sounds"):SetInt(0)
				GryMod.PlaySound("suit/suit_maximum_armor.mp3")
				expect(played).to.equal(1)
			end
		},
		{
			name = "the mode sent by the server always wins on the client",
			func = function(state)
				LocalPlayer().NanosuitMode = GryMod.Modes.SPEED
				GryMod.ApplyServerMode(GryMod.Modes.ARMOR)
				expect(LocalPlayer().NanosuitMode).to.equal(GryMod.Modes.ARMOR)
				-- and picking the same mode as the (resynchronised) current one is a no-op
				GryMod.ApplyServerMode(GryMod.Modes.CLOAK)
				expect(LocalPlayer().NanosuitMode).to.equal(GryMod.Modes.CLOAK)
				GryMod.ApplyServerMode(GryMod.Modes.ARMOR)
			end
		},
		{
			name = "cloak does not error when the player has no hands entity",
			func = function(state)
				local meta = FindMetaTable("Player")
				state.realGetHands = meta.GetHands
				meta.GetHands = function() return NULL end
				LocalPlayer().NanosuitMode = GryMod.Modes.ARMOR
				expect(function() LocalPlayer():SetNanosuitMode(GryMod.Modes.CLOAK, false) end).to.succeed()
			end
		},
		{
			name = "the Eyefinity mode is gone",
			func = function(state)
				expect(GryMod.EyeFinityScrW).to.beNil()
			end
		},
	}
}
