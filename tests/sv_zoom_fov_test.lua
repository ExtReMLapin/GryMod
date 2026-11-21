-- Tests of the field of view that follows the own zoom (GryMod.ZoomFov, sv_zoom_fov.lua), GLuaTest format, server realm. The binoculars of
-- the own zoom (the key of the suit mod, H by default) only give the VIEW another field of view (CalcView): the engine's field of view
-- of the player (m_iFOV) stays at his normal one, and the engine scales the fade distances and the details of the world with THAT one
-- (measured in the game, d2_coast_07: the windows of a far house have their panes with Player:SetFOV(20) and are flat rectangles with
-- only a CalcView of 20; the models' own level of detail follows the rendered field of view in both cases). So the client tells the
-- server the field of view of its stage (gry_zoom_fov, one float, 0 = back to normal) and the server sets the player's field of view
-- to it (Player:SetFOV is shared and has no effect when called on the client only). The server decides from what it knows: a living
-- player, a number in the range the player may have, no weapon holding the zoom, 10 requests a second at most; a request that does not
-- come again (a client that died) is ended after a few seconds. Fake players for the rules; the real engine for the contract.

-- a player as far as the module looks: alive, the normal field of view he chose, who owns the zoom
local function fakePlayer(fields)
	local p = {
		alive = true,
		default = 100,
		owner = nil,
		fovCalls = {}
	}

	for k, v in pairs(fields or {}) do
		p[k] = v
	end

	p.IsValid = function() return p.valid ~= false end
	p.Alive = function() return p.alive end
	p.GetInfoNum = function(_, name, fallback)
		if name == "fov_desired" then
			return p.default
		end

		return fallback
	end
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

local function ply1()
	return player.GetAll()[1]
end

return {
	groupName = "GryMod zoom field of view (server)",
	beforeEach = function()
		GryMod.ZoomFov.Reset()
	end,
	afterEach = function()
		GryMod.ZoomFov.Reset()
	end,
	cases = {
		{
			name = "the module, its net message and its receiver exist; the limits are what the doc says",
			func = function()
				local Z = GryMod.ZoomFov
				expect(Z ~= nil).to.beTrue()
				expect(util.NetworkStringToID("gry_zoom_fov") ~= 0).to.beTrue()
				expect(net.Receivers["gry_zoom_fov"] ~= nil).to.beTrue()
				expect(Z.MIN_FOV).to.equal(5)
				expect(Z.TRANSITION).to.equal(0.1)
				expect(Z.TIMEOUT).to.equal(3)
				expect(Z.LIMIT).to.equal(10)
				expect(Z.WINDOW).to.equal(1)
			end
		},
		{
			name = "a field of view below the normal one is set on the player with the short transition, and remembered",
			func = function()
				local Z = GryMod.ZoomFov
				local p = fakePlayer()

				expect(Z.Handle(p, 33.2, 100)).to.equal("set")
				expect(#p.fovCalls).to.equal(1)
				expect(p.fovCalls[1][1]).to.equal(33.2)
				expect(p.fovCalls[1][2]).to.equal(Z.TRANSITION)
				expect(Z.Held(p)).to.equal(33.2)
			end
		},
		{
			name = "the same field of view again (the client's heartbeat) does not call the engine again, a different one does",
			func = function()
				local Z = GryMod.ZoomFov
				local p = fakePlayer()

				Z.Handle(p, 61.6, 100)
				expect(Z.Handle(p, 61.6, 101)).to.equal("held")
				expect(#p.fovCalls).to.equal(1)

				expect(Z.Handle(p, 33.2, 101.2)).to.equal("set")
				expect(#p.fovCalls).to.equal(2)
				expect(p.fovCalls[2][1]).to.equal(33.2)
				expect(Z.Held(p)).to.equal(33.2)
			end
		},
		{
			name = "0 gives the player's field of view back, once, and only when this module had set one (a zoom of a weapon is not touched)",
			func = function()
				local Z = GryMod.ZoomFov
				local p = fakePlayer()

				expect(Z.Handle(p, 0, 100)).to.beFalse()
				expect(#p.fovCalls).to.equal(0)

				Z.Handle(p, 33.2, 101)
				expect(Z.Handle(p, 0, 102)).to.equal("release")
				expect(#p.fovCalls).to.equal(2)
				expect(p.fovCalls[2][1]).to.equal(0)
				expect(p.fovCalls[2][2]).to.equal(Z.TRANSITION)
				expect(Z.Held(p)).to.beNil()

				expect(Z.Handle(p, 0, 103)).to.beFalse()
				expect(#p.fovCalls).to.equal(2)
			end
		},
		{
			name = "a field of view that is not below the normal one is a release (nothing to zoom), and one that is too small is raised to the minimum",
			func = function()
				local Z = GryMod.ZoomFov
				local p = fakePlayer({default = 90})

				Z.Handle(p, 40, 100)
				expect(Z.Handle(p, 90, 101)).to.equal("release")
				expect(Z.Held(p)).to.beNil()

				expect(Z.Handle(p, 120, 102)).to.beFalse()
				expect(#p.fovCalls).to.equal(2)

				expect(Z.Handle(p, 1, 103)).to.equal("set")
				expect(p.fovCalls[3][1]).to.equal(Z.MIN_FOV)
			end
		},
		{
			name = "values that are not a usable number are ignored: nothing is set, nothing is released, what was held stays",
			func = function()
				local Z = GryMod.ZoomFov
				local p = fakePlayer()

				Z.Handle(p, 40, 100)

				for i, bad in ipairs({"33", 0 / 0, math.huge, -math.huge, -5, {}, true}) do
					expect(Z.Handle(p, bad, 100 + i * 0.01)).to.beFalse()
				end

				expect(Z.Handle(p, nil, 101)).to.beFalse()
				expect(#p.fovCalls).to.equal(1)
				expect(Z.Held(p)).to.equal(40)
			end
		},
		{
			name = "a dead player or an invalid one is refused",
			func = function()
				local Z = GryMod.ZoomFov
				local dead = fakePlayer({alive = false})
				expect(Z.Handle(dead, 40, 100)).to.beFalse()
				expect(#dead.fovCalls).to.equal(0)

				local gone = fakePlayer({valid = false})
				expect(Z.Handle(gone, 40, 100)).to.beFalse()
				expect(Z.Handle(nil, 40, 100)).to.beFalse()
			end
		},
		{
			name = "a zoom held by a weapon is not taken: nothing is set or remembered (the engine would refuse it); the player's own zoom is",
			func = function()
				local Z = GryMod.ZoomFov
				-- (a real entity: the engine hands the zoom owner back as one)
				local weapon = ents.Create("prop_physics")
				local held = fakePlayer({owner = weapon})

				local ok, err = pcall(function()
					expect(IsValid(weapon)).to.beTrue()
					expect(Z.Handle(held, 40, 100)).to.beFalse()
					expect(#held.fovCalls).to.equal(0)
					expect(Z.Held(held)).to.beNil()
				end)

				weapon:Remove()

				if not ok then
					error(err, 0)
				end

				local own = fakePlayer()
				own.owner = own
				own.IsValid = function() return true end
				expect(Z.Handle(own, 40, 100)).to.equal("set")
			end
		},
		{
			name = "at most 10 requests a second per player; the next window is open again; one player does not use up another's",
			func = function()
				local Z = GryMod.ZoomFov
				local p = fakePlayer()
				local q = fakePlayer()

				for i = 1, Z.LIMIT do
					expect(Z.Handle(p, 30 + i, 100 + i * 0.01)).to.equal("set")
				end

				expect(Z.Handle(p, 20, 100.5)).to.beFalse()
				expect(Z.Handle(q, 20, 100.5)).to.equal("set")
				expect(Z.Handle(p, 20, 101.2)).to.equal("set")
			end
		},
		{
			name = "a request that does not come again is ended after the timeout, the one kept alive is not, and what is ended is given back to the engine",
			func = function()
				local Z = GryMod.ZoomFov
				local stale = fakePlayer()
				local fresh = fakePlayer()

				Z.Handle(stale, 40, 100)
				Z.Handle(fresh, 40, 100)
				Z.Handle(fresh, 40, 102.5)

				expect(Z.Expire(102.9)).to.equal(0)
				expect(Z.Expire(103.2)).to.equal(1)
				expect(Z.Held(stale)).to.beNil()
				expect(stale.fovCalls[#stale.fovCalls][1]).to.equal(0)
				expect(Z.Held(fresh)).to.equal(40)
				expect(#fresh.fovCalls).to.equal(1)
			end
		},
		{
			name = "Forget (a death, a disconnection) drops what is held without a call; Release gives the field of view back and drops it",
			func = function()
				local Z = GryMod.ZoomFov
				local p = fakePlayer()

				Z.Handle(p, 40, 100)
				Z.Forget(p)
				expect(Z.Held(p)).to.beNil()
				expect(#p.fovCalls).to.equal(1)

				Z.Handle(p, 40, 101)
				Z.Release(p)
				expect(Z.Held(p)).to.beNil()
				expect(#p.fovCalls).to.equal(3)
				expect(p.fovCalls[3][1]).to.equal(0)

				-- (nothing held: nothing to give back)
				Z.Release(p)
				expect(#p.fovCalls).to.equal(3)
			end
		},
		{
			name = "engine contract (real player): the field of view the module sets is the player's, and 0 gives the normal one back",
			func = function()
				local Z = GryMod.ZoomFov
				local p = ply1()

				if not p:Alive() then p:Spawn() end

				for _, w in ipairs(p:GetWeapons()) do
					p:SetFOV(0, 0, w)
				end

				p:SetFOV(0, 0)

				local normal = p:GetFOV()
				local ok, err = pcall(function()
					expect(Z.Handle(p, normal / 2, RealTime())).to.equal("set")
					-- (the transition is short: the engine has the value at once when the time is 0, so the contract is read after the release below)
					expect(Z.Held(p)).to.equal(normal / 2)
					expect(Z.Handle(p, 0, RealTime() + 0.01)).to.equal("release")
				end)

				Z.Forget(p)
				p:SetFOV(0, 0)

				if not ok then
					error(err, 0)
				end

				expect(p:GetFOV()).to.equal(normal)
			end
		}
	}
}
