-- Tests of the Compatibility page of the options menu (GryMod.CompatOptionsPanel, lua/grymod/client/cl_options_compat.lua), GLuaTest format, client realm. The settings that
-- belong to a third-party addon do not go in the general page: they have a page of their own with one TAB for each family of addons (TFA, the other weapon bases), and the
-- general page's server section no longer holds the suit's effects on weapons. Each case names the change that makes it fail.

local panels

local function make()
	local panel = vgui.Create("ControlPanel")

	panels[#panels + 1] = panel

	return panel
end

-- every text of the labels, check boxes and buttons under a panel
local function texts(panel, into)
	into = into or {}

	if panel.GetText and isfunction(panel.GetText) then
		local ok, text = pcall(panel.GetText, panel)

		if ok and isstring(text) and text ~= "" then
			into[#into + 1] = text
		end
	end

	for _, child in ipairs(panel:GetChildren()) do
		texts(child, into)
	end

	return into
end

local function has(list, wanted)
	for _, text in ipairs(list) do
		if string.find(text, wanted, 1, true) then
			return true
		end
	end

	return false
end

-- the property sheet under a panel and the names of its tabs
local function sheetOf(panel)
	if panel.GetItems and panel.AddSheet then
		return panel
	end

	for _, child in ipairs(panel:GetChildren()) do
		local found = sheetOf(child)

		if found then
			return found
		end
	end

	return nil
end

local function tabNames(sheet)
	local names = {}

	for _, item in ipairs(sheet:GetItems()) do
		names[#names + 1] = item.Tab:GetText()
	end

	return names
end

return {
	groupName = "GryMod options: the Compatibility page",
	beforeEach = function()
		panels = {}
	end,
	afterEach = function()
		for _, panel in ipairs(panels) do
			if IsValid(panel) then
				panel:Remove()
			end
		end
	end,
	cases = {
		{
			-- fails without the page, or when it has no tabs (everything would be in one long list again)
			name = "the page exists and has one tab for TFA, one for ARC9 and one for the other weapon bases",
			func = function()
				expect(isfunction(GryMod.CompatOptionsPanel)).to.beTrue()

				local panel = make()

				GryMod.CompatOptionsPanel(panel)

				local sheet = sheetOf(panel)

				expect(sheet ~= nil).to.beTrue()

				local names = tabNames(sheet)

				expect(table.concat(names, ",")).to.equal("TFA,ARC9,Other weapon bases")
			end
		},
		{
			-- fails when a setting of the suit's effects on TFA weapons is not on the TFA tab (the owner asked for them under Compatibility, in a TFA category)
			name = "the TFA tab holds the suit's effects on weapons, the other tab says what is known about the other bases",
			func = function()
				local panel = make()

				GryMod.CompatOptionsPanel(panel)

				local all = texts(panel)

				for _, wanted in ipairs({"Speed mode: faster weapon handling", "Speed mode: reload speed", "Strength mode: stronger melee", "Strength mode: less recoil", "Strength mode: energy of a shot"}) do
					expect(has(all, wanted)).to.beTrue()
				end

				for _, base in ipairs({"ARC9", "ArcCW", "CW 2.0", "FA:S 2", "M9K", "Hide ARC9's own HUD"}) do
					expect(has(all, base)).to.beTrue()
				end
			end
		},
		{
			-- fails when the settings are still in the general page's server section too (two places for one setting)
			name = "the general page's server section no longer holds them",
			func = function()
				local panel = make()

				GryMod.GryOptionschute(panel)

				local all = texts(panel)

				expect(has(all, "Strength mode: stronger melee")).to.beFalse()
				expect(has(all, "Speed mode: faster weapon handling")).to.beFalse()
				expect(has(all, "Movement speeds")).to.beTrue() -- the section itself is still there
			end
		},
		{
			-- fails when the page is not offered in the menu (the spawn menu's Options tab) next to the two other pages
			name = "the page is registered in the menu with the two others",
			func = function()
				local added = {}
				local real = spawnmenu.AddToolMenuOption

				spawnmenu.AddToolMenuOption = function(tab, category, class, name, ...) added[#added + 1] = {tab = tab, category = category, class = class, name = name} end

				local ok, err = pcall(GryMod.GryOptionschuteOptionmenu)

				spawnmenu.AddToolMenuOption = real

				if not ok then
					error(err, 0)
				end

				local classes = {}

				for _, entry in ipairs(added) do
					classes[entry.class] = entry.category
				end

				expect(classes.Config).to.equal("GryMod")
				expect(classes.Radar).to.equal("GryMod")
				expect(classes.Compat).to.equal("GryMod")
			end
		}
	}
}
