-- Tells the server the field of view of the own zoom, so that the engine's field of view of the player follows it. The own zoom of the
-- binoculars (the key of the suit mod, H by default) only gives the VIEW its stage's field of view (CalcView, see
-- cl_hud_binoculars_flash.lua): the engine's field of view of the player stays at the normal one, and the engine scales the fade
-- distances and the details of the world with THAT one. Measured in the game (d2_coast_07): the panes of the windows of a far house are
-- there with Player:SetFOV(20) and are flat rectangles with a CalcView of 20; the crossbow's zoom and the Half-Life 2 zoom key set the
-- engine's field of view themselves and have them; the models' own level of detail follows the rendered field of view in both cases.
-- Player:SetFOV is shared and has no effect when it is called on the client only, so the server sets it (sv_zoom_fov.lua) from the one float
-- that is sent here (gry_zoom_fov, 0 = back to normal).
--
-- What is sent: the field of view of the stage the binoculars are in (not the eased value of the view: the engine has its own short
-- transition), only while the OWN zoom is up (the Half-Life 2 key sets the engine's field of view itself), at every change, and once a
-- second while it holds (the server ends a request that is not renewed, so a lost message cannot leave the player zoomed). 0 once when
-- the zoom ends, the option goes off, the HUD element goes off or the binoculars are not wanted any more. One check box
-- (gry_zoom_follow_fov, on by default).

GryMod = GryMod or {}

local ZoomFov = GryMod.ZoomFov or {}
GryMod.ZoomFov = ZoomFov

local OptionConVar = CreateClientConVar("gry_zoom_follow_fov", "1", true, false, "While the own zoom of the binoculars is up, the player's field of view follows its stage (the server sets it), so that the world keeps the details of a zoomed view: distant windows, fades (off: only the picture is zoomed, the details stay those of the normal view)")

-- the same value again is sent after this long, seconds (the server's timeout is 3)
ZoomFov.HEARTBEAT = 1
-- a change smaller than this is not one (degrees)
ZoomFov.EPSILON = 0.05

local state

function ZoomFov.Enabled()
	return OptionConVar:GetBool()
end

function ZoomFov.NewState()
	return {sent = 0, at = -math.huge}
end

state = ZoomFov.NewState()

-- Forgets what was sent (the tests, a map change).
function ZoomFov.Reset()
	state = ZoomFov.NewState()
end

-- The field of view the engine should have: the stage's (2x, 4x, 8x of the normal field of view) while the own zoom is up, else 0. Pure.
function ZoomFov.Target(own, stage, base)
	if not own or type(stage) ~= "number" or type(base) ~= "number" or base ~= base or base <= 0 or base >= 180 then
		return 0
	end

	local Bino = GryMod.FlashBinoculars
	local factor = Bino and Bino.ZOOM_STAGES[stage]

	if not factor then
		return 0
	end

	return Bino.StageFov(base, factor)
end

-- What to send now, or nil; what is returned counts as sent (s.sent is the last value sent, s.at when). Touches only the state it is given.
function ZoomFov.Decide(s, target, now)
	if math.abs(target - s.sent) > ZoomFov.EPSILON or (target > 0 and now - s.at >= ZoomFov.HEARTBEAT) then
		s.sent, s.at = target, now

		return target
	end

	return nil
end

-- The message: one float.
function ZoomFov.Send(fov)
	net.Start("gry_zoom_fov")
	net.WriteFloat(fov)
	net.SendToServer()
end

-- The field of view the engine should have now, read from the world.
local function wantedFov(ply)
	local Bino, suit = GryMod.FlashBinoculars, GryMod.SuitZoom

	if not ZoomFov.Enabled() or not Bino or not suit or not IsValid(ply) then
		return 0
	end

	if not Bino.Enabled() or Bino.IsMissing() or not suit.IsActive() or not Bino.Wanted(ply) then
		return 0
	end

	return ZoomFov.Target(true, Bino.ZoomState.stage, ply:GetInfoNum("fov_desired", 75))
end

-- Once per frame.
function ZoomFov.Step(ply, now)
	local send = ZoomFov.Decide(state, wantedFov(ply), now)

	if send ~= nil then
		ZoomFov.Send(send)
	end
end

hook.Add("Think", "GRYZOOMFOV", function()
	ZoomFov.Step(LocalPlayer(), RealTime())
end)
