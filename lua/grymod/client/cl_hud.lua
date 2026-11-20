local color_white = color_white
-- All the settings are saved between sessions (second argument)
local GryModXDistance = CreateClientConVar("gry_xadd", "0", true, false)
local GryModXDistance2 = CreateClientConVar("gry_xdist", "0", true, false)
local GryModXDistance_int = GryModXDistance:GetInt()
local GryModXDistance2_int = GryModXDistance2:GetInt()
local HUDEnabled = CreateClientConVar("gry_hud", "1", true, false, "Draw the GryMod HUD (the quick menu and the suit abilities work without it)")
local SoundsEnabled = CreateClientConVar("gry_sounds", "1", true, false, "Play the GryMod suit sounds")
local GRYOPEN = false
local meta = FindMetaTable("Player")
GryMod.rcr = 105
GryMod.rcg = 235
GryMod.rcb = 100

cvars.AddChangeCallback("gry_xadd", function(convar_name, value_old, value_new)
	GryModXDistance_int = tonumber(value_new) or 0
end)

cvars.AddChangeCallback("gry_xdist", function(convar_name, value_old, value_new)
	GryModXDistance2_int = tonumber(value_new) or 0
end)

-- Every GryMod sound goes through here, so players can switch them off (gry_sounds 0)
function GryMod.PlaySound(path)
	if not SoundsEnabled:GetBool() then
		return false
	end

	surface.PlaySound(path)

	return true
end

function GryMod.SoundsEnabled()
	return SoundsEnabled:GetBool()
end

local gry_icons = {Material("gryarmor.png"), Material("gryspeed.png"), Material("grystrength.png"), Material("grycloak.png"), Material("grydrop.png")}
local base = surface.GetTextureID("cryhud/base")
local compass = surface.GetTextureID("cryhud/compass")

function meta:CanGryMod()
	return self:Alive()
end

-- You can change it , for others admins mods , but you'll have to change it in example : 
--[[  
function meta:CanGryMod() 
	return self:IsAdmin() or self:IsVip() 
end
]]
-- Centre of the quick menu
function GryMod.MenuCenter()
	return ScrW() / 2, ScrH() / 2
end

-- Text drawn at a small angle (1 to 1.2 degrees). Everything that only depends on the angle is computed
-- once, and the matrix, vector and angle objects are reused: nothing is allocated per frame. The caller
-- pushes the texture filters and sets the font and the text colour once for a group of texts.
local rotations = {}

local function rotation(ang)
	local r = rotations[ang]

	if not r then
		local rad = -math.rad(ang)
		local halvedPi = math.pi / 2
		r = {
			sinHalved = math.sin(rad + halvedPi),
			sinRad = math.sin(rad),
			cosHalved = math.cos(rad + halvedPi),
			cosRad = math.cos(rad),
			angle = Angle(0, ang, 0)
		}
		rotations[ang] = r
	end

	return r
end

local textMatrix, textTranslation = Matrix(), Vector(0, 0, 0)

local function drawTextRotated(text, x, y, ang)
	local r = rotation(ang)
	surface.SetTextPos(0, 0)
	local textWidth, textHeight = surface.GetTextSize(text)
	x = x - (r.sinHalved * textWidth / 2 + r.sinRad * textHeight / 2)
	y = y - (r.cosHalved * textWidth / 2 + r.cosRad * textHeight / 2)
	textMatrix:Identity()
	textMatrix:SetAngles(r.angle)
	textTranslation.x = x
	textTranslation.y = y
	textMatrix:SetTranslation(textTranslation)
	cam.PushModelMatrix(textMatrix)
	surface.DrawText(text)
	cam.PopModelMatrix()
end

-- tostring() of the numbers shown in the HUD, kept: the same few values come back every frame
local numberTexts = setmetatable({}, {
	__index = function(t, n)
		local s = tostring(n)
		t[n] = s

		return s
	end
})

local grymodesuit = gry_icons[1] -- Init mode, you better not reload this file, else there will be a de-sync
local crytx = surface.GetTextureID("crysis_button")
local crytx_grid = surface.GetTextureID("crysis_button_grid")
local crycircletx = surface.GetTextureID("crysis_circle")
local cryarrowtx = surface.GetTextureID("crysis_arrow")
local global_mul, global_mul_goal = 0, 0 --The global multiplier, if this is 0 the menu is hidden, 1 and it's fully visible, between 0 and 1 for transition
local selected, oldselected = 0, 0 --Which slot is selected?
local snd_o, snd_c, snd_s, snd_h, snd_e = Sound("cry_open.wav"), Sound("cry_close.wav"), Sound("cry_select.wav"), Sound("cry_hover.wav"), Sound("cry_error.wav")
local crydist = {} --Distance to center for every slot

