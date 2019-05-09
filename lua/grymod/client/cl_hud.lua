--Yeah, fuck you, the guys with shitty monitors.
local color_white = color_white
local GryModXDistance = CreateClientConVar("gry_xadd", "0", false, false)
local GryModXDistance2 = CreateClientConVar("gry_xdist", "0", false, false)
local GryModXDistance_int = GryModXDistance:GetInt()
local GryModXDistance2_int = GryModXDistance2:GetInt()
local EyeFinity = CreateClientConVar("cl_Eyefinity", "0", false, false)
local GRYOPEN = false
local meta = FindMetaTable("Player")
GryMod.rcr = 105
GryMod.rcg = 235
GryMod.rcb = 100

cvars.AddChangeCallback("gry_xadd", function(convar_name, value_old, value_new)
	GryModXDistance_int = value_new
end)

cvars.AddChangeCallback("gry_xdist", function(convar_name, value_old, value_new)
	GryModXDistance2_int = value_new
end)

local gry_icons = {Material("gryarmor.png"), Material("gryspeed.png"), Material("grystrength.png"), Material("grycloak.png"), Material("grydrop.png")}
local tempscrw = ScrW()
local tempscrh = ScrH()
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
function GryMod.EyeFinityScrW()
	if EyeFinity:GetInt() > 0 then
		return tempscrw / 3
	else
		return tempscrw
	end
end

local function drawTextRotated(text, font, x, y, color, ang)
	render.PushFilterMag(TEXFILTER.ANISOTROPIC)
	render.PushFilterMin(TEXFILTER.ANISOTROPIC)
	surface.SetFont(font)
	surface.SetTextColor(color)
	surface.SetTextPos(0, 0)
	local textWidth, textHeight = surface.GetTextSize(text)
	local rad = -math.rad(ang)
	local halvedPi = math.pi / 2
	x = x - (math.sin(rad + halvedPi) * textWidth / 2 + math.sin(rad) * textHeight / 2)
	y = y - (math.cos(rad + halvedPi) * textWidth / 2 + math.cos(rad) * textHeight / 2)
	local m = Matrix()
	m:SetAngles(Angle(0, ang, 0))
	m:SetTranslation(Vector(x, y, 0))
	cam.PushModelMatrix(m)
	surface.DrawText(text)
	cam.PopModelMatrix()
	render.PopFilterMag()
	render.PopFilterMin()
end


local grymodesuit = gry_icons[1] -- Init mode, you better not reload this file, else there will be a de-sync

local crytx = surface.GetTextureID("crysis_button")
local crytx_grid = surface.GetTextureID("crysis_button_grid")
local crycircletx = surface.GetTextureID("crysis_circle")
local cryarrowtx = surface.GetTextureID("crysis_arrow")
local global_mul, global_mul_goal = 0, 0 --The global multiplier, if this is 0 the menu is hidden, 1 and it's fully visible, between 0 and 1 for transition
local cryx, cryy = GryMod.EyeFinityScrW() / 2, tempscrh / 2 --Changing this makes the menu appear in a different place
local selected, oldselected = 0, 0 --Which slot is selected?
local snd_o, snd_c, snd_s, snd_h, snd_e = Sound("cry_open.wav"), Sound("cry_close.wav"), Sound("cry_select.wav"), Sound("cry_hover.wav"), Sound("cry_error.wav")
local crydist = {} --Distance to center for every slot

for i = 1, 5 do
	crydist[i] = 0
end

local nilweps = {"weapon_physgun", "weapon_physcannon", "weapon_crowbar", "mod_tool"} -- Weapons with *infinite* ammo
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


local iconsposfix = {
{5,8}, -- cloak
{7,3}, -- strength
{0,-2}, -- speed
{-6,3}, -- armor
{-3,12}, -- drop
}

function GryMod.MouseInCircle(x, y)
	local centerdist = math.Distance(gui.MouseX(), gui.MouseY(), x, y)

	return centerdist > 50 and centerdist < 220
end

--Checks if the mouse is in the circle
local w = 90

