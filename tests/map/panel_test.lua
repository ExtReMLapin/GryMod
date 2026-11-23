-- Tests of the big map (lua/grymod/client/map/panel.lua), GLuaTest format, client realm: opening and closing (the API, the HUD events, the hooks, the switch),
-- the zoom of the first opening and of the later ones, the pan that starts again at the player, the wheel that zooms toward the mouse, the drags, the markers,
-- the key and the command, the share of the captures, and one frame of drawing against recorders instead of the real surface. The bounds are replaced by a
-- known box around the player; the minimap's cache, capture, floors and settings and the engine's render targets are replaced by stand-ins (as in
-- tiles_test.lua); every stand-in and every convar the cases touch is put back in afterEach inside a pcall, also when a case failed.
-- The real map panel is created (a popup); a case that opens it closes it before it ends.

local LEVEL = {id = "open_t256", open = true, zlo = -100, zhi = 256}
local CONVARS = {"gry_map_enable", "gry_map_zoom", "gry_map_loading_fx", "gry_map_finished", "gry_map_grid"}
local PPM_LEVELS = {2, 4, 8, 16, 32, 64}

local function M()
	local map = GryMod and GryMod.Map

	expect(map ~= nil and map.Open ~= nil).to.beTrue()

	return map
end

local function playerPos()
	return LocalPlayer():GetPos()
end

-- bounds around the player, `half` units each side
local function boundsAround(half)
	local p = playerPos()

	return {x0 = p.x - half, x1 = p.x + half, y0 = p.y - half, y1 = p.y + half, source = "test"}
end

local recorded -- the calls of the drawing recorders

local DRAW_STUBS = {
	surface = {"SetDrawColor", "DrawRect", "DrawTexturedRectUV", "SetMaterial", "DrawLine", "DrawOutlinedRect", "DrawPoly", "DrawCircle"},
	draw = {"SimpleText", "NoTexture", "RoundedBox"},
	render = {"SetScissorRect", "OverrideBlend"}
}

