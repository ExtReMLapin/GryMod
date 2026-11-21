-- Contact sheet of the shapes of a converted movie, to compare two versions of its atlas (PNG against VTF, another
-- packing...) pixel by pixel with dev_resources/flash2lua/compare_pixels.py. Run as a gmod-mcp lua_job in the CLIENT realm:
--   lua_job {realm = "client", path = ".../tests/flash_atlas_job.lua",
--            args = {movies = {"hud_quickmenu"}, scales = {0.5, 2.8}, tag = "before"}}
-- Every shape of the movie is drawn at its stage size on a grid (the shapes of a movie are not placed anywhere
-- as a group otherwise), once with its own colours (white = false) or as the white silhouette a colour-set clip
-- tints (white = true: multiplier 0, colour added, as Color.setRGB does). The picture is written under garrysmod/data/
-- as <tag>_<movie>_<scale>[_w].png and the same number of shapes in the same order are drawn whatever the atlas looks like, so two
-- runs on two versions of the atlas give two pictures of the same size. Result: {files = {name = {width, height, shapes}}}. Each movie is drawn in both modes at every scale.

local Flash = GryMod.Flash
local bg = args.bg or {51, 51, 51}
local tag = args.tag or "sheet"
local WIDTH, GAP = 1024, 4

Flash.IgnoreBlendModes = true

local function sheetOf(movie, white)
	local ids = {}

	for id, definition in pairs(movie.chars) do
		if definition.k == "shape" then
			ids[#ids + 1] = id
		end
	end

	table.sort(ids)

	local x, y, rowHeight = GAP, GAP, 0
	local ops = {}

	for index, id in ipairs(ids) do
		local shape = movie.chars[id]
		local w, h = shape.dw, shape.dh

		if x + w + GAP > WIDTH then
			x, y, rowHeight = GAP, y + rowHeight + GAP, 0
		end

		local op = {d = index, c = id, m = {1, 0, 0, 1, x - shape.ox, y - shape.oy}}

		if white then
			op.cx = {0, 0, 0, 1, 255, 64, 0, 0}
		end

		ops[#ops + 1] = op
		x = x + w + GAP
		rowHeight = math.max(rowHeight, h)
	end

	local stageH = math.ceil(y + rowHeight + GAP)

	return {w = WIDTH, h = stageH, fps = 30, atlases = movie.atlases, white = movie.white, chars = movie.chars,
		fonts = movie.fonts, root = {ops}}, #ids
end

local results = {}

for _, movieName in ipairs(args.movies or {"hud_ammohealthenergysuit"}) do
	if Flash.ClearMaterialCache then
		Flash.ClearMaterialCache()
	end

	local movie = Flash.Load(movieName)

	for _, scale in ipairs(args.scales or {1}) do
		for _, white in ipairs({false, true}) do
			local sheet, count = sheetOf(movie, white)
			local root = Flash.NewRoot(sheet)
			local width, height = math.ceil(WIDTH * scale), math.ceil(sheet.h * scale)
			local name = string.format("grymod_dev/%s_%s_%s%s", tag, movieName, tostring(scale), white and "_w" or "")
			local rt = GetRenderTarget("grymod_flash_sheet_" .. width .. "x" .. height, width, height)
			local finished, failure

			hook.Add("PostRender", "grymod_flash_sheet", function()
				hook.Remove("PostRender", "grymod_flash_sheet")

				local ok, err = pcall(function()
					render.PushRenderTarget(rt)
					render.Clear(bg[1], bg[2], bg[3], 255, true, true)
					cam.Start2D()
					Flash.Draw(root, 0, 0, scale)
					cam.End2D()
					file.CreateDir("grymod_dev")
					file.Write(name .. ".png", render.Capture({format = "png", x = 0, y = 0, w = width, h = height, alpha = false}))
					render.PopRenderTarget()
				end)

				finished = true
				failure = not ok and tostring(err) or nil
			end)

			job:wait(function() return finished end, 20)
			results[name] = {width, height, count, failure}
		end
	end
end

return {files = results, stats = Flash.Stats}