-- fow how many seconds you show the grid orange thing effect on buttons after being selected
local timeshowselected = 0.25

function GryMod.CRYHUD()
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
			crydistadd = 128
			crygray1 = 255
			crygray2 = 255
			crygray3 = 255
		end

		-- NORMAL
		if not LocalPlayer():CanGryMod() then
			crydistadd = 128
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
			crydistadd = 128
			crygray1 = 240
			crygray2 = 23
			crygray3 = 27
		end

		crydist[numb] = crydist[numb] + (crydistadd - crydist[numb]) * math.Clamp(FrameTime() * 20, 0, 1)
		local cryaddx, cryaddy = math.sin(math.rad(i)) * crydist[numb] * global_mul, math.cos(math.rad(i)) * crydist[numb] * global_mul
		surface.SetDrawColor(crygray1, crygray2, crygray3, global_mul * 255) -- button color
		surface.DrawTexturedRectRotated(cryx + cryaddx, cryy + cryaddy, 128 * global_mul, 128 * global_mul, i - 180)


		surface.SetMaterial(slots[numb].material)
		surface.SetDrawColor(Color(crygraya1, crygraya2, crygraya3, global_mul * crygraya4))

		surface.DrawTexturedRect(cryx + cryaddx - w / 2 + iconsposfix[numb][1], cryy + cryaddy - w / 2 + iconsposfix[numb][2], w, w)


		local timeSelected = CurTime() - slots[numb].selectedtime
		
		if (timeSelected < timeshowselected) then
			local alpha = 0;
			 --first half
			if (timeSelected <= timeshowselected / 2 ) then
				alpha = math.Remap(timeSelected, 0, timeshowselected / 2, 0, 0.5)
			else
				alpha = math.Remap(timeSelected, timeshowselected / 2,timeshowselected , 0.5,0)
			end
			surface.SetTexture(crytx_grid)
			surface.SetDrawColor(255, 206, 75, global_mul * 255 * alpha) -- button color
			surface.DrawTexturedRectRotated(cryx + cryaddx, cryy + cryaddy, 128 * global_mul, 128 * global_mul, i - 180)
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
	surface.DrawTexturedRectRotated(cryx, cryy, 128 * global_mul, 128 * global_mul, math.fmod(CurTime() * -16, 360))

	if GryMod.MouseInCircle(cryx, cryy) then
		surface.SetTexture(cryarrowtx)
		if LocalPlayer():CanGryMod() then
			surface.SetDrawColor(150, 155, 150, global_mul * 255)
		else
			surface.SetDrawColor(255, 23, 27, global_mul * 255)
		end
		local arrowang = math.pi * 2 - cursorang + math.pi / 2
		local arrowdist = 68 * global_mul
		local arrowx, arrowy = math.sin(arrowang) * arrowdist, math.cos(arrowang) * arrowdist
		surface.DrawTexturedRectRotated(cryx + arrowx, cryy + arrowy, 64 , 32 , math.deg(arrowang) + 180)
	end

	if (selected ~= oldselected and selected ~= 0 and LocalPlayer():CanGryMod()) then

		surface.PlaySound(snd_h)
		if (slots[selected].id == GryMod.Modes.DROP and not IsValid(LocalPlayer():GetActiveWeapon())) then
			oldselected = selected
		else
			slots[selected].selectedtime = CurTime()
			oldselected = selected
		end
	end
end

function GryMod.EnableMenu(b)
	if (b and global_mul_goal == 0) then
		if LocalPlayer():CanGryMod() then
			surface.PlaySound(snd_o)
		else
			surface.PlaySound(snd_e)
		end
		GRYOPEN = true
	end

	gui.EnableScreenClicker(b)

	if (b) then
		global_mul_goal = 1
	else
		global_mul_goal = 0
	end

	if not b then
		GRYOPEN = false
	end
end

net.Receive("gry_jump", function()
	surface.PlaySound("suit/strengthjump.mp3")
end)

