-- Tests of GryMod.API.ClientRelation (lua/grymod/client/cl_api.lua) and of the relation of the crosshair it reuses (GryMod.FlashCrosshair.RelationName / OnAnswer / ReadAnswer),
-- GLuaTest format, client realm (SHARED-CLIENT-RELATION-1). The relation chain lives on the server; an addon's client code asks the answer the crosshair already gets: "ally",
-- "neutral" or "hostile", nil until the server has answered. Each case names the production change whose absence makes it fail.

local API = GryMod.API
local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function restore()
	for i = #saved, 1, -1 do
		local entry = saved[i]
		entry[1][entry[2]] = entry[3]
	end

	saved = {}
end

-- an entity stand-in
local function entity(index, fields)
	local e = {
		IsValid = function() return true end,
		IsPlayer = function() return false end,
		EntIndex = function() return index end
	}

	for key, value in pairs(fields or {}) do
		e[key] = value
	end

	return e
end

local function team(number, index)
	return entity(index or 900, {IsPlayer = function() return true end, Team = function() return number end})
end

return {
	groupName = "GryMod extension API: ClientRelation (client)",
	beforeEach = function()
		GryMod.FlashCrosshair.ForgetRelations()
	end,
	afterEach = function()
		pcall(restore)
		pcall(GryMod.FlashCrosshair.ForgetRelations)
	end,
	cases = {
		{
			-- fails without the function or the feature name
			name = "ClientRelation exists and is announced by Has(\"clientrelation\"); what is not an entity gives nil and asks nothing",
			func = function()
				local asked = 0

				stub(GryMod.FlashCrosshair, "AskServer", function() asked = asked + 1 end)

				expect(API.Has("clientrelation")).to.beTrue()
				expect(API.ClientRelation(nil)).to.beNil()
				expect(API.ClientRelation(NULL)).to.beNil()
				expect(API.ClientRelation(5)).to.beNil()
				expect(API.ClientRelation("npc")).to.beNil()
				expect(asked).to.equal(0)
			end
		},
		{
			-- fails when the first call does not send the question (nil forever), or sends it again at every call
			name = "an entity the server has not answered about gives nil and sends ONE question (its index); once the answer is there it gives the relation, hostile included",
			func = function()
				local Cross = GryMod.FlashCrosshair
				local asked = {}
				local npc = entity(77)

				stub(Cross, "AskServer", function(index) asked[#asked + 1] = index end)

				expect(API.ClientRelation(npc)).to.beNil()
				expect(API.ClientRelation(npc)).to.beNil()
				expect(#asked).to.equal(1)
				expect(asked[1]).to.equal(77)

				Cross.OnAnswer(77, false, RealTime(), "hostile")
				expect(API.ClientRelation(npc)).to.equal("hostile")

				Cross.OnAnswer(77, true, RealTime(), "ally")
				expect(API.ClientRelation(npc)).to.equal("ally")

				Cross.OnAnswer(77, false, RealTime(), "neutral")
				expect(API.ClientRelation(npc)).to.equal("neutral")
			end
		},
		{
			-- fails when a server that only says whether it is an ally (the older message) is read as hostile, or its answer is lost
			name = "an answer without the relation (the older message) is \"ally\" when it is an ally and \"neutral\" otherwise; an answer of two seconds ago is dropped",
			func = function()
				local Cross = GryMod.FlashCrosshair
				local npc = entity(78)

				stub(Cross, "AskServer", function() end)

				Cross.OnAnswer(78, true, 10)
				expect(Cross.RelationName(npc, 10.5)).to.equal("ally")
				Cross.OnAnswer(78, false, 11)
				expect(Cross.RelationName(npc, 11.1)).to.equal("neutral")
				expect(Cross.RelationName(npc, 13.5)).to.beNil()
			end
		},
		{
			-- fails when the questions of an addon do not go through the crosshair's limit (a map of entities asked in a frame would flood the server)
			name = "the questions share the crosshair's limit: ten entities asked in one second send at most five questions",
			func = function()
				local Cross = GryMod.FlashCrosshair
				local asked = 0

				stub(Cross, "AskServer", function() asked = asked + 1 end)

				for i = 1, 10 do
					Cross.RelationName(entity(100 + i), 50 + i * 0.1)
				end

				expect(asked <= 5).to.beTrue()
				expect(asked >= 1).to.beTrue()
			end
		},
		{
			-- fails when a player is asked to the server (it is known from the teams), or a player of another team is an ally, or the player himself is
			name = "a player is answered at once from the teams: ally for the same team (when there are teams), neutral for another team, unassigned (1001) or spectator (1002), and for himself; nothing is asked",
			func = function()
				local Cross = GryMod.FlashCrosshair
				local me = team(3, 1)
				local asked = 0

				stub(Cross, "AskServer", function() asked = asked + 1 end)

				expect(Cross.PlayerRelation(team(3), me)).to.equal("ally")
				expect(Cross.PlayerRelation(team(4), me)).to.equal("neutral")
				expect(Cross.PlayerRelation(me, me)).to.equal("neutral")
				expect(Cross.PlayerRelation(team(1001), team(1001))).to.equal("neutral")
				expect(Cross.PlayerRelation(team(1002), team(1002))).to.equal("neutral")

				-- through the API: another player of the local player's team
				stub(_G, "LocalPlayer", function() return me end)
				expect(API.ClientRelation(team(3))).to.equal("ally")
				expect(API.ClientRelation(team(4))).to.equal("neutral")
				expect(asked).to.equal(0)
			end
		},
		{
			-- fails when an entity that has no index the server knows (a client side model) is asked (the 13 bit index would be written wrong)
			name = "an entity with an index of 0 or less (client side), or one that does not fit the question's 13 bits, is neutral and is not asked",
			func = function()
				local Cross = GryMod.FlashCrosshair
				local asked = 0

				stub(Cross, "AskServer", function() asked = asked + 1 end)

				expect(API.ClientRelation(entity(-1))).to.equal("neutral")
				expect(API.ClientRelation(entity(0))).to.equal("neutral")
				expect(API.ClientRelation(entity(9000))).to.equal("neutral")
				expect(asked).to.equal(0)
			end
		},
		{
			-- fails when the message is read as before (a bool only): the relation the server adds after it is never read, or an older message makes the reader fail
			name = "ReadAnswer reads the index and the bool, then the two bit relation code when the message has it (0 neutral, 1 ally, 2 hostile); the older message ends after the bool",
			func = function()
				local Cross = GryMod.FlashCrosshair

				local function reader(index, friendly, code)
					local reads = {13, 1}

					return {
						ReadUInt = function(bits) if bits == 13 then return index end return code end,
						ReadBool = function() return friendly end,
						BytesLeft = function() if code ~= nil then return 1, 2 end return 0, 0 end
					}
				end

				local index, friendly, relation = Cross.ReadAnswer(reader(300, true, nil))
				expect(index).to.equal(300)
				expect(friendly).to.beTrue()
				expect(relation).to.beNil()

				expect(select(3, Cross.ReadAnswer(reader(5, false, 2)))).to.equal("hostile")
				expect(select(3, Cross.ReadAnswer(reader(5, true, 1)))).to.equal("ally")
				expect(select(3, Cross.ReadAnswer(reader(5, false, 0)))).to.equal("neutral")
			end
		}
	}
}
