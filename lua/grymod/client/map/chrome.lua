-- The big map's chrome (GryMod.Map.Chrome): the frame of the real Crysis PDA map, drawn from the original Scaleform movie HUD_PDA_Map (converted by
-- dev_resources/flash2lua, see cl_flash.lua). The movie holds the panel's outline, the title, the "uplink online" strip, the DONE button, the dark backdrop and the
-- opening and closing animations. It holds NO map: the original's C++ places its one picture in the clip Map_G, and here the tiles of the big map (panel.lua)
-- are drawn instead, inside the movie's own map window, by a hook of the Flash player (clip.drawBefore, as the radar does for its map).
--
-- WHAT IS PORTED BY HAND. The original script of the movie (root of HUD_PDA_Map) is run by hand for the parts the player does not run:
--   showPDA / hidePDA   the PDAArea clip plays "openSinglePlayer" (its frames also play the clip mask_02, the screen opening) and the backdrop Alpha_Layer plays
--                       "open"; closing plays "closeSinglePlayer" and "close". (The original's own closing script plays mask_02 through a misspelt name, so its mask
--                       never closes; here it does.)
--   destroy(1) / reboot / setDisconnect   the malfunction frame, the return to the normal frame, the "Satellite Uplink disconnected" overlay (core) and the
--                       blinking status. The original also dims the map to 35 percent and shakes it by 3 pixels while it is disconnected: the content function is told
--                       the alpha (ContentAlpha) and the shake (ShakeOffset).
--   the single player strip: only the DONE button (Buttons goes to "SinglePlayer"); the team buttons, the Korean flag and the multiplayer texts are hidden.
--                       The US flag between the header's brackets stays: the original's script (PDAArea frame 17) shows the flag of _root.PlayerTeam, which the
--                       original's C++ sets to US for the player.
--   Map_G / infoBox / the marker and ping templates are hidden: the movie's picture is NOT used, the map draws its own tiles and markers.
-- WHAT THE PLAYER CANNOT DRAW. Static texts (the letters A to H and the numbers 1 to 8 of the sector grid, "SECTOR 08", "SATELLITE UPLINK") are not drawn by the
-- Flash player (the converter writes them as `stext`): the grid letters stay the map's own drawing.
--
-- WHERE THE MOVIE GOES. The stage is 1024 x 768 (4:3) but the panel only fills its right part (x 570 to 1003, y 47 to 612). It is NOT put where the stage would be
-- centred (a 16:9 screen would show the panel right of the middle, small): the PANEL rectangle is centred on the screen and made 92 percent of the screen's
-- height (96 percent of its width on a narrow screen). On 16:9 the map window is then a square about two thirds of the screen's height; the window of the bounds'
-- shape (1:2 to 2:1, Frame.WindowSize) sits inside it, centred.
--
-- The pure functions (placement, rectangles, phases, shake) need no engine; the instance needs the Flash player (cl_flash.lua) and draws with Flash.Draw.

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}
GryMod.Map.Chrome = GryMod.Map.Chrome or {}

local Chrome = GryMod.Map.Chrome

Chrome.MOVIE = "hud_pda_map"

-- the part of the stage the panel fills (stage pixels): the outline x 572 to 1001, y 49 to 599, and the DONE button under it down to 609, with a margin
Chrome.PANEL = {x0 = 570, y0 = 47, x1 = 1003, y1 = 612}
-- the free right half of the movie's text strip under the window (the left half holds OBJECTIVE: and the cell of the main objective): the map's hint goes there
Chrome.STRIP = {x0 = 745, y0 = 501, x1 = 993, y1 = 530}
Chrome.FILL_HEIGHT = 0.92
Chrome.FILL_WIDTH = 0.96

-- the movie's own colours (the defaults of its script: line #607050, over #d88b32, text #b5d68e); the HUD theme replaces them
Chrome.DEFAULT_THEME = {Line = {96, 112, 80}, Over = {216, 139, 50}, Text = {181, 214, 142}}

