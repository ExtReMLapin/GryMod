-- The Compatibility page of the options menu: what belongs to a third-party addon has a page of its own, with one tab for each family of addons, so that the general
-- pages stay about GryMod. The tabs: "Suit effects" (what the suit does to the weapons of the bases that have a patch: the server's settings, administrators only, the same
-- for every base, so they are on one tab and nowhere else), TFA and ARC9 (what the weapon icon of the quick menu does for them, and for ARC9 its own HUD) and the other weapon
-- bases (what is known about each). The server's settings are GryMod.AdminOption: the same white list, check boxes that show the state.
-- More tabs go here as more addons get a patch (lua/grymod/compat/, docs/compat.md): GryMod.AddOptionTab("compat", "Name", function(root, Panel) ... end), see cl_options_tabs.lua.

-- The suit's effects on the weapons of a base: the server settings (lua/grymod/sh_suit_weapons.lua), the same for every base. `Panel` is the page itself: the administrators'
-- controls are registered on it (GryMod.AdminOption), wherever they are drawn (`root`, the tab).
local function suitEffectsTab(root, Panel)
	GryMod.OptionNote(root, "What the suit does to the weapons, with the original game's numbers. These are the server's settings (the same for every weapon base): only an administrator changes them. They work with TFA and ARC9 weapons for now.")

	GryMod.AdminUI.Section(Panel, "Suit effects on weapons", root)

	local status = Panel.GryAdminStatus
	local holder = IsValid(status) and status:GetParent()

	if holder and holder ~= root then
		holder.GryKind = "note"
	end

	GryMod.AdminOption(Panel, "Strength mode: stronger melee", "gry_suit_strength_melee", "bool", {into = root, help = "A melee hit does more damage and pushes harder with the energy, up to 9 times with a full bar."})
	GryMod.AdminOption(Panel, "Strength mode: less recoil", "gry_suit_strength_recoil", "bool", {into = root, help = "The kick of a shot is much smaller with the energy (about a third with a full bar)."})
	GryMod.AdminOption(Panel, "Strength mode: energy of a shot", "gry_suit_shot_cost", "choice", {
		into = root,
		help = "The energy each shot takes in the strength mode. The original takes 7.5 of the bar.",
		choices = {
			{"Free", "0"},
			{"Half the original's", "3.75"},
			{"The original's (7.5)", "7.5"},
			{"Double", "15"}
		}
	})

	GryMod.AdminOption(Panel, "Strength mode: the calibre counts", "gry_suit_shot_cost_by_ammo", "bool", {into = root, help = "A shot costs more energy with a bigger calibre: pistol and SMG rounds less, magnum, sniper and buckshot more. Off: the same price for every weapon, like the original game."})

	GryMod.AdminOption(Panel, "Melee: energy of a blow", "gry_suit_melee_cost", "choice", {
		into = root,
		help = "Each melee blow takes energy in the strength mode (20 of the bar) and in the speed mode (10), like the original game's demo.",
		choices = {
			{"Free", "0"},
			{"Half the original's", "0.5"},
			{"The original's", "1"},
			{"Double", "2"}
		}
	})

	GryMod.AdminOption(Panel, "Speed mode: faster weapon handling", "gry_suit_handling", "bool", {into = root, help = "Like the original game: a weapon is drawn, put away and raised faster (x1.75) and a melee swing is faster (x1.5)."})
	GryMod.AdminOption(Panel, "Speed mode: reload speed", "gry_suit_reload_rate", "choice", {
		into = root,
		help = "The original game does not make a reload faster in the speed mode, so the default is the normal speed.",
		choices = {
			{"Normal (the original's)", "1"},
			{"x1.25", "1.25"},
			{"x1.5", "1.5"},
			{"x2", "2"}
		}
	})
end

local function tfaTab(root)
	GryMod.OptionNote(root, "The weapon icon of the quick menu opens TFA's own menu (the attachments and the ammunition) for the weapon in your hands. TFA's server setting sv_tfa_cmenu must be on.")
	GryMod.OptionNote(root, "What the suit does to TFA weapons (strength, speed) is in the Suit effects tab.")
end

local function arc9Tab(root)
	GryMod.OptionBox(root, "Hide ARC9's own HUD", "gry_arc9_hide_hud", "ARC9 draws the weapon's name, the ammunition and the fire mode in the bottom left corner, under the minimap. Hidden while GryMod's HUD is up. ARC9's key hints and its customization menu stay, and none of ARC9's own settings is changed.")
	GryMod.OptionNote(root, "The weapon icon of the quick menu opens ARC9's customization menu for the weapon in your hands. While that menu is up the camouflage leaves the gun plain, so that the parts can be seen.")
	GryMod.OptionNote(root, "What the suit does to ARC9 weapons (strength, speed) is in the Suit effects tab.")
end

local function othersTab(root)
	GryMod.OptionNote(root, "Weapon bases other than TFA and ARC9. They only have what could be read in their source code: none of them was tried in a game yet.")
	GryMod.OptionNote(root, "ArcCW, CW 2.0, FA:S 2: the weapon icon of the quick menu opens the base's own customization menu (read from the source, not tried). The fire mode shown by the HUD is read for ArcCW, CW 2.0 and FA:S 2 too. ARC9 has a tab of its own.")
	GryMod.OptionNote(root, "M9K: the fire mode shown by the HUD (single, automatic, shotgun). M9K has no customization menu to open.")
	GryMod.OptionNote(root, "The suit's effects on weapons (strength, speed) are for TFA and ARC9 weapons only for now.")
end

GryMod.AddOptionTab("compat", "Suit effects", suitEffectsTab, 10)
GryMod.AddOptionTab("compat", "TFA", tfaTab, 20)
GryMod.AddOptionTab("compat", "ARC9", arc9Tab, 30)
GryMod.AddOptionTab("compat", "Other weapon bases", othersTab, 40)

-- The page: title, filter, tabs.
function GryMod.CompatOptionsPanel(Panel)
	return GryMod.BuildOptionsPage(Panel, "compat")
end
