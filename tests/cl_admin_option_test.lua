-- Tests of the administrators' settings in the options panel (GryMod.AdminOption and GryMod.AdminUI, cl_admin_option.lua), GLuaTest format,
-- client realm. The settings that belong to the SERVER (the white list in sh_server_options.lua) are in a section of their own, greyed and disabled
-- (grey, a tooltip that says why) when the player is not an admin; they never write the convar from the client (on a dedicated server a client cannot
-- change a server convar): they ask the server with ONE net message, and the box shows the value the server really has. No global is replaced here:
-- the transport and the command runner are fields of GryMod.AdminUI (put back after each case), and the admin status is swapped on the Player
-- metatable inside a pcall that always puts it back.

local UI = function() return GryMod.AdminUI end

local realTransport, realRunner

local function asAdmin(isAdmin, fn)
	local meta = FindMetaTable("Player")
	local real = meta.IsAdmin
	meta.IsAdmin = function() return isAdmin end
	local ok, err = pcall(fn)
	meta.IsAdmin = real

	if not ok then
		error(err, 0)
	end
end

local function newPanel()
	return vgui.Create("ControlPanel")
end

-- every panel under (and including) `root`
local function walk(root, visit, flag)
	for _, child in ipairs(root:GetChildren()) do
		visit(child, flag or child.GryAdminItem)
		walk(child, visit, flag or child.GryAdminItem)
	end
end

local INTERACTIVE = {DCheckBoxLabel = true, DButton = true, DComboBox = true, DNumSlider = true, DBinder = true, DColorMixer = true}

