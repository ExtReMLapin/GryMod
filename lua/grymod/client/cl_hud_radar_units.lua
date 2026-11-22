-- The contacts on the radar panel: the icons of the original movie's Units clip (HUD_RadarCompassStealth), placed with the
-- formulas of the movie's own script (setObjectArray) from the units the server sends (sv_radar.lua). The rules and the
-- numbers are in docs/superpowers/plans/2026-11-21-radar-research.md. Loaded after cl_hud_radar_flash.lua.

GryMod = GryMod or {}

local Flash = GryMod.Flash
local Radar = GryMod.FlashRadar
local S = GryMod.RadarShared

-- The polygon the original game clips its units with, in radar pixels around the player (x right, y down). At the original's scale (43 pixels for 75 m) it is
-- 73 m ahead, 78 m behind, 101 m to the left and 108 m to the right. It is smaller than the glass the movie draws, so with it a contact vanished while still
-- over the glass (and the minimap stopped short of the glass): see Radar.FRAME.
Radar.ORIGINAL_FRAME = {
	{-58, 17}, {-58, -42}, {62, -42}, {62, 32.15}, {46.25, 45}, {-46.75, 45}, {-46.75, 25.8}
}

-- The radar frame, in the same radar pixels: the glass the movie really shows, which is the outline of its NoiseMask clip (the clip that masks the units) taken
-- through the conversion below (the player at (64.1, 52.3) of the Units clip, 110 / 94 movie pixels for a radar pixel, the matrices of NoiseMask and Units). A contact
-- is drawn until it leaves the glass, and the minimap fills it (View.MapFrame is this polygon without the strip of the danger bar, left of the notch). It is 46 pixels
-- ahead, 49.5 behind, 77 to the left and 71 to the right of the player; at 38 m for 43 pixels that is 40.5, 43.8, 68.4 and 62.6 m. tests/minimap/radar_frame_test.lua
-- derives the polygon from the movie's data and compares. GryMod.RadarShared.SCAN_FACTOR (the server's search radius) has to reach its farthest corner.
Radar.FRAME = {
	{-77.38, 11.75}, {-77.38, -45.95}, {70.8, -45.95}, {70.8, 36.19}, {54.22, 49.99}, {-51.23, 49.09}, {-51.23, 28.37}
}

-- The left edge of the map, in radar pixels: the movie's own map window (the mask of its MapArea) starts there, right of the danger bar (the StealthBar clip, -74.9 to -66.7).
-- The part of the glass between this and the notch of the frame (x = -51.23) is map too: cutting the map at the notch left a hole 14.6 pixels wide beside the bar.
-- tests/minimap/radar_frame_test.lua derives it from the movie's data. View.MapFrame() starts the map here.
Radar.MAP_LEFT = -65.8

-- The movie turns radar pixels into its own coordinates: x = n * 110 + 10 and y = n * 110 - 3.5, with n over the 94 pixels
-- of the radar's square; so the centre of the radar is at (65, 51.5) and one radar pixel is 110 / 94 movie pixels.
-- The radius of the radar is the player's choice (the original has a constant 75 m, or the level's mapRadius): 5 to 100 metres, 75 by default (at 5 the map is a close-up).
-- A smaller radius makes the same pixels stand for fewer metres: the icons of big things (a vehicle) are then closer to their real size.
local RangeConVar = CreateClientConVar("gry_radar_range", "75", true, false,
	"Radius of the radar in metres (5 to 100). 75 is the original game's; 40 to 75 are good values: at 75 an icon of a vehicle stands for about 14 metres of ground; down to 5 zooms the map right in", 5, 100)

-- The radius the player asked for (whole metres): the slider, or, with the automatic zoom on (cl_hud_radar_zoom.lua), the range of the mode in use.
-- The server, the map's definition and the tiles asked for follow THIS one at once.
function Radar.TargetRange()
	local Zoom = GryMod.RadarZoom

	if Zoom and Zoom.Enabled() then
		return Zoom.TargetRange()
	end

	return S.ClampRange(RangeConVar:GetFloat())
