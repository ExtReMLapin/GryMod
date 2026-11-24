-- Tests of the nextbots that report their own awareness to the radar (server/sv_radar.lua: Radar.AwarenessOf, Radar.LevelOf, Describe, Detect,
-- SendDetect, AlertLevelOf), GLuaTest format, server realm. An entity with ENT:GetGryAwareness(ply) -> level (0 calm, 1 alerted, 2 fighting),
-- exposure (0 to 1, how much it is aware of THIS player), seen, heard gives the radar its real state; every other entity keeps today's rule.
-- The highest exposure of the hostiles goes to the client with the detection message (a 6-bit field after the two numbers), so the stealth bar
-- can show the true exposure instead of the 0 / 0.5 / 1 steps. Design: spec section 6.2.

local R -- GryMod.Radar
local BOT = "gry_test_aware_bot"
local spawned = {}

local function ply()
	return player.GetAll()[1]
end

local nextId = 0

local function desc(extra)
	nextId = nextId + 1
	local d = {key = {}, id = 700 + nextId, class = "npc_combine_s", hostile = true, ally = false, state = NPC_STATE_IDLE, enemyIsPlayer = false, seen = false,
		heard = false, health = 50, maxHealth = 50, x = 0, y = 0, z = 0, yaw = 0}

	for k, v in pairs(extra or {}) do
		d[k] = v
	end

	return d
end

-- a bot whose GetGryAwareness returns what `fn` returns
local function spawnBot(fn)
	local bot = ents.Create(BOT)
	bot:SetPos(ply():GetPos() + Vector(200, 0, 0))
	bot.GetGryAwareness = fn
	bot:Spawn()
	spawned[#spawned + 1] = bot

	return bot
end

return {
	groupName = "GryMod radar: nextbots that report their awareness (server)",
	beforeAll = function()
		R = GryMod.Radar
		scripted_ents.Register({Type = "nextbot", Base = "base_nextbot", Spawnable = false, Initialize = function(self)
			self:SetModel("models/props_junk/PopCan01a.mdl")
		end, RunBehaviour = function(self)
			while true do coroutine.yield() end
		end}, BOT)
	end,
	afterEach = function(state)
		if state.realStart then
			net.Start, net.WriteUInt, net.Send = state.realStart, state.realWriteUInt, state.realSend
			state.realStart = nil
		end

		for _, e in ipairs(spawned) do
			if IsValid(e) then e:Remove() end
		end

		spawned = {}
	end,
	cases = {
		{
			name = "LevelOf takes the bot's word when there is one, today's rule otherwise",
			func = function()
				expect(R.LevelOf({awareLevel = 1, state = NPC_STATE_COMBAT, enemyIsPlayer = true})).to.equal(1)
				expect(R.LevelOf({state = NPC_STATE_COMBAT, enemyIsPlayer = true})).to.equal(2)
				expect(R.LevelOf({state = NPC_STATE_IDLE, enemyIsPlayer = false})).to.equal(0)
			end
		},
		{
			name = "Detect gives the highest exposure of the hostiles as a third number, contacts included, allies left out",
			func = function()
				local _, _, e = R.Detect({desc({awareLevel = 0, exposure = 0.4})}, {})
				expect(e).to.equal(0.4)

				local a, b = desc({awareLevel = 0, exposure = 0.4}), desc({awareLevel = 0, exposure = 0.7})
				_, _, e = R.Detect({a, b}, {[b.id] = true})
				expect(e).to.equal(0.7)

				_, _, e = R.Detect({desc({ally = true, hostile = false, exposure = 0.9})}, {})
				expect(e).to.equal(0)

				local puppet
				puppet, _, e = R.Detect({desc({awareLevel = 0, exposure = 0.4})}, {})
				expect(puppet).to.equal(0)
			end
		},
		{
			name = "Detect counts the bot's level instead of the NPC state",
			func = function()
				local puppet = R.Detect({desc({awareLevel = 2, exposure = 1})}, {})
				expect(puppet).to.equal(2)
				puppet = R.Detect({desc({awareLevel = 1, exposure = 0.5, state = NPC_STATE_COMBAT, enemyIsPlayer = true})}, {})
				expect(puppet).to.equal(1)
			end
		},
		{
			name = "Describe takes the bot's level, exposure, seen and heard",
			func = function()
				local bot = spawnBot(function() return 2, 0.8, true, false end)
				local d = R.Describe(bot, ply())

				expect(d.awareLevel).to.equal(2)
				expect(d.exposure).to.equal(0.8)
				expect(d.seen).to.beTrue()
				expect(d.heard).to.beFalse()
			end
		},
		{
			name = "Describe clamps garbage: a level of 7 is 2, an exposure of 3 is 1, a string is true",
			func = function()
				local bot = spawnBot(function() return 7, 3, "x", nil end)
				local d = R.Describe(bot, ply())

				expect(d.awareLevel).to.equal(2)
				expect(d.exposure).to.equal(1)
				expect(d.seen).to.beTrue()
				expect(d.heard).to.beFalse()
			end
		},
		{
			name = "a GetGryAwareness that throws leaves the description as today's, and Describe does not throw",
			func = function()
				local bot = spawnBot(function() error("broken bot") end)
				local d

				expect(function() d = R.Describe(bot, ply()) end).to.succeed()
				expect(d.awareLevel).to.beNil()
				expect(d.exposure).to.beNil()
			end
		},
		{
			name = "an NPC without the method has no awareness fields",
			func = function()
				local npc = ents.Create("npc_combine_s")
				npc:SetPos(ply():GetPos() + Vector(300, 0, 10))
				npc:Spawn()
				spawned[#spawned + 1] = npc
				local d = R.Describe(npc, ply())

				expect(d.awareLevel).to.beNil()
				expect(d.exposure).to.beNil()
			end
		},
		{
			name = "AlertLevelOf takes the bot's level",
			func = function()
				local bot = spawnBot(function() return 2, 1, true, false end)
				expect(R.AlertLevelOf(bot, ply())).to.equal(2)
			end
		},
		{
			name = "SendDetect writes the exposure as a 6-bit number after the two 2-bit numbers, and sends again when only the exposure moves by more than a step",
			func = function(state)
				local sent = {}
				state.realStart, state.realWriteUInt, state.realSend = net.Start, net.WriteUInt, net.Send
				net.Start = function(name) sent[#sent + 1] = {name = name, values = {}, bits = {}} return true end
				net.WriteUInt = function(v, bits) local m = sent[#sent] m.values[#m.values + 1] = v m.bits[#m.bits + 1] = bits end
				net.Send = function(p) sent[#sent].to = p end
				local p, st = {}, {}

				R.SendDetect(p, st, 0, 0, 0.5)
				expect(#sent).to.equal(1)
				expect(sent[1].values[3]).to.equal(32)
				expect(sent[1].bits[1]).to.equal(2)
				expect(sent[1].bits[3]).to.equal(6)

				R.SendDetect(p, st, 0, 0, 0.505)
				expect(#sent).to.equal(1)
				R.SendDetect(p, st, 0, 0, 0.8)
				expect(#sent).to.equal(2)
				R.SendDetect(p, st, 0, 0, 0)
				expect(#sent).to.equal(3)
				R.SendDetect(p, st, 0, 0, 0)
				expect(#sent).to.equal(3)
			end
		},
		{
			name = "the feature is announced",
			func = function()
				expect(GryMod.API.Has("awareness")).to.beTrue()
			end
		}
	}
}
