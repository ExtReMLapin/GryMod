-- client job: args.secs, args.move, args.from, args.to
local P = GRY_CPROBE
P.rows = {}
P.on = true
P.move = args.move and true or false
job:sleep(args.secs or 3)
P.on = false
P.move = false
local rows = P.rows
local function brief(r)
	if not r.samples then return r end
	return {sample_hz = r.sample_hz, changes_per_s = r.changes_per_s, int_ms = r.int_ms, step = r.step, frames_between = r.frames_between_changes}
end
local out = {n = #rows}
out.nwfloat = brief(GRY_ANALYZE(rows, 2, nil, args.from, args.to))
out.server_value = brief(GRY_ANALYZE(rows, 4, nil, args.from, args.to))
out.shown_float = brief(GRY_ANALYZE(rows, 5, nil, args.from, args.to))
out.hud_value = brief(GRY_ANALYZE(rows, 3, nil, args.from, args.to))
return out
