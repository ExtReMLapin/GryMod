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
	net.Start, net.WriteVector, net.WriteNormal, net.Send = real.Start, real.WriteVector, real.WriteNormal, real.Send
end

local function feedback(victim, attacker, amount)
	local dmg = DamageInfo()
	dmg:SetDamage(amount or 10)
	dmg:SetDamageType(DMG_BULLET)

	if attacker then
		dmg:SetAttacker(attacker)
	end

	startRecording()
	local ok, err = pcall(hook.GetTable().EntityTakeDamage["GryMod feedback"], victim, dmg)
	stopRecording()
	assert(ok, err)

	return sent
end

local spawned = {}

local function spawnNPC(class, pos)
	local npc = ents.Create(class)
	npc:SetPos(pos)
	npc:Spawn()
	spawned[#spawned + 1] = npc

	return npc
end

return {
	groupName = "GryMod crosshair feedback",
	afterEach = function(state)
		local p = ply()

		if IsValid(p) then
			p.gryNextDamageDir = nil
		end

		for _, e in ipairs(spawned) do
			if IsValid(e) then e:Remove() end
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
		}
	}
}