end

-- The radius the radar DRAWS with: the same, except while the automatic zoom glides from one range to another (then a number with decimals, on its way to
-- the target). The contacts and the map are placed with it.
function Radar.Range()
	local Zoom = GryMod.RadarZoom

	if Zoom and Zoom.Enabled() then
		return Zoom.Displayed(RealTime())
	end

	return S.ClampRange(RangeConVar:GetFloat())
end

Radar.UNITS_PIXEL = 110 / 94
-- The script's arithmetic gives (65, 51.5), but the player is not drawn there: MEASURED on two screenshots of the game (the movie's own
-- vertical line and the base of the view cone, against icons whose movie coordinates were known), the centre of the radar is at
-- (64.1, 52.3) in the Units clip: a unit straight ahead sits on the line. 1 pixel of the film is about 4.6 pixels at 4K.
Radar.UNITS_CENTRE_X = 64.1
Radar.UNITS_CENTRE_Y = 52.3

-- The pulse of the alerted icons: the phase turns 3 radians a second and the alpha is cos * 0.35 + 0.65 (30 to 100 %).
Radar.PULSE_SPEED = 3
Radar.ALPHA = 85

-- The ally: the movie has no icon for it, so the calm still image of its type is drawn with a colour transform whose multipliers
-- (red, green, blue) turn it blue. The transform is the movie's own mechanism (the clip's colour transform, as the theme
-- colours use); no image is made for it.
Radar.ALLY_TINT = {0.3, 0.6, 1}

local frame = Radar.FRAME

local function insideFrame(x, y)
	local inside = false
	local j = #frame

	for i = 1, #frame do
		local xi, yi, xj, yj = frame[i][1], frame[i][2], frame[j][1], frame[j][2]

		if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then
			inside = not inside
		end

		j = i
	end

	return inside
end

-- Where the line from the centre to (x, y) leaves the frame (the frame is seen whole from its centre, so the line meets
-- it once).
local function borderPoint(x, y)
	local best = math.huge
	local j = #frame

	for i = 1, #frame do
		local ax, ay, bx, by = frame[j][1], frame[j][2], frame[i][1], frame[i][2]
		local ex, ey = bx - ax, by - ay
		local denominator = x * ey - y * ex

		if math.abs(denominator) > 1e-9 then
			local s = (ax * ey - ay * ex) / denominator
			local t = (ax * y - ay * x) / denominator

			if s > 0 and t >= 0 and t <= 1 and s < best then
				best = s
			end
		end

		j = i
	end

	if best == math.huge then
		return 0, 0
	end

	return x * best, y * best
end

-- The size of an icon for a unit `dz` metres above the player: 1.3 when it is 15 m or more below, 2.5 when 15 m or more
-- above, between in a straight line; times 25 percent.
local function sizeFor(dz, big)
	local t = math.Clamp((dz + 15) / 30, 0, 1)
	local size = 25 * (1.3 + (2.5 - 1.3) * t)

	return big and size * 2 or size
end