-- where in MapArea's drawing the map goes: just before the entry at this depth (the info box), after the picture of the movie (depth 1, hidden)
Chrome.CONTENT_DEPTH = 2

-- the original dims the map to 35 percent and shakes it by 3 pixels (stage) while the uplink is lost
Chrome.JAM_ALPHA = 0.35
Chrome.SHAKE_RADIUS = 3
Chrome.SHAKE_RATE = 30

-- what the movie shows that the big map does not use, by instance name, at each level of the tree
Chrome.HIDE = {
	root = {"Line", "Over", "Text"}, -- (the root's two empty text fields lie above the stage)
	pda = {"Flag_Korean"}, -- (the US flag is shown: the original's script shows the player's team flag, and the player of single player is US)
	map = {"HelpBar", "HideBtn_M"},
	area = {"Map", "infoBox", "ObjectIcon", "EventIcon"}
}

local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local cos, sin, random = math.cos, math.sin, math.random

-- pure ---------------------------------------------------------------------------------------------------------------------------------------------------

-- Where the stage goes on a screen of sw x sh pixels: the origin (x, y) and the scale. The PANEL rectangle is centred and as large as the fill limits allow.
function Chrome.Placement(sw, sh)
	local P = Chrome.PANEL
	local panelW, panelH = P.x1 - P.x0, P.y1 - P.y0
	local scale = min(Chrome.FILL_HEIGHT * sh / panelH, Chrome.FILL_WIDTH * sw / panelW)

	return sw / 2 - (P.x0 + P.x1) / 2 * scale, sh / 2 - (P.y0 + P.y1) / 2 * scale, scale
end

-- A stage rectangle {x, y, w, h} on the screen.
function Chrome.ToScreen(ox, oy, scale, rect)
	return {x = ox + rect.x * scale, y = oy + rect.y * scale, w = rect.w * scale, h = rect.h * scale}
end

-- The window of the bounds' shape inside the movie's window `area` ({x, y, w, h}, whole pixels): as large as fits, centred.
function Chrome.FitWindow(area, bounds)
	local w, h = GryMod.Map.Frame.WindowSize(area.w, area.h, bounds)

	return {x = floor(area.x + (area.w - w) / 2), y = floor(area.y + (area.h - h) / 2), w = w, h = h}
end

-- The phase of the PDAArea clip from its frame and its labels: "off" (before the opening and after the closing), "opening", "on" (the malfunction frames too), "closing".
function Chrome.PhaseOf(frame, labels)
	local open, on, close, off = labels.openSinglePlayer, labels.on, labels.closeSinglePlayer, labels.off

	if not (open and on and close and off) then
		return "off"
	end

	if frame >= off then
		return "off"
	elseif frame >= close then
		return "closing"
	elseif frame >= on then
		return "on"
	elseif frame >= open then
		return "opening"
	end

	return "off"
end

-- One step of the original's shake of a lost uplink (an onEnterFrame of the movie): both phases move on by up to 2, the offset is the radius times cos and sin.
-- r1 and r2 are numbers from 0 to 1. Returns the new phases and the offset in stage pixels.
function Chrome.ShakeStep(wx, wy, r1, r2)
	wx, wy = wx + 2 * r1, wy + 2 * r2

	return wx, wy, Chrome.SHAKE_RADIUS * cos(wx), Chrome.SHAKE_RADIUS * sin(wy)
end

-- matrices are {a, b, c, d, tx, ty}: the point (x, y) goes to (a x + c y + tx, b x + d y + ty). mul(p, m) is m applied first, then p.
local function mul(p, m)
	return {
		p[1] * m[1] + p[3] * m[2], p[2] * m[1] + p[4] * m[2],
		p[1] * m[3] + p[3] * m[4], p[2] * m[3] + p[4] * m[4],
		p[1] * m[5] + p[3] * m[6] + p[5], p[2] * m[5] + p[4] * m[6] + p[6]
	}
end

local IDENTITY = {1, 0, 0, 1, 0, 0}

-- The matrix from the clip at `path` (dotted instance names under `root`) to the stage, or nil when a name is missing.
function Chrome.StageMatrix(root, path)
	local m = IDENTITY
	local current = root

	for name in string.gmatch(path, "[^.]+") do
		local child = current.Child and current:Child(name)

		if not child then
			return nil
		end

		local entry = child.entry or child

		if not entry.m then
			return nil
		end

		m = mul(m, entry.m)
		current = child
	end

	return m
end

-- The local rectangle (x0, y0, x1, y1) of what an entry draws: a shape, a text field, or a morph at its ratio.
local function localRect(movie, entry)
	local d = movie.chars[entry.id]

	if not d then
		return nil
	end

	if d.k == "shape" then
		return d.ox, d.oy, d.ox + d.dw, d.oy + d.dh
	elseif d.k == "text" then
		return d.ox, d.oy, d.ox + d.w, d.oy + d.h
	elseif d.k == "morph" and d.ex then
		local r = max(0, min(1, (entry.ratio or 0) / 65535))

		return d.ox + (d.ex - d.ox) * r, d.oy + (d.ey - d.oy) * r,
			d.ox + d.w + ((d.ex + d.ew) - (d.ox + d.w)) * r, d.oy + d.h + ((d.ey + d.eh) - (d.oy + d.h)) * r
	end

	return nil
end

-- The box of the four corners of a local rectangle under matrix m: x0, y0, x1, y1.
local function transformed(m, x0, y0, x1, y1)
	local xs, ys = {}, {}
	local corners = {x0, y0, x1, y0, x0, y1, x1, y1}

	for i = 1, 4 do
		local x, y = corners[i * 2 - 1], corners[i * 2]

		xs[i], ys[i] = m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
	end

	return min(xs[1], xs[2], xs[3], xs[4]), min(ys[1], ys[2], ys[3], ys[4]), max(xs[1], xs[2], xs[3], xs[4]), max(ys[1], ys[2], ys[3], ys[4])
end

local function rectTable(x0, y0, x1, y1)
	return {x = x0, y = y0, w = x1 - x0, h = y1 - y0}
end

-- The stage rectangle of one entry (a shape or morph placed in a clip), when its clip's matrix to the stage is `parent`.
local function entryRect(movie, entry, parent)
	local x0, y0, x1, y1 = localRect(movie, entry)

	if not x0 then
		return nil
	end

	return rectTable(transformed(mul(parent, entry.m), x0, y0, x1, y1))
end

-- The window of the map in the stage: the rectangle the movie clips its map to (the mask at the bottom of Map_M, about 410 x 409 at (582, 85)).
function Chrome.AreaStage(root)
	local mapM = root:Find("Root.PDAArea.Map_M")
	local mask = mapM and mapM:EntryAt(1)

	if not mask or not mask.clipDepth then
		return nil
	end

	return entryRect(root.movie, mask, Chrome.StageMatrix(root, "Root.PDAArea.Map_M"))
end

-- The part of the stage the movie's screen-opening mask (PDAArea.mask_02) shows now, or nil when it is not there. The tiles are not masked by the movie (its masks cut
-- what it draws itself), so the map draws inside this rectangle to open and close with the frame.
function Chrome.RevealStage(root)
	local mask = root:Find("Root.PDAArea.mask_02")
	local entry = mask and mask:EntryAt(1)

	if not entry then
		return nil
	end

	return entryRect(root.movie, entry, Chrome.StageMatrix(root, "Root.PDAArea.mask_02"))
