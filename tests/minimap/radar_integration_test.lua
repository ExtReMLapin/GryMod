-- Tests of the minimap's integration into the radar panel (Panel:Draw, Panel:MapTransform, the progress veil in
-- cl_hud_radar_flash.lua), GLuaTest format, client realm. The modules of the minimap that other files own (Settings, Gen, Cache, Floors, View)
-- and the drawing of the movie are replaced by stand-ins that record what they are asked; all of it is put back in afterEach, inside a pcall,
-- also when a case failed. The pure maths and the real movie run for real.

local MODULES = {"Settings", "Gen", "Cache", "Floors", "View"}

local function newPanel()
	return GryMod.FlashRadar.New(GryMod.Flash.Load("hud_radarcompassstealth"))
end

-- the alpha multiplier (0..1) of a clip's colour transform, 1 when it has none
local function alphaOf(clip)
	local cx = clip.entry and clip.entry.cx

	return cx and cx[4] or 1
end

local function install(state)
	GryMod.Minimap = GryMod.Minimap or {}
	state.saved = {}

	for _, name in ipairs(MODULES) do
		state.saved[name] = GryMod.Minimap[name]
	end

	state.savedFlashDraw = GryMod.Flash.Draw
	state.savedLog = GryMod.FlashRadar.LogMinimapError
	state.savedSetDrawColor = surface.SetDrawColor
	state.colors = {}
	GryMod.FlashRadar.ForgetMinimapErrors()

	state.enabled, state.has = true, true
	state.level = {id = "a1", zlo = -32, zhi = 128}
	state.progress = {done = 0, total = 4, percent = 0, active = true, failed = 0}
	state.calls, state.args, state.logged, state.tiles = {}, {}, {}, {}

	GryMod.Minimap.Settings = {
		Enabled = function() return state.enabled end,
		Definition = function() return 3 end,
		TileRes = function() return 1024 end,
		BudgetMs = function() return 6 end
	}

	GryMod.Minimap.Floors = {
		Current = function(z)
			state.args.floorZ = z

			return state.level
		end
	}

	GryMod.Minimap.Gen = {
		Request = function(...)
			state.calls[#state.calls + 1] = "Gen.Request"
			state.args.request = {...}

			if state.requestError then
				error(state.requestError, 0)
			end

			return state.requestResult
		end,
		Progress = function() return state.progress end
	}

	GryMod.Minimap.Cache = {
		TileOf = function(x, y, res, ppm)
			state.args.tileOf = {x, y, res, ppm}

			return math.floor(x / 1000), math.floor(y / 1000)
		end,
		Has = function(tile)
			state.tiles[#state.tiles + 1] = {level = tile.level, tx = tile.tx, ty = tile.ty, res = tile.res, ppm = tile.ppm}

			return state.has
		end
	}

	GryMod.Minimap.View = {
		Draw = function(...)
			state.calls[#state.calls + 1] = "View.Draw"
			state.args.draw = {...}

			if state.drawError then
				error(state.drawError, 0)
			end

			return 1
		end
	}

	GryMod.Flash.Draw = function(root, x, y, scale)
		state.calls[#state.calls + 1] = "Flash.Draw"
		state.args.flash = {root, x, y, scale}

		return true
	end

	GryMod.FlashRadar.LogMinimapError = function(message)
		state.logged[#state.logged + 1] = message
	end

	-- records the colour set and how many recorded calls came before it
	surface.SetDrawColor = function(r, g, b, a)
		state.colors[#state.colors + 1] = {after = #state.calls, r = r, g = g, b = b, a = a}
	end
end

local function uninstall(state)
	if state.saved then
		for _, name in ipairs(MODULES) do
			GryMod.Minimap[name] = state.saved[name]
		end
	end

	if state.savedFlashDraw then
		GryMod.Flash.Draw = state.savedFlashDraw
	end

	GryMod.FlashRadar.LogMinimapError = state.savedLog

	if state.savedSetDrawColor then
		surface.SetDrawColor = state.savedSetDrawColor
	end
end

-- applies a matrix {a, b, c, d, tx, ty} to a point, the way the movie's drawing does
local function apply(m, x, y)
	return m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
end

-- the point of the screen a radar pixel lands on, step by step (no composed matrix): the Units clip's point, the matrix of Units, the
-- matrix of Root, then the scale and the offset of Panel:Draw
local function screenPoint(rootM, unitsM, x, y, scale, rx, ry)
	local R = GryMod.FlashRadar
	local px, py = R.UNITS_CENTRE_X + rx * R.UNITS_PIXEL, R.UNITS_CENTRE_Y + ry * R.UNITS_PIXEL
	px, py = apply(unitsM, px, py)
	px, py = apply(rootM, px, py)

	return px * scale + x, py * scale + y
end

-- a panel that only has what MapTransform and Draw read: the entry of Root, the Units clip with its entry
local function fakePanel(rootM, unitsM)
	local units = {entry = {m = unitsM}}

	return setmetatable({
		root = {},
		main = {entry = {m = rootM}, Child = function(_, name) if name == "Units" then return units end end}
	}, GryMod.FlashRadar.Panel)
end

local function hookCounts()
	local counts = {}

	for event, handlers in pairs(hook.GetTable()) do
		local n = 0

		for _ in pairs(handlers) do n = n + 1 end

		counts[event] = n
	end

	return counts
end

return {
	groupName = "GryMod radar and minimap (integration)",
	beforeEach = function(state)
		install(state)
	end,
	afterEach = function(state)
		pcall(uninstall, state)
	end,
	cases = {
		{
			name = "the map is drawn before the movie: Gen.Request, then View.Draw, then Flash.Draw (the call is after Flash.Draw, or missing)",
			func = function(state)
				newPanel():Draw(10, 20, 1)
				expect(#state.calls).to.equal(3)
				expect(state.calls[1]).to.equal("Gen.Request")
				expect(state.calls[2]).to.equal("View.Draw")
				expect(state.calls[3]).to.equal("Flash.Draw")
			end
		},
		{
			name = "the movie is still drawn with the root and the position of Draw (Flash.Draw is not given other arguments)",
			func = function(state)
				local panel = newPanel()
				panel:Draw(10, 20, 1.5)
				expect(state.args.flash[1]).to.equal(panel.root)
				expect(state.args.flash[2]).to.equal(10)
				expect(state.args.flash[3]).to.equal(20)
				expect(state.args.flash[4]).to.equal(1.5)
			end
		},
		{
			name = "Gen.Request gets the level, the player's position and 1.75 times the range in units (another extent, range in metres, or no level)",
			func = function(state)
				local ply = LocalPlayer()
				local pos = ply:GetPos()
				local range = GryMod.FlashRadar.Range() / GryMod.RadarShared.METRES_PER_UNIT
				newPanel():Draw(0, 0, 1)
				local request = state.args.request
				expect(request[1]).to.equal(state.level)
				expect(request[2]).to.aboutEqual(pos.x, 0.01)
				expect(request[3]).to.aboutEqual(pos.y, 0.01)
				expect(request[4]).to.aboutEqual(range * 1.75, 0.001)
				expect(state.args.floorZ).to.aboutEqual(pos.z, 0.01)
			end
		},
		{
			name = "View.Draw gets the transform, the position, the yaw, the range in units, the level and the alpha 0.6",
			func = function(state)
				local ply = LocalPlayer()
				local pos = ply:GetPos()
				local range = GryMod.FlashRadar.Range() / GryMod.RadarShared.METRES_PER_UNIT
				newPanel():Draw(0, 0, 1)
				local draw = state.args.draw
				expect(type(draw[1])).to.equal("table")
				expect(draw[2]).to.aboutEqual(pos.x, 0.01)
				expect(draw[3]).to.aboutEqual(pos.y, 0.01)
				expect(draw[4]).to.aboutEqual(ply:EyeAngles().y, 0.01)
				expect(draw[5]).to.aboutEqual(range, 0.001)
				expect(draw[6]).to.equal(state.level)
				expect(draw[7]).to.equal(0.6)
			end
		},
		{
			name = "the yaw given to View.Draw is always the player's eye yaw, the map turns like the contacts (even if a Settings.Rotate were still around and said false)",
			func = function(state)
				GryMod.Minimap.Settings.Rotate = function() return false end
				newPanel():Draw(0, 0, 1)
				expect(state.args.draw[4]).to.aboutEqual(LocalPlayer():EyeAngles().y, 0.01)
			end
		},
		{
			name = "the draw colour is put back to opaque white right after View.Draw, before the movie draws (the map's alpha is left in surface)",
			func = function(state)
				newPanel():Draw(0, 0, 1)
				expect(#state.colors).to.equal(1)
				local color = state.colors[1]
				expect(color.after).to.equal(2) -- after Gen.Request and View.Draw, before Flash.Draw
				expect(color.r).to.equal(255)
				expect(color.g).to.equal(255)
				expect(color.b).to.equal(255)
				expect(color.a).to.equal(255)
			end
		},
		{
			name = "the draw colour is put back also when View.Draw raised, and is not touched with the minimap off",
			func = function(state)
				state.drawError = "view blew up"
				newPanel():Draw(0, 0, 1)
				expect(#state.colors).to.equal(1)
				expect(state.colors[1].a).to.equal(255)
				state.colors, state.drawError, state.enabled = {}, nil, false
				newPanel():Draw(0, 0, 1)
				expect(#state.colors).to.equal(0)
			end
		},
		{
			name = "Gen.Request answering false or nil is not an error: nothing is logged and the map is still drawn",
			func = function(state)
				state.requestResult = false
				local panel = newPanel()
				panel:Draw(0, 0, 1)
				state.requestResult = nil
				panel:Draw(0, 0, 1)
				expect(#state.logged).to.equal(0)
				local draws = 0

				for _, call in ipairs(state.calls) do
					if call == "View.Draw" then draws = draws + 1 end
				end

				expect(draws).to.equal(2)
			end
		},
		{
			name = "the text is the whole percentage and a percentage of 99.9 is not rounded up to 100 (a rounding, or a decimal point)",
			func = function(state)
				state.has = false
				state.progress = {done = 3, total = 4, percent = 99.9, active = true, failed = 0}
				local panel = newPanel()
				panel:Draw(0, 0, 1)
				expect(panel.zone:Child("Zone").text).to.equal("99%")
				state.progress = {done = 1, total = 3, percent = 100 / 3, active = true, failed = 0}
				panel:Draw(0, 0, 1)
				expect(panel.zone:Child("Zone").text).to.equal("33%")
			end
		},
		{
			name = "a present tile with an idle generator (active false) leaves no veil and no text",
			func = function(state)
				state.has = true
				state.progress = {done = 4, total = 4, percent = 100, active = false, failed = 0}
				local panel = newPanel()
				panel:SetSector("gm_bigcity")
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				expect(panel.main:Child("Noise").visible).to.beFalse()
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(1, 0.001)
				expect(panel.progressText).to.beNil()
				expect(panel.zone:Child("Zone").text).to.equal("gm_bigcity")
			end
		},
		{
			name = "the range follows gry_radar_range (the range is a constant)",
			func = function(state)
				local convar = GetConVar("gry_radar_range")
				local old = convar:GetString()

				local ok, err = pcall(function()
					convar:SetString("40")
					newPanel():Draw(0, 0, 1)
					expect(state.args.draw[5]).to.aboutEqual(40 / GryMod.RadarShared.METRES_PER_UNIT, 0.001)
					expect(state.args.request[4]).to.aboutEqual(40 / GryMod.RadarShared.METRES_PER_UNIT * 1.75, 0.001)
				end)

				convar:SetString(old)

				if not ok then error(err, 0) end
			end
		},
		{
			name = "the transform sends a radar pixel where the movie draws it: Units' point, Units' matrix, Root's matrix, then the scale and the offset",
			func = function(state)
				local panel = newPanel()
				local x, y, scale = 100, 50, 2
				panel:Draw(x, y, scale)
				local xf = state.args.draw[1]
				local rootM, unitsM = panel.main.entry.m, panel.main:Child("Units").entry.m

				-- the movie's numbers: Root {0.998627, -0.0523376, 0, 1, 54.8, 538.9}; Units is placed at x 18.6 and its y depends on the frame (68.1 or 68.4)
				expect(rootM[1]).to.aboutEqual(0.998627, 1e-6)
				expect(rootM[2]).to.aboutEqual(-0.0523376, 1e-6)
				expect(rootM[5]).to.aboutEqual(54.8, 1e-6)
				expect(rootM[6]).to.aboutEqual(538.9, 1e-6)
				expect(unitsM[5]).to.aboutEqual(18.6, 1e-6)

				for _, p in ipairs({{0, 0}, {10, -20}, {-43, 43}, {43, 7.5}}) do
					local ex, ey = screenPoint(rootM, unitsM, x, y, scale, p[1], p[2])
					local gx, gy = apply(xf, p[1], p[2])
					expect(gx).to.aboutEqual(ex, 1e-6)
					expect(gy).to.aboutEqual(ey, 1e-6)
				end

				-- the player (radar pixel 0, 0) by hand: (64.1, 52.3) + Units' offset = the point in Root
				local ux, uy = 64.1 + unitsM[5], 52.3 + unitsM[6]
				local gx, gy = apply(xf, 0, 0)
				expect(gx).to.aboutEqual((0.998627 * ux + 54.8) * 2 + 100, 1e-4)
				expect(gy).to.aboutEqual((-0.0523376 * ux + uy + 538.9) * 2 + 50, 1e-4)
			end
		},
		{
			name = "the transform composes in that order for matrices that do not commute (a rotation and a shear in the wrong order gives other points)",
			func = function(state)
				local rootM = {0.8, 0.6, -0.5, 1.2, 30, -12}
				local unitsM = {1.1, -0.2, 0.3, 0.9, 5, 70}
				local panel = fakePanel(rootM, unitsM)
				local xf = panel:MapTransform(40, 25, 1.5)

				for _, p in ipairs({{0, 0}, {10, -20}, {-43, 43}, {43, 7.5}}) do
					local ex, ey = screenPoint(rootM, unitsM, 40, 25, 1.5, p[1], p[2])
					local gx, gy = apply(xf, p[1], p[2])
					expect(gx).to.aboutEqual(ex, 1e-6)
					expect(gy).to.aboutEqual(ey, 1e-6)
				end
			end
		},
		{
			name = "a panel without a Units clip draws the movie and asks nothing of the minimap (no nil guard)",
			func = function(state)
				local panel = fakePanel({1, 0, 0, 1, 0, 0}, {1, 0, 0, 1, 0, 0})
				panel.main.Child = function() return nil end
				panel:Draw(0, 0, 1)
				expect(state.calls[#state.calls]).to.equal("Flash.Draw")
				expect(#state.logged).to.equal(0)
			end
		},
		{
			name = "Gen.Request and View.Draw are called at every draw (Gen is cheap, it compares with its previous request)",
			func = function(state)
				local panel = newPanel()

				for _ = 1, 3 do
					panel:Draw(0, 0, 1)
				end

				local requests, draws = 0, 0

				for _, call in ipairs(state.calls) do
					if call == "Gen.Request" then requests = requests + 1 end
					if call == "View.Draw" then draws = draws + 1 end
				end

				expect(requests).to.equal(3)
				expect(draws).to.equal(3)
			end
		},
		{
			name = "with gry_minimap off neither Gen.Request nor View.Draw is called and the movie is drawn (the switch is ignored)",
			func = function(state)
				state.enabled = false
				newPanel():Draw(0, 0, 1)
				expect(#state.calls).to.equal(1)
				expect(state.calls[1]).to.equal("Flash.Draw")
			end
		},
		{
			name = "with a module of the minimap missing the radar draws on without a word",
			func = function(state)
				GryMod.Minimap.Settings = nil
				newPanel():Draw(0, 0, 1)
				expect(#state.calls).to.equal(1)
				expect(state.calls[1]).to.equal("Flash.Draw")
				expect(#state.logged).to.equal(0)
			end
		},
		-- the progress veil
		{
			name = "a missing tile under the player: noise 0.6 with the units kept, the percentage in the zone text; asked once (SetNoise at every draw)",
			func = function(state)
				state.has = false
				state.progress = {done = 1, total = 4, percent = 40.7, active = true, failed = 0}
				local panel = newPanel()
				local noiseCalls = 0
				local real = panel.SetNoise

				panel.SetNoise = function(self, v, keep)
					noiseCalls = noiseCalls + 1
					state.args.noise = {v, keep}

					return real(self, v, keep)
				end

				panel:Draw(0, 0, 1)
				expect(noiseCalls).to.equal(1)
				expect(state.args.noise[1]).to.equal(0.6)
				expect(state.args.noise[2]).to.beTrue()
				expect(panel.progressText).to.equal("40%")
				expect(panel.zone:Child("Zone").text).to.equal("40%")
				expect(panel.main:Child("Noise").visible).to.beTrue()
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(1, 0.001)
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				expect(noiseCalls).to.equal(1)
				expect(panel.progressText).to.equal("40%")
			end
		},
		{
			name = "the tile looked up is the one under the player: its level id, the tile of the position, the settings' resolution and definition",
			func = function(state)
				state.has = false
				newPanel():Draw(0, 0, 1)
				local pos = LocalPlayer():GetPos()
				local tile = state.tiles[1]
				expect(tile.level).to.equal("a1")
				expect(tile.tx).to.equal(math.floor(pos.x / 1000))
				expect(tile.ty).to.equal(math.floor(pos.y / 1000))
				expect(tile.res).to.equal(1024)
				expect(tile.ppm).to.equal(3)
				expect(state.args.tileOf[3]).to.equal(1024)
				expect(state.args.tileOf[4]).to.equal(3)
			end
		},
		{
			name = "a new percentage changes the text and not the noise; the tile coming in clears both; absent again brings both back",
			func = function(state)
				state.has = false
				state.progress = {done = 1, total = 4, percent = 25, active = true, failed = 0}
				local panel = newPanel()
				local noiseCalls = {}
				local real = panel.SetNoise

				panel.SetNoise = function(self, v, keep)
					noiseCalls[#noiseCalls + 1] = {v, keep}

					return real(self, v, keep)
				end

				panel:Draw(0, 0, 1)
				expect(#noiseCalls).to.equal(1)
				expect(panel.zone:Child("Zone").text).to.equal("25%")

				state.progress = {done = 2, total = 4, percent = 50, active = true, failed = 0}
				panel:Draw(0, 0, 1)
				expect(#noiseCalls).to.equal(1)
				expect(panel.zone:Child("Zone").text).to.equal("50%")

				state.has = true
				panel:Draw(0, 0, 1)
				expect(#noiseCalls).to.equal(2)
				expect(noiseCalls[2][1]).to.equal(0)
				expect(panel.progressText).to.beNil()
				expect(panel.main:Child("Noise").visible).to.beFalse()
				panel:Draw(0, 0, 1)
				expect(#noiseCalls).to.equal(2)

				state.has = false
				panel:Draw(0, 0, 1)
				expect(#noiseCalls).to.equal(3)
				expect(noiseCalls[3][1]).to.equal(0.6)
				expect(noiseCalls[3][2]).to.beTrue()
				expect(panel.zone:Child("Zone").text).to.equal("50%")
			end
		},
		{
			name = "with the tile present nothing is asked of the noise at all (SetNoise(0) at every draw)",
			func = function(state)
				local panel = newPanel()
				local noiseCalls = 0
				panel.SetNoise = function() noiseCalls = noiseCalls + 1 end

				for _ = 1, 3 do
					panel:Draw(0, 0, 1)
				end

				expect(noiseCalls).to.equal(0)
				expect(panel.progressText).to.beNil()
			end
		},
		{
			name = "the sector name comes back in the zone field when the tile arrives (the progress text replaces the sector for good)",
			func = function(state)
				state.has = false
				state.progress = {done = 0, total = 4, percent = 0, active = true, failed = 0}
				local panel = newPanel()
				panel:SetSector("gm_bigcity")
				panel:Draw(0, 0, 1)
				expect(panel.zone:Child("Zone").text).to.equal("0%")
				state.has = true
				panel:Draw(0, 0, 1)
				expect(panel.zone:Child("Zone").text).to.equal("gm_bigcity")
			end
		},
		{
			name = "switching gry_minimap off during the generation clears the veil and the text (the veil stays)",
			func = function(state)
				state.has = false
				local panel = newPanel()
				panel:SetSector("gm_bigcity")
				panel:Draw(0, 0, 1)
				expect(panel.main:Child("Noise").visible).to.beTrue()
				state.enabled = false
				panel:Draw(0, 0, 1)
				expect(panel.main:Child("Noise").visible).to.beFalse()
				expect(panel.progressText).to.beNil()
				expect(panel.zone:Child("Zone").text).to.equal("gm_bigcity")
			end
		},
		-- failures never stop the radar
		{
			name = "an error raised by View.Draw does not stop the movie, and is shown once however many frames repeat it (no pcall, or no memory of the message)",
			func = function(state)
				state.drawError = "view blew up"
				local panel = newPanel()

				for _ = 1, 3 do
					panel:Draw(0, 0, 1)
				end

				local flashDraws = 0

				for _, call in ipairs(state.calls) do
					if call == "Flash.Draw" then flashDraws = flashDraws + 1 end
				end

				expect(flashDraws).to.equal(3)
				expect(#state.logged).to.equal(1)
				expect(string.find(state.logged[1], "view blew up", 1, true) ~= nil).to.beTrue()

				state.drawError = "another failure"
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				expect(#state.logged).to.equal(2)
				expect(string.find(state.logged[2], "another failure", 1, true) ~= nil).to.beTrue()
			end
		},
		{
			name = "an error raised by Gen.Request does not stop the movie either",
			func = function(state)
				state.requestError = "gen blew up"
				newPanel():Draw(0, 0, 1)
				expect(state.calls[#state.calls]).to.equal("Flash.Draw")
				expect(#state.logged).to.equal(1)
			end
		},
		{
			name = "an error in a module that returns nothing sensible (Floors.Current gives nil) does not stop the movie",
			func = function(state)
				state.level = nil
				newPanel():Draw(0, 0, 1)
				expect(state.calls[#state.calls]).to.equal("Flash.Draw")
			end
		},
		-- no hook
		{
			name = "drawing the radar with the minimap adds no hook (Think, Tick, HUDPaint or any other)",
			func = function(state)
				local before = hookCounts()
				local panel = newPanel()
				state.has = false

				for _ = 1, 3 do
					panel:Draw(0, 0, 1)
				end

				state.has = true
				panel:Draw(0, 0, 1)

				local after = hookCounts()

				for event, n in pairs(after) do
					expect(n).to.equal(before[event] or 0)
				end

				local source = file.Read("lua/grymod/client/cl_hud_radar_flash.lua", "GAME") or ""
				expect(string.find(source, "hook.Add", 1, true)).to.beNil()
				expect(string.find(source, "timer.Create", 1, true)).to.beNil()
			end
		}
	}
}
