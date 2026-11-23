-- Tests of the objectives demo (GryMod.ObjectivesDemo, lua/grymod/server/sv_objectives_demo.lua), GLuaTest format, server realm: one command, gry_objectives_demo,
-- puts three sample objectives on (a primary one 50 m in front of the player, a secondary one 200 m in front, one that follows the nearest NPC and is finished when
-- the NPC goes) and takes them away when it is run again; administrators only; also a button of the effects test window. The engine is replaced where a case needs it
-- (the NPCs of the map, the administrators' rule, the objectives API for the cases that look at the calls) and put back in afterEach inside a pcall; the cases that
-- use the real API remove the three objectives they made. Each case names the production change whose absence makes it fail.

local Demo = GryMod.ObjectivesDemo
local API = GryMod.API

local saved = {}
local madeEnts = {}
local chat

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

-- a player of the tests: a table that answers what the demo asks
local function fakePly(pos, yaw)
	return {
		IsValid = function() return true end,
		IsPlayer = function() return true end,
		GetPos = function() return pos or Vector(0, 0, 0) end,
		EyeAngles = function() return Angle(0, yaw or 0, 0) end,
		ChatPrint = function(_, text) chat[#chat + 1] = text end
	}
end

local function point(pos)
	local e = ents.Create("info_target")

	e:SetPos(pos or Vector(0, 0, 0))
	e:Spawn()
	madeEnts[#madeEnts + 1] = e

	return e
end

local function removeDemo()
	for _, id in pairs(Demo.IDS) do
		if API.GetObjective(id) then
			API.RemoveObjective(id)
		end
	end
end

return {
	groupName = "GryMod objectives demo",
	beforeEach = function()
		chat = {}
		madeEnts = {}
		removeDemo()
	end,
	afterEach = function()
		pcall(removeDemo)
		pcall(restore)

		pcall(function()
			for _, e in ipairs(madeEnts) do
				if IsValid(e) then
					e:Remove()
				end
			end
		end)
	end,
	cases = {
		{
			-- fails without Demo.PointAhead
			name = "PointAhead: the distance in metres along the way the player faces, a little above the ground",
			func = function()
				local ahead = Demo.PointAhead(Vector(0, 0, 0), 90, 50)
				expect(ahead.x).to.aboutEqual(0, 0.01)
				expect(ahead.y).to.aboutEqual(50 / 0.01905, 0.01)
				expect(ahead.z).to.aboutEqual(48, 0.01)

				local east = Demo.PointAhead(Vector(100, 100, 0), 0, 200)
				expect(east.x).to.aboutEqual(100 + 200 / 0.01905, 0.01)
				expect(east.y).to.aboutEqual(100, 0.01)
			end
		},
		{
			-- fails without Demo.Nearest
			name = "Nearest: the closest valid entity, nil for none",
			func = function()
				local far, near = point(Vector(1000, 0, 0)), point(Vector(100, 0, 0))

				expect(Demo.Nearest(Vector(0, 0, 0), {far, near}) == near).to.beTrue()
				expect(Demo.Nearest(Vector(0, 0, 0), {})).to.beNil()
			end
		},
		{
			-- fails without Demo.Toggle / Demo.Start: the three objectives of the brief, with their kinds and places
			name = "Toggle on: a primary objective 50 m ahead, a secondary 200 m ahead, one that follows the nearest NPC and completes when it goes",
			func = function()
				local npc = point(Vector(300, 0, 0))
				local other = point(Vector(5000, 0, 0))
				local calls = {}

				stub(Demo, "FindNPCs", function() return {other, npc} end)
				stub(API, "RegisterObjective", function(id, def)
					calls[id] = def

					return true
				end)
				stub(API, "SetMainObjective", function() return true end)
				stub(API, "GetObjective", function() return nil end)

				expect(Demo.Toggle(fakePly(Vector(0, 0, 0), 90))).to.equal("started")

				local primary, secondary, follow = calls[Demo.IDS.primary], calls[Demo.IDS.secondary], calls[Demo.IDS.follow]
				expect(primary.primary).to.beTrue()
				expect(primary.pos.y).to.aboutEqual(50 / 0.01905, 0.01)
				expect(secondary.primary).to.beFalse()
				expect(secondary.pos.y).to.aboutEqual(200 / 0.01905, 0.01)
				expect(follow.ent == npc).to.beTrue()
				expect(follow.onRemove).to.equal("complete")
				expect(follow.pos).to.beNil()
			end
		},
		{
			-- fails without the second half of Demo.Toggle: the same command takes the objectives away
			name = "Toggle again: the three objectives are removed, 'stopped'",
			func = function()
				local present = {}
				local removed = {}

				stub(Demo, "FindNPCs", function() return {point(Vector(300, 0, 0))} end)
				stub(API, "RegisterObjective", function(id) present[id] = true return true end)
				stub(API, "SetMainObjective", function() return true end)
				stub(API, "GetObjective", function(id) return present[id] and {id = id} or nil end)
				stub(API, "RemoveObjective", function(id)
					removed[#removed + 1] = id
					present[id] = nil

					return true
				end)

				local ply = fakePly()
				expect(Demo.Toggle(ply)).to.equal("started")
				expect(Demo.Active()).to.beTrue()
				expect(Demo.Toggle(ply)).to.equal("stopped")
				expect(#removed).to.equal(3)
				expect(Demo.Active()).to.beFalse()
			end
		},
		{
			-- fails without the NPC test in Demo.Start: with no NPC the two fixed objectives still come and the player is told how to get the third
			name = "no NPC on the map: two objectives, and a message in the chat",
			func = function()
				local calls = {}

				stub(Demo, "FindNPCs", function() return {} end)
				stub(API, "RegisterObjective", function(id) calls[#calls + 1] = id return true end)
				stub(API, "SetMainObjective", function() return true end)
				stub(API, "GetObjective", function() return nil end)

				expect(Demo.Toggle(fakePly())).to.equal("started")
				expect(#calls).to.equal(2)
				expect(string.find(chat[1], "no NPC", 1, true) ~= nil).to.beTrue()
			end
		},
		{
			-- fails without the check of the administrators' rule in Demo.Command: a player who may not configure the addon must not be able to run it
			name = "Command: refused for a player who may not configure, and for the console; allowed for an administrator",
			func = function()
				local registered = 0

				stub(API, "RegisterObjective", function() registered = registered + 1 return true end)
				stub(API, "SetMainObjective", function() return true end)
				stub(API, "GetObjective", function() return nil end)
				stub(Demo, "FindNPCs", function() return {} end)

				stub(GryMod, "MayConfigure", function() return false end)
				local _, reason = Demo.Command(fakePly())
				expect(reason).to.equal("denied")
				expect(registered).to.equal(0)

				local _, consoleReason = Demo.Command(NULL)
				expect(consoleReason).to.equal("no player")

				stub(GryMod, "MayConfigure", function() return true end)
				expect(Demo.Command(fakePly())).to.equal("started")
				expect(registered > 0).to.beTrue()
			end
		},
		{
			-- fails without the concommand and its registration in the debug registry
			name = "the command exists, and the effects test window has a button for it (the registry of its real commands)",
			func = function()
				expect(concommand.GetTable()["gry_objectives_demo"]).to.exist()

				local listed = false

				for _, entry in ipairs(GryMod.DebugCmd.List()) do
					if entry.id == "objectives_demo" then
						listed = true
					end
				end

				expect(listed).to.beTrue()
			end
		},
		{
			-- fails if a definition of the demo does not pass the real check of the objectives (a title too long, a wrong field): the real API, the real server state
			name = "through the real objectives API: the three objectives exist with the right flags, and the followed NPC finishes the objective when it is removed",
			func = function()
				local npc = point(Vector(300, 0, 0))

				stub(Demo, "FindNPCs", function() return {npc} end)

				local ok = pcall(function()
					expect(Demo.Toggle(fakePly(Vector(0, 0, 0), 0))).to.equal("started")
				end)
				expect(ok).to.beTrue()

				local primary = API.GetObjective(Demo.IDS.primary)
				local secondary = API.GetObjective(Demo.IDS.secondary)
				local follow = API.GetObjective(Demo.IDS.follow)

				expect(primary).to.exist()
				expect(primary.primary).to.beTrue()
				expect(primary.main).to.beTrue()
				expect(secondary.primary).to.beFalse()
				expect(follow.ent == npc).to.beTrue()
				expect(follow.state).to.equal("active")

				-- the engine tells the objectives about a removal with the EntityRemoved hook: run it here for the NPC, then remove it (the objectives do not ask the engine)
				hook.Run("EntityRemoved", npc)
				npc:Remove()
				expect(API.GetObjective(Demo.IDS.follow).state).to.equal("done")
			end
		}
	}
}