end

-- The box of everything a clip draws (visible clips only), in the stage, when the matrix of the clip to the stage is `m`. nil when it draws nothing.
local function clipBox(movie, clip, m, box)
	for _, entry in ipairs(clip:Entries()) do
		if not entry.clipDepth then
			if entry.clip then
				if entry.clip.visible then
					box = clipBox(movie, entry.clip, mul(m, entry.m), box)
				end
			else
				local x0, y0, x1, y1 = localRect(movie, entry)

				if x0 then
					x0, y0, x1, y1 = transformed(mul(m, entry.m), x0, y0, x1, y1)

					if box then
						box[1], box[2], box[3], box[4] = min(box[1], x0), min(box[2], y0), max(box[3], x1), max(box[4], y1)
					else
						box = {x0, y0, x1, y1}
					end
				end
			end
		end
	end

	return box
end

-- the instance ---------------------------------------------------------------------------------------------------------------------------------------

local Inst = {}
Inst.__index = Inst

-- Whether the movie and the player are there (the big map falls back on its plain panel when they are not).
function Chrome.Available()
	local Flash = GryMod.Flash

	return Flash ~= nil and Flash.Load ~= nil and Flash.Draw ~= nil and Flash.Load(Chrome.MOVIE) ~= nil
end

-- A chrome from the converted movie (nil when the movie is missing or is not the one expected). `theme` = {Line, Over, Text} colours: the HUD's by default.
function Chrome.New(movie, theme)
	local Flash = GryMod.Flash

	if not movie or not Flash then
		return nil
	end

	local root = Flash.NewRoot(movie, theme or (GryMod.FlashHUD and GryMod.FlashHUD.Theme) or Chrome.DEFAULT_THEME)
	local main = root:Child("Root")
	local area = main and main:Child("PDAArea")
	local alpha = main and main:Child("Alpha_Layer")
	local core = root:Child("core")
	local window = Chrome.AreaStage(root)

	if not (area and alpha and core and window) then
		return nil
	end

	local inst = setmetatable({
		root = root, main = main, area = area, alpha = alpha, core = core,
		window = window,
		status = 0, jam = false, hidden = false, started = false, closing = false,
		doneState = "off", objectiveCell = nil,
		ox = 0, oy = 0, scale = 1,
		shakeX = 0, shakeY = 0, shakeTime = 0, shakePhaseX = 0, shakePhaseY = 0
	}, Inst)

	-- the function the movie's drawing calls inside MapArea: made once, it reads what the instance holds when it runs
	inst.hook = function()
		inst:_runContent()
	end

	return inst
