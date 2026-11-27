-- Server job (lua_job, realm server): real falls on the real engine, end to end, the part that tests/sv_fall_damage_test.lua cannot do (the engine's own landing, the real
-- setting mp_falldamage, which a console command only changes at the end of the frame). Needs a map with an open space above the player (gm_construct, gm_flatgrass) and the
-- first player alive. For each height the player is dropped in armor mode with a full bar and the health and the bar are read once he has landed (the bar recharges a
-- little during the fall's rest: read the numbers as "about"). Expected, with a gravity of 600: speed = sqrt(2 * 600 * height); realistic damage = (speed - 526.5) * 100 / 396.
--   mp_falldamage 0: about 10 for 600 up (the bar goes to about 90), nothing under 526.5 units a second (under 231 up).
--   mp_falldamage 1: 300 up: about 18.6 (speed 600); 600 up: about 81.5 (speed 849); 1200 up: about 170, more than the bar: the bar is 0 and the health takes the rest.
--   gry_realistic_fall 1: sets mp_falldamage to 1 within a frame; 0 takes it back, unless it was already on before.
-- Returns a table of measures; the settings it changes are put back.
local p = Entity(1)
local out = {}
local savedFall = GetConVar("mp_falldamage"):GetString()
local savedOption = GetConVar("gry_realistic_fall"):GetString()

local function drop(height)
	p:GodDisable()

	if not p:Alive() then
		p:Spawn()
		job:sleep(0.5)
	end

	p:SetHealth(100)
	p:SetNW2Float("GryEnergy", 100)
	p:SetVelocity(-p:GetVelocity())
	p:SetPos(p:GetPos() + Vector(0, 0, height))

	local t0 = CurTime()

	job:wait(function()
		return (p:OnGround() and CurTime() - t0 > 0.3) or not p:Alive()
	end)
	job:sleep(0.3)

	return {alive = p:Alive(), health = p:Health(), energy = math.Round(p:GetNW2Float("GryEnergy"), 1)}
end

RunConsoleCommand("mp_falldamage", "0")
job:sleep(0.3)
out.setting_0_up600 = drop(600)

RunConsoleCommand("mp_falldamage", "1")
job:sleep(0.3)
out.setting_1_up300 = drop(300)
out.setting_1_up600 = drop(600)
out.setting_1_up1200 = drop(1200)

RunConsoleCommand("mp_falldamage", "0")
job:sleep(0.3)
GetConVar("gry_realistic_fall"):SetString("1")
job:sleep(0.3)
out.option_on_sets_the_setting = GetConVar("mp_falldamage"):GetInt()
GetConVar("gry_realistic_fall"):SetString("0")
job:sleep(0.3)
out.option_off_takes_it_back = GetConVar("mp_falldamage"):GetInt()

GetConVar("gry_realistic_fall"):SetString(savedOption)
RunConsoleCommand("mp_falldamage", savedFall)

return out
