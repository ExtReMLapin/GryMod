# tests

Tests in the GLuaTest format, run inside a real game with [gmod-mcp](https://github.com/ExtReMLapin/gmod-mcp): load a map, then call `tests_run` with the file and the realm. They need Garry's Mod; nothing here runs in the GitHub Actions (the checks that need no game are in [`tools/`](../tools/README.md)).

| Prefix | Realm | Holds |
| --- | --- | --- |
| `sv_*_test.lua` | server | Rules of the suit, the radar, objectives, the API on the server, the compat patches' server side. |
| `cl_*_test.lua` | client | The HUD, the Flash player, the options, the rendering, the API on the client, the compat patches' client side. |
| `sh_*_test.lua` | server | Shared code (registries, wire formats). |
| `*_job.lua`, `*_tool.lua` | either | Not tests: scripts run with `lua_job` for measurements, walks through a map, pixel comparisons. They report numbers or write pictures. |
| `minimap/`, `map/` | client | The minimap and the big map. |
| `fixtures/` | | Files the tests read. |

## Rules the tests follow

- A test that checks a change is written first and seen to fail for the right reason.
- A test puts back everything it replaced (a function, a convar, a hook), also when it fails, because a game keeps running after a test.
- A test says in a comment which change would make it fail.
- A server suite is run once per map load: the campaign tests leave entities behind that a second run trips on.

Known failures that are not caused by the code (an addon mounted in the game, a timing-sensitive case at a low frame rate) are not hidden: a run reports them like any other.
