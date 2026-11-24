-- Tests of the smooth energy bars (GryMod.FlashBarSmooth, cl_hud_bar_smooth.lua, with the pure part of lua/grymod/sh_flash_bar.lua that tools/test_flash_bar.py tests
-- outside the game), GLuaTest format, client realm: the suit's energy bar (HUD:SetEnergyExact) and the night vision's bar (Instance:SetBar). What is checked: the
-- frames and the cut a value gives on the real converted movies, nothing smoothed on a whole step, at the ends, when a step is a pixel or less or when the
-- setting is off, the setting itself, and that a paint allocates nothing for the bar. The drawing of the cut is tests/cl_flash_cut_test.lua.

local Smooth, NightBar
local saved

local function savedConVar(name)
	local convar = GetConVar(name)

	if convar then
		saved[#saved + 1] = {name, convar:GetString()}
	end
end

local function suitHUD()
	local movie = GryMod.Flash.Load(GryMod.FlashHUD.MOVIE)
	local hud = GryMod.FlashHUD.New(movie)

	assert(hud, "the HUD movie")

	return hud
end

return {
	groupName = "GryMod smooth energy bars",
	beforeAll = function(state)
		Smooth = GryMod.FlashBarSmooth
		NightBar = GryMod.FlashNightVisionBar
	end,
	beforeEach = function(state)
		saved = {}
		savedConVar("gry_hud_bar_smooth")
		GetConVar("gry_hud_bar_smooth"):SetString("1")
	end,
	afterEach = function(state)
		for i = #saved, 1, -1 do
			pcall(function() GetConVar(saved[i][1]):SetString(saved[i][2]) end)
		end

		pcall(function() GryMod.Flash.ClearGroupCache() end)
	end,
	cases = {
		{
			-- needs: the HUD element "bar_smooth" (gry_hud_bar_smooth, on by default) with its check box
			name = "the smooth bars are a HUD element that is on by default (gry_hud_bar_smooth) with a check box in the options",
			func = function(state)
				local convar = GetConVar("gry_hud_bar_smooth")
				expect(convar).toNot.beNil()
				expect(GryMod.HUDOptions.Find("bar_smooth")).to.exist()
				expect(GryMod.HUDOptions.Find("bar_smooth").default).to.beNil()
				convar:SetString("0")
				expect(Smooth.Enabled()).to.beFalse()
				convar:SetString("1")
				expect(Smooth.Enabled()).to.beTrue()

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found["gry_hud_bar_smooth"]).to.beTrue()
			end
		},
		{
			-- needs: the movie's mask read once into edges, for the three bars
			name = "the edges of the suit's energy and health bars and of the night vision's are read from the movies (a mask, a step of about 1.3 and 1.5 stage pixels)",
			func = function(state)
				local F = GryMod.Flash
				local suit, night = F.Load(GryMod.FlashHUD.MOVIE), F.Load(NightBar.MOVIE)
				local e = Smooth.Math.Edges(suit.chars[16], suit.chars)
				expect(e).toNot.beNil()
				expect(e.n).to.equal(100)
				expect(math.abs(e.step - 1.3214) < 0.01).to.beTrue()
				e = Smooth.Math.Edges(suit.chars[25], suit.chars)
				expect(e.n).to.equal(100)
				e = Smooth.Math.Edges(night.chars[12], night.chars)
				expect(e.n).to.equal(102)
				expect(math.abs(e.step - 1.4754) < 0.01).to.beTrue()
			end
		},
		{
			-- needs: HUD:SetEnergyExact: the integer frame, the clone at the next one and the cut line for a fraction
			name = "the suit's energy bar at 50 and a third is at frame 50 with a clone at frame 51 and a cut line between their edges (1080p)",
			func = function(state)
				local hud = suitHUD()
				local bar = hud.energyBar
				hud:SetEnergy(51) -- the original's way: the value plus one, the frame is that minus one

				local ok, err = pcall(function()
					local edges = Smooth.EdgesOf(bar)
					local sbar = Smooth.ForClip(bar, 0)
					-- the HUD's own entry point reads the screen's height: here 1080 is given
					local frame, fraction = Smooth.Apply(sbar, 50 + 1 / 3, 1080)
					expect(frame).to.equal(50)
					expect(math.abs(fraction - 1 / 3) < 1e-9).to.beTrue() -- the bar is 0.78 of the stage in the HUD: a step is 1.45 px at 1080p, a grid of 3 a frame, and a third is on it
					expect(bar:CurrentFrame()).to.equal(50)
					expect(bar.cutClone).toNot.beNil()
					expect(bar.cutClone:CurrentFrame()).to.equal(51)
					expect(bar.cutSide).to.equal(1)
					local line = edges.edge[50] + (edges.edge[51] - edges.edge[50]) / 3
					expect(math.abs(bar.cutX - line) < 1e-9).to.beTrue()
					expect(bar.cutY).to.equal(edges.y)

					-- the next frame: the clone is not made again
					local clone = bar.cutClone
					Smooth.Apply(sbar, 50 + 2 / 3, 1080)
					expect(bar.cutClone).to.equal(clone)
					expect(clone:CurrentFrame()).to.equal(51)
					expect(bar:CurrentFrame()).to.equal(50)
				end)
				GryMod.Flash.ReleaseClip(hud.root)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- needs: a whole step drawn as the original did
			name = "on a whole step there is no cut line and the frame is the original's (floor(energy)), the ends included",
			func = function(state)
				local hud = suitHUD()
				local bar = hud.energyBar
				local sbar = Smooth.ForClip(bar, 0)

				for _, pair in ipairs({{0, 1}, {1, 1}, {2, 2}, {50, 50}, {99, 99}, {100, 100}, {120, 100}, {-4, 1}, {0 / 0, 1}}) do
					local frame, fraction = Smooth.Apply(sbar, pair[1], 2160)
					expect(frame).to.equal(pair[2])
					expect(fraction).to.equal(0)
					expect(bar:CurrentFrame()).to.equal(pair[2])
					expect(bar.cutClone).to.beNil()
				end

				GryMod.Flash.ReleaseClip(hud.root)
			end
		},
		{
			-- needs: Subdivisions: a step of a pixel or less is not smoothed
			name = "nothing is smoothed when a step is a pixel or less (a small screen) or when the setting is off: the bar is at floor(value) as before",
			func = function(state)
				local hud = suitHUD()
				local bar = hud.energyBar
				local sbar = Smooth.ForClip(bar, 0)

				-- 1.3 stage pixels a step: a screen 560 high makes it 0.95 px
				local frame, fraction = Smooth.Apply(sbar, 50.9, 560)
				expect(frame).to.equal(50)
				expect(fraction).to.equal(0)
				expect(bar.cutClone).to.beNil()

				-- the same value on a big screen is smoothed
				frame, fraction = Smooth.Apply(sbar, 50.9, 2160)
				expect(frame).to.equal(50)
				expect(fraction > 0.8).to.beTrue()
				expect(bar.cutClone).toNot.beNil()

				-- the setting off puts it back at once
				GetConVar("gry_hud_bar_smooth"):SetString("0")
				frame, fraction = Smooth.Apply(sbar, 50.9, 2160)
				expect(frame).to.equal(50)
				expect(fraction).to.equal(0)
				expect(bar.cutClone).to.beNil()
				GryMod.Flash.ReleaseClip(hud.root)
			end
		},
		{
			-- needs: the fill follows the value: the cut line goes down with the value, never up, never by more than the step
			name = "the cut line follows the value in small steps without a jump (the suit's bar, 0 to 100 in a tenth of a percent)",
			func = function(state)
				local hud = suitHUD()
				local bar = hud.energyBar
				local sbar = Smooth.ForClip(bar, 0)
				local edges = Smooth.EdgesOf(bar)
				local previous

				for tenth = 0, 1000 do
					local frame, fraction = Smooth.Apply(sbar, tenth / 10, 1080)
					local x = Smooth.Math.Cut(edges, frame, fraction)

					if previous then
						expect(x <= previous + 1e-9).to.beTrue()
						expect(previous - x < edges.step * 0.5).to.beTrue()
					end

					previous = x
				end

				GryMod.Flash.ReleaseClip(hud.root)
			end
		},
		{
			-- needs: the night vision bar through Instance:SetBar with the second copy of the movie at the next frame
			name = "the night vision bar at 40.4 is at frame 41 with a copy at frame 42, the line between their edges; the copy plays the same time and takes the same state",
			func = function(state)
				local bar = NightBar.New(GryMod.Flash.Load(NightBar.MOVIE))
				expect(bar).toNot.beNil()

				local ok, err = pcall(function()
					local smooth = Smooth.New(bar.clip, bar.root:Find(NightBar.PATH), 1, bar.copyClip, bar.copy:Find(NightBar.PATH))
					expect(smooth).toNot.beNil()
					local frame, fraction = Smooth.Apply(smooth, 40.4, 1080)
					expect(frame).to.equal(41)
					expect(fraction > 0.3 and fraction < 0.5).to.beTrue() -- the grid of 5 a frame at 1080p: .4 is on it
					expect(bar.root:Find(NightBar.PATH):CurrentFrame()).to.equal(41)
					expect(bar.copy:Find(NightBar.PATH):CurrentFrame()).to.equal(42)
					expect(bar.clip.cutClone).to.equal(bar.copyClip)
					expect(bar.clip.cutSide).to.equal(1)

					-- the movie plays: both are in the same state
					for _ = 1, 20 do
						bar:Update(1 / 30)
					end

					expect(bar.root:Find("Root.Bar"):CurrentFrame()).to.equal(17)
					expect(bar.copy:Find("Root.Bar"):CurrentFrame()).to.equal(17)

					-- the HUD's red and flicker states reach both
					bar:Destroy(1)
					expect(bar.clip:CurrentFrame() == bar.copyClip:CurrentFrame()).to.beTrue()
					bar:Destroy(0)
				end)
				GryMod.Flash.ReleaseClip(bar.root)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- needs: SetBar using the smooth bar: the whole frame floor(value) + 1 when nothing is smoothed (the earlier tests of the bar), the fraction otherwise
			name = "SetBar still draws the whole frame of the original when the setting is off, and the same frames as Apply when it is on",
			func = function(state)
				local bar = NightBar.New(GryMod.Flash.Load(NightBar.MOVIE))
				GetConVar("gry_hud_bar_smooth"):SetString("0")

				for _, pair in ipairs({{0, 1}, {12.9, 13}, {50, 51}, {100, 101}}) do
					bar:SetBar(pair[1])
					expect(bar.root:Find(NightBar.PATH):CurrentFrame()).to.equal(pair[2])
					expect(bar.clip.cutClone).to.beNil()
				end

				GetConVar("gry_hud_bar_smooth"):SetString("1")
				bar:SetBar(50)
				expect(bar.root:Find(NightBar.PATH):CurrentFrame()).to.equal(51)
				expect(bar.clip.cutClone).to.beNil()
				GryMod.Flash.ReleaseClip(bar.root)
			end
		},
		{
			-- needs: nothing allocated by the bars: the collector is stopped and the memory counted before and after many applications
			name = "applying a value to a bar allocates nothing while the frame stays (the suit's and the night vision's), fractions or not",
			timing = true, -- no count hook: under it the interpreter allocates for its own sake
			func = function(state)
				local hud = suitHUD()
				local sbar = Smooth.ForClip(hud.energyBar, 0)
				local night = NightBar.New(GryMod.Flash.Load(NightBar.MOVIE))
				-- the clones are made by a first pass
				Smooth.Apply(sbar, 50.5, 2160)
				night:SetBar(50.5)

				-- the memory used by n applications; a part of it is the same whatever n is (the engine's compiler warming up), so two runs are compared
				local function used(n)
					collectgarbage("collect")
					collectgarbage("stop")
					local before = collectgarbage("count")

					for i = 1, n do
						local fraction = (i % 80) / 100
						Smooth.Apply(sbar, 50 + fraction, 2160)
						night:SetBar(40 + fraction)
					end

					local after = collectgarbage("count")
					collectgarbage("restart")

					return (after - before) * 1024
				end

				used(500)
				local few, many = used(1000), used(5000)
				GryMod.Flash.ReleaseClip(hud.root)
				GryMod.Flash.ReleaseClip(night.root)
				-- bytes per application, beyond the fixed part
				expect((many - few) / 4000 < 2).to.beTrue()
			end
		}
	}
}
