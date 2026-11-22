-- GryMod minimap: module settings. Filled by its owner agent (see docs/superpowers/specs/2026-11-21-minimap-design.md).
-- Nine saved client convars and the accessors the other modules use. The definition (pixels per metre of the tiles) is either the slider's value or,
-- when gry_minimap_definition_auto is on, a level of a pyramid (2, 4, 8, 16, 32, 64) that the radar picks from the range and the screen: Definition()
-- gives the one in use, so Gen, View, Cache and Capture need not know which of the two it is. Whatever the convar holds (the player can type anything in the console
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
local DEFAULT_OUTSIDE = 80
local DEFAULT_OPACITY = 90
local DEFAULT_CACHE_MB = 768
local BYTES_PER_MB = 1048576

-- the tile sizes the capture and the cache know (powers of two, see the design)
local TILE_SIZES = {512, 1024, 2048}

-- these are the saved settings of the minimap: GetConVar first, so that a hot reload of this file keeps the same convars
local EnabledConVar = GetConVar("gry_minimap") or CreateClientConVar("gry_minimap", "1", true, false,
	"Draw the map of the level behind the radar (1) or not (0)", 0, 1)
local DefinitionConVar = GetConVar("gry_minimap_definition") or CreateClientConVar("gry_minimap_definition", "3", true, false,
	"Pixels per metre of the map tiles (1 to 64, whole numbers), used when gry_minimap_definition_auto is 0. The distance the radar shows is gry_radar_range", 1, 64)
local DefinitionAutoConVar = GetConVar("gry_minimap_definition_auto") or CreateClientConVar("gry_minimap_definition_auto", "1", true, false,
	"Choose the definition of the map by itself from the radar range and the screen (1), or use gry_minimap_definition (0)", 0, 1)
local TileConVar = GetConVar("gry_minimap_tile") or CreateClientConVar("gry_minimap_tile", "1024", true, false,
	"Size of one map tile in pixels: 512, 1024 or 2048 (another number is taken to the nearest of these)", 512, 2048)
local BudgetConVar = GetConVar("gry_minimap_budget_ms") or CreateClientConVar("gry_minimap_budget_ms", "6", true, false,
	"Milliseconds per frame the map generator may use (1 to 30). One capture of a tile (about 7 ms) may exceed it", 1, 30)
local BelowConVar = GetConVar("gry_minimap_below") or CreateClientConVar("gry_minimap_below", "40", true, false,
	"Opacity in percent of the floor below, seen through the empty parts of the current floor (0 = off)", 0, 100)
local OutsideConVar = GetConVar("gry_minimap_outside") or CreateClientConVar("gry_minimap_outside", "80", true, false,
	"Opacity in percent of the outside (the whole height of the map) seen through the voids of the floors, under the floor below (0 = off)", 0, 100)
local CacheMBConVar = GetConVar("gry_minimap_cache_mb") or CreateClientConVar("gry_minimap_cache_mb", "768", true, false,
	"Size limit in megabytes of the minimap cache of one map; the oldest tiles are deleted above it", 16, 4096)
local OpacityConVar = GetConVar("gry_minimap_opacity") or CreateClientConVar("gry_minimap_opacity", "90", true, false,
	"Opacity in percent of the minimap background in the radar (the floor below uses its own setting on top of it)", 0, 100)

local VeilDiscoveryConVar = GetConVar("gry_minimap_veil_discovery") or CreateClientConVar("gry_minimap_veil_discovery", "0", true, false,
	"Show the noise veil and the percentage whenever the map tile under the player is missing (1, the old behaviour), or only when there is nothing to show (0, the default: while the map is discovered the last picture stays and the new tile comes when it is ready)", 0, 1)

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

-- The veil in discovery: the whole part of the number is not 0 (1: the old veil whenever the tile under the player is missing). No number: the default (0, no veil).
function Settings.ParseVeilDiscovery(text)
	local n = number(text)

	if n == nil then
		return false
	end

	return n >= 1 or n <= -1
end

-- Pixels per metre: a whole number from 1 to 64 (a half rounds up).
function Settings.ParseDefinition(text)
	local n = number(text)

	if n == nil then
		return DEFAULT_DEFINITION
	end

	return math.floor(clamp(n, 1, 64) + 0.5)
end

-- The automatic definition switch: read as the other switches (the default, on, for a text that is no number).
function Settings.ParseDefinitionAuto(text)
	return Settings.ParseSwitch(text)
end

-- The pyramid of the automatic definition: the levels of pixels per metre it chooses from. Each has its own tiles (the definition is in the name of a tile).
Settings.AUTO_LEVELS = {2, 4, 8, 16, 32, 64}

-- The level the radar starts with, before it has calculated one.
local AUTO_START = 4
-- A level is the smallest one that has at least this share of the density of the screen (the texture is stretched 1 / 0.7 = 1.43 times at most)...
local AUTO_FIT = 0.7
-- ...and the level in use is kept while the density of the screen stays between these multiples of it (a range slider that is dragged does not make the
-- map again at every step: a level chosen by the rule is always inside this band, so two changes never follow each other for a density that goes back
-- and forth around an edge).
local AUTO_KEEP_LOW, AUTO_KEEP_HIGH = 0.6, 1.6

-- The state of the automatic level, kept by the module (public for the tests): the level the radar calculated last, and the one before it (nil at the start)
-- for the radar to go on drawing its tiles while the new ones are made. A hot reload of this file keeps it.
Settings.AutoState = Settings.AutoState or {current = AUTO_START, previous = nil}

local function isLevel(ppm)
	for i = 1, #Settings.AUTO_LEVELS do
		if Settings.AUTO_LEVELS[i] == ppm then
			return true
		end
	end

	return false
end

-- The level of the pyramid for a screen that shows `screenPixelsPerMetre` pixels per metre of ground (the radar's pixels per metre times the screen's pixels
-- per radar pixel), given the level in use `previousPpm`: the level in use while the density is within 0.6 to 1.6 times it, else the smallest level of at
-- least 0.7 times the density, bounded by the ends of the pyramid. A density that is no positive number, or no level in use, gives the level in use, or the
-- start level (4). Pure.
function Settings.AutoDefinitionFor(screenPixelsPerMetre, previousPpm)
	local levels = Settings.AUTO_LEVELS
	local usable = type(previousPpm) == "number" and isLevel(previousPpm)

	if type(screenPixelsPerMetre) ~= "number" or screenPixelsPerMetre ~= screenPixelsPerMetre or screenPixelsPerMetre <= 0 then
		return usable and previousPpm or AUTO_START
	end

	if usable and screenPixelsPerMetre >= previousPpm * AUTO_KEEP_LOW and screenPixelsPerMetre <= previousPpm * AUTO_KEEP_HIGH then
		return previousPpm
	end

	local wanted = screenPixelsPerMetre * AUTO_FIT

	for i = 1, #levels do
		if levels[i] >= wanted then
			return levels[i]
		end
	end

	return levels[#levels]
end

-- The radar gives the level it calculated (at every frame): only a level of the pyramid is taken (true), anything else is ignored (false). A change of level
-- keeps the one it replaces as the previous level.
function Settings.SetAutoDefinition(ppm)
	if type(ppm) ~= "number" or not isLevel(ppm) then
		return false
	end

	local state = Settings.AutoState

	if state.current ~= ppm then
		state.previous = state.current
		state.current = ppm
	end

	return true
end

-- The screen constant: the density of the screen (pixels per metre of ground) times the range in metres, the same whatever the range (the radar's pixels per metre
-- times the screen's pixels per radar pixel). The radar records it at every draw; the tile preload reads it to know which definition each zoom range will get without
-- a radar to ask (the density at a range r is k / r). nil until the radar has drawn once. Kept by the module across a hot reload.
Settings.ScreenK = Settings.ScreenK

-- Only a positive finite number is taken (true); anything else is refused (false) and the value in use stays.
function Settings.SetScreenConstant(k)
	if type(k) ~= "number" or k ~= k or k <= 0 or k == math.huge then
		return false
	end

	Settings.ScreenK = k

	return true
end

function Settings.ScreenConstant()
	return Settings.ScreenK
end

-- The level used before the current automatic one (the radar draws its tiles under the new ones until the new ones exist), or nil: at the start, and
-- whenever the automatic definition is off (the slider's value has no pyramid).
function Settings.PreviousDefinition()
	if not Settings.DefinitionAuto() then
		return nil
	end

	local previous = Settings.AutoState.previous

	if previous ~= nil and previous ~= Settings.AutoState.current and isLevel(previous) then
		return previous
	end

	return nil
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

-- true: the old behaviour (the noise veil as soon as the tile under the player is missing); false (the default): the discovery mode (the veil only for a real loading).
function Settings.VeilInDiscovery()
	return Settings.ParseVeilDiscovery(VeilDiscoveryConVar:GetString())
end

function Settings.DefinitionAuto()
	return Settings.ParseDefinitionAuto(DefinitionAutoConVar:GetString())
end

-- The definition in use: the level the radar calculated when the automatic definition is on, else the slider's.
function Settings.Definition()
	if Settings.DefinitionAuto() then
		return Settings.AutoState.current
	end

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
