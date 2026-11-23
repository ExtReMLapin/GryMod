-- The big map (GryMod.Map): a map of the whole level, opened by a key (M by default), drawn in a panel with the screen clicker. This file is the glue: the
-- panel, the input, the drawing, the key, the console command, the HUD events, the hooks and the developer API. The rules live in small pure modules
-- (zoom.lua, frame.lua, bounds.lua, pyramid.lua, store.lua, fx.lua, markers.lua) and the tiles in tiles.lua.
--
-- WHAT IT DOES NOT DO: it does not pause the game and does not take the keyboard. Only the mouse look is blocked (the cursor is shown): the movement keys,
-- the other keys and the world go on, as in the original. It closes when its key is pressed again, when the game menu opens, when the player dies or when the
-- switch is turned off.
--
-- THE CONTROLS. The wheel zooms TOWARD THE MOUSE (the point under the cursor stays under it). A drag with the left or the right button moves the map, and
-- it stops at the bounds (the picture always fills the window: there is never an empty margin). The middle button held with the mouse moved up and down is a
-- smooth zoom. At the first opening of a map the zoom is automatic; later openings keep the last zoom (the convar gry_map_zoom); the map opens centred on the
-- player each time.
--
-- COST. Nothing runs while the map is closed: no hook, no timer but one that forgets the tiles a minute after it closed. While it is open one Think hook polls
-- its close conditions and the tiles are made by a PostRender hook that exists only while tiles are missing (tiles.lua).

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}

local Map = GryMod.Map

local Zoom, Frame, Bounds, Pyramid, Fx, Markers, Tiles, Settings

local function modules()
	Zoom, Frame, Bounds, Pyramid = Map.Zoom, Map.Frame, Map.Bounds, Map.Pyramid
	Fx, Markers, Tiles, Settings = Map.Fx, Map.Markers, Map.Tiles, Map.Settings
end

modules()

local floor, ceil, sin, cos, rad = math.floor, math.ceil, math.sin, math.cos, math.rad

-- The sounds of the original's map (HUD sounds 20 and 21), stood in for by the quick menu's pair: the same family of sounds.
Map.Sounds = {
	open = Sound("grymod/menu/modification_menu_appear.wav"),
	close = Sound("grymod/menu/modification_menu_dissapear.wav")
}

Map.TRIM_SECONDS = 60 -- the tiles of the map are forgotten this long after it closed
Map.CLOSE_GUARD = 0.25 -- seconds after a close during which the key does not open it again (the key that closed it may be seen by two readers)

-- the colours of the original's map: line, hover, text, and the accent
local LINE = Color(96, 112, 80)
local OVER = Color(216, 139, 50)
local TEXT = Color(181, 214, 142)
local ACCENT = Color(154, 214, 90)
local SHADOW = Color(0, 0, 0, 200)
local WINDOW_BACK = Color(8, 12, 10)
local DIM = Color(0, 0, 0, 160)
local TILE_TINT = Color(215, 230, 240)
local GREY = Color(170, 170, 170)
local dotColour = Color(255, 255, 255, 255)

local TITLE_FONT, LABEL_FONT, SMALL_FONT = "GryMapTitle", "GryMapLabel", "GryMapSmall"

local function makeFonts()
	local sh = ScrH()

	surface.CreateFont(TITLE_FONT, {font = "Tahoma", size = math.max(18, floor(sh / 40)), weight = 700, antialias = true})
	surface.CreateFont(LABEL_FONT, {font = "Tahoma", size = math.max(14, floor(sh / 62)), weight = 600, antialias = true})
	surface.CreateFont(SMALL_FONT, {font = "Tahoma", size = math.max(12, floor(sh / 78)), weight = 500, antialias = true})
end

makeFonts()

-- the state: one table that lives through a reload of this file ------------------------------------------------------------------------------------------
local S = Map._state or {}

Map._state = S

S.open = S.open or false
S.opened = S.opened or false -- a map was opened in this session already (the first opening is automatic, the others keep the last zoom)
S.lastClose = S.lastClose or -math.huge
S.lastReason = S.lastReason or nil

-- the markers of one frame, reused
local sourceBuffer, objectiveBuffer = {}, {}
local coarseCell = {pic = nil, u0 = 0, v0 = 0, u1 = 1, v1 = 1}
local sharpCell = {pic = nil, u0 = 0, v0 = 0, u1 = 1, v1 = 1}
local effectCell = {x = 0, y = 0, w = 0, h = 0, tx = 0, ty = 0, coarse = nil, sharp = nil}
local rimRect = {x = 0, y = 0, w = 0, h = 0}
local planSpec = {
	res = 1024, mpu = 0.01905, target = 2, coarse = 2, margin = 1,
	view = {minx = 0, maxx = 0, miny = 0, maxy = 0}, bounds = {x0 = 0, x1 = 0, y0 = 0, y1 = 0}, mouse = {x = 0, y = 0}
}

