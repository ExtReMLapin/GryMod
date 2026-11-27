-- The stock melee weapons of Garry's Mod (server): what the suit's strength and speed modes do to the crowbar, the stun baton and the fists, with the rules of
-- lua/grymod/sh_suit_weapons.lua. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md); the decoration of the fists' own code is in sh_melee_suit.lua, which
-- also names the three classes.
--   * Strength mode, damage and push: a hit whose inflictor is one of these weapons, held by a player, is multiplied (x9.2 with a full bar). It is read in EntityTakeDamage, so
--     the bullets and every other damage of the same player are left alone.
--   * The price of a blow (20 of the bar in the strength mode, 10 in the speed mode) is taken when the blow STARTS, so that the energy that is left decides how hard it hits.
--   * Speed mode, the blow 1.5 times quicker and the draw 1.75 times: the crowbar and the stun baton are written in C++, so their next fire time and their view model's rate are
--     set from outside, one command after the blow starts.
--
-- The two engine weapons have no event for the start of a blow, and a held click makes a blow every cooldown (the price follows the blows, not the key presses). The only
-- place that sees the key and the weapon's next fire time together, before the engine runs the weapon, is the player's command (StartCommand): a blow starts in a command that
-- has the attack key down while the weapon's next fire time is not ahead (the engine's own rule, CBaseHLBludgeonWeapon::ItemPostFrame). That hook costs something for every
-- command of every player, so it is NOT permanent: it is added when a crowbar or a stun baton comes into a player's hand (PlayerSwitchWeapon, an event) and removed when no
-- player holds one. The right click of these two weapons does nothing in the game (measured), so only the attack key is watched.
-- The server alone does this: the weapon's times are networked, and the client takes the server's.

local API = GryMod.API
local SW = GryMod.SuitWeapons
local SM = GryMod.StockMelee

if not API or not SW or not SM then
	return -- sv_api.lua, sh_suit_weapons.lua and sh_melee_suit.lua are included first (grymod_shared.lua)
end

local KEY = "GryMod compat stock melee"

-- ---------------------------------------------------------------------------------------------------------
-- Damage and push
-- ---------------------------------------------------------------------------------------------------------

hook.Add("EntityTakeDamage", KEY, function(_, info)
	pcall(function()
		local weapon = info:GetInflictor()

		if not isentity(weapon) and not istable(weapon) then
			return
		end

		if not weapon.IsValid or not weapon:IsValid() or not SM.Kind(weapon:GetClass()) then
			return
		end

		local ply = SW.HolderOf(weapon)

		if not ply then
			return
		end

		local scale = SW.MeleeScale(SW.ModeOf(ply), SW.EnergyOf(ply))

		if scale > 1 then
			info:ScaleDamage(scale)
			info:SetDamageForce(info:GetDamageForce() * scale)
		end
	end)

	return nil -- the hit goes on as it was (this only changes its numbers)
end)

-- ---------------------------------------------------------------------------------------------------------
-- The price of a blow
-- ---------------------------------------------------------------------------------------------------------

-- Never under 0, nothing while the armor is infinite (the energy API keeps the bar in its range).
function SM.PayBlow(ply)
	if GryMod.Config.InfiniteArmor then
		return
	end

	local cost = SW.MeleeCost(SW.ModeOf(ply))

	if cost > 0 then
		API.AddEnergy(ply, -cost)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- The crowbar and the stun baton: the blow and the draw, seen from the player's commands
-- ---------------------------------------------------------------------------------------------------------

local tracked = {} -- player -> {pending = {t, rate, weapon}}
local count = 0

local function onCommand(ply, cmd)
	local ok, err = pcall(SM.OnCommand, ply, cmd)

	if not ok then
		ErrorNoHalt("GryMod stock melee: " .. tostring(err) .. "\n")
	end
end

function SM.Tracked()
	return count
end

function SM.Track(ply)
	if not tracked[ply] then
		tracked[ply] = {}
		count = count + 1
	end

	hook.Add("StartCommand", KEY, onCommand)
end

function SM.Untrack(ply)
	if tracked[ply] then
		tracked[ply] = nil
		count = count - 1
	end

	if count <= 0 then
		count = 0
		hook.Remove("StartCommand", KEY)
	end
end

-- The times that are still ahead of `start` go `rate` times faster, and so does the view model's animation (a new animation starts at the rate of 1, so this does not pile up).
local function settle(ply, weapon, pending)
	for _, name in ipairs({"NextPrimaryFire", "NextSecondaryFire"}) do
		local t = weapon["Get" .. name](weapon)

		if t > pending.t then
			weapon["Set" .. name](weapon, pending.t + (t - pending.t) / pending.rate)
		end
	end

	local vm = ply:GetViewModel()

	if IsValid(vm) then
		vm:SetPlaybackRate(vm:GetPlaybackRate() * pending.rate)
	end
end

-- One command of a tracked player. `weapon` and `now` are for the tests; the game gives neither (the weapon in hand, the time of the command).
function SM.OnCommand(ply, cmd, weapon, now)
	local state = tracked[ply]

	if not state then
		return
	end

	weapon = weapon or ply:GetActiveWeapon()

	if not IsValid(weapon) or SM.Kind(weapon:GetClass()) ~= "engine" or not ply:Alive() then
		SM.Untrack(ply) -- put away, dead, stripped: the way out of a weapon that has no switch event

		return
	end

	now = now or CurTime()

	-- the blow (or the draw) that started in the command before: the weapon has its times now
	local pending = state.pending

	state.pending = nil

	if pending and pending.weapon == weapon then
		settle(ply, weapon, pending)
	end

	-- a blow starts in this command: the key is down and the weapon may attack (the engine's rule)
	if bit.band(cmd:GetButtons(), IN_ATTACK) ~= 0 and weapon:GetNextPrimaryFire() <= now then
		SM.PayBlow(ply)

		local rate = SW.Rate(SW.ModeOf(ply), "melee")

		if rate ~= 1 then
			state.pending = {t = now, rate = rate, weapon = weapon}
		end
	end
end

-- A player changes weapon (an event, with the weapon he takes in his hands). `now` is for the tests.
function SM.OnSwitch(ply, old, new, now)
	if IsValid(new) and SM.Kind(new:GetClass()) == "engine" then
		SM.Track(ply)

		local rate = SW.Rate(SW.ModeOf(ply), "draw")

		if rate ~= 1 then
			tracked[ply].pending = {t = now or CurTime(), rate = rate, weapon = new}
		end
	else
		SM.Untrack(ply)
	end
end

hook.Add("PlayerSwitchWeapon", KEY, function(ply, old, new)
	pcall(SM.OnSwitch, ply, old, new)

	return nil -- the switch goes on
end)

hook.Add("PlayerDisconnected", KEY, function(ply)
	SM.Untrack(ply)
end)

-- A player who already holds one when this file runs (a hot reload).
for _, ply in ipairs(player.GetAll()) do
	local weapon = ply:GetActiveWeapon()

	if IsValid(weapon) and SM.Kind(weapon:GetClass()) == "engine" then
		SM.Track(ply)
	end
end