function meta:SetNanosuitMode(mode, networked)
	if (mode == LocalPlayer().NanosuitMode) then return end
	if mode == GryMod.Modes.ARMOR then
		surface.PlaySound(Sound("suit/suit_maximum_armor.mp3"))
		surface.PlaySound(Sound("suit/suit_armor_108.mp3"))
	end

	if mode == GryMod.Modes.SPEED then
		surface.PlaySound(Sound("suit/suit_maximum_speed.mp3"))
		surface.PlaySound(Sound("suit/suit_speed_activate_07_good.wa.mp3"))
	end

	if mode == GryMod.Modes.STRENGTH then
		surface.PlaySound(Sound("suit/suit_maximum_strength.mp3"))
		surface.PlaySound(Sound("suit/strengthmode.mp3"))
	end

	if mode == GryMod.Modes.CLOAK then
		if IsValid(LocalPlayer()) and IsValid(LocalPlayer():GetViewModel()) then
			LocalPlayer():GetViewModel():SetMaterial("cloak/organic")
			LocalPlayer():GetHands():SetMaterial("cloak/organic") -- ask someone to fix that
			surface.PlaySound(Sound("suit/suit_modification_engaged.mp3"))
			surface.PlaySound(Sound("suit/suit_cloak_chameleon_101_r.mp3"))
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
	end -- it's not a real mode so don't change anything
end

net.Receive("gry_nanosuit_mode_change", function()
	if not IsValid(LocalPlayer()) or not LocalPlayer():Alive() then
		return
	end

	local mode = net.ReadUInt(3)
	LocalPlayer():SetNanosuitMode(mode, false)
end)

function GryMod.CryOpenClose(ply, command, args)



	if (LocalPlayer():CanGryMod() and command ~= "+crysishud") then
		if (GryMod.MouseInCircle(cryx, cryy)) then
			surface.PlaySound(snd_s)
			if slots[selected] then
				LocalPlayer():SetNanosuitMode(slots[selected].id, true)
			end

		elseif (global_mul_goal == 1) then
			surface.PlaySound(snd_c)
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





function GryMod.mathradar()
	radarnpc = {}

	if IsValid(LocalPlayer()) then
		for k, v in pairs(ents.FindInSphere(LocalPlayer():GetPos(), 1280)) do
			if v:IsNPC() then
				table.insert(radarnpc, v)
			end
		end

		for k, v in pairs(radarnpc) do
			if not table.HasValue(ents.FindInSphere(LocalPlayer():GetPos(), 1280), v) then
				table.remove(radarnpc, k)
			end
		end

		raderpers = math.Min(math.MapSimple(table.Count(radarnpc), 20, 150), 150) -- For the color
		levelEnemies = math.Min(math.MapSimple(table.Count(radarnpc), 20, 100), 100) -- For the API/Level of the texture
		GryMod.rcr = 105 + raderpers
		GryMod.rcg = 235 - raderpers * 1.5
		GryMod.rcb = 100 - (raderpers / 1.8)
		Gry_Danger0 = math.Min(math.MapSimple(table.Count(radarnpc) * 5, 20, 17), 17.9)
		Gry_Danger1 = math.Min(math.MapSimple((table.Count(radarnpc) - 4) * 5, 20, 22), 22)
		Gry_Danger2 = math.Min(math.MapSimple((table.Count(radarnpc) - 8) * 5, 20, 20), 20)
		Gry_Danger3 = math.Min(math.MapSimple((table.Count(radarnpc) - 12) * 5, 20, 19), 19)
	end

	timer.Simple(0.1, GryMod.mathradar)
end

GryMod.mathradar()
local alpha_ch = {0, 0}

