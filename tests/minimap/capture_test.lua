-- Tests of the minimap's capture module (lua/grymod/client/minimap/capture.lua), GLuaTest format, client realm. One render of one tile from above:
-- the entities that are not the map's are hidden (and restored exactly), the temporary hooks that keep the effects out of the picture are
-- installed (and removed), the view is orthographic and the slab is cut with a very high camera, the bytes are read before the render
-- target is popped. Nothing here needs a render context: the render.* calls (and the engine's render target creation) are replaced by
-- stand-ins that record what they were given, and every stand-in is put back in afterEach inside a pcall, also when a case failed.
-- The real pixels are checked by tests/minimap/capture_job.lua (lua_job, PostRender).

local HOOK_NAME = "GryMod minimap capture"
local EVENTS = {"PreDrawHalos", "PreDrawEffects", "PrePlayerDraw", "PreDrawViewModel", "PreDrawSkyBox", "SetupWorldFog"}
local MODEL = "models/props_junk/PopCan01a.mdl"
local RENDER_CALLS = {"PushRenderTarget", "Clear", "RenderView", "Capture", "PopRenderTarget", "SetLightingMode", "FogMode", "SetWriteDepthToDestAlpha", "CopyRenderTargetToTexture"}
local OTHER_HOOK = "GryMod minimap capture test other addon"

local savedRender = {}   -- render.<name> originals, saved by stubRender
local savedEntity = {}   -- the Entity metatable's original CreatedByMap (and the hook, if any)
local savedGlobals = {}  -- GetRenderTargetEx, FrameNumber
local made = {}          -- client props created by a case
local fakeMap = {}       -- {ent = , value = , raise = } entries of the CreatedByMap stand-in
local snapshot           -- {{ent, noDraw}} of every entity before the case

local function capture()
	local C = GryMod and GryMod.Minimap and GryMod.Minimap.Capture

	expect(C ~= nil).to.beTrue()

	return C
end

-- the function of that name must exist: a missing function is the one reason a case is red before the module is written
local function need(name)
	local f = capture()[name]

	expect(type(f)).to.equal("function")

	return f
end

local function makeProp(noDraw)
	local p = ents.CreateClientProp(MODEL)

	expect(IsValid(p)).to.beTrue()
	p:SetPos(LocalPlayer():GetPos() + Vector(0, 0, 64))
	made[#made + 1] = p

	if noDraw then
		p:SetNoDraw(true)
	end

	return p
end

local function standInCreatedByMap()
	if savedEntity.CreatedByMap then
		return
	end

	local meta = FindMetaTable("Entity")
	local original = meta.CreatedByMap

	savedEntity.CreatedByMap = original
	savedEntity.meta = meta
	meta.CreatedByMap = function(e)
		for i = 1, #fakeMap do
			local f = fakeMap[i]

			if f.ent == e then
				if f.raise then
					if f.probe then
						f.probe()
					end

					error("capture test: CreatedByMap exploded", 0)
				end

				return f.value
			end
		end

		return original(e)
	end
end

-- raise: the stand-in raises for this entity; probe (optional) is called just before it does
local function fakeCreatedByMap(ent, value, raise, probe)
	standInCreatedByMap()
	fakeMap[#fakeMap + 1] = {ent = ent, value = value, raise = raise, probe = probe}
end

-- every render.* call of the capture is replaced: it records its name (and its arguments) in seq / args, then calls handlers[name] if there is one
local function stubRender(seq, args, handlers)
	for i = 1, #RENDER_CALLS do
		local name = RENDER_CALLS[i]

		if savedRender[name] == nil then
			savedRender[name] = render[name]
		end

		render[name] = function(...)
			seq[#seq + 1] = name
			args[name] = {n = select("#", ...), ...}

			local h = handlers and handlers[name]

			if h then
				return h(...)
			end
		end
	end
end

local function validTile(over)
	local t = {level = "a1", tx = 1, ty = -2, res = 64, ppm = 2}

	for k, v in pairs(over or {}) do
		t[k] = v
	end

	return t
end

local function validLevel()
	return {id = "a1", zlo = -32, zhi = 128}
end

local function pixels(res)
	return string.rep("\7", res * res * 4)
end

-- Render under pcall (it must never raise) with exactly the tile and the level given (nil stays nil)
local function renderRaw(handlers, tile, level)
	local seq, args = {}, {}

	stubRender(seq, args, handlers)

	local ok, a, b = pcall(capture().Render, tile, level)

	return seq, args, ok, a, b
end

-- the same with a valid tile and level when none is given
local function renderOnce(handlers, tile, level)
	return renderRaw(handlers, tile or validTile(), level or validLevel())
end

local function noDrawOf(ent)
	return ent:GetNoDraw()
end

local function listHas(list, ent)
	for i = 1, #list do
		if list[i] == ent then
			return true
		end
	end

	return false
end

local function countHooks()
	local n = 0

	for _, event in ipairs(EVENTS) do
		local t = hook.GetTable()[event]

		if t and t[HOOK_NAME] ~= nil then
			n = n + 1
		end
	end

	return n
end

return {
	groupName = "GryMod minimap capture (client)",
	beforeEach = function(state)
		snapshot = {}

		for _, e in ipairs(ents.GetAll()) do
			snapshot[#snapshot + 1] = {ent = e, noDraw = e:GetNoDraw()}
		end

		state.hiddenSafety = nil
		fakeMap = {}
		made = {}
	end,
	afterEach = function(state)
		for name, f in pairs(savedRender) do
			pcall(function() render[name] = f end)
		end

		savedRender = {}

		if savedEntity.CreatedByMap then
			pcall(function() savedEntity.meta.CreatedByMap = savedEntity.CreatedByMap end)
		end

		savedEntity = {}
		fakeMap = {}

		if savedGlobals.GetRenderTargetEx then
			GetRenderTargetEx = savedGlobals.GetRenderTargetEx
			savedGlobals.GetRenderTargetEx = nil

			local C = GryMod.Minimap and GryMod.Minimap.Capture

			-- the fake targets must not stay in the module's cache
			if C and C.ResetRTCache then
				pcall(C.ResetRTCache)
			end
		end

		if savedGlobals.FrameNumber then
			FrameNumber = savedGlobals.FrameNumber
			savedGlobals.FrameNumber = nil
		end

		-- the arbitration of the frame (MayCapture) is global state: back to nothing
		pcall(function()
			local C = GryMod.Minimap.Capture

			C.SetPriority(nil)
			C.ResetFrame()
		end)

		pcall(hook.Remove, "PreDrawHalos", OTHER_HOOK)

		-- the temporary hooks are never left behind, whatever the case did
		for _, event in ipairs(EVENTS) do
			pcall(hook.Remove, event, HOOK_NAME)
		end

		for i = 1, #made do
			if IsValid(made[i]) then
				made[i]:Remove()
			end
		end

		made = {}

		-- every entity that existed goes back to the NoDraw state it had
		for i = 1, #(snapshot or {}) do
			local s = snapshot[i]

			if IsValid(s.ent) and s.ent:GetNoDraw() ~= s.noDraw then
				pcall(function() s.ent:SetNoDraw(s.noDraw) end)
			end
		end

		snapshot = nil
	end,
	cases = {
		-- HideNonMap / Restore ------------------------------------------------------------------------------------------------
		{
			-- fails if: HideNonMap hides nothing, hides the wrong thing, or Restore does not show it again
			name = "an entity that is visible and not the map's is hidden, then visible again after Restore",
			func = function()
				local Hide, Restore = need("HideNonMap"), need("Restore")
				local a = makeProp(false)

				expect(noDrawOf(a)).to.equal(false)

				local list = Hide()

				expect(type(list)).to.equal("table")
				expect(listHas(list, a)).to.beTrue()
				expect(noDrawOf(a)).to.equal(true)

				Restore(list)
				expect(noDrawOf(a)).to.equal(false)
			end
		},
		{
			-- fails if: the module sets NoDraw false on an entity that was already hidden (before: its own choice), or lists it
			name = "an entity that was already NoDraw is never touched: not listed, still NoDraw after the hide and after the restore",
			func = function()
				local Hide, Restore = need("HideNonMap"), need("Restore")
				local b = makeProp(true)
				local list = Hide()

				expect(listHas(list, b)).to.beFalse()
				expect(noDrawOf(b)).to.equal(true)
				Restore(list)
				expect(noDrawOf(b)).to.equal(true)
			end
		},
		{
			-- fails if: the map filter is missing or inverted (the stand-in answers true for this entity, as the engine does for the map's props)
			name = "an entity created by the map is never touched (CreatedByMap true): visible during the hide, not listed",
			func = function()
				local Hide, Restore = need("HideNonMap"), need("Restore")
				local c = makeProp(false)

				fakeCreatedByMap(c, true)

				local list = Hide()

				expect(listHas(list, c)).to.beFalse()
				expect(noDrawOf(c)).to.equal(false)
				Restore(list)
				expect(noDrawOf(c)).to.equal(false)
			end
		},
		{
			-- fails if: the local player is hidden (the stand-in says it is not the map's, which is what the engine says too)
			name = "the local player is never touched",
			func = function()
				local Hide, Restore = need("HideNonMap"), need("Restore")
				local me = LocalPlayer()
				local before = noDrawOf(me)

				fakeCreatedByMap(me, false)

				local list = Hide()

				expect(listHas(list, me)).to.beFalse()
				expect(noDrawOf(me)).to.equal(before)
				Restore(list)
				expect(noDrawOf(me)).to.equal(before)
			end
		},
		{
			-- fails if: the world is hidden, or Restore shows an entity it did not hide: every entity has exactly its first state afterwards
			name = "after a hide and a restore every entity of the client has exactly the NoDraw state it had, whatever it is",
			func = function()
				local Hide, Restore = need("HideNonMap"), need("Restore")

				makeProp(false)
				makeProp(true)

				local before = {}

				for _, e in ipairs(ents.GetAll()) do
					before[#before + 1] = {ent = e, noDraw = e:GetNoDraw()}
				end

				local list = Hide()
				local hiddenOnes = 0

				for i = 1, #list do
					expect(list[i]:CreatedByMap()).to.beFalse()
					expect(noDrawOf(list[i])).to.equal(true)
					hiddenOnes = hiddenOnes + 1
				end

				expect(hiddenOnes > 0).to.beTrue()
				Restore(list)

				for i = 1, #before do
					if IsValid(before[i].ent) then
						expect(before[i].ent:GetNoDraw()).to.equal(before[i].noDraw)
					end
				end
			end
		},
		{
			-- fails if: Restore raises on an entity that is gone, or shows something that is not in ITS list
			name = "Restore skips an entity that was removed, shows only the ones of its own list, and accepts an empty or missing list",
			func = function()
				local Hide, Restore = need("HideNonMap"), need("Restore")
				local a = makeProp(false)
				local other = makeProp(false)
				local list = Hide()

				-- a second entity hidden by someone else after the hide is not in the list: Restore leaves it hidden
				local late = makeProp(false)

				late:SetNoDraw(true)
				a:Remove()
				expect(pcall(Restore, list)).to.beTrue()
				expect(noDrawOf(other)).to.equal(false)
				expect(noDrawOf(late)).to.equal(true)
				expect(pcall(Restore, {})).to.beTrue()
				expect(pcall(Restore, nil)).to.beTrue()
			end
		},
		{
			-- fails if: HideNonMap leaves the entities it already hid hidden when its own loop raises (a stand-in raises for one entity)
			name = "if the hide itself raises halfway, what it hid is restored and it answers nil, reason (nothing stays hidden)",
			func = function()
				local Hide = need("HideNonMap")
				local a = makeProp(false)
				local t = makeProp(false)

				-- t is created after a: the sweep meets a first (and hides it), then raises on t
				local aWasHidden

				fakeCreatedByMap(t, false, true, function() aWasHidden = noDrawOf(a) end)

				local ok, list, why = pcall(Hide)

				expect(aWasHidden).to.equal(true)
				expect(ok).to.beTrue()
				expect(list).to.beNil()
				expect(type(why)).to.equal("string")
				expect(noDrawOf(a)).to.equal(false)
				expect(noDrawOf(t)).to.equal(false)
			end
		},
		-- Render: errors ------------------------------------------------------------------------------------------------------
		{
			-- fails if: the restore is not in a finally of its own (an error of RenderView leaves A hidden, the hooks installed, or IsCapturing true)
			name = "Render with a RenderView that raises: the hidden entities are back, the hooks are removed, IsCapturing is false, it answers nil, reason",
			func = function()
				local a = makeProp(false)
				local b = makeProp(true)
				local hiddenDuring, hooksDuring

				local seq, args, ok, r1, r2 = renderOnce({
					RenderView = function()
						hiddenDuring = noDrawOf(a)
						hooksDuring = countHooks()
						error("capture test: RenderView exploded", 0)
					end
				})

				expect(ok).to.beTrue()
				expect(r1).to.beNil()
				expect(type(r2)).to.equal("string")
				expect(string.find(r2, "RenderView exploded", 1, true) ~= nil).to.beTrue()
				-- the error came while everything was in place, and everything is undone afterwards
				expect(hiddenDuring).to.equal(true)
				expect(hooksDuring).to.equal(#EVENTS)
				expect(noDrawOf(a)).to.equal(false)
				expect(noDrawOf(b)).to.equal(true)
				expect(countHooks()).to.equal(0)
				expect(capture().IsCapturing()).to.equal(false)
				-- the render target that was pushed is popped, and nothing was read
				expect(seq[#seq]).to.equal("PopRenderTarget")
				expect(args.Capture).to.beNil()
			end
		},
		{
			-- fails if: an error of render.Capture (or of the push) is not contained and cleaned the same way
			name = "Render with a render.Capture that raises: same clean-up, the render target is popped",
			func = function()
				local a = makeProp(false)
				local seq, _, ok, r1, r2 = renderOnce({
					Capture = function() error("capture test: Capture exploded", 0) end
				})

				expect(ok).to.beTrue()
				expect(r1).to.beNil()
				expect(string.find(r2, "Capture exploded", 1, true) ~= nil).to.beTrue()
				expect(noDrawOf(a)).to.equal(false)
				expect(countHooks()).to.equal(0)
				expect(capture().IsCapturing()).to.equal(false)

				local pushes, pops = 0, 0

				for i = 1, #seq do
					if seq[i] == "PushRenderTarget" then pushes = pushes + 1 end
					if seq[i] == "PopRenderTarget" then pops = pops + 1 end
				end

				expect(pushes).to.equal(1)
				expect(pops).to.equal(1)
			end
		},
		{
			-- fails if: a raise of the hide loop is not contained: entities stay hidden, hooks stay, or the render goes on
			name = "Render when the hide loop raises halfway: what was hidden is restored, no render call is made, the hooks are removed",
			func = function()
				local a = makeProp(false)
				local t = makeProp(false)

				local aWasHidden

				fakeCreatedByMap(t, false, true, function() aWasHidden = noDrawOf(a) end)

				local seq, _, ok, r1, r2 = renderOnce({})

				expect(aWasHidden).to.equal(true)
				expect(ok).to.beTrue()
				expect(r1).to.beNil()
				expect(type(r2)).to.equal("string")
				expect(noDrawOf(a)).to.equal(false)
				expect(noDrawOf(t)).to.equal(false)
				expect(#seq).to.equal(0)
				expect(countHooks()).to.equal(0)
				expect(capture().IsCapturing()).to.equal(false)
			end
		},
		{
			-- fails if: Render does not leave the pre-existing hooks of other addons alone (it removes only its own name)
			name = "the hooks of other addons on the same events are untouched",
			func = function()
				local other = function() end

				hook.Add("PreDrawHalos", OTHER_HOOK, other)

				local _, _, ok = renderOnce({RenderView = function() end, Capture = function() return pixels(64) end})

				expect(ok).to.beTrue()
				expect(hook.GetTable().PreDrawHalos[OTHER_HOOK]).to.equal(other)
			end
		},
		-- Render: the view -----------------------------------------------------------------------------------------------------
		{
			-- fails if: any field of the view is different (ortho half width, camera height, slab planes, sizes, flags)
			name = "the view given to RenderView: orthographic, from straight above, camera 50000 above the top of the level, slab as znear/zfar, no HUD or effects",
			func = function()
				local tile, level = validTile({tx = -2, ty = 3, res = 128, ppm = 4}), {id = "a1", zlo = -32.5, zhi = 191.5}
				local T = 128 / 4 / GryMod.RadarShared.METRES_PER_UNIT
				local half = T / 2
				local view

				local _, _, ok = renderOnce({
					RenderView = function(v) view = v end,
					Capture = function() return pixels(128) end
				}, tile, level)

				expect(ok).to.beTrue()
				expect(type(view)).to.equal("table")
				expect(view.ortho.left).to.aboutEqual(-half, 0.01)
				expect(view.ortho.right).to.aboutEqual(half, 0.01)
				expect(view.ortho.top).to.aboutEqual(-half, 0.01)
				expect(view.ortho.bottom).to.aboutEqual(half, 0.01)
				expect(view.angles.p).to.aboutEqual(90, 0.0001)
				expect(view.angles.y).to.aboutEqual(0, 0.0001)
				expect(view.angles.r).to.aboutEqual(0, 0.0001)
				-- the centre of the tile (tx, ty): ((tx + 0.5) * T, (ty + 0.5) * T)
				expect(view.origin.x).to.aboutEqual((-2 + 0.5) * T, 0.01)
				expect(view.origin.y).to.aboutEqual((3 + 0.5) * T, 0.01)
				expect(view.origin.z).to.aboutEqual(191.5 + 50000, 0.01)
				expect(view.znear).to.equal(50000)
				expect(view.zfar).to.aboutEqual(50000 + (191.5 - -32.5), 0.001)
				expect(view.x).to.equal(0)
				expect(view.y).to.equal(0)
				expect(view.w).to.equal(128)
				expect(view.h).to.equal(128)
				expect(view.aspect).to.equal(1)
				expect(view.drawviewmodel).to.equal(false)
				expect(view.drawhud).to.equal(false)
				expect(view.drawmonitors).to.equal(false)
				expect(view.dopostprocess).to.equal(false)
				expect(view.drawviewer).to.equal(false)
				expect(view.bloomtone).to.equal(false)
			end
		},
		-- Render: order of the calls ------------------------------------------------------------------------------------------
		{
			-- fails if: the order is not push, clear, render, capture, pop, restore (the capture must read the target BEFORE it is popped; the
			-- entities must be hidden all along and shown only after the pop)
			name = "the order of the calls: PushRenderTarget, Clear, RenderView, Capture, PopRenderTarget, then the restoration; the render target is the cached one",
			func = function()
				local a = makeProp(false)
				local hiddenAt = {}

				local function mark(name)
					return function() hiddenAt[name] = noDrawOf(a) end
				end

				local seq, args, ok, r1 = renderOnce({
					PushRenderTarget = mark("push"),
					Clear = mark("clear"),
					RenderView = mark("view"),
					Capture = function() hiddenAt.capture = noDrawOf(a) return pixels(64) end,
					PopRenderTarget = mark("pop")
				})

				expect(ok).to.beTrue()
				expect(type(r1)).to.equal("string")

				local order = {}

				for i = 1, #seq do
					local n = seq[i]

					if n == "PushRenderTarget" or n == "Clear" or n == "RenderView" or n == "Capture" or n == "PopRenderTarget" then
						order[#order + 1] = n
					end
				end

				expect(table.concat(order, ",")).to.equal("PushRenderTarget,Clear,RenderView,Capture,PopRenderTarget")
				-- the lighting mode is set before the view is rendered (mode 0)
				local light, view
				for i = 1, #seq do
					if seq[i] == "SetLightingMode" and not light then light = i end
					if seq[i] == "RenderView" then view = i end
				end
				expect(light ~= nil and view ~= nil and light < view).to.beTrue()
				expect(args.SetLightingMode[1]).to.equal(0)
				-- the entity is hidden at every step, including the pop, and shown only when Render has returned
				expect(hiddenAt.push and hiddenAt.clear and hiddenAt.view and hiddenAt.capture and hiddenAt.pop).to.equal(true)
				expect(noDrawOf(a)).to.equal(false)
				expect(args.PushRenderTarget[1] == capture().GetRT(64)).to.beTrue()
			end
		},
		{
			-- fails if: the capture asks for another format or another rectangle; or a nil capture is turned into an error / a string
			name = "render.Capture gets format bgra and w = h = res, x = y = 0; its bytes are returned unchanged",
			func = function()
				local bytes = pixels(64)
				local _, args, ok, r1 = renderOnce({Capture = function() return bytes end})

				expect(ok).to.beTrue()
				expect(r1 == bytes).to.beTrue()

				local p = args.Capture[1]

				expect(p.format).to.equal("bgra")
				expect(p.x).to.equal(0)
				expect(p.y).to.equal(0)
				expect(p.w).to.equal(64)
				expect(p.h).to.equal(64)
			end
		},
		{
			-- fails if: a nil capture (the menu is open) raises, or does not give the reason the generator waits for; the cleanup must still be done
			name = "when render.Capture gives nil (the menu is open): nil, \"capture unavailable\", no error, everything restored",
			func = function()
				local a = makeProp(false)
				local seq, _, ok, r1, r2 = renderOnce({Capture = function() return nil end})

				expect(ok).to.beTrue()
				expect(r1).to.beNil()
				expect(r2).to.equal("capture unavailable")
				expect(noDrawOf(a)).to.equal(false)
				expect(countHooks()).to.equal(0)
				expect(seq[#seq]).to.equal("PopRenderTarget")
			end
		},
		{
			-- fails if: the bytes are not the size of the tile (a wrong length would end as a corrupt VTF): a short string is refused as an error
			name = "a capture whose length is not res * res * 4 is refused (nil, reason)",
			func = function()
				local _, _, ok, r1, r2 = renderOnce({Capture = function() return "abc" end})

				expect(ok).to.beTrue()
				expect(r1).to.beNil()
				expect(type(r2)).to.equal("string")
			end
		},
		-- Render: the temporary hooks ------------------------------------------------------------------------------------------
		{
			-- fails if: one of the six events does not answer true while rendering, or the fog is not switched off, or a hook stays after
			name = "during the render the six events answer true (halos, effects, player draw, view model, sky box, world fog), the fog is switched off; afterwards none of them",
			func = function()
				local answers = {}
				local seq, args, ok = renderOnce({
					RenderView = function()
						for _, event in ipairs(EVENTS) do
							answers[event] = hook.Run(event, LocalPlayer())
						end
					end,
					Capture = function() return pixels(64) end
				})

				expect(ok).to.beTrue()

				for _, event in ipairs(EVENTS) do
					expect(answers[event]).to.equal(true)
				end

				-- the fog hook switched the fog off through render.FogMode(MATERIAL_FOG_NONE)
				local fogged = false

				for i = 1, #seq do
					if seq[i] == "FogMode" then fogged = true end
				end

				expect(fogged).to.beTrue()
				expect(args.FogMode[1]).to.equal(MATERIAL_FOG_NONE)
				expect(countHooks()).to.equal(0)

				-- after the render the events are not answered by the module any more
				local t = hook.GetTable()

				for _, event in ipairs(EVENTS) do
					expect(t[event] == nil or t[event][HOOK_NAME] == nil).to.beTrue()
				end
			end
		},
		-- Render: state -------------------------------------------------------------------------------------------------------
		{
			-- fails if: IsCapturing is not exactly "inside Render" (true too late, false too early, or stuck true after a failure)
			name = "IsCapturing is true only while Render runs (also during the capture call), false before, after, and after an error",
			func = function()
				local isCap = need("IsCapturing")
				local during = {}

				expect(isCap()).to.equal(false)

				local _, _, ok = renderOnce({
					PushRenderTarget = function() during.push = isCap() end,
					RenderView = function() during.view = isCap() end,
					Capture = function() during.capture = isCap() return pixels(64) end,
					PopRenderTarget = function() during.pop = isCap() end
				})

				expect(ok).to.beTrue()
				expect(during.push).to.equal(true)
				expect(during.view).to.equal(true)
				expect(during.capture).to.equal(true)
				expect(during.pop).to.equal(true)
				expect(isCap()).to.equal(false)

				renderOnce({RenderView = function() error("capture test: boom", 0) end})
				expect(isCap()).to.equal(false)
			end
		},
		{
			-- fails if: a Render started inside a Render (from a hook it triggers) is allowed to nest, or leaves the first one broken
			name = "a Render inside a Render is refused (nil, reason) and the outer one still cleans up",
			func = function()
				local a = makeProp(false)
				local innerOk, innerA, innerB
				local seq, _, ok, r1 = renderOnce({
					RenderView = function()
						innerOk, innerA, innerB = pcall(capture().Render, validTile(), validLevel())
					end,
					Capture = function() return pixels(64) end
				})

				expect(ok).to.beTrue()
				expect(type(r1)).to.equal("string")
				expect(innerOk).to.beTrue()
				expect(innerA).to.beNil()
				expect(type(innerB)).to.equal("string")
				expect(noDrawOf(a)).to.equal(false)
				expect(capture().IsCapturing()).to.equal(false)

				local pushes = 0

				for i = 1, #seq do
					if seq[i] == "PushRenderTarget" then pushes = pushes + 1 end
				end

				expect(pushes).to.equal(1)
			end
		},
		-- Render: refusals ------------------------------------------------------------------------------------------------------
		{
			-- fails if: a resolution that is not a power of two (or too small / too big / not an integer) reaches the engine
			name = "Render refuses a res that is not a power of two, above 4096, zero, negative, fractional or not a number",
			func = function()
				local bad = {100, 8192, 0, -64, 64.5, 3, 2 ^ 31, "64", math.huge, 0 / 0}
				local a = makeProp(false)

				for _, res in ipairs(bad) do
					local seq, _, ok, r1, r2 = renderOnce({Capture = function() return pixels(64) end}, validTile({res = res}))

					expect(ok).to.beTrue()
					expect(r1).to.beNil()
					expect(type(r2)).to.equal("string")
					expect(#seq).to.equal(0)
				end

				expect(noDrawOf(a)).to.equal(false)
				expect(capture().IsCapturing()).to.equal(false)
				expect(countHooks()).to.equal(0)
			end
		},
		{
			-- fails if: the largest legal resolution (4096) or a small one is refused
			name = "Render accepts the limits: 4, 512 and 4096 (the stand-in render accepts any size)",
			func = function()
				-- no real 4096 x 4096 target (64 MB of video memory): the engine's creation is replaced
				savedGlobals.GetRenderTargetEx = GetRenderTargetEx
				GetRenderTargetEx = function() return {fake = true} end
				need("ResetRTCache")()

				for _, res in ipairs({4, 512, 4096}) do
					local _, _, ok, r1 = renderOnce({Capture = function() return "" end}, validTile({res = res}))

					expect(ok).to.beTrue()
					-- the stand-in returns nothing of the right length: that is the length check's reason, not the res's
					expect(r1).to.beNil()
				end

				-- 512 with the right number of bytes goes all the way
				local _, _, ok, r1 = renderOnce({Capture = function() return pixels(512) end}, validTile({res = 512}))

				expect(ok).to.beTrue()
				expect(#r1).to.equal(512 * 512 * 4)
			end
		},
		{
			-- fails if: a malformed tile or level reaches the engine (tile or level nil, missing fields, wrong types, inverted slab, ids that differ)
			name = "Render refuses a malformed tile or level: nil, missing or fractional tx, ty, bad ppm, a level that is not a table, zlo >= zhi, NaN, level ids that differ",
			func = function()
				local a = makeProp(false)
				local cases = {
					{nil, validLevel()},
					{validTile(), nil},
					{"tile", validLevel()},
					{validTile(), "level"},
					{validTile({tx = "1"}), validLevel()},
					{validTile({tx = 1.5}), validLevel()},
					{validTile({ty = 0 / 0}), validLevel()},
					{validTile({ty = math.huge}), validLevel()},
					{validTile({ppm = 0}), validLevel()},
					{validTile({ppm = -3}), validLevel()},
					{validTile({ppm = "2"}), validLevel()},
					{validTile({level = 5}), validLevel()},
					{validTile({level = "b2"}), validLevel()},
					{validTile(), {id = "a1", zlo = 128, zhi = -32}},
					{validTile(), {id = "a1", zlo = 10, zhi = 10}},
					{validTile(), {id = "a1", zlo = 0 / 0, zhi = 10}},
					{validTile(), {id = "a1", zlo = 0, zhi = math.huge}},
					{validTile(), {id = "a1", zlo = "0", zhi = 10}},
					{validTile(), {id = 7, zlo = 0, zhi = 10}},
					{validTile(), {zlo = 0, zhi = 10}}
				}

				for i, c in ipairs(cases) do
					local seq, _, ok, r1, r2 = renderRaw({Capture = function() return pixels(64) end}, c[1], c[2])

					expect(ok).to.beTrue()
					expect(r1).to.beNil()
					expect(type(r2)).to.equal("string")
					expect(#seq).to.equal(0)
				end

				expect(noDrawOf(a)).to.equal(false)
				expect(capture().IsCapturing()).to.equal(false)
				expect(countHooks()).to.equal(0)
			end
		},
		-- Real alpha (wave 2): the void keeps alpha 0 ----------------------------------------------------------------------------
		{
			-- fails if: the target is cleared with an opaque alpha (the void would then be opaque black)
			name = "the target is cleared to transparent black: Clear(0, 0, 0, 0, true, true)",
			func = function()
				local _, args, ok = renderOnce({RenderView = function() end, Capture = function() return pixels(64) end})

				expect(ok).to.beTrue()
				expect(args.Clear.n).to.equal(6)
				expect(args.Clear[1]).to.equal(0)
				expect(args.Clear[2]).to.equal(0)
				expect(args.Clear[3]).to.equal(0)
				expect(args.Clear[4]).to.equal(0)
				expect(args.Clear[5]).to.equal(true)
				expect(args.Clear[6]).to.equal(true)
			end
		},
		{
			-- fails if: the depth is written to the alpha while the view renders (the alpha would not tell the void), or is not put back after
			name = "SetWriteDepthToDestAlpha(false) is set after Clear and before RenderView, and true again right after RenderView (and before the capture reads the bytes)",
			func = function()
				local seq = {}
				local writes = {}
				local stateDuringView

				stubRender(seq, {}, {
					RenderView = function() stateDuringView = writes[#writes] end,
					Capture = function() return pixels(64) end,
					SetWriteDepthToDestAlpha = function(v) writes[#writes + 1] = v end
				})

				local ok, r1 = pcall(capture().Render, validTile(), validLevel())

				expect(ok).to.beTrue()
				expect(type(r1)).to.equal("string")
				expect(#writes).to.equal(2)
				expect(writes[1]).to.equal(false)
				expect(writes[2]).to.equal(true)
				expect(stateDuringView).to.equal(false)

				local at = {}

				for i = 1, #seq do
					if seq[i] == "SetWriteDepthToDestAlpha" then
						at[#at + 1] = i
					else
						at[seq[i]] = i
					end
				end

				expect(at.Clear < at[1]).to.beTrue()
				expect(at[1] < at.RenderView).to.beTrue()
				expect(at.RenderView < at[2]).to.beTrue()
				expect(at[2] < at.Capture).to.beTrue()
			end
		},
		{
			-- fails if: an error in RenderView leaves the depth-to-alpha write off for the whole game (everything else drawn afterwards would be wrong)
			name = "a RenderView that raises: the depth write to the alpha is put back to true (once), after the failure",
			func = function()
				local writes = {}
				local _, _, ok, r1 = renderOnce({
					RenderView = function() error("capture test: RenderView exploded", 0) end,
					SetWriteDepthToDestAlpha = function(v) writes[#writes + 1] = v end
				})

				expect(ok).to.beTrue()
				expect(r1).to.beNil()
				expect(#writes).to.equal(2)
				expect(writes[1]).to.equal(false)
				expect(writes[2]).to.equal(true)
			end
		},
		{
			-- fails if: a failure before the view leaves the write off
			name = "a failure before the view (the push raises): the depth write is never left off",
			func = function()
				local writes = {}
				local _, _, ok, r1 = renderOnce({
					PushRenderTarget = function() error("capture test: push exploded", 0) end,
					SetWriteDepthToDestAlpha = function(v) writes[#writes + 1] = v end
				})

				expect(ok).to.beTrue()
				expect(r1).to.beNil()
				expect(#writes == 0 or writes[#writes] == true).to.beTrue()
			end
		},
		{
			-- fails if: the bytes are changed on the way (the alpha is the mask of the void: it must come back as render.Capture gave it)
			name = "the returned BGRA keeps its alpha: the bytes are not touched (alpha 0 and alpha 1 pixels come back as they were)",
			func = function()
				local res = 64
				local bytes = string.rep("\0\0\0\0", res * res - 2) .. "\9\8\7\1" .. "\0\0\5\0"
				local _, _, ok, r1 = renderOnce({Capture = function() return bytes end})

				expect(ok).to.beTrue()
				expect(r1 == bytes).to.beTrue()
				expect(select(4, string.byte(r1, #r1 - 7, #r1 - 4))).to.equal(1)
				expect(select(4, string.byte(r1, #r1 - 3, #r1))).to.equal(0)
			end
		},
		{
			-- fails if: the rule is the alpha alone (about 5 % of the pixels of alpha 0 carry a colour: geometry that writes alpha 0), or a black solid pixel is taken for void
			name = "IsVoid(b, g, r, a): void only when the alpha is 0 AND the colour is black; a coloured pixel of alpha 0 and a black pixel of alpha 1 are solid",
			func = function()
				local IsVoid = need("IsVoid")

				expect(IsVoid(0, 0, 0, 0)).to.equal(true)
				-- a black solid pixel (alpha 1, the geometry's alpha) is solid
				expect(IsVoid(0, 0, 0, 1)).to.equal(false)
				expect(IsVoid(0, 0, 0, 255)).to.equal(false)
				-- geometry that wrote alpha 0 but has a colour: solid, whichever channel carries it
				expect(IsVoid(5, 0, 0, 0)).to.equal(false)
				expect(IsVoid(0, 5, 0, 0)).to.equal(false)
				expect(IsVoid(0, 0, 5, 0)).to.equal(false)
				expect(IsVoid(200, 120, 40, 0)).to.equal(false)
				-- coloured and opaque
				expect(IsVoid(200, 120, 40, 255)).to.equal(false)
				expect(IsVoid(255, 255, 255, 1)).to.equal(false)
				-- nothing missing is void
				expect(IsVoid(nil, nil, nil, nil)).to.equal(false)
				expect(IsVoid(0, 0, 0)).to.equal(false)
			end
		},
		-- the background the engine paints for "nothing": alpha 255, whatever the colour (black on gm_funkis, d1_canals_01, gm_everpine_mall; a sky blue that drifts with the time on gm_boreas) -----
		-- the geometry's own alpha is 1, so the alpha 255 is the engine's fill. A few alpha-255 pixels of other colours exist at the edges of translucent geometry (0.01 to 0.7 % of the alpha-255 pixels,
		-- measured on funkis, canals, coast_07, everpine): only the colour of the fill is void.
		{
			-- fails if the rule reads only black, ignores a channel, or takes the geometry's alpha (1), the void (0), an alpha of 254 or a near colour for the fill
			name = "IsBackground(b, g, r, a, bg): only exactly the colour of bg with alpha 255 (black when no bg is given); other colours, other alphas, missing channels are not",
			func = function()
				local IsBackground = need("IsBackground")
				local BLUE = "\227\181\139\255" -- (r, g, b) = (139, 181, 227)

				expect(IsBackground(227, 181, 139, 255, BLUE)).to.equal(true)
				expect(IsBackground(227, 181, 139, 1, BLUE)).to.equal(false) -- geometry of that colour
				expect(IsBackground(227, 181, 139, 0, BLUE)).to.equal(false)
				expect(IsBackground(227, 181, 139, 254, BLUE)).to.equal(false)
				expect(IsBackground(228, 181, 139, 255, BLUE)).to.equal(false)
				expect(IsBackground(227, 182, 139, 255, BLUE)).to.equal(false)
				expect(IsBackground(227, 181, 140, 255, BLUE)).to.equal(false)
				expect(IsBackground(0, 0, 0, 255, BLUE)).to.equal(false) -- black is not the fill of a blue map
				expect(IsBackground(255, 255, 255, 255, "\255\255\255\255")).to.equal(true)
				expect(IsBackground(nil, nil, nil, nil, BLUE)).to.equal(false)
				expect(IsBackground(227, 181, 139, nil, BLUE)).to.equal(false)

				-- no bg: black
				expect(IsBackground(0, 0, 0, 255)).to.equal(true)
				expect(IsBackground(0, 0, 0, 1)).to.equal(false)
				expect(IsBackground(0, 0, 1, 255)).to.equal(false)
				expect(IsBackground(227, 181, 139, 255)).to.equal(false)
			end
		},
		{
			-- fails if BackgroundToVoid touches anything but the exact pixels of the fill, or does not return how many it changed, for any colour of fill (a colour with a 255 byte included)
			name = "BackgroundToVoid: the pixels of the fill become void (0, 0, 0, 0) whatever its colour; geometry, void, other colours and near colours stay as they are",
			func = function()
				local BackgroundToVoid = need("BackgroundToVoid")
				local V = "\0\0\0\0"

				for _, K in ipairs({"\0\0\0\255", "\227\181\139\255", "\255\255\255\255", "\1\2\3\255", "\255\0\7\255"}) do
					local function near(i) -- the colour of the fill with one channel one step off
						local t = {K:byte(1, 4)}

						t[i] = (t[i] + 1) % 256

						return string.char(t[1], t[2], t[3], 255)
					end

					local keep = {K:sub(1, 3) .. "\1", V, near(1), near(2), near(3), K:sub(1, 3) .. "\254", K:sub(1, 3) .. "\0", "\9\8\7\255"}
					local list = {K, keep[1], K, keep[2], K, K, keep[3], keep[4], K, keep[5], keep[6], keep[7], K, keep[8]}
					local want = {}

					for i = 1, #list do
						want[i] = list[i] == K and V or list[i]
					end

					local out, n = BackgroundToVoid(table.concat(list), K)

					expect(out == table.concat(want)).to.beTrue()
					expect(n).to.equal(6)
				end
			end
		},
		{
			-- fails if a black pixel at alpha 255 is changed when the fill is another colour (the dark edge pixels of geometry), or a coloured one when the fill is black
			name = "BackgroundToVoid: only the colour of bg is changed; the other opaque colours stay (a black pixel of a blue map, a blue pixel of a black map)",
			func = function()
				local BackgroundToVoid = need("BackgroundToVoid")
				local BLUE, BLACK = "\227\181\139\255", "\0\0\0\255"
				local s = BLUE .. BLACK .. BLUE .. BLACK .. BLACK

				local out, n = BackgroundToVoid(s, BLUE)

				expect(out == "\0\0\0\0" .. BLACK .. "\0\0\0\0" .. BLACK .. BLACK).to.beTrue()
				expect(n).to.equal(2)

				out, n = BackgroundToVoid(s, BLACK)
				expect(out == BLUE .. "\0\0\0\0" .. BLUE .. "\0\0\0\0\0\0\0\0").to.beTrue()
				expect(n).to.equal(3)

				-- no bg given: black, like the first version of the rule
				out, n = BackgroundToVoid(s)
				expect(out == BLUE .. "\0\0\0\0" .. BLUE .. "\0\0\0\0\0\0\0\0").to.beTrue()
				expect(n).to.equal(3)
			end
		},
		{
			-- fails if the bytes are matched without the alignment of the pixels: the colour bytes of the fill followed by 255 also appear across two pixels
			name = "BackgroundToVoid: the bytes of the fill that straddle two pixels are not a pixel of the fill and are not changed",
			func = function()
				local BackgroundToVoid = need("BackgroundToVoid")

				for _, K in ipairs({"\0\0\0\255", "\227\181\139\255"}) do
					-- pixel 1 = (x, c1, c2, c3), pixel 2 = (255, y, z, w): the bytes c1, c2, c3, 255 are at offset 2 of the string
					local straddle = "\5" .. K:sub(1, 3) .. "\255\7\7\7"
					local s = straddle .. K .. K
					local out, n = BackgroundToVoid(s, K)

					expect(out == straddle .. "\0\0\0\0\0\0\0\0").to.beTrue()
					expect(n).to.equal(2)

					local out2, n2 = BackgroundToVoid(straddle, K)

					expect(out2 == straddle).to.beTrue()
					expect(n2).to.equal(0)
				end
			end
		},
		{
			-- fails if a long run is cut at the size of the group the scan jumps by (four pixels), or if the pixel after a run is lost
			name = "BackgroundToVoid: runs of every length (1 pixel to a whole 64 x 64 picture, around every power of two) are replaced completely, and what follows is kept",
			func = function()
				local BackgroundToVoid = need("BackgroundToVoid")
				local V, X = "\0\0\0\0", "\9\9\9\1"
				local total = 64 * 64
				local lengths = {1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 63, 64, 65, 255, 256, 257, 1023, 1024, 1025, 4095, 4096, 4097, 4099}

				for _, K in ipairs({"\0\0\0\255", "\227\181\139\255"}) do
					for _, len in ipairs(lengths) do
						for _, start in ipairs({0, 1, 3}) do
							-- `start` coloured pixels, then `len` pixels of the fill, then a coloured pixel, then the fill up to the end
							local head = string.rep(X, start)
							local tail = math.max(0, total - start - len - 1)
							local s = head .. string.rep(K, len) .. X .. string.rep(K, tail)
							local want = head .. string.rep(V, len) .. X .. string.rep(V, tail)
							local out, n = BackgroundToVoid(s, K)

							expect(out == want).to.beTrue()
							expect(n).to.equal(len + tail)
						end
					end

					local out, n = BackgroundToVoid(string.rep(K, total), K)

					expect(out == string.rep(V, total)).to.beTrue()
					expect(n).to.equal(total)

					-- a pixel one step off in one channel inside a long run ends the run (it is geometry): the run is cut there and goes on after it
					for i = 1, 3 do
						local t = {K:byte(1, 4)}

						t[i] = (t[i] + 1) % 256

						local off = string.char(t[1], t[2], t[3], 255)
						local out2, n2 = BackgroundToVoid(string.rep(K, 37) .. off .. string.rep(K, 40), K)

						expect(out2 == string.rep(V, 37) .. off .. string.rep(V, 40)).to.beTrue()
						expect(n2).to.equal(77)
					end

					-- the geometry of the same colour (alpha 1) ends a run too, also when fewer than four pixels are left to look at
					local geo = K:sub(1, 3) .. "\1"

					for _, len in ipairs({1, 2, 3, 5, 6, 7}) do
						local out3, n3 = BackgroundToVoid(string.rep(K, len) .. geo, K)

						expect(out3 == string.rep(V, len) .. geo).to.beTrue()
						expect(n3).to.equal(len)
					end
				end
			end
		},
		{
			-- fails if a picture without the fill is copied, changed, or counted wrongly
			name = "BackgroundToVoid: a picture with no pixel of the fill gives the same string and 0; an empty string too",
			func = function()
				local BackgroundToVoid = need("BackgroundToVoid")
				local s = string.rep("\0\0\0\0", 100) .. string.rep("\3\4\4\1", 50) .. "\0\0\0\1" .. string.rep("\227\181\139\255", 3)
				local out, n = BackgroundToVoid(s)

				expect(out == s .. "").to.beTrue()
				expect(n).to.equal(0)

				out, n = BackgroundToVoid(s, "\5\5\5\255")
				expect(out == s).to.beTrue()
				expect(n).to.equal(0)

				local e, ne = BackgroundToVoid("")

				expect(e).to.equal("")
				expect(ne).to.equal(0)
			end
		},
		{
			-- fails if a bad argument raises an error or is accepted
			name = "BackgroundToVoid refuses what is not a picture (a value that is not a string, a length that is not a multiple of 4) and a bg that is not a pixel of alpha 255 (nil, reason)",
			func = function()
				local BackgroundToVoid = need("BackgroundToVoid")

				for _, bad in ipairs({5, true, {}, "\0\0\0\255\0"}) do
					local out, why = BackgroundToVoid(bad)

					expect(out).to.beNil()
					expect(type(why)).to.equal("string")
				end

				local out, why = BackgroundToVoid(nil)

				expect(out).to.beNil()
				expect(type(why)).to.equal("string")

				for _, bad in ipairs({5, true, {}, "", "\0\0\0", "\0\0\0\255\255", "\0\0\0\0", "\0\0\0\1"}) do
					out, why = BackgroundToVoid("\0\0\0\255", bad)
					expect(out).to.beNil()
					expect(type(why)).to.equal("string")
				end
			end
		},
		{
			-- fails if one pixel that is not the fill is overlooked (first, last, in the middle, around the groups of four) or if a picture of nothing but the fill is not recognised
			name = "IsAllBackground: true only when every pixel is exactly the fill; one other pixel anywhere gives false",
			func = function()
				local IsAllBackground = need("IsAllBackground")
				local total = 64 * 64

				for _, K in ipairs({"\0\0\0\255", "\227\181\139\255", "\255\255\255\255"}) do
					expect(IsAllBackground(string.rep(K, total), K)).to.equal(true)
					expect(IsAllBackground(K, K)).to.equal(true)

					-- the colour of the fill with one channel one step off (blue, green, red)
					local function near(i)
						local t = {K:byte(1, 4)}

						t[i] = (t[i] + 1) % 256

						return string.char(t[1], t[2], t[3], 255)
					end

					for _, other in ipairs({"\0\0\0\0", K:sub(1, 3) .. "\1", K:sub(1, 3) .. "\254", near(1), near(2), near(3), "\9\9\9\255"}) do
						for _, at in ipairs({0, 1, 3, 4, 5, 15, 16, 255, 256, 1023, 1024, 4094, 4095}) do
							local s = string.rep(K, at) .. other .. string.rep(K, total - at - 1)

							expect(IsAllBackground(s, K)).to.equal(false)
						end
					end
				end

				-- no bg: black
				expect(IsAllBackground(string.rep("\0\0\0\255", total))).to.equal(true)
				expect(IsAllBackground(string.rep("\227\181\139\255", total))).to.equal(false)
				-- the fill found at an offset that is not a multiple of 4 is not a pixel of the fill
				expect(IsAllBackground("\5\0\0\0" .. string.rep("\255\0\0\0", 3))).to.equal(false)
				expect(IsAllBackground("\0\0\0\255" .. "\5\0\0\0" .. "\255\0\0\0")).to.equal(false)
			end
		},
		{
			-- fails if an empty picture or a bad argument is called a picture of the fill, or raises
			name = "IsAllBackground: an empty string, a length that is not a multiple of 4, a value that is not a string or a bad bg is not a picture of nothing (nil, reason)",
			func = function()
				local IsAllBackground = need("IsAllBackground")

				for _, bad in ipairs({"", "\0\0\0\255\0", 7, true, {}}) do
					local r, why = IsAllBackground(bad)

					expect(r).to.beNil()
					expect(type(why)).to.equal("string")
				end

				local r, why = IsAllBackground(nil)

				expect(r).to.beNil()
				expect(type(why)).to.equal("string")

				r, why = IsAllBackground("\0\0\0\255", "\0\0\0")
				expect(r).to.beNil()
				expect(type(why)).to.equal("string")
			end
		},
		-- FindBackground: the colour of the fill of a picture. The fill is the colour that most of the alpha-255 pixels have, measured on a sample of the pixels (one in BACKGROUND_STEP).
		-- It drifts with the time on gm_boreas (123, 161, 201 then 128, 168, 209 within seconds), so it is read from the picture itself and not once per map.
		{
			-- fails if the fill is not found when it covers the picture, with a colour that has a 255 byte, or if it is not a pixel string of alpha 255
			name = "FindBackground: a picture that is mostly one colour at alpha 255 gives that colour as a pixel (alpha 255), whatever the geometry around it",
			func = function()
				local FindBackground = need("FindBackground")
				local total = 64 * 64

				for _, K in ipairs({"\0\0\0\255", "\227\181\139\255", "\255\255\255\255", "\255\0\7\255"}) do
					local pic = string.rep(K, total)

					expect(FindBackground(pic) == K).to.beTrue()

					-- 70 % of the fill, geometry of alpha 1 and a few dark opaque edge pixels
					local parts = {}

					for i = 0, total - 1 do
						parts[#parts + 1] = (i % 10 < 7) and K or ((i % 10 == 9 and i % 3 == 0) and "\20\30\22\255" or "\30\60\90\1")
					end

					expect(FindBackground(table.concat(parts)) == K).to.beTrue()
				end
			end
		},
		{
			-- fails if the sample is not the documented one (positions 0, STEP, 2 * STEP...), or if the thresholds are not the documented ones (a strict majority of the alpha-255 samples, at least MIN of them)
			name = "FindBackground: needs at least BACKGROUND_MIN_SAMPLES samples of that colour and a strict majority of the alpha-255 samples; otherwise nil (the picture has no fill)",
			func = function()
				local FindBackground = need("FindBackground")
				local C = capture()
				local step, min = C.BACKGROUND_STEP, C.BACKGROUND_MIN_SAMPLES

				expect(type(step)).to.equal("number")
				expect(type(min)).to.equal("number")

				local total = 64 * 64
				local K, L = "\227\181\139\255", "\9\8\7\255"

				-- a picture of geometry (alpha 1) with the sampled pixels set by index: set[sampleIndex] = pixel string (the first sample is the pixel 0)
				local function picture(set)
					local t = {}

					for i = 0, total - 1 do
						t[i + 1] = "\30\60\90\1"
					end

					for k, px in pairs(set) do
						t[k * step + 1] = px
					end

					return table.concat(t)
				end

				local function same(n, px)
					local set = {}

					for k = 0, n - 1 do
						set[k] = px
					end

					return set
				end

				expect(FindBackground(picture(same(min, K))) == K).to.beTrue()
				expect(FindBackground(picture(same(min - 1, K)))).to.beNil()
				expect(FindBackground(picture({}))).to.beNil()

				-- a strict majority of the alpha-255 samples: 20 against 20 is no answer, 21 against 20 is
				local tie = same(20, K)

				for k = 20, 39 do
					tie[k] = L
				end

				expect(FindBackground(picture(tie))).to.beNil()
				tie[40] = K
				expect(FindBackground(picture(tie)) == K).to.beTrue()

				-- strays only: every sampled pixel a different colour
				local strays = {}

				for k = 0, 40 do
					strays[k] = string.char(k, 2 * k, 3, 255)
				end

				expect(FindBackground(picture(strays))).to.beNil()

				-- pixels of the fill that are not sampled do not count
				local t = {}

				for i = 0, total - 1 do
					t[i + 1] = (i % step == 0) and "\30\60\90\1" or K
				end

				expect(FindBackground(table.concat(t))).to.beNil()

				-- alpha 0 (void) and alpha 254 samples are not alpha-255 samples: they neither help nor count against
				local mixed = same(min, K)

				for k = min, min + 30 do
					mixed[k] = (k % 2 == 0) and "\0\0\0\0" or "\227\181\139\254"
				end

				expect(FindBackground(picture(mixed)) == K).to.beTrue()
			end
		},
		{
			-- fails if a bad picture raises, or is answered with a colour
			name = "FindBackground refuses what is not a picture (a value that is not a string, a length that is not a multiple of 4, an empty string): nil, reason",
			func = function()
				local FindBackground = need("FindBackground")

				for _, bad in ipairs({5, true, {}, "\0\0\0\255\0", ""}) do
					local r, why = FindBackground(bad)

					expect(r).to.beNil()
					expect(type(why)).to.equal("string")
				end

				local r, why = FindBackground(nil)

				expect(r).to.beNil()
				expect(type(why)).to.equal("string")
			end
		},
		-- GetRT -----------------------------------------------------------------------------------------------------------------
		{
			-- fails if: the render target is created again at each call, or with another name, size or depth mode
			name = "GetRT: one render target per resolution, created once, named gry_minimap_rt_<res>, literal size, separate depth",
			func = function()
				local GetRT, Reset = need("GetRT"), need("ResetRTCache")
				local created = {}

				savedGlobals.GetRenderTargetEx = GetRenderTargetEx
				GetRenderTargetEx = function(name, w, h, sizeMode, depthMode, textureFlags, rtFlags, imageFormat)
					local rt = {fake = true, name = name}

					created[#created + 1] = {name = name, w = w, h = h, sizeMode = sizeMode, depthMode = depthMode, imageFormat = imageFormat, rt = rt}

					return rt
				end
				Reset()

				local first = GetRT(128)
				local again = GetRT(128)
				local other = GetRT(256)

				expect(first == again).to.beTrue()
				expect(first == other).to.beFalse()
				expect(#created).to.equal(2)
				expect(created[1].name).to.equal("gry_minimap_rt_128")
				expect(created[1].w).to.equal(128)
				expect(created[1].h).to.equal(128)
				expect(created[1].sizeMode).to.equal(RT_SIZE_LITERAL)
				expect(created[1].depthMode).to.equal(MATERIAL_RT_DEPTH_SEPARATE)
				expect(created[2].name).to.equal("gry_minimap_rt_256")
				expect(created[1].rt == first).to.beTrue()
			end
		},
		{
			-- fails if: GetRT creates a target for a resolution the engine cannot use
			name = "GetRT refuses a bad resolution (nil, reason) and creates nothing",
			func = function()
				local GetRT, Reset = need("GetRT"), need("ResetRTCache")
				local created = 0

				savedGlobals.GetRenderTargetEx = GetRenderTargetEx
				GetRenderTargetEx = function() created = created + 1 return {} end
				Reset()

				for _, res in ipairs({100, 8192, 0, -4, 64.5, "64"}) do
					local rt, why = GetRT(res)

					expect(rt).to.beNil()
					expect(type(why)).to.equal("string")
				end

				expect(created).to.equal(0)
			end
		},
		-- RenderTo and the arbitration of the frame (the big map shares the render with the minimap) ----------------------------------
		{
			-- fails without Capture.RenderTo (the big map would need a copy of the render), or when it reads the bytes instead of copying
			name = "RenderTo copies the picture into the caller's target before the shared one is popped: PushRenderTarget, Clear, RenderView, CopyRenderTargetToTexture, PopRenderTarget; render.Capture is never called",
			func = function()
				local RenderTo = need("RenderTo")
				local a = makeProp(false)
				local dest = {fake = "destination"}
				local seq, args = {}, {}

				stubRender(seq, args, {})

				local ok, r1, r2 = pcall(RenderTo, validTile(), validLevel(), dest)

				expect(ok).to.beTrue()
				expect(r1).to.equal(true)
				expect(r2).to.beNil()

				local order = {}

				for i = 1, #seq do
					local n = seq[i]

					if n == "PushRenderTarget" or n == "Clear" or n == "RenderView" or n == "Capture" or n == "CopyRenderTargetToTexture" or n == "PopRenderTarget" then
						order[#order + 1] = n
					end
				end

				expect(table.concat(order, ",")).to.equal("PushRenderTarget,Clear,RenderView,CopyRenderTargetToTexture,PopRenderTarget")
				expect(args.CopyRenderTargetToTexture[1] == dest).to.beTrue()
				-- the same render as Render: the shared target of that resolution, the entities hidden until the end, then back, no hook left
				expect(args.PushRenderTarget[1] == capture().GetRT(64)).to.beTrue()
				expect(noDrawOf(a)).to.equal(false)
				expect(countHooks()).to.equal(0)
				expect(capture().IsCapturing()).to.equal(false)
			end
		},
		{
			-- fails if a missing destination renders anyway (a picture nobody can read) or raises
			name = "RenderTo without a destination answers nil, a reason, and renders nothing",
			func = function()
				local RenderTo = need("RenderTo")
				local seq, args = {}, {}

				stubRender(seq, args, {})

				local ok, r1, r2 = pcall(RenderTo, validTile(), validLevel(), nil)

				expect(ok).to.beTrue()
				expect(r1).to.beNil()
				expect(type(r2)).to.equal("string")
				expect(#seq).to.equal(0)
			end
		},
		{
			-- fails if a copy that raises leaves the target pushed, the hooks installed or the entities hidden
			name = "RenderTo with a copy that raises: the shared target is popped, the hooks are removed, the entities are back, IsCapturing is false, it answers nil, reason",
			func = function()
				local RenderTo = need("RenderTo")
				local a = makeProp(false)
				local seq, args = {}, {}

				stubRender(seq, args, {CopyRenderTargetToTexture = function() error("copy exploded", 0) end})

				local ok, r1, r2 = pcall(RenderTo, validTile(), validLevel(), {})

				expect(ok).to.beTrue()
				expect(r1).to.beNil()
				expect(type(r2)).to.equal("string")
				expect(seq[#seq]).to.equal("PopRenderTarget")
				expect(noDrawOf(a)).to.equal(false)
				expect(countHooks()).to.equal(0)
				expect(capture().IsCapturing()).to.equal(false)
			end
		},
		{
			-- fails if RenderTo does not validate the tile and the level as Render does
			name = "RenderTo refuses a bad tile or level like Render (nil, reason, no render call)",
			func = function()
				local RenderTo = need("RenderTo")
				local seq, args = {}, {}

				stubRender(seq, args, {})

				local _, why = RenderTo(validTile({res = 100}), validLevel(), {})
				local _, why2 = RenderTo(validTile(), {id = "a1", zlo = 5, zhi = 5}, {})

				expect(type(why)).to.equal("string")
				expect(type(why2)).to.equal("string")
				expect(#seq).to.equal(0)
			end
		},
		{
			-- fails if two captures can be made in one frame whoever asks, or if the frame of the last one is not recorded
			name = "MayCapture: a frame where a capture ran is closed to everybody (Render and RenderTo record their frame), the next frame is open",
			func = function()
				local C = capture()
				local frame = 41

				savedGlobals.FrameNumber = FrameNumber
				FrameNumber = function() return frame end
				C.ResetFrame()

				expect(C.MayCapture("gen")).to.beTrue()

				local seq, args = {}, {}

				stubRender(seq, args, {Capture = function() return pixels(64) end})
				expect(C.Render(validTile(), validLevel()) ~= nil).to.beTrue()

				expect(C.MayCapture("gen")).to.beFalse()
				expect(C.MayCapture("map")).to.beFalse()
				expect(C.MayCapture("gen", 41)).to.beFalse()
				expect(C.MayCapture("gen", 42)).to.beTrue()

				frame = 42
				expect(C.MayCapture("gen")).to.beTrue()

				-- RenderTo records its frame too
				expect(C.RenderTo(validTile(), validLevel(), {})).to.equal(true)
				expect(C.MayCapture("map")).to.beFalse()
			end
		},
		{
			-- fails if the priority does not give the even frames to its owner, or takes the odd ones from the others
			name = "SetPriority(owner): the owner may capture in every frame, the others only in the odd ones; no priority, everybody every frame",
			func = function()
				local C = capture()

				C.ResetFrame()
				C.SetPriority("map")

				expect(C.MayCapture("map", 10)).to.beTrue()
				expect(C.MayCapture("map", 11)).to.beTrue()
				expect(C.MayCapture("gen", 10)).to.beFalse()
				expect(C.MayCapture("gen", 11)).to.beTrue()

				C.SetPriority(nil)
				expect(C.MayCapture("gen", 10)).to.beTrue()
			end
		}
	}
}
