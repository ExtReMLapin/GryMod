-- The big map: its saved settings (GryMod.Map.Settings). Six client convars and the accessors the other modules use. Whatever the convar holds (the
-- player can type anything in the console or in a cfg file) an accessor gives a value of the right kind and inside its range; the Parse functions are pure
-- and take any text. The key that opens the map is made by the key factory (cl_key_binder.lua) in map/panel.lua: gry_map_key, M by default.

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}
GryMod.Map.Settings = GryMod.Map.Settings or {}

local Settings = GryMod.Map.Settings

Settings.DEFAULT_ENABLE = true
Settings.DEFAULT_ZOOM = 1
Settings.DEFAULT_FX = "glitch"
Settings.DEFAULT_FINISHED = false
Settings.DEFAULT_GRID = true
Settings.DEFAULT_CHROME = true
Settings.DEFAULT_WAYPOINTS = true

-- GetConVar first, so that a hot reload of this file keeps the same convars
local EnableConVar = GetConVar("gry_map_enable") or CreateClientConVar("gry_map_enable", "1", true, false,
	"The big map, opened by its key (M by default): 1 on, 0 off", 0, 1)
local ZoomConVar = GetConVar("gry_map_zoom") or CreateClientConVar("gry_map_zoom", "1", true, false,
	"The zoom the big map had when it was closed (1 to 1024, the map puts it inside its own limit): the next opening of a map session starts there. The first opening of a map is automatic", 1, 1024)
local ZoomCmConVar = GetConVar("gry_map_zoom_cm") or CreateClientConVar("gry_map_zoom_cm", "7", true, false,
	"How closely the big map zooms: what a pixel of the screen covers in the world at the closest zoom, in centimetres (7 by default, 1 to 100). A small map always keeps x8", 1, 100)
local FxConVar = GetConVar("gry_map_loading_fx") or CreateClientConVar("gry_map_loading_fx", "glitch", true, false,
	"The look of the big map's tiles while they load (a name registered with GryMod.Map.Fx.Register; glitch by default)")
local FinishedConVar = GetConVar("gry_map_finished") or CreateClientConVar("gry_map_finished", "0", true, false,
	"The big map also shows the objectives that are done or failed, greyed (1), or only the active ones (0)", 0, 1)
local GridConVar = GetConVar("gry_map_grid") or CreateClientConVar("gry_map_grid", "1", true, false,
	"The big map shows its 8 x 8 grid with the letters A to H and the numbers 1 to 8 (1), or not (0)", 0, 1)

local WaypointsConVar = GetConVar("gry_map_waypoints") or CreateClientConVar("gry_map_waypoints", "1", true, false,
	"The player's own objective points on the big map (a right click without moving the mouse puts one with a title, a right click on one takes it away; private, kept for each map): 1 on, 0 off", 0, 1)

local ChromeConVar = GetConVar("gry_map_chrome") or CreateClientConVar("gry_map_chrome", "1", true, false,
	"The big map is drawn in the frame of the original Crysis PDA map (1), or in the plain panel it had before (0)", 0, 1)

local function number(text)
	local n = tonumber(text)

	if n == nil or n ~= n then
		return nil
	end

	return n
end

-- A switch, as the engine reads a boolean convar: the whole part of the number is not 0. A text that is no number gives `default`.
function Settings.ParseSwitch(text, default)
	local n = number(text)

	if n == nil then
		return default == true
	end

	return n >= 1 or n <= -1
end

-- The zoom, from 1 to Zoom.ABSOLUTE_MAX (the view's own limit is applied when it is set); a text that is no number gives 1.
function Settings.ParseZoom(text)
	local Zoom = GryMod.Map.Zoom

	if Zoom then
		return Zoom.ParseSaved(text)
	end

	local n = number(text) or 1

	return n < 1 and 1 or (n > 1024 and 1024 or n)
end

-- The centimetres a screen pixel covers at the closest zoom, from any text: 1 to 100, 7 by default.
function Settings.ParseZoomCentimetres(text)
	local Zoom = GryMod.Map.Zoom

	if Zoom then
		return Zoom.ParseCentimetres(text)
	end

	local n = number(text) or 7

	return n < 1 and 1 or (n > 100 and 100 or n)
end

-- The name of a loading look: letters, digits and underscore, at most 32. Anything else gives the default look.
function Settings.ParseFx(text)
	if type(text) == "string" and #text <= 32 and string.find(text, "^[%w_]+$") then
		return text
	end

	return Settings.DEFAULT_FX
end

function Settings.Enabled()
	return Settings.ParseSwitch(EnableConVar:GetString(), Settings.DEFAULT_ENABLE)
end

function Settings.Zoom()
	return Settings.ParseZoom(ZoomConVar:GetString())
end

-- What a pixel of the screen covers in the world at the closest zoom, in centimetres (the setting gry_map_zoom_cm).
function Settings.ZoomCentimetres()
	return Settings.ParseZoomCentimetres(ZoomCmConVar:GetString())
end

-- Saves the zoom the map had when it was closed.
function Settings.SaveZoom(zoom)
	ZoomConVar:SetFloat(Settings.ParseZoom(zoom))
end

function Settings.LoadingFx()
	return Settings.ParseFx(FxConVar:GetString())
end

function Settings.ShowFinished()
	return Settings.ParseSwitch(FinishedConVar:GetString(), Settings.DEFAULT_FINISHED)
end

function Settings.ShowGrid()
	return Settings.ParseSwitch(GridConVar:GetString(), Settings.DEFAULT_GRID)
end

function Settings.Chrome()
	return Settings.ParseSwitch(ChromeConVar:GetString(), Settings.DEFAULT_CHROME)
end

-- Whether the player may put objective points of his own on the big map (gry_map_waypoints).
function Settings.Waypoints()
	return Settings.ParseSwitch(WaypointsConVar:GetString(), Settings.DEFAULT_WAYPOINTS)
end
