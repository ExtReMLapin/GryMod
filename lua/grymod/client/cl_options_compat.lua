-- The Compatibility page of the options menu: what belongs to a third-party addon has a page of its own, with one tab for each family of addons, so that the general
-- page stays about GryMod. The tabs: TFA and ARC9 (the suit's effects on their weapons, what the weapon icon of the quick menu does for them, and for ARC9 its own HUD) and
-- the other weapon bases (what is known about each). The suit's effects are the server's settings (administrators only, GryMod.AdminOption: the same white list, check boxes that show the state).
-- More tabs go here as more addons get a patch (lua/grymod/compat/, docs/compat.md).

local TAB_HEIGHT = 560

-- A tab: a scrolling panel with a panel of controls in it (GryMod.OptionsCategory and GryMod.AdminOption build on a control panel).
local function addTab(sheet, name, build, Panel)
	local scroll = vgui.Create("DScrollPanel", sheet)
	local root = vgui.Create("ControlPanel", scroll)

	root:Dock(TOP)

	-- the page of a tab has no title bar of its own (the tab's name is its title): a control panel shows one, "Label", unless it is hidden
	if IsValid(root.Header) then
		root.Header:SetVisible(false)
		root.Header:SetTall(0)
		root.Header.PerformLayout = function(self) self:SetTall(0) end
	end

	build(root, Panel)
	sheet:AddSheet(name, scroll)

	return root
end

-- The suit's effects on the weapons of a base: the same server settings for every base (lua/grymod/sh_suit_weapons.lua), so each tab shows them under the name of its base.
-- `Panel` is the menu panel itself: the administrators' controls are registered on it (GryMod.AdminOption), wherever they are drawn
local function suitEffects(root, Panel, base)
	root:Help("What the suit does to " .. base .. " weapons, with the original game's numbers. These are the server's settings (the same for every weapon base): only an administrator changes them.")

	local strength = GryMod.OptionsCategory(root, "Strength mode", true)

	GryMod.AdminOption(Panel, "Strength mode: stronger melee", "gry_suit_strength_melee", "bool", {into = strength, help = "A melee hit does more damage and pushes harder with the energy, up to 9 times with a full bar."})
	GryMod.AdminOption(Panel, "Strength mode: less recoil", "gry_suit_strength_recoil", "bool", {into = strength, help = "The kick of a shot is much smaller with the energy (about a third with a full bar)."})
	GryMod.AdminOption(Panel, "Strength mode: energy of a shot", "gry_suit_shot_cost", "choice", {
		into = strength,
		help = "The energy each shot takes in the strength mode. The original takes 7.5 of the bar.",
		choices = {
			{"Free", "0"},
			{"Half the original's", "3.75"},
			{"The original's (7.5)", "7.5"},
			{"Double", "15"}
		}
	})

	GryMod.AdminOption(Panel, "Strength mode: the calibre counts", "gry_suit_shot_cost_by_ammo", "bool", {into = strength, help = "A shot costs more energy with a bigger calibre: pistol and SMG rounds less, magnum, sniper and buckshot more. Off: the same price for every weapon, like the original game."})

	GryMod.AdminOption(Panel, "Melee: energy of a blow", "gry_suit_melee_cost", "choice", {
		into = strength,
		help = "Each melee blow takes energy in the strength mode (20 of the bar) and in the speed mode (10), like the original game's demo.",
		choices = {
			{"Free", "0"},
			{"Half the original's", "0.5"},
			{"The original's", "1"},
			{"Double", "2"}
		}
	})

	local speed = GryMod.OptionsCategory(root, "Speed mode", true)

	GryMod.AdminOption(Panel, "Speed mode: faster weapon handling", "gry_suit_handling", "bool", {into = speed, help = "Like the original game: a weapon is drawn, put away and raised faster (x1.75) and a melee swing is faster (x1.5)."})
	GryMod.AdminOption(Panel, "Speed mode: reload speed", "gry_suit_reload_rate", "choice", {
		into = speed,
		help = "The original game does not make a reload faster in the speed mode, so the default is the normal speed.",
		choices = {
			{"Normal (the original's)", "1"},
			{"x1.25", "1.25"},
			{"x1.5", "1.5"},
			{"x2", "2"}
		}
	})
end

local function tfaTab(root, Panel)
	suitEffects(root, Panel, "a TFA")

	local menu = GryMod.OptionsCategory(root, "Weapon menu")

	menu:Help("The weapon icon of the quick menu opens TFA's own menu (the attachments and the ammunition) for the weapon in your hands. TFA's server setting sv_tfa_cmenu must be on.")
end

local function arc9Tab(root, Panel)
	local hud = GryMod.OptionsCategory(root, "HUD", true)

	GryMod.OptionBox(hud, "Hide ARC9's own HUD", "gry_arc9_hide_hud", "ARC9 draws the weapon's name, the ammunition and the fire mode in the bottom left corner, under the minimap. Hidden while GryMod's HUD is up. ARC9's key hints and its customization menu stay, and none of ARC9's own settings is changed.")

	suitEffects(root, Panel, "an ARC9")

	local menu = GryMod.OptionsCategory(root, "Weapon menu")

	menu:Help("The weapon icon of the quick menu opens ARC9's customization menu for the weapon in your hands. While that menu is up the camouflage leaves the gun plain, so that the parts can be seen.")
end

local function othersTab(root)
	root:Help("Weapon bases other than TFA and ARC9. They only have what could be read in their source code: none of them was tried in a game yet.")

	local bases = GryMod.OptionsCategory(root, "What GryMod does with them", true)

	bases:Help("ArcCW, CW 2.0, FA:S 2: the weapon icon of the quick menu opens the base's own customization menu (read from the source, not tried). The fire mode shown by the HUD is read for ArcCW, CW 2.0 and FA:S 2 too. ARC9 has a tab of its own.")
	bases:Help("M9K: the fire mode shown by the HUD (single, automatic, shotgun). M9K has no customization menu to open.")
	bases:Help("The suit's effects on weapons (strength, speed) are for TFA and ARC9 weapons only for now.")
end

function GryMod.CompatOptionsPanel(Panel)
	Panel:AddControl("Label", {
		Text = "GryMod Compatibility"
	})

	local sheet = vgui.Create("DPropertySheet", Panel)

	sheet:SetTall(TAB_HEIGHT)
	Panel:AddItem(sheet)

	addTab(sheet, "TFA", tfaTab, Panel)
	addTab(sheet, "ARC9", arc9Tab, Panel)
	addTab(sheet, "Other weapon bases", othersTab, Panel)

	return sheet
end