local function stubDrawing(state)
	recorded = {}
	state.drawSaved = {}

	for libName, names in pairs(DRAW_STUBS) do
		local lib = _G[libName]

		state.drawSaved[libName] = {}

		for _, name in ipairs(names) do
			state.drawSaved[libName][name] = lib[name]
			lib[name] = function(...)
				recorded[#recorded + 1] = {libName .. "." .. name, ...}
			end
		end
	end
end

local function unstubDrawing(state)
	for libName, saved in pairs(state.drawSaved or {}) do
		for name, fn in pairs(saved) do
			_G[libName][name] = fn
		end
	end

	state.drawSaved = nil
end

local function callsOf(name)
	local list = {}

	for _, c in ipairs(recorded or {}) do
		if c[1] == name then
			list[#list + 1] = c
		end
	end

	return list
end

local function cacheKey(ppm, tx, ty)
	return ppm .. ":" .. tx .. ":" .. ty
end

return {
	groupName = "GryMod big map",
	beforeEach = function(state)
		local Map = M()
		local Mini = GryMod.Minimap

		state.convars = {}

		for _, name in ipairs(CONVARS) do
			state.convars[name] = GetConVar(name):GetString()
		end

		-- the convars the cases depend on are fixed here (the owner's saved values leak into every client)
		GetConVar("gry_map_enable"):SetString("1")
		GetConVar("gry_map_zoom"):SetString("1")
		GetConVar("gry_map_loading_fx"):SetString("glitch")
		GetConVar("gry_map_finished"):SetString("0")
		GetConVar("gry_map_grid"):SetString("1")

		state.saved = {
			Compute = Map.Bounds.Compute,
			opened = Map._state.opened,
			lastClose = Map._state.lastClose,
			Cache = Mini.Cache, Capture = Mini.Capture, Floors = Mini.Floors, Settings = Mini.Settings,
			Engine = {},
			IsButtonDown = input.IsButtonDown,
			List = GryMod.Objectives and GryMod.Objectives.List
		}

		for k, v in pairs(Map.Tiles.Engine) do
			state.saved.Engine[k] = v
		end

		Map.Bounds.Compute = function() return boundsAround(10000) end
		Map._state.lastClose = -math.huge
		state.hooksRun = {}
		state.cache = {}
		state.slots = 0
		state.clock = 100
		state.frame = 1
	end,
	afterEach = function(state)
		pcall(function()
			local Map = GryMod.Map
			local Mini = GryMod.Minimap

			if Map.IsOpen() then
				Map._close()
			end

			pcall(hook.Remove, "GryMod_MapOpened", "gry map test")
			pcall(hook.Remove, "GryMod_MapClosed", "gry map test")
			pcall(hook.Remove, "GryMod_MapZoomed", "gry map test")
			pcall(hook.Remove, "GryMod_HUDEvent", "gry map test")

			Map.Bounds.Compute = state.saved.Compute
			Map._state.opened = state.saved.opened
			Map._state.lastClose = state.saved.lastClose
			Mini.Cache, Mini.Capture, Mini.Floors, Mini.Settings = state.saved.Cache, state.saved.Capture, state.saved.Floors, state.saved.Settings
			input.IsButtonDown = state.saved.IsButtonDown

			for k, v in pairs(state.saved.Engine) do
				Map.Tiles.Engine[k] = v
			end

			if GryMod.Objectives and state.saved.List then
				GryMod.Objectives.List = state.saved.List
			end

			Map.RemoveMarkerSource("gry map test")
			Map.Tiles.Reset()

			for name, value in pairs(state.convars) do
				GetConVar(name):SetString(value)
			end

			timer.Remove("GryMod big map trim")
		end)

		pcall(unstubDrawing, state)
	end,
	cases = {
		-- fails without Map.Open / IsOpen / Close (the file is missing), or when the panel, the hook or the capture priority are left behind
		{
			name = "Open opens the map (a popup panel that takes the mouse and not the keyboard, one Think hook, the capture priority), Close removes all of it",
			func = function(state)
				local Map = M()

				expect(Map.IsOpen()).to.beFalse()
				expect(Map.Open()).to.beTrue()
				expect(Map.IsOpen()).to.beTrue()

				local panel = Map._state.panel

				expect(IsValid(panel)).to.beTrue()
				expect(panel:IsMouseInputEnabled()).to.beTrue()
				-- the game goes on: the keyboard stays with the game, so the movement keys work while the map is open
				expect(panel:IsKeyboardInputEnabled()).to.beFalse()
				expect(hook.GetTable().Think["GryMod big map poll"] ~= nil).to.beTrue()
				-- the capture priority: the even frames are the map's
				expect(GryMod.Minimap.Capture.MayCapture("gen", 2000000)).to.beFalse()
				expect(GryMod.Minimap.Capture.MayCapture("gen", 2000001)).to.beTrue()

				expect(Map.Close()).to.beTrue()
				expect(Map.IsOpen()).to.beFalse()
				expect(IsValid(panel)).to.beFalse()
				expect(hook.GetTable().Think["GryMod big map poll"]).to.beNil()
				expect(GryMod.Minimap.Capture.MayCapture("gen", 2000000)).to.beTrue()
				-- the tiles are forgotten a minute later, not at once
				expect(timer.Exists("GryMod big map trim")).to.beTrue()

				Map.Open()
				expect(timer.Exists("GryMod big map trim")).to.beFalse()
				Map.Close()
			end
		},
		-- fails when Toggle does not follow the state
		{
			name = "Toggle opens a closed map and closes an open one",
			func = function()
				local Map = M()

				Map.Toggle()
				expect(Map.IsOpen()).to.beTrue()
				Map.Toggle()
				expect(Map.IsOpen()).to.beFalse()
			end
		},
		-- fails when the hooks are not run, or run twice
		{
			name = "GryMod_MapOpened and GryMod_MapClosed run once each, and opening an open map or closing a closed one runs nothing",
			func = function(state)
				local Map = M()
				local opened, closed = 0, 0

				hook.Add("GryMod_MapOpened", "gry map test", function() opened = opened + 1 end)
				hook.Add("GryMod_MapClosed", "gry map test", function() closed = closed + 1 end)

				Map.Open()
				Map.Open()
				expect(opened).to.equal(1)
				Map.Close()
				Map.Close()
				expect(closed).to.equal(1)
			end
		},
		-- fails when a listener that raises stops the map from opening
		{
			name = "a listener of GryMod_MapOpened that raises does not keep the map from opening",
			func = function()
				local Map = M()

				hook.Add("GryMod_MapOpened", "gry map test", function() error("listener exploded") end)

				local ok = pcall(Map.Open)

				expect(ok).to.beTrue()
				expect(Map.IsOpen()).to.beTrue()
				Map.Close()
			end
		},
		-- fails when the switch does not stop the map
		{
			name = "with gry_map_enable 0 the map does not open: false and a reason, and no hook runs",
			func = function()
				local Map = M()
				local ran = 0

				GetConVar("gry_map_enable"):SetString("0")
				hook.Add("GryMod_MapOpened", "gry map test", function() ran = ran + 1 end)

				local ok, why = Map.Open()

				expect(ok).to.beFalse()
				expect(type(why)).to.equal("string")
				expect(Map.IsOpen()).to.beFalse()
				expect(ran).to.equal(0)
			end
		},
		-- fails when the map is not opened by the same HUD event as every other effect
		{
			name = "the HUD events map_open and map_close exist and do the work; GryMod_HUDEvent tells about them",
			func = function()
				local Map = M()
				local seen = {}
				local names = {}

				for _, name in ipairs(GryMod.API.ListHUDEvents()) do
					names[name] = true
				end

				expect(names.map_open).to.beTrue()
				expect(names.map_close).to.beTrue()

				hook.Add("GryMod_HUDEvent", "gry map test", function(name) seen[#seen + 1] = name end)

				expect(GryMod.API.HUDEvent("map_open")).to.beTrue()
				expect(Map.IsOpen()).to.beTrue()
				expect(GryMod.API.HUDEvent("map_close")).to.beTrue()
				expect(Map.IsOpen()).to.beFalse()

				expect(seen[1]).to.equal("map_open")
				expect(seen[2]).to.equal("map_close")
			end
		},
		-- fails when the first opening is not automatic or the later ones do not use the last zoom
		{
			name = "the first opening of a map session uses the automatic zoom (a 4000 m map gives 5), the closing saves the zoom, a later opening uses the saved one",
			func = function()
				local Map = M()
				local half = 4000 / 0.01905 / 2

				Map.Bounds.Compute = function() return boundsAround(half) end
				Map._state.opened = false
				-- the saved zoom must not matter at the first opening
				GetConVar("gry_map_zoom"):SetString("2")

				Map.Open()
				expect(Map.GetZoom()).to.aboutEqual(5, 0.01)
				Map.Close()

				-- closing saved the zoom the map had
				expect(tonumber(GetConVar("gry_map_zoom"):GetString())).to.aboutEqual(5, 0.01)

				GetConVar("gry_map_zoom"):SetString("2.5")
				Map.Open()
				expect(Map.GetZoom()).to.aboutEqual(2.5, 0.001)
				Map.Close()
			end
		},
		-- fails when the pan is kept between two openings
		{
			name = "every opening is centred on the player: a pan made in one opening is gone at the next, the zoom is kept",
			func = function()
				local Map = M()
				local p = playerPos()

				Map._state.opened = true
				GetConVar("gry_map_zoom"):SetString("4")
				Map.Open()

				local view = Map._state.view

				expect(view.cx).to.aboutEqual(p.x, 0.01)
				expect(view.cy).to.aboutEqual(p.y, 0.01)

				-- drag the picture
				Map.PressStart(MOUSE_LEFT, view.x + 10, view.y + 10)
				Map.DragMove(view.x + 200, view.y + 150)
				Map.PressEnd(MOUSE_LEFT, view.x + 200, view.y + 150)
				expect(math.abs(view.cx - p.x) > 1 or math.abs(view.cy - p.y) > 1).to.beTrue()
				Map.Close()

				Map.Open()
				view = Map._state.view
				expect(view.cx).to.aboutEqual(p.x, 0.01)
				expect(view.cy).to.aboutEqual(p.y, 0.01)
				expect(view.zoom).to.aboutEqual(4, 0.001)
				Map.Close()
			end
		},
		-- fails when the wheel zooms toward the centre
		{
			name = "the wheel zooms toward the mouse: the world point under the cursor stays under it, the zoom steps like the original's and GryMod_MapZoomed says it",
			func = function()
				local Map = M()
				local Frame = Map.Frame
				local zoomed = {}

				Map._state.opened = true
				GetConVar("gry_map_zoom"):SetString("1")
				hook.Add("GryMod_MapZoomed", "gry map test", function(z) zoomed[#zoomed + 1] = z end)
				Map.Open()

				local view = Map._state.view
				local mx, my = view.x + view.w * 0.8, view.y + view.h * 0.3
				local wx, wy = Frame.ToWorld(view, mx, my)

				expect(Map.Wheel(mx, my, 1)).to.beTrue()
				expect(view.zoom).to.aboutEqual(1.10, 1e-9)

				local sx, sy = Frame.ToScreen(view, wx, wy)

				expect(sx).to.aboutEqual(mx, 1e-6)
				expect(sy).to.aboutEqual(my, 1e-6)

				-- several notches: still under the cursor (the bounds are far enough here), and the hook told each zoom
				for _ = 1, 4 do
					Map.Wheel(mx, my, 1)
				end

				sx, sy = Frame.ToScreen(view, wx, wy)
				expect(sx).to.aboutEqual(mx, 1e-3)
				expect(sy).to.aboutEqual(my, 1e-3)
				expect(#zoomed).to.equal(5)
				expect(zoomed[#zoomed]).to.equal(view.zoom)

				-- out again to 1: at the limit nothing more happens and no hook runs
				for _ = 1, 20 do
					Map.Wheel(mx, my, -1)
				end

				expect(view.zoom).to.equal(1)
				local count = #zoomed

				expect(Map.Wheel(mx, my, -1)).to.beFalse()
				expect(#zoomed).to.equal(count)
				Map.Close()
			end
		},
		-- fails when a wheel outside the window zooms toward the cursor, or a wheel on a closed map does anything
		{
			name = "a wheel with the cursor outside the window zooms toward the middle; a wheel on a closed map does nothing",
			func = function()
				local Map = M()

				expect(Map.Wheel(10, 10, 1)).to.beFalse()

				Map._state.opened = true
				GetConVar("gry_map_zoom"):SetString("1")
				Map.Open()

				local view = Map._state.view
				local cx, cy = view.cx, view.cy

				expect(Map.Wheel(2, 2, 1)).to.beTrue()
				expect(view.cx).to.aboutEqual(cx, 1e-6)
				expect(view.cy).to.aboutEqual(cy, 1e-6)
				Map.Close()
			end
		},
		-- fails when a drag button does not pan, or the middle one does not zoom
		{
			name = "the left and the right buttons pan, the middle one zooms while the mouse goes up and down (up zooms in), a press outside the window starts nothing",
			func = function()
				local Map = M()

				Map._state.opened = true
				GetConVar("gry_map_zoom"):SetString("3")
				Map.Open()

				local view = Map._state.view
				local x, y = view.x + view.w / 2, view.y + view.h / 2

				expect(Map.PressStart(MOUSE_LEFT, x, y)).to.equal("pan")
				Map.PressEnd(MOUSE_LEFT, x, y)
				expect(Map.PressStart(MOUSE_RIGHT, x, y)).to.equal("pan")
				Map.PressEnd(MOUSE_RIGHT, x, y)
				expect(Map.PressStart(MOUSE_LEFT, 1, 1)).to.beNil()
				expect(Map.PressStart(MOUSE_RIGHT, view.x + view.w + 50, y)).to.beNil()

				-- the middle button: the mouse moves up by 20 pixels: 0.6 more zoom
				expect(Map.PressStart(MOUSE_MIDDLE, x, y)).to.equal("zoom")
				Map.DragMove(x, y - 20)
				expect(view.zoom).to.aboutEqual(3.6, 1e-6)
				Map.DragMove(x, y + 20)
				expect(view.zoom).to.aboutEqual(2.4, 1e-6)
				Map.PressEnd(MOUSE_MIDDLE, x, y)

				-- no button down: a move changes nothing
				expect(Map.DragMove(x + 50, y + 50)).to.beFalse()
				Map.Close()
			end
		},
		-- fails when the pan can leave the bounds
		{
			name = "a drag stops at the bounds: the window never shows anything outside them, and a drag back works at once",
			func = function()
				local Map = M()

				Map._state.opened = true
				GetConVar("gry_map_zoom"):SetString("2")
				Map.Open()

				local view = Map._state.view
				local x, y = view.x + view.w / 2, view.y + view.h / 2

				Map.PressStart(MOUSE_LEFT, x, y)
				Map.DragMove(x + 100000, y + 100000)

				local minx, maxx, miny, maxy = Map.Frame.View(view)

				expect(minx >= view.x0 - 1e-6).to.beTrue()
				expect(maxx <= view.x1 + 1e-6).to.beTrue()
				expect(miny >= view.y0 - 1e-6).to.beTrue()
				expect(maxy <= view.y1 + 1e-6).to.beTrue()

				local before = view.cy

				Map.DragMove(x + 100000 - 30, y + 100000)
				expect(view.cy ~= before).to.beTrue()
				Map.PressEnd(MOUSE_LEFT, x, y)
				Map.Close()
			end
		},
		-- fails when the done button does not close the map
		{
			name = "a click on the done button closes the map: a press and a release on it",
			func = function(state)
				local Map = M()

				stubDrawing(state)
				Map.Open()

				-- the button is placed by the first frame drawn
				local panel = Map._state.panel

				panel:Paint(ScrW(), ScrH())

				local rect = Map._state.doneRect

				expect(rect ~= nil).to.beTrue()
				expect(Map.PressStart(MOUSE_LEFT, rect.x + 2, rect.y + 2)).to.equal("done")
				Map.PressEnd(MOUSE_LEFT, rect.x + 2, rect.y + 2)
				expect(Map.IsOpen()).to.beFalse()
			end
		},
		-- fails when the close conditions are not polled (the switch, the key)
		{
			name = "the Think hook closes the map when the switch goes off, and when the key goes down again (not when it was already down at the opening)",
			func = function(state)
				local Map = M()
				local poll

				-- the key is read by the stand-in input
				local down = {}

				input.IsButtonDown = function(code) return down[code] == true end

				local code = Map.Key.Effective()

				expect(code > 0).to.beTrue()

				down[code] = true -- the key that opened the map is still down
				Map.Open()
				poll = hook.GetTable().Think["GryMod big map poll"]
				poll()
				expect(Map.IsOpen()).to.beTrue()

				down[code] = false
				poll()
				expect(Map.IsOpen()).to.beTrue()

				down[code] = true
				poll()
				expect(Map.IsOpen()).to.beFalse()

				-- the switch
				down[code] = false
				Map.Open()
				poll = hook.GetTable().Think["GryMod big map poll"]
				GetConVar("gry_map_enable"):SetString("0")
				poll()
				expect(Map.IsOpen()).to.beFalse()
			end
		},
		-- fails when the key that closed the map opens it again in the same moment
		{
			name = "the key press that comes right after a close does not open the map again; a press a moment later does; a release does nothing",
			func = function()
				local Map = M()

				Map.Open()
				Map.Close()

				Map.KeyPress(true)
				expect(Map.IsOpen()).to.beFalse()

				-- a quarter of a second later (the guard is over)
				Map._state.lastClose = -math.huge
				Map.KeyPress(false)
				expect(Map.IsOpen()).to.beFalse()
				Map.KeyPress(true)
				expect(Map.IsOpen()).to.beTrue()
				Map.Close()
			end
		},
		-- fails when the default key is not M or a key of the addon can be taken
		{
			name = "the key: M by default, the setting gry_map_key is saved, Escape is refused, and the console command gry_map toggles",
			func = function()
				local Map = M()
				local key = Map.Key

				expect(GetConVar("gry_map_key") ~= nil).to.beTrue()
				expect(GetConVar("gry_map_key"):IsFlagSet(FCVAR_ARCHIVE)).to.beTrue()

				if key.Chosen() == 0 then
					expect(key.Effective()).to.equal(KEY_M)
				end

				expect(key.SetKey(KEY_ESCAPE)).to.beFalse()
				expect(concommand.GetTable().gry_map ~= nil).to.beTrue()
			end
		},
		-- fails when third parties cannot add markers, or the objectives are not on the map
		{
			name = "a marker source is collected with the objectives: the API adds and removes sources, an active objective is a marker, a done one only when asked",
			func = function(state)
				local Map = M()

				expect(Map.AddMarkerSource("gry map test", function()
					return {{pos = Vector(1, 2, 3), type = 7, id = "mate"}}
				end)).to.beTrue()

				GryMod.Objectives.List = function()
					return {
						{id = "a", title = "Active one", primary = true, main = true, state = "active", pos = Vector(10, 20, 0), radar = true},
						{id = "b", title = "Done one", primary = false, main = false, state = "done", pos = Vector(30, 40, 0), radar = true}
					}
				end

				local sources, nSources, objectives, nObjectives = Map.CollectMarkers()

				expect(nObjectives).to.equal(1)
				expect(objectives[1].label).to.equal("Active one")
				expect(objectives[1].main).to.beTrue()
				expect(nSources >= 1).to.beTrue()

				local found = false

				for i = 1, nSources do
					found = found or sources[i].id == "mate"
				end

				expect(found).to.beTrue()

				GetConVar("gry_map_finished"):SetString("1")
				_, _, objectives, nObjectives = Map.CollectMarkers()
				expect(nObjectives).to.equal(2)
				expect(objectives[2].finished).to.beTrue()

				expect(Map.RemoveMarkerSource("gry map test")).to.beTrue()
			end
		},
		-- one frame of drawing against recorders -------------------------------------------------------------------------------------------
		{
			-- fails when a frame raises (nil field, wrong name), draws no tile, no grid, no player, or leaves the scissor on
			name = "one frame: the dimmed screen, the tile of the store at the player's place, the grid (9 + 9 lines), the player's arrow and the frame; the scissor is switched off at the end and the map stays open",
			func = function(state)
				local Map = M()
				local Mini = GryMod.Minimap
				local Tiles = Map.Tiles
				local Pyramid = Map.Pyramid

				-- stand-ins as in tiles_test.lua
				Mini.Cache = {Has = function() return false end, IsEmpty = function() return false end, Path = function() return "x" end}
				Mini.Capture = {MayCapture = function() return true end, RenderTo = function() return true end}
				Mini.Floors = {Outside = function() return LEVEL end}
				Mini.Settings = setmetatable({TileRes = function() return 1024 end}, {__index = state.saved.Settings})
				Tiles.Engine.RealTime = function() return 1 end -- an arrival long ago: no look over the tile
				Tiles.Engine.FrameNumber = function() return 10 end
				Tiles.Engine.NewSlot = function(res, index)
					return {rt = {}, pic = {mat = "SLOT_MAT_" .. index, fade = "SLOT_FADE_" .. index}}
				end
				Tiles.Reset()

				Map._state.opened = true
				GetConVar("gry_map_zoom"):SetString("1")
				Map.Open()

				local view = Map._state.view
				local p = playerPos()
				local target = Pyramid.Target(Map.Frame.Scale(view), nil)
				local T = Pyramid.TileUnits(1024, target, 0.01905)
				local tx, ty = math.floor(p.x / T), math.floor(p.y / T)

				-- the tile under the player is in the store
				Tiles.Begin()
				Tiles.SetPlan({{ppm = target, tx = tx, ty = ty, d = 0}}, 1)
				Tiles.Step(1)
				expect(Tiles.Has(target, tx, ty)).to.beTrue()

				stubDrawing(state)

				local panel = Map._state.panel
				local ok, err = pcall(panel.Paint, panel, ScrW(), ScrH())

				expect(ok).to.beTrue()
				expect(Map.IsOpen()).to.beTrue()

				-- the tile: drawn with the slot's own opaque material
				local quads = callsOf("surface.DrawTexturedRectUV")

				expect(#quads >= 1).to.beTrue()

				local materials = callsOf("surface.SetMaterial")
				local usedSlot = false

				for _, c in ipairs(materials) do
					usedSlot = usedSlot or c[2] == "SLOT_MAT_1"
				end

				expect(usedSlot).to.beTrue()

				-- the grid: nine lines each way, and the 16 labels are texts (some may be out of the window at a large zoom: none at zoom 1)
				expect(#callsOf("surface.DrawLine") >= 18).to.beTrue()

				local texts = {}

				for _, c in ipairs(callsOf("draw.SimpleText")) do
					texts[tostring(c[2])] = true
				end

				for _, label in ipairs({"A", "H", "1", "8", "STRATEGIC MAP", "DONE"}) do
					expect(texts[label]).to.beTrue()
				end

				-- the player's arrow is a polygon, the scissor is on for the window and off at the end
				expect(#callsOf("surface.DrawPoly") >= 1).to.beTrue()

				local scissors = callsOf("render.SetScissorRect")

				expect(#scissors >= 2).to.beTrue()
				expect(scissors[1][6]).to.equal(true)
				expect(scissors[#scissors][6]).to.equal(false)
				Map.Close()
			end
		},
		-- fails when the grid switch is not read
		{
			name = "with gry_map_grid 0 the frame draws no grid lines and no letters or numbers",
			func = function(state)
				local Map = M()

				GetConVar("gry_map_grid"):SetString("0")
				Map._state.opened = true
				Map.Open()
				stubDrawing(state)

				local panel = Map._state.panel

				panel:Paint(ScrW(), ScrH())

				local texts = {}

				for _, c in ipairs(callsOf("draw.SimpleText")) do
					texts[tostring(c[2])] = true
				end

				expect(texts["A"]).to.beNil()
				expect(texts["STRATEGIC MAP"]).to.beTrue()
				Map.Close()
			end
		},
		-- fails when a tile that is loading does not show its loading look over the coarse picture, or the arrival's tear
		{
			name = "a tile that waits is drawn over the coarse picture of its place with the veil and six bands; when it arrives it tears (bands plus two additive copies); later it is plain",
			func = function(state)
				local Map = M()
				local Mini = GryMod.Minimap
				local Tiles = Map.Tiles
				local Pyramid = Map.Pyramid
				local now = RealTime()

				-- a small map (4000 units): the zoom of the window needs a fine level, so a coarser tile can stand in
				Map.Bounds.Compute = function() return boundsAround(2000) end

				state.cache = {}
				Mini.Cache = {
					Has = function(tile) return tile.ppm == 2 and state.cache[cacheKey(tile.ppm, tile.tx, tile.ty)] ~= nil and tile.level == LEVEL.id end,
					IsEmpty = function() return false end,
					Path = function(tile) return "t_" .. tile.tx .. "_" .. tile.ty end
				}
				Mini.Capture = {MayCapture = function() return true end, RenderTo = function() return true end}
				Mini.Floors = {Outside = function() return LEVEL end}
				Mini.Settings = setmetatable({TileRes = function() return 1024 end}, {__index = state.saved.Settings})
				Tiles.Engine.RealTime = function() return RealTime() end
				Tiles.Engine.FrameNumber = function() return 10 end
				Tiles.Engine.NewSlot = function(res, index)
					return {rt = {}, pic = {mat = "SLOT_MAT_" .. index, fade = "SLOT_FADE_" .. index}}
				end
				Tiles.Engine.LoadMaterial = function(path)
					return {path = path, IsError = function() return false end, fakeMat = path}
				end
				Tiles.Reset()

				Map._state.opened = true
				GetConVar("gry_map_zoom"):SetString("1")
				Map.Open()

				local view = Map._state.view
				local p = playerPos()
				local target = Pyramid.Target(Map.Frame.Scale(view), nil)

				expect(target > 2).to.beTrue()

				local T = Pyramid.TileUnits(1024, target, 0.01905)
				local tx, ty = math.floor(p.x / T), math.floor(p.y / T)
				local coarseT = Pyramid.TileUnits(1024, 2, 0.01905)

				-- the coarse tile of that place is in the minimap's cache
				state.cache[cacheKey(2, math.floor(p.x / coarseT), math.floor(p.y / coarseT))] = "file"

				Tiles.Begin()
				Tiles.SetPlan({{ppm = target, tx = tx, ty = ty, d = 0}}, now)
				stubDrawing(state)

				local panel = Map._state.panel

				-- 1. waiting
				panel:Paint(ScrW(), ScrH())

				-- the veil of the glitch is black with alpha 77
				local colours = callsOf("surface.SetDrawColor")
				local sawVeil = false

				for _, c in ipairs(colours) do
					sawVeil = sawVeil or (c[2] == 0 and c[3] == 0 and c[4] == 0 and c[5] == 77)
				end

				expect(sawVeil).to.beTrue()
				-- the coarse picture's own material (loaded through the map's table) is the one drawn as bands
				local bands = 0

				for _, c in ipairs(callsOf("surface.SetMaterial")) do
					if type(c[2]) == "table" and c[2].fakeMat then
						bands = bands + 1
					end
				end

				expect(bands >= 7).to.beTrue() -- the plain base and six bands

				-- 2. arrival: the tiles are made now (one a frame, the coarse ones of the window first), the look is "arrived" for a third of a second
				recorded = {}

				local frame = 100

				while not Tiles.Has(target, tx, ty) and frame < 120 do
					frame = frame + 1
					Tiles.Engine.FrameNumber = function() return frame end
					Tiles.Begin()
					Tiles.Step(RealTime())
				end

				expect(Tiles.Has(target, tx, ty)).to.beTrue()
				panel:Paint(ScrW(), ScrH())

				local additive = 0

				for _, c in ipairs(callsOf("render.OverrideBlend")) do
					if c[2] == true then
						additive = additive + 1
					end
				end

				-- the red copy and the cyan copy of the tile that just arrived (another tile made in the same frames tears too)
				expect(additive >= 2).to.beTrue()

				local slotQuads = 0

				for _, c in ipairs(callsOf("surface.SetMaterial")) do
					if type(c[2]) == "string" and string.find(c[2], "^SLOT_") then
						slotQuads = slotQuads + 1
					end
				end

				expect(slotQuads >= 8).to.beTrue()

				-- 3. later: the arrivals are old, nothing but the plain tiles
				for key, at in pairs(Tiles.Tracker().arrived) do
					Tiles.Tracker().arrived[key] = at - 5
				end

				recorded = {}
				panel:Paint(ScrW(), ScrH())

				for _, c in ipairs(callsOf("render.OverrideBlend")) do
					expect(c[2]).to.equal(false)
				end

				Map.Close()
			end
		},
		-- fails when an error inside the drawing leaves Paint (the engine would print it at every frame, with the cursor kept by a broken map)
		{
			name = "a frame that raises does not leave Paint: the error is reported once and the map is closed at the next frame",
			func = function(state)
				local Map = M()
				local realError = ErrorNoHalt
				local reported = 0

				ErrorNoHalt = function() reported = reported + 1 end
				Map.Open()
				stubDrawing(state)
				surface.DrawRect = function() error("draw exploded") end

				local panel = Map._state.panel
				local ok = pcall(panel.Paint, panel, ScrW(), ScrH())

				ErrorNoHalt = realError
				unstubDrawing(state)

				expect(ok).to.beTrue()
				expect(reported).to.equal(1)
				Map.Close()
			end
		},
		-- fails when the pyramid levels the map asks are not the minimap's
		{
			name = "the levels the map works with are the minimap's pyramid",
			func = function()
				local levels = GryMod.Map.Pyramid.Levels()

				for i, ppm in ipairs(PPM_LEVELS) do
					expect(levels[i]).to.equal(ppm)
				end
			end
		}
	}
}
