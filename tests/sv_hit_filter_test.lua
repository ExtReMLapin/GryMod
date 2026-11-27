-- Tests of the hit filters of the extension API (GryMod.API.AddHitFilter, server/sv_api.lua; the hook "Grymod damage handeling" of sv_health.lua and the
-- hit marker of the radar ask them), GLuaTest format, server realm. A filter says, for one hit on a player: nothing (the suit does what it always does),
-- "ignore" (the suit does NOTHING for this hit: no energy, no arrows, no hit marker, no malfunction, no sound) or "bypass" (the whole damage goes to the
-- health, the bar is not touched). Each case names the production change whose absence makes it fail.

local function ply()
	return player.GetAll()[1]
end

local function ours()
	return hook.GetTable().EntityTakeDamage["Grymod damage handeling"]
end

local function damage(amount, kind)
	local d = DamageInfo()

	d:SetDamage(amount)
	d:SetDamageType(kind or DMG_BULLET)
	d:SetAttacker(game.GetWorld())
	d:SetInflictor(game.GetWorld())

	return d
end

-- Runs fn with the network recorded and the reports of the suit counted, and the functions of `spied` ({table, name}) replaced by a counter that calls the
-- original, whatever happens inside. Returns the names of the messages sent and the counts by name.
local function run(fn, spied)
	local sent, counts = {}, {}
	local realStart, realSend = net.Start, net.Send
	local originals = {}

	net.Start = function(name)
		sent[#sent + 1] = name

		return true
	end
	net.Send = function() end

	for _, target in ipairs(spied or {}) do
		local tbl, name = target[1], target[2]

		originals[#originals + 1] = {tbl, name, tbl[name]}
		counts[name] = 0

		tbl[name] = function(...)
			counts[name] = counts[name] + 1

			return originals[#originals][3](...)
		end
	end

	local ok, err = pcall(fn)

	net.Start, net.Send = realStart, realSend

	for _, original in ipairs(originals) do
		original[1][original[2]] = original[3]
	end

	assert(ok, err)

	return sent, counts
end

local added = {}

local function add(id, fn, priority)
	added[#added + 1] = id

	return GryMod.API.AddHitFilter(id, fn, priority)
end

local savedConfig

return {
	groupName = "GryMod hit filters (server)",
	beforeAll = function()
		savedConfig = table.Copy(GryMod.Config)
	end,
	beforeEach = function()
		local p = ply()

		if not p:Alive() then
			p:Spawn()
		end

		p:GodDisable()
		p:SetHealth(p:GetMaxHealth())
		p:SetNW2Bool("GryDisabled", false)
		p:SetNW2Float("GryEnergy", 100)
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		p.next_health_regen = 0
		GryMod.Config = table.Copy(savedConfig)
		GryMod.Config.InfiniteArmor = false
	end,
	afterEach = function()
		for _, id in ipairs(added) do
			pcall(GryMod.API.RemoveHitFilter, id)
			pcall(GryMod.API.SafeCallReset, "hitfilter:" .. id)
		end

		added = {}

		local p = ply()

		if IsValid(p) then
			p:SetNW2Float("GryEnergy", 100)
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
			p:SetHealth(p:GetMaxHealth())
		end

		GryMod.Config = table.Copy(savedConfig)
	end,
	cases = {
		{
			-- fails when the API names do not exist, or when a bad id or function is accepted, or a second filter with the same id is added next to the first
			name = "AddHitFilter / RemoveHitFilter: valid ids and functions are accepted, bad ones refused, the same id replaces the filter, a feature is announced",
			func = function()
				local API = GryMod.API

				expect(API.Has("hitfilter")).to.beTrue()
				expect(add("t1", function() end)).to.beTrue()
				expect(select(1, API.AddHitFilter("", function() end))).to.equal(false)
				expect(select(1, API.AddHitFilter(12, function() end))).to.equal(false)
				expect(select(1, API.AddHitFilter("t2", "nope"))).to.equal(false)
				expect(select(1, API.AddHitFilter("t2", function() end, "high"))).to.equal(false)

				-- the same id: the new function replaces the old one
				local calls = {}

				add("t1", function() calls[#calls + 1] = "old" end)
				add("t1", function() calls[#calls + 1] = "new" end)
				API.HitVerdict(ply(), damage(1))
				expect(#calls).to.equal(1)
				expect(calls[1]).to.equal("new")

				expect(API.RemoveHitFilter("t1")).to.beTrue()
				expect(API.RemoveHitFilter("t1")).to.equal(false)
			end
		},
		{
			-- fails when a filter that answers nothing (or something else than "ignore" and "bypass") changes what the suit does with a hit
			name = "no filter, a filter that answers nil, and a filter that answers nonsense: the armor takes the hit as it always did",
			func = function()
				local p = ply()

				for _, answer in ipairs({"none", "nil", "nonsense", "true"}) do
					p:SetNW2Float("GryEnergy", 100)

					if answer == "nil" then
						add("t1", function() return nil end)
					elseif answer == "nonsense" then
						add("t1", function() return "banana" end)
					elseif answer == "true" then
						add("t1", function() return true end)
					end

					local d = damage(30)

					run(function()
						ours()(p, d)
					end)

					expect(p:GetNW2Float("GryEnergy")).to.equal(70)
					expect(d:GetDamage()).to.equal(0)
					GryMod.API.RemoveHitFilter("t1")
				end
			end
		},
		{
			-- fails when "ignore" lets any part of the suit work: the bar, the damage, the arrows or the hit marker (Feedback.OnHit), the malfunction (Malfunction.OnDamage),
			-- a sound or a message of the armor, the "armor absorbed" report
			name = "\"ignore\": no energy taken, the damage left as it is, no arrows, no hit marker, no malfunction, no message, no report",
			func = function()
				local p = ply()
				local d = damage(30)
				local reports = 0
				local realRun = hook.Run

				add("t1", function() return "ignore" end)

				hook.Run = function(name, ...)
					if name == "GryMod_ArmorAbsorbed" then
						reports = reports + 1
					end

					return realRun(name, ...)
				end

				local ok, err = pcall(function()
					local sent, counts = run(function()
						ours()(p, d)
					end, {{GryMod.Feedback, "OnHit"}, {GryMod.Malfunction, "OnDamage"}})

					expect(#sent).to.equal(0)
					expect(counts.OnHit).to.equal(0)
					expect(counts.OnDamage).to.equal(0)
				end)

				hook.Run = realRun
				assert(ok, err)

				expect(reports).to.equal(0)
				expect(p:GetNW2Float("GryEnergy")).to.equal(100)
				expect(d:GetDamage()).to.equal(30)
			end
		},
		{
			-- fails when the radar still marks the NPC that hit the player for an ignored hit (its hook runs on its own, in no fixed order: it must ask the same verdict)
			name = "\"ignore\": the radar does not mark the NPC that struck; without the filter it does",
			func = function()
				local p = ply()
				local npc = ents.Create("npc_zombie")

				npc:SetPos(p:GetPos() + Vector(300, 0, 0))
				npc:Spawn()

				local ok, err = pcall(function()
					local radarHook = hook.GetTable().EntityTakeDamage["GryMod radar"]
					local st = GryMod.Radar.State(p)

					local d = damage(10)

					d:SetAttacker(npc)
					d:SetInflictor(npc)

					st.markers[npc] = nil
					radarHook(p, d)
					expect(st.markers[npc]).to.exist()

					st.markers[npc] = nil
					add("t1", function() return "ignore" end)

					local d2 = damage(10)

					d2:SetAttacker(npc)
					d2:SetInflictor(npc)
					radarHook(p, d2)
					expect(st.markers[npc]).to.beNil()
					st.markers[npc] = nil
				end)

				npc:Remove()
				assert(ok, err)
			end
		},
		{
			-- fails when "bypass" touches the bar, or does not let the damage go to the health as it came, or forgets the wait before the health comes back (the tail of the hook)
			name = "\"bypass\": the bar is not touched, the whole damage goes on to the health, the regeneration waits as after any damage, no armor message",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
				p.next_health_regen = 0
				add("t1", function() return "bypass" end)

				local d = damage(30)
				local sent, counts = run(function()
					ours()(p, d)
				end, {{GryMod.Malfunction, "OnDamage"}})

				expect(p:GetNW2Float("GryEnergy")).to.equal(100)
				expect(d:GetDamage()).to.equal(30)
				expect(counts.OnDamage).to.equal(0)

				for _, name in ipairs(sent) do
					expect(name).notTo.equal("gry_armor_hit_sound")
				end

				expect(p.next_health_regen > CurTime()).to.beTrue()
				expect(p.health_on_dmg).to.equal(p:Health() - 30)
			end
		},
		{
			-- fails when "bypass" is read only in the armor mode, or the infinite armor still wipes the damage out
			name = "\"bypass\" in the other modes and with the infinite armor: the damage still goes to the health and the bar is not touched",
			func = function()
				local p = ply()

				add("t1", function() return "bypass" end)

				for _, mode in ipairs({GryMod.Modes.ARMOR, GryMod.Modes.SPEED, GryMod.Modes.CLOAK, GryMod.Modes.STRENGTH}) do
					for _, infinite in ipairs({false, true}) do
						p:SetNanosuitMode(mode, false)
						p:SetNW2Float("GryEnergy", 60)
						GryMod.Config.InfiniteArmor = infinite

						local d = damage(25)

						run(function()
							ours()(p, d)
						end)

						expect(d:GetDamage()).to.equal(25)
						expect(p:GetNW2Float("GryEnergy")).to.equal(60)
					end
				end
			end
		},
		{
			-- fails when the filters are not run by priority (the higher first), or when the first real answer does not win, or when a filter after it is still asked
			name = "several filters: the higher priority first, then the order of registration; the first answer wins and the others are not asked",
			func = function()
				local order = {}

				add("low", function() order[#order + 1] = "low" return "ignore" end, -5)
				add("mid1", function() order[#order + 1] = "mid1" end)
				add("high", function() order[#order + 1] = "high" return "bypass" end, 10)
				add("mid2", function() order[#order + 1] = "mid2" return "ignore" end)

				expect(GryMod.API.HitVerdict(ply(), damage(1))).to.equal("bypass")
				expect(table.concat(order, ",")).to.equal("high")

				GryMod.API.RemoveHitFilter("high")
				order = {}
				expect(GryMod.API.HitVerdict(ply(), damage(2))).to.equal("ignore")
				expect(table.concat(order, ",")).to.equal("mid1,mid2")
			end
		},
		{
			-- fails when a filter that raises an error stops the hit (the armor never works) or is never switched off, or when another addon's filter is lost because of it
			name = "a filter that raises an error is skipped (the next one answers); five in a row switch it off, and adding it again arms it again",
			func = function()
				local p = ply()
				local boom = 0

				add("bad", function() boom = boom + 1 error("filter failure") end, 10)
				add("good", function() return "ignore" end)

				for i = 1, GryMod.API.SafeCallLimit + 2 do
					expect(GryMod.API.HitVerdict(p, damage(i))).to.equal("ignore")
				end

				expect(boom).to.equal(GryMod.API.SafeCallLimit)
				expect(GryMod.API.SafeCallDisabled("hitfilter:bad")).to.beTrue()

				add("bad", function() return "bypass" end, 10)
				expect(GryMod.API.HitVerdict(p, damage(1))).to.equal("bypass")
			end
		},
		{
			-- fails when the two hooks that read a hit (the armor and the radar's marker) each run the filters: a filter that counts, or that is not free of side effects, would see
			-- the same hit twice
			name = "the filters run once per hit, however many of the suit's hooks ask for the verdict",
			func = function()
				local p = ply()
				local count = 0
				local d = damage(10)

				add("t1", function() count = count + 1 return "ignore" end)

				expect(GryMod.API.HitVerdict(p, d)).to.equal("ignore")
				expect(GryMod.API.HitVerdict(p, d)).to.equal("ignore")
				expect(count).to.equal(1)

				-- a new hit is a new question
				GryMod.API.HitVerdict(p, damage(10))
				expect(count).to.equal(2)
			end
		},
		{
			-- fails when the filter is given the wrong arguments
			name = "the filter is given the victim and the damage info",
			func = function()
				local p = ply()
				local gotPly, gotInfo
				local d = damage(10)

				add("t1", function(victim, info) gotPly, gotInfo = victim, info end)
				GryMod.API.HitVerdict(p, d)
				expect(gotPly).to.equal(p)
				expect(gotInfo).to.equal(d)
			end
		}
	}
}