for i = 1, 5 do
	crydist[i] = 0
end

local nilweps = {weapon_physgun = true, weapon_physcannon = true, weapon_crowbar = true, mod_tool = true} -- Weapons with *infinite* ammo
local armormode = {}
armormode["Armor"] = {}
armormode["Armor"].material = gry_icons[1]
armormode["Armor"].id = GryMod.Modes.ARMOR
armormode["Armor"].selectedtime = 0
armormode["Speed"] = {}
armormode["Speed"].material = gry_icons[2]
armormode["Speed"].id = GryMod.Modes.SPEED
armormode["Speed"].selectedtime = 0
armormode["Strength"] = {}
armormode["Strength"].material = gry_icons[3]
armormode["Strength"].id = GryMod.Modes.STRENGTH
armormode["Strength"].selectedtime = 0
armormode["Cloak"] = {}
armormode["Cloak"].material = gry_icons[4]
armormode["Cloak"].id = GryMod.Modes.CLOAK
armormode["Cloak"].selectedtime = 0
armormode["Drop"] = {}
armormode["Drop"].material = gry_icons[5]
armormode["Drop"].id = GryMod.Modes.DROP
armormode["Drop"].selectedtime = 0
local slots = {} --Standard slots, change these at will
slots[1] = armormode["Cloak"]
slots[2] = armormode["Strength"]
slots[3] = armormode["Speed"]
slots[4] = armormode["Armor"]
slots[5] = armormode["Drop"]

local function px(x)
	return ScrW() * (x / 2560)
end

local iconsposfix = {{px(5), px(8)}, {px(7), px(3)}, {px(0), px(-2)}, {px(-6), px(3)}, {px(-3), px(12)}}

-- cloak
-- strength
-- speed
-- armor
-- drop
function GryMod.MouseInCircle(x, y)
	local centerdist = math.Distance(gui.MouseX(), gui.MouseY(), x, y)

	return centerdist > px(50) and centerdist < px(220)
end

--Checks if the mouse is in the circle
local w = px(90)
-- fow how many seconds you show the grid orange thing effect on buttons after being selected
local timeshowselected = 0.25