-- hooks and the key -------------------------------------------------------------------------------------------------------------------------------------

local function runHook(name, ...)
	local ok, err = pcall(hook.Run, name, ...)

	if not ok then
		ErrorNoHalt("[GryMod] " .. name .. ": " .. tostring(err) .. "\n")
	end
end

local function play(path)
	if GryMod.PlaySound then
		GryMod.PlaySound(path)
	end
end

local function metresPerUnit()
	return GryMod.RadarShared and GryMod.RadarShared.METRES_PER_UNIT or 0.01905
end

-- the bounds of the map -------------------------------------------------------------------------------------------------------------------------------

-- The ground nodes of the AI graph, read once per map (the file is parsed the first time the map opens: one-off, about 20 ms for 4000 nodes).
local function mapNodes()
	local map = game.GetMap()

	if S.nodesMap ~= map then
		S.nodesMap, S.nodes = map, nil

		local AIN = GryMod.AIN or (GryMod.Minimap and GryMod.Minimap.AIN)

		if AIN and AIN.Load then
			local ok, graph = pcall(AIN.Load, map)

			if ok and type(graph) == "table" then
				S.nodes = graph.nodes
			end
		end
	end

	return S.nodes
end

-- The box of the world in x and y (the whole BSP: often much larger than the playable area), or nil.
local function worldBox()
	local ok, world = pcall(game.GetWorld)

	if not ok or not IsValid(world) then
		return nil
	end

	local ok2, low, high = pcall(world.GetModelBounds, world)

	if not ok2 or not low or not high then
		return nil
	end

	return {x0 = low.x, x1 = high.x, y0 = low.y, y1 = high.y}
end

local function computeBounds(ply)
	local Zone = GryMod.ZoneMapClient
	local boxes = Zone and Zone.Boxes and Zone.Boxes() or nil
	local pos = IsValid(ply) and ply:GetPos() or nil

	return Bounds.Compute({
		nodes = mapNodes(),
		boxes = boxes,
		world = worldBox(),
		player = pos and {x = pos.x, y = pos.y} or nil
	})
end

-- the window ---------------------------------------------------------------------------------------------------------------------------------------------

local function layout(bounds)
	local sw, sh = ScrW(), ScrH()
	local w, h = Frame.WindowSize(sw * 0.84, sh * 0.74, bounds)

	return {x = floor((sw - w) / 2), y = floor((sh - h) / 2), w = w, h = h}
end

-- The state of the view: the frame, the level of the pyramid in use, the mouse, a drag.
local function fireZoomed(view)
	if S.zoomFired ~= view.zoom then
		S.zoomFired = view.zoom
		runHook("GryMod_MapZoomed", view.zoom)
	end
end

-- Whether a screen point is inside the window of the map.
local function inWindow(view, x, y)
	return x >= view.x and x <= view.x + view.w and y >= view.y and y <= view.y + view.h
end

