-- GryMod minimap: module settings. Filled by its owner agent (see docs/superpowers/specs/2026-11-21-minimap-design.md).
-- Eight saved client convars and the accessors the other modules use. Whatever the convar holds (the player can type anything in the console
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
local DEFAULT_BELOW = 40
local DEFAULT_OUTSIDE = 30
local DEFAULT_OPACITY = 90
local DEFAULT_CACHE_MB = 256
local BYTES_PER_MB = 1048576

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
local BelowConVar = GetConVar("gry_minimap_below") or CreateClientConVar("gry_minimap_below", "40", true, false,
	"Opacity in percent of the floor below, seen through the empty parts of the current floor (0 = off)", 0, 100)
local OutsideConVar = GetConVar("gry_minimap_outside") or CreateClientConVar("gry_minimap_outside", "30", true, false,
	"Opacity in percent of the outside (the whole height of the map) seen through the voids of the floors, under the floor below (0 = off)", 0, 100)
local CacheMBConVar = GetConVar("gry_minimap_cache_mb") or CreateClientConVar("gry_minimap_cache_mb", "256", true, false,
	"Size limit in megabytes of the minimap cache of one map; the oldest tiles are deleted above it", 16, 4096)
local OpacityConVar = GetConVar("gry_minimap_opacity") or CreateClientConVar("gry_minimap_opacity", "90", true, false,
	"Opacity in percent of the minimap background in the radar (the floor below uses its own setting on top of it)", 0, 100)

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

-- Opacity of the floor below, from 0 to 1: a whole percent from 0 to 100, divided by 100. No number: the default percent.
function Settings.ParseBelow(text)
	local n = number(text)

	if n == nil then
		n = DEFAULT_BELOW
	end

	return math.floor(clamp(n, 0, 100) + 0.5) / 100
end

-- Opacity of the outside (the open level, drawn under everything else), from 0 to 1: a whole percent from 0 to 100, divided by 100. No number: the
-- default percent.
function Settings.ParseOutside(text)
	local n = number(text)

	if n == nil then
		n = DEFAULT_OUTSIDE
	end

	return math.floor(clamp(n, 0, 100) + 0.5) / 100
end

-- The size limit of the cache of one map, in whole megabytes from 16 to 4096. No number: the default.
function Settings.ParseCacheMB(text)
	local n = number(text)

	if n == nil then
		return DEFAULT_CACHE_MB
	end

	return math.floor(clamp(n, 16, 4096) + 0.5)
end

-- Opacity of the map in the radar, from 0 to 1: a whole percent from 0 to 100, divided by 100. No number: the default percent.
function Settings.ParseOpacity(text)
	local n = number(text)

	if n == nil then
		n = DEFAULT_OPACITY
	end

	return math.floor(clamp(n, 0, 100) + 0.5) / 100
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

function Settings.Below()
	return Settings.ParseBelow(BelowConVar:GetString())
end

function Settings.Outside()
	return Settings.ParseOutside(OutsideConVar:GetString())
end

-- The same limit in bytes (what the cache compares the size of its files with).
function Settings.CacheBytes()
	return Settings.ParseCacheMB(CacheMBConVar:GetString()) * BYTES_PER_MB
end

function Settings.Opacity()
	return Settings.ParseOpacity(OpacityConVar:GetString())
end