function GryMod.CRYHUD()
	local cryx, cryy = GryMod.MenuCenter()

	if (global_mul_goal ~= global_mul) then
		global_mul = global_mul + (global_mul_goal - global_mul) * math.Clamp(FrameTime() * 10, 0, 1) --I love mah math
	end

	local numb = 1
	local cryadd = 360 / 5
	local cursorang = math.fmod(math.atan2(gui.MouseY() - cryy, gui.MouseX() - cryx), math.pi * 2) --This angle shit makes my head implode
	local cursorangd = math.deg(cursorang) + 180

	if (cursorangd >= 0 and cursorangd < cryadd) then
		selected = 4
	elseif (cursorangd >= cryadd and cursorangd < cryadd * 2) then
		selected = 3
	elseif (cursorangd >= cryadd * 2 and cursorangd < cryadd * 3) then
		selected = 2
	elseif (cursorangd >= cryadd * 3 and cursorangd < cryadd * 4) then
		selected = 1
	elseif (cursorangd >= cryadd * 4 and cursorangd < cryadd * 5) then
		selected = 5
	end

	if (global_mul == 0) then
		return
	end

	--Don't run if the menu ain't visible
	if (not GryMod.MouseInCircle(cryx, cryy)) then
		selected = 0
	end

	-- Aka if mouse is not in da circle , dont do anything
	for i = 0 + cryadd / 2, 360 - cryadd / 2, cryadd do
		-- Current selected mode
		local crygraya1 = 131
		local crygraya2 = 176
		local crygraya3 = 131
		local crygraya4 = 250

		if (numb == selected and LocalPlayer():CanGryMod()) then
			crygraya1 = 255
			crygraya2 = 192
			crygraya3 = 80
			crygraya4 = 225
		end

		if not LocalPlayer():CanGryMod() or (numb == selected and not LocalPlayer():CanGryMod()) or (slots[numb].id == GryMod.Modes.DROP and not IsValid(LocalPlayer():GetActiveWeapon())) then
			crygraya1 = 240
			crygraya2 = 27
			crygraya3 = 27
		end

		surface.SetTexture(crytx)

		-- Arrows
		if LocalPlayer():CanGryMod() then
			crydistadd = px(128)
			crygray1 = 255
			crygray2 = 255
			crygray3 = 255
		end

		-- NORMAL
		if not LocalPlayer():CanGryMod() then
			crydistadd = px(128)
			crygray1 = 240
			crygray2 = 23
			crygray3 = 27
		end

		-- ROUGE
		if (numb == selected and LocalPlayer():CanGryMod()) then
			crydistadd = crydistadd * 1.15
		end

		--   ROUGE
		if (slots[numb].id == GryMod.Modes.DROP and not IsValid(LocalPlayer():GetActiveWeapon())) then
			crydistadd = px(128)
			crygray1 = 240
			crygray2 = 23
			crygray3 = 27
		end

		crydist[numb] = crydist[numb] + (crydistadd - crydist[numb]) * math.Clamp(FrameTime() * 20, 0, 1)
		local cryaddx, cryaddy = math.sin(math.rad(i)) * crydist[numb] * global_mul, math.cos(math.rad(i)) * crydist[numb] * global_mul
		surface.SetDrawColor(crygray1, crygray2, crygray3, global_mul * 255) -- button color
		surface.DrawTexturedRectRotated(cryx + cryaddx, cryy + cryaddy, px(128) * global_mul, px(128) * global_mul, i - 180)
		surface.SetMaterial(slots[numb].material)
		surface.SetDrawColor(Color(crygraya1, crygraya2, crygraya3, global_mul * crygraya4))
		surface.DrawTexturedRect(cryx + cryaddx - w / 2 + iconsposfix[numb][1], cryy + cryaddy - w / 2 + iconsposfix[numb][2], w, w)
		local timeSelected = CurTime() - slots[numb].selectedtime

		if (timeSelected < timeshowselected) then
			local alpha = 0

			--first half
			if (timeSelected <= timeshowselected / 2) then
				alpha = math.Remap(timeSelected, 0, timeshowselected / 2, 0, 0.5)
			else
				alpha = math.Remap(timeSelected, timeshowselected / 2, timeshowselected, 0.5, 0)
			end

			surface.SetTexture(crytx_grid)
			surface.SetDrawColor(255, 206, 75, global_mul * 255 * alpha) -- button color
			surface.DrawTexturedRectRotated(cryx + cryaddx, cryy + cryaddy, px(128) * global_mul, px(128) * global_mul, i - 180)
		end

		numb = numb + 1
	end

	if LocalPlayer():CanGryMod() then
		if selected > 0 then
			circlea = 177
			circleb = 206
			circlec = 183
		else
			circlea = 255
			circleb = 255
			circlec = 255
		end
	end

	-- No , i wont use "else"
	if not LocalPlayer():CanGryMod() then
		circlea = 250
		circleb = 23
		circlec = 27
	end

	surface.SetTexture(crycircletx)
	surface.SetDrawColor(circlea, circleb, circlec, global_mul * 200)
	surface.DrawTexturedRectRotated(cryx, cryy, px(128) * global_mul, px(128) * global_mul, math.fmod(CurTime() * -16, 360))

	if GryMod.MouseInCircle(cryx, cryy) then
		surface.SetTexture(cryarrowtx)

		if LocalPlayer():CanGryMod() then
			surface.SetDrawColor(150, 155, 150, global_mul * 255)
		else
			surface.SetDrawColor(255, 23, 27, global_mul * 255)
		end

		local arrowang = math.pi * 2 - cursorang + math.pi / 2
		local arrowdist = px(68) * global_mul
		local arrowx, arrowy = math.sin(arrowang) * arrowdist, math.cos(arrowang) * arrowdist
		surface.DrawTexturedRectRotated(cryx + arrowx, cryy + arrowy, px(64), px(32), math.deg(arrowang) + 180)
	end

	if (selected ~= oldselected and selected ~= 0 and LocalPlayer():CanGryMod()) then
		GryMod.PlaySound(snd_h)

		if (slots[selected].id == GryMod.Modes.DROP and not IsValid(LocalPlayer():GetActiveWeapon())) then
			oldselected = selected
		else
			slots[selected].selectedtime = CurTime()
			oldselected = selected
		end
	end
