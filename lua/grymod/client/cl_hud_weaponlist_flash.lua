-- The weapon list of the original HUD (movie HUD_WeaponSelection), see cl_flash.lua: up to five rows at the bottom right, one silhouette of a weapon
-- each, the weapon in hand on a plate, shown at each weapon change and faded out after 3 seconds (the movie's own m_time).
--
-- It is a DISPLAY next to the Half-Life 2 selector, not a replacement for it. The stock weapons are engine weapons: the engine draws their selector
-- (one letter of a font, top right) and the hooks that scripted weapons have (DrawWeaponSelection...) do not run for them. Hiding that selector may
-- also stop the switching, and nobody has tried it, so this file does neither: it never hides CHudWeaponSelection and never takes a bind. The
-- stock selector stays on top right, fully working; this list shows at the bottom right.
--
-- Nothing runs between two weapon changes. The HUD's own feed (cl_hud_flash.lua) already compares the weapon at each paint and calls
-- GryMod.FlashWeaponList.OnWeaponChanged when it really changed; a paint hook of our own exists only while a list is on.
--
-- The silhouette of a weapon comes from the weapon registry (field listIcon, docs/weapons.md; the stock weapons are data in sh_api_weapons_hl2.lua),
-- else from the kind of its hand grenade. A weapon with neither gets a row with its NAME written: never a wrong silhouette, and never the
-- movie's first frame ("emtpy"), which is a forbidden sign.
--
-- The movie's own ActionScript is not run by our player (setInterval, the loops over the log), so the timing and the order are done here:
-- rows are numbered from the bottom in the movie (Log0 is the lowest and the list is anchored there, the rows are used from Log0 up).

GryMod = GryMod or {}

local Flash = GryMod.Flash
local API = GryMod.API

local List = {}
GryMod.FlashWeaponList = List

List.MOVIE = "hud_weaponselection"

local STAGE_W, STAGE_H = 1024, 768

List.MAX_ROWS = 5 -- the movie's m_maxLines
List.HOLD = 3 -- the movie's m_time, seconds before the rows fade
List.FADE_FRAMES = 16 -- the rows' own fade, frames 2 to 17 of the movie (30 fps)
List.FADED_FRAME = 17
List.MAX_LABEL = 18

-- The hand grenade kinds of the registry (API.GrenadeKinds) and their silhouettes in the list.
List.GrenadeIcon = {
	explosivegrenade = "Grenade_Explosive",
	flashbang = "Grenade_Flashbang",
	smokegrenade = "Grenade_Smoke",
	empgrenade = "Grenade_EMP"
}

-- Where the rows are, measured on the movie: the Root clip is at (713, 599) with a 3 degree turn, each Log clip has its own place inside it.
local ROOT_X, ROOT_Y, ROOT_A, ROOT_B = 713, 599, 0.998627, 0.0523529
local ROOT_ANGLE = math.deg(math.atan2(ROOT_B, ROOT_A))
local LOG_X = 14.8
local LOG_Y = {[0] = -0.85, -31.55, -62.45, -93.35, -125.05}
local TEXT_RIGHT, TEXT_DOWN = 236, 4 -- the right end and the middle of a text row, inside a Log clip (the icon's own place)

-- Where the stage goes on a screen of w x h pixels: x and y of its origin and the scale. The stage is as high as the screen and sits against the
-- right edge, like the other panel of the bottom right (the status panel).
function List.Placement(w, h)
	local scale = h / STAGE_H

	return w - STAGE_W * scale, 0, scale
end

-- ---------------------------------------------------------------------------------------------------------
-- What is shown
-- ---------------------------------------------------------------------------------------------------------

-- The silhouette (a label of the movie's icon clip) of a weapon: its registry listIcon, else the kind of its hand grenade, else nil.
function List.IconFor(weapon)
	if weapon == nil then
		return nil
	end

	local icon = API.WeaponValue(weapon, "listIcon", true)

	if icon then
		return icon
	end

	local kind = API.WeaponValue(weapon, "grenade", true)

	return kind and List.GrenadeIcon[kind] or nil
end

-- The text of a row with no silhouette: capitals (the movie's font is one), no line break, 18 characters at most.
function List.Label(name)
	name = string.upper(string.gsub(tostring(name or ""), "[%c]+", " "))

	if #name > List.MAX_LABEL then
		name = string.sub(name, 1, List.MAX_LABEL)
	end

	return name
end

local function nameOf(weapon)
	local name = isfunction(weapon.GetPrintName) and weapon:GetPrintName() or weapon:GetClass()

	if isstring(name) and string.sub(name, 1, 1) == "#" and language and language.GetPhrase then
		name = language.GetPhrase(string.sub(name, 2))
	end

	return name
end

-- By slot, then by place in the slot, then by class (so the order never changes from one call to the next).
local function byPlace(a, b)
	local slotA, slotB = a:GetSlot(), b:GetSlot()

	if slotA ~= slotB then
		return slotA < slotB
	end

	local posA, posB = a:GetSlotPos(), b:GetSlotPos()

	if posA ~= posB then
		return posA < posB
	end

	return a:GetClass() < b:GetClass()
end

-- The rows of the list, from the top one down: {weapon, icon (a label or nil), name, current}. `weapons` is the player's weapons, `active` the one in
-- hand, `max` the number of rows. More weapons than rows give a window of rows around the weapon in hand.
function List.Entries(weapons, active, max)
	local sorted = {}

	for _, weapon in ipairs(weapons or {}) do
		if IsValid(weapon) then
			sorted[#sorted + 1] = weapon
		end
	end

	table.sort(sorted, byPlace)

	local count = #sorted
	local first = 1

	if count > max then
		local at = 1

		for index, weapon in ipairs(sorted) do
			if weapon == active then
				at = index

				break
			end
		end

		first = math.Clamp(at - math.floor(max / 2), 1, count - max + 1)
		count = max
	end

	local entries = {}

	for index = 1, count do
		local weapon = sorted[first + index - 1]

		entries[index] = {weapon = weapon, icon = List.IconFor(weapon), name = nameOf(weapon), current = weapon == active}
	end

	return entries
end

-- The row of the movie (0 = the lowest) of entry `index` of `count`: the list is anchored at the bottom, the last entry is Log0.
function List.RowFor(index, count)
	return count - index
end

-- Where a list is, from the time since it was shown: "hold" (3 seconds), "fade" (the rows' own 16 frames), "done". A clock that went back or
-- is not a number is the start.
function List.Phase(elapsed)
	if not (elapsed >= 0) then
		return "hold"
	end

	if elapsed < List.HOLD then
		return "hold"
	end

	if elapsed < List.HOLD + List.FADE_FRAMES / 30 + 0.2 then
		return "fade"
	end

	return "done"
end

-- The alpha (0 to 1) of a row at this frame of its clip, as the movie's fade sets it: 1 on its first two frames, then 14/15 down to 0 on frame 17.
function List.FadeAlpha(frame)
	if frame <= 2 then
		return 1
	end

	return math.max(0, (List.FADED_FRAME - frame) / (List.FADED_FRAME - 2))
end

-- Where the text of a row goes, in stage pixels (the right end of its text, its middle).
function List.TextAnchor(row)
	local x = LOG_X + TEXT_RIGHT
	local y = LOG_Y[row] + TEXT_DOWN

	return ROOT_X + ROOT_A * x, ROOT_Y + ROOT_B * x + y
end

-- ---------------------------------------------------------------------------------------------------------
-- The movie
-- ---------------------------------------------------------------------------------------------------------

local instance -- {movie, root, holder, rows}
local failed = false
local status = 0 -- what the HUD last reported (cl_hud_flash.lua: 1 malfunction, 0 normal, 2 flicker)
local current -- {startedAt, rows = number of rows used, fading} while a list is on
local texts = {} -- {row, text} of the rows with no silhouette
local hooked = false
local lastTime

local HOOK = "GRYFLASHWEAPONLIST"

-- Puts the movie's Root clip in the state of the suit. Its first frame has no stop() in the original, whose C++ calls destroy() after loading it, so
-- the clip is stopped here; anything else would run it into the red frame of the malfunction.
local function applyStatus(ready)
	local holder = ready.holder

	if status == 1 then
		holder:GotoAndStop("malfunction")
	elseif status == 2 then
		holder:GotoAndStop("flickering")
	else
		holder:GotoAndStop(1)
	end

	-- a jump back makes the rows again (Flash rebuilds a clip from its first frame): the old clips are not the ones on the stage any more
	for index = 0, List.MAX_ROWS - 1 do
		ready.rows[index] = holder:Child("Log" .. index) or ready.rows[index]
	end
end

local function hideRows(ready)
	for index = 0, List.MAX_ROWS - 1 do
		ready.rows[index]:SetVisible(false)
	end
end

local function ensure()
	if instance then
		return instance
	end

	if failed then
		return nil
	end

	local movie = Flash.Load(List.MOVIE)
	local root = movie and Flash.NewRoot(movie, GryMod.FlashHUD and GryMod.FlashHUD.Theme)
	local holder = root and root:Child("Root")
	local rows = {}

	for index = 0, List.MAX_ROWS - 1 do
		rows[index] = holder and holder:Child("Log" .. index)

		if not rows[index] then
			holder = nil

			break
		end
	end

	if not holder then
		if root then
			Flash.ReleaseClip(root)
		end

		failed = true

		return nil
	end

	-- the three clips the colours come from, and the one the movie keeps above its stage (out of sight): nothing to draw
	for _, name in ipairs({"Line", "Over", "Text", "US"}) do
		local source = root:Child(name)

		if source then
			source:SetVisible(false)
		end
	end

	instance = {movie = movie, root = root, holder = holder, rows = rows}
	applyStatus(instance)
	hideRows(instance)

	return instance
end

local function stopPaint()
	if hooked then
		hook.Remove("HUDPaint", HOOK)
		hooked = false
	end

	lastTime = nil
end

-- Ends the list on show: the rows are hidden, the paint hook goes.
function List.Clear()
	stopPaint()
	current = nil
	texts = {}

	if instance then
		hideRows(instance)
	end
end

-- Whether the list is wanted: the HUD is on (and the suit with it) and the player did not turn the list off.
function List.Enabled()
	return GryMod.FlashHUD ~= nil and GryMod.FlashHUD.Enabled() and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("weaponlist"))
end

-- The font of the text rows at a size (made once per size).
local fonts = {}

local function fontFor(size)
	local name = fonts[size]

	if not name then
		name = "GryWeaponList" .. size
		surface.CreateFont(name, {font = "Arial", size = size, weight = 700, antialias = true})
		fonts[size] = name
	end

	return name
end

-- Writes the names of the rows with no silhouette, over the movie: at the place of their row, turned like the movie's stage, faded with the row.
function List.DrawTexts(list, x, y, scale)
	local ready = instance
	local theme = GryMod.FlashHUD and GryMod.FlashHUD.Theme
	local colour = theme and theme.Text or {255, 255, 255}
	local font = fontFor(math.max(10, math.floor(12 * scale + 0.5)))

	for _, item in ipairs(list) do
		local alpha = List.FadeAlpha(ready.rows[item.row]:CurrentFrame())

		if alpha > 0 then
			local stageX, stageY = List.TextAnchor(item.row)
			local matrix = Matrix()

			-- the text goes from the matrix's origin to the right and down: the engine drops a text at a NEGATIVE place of the matrix (a text right-aligned
			-- at 0 is one), so the width and the half height are taken off the origin by the matrix itself, after the turn
			surface.SetFont(font)

			local width, height = surface.GetTextSize(item.text)

			matrix:Translate(Vector(x + stageX * scale, y + stageY * scale, 0))
			matrix:Rotate(Angle(0, ROOT_ANGLE, 0))
			matrix:Translate(Vector(-width, -height / 2, 0))
			cam.PushModelMatrix(matrix)
			draw.SimpleText(item.text, font, 0, 0, Color(colour[1], colour[2], colour[3], math.floor(255 * alpha)), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			cam.PopModelMatrix()
		end
	end
end

local function allFaded(ready, used)
	for row = 0, used - 1 do
		if ready.rows[row]:CurrentFrame() < List.FADED_FRAME then
			return false
		end
	end

	return true
end

function List.Paint()
	if not instance or not current then
		stopPaint()

		return
	end

	if not List.Enabled() then
		List.Clear()

		return
	end

	local now = RealTime()
	local dt = math.min(now - (lastTime or now), 0.1)
	lastTime = now

	local phase = List.Phase(now - current.startedAt)

	-- the movie's timers are not run by our player: after the hold, every row goes to its fade
	if phase ~= "hold" and not current.fading then
		current.fading = true

		for row = 0, current.rows - 1 do
			instance.rows[row]:GotoAndPlay("fade")
		end
	end

	instance.root:Advance(dt)

	if phase == "done" or (current.fading and allFaded(instance, current.rows)) then
		List.Clear()

		return
	end

	local x, y, scale = List.Placement(ScrW(), ScrH())

	Flash.Draw(instance.root, x, y, scale)

	if texts[1] then
		List.DrawTexts(texts, x, y, scale)
	end
end

-- Shows the list for this player with this weapon in hand. Returns true, or false and why not.
function List.Show(ply, weapon)
	if not List.Enabled() then
		return false, "off"
	end

	local ready = ensure()

	if not ready then
		return false, "no movie"
	end

	local entries = List.Entries(ply:GetWeapons(), weapon, List.MAX_ROWS)
	local count = #entries

	if count == 0 then
		return false, "no weapons"
	end

	hideRows(ready)
	texts = {}

	for index, entry in ipairs(entries) do
		local rowIndex = List.RowFor(index, count)
		local row = ready.rows[rowIndex]

		-- as the movie's updateLogs: a row that was fading goes back to its first frame (it makes its picture again), THEN its content is set
		if row:CurrentFrame() > 1 then
			row:GotoAndStop("active")
		end

		row:SetVisible(true)

		local content = row:Child("Content")
		local picture = content:Child("KillIcon")

		content:Child("Frame"):SetVisible(entry.current)

		if entry.icon then
			picture:Child("Colorset"):GotoAndStop(entry.icon)
			picture:SetVisible(true)
		else
			-- a text row: the movie's first frame is a forbidden sign, not a blank
			picture:SetVisible(false)
			texts[#texts + 1] = {row = rowIndex, text = List.Label(entry.name)}
		end
	end

	current = {startedAt = RealTime(), rows = count, fading = false}

	if not hooked then
		lastTime = nil
		hook.Add("HUDPaint", HOOK, List.Paint)
		hooked = true
	end

	pcall(hook.Run, "GryMod_WeaponListShown", ply, weapon) -- a broken listener must not stop the list

	return true
end

-- The HUD's feed says the weapon in hand changed (cl_hud_flash.lua). `previous` is the weapon before: nil when the HUD was just made (nothing changed,
-- the player only appeared), and a weapon that is not valid is no weapon (the player has none in hand).
function List.OnWeaponChanged(ply, weapon, previous)
	if previous == nil or not IsValid(weapon) then
		return false
	end

	return (List.Show(ply, weapon)) == true
end

-- The HUD changes its state (cl_hud_flash.lua: 1 malfunction, 0 normal, 2 flicker). The movie's rows are made again by a jump back, so the list
-- on show ends with the change; the next weapon change shows a new one in the new state.
function List.SetStatus(value)
	status = value

	if instance then
		applyStatus(instance)
		List.Clear()
	end
end

hook.Add("GryMod_HUDStatus", "GRYWEAPONLIST", function(value)
	List.SetStatus(value)
end)

-- ---------------------------------------------------------------------------------------------------------
-- What the tests and the tools look at
-- ---------------------------------------------------------------------------------------------------------

function List.Active()
	return hooked
end

function List.Status()
	return status
end

-- The number of rows on show.
function List.Count()
	return current and current.rows or 0
end

function List.Texts()
	return texts
end

function List.Root()
	return instance and instance.root
end

-- The clip of a row of the movie (0 = the lowest).
function List.Row(index)
	return instance and instance.rows[index]
end

-- Takes the list away (a new life, a new theme): the movie is made again at the next list.
function List.Reset()
	stopPaint()
	current = nil
	texts = {}

	if instance then
		Flash.ReleaseClip(instance.root)
	end

	instance, failed = nil, false
end

if API.AddFeature then
	API.AddFeature("weaponlist")
end
