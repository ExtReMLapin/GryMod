-- Flash timeline player: replays the movie clips of the Crysis HUD movies converted by dev_resources/flash2lua
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

-- The yaw of the player's view in the world (degrees). In a vehicle the eye angles are relative to it (measured in a Buggy, view at 1.2 in the world: EyeAngles 86.9,
-- vehicle at -85.7), so the radar, its map, the compass and the damage arcs turned with the vehicle: there they are turned by the vehicle's own angles.
function Flash.ViewYaw(ply)
	local eyes = ply:EyeAngles()

	if ply:InVehicle() then
		local vehicle = ply:GetVehicle()

		if IsValid(vehicle) then
			return vehicle:LocalToWorldAngles(eyes).y
		end
	end

	return eyes.y
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

-- ---------------------------------------------------------------------------------------------------------
-- Going back to an earlier frame without making everything again.
--
-- Going back rebuilds the display list from the first frame, as Flash does: every object is made again, with every clip inside it (about 10 KB for one step
-- of the energy bar, a bar that is emptied makes that at each step, more for the sprites that place something at each frame). Most of the time the objects
-- are the same at both frames and only their matrix, colour, morph ratio and blend mode differ: this path keeps them and puts those four back to what the
-- first frame's replay would give. It is only taken when its result cannot be told from the rebuild's, otherwise `_rebuild` runs (the fallback):
--   * no frame after the target, up to the current one, places or removes anything (the objects are then the same ones),
--   * the display list is what the movie made (nothing added by other files, no text, only the fields this file and the drawing write),
--   * every clip inside is still exactly as a new one of its sprite (it never moved, no change was made inside it): then keeping it is making it again.
-- Flash.NoFastRewind = true forces the rebuild (tests). Flash.RewindStats counts both paths.
-- ---------------------------------------------------------------------------------------------------------

Flash.RewindStats = Flash.RewindStats or {fast = 0, slow = 0}

-- the fields of a display list entry and of a clip that are made by this file (the drawing adds `cache` and `cacheB`: images derived from the state)
local ENTRY_FIELDS = {depth = true, id = true, kind = true, m = true, cx = true, name = true, blend = true, clipDepth = true, ratio = true, clip = true, text = true, cache = true, cacheB = true}
local CLIP_FIELDS = {movie = true, id = true, n = true, labels = true, frames = true, frame = true, frac = true, pos = true, playing = true, visible = true, list = true, names = true, count = true, sorted = true, jumps = true, theme = true, version = true, parent = true, entry = true}

-- what the replay of the frames from the first to the target gives for each depth: the id and the four properties a move changes (reused tables). A depth
-- with nothing, or a property that is nil, holds false and never nil: a table that gets keys removed and added again at each call grows and shrinks (the collector
-- forgets the removed keys), which allocates.
local shadowId, shadowM, shadowCx, shadowBlend, shadowRatio = {}, {}, {}, {}, {}

local function shadowDrop(depth)
	shadowId[depth], shadowM[depth], shadowCx[depth], shadowBlend[depth], shadowRatio[depth] = false, false, false, false, false
end

-- Replays frames 1..target on the shadow with the rules of _place and _remove. Returns how many objects are there.
local function shadowReplay(frames, chars, target)
	for depth in next, shadowId do
		shadowDrop(depth)
	end

	local shown = 0

	for index = 1, target do
		local frame = frames[index]

		if frame then
			for i = 1, #frame do
				local op = frame[i]
				local depth = op.rm

				if depth then
					if shadowId[depth] then
						shadowDrop(depth)
						shown = shown - 1
					end
				else
					depth = op.d
					local id = op.c
					local current = shadowId[depth]

					if id and not (op.mv and current == id) then
						local m, cx, blend, ratio = shadowM[depth], shadowCx[depth], shadowBlend[depth], shadowRatio[depth]

						if current then
							shadowDrop(depth)
							shown = shown - 1
						end

						if chars[id] then
							shadowId[depth] = id
							shadowM[depth] = op.m or m or IDENTITY
							shadowCx[depth] = op.cx or cx or false
							shadowBlend[depth] = op.bl or blend or false
							shadowRatio[depth] = op.r or ratio or false
							shown = shown + 1
						end
					elseif current then
						if op.m then shadowM[depth] = op.m end
						if op.cx then shadowCx[depth] = op.cx end
						if op.r then shadowRatio[depth] = op.r end
						if op.bl then shadowBlend[depth] = op.bl end
					end
				end
			end
		end
	end

	return shown
