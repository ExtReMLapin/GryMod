-- Tests of the options page of the big map (lua/grymod/client/map/options.lua, GryMod.MapOptionsPanel), GLuaTest format, client realm. The page is a third entry of
-- the GryMod category of the Options tab, next to Config and Radar and map: the switch, the key, the Crysis PDA frame, the grid, the finished objectives and the loading look. Opening
-- the page writes nothing. The stand-ins (RunConsoleCommand, spawnmenu.AddToolMenuOption) are put back in afterEach inside a pcall, also when a case failed.

local function walk(panel, found)
	found = found or {}

	for _, child in ipairs(panel:GetChildren()) do
		found[#found + 1] = child
		walk(child, found)
	end

	return found
end

-- the controls in the order they were made: "label:<title>", "box:<convar>", "binder", "combo:<convar>"
local function markers(panel)
	local order = {}

	for _, p in ipairs(walk(panel)) do
		if p.ClassName == "ControlPanel" and p.Header and (p.Header:GetText() == "Big map") then
			order[#order + 1] = "label:Big map"
		elseif p.ClassName == "DCheckBoxLabel" and p.Button then
			order[#order + 1] = "box:" .. tostring(p.Button:GetTable().m_strConVar)
		elseif p.ClassName == "DBinder" then
			order[#order + 1] = "binder"
		elseif p.ClassName == "DComboBox" then
			order[#order + 1] = "combo:" .. tostring(p.GryConVar)
		end
	end

	return order
end

return {
	groupName = "GryMod big map options page",
	beforeEach = function(state)
		state.realRun = RunConsoleCommand
		state.realAdd = spawnmenu.AddToolMenuOption
		state.writes = {}
		state.panel = nil

		RunConsoleCommand = function(name, value)
			state.writes[#state.writes + 1] = tostring(name):lower() .. "=" .. tostring(value)
		end
	end,
	afterEach = function(state)
		pcall(function()
			RunConsoleCommand = state.realRun
			spawnmenu.AddToolMenuOption = state.realAdd

			if state.panel and IsValid(state.panel) then
				state.panel:Remove()
			end
		end)
	end,
	cases = {
		-- fails without GryMod.MapOptionsPanel (the file is missing) or when a control is left out or moved
		{
			name = "the page holds, in this order: the Big map category, the switch, the key picker, the Crysis PDA frame, the grid, the finished objectives, the NPC contacts, the player's own points and the loading look",
			func = function(state)
				expect(isfunction(GryMod.MapOptionsPanel)).to.beTrue()

				state.panel = vgui.Create("ControlPanel")
				GryMod.MapOptionsPanel(state.panel)

				expect(table.concat(markers(state.panel), "\n")).to.equal(table.concat({
					"label:Big map",
					"box:gry_map_enable",
					"binder",
					"box:gry_map_chrome",
					"box:gry_map_grid",
					"box:gry_map_finished",
					"box:gry_map_contacts",
					"box:gry_map_waypoints",
					"combo:gry_map_loading_fx"
				}, "\n"))
			end
		},
		-- fails when the button that takes the player's points away does so without asking, or does not take them
		{
			name = "the button 'Remove my objective points of this map' asks first, and takes the points away only on yes",
			func = function(state)
				local W = GryMod.Map.Waypoints
				local realConfirm, realIO = GryMod.Confirm, W.IO
				local asked, yes = 0, nil

				W.IO = {Read = function() return nil end, Write = function() end, CreateDir = function() end}
				W.Reset()
				GryMod.Confirm = function(text, onYes) asked = asked + 1 yes = onYes end

				local ok, err = pcall(function()
					state.panel = vgui.Create("ControlPanel")
					GryMod.MapOptionsPanel(state.panel)

					local button

					for _, p in ipairs(walk(state.panel)) do
						if p.ClassName == "DButton" and p:GetText() == "Remove my objective points of this map" then
							button = p
						end
					end

					expect(button ~= nil).to.beTrue()
					W.Add(0, 0, 0, "Camp")
					button:DoClick()
					expect(asked).to.equal(1)
					expect(#W.List()).to.equal(1) -- asked, not done
					yes()
					expect(#W.List()).to.equal(0)
				end)

				GryMod.Confirm, W.IO = realConfirm, realIO
				W.Reset()

				if not ok then
					error(err, 0)
				end
			end
		},
		-- fails when opening the page writes a setting (a combo box that selects its saved line writes it)
		{
			name = "building the page writes nothing, and shows the look that is saved without choosing it",
			func = function(state)
				state.panel = vgui.Create("ControlPanel")
				GryMod.MapOptionsPanel(state.panel)

				expect(table.concat(state.writes, ",")).to.equal("")

				local combo

				for _, p in ipairs(walk(state.panel)) do
					if p.ClassName == "DComboBox" then
						combo = p
					end
				end

				expect(combo ~= nil).to.beTrue()
				expect(combo:GetValue()).to.equal(GryMod.Map.Fx.Get(GryMod.Map.Settings.LoadingFx()) and GryMod.Map.Fx.Get(GryMod.Map.Settings.LoadingFx()).label or GryMod.Map.Settings.LoadingFx())

				-- choosing a look writes the setting
				combo.OnSelect(combo, 1, "Glitch", "glitch")
				expect(state.writes[1]).to.equal("gry_map_loading_fx=glitch")
			end
		},
		-- fails when a registered look is not offered
		{
			name = "every look of the registry is a choice of the loading look box, with its label",
			func = function(state)
				local Fx = GryMod.Map.Fx

				Fx.Register("test_look", {label = "A test look", waiting = function() end, arrived = function() end})

				local ok, err = pcall(function()
					state.panel = vgui.Create("ControlPanel")
					GryMod.MapOptionsPanel(state.panel)

					local combo

					for _, p in ipairs(walk(state.panel)) do
						if p.ClassName == "DComboBox" then
							combo = p
						end
					end

					local found = false

					for id = 1, #Fx.List() do
						found = found or combo:GetOptionData(id) == "test_look"
					end

					expect(found).to.beTrue()
				end)

				Fx.Unregister("test_look")

				if not ok then
					error(err, 0)
				end
			end
		},
		-- fails when the page is not registered in the tool menu, or when it takes the place of another
		{
			name = "the page is added to the tool menu (Options, GryMod, 'Big map') by its own hook, and the two other entries are still the Config and Radar menus' own",
			func = function(state)
				local added = {}

				spawnmenu.AddToolMenuOption = function(tab, category, name, label, command, config, builder)
					added[#added + 1] = {tab = tab, category = category, name = name, label = label, builder = builder}
				end

				local ok, err = pcall(GryMod.MapOptionsMenu)

				spawnmenu.AddToolMenuOption = state.realAdd

				if not ok then
					error(err, 0)
				end

				expect(#added).to.equal(1)
				expect(added[1].tab).to.equal("Options")
				expect(added[1].category).to.equal("GryMod")
				expect(added[1].name).to.equal("BigMap")
				expect(added[1].label).to.equal("Big map")
				expect(added[1].builder).to.equal(GryMod.MapOptionsPanel)
				expect(hook.GetTable().PopulateToolMenu["GryMod big map options"]).to.equal(GryMod.MapOptionsMenu)
				-- the existing hook still makes the two menus of the others
				expect(hook.GetTable().PopulateToolMenu.PopulateToolMenu).to.equal(GryMod.GryOptionschuteOptionmenu)
			end
		}
	}
}
