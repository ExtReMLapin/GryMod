-- Client job (lua_job, realm client): the options panel and the server, end to end in single player or on a listen server host (the host is an
-- admin). The real net message goes from the boxes to the server and the replicated convar is read back; then a player who is not an admin is
-- simulated by swapping IsAdmin on the Player metatable inside a pcall that always puts it back (never across a yield): the controls are disabled
-- and nothing is sent (the server counts the messages it receives: run `tests/admin_options_server_count.lua` first, read its counter after).
-- Returns a table of measures; every convar it changes is put back.
local out = {}
local meta = FindMetaTable("Player")
local panel = vgui.Create("ControlPanel")
local saved = {
	gry_malfunction = GetConVar("gry_malfunction"):GetString(),
	gry_mechanics = GetConVar("gry_mechanics"):GetString(),
	gry_energy_net = GetConVar("gry_energy_net"):GetString()
}

local function convar(name)
	return GetConVar(name):GetString()
end

local function other(value)
	if value == "crysis" then return "classic" end
	if value == "classic" then return "crysis" end

	return value == "1" and "0" or "1"
end

local function withAdmin(isAdmin, fn)
	local real = meta.IsAdmin
	meta.IsAdmin = function() return isAdmin end
	local ok, err = pcall(fn)
	meta.IsAdmin = real

	if not ok then
		error(err, 0)
	end
end

GryMod.GryOptionschute(panel)
local box = panel.GryAdminControls.gry_malfunction
local combo = panel.GryAdminControls.gry_mechanics
local energy = panel.GryAdminControls.gry_energy_net
out.isAdmin = LocalPlayer():IsAdmin()
out.enabledForHost = box:IsEnabled() and combo:IsEnabled() and energy:IsEnabled()
out.energyNetReadByClient = GetConVar("gry_energy_net") ~= nil

-- the host (admin): the real message, the server's convar changes, the replicated copy follows
local before = convar("gry_malfunction")
box:SetValue(not box:GetChecked())
job:frames(6)
out.boolBefore, out.boolAfter = before, convar("gry_malfunction")
out.boolChanged = convar("gry_malfunction") == other(before)

local rules = convar("gry_mechanics")
combo:ChooseOptionID(rules == "crysis" and 2 or 1)
job:frames(6)
out.choiceBefore, out.choiceAfter = rules, convar("gry_mechanics")
out.choiceChanged = convar("gry_mechanics") == other(rules)

local netBefore = convar("gry_energy_net")
energy:SetValue(not energy:GetChecked())
job:frames(6)
out.energyBefore, out.energyAfter = netBefore, convar("gry_energy_net")
out.energyChanged = convar("gry_energy_net") == other(netBefore)

-- the poll shows the server's value
panel.GryAdminPolled = -10
panel:Think()
out.boxShowsServer = box:GetChecked() == GetConVar("gry_malfunction"):GetBool()

-- a player who is not an admin: disabled, and a forced change sends nothing
local heldBefore = convar("gry_malfunction")
withAdmin(false, function()
	panel.GryAdminPolled = -10
	panel:Think()
	out.nonAdminDisabled = not box:IsEnabled() and not combo:IsEnabled() and not energy:IsEnabled()
	out.tooltip = box:GetParent():GetTooltip()
	box:SetValue(not box:GetChecked()) -- a change that got through the mouse
	combo:ChooseOptionID(combo:GetSelectedID() == 1 and 2 or 1)
end)
job:frames(6)
out.nonAdminChangedServer = convar("gry_malfunction") ~= heldBefore

-- the poll puts the controls back on for the admin
panel.GryAdminPolled = -10
panel:Think()
out.enabledAgain = box:IsEnabled() and combo:IsEnabled()

-- put everything back, through the same real message
for name, value in pairs(saved) do
	if convar(name) ~= value then
		GryMod.AdminUI.Transport(name, value)
		job:frames(3)
	end
end

job:frames(6)
out.restored = convar("gry_malfunction") == saved.gry_malfunction and convar("gry_mechanics") == saved.gry_mechanics and convar("gry_energy_net") == saved.gry_energy_net
panel:Remove()

return out
