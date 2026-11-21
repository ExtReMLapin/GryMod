-- Tests of the request to end a weapon's zoom when the binoculars open (GryMod.WeaponZoom, cl_weapon_zoom.lua), GLuaTest format, client
-- realm. The crossbow's right click zooms (the engine's field of view goes to 20 and the weapon owns that zoom); the binoculars (the own
-- zoom of the suit or the Half-Life 2 key) give a view of their own and, when they close, the engine's field of view is the crossbow's
-- again: a jump. The client asks the server to end the weapon's zoom at the moment the binoculars open, and only then, and only when a
-- zoom of a weapon on the list is really up (the field of view of the player is below the normal one). The decision is a pure function;
-- the step reads the world and feeds it. Nothing is sent to the server by these tests.

local OPTION = "gry_zoom_cancel_weapon"

local function setting(name)
	return GetConVar(name)
end

return {
	groupName = "GryMod weapon zoom cancel (client)",
	beforeEach = function(state)
		local W = GryMod.WeaponZoom
		local Bino = GryMod.FlashBinoculars
		state.saved = {
			option = setting(OPTION) and setting(OPTION):GetString(),
			send = W and W.Send,
			wanted = Bino and Bino.Wanted,
			enabled = Bino and Bino.Enabled,
			missing = Bino and Bino.IsMissing,
			fov = FindMetaTable("Player").GetFOV,
			info = FindMetaTable("Player").GetInfoNum,
			weapon = FindMetaTable("Player").GetActiveWeapon
		}
		state.sent = 0
		state.world = {wanted = false, enabled = true, missing = false, fov = 100, default = 100, class = "weapon_crossbow"}

		if W then
			W.Send = function() state.sent = state.sent + 1 end
			W.Reset()
		end

		if setting(OPTION) then
			setting(OPTION):SetString("1")
		end

		Bino.Wanted = function() return state.world.wanted end
		Bino.Enabled = function() return state.world.enabled end
		Bino.IsMissing = function() return state.world.missing end

		-- (what the step reads about the player)
		local meta = FindMetaTable("Player")
		meta.GetFOV = function() return state.world.fov end
		meta.GetInfoNum = function(_, name, default)
			if name == "fov_desired" then
				return state.world.default
			end

			return state.saved.info(LocalPlayer(), name, default)
		end
		meta.GetActiveWeapon = function()
			return {IsValid = function() return true end, GetClass = function() return state.world.class end}
		end
	end,
	afterEach = function(state)
		local W = GryMod.WeaponZoom
		local Bino = GryMod.FlashBinoculars
		local saved = state.saved
		local meta = FindMetaTable("Player")

		meta.GetFOV = saved.fov
		meta.GetInfoNum = saved.info
		meta.GetActiveWeapon = saved.weapon
		Bino.Wanted = saved.wanted
		Bino.Enabled = saved.enabled
		Bino.IsMissing = saved.missing

		if W then
			W.Send = saved.send
			W.Reset()
		end

		if saved.option and setting(OPTION) then
			setting(OPTION):SetString(saved.option)
		end
	end,
	cases = {
		{
			name = "the option exists (saved, on by default) and has a check box in the options panel, and the white list holds the crossbow and nothing else",
			func = function()
				local W = GryMod.WeaponZoom
				expect(W ~= nil).to.beTrue()
				expect(setting(OPTION) ~= nil).to.beTrue()
				expect(setting(OPTION):GetDefault()).to.equal("1")
				expect(W.Weapons.weapon_crossbow).to.beTrue()

				local count = 0
				for _ in pairs(W.Weapons) do count = count + 1 end
				expect(count).to.equal(1)

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = child:GetText()
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found[OPTION] ~= nil).to.beTrue()
			end
		},
		{
			name = "decision: the binoculars OPENING (down, then up) with the crossbow in hand and the field of view below the normal one asks; every other combination does not",
			func = function()
				local W = GryMod.WeaponZoom

				expect(W.Decide(true, false, true, "weapon_crossbow", 20, 100)).to.beTrue()
				-- already up the frame before: not an opening
				expect(W.Decide(true, true, true, "weapon_crossbow", 20, 100)).to.beFalse()
				-- still down, or closing
				expect(W.Decide(true, false, false, "weapon_crossbow", 20, 100)).to.beFalse()
				expect(W.Decide(true, true, false, "weapon_crossbow", 20, 100)).to.beFalse()
				-- the option off
				expect(W.Decide(false, false, true, "weapon_crossbow", 20, 100)).to.beFalse()
				-- another weapon, or none
				expect(W.Decide(true, false, true, "weapon_ar2", 20, 100)).to.beFalse()
				expect(W.Decide(true, false, true, nil, 20, 100)).to.beFalse()
				-- no zoom up: the field of view is the normal one (the Half-Life 2 zoom would only just be asked for: nothing to end)
				expect(W.Decide(true, false, true, "weapon_crossbow", 100, 100)).to.beFalse()
				expect(W.Decide(true, false, true, "weapon_crossbow", 99.8, 100)).to.beFalse()
				expect(W.Decide(true, false, true, "weapon_crossbow", 100.4, 100)).to.beFalse()
				-- a normal field of view that is not 100
				expect(W.Decide(true, false, true, "weapon_crossbow", 20, 75)).to.beTrue()
				expect(W.Decide(true, false, true, "weapon_crossbow", 75, 75)).to.beFalse()
				-- nonsense in
				expect(W.Decide(true, false, true, "weapon_crossbow", nil, 100)).to.beFalse()
				expect(W.Decide(true, false, true, "weapon_crossbow", 0 / 0, 100)).to.beFalse()
				expect(W.Decide(true, false, true, "weapon_crossbow", 20, nil)).to.beFalse()
			end
		},
		{
			name = "step: the crossbow zoomed, the binoculars open: one request, at the opening only (not again while they stay up)",
			func = function(state)
				local W = GryMod.WeaponZoom
				local ply = LocalPlayer()

				state.world.fov = 20
				W.Step(ply)
				expect(state.sent).to.equal(0)

				state.world.wanted = true
				W.Step(ply)
				expect(state.sent).to.equal(1)

				W.Step(ply)
				W.Step(ply)
				expect(state.sent).to.equal(1)

				-- closed, then open again with the zoom up again: a second request
				state.world.wanted = false
				W.Step(ply)
				state.world.wanted = true
				W.Step(ply)
				expect(state.sent).to.equal(2)
			end
		},
		{
			name = "step: the binoculars alone (the field of view is the normal one when they open), or the Half-Life 2 zoom that follows a moment later: nothing is asked",
			func = function(state)
				local W = GryMod.WeaponZoom
				local ply = LocalPlayer()

				state.world.wanted = true
				W.Step(ply)
				expect(state.sent).to.equal(0)

				-- (the Half-Life 2 zoom reaches 25 degrees after the opening: the opening was the moment to look, and it is past)
				state.world.fov = 25
				W.Step(ply)
				expect(state.sent).to.equal(0)
			end
		},
		{
			name = "step: another weapon in hand with a zoom (a field of view below the normal one) sends nothing",
			func = function(state)
				local W = GryMod.WeaponZoom
				local ply = LocalPlayer()

				state.world.class = "weapon_ar2"
				state.world.fov = 20
				W.Step(ply)
				state.world.wanted = true
				W.Step(ply)
				expect(state.sent).to.equal(0)
			end
		},
		{
			name = "step: the option off, the binoculars element off, or the movie missing: nothing is asked",
			func = function(state)
				local W = GryMod.WeaponZoom
				local ply = LocalPlayer()

				state.world.fov = 20

				setting(OPTION):SetString("0")
				W.Step(ply)
				state.world.wanted = true
				W.Step(ply)
				expect(state.sent).to.equal(0)

				setting(OPTION):SetString("1")
				state.world.wanted = false
				W.Step(ply)
				state.world.enabled = false
				state.world.wanted = true
				W.Step(ply)
				expect(state.sent).to.equal(0)

				state.world.enabled = true
				state.world.missing = true
				state.world.wanted = false
				W.Step(ply)
				state.world.wanted = true
				W.Step(ply)
				expect(state.sent).to.equal(0)
			end
		},
		{
			name = "step: the binoculars already up when the option comes on, or the step starts, are not an opening; and a Reset forgets that they were up",
			func = function(state)
				local W = GryMod.WeaponZoom
				local ply = LocalPlayer()

				state.world.fov = 20
				state.world.wanted = true
				W.Step(ply)
				-- (the first look of the step sees them up: it asked at once, they were just opened)
				expect(state.sent).to.equal(1)

				W.Reset()
				W.Step(ply)
				expect(state.sent).to.equal(2)
			end
		},
		{
			name = "the real Send writes the message with no payload to the server (the net functions are called, nothing else)",
			func = function(state)
				local W = GryMod.WeaponZoom
				local sendReal = state.saved.send
				local calls = {}
				local start, send = net.Start, net.SendToServer
				net.Start = function(name) calls[#calls + 1] = "start:" .. tostring(name) end
				net.SendToServer = function() calls[#calls + 1] = "send" end

				local ok, err = pcall(sendReal)
				net.Start, net.SendToServer = start, send

				if not ok then
					error(err, 0)
				end

				expect(#calls).to.equal(2)
				expect(calls[1]).to.equal("start:gry_cancel_weapon_zoom")
				expect(calls[2]).to.equal("send")
			end
		}
	}
}
