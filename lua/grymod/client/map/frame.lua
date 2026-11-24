-- The big map: the frame (GryMod.Map.Frame). The maths between the world and the window of the map: where a world point is on the screen, which world
-- rectangle the window shows, the zoom toward the mouse, the drag and the hard limit at the bounds. Pure, no engine call.
--
-- THE ORIENTATION. The map is not turned. World +X is UP on the screen and world -Y is to the RIGHT: that is the way a captured tile is stored (the
-- picture of a tile has its top at world +X and its right at world -Y), so a tile is drawn as it is, without any rotation. It is also what the radar
-- shows for a player who looks along +X.
--
-- THE VIEW. A view `v` is a plain table, changed in place:
--   x, y, w, h        the window on the screen, in pixels
--   x0, x1, y0, y1    the bounds of the map in world units (x0 < x1, y0 < y1); the picture never leaves them
--   k1                pixels per world unit at zoom 1
--   zoom              1 to zoomMax
--   zoomMax           the closest zoom of this view: the one where a screen pixel covers the centimetres of the setting (7 by default), never under 8
--                     (Zoom.MaxFor); it follows the window and the bounds
--   cx, cy            the world point in the middle of the window
-- The scale is k1 * zoom. The scale at zoom 1 COVERS the window (the larger of the two ratios), so the picture always fills it: there is never an
-- empty margin, at any zoom. A window of the shape of the bounds (see WindowSize) is covered exactly, and then there is no pan at zoom 1.

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}
GryMod.Map.Frame = GryMod.Map.Frame or {}

local Frame = GryMod.Map.Frame

-- The shape of the window (width over height) is the bounds' shape, kept inside these limits.
Frame.ASPECT_MIN = 0.5
Frame.ASPECT_MAX = 2

local floor = math.floor

local function zoomLimits(v)
	local Zoom = GryMod.Map.Zoom

	if Zoom then
		return Zoom.MIN, v and v.zoomMax or Zoom.MAX
	end

	return 1, v and v.zoomMax or 8
end

-- What a screen pixel covers at the closest zoom, in centimetres of the world: the setting when its module is there, else the default.
local function centimetres()
	local Settings = GryMod.Map.Settings

	if Settings and Settings.ZoomCentimetres then
		return Settings.ZoomCentimetres()
	end

	return 7
end


-- The size of the window inside a room of availW x availH pixels, for bounds: the shape of the bounds (the screen's horizontal axis is world Y, the
-- vertical one is world X), kept from 1:2 to 2:1, as large as the room allows. Whole pixels.
function Frame.WindowSize(availW, availH, bounds)
	local bw, bh = bounds.y1 - bounds.y0, bounds.x1 - bounds.x0
	local aspect = 1

	if bw > 0 and bh > 0 then
		aspect = bw / bh
	end

	if aspect < Frame.ASPECT_MIN then
		aspect = Frame.ASPECT_MIN
	elseif aspect > Frame.ASPECT_MAX then
		aspect = Frame.ASPECT_MAX
	end

	local w = availW
	local h = w / aspect

	if h > availH then
		h = availH
		w = h * aspect
	end

	return floor(w + 0.5), floor(h + 0.5)
end

-- Pixels per world unit at zoom 1: the scale that makes the bounds cover the window.
local function fitScale(w, h, bounds)
	local bw, bh = bounds.y1 - bounds.y0, bounds.x1 - bounds.x0

	if not (bw > 0 and bh > 0) then
		return 1
	end

	local a, b = w / bw, h / bh

	return a > b and a or b
end

-- The scale at zoom 1 and, from it, the closest zoom.
local function refit(v, bounds)
	local Zoom = GryMod.Map.Zoom

	v.k1 = fitScale(v.w, v.h, bounds)
	v.zoomMax = Zoom and Zoom.MaxFor(v.k1, centimetres()) or 8
end

function Frame.Scale(v)
	return v.k1 * v.zoom
end

