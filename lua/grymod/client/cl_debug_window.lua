-- The effects test window: a popup, apart from the options panel (its last button opens it), where every HUD effect is one button, to try
-- them one by one. Nothing in this file names an effect or a command: both sections are loops over lists that other code owns.
--   * "Effects on this screen": for each name of GryMod.API.ListHUDEvents, the description GryMod.API.GetHUDEventInfo(name) gives ({label,
--     variants = {{label, data}, ...}, follows = {{convar, what the option cuts}, ...}}, all optional): one button per variant, or one button when
--     there is none, played with GryMod.API.HUDEvent on THIS client only. The seconds of the slider are given as data.seconds. The tooltip comes from
--     `follows`: a button whose option of the player cuts the effect says so but still plays (the player is here to test). The events of other
--     addons show by themselves. Without GetHUDEventInfo the label is the name and there is no variant and no tooltip.
--   * "Real, on me (administrators only)": the commands of the registry of sv_debug_cmd.lua. At each Open the window asks the server for the list
--     (gry_debug_list), keeps the answer and makes the buttons again from it; a button sends the id of an entry of that list, and the server decides
--     again. Greyed and inactive for a player who is not an admin (who gets an empty list).
-- One window: Open shows the same panel again (both sections are made again each time, so what was registered since appears); closing hides it.
-- Cost: nothing runs while the window is hidden (a hidden panel does not think); nothing is created at load.

GryMod = GryMod or {}

local DW = GryMod.DebugWindow or {}
GryMod.DebugWindow = DW

-- a hot reload of this file: the old window goes away, so no panel leaks
if DW.Destroy then
	pcall(DW.Destroy)
end

local POLL = 1 -- seconds between two looks at the admin status
local TITLE = "GryMod effects test"
local ADMIN_TIP = "Administrators only: this changes the real state of your suit"

DW.RealList = DW.RealList or {} -- what the server last said: {{id = , label = }, ...}

-- ---------------------------------------------------------------------------------------------------------
-- The ways out of the window (fields, so that the tests can look at what goes through them)
-- ---------------------------------------------------------------------------------------------------------

-- How the window takes the mouse and the keyboard.
function DW.MakePopup(frame)
	frame:MakePopup()
end

-- How a real command goes to the server.
function DW.SendCommand(id)
	net.Start("gry_debug_cmd")
	net.WriteString(id)
	net.SendToServer()
end

-- How the list of the real commands is asked for (the answer comes in the receiver at the bottom).
function DW.RequestList()
	net.Start("gry_debug_list")
	net.SendToServer()
end

function DW.IsAdmin()
	if GryMod.AdminUI and GryMod.AdminUI.IsAdmin then
		return GryMod.AdminUI.IsAdmin()
	end

	local ply = LocalPlayer()

	return IsValid(ply) and ply:IsAdmin() == true
end

-- The sorted names of the events, or an empty list (ListHUDEvents is not there yet, or answers nothing).
local function listEvents()
	local list = GryMod.API and GryMod.API.ListHUDEvents

	if not isfunction(list) then
		return {}
	end

	local ok, names = pcall(list)

	return ok and istable(names) and names or {}
end

-- The description of an event (a table, empty when the API has none: the button is then the name, alone, with no tooltip).
local function eventInfo(name)
	local get = GryMod.API and GryMod.API.GetHUDEventInfo

	if not isfunction(get) then
		return {}
	end

	local ok, info = pcall(get, name)

	return ok and istable(info) and info or {}
end

