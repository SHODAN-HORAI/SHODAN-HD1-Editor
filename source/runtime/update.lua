-- Updates from the GitHub releases, done by the game itself through Windows' own web functions (WinHTTP,
-- through LuaJIT's FFI, which the game loads on PC): no other program is started. The check and the download
-- are read a piece a frame. The zip is stored uncompressed, so its files are read straight out of it, and the
-- new patch file goes in when the game closes (the game holds it open while it runs).
local M = { state = "off", latest = nil }   -- state: off, checking, none, available, downloading, ready, failed
local REPO = "SHODAN-HORAI/SHODAN-HD1-Editor"
local DOWNLOADS = "https://github.com/" .. REPO .. "/releases/download/"
local PATCH = "9cf71054ea26dddf.patch_0"
local log, folder = function() end, nil
local C = nil

local function load_ffi()
	if C ~= nil then return C end
	C = false
	local ok, ffi = pcall(require, "ffi")
	if not ok or type(ffi) ~= "table" or ffi.os ~= "Windows" then return C end
	-- Names of our own (the __asm__ part is the real one): every script in the game shares LuaJIT's C names.
	local declared = pcall(ffi.cdef, [[
		int fgw_MultiByteToWideChar(unsigned int page, uint32_t flags, const char *s, int n, wchar_t *out, int size) __asm__("MultiByteToWideChar");
		int fgw_CreateDirectoryW(const wchar_t *path, void *security) __asm__("CreateDirectoryW");
		void *fgw_ShellExecuteW(void *hwnd, const wchar_t *verb, const wchar_t *file, const wchar_t *params, const wchar_t *dir, int show) __asm__("ShellExecuteW");
		void *fgw_WinHttpOpen(const wchar_t *agent, uint32_t access, const wchar_t *proxy, const wchar_t *bypass, uint32_t flags) __asm__("WinHttpOpen");
		int fgw_WinHttpSetTimeouts(void *h, int resolve, int connect, int send, int receive) __asm__("WinHttpSetTimeouts");
		void *fgw_WinHttpConnect(void *h, const wchar_t *server, unsigned short port, uint32_t reserved) __asm__("WinHttpConnect");
		void *fgw_WinHttpOpenRequest(void *h, const wchar_t *verb, const wchar_t *path, const wchar_t *version, const wchar_t *referrer, const wchar_t **types, uint32_t flags) __asm__("WinHttpOpenRequest");
		int fgw_WinHttpSendRequest(void *h, const wchar_t *headers, uint32_t length, void *optional, uint32_t optional_length, uint32_t total, uintptr_t context) __asm__("WinHttpSendRequest");
		int fgw_WinHttpReceiveResponse(void *h, void *reserved) __asm__("WinHttpReceiveResponse");
		int fgw_WinHttpQueryHeaders(void *h, uint32_t level, const wchar_t *name, void *buffer, uint32_t *length, uint32_t *index) __asm__("WinHttpQueryHeaders");
		int fgw_WinHttpQueryDataAvailable(void *h, uint32_t *available) __asm__("WinHttpQueryDataAvailable");
		int fgw_WinHttpReadData(void *h, void *buffer, uint32_t size, uint32_t *read) __asm__("WinHttpReadData");
		int fgw_WinHttpCloseHandle(void *h) __asm__("WinHttpCloseHandle");
	]])
	if not declared then return C end
	local ok2, shell = pcall(ffi.load, "shell32")
	local ok3, kernel = pcall(ffi.load, "kernel32")
	local ok4, http = pcall(ffi.load, "winhttp")
	if ok2 and ok3 then C = { ffi = ffi, shell = shell, kernel = kernel, http = ok4 and http or nil } end
	return C
end

-- getenv's paths are in Windows' own code page, so that's what they're read as.
local function wide(s)
	local n = C.kernel.fgw_MultiByteToWideChar(0, 0, s, -1, nil, 0)
	local out = C.ffi.new("wchar_t[?]", math.max(n, 1))
	C.kernel.fgw_MultiByteToWideChar(0, 0, s, -1, out, n)
	return out
end

local function mkdir(path)
	if load_ffi() then C.kernel.fgw_CreateDirectoryW(wide(path), nil) end
end

-- Opens a folder or web page the way Windows does (Explorer, the browser).
function M.open(target)
	if not load_ffi() then return false end
	local h = C.shell.fgw_ShellExecuteW(nil, wide("open"), wide(target), nil, nil, 1)
	return tonumber(C.ffi.cast("intptr_t", h)) > 32
end

-- Files ----------------------------------------------------------------------------------------------------

