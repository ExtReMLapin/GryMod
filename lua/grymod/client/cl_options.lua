
function GryMod.GryOptionschute(Panel)
	Panel:AddControl("Label", {
		Text = "GryMod Config"
	})

	enabled1 = vgui.Create("DButton", Panel)
	enabled1:SetSize(250, 25)
	enabled1:SetText("Enable Base HUD")

	enabled1.DoClick = function()
		hook.Add("HUDPaint", "HUDBASECRY", GryMod.hudbase)
		hook.Add("HUDShouldDraw", "How to: HUD Example HUD hider", HUDShouldDraw)
		hook.Add("HUDPaint", "Nade detection", GryMod.grenadetetect)
		hook.Add("HUDPaint", "GryCross", GryMod.cross)
	end

	disabled1 = vgui.Create("DButton", Panel)
	disabled1:SetSize(250, 25)
	disabled1:SetText("Disable Base HUD")

	disabled1.DoClick = function()
		hook.Remove("HUDPaint", "HUDBASECRY")
		hook.Remove("HUDShouldDraw", "How to: HUD Example HUD hider")
		hook.Remove("HUDPaint", "Nade detection")
		hook.Remove("HUDPaint", "GryCross")
	end

	togglehealth = vgui.Create("DButton", Panel)
	togglehealth:SetSize(250, 20)
	togglehealth:SetText("[ADMIN] Toggle Health Regen")

	togglehealth.DoClick = function()
		RunConsoleCommand("gry_Health")
	end

	togglearmor = vgui.Create("DButton", Panel)
	togglearmor:SetSize(250, 20)
	togglearmor:SetText("[ADMIN] Toggle Infinite Armor")

	togglearmor.DoClick = function()
		RunConsoleCommand("gry_Armor")
	end

	local NumSliderThingy = vgui.Create("DNumSlider", Panel)
	NumSliderThingy:SetPos(25, 150)
	NumSliderThingy:SetSize(250, 10)
	NumSliderThingy:SetText("Mirror Distance")
	NumSliderThingy:SetMin(-5000)
	NumSliderThingy:SetMax(5000)
	NumSliderThingy:SetDecimals(0)
	NumSliderThingy:SetConVar("gry_xadd")
	local NumSliderThingy1 = vgui.Create("DNumSlider", Panel)
	NumSliderThingy1:SetPos(25, 180)
	NumSliderThingy1:SetSize(250, 10)
	NumSliderThingy1:SetText("X Posision")
	NumSliderThingy1:SetMin(-5000)
	NumSliderThingy1:SetMax(5000)
	NumSliderThingy1:SetDecimals(0)
	NumSliderThingy1:SetConVar("gry_xdist")
	local CheckBoxThing = vgui.Create("DCheckBoxLabel", Panel)
	CheckBoxThing:SetPos(25, 195)
	CheckBoxThing:SetText("Eyefinity")
	CheckBoxThing:SetConVar("cl_Eyefinity")
	CheckBoxThing:SetValue(0)
	CheckBoxThing:SizeToContents()


	Panel:AddItem(disabled1)
	Panel:AddItem(enabled1)
	Panel:AddItem(togglehealth)
	Panel:AddItem(togglearmor)
	Panel:AddItem(NumSliderThingy)
	Panel:AddItem(NumSliderThingy1)
	Panel:AddItem(CheckBoxThing)

end

function GryMod.GryOptionschuteOptionmenu()
	spawnmenu.AddToolMenuOption("Options", "GryMod", "Config", "Config it !", "test1", "test23", GryMod.GryOptionschute)
end

hook.Add("PopulateToolMenu", "PopulateToolMenu", GryMod.GryOptionschuteOptionmenu)