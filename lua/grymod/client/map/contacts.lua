-- The NPC contacts on the big map (GryMod.Map.Contacts): the units the minimap and the compass radar show (the soldiers, the creatures, the vehicles, the team mates
-- and the unit that hurt the player), drawn on the big map the same way. NOTHING is made twice:
--   * the contacts are the radar's (GryMod.FlashRadar.Live: the list the server sends to the radar, with the position and the facing of each unit read from the entity
--     when this client has it). The map asks the server for nothing; what the radar knows is what the map shows (the radar's range, not the whole map);
--   * the look of a contact (the icon of the movie, its size, its alpha, its tint) is the radar's own function, GryMod.FlashRadar.ContactStyle, and the turn of the icon
--     and the pulse of an alert are Radar.Rotation and Radar.Pulse;
--   * the icons are the movie's own clips: a second panel of the radar movie (Radar.New) is kept apart from the HUD's and its Units clip is given the icons by the same
--     Panel:SetObjects the HUD's radar uses (the clips are made once, kept, hidden when they are not needed), and drawn alone with the Flash drawer.
-- Only the PLACE is the map's: the world position through the view of the big map (the map is not turned: up is +X). The icons are drawn after the window's scissor is lifted
-- (a group drawn with a blend mode uses a render target, which the scissor would cut), so an icon is only kept when it is wholly inside the window (Entries' margin).
-- The switch is gry_map_contacts. Nothing runs while the map is closed.

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}
GryMod.Map.Contacts = GryMod.Map.Contacts or {}

local C = GryMod.Map.Contacts

C.BASE_SCALE = 1.4 -- screen pixels for one pixel of the movie's icons at 1080p (the icon's size in percent is the radar's own)
C.EDGE = 10 -- pixels (at 1080p): an icon nearer to the edge of the window than this is not drawn (it would be cut by the frame)
C.BACK_RADIUS = 5 -- pixels of the movie: the radius of the dark disc under an icon of the usual size (62.5 percent); a bigger icon has a bigger disc
C.BACK_COLOUR = Color(0, 0, 0, 120)

local floor = math.floor

local function finite(n)
	return type(n) == "number" and n - n == 0
end

function C.Enabled()
	local Settings = GryMod.Map.Settings

	if Settings and Settings.Contacts then
		return Settings.Contacts()
	end

	return true
end

-- The size of the movie's pixel on the screen.
function C.Scale(uiScale)
	return C.BASE_SCALE * (uiScale or 1)
end

local none = {}

-- The radar's contacts (Radar.Live()), or an empty list when there is no radar. The server sends a list when it CHANGES (and an empty one once when the contacts end,
-- also when the client stops asking for them), so the last list is the truth whatever its age: the positions are read from the entities every frame.
function C.Current()
	local Radar = GryMod.FlashRadar

	if not Radar or not Radar.Live then
		return none
	end

	return Radar.Live()
end

-- The entries for the radar panel's SetObjects, in `out` (reused, the tail cleared), and how many: for each contact of `contacts` {id, x, y, z, yaw, type, sub, marker,
-- big} that is wholly inside the window of `view` (at least `margin` pixels from its edges), within 500 m of the height of the player (`playerZ`) and with a usable
-- position, {id, x, y, rotation, frame, scale, alpha, tint}: the radar's own look and a place in the units of the clip, that is the screen pixel over the draw scale `k`.
function C.Entries(view, contacts, playerZ, phase, k, margin, out)
	local Radar, S, Frame = GryMod.FlashRadar, GryMod.RadarShared, GryMod.Map.Frame
	local pulse = Radar.Pulse(phase)
	local x0, y0, x1, y1 = view.x + margin, view.y + margin, view.x + view.w - margin, view.y + view.h - margin
	local count = 0

	for i = 1, math.min(#contacts, S.MAX_CONTACTS) do
		local c = contacts[i]
		local dz = c.z - playerZ

		if finite(dz) and math.abs(dz) * S.METRES_PER_UNIT <= S.HEIGHT_LIMIT and finite(c.x) and finite(c.y) and finite(c.yaw) then
			local sx, sy = Frame.ToScreen(view, c.x, c.y)

			if sx >= x0 and sx <= x1 and sy >= y0 and sy <= y1 then
				count = count + 1

				local e = out[count]

				if not e then
					e = {}
					out[count] = e
				end

				e.id, e.x, e.y = c.id, sx / k, sy / k
				e.rotation = Radar.Rotation(0, c.yaw)
				e.frame, e.scale, e.alpha, e.tint = Radar.ContactStyle(c, dz * S.METRES_PER_UNIT, pulse)
			end
		end
	end

	for i = #out, count + 1, -1 do
		out[i] = nil
	end

	return out, count
end

-- the panel and its Units clip: made when the map first draws a contact, kept until Release -----------------------------------------------------------------------------

local panel, units
local failed = false
local entries = {}

local function ensure()
	if units then
		return units
	end

	if failed then
		return nil
	end

	local Flash, Radar = GryMod.Flash, GryMod.FlashRadar
	local movie = Flash and Radar and Radar.New and Flash.Load(Radar.MOVIE)
	local made = movie and Radar.New(movie)
	local clip = made and made.main and made.main:Child("Units")

	if not clip then
		if made and made.Release then
			made:Release()
		end

		failed = true

		return nil
	end

	-- the movie keeps a template of the icon in the Units clip (the radar's script never shows it): only the copies are the contacts
	local template = clip:Child("ObjectIcon")

	if template then
		template:SetVisible(false)
	end

	panel, units = made, clip

	return units
end

-- Gives back the panel's images (the tests, a reload).
function C.Release()
	if panel and panel.Release then
		pcall(panel.Release, panel)
	end

	panel, units, failed = nil, nil, false
end

-- Draws the contacts on the big map's window `view`, for the player `ply` (a screen of 1080 pixels high is uiScale 1). Returns how many icons were drawn: 0 when the
-- switch is off, when the radar has nothing fresh, or when nothing is inside the window.
function C.Draw(view, ply, uiScale)
	if not C.Enabled() then
		return 0
	end

	local contacts = C.Current()

	if #contacts == 0 then
		return 0
	end

	local clip = ensure()

	if not clip then
		return 0
	end

	local Radar = GryMod.FlashRadar
	local k = C.Scale(uiScale)
	local list, count = C.Entries(view, contacts, ply:GetPos().z, RealTime() * Radar.PULSE_SPEED, k, floor(C.EDGE * (uiScale or 1)), entries)

	-- the icons of the units that left are hidden by SetObjects, the others are given their place
	panel:SetObjects(list)

	if count > 0 then
		-- the icons are blended with add (the radar's, on its dark glass): over the map's light tiles a light icon would vanish, so each has a dark disc under it
		for i = 1, count do
			local e = list[i]
			local radius = math.ceil(C.BACK_RADIUS * k * e.scale / 62.5)

			draw.RoundedBox(radius, e.x * k - radius, e.y * k - radius, radius * 2, radius * 2, C.BACK_COLOUR)
		end

		GryMod.Flash.Draw(clip, 0, 0, k)
	end

	return count
end
