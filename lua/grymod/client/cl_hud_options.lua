-- The HUD settings: one saved switch (gry_hud_<name>, 1 or 0) for each element of the interface, so that every
-- piece can be turned off. The original game has no such switches (its options only offer the four colour sets
-- and the crosshair style); these are GryMod's own, kept in one list so that the options menu, the pieces that
-- check them and the tests all read the same table.

GryMod = GryMod or {}

local Options = {}
GryMod.HUDOptions = Options

-- In the order of the menu.
Options.List = {
	{name = "status", label = "Health, energy and ammo panel", help = "The panel at the bottom right"},
	{name = "radar", label = "Compass and radar panel", help = "The panel at the bottom left"},
	{name = "crosshair", label = "Crosshair", help = "The Crysis crosshair (the Half-Life 2 one is hidden when it is on)"},
	{name = "damage", label = "Damage direction arcs", help = "Arcs around the crosshair, on the side the damage came from"},
	{name = "hit", label = "Hit marker", help = "The crosshair blinks when you hurt something"},
	{name = "grenade", label = "Grenade warning", help = "The red hexagon on a grenade coming at you"},
	{name = "binoculars", label = "Binoculars", help = "The binoculars screen while you zoom"},
	{name = "quickmenu", label = "Quick menu", help = "The suit mode wheel (hold its key, point, release)"},
	{name = "boot", label = "Start-up and reboot sequences", help = "The log when you spawn, the shutdown animation and the reboot after a malfunction, with their sounds"}
}

local byName = {}
local convars = {}

for _, option in ipairs(Options.List) do
	byName[option.name] = option
	convars[option.name] = CreateClientConVar("gry_hud_" .. option.name, "1", true, false, option.help)
end

function Options.Find(name)
	return byName[name]
end

-- Whether this element is switched on (an element that has no switch is on).
function Options.Enabled(name)
	local convar = convars[name]

	return not convar or convar:GetBool()
end

-- Switches every element back on.
function Options.Reset()
	for _, convar in pairs(convars) do
		convar:SetString(convar:GetDefault())
	end
end

concommand.Add("gry_hud_reset", function()
	Options.Reset()
end)
