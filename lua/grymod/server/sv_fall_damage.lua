-- Realistic fall damage, kept between two launches of the game.
--
-- How a fall reaches the suit: the engine asks `GM:GetFallDamage(ply, speed)` when a player lands faster than 526.5 units a second (the hooks of the addons
-- first, then the gamemode) and applies the answer as damage of the type DMG_FALL from the world. The armor (sv_health.lua) sees that damage like any
-- other and pays it from the bar: GryMod needs no code of its own for the fall, and the answer of every addon that changes the fall damage reaches the armor,
-- whatever the order of the addons (docs/compat.md).
--
-- The gamemode's answer is 10 for every fall, whatever the height, unless the game's setting `mp_falldamage` is on ("realistic fall damage" of the sandbox's
-- server settings): then it is (speed - 526.5) * 100 / 396, the Source SDK's rule. That setting is not saved: the game puts it back to 0 at every launch.
-- gry_realistic_fall (saved, an administrator's setting of the options panel) turns it on at every launch and when it is changed. It is off by default: the
-- game keeps its own behaviour.
--
-- It sets the game's setting and nothing else: it adds no GetFallDamage hook, so that an addon that answers the fall (a roll that cancels it, water, a lethal
-- height) keeps its own answer, whatever the order of the hooks. GryMod only takes the setting back (off) when it was GryMod that turned it on.

GryMod = GryMod or {}

local FD = GryMod.FallDamage or {}
GryMod.FallDamage = FD

local Wanted = CreateConVar("gry_realistic_fall", "0", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"Turn the game's realistic fall damage (mp_falldamage) on at every launch: the fall hurts by its speed (10 whatever the height otherwise). The suit's armor takes the fall as any other damage")

-- true when GryMod turned the game's setting on (and so takes it back)
FD.Owned = FD.Owned or false

function FD.EngineOn()
	local convar = GetConVar("mp_falldamage")

	return convar ~= nil and convar:GetBool()
end

-- The game's convar cannot be written by Lua (a command of the console, run at the end of the frame)
function FD.SetEngine(on)
	RunConsoleCommand("mp_falldamage", on and "1" or "0")
end

-- Puts the game's setting in agreement with the wanted state (the setting's own value when none is given). On: turned on if it is not. Off: turned off only if
-- GryMod turned it on, so that the checkbox of the sandbox, a server's config or an administrator who set it before stays as it is.
function FD.Sync(wanted)
	if wanted == nil then
		wanted = Wanted:GetBool()
	end

	if wanted then
		if not FD.EngineOn() then
			FD.SetEngine(true)
			FD.Owned = true
		end
	elseif FD.Owned then
		FD.Owned = false
		FD.SetEngine(false)
	end
end

cvars.AddChangeCallback("gry_realistic_fall", function(_, _, new)
	FD.Sync(tonumber(new) ~= nil and tonumber(new) ~= 0)
end, "GryMod fall damage")

-- at the launch: the game's setting is back to 0 (the engine's convars are read once the map is there)
hook.Add("InitPostEntity", "GryMod fall damage", function()
	FD.Sync()
end)
