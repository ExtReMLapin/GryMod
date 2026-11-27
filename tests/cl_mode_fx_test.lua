-- Tests of the screen effect of a suit mode change (cl_mode_fx.lua), GLuaTest format, client realm. The rules are read from
-- the original game's flow graphs suit_armormode, suit_speedmode and suit_strengthmode (see
-- docs/superpowers/plans/2026-11-21-suit-mode-fx.md): a short colour grade that rises then falls, one tint per mode. The
-- camouflage has its own effect (cl_cloak_fx.lua) and is not repeated here.

local FX = GryMod.ModeFX
local Modes = GryMod.Modes

local saved = {}

-- The minimap's capture (lua/grymod/client/minimap/capture.lua) renders the map from above inside a render hook: the post effects must stay out of it.
-- The cases that need it say so through this stand-in, put back after each case (also when the case failed).
local realIsCapturing

local function standInCapturing(value)
	local capture = GryMod.Minimap.Capture

	if realIsCapturing == nil then
		realIsCapturing = capture.IsCapturing
	end

	capture.IsCapturing = function() return value end
end

local function putBackCapturing()
	if realIsCapturing ~= nil then
		pcall(function() GryMod.Minimap.Capture.IsCapturing = realIsCapturing end)
		realIsCapturing = nil
	end
end

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function restore()
	for i = #saved, 1, -1 do
		local entry = saved[i]
		entry[1][entry[2]] = entry[3]
	end

	saved = {}
end

local function paintHook()
	return hook.GetTable().RenderScreenspaceEffects and hook.GetTable().RenderScreenspaceEffects["GryModeFx"]
end

local function r3(mode, t)
	local r, g, b = FX.Offsets(mode, t)

	return {r, g, b}
end

-- a sample the way FX.TintNow builds it
local function sample(alive, malfunction)
	return {alive = alive ~= false, malfunction = malfunction == true}
end

-- a state whose last respawn was a long time ago
local function seen()
	local state = FX.NewState()
	FX.Spawn(state, -100)

	return state
end

local function fakeMe(mode, alive, malfunction)
	return {
		NanosuitMode = mode,
		IsValid = function() return true end,
		Alive = function() return alive end,
		GetNW2Bool = function(_, name) return name == "GryMalfunction" and malfunction or false end
	}
end

