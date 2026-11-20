-- GryMod client-side tests, GLuaTest format (run with gmod-mcp: tests_run realm=client).
-- Needs a loaded map (singleplayer is enough).

local realRunConsoleCommand = RunConsoleCommand
local realPlaySound = surface.PlaySound
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

		-- back to Armor, icon included (the early return of SetNanosuitMode needs a different mode first)
		LocalPlayer().NanosuitMode = -1
		GryMod.ApplyServerMode(GryMod.Modes.ARMOR)
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
			name = "the HUD layout is computed once and rebuilt when a setting changes",
			func = function(state)
				GetConVar("gry_xadd"):SetInt(0)
				GetConVar("gry_xdist"):SetInt(0)
				local first = GryMod.GetHudLayout()
				expect(GryMod.GetHudLayout() == first).to.beTrue() -- same table: nothing allocated per frame
				expect(first.W).to.equal(ScrW())

				GetConVar("gry_xadd"):SetInt(30)
				GetConVar("gry_xdist"):SetInt(-20)
				local moved = GryMod.GetHudLayout()
				expect(moved.xa).to.equal(30)
				expect(moved.xd).to.equal(-20)
				expect(moved == first).to.beFalse()
			end
		},
		{
			name = "the HUD layout gives the positions the original formulas gave",
			func = function(state)
				GetConVar("gry_xadd"):SetInt(30)
				GetConVar("gry_xdist"):SetInt(-20)
				local L = GryMod.GetHudLayout()
				-- the original formulas, with the original names
				local W, H = ScrW(), ScrH()
				local xa, xd = 30, -20
				local tol = 0.000001
				expect(L.baseX).to.aboutEqual(W - (W / 4.06) + xa + xd, tol)
				expect(L.baseY).to.aboutEqual(H - (W / 5.19), tol)
				expect(L.compassX).to.aboutEqual(W * (10 / 1920) - xa + xd, tol)
				expect(L.radarX).to.aboutEqual(W * (64 / 1920) - xa + xd, tol)
				expect(L.radarY[3]).to.aboutEqual(H - W * (145.5 / 1920), tol)
				expect(L.maskPoly[2].x).to.aboutEqual(-1 * xa + xd + W * (273 / 1920), tol)
				expect(L.maskPoly[2].y).to.aboutEqual(H - W * (227 / 1920), tol)
				expect(L.energyPoly1[3].x).to.aboutEqual(xa + xd + W - W * (277 / 1920), tol)
				expect(L.energyPoly1[3].y).to.aboutEqual(H - W * (136 / 1920), tol)
				expect(L.healthPoly1[5].y).to.aboutEqual(H - W * (97 / 1920), tol)
				expect(L.healthPoly2[2].x).to.aboutEqual(xa + xd + W - W * (228 / 1920), tol)
				expect(L.ammoX).to.aboutEqual(W - (W / 7.5) + xa + xd, tol)
				expect(L.modeY).to.aboutEqual(H - (W / 15.5), tol)
			end
		},
		{
			name = "the compass letters sit where the original formulas put them",
			func = function(state)
				GetConVar("gry_xadd"):SetInt(30)
				GetConVar("gry_xdist"):SetInt(-20)
				local W, H = ScrW(), ScrH()
				local xa, xd = 30, -20
				local tol = 0.000001
				local offsets = {N = 0, NE = 45, E = 90, SE = 135, SW = -135, W = -90, NW = -45}
				local order = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"}

				for _, yaw in ipairs({-170, -33.3, 0, 12.5, 90, 179}) do
					local ly = yaw + 6.256798

					for index, letter in ipairs(order) do
						local x, y
						if letter == "S" then
							local m = math.max(math.NormalizeAngle(ly + 180), math.NormalizeAngle(ly - 180))
							x = W * (20 / 1920) - xa + xd + (m * 3.32) + W * (134 / 1920)
							y = H - W * (218 / 1920) - ((m * 3.32) / 15) + W * (-5 / 1920)
						else
							local v = ly + offsets[letter]
							x = W * (20 / 1920) - xa + xd + (v * 3.32) + W * (134 / 1920)
							y = H - W * (218 / 1920) - ((v * 3.32) / 15) + W * (-5 / 1920)
						end
						local gx, gy = GryMod.CompassPosition(index, yaw)
						expect(gx).to.aboutEqual(x, tol)
						expect(gy).to.aboutEqual(y, tol)
					end
				end
			end
		},
		{
			name = "every compass letter moves at the same speed when the player turns (south used to be 50 % faster)",
			func = function(state)
				GetConVar("gry_xadd"):SetInt(0)
				GetConVar("gry_xdist"):SetInt(0)

				-- away from the +-180 seam, one more degree of yaw moves every letter by the same distance
				for _, yaw in ipairs({-150, -100, -40, 0, 30, 100, 150}) do
					local x1 = {}

					for index = 1, 8 do
						x1[index] = GryMod.CompassPosition(index, yaw)
					end

					for index = 1, 8 do
						local x2 = GryMod.CompassPosition(index, yaw + 1)
						expect(x2 - x1[index]).to.aboutEqual(3.32, 0.0001)
					end
				end

				-- and across the seam, south goes on at the same speed
				local before = GryMod.CompassPosition(5, 179)
				local after = GryMod.CompassPosition(5, -179.5)
				expect(math.abs(after - before)).to.aboutEqual(3.32 * 1.5, 0.0001)
			end
		},
		{
			name = "the quick menu is centred on the screen",
			func = function(state)
				local x, y = GryMod.MenuCenter()
				expect(x).to.aboutEqual(ScrW() / 2, 0.01)
				expect(y).to.aboutEqual(ScrH() / 2, 0.01)
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
