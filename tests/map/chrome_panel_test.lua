-- Tests of the big map drawn in the frame of the real PDA movie (panel.lua with gry_map_chrome 1, and chrome.lua), GLuaTest format, client realm. The panel_test.lua
-- cases are about the plain panel (they set the convar to 0); these are about the frame: the window that sits in the movie's own window, the content that is drawn
-- from inside the movie only where its opening mask has revealed it, the texts that now come from the movie (no title, no DONE drawn by the map), the DONE button of the
-- movie, the closing animation that goes on after the map is closed, the jammed look driven by GryMod_HUDStatus, the fall back on the plain panel, the theme colours.
-- The Flash player's drawing is replaced by a function that runs the drawBefore hooks as the real drawing does (no picture is made), the drawing functions of the
-- engine by recorders, the minimap's cache, capture, floors and settings and the engine's render targets by stand-ins (as in panel_test.lua). Everything a case changes
-- (the stand-ins, the convars, the HUD theme, the HUD status, a closing animation that was left) is put back in afterEach inside a pcall, also when a case failed.

local LEVEL = {id = "open_t256", open = true, zlo = -100, zhi = 256}
local CONVARS = {"gry_map_enable", "gry_map_zoom", "gry_map_loading_fx", "gry_map_finished", "gry_map_grid", "gry_map_chrome"}
local STEP = 1 / 30

local function M()
	local map = GryMod and GryMod.Map

	expect(map ~= nil and map.Open ~= nil and map.Chrome ~= nil).to.beTrue()

	return map
end

local function playerPos()
	return LocalPlayer():GetPos()
end

local function boundsAround(half)
	local p = playerPos()

	return {x0 = p.x - half, x1 = p.x + half, y0 = p.y - half, y1 = p.y + half, source = "test"}
end

local recorded
local flashDraws

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

local function textsDrawn()
	local texts = {}

	for _, c in ipairs(callsOf("draw.SimpleText")) do
		texts[tostring(c[2])] = true
	end

	return texts
end

