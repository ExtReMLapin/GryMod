-- Fapadar made 95% of the code
if SERVER then
	concommand.Add("_ping", function(p, c, a)
		if (p.LastPing and p.LastPing + 5 < CurTime()) or not p.LastPing then
			p.LastPing = CurTime()
			umsg.Start("pong", p)
			umsg.String("")
			umsg.End()
		end
	end)

	return
end

local lastmovetime = CurTime() + 10 -- Variable to check when move packets were last received
local enabled = util.tobool(math.floor(CreateConVar("anticrash_enabled", 1, true, true):GetInt()))

cvars.AddChangeCallback("anticrash_enabled", function(c, o, n)
	enabled = util.tobool(math.floor(n))
end)

local crashtime = 1
local crashed = false
local spawned = false
local pending = false
local spawntime

-- Slightly neater having all the stuff in a function, but the script overall is still a mess
local function IsCrashed()
	if enabled then
		if not crashed then
			if spawned and spawntime < CurTime() then
				if lastmovetime + crashtime < CurTime() then
					if (LocalPlayer and IsValid(LocalPlayer()) and not LocalPlayer():IsFrozen() and not LocalPlayer():InVehicle()) then
						return true
					end
				end
			end
		end -- Prevent repetition.
	end
end

usermessage.Hook("pong", function(um)
	lastmovetime = CurTime() + 10
end)

hook.Add("Move", "CrashReconnect", function()
	lastmovetime = CurTime() -- Set the last move packet to the current time.
end)

hook.Add("InitPostEntity", "CrashReconnect", function()
	spawned = true
	spawntime = CurTime() + 5
end)

hook.Add("Think", "CrashReconnect", function()
	if not crashed and IsCrashed() and not pending then
		pending = true
		RunConsoleCommand("_ping")

		timer.Simple(3.5, function()
			if lastmovetime + crashtime < CurTime() then
				crashed = true
				shouldretry = true -- This is a seperate crash from the previous, the user might want to reconnect this time.
				pending = false
				hook.Call("ServerCrash", nil) -- Incase anyone else wants to hook into server crashes.
			else
				pending = false
				crashed = false
			end
		end)
	end
end)

if not CLIENT then
	return
end

local crashlogo = surface.GetTextureID("cryhud/crash")

function CrashLogo()
	if IsCrashed() and not game.SinglePlayer() then
		surface.SetTexture(crashlogo)
		surface.SetDrawColor(Color(255, 255, 255, 255))
		surface.DrawTexturedRect(ScrW() / 2 - 50, ScrH() / 2 - 50, 100, 100)
	end
end -- Wow such coding skillz

hook.Add("HUDPaint", "DetectCrash", CrashLogo)