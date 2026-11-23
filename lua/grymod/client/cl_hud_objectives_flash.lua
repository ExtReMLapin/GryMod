-- The objective markers on the screen, drawn from the original Scaleform movie (HUD_MissionObjective_Icon), see cl_flash.lua. One marker for each ACTIVE
-- objective of GryMod.Objectives.List() that has `marker` on, at the place of the objective on the screen:
--   * the yellow diamond (frame icon24_0) with the distance in metres, smaller the further the objective is (1.4 up to 10 m, 0.7 from 500 m, the original's
--     hud_onScreenNearDistance / FarDistance / NearSize / FarSize defaults);
--   * when the objective is off the screen or behind the player, one of the 8 arrows of the movie (icon13_0 to icon20_0) on the border of the screen, the one
--     that points the way (the movie's own matrices: 13 points left, 14 up-left, 15 up, 16 up-right, 17 right, 18 down-right, 19 down, 20 down-left);
--   * the marker nearest to the middle of the screen (when it is close enough) opens the description box of the movie (setNearCenter): the title of the
--     objective in it. The others close theirs.
-- What the original does not do and this file does not either: a primary and a secondary objective look the same on the screen (the original's single player
-- call has no secondary flag; they differ on the radar and in the list); a finished or failed objective has no marker (the original takes it out of the map;
-- the movie has no grey frame for it); the binoculars change nothing (the markers stay while the player zooms). The colours are the HUD theme's.
-- The movie's own script (updateMissionObjectives, setNearCenter, UpdateText) is ported by hand: the engine runs only the stop / play / goto actions.
--
-- Cost: nothing at all when there is nothing to show. The paint hook exists only while an eligible objective exists (it is added and removed by the three
-- reporting hooks of the objectives and by the switch gry_hud_objectives); no Think. The player turns it off with gry_hud_objectives (a HUD element).

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Marks = GryMod.FlashObjectives or {}
GryMod.FlashObjectives = Marks

Marks.MOVIE = "hud_missionobjective_icon"

local STAGE_W, STAGE_H = 1366, 768

-- The original's defaults (the cvars hud_onScreenNearDistance, FarDistance, NearSize, FarSize), in metres and as a factor of the picture.
Marks.NEAR_DISTANCE, Marks.FAR_DISTANCE = 10, 500
Marks.NEAR_SIZE, Marks.FAR_SIZE = 1.4, 0.7

-- The picture of an objective on the screen, and the state number of the frames (the single player call always gives 0).
Marks.TYPE_OBJECTIVE = 24
Marks.STATE = 0

-- How many markers at most (the objectives are 256 at most; nobody reads more than a few of them on a screen).
Marks.MAX = 24

-- How far from the border of the screen (stage pixels) the picture of an arrow stands: the arrow is about 30 pixels across.
Marks.EDGE_MARGIN = 40

-- A marker is "near the middle" when the squared normalised offset of its centre (0 in the middle, 1 at the border of the screen at the middle of a side) is
-- under this: about a fifth of the half screen. The original's constant is not known; this is a choice.
Marks.CENTRE_LIMIT = 0.05

-- The arrows of the movie by the way they point, from "right" turning clockwise (the screen's y goes down), in steps of 45 degrees.
local ARROWS = {17, 18, 19, 20, 13, 14, 15, 16}

local METRES_PER_UNIT = GryMod.RadarShared and GryMod.RadarShared.METRES_PER_UNIT or 0.01905

local OPEN_LABEL, CLOSE_FRAME = "open", 22

-- ---------------------------------------------------------------------------------------------------------
-- The pure parts
-- ---------------------------------------------------------------------------------------------------------

-- The size of the picture for an objective `metres` away: a straight line between the near and the far values, held outside them.
function Marks.SizeFor(metres)
	local t = (metres - Marks.NEAR_DISTANCE) / (Marks.FAR_DISTANCE - Marks.NEAR_DISTANCE)

	if t < 0 then
		t = 0
	elseif t > 1 then
		t = 1
	end

	return Marks.NEAR_SIZE + (Marks.FAR_SIZE - Marks.NEAR_SIZE) * t
end

-- The arrow (a type 13 to 20 of the movie) that points the way (dx, dy): x to the right, y down.
function Marks.ArrowFor(dx, dy)
	local sector = math.floor((math.deg(math.atan2(dy, dx)) + 22.5) / 45) % 8

	return ARROWS[sector + 1]
end

-- The name of the frame of the movie.
function Marks.Label(kind, state)
	return "icon" .. kind .. "_" .. (state or Marks.STATE)
end

-- Whether an objective has a marker: it is active and its marker is on. Primary and secondary alike.
function Marks.Eligible(o)
	return o.marker == true and o.state == "active"
end

-- The picture of the stage on a screen of w x h pixels: as high as the screen, centred across its width. Returns the x of its left side, the y (0) and the
-- number of screen pixels for a stage pixel.
function Marks.Placement(w, h)
	local scale = h / STAGE_H

	return (w - STAGE_W * scale) / 2, 0, scale
end

-- Where a marker goes, in the stage's own coordinates. (sx, sy) is the point on the screen as the engine says (`visible` false: behind the camera, where the
-- engine's answer is the mirror image and means nothing); (dx, dy) is the way to the point on the screen (x right, y down: what the player would have to
-- turn towards), used when the point is not on the screen. Returns x, y, the type of the picture (24 on the screen, an arrow off it) and whether it is on
-- the screen.
function Marks.Layout(sx, sy, visible, dx, dy, w, h)
	local ox, _, scale = Marks.Placement(w, h)
	local margin = Marks.EDGE_MARGIN * scale
	local px, py, kind
	local onScreen = visible and sx >= margin and sx <= w - margin and sy >= margin and sy <= h - margin

	if onScreen then
		px, py, kind = sx, sy, Marks.TYPE_OBJECTIVE
	else
		-- straight behind: no way to the side, so the bottom of the screen
		if dx * dx + dy * dy < 1e-6 then
			dx, dy = 0, 1
		end

		local halfW, halfH = w / 2 - margin, h / 2 - margin
		local t = math.min(halfW / math.abs(dx), halfH / math.abs(dy))

		px, py, kind = w / 2 + dx * t, h / 2 + dy * t, Marks.ArrowFor(dx, dy)
	end

	return (px - ox) / scale, py / scale, kind, onScreen == true
end

-- How far a point of the screen is from the middle, squared and normalised: 0 in the middle, 1 in the middle of a side.
function Marks.CentreDistance2(sx, sy, w, h)
	local nx, ny = (sx - w / 2) / (w / 2), (sy - h / 2) / (h / 2)

	return nx * nx + ny * ny
end

-- The id of the marker that opens its description: of the first `count` entries, the one on the screen nearest to the middle, when it is close enough. nil
-- for none.
function Marks.NearCentreId(entries, count)
	local best, bestDistance = nil, Marks.CENTRE_LIMIT

	for i = 1, count do
		local e = entries[i]

		if e.onScreen and e.centre < bestDistance then
			best, bestDistance = e.id, e.centre
		end
	end

	return best
end

-- ---------------------------------------------------------------------------------------------------------
-- The engine (replaced by the tests)
-- ---------------------------------------------------------------------------------------------------------

-- The place of the marker for an objective: the middle of the entity it follows when the client has it, else its position.
function Marks.PositionOf(o)
	local ent = o.ent

	if ent and IsValid(ent) then
		return ent:WorldSpaceCenter()
	end

	return o.pos
end

-- Where a world point is for the player: the screen position and whether it is in front, the way to it on the screen (right, down) and its distance in
-- metres. Called while the HUD paints, where the view is the right one.
function Marks.Project(pos)
	local screen = pos:ToScreen()
	local ang = EyeAngles()
	local way = pos - EyePos()

	return screen.x, screen.y, screen.visible, way:Dot(ang:Right()), -way:Dot(ang:Up()), way:Length() * METRES_PER_UNIT
end

-- ---------------------------------------------------------------------------------------------------------
-- The entries of a frame
-- ---------------------------------------------------------------------------------------------------------

local entries = {}

-- The markers to show for `list` (GryMod.Objectives.List()): the table of entries (reused: good until the next call) and how many. An entry: id, title, x, y
-- (stage), type, onScreen, centre (squared distance to the middle, on the screen), metres (whole), size.
function Marks.Collect(list)
	local w, h = ScrW(), ScrH()
	local count = 0

	for i = 1, #list do
		local o = list[i]

		if count < Marks.MAX and Marks.Eligible(o) then
			local sx, sy, visible, dx, dy, metres = Marks.Project(Marks.PositionOf(o))
			local e = entries[count + 1]

			if not e then
				e = {}
				entries[count + 1] = e
			end

			count = count + 1
			e.id, e.title = o.id, o.title
			e.x, e.y, e.type, e.onScreen = Marks.Layout(sx, sy, visible, dx, dy, w, h)
			e.centre = e.onScreen and Marks.CentreDistance2(sx, sy, w, h) or 1
			e.metres = math.floor(metres + 0.5)
			e.size = Marks.SizeFor(metres)
		end
	end

	for i = #entries, count + 1, -1 do
		entries[i] = nil
	end

	return entries, count
end

-- ---------------------------------------------------------------------------------------------------------
-- The movie
-- ---------------------------------------------------------------------------------------------------------

local instance -- {root, holder, icons}
local failed = false
local hooked = false
local lastTime

local HOOK = "GRYFLASHOBJECTIVES"

local function ensure()
	if instance then
		return instance
	end

	if failed then
		return nil
	end

	local movie = Flash.Load(Marks.MOVIE)
	local root = movie and Flash.NewRoot(movie, GryMod.FlashHUD and GryMod.FlashHUD.Theme)
	local holder = root and root:Child("Root1")
	local template = holder and holder.Child and holder:Child("MissionObjective")

	if not template or not template.SetVisible or not Flash.Duplicate then
		if root then
			Flash.ReleaseClip(root)
		end

		failed = true

		return nil
	end

	-- the movie's own script hides the template, the colour sources and the player name; the copies are the markers
	template:SetVisible(false)

	for _, name in ipairs({"PlayerNameVar", "Line", "Over", "Text"}) do
		local clip = root:Child(name)

		if clip and clip.SetVisible then
			clip:SetVisible(false)
		end
	end

	instance = {root = root, holder = holder, icons = {}}

	return instance
end

-- The marker `index`: made when it is first needed (a copy of the template, like the movie's duplicateMovieClip) and kept.
local function iconFor(current, index)
	local icon = current.icons[index]

	if not icon then
		local clip = Flash.Duplicate(current.holder, "MissionObjective", "Objective_" .. (index + 99), index + 99)

		if not clip then
			return nil
		end

		icon = {clip = clip}
		current.icons[index] = icon
	end

	return icon
end

-- The texts of the box of an icon (the movie's UpdateText: the distance and the description, read from the icon's variables each time it is called). The
-- box is made again when its clip goes back to its first frame, so they are written again whenever its frame, the distance or the title changed.
local function writeTexts(icon, e, card)
	local frame = card:CurrentFrame()

	if icon.textFrame == frame and icon.textMetres == e.metres and icon.textTitle == e.title then
		return
	end

	icon.textFrame, icon.textMetres, icon.textTitle = frame, e.metres, e.title

	local distance = card:Find("DistanceText.Colorset")

	if distance then
		distance:SetText("DistanceText", e.metres .. "M")
	end

	local description = card:Find("MissionObjectiveText.Colorset")

	if description then
		description:SetText("MissionObjectiveText", e.title)
	end
end

-- updateMissionObjectives for one marker.
local function applyIcon(icon, e)
	local clip = icon.clip
	local label = Marks.Label(e.type)

	if icon.label ~= label then
		clip:GotoAndStop(label)
		icon.label = label
		icon.textFrame = nil
	end

	icon.id = e.id

	if icon.x ~= e.x then
		clip:SetX(e.x)
		icon.x = e.x
	end

	if icon.y ~= e.y then
		clip:SetY(e.y)
		icon.y = e.y
	end

	if icon.size ~= e.size then
		clip:SetScale(e.size * 100, e.size * 100)
		icon.size = e.size
	end

	if not icon.shown then
		clip:SetVisible(true)
		icon.shown = true
	end

	local card = clip:Child("MissionObectiveIcon")

	if card then
		writeTexts(icon, e, card)
	end
end

-- setNearCenter of the movie: the marker with this id opens its box (when it is closed), the others close theirs (when they are open and not already closing).
local function nearCentre(current, count, id)
	for i = 1, count do
		local icon = current.icons[i]
		local card = icon and icon.clip:Child("MissionObectiveIcon")

		if card then
			local frame = card:CurrentFrame()

			if icon.id == id then
				if frame == 1 then
					card:GotoAndPlay(OPEN_LABEL)
				end
			elseif frame > 1 and frame < CLOSE_FRAME then
				card:GotoAndPlay("close")
			end
		end
	end
end

-- The markers of the movie for `count` entries: each takes its entry, the ones past them hide, the boxes open and close.
function Marks.Apply(current, list, count)
	local icons = current.icons

	for i = 1, count do
		local icon = iconFor(current, i)

		if not icon then
			return
		end

		applyIcon(icon, list[i])
	end

	for i = count + 1, #icons do
		if icons[i].shown then
			icons[i].clip:SetVisible(false)
			icons[i].shown = false
		end
	end

	nearCentre(current, count, Marks.NearCentreId(list, count))
end

-- Whether the markers are on: the HUD is on (and the suit with it) and the player did not turn them off.
function Marks.Enabled()
	return GryMod.FlashHUD ~= nil and GryMod.FlashHUD.Enabled() and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("objectives"))
end

function Marks.Paint()
	local ply = LocalPlayer()

	if not IsValid(ply) or not ply:Alive() or not Marks.Enabled() then
		lastTime = nil

		return
	end

	local list, count = Marks.Collect(GryMod.Objectives.List())

	if count == 0 then
		lastTime = nil

		return
	end

	local current = ensure()

	if not current then
		return
	end

	Marks.Apply(current, list, count)

	local now = RealTime()
	local dt = math.min(now - (lastTime or now), 0.1)
	lastTime = now

	current.root:Advance(dt)

	local x, y, scale = Marks.Placement(ScrW(), ScrH())

	Flash.Draw(current.root, x, y, scale)
end

-- ---------------------------------------------------------------------------------------------------------
-- The paint hook follows the list
-- ---------------------------------------------------------------------------------------------------------

-- Whether something is to be shown: the option is on and an objective is eligible.
local function wanted()
	if GryMod.HUDOptions and not GryMod.HUDOptions.Enabled("objectives") then
		return false
	end

	local list = GryMod.Objectives and GryMod.Objectives.List()

	if not list then
		return false
	end

	for i = 1, #list do
		if Marks.Eligible(list[i]) then
			return true
		end
	end

	return false
end

-- Adds the paint hook when there is something to show, takes it away when there is not. Told by the reporting hooks of the objectives and by the switch: it
-- is the only place that decides.
function Marks.Refresh()
	local want = wanted()

	if want and not hooked then
		lastTime = nil
		hook.Add("HUDPaint", HOOK, Marks.Paint)
		hooked = true
	elseif not want and hooked then
		hook.Remove("HUDPaint", HOOK)
		hooked = false
		lastTime = nil
	end
end

function Marks.Active()
	return hooked
end

-- The markers of the movie (tests and tools): {{clip, id, label...}, ...}, nil before the first one was shown.
function Marks.Icons()
	return instance and instance.icons
end

-- Takes everything away (a new life, a new theme): the next frame builds the movie again.
function Marks.Reset()
	if instance then
		Flash.ReleaseClip(instance.root)
	end

	instance, failed = nil, false
	lastTime = nil
end

hook.Add("GryMod_ObjectiveAdded", "GryObjectiveMarks", function()
	Marks.Refresh()
end)

hook.Add("GryMod_ObjectiveChanged", "GryObjectiveMarks", function()
	Marks.Refresh()
end)

hook.Add("GryMod_ObjectiveRemoved", "GryObjectiveMarks", function()
	Marks.Refresh()
end)

cvars.AddChangeCallback("gry_hud_objectives", function()
	Marks.Refresh()
end, "GryObjectiveMarks")

-- objectives that exist already (a reload of this file, or the file loaded after the first list)
Marks.Refresh()
