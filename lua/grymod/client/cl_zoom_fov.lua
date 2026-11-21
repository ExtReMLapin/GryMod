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

-- One look at the world: sends what has to be sent.
function ZoomFov.Step(ply, now)
	local send = ZoomFov.Decide(state, wantedFov(ply), now)

	if send ~= nil then
		ZoomFov.Send(send)
	end
end

-- The stage changes (the wheel), the option, the HUD and the heartbeat are not events of their own: they are looked at at every frame, but
-- only while the own zoom is up. The Think hook is put when the own zoom opens and taken off by the frame in which the own zoom is down
-- and 0 has been sent, so that a player who does not zoom pays nothing (see the hook GryMod_SuitZoom below, and cl_suit_zoom.lua).
local THINK = "GRYZOOMFOV"

local function zoomUp()
	local suit = GryMod.SuitZoom

	return suit ~= nil and suit.IsActive()
end

-- A look at the world (Step) and, when the own zoom is down and nothing is left to take back, the Think hook goes.
function ZoomFov.Update(ply, now)
	ZoomFov.Step(ply, now)

	if state.sent == 0 and not zoomUp() then
		hook.Remove("Think", THINK)
	end
end

local function think()
	ZoomFov.Update(LocalPlayer(), RealTime())
end

-- The own zoom opens or closes (cl_suit_zoom.lua runs this hook in both cases, once, in the same frame).
function ZoomFov.OnSuitZoom(active)
	if active then
		hook.Add("Think", THINK, think)
	else
		-- (0 is sent now, not a frame later)
		ZoomFov.Update(LocalPlayer(), RealTime())
	end
end

hook.Add("GryMod_SuitZoom", "GRYZOOMFOV", function(active)
	ZoomFov.OnSuitZoom(active)
end)

-- This file loaded again: the hook of an older copy that watched at every frame goes, unless the own zoom is up already.
if zoomUp() then
	hook.Add("Think", THINK, think)
else
	hook.Remove("Think", THINK)
end
