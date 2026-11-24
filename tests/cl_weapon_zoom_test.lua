-- Tests of the request to end a weapon's zoom when the binoculars open (GryMod.WeaponZoom, cl_weapon_zoom.lua), GLuaTest format, client
-- realm. The crossbow's right click zooms (the engine's field of view goes to 20 and the weapon owns that zoom); the binoculars (the own
-- zoom of the suit or the Half-Life 2 key) give a view of their own and, when they close, the engine's field of view is the crossbow's
-- again: a jump. The client asks the server to end the weapon's zoom at the moment the binoculars open, and only then, and only when a
-- zoom of a weapon on the list is really up (the field of view of the player is below the normal one). The decision is a pure function;
-- the step reads the world and feeds it. Nothing is sent to the server by these tests.

local OPTION = "gry_zoom_cancel_weapon"

local function setting(name)
	return GetConVar(name)
end

return {
	groupName = "GryMod weapon zoom cancel (client)",
	beforeEach = function(state)
		local W = GryMod.WeaponZoom
		local Bino = GryMod.FlashBinoculars
		state.saved = {
			option = setting(OPTION) and setting(OPTION):GetString(),
			send = W and W.Send,
			wanted = Bino and Bino.Wanted,
			enabled = Bino and Bino.Enabled,
			missing = Bino and Bino.IsMissing,
			fov = FindMetaTable("Player").GetFOV,
			info = FindMetaTable("Player").GetInfoNum,
			weapon = FindMetaTable("Player").GetActiveWeapon
		}
		state.sent = 0
		state.world = {wanted = false, enabled = true, missing = false, fov = 100, default = 100, class = "weapon_crossbow"}

		if W then
			W.Send = function() state.sent = state.sent + 1 end
		end

		if setting(OPTION) then
			setting(OPTION):SetString("1")
		end

		Bino.Wanted = function() return state.world.wanted end
		Bino.Enabled = function() return state.world.enabled end
		Bino.IsMissing = function() return state.world.missing end

		-- (what the step reads about the player)
		local meta = FindMetaTable("Player")
		meta.GetFOV = function() return state.world.fov end
		meta.GetInfoNum = function(_, name, default)
			if name == "fov_desired" then
				return state.world.default
			end

			return state.saved.info(LocalPlayer(), name, default)
		end
		meta.GetActiveWeapon = function()
			return {IsValid = function() return true end, GetClass = function() return state.world.class end}
		end
	end,
	afterEach = function(state)
		local W = GryMod.WeaponZoom
		local Bino = GryMod.FlashBinoculars
		local saved = state.saved
		local meta = FindMetaTable("Player")

		meta.GetFOV = saved.fov
		meta.GetInfoNum = saved.info
		meta.GetActiveWeapon = saved.weapon

		for _, class in ipairs({"doc_test_zoom_gun", "doc_test_grenade_gun"}) do
			GryMod.API.UnregisterWeapon(class)
		end

		Bino.Wanted = saved.wanted
		Bino.Enabled = saved.enabled
		Bino.IsMissing = saved.missing

		if W then
			W.Send = saved.send
		end

		if saved.option and setting(OPTION) then
			setting(OPTION):SetString(saved.option)
		end
	end,
	cases = {
		{
			name = "the option exists (saved, on by default) and has a check box in the options panel, and the weapon registry says that the crossbow's right click zooms (alt = zoom) and no other stock weapon's does",
			func = function()
				local W = GryMod.WeaponZoom
				expect(W ~= nil).to.beTrue()
				expect(setting(OPTION) ~= nil).to.beTrue()
				expect(setting(OPTION):GetDefault()).to.equal("1")
				expect(GryMod.API.WeaponValue("weapon_crossbow", "alt", true)).to.equal("zoom")

				-- (no private list of classes: the registry is the only source)
				expect(W.Weapons).to.beNil()

				for _, class in ipairs({"weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_frag", "weapon_pistol", "weapon_357", "weapon_rpg", "weapon_physcannon", "weapon_crowbar", "weapon_stunstick", "weapon_fists"}) do
					expect(GryMod.API.WeaponValue(class, "alt", true) == "zoom").to.beFalse()
				end

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = child:GetText()
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found[OPTION] ~= nil).to.beTrue()
			end
		},
		{
			name = "decision: the binoculars OPENING (down, then up) with the crossbow in hand and the field of view below the normal one asks; every other combination does not",
			func = function()
				local W = GryMod.WeaponZoom

				expect(W.Decide(true, false, true, "weapon_crossbow", 20, 100)).to.beTrue()
				-- already up the frame before: not an opening
				expect(W.Decide(true, true, true, "weapon_crossbow", 20, 100)).to.beFalse()
				-- still down, or closing
				expect(W.Decide(true, false, false, "weapon_crossbow", 20, 100)).to.beFalse()
				expect(W.Decide(true, true, false, "weapon_crossbow", 20, 100)).to.beFalse()
				-- the option off
				expect(W.Decide(false, false, true, "weapon_crossbow", 20, 100)).to.beFalse()
				-- another weapon, or none
				expect(W.Decide(true, false, true, "weapon_ar2", 20, 100)).to.beFalse()
				expect(W.Decide(true, false, true, nil, 20, 100)).to.beFalse()
				-- no zoom up: the field of view is the normal one (the Half-Life 2 zoom would only just be asked for: nothing to end)
				expect(W.Decide(true, false, true, "weapon_crossbow", 100, 100)).to.beFalse()
				expect(W.Decide(true, false, true, "weapon_crossbow", 99.8, 100)).to.beFalse()
				expect(W.Decide(true, false, true, "weapon_crossbow", 100.4, 100)).to.beFalse()
				-- a normal field of view that is not 100
				expect(W.Decide(true, false, true, "weapon_crossbow", 20, 75)).to.beTrue()
				expect(W.Decide(true, false, true, "weapon_crossbow", 75, 75)).to.beFalse()
				-- nonsense in
				expect(W.Decide(true, false, true, "weapon_crossbow", nil, 100)).to.beFalse()
				expect(W.Decide(true, false, true, "weapon_crossbow", 0 / 0, 100)).to.beFalse()
				expect(W.Decide(true, false, true, "weapon_crossbow", 20, nil)).to.beFalse()
			end
		},
		{
			name = "no permanent Think hook: at rest there is none, and the event of the binoculars going up or down has the hook; the file loaded again takes an older copy's Think hook off",
			func = function(state)
				expect(hook.GetTable().Think["GRYWEAPONZOOM"]).to.beNil()
				expect(isfunction(hook.GetTable()["GryMod_BinocularsToggled"]["GRYWEAPONZOOM"])).to.beTrue()

				local ok, err = pcall(function()
					hook.Add("Think", "GRYWEAPONZOOM", function() end)
					include("grymod/client/cl_weapon_zoom.lua")
					expect(hook.GetTable().Think["GRYWEAPONZOOM"]).to.beNil()
					expect(isfunction(hook.GetTable()["GryMod_BinocularsToggled"]["GRYWEAPONZOOM"])).to.beTrue()
				end)

				-- (the file's own Send is back after the load: stub it again before anything can ask)
				hook.Remove("Think", "GRYWEAPONZOOM")
				GryMod.WeaponZoom.Send = function() state.sent = state.sent + 1 end

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "a third-party weapon registered through the API with alt = zoom gets the crossbow's treatment (decision and opening); one registered with another alt, or not at all, does not",
			func = function(state)
				local W = GryMod.WeaponZoom
				local API = GryMod.API
				local ply = LocalPlayer()

				-- (rouge before the migration: the private list knew only the crossbow)
				expect(W.Decide(true, false, true, "doc_test_zoom_gun", 20, 100)).to.beFalse()

				expect((API.RegisterWeapon("doc_test_zoom_gun", {fire = "semi", alt = "zoom", altShoots = false}))).to.beTrue()
				expect((API.RegisterWeapon("doc_test_grenade_gun", {fire = "auto", alt = "grenade", altAmmo = "SMG1_Grenade"}))).to.beTrue()

				expect(W.Decide(true, false, true, "doc_test_zoom_gun", 20, 100)).to.beTrue()
				expect(W.Decide(true, false, true, "doc_test_zoom_gun", 100, 100)).to.beFalse()
				expect(W.Decide(true, true, true, "doc_test_zoom_gun", 20, 100)).to.beFalse()
				expect(W.Decide(true, false, true, "doc_test_grenade_gun", 20, 100)).to.beFalse()
				expect(W.Decide(true, false, true, "doc_test_unregistered_gun", 20, 100)).to.beFalse()

				-- (the weapon entity is accepted too: that is what the opening gives)
				expect(W.Decide(true, false, true, {GetClass = function() return "doc_test_zoom_gun" end, IsValid = function() return true end}, 20, 100)).to.beTrue()

				state.world.class = "doc_test_zoom_gun"
				state.world.fov = 20
				W.Opened(ply)
				expect(state.sent).to.equal(1)

				-- unregistered: back to nothing
				API.UnregisterWeapon("doc_test_zoom_gun")
				expect(W.Decide(true, false, true, "doc_test_zoom_gun", 20, 100)).to.beFalse()
			end
		},
		{
			name = "opening: the crossbow zoomed, the binoculars go up (the event): one request, at the going up only (not when they go down)",
			func = function(state)
				local event = hook.GetTable()["GryMod_BinocularsToggled"]["GRYWEAPONZOOM"]

				state.world.fov = 20
				event(true)
				expect(state.sent).to.equal(1)

				-- closing: nothing
				event(false)
				expect(state.sent).to.equal(1)

				-- open again with the zoom up again: a second request
				event(true)
				expect(state.sent).to.equal(2)
			end
		},
		{
			name = "end to end: the binoculars' own check (Bino.CheckToggled, woken by the own zoom's or the game key's event) runs the event and the request goes out once, at the opening",
			func = function(state)
				local Bino = GryMod.FlashBinoculars

				state.world.fov = 20
				state.world.wanted = false
				Bino.CheckToggled()
				expect(state.sent).to.equal(0)

				state.world.wanted = true
				Bino.CheckToggled()
				Bino.CheckToggled()
				expect(state.sent).to.equal(1)

				-- (leaves the binoculars' memory as the world is: down)
				state.world.wanted = false
				Bino.CheckToggled()
				expect(state.sent).to.equal(1)
			end
		},
		{
			name = "opening: the binoculars alone (the field of view is the normal one when they go up) asks nothing",
			func = function(state)
				local event = hook.GetTable()["GryMod_BinocularsToggled"]["GRYWEAPONZOOM"]

				-- (the Half-Life 2 zoom reaches 25 degrees after the opening: the opening was the moment to look)
				event(true)
				expect(state.sent).to.equal(0)
				event(false)
				expect(state.sent).to.equal(0)
			end
		},
		{
			name = "opening: another weapon in hand with a zoom (a field of view below the normal one) sends nothing",
			func = function(state)
				local event = hook.GetTable()["GryMod_BinocularsToggled"]["GRYWEAPONZOOM"]

				state.world.class = "weapon_ar2"
				state.world.fov = 20
				event(true)
				expect(state.sent).to.equal(0)
			end
		},
		{
			name = "opening: the option off, the binoculars element off, or the movie missing: nothing is asked",
			func = function(state)
				local event = hook.GetTable()["GryMod_BinocularsToggled"]["GRYWEAPONZOOM"]

				state.world.fov = 20

				setting(OPTION):SetString("0")
				event(true)
				expect(state.sent).to.equal(0)

				setting(OPTION):SetString("1")
				state.world.enabled = false
				event(true)
				expect(state.sent).to.equal(0)

				state.world.enabled = true
				state.world.missing = true
				event(true)
				expect(state.sent).to.equal(0)

				-- (and with everything on, the same call asks: the three checks above were the reason)
				state.world.missing = false
				event(true)
				expect(state.sent).to.equal(1)
			end
		},
		{
			name = "the real Send writes the message with no payload to the server (the net functions are called, nothing else)",
			func = function(state)
				local W = GryMod.WeaponZoom
				local sendReal = state.saved.send
				local calls = {}
				local start, send = net.Start, net.SendToServer
				net.Start = function(name) calls[#calls + 1] = "start:" .. tostring(name) end
				net.SendToServer = function() calls[#calls + 1] = "send" end

				local ok, err = pcall(sendReal)
				net.Start, net.SendToServer = start, send

				if not ok then
					error(err, 0)
				end

				expect(#calls).to.equal(2)
				expect(calls[1]).to.equal("start:gry_cancel_weapon_zoom")
				expect(calls[2]).to.equal("send")
			end
		},
		{
			-- fails without WeaponZoom.IsZoomed
			name = "IsZoomed: true for a weapon whose right click zooms (alt = zoom) while the field of view is under the normal one; false for the same weapon at rest, another weapon, no weapon, the option off, or no player",
			func = function()
				local W = GryMod.WeaponZoom

				local function fake(class, fov, default)
					return {
						IsValid = function() return true end,
						GetActiveWeapon = function()
							return class and {IsValid = function() return true end, GetClass = function() return class end} or NULL
						end,
						GetFOV = function() return fov end,
						GetInfoNum = function(_, name, fallback) return name == "fov_desired" and default or fallback end
					}
				end

				-- a weapon of an addon whose zoom is a scope with its own aim (alt = zoom, nothing more said)
				GryMod.API.RegisterWeapon("test_scope_rifle", {fire = "semi", alt = "zoom", altShoots = false})

				local ok, err = pcall(function()
					expect(W.IsZoomed(fake("test_scope_rifle", 20, 75))).to.beTrue()
					expect(W.IsZoomed(fake("test_scope_rifle", 75, 75))).to.beFalse()
					expect(W.IsZoomed(fake("test_scope_rifle", 74.8, 75))).to.beFalse() -- within the tolerance
					expect(W.IsZoomed(fake("weapon_smg1", 20, 75))).to.beFalse()
					expect(W.IsZoomed(fake(nil, 20, 75))).to.beFalse()
					expect(W.IsZoomed(NULL)).to.beFalse()

					local convar = setting("gry_zoom_hide_crosshair")
					expect(convar ~= nil).to.beTrue()
					local saved = convar:GetString()
					convar:SetString("0")
					local off = W.IsZoomed(fake("test_scope_rifle", 20, 75))
					convar:SetString(saved)
					expect(off).to.beFalse()
				end)

				GryMod.API.UnregisterWeapon("test_scope_rifle")

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails if the crossbow's zoom hides the crosshair: the Half-Life 2 crossbow has no scope picture of its own in Garry's Mod, so the zoomed crossbow had NO
			-- crosshair at all (reported 2026-11-24); it says so in the registry (zoomCrosshair)
			name = "the zoomed crossbow keeps the crosshair (its registry entry says zoomCrosshair); a weapon with its own scope does not, and the field only takes true or false",
			func = function()
				local W = GryMod.WeaponZoom
				local zoomed = {
					IsValid = function() return true end,
					GetActiveWeapon = function() return {IsValid = function() return true end, GetClass = function() return "weapon_crossbow" end} end,
					GetFOV = function() return 20 end,
					GetInfoNum = function(_, name, fallback) return name == "fov_desired" and 75 or fallback end
				}

				expect(GryMod.API.WeaponValue("weapon_crossbow", "zoomCrosshair", true)).to.equal(7) -- the thin cross: a precision weapon wants a precise aim
				expect(W.IsZoomed(zoomed)).to.beFalse()

				local okBad = GryMod.API.RegisterWeapon("test_bad_zoom_crosshair", {alt = "zoom", zoomCrosshair = "yes"})
				GryMod.API.UnregisterWeapon("test_bad_zoom_crosshair")
				expect(okBad).to.beFalse()
				local okRange = GryMod.API.RegisterWeapon("test_bad_zoom_crosshair", {alt = "zoom", zoomCrosshair = 14})
				GryMod.API.UnregisterWeapon("test_bad_zoom_crosshair")
				expect(okRange).to.beFalse()
			end
		},
		{
			-- fails without WeaponZoom.CrosshairFor / Cross.ZoomOverride: the zoomed crossbow showed the player's style (the 6: a wide circle with corners, reported
			-- 2026-11-24 as not precise for a precision weapon)
			name = "a zoomed weapon whose zoomCrosshair is a number shows that crosshair of the movie in its zoom (the crossbow: the thin cross), only if the player lets weapons choose",
			func = function()
				local W = GryMod.WeaponZoom
				local Cross = GryMod.FlashCrosshair

				local function fake(class, fov)
					return {
						IsValid = function() return true end,
						GetActiveWeapon = function() return {IsValid = function() return true end, GetClass = function() return class end} end,
						GetFOV = function() return fov end,
						GetInfoNum = function(_, name, fallback) return name == "fov_desired" and 75 or fallback end
					}
				end

				expect(W.CrosshairFor(fake("weapon_crossbow", 20))).to.equal(7)
				expect(W.CrosshairFor(fake("weapon_crossbow", 75))).to.beNil() -- at rest: the player's style
				expect(W.CrosshairFor(fake("weapon_smg1", 20))).to.beNil()
				expect(W.CrosshairFor(NULL)).to.beNil()

				GryMod.API.RegisterWeapon("test_keep_rifle", {alt = "zoom", altShoots = false, zoomCrosshair = true})
				GryMod.API.RegisterWeapon("test_scope_rifle", {alt = "zoom", altShoots = false})

				local ok, err = pcall(function()
					expect(W.CrosshairFor(fake("test_keep_rifle", 20))).to.beNil() -- true: the player's style stays
					expect(W.IsZoomed(fake("test_keep_rifle", 20))).to.beFalse()
					expect(W.CrosshairFor(fake("test_scope_rifle", 20))).to.beNil() -- no field: the weapon's own scope, the crosshair goes
				end)

				GryMod.API.UnregisterWeapon("test_keep_rifle")
				GryMod.API.UnregisterWeapon("test_scope_rifle")

				if not ok then
					error(err, 0)
				end

				-- the override: only over a crosshair that is shown (0 stays 0: the binoculars, a weapon without one), and not when the player wants his own style everywhere
				expect(Cross.ZoomOverride(6, 7, true)).to.equal(7)
				expect(Cross.ZoomOverride(6, nil, true)).to.equal(6)
				expect(Cross.ZoomOverride(0, 7, true)).to.equal(0)
				expect(Cross.ZoomOverride(6, 7, false)).to.equal(6)
			end
		},
		{
			-- fails without the wrapper of Cross.Zooming (the crosshair would stay over the crossbow's zoom), or if it hides the base answer
			name = "the crosshair's Zooming says yes for a zoomed weapon as well, keeps its own answer for the binoculars, and is wrapped only once",
			func = function(state)
				local W = GryMod.WeaponZoom
				local Cross = GryMod.FlashCrosshair
				expect(Cross.Zooming).to.equal(W.CrossWrapper)

				-- (a weapon with a scope of its own: the crossbow keeps the crosshair, see the test above)
				local function fake(fov)
					return {
						IsValid = function() return true end,
						GetActiveWeapon = function()
							return {IsValid = function() return true end, GetClass = function() return "test_scope_rifle" end}
						end,
						GetFOV = function() return fov end,
						GetInfoNum = function(_, name, fallback) return name == "fov_desired" and 75 or fallback end
					}
				end

				GryMod.API.RegisterWeapon("test_scope_rifle", {fire = "semi", alt = "zoom", altShoots = false})

				local ok, err = pcall(function()
					state.world.wanted = false
					expect(Cross.Zooming(fake(20))).to.beTrue()
					expect(Cross.Zooming(fake(75))).to.beFalse()

					-- the binoculars up: the base rule answers yes whatever the weapon does
					state.world.wanted = true
					expect(Cross.Zooming(fake(75))).to.beTrue()
				end)

				GryMod.API.UnregisterWeapon("test_scope_rifle")

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "gry_zoom_hide_crosshair is saved, on by default, with a check box in the Binoculars options",
			func = function()
				local convar = setting("gry_zoom_hide_crosshair")
				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("1")
				expect(convar:GetFlags()).to.equal(setting(OPTION):GetFlags())

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.BinocularsOptions(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found["gry_zoom_hide_crosshair"]).to.beTrue()
			end
		}
	}
}
