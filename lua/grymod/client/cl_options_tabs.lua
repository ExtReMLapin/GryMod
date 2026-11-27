-- The pages of the options menu (the spawn menu's Options tab, GryMod category) and their TABS.
--
-- The menu has five entries, one for each subject a player thinks about: the HUD and the keys, the suit and the vision, the radar and the maps, the
-- compatibility with other addons, the server. Each entry is a PAGE: a title, a filter field and a property sheet whose tabs hold the settings (about eight to
-- ten at the most in a tab, so that a tab fits the screen). The menu gives a page ONE scroll bar, its own: the sheet is made exactly as tall as the tab that is
-- shown (nothing inside a tab scrolls by itself), so there is never a scroll bar in another one.
--
-- To add a setting: put it in a tab that is already there (a function that builds it is registered below its tab's name).
-- To add a tab (an addon's compatibility, a new subject), from any file loaded after this one:
--
--     GryMod.AddOptionTab("compat", "My addon", function(root, Panel)
--         GryMod.OptionBox(root, "A short label", "my_convar", "The explanation, in a few words.")
--         GryMod.AdminOption(Panel, "A server setting", "gry_name_in_the_white_list", "bool", {into = root, help = "..."})
--     end)
--
-- `page`: "hud", "suit", "radar", "compat" or "server" (GryMod.OptionPages). `root`: the control panel of the tab (it has Help, CheckBox, NumSlider, AddItem, AddControl,
-- ControlHelp...; GryMod.OptionBox, GryMod.OptionSlider and GryMod.OptionNote build on it). `Panel`: the panel of the whole page, which looks after the server
-- settings (GryMod.AdminOption wants it first, and `into = root` to draw them in the tab). A tab of the same name in the same page is replaced (a file that is run again),
-- an optional 4th argument orders the tabs (the ones of this addon are 10, 20, 30...; the default puts yours after them, in the order they are added). A tab that
-- fails to build shows its error and does not take the page with it. The filter field looks at the label and the explanation of every control of the page: nothing to do for
-- that, but write a paragraph that is no setting with GryMod.OptionNote (it is found by the filter as one block, and never glued to the control under it).

GryMod = GryMod or {}

-- The entries of the menu, in this order: class (the name the spawn menu keeps), the name of the entry, the title at the top of the page, and `admin` for a page whose settings are the
-- server's (a line says whether you are an administrator).
local previousPages = {}

for _, page in ipairs(GryMod.OptionPages or {}) do
	previousPages[page.id] = page
end

GryMod.OptionPages = {
	{id = "hud", class = "HUD", name = "HUD and controls", title = "GryMod HUD and controls"},
	{id = "suit", class = "Suit", name = "Suit and vision", title = "GryMod Suit and vision"},
	{id = "radar", class = "Radar", name = "Radar and map", title = "GryMod Radar and map"},
	{id = "compat", class = "Compat", name = "Compatibility", title = "GryMod Compatibility"},
	{id = "server", class = "Server", name = "Server (admins)", title = "GryMod Server settings", admin = true}
}

local pageById = {}

-- (this file run again, a reload while working on it, keeps the tabs that the other files registered)
for _, page in ipairs(GryMod.OptionPages) do
	local before = previousPages[page.id]

	pageById[page.id] = page
	page.tabs = before and before.tabs or {}
	page.serial = before and before.serial or nil
end

local DEFAULT_ORDER = 1000
local FILTER_HINT = "Filter the settings of this page"
local CONTROL_CLASSES = {DCheckBoxLabel = true, DNumSlider = true, DComboBox = true, DBinder = true, DColorMixer = true, DButton = true, CtrlListBox = true}

-- Adds (or replaces) a tab of a page; see the top of this file.
function GryMod.AddOptionTab(pageId, name, build, order)
	local page = pageById[pageId]

	if not page then
		error("GryMod.AddOptionTab: there is no page \"" .. tostring(pageId) .. "\" (pages: hud, suit, radar, compat, server)", 2)
	end

	for _, tab in ipairs(page.tabs) do
		if tab.name == name then
			tab.build = build
			tab.order = order or tab.order

			return
		end
	end

	page.serial = (page.serial or 0) + 1
	page.tabs[#page.tabs + 1] = {name = name, build = build, order = order or DEFAULT_ORDER, serial = page.serial}
end

-- Takes a tab away (for a file that stops offering it, and for the tests).
function GryMod.RemoveOptionTab(pageId, name)
	local page = pageById[pageId]

	if not page then
		return
	end

	for i, tab in ipairs(page.tabs) do
		if tab.name == name then
			table.remove(page.tabs, i)

			return
		end
	end
end

-- The tabs of a page in the order they are shown.
function GryMod.OptionTabList(pageId)
	local page = pageById[pageId]
	local list = {}

	if page then
		for i, tab in ipairs(page.tabs) do
			list[i] = tab
		end

		table.sort(list, function(a, b)
			if a.order ~= b.order then
				return a.order < b.order
			end

			return a.serial < b.serial
		end)
	end

	return list
end

-- The holder of a panel in a tab root: the panel of the root that holds it (the control panel puts each item in a small panel of its own).
local function holderIn(root, panel)
	while panel and panel:GetParent() ~= root do
		panel = panel:GetParent()
	end

	return panel
end

-- A paragraph that is no setting (an explanation of the tab, what is known about an addon): the filter finds it as a block of its own.
function GryMod.OptionNote(form, text)
	local label = form:Help(text)
	local holder = holderIn(form, label)

	if holder then
		holder.GryKind = "note"
	end

	return label
end

-- ---------------------------------------------------------------------------------------------------------
-- The tab: a control panel that is as tall as what is in it
-- ---------------------------------------------------------------------------------------------------------

-- The control panel of a tab: no title bar (the tab's name is its title), no stretching (its own height is the height of what it holds), and the explanations
-- under the controls are marked, so that the filter keeps each one with its control.
local function newRoot(sheet)
	local root = vgui.Create("ControlPanel", sheet)

	root.GryTabRoot = true
	root.NoStretchY = true

	-- a control panel slides open when it is made (its height grows over a few frames, and the sheet would follow it): the tab has no header to open or close, it is
	-- there at once, as tall as what it holds
	root.animSlide = {Run = function() end, Start = function() end, Finished = true}

	if IsValid(root.Header) then
		root.Header:SetVisible(false)
		root.Header:SetTall(0)
		root.Header.PerformLayout = function(self) self:SetTall(0) end
	end

	root:DockPadding(0, 8, 0, 8)

	-- what is in the tab grows when its labels wrap (the width is known after the first layout): the sheet follows
	root.OnSizeChanged = function()
		if IsValid(sheet) then
			sheet:InvalidateLayout()
		end
	end

	local controlHelp = root.ControlHelp

	root.ControlHelp = function(self, text)
		local label = controlHelp(self, text)
		local holder = IsValid(label) and holderIn(self, label)

		if holder then
			holder.GryKind = "help"
		end

		return label
	end

	return root
end

-- Lays a panel and everything in it out NOW, widths first (top down: a wrapped text needs its width) and heights after (bottom up: a panel is as tall as what it holds).
-- Without it the height of a tab settles one level of panels per frame and the sheet is cut for a moment each time a tab is chosen.
local function layoutDown(panel)
	panel:InvalidateLayout(true)

	for _, child in ipairs(panel:GetChildren()) do
		layoutDown(child)
	end
end

local function layoutUp(panel)
	for _, child in ipairs(panel:GetChildren()) do
		layoutUp(child)
	end

	panel:InvalidateLayout(true)
end

-- The sheet is as tall as the tab that is shown (the menu's own scroll bar does the scrolling), at every layout and when another tab is chosen.
local function sizeToTab(sheet)
	local base = sheet.PerformLayout

	sheet.PerformLayout = function(self, w, h)
		base(self, w, h)

		local active = self:GetActiveTab()

		if not active then
			return
		end

		local content = active:GetPanel()

		if not IsValid(content) then
			return
		end

		-- a few passes: what grows (a wrapped text, a panel that holds one) can make its parent grow in the next one
		local last = -1

		for _ = 1, 6 do
			layoutDown(content)
			layoutUp(content)

			if content:GetTall() == last then
				break
			end

			last = content:GetTall()
		end

		-- (not content:GetY(): the sheet slides the shown tab in when it changes, so its position is not where it ends; it ends under the tabs)
		local want = active:GetTall() - 8 + content:GetTall() + self:GetPadding()

		if self:GetTall() ~= want then
			self:SetTall(want)

			local parent = self:GetParent()

			if IsValid(parent) then
				parent:InvalidateLayout()
			end
		end
	end
end

-- One tab of a page: its control panel, built by its function (a failure is shown in the tab and printed, the page goes on).
local function addTab(sheet, tab, Panel)
	local root = newRoot(sheet)
	local ok, err = pcall(tab.build, root, Panel)

	if not ok then
		ErrorNoHalt("GryMod options, tab \"" .. tostring(tab.name) .. "\": " .. tostring(err) .. "\n")
		root:Help("This tab could not be built: " .. tostring(err))
	end

	local item = sheet:AddSheet(tab.name, root, nil, false, true)

	item.Tab.GryName = tab.name
	sheet.GryTabs[#sheet.GryTabs + 1] = {name = tab.name, root = root, item = item}

	return item
end

-- ---------------------------------------------------------------------------------------------------------
-- The filter
-- ---------------------------------------------------------------------------------------------------------

local function collectTexts(panel, out)
	local class = panel.ClassName

	if class ~= "DTextEntry" and class ~= "DBinder" and isfunction(panel.GetText) then
		local ok, text = pcall(panel.GetText, panel)

		if ok and isstring(text) and text ~= "" then
			out[#out + 1] = text
		end
	end

	for _, child in ipairs(panel:GetChildren()) do
		collectTexts(child, out)
	end
end

local function hasControl(panel)
	if CONTROL_CLASSES[panel.ClassName] and not panel.Header then
		return true
	end

	for _, child in ipairs(panel:GetChildren()) do
		if hasControl(child) then
			return true
		end
	end

	return false
end

-- The settings of a tab, in the order they are shown: a group is a heading (a label that names the control under it), the control, and its explanation. A note is a group
-- of its own. Each group has the text that the filter looks in (lower case).
local function groupsOf(root)
	local groups, current = {}, nil

	local function flush()
		if current then
			current.text = string.lower(table.concat(current.texts, " "))
			groups[#groups + 1] = current
		end

		current = nil
	end

	for _, holder in ipairs(root:GetChildren()) do
		if holder.ClassName == "DSizeToContents" then
			local kind = holder.GryKind or (hasControl(holder) and "control" or "head")

			if kind == "note" or ((kind == "control" or kind == "head") and current and current.control) then
				flush()
			end

			current = current or {holders = {}, texts = {}}
			current.holders[#current.holders + 1] = holder
			collectTexts(holder, current.texts)

			if kind == "control" then
				current.control = true
			elseif kind == "note" then
				current.note = true
				flush()
			end
		end
	end

	flush()

	return groups
end

-- Shows only the settings of the page whose label or explanation holds `text` (no case, no pattern): returns how many each tab has left ({[tab name] = n}),
-- puts that number after the tab's name, and goes to the first tab that has one when the shown tab has none. An empty text brings everything back.
function GryMod.FilterOptions(Panel, text)
	local state = Panel.GryOptionsPage

	if not state then
		return {}
	end

	text = string.lower(string.Trim(tostring(text or "")))

	local sheet, counts = state.sheet, {}

	for _, tab in ipairs(sheet.GryTabs) do
		local count = 0

		for _, group in ipairs(groupsOf(tab.root)) do
			local show = text == "" or string.find(group.text, text, 1, true) ~= nil

			for _, holder in ipairs(group.holders) do
				holder:SetVisible(show)
			end

			if show and (group.control or group.note) then
				count = count + 1
			end
		end

		counts[tab.name] = count

		local label = text == "" and tab.name or (tab.name .. " (" .. count .. ")")

		if tab.item.Tab:GetText() ~= label then
			tab.item.Tab:SetText(label)
			tab.item.Tab:InvalidateLayout(true)
		end

		tab.item.Tab:SetAlpha((text ~= "" and count == 0) and 110 or 255)
		tab.root:InvalidateLayout()
	end

	if text ~= "" then
		local active = sheet:GetActiveTab()

		if IsValid(active) and counts[active.GryName] == 0 then
			for _, tab in ipairs(sheet.GryTabs) do
				if counts[tab.name] > 0 then
					sheet:SetActiveTab(tab.item.Tab)

					break
				end
			end
		end
	end

	sheet:InvalidateLayout()

	if IsValid(sheet.tabScroller) then
		sheet.tabScroller:InvalidateLayout()
	end

	return counts
end

-- ---------------------------------------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------------------------------------

-- The panel of a page of the menu: title, filter, the sheet of tabs. Returns the sheet.
function GryMod.BuildOptionsPage(Panel, pageId)
	local page = pageById[pageId]

	if not page then
		error("GryMod.BuildOptionsPage: there is no page \"" .. tostring(pageId) .. "\"", 2)
	end

	Panel:AddControl("Label", {
		Text = page.title
	})

	if page.admin then
		-- one line for the whole page: whether you are an administrator (the controls are looked after by this panel)
		GryMod.AdminUI.Section(Panel, page.title, Panel)
	end

	local filter = vgui.Create("DTextEntry", Panel)

	filter:SetUpdateOnType(true)

	if isfunction(filter.SetPlaceholderText) then
		filter:SetPlaceholderText(FILTER_HINT)
	end

	Panel:AddItem(filter)

	local sheet = vgui.Create("DPropertySheet", Panel)

	sheet.GryTabs = {}
	sizeToTab(sheet)
	Panel:AddItem(sheet)

	for _, tab in ipairs(GryMod.OptionTabList(pageId)) do
		addTab(sheet, tab, Panel)
	end

	Panel.GryOptionsPage = {sheet = sheet, filter = filter, page = page}

	filter.OnValueChange = function(_, value)
		GryMod.FilterOptions(Panel, value)
	end

	return sheet
end

-- The same tabs, one after the other on the panel itself with no sheet: what a script or a test wants when it needs every setting of some pages on one panel (the
-- builders then make their folding categories, as they did before the tabs). The settings of the server are not drawn (they have their own page).
function GryMod.BuildOptionsFlat(Panel, pageIds)
	for _, pageId in ipairs(pageIds) do
		for _, tab in ipairs(GryMod.OptionTabList(pageId)) do
			local ok, err = pcall(tab.build, Panel, Panel)

			if not ok then
				ErrorNoHalt("GryMod options, tab \"" .. tostring(tab.name) .. "\": " .. tostring(err) .. "\n")
			end
		end
	end
end
