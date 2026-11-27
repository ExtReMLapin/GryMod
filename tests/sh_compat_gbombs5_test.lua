-- Tests of the Gbombs 5 patch (lua/grymod/compat/tools/sh_gbombs5.lua), GLuaTest format, runs in the server AND in the client realm. GB5 was not installed when this was written;
-- the stand-ins have what the patch reads in its public code (github.com/SCI-Revived/gbombs-5, a copy of the Workshop code): the bombs and rockets of 163 entities share methods
-- (ENT:Arm, ENT:Explode of gb5_base_advanced.lua, gb5_base_dumb.lua, gb5_base_rocket_.lua), keep their state in server fields (`Armed`, `Exploded`, `Fired`), the owner in
-- `GBOWNER`, whether they are timed in the class field `Timed`, and ENT:Use arms them when the replicated convar gb5_easyuse is 1. The entity files set no ENT.Base, so no
-- entry can name a base. Each case names the change whose absence makes it fail.

local API
local easyWas

local function ent(class, fields)
	local e = {
		IsValid = function() return true end,
		GetClass = function() return class end,
		GetSpawnFlags = function() return 0 end,
		GetVelocity = function() return Vector(0, 0, 0) end,
		GetNW2Bool = function() return false end
	}

	for key, value in pairs(fields or {}) do
		e[key] = value
	end

	return e
end

-- a bomb: the methods of the GB5 bases
local function bomb(class, fields)
	local f = {Arm = function() end, Explode = function() end}

	for key, value in pairs(fields or {}) do
		f[key] = value
	end

	return ent(class, f)
end

local function player()
	return {IsValid = function() return true end, IsPlayer = function() return true end}
end

return {
	groupName = "GryMod compat: Gbombs 5 (shared)",
	beforeEach = function()
		API = GryMod.API
		local var = GetConVar("gb5_easyuse") or CreateConVar("gb5_easyuse", "1")

		easyWas = var:GetBool()
		-- (a replicated setting cannot be written from the client: it keeps the server's value, which is 1 here)
		pcall(function() var:SetBool(true) end)
		include("grymod/compat/tools/sh_gbombs5.lua")
	end,
	afterEach = function()
		pcall(function() GetConVar("gb5_easyuse"):SetBool(easyWas) end)
	end,
	cases = {
		{
			-- fails when a GB5 bomb is not a danger, or when something of another addon is taken for one by its name
			name = "a GB5 bomb or rocket (a gb5_ class with Arm and Explode) is a danger; a gb5_ entity that is no bomb, and another addon's, are not",
			func = function()
				expect(API.GetDanger(bomb("gb5_light_b_50lb")) ~= nil).to.beTrue()
				expect(API.GetDanger(bomb("gb5_proj_tomahawk")) ~= nil).to.beTrue()
				expect(API.GetDanger(ent("gb5_shockwave_ent"))).to.beNil()
				expect(API.GetDanger(ent("gb5_chemical_poisongas"))).to.beNil()
				expect(API.GetDanger(bomb("not_gb5_bomb"))).to.beNil()
			end
		},
		{
			-- fails when a bomb that lies armed (it waits for an impact) warns all the time, or when the fuse of a timed one does not warn
			name = "a timed bomb warns while its fuse runs, a rocket in flight warns, an impact bomb only while it falls, an exploded or unarmed one never",
			func = function()
				local entry = API.GetDanger(bomb("gb5_light_b_50lb"))
				local armed = entry.danger.armed

				expect(armed(bomb("gb5_light_b_50lb", {Armed = true, Timed = true}))).to.beTrue()
				expect(armed(bomb("gb5_proj_tomahawk", {Fired = true}))).to.beTrue()
				expect(armed(bomb("gb5_light_b_50lb", {Armed = true, Timed = false}))).to.beFalse()
				expect(armed(bomb("gb5_light_b_50lb", {Armed = true, Timed = false, GetVelocity = function() return Vector(0, 0, -600) end}))).to.beTrue()
				expect(armed(bomb("gb5_light_b_50lb", {Armed = false, Timed = true}))).to.beFalse()
				expect(armed(bomb("gb5_light_b_50lb", {Armed = true, Timed = true, Exploded = true}))).to.beFalse()
				expect(armed(bomb("gb5_light_b_50lb", {}))).to.beFalse()
			end
		},
		{
			-- fails when the owner is not read from GBOWNER (the engine's owner is not set by GB5), or when anything but a player counts
			name = "the owner of a GB5 bomb is its GBOWNER, a player only",
			func = function()
				local me = player()
				local entry = API.GetDanger(bomb("gb5_light_b_50lb"))

				expect(entry.danger.ownerOf(bomb("gb5_light_b_50lb", {GBOWNER = me}))).to.equal(me)
				expect(entry.danger.ownerOf(bomb("gb5_light_b_50lb", {GBOWNER = {IsValid = function() return true end, IsPlayer = function() return false end}}))).to.beNil()
				expect(entry.danger.ownerOf(bomb("gb5_light_b_50lb"))).to.beNil()
			end
		},
		{
			-- fails when a GB5 bomb has no prompt, when it keeps it once it is armed (GryArmed, networked by GryMod for the danger entries), or when the easy use setting is off
			name = "a bomb has the ARM prompt, taken away once it is armed, and when the easy use setting is off",
			func = function()
				local fresh = bomb("gb5_light_b_50lb")
				local entry = API.GetUsable(fresh)

				expect(entry ~= nil).to.beTrue()
				expect(entry.text).to.equal("ARM")
				expect(API.UsableBusy(fresh, nil, entry)).to.beFalse()

				local armed = bomb("gb5_light_b_50lb", {GetNW2Bool = function(_, name) return name == "GryArmed" end})

				expect(API.UsableBusy(armed, nil, API.GetUsable(armed))).to.beTrue()

				GetConVar("gb5_easyuse"):SetBool(false)

				expect(API.GetUsable(bomb("gb5_light_b_50lb"))).to.beNil()
			end
		},
		{
			-- fails when a thing that has no Use (a shockwave, a radiation entity) or another addon's entity gets the prompt
			name = "what is not a bomb has no prompt",
			func = function()
				expect(API.GetUsable(ent("gb5_shockwave_ent"))).to.beNil()
				expect(API.GetUsable(ent("info_target"))).to.beNil() -- (not prop_physics: the stock entry of the game gives the props a prompt)
			end
		}
	}
}
