-- Tests of the grenade warning for the danger entries that SHARED-DANGER-1 added (lua/grymod/client/cl_hud_grenade_flash.lua, GryMod.API.RegisterTracked `danger`), GLuaTest
-- format, client realm: a projectile found by a base or a match function is followed and warned about with its own entry, and `danger.warnFor(ent, ply)` lets only a projectile
-- that aims at THIS player warn. Each case names the production change whose absence makes it fail.

local saved, fakes = {}, {}
local KEYS = {"t_cd_a", "t_cd_b"}

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

local function fakeEntity(class, fields)
	local ent = {class = class, valid = true}

	function ent:IsValid() return self.valid end
	function ent:GetClass() return self.class end
	function ent:GetOwner() return NULL end
	function ent:GetNW2Entity() return NULL end
	function ent:GetNW2Bool() return true end -- armed
	function ent:GetPos() return Vector(100, 0, 0) end
	function ent:WorldSpaceCenter() return Vector(100, 0, 0) end

	for key, value in pairs(fields or {}) do
		ent[key] = value
	end

	fakes[#fakes + 1] = ent

	return ent
end

local function fakePlayer()
	return {EyePos = function() return Vector(0, 0, 0) end, IsValid = function() return true end}
end

local function created(ent)
	hook.GetTable()["OnEntityCreated"]["GRYGRENADEFOLLOW"](ent)
end

local function mine(list)
	local out = {}

	for _, candidate in ipairs(list) do
		for _, fake in ipairs(fakes) do
			if candidate.ent == fake then out[#out + 1] = candidate end
		end
	end

	return out
end

return {
	groupName = "GryMod grenade warning: danger by base, match and warnFor (client)",
	afterEach = function()
		pcall(restore)

		for _, ent in ipairs(fakes) do
			ent.valid = false
			pcall(GryMod.FlashGrenade.Forget, ent)
		end

		pcall(GryMod.FlashGrenade.Settle)
		fakes = {}

		for _, key in ipairs(KEYS) do
			pcall(GryMod.API.UnregisterTracked, key)
			pcall(GryMod.API.SafeCallReset, "tracked:" .. key .. "/warnfor")
		end
	end,
	cases = {
		{
			-- fails when the client follows by class only (a projectile of a base or found by a function is never a candidate)
			name = "a projectile found by a match function is followed from OnEntityCreated and is a candidate that carries its own entry",
			func = function()
				local G, API = GryMod.FlashGrenade, GryMod.API
				local ply = fakePlayer()

				stub(ents, "FindByClass", function() return {} end)
				G.Candidates(ply, {})

				expect(API.RegisterTracked("t_cd_a", {match = function(e) return e.isMissile == true end, danger = {label = "MISSILE"}})).to.beTrue()

				local ent = fakeEntity("t_cd_missile_7", {isMissile = true})
				local plain = fakeEntity("t_cd_prop")

				created(ent)
				created(plain)

				local list = mine(G.Candidates(ply, {}))

				expect(#list).to.equal(1)
				expect(list[1].ent).to.equal(ent)
				expect(list[1].entry.key).to.equal("t_cd_a")
				expect(G.TypeFor(list[1].class, list[1].entry)).to.equal("MISSILE")
				expect(G.Warns(list[1], true, {})).to.beTrue()
			end
		},
		{
			-- fails when the range of an entry found by a match function is read by class (it is not found by it): the warning would never or always apply
			name = "Warns reads the entry the candidate carries: its own range shortens the warning of a projectile that has no class entry",
			func = function()
				local G, API = GryMod.FlashGrenade, GryMod.API
				local ply = fakePlayer()

				stub(ents, "FindByClass", function() return {} end)
				G.Candidates(ply, {})
				API.RegisterTracked("t_cd_a", {match = function(e) return e.isMissile == true end, danger = {label = "MISSILE", range = 5}})

				local ent = fakeEntity("t_cd_missile_7", {isMissile = true})

				created(ent)

				local list = mine(G.Candidates(ply, {}))

				expect(#list).to.equal(1)
				list[1].metres = 4
				expect(G.Warns(list[1], true, {})).to.beTrue()
				list[1].metres = 9
				expect(G.Warns(list[1], true, {})).to.beFalse()
			end
		},
		{
			-- fails when a projectile whose match answers only after its creation (fields set after the hook) is never followed
			name = "a projectile the registry cannot place at its creation is judged again one frame on (one timer for the frame), only while an entry needs the entity",
			func = function()
				local G, API = GryMod.FlashGrenade, GryMod.API
				local ply = fakePlayer()
				local timers = {}

				stub(ents, "FindByClass", function() return {} end)
				G.Candidates(ply, {})
				G.Settle() -- (what the cases before waited for is judged, and no timer is left to wait for)
				stub(timer, "Simple", function(delay, fn) timers[#timers + 1] = {delay = delay, fn = fn} end)
				API.RegisterTracked("t_cd_a", {match = function(e) return e.isMissile == true end, danger = {label = "MISSILE"}})

				local ent = fakeEntity("t_cd_late")

				created(ent)
				expect(#mine(G.Candidates(ply, {}))).to.equal(0)
				expect(#timers).to.equal(1)

				ent.isMissile = true
				timers[1].fn()
				expect(#mine(G.Candidates(ply, {}))).to.equal(1)
			end
		},
		{
			-- fails when warnFor is not asked (every projectile warns), or is asked with other arguments, or its false does not silence the warning
			name = "danger.warnFor(ent, ply): false takes the projectile out of the candidates, true or no function keeps it, a function that errors keeps it (the default is to warn)",
			func = function()
				local G, API = GryMod.FlashGrenade, GryMod.API
				local ply = fakePlayer()
				local answer, seenEnt, seenPly = false

				stub(ents, "FindByClass", function() return {} end)
				G.Candidates(ply, {})
				API.RegisterTracked("t_cd_a", {class = "t_cd_aimed", danger = {label = "AIMED", warnFor = function(e, p) seenEnt, seenPly = e, p return answer end}})
				API.RegisterTracked("t_cd_b", {class = "t_cd_free", danger = {label = "FREE"}})

				local aimed, free = fakeEntity("t_cd_aimed"), fakeEntity("t_cd_free")

				created(aimed)
				created(free)

				local list = mine(G.Candidates(ply, {}))

				expect(#list).to.equal(1)
				expect(list[1].ent).to.equal(free)
				expect(seenEnt).to.equal(aimed)
				expect(seenPly).to.equal(ply)

				answer = true
				expect(#mine(G.Candidates(ply, {}))).to.equal(2)

				API.RegisterTracked("t_cd_a", {class = "t_cd_aimed", danger = {label = "AIMED", warnFor = function() error("broken warnFor") end}})
				expect(#mine(G.Candidates(ply, {}))).to.equal(2)
			end
		}
	}
}
