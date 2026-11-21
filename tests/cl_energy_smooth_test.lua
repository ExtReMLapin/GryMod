-- The energy shown by the HUD (cl_energy_smooth.lua), GLuaTest format, client realm.
--
-- The server tells the client the energy and its rate of change at every tick (gry_energy message; the networked
-- float alone only arrives about every 0.1 s). The original game gives its HUD the energy at every frame, so the
-- client predicts between two ticks and reconciles when a new value comes. These tests play a server and a client
-- through time, with frame rates and update rates of their own, and look at what the HUD would draw.
-- See docs/superpowers/plans/2026-11-21-energy-smooth.md.

local savedConvars = {}

local function remember(name)
	local c = GetConVar(name)
	savedConvars[name] = c and c:GetString()
end

-- Plays `seconds` of a server whose real energy is truth(t) with rate(t), told every 1/updateHz seconds, to a client
-- that draws every 1/fps seconds. predictFn(t) says whether the client may predict (default yes).
local function play(opts)
	local sm = GryMod.NewEnergySmooth()
	local frames = {}
	local dt = 1 / opts.fps
	local tick = 1 / opts.updateHz
	local nextTick = opts.firstTick or 0
	local sample = {truth = opts.truth(0), rate = opts.rate(0), t = 0}
	local resetAt = opts.resetAt

	for i = 0, math.floor(opts.seconds * opts.fps) do
		local t = i * dt
		local received = false

		while nextTick <= t + 1e-9 do
			if not opts.dropTick or not opts.dropTick(nextTick) then
				sample = {truth = opts.truth(nextTick), rate = opts.rate(nextTick), t = nextTick}
				received = true
			end

			nextTick = nextTick + tick
		end

		if resetAt and resetAt(t) then
			sm:Reset()
		end

		local predict = true

		if opts.predictFn then
			predict = opts.predictFn(t)
		end

		local shown = sm:Update(sample.truth, sample.rate, t, predict)
		frames[#frames + 1] = {t = t, shown = shown, real = opts.truth(t), rate = opts.rate(t), sample = sample.truth, received = received}
	end

	return frames
end

local function maxStep(frames, from)
	local worst = 0

	for i = 2, #frames do
		if not from or frames[i].t >= from then
			-- what the bar may move by in a frame: the rate of the moment, plus half a point of slack
			local allowed = math.max(math.abs(frames[i].rate), math.abs(frames[i - 1].rate)) * (frames[i].t - frames[i - 1].t)
			worst = math.max(worst, math.abs(frames[i].shown - frames[i - 1].shown) - allowed)
		end
	end

	return worst
end

local function monotone(frames, direction, from, to)
	for i = 2, #frames do
		if (not from or frames[i].t >= from) and (not to or frames[i].t <= to) and (frames[i].shown - frames[i - 1].shown) * direction < -1e-7 then
			return false, frames[i].t
		end
	end

	return true
end

local function maxError(frames, from, to)
	local worst = 0

	for _, f in ipairs(frames) do
		if f.t >= (from or 0) and f.t <= (to or math.huge) then
			worst = math.max(worst, math.abs(f.shown - f.real))
		end
	end

	return worst
end

local function distinctFraction(frames, from, to)
	local changed, n = 0, 0

	for i = 2, #frames do
		if frames[i].t >= (from or 0) and frames[i].t <= (to or math.huge) then
			n = n + 1

			if frames[i].shown ~= frames[i - 1].shown then
				changed = changed + 1
			end
		end
	end

	return changed / math.max(n, 1)
end

local function inRange(frames)
	for _, f in ipairs(frames) do
		if f.shown < 0 or f.shown > 100 then
			return false, f
		end
	end

	return true
end

-- the sprint of the Crysis rules: 42.5 a second above 20, 1.5 under it
local function sprintTruth(t)
	if t < 0 then
		return 100
	end

	local toTwenty = 80 / 42.5

	if t < toTwenty then
		return 100 - 42.5 * t
	end

	return math.max(0, 20 - 1.5 * (t - toTwenty))
end

local function sprintRate(t)
	return t < 80 / 42.5 and -42.5 or -1.5
end

-- What a frame may move by beyond the movement of its duration: a point with 33 updates a second or more at 60
-- frames a second and more (the realistic cases). The bar cannot know how old an update is (up to one update
-- interval) and moves by the difference: with 15 updates a second, or 20 frames a second, that is up to 2 points (one
-- server step of 2.8 at 15 updates).
local function stepSlack(fps, updateHz)
	return (fps >= 60 and updateHz >= 33) and 1 or 2
end

local RATES = {{fps = 20, updateHz = 15}, {fps = 20, updateHz = 66}, {fps = 60, updateHz = 15}, {fps = 60, updateHz = 33}, {fps = 60, updateHz = 66}, {fps = 144, updateHz = 15}, {fps = 144, updateHz = 33}, {fps = 144, updateHz = 66}, {fps = 166, updateHz = 66}}

local function each(fn)
	for _, r in ipairs(RATES) do
		local ok, err = pcall(fn, r.fps, r.updateHz)

		if not ok then
			if type(err) == "table" then
				err = err.message or util.TableToJSON(err)
			end

			error(string.format("at %d fps with %d updates a second: %s", r.fps, r.updateHz, tostring(err)), 0)
		end
	end
end

return {
	groupName = "GryMod energy smoothing",
	beforeAll = function()
		remember("gry_hud_energy_smooth")
	end,
	beforeEach = function()
		GetConVar("gry_hud_energy_smooth"):SetInt(1)
	end,
	afterAll = function()
		if savedConvars.gry_hud_energy_smooth and GetConVar("gry_hud_energy_smooth") then
			GetConVar("gry_hud_energy_smooth"):SetString(savedConvars.gry_hud_energy_smooth)
		end
	end,
	cases = {
		{
			name = "gry_hud_energy_smooth exists, on by default",
			func = function()
				local c = GetConVar("gry_hud_energy_smooth")
				expect(c ~= nil).to.beTrue()
				expect(c:GetDefault()).to.equal("1")
			end
		},
		{
			name = "a sprint of 2 s: the bar moves at every frame, never back, in steps no bigger than the movement, and stays on the real value, at 20 to 166 fps and 15 to 66 updates a second",
			func = function()
				each(function(fps, updateHz)
					local frames = play({fps = fps, updateHz = updateHz, seconds = 2, truth = sprintTruth, rate = sprintRate})
					local ok, at = monotone(frames, -1)
					expect(ok).to.beTrue()
					expect(maxStep(frames)).to.beLessThan(stepSlack(fps, updateHz))
					expect(maxError(frames)).to.beLessThan(updateHz >= 33 and 1 or 2)
					expect(inRange(frames)).to.beTrue()
					-- a frame in which the bar did not move is a frame in which the movement was too small to show
					expect(distinctFraction(frames, 0.1)).to.beGreaterThan(0.99)
				end)
			end
		},
		{
			name = "the recharge after its delay, 16.7 a second, is as smooth",
			func = function()
				each(function(fps, updateHz)
					local truth = function(t) return 30 + math.max(0, t - 1) * 100 / 6 end
					local rate = function(t) return t >= 1 and 100 / 6 or 0 end
					local frames = play({fps = fps, updateHz = updateHz, seconds = 3, truth = truth, rate = rate})
					expect(monotone(frames, 1)).to.beTrue()
					expect(maxStep(frames)).to.beLessThan(stepSlack(fps, updateHz))
					expect(maxError(frames, 1.3)).to.beLessThan(1)
					-- nothing moves during the delay
					expect(maxError(frames, 0, 0.99)).to.beLessThan(0.001)
				end)
			end
		},
		{
			name = "the sprint stops at once: no jump, no step back, and the bar stands on the real value within a tenth of a second",
			func = function()
				each(function(fps, updateHz)
					-- sprints 0.7 s (100 to 70.25), stops
					local stop = 0.7
					local truth = function(t) return 100 - 42.5 * math.min(t, stop) end
					local rate = function(t) return t < stop and -42.5 or 0 end
					local frames = play({fps = fps, updateHz = updateHz, seconds = 1.5, truth = truth, rate = rate})
					expect(monotone(frames, -1, 0, stop)).to.beTrue()
					expect(maxStep(frames)).to.beLessThan(stepSlack(fps, updateHz))
					-- the prediction can go on for one update interval after the stop (the client does not know yet), and
					-- the bar then comes back by what it went too far
					local final = truth(stop)
					local worst, rebound, lowest = 0, 0, 100

					for _, f in ipairs(frames) do
						worst = math.max(worst, final - f.shown)
						lowest = math.min(lowest, f.shown)
						rebound = math.max(rebound, f.shown - lowest)
					end

					expect(worst).to.beLessThan(42.5 * (1 / updateHz + 1 / fps) + 0.2)
					expect(rebound).to.beLessThan(42.5 * (1 / updateHz + 1 / fps) + 0.2)
					expect(maxError(frames, stop + 0.4)).to.beLessThan(0.02)
				end)
			end
		},
		{
			name = "an armor hit is not hidden: the bar goes to the new value at the frame that receives it",
			func = function()
				each(function(fps, updateHz)
					local truth = function(t) return t < 0.5 and 80 or 50 end
					local frames = play({fps = fps, updateHz = updateHz, seconds = 1, truth = truth, rate = function() return 0 end})
					local firstNew
					for _, f in ipairs(frames) do
						if f.sample == 50 then
							firstNew = f
							break
						end
					end
					expect(firstNew ~= nil).to.beTrue()
					expect(firstNew.shown).to.equal(50)
				end)
			end
		},
		{
			name = "a hit while the bar recharges, and a small one (2 points), are taken at once or within a few frames, never delayed by a sweep",
			func = function()
				each(function(fps, updateHz)
					-- recharging at 16.7 a second from 40, a hit of 25 at 0.5 s, the recharge goes on after the 1 s delay
					local function truth(t)
						if t < 0.5 then
							return 40 + t * 100 / 6
						elseif t < 1.5 then
							return 40 + 0.5 * 100 / 6 - 25
						end

						return 40 + 0.5 * 100 / 6 - 25 + (t - 1.5) * 100 / 6
					end

					local function rate(t) return (t < 0.5 or t >= 1.5) and 100 / 6 or 0 end
					local frames = play({fps = fps, updateHz = updateHz, seconds = 2.5, truth = truth, rate = rate})

					for _, f in ipairs(frames) do
						if f.t > 0.5 and f.sample < 40 + 0.5 * 100 / 6 - 20 and f.t < 1.4 then
							-- the sample that carries the hit has arrived: the bar is down with it
							expect(f.shown).to.beLessThan(f.sample + 1.2)
						end
					end

					expect(maxError(frames, 1.7)).to.beLessThan(1)
				end)
			end
		},
		{
			name = "a small drop (2 points) is followed within a few frames",
			func = function()
				local frames = play({fps = 144, updateHz = 66, seconds = 1, truth = function(t) return t < 0.5 and 60 or 58 end, rate = function() return 0 end})
				expect(frames[#frames].shown).to.equal(58)
				expect(monotone(frames, -1)).to.beTrue()
			end
		},
		{
			name = "no rate (the networked float alone: 9.4 updates a second of 4.5 points): no prediction, the bar is the value told, never back, never out of range",
			func = function()
				local frames = play({fps = 144, updateHz = 9.4, seconds = 2, truth = function(t) return 100 - 42.5 * t end, rate = function() return 0 end})
				expect(monotone(frames, -1)).to.beTrue()
				expect(inRange(frames)).to.beTrue()

				for _, f in ipairs(frames) do
					expect(math.abs(f.shown - f.sample) < 1e-6).to.beTrue()
				end
			end
		},
		{
			name = "while the suit is down (predict off) the bar is the last value told, whatever the rate says",
			func = function()
				local frames = play({fps = 144, updateHz = 66, seconds = 1, truth = function(t) return 60 - 42.5 * t end, rate = function() return -42.5 end, predictFn = function() return false end})

				for _, f in ipairs(frames) do
					expect(f.shown >= f.sample - 1e-6).to.beTrue()
					expect(f.shown).to.beLessThan(f.sample + 2.6) -- the easing (50 ms) of a bar that falls at 42.5 a second
				end
			end
		},
		{
			name = "the server goes silent (a lost packet, a pause): the prediction stops after a quarter of a second and never leaves 0 to 100",
			func = function()
				-- from 30, draining at 42.5; no tick after 0.1 s
				local frames = play({fps = 144, updateHz = 66, seconds = 2, truth = function(t) return math.max(0, 30 - 42.5 * t) end, rate = function() return -42.5 end, dropTick = function(t) return t > 0.1 end})
				local atEnd = frames[#frames].shown
				local sample = 30 - 42.5 * 0.1
				expect(atEnd).to.beGreaterThan(sample - 42.5 * 0.27)
				expect(atEnd).to.beLessThan(sample - 42.5 * 0.2)
				expect(inRange(frames)).to.beTrue()
				-- near the bottom: the prediction does not go under 0
				frames = play({fps = 60, updateHz = 66, seconds = 1, truth = function(t) return math.max(0, 3 - 42.5 * t) end, rate = function(t) return 3 - 42.5 * t > 0 and -42.5 or 0 end, dropTick = function(t) return t > 0.01 end})
				expect(inRange(frames)).to.beTrue()
			end
		},
		{
			name = "a respawn (Reset): the first frame shows the real value at once, not a sweep from the old one",
			func = function()
				local sm = GryMod.NewEnergySmooth()
				sm:Update(4, -42.5, 0, true)
				sm:Update(3.5, -42.5, 0.016, true)
				sm:Reset()
				expect(sm:Update(100, 0, 1.0, true)).to.equal(100)
				-- and the very first frame of a new smoother
				expect(GryMod.NewEnergySmooth():Update(37.5, 0, 5, true)).to.equal(37.5)
			end
		},
		{
			name = "the rate changes with the mode (a cloak at 3 a second, then a sprint at 42.5): no jump, no step back",
			func = function()
				local function truth(t) return t < 0.5 and 90 - 3 * t or 90 - 1.5 - 42.5 * (t - 0.5) end
				local function rate(t) return t < 0.5 and -3 or -42.5 end

				each(function(fps, updateHz)
					local frames = play({fps = fps, updateHz = updateHz, seconds = 1.2, truth = truth, rate = rate})
					expect(monotone(frames, -1)).to.beTrue()
					expect(maxStep(frames)).to.beLessThan(stepSlack(fps, updateHz))
					expect(maxError(frames, 0.5 + 2 / updateHz + 0.2)).to.beLessThan(updateHz >= 33 and 1 or 2)
				end)
			end
		},
		{
			name = "a long frame (the game was stopped for 3 s): no error, in range, and back on the real value at once",
			func = function()
				local sm = GryMod.NewEnergySmooth()
				sm:Update(80, -42.5, 0, true)
				sm:Update(79, -42.5, 0.016, true)
				local shown = sm:Update(30, 0, 3.0, true)
				expect(shown >= 0 and shown <= 100).to.beTrue()
				expect(shown).to.equal(30)
			end
		},
		{
			name = "garbage in (NaN, nil rate, values over 100 or under 0): the result is a number from 0 to 100",
			func = function()
				local sm = GryMod.NewEnergySmooth()
				local function ok(v) return type(v) == "number" and v == v and v >= 0 and v <= 100 end
				expect(ok(sm:Update(250, 0, 0, true))).to.beTrue()
				expect(ok(sm:Update(-20, 5, 0.1, true))).to.beTrue()
				expect(ok(sm:Update(50, nil, 0.2, true))).to.beTrue()
				expect(ok(sm:Update(0 / 0, 1, 0.3, true))).to.beTrue()
				expect(ok(sm:Update(50, 0 / 0, 0.4, true))).to.beTrue()
			end
		},
		{
			name = "the time going back (a new map restarts CurTime): the bar goes to the value, does not freeze",
			func = function()
				local sm = GryMod.NewEnergySmooth()
				sm:Update(80, -42.5, 1000, true)
				sm:Update(70, -42.5, 1000.2, true)
				expect(sm:Update(100, 0, 1, true)).to.equal(100)
				expect(sm:Update(100, 0, 1.1, true)).to.equal(100)
			end
		},
		{
			name = "the server value that reaches the HUD: the fresh gry_energy value and rate win over the networked float, an old one does not",
			func = function()
				local ES = GryMod.EnergySmooth
				expect(ES ~= nil).to.beTrue()
				local fake = {GetNWFloat = function() return 55 end, GetNWBool = function() return false end, Health = function() return 100 end}
				ES.Receive(42.25, -42.5, 10.0)
				local value, rate = ES.Raw(fake, 10.1)
				expect(value).to.equal(42.25)
				expect(rate).to.equal(-42.5)
				value, rate = ES.Raw(fake, 10.6)
				expect(value).to.equal(55)
				expect(rate).to.equal(0)
				-- a clock that went back (new map): not a fresh value
				value = ES.Raw(fake, 2)
				expect(value).to.equal(55)
				ES.Reset()
			end
		},
		{
			name = "EnergyShown: predicted by default, the raw server value with gry_hud_energy_smooth 0, the networked float when nothing came, no prediction while the suit is down",
			func = function()
				local ES = GryMod.EnergySmooth
				local down = false
				local fake = {GetNWFloat = function() return 55 end, GetNWBool = function(_, name) return name == "GryMalfunction" and down end, Health = function() return 100 end}
				ES.Reset()
				-- nothing came: the networked float
				expect(ES.Shown(fake, 20)).to.equal(55)
				-- a drain: the bar goes on between two updates
				ES.Receive(50, -42.5, 20.0)
				local a = ES.Shown(fake, 20.0)
				local b = ES.Shown(fake, 20.05)
				expect(a).to.equal(50)
				expect(b < 49).to.beTrue()
				-- switched off: the value told, as it is
				GetConVar("gry_hud_energy_smooth"):SetInt(0)
				expect(ES.Shown(fake, 20.1)).to.equal(50)
				GetConVar("gry_hud_energy_smooth"):SetInt(1)
				-- the suit is down: the value told
				ES.Reset()
				ES.Receive(50, -42.5, 30.0)
				down = true
				ES.Shown(fake, 30.0)
				expect(ES.Shown(fake, 30.1) >= 49.99).to.beTrue()
				down = false
				ES.Reset()
			end
		},
		{
			name = "a dead player: the value as it is, and the smoother starts again at the respawn",
			func = function()
				local ES = GryMod.EnergySmooth
				local health = 0
				local fake = {GetNWFloat = function() return 0 end, GetNWBool = function() return false end, Health = function() return health end}
				ES.Reset()
				ES.Receive(0, 0, 40.0)
				expect(ES.Shown(fake, 40.0)).to.equal(0)
				health = 100
				ES.Receive(100, 0, 41.0)
				expect(ES.Shown(fake, 41.0)).to.equal(100)
				ES.Reset()
			end
		}
	}
}
