-- Tests of the class of an entity as the use prompt sees it (GryMod.UsableClass, lua/grymod/client/cl_usable_class.lua), GLuaTest format, client realm.
-- ent:GetClass() on the client gives the name of the network class ("class C_BaseToggle") for a func_button or a momentary_rot_button, never "func_button"
-- (read in game on d1_eli_01: the entities 56, 76, 78, 80, 82 are buttons and 314 to 316 wheels, all "class C_BaseToggle"): without the real class the
-- registry could never find a button. The client asks the server, once for an entity, again after a while, never faster than the server answers.

local UC = GryMod.UsableClass
local API = GryMod.API

local savedAsk

local function fake(index, class)
	return {IsValid = function() return true end, EntIndex = function() return index end, GetClass = function() return class end}
end

return {
	groupName = "GryMod use prompt: the class of an entity (client)",
	beforeEach = function()
		savedAsk = UC and UC.Ask
	end,
	afterEach = function()
		if UC then
			UC.Ask = savedAsk
			UC.Forget()
		end
	end,
	cases = {
		{
			-- fails without the module
			name = "the client module and the resolver the registry uses exist",
			func = function()
				expect(UC ~= nil).to.beTrue()
				expect(API.UsableClassResolver == UC.Resolve).to.beTrue()
				expect(util.NetworkStringToID("gry_class_ask") ~= 0).to.beTrue()
			end
		},
		{
			-- fails if a class the game really names were asked about, or if the resolver changed it
			name = "an entity the game names itself (func_door, a prop, a weapon) is never asked about, and keeps its class",
			func = function()
				local asked = 0

				UC.Ask = function() asked = asked + 1 end

				for _, class in ipairs({"func_door", "prop_physics", "weapon_pistol", "func_useableladder", "item_healthcharger"}) do
					expect(API.UsableClassOf(fake(900, class))).to.equal(class)
				end

				expect(asked).to.equal(0)
			end
		},
		{
			-- fails without the question: the class stays the network name and no button is ever found
			name = "a network class name (class C_BaseToggle) is asked about ONCE: the answer gives the real class, which the registry then uses; until it comes the class stays generic",
			func = function()
				local asked = {}
				local button = fake(76, "class C_BaseToggle")
				-- the real clock: the registry's own call of the resolver (API.GetUsable below) reads it
				local t0 = RealTime()

				UC.Ask = function(index) asked[#asked + 1] = index end
				UC.Forget()

				expect(UC.Resolve(button, "class C_BaseToggle", t0)).to.beNil()
				expect(UC.Resolve(button, "class C_BaseToggle", t0 + 0.01)).to.beNil()
				expect(#asked).to.equal(1)
				expect(asked[1]).to.equal(76)

				UC.OnAnswer(76, "func_button", t0 + 0.02)
				expect(UC.Resolve(button, "class C_BaseToggle", t0 + 0.03)).to.equal("func_button")
				expect(API.UsableClassOf(button)).to.equal("func_button")
				expect(#asked).to.equal(1)

				-- the registry finds the button with it: use key and flags
				button.GetSpawnFlags = function() return 1025 end
				expect(API.GetUsable(button)).to.exist()
				expect(API.GetUsable(button).key).to.equal("hl2_buttons")
				button.GetSpawnFlags = function() return 513 end
				expect(API.GetUsable(button)).to.beNil() -- touch or damage only
			end
		},
		{
			-- fails if the answer were trusted for ever (an index is reused by another entity) or asked again at once
			name = "an answer is trusted for 20 seconds and asked again after (the old one counts meanwhile); another entity at the same index is asked about when the answer is old",
			func = function()
				local asked = {}

				UC.Ask = function(index) asked[#asked + 1] = index end
				UC.Forget()

				UC.OnAnswer(80, "momentary_rot_button", 100)
				expect(UC.Resolve(fake(80, "class C_BaseToggle"), "class C_BaseToggle", 110)).to.equal("momentary_rot_button")
				expect(#asked).to.equal(0)
				expect(UC.Resolve(fake(80, "class C_BaseToggle"), "class C_BaseToggle", 121)).to.equal("momentary_rot_button")
				expect(#asked).to.equal(1)
			end
		},
		{
			-- fails without the spacing of the questions
			name = "the questions are at least a fifth of a second apart, whatever generic entity the player sweeps over; the one that waits is asked next time",
			func = function()
				local asked = {}

				UC.Ask = function(index) asked[#asked + 1] = index end
				UC.Forget()

				for i = 1, 5 do
					UC.Resolve(fake(300 + i, "class C_BaseEntity"), "class C_BaseEntity", 50 + i * 0.01)
				end

				expect(#asked).to.equal(1)
				UC.Resolve(fake(302, "class C_BaseEntity"), "class C_BaseEntity", 50.3)
				expect(#asked).to.equal(2)
				expect(asked[2]).to.equal(302)
			end
		},
		{
			-- fails if the resolver were hooked to every entity or ran on a bad value
			name = "a resolver that gets nothing usable (a stand-in without EntIndex) answers nil, no error",
			func = function()
				UC.Ask = function() error("must not ask") end

				expect(UC.Resolve({}, "class C_BaseToggle", 1)).to.beNil()
				expect(UC.Resolve(nil, "class C_BaseToggle", 1)).to.beNil()
				expect(API.UsableClassOf({IsValid = function() return true end, GetClass = function() return "class C_X" end})).to.equal("class C_X")
			end
		}
	}
}
