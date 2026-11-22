-- Tests of the minimap section of the options panel (GryMod.MinimapOptions in cl_options.lua), GLuaTest format, client realm. Every control
-- is bound to its convar (the settings are saved and opening the panel writes nothing), and the button that clears the cache goes through the
-- Cache module when there is one and does nothing (with a message) when there is not.

local function walk(panel, found)
	found = found or {}

	for _, child in ipairs(panel:GetChildren()) do
		found[#found + 1] = child
		walk(child, found)
	end

	return found
end

local function checkBoxOn(panel, convarName)
	for _, p in ipairs(walk(panel)) do
		if p.ClassName == "DCheckBoxLabel" and p.Button and p.Button:GetTable().m_strConVar == convarName then
			return p
		end
	end
end

local function sliderOn(panel, convarName)
	for _, p in ipairs(walk(panel)) do
		if p.ClassName == "DNumSlider" and p.Scratch and p.Scratch:GetTable().m_strConVar == convarName then
			return p
		end
	end
end

local function comboOn(panel, convarName)
	for _, p in ipairs(walk(panel)) do
		if p.ClassName == "DComboBox" and p.GryConVar == convarName then
			return p
		end
	end
end

local function clearButton(panel)
	for _, p in ipairs(walk(panel)) do
		if p.GryMinimapClear then
			return p
		end
	end
end

local function hasLabel(panel, text)
	for _, p in ipairs(walk(panel)) do
		if p.ClassName == "DLabel" and p:GetText() == text then
			return true
		end
	end

	return false
end

local function build()
	local panel = vgui.Create("ControlPanel")
	GryMod.MinimapOptions(panel)

	return panel
end

-- the convar of every slider and check box of the panel, in the order they are shown ("slider:name" or "box:name")
local function controlsInOrder(panel)
	local order = {}

	for _, p in ipairs(walk(panel)) do
		if p.ClassName == "DNumSlider" and p.Scratch then
			order[#order + 1] = "slider:" .. tostring(p.Scratch:GetTable().m_strConVar)
		elseif p.ClassName == "DCheckBoxLabel" and p.Button then
			order[#order + 1] = "box:" .. tostring(p.Button:GetTable().m_strConVar)
		end
	end

	return order
end

local function indexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
end

local AUTO = "gry_minimap_definition_auto"

-- how many change callbacks the convar has (a panel that leaves one behind makes it grow)
local function callbackCount(name)
	return #(cvars.GetConVarCallbacks(name, false) or {})
end

return {
	groupName = "GryMod minimap options menu",
	beforeEach = function(state)
		state.panel = nil
		state.cache = GryMod.Minimap.Cache
		state.gen = GryMod.Minimap.Gen
		state.realRun = RunConsoleCommand
		state.realAdd = notification and notification.AddLegacy
		state.writes = {}
		state.messages = {}
		state.tile = GetConVar("gry_minimap_tile") and GetConVar("gry_minimap_tile"):GetString()
		state.auto = GetConVar(AUTO) and GetConVar(AUTO):GetString()
		state.definition = GetConVar("gry_minimap_definition") and GetConVar("gry_minimap_definition"):GetString()
		state.callbacks = callbackCount(AUTO)

		-- stand-ins: the console commands are only recorded, the notices too
		RunConsoleCommand = function(name, value)
			state.writes[#state.writes + 1] = tostring(name):lower() .. "=" .. tostring(value)
		end

		notification.AddLegacy = function(text)
			state.messages[#state.messages + 1] = tostring(text)
		end
	end,
	afterEach = function(state)
		pcall(function()
			RunConsoleCommand = state.realRun
			notification.AddLegacy = state.realAdd
			GryMod.Minimap.Cache = state.cache
			GryMod.Minimap.Gen = state.gen

			if state.panel and IsValid(state.panel) then
				state.panel:Remove()
			end

			if state.tile and GetConVar("gry_minimap_tile") then
				GetConVar("gry_minimap_tile"):SetString(state.tile)
			end

			if state.auto and GetConVar(AUTO) then
				GetConVar(AUTO):SetString(state.auto)
			end

			if state.definition and GetConVar("gry_minimap_definition") then
				GetConVar("gry_minimap_definition"):SetString(state.definition)
			end
		end)
	end,
	cases = {
		{
			name = "the panel has a Minimap section header, and opening it writes nothing",
			func = function(state)
				expect(isfunction(GryMod.MinimapOptions)).to.beTrue()

				state.panel = build()
				expect(hasLabel(state.panel, "Minimap")).to.beTrue()
				expect(#state.writes).to.equal(0)
			end
		},
		{
			name = "the check box is bound to gry_minimap, and there is no rotation option (the map always turns with the radar contacts)",
			func = function(state)
				state.panel = build()
				expect(checkBoxOn(state.panel, "gry_minimap") ~= nil).to.beTrue()
				expect(checkBoxOn(state.panel, "gry_minimap_rotate") == nil).to.beTrue()
			end
		},
		{
			-- the upper bound went from 16 to 64 with the automatic definition (its levels go up to 64)
			name = "the definition slider is bound to gry_minimap_definition: 1 to 64, whole numbers",
			func = function(state)
				state.panel = build()

				local slider = sliderOn(state.panel, "gry_minimap_definition")
				expect(slider ~= nil).to.beTrue()
				expect(slider:GetMin()).to.equal(1)
				expect(slider:GetMax()).to.equal(64)
				expect(slider:GetDecimals()).to.equal(0)
			end
		},
		{
			-- breaks if: the range slider stays in the Radar section only, or comes after the check box, or is not right before it
			name = "the Minimap section has, in this order, the radar range slider (gry_radar_range, 5 to 100), the automatic definition check box, then the definition slider",
			func = function(state)
				state.panel = build()

				local range = sliderOn(state.panel, "gry_radar_range")
				expect(range ~= nil).to.beTrue()
				expect(range:GetMin()).to.equal(5)
				expect(range:GetMax()).to.equal(100)
				expect(range:GetDecimals()).to.equal(0)
				-- the short label of the Radar section, unchanged
				expect(string.find(range:GetText(), "75", 1, true) ~= nil).to.beTrue()
				expect(string.find(range:GetText(), "down to 5", 1, true) ~= nil).to.beTrue()

				local box = checkBoxOn(state.panel, AUTO)
				expect(box ~= nil).to.beTrue()
				expect(string.find(box:GetText(), "Automatic definition", 1, true)).to.equal(1)
				expect(#state.writes).to.equal(0)

				local order = controlsInOrder(state.panel)
				local at = indexOf(order, "slider:gry_radar_range")
				expect(at ~= nil).to.beTrue()
				expect(order[at + 1]).to.equal("box:" .. AUTO)
				expect(order[at + 2]).to.equal("slider:gry_minimap_definition")
			end
		},
		{
			-- breaks if: the slider is built enabled whatever the check box says
			name = "the definition slider is greyed (disabled, its value kept) when the automatic definition is on, and active when it is off, at the moment the panel is built",
			func = function(state)
				GetConVar("gry_minimap_definition"):SetString("7")

				GetConVar(AUTO):SetString("1")
				state.panel = build()
				local slider = sliderOn(state.panel, "gry_minimap_definition")
				expect(slider:IsEnabled()).to.beFalse()
				expect(GetConVar("gry_minimap_definition"):GetString()).to.equal("7")
				state.panel:Remove()

				GetConVar(AUTO):SetString("0")
				state.panel = build()
				expect(sliderOn(state.panel, "gry_minimap_definition"):IsEnabled()).to.beTrue()
				expect(#state.writes).to.equal(0)
			end
		},
		{
			-- breaks if: the slider follows the box only when the panel is built (a change by the console is not seen)
			name = "ticking or unticking the box, or changing gry_minimap_definition_auto from the console, greys or wakes the slider at once, and keeps its value",
			func = function(state)
				GetConVar("gry_minimap_definition"):SetString("7")
				GetConVar(AUTO):SetString("0")
				state.panel = build()

				local slider = sliderOn(state.panel, "gry_minimap_definition")
				expect(slider:IsEnabled()).to.beTrue()

				GetConVar(AUTO):SetString("1")
				expect(slider:IsEnabled()).to.beFalse()
				expect(GetConVar("gry_minimap_definition"):GetString()).to.equal("7")

				GetConVar(AUTO):SetString("0")
				expect(slider:IsEnabled()).to.beTrue()
				expect(GetConVar("gry_minimap_definition"):GetString()).to.equal("7")

				-- a text like the engine reads a switch: 0.4 is off, 2 is on
				GetConVar(AUTO):SetString("1")
				GetConVar(AUTO):SetString("0")
				expect(slider:IsEnabled()).to.beTrue()
			end
		},
		{
			-- breaks if: the callback stays after the panel is gone (a permanent hook, and it would hold the dead panel), or it raises on a dead panel
			name = "each panel has its own change callback, taken off by the panel's OnRemove (the engine's call when it deletes the panel), and a change of the convar between Remove and that deletion raises nothing",
			func = function(state)
				state.panel = build()
				local one = callbackCount(AUTO)
				expect(one).to.equal(state.callbacks + 1)

				-- two panels do not share a callback
				local second = build()
				expect(callbackCount(AUTO)).to.equal(state.callbacks + 2)

				local slider = sliderOn(second, "gry_minimap_definition")

				-- Remove only marks the panel: the engine deletes it (and calls OnRemove) at the end of the frame, so a change in between meets the callback of a dead panel
				second:Remove()
				expect(function()
					GetConVar(AUTO):SetString("1")
					GetConVar(AUTO):SetString("0")
				end).to.succeed()
				expect(#state.writes).to.equal(0)

				-- the engine's deletion: OnRemove takes this panel's callback off and no other
				expect(isfunction(slider.OnRemove)).to.beTrue()
				slider:OnRemove()
				expect(callbackCount(AUTO)).to.equal(state.callbacks + 1)

				-- the other panel still follows the convar
				local other = sliderOn(state.panel, "gry_minimap_definition")
				GetConVar(AUTO):SetString("1")
				expect(other:IsEnabled()).to.beFalse()
				GetConVar(AUTO):SetString("0")
				expect(other:IsEnabled()).to.beTrue()
			end
		},
		{
			name = "the whole options panel has the automatic definition check box and the range slider once each, and the Radar section only points to the Minimap section",
			func = function(state)
				state.panel = vgui.Create("ControlPanel")
				GryMod.GryOptionschute(state.panel)

				local order = controlsInOrder(state.panel)
				local ranges, autos = 0, 0

				for _, entry in ipairs(order) do
					if entry == "slider:gry_radar_range" then ranges = ranges + 1 end
					if entry == "box:" .. AUTO then autos = autos + 1 end
				end

				expect(ranges).to.equal(1)
				expect(autos).to.equal(1)
				expect(hasLabel(state.panel, "The radar range slider is in the Minimap section.")).to.beTrue()
				expect(#state.writes).to.equal(0)
			end
		},
		{
			name = "the map opacity slider is bound to gry_minimap_opacity: 0 to 100, whole numbers, right before the floor below slider",
			func = function(state)
				state.panel = build()

				local slider = sliderOn(state.panel, "gry_minimap_opacity")
				expect(slider ~= nil).to.beTrue()
				expect(slider:GetMin()).to.equal(0)
				expect(slider:GetMax()).to.equal(100)
				expect(slider:GetDecimals()).to.equal(0)
				expect(#state.writes).to.equal(0)

				local order = {}

				for _, p in ipairs(walk(state.panel)) do
					if p.ClassName == "DNumSlider" and p.Scratch then
						order[#order + 1] = p.Scratch:GetTable().m_strConVar
					end
				end

				local below
				for i, name in ipairs(order) do
					if name == "gry_minimap_below" then below = i end
				end

				expect(below ~= nil and below > 1).to.beTrue()
				expect(order[below - 1]).to.equal("gry_minimap_opacity")
			end
		},
		{
			name = "the floor below slider is bound to gry_minimap_below: 0 to 100, whole numbers",
			func = function(state)
				state.panel = build()

				local slider = sliderOn(state.panel, "gry_minimap_below")
				expect(slider ~= nil).to.beTrue()
				expect(slider:GetMin()).to.equal(0)
				expect(slider:GetMax()).to.equal(100)
				expect(slider:GetDecimals()).to.equal(0)
				expect(#state.writes).to.equal(0)
			end
		},
		{
			name = "the outside slider is bound to gry_minimap_outside: 0 to 100, whole numbers, right after the floor below slider",
			func = function(state)
				state.panel = build()

				local slider = sliderOn(state.panel, "gry_minimap_outside")
				expect(slider ~= nil).to.beTrue()
				expect(slider:GetMin()).to.equal(0)
				expect(slider:GetMax()).to.equal(100)
				expect(slider:GetDecimals()).to.equal(0)
				expect(#state.writes).to.equal(0)

				local order = {}

				for _, p in ipairs(walk(state.panel)) do
					if p.ClassName == "DNumSlider" and p.Scratch then
						order[#order + 1] = p.Scratch:GetTable().m_strConVar
					end
				end

				local below
				for i, name in ipairs(order) do
					if name == "gry_minimap_below" then below = i end
				end

				expect(below ~= nil).to.beTrue()
				expect(order[below + 1]).to.equal("gry_minimap_outside")
			end
		},
		{
			name = "the cache size slider is bound to gry_minimap_cache_mb: 16 to 4096, whole numbers, right after the outside slider (which follows the floor below slider)",
			func = function(state)
				state.panel = build()

				local slider = sliderOn(state.panel, "gry_minimap_cache_mb")
				expect(slider ~= nil).to.beTrue()
				expect(slider:GetMin()).to.equal(16)
				expect(slider:GetMax()).to.equal(4096)
				expect(slider:GetDecimals()).to.equal(0)
				expect(#state.writes).to.equal(0)

				local order = {}

				for _, p in ipairs(walk(state.panel)) do
					if p.ClassName == "DNumSlider" and p.Scratch then
						order[#order + 1] = p.Scratch:GetTable().m_strConVar
					end
				end

				local outside
				for i, name in ipairs(order) do
					if name == "gry_minimap_outside" then outside = i end
				end

				expect(outside ~= nil).to.beTrue()
				expect(order[outside + 1]).to.equal("gry_minimap_cache_mb")
			end
		},
		{
			name = "the budget slider is bound to gry_minimap_budget_ms: 1 to 30",
			func = function(state)
				state.panel = build()

				local slider = sliderOn(state.panel, "gry_minimap_budget_ms")
				expect(slider ~= nil).to.beTrue()
				expect(slider:GetMin()).to.equal(1)
				expect(slider:GetMax()).to.equal(30)
			end
		},
		{
			name = "the tile size is a choice of 512, 1024 and 2048 that shows the current size and writes only when the player picks one",
			func = function(state)
				GetConVar("gry_minimap_tile"):SetString("2048")
				state.panel = build()

				local combo = comboOn(state.panel, "gry_minimap_tile")
				expect(combo ~= nil).to.beTrue()
				expect(combo:GetOptionData(1)).to.equal("512")
				expect(combo:GetOptionData(2)).to.equal("1024")
				expect(combo:GetOptionData(3)).to.equal("2048")
				expect(combo:GetSelectedID()).to.equal(3)
				expect(#state.writes).to.equal(0)

				combo:ChooseOptionID(1)
				expect(state.writes[#state.writes]).to.equal("gry_minimap_tile=512")
			end
		},
		{
			name = "the Clear button calls Cache.Clear with the current key, and tells the player",
			func = function(state)
				local cleared = {}

				GryMod.Minimap.Cache = {
					Key = function() return "gm_test_123_v1" end,
					Clear = function(key) cleared[#cleared + 1] = key return true end
				}

				state.panel = build()

				local button = clearButton(state.panel)
				expect(button ~= nil).to.beTrue()
				button:DoClick()

				expect(#cleared).to.equal(1)
				expect(cleared[1]).to.equal("gm_test_123_v1")
				expect(#state.messages).to.equal(1)
			end
		},
		{
			name = "the Clear button also calls Gen.Cancel, after Cache.Clear (a request Gen remembers would otherwise make nothing)",
			func = function(state)
				local order = {}

				GryMod.Minimap.Cache = {
					Key = function() return "k" end,
					Clear = function() order[#order + 1] = "clear" return true end
				}
				GryMod.Minimap.Gen = {Cancel = function() order[#order + 1] = "cancel" end}

				state.panel = build()
				clearButton(state.panel):DoClick()

				expect(#order).to.equal(2)
				expect(order[1]).to.equal("clear")
				expect(order[2]).to.equal("cancel")
			end
		},
		{
			name = "the Clear button does not crash when Gen is missing, has no Cancel, or Cancel raises, and still clears the cache",
			func = function(state)
				local cleared = 0

				GryMod.Minimap.Cache = {
					Key = function() return "k" end,
					Clear = function() cleared = cleared + 1 return true end
				}

				state.panel = build()

				local button = clearButton(state.panel)

				for _, gen in ipairs({false, {}, {Cancel = function() error("boom") end}}) do
					GryMod.Minimap.Gen = gen or nil
					expect(function() button:DoClick() end).to.succeed()
				end

				expect(cleared).to.equal(3)
			end
		},
		{
			name = "the Clear button does not crash when the Cache module is missing, and says so",
			func = function(state)
				GryMod.Minimap.Cache = nil
				state.panel = build()

				local button = clearButton(state.panel)
				expect(button ~= nil).to.beTrue()
				expect(function() button:DoClick() end).to.succeed()
				expect(#state.messages).to.equal(1)
			end
		},
		{
			name = "the Clear button does not crash when Cache.Clear raises or Key is missing",
			func = function(state)
				state.panel = build()

				local button = clearButton(state.panel)

				GryMod.Minimap.Cache = {Key = function() return "k" end, Clear = function() error("boom") end}
				expect(function() button:DoClick() end).to.succeed()
				expect(#state.messages).to.equal(1)

				GryMod.Minimap.Cache = {Clear = function() return true end}
				expect(function() button:DoClick() end).to.succeed()
				expect(#state.messages).to.equal(2)
			end
		},
		{
			name = "the whole options panel contains the Minimap section once",
			func = function(state)
				state.panel = vgui.Create("ControlPanel")
				GryMod.GryOptionschute(state.panel)

				local count = 0

				for _, p in ipairs(walk(state.panel)) do
					if p.ClassName == "DNumSlider" and p.Scratch and p.Scratch:GetTable().m_strConVar == "gry_minimap_definition" then
						count = count + 1
					end
				end

				expect(count).to.equal(1)
				expect(#state.writes).to.equal(0)
			end
		}
	}
}
