-- Tests of the big map's chrome (lua/grymod/client/map/chrome.lua, GryMod.Map.Chrome), GLuaTest format, client realm: the frame of the real Crysis PDA movie
-- (HUD_PDA_Map) that the big map is drawn in. What is tested: where the movie goes on the screen (any ratio), the rectangle of its map window taken from the
-- movie's own data, the window of the bounds' shape inside it, the open and close animations (PDAArea frames, mask_02 and Alpha_Layer), the jammed look of a
-- malfunction, the texts (translated keys, no raw "@ui"), what is hidden (the multiplayer parts), the DONE button, the objective cell, and the hook that lets the
-- map draw its tiles inside the movie. No drawing is done: the drawing function of the Flash player is replaced by a recorder where a case needs it, and put back
-- in afterEach inside a pcall, also when a case failed.

local STEP = 1 / 30

local function C()
	local chrome = GryMod and GryMod.Map and GryMod.Map.Chrome

	expect(chrome ~= nil and chrome.New ~= nil).to.beTrue()

	return chrome
end

local function movie()
	local m = GryMod.Flash.Load(C().MOVIE)

	expect(m ~= nil).to.beTrue()

	return m
end

local function fresh()
	local inst = C().New(movie())

	expect(inst ~= nil).to.beTrue()

	return inst
end

-- runs the movie for `seconds`, one frame at a time
local function run(inst, seconds)
	for _ = 1, math.ceil(seconds / STEP - 1e-9) do
		inst:Update(STEP)
	end
end