return {
	groupName = "GryMod administrators' settings (options panel)",
	beforeEach = function()
		realTransport, realRunner = UI().Transport, UI().RunCommand
	end,
	afterEach = function()
		UI().Transport, UI().RunCommand = realTransport, realRunner
	end,
	cases = {
		{
			name = "the decision is a pure function: an admin has the option on and no tooltip, anybody else has it off with the tooltip that says why",
			func = function()
				local on, tip = UI().Decide(true)
				expect(on).to.beTrue()
				expect(tip).to.beNil()

				local off, why = UI().Decide(false)
				expect(off).to.beFalse()
				expect(why).to.equal("Server setting: administrators only")

				-- what is not known to be an admin is not one
				expect((UI().Decide(nil))).to.beFalse()
				expect((UI().Decide("yes"))).to.beFalse()
			end
		},
		{
			name = "the line above the section follows the status: what an admin can do, what the others cannot",
			func = function()
				local admin, other = UI().StatusText(true), UI().StatusText(false)
				expect(admin ~= other).to.beTrue()
				expect(string.find(admin, "administrator", 1, true) ~= nil).to.beTrue()
				expect(string.find(other, "not", 1, true) ~= nil).to.beTrue()
			end
		},
		{
			name = "IsAdmin is the local player's status as the engine knows it, and a missing player is no admin",
			func = function()
				expect(UI().IsAdmin()).to.equal(LocalPlayer():IsAdmin())
				asAdmin(false, function() expect(UI().IsAdmin()).to.beFalse() end)
				asAdmin(true, function() expect(UI().IsAdmin()).to.beTrue() end)
				expect(LocalPlayer():IsAdmin()).to.equal(UI().IsAdmin()) -- put back
			end
		},
		{
			name = "a yes / no option is a check box that shows the value the server has and is not tied to a client convar",
			func = function()
				local panel = newPanel()
				local ok, err = pcall(function()
					asAdmin(true, function()
						local box = GryMod.AdminOption(panel, "label", "gry_malfunction", "bool")
						expect(box.ClassName).to.equal("DCheckBoxLabel")
						expect(box:GetChecked()).to.equal(GetConVar("gry_malfunction"):GetBool())
						expect(box.Button.m_strConVar).to.beNil()
						expect(box:GetText()).to.equal("label")
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "an admin who ticks a box sends the name and the value through the transport, once, and the convar is not written from the client",
			func = function()
				local panel = newPanel()
				local sent = {}
				UI().Transport = function(name, value) sent[#sent + 1] = name .. "=" .. value end
				local before = GetConVar("gry_malfunction"):GetString()

				local ok, err = pcall(function()
					asAdmin(true, function()
						local box = GryMod.AdminOption(panel, "label", "gry_malfunction", "bool")
						expect(box:IsEnabled()).to.beTrue()
						box:SetValue(not box:GetChecked())
						expect(#sent).to.equal(1)
						expect(sent[1]).to.equal("gry_malfunction=" .. (before == "1" and "0" or "1"))
						expect(GetConVar("gry_malfunction"):GetString()).to.equal(before)
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "for a player who is not an admin the box is disabled, dimmed, has the tooltip, and a click that gets through anyway sends nothing and changes nothing shown",
			func = function()
				local panel = newPanel()
				local sent = 0
				UI().Transport = function() sent = sent + 1 end

				local ok, err = pcall(function()
					asAdmin(false, function()
						local box = GryMod.AdminOption(panel, "label", "gry_malfunction", "bool")
						local shown = box:GetChecked()
						expect(box:IsEnabled()).to.beFalse()
						expect(box.Button:IsEnabled()).to.beFalse()
						expect(box:GetAlpha() < 255).to.beTrue() -- attenuated
						expect(box:GetParent():GetTooltip()).to.equal("Server setting: administrators only")
						expect(box.Button:IsMouseInputEnabled()).to.beFalse()

						box.Button:DoClick() -- something that skips the mouse code
						expect(sent).to.equal(0)
						expect(box:GetChecked()).to.equal(shown)
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "a choice option is a selector that shows the server's value and asks for the other one through the transport",
			func = function()
				local panel = newPanel()
				local sent = {}
				UI().Transport = function(name, value) sent[#sent + 1] = name .. "=" .. value end

				local ok, err = pcall(function()
					asAdmin(true, function()
						local combo = GryMod.AdminOption(panel, "Suit rules", "gry_mechanics", "choice", {
							choices = {{"Crysis numbers", "crysis"}, {"Classic", "classic"}}
						})
						expect(combo.ClassName).to.equal("DComboBox")

						local value = GetConVar("gry_mechanics"):GetString()
						expect(combo:GetValue()).to.equal(value == "crysis" and "Crysis numbers" or "Classic")

						combo:ChooseOptionID(value == "crysis" and 2 or 1)
						expect(#sent).to.equal(1)
						expect(sent[1]).to.equal("gry_mechanics=" .. (value == "crysis" and "classic" or "crysis"))
						expect(GetConVar("gry_mechanics"):GetString()).to.equal(value)
					end)

					asAdmin(false, function()
						sent = {}
						local combo = GryMod.AdminOption(panel, "Suit rules", "gry_mechanics", "choice", {
							choices = {{"Crysis numbers", "crysis"}, {"Classic", "classic"}}
						})
						expect(combo:IsEnabled()).to.beFalse()
						combo:ChooseOptionID(2)
						expect(#sent).to.equal(0)
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "a button option runs its console command for an admin only (the server checks again)",
			func = function()
				local panel = newPanel()
				local ran = {}
				UI().RunCommand = function(command) ran[#ran + 1] = command end

				local ok, err = pcall(function()
					asAdmin(true, function()
						local button = GryMod.AdminOption(panel, "Toggle", nil, "button", {command = "gry_Health"})
						expect(button.ClassName).to.equal("DButton")
						expect(button:IsEnabled()).to.beTrue()
						button:DoClick()
						expect(#ran).to.equal(1)
						expect(ran[1]).to.equal("gry_Health")
					end)

					asAdmin(false, function()
						ran = {}
						local button = GryMod.AdminOption(panel, "Toggle", nil, "button", {command = "gry_Health"})
						expect(button:IsEnabled()).to.beFalse()
						button:DoClick()
						expect(#ran).to.equal(0)
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "the state follows the player live: the poll (once a second, from the panel's Think) greys the options when the player stops being an admin and turns them on again when he becomes one",
			func = function()
				local panel = newPanel()

				local ok, err = pcall(function()
					local box, status
					asAdmin(true, function()
						box = GryMod.AdminOption(panel, "label", "gry_malfunction", "bool")
						expect(box:IsEnabled()).to.beTrue()
					end)

					asAdmin(false, function()
						-- less than a second after the last poll: nothing is looked at
						UI().Poll(panel, panel.GryAdminPolled + 0.5)
						expect(box:IsEnabled()).to.beTrue()

						UI().Poll(panel, panel.GryAdminPolled + 1.01)
						expect(box:IsEnabled()).to.beFalse()
						expect(box:GetParent():GetTooltip()).to.equal("Server setting: administrators only")
					end)

					asAdmin(true, function()
						UI().Poll(panel, panel.GryAdminPolled + 1.01)
						expect(box:IsEnabled()).to.beTrue()
						expect(box:GetParent():GetTooltip()).to.beNil()
					end)

					-- and the panel's own Think makes the poll (with the real time)
					asAdmin(false, function()
						panel.GryAdminPolled = -10
						panel:Think()
						expect(box:IsEnabled()).to.beFalse()
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "the box follows the value the server really has, and goes back to it when the server did not take a request",
			func = function()
				local panel = newPanel()
				local fake = CreateClientConVar("gry_test_admin_option", "1", false, false)

				local ok, err = pcall(function()
					asAdmin(true, function()
						local box = GryMod.AdminOption(panel, "label", "gry_test_admin_option", "bool")
						expect(box:GetChecked()).to.beTrue()

						fake:SetInt(0) -- a client convar here: a replicated one is changed by the server only
						UI().Poll(panel, panel.GryAdminPolled + 1.01)
						expect(box:GetChecked()).to.beFalse()

						-- the player ticks it: the request goes, the server does not change the convar (a refusal, the rate limit...): the box comes back to the real value
						local sent = 0
						UI().Transport = function() sent = sent + 1 end
						box:SetValue(true)
						expect(sent).to.equal(1)
						expect(box:GetChecked()).to.beTrue()
						UI().Poll(panel, panel.GryAdminPolled + 3)
						expect(box:GetChecked()).to.beFalse()
						expect(sent).to.equal(1) -- the poll only shows, it never asks
					end)
				end)

				fake:SetInt(1)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "the options panel has a Server (administrators only) section at the bottom with every server setting of the white list, the two admin buttons, and only those",
			func = function()
				local panel = newPanel()
				local ok, err = pcall(function()
					asAdmin(true, function()
						GryMod.GryOptionschute(panel)
					end)

					local seen = {}
					for name in pairs(panel.GryAdminControls or {}) do
						seen[#seen + 1] = name
					end

					local expected = {}
					for _, setting in ipairs(GryMod.ServerSettings.List) do
						expected[#expected + 1] = setting.name
					end

					expected[#expected + 1] = "button:gry_Health"
					expected[#expected + 1] = "button:gry_Armor"
					table.sort(seen)
					table.sort(expected)
					expect(table.concat(seen, ",")).to.equal(table.concat(expected, ","))

					-- the kind of each control is the kind of the list
					for _, setting in ipairs(GryMod.ServerSettings.List) do
						local control = panel.GryAdminControls[setting.name]
						expect(control.ClassName).to.equal(setting.kind == "choice" and "DComboBox" or "DCheckBoxLabel")
					end

					-- order: the title, then all of the admin controls; no other control comes after the title
					local order, titleAt = {}, nil
					walk(panel, function(child, admin)
						if child.ClassName == "DLabel" and child.GetText and child:GetText() == "Server (administrators only)" then
							titleAt = #order + 1
							order[#order + 1] = "title"
						elseif child.GryDebugOpen then
							order[#order + 1] = "debug" -- the button that opens the effects test window (cl_debug_window.lua)
						elseif INTERACTIVE[child.ClassName] then
							order[#order + 1] = admin and "admin" or "other"
						end
					end)

					expect(titleAt ~= nil).to.beTrue()

					-- the button of the effects test window is the last control of the panel, after the administrators' section
					expect(order[#order]).to.equal("debug")
					table.remove(order)

					for i = titleAt + 1, #order do
						expect(order[i]).to.equal("admin")
					end

					for i = 1, titleAt - 1 do
						expect(order[i]).to.equal("other")
					end

					-- none of the server settings is a box tied to a client convar any more
					for _, setting in ipairs(GryMod.ServerSettings.List) do
						walk(panel, function(child)
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								expect(child.Button.m_strConVar ~= setting.name).to.beTrue()
							end
						end)
					end
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "for a player who is not an admin every control of the section is disabled and no other control of the panel is",
			func = function()
				local panel = newPanel()
				local ok, err = pcall(function()
					asAdmin(false, function()
						GryMod.GryOptionschute(panel)

						local admins, others = 0, 0
						walk(panel, function(child, admin)
							if INTERACTIVE[child.ClassName] then
								if admin then
									admins = admins + 1
									expect(child:IsEnabled()).to.beFalse()
								else
									others = others + 1
									expect(child:IsEnabled()).to.beTrue()
								end
							end
						end)

						expect(admins >= 8).to.beTrue() -- 6 settings and 2 buttons
						expect(others > 20).to.beTrue()
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "for an admin every control of the section is enabled",
			func = function()
				local panel = newPanel()
				local ok, err = pcall(function()
					asAdmin(true, function()
						GryMod.GryOptionschute(panel)

						local admins = 0
						walk(panel, function(child, admin)
							if admin and INTERACTIVE[child.ClassName] then
								admins = admins + 1
								expect(child:IsEnabled()).to.beTrue()
							end
						end)

						expect(admins >= 8).to.beTrue()
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "the real transport is the net message gry_set_server_option with the name and the value as two strings",
			func = function()
				expect(util.NetworkStringToID("gry_set_server_option") ~= 0).to.beTrue()

				local realStart, realWrite, realSend = net.Start, net.WriteString, net.SendToServer
				local log = {}
				local ok, err = pcall(function()
					net.Start = function(name) log[#log + 1] = "start:" .. name end
					net.WriteString = function(text) log[#log + 1] = "string:" .. text end
					net.SendToServer = function() log[#log + 1] = "send" end
					realTransport("gry_malfunction", "0")
				end)

				net.Start, net.WriteString, net.SendToServer = realStart, realWrite, realSend
				if not ok then error(err, 0) end

				expect(table.concat(log, "|")).to.equal("start:gry_set_server_option|string:gry_malfunction|string:0|send")
				expect(net.Start).to.equal(realStart)
			end
		},
	}
}