end

function GryMod.EnableMenu(b)
	GRYOPEN = b

	if (b and global_mul_goal == 0) then
		if LocalPlayer():CanGryMod() then
			GryMod.PlaySound(snd_o)
		else
			GryMod.PlaySound(snd_e)
		end
	end

	gui.EnableScreenClicker(b)

	if (b) then
		global_mul_goal = 1
	else
		global_mul_goal = 0
	end
end

net.Receive("gry_jump", function()
	GryMod.PlaySound("suit/strengthjump.mp3")
end)

function meta:SetNanosuitMode(mode, networked)
	if (mode == LocalPlayer().NanosuitMode) then
		return
	end

	if mode == GryMod.Modes.ARMOR then
		GryMod.PlaySound(Sound("suit/suit_maximum_armor.mp3"))
		GryMod.PlaySound(Sound("suit/suit_armor_108.mp3"))
	end

	if mode == GryMod.Modes.SPEED then
		GryMod.PlaySound(Sound("suit/suit_maximum_speed.mp3"))
		GryMod.PlaySound(Sound("suit/suit_speed_activate_07_good.wa.mp3"))
	end

	if mode == GryMod.Modes.STRENGTH then
		GryMod.PlaySound(Sound("suit/suit_maximum_strength.mp3"))
		GryMod.PlaySound(Sound("suit/strengthmode.mp3"))
	end

	if mode == GryMod.Modes.CLOAK then
		if IsValid(LocalPlayer()) and IsValid(LocalPlayer():GetViewModel()) then
			LocalPlayer():GetViewModel():SetMaterial("cloak/organic")

			-- some gamemodes do not give c_arms hands
			if IsValid(LocalPlayer():GetHands()) then
				LocalPlayer():GetHands():SetMaterial("cloak/organic")
			end

			GryMod.PlaySound(Sound("suit/suit_modification_engaged.mp3"))
			GryMod.PlaySound(Sound("suit/suit_cloak_chameleon_101_r.mp3"))
		end
	elseif IsValid(LocalPlayer()) and IsValid(LocalPlayer():GetViewModel()) then
		LocalPlayer():GetViewModel():SetMaterial("")

		if IsValid(LocalPlayer():GetHands()) then
			LocalPlayer():GetHands():SetMaterial("")
		end
	end

	if mode == GryMod.Modes.DROP then
		net.Start("gry_drop")
		net.SendToServer()
	else
		if networked then
			net.Start("gry_nanosuit_mode_change")
			net.WriteUInt(mode, 3)
			net.SendToServer()
		end

		LocalPlayer().NanosuitMode = mode

		for k, v in pairs(armormode) do
			if v.id == mode then
				grymodesuit = v.material
				break
			end
		end
	end
	-- it's not a real mode so don't change anything
end

-- The server decides the mode (at every respawn it goes back to Armor). This must not wait for the
-- player to be alive on the client: the respawn message can arrive first, and a client that kept its old
-- mode ignores the player picking that mode again, so the suit stayed in Armor with a Speed icon.
function GryMod.ApplyServerMode(mode)
	if not IsValid(LocalPlayer()) then
		return
	end

	LocalPlayer():SetNanosuitMode(mode, false)
end

net.Receive("gry_nanosuit_mode_change", function()
	GryMod.ApplyServerMode(net.ReadUInt(3))
end)

function GryMod.CryOpenClose(ply, command, args)
	local cryx, cryy = GryMod.MenuCenter()

	if (LocalPlayer():CanGryMod() and command ~= "+crysishud") then
		if (GryMod.MouseInCircle(cryx, cryy)) then
			GryMod.PlaySound(snd_s)

			if slots[selected] then
				LocalPlayer():SetNanosuitMode(slots[selected].id, true)
			end
		elseif (global_mul_goal == 1) then
			GryMod.PlaySound(snd_c)
		end
	end

	GryMod.EnableMenu(command == "+crysishud") --Enable menu if it's +crysishud, disable otherwise
end

concommand.Add("+crysishud", GryMod.CryOpenClose)
concommand.Add("-crysishud", GryMod.CryOpenClose)

