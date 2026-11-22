-- The player list, made once a tick for every hook that walks it.
-- The suit's Think hooks (speed drain, cloak drain, run speed, health, energy net) each called player.GetAll or player.GetHumans: the engine builds a new
-- table at every call, five of them 66 times a second (the BadCoderz report). They now ask here: the first caller of a tick pays, the others get the same
-- table. The lists are read only: a hook that wants to change one copies it.
GryMod.Players = GryMod.Players or {}

local Players = GryMod.Players
local tickOf, all, humans

-- Forgets the lists: the next call asks the engine again (a player came or left, tests).
function Players.Invalidate()
	tickOf, all, humans = nil, nil, nil
end

-- Every player, as player.GetAll gives them.
function Players.All()
	local tick = engine.TickCount()

	if tick ~= tickOf or not all then
		tickOf, all, humans = tick, player.GetAll(), nil
	end

	return all
end

-- The players that are not bots (what player.GetHumans gives), taken from the same list.
function Players.Humans()
	local list = Players.All()

	if not humans then
		humans = {}

		for i = 1, #list do
			local ply = list[i]

			if not ply:IsBot() then
				humans[#humans + 1] = ply
			end
		end
	end

	return humans
end

-- A player who comes or goes changes the list inside the tick: the next call asks again.
hook.Add("PlayerInitialSpawn", "GryModPlayersList", Players.Invalidate)
hook.Add("PlayerDisconnected", "GryModPlayersList", Players.Invalidate)
