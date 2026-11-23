-- Tests of the suit commands and events of the extension API (lua/grymod/server/sv_api.lua), GLuaTest format, server realm.
-- The commands WRAP the existing code (Player:SetNanosuitMode, the energy networked float with the GryUseEnergy hook,
-- GryMod.Malfunction): these tests also check that the old hooks keep firing and that the rules of the wrapped code
-- (the veto, the suit that is off, the malfunction) hold on EVERY path that changes the mode, the client's request included.
-- Design: docs/superpowers/specs/2026-11-21-extension-api-design.md, part 1.

local function ply()
	return player.GetAll()[1]
end

local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 0.001)
end

local savedConfig
local added = {}

-- a hook of the test, removed in afterEach
local function listen(event, fn)
	local id = "gry_api_suit_test_" .. event .. "_" .. #added
	hook.Add(event, id, fn)
	added[#added + 1] = {event, id}
end

local function takeDamage(p, amount, damageType)
	local dmg = DamageInfo()
	dmg:SetDamage(amount)
	dmg:SetDamageType(damageType or DMG_BULLET)
	hook.GetTable().EntityTakeDamage["Grymod damage handeling"](p, dmg)

	return dmg
end

-- the messages "gry_nanosuit_mode_change" the server starts: the mode (first UInt) and the cause (second UInt, an id of GryMod.ModeReasonIds) of each,
-- kept apart. The real functions still run (the message goes to the test client's player, as before).
local realStart, realUInt, realSend
local sentModes, sentReasons, sentReasonBits

local function spyNet()
	realStart, realUInt, realSend = net.Start, net.WriteUInt, net.Send
	sentModes, sentReasons, sentReasonBits = {}, {}, {}
	local current, written = nil, 0

	net.Start = function(name, ...)
		current, written = name, 0

		return realStart(name, ...)
	end

	net.WriteUInt = function(value, bits)
		if current == "gry_nanosuit_mode_change" then
			written = written + 1

			if written == 1 then
				sentModes[#sentModes + 1] = value
			elseif written == 2 then
				sentReasons[#sentReasons + 1] = value
				sentReasonBits[#sentReasonBits + 1] = bits
			end
		end

		return realUInt(value, bits)
	end
end

local function unspyNet()
	if realStart then
		net.Start, net.WriteUInt, net.Send = realStart, realUInt, realSend
		realStart, realUInt, realSend = nil, nil, nil
	end
end

-- runs fn with the spy on; the real net functions are back right after, whatever happens inside (afterEach puts them back too)
local function spied(fn)
	spyNet()

	local ok, err = pcall(fn)
	unspyNet()

	if not ok then
		error(err, 0)
	end
end

return {
	groupName = "GryMod extension API: suit commands and events (server)",
	beforeAll = function()
		savedConfig = table.Copy(GryMod.Config)
	end,
	beforeEach = function()
		local p = ply()
		if not p:Alive() then p:Spawn() end

		GryMod.Config = table.Copy(savedConfig)
		GryMod.Config.InfiniteArmor = false
		GryMod.Config.Mechanics = "classic"
		GryMod.Malfunction.Clear(p)
		p:SetNW2Bool("GryDisabled", false)
		p:SetHealth(p:GetMaxHealth())
		p:SetNW2Float("GryEnergy", 100)
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		p.gryApiEnergyEmpty = nil
	end,
	afterEach = function()
		unspyNet()

		for _, h in ipairs(added) do
			hook.Remove(h[1], h[2])
		end

		added = {}

		local p = ply()

		if IsValid(p) then
			GryMod.Malfunction.Clear(p)
			p:SetNW2Bool("GryDisabled", false)
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
			p:SetNW2Float("GryEnergy", 100)
			p:SetHealth(p:GetMaxHealth())
		end

		GryMod.Config = table.Copy(savedConfig)
	end,
	cases = {
		{
			name = "the commands exist, and the optional part is advertised",
			func = function()
				for _, name in ipairs({"SetEnergy", "AddEnergy", "RefillEnergy", "EmptyEnergy", "GetEnergy", "SetMode", "GetMode", "SetSuitEnabled", "IsSuitEnabled", "StartMalfunction", "EMP"}) do
					expect(isfunction(GryMod.API[name])).to.beTrue()
				end
			end
		},
		-- energy
		{
			name = "SetEnergy sets the energy, clamped to 0..100, and returns true",
			func = function()
				local API, p = GryMod.API, ply()

				expect(API.SetEnergy(p, 42.5)).to.beTrue()
				expect(p:GetNW2Float("GryEnergy")).to.equal(42.5)
				expect(API.GetEnergy(p)).to.equal(42.5)

				expect(API.SetEnergy(p, 250)).to.beTrue()
				expect(API.GetEnergy(p)).to.equal(100)

				expect(API.SetEnergy(p, -30)).to.beTrue()
				expect(API.GetEnergy(p)).to.equal(0)
			end
		},
		{
			name = "SetEnergy refuses what is not a number (nil, text, NaN) and a player that is not valid, with a reason, and changes nothing",
			func = function()
				local API, p = GryMod.API, ply()
				p:SetNW2Float("GryEnergy", 60)

				for _, bad in ipairs({"lots", true, 0 / 0}) do
					local ok, reason = API.SetEnergy(p, bad)
					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
				end

				expect(API.SetEnergy(p, nil)).to.beFalse()
				expect(API.SetEnergy(nil, 10)).to.beFalse()
				expect(API.SetEnergy(NULL, 10)).to.beFalse()
				expect(API.SetEnergy(game.GetWorld(), 10)).to.beFalse()
				expect(API.SetEnergy(5, 10)).to.beFalse() -- junk raises nothing (IsValid itself errors on a number)
				expect(API.SetMode("player", GryMod.Modes.ARMOR)).to.beFalse()
				expect(API.GetMode(12)).to.beNil()
				expect(API.IsSuitEnabled(12)).to.beFalse()
				expect(API.GetEnergy(p)).to.equal(60)
				expect(API.GetEnergy(nil)).to.beNil()
			end
		},
		{
			name = "AddEnergy adds (a negative amount takes), clamped; RefillEnergy fills the bar; EmptyEnergy empties it",
			func = function()
				local API, p = GryMod.API, ply()
				p:SetNW2Float("GryEnergy", 50)

				expect(API.AddEnergy(p, 20)).to.beTrue()
				expect(API.GetEnergy(p)).to.equal(70)
				expect(API.AddEnergy(p, -100)).to.beTrue()
				expect(API.GetEnergy(p)).to.equal(0)
				expect(API.AddEnergy(p, 1000)).to.beTrue()
				expect(API.GetEnergy(p)).to.equal(100)

				API.SetEnergy(p, 10)
				expect(API.RefillEnergy(p)).to.beTrue()
				expect(API.GetEnergy(p)).to.equal(100)
				expect(API.EmptyEnergy(p)).to.beTrue()
				expect(API.GetEnergy(p)).to.equal(0)

				expect(API.AddEnergy(p, "x")).to.beFalse()
			end
		},
		{
			name = "an energy command counts as a use of the energy (the recharge delay starts from the new value): it goes through the GryUseEnergy hook, nothing is duplicated",
			func = function()
				local API, p = GryMod.API, ply()
				p.next_energy_regen = 0
				p.energy_on_use = 99

				API.SetEnergy(p, 30)

				expect(p.energy_on_use).to.equal(30)
				expect(p.next_energy_regen > CurTime()).to.beTrue()
			end
		},
		{
			name = "GryMod_EnergyUsed is the new name of GryUseEnergy: both fire for the same use, and the old one keeps working",
			func = function()
				local p = ply()
				local oldCount, newCount, lastPlayer = 0, 0, nil

				listen("GryUseEnergy", function() oldCount = oldCount + 1 end)
				listen("GryMod_EnergyUsed", function(who) newCount = newCount + 1; lastPlayer = who end)

				hook.Run("GryUseEnergy", p)

				expect(oldCount).to.equal(1)
				expect(newCount).to.equal(1)
				expect(lastPlayer).to.equal(p)

				GryMod.API.SetEnergy(p, 20)

				expect(oldCount).to.equal(2)
				expect(newCount).to.equal(2)
			end
		},
		{
			name = "GryMod_EnergyEmpty fires once when the bar reaches 0 (EmptyEnergy, SetEnergy 0, armor damage), not again while it stays empty, and again after it was above 0",
			func = function()
				local API, p = GryMod.API, ply()
				local count = 0

				listen("GryMod_EnergyEmpty", function(who)
					expect(who).to.equal(p)
					count = count + 1
				end)

				API.SetEnergy(p, 50)
				expect(count).to.equal(0)

				API.EmptyEnergy(p)
				expect(count).to.equal(1)

				API.EmptyEnergy(p)
				API.SetEnergy(p, 0)
				expect(count).to.equal(1)

				API.SetEnergy(p, 30)
				takeDamage(p, 80, DMG_BULLET) -- the armor takes the 30 and the bar is empty
				expect(API.GetEnergy(p)).to.equal(0)
				expect(count).to.equal(2)
			end
		},
		-- mode
		{
			name = "SetMode puts the suit in a real mode (armor, speed, cloak, strength) and GetMode tells it",
			func = function()
				local API, p = GryMod.API, ply()
				local M = GryMod.Modes

				for _, mode in ipairs({M.SPEED, M.CLOAK, M.STRENGTH, M.ARMOR}) do
					expect(API.SetMode(p, mode)).to.beTrue()
					expect(API.GetMode(p)).to.equal(mode)
					expect(p.Nanosuit_mode).to.equal(mode)
				end
			end
		},
		{
			name = "SetMode refuses a mode that does not exist, the drop pseudo-mode, a name and nil, a dead player, and keeps the mode",
			func = function()
				local API, p = GryMod.API, ply()
				API.SetMode(p, GryMod.Modes.SPEED)

				for _, bad in ipairs({GryMod.Modes.DROP, 7, -1, "speed", 1.5}) do
					local ok, reason = API.SetMode(p, bad)
					expect(ok).to.beFalse()
					expect(reason).to.equal("invalid mode")
				end

				expect(API.SetMode(p, nil)).to.beFalse()
				expect(API.SetMode(nil, GryMod.Modes.ARMOR)).to.beFalse()
				expect(API.GetMode(p)).to.equal(GryMod.Modes.SPEED)

				p:KillSilent()
				local ok, reason = API.SetMode(p, GryMod.Modes.ARMOR)
				expect(ok).to.beFalse()
				expect(reason).to.equal("dead")
				p:Spawn()
			end
		},
		{
			name = "GryMod_ModeChanged(ply, mode, oldMode) fires when the mode changes, not for the same mode, and the old GryNanosuitMode keeps firing",
			func = function()
				local API, p = GryMod.API, ply()
				local changes, legacy = {}, 0

				listen("GryMod_ModeChanged", function(who, mode, old) changes[#changes + 1] = {who, mode, old} end)
				listen("GryNanosuitMode", function() legacy = legacy + 1 end)

				API.SetMode(p, GryMod.Modes.SPEED)

				expect(#changes).to.equal(1)
				expect(changes[1][1]).to.equal(p)
				expect(changes[1][2]).to.equal(GryMod.Modes.SPEED)
				expect(changes[1][3]).to.equal(GryMod.Modes.ARMOR)
				expect(legacy).to.equal(1)

				API.SetMode(p, GryMod.Modes.SPEED)
				expect(#changes).to.equal(1)

				API.SetMode(p, GryMod.Modes.CLOAK)
				expect(#changes).to.equal(2)
				expect(changes[2][3]).to.equal(GryMod.Modes.SPEED)
			end
		},
		{
			name = "GryMod.ModeReasons names the causes of a mode change: plain strings, all different",
			func = function()
				expect(GryMod.ModeReasons).to.exist()

				local seen = {}

				for _, key in ipairs({"SPAWN", "PLAYER", "API", "ENERGY", "MALFUNCTION", "DISABLED", "OTHER", "VETOED", "SYNC"}) do
					local value = GryMod.ModeReasons[key]
					expect(isstring(value)).to.beTrue()
					expect(seen[value]).to.beNil()
					seen[value] = true
				end
			end
		},
		{
			name = "GryMod_ModeChanged gets the cause as 4th argument: the API, the player's request, the empty bar of the camouflage, a malfunction, the suit switched off",
			func = function()
				local API, p, Why = GryMod.API, ply(), GryMod.ModeReasons
				local causes = {}

				listen("GryMod_ModeChanged", function(who, mode, old, why) causes[#causes + 1] = why end)

				API.SetMode(p, GryMod.Modes.SPEED)
				expect(causes[#causes]).to.equal(Why.API)

				GryMod.SetModeFromClient(p, GryMod.Modes.STRENGTH)
				expect(causes[#causes]).to.equal(Why.PLAYER)

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false, Why.API)
				p:SetNW2Float("GryEnergy", 0)
				hook.GetTable().Think["GryCloakThink"]()
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.ARMOR)
				expect(causes[#causes]).to.equal(Why.ENERGY)

				API.SetMode(p, GryMod.Modes.SPEED)
				API.StartMalfunction(p, 5, "test")
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.ARMOR)
				expect(causes[#causes]).to.equal(Why.MALFUNCTION)
				GryMod.Malfunction.Clear(p)

				API.SetMode(p, GryMod.Modes.SPEED)
				API.SetSuitEnabled(p, false)
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.ARMOR)
				expect(causes[#causes]).to.equal(Why.DISABLED)
			end
		},
		{
			name = "a mode that is asked while the suit cannot take it ends in armor, and the cause is the real one (disabled), not the asker's",
			func = function()
				local API, p, Why = GryMod.API, ply(), GryMod.ModeReasons
				local seen = {}

				API.SetMode(p, GryMod.Modes.SPEED)
				p:SetNW2Bool("GryDisabled", true)

				listen("GryMod_ModeChanged", function(who, mode, old, why) seen[#seen + 1] = {mode, old, why} end)

				local ok, refused = API.SetMode(p, GryMod.Modes.CLOAK)

				expect(ok).to.beFalse()
				expect(refused).to.equal("disabled")
				expect(#seen).to.equal(1)
				expect(seen[1][1]).to.equal(GryMod.Modes.ARMOR)
				expect(seen[1][2]).to.equal(GryMod.Modes.SPEED)
				expect(seen[1][3]).to.equal(Why.DISABLED)
			end
		},
		{
			-- would fail if: the hook only ran when the mode changed (armor to armor says nothing), or the respawn's cause was not SPAWN
			name = "the respawn is always announced (cause SPAWN), even armor to armor, and the old mode is given when there was one",
			func = function()
				local API, p, Why = GryMod.API, ply(), GryMod.ModeReasons
				local seen = {}
				local spawn = hook.GetTable().PlayerSpawn["GryModSpawn"]

				expect(spawn ~= nil).to.beTrue()
				listen("GryMod_ModeChanged", function(who, mode, old, why) seen[#seen + 1] = {who, mode, old, why} end)

				spawn(p) -- armor to armor: still announced
				expect(#seen).to.equal(1)
				expect(seen[1][1]).to.equal(p)
				expect(seen[1][2]).to.equal(GryMod.Modes.ARMOR)
				expect(seen[1][3]).to.equal(GryMod.Modes.ARMOR)
				expect(seen[1][4]).to.equal(Why.SPAWN)

				API.SetMode(p, GryMod.Modes.CLOAK)
				seen = {}
				spawn(p)

				expect(#seen).to.equal(1)
				expect(seen[1][1]).to.equal(p)
				expect(seen[1][2]).to.equal(GryMod.Modes.ARMOR)
				expect(seen[1][3]).to.equal(GryMod.Modes.CLOAK)
				expect(seen[1][4]).to.equal(Why.SPAWN)
			end
		},
		{
			-- would fail if: the respawn set the energy to 100 AFTER SetNanosuitMode (a handler of SPAWN would still read the energy of the last life)
			name = "at the respawn the energy is 100 BEFORE the hook: a handler of GryMod_ModeChanged(SPAWN) reads the full bar, not the old one",
			func = function()
				local p, Why = ply(), GryMod.ModeReasons
				local spawn = hook.GetTable().PlayerSpawn["GryModSpawn"]
				local energy

				p:SetNW2Float("GryEnergy", 10)
				listen("GryMod_ModeChanged", function(who, mode, old, why)
					if why == Why.SPAWN then energy = who:GetNW2Float("GryEnergy", -1) end
				end)

				spawn(p)
				expect(energy).to.equal(100)
				expect(p:GetNW2Float("GryEnergy", -1)).to.equal(100)
			end
		},
		{
			-- would fail if: the condition was only "the cause is SPAWN" (a same-mode call with any other cause would be announced) or the cause alone decided
			name = "no hook when the mode is the same and the cause is not SPAWN: the same mode asked again says nothing, whoever asks",
			func = function()
				local API, p, Why = GryMod.API, ply(), GryMod.ModeReasons
				local seen = 0

				API.SetMode(p, GryMod.Modes.SPEED)
				listen("GryMod_ModeChanged", function() seen = seen + 1 end)

				for _, why in ipairs({Why.API, Why.PLAYER, Why.SYNC, Why.VETOED, Why.OTHER}) do
					p:SetNanosuitMode(GryMod.Modes.SPEED, false, why)
				end

				expect(seen).to.equal(0)
			end
		},
		{
			-- would fail if: the message carried no cause, or the cause was not the one of the path (API here), or was written with another width than ModeReasonBits
			name = "a networked change sends the mode and then the cause as an id (API: 4 bits)",
			func = function()
				local API, p, Why = GryMod.API, ply(), GryMod.ModeReasons

				spied(function()
					API.SetMode(p, GryMod.Modes.SPEED)
				end)

				expect(#sentModes).to.equal(1)
				expect(sentModes[1]).to.equal(GryMod.Modes.SPEED)
				expect(sentReasons[1]).to.equal(GryMod.ModeReasonIds[Why.API])
				expect(sentReasonBits[1]).to.equal(GryMod.ModeReasonBits)
			end
		},
		{
			-- would fail if: the respawn's message (tellMode at the end of SetNanosuitMode) said OTHER or nothing
			name = "the respawn's message carries the cause SPAWN",
			func = function()
				local p, Why = ply(), GryMod.ModeReasons
				local spawn = hook.GetTable().PlayerSpawn["GryModSpawn"]

				spied(function()
					spawn(p)
				end)

				expect(#sentModes).to.equal(1)
				expect(sentModes[1]).to.equal(GryMod.Modes.ARMOR)
				expect(sentReasons[1]).to.equal(GryMod.ModeReasonIds[Why.SPAWN])
			end
		},
		{
			-- would fail if: a mode refused because the suit is down was sent with the asker's cause (API) instead of the real one
			name = "a mode refused because the suit is down is told with the real cause (malfunction), the armor as the mode",
			func = function()
				local API, p, Why = GryMod.API, ply(), GryMod.ModeReasons

				GryMod.Malfunction.Start(p, 5, "emp")

				spied(function()
					API.SetMode(p, GryMod.Modes.SPEED)
				end)

				expect(sentModes[#sentModes]).to.equal(GryMod.Modes.ARMOR)
				expect(sentReasons[#sentReasons]).to.equal(GryMod.ModeReasonIds[Why.MALFUNCTION])
			end
		},
		{
			-- would fail if: the refusal of a request that is not a selectable mode (DROP, a number the client invented) was sent without the cause VETOED
			name = "a request for something that is not a mode is refused with the real mode and the cause VETOED",
			func = function()
				local p, Why = ply(), GryMod.ModeReasons

				GryMod.API.SetMode(p, GryMod.Modes.SPEED)

				spied(function()
					GryMod.SetModeFromClient(p, GryMod.Modes.DROP)
				end)

				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.SPEED)
				expect(#sentModes).to.equal(1)
				expect(sentModes[1]).to.equal(GryMod.Modes.SPEED)
				expect(sentReasons[1]).to.equal(GryMod.ModeReasonIds[Why.VETOED])
			end
		},
		{
			-- would fail if: the veto reached the player without a cause from the API path either (the veto is in SetNanosuitMode, not in SetModeFromClient)
			name = "a mode vetoed by an addon is told to the client with the cause VETOED, also when the request came from the API",
			func = function()
				local p, Why = ply(), GryMod.ModeReasons

				listen("GryMod_CanSetMode", function() return false end)

				spied(function()
					local ok = GryMod.API.SetMode(p, GryMod.Modes.CLOAK)
				end)

				expect(ok).to.beFalse()
				expect(#sentModes).to.equal(1)
				expect(sentModes[1]).to.equal(GryMod.Modes.ARMOR)
				expect(sentReasons[1]).to.equal(GryMod.ModeReasonIds[Why.VETOED])
			end
		},
		{
			name = "a caller that gives no cause gets OTHER (the old two-argument calls keep working)",
			func = function()
				local p, Why = ply(), GryMod.ModeReasons
				local cause

				listen("GryMod_ModeChanged", function(who, mode, old, why) cause = why end)

				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				expect(cause).to.equal(Why.OTHER)
			end
		},
		{
			name = "the veto GryMod_CanSetMode(ply, mode): a handler that returns false refuses the mode; any other answer lets it through",
			func = function()
				local API, p = GryMod.API, ply()
				local asked = {}
				local answer

				listen("GryMod_CanSetMode", function(who, mode)
					asked[#asked + 1] = {who, mode}

					return answer
				end)

				answer = false
				local ok, reason = API.SetMode(p, GryMod.Modes.SPEED)
				expect(ok).to.beFalse()
				expect(reason).to.equal("vetoed")
				expect(API.GetMode(p)).to.equal(GryMod.Modes.ARMOR)
				expect(asked[1][1]).to.equal(p)
				expect(asked[1][2]).to.equal(GryMod.Modes.SPEED)

				for _, other in ipairs({true, 1}) do
					answer = other
					expect(API.SetMode(p, GryMod.Modes.SPEED)).to.beTrue()
					API.SetMode(p, GryMod.Modes.ARMOR)
				end

				answer = nil
				expect(API.SetMode(p, GryMod.Modes.CLOAK)).to.beTrue()
			end
		},
		{
			name = "the veto holds on the client's request too (the quick menu), and the client is told the real mode so both sides stay in step",
			func = function()
				local p = ply()
				GryMod.API.SetMode(p, GryMod.Modes.SPEED)

				listen("GryMod_CanSetMode", function() return false end)
				spied(function()
					GryMod.SetModeFromClient(p, GryMod.Modes.STRENGTH)
				end)

				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.SPEED)
				expect(#sentModes).to.equal(1)
				expect(sentModes[1]).to.equal(GryMod.Modes.SPEED)
				-- would fail if: the veto's answer carried no cause or another one (the client would not know its change was undone by a refusal)
				expect(sentReasons[1]).to.equal(GryMod.ModeReasonIds[GryMod.ModeReasons.VETOED])
			end
		},
		{
			name = "the veto never stops the armor: a suit that goes down (malfunction) or runs out is still forced to armor, whatever a handler says",
			func = function()
				local API, p = GryMod.API, ply()
				API.SetMode(p, GryMod.Modes.SPEED)

				listen("GryMod_CanSetMode", function() return false end)

				expect(API.SetMode(p, GryMod.Modes.ARMOR)).to.beTrue()
				expect(API.GetMode(p)).to.equal(GryMod.Modes.ARMOR)
			end
		},
		{
			name = "SetMode while the suit is down (malfunction) keeps the armor and says why",
			func = function()
				local API, p = GryMod.API, ply()
				GryMod.Malfunction.Start(p, 5, "emp")

				local ok, reason = API.SetMode(p, GryMod.Modes.SPEED)

				expect(ok).to.beFalse()
				expect(reason).to.equal("malfunction")
				expect(API.GetMode(p)).to.equal(GryMod.Modes.ARMOR)
			end
		},
		-- malfunction and EMP
		{
			name = "StartMalfunction puts the suit down for the given seconds with the reason (the wrapped Malfunction.Start), and refuses a bad player",
			func = function()
				local API, p = GryMod.API, ply()
				local started

				listen("GryMod_MalfunctionStart", function(who, seconds, reason) started = {who, seconds, reason} end)

				expect(API.StartMalfunction(p, 4, "scripted")).to.beTrue()
				expect(GryMod.Malfunction.IsActive(p)).to.beTrue()
				expect(started[1]).to.equal(p)
				expect(started[2]).to.equal(4)
				expect(started[3]).to.equal("scripted")

				expect(API.StartMalfunction(nil, 4, "x")).to.beFalse()
				expect(API.StartMalfunction(NULL, 4, "x")).to.beFalse()
			end
		},
		{
			name = "EMP puts the suits in range down and returns how many; out of range none; a position that is not a vector is refused",
			func = function()
				local API, p = GryMod.API, ply()

				expect(API.EMP(p:GetPos() + Vector(100000, 0, 0), 300, 5)).to.equal(0)
				expect(GryMod.Malfunction.IsActive(p)).to.beFalse()

				expect(API.EMP(p:GetPos(), 300, 5)).to.equal(1)
				expect(GryMod.Malfunction.IsActive(p)).to.beTrue()

				GryMod.Malfunction.Clear(p)
				local count, reason = API.EMP("here", 300, 5)
				expect(count).to.equal(0)
				expect(isstring(reason)).to.beTrue()
			end
		},
		-- the suit enabled or not
		{
			name = "SetSuitEnabled(false) switches the suit off: the network flag, armor mode forced, the events once; true restores it",
			func = function()
				local API, p = GryMod.API, ply()
				local offs, ons = 0, 0

				listen("GryMod_SuitDisabled", function(who) expect(who).to.equal(p); offs = offs + 1 end)
				listen("GryMod_SuitEnabled", function(who) expect(who).to.equal(p); ons = ons + 1 end)

				expect(API.IsSuitEnabled(p)).to.beTrue()

				API.SetMode(p, GryMod.Modes.SPEED)
				expect(API.SetSuitEnabled(p, false)).to.beTrue()

				expect(API.IsSuitEnabled(p)).to.beFalse()
				expect(p:GetNW2Bool("GryDisabled")).to.beTrue()
				expect(API.GetMode(p)).to.equal(GryMod.Modes.ARMOR)
				expect(offs).to.equal(1)

				API.SetSuitEnabled(p, false)
				expect(offs).to.equal(1)

				expect(API.SetSuitEnabled(p, true)).to.beTrue()
				expect(API.IsSuitEnabled(p)).to.beTrue()
				expect(p:GetNW2Bool("GryDisabled")).to.beFalse()
				expect(ons).to.equal(1)

				API.SetSuitEnabled(p, true)
				expect(ons).to.equal(1)

				expect(API.SetSuitEnabled(nil, true)).to.beFalse()
				expect(API.SetSuitEnabled(p, "yes")).to.beFalse()
			end
		},
		{
			name = "a suit that is off accepts no mode change, from the API or from the client, and says why; once back on the modes work again",
			func = function()
				local API, p = GryMod.API, ply()
				API.SetSuitEnabled(p, false)

				local ok, reason = API.SetMode(p, GryMod.Modes.SPEED)
				expect(ok).to.beFalse()
				expect(reason).to.equal("disabled")
				expect(API.GetMode(p)).to.equal(GryMod.Modes.ARMOR)

				GryMod.SetModeFromClient(p, GryMod.Modes.CLOAK)
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.ARMOR)
				expect(p:GetNW2Bool("GryCloak")).to.beFalse()

				API.SetSuitEnabled(p, true)
				expect(API.SetMode(p, GryMod.Modes.SPEED)).to.beTrue()
			end
		},
		{
			name = "a suit that is off has no drain: the armor takes nothing, the whole hit goes through, the energy is untouched",
			func = function()
				local API, p = GryMod.API, ply()
				API.SetEnergy(p, 80)
				API.SetSuitEnabled(p, false)

				local dmg = takeDamage(p, 30, DMG_BULLET)

				expect(dmg:GetDamage()).to.equal(30)
				expect(API.GetEnergy(p)).to.equal(80)

				API.SetSuitEnabled(p, true)
				dmg = takeDamage(p, 30, DMG_BULLET)

				expect(dmg:GetDamage()).to.equal(0)
				expect(API.GetEnergy(p)).to.equal(50)
			end
		},
		{
			name = "a suit that is off has no recharge, and the rate told to the client is 0; back on, the recharge resumes",
			func = function()
				local API, p = GryMod.API, ply()
				API.SetEnergy(p, 20)
				local think = hook.GetTable().Think["GryMod health think"]

				API.SetSuitEnabled(p, false)
				p.next_energy_regen = CurTime() - 3
				p.energy_on_use = 20
				think()

				expect(API.GetEnergy(p)).to.equal(20)
				expect(GryMod.EnergyRate(p)).to.equal(0)

				API.SetSuitEnabled(p, true)
				p.next_energy_regen = CurTime() - 3
				p.energy_on_use = 20
				think()

				expect(API.GetEnergy(p) > 20).to.beTrue()
				expect(GryMod.EnergyRate(p) > 0).to.beTrue()
			end
		},
		{
			name = "a suit that is off cannot go down in a malfunction (nothing to put down); the flag survives a respawn",
			func = function()
				local API, p = GryMod.API, ply()
				API.SetSuitEnabled(p, false)

				local ok = API.StartMalfunction(p, 5, "emp")
				expect(ok).to.beFalse()
				expect(GryMod.Malfunction.IsActive(p)).to.beFalse()

				hook.GetTable().PlayerSpawn["GryModSpawn"](p)
				expect(API.IsSuitEnabled(p)).to.beFalse()
				expect(API.GetMode(p)).to.equal(GryMod.Modes.ARMOR)
			end
		}
	}
}
