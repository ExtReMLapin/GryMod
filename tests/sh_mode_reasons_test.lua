-- Tests of the causes of a mode change as the server and the client share them (lua/autorun/grymod_shared.lua), GLuaTest format, either realm.
-- The cause crosses the network as an integer (an enum) and comes back as the string the GryMod_ModeChanged hook gets, so the two tables must agree.

return {
	groupName = "GryMod mode change causes: names and ids on the wire",
	cases = {
		{
			-- would fail if: VETOED or SYNC were missing from GryMod.ModeReasons, or were not plain strings
			name = "the two causes of the client's side exist: VETOED and SYNC, as strings, different from the others",
			func = function()
				expect(GryMod.ModeReasons.VETOED).to.equal("vetoed")
				expect(GryMod.ModeReasons.SYNC).to.equal("sync")

				local seen = {}

				for key, value in pairs(GryMod.ModeReasons) do
					expect(isstring(value)).to.beTrue()
					expect(seen[value]).to.beNil()
					seen[value] = key
				end
			end
		},
		{
			-- would fail if: a cause was added to GryMod.ModeReasons without an id (it could not be sent), or the list kept a string that no constant has
			name = "every cause has an id and every id has a cause: the list and ModeReasons hold exactly the same strings",
			func = function()
				local list = GryMod.ModeReasonList
				expect(istable(list)).to.beTrue()

				local fromConstants = 0

				for _, value in pairs(GryMod.ModeReasons) do
					fromConstants = fromConstants + 1
					expect(GryMod.ModeReasonIds[value] ~= nil).to.beTrue()
				end

				expect(#list).to.equal(fromConstants)
			end
		},
		{
			-- would fail if: the order of the list changed (the ids are the wire format: an old client would read the wrong cause) or an id was off by one
			name = "the ids are the position in the list minus 1, in the order of the wire format: spawn is 0, sync is 8, restore (added at the end) is 9",
			func = function()
				local expected = {"spawn", "player", "api", "energy", "malfunction", "disabled", "other", "vetoed", "sync", "restore"}

				for i, reason in ipairs(expected) do
					expect(GryMod.ModeReasonList[i]).to.equal(reason)
					expect(GryMod.ModeReasonIds[reason]).to.equal(i - 1)
				end
			end
		},
		{
			-- would fail if: the width was too small for the biggest id (the cause would be cut on the wire), or the inverse table did not match the list
			name = "every cause goes through the wire and back: its id fits in ModeReasonBits, and the list gives the same string",
			func = function()
				expect(GryMod.ModeReasonBits).to.equal(4)

				for key, reason in pairs(GryMod.ModeReasons) do
					local id = GryMod.ModeReasonIds[reason]

					expect(id >= 0 and id < 2 ^ GryMod.ModeReasonBits).to.beTrue()
					expect(GryMod.ModeReasonList[id + 1]).to.equal(reason)
				end
			end
		}
	}
}