-- the Flash player's drawing: it draws nothing, runs the drawBefore hooks of the visible clips as the real one does, records its calls
local function stubFlashDraw(result)
	flashDraws = {}

	GryMod.Flash.Draw = function(clip, x, y, scale)
		flashDraws[#flashDraws + 1] = {clip, x, y, scale}

		local function walk(c)
			if c.drawBefore then
				c.drawBefore()
			end

			for _, entry in ipairs(c:Entries()) do
				if entry.clip and entry.clip.visible then
					walk(entry.clip)
				end
			end
		end

		walk(clip)

		return result ~= false
	end
end

-- the stand-ins of the minimap and the render targets, as panel_test.lua makes them, and the tile under the player at the level the zoom needs
local function standIns(state)
	local Map = M()
	local Mini = GryMod.Minimap
	local Tiles = Map.Tiles

	Mini.Cache = {Has = function() return false end, IsEmpty = function() return false end, Path = function() return "x" end}
	Mini.Capture = {MayCapture = function() return true end, RenderTo = function() return true end, SetPriority = function() end}
	Mini.Floors = {Outside = function() return LEVEL end}
	Mini.Settings = setmetatable({TileRes = function() return 1024 end}, {__index = state.saved.Settings})
	Tiles.Engine.RealTime = function() return 1 end
	Tiles.Engine.FrameNumber = function() return 10 end
	Tiles.Engine.NewSlot = function(res, index)
		return {rt = {}, pic = {mat = "SLOT_MAT_" .. index, fade = "SLOT_FADE_" .. index}}
	end
	Tiles.Reset()
end

local function tileUnderPlayer()
	local Map = M()
	local view = Map._state.view
	local p = playerPos()
	local target = Map.Pyramid.Target(Map.Frame.Scale(view), nil)
	local T = Map.Pyramid.TileUnits(1024, target, 0.01905)
	local tx, ty = math.floor(p.x / T), math.floor(p.y / T)

	Map.Tiles.Begin()
	Map.Tiles.SetPlan({{ppm = target, tx = tx, ty = ty, d = 0}}, 1)
	Map.Tiles.Step(1)
end

-- the movie runs for `seconds` (the panel's own frame also advances it, by the time between two frames: nothing here)
local function run(seconds)
	local chrome = M()._state.chrome

	for _ = 1, math.ceil(seconds / STEP - 1e-9) do
		chrome:Update(STEP)
	end
end

local function paint()
	local panel = M()._state.panel

	expect(IsValid(panel)).to.beTrue()
	panel:Paint(ScrW(), ScrH())
end

return {
	groupName = "GryMod big map in the PDA frame",
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
		GetConVar("gry_map_chrome"):SetString("1")

		state.saved = {
			Compute = Map.Bounds.Compute,
			opened = Map._state.opened,
			lastClose = Map._state.lastClose,
			hudStatus = Map._state.hudStatus,
			Cache = Mini.Cache, Capture = Mini.Capture, Floors = Mini.Floors, Settings = Mini.Settings,
			Engine = {},
			Draw = GryMod.Flash.Draw,
			Theme = GryMod.FlashHUD and GryMod.FlashHUD.Theme,
			List = GryMod.Objectives and GryMod.Objectives.List,
			MousePos = gui.MousePos
		}

		for k, v in pairs(Map.Tiles.Engine) do
			state.saved.Engine[k] = v
		end

		Map.Bounds.Compute = function() return boundsAround(10000) end
		Map._state.lastClose = -math.huge
		Map._state.hudStatus = 0
		stubFlashDraw(true)
	end,
	afterEach = function(state)
		pcall(function()
			local Map = GryMod.Map
			local Mini = GryMod.Minimap

			if Map.IsOpen() then
				Map._close()
			end

			-- a closing animation that is still playing
			if IsValid(Map._state.ghost) then
				Map._state.ghost:Remove()
			end

			Map._state.ghost, Map._state.ghostLeaving, Map._state.closing = nil, false, false
			Map._state.chrome = nil

			Map.Bounds.Compute = state.saved.Compute
			Map._state.opened = state.saved.opened
			Map._state.lastClose = state.saved.lastClose
			Map._state.hudStatus = state.saved.hudStatus
			Mini.Cache, Mini.Capture, Mini.Floors, Mini.Settings = state.saved.Cache, state.saved.Capture, state.saved.Floors, state.saved.Settings
			GryMod.Flash.Draw = state.saved.Draw
			gui.MousePos = state.saved.MousePos

			if GryMod.FlashHUD then
				GryMod.FlashHUD.Theme = state.saved.Theme
			end

			for k, v in pairs(state.saved.Engine) do
				Map.Tiles.Engine[k] = v
			end

			if GryMod.Objectives and state.saved.List then
				GryMod.Objectives.List = state.saved.List
			end

			Map.Tiles.Reset()

			for name, value in pairs(state.convars) do
				GetConVar(name):SetString(value)
			end

			timer.Remove("GryMod big map trim")
		end)

		pcall(unstubDrawing, state)
	end,
	cases = {
		-- fails without the chrome in Map._open / layout: the window must sit in the movie's window
		{
			name = "with the convar at 1 the map opens in the movie: its window is inside the movie's map window, the shape of the bounds, and the placement is the chrome's",
			func = function(state)
				local Map = M()
				local Chrome = Map.Chrome

				standIns(state)
				Map.Open()

				local S = Map._state

				expect(S.chrome ~= nil).to.beTrue()

				local ox, oy, scale = Chrome.Placement(ScrW(), ScrH())

				expect(S.ox).to.aboutEqual(ox, 1e-9)
				expect(S.scale).to.aboutEqual(scale, 1e-9)

				local area = Chrome.ToScreen(ox, oy, scale, S.chrome.window)
				local view = S.view

				expect(view.x >= area.x - 1 and view.y >= area.y - 1).to.beTrue()
				expect(view.x + view.w <= area.x + area.w + 1 and view.y + view.h <= area.y + area.h + 1).to.beTrue()
				-- square bounds: the movie's window (it is a pixel narrower than high, so the square is its height)
				expect(math.abs(view.w - view.h) <= 1).to.beTrue()
				expect(view.h >= area.h - 2).to.beTrue()

				-- the zoom, the pan and the bounds are the map's: the same rules as before
				expect(view.zoom).to.equal(1)
				expect(view.cx).to.aboutEqual(playerPos().x, 1e-6)
				Map.Close()
			end
		},
		-- fails when the convar is not read at the opening
		{
			name = "with the convar at 0 the map opens as the plain panel: no chrome, the old window",
			func = function(state)
				local Map = M()

				GetConVar("gry_map_chrome"):SetString("0")
				standIns(state)
				Map.Open()
				expect(Map._state.chrome).to.beNil()
				expect(#flashDraws).to.equal(0)

				stubDrawing(state)
				paint()
				expect(textsDrawn()["STRATEGIC MAP"]).to.beTrue()
				expect(#flashDraws).to.equal(0)
				Map.Close()
				expect(Map._state.ghost).to.beNil()
			end
		},
		-- fails when the content is not gated by the opening mask (it showed at once, over the half-open frame) or is never drawn
		{
			name = "the tiles, the arrow and the grid are drawn from inside the movie only where its opening mask has revealed the window: nothing on the first frame, all of it when on",
			func = function(state)
				local Map = M()

				standIns(state)
				Map._state.opened = true
				Map.Open()
				tileUnderPlayer()
				stubDrawing(state)

				-- the first frame: the movie is drawn (once), the mask is a thin bar at the top of the panel, above the window: no content
				paint()
				expect(#flashDraws).to.equal(1)
				expect(#callsOf("surface.DrawTexturedRectUV")).to.equal(0)
				expect(#callsOf("surface.DrawPoly")).to.equal(0)

				-- the opening: the mask sweeps down; a frame in the middle of it reveals the window from its top down to the mask's edge
				run(0.75)
				recorded = {}
				paint()

				local scissors = callsOf("render.SetScissorRect")
				local view = Map._state.view

				if #scissors > 0 then
					expect(scissors[1][3] >= view.y).to.beTrue()
					expect(scissors[1][5] <= view.y + view.h).to.beTrue()
				end

				-- on: the whole window
				run(2)
				recorded = {}
				paint()

				expect(#callsOf("surface.DrawTexturedRectUV") >= 1).to.beTrue()
				expect(#callsOf("surface.DrawPoly") >= 1).to.beTrue()
				expect(#callsOf("surface.DrawLine") >= 18).to.beTrue()

				scissors = callsOf("render.SetScissorRect")
				expect(#scissors >= 2).to.beTrue()
				expect(scissors[1][6]).to.equal(true)
				expect(scissors[1][2] <= view.x + 1 and scissors[1][3] <= view.y + 1).to.beTrue()
				expect(scissors[1][4] >= view.x + view.w - 1 and scissors[1][5] >= view.y + view.h - 1).to.beTrue()
				expect(scissors[#scissors][6]).to.equal(false)
				Map.Close()
			end
		},
		-- fails when the map still draws its own title, DONE button or outline over the movie's
		{
			name = "the movie's texts replace the map's own: no 'STRATEGIC MAP', no 'DONE' drawn by the map; the zoom and cell, the hint and the grid letters are the map's",
			func = function(state)
				local Map = M()

				standIns(state)
				Map._state.opened = true
				Map.Open()
				tileUnderPlayer()
				run(2)
				stubDrawing(state)
				paint()

				local texts = textsDrawn()

				expect(texts["STRATEGIC MAP"]).to.beNil()
				expect(texts["DONE"]).to.beNil()

				for _, label in ipairs({"A", "H", "1", "8"}) do
					expect(texts[label]).to.beTrue()
				end

				-- the corner label: the cell of the player and the zoom
				local corner = false
				local hint = false

				for text in pairs(texts) do
					corner = corner or string.find(text, "x1.0", 1, true) ~= nil
					hint = hint or string.find(text, "CLOSE", 1, true) ~= nil
				end

				expect(corner).to.beTrue()
				expect(hint).to.beTrue()

				-- no outline of the plain panel when the window is the movie's whole window (its own frame is there)
				expect(#callsOf("surface.DrawOutlinedRect")).to.equal(0)
				Map.Close()
			end
		},
		-- fails when a long map is not letterboxed inside the movie's window
		{
			name = "a long map (2:1) is letterboxed in the movie's window, keeps its shape, and gets its own outline",
			func = function(state)
				local Map = M()
				local p = playerPos()

				Map.Bounds.Compute = function()
					return {x0 = p.x - 5000, x1 = p.x + 5000, y0 = p.y - 10000, y1 = p.y + 10000, source = "test"}
				end

				standIns(state)
				Map._state.opened = true
				Map.Open()
				run(2)

				local view = Map._state.view
				local area = Map._state.area

				expect(view.w).to.equal(area.w)
				expect(math.abs(view.h * 2 - view.w) <= 1).to.beTrue()
				expect(view.y > area.y).to.beTrue()

				stubDrawing(state)
				paint()
				expect(#callsOf("surface.DrawOutlinedRect")).to.equal(1)
				Map.Close()
			end
		},
		-- fails without the DONE of the movie
		{
			name = "the DONE button is the movie's: not there at the first frame, there once the movie is on (bottom right), clickable, and it follows the mouse with the movie's frames",
			func = function(state)
				local Map = M()

				standIns(state)
				Map.Open()
				stubDrawing(state)
				paint()
				expect(Map._state.doneRect).to.beNil()

				run(2)
				paint()

				local rect = Map._state.doneRect

				expect(rect ~= nil).to.beTrue()
				expect(rect.x > ScrW() / 2 and rect.y > ScrH() / 2).to.beTrue()

				local done = Map._state.chrome.area:Find("Buttons.BtnDone")

				-- the mouse outside: off; over it: the movie's over frame
				gui.MousePos = function() return 0, 0 end
				paint()
				expect(done:CurrentLabel()).to.equal("off")

				gui.MousePos = function() return rect.x + 3, rect.y + 3 end
				paint()
				expect(done:CurrentLabel()).to.equal("over_noanim")

				-- a click: press and release on it closes the map
				expect(Map.PressStart(MOUSE_LEFT, rect.x + 3, rect.y + 3)).to.equal("done")
				paint()
				expect(done:CurrentLabel()).to.equal("press")
				Map.PressEnd(MOUSE_LEFT, rect.x + 3, rect.y + 3)
				expect(Map.IsOpen()).to.beFalse()
			end
		},
		-- fails when the closing is cut at once (no animation) or the panel that took the mouse stays
		{
			name = "closing the map plays the movie's closing on a panel that takes no mouse and no key; the cursor and the game are free at once; a new opening ends it",
			func = function(state)
				local Map = M()

				standIns(state)
				Map.Open()
				run(2)

				local panel = Map._state.panel

				expect(Map.Close()).to.beTrue()
				expect(Map.IsOpen()).to.beFalse()
				expect(IsValid(panel)).to.beFalse()
				expect(hook.GetTable().Think["GryMod big map poll"]).to.beNil()

				local ghost = Map._state.ghost

				expect(IsValid(ghost)).to.beTrue()
				expect(ghost:IsMouseInputEnabled()).to.beFalse()
				expect(ghost:IsKeyboardInputEnabled()).to.beFalse()
				expect(Map._state.closing).to.beTrue()
				expect(Map._state.chrome:Phase()).to.equal("closing")

				-- it paints the movie, and asks the tile generator for nothing new
				stubDrawing(state)

				local planned = 0
				local realUpdate = Map.Tiles.Update

				Map.Tiles.Update = function(...)
					planned = planned + 1

					return realUpdate(...)
				end

				local before = #flashDraws
				local ok, err = pcall(ghost.Paint, ghost, ScrW(), ScrH())

				Map.Tiles.Update = realUpdate
				expect(ok).to.beTrue()
				expect(#flashDraws).to.equal(before + 1)
				expect(planned).to.equal(0)

				-- the end of the animation: the ghost asks to go (the timer removes it)
				run(2)
				ghost:Paint(ScrW(), ScrH())
				expect(Map._state.ghostLeaving).to.beTrue()
				expect(#flashDraws).to.equal(before + 1)

				-- a new opening before it goes: the old one is gone at once
				Map.Open()
				expect(IsValid(ghost)).to.beFalse()
				expect(Map._state.closing).to.beFalse()
				expect(Map.IsOpen()).to.beTrue()
				expect(Map._state.chrome:Phase()).to.equal("opening")
				Map.Close()
			end
		},
		-- fails when the HUD status is not followed
		{
			name = "GryMod_HUDStatus drives the movie: a malfunction jams it (the map dims to 35 percent), the end reboots it, a suit that is down at the opening opens it jammed",
			func = function(state)
				local Map = M()

				standIns(state)
				Map._state.opened = true
				Map.Open()
				tileUnderPlayer()
				run(2)
				expect(Map._state.chrome:Jammed()).to.beFalse()

				hook.Run("GryMod_HUDStatus", 1)
				expect(Map._state.chrome:Jammed()).to.beTrue()
				run(0.5)
				stubDrawing(state)
				paint()

				-- the dimming: a black rectangle over the window, 65 percent opaque
				local dimmed = false

				for _, c in ipairs(callsOf("surface.SetDrawColor")) do
					dimmed = dimmed or (c[2] == 0 and c[3] == 0 and c[4] == 0 and c[5] == math.floor(0.65 * 255))
				end

				expect(dimmed).to.beTrue()

				hook.Run("GryMod_HUDStatus", 0)
				expect(Map._state.chrome:Jammed()).to.beFalse()

				-- a flicker hides the movie and the map for a moment
				hook.Run("GryMod_HUDStatus", 2)
				recorded, flashDraws = {}, {}
				paint()
				expect(#flashDraws).to.equal(0)
				expect(#callsOf("surface.DrawPoly")).to.equal(0)
				hook.Run("GryMod_HUDStatus", 0)
				Map.Close()

				-- a map that opens while the suit is down
				hook.Run("GryMod_HUDStatus", 1)
				Map.Open()
				expect(Map._state.chrome:Jammed()).to.beTrue()
				Map.Close()
				hook.Run("GryMod_HUDStatus", 0)
				expect(Map._state.hudStatus).to.equal(0)
			end
		},
		-- fails when a movie that cannot be drawn leaves the player without a map
		{
			name = "when the movie cannot be drawn the plain panel takes over at once (same frame), the map stays open",
			func = function(state)
				local Map = M()

				standIns(state)
				Map.Open()
				run(2)
				stubFlashDraw(false)
				stubDrawing(state)

				local ok = pcall(function()
					local saved = ErrorNoHalt

					ErrorNoHalt = function() end
					paint()
					ErrorNoHalt = saved
				end)

				ErrorNoHalt = ErrorNoHalt
				expect(ok).to.beTrue()
				expect(Map.IsOpen()).to.beTrue()
				expect(Map._state.chrome).to.beNil()
				expect(textsDrawn()["STRATEGIC MAP"]).to.beTrue()
				expect(textsDrawn()["DONE"]).to.beTrue()

				-- the window is the plain one now (84 percent by 74 percent of the room, square bounds: the height)
				local view = Map._state.view

				expect(view.h).to.equal(math.floor(ScrH() * 0.74 + 0.5))
				Map.Close()
			end
		},
		-- fails when the frame does not wear the HUD's theme
		{
			name = "the grid wears the HUD theme's line colour with the frame, and the original's own colour without it",
			func = function(state)
				local Map = M()

				GryMod.FlashHUD = GryMod.FlashHUD or {}
				GryMod.FlashHUD.Theme = {Line = {11, 22, 33}, Over = {44, 55, 66}, Text = {77, 88, 99}}
				standIns(state)
				Map.Open()
				run(2)
				stubDrawing(state)
				paint()

				local found = false

				for _, c in ipairs(callsOf("surface.SetDrawColor")) do
					found = found or (c[2] == 11 and c[3] == 22 and c[4] == 33 and c[5] == 70)
				end

				expect(found).to.beTrue()
				Map.Close()

				-- the plain panel keeps the original's colours
				GetConVar("gry_map_chrome"):SetString("0")
				Map.Open()
				recorded = {}
				paint()
				found = false

				for _, c in ipairs(callsOf("surface.SetDrawColor")) do
					found = found or (c[2] == 96 and c[3] == 112 and c[4] == 80 and c[5] == 70)
				end

				expect(found).to.beTrue()
				Map.Close()
			end
		},
		-- fails when the cell of the main objective does not reach the movie's strip
		{
			name = "the cell of the main objective is written in the movie's OBJECTIVE: strip",
			func = function(state)
				local Map = M()
				local p = playerPos()

				GryMod.Objectives = GryMod.Objectives or {}
				GryMod.Objectives.List = function()
					return {{id = "a", title = "Go", state = "active", main = true, primary = true, radar = true, pos = Vector(p.x, p.y, p.z)}}
				end

				standIns(state)
				Map._state.opened = true
				Map.Open()
				tileUnderPlayer()
				run(2)
				stubDrawing(state)
				paint() -- the content finds the cell
				paint() -- the movie is told it at the next frame

				local chrome = Map._state.chrome

				expect(chrome.objectiveCell ~= nil).to.beTrue()
				expect(chrome.area:Child("TextBottom").visible).to.beTrue()
				Map.Close()
			end
		}
	}
}
