-- The options menu of the big map: a page of its own, "Big map", next to Config and Radar and map in the GryMod category of the Options tab. The settings are
-- written when the player changes a control, never when the panel opens. The key picker is the factory's (cl_key_binder.lua), like the other keys.

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}

local Map = GryMod.Map

-- The line under the key picker: what the game already does with the key (a warning), or the default.
local function keyStatus(code)
	if code and code > 0 then
		return GryMod.KeyBinder.ConflictText(code, "gry_map") or "This key is free in the game."
	end

	return "Default: M, until you choose another key here. A `bind <key> gry_map` in the console works too."
end

-- The loading looks the map knows (the registry), with their labels. Called when the panel is built.
local function lookChoices()
	local choices = {}

	for _, name in ipairs(Map.Fx.List()) do
		local look = Map.Fx.Get(name)

		choices[#choices + 1] = {name = name, label = look and look.label or name}
	end

	return choices
end

function GryMod.MapOptionsPanel(Panel)
	Panel:AddControl("Label", {
		Text = "GryMod Big map"
	})

	local form = GryMod.OptionsCategory(Panel, "Big map", true)

	GryMod.OptionBox(form, "Big map", "gry_map_enable", "A map of the whole level on a key: the wheel zooms toward the mouse, a drag moves it. The game goes on while it is open.")

	form:Help("Key that opens the big map")

	local binder = vgui.Create("DBinder")

	binder:SetValue(GetConVar("gry_map_key"):GetInt())
	form:AddItem(binder)

	local status = form:Help(keyStatus(Map.Key.Chosen()))

	binder.OnChange = function(self, code)
		if not Map.Key.SetKey(code) then
			self:SetValue(Map.Key.Chosen())
		end

		status:SetText(keyStatus(Map.Key.Chosen()))
	end

	GryMod.OptionBox(form, "Crysis PDA frame", "gry_map_chrome", "Draw the map in the frame of the original Crysis PDA map (its title, status strip, DONE button and opening). Off: the plain panel. Takes effect at the next opening.")
	GryMod.OptionBox(form, "Grid", "gry_map_grid", "The 8 x 8 grid with the letters A to H and the numbers 1 to 8.")
	GryMod.OptionBox(form, "Finished objectives", "gry_map_finished", "Show the objectives that are done or failed, greyed. Off: only the active ones.")

	form:Help("Look of the tiles while they load")

	local combo = vgui.Create("DComboBox")

	combo.GryConVar = "gry_map_loading_fx"
	combo:SetSortItems(false)

	local current = Map.Settings.LoadingFx()

	-- the look that is saved is shown without choosing it (choosing writes the setting: OnSelect is put on after, as for the tile size of the minimap)
	for _, choice in ipairs(lookChoices()) do
		combo:AddChoice(choice.label, choice.name)

		if choice.name == current then
			combo:SetValue(choice.label)
		end
	end

	combo.OnSelect = function(_, _, _, data)
		RunConsoleCommand("gry_map_loading_fx", tostring(data))
	end

	form:AddItem(combo)
end

function GryMod.MapOptionsMenu()
	spawnmenu.AddToolMenuOption("Options", "GryMod", "BigMap", "Big map", "", "", GryMod.MapOptionsPanel)
end

hook.Add("PopulateToolMenu", "GryMod big map options", GryMod.MapOptionsMenu)