----------------------------------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------
function GryMod.CloackAttack(ply, key)
	if key == IN_ATTACK and LocalPlayer().NanosuitMode == GryMod.Modes.CLOAK then
		LocalPlayer():SetNanosuitMode(GryMod.Modes.ARMOR, true)
		net.Start("gry_empty_energy")
		net.SendToServer() -- too lazy to fight cheaters
	end
end

local Gry_Danger = {0, 0, 0, 0} -- heights of the four radar bars

-- Heights of the four radar bars for a number of NPCs around the player. Each bar starts to grow
-- 4 NPCs after the previous one; they used to go negative below that.
function GryMod.RadarLevels(count)
	return math.Clamp(math.MapSimple(count * 5, 20, 17), 0, 17.9),
		math.Clamp(math.MapSimple((count - 4) * 5, 20, 22), 0, 22),
		math.Clamp(math.MapSimple((count - 8) * 5, 20, 20), 0, 20),
		math.Clamp(math.MapSimple((count - 12) * 5, 20, 19), 0, 19)
end

function GryMod.CountNearbyNPCs()
	local count = 0

	for _, ent in ipairs(ents.FindInSphere(LocalPlayer():GetPos(), 1280)) do
		if ent:IsNPC() then
			count = count + 1
		end
	end

	return count
end

function GryMod.UpdateRadar()
	if not IsValid(LocalPlayer()) then
		return
	end

	local count = GryMod.CountNearbyNPCs()
	local raderpers = math.Min(math.MapSimple(count, 20, 150), 150) -- For the color
	GryMod.rcr = 105 + raderpers
	GryMod.rcg = 235 - raderpers * 1.5
	GryMod.rcb = 100 - (raderpers / 1.8)
	Gry_Danger[1], Gry_Danger[2], Gry_Danger[3], Gry_Danger[4] = GryMod.RadarLevels(count)
end

-- One named timer: loading the file again replaces it instead of stacking another one
function GryMod.StartRadar()
	timer.Create("GryModRadar", 0.1, 0, GryMod.UpdateRadar)
end

GryMod.StartRadar()
-- Everything the HUD draws that only depends on the screen size and the position offsets (rectangles,
-- polygons, text positions) is computed here, once, and again only when one of them changes. The
-- expressions are the ones the HUD used to evaluate every frame, in the same order, so the numbers are
-- the same ones.
local layout, layoutScrW, layoutScrH, layoutXa, layoutXd

local function pt(x, y)
	return {x = x, y = y}
end

local function buildLayout(W, H, xa, xd)
	local L = {W = W, H = H, xa = xa, xd = xd}
	local full = W * (219 / 1920)
	L.full = full

	L.baseX, L.baseY, L.baseS = W - (W / 4.06) + xa + xd, H - (W / 5.19), W / 4.26
	L.compassX, L.compassY, L.compassS = W * (10 / 1920) - xa + xd, H - (W / 7.111), W * (290 / 1920)

	-- radar: four bars and a triangle
	L.radarX = W * (64 / 1920) - xa + xd
	L.radarW = W * (13 / 1920)
	L.radarY = {H - W * (100 / 1920), H - W * (120.8 / 1920), H - W * (145.5 / 1920), H - W * (168.4 / 1920)}
	L.radarPoly = {
		pt(W * (64 / 1920) - xa + xd, H - W * (99.8 / 1920)),
		pt(W * (77 / 1920) - xa + xd, H - W * (100 / 1920)),
		pt(W * (77 / 1920) - xa + xd, H - W * (92 / 1920))
	}

	-- texts and icons
	L.grenX, L.grenY = W - (W / 9) + xa + xd, H - (W / 11)
	L.healthX, L.healthY = W - (W / 10) + xa + xd, H - (W / 22)
	L.energyX, L.energyY = W - (W / 10) + xa + xd, H - (W / 16)
	L.modeX, L.modeY, L.modeS = (W - (W / 13.1)) + xa + xd, H - (W / 15.5), W * (100 / 1920)
	L.infinityX, L.infinityY = W - (W / 8) + xa + xd, H - (W / 8.4)
	L.ammoX, L.ammoY = W - (W / 7.5) + xa + xd, H - (W / 8.4)

	-- compass: the mask the letters are clipped to, and the terms of the letters' positions
	local xs = -1 * xa + xd
	L.maskPoly = {
		pt(xs + W * (072 / 1920), H - W * (215 / 1920)),
		pt(xs + W * (273 / 1920), H - W * (227 / 1920)),
		pt(xs + W * (294 / 1920), H - W * (207 / 1920)),
		pt(xs + W * (061 / 1920), H - W * (194 / 1920)),
		pt(xs + W * (060 / 1920), H - W * (204 / 1920))
	}
	L.letterX = W * (20 / 1920) - xa + xd
	L.letterXAdd = W * (134 / 1920)
	L.letterY = H - W * (218 / 1920)
	L.letterYAdd = W * (-5 / 1920)

	-- energy and health bars: a polygon the bar is clipped to, and the bar itself
	local xsum = xa + xd
	local function barPt(c, ch)
		return pt(xsum + W - W * (c / 1920), H - W * (ch / 1920))
	end

	L.energyPoly1 = {barPt(446, 136), barPt(436, 144), barPt(277, 136), barPt(277, 113.5), barPt(446, 122)}
	L.energyPoly2 = {barPt(270, 135.5), barPt(228, 133), barPt(228, 111), barPt(270, 113.5)}
	L.healthPoly1 = {barPt(446, 112), barPt(277, 102.5), barPt(277, 81.5), barPt(436, 91), barPt(446, 97)}
	L.healthPoly2 = {barPt(270, 102), barPt(228, 99.5), barPt(228, 78.5), barPt(270, 81)}
	L.barBaseX = xsum + W - W * (446 / 1920)
	L.energyBarY, L.healthBarY, L.barH = H - W * (144 / 1920), H - W * (113 / 1920), W * (37 / 1920)

	return L
