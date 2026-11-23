-- Tests of the objective markers on the screen (GryMod.FlashObjectives, lua/grymod/client/cl_hud_objectives_flash.lua), GLuaTest format, client realm.
-- Needs the converted movie lua/grymod/flash/hud_missionobjective_icon.lua. What the original does (HUD_MissionObjective_Icon, see the head of the module):
-- one marker per ACTIVE objective, the same picture for a primary and a secondary one, a smaller picture the further it is, an arrow on the edge of the screen
-- when it is off screen or behind, the distance in metres, and the description opening when the marker is near the middle of the screen. The pure parts are
-- tested with plain numbers; the engine (the projection, the list of objectives, the drawing, the HUD state) is replaced where a case needs it and put back in
-- afterEach inside a pcall. Each case names the production change whose absence makes it fail.

local Marks = GryMod.FlashObjectives
local Flash = GryMod.Flash

local saved = {}
local convarsSaved = {}
local drawn

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function setConVar(name, value)
	local convar = GetConVar(name)

	if convarsSaved[name] == nil then
		convarsSaved[name] = convar:GetString()
	end

	convar:SetString(value)
end

local function restore()
	for i = #saved, 1, -1 do
		local entry = saved[i]
		entry[1][entry[2]] = entry[3]
	end

	saved = {}

	for name, value in pairs(convarsSaved) do
		GetConVar(name):SetString(value)
	end

	convarsSaved = {}
end

local function objective(id, extra)
	local o = {id = id, title = "Title " .. id, description = "", primary = true, main = false, state = "active", pos = Vector(100, 0, 0), radar = true, marker = true}

	for k, v in pairs(extra or {}) do
		o[k] = v
	end

	return o
end

-- the list the module reads: GryMod.Objectives.List replaced by one that answers `list`
local function listOf(...)
	local list = {...}

	stub(GryMod.Objectives, "List", function() return list end)

	return list
end

-- A projection that answers the same for every objective: where the engine would put the point, as Marks.Project gives it.
local function projectAt(sx, sy, visible, dx, dy, metres)
	stub(Marks, "Project", function()
		return sx, sy, visible, dx, dy, metres
	end)
	stub(Marks, "PositionOf", function(o) return o.pos end)
end

local function iconOf(index)
	return Marks.Icons()[index]
end

local function cardOf(index)
	return iconOf(index).clip:Child("MissionObectiveIcon")
end

local function textOf(card, name)
	local holder = card:Find(name .. ".Colorset")

	return holder and holder:Child(name).text
end

