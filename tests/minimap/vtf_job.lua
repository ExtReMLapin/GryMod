-- Pixel check of the minimap VTF module: writes a 16x16 image of known blocks as a BGRA VTF and as a hand-made DXT1 VTF, loads each with
-- Material("../data/..."), draws it 1:1 in a render target in PostRender and reads pixels back with render.ReadPixel. Run as a gmod-mcp lua_job
-- in the CLIENT realm (the game window must not be in the menu: render targets are not read back there):
--   lua_job {realm = "client", path = ".../tests/minimap/vtf_job.lua"}
-- Returns {ok = bool, failures = {...}, samples = {...}}. The files are deleted at the end, also when the check fails.
-- The image is made of 4x4-pixel blocks of one colour (the material is sampled linearly, so a single pixel is blended with its neighbours when
-- the quad is not exactly pixel aligned; the middle of a block is exact). Block (bx, by) from the top-left: (0,0) red, (3,0) green, (0,3) blue,
-- (3,3) white, the rest black; the BGRA version also has block (1,2) = (10, 120, 250), three different channels, to check the channel order.
-- Only the four middle pixels of each block are compared.

local VTF = GryMod.Minimap.VTF

local function hex(s)
	return (s:gsub("%s", ""):gsub("%x%x", function(h)
		return string.char(tonumber(h, 16))
	end))
end

local dir = "grymod/minimap/test_vtf_job_" .. os.time() .. "_" .. math.random(1, 999999)

-- the wanted colour of the pixel at (col, row), nil on the edge of a block
local function wanted(col, row, kind)
	local cx, cy = col % 4, row % 4

	if cx == 0 or cx == 3 or cy == 0 or cy == 3 then
		return nil
	end

	local bx, by = math.floor(col / 4), math.floor(row / 4)

	if bx == 0 and by == 0 then return 255, 0, 0 end
	if bx == 3 and by == 0 then return 0, 255, 0 end
	if bx == 0 and by == 3 then return 0, 0, 255 end
	if bx == 3 and by == 3 then return 255, 255, 255 end
	if kind == "bgra" and bx == 1 and by == 2 then return 10, 120, 250 end

	return 0, 0, 0
end

local function bgraImage()
	local out = {}

	for row = 0, 15 do
		for col = 0, 15 do
			-- the block's colour is the one of its middle pixel
			local r, g, b = wanted(math.floor(col / 4) * 4 + 1, math.floor(row / 4) * 4 + 1, "bgra")

			out[#out + 1] = string.char(b, g, r, 255)
		end
	end

	return table.concat(out)
end

local function dxt1Image()
	local colours = {[0] = "00 F8", [3] = "E0 07", [12] = "1F 00", [15] = "FF FF"}
	local out = {}

	for i = 0, 15 do
		local c = colours[i] or "00 00"
		out[#out + 1] = hex(c .. " " .. c .. " 00 00 00 00")
	end

	return table.concat(out)
end

local function wipe()
	local files = file.Find(dir .. "/*", "DATA")

	for _, name in ipairs(files or {}) do
		file.Delete(dir .. "/" .. name)
	end

	file.Delete(dir)
end

local failures, samples = {}, {}
local setup, setupErr = pcall(function()
	assert(VTF.Write(dir .. "/bgra.vtf", 16, 16, VTF.FORMAT_BGRA8888, bgraImage()))
	assert(VTF.WriteVMT(dir .. "/bgra.vmt", "../data/" .. dir .. "/bgra"))
	assert(VTF.Write(dir .. "/dxt1.vtf", 16, 16, VTF.FORMAT_DXT1, dxt1Image()))
	assert(VTF.WriteVMT(dir .. "/dxt1.vmt", "../data/" .. dir .. "/dxt1"))
end)

if not setup then
	wipe()

	return {ok = false, error = tostring(setupErr)}
end

local rt = GetRenderTarget("grymod_vtf_job_" .. math.random(1, 999999), 64, 64)
local finished, failure

hook.Add("PostRender", "grymod_vtf_job", function()
	hook.Remove("PostRender", "grymod_vtf_job")

	local ok, err = pcall(function()
		for _, kind in ipairs({"bgra", "dxt1"}) do
			local mat = Material("../data/" .. dir .. "/" .. kind)

			if mat:IsError() then
				failures[#failures + 1] = kind .. ": error material"
			else
				render.PushRenderTarget(rt)
				render.Clear(255, 0, 255, 255, true, true)
				cam.Start2D()
				surface.SetMaterial(mat)
				surface.SetDrawColor(255, 255, 255, 255)
				surface.DrawTexturedRect(0, 0, 16, 16)
				cam.End2D()
				render.CapturePixels()

				local compared = 0

				for row = 0, 15 do
					for col = 0, 15 do
						local r, g, b = render.ReadPixel(col, row)
						local wr, wg, wb = wanted(col, row, kind)

						if wr then
							compared = compared + 1

							if r ~= wr or g ~= wg or b ~= wb then
								failures[#failures + 1] = kind .. " pixel (" .. col .. "," .. row .. ") got " .. r .. "," .. g .. "," .. b .. " want " .. wr .. "," .. wg .. "," .. wb
							end
						end
					end
				end

				samples[kind] = {
					compared = compared,
					topLeft = {render.ReadPixel(1, 1)}, topRight = {render.ReadPixel(14, 1)}, bottomLeft = {render.ReadPixel(1, 14)},
					bottomRight = {render.ReadPixel(14, 14)}, block12 = {render.ReadPixel(6, 9)}, cornerPixel = {render.ReadPixel(0, 0)}
				}
				render.PopRenderTarget()
			end
		end
	end)

	if not ok then
		failure = tostring(err)
		pcall(render.PopRenderTarget)
	end

	finished = true
end)

job:wait(function() return finished end, 10)
pcall(wipe)

if not finished then
	failure = "the PostRender hook never ran (menu open?)"
	hook.Remove("PostRender", "grymod_vtf_job")
end

if failure then
	failures[#failures + 1] = failure
end

return {ok = #failures == 0, failures = failures, samples = samples}
