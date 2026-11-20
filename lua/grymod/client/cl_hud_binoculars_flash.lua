-- The binoculars drawn from the original Scaleform movie (HUD_Binoculars), see cl_flash.lua. In GryMod they are the
-- Half-Life 2 suit zoom (the zoom key): the movie shows while it is held, with the distance of what is aimed at,
-- the zoom factor and the world position. Hand-ported parts of its ActionScript: setVisible, closeBinoculars,
-- setPosition, setDistance, setZoomMode. Not ported: the horizon ladder (Attitude), the target lock icons.

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Bino = {}
GryMod.FlashBinoculars = Bino

Bino.MOVIE = "hud_binoculars"

local Instance = {}
Instance.__index = Instance

-- World units in a metre (the same ratio as the original game's scale: 1 unit = 1.905 cm).
Bino.UNITS_PER_METRE = 52.49

-- The mode (1 to 4, shown as X02 to X08) of a zoom: the factor is the ratio of the tangents of the half fields
-- of view, and each mode covers two factors.
function Bino.ZoomModeFor(defaultFov, fov)
	if type(defaultFov) ~= "number" or type(fov) ~= "number" or fov ~= fov or defaultFov ~= defaultFov or fov <= 0 then
		return 1
	end

	local factor = math.tan(math.rad(defaultFov) / 2) / math.tan(math.rad(fov) / 2)

	return math.Clamp(math.floor(factor / 2), 1, 4)
end

-- The two numbers setDistance wants (whole metres, hundredths), (0, 0) when nothing is aimed at; the display has
-- three digits.
function Bino.MetresFrom(units)
	if type(units) ~= "number" or units ~= units or units <= 0 then
		return 0, 0
	end

	local metres = units / Bino.UNITS_PER_METRE

	if metres >= 1000 then
		return 999, 99
	end

	local int = math.floor(metres)

	return int, math.floor((metres - int) * 100 + 1e-6)
end

local function degrees(value)
	-- "DDD° MM.MM": a world coordinate in metres as degrees (60 metres each) and minutes
	local whole = math.floor(value / 60)
	local minutes = value - whole * 60

	return string.format("%03d° %05.2f", whole, minutes)
end

-- setPosition's two strings for a world position: north from y, west from -x.
function Bino.PositionStrings(position)
	local x, y = position.x / Bino.UNITS_PER_METRE, position.y / Bino.UNITS_PER_METRE

	return degrees(math.abs(y)) .. (y >= 0 and " N" or " S"), degrees(math.abs(x)) .. (x <= 0 and " W" or " E")
end

function Bino.New(movie, theme)
	if not movie then
		return nil
	end

	local root = Flash.NewRoot(movie, theme or (GryMod.FlashHUD and GryMod.FlashHUD.Theme))
	local bino = root:Find("Root.Binoculars")

	if not bino then
		return nil
	end

	for _, name in ipairs({"Line", "Over", "Text"}) do
		local holder = root:Child(name)

		if holder then
			holder:SetVisible(false)
		end
	end

	return setmetatable({
		root = root,
		bino = bino,
		shown = false,
		closing = false,
		zoom = 1,
		north = "000° 000.00 N",
		west = "000° 000.00 W",
		metres = 0,
		hundredths = 0
	}, Instance)
end

function Instance:IsShown()
	return self.shown
end

-- setVisible(true, true): the intro plays from its first frame.
function Instance:Show()
	if self.shown and not self.closing then
		return
	end

	self.shown = true
	self.closing = false
	self.bino:GotoAndPlay(1)
	self:_apply()
end

-- closeBinoculars(): the close animation; the binoculars are hidden at its end.
function Instance:Close()
	if not self.shown or self.closing then
		return
	end

	self.closing = true
	self.bino:GotoAndPlay("close")
end

function Instance:SetZoomMode(mode)
	self.zoom = mode
	self:_applyZoom()
end

function Instance:SetPosition(north, west)
	self.north, self.west = north, west
	self:_applyPosition()
end

function Instance:SetDistance(metres, hundredths)
	self.metres, self.hundredths = metres, hundredths
	self:_applyDistance()
end

function Instance:_applyZoom()
	local zoom = self.bino:Find("Zoom.Colorset")

	if zoom then
		zoom:SetText("Zoom", "X0" .. self.zoom * 2)
	end
end

function Instance:_applyPosition()
	local north, west = self.bino:Find("DegreeN.Colorset"), self.bino:Find("DegreeW.Colorset")

	if north then
		north:SetText("DegreeN", self.north)
	end

	if west then
		west:SetText("DegreeW", self.west)
	end
end

-- setDistance(int, float): three digits (the leading zeros are shown dim), two decimals, the dot and the M; with
-- nothing aimed at, the digits are blank and the icon shows.
function Instance:_applyDistance()
	local d = self.bino:Find("TargetDistance.Colorset")

	if not d then
		return
	end

	local int, frac = self.metres, self.hundredths
	local digits = {math.floor(int / 100), math.floor((int % 100) / 10), int % 10}
	local leading = true

	for i = 0, 2 do
		local clip = d:Child("ObjNumber" .. i)
		local digit = digits[i + 1]

		if clip then
			leading = leading and digit == 0 and (i < 2 or int == 0)

			-- a leading zero is a dim one (frame 2, its text in "Low"), the others are plain digits (frame 1)
			if digit == 0 and leading then
				clip:GotoAndStop(2)
				local low = clip:Child("Low")

				if low then
					low:SetText("ObjNumber" .. i, "0")
				end
			else
				leading = false
				clip:GotoAndStop(1)
				clip:SetText("ObjNumber" .. i, tostring(digit))
			end
		end
	end

	d:SetText("ObjNumber4", tostring(math.floor((frac % 100) / 10)))
	d:SetText("ObjNumber5", tostring(frac % 10))

	local icon = d:Child("Icon")

	if int == 0 and frac == 0 then
		for i = 0, 2 do
			local clip = d:Child("ObjNumber" .. i)

			if clip then
				clip:SetText("ObjNumber" .. i, "")
				local low = clip:Child("Low")

				if low then
					low:SetText("ObjNumber" .. i, "")
				end
			end
		end

		d:SetText("ObjNumber4", "")
		d:SetText("ObjNumber5", "")
		d:SetText("Dot", "")
		d:SetText("MTEXT", "")

		if icon then icon:SetVisible(true) end
	else
		d:SetText("Dot", ".")
		d:SetText("MTEXT", "M")

		if icon then icon:SetVisible(false) end
	end
end

function Instance:_apply()
	self:_applyZoom()
	self:_applyPosition()
	self:_applyDistance()
end

function Instance:Update(dt)
	if not self.shown then
		return
	end

	self.root:Advance(dt)

	-- the frames rebuild the clips (the intro, the close): say the values again while the timeline moves
	local frame = self.bino:CurrentFrame()

	if frame ~= self.lastFrame then
		self.lastFrame = frame
		self:_apply()
	end

	if self.closing and (not self.bino.playing or frame >= self.bino.n) then
		self.shown = false
		self.closing = false
		self.lastFrame = nil
	end
end

function Instance:Draw(x, y, scale)
	if self.shown then
		Flash.Draw(self.root, x, y, scale)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- In the game: the Half-Life 2 suit zoom (the zoom key) shows the binoculars
-- ---------------------------------------------------------------------------------------------------------

local binoculars
local lastTime
local fed = {}

local function enabled()
	return GryMod.FlashHUD ~= nil and GryMod.FlashHUD.Enabled()
end

-- Whether the player is zooming: the suit zoom key held, alive, not in a menu.
function Bino.Wanted(ply)
	return IsValid(ply) and ply:Alive() and ply:KeyDown(IN_ZOOM)
end

local function feed(ply)
	local defaultFov = ply:GetInfoNum("fov_desired", 75)
	local zoom = Bino.ZoomModeFor(defaultFov, ply:GetFOV())

	if fed.zoom ~= zoom then
		fed.zoom = zoom
		binoculars:SetZoomMode(zoom)
	end

	local north, west = Bino.PositionStrings(ply:GetPos())

	if fed.north ~= north or fed.west ~= west then
		fed.north, fed.west = north, west
		binoculars:SetPosition(north, west)
	end

	local start = ply:EyePos()
	local trace = util.TraceLine({start = start, endpos = start + ply:EyeAngles():Forward() * 52.49 * 1000, filter = ply, mask = MASK_SHOT})
	local metres, hundredths = Bino.MetresFrom(trace.Hit and not trace.HitSky and start:Distance(trace.HitPos) or nil)

	if fed.metres ~= metres or fed.hundredths ~= hundredths then
		fed.metres, fed.hundredths = metres, hundredths
		binoculars:SetDistance(metres, hundredths)
	end
end

hook.Add("HUDPaint", "GRYBINOCULARS", function()
	if not enabled() then
		return
	end

	local ply = LocalPlayer()
	local wanted = Bino.Wanted(ply)

	if not binoculars then
		if not wanted then
			return
		end

		binoculars = Bino.New(Flash.Load(Bino.MOVIE))

		if not binoculars then
			return
		end

		fed, lastTime = {}, nil
	end

	if wanted then
		binoculars:Show()
	else
		binoculars:Close()
	end

	if not binoculars:IsShown() then
		return
	end

	if wanted then
		feed(ply)
	end

	local now = RealTime()
	local dt = math.min(now - (lastTime or now), 0.1)
	lastTime = now
	binoculars:Update(dt)

	-- the stage is 1366 x 768: scaled to the screen height, centred
	local scale = ScrH() / 768
	binoculars:Draw((ScrW() - 1366 * scale) / 2, 0, scale)
end)

function Bino.Reset()
	if binoculars then
		Flash.ReleaseClip(binoculars.root)
	end

	binoculars = nil
end