return {
	groupName = "GryMod suit mode screen effect",
	afterEach = function(state)
		putBackCapturing()
		restore()
		hook.Remove("RenderScreenspaceEffects", "GryModeFx")
	end,
	cases = {
		{
			name = "armor: blue rises to 0.15 in 0.1 s and is gone 0.4 s later (flow graph: yellow 0 to -0.15 in 0.1 s, back in 0.4 s)",
			func = function(state)
				expect(FX.Duration(Modes.ARMOR)).to.aboutEqual(0.5, 0.0001)

				local peak = r3(Modes.ARMOR, 0.1)
				expect(peak[1]).to.equal(0)
				expect(peak[2]).to.equal(0)
				expect(peak[3]).to.aboutEqual(0.15, 0.0001)

				expect(r3(Modes.ARMOR, 0.05)[3]).to.aboutEqual(0.075, 0.0001)
				expect(r3(Modes.ARMOR, 0.3)[3]).to.aboutEqual(0.075, 0.0001)
				expect(r3(Modes.ARMOR, 0.0)[3]).to.equal(0)
				expect(r3(Modes.ARMOR, 0.5)[3]).to.equal(0)
				expect(r3(Modes.ARMOR, 2)[3]).to.equal(0)
				expect(r3(Modes.ARMOR, -1)[3]).to.equal(0)
			end
		},
		{
			name = "speed: all three channels brighten to 0.2 in 0.15 s and fall back in 0.35 s (flow graph: black 0 to -0.2 in 0.15 s, back in 0.35 s)",
			func = function(state)
				expect(FX.Duration(Modes.SPEED)).to.aboutEqual(0.5, 0.0001)

				local peak = r3(Modes.SPEED, 0.15)
				expect(peak[1]).to.aboutEqual(0.2, 0.0001)
				expect(peak[2]).to.aboutEqual(0.2, 0.0001)
				expect(peak[3]).to.aboutEqual(0.2, 0.0001)

				expect(r3(Modes.SPEED, 0.075)[1]).to.aboutEqual(0.1, 0.0001)
				expect(r3(Modes.SPEED, 0.325)[2]).to.aboutEqual(0.1, 0.0001)
				expect(r3(Modes.SPEED, 0.5)[3]).to.equal(0)
			end
		},
		{
			name = "strength: red rises to 0.2 in 0.2 s and is gone 0.4 s later (flow graph: cyan 0 to -0.2 in 0.2 s, back in 0.4 s)",
			func = function(state)
				expect(FX.Duration(Modes.STRENGTH)).to.aboutEqual(0.6, 0.0001)

				local peak = r3(Modes.STRENGTH, 0.2)
				expect(peak[1]).to.aboutEqual(0.2, 0.0001)
				expect(peak[2]).to.equal(0)
				expect(peak[3]).to.equal(0)

				expect(r3(Modes.STRENGTH, 0.1)[1]).to.aboutEqual(0.1, 0.0001)
				expect(r3(Modes.STRENGTH, 0.4)[1]).to.aboutEqual(0.1, 0.0001)
				expect(r3(Modes.STRENGTH, 0.6)[1]).to.equal(0)
			end
		},
		{
			name = "no profile for the camouflage (cl_cloak_fx.lua has it), the drop, or anything else",
			func = function(state)
				for _, mode in ipairs({Modes.CLOAK, 4, 99, "armor"}) do
					expect(FX.Duration(mode)).to.equal(0)
					local o = r3(mode, 0.1)
					expect(o[1] + o[2] + o[3]).to.equal(0)
				end

				expect(FX.Duration(nil)).to.equal(0)
				expect(r3(nil, 0.1)[1]).to.equal(0)
			end
		},
		{
			name = "TintDue: a real change to a mode that has a tint gets it; the same mode again, the first mode known (nothing before it), or a mode without a tint does not",
			func = function(state)
				local s = seen()
				expect(FX.TintDue(s, Modes.ARMOR, Modes.SPEED, sample(), 10)).to.beTrue()
				expect(FX.TintDue(s, Modes.SPEED, Modes.STRENGTH, sample(), 10)).to.beTrue()
				expect(FX.TintDue(s, Modes.CLOAK, Modes.ARMOR, sample(), 10)).to.beTrue()
				expect(FX.TintDue(s, Modes.SPEED, Modes.SPEED, sample(), 10)).to.beFalse()
				expect(FX.TintDue(s, nil, Modes.SPEED, sample(), 10)).to.beFalse()
				expect(FX.TintDue(s, Modes.ARMOR, Modes.CLOAK, sample(), 10)).to.beFalse()
				expect(FX.TintDue(s, Modes.ARMOR, 4, sample(), 10)).to.beFalse()
				expect(FX.TintDue(s, Modes.ARMOR, nil, sample(), 10)).to.beFalse()
			end
		},
		{
			name = "TintDue: nothing while dead, nor in the first second after the respawn (the server puts the suit back in armor); a state with no respawn on record is not held back",
			func = function(state)
				local s = seen()
				expect(FX.TintDue(s, Modes.ARMOR, Modes.SPEED, sample(false), 10)).to.beFalse()

				-- the respawn message (net gry_spawn) is the stamp: the second after it holds the tint back
				FX.Spawn(s, 12)
				expect(FX.TintDue(s, Modes.ARMOR, Modes.SPEED, sample(true), 12)).to.beFalse()
				expect(FX.TintDue(s, Modes.ARMOR, Modes.SPEED, sample(true), 12.5)).to.beFalse()
				expect(FX.TintDue(s, Modes.ARMOR, Modes.SPEED, sample(true), 13)).to.beTrue()

				-- a file loaded into a game already running has seen no respawn: the player has been there for a while
				expect(FX.TintDue(FX.NewState(), Modes.ARMOR, Modes.SPEED, sample(true), 0.1)).to.beTrue()
			end
		},
		{
			name = "TintDue: no tint while the suit is down (the server forces armor mode)",
			func = function(state)
				local s = seen()
				expect(FX.TintDue(s, Modes.SPEED, Modes.ARMOR, sample(true, true), 10)).to.beFalse()
				expect(FX.TintDue(s, Modes.SPEED, Modes.ARMOR, sample(true, false), 10)).to.beTrue()
			end
		},
		{
			name = "Play starts the tint and remembers it; the malfunction flag or the respawn message that shows a moment after the forced armor mode takes it back (seen live: mode first, flag 50 ms later)",
			func = function(state)
				local s = seen()
				expect(FX.Play(s, Modes.ARMOR, 10)).to.beTrue()
				expect(FX.Params(s, 10.02)).toNot.beNil()

				FX.Withdraw(s, 10.05)
				expect(FX.Params(s, 10.05)).to.beNil()

				-- a respawn message right after a mode message (the order they arrive in is the engine's): the same
				local respawn = seen()
				FX.Play(respawn, Modes.STRENGTH, 20)
				FX.Spawn(respawn, 20.05)
				expect(FX.Params(respawn, 20.05)).to.beNil()
				expect(FX.TintDue(respawn, Modes.ARMOR, Modes.SPEED, sample(), 20.5)).to.beFalse()

				-- a flag that comes long after leaves a normal effect alone
				local late = seen()
				FX.Play(late, Modes.SPEED, 10)
				FX.Withdraw(late, 10.35)
				expect(FX.Params(late, 10.35)).toNot.beNil()

				-- nothing started, or already taken back: nothing to do
				FX.Withdraw(FX.NewState(), 10)
				FX.Withdraw(s, 10.06)

				-- no tint for the camouflage
				expect(FX.Play(seen(), Modes.CLOAK, 10)).to.beFalse()
			end
		},
		{
			name = "the event's mode data: the names and the numbers of the four modes, nothing else",
			func = function(state)
				expect(FX.ModeFromData("armor")).to.equal(Modes.ARMOR)
				expect(FX.ModeFromData("speed")).to.equal(Modes.SPEED)
				expect(FX.ModeFromData("strength")).to.equal(Modes.STRENGTH)
				expect(FX.ModeFromData("cloak")).to.equal(Modes.CLOAK)
				expect(FX.ModeFromData(Modes.SPEED)).to.equal(Modes.SPEED)
				expect(FX.ModeFromData(Modes.ARMOR)).to.equal(Modes.ARMOR)
				expect(FX.ModeFromData(4)).to.beNil()
				expect(FX.ModeFromData("nonsense")).to.beNil()
				expect(FX.ModeFromData(nil)).to.beNil()
				expect(FX.NameOf(Modes.STRENGTH)).to.equal("strength")
				expect(FX.NameOf(4)).to.beNil()
			end
		},
		{
			name = "Params: nothing when no effect runs, the offsets of the running one otherwise, then nothing once it is over",
			func = function(state)
				local s = FX.NewState()
				expect(FX.Params(s, 0)).to.beNil()

				FX.Start(s, Modes.STRENGTH, 100)
				local r, g, b = FX.Params(s, 100.2)
				expect(r).to.aboutEqual(0.2, 0.0001)
				expect(g).to.equal(0)
				expect(b).to.equal(0)

				expect(FX.Params(s, 100.65)).to.beNil()
				expect(FX.Params(s, 101)).to.beNil()
			end
		},
		{
			name = "Params: two effects at once add up (a quick switch), each one on its own clock",
			func = function(state)
				local s = FX.NewState()
				FX.Start(s, Modes.ARMOR, 10)
				FX.Start(s, Modes.STRENGTH, 10.2)

				-- armor at 0.2 s into it: 0.15 - (0.1 / 0.4) * 0.15 = 0.1125 ; strength at its start: 0
				local r, g, b = FX.Params(s, 10.2)
				expect(r).to.equal(0)
				expect(b).to.aboutEqual(0.1125, 0.0001)

				-- armor at 0.4 s: 0.0375 ; strength at 0.2 s: 0.2
				r, g, b = FX.Params(s, 10.4)
				expect(r).to.aboutEqual(0.2, 0.0001)
				expect(b).to.aboutEqual(0.0375, 0.0001)

				-- the armor one is over at 10.5, the strength one runs to 10.8
				r, g, b = FX.Params(s, 10.6)
				expect(r).to.aboutEqual(0.1, 0.0001)
				expect(b).to.equal(0)
			end
		},
		{
			name = "Start again while the effect runs: it restarts from zero",
			func = function(state)
				local s = FX.NewState()
				FX.Start(s, Modes.SPEED, 0)
				FX.Start(s, Modes.SPEED, 0.4)
				local r = FX.Params(s, 0.4)
				expect(r).to.equal(0)
				r = FX.Params(s, 0.55)
				expect(r).to.aboutEqual(0.2, 0.0001)
			end
		},
		{
			name = "the post hook exists only while an effect runs: added by Start, removed by itself when the effect is over",
			func = function(state)
				local now = 50
				stub(FX, "Now", function() return now end)
				stub(_G, "DrawColorModify", function() end)

				local s = FX.NewState()
				expect(paintHook()).to.beNil()

				FX.Start(s, Modes.SPEED, now)
				expect(isfunction(paintHook())).to.beTrue()

				now = 50.3
				paintHook()()
				expect(isfunction(paintHook())).to.beTrue()

				now = 51
				paintHook()()
				expect(paintHook()).to.beNil()
			end
		},
		{
			name = "the post hook asks for the colour grade of the moment: the red of the strength mode goes to the red offset only",
			func = function(state)
				local now = 10
				local seenColour
				stub(FX, "Now", function() return now end)
				stub(_G, "DrawColorModify", function(tbl)
					seenColour = {tbl["$pp_colour_addr"], tbl["$pp_colour_addg"], tbl["$pp_colour_addb"], tbl["$pp_colour_colour"], tbl["$pp_colour_brightness"], tbl["$pp_colour_contrast"]}
				end)

				local s = FX.NewState()
				FX.Start(s, Modes.STRENGTH, 10)
				now = 10.2
				paintHook()()

				expect(seenColour[1]).to.aboutEqual(0.2, 0.0001)
				expect(seenColour[2]).to.equal(0)
				expect(seenColour[3]).to.equal(0)
				-- nothing else is touched: saturation, brightness and contrast stay neutral
				expect(seenColour[4]).to.equal(1)
				expect(seenColour[5]).to.equal(0)
				expect(seenColour[6]).to.equal(1)
			end
		},
		{
			name = "the post hook of an effect that is over draws nothing and takes itself away",
			func = function(state)
				local now = 0
				local drawn = 0
				stub(FX, "Now", function() return now end)
				stub(_G, "DrawColorModify", function() drawn = drawn + 1 end)

				FX.Start(FX.NewState(), Modes.ARMOR, 0)
				now = 5
				paintHook()()
				expect(drawn).to.equal(0)
				expect(paintHook()).to.beNil()
			end
		},
		{
			name = "no Think hook: the bookkeeping rides on events (the respawn message, the networked flag, the arrival in game), nothing runs at every frame",
			func = function(state)
				expect(hook.GetTable().Think.GryModeFx).to.beNil()
				expect(isfunction(hook.GetTable().EntityNetworkedVarChanged.GryModeFx)).to.beTrue()
				expect(isfunction(hook.GetTable().InitPostEntity.GryModeFx)).to.beTrue()
			end
		},
		{
			name = "loading the file again leaves one hook of each kind and removes the Think of an older load",
			func = function(state)
				hook.Add("Think", "GryModeFx", function() end) -- the copy an older version left
				stub(FX, "Now", FX.Now) -- the load puts its own back
				stub(FX, "State", FX.State)

				include("grymod/client/cl_mode_fx.lua")

				local hooks = hook.GetTable()
				expect(hooks.Think.GryModeFx).to.beNil()
				expect(isfunction(hooks.EntityNetworkedVarChanged.GryModeFx)).to.beTrue()
				expect(isfunction(hooks.InitPostEntity.GryModeFx)).to.beTrue()

				-- hooks are keyed by name: a second load replaces, it does not add
				for _, event in ipairs({"EntityNetworkedVarChanged", "InitPostEntity"}) do
					local count = 0

					for name in pairs(hooks[event]) do
						if name == "GryModeFx" then count = count + 1 end
					end

					expect(count).to.equal(1)
				end
			end
		},
		{
			name = "the flag GryMalfunction turning on for the local player takes back a tint that started a moment ago; other variables, other entities, the flag turning off, or a late flag do not",
			func = function(state)
				local now = 1000
				local me = fakeMe(Modes.ARMOR, true, false)
				stub(FX, "Now", function() return now end)
				stub(_G, "LocalPlayer", function() return me end)
				stub(_G, "DrawColorModify", function() end)
				stub(FX, "State", seen())

				local changed = hook.GetTable().EntityNetworkedVarChanged.GryModeFx

				local function started(mode)
					FX.State = seen()
					FX.Play(FX.State, mode, now)
				end

				started(Modes.ARMOR)
				changed(me, "GryMalfunction", false, true)
				expect(FX.Params(FX.State, now)).to.beNil()

				for _, case in ipairs({
					{me, "GryEnergy", 0, true},
					{me, "GryMalfunction", true, false},
					{fakeMe(Modes.ARMOR, true, false), "GryMalfunction", false, true}
				}) do
					started(Modes.SPEED)
					now = now + 0.01
					changed(case[1], case[2], case[3], case[4])
					expect(FX.Params(FX.State, now)).toNot.beNil()
				end

				started(Modes.SPEED)
				now = now + 0.35
				changed(me, "GryMalfunction", false, true) -- long after the change: a normal effect, left alone
				expect(FX.Params(FX.State, now)).toNot.beNil()
			end
		},
		{
			name = "the arrival in game (InitPostEntity) counts as a respawn: no tint in the first second",
			func = function(state)
				local now = 1000
				stub(FX, "Now", function() return now end)
				stub(FX, "State", seen())

				hook.GetTable().InitPostEntity.GryModeFx()
				expect(FX.TintDue(FX.State, Modes.ARMOR, Modes.SPEED, sample(), now + 0.5)).to.beFalse()
				expect(FX.TintDue(FX.State, Modes.ARMOR, Modes.SPEED, sample(), now + 1)).to.beTrue()
			end
		},
		{
			name = "FX.Spawned stamps the respawn on the live state at the live time; the net message gry_spawn calls it",
			func = function(state)
				local now = 1000
				stub(FX, "Now", function() return now end)
				stub(FX, "State", seen())
				stub(timer, "Simple", function() end) -- the receiver also arms the key prompts

				FX.Spawned()
				expect(FX.TintDue(FX.State, Modes.ARMOR, Modes.SPEED, sample(), now + 0.5)).to.beFalse()
				expect(FX.TintDue(FX.State, Modes.ARMOR, Modes.SPEED, sample(), now + 1)).to.beTrue()

				FX.State = seen()
				local called = 0
				stub(FX, "Spawned", function() called = called + 1 end)
				local receiver = net.Receivers["gry_spawn"]
				expect(isfunction(receiver)).to.beTrue()
				receiver()
				expect(called).to.equal(1)
			end
		},
		{
			name = "the live decision (TintNow) reads the player on demand: no player, alive for a while and not down, down, dead",
			func = function(state)
				local now = 1000
				local me = fakeMe(Modes.ARMOR, true, false)
				stub(FX, "Now", function() return now end)
				stub(_G, "LocalPlayer", function() return nil end)
				stub(FX, "State", seen())

				expect(FX.TintNow(Modes.ARMOR, Modes.SPEED)).to.beFalse()

				_G.LocalPlayer = function() return me end
				expect(FX.TintNow(Modes.ARMOR, Modes.SPEED)).to.beTrue()

				me.GetNW2Bool = function(_, name) return name == "GryMalfunction" end
				expect(FX.TintNow(Modes.ARMOR, Modes.SPEED)).to.beFalse()

				me.GetNW2Bool = function() return false end
				me.Alive = function() return false end
				expect(FX.TintNow(Modes.ARMOR, Modes.SPEED)).to.beFalse()
			end
		},
		{
			name = "Enabled follows the switch gry_screenfx (the same one as the damage effects)",
			func = function(state)
				local convar = GetConVar("gry_screenfx")
				expect(convar).toNot.beNil()

				local before = convar:GetBool()
				local ok, err = pcall(function()
					convar:SetBool(false)
					expect(FX.Enabled()).to.beFalse()
					convar:SetBool(true)
					expect(FX.Enabled()).to.beTrue()
				end)

				convar:SetBool(before)
				assert(ok, err)
			end
		},
		{
			-- fails if: the post hook does not ask the minimap's capture before it draws
			name = "the post hook draws nothing while the minimap captures the map from above (and stays), and draws the colour grade as before otherwise",
			func = function(state)
				local now = 10
				local drawn = 0
				stub(FX, "Now", function() return now end)
				stub(_G, "DrawColorModify", function() drawn = drawn + 1 end)

				FX.Start(FX.NewState(), Modes.STRENGTH, 10)
				now = 10.2

				standInCapturing(true)
				paintHook()()
				expect(drawn).to.equal(0)
				expect(isfunction(paintHook())).to.beTrue()

				standInCapturing(false)
				paintHook()()
				expect(drawn).to.equal(1)
			end
		}
	}
}