-- input, as functions that do not touch a panel (the panel's handlers call them; the tests call them too) ---------------------------------------------------

-- A wheel event at (x, y): zooms toward that point when it is inside the window, else toward the middle.
function Map.Wheel(x, y, delta)
	local view = S.view

	if not S.open or not view then
		return false
	end

	local zoom = Zoom.Step(view.zoom, delta)

	if zoom == view.zoom then
		return false
	end

	if inWindow(view, x, y) then
		Frame.ZoomAt(view, zoom, x, y)
	else
		Frame.SetZoom(view, zoom)
	end

	fireZoomed(view)

	return true
end

-- A mouse button goes down at (x, y). The left and the right buttons move the map, the middle one zooms while the mouse goes up and down, a click on the
-- "done" button closes it. Returns what started: "pan", "zoom", "done" or nil.
function Map.PressStart(code, x, y)
	local view = S.view

	if not S.open or not view then
		return nil
	end

	local done = S.doneRect

	if code == MOUSE_LEFT and done and x >= done.x and x <= done.x + done.w and y >= done.y and y <= done.y + done.h then
		S.drag = "done"

		return "done"
	end

	if code == MOUSE_LEFT or code == MOUSE_RIGHT then
		if not inWindow(view, x, y) then
			return nil
		end

		S.drag, S.dragX, S.dragY = "pan", x, y

		return "pan"
	end

	if code == MOUSE_MIDDLE then
		S.drag, S.dragX, S.dragY = "zoom", x, y
		S.anchorX, S.anchorY = x, y

		return "zoom"
	end

	return nil
end

-- The mouse moved to (x, y) while a button is down.
function Map.DragMove(x, y)
	local view = S.view

	if not S.open or not view or not S.drag then
		return false
	end

	local dx, dy = x - S.dragX, y - S.dragY

	S.dragX, S.dragY = x, y

	if S.drag == "pan" then
		Frame.Pan(view, dx, dy)

		return true
	end

	if S.drag == "zoom" then
		local zoom = Zoom.Analog(view.zoom, dy)

		if zoom ~= view.zoom then
			if inWindow(view, S.anchorX, S.anchorY) then
				Frame.ZoomAt(view, zoom, S.anchorX, S.anchorY)
			else
				Frame.SetZoom(view, zoom)
			end

			fireZoomed(view)
		end

		return true
	end

	return false
end

-- A mouse button goes up. A click on "done" that ends on "done" closes the map.
function Map.PressEnd(code, x, y)
	local kind = S.drag

	S.drag = nil

	if kind == "done" and code == MOUSE_LEFT then
		local done = S.doneRect

		if done and x >= done.x and x <= done.x + done.w and y >= done.y and y <= done.y + done.h then
			Map.Close()
		end
	end

	return kind
end

-- the markers ---------------------------------------------------------------------------------------------------------------------------------------------

-- The markers of this frame: the objectives, then every source. Returns the buffer of the sources and its length, and the objectives' buffer and its length.
function Map.CollectMarkers()
	local list = GryMod.Objectives and GryMod.Objectives.List and GryMod.Objectives.List() or nil
	local nObjectives = Markers.FromObjectives(list, Settings.ShowFinished(), objectiveBuffer)
	local nSources = Markers.Collect(sourceBuffer)

	return sourceBuffer, nSources, objectiveBuffer, nObjectives
end

-- drawing --------------------------------------------------------------------------------------------------------------------------------------------------

-- The drawer the loading looks are written against (fx.lua): everything goes through these three functions.
local Drawer = {}

function Drawer.Fill(x, y, w, h, r, g, b, a)
	surface.SetDrawColor(r, g, b, a)
	surface.DrawRect(x, y, w, h)
end

-- A band of a cell's picture, shifted sideways. `pic` is {pic = {mat, fade}, u0, v0, u1, v1}: the part of the picture that covers the cell.
function Drawer.Slice(pic, x, y, w, h, f0, f1, dx, r, g, b, a, additive)
	local picture = pic and pic.pic

	if not picture or picture == Tiles.EMPTY then
		return
	end

	local v0 = pic.v0 + (pic.v1 - pic.v0) * f0
	local v1 = pic.v0 + (pic.v1 - pic.v0) * f1
	local top = y + floor(h * f0)
	local height = y + ceil(h * f1) - top

	surface.SetMaterial((a < 255 or additive) and picture.fade or picture.mat)
	surface.SetDrawColor(r, g, b, a)

	if additive then
		render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
		surface.DrawTexturedRectUV(x + dx, top, w, height, pic.u0, v0, pic.u1, v1)
		render.OverrideBlend(false)
	else
		surface.DrawTexturedRectUV(x + dx, top, w, height, pic.u0, v0, pic.u1, v1)
	end
end

function Drawer.Rim(x, y, w, h, thickness, r, g, b, a)
	surface.SetDrawColor(r, g, b, a)
	surface.DrawRect(x, y, w, thickness)
	surface.DrawRect(x, y + h - thickness, w, thickness)
	surface.DrawRect(x, y + thickness, thickness, h - 2 * thickness)
	surface.DrawRect(x + w - thickness, y + thickness, thickness, h - 2 * thickness)
end

local function setPicture(cell, picture, u0, v0, u1, v1)
	cell.pic, cell.u0, cell.v0, cell.u1, cell.v1 = picture, u0, v0, u1, v1

	return cell
end

-- draws a picture (the part u0..v1 of it) opaque in the rectangle
local function drawPicture(picture, x, y, w, h, u0, v0, u1, v1)
	if picture == nil or picture == Tiles.EMPTY then
		return
	end

	surface.SetMaterial(picture.mat)
	surface.SetDrawColor(TILE_TINT.r, TILE_TINT.g, TILE_TINT.b, 255)
	surface.DrawTexturedRectUV(x, y, w, h, u0, v0, u1, v1)
end

-- Resolve with the exact level left out: the coarser picture of a place (the base of the loading looks).
local skipLevel = nil

local function lookupBelow(ppm, tx, ty)
	if ppm == skipLevel then
		return nil
	end

	return Tiles.Lookup(ppm, tx, ty)
end

-- the tiles ---------------------------------------------------------------------------------------------------------------------------------------------------

local function drawTiles(view, level, res, target, now)
	local mpu = metresPerUnit()
	local T = Pyramid.TileUnits(res, target, mpu)
	local minx, maxx, miny, maxy = Frame.View(view)
	local tx0, tx1, ty0, ty1 = Pyramid.Range(minx, maxx, miny, maxy, T, 0)
	local look = Fx.Resolve(Settings.LoadingFx())
	local arriveSeconds = Fx.ArriveSeconds(look)
	local tracker = Tiles.Tracker()
	local index = Pyramid.LevelIndex(target)

	-- the window is dark under the tiles
	surface.SetDrawColor(WINDOW_BACK.r, WINDOW_BACK.g, WINDOW_BACK.b, 255)
	surface.DrawRect(view.x, view.y, view.w, view.h)

	if (tx1 - tx0 + 1) * (ty1 - ty0 + 1) > 400 then
		return
	end

	for tx = tx0, tx1 do
		for ty = ty0, ty1 do
			local left, top, right, bottom = Frame.TileRect(view, tx * T, ty * T, (tx + 1) * T, (ty + 1) * T)
			local x0, y0 = floor(left), floor(top)
			local w, h = ceil(right) - x0, ceil(bottom) - y0
			local key = Pyramid.Key(index, tx, ty)
			local mode, a, b = Fx.Tracker.Look(tracker, key, now, arriveSeconds)
			local exact, _, eu0, ev0, eu1, ev1

			skipLevel = nil
			exact, _, eu0, ev0, eu1, ev1 = Pyramid.Resolve(tx, ty, target, Tiles.Lookup)

			if mode == nil then
				-- nothing to say about this cell: the best picture there is, plain
				drawPicture(exact, x0, y0, w, h, eu0 or 0, ev0 or 0, eu1 or 1, ev1 or 1)
			else
				-- the coarser picture of the place is the base; the look draws over it
				skipLevel = target

				local coarse, _, cu0, cv0, cu1, cv1 = Pyramid.Resolve(tx, ty, target, lookupBelow)

				skipLevel = nil

				if coarse then
					drawPicture(coarse, x0, y0, w, h, cu0, cv0, cu1, cv1)
				end

				effectCell.x, effectCell.y, effectCell.w, effectCell.h, effectCell.tx, effectCell.ty = x0, y0, w, h, tx, ty
				effectCell.coarse = coarse and setPicture(coarseCell, coarse, cu0, cv0, cu1, cv1) or nil

				if mode == "waiting" then
					effectCell.sharp = nil
					look.waiting(Drawer, effectCell, a)
				else
					-- arrived: the sharp tile is the exact one (never a coarser one: the look is the arrival of THIS tile)
					local sharp = Tiles.Lookup(target, tx, ty)

					effectCell.sharp = sharp and sharp ~= Tiles.EMPTY and setPicture(sharpCell, sharp, 0, 0, 1, 1) or nil

					if effectCell.sharp then
						look.arrived(Drawer, effectCell, a, b)
					else
						drawPicture(exact, x0, y0, w, h, eu0 or 0, ev0 or 0, eu1 or 1, ev1 or 1)
					end
				end
			end
		end
	end
end

-- grid, markers, texts ----------------------------------------------------------------------------------------------------------------------------------

local function drawGrid(view)
	local xs, ys = Markers.GridLines(view)
	local lineA = 70

	surface.SetDrawColor(LINE.r, LINE.g, LINE.b, lineA)

	-- a line of constant X is horizontal on the screen, one of constant Y vertical
	for i = 1, 9 do
		local _, sy = Frame.ToScreen(view, xs[i], view.cy)
		local sx = Frame.ToScreen(view, view.cx, ys[i])

		surface.DrawLine(view.x, sy, view.x + view.w, sy)
		surface.DrawLine(sx, view.y, sx, view.y + view.h)
	end

	-- the numbers along the top (counting toward -Y), the letters down the left side (counting toward -X)
	local stepY, stepX = (view.y1 - view.y0) / 8, (view.x1 - view.x0) / 8

	for i = 1, 8 do
		local sx = Frame.ToScreen(view, view.cx, view.y1 - (i - 0.5) * stepY)

		if sx > view.x + 10 and sx < view.x + view.w - 10 then
			draw.SimpleText(tostring(i), SMALL_FONT, sx, view.y + 4, TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		end

		local _, sy = Frame.ToScreen(view, view.x1 - (i - 0.5) * stepX, view.cy)

		if sy > view.y + 10 and sy < view.y + view.h - 10 then
			draw.SimpleText(string.sub("ABCDEFGH", i, i), SMALL_FONT, view.x + 6, sy, TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
end

-- a diamond (the objective's icon): points clockwise on the screen
local diamond = {{x = 0, y = 0}, {x = 0, y = 0}, {x = 0, y = 0}, {x = 0, y = 0}}

local function drawDiamond(x, y, size, r, g, b, a)
	diamond[1].x, diamond[1].y = x, y - size
	diamond[2].x, diamond[2].y = x + size, y
	diamond[3].x, diamond[3].y = x, y + size
	diamond[4].x, diamond[4].y = x - size, y

	draw.NoTexture()
	surface.SetDrawColor(r, g, b, a)
	surface.DrawPoly(diamond)
	surface.SetDrawColor(0, 0, 0, a)
	surface.DrawLine(x, y - size, x + size, y)
	surface.DrawLine(x + size, y, x, y + size)
	surface.DrawLine(x, y + size, x - size, y)
	surface.DrawLine(x - size, y, x, y - size)
end

local function drawMarker(view, m, uiScale)
	local pos = m.pos

	if type(pos) ~= "table" and not isvector(pos) then
		return
	end

	local sx, sy = Frame.ToScreen(view, pos.x, pos.y)
	local x, y, pinned = Markers.Pin(sx, sy, view, 8)
	local shape, r, g, b = Markers.Style(m)
	local alpha = floor((type(m.alpha) == "number" and math.Clamp(m.alpha, 0, 1) or 1) * (pinned and 0.6 or 1) * 255)
	local size = Markers.IconSize(view.zoom, 7 * uiScale, m.scale)

	if shape == "diamond" then
		if m.main then
			surface.DrawCircle(x, y, size * 1.9, ACCENT.r, ACCENT.g, ACCENT.b, alpha)
			surface.DrawCircle(x, y, size * 1.9 + 1, ACCENT.r, ACCENT.g, ACCENT.b, alpha)
		end

		drawDiamond(x, y, size, r, g, b, alpha)
	elseif shape == "ring" then
		surface.DrawCircle(x, y, size * 1.4, r, g, b, alpha)
	else
		dotColour.r, dotColour.g, dotColour.b, dotColour.a = r, g, b, alpha
		draw.RoundedBox(size * 0.6, x - size * 0.6, y - size * 0.6, size * 1.2, size * 1.2, dotColour)
	end

	if m.label and not pinned then
		local text = tostring(m.label)

		draw.SimpleText(text, LABEL_FONT, x + size + 5, y + 1, SHADOW, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(text, LABEL_FONT, x + size + 4, y, m.finished and GREY or TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
end

-- the player: a white arrow turned with his view. The map is not turned: world +X is up, so a player who looks along +X (yaw 0) points up, one who looks
-- along +Y (yaw 90) points to the left (the picture's -Y side is its right).
local arrow = {{x = 0, y = 0}, {x = 0, y = 0}, {x = 0, y = 0}, {x = 0, y = 0}}

local function drawPlayer(view, ply, uiScale)
	local pos = ply:GetPos()
	local yaw = rad(ply:EyeAngles().yaw)
	local sx, sy = Frame.ToScreen(view, pos.x, pos.y)
	local fx, fy = -sin(yaw), -cos(yaw) -- forward on the screen
	local rx, ry = -fy, fx -- to its right on the screen
	local s = Markers.IconSize(view.zoom, 9 * uiScale, 100)
	local x, y = sx, sy

	arrow[1].x, arrow[1].y = x + fx * s * 1.4, y + fy * s * 1.4
	arrow[2].x, arrow[2].y = x - fx * s + rx * s * 0.9, y - fy * s + ry * s * 0.9
	arrow[3].x, arrow[3].y = x - fx * s * 0.35, y - fy * s * 0.35
	arrow[4].x, arrow[4].y = x - fx * s - rx * s * 0.9, y - fy * s - ry * s * 0.9

	draw.NoTexture()
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawPoly(arrow)
	surface.SetDrawColor(0, 0, 0, 255)

	for i = 1, 4 do
		local a, b = arrow[i], arrow[i % 4 + 1]

		surface.DrawLine(a.x, a.y, b.x, b.y)
	end
end

local function drawFrameAndTexts(view, ply)
	surface.SetDrawColor(LINE.r, LINE.g, LINE.b, 255)
	surface.DrawOutlinedRect(view.x - 1, view.y - 1, view.w + 2, view.h + 2, 2)

	local _, _, text = Markers.GridRef(view, ply:GetPos().x, ply:GetPos().y)
	local key = Map.Key and Map.Key.KeyName(Map.Key.Effective()) or "M"
	local gap = floor(ScrH() * 0.012)

	draw.SimpleText("STRATEGIC MAP", TITLE_FONT, view.x, view.y - gap, TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
	draw.SimpleText(string.format("%s    x%.1f", text or "--", view.zoom), TITLE_FONT, view.x + view.w, view.y - gap, TEXT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	draw.SimpleText("WHEEL: ZOOM   DRAG: MOVE   MIDDLE BUTTON: SMOOTH ZOOM   " .. key .. ": CLOSE", SMALL_FONT, view.x, view.y + view.h + gap, LINE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

	-- the "done" button (the original has one too)
	local bw, bh = floor(ScrW() * 0.06), floor(ScrH() * 0.034)
	local bx, by = view.x + view.w - bw, view.y + view.h + gap
	local mx, my = gui.MousePos()
	local over = mx >= bx and mx <= bx + bw and my >= by and my <= by + bh

	S.doneRect = {x = bx, y = by, w = bw, h = bh}
	surface.SetDrawColor((over and OVER or LINE).r, (over and OVER or LINE).g, (over and OVER or LINE).b, 255)
	surface.DrawOutlinedRect(bx, by, bw, bh, 2)
	draw.SimpleText("DONE", LABEL_FONT, bx + bw / 2, by + bh / 2, over and OVER or TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- What is drawn inside the window (clipped to it by the scissor rectangle): the tiles with their loading looks, the grid, the markers, the player, the rim.
local function drawContent(view, level, res, target, now, ply, uiScale)
	drawTiles(view, level, res, target, now)

	if Settings.ShowGrid() then
		drawGrid(view)
	end

	local sources, nSources, objectives, nObjectives = Map.CollectMarkers()

	for i = 1, nObjectives do
		drawMarker(view, objectives[i], uiScale)
	end

	for i = 1, nSources do
		drawMarker(view, sources[i], uiScale)
	end

	drawPlayer(view, ply, uiScale)

	-- the rim at the very end of a loading
	local look = Fx.Resolve(Settings.LoadingFx())
	local p = Fx.Tracker.Rim(Tiles.Tracker(), now, Fx.RimSeconds(look))

	if p and look.finish then
		rimRect.x, rimRect.y, rimRect.w, rimRect.h = view.x, view.y, view.w, view.h
		look.finish(Drawer, rimRect, p)
	end
end

-- The whole map, one frame. Runs under pcall (see paintPanel).
local function drawMap(panel)
	modules()

	local ply = LocalPlayer()

	if not IsValid(ply) or not S.view then
		return
	end

	local view = S.view
	local now = RealTime()
	local uiScale = ScrH() / 1080

	-- the screen changed size: the window follows
	if S.screenW ~= ScrW() or S.screenH ~= ScrH() then
		S.screenW, S.screenH = ScrW(), ScrH()
		Frame.SetRect(view, layout(view))
		makeFonts()
	end

	-- the dimmed screen behind the map
	surface.SetDrawColor(DIM.r, DIM.g, DIM.b, DIM.a)
	surface.DrawRect(0, 0, ScrW(), ScrH())

	local level, res = Tiles.Begin()

	-- the definition the zoom needs, and the plan of the tiles (made again only when it changes)
	local mx, my = gui.MousePos()
	local mouseX, mouseY

	if inWindow(view, mx, my) then
		mouseX, mouseY = Frame.ToWorld(view, mx, my)
	else
		mouseX, mouseY = view.cx, view.cy
	end

	local target = Pyramid.Target(Frame.Scale(view), S.target)

	S.target = target

	local levels = Pyramid.Levels()
	local minx, maxx, miny, maxy = Frame.View(view)

	planSpec.res, planSpec.mpu, planSpec.target, planSpec.coarse = res, metresPerUnit(), target, levels[1]
	planSpec.view.minx, planSpec.view.maxx, planSpec.view.miny, planSpec.view.maxy = minx, maxx, miny, maxy
	planSpec.bounds.x0, planSpec.bounds.x1, planSpec.bounds.y0, planSpec.bounds.y1 = view.x0, view.x1, view.y0, view.y1
	planSpec.mouse.x, planSpec.mouse.y = mouseX, mouseY
	Tiles.Update(planSpec, now)

	render.SetScissorRect(view.x, view.y, view.x + view.w, view.y + view.h, true)

	local ok, err = pcall(drawContent, view, level, res, target, now, ply, uiScale)

	render.SetScissorRect(0, 0, 0, 0, false)
	render.OverrideBlend(false)

	if not ok then
		error(err, 0)
	end

	drawFrameAndTexts(view, ply)

	if now - (S.prunedAt or 0) > 1 then
		S.prunedAt = now
		Fx.Tracker.Prune(Tiles.Tracker(), now, Fx.ArriveSeconds(Fx.Resolve(Settings.LoadingFx())))
	end
end

-- A failure while painting closes the map and says why once: a broken map must never keep the cursor or the game.
local function paintPanel(panel)
	local ok, err = pcall(drawMap, panel)

	if not ok then
		ErrorNoHalt("[GryMod] the big map stopped: " .. tostring(err) .. "\n")
		timer.Simple(0, function()
			Map.Close()
		end)
	end
end

-- opening and closing -----------------------------------------------------------------------------------------------------------------------------------

local POLL_HOOK = "GryMod big map poll"

-- Once per frame while the map is open (a temporary Think: it is removed when the map closes): the conditions that close it.
local function poll()
	local ply = LocalPlayer()

	if not S.open then
		return
	end

	if not IsValid(ply) or not ply:Alive() or not Settings.Enabled() or gui.IsGameUIVisible() then
		Map.Close()

		return
	end

	local key = Map.Key
	local code = key and key.Effective() or 0

	if code > 0 then
		local down = input.IsButtonDown(code)

		-- the key goes down while the map is open: it closes (unless the player is typing: a key that opens the chat is not ours)
		if down and not S.keyDown and not ply:IsTyping() then
			Map.Close()

			return
		end

		S.keyDown = down
	end
end

-- Opens the map. The HUD event "map_open" is the entry (Map.Open sends it); this does the work. Returns true, or false and why.
function Map._open()
	modules()

	if S.open then
		return true
	end

	local ply = LocalPlayer()

	if not Settings.Enabled() then
		S.lastReason = "the big map is switched off (gry_map_enable 0)"

		return false, S.lastReason
	end

	if not IsValid(ply) or not ply:Alive() then
		S.lastReason = "the player is dead"

		return false, S.lastReason
	end

	local bounds = computeBounds(ply)
	local rect = layout(bounds)
	local view = Frame.New(rect, bounds)
	local zoom

	if S.opened then
		zoom = Settings.Zoom() -- the last zoom
	else
		zoom = Zoom.Auto(Bounds.SpanMetres(bounds)) -- the first opening of a map: automatic
	end

	Frame.SetZoom(view, zoom)

	local pos = ply:GetPos()

	Frame.CentreOn(view, pos.x, pos.y) -- the pan starts again at the player each time

	S.view, S.bounds, S.target = view, bounds, nil
	S.opened, S.open, S.drag = true, true, nil
	S.zoomFired = view.zoom
	S.screenW, S.screenH = ScrW(), ScrH()
	S.keyDown = Map.Key and Map.Key.Effective() > 0 and input.IsButtonDown(Map.Key.Effective()) or false
	S.lastReason = nil

	timer.Remove("GryMod big map trim")

	local panel = vgui.Create("Panel")

	panel:SetSize(ScrW(), ScrH())
	panel:SetPos(0, 0)
	panel:SetCursor("arrow")
	panel:MakePopup()
	panel:SetKeyboardInputEnabled(false) -- the keys of the game go on: only the mouse is taken
	panel.Paint = paintPanel

	function panel:OnMouseWheeled(delta)
		local x, y = self:CursorPos()

		Map.Wheel(x, y, delta)
	end

	function panel:OnMousePressed(code)
		local x, y = self:CursorPos()

		if Map.PressStart(code, x, y) then
			self:MouseCapture(true)
		end
	end

	function panel:OnMouseReleased(code)
		local x, y = self:CursorPos()

		self:MouseCapture(false)
		Map.PressEnd(code, x, y)
	end

	function panel:OnCursorMoved(x, y)
		Map.DragMove(x, y)
	end

	S.panel = panel

	hook.Add("Think", POLL_HOOK, poll)

	-- the big map takes the even frames of the capture while it is open, so its tiles come even when the radar is busy
	local Capture = GryMod.Minimap and GryMod.Minimap.Capture

	if Capture and Capture.SetPriority then
		Capture.SetPriority("map")
	end

	play(Map.Sounds.open)
	runHook("GryMod_MapOpened")

	return true
end

-- Closes the map. The HUD event "map_close" is the entry; this does the work.
function Map._close()
	if not S.open then
		return true
	end

	S.open = false
	S.drag = nil
	S.lastClose = RealTime()

	hook.Remove("Think", POLL_HOOK)

	if IsValid(S.panel) then
		S.panel:MouseCapture(false)
		S.panel:Remove()
	end

	S.panel = nil

	if S.view then
		Settings.SaveZoom(S.view.zoom)
	end

	local Capture = GryMod.Minimap and GryMod.Minimap.Capture

	if Capture and Capture.SetPriority then
		Capture.SetPriority(nil)
	end

	if Tiles then
		Tiles.Cancel()
	end

	-- the tiles stay a minute (a quick reopening finds them), then they are forgotten
	timer.Create("GryMod big map trim", Map.TRIM_SECONDS, 1, function()
		if not S.open and Tiles then
			Tiles.Clear()
		end
	end)

	play(Map.Sounds.close)
	runHook("GryMod_MapClosed")

	return true
end

-- the developer API -------------------------------------------------------------------------------------------------------------------------------------------

-- Opens the big map (by the HUD event "map_open", like every effect of the interface). Returns true, or false and why.
function Map.Open()
	if S.open then
		return true
	end

	local API = GryMod.API

	if API and API.HUDEvent then
		API.HUDEvent("map_open")
	else
		Map._open()
	end

	if S.open then
		return true
	end

	return false, S.lastReason or "the big map did not open"
end

function Map.Close()
	if not S.open then
		return true
	end

	local API = GryMod.API

	if API and API.HUDEvent then
		API.HUDEvent("map_close")
	else
		Map._close()
	end

	return not S.open
end

function Map.Toggle()
	if S.open then
		return Map.Close()
	end

	return Map.Open()
end

function Map.IsOpen()
	return S.open == true
end

-- The zoom now (1 to 8), or the saved one while the map is closed.
function Map.GetZoom()
	if S.open and S.view then
		return S.view.zoom
	end

	return Settings.Zoom()
end

-- The bounds of the picture {x0, x1, y0, y1, source} of the map in use, or nil before it was ever opened.
function Map.GetBounds()
	return S.bounds
end

-- Marker sources for third parties: the same records as GryMod.Radar.AddSource (see docs/minimap.md).
function Map.AddMarkerSource(key, fn)
	return Markers.AddSource(key, fn)
end

function Map.RemoveMarkerSource(key)
	return Markers.RemoveSource(key)
end

-- The player's key. The default is M; a `bind <key> gry_map` in the console works too.
Map.Key = GryMod.KeyBinder.New{
	convar = "gry_map_key",
	description = "Key that opens and closes the big map (a button code, 0 = the default key M; `bind <key> gry_map` works too)",
	command = "gry_map",
	title = "GryMod big map",
	text = "Click the box and press the key you want for the big map.",
	-- no prompt at spawn: the map has a default key
	active = function() return false end,
	default = function() return KEY_M end,
	-- the other keys of the addon are not taken
	refuse = function(code)
		return (GryMod.MenuKey ~= nil and GryMod.MenuKey.Chosen() == code) or (GryMod.SuitZoom ~= nil and GryMod.SuitZoom.Key.Chosen() == code)
	end,
	press = function(down)
		-- the key that just closed the map may be read by two readers in one frame: it does not open it again
		if down and RealTime() - S.lastClose > Map.CLOSE_GUARD then
			Map.Toggle()
		end
	end
}

concommand.Add("gry_map", function()
	Map.Toggle()
end, nil, "Opens or closes the big map")

-- the HUD events: the map opens and closes like every other effect of the interface (the picture and the sound in one call) ----------------------------------

local API = GryMod.API

if API and API.RegisterHUDEvent then
	API.RegisterHUDEvent("map_open", function()
		Map._open()
	end, {
		label = "Open the big map",
		follows = {{"gry_map_enable", "the big map"}, {"gry_sounds", "the sound"}}
	})

	API.RegisterHUDEvent("map_close", function()
		Map._close()
	end, {
		label = "Close the big map",
		follows = {{"gry_sounds", "the sound"}}
	})
end

if API and API.AddFeature then
	API.AddFeature("bigmap")
end

-- a map that is still open when this file loads again (a reload in the game) closes: its panel belongs to the old code
if IsValid(S.panel) then
	S.panel:Remove()
	S.panel, S.open = nil, false
	hook.Remove("Think", POLL_HOOK)
end
