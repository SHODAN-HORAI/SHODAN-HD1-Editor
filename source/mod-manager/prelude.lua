-- SHODAN HD1 Editor for Obsidian Mod Manager: the same editor as the standalone one, on Obsidian's calls.
-- package.py puts the editor's source right after this.
if rawget(_G, "fgw") then
	-- The standalone editor is installed too and already runs: two windows on one key would fight.
	obsidian.log("the standalone SHODAN HD1 Editor is installed, so this copy stays off")
	return
end
local fgw = {
	log = obsidian.log, storage = obsidian.storage, hook = obsidian.hook, wrap = obsidian.wrap,
	on_frame = obsidian.on_frame, on_session = obsidian.on_session, keybind = obsidian.keybind, ui = obsidian.ui,
	import = function(name) return obsidian.import(name == "api" and "obsidian.api" or name) end,
}