end

-- The layout for the current screen and settings: the same table until one of them changes
function GryMod.GetHudLayout()
	local w, h = ScrW(), ScrH()

	if not layout or w ~= layoutScrW or h ~= layoutScrH or GryModXDistance_int ~= layoutXa or GryModXDistance2_int ~= layoutXd then
		layoutScrW, layoutScrH, layoutXa, layoutXd = w, h, GryModXDistance_int, GryModXDistance2_int
		layout = buildLayout(w, h, GryModXDistance_int, GryModXDistance2_int)
	end

	return layout
end

-- Position of one compass letter (1 = N, 2 = NE ... 8 = NW) for a player yaw
local compassLetters = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"}
local compassOffsets = {0, 45, 90, 135, false, -135, -90, -45}

local function compassPosition(L, index, yaw)
	local ly = yaw + 6.256798
	local v

	if compassOffsets[index] then
		v = ly + compassOffsets[index]
	else
		-- south wraps around +-180
		v = math.max(math.NormalizeAngle(ly + 180), math.NormalizeAngle(ly - 180))
	end

	-- every letter moves by 3.32 pixels per degree (south used to use 5, so it ran 50 % faster than the rest)
	return L.letterX + (v * 3.32) + L.letterXAdd, L.letterY - ((v * 3.32) / 15) + L.letterYAdd
end

function GryMod.CompassPosition(index, yaw)
	return compassPosition(GryMod.GetHudLayout(), index, yaw)
end

local lastClip, lastExtra, lastGrenades, ammoText

-- "clip | reserve || grenades" is only rebuilt when one of the numbers changes
local function ammoLine(clip, extra, grenades)
	if clip ~= lastClip or extra ~= lastExtra or grenades ~= lastGrenades then
		lastClip, lastExtra, lastGrenades = clip, extra, grenades

		if clip == -1 then
			ammoText = extra .. "  ||  " .. grenades
		else
			ammoText = clip .. " | " .. extra .. "  ||  " .. grenades
		end
	end

	return ammoText
end

