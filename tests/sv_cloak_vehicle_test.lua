-- Tests of the notarget flag of the camouflage (sv_system.lua: GryMod.NoTarget; sv_cloak_ai.lua: the hooks PlayerEnteredVehicle / PlayerLeaveVehicle and the 0.5 s timer of CloakAI.Tick),
-- GLuaTest format, server realm. The owner's decisions: (1) the AI must NOT ignore a camouflaged player who sits in a vehicle ("they see a vehicle move"), whatever the base of the
-- vehicle: the source of truth is Player:InVehicle(). While he is seated the FL_NOTARGET that GryMod set is taken off and the camouflaged-player rules of the NPCs (cloakBlind) do not
-- apply; when he gets out and is still camouflaged the flag is put back, AT ONCE (the engine's hooks) and, for a base that puts a player in without them, within the 0.5 s of the timer.
-- (2) GryMod only takes off a notarget that it set itself: a notarget of the engine's command or of another addon is never erased. Real seats (prop_vehicle_prisoner_pod) are used.
-- Each case names the production change whose absence makes it fail.

local function ply()
	return player.GetAll()[1]
end

local spawned = {}
local savedAI

local function setAI(value)
	local c = GetConVar("gry_cloak_ai")

	if c then
		c:SetString(value)
	end
end

local function seat(dx)
	local p = ply()
	local s = ents.Create("prop_vehicle_prisoner_pod")

	s:SetModel("models/nova/airboat_seat.mdl")
	s:SetKeyValue("vehiclescript", "scripts/vehicles/prisoner_pod.txt")
	s:SetKeyValue("limitview", "0")
	s:SetPos(p:GetPos() + Vector(100 + (dx or 0), 0, 20))
	s:Spawn()
	s:Activate()
	spawned[#spawned + 1] = s

	return s
end

local function noTarget()
	return ply():IsFlagSet(FL_NOTARGET)
end

local function cloak(on)
	ply():SetNanosuitMode(on and GryMod.Modes.CLOAK or GryMod.Modes.ARMOR, false)
end

return {
	groupName = "GryMod camouflage: the notarget flag and the vehicles (server)",
	beforeAll = function()
		savedAI = GetConVar("gry_cloak_ai") and GetConVar("gry_cloak_ai"):GetString()
	end,
	beforeEach = function()
		local p = ply()

		if not p:Alive() then
			p:Spawn()
		end

		if p:InVehicle() then
			p:ExitVehicle()
		end

		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		p:SetNoTarget(false)
		p.GryOwnsNoTarget = nil
		p:SetNW2Float("GryEnergy", 100)
		setAI("1")
	end,
	afterEach = function()
		local p = ply()

		if IsValid(p) then
			if p:InVehicle() then
				p:ExitVehicle()
			end

			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
			p:SetNoTarget(false)
			p.GryOwnsNoTarget = nil
		end

		for _, e in ipairs(spawned) do
			if IsValid(e) then
				e:Remove()
			end
		end

		spawned = {}
		setAI(savedAI or "1")
	end,
	cases = {
		{
			-- fails when the flag stays on a camouflaged player who gets into a seat (the AI would ignore a vehicle that moves), or is not put back when he gets out still camouflaged
			name = "camouflaged, he gets into a seat: no notarget; he gets out: the notarget is back (the engine's hooks, at once)",
			func = function()
				local p, s = ply(), seat()

				cloak(true)
				expect(noTarget()).to.beTrue()

				p:EnterVehicle(s)
				expect(p:InVehicle()).to.beTrue()
				expect(noTarget()).to.beFalse()
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.CLOAK)

				p:ExitVehicle()
				expect(p:InVehicle()).to.beFalse()
				expect(noTarget()).to.beTrue()
			end
		},
		{
			-- fails when going camouflaged while seated sets the flag (it must wait for the exit)
			name = "going camouflaged while seated does not set the notarget; getting out sets it",
			func = function()
				local p, s = ply(), seat()

				p:EnterVehicle(s)
				cloak(true)
				expect(noTarget()).to.beFalse()

				p:ExitVehicle()
				expect(noTarget()).to.beTrue()
			end
		},
		{
			-- fails when ending the camouflage while seated puts the flag at the exit (the flag was off: nothing to put back), or leaves the ownership mark behind
			name = "leaving the camouflage while seated: nothing is put at the exit, and GryMod owns no notarget any more",
			func = function()
				local p, s = ply(), seat()

				cloak(true)
				p:EnterVehicle(s)
				cloak(false)
				expect(noTarget()).to.beFalse()

				p:ExitVehicle()
				expect(noTarget()).to.beFalse()
				expect(p.GryOwnsNoTarget).to.beNil()
			end
		},
		{
			-- fails when going in and out several times loses the flag, puts it twice or leaks an ownership mark
			name = "in and out ten times: the flag is off while seated and on while standing, every time, and nothing is left behind",
			func = function()
				local p, s = ply(), seat()

				cloak(true)

				for i = 1, 10 do
					p:EnterVehicle(s)
					expect(noTarget()).to.beFalse()
					expect(p.GryOwnsNoTarget).to.beNil()
					p:ExitVehicle()
					expect(noTarget()).to.beTrue()
					expect(p.GryOwnsNoTarget).to.beTrue()
				end

				cloak(false)
				expect(noTarget()).to.beFalse()
				expect(p.GryOwnsNoTarget).to.beNil()
			end
		},
		{
			-- fails when the notarget of someone else (the engine's `notarget` command, another addon) is erased by the end of the camouflage: GryMod only undoes what it set
			name = "a notarget set by someone else before the camouflage is still there after it, on foot",
			func = function()
				local p = ply()

				p:SetNoTarget(true)
				cloak(true)
				expect(p.GryOwnsNoTarget).to.beNil()
				cloak(false)
				expect(noTarget()).to.beTrue()
			end
		},
		{
			-- fails when the vehicle logic takes off or puts back a notarget that is not GryMod's
			name = "a notarget of someone else stays whatever happens with a seat: set before the camouflage, or set while seated",
			func = function()
				local p, s = ply(), seat()

				-- set before
				p:SetNoTarget(true)
				cloak(true)
				p:EnterVehicle(s)
				expect(noTarget()).to.beTrue()
				p:ExitVehicle()
				expect(noTarget()).to.beTrue()
				cloak(false)
				expect(noTarget()).to.beTrue()
				p:SetNoTarget(false)

				-- set while seated and camouflaged
				cloak(true)
				p:EnterVehicle(s)
				expect(noTarget()).to.beFalse()
				p:SetNoTarget(true)
				cloak(false)
				expect(noTarget()).to.beTrue()
				p:ExitVehicle()
				expect(noTarget()).to.beTrue()
			end
		},
		{
			-- fails when the NPCs that the camouflage makes blind (cloakBlind: the strider) are still blind to a camouflaged player who sits in a vehicle, or are not blind again at the exit
			name = "a strider that fought the player: neutral to him while he is camouflaged on foot, hostile again when he is seated (it sees the vehicle), neutral again when he gets out",
			func = function()
				local p, s = ply(), seat()
				local npc = ents.Create("npc_strider")

				npc:SetPos(p:GetPos() + Vector(600, 0, 20))
				npc:Spawn()
				npc:Activate()
				spawned[#spawned + 1] = npc
				npc:AddEntityRelationship(p, D_HT, 99)
				npc:SetEnemy(p)

				cloak(true)
				expect(npc:Disposition(p)).to.equal(D_NU)

				p:EnterVehicle(s)
				expect(npc:Disposition(p)).to.equal(D_HT)

				p:ExitVehicle()
				expect(npc:Disposition(p)).to.equal(D_NU)

				p:EnterVehicle(s)
				cloak(false)
				expect(npc:Disposition(p)).to.equal(D_HT)
			end
		},
		{
			-- fails when a base that puts the player in without the engine's hooks (SetParent, an exotic EnterVehicle) is never noticed: the timer of CloakAI.Tick must bring the flag to the
			-- state that is wanted, in both directions, and the timer must exist while he is camouflaged AND seated
			name = "the 0.5 s timer catches a player forced seated without the hooks, and forced standing again: the flag follows InVehicle",
			func = function()
				local p = ply()
				local meta = FindMetaTable("Player")
				local real = meta.InVehicle
				local forced = false

				cloak(true)
				expect(noTarget()).to.beTrue()
				expect(timer.Exists("GryCloakAI")).to.beTrue()

				meta.InVehicle = function() return forced end

				local ok, err = pcall(function()
					forced = true
					expect(noTarget()).to.beTrue() -- no hook ran: nothing has changed yet
					GryMod.CloakAI.Tick()
					expect(noTarget()).to.beFalse()
					-- and he is still watched by the timer while seated
					expect(timer.Exists("GryCloakAI")).to.beTrue()
					expect(timer.TimeLeft("GryCloakAI") <= 0.5).to.beTrue()

					forced = false
					GryMod.CloakAI.Tick()
					expect(noTarget()).to.beTrue()
				end)

				meta.InVehicle = real
				assert(ok, err)
			end
		},
		{
			-- fails when the timer puts the flag back on a seated player (drgbase: a possession that ended lost the flag, the timer puts it back, but never for a seated player)
			name = "the timer puts the notarget back when it was lost on foot, and does not while seated",
			func = function()
				local p, s = ply(), seat()

				cloak(true)
				p:SetNoTarget(false) -- lost: a possession ended, an addon cleared it
				GryMod.CloakAI.Tick()
				expect(noTarget()).to.beTrue()

				p:EnterVehicle(s)
				GryMod.CloakAI.Tick()
				expect(noTarget()).to.beFalse()
				GryMod.CloakAI.Tick()
				expect(noTarget()).to.beFalse()
			end
		},
		{
			-- fails when a respawn leaves the ownership mark of the old life (the next life's notarget of another addon would be erased by the first mode change)
			name = "a respawn forgets the ownership mark: a notarget set by someone else in the new life survives the first mode change",
			func = function()
				local p = ply()

				cloak(true)
				expect(p.GryOwnsNoTarget).to.beTrue()
				p:KillSilent()
				p:Spawn()
				p:SetNoTarget(true)
				cloak(true)
				cloak(false)
				expect(noTarget()).to.beTrue()
			end
		}
	}
}
