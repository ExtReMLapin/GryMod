-- The drowning rule of the original game (docs/superpowers/plans/2026-11-21-underwater-notes.md). There is no oxygen
-- gauge: the player holds the breath for 60 s, then the suit energy pays for 30 s (the whole bar), then every second
-- a tenth of the maximum health is lost, with a gasp. Coming up resets it all. The engine's own drowning (12 s of air,
-- then damage that grows) is held off while the rule is on: its air time is kept in the future for as long as the head
-- is under. gry_drown_rules (replicated, saved) turns the rule off and gives the engine back its own.
--
-- Nothing runs on dry land but a check of the water level of each player every quarter of a second.

GryMod = GryMod or {}

util.AddNetworkString("gry_drown_tick")

local Drown = {}
GryMod.Drown = Drown

local RulesConVar = CreateConVar("gry_drown_rules", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"Drowning as in the original game: 60 s of held breath, then the suit energy for 30 s, then 10 percent of the health per second (0: the engine's)")

-- the original's constants
Drown.HoldSeconds = 60
Drown.EnergySeconds = 30
Drown.TickSeconds = 1
Drown.DamageFraction = 0.1

-- how long the engine's air is made to last past now each time it is held, and how often the players are looked at
local AIR_HOLD = 10
local POLL = 0.25

function Drown.Enabled()
	return RulesConVar:GetBool()
end

function Drown.NewState()
	return {seconds = 0, tick = 0}
end

-- One step of the rule. state: {seconds under water, seconds to the next tick}; returns the energy after the step and the
-- damage of a tick (0 when there is none). params: maxEnergy and maxHealth. The state is changed in place.
--  - head out: everything goes back to 0
--  - under for the first 60 s: nothing
--  - then the energy loses maxEnergy per EnergySeconds; the damage waits until the bar is empty
--  - bar empty: a tick at once, then one per TickSeconds, of DamageFraction of the maximum health
function Drown.Step(state, dt, submerged, energy, params)
	if not submerged then
		state.seconds = 0
		state.tick = 0

		return energy, 0
	end

	state.seconds = state.seconds + dt

	if state.seconds <= Drown.HoldSeconds then
		state.tick = 0

		return energy, 0
	end

	if energy > 0 then
		local after = energy - params.maxEnergy / Drown.EnergySeconds * dt

		if after > 0 then
			return after, 0
		end

		energy = 0
	end

	state.tick = state.tick - dt

	if state.tick > 0 then
		return 0, 0
	end

	state.tick = Drown.TickSeconds

	return 0, math.floor(params.maxHealth * Drown.DamageFraction)
end

-- Whether the state is one of drowning (the suit is empty and the ticks run).
function Drown.IsDrowning(state)
	return state.seconds > Drown.HoldSeconds and state.tick > 0
end

function Drown.Clear(ply)
	ply.gryDrown = nil

	if IsValid(ply) then
		ply:SetNWBool("GryDrowning", false)
	end
end

-- the damage of a tick: an ordinary hit, through the suit's damage handling
function Drown.Hurt(ply, amount)
	local dmg = DamageInfo()
	dmg:SetDamage(amount)
	dmg:SetDamageType(DMG_DROWN)
	dmg:SetAttacker(game.GetWorld())
	dmg:SetInflictor(game.GetWorld())
	ply:TakeDamageInfo(dmg)
end

-- the client plays a gasp
function Drown.Notify(ply)
	net.Start("gry_drown_tick")
	net.Send(ply)
end

local function update(ply, dt)
	local state = ply.gryDrown

	if not state then
		state = Drown.NewState()
		ply.gryDrown = state
	end

	-- the engine's air stays in the future: it does not drown the player on its own
	ply:SetSaveValue("m_AirFinished", CurTime() + AIR_HOLD)

	local energy = ply:GetNWFloat("GryEnergy")
	local after, damage = Drown.Step(state, dt, true, energy, {maxEnergy = 100, maxHealth = ply:GetMaxHealth()})

	if after ~= energy then
		ply:SetNWFloat("GryEnergy", after)
		-- while the suit pays the bar does not recharge (the recharge waits as after any use of the energy)
		ply.next_energy_regen = CurTime() + GryMod.Mech.EnergyRechargeDelay()
		ply.energy_on_use = after
	end

	local drowning = Drown.IsDrowning(state)

	if ply:GetNWBool("GryDrowning", false) ~= drowning then
		ply:SetNWBool("GryDrowning", drowning)
	end

	if damage > 0 then
		Drown.Notify(ply)
		Drown.Hurt(ply, damage)
	end
end

-- The check of every player (dt: the seconds since the last one). A player whose head is out only has its count cleared,
-- once.
function Drown.Poll(dt)
	if not Drown.Enabled() then
		return
	end

	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and ply:WaterLevel() >= 3 then
			update(ply, dt)
		elseif ply.gryDrown then
			Drown.Clear(ply)
		end
	end
end

timer.Create("GryDrownPoll", POLL, 0, function()
	Drown.Poll(POLL)
end)

hook.Add("PlayerDeath", "GryDrownClear", function(ply)
	Drown.Clear(ply)
end)

hook.Add("PlayerSpawn", "GryDrownClear", function(ply)
	Drown.Clear(ply)
end)
