-- Server side of tests/admin_options_job.lua (lua_exec, realm server): `return GryMod.AdminOptionsCount(true)` installs a counter on the
-- receiver of gry_set_server_option and `return GryMod.AdminOptionsCount(false)` reads it and puts the real receiver back.
GryMod.AdminOptionsCount = function(start)
	if start then
		GryMod.__optionsReceiver = GryMod.__optionsReceiver or net.Receivers["gry_set_server_option"]
		GryMod.__optionsCount = 0
		local real = GryMod.__optionsReceiver
		net.Receivers["gry_set_server_option"] = function(len, ply)
			GryMod.__optionsCount = GryMod.__optionsCount + 1
			return real(len, ply)
		end

		return "counting"
	end

	net.Receivers["gry_set_server_option"] = GryMod.__optionsReceiver
	GryMod.__optionsReceiver = nil

	return GryMod.__optionsCount
end