function GryMod.hudbase()
	alpha_ch[1] = 200
	alpha_ch[2] = 255
	r_ch = 0
	g_ch = 0
	b_ch = 0
	surface.SetTexture(base)
	surface.SetDrawColor(Color(220, 235, 220, alpha_ch[1]))
	surface.DrawTexturedRect(GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW() / 4.06) + GryModXDistance_int + GryModXDistance2_int, tempscrh - (GryMod.EyeFinityScrW() / 5.19), GryMod.EyeFinityScrW() / 4.26, GryMod.EyeFinityScrW() / 4.26)
	surface.SetTexture(compass)
	surface.SetDrawColor(Color(220, 235, 220, alpha_ch[1]))
	surface.DrawTexturedRect(GryMod.EyeFinityScrW() * (10 / 1920) - GryModXDistance_int + GryModXDistance2_int, tempscrh - (GryMod.EyeFinityScrW() / 7.111), GryMod.EyeFinityScrW() * (290 / 1920), GryMod.EyeFinityScrW() * (290 / 1920))
	------------------------------------------------/
	---------------- START RADAR --------------------
	------------------------------------------------/
	surface.SetDrawColor(Color(GryMod.rcr, GryMod.rcg, GryMod.rcb, 255))
	surface.DrawRect(GryMod.EyeFinityScrW() * (64 / 1920) - GryModXDistance_int + GryModXDistance2_int, tempscrh - GryMod.EyeFinityScrW() * (100 / 1920) - GryMod.EyeFinityScrW() * (Gry_Danger0 / 1920), GryMod.EyeFinityScrW() * (13 / 1920), GryMod.EyeFinityScrW() * (Gry_Danger0 / 1920))
	surface.SetDrawColor(Color(GryMod.rcr, GryMod.rcg, GryMod.rcb, 255))
	surface.DrawRect(GryMod.EyeFinityScrW() * (64 / 1920) - GryModXDistance_int + GryModXDistance2_int, tempscrh - GryMod.EyeFinityScrW() * (120.8 / 1920) - GryMod.EyeFinityScrW() * (Gry_Danger1 / 1920), GryMod.EyeFinityScrW() * (13 / 1920), GryMod.EyeFinityScrW() * (Gry_Danger1 / 1920))
	surface.SetDrawColor(Color(GryMod.rcr, GryMod.rcg, GryMod.rcb, 255))
	surface.DrawRect(GryMod.EyeFinityScrW() * (64 / 1920) - GryModXDistance_int + GryModXDistance2_int, tempscrh - GryMod.EyeFinityScrW() * (145.5 / 1920) - GryMod.EyeFinityScrW() * (Gry_Danger2 / 1920), GryMod.EyeFinityScrW() * (13 / 1920), GryMod.EyeFinityScrW() * (Gry_Danger2 / 1920))
	surface.SetDrawColor(Color(GryMod.rcr, GryMod.rcg, GryMod.rcb, 255))
	surface.DrawRect(GryMod.EyeFinityScrW() * (64 / 1920) - GryModXDistance_int + GryModXDistance2_int, tempscrh - GryMod.EyeFinityScrW() * (168.4 / 1920) - GryMod.EyeFinityScrW() * (Gry_Danger3 / 1920), GryMod.EyeFinityScrW() * (13 / 1920), GryMod.EyeFinityScrW() * (Gry_Danger3 / 1920))
	surface.SetDrawColor(GryMod.rcr, GryMod.rcg, GryMod.rcb, 255)
	draw.NoTexture()

	surface.DrawPoly({
		{
			x = GryMod.EyeFinityScrW() * (64 / 1920) - GryModXDistance_int + GryModXDistance2_int,
			y = tempscrh - GryMod.EyeFinityScrW() * (99.8 / 1920)
		},
		{
			x = GryMod.EyeFinityScrW() * (77 / 1920) - GryModXDistance_int + GryModXDistance2_int,
			y = tempscrh - GryMod.EyeFinityScrW() * (100 / 1920)
		},
		{
			x = GryMod.EyeFinityScrW() * (77 / 1920) - GryModXDistance_int + GryModXDistance2_int,
			y = tempscrh - GryMod.EyeFinityScrW() * (92 / 1920)
		}
	})

	--------------------------------------------------------------
	---------------------- END RADAR -----------------------------
	--------------------------------------------------------------
	drawTextRotated(LocalPlayer():GetAmmoCount("grenade"), "CrysisInfos", GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW() / 9) + GryModXDistance_int + GryModXDistance2_int, tempscrh - (GryMod.EyeFinityScrW() / 11), Color(190, 195, 190, alpha_ch[2]), 1.2) -- Fixed in v2.3
	drawTextRotated(LocalPlayer():Health(), "CrysisInfos", GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW() / 10) + GryModXDistance_int + GryModXDistance2_int, tempscrh - (GryMod.EyeFinityScrW() / 22), Color(190, 195, 190, alpha_ch[2]), 1) -- Fixed in v2.3
	drawTextRotated(math.Round(LocalPlayer():GetNWFloat("GryEnergy")), "CrysisInfos", GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW() / 10) + GryModXDistance_int + GryModXDistance2_int, tempscrh - (GryMod.EyeFinityScrW() / 16), Color(190, 195, 190, alpha_ch[2]), 1.2) -- Fixed in v2.3
	local modeposw = GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW() / 13.1)
	local modeposh = tempscrh - (GryMod.EyeFinityScrW() / 15.5)
	surface.SetMaterial(grymodesuit)
	surface.SetDrawColor(Color(150, 195, 150, alpha_ch[2] - 100))
	surface.DrawTexturedRect(modeposw + GryModXDistance_int + GryModXDistance2_int, modeposh, GryMod.EyeFinityScrW() * (100 / 1920), GryMod.EyeFinityScrW() * (100 / 1920))

	if LocalPlayer():GetActiveWeapon():IsValid() then
		if table.HasValue(nilweps, LocalPlayer():GetActiveWeapon():GetClass()) then
			drawTextRotated("∞", "CrysisInfos", GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW() / 8) + GryModXDistance_int + GryModXDistance2_int, tempscrh - (GryMod.EyeFinityScrW() / 8.4), Color(190, 195, 190, alpha_ch[2]), 1.2)
			-- Because the ammo is  -1 with grenades
		else
			local extra = LocalPlayer():GetAmmoCount(LocalPlayer():GetActiveWeapon():GetPrimaryAmmoType())
			local ammonum = LocalPlayer():GetActiveWeapon():Clip1()
			local grenum = LocalPlayer():GetAmmoCount(LocalPlayer():GetActiveWeapon():GetSecondaryAmmoType())

			if (ammonum == -1) then
				drawTextRotated(extra .. "  ||  " .. grenum, "CrysisInfos", GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW() / 7.5) + GryModXDistance_int + GryModXDistance2_int, tempscrh - (GryMod.EyeFinityScrW() / 8.4), Color(190, 195, 190, alpha_ch[2]), 1.2)
			else
				drawTextRotated(ammonum .. " | " .. extra .. "  ||  " .. grenum, "CrysisInfos", GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW() / 7.5) + GryModXDistance_int + GryModXDistance2_int, tempscrh - (GryMod.EyeFinityScrW() / 8.4), Color(190, 195, 190, alpha_ch[2]), 1.2)
			end
		end
	end

	-- Lets get ammo MOTHERFUCKER
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	local compassmask = {
		{
			x = -1 * GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() * (072 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (215 / 1920)
		},
		{
			x = -1 * GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() * (273 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (227 / 1920)
		},
		{
			x = -1 * GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() * (294 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (207 / 1920)
		},
		{
			x = -1 * GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() * (061 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (194 / 1920)
		},
		{
			x = -1 * GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() * (060 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (204 / 1920)
		}
	}

	-- if we want to support eyefinity, we have to update the table each frames
	local nbener = LocalPlayer():GetNWFloat("GryEnergy")
	local nbhlt = LocalPlayer():Health()
	local healthoffset = math.Remap(nbhlt, 0, 100, 0, GryMod.EyeFinityScrW() * (219 / 1920))
	local energyoffset = math.Remap(nbener, 0, 100, 0, GryMod.EyeFinityScrW() * (219 / 1920))
	render.ClearStencil()
	render.SetStencilEnable(true)
	render.SetStencilWriteMask(15)
	render.SetStencilTestMask(15)
	render.SetStencilReferenceValue(15)
	render.SetStencilFailOperation(STENCILOPERATION_ZERO)
	render.SetStencilPassOperation(STENCILOPERATION_REPLACE)
	render.SetStencilZFailOperation(STENCILOPERATION_KEEP)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
	surface.SetDrawColor(color_white)
	render.SetBlend(0)
	surface.DrawPoly(compassmask)
	render.SetBlend(1)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)
	LocalPlayer_y = LocalPlayer():EyeAngles().y + 6.256798
	draw.SimpleText("N", "ScoreboardText", GryMod.EyeFinityScrW() * (20 / 1920) - GryModXDistance_int + GryModXDistance2_int + (LocalPlayer_y * 3.32) + GryMod.EyeFinityScrW() * (134 / 1920), tempscrh - GryMod.EyeFinityScrW() * (218 / 1920) - ((LocalPlayer_y * 3.32) / 15) + GryMod.EyeFinityScrW() * (-5 / 1920), color_white)
	draw.SimpleText("NE", "ScoreboardText", GryMod.EyeFinityScrW() * (20 / 1920) - GryModXDistance_int + GryModXDistance2_int + ((LocalPlayer_y + 45) * 3.32) + GryMod.EyeFinityScrW() * (134 / 1920), ((tempscrh - GryMod.EyeFinityScrW() * (218 / 1920) - (((LocalPlayer_y + 45) * 3.32) / 15) + GryMod.EyeFinityScrW() * (-5 / 1920))), color_white)
	draw.SimpleText("E", "ScoreboardText", GryMod.EyeFinityScrW() * (20 / 1920) - GryModXDistance_int + GryModXDistance2_int + ((LocalPlayer_y + 90) * 3.32) + GryMod.EyeFinityScrW() * (134 / 1920), ((tempscrh - GryMod.EyeFinityScrW() * (218 / 1920) - ((LocalPlayer_y + 90) * 3.32) / 15) + GryMod.EyeFinityScrW() * (-5 / 1920)), color_white)
	draw.SimpleText("SE", "ScoreboardText", GryMod.EyeFinityScrW() * (20 / 1920) - GryModXDistance_int + GryModXDistance2_int + ((LocalPlayer_y + 135) * 3.32) + GryMod.EyeFinityScrW() * (134 / 1920), ((tempscrh - GryMod.EyeFinityScrW() * (218 / 1920) - (((LocalPlayer_y + 135) * 3.32) / 15) + GryMod.EyeFinityScrW() * (-5 / 1920))), color_white)
	draw.SimpleText("S", "ScoreboardText", GryMod.EyeFinityScrW() * (20 / 1920) - GryModXDistance_int + GryModXDistance2_int + math.max(math.NormalizeAngle(LocalPlayer_y + 180), math.NormalizeAngle(LocalPlayer_y - 180)) * 5 + GryMod.EyeFinityScrW() * (134 / 1920), ((tempscrh - GryMod.EyeFinityScrW() * (218 / 1920) - ((math.max(math.NormalizeAngle(LocalPlayer_y + 180), math.NormalizeAngle(LocalPlayer_y - 180)) * 3.32) / 15) + GryMod.EyeFinityScrW() * (-5 / 1920))), color_white)
	draw.SimpleText("SW", "ScoreboardText", GryMod.EyeFinityScrW() * (20 / 1920) - GryModXDistance_int + GryModXDistance2_int + ((LocalPlayer_y - 135) * 3.32) + GryMod.EyeFinityScrW() * (134 / 1920), ((tempscrh - GryMod.EyeFinityScrW() * (218 / 1920) - (((LocalPlayer_y - 135) * 3.32) / 15) + GryMod.EyeFinityScrW() * (-5 / 1920))), color_white)
	draw.SimpleText("W", "ScoreboardText", GryMod.EyeFinityScrW() * (20 / 1920) - GryModXDistance_int + GryModXDistance2_int + ((LocalPlayer_y - 90) * 3.32) + GryMod.EyeFinityScrW() * (134 / 1920), ((tempscrh - GryMod.EyeFinityScrW() * (218 / 1920) - (((LocalPlayer_y - 90) * 3.32) / 15) + GryMod.EyeFinityScrW() * (-5 / 1920))), color_white)
	draw.SimpleText("NW", "ScoreboardText", GryMod.EyeFinityScrW() * (20 / 1920) - GryModXDistance_int + GryModXDistance2_int + ((LocalPlayer_y - 45) * 3.32) + GryMod.EyeFinityScrW() * (134 / 1920), ((tempscrh - GryMod.EyeFinityScrW() * (218 / 1920) - (((LocalPlayer_y - 45) * 3.32) / 15) + GryMod.EyeFinityScrW() * (-5 / 1920))), color_white)
	render.SetStencilEnable(false)

	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	local energybarpoly1 = {
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (446 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (136 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (436 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (144 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (277 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (136 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (277 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (113.5 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (446 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (122 / 1920)
		}
	} -- energy left

	local energybarpoly2 = {
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (270 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (135.5 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (228 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (133 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (228 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (111 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (270 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (113.5 / 1920)
		}
	} -- energy right

	local healthbarpoly1 = {
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (446 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (112 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (277 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (102.5 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (277 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (81.5 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (436 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (91 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (446 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (97 / 1920)
		}
	} -- health left

	local healthbarpoly2 = {
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (270 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (102 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (228 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (99.5 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (228 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (78.5 / 1920)
		},
		{
			x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (270 / 1920),
			y = ScrH() - GryMod.EyeFinityScrW() * (81 / 1920)
		}
	} -- health right

	render.ClearStencil()
	render.SetStencilEnable(true)
	render.SetStencilWriteMask(246)
	render.SetStencilTestMask(246)
	render.SetStencilReferenceValue(16)
	render.SetStencilFailOperation(STENCILOPERATION_ZERO)
	render.SetStencilPassOperation(STENCILOPERATION_REPLACE)
	render.SetStencilZFailOperation(STENCILOPERATION_KEEP)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
	surface.SetDrawColor(color_white)
	--render.SetBlend(0)
	surface.DrawPoly(energybarpoly1)
	--render.SetBlend(1)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)
	surface.SetDrawColor(Color(20, 150, 230, alpha_ch[1]))
	surface.DrawRect(GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (446 / 1920) + (GryMod.EyeFinityScrW() * (219 / 1920) - energyoffset), ScrH() - GryMod.EyeFinityScrW() * (144 / 1920), GryMod.EyeFinityScrW() * (219 / 1920) - (GryMod.EyeFinityScrW() * (219 / 1920) - energyoffset), GryMod.EyeFinityScrW() * (37 / 1920))
	render.SetStencilEnable(false)
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	render.ClearStencil()
	render.SetStencilEnable(true)
	render.SetStencilWriteMask(247)
	render.SetStencilTestMask(247)
	render.SetStencilReferenceValue(17)
	render.SetStencilFailOperation(STENCILOPERATION_ZERO)
	render.SetStencilPassOperation(STENCILOPERATION_REPLACE)
	render.SetStencilZFailOperation(STENCILOPERATION_KEEP)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
	surface.SetDrawColor(color_white)
	--render.SetBlend(0)
	surface.DrawPoly(healthbarpoly1)
	--render.SetBlend(1)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)
	surface.SetDrawColor(Color(116, 194, 27, alpha_ch[1]))
	surface.DrawRect(GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (446 / 1920) + (GryMod.EyeFinityScrW() * (219 / 1920) - healthoffset), ScrH() - GryMod.EyeFinityScrW() * (113 / 1920), GryMod.EyeFinityScrW() * (219 / 1920) - (GryMod.EyeFinityScrW() * (219 / 1920) - healthoffset), GryMod.EyeFinityScrW() * (37 / 1920))
	render.SetStencilEnable(false)
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	render.ClearStencil()
	render.SetStencilEnable(true)
	render.SetStencilWriteMask(248)
	render.SetStencilTestMask(248)
	render.SetStencilReferenceValue(18)
	render.SetStencilFailOperation(STENCILOPERATION_ZERO)
	render.SetStencilPassOperation(STENCILOPERATION_REPLACE)
	render.SetStencilZFailOperation(STENCILOPERATION_KEEP)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
	surface.SetDrawColor(color_white)
	render.SetBlend(0)
	surface.DrawPoly(healthbarpoly2)
	render.SetBlend(1)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)

	if nbhlt > 20 then
		surface.SetDrawColor(Color(116, 194, 27, alpha_ch[1]))
	else
		surface.SetDrawColor(Color(240, 23, 27, alpha_ch[1]))
	end

	surface.DrawRect(GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (446 / 1920) + (GryMod.EyeFinityScrW() * (219 / 1920) - healthoffset), ScrH() - GryMod.EyeFinityScrW() * (113 / 1920), GryMod.EyeFinityScrW() * (219 / 1920) - (GryMod.EyeFinityScrW() * (219 / 1920) - healthoffset), GryMod.EyeFinityScrW() * (37 / 1920))
	render.SetStencilEnable(false)
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	render.ClearStencil()
	render.SetStencilEnable(true)
	render.SetStencilWriteMask(249)
	render.SetStencilTestMask(249)
	render.SetStencilReferenceValue(19)
	render.SetStencilFailOperation(STENCILOPERATION_ZERO)
	render.SetStencilPassOperation(STENCILOPERATION_REPLACE)
	render.SetStencilZFailOperation(STENCILOPERATION_KEEP)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
	surface.SetDrawColor(color_white)
	render.SetBlend(0)
	surface.DrawPoly(energybarpoly2)
	render.SetBlend(1)
	render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)

	if nbener > 20 then
		surface.SetDrawColor(Color(20, 150, 230, alpha_ch[1]))
	else
		surface.SetDrawColor(Color(240, 23, 27, alpha_ch[1]))
	end

	surface.DrawRect(GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW() - GryMod.EyeFinityScrW() * (446 / 1920) + (GryMod.EyeFinityScrW() * (219 / 1920) - energyoffset), ScrH() - GryMod.EyeFinityScrW() * (144 / 1920), GryMod.EyeFinityScrW() * (219 / 1920) - (GryMod.EyeFinityScrW() * (219 / 1920) - energyoffset), GryMod.EyeFinityScrW() * (37 / 1920))
	render.SetStencilEnable(false)
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	--//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
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
local MOUSE_CHECK_DIST = 160

function GryMod.RadialThink()
	if not GRYOPEN then
		return
	end

	local hypotenus = math.Distance(gui.MouseX(), gui.MouseY(), ScrW() / 2, ScrH() / 2)

	if (hypotenus > MOUSE_CHECK_DIST) then
		local distx = math.abs(ScrW() / 2 - gui.MouseX())
		local angle = math.abs(math.acos(distx / hypotenus) * 180 / math.pi)

		if (tostring(angle) == "nan") then
			return
		end

		local newtriangle_hypotenus = MOUSE_CHECK_DIST
		local multx = 1 -- change direction of x and y because we're not just working with a triangle now, you need to define the "orientation of the triangle"
		local multy = 1

		if (gui.MouseX() < ScrW() / 2) then
			multx = -1
		end

		if (gui.MouseY() < ScrH() / 2) then
			multy = -1
		end

		local newx = (math.cos(angle / (180 / math.pi)) * newtriangle_hypotenus) * multx
		local newy = (math.sin(angle / (180 / math.pi)) * newtriangle_hypotenus) * multy
		gui.SetMousePos(ScrW() / 2 + newx, ScrH() / 2 + newy)
	end
end







local hidethings = {
	["CHudHealth"] = true,
	["CHudBattery"] = true,
	["CHudAmmo"] = true,
	["CHudSecondaryAmmo"] = true
}

function HUDShouldDraw(name)
	if (hidethings[name]) then
		return false
	end
end

hook.Add("HUDShouldDraw", "How to: HUD Example HUD hider", HUDShouldDraw)
hook.Add("HUDPaint", "GRYHUD", GryMod.CRYHUD)
hook.Add("KeyPress", "AttackDetection", GryMod.CloackAttack)
hook.Add("Think", "SuitBreathUnderwater", GryMod.SuitBreathUnderwater)
hook.Add("HUDPaint", "HUDBASECRY", GryMod.hudbase)
hook.Add("Think", "HueHue fix normal shit", GryMod.RadialThink)