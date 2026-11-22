-- MANUAL TOOL (not a GLuaTest): to take screenshots of the radar in the discovery mode and in the initial loading (client realm, gmod-mcp; the map needs a navigation mesh or a graph).
-- Load preload_coverage_job.lua and display_walk_tool.lua first (lua_exec_file, CLIENT), write the centres file (see discovery_walk_job.lua), then lua_exec_file this file and:
--   DS.setup(scale)        scratch cache ("zz_dl_<map>_v5"), the real generator, the radar's own panel drawn by this tool's HUDPaint hook (the game's own radar hook is taken off); `scale` is
--                          the size of the radar on the screen (0.75 fits a 640 x 360 window); returns the places found (DS.pair)
--   DS.state()             the state the radar tells itself (panel.mapState), whether the noise veil shows, the text, the tile under the player, the coverage
--   DS.veilOld(true)       the old rule (gry_minimap_veil_discovery 1) WITHOUT writing the saved setting: the function Settings.VeilInDiscovery is replaced; false puts it back
--   DS.gen(false)          the generator asks nothing (the tile under the player stays missing); true: the real one again
--   DS.restore()           everything back
-- The server half moves the player: SetPos in the SERVER realm (noclip), to DS.pair.before (the tile there is made by the real generator), then DS.pair.after (the tile of the other
-- side of a tile border, never made).

DS = DS or {}

local Mm = GryMod.Minimap

-- two consecutive places of the walk on the two sides of a border between two tiles: the first one is on a tile that exists once the generator made it, the second one is on the tile
-- next to it, 400 units away at most
function DS.find()
	local S = Mm.Settings
	local T = Mm.Cache.TileUnits(S.TileRes(), S.Definition())

	for i = 1, #COV.nav - 1 do
		local a, b = COV.nav[i], COV.nav[i + 1]

		if not b.jump and math.abs(b.x - a.x) + math.abs(b.y - a.y) < 400 and (math.floor(a.x / T) ~= math.floor(b.x / T) or math.floor(a.y / T) ~= math.floor(b.y / T)) then
			return {before = {x = a.x, y = a.y, z = a.z}, after = {x = b.x, y = b.y, z = b.z}, tile = T}
		end
	end
end

function DS.setup(scale)
	local Radar = GryMod.FlashRadar
	local pts = COV.readCentres("grymod_tmp/dl_centres_" .. string.lower(game.GetMap()) .. ".txt")
	local begun = DW.begin({points = pts})

	if begun.error then
		return begun
	end

	Mm.Preload.Stop()
	Mm.Gen.SetPreload({})
	Mm.Gen.Cancel()
	Mm.Gen.Request = COV.real.request
	DS.requestReal = COV.real.request
	DS.pair = DS.find()

	DS.scale = scale or 0.75
	DS.panel = Radar.New(GryMod.Flash.Load(Radar.MOVIE))
	DS.savedHud = hook.GetTable().HUDPaint and hook.GetTable().HUDPaint.GRYFLASHHUD
	DS.realVeil = Mm.Settings.VeilInDiscovery

	if DS.savedHud then
		hook.Remove("HUDPaint", "GRYFLASHHUD")
	end

	local last
	hook.Add("HUDPaint", "GryDiscoveryShots", function()
		local now = RealTime()
		local dt = last and math.min(now - last, 0.1) or 0
		last = now

		DS.panel:SetHeading(Radar.BearingFromYaw(LocalPlayer():EyeAngles().y))

		if Radar.Feed then
			Radar.Feed(DS.panel, LocalPlayer(), dt)
		end

		DS.panel:Update(dt)
		DS.panel:Draw(0, ScrH() - 768 * DS.scale, DS.scale)
	end)

	return {pair = DS.pair, steps = #COV.nav}
end

function DS.state()
	local p = DS.panel
	local pos = LocalPlayer():GetPos()
	local S = Mm.Settings
	local level = Mm.Floors.CurrentAt(pos)
	local cov = Mm.View.Coverage(pos.x, pos.y, GryMod.FlashRadar.Range() / GryMod.RadarShared.METRES_PER_UNIT, level)

	return {state = p.mapState, noise = p.main:Child("Noise").visible, text = p.progressText, pos = string.format("%d,%d,%d", pos.x, pos.y, pos.z), coverage = cov, definition = S.Definition(),
		pending = Mm.Gen.Pending()}
end

function DS.veilOld(on)
	if on then
		Mm.Settings.VeilInDiscovery = function() return true end
	else
		Mm.Settings.VeilInDiscovery = DS.realVeil
	end
end

function DS.gen(on)
	if on then
		Mm.Gen.Request = DS.requestReal
	else
		Mm.Gen.Request = function() return false end
		Mm.Gen.Cancel()
	end
end

function DS.restore()
	hook.Remove("HUDPaint", "GryDiscoveryShots")

	if DS.savedHud then
		hook.Add("HUDPaint", "GRYFLASHHUD", DS.savedHud)
	end

	if DS.panel then
		pcall(GryMod.Flash.ReleaseClip, DS.panel.root)
	end

	Mm.Settings.VeilInDiscovery = DS.realVeil or Mm.Settings.VeilInDiscovery

	if DS.realHas then
		Mm.Cache.Has, Mm.Cache.Material = DS.realHas, DS.realMaterial
		DS.realHas, DS.realMaterial, DS.hidden = nil, nil, nil
	end
	COV.finish()
	DS.panel = nil
end

-- DS.hide(function(tile) return true end): the tiles for which the function answers true "do not exist yet" (Cache.Has false, no material), as if the generator had not made them;
-- DS.hide(nil) shows them again. This is how a tile that is late is staged: the generator asks the tile across the border as a margin, so it is usually made before the player gets there.
function DS.hide(filter)
	local C = Mm.Cache

	DS.realHas, DS.realMaterial = DS.realHas or C.Has, DS.realMaterial or C.Material
	DS.hidden = filter

	C.Has = function(tile)
		if DS.hidden and DS.hidden(tile) then
			return false
		end

		return DS.realHas(tile)
	end

	C.Material = function(tile)
		if DS.hidden and DS.hidden(tile) then
			return nil
		end

		return DS.realMaterial(tile)
	end
end
