-- Tests of the attacks that are not bullets and end the camouflage: GryMod.API.ReportAttack (lua/grymod/server/sv_api.lua) and the TFA patch that uses it
-- (lua/grymod/compat/weapons/sv_tfa.lua), GLuaTest format, server realm. The server sees every BULLET of the player (EntityFireBullets, sv_system.lua), but not a swing of a
-- knife, a thrown grenade or a launched one: a weapon, or a patch for a weapon base, tells it here. The client of the player ends the camouflage (unless the attack was a right
-- click and he turned that rule off). TFA calls its hook TFA_PostSecondaryAttack for a gun's right click even when it is only the sights, so the patch has to say which right
-- clicks are attacks, as TFA's own SecondaryAttack does. A real weapon entity is given to the player (a stock pistol that the cases dress as a TFA weapon: the fields the patch
-- reads), the network is recorded, and everything is put back in afterEach inside a pcall. Each case names the production change whose absence makes it fail.

local function ply()
	return player.GetAll()[1]
end

-- Runs fn with the network recorded. Returns what fn returned, and the list of messages {name, bool}.
local function recorded(fn)
	local sent = {}
	local realStart, realSend, realWriteBool = net.Start, net.Send, net.WriteBool

	net.Start = function(name)
		sent[#sent + 1] = {name = name}

		return true
	end
	net.WriteBool = function(value)
		sent[#sent].bool = value
	end
	net.Send = function(to)
		sent[#sent].to = to
	end

	local ok, a = pcall(fn)

	net.Start, net.Send, net.WriteBool = realStart, realSend, realWriteBool
	assert(ok, a)

	return a, sent
end

local function shots(sent)
	local list = {}

	for _, m in ipairs(sent) do
		if m.name == "gry_cloak_shot" then
			list[#list + 1] = m
		end
	end

	return list
end

local function patch(event)
	local hooks = hook.GetTable()[event]

	return hooks and hooks["GryMod compat tfa"]
end

-- a weapon in the player's hands, dressed as a TFA weapon of a kind: "knife" (IsMelee), "grenade" (IsGrenade), "gun" with or without an AltAttack and with its sights on or off
local function weapon(kind, altAttack, sights)
	local w = ply():Give("weapon_pistol")

	if kind == "knife" then
		w.IsMelee = true
	elseif kind == "grenade" then
		w.IsGrenade = true
	end

	if altAttack then
		w.AltAttack = function() end
	end

	w.GetStatL = function(_, stat, default)
		if stat == "Secondary.IronSightsEnabled" then
			return sights == true
		end

		return default
	end

	return w
end

local function cloak(on)
	local p = ply()

	p:SetNanosuitMode(on and GryMod.Modes.CLOAK or GryMod.Modes.ARMOR, false)
end

return {
	groupName = "GryMod attacks that are not bullets end the camouflage (server)",
	beforeEach = function()
		local p = ply()

		if not p:Alive() then
			p:Spawn()
		end

		p:StripWeapons()
		p:SetNW2Float("GryEnergy", 100)
		cloak(true)
	end,
	afterEach = function()
		pcall(function()
			local p = ply()

			if IsValid(p) then
				cloak(false)
				p:StripWeapons()
			end
		end)
	end,
	cases = {
		{
			-- fails without GryMod.API.ReportAttack, or when it does not tell the player's client (the camouflage ends there) with the right click flag it was given
			name = "ReportAttack: a camouflaged player is told (the message of a shot), with the right click flag as given, and the answer is true",
			func = function()
				local p = ply()

				expect(isfunction(GryMod.API.ReportAttack)).to.beTrue()

				local result, sent = recorded(function()
					return GryMod.API.ReportAttack(p, true)
				end)

				expect(result).to.beTrue()
				expect(#shots(sent)).to.equal(1)
				expect(shots(sent)[1].bool).to.beTrue()
				expect(shots(sent)[1].to).to.equal(p)

				_, sent = recorded(function()
					return GryMod.API.ReportAttack(p, false)
				end)
				expect(shots(sent)[1].bool).to.beFalse()

				_, sent = recorded(function()
					return GryMod.API.ReportAttack(p)
				end)
				expect(shots(sent)[1].bool).to.beFalse() -- no flag: not a right click
			end
		},
		{
			-- fails when a player that is not camouflaged is told (the message would reach a client that has nothing to end), or a value that is no player raises an error
			name = "ReportAttack: nothing is sent for a player who is not camouflaged (false and why), and a value that is no player gives false without an error",
			func = function()
				local p = ply()

				cloak(false)

				local result, sent = recorded(function()
					return GryMod.API.ReportAttack(p, true)
				end)

				expect(result).to.beFalse()
				expect(#shots(sent)).to.equal(0)
				expect((select(2, GryMod.API.ReportAttack(p, true)))).to.equal("not camouflaged")

				for _, value in ipairs({false, 5, "a player", {}}) do
					local r, s = recorded(function()
						return GryMod.API.ReportAttack(value, true)
					end)

					expect(r).to.beFalse()
					expect(#shots(s)).to.equal(0)
				end

				local r = recorded(function() return GryMod.API.ReportAttack(nil, true) end)

				expect(r).to.beFalse()
				expect((select(2, GryMod.API.ReportAttack(NULL, true)))).to.equal("invalid player")
			end
		},
		{
			-- fails when the patch is not registered on TFA's hooks (a knife's stab, a bash), or a knife's right click does not end the camouflage as a right click
			name = "TFA patch: a knife's right click (TFA_PostSecondaryAttack on a melee weapon) and a bash (TFA_PostBash) are attacks: the first one is told as a right click, the second one is not",
			func = function()
				local w = weapon("knife")

				expect(isfunction(patch("TFA_PostSecondaryAttack"))).to.beTrue()
				expect(isfunction(patch("TFA_PostBash"))).to.beTrue()

				local _, sent = recorded(function()
					patch("TFA_PostSecondaryAttack")(w)
				end)

				expect(#shots(sent)).to.equal(1)
				expect(shots(sent)[1].bool).to.beTrue()

				_, sent = recorded(function()
					patch("TFA_PostBash")(w)
				end)
				expect(#shots(sent)).to.equal(1)
				expect(shots(sent)[1].bool).to.beFalse()
			end
		},
		{
			-- fails when aiming down the sights of a TFA gun ends the camouflage: TFA runs TFA_PostSecondaryAttack for it too
			name = "TFA patch: a gun's right click is only the sights unless the gun has an alt attack and its sights are off: aiming does not end the camouflage, the alt attack does, a grenade's right click does",
			func = function()
				-- no alt attack: the sights
				local _, sent = recorded(function()
					patch("TFA_PostSecondaryAttack")(weapon("gun", false, false))
				end)
				expect(#shots(sent)).to.equal(0)

				-- an alt attack but the sights are enabled for the right click: TFA's own SecondaryAttack does not run the alt attack either
				ply():StripWeapons()
				_, sent = recorded(function()
					patch("TFA_PostSecondaryAttack")(weapon("gun", true, true))
				end)
				expect(#shots(sent)).to.equal(0)

				-- an alt attack and no sights on the right click: an underbarrel launcher, a bayonet
				ply():StripWeapons()
				_, sent = recorded(function()
					patch("TFA_PostSecondaryAttack")(weapon("gun", true, false))
				end)
				expect(#shots(sent)).to.equal(1)

				-- a grenade: the right click is the low throw
				ply():StripWeapons()
				_, sent = recorded(function()
					patch("TFA_PostSecondaryAttack")(weapon("grenade"))
				end)
				expect(#shots(sent)).to.equal(1)
			end
		},
		{
			-- fails when the patch raises an error into TFA's attack code (a weapon with no owner, an owner that is not a player, a value that is no weapon), or tells a player
			-- who is not camouflaged
			name = "TFA patch: never an error into TFA, and nothing for a weapon with no owner, an NPC owner, a player who is not camouflaged or something that is no weapon",
			func = function()
				local w = weapon("knife")

				-- not camouflaged
				cloak(false)

				local _, sent = recorded(function()
					patch("TFA_PostSecondaryAttack")(w)
					patch("TFA_PostBash")(w)
				end)
				expect(#shots(sent)).to.equal(0)

				cloak(true)

				-- no owner (the weapon on the floor)
				ply():DropWeapon(w)
				_, sent = recorded(function()
					patch("TFA_PostSecondaryAttack")(w)
					patch("TFA_PostBash")(w)
				end)
				expect(#shots(sent)).to.equal(0)

				if IsValid(w) then
					w:Remove()
				end

				-- junk
				for _, junk in ipairs({false, 5, "weapon", {}, NULL}) do
					_, sent = recorded(function()
						expect(pcall(patch("TFA_PostSecondaryAttack"), junk)).to.beTrue()
						expect(pcall(patch("TFA_PostBash"), junk)).to.beTrue()
					end)
					expect(#shots(sent)).to.equal(0)
				end
			end
		}
	}
}
