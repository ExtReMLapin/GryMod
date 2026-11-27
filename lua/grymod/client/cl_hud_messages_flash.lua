-- The text lines of the HUD drawn from the original Scaleform movie (HUD_Messages), see cl_flash.lua. The movie has four lanes
-- (Root1 to Root4); each of the two stacks (the top lane and the one under the centre) holds seven lines, a new line enters at the
-- end and pushes the older ones along, each line lives 150 frames (5 s at 30 a second) and fades out in its last 60. The movie's own
-- ActionScript does three things the player does not run, so they are done here: copying the texts and the frames of the lines when a
-- new one comes, making the dark plate behind a line 50 pixels wider than its text, and clearing a line that is over.
--
-- What shows a line is ONE HUD event, "message" (docs/events.md): it draws the text and plays its sound together, whoever asks, the
-- game's own triggers (the suit's lines, below) or an addon (GryMod.API.ShowMessage(text, opts) on the client, the same call with a
-- player in front on the server, sv_messages.lua). The shared data and the limits are in sh_messages.lua.
--
-- Nothing runs when no line is shown: the paint hook is added by the first line and removed when the last one is over.

GryMod = GryMod or {}

local Flash = GryMod.Flash
local API = GryMod.API
local Messages = GryMod.Messages

local Module = {}
GryMod.FlashMessages = Module

Module.MOVIE = "hud_messages"

local STAGE_W, STAGE_H = 1024, 768

-- Which clip of the movie each lane is, and which lines it has. The top lane and the one under the centre are stacks of seven lines
-- (Message4 oldest ... Message10 newest); the two others show one line (their other lines are placed outside the screen).
local ROOTS = {top = "Root2", middle = "Root3", status = "Root1", crosshair = "Root4"}
local STACK = {4, 5, 6, 7, 8, 9, 10}
local SINGLE = {10}
local SLOTS = {top = STACK, status = STACK, middle = SINGLE, crosshair = SINGLE}

-- The two lanes that show one line do not end by themselves: the movie stops the line and the game fades it out when it wants
-- (fadeOutMiddleLine, fadeOutCrossHairLine). Here it is the same fade, started after this part of the life of the line (the movie's
-- fade is the last 60 of its 150 frames).
local HOLD = {middle = true, crosshair = true}
local HOLD_PART = 0.6

Module.PLATE_PAD = 50 -- the plate is this much wider than the text (Update() of the movie)
Module.PLATE_BASE = 2.8 -- the width of the plate's picture at 100 percent
Module.FIELD_MAX = 1000 -- the room a line has (stage pixels)

-- The scale (percent) of the plate's picture for a text this wide (the text's width, margins left out, in stage pixels).
function Module.PlateScale(textWidth)
	return (textWidth + 4 + Module.PLATE_PAD) / Module.PLATE_BASE * 100
end

-- The picture of the stage on a screen of w x h pixels: as high as the screen, centred across its width (the same rule as the other
-- movies, see GryMod.FlashBoot.Placement).
function Module.Placement(w, h)
	local scale = h / STAGE_H

	return (w - STAGE_W * scale) / 2, 0, scale
end

-- ---------------------------------------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------------------------------------

-- The suit's own lines each have a switch of the player (gry_msg_*), on by default.
local lineConVars = {}

for key, line in pairs(Messages.Lines) do
	lineConVars[key] = CreateClientConVar(line.convar, line.default or "1", true, false, line.help)
end

-- Whether the player wants this line of the suit (a key of GryMod.Messages.Lines).
function Module.LineOn(key)
	local convar = lineConVars[key]

	return not convar or convar:GetBool()
end

-- Whether the lines are on: the HUD is on (and the suit with it) and the player did not turn the text lines off.
function Module.Enabled()
	return GryMod.FlashHUD ~= nil and GryMod.FlashHUD.Enabled() and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("messages"))
end

-- ---------------------------------------------------------------------------------------------------------
-- The movie
-- ---------------------------------------------------------------------------------------------------------

local EMPTY = {frame = 1, speed = 1} -- a place with no line: shared, never changed

local instance -- {root, lanes = {[name] = lane}}
local failed = false
local hooked = false
local lastTime

-- A lane: its clip and its places (slots); `items` says what is in each place, oldest first.
local function buildLane(root, name)
	local holder = root:Child(ROOTS[name])

	if not holder or not holder.Child then
		return nil
	end

	local lane = {name = name, slots = {}, items = {}}

	for index, n in ipairs(SLOTS[name]) do
		local text = holder:Child("Message" .. n)
		local plate = holder:Child("Message" .. n .. "s")
		local ani = text and text.Child and text:Child("Ani")
		local field = ani and ani.Field and ani:Field("Message" .. n)

		if not field then
			return nil
		end

		local entry = ani:Child("Message" .. n)
		local centre = text.entry.m[5] + ani.entry.m[5] + entry.m[5] + field.w / 2

		lane.slots[index] = {
			n = n, text = text, plate = plate and plate.Child and plate or nil, baseW = field.w,
			-- the middle of the line, in the coordinates of the plate's clip
			plateX = centre - (plate and plate.entry and plate.entry.m[5] or 0)
		}
		lane.items[index] = EMPTY
	end

	return lane
