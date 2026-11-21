-- Tests of the cancel of a weapon's zoom (GryMod.WeaponZoom, sv_weapon_zoom.lua), GLuaTest format, server realm. The crossbow's right
-- click zooms (the weapon asks the engine for a field of view of 20 and OWNS the zoom: Player m_hZoomOwner is the weapon); the binoculars
-- of the suit (the own zoom or the Half-Life 2 key) are a view of their own, and when they closed the engine's field of view was the
-- crossbow's again, a jump (measured on a test client: 61.6 eased to 100, then 20 after 0.6 s). The client asks the server to end the
-- weapon's zoom when the binoculars open (gry_cancel_weapon_zoom, no payload); the server decides from what it knows: a white list of
-- weapons, the player alive, the zoom really owned by that weapon. Measured: Player:SetFOV(0, 0.1) alone does NOT release a zoom owned
-- by a weapon, only with the weapon as the requester; and the crossbow's own state (m_bInZoom, not readable from Lua) is put right by
-- a one tick IN_ATTACK2 in the player's command (the weapon toggles itself off), not by SetFOV. Fake players for the rules; the real
-- engine for the ownership contract.

local function weapon(class)
	return {IsValid = function() return true end, GetClass = function() return class end}
end

-- a player as far as the module looks: alive, an active weapon, who owns the zoom
local function fakePlayer(fields)
	local p = {
		alive = true,
		active = nil,
		owner = nil,
		fovCalls = {}
	}

	for k, v in pairs(fields or {}) do
		p[k] = v
	end

	p.IsValid = function() return p.valid ~= false end
	p.Alive = function() return p.alive end
	p.GetActiveWeapon = function() return p.active end
	p.GetInternalVariable = function(_, name)
		if name == "m_hZoomOwner" then
			return p.owner
		end

		return nil
	end
	p.SetFOV = function(_, fov, time, requester)
		p.fovCalls[#p.fovCalls + 1] = {fov, time, requester}
	end

	return p
end

local function fakeCmd(buttons)
	local cmd = {buttons = buttons or 0}
	cmd.GetButtons = function() return cmd.buttons end
	cmd.SetButtons = function(_, value) cmd.buttons = value end

	return cmd
end

-- a scheduler that keeps what it is asked and runs it when the test says
local function scheduler()
	local s = {jobs = {}}
	s.at = function(delay, fn) s.jobs[#s.jobs + 1] = {delay = delay, fn = fn} end
	s.run = function() for _, j in ipairs(s.jobs) do j.fn() end s.jobs = {} end

	return s
end

local function ply1()
	return player.GetAll()[1]
end

return {
	groupName = "GryMod weapon zoom cancel (server)",
	beforeEach = function()
		GryMod.WeaponZoom.Reset()
	end,
	afterEach = function()
		GryMod.WeaponZoom.Reset()

		for _, class in ipairs({"doc_test_zoom_gun", "doc_test_grenade_gun"}) do
			GryMod.API.UnregisterWeapon(class)
		end
	end,
	cases = {
		{
			name = "the module, its net message and its receiver exist; the weapon registry says that the crossbow zooms (alt = zoom) and there is no private list",
			func = function()
				local W = GryMod.WeaponZoom
				expect(W ~= nil).to.beTrue()
				expect(util.NetworkStringToID("gry_cancel_weapon_zoom") ~= 0).to.beTrue()
				expect(net.Receivers["gry_cancel_weapon_zoom"] ~= nil).to.beTrue()
				expect(GryMod.API.WeaponValue("weapon_crossbow", "alt", true)).to.equal("zoom")
				expect(W.Weapons).to.beNil()
			end
		},
		{
			name = "a third-party weapon registered through the API with alt = zoom is treated like the crossbow (marked, IN_ATTACK2 once, safety net); one with another alt is not",
			func = function()
				local W = GryMod.WeaponZoom
				local API = GryMod.API

				-- (rouge before the migration: the private list knew only the crossbow)
				local before = weapon("doc_test_zoom_gun")
				expect(W.Zoomer(fakePlayer({active = before, owner = before})) == nil).to.beTrue()

				expect((API.RegisterWeapon("doc_test_zoom_gun", {fire = "semi", alt = "zoom", altShoots = false}))).to.beTrue()
				expect((API.RegisterWeapon("doc_test_grenade_gun", {fire = "auto", alt = "grenade", altAmmo = "SMG1_Grenade"}))).to.beTrue()

				local gun = weapon("doc_test_zoom_gun")
				local p = fakePlayer({active = gun, owner = gun})
				local sched = scheduler()

				expect(W.Zoomer(p) == gun).to.beTrue()
				expect(W.Handle(p, 100, sched.at)).to.beTrue()
				expect(#sched.jobs).to.equal(1)

				local cmd = fakeCmd(0)
				W.Command(p, cmd)
				expect(bit.band(cmd.buttons, IN_ATTACK2) ~= 0).to.beTrue()

				-- the safety net releases the zoom of the weapon when the command did not
				local p2 = fakePlayer({active = gun, owner = gun})
				local sched2 = scheduler()
				expect(W.Handle(p2, 100, sched2.at)).to.beTrue()
				sched2.run()
				expect(#p2.fovCalls).to.equal(1)
				expect(p2.fovCalls[1][3] == gun).to.beTrue()

				-- another kind of secondary fire: not ours
				local other = weapon("doc_test_grenade_gun")
				local p3 = fakePlayer({active = other, owner = other})
				expect(W.Zoomer(p3) == nil).to.beTrue()
				expect(W.Handle(p3, 100, scheduler().at)).to.beFalse()
			end
		},
		{
			name = "a crossbow that owns the zoom: the request marks the player, the next command carries IN_ATTACK2 once (the weapon toggles itself off), the one after carries nothing",
			func = function()
				local W = GryMod.WeaponZoom
				local xbow = weapon("weapon_crossbow")
				local p = fakePlayer({active = xbow, owner = xbow})
				local sched = scheduler()

				expect(W.Handle(p, 100, sched.at)).to.beTrue()

				local first = fakeCmd(IN_FORWARD)
				W.Command(p, first)
				expect(bit.band(first.buttons, IN_ATTACK2) ~= 0).to.beTrue()
				-- (what the player held is kept)
				expect(bit.band(first.buttons, IN_FORWARD) ~= 0).to.beTrue()

				local second = fakeCmd(0)
				W.Command(p, second)
				expect(second.buttons).to.equal(0)
			end
		},
		{
			name = "nothing is marked and nothing is injected for a weapon that is not on the white list, even when it owns the zoom",
			func = function()
				local W = GryMod.WeaponZoom
				local other = weapon("weapon_ar2")
				local p = fakePlayer({active = other, owner = other})
				local sched = scheduler()

				expect(W.Handle(p, 100, sched.at)).to.beFalse()
				expect(#sched.jobs).to.equal(0)

				local cmd = fakeCmd(0)
				W.Command(p, cmd)
				expect(cmd.buttons).to.equal(0)
			end
		},
		{
			name = "nothing for a crossbow that does not own the zoom: no zoom at all, or the suit's (the player owns it): an IN_ATTACK2 there would ZOOM the weapon",
			func = function()
				local W = GryMod.WeaponZoom
				local xbow = weapon("weapon_crossbow")
				local sched = scheduler()

				local idle = fakePlayer({active = xbow, owner = nil})
				expect(W.Handle(idle, 100, sched.at)).to.beFalse()

				local suit = fakePlayer({active = xbow, owner = {IsValid = function() return true end}})
				expect(W.Handle(suit, 100, sched.at)).to.beFalse()

				-- (the zoom is owned by a weapon in the player's hands that is not the active one: not ours to touch)
				local held = fakePlayer({active = xbow, owner = weapon("weapon_crossbow")})
				expect(W.Handle(held, 100, sched.at)).to.beFalse()

				expect(#sched.jobs).to.equal(0)
			end
		},
		{
			name = "a dead or invalid player, or one with no weapon in hand, gets nothing",
			func = function()
				local W = GryMod.WeaponZoom
				local xbow = weapon("weapon_crossbow")
				local sched = scheduler()

				expect(W.Handle(fakePlayer({active = xbow, owner = xbow, alive = false}), 100, sched.at)).to.beFalse()
				expect(W.Handle(fakePlayer({active = xbow, owner = xbow, valid = false}), 100, sched.at)).to.beFalse()
				expect(W.Handle(fakePlayer({active = nil, owner = xbow}), 100, sched.at)).to.beFalse()
				expect(W.Handle(nil, 100, sched.at)).to.beFalse()
				expect(#sched.jobs).to.equal(0)
			end
		},
		{
			name = "a player who dies or changes weapon between the request and the command is not touched",
			func = function()
				local W = GryMod.WeaponZoom
				local xbow = weapon("weapon_crossbow")
				local p = fakePlayer({active = xbow, owner = xbow})
				local sched = scheduler()

				expect(W.Handle(p, 100, sched.at)).to.beTrue()
				p.alive = false

				local cmd = fakeCmd(0)
				W.Command(p, cmd)
				expect(cmd.buttons).to.equal(0)

				local q = fakePlayer({active = xbow, owner = xbow})
				expect(W.Handle(q, 100, sched.at)).to.beTrue()
				q.active, q.owner = weapon("weapon_physcannon"), nil

				local cmd2 = fakeCmd(0)
				W.Command(q, cmd2)
				expect(cmd2.buttons).to.equal(0)
			end
		},
		{
			name = "rate limit: five requests a second for a player, the sixth is ignored, a new second allows again, and another player has his own count",
			func = function()
				local W = GryMod.WeaponZoom
				local xbow = weapon("weapon_crossbow")
				local a = fakePlayer({active = xbow, owner = xbow})
				local b = fakePlayer({active = xbow, owner = xbow})
				local sched = scheduler()
				local accepted = 0

				for i = 1, 8 do
					if W.Handle(a, 200 + i * 0.01, sched.at) then
						accepted = accepted + 1
					end
				end

				expect(accepted).to.equal(5)
				expect(W.Handle(a, 201.5, sched.at)).to.beTrue()
				expect(W.Handle(b, 200.05, sched.at)).to.beTrue()
			end
		},
		{
			name = "the safety net: when the command never came (or the weapon was not ready: its next secondary attack is later) and the weapon still owns the zoom a moment later, the player's field of view is released with the weapon as the requester; when the zoom is gone nothing is done",
			func = function()
				local W = GryMod.WeaponZoom
				local xbow = weapon("weapon_crossbow")
				local p = fakePlayer({active = xbow, owner = xbow})
				local sched = scheduler()

				expect(W.Handle(p, 100, sched.at)).to.beTrue()
				expect(#sched.jobs).to.equal(1)
				expect(sched.jobs[1].delay).to.equal(W.FALLBACK_DELAY)

				sched.run()
				expect(#p.fovCalls).to.equal(1)
				expect(p.fovCalls[1][1]).to.equal(0)
				expect(p.fovCalls[1][2]).to.equal(0.1)
				expect(p.fovCalls[1][3] == xbow).to.beTrue()

				-- the command did its work: the weapon let go of the zoom, nothing left to do
				local q = fakePlayer({active = xbow, owner = xbow})
				expect(W.Handle(q, 300, sched.at)).to.beTrue()
				W.Command(q, fakeCmd(0))
				q.owner = nil
				sched.run()
				expect(#q.fovCalls).to.equal(0)
			end
		},
		{
			name = "the player leaving clears what was waiting for him",
			func = function()
				local W = GryMod.WeaponZoom
				local xbow = weapon("weapon_crossbow")
				local p = fakePlayer({active = xbow, owner = xbow})
				local sched = scheduler()

				expect(W.Handle(p, 100, sched.at)).to.beTrue()
				W.Forget(p)

				local cmd = fakeCmd(0)
				W.Command(p, cmd)
				expect(cmd.buttons).to.equal(0)
			end
		},
		{
			name = "engine contract (real player, real crossbow): the weapon owns a zoom it asked for, Player:SetFOV(0, t) without a requester does NOT release it, with the weapon it does, and the module sees the ownership",
			func = function()
				local W = GryMod.WeaponZoom
				local p = ply1()

				if not p:Alive() then p:Spawn() end

				p:Give("weapon_crossbow")
				p:SelectWeapon("weapon_crossbow")

				local xbow = p:GetWeapon("weapon_crossbow")
				expect(IsValid(xbow)).to.beTrue()

				-- (SelectWeapon takes effect on the next tick: the module looks at the active weapon, so make it so for this case)
				local before = p:GetActiveWeapon()
				p:SetActiveWeapon(xbow)

				-- (a zoom left by an earlier test or by the player: let every weapon he has release it)
				for _, w in ipairs(p:GetWeapons()) do
					p:SetFOV(0, 0, w)
				end

				local ok, err = pcall(function()
					expect(W.Zoomer(p) == nil).to.beTrue()

					p:SetFOV(20, 0.1, xbow)
					expect(W.Zoomer(p) == xbow).to.beTrue()

					p:SetFOV(0, 0.1)
					expect(W.Zoomer(p) == xbow).to.beTrue()

					p:SetFOV(0, 0.1, xbow)
					expect(W.Zoomer(p) == nil).to.beTrue()
				end)

				p:SetFOV(0, 0, xbow)
				p:SetActiveWeapon(before)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the real fallback on the real player: the zoom the crossbow owns is released by W.Fallback",
			func = function()
				local W = GryMod.WeaponZoom
				local p = ply1()

				if not p:Alive() then p:Spawn() end

				p:Give("weapon_crossbow")
				p:SelectWeapon("weapon_crossbow")

				local xbow = p:GetWeapon("weapon_crossbow")
				local before = p:GetActiveWeapon()
				p:SetActiveWeapon(xbow)

				local ok, err = pcall(function()
					p:SetFOV(20, 0.1, xbow)
					expect(W.Zoomer(p) == xbow).to.beTrue()

					W.Fallback(p, xbow)
					expect(W.Zoomer(p) == nil).to.beTrue()
				end)

				p:SetFOV(0, 0, xbow)
				p:SetActiveWeapon(before)

				if not ok then
					error(err, 0)
				end
			end
		}
	}
}
