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
			name = "the definition slider is bound to gry_minimap_definition: 1 to 16, whole numbers",
			func = function(state)
				state.panel = build()

				local slider = sliderOn(state.panel, "gry_minimap_definition")
				expect(slider ~= nil).to.beTrue()
				expect(slider:GetMin()).to.equal(1)
				expect(slider:GetMax()).to.equal(16)
				expect(slider:GetDecimals()).to.equal(0)
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
