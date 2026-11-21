-- Tests of the drowning rule (GryMod.Drown, sv_underwater.lua), GLuaTest format, server realm: the breath held for 60 s,
-- the suit paying for 30 s, then a tenth of the health every second (the original game's rule, in
-- docs/superpowers/plans/2026-11-21-underwater-notes.md), the hold on the engine's own drowning and the switch.
-- The pure step is tested with numbers; the driver with a player whose water level, damage and network calls are
-- replaced by recorders (and put back after each case).

local function ply()
	return player.GetAll()[1]
end

local saved = {}
local savedConVars = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function setConVar(name, value)
	local convar = GetConVar(name)
	savedConVars[name] = savedConVars[name] or convar:GetString()
	convar:SetString(value)
end

local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 0.001)
end

-- runs the step for `seconds` at `dt`; returns the energy, the list of damage ticks (time, amount) and the state
local function simulate(seconds, dt, energy, maxHealth, state)
	local Drown = GryMod.Drown
	state = state or Drown.NewState()
	local ticks = {}
	local now = 0

	while now < seconds - 1e-9 do
		now = now + dt
		local damage
		energy, damage = Drown.Step(state, dt, true, energy, {maxEnergy = 100, maxHealth = maxHealth or 100})

		if damage > 0 then ticks[#ticks + 1] = {now, damage} end
	end

	return energy, ticks, state
end

return {
	groupName = "GryMod drowning rule",
	beforeEach = function(state)
		saved = {}
		setConVar("gry_drown_rules", "1")
	end,
	afterEach = function(state)
		for i = #saved, 1, -1 do
			local entry = saved[i]
			entry[1][entry[2]] = entry[3]
		end

		for name, value in pairs(savedConVars) do
			GetConVar(name):SetString(value)
		end

		savedConVars = {}
		for _, p in ipairs(player.GetAll()) do
			GryMod.Drown.Clear(p)
			p:SetNWFloat("GryEnergy", 100)
			p:SetHealth(p:GetMaxHealth())
		end
	end,
	cases = {
		{
			name = "gry_drown_rules exists: replicated, saved, 1 by default",
			func = function(state)
				local convar = GetConVar("gry_drown_rules")
				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("1")
				expect(bit.band(convar:GetFlags(), FCVAR_REPLICATED) ~= 0).to.beTrue()
				-- the flags of the other server settings (saved, replicated, notified)
				expect(convar:GetFlags()).to.equal(GetConVar("gry_malfunction"):GetFlags())
			end
		},
		{
			name = "the numbers are the original's: 60 s of held breath, the bar empties in 30 s, a tick every second, a tenth of the health",
			func = function(state)
				expect(GryMod.Drown.HoldSeconds).to.equal(60)
				expect(GryMod.Drown.EnergySeconds).to.equal(30)
				expect(GryMod.Drown.TickSeconds).to.equal(1)
				expect(GryMod.Drown.DamageFraction).to.equal(0.1)
			end
		},
		{
			name = "the first minute under water costs nothing",
			func = function(state)
				local energy, ticks = simulate(59.9, 0.1, 100)
				expect(energy).to.equal(100)
				expect(#ticks).to.equal(0)
			end
		},
		{
			name = "after the minute the energy goes down by a thirtieth of the bar per second",
			func = function(state)
				local energy = simulate(70, 0.1, 100)
				expect(near(energy, 100 - 10 * 100 / 30, 0.5)).to.beTrue()
			end
		},
		{
			name = "no damage while the energy lasts: the bar is empty 30 s after the minute, and the first tick comes with it",
			func = function(state)
				local energy, ticks = simulate(89.5, 0.1, 100)
				expect(energy > 0).to.beTrue()
				expect(#ticks).to.equal(0)

				energy, ticks = simulate(91, 0.1, 100)
				expect(energy).to.equal(0)
				expect(#ticks > 0).to.beTrue()
				expect(near(ticks[1][1], 90, 0.2)).to.beTrue()
			end
		},
		{
			name = "drowning: 10 damage on 100 health every second",
			func = function(state)
				local _, ticks = simulate(100, 0.1, 100)
				-- from 90 s to 100 s: 10 or 11 ticks of 10
				expect(#ticks >= 10 and #ticks <= 11).to.beTrue()

				for _, tick in ipairs(ticks) do
					expect(tick[2]).to.equal(10)
				end

				expect(near(ticks[2][1] - ticks[1][1], 1, 0.15)).to.beTrue()
			end
		},
		{
			name = "the damage follows the maximum health (a tenth of it)",
			func = function(state)
				local _, ticks = simulate(95, 0.1, 100, 250)
				expect(ticks[1][2]).to.equal(25)
			end
		},
		{
			name = "an empty bar from the start of the minute drowns at once after it",
			func = function(state)
				local _, ticks = simulate(61, 0.1, 0)
				expect(#ticks > 0).to.beTrue()
				expect(near(ticks[1][1], 60, 0.2)).to.beTrue()
			end
		},
		{
			name = "surfacing resets the count: a minute after coming up the clock starts again",
			func = function(state)
				local Drown = GryMod.Drown
				local _, _, s = simulate(80, 0.1, 100)
				expect(s.seconds > 79).to.beTrue()

				Drown.Step(s, 0.1, false, 50, {maxEnergy = 100, maxHealth = 100})
				expect(s.seconds).to.equal(0)
				expect(s.tick).to.equal(0)

				local energy, ticks = simulate(59, 0.1, 50, 100, s)
				expect(energy).to.equal(50)
				expect(#ticks).to.equal(0)
			end
		},
		{
			name = "drowning is reported as a state: false in the minute and while the energy lasts, true when the ticks run",
			func = function(state)
				local Drown = GryMod.Drown
				local _, _, s = simulate(50, 0.1, 100)
				expect(Drown.IsDrowning(s)).to.beFalse()
				_, _, s = simulate(75, 0.1, 100)
				expect(Drown.IsDrowning(s)).to.beFalse()
				_, _, s = simulate(95, 0.1, 100)
				expect(Drown.IsDrowning(s)).to.beTrue()
			end
		},
		{
			name = "the driver, rules on: while the head is under, the engine's air is kept in the future so that it never drowns",
			func = function(state)
				local p = ply()
				local air = {}
				stub(FindMetaTable("Entity"), "WaterLevel", function() return 3 end)
				stub(FindMetaTable("Entity"), "SetSaveValue", function(self, name, value)
					if self == p then air[#air + 1] = {name, value} end
				end)
				stub(GryMod.Drown, "Hurt", function() end)

				GryMod.Drown.Poll(0.25)

				expect(#air).to.equal(1)
				expect(air[1][1]).to.equal("m_AirFinished")
				expect(air[1][2] > CurTime() + 5).to.beTrue()
			end
		},
		{
			name = "the driver, rules off: the engine is left alone (no air hold, no energy cost, no damage, no tick)",
			func = function(state)
				setConVar("gry_drown_rules", "0")
				local p = ply()
				local touched = 0
				p:SetNWFloat("GryEnergy", 100)
				stub(FindMetaTable("Entity"), "WaterLevel", function() return 3 end)
				stub(FindMetaTable("Entity"), "SetSaveValue", function() touched = touched + 1 end)
				stub(GryMod.Drown, "Hurt", function() touched = touched + 1 end)
				stub(GryMod.Drown, "Notify", function() touched = touched + 1 end)

				for _ = 1, 4000 do GryMod.Drown.Poll(0.25) end

				expect(touched).to.equal(0)
				expect(p:GetNWFloat("GryEnergy")).to.equal(100)
			end
		},
		{
			name = "the driver on a long dive: the energy goes down, then each tick hurts and notifies the player, and the player is marked as drowning",
			func = function(state)
				local p = ply()
				local hurts, notes = {}, 0
				p:SetNWFloat("GryEnergy", 100)
				stub(FindMetaTable("Entity"), "WaterLevel", function() return 3 end)
				stub(FindMetaTable("Entity"), "SetSaveValue", function() end)
				-- the other players of the test server (bots) are under water too: only the first one is counted
				stub(GryMod.Drown, "Hurt", function(who, amount)
					if who == p then hurts[#hurts + 1] = {who, amount} end
				end)
				stub(GryMod.Drown, "Notify", function(who)
					if who == p then notes = notes + 1 end
				end)

				-- 65 s: the minute and five seconds of the suit paying
				for _ = 1, 260 do GryMod.Drown.Poll(0.25) end

				expect(near(p:GetNWFloat("GryEnergy"), 100 - 5 * 100 / 30, 1)).to.beTrue()
				expect(#hurts).to.equal(0)
				expect(p:GetNWBool("GryDrowning")).to.beFalse()

				-- 25 more seconds: the bar is empty, then 5 s of drowning
				for _ = 1, 120 do GryMod.Drown.Poll(0.25) end

				expect(p:GetNWFloat("GryEnergy")).to.equal(0)
				expect(#hurts >= 5 and #hurts <= 6).to.beTrue()
				expect(notes).to.equal(#hurts)
				expect(hurts[1][1]).to.equal(p)
				expect(hurts[1][2]).to.equal(math.floor(p:GetMaxHealth() * 0.1))
				expect(p:GetNWBool("GryDrowning")).to.beTrue()

				-- the head comes out: the mark and the count are cleared
				stub(FindMetaTable("Entity"), "WaterLevel", function() return 0 end)
				GryMod.Drown.Poll(0.25)
				expect(p:GetNWBool("GryDrowning")).to.beFalse()
				expect(p.gryDrown == nil or p.gryDrown.seconds == 0).to.beTrue()
			end
		},
		{
			name = "the energy does not come back while the suit pays (the recharge is held as the energy is spent)",
			func = function(state)
				local p = ply()
				p:SetNWFloat("GryEnergy", 100)
				p.next_energy_regen = 0
				stub(FindMetaTable("Entity"), "WaterLevel", function() return 3 end)
				stub(FindMetaTable("Entity"), "SetSaveValue", function() end)
				stub(GryMod.Drown, "Hurt", function() end)

				for _ = 1, 280 do GryMod.Drown.Poll(0.25) end

				expect(p.next_energy_regen > CurTime()).to.beTrue()
			end
		},
		{
			name = "the damage call: an ordinary drowning hit (DMG_DROWN, from the world) through the engine's damage",
			func = function(state)
				local p = ply()
				local hits = {}
				stub(FindMetaTable("Entity"), "TakeDamageInfo", function(self, dmg)
					hits[#hits + 1] = {self, dmg:GetDamage(), dmg:GetDamageType(), dmg:GetAttacker()}
				end)

				GryMod.Drown.Hurt(p, 10)

				expect(#hits).to.equal(1)
				expect(hits[1][1]).to.equal(p)
				expect(hits[1][2]).to.equal(10)
				expect(hits[1][3]).to.equal(DMG_DROWN)
				expect(hits[1][4]).to.equal(game.GetWorld())
			end
		},
		{
			name = "the tick message goes to the drowning player only",
			func = function(state)
				local started, sent = {}, {}
				stub(net, "Start", function(name) started[#started + 1] = name end)
				stub(net, "Send", function(who) sent[#sent + 1] = who end)

				GryMod.Drown.Notify(ply())

				expect(started[1]).to.equal("gry_drown_tick")
				expect(sent[1]).to.equal(ply())
			end
		}
	}
}