return {
	groupName = "GryMod objective markers (HUD_MissionObjective_Icon)",
	beforeEach = function()
		Marks.Reset()
		drawn = 0

		stub(GryMod.FlashHUD, "Enabled", function() return true end)
		stub(Flash, "Draw", function() drawn = drawn + 1 return true end)
		setConVar("gry_hud_objectives", "1")
		-- (the mode of the binoculars is the default; these cases are about the markers themselves: "always", the binoculars' own cases set it)
		setConVar("gry_objectives_marker_mode", "always")
	end,
	afterEach = function()
		pcall(Marks.Reset)
		pcall(function()
			hook.Remove("HUDPaint", "GRYFLASHOBJECTIVES")
		end)
		pcall(restore)
		pcall(Marks.Refresh)
	end,
	cases = {
		{
			-- fails without Marks.SizeFor
			name = "SizeFor: 1.4 up to 10 m, 0.7 from 500 m, a straight line between (the original's hud_onScreen cvars)",
			func = function()
				expect(Marks.SizeFor(0)).to.aboutEqual(1.4, 0.001)
				expect(Marks.SizeFor(10)).to.aboutEqual(1.4, 0.001)
				expect(Marks.SizeFor(255)).to.aboutEqual(1.05, 0.001)
				expect(Marks.SizeFor(500)).to.aboutEqual(0.7, 0.001)
				expect(Marks.SizeFor(5000)).to.aboutEqual(0.7, 0.001)
			end
		},
		{
			-- fails without Marks.ArrowFor: the table of the 8 arrows (frames icon13..icon20) is read from the movie's own matrices: 13 points left, 14 up-left,
			-- 15 up, 16 up-right, 17 right (mirrored), 18 down-right, 19 down, 20 down-left
			name = "ArrowFor: the picture of the arrow that points the way (screen x right, y down)",
			func = function()
				expect(Marks.ArrowFor(1, 0)).to.equal(17)
				expect(Marks.ArrowFor(1, 1)).to.equal(18)
				expect(Marks.ArrowFor(0, 1)).to.equal(19)
				expect(Marks.ArrowFor(-1, 1)).to.equal(20)
				expect(Marks.ArrowFor(-1, 0)).to.equal(13)
				expect(Marks.ArrowFor(-1, -1)).to.equal(14)
				expect(Marks.ArrowFor(0, -1)).to.equal(15)
				expect(Marks.ArrowFor(1, -1)).to.equal(16)
				-- a sector is 45 degrees wide, centred on its direction
				expect(Marks.ArrowFor(10, -3)).to.equal(17)
				expect(Marks.ArrowFor(10, -5)).to.equal(16)
			end
		},
		{
			-- fails without Marks.Label: the movie's frames are named icon<type>_<state>
			name = "Label: icon<type>_<state>, and every label the module uses exists in the movie",
			func = function()
				expect(Marks.Label(24, 0)).to.equal("icon24_0")
				expect(Marks.Label(13, 0)).to.equal("icon13_0")

				local movie = Flash.Load(Marks.MOVIE)
				expect(movie).to.exist()

				local root = Flash.NewRoot(movie)
				local made = Flash.Duplicate(root:Child("Root1"), "MissionObjective", "probe", 1000)
				expect(made).to.exist()

				for _, kind in ipairs({24, 13, 14, 15, 16, 17, 18, 19, 20}) do
					made:GotoAndStop(Marks.Label(kind, 0))
					expect(made:CurrentLabel()).to.equal(Marks.Label(kind, 0))
				end

				Flash.ReleaseClip(root)
			end
		},
		{
			-- fails without Marks.Eligible: the original keeps an objective on screen only while it is active (a finished or failed one leaves its list)
			name = "Eligible: active and marker on; done, failed or marker off are not shown; primary and secondary look the same",
			func = function()
				expect(Marks.Eligible(objective("a"))).to.beTrue()
				expect(Marks.Eligible(objective("a", {primary = false}))).to.beTrue()
				expect(Marks.Eligible(objective("a", {state = "done"}))).to.beFalse()
				expect(Marks.Eligible(objective("a", {state = "failed"}))).to.beFalse()
				expect(Marks.Eligible(objective("a", {marker = false}))).to.beFalse()
			end
		},
		{
			-- fails without Marks.Placement: the picture of the 1366 x 768 stage is as high as the screen, centred
			name = "Placement: as high as the screen, centred across its width",
			func = function()
				local x, y, scale = Marks.Placement(1920, 1080)
				expect(scale).to.aboutEqual(1080 / 768, 0.0001)
				expect(y).to.equal(0)
				expect(x).to.aboutEqual((1920 - 1366 * 1080 / 768) / 2, 0.01)
			end
		},
		{
			-- fails without Marks.Layout: on the screen the marker sits on the projected point (in stage units), with the objective picture
			name = "Layout: a point inside the screen keeps its place and the objective picture (24)",
			func = function()
				-- a 1366 x 768 screen: the stage is the screen
				local x, y, kind, onScreen = Marks.Layout(683, 384, true, 0, 0, 1366, 768)
				expect(onScreen).to.beTrue()
				expect(kind).to.equal(24)
				expect(x).to.aboutEqual(683, 0.01)
				expect(y).to.aboutEqual(384, 0.01)

				-- a wider screen: the point is moved into the stage's own coordinates (the stage is centred)
				local wx, wy = Marks.Layout(960, 540, true, 0, 0, 1920, 1080)
				expect(wx).to.aboutEqual(683, 0.5)
				expect(wy).to.aboutEqual(384, 0.5)
			end
		},
		{
			-- fails without the edge clamp in Marks.Layout: off the screen the marker goes to the border, inside a margin, with the arrow of its direction
			name = "Layout: off the screen to the right, the marker goes to the right border with the right arrow; behind, to the bottom",
			func = function()
				local x, y, kind, onScreen = Marks.Layout(5000, 384, true, 100, 0, 1366, 768)
				expect(onScreen).to.beFalse()
				expect(kind).to.equal(17)
				expect(x).to.aboutEqual(1366 - Marks.EDGE_MARGIN, 0.01)
				expect(y).to.aboutEqual(384, 0.01)

				-- up and to the left of the screen: the corner, the arrow that points up-left
				local cx, cy, ckind = Marks.Layout(-900, -900, true, -100, -100, 1366, 768)
				expect(ckind).to.equal(14)
				-- the direction (-1, -1) reaches the top border (344 from the middle) before the left one (643): 683 - 344
				expect(cx).to.aboutEqual(339, 0.01)
				expect(cy).to.aboutEqual(Marks.EDGE_MARGIN, 0.01)

				-- behind the camera, straight behind (no sideways direction): the bottom edge, the arrow that points down
				local bx, by, bkind, bOn = Marks.Layout(683, 384, false, 0, 0, 1366, 768)
				expect(bOn).to.beFalse()
				expect(bkind).to.equal(19)
				expect(bx).to.aboutEqual(683, 0.01)
				expect(by).to.aboutEqual(768 - Marks.EDGE_MARGIN, 0.01)

				-- on the screen's own coordinates the point can be "visible" for the engine and still near the border: the margin keeps the picture whole
				local _, _, nearKind, nearOn = Marks.Layout(1360, 384, true, 100, 0, 1366, 768)
				expect(nearOn).to.beFalse()
				expect(nearKind).to.equal(17)
			end
		},
		{
			-- fails without Marks.CentreDistance2 / Marks.NearCentreId: the description opens for the marker near the middle of the screen, one at a time
			name = "NearCentreId: the on-screen marker nearest to the middle, only when it is close enough; an arrow never",
			func = function()
				expect(Marks.CentreDistance2(683, 384, 1366, 768)).to.aboutEqual(0, 0.0001)
				expect(Marks.CentreDistance2(1366, 384, 1366, 768)).to.aboutEqual(1, 0.0001)

				local entries = {
					{id = "far", onScreen = true, centre = 0.5},
					{id = "near", onScreen = true, centre = 0.01},
					{id = "nearer", onScreen = true, centre = 0.002},
					{id = "edge", onScreen = false, centre = 0}
				}

				expect(Marks.NearCentreId(entries, 4)).to.equal("nearer")
				expect(Marks.NearCentreId({{id = "far", onScreen = true, centre = 0.5}}, 1)).to.beNil()
				expect(Marks.NearCentreId({{id = "edge", onScreen = false, centre = 0}}, 1)).to.beNil()
				expect(Marks.NearCentreId({}, 0)).to.beNil()
			end
		},
		{
			-- fails without Marks.Collect: one entry for each eligible objective; the objects the player must not see are never projected
			name = "Collect: only the active objectives with a marker are projected; the distance is in whole metres and the size follows it",
			func = function()
				local calls = 0
				local list = listOf(objective("a"), objective("b", {state = "done"}), objective("c", {marker = false}), objective("d", {primary = false}))

				stub(Marks, "Project", function()
					calls = calls + 1

					return 683, 384, true, 0, 0, 250.4
				end)
				stub(Marks, "PositionOf", function(o) return o.pos end)

				local entries, count = Marks.Collect(list)
				expect(count).to.equal(2)
				expect(calls).to.equal(2)
				expect(entries[1].id).to.equal("a")
				expect(entries[2].id).to.equal("d")
				expect(entries[1].metres).to.equal(250)
				expect(entries[1].size).to.aboutEqual(Marks.SizeFor(250.4), 0.0001)
				expect(entries[3]).to.beNil()
			end
		},
		{
			-- fails without the empty-list shortcut in Marks.Collect / Marks.Refresh: with nothing to show nothing runs, and no paint hook exists
			name = "Refresh: the paint hook exists only while an eligible objective exists (added, finished, removed)",
			func = function()
				local list = listOf()

				Marks.Refresh()
				expect(Marks.Active()).to.beFalse()
				expect(hook.GetTable()["HUDPaint"]["GRYFLASHOBJECTIVES"]).to.beNil()

				list[1] = objective("a")
				Marks.Refresh()
				expect(Marks.Active()).to.beTrue()
				expect(hook.GetTable()["HUDPaint"]["GRYFLASHOBJECTIVES"]).to.exist()

				list[1].state = "done"
				Marks.Refresh()
				expect(Marks.Active()).to.beFalse()
				expect(hook.GetTable()["HUDPaint"]["GRYFLASHOBJECTIVES"]).to.beNil()

				-- the option off: no hook either
				list[1].state = "active"
				setConVar("gry_hud_objectives", "0")
				Marks.Refresh()
				expect(Marks.Active()).to.beFalse()
			end
		},
		{
			-- fails without Marks.ModeAllows
			name = "ModeAllows: always shows; binoculars shows only with them up, unless the binoculars' screen is off (the markers would never show)",
			func = function()
				expect(Marks.ModeAllows("always", true, false)).to.beTrue()
				expect(Marks.ModeAllows("always", false, false)).to.beTrue()
				expect(Marks.ModeAllows("binoculars", true, true)).to.beTrue()
				expect(Marks.ModeAllows("binoculars", true, false)).to.beFalse()
				expect(Marks.ModeAllows("binoculars", false, false)).to.beTrue()
			end
		},
		{
			-- fails without Marks.Mode and the convar: the default "binoculars" is the original's
			name = "the mode is the saved convar gry_objectives_marker_mode, binoculars by default, and anything but always is binoculars",
			func = function()
				expect(GetConVar("gry_objectives_marker_mode"):GetDefault()).to.equal("binoculars")
				expect(bit.band(GetConVar("gry_objectives_marker_mode"):GetFlags(), FCVAR_ARCHIVE)).to.equal(FCVAR_ARCHIVE)

				setConVar("gry_objectives_marker_mode", "always")
				expect(Marks.Mode()).to.equal("always")
				setConVar("gry_objectives_marker_mode", "binoculars")
				expect(Marks.Mode()).to.equal("binoculars")
				setConVar("gry_objectives_marker_mode", "nonsense")
				expect(Marks.Mode()).to.equal("binoculars")
			end
		},
		{
			-- fails without the mode in Marks.Refresh / Marks.Paint, or without the listener of GryMod_BinocularsToggled: the markers would show without the binoculars
			name = "binoculars mode: no paint hook and nothing drawn while the binoculars are down; up, the hook comes with the report of the toggle and the marker is drawn; down again, it goes",
			func = function()
				local up = false
				local bino = GryMod.FlashBinoculars

				stub(bino, "Enabled", function() return true end)
				stub(bino, "Wanted", function() return up end)
				stub(_G, "LocalPlayer", function() return {IsValid = function() return true end, Alive = function() return true end} end)
				setConVar("gry_objectives_marker_mode", "binoculars")
				listOf(objective("a"))
				projectAt(300, 200, true, 0, 0, 64)

				Marks.Refresh()
				expect(Marks.Active()).to.beFalse()
				Marks.Paint()
				expect(drawn).to.equal(0)

				local listener = hook.GetTable()["GryMod_BinocularsToggled"]["GryObjectiveMarks"]
				expect(listener).to.beA("function")

				up = true
				listener(true)
				expect(Marks.Active()).to.beTrue()
				Marks.Paint()
				expect(drawn).to.equal(1)

				up = false
				listener(false)
				expect(Marks.Active()).to.beFalse()
				Marks.Paint()
				expect(drawn).to.equal(1)

				-- the mode changed to always while they are down: the markers come at once
				setConVar("gry_objectives_marker_mode", "always")
				Marks.Refresh()
				expect(Marks.Active()).to.beTrue()
			end
		},
		{
			-- fails without the hooks GryMod_ObjectiveAdded / Changed / Removed in the module: the paint hook follows the list by itself
			name = "the reporting hooks of the objectives call Refresh: the hook comes with the first objective and goes with the last",
			func = function()
				local list = listOf()
				local added = hook.GetTable()["GryMod_ObjectiveAdded"]["GryObjectiveMarks"]
				local changed = hook.GetTable()["GryMod_ObjectiveChanged"]["GryObjectiveMarks"]
				local removed = hook.GetTable()["GryMod_ObjectiveRemoved"]["GryObjectiveMarks"]

				expect(added).to.exist()
				expect(changed).to.exist()
				expect(removed).to.exist()

				list[1] = objective("a")
				added("a", list[1])
				expect(Marks.Active()).to.beTrue()

				list[1] = nil
				removed("a", {}, "removed")
				expect(Marks.Active()).to.beFalse()
			end
		},
		{
			-- fails without Marks.Paint drawing through Flash.Draw with the icon of the objective: the marker, its picture and its distance text
			name = "Paint: one marker with the objective picture and the distance in metres; primary and secondary get the same frame",
			func = function()
				listOf(objective("a"), objective("b", {primary = false}))
				projectAt(300, 200, true, 0, 0, 64.4)
				Marks.Refresh()
				Marks.Paint()

				expect(drawn).to.equal(1)
				expect(iconOf(1).clip:CurrentLabel()).to.equal("icon24_0")
				expect(iconOf(2).clip:CurrentLabel()).to.equal("icon24_0")
				expect(textOf(cardOf(1), "DistanceText")).to.equal("64M")
				expect(iconOf(1).clip.visible).to.beTrue()
			end
		},
		{
			-- fails without the edge handling in Paint: an objective off the screen is an arrow (a frame icon13..20), without the description box
			name = "Paint: off the screen the marker becomes the arrow of its direction",
			func = function()
				listOf(objective("a"))
				projectAt(-4000, 200, true, -100, 0, 80)
				Marks.Refresh()
				Marks.Paint()

				expect(iconOf(1).clip:CurrentLabel()).to.equal("icon13_0")
				expect(iconOf(1).clip:Child("MissionObectiveIcon")).to.beNil()
			end
		},
		{
			-- fails without Marks.NearCentre in Paint: setNearCenter of the movie opens the description box of the marker near the middle, writes the title in it
			name = "Paint: the marker near the middle of the screen opens its description (the title); the other one stays closed",
			func = function()
				listOf(objective("a"), objective("b"))

				local index = 0
				stub(Marks, "Project", function()
					index = index + 1

					if index % 2 == 1 then
						return ScrW() / 2, ScrH() / 2, true, 0, 0, 50
					end

					return ScrW() * 0.2, ScrH() * 0.8, true, 0, 0, 50
				end)
				stub(Marks, "PositionOf", function(o) return o.pos end)

				Marks.Refresh()
				Marks.Paint()

				expect(cardOf(1):CurrentFrame() > 1).to.beTrue()
				expect(cardOf(2):CurrentFrame()).to.equal(1)
				expect(textOf(cardOf(1), "MissionObjectiveText")).to.equal("Title a")
			end
		},
		{
			-- fails without the closing half of Marks.NearCentre: a box that is open closes when the marker leaves the middle
			name = "Paint: an open description closes when the marker leaves the middle of the screen",
			func = function()
				listOf(objective("a"))

				local atCentre = true
				stub(Marks, "Project", function()
					if atCentre then
						return ScrW() / 2, ScrH() / 2, true, 0, 0, 50
					end

					return ScrW() * 0.2, ScrH() * 0.8, true, 0, 0, 50
				end)
				stub(Marks, "PositionOf", function(o) return o.pos end)

				Marks.Refresh()
				Marks.Paint()
				expect(cardOf(1):CurrentFrame() > 1).to.beTrue()

				atCentre = false
				Marks.Paint()
				-- "close" is the label at frame 22 of the card: the card plays it
				expect(cardOf(1):CurrentFrame()).to.equal(cardOf(1).labels["close"])
			end
		},
		{
			-- fails without the Enabled test in Paint: the HUD off, the option off or a dead player draws nothing
			name = "Paint: nothing is drawn when the option is off, the HUD is off or the player is dead",
			func = function()
				listOf(objective("a"))
				projectAt(300, 200, true, 0, 0, 64)
				Marks.Refresh()

				setConVar("gry_hud_objectives", "0")
				Marks.Paint()
				expect(drawn).to.equal(0)

				setConVar("gry_hud_objectives", "1")
				stub(GryMod.FlashHUD, "Enabled", function() return false end)
				Marks.Paint()
				expect(drawn).to.equal(0)

				stub(GryMod.FlashHUD, "Enabled", function() return true end)
				stub(_G, "LocalPlayer", function() return {IsValid = function() return true end, Alive = function() return false end} end)
				Marks.Paint()
				expect(drawn).to.equal(0)
			end
		},
		{
			-- fails without the entry "objectives" in the HUD options list (cl_hud_options.lua): the switch gry_hud_objectives and the menu line come from it
			name = "gry_hud_objectives is a HUD element: on by default",
			func = function()
				expect(GryMod.HUDOptions.Find("objectives")).to.exist()
				expect(GetConVar("gry_hud_objectives"):GetDefault()).to.equal("1")
			end
		},
		{
			-- fails without the entry in ResetAll / the prewarm pieces: a new theme rebuilds the markers, the movie is loaded ahead of time
			name = "the module is part of the theme rebuild and of the prewarm list",
			func = function()
				local found = false

				for _, piece in ipairs(GryMod.FlashPrewarm.Pieces) do
					if piece.name == "objectives" then
						found = true
						expect(piece.option).to.equal("objectives")
						expect(piece.films()[1]).to.equal(Marks.MOVIE)
					end
				end

				expect(found).to.beTrue()
			end
		}
	}
}
