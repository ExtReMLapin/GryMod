-- Tests of the veto of the reset at a spawn (the hook GryMod_CanResetOnSpawn, sv_system.lua: GryMod.KeepStateOnSpawn), GLuaTest format, server realm. An addon that
-- brings a player back with Player:Spawn (a ragdoll that gets up, a respawn in place) answers false: the suit keeps its state. The energy is kept, the mode and the camouflage
-- are put on again in silence (the engine's Spawn erased the notarget flag, the material and the run speed), the HUD plays no start-up sequence, and the cause of the
-- silent change is "restore". Each case names the production change whose absence makes it fail.

local function ply()
	return player.GetAll()[1]
end

-- The PlayerSpawn hooks of GryMod, called one after the other the way the engine's call does (in no fixed order of the engine's: the veto must give the same answer to all).
local SPAWN_HOOKS = {"GryModSpawn", "GryMod_ENER_HLT_VARS", "GryMod API energy", "GryMod malfunction spawn", "GryMod radar", "GryDrownClear"}

-- Runs a spawn with the messages recorded; returns the names of the messages sent.
local function spawn(p, how)
	local sent = {}
	local realStart, realSend = net.Start, net.Send

	net.Start = function(name)
		sent[#sent + 1] = name

		return true
	end
	net.Send = function() end

	if GryMod.SpawnRestore and GryMod.SpawnRestore.Reset then
		GryMod.SpawnRestore.Reset(p)
	end

	local ok, err = pcall(function()
		if how == "engine" then
			p:Spawn()
		else
			local hooks = hook.GetTable().PlayerSpawn

			for _, id in ipairs(SPAWN_HOOKS) do
				assert(hooks[id], "the hook " .. id .. " is missing")
				hooks[id](p)
			end
		end
	end)

	net.Start, net.Send = realStart, realSend
	assert(ok, err)

	return sent
end

local function has(list, name)
	for _, entry in ipairs(list) do
		if entry == name then
			return true
		end
	end

	return false
end

local function veto(answer)
	hook.Add("GryMod_CanResetOnSpawn", "gry_test_restore", function()
		return answer
	end)
end

local changes

return {
	groupName = "GryMod keeps the suit at a spawn that an addon vetoes (server)",
	beforeEach = function()
		local p = ply()

		if not p:Alive() then
			p:Spawn()
		end

		hook.Remove("GryMod_CanResetOnSpawn", "gry_test_restore")
		p:SetNW2Bool("GryDisabled", false)
		p:SetNW2Float("GryEnergy", 100)
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		changes = {}
		hook.Add("GryMod_ModeChanged", "gry_test_restore", function(_, mode, old, reason)
			changes[#changes + 1] = {mode, old, reason}
		end)
	end,
	afterEach = function()
		hook.Remove("GryMod_CanResetOnSpawn", "gry_test_restore")
		hook.Remove("GryMod_ModeChanged", "gry_test_restore")

		local p = ply()

		if IsValid(p) then
			if GryMod.Malfunction then
				GryMod.Malfunction.Clear(p)
			end

			p:SetNW2Float("GryEnergy", 100)
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
			p:SetNoTarget(false)
		end
	end,
	cases = {
		{
			-- fails when "restore" is not in the list of causes (appended at the end: the ids of the others do not move), or is not a string of the table
			name = "the cause \"restore\" exists, comes last in the list of causes and has an id that fits the wire",
			func = function()
				expect(GryMod.ModeReasons.RESTORE).to.equal("restore")
				expect(GryMod.ModeReasonList[#GryMod.ModeReasonList]).to.equal("restore")
				expect(GryMod.ModeReasonIds.restore).to.equal(9)
				expect(GryMod.ModeReasonIds.sync).to.equal(8)
			end
		},
		{
			-- fails when a spawn without veto no longer resets the suit (a full bar, armor mode, the HUD told), the behaviour of every spawn so far
			name = "without a veto a spawn is what it always was: full bar, armor mode, the HUD is told",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryEnergy", 40)

				local sent = spawn(p)

				expect(p:GetNW2Float("GryEnergy")).to.equal(100)
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.ARMOR)
				expect(has(sent, "gry_spawn")).to.beTrue()
			end
		},
		{
			-- fails when a handler that answers true or nothing keeps the state (only false does)
			name = "a handler that answers nothing or true does not keep the state",
			func = function()
				local p = ply()

				for _, answer in ipairs({"nothing", true}) do
					hook.Remove("GryMod_CanResetOnSpawn", "gry_test_restore")
					hook.Add("GryMod_CanResetOnSpawn", "gry_test_restore", function()
						if answer == true then
							return true
						end
					end)
					p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
					p:SetNW2Float("GryEnergy", 40)
					spawn(p)
					expect(p:GetNW2Float("GryEnergy")).to.equal(100)
					expect(p.Nanosuit_mode).to.equal(GryMod.Modes.ARMOR)
				end
			end
		},
		{
			-- fails when the veto does not keep the energy, the mode and the camouflage, or still plays the start-up (gry_spawn), tells the client a mode (it did not change),
			-- or announces a mode change to the addons
			name = "a veto keeps the energy, the camouflage and the notarget, tells nothing to the client and announces no change",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryEnergy", 40)
				p:SetNoTarget(false) -- what the engine's Spawn does
				changes = {}
				veto(false)

				local sent = spawn(p)

				expect(p:GetNW2Float("GryEnergy")).to.equal(40)
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.CLOAK)
				expect(p:GetNW2Bool("GryCloak", false)).to.beTrue()
				expect(p:IsFlagSet(FL_NOTARGET)).to.beTrue()
				expect(has(sent, "gry_spawn")).to.beFalse()
				expect(has(sent, "gry_nanosuit_mode_change")).to.beFalse()
				expect(#changes).to.equal(0)
			end
		},
		{
			-- fails when the veto is only asked by some of the spawn hooks: the energy is back at 100 (sv_system.lua), the radar forgets its tags (sv_radar.lua), the malfunction
			-- is cleared (sv_malfunction.lua) or the regeneration is reset (sv_health.lua), each of them is checked here
			name = "a veto keeps what the other spawn hooks reset: the radar's tags, a malfunction in progress, the repair and recharge delays",
			func = function()
				local p = ply()

				p.last_repair_sound = 12.5
				p.next_energy_regen = 4321
				p.energy_on_use = 33
				GryMod.Radar.State(p).tagged[p] = true
				p:SetNW2Bool("GryMalfunction", true)
				p.gryMalfunctionEnd = CurTime() + 30
				veto(false)
				spawn(p)

				expect(GryMod.Radar.State(p).tagged[p]).to.beTrue()
				expect(p:GetNW2Bool("GryMalfunction", false)).to.beTrue()
				expect(p.last_repair_sound).to.equal(12.5)
				expect(p.next_energy_regen).to.equal(4321)
				expect(p.energy_on_use).to.equal(33)

				-- without the veto all of it goes
				hook.Remove("GryMod_CanResetOnSpawn", "gry_test_restore")
				spawn(p)
				expect(GryMod.Radar.State(p).tagged[p]).to.beNil()
				expect(p:GetNW2Bool("GryMalfunction", false)).to.beFalse()
			end
		},
		{
			-- fails when the speed mode's run speed (erased by the engine's Spawn) is not put back, or the jump power
			name = "a veto in the speed mode puts the run speed of the mode back after the engine's Spawn",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.SPEED, false)

				local run = p:GetRunSpeed()

				p:SetRunSpeed(100)
				veto(false)
				spawn(p)

				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.SPEED)
				expect(p:GetRunSpeed()).to.equal(run)
			end
		},
		{
			-- fails when the veto is asked once by each hook (six questions to a handler that may count or have a side effect) instead of once for the spawn
			name = "the handler is asked once per spawn, however many hooks need the answer, and again at the next spawn",
			func = function()
				local p = ply()
				local asked = 0

				hook.Add("GryMod_CanResetOnSpawn", "gry_test_restore", function()
					asked = asked + 1

					return false
				end)

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				spawn(p)
				expect(asked).to.equal(1)
				spawn(p)
				expect(asked).to.equal(2)
			end
		},
		{
			-- fails when a handler that raises an error breaks the spawn of the player (no hook after it runs) or is read as a veto
			name = "a handler that raises an error does not break the spawn and is not a veto",
			func = function()
				local p = ply()

				hook.Add("GryMod_CanResetOnSpawn", "gry_test_restore", function()
					error("handler failure")
				end)
				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryEnergy", 40)

				local realNoHalt = ErrorNoHalt

				ErrorNoHalt = function() end

				local ok, err = pcall(spawn, p)

				ErrorNoHalt = realNoHalt
				assert(ok, err)
				expect(p:GetNW2Float("GryEnergy")).to.equal(100)
			end
		},
		{
			-- fails when the veto is obeyed for a player that has no suit state yet (a first spawn: nothing to keep)
			name = "a veto for a player who never had a mode does nothing special: the usual first spawn",
			func = function()
				local p = ply()
				local was = p.Nanosuit_mode

				p.Nanosuit_mode = nil
				p:SetNW2Float("GryEnergy", 40)
				veto(false)
				spawn(p)
				expect(p:GetNW2Float("GryEnergy")).to.equal(100)
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.ARMOR)
				p.Nanosuit_mode = was or GryMod.Modes.ARMOR
			end
		},
		{
			-- fails when the real Spawn of the engine (which clears the notarget flag, the material and the run speed) is not followed by the suit putting them back
			name = "with the real Player:Spawn of the engine: the camouflaged player keeps the notarget flag and his bar",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryEnergy", 55)
				veto(false)

				local sent = spawn(p, "engine")

				expect(p:Alive()).to.beTrue()
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.CLOAK)
				expect(p:IsFlagSet(FL_NOTARGET)).to.beTrue()
				expect(p:GetNW2Float("GryEnergy")).to.equal(55)
				expect(has(sent, "gry_spawn")).to.beFalse()
			end
		}
	}
}
