-- Tests of the screen effect of a suit mode change (cl_mode_fx.lua), GLuaTest format, client realm. The rules are read from
-- the original game's flow graphs suit_armormode, suit_speedmode and suit_strengthmode (see
-- docs/superpowers/plans/2026-11-21-suit-mode-fx.md): a short colour grade that rises then falls, one tint per mode. The
-- camouflage has its own effect (cl_cloak_fx.lua) and is not repeated here.

local FX = GryMod.ModeFX
local Modes = GryMod.Modes

local saved = {}

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

-- a sample the way the Think hook builds it
local function sample(mode, alive, malfunction)
	return {mode = mode, alive = alive ~= false, malfunction = malfunction == true}
end

-- a state that has seen one sample at time 0 and has been alive for a long time
local function seen(mode)
	local state = FX.NewState()
	FX.Observe(state, sample(mode), -100, true)

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
				for _, mode in ipairs({Modes.CLOAK, Modes.DROP, 99, "armor"}) do
					expect(FX.Duration(mode)).to.equal(0)
					local o = r3(mode, 0.1)
					expect(o[1] + o[2] + o[3]).to.equal(0)
				end

				expect(FX.Duration(nil)).to.equal(0)
				expect(r3(nil, 0.1)[1]).to.equal(0)
			end
		},
		{
			name = "Observe: the first sample is only the reference, a change to another mode starts that mode's effect",
			func = function(state)
				local fresh = FX.NewState()
				expect(FX.Observe(fresh, sample(Modes.ARMOR), 0, true)).to.beNil()
				expect(FX.Observe(fresh, sample(Modes.ARMOR), 5, true)).to.beNil()
				expect(FX.Observe(fresh, sample(Modes.SPEED), 10, true)).to.equal(Modes.SPEED)
				expect(FX.Observe(fresh, sample(Modes.SPEED), 11, true)).to.beNil()
				expect(FX.Observe(fresh, sample(Modes.STRENGTH), 20, true)).to.equal(Modes.STRENGTH)
				expect(FX.Observe(fresh, sample(Modes.ARMOR), 30, true)).to.equal(Modes.ARMOR)
			end
		},
		{
			name = "Observe: the camouflage starts nothing here, leaving it starts the effect of the mode entered",
			func = function(state)
				local s = seen(Modes.ARMOR)
				expect(FX.Observe(s, sample(Modes.CLOAK), 10, true)).to.beNil()
				expect(FX.Observe(s, sample(Modes.SPEED), 20, true)).to.equal(Modes.SPEED)
				expect(FX.Observe(s, sample(Modes.CLOAK), 30, true)).to.beNil()
				expect(FX.Observe(s, sample(Modes.ARMOR), 40, true)).to.equal(Modes.ARMOR)
			end
		},
		{
			name = "Observe: nothing while dead (the mode is followed silently), nor in the first second after the respawn",
			func = function(state)
				local s = seen(Modes.SPEED)

				-- dies, and the server puts the suit back in armor before the player is alive again
				expect(FX.Observe(s, sample(Modes.SPEED, false), 10, true)).to.beNil()
				expect(FX.Observe(s, sample(Modes.ARMOR, false), 11, true)).to.beNil()

				-- alive: the mode is already armor, nothing changes
				expect(FX.Observe(s, sample(Modes.ARMOR, true), 12, true)).to.beNil()

				-- the mode message arrives a moment after the player is alive: still the spawn
				expect(FX.Observe(s, sample(Modes.SPEED, true), 12.5, true)).to.beNil()

				-- a real choice later is played
				expect(FX.Observe(s, sample(Modes.STRENGTH, true), 13.5, true)).to.equal(Modes.STRENGTH)
			end
		},
		{
			name = "Observe: no effect while the suit is down (the server forces armor mode), and none for it afterwards",
			func = function(state)
				local s = seen(Modes.SPEED)
				expect(FX.Observe(s, sample(Modes.ARMOR, true, true), 10, true)).to.beNil()
				expect(FX.Observe(s, sample(Modes.ARMOR, true, false), 11, true)).to.beNil()
				expect(FX.Observe(s, sample(Modes.SPEED, true, false), 20, true)).to.equal(Modes.SPEED)
			end
		},
		{
			name = "Observe: the malfunction flag that shows a moment after the forced armor mode takes the effect back (seen live: mode first, flag 50 ms later)",
			func = function(state)
				local s = seen(Modes.SPEED)
				expect(FX.Observe(s, sample(Modes.ARMOR, true, false), 10, true)).to.equal(Modes.ARMOR)
				expect(FX.Params(s, 10.02)).toNot.beNil()

				expect(FX.Observe(s, sample(Modes.ARMOR, true, true), 10.05, true)).to.beNil()
				expect(FX.Params(s, 10.05)).to.beNil()

				-- a flag that comes long after leaves a normal effect alone
				local late = seen(Modes.ARMOR)
				expect(FX.Observe(late, sample(Modes.SPEED, true, false), 10, true)).to.equal(Modes.SPEED)
				FX.Observe(late, sample(Modes.SPEED, true, true), 10.35, true)
				expect(FX.Params(late, 10.35)).toNot.beNil()
			end
		},
		{
			name = "Observe: the switch off plays nothing, and turning it on later does not replay a past change",
			func = function(state)
				local s = seen(Modes.ARMOR)
				expect(FX.Observe(s, sample(Modes.SPEED), 10, false)).to.beNil()
				expect(FX.Observe(s, sample(Modes.SPEED), 11, true)).to.beNil()
				expect(FX.Observe(s, sample(Modes.ARMOR), 20, true)).to.equal(Modes.ARMOR)
			end
		},
		{
			name = "Observe: a missing mode (the server has not said yet) changes nothing",
			func = function(state)
				local s = seen(Modes.SPEED)
				expect(FX.Observe(s, sample(nil), 10, true)).to.beNil()
				expect(FX.Observe(s, sample(Modes.SPEED), 11, true)).to.beNil()
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
			name = "the Think hook reads the player's mode: a change of mode starts the effect and the post hook",
			func = function(state)
				local now = 1000
				local me = fakeMe(Modes.ARMOR, true, false)
				stub(FX, "Now", function() return now end)
				stub(FX, "Enabled", function() return true end)
				stub(_G, "LocalPlayer", function() return me end)
				stub(_G, "DrawColorModify", function() end)
				stub(FX, "State", FX.NewState())

				local think = hook.GetTable().Think.GryModeFx
				expect(isfunction(think)).to.beTrue()

				think() -- the reference
				expect(paintHook()).to.beNil()

				me.NanosuitMode = Modes.SPEED
				now = 1010
				think()
				expect(isfunction(paintHook())).to.beTrue()
			end
		},
		{
			name = "the Think hook does nothing without a player, with the switch off, or while the suit is down",
			func = function(state)
				local now = 1000
				local me = fakeMe(Modes.ARMOR, true, false)
				local enabled = true
				stub(FX, "Now", function() return now end)
				stub(FX, "Enabled", function() return enabled end)
				stub(_G, "LocalPlayer", function() return nil end)
				stub(FX, "State", FX.NewState())

				local think = hook.GetTable().Think.GryModeFx
				think() -- no player: no error

				_G.LocalPlayer = function() return me end
				think()

				enabled = false
				me.NanosuitMode = Modes.SPEED
				now = 1010
				think()
				expect(paintHook()).to.beNil()

				enabled = true
				me.NanosuitMode = Modes.STRENGTH
				me.GetNW2Bool = function(_, name) return name == "GryMalfunction" end
				now = 1020
				think()
				expect(paintHook()).to.beNil()
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
		}
	}
}
