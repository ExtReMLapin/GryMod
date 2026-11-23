-- Tests of the radar's marker sources (GryMod.Radar.AddSource / RemoveSource, cl_hud_radar_sources.lua), GLuaTest format, client realm. A source is a
-- function that returns the markers of the moment {pos, type, subtype, alpha, scale, id}; the radar places them with the rules of the original's
-- icon types (docs/superpowers/plans/status/radar.md of the project): type 5 (objective arrow) sticks to the border of the radar, type 7 (team
-- mate) to the circle of the range, the other types vanish with the radar's frame. Needs the converted movie lua/grymod/flash/hud_radarcompassstealth.lua.

local U = 0.01905 -- metres per Source unit

local function metres(m)
	return m / U
end

local PX = 110 / 94 -- movie pixels per radar pixel
local CX, CY = 64.1, 52.3 -- the centre of the radar in the Units clip (cl_hud_radar_units.lua)

-- a marker `ahead` metres in front of a player at the origin looking along +x, `right` metres to his right
local function marker(kind, ahead, right, extra)
	local m = {pos = Vector(metres(ahead or 0), -metres(right or 0), 0), type = kind}

	for k, v in pairs(extra or {}) do
		m[k] = v
	end

	return m
end

local function place(markers, yaw)
	return GryMod.FlashRadar.MarkerEntries(Vector(0, 0, 0), yaw or 0, markers, #markers, nil, nil)
end

local function one(m, yaw)
	local list = place({m}, yaw)

	return list[1], list
end

-- Runs fn, then removes the sources of these keys whatever happened (a failing test must not leave a source that throws in the player's radar).
local function withSources(keys, fn)
	local ok, err = pcall(fn)

	for _, key in ipairs(keys) do
		GryMod.Radar.RemoveSource(key)
	end

	if not ok then
		error(err, 0)
	end
end

local function newPanel()
	return GryMod.FlashRadar.New(GryMod.Flash.Load("hud_radarcompassstealth"))
end

return {
	groupName = "GryMod radar marker sources",
	cases = {
		-- fails without MarkerEntries / MarkerFrame in cl_hud_radar_sources.lua
		{
			name = "the frame of an icon is the type times 5 plus the subtype; for the objective arrow (type 5) the radar picks the edge variant: 25 primary, 26 primary on the edge, 27 secondary, 28 secondary on the edge",
			func = function(state)
				local R = GryMod.FlashRadar
				expect(R.MarkerFrame(1, 4, false)).to.equal(9)
				expect(R.MarkerFrame(6, 0, false)).to.equal(30)
				expect(R.MarkerFrame(7, 0, false)).to.equal(35)
				expect(R.MarkerFrame(5, 0, false)).to.equal(25)
				expect(R.MarkerFrame(5, 0, true)).to.equal(26)
				expect(R.MarkerFrame(5, 2, false)).to.equal(27)
				expect(R.MarkerFrame(5, 2, true)).to.equal(28)
				-- 1 and 3 are the edge variants asked for by name: they are the same as 0 and 2 (the radar decides), 4 has no picture
				expect(R.MarkerFrame(5, 1, false)).to.equal(25)
				expect(R.MarkerFrame(5, 3, false)).to.equal(27)
				expect(R.MarkerFrame(5, 4, true)).to.equal(26)
			end
		},
		-- fails when the entry of an objective is not on the border (the marker would be dropped as a unit outside the frame)
		{
			name = "a type 5 marker far ahead sticks to the top border of the radar, in the edge frame, its arrow turned to point away from the player",
			func = function(state)
				local e = one(marker(5, 200, 0))
				expect(e).toNot.beNil()
				expect(e.frame).to.equal(26)
				expect(e.x).to.aboutEqual(CX, 0.01)
				expect(e.y).to.aboutEqual(CY - 45.95 * PX, 0.01) -- the top of GryMod.FlashRadar.FRAME
				-- the base shape of the icons points down: turned 180 degrees it points up
				expect(e.rotation).to.aboutEqual(180, 0.01)
			end
		},
		{
			name = "a type 5 marker far to the right sticks to the right border and the arrow points right (the icon turned 270 degrees)",
			func = function(state)
				local e = one(marker(5, 0, 200))
				expect(e.frame).to.equal(26)
				expect(e.x).to.aboutEqual(CX + 70.8 * PX, 0.01)
				expect(e.y).to.aboutEqual(CY, 0.01)
				expect(e.rotation).to.aboutEqual(270, 0.01)
			end
		},
		{
			name = "a secondary type 5 marker (subtype 2) is the yellow icon: 27 inside the radar, 28 on its border; alpha and size are the original's constants (75 percent) unless the source says",
			func = function(state)
				local near = one(marker(5, 37.5, 0, {subtype = 2}))
				expect(near.frame).to.equal(27)
				expect(near.alpha).to.aboutEqual(75, 0.01)
				expect(near.scale).to.aboutEqual(75, 0.01)
				expect(near.y).to.aboutEqual(CY - 21.5 * PX, 0.01) -- 21.5 radar pixels for half the radius, as a contact

				expect((one(marker(5, 200, 0, {subtype = 2}))).frame).to.equal(28)

				local custom = one(marker(5, 37.5, 0, {alpha = 0.5, scale = 120}))
				expect(custom.alpha).to.aboutEqual(50, 0.01)
				expect(custom.scale).to.aboutEqual(120, 0.01)
				expect(custom.frame).to.equal(25)
			end
		},
		-- fails when every type is clamped to the border (the original clamps the objective arrows and the team mates only)
		{
			name = "types that the original does not clamp vanish outside the radar: an explosion ring (6) and a unit icon (1) 200 m away are not listed",
			func = function(state)
				expect(#place({marker(6, 200, 0), marker(1, 200, 0, {subtype = 4}), marker(3, 0, -200)})).to.equal(0)
				local e = one(marker(6, 37.5, 0))
				expect(e).toNot.beNil()
				expect(e.frame).to.equal(30)
				expect(e.alpha).to.aboutEqual(100, 0.01)
				-- the scale of a ring is the source's own (the percent of the movie)
				expect((one(marker(6, 37.5, 0, {scale = 250}))).scale).to.aboutEqual(250, 0.01)
			end
		},
		{
			name = "a type 7 team mate beyond the range sticks to the circle of the range (43 radar pixels), not to the frame; inside the range it is placed as a contact",
			func = function(state)
				local far = one(marker(7, 200, 0))
				expect(far.frame).to.equal(35)
				expect(far.x).to.aboutEqual(CX, 0.01)
				expect(far.y).to.aboutEqual(CY - 43 * PX, 0.01)
				expect(far.alpha).to.aboutEqual(100, 0.01)
				-- 100 times the height factor: 1.9 for a mate level with the player (the units' 25 times it)
				expect(far.scale).to.aboutEqual(190, 0.01)

				local near = one(marker(7, 37.5, 0))
				expect(near.y).to.aboutEqual(CY - 21.5 * PX, 0.01)

				-- a mate 30 m to the right and 40 m behind (50 m away, within the range): not moved
				local side = one(marker(7, -30, 40))
				expect(side.x).to.aboutEqual(CX + 40 * 43 / 75 * PX, 0.01)
				expect(side.y).to.aboutEqual(CY + 30 * 43 / 75 * PX, 0.01)
			end
		},
		{
			name = "the radar's own range applies: with a range of 40 m a marker 30 m ahead is at 32.25 radar pixels, and a mate 60 m ahead is on the circle",
			func = function(state)
				local R = GryMod.FlashRadar
				local list = R.MarkerEntries(Vector(0, 0, 0), 0, {marker(6, 30, 0), marker(7, 60, 0)}, 2, 40, nil)
				expect(list[1].y).to.aboutEqual(CY - 30 * 43 / 40 * PX, 0.01)
				expect(list[2].y).to.aboutEqual(CY - 43 * PX, 0.01)
			end
		},
		{
			name = "the turn of the player turns the markers (yaw 90 looks along +y)",
			func = function(state)
				local m = {pos = Vector(0, metres(37.5), 0), type = 6}
				local e = one(m, 90)
				expect(e.x).to.aboutEqual(CX, 0.01)
				expect(e.y).to.aboutEqual(CY - 21.5 * PX, 0.01)
			end
		},
		{
			name = "a marker more than 500 m above or below the player is dropped; the height sets the size of a mate",
			func = function(state)
				local R = GryMod.FlashRadar
				expect(#place({marker(7, 10, 0, {pos = Vector(metres(10), 0, metres(600))})})).to.equal(0)
				local high = R.MarkerEntries(Vector(0, 0, 0), 0, {{pos = Vector(metres(10), 0, metres(20)), type = 7}}, 1)
				local low = R.MarkerEntries(Vector(0, 0, 0), 0, {{pos = Vector(metres(10), 0, -metres(20)), type = 7}}, 1)
				-- 15 m and more above: the factor 2.5, below: 1.3
				expect(high[1].scale).to.aboutEqual(250, 0.01)
				expect(low[1].scale).to.aboutEqual(130, 0.01)
			end
		},
		{
			name = "markers that are not valid are left out, the others are kept: no position, a type that is not 1 to 7, a position that is not a number",
			func = function(state)
				local list = place({
					{type = 5},
					{pos = Vector(1, 1, 1), type = 0},
					{pos = Vector(1, 1, 1), type = 8},
					{pos = Vector(1, 1, 1), type = "5"},
					{pos = Vector(0 / 0, 0, 0), type = 5},
					"not a table",
					marker(6, 10, 0)
				})
				expect(#list).to.equal(1)
				expect(list[1].frame).to.equal(30)
			end
		},
		{
			name = "an alpha outside 0 to 1 is held to it, and the id of the marker is given back (or made from its place in the list)",
			func = function(state)
				expect((one(marker(6, 10, 0, {alpha = 7}))).alpha).to.aboutEqual(100, 0.01)
				expect((one(marker(6, 10, 0, {alpha = -1}))).alpha).to.aboutEqual(0, 0.01)
				expect((one(marker(6, 10, 0, {id = "quest"}))).id).to.equal("quest")
			end
		},
		{
			name = "given a table to fill, MarkerEntries reuses it and its entries and leaves no stale field (the HUD asks every frame)",
			func = function(state)
				local R = GryMod.FlashRadar
				local mine = {}
				local first = R.MarkerEntries(Vector(0, 0, 0), 0, {marker(5, 200, 0), marker(6, 10, 0)}, 2, nil, mine)
				expect(first).to.equal(mine)
				expect(#mine).to.equal(2)
				local entry = mine[1]
				local again = R.MarkerEntries(Vector(0, 0, 0), 0, {marker(6, 10, 0, {alpha = 0.3})}, 1, nil, mine)
				expect(again).to.equal(mine)
				expect(#again).to.equal(1)
				expect(again[1]).to.equal(entry)
				expect(again[1].frame).to.equal(30)
				expect(again[1].alpha).to.aboutEqual(30, 0.01)
				expect(again[1].rotation).to.aboutEqual(180, 0.01) -- an icon that is not an arrow points up (as the contacts do)
			end
		},
		-- fails without the AddFeature line at the end of cl_hud_radar_sources.lua
		{
			name = "an addon can ask whether the marker sources exist: GryMod.API.Has(\"radarmarkers\")",
			func = function(state)
				expect(GryMod.API.Has("radarmarkers")).to.beTrue()
			end
		},
		-- fails without AddSource / RemoveSource / CollectMarkers
		{
			name = "AddSource takes a key and a function, RemoveSource takes the key away; a bad key or function is refused with a reason",
			func = function(state)
				local A = GryMod.Radar
				local ok, reason = A.AddSource(nil, function() end)
				expect(ok).to.beFalse()
				expect(isstring(reason)).to.beTrue()
				ok = A.AddSource("test_bad_fn", "nope")
				expect(ok).to.beFalse()
				expect(A.HasSource("test_bad_fn")).to.beFalse()

				withSources({"test_src"}, function()
					expect(A.AddSource("test_src", function() return {} end)).to.beTrue()
					expect(A.HasSource("test_src")).to.beTrue()
					expect(A.RemoveSource("test_src")).to.beTrue()
					expect(A.HasSource("test_src")).to.beFalse()
					expect(A.RemoveSource("test_src")).to.beFalse()
				end)
			end
		},
		{
			name = "CollectMarkers gives the markers of every source in the order the sources were added; a second AddSource with the same key replaces the first and keeps its place",
			func = function(state)
				local A, R = GryMod.Radar, GryMod.FlashRadar
				withSources({"test_a", "test_b"}, function()
					A.AddSource("test_a", function() return {marker(6, 10, 0, {id = "a1"}), marker(6, 20, 0, {id = "a2"})} end)
					A.AddSource("test_b", function() return {marker(5, 30, 0, {id = "b1"})} end)
					local buffer = {}
					local count = R.CollectMarkers(buffer)
					local ids = {}

					for i = 1, count do
						if buffer[i].id then ids[#ids + 1] = buffer[i].id end
					end

					expect(table.concat(ids, ",")).to.equal("a1,a2,b1")

					A.AddSource("test_a", function() return {marker(6, 10, 0, {id = "a3"})} end)
					count = R.CollectMarkers(buffer)
					ids = {}

					for i = 1, count do
						if buffer[i].id then ids[#ids + 1] = buffer[i].id end
					end

					expect(table.concat(ids, ",")).to.equal("a3,b1")
				end)
			end
		},
		-- fails without the pcall around each source
		{
			name = "a source that throws does not stop the others; after three errors in a row it is removed (and told once), a good answer in between starts the count again",
			func = function(state)
				local A, R = GryMod.Radar, GryMod.FlashRadar
				local told = 0
				local realNoHalt = ErrorNoHalt
				ErrorNoHalt = function() told = told + 1 end
				withSources({"test_bad", "test_good", "test_flaky"}, function()
					local calls = 0
					A.AddSource("test_bad", function() calls = calls + 1 error("boom") end)
					A.AddSource("test_good", function() return {marker(6, 10, 0, {id = "good"})} end)
					local buffer = {}

					for i = 1, 3 do
						local count = R.CollectMarkers(buffer)
						local found = false

						for k = 1, count do
							if buffer[k].id == "good" then found = true end
						end

						expect(found).to.beTrue()
					end

					expect(calls).to.equal(3)
					expect(A.HasSource("test_bad")).to.beFalse()
					expect(A.HasSource("test_good")).to.beTrue()
					expect(told).to.equal(1)
					R.CollectMarkers(buffer)
					expect(calls).to.equal(3) -- not called again

					-- fails twice, answers once, fails twice again: still there
					local step = 0
					A.AddSource("test_flaky", function()
						step = step + 1

						if step ~= 3 then error("flaky") end

						return {}
					end)

					for i = 1, 5 do R.CollectMarkers(buffer) end

					expect(step).to.equal(5)
					expect(A.HasSource("test_flaky")).to.beTrue()
				end)
				ErrorNoHalt = realNoHalt
			end
		},
		{
			name = "a source that answers something that is not a table, or markers that are not valid, is ignored and counts as no error",
			func = function(state)
				local A, R = GryMod.Radar, GryMod.FlashRadar
				withSources({"test_nil", "test_num"}, function()
					A.AddSource("test_nil", function() return nil end)
					A.AddSource("test_num", function() return 42 end)
					local buffer = {}

					for i = 1, 5 do R.CollectMarkers(buffer) end

					expect(A.HasSource("test_nil")).to.beTrue()
					expect(A.HasSource("test_num")).to.beTrue()
				end)
			end
		},
		{
			name = "no more markers than the limit are taken from the sources, and the buffer is cleared past the count",
			func = function(state)
				local A, R = GryMod.Radar, GryMod.FlashRadar
				withSources({"test_many"}, function()
					A.AddSource("test_many", function()
						local list = {}

						for i = 1, R.MAX_MARKERS + 30 do
							list[i] = marker(6, 10, 0)
						end

						return list
					end)
					local buffer = {"stale", "stale", "stale"}
					local count = R.CollectMarkers(buffer)
					expect(count).to.equal(R.MAX_MARKERS)
					A.RemoveSource("test_many")
					count = R.CollectMarkers(buffer)
					expect(count).to.equal(0)
					expect(buffer[1]).to.beNil()
				end)
			end
		},
		-- fails when SetObjects ignores its second list
		{
			name = "the panel draws the markers after the contacts: the extra list is given to SetObjects, the icons that are not needed any more are hidden",
			func = function(state)
				local R = GryMod.FlashRadar
				local panel = newPanel()
				local contacts = R.Contacts(Vector(0, 0, 0), 0, {{id = 1, x = metres(10), y = 0, z = 0, yaw = 0, type = 1, sub = 4}}, 0)
				local extra = place({marker(5, 200, 0), marker(6, 10, 0)})
				panel:SetObjects(contacts, extra)
				local units = panel.main:Child("Units")
				expect(units:Child("ObjectIcon_100"):Child("Icon"):CurrentFrame()).to.equal(9)
				expect(units:Child("ObjectIcon_101"):Child("Icon"):CurrentFrame()).to.equal(26)
				expect(units:Child("ObjectIcon_102"):Child("Icon"):CurrentFrame()).to.equal(30)
				expect(units:Child("ObjectIcon_102").visible).to.beTrue()
				panel:SetObjects(contacts, nil)
				expect(units:Child("ObjectIcon_100").visible).to.beTrue()
				expect(units:Child("ObjectIcon_101").visible).to.beFalse()
				expect(units:Child("ObjectIcon_102").visible).to.beFalse()
			end
		},
		-- fails when Feed does not look at the sources
		{
			name = "the HUD's feed draws what the sources give, also with the radar contacts switched off, and nothing when the player switched the markers off (gry_hud_radarmarkers 0)",
			func = function(state)
				local R, A = GryMod.FlashRadar, GryMod.Radar
				local panel = newPanel()
				local options = GryMod.HUDOptions
				local realSnapshot, realFind, realEnabled, realZoom = R.Snapshot, R.FindEntity, options.Enabled, GryMod.RadarZoom
				local convar = GetConVar("gry_hud_radarmarkers")
				local realValue = convar:GetString()
				local real = {Start = net.Start, WriteBool = net.WriteBool, WriteUInt = net.WriteUInt, SendToServer = net.SendToServer}
				local ply = {GetPos = function() return Vector(0, 0, 0) end, EyeAngles = function() return Angle(0, 0, 0) end, InVehicle = function() return false end}
				net.Start, net.WriteBool, net.WriteUInt, net.SendToServer = function() end, function() end, function() end, function() end

				withSources({"test_feed"}, function()
					local ok, err = pcall(function()
						options.Enabled = function(name) return name ~= "radarunits" end
						GryMod.RadarZoom = nil
						R.Snapshot, R.FindEntity = {}, function() return nil end
						A.AddSource("test_feed", function() return {marker(5, 200, 0)} end)
						convar:SetString("1")
						R.Feed(panel, ply, 1 / 30)
						local icon = panel.main:Child("Units"):Child("ObjectIcon_100")
						expect(icon).toNot.beNil()
						expect(icon.visible).to.beTrue()
						expect(icon:Child("Icon"):CurrentFrame()).to.equal(26)

						convar:SetString("0")
						R.Feed(panel, ply, 1 / 30)
						expect(icon.visible).to.beFalse()
					end)
					convar:SetString(realValue)
					R.Snapshot, R.FindEntity, options.Enabled, GryMod.RadarZoom = realSnapshot, realFind, realEnabled, realZoom
					net.Start, net.WriteBool, net.WriteUInt, net.SendToServer = real.Start, real.WriteBool, real.WriteUInt, real.SendToServer

					if not ok then
						error(err, 0)
					end
				end)
			end
		}
	}
}
