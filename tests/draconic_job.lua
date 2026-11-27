-- Live checks of the Draconic Base adapter (lua/grymod/compat/weapons/*draconic.lua) with the REAL Draconic Base (installed from the Workshop), run with lua_job (server realm, one job at a time,
-- a map loaded; the player is left in god mode). The two test weapons of tests/fixtures/draconic/ (a gun with the three fire modes, a launcher of Draconic grenades) are copied to lua/weapons/ of the mounted
-- folder: the owner's Workshop has the base and a few tools of it (drc_unarmed, drc_empgun...), no gun pack. Every `ok` of the result must be true.

local ply = player.GetAll()[1]
local results = {}

local function check(name, ok, detail)
	results[#results + 1] = {name = name, ok = ok == true, detail = detail}
end

if not DRC then
	return {skipped = "the Draconic Base is not installed"}
end

ply:GodEnable()
ply:StripWeapons()
GryMod.API.RefillEnergy(ply)
GryMod.API.SetMode(ply, GryMod.Modes.ARMOR)
ply:SetPos(Vector(0, 0, -130))

local function give(class)
	ply:Give(class)
	job:sleep(0.3)
	ply:SelectWeapon(class)
	job:sleep(1.5)

	return ply:GetActiveWeapon()
end

local function zoom(fov)
	job:call("client", "net.Start('gry_zoom_fov') net.WriteFloat(" .. fov .. ") net.SendToServer()")
end

-- the fists: no gun on the icon
local fists = give("drc_unarmed")

check("the fists are patched and show no gun", job:call("client", "return GryMod.FlashHUD.FireModeFor(LocalPlayer():GetActiveWeapon())") == "NoGun")

if weapons.GetStored("drc_gry_test_gun") then
	local gun = give("drc_gry_test_gun")
	local icons = {}

	for i = 1, 3 do
		icons[#icons + 1] = job:call("client", "return GryMod.FlashHUD.FireModeFor(LocalPlayer():GetActiveWeapon())")
		gun:SetFireMode(nil, false)
		job:sleep(0.6)
	end

	check("the fire mode icon follows the three modes (auto, burst, single)", icons[1] == "Auto" and icons[2] == "Burst" and icons[3] == "Single", icons)
	check("the weapon was patched for the field of view", gun.GryFovPatched == true)

	-- the zoom of the suit holds while the weapon is in hand; without the adapter Draconic puts the field of view back
	local function hold()
		local fovs = {}

		for i = 1, 5 do
			zoom(30)
			job:sleep(0.5)
			fovs[#fovs + 1] = ply:GetFOV()
		end

		zoom(0)
		job:sleep(0.6)

		return fovs
	end

	local held = hold()
	local patched = gun.ShouldFixFOV

	gun.ShouldFixFOV = weapons.GetStored("draconic_base").ShouldFixFOV
	gun.GryFovPatched = nil

	local alone = hold()

	gun.ShouldFixFOV = patched
	gun.GryFovPatched = true
	check("the suit's zoom holds with the adapter", held[1] == 30 and held[5] == 30, held)
	check("and does not without it (Draconic's own habit, the reason of the adapter)", alone[#alone] ~= 30, alone)
end

if weapons.GetStored("drc_gry_test_launcher") then
	local launcher = give("drc_gry_test_launcher")

	local function fire(withHook)
		GryMod.API.RefillEnergy(ply)
		GryMod.API.SetMode(ply, GryMod.Modes.CLOAK)
		job:sleep(0.8)

		local hook_ = hook.GetTable().OnEntityCreated["GryMod compat draconic"]

		if not withHook then hook.Remove("OnEntityCreated", "GryMod compat draconic") end

		launcher:SetNextPrimaryFire(0)
		launcher:SetClip1(6)
		launcher:PrimaryAttack()
		job:sleep(1.2)

		for _, e in ipairs(ents.FindByClass("drc_fraggrenade")) do e:Remove() end

		if not withHook then hook.Add("OnEntityCreated", "GryMod compat draconic", hook_) end

		local after = ply.Nanosuit_mode

		GryMod.API.SetMode(ply, GryMod.Modes.ARMOR)
		job:sleep(0.5)

		return after
	end

	check("a projectile shot ends the camouflage (the server does not see it as a bullet)", fire(true) == GryMod.Modes.ARMOR)
	check("and does not without the adapter (control)", fire(false) == GryMod.Modes.CLOAK)
end

-- the EMP of the base puts the suit of a player down
GryMod.API.RefillEnergy(ply)
GryMod.API.SetMode(ply, GryMod.Modes.SPEED)
job:sleep(0.3)
DRC:EMP(fists, ply, 3)
job:sleep(0.4)
check("DRC:EMP puts the suit down", GryMod.Malfunction.IsActive(ply))
job:sleep(3.5)
check("and the suit comes back", not GryMod.Malfunction.IsActive(ply))

local failed = {}

for _, r in ipairs(results) do
	if not r.ok then
		failed[#failed + 1] = r.name
	end
end

return {ok = #failed == 0, failed = failed, results = results}
