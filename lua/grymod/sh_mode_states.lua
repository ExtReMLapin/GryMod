-- Which suit modes a veto refuses right now, as the server tells the quick menu (both realms read the same bits).
--
-- The veto hook GryMod_CanSetMode(ply, mode) is a function of the addon that owns it: the client cannot know its answer. The quick menu asks the
-- server when it opens (and again when the mode or the malfunction changes while it is open), the server asks the veto once per mode and answers with
-- a small mask. Nothing runs on a timer or on every frame (sv_mode_states.lua, cl_hud_quickmenu_flash.lua).

GryMod = GryMod or {}

local Modes = GryMod.Modes

local States = {}
GryMod.ModeStates = States

-- The modes a veto can refuse, one bit each, in this order. The armor is never refused (it is the suit's safe state, see Player:SetNanosuitMode) and
-- dropping the weapon is not a mode. ONLY ADD AT THE END: the bits are the wire format.
States.Order = {Modes.SPEED, Modes.CLOAK, Modes.STRENGTH}
States.Bits = #States.Order

-- A table keyed by mode (true = refused) as a number.
function States.Pack(refused)
	local mask = 0

	for i, mode in ipairs(States.Order) do
		if refused and refused[mode] then
			mask = bit.bor(mask, bit.lshift(1, i - 1))
		end
	end

	return mask
end

-- The number as a table keyed by mode (true = refused). `into` (optional) is emptied and filled, so a caller that reads it often makes no garbage.
function States.Unpack(mask, into)
	into = into or {}
	mask = tonumber(mask) or 0

	for i, mode in ipairs(States.Order) do
		into[mode] = bit.band(mask, bit.lshift(1, i - 1)) ~= 0 or nil
	end

	return into
end
