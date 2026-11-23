-- The big map: the rules of its zoom (GryMod.Map.Zoom). Pure maths, no engine call, so it can be tested without a game.
-- The numbers are the original game's (CryGame.dll of the Crysis demo, `FUN_391bfad0` and `FUN_391bfb50`): the zoom goes from 1 (the whole map
-- fills the window) to 8; a notch of the mouse wheel is z' = 1.35 z - 0.25 in and z' = z / (1.35 - 0.25 / z) out (eleven notches from 1 to 8);
-- holding the middle button and moving the mouse up and down is a smooth zoom of 0.03 a pixel.

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}
GryMod.Map.Zoom = GryMod.Map.Zoom or {}

local Zoom = GryMod.Map.Zoom

Zoom.MIN = 1
Zoom.MAX = 8
Zoom.ANALOG_PER_PIXEL = 0.03

-- The first opening of a map: the whole bounds when their long side is up to this many metres, else a window of AUTO_WINDOW_METRES.
Zoom.AUTO_FIT_MAX_METRES = 1000
Zoom.AUTO_WINDOW_METRES = 800

local function isNumber(n)
	return type(n) == "number" and n == n
end

-- The zoom inside its limits; anything that is not a number is 1 (the whole map).
function Zoom.Clamp(z)
	if not isNumber(z) then
		return Zoom.MIN
	end

	if z < Zoom.MIN then
		return Zoom.MIN
	end

	if z > Zoom.MAX then
		return Zoom.MAX
	end

	return z
end

-- One wheel notch in: 1.35 z - 0.25 (the first notch is +10 percent, the last +30).
function Zoom.StepIn(z)
	z = Zoom.Clamp(z)

	return Zoom.Clamp(1.35 * z - 0.25)
end

-- One wheel notch out: z / (1.35 - 0.25 / z). It is not the exact inverse of StepIn (the original's rule): it goes down for any zoom above 1.
function Zoom.StepOut(z)
	z = Zoom.Clamp(z)

	return Zoom.Clamp(z / (1.35 - 0.25 / z))
end

-- A wheel event: a positive direction zooms in, a negative one out, nothing else changes the zoom.
function Zoom.Step(z, direction)
	if not isNumber(direction) or direction == 0 then
		return Zoom.Clamp(z)
	end

	if direction > 0 then
		return Zoom.StepIn(z)
	end

	return Zoom.StepOut(z)
end

-- The middle button held while the mouse moves `dy` pixels (negative: up): 0.03 a pixel, up zooms in.
function Zoom.Analog(z, dy)
	if not isNumber(dy) then
		return Zoom.Clamp(z)
	end

	return Zoom.Clamp(Zoom.Clamp(z) - dy * Zoom.ANALOG_PER_PIXEL)
end

-- The zoom of the first opening of a map: 1 (the whole bounds) when the long side is up to AUTO_FIT_MAX_METRES, else the zoom that shows a
-- window of AUTO_WINDOW_METRES (the long side over the window), at most 8. No usable size gives 1.
function Zoom.Auto(longSideMetres)
	if not isNumber(longSideMetres) or longSideMetres <= Zoom.AUTO_FIT_MAX_METRES then
		return Zoom.MIN
	end

	return Zoom.Clamp(longSideMetres / Zoom.AUTO_WINDOW_METRES)
end

-- The saved zoom (the convar gry_map_zoom) as a number inside the limits; a text that is no number gives 1.
function Zoom.ParseSaved(text)
	return Zoom.Clamp(tonumber(text))
end
