-- GryMod client-side tests, GLuaTest format (run with gmod-mcp: tests_run realm=client).
-- Needs a loaded map (singleplayer is enough).

local realRunConsoleCommand = RunConsoleCommand
local realPlaySound = surface.PlaySound
local savedConVars = {}
local conVarNames = {"cl_Eyefinity", "gry_hud", "gry_sounds", "gry_xadd", "gry_xdist"}

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
	afterEach = function(state)
		RunConsoleCommand = realRunConsoleCommand
		surface.PlaySound = realPlaySound

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

		LocalPlayer().NanosuitMode = GryMod.Modes.ARMOR
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
			name = "opening the options panel does not reset Eyefinity",
			func = function(state)
				local eye = GetConVar("cl_Eyefinity")
				eye:SetInt(1)
				local writes = {}
				RunConsoleCommand = function(name, value)
					writes[#writes + 1] = tostring(name):lower() .. "=" .. tostring(value)
				end
				state.panel = vgui.Create("ControlPanel")
				GryMod.GryOptionschute(state.panel)
				expect(eye:GetInt()).to.equal(1)
				expect(table.HasValue(writes, "cl_eyefinity=0")).to.beFalse()
			end
		},
		{
			name = "the HUD can be turned off and the choice is remembered",
			func = function(state)
				GryMod.SetHUDEnabled(false)
				expect(GetConVar("gry_hud"):GetBool()).to.beFalse()
				expect(hook.GetTable().HUDPaint.HUDBASECRY).to.beNil()
				expect(hook.GetTable().HUDShouldDraw["How to: HUD Example HUD hider"]).to.beNil()
				-- the quick menu is not part of the HUD: the abilities stay usable
				expect(hook.GetTable().HUDPaint.GRYHUD ~= nil).to.beTrue()

				GryMod.SetHUDEnabled(true)
				expect(GetConVar("gry_hud"):GetBool()).to.beTrue()
				expect(hook.GetTable().HUDPaint.HUDBASECRY ~= nil).to.beTrue()
				expect(hook.GetTable().HUDShouldDraw["How to: HUD Example HUD hider"] ~= nil).to.beTrue()
			end
		},
		{
			name = "the radar bars are never negative and grow with the number of NPCs",
			func = function(state)
				local previous = {0, 0, 0, 0}

				for count = 0, 30 do
					local levels = {GryMod.RadarLevels(count)}
					expect(#levels).to.equal(4)

					for i = 1, 4 do
						expect(levels[i]).to.beGreaterThan(-0.0001)
						expect(levels[i] >= previous[i]).to.beTrue()
					end

					previous = levels
				end

				local none = {GryMod.RadarLevels(0)}
				expect(none[1] + none[2] + none[3] + none[4]).to.equal(0)
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
				surface.PlaySound = function() played = played + 1 end
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
			name = "the quick menu is centred on the screen, or on the middle screen with Eyefinity",
			func = function(state)
				GetConVar("cl_Eyefinity"):SetInt(0)
				local x = GryMod.MenuCenter()
				expect(x).to.aboutEqual(ScrW() / 2, 0.01)
				GetConVar("cl_Eyefinity"):SetInt(1)
				x = GryMod.MenuCenter()
				expect(x).to.aboutEqual(ScrW() / 6, 0.01)
			end
		},
	}
}
