-- Tests of the per-tick player list (GryMod.Players, server/sv_players.lua), GLuaTest format, server realm.
-- The suit's Think hooks (speed drain, cloak drain, run speed, health, energy net) each asked the engine for the player list at every tick: five
-- tables made and thrown away 66 times a second. They now share one list made once a tick (BadCoderz report: player.GetAll in GM:Think).

local THINKS = {"GrySpeedThink", "GryCloakThink", "GryMod run speed", "GryMod health think", "GryMod energy net"}

local realAll, realHumans, realTick = player.GetAll, player.GetHumans, engine.TickCount
local calls

-- Counts the engine's list calls and lets the test say which tick it is. Everything goes back in `restore`, even after an error.
local function stub(tick)
	calls = {all = 0, humans = 0}
	local current = tick

	player.GetAll = function()
		calls.all = calls.all + 1

		return realAll()
	end

	player.GetHumans = function()
		calls.humans = calls.humans + 1

		return realHumans()
	end

	engine.TickCount = function()
		return current
	end

	return function(t)
		current = t
	end
end

local function restore()
	player.GetAll, player.GetHumans, engine.TickCount = realAll, realHumans, realTick
end

local function guarded(body)
	local ok, err = pcall(body)
	restore()

	if not ok then
		error(err, 0)
	end
end

return {
	groupName = "GryMod per-tick player list (server)",
	afterEach = function()
		restore()

		if GryMod.Players then
			GryMod.Players.Invalidate()
		end
	end,
	cases = {
		{
			name = "the list is made once for every call of the same tick, and again on the next tick",
			func = function()
				expect(GryMod.Players).to.exist()

				guarded(function()
					GryMod.Players.Invalidate()
					local setTick = stub(1000)

					local first = GryMod.Players.All()
					local second = GryMod.Players.All()
					expect(calls.all).to.equal(1)
					expect(second).to.equal(first)
					expect(#first).to.equal(#realAll())

					setTick(1001)
					GryMod.Players.All()
					expect(calls.all).to.equal(2)
				end)
			end
		},
		{
			name = "the humans are the players that are not bots, taken from the same list (no second engine call)",
			func = function()
				guarded(function()
					GryMod.Players.Invalidate()
					stub(2000)

					local humans = GryMod.Players.Humans()
					GryMod.Players.Humans()
					GryMod.Players.All()
					expect(calls.all).to.equal(1)
					expect(calls.humans).to.equal(0)

					local expected = 0

					for _, p in ipairs(realAll()) do
						if not p:IsBot() then
							expected = expected + 1
						end
					end

					expect(#humans).to.equal(expected)

					for _, p in ipairs(humans) do
						expect(p:IsBot()).to.beFalse()
					end
				end)
			end
		},
		{
			name = "a player who joins or leaves makes the next call ask the engine again, in the same tick",
			func = function()
				guarded(function()
					GryMod.Players.Invalidate()
					stub(3000)
					GryMod.Players.All()
					expect(calls.all).to.equal(1)

					for _, name in ipairs({"PlayerInitialSpawn", "PlayerDisconnected"}) do
						local handler = hook.GetTable()[name]["GryModPlayersList"]
						expect(handler ~= nil).to.beTrue()

						GryMod.Players.All()
						local before = calls.all
						handler(realAll()[1])
						GryMod.Players.All()
						expect(calls.all).to.equal(before + 1)
					end
				end)
			end
		},
		{
			name = "the five suit Think hooks of a tick ask the engine for the list once between them, never five times",
			func = function()
				guarded(function()
					GryMod.Players.Invalidate()
					stub(4000)

					for _, name in ipairs(THINKS) do
						local think = hook.GetTable().Think[name]
						expect(think ~= nil).to.beTrue()
						pcall(think) -- a bot is no network recipient: the hook may stop there, the engine calls it made before are counted
					end

					expect(calls.all).to.equal(1)
					expect(calls.humans).to.equal(0)
				end)
			end
		},
	}
}
