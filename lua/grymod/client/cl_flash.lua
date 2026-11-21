-- Flash timeline player: replays the movie clips of the Crysis HUD movies converted by tools/flash2lua
-- (see that tool's emit_lua.lua for the data format).
--
-- A Clip is one running movie clip: a timeline (frames with display-list operations, labels and the few
-- frame actions the HUD uses), a clock at the movie's frame rate (a float position, so it can advance by any
-- time step), and a display list (depth -> entry). Drawing is in cl_flash_draw.lua.

GryMod = GryMod or {}

-- kept across a reload of this file, so the drawing functions that cl_flash_draw.lua added stay
local Flash = GryMod.Flash or {}
GryMod.Flash = Flash

local Clip = {}
Clip.__index = Clip

local IDENTITY = {1, 0, 0, 1, 0, 0}
local EPSILON = 1e-6
local MAX_JUMPS = 8 -- frame actions jumping to each other

local movies = {}

-- The movies hold localisation keys ("@ui_ZOOM") where the engine of the original game writes its English texts.
-- The texts are in grymod/flash/hud_boot_strings.lua (lower case keys); a key without a text shows its name.
local STRINGS = include("grymod/flash/hud_boot_strings.lua") or {}

function Flash.Localise(text)
	if not isstring(text) or string.sub(text, 1, 1) ~= "@" then
		return text
	end

	local key = string.lower(string.sub(text, 2))

	return STRINGS[key] or (string.gsub(string.gsub(string.sub(text, 2), "^ui_", ""), "_", " "))
end

-- Makes a movie available under a name (tests, or data built at runtime).
function Flash.Register(name, data)
	movies[name] = data
end

-- Whether the movie is in memory already (loading it again costs nothing).
function Flash.Loaded(name)
	return movies[name] ~= nil
end

-- Forgets a movie loaded from its file (the next Load reads it again): tests.
function Flash.Unload(name)
	movies[name] = nil
end

-- The converted movie `grymod/flash/<name>.lua`, or nil when it does not exist.
function Flash.Load(name)
	if movies[name] then
		return movies[name]
	end

	local path = "grymod/flash/" .. name .. ".lua"

	if not file.Exists(path, "LUA") then
		return nil
	end

	local ok, data = pcall(include, path)

	if ok and istable(data) then
		movies[name] = data

		return data
	end

	return nil
end

local function clampFrame(frame, count)
	if not (frame >= 1) then -- also catches NaN
		return 1
	end

	frame = math.floor(frame)

	if frame > count then
		return count
	end

	return frame
end

local function newClip(movie, definition, id, theme)
	local clip = setmetatable({
		movie = movie,
		id = id,
		n = definition.n,
		labels = definition.labels or {},
		frames = definition.frames,
		frame = 0,
		frac = 0,
		pos = 1,
		playing = true,
		visible = true,
		list = {},
		names = {},
		count = 0,
		sorted = nil,
		jumps = 0,
		theme = theme,
		version = 0
	}, Clip)

	clip:_goto(1)
	clip:_runActions()

	return clip
end

-- A clip made from sprite `id` of the movie, or nil when the id is not a sprite. `theme` = {Line = {r, g, b},
-- Over = ..., Text = ...}: the colours the colour-set scripts of the HUD movies copy onto their children.
function Flash.NewClip(movie, id, theme)
	local definition = movie.chars[id]

	if not definition or definition.k ~= "sprite" then
		return nil
	end

	return newClip(movie, definition, id, theme)
end

