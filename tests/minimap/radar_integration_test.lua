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
	state.tileOfCalls = {}
	-- the state table is shared by the cases of the group: what an earlier case made the stand-ins do is cleared
	state.requestError, state.requestResult, state.requestReason, state.drawError, state.viewLastError = nil, nil, nil, nil, nil
	state.autoForError = nil

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

			return state.requestResult, state.requestReason
		end,
		Progress = function() return state.progress end
	}

	GryMod.Minimap.Cache = {
		TileOf = function(x, y, res, ppm)
			state.args.tileOf = {x, y, res, ppm}
			state.tileOfCalls[#state.tileOfCalls + 1] = {x, y, res, ppm}

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
			state.args.drawInFlash, state.args.drawDepth = state.inFlash, state.hookDepth
			GryMod.Minimap.View.LastError = state.viewLastError

			if state.drawError then
				error(state.drawError, 0)
			end

			return 1
		end
	}

	-- the movie's drawing: like the real one it runs the hook of the Root clip (drawBefore, at drawBeforeDepth) in the middle of its entries; the call
	-- is recorded when it is done, so what the hook calls comes before it
	GryMod.Flash.Draw = function(root, x, y, scale)
		state.args.flash = {root, x, y, scale}
		local main = type(root) == "table" and root.Child and root:Child("Root")

		if main and main.drawBefore then
			state.inFlash, state.hookDepth = true, main.drawBeforeDepth
			local ok, err = pcall(main.drawBefore, 1, 0, 0, 1, 0, 0)
			state.inFlash = false

			if not ok then
				error(err, 0)
			end
		end

		state.calls[#state.calls + 1] = "Flash.Draw"

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

-- The settings' side of the automatic definition, as stand-ins on top of the ones install made: the level in use (state.definition), the level the rule will
-- give (state.autoLevel), the one before the current one (state.previousDefinition, kept as the real settings do when the level changes), and what the radar asked.
local function installAuto(state)
	local S = GryMod.Minimap.Settings

	state.auto, state.definition, state.autoLevel, state.previousDefinition = true, 8, 8, nil
	state.autoCalls, state.setCalls = {}, {}

	S.DefinitionAuto = function() return state.auto end
	S.Definition = function() return state.definition end
	S.AutoDefinitionFor = function(density, previous)
		state.calls[#state.calls + 1] = "Settings.AutoDefinitionFor"
		state.autoCalls[#state.autoCalls + 1] = {density, previous}

		if state.autoForError then
			error(state.autoForError, 0)
		end

		return state.autoLevel
	end
	S.SetAutoDefinition = function(ppm)
		state.calls[#state.calls + 1] = "Settings.SetAutoDefinition"
		state.setCalls[#state.setCalls + 1] = ppm

		if ppm ~= state.definition then
			state.previousDefinition = state.definition
			state.definition = ppm
		end

		return true
	end
	S.PreviousDefinition = function() return state.previousDefinition end
	S.SetScreenConstant = function(k)
		state.screenK = k

		return true
	end
end

-- the density the radar must give the rule: its pixels per metre times the screen pixels per radar pixel (the length of a column of the transform)
local function expectedDensity(panel, scale, metres)
	local xf = panel:MapTransform(0, 0, scale)

	return GryMod.RadarShared.PIXELS / metres * math.sqrt(xf[1] * xf[1] + xf[2] * xf[2])
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
		-- The cases that set gry_radar_range by hand assume the MANUAL range. With the automatic zoom on (the player's own setting, archived) the range follows the
		-- three modes and the slider is ignored, so these cases failed on his machine and passed on a clean one. Every case starts with the automatic zoom off
		-- (the cases about the automatic zoom turn it on themselves) and the player's value is put back in afterEach.
		local auto = GetConVar("gry_radar_autozoom")

		state.savedAutoZoom = auto and auto:GetString() or nil

		if auto then
			auto:SetString("0")
		end

		if GryMod.RadarZoom and GryMod.RadarZoom.Reset then
			pcall(GryMod.RadarZoom.Reset)
		end

		install(state)
	end,
	afterEach = function(state)
		pcall(uninstall, state)

		pcall(function()
			local auto = GetConVar("gry_radar_autozoom")

			if auto and state.savedAutoZoom then
				auto:SetString(state.savedAutoZoom)
			end

			if GryMod.RadarZoom and GryMod.RadarZoom.Reset then
				GryMod.RadarZoom.Reset()
			end
		end)
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
			name = "Gen.Request gets the level, the player's position and the map extent (MAP_EXTENT) times the range in units (another extent, range in metres, or no level)",
			func = function(state)
				local ply = LocalPlayer()
				local pos = ply:GetPos()
				local range = GryMod.FlashRadar.Range() / GryMod.RadarShared.METRES_PER_UNIT
				newPanel():Draw(0, 0, 1)
				local request = state.args.request
				expect(request[1]).to.equal(state.level)
				expect(request[2]).to.aboutEqual(pos.x, 0.01)
				expect(request[3]).to.aboutEqual(pos.y, 0.01)
				expect(request[4]).to.aboutEqual(range * GryMod.FlashRadar.MAP_EXTENT, 0.001)
				expect(state.args.floorZ).to.aboutEqual(pos.z, 0.01)
			end
		},
		{
			name = "View.Draw gets the transform, the position, the yaw, the range in units, the level and the map alpha (MAP_ALPHA)",
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
				expect(draw[7]).to.equal(GryMod.FlashRadar.MAP_ALPHA)
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
					expect(state.args.request[4]).to.aboutEqual(40 / GryMod.RadarShared.METRES_PER_UNIT * GryMod.FlashRadar.MAP_EXTENT, 0.001)
				end)

				convar:SetString(old)

				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if: the map is asked for (or the definition chosen from) the range shown instead of the target: a glide would then change the tiles asked for at every
			-- frame, or the pyramid's level on the way; or if the view is drawn with the target (no glide to see)
			name = "Automatic zoom: during a glide View.Draw gets the range SHOWN, while Gen.Request and the automatic definition get the TARGET, the same at every frame of the glide",
			func = function(state)
				installAuto(state)

				local auto = GetConVar("gry_radar_autozoom")
				local foot, indoor, delay = GetConVar("gry_radar_zoom_foot"), GetConVar("gry_radar_zoom_indoor"), GetConVar("gry_radar_zoom_delay")
				local saved = {auto:GetString(), foot:GetString(), indoor:GetString(), delay:GetString()}
				local Z = GryMod.RadarZoom

				local ok, err = pcall(function()
					auto:SetString("1")
					foot:SetString("75")
					indoor:SetString("25")
					delay:SetString("0.7")
					Z.Reset()

					-- on foot, then indoors for 0.7 s: the mode went to indoor 0.6 s ago, so the glide from 75 to 25 is at 3/4 of its time
					local now = RealTime()

					Z.Observe(now - 2, false, false)
					Z.Observe(now - 1.3, false, true)
					Z.Observe(now - 0.6, false, true)
					expect(Z.Mode()).to.equal("indoor")

					local mpu = GryMod.RadarShared.METRES_PER_UNIT
					local panel = newPanel()

					state.autoCalls = {}
					panel:Draw(0, 0, 1)

					local shown = state.args.draw[5] * mpu
					local firstExtent = state.args.request[4]
					local firstDensity = state.autoCalls[1][1]

					expect(shown < 75 and shown > 25).to.beTrue()
					expect(firstExtent).to.aboutEqual(25 / mpu * GryMod.FlashRadar.MAP_EXTENT, 0.001)
					expect(firstDensity).to.aboutEqual(expectedDensity(panel, 1, 25), 1e-6)

					panel:Draw(0, 0, 1)
					expect(state.args.request[4]).to.aboutEqual(firstExtent, 0.001)
					expect(state.autoCalls[#state.autoCalls][1]).to.aboutEqual(firstDensity, 1e-6)
				end)

				pcall(function()
					auto:SetString(saved[1])
					foot:SetString(saved[2])
					indoor:SetString(saved[3])
					delay:SetString(saved[4])
					Z.Reset()
				end)

				if not ok then error(err, 0) end
			end
		},
		{
			name = "at 5 metres (gry_radar_range at its minimum) Gen and View get a small finite extent, the real View needs a handful of tiles, and the contact at 4 m shows while the one at 6 m does not",
			func = function(state)
				local convar = GetConVar("gry_radar_range")
				local old = convar:GetString()

				local ok, err = pcall(function()
					convar:SetString("5")
					newPanel():Draw(0, 0, 1)

					local mpu = GryMod.RadarShared.METRES_PER_UNIT
					local range = 5 / mpu
					local extent = state.args.request[4]

					expect(GryMod.FlashRadar.Range()).to.equal(5)
					expect(state.args.draw[5]).to.aboutEqual(range, 0.001)
					expect(extent == extent and extent > 0 and extent < math.huge).to.beTrue()
					expect(extent).to.aboutEqual(range * GryMod.FlashRadar.MAP_EXTENT, 0.001)

					-- the real View (the stand-ins replaced it for the draw only): the tiles of that extent around the player at the owner's usual definition
					local realView = state.saved.View
					expect(realView ~= nil and realView.VisibleTiles ~= nil).to.beTrue()
					local pos = LocalPlayer():GetPos()
					-- View reads GryMod.Minimap.Cache at call time (the tile size is the cache's job): the real cache is put back for the call only
					local standIn = GryMod.Minimap.Cache
					GryMod.Minimap.Cache = state.saved.Cache
					local okTiles, tiles = pcall(realView.VisibleTiles, state.level, pos.x, pos.y, extent, 1024, 3)
					GryMod.Minimap.Cache = standIn

					if not okTiles then error(tiles, 0) end

					expect(type(tiles)).to.equal("table")
					expect(#tiles >= 1 and #tiles <= 9).to.beTrue()

					-- the contacts: 8.6 pixels a metre, the glass is 46 pixels ahead
					local R = GryMod.FlashRadar
					local function at(metres)
						return {id = 1, x = metres / mpu, y = 0, z = 0, yaw = 0, type = 1, sub = 4, marker = false, big = false}
					end

					local shown = R.Contacts(Vector(0, 0, 0), 0, {at(4)}, 0, R.Range())
					local gone = R.Contacts(Vector(0, 0, 0), 0, {at(6)}, 0, R.Range())

					expect(#shown).to.equal(1)
					expect(shown[1].x == shown[1].x and shown[1].y == shown[1].y).to.beTrue()
					expect(#gone).to.equal(0)
				end)

				pcall(function() convar:SetString(old) end)

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
			-- the owner's design (2026-11-22): from the moment a player joins, while the server has not answered, while it waits or computes the in/out map, the radar is veiled,
			-- with the SERVER's percentage; then, once the in/out map is there, the veil is the CLIENT's tile percentage as before. Breaks if the veil follows only the tiles, if
			-- the in/out percentage is not shown with its name, or if the veil stays after the in/out map has come
			name = "the in/out map first: while it is loading the radar is veiled with 'In/out NN%' even when the tile under the player is there, then the tile's own percentage",
			func = function(state)
				local realZone = GryMod.ZoneMapClient
				local zone = {loading = true, percent = 40}
				local ok, err = pcall(function()
					GryMod.ZoneMapClient = {Loading = function() return zone.loading, zone.percent end}

					-- the tile under the player is there (no tile veil), the in/out map is loading: veil and the server's percentage
					state.has = true
					state.progress = {done = 4, total = 4, percent = 100, active = false, failed = 0}

					local panel = newPanel()

					panel:Draw(0, 0, 1)
					expect(panel.progressText).to.equal("In/out 40%")
					expect(panel.main:Child("Noise").visible).to.beTrue()
					expect(panel.zone:Child("Zone").text).to.equal("In/out 40%")

					-- it goes up with the server's work
					zone.percent = 75
					panel:Draw(0, 0, 1)
					expect(panel.progressText).to.equal("In/out 75%")

					-- the in/out map is there and the tile is not: the veil stays, now with the tile's own percentage
					zone.loading = false
					state.has = false
					state.progress = {done = 1, total = 4, percent = 40.7, active = true, failed = 0}
					panel:Draw(0, 0, 1)
					expect(panel.progressText).to.equal("40%")
					expect(panel.main:Child("Noise").visible).to.beTrue()

					-- both there: no veil, no text
					state.has = true
					state.progress = {done = 4, total = 4, percent = 100, active = false, failed = 0}
					panel:Draw(0, 0, 1)
					expect(panel.progressText).to.beNil()
					expect(panel.main:Child("Noise").visible).to.beFalse()

					-- a module that raises is no veil and no error: the tiles decide as before
					GryMod.ZoneMapClient = {Loading = function() error("boom") end}
					panel:Draw(0, 0, 1)
					expect(panel.progressText).to.beNil()

					-- no module at all
					GryMod.ZoneMapClient = nil
					panel:Draw(0, 0, 1)
					expect(panel.progressText).to.beNil()
				end)

				GryMod.ZoneMapClient = realZone

				if not ok then error(err, 0) end
			end
		},
		{
			-- the owner's decision (2026-11-22): while the server waits for the navigation mesh (the engine gives no progress) the veil says "Navigation mesh..." with NO
			-- percentage; when the server computes, "In/out NN%". Breaks if the wait shows a percentage ("In/out 0%"), if the phase is ignored, if a switch from the wait to the
			-- computation does not change the text exactly once, or if the same text is applied again at every draw
			name = "the in/out map waits for the navigation mesh: the veil says 'Navigation mesh...' with no percentage, then 'In/out NN%' once the server computes (text changed once per change)",
			func = function(state)
				local realZone = GryMod.ZoneMapClient
				local zone = {phase = "wait", percent = 0}
				local ok, err = pcall(function()
					GryMod.ZoneMapClient = {Loading = function() return true, zone.percent, zone.phase end}

					state.has = true
					state.progress = {done = 4, total = 4, percent = 100, active = false, failed = 0}

					local panel = newPanel()
					local texts = {}
					local real = panel.SetProgressText

					panel.SetProgressText = function(self, text)
						texts[#texts + 1] = text or false

						return real(self, text)
					end

					panel:Draw(0, 0, 1)
					panel:Draw(0, 0, 1)
					expect(panel.progressText).to.equal("Navigation mesh...")
					expect(string.find(panel.progressText, "%", 1, true)).to.beNil()
					expect(panel.zone:Child("Zone").text).to.equal("Navigation mesh...")
					expect(panel.main:Child("Noise").visible).to.beTrue()
					expect(#texts).to.equal(1)

					-- the server computes: the percentage, one change
					zone.phase, zone.percent = "percent", 0
					panel:Draw(0, 0, 1)
					expect(panel.progressText).to.equal("In/out 0%")
					expect(#texts).to.equal(2)
					panel:Draw(0, 0, 1)
					expect(#texts).to.equal(2)

					zone.percent = 41
					panel:Draw(0, 0, 1)
					expect(panel.progressText).to.equal("In/out 41%")
					expect(#texts).to.equal(3)

					-- back to the wait (a new start): the label alone again
					zone.phase, zone.percent = "wait", 0
					panel:Draw(0, 0, 1)
					expect(panel.progressText).to.equal("Navigation mesh...")
					expect(#texts).to.equal(4)

					-- no phase given (a module that only answers the percentage): the percentage, as before
					GryMod.ZoneMapClient = {Loading = function() return true, 12 end}
					panel:Draw(0, 0, 1)
					expect(panel.progressText).to.equal("In/out 12%")
				end)

				GryMod.ZoneMapClient = realZone

				if not ok then error(err, 0) end
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
		-- the floor below (wave 2)
		{
			name = "with Settings.Below() > 0 the level below goes to Gen.Request (5th argument) and to View.Draw with the opacity times the map's alpha (nothing passed)",
			func = function(state)
				local lower = {id = "a0", zlo = -160, zhi = 0}
				state.belowLevel = lower
				GryMod.Minimap.Settings.Below = function() return 0.4 end
				GryMod.Minimap.Floors.Below = function(level)
					state.args.belowOf = level
					state.belowCalls = (state.belowCalls or 0) + 1

					return state.belowLevel
				end

				local range = GryMod.FlashRadar.Range() / GryMod.RadarShared.METRES_PER_UNIT
				newPanel():Draw(0, 0, 1)
				expect(state.args.belowOf).to.equal(state.level)
				expect(state.args.request[4]).to.aboutEqual(range * GryMod.FlashRadar.MAP_EXTENT, 0.001)
				expect(state.args.request[5]).to.equal(lower)
				local draw = state.args.draw
				expect(draw[6]).to.equal(state.level)
				expect(draw[7]).to.equal(GryMod.FlashRadar.MAP_ALPHA)
				expect(draw[8]).to.equal(lower)
				expect(draw[9]).to.aboutEqual(0.4 * GryMod.FlashRadar.MAP_ALPHA, 1e-9)
			end
		},
		{
			name = "with Settings.Below() = 0 Floors.Below is not asked and both calls are as before (nil for the new arguments)",
			func = function(state)
				state.belowLevel = {id = "a0", zlo = -160, zhi = 0}
				state.belowCalls = 0
				GryMod.Minimap.Settings.Below = function() return 0 end
				GryMod.Minimap.Floors.Below = function() state.belowCalls = state.belowCalls + 1 return state.belowLevel end
				newPanel():Draw(0, 0, 1)
				expect(state.belowCalls).to.equal(0)
				expect(state.args.request[5]).to.beNil()
				expect(state.args.draw[8]).to.beNil()
				expect(state.args.draw[9] or 0).to.equal(0)
				expect(state.args.draw[7]).to.equal(GryMod.FlashRadar.MAP_ALPHA)
			end
		},
		{
			name = "without Settings.Below or without Floors.Below the calls are as before and nothing is logged",
			func = function(state)
				-- no Below in Settings (the stand-in has none): Floors.Below must not even be needed
				newPanel():Draw(0, 0, 1)
				expect(state.args.request[5]).to.beNil()
				expect(state.args.draw[8]).to.beNil()

				-- Settings.Below asks for a floor, but Floors has no Below
				GryMod.Minimap.Settings.Below = function() return 0.5 end
				GryMod.Minimap.Floors.Below = nil
				newPanel():Draw(0, 0, 1)
				expect(state.args.request[5]).to.beNil()
				expect(state.args.draw[8]).to.beNil()
				expect(state.args.draw[9] or 0).to.equal(0)
				expect(state.args.draw[7]).to.equal(GryMod.FlashRadar.MAP_ALPHA)
				expect(#state.logged).to.equal(0)
			end
		},
		{
			name = "Floors.Below answering nil and a reason means no floor below, not an error: the map is still drawn",
			func = function(state)
				GryMod.Minimap.Settings.Below = function() return 0.5 end
				GryMod.Minimap.Floors.Below = function() return nil, "no level" end
				newPanel():Draw(0, 0, 1)
				expect(#state.logged).to.equal(0)
				expect(state.args.request[5]).to.beNil()
				expect(state.args.draw[8]).to.beNil()
				expect(state.args.draw[9] or 0).to.equal(0)
				expect(state.calls[#state.calls]).to.equal("Flash.Draw")
				expect(state.calls[2]).to.equal("View.Draw")
			end
		},
		{
			name = "the veil and the text depend on the main level only: the floor below being made, or its tile being absent, changes nothing",
			func = function(state)
				local lower = {id = "a0", zlo = -160, zhi = 0}
				GryMod.Minimap.Settings.Below = function() return 0.4 end
				GryMod.Minimap.Floors.Below = function() return lower end
				-- the main tile is there, the lower one is being made (Progress describes the main level, belowDone/belowTotal the other)
				state.has = true
				state.progress = {done = 4, total = 4, percent = 100, active = true, failed = 0, belowDone = 1, belowTotal = 9}
				local panel = newPanel()
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				expect(panel.main:Child("Noise").visible).to.beFalse()
				expect(panel.progressText).to.beNil()
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(1, 0.001)

				-- only tiles of the main level are looked up under the player
				for _, tile in ipairs(state.tiles) do
					expect(tile.level).to.equal("a1")
				end

				-- the main tile is absent: the text is the main level's percentage, whatever the lower floor says
				state.has = false
				state.progress = {done = 1, total = 4, percent = 25, active = true, failed = 0, belowDone = 9, belowTotal = 9}
				panel:Draw(0, 0, 1)
				expect(panel.main:Child("Noise").visible).to.beTrue()
				expect(panel.progressText).to.equal("25%")

				for _, tile in ipairs(state.tiles) do
					expect(tile.level).to.equal("a1")
				end
			end
		},
		-- the outside, under the floor below (the open level of the map)
		{
			-- breaks if: the outside is not asked of Floors, not given to Gen.Request as 6th argument or to View.Draw as 10th with the map's alpha times its opacity
			name = "with Settings.Outside() > 0 the outside goes to Gen.Request (6th argument) and to View.Draw (10th) with the opacity times the map's alpha, whatever the floor below is",
			func = function(state)
				local lower = {id = "a0", zlo = -160, zhi = 0}
				local outside = {id = "open", open = true, zlo = -500, zhi = 900}
				GryMod.Minimap.Settings.Below = function() return 0.4 end
				GryMod.Minimap.Settings.Outside = function() return 0.3 end
				GryMod.Minimap.Floors.Below = function() return lower end
				GryMod.Minimap.Floors.Outside = function(level)
					state.args.outsideOf = level
					state.outsideCalls = (state.outsideCalls or 0) + 1

					return outside
				end

				newPanel():Draw(0, 0, 1)
				expect(state.args.outsideOf).to.equal(state.level)
				expect(state.args.request[5]).to.equal(lower)
				expect(state.args.request[6]).to.equal(outside)
				local draw = state.args.draw
				expect(draw[6]).to.equal(state.level)
				expect(draw[8]).to.equal(lower)
				expect(draw[9]).to.aboutEqual(0.4 * GryMod.FlashRadar.MAP_ALPHA, 1e-9)
				expect(draw[10]).to.equal(outside)
				expect(draw[11]).to.aboutEqual(0.3 * GryMod.FlashRadar.MAP_ALPHA, 1e-9)

				-- without a floor below the outside is still there
				GryMod.Minimap.Settings.Below = function() return 0 end
				newPanel():Draw(0, 0, 1)
				expect(state.args.request[5]).to.beNil()
				expect(state.args.request[6]).to.equal(outside)
				expect(state.args.draw[8]).to.beNil()
				expect(state.args.draw[10]).to.equal(outside)
			end
		},
		{
			-- breaks if: Floors.Outside is asked with the setting at 0, or the new arguments are not nil
			name = "with Settings.Outside() = 0 Floors.Outside is not asked and both calls have no outside (nil, alpha 0)",
			func = function(state)
				state.outsideCalls = 0
				GryMod.Minimap.Settings.Outside = function() return 0 end
				GryMod.Minimap.Floors.Outside = function() state.outsideCalls = state.outsideCalls + 1 return {id = "open", open = true} end
				newPanel():Draw(0, 0, 1)
				expect(state.outsideCalls).to.equal(0)
				expect(state.args.request[6]).to.beNil()
				expect(state.args.draw[10]).to.beNil()
				expect(state.args.draw[11] or 0).to.equal(0)
				expect(state.args.draw[7]).to.equal(GryMod.FlashRadar.MAP_ALPHA)
			end
		},
		{
			-- breaks if: a missing Settings.Outside or Floors.Outside raises, logs, or draws an outside
			name = "without Settings.Outside or without Floors.Outside there is no outside, and nothing is logged",
			func = function(state)
				-- no Outside in Settings (the stand-in has none)
				GryMod.Minimap.Floors.Outside = function() return {id = "open", open = true} end
				newPanel():Draw(0, 0, 1)
				expect(state.args.request[6]).to.beNil()
				expect(state.args.draw[10]).to.beNil()

				-- Settings.Outside asks for it, but Floors has no Outside
				GryMod.Minimap.Settings.Outside = function() return 0.5 end
				GryMod.Minimap.Floors.Outside = nil
				newPanel():Draw(0, 0, 1)
				expect(state.args.request[6]).to.beNil()
				expect(state.args.draw[10]).to.beNil()
				expect(state.args.draw[11] or 0).to.equal(0)
				expect(state.args.draw[7]).to.equal(GryMod.FlashRadar.MAP_ALPHA)
				expect(#state.logged).to.equal(0)

				-- a nonsense setting is no outside
				GryMod.Minimap.Floors.Outside = function() return {id = "open", open = true} end

				for _, bad in ipairs({0 / 0, "x", -1, false}) do
					GryMod.Minimap.Settings.Outside = function() return bad end
					newPanel():Draw(0, 0, 1)
					expect(state.args.request[6]).to.beNil()
					expect(state.args.draw[10]).to.beNil()
				end

				expect(#state.logged).to.equal(0)
			end
		},
		{
			-- breaks if: an open level (nothing behind it) is reported as an error
			name = "Floors.Outside answering nil and \"open\" (the player is outdoors) or nil and a reason is no outside, not an error: the map is still drawn",
			func = function(state)
				local open = {id = "open", open = true, zlo = -16384, zhi = 16384}
				GryMod.Minimap.Settings.Outside = function() return 0.3 end
				GryMod.Minimap.Floors.CurrentAt = function() return open end
				GryMod.Minimap.Floors.Outside = function(level) state.args.outsideOf = level return nil, "open" end
				newPanel():Draw(0, 0, 1)
				expect(state.args.outsideOf).to.equal(open)
				expect(#state.logged).to.equal(0)
				expect(state.args.request[6]).to.beNil()
				expect(state.args.draw[10]).to.beNil()
				expect(state.args.draw[11] or 0).to.equal(0)
				expect(state.calls[#state.calls]).to.equal("Flash.Draw")
				expect(state.calls[2]).to.equal("View.Draw")

				GryMod.Minimap.Floors.Outside = function() return nil, "no world bounds" end
				newPanel():Draw(0, 0, 1)
				expect(#state.logged).to.equal(0)
				expect(state.args.draw[10]).to.beNil()
			end
		},
		{
			-- breaks if: an error in Floors.Outside loses the whole map
			name = "Floors.Outside that raises is told, and the map is still drawn without the outside",
			func = function(state)
				GryMod.Minimap.Settings.Outside = function() return 0.3 end
				GryMod.Minimap.Floors.Outside = function() error("outside blew up", 0) end
				newPanel():Draw(0, 0, 1)
				expect(#state.logged).to.equal(1)
				expect(state.logged[1]:find("outside blew up", 1, true) ~= nil).to.beTrue()
				expect(state.calls[2]).to.equal("View.Draw")
				expect(state.args.draw[10]).to.beNil()
				expect(state.args.request[6]).to.beNil()
			end
		},
		{
			-- breaks if: the veil or the text count the outside, or the tile of the outside is looked up under the player
			name = "the veil and the text depend on the main level only: the outside being made, or its tile being absent, changes nothing",
			func = function(state)
				local outside = {id = "open", open = true, zlo = -500, zhi = 900}
				GryMod.Minimap.Settings.Outside = function() return 0.3 end
				GryMod.Minimap.Floors.Outside = function() return outside end
				state.has = true
				state.progress = {done = 4, total = 4, percent = 100, active = true, failed = 0, outsideDone = 1, outsideTotal = 9}
				local panel = newPanel()
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				expect(panel.main:Child("Noise").visible).to.beFalse()
				expect(panel.progressText).to.beNil()
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(1, 0.001)

				state.has = false
				state.progress = {done = 1, total = 4, percent = 25, active = true, failed = 0, outsideDone = 9, outsideTotal = 9}
				panel:Draw(0, 0, 1)
				expect(panel.main:Child("Noise").visible).to.beTrue()
				expect(panel.progressText).to.equal("25%")

				for _, tile in ipairs(state.tiles) do
					expect(tile.level).to.equal("a1")
				end
			end
		},
		{
			-- breaks if: the outside alpha does not follow the map's opacity, or the setting is cached and not read at each request
			name = "the outside's alpha is the map's alpha times its own opacity; a change of the setting is seen at the next draw (the next request is recomputed)",
			func = function(state)
				local outside = {id = "open", open = true, zlo = -500, zhi = 900}
				local setting = 0.3
				GryMod.Minimap.Settings.Opacity = function() return 0.7 end
				GryMod.Minimap.Settings.Outside = function() return setting end
				GryMod.Minimap.Floors.Outside = function() return outside end
				local panel = newPanel()
				panel:Draw(0, 0, 1)
				expect(state.args.draw[11]).to.aboutEqual(0.21, 1e-9)
				expect(state.args.request[6]).to.equal(outside)

				setting = 0.5
				panel:Draw(0, 0, 1)
				expect(state.args.draw[11]).to.aboutEqual(0.35, 1e-9)

				setting = 0
				panel:Draw(0, 0, 1)
				expect(state.args.request[6]).to.beNil()
				expect(state.args.draw[10]).to.beNil()
				expect(state.args.draw[11] or 0).to.equal(0)

				setting = 0.3
				panel:Draw(0, 0, 1)
				expect(state.args.request[6]).to.equal(outside)
			end
		},
		{
			-- breaks if: a table is made for the call of each frame (the outside is written in the table of the panel)
			name = "the call kept for the hook is one table per panel: the outside is written into it, no new table at each frame",
			func = function(state)
				local outside = {id = "open", open = true, zlo = -500, zhi = 900}
				GryMod.Minimap.Settings.Outside = function() return 0.3 end
				GryMod.Minimap.Floors.Outside = function() return outside end
				local panel = newPanel()
				panel:Draw(0, 0, 1)
				local call = panel.mapCall
				expect(type(call)).to.equal("table")
				expect(call.outside).to.equal(outside)
				expect(call.outsideAlpha).to.aboutEqual(0.3 * GryMod.FlashRadar.MAP_ALPHA, 1e-9)

				for i = 1, 5 do
					panel:Draw(0, 0, 1)
				end

				expect(panel.mapCall).to.equal(call)
			end
		},
		-- the level of the player from Floors.CurrentAt (wave 3)
		{
			name = "Floors.CurrentAt gets the player's position vector and its level goes to Gen.Request, View.Draw and the tile looked up (Current(z) is still used)",
			func = function(state)
				local ceiling = {id = "z0h2", zlo = -56, zhi = 72}
				state.currentAtCalls = 0
				GryMod.Minimap.Floors.CurrentAt = function(pos)
					state.currentAtCalls = state.currentAtCalls + 1
					state.args.currentAt = pos

					return ceiling
				end

				state.has = false
				newPanel():Draw(0, 0, 1)
				local pos = LocalPlayer():GetPos()
				expect(state.currentAtCalls).to.equal(1)
				expect(isvector(state.args.currentAt)).to.beTrue()
				expect(state.args.currentAt.x).to.aboutEqual(pos.x, 0.01)
				expect(state.args.currentAt.y).to.aboutEqual(pos.y, 0.01)
				expect(state.args.currentAt.z).to.aboutEqual(pos.z, 0.01)
				expect(state.args.floorZ).to.beNil() -- Current(z) was not asked
				expect(state.args.request[1]).to.equal(ceiling)
				expect(state.args.draw[6]).to.equal(ceiling)
				expect(state.tiles[1].level).to.equal("z0h2")
			end
		},
		{
			name = "without Floors.CurrentAt the level comes from Current(z) as before",
			func = function(state)
				GryMod.Minimap.Floors.CurrentAt = nil
				newPanel():Draw(0, 0, 1)
				expect(state.args.floorZ).to.aboutEqual(LocalPlayer():GetPos().z, 0.01)
				expect(state.args.request[1]).to.equal(state.level)
				expect(state.args.draw[6]).to.equal(state.level)
				expect(#state.logged).to.equal(0)
			end
		},
		{
			name = "an open level (outdoors) has no floor below and it is not an error: Floors.Below answers nil and \"open\", nothing is logged",
			func = function(state)
				local open = {id = "open", open = true, zlo = -16384, zhi = 16384}
				GryMod.Minimap.Settings.Below = function() return 0.4 end
				GryMod.Minimap.Floors.CurrentAt = function() return open end
				GryMod.Minimap.Floors.Below = function(level)
					state.args.belowOf = level

					return nil, "open"
				end

				newPanel():Draw(0, 0, 1)
				expect(state.args.belowOf).to.equal(open)
				expect(#state.logged).to.equal(0)
				expect(state.args.request[1]).to.equal(open)
				expect(state.args.request[5]).to.beNil()
				expect(state.args.draw[6]).to.equal(open)
				expect(state.args.draw[8]).to.beNil()
				expect(state.args.draw[9] or 0).to.equal(0)
				expect(state.calls[#state.calls]).to.equal("Flash.Draw")
				expect(state.calls[2]).to.equal("View.Draw")
			end
		},
		-- the map is drawn in the middle of the movie, between the glass and the rest (a map drawn before the film is dimmed by the glass)
		{
			name = "View.Draw runs inside the movie's drawing, from the hook of the Root clip at depth 3: after the glass (depth 1), before the mask, the units and the frame (drawn before the film)",
			func = function(state)
				local panel = newPanel()
				panel:Draw(0, 0, 1)
				expect(state.args.drawInFlash).to.beTrue()
				expect(state.args.drawDepth).to.equal(3)
				expect(panel.main.drawBeforeDepth).to.equal(3)
				expect(type(panel.main.drawBefore)).to.equal("function")
				-- the glass is the Root clip's first entry and the mask is at depth 3 in the movie: the hook is between them
				local depths = {}

				for _, entry in ipairs(panel.main:Entries()) do
					depths[#depths + 1] = entry.depth
				end

				expect(depths[1] < 3).to.beTrue()
				expect(depths[2]).to.equal(3)
			end
		},
		{
			name = "Draw puts the hook back when the Root clip lost it, and draws the map every frame",
			func = function(state)
				local panel = newPanel()
				panel:Draw(0, 0, 1)
				panel.main.drawBefore, panel.main.drawBeforeDepth = nil, nil
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				local draws = 0

				for _, call in ipairs(state.calls) do
					if call == "View.Draw" then draws = draws + 1 end
				end

				expect(draws).to.equal(3)
				expect(state.args.drawInFlash).to.beTrue()
			end
		},
		{
			name = "the map is not drawn when the movie's drawing does not reach the hook, and never twice for one frame (View.Draw stays in the hook)",
			func = function(state)
				local panel = newPanel()
				panel:Draw(0, 0, 1)
				local before = #state.calls
				-- a frame in which the movie is not drawn at all: Draw is not called, nothing may draw the map
				expect(before).to.equal(3)
				-- a movie drawing that ignores the hook
				GryMod.Flash.Draw = function() state.calls[#state.calls + 1] = "Flash.Draw" return true end
				panel:Draw(0, 0, 1)
				local draws = 0

				for _, call in ipairs(state.calls) do
					if call == "View.Draw" then draws = draws + 1 end
				end

				expect(draws).to.equal(1)
			end
		},
		{
			name = "the map's alpha is 0.9 by default and follows Settings.Opacity when there is one; the floor below is that alpha times its own opacity",
			func = function(state)
				expect(GryMod.FlashRadar.MAP_ALPHA).to.equal(0.9)
				newPanel():Draw(0, 0, 1)
				expect(state.args.draw[7]).to.equal(0.9)

				GryMod.Minimap.Settings.Opacity = function() return 0.7 end
				GryMod.Minimap.Settings.Below = function() return 0.4 end
				GryMod.Minimap.Floors.Below = function() return {id = "a0", zlo = -160, zhi = 0} end
				newPanel():Draw(0, 0, 1)
				expect(state.args.draw[7]).to.aboutEqual(0.7, 1e-9)
				expect(state.args.draw[9]).to.aboutEqual(0.28, 1e-9)

				-- a nonsense value is not used
				GryMod.Minimap.Settings.Opacity = function() return 0 / 0 end
				newPanel():Draw(0, 0, 1)
				expect(state.args.draw[7]).to.equal(0.9)
			end
		},
		{
			name = "the extent asked of Gen is the reach of the map frame: View.ExtentFactor() when the view has one, else MAP_EXTENT",
			func = function(state)
				local range = GryMod.FlashRadar.Range() / GryMod.RadarShared.METRES_PER_UNIT
				GryMod.Minimap.View.ExtentFactor = function() return 1.97 end
				newPanel():Draw(0, 0, 1)
				expect(state.args.request[4]).to.aboutEqual(range * 1.97, 0.001)
				GryMod.Minimap.View.ExtentFactor = nil
				newPanel():Draw(0, 0, 1)
				expect(state.args.request[4]).to.aboutEqual(range * GryMod.FlashRadar.MAP_EXTENT, 0.001)
			end
		},
		-- switching the map off during a generation, the errors of the view and of the generator, the index of the cache
		{
			name = "switching gry_minimap off cancels the generator once; switching it on re-arms it (the queue was still being emptied by the PostRender hook)",
			func = function(state)
				state.cancelCalls = 0
				GryMod.Minimap.Gen.Cancel = function() state.cancelCalls = state.cancelCalls + 1 end
				local panel = newPanel()
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				expect(state.cancelCalls).to.equal(0)
				state.enabled = false
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				expect(state.cancelCalls).to.equal(1)
				state.enabled = true
				panel:Draw(0, 0, 1)
				expect(state.cancelCalls).to.equal(1)
				state.enabled = false
				panel:Draw(0, 0, 1)
				expect(state.cancelCalls).to.equal(2)
			end
		},
		{
			name = "a generator without Cancel, a missing one, or a Cancel that raises does not stop the radar (the error is told once)",
			func = function(state)
				state.enabled = false
				newPanel():Draw(0, 0, 1)
				expect(#state.logged).to.equal(0)
				GryMod.Minimap.Gen.Cancel = function() error("cancel failed", 0) end
				local panel = newPanel()
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				expect(#state.logged).to.equal(1)
				expect(string.find(state.logged[1], "cancel failed", 1, true) ~= nil).to.beTrue()
				expect(state.calls[#state.calls]).to.equal("Flash.Draw")
				GryMod.Minimap.Gen = nil
				newPanel():Draw(0, 0, 1)
				expect(state.calls[#state.calls]).to.equal("Flash.Draw")
			end
		},
		{
			name = "View.LastError is told once per message after View.Draw and cleared (the view keeps the last error it swallowed)",
			func = function(state)
				state.viewLastError = "tile 3,4 failed"
				local panel = newPanel()
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				expect(#state.logged).to.equal(1)
				expect(string.find(state.logged[1], "tile 3,4 failed", 1, true) ~= nil).to.beTrue()
				-- the field is given back to nil after the first read: here the stand-in sets it again at each draw, the message is told once all the same
				state.viewLastError = "another one"
				panel:Draw(0, 0, 1)
				expect(#state.logged).to.equal(2)
				state.viewLastError = nil
				panel:Draw(0, 0, 1)
				expect(GryMod.Minimap.View.LastError).to.beNil()
				expect(#state.logged).to.equal(2)
				expect(state.calls[#state.calls]).to.equal("Flash.Draw")
			end
		},
		{
			name = "Gen.Request answering nil and a reason blocks nothing and is told once (too many tiles, no tile size); no reason, no word",
			func = function(state)
				state.requestResult, state.requestReason = nil, "too many tiles"
				local panel = newPanel()
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				expect(#state.logged).to.equal(1)
				expect(string.find(state.logged[1], "too many tiles", 1, true) ~= nil).to.beTrue()
				local draws = 0

				for _, call in ipairs(state.calls) do
					if call == "View.Draw" then draws = draws + 1 end
				end

				expect(draws).to.equal(3)
				state.requestReason = "no tile size"
				panel:Draw(0, 0, 1)
				expect(#state.logged).to.equal(2)
				state.requestResult, state.requestReason = true, nil
				panel:Draw(0, 0, 1)
				expect(#state.logged).to.equal(2)
			end
		},
		{
			name = "when the generation ends (the tile under the player is there and the generator is idle) Cache.Flush is called once, not before and not again",
			func = function(state)
				state.flushCalls = 0
				GryMod.Minimap.Cache.Flush = function() state.flushCalls = state.flushCalls + 1 end
				local panel = newPanel()
				-- always ready and idle: nothing to flush
				state.progress = {done = 4, total = 4, percent = 100, active = false, failed = 0}
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				expect(state.flushCalls).to.equal(0)
				-- generating: the tile under the player is missing
				state.has = false
				state.progress = {done = 1, total = 4, percent = 25, active = true, failed = 0}
				panel:Draw(0, 0, 1)
				expect(state.flushCalls).to.equal(0)
				-- the tile is there but the generator still works: not yet
				state.has = true
				panel:Draw(0, 0, 1)
				expect(state.flushCalls).to.equal(0)
				-- idle: the index is written, once
				state.progress = {done = 4, total = 4, percent = 100, active = false, failed = 0}
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)
				expect(state.flushCalls).to.equal(1)
				-- and again the next time
				state.has, state.progress = false, {done = 0, total = 4, percent = 0, active = true, failed = 0}
				panel:Draw(0, 0, 1)
				state.has, state.progress = true, {done = 4, total = 4, percent = 100, active = false, failed = 0}
				panel:Draw(0, 0, 1)
				expect(state.flushCalls).to.equal(2)
			end
		},
		{
			name = "a cache without Flush, or a Flush that raises, does not stop the radar (told once)",
			func = function(state)
				local panel = newPanel()
				state.has, state.progress = false, {done = 0, total = 4, percent = 0, active = true, failed = 0}
				panel:Draw(0, 0, 1)
				state.has, state.progress = true, {done = 4, total = 4, percent = 100, active = false, failed = 0}
				panel:Draw(0, 0, 1)
				expect(#state.logged).to.equal(0)
				GryMod.Minimap.Cache.Flush = function() error("flush failed", 0) end
				state.has, state.progress = false, {done = 0, total = 4, percent = 0, active = true, failed = 0}
				panel:Draw(0, 0, 1)
				state.has, state.progress = true, {done = 4, total = 4, percent = 100, active = false, failed = 0}
				panel:Draw(0, 0, 1)
				expect(#state.logged).to.equal(1)
				expect(state.calls[#state.calls]).to.equal("Flash.Draw")
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
		-- the automatic definition
		{
			-- breaks if: the density is not the pixels per metre of the radar times the pixels of the screen per radar pixel (a wrong constant, the range in units,
			-- the scale left out), or if the level in use is not given as the previous one for the hysteresis
			name = "Auto: the rule gets the density (radar pixels per metre times screen pixels per radar pixel, 43 / range * the length of a column of the transform) and the level in use",
			func = function(state)
				installAuto(state)

				local convar = GetConVar("gry_radar_range")
				local old = convar:GetString()

				local ok, err = pcall(function()
					for _, metres in ipairs({5, 38}) do
						for _, scale in ipairs({1, 2.5}) do
							convar:SetString(tostring(metres))
							state.autoCalls = {}
							state.definition = 8

							local panel = newPanel()
							panel:Draw(0, 0, scale)

							expect(#state.autoCalls).to.equal(1)
							expect(state.autoCalls[1][1]).to.aboutEqual(expectedDensity(panel, scale, metres), 1e-6)
							expect(state.autoCalls[1][2]).to.equal(8)
						end
					end

					-- a hand-computed number: at 5 m the radar has 43 / 5 = 8.6 pixels a metre, and the length of a column is the scale times the transforms'
					-- lengths; on this panel it is what MapTransform says, so the density is 8.6 times that
					state.autoCalls = {}
					convar:SetString("5")

					local panel = newPanel()
					panel:Draw(0, 0, 4)

					local xf = panel:MapTransform(0, 0, 4)
					expect(state.autoCalls[1][1]).to.aboutEqual(8.6 * math.sqrt(xf[1] ^ 2 + xf[2] ^ 2), 1e-6)
				end)

				pcall(function() convar:SetString(old) end)

				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if: the level is given to Settings after Gen.Request (the generator would ask for the old definition once more), or not at all
			-- the tile preload has no radar to ask which definition a zoom range will get: it needs the screen constant (the density at a range r is k / r), which only the
			-- radar knows. breaks if: the radar does not record it, records the density instead of density * range (it would change with the range), or records it with
			-- the automatic definition off
			name = "Auto: the radar records the screen constant (density times range: the same at every range), once a draw, for the tile preload",
			func = function(state)
				installAuto(state)

				local convar = GetConVar("gry_radar_range")
				local old = convar:GetString()

				local ok, err = pcall(function()
					local seen = {}

					for _, metres in ipairs({10, 38}) do
						convar:SetString(tostring(metres))
						state.screenK = nil

						local panel = newPanel()

						panel:Draw(0, 0, 2.5)
						expect(state.screenK ~= nil).to.beTrue()
						expect(state.screenK).to.aboutEqual(expectedDensity(panel, 2.5, metres) * metres, 1e-6)
						seen[#seen + 1] = state.screenK
					end

					-- the same constant at the two ranges
					expect(seen[1]).to.aboutEqual(seen[2], 1e-6)

					-- with the automatic definition off nothing is recorded (the preload has no pyramid to work with)
					state.auto = false
					state.screenK = nil
					newPanel():Draw(0, 0, 2.5)
					expect(state.screenK).to.beNil()
				end)

				pcall(function() convar:SetString(old) end)

				if not ok then error(err, 0) end
			end
		},
		{
			name = "Auto: the level the rule gave goes to Settings.SetAutoDefinition once a draw, before Gen.Request, and the tile looked up for the veil is at that definition",
			func = function(state)
				installAuto(state)
				state.autoLevel = 32
				state.has = false

				newPanel():Draw(0, 0, 1)

				expect(state.setCalls[1]).to.equal(32)
				expect(#state.setCalls).to.equal(1)
				expect(state.calls[1]).to.equal("Settings.AutoDefinitionFor")
				expect(state.calls[2]).to.equal("Settings.SetAutoDefinition")
				expect(state.calls[3]).to.equal("Gen.Request")
				expect(state.tiles[1].ppm).to.equal(32)
				-- the first tile looked up is at the new definition (the previous one comes after, for the veil)
				expect(state.tileOfCalls[1][4]).to.equal(32)
			end
		},
		{
			-- breaks if: the rule is run with the automatic definition off (the slider would be overwritten, and Settings would keep a level for nothing)
			name = "Auto: with the automatic definition off the rule is not asked and nothing is given to Settings",
			func = function(state)
				installAuto(state)
				state.auto = false

				newPanel():Draw(0, 0, 1)

				expect(#state.autoCalls).to.equal(0)
				expect(#state.setCalls).to.equal(0)
				expect(state.calls[1]).to.equal("Gen.Request")
			end
		},
		{
			-- breaks if: an error in the rule (or settings answering nothing) stops the map: the radar draws on, the error is told once
			name = "Auto: a rule that raises is told once and the map is still asked and drawn (at the definition in use)",
			func = function(state)
				installAuto(state)
				state.autoForError = "rule blew up"

				local panel = newPanel()
				panel:Draw(0, 0, 1)
				panel:Draw(0, 0, 1)

				expect(#state.logged).to.equal(1)
				expect(string.find(state.logged[1], "rule blew up", 1, true) ~= nil).to.beTrue()

				local draws = 0

				for _, call in ipairs(state.calls) do
					if call == "View.Draw" then draws = draws + 1 end
				end

				expect(draws).to.equal(2)
				expect(#state.setCalls).to.equal(0)
			end
		},
		{
			-- breaks if: the veil is decided by the current definition's tile alone (a zoom would hide the map under noise while the previous tiles are drawn)
			name = "Auto: the veil does not appear when the tile under the player does not exist at the new definition but does at the previous one",
			func = function(state)
				installAuto(state)
				state.autoLevel = 32
				state.definition = 8
				state.progress = {done = 0, total = 9, percent = 0, active = true, failed = 0}
				local asked = {}

				GryMod.Minimap.Cache.Has = function(tile)
					asked[#asked + 1] = {level = tile.level, ppm = tile.ppm, tx = tile.tx, ty = tile.ty}

					return tile.ppm == 8
				end

				local panel = newPanel()
				panel:Draw(0, 0, 1)

				expect(panel.main:Child("Noise").visible).to.beFalse()
				expect(panel.progressText).to.beNil()
				expect(asked[1].ppm).to.equal(32)
				expect(asked[2].ppm).to.equal(8)
				expect(asked[2].level).to.equal("a1")

				-- the previous tile is the one under the player at the previous definition: Cache.TileOf was asked for that definition too
				local last = state.tileOfCalls[#state.tileOfCalls]
				expect(last[4]).to.equal(8)
				expect(last[3]).to.equal(1024)
			end
		},
		{
			-- breaks if: any tile of another definition (not the previous one of Settings) hides the veil, or no tile at all does
			name = "Auto: the veil appears (with the percentage) when neither the new nor the previous definition has the tile under the player, and with no previous definition at all",
			func = function(state)
				installAuto(state)
				state.autoLevel = 32
				state.definition = 8
				state.progress = {done = 1, total = 4, percent = 40.7, active = true, failed = 0}
				GryMod.Minimap.Cache.Has = function() return false end

				local panel = newPanel()
				panel:Draw(0, 0, 1)

				expect(panel.main:Child("Noise").visible).to.beTrue()
				expect(panel.progressText).to.equal("40%")

				-- no previous definition (the start): the veil as before
				installAuto(state)
				state.autoLevel, state.definition = 8, 8
				state.has = false
				GryMod.Minimap.Cache.Has = function() return false end

				local second = newPanel()
				second:Draw(0, 0, 1)
				expect(second.main:Child("Noise").visible).to.beTrue()
				expect(second.progressText).to.equal("40%")
			end
		},
		{
			-- breaks if: the previous definition is looked up while the current tile exists (a needless call at every frame), or when it is the current definition
			name = "Auto: with the current tile present, or a previous definition equal to the current one, no other definition is looked up",
			func = function(state)
				installAuto(state)
				state.autoLevel, state.definition = 16, 16
				state.previousDefinition = 4
				state.progress = {done = 4, total = 4, percent = 100, active = false, failed = 0}
				local asked = {}

				GryMod.Minimap.Cache.Has = function(tile)
					asked[#asked + 1] = tile.ppm

					return true
				end

				newPanel():Draw(0, 0, 1)
				expect(#asked).to.equal(1)
				expect(asked[1]).to.equal(16)

				-- missing, with a previous definition equal to the current one: the previous one is no other definition
				asked = {}
				state.previousDefinition = 16
				GryMod.Minimap.Cache.Has = function(tile)
					asked[#asked + 1] = tile.ppm

					return false
				end

				newPanel():Draw(0, 0, 1)
				expect(#asked).to.equal(1)
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