function GryMod.hudbase()
	local L = GryMod.GetHudLayout()
	local ply = LocalPlayer()
	surface.SetTexture(base)
	surface.SetDrawColor(220, 235, 220, 200)
	surface.DrawTexturedRect(L.baseX, L.baseY, L.baseS, L.baseS)
	surface.SetTexture(compass)
	surface.SetDrawColor(220, 235, 220, 200)
	surface.DrawTexturedRect(L.compassX, L.compassY, L.compassS, L.compassS)
	------------------------------------------------/
	---------------- START RADAR --------------------
	------------------------------------------------/
	local W = L.W
	surface.SetDrawColor(GryMod.rcr, GryMod.rcg, GryMod.rcb, 255)

	for i = 1, 4 do
		local height = W * (Gry_Danger[i] / 1920)
		surface.DrawRect(L.radarX, L.radarY[i] - height, L.radarW, height)
	end

	draw.NoTexture()
	surface.DrawPoly(L.radarPoly)
	--------------------------------------------------------------
	---------------------- END RADAR -----------------------------
	--------------------------------------------------------------
	render.PushFilterMag(TEXFILTER.ANISOTROPIC)
	render.PushFilterMin(TEXFILTER.ANISOTROPIC)
	surface.SetFont("CrysisInfos")
	surface.SetTextColor(190, 195, 190, 255)
	drawTextRotated(numberTexts[ply:GetAmmoCount("grenade")], L.grenX, L.grenY, 1.2)
	drawTextRotated(numberTexts[ply:Health()], L.healthX, L.healthY, 1)
	local nbener = ply:GetNWFloat("GryEnergy")
	drawTextRotated(numberTexts[math.Round(nbener)], L.energyX, L.energyY, 1.2)
	render.PopFilterMag()
	render.PopFilterMin()
	surface.SetMaterial(grymodesuit)
	surface.SetDrawColor(150, 195, 150, 155)
	surface.DrawTexturedRect(L.modeX, L.modeY, L.modeS, L.modeS)
	local weapon = ply:GetActiveWeapon()

	if weapon:IsValid() then
		render.PushFilterMag(TEXFILTER.ANISOTROPIC)
		render.PushFilterMin(TEXFILTER.ANISOTROPIC)
		surface.SetFont("CrysisInfos")
		surface.SetTextColor(190, 195, 190, 255)

		if nilweps[weapon:GetClass()] then
			drawTextRotated("∞", L.infinityX, L.infinityY, 1.2)
			-- Because the ammo is  -1 with grenades
		else
			local extra = ply:GetAmmoCount(weapon:GetPrimaryAmmoType())
			local grenum = ply:GetAmmoCount(weapon:GetSecondaryAmmoType())
			drawTextRotated(ammoLine(weapon:Clip1(), extra, grenum), L.ammoX, L.ammoY, 1.2)
		end

		render.PopFilterMag()
		render.PopFilterMin()
	end

	-- The bars and the compass are clipped with the stencil buffer. It is cleared once, and every
	-- clipped shape gets a reference value of its own (it used to be cleared before each one).
	local nbhlt = ply:Health()
	local healthoffset = (nbhlt / 100) * L.full -- math.Remap(nbhlt, 0, 100, 0, full)
	local energyoffset = (nbener / 100) * L.full
	local full = L.full
	render.ClearStencil()
	render.SetStencilEnable(true)
	render.SetStencilWriteMask(255)
	render.SetStencilTestMask(255)
	render.SetStencilFailOperation(STENCILOPERATION_ZERO)
	render.SetStencilPassOperation(STENCILOPERATION_REPLACE)
	render.SetStencilZFailOperation(STENCILOPERATION_KEEP)

	-- compass: letters only inside the mask
	render.SetStencilReferenceValue(1)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
	surface.SetDrawColor(255, 255, 255, 255)
	render.SetBlend(0)
	surface.DrawPoly(L.maskPoly)
	render.SetBlend(1)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)
	local yaw = ply:EyeAngles().y
	surface.SetFont("ScoreboardText")
	surface.SetTextColor(255, 255, 255, 255)

	for i = 1, 8 do
		local x, y = compassPosition(L, i, yaw)
		surface.SetTextPos(math.ceil(x), math.ceil(y))
		surface.DrawText(compassLetters[i])
	end

	-- energy, right part
	render.SetStencilReferenceValue(2)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawPoly(L.energyPoly1)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)
	surface.SetDrawColor(20, 150, 230, 200)
	surface.DrawRect(L.barBaseX + (full - energyoffset), L.energyBarY, full - (full - energyoffset), L.barH)

	-- health, right part
	render.SetStencilReferenceValue(3)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawPoly(L.healthPoly1)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)
	surface.SetDrawColor(116, 194, 27, 200)
	surface.DrawRect(L.barBaseX + (full - healthoffset), L.healthBarY, full - (full - healthoffset), L.barH)

	-- health, left part: red under 20
	render.SetStencilReferenceValue(4)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
	surface.SetDrawColor(255, 255, 255, 255)
	render.SetBlend(0)
	surface.DrawPoly(L.healthPoly2)
	render.SetBlend(1)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)

	if nbhlt > 20 then
		surface.SetDrawColor(116, 194, 27, 200)
	else
		surface.SetDrawColor(240, 23, 27, 200)
	end

	surface.DrawRect(L.barBaseX + (full - healthoffset), L.healthBarY, full - (full - healthoffset), L.barH)

	-- energy, left part: red under 20
	render.SetStencilReferenceValue(5)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
	surface.SetDrawColor(255, 255, 255, 255)
	render.SetBlend(0)
	surface.DrawPoly(L.energyPoly2)
	render.SetBlend(1)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)

	if nbener > 20 then
		surface.SetDrawColor(20, 150, 230, 200)
	else
		surface.SetDrawColor(240, 23, 27, 200)
	end

	surface.DrawRect(L.barBaseX + (full - energyoffset), L.energyBarY, full - (full - energyoffset), L.barH)
	render.SetStencilEnable(false)
