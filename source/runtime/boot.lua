-- SHODAN HD1 Editor. The game requires this chunk as foundation/lua/build_date_information: the first line
-- is what the game's own chunk does, so anything failing after it leaves the game as it was.
BUILD_DATE_INFORMATION = "2020-12-22 09:33:14"

local ok, core = pcall(require, "fgw/core")
if ok and type(core) == "table" and type(core.start) == "function" then pcall(core.start) end
