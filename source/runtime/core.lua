-- SHODAN HD1 Editor's runtime: starts the editor inside the game and gives it what it needs, as the
-- table `fgw` the editor and the API files (api/lib/, MIT, see api/LICENSE) call.
-- The engine calls the global `update` every frame; the boot script defines it after this file runs, so
-- the frame driver goes in from a wrapped `require`, as do hooks on classes that load later.
local G = _G
local rawget, rawset, type, pairs, ipairs, pcall, select, tostring = rawget, rawset, type, pairs, ipairs, pcall, select, tostring
local unpack = unpack or table.unpack
local function pack(...) return { n = select("#", ...), ... } end

local M = { frame_fns = {}, hooks = {}, binds = {}, toasts = {}, modules = {}, started = false }
local ID = "shodan.fgw"
local FOLDER = nil   -- %LOCALAPPDATA%\SHODAN\SHD1Editor\, made by the installer
do
	local ok, base = pcall(function() return os.getenv("LOCALAPPDATA") end)
	if ok and type(base) == "string" then FOLDER = base .. "\\SHODAN\\SHD1Editor\\" end
end

-- Log: one file per launch, kept short.
local log_lines = 0
local function log(s)
	if not FOLDER or log_lines > 2000 then return end
	log_lines = log_lines + 1
	pcall(function()
		local f = io.open(FOLDER .. "log.txt", log_lines == 1 and "w" or "a")
		if f then
			f:write(os.date("%H:%M:%S "), tostring(s), "\n")
			f:close()
		end
	end)
end
M.log = log

-- Storage: one text file, "key<TAB>s or n<TAB>value" per line, \, tabs and line breaks escaped.
-- Written on every change.
local store, store_loaded = {}, false
local ESCAPES = { ["\\"] = "\\\\", ["\t"] = "\\t", ["\n"] = "\\n", ["\r"] = "\\r" }
local UNESCAPES = { ["\\\\"] = "\\", ["\\t"] = "\t", ["\\n"] = "\n", ["\\r"] = "\r" }
local function unescape(s) return (s:gsub("\\.", UNESCAPES)) end
local function escape(s) return (s:gsub("[\\\t\n\r]", ESCAPES)) end
local function load_store()
	if store_loaded then return end
	store_loaded = true
	if not FOLDER then return end
	pcall(function()
		local f = io.open(FOLDER .. "storage.txt", "r")
		if not f then return end
		for line in f:lines() do
			local k, kind, v = line:match("^([^\t]*)\t([sbn])\t(.*)$")
			if k then
				v = unescape(v)
				if kind == "b" then v = v == "1" elseif kind == "n" then v = tonumber(v) end
				store[unescape(k)] = v
			end
		end
		f:close()
	end)
