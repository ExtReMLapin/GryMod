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

-- Makes a movie available under a name (tests, or data built at runtime).
function Flash.Register(name, data)
	movies[name] = data
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
		entry.text = definition.t or ""
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

-- Where the text starts inside its field: returns x (from the field's left), the baseline (from its top)
-- and the text width, all in stage pixels. Characters the font does not have count for nothing.
function Flash.LayoutText(font, field, text)
	local scale = field.fh / font.em
	local glyphs = font.g
	local width = 0

	for i = 1, #text do
		local glyph = glyphs[string.byte(text, i)]

		if glyph then
			width = width + glyph.adv * scale
		end
	end

	local x

	if field.al == 2 then
		x = (field.w - width) / 2
	elseif field.al == 1 then
		x = field.w - TEXT_MARGIN - width
	else
		x = TEXT_MARGIN
	end

	return x, TEXT_MARGIN + font.asc * scale, width
end