end

function Inst:Phase()
	return Chrome.PhaseOf(self.area:CurrentFrame(), self.area.labels)
end

function Inst:IsFinished()
	return self.closing and self:Phase() == "off"
end

function Inst:IsHidden()
	return self.hidden
end

function Inst:Jammed()
	return self.jam
end

-- The alpha the map's content is drawn with: 35 percent while the uplink is lost, as the original's Map_M.
function Inst:ContentAlpha()
	return self.jam and Chrome.JAM_ALPHA or 1
end

-- The shake of the content in screen pixels (0 when the uplink works).
function Inst:ShakeOffset()
	return self.shakeX * self.scale, self.shakeY * self.scale
end

-- showPDA() then destroy(status): the panel opens, and goes to the malfunction look at once when the suit is already down.
function Inst:Open(status)
	self.started, self.closing = true, false
	self.status = (status == 1 or status == 2) and status or 0
	self.jam, self.hidden = false, false
	self.core:GotoAndStop(1)
	self.area:GotoAndPlay("openSinglePlayer")
	self.alpha:GotoAndPlay("open")
	self.doneState = "off"
	self:_sanitise()
	self:_applyStatus(0)
end

-- hidePDA(): the closing animations. The movie's script plays mask_02 through a misspelt name; here it closes too.
function Inst:Close()
	if not self.started or self.closing then
		return
	end

	self.closing = true

	local before = self:_snapshot()

	self.area:GotoAndPlay("closeSinglePlayer")

	-- the forward jump replays the malfunction frame, which paints the frame, the strip and the DONE glow red (see _undoMalfunction)
	if self.status ~= 1 then
		self:_undoMalfunction(before)
	end

	local mask = self.area:Child("mask_02")

	if mask then
		mask:GotoAndPlay("closeSinglePlayer")
	end

	self.alpha:GotoAndPlay("close")
