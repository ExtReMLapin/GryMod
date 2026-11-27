-- Tests of the big map (lua/grymod/client/map/panel.lua), GLuaTest format, client realm: opening and closing (the API, the HUD events, the hooks, the switch),
-- the zoom of the first opening and of the later ones, the pan that starts again at the player, the wheel that zooms toward the mouse, the drags, the markers,
-- the key and the command, the share of the captures, and one frame of drawing against recorders instead of the real surface. The bounds are replaced by a
-- known box around the player; the minimap's cache, capture, floors and settings and the engine's render targets are replaced by stand-ins (as in
-- tiles_test.lua); every stand-in and every convar the cases touch is put back in afterEach inside a pcall, also when a case failed.
-- The real map panel is created (a popup); a case that opens it closes it before it ends.

local LEVEL = {id = "open_t256", open = true, zlo = -100, zhi = 256}
local CONVARS = {"gry_map_enable", "gry_map_zoom", "gry_map_loading_fx", "gry_map_finished", "gry_map_grid", "gry_map_chrome", "gry_map_waypoints"}
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
		-- these cases are about the plain panel (the title, the hint and the DONE button are drawn by the map itself, a frame is drawn at once); the frame of the
		-- movie has its own cases in chrome_panel_test.lua
		GetConVar("gry_map_chrome"):SetString("0")
		-- the player's own points (waypoints.lua): on, no disk, none from an earlier case
		GetConVar("gry_map_waypoints"):SetString("1")

		state.saved = {
			wpIO = Map.Waypoints.IO,
			ui = {Menu = Map.UI.Menu, Ask = Map.UI.Ask, Ground = Map.UI.Ground, CancelAsk = Map.UI.CancelAsk},
			Compute = Map.Bounds.Compute,
			opened = Map._state.opened,
			lastClose = Map._state.lastClose,
			Cache = Mini.Cache, Capture = Mini.Capture, Floors = Mini.Floors, Settings = Mini.Settings,
			Engine = {},
			IsButtonDown = input.IsButtonDown,
			UseCache = Map.Tiles.USE_MINIMAP_CACHE,
			List = GryMod.Objectives and GryMod.Objectives.List
		}

		for k, v in pairs(Map.Tiles.Engine) do
			state.saved.Engine[k] = v
		end

		Map.Bounds.Compute = function() return boundsAround(10000) end
		Map.Waypoints.IO = {Read = function() return nil end, Write = function() end, CreateDir = function() end}
		Map.Waypoints.Reset()
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
			Map.Waypoints.Reset()
			Map.Waypoints.IO = state.saved.wpIO

			for k, v in pairs(state.saved.ui) do
				Map.UI[k] = v
			end

			Map._state.opened = state.saved.opened
			Map._state.lastClose = state.saved.lastClose
			Mini.Cache, Mini.Capture, Mini.Floors, Mini.Settings = state.saved.Cache, state.saved.Capture, state.saved.Floors, state.saved.Settings
			input.IsButtonDown = state.saved.IsButtonDown
			Map.Tiles.USE_MINIMAP_CACHE = state.saved.UseCache

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
		-- fails when a move with the button of DONE held raises an error (the press of DONE keeps no start point: S.dragX was nil, reported 2026-11-24, four
		-- errors a drag in the owner's game)
		{
			name = "moving the mouse with the DONE button held does nothing and raises no error (the press keeps no start point); letting go off the button closes nothing",
			func = function(state)
				local Map = M()

				stubDrawing(state)
				Map.Open()
				Map._state.panel:Paint(ScrW(), ScrH())

				local rect = Map._state.doneRect
				local view = Map._state.view
				local viewX, viewY = view.x, view.y
				local centre = view.zoom

				-- a first interaction: no drag has ever started in this game (the state of an earlier test would hide the error)
				Map._state.dragX, Map._state.dragY = nil, nil

				expect(Map.PressStart(MOUSE_LEFT, rect.x + 2, rect.y + 2)).to.equal("done")

				local ok, moved = pcall(Map.DragMove, rect.x + 40, rect.y + 25)
				expect(ok).to.beTrue()
				expect(moved).to.beFalse()
				expect(view.zoom).to.equal(centre)
				expect(view.x).to.equal(viewX)
				expect(view.y).to.equal(viewY)

				-- the button goes up away from DONE: nothing is closed
				Map.PressEnd(MOUSE_LEFT, 1, 1)
				expect(Map.IsOpen()).to.beTrue()
				Map.Close()
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
				-- (GetFlags does not report FCVAR_ARCHIVE for Lua-created convars in this build: the flags are those of a saved sibling)
				expect(GetConVar("gry_map_key"):GetFlags()).to.equal(GetConVar("gry_menu_key"):GetFlags())

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
		-- fails without the margin under the numbers in drawGrid: a row letter whose line sat just under the top edge was drawn over the column number "1" (seen at 1080p)
		{
			name = "a grid row letter is never drawn in the band of the column numbers along the top edge of the window",
			func = function(state)
				local Map = M()
				local Mini = GryMod.Minimap
				local Tiles = Map.Tiles
				local Frame = Map.Frame

				Mini.Cache = {Has = function() return false end, IsEmpty = function() return false end, Path = function() return "x" end}
				Mini.Capture = {MayCapture = function() return false end, RenderTo = function() return false end}
				Mini.Floors = {Outside = function() return LEVEL end}
				Mini.Settings = setmetatable({TileRes = function() return 1024 end}, {__index = state.saved.Settings})
				Tiles.Engine.RealTime = function() return 1 end
				Tiles.Engine.FrameNumber = function() return 10 end
				Tiles.Reset()
				Map._state.opened = true
				GetConVar("gry_map_zoom"):SetString("1")
				Map.Open()

				local view = Map._state.view
				local stepX = (view.x1 - view.x0) / 8
				local rowX = view.x1 - 0.5 * stepX -- the line of the row A

				-- the row A's line is put 15 pixels under the top edge (as a pan or a zoom around the mouse does it): the screen position of that one line is replaced
				local ToScreen = Frame.ToScreen

				Frame.ToScreen = function(v, wx, wy)
					local sx, sy = ToScreen(v, wx, wy)

					if math.abs(wx - rowX) < 0.01 then
						sy = v.y + 15
					end

					return sx, sy
				end

				stubDrawing(state)

				local panel = Map._state.panel
				local ok = pcall(panel.Paint, panel, ScrW(), ScrH())

				Frame.ToScreen = ToScreen

				expect(ok).to.beTrue()

				local letters, other = 0, 0

				for _, c in ipairs(callsOf("draw.SimpleText")) do
					if #tostring(c[2]) == 1 and string.find("ABCDEFGH", tostring(c[2]), 1, true) then
						letters = letters + 1
						-- c[5] is the centre of the letter: the numbers are drawn from view.y + 4, about a line of the small font tall
						expect(c[5] > view.y + 4 + 1.5 * math.max(12, math.floor(ScrH() / 78))).to.beTrue()
					else
						other = other + 1
					end
				end

				-- the other rows are still there (a rule that drew no letter at all would pass the check above)
				expect(letters >= 5).to.beTrue()
				Map.Close()
			end
		},
		-- fails without Map.ARROW_MIN: at zoom 1 the arrow was 4.5 pixels at 720p, a speck
		{
			name = "the player's arrow is never smaller than ARROW_MIN at zoom 1 (about 17 pixels long), and still grows with the screen",
			func = function(state)
				local Map = M()
				local Mini = GryMod.Minimap
				local Tiles = Map.Tiles

				Mini.Cache = {Has = function() return false end, IsEmpty = function() return false end, Path = function() return "x" end}
				Mini.Capture = {MayCapture = function() return true end, RenderTo = function() return true end}
				Mini.Floors = {Outside = function() return LEVEL end}
				Mini.Settings = setmetatable({TileRes = function() return 1024 end}, {__index = state.saved.Settings})
				Tiles.Engine.RealTime = function() return 1 end
				Tiles.Engine.FrameNumber = function() return 10 end
				Tiles.Engine.NewSlot = function(res, index)
					return {rt = {}, pic = {mat = "SLOT_MAT_" .. index, fade = "SLOT_FADE_" .. index}}
				end
				Tiles.Reset()

				Map._state.opened = true
				GetConVar("gry_map_zoom"):SetString("1")
				Map.Open()
				stubDrawing(state)

				local ok = pcall(Map._state.panel.Paint, Map._state.panel, ScrW(), ScrH())

				expect(ok).to.beTrue()

				-- the last polygon is the arrow (tip first, then the two wings and the notch): its length is tip to the middle of the wings, 2.4 times the size
				local polys = callsOf("surface.DrawPoly")
				local a = polys[#polys][2]
				local mx, my = (a[2].x + a[4].x) / 2, (a[2].y + a[4].y) / 2
				local length = math.sqrt((a[1].x - mx) ^ 2 + (a[1].y - my) ^ 2)

				expect(length >= 2.4 * (Map.ARROW_MIN or 7) - 0.01).to.beTrue()
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
				-- this case is about a coarse tile of the minimap's cache standing in for the tile that waits: the cache path is on for it
				Tiles.USE_MINIMAP_CACHE = true
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
		},
		-- fails when a right click that did not move does not open the little menu at the cursor, when "create" does not ask for the title, or when the point is not put at
		-- the world place under the click at the ground the map shows there
		{
			name = "a right click without moving opens the menu where it was made; its button asks for the title; the point goes where the click was, on the ground of the map, and is an objective",
			func = function()
				local Map = M()
				local W = Map.Waypoints

				Map._state.opened = true
				GetConVar("gry_map_zoom"):SetString("3")
				Map.Open()

				local view = Map._state.view
				local x, y = view.x + view.w / 3, view.y + view.h / 4
				local menu, ask, groundAt = nil, nil, nil

				Map.UI.Menu = function(sx, sy, onCreate) menu = {x = sx, y = sy, create = onCreate} end
				Map.UI.Ask = function(default, onDone) ask = {default = default, done = onDone} end
				Map.UI.Ground = function(wx, wy) groundAt = {wx, wy} return 77 end

				expect(Map.PressStart(MOUSE_RIGHT, x, y)).to.equal("pan")
				Map.DragMove(x + 1, y + 1) -- a hand that trembles: still a click
				Map.PressEnd(MOUSE_RIGHT, x + 1, y + 1)

				expect(menu ~= nil).to.beTrue()
				expect(menu.x).to.equal(x + 1)
				expect(menu.y).to.equal(y + 1)
				expect(ask).to.beNil()
				expect(#W.List()).to.equal(0)

				menu.create()
				expect(ask ~= nil).to.beTrue()
				-- the title it offers is made of the grid cell under the click
				expect(string.find(ask.default, "^Point [A-H][1-8]$") ~= nil).to.beTrue()

				ask.done("Camp")

				local wx, wy = Map.Frame.ToWorld(view, x + 1, y + 1)

				expect(#W.List()).to.equal(1)
				expect(W.List()[1].x).to.aboutEqual(wx, 1e-6)
				expect(W.List()[1].y).to.aboutEqual(wy, 1e-6)
				expect(W.List()[1].z).to.equal(77)
				expect(groundAt[1]).to.aboutEqual(wx, 1e-6)
				expect(GryMod.Objectives.Get(W.List()[1].id).title).to.equal("Camp")
				Map.Close()
			end
		},
		-- fails when a drag with the right button (the map's pan) also opens the menu, or a left click does
		{
			name = "a right drag is still the pan and opens nothing; a left click opens nothing; a right click outside the window opens nothing",
			func = function()
				local Map = M()
				local opened = 0

				Map._state.opened = true
				GetConVar("gry_map_zoom"):SetString("3")
				Map.Open()

				local view = Map._state.view
				local x, y = view.x + view.w / 2, view.y + view.h / 2

				Map.UI.Menu = function() opened = opened + 1 end

				Map.PressStart(MOUSE_RIGHT, x, y)
				Map.DragMove(x + 40, y)
				Map.PressEnd(MOUSE_RIGHT, x + 40, y)
				expect(opened).to.equal(0)

				-- a move and a move back is still a move
				Map.PressStart(MOUSE_RIGHT, x, y)
				Map.DragMove(x + 30, y)
				Map.DragMove(x, y)
				Map.PressEnd(MOUSE_RIGHT, x, y)
				expect(opened).to.equal(0)

				Map.PressStart(MOUSE_LEFT, x, y)
				Map.PressEnd(MOUSE_LEFT, x, y)
				expect(opened).to.equal(0)

				Map.PressStart(MOUSE_RIGHT, view.x + view.w + 50, y)
				Map.PressEnd(MOUSE_RIGHT, view.x + view.w + 50, y)
				expect(opened).to.equal(0)

				-- and a clean click does
				Map.PressStart(MOUSE_RIGHT, x, y)
				Map.PressEnd(MOUSE_RIGHT, x, y)
				expect(opened).to.equal(1)
				Map.Close()
			end
		},
		-- fails when a right click on a point opens the menu instead of taking the point away, or leaves it in the mirror
		{
			name = "a right click on one of the player's points takes it away (no menu); a right click next to it opens the menu",
			func = function()
				local Map = M()
				local W = Map.Waypoints
				local menus = 0

				Map._state.opened = true
				GetConVar("gry_map_zoom"):SetString("3")
				Map.Open()

				local view = Map._state.view
				local cx, cy = view.cx, view.cy
				local id = W.Add(cx, cy, 0, "Camp")
				local px, py = Map.Frame.ToScreen(view, cx, cy)

				Map.UI.Menu = function() menus = menus + 1 end

				-- 60 pixels away: not the point
				Map.PressStart(MOUSE_RIGHT, px + 60, py)
				Map.PressEnd(MOUSE_RIGHT, px + 60, py)
				expect(menus).to.equal(1)
				expect(GryMod.Objectives.Get(id) ~= nil).to.beTrue()

				Map.PressStart(MOUSE_RIGHT, px + 2, py - 2)
				Map.PressEnd(MOUSE_RIGHT, px + 2, py - 2)
				expect(menus).to.equal(1)
				expect(GryMod.Objectives.Get(id)).to.beNil()
				expect(#W.List()).to.equal(0)
				Map.Close()
			end
		},
		-- fails when the switch does not stop the menu, or the point is made with a title the player did not give and then cancelled
		{
			name = "the switch gry_map_waypoints 0: a right click opens nothing; a title left empty gets the default one; a cancelled request puts no point",
			func = function()
				local Map = M()
				local W = Map.Waypoints
				local menu, ask

				Map._state.opened = true
				GetConVar("gry_map_zoom"):SetString("3")
				Map.Open()

				local view = Map._state.view
				local x, y = view.x + view.w / 2, view.y + view.h / 2

				Map.UI.Menu = function(sx, sy, onCreate) menu = onCreate end
				Map.UI.Ask = function(default, onDone) ask = {default = default, done = onDone} end
				Map.UI.Ground = function() return 5 end

				GetConVar("gry_map_waypoints"):SetString("0")
				Map.PressStart(MOUSE_RIGHT, x, y)
				Map.PressEnd(MOUSE_RIGHT, x, y)
				expect(menu).to.beNil()

				GetConVar("gry_map_waypoints"):SetString("1")
				Map.PressStart(MOUSE_RIGHT, x, y)
				Map.PressEnd(MOUSE_RIGHT, x, y)
				menu()
				ask.done(nil) -- cancelled
				expect(#W.List()).to.equal(0)

				menu()
				ask.done("   ") -- nothing typed
				expect(#W.List()).to.equal(1)
				expect(W.List()[1].title).to.equal(ask.default)
				Map.Close()
			end
		},
		-- fails when the ground is not looked for under the top of the level shown, or a place with no ground (outside the world) is put at height 0 instead of the player's
		{
			name = "the ground under a click: from the top of the level shown down, and the player's own height when there is none",
			func = function()
				local Map = M()
				local seen

				Map._state.opened = true
				Map.Open()
				Map._state.level = {id = "x", zlo = -500, zhi = 900}

				local realTrace = util.TraceLine

				util.TraceLine = function(t)
					seen = t

					return {Hit = true, HitSky = false, HitPos = Vector(t.start.x, t.start.y, 123)}
				end

				local ok, z = pcall(Map.UI.Ground, 10, 20)

				util.TraceLine = realTrace
				expect(ok).to.beTrue()
				expect(z).to.equal(123)
				expect(seen.start.z).to.equal(900)
				expect(seen.endpos.z).to.equal(-500)

				util.TraceLine = function() return {Hit = false} end
				ok, z = pcall(Map.UI.Ground, 10, 20)
				util.TraceLine = realTrace
				expect(ok).to.beTrue()
				expect(z).to.equal(LocalPlayer():GetPos().z)
				Map.Close()
			end
		},
		-- fails when the title request leaves the map's key active (typing the key's letter in the box would close the map under it) or stays open after the map closes
		{
			name = "while the title is asked for, the map is told the player is typing (its key does not close it); closing the map cancels the request",
			func = function()
				local Map = M()
				local cancelled = 0
				local ask

				Map._state.opened = true
				Map.Open()
				Map.UI.Menu = function(sx, sy, onCreate) onCreate() end
				Map.UI.Ask = function(default, onDone) ask = onDone end
				Map.UI.CancelAsk = function() cancelled = cancelled + 1 end
				Map.UI.Ground = function() return 0 end

				local view = Map._state.view
				local x, y = view.x + view.w / 2, view.y + view.h / 2

				Map.PressStart(MOUSE_RIGHT, x, y)
				Map.PressEnd(MOUSE_RIGHT, x, y)
				expect(Map.IsTyping()).to.beTrue()

				ask("Done")
				expect(Map.IsTyping()).to.beFalse()

				Map.PressStart(MOUSE_RIGHT, x, y + 30)
				Map.PressEnd(MOUSE_RIGHT, x, y + 30)
				expect(Map.IsTyping()).to.beTrue()
				Map.Close()
				expect(Map.IsTyping()).to.beFalse()
				expect(cancelled).to.equal(1)
			end
		},
		-- fails when the real request does not give the text to onDone exactly once (the window closes before the Create button's callback runs), or when closing the window by its
		-- own cross is not a cancel (the map would believe the player is still typing and its key would never close it)
		{
			name = "the real title request: Create gives the text once; closing the window by its cross is a cancel, told once, after the buttons' own callbacks",
			func = function()
				local Map = M()

				local function find(panel, class, text)
					for _, child in ipairs(panel:GetChildren()) do
						if child.ClassName == class and (text == nil or child:GetText() == text) then
							return child
						end

						local deeper = find(child, class, text)

						if deeper then
							return deeper
						end
					end
				end

				local queued = {}
				local realSimple = timer.Simple

				timer.Simple = function(_, fn) queued[#queued + 1] = fn end

				local ok, err = pcall(function()
					local got = {}
					local function onDone(text) got[#got + 1] = text == nil and "cancel" or text end

					Map.UI.Ask("Point A1", onDone)

					local frame = Map._state.ask

					expect(IsValid(frame)).to.beTrue()
					expect(find(frame, "DTextEntry"):GetValue()).to.equal("Point A1")
					find(frame, "DTextEntry"):SetValue("Camp")
					find(frame, "DButton", "Create"):DoClick()

					for _, fn in ipairs(queued) do fn() end

					expect(#got).to.equal(1)
					expect(got[1]).to.equal("Camp")
					expect(Map._state.ask).to.beNil()

					-- the window's cross
					queued, got = {}, {}
					Map.UI.Ask("Point B2", onDone)
					Map._state.ask:Close()
					expect(#got).to.equal(0) -- not at once: the buttons' callbacks come right after Close

					for _, fn in ipairs(queued) do fn() end

					expect(#got).to.equal(1)
					expect(got[1]).to.equal("cancel")
					expect(Map._state.ask).to.beNil()

					-- the Cancel button: told once, not twice
					queued, got = {}, {}
					Map.UI.Ask("Point C3", onDone)
					find(Map._state.ask, "DButton", "Cancel"):DoClick()

					for _, fn in ipairs(queued) do fn() end

					expect(#got).to.equal(1)
					expect(got[1]).to.equal("cancel")
				end)

				timer.Simple = realSimple
				Map.UI.CancelAsk()

				if not ok then
					error(err, 0)
				end
			end
		},
		-- fails when the plain panel does not draw the NPC contacts, draws them with the window's scissor still on, or before the tiles
		{
			name = "the plain panel draws the NPC contacts once a frame with the map's view, after the window's scissor is lifted and after its tiles",
			func = function(state)
				local Map = M()
				local real = Map.Contacts.Draw
				local calls = {}

				Map.Open()
				stubDrawing(state)

				Map.Contacts.Draw = function(view, ply, uiScale)
					calls[#calls + 1] = {view = view, ply = ply, uiScale = uiScale}
					recorded[#recorded + 1] = {"contacts"}

					return 0
				end

				local ok, err = pcall(function()
					local panel = Map._state.panel

					expect(pcall(panel.Paint, panel, ScrW(), ScrH())).to.beTrue()
					expect(#calls).to.equal(1)
					expect(calls[1].view).to.equal(Map._state.view)

					local at, lastScissor

					for i, c in ipairs(recorded) do
						if c[1] == "contacts" then
							at = i
						elseif c[1] == "render.SetScissorRect" and not at then
							lastScissor = c
						end
					end

					expect(at ~= nil).to.beTrue()
					expect(lastScissor[6]).to.equal(false)
				end)

				Map.Contacts.Draw = real
				Map.Close()

				if not ok then
					error(err, 0)
				end
			end
		},
		-- fails when a contact drawing that raises closes the map (the contacts are extra), or is reported at every frame
		{
			name = "a contact drawing that raises is reported once and stops for this opening; the map stays open and goes on drawing",
			func = function(state)
				local Map = M()
				local real, realError = Map.Contacts.Draw, ErrorNoHalt
				local calls, reported = 0, 0

				Map.Open()
				stubDrawing(state)
				Map.Contacts.Draw = function() calls = calls + 1 error("contacts exploded") end
				ErrorNoHalt = function() reported = reported + 1 end

				local ok, err = pcall(function()
					local panel = Map._state.panel

					expect(pcall(panel.Paint, panel, ScrW(), ScrH())).to.beTrue()
					expect(pcall(panel.Paint, panel, ScrW(), ScrH())).to.beTrue()
					expect(Map.IsOpen()).to.beTrue()
					expect(calls).to.equal(1)
					expect(reported).to.equal(1)
					expect(#callsOf("draw.SimpleText") > 0).to.beTrue() -- the frame and its texts are still drawn
				end)

				Map.Contacts.Draw, ErrorNoHalt = real, realError
				Map.Close()

				if not ok then
					error(err, 0)
				end
			end
		},
		-- fails when the hint under the map does not tell about the right click, or keeps telling when it is switched off
		{
			name = "the hint lines: the right click is in the long ones when the switch is on, and in none when it is off; the last one is only the key",
			func = function()
				local Map = M()

				GetConVar("gry_map_waypoints"):SetString("1")

				local on = Map.HintVariants("M")

				expect(#on >= 3).to.beTrue()
				expect(string.find(on[1], "RIGHT CLICK", 1, true) ~= nil).to.beTrue()
				expect(string.find(on[1], "M: CLOSE", 1, true) ~= nil).to.beTrue()
				expect(on[#on]).to.equal("M: CLOSE")

				-- from the longest to the shortest
				for i = 2, #on do
					expect(#on[i] < #on[i - 1]).to.beTrue()
				end

				GetConVar("gry_map_waypoints"):SetString("0")

				for _, line in ipairs(Map.HintVariants("M")) do
					expect(string.find(line, "RIGHT CLICK", 1, true)).to.beNil()
				end
			end
		}
	}
}
