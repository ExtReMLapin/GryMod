-- The player's own objective points on the big map (GryMod.Map.Waypoints). A right click on the map (without moving the mouse) offers to put a point there, with a
-- title the player types; a right click on a point takes it away. A point is an "own" objective of this client's mirror (cl_objectives.lua, Obj.ApplyOwn): it
-- is a secondary objective, so the big map, the minimap and the compass radar draw it, and the markers of the binoculars show it, with no code of their own for it.
-- It is PRIVATE: the server never knows it and nobody else sees it. The points are kept in a text file a map (data/grymod/waypoints/<map>.txt) and come back
-- when the map is played again. The switch gry_map_waypoints turns the whole thing off (the points stay in the file).
-- This file holds the rules (the title, the file, the ground under a click, the list, the pick under the mouse); the menu and the input are in panel.lua.

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}
GryMod.Map.Waypoints = GryMod.Map.Waypoints or {}

local W = GryMod.Map.Waypoints

W.PREFIX = "gry_user_" -- the id of a point is this and a number (an id the server's objectives never use)
W.MAX = 32 -- the points a map keeps at most (the map and the radar walk the list at every frame)
W.TITLE_MAX = 128 -- bytes: the limit of an objective's title (sh_objectives.lua)
W.HEADER = "GRYWP 1" -- the first line of the file: the format and its version
W.DIR = "grymod/waypoints"
W.GROUND_STEPS = 8 -- how many sky brushes the search for the ground goes through at most

-- The points live through a reload of this file: {id, x, y, z, title} in the order they were made.
local items = W._items or {}
local counter = W._counter or {next = 1}

W._items, W._counter = items, counter

-- The disk, as functions: the tests put their own in W.IO.
W.IO = W.IO or {
	Read = function(path)
		return file.Read(path, "DATA")
	end,
	Write = function(path, text)
		file.CreateDir(W.DIR)
		file.Write(path, text)
	end
}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- the switch ------------------------------------------------------------------------------------------------------------------------------------------------

function W.Enabled()
	local Settings = GryMod.Map.Settings

	if Settings and Settings.Waypoints then
		return Settings.Waypoints()
	end

	return true
end

-- the title ---------------------------------------------------------------------------------------------------------------------------------------------------

-- The title a text becomes: control characters, line breaks and tabs are spaces, runs of spaces are one, trimmed, cut at 128 bytes on a whole character. nil for an
-- empty text or a value that is not a text.
function W.CleanTitle(text)
	if type(text) ~= "string" then
		return nil
	end

	text = string.gsub(text, "[%c%s]+", " ")
	text = string.gsub(text, "^ ", "")
	text = string.gsub(text, " $", "")

	if text == "" then
		return nil
	end

	if #text > W.TITLE_MAX then
		local cut = W.TITLE_MAX

		-- never in the middle of a multi-byte character: back to the byte that starts it
		while cut > 0 do
			local byte = string.byte(text, cut + 1)

			if byte and byte >= 0x80 and byte < 0xC0 then
				cut = cut - 1
			else
				break
			end
		end

		text = string.gsub(string.sub(text, 1, cut), " $", "")
	end

	return text
end

-- The title of a point that was given none: its grid cell ("Point C4").
function W.DefaultTitle(cell)
	if type(cell) == "string" and cell ~= "" then
		return "Point " .. cell
	end

	return "Point"
end

-- the file ------------------------------------------------------------------------------------------------------------------------------------------------------
-- A text: the header, then a line a point: x, y, z, the title, separated by tabs (a title has no tab: CleanTitle). A damaged line is dropped, never an error.

-- The path of the file of a map: only letters, digits, underscore and dash of the name are kept (anything else is an underscore: no way out of the folder).
function W.PathFor(mapName)
	local name = type(mapName) == "string" and mapName ~= "" and string.gsub(mapName, "[^%w_%-]", "_") or "map"

	return W.DIR .. "/" .. name .. ".txt"
end

function W.Path()
	return W.PathFor(game.GetMap())
end

-- The text of a list of points ({x, y, z, title}).
function W.Encode(list)
	local lines = {W.HEADER}

	for i = 1, #list do
		local it = list[i]

		lines[#lines + 1] = string.format("%.1f\t%.1f\t%.1f\t%s", it.x, it.y, it.z, it.title)
	end

	return table.concat(lines, "\n") .. "\n"
end

-- The points of a text: {{x, y, z, title}, ...}, MAX at most. Nothing for a text with no header or another version.
function W.Decode(text)
	local out = {}

	if type(text) ~= "string" then
		return out
	end

	local first = true

	for line in string.gmatch(text, "[^\n]+") do
		line = string.gsub(line, "\r$", "")

		if first then
			first = false

			if line ~= W.HEADER then
				return out
			end
		elseif #out < W.MAX then
			local x, y, z, title = string.match(line, "^([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")

			x, y, z = tonumber(x), tonumber(y), tonumber(z)
			title = W.CleanTitle(title)

			if title and finite(x) and finite(y) and finite(z) then
				out[#out + 1] = {x = x, y = y, z = z, title = title}
			end
		end
	end

	return out
end

-- Writes the file of this map. Nothing is raised: a disk that refuses loses the points of the next session, not the game.
function W.Save()
	local ok, err = pcall(function()
		W.IO.Write(W.Path(), W.Encode(items))
	end)

	if not ok and ErrorNoHalt then
		ErrorNoHalt("[GryMod] the objective points could not be saved: " .. tostring(err) .. "\n")
	end

	return ok
end

-- the ground ------------------------------------------------------------------------------------------------------------------------------------------------------

-- The z of the first solid surface under (x, y), from `zTop` down to `zBottom`: what the picture of the map shows at that place (it is a view from above,
-- cut at the top of the level shown). `trace(x, y, fromZ, toZ)` gives a trace result {Hit, HitSky, HitPos} (the panel's is a line trace against the brushes of
-- the world). A sky brush is passed through. nil when there is nothing (outside the world, or too many sky brushes): the caller takes the height of the player.
function W.GroundAt(x, y, zTop, zBottom, trace)
	local from = zTop

	for _ = 1, W.GROUND_STEPS do
		if from <= zBottom then
			return nil
		end

		local tr = trace(x, y, from, zBottom)

		if type(tr) ~= "table" or not tr.Hit then
			return nil
		end

		if tr.StartSolid then
			from = from - 64
		elseif tr.HitSky then
			from = tr.HitPos.z - 8
		else
			return tr.HitPos.z
		end
	end

	return nil
end

-- the mirror ----------------------------------------------------------------------------------------------------------------------------------------------------------

local function objectives()
	return GryMod.Objectives
end

local function register(it)
	local Obj = objectives()

	if Obj and Obj.ApplyOwn then
		Obj.ApplyOwn({
			id = it.id, title = it.title, description = "", primary = false, state = "active", main = false, radar = true, marker = true,
			pos = Vector(it.x, it.y, it.z), entIndex = 0
		})
	end
end

local function unregister(id)
	local Obj = objectives()

	if Obj and Obj.RemoveOwn then
		Obj.RemoveOwn(id)
	end
end

-- Puts the mirror as the switch says: every point in it when on, none when off (the list and the file keep them).
function W.Apply()
	local on = W.Enabled()

	for i = 1, #items do
		if on then
			register(items[i])
		else
			unregister(items[i].id)
		end
	end
end

-- Forgets every point of this session, in the list and in the mirror (the file is not touched). For the tests and a reload.
function W.Reset()
	for i = #items, 1, -1 do
		unregister(items[i].id)
		items[i] = nil
	end

	counter.next = 1
end

-- The points: the array of {id, x, y, z, title} (the module's own: read it, do not change it).
function W.List()
	return items
end

local function newId()
	local id = W.PREFIX .. counter.next

	counter.next = counter.next + 1

	return id
end

-- Reads the file of this map and puts its points in the list and the mirror (the ones of before are dropped). Returns how many.
function W.Load()
	W.Reset()

	local ok, text = pcall(W.IO.Read, W.Path())
	local list = ok and W.Decode(text) or {}

	for i = 1, #list do
		local it = list[i]

		it.id = newId()
		items[#items + 1] = it
	end

	W.Apply()

	return #items
end

-- Puts a point at (x, y, z) with a title. Returns its id, or false and why.
function W.Add(x, y, z, title)
	if not W.Enabled() then
		return false, "the objective points are switched off (gry_map_waypoints 0)"
	end

	if not (finite(x) and finite(y) and finite(z)) then
		return false, "no position"
	end

	local clean = W.CleanTitle(title)

	if not clean then
		return false, "the title is empty"
	end

	if #items >= W.MAX then
		return false, "too many points on this map (" .. W.MAX .. " at most)"
	end

	local it = {id = newId(), x = x, y = y, z = z, title = clean}

	items[#items + 1] = it
	register(it)
	W.Save()

	return it.id
end

-- Takes a point away. Returns false for an id that is not one of the player's points (an objective of the server is never touched).
function W.Remove(id)
	for i = 1, #items do
		if items[i].id == id then
			table.remove(items, i)
			unregister(id)
			W.Save()

			return true
		end
	end

	return false
end

-- Takes every point of this map away. Returns how many.
function W.Clear()
	local count = #items

	for i = count, 1, -1 do
		unregister(items[i].id)
		items[i] = nil
	end

	W.Save()

	return count
end

-- The point nearest to the screen position (sx, sy) in a view of the big map, within `radius` pixels: its id, or nil.
function W.Pick(view, sx, sy, radius)
	if not W.Enabled() then
		return nil
	end

	local Frame = GryMod.Map.Frame
	local best, bestD = nil, radius * radius

	for i = 1, #items do
		local px, py = Frame.ToScreen(view, items[i].x, items[i].y)
		local dx, dy = px - sx, py - sy
		local d = dx * dx + dy * dy

		if d <= bestD then
			best, bestD = items[i].id, d
		end
	end

	return best
end

-- the hooks ---------------------------------------------------------------------------------------------------------------------------------------------------------

-- the points of a map come back when the map starts (no Think, no timer)
hook.Add("InitPostEntity", "GryMapWaypoints", function()
	W.Load()
end)

cvars.AddChangeCallback("gry_map_waypoints", function()
	W.Apply()
end, "GryMapWaypoints")

-- a file loaded in a game that is already running (a reload, an update)
if #items == 0 then
	W.Load()
end
