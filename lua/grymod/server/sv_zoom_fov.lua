-- The field of view of the player follows the own zoom of the binoculars (the client asks: gry_zoom_fov, one float, 0 = back to normal).
-- The own zoom (the key of the suit mod, H by default) only gives the VIEW another field of view (CalcView, see cl_hud_binoculars_flash.lua):
-- the engine's field of view of the player (m_iFOV) stays at his normal one, and the engine scales the fade distances and the details of the
-- world with THAT one. Measured in the game (d2_coast_07): the windows of a far house have their panes with Player:SetFOV(20) and are flat
-- rectangles with only a CalcView of 20, as the crossbow's zoom and the Half-Life 2 zoom key (B) have them (they set the engine's field of
-- view); the models' own level of detail follows the rendered field of view in both cases. Player:SetFOV is shared and has no effect when it
-- is called on the client only, so the client says what field of view its stage has and the server sets it.
--
-- What the server does, for a living player and a field of view in the range he may have (below his normal one, not under MIN_FOV):
--   * the engine's field of view is set to it (Player:SetFOV(fov, TRANSITION)); the same value again only keeps the request alive;
--   * 0 (or a value that is not below the normal field of view) gives the normal one back, once, and only when this module had set one:
--     a zoom of a weapon (the crossbow) is never touched, and a weapon that holds the zoom is not taken from (the engine refuses it);
--   * a request that does not come again for TIMEOUT seconds (the client keeps sending it once a second while it zooms) is ended, so a
--     client that died or lost the message cannot leave the player zoomed;
--   * the death and the disconnection of the player drop what is held.
-- A player may ask 10 times a second at most (the requests beyond are ignored, those that are not numbers count too).

util.AddNetworkString("gry_zoom_fov")

GryMod = GryMod or {}

local ZoomFov = GryMod.ZoomFov or {}
GryMod.ZoomFov = ZoomFov

-- the smallest field of view a client can ask for (degrees): the 8x stage of a 100 degrees view is 16.9
ZoomFov.MIN_FOV = 5
-- how long the engine takes to go to the field of view asked for, seconds: short, the client's view has its own easing
ZoomFov.TRANSITION = 0.1
-- a request not renewed for this long is ended, seconds
ZoomFov.TIMEOUT = 3
ZoomFov.LIMIT = 10 -- requests per player per window
ZoomFov.WINDOW = 1 -- seconds
-- a field of view this close to the normal one is not a zoom
ZoomFov.TOLERANCE = 0.5

local held = setmetatable({}, {__mode = "k"}) -- [player] = {fov = degrees, seen = time}
local windows = setmetatable({}, {__mode = "k"}) -- [player] = {start = time, count = n}

-- Everything forgotten (the tests).
function ZoomFov.Reset()
	held = setmetatable({}, {__mode = "k"})
	windows = setmetatable({}, {__mode = "k"})
end

-- The field of view this module holds on the player, or nil.
function ZoomFov.Held(ply)
	local h = held[ply]

	return h and h.fov or nil
end

-- Drops what is held without any call (the player died, left, the map changed: the engine has the normal field of view again).
function ZoomFov.Forget(ply)
	held[ply] = nil
	windows[ply] = nil
end

-- Gives the player's field of view back when this module had set one.
function ZoomFov.Release(ply)
	if held[ply] == nil then
		return false
	end

	held[ply] = nil

	if IsValid(ply) then
		ply:SetFOV(0, ZoomFov.TRANSITION)
	end

	return true
end

-- Whether the player may ask now (10 a second).
function ZoomFov.Allowed(ply, now)
	local w = windows[ply]

	if not w or now - w.start >= ZoomFov.WINDOW then
		windows[ply] = {start = now, count = 1}

		return true
	end

	if w.count >= ZoomFov.LIMIT then
		return false
	end

	w.count = w.count + 1

	return true
end

local function usable(fov)
	return type(fov) == "number" and fov == fov and fov ~= math.huge and fov ~= -math.huge and fov >= 0
end

-- Whether a weapon (or anything that is not the player) holds the zoom of the player: the engine refuses a field of view from another.
local function takenByAnother(ply)
	local owner = ply:GetInternalVariable("m_hZoomOwner")

	return isentity(owner) and IsValid(owner) and owner ~= ply
end

-- One request. Returns "set" (the engine's field of view was set), "held" (the same value: only kept alive), "release" (given back) or
-- false (nothing done).
function ZoomFov.Handle(ply, fov, now)
	if not ply or not IsValid(ply) or not ZoomFov.Allowed(ply, now) then
		return false
	end

	if not usable(fov) or not ply:Alive() then
		return false
	end

	local normal = ply:GetInfoNum("fov_desired", 75)

	if fov == 0 or fov >= normal - ZoomFov.TOLERANCE then
		if ZoomFov.Release(ply) then
			return "release"
		end

		return false
	end

	fov = math.max(fov, ZoomFov.MIN_FOV)

	if takenByAnother(ply) then
		return false
	end

	local h = held[ply]

	if h and math.abs(h.fov - fov) < 0.01 then
		h.seen = now

		return "held"
	end

	held[ply] = {fov = fov, seen = now}
	ply:SetFOV(fov, ZoomFov.TRANSITION)

	return "set"
end

-- Ends the requests that were not renewed for TIMEOUT seconds. Returns how many.
function ZoomFov.Expire(now)
	local count = 0

	for ply, h in pairs(held) do
		if now - h.seen >= ZoomFov.TIMEOUT then
			count = count + 1
			ZoomFov.Release(ply)
		end
	end

	return count
end

net.Receive("gry_zoom_fov", function(_, ply)
	ZoomFov.Handle(ply, net.ReadFloat(), RealTime())
end)

-- (nothing runs while nobody holds a zoom)
timer.Create("GRYZOOMFOVEXPIRE", 1, 0, function()
	if next(held) ~= nil then
		ZoomFov.Expire(RealTime())
	end
end)

hook.Add("PlayerDisconnected", "GryMod zoom fov", function(ply)
	ZoomFov.Forget(ply)
end)

hook.Add("PostPlayerDeath", "GryMod zoom fov", function(ply)
	-- (the engine gives the normal field of view back at the respawn)
	held[ply] = nil
end)
