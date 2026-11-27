-- Tests of the registry of player parts (GryMod.API.AddPlayerPartsProvider / RemovePlayerPartsProvider / GetPlayerParts, lua/grymod/client/cl_api.lua) and of the client hook
-- GryMod_CloakChanged (lua/grymod/client/cl_cloak_fx.lua), GLuaTest format, client realm (SHARED-PLAYER-PARTS-1). A player can wear models of his own that the engine does not
-- know as part of him (armor, a backpack, a PAC outfit): the camouflage of another player would leave them plain. A provider says which they are, for a player, at the moment
-- it is asked (the same rules as the weapon parts); the camouflage lays its layers on them. The hook tells the others (an addon that hides its own parts) at each change of
-- the camouflage of ANY player. Each case names the production change whose absence makes it fail.

local API = GryMod.API
local made, ids
local saved = {}
local fakes = {} -- the fake players the camouflage module was given: never left in its states, whatever a case does

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function part()
	local ent = ClientsideModel("models/props_junk/PopCan01a.mdl", RENDERGROUP_OTHER)

	made[#made + 1] = ent
	ent:SetNoDraw(true)

	return ent
end

local function provider(id, fn)
	ids[#ids + 1] = id

	return API.AddPlayerPartsProvider(id, fn)
end

-- a player stand-in: a table that answers IsValid
local function person(name)
	return {IsValid = function() return true end, name = name or "test"}
end

-- a fake player for the camouflage module's Update (only what it asks for)
local function fakePlayer()
	local ply = {center = Vector(300, 0, 0)}
	local flag = true

	function ply:IsValid() return true end
	function ply:IsPlayer() return true end
	function ply:Alive() return true end
	function ply:GetNW2Bool(name) return name == "GryCloak" and flag end
	function ply:GetNW2Float(name, default) return default end
	function ply:GetVelocity() return Vector(0, 0, 0) end
	function ply:DrawShadow() end
	function ply:SetSwitch(value) flag = value end

	fakes[#fakes + 1] = ply

	return ply
end

return {
	groupName = "GryMod extension API: player parts and the camouflage hook (client)",
	beforeEach = function()
		made, ids = {}, {}
	end,
	afterEach = function()
		pcall(function()
			for _, id in ipairs(ids) do
				API.RemovePlayerPartsProvider(id)
			end

			for _, ent in ipairs(made) do
				if IsValid(ent) then
					ent:Remove()
				end
			end

			hook.Remove("GryMod_CloakChanged", "test.cloakchanged")

			for _, fake in ipairs(fakes) do
				GryMod.CloakFX.States[fake] = nil
			end

			fakes = {}

			if not next(GryMod.CloakFX.States) then
				GryMod.CloakFX.SetDrawHooks(false)
			end

			for i = #saved, 1, -1 do
				saved[i][1][saved[i][2]] = saved[i][3]
			end

			saved = {}
		end)
	end,
	cases = {
		{
			-- fails without the functions, or when a bad id or function is accepted
			name = "AddPlayerPartsProvider takes a text id and a function, and answers false for anything else; the feature is announced",
			func = function()
				expect(API.Has("playerparts")).to.beTrue()
				expect(provider("test.a", function() end)).to.beTrue()
				expect(API.AddPlayerPartsProvider("", function() end)).to.beFalse()
				expect(API.AddPlayerPartsProvider(5, function() end)).to.beFalse()
				expect(API.AddPlayerPartsProvider("test.b", "no")).to.beFalse()
				expect(API.AddPlayerPartsProvider("test.b")).to.beFalse()
			end
		},
		{
			-- fails when the providers are not all asked, when the player is not given to them, or when what they add is not in the caller's table
			name = "GetPlayerParts: each provider adds its entities to the caller's table, in the order of the providers, asked about the player; the count is returned",
			func = function()
				local ply = person()
				local a, b, c = part(), part(), part()
				local seen
				local out = {}

				provider("test.one", function(given, list) seen = given list[#list + 1] = a end)
				provider("test.two", function(_, list) list[#list + 1] = b list[#list + 1] = c end)

				local back, count = API.GetPlayerParts(ply, out)

				expect(back).to.equal(out)
				expect(count).to.equal(3)
				expect(out[1]).to.equal(a)
				expect(out[2]).to.equal(b)
				expect(out[3]).to.equal(c)
				expect(seen).to.equal(ply)

				-- the table is the caller's and is cleaned first: the next call does not pile up
				local _, again = API.GetPlayerParts(ply, out)
				expect(again).to.equal(3)
				expect(#out).to.equal(3)
			end
		},
		{
			-- fails when a value that is not a valid entity ends in the list (the camouflage would draw it), or an invalid player is asked
			name = "what a provider gives is checked: only valid entities stay; an invalid player or none gives an empty list and asks nobody",
			func = function()
				local ply = person()
				local good = part()
				local asked = 0

				provider("test.junk", function(_, list)
					asked = asked + 1
					list[#list + 1] = "model"
					list[#list + 1] = NULL
					list[#list + 1] = good
					list[#list + 1] = 5
				end)

				local out, count = API.GetPlayerParts(ply, {})
				expect(count).to.equal(1)
				expect(out[1]).to.equal(good)
				expect(asked).to.equal(1)

				for _, junk in ipairs({false, 5, "player", NULL}) do
					local _, none = API.GetPlayerParts(junk, {})
					expect(none).to.equal(0)
				end

				expect(select(2, API.GetPlayerParts(nil, {}))).to.equal(0)
				expect(asked).to.equal(1)
			end
		},
		{
			-- fails when the list is not bounded (a provider that gives hundreds of entities would draw them all, every frame)
			name = "the list holds MAX_PLAYER_PARTS at most, the first ones kept",
			func = function()
				local first = part()

				expect(API.MAX_PLAYER_PARTS).to.equal(16)

				provider("test.many", function(_, list)
					list[#list + 1] = first

					for _ = 1, 30 do
						list[#list + 1] = part()
					end
				end)

				local out, count = API.GetPlayerParts(person(), {})
				expect(count).to.equal(16)
				expect(out[1]).to.equal(first)
				expect(#out).to.equal(16)
			end
		},
		{
			-- fails when a provider that raises an error stops the others, is asked again after the fifth error, or cannot be re-armed by adding it again; or when it shares the weapon ids
			name = "a provider that raises an error is skipped and gives nothing, the next one still answers; five errors in a row switch it off; adding it again re-arms it",
			func = function()
				local calls = 0
				local good = part()
				local ply = person()

				provider("test.bad", function(_, list) calls = calls + 1 list[#list + 1] = part() error("broken provider") end)
				provider("test.good", function(_, list) list[#list + 1] = good end)

				for _ = 1, 8 do
					local out, count = API.GetPlayerParts(ply, {})
					expect(count).to.equal(1)
					expect(out[1]).to.equal(good)
				end

				expect(calls).to.equal(5)

				provider("test.bad", function() calls = calls + 1 end)
				API.GetPlayerParts(ply, {})
				expect(calls).to.equal(6)
			end
		},
		{
			-- fails when a player provider is also a weapon provider (the two registries are one), or the same id adds a second provider
			name = "the player and the weapon registries are two: a player provider is not asked for a weapon; the same id replaces; Remove takes it away",
			func = function()
				local asked = 0
				local mine = part()

				provider("test.same", function() asked = asked + 1 end)
				provider("test.same", function(_, list) list[#list + 1] = mine end)

				expect(select(2, API.GetWeaponParts(person(), {}))).to.equal(0)
				expect(asked).to.equal(0)
				expect(select(2, API.GetPlayerParts(person(), {}))).to.equal(1)
				expect(API.RemovePlayerPartsProvider("test.same")).to.beTrue()
				expect(API.RemovePlayerPartsProvider("test.same")).to.beFalse()
				expect(select(2, API.GetPlayerParts(person(), {}))).to.equal(0)
			end
		},
		{
			-- fails when the hook is not run at the start of a camouflage, runs at each frame, or does not tell the player, the state and the level
			name = "GryMod_CloakChanged(ply, on, level): once when a player's camouflage starts, once when it ends (not while the fade-out goes on), again at the next camouflage, for any player",
			func = function()
				local F = GryMod.CloakFX
				local told = {}
				local ply, other = fakePlayer(), fakePlayer()

				stub(_G, "FrameTime", function() return 0.05 end)
				hook.Add("GryMod_CloakChanged", "test.cloakchanged", function(who, on, level) told[#told + 1] = {who = who, on = on, level = level} end)

				F.Update(ply)
				F.Update(ply)
				F.Update(ply)
				expect(#told).to.equal(1)
				expect(told[1].who).to.equal(ply)
				expect(told[1].on).to.beTrue()
				expect(isnumber(told[1].level) and told[1].level >= 0 and told[1].level <= 1).to.beTrue()

				-- another player, not the local one: told too
				F.Update(other)
				expect(#told).to.equal(2)
				expect(told[2].who).to.equal(other)

				-- the switch goes off: told once, while the fade-out goes on for several frames
				ply:SetSwitch(false)
				F.Update(ply)
				F.Update(ply)
				expect(#told).to.equal(3)
				expect(told[3].who).to.equal(ply)
				expect(told[3].on).to.beFalse()

				-- on again
				ply:SetSwitch(true)
				F.Update(ply)
				expect(#told).to.equal(4)
				expect(told[4].on).to.beTrue()

				-- clean up: both plain again, forgotten
				stub(_G, "FrameTime", function() return 5 end)
				ply:SetSwitch(false)
				other:SetSwitch(false)

				for _ = 1, 3 do
					F.Update(ply)
					F.Update(other)
				end

				expect(F.States[ply]).to.beNil()
				expect(F.States[other]).to.beNil()
			end
		}
	}
}