-- The movie's main timeline as a clip (theme: see NewClip).
function Flash.NewRoot(movie, theme)
	local labels = {}

	for index, frame in ipairs(movie.root) do
		if frame.l and not labels[frame.l] then
			labels[frame.l] = index
		end
	end

	return newClip(movie, {n = #movie.root, labels = labels, frames = movie.root}, 0, theme)
end

function Clip:_remove(depth)
	local entry = self.list[depth]

	if not entry then
		return
	end

	self.list[depth] = nil
	self.count = self.count - 1
	self.sorted = nil

	if Flash.ReleaseEntry then
		Flash.ReleaseEntry(entry)
	end

	if entry.name and self.names[entry.name] == entry then
		self.names[entry.name] = nil
	end
end

function Clip:_add(depth, id, op, inherit)
	local definition = self.movie.chars[id]

	if not definition then
		return
	end

	local entry = {
		depth = depth,
		id = id,
		kind = definition.k,
		m = op.m or (inherit and inherit.m) or IDENTITY,
		cx = op.cx or (inherit and inherit.cx),
		name = op.n or (inherit and inherit.name),
		blend = op.bl or (inherit and inherit.blend),
		clipDepth = op.cd or (inherit and inherit.clipDepth),
		ratio = op.r or (inherit and inherit.ratio)
	}

	if definition.k == "sprite" then
		entry.clip = newClip(self.movie, definition, id, self.theme)
		entry.clip.parent = self
		entry.clip.entry = entry
	elseif definition.k == "text" then
		entry.text = Flash.Localise(definition.t or "")
	end

	self.list[depth] = entry
	self.count = self.count + 1
	self.sorted = nil

	if entry.name then
		self.names[entry.name] = entry
	end
end

function Clip:_place(op)
	local depth = op.d
	local entry = self.list[depth]

	if op.c and not (op.mv and entry and entry.id == op.c) then
		if entry then
			self:_remove(depth)
		end

		self:_add(depth, op.c, op, entry)

		return
	end

	if not entry then
		return
	end

	-- a move: the character stays, the given properties change
	if op.m then entry.m = op.m end
	if op.cx then entry.cx = op.cx end
	if op.r then entry.ratio = op.r end
	if op.bl then entry.blend = op.bl end
end

function Clip:_applyOps(index)
	local frame = self.frames[index]

	if not frame then
		return
	end

	for i = 1, #frame do
		local op = frame[i]

		if op.rm then
			self:_remove(op.rm)
		else
			self:_place(op)
		end
	end
end

function Clip:_clear()
	if Flash.ReleaseEntry then
		for _, entry in pairs(self.list) do
			Flash.ReleaseEntry(entry)
		end
	end

	self.list = {}
	self.names = {}
	self.count = 0
	self.sorted = nil
end

-- Makes the display list that of `target` (already clamped). Going forward replays the frames in between
-- (children keep their state); going back rebuilds from the first frame, as Flash does.
function Clip:_goto(target)
	if target == self.frame then
		return
	end

	if target < self.frame then
		self:_clear()

		for index = 1, target do
			self:_applyOps(index)
		end
	else
		for index = self.frame + 1, target do
			self:_applyOps(index)
		end
	end

	self.frame = target
	self.pos = target + self.frac
	self:_touch()
end

-- Says that what this clip draws changed: its version, and its parents' (a cached image of a parent is stale too).
function Clip:_touch()
	local clip = self

	while clip do
		clip.version = clip.version + 1
		clip = clip.parent
	end
end

-- Flash's _x: moves this clip horizontally (replaces the x of its placement matrix).
function Clip:SetX(x)
	local entry = self.entry

	if not entry or entry.m[5] == x then
		return
	end

	local m = entry.m
	entry.m = {m[1], m[2], m[3], m[4], x, m[6]}

	if self.parent then
		self.parent:_touch()
	end
end

-- Flash's _y: moves this clip vertically.
function Clip:SetY(y)
	local entry = self.entry

	if not entry or entry.m[6] == y then
		return
	end

	local m = entry.m
	entry.m = {m[1], m[2], m[3], m[4], m[5], y}

	if self.parent then
		self.parent:_touch()
	end
end

-- Flash's _xscale and _yscale (percent): the size of this clip, its rotation and position stay.
function Clip:SetScale(percentX, percentY)
	local entry = self.entry

	if not entry or percentX ~= percentX or percentY ~= percentY then
		return
	end

	local m = entry.m
	local angle = math.atan2(m[2], m[1])
	local sx, sy = percentX / 100, percentY / 100
	local sin, cos = math.sin(angle), math.cos(angle)
	local a, b, c, d = sx * cos, sx * sin, -sy * sin, sy * cos

	if math.abs(m[1] - a) < 1e-9 and math.abs(m[2] - b) < 1e-9 and math.abs(m[3] - c) < 1e-9 and math.abs(m[4] - d) < 1e-9 then
		return
	end

	entry.m = {a, b, c, d, m[5], m[6]}

	if self.parent then
		self.parent:_touch()
	end
end

-- Flash's _rotation: turns this clip by an angle in degrees (clockwise on screen), keeping its scale and its
-- position (the rotation part of its placement matrix is replaced).
function Clip:SetRotation(degrees)
	local entry = self.entry

	if not entry or not (degrees == degrees) then
		return
	end

	local m = entry.m
	local sx, sy = math.sqrt(m[1] * m[1] + m[2] * m[2]), math.sqrt(m[3] * m[3] + m[4] * m[4])
	local radians = math.rad(degrees)
	local sin, cos = math.sin(radians), math.cos(radians)
	local a, b, c, d = sx * cos, sx * sin, -sy * sin, sy * cos

	if math.abs(m[1] - a) < 1e-9 and math.abs(m[2] - b) < 1e-9 and math.abs(m[3] - c) < 1e-9 and math.abs(m[4] - d) < 1e-9 then
		return
	end

	entry.m = {a, b, c, d, m[5], m[6]}

	if self.parent then
		self.parent:_touch()
	end
end

-- Flash's _alpha: a percentage that replaces the alpha multiplier of this clip's colour transform (the colour
-- terms stay).
function Clip:SetAlpha(percent)
	local entry = self.entry

	if not entry or type(percent) ~= "number" or percent ~= percent then
		return
	end

	local alpha = math.Clamp(percent, 0, 100) / 100
	local cx = entry.cx or {1, 1, 1, 1, 0, 0, 0, 0}

	if math.abs(cx[4] - alpha) < 1e-9 then
		return
	end

	entry.cx = {cx[1], cx[2], cx[3], alpha, cx[5], cx[6], cx[7], cx[8]}

	if self.parent then
		self.parent:_touch()
	end
end

function Clip:SetVisible(visible)
	if self.visible ~= visible then
		self.visible = visible
		self:_touch()
	end
end

function Clip:_jump(frame)
	if self.jumps >= MAX_JUMPS then
		return
	end

	self.jumps = self.jumps + 1
	self.frac = 0
	self:_goto(clampFrame(frame, self.n))
	self.pos = self.frame
	self:_runActions()
	self.jumps = self.jumps - 1
end

-- Flash's Color.setRGB on a child: replaces its colour by the theme colour (multiplier 0, colour added), the
-- alpha terms stay as they are.
function Clip:_colorChild(themeName, childName)
	local rgb = self.theme and self.theme[themeName]
	local entry = rgb and self.names[childName]

	if not entry then
		return
	end

	local old = entry.cx

	entry.cx = {0, 0, 0, old and old[4] or 1, rgb[1], rgb[2], rgb[3], old and old[8] or 0}
	self:_touch()
end

function Clip:_runActions()
	local frame = self.frames[self.frame]
	local actions = frame and frame.a

	if not actions then
		return
	end

	for i = 1, #actions do
		local action = actions[i]
		local what = action[1]

		if what == "stop" then
			self.playing = false
		elseif what == "play" then
			self.playing = true
		elseif what == "goto" then
			self:_jump(action[2])
		elseif what == "color" then
			self:_colorChild(action[2], action[3])
		elseif what == "child" then
			local child = self.names[action[2]]
			child = child and child.clip

			if child then
				if action[3] then
					child:GotoAndPlay(action[4])
				else
					child:GotoAndStop(action[4])
				end
			end
		elseif what == "gotol" then
			local target = self.labels[action[2]]

			if target then
				self:_jump(target)
			end
		end
	end
end

local function resolve(self, where)
	if isstring(where) then
		return self.labels[where]
	end

	if isnumber(where) then
		return where
	end

	return nil
end

function Clip:GotoAndStop(where)
	local frame = resolve(self, where)

	if frame == nil then
		return
	end

	self.playing = false
	self:_jump(frame)
end

function Clip:GotoAndPlay(where)
	local frame = resolve(self, where)

	if frame == nil then
		return
	end

	self.playing = true
	self:_jump(frame)
end

function Clip:Stop()
	self.playing = false
end

function Clip:Play()
	self.playing = true
end

-- Moves the clock of this clip and of all its children by `dt` seconds.
function Clip:Advance(dt)
	-- a time step that is NaN, negative or huge (a long freeze) must not poison the clock or spin for long
	if not (dt > 0) then
		dt = 0
	elseif dt > 1 then
		dt = 1
	end

	if self.playing and self.n > 1 then
		self.frac = self.frac + dt * self.movie.fps

		while self.frac >= 1 - EPSILON do
			self.frac = math.max(self.frac - 1, 0)

			local nextFrame = self.frame + 1

			if nextFrame > self.n then
				nextFrame = 1
			end

			self:_goto(nextFrame)
			self:_runActions()

			if not self.playing then
				self.frac = 0

				break
			end
		end

		self.pos = self.frame + self.frac
	end

	for _, entry in ipairs(self:Entries()) do
		if entry.clip then
			entry.clip:Advance(dt)
		end
	end
end

-- Display list entries in drawing order (lowest depth first).
function Clip:Entries()
	local sorted = self.sorted

	if not sorted then
		sorted = {}

		for _, entry in pairs(self.list) do
			sorted[#sorted + 1] = entry
		end

		table.sort(sorted, function(a, b) return a.depth < b.depth end)
		self.sorted = sorted
	end

	return sorted
end

-- The child clip with this instance name (or its non-clip entry), searched at this level only.
function Clip:Child(name)
	local entry = self.names[name]

	if not entry then
		return nil
	end

	return entry.clip or entry
end

function Clip:ChildCount()
	return self.count
end

function Clip:EntryAt(depth)
	return self.list[depth]
end

function Clip:CurrentFrame()
	return self.frame
end

function Clip:CurrentLabel()
	local frame = self.frames[self.frame]

	return frame and frame.l
end

-- Sets the text of the text field with this instance name (at this level). Returns whether it was found.
function Clip:SetText(name, text)
	local entry = self.names[name]

	if not entry or entry.kind ~= "text" then
		return false
	end

	text = text == nil and "" or tostring(text)

	if entry.text ~= text then
		entry.text = text
		self:_touch()
	end

	return true
end

-- Replaces the text of every text field in this clip and in the clips inside it by fn(text) (the fields the
-- engine fills with localised strings carry a "@ui_..." key as their initial text).
function Clip:MapText(fn)
	local changed = false

	for _, entry in pairs(self.list) do
		if entry.kind == "text" then
			local text = fn(entry.text)

			if text ~= entry.text then
				entry.text = text
				changed = true
			end
		elseif entry.clip then
			entry.clip:MapText(fn)
		end
	end

	if changed then
		self:_touch()
	end
end

-- The child clip (or field) at a dotted path of instance names, e.g. "Root.Texts.HealthEnergy", or nil.
function Clip:Find(path)
	local current = self

	for name in string.gmatch(path, "[^.]+") do
		if not current or not current.Child then
			return nil
		end

		current = current:Child(name)

		if current == nil then
			return nil
		end
	end

	return current
end

local TEXT_MARGIN = 2 -- Flash keeps 2 pixels between a text field's border and its text

-- Where a line of this width starts, from the field's left (the alignment of the field).
local function lineX(field, width)
	if field.al == 2 then
		return (field.w - width) / 2
	elseif field.al == 1 then
		return field.w - TEXT_MARGIN - width
	end

	return TEXT_MARGIN
end

local function lineAt(font, field, scale, text, width, index)
	local x = lineX(field, width)
	local lineHeight = (font.asc + font.desc) * scale + (field.ld or 0)

	return {text = text, x = x, baseline = TEXT_MARGIN + font.asc * scale + (index - 1) * lineHeight, width = width}
end

-- The width of text[first .. last] in stage pixels (characters the font does not have count for nothing).
local function spanWidth(glyphs, scale, text, first, last)
	local width = 0

	for i = first, last do
		local glyph = glyphs[string.byte(text, i)]

		if glyph then
			width = width + glyph.adv * scale
		end
	end

	return width
end

-- A paragraph (no line break inside) of a field with word wrap, broken into lines that fit `available` pixels: at
-- the spaces (a break drops the spaces it replaces), and between two characters for a word that is wider than the
-- field. Calls add(first, last) for the characters of each line.
local function wrapParagraph(glyphs, scale, text, available, add)
	local count = #text
	local lineFirst, lineLast, lineWidth = 1, 0, 0
	local position = 1

	while position <= count do
		local spaces = string.find(text, "[^ ]", position) or count + 1
		local wordEnd = (string.find(text, " ", spaces, true) or count + 1) - 1

		if spaces > count then
			break
		end

		local gap = spanWidth(glyphs, scale, text, position, spaces - 1)
		local word = spanWidth(glyphs, scale, text, spaces, wordEnd)

		if lineLast >= lineFirst and lineWidth + gap + word > available + 1e-6 then
			add(lineFirst, lineLast)
			lineFirst, lineLast, lineWidth, gap = spaces, spaces - 1, 0, 0
		elseif lineLast < lineFirst then
			-- the first word of a line: the spaces before it are kept on the first line of the paragraph only
			if lineFirst == 1 then
				lineFirst, lineLast = 1, spaces - 1
				lineWidth = gap
			else
				lineFirst, lineLast, lineWidth, gap = spaces, spaces - 1, 0, 0
			end
		end

		if lineWidth + gap + word <= available + 1e-6 then
			lineLast, lineWidth = wordEnd, lineWidth + gap + word
		else
			-- wider than a whole line: cut between two characters
			for i = spaces, wordEnd do
				local glyph = glyphs[string.byte(text, i)]
				local advance = glyph and glyph.adv * scale or 0

				if lineLast >= lineFirst and lineWidth + advance > available + 1e-6 then
					add(lineFirst, lineLast)
					lineFirst, lineLast, lineWidth = i, i - 1, 0
				end

				if lineLast < lineFirst then
					lineFirst = i
				end

				lineLast, lineWidth = i, lineWidth + advance
			end
		end

		position = wordEnd + 1
	end

	if lineLast >= lineFirst then
		add(lineFirst, lineLast)
	end
end

-- The lines of a text in its field: returns a list of {text, x, baseline, width} (x from the field's left,
-- baseline from its top, width of the line, all in stage pixels) and whether the field clips its text to its
-- rectangle. A multiline field (field.ml) breaks its lines at the line breaks of the text, and at spaces so that
-- they fit the width minus the 2 pixel margins when it has word wrap (field.ww); the lines are one line height
-- apart: ascent + descent of the font plus the leading of the field (field.ld). A field that is not multiline is
-- one line, whatever its text. Every line is aligned on its own. Text fields of the original clip what does not fit
-- their rectangle, except the ones that resize themselves (field.as). Characters the font does not have count for
-- nothing.
function Flash.LayoutLines(font, field, text)
	local scale = field.fh / font.em
	local glyphs = font.g
	local lines = {}
	local clips = not field.as

	local function add(paragraph, first, last)
		local part = string.sub(paragraph, first, last)

		lines[#lines + 1] = lineAt(font, field, scale, part, spanWidth(glyphs, scale, part, 1, #part), #lines + 1)
	end

	if not field.ml then
		text = string.gsub(text, "[\r\n]", "")
		add(text, 1, #text)

		return lines, clips
	end

	local available = field.w - 2 * TEXT_MARGIN
	local start = 1

	while true do
		local stop = string.find(text, "\n", start, true)
		local paragraph = string.gsub(string.sub(text, start, (stop or #text + 1) - 1), "\r", "")

		if not field.ww or spanWidth(glyphs, scale, paragraph, 1, #paragraph) <= available + 1e-6 then
			add(paragraph, 1, #paragraph)
		else
			wrapParagraph(glyphs, scale, paragraph, available, function(first, last)
				add(paragraph, first, last)
			end)
		end

		if not stop then
			break
		end

		start = stop + 1
	end

	return lines, clips
end

-- Where the text starts inside its field: returns x (from the field's left), the baseline (from its top)
-- and the text width, all in stage pixels, of its first line (see LayoutLines for the others).
function Flash.LayoutText(font, field, text)
	if field.ml then
		local line = Flash.LayoutLines(font, field, text)[1]

		return line.x, line.baseline, line.width
	end

	-- one line (what the drawing does for most fields, every frame): no table made
	local scale = field.fh / font.em
	local width = spanWidth(font.g, scale, text, 1, #text)

	return lineX(field, width), TEXT_MARGIN + font.asc * scale, width
end

