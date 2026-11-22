-- MANUAL MEASUREMENT TOOL (not a GLuaTest): how long the noise veil would show during a REAL walk, with the old rule and with the discovery mode (client realm, gmod-mcp).
-- It is the live version of display_walk_tool.lua: there the generator is supposed to keep up with the walk; here the player really moves, the real radar draws every frame and
-- the real generator makes the tiles in real time (so what it measures depends on the frame rate of the client: raise fps_max and fps_max_nofocus with console_exec on a test client).
--
-- Order (2026-11-22): 1. lua_exec_file preload_coverage_job.lua and display_walk_tool.lua (CLIENT) 2. the navigation mesh centres written by the SERVER to
-- data/grymod_tmp/dl_centres_<map>.txt (see the comment of COV.readCentres; the map needs a navigation mesh or a node graph) 3. lua_job discovery_walk_server.lua in the SERVER realm,
-- async: true (it waits for the signal file, then moves the player along the route) 4. lua_job this file in the CLIENT realm.
-- args: speed (units a second, 266: a sprint), maxUnits (how far the walk goes, 40000), preload (true: the tile preload runs first, the way it does in a game; default false: the
-- walk meets an empty cache, the owner's "on se balade et il y a des trucs qui chargent"), scale (the radar is drawn at this scale: 2160 / 768 puts the density of a 4K screen on
-- a small test window), points ("nav" reads the centres file, else the ground nodes).
-- The cache is a scratch one ("zz_dl_<map>_v5", never the real folder); the radar's own panel is made here and drawn from this file's HUDPaint hook, the game's own radar hook is taken
-- off during the run and put back after. Per frame the state the radar tells itself (panel.mapState): "ready", "discovery" or "loading". OLD veil = not ready (the tile under the
-- player is missing), NEW veil = loading (nothing to show), both read in the same frame of the same walk.

local Mm = GryMod.Minimap
local Z = GryMod.ZoneMapClient
local args = job.args or {}

job:wait(function() return Z and Z.Boxes and type(Z.Boxes()) == "table" end, 120)

local pts

if args.points == "nav" then
	pts = COV.readCentres("grymod_tmp/dl_centres_" .. string.lower(game.GetMap()) .. ".txt")
end

local begun = DW.begin({points = pts})

if begun.error then
	COV.finish()

	return begun
end

-- the radar asks the generator for real
Mm.Gen.Request = COV.real.request

if args.preload then
	job:sleep(2)
	job:wait(function()
		local p = Mm.Gen.PreloadProgress()

		return p and p.total and p.total > 0 and Mm.Gen.Pending() == 0 and (p.done or 0) + (p.failed or 0) >= p.total
	end, 2400)
else
	Mm.Preload.Stop()
	Mm.Gen.SetPreload({})
	Mm.Gen.Cancel()
end

-- the route for the server's mover
local route = {}

for i, p in ipairs(COV.nav) do
	route[i] = string.format("%d,%d,%d,%d", p.x, p.y, p.z, p.jump and 1 or 0)
end

file.CreateDir("grymod_tmp")
file.Delete("grymod_tmp/dw_done.txt")
file.Write("grymod_tmp/dw_route.txt", table.concat(route, ";"))

-- the radar's own panel, and the game's one taken off
local Radar = GryMod.FlashRadar
local panel = Radar.New(GryMod.Flash.Load(Radar.MOVIE))
local savedHud = hook.GetTable().HUDPaint and hook.GetTable().HUDPaint.GRYFLASHHUD

if savedHud then
	hook.Remove("HUDPaint", "GRYFLASHHUD")
end

local scale = args.scale or (2160 / 768)
local live = {frames = 0, seconds = 0, oldFrames = 0, newFrames = 0, oldSeconds = 0, newSeconds = 0, oldEpisodes = 0, newEpisodes = 0, noiseMismatch = 0, genBusyFrames = 0,
	longestOld = 0, longestNew = 0, states = {ready = 0, discovery = 0, loading = 0}, defFrames = {}, examples = {}, done = false}
