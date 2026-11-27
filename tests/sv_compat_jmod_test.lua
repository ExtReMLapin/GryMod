-- Tests of the JMod patch, the server part (lua/grymod/compat/tools/sv_jmod.lua), GLuaTest format, server realm. JMod was not installed when this was written; the stand-ins have what
-- the patch reads in its public code (github.com/Jackarunda/gmod): the hook JMod_ShouldAttack(self, ent, vehiclesOnly, peace) of JMod.ShouldAttack (sv_util.lua:209), where a
-- mine, a sentry... asks whether a target is one, and JMod.GetPlayerHeldEntity (sh_init.lua:208), the grenade that is in the player's hands, which the attack keys throw
-- (JMod.ThrowablePickup, sv_util.lua:294). Each case names the change whose absence makes it fail.

-- the patch's own function of an event (hook.Run would also run every other addon's hooks with these stand-ins)
local function fire(event, ...)
	local fn = hook.GetTable()[event] and hook.GetTable()[event]["GryMod compat jmod"]

	if fn then
		return fn(...)
	end

	return nil
end

local API
local realJMod, realCloakLevel, realReport, reports
local aiVar, aiWas

local function player(fields)
	local p = {IsValid = function() return true end, IsPlayer = function() return true end, Alive = function() return true end}

	for key, value in pairs(fields or {}) do
		p[key] = value
	end

	return p
end

local mine = {IsValid = function() return true end, GetClass = function() return "ent_jack_gmod_ezlandmine" end}
local atMine = {IsValid = function() return true end, GetClass = function() return "ent_jack_gmod_ezatmine" end}
local sentry = {IsValid = function() return true end, GetClass = function() return "ent_jack_gmod_ezsentry" end}

-- the device that asks (a sentry unless told otherwise): the camouflage hides from the eyes of a sentry, not from a mine that goes off under the feet
local function shouldAttack(target, device)
	return fire("JMod_ShouldAttack", device or sentry, target, false, false)
end

local function press(ply, key)
	fire("KeyPress", ply, key)
end

return {
	groupName = "GryMod compat: JMod (server)",
	beforeEach = function()
		API = GryMod.API
		realJMod, realCloakLevel, realReport = JMod, API.CloakLevel, API.ReportAttack
		reports = {}
		API.ReportAttack = function(ply, alt) reports[#reports + 1] = {ply, alt} return true end
		API.CloakLevel = function(ply) return ply.__cloak or 0 end
		JMod = {GetPlayerHeldEntity = function(ply) return ply.__held end}
		aiVar = GetConVar("gry_cloak_ai") or CreateConVar("gry_cloak_ai", "1")
		aiWas = aiVar:GetBool()
		aiVar:SetBool(true)
		include("grymod/compat/tools/sh_jmod.lua")
		include("grymod/compat/tools/sv_jmod.lua")
	end,
	afterEach = function()
		JMod, API.CloakLevel, API.ReportAttack = realJMod, realCloakLevel, realReport
		aiVar:SetBool(aiWas)
	end,
	cases = {
		{
			-- fails when the hook is not there, or when a camouflaged player is attacked by a device of JMod like anybody else
			name = "a sentry of JMod does not take a camouflaged player for a target (it recognises by sight)",
			func = function()
				expect(shouldAttack(player({__cloak = 1}))).to.equal(false)
				expect(shouldAttack(player({__cloak = 0.6}))).to.equal(false)
			end
		},
		{
			-- fails when a mine goes by the camouflage: it goes off under the feet whatever the player is seen as (the camouflage hides from the visible light only)
			name = "a mine of JMod goes off for a camouflaged player like for anybody: no opinion",
			func = function()
				expect(shouldAttack(player({__cloak = 1}), mine)).to.beNil()
				expect(shouldAttack(player({__cloak = 1}), atMine)).to.beNil()
				expect(shouldAttack(player({__cloak = 1}), {IsValid = function() return true end, GetClass = function() return "ent_jack_gmod_ezbomb" end})).to.beNil()
			end
		},
		{
			-- fails when a player who is not camouflaged (or hardly: the fade has just begun), an NPC or a prop is answered for: the answer nil leaves JMod's own rule
			name = "no opinion for a player who is not camouflaged, one in the first part of the fade, and for what is not a player",
			func = function()
				expect(shouldAttack(player({__cloak = 0}))).to.beNil()
				expect(shouldAttack(player({__cloak = 0.3}))).to.beNil()
				expect(shouldAttack({IsValid = function() return true end, IsPlayer = function() return false end, IsNPC = function() return true end})).to.beNil()
			end
		},
		{
			-- fails when the patch ignores the administrators' switch that makes the enemies forget a camouflaged player (gry_cloak_ai)
			name = "with the setting that makes the enemies forget a camouflaged player off, JMod's devices attack him as before",
			func = function()
				aiVar:SetBool(false)

				expect(shouldAttack(player({__cloak = 1}))).to.beNil()
			end
		},
		{
			-- fails when the hook raises an error into JMod's attack code for a bad target
			name = "a target that is not valid, or has no player methods, raises nothing",
			func = function()
				expect(shouldAttack(nil)).to.beNil()
				expect(shouldAttack({})).to.beNil()
			end
		},
		{
			-- fails when a grenade thrown by the hand (JMod's own throw: the player holds it and presses the attack key) does not end the camouflage
			name = "the attack key with a JMod grenade in the hand is an attack: the camouflage ends; the right click is the soft throw",
			func = function()
				local nade = {IsValid = function() return true end, GetClass = function() return "ent_jack_gmod_ezfragnade" end, Base = "ent_jack_gmod_ezgrenade"}
				local ply = player({__held = nade})

				press(ply, IN_ATTACK)
				press(ply, IN_ATTACK2)

				expect(#reports).to.equal(2)
				expect(reports[1][1]).to.equal(ply)
				expect(reports[1][2]).to.equal(false)
				expect(reports[2][2]).to.equal(true)
			end
		},
		{
			-- fails when a key press with nothing in the hands, with something that is no danger (a resource box), or another key, is told as an attack
			name = "nothing is told when the hands are empty, hold a resource box, or the key is not an attack",
			func = function()
				local box = {IsValid = function() return true end, GetClass = function() return "ent_jack_gmod_ezsteel" end}

				press(player(), IN_ATTACK)
				press(player({__held = box}), IN_ATTACK)
				press(player({__held = {IsValid = function() return true end, GetClass = function() return "ent_jack_gmod_ezfragnade" end}}), IN_USE)

				expect(#reports).to.equal(0)
			end
		},
		{
			-- fails when the patch raises an error without JMod (the global is not there) or when JMod's function raises one: a hook of the key press must never break the game's
			name = "without JMod, or with a JMod that fails, a key press raises nothing and tells nothing",
			func = function()
				local nade = {IsValid = function() return true end, GetClass = function() return "x" end}

				JMod = nil
				press(player({__held = nade}), IN_ATTACK)

				JMod = {GetPlayerHeldEntity = function() error("boom") end}
				press(player({__held = nade}), IN_ATTACK)

				expect(#reports).to.equal(0)
			end
		}
	}
}
