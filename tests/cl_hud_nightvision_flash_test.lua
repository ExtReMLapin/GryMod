-- Tests of the night vision's energy bar drawn from the original Scaleform movie HUD_NightVision (GryMod.FlashNightVisionBar, cl_hud_nightvision_flash.lua),
-- GLuaTest format, client realm. The rules are from the movie's ActionScript (setNightVisionBar(v) = frame floor(v) + 1 of the 102-frame clip, destroy(status)
-- as the corner marks) and from the original's code (the bar comes up when the night vision is switched on, stays while it is on and while the energy
-- refills, and goes when the energy is full again). The world is the test's own: the night vision's clock, its state and the HUD switches are replaced for
-- each case and put back after it, in a pcall (a stub must never stay).

local NightBar
local NV
local drawn
local realDraw
local saved
local state_now -- the night vision's clock in the test

local function savedConVar(name)
	local convar = GetConVar(name)

	if convar then
		saved.convars[#saved.convars + 1] = {name, convar:GetString()}
	end
end

-- Flash.Draw is a recorder: the roots that were drawn, in order.
local function recordDraws()
	realDraw = GryMod.Flash.Draw
	GryMod.Flash.Draw = function(root, x, y, scale)
		drawn[#drawn + 1] = {root = root, x = x, y = y, scale = scale}
	end
end

local function run(instance, seconds)
	for _ = 1, math.ceil(seconds * 30) do
		instance:Update(1 / 30)
	end
end

-- The night vision with a clock of the test's own: on or off, an energy of 0 to 30 (the energy of the moment `now`).
local function world(on, energy)
	state_now = state_now or 100
	NV.Clock = function() return state_now end
	NV.IsOn = function() return on end
	NV.SetEnergy(energy)
	-- (SetEnergy armed a timer for the second the energy would reach zero: not wanted here)
	timer.Remove("GryMod_NightVisionEmpty")
end

return {
	groupName = "GryMod night vision bar (Flash)",
	beforeAll = function(state)
		NightBar = GryMod.FlashNightVisionBar
		NV = GryMod.NightVision
	end,
	beforeEach = function(state)
		drawn = {}
		saved = {convars = {}, nv = {Clock = NV.Clock, IsOn = NV.IsOn, Energy0 = NV.Energy(), BarVisible = NV.BarVisible}}
		savedConVar("gry_hud_nightvision")
		savedConVar("gry_hud")
		savedConVar("gry_nightvision_energy")
		state_now = nil
		NightBar.Reset()
		NightBar.SetStatus(0)
	end,
	afterEach = function(state)
		if realDraw then
			GryMod.Flash.Draw = realDraw
			realDraw = nil
		end

		pcall(function()
			NV.Clock, NV.IsOn, NV.BarVisible = saved.nv.Clock, saved.nv.IsOn, saved.nv.BarVisible
		end)

		for i = #saved.convars, 1, -1 do
			pcall(function() GetConVar(saved.convars[i][1]):SetString(saved.convars[i][2]) end)
		end

		pcall(function() NV.SetEnergy(NV.MAX) end)
		pcall(function() timer.Remove("GryMod_NightVisionEmpty") end)
		pcall(NightBar.Reset)
		pcall(NightBar.SetStatus, 0)
		-- (the flag is the original's: clear it by painting with the night vision off and full)
		pcall(function() NightBar.Shown() end)
	end,
	cases = {
		{
			-- needs: NightBar.FrameFor, the movie's setNightVisionBar (Math.floor(value), gotoAndStop(value + 1))
			name = "the value of 0 to 100 gives frame floor(value) + 1 of the 102-frame clip, a value out of the range is held in it and what is not a number is 0",
			func = function(state)
				local F = NightBar.FrameFor
				expect(F(0)).to.equal(1)
				expect(F(0.99)).to.equal(1)
				expect(F(1)).to.equal(2)
				expect(F(25)).to.equal(26)
				expect(F(50)).to.equal(51)
				expect(F(50.7)).to.equal(51)
				expect(F(99.9)).to.equal(100)
				expect(F(100)).to.equal(101)
				expect(F(101)).to.equal(102)
				expect(F(250)).to.equal(102)
				expect(F(-5)).to.equal(1)
				expect(F(nil)).to.equal(1)
				expect(F(0 / 0)).to.equal(1)
				expect(F("50")).to.equal(51)
				expect(F("not a number")).to.equal(1)
			end
		},
		{
			-- needs: NightBar.Placement, the same stage placement as the right corner mark's movie
			name = "the movie is against the right edge of the screen, the stage as high as the screen, like the right corner mark",
			func = function(state)
				for _, size in ipairs({{1920, 1080}, {1280, 720}, {1024, 768}, {2560, 1080}, {3840, 2160}}) do
					local w, h = size[1], size[2]
					local x, y, scale = NightBar.Placement(w, h)
					local cx, cy, cscale = GryMod.FlashCorners.Placement("right", w, h)
					expect(y).to.equal(0)
					expect(scale).to.equal(h / 768)
					expect(math.abs(x - (w - 1024 * h / 768)) < 1e-6).to.beTrue()
					expect(x).to.equal(cx)
					expect(y).to.equal(cy)
					expect(scale).to.equal(cscale)
				end
			end
		},
		{
			-- needs: the converted movie and NightBar.New
			name = "the movie loads and makes a bar, a missing movie makes none, and the bar's clip is at Root.Bar.Bar",
			func = function(state)
				local Flash = GryMod.Flash
				local movie = Flash.Load(NightBar.MOVIE)
				expect(movie).toNot.beNil()
				local bar = NightBar.New(movie)
				expect(bar).toNot.beNil()
				expect(bar.root:Find(NightBar.PATH)).toNot.beNil()
				expect(NightBar.New(nil)).to.beNil()
				-- the movie is a stage of 1024 x 768 with its root clip at the top right
				expect(movie.w).to.equal(1024)
				expect(movie.h).to.equal(768)
				expect(movie.root[1][1].m[5] > 800 and movie.root[1][1].m[5] < 850).to.beTrue()
				expect(movie.root[1][1].m[6] < 50).to.beTrue()
			end
		},
		{
			-- needs: Instance:SetBar going to the frame of the bar's clip
			name = "SetBar puts the bar at the frame of the value: 0 is the first frame, 25 the 26th, 50 the 51st, 100 the 101st",
			func = function(state)
				local bar = NightBar.New(GryMod.Flash.Load(NightBar.MOVIE))

				for _, pair in ipairs({{0, 1}, {25, 26}, {50, 51}, {100, 101}, {12.9, 13}}) do
					bar:SetBar(pair[1])
					run(bar, 0.1)
					expect(bar.root:Find(NightBar.PATH):CurrentFrame()).to.equal(pair[2])
				end
			end
		},
		{
			-- needs: the opening clip of the movie playing once when the movie is made (17 frames), the bar value kept through it
			name = "the opening plays its 17 frames once and stops, with the bar's value kept through it",
			func = function(state)
				local bar = NightBar.New(GryMod.Flash.Load(NightBar.MOVIE))
				bar:SetBar(60)
				run(bar, 0.1)
				expect(bar.root:Find("Root.Bar"):CurrentFrame() < 17).to.beTrue()
				run(bar, 1)
				expect(bar.root:Find("Root.Bar"):CurrentFrame()).to.equal(17)
				expect(bar.root:Find(NightBar.PATH):CurrentFrame()).to.equal(61)
			end
		},
		{
			-- needs: Instance:Destroy as the corner marks: 1 malfunction (red), 2 flickering, 0 normal; the bar value set again after the movie made the bar again
			name = "destroy(1) goes to the red state, destroy(2) flickers, destroy(0) is back to normal and the bar takes its value again",
			func = function(state)
				local bar = NightBar.New(GryMod.Flash.Load(NightBar.MOVIE))
				bar:SetBar(50)
				run(bar, 1)
				bar:Destroy(1)
				run(bar, 0.5)
				expect(bar.clip:CurrentLabel()).to.equal("malfunctionOn")
				bar:Destroy(2)
				run(bar, 1)
				expect(bar.clip:CurrentFrame()).to.equal(24) -- the flicker ends at its 24th frame, faded out, and stops
				bar:Destroy(0)
				run(bar, 0.2)
				expect(bar.clip:CurrentLabel()).to.equal("normal")
				-- the movie made the bar again, at its first frame: the next set (every paint does it) puts it back
				bar:SetBar(50)
				expect(bar.root:Find(NightBar.PATH):CurrentFrame()).to.equal(51)
			end
		},
		{
			-- needs: the HUD element "nightvision" (default on), listed in the options, with the check box in the HUD menu
			name = "the bar is a HUD element that is on by default (gry_hud_nightvision) with a check box in the options",
			func = function(state)
				local convar = GetConVar("gry_hud_nightvision")
				expect(convar).toNot.beNil()
				expect(GryMod.HUDOptions.Find("nightvision")).to.exist()
				expect(GryMod.HUDOptions.Find("nightvision").default).to.beNil()
				convar:SetString("0")
				expect(NightBar.Wanted()).to.beFalse()
				convar:SetString("1")
				expect(NightBar.Wanted()).to.beTrue()

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

				expect(found["gry_hud_nightvision"]).to.beTrue()
			end
		},
		{
			-- needs: the paint costing one test of a flag while the bar is not up: no movie made, nothing drawn
			name = "a paint with the bar not up draws nothing and makes nothing",
			func = function(state)
				recordDraws()
				GetConVar("gry_hud_nightvision"):SetString("1")
				NightBar.Paint(1 / 60)
				NightBar.Paint(1 / 60)
				expect(#drawn).to.equal(0)
				expect(NightBar.Bar()).to.beNil()
				expect(NightBar.IsUp()).to.beFalse()
			end
		},
		{
			-- needs: the hook GryMod_NightVision (the report of cl_nightvision.lua) raising the flag: switching ON raises it, OFF does not clear it
			name = "the night vision's report (GryMod_NightVision) brings the bar up when it is switched on, and switching off does not take it away",
			func = function(state)
				local listener = hook.GetTable()["GryMod_NightVision"]["GRYNIGHTVISIONBAR"]
				expect(listener).toNot.beNil()
				expect(NightBar.IsUp()).to.beFalse()
				listener(false, "test")
				expect(NightBar.IsUp()).to.beFalse()
				listener(true, "test")
				expect(NightBar.IsUp()).to.beTrue()
				listener(false, "test")
				expect(NightBar.IsUp()).to.beTrue()
			end
		},
		{
			-- needs: the original's rule: shown while on, shown while the energy refills, gone when it is full and off
			name = "the bar is drawn while the night vision is on and while the energy refills, and goes (the flag with it) when the energy is full and it is off",
			func = function(state)
				recordDraws()
				GetConVar("gry_hud_nightvision"):SetString("1")
				GetConVar("gry_nightvision_energy"):SetString("1")
				local listener = hook.GetTable()["GryMod_NightVision"]["GRYNIGHTVISIONBAR"]

				-- on, with the energy at its maximum at the very moment of the switch: drawn
				world(true, NV.MAX)
				listener(true, "test")
				NightBar.Paint(1 / 60)
				expect(#drawn).to.equal(1)
				expect(NightBar.Bar()).toNot.beNil()
				expect(drawn[1].root).to.equal(NightBar.Bar().root)

				-- off with the energy half: it refills, the bar stays and shows the energy
				world(false, 15)
				drawn = {}
				NightBar.Paint(1 / 60)
				expect(#drawn).to.equal(1)
				expect(NightBar.Bar().root:Find(NightBar.PATH):CurrentFrame()).to.equal(NightBar.FrameFor(50))

				-- the clock goes on: 2 a second, 15 s to the maximum; just before it, still drawn
				state_now = state_now + 7
				drawn = {}
				NightBar.Paint(1 / 60)
				expect(#drawn).to.equal(1)
				expect(NightBar.Bar().root:Find(NightBar.PATH):CurrentFrame()).to.equal(NightBar.FrameFor(29 * 100 / 30))
				expect(NightBar.IsUp()).to.beTrue()

				-- full: gone, and the flag with it
				state_now = state_now + 1
				drawn = {}
				NightBar.Paint(1 / 60)
				expect(#drawn).to.equal(0)
				expect(NightBar.IsUp()).to.beFalse()

				-- (the flag is down: nothing more is drawn until the next switch on, whatever the energy)
				world(false, 5)
				NightBar.Paint(1 / 60)
				expect(#drawn).to.equal(0)
			end
		},
		{
			-- needs: BarVisible false (the energy not limited): no bar, the flag falls with it
			name = "a night vision with no limit has no bar: nothing is drawn and the flag goes",
			func = function(state)
				recordDraws()
				GetConVar("gry_hud_nightvision"):SetString("1")
				local listener = hook.GetTable()["GryMod_NightVision"]["GRYNIGHTVISIONBAR"]
				GetConVar("gry_nightvision_energy"):SetString("0")
				expect(NV.BarVisible()).to.beFalse()
				world(true, NV.MAX)
				listener(true, "test")
				NightBar.Paint(1 / 60)
				expect(#drawn).to.equal(0)
				expect(NightBar.IsUp()).to.beFalse()
				-- (and when the limit is back with the night vision on: the next switch brings it up again)
				GetConVar("gry_nightvision_energy"):SetString("1")
				listener(true, "test")
				NightBar.Paint(1 / 60)
				expect(#drawn).to.equal(1)
			end
		},
		{
			-- needs: the HUD element switch read at the paint: nothing made while off, the bar back with the setting (the flag keeps)
			name = "with the HUD element off nothing is drawn or kept, and the bar is back when it is on again",
			func = function(state)
				recordDraws()
				local listener = hook.GetTable()["GryMod_NightVision"]["GRYNIGHTVISIONBAR"]
				world(true, 20)
				listener(true, "test")
				GetConVar("gry_hud_nightvision"):SetString("1")
				NightBar.Paint(1 / 60)
				expect(#drawn).to.equal(1)

				drawn = {}
				GetConVar("gry_hud_nightvision"):SetString("0")
				NightBar.Paint(1 / 60)
				expect(#drawn).to.equal(0)
				expect(NightBar.Bar()).to.beNil()

				GetConVar("gry_hud_nightvision"):SetString("1")
				NightBar.Paint(1 / 60)
				expect(#drawn).to.equal(1)
			end
		},
		{
			-- needs: Paint placing the draw at Placement for the screen
			name = "the paint draws at the placement of the screen",
			func = function(state)
				recordDraws()
				GetConVar("gry_hud_nightvision"):SetString("1")
				local listener = hook.GetTable()["GryMod_NightVision"]["GRYNIGHTVISIONBAR"]
				world(true, 10)
				listener(true, "test")
				NightBar.Paint(1 / 60)
				local x, y, scale = NightBar.Placement(ScrW(), ScrH())
				expect(#drawn).to.equal(1)
				expect(drawn[1].x).to.equal(x)
				expect(drawn[1].y).to.equal(y)
				expect(drawn[1].scale).to.equal(scale)
			end
		},
		{
			-- needs: the HUD status hook: a bar made after the report starts in that state, one made before takes it
			name = "the HUD's report of its state (GryMod_HUDStatus) turns the bar red or off and back, including a bar made after the report, and the value survives it",
			func = function(state)
				recordDraws()
				GetConVar("gry_hud_nightvision"):SetString("1")
				local listener = hook.GetTable()["GryMod_NightVision"]["GRYNIGHTVISIONBAR"]
				local report = hook.GetTable()["GryMod_HUDStatus"]["GRYNIGHTVISIONBAR"]
				expect(report).toNot.beNil()
				world(false, 15)
				listener(true, "test")
				NightBar.Paint(1 / 30)
				report(1)
				expect(NightBar.Status()).to.equal(1)
				expect(NightBar.Bar().status).to.equal(1)

				NightBar.Reset()
				NightBar.Paint(1 / 30)
				expect(NightBar.Bar().status).to.equal(1)

				report(2)
				expect(NightBar.Bar().status).to.equal(2)
				for _ = 1, 40 do NightBar.Paint(1 / 30) end
				report(0)
				for _ = 1, 10 do NightBar.Paint(1 / 30) end
				expect(NightBar.Bar().status).to.equal(0)
				-- the movie made the bar again after the flicker: the paint set it to the energy (50 percent) again
				expect(NightBar.Bar().root:Find(NightBar.PATH):CurrentFrame()).to.equal(NightBar.FrameFor(50))
			end
		},
		{
			-- needs: the HUD paint calling NightBar.Paint, and Module.Reset giving the bar back
			name = "the HUD's paint draws the bar when it is up, and resetting the HUD gives it back",
			func = function(state)
				local HUD = GryMod.FlashHUD
				local ply = LocalPlayer()

				if not IsValid(ply) or not ply:Alive() then
					return
				end

				recordDraws()
				GetConVar("gry_hud_nightvision"):SetString("1")
				GetConVar("gry_hud"):SetString("1")
				local listener = hook.GetTable()["GryMod_NightVision"]["GRYNIGHTVISIONBAR"]
				world(true, 20)
				listener(true, "test")
				HUD.Reset()
				HUD.Paint()
				local bars = 0

				for _, d in ipairs(drawn) do
					if NightBar.Bar() and d.root == NightBar.Bar().root then
						bars = bars + 1
					end
				end

				expect(bars).to.equal(1)
				HUD.Reset()
				expect(NightBar.Bar()).to.beNil()
			end
		},
		{
			-- needs: no hook of its own on a frame event: the HUD's paint is the only thing that calls it
			name = "it adds no hook to a per-frame event",
			func = function(state)
				local all = hook.GetTable()

				for _, event in ipairs({"Think", "Tick", "HUDPaint", "HUDPaintBackground", "PreRender", "PostRender", "RenderScreenspaceEffects"}) do
					for name in pairs(all[event] or {}) do
						expect(tostring(name)).toNot.equal("GRYNIGHTVISIONBAR")
					end
				end
			end
		},
		{
			-- needs: the piece in the preloading plan, so that the first night vision does not freeze to load the movie
			name = "the movie is part of the preloading, behind the HUD element switch",
			func = function(state)
				local found

				for _, piece in ipairs(GryMod.FlashPrewarm.Pieces) do
					if piece.name == "nightvision" then
						found = piece
					end
				end

				expect(found).toNot.beNil()
				expect(found.option).to.equal("nightvision")
				expect(found.hud).to.beTrue()
				expect(found.films()[1]).to.equal("hud_nightvision")
			end
		}
	}
}
