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
				-- this is about the classic HUD, whatever style the player picked
				local style = GetConVar("gry_hud_style")
				local savedStyle = style:GetString()
				style:SetString("classic")
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
				style:SetString(savedStyle)
				GryMod.ApplyHUD()
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
				local degPx = W * (3.32 / 1920) -- pixels per degree: proportional to the screen, like the compass picture
				local offsets = {N = 0, NE = 45, E = 90, SE = 135, S = 180, SW = -135, W = -90, NW = -45}
				local order = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"}

				for _, yaw in ipairs({-170, -33.3, 0, 12.5, 90, 179}) do
					local ly = yaw + 6.256798

					for index, letter in ipairs(order) do
						-- the heading of the letter relative to the player, wrapped into -180..180
						local v = math.NormalizeAngle(ly + offsets[letter])
						local x = W * (20 / 1920) - xa + xd + (v * degPx) + W * (134 / 1920)
						local y = H - W * (218 / 1920) - ((v * degPx) / 15) + W * (-5 / 1920)
						local gx, gy = GryMod.CompassPosition(index, yaw)
						expect(gx).to.aboutEqual(x, tol)
						expect(gy).to.aboutEqual(y, tol)
					end
				end
			end
		},
		{
			name = "a compass letter does not jump when the yaw goes from 180 to -180",
			func = function(state)
				GetConVar("gry_xadd"):SetInt(0)
				GetConVar("gry_xdist"):SetInt(0)

				-- the engine reports the yaw between -180 and 180: the letters must not depend on the turn
				for index = 1, 8 do
					for _, yaw in ipairs({-179.9, -170, -90, -45, 0, 12.5, 45, 90, 135, 179.9}) do
						local x1, y1 = GryMod.CompassPosition(index, yaw)
						local x2, y2 = GryMod.CompassPosition(index, yaw + 360)
						expect(x2).to.aboutEqual(x1, 0.000001)
						expect(y2).to.aboutEqual(y1, 0.000001)
					end

					-- turning 0.2 degree across the seam moves the letter by 0.2 degree
					local degPx = ScrW() * (3.32 / 1920)
					local before = GryMod.CompassPosition(index, 179.9)
					local after = GryMod.CompassPosition(index, -179.9)
					expect(after - before).to.aboutEqual(0.2 * degPx, 0.000001)
				end
			end
		},
		{
			name = "the compass shows the same headings whatever the resolution",
			func = function(state)
				local function window(W)
					local L = GryMod.BuildHudLayout(W, math.floor(W * 9 / 16), 0, 0)
					local minX, maxX = math.huge, -math.huge

					for _, p in ipairs(L.maskPoly) do
						minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
					end

					return (maxX - minX) / L.degPx, L
				end

				local reference = window(1920)

				for _, W in ipairs({1280, 2560, 3840}) do
					local degrees, L = window(W)
					expect(degrees).to.aboutEqual(reference, 0.0001)
					-- 45 degrees between two neighbouring letters is the same share of the picture
					local nx = GryMod.CompassPositionIn(L, 1, 0)
					local nex = GryMod.CompassPositionIn(L, 2, 0)
					expect(nex - nx).to.aboutEqual(45 * L.degPx, 0.0001)
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
						expect(x2 - x1[index]).to.aboutEqual(ScrW() * (3.32 / 1920), 0.0001)
					end
				end

				-- and across the seam, south goes on at the same speed
				local before = GryMod.CompassPosition(5, 179)
				local after = GryMod.CompassPosition(5, -179.5)
				expect(after - before).to.aboutEqual(ScrW() * (3.32 / 1920) * 1.5, 0.0001)
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
