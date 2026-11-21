-- Where the boot sequences (HUD_Initialize, HUD_Lost, HUD_Reboot) are drawn on the screen, GLuaTest format, client realm:
-- the 4:3 stage of the movies is scaled to the height of the screen and centred across its width, on any aspect ratio.
-- What is drawn inside the stage is the movie's own placement: the Lost frame is placed low in its movie (its content
-- is about 220 stage pixels under the clip's origin at the centre of the stage, in the SWF), the other two are centred
-- (their drawing holds shapes far outside the frame, so only the frame of Lost is measured here).

local Boot = GryMod.FlashBoot
local Flash = GryMod.Flash

local SCREENS = {{3840, 2160}, {3440, 1440}, {1920, 1080}, {1280, 720}}

-- Draws a started sequence with the mesh calls replaced by recorders and returns the bounding box of every vertex
-- (screen pixels): minX, minY, maxX, maxY.
local function boundsOf(sequence, w, h)
	local originals = {mesh = {}, render = {}}
	local names = {mesh = {"Begin", "Position", "TexCoord", "Color", "AdvanceVertex", "End"}, render = {"SetMaterial", "OverrideBlend"}}
	local current
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	local fakes = {
		mesh = {
			Begin = function() end,
			Position = function(position) current = {position.x, position.y} end,
			TexCoord = function() end,
			Color = function() end,
			AdvanceVertex = function()
				x0, y0 = math.min(x0, current[1]), math.min(y0, current[2])
				x1, y1 = math.max(x1, current[1]), math.max(y1, current[2])
			end,
			End = function() end
		},
		render = {SetMaterial = function() end, OverrideBlend = function() end}
	}

	for library, list in pairs(names) do
		for _, name in ipairs(list) do
			originals[library][name] = _G[library][name]
			_G[library][name] = fakes[library][name]
		end
	end

	local ignored = Flash.IgnoreBlendModes
	Flash.IgnoreBlendModes = true
	local x, y, scale = Boot.Placement(w, h)
	local ok, err = pcall(sequence.Draw, sequence, x, y, scale)
	Flash.IgnoreBlendModes = ignored

	for library, list in pairs(names) do
		for _, name in ipairs(list) do
			_G[library][name] = originals[library][name]
		end
	end

	assert(ok, tostring(err))

	return x0, y0, x1, y1
end

local function started(kind, seconds)
	local sequence = Boot.New(kind, Flash.Load(Boot.MOVIES[kind]))
	sequence:Start()

	for _ = 1, math.floor(seconds * 30) do
		sequence:Update(1 / 30)
	end

	return sequence
end

return {
	groupName = "GryMod boot sequences placement",
	cases = {
		{
			name = "the stage is scaled to the height of the screen and centred across its width (16:9, 21:9 and others)",
			func = function(state)
				for _, screen in ipairs(SCREENS) do
					local x, y, scale = Boot.Placement(screen[1], screen[2])
					expect(scale).to.aboutEqual(screen[2] / 768, 1e-9)
					expect(y).to.equal(0)
					expect(x).to.aboutEqual((screen[1] - 1024 * scale) / 2, 1e-9)
				end
			end
		},
		{
			name = "the stage centre lands on the centre of the screen across its width, on every aspect ratio",
			func = function(state)
				for _, screen in ipairs(SCREENS) do
					local x, _, scale = Boot.Placement(screen[1], screen[2])
					expect(x + 512 * scale).to.aboutEqual(screen[1] / 2, 1e-6)
					expect(768 * scale).to.aboutEqual(screen[2], 1e-6)
				end
			end
		},
		{
			name = "the Lost frame is drawn inside the screen, centred across it, and low as in its movie (centre of the frame at about 80 % of the height)",
			func = function(state)
				for _, screen in ipairs(SCREENS) do
					local x0, y0, x1, y1 = boundsOf(started("lost", 2.5), screen[1], screen[2])
					expect(x0 >= 0 and x1 <= screen[1] and y0 >= 0 and y1 <= screen[2]).to.beTrue()
					expect(math.abs((x0 + x1) / 2 / screen[1] - 0.5) < 0.03).to.beTrue()
					local centre = (y0 + y1) / 2 / screen[2]
					expect(centre > 0.76 and centre < 0.84).to.beTrue()
				end
			end
		}
	}
}
