-- Tests of the contacts on the radar (the Units clip of the original movie), GLuaTest format, client realm. The original
-- rules (CHUDRadar::Update) are in docs/superpowers/plans/2026-11-21-radar-research.md. Needs the converted movie
-- lua/grymod/flash/hud_radarcompassstealth.lua.

local function newPanel()
	return GryMod.FlashRadar.New(GryMod.Flash.Load("hud_radarcompassstealth"))
end

local U = 0.01905 -- metres per Source unit, so that a metre is 52.5 units

local function metres(m)
	return m / U
end

-- a contact `ahead` metres in front of a player at the origin looking along +x, `right` metres to his right
local function contact(ahead, right, extra)
	local c = {id = 1, x = ahead and metres(ahead) or 0, y = right and -metres(right) or 0, z = 0, yaw = 0, type = 1, sub = 4}

	for k, v in pairs(extra or {}) do
		c[k] = v
	end

	return c
end

local PX = 110 / 94 -- movie pixels per radar pixel: x = n * 110 + 10 with n over 94 pixels

-- The centre of the radar in the Units clip: where the player is, on the movie's own vertical line and at the middle of the cone. MEASURED on
-- two screenshots of the game (the line and the cone's base against icons whose movie coordinates were known): (64.1, 52.3), not the (65, 51.5)
-- that the original script's arithmetic gives (x * 110 + 10, y * 110 - 3.5 with the radar's square 94 pixels wide): about 1 pixel of the film
-- to the right and 0.8 above, visible as a unit straight ahead that is off the line.
local CX, CY = 64.1, 52.3

local function one(contacts, plyYaw, phase)
	local list = GryMod.FlashRadar.Contacts(Vector(0, 0, 0), plyYaw or 0, contacts, phase or 0)

	return list[1], list
end

