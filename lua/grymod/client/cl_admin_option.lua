-- The settings of the SERVER in the options panel, for the administrators only (the white list is sh_server_options.lua, the rule is
-- sv_server_options.lua). A client cannot change a server convar by itself (on a dedicated server a replicated convar refuses the console of
-- a client and a convar that is not replicated does not exist for it; measured: even in single player ConVar:SetString of a replicated convar
-- raises an error), so these controls never write a convar: they send ONE net message, gry_set_server_option (the name, the value), and the
-- server decides. What they show is the value the server really has (the replicated convar, read every second and when a request was made).
-- For a player who is not an admin they are disabled (no mouse, dimmed) with a tooltip that says why; the status is looked at once a second in
-- the Think of the panel (a panel that is not shown does not think: nothing runs outside the panel) so that a player who becomes an admin, or
-- stops being one, sees it without reopening the panel.

GryMod = GryMod or {}

local UI = GryMod.AdminUI or {}
GryMod.AdminUI = UI

local TOOLTIP = "Server setting: administrators only"
local POLL = 1 -- seconds between two looks at the status and at the values
local HOLD = 1 -- seconds after a request during which the box keeps what the player chose: the server's answer needs a tick to come back

-- Whether the local player is an admin, as the engine knows it (the host of a listen server and the single player are).
function UI.IsAdmin()
	local ply = LocalPlayer()

	return IsValid(ply) and ply:IsAdmin() == true
end

-- The decision, pure: whether the option is on, and the tooltip to show (nil when on). What is not known to be an admin is not one.
function UI.Decide(isAdmin)
	if isAdmin == true then
		return true, nil
	end

	return false, TOOLTIP
end

-- The line under the title of the section.
function UI.StatusText(isAdmin)
	if isAdmin then
		return "You are an administrator: these are the server's settings and they apply to every player."
	end

	return "You are not an administrator: only an administrator can change these settings."
end

-- The real way to ask the server (a field so that the tests can look at what is sent).
function UI.Transport(name, value)
	net.Start("gry_set_server_option")
	net.WriteString(name)
	net.WriteString(value)
	net.SendToServer()
end

-- The real way to run a command of the server (the button options).
function UI.RunCommand(command)
	RunConsoleCommand(command)
end

-- The real way to send a message of the server that has no payload (the action options): the server checks the right again.
function UI.SendMessage(name)
	net.Start(name)
	net.SendToServer()
end

-- ---------------------------------------------------------------------------------------------------------
-- The controls
-- ---------------------------------------------------------------------------------------------------------

-- The text of the choice that has this value, or nil.
local function choiceText(choices, value)
	for _, choice in ipairs(choices) do
		if choice[2] == value then
			return choice[1]
		end
	end

	-- a number is written as the engine writes it ("7.500000" for the choice "7.5"): the same number is the same choice
	local number = tonumber(value)

	if number then
		for _, choice in ipairs(choices) do
			if tonumber(choice[2]) == number then
				return choice[1]
			end
		end
	end
end

-- Shows the value the server has in the control (without asking the server again).
local function syncValue(entry)
	local convar = entry.name and GetConVar(entry.name)

	if not convar or not IsValid(entry.control) then
		return
	end

	entry.syncing = true

	if entry.kind == "bool" then
		local want = convar:GetBool()

		if entry.control:GetChecked() ~= want then
			entry.control:SetValue(want)
		end
	elseif entry.kind == "choice" then
		local text = choiceText(entry.choices, convar:GetString())

		if text and entry.control:GetValue() ~= text then
			entry.control:SetValue(text)
		end
	end

	entry.syncing = false
end

-- Puts a control on or off: disabled (no mouse, dimmed, once: the outer panel carries the dimming) with the tooltip on the item that holds it,
-- which gets the mouse when the control itself does not.
local function apply(entry, isAdmin)
	local enabled, tooltip = UI.Decide(isAdmin)
	entry.admin = isAdmin

	for _, part in ipairs(entry.parts) do
		if IsValid(part) then
			part:SetEnabled(enabled)
			part:SetMouseInputEnabled(enabled)
		end
	end

	-- the inner controls are dimmed by their parent: not twice
	for _, part in ipairs(entry.inner) do
		if IsValid(part) then
			part:SetAlpha(255)
		end
	end

	for _, holder in ipairs(entry.holders) do
		if IsValid(holder) then
			holder:SetTooltip(tooltip)
		end
	end
end

-- The player asks for a value: the server is asked only when the player is an admin; otherwise (a click that got through) the control goes back
-- to what the server has.
local function request(entry, value)
	if entry.syncing then
		return
	end

	if not UI.IsAdmin() then
		syncValue(entry)

		return
	end

	entry.requestedAt = RealTime()
	UI.Transport(entry.name, value)
end

