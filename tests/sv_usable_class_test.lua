-- Tests of the class of an entity for the use prompt (GryMod.UsableClass, sv_usable_class.lua), GLuaTest format, server realm. For a lot of the brush
-- entities of the game (func_button, momentary_rot_button...) the client has no class of its own: ent:GetClass() there says "class C_BaseToggle", the
-- name of the network class, so the registry of usable things cannot tell a button from a wheel. The client asks the server, which answers with the
-- class name the map gave the entity.

local spawned = {}

local function spawn(class)
	local ent = ents.Create(class)

	ent:SetPos(Vector(0, 0, 4000))
	ent:Spawn()
	spawned[#spawned + 1] = ent

	return ent
end

return {
	groupName = "GryMod use prompt: the class of an entity (server)",
	afterEach = function()
		for _, e in ipairs(spawned) do
			if IsValid(e) then e:Remove() end
		end

		spawned = {}
	end,
	cases = {
		{
			-- fails without GryMod.UsableClass (sv_usable_class.lua)
			name = "the module and its two net messages exist",
			func = function()
				expect(GryMod.UsableClass ~= nil).to.beTrue()
				expect(util.NetworkStringToID("gry_class_ask") ~= 0).to.beTrue()
				expect(util.NetworkStringToID("gry_class") ~= 0).to.beTrue()
				expect(net.Receivers["gry_class_ask"] ~= nil).to.beTrue()
			end
		},
		{
			-- fails when the answer is not the server's own class name
			name = "Of(ent) is the class the server gives the entity, nil for what is not an entity",
			func = function()
				expect(GryMod.UsableClass.Of(spawn("prop_physics"))).to.equal("prop_physics")
				expect(GryMod.UsableClass.Of(spawn("info_target"))).to.equal("info_target")
				expect(GryMod.UsableClass.Of(nil)).to.beNil()
				expect(GryMod.UsableClass.Of(NULL)).to.beNil()
				expect(GryMod.UsableClass.Of({})).to.beNil()
			end
		},
		{
			-- fails when a player can flood the server with questions
			name = "a player may ask 10 times a second, the questions beyond are ignored; the answer goes to the asker with the entity index and the class",
			func = function()
				local ent = spawn("info_target")
				local ply = player.GetAll()[1]
				local replies = {}
				local function reply(p, index, class) replies[#replies + 1] = {p, index, class} end

				GryMod.UsableClass.Forget(ply)

				for _ = 1, 15 do
					GryMod.UsableClass.Handle(ply, ent:EntIndex(), 100, reply)
				end

				expect(#replies).to.equal(10)
				expect(replies[1][1] == ply).to.beTrue()
				expect(replies[1][2]).to.equal(ent:EntIndex())
				expect(replies[1][3]).to.equal("info_target")

				-- a second later it answers again
				GryMod.UsableClass.Handle(ply, ent:EntIndex(), 101.5, reply)
				expect(#replies).to.equal(11)

				-- an index that is no entity: no answer
				GryMod.UsableClass.Forget(ply)
				GryMod.UsableClass.Handle(ply, 4000, 200, reply)
				expect(#replies).to.equal(11)
			end
		}
	}
}
