-- Tests of the registry of weapon parts (GryMod.API.AddWeaponPartsProvider / RemoveWeaponPartsProvider / GetWeaponParts, lua/grymod/client/cl_api.lua), GLuaTest format, client
-- realm. A weapon can draw models of its own that are not its view model (the attachments of a weapon base: a sight, a silencer, a laser): the engine does not know them, so
-- the suit's effects (the camouflage) would leave them plain. A provider says which they are, for a weapon, at the moment it is asked: nothing is kept between two calls, so
-- an attachment that is changed while the effect runs is the next frame's list. The provider runs under SafeCall (five errors in a row switch it off), what it gives is
-- checked (only valid entities), at most MAX_WEAPON_PARTS of them, and the list is the caller's own table, reused. Each case names the production change whose absence makes it fail.

local API = GryMod.API
local made, ids

local function part()
	local ent = ClientsideModel("models/props_junk/PopCan01a.mdl", RENDERGROUP_OTHER)

	made[#made + 1] = ent
	ent:SetNoDraw(true)

	return ent
end

local function provider(id, fn)
	ids[#ids + 1] = id

	return API.AddWeaponPartsProvider(id, fn)
end

-- a weapon stand-in: a table that answers IsValid
local function weapon(class)
	return {IsValid = function() return true end, class = class or "test"}
end

return {
	groupName = "GryMod extension API: weapon parts (client)",
	beforeEach = function()
		made, ids = {}, {}
	end,
	afterEach = function()
		pcall(function()
			for _, id in ipairs(ids) do
				API.RemoveWeaponPartsProvider(id)
			end

			for _, ent in ipairs(made) do
				if IsValid(ent) then
					ent:Remove()
				end
			end
		end)
	end,
	cases = {
		{
			-- fails without the functions, or when a bad id or function is accepted
			name = "AddWeaponPartsProvider takes a text id and a function, and answers false for anything else; the feature is announced",
			func = function()
				expect(API.Has("weaponparts")).to.beTrue()
				expect(provider("test.a", function() end)).to.beTrue()
				expect(API.AddWeaponPartsProvider("", function() end)).to.beFalse()
				expect(API.AddWeaponPartsProvider(5, function() end)).to.beFalse()
				expect(API.AddWeaponPartsProvider("test.b", "no")).to.beFalse()
				expect(API.AddWeaponPartsProvider("test.b")).to.beFalse()
			end
		},
		{
			-- fails when the parts of the providers are not all collected in the order the providers were added, or the list is not the caller's own reused table with its tail cleared
			name = "GetWeaponParts: the parts of every provider in the order they were added, into the caller's table (reused, the tail cleared), with their count",
			func = function()
				local a, b, c = part(), part(), part()

				provider("test.first", function(_, out) out[#out + 1] = a out[#out + 1] = b end)
				provider("test.second", function(_, out) out[#out + 1] = c end)

				local out = {}
				local list, count = API.GetWeaponParts(weapon(), out)

				expect(list).to.equal(out)
				expect(count).to.equal(3)
				expect(list[1]).to.equal(a)
				expect(list[2]).to.equal(b)
				expect(list[3]).to.equal(c)

				-- a second call with a shorter result clears what the first left
				API.RemoveWeaponPartsProvider("test.second")
				API.RemoveWeaponPartsProvider("test.first")
				provider("test.one", function(_, o) o[#o + 1] = b end)
				list, count = API.GetWeaponParts(weapon(), out)
				expect(count).to.equal(1)
				expect(list[1]).to.equal(b)
				expect(list[2]).to.beNil()
				expect(list[3]).to.beNil()
			end
		},
		{
			-- fails when the provider is asked about the weapon it was not given, or about a weapon that is not valid
			name = "GetWeaponParts: the provider is given the weapon it is asked about; no weapon, an invalid one or none at all give nothing and no error",
			func = function()
				local seen = {}

				provider("test.seen", function(w, out)
					seen[#seen + 1] = w
				end)

				local w = weapon()

				API.GetWeaponParts(w, {})
				expect(seen[1]).to.equal(w)

				for _, junk in ipairs({false, 5, "weapon", NULL}) do
					local _, count = API.GetWeaponParts(junk, {})

					expect(count).to.equal(0)
				end

				expect((select(2, API.GetWeaponParts(nil, {})))).to.equal(0)
				expect(#seen).to.equal(1)
			end
		},
		{
			-- fails when what a provider gives is not checked: a value that is no entity reaches DrawModel of the effects and raises an error at every frame
			name = "GetWeaponParts: only valid entities are kept (false, numbers, text, empty tables and NULL are dropped)",
			func = function()
				local good = part()

				provider("test.junk", function(_, out)
					out[#out + 1] = false
					out[#out + 1] = 5
					out[#out + 1] = "model"
					out[#out + 1] = {}
					out[#out + 1] = NULL
					out[#out + 1] = good
				end)

				local list, count = API.GetWeaponParts(weapon(), {})

				expect(count).to.equal(1)
				expect(list[1]).to.equal(good)
			end
		},
		{
			-- fails when the list is not capped (a weapon with hundreds of parts would draw them all at every frame)
			name = "GetWeaponParts: at most MAX_WEAPON_PARTS parts",
			func = function()
				provider("test.many", function(_, out)
					for _ = 1, API.MAX_WEAPON_PARTS + 10 do
						out[#out + 1] = part()
					end
				end)

				local _, count = API.GetWeaponParts(weapon(), {})

				expect(count).to.equal(API.MAX_WEAPON_PARTS)
			end
		},
		{
			-- fails when a provider that raises an error stops the others (or the effect), is asked again after the fifth error, or cannot be re-armed by adding it again
			name = "a provider that raises an error is skipped and the others still give their parts; five errors in a row switch it off; adding it again re-arms it",
			func = function()
				local good = part()
				local calls = 0

				provider("test.bad", function()
					calls = calls + 1
					error("broken provider")
				end)
				provider("test.good", function(_, out) out[#out + 1] = good end)

				for _ = 1, 8 do
					local list, count = API.GetWeaponParts(weapon(), {})

					expect(count).to.equal(1)
					expect(list[1]).to.equal(good)
				end

				expect(calls).to.equal(5) -- switched off after the fifth

				provider("test.bad", function() calls = calls + 1 end)
				API.GetWeaponParts(weapon(), {})
				expect(calls).to.equal(6)
			end
		},
		{
			-- fails when adding a provider with the same id adds a second one (a reloaded file would make every part twice), or Remove does not take it away
			name = "the same id replaces the provider (a reloaded file does not add a second one), and RemoveWeaponPartsProvider takes it away",
			func = function()
				local p = part()

				provider("test.same", function(_, out) out[#out + 1] = p end)
				provider("test.same", function(_, out) out[#out + 1] = p end)

				local _, count = API.GetWeaponParts(weapon(), {})

				expect(count).to.equal(1)
				expect(API.RemoveWeaponPartsProvider("test.same")).to.beTrue()
				expect(API.RemoveWeaponPartsProvider("test.same")).to.beFalse()
				_, count = API.GetWeaponParts(weapon(), {})
				expect(count).to.equal(0)
			end
		}
	}
}