end
local function save_store()
	if not FOLDER then return end
	local ok, err = pcall(function()
		local lines = {}
		for k, v in pairs(store) do
			lines[#lines + 1] = escape(k) .. "\t" .. (type(v) == "number" and "n" or "s") .. "\t" .. escape(tostring(v))
		end
		table.sort(lines)
		local f = assert(io.open(FOLDER .. "storage.tmp", "w"))
		f:write(table.concat(lines, "\n"), "\n")
		f:close()
		os.remove(FOLDER .. "storage.txt")
		assert(os.rename(FOLDER .. "storage.tmp", FOLDER .. "storage.txt"))
	end)
	if not ok then log("storage not saved: " .. tostring(err)) end
end
local storage = {
	get = function(k, default)
		load_store()
		local v = store[k]
		if v == nil then return default end
		return v
	end,
	set = function(k, v)
		load_store()
		if v ~= nil and type(v) ~= "string" and type(v) ~= "number" then v = tostring(v) end
		store[k] = v
		save_store()
		return true
	end,
	all = function()
		load_store()
		local out = {}
		for k, v in pairs(store) do out[k] = v end
		return out
	end,
}

-- Hooks: fn(original, ...) in place of Class.method, put in once the class has the method. A hook
-- that fails falls back to the game's own function, so a broken hook can't take the game down.
local function try_hook(h)
	local t = rawget(G, h.class)
	if type(t) ~= "table" then return false end
	local original = rawget(t, h.method)
	if type(original) ~= "function" then
		-- A method on the class behind an instance.
		original = t[h.method]
		if type(original) ~= "function" then return false end
	end
	local fn, name = h.fn, h.class .. "." .. h.method
	local failed = false
	-- When the hook fails after it ran the game's function, that isn't run again: it would save or
	-- spend twice. One closure per hook, as a new one per call stops the JIT.
	local ran, results = false, nil
	local function once(...)
		ran = true
		results = pack(original(...))
		return unpack(results, 1, results.n)
	end
	t[h.method] = function(...)
		if failed then return original(...) end
		local outer_ran, outer_results = ran, results
		ran, results = false, nil
		local out = pack(pcall(fn, once, ...))
		local did, got = ran, results
		ran, results = outer_ran, outer_results
		if out[1] then return unpack(out, 2, out.n) end
		failed = true
		log("hook " .. name .. " failed, off from now on: " .. tostring(out[2]))
		if did then
			if got then return unpack(got, 1, got.n) end
			return
		end
		return original(...)
	end
	return true
end
local function hook(class, method, fn)
	local h = { class = class, method = method, fn = fn }
	if not try_hook(h) then M.hooks[#M.hooks + 1] = h end
	return true
end
local function pending_hooks()
	for i = #M.hooks, 1, -1 do
		if try_hook(M.hooks[i]) then table.remove(M.hooks, i) end
	end
end

-- Keys: a bind fires on the key's press. Keys are named as Keyboard.button_index names them.
local function poll_binds()
	local kb = rawget(G, "Keyboard")
	if type(kb) ~= "table" then return end
	for _, b in ipairs(M.binds) do
		local name = storage.get("key." .. b.id, b.key)
		if b.name ~= name then
			local ok, i = pcall(kb.button_index, name)
			b.name, b.index = name, ok and i or nil
		end
		if b.index and kb.pressed(b.index) == true then
			local ok, err = pcall(b.fn)
			if not ok then log("key " .. b.id .. ": " .. tostring(err)) end
		end
	end
end

-- Toasts: a short line at the top of the screen for a few seconds.
local toast_kit
local function toast(s)
	M.toasts[#M.toasts + 1] = { text = tostring(s), left = 3 }
	while #M.toasts > 4 do table.remove(M.toasts, 1) end
	log("toast: " .. tostring(s))
end
local function draw_toasts(dt)
	if #M.toasts == 0 then return end
	local kit = toast_kit
	for i = #M.toasts, 1, -1 do
		local t = M.toasts[i]
		t.left = t.left - dt
		if t.left <= 0 then table.remove(M.toasts, i) end
	end
	for i, t in ipairs(M.toasts) do
		local w = kit:measure(t.text, { font = "ui", size = 16 }) + 32
		local y = 720 - 40 - (i - 1) * 34
		local a = math.min(1, t.left * 2)
		kit:layer(870)
		kit:rect(640 - w / 2, y - 8, w, 28, { 8, 11, 15, 235 * a })
		kit:layer(871)
		kit:rect(640 - w / 2, y - 8, 3, 28, { 255, 213, 0, 255 * a })
		kit:text(t.text, 640, y, { font = "ui", size = 16, color = { 238, 242, 246, 255 * a }, align = "center" })
	end
end

local update = nil

-- The frame driver.
local function frame(dt)
	pending_hooks()
	poll_binds()
	if update then
		pcall(update.tick, dt)
		if update.done and toast_kit:ready() then
			toast("SHODAN HD1 Editor updated to " .. update.done)
			update.done = nil
		end
		if update.failed and toast_kit:ready() then
			toast("HD1 Editor " .. update.failed .. " couldn't go in by itself: run Install.bat in " .. FOLDER .. "update\\SHODAN HD1 Editor")
			update.failed = nil
		end
	end
	for i = #M.frame_fns, 1, -1 do
		local f = M.frame_fns[i]
		local ok, done = pcall(f)
		if not ok then
			log("frame: " .. tostring(done))
		elseif done == true then
			table.remove(M.frame_fns, i)
		end
	end
	local script = rawget(G, "Script")
	local v, q, m = script.temp_count()
	local ok, err = pcall(draw_toasts, dt)
	script.set_temp_count(v, q, m)
	if not ok then log("toasts: " .. tostring(err)) end
end

local driven
local function drive()
	-- Once: another mod's loader wraps update over ours, and wrapping that again would run us twice a frame.
	local update = rawget(G, "update")
	if driven or type(update) ~= "function" then return end
	local game_update = update
	driven = function(dt, ...)
		local out = pack(game_update(dt, ...))
		local ok, err = pcall(frame, type(dt) == "number" and dt or 0.016)
		if not ok then log("frame driver: " .. tostring(err)) end
		return unpack(out, 1, out.n)
	end
	rawset(G, "update", driven)
	log("frame driver on")
end

local function wrap_require()
	local real = rawget(G, "require")
	rawset(G, "require", function(name, ...)
		local out = pack(real(name, ...))
		pcall(drive)
		pcall(pending_hooks)
		return unpack(out, 1, out.n)
	end)
end

-- The API files, loaded by name. lib/custom (custom stratagems) is left out: an empty stand-in.
local CUSTOM = {
	list = function() return {} end, is_unlocked = function() return false end,
	unlock = function() return false, "not_available" end, lock = function() return false, "not_available" end,
	define = function() return nil, "not_available" end, install = function() end, tick = function() end,
}
local function module(name)
	local m = M.modules[name]
	if m ~= nil then return m end
	if name == "lib/custom" then m = CUSTOM else m = require("fgw/api/" .. name) end
	M.modules[name] = m
	return m
end

local kit = nil
local api = nil
local function make_api()
	if api then return api end
	local game, effects, edits, data, catalog, gear, stratagems, progress =
		module("lib/game"), module("lib/effects"), module("lib/edits"), module("lib/data"),
		module("lib/catalog"), module("lib/gear"), module("lib/stratagems"), module("lib/progress")
	M.frame_fns[#M.frame_fns + 1] = function()
		game.tick()
		effects.tick(rawget(G, "ENGINE_DT") or 0.016)
	end
	api = { version = 1, game = game, effects = effects, edits = edits, data = data, catalog = catalog,
		gear = gear, stratagems = stratagems, progress = progress, menu = { toast = toast } }
	return api
end

G.fgw = {
	log = log,
	caller = function() return ID end,
	scope = function() return "session" end,
	session = { cleared = function() return true end },
	storage = storage,
	module = module,
	import = function(name) if name == "api" then return make_api() end end,
	hook = hook,
	wrap = hook,
	on_frame = function(fn) table.insert(M.frame_fns, 1, fn) return true end,
	on_session = function() return true end,
	keybind = function(id, fn) M.binds[#M.binds + 1] = { id = id, key = "f7", fn = fn } return true end,
	ui = {
		frame = function(w, h) return kit.frame(w, h) end,
		canvas = function(id, opts) return kit.canvas(id, opts) end,
	},
}

function M.start()
	if M.started then return end
	M.started = true
	log("SHODAN HD1 Editor starting")
	kit = require("fgw/kit")
	kit.setup(log)
	toast_kit = kit.canvas("toasts", { over_fades = true })
	require("fgw/block").setup(hook, log)
	update = require("fgw/update")
	update.setup(FOLDER, log, toast)
	G.fgw.update = update
	G.fgw.open, G.fgw.folder = update.open, FOLDER
	wrap_require()
	drive()
	local ok, err = pcall(require, "fgw/editor")
	if not ok then log("editor: " .. tostring(err)) end
end

return M
