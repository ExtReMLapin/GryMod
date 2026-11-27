-- Tests of the push of the refused modes to the quick menu (lua/grymod/server/sv_mode_states.lua and the bits of lua/grymod/sh_mode_states.lua),
-- GLuaTest format, server realm. The veto is GryMod_CanSetMode (docs/api.md). The client never asks: the server sends the mask when a client is ready
-- and at a spawn, when a report of GryMod changes it, when an addon calls GryMod.API.RefreshModeStates, and from a timer that exists only while a veto
-- exists. Each case names the production change whose absence makes it fail. Nothing is sent and no timer is made: net.Start, net.WriteUInt, net.Send
-- and timer.Exists / Create / Remove are replaced by recorders and put back at the end of the case AND in afterEach, whatever happens.

local function ply()
	local p = player.GetAll()[1]

	if not p:Alive() then
		p:Spawn()
	end

	return p
end

local Modes = GryMod.Modes
local States = GryMod.ModeStates
local added = {}

-- a hook of the test, removed in afterEach
local function listen(event, fn)
	local id = "gry_mode_states_test_" .. event .. "_" .. #added
	hook.Add(event, id, fn)
	added[#added + 1] = {event, id}
end

-- the fields a test puts on the real player, put back in afterEach
local touched = {}

local function override(p, key, value)
	if touched[key] == nil then
		touched[key] = {had = rawget(p:GetTable(), key)}
	end

	p[key] = value
end

local function restoreFields(p)
	if IsValid(p) then
		for key, saved in pairs(touched) do
			p[key] = saved.had
		end
	end

	touched = {}
end

-- the recorders: what the server would have sent ({name, value, bits, target}) and the timers it would have made
local real
local sent, timers

local function recordNet()
	real = {
		start = net.Start, writeUInt = net.WriteUInt, send = net.Send,
		exists = timer.Exists, create = timer.Create, remove = timer.Remove,
		hasListeners = States.HasListeners, anyAlive = States.AnyAlive
	}
	sent = {}
	timers = {exists = false, created = {}, removed = 0}
	local current

	net.Start = function(name)
		current = {name = name}
	end

	net.WriteUInt = function(value, bits)
		current.value, current.bits = value, bits
	end

	net.Send = function(target)
		current.target = target
		sent[#sent + 1] = current
	end

	timer.Exists = function() return timers.exists end

	timer.Create = function(name, delay, repetitions, fn)
		timers.created[#timers.created + 1] = {name = name, delay = delay, repetitions = repetitions, fn = fn}
		timers.exists = true
	end

	timer.Remove = function()
		timers.removed = timers.removed + 1
		timers.exists = false
	end
end

local function restoreNet()
	if real then
		net.Start, net.WriteUInt, net.Send = real.start, real.writeUInt, real.send
		timer.Exists, timer.Create, timer.Remove = real.exists, real.create, real.remove
		States.HasListeners, States.AnyAlive = real.hasListeners, real.anyAlive
		real = nil
	end
end

local function recorded(fn)
	recordNet()

	local ok, err = pcall(fn)
	restoreNet()

	if not ok then
		error(err, 0)
	end
end

-- the messages gry_modes_refused sent to one player
local function toPlayer(p)
	local out = {}

	for _, message in ipairs(sent) do
		if message.name == "gry_modes_refused" and message.target == p then
			out[#out + 1] = message
		end
	end

	return out
end

-- a veto the test can change: refuses the camouflage while veto.cloak is true
local veto = {cloak = false}

local function listenVeto()
	listen("GryMod_CanSetMode", function(_, mode)
		if veto.cloak and mode == Modes.CLOAK then
			return false
		end
	end)
end

local savedErrorNoHalt

return {
	groupName = "GryMod quick menu: refused modes pushed to the client (server)",
	beforeEach = function()
		savedErrorNoHalt = ErrorNoHalt
		veto.cloak = false
	end,
	afterEach = function()
		restoreNet()
		ErrorNoHalt = savedErrorNoHalt

		for _, h in ipairs(added) do
			hook.Remove(h[1], h[2])
		end

		added = {}
		restoreFields(player.GetAll()[1])
	end,
	cases = {
		{
			-- fails without GryMod.ModeStates.Pack / Unpack (sh_mode_states.lua), or with a bit moved: the bits are the wire format
			name = "the refused modes go through a 3 bit number and come back: speed is bit 0, cloak bit 1, strength bit 2; armor and the weapon drop have no bit",
			func = function()
				expect(States.Bits).to.equal(3)
				expect(States.Pack({})).to.equal(0)
				expect(States.Pack({[Modes.SPEED] = true})).to.equal(1)
				expect(States.Pack({[Modes.CLOAK] = true})).to.equal(2)
				expect(States.Pack({[Modes.STRENGTH] = true})).to.equal(4)
				expect(States.Pack({[Modes.SPEED] = true, [Modes.STRENGTH] = true})).to.equal(5)
				expect(States.Pack({[Modes.ARMOR] = true, [4] = true})).to.equal(0)

				local back = States.Unpack(6)
				expect(back[Modes.CLOAK]).to.beTrue()
				expect(back[Modes.STRENGTH]).to.beTrue()
				expect(back[Modes.SPEED]).to.beNil()

				-- a table given is emptied and filled in place (the menu reads it every frame and makes no garbage)
				local into = {[Modes.SPEED] = true, [Modes.ARMOR] = true}
				expect(States.Unpack(2, into)).to.equal(into)
				expect(into[Modes.SPEED]).to.beNil()
				expect(into[Modes.CLOAK]).to.beTrue()
			end
		},
		{
			-- fails without States.MaskFor
			name = "MaskFor sets the bit of each mode the veto refuses, and nothing when it refuses none",
			func = function()
				expect(States.MaskFor(Modes.ARMOR, false, function() return false end)).to.equal(0)
				expect(States.MaskFor(Modes.ARMOR, false, function(mode) return mode == Modes.CLOAK end)).to.equal(States.Pack({[Modes.CLOAK] = true}))
				expect(States.MaskFor(Modes.ARMOR, false, function() return true end)).to.equal(7)
			end
		},
		{
			-- fails if MaskFor asks about the mode the suit is in (the veto only runs for a change in Player:SetNanosuitMode), or about the armor
			name = "the veto is asked only about the three modes a change can be refused to, never the mode the suit is in, never the armor or the drop",
			func = function()
				local asked = {}
				local mask = States.MaskFor(Modes.CLOAK, false, function(mode)
					asked[#asked + 1] = mode

					return true
				end)

				table.sort(asked)
				expect(table.concat(asked, ",")).to.equal(Modes.SPEED .. "," .. Modes.STRENGTH)
				expect(mask).to.equal(States.Pack({[Modes.SPEED] = true, [Modes.STRENGTH] = true}))
			end
		},
		{
			-- fails if MaskFor asks when the suit is down or off: SetNanosuitMode answers "malfunction" / "disabled" before the veto, so the veto is not asked
			name = "a suit that is down or off asks no veto at all and refuses nothing (the client already knows the state from the networked flags)",
			func = function()
				local calls = 0
				local mask = States.MaskFor(Modes.ARMOR, true, function()
					calls = calls + 1

					return true
				end)

				expect(mask).to.equal(0)
				expect(calls).to.equal(0)
			end
		},
		{
			-- fails without States.Mask reading GryMod_CanSetMode (the hook is run with the player and the mode, as SetNanosuitMode runs it)
			name = "Mask asks the listeners of GryMod_CanSetMode, with the player and the mode, and a false answer refuses; any other answer does not",
			func = function()
				local p = ply()
				override(p, "Nanosuit_mode", Modes.ARMOR)
				local seen = {}

				listen("GryMod_CanSetMode", function(who, mode)
					seen[#seen + 1] = {who, mode}

					if mode == Modes.CLOAK then
						return false
					elseif mode == Modes.SPEED then
						return true -- only false is a veto
					end
				end)

				local back = States.Unpack(States.Mask(p))
				expect(back[Modes.CLOAK]).to.beTrue()
				expect(back[Modes.SPEED]).to.beNil()
				expect(back[Modes.STRENGTH]).to.beNil()
				expect(#seen).to.equal(3)
				expect(seen[1][1]).to.equal(p)
			end
		},
		{
			-- fails if a listener that errors stops the answer or counts as a veto
			name = "a listener that fails does not refuse and does not stop the answer",
			func = function()
				local p = ply()
				override(p, "Nanosuit_mode", Modes.ARMOR)
				local shown = 0
				ErrorNoHalt = function() shown = shown + 1 end

				listen("GryMod_CanSetMode", function(_, mode)
					if mode == Modes.SPEED then
						error("broken listener")
					elseif mode == Modes.STRENGTH then
						return false
					end
				end)

				local back = States.Unpack(States.Mask(p))
				expect(back[Modes.SPEED]).to.beNil()
				expect(back[Modes.STRENGTH]).to.beTrue()
				expect(shown).to.equal(1)
			end
		},
		{
			-- fails if Mask asks the veto for a dead or invalid player
			name = "a player who is not alive, or not valid, gets 0 and no listener is asked",
			func = function()
				local calls = 0

				listen("GryMod_CanSetMode", function()
					calls = calls + 1

					return false
				end)

				local dead = {IsValid = function() return true end, Alive = function() return false end}
				expect(States.Mask(dead)).to.equal(0)
				expect(States.Mask(NULL)).to.equal(0)
				expect(calls).to.equal(0)
			end
		},
		{
			-- fails without Push writing the mask in States.Bits bits to the player, or without it remembering what the client was told
			name = "Push sends gry_modes_refused with the mask, in the width the client reads, and remembers it",
			func = function()
				local p = ply()
				override(p, "Nanosuit_mode", Modes.ARMOR)
				override(p, "gryModesSent", nil)
				veto.cloak = true
				listenVeto()

				recorded(function()
					expect(States.Push(p)).to.beTrue()
					expect(#sent).to.equal(1)
					expect(sent[1].name).to.equal("gry_modes_refused")
					expect(sent[1].value).to.equal(States.Pack({[Modes.CLOAK] = true}))
					expect(sent[1].bits).to.equal(States.Bits)
					expect(sent[1].target).to.equal(p)
					expect(p.gryModesSent).to.equal(sent[1].value)
					expect(States.Push(NULL)).to.beFalse()
				end)
			end
		},
		{
			-- fails if PushIfChanged sends when nothing changed (the network would be filled), or never sends after the first time
			name = "PushIfChanged sends only when the mask is not what the client was told: nothing at first with no veto, one message when a veto appears, none while it stays, one when it goes",
			func = function()
				local p = ply()
				override(p, "Nanosuit_mode", Modes.ARMOR)
				override(p, "gryModesSent", nil)
				listenVeto()

				recorded(function()
					expect(States.PushIfChanged(p)).to.beFalse() -- a client starts with no mode refused: it already knows
					expect(#sent).to.equal(0)

					veto.cloak = true
					expect(States.PushIfChanged(p)).to.beTrue()
					expect(#sent).to.equal(1)
					expect(sent[1].value).to.equal(States.Pack({[Modes.CLOAK] = true}))

					expect(States.PushIfChanged(p)).to.beFalse()
					expect(States.PushIfChanged(p)).to.beFalse()
					expect(#sent).to.equal(1)

					veto.cloak = false
					expect(States.PushIfChanged(p)).to.beTrue()
					expect(#sent).to.equal(2)
					expect(sent[2].value).to.equal(0)
				end)
			end
		},
		{
			-- fails if the client can still ask (the owner: asking on opening slows the menu and spams the network)
			name = "there is no message of the client asking for the modes, and the server has no receiver or throttle for one",
			func = function()
				expect(util.NetworkStringToID("gry_modes_ask")).to.equal(0)
				expect(net.Receivers["gry_modes_ask"]).to.beNil()
				expect(States.Answer).to.beNil()
				expect(States.AskInterval).to.beNil()
			end
		},
		{
			-- fails without the push in AnswerReady: a client that joins would hold no mask until something changed
			name = "a client that says it is ready is told the refused modes at once, whether or not they changed",
			func = function()
				local p = ply()
				override(p, "Nanosuit_mode", Modes.ARMOR)
				override(p, "gryModesSent", 0)
				override(p, "gryReadyAnswered", nil)

				recorded(function()
					expect(GryMod.AnswerReady(p)).to.beTrue()
					expect(#toPlayer(p)).to.equal(1) -- nothing refused, still sent: the client has just loaded
					expect(toPlayer(p)[1].value).to.equal(0)
				end)
			end
		},
		{
			-- fails without the ModeChanged listener, or if a respawn is not always pushed
			name = "a change of mode pushes only if the mask changed; a respawn always pushes (the client may hold the last life's mask)",
			func = function()
				local listener = hook.GetTable().GryMod_ModeChanged and hook.GetTable().GryMod_ModeChanged["GRYMODESTATES"]
				expect(listener).to.beA("function")
				local p = ply()
				override(p, "Nanosuit_mode", Modes.ARMOR)
				override(p, "gryModesSent", 0)
				listenVeto()

				recorded(function()
					States.HasListeners, States.AnyAlive = function() return false end, function() return false end

					listener(p, Modes.SPEED, Modes.ARMOR, GryMod.ModeReasons.PLAYER)
					expect(#toPlayer(p)).to.equal(0)

					veto.cloak = true
					listener(p, Modes.SPEED, Modes.ARMOR, GryMod.ModeReasons.PLAYER)
					expect(#toPlayer(p)).to.equal(1)
					listener(p, Modes.SPEED, Modes.ARMOR, GryMod.ModeReasons.API)
					expect(#toPlayer(p)).to.equal(1)

					listener(p, Modes.ARMOR, Modes.ARMOR, GryMod.ModeReasons.SPAWN)
					expect(#toPlayer(p)).to.equal(2)
				end)
			end
		},
		{
			-- fails without one of the four listeners (the mask is 0 while the suit is down or off, and the veto answers again afterwards)
			name = "the start and end of a malfunction and the suit going off or on push when the mask changed, and not otherwise",
			func = function()
				local p = ply()
				override(p, "Nanosuit_mode", Modes.ARMOR)
				override(p, "gryModesSent", 0)
				listenVeto()

				for _, event in ipairs({"GryMod_MalfunctionStart", "GryMod_MalfunctionEnd", "GryMod_SuitEnabled", "GryMod_SuitDisabled"}) do
					local listener = hook.GetTable()[event] and hook.GetTable()[event]["GRYMODESTATES"]
					expect(listener).to.beA("function")

					recorded(function()
						p.gryModesSent = 0
						veto.cloak = false
						listener(p)
						expect(#toPlayer(p)).to.equal(0) -- nothing changed

						veto.cloak = true
						listener(p)
						expect(#toPlayer(p)).to.equal(1)
						listener(p)
						expect(#toPlayer(p)).to.equal(1)
					end)
				end
			end
		},
		{
			-- fails if RefreshModeStates sends when nothing changed, or does not start the timer for a veto added late
			name = "GryMod.API.RefreshModeStates pushes when the mask changed, starts the timer when a veto exists, and refuses what is not a player",
			func = function()
				local p = ply()
				override(p, "Nanosuit_mode", Modes.ARMOR)
				override(p, "gryModesSent", 0)
				listenVeto()

				recorded(function()
					States.HasListeners, States.AnyAlive = function() return true end, function() return true end

					expect(GryMod.API.RefreshModeStates(p)).to.beTrue()
					expect(#toPlayer(p)).to.equal(0)
					expect(#timers.created).to.equal(1)

					veto.cloak = true
					expect(GryMod.API.RefreshModeStates(p)).to.beTrue()
					expect(#toPlayer(p)).to.equal(1)
					expect(GryMod.API.RefreshModeStates(p)).to.beTrue()
					expect(#toPlayer(p)).to.equal(1)
					expect(#timers.created).to.equal(1) -- it exists already

					local ok, why = GryMod.API.RefreshModeStates(NULL)
					expect(ok).to.beFalse()
					expect(why).to.equal("invalid player")
					expect(GryMod.API.RefreshModeStates("x")).to.beFalse()
				end)
			end
		},
		{
			-- fails without TimerWanted
			name = "the timer is wanted only while a veto exists and a player is alive",
			func = function()
				expect(States.TimerWanted(true, true)).to.beTrue()
				expect(States.TimerWanted(true, false)).to.beFalse()
				expect(States.TimerWanted(false, true)).to.beFalse()
				expect(States.TimerWanted(false, false)).to.beFalse()
				expect(States.TimerWanted(nil, true)).to.beFalse()
			end
		},
		{
			-- fails if the timer is permanent (made with no veto) or made twice, or not removed when the veto goes
			name = "Sync makes the timer (every 0.5 s, for ever) when it is wanted and absent, keeps it when it exists, removes it when it is not wanted",
			func = function()
				recorded(function()
					States.HasListeners, States.AnyAlive = function() return false end, function() return true end

					expect(States.Sync()).to.beFalse()
					expect(#timers.created).to.equal(0) -- no veto: no timer
					expect(timers.removed).to.equal(0)

					States.HasListeners = function() return true end
					expect(States.Sync()).to.beTrue()
					expect(#timers.created).to.equal(1)
					expect(timers.created[1].name).to.equal(States.TIMER)
					expect(timers.created[1].delay).to.equal(0.5)
					expect(timers.created[1].repetitions).to.equal(0)
					expect(timers.created[1].fn).to.equal(States.Tick)

					States.Sync()
					expect(#timers.created).to.equal(1)

					States.HasListeners = function() return false end
					expect(States.Sync()).to.beFalse()
					expect(timers.removed).to.equal(1)

					-- nobody alive: the same
					States.HasListeners, States.AnyAlive = function() return true end, function() return true end
					States.Sync()
					expect(timers.exists).to.beTrue()
					States.AnyAlive = function() return false end
					States.Sync()
					expect(timers.exists).to.beFalse()
				end)
			end
		},
		{
			-- fails if a tick sends to a player whose mask did not change, or never sends one that did
			name = "a tick tells only the players whose mask changed: one message when the veto turns on, none while it stays, one when it turns off",
			func = function()
				local p = ply()
				override(p, "Nanosuit_mode", Modes.ARMOR)
				override(p, "gryModesSent", 0)
				listenVeto()

				recorded(function()
					States.HasListeners, States.AnyAlive = function() return true end, function() return true end
					timers.exists = true

					States.Tick()
					expect(#toPlayer(p)).to.equal(0)

					veto.cloak = true
					States.Tick()
					expect(#toPlayer(p)).to.equal(1)
					expect(toPlayer(p)[1].value).to.equal(States.Pack({[Modes.CLOAK] = true}))
					States.Tick()
					States.Tick()
					expect(#toPlayer(p)).to.equal(1)

					veto.cloak = false
					States.Tick()
					expect(#toPlayer(p)).to.equal(2)
					expect(toPlayer(p)[2].value).to.equal(0)
				end)
			end
		},
		{
			-- fails if the tick keeps going with no veto left (a permanent cost for nothing)
			name = "a tick that finds no veto ends the timer and sends nothing, without asking any player",
			func = function()
				local p = ply()
				override(p, "gryModesSent", 0)
				local asked = 0

				recorded(function()
					States.HasListeners, States.AnyAlive = function() return false end, function() return true end
					timers.exists = true
					local mask = States.Mask

					States.Mask = function(who)
						asked = asked + 1

						return mask(who)
					end

					local ok, err = pcall(function()
						expect(States.Tick()).to.equal(0)
					end)

					States.Mask = mask

					if not ok then
						error(err, 0)
					end

					expect(timers.removed).to.equal(1)
					expect(#sent).to.equal(0)
					expect(asked).to.equal(0)
				end)
			end
		}
	}
}