end

local function sameNumbers(a, b)
	if a == b then
		return true
	end

	if not a or not b then
		return false
	end

	local count = #a

	if count ~= #b then
		return false
	end

	for i = 1, count do
		if a[i] ~= b[i] then
			return false
		end
	end

	return true
end

local function sameTheme(copy, theme)
	if not theme or not copy then
		return theme == copy
	end

	local count = 0

	for name, rgb in next, theme do
		local saved = copy[name]
		count = count + 1

		if not saved or saved[1] ~= rgb[1] or saved[2] ~= rgb[2] or saved[3] ~= rgb[3] then
			return false
		end
	end

	for _ in next, copy do
		count = count - 1
	end

	return count == 0
end

local function copyTheme(theme)
	if not theme then
		return nil
	end

	local copy = {}

	for name, rgb in next, theme do
		copy[name] = {rgb[1], rgb[2], rgb[3]}
	end

	return copy
end

-- A new clip of each sprite that was asked about, to compare the clips that stay with (made once per sprite and colour theme: the movies' data does not change).
local templates = setmetatable({}, {__mode = "k"})

local function templateOf(clip, theme)
	local definition = clip.movie.chars[clip.id]

	if not definition or definition.k ~= "sprite" or definition.frames ~= clip.frames then
		return nil
	end

	local slot = templates[definition]

	if slot and slot.theme == theme and slot.movie == clip.movie and sameTheme(slot.copy, theme) then
		return slot.clip
	end

	slot = {theme = theme, movie = clip.movie, copy = copyTheme(theme), clip = newClip(clip.movie, definition, clip.id, theme)}
	templates[definition] = slot

	return slot.clip
end

local function plainEntry(entry)
	for key in next, entry do
		if not ENTRY_FIELDS[key] then
			return false
		end
	end

	return entry.kind ~= "text"
end

-- Whether `live`, a clip inside the one that goes back, is in the state of a new clip `made` (same sprite, same theme): everything this file keeps for a clip,
-- its display list with every property, its names, its clock. Then making it again would give what it is.
local function asNew(live, made)
	if live.version ~= made.version or live.frame ~= made.frame or live.frac ~= made.frac or live.pos ~= made.pos or live.playing ~= made.playing
		or live.visible ~= made.visible or live.jumps ~= made.jumps or live.theme ~= made.theme or live.count ~= made.count then
		return false
	end

	for key in next, live do
		if not CLIP_FIELDS[key] then
			return false
		end
	end

	local seen = 0

	for depth, entry in next, live.list do
		local other = made.list[depth]
		seen = seen + 1

		if not other or entry.depth ~= depth or entry.id ~= other.id or entry.kind ~= other.kind or entry.name ~= other.name or entry.blend ~= other.blend
			or entry.clipDepth ~= other.clipDepth or entry.ratio ~= other.ratio or entry.text ~= other.text
			or not sameNumbers(entry.m, other.m) or not sameNumbers(entry.cx, other.cx) then
			return false
		end

		for key in next, entry do
			if not ENTRY_FIELDS[key] then
				return false
			end
		end

		local child = entry.clip

		if child or other.clip then
			if not child or not other.clip or child.parent ~= live or child.entry ~= entry or not asNew(child, other.clip) then
				return false
			end
		end
	end

	if seen ~= made.count then
		return false
	end

	local named = 0

	for name, entry in next, live.names do
		local other = made.names[name]
		named = named + 1

		if not other or other.depth ~= entry.depth or live.list[entry.depth] ~= entry then
			return false
		end
	end

	for _ in next, made.names do
		named = named - 1
	end

	return named == 0
end

-- Goes back to `target` (< the current frame) keeping the objects; false, with nothing changed, when the result could differ from `_rebuild`'s.
function Clip:_rewind(target)
	if Flash.NoFastRewind then
		return false
	end

	local frames = self.frames

	for index = target + 1, self.frame do
		local frame = frames[index]

		if frame then
			for i = 1, #frame do
				local op = frame[i]

				if op.rm or op.c then
					return false
				end
			end
		end
	end

	local list = self.list

	if shadowReplay(frames, self.movie.chars, target) ~= self.count then
		return false
	end

	local theme = self.theme
	local seen = 0

	for depth, entry in next, list do
		seen = seen + 1

		if shadowId[depth] ~= entry.id or entry.depth ~= depth or not plainEntry(entry) then
			return false
		end

		local child = entry.clip

		if child then
			local made = child.parent == self and child.entry == entry and templateOf(child, theme)

			if not made or not asNew(child, made) then
				return false
			end
		end
	end

	if seen ~= self.count then
		return false
	end

	for _, entry in next, self.names do
		if list[entry.depth] ~= entry then
			return false
		end
	end

	for depth, entry in next, list do
		entry.m, entry.cx, entry.blend, entry.ratio = shadowM[depth], shadowCx[depth] or nil, shadowBlend[depth] or nil, shadowRatio[depth] or nil
	end

	return true
end

-- The rebuild of Flash: the display list is emptied and the frames from the first one to the target are replayed.
function Clip:_rebuild(target)
	self:_clear()

	for index = 1, target do
		self:_applyOps(index)
	end
end

-- Makes the display list that of `target` (already clamped). Going forward replays the frames in between
-- (children keep their state); going back keeps what stays (see _rewind) or else rebuilds from the first frame, as Flash does.
function Clip:_goto(target)
	if target == self.frame then
		return
	end

	if target < self.frame then
		local stats = Flash.RewindStats

		if self:_rewind(target) then
			stats.fast = stats.fast + 1
		else
			stats.slow = stats.slow + 1
			self:_rebuild(target)
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

-- A smooth bar (sh_flash_bar.lua, cl_hud_bar_smooth.lua): this clip is drawn as a group (it has a blend mode), and its cached image is cut by a vertical line at
-- x (in this clip's own coordinates, at height y): on the side of the line that `side` says (+1: the larger x) the image of `clone`, a clip of the same
-- kind kept at the next frame, is drawn instead (cl_flash_draw.lua, drawGroup). Numbers and one reference: setting them allocates nothing.
function Clip:SetCut(x, y, side, clone)
	self.cutX, self.cutY, self.cutSide, self.cutClone = x, y, side, clone
end

function Clip:ClearCut()
	self.cutX, self.cutY, self.cutSide, self.cutClone = nil, nil, nil, nil
end

-- The point (x, y) of this clip's own coordinates, in the coordinates of its ancestor `ancestor` (the entry matrices of the clips between them are
-- applied). Returns x and y; the point itself when `ancestor` is this clip or is not above it.
function Clip:PointIn(ancestor, x, y)
	local clip = self

	while clip and clip ~= ancestor do
		local entry = clip.entry

		if not entry then
			return x, y
		end

		local m = entry.m
		x, y = m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
		clip = clip.parent
	end

	return x, y
end

-- The horizontal scale of this clip's coordinates on the stage: the product of the entry matrices' a up to the root (a rotation of a few degrees
-- changes it by a thousandth). 1 for a clip that is not in a display list.
function Clip:ScaleX()
	local scale = 1
	local clip = self

	while clip do
		local entry = clip.entry

		if entry then
			scale = scale * entry.m[1]
		end

		clip = clip.parent
	end

	return scale
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

-- The definition of the text field with this instance name (at this level) as it is drawn: the movie's own, or this clip's copy
-- when its width was changed (FitTextWidth). nil when there is no such text field.
function Clip:Field(name)
	local entry = self.names[name]

	if not entry or entry.kind ~= "text" then
		return nil
	end

	return entry.field or self.movie.chars[entry.id]
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

-- Widens the text field with this instance name (at this level) on THIS clip only, so that `text` is not cut: the width is
-- the text's plus the two margins, never less than the movie's own width and never more than `maxWidth` (the room the caller
-- knows the field has; a `maxWidth` under the movie's width leaves the movie's). The field keeps its left edge and grows to the
-- right; the movie's definition is never changed (the other clips made from it keep their width). Only single line fields.
-- The clip draws again only when the width changes. Returns whether the field was found.
function Clip:FitTextWidth(name, text, maxWidth)
	local entry = self.names[name]

	if not entry or entry.kind ~= "text" then
		return false
	end

	local definition = self.movie.chars[entry.id]
	local font = self.movie.fonts and self.movie.fonts[definition.f]
	local width = definition.w

	if font and not definition.ml and text and text ~= "" then
		local _, _, textWidth = Flash.LayoutText(font, definition, text)
		width = math.min(math.max(width, textWidth + 2 * TEXT_MARGIN), math.max(maxWidth or width, width))
	end

	local current = entry.field and entry.field.w or definition.w

	if width ~= current then
		entry.field = width ~= definition.w and setmetatable({w = width}, {__index = definition}) or nil
		self:_touch()
	end

	return true
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

