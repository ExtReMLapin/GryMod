-- Tests of the objective banner (GryMod.ObjectivesBanner, lua/grymod/client/cl_objectives_banner.lua), GLuaTest format, client realm. When an objective is
-- added, finished or failed, the top lane of the text line shows "<NEW OBJECTIVE | OBJECTIVE COMPLETED | OBJECTIVE FAILED>: <title>" and plays a sound, as ONE HUD
-- event ("objective"): the original plays pda_update for an objective that arrives (and for a failed one) and objective_completed for a finished one. The list
-- sent when the player joins is silent. The engine is replaced where a case needs it (the text line, the sound, the HUD event, the objectives' mirror) and put
-- back in afterEach inside a pcall. Each case names the production change whose absence makes it fail.

local Banner = GryMod.ObjectivesBanner
local API = GryMod.API
local Obj = GryMod.Objectives

local saved = {}
local convarsSaved = {}
local madeHooks = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function setConVar(name, value)
	local convar = GetConVar(name)

	if convarsSaved[name] == nil then
		convarsSaved[name] = convar:GetString()
	end

	convar:SetString(value)
end

local function restore()
	for i = #saved, 1, -1 do
		local entry = saved[i]
		entry[1][entry[2]] = entry[3]
	end

	saved = {}

	for name, value in pairs(convarsSaved) do
		GetConVar(name):SetString(value)
	end

	convarsSaved = {}
end

local function objective(extra)
	local o = {id = "a", title = "Find the key", description = "", primary = true, main = false, state = "active", pos = Vector(0, 0, 0), radar = true, marker = true}

	for k, v in pairs(extra or {}) do
		o[k] = v
	end

	return o
end

local function rec(id, extra)
	local r = {id = id, title = "Title " .. id, description = "", primary = true, state = "active", main = false, radar = true, marker = true, pos = Vector(1, 2, 3), entIndex = 0}

	for k, v in pairs(extra or {}) do
		r[k] = v
	end

	return r
end

return {
	groupName = "GryMod objective banner",
	beforeEach = function()
		madeHooks = {}
		Obj.Reset()
		setConVar("gry_msg_objectives", "1")
		setConVar("gry_hud_messages", "1")
	end,
	afterEach = function()
		pcall(function()
			for _, h in ipairs(madeHooks) do
				hook.Remove(h[1], h[2])
			end
		end)
		pcall(Obj.Reset)
		pcall(function()
			if GryMod.FlashMessages then
				GryMod.FlashMessages.Reset()
			end
		end)
		pcall(restore)
	end,
	cases = {
		{
			-- fails without Banner.Decide
			name = "Decide: a new active objective is 'added', a finished one 'completed', a failed one 'failed'; a change that is not of the state says nothing",
			func = function()
				expect(Banner.Decide("added", objective())).to.equal("added")
				expect(Banner.Decide("added", objective({state = "done"}))).to.equal("completed")
				expect(Banner.Decide("added", objective({state = "failed"}))).to.equal("failed")

				expect(Banner.Decide("changed", objective({state = "done"}), "active")).to.equal("completed")
				expect(Banner.Decide("changed", objective({state = "failed"}), "active")).to.equal("failed")
				expect(Banner.Decide("changed", objective({state = "active"}), "done")).to.equal("added")

				-- a new title, the main flag, the primary flag: not news
				expect(Banner.Decide("changed", objective({state = "active"}), "active")).to.beNil()
				expect(Banner.Decide("changed", objective({state = "done"}), "done")).to.beNil()

				expect(Banner.Decide("removed", objective())).to.beNil()
				expect(Banner.Decide("added", objective({title = ""}))).to.beNil()
			end
		},
		{
			-- fails without the `syncing` argument of Banner.Decide: the list sent at join would show one banner for each objective
			name = "Decide: nothing is said while a full list arrives (the list sent when the player joins)",
			func = function()
				expect(Banner.Decide("added", objective(), nil, true)).to.beNil()
				expect(Banner.Decide("added", objective({state = "done"}), nil, true)).to.beNil()
				expect(Banner.Decide("changed", objective({state = "done"}), "active", true)).to.beNil()
			end
		},
		{
			-- fails without Banner.Text and the keys in hud_boot_strings.lua
			name = "Text: the translated prefix, a colon and the title; a long title is cut so that the line is accepted",
			func = function()
				expect(Banner.Text("added", "Find the key")).to.equal("NEW OBJECTIVE: Find the key")
				expect(Banner.Text("completed", "Find the key")).to.equal("OBJECTIVE COMPLETED: Find the key")
				expect(Banner.Text("failed", "Find the key")).to.equal("OBJECTIVE FAILED: Find the key")
				expect(Banner.Text("added", "  two\n words ")).to.equal("NEW OBJECTIVE: two words")
				expect(Banner.Text("nonsense", "x")).to.beNil()
				expect(Banner.Text("added", "")).to.beNil()

				local long = Banner.Text("completed", string.rep("w", 200))
				expect(#long <= GryMod.Messages.MAX_TEXT).to.beTrue()
				expect(string.sub(long, -3)).to.equal("...")
				expect(string.sub(long, 1, 20)).to.equal("OBJECTIVE COMPLETED:")
			end
		},
		{
			-- fails without Banner.Handle: the event shows the line on the top lane with the sound of the kind
			name = "Handle: the line goes to the top lane with pda_updated for 'added' and 'failed', hud_mission_accomplished for 'completed'",
			func = function()
				local shown = {}

				stub(API, "ShowMessage", function(text, opts)
					shown[#shown + 1] = {text, opts}

					return true
				end)

				Banner.Handle({kind = "added", title = "Find the key"})
				Banner.Handle({kind = "completed", title = "Find the key"})
				Banner.Handle({kind = "failed", title = "Find the key"})

				expect(#shown).to.equal(3)
				expect(shown[1][1]).to.equal("NEW OBJECTIVE: Find the key")
				expect(shown[1][2].lane).to.equal("top")
				expect(shown[1][2].sound).to.equal("grymod/hud/pda_updated.wav")
				expect(shown[2][2].sound).to.equal("grymod/hud/hud_mission_accomplished.wav")
				expect(shown[3][2].sound).to.equal("grymod/hud/pda_updated.wav")

				-- data that is not valid is ignored, never an error
				expect(Banner.Handle(nil)).to.beFalse()
				expect(Banner.Handle({kind = "x", title = "t"})).to.beFalse()
				expect(Banner.Handle({kind = "added"})).to.beFalse()
				expect(#shown).to.equal(3)
			end
		},
		{
			-- fails without the switch gry_msg_objectives in Handle: the player turns the banner and its sound off together
			name = "Handle: gry_msg_objectives 0 shows no line and plays no sound; it is on by default",
			func = function()
				local shown = 0

				stub(API, "ShowMessage", function() shown = shown + 1 return true end)
				expect(GetConVar("gry_msg_objectives"):GetDefault()).to.equal("1")

				setConVar("gry_msg_objectives", "0")
				Banner.Handle({kind = "added", title = "x"})
				expect(shown).to.equal(0)
			end
		},
		{
			-- fails without the hooks: the objective hooks of the client tell the banner
			name = "the hooks GryMod_ObjectiveAdded / Changed run the event 'objective' once for a real change",
			func = function()
				local events = {}

				stub(API, "HUDEvent", function(name, data)
					events[#events + 1] = {name, data}

					return true
				end)

				local added = hook.GetTable()["GryMod_ObjectiveAdded"]["GryObjectiveBanner"]
				local changed = hook.GetTable()["GryMod_ObjectiveChanged"]["GryObjectiveBanner"]
				expect(added).to.exist()
				expect(changed).to.exist()

				added("a", objective())
				expect(#events).to.equal(1)
				expect(events[1][1]).to.equal("objective")
				expect(events[1][2].kind).to.equal("added")
				expect(events[1][2].title).to.equal("Find the key")

				changed("a", objective({state = "done"}), "active")
				expect(#events).to.equal(2)
				expect(events[2][2].kind).to.equal("completed")

				changed("a", objective({state = "done", main = true}), "done")
				expect(#events).to.equal(2)
			end
		},
		{
			-- fails without Obj.Syncing being read by the listener: the join list through the REAL mirror is silent, a live add afterwards is not
			name = "the list sent at join is silent (BEGIN ... END through the mirror), a live add and a live finish are not",
			func = function()
				local events = {}

				stub(API, "HUDEvent", function(name, data)
					events[#events + 1] = data.kind .. ":" .. data.title

					return true
				end)

				Obj.ApplyBegin()
				Obj.ApplySet(rec("one"))
				Obj.ApplySet(rec("two", {state = "done"}))
				Obj.ApplyEnd()
				expect(#events).to.equal(0)

				Obj.ApplySet(rec("three"))
				Obj.ApplySet(rec("one", {state = "done"}))
				expect(#events).to.equal(2)
				expect(events[1]).to.equal("added:Title three")
				expect(events[2]).to.equal("completed:Title one")
			end
		},
		{
			-- fails without the registration of the event: the debug window and the other addons find it through the HUD event registry
			name = "the event 'objective' is registered with a variant for each kind (the debug window lists them)",
			func = function()
				local found = false

				for _, name in ipairs(API.ListHUDEvents()) do
					if name == "objective" then
						found = true
					end
				end

				expect(found).to.beTrue()

				local info = API.GetHUDEventInfo("objective")
				expect(#info.variants).to.equal(3)
				expect(info.variants[1].data.kind).to.equal("added")
			end
		},
		{
			-- fails without Handle calling the real text line: line and sound together through the whole chain (the text line module, its lane, the mix)
			name = "through the real text line: the top lane holds the line and the sound of the kind is played once",
			func = function()
				local Messages = GryMod.FlashMessages
				expect(Messages).to.exist()

				local played = {}

				stub(GryMod, "PlaySound", function(path) played[#played + 1] = path end)
				stub(GryMod.FlashHUD, "Enabled", function() return true end)
				Messages.Reset()

				Banner.Handle({kind = "completed", title = "Find the key"})

				local texts = Messages.Texts("top")
				expect(texts[#texts]).to.equal("OBJECTIVE COMPLETED: Find the key")
				expect(#played).to.equal(1)
				expect(played[1]).to.equal("grymod/hud/hud_mission_accomplished.wav")
			end
		},
		{
			-- fails when a point the player put on the map announces itself as a new objective (the player made it: it is no news)
			name = "Decide: an own objective (a private point of the player) says nothing, whatever happens to it",
			func = function()
				expect(Banner.Decide("added", objective({own = true}))).to.beNil()
				expect(Banner.Decide("changed", objective({own = true, state = "done"}), "active")).to.beNil()
				expect(Banner.Decide("added", objective({own = false}))).to.equal("added")
			end
		}
	}
}