-- The entries for the movie, from the player's position and yaw (degrees) and the contacts {id, x, y, z, yaw, type, sub,
-- marker, big}: {id, x, y, rotation, frame, scale, alpha, tint}, in the movie's coordinates (tint: the colour multipliers of an
-- ally, nil for the movie's own colours). A unit outside the frame or more
-- than 500 m above or below is left out, except a marker (the unit that hurt the player), which is put on the border of
-- the frame. `phase` is the pulse of the alerted icons.
function Radar.Contacts(pos, yaw, contacts, phase, range)
	local list = {}

	if not contacts or not pos or not (yaw == yaw) then
		return list
	end

	local radians = math.rad(yaw)
	local cos, sin = math.cos(radians), math.sin(radians)
	local pixels = S.METRES_PER_UNIT * S.PIXELS / (range or S.RANGE)
	local pulse = 100 * (math.cos(phase or 0) * 0.35 + 0.65)
	local px, py, pz = pos.x, pos.y, pos.z

	for i = 1, math.min(#contacts, S.MAX_CONTACTS) do
		local c = contacts[i]
		local dx, dy, dz = c.x - px, c.y - py, c.z - pz

		if dx == dx and dy == dy and dz == dz and math.abs(dz) * S.METRES_PER_UNIT <= S.HEIGHT_LIMIT then
			-- x right, y down on the radar (up is where the player looks)
			local x = (dx * sin - dy * cos) * pixels
			local y = -(dx * cos + dy * sin) * pixels
			local show = true

			if not insideFrame(x, y) then
				if c.marker then
					x, y = borderPoint(x, y)
				else
					show = false
				end
			end

			if show then
				local ally = c.sub == S.SUB_ALLY

				list[#list + 1] = {
					id = c.id,
					x = Radar.UNITS_CENTRE_X + x * Radar.UNITS_PIXEL,
					y = Radar.UNITS_CENTRE_Y + y * Radar.UNITS_PIXEL,
					rotation = (yaw - c.yaw + 180) % 360,
					frame = c.type * 5 + (ally and 0 or c.sub),
					scale = sizeFor(dz * S.METRES_PER_UNIT, c.big),
					alpha = (c.sub >= 3 and c.sub <= 4 and not c.marker) and pulse or Radar.ALPHA,
					tint = ally and Radar.ALLY_TINT or nil
				}
			end
		end
	end

	return list
end

-- A copy of the child `sourceName` of `parent` with the instance name `name` at `depth`: what the movie's script does with
-- duplicateMovieClip. The copy has its own timeline (starting at its first frame) and its own placement; cl_flash.lua only
-- builds clips from the movie's timelines, so this is the one place that makes one by hand.
function Flash.Duplicate(parent, sourceName, name, depth)
	local source = parent.names[sourceName]

	if not source or not source.clip then
		return nil
	end

	local clip = Flash.NewClip(parent.movie, source.id, parent.theme)

	if not clip then
		return nil
	end

	local entry = {
		depth = depth, id = source.id, kind = "sprite", m = source.m, cx = source.cx, name = name, blend = source.blend,
		clipDepth = nil, ratio = source.ratio, clip = clip
	}

	clip.parent = parent
	clip.entry = entry
	parent.list[depth] = entry
	parent.names[name] = entry
	parent.count = parent.count + 1
	parent.sorted = nil
	parent:_touch()

	return clip
end

local Panel = Radar.Panel

-- The movie's blend mode "add" (the script sets blendMode = 8 on the copies).
local BLEND_ADD = 8

-- The colour multipliers of an icon: the tint of the entry, or the movie's own colours. The alpha and the added colour of its
-- transform stay as they are.
local function setTint(icon, tint)
	local entry = icon.entry
	local cx = entry.cx
	local r, g, b = 1, 1, 1

	if tint then
		r, g, b = tint[1], tint[2], tint[3]
	end

	if not cx then
		if not tint then
			return
		end

		cx = {1, 1, 1, 1, 0, 0, 0, 0}
	end

	if cx[1] == r and cx[2] == g and cx[3] == b then
		return
	end

	entry.cx = {r, g, b, cx[4], cx[5], cx[6], cx[7], cx[8]}

	if icon.parent then
		icon.parent:_touch()
	end
end

-- setObjectArray: gives the icons of the Units clip the entries of Radar.Contacts. The icons are made when they are first
-- needed (named "ObjectIcon_" .. n at depth n + 99 + 1, like the script's) and kept; the ones past the list are hidden.
function Panel:SetObjects(list)
	local units = self.main:Child("Units")

	if not units then
		return
	end

	-- the movie's own timeline can rebuild the clip (a reboot, a malfunction): the icons were its children
	if self.unitsClip ~= units then
		self.unitsClip = units
		self.icons = {}
	end

	local icons = self.icons
	local count = math.min(#list, S.MAX_CONTACTS)

	for i = 1, count do
		local e = list[i]
		local icon = icons[i]

		if not icon then
			icon = Flash.Duplicate(units, "ObjectIcon", "ObjectIcon_" .. (i + 99), i + 99)

			if not icon then
				return
			end

			icon.entry.blend = BLEND_ADD
			icons[i] = icon
		end

		local image = icon:Child("Icon")

		if image and image:CurrentFrame() ~= e.frame then
			image:GotoAndStop(e.frame)
		end

		icon:SetX(e.x)
		icon:SetY(e.y)
		icon:SetScale(e.scale, e.scale)
		icon:SetRotation(e.rotation)
		icon:SetAlpha(e.alpha)
		setTint(icon, e.tint)
		icon:SetVisible(true)
	end

	for i = count + 1, #icons do
		if icons[i].visible then
			icons[i]:SetVisible(false)
		end
	end
end

-- What the server sent last: the contacts and when.
Radar.Snapshot = {}
Radar.SnapshotTime = 0

net.Receive("gry_radar", function()
	Radar.Snapshot = S.Read()
	Radar.SnapshotTime = RealTime()
end)

-- The contacts to draw now: the server's list, with the position and facing of each unit read from the entity when the client
-- has it (it moves every frame, the list comes five times a second).
local live = {}

-- How the entity of a contact is found (replaced by the tests).
Radar.FindEntity = Entity

-- The way an entity faces, in degrees: its yaw, except for a vehicle, which faces 90 degrees from it (MEASURED on a real Buggy: the
-- Buggy and the airboat at yaw 0 face along +y). Not through GetForward: on the server it says so, on the client it is the forward of
-- the raw angles. The same rule as the server's (Radar.Facing, sv_radar.lua), which this replaces whenever the client has the entity.
Radar.VEHICLE_YAW = 90

function Radar.Facing(ent)
	local yaw = ent:GetAngles().y

	if isfunction(ent.IsVehicle) and ent:IsVehicle() then
		return yaw + Radar.VEHICLE_YAW
	end

	return yaw
end

function Radar.Live()
	local snapshot = Radar.Snapshot
	local count = #snapshot

	for i = 1, count do
		local c = snapshot[i]
		local l = live[i]

		if not l then
			l = {}
			live[i] = l
		end

		l.id, l.type, l.sub, l.marker, l.big = c.id, c.type, c.sub, c.marker, c.big
		l.x, l.y, l.z, l.yaw = c.x, c.y, c.z, c.yaw

		local ent = Radar.FindEntity(c.id)

		if IsValid(ent) and not ent:IsDormant() then
			local at = ent:GetPos()
			l.x, l.y, l.z = at.x, at.y, at.z
			l.yaw = Radar.Facing(ent)
		end
	end

	for i = count + 1, #live do
		live[i] = nil
	end

	return live
end

-- Whether the client wants the contacts: the HUD fed the radar within the last moments and its switches are on.
local lastFeed = -1000
local wanted, sentRange

local function wantsContacts()
	local options = GryMod.HUDOptions

	return RealTime() - lastFeed < 1.5 and (not options or (options.Enabled("radar") and options.Enabled("radarunits")))
end

-- Tells the server whether this client wants the contacts and in which radius (8 bits, metres): at a change of either, and not otherwise.
function Radar.TellServer(want)
	local range = Radar.TargetRange()

	if want ~= wanted or (want and range ~= sentRange) then
		wanted, sentRange = want, range
		net.Start("gry_radar_want")
		net.WriteBool(want)
		net.WriteUInt(range, 8)
		net.SendToServer()
	end
end

-- The target range changed (the automatic zoom went to another mode): tells the server now, not at the next tick of the one second timer. Does nothing
-- while the server was not told that the contacts are wanted.
function Radar.RangeChanged()
	if wanted then
		Radar.TellServer(true)
	end
end

-- Forgets what was told (the tests).
function Radar.ResetWant()
	wanted, sentRange = nil, nil
end

timer.Create("GryMod radar want", 1, 0, function()
	Radar.TellServer(wantsContacts())
end)

-- The stealth bar of the panel: the original asks its AI system for the detection level of the hostile AI around the player
-- (0 to 1, the bar takes the higher of two such numbers; the ramp is the AI system's, see the research note, section 7). Here
-- it comes from the contacts the server sends, so friends and neutrals never count: a hostile that fights the player (or just
-- shot him: its marker) is 1, a hostile that is alerted is 0.5, a calm one, a friend and nothing are 0. The highest wins, a
-- crowd does not add up. Only what the server lists counts: a hostile is listed once it is alerted within 26 m of the player
-- or after a binoculars scan, and within 97 m (the scan radius), so a distant shooter or an alert past 26 m does not show.
Radar.STEALTH_FIGHTING = 1
Radar.STEALTH_ALERTED = 0.5
-- Units a second: fast up (a unit that sees the player is felt at once), slow down (it takes a while to lose him).
Radar.STEALTH_RISE = 1
Radar.STEALTH_FALL = 0.25

-- The awareness of one contact {sub, marker}: sub 4 fighting the player and 3 alerted are the hostile ones; sub 2 is a calm
-- hostile, except when it is a marker (it hurt the player in the last 10 s); 0 and 1 are not hostile, and 5 (S.SUB_ALLY) is an ally,
-- which never counts, marker or not.
function Radar.Awareness(c)
	local sub = c.sub

	if sub == 4 or sub == 2 and c.marker then
		return Radar.STEALTH_FIGHTING
	end

	if sub == 3 then
		return Radar.STEALTH_ALERTED
	end

	return 0
end

-- The level the bar goes to for a list of contacts {sub, marker}.
function Radar.StealthTarget(contacts)
	local target = 0

	if not contacts then
		return target
	end

	for i = 1, math.min(#contacts, S.MAX_CONTACTS) do
		local awareness = Radar.Awareness(contacts[i])

		if awareness > target then
			target = awareness
		end
	end

	return target
end

-- The level `dt` seconds after `level` when it is going to `target`.
function Radar.StealthStep(level, target, dt)
	if level == nil or level ~= level then
		level = 0
	end

	if dt == nil or dt ~= dt or dt <= 0 then
		return level
	end

	if level < target then
		return math.min(level + Radar.STEALTH_RISE * dt, target)
	end

	return math.max(level - Radar.STEALTH_FALL * dt, target)
end

-- The level the bar shows now.
Radar.Stealth = 0

-- Each frame the HUD draws: the phase of the pulse, the contacts of the server placed for this frame, the stealth bar.
local phase = 0

local zoomError

function Radar.Feed(panel, ply, dt)
	lastFeed = RealTime()
	phase = (phase + dt * Radar.PULSE_SPEED) % (2 * math.pi)

	-- the automatic zoom looks at the place (nothing at all while it is off); a failure is told once and the radar goes on with the range it has
	local Zoom = GryMod.RadarZoom

	if Zoom then
		local ok, err = pcall(Zoom.Update, ply, lastFeed)

		if not ok and err ~= zoomError then
			zoomError = err
			ErrorNoHalt("[GryMod] radar automatic zoom: " .. tostring(err) .. "\n")
		end
	end

	-- off to on at once (the timer notices the other way within a second)
	if not wanted then
		Radar.TellServer(wantsContacts())
	end

	local options = GryMod.HUDOptions

	if options and not options.Enabled("radarunits") or not wanted then
		panel:SetObjects({})
		-- no contacts, no news of the hostiles: the bar goes down
		Radar.Stealth = Radar.StealthStep(Radar.Stealth, 0, dt)
		panel:SetStealth(Radar.Stealth)

		return
	end

	panel:SetObjects(Radar.Contacts(ply:GetPos(), ply:EyeAngles().y, Radar.Live(), phase, Radar.Range()))
	Radar.Stealth = Radar.StealthStep(Radar.Stealth, Radar.StealthTarget(Radar.Snapshot), dt)
	panel:SetStealth(Radar.Stealth)
end