end

-- What the PDAArea clip shows by depth: {matrix, colour transform} of each entry (the tables are replaced, not changed, by the movie's moves, so the references keep).
function Inst:_snapshot()
	local list = {}

	for _, entry in ipairs(self.area:Entries()) do
		list[entry.depth] = {m = entry.m, cx = entry.cx}
	end

	return list
end

-- WHY THE PANEL WENT RED WHEN IT CLOSED. The timeline of PDAArea is on, malfunction (red: a colour transform that adds 255 red to the frame's outline, the strip under the
-- window and the DONE glow, and a second copy of that glow), then closeSinglePlayer, which only puts three of those clips back. Like Flash does, the player replays
-- the frames in between on a forward jump, so closing a panel that works passed through the malfunction frame and flashed the whole frame red for the length of the
-- closing. The original's own script jumps the same way (the red is in its timeline: it is only meant for a closing during a malfunction). Here a closing of a panel that
-- works puts back what the jump has painted red (its matrix and colour from before the jump) and drops what only the malfunction frame adds.
function Inst:_undoMalfunction(before)
	local area = self.area
	local drop, fix = {}, {}

	for _, entry in ipairs(area:Entries()) do
		local cx = entry.cx
		local old = before[entry.depth]

		if not old then
			-- a clip that only exists in the malfunction look (the second glow)
			if cx and cx[5] > 0 and cx[6] == 0 and cx[7] == 0 then
				drop[#drop + 1] = entry.depth
			end
		elseif cx and cx ~= old.cx and cx[5] > 0 and cx[6] == 0 and cx[7] == 0 then
			fix[#fix + 1] = entry
		end
	end

	for i = 1, #drop do
		area:_remove(drop[i])
	end

	for i = 1, #fix do
		local entry = fix[i]
		local old = before[entry.depth]

		entry.cx, entry.m = old.cx, old.m
	end

	if #drop > 0 or #fix > 0 then
		area:_touch()
	end
end

-- Whether the panel is in a state where the suit's malfunction changes its look (opening or on).
function Inst:_alive()
	if not self.started or self.closing then
		return false
	end

	local phase = self:Phase()

	return phase == "opening" or phase == "on"
end

-- setDisconnect(b): the overlay of the lost uplink and the status strip.
function Inst:_setJam(jam)
	if self.jam == jam then
		return
	end

	self.jam = jam

	local mapM = self.area:Child("Map_M")
	local status = mapM and mapM:Child("Status")

	if jam then
		self.core:GotoAndPlay(2)

		if status then
			status:GotoAndPlay("off")
		end
	else
		self.core:GotoAndStop(1)
		self.shakeX, self.shakeY = 0, 0

		if status then
			status:GotoAndPlay(2)
		end
	end
end

-- The status of the HUD (0 working, 1 malfunction, 2 flicker; GryMod_HUDStatus): destroy(status) of the original, with the reboot at the end of a malfunction.
function Inst:SetStatus(status)
	status = (status == 1 or status == 2) and status or 0

	local old = self.status

	self.status = status

	if self.started then
		self:_applyStatus(old)
	end
end

function Inst:_applyStatus(old)
	local status = self.status

	if status == 2 then
		self.hidden = true

		return
	end

	self.hidden = false

	if status == 1 then
		if old ~= 1 and self:_alive() then
			self.area:GotoAndStop("malfunction")
		end

		if self:_alive() then
			self:_setJam(true)
		end
	elseif self.jam then
		-- reboot(): back to the normal frame
		if self:_alive() then
			self.area:GotoAndPlay("on")
		end

		self:_setJam(false)
	end
end

-- The clips of the movie are rebuilt when its timeline goes back (a reboot): what must be hidden, and what the movie's scripts did to a clip that was made again,
-- is put back each frame (a few lookups).
function Inst:_sanitise()
	local root, area = self.root, self.area

	for _, name in ipairs(Chrome.HIDE.root) do
		local clip = root:Child(name)

		if clip and clip.SetVisible then
			clip:SetVisible(false)
		end
	end

	for _, name in ipairs(Chrome.HIDE.pda) do
		local clip = area:Child(name)

		if clip and clip.SetVisible then
			clip:SetVisible(false)
		end
	end

	local mapM = area:Child("Map_M")

	if mapM then
		-- the script of Map_G (sprite 26) starts the map's own frames; the player does not run it
		if mapM ~= self.mapMClip then
			self.mapMClip = mapM
			mapM:GotoAndPlay("map")
		end

		for _, name in ipairs(Chrome.HIDE.map) do
			local clip = mapM:Child(name)

			if clip and clip.SetVisible then
				clip:SetVisible(false)
			end
		end

		local status = mapM:Child("Status")

		if status and status ~= self.statusClip then
			self.statusClip = status

			if self.jam then
				status:GotoAndPlay("off")
			end
		end

		local mapArea = mapM:Child("MapArea")

		self.mapArea = mapArea

		if mapArea then
			for _, name in ipairs(Chrome.HIDE.area) do
				local clip = mapArea:Child(name)

				if clip and clip.SetVisible then
					clip:SetVisible(false)
				end
			end
		end
	else
		self.mapArea = nil
	end

	-- the single player strip: only the DONE button
	local buttons = area:Child("Buttons")

	if buttons and buttons:CurrentLabel() ~= "SinglePlayer" then
		buttons:GotoAndStop("SinglePlayer")
	end

	if buttons and buttons ~= self.buttonsClip then
		self.buttonsClip = buttons
		self.doneApplied = nil
	end

	-- the strip under the window: the cell of the main objective, or nothing
	local bottom = area:Child("TextBottom")

	if bottom then
		if bottom ~= self.bottomClip then
			self.bottomClip = bottom
			self.bottomText = nil
			-- its second frame says gotoAndStop(1) and the converter dropped the stop: without this it would rebuild its texts every other frame
			bottom:Stop()
			-- the label of the deploy spot belongs to the multiplayer
			bottom:MapText(function(text)
				if text == "DEPLOY SPOT:" then
					return ""
				end

				return text
			end)
		end

		bottom:SetVisible(self.objectiveCell ~= nil)

		if self.bottomText ~= self.objectiveCell then
			self.bottomText = self.objectiveCell

			local colours = bottom:Child("Colorset")

			if colours then
				colours:SetText("ObjectiveText", self.objectiveCell or "")
			end
		end
	end

	-- a DONE button that was made again starts in its state
	local done = buttons and buttons:Child("BtnDone")

	if done and self.doneApplied ~= done then
		self.doneApplied = done

		if self.doneState ~= "off" then
			done:GotoAndPlay(self.doneState)
		end
	end
end

-- The cell of the main objective (the "C4" of the grid) for the strip under the window, or nil for none.
function Inst:SetObjectiveCell(text)
	self.objectiveCell = (type(text) == "string" and text ~= "") and text or nil
end

-- The state of the DONE button from the mouse: "off", "over" or "press". The movie's own animations play.
function Inst:SetDone(state)
	if state ~= "over" and state ~= "press" then
		state = "off"
	end

	if state == self.doneState then
		return
	end

	local old = self.doneState

	self.doneState = state

	local buttons = self.area:Child("Buttons")
	local done = buttons and buttons:Child("BtnDone")

	if not done then
		return
	end

	self.doneApplied = done

	if state == "off" then
		if old ~= "off" then
			done:GotoAndPlay("out")
		end
	else
		done:GotoAndPlay(state)
	end
end

-- The rectangle of the DONE button on the screen, for the stage placed at (ox, oy) with the scale, or nil while the button is not there.
function Inst:DoneRect(ox, oy, scale)
	local buttons = self.area:Child("Buttons")
	local done = buttons and buttons:Child("BtnDone")

	if not done or not done.entry then
		return nil
	end

	if self.doneBoxClip ~= done then
		local m = mul(Chrome.StageMatrix(self.root, "Root.PDAArea.Buttons"), done.entry.m)
		local box = clipBox(self.root.movie, done, m, nil)

		if not box then
			return nil
		end

		self.doneBoxClip, self.doneBox = done, box
	end

	local box = self.doneBox

	return {x = ox + box[1] * scale, y = oy + box[2] * scale, w = (box[3] - box[1]) * scale, h = (box[4] - box[2]) * scale}
end

-- The function the map draws its content with: content(x0, y0, x1, y1, alpha) with the screen rectangle of the window that is revealed now.
function Inst:SetContent(fn)
	self.content = fn
end

-- The screen rectangle of the window that the opening or closing mask reveals now (whole pixels, outward), or nil when nothing is.
function Inst:ContentRect()
	local reveal = Chrome.RevealStage(self.root)

	if not reveal then
		return nil
	end

	local window = self.window
	local x0, y0 = max(window.x, reveal.x), max(window.y, reveal.y)
	local x1, y1 = min(window.x + window.w, reveal.x + reveal.w), min(window.y + window.h, reveal.y + reveal.h)

	if x1 <= x0 or y1 <= y0 then
		return nil
	end

	local ox, oy, scale = self.ox, self.oy, self.scale

	return floor(ox + x0 * scale), floor(oy + y0 * scale), ceil(ox + x1 * scale), ceil(oy + y1 * scale)
end

function Inst:_runContent()
	local content = self.content

	if not content then
		return
	end

	local x0, y0, x1, y1 = self:ContentRect()

	if x0 then
		content(x0, y0, x1, y1, self:ContentAlpha())
	end
end

-- Moves the movie on by dt seconds: the clips, then what the movie's scripts do that the player does not run, and the shake of a lost uplink.
function Inst:Update(dt)
	if not self.started then
		return
	end

	self.root:Advance(dt)
	self:_sanitise()

	if self.jam then
		self.shakeTime = self.shakeTime + (dt > 0 and dt or 0)

		local steps = floor(self.shakeTime * Chrome.SHAKE_RATE)

		if steps > 0 then
			self.shakeTime = self.shakeTime - steps / Chrome.SHAKE_RATE

			for _ = 1, min(steps, 4) do
				self.shakePhaseX, self.shakePhaseY, self.shakeX, self.shakeY = Chrome.ShakeStep(self.shakePhaseX, self.shakePhaseY, random(), random())
			end
		end
	end
end

-- Draws the movie with the stage at (ox, oy) and `scale` pixels per stage pixel; the content function is called from inside, in the map window. Returns false when
-- nothing was drawn (not open, finished, hidden by a flicker, or the drawing failed).
function Inst:Draw(ox, oy, scale)
	if not self.started or self.hidden or self:IsFinished() then
		return false
	end

	self.ox, self.oy, self.scale = ox, oy, scale

	local mapArea = self.mapArea

	if mapArea and (mapArea.drawBefore ~= self.hook or mapArea.drawBeforeDepth ~= Chrome.CONTENT_DEPTH) then
		mapArea.drawBefore, mapArea.drawBeforeDepth = self.hook, Chrome.CONTENT_DEPTH
	end

	return GryMod.Flash.Draw(self.root, ox, oy, scale) ~= false
end

-- Lets the clips of the movie go (their cached images).
function Inst:Release()
	if GryMod.Flash.ReleaseClip then
		GryMod.Flash.ReleaseClip(self.root)
	end
end