end

local inited = false

------------------------------------------
net.Receive("gry_spawn", function()
	if gamemode.Get("sandbox") and inited == false then
		GAMEMODE:AddNotify("To open GryMod menu, bind a key to +crysishud ", NOTIFY_GENERIC, 15)
		GAMEMODE:AddNotify("Check the console for more informations ", NOTIFY_GENERIC, 13)

		if not file.Exists("resource/fonts/Agency FB.ttf", "GAME") then
			GAMEMODE:AddNotify("You don't have the required Font fix, check console to get the download link!", NOTIFY_GENERIC, 20)
		else
			GAMEMODE:AddNotify("Font fix installed ( ͡° ͜ʖ ͡°)", NOTIFY_GENERIC, 10)
		end

		inited = true
	end
end)

----------------FIX----------------
local MOUSE_CHECK_DIST = px(160)

function GryMod.RadialThink()
	if not GRYOPEN then
		return
	end

	-- keep the cursor around the centre of the menu
	local cx, cy = GryMod.MenuCenter()
	local hypotenus = math.Distance(gui.MouseX(), gui.MouseY(), cx, cy)

	if (hypotenus > MOUSE_CHECK_DIST) then
		local distx = math.abs(cx - gui.MouseX())
		local angle = math.abs(math.acos(distx / hypotenus) * 180 / math.pi)

		if (tostring(angle) == "nan") then
			return
		end

		local newtriangle_hypotenus = MOUSE_CHECK_DIST
		local multx = 1 -- change direction of x and y because we're not just working with a triangle now, you need to define the "orientation of the triangle"
		local multy = 1

		if (gui.MouseX() < cx) then
			multx = -1
		end

		if (gui.MouseY() < cy) then
			multy = -1
		end

		local newx = (math.cos(angle / (180 / math.pi)) * newtriangle_hypotenus) * multx
		local newy = (math.sin(angle / (180 / math.pi)) * newtriangle_hypotenus) * multy
		gui.SetMousePos(cx + newx, cy + newy)
	end
end

local hidethings = {
	["CHudHealth"] = true,
	["CHudBattery"] = true,
	["CHudAmmo"] = true,
	["CHudSecondaryAmmo"] = true
}

local function HUDShouldDraw(name)
	if (hidethings[name]) then
		return false
	end
end

-- The HUD (health, energy, ammo, radar, compass) can be turned off with gry_hud 0 or from the options
-- menu; the quick menu and the suit abilities keep working. The choice is saved with the convar.
local function applyHUD(enabled)
	if enabled then
		hook.Add("HUDPaint", "HUDBASECRY", GryMod.hudbase)
		hook.Add("HUDShouldDraw", "How to: HUD Example HUD hider", HUDShouldDraw)
	else
		hook.Remove("HUDPaint", "HUDBASECRY")
		hook.Remove("HUDShouldDraw", "How to: HUD Example HUD hider")
	end
end

function GryMod.SetHUDEnabled(enabled)
	HUDEnabled:SetBool(enabled)
	applyHUD(enabled)
end

-- the options menu (or the console) changes the convar: follow it
cvars.AddChangeCallback("gry_hud", function(convar_name, value_old, value_new)
	applyHUD(tonumber(value_new) ~= 0)
end, "GryModHUD")

hook.Add("HUDPaint", "GRYHUD", GryMod.CRYHUD)
hook.Add("KeyPress", "AttackDetection", GryMod.CloackAttack)
hook.Add("Think", "HueHue fix normal shit", GryMod.RadialThink)
GryMod.SetHUDEnabled(HUDEnabled:GetBool())