-- The text lines of the HUD (the movie HUD_Messages, drawn by cl_hud_messages_flash.lua): what is shared by both realms, and pure.
-- A line is shown by the HUD event "message" (docs/events.md); the server asks a client for one with GryMod.API.ShowMessage(ply, text,
-- opts) (sv_messages.lua), a client shows its own with GryMod.API.ShowMessage(text, opts) (cl_hud_messages_flash.lua). Both build the
-- same event data here, so that the limits of the HUD events (128 characters a string) are checked in ONE place, before anything is sent.

GryMod = GryMod or {}

local Messages = GryMod.Messages or {}
GryMod.Messages = Messages

-- The longest text: the limit of a string in the data of a HUD event.
Messages.MAX_TEXT = 128

-- How long a line stays when the caller does not say (the movie's own life of a line: 150 frames at 30 a second) and the bounds of
-- `duration` (the whole life of the line, its fade out included).
Messages.LIFE = 5
Messages.MIN_DURATION = 0.5
Messages.MAX_DURATION = 60

-- The four lanes of the movie, with the number the original gives each in its call setMessageText(text, align, colour): 1 the top
-- line (the banner of the objectives), 2 the upper middle, 3 just under the centre (the suit's own lines), 4 above the crosshair.
Messages.LANES = {"top", "middle", "status", "crosshair"}

local LANE_SET = {}

for _, name in ipairs(Messages.LANES) do
	LANE_SET[name] = true
end

-- The name of the lane for what a caller wrote: nothing is the top lane, a name of the list, or the number 1 to 4 of the original.
-- nil for anything else.
function Messages.LaneName(value)
	if value == nil then
		return "top"
	end

	if isstring(value) then
		return LANE_SET[value] and value or nil
	end

	if isnumber(value) and value == math.floor(value) then
		return Messages.LANES[value]
	end

	return nil
end

-- The suit's own lines, by key (the data `line` of the event): the texts of the original game's StatusMessages.xml and
-- game_text_messages.xml (English). Each has the client setting that turns it off, so that nobody has to read a line he does not
-- want. `lane` is where it is shown: the suit's lines go under the centre as in the original; the lane of "killed a friendly" was
-- not read in the original, the upper middle is a choice made here.
Messages.Lines = {
	cloak_disabled = {text = "Temperature Camo: Disabled!", lane = "status", convar = "gry_msg_cloak_disabled", label = "Message: camouflage out of energy",
		help = "The camouflage ran out of energy and the suit went back to armor"},
	cloak_health = {text = "Temperature Camo: Health too low!", lane = "status", convar = "gry_msg_cloak_health", label = "Message: camouflage, health too low",
		help = "The camouflage was refused because the health is too low (the server's gry_cloak_min_health)"},
	killed_friend = {text = "YOU KILLED A FRIENDLY!", lane = "middle", convar = "gry_msg_killed_friend", label = "Message: killed a friendly",
		help = "You killed an ally (a player of your team, or an NPC that likes you)"}
}

-- The keys of the lines, sorted (for tools and tests).
function Messages.LineKeys()
	local keys = {}

	for key in pairs(Messages.Lines) do
		keys[#keys + 1] = key
	end

	table.sort(keys)

	return keys
end

-- A text for the movie: one line (a run of spaces, tabs and line breaks is one space), no control characters, no space at the ends. nil when
-- nothing is left.
function Messages.Clean(text)
	if not isstring(text) then
		return nil
	end

	text = string.gsub(text, "[%c%s]+", " ")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")

	if text == "" then
		return nil
	end

	return text
end

-- The data of the event "message" for a text and its options, or false and why not. `opts` is nil or a table: `sound` (a sound path,
-- played with the line), `duration` (seconds the line stays, 0.5 to 60), `lane` ("top", "middle", "status", "crosshair" or 1 to 4).
-- A text that is too long is refused, not cut: the caller wrote it and should know.
function Messages.Build(text, opts)
	local clean = Messages.Clean(text)

	if not clean then
		return false, "no text"
	end

	if #clean > Messages.MAX_TEXT then
		return false, "text too long (" .. Messages.MAX_TEXT .. " characters at most)"
	end

	if opts ~= nil and not istable(opts) then
		return false, "the options must be a table"
	end

	opts = opts or {}

	local data = {text = clean}

	if opts.lane ~= nil then
		data.lane = Messages.LaneName(opts.lane)

		if not data.lane then
			return false, "invalid lane"
		end
	end

	if opts.sound ~= nil then
		if not isstring(opts.sound) or #opts.sound < 1 or #opts.sound > Messages.MAX_TEXT then
			return false, "invalid sound"
		end

		data.sound = opts.sound
	end

	if opts.duration ~= nil then
		local seconds = opts.duration

		if not isnumber(seconds) or seconds ~= seconds or seconds == math.huge or seconds == -math.huge then
			return false, "invalid duration"
		end

		data.duration = math.Clamp(seconds, Messages.MIN_DURATION, Messages.MAX_DURATION)
	end

	return data
end

-- What a received event says, in the shape the HUD shows: {text, lane, sound, duration, line}, or nil and why not. The data is what
-- Build makes, or {line = key} for one of the suit's own lines (`lineOn(key)` says whether the player wants it: true when left out).
-- Never trusts the data: a text is cleaned and bounded again, a lane or a sound that is not valid is dropped, not an error.
function Messages.Resolve(data, lineOn)
	if not istable(data) then
		return nil, "no data"
	end

	local text, lane, line
	local key = data.line

	if key ~= nil then
		line = isstring(key) and Messages.Lines[key]

		if not line then
			return nil, "unknown line"
		end

		if lineOn and not lineOn(key) then
			return nil, "line off"
		end

		text, lane = line.text, line.lane
	else
		text = Messages.Clean(data.text)

		if not text then
			return nil, "no text"
		end

		if #text > Messages.MAX_TEXT then
			text = string.sub(text, 1, Messages.MAX_TEXT)
		end
	end

	-- the lane of the data wins when it is valid; LaneName(nil) is the top lane, so a missing lane is not asked
	lane = (data.lane ~= nil and Messages.LaneName(data.lane)) or lane or "top"

	local sound = isstring(data.sound) and #data.sound >= 1 and #data.sound <= Messages.MAX_TEXT and data.sound or nil
	local duration

	if isnumber(data.duration) and data.duration == data.duration and data.duration ~= math.huge and data.duration ~= -math.huge then
		duration = math.Clamp(data.duration, Messages.MIN_DURATION, Messages.MAX_DURATION)
	end

	return {text = text, lane = lane, sound = sound, duration = duration, line = key}
end

-- The speed the movie plays a line at so that its life lasts `duration` seconds (nil: the movie's own five seconds).
function Messages.SpeedFor(duration)
	if not isnumber(duration) or not (duration > 0) then
		return 1
	end

	return Messages.LIFE / math.Clamp(duration, Messages.MIN_DURATION, Messages.MAX_DURATION)
end

-- The slots of a lane when a new line comes in: `items` is the list of the lines on show, the oldest first, as {text, frame, speed}
-- (an empty slot has no text). The new line takes the last place and every line moves one place up the list, the oldest one leaves; it
-- is what the movie does with the texts and the frames of its lines. Returns a new list of the same length (the items are shared).
function Messages.Shift(items, entry)
	local count = #items
	local result = {}

	for i = 1, count - 1 do
		result[i] = items[i + 1]
	end

	result[count] = entry

	return result
end

if GryMod.API and GryMod.API.AddFeature then
	GryMod.API.AddFeature("messages")
end
