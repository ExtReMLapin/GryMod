-- Tests of the class and creature providers of the extension API (GryMod.API.ClassOf, AddClassProvider, IsCreature, AddCreatureProvider; lua/grymod/sh_api_class.lua),
-- GLuaTest format, runs in the server AND in the client realm. Each case names the production change whose absence makes it fail.

local API
local KEYS = {"t_cls_a", "t_cls_b"}

local function ent(class, fields)
	local e = {
		IsValid = function() return true end,
		GetClass = function() return class end
	}

	for key, value in pairs(fields or {}) do
		e[key] = value
	end

	return e
end

local function cleanUp()
	for _, key in ipairs(KEYS) do
		API.RemoveClassProvider(key)
		API.RemoveCreatureProvider(key)
		API.SafeCallReset("class:" .. key)
		API.SafeCallReset("creature:" .. key)
	end
end

return {
	groupName = "GryMod extension API: class and creature providers (shared)",
	beforeEach = function()
		API = GryMod.API
		cleanUp()
	end,
	afterEach = function()
		cleanUp()
	end,
	cases = {
		{
			-- fails when the functions do not exist, the features are not announced, or a bad key or function is accepted
			name = "the class and creature providers check their arguments and announce their features",
			func = function()
				expect(API.Has("class")).to.beTrue()
				expect(API.Has("creature")).to.beTrue()
				expect((API.AddClassProvider("", function() end))).to.beFalse()
				expect((API.AddClassProvider("t_cls_a", "nope"))).to.beFalse()
				expect((API.AddCreatureProvider(3, function() end))).to.beFalse()
				expect((API.AddCreatureProvider("t_cls_a", nil))).to.beFalse()
				expect(API.AddClassProvider("t_cls_a", function() end)).to.beTrue()
				expect(API.AddCreatureProvider("t_cls_a", function() end)).to.beTrue()
				expect(API.RemoveClassProvider("t_cls_a")).to.beTrue()
				expect(API.RemoveClassProvider("t_cls_a")).to.beFalse()
				expect(API.RemoveCreatureProvider("t_cls_a")).to.beTrue()
				expect(API.RemoveCreatureProvider("t_cls_a")).to.beFalse()
			end
		},
		{
			-- fails when ClassOf is no longer Entity:GetClass without a provider, or crashes on something that is not an entity
			name = "ClassOf without a provider is the entity's own class; nil for what is not a valid entity",
			func = function()
				expect(API.ClassOf(ent("npc_zombie"))).to.equal("npc_zombie")
				expect(API.ClassOf(nil)).to.beNil()
				expect(API.ClassOf(5)).to.beNil()
				expect(API.ClassOf(ent("x", {IsValid = function() return false end}))).to.beNil()
			end
		},
		{
			-- fails when a provider's class is not the one returned (ZBase: the wrapper hides the real class), when the first provider that answers does not win, or when a provider
			-- that errors, answers nil, an empty string or a number stops the search
			name = "ClassOf: the first provider that answers a class wins; errors, nil, empty text and numbers are skipped",
			func = function()
				local npc = ent("wrapper_class")

				API.AddClassProvider("t_cls_a", function() error("provider failure") end)
				expect(API.ClassOf(npc)).to.equal("wrapper_class")

				API.AddClassProvider("t_cls_a", function() return "" end)
				expect(API.ClassOf(npc)).to.equal("wrapper_class")

				API.AddClassProvider("t_cls_a", function() return 7 end)
				expect(API.ClassOf(npc)).to.equal("wrapper_class")

				API.AddClassProvider("t_cls_a", function() return nil end)
				API.AddClassProvider("t_cls_b", function() return "real_class" end)
				expect(API.ClassOf(npc)).to.equal("real_class")

				API.RemoveClassProvider("t_cls_b")
				expect(API.ClassOf(npc)).to.equal("wrapper_class")
			end
		},
		{
			-- fails when IsCreature is no longer true for an NPC, or is true for something that is not one with no provider
			name = "IsCreature: an NPC is one; without a provider a plain entity, a missing entity or a number is not",
			func = function()
				expect(API.IsCreature(ent("npc_zombie", {IsNPC = function() return true end}))).to.beTrue()
				expect(API.IsCreature(ent("prop_physics", {IsNPC = function() return false end}))).to.beFalse()
				expect(API.IsCreature(ent("prop_physics"))).to.beFalse()
				expect(API.IsCreature(nil)).to.beFalse()
				expect(API.IsCreature(5)).to.beFalse()
			end
		},
		{
			-- fails when a provider's "yes" is not honoured (a DrGBase nextbot), when only a real true counts as yes (a truthy value would make everything a creature), or when a
			-- provider that errors breaks the question
			name = "IsCreature: a provider that says true makes it a creature; false, nil, junk and errors do not",
			func = function()
				local bot = ent("drgbase_nextbot", {IsNPC = function() return false end})

				API.AddCreatureProvider("t_cls_a", function() error("provider failure") end)
				expect(API.IsCreature(bot)).to.beFalse()

				API.AddCreatureProvider("t_cls_a", function() return "yes" end)
				expect(API.IsCreature(bot)).to.beFalse()

				API.AddCreatureProvider("t_cls_a", function() return false end)
				API.AddCreatureProvider("t_cls_b", function(e) return e == bot end)
				expect(API.IsCreature(bot)).to.beTrue()
				expect(API.IsCreature(ent("prop_physics"))).to.beFalse()
			end
		},
		{
			-- fails when a provider that keeps raising errors is never switched off, or adding it again does not arm it again
			name = "a class provider that fails five times in a row is switched off; adding it again arms it again",
			func = function()
				local calls = 0
				local npc = ent("wrapper_class")

				API.AddClassProvider("t_cls_a", function() calls = calls + 1 error("provider failure") end)

				for _ = 1, API.SafeCallLimit + 3 do
					API.ClassOf(npc)
				end

				expect(calls).to.equal(API.SafeCallLimit)
				expect(API.SafeCallDisabled("class:t_cls_a")).to.beTrue()
				API.AddClassProvider("t_cls_a", function() return "back" end)
				expect(API.ClassOf(npc)).to.equal("back")
			end
		}
	}
}
