-- Tests of the field of view that follows the own zoom (GryMod.ZoomFov, cl_zoom_fov.lua), GLuaTest format, client realm. The own zoom of
-- the binoculars (the key of the suit mod) only gives the VIEW its stage's field of view (CalcView): the engine's field of view of the
-- player stays at the normal one, and the engine scales the fade distances and the details of the world with that one (measured in the
-- game: the panes of the windows of a far house are there with Player:SetFOV(20) and not with a CalcView of 20). The client tells the
-- server the field of view of the stage it is in (gry_zoom_fov, one float, 0 = back to normal); Player:SetFOV is server side. The
-- decision is pure (what is to be sent now), the step reads the world and feeds it. Nothing is sent to the server by these tests.

local OPTION = "gry_zoom_follow_fov"

local function setting(name)
	return GetConVar(name)
end

return {
	groupName = "GryMod zoom field of view (client)",
	beforeEach = function(state)
		local Z = GryMod.ZoomFov
		local Bino = GryMod.FlashBinoculars
		local suit = GryMod.SuitZoom
		state.saved = {
			option = setting(OPTION) and setting(OPTION):GetString(),
			send = Z and Z.Send,
			wanted = Bino and Bino.Wanted,
			enabled = Bino and Bino.Enabled,
			missing = Bino and Bino.IsMissing,
			active = suit and suit.IsActive,
			info = FindMetaTable("Player").GetInfoNum,
			stage = Bino and Bino.ZoomState and Bino.ZoomState.stage
		}
		state.sent = {}
		state.world = {wanted = true, enabled = true, missing = false, own = true, default = 100}

		if Z then
			Z.Send = function(fov) state.sent[#state.sent + 1] = fov end
			Z.Reset()
		end

		if setting(OPTION) then
			setting(OPTION):SetString("1")
		end

		Bino.Wanted = function() return state.world.wanted end
		Bino.Enabled = function() return state.world.enabled end
		Bino.IsMissing = function() return state.world.missing end
		suit.IsActive = function() return state.world.own end

		local meta = FindMetaTable("Player")
		meta.GetInfoNum = function(_, name, default)
			if name == "fov_desired" then
				return state.world.default
			end

			return state.saved.info(LocalPlayer(), name, default)
		end
	end,
	afterEach = function(state)
		local Z = GryMod.ZoomFov
		local Bino = GryMod.FlashBinoculars
		local suit = GryMod.SuitZoom
		local saved = state.saved

		FindMetaTable("Player").GetInfoNum = saved.info
		Bino.Wanted = saved.wanted
		Bino.Enabled = saved.enabled
		Bino.IsMissing = saved.missing
		suit.IsActive = saved.active
		Bino.ZoomState.stage = saved.stage or 0

		if Z then
			Z.Send = saved.send
			Z.Reset()
		end

		if saved.option and setting(OPTION) then
			setting(OPTION):SetString(saved.option)
		end
	end,
	cases = {
		{
			name = "the option exists (saved, on by default) and has a check box in the options panel",
			func = function()
				local Z = GryMod.ZoomFov
				expect(Z ~= nil).to.beTrue()
				expect(setting(OPTION) ~= nil).to.beTrue()
				expect(setting(OPTION):GetDefault()).to.equal("1")

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
			name = "target: the field of view of the stage (2x, 4x, 8x of the base: 61.6, 33.2, 16.9 at 100) while the own zoom is up; 0 for no stage, no own zoom, a stage that does not exist or a base that is not a number",
			func = function()
				local Z = GryMod.ZoomFov

				expect(Z.Target(true, 1, 100)).to.beBetween(61.5, 61.7)
				expect(Z.Target(true, 2, 100)).to.beBetween(33.1, 33.3)
				expect(Z.Target(true, 3, 100)).to.beBetween(16.8, 17)
				expect(Z.Target(true, 0, 100)).to.equal(0)
				expect(Z.Target(false, 2, 100)).to.equal(0)
				expect(Z.Target(true, 4, 100)).to.equal(0)
				expect(Z.Target(true, nil, 100)).to.equal(0)
				expect(Z.Target(true, 2, nil)).to.equal(0)
				expect(Z.Target(true, 2, 0 / 0)).to.equal(0)
				expect(Z.Target(true, 2, -10)).to.equal(0)
			end
		},
		{
			name = "decision: a new target is sent at once; the same one is sent again once a second (it keeps the server's request alive) and not before; 0 is sent once, when something was sent",
			func = function()
				local Z = GryMod.ZoomFov
				local s = Z.NewState()

				-- nothing zoomed, nothing sent
				expect(Z.Decide(s, 0, 10)).to.beNil()

				expect(Z.Decide(s, 61.6, 10)).to.equal(61.6)
				expect(Z.Decide(s, 61.6, 10.5)).to.beNil()
				expect(Z.Decide(s, 61.6, 11.01)).to.equal(61.6)
				expect(Z.Decide(s, 61.6, 11.5)).to.beNil()

				-- a step to another stage: at once
				expect(Z.Decide(s, 33.2, 11.6)).to.equal(33.2)

				-- the zoom ends: 0 once
				expect(Z.Decide(s, 0, 11.7)).to.equal(0)
				expect(Z.Decide(s, 0, 11.8)).to.beNil()
				expect(Z.Decide(s, 0, 20)).to.beNil()
			end
		},
		{
			name = "the step: the own zoom up in a stage sends that stage's field of view once, then nothing while it does not change",
			func = function(state)
				local Z = GryMod.ZoomFov
				GryMod.FlashBinoculars.ZoomState.stage = 2

				Z.Step(LocalPlayer(), 10)
				Z.Step(LocalPlayer(), 10.1)
				Z.Step(LocalPlayer(), 10.2)

				expect(#state.sent).to.equal(1)
				expect(state.sent[1]).to.beBetween(33.1, 33.3)

				-- the wheel steps to the next stage
				GryMod.FlashBinoculars.ZoomState.stage = 3
				Z.Step(LocalPlayer(), 10.3)
				expect(#state.sent).to.equal(2)
				expect(state.sent[2]).to.beBetween(16.8, 17)

				-- the zoom closes
				GryMod.FlashBinoculars.ZoomState.stage = 0
				Z.Step(LocalPlayer(), 10.4)
				Z.Step(LocalPlayer(), 10.5)
				expect(#state.sent).to.equal(3)
				expect(state.sent[3]).to.equal(0)
			end
		},
		{
			name = "the step sends nothing when the own zoom is not the one that is up (the Half-Life 2 key sets the engine's field of view itself)",
			func = function(state)
				local Z = GryMod.ZoomFov
				GryMod.FlashBinoculars.ZoomState.stage = 2
				state.world.own = false

				Z.Step(LocalPlayer(), 10)
				expect(#state.sent).to.equal(0)
			end
		},
		{
			name = "the step sends nothing with the option off, the HUD element off or the movie missing; one that was sent is taken back with 0",
			func = function(state)
				local Z = GryMod.ZoomFov
				GryMod.FlashBinoculars.ZoomState.stage = 2

				setting(OPTION):SetString("0")
				Z.Step(LocalPlayer(), 10)
				expect(#state.sent).to.equal(0)

				setting(OPTION):SetString("1")
				state.world.enabled = false
				Z.Step(LocalPlayer(), 11)
				expect(#state.sent).to.equal(0)

				state.world.enabled, state.world.missing = true, true
				Z.Step(LocalPlayer(), 12)
				expect(#state.sent).to.equal(0)

				state.world.missing = false
				Z.Step(LocalPlayer(), 13)
				expect(#state.sent).to.equal(1)

				-- (the option goes off while zoomed: the server is told to give the field of view back)
				setting(OPTION):SetString("0")
				Z.Step(LocalPlayer(), 13.1)
				expect(#state.sent).to.equal(2)
				expect(state.sent[2]).to.equal(0)
			end
		},
		{
			name = "the step: the binoculars not wanted any more (a death, a menu) send 0 even when the stage state is still up",
			func = function(state)
				local Z = GryMod.ZoomFov
				GryMod.FlashBinoculars.ZoomState.stage = 1

				Z.Step(LocalPlayer(), 10)
				expect(#state.sent).to.equal(1)

				state.world.wanted = false
				Z.Step(LocalPlayer(), 10.1)
				expect(#state.sent).to.equal(2)
				expect(state.sent[2]).to.equal(0)
			end
		},
		{
			name = "Send writes one float to the real net message (the encoding the server reads)",
			func = function(state)
				-- (the real net functions are saved FIRST and put back whatever happens, even when the module is missing: a stub left in
				-- the net library stops every message of the client)
				local calls = {}
				local saved = {start = net.Start, write = net.WriteFloat, send = net.SendToServer}

				local ok, err = pcall(function()
					local Z = GryMod.ZoomFov

					net.Start = function(name) calls[#calls + 1] = "start:" .. name end
					net.WriteFloat = function(v) calls[#calls + 1] = "float:" .. v end
					net.SendToServer = function() calls[#calls + 1] = "send" end
					Z.Send = state.saved.send
					Z.Send(33.5)
				end)

				net.Start, net.WriteFloat, net.SendToServer = saved.start, saved.write, saved.send

				if not ok then
					error(err, 0)
				end

				expect(calls[1]).to.equal("start:gry_zoom_fov")
				expect(calls[2]).to.equal("float:33.5")
				expect(calls[3]).to.equal("send")
			end
		}
	}
}