-- The tooltip of a button from the `follows` of its event: what the options of the player cut now, or nil when nothing does.
function DW.Tooltip(follows)
	local lines = {}

	for _, entry in ipairs(istable(follows) and follows or {}) do
		local convar = istable(entry) and isstring(entry[1]) and GetConVar(entry[1])

		if convar and not convar:GetBool() then
			lines[#lines + 1] = "off by your option (" .. entry[1] .. "): " .. tostring(entry[2])
		end
	end

	if #lines == 0 then
		return nil
	end

	return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------------------------------------

local function section(parent, text)
	local label = vgui.Create("DLabel", parent)
	label:SetFont("DermaDefaultBold")
	label:SetDark(true)
	label:SetText(text)
	label:SizeToContents()
	label:Dock(TOP)
	label:DockMargin(0, 10, 0, 4)

	return label
end

local function note(parent, text)
	local label = vgui.Create("DLabel", parent)
	label:SetDark(true)
	label:SetText(text)
	label:SetWrap(true)
	label:SetAutoStretchVertical(true)
	label:Dock(TOP)
	label:DockMargin(0, 0, 0, 4)

	return label
end

local function grid(parent)
	local layout = vgui.Create("DIconLayout", parent)
	layout:Dock(TOP)
	layout:SetSpaceX(4)
	layout:SetSpaceY(4)

	return layout
end

local function gridButton(layout, text)
	local button = layout:Add("DButton")
	button:SetText(text)
	button:SetSize(150, 26)

	return button
end

-- Makes the grid of the events again from the registry of the moment: one button per variant, or one button for an event with none.
local function fillEvents(frame)
	frame.GryEventGrid:Clear()
	frame.GryEventButtons = {}

	for _, name in ipairs(listEvents()) do
		local info = eventInfo(name)
		local variants = info.variants

		if not istable(variants) or #variants == 0 then
			variants = {{label = info.label}}
		end

		for _, variant in ipairs(variants) do
			local button = gridButton(frame.GryEventGrid, tostring(variant.label or info.label or name))
			local extra = istable(variant.data) and variant.data or {}

			button:SetTooltip(DW.Tooltip(info.follows))

			button.OnCursorEntered = function(self)
				self:SetTooltip(DW.Tooltip(info.follows))
			end

			button.DoClick = function()
				local data = {seconds = frame.GrySeconds:GetValue()}

				for key, value in pairs(extra) do
					data[key] = value
				end

				GryMod.API.HUDEvent(name, data)
			end

			frame.GryEventButtons[#frame.GryEventButtons + 1] = button
		end
	end

	frame.GryEventGrid:InvalidateLayout(true)
end

-- Puts the real buttons on or off for the admin status: inactive and dimmed with the tooltip that says why.
local function applyAdmin(frame, isAdmin)
	frame.GryAdmin = isAdmin

	for _, button in pairs(frame.GryRealButtons) do
		button:SetEnabled(isAdmin)
		button:SetAlpha(isAdmin and 255 or 90)
		button:SetTooltip(not isAdmin and ADMIN_TIP or nil)
	end

	if not isAdmin then
		frame.GryRealStatus:SetText("You are not an administrator: there is nothing here for you.")
	elseif #frame.GryRealOrder == 0 then
		frame.GryRealStatus:SetText("You are an administrator. The server's list of commands has not come yet (or it is empty).")
	else
		frame.GryRealStatus:SetText("You are an administrator: these act on your real suit, on you only.")
	end
end

-- Makes the real buttons again from the list the server last sent. A button sends the id of its entry: only ids of that list can be sent.
local function fillReal(frame)
	frame.GryRealGrid:Clear()
	frame.GryRealButtons = {}
	frame.GryRealOrder = {}

	for _, entry in ipairs(DW.RealList) do
		local id = entry.id
		local button = gridButton(frame.GryRealGrid, entry.label)

		button.DoClick = function(self)
			if not self:IsEnabled() then
				return
			end

			DW.SendCommand(id)
		end

		frame.GryRealButtons[id] = button
		frame.GryRealOrder[#frame.GryRealOrder + 1] = id
	end

	frame.GryRealGrid:InvalidateLayout(true)
	applyAdmin(frame, DW.IsAdmin())
end

-- Keeps the list the server sent (a list of {id, label}: what is not a pair of texts is dropped) and shows it if the window exists.
function DW.SetRealList(list)
	DW.RealList = {}

	for _, entry in ipairs(istable(list) and list or {}) do
		if istable(entry) and isstring(entry.id) and isstring(entry.label) then
			DW.RealList[#DW.RealList + 1] = {id = entry.id, label = entry.label}
		end
	end

	if IsValid(DW.Frame) then
		fillReal(DW.Frame)
	end
end

-- The look at the admin status, at most once a second (`now` is given so that a test can pass the time).
function DW.Poll(frame, now)
	if not IsValid(frame) or now - frame.GryPolled < POLL then
		return
	end

	frame.GryPolled = now

	local isAdmin = DW.IsAdmin()

	if frame.GryAdmin ~= isAdmin then
		applyAdmin(frame, isAdmin)
	end
end

local function build()
	local frame = vgui.Create("DFrame")
	frame.GryDebugWindow = true
	frame:SetTitle(TITLE)
	frame:SetSize(660, 520)
	frame:SetMinWidth(360)
	frame:SetMinHeight(280)
	frame:SetSizable(true)
	frame:SetDraggable(true)
	frame:SetDeleteOnClose(false) -- closing hides: Open shows the same panel again
	frame:Center()

	local previous = frame.Think

	frame.Think = function(self, ...)
		if previous then
			previous(self, ...)
		end

		DW.Poll(self, RealTime())
	end

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:Dock(FILL)

	local slider = vgui.Create("DNumSlider", scroll)
	slider:Dock(TOP)
	slider:SetText("Seconds (given to every effect)")
	slider:SetDark(true)
	slider:SetMin(0.5)
	slider:SetMax(15)
	slider:SetDecimals(1)
	slider:SetValue(5)
	frame.GrySeconds = slider

	section(scroll, "Effects on this screen")
	note(scroll, "Each button plays the effect (picture and sound) on your screen only. A tooltip tells when one of your options cuts it.")
	frame.GryEventGrid = grid(scroll)
	fillEvents(frame)

	section(scroll, "Real, on me (administrators only)")
	frame.GryRealStatus = note(scroll, "")
	frame.GryRealGrid = grid(scroll)
	frame.GryRealButtons = {}
	frame.GryRealOrder = {}
	fillReal(frame)

	frame.GryPolled = RealTime()

	return frame
end

-- Opens the window, or brings the one that exists to the front. Both sections are made again (the events registered since appear) and the
-- server is asked for its list of commands again: the answer makes the real buttons again when it comes.
function DW.Open()
	local frame = DW.Frame

	if not IsValid(frame) then
		frame = build()
		DW.Frame = frame
	else
		fillEvents(frame)
		fillReal(frame)
		frame.GryPolled = RealTime()
	end

	frame:SetVisible(true)
	DW.MakePopup(frame)
	frame:MoveToFront()
	DW.RequestList()

	return frame
end

-- Removes the window for good.
function DW.Destroy()
	if IsValid(DW.Frame) then
		DW.Frame:Remove()
	end

	DW.Frame = nil
end

-- The answer of the server: a count, then an id and a label for each.
net.Receive("gry_debug_list", function()
	local list = {}

	for _ = 1, net.ReadUInt(8) do
		list[#list + 1] = {id = net.ReadString(), label = net.ReadString()}
	end

	DW.SetRealList(list)
end)