end

local function plateMiddle(slot)
	local ani = slot.plate and slot.plate:Child("Ani")

	return ani and ani:Child("Middle")
end

-- A place goes empty: the text clip starts again from its first frame (that rebuilds it, so its text is gone), the plate hides.
local function clearSlot(slot)
	slot.text:GotoAndStop(1)

	if slot.plate then
		slot.plate:GotoAndStop(1)

		local middle = plateMiddle(slot)

		if middle then
			middle:SetVisible(false)
		end
	end
end

-- Writes a line in a place: the text, centred on the same point whatever its width, and the plate behind it.
local function writeSlot(slot, text, movie)
	local name = "Message" .. slot.n
	local ani = slot.text:Child("Ani")

	if not ani then
		return
	end

	ani:SetText(name, text)
	ani:FitTextWidth(name, text, Module.FIELD_MAX)

	local field = ani:Field(name)

	ani:SetX((slot.baseW - field.w) / 2)

	local middle = plateMiddle(slot)

	if middle then
		local font = movie.fonts and movie.fonts[field.f]
		local width = font and select(3, Flash.LayoutText(font, field, text)) or field.w

		middle:SetVisible(true)
		middle:SetScale(Module.PlateScale(width), 100)
		middle:SetX(slot.plateX)
	end
end

local function placeItem(slot, item, movie)
	if not item.text then
		clearSlot(slot)

		return
	end

	-- the frames first: going back in a clip makes it again from its first frame, and its text with it
	slot.text:GotoAndPlay(item.frame)

	if slot.plate then
		slot.plate:GotoAndPlay(item.frame)
	end

	writeSlot(slot, item.text, movie)
end

local function ensure()
	if instance then
		return instance
	end

	if failed then
		return nil
	end

	local movie = Flash.Load(Module.MOVIE)
	local root = movie and Flash.NewRoot(movie, GryMod.FlashHUD and GryMod.FlashHUD.Theme)

	if not root then
		failed = true

		return nil
	end

	instance = {movie = movie, root = root, lanes = {}}

	for _, name in ipairs(Messages.LANES) do
		local lane = buildLane(root, name)

		if not lane then
			Flash.ReleaseClip(root)
			instance, failed = nil, true

			return nil
		end

		instance.lanes[name] = lane

		-- nothing is on show: the plates start with their picture in the middle of the stage, hide them
		for _, slot in ipairs(lane.slots) do
			clearSlot(slot)
		end
	end

	return instance
end

-- Puts a line (what Messages.Resolve returns) on the lane it asks for. Returns true, or false and why not.
function Module.Show(info)
	if not Module.Enabled() then
		return false, "off"
	end

	local current = ensure()

	if not current then
		return false, "no movie"
	end

	local lane = current.lanes[info.lane]

	-- the lines on show keep their age: the frame of each is read from its clip before they move up
	for index, slot in ipairs(lane.slots) do
		local item = lane.items[index]

		if item.text then
			item.frame = slot.text:CurrentFrame()
		end
	end

	local entry = {text = info.text, frame = 2, speed = Messages.SpeedFor(info.duration)}

	if HOLD[lane.name] then
		entry.hold = (info.duration or Messages.LIFE) * HOLD_PART
	end

	lane.items = Messages.Shift(lane.items, entry)

	for index, slot in ipairs(lane.slots) do
		placeItem(slot, lane.items[index], current.movie)
	end

	return true
end

-- One step of time for every line on show, at its own speed (a line with a `duration` plays the movie faster or slower). A line whose
-- clip has gone back to its first frame is over and its place is cleared. Returns whether a line is still on show.
function Module.Step(dt)
	if not instance then
		return false
	end

	local any = false

	for _, lane in pairs(instance.lanes) do
		for index, slot in ipairs(lane.slots) do
			local item = lane.items[index]

			if item.text then
				local step = dt * item.speed

				-- a line that is held (see HOLD) fades out when its time is up
				if item.hold then
					item.hold = item.hold - dt

					if item.hold <= 0 then
						item.hold = nil
						slot.text:GotoAndPlay("fadeout")

						if slot.plate then
							slot.plate:GotoAndPlay("fadeout")
						end
					end
				end

				slot.text:Advance(step)

				if slot.plate then
					slot.plate:Advance(step)
				end

				if slot.text:CurrentFrame() == 1 then
					lane.items[index] = EMPTY
					clearSlot(slot)
				else
					any = true
				end
			end
		end
	end

	return any
end

