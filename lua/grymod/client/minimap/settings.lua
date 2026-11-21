-- GryMod minimap: module settings. Filled by its owner agent (see docs/superpowers/specs/2026-11-21-minimap-design.md).
-- Four saved client convars and the accessors the other modules use. Whatever the convar holds (the player can type anything in the console
-- or in a cfg file) an accessor gives a value inside its range and never nil: the Parse* functions (pure, public so that the tests can run them
-- on any text) turn the text into a number and fall back on the default when it is no number; the engine already clamps what it can, this does
-- not rely on it. There is no rotation setting: the radar's contacts always turn with the player's view, so the map always does too (a fixed
-- north would shift it away from the contacts). Nothing is cached, so a change of the convar is seen at once; nothing runs per frame by itself.
GryMod = GryMod or {}
GryMod.Minimap = GryMod.Minimap or {}
GryMod.Minimap.Settings = GryMod.Minimap.Settings or {}

local Settings = GryMod.Minimap.Settings

local DEFAULT_DEFINITION = 3
local DEFAULT_TILE = 1024
local DEFAULT_BUDGET_MS = 6

-- the tile sizes the capture and the cache know (powers of two, see the design)
local TILE_SIZES = {512, 1024, 2048}

-- these are the saved settings of the minimap: GetConVar first, so that a hot reload of this file keeps the same convars
local EnabledConVar = GetConVar("gry_minimap") or CreateClientConVar("gry_minimap", "1", true, false,
	"Draw the map of the level behind the radar (1) or not (0)", 0, 1)
local DefinitionConVar = GetConVar("gry_minimap_definition") or CreateClientConVar("gry_minimap_definition", "3", true, false,
	"Pixels per metre of the map tiles (1 to 16, whole numbers). The distance the radar shows is gry_radar_range", 1, 16)
local TileConVar = GetConVar("gry_minimap_tile") or CreateClientConVar("gry_minimap_tile", "1024", true, false,
	"Size of one map tile in pixels: 512, 1024 or 2048 (another number is taken to the nearest of these)", 512, 2048)
local BudgetConVar = GetConVar("gry_minimap_budget_ms") or CreateClientConVar("gry_minimap_budget_ms", "6", true, false,
	"Milliseconds per frame the map generator may use (1 to 30). One capture of a tile (about 7 ms) may exceed it", 1, 30)

-- The number a text holds, or nil for a text that is no number (empty, a word, nan).
local function number(text)
	local n = tonumber(text)

	if n == nil or n ~= n then
		return nil
	end

	return n
end

local function clamp(n, low, high)
	if n < low then
		return low
	elseif n > high then
		return high
	end

	return n
end

-- A switch, as the engine reads a boolean convar: the whole part of the number is not 0. No number: the default (on).
function Settings.ParseSwitch(text)
	local n = number(text)

	if n == nil then
		return true
	end

	return n >= 1 or n <= -1
end

-- Pixels per metre: a whole number from 1 to 16 (a half rounds up).
function Settings.ParseDefinition(text)
	local n = number(text)

	if n == nil then
		return DEFAULT_DEFINITION
	end

	return math.floor(clamp(n, 1, 16) + 0.5)
end

-- The tile size: the allowed size nearest to the number. A tie (768 between 512 and 1024) goes to the smaller tile, which costs less memory.
function Settings.ParseTileRes(text)
	local n = number(text)

	if n == nil then
		return DEFAULT_TILE
	end

	local best = TILE_SIZES[1]
	local bestDistance = math.abs(n - best)

	for i = 2, #TILE_SIZES do
		local distance = math.abs(n - TILE_SIZES[i])

		if distance < bestDistance then
			best, bestDistance = TILE_SIZES[i], distance
		end
	end

	return best
end

-- Milliseconds per frame for the generator: from 1 to 30, decimals allowed.
function Settings.ParseBudgetMs(text)
	local n = number(text)

	if n == nil then
		return DEFAULT_BUDGET_MS
	end

	return clamp(n, 1, 30)
end

function Settings.Enabled()
	return Settings.ParseSwitch(EnabledConVar:GetString())
end

function Settings.Definition()
	return Settings.ParseDefinition(DefinitionConVar:GetString())
end

function Settings.TileRes()
	return Settings.ParseTileRes(TileConVar:GetString())
end

function Settings.BudgetMs()
	return Settings.ParseBudgetMs(BudgetConVar:GetString())
end
