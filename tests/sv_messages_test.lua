-- Tests of the text lines on the server (lua/grymod/server/sv_messages.lua), GLuaTest format, server realm: GryMod.API.ShowMessage(ply,
-- text, opts) sends the HUD event "message" through the one message the HUD events use; the suit's own lines the server knows (the
-- camouflage refused at low health, "you killed a friendly") go the same way. The net functions are replaced by recorders, so nothing
-- reaches a real client; the relation and the sender of a line are replaced where a case needs it. Nothing here kills, hurts or cloaks
-- the real player, and everything is put back in afterEach inside a pcall.

local API = GryMod.API
local Messages = GryMod.Messages

local function ply()
	return player.GetAll()[1]
end

local saved = {}
local convarsSaved = {}
local real = {}
local sent, started, writes

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

local function spy()
	for _, n in ipairs({"Start", "Send", "WriteString", "WriteUInt", "WriteBool", "WriteDouble"}) do
		real[n] = net[n]
	end

	sent, started, writes = {}, {}, {}

	net.Start = function(name) started[#started + 1] = name end
	net.Send = function(recipients) sent[#sent + 1] = recipients end
	net.WriteString = function(v) writes[#writes + 1] = v end
	net.WriteUInt = function(v) writes[#writes + 1] = v end
	net.WriteBool = function(v) writes[#writes + 1] = v end
	net.WriteDouble = function(v) writes[#writes + 1] = v end
end

local function unspy()
	for n, f in pairs(real) do
		net[n] = f
	end

	real = {}
end

local function fakeEntity(isPlayer)
	return {
		IsValid = function() return true end,
		IsPlayer = function() return isPlayer end
	}
end

-- the strings and the numbers a message wrote, as a table name -> value (the order of the pairs is not the order they were sent in)
local function written()
	local fields = {}
	local count = writes[2]

	for i = 0, count - 1 do
		fields[writes[3 + i * 3]] = writes[5 + i * 3]
	end

	return writes[1], fields
end

return {
	groupName = "GryMod text lines, server side",
	beforeEach = function()
		local p = ply()
		if not p:Alive() then p:Spawn() end

		spy()
	end,
	afterEach = function()
		pcall(unspy)

		for i = #saved, 1, -1 do
			local entry = saved[i]
			pcall(function() entry[1][entry[2]] = entry[3] end)
		end

		saved = {}

		for name, value in pairs(convarsSaved) do
			pcall(function() GetConVar(name):SetString(value) end)
		end

		convarsSaved = {}
	end,
	cases = {
		{
			-- fails without GryMod.API.ShowMessage on the server
			name = "ShowMessage sends the HUD event \"message\" with the text and the options to the player, in one message",
			func = function()
				local p = ply()
				local ok, count = API.ShowMessage(p, "HELLO", {lane = "status", duration = 3})

				expect(ok).to.beTrue()
				expect(count).to.equal(1)
				expect(#started).to.equal(1)
				expect(started[1]).to.equal("gry_api_hud")
				expect(sent[1][1]).to.equal(p)

				local name, fields = written()
				expect(name).to.equal("message")
				expect(fields.text).to.equal("HELLO")
				expect(fields.lane).to.equal("status")
				expect(fields.duration).to.equal(3)
			end
		},
		{
			-- fails if a text that breaks the limits were sent anyway
			name = "ShowMessage refuses a text or an option that breaks the limits, with a reason, and sends nothing",
			func = function()
				local p = ply()

				for _, args in ipairs({{""}, {nil}, {string.rep("a", 129)}, {"x", {lane = "nowhere"}}, {"x", {duration = "long"}}, {"x", {sound = 4}}}) do
					local ok, reason = API.ShowMessage(p, args[1], args[2])
					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
				end

				-- no valid recipient is the HUD event's own answer
				local ok = API.ShowMessage(NULL, "HELLO")
				expect(ok).to.beFalse()
				expect(#sent).to.equal(0)
			end
		},
		{
			-- fails without Messages.SendLine
			name = "a suit line goes out by its key; an unknown key or something that is not a player is refused",
			func = function()
				local p = ply()

				expect(Messages.SendLine(p, "killed_friend")).to.beTrue()

				local name, fields = written()
				expect(name).to.equal("message")
				expect(fields.line).to.equal("killed_friend")
				expect(fields.text).to.beNil() -- the client has the text (and the player's own setting for the line)

				for _, args in ipairs({{p, "nothing"}, {NULL, "killed_friend"}, {game.GetWorld(), "killed_friend"}}) do
					expect(Messages.SendLine(args[1], args[2])).to.beFalse()
				end

				expect(#sent).to.equal(1)
			end
		},
		{
			-- fails without the setting gry_cloak_min_health
			name = "the camouflage is refused at the health of the setting or less; 0 is no rule",
			func = function()
				setConVar("gry_cloak_min_health", "0")
				expect(Messages.CloakRefusedAt(1)).to.beFalse()
				expect(Messages.CloakRefusedAt(100)).to.beFalse()

				setConVar("gry_cloak_min_health", "24")
				expect(Messages.CloakRefusedAt(24)).to.beTrue()
				expect(Messages.CloakRefusedAt(10)).to.beTrue()
				expect(Messages.CloakRefusedAt(25)).to.beFalse()
				expect(GetConVar("gry_cloak_min_health"):GetDefault()).to.equal("0")
			end
		},
		{
			-- fails without the veto hook
			name = "the veto of the mode change refuses the camouflage only, only when the rule says so, and says why to the player",
			func = function()
				local p = ply()
				local veto = hook.GetTable()["GryMod_CanSetMode"]["GryMessagesCloakHealth"]
				expect(veto).to.exist()

				stub(Messages, "CloakRefusedAt", function() return true end)
				expect(veto(p, GryMod.Modes.CLOAK)).to.beFalse()
				expect(#started).to.equal(1)

				local _, fields = written()
				expect(fields.line).to.equal("cloak_health")

				-- the other modes are never refused by it
				started, sent, writes = {}, {}, {}
				expect(veto(p, GryMod.Modes.SPEED)).to.beNil()
				expect(veto(p, GryMod.Modes.ARMOR)).to.beNil()
				expect(#started).to.equal(0)

				-- the rule says no: nothing is refused, nothing is said
				Messages.CloakRefusedAt = function() return false end
				expect(veto(p, GryMod.Modes.CLOAK)).to.beNil()
				expect(#started).to.equal(0)
			end
		},
		{
			-- fails without Messages.FriendlyKiller
			name = "the player who kills an ally is told; a hostile, a neutral, himself, a kill by something that is not a player are not",
			func = function()
				local player1, victim = fakeEntity(true), fakeEntity(false)
				local relation = "ally"

				stub(API, "Relation", function() return relation end)

				expect(Messages.FriendlyKiller(player1, victim)).to.equal(player1)

				for _, other in ipairs({"hostile", "neutral"}) do
					relation = other
					expect(Messages.FriendlyKiller(player1, victim)).to.beNil()
				end

				relation = "ally"
				expect(Messages.FriendlyKiller(player1, player1)).to.beNil()
				expect(Messages.FriendlyKiller(fakeEntity(false), victim)).to.beNil() -- the killer is an NPC, a trap, the world
				expect(Messages.FriendlyKiller(NULL, victim)).to.beNil()
				expect(Messages.FriendlyKiller(player1, NULL)).to.beNil()
			end
		},
		{
			-- fails without the hooks of the kills
			name = "an NPC that dies and a player that dies tell the killer through the same line, \"killed_friend\"",
			func = function()
				local told = {}
				local killer = fakeEntity(true)

				stub(Messages, "FriendlyKiller", function(attacker) return attacker == killer and killer or nil end)
				stub(Messages, "SendLine", function(target, key) told[#told + 1] = {target, key} return true end)

				local npcHook = hook.GetTable()["OnNPCKilled"]["GryMessagesFriendly"]
				local playerHook = hook.GetTable()["PlayerDeath"]["GryMessagesFriendly"]
				expect(npcHook).to.exist()
				expect(playerHook).to.exist()

				npcHook(fakeEntity(false), killer, killer)
				expect(#told).to.equal(1)
				expect(told[1][1]).to.equal(killer)
				expect(told[1][2]).to.equal("killed_friend")

				playerHook(fakeEntity(true), killer, killer)
				expect(#told).to.equal(2)

				-- somebody else killed it: nobody is told
				npcHook(fakeEntity(false), fakeEntity(true), killer)
				playerHook(fakeEntity(true), killer, fakeEntity(false))
				expect(#told).to.equal(2)
			end
		}
	}
}
