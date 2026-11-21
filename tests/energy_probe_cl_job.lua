-- Energy probe, client realm: per frame, the raw NWFloat and what the HUD would be fed.
GRY_CPROBE = GRY_CPROBE or {}
local P = GRY_CPROBE
P.rows = {}
P.on = false

-- the HUD's own state (the local `fed` of cl_hud_flash.lua), to read what the movie is given
local function findFed()
	local f = GryMod.FlashHUD and GryMod.FlashHUD.Paint
	if not f then return end
	for i = 1, 60 do
		local n, v = debug.getupvalue(f, i)
		if not n then return end
		if n == "fed" then return v end
	end
end

P.fed = findFed()

hook.Remove("PreRender", "gryprobe_cl")
hook.Add("PreRender", "gryprobe_cl", function()
	if not P.on then return end
	local p = LocalPlayer()
	if not IsValid(p) then return end
	local ES = GryMod.EnergySmooth
	local raw = p:GetNW2Float("GryEnergy")
	P.fed = findFed()
	local fedE = P.fed and P.fed.energy
	-- cols: 2 NWFloat, 3 value given to the HUD (setEnergy), 4 server value (gry_energy or NW), 5 shown float
	local srv = ES and ES.Raw(p, CurTime()) or raw
	P.rows[#P.rows + 1] = {SysTime(), raw, fedE, srv, ES and ES.view.shown}
end)

hook.Remove("CreateMove", "gryprobe_cm")
hook.Add("CreateMove", "gryprobe_cm", function(cmd)
	if P.move then
		cmd:SetViewAngles(Angle(0, 120, 0))
		cmd:SetForwardMove(10000)
		cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_FORWARD, IN_SPEED))
	end
end)

return "ok"