return {
	groupName = "GryMod radar contacts (Flash)",
	cases = {
		{
			name = "the radar is heading up: a unit straight ahead is above the centre, one to the right is right of it",
			func = function(state)
				-- 37.5 m is half the radius: 21.5 radar pixels
				local e = one({contact(37.5, 0)})
				expect(e).toNot.beNil()
				expect(e.x).to.aboutEqual(CX, 0.01)
				expect(e.y).to.aboutEqual(CY - 21.5 * PX, 0.01)

				e = one({contact(0, 37.5)})
				expect(e.x).to.aboutEqual(CX + 21.5 * PX, 0.01)
				expect(e.y).to.aboutEqual(CY, 0.01)

				e = one({contact(-37.5, 0)})
				expect(e.x).to.aboutEqual(CX, 0.01)
				expect(e.y).to.aboutEqual(CY + 21.5 * PX, 0.01)
			end
		},
		{
			name = "turning the player turns the radar: yaw 90 looks along +y",
			func = function(state)
				local e = one({{id = 1, x = 0, y = metres(37.5), z = 0, yaw = 90, type = 1, sub = 4}}, 90)
				expect(e.x).to.aboutEqual(CX, 0.01)
				expect(e.y).to.aboutEqual(CY - 21.5 * PX, 0.01)

				-- a unit at the player's right after the turn is at -x
				e = one({{id = 1, x = metres(37.5), y = 0, z = 0, yaw = 0, type = 1, sub = 4}}, 90)
				expect(e.x).to.aboutEqual(CX + 21.5 * PX, 0.01)
			end
		},
		{
			name = "the icon frame is the type times 5 plus the subtype",
			func = function(state)
				expect((one({contact(10, 0, {type = 1, sub = 0})})).frame).to.equal(5)
				expect((one({contact(10, 0, {type = 1, sub = 4})})).frame).to.equal(9)
				expect((one({contact(10, 0, {type = 2, sub = 3})})).frame).to.equal(13)
				expect((one({contact(10, 0, {type = 3, sub = 4})})).frame).to.equal(19)
			end
		},
		{
			name = "an ally is drawn with the calm still image of its type, tinted blue, at the calm alpha and never pulsing",
			func = function(state)
				local S = GryMod.RadarShared
				local e = one({contact(10, 0, {type = 1, sub = S.SUB_ALLY})}, 0, math.pi)
				expect(e.frame).to.equal(5) -- the sub 0 image of the ground type
				expect(e.alpha).to.aboutEqual(85, 0.01) -- sub 5 is past 3, but it does not pulse
				expect(e.tint).toNot.beNil()
				-- blue: the blue is the strongest and the red the weakest
				expect(e.tint[3] > e.tint[2]).to.beTrue()
				expect(e.tint[2] > e.tint[1]).to.beTrue()
				expect((one({contact(10, 0, {type = 2, sub = S.SUB_ALLY})})).frame).to.equal(10)
				expect((one({contact(10, 0, {type = 3, sub = S.SUB_ALLY})})).frame).to.equal(15)
				-- a marker of an ally does not pulse either
				expect((one({contact(10, 0, {sub = S.SUB_ALLY, marker = true})}, 0, math.pi)).alpha).to.aboutEqual(85, 0.01)
				-- the other subtypes have no tint
				for sub = 0, 4 do
					expect((one({contact(10, 0, {sub = sub})})).tint).to.beNil()
				end
			end
		},
		{
			name = "an icon takes the ally tint and loses it when it shows something else, the alpha of the pulse keeps working",
			func = function(state)
				local panel = newPanel()
				local R = GryMod.FlashRadar
				local S = GryMod.RadarShared
				panel:SetObjects(R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0, {sub = S.SUB_ALLY})}, 0))
				local icon = panel.main:Child("Units"):Child("ObjectIcon_100")
				local cx = icon.entry.cx
				expect(cx).toNot.beNil()
				expect(cx[3] > cx[1]).to.beTrue()
				expect(cx[4]).to.aboutEqual(0.85, 0.001)
				expect(icon:Child("Icon"):CurrentFrame()).to.equal(5)
				-- the same icon now a hostile that fights: no tint, the movie's own colours (multipliers 1)
				panel:SetObjects(R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0, {sub = 4})}, math.pi))
				cx = icon.entry.cx
				expect(cx[1]).to.aboutEqual(1, 0.001)
				expect(cx[2]).to.aboutEqual(1, 0.001)
				expect(cx[3]).to.aboutEqual(1, 0.001)
				expect(cx[4]).to.aboutEqual(0.3, 0.001)
				expect(icon:Child("Icon"):CurrentFrame()).to.equal(9)
				-- and an ally again
				panel:SetObjects(R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0, {sub = S.SUB_ALLY})}, 0))
				expect(icon.entry.cx[3] > icon.entry.cx[1]).to.beTrue()
			end
		},
		{
			name = "the visible area is the glass of the movie (Radar.FRAME), not a disc and not the original's smaller polygon",
			func = function(state)
				-- at 75 m the glass is 45.95 pixels ahead = 80.1 m, 49.5 behind = 86.4 m, 77.4 to the left = 135 m, 70.8 to the right = 123.5 m
				expect(one({contact(78, 0)})).toNot.beNil()
				expect(one({contact(83, 0)})).to.beNil()
				expect(one({contact(-84, 0)})).toNot.beNil()
				expect(one({contact(-89, 0)})).to.beNil()
				expect(one({contact(0, -132)})).toNot.beNil()
				expect(one({contact(0, -138)})).to.beNil()
				expect(one({contact(0, 121)})).toNot.beNil()
				expect(one({contact(0, 126)})).to.beNil()
				-- what the original's polygon (Radar.ORIGINAL_FRAME) dropped is still there: 76 m ahead, 81 m behind, 104 m to the left, 111 m to the right
				expect(one({contact(76, 0)})).toNot.beNil()
				expect(one({contact(-81, 0)})).toNot.beNil()
				expect(one({contact(0, -104)})).toNot.beNil()
				expect(one({contact(0, 111)})).toNot.beNil()
				-- the lower right corner is cut: (60 px, 40 px behind) is in, (70 px, 40 px behind) is out
				expect(one({contact(-40 * 75 / 43, 60 * 75 / 43)})).toNot.beNil()
				expect(one({contact(-40 * 75 / 43, 70 * 75 / 43)})).to.beNil()
			end
		},
		{
			name = "a unit more than 500 m above or below is dropped",
			func = function(state)
				expect(one({contact(10, 0, {z = metres(499)})})).toNot.beNil()
				expect(one({contact(10, 0, {z = metres(501)})})).to.beNil()
				expect(one({contact(10, 0, {z = -metres(501)})})).to.beNil()
			end
		},
		{
			name = "the icon is bigger the higher the unit is, between 32.5 % below and 62.5 % above 15 m of difference",
			func = function(state)
				expect((one({contact(10, 0, {z = -metres(20)})})).scale).to.aboutEqual(32.5, 0.01)
				expect((one({contact(10, 0, {z = metres(20)})})).scale).to.aboutEqual(62.5, 0.01)
				expect((one({contact(10, 0, {z = 0})})).scale).to.aboutEqual(47.5, 0.01)
				expect((one({contact(10, 0, {z = metres(7.5)})})).scale).to.aboutEqual(55, 0.01)
				-- the big ones (the original's Hunter) are doubled
				expect((one({contact(10, 0, {z = 0, big = true})})).scale).to.aboutEqual(95, 0.01)
			end
		},
		{
			name = "the icon points where the unit faces, relative to the player (the same way is up)",
			func = function(state)
				expect((one({contact(10, 0, {yaw = 0})})).rotation).to.aboutEqual(180, 0.01)
				expect((one({contact(10, 0, {yaw = 90})})).rotation).to.aboutEqual(90, 0.01) -- turned left: counter clockwise
				expect((one({contact(10, 0, {yaw = -90})})).rotation).to.aboutEqual(270, 0.01)
				expect((one({contact(10, 0, {yaw = 180})})).rotation).to.aboutEqual(0, 0.01)
				-- the player turned too: still relative
				expect((one({contact(10, 0, {yaw = 90, x = 0, y = metres(10)})}, 90)).rotation).to.aboutEqual(180, 0.01)
			end
		},
		{
			name = "the alert levels pulse between 30 % and 100 % and the others are at 85 %",
			func = function(state)
				expect((one({contact(10, 0, {sub = 4})}, 0, 0)).alpha).to.aboutEqual(100, 0.01)
				expect((one({contact(10, 0, {sub = 3})}, 0, math.pi)).alpha).to.aboutEqual(30, 0.01)
				expect((one({contact(10, 0, {sub = 4})}, 0, math.pi / 2)).alpha).to.aboutEqual(65, 0.01)
				expect((one({contact(10, 0, {sub = 2})}, 0, 0)).alpha).to.aboutEqual(85, 0.01)
				expect((one({contact(10, 0, {sub = 0})}, 0, 1)).alpha).to.aboutEqual(85, 0.01)
				expect((one({contact(10, 0, {sub = 4, marker = true})}, 0, math.pi)).alpha).to.aboutEqual(85, 0.01)
			end
		},
		{
			name = "a shooter marker outside the glass sits on its border, in the same direction",
			func = function(state)
				local e = one({contact(300, 0, {marker = true, sub = 2})})
				expect(e).toNot.beNil()
				expect(e.x).to.aboutEqual(CX, 0.05)
				expect(e.y).to.aboutEqual(CY - 45.95 * PX, 0.05)

				-- far to the right: the right edge (70.8 pixels)
				e = one({contact(0, 400, {marker = true})})
				expect(e.x).to.aboutEqual(CX + 70.8 * PX, 0.05)
				expect(e.y).to.aboutEqual(CY, 0.05)

				-- diagonal ahead left: on the border, still up and left
				e = one({contact(400, -400, {marker = true})})
				expect(e.x < CX).to.beTrue()
				expect(e.y < CY).to.beTrue()
				expect(e.x >= CX - 77.38 * PX - 0.05).to.beTrue()
				expect(e.y >= CY - 45.95 * PX - 0.05).to.beTrue()
			end
		},
		{
			name = "the entries come with the id of the contact, in the given order, no more than the limit",
			func = function(state)
				local contacts = {}

				for i = 1, 100 do
					contacts[i] = contact(5, 0, {id = i})
				end

				local _, list = one(contacts)
				expect(#list).to.equal(GryMod.RadarShared.MAX_CONTACTS)
				expect(list[1].id).to.equal(1)
				expect(list[2].id).to.equal(2)
			end
		},
		{
			name = "nothing, nil and bad numbers give an empty list, not an error",
			func = function(state)
				expect(#GryMod.FlashRadar.Contacts(Vector(0, 0, 0), 0, {}, 0)).to.equal(0)
				expect(#GryMod.FlashRadar.Contacts(Vector(0, 0, 0), 0, nil, 0)).to.equal(0)
				expect(#GryMod.FlashRadar.Contacts(Vector(0, 0, 0), 0 / 0, {contact(10, 0)}, 0)).to.equal(0)
				expect(#GryMod.FlashRadar.Contacts(Vector(0, 0, 0), 0, {contact(10, 0, {x = 0 / 0})}, 0)).to.equal(0)
			end
		},
		{
			name = "the panel makes one icon per contact in the Units clip, the way the movie's script does",
			func = function(state)
				local panel = newPanel()
				local units = panel.main:Child("Units")
				local before = units:ChildCount()
				panel:SetObjects(GryMod.FlashRadar.Contacts(Vector(0, 0, 0), 0, {contact(10, 0, {id = 1}), contact(20, 5, {id = 2, sub = 3, type = 2})}, 0))
				expect(units:ChildCount()).to.equal(before + 2)
				local first = units:Child("ObjectIcon_100")
				local second = units:Child("ObjectIcon_101")
				expect(first).toNot.beNil()
				expect(second).toNot.beNil()
				expect(first.visible).to.beTrue()
				expect(first:Child("Icon"):CurrentFrame()).to.equal(9)
				expect(second:Child("Icon"):CurrentFrame()).to.equal(13)
				-- the movie's own icon (the original of the copies) is left alone
				expect(units:Child("ObjectIcon")).toNot.beNil()
				expect(units:Child("ObjectIcon"):Child("Icon"):CurrentFrame()).to.equal(1)
				-- the copies are blended with add (the movie sets blendMode = 8)
				expect(first.entry.blend).to.equal(8)
			end
		},
		{
			name = "the icons are placed with the movie's formulas and their position, turn, size and alpha follow",
			func = function(state)
				local panel = newPanel()
				local list = GryMod.FlashRadar.Contacts(Vector(0, 0, 0), 0, {contact(37.5, 0, {yaw = 90, z = metres(20)})}, 0)
				panel:SetObjects(list)
				local icon = panel.main:Child("Units"):Child("ObjectIcon_100")
				expect(icon.entry.m[5]).to.aboutEqual(list[1].x, 0.001)
				expect(icon.entry.m[6]).to.aboutEqual(list[1].y, 0.001)
				-- rotation 90 degrees: a = cos, b = sin of the angle, scaled by 62.5 %
				expect(icon.entry.m[1]).to.aboutEqual(0, 0.001)
				expect(icon.entry.m[2]).to.aboutEqual(0.625, 0.001)
				expect(icon.entry.cx and icon.entry.cx[4] or 1).to.aboutEqual(1, 0.001) -- sub 4 at phase 0: 100 % (no transform is the same)
				panel:SetObjects(GryMod.FlashRadar.Contacts(Vector(0, 0, 0), 0, {contact(37.5, 0, {sub = 4})}, math.pi))
				expect(icon.entry.cx[4]).to.aboutEqual(0.3, 0.001) -- the low end of the pulse
			end
		},
		{
			name = "a smaller list hides the extra icons, a bigger one brings them back without making new ones",
			func = function(state)
				local panel = newPanel()
				local units = panel.main:Child("Units")
				local R = GryMod.FlashRadar
				panel:SetObjects(R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0, {id = 1}), contact(20, 0, {id = 2}), contact(30, 0, {id = 3})}, 0))
				local count = units:ChildCount()
				local third = units:Child("ObjectIcon_102")
				expect(third.visible).to.beTrue()
				panel:SetObjects(R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0, {id = 1})}, 0))
				expect(units:ChildCount()).to.equal(count)
				expect(units:Child("ObjectIcon_100").visible).to.beTrue()
				expect(units:Child("ObjectIcon_101").visible).to.beFalse()
				expect(third.visible).to.beFalse()
				panel:SetObjects({})
				expect(units:Child("ObjectIcon_100").visible).to.beFalse()
				panel:SetObjects(R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0), contact(20, 0), contact(30, 0)}, 0))
				expect(units:ChildCount()).to.equal(count)
				expect(third.visible).to.beTrue()
				expect(units:Child("ObjectIcon_102")).to.equal(third)
			end
		},
		{
			name = "an icon changes frame only when its icon changes, and a new frame is the one asked for",
			func = function(state)
				local panel = newPanel()
				local R = GryMod.FlashRadar
				panel:SetObjects(R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0, {sub = 2})}, 0))
				local icon = panel.main:Child("Units"):Child("ObjectIcon_100"):Child("Icon")
				expect(icon:CurrentFrame()).to.equal(7)
				panel:SetObjects(R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0, {sub = 4})}, 0))
				expect(icon:CurrentFrame()).to.equal(9)
				panel:SetObjects(R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0, {sub = 4, type = 3})}, 0))
				expect(icon:CurrentFrame()).to.equal(19)
			end
		},
		{
			name = "the units keep the dimming of a malfunction and the contacts survive the movie's own frame changes",
			func = function(state)
				local panel = newPanel()
				local R = GryMod.FlashRadar
				panel:SetObjects(R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0)}, 0))
				panel:Destroy(1)

				for _ = 1, 90 do panel:Update(1 / 30) end

				local units = panel.main:Child("Units")
				expect(math.abs(units.entry.cx[4] - 0.4) < 0.001).to.beTrue()
				panel:SetObjects(R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0)}, 0))
				expect(units:Child("ObjectIcon_100")).toNot.beNil()
				expect(units:Child("ObjectIcon_100").visible).to.beTrue()
				-- the dimming of the units is the noise's job: the icons do not touch it
				expect(math.abs(units.entry.cx[4] - 0.4) < 0.001).to.beTrue()
			end
		},
		{
			name = "the live facing of a vehicle is the way it faces, 90 degrees from its raw yaw (the client's forward vector does not say so: measured), not its yaw: the rectangle points where it drives",
			func = function(state)
				local R = GryMod.FlashRadar
				local realFind, realSnapshot = R.FindEntity, R.Snapshot
				local function ent(vehicle)
					return {IsValid = function() return true end, IsDormant = function() return false end, IsVehicle = function() return vehicle end,
						GetPos = function() return Vector(10, 20, 30) end, GetAngles = function() return Angle(0, 30, 0) end,
						-- (MEASURED on a real Buggy: on the CLIENT GetForward is the forward of the raw angles, 30 here; only the server's is
						-- the way the vehicle faces)
						GetForward = function() return Vector(math.cos(math.rad(30)), math.sin(math.rad(30)), 0) end}
				end
				local ents = {[7] = ent(true), [8] = ent(false)}
				R.FindEntity = function(id) return ents[id] end
				R.Snapshot = {
					{id = 7, x = 1, y = 1, z = 0, yaw = 0, type = 3, sub = 0, marker = false, big = false},
					{id = 8, x = 2, y = 2, z = 0, yaw = 0, type = 1, sub = 2, marker = false, big = false}
				}
				local ok, live = pcall(R.Live)
				R.FindEntity, R.Snapshot = realFind, realSnapshot
				assert(ok, live)
				expect(math.abs(math.AngleDifference(live[1].yaw, 120)) < 0.5).to.beTrue()
				expect(live[2].yaw).to.equal(30)
			end
		},
		{
			name = "the live contacts take the position and facing of the entity when the client has it, the server's otherwise",
			func = function(state)
				local R = GryMod.FlashRadar
				local realFind, realSnapshot = R.FindEntity, R.Snapshot
				local ents = {
					[7] = {IsValid = function() return true end, IsDormant = function() return false end,
						GetPos = function() return Vector(111, 222, 333) end, GetAngles = function() return Angle(0, 45, 0) end},
					[8] = {IsValid = function() return true end, IsDormant = function() return true end,
						GetPos = function() return Vector(1, 2, 3) end, GetAngles = function() return Angle(0, 9, 0) end}
				}
				R.FindEntity = function(id) return ents[id] end
				R.Snapshot = {
					{id = 7, x = 1000, y = 1000, z = 0, yaw = 0, type = 1, sub = 4, marker = false, big = false},
					{id = 8, x = 2000, y = 2000, z = 0, yaw = 90, type = 3, sub = 2, marker = true, big = true},
					{id = 9, x = 3000, y = 3000, z = 0, yaw = 180, type = 2, sub = 3, marker = false, big = false}
				}
				local ok, live = pcall(R.Live)
				R.FindEntity, R.Snapshot = realFind, realSnapshot
				assert(ok, live)
				expect(#live).to.equal(3)
				expect(live[1].x).to.equal(111)
				expect(live[1].z).to.equal(333)
				expect(live[1].yaw).to.equal(45)
				expect(live[2].x).to.equal(2000) -- dormant: the server's
				expect(live[2].yaw).to.equal(90)
				expect(live[2].marker).to.beTrue()
				expect(live[3].x).to.equal(3000) -- not on the client: the server's
				expect(live[3].type).to.equal(2)
			end
		},
		{
			name = "the HUD's feed places the server's contacts, nothing when the switch is off, and asks the server for them",
			func = function(state)
				local R = GryMod.FlashRadar
				local panel = newPanel()
				local options = GryMod.HUDOptions
				local realSnapshot, realFind, realEnabled = R.Snapshot, R.FindEntity, options.Enabled
				local sent = {}
				local real = {Start = net.Start, WriteBool = net.WriteBool, SendToServer = net.SendToServer}
				net.Start = function(name) sent[#sent + 1] = {name = name} end
				net.WriteBool = function(v) sent[#sent].value = v end
				net.SendToServer = function() end
				R.FindEntity = function() return nil end
				R.Snapshot = {{id = 7, x = metres(10), y = 0, z = 0, yaw = 0, type = 1, sub = 4, marker = false, big = false}}
				local ply = {GetPos = function() return Vector(0, 0, 0) end, EyeAngles = function() return Angle(0, 0, 0) end}
				local ok, err = pcall(function()
					options.Enabled = function() return true end
					R.Feed(panel, ply, 1 / 30)
					local units = panel.main:Child("Units")
					local icon = units:Child("ObjectIcon_100")
					expect(icon).toNot.beNil()
					expect(icon.visible).to.beTrue()
					expect(icon:Child("Icon"):CurrentFrame()).to.equal(9)

					options.Enabled = function(name) return name ~= "radarunits" end
					R.Feed(panel, ply, 1 / 30)
					expect(icon.visible).to.beFalse()
				end)
				R.Snapshot, R.FindEntity, options.Enabled = realSnapshot, realFind, realEnabled
				net.Start, net.WriteBool, net.SendToServer = real.Start, real.WriteBool, real.SendToServer
				assert(ok, err)
			end
		},
		{
			name = "after the movie rebuilds its Units clip the icons are made again in the new one",
			func = function(state)
				local panel = newPanel()
				local R = GryMod.FlashRadar
				panel:SetObjects(R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0)}, 0))
				panel.main:GotoAndStop("normal") -- the clips are rebuilt
				panel:Update(0)
				panel:SetObjects(R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0)}, 0))
				local units = panel.main:Child("Units")
				expect(units:Child("ObjectIcon_100")).toNot.beNil()
				expect(units:Child("ObjectIcon_100").visible).to.beTrue()
			end
		},
		{
			name = "the stealth target is the highest awareness of the hostile contacts: fighting 1, alerted 0.5, calm, friends and nothing 0",
			func = function(state)
				local R = GryMod.FlashRadar
				expect(R.StealthTarget(nil)).to.equal(0)
				expect(R.StealthTarget({})).to.equal(0)
				expect(R.StealthTarget({contact(10, 0, {sub = 4})})).to.equal(1)
				expect(R.StealthTarget({contact(10, 0, {sub = 3})})).to.equal(0.5)
				expect(R.StealthTarget({contact(10, 0, {sub = 2})})).to.equal(0) -- tagged, hostile, calm
				-- friends (tagged then turned friendly, or the marker of a non hostile): never
				expect(R.StealthTarget({contact(10, 0, {sub = 0}), contact(20, 0, {sub = 1, marker = true})})).to.equal(0)
				-- the highest wins, a crowd does not add up
				expect(R.StealthTarget({contact(10, 0, {sub = 3}), contact(20, 0, {sub = 3}), contact(30, 0, {sub = 3}), contact(40, 0, {sub = 2})})).to.equal(0.5)
				expect(R.StealthTarget({contact(10, 0, {sub = 3}), contact(20, 0, {sub = 4}), contact(30, 0, {sub = 0})})).to.equal(1)
				-- a hostile that shot the player (its marker) is aware of him
				expect(R.StealthTarget({contact(90, 0, {sub = 2, marker = true})})).to.equal(1)
			end
		},
		{
			name = "an ally never raises the stealth bar, whatever the other contacts are, its marker neither",
			func = function(state)
				local R = GryMod.FlashRadar
				local S = GryMod.RadarShared
				expect(R.Awareness({sub = S.SUB_ALLY, marker = false})).to.equal(0)
				expect(R.Awareness({sub = S.SUB_ALLY, marker = true})).to.equal(0)
				expect(R.StealthTarget({contact(10, 0, {sub = S.SUB_ALLY}), contact(20, 0, {sub = S.SUB_ALLY, marker = true})})).to.equal(0)
				-- next to a hostile, the bar still follows the hostile only
				expect(R.StealthTarget({contact(10, 0, {sub = S.SUB_ALLY}), contact(20, 0, {sub = 3})})).to.equal(0.5)
			end
		},
		{
			name = "the stealth level rises a second per unit and falls four times slower, never past the target",
			func = function(state)
				local R = GryMod.FlashRadar
				expect(R.StealthStep(0, 1, 0.5)).to.aboutEqual(0.5, 1e-6)
				expect(R.StealthStep(0, 0.5, 1)).to.aboutEqual(0.5, 1e-6) -- no overshoot
				expect(R.StealthStep(0.9, 1, 1)).to.equal(1)
				expect(R.StealthStep(1, 0, 1)).to.aboutEqual(0.75, 1e-6)
				expect(R.StealthStep(0.1, 0, 10)).to.equal(0)
				expect(R.StealthStep(0.5, 0.5, 1)).to.equal(0.5)
				expect(R.StealthStep(nil, 1, 0.5)).to.aboutEqual(0.5, 1e-6)
				expect(R.StealthStep(0.3, 0.3, 0 / 0)).to.equal(0.3)
				expect(R.StealthStep(0.3, 1, -1)).to.equal(0.3)
			end
		},
		{
			name = "the old count of NPCs near no longer feeds the stealth bar",
			func = function(state)
				expect(GryMod.FlashRadar.StealthFromCount).to.beNil()
			end
		},
		{
			name = "the HUD's feed: friends around keep the stealth bar at zero, a fighting hostile raises it, and it falls when he is gone",
			func = function(state)
				local R = GryMod.FlashRadar
				local panel = newPanel()
				local options = GryMod.HUDOptions
				local realSnapshot, realFind, realEnabled, realStealth = R.Snapshot, R.FindEntity, options.Enabled, R.Stealth
				local real = {Start = net.Start, WriteBool = net.WriteBool, SendToServer = net.SendToServer}
				net.Start = function() end
				net.WriteBool = function() end
				net.SendToServer = function() end
				R.FindEntity = function() return nil end
				local ply = {GetPos = function() return Vector(0, 0, 0) end, EyeAngles = function() return Angle(0, 0, 0) end}
				local bar = panel.view:Child("StealthBar")
				local ok, err = pcall(function()
					options.Enabled = function() return true end
					R.Stealth = 0
					-- sixteen friends and calm hostiles, as many as filled the bar before
					R.Snapshot = {}
					for i = 1, 16 do
						R.Snapshot[i] = {id = i, x = metres(10 + i), y = 0, z = 0, yaw = 0, type = 1, sub = (i % 2 == 0) and 0 or 2, marker = false, big = false}
					end
					for _ = 1, 60 do R.Feed(panel, ply, 1 / 30) end
					expect(bar:CurrentFrame()).to.equal(1)
					expect(R.Stealth).to.equal(0)

					R.Snapshot[1].sub = 4
					for _ = 1, 15 do R.Feed(panel, ply, 1 / 30) end -- half a second
					expect(R.Stealth).to.aboutEqual(0.5, 0.02)
					expect(bar:CurrentFrame()).to.equal(math.floor(R.Stealth * 100 + 1.5))
					for _ = 1, 30 do R.Feed(panel, ply, 1 / 30) end
					expect(bar:CurrentFrame()).to.equal(101)

					R.Snapshot = {}
					for _ = 1, 30 do R.Feed(panel, ply, 1 / 30) end -- a second: a quarter lower
					expect(R.Stealth).to.aboutEqual(0.75, 0.02)
					for _ = 1, 150 do R.Feed(panel, ply, 1 / 30) end
					expect(bar:CurrentFrame()).to.equal(1)

					-- the contacts switched off: no stale level
					R.Stealth = 1
					R.Snapshot = {{id = 1, x = metres(10), y = 0, z = 0, yaw = 0, type = 1, sub = 4, marker = false, big = false}}
					options.Enabled = function(name) return name ~= "radarunits" end
					for _ = 1, 150 do R.Feed(panel, ply, 1 / 30) end
					expect(R.Stealth).to.equal(0)
				end)
				R.Snapshot, R.FindEntity, options.Enabled, R.Stealth = realSnapshot, realFind, realEnabled, realStealth
				net.Start, net.WriteBool, net.SendToServer = real.Start, real.WriteBool, real.SendToServer

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "Contacts given a table to fill reuses it and its entries, and says the same as a fresh list, with no stale field",
			func = function(state)
				local R = GryMod.FlashRadar
				local S = GryMod.RadarShared
				local mine = {}
				local ally = {contact(10, 0, {id = 1, sub = S.SUB_ALLY}), contact(20, 5, {id = 2, sub = 3, type = 2}), contact(30, -5, {id = 3})}
				local filled = R.Contacts(Vector(0, 0, 0), 0, ally, 1, nil, mine)
				expect(filled).to.equal(mine)
				local fresh = R.Contacts(Vector(0, 0, 0), 0, ally, 1)
				expect(#filled).to.equal(#fresh)

				for i = 1, #fresh do
					for _, key in ipairs({"id", "x", "y", "rotation", "frame", "scale", "alpha", "tint"}) do
						expect(filled[i][key]).to.equal(fresh[i][key])
					end
				end

				-- the next call: fewer contacts, the first one is no ally any more (its tint must be gone), the entries are the same tables
				local first, second = filled[1], filled[2]
				local again = R.Contacts(Vector(0, 0, 0), 0, {contact(10, 0, {id = 7, sub = 4})}, 0, nil, mine)
				expect(again).to.equal(mine)
				expect(#again).to.equal(1)
				expect(again[1]).to.equal(first)
				expect(again[1].id).to.equal(7)
				expect(again[1].tint).to.beNil()
				expect(second.id).to.equal(2) -- the dropped entry is left alone, it is only out of the list
				-- nothing at all empties the list
				expect(#R.Contacts(Vector(0, 0, 0), 0, nil, 0, nil, mine)).to.equal(0)
			end
		},
		{
			name = "an icon whose size and turn are the same is not recomputed, and any change made to it from outside is put back",
			func = function(state)
				local panel = newPanel()
				local R = GryMod.FlashRadar
				local list = R.Contacts(Vector(0, 0, 0), 0, {contact(37.5, 0, {yaw = 90, z = metres(20)})}, 0)
				panel:SetObjects(list)
				local icon = panel.main:Child("Units"):Child("ObjectIcon_100")
				local calls = 0
				local ok, err = pcall(function()
					icon.SetScale = function(self, ...) calls = calls + 1 return getmetatable(self).__index.SetScale(self, ...) end
					icon.SetRotation = function(self, ...) calls = calls + 1 return getmetatable(self).__index.SetRotation(self, ...) end
					panel:SetObjects(list)
					expect(calls).to.equal(0)
					-- the contact moves: its place changes, its size and turn do not
					local moved = R.Contacts(Vector(0, 0, 0), 0, {contact(40, 3, {yaw = 90, z = metres(20)})}, 0)
					panel:SetObjects(moved)
					expect(calls).to.equal(0)
					expect(icon.entry.m[5]).to.aboutEqual(moved[1].x, 0.001)
					-- someone else turns the icon: the next feed puts it back
					icon.SetScale, icon.SetRotation = nil, nil
					icon:SetRotation(10)
					icon:SetScale(300, 300)
					panel:SetObjects(moved)
					expect(icon.entry.m[1]).to.aboutEqual(0, 0.001)
					expect(icon.entry.m[2]).to.aboutEqual(0.625, 0.001)
					-- a new turn is applied
					panel:SetObjects(R.Contacts(Vector(0, 0, 0), 90, {contact(40, 3, {yaw = 90, z = metres(20)})}, 0))
					expect(icon.entry.m[2]).to.aboutEqual(0, 0.001)
					expect(icon.entry.m[1]).to.aboutEqual(-0.625, 0.001)
				end)
				icon.SetScale, icon.SetRotation = nil, nil

				if not ok then
					error(err, 0)
				end
			end
		}
	}
}
