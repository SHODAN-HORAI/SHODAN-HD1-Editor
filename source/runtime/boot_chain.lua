-- SHODAN HD1 Editor, installed beside another mod's patch: the same as boot.lua, then the other mod's own
-- boot chunk, which the installer kept as fgw/chain, so both run.
BUILD_DATE_INFORMATION = "2020-12-22 09:33:14"

local ok, core = pcall(require, "fgw/core")
if ok and type(core) == "table" and type(core.start) == "function" then pcall(core.start) end
pcall(require, "fgw/chain")
