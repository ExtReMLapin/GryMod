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
local function boundsOf(sequence, w, h, placement)
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
	local x, y, scale = (placement or Boot.Placement)(w, h)
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
		},
		{
			-- fails without Boot.DrawBackdrop (the dark rectangle behind the shutdown panel, which is hard to read on a bright scene), or when it is not black at 25 %, does not hold the whole
			-- panel, is not on the panel (in the middle of the screen, as the panel is), is drawn for another sequence, or when the setting gry_hud_lost_backdrop (on by default) does not
			-- turn it off
			name = "gry_hud_lost_backdrop: a black rectangle at 25 % behind the Lost panel (and only that one), around the whole panel, on the panel; off, none",
			func = function(state)
				local convar = GetConVar("gry_hud_lost_backdrop")
				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("1")
				expect(isfunction(Boot.DrawBackdrop)).to.beTrue()

				local centered = GetConVar("gry_hud_lost_centered")
				local savedBackdrop, savedCentered = convar:GetString(), centered:GetString()
				local setColor, drawRect = surface.SetDrawColor, surface.DrawRect
				local colour, rects

				surface.SetDrawColor = function(r, g, b, a)
					if istable(r) then r, g, b, a = r.r, r.g, r.b, r.a end
					colour = {r, g, b, a or 255}
				end

				surface.DrawRect = function(x, y, w, h)
					rects[#rects + 1] = {x, y, w, h, colour}
				end

				local ok, err = pcall(function()
					centered:SetString("1")

					for _, screen in ipairs(SCREENS) do
						local w, h = screen[1], screen[2]
						local lost = function(sw, sh) return Boot.PlacementFor("lost", sw, sh) end
						local x0, y0, x1, y1 = boundsOf(started("lost", 2.5), w, h, lost)

						convar:SetString("1")
						rects = {}
						Boot.DrawBackdrop("lost", w, h)
						expect(#rects).to.equal(1)

						local rect = rects[1]
						expect(rect[5][1]).to.equal(0)
						expect(rect[5][2]).to.equal(0)
						expect(rect[5][3]).to.equal(0)
						expect(rect[5][4]).to.equal(64) -- 25 % of 255
						expect(rect[1] <= x0 and rect[2] <= y0 and rect[1] + rect[3] >= x1 and rect[2] + rect[4] >= y1).to.beTrue()
						expect(math.abs((rect[1] + rect[3] / 2) / w - 0.5) < 0.03).to.beTrue()
						expect(math.abs((rect[2] + rect[4] / 2) / h - 0.5) < 0.04).to.beTrue()
						expect(rect[3] < w and rect[4] < h).to.beTrue() -- a rectangle around the panel, not the whole screen

						for _, kind in ipairs({"initialize", "reboot"}) do
							rects = {}
							Boot.DrawBackdrop(kind, w, h)
							expect(#rects).to.equal(0)
						end

						convar:SetString("0")
						rects = {}
						Boot.DrawBackdrop("lost", w, h)
						expect(#rects).to.equal(0)
					end
				end)

				surface.SetDrawColor, surface.DrawRect = setColor, drawRect
				convar:SetString(savedBackdrop)
				centered:SetString(savedCentered)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails without Boot.PlacementFor, the setting gry_hud_lost_centered and the shift of the Lost screen
			name = "gry_hud_lost_centered: the Lost screen (only that one) goes to the middle of the screen, still centred across; on by default; off, it stays low as in its movie",
			func = function(state)
				local convar = GetConVar("gry_hud_lost_centered")
				expect(convar).toNot.beNil()
				-- fails while the default is 0: the owner wants the shutdown screen in the middle without having to find the setting
				expect(convar:GetDefault()).to.equal("1")

				local saved = convar:GetString()

				local ok, err = pcall(function()
					for _, screen in ipairs(SCREENS) do
						local lost = function(w, h) return Boot.PlacementFor("lost", w, h) end

						convar:SetString("0")
						local x0, y0, x1, y1 = boundsOf(started("lost", 2.5), screen[1], screen[2], lost)
						local low = (y0 + y1) / 2 / screen[2]
						expect(low > 0.76 and low < 0.84).to.beTrue()

						convar:SetString("1")
						x0, y0, x1, y1 = boundsOf(started("lost", 2.5), screen[1], screen[2], lost)
						local centre = (y0 + y1) / 2 / screen[2]
						expect(x0 >= 0 and x1 <= screen[1] and y0 >= 0 and y1 <= screen[2]).to.beTrue()
						expect(math.abs((x0 + x1) / 2 / screen[1] - 0.5) < 0.03).to.beTrue()
						expect(math.abs(centre - 0.5) < 0.03).to.beTrue()

						-- the two other sequences keep the stage where it was, whatever the setting
						for _, kind in ipairs({"initialize", "reboot"}) do
							local px, py, pscale = Boot.PlacementFor(kind, screen[1], screen[2])
							local bx, by, bscale = Boot.Placement(screen[1], screen[2])
							expect(px).to.equal(bx)
							expect(py).to.equal(by)
							expect(pscale).to.equal(bscale)
						end
					end
				end)

				convar:SetString(saved)

				if not ok then
					error(err, 0)
				end
			end
		}
	}
}
