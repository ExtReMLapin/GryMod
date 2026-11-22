-- Pixel check of the cached group images that follow their clip by whole pixels (cl_flash_draw.lua, sameKey): the status HUD and the
-- radar panel are drawn into an image, then drawn again some whole pixels away (the cached images are drawn again, none is made
-- again), and that picture must be the same, byte for byte, as the one of a clip drawn there for the first time (every image made
-- fresh). A fraction of a pixel away is the control: the picture must then differ from the one at the whole shift. Run as a gmod-mcp
-- lua_job in the CLIENT realm:
--   lua_job {realm = "client", path = ".../tests/flash_shift_pixels_job.lua", args = {dx = 13, dy = -9}}

local Flash = GryMod.Flash
local W, H = 1024, 768
local dx, dy = args and args.dx or 13, args and args.dy or -9
local scale = args and args.scale or 0.9
local x0, y0 = args and args.x or 100.3, args and args.y or 60.6
local rt = GetRenderTarget("grymod_shift_pixels_" .. W, W, H)

local function newStatus()
	local hud = GryMod.FlashHUD.New(Flash.Load(GryMod.FlashHUD.MOVIE))
	hud:SetHealth(62)
	hud:SetEnergy(37)
	hud:SetAmmo(12, 90, 30, 2, "explosivegrenade", "Single", nil, true)
	hud.root:Advance(0.05)

	return hud.root
end

local function newRadar()
	local panel = GryMod.FlashRadar.New(Flash.Load(GryMod.FlashRadar.MOVIE))
	panel:SetHeading(40)
	panel:Update(0.05)

	return panel.root
end

local function picture(root, x, y)
	render.PushRenderTarget(rt)
	render.Clear(51, 51, 51, 255, true, true)
	cam.Start2D()
	local ok = Flash.Draw(root, x, y, scale)
	local png = render.Capture({format = "png", x = 0, y = 0, w = W, h = H, alpha = false})
	cam.End2D()
	render.PopRenderTarget()
	assert(ok, "the drawing failed")

	return png
end

local result = {}
local done

local function run(name, make)
	local reused = make()
	picture(reused, x0, y0)
	local before = Flash.Stats.groupRenders
	local shifted = picture(reused, x0 + dx, y0 + dy)
	local rendersShift = Flash.Stats.groupRenders - before
	local fresh = picture(make(), x0 + dx, y0 + dy)
	local fractional = picture(reused, x0 + dx + 0.5, y0 + dy)
	local rendersFraction = Flash.Stats.groupRenders - before - rendersShift
	local back = picture(reused, x0, y0)
	local first = picture(make(), x0, y0)

	result[name] = {
		shiftedEqualsFresh = shifted == fresh,
		backEqualsFirst = back == first,
		controlFractionDiffers = fractional ~= fresh,
		groupRendersAtWholeShift = rendersShift,
		groupRendersAtFraction = rendersFraction,
		pngBytes = #fresh
	}
end

hook.Add("PostRender", "grymod_shift_pixels", function()
	hook.Remove("PostRender", "grymod_shift_pixels")
	local ok, err = pcall(function()
		run("status", newStatus)
		run("radar", newRadar)
	end)
	result.error = not ok and tostring(err) or nil
	done = true
end)

job:wait(function() return done end)

return result
