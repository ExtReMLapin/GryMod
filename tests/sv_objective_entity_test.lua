-- Tests of the map entity gry_objective (lua/entities/gry_objective.lua), GLuaTest format, server realm: a point entity a mapmaker places in Hammer to give an
-- objective with no Lua. Keyvalues: id, title, description, primary, radar, marker, startactive, follow, removeaction; inputs: Activate, Complete, Fail, Remove,
-- SetMain; outputs: OnActivated, OnCompleted, OnFailed, OnRemoved. It goes through the same GryMod.API as an addon, so every case reads the result there.
-- The entities are real and made here; they are called the way the engine calls them (KeyValue, AcceptInput). The objectives and the entities are removed after
-- each case, even when it fails. Each case names the production change whose absence makes it fail.

local API
local madeEnts, madeIds

-- a gry_objective with the keyvalues given, and the outputs it triggers recorded
local function make(keys, pos)
	local e = ents.Create("gry_objective")

	madeEnts[#madeEnts + 1] = e
	e:SetPos(pos or Vector(0, 0, 0))

	for k, v in pairs(keys or {}) do
		e:KeyValue(k, v)
	end

	e:Spawn()
	e.fired = {}
	e.TriggerOutput = function(self, name)
		self.fired[#self.fired + 1] = name
	end

	if keys and keys.id then
		madeIds[#madeIds + 1] = keys.id
	end

	return e
end

local function input(e, name)
	return e:AcceptInput(name, NULL, NULL, "")
end

local function scene(body)
	return function()
		madeEnts, madeIds = {}, {}

		local ok, err = pcall(body)

		pcall(function()
			for _, id in ipairs(madeIds) do
				API.RemoveObjective(id)
			end

			API.ClearObjectives()

			for _, e in ipairs(madeEnts) do
				if IsValid(e) then
					e:Remove()
				end
			end
		end)

		if not ok then
			error(err, 0)
		end
	end
end

return {
	groupName = "GryMod map entity gry_objective (server)",
	beforeAll = function()
		API = GryMod.API
	end,
	cases = {
		{
			-- breaks if: lua/entities/gry_objective.lua is missing, or is not a point entity (a mapmaker could not place it)
			name = "the entity exists and is a point entity that is not spawnable from the menu",
			func = function()
				local stored = scripted_ents.Get("gry_objective")

				expect(stored ~= nil).to.beTrue()
				expect(stored.Type).to.equal("point")
				expect(stored.Spawnable).to.beFalse()
			end
		},
		{
			-- breaks if: a keyvalue is not read, or the Activate input does not go through RegisterObjective with the entity's place
			name = "Activate registers the objective from the keyvalues, at the place of the entity, active; OnActivated is triggered",
			func = scene(function()
				local e = make({id = "gry_test_ent_a", title = "Find the key", description = "In the cellar.", primary = "0", radar = "0", marker = "1"}, Vector(10, 20, 30))

				expect(API.GetObjective("gry_test_ent_a")).to.beNil() -- nothing until the map says so

				expect(input(e, "Activate")).to.beTrue()

				local o = API.GetObjective("gry_test_ent_a")
				expect(o ~= nil).to.beTrue()
				expect(o.title).to.equal("Find the key")
				expect(o.description).to.equal("In the cellar.")
				expect(o.primary).to.beFalse()
				expect(o.radar).to.beFalse()
				expect(o.marker).to.beTrue()
				expect(o.state).to.equal("active")
				expect(o.pos == Vector(10, 20, 30)).to.beTrue()
				expect(o.ent).to.beNil()
				expect(table.concat(e.fired, ",")).to.equal("OnActivated")
			end)
		},
		{
			-- breaks if: the defaults of the entity differ from the API's (primary, radar and marker on) or the title is not the id when none is given
			name = "with no keyvalue but the id: primary, radar and marker are on, the title is the id",
			func = scene(function()
				local e = make({id = "gry_test_ent_b"})

				input(e, "Activate")

				local o = API.GetObjective("gry_test_ent_b")
				expect(o.title).to.equal("gry_test_ent_b")
				expect(o.primary).to.beTrue()
				expect(o.radar).to.beTrue()
				expect(o.marker).to.beTrue()
			end)
		},
		{
			-- breaks if: the objective has no id when the mapmaker gave none (the targetname, or a name made from the entity index, is the id)
			name = "no id keyvalue: the name of the entity is the id; no name either: an id made from the entity index",
			func = scene(function()
				local named = make({title = "Named"})
				named:SetName("gry_test_ent_name")
				madeIds[#madeIds + 1] = "gry_test_ent_name"
				input(named, "Activate")
				expect(API.GetObjective("gry_test_ent_name") ~= nil).to.beTrue()

				local anonymous = make({title = "Anonymous"})
				local id = "gry_objective_" .. anonymous:EntIndex()
				madeIds[#madeIds + 1] = id
				input(anonymous, "Activate")
				expect(API.GetObjective(id) ~= nil).to.beTrue()
			end)
		},
		{
			-- breaks if: Complete or Fail does not set the state, does not register an objective that was never activated, or the outputs are not triggered
			name = "Complete and Fail set the state (the objective is registered first when it was never activated) and trigger OnCompleted / OnFailed",
			func = scene(function()
				local done = make({id = "gry_test_ent_c", title = "Done"})
				local lost = make({id = "gry_test_ent_d", title = "Lost"})

				expect(input(done, "Complete")).to.beTrue()
				expect(API.GetObjective("gry_test_ent_c").state).to.equal("done")
				expect(table.concat(done.fired, ",")).to.equal("OnCompleted")

				input(lost, "Activate")
				expect(input(lost, "Fail")).to.beTrue()
				expect(API.GetObjective("gry_test_ent_d").state).to.equal("failed")
				expect(table.concat(lost.fired, ",")).to.equal("OnActivated,OnFailed")

				-- the inputs are not case sensitive, and a second Activate puts the objective back to active
				expect(input(lost, "ACTIVATE")).to.beTrue()
				expect(API.GetObjective("gry_test_ent_d").state).to.equal("active")
			end)
		},
		{
			-- breaks if: Remove leaves the objective or does not trigger OnRemoved; SetMain must not register anything by itself
			name = "Remove takes the objective away and triggers OnRemoved; SetMain makes it the main objective",
			func = scene(function()
				local e = make({id = "gry_test_ent_e", title = "Removable"})

				input(e, "Activate")
				expect(input(e, "SetMain")).to.beTrue()
				expect(API.GetObjective("gry_test_ent_e").main).to.beTrue()

				expect(input(e, "Remove")).to.beTrue()
				expect(API.GetObjective("gry_test_ent_e")).to.beNil()
				expect(e.fired[#e.fired]).to.equal("OnRemoved")

				-- removing what is not there is not an error
				expect(function() input(e, "Remove") end).to.succeed()
			end)
		},
		{
			-- breaks if: an input of the engine (Kill, FireUser1...) is swallowed: only the five of this entity are answered with true
			name = "an input that is not one of the entity's is not claimed",
			func = scene(function()
				local e = make({id = "gry_test_ent_f", title = "Other"})

				expect(input(e, "Kill") == true).to.beFalse()
				expect(API.GetObjective("gry_test_ent_f")).to.beNil()
			end)
		},
		{
			-- breaks if: follow is not read, or the objective sits on the entity itself instead of the one named
			name = "follow: the objective follows the entity with that name (onRemove from the removeaction keyvalue); a name nobody has falls back to the entity's own place",
			func = scene(function()
				local target = ents.Create("info_target")
				madeEnts[#madeEnts + 1] = target
				target:SetPos(Vector(500, 0, 0))
				target:SetName("gry_test_ent_target")
				target:Spawn()

				local e = make({id = "gry_test_ent_g", title = "Follow", follow = "gry_test_ent_target", removeaction = "complete"}, Vector(1, 1, 1))
				input(e, "Activate")

				local o = API.GetObjective("gry_test_ent_g")
				expect(o.ent == target).to.beTrue()
				expect(o.pos == Vector(500, 0, 0)).to.beTrue()
				expect(o.onRemove).to.equal("complete")

				local lonely = make({id = "gry_test_ent_h", title = "Lonely", follow = "gry_test_ent_nobody"}, Vector(2, 2, 2))
				input(lonely, "Activate")
				expect(API.GetObjective("gry_test_ent_h").ent).to.beNil()
				expect(API.GetObjective("gry_test_ent_h").pos == Vector(2, 2, 2)).to.beTrue()
			end)
		},
		{
			-- breaks if: startactive does not register at the start of the map, or registers when it is 0
			name = "startactive 1: the objective is registered when the map starts (OnStart); 0 or nothing: it waits for the input",
			func = scene(function()
				local on = make({id = "gry_test_ent_i", title = "On", startactive = "1"})
				local off = make({id = "gry_test_ent_j", title = "Off", startactive = "0"})

				expect(API.GetObjective("gry_test_ent_i")).to.beNil() -- not at Spawn: the other entities of the map are not there yet
				on:OnStart()
				off:OnStart()
				expect(API.GetObjective("gry_test_ent_i") ~= nil).to.beTrue()
				expect(API.GetObjective("gry_test_ent_i").state).to.equal("active")
				expect(API.GetObjective("gry_test_ent_j")).to.beNil()
			end)
		},
		{
			-- breaks if: the output keyvalues are not given to the engine (a map's connections would do nothing)
			name = "the keyvalues of the outputs are stored with the engine, whatever their case",
			func = scene(function()
				local e = ents.Create("gry_objective")
				local stored = {}

				madeEnts[#madeEnts + 1] = e
				e.StoreOutput = function(_, name, info) stored[#stored + 1] = name .. "=" .. info end

				e:KeyValue("OnActivated", "door,Open,,0,-1")
				e:KeyValue("oncompleted", "door,Close,,0,-1")
				e:KeyValue("id", "gry_test_ent_k")

				expect(table.concat(stored, ";")).to.equal("OnActivated=door,Open,,0,-1;oncompleted=door,Close,,0,-1")
			end)
		}
	}
}
