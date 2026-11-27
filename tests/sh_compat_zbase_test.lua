-- Tests of the ZBase adapter (lua/grymod/compat/npc/sh_zbase.lua), GLuaTest format, runs in the server AND in the client realm. ZBase's NPCs are real engine NPCs wrapped in Lua, with three things
-- GryMod must know: Entity:GetClass is replaced (a ZBase hunter answers "zb_hunter": the class providers of the API give the real class back), the NPC that ZBase replaces stays as an invisible
-- "dull" copy that must never be a contact, and its projectiles (the rocket and the mortar of the NPCs) are dangers. ZBase is stood in for. Each case names the change that makes it fail.

local API
local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

-- an NPC of ZBase: GetClass answers the wrapper's name unless the flag of ZBase is up
local function zbaseNpc(wrapped, real, fields)
	local npc = {}

	function npc:IsValid() return true end
	function npc:GetNWBool(key, default)
		if key == "IsZBaseNPC" then return true end

		return fields and fields[key] or default or false
	end
	function npc:GetClass()
		if _G.ZBASE_SkipClassNameWrapper then return real end

		return wrapped
	end

	return npc
end

return {
	groupName = "GryMod compat: ZBase NPCs (shared)",
	beforeEach = function()
		API = GryMod.API
		saved = {}
		stub(_G, "ZBaseInstalled", true)
		stub(_G, "ZBASE_SkipClassNameWrapper", false)
	end,
	afterEach = function()
		for i = #saved, 1, -1 do
			saved[i][1][saved[i][2]] = saved[i][3]
		end

		saved = {}
	end,
	cases = {
		{
			-- fails when no class provider is added (ClassOf answers "zb_hunter"), or when the flag of ZBase is not put back after the call (every later GetClass of any NPC would be wrong)
			name = "the real class of a ZBase NPC is the class under the wrapper, and the flag of ZBase is put back",
			func = function()
				local npc = zbaseNpc("zb_hunter", "npc_hunter")

				expect(npc:GetClass()).to.equal("zb_hunter")
				expect(API.ClassOf(npc)).to.equal("npc_hunter")
				expect(_G.ZBASE_SkipClassNameWrapper).to.equal(false)
			end
		},
		{
			-- fails when an error inside GetClass leaves the flag up
			name = "the flag is put back even when GetClass raises an error",
			func = function()
				local npc = zbaseNpc("zb_hunter", "npc_hunter")

				npc.GetClass = function() error("broken") end
				pcall(API.ClassOf, npc) -- (the entity's own GetClass raises the error again after the provider gave up)

				expect(_G.ZBASE_SkipClassNameWrapper).to.equal(false)
			end
		},
		{
			-- fails when the provider answers for an entity that is not a ZBase NPC, or does anything when ZBase is not installed (it must not even ask the entity)
			name = "an entity that is not a ZBase NPC keeps its class, and nothing is asked when ZBase is not there",
			func = function()
				local plain = {IsValid = function() return true end, GetClass = function() return "npc_combine_s" end, GetNWBool = function() return false end}

				expect(API.ClassOf(plain)).to.equal("npc_combine_s")

				_G.ZBaseInstalled = nil

				local never = {IsValid = function() return true end, GetClass = function() return "zb_x" end, GetNWBool = function() error("asked") end}

				expect(API.ClassOf(never)).to.equal("zb_x")
			end
		},
		{
			-- fails when the registry still reads the wrapper's class: the hunter would lose the stock entry (the big icon, the heavy machine)
			name = "a ZBase hunter is the hunter of the registry (heavy machine), through the real class",
			func = function()
				local entry = API.GetTracked(zbaseNpc("zb_hunter", "npc_hunter"))

				expect(entry).toNot.beNil()
				expect(entry.heavy).to.beTrue()
			end
		},
		{
			-- fails when the dull copy is not an entry, or its rules are not "never listed, never scanned, neutral"
			name = "the dull copy that ZBase leaves of a replaced NPC is never a contact: no radar, no scan, neutral",
			func = function()
				local ghost = zbaseNpc("npc_combine_s", "npc_combine_s", {ZBaseNPCCopy_DullState = true})
				local entry = API.GetTracked(ghost)

				expect(entry).toNot.beNil()
				expect(entry.key).to.equal("compat.zbase.dull")
				expect(entry.radar).to.equal("never")
				expect(entry.scan).to.equal(false)
				expect(entry.relation).to.equal("neutral")
			end
		},
		{
			-- fails when a living ZBase NPC is taken for a dull copy, or when the check runs without ZBase (a field read on every NPC of the map)
			name = "a living ZBase NPC is not the dull copy, and without ZBase the entry never matches",
			func = function()
				local living = zbaseNpc("zb_human_rebel", "npc_citizen")
				local entry = API.GetTracked(living)

				expect(entry == nil or entry.key ~= "compat.zbase.dull").to.beTrue()

				_G.ZBaseInstalled = nil

				local ghost = {IsValid = function() return true end, GetClass = function() return "npc_combine_s" end, GetNWBool = function() error("asked") end}
				local other = API.GetTracked(ghost)

				expect(other == nil or other.key ~= "compat.zbase.dull").to.beTrue()
			end
		},
		{
			-- fails when the rocket and the mortar of the ZBase NPCs are no dangers, or are armed while they lie still
			name = "the rocket and the mortar of the ZBase NPCs are dangers while they move",
			func = function()
				for class, label in pairs({zb_rocket = "ROCKET", zb_mortar = "MORTAR"}) do
					local entry = API.GetDanger(class)

					expect(entry).toNot.beNil()
					expect(entry.danger.label).to.equal(label)

					local function projectile(speed)
						return {GetVelocity = function() return Vector(speed, 0, 0) end}
					end

					expect(entry.danger.armed(projectile(0))).to.beFalse()
					expect(entry.danger.armed(projectile(400))).to.beTrue()
				end
			end
		}
	}
}
