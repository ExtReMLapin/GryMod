-- Renders a converted Flash movie into a render target and saves it as a PNG, to compare with FFDec's render of
-- the same SWF (tools/flash2lua/compare_pixels.py). Run as a gmod-mcp lua_job in the CLIENT realm:
--   lua_job {realm = "client", path = ".../tests/flash_pixels_job.lua",
--            args = {movie = "hud_ammohealthenergysuit", out = "grymod_dev/flash_px.png"}}
-- The atlas PNGs must be in garrysmod/data/grymod_dev/ (copy materials/grymod/flash/*.png there): a branch that is
-- not mounted as an addon has no materials folder in the game's search path.
-- The result is written under garrysmod/data/ (out). Optional args: width, height (1024x768), scale (1), bg,
-- twice (draw a second time and save out_2.png: it must be identical, from the group caches),
-- radar = {bearing, fov, stealth} (the compass panel), advance (seconds of timeline to play before drawing the HUD),
-- hud = {health, energy, mode, fireMode, ammo = {mag, reserve, size, grenades}} (the Crysis HUD with values),
-- sprite, frame, x, y (draw one sprite of the movie alone instead of the whole movie),
-- texts = {{path = "Root.Texts.HealthEnergy.Colorset", name = "HealthText1", text = "1"}, ...},
-- drawX, drawY (shift of the stage origin in pixels), atlasSuffix, ignoreBlend (draw additive sprites as normal blends: FFDec's reference render does not honour blend modes).

local movieName = args.movie or "hud_ammohealthenergysuit"
local out = args.out or "grymod_dev/flash_px.png"
local width, height = args.width or 1024, args.height or 768
local scale = args.scale or 1
local bg = args.bg or {51, 51, 51}

local Flash = GryMod.Flash
Flash.IgnoreBlendModes = args.ignoreBlend == true

-- atlasSuffix: the engine keeps a texture by its path, so a regenerated atlas needs a new file name
-- (copy hud_x_1.png to data/grymod_dev/hud_x_1<suffix>.png and pass the suffix)
local suffix = args.atlasSuffix or ""

Flash.AtlasMaterialPath = function(path)
	local name = path:match("[^/]+$"):gsub("%.png$", suffix .. ".png")

	return "../data/grymod_dev/" .. name
end

if Flash.ClearMaterialCache then
	Flash.ClearMaterialCache()
end

local movie = Flash.Load(movieName)
local root
local function setTexts(clip)
	for _, t in ipairs(args.texts or {}) do
		local target = clip:Find(t.path)
		assert(target and target:SetText(t.name, t.text), "no text field " .. t.path .. "." .. t.name)
	end
end

if args.hud then
	-- the Crysis HUD with values: hud = {health = 101, energy = 101, mode = "Armor", ammo = {mag, reserve, size, grenades}}
	local hud = GryMod.FlashHUD.New(movie)
	hud:SetHealth(args.hud.health or 101)
	hud:SetEnergy(args.hud.energy or 101)
	hud:SetMode(args.hud.mode or "Armor")
	local a = args.hud.ammo or {31, 71, 40, 7}
	hud:SetAmmo(a[1], a[2], a[3], a[4], "explosivegrenade", args.hud.fireMode or "Auto")
	root = hud.root

	if args.advance then
		-- let the timelines play (the digits flash when they change)
		for _ = 1, math.floor(args.advance * 30) do hud:Update(1 / 30) end
	end
elseif args.radar then
	-- the compass panel: radar = {bearing = 0, stealth = 0.3, fov = 15}
	local panel = GryMod.FlashRadar.New(movie)
	panel:SetHeading(args.radar.bearing or 0)
	panel:SetFOV(args.radar.fov or 15)
	panel:SetStealth(args.radar.stealth or 0)
	root = panel.root

	if args.advance then
		for _ = 1, math.floor(args.advance * 30) do panel:Update(1 / 30) end
	end
elseif args.sprite then
	-- one sprite of the movie alone, at (args.x, args.y) of the stage, on the frame args.frame
	local single = {w = movie.w, h = movie.h, fps = movie.fps, atlases = movie.atlases, chars = movie.chars,
		root = {{{d = 1, c = args.sprite, n = "S", m = {1, 0, 0, 1, args.x or 10, args.y or 10}}}}}
	root = Flash.NewRoot(single)

	if args.frame then
		root:Child("S"):GotoAndStop(args.frame)
	end
else
	root = Flash.NewRoot(movie)
end

setTexts(root)

local rt = GetRenderTarget("grymod_flash_px_" .. width .. "x" .. height, width, height)
local finished, failure

hook.Add("PostRender", "grymod_flash_px", function()
	hook.Remove("PostRender", "grymod_flash_px")

	local ok, err = pcall(function()
		render.PushRenderTarget(rt)
		render.Clear(bg[1], bg[2], bg[3], 255, true, true)
		cam.Start2D()

		if Flash.Draw then
			Flash.Draw(root, args.drawX or 0, args.drawY or 0, scale)
		end

		cam.End2D()

		local data = render.Capture({format = "png", x = 0, y = 0, w = width, h = height, alpha = false})
		file.CreateDir("grymod_dev")
		file.Write(out, data)

		if args.twice then
			-- the second draw of the same clips must come from the cached group images and look the same
			Flash.Stats.firstRenders = Flash.Stats.groupRenders
			render.Clear(bg[1], bg[2], bg[3], 255, true, true)
			cam.Start2D()
			Flash.Draw(root, args.drawX or 0, args.drawY or 0, scale)
			cam.End2D()
			file.Write(out:gsub("%.png$", "_2.png"), render.Capture({format = "png", x = 0, y = 0, w = width, h = height, alpha = false}))
		end

		render.PopRenderTarget()
	end)

	finished = true

	if not ok then
		failure = tostring(err)
	end
end)

job:wait(function() return finished end, 10)

return {out = out, drawn = Flash.Draw ~= nil, error = failure, size = file.Size(out, "DATA"), stats = Flash.Stats}
