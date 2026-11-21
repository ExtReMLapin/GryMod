-- Cost of drawing the HUD panels (microseconds per Flash.Draw, over args.count draws, 400 by default), and the time
-- Material() takes for each atlas picture of the movies. Run as a gmod-mcp lua_job in the CLIENT realm:
--   lua_job {realm = "client", path = ".../tests/flash_draw_cost_job.lua", args = {scale = 2.8, old = false}}
-- args.old = true measures the PNG atlases and movies found under garrysmod/data/grymod_dev/old/ (see flash_scenes_job.lua).

local Flash = GryMod.Flash
local scale = args.scale or 1
local count = args.count or 400
local movies = {"hud_ammohealthenergysuit", "hud_radarcompassstealth"}
local allMovies = {"hud_ammohealthenergysuit", "hud_binoculars", "hud_crosshair", "hud_friendlycross", "hud_grenadedetect", "hud_initialize", "hud_lost", "hud_quickmenu", "hud_radarcompassstealth", "hud_reboot"}
local oldPath = "grymod_dev/old/"
local realPath = Flash.AtlasMaterialPath

if args.old then
	Flash.AtlasMaterialPath = function(path)
		return "../data/" .. oldPath .. path:match("[^/]+$")
	end
end

local function load(name)
	Flash.Unload(name)

	if args.old then
		Flash.Register(name, CompileString(file.Read(oldPath .. name .. ".lua", "DATA"), name)())
	end

	return Flash.Load(name)
end

Flash.ClearMaterialCache()
Flash.ClearGroupCache()

-- the first use of every picture: the time Material() takes (and the first size query that makes the engine load it)
local loads = {}
local totalLoad = 0

for _, name in ipairs(allMovies) do
	local movie = load(name)

	for index, path in ipairs(movie.atlases) do
		for _, p in ipairs({path, Flash.AtlasPathFor(movie, index, 0, 0, 0)}) do
			if not Flash.AtlasLoaded(p) then
				local t0 = SysTime()
				Flash.AtlasMaterial(p)
				local ms = (SysTime() - t0) * 1000
				loads[p] = math.Round(ms, 1)
				totalLoad = totalLoad + ms
			end
		end
	end
end

local results = {}
local finished

hook.Add("PostRender", "grymod_flash_cost", function()
	hook.Remove("PostRender", "grymod_flash_cost")

	for _, name in ipairs(movies) do
		local movie = Flash.Load(name)
		local root, step

		if name == "hud_ammohealthenergysuit" then
			local hud = GryMod.FlashHUD.New(movie)
			hud:SetHealth(68)
			hud:SetEnergy(55)
			hud:SetAmmo(17, 90, 30, 3, "explosivegrenade", "Auto")
			root = hud.root
		else
			local panel = GryMod.FlashRadar.New(movie)
			panel:SetHeading(40)
			panel:SetFOV(15)
			root = panel.root
		end

		cam.Start2D()
		Flash.Draw(root, 0, 0, scale)

		for _ = 1, 20 do
			Flash.Draw(root, 0, 0, scale)
		end

		local t0 = SysTime()

		for _ = 1, count do
			Flash.Draw(root, 0, 0, scale)
		end

		results[name] = math.Round((SysTime() - t0) / count * 1e6, 1)
		cam.End2D()
	end

	finished = true
end)

job:wait(function() return finished end, 60)

if args.old then
	Flash.AtlasMaterialPath = realPath

	for _, name in ipairs(allMovies) do
		Flash.Unload(name)
	end

	Flash.ClearMaterialCache()
end

return {microsecondsPerDraw = results, loadMs = loads, loadTotalMs = math.Round(totalLoad), count = count}
