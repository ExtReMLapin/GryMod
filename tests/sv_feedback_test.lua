-- Tests of what the server tells the client for the crosshair (GryMod.Feedback), GLuaTest format, server realm:
-- the direction of the damage taken (the arcs around the crosshair) and a hit on a living target (the hit marker).

local function ply()
	return player.GetAll()[1]
end

local sent
local real = {}

local function startRecording()
	sent = {}
	real.Start, real.WriteVector, real.WriteNormal, real.Send = net.Start, net.WriteVector, net.WriteNormal, net.Send
	net.Start = function(name)
		sent[#sent + 1] = {name = name}

		return true
	end
	net.WriteVector = function(v)
		sent[#sent].vector = v
	end
	net.WriteNormal = function(v)
		sent[#sent].normal = v
	end
	net.Send = function(p)
		sent[#sent].to = p
	end
end

local function stopRecording()
	if real.Start then
		net.Start, net.WriteVector, net.WriteNormal, net.Send = real.Start, real.WriteVector, real.WriteNormal, real.Send
	end
end

-- Both hooks that see a hit, run in the order given. The engine runs the EntityTakeDamage hooks in no fixed order, and
-- the suit's armor (sv_health.lua) can take all of a hit (damage 0) before the other hook looks at it: whatever the
-- order, the same thing must be told. Only the two crosshair messages are kept (the suit sends others of its own).
local function run(order, victim, attacker, amount)
	local dmg = DamageInfo()
	dmg:SetDamage(amount or 10)
	dmg:SetDamageType(DMG_BULLET)

	if attacker then
		dmg:SetAttacker(attacker)
	end

	local handlers = {
		health = hook.GetTable().EntityTakeDamage["Grymod damage handeling"],
		feedback = hook.GetTable().EntityTakeDamage["GryMod feedback"]
	}

	startRecording()
	local ok, err = pcall(function()
		for _, name in ipairs(order) do
			handlers[name](victim, dmg)
		end
	end)
	stopRecording()
	assert(ok, err)

	local list = {}

	for _, m in ipairs(sent) do
		if m.name == "gry_hit" or m.name == "gry_damage_dir" then
			list[#list + 1] = m
		end
	end

	return list, dmg
end

local function feedback(victim, attacker, amount)
	return (run({"health", "feedback"}, victim, attacker, amount))
end

-- the same with the suit's armor on
local function armorHit(order, victim, attacker, amount, energy)
	victim.Nanosuit_mode = GryMod.Modes.ARMOR
	victim:SetNWFloat("GryEnergy", energy)

	return run(order, victim, attacker, amount)
end

local ORDERS = {{"health", "feedback"}, {"feedback", "health"}}

local spawned = {}
local savedMode, savedEnergy, savedInfinite

local function spawnNPC(class, pos)
	local npc = ents.Create(class)
	npc:SetPos(pos)
	npc:Spawn()
	spawned[#spawned + 1] = npc

	return npc
end

return {
	groupName = "GryMod crosshair feedback",
	beforeEach = function(state)
		local p = ply()
		savedMode, savedEnergy, savedInfinite = p.Nanosuit_mode, p:GetNWFloat("GryEnergy"), GryMod.Config.InfiniteArmor
	end,
	afterEach = function(state)
		local p = ply()

		if IsValid(p) then
			p.gryNextDamageDir = nil
			p.Nanosuit_mode = savedMode
			p:SetNWFloat("GryEnergy", savedEnergy)
		end

		GryMod.Config.InfiniteArmor = savedInfinite

		for _, e in ipairs(spawned) do
			if IsValid(e) and e:IsPlayer() then
				e:Kick("test over")
			elseif IsValid(e) then
				e:Remove()
			end
		end

		spawned = {}
	end,
	cases = {
		{
			name = "the two messages exist",
			func = function(state)
				expect(util.NetworkStringToID("gry_hit") ~= 0).to.beTrue()
				expect(util.NetworkStringToID("gry_damage_dir") ~= 0).to.beTrue()
			end
		},
		{
			name = "a player hurt by an NPC is told the direction of the NPC, not its position",
			func = function(state)
				local p = ply()
				local npc = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))
				local list = feedback(p, npc)
				expect(#list).to.equal(1)
				expect(list[1].name).to.equal("gry_damage_dir")
				expect(list[1].to).to.equal(p)
				expect(list[1].vector).to.beNil()
				expect(list[1].normal:Distance(Vector(1, 0, 0)) < 0.01).to.beTrue()
			end
		},
		{
			name = "damage from the world, from the player itself or of no amount tells nothing",
			func = function(state)
				local p = ply()
				expect(#feedback(p, game.GetWorld())).to.equal(0)
				expect(#feedback(p, nil)).to.equal(0)
				expect(#feedback(p, p)).to.equal(0)
				local npc = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))
				expect(#feedback(p, npc, 0)).to.equal(0)
			end
		},
		{
			name = "the damage direction is sent at most ten times a second to a player (a shotgun fires many pellets at once)",
			func = function(state)
				local p = ply()
				local npc = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))
				expect(#feedback(p, npc)).to.equal(1)
				expect(#feedback(p, npc)).to.equal(0)
				p.gryNextDamageDir = CurTime() - 0.01
				expect(#feedback(p, npc)).to.equal(1)
			end
		},
		{
			name = "a player who hurts an NPC is told with a hit message, nothing for a prop or for hurting itself",
			func = function(state)
				local p = ply()
				local npc = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))
				local list = feedback(npc, p)
				expect(#list).to.equal(1)
				expect(list[1].name).to.equal("gry_hit")
				expect(list[1].to).to.equal(p)

				local prop = ents.Create("prop_physics")
				prop:SetModel("models/props_junk/wood_crate001a.mdl")
				prop:SetPos(p:GetPos() + Vector(0, 300, 0))
				prop:Spawn()
				spawned[#spawned + 1] = prop
				expect(#feedback(prop, p)).to.equal(0)
				expect(#feedback(p, p)).to.equal(0)
			end
		},
		{
			name = "a hit the armor takes all of still tells the direction, whatever the order of the two hooks",
			func = function(state)
				local p = ply()
				local npc = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))

				for _, order in ipairs(ORDERS) do
					p.gryNextDamageDir = nil
					local list, dmg = armorHit(order, p, npc, 10, 100)
					expect(#list).to.equal(1)
					expect(list[1].name).to.equal("gry_damage_dir")
					expect(list[1].to).to.equal(p)
					expect(list[1].normal:Distance(Vector(1, 0, 0)) < 0.01).to.beTrue()

					if order[1] == "health" then
						-- the armor did take it all: the amount the suit leaves is 0
						expect(dmg:GetDamage()).to.equal(0)
					end
				end
			end
		},
		{
			name = "a hit that outruns the bar, or on the infinite armor, tells the direction in both orders too",
			func = function(state)
				local p = ply()
				local npc = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))

				for _, order in ipairs(ORDERS) do
					p.gryNextDamageDir = nil
					local list = armorHit(order, p, npc, 10, 0)
					expect(#list).to.equal(1)
					expect(list[1].name).to.equal("gry_damage_dir")

					p.gryNextDamageDir = nil
					GryMod.Config.InfiniteArmor = true
					list = armorHit(order, p, npc, 10, 100)
					GryMod.Config.InfiniteArmor = savedInfinite
					expect(#list).to.equal(1)
					expect(list[1].name).to.equal("gry_damage_dir")
				end
			end
		},
		{
			name = "a hit of no amount at the start tells nothing with the armor on, in both orders",
			func = function(state)
				local p = ply()
				local npc = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))

				for _, order in ipairs(ORDERS) do
					p.gryNextDamageDir = nil
					expect(#armorHit(order, p, npc, 0, 100)).to.equal(0)
					expect(#armorHit(order, p, npc, 0, 0)).to.equal(0)
				end
			end
		},
		{
			name = "a hit marker is sent for a living target whose armor takes the hit, in both orders",
			func = function(state)
				local p = ply()
				local bot = player.CreateNextBot("GryFeedbackBot")

				if not IsValid(bot) then
					return
				end

				spawned[#spawned + 1] = bot
				bot:Spawn()

				for _, order in ipairs(ORDERS) do
					local list = armorHit(order, bot, p, 10, 100)
					expect(#list).to.equal(2)
					local names = {}

					for _, m in ipairs(list) do
						names[m.name] = m.to
					end

					expect(names.gry_hit).to.equal(p)
					expect(names.gry_damage_dir).to.equal(bot)
					bot.gryNextDamageDir = nil
				end

				expect(#armorHit({"health", "feedback"}, bot, p, 0, 100)).to.equal(0)
			end
		},
		{
			name = "the feedback hook alone says nothing for a player: the suit's hook reports the hits on players, once",
			func = function(state)
				local p = ply()
				local npc = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))
				expect(#run({"feedback"}, p, npc, 10)).to.equal(0)
				expect(#run({"health"}, p, npc, 10)).to.equal(1)
				p.gryNextDamageDir = nil
				expect(#run({"health", "feedback"}, p, npc, 10)).to.equal(1)
			end
		}
	}
}
