-- Tests of the mass of a prop for the use prompt (GryMod.UsableMass, sv_usable_mass.lua), GLuaTest format, server realm. The client has no
-- physics object for a prop of the server (its GetPhysicsObject is invalid), so it cannot tell a 90 kg drum from a 10 kg crate: it asks the server, which
-- answers with the mass the game itself uses to decide whether +use lifts the prop (all the physics objects of the entity added up).

local spawned = {}

local function spawn(model, mass)
	local ent = ents.Create("prop_physics")

	ent:SetModel(model)
	ent:SetPos(Vector(0, 0, 4000))
	ent:Spawn()
	spawned[#spawned + 1] = ent

	if mass then
		ent:GetPhysicsObject():SetMass(mass)
	end

	return ent
end

return {
	groupName = "GryMod use prompt: the mass of a prop (server)",
	afterEach = function()
		for _, e in ipairs(spawned) do
			if IsValid(e) then e:Remove() end
		end

		spawned = {}
	end,
	cases = {
		{
			-- fails without GryMod.UsableMass (sv_usable_mass.lua)
			name = "the module and its two net messages exist",
			func = function()
				expect(GryMod.UsableMass ~= nil).to.beTrue()
				expect(util.NetworkStringToID("gry_mass_ask") ~= 0).to.beTrue()
				expect(util.NetworkStringToID("gry_mass") ~= 0).to.beTrue()
				expect(net.Receivers["gry_mass_ask"] ~= nil).to.beTrue()
			end
		},
		{
			-- fails when the mass is not the physics object's own
			name = "Of(ent) is the mass the prop really has: a heavy one is heavy, a light one light, a mass set later is read",
			func = function()
				local drum = spawn("models/props_c17/oildrum001.mdl", 90)
				local can = spawn("models/props_junk/PopCan01a.mdl")

				expect(GryMod.UsableMass.Of(drum)).to.equal(90)
				expect(GryMod.UsableMass.Of(can) < 5).to.beTrue()

				drum:GetPhysicsObject():SetMass(12)
				expect(GryMod.UsableMass.Of(drum)).to.equal(12)
			end
		},
		{
			-- fails when something that has no physics answers a number
			name = "Of gives nil for what has no physics (a bad value, an invalid entity, an entity without a physics object)",
			func = function()
				expect(GryMod.UsableMass.Of(nil)).to.beNil()
				expect(GryMod.UsableMass.Of(NULL)).to.beNil()
				expect(GryMod.UsableMass.Of({})).to.beNil()
				expect(GryMod.UsableMass.Of({IsValid = function() return true end, GetPhysicsObject = function() return NULL end})).to.beNil()
			end
		},
		{
			-- fails when the masses of a ragdoll's bones are not added up (the game's CanPickupObject adds them)
			name = "an entity with several physics objects adds their masses up",
			func = function()
				local bones = {{GetMass = function() return 20 end, IsValid = function() return true end}, {GetMass = function() return 30 end, IsValid = function() return true end}}
				local fakeRagdoll = {
					IsValid = function() return true end,
					GetPhysicsObjectCount = function() return 2 end,
					GetPhysicsObjectNum = function(_, i) return bones[i + 1] end
				}

				expect(GryMod.UsableMass.Of(fakeRagdoll)).to.equal(50)
			end
		},
		{
			-- fails when a player can flood the server with questions
			name = "a player may ask 10 times a second, the questions beyond are ignored; the answer is sent to the asker for the entity index asked",
			func = function()
				local drum = spawn("models/props_c17/oildrum001.mdl", 90)
				local ply = player.GetAll()[1]
				local replies = {}
				local function reply(p, index, mass) replies[#replies + 1] = {p, index, mass} end

				GryMod.UsableMass.Forget(ply)

				for _ = 1, 15 do
					GryMod.UsableMass.Handle(ply, drum:EntIndex(), 100, reply)
				end

				expect(#replies).to.equal(10)
				expect(replies[1][1] == ply).to.beTrue()
				expect(replies[1][2]).to.equal(drum:EntIndex())
				expect(replies[1][3]).to.equal(90)

				-- a second later it answers again
				GryMod.UsableMass.Handle(ply, drum:EntIndex(), 101.5, reply)
				expect(#replies).to.equal(11)

				-- an index that is no entity: no answer
				GryMod.UsableMass.Forget(ply)
				GryMod.UsableMass.Handle(ply, 4000, 200, reply)
				expect(#replies).to.equal(11)
			end
		}
	}
}
