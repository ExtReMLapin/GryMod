-- The contacts on the radar panel: the icons of the original movie's Units clip (HUD_RadarCompassStealth), placed with the
-- formulas of the movie's own script (setObjectArray) from the units the server sends (sv_radar.lua). The rules and the
-- numbers are in docs/superpowers/plans/2026-11-21-radar-research.md. Loaded after cl_hud_radar_flash.lua.

GryMod = GryMod or {}

local Flash = GryMod.Flash
local Radar = GryMod.FlashRadar
local S = GryMod.RadarShared

-- The radar frame in radar pixels around its centre (x right, y down): the polygon the original clips the units with.
-- At the original's scale (43 pixels for 75 m) it is 73 m ahead, 78 m behind, 101 m to the left and 108 m to the right.
Radar.FRAME = {
	{-58, 17}, {-58, -42}, {62, -42}, {62, 32.15}, {46.25, 45}, {-46.75, 45}, {-46.75, 25.8}
}

-- The movie turns radar pixels into its own coordinates: x = n * 110 + 10 and y = n * 110 - 3.5, with n over the 94 pixels
-- of the radar's square; so the centre of the radar is at (65, 51.5) and one radar pixel is 110 / 94 movie pixels.
Radar.UNITS_PIXEL = 110 / 94
Radar.UNITS_CENTRE_X = 65
Radar.UNITS_CENTRE_Y = 51.5

-- The pulse of the alerted icons: the phase turns 3 radians a second and the alpha is cos * 0.35 + 0.65 (30 to 100 %).
Radar.PULSE_SPEED = 3
Radar.ALPHA = 85

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
-- marker, big}: {id, x, y, rotation, frame, scale, alpha}, in the movie's coordinates. A unit outside the frame or more
-- than 500 m above or below is left out, except a marker (the unit that hurt the player), which is put on the border of
-- the frame. `phase` is the pulse of the alerted icons.
function Radar.Contacts(pos, yaw, contacts, phase)
	local list = {}

	if not contacts or not pos or not (yaw == yaw) then
		return list
	end

	local radians = math.rad(yaw)
	local cos, sin = math.cos(radians), math.sin(radians)
	local pixels = S.METRES_PER_UNIT * S.PIXELS / S.RANGE
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
				list[#list + 1] = {
					id = c.id,
					x = Radar.UNITS_CENTRE_X + x * Radar.UNITS_PIXEL,
					y = Radar.UNITS_CENTRE_Y + y * Radar.UNITS_PIXEL,
					rotation = (yaw - c.yaw + 180) % 360,
					frame = c.type * 5 + c.sub,
					scale = sizeFor(dz * S.METRES_PER_UNIT, c.big),
					alpha = (c.sub >= 3 and not c.marker) and pulse or Radar.ALPHA
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
			l.yaw = ent:GetAngles().y
		end
	end

	for i = count + 1, #live do
		live[i] = nil
	end

	return live
end

-- Whether the client wants the contacts: the HUD fed the radar within the last moments and its switches are on.
local lastFeed = -1000
local wanted

local function wantsContacts()
	local options = GryMod.HUDOptions

	return RealTime() - lastFeed < 1.5 and (not options or (options.Enabled("radar") and options.Enabled("radarunits")))
end

local function tellServer()
	local want = wantsContacts()

	if want ~= wanted then
		wanted = want
		net.Start("gry_radar_want")
		net.WriteBool(want)
		net.SendToServer()
	end
end

timer.Create("GryMod radar want", 1, 0, tellServer)

-- Each frame the HUD draws: the phase of the pulse, the contacts of the server placed for this frame.
local phase = 0

function Radar.Feed(panel, ply, dt)
	lastFeed = RealTime()
	phase = (phase + dt * Radar.PULSE_SPEED) % (2 * math.pi)

	-- off to on at once (the timer notices the other way within a second)
	if not wanted then
		tellServer()
	end

	local options = GryMod.HUDOptions

	if options and not options.Enabled("radarunits") or not wanted then
		panel:SetObjects({})

		return
	end

	panel:SetObjects(Radar.Contacts(ply:GetPos(), ply:EyeAngles().y, Radar.Live(), phase))
end
