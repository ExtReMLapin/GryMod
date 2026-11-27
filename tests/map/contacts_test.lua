-- Tests of the NPC contacts on the big map (GryMod.Map.Contacts, lua/grymod/client/map/contacts.lua), GLuaTest format, client realm. The big map shows the same
-- contacts as the minimap and the compass radar, with the same icons: the units the server sends to the radar (GryMod.FlashRadar.Live), the look of each from the
-- radar's own function (ContactStyle, Pulse, Rotation) and the movie's own icon clips (the radar panel's SetObjects). Only the PLACE of an icon is the map's: the world
-- position through the view of the big map. This file checks that place, the culling at the edge of the window, the switch, the age of the contacts and one real
-- drawing (the real icon clips, the Flash drawer replaced by a recorder). Every stand-in and convar is put back in afterEach inside a pcall.
-- Each case names the change whose absence makes it fail.

local C, R, Frame, S
local saved

local function view()
	local v = Frame.New({x = 100, y = 50, w = 800, h = 600}, {x0 = -4000, x1 = 4000, y0 = -4000, y1 = 4000})

	Frame.SetZoom(v, 2)
	Frame.CentreOn(v, 0, 0)

	return v
end

local function contact(x, y, extra)
	local c = {id = 1, x = x, y = y, z = 0, yaw = 0, type = 1, sub = 2}

	for k, v in pairs(extra or {}) do
		c[k] = v
	end

	return c
end

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

return {
	groupName = "GryMod big map: NPC contacts",
	beforeEach = function()
		C, R, Frame, S = GryMod.Map.Contacts, GryMod.FlashRadar, GryMod.Map.Frame, GryMod.RadarShared
		expect(C ~= nil).to.beTrue()
		saved = {}
		saved.convar = GetConVar("gry_map_contacts"):GetString()
		GetConVar("gry_map_contacts"):SetString("1")
	end,
	afterEach = function()
		pcall(function()
			for i = #saved, 1, -1 do
				local entry = saved[i]

				entry[1][entry[2]] = entry[3]
			end

			GetConVar("gry_map_contacts"):SetString(saved.convar)
			C.Release()
		end)
	end,
	cases = {
		{
			-- fails when the icon is not where the world position is in the view (a unit at the other side of the map), or its place is not in the clip's own units
			-- (the draw scale k turns them into pixels)
			name = "Entries: an icon is at the screen place of the contact's world position (in the units of the clip: pixels over the draw scale)",
			func = function()
				local v = view()
				local k = 1.5
				local list, count = C.Entries(v, {contact(0, 0), contact(400, -300, {id = 2})}, 0, 0, k, 0, {})

				expect(count).to.equal(2)

				local sx, sy = Frame.ToScreen(v, 0, 0)

				expect(list[1].x * k).to.aboutEqual(sx, 1e-6)
				expect(list[1].y * k).to.aboutEqual(sy, 1e-6)
				expect(list[1].id).to.equal(1)

				sx, sy = Frame.ToScreen(v, 400, -300)
				expect(list[2].x * k).to.aboutEqual(sx, 1e-6)
				expect(list[2].y * k).to.aboutEqual(sy, 1e-6)
				expect(list[2].id).to.equal(2)
			end
		},
		{
			-- fails when the look is computed here and not by the radar's ContactStyle (the two would drift), or the turn is the radar's (the map is not turned: up is +X)
			name = "Entries: the frame, the size, the alpha and the tint are the radar's (ContactStyle), the icon turns with the unit's yaw on a map that is not turned",
			func = function()
				local v = view()
				local phase = 1.2
				local ally = contact(0, 0, {sub = S.SUB_ALLY, type = 3, yaw = 90, z = 20 / S.METRES_PER_UNIT})
				local alert = contact(100, 0, {sub = 4, yaw = 0, id = 2})
				local list = C.Entries(v, {ally, alert}, 0, phase, 1, 0, {})

				local frame, scale, alpha, tint = R.ContactStyle(ally, 20, R.Pulse(phase))

				expect(list[1].frame).to.equal(frame)
				expect(list[1].scale).to.equal(scale)
				expect(list[1].alpha).to.equal(alpha)
				expect(list[1].tint).to.equal(tint)
				expect(list[1].rotation).to.equal(R.Rotation(0, 90))

				expect(list[2].alpha).to.aboutEqual(R.Pulse(phase), 1e-9)
				expect(list[2].rotation).to.equal(180)
				expect(list[2].tint).to.beNil()
			end
		},
		{
			-- fails when the height is taken from the world and not from the player (the radar's size grows and shrinks with the height over the player)
			name = "Entries: the size follows the height of the contact above the player",
			func = function()
				local v = view()
				local up = 30 / S.METRES_PER_UNIT
				local at = C.Entries(v, {contact(0, 0, {z = 1000 + up})}, 1000, 0, 1, 0, {})
				local same = C.Entries(v, {contact(0, 0, {z = 1000})}, 1000, 0, 1, 0, {})

				expect(at[1].scale).to.equal(R.SizeFor(30, nil))
				expect(same[1].scale).to.equal(R.SizeFor(0, nil))
			end
		},
		{
			-- fails when an icon outside the window is kept (it would be drawn over the frame of the map: the nested drawing is not clipped), or one that is too near the edge
			name = "Entries: a contact outside the window, or nearer to its edge than the margin, is left out; nothing is drawn from a bad number or half a kilometre of height",
			func = function()
				local v = view()
				local sxEdge = v.x + v.w
				local list, count = C.Entries(v, {
					contact(0, 0),
					contact(0, -100000, {id = 2}), -- far to the right of the window
					contact(100000, 0, {id = 3}), -- far above it
					contact(0 / 0, 0, {id = 4}),
					contact(0, 0, {id = 5, z = 600 / S.METRES_PER_UNIT})
				}, 0, 0, 1, 10, {})

				expect(count).to.equal(1)
				expect(list[1].id).to.equal(1)

				-- the margin: a contact whose centre is 5 pixels inside the right edge is out with a margin of 10, in with 4
				local nearY = v.cy - (sxEdge - 5 - (v.x + v.w / 2)) / (v.k1 * v.zoom)

				expect(select(2, C.Entries(v, {contact(0, nearY)}, 0, 0, 1, 10, {}))).to.equal(0)
				expect(select(2, C.Entries(v, {contact(0, nearY)}, 0, 0, 1, 4, {}))).to.equal(1)
			end
		},
		{
			-- fails when the list is not cleared past the new count (an icon of a unit that left would stay), or a new table is made at every call
			name = "Entries: the list and its entries are reused between calls, the tail is cleared",
			func = function()
				local v = view()
				local out = {}
				local list = C.Entries(v, {contact(0, 0), contact(10, 0, {id = 2}), contact(20, 0, {id = 3})}, 0, 0, 1, 0, out)

				expect(list).to.equal(out)
				expect(#list).to.equal(3)

				local first = list[1]

				list = C.Entries(v, {contact(5, 0, {id = 9})}, 0, 0, 1, 0, out)
				expect(#list).to.equal(1)
				expect(list[1]).to.equal(first)
				expect(list[1].id).to.equal(9)
			end
		},
		{
			-- fails when the switch does not stop the contacts, or its default is not on
			name = "the switch gry_map_contacts: on by default, 0 draws nothing",
			func = function()
				expect(C.Enabled()).to.beTrue()
				GetConVar("gry_map_contacts"):SetString("0")
				expect(C.Enabled()).to.beFalse()
				GetConVar("gry_map_contacts"):SetString("1")
				expect(C.Enabled()).to.beTrue()
			end
		},
		{
			-- fails when the contacts are not the radar's own list (the map would need its own request to the server), or an old list is thrown away (the server sends a list
			-- when it changes: a unit that stands still is not sent again, and must stay on the map)
			name = "Current: the radar's list as it is, however old (the server only sends a change), an empty one without a radar",
			func = function()
				stub(R, "Live", function() return {contact(0, 0)} end)
				stub(R, "SnapshotTime", RealTime() - 3600)
				expect(#C.Current()).to.equal(1)

				R.Live = nil
				expect(#C.Current()).to.equal(0)
			end
		},
		{
			-- fails when the icons are drawn on the bare tiles (the radar's blend add makes a white or a light icon vanish over a light roof or a pale road), or the backing
			-- is not under the icon it belongs to, or is drawn after the icons (it would hide them)
			name = "Draw: a dark disc under each icon, centred on it and drawn before the icons (they are blended with add and would vanish over light tiles)",
			func = function()
				local v = view()
				local ply = {GetPos = function() return Vector(0, 0, 0) end}
				local order = {}

				stub(R, "Live", function() return {contact(0, 0), contact(100, 100, {id = 2, type = R.MATE_TYPE, sub = 0})} end)
				stub(draw, "RoundedBox", function(radius, x, y, w, h, colour) order[#order + 1] = {"box", radius, x, y, w, h, colour} end)
				stub(GryMod.Flash, "Draw", function() order[#order + 1] = {"flash"} return true end)

				expect(C.Draw(v, ply, 1)).to.equal(2)
				expect(#order).to.equal(3)
				expect(order[1][1]).to.equal("box")
				expect(order[2][1]).to.equal("box")
				expect(order[3][1]).to.equal("flash")

				for i = 1, 2 do
					local b = order[i]
					local sx, sy = Frame.ToScreen(v, i == 1 and 0 or 100, i == 1 and 0 or 100)

					expect(b[3] + b[5] / 2).to.aboutEqual(sx, 1e-6)
					expect(b[4] + b[6] / 2).to.aboutEqual(sy, 1e-6)
					expect(b[5]).to.equal(b[6])
					expect(b[7].r < 40 and b[7].g < 40 and b[7].b < 40).to.beTrue()
					expect(b[7].a > 0 and b[7].a < 255).to.beTrue()
				end

				-- a team mate's icon is four times the size: its disc is bigger
				expect(order[2][5] > order[1][5]).to.beTrue()
			end
		},
		{
			-- fails when the map draws its own icons (not the movie's through the radar panel's SetObjects), draws with the switch off, or draws outside the map's window
			name = "Draw: the real icon clips are given the entries and drawn once at the map's scale; the switch off or no contact draw nothing",
			func = function()
				local v = view()
				local ply = {GetPos = function() return Vector(0, 0, 0) end}
				local drawn = {}

				stub(R, "Live", function() return {contact(0, 0), contact(100, 100, {id = 2, sub = S.SUB_ALLY})} end)
				stub(GryMod.Flash, "Draw", function(clip, x, y, scale) drawn[#drawn + 1] = {clip = clip, x = x, y = y, scale = scale} return true end)

				expect(C.Draw(v, ply, 1)).to.equal(2)
				expect(#drawn).to.equal(1)
				expect(drawn[1].scale > 0).to.beTrue()

				-- the clip drawn is the movie's own Units clip, with two visible icons that show the contacts' frames
				local units = drawn[1].clip

				expect(units ~= nil).to.beTrue()
				expect(units:Child("ObjectIcon_100").visible).to.beTrue()
				expect(units:Child("ObjectIcon_101").visible).to.beTrue()
				-- the radar's own icons: blended with add, as the movie says
				expect(units:Child("ObjectIcon_100").entry.blend).to.equal(8)
				expect(units:Child("ObjectIcon_100"):Child("Icon"):CurrentFrame()).to.equal(7)
				expect(units:Child("ObjectIcon_101"):Child("Icon"):CurrentFrame()).to.equal(5)

				-- the template the movie's script keeps is not seen
				local template = units:Child("ObjectIcon")

				expect(template == nil or template.visible == false).to.beTrue()

				drawn = {}
				GetConVar("gry_map_contacts"):SetString("0")
				expect(C.Draw(v, ply, 1)).to.equal(0)
				expect(#drawn).to.equal(0)

				GetConVar("gry_map_contacts"):SetString("1")
				R.Live = function() return {} end
				expect(C.Draw(v, ply, 1)).to.equal(0)
			end
		}
	}
}