-- The text of what is on show, for a lane, newest last (tests and tools).
function Module.Texts(laneName)
	local lane = instance and instance.lanes[laneName]
	local texts = {}

	if lane then
		for _, item in ipairs(lane.items) do
			if item.text then
				texts[#texts + 1] = item.text
			end
		end
	end

	return texts
end

function Module.Active()
	return hooked
end

-- The places of a lane and what is in them ({text, frame, speed} each, oldest first), or nil before anything was shown (tests and tools).
function Module.Lane(laneName)
	local lane = instance and instance.lanes[laneName]

	return lane and lane.slots, lane and lane.items
end

-- ---------------------------------------------------------------------------------------------------------
-- Drawing (a paint hook that exists only while a line is on show)
-- ---------------------------------------------------------------------------------------------------------

local HOOK = "GRYFLASHMESSAGES"

local function stopPaint()
	hook.Remove("HUDPaint", HOOK)
	hooked = false
	lastTime = nil
end

function Module.Paint()
	if not instance then
		stopPaint()

		return
	end

	local now = RealTime()
	local dt = math.min(now - (lastTime or now), 0.1)
	lastTime = now

	if not Module.Step(dt) then
		stopPaint()

		return
	end

	if Module.Enabled() then
		local x, y, scale = Module.Placement(ScrW(), ScrH())

		Flash.Draw(instance.root, x, y, scale)
	end
end

local function startPaint()
	if not hooked then
		lastTime = nil
		hook.Add("HUDPaint", HOOK, Module.Paint)
		hooked = true
	end
end

-- Takes everything off the screen (a new life, a new theme): the lines are forgotten, the clips go back to the pool.
function Module.Reset()
	stopPaint()

	if instance then
		Flash.ReleaseClip(instance.root)
	end

	instance, failed = nil, false
end

-- ---------------------------------------------------------------------------------------------------------
-- The HUD event "message"
-- ---------------------------------------------------------------------------------------------------------

-- The event: data = {text, lane, sound, duration} or {line = key} (the suit's own lines, see sh_messages.lua). The picture and the sound
-- are played together, and the hook GryMod_MessageShown(text, opts) says that a line was shown (a line that is not shown, because the
-- text lines are off or the movie is missing, plays no sound and is not reported).
function Module.Handle(data)
	local info = Messages.Resolve(data, Module.LineOn)

	if not info or not Module.Show(info) then
		return false
	end

	startPaint()

	if info.sound and GryMod.PlaySound then
		GryMod.PlaySound(info.sound)
	end

	-- a listener that fails must not switch the event off (five errors in a row do): the report is run apart, its error printed once
	local ok, err = pcall(hook.Run, "GryMod_MessageShown", info.text, {lane = info.lane, sound = info.sound, duration = info.duration, line = info.line})

	if not ok then
		ErrorNoHalt("[GryMod] A listener of GryMod_MessageShown failed: " .. tostring(err) .. "\n")
	end

	return true
end

if API and API.RegisterHUDEvent then
	API.RegisterHUDEvent("message", Module.Handle, {
		label = "Text line",
		variants = {
			{label = "Line, top lane", data = {text = "OBJECTIVE ACTIVATED", lane = "top"}},
			{label = "Line, under the centre", data = {text = "Temperature Camo: Disabled!", lane = "status"}},
			{label = "Line, long", data = {text = "This is a longer line, to see the plate behind it follow its width", lane = "status", duration = 8}},
			{label = "Suit line: camouflage out of energy", data = {line = "cloak_disabled"}},
			{label = "Suit line: health too low", data = {line = "cloak_health"}},
			{label = "Suit line: killed a friendly", data = {line = "killed_friend"}}
		},
		follows = {{"gry_hud_messages", "the text lines"}, {"gry_hud", "the HUD"}, {"gry_sounds", "the sound of a line"}}
	})
end

-- Shows a text line on the HUD of this client: text (128 characters at most) and opts = nil or {lane = "top" (default) | "middle" |
-- "status" | "crosshair" (or 1 to 4), sound = a sound path played with the line, duration = seconds it stays (0.5 to 60, 5 by default)}.
-- It is the event "message" called with checked data. Returns true when the event ran, false and why otherwise (a line that is turned
-- off by the player still returns true: the event ran, it drew nothing).
function API.ShowMessage(text, opts)
	local data, reason = Messages.Build(text, opts)

	if not data then
		return false, reason
	end

	return API.HUDEvent("message", data)
end

-- ---------------------------------------------------------------------------------------------------------
-- The suit's own lines that the client knows by itself
-- ---------------------------------------------------------------------------------------------------------

-- Whether a change of mode is the camouflage giving out for lack of energy (the server drops it to armor, cause ENERGY: sv_system.lua).
function Module.CloakDropped(mode, oldMode, reason)
	return oldMode == GryMod.Modes.CLOAK and mode == GryMod.Modes.ARMOR and reason == GryMod.ModeReasons.ENERGY
end

hook.Add("GryMod_ModeChanged", "GryMessagesCloak", function(ply, mode, oldMode, reason)
	if ply == LocalPlayer() and Module.CloakDropped(mode, oldMode, reason) and API and API.HUDEvent then
		API.HUDEvent("message", {line = "cloak_disabled"})
	end
end)