local function read_file(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- Written whole or not at all: a half-written patch file would be worse than the old one.
local function write_file(path, data)
	local f = io.open(path .. ".new", "wb")
	if not f then return false end
	local ok = f:write(data) ~= nil
	ok = f:close() and ok
	if not ok then os.remove(path .. ".new") return false end
	os.remove(path)
	if os.rename(path .. ".new", path) then return true end
	os.remove(path .. ".new")
	return false
end

local function u16(s, at) local a, b = s:byte(at, at + 1) return a + b * 256 end
local function u32(s, at) local a, b, c, d = s:byte(at, at + 3) return a + b * 256 + c * 65536 + d * 16777216 end
local function le32(n) return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256) end

-- The files of a stored (uncompressed) zip, by name.
function M.unzip(z)
	local out, at = {}, 1
	while z:sub(at, at + 3) == "PK\3\4" do
		local method, size, nlen, xlen = u16(z, at + 8), u32(z, at + 18), u16(z, at + 26), u16(z, at + 28)
		if method ~= 0 then return nil end
		local name = z:sub(at + 30, at + 29 + nlen)
		local start = at + 30 + nlen + xlen
		out[name] = z:sub(start, start + size - 1)
		at = start + size
	end
	return out
end
local function find(files, tail)
	for name, data in pairs(files) do
		if name:sub(-#tail) == tail then return data end
	end
end

-- Patch files ----------------------------------------------------------------------------------------------
-- A 12-byte header, then 64 KiB chunks, each zlib or, at exactly 65536 bytes, stored as is. The editor and
-- its installer write every chunk stored, so only those are read here. Names are kept as their 8 bytes.

local function hex8(h)   -- a hash's 8 bytes as the file holds them (little-endian)
	local out = {}
	for i = 15, 1, -2 do out[#out + 1] = string.char(tonumber(h:sub(i, i + 1), 16)) end
	return table.concat(out)
end
local LUA, BOOT, CHAIN, CORE = hex8("a14e8dfa2cd117e2"), hex8("35546153a5bb59d2"), hex8("0776dd65fac5026d"), hex8("0caefbeadd82700b")

local function unpack_bundle(raw)
	local size, parts, at, got = u32(raw, 5), {}, 13, 0
	while got < size and at <= #raw do
		local n = u32(raw, at)
		if n ~= 65536 then return nil end
		parts[#parts + 1] = raw:sub(at + 4, at + 3 + n)
		got, at = got + n, at + 4 + n
	end
	return table.concat(parts):sub(1, size)
end

local function parse(d)
	local count, res = u32(d, 1), {}
	local at = 261 + count * 16
	for _ = 1, count do
		local start, vc, sizes = at, u32(d, at + 16), 0
		for v = 0, vc - 1 do sizes = sizes + u32(d, at + 24 + v * 12 + 4) end
		at = at + 24 + 12 * vc + sizes
		res[#res + 1] = { type = d:sub(start, start + 7), name = d:sub(start + 8, start + 15), bytes = d:sub(start, at - 1) }
	end
	return { block = d:sub(5, 260), res = res }
end

local function pack(block, res)
	table.sort(res, function(a, b) return a.name:reverse() < b.name:reverse() end)   -- by the name's number
	local out = { le32(#res), block }
	for _, r in ipairs(res) do out[#out + 1] = r.type .. r.name end
	for _, r in ipairs(res) do out[#out + 1] = r.bytes end
	local d = table.concat(out)
	local chunks = { le32(0xF0000004), le32(#d), le32(0) }
	for i = 1, #d, 65536 do
		local c = d:sub(i, i + 65535)
		chunks[#chunks + 1] = le32(65536) .. c .. string.rep("\0", 65536 - #c)
	end
	return table.concat(chunks)
end

local function lua_record(name, data)
	return { type = LUA, name = name, bytes = LUA .. name .. le32(1) .. le32(0) .. le32(0) .. le32(#data) .. le32(0) .. data }
end

-- The new patch file: the new editor's files, and everything else the one there now holds (another mod's
-- files, kept beside ours by the installer). nil and why when it can't be done.
-- shortcut: a file a newer version no longer has stays in the patch (harmless); the installer clears them.
function M.merge(current_raw, files)
	local new_raw, chain = find(files, "/" .. PATCH), find(files, "/boot_chain.bin")
	if not (new_raw and chain) then return nil, "the zip has no patch file" end
	local cur_d, new_d = unpack_bundle(current_raw), unpack_bundle(new_raw)
	if not (cur_d and new_d) then return nil, "a patch file isn't stored the editor's way" end
	local cur, new = parse(cur_d), parse(new_d)
	local ours, chained = false, false
	for _, r in ipairs(cur.res) do
		if r.name == CORE then ours = true end
		if r.name == CHAIN then chained = true end
	end
	if not ours then return nil, "the patch file there isn't the editor's (another mod manager wrote it)" end
	local names, out = {}, {}
	for _, r in ipairs(new.res) do
		names[r.name] = true
		out[#out + 1] = (chained and r.name == BOOT) and lua_record(BOOT, chain) or r
	end
	for _, r in ipairs(cur.res) do
		if not names[r.name] then out[#out + 1] = r end
	end
	return pack(new.block, out)
end

-- Web ------------------------------------------------------------------------------------------------------
-- One request at a time. Sending it and its first answer wait in one frame (well under a second); the body
-- is read up to 256 KiB a frame.

local req = nil
local function close_req()
	if not req then return end
	for _, h in ipairs({ req.r or false, req.c or false, req.s or false }) do
		if h and h ~= nil then C.http.fgw_WinHttpCloseHandle(h) end
	end
	req = nil
end

local function fetch(url, done)
	close_req()
	if not (load_ffi() and C.http) then return done(nil, "no WinHTTP") end
	local host, path = url:match("^https://([^/]+)(/.*)$")
	if not host then return done(nil, "bad address") end
	local h = C.http
	local s = h.fgw_WinHttpOpen(wide("SHODAN-HD1-Editor"), 4, nil, nil, 0)   -- 4: the system's proxy settings
	if s == nil then s = h.fgw_WinHttpOpen(wide("SHODAN-HD1-Editor"), 0, nil, nil, 0) end
	if s == nil then return done(nil, "WinHttpOpen failed") end
	h.fgw_WinHttpSetTimeouts(s, 3000, 3000, 3000, 5000)
	req = { s = s, parts = {}, done = done }
	req.c = h.fgw_WinHttpConnect(s, wide(host), 443, 0)
	if req.c ~= nil then req.r = h.fgw_WinHttpOpenRequest(req.c, wide("GET"), wide(path), nil, nil, nil, 0x00800000) end
	local ok = req.r and req.r ~= nil and h.fgw_WinHttpSendRequest(req.r, nil, 0, nil, 0, 0, 0) ~= 0
		and h.fgw_WinHttpReceiveResponse(req.r, nil) ~= 0
	if not ok then close_req() return done(nil, "no answer from GitHub") end
	local code, len = C.ffi.new("uint32_t[1]"), C.ffi.new("uint32_t[1]", 4)
	h.fgw_WinHttpQueryHeaders(req.r, 19 + 0x20000000, nil, code, len, nil)   -- the status code, as a number
	req.status = code[0]
	req.buf, req.n = C.ffi.new("uint8_t[65536]"), C.ffi.new("uint32_t[1]")
end

local function fetch_step()
	if not req then return end
	local h, got = C.http, 0
	while req and got < 262144 do
		local r = req
		if h.fgw_WinHttpQueryDataAvailable(r.r, r.n) == 0 then
			close_req()
			return r.done(nil, "the download broke off")
		end
		local want = math.min(r.n[0], 65536)
		if want == 0 then
			close_req()
			if r.status ~= 200 then return r.done(nil, "GitHub said " .. tostring(r.status)) end
			return r.done(table.concat(r.parts))
		end
		if h.fgw_WinHttpReadData(r.r, r.buf, want, r.n) == 0 then
			close_req()
			return r.done(nil, "the download broke off")
		end
		r.parts[#r.parts + 1] = C.ffi.string(r.buf, r.n[0])
		got = got + r.n[0]
	end
end

-- Versions -------------------------------------------------------------------------------------------------

local function parts(v)
	local out = {}
	for n in tostring(v or ""):gmatch("%d+") do out[#out + 1] = tonumber(n) end
	return out
end
local function newer(a, b)
	local x, y = parts(a), parts(b)
	for k = 1, math.max(#x, #y) do
		local p, q = x[k] or 0, y[k] or 0
		if p ~= q then return p > q end
	end
	return false
end

-- GitHub's answer about a release: { version, label, url, commit } or nil.
function M.read_release(json, channel)
	for url in json:gmatch('"browser_download_url"%s*:%s*"([^"]+)"') do
		if url:sub(1, #DOWNLOADS) == DOWNLOADS then
			local file = url:match("[^/]+$")
			if channel == "commits" then
				local commit = file:match("^SHODAN%-HD1%-Editor%-dev%-(%x+)%.zip$")
				if commit then return { version = "dev", label = "dev " .. commit:sub(1, 7), url = url, commit = commit } end
			elseif file:match("^SHODAN%-HD1%-Editor%-[%d%.]+%.zip$") then
				local version = (json:match('"tag_name"%s*:%s*"([^"]+)"') or ""):gsub("^v", "")
				return { version = version, label = version, url = url, commit = "" }
			end
		end
	end
end

-- version: the running editor's. channel: "releases" or "commits". mode: "ask" or "auto".
function M.check(version, channel, mode)
	if not folder or M.state == "downloading" or M.state == "ready" then return end
	M.version, M.channel, M.mode = version, channel, mode
	M.state = "checking"
	local api = "https://api.github.com/repos/" .. REPO .. (channel == "commits" and "/releases/tags/dev" or "/releases/latest")
	fetch(api, function(json, why)
		if not json then
			M.state = "none"
			return log("update: nothing found (" .. tostring(why) .. ")")
		end
		local l = M.read_release(json, channel)
		local mine = read_file(folder .. "update\\commit.txt")
		local is_new = l and (channel == "commits" and l.commit ~= (mine and mine:match("%w+")) or channel ~= "commits" and newer(l.version, version))
		if not is_new then
			M.state = "none"
			return log("update: up to date" .. (l and " (" .. l.label .. ")" or ""))
		end
		M.latest, M.state = l, "available"
		log("update: " .. l.label .. " is available")
		if M.mode == "auto" then M.install() end
	end)
end

-- Downloads the update now; it goes in when the game closes.
function M.install()
	if M.state ~= "available" then return false end
	local l = M.latest
	if l.url:sub(1, #DOWNLOADS) ~= DOWNLOADS then M.state = "failed" return false end
	M.state = "downloading"
	log("update: downloading " .. l.label)
	fetch(l.url, function(zip, why)
		local files = zip and M.unzip(zip)
		if not (files and find(files, "/" .. PATCH)) then
			M.state = "failed"
			return log("update: download failed (" .. tostring(why or "not a zip of the editor") .. ")")
		end
		M.files, M.state = files, "ready"
		log("update: " .. l.label .. " downloaded, goes in when the game closes")
		M.toast("HD1 Editor " .. l.label .. " is downloaded. It goes in when you close the game.")
	end)
	return true
end

-- At the game's shutdown: the new patch file goes in. If it can't, the update's files are unpacked in
-- update\ with their installer, and the next start says to run it.
function M.put_in()
	if M.state ~= "ready" then return end
	local l, files = M.latest, M.files
	M.state = "off"
	local game = read_file(folder .. "game.txt")
	game = game and game:match("[^\r\n]+")
	local target = game and (game .. "\\" .. PATCH)
	local current = target and read_file(target)
	local merged, why = nil, "the game's folder isn't known"
	if current then merged, why = M.merge(current, files) end
	if merged and write_file(target, merged) then
		local commit = find(files, "/commit.txt")
		if commit then write_file(folder .. "update\\commit.txt", commit) else os.remove(folder .. "update\\commit.txt") end
		write_file(folder .. "update\\done.txt", l.label)
		return log("update: " .. l.label .. " is in")
	end
	local dir = folder .. "update\\SHODAN HD1 Editor"
	mkdir(dir)
	for name, data in pairs(files) do
		local rel = name:match("^[^/]+/(.+)$")
		if rel and rel:sub(-1) ~= "/" then
			local sub = rel:match("^(.*)/")
			if sub then mkdir(dir .. "\\" .. sub:gsub("/", "\\")) end
			local f = io.open(dir .. "\\" .. rel:gsub("/", "\\"), "wb")
			if f then f:write(data) f:close() end
		end
	end
	write_file(folder .. "update\\failed.txt", l.label .. "\t" .. tostring(why or "the game held the file"))
	log("update: couldn't put " .. l.label .. " in: " .. tostring(why or "the game held the file"))
end

function M.set_mode(mode)
	M.mode = mode
	if mode == "auto" and M.state == "available" then M.install() end
end

local wrapped = false
function M.tick(dt)
	if req then
		local ok, err = pcall(fetch_step)
		if not ok then
			close_req()
			M.state = "failed"
			log("update: " .. tostring(err))
		end
	end
	-- The game's shutdown is defined after the editor starts: wrapped once it's there.
	local shutdown = rawget(_G, "shutdown")
	if not wrapped and type(shutdown) == "function" then
		wrapped = true
		rawset(_G, "shutdown", function(...)
			local ok, err = pcall(M.put_in)
			if not ok then log("update: " .. tostring(err)) end
			return shutdown(...)
		end)
	end
end

-- A label to show on the title bar's button, or nil.
function M.offer()
	if M.state == "available" and M.mode == "ask" then return "Update to " .. M.latest.label end
	if M.state == "downloading" then return "Downloading " .. M.latest.label end
	if M.state == "ready" then return "Updates when the game closes" end
	return nil
end

function M.setup(dir, log_fn, toast)
	folder, log, M.toast = dir, log_fn or log, toast or function() end
	if not folder then return end
	mkdir(folder .. "update")
	-- Put in when the game last closed, or left for a hand install.
	local done = read_file(folder .. "update\\done.txt")
	if done then
		os.remove(folder .. "update\\done.txt")
		M.done = done:match("[^\r\n]+")
	end
	local failed = read_file(folder .. "update\\failed.txt")
	if failed then
		os.remove(folder .. "update\\failed.txt")
		M.failed = failed:match("^[^\t\r\n]+")
	end
end

return M