local runOld, runNew, wasOld, wasNew, last = 0, 0, false, false, nil

hook.Add("HUDPaint", "GryDiscoveryWalk", function()
	local now = RealTime()
	local dt = last and math.min(now - last, 0.1) or 0
	last = now

	panel:SetHeading(Radar.BearingFromYaw(LocalPlayer():EyeAngles().y))

	-- the contacts and the automatic zoom (cl_hud_radar_units.lua): the real HUD does it before Update, and the zoom mode (vehicle, foot, indoor) sets the range and so the definition
	if Radar.Feed then
		Radar.Feed(panel, LocalPlayer(), dt)
	end

	panel:Update(dt)
	panel:Draw(0, ScrH() - 768 * scale, scale)

	local state = panel.mapState
	local old, new = state ~= "ready", state == "loading"

	live.frames = live.frames + 1

	local def = Mm.Settings.Definition()

	live.defFrames[def] = (live.defFrames[def] or 0) + 1
	live.seconds = live.seconds + dt
	live.states[state or "none"] = (live.states[state or "none"] or 0) + 1

	if Mm.Gen.Pending() > 0 then
		live.genBusyFrames = live.genBusyFrames + 1
	end

	if old then
		live.oldFrames, live.oldSeconds, runOld = live.oldFrames + 1, live.oldSeconds + dt, runOld + 1

		if not wasOld then
			live.oldEpisodes = live.oldEpisodes + 1
		end

		live.longestOld = math.max(live.longestOld, runOld)
	else
		runOld = 0
	end

	if new then
		live.newFrames, live.newSeconds, runNew = live.newFrames + 1, live.newSeconds + dt, runNew + 1

		if not wasNew then
			live.newEpisodes = live.newEpisodes + 1

			if #live.examples < 6 then
				local p = LocalPlayer():GetPos()
				live.examples[#live.examples + 1] = string.format("%d,%d,%d", p.x, p.y, p.z)
			end
		end

		live.longestNew = math.max(live.longestNew, runNew)
	else
		runNew = 0
	end

	wasOld, wasNew = old, new

	-- the veil the player sees is the one the state tells (the noise clip)
	local noise = panel.main and panel.main:Child("Noise")

	if noise and (noise.visible == true) ~= new then
		live.noiseMismatch = live.noiseMismatch + 1
	end
end)

-- the radar's settings the run used
local S = Mm.Settings
local info = {range = Radar.Range(), definition = S.Definition(), auto = S.DefinitionAuto(), tile = S.TileRes(), autozoom = GetConVar("gry_radar_autozoom"):GetInt(), veilSetting = tostring(S.VeilInDiscovery and S.VeilInDiscovery())}

file.Write("grymod_tmp/dw_go.txt", tostring(args.speed or 266) .. "," .. tostring(args.maxUnits or 40000))

local t0 = RealTime()

job:wait(function() return file.Exists("grymod_tmp/dw_done.txt", "DATA") end, args.timeoutS or 900)

live.done = true
hook.Remove("HUDPaint", "GryDiscoveryWalk")

if savedHud then
	hook.Add("HUDPaint", "GRYFLASHHUD", savedHud)
end

pcall(GryMod.Flash.ReleaseClip, panel.root)
file.Delete("grymod_tmp/dw_go.txt")
file.Delete("grymod_tmp/dw_route.txt")

local progress = Mm.Gen.Progress()
local made = Mm.Cache.Count and Mm.Cache.Count() or nil

COV.finish()

live.wallSeconds = math.floor((RealTime() - t0) * 10) / 10
live.fps = live.seconds > 0 and math.floor(live.frames / live.seconds) or 0
live.oldSeconds, live.newSeconds, live.seconds = math.floor(live.oldSeconds * 10) / 10, math.floor(live.newSeconds * 10) / 10, math.floor(live.seconds * 10) / 10

return {info = info, route = {steps = #route, preload = args.preload and true or false}, live = live, tilesInCache = made}