-- The look at the status and at the values, at most once a second (`now` is given so that a test can pass the time).
function UI.Poll(panel, now)
	if not panel.GryAdminEntries or now - panel.GryAdminPolled < POLL then
		return
	end

	panel.GryAdminPolled = now

	local isAdmin = UI.IsAdmin()

	for _, entry in ipairs(panel.GryAdminEntries) do
		if entry.admin ~= isAdmin then
			apply(entry, isAdmin)
		end

		if entry.name and now - entry.requestedAt >= HOLD then
			syncValue(entry)
		end
	end

	if IsValid(panel.GryAdminStatus) and panel.GryAdminStatusShown ~= isAdmin then
		panel.GryAdminStatusShown = isAdmin
		panel.GryAdminStatus:SetText(UI.StatusText(isAdmin))
	end
end

-- The panel looks after its own options: once, at the first one.
local function install(panel)
	if panel.GryAdminEntries then
		return
	end

	panel.GryAdminEntries = {}
	panel.GryAdminControls = {}
	panel.GryAdminPolled = RealTime()

	local previous = panel.Think

	panel.Think = function(self, ...)
		if previous then
			previous(self, ...)
		end

		UI.Poll(self, RealTime())
	end
end

-- The title of the section and the line that says whether the player is an admin. `into` (optional): a category of the panel (a nested control panel) that holds
-- the controls: it is its folding title that names the section, so only the status line is written there; the state of the options stays on `Panel`.
function UI.Section(Panel, title, into)
	install(Panel)

	if not into then
		Panel:Help(title)
	end

	Panel.GryAdminStatusShown = UI.IsAdmin()
	Panel.GryAdminStatus = (into or Panel):Help(UI.StatusText(Panel.GryAdminStatusShown))
end

-- One option of the server. kind: "bool" (a check box on the setting `convarName`), "choice" (a selector, opts.choices = {{text, value}, ...}),
-- "button" (a button that runs the server command opts.command, which checks the admin itself), "action" (a button, an action is never a check box: a click
-- asks GryMod.Confirm(opts.confirm) and on yes runs opts.onTick() or sends the net message opts.message with no payload; the server checks the right
-- again). Returns the control.
-- opts.into: a category of the panel that holds the control (the options of the server are still looked after by `Panel`); opts.help: the explanation, in a
-- small wrapped text under the control, so that the label can be short.
function GryMod.AdminOption(Panel, label, convarName, kind, opts)
	opts = opts or {}
	install(Panel)

	local into = opts.into or Panel

	local entry = {
		name = convarName,
		kind = kind,
		choices = opts.choices,
		requestedAt = -math.huge,
		syncing = false,
		parts = {},
		inner = {},
		holders = {}
	}

	local control

	if kind == "bool" then
		control = vgui.Create("DCheckBoxLabel", into)
		control:SetText(label)
		control:SetDark(true)
		into:AddItem(control)

		control.OnChange = function(_, value)
			request(entry, value and "1" or "0")
		end

		entry.parts = {control, control.Button}
		entry.inner = {control.Button}
		entry.holders = {control:GetParent()}
	elseif kind == "choice" then
		local title = into:Help(label)

		control = vgui.Create("DComboBox", into)
		control:SetSortItems(false)

		for _, choice in ipairs(opts.choices) do
			control:AddChoice(choice[1], choice[2])
		end

		control.OnSelect = function(_, _, _, data)
			request(entry, data)
		end

		into:AddItem(control)

		entry.parts = {control, title}
		entry.holders = {control:GetParent(), title:GetParent()}
	elseif kind == "action" then
		control = vgui.Create("DButton", into)
		control:SetText(label)

		-- the front prediction: a click that gets through for a player who is not an admin asks nothing and sends nothing (the server checks again)
		control.DoClick = function()
			if not UI.IsAdmin() then
				return
			end

			GryMod.Confirm(opts.confirm or (label .. "?"), function()
				if opts.onTick then
					opts.onTick()
				else
					UI.SendMessage(opts.message)
				end
			end)
		end

		into:AddItem(control)

		entry.parts = {control}
		entry.holders = {control:GetParent()}
	else
		control = vgui.Create("DButton", into)
		control:SetText(label)

		control.DoClick = function()
			if UI.IsAdmin() then
				UI.RunCommand(opts.command)
			end
		end

		into:AddItem(control)

		entry.parts = {control}
		entry.holders = {control:GetParent()}
	end

	entry.control = control
	Panel.GryAdminEntries[#Panel.GryAdminEntries + 1] = entry
	Panel.GryAdminControls[convarName or ((kind == "action" and "action:" .. tostring(opts.message or label)) or ("button:" .. tostring(opts.command)))] = control

	-- the item that holds it (and the one of its title) is how the tests and the tooltip find the control
	for _, holder in ipairs(entry.holders) do
		holder.GryAdminItem = true
	end

	if opts.help then
		into:ControlHelp(opts.help)
	end

	syncValue(entry)
	apply(entry, UI.IsAdmin())

	return control
end