-- The centre pushed back so that the window stays inside the bounds (on an axis where the window is larger than the bounds, it stays on the middle).
function Frame.Clamp(v)
	local low, high = zoomLimits(v)

	if v.zoom < low then
		v.zoom = low
	elseif v.zoom > high then
		v.zoom = high
	end

	local k = v.k1 * v.zoom
	local hx, hy = v.h / (2 * k), v.w / (2 * k)
	local lo, hi = v.x0 + hx, v.x1 - hx

	if lo > hi then
		v.cx = (v.x0 + v.x1) / 2
	elseif v.cx < lo then
		v.cx = lo
	elseif v.cx > hi then
		v.cx = hi
	end

	lo, hi = v.y0 + hy, v.y1 - hy

	if lo > hi then
		v.cy = (v.y0 + v.y1) / 2
	elseif v.cy < lo then
		v.cy = lo
	elseif v.cy > hi then
		v.cy = hi
	end

	return v
end

-- A view of `bounds` {x0, x1, y0, y1} in the window `rect` {x, y, w, h}: zoom 1, centred on the bounds.
function Frame.New(rect, bounds)
	local v = {
		x = rect.x, y = rect.y, w = rect.w, h = rect.h,
		x0 = bounds.x0, x1 = bounds.x1, y0 = bounds.y0, y1 = bounds.y1,
		zoom = 1, cx = (bounds.x0 + bounds.x1) / 2, cy = (bounds.y0 + bounds.y1) / 2
	}

	refit(v, bounds)

	return Frame.Clamp(v)
end

-- Other bounds (the map knows more of itself): the zoom and the centre stay as far as they fit.
function Frame.SetBounds(v, bounds)
	v.x0, v.x1, v.y0, v.y1 = bounds.x0, bounds.x1, bounds.y0, bounds.y1
	refit(v, bounds)

	return Frame.Clamp(v)
end

-- The window moves or changes size (the screen changed): the world point in the middle stays.
function Frame.SetRect(v, rect)
	v.x, v.y, v.w, v.h = rect.x, rect.y, rect.w, rect.h
	refit(v, v)

	return Frame.Clamp(v)
end

-- Screen pixel of a world point.
function Frame.ToScreen(v, wx, wy)
	local k = v.k1 * v.zoom

	return v.x + v.w / 2 - (wy - v.cy) * k, v.y + v.h / 2 - (wx - v.cx) * k
end

-- World point under a screen pixel.
function Frame.ToWorld(v, sx, sy)
	local k = v.k1 * v.zoom

	return v.cx - (sy - (v.y + v.h / 2)) / k, v.cy - (sx - (v.x + v.w / 2)) / k
end

-- A new zoom about the middle of the window.
function Frame.SetZoom(v, zoom)
	v.zoom = zoom

	return Frame.Clamp(v)
end

-- A new zoom TOWARD a screen point: the world point under (sx, sy) stays under it (as far as the bounds allow).
function Frame.ZoomAt(v, zoom, sx, sy)
	local wx, wy = Frame.ToWorld(v, sx, sy)

	v.zoom = zoom

	local low, high = zoomLimits(v)

	if v.zoom < low then
		v.zoom = low
	elseif v.zoom > high then
		v.zoom = high
	end

	local k = v.k1 * v.zoom

	v.cx = wx + (sy - (v.y + v.h / 2)) / k
	v.cy = wy + (sx - (v.x + v.w / 2)) / k

	return Frame.Clamp(v)
end

-- A drag of the mouse by (dsx, dsy) pixels: the picture follows the hand.
function Frame.Pan(v, dsx, dsy)
	local k = v.k1 * v.zoom

	v.cy = v.cy + dsx / k
	v.cx = v.cx + dsy / k

	return Frame.Clamp(v)
end

-- Puts a world point in the middle of the window.
function Frame.CentreOn(v, wx, wy)
	v.cx, v.cy = wx, wy

	return Frame.Clamp(v)
end

-- The world rectangle the window shows: minx, maxx, miny, maxy.
function Frame.View(v)
	local k = v.k1 * v.zoom
	local hx, hy = v.h / (2 * k), v.w / (2 * k)

	return v.cx - hx, v.cx + hx, v.cy - hy, v.cy + hy
end

-- The rectangle on the screen of a world rectangle (a tile): left, top, right, bottom. The top is the largest X, the left the largest Y.
function Frame.TileRect(v, minx, miny, maxx, maxy)
	local left, top = Frame.ToScreen(v, maxx, maxy)
	local right, bottom = Frame.ToScreen(v, minx, miny)

	return left, top, right, bottom
end
