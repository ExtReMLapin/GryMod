-- The answer to the quick menu's question "which modes does a veto refuse right now?" (see sh_mode_states.lua).
--
-- The question comes when the menu opens and when the mode or the malfunction changes while it is open; an addon whose veto changed for another
-- reason calls GryMod.API.RefreshModeStates(ply). Each question asks every listener of GryMod_CanSetMode once per mode, so a listener must have no
-- side effect (docs/api.md). Nothing here runs on a timer or on a frame: a client that does not ask is never answered.

GryMod = GryMod or {}

local States = GryMod.ModeStates
local API = GryMod.API

if not States or not API then
	return -- sh_mode_states.lua and sh_api.lua are included first (grymod_shared.lua)
end

util.AddNetworkString("gry_modes_ask")
util.AddNetworkString("gry_modes_refused")

-- One answer per player and per interval (seconds): a client cannot make the server ask the veto without end.
States.AskInterval = 0.2

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

-- Sends the mask to the player, whenever it is asked.
function States.Push(ply)
	if not IsValid(ply) then
		return false
	end

	net.Start("gry_modes_refused")
	net.WriteUInt(States.Mask(ply), States.Bits)
	net.Send(ply)

	return true
end

-- The answer to the client's question. At most one per interval and per player: a question that comes too soon is not lost (the mode may just have
-- changed, and the client needs the new answer), it is answered once, when the interval is over, whatever the number of questions in between.
-- Returns true when it answered at once, false and "deferred" when it will answer later, false and "invalid player".
function States.Answer(ply)
	if not IsValid(ply) then
		return false, "invalid player"
	end

	local now = CurTime()
	local last = ply.gryModesAnswered

	if last and now - last < States.AskInterval then
		if not ply.gryModesPending then
			ply.gryModesPending = true

			timer.Simple(last + States.AskInterval - now, function()
				if IsValid(ply) then
					ply.gryModesPending = nil
					ply.gryModesAnswered = CurTime()
					States.Push(ply)
				end
			end)
		end

		return false, "deferred"
	end

	ply.gryModesAnswered = now
	States.Push(ply)

	return true
end

net.Receive("gry_modes_ask", function(len, ply)
	States.Answer(ply)
end)

-- For an addon: the veto of `ply` changed (a zone entered, a rule switched), tell the quick menu now. It only matters while the menu is open: a closed
-- menu asks again when it opens. Returns true, or false and why.
function API.RefreshModeStates(ply)
	if not (isentity(ply) and IsValid(ply) and ply:IsPlayer()) then
		return false, "invalid player"
	end

	States.Push(ply)

	return true
end
