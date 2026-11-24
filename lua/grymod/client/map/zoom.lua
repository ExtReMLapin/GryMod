-- The big map: the rules of its zoom (GryMod.Map.Zoom). Pure maths, no engine call, so it can be tested without a game.
-- The numbers are the original game's (CryGame.dll of the Crysis demo, `FUN_391bfad0` and `FUN_391bfb50`): the zoom goes from 1 (the whole map
-- fills the window) to 8; a notch of the mouse wheel is z' = 1.35 z - 0.25 in and z' = z / (1.35 - 0.25 / z) out (eleven notches from 1 to 8);
-- holding the middle button and moving the mouse up and down is a smooth zoom of 0.03 a pixel.
--
-- THE LIMIT. The original's 8 is a fraction of the whole map, so on a big map it is a coarse picture (a 4 km map at 8 shows a pixel as 25 cm): the closest
-- zoom is now set by what a screen pixel covers in the world (MaxFor: 7 cm a pixel by default, the setting gry_map_zoom_cm) and is never under 8, so a small
-- map keeps what it had. A view carries its own limit (Frame.New, view.zoomMax) and the functions below take it as their last argument, 8 when none is given.

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}
GryMod.Map.Zoom = GryMod.Map.Zoom or {}

local Zoom = GryMod.Map.Zoom

Zoom.MIN = 1
-- the original's closest zoom, and the limit of a call that is given none
Zoom.MAX = 8
-- no view goes over this, whatever the map (the saved zoom is read against it)
Zoom.ABSOLUTE_MAX = 1024
-- a world unit is this many metres (the engine's: 16 units to a foot)
Zoom.METRES_PER_UNIT = 0.01905
Zoom.ANALOG_PER_PIXEL = 0.03

-- The first opening of a map: the whole bounds when their long side is up to this many metres, else a window of AUTO_WINDOW_METRES.
Zoom.AUTO_FIT_MAX_METRES = 1000
Zoom.AUTO_WINDOW_METRES = 800

local function isNumber(n)
	return type(n) == "number" and n == n
end

-- The closest zoom of a view whose scale at zoom 1 is `k1` pixels per world unit: the zoom at which a screen pixel covers `centimetres` of the world, kept
-- from Zoom.MAX (a small map keeps the original's 8) to Zoom.ABSOLUTE_MAX. No usable number gives Zoom.MAX.
function Zoom.MaxFor(k1, centimetres)
	if not isNumber(k1) or k1 <= 0 or not isNumber(centimetres) or centimetres <= 0 then
		return Zoom.MAX
	end

	local pixelsPerUnit = Zoom.METRES_PER_UNIT / (centimetres / 100)
	local max = pixelsPerUnit / k1

	if max < Zoom.MAX then
		return Zoom.MAX
	end

	if max > Zoom.ABSOLUTE_MAX then
		return Zoom.ABSOLUTE_MAX
	end

	return max
end

-- the limit a function is given, or the default one
local function limit(max)
	if not isNumber(max) or max < Zoom.MIN then
		return Zoom.MAX
	end

	return max > Zoom.ABSOLUTE_MAX and Zoom.ABSOLUTE_MAX or max
end

-- The zoom inside its limits (1 to `max`, 8 when none is given); anything that is not a number is 1 (the whole map).
function Zoom.Clamp(z, max)
	if not isNumber(z) then
		return Zoom.MIN
	end

	if z < Zoom.MIN then
		return Zoom.MIN
	end

	max = limit(max)

	if z > max then
		return max
	end

	return z
end

-- One wheel notch in: 1.35 z - 0.25 (the first notch is +10 percent, the last +30).
function Zoom.StepIn(z, max)
	z = Zoom.Clamp(z, max)

	return Zoom.Clamp(1.35 * z - 0.25, max)
end

-- One wheel notch out: z / (1.35 - 0.25 / z). It is not the exact inverse of StepIn (the original's rule): it goes down for any zoom above 1.
function Zoom.StepOut(z, max)
	z = Zoom.Clamp(z, max)

	return Zoom.Clamp(z / (1.35 - 0.25 / z), max)
end

-- A wheel event: a positive direction zooms in, a negative one out, nothing else changes the zoom.
function Zoom.Step(z, direction, max)
	if not isNumber(direction) or direction == 0 then
		return Zoom.Clamp(z, max)
	end

	if direction > 0 then
		return Zoom.StepIn(z, max)
	end

	return Zoom.StepOut(z, max)
end

-- The middle button held while the mouse moves `dy` pixels (negative: up): 0.03 a pixel, up zooms in. Over 8 the step grows with the zoom (z / 8 times as
-- much), so that going from 8 to 60 does not take two thousand pixels of mouse.
function Zoom.Analog(z, dy, max)
	z = Zoom.Clamp(z, max)

	if not isNumber(dy) then
		return z
	end

	local rate = Zoom.ANALOG_PER_PIXEL * (z > Zoom.MAX and z / Zoom.MAX or 1)

	return Zoom.Clamp(z - dy * rate, max)
end

-- The zoom of the first opening of a map: 1 (the whole bounds) when the long side is up to AUTO_FIT_MAX_METRES, else the zoom that shows a
-- window of AUTO_WINDOW_METRES (the long side over the window), at most `max` (8 when none is given). No usable size gives 1.
function Zoom.Auto(longSideMetres, max)
	if not isNumber(longSideMetres) or longSideMetres <= Zoom.AUTO_FIT_MAX_METRES then
		return Zoom.MIN
	end

	return Zoom.Clamp(longSideMetres / Zoom.AUTO_WINDOW_METRES, max)
end

-- The saved zoom (the convar gry_map_zoom) as a number from 1 to Zoom.ABSOLUTE_MAX (the view puts it inside its own limit); a text that is no number gives 1.
function Zoom.ParseSaved(text)
	return Zoom.Clamp(tonumber(text), Zoom.ABSOLUTE_MAX)
end

-- The setting gry_map_zoom_cm (what a pixel of the screen covers at the closest zoom, in centimetres of the world) read from any text: 1 to 100, 7 by default.
Zoom.DEFAULT_CENTIMETRES = 7
Zoom.CENTIMETRES_MIN = 1
Zoom.CENTIMETRES_MAX = 100

function Zoom.ParseCentimetres(text)
	local n = tonumber(text)

	if not isNumber(n) then
		return Zoom.DEFAULT_CENTIMETRES
	end

	if n < Zoom.CENTIMETRES_MIN then
		return Zoom.CENTIMETRES_MIN
	end

	if n > Zoom.CENTIMETRES_MAX then
		return Zoom.CENTIMETRES_MAX
	end

	return n
end
