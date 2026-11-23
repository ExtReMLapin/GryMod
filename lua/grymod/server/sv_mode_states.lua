-- Tells each client which suit modes a veto refuses right now (see sh_mode_states.lua), so that the quick menu opens at once with the answer
-- already there. The CLIENT NEVER ASKS: the server pushes the mask (3 bits, gry_modes_refused) and the client keeps the last one.
--
-- When a push is sent:
--  * a client that is ready (GryMod.AnswerReady) and at every spawn: always, the client may have nothing;
--  * when something GryMod knows changes (the mode, the malfunction, the suit on or off, from the reporting hooks): only if the mask changed;
--  * when an addon calls GryMod.API.RefreshModeStates(ply): only if the mask changed. This is THE way for the owner of a veto to say "my
--    condition changed", and also what starts the timer below if the veto was added after the players spawned;
--  * from a timer, because a veto is any function of any addon's state and GryMod cannot see it change. The timer (every 0.5 s) exists only while
--    at least one listener of GryMod_CanSetMode exists and at least one player is alive: Sync creates it when both are true and removes it when
--    not, and a tick that finds them false removes it. It sends a push only to the players whose mask changed. With no veto nothing runs at all.
-- Cost of the timer: a tick asks the listeners once per mode the suit can change to, for each living player: 2 or 3 calls of the hook (every
-- listener of it runs each time), so at most 3 x 2 = 6 calls of the hook a second for each living player, and one small message per real change.

GryMod = GryMod or {}

local States = GryMod.ModeStates
local API = GryMod.API

if not States or not API then
	return -- sh_mode_states.lua and sh_api.lua are included first (grymod_shared.lua)
end

util.AddNetworkString("gry_modes_refused")

States.TIMER = "GryModeStates"
States.TICK_SECONDS = 0.5

-- The mask of the modes refused, from the facts and the question (a pure rule, tested alone). `current` is the mode the suit is in (never asked: the
-- veto only runs for a change), `blocked` is true when the suit is down or off (the modes are not chosen at all then, and the veto is not asked
-- either: Player:SetNanosuitMode answers before it), `refuses(mode)` says whether the veto refuses that mode.
function States.MaskFor(current, blocked, refuses)
	if blocked then
		return 0
	end

	local refused = {}

	for _, mode in ipairs(States.Order) do
		if mode ~= current and refuses(mode) then
			refused[mode] = true
		end
	end

	return States.Pack(refused)
end

-- The question put to the listeners, the way Player:SetNanosuitMode puts it. A listener that fails does not refuse (its error is shown).
local function askVeto(ply)
	return function(mode)
		local ok, answer = pcall(hook.Run, "GryMod_CanSetMode", ply, mode)

		if not ok then
			ErrorNoHalt("[GryMod] GryMod_CanSetMode listener: " .. tostring(answer) .. "\n")

			return false
		end

		return answer == false
	end
end

-- The mask for a player now (0 for a player who is not alive).
function States.Mask(ply)
	if not IsValid(ply) or not ply:Alive() then
		return 0
	end

	local blocked = ply:GetNW2Bool("GryMalfunction", false) or ply:GetNW2Bool("GryDisabled", false)

	return States.MaskFor(ply.Nanosuit_mode or GryMod.Modes.ARMOR, blocked, askVeto(ply))
end

-- Sends the mask to the player whatever he has, and remembers it as what he knows. Returns false for a player who is not valid.
function States.Push(ply)
	if not IsValid(ply) then
		return false
	end

	local mask = States.Mask(ply)
	ply.gryModesSent = mask

	net.Start("gry_modes_refused")
	net.WriteUInt(mask, States.Bits)
	net.Send(ply)

	return true
end

-- Sends the mask only if it is not what the player was last told (a client starts with no mode refused). Returns true when it sent.
function States.PushIfChanged(ply)
	if not IsValid(ply) or States.Mask(ply) == (ply.gryModesSent or 0) then
		return false
	end

	return States.Push(ply)
end

-- ---------------------------------------------------------------------------------------------------------
-- The timer that follows the vetoes
-- ---------------------------------------------------------------------------------------------------------

-- Whether any listener of the veto exists (replaceable: the tests).
function States.HasListeners()
	local listeners = hook.GetTable().GryMod_CanSetMode

	return listeners ~= nil and next(listeners) ~= nil
end

-- Whether at least one player is alive (replaceable: the tests).
function States.AnyAlive()
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() then
			return true
		end
	end

	return false
end

-- The rule: the timer is wanted while a veto exists and someone is alive.
function States.TimerWanted(listeners, anyAlive)
	return listeners == true and anyAlive == true
end

-- Creates the timer when it is wanted and absent, removes it when it is not wanted and there. Returns whether it is wanted.
function States.Sync()
	local wanted = States.TimerWanted(States.HasListeners(), States.AnyAlive())
	local exists = timer.Exists(States.TIMER)

	if wanted and not exists then
		timer.Create(States.TIMER, States.TICK_SECONDS, 0, States.Tick)
	elseif not wanted and exists then
		timer.Remove(States.TIMER)
	end

	return wanted
end

-- One tick: the players whose mask changed are told. A tick that finds no veto or nobody alive ends the timer. Returns how many it told.
function States.Tick()
	if not States.Sync() then
		return 0
	end

	local sent = 0

	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and States.PushIfChanged(ply) then
			sent = sent + 1
		end
	end

	return sent
end

-- ---------------------------------------------------------------------------------------------------------
-- The triggers: the reports GryMod already makes
-- ---------------------------------------------------------------------------------------------------------

-- The mode changed, and every respawn (the report also comes with the cause "spawn": a new life, the client may hold what the last one left).
hook.Add("GryMod_ModeChanged", "GRYMODESTATES", function(ply, mode, oldMode, reason)
	if reason == GryMod.ModeReasons.SPAWN then
		States.Push(ply)
		States.Sync()
	else
		States.PushIfChanged(ply)
	end
end)

-- The suit goes down or comes back, is switched off or on: the mask is 0 while it is blocked, and the veto answers again afterwards.
local function changed(ply)
	States.PushIfChanged(ply)
end

hook.Add("GryMod_MalfunctionStart", "GRYMODESTATES", changed)
hook.Add("GryMod_MalfunctionEnd", "GRYMODESTATES", changed)
hook.Add("GryMod_SuitEnabled", "GRYMODESTATES", changed)
hook.Add("GryMod_SuitDisabled", "GRYMODESTATES", changed)

-- For an addon: the veto of `ply` changed (a zone entered, a rule switched), or it added its listener after the players spawned. The mask is
-- evaluated now and sent if it differs from what the client knows; the follow-up timer starts if a veto exists. Returns true, or false and why.
function API.RefreshModeStates(ply)
	if not (isentity(ply) and IsValid(ply) and ply:IsPlayer()) then
		return false, "invalid player"
	end

	States.PushIfChanged(ply)
	States.Sync()

	return true
end
