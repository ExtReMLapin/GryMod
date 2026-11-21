-- Tests of when the server asks the client for the armor hit sound and for the repair sound (sv_health.lua),
-- GLuaTest format, server realm. The conditions come from the original game's code (research notes
-- research-mech/NOTES.md, and for the armor hit BasicActor.lua Client:OnHit: the local player, bullet damage over 10,
-- armor over 10 after the hit, armor mode only). The sounds are not listened to: only the messages are checked.

local function ply()
	return player.GetAll()[1]
end

local sent
local real = {}

local function startRecording()
	sent = {}
	real.Start, real.Send = net.Start, net.Send
	net.Start = function(name)
		sent[#sent + 1] = {name = name}

		return true
	end
	net.Send = function(p)
		sent[#sent].to = p
	end
end

local function stopRecording()
	net.Start, net.Send = real.Start, real.Send
end

local function count(name)
	local n = 0

	for _, message in ipairs(sent) do
		if message.name == name then n = n + 1 end
	end

	return n
end

-- run a function with net.Start/net.Send recorded, whatever happens inside
local function recorded(fn)
	startRecording()
	local ok, err = pcall(fn)
	stopRecording()
	assert(ok, err)

	return sent
end

local function hit(p, amount, damageType)
	local dmg = DamageInfo()
	dmg:SetDamage(amount)
	dmg:SetDamageType(damageType or DMG_BULLET)

	return recorded(function()
		hook.GetTable().EntityTakeDamage["Grymod damage handeling"](p, dmg)
	end)
end

local function think()
	return recorded(function()
		hook.GetTable().Think["GryMod health think"]()
	end)
end

local savedConfig

return {
	groupName = "GryMod armor hit and repair sounds",
	beforeAll = function(state)
		savedConfig = table.Copy(GryMod.Config)
	end,
	beforeEach = function(state)
		local p = ply()
		if not p:Alive() then p:Spawn() end
		p:SetHealth(p:GetMaxHealth())
		p:SetNWFloat("GryEnergy", 100)
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		p.last_repair_sound = nil
		p.should_heath_regen = false
		p.next_health_regen = nil
		p.next_health_tick = nil
		GryMod.Config = table.Copy(savedConfig)
		GryMod.Config.ShouldRegen = true
		GryMod.Config.InfiniteArmor = false
		GryMod.Config.Mechanics = "crysis"
	end,
	afterEach = function(state)
		local p = ply()

		if IsValid(p) then
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
			p:SetHealth(p:GetMaxHealth())
			p.last_repair_sound = nil
			p.should_heath_regen = false
			p.next_health_regen = nil
		end

		GryMod.Config = table.Copy(savedConfig)
	end,
	cases = {
		-- the armor hit sound
		{
			name = "a bullet in armor mode with energy left plays the armor hit sound, to the player hit only",
			func = function(state)
				local p = ply()
				local messages = hit(p, 20)
				expect(count("gry_armor_hit_sound")).to.equal(1)
				expect(messages[1].to).to.equal(p)
			end
		},
		{
			name = "no armor hit sound outside the armor mode",
			func = function(state)
				local p = ply()
				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				hit(p, 20)
				expect(count("gry_armor_hit_sound")).to.equal(0)
			end
		},
		{
			name = "no armor hit sound for damage that is not a bullet (explosion, fall, melee)",
			func = function(state)
				local p = ply()
				hit(p, 20, DMG_BLAST)
				expect(count("gry_armor_hit_sound")).to.equal(0)
				hit(p, 20, DMG_FALL)
				expect(count("gry_armor_hit_sound")).to.equal(0)
				hit(p, 20, DMG_CLUB)
				expect(count("gry_armor_hit_sound")).to.equal(0)
			end
		},
		{
			name = "no armor hit sound for a hit of 5 percent of the health or less (the game's 10 of 200)",
			func = function(state)
				local p = ply()
				local limit = 10 * p:GetMaxHealth() / 200
				hit(p, limit)
				expect(count("gry_armor_hit_sound")).to.equal(0)
				hit(p, limit + 1)
				expect(count("gry_armor_hit_sound")).to.equal(1)
			end
		},
		{
			name = "no armor hit sound once the hit leaves the armor under a tenth of the bar (the game's armor of 10 or less)",
			func = function(state)
				local p = ply()
				-- 100 energy, 91 taken: 9 left, under 10
				p:SetNWFloat("GryEnergy", 100)
				hit(p, 91)
				expect(count("gry_armor_hit_sound")).to.equal(0)
				-- 100 energy, 80 taken: 20 left
				p:SetNWFloat("GryEnergy", 100)
				hit(p, 80)
				expect(count("gry_armor_hit_sound")).to.equal(1)
				-- an empty bar
				p:SetNWFloat("GryEnergy", 0)
				hit(p, 30)
				expect(count("gry_armor_hit_sound")).to.equal(0)
			end
		},
		{
			name = "the infinite armor cheat plays the armor hit sound too (the bar is full)",
			func = function(state)
				local p = ply()
				GryMod.Config.InfiniteArmor = true
				hit(p, 20)
				expect(count("gry_armor_hit_sound")).to.equal(1)
			end
		},
		{
			name = "gry_mechanics classic keeps the earlier rule: any bullet while the bar is not empty",
			func = function(state)
				local p = ply()
				GryMod.Config.Mechanics = "classic"
				hit(p, 2)
				expect(count("gry_armor_hit_sound")).to.equal(1)
				p:SetNWFloat("GryEnergy", 0)
				hit(p, 2)
				expect(count("gry_armor_hit_sound")).to.equal(0)
			end
		},
		-- the repair sound
		{
			name = "the repair sound starts as soon as the health is under 90 percent in armor mode, not after the regeneration delay",
			func = function(state)
				local p = ply()
				p:SetHealth(60)
				p.next_health_regen = CurTime() + 2.5
				think()
				expect(count("gry_start_health_regen")).to.equal(1)
				expect(p.last_repair_sound ~= nil).to.beTrue()
			end
		},
		{
			name = "the repair sound is not played outside the armor mode, with the health over 90 percent, or twice in 30 seconds",
			func = function(state)
				local p = ply()
				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				p:SetHealth(60)
				p.next_health_regen = CurTime() + 2.5
				think()
				expect(count("gry_start_health_regen")).to.equal(0)
				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
				p:SetHealth(p:GetMaxHealth() * 0.95)
				think()
				expect(count("gry_start_health_regen")).to.equal(0)
				p:SetHealth(60)
				think()
				expect(count("gry_start_health_regen")).to.equal(1)
				p:SetHealth(60)
				think()
				expect(count("gry_start_health_regen")).to.equal(0)
			end
		},
		{
			name = "a hit does not cut the repair sound (the game has no stop for it): the stop message is for the death only",
			func = function(state)
				local p = ply()
				p:SetHealth(60)
				p.next_health_regen = CurTime() + 2.5
				think()
				p:SetNWFloat("GryEnergy", 0)
				hit(p, 10)
				expect(count("gry_stop_health_regen")).to.equal(0)
				local dead = recorded(function()
					hook.GetTable().PlayerDeath["grymod death stop healing sound"](p)
				end)
				expect(count("gry_stop_health_regen")).to.equal(1)
			end
		},
		{
			name = "a new life starts without the 30 second wait of the last one",
			func = function(state)
				local p = ply()
				p.last_repair_sound = CurTime()
				hook.GetTable().PlayerSpawn["GryMod_ENER_HLT_VARS"](p)
				expect(p.last_repair_sound).to.beNil()
			end
		},
		{
			name = "gry_mechanics classic keeps the earlier repair sound: it starts with the regeneration, in any mode, and stops at full health",
			func = function(state)
				local p = ply()
				GryMod.Config.Mechanics = "classic"
				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				p:SetHealth(60)
				p.health_on_dmg = 60
				p.next_health_regen = CurTime() - 0.1
				think()
				expect(count("gry_start_health_regen")).to.equal(1)
				p:SetHealth(p:GetMaxHealth())
				think()
				expect(count("gry_stop_health_regen")).to.equal(1)
			end
		}
	}
}
