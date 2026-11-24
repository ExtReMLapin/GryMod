-- The pure part of the smooth bars of the HUD (the suit's energy and health bars, the night vision's energy bar). No game global: numbers in, numbers out,
-- so that it is tested in a plain LuaJIT (tools/test_flash_bar.py), on the real data of the converted movies.
--
-- THE PROBLEM. The movies draw a bar at one of its 100 frames (the value of the bar, rounded down), and one frame is one percent of the bar: on a screen
-- where the bar is more than 100 pixels wide, a step is more than a pixel and the bar is seen to jump. The value itself is a float that moves at every
-- frame; only the drawing quantises it.
--
-- THE METHOD. A frame of such a bar is the same picture with its fill longer: the movie's sprite has a MASK (a morph shape, a rectangle whose left edge
-- goes from the right end of the bar to its left end as the frame goes up) and the fill drawn through it. So a value between two frames is the two
-- pictures of the frames, cut by a vertical line at the x between their two edges: the picture of the frame under it on the track side of the line, the
-- picture of the frame over it on the fill side. Nothing is computed about the shapes, the colours or the matrices (the red of a low night vision
-- energy, the colours of the theme are the integer frame's own); the line's x is the only new number, and it is
-- lerp(edge[frame], edge[frame + 1], fraction). The player (cl_flash.lua, cl_flash_draw.lua) draws the two images of the frames, the cached ones, and cuts
-- the quad of each at the line: no polygon, no table, nothing allocated at a frame.
--
-- WHAT IS HERE: the value to a position on the frames (Position), the position to a frame and a fraction (Split), the grid the position is rounded to
-- (Subdivisions, Quantise), the table of the edges of a bar clip read once from its movie (Edges), and the line's x (Cut).

local Bar = {}

-- The number of steps of the grid is at most this (a step of the grid is half a pixel at most).
Bar.MAX_DIVISIONS = 16

-- Whether x is a number that is not NaN.
local function isNumber(x)
	return type(x) == "number" and x == x
end

-- A position (frames from 1, a float) to the integer frame and the fraction between it and the next one. The first frame is 1 and the last has no
-- next one (the fraction is 0 there); anything that is not a number is the first frame.
function Bar.Split(position, n)
	if not isNumber(position) or not isNumber(n) or n < 1 or position <= 1 then
		return 1, 0
	end

	if position >= n then
		return n, 0
	end

	local frame = math.floor(position)

	return frame, position - frame
end

-- The position on the frames of a value of a bar: value + offset, held between 1 and n. The suit's energy bar shows frame floor(energy) (offset 0, 100
-- frames: 0 and 1 are both the first frame), the night vision's shows floor(value) + 1 (offset 1, 102 frames).
function Bar.Position(value, offset, n)
	if not isNumber(value) then
		return 1
	end

	local position = value + (offset or 0)

	if position < 1 then
		return 1
	end

	if position > n then
		return n
	end

	return position
end

-- The number of steps of the grid a position is rounded to for a bar whose step (a frame) is `stepPixels` wide on the screen: 1, which is the
-- original's whole steps, when a step is one pixel or less (nothing to smooth), else enough for a step of the grid to be half a pixel at most.
function Bar.Subdivisions(stepPixels, limit)
	if not isNumber(stepPixels) or stepPixels <= 1 then
		return 1
	end

	return math.min(limit or Bar.MAX_DIVISIONS, math.ceil(stepPixels * 2))
end

-- The position rounded to the grid of `divisions` steps a frame. A grid of 1 is the original's drawing: the frame, rounded down. A position that is a
-- whole frame stays it on any grid.
function Bar.Quantise(position, divisions)
	if not isNumber(position) or position < 1 then
		return 1
	end

	if not isNumber(divisions) or divisions <= 1 then
		return math.floor(position)
	end

	return math.floor(position * divisions + 0.5) / divisions
end

-- The table of the edges of a bar clip, read once from the movie: `definition` is the sprite (frames, n) and `chars` the characters of the movie. The clip
-- masks its fill with a morph shape (an operation with a clip depth); its ratio at each frame comes from the operations that move it, and the edge is
-- the x, in the clip's own coordinates, of the side of the mask outline that goes from the one end of the bar to the other. Returns
--   edge[frame] the x of the fill's edge, n the number of frames, y the middle of the mask outline (the line is cut there), step the x a frame moves,
--   side +1 when the fill is on the larger x side of the edge (the edge moves towards the smaller x as the frame goes up), -1 when it is on the smaller,
--   depth the mask's depth in the clip,
-- or nil for a clip that has no mask.
function Bar.Edges(definition, chars)
	local frames, n = definition and definition.frames, definition and definition.n

	if not frames or not isNumber(n) or n < 2 then
		return nil
	end

	-- the mask: the first operation with a clip depth whose character is a morph with a start and an end outline
	local depth, morph

	for f = 1, n do
		local frame = frames[f]

		for i = 1, frame and #frame or 0 do
			local op = frame[i]
			local char = op.cd and op.c and chars[op.c]

			if char and char.p and char.pe and not depth then
				depth, morph = op.d, char
			end
		end

		if depth then
			break
		end
	end

	if not depth then
		return nil
	end

	local from, to = morph.p, morph.pe
	local left, right = {}, {}
	local ratio = 0

	for f = 1, n do
		local frame = frames[f]

		for i = 1, frame and #frame or 0 do
			local op = frame[i]

			if op.d == depth and op.r then
				ratio = op.r
			end
		end

		local t = ratio / 65535
		local lo, hi = math.huge, -math.huge

		for k = 1, #from, 2 do
			local x = from[k] + (to[k] - from[k]) * t

			if x < lo then
				lo = x
			end

			if x > hi then
				hi = x
			end
		end

		left[f], right[f] = lo, hi
	end

	-- the edge that travels: the other one stays about where it is
	local edge = math.abs(left[n] - left[1]) >= math.abs(right[n] - right[1]) and left or right
	local sumY = 0

	for k = 2, #to, 2 do
		sumY = sumY + to[k]
	end

	return {
		edge = edge,
		n = n,
		y = sumY / (#to / 2),
		step = math.abs(edge[n] - edge[1]) / (n - 1),
		side = edge[n] < edge[1] and 1 or -1,
		depth = depth
	}
end

-- The x of the cut line for a frame and a fraction of the way to the next: the edge of the frame on a whole step, between the two edges otherwise.
function Bar.Cut(edges, frame, fraction)
	local edge = edges.edge

	if frame >= edges.n or not (fraction > 0) then
		return edge[frame]
	end

	return edge[frame] + (edge[frame + 1] - edge[frame]) * fraction
end

return Bar