-- every text entry of a clip and of the clips in it
local function texts(clip, found)
	found = found or {}

	for _, entry in ipairs(clip:Entries()) do
		if entry.clip then
			if entry.clip.visible then
				texts(entry.clip, found)
			end
		elseif entry.kind == "text" then
			found[#found + 1] = entry.text
		end
	end

	return found
end

local function has(list, text)
	for _, t in ipairs(list) do
		if t == text then
			return true
		end
	end

	return false
end

return {
	groupName = "GryMod big map chrome",
	beforeEach = function(state)
		state.drawSaved = GryMod.Flash.Draw
	end,
	afterEach = function(state)
		pcall(function()
			GryMod.Flash.Draw = state.drawSaved
		end)
	end,
	cases = {
		-- fails without Chrome.Placement
		{
			name = "the movie's panel is centred on the screen and as high as 92 percent of it, or as wide as 96 percent when the screen is narrow, whatever the ratio",
			func = function()
				local Chrome = C()
				local P = Chrome.PANEL

				for _, size in ipairs({{3840, 2160}, {1920, 1080}, {1280, 1024}, {1024, 768}, {800, 1200}}) do
					local sw, sh = size[1], size[2]
					local ox, oy, scale = Chrome.Placement(sw, sh)
					local left, top = ox + P.x0 * scale, oy + P.y0 * scale
					local right, bottom = ox + P.x1 * scale, oy + P.y1 * scale

					-- centred
					expect((left + right) / 2).to.aboutEqual(sw / 2, 1e-6)
					expect((top + bottom) / 2).to.aboutEqual(sh / 2, 1e-6)

					-- inside the screen, and touching the limit on one side
					expect(right - left <= 0.96 * sw + 1e-6).to.beTrue()
					expect(bottom - top <= 0.92 * sh + 1e-6).to.beTrue()
					expect(math.abs(right - left - 0.96 * sw) < 1e-6 or math.abs(bottom - top - 0.92 * sh) < 1e-6).to.beTrue()
				end

				-- 16:9 is limited by the height
				local _, _, scale = Chrome.Placement(3840, 2160)

				expect((P.y1 - P.y0) * scale).to.aboutEqual(0.92 * 2160, 1e-6)

				-- a portrait screen is limited by the width
				_, _, scale = Chrome.Placement(800, 1200)
				expect((P.x1 - P.x0) * scale).to.aboutEqual(0.96 * 800, 1e-6)
			end
		},
		-- fails without Chrome.AreaStage: the window must come from the movie's own mask, not from a number written here
		{
			name = "the map window is the rectangle the movie clips its map to (the mask of Map_M): about 410 x 409 stage pixels at (582, 85), inside the panel",
			func = function()
				local Chrome = C()
				local rect = Chrome.AreaStage(fresh().root)

				expect(rect ~= nil).to.beTrue()
				expect(rect.x).to.aboutEqual(581.8, 0.5)
				expect(rect.y).to.aboutEqual(85.3, 0.5)
				expect(rect.w).to.aboutEqual(409.7, 0.5)
				expect(rect.h).to.aboutEqual(408.8, 0.5)

				local P = Chrome.PANEL

				expect(rect.x > P.x0 and rect.x + rect.w < P.x1 and rect.y > P.y0 and rect.y + rect.h < P.y1).to.beTrue()

				-- on a 16:9 4K screen the window is a large square in the right place: centred across, about two thirds of the height
				local ox, oy, scale = Chrome.Placement(3840, 2160)
				local area = Chrome.ToScreen(ox, oy, scale, rect)

				expect(area.x + area.w / 2).to.aboutEqual(1920, 4)
				expect(area.w / 2160 > 0.6 and area.w / 2160 < 0.72).to.beTrue()
				expect(area.y > 0 and area.y + area.h < 2160).to.beTrue()
			end
		},
		-- fails without Chrome.FitWindow: the bounds' shape inside the movie's window
		{
			name = "the window of the bounds' shape (1:2 to 2:1) sits in the middle of the movie's window and never leaves it",
			func = function()
				local Chrome = C()
				local area = {x = 100, y = 50, w = 400, h = 400}

				-- square bounds: the whole area
				local w = Chrome.FitWindow(area, {x0 = 0, x1 = 1000, y0 = 0, y1 = 1000})

				expect(w.x).to.equal(100)
				expect(w.y).to.equal(50)
				expect(w.w).to.equal(400)
				expect(w.h).to.equal(400)

				-- twice as wide as high (the screen's horizontal axis is world Y): full width, half height, centred vertically
				w = Chrome.FitWindow(area, {x0 = 0, x1 = 1000, y0 = 0, y1 = 2000})
				expect(w.w).to.equal(400)
				expect(w.h).to.equal(200)
				expect(w.x).to.equal(100)
				expect(w.y).to.equal(150)

				-- tall: centred across
				w = Chrome.FitWindow(area, {x0 = 0, x1 = 4000, y0 = 0, y1 = 1000})
				expect(w.w).to.equal(200)
				expect(w.h).to.equal(400)
				expect(w.x).to.equal(200)
				expect(w.y).to.equal(50)

				-- very long: the shape stops at 2:1
				w = Chrome.FitWindow(area, {x0 = 0, x1 = 1000, y0 = 0, y1 = 9000})
				expect(w.w).to.equal(400)
				expect(w.h).to.equal(200)
			end
		},
		-- fails without Chrome.PhaseOf
		{
			name = "the phase of the PDAArea clip from its frame and the labels of the movie: off before the opening, opening, on (the malfunction frames too), closing, off at the end",
			func = function()
				local Chrome = C()
				local labels = fresh().area.labels

				expect(labels.openSinglePlayer ~= nil and labels.on ~= nil and labels.closeSinglePlayer ~= nil and labels.off ~= nil).to.beTrue()
				expect(Chrome.PhaseOf(1, labels)).to.equal("off")
				expect(Chrome.PhaseOf(labels.openSinglePlayer, labels)).to.equal("opening")
				expect(Chrome.PhaseOf(labels.on - 1, labels)).to.equal("opening")
				expect(Chrome.PhaseOf(labels.on, labels)).to.equal("on")
				expect(Chrome.PhaseOf(labels.malfunction + 1, labels)).to.equal("on")
				expect(Chrome.PhaseOf(labels.closeSinglePlayer, labels)).to.equal("closing")
				expect(Chrome.PhaseOf(labels.off - 1, labels)).to.equal("closing")
				expect(Chrome.PhaseOf(labels.off, labels)).to.equal("off")
			end
		},
		-- fails without Inst:Open / Update: the movie must play its own opening (PDAArea, mask_02, Alpha_Layer), then stay on
		{
			name = "Open plays the movie's opening for about a second (mask_02 sweeps, Alpha_Layer fades in) and then the panel is on, with only the DONE button",
			func = function()
				local inst = fresh()

				expect(inst:Phase()).to.equal("off")
				inst:Open(0)
				expect(inst:Phase()).to.equal("opening")
				expect(inst.area:Child("mask_02"):CurrentLabel()).to.equal("openSinglePlayer")
				expect(inst.alpha:CurrentLabel()).to.equal("open")

				run(inst, 0.5)
				expect(inst:Phase()).to.equal("opening")

				run(inst, 1.5)
				expect(inst:Phase()).to.equal("on")
				expect(inst.area:Child("mask_02"):CurrentLabel()).to.equal("on")
				expect(inst.alpha:CurrentLabel()).to.equal("on")

				-- the single player strip: only DONE (the movie's own script chooses by _root.MultiPlayer, which is not run)
				local buttons = inst.area:Child("Buttons")

				expect(buttons ~= nil).to.beTrue()
				expect(buttons:CurrentLabel()).to.equal("SinglePlayer")
				expect(buttons:Child("BtnDone") ~= nil).to.beTrue()
				expect(buttons:Child("BtnSWITCH")).to.beNil()
				expect(buttons:Child("BtnSuicide")).to.beNil()
			end
		},
		-- fails without Chrome.RevealStage: the tiles are not masked by the movie, so they follow its mask_02 rectangle
		{
			name = "the part of the window that is revealed follows mask_02: a thin bar at first, then growing down to the whole window, whole when on",
			func = function()
				local inst = fresh()
				local window = C().AreaStage(inst.root)

				inst:Open(0)
				run(inst, 0.2)

				local bar = C().RevealStage(inst.root)

				expect(bar ~= nil).to.beTrue()
				expect(bar.h < 12).to.beTrue()

				-- growing: later frames reveal more, never less, and the bottom edge goes down
				local last = bar.h

				for _ = 1, 30 do
					run(inst, STEP)

					local r = C().RevealStage(inst.root)

					expect(r ~= nil).to.beTrue()
					expect(r.h >= last - 1e-6).to.beTrue()
					last = r.h
				end

				run(inst, 1)

				local full = C().RevealStage(inst.root)

				expect(inst:Phase()).to.equal("on")
				-- the whole window is under the revealed rectangle
				expect(full.x <= window.x and full.y <= window.y).to.beTrue()
				expect(full.x + full.w >= window.x + window.w and full.y + full.h >= window.y + window.h).to.beTrue()
			end
		},
		-- fails without Inst:Close: hidePDA
		{
			name = "Close plays the movie's closing (PDAArea closeSinglePlayer, Alpha_Layer close), the reveal shrinks, and the clip is finished when it reaches 'off'",
			func = function()
				local inst = fresh()

				inst:Open(0)
				run(inst, 2)
				expect(inst:Phase()).to.equal("on")
				expect(inst:IsFinished()).to.beFalse()

				inst:Close()
				expect(inst:Phase()).to.equal("closing")
				expect(inst.alpha:CurrentLabel()).to.equal("close")

				local before = C().RevealStage(inst.root).h

				run(inst, 0.3)

				local mid = C().RevealStage(inst.root)

				expect(inst:Phase()).to.equal("closing")
				expect(mid == nil or mid.h < before).to.beTrue()
				expect(inst:IsFinished()).to.beFalse()

				run(inst, 1.5)
				expect(inst:Phase()).to.equal("off")
				expect(inst:IsFinished()).to.beTrue()
			end
		},
		-- fails without Inst:SetStatus: the malfunction look
		{
			name = "a malfunction (status 1) puts the panel on its red malfunction frame with the uplink lost (core overlay playing, Status off); the end of it reboots to the normal frame",
			func = function()
				local inst = fresh()

				inst:Open(0)
				run(inst, 2)
				expect(inst:Jammed()).to.beFalse()

				inst:SetStatus(1)
				run(inst, 0.3)
				expect(inst:Jammed()).to.beTrue()
				expect(inst.area:CurrentFrame() >= inst.area.labels.malfunction).to.beTrue()
				expect(inst.core:CurrentFrame() > 1).to.beTrue()
				expect(inst.area:Find("Map_M.Status"):CurrentFrame() >= 13).to.beTrue() -- the strip plays its "off" part
				-- the map under the jam is dimmed to 35 percent and shaken
				expect(inst:ContentAlpha()).to.aboutEqual(0.35, 1e-9)

				inst:SetStatus(0)
				run(inst, 0.3)
				expect(inst:Jammed()).to.beFalse()
				expect(inst.area:CurrentFrame() < inst.area.labels.malfunction).to.beTrue()
				expect(inst.core:CurrentFrame()).to.equal(1)
				expect(inst:ContentAlpha()).to.equal(1)
				expect(inst:Phase()).to.equal("on")

				-- opening with the suit already down: the movie opens and goes to the malfunction frame at once (the original sends destroy(status) after showPDA)
				local down = fresh()

				down:Open(1)
				run(down, 2)
				expect(down:Jammed()).to.beTrue()
				expect(down.area:CurrentFrame() >= down.area.labels.malfunction).to.beTrue()
			end
		},
		-- fails without Inst:SetStatus 2: the flicker hides the movie as destroy(2) does
		{
			name = "a flicker (status 2) hides the panel and the map for its duration and shows them again at status 0; the animation is not restarted",
			func = function()
				local inst = fresh()

				inst:Open(0)
				run(inst, 2)
				expect(inst:IsHidden()).to.beFalse()
				inst:SetStatus(2)
				expect(inst:IsHidden()).to.beTrue()
				inst:SetStatus(0)
				expect(inst:IsHidden()).to.beFalse()
				expect(inst:Phase()).to.equal("on")
				expect(inst.area:CurrentFrame() < inst.area.labels.malfunction).to.beTrue()
			end
		},
		-- fails without the translation keys (hud_boot_strings.lua) or without the sanitising of the movie's other parts
		{
			name = "the movie's texts are English (the title 'STRATEGIC MAP ONLINE', 'ONLINE', 'DONE'), none is a raw @ui key, and the multiplayer parts are not shown",
			func = function()
				local inst = fresh()

				inst:Open(0)
				run(inst, 2)

				local all = texts(inst.root)

				expect(has(all, "STRATEGIC MAP ONLINE")).to.beTrue()
				expect(has(all, "ONLINE")).to.beTrue()
				expect(has(all, "DONE")).to.beTrue()

				for _, text in ipairs(all) do
					expect(string.sub(text, 1, 1) ~= "@").to.beTrue()
				end

				-- the team buttons are gone with the SinglePlayer strip
				expect(has(all, "btn SWITCHTEAM")).to.beFalse()
				expect(has(all, "btn SUICIDE")).to.beFalse()

				-- the flags, the marker and ping templates, the picture of the movie, the info box and the root's helper fields are hidden
				local flag = inst.area:Child("Flag_US")

				expect(flag == nil or flag.visible == false).to.beTrue()
				flag = inst.area:Child("Flag_Korean")
				expect(flag == nil or flag.visible == false).to.beTrue()

				local mapArea = inst.area:Find("Map_M.MapArea")

				for _, name in ipairs({"Map", "infoBox", "ObjectIcon", "EventIcon"}) do
					local child = mapArea:Child(name)

					expect(child ~= nil and child.visible == false).to.beTrue()
				end

				for _, name in ipairs({"Line", "Over", "Text"}) do
					expect(inst.root:Child(name).visible).to.beFalse()
				end
			end
		},
		-- fails when the rebuild of the clips (a reboot goes back to an earlier frame) loses what was hidden
		{
			name = "what is hidden stays hidden after a malfunction and its reboot rebuilt the clips",
			func = function()
				local inst = fresh()

				inst:Open(0)
				run(inst, 2)
				inst:SetStatus(1)
				run(inst, 0.5)
				inst:SetStatus(0)
				run(inst, 0.5)

				local mapArea = inst.area:Find("Map_M.MapArea")

				for _, name in ipairs({"Map", "infoBox", "ObjectIcon", "EventIcon"}) do
					expect(mapArea:Child(name).visible).to.beFalse()
				end

				expect(inst.area:Child("Buttons"):CurrentLabel()).to.equal("SinglePlayer")
			end
		},
		-- fails without Chrome.ShakeStep
		{
			name = "the shake of a lost uplink is the original's: both phases advance by up to 2 per step and the offset is 3 stage pixels times cos and sin",
			func = function()
				local Chrome = C()
				local wx, wy, dx, dy = Chrome.ShakeStep(0, 0, 0, 0)

				expect(wx).to.equal(0)
				expect(wy).to.equal(0)
				expect(dx).to.aboutEqual(3, 1e-9)
				expect(dy).to.aboutEqual(0, 1e-9)

				wx, wy, dx, dy = Chrome.ShakeStep(0, 0, 0.5, 1)
				expect(wx).to.equal(1)
				expect(wy).to.equal(2)
				expect(dx).to.aboutEqual(3 * math.cos(1), 1e-9)
				expect(dy).to.aboutEqual(3 * math.sin(2), 1e-9)

				-- never further than the radius
				for i = 1, 50 do
					wx, wy, dx, dy = Chrome.ShakeStep(wx, wy, 0.37, 0.91)
					expect(dx * dx + dy * dy <= 18 + 1e-9).to.beTrue()
				end

				-- the offset of a jammed instance is 0 at rest and follows the placement
				local inst = fresh()

				inst:Open(0)
				run(inst, 2)

				local x, y = inst:ShakeOffset()

				expect(x).to.equal(0)
				expect(y).to.equal(0)
				inst:SetStatus(1)
				run(inst, 1)
				inst.scale = 2
				x, y = inst:ShakeOffset()
				expect(x * x + y * y <= 4 * 18 + 1e-9).to.beTrue()
			end
		},
		-- fails without Inst:SetObjectiveCell: the movie's OBJECTIVE: strip
		{
			name = "the cell of the main objective goes into the movie's OBJECTIVE: field (the DEPLOY SPOT label is blanked); no objective hides the strip",
			func = function()
				local inst = fresh()

				inst:Open(0)
				run(inst, 2)

				local strip = inst.area:Child("TextBottom")

				expect(strip ~= nil).to.beTrue()
				expect(strip.visible).to.beFalse()

				inst:SetObjectiveCell("C4")
				-- a second of frames: the strip's own timeline loops (gotoAndStop(1) lost its stop in the conversion) and would rebuild the blanked label
				run(inst, 1)
				expect(strip.visible).to.beTrue()

				local all = texts(inst.root)

				expect(has(all, "OBJECTIVE:")).to.beTrue()
				expect(has(all, "C4")).to.beTrue()
				expect(has(all, "DEPLOY SPOT:")).to.beFalse()

				inst:SetObjectiveCell(nil)
				inst:Update(STEP)
				expect(strip.visible).to.beFalse()
			end
		},
		-- fails without Inst:DoneRect / SetDone
		{
			name = "the DONE button: its rectangle is the movie's own (bottom right of the panel), and rolling over it plays the movie's over, out and press animations",
			func = function()
				local Chrome = C()
				local inst = fresh()

				expect(inst:DoneRect(0, 0, 1)).to.beNil() -- not open: no button yet

				inst:Open(0)
				run(inst, 2)

				local rect = inst:DoneRect(0, 0, 1)

				expect(rect ~= nil).to.beTrue()
				expect(rect.x).to.aboutEqual(870.5, 1.5)
				expect(rect.y).to.aboutEqual(585.3, 1.5)
				expect(rect.w).to.aboutEqual(124.7, 3)
				expect(rect.h).to.aboutEqual(24.1, 2)

				-- the rectangle follows the placement
				local ox, oy, scale = Chrome.Placement(1920, 1080)
				local screen = inst:DoneRect(ox, oy, scale)

				expect(screen.w).to.aboutEqual(rect.w * scale, 1e-6)
				expect(screen.x).to.aboutEqual(ox + rect.x * scale, 1e-6)
				expect(screen.y > 540 and screen.x > 960).to.beTrue()

				local done = inst.area:Find("Buttons.BtnDone")

				-- the movie's own scripts: "over" and "out" jump at once to their still frames (over_noanim, out_noanim), "press" stays
				expect(done:CurrentLabel()).to.equal("off")
				inst:SetDone("over")
				expect(done:CurrentLabel()).to.equal("over_noanim")
				inst:SetDone("press")
				expect(done:CurrentLabel()).to.equal("press")
				inst:SetDone("off")
				expect(done:CurrentLabel()).to.equal("out_noanim")
			end
		},
		-- fails without the hook installation: the tiles are drawn by the movie's own drawing, in the middle of MapArea
		{
			name = "Draw hands the movie's drawing a hook in MapArea just before its info box (depth 2), draws once, and puts the hook back after the clips were rebuilt",
			func = function(state)
				local inst = fresh()
				local calls = {}

				GryMod.Flash.Draw = function(clip, x, y, scale)
					calls[#calls + 1] = {clip, x, y, scale}

					return true
				end

				inst:Open(0)
				run(inst, 2)
				inst:Draw(10, 20, 2)

				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal(inst.root)
				expect(calls[1][2]).to.equal(10)
				expect(calls[1][4]).to.equal(2)

				local mapArea = inst.area:Find("Map_M.MapArea")

				expect(mapArea.drawBefore ~= nil).to.beTrue()
				expect(mapArea.drawBeforeDepth).to.equal(2)

				local hook = mapArea.drawBefore

				-- the clips are rebuilt (a reboot returns to an earlier frame): a new MapArea gets the hook again
				inst:SetStatus(1)
				run(inst, 0.5)
				inst:SetStatus(0)
				run(inst, 0.5)
				inst:Draw(10, 20, 2)
				mapArea = inst.area:Find("Map_M.MapArea")
				expect(mapArea.drawBefore).to.equal(hook)
				expect(mapArea.drawBeforeDepth).to.equal(2)

				-- the hook calls the content function once, with the screen rectangle that is revealed inside the window
				local got = {}

				inst:SetContent(function(x0, y0, x1, y1, alpha)
					got[#got + 1] = {x0, y0, x1, y1, alpha}
				end)
				inst:Draw(0, 0, 1)
				hook()
				expect(#got).to.equal(1)

				local window = C().AreaStage(inst.root)

				expect(got[1][1]).to.aboutEqual(window.x, 1)
				expect(got[1][2]).to.aboutEqual(window.y, 1)
				expect(got[1][3]).to.aboutEqual(window.x + window.w, 1)
				expect(got[1][4]).to.aboutEqual(window.y + window.h, 1)
				expect(got[1][5]).to.equal(1)

				-- hidden (a flicker) or not started: no drawing at all
				inst:SetStatus(2)
				inst:Draw(0, 0, 1)
				expect(#calls).to.equal(3)
			end
		}
	}
}
