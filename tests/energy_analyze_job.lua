-- GRY_ANALYZE(rows, vi, quant): distribution of the changes of the value (column vi) over time (column 1).
-- quant: optional function applied to the value first (e.g. math.floor: the frame of the bar).
function GRY_ANALYZE(rows, vi, quant, from, to)
	local n = #rows
	local r = {}
	if n < 3 then return {n = n} end
	local t0 = rows[1][1]
	local pts = {}
	for i = 1, n do
		local tt = rows[i][1] - t0
		if (not from or tt >= from) and (not to or tt <= to) then pts[#pts + 1] = {tt, rows[i][vi]} end
	end
	local function q(v) return quant and quant(v) or v end
	local dur = pts[#pts][1] - pts[1][1]
	local ints, steps, fr = {}, {}, {}
	local last = q(pts[1][2])
	local lastT, lastI = pts[1][1], 1
	local changes = 0
	for i = 2, #pts do
		local v = q(pts[i][2])
		if v ~= last then
			changes = changes + 1
			ints[#ints + 1] = (pts[i][1] - lastT) * 1000
			steps[#steps + 1] = math.abs(v - last)
			fr[#fr + 1] = i - lastI
			last, lastT, lastI = v, pts[i][1], i
		end
	end
	local function pct(a, p)
		if #a == 0 then return 0 end
		local c = table.Copy(a)
		table.sort(c)
		return c[math.max(1, math.ceil(#c * p))]
	end
	local function mean(a)
		local s = 0
		for _, x in ipairs(a) do s = s + x end
		return #a > 0 and s / #a or 0
	end
	local m = mean(ints)
	local var = 0
	for _, x in ipairs(ints) do var = var + (x - m) ^ 2 end
	r.samples = #pts
	r.dur_s = math.Round(dur, 3)
	r.sample_hz = math.Round(#pts / dur, 1)
	r.changes_per_s = math.Round(changes / dur, 1)
	r.int_ms = {mean = math.Round(m, 2), med = math.Round(pct(ints, 0.5), 2), p95 = math.Round(pct(ints, 0.95), 2), max = math.Round(pct(ints, 1), 2), sd = math.Round(#ints > 0 and math.sqrt(var / #ints) or 0, 2)}
	r.step = {med = math.Round(pct(steps, 0.5), 3), p95 = math.Round(pct(steps, 0.95), 3), max = math.Round(pct(steps, 1), 3)}
	r.frames_between_changes = {med = pct(fr, 0.5), p95 = pct(fr, 0.95), max = pct(fr, 1)}
	return r
end
return "ok"
