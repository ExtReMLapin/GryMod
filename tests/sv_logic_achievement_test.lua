-- Test of the stand-in entity logic_achievement (lua/entities/logic_achievement.lua), GLuaTest format, server realm. Garry's Mod does not make Half-Life 2's achievement relay,
-- so the inputs a map sends to it were lost and the campaign steps that end on it (the can in the bin...) could never finish. The stand-in only has to exist on the map.

return {
	groupName = "logic_achievement stand-in",
	cases = {
		{
			-- fails without lua/entities/logic_achievement.lua: the class is not made, a map's logic_achievement is dropped and its inputs go nowhere
			name = "the class can be made, keeps its name, and takes the input FireEvent without an error",
			func = function()
				local e = ents.Create("logic_achievement")

				expect(IsValid(e)).to.beTrue()

				local ok, err = pcall(function()
					e:SetName("gry_test_achievement")
					e:SetKeyValue("AchievementEvent", "ACHIEVEMENT_EVENT_TEST")
					e:Spawn()
					expect(e:GetName()).to.equal("gry_test_achievement")
					e:Input("FireEvent")
				end)

				if IsValid(e) then
					e:Remove()
				end

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails if the stand-in swallows the input: GM:AcceptInput is how the campaign module hears the step
			name = "the input reaches GM:AcceptInput, where the campaign module listens",
			func = function()
				local seen
				local e = ents.Create("logic_achievement")

				e:SetName("gry_test_achievement2")
				e:Spawn()

				hook.Add("AcceptInput", "GryTestAchievementSeen", function(ent, input)
					if ent == e and input == "FireEvent" then
						seen = true
					end
				end)

				local ok, err = pcall(function()
					e:Input("FireEvent")
				end)

				hook.Remove("AcceptInput", "GryTestAchievementSeen")

				if IsValid(e) then
					e:Remove()
				end

				if not ok then
					error(err, 0)
				end

				expect(seen).to.beTrue()
			end
		}
	}
}
