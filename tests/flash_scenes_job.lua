-- Renders the converted movies as they play (the first seconds of their timeline, and the HUD and radar panels
-- with values), to compare two states of the atlases pixel by pixel (tools/flash2lua/compare_pixels.py). Run as a
-- gmod-mcp lua_job in the CLIENT realm:
--   lua_job {realm = "client", path = ".../tests/flash_scenes_job.lua",
--            args = {movies = {"hud_lost"}, times = {0.5, 2}, scale = 1, tag = "after"}}
-- args.old = true draws the movies and PNG atlases that the job finds under garrysmod/data/grymod_dev/old/
-- (<movie>.lua and the PNG files: `git show <commit>:<path>` of the state to compare with) instead of the current ones.
-- Pictures: garrysmod/data/grymod_dev/<tag>_<movie>_<time>_<scale>.png. Result: {files = {name = {w, h}}}.

local Flash = GryMod.Flash
local bg = args.bg or {51, 51, 51}
local scale = args.scale or 1
local tag = args.tag or "scene"
local movies = args.movies or {"hud_ammohealthenergysuit"}
local times = args.times or {0, 1}
local oldPath = "grymod_dev/old/"
local realPathFunction = Flash.AtlasMaterialPath

local function registerOld()
	Flash.AtlasMaterialPath = function(path)
		return "../data/" .. oldPath .. path:match("[^/]+$")
	end

	for _, name in ipairs(movies) do
		Flash.Unload(name)
		local source = file.Read(oldPath .. name .. ".lua", "DATA")
		assert(source, "no old movie " .. name)
		Flash.Register(name, CompileString(source, name)())
	end
end

local function restore()
	Flash.AtlasMaterialPath = realPathFunction

	for _, name in ipairs(movies) do
		Flash.Unload(name)
	end
end

Flash.IgnoreBlendModes = false

if args.old then
	registerOld()
end

Flash.ClearMaterialCache()
Flash.ClearGroupCache()

local results = {}

local function capture(root, name, w, h)
	local rt = GetRenderTarget("grymod_flash_scene_" .. w .. "x" .. h, w, h)
	local finished, failure

	hook.Add("PostRender", "grymod_flash_scene", function()
		hook.Remove("PostRender", "grymod_flash_scene")

		local ok, err = pcall(function()
			render.PushRenderTarget(rt)
			render.Clear(bg[1], bg[2], bg[3], 255, true, true)
			cam.Start2D()
			Flash.Draw(root, 0, 0, scale)
			cam.End2D()
			file.CreateDir("grymod_dev")
			file.Write(name .. ".png", render.Capture({format = "png", x = 0, y = 0, w = w, h = h, alpha = false}))
			render.PopRenderTarget()
		end)

		finished = true
		failure = not ok and tostring(err) or nil
	end)

	job:wait(function() return finished end, 20)
	results[name] = {w, h, failure}
end

for _, movieName in ipairs(movies) do
	local movie = Flash.Load(movieName)
	local root, step

	if movieName == "hud_ammohealthenergysuit" then
		local hud = GryMod.FlashHUD.New(movie)
		hud:SetHealth(68)
		hud:SetEnergy(55)
		hud:SetMode("Armor")
		hud:SetAmmo(17, 90, 30, 3, "explosivegrenade", "Auto")
		root, step = hud.root, function(dt) hud:Update(dt) end
	elseif movieName == "hud_radarcompassstealth" then
		local panel = GryMod.FlashRadar.New(movie)
		panel:SetHeading(40)
		panel:SetFOV(15)
		panel:SetStealth(0.3)
		root, step = panel.root, function(dt) panel:Update(dt) end
	else
		root = Flash.NewRoot(movie)
		step = function(dt) root:Advance(dt) end
	end

	local now = 0

	for _, t in ipairs(times) do
		while now < t - 1e-6 do
			step(1 / 30)
			now = now + 1 / 30
		end

		capture(root, string.format("grymod_dev/%s_%s_%s_%s", tag, movieName, tostring(t), tostring(scale)),
			math.ceil(movie.w * scale), math.ceil(movie.h * scale))
	end
end

if args.old then
	restore()
	Flash.ClearMaterialCache()
end

return {files = results, stats = Flash.Stats}
