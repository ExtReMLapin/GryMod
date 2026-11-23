-- The big map: its bounds (GryMod.Map.Bounds). The picture of the map stops at these limits, so they are the hard limit of the pan. The original
-- game writes them in the level's file; GMod has no such file, so they come from what the addon already knows of the map, in this order of trust:
--   1. the ground nodes of the AI node graph (maps/graphs/<map>.ain, GryMod.AIN), when there are at least MIN_NODES of them;
--   2. the boxes of the in/out map (GryMod.ZoneMapClient.Boxes()), joined with the nodes when both exist;
--   3. the box of the world (game.GetWorld():GetModelBounds(), x and y), which is often far larger than the playable area;
--   4. a square of FALLBACK_HALF units around the player; and a square around the origin when even that is unknown.
-- The result is padded (5 percent, at least 1024 units), cut at the world's box when that leaves a usable map, widened to MIN_SIDE units, and always
-- holds the player. Pure: everything is given as plain tables, nothing is read from the engine here.

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}
GryMod.Map.Bounds = GryMod.Map.Bounds or {}

local Bounds = GryMod.Map.Bounds

Bounds.GROUND = 2 -- the type of a ground node
Bounds.MIN_NODES = 8
Bounds.CELL = 128 -- the size of a cell of the in/out map, in units
Bounds.PAD_MIN = 1024
Bounds.PAD_FRACTION = 0.05
Bounds.MIN_SIDE = 5249 -- about 100 m
Bounds.FALLBACK_HALF = 13123 -- about 250 m each side of the player
Bounds.PLAYER_MARGIN = 512
Bounds.METRES_PER_UNIT = 0.01905

local function finite(n)
	return type(n) == "number" and n - n == 0
end

-- The extent of the usable points: x0, x1, y0, y1, count (nil when none).
local function extendPoint(box, x, y)
	if x < box.x0 then box.x0 = x end
	if x > box.x1 then box.x1 = x end
	if y < box.y0 then box.y0 = y end
	if y > box.y1 then box.y1 = y end
end

local function newBox()
	return {x0 = math.huge, x1 = -math.huge, y0 = math.huge, y1 = -math.huge, count = 0}
end

-- The box of the ground nodes (nil when fewer than MIN_NODES).
local function nodesBox(nodes)
	if type(nodes) ~= "table" then
		return nil
	end

	local box = newBox()

	for i = 1, #nodes do
		local n = nodes[i]

		if type(n) == "table" and n.type == Bounds.GROUND and finite(n.x) and finite(n.y) then
			extendPoint(box, n.x, n.y)
			box.count = box.count + 1
		end
	end

	if box.count < Bounds.MIN_NODES then
		return nil
	end

	return box
end

-- A box of the in/out map: {layer, x1, y1, x2, y2, ...} or with the names; x2 and y2 are the LAST cell, so the box ends one cell further.
local function field(box, name, at)
	local value = box[name]

	if value == nil then
		value = box[at]
	end

	return value
end

local function zonesBox(boxes)
	if type(boxes) ~= "table" then
		return nil
	end

	local out = newBox()
	local cell = Bounds.CELL

	for i = 1, #boxes do
		local b = boxes[i]

		if type(b) == "table" then
			local cx1, cy1, cx2, cy2 = field(b, "x1", 2), field(b, "y1", 3), field(b, "x2", 4), field(b, "y2", 5)

			if finite(cx1) and finite(cy1) and finite(cx2) and finite(cy2) then
				extendPoint(out, cx1 * cell, cy1 * cell)
				extendPoint(out, (cx2 + 1) * cell, (cy2 + 1) * cell)
				out.count = out.count + 1
			end
		end
	end

	if out.count == 0 then
		return nil
	end

	return out
end

local function worldBox(world)
	if type(world) ~= "table" or not (finite(world.x0) and finite(world.x1) and finite(world.y0) and finite(world.y1)) then
		return nil
	end

	if world.x1 <= world.x0 or world.y1 <= world.y0 then
		return nil
	end

	return {x0 = world.x0, x1 = world.x1, y0 = world.y0, y1 = world.y1}
end

-- The bounds {x0, x1, y0, y1, source} from {nodes, boxes, world, player}, every field optional. Never raises. `source` says where the box came from:
-- "nodes", "zones" (the boxes, with or without the nodes), "world", "player" or "default".
function Bounds.Compute(input)
	input = type(input) == "table" and input or {}

	local nodes, zones = nodesBox(input.nodes), zonesBox(input.boxes)
	local world = worldBox(input.world)
	local px, py

	if type(input.player) == "table" and finite(input.player.x) and finite(input.player.y) then
		px, py = input.player.x, input.player.y
	end

	local box, source

	if nodes or zones then
		box = newBox()

		for _, part in ipairs({nodes or false, zones or false}) do
			if part then
				extendPoint(box, part.x0, part.y0)
				extendPoint(box, part.x1, part.y1)
			end
		end

		source = nodes and "nodes" or "zones"
	elseif world then
		box, source = {x0 = world.x0, x1 = world.x1, y0 = world.y0, y1 = world.y1}, "world"
	elseif px then
		local half = Bounds.FALLBACK_HALF

		box, source = {x0 = px - half, x1 = px + half, y0 = py - half, y1 = py + half}, "player"
	else
		local half = Bounds.FALLBACK_HALF

		box, source = {x0 = -half, x1 = half, y0 = -half, y1 = half}, "default"
	end

	if source == "nodes" or source == "zones" then
		-- the margin: 5 percent of the long side, at least PAD_MIN
		local pad = math.max(Bounds.PAD_MIN, Bounds.PAD_FRACTION * math.max(box.x1 - box.x0, box.y1 - box.y0))

		box.x0, box.x1, box.y0, box.y1 = box.x0 - pad, box.x1 + pad, box.y0 - pad, box.y1 + pad

		-- the world's box is the outer limit, when it leaves a usable map
		if world then
			local x0, x1 = math.max(box.x0, world.x0), math.min(box.x1, world.x1)
			local y0, y1 = math.max(box.y0, world.y0), math.min(box.y1, world.y1)

			if x1 - x0 >= Bounds.MIN_SIDE and y1 - y0 >= Bounds.MIN_SIDE then
				box.x0, box.x1, box.y0, box.y1 = x0, x1, y0, y1
			end
		end
	end

	-- the player is inside, even where the graph does not reach
	if px then
		local m = Bounds.PLAYER_MARGIN

		if px - m < box.x0 then box.x0 = px - m end
		if px + m > box.x1 then box.x1 = px + m end
		if py - m < box.y0 then box.y0 = py - m end
		if py + m > box.y1 then box.y1 = py + m end
	end

	-- not smaller than MIN_SIDE a side, around the middle
	for _, axis in ipairs({{"x0", "x1"}, {"y0", "y1"}}) do
		local lo, hi = axis[1], axis[2]

		if box[hi] - box[lo] < Bounds.MIN_SIDE then
			local middle = (box[lo] + box[hi]) / 2

			box[lo], box[hi] = middle - Bounds.MIN_SIDE / 2, middle + Bounds.MIN_SIDE / 2
		end
	end

	return {x0 = box.x0, x1 = box.x1, y0 = box.y0, y1 = box.y1, source = source}
end

-- The long side of the bounds in metres (0 for anything that is not bounds).
function Bounds.SpanMetres(b)
	if type(b) ~= "table" or not (finite(b.x0) and finite(b.x1) and finite(b.y0) and finite(b.y1)) then
		return 0
	end

	return math.max(b.x1 - b.x0, b.y1 - b.y0) * Bounds.METRES_PER_UNIT
end
