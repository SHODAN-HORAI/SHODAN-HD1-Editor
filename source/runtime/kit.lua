-- Drawing for SHODAN HD1 Editor: rectangles and text on one immediate gui on the brightness world, the
-- only world that lives through every state change. Coordinates are a design space (frame(w, h)),
-- scaled to fit the window and centred, y going up from the bottom left as the engine's does.
local G = _G
local rawget, type, pcall, tostring = rawget, type, pcall, tostring

local M = { w = 1280, h = 720 }
local log = function() end

-- The game's own fonts. ui: body text, ui_heading: titles. chat has every letter, so it stands in
-- for a text the others can't draw.
local FONTS = {
	ui = { path = "fonts/handel_small", material = "handel_small", size = 18 },
	ui_heading = { path = "fonts/insignia_headliner", material = "insignia_headliner", size = 42 },
	chat = { path = "fonts/chat", material = "chat", size = 30 },
}
FONTS.body, FONTS.heading = FONTS.ui, FONTS.ui_heading

local gui, world
local function get_gui()
	if gui then return gui end
	local boot = rawget(G, "Boot")
	world = type(boot) == "table" and boot.brightness_world
	local manager = type(boot) == "table" and boot.package_manager
	if not world or not manager then return nil end
	-- A gui naming a material that isn't loaded yet would take the game down, so it waits for the fonts.
	local ok, on = pcall(manager.is_package_online, manager, "resource_packages/localization")
	if not (ok and on == true) then return nil end
	gui = rawget(G, "World").create_screen_gui(world, "material", "foundation/gui/gui", "material", "fonts/fonts", "immediate")
	-- The world goes at shutdown, so the gui goes first.
	local shutdown = rawget(G, "shutdown")
	if type(shutdown) == "function" then
		rawset(G, "shutdown", function(...)
			pcall(rawget(G, "World").destroy_gui, world, gui)
			gui = nil
			return shutdown(...)
		end)
	end
	log("gui made")
	return gui
end

local function layout()
	local w, h = rawget(G, "Application").resolution()
	local s = math.min(w / M.w, h / M.h)
	return s, (w - M.w * s) * 0.5, (h - M.h * s) * 0.5
end

local glyphs, glyph_count = {}, 0
local function font_for(name, s)
	local font = FONTS[name or "ui"] or FONTS.ui
	if font == FONTS.chat then return font end
	local key = font.path .. "\0" .. s
	local known = glyphs[key]
	if known == nil then
		known = rawget(G, "Gui").has_all_glyphs(gui, s, font.path) == true
		if glyph_count >= 512 then glyphs, glyph_count = {}, 0 end
		glyphs[key], glyph_count = known, glyph_count + 1
	end
	return known and font or FONTS.chat
end

-- Colors: { r, g, b } or { r, g, b, a }, 0 to 255. The engine's Color takes alpha first.
local function color(c)
	if type(c) ~= "table" then return rawget(G, "Color")(255, 255, 255, 255) end
	return rawget(G, "Color")(c[4] or 255, c[1], c[2], c[3])
end

local function intersect(area, x, y, w, h)
	if not area then return x, y, w, h end
	local left, bottom = math.max(area.x, x), math.max(area.y, y)
	local right, top = math.min(area.x + area.w, x + w), math.min(area.y + area.h, y + h)
	if right <= left or top <= bottom then return nil end
	return left, bottom, right - left, top - bottom
end

local Kit = {}
Kit.__index = Kit

-- Each draw works out the scale again, so a resolution change just works.
function Kit:ready()
	if not get_gui() then return false end
	self.scale, self.ox, self.oy = layout()
	return true
end

function Kit:layer(n)
	if type(n) == "number" then self.z = math.max(0, math.min(math.floor(n), 875)) end
	return self.z
end

-- A point in pixels (the mouse's), in design units.
function Kit:point(x, y)
	local s, ox, oy = layout()
	return (x - ox) / s, (y - oy) / s
end

function Kit:rect(x, y, w, h, c)
	if not self:ready() then return end
	local cx, cy, cw, ch = intersect(self.area, x, y, w, h)
	if not cx then return end
	local s = self.scale
	rawget(G, "Gui").rect(gui, rawget(G, "Vector3")(self.ox + cx * s, self.oy + cy * s, self.z),
		rawget(G, "Vector2")(cw * s, ch * s), color(c))
end

local function width_px(font, s, size)
	local low, high = rawget(G, "Gui").text_extents(gui, s, font.path, size)
	return high.x - low.x
end

-- The part of a line inside the clip, in whole letters: one gui can't cut through a letter.
local function fit_line(line, x, left, right, width_of)
	local chars = {}
	for ch in line:gmatch("[%z\1-\127\192-\255][\128-\191]*") do chars[#chars + 1] = ch end
	local first, last = 1, #chars
	while first <= last and x < left do
		x = x + width_of(chars[first])
		first = first + 1
	end
	while last >= first and x + width_of(table.concat(chars, "", first, last)) > right do last = last - 1 end
	if last < first then return nil end
	return table.concat(chars, "", first, last), x
end

-- One line of text, y its baseline. opts: font, size, color, align ("left", "center", "right").
function Kit:text(s, x, y, opts)
	if not self:ready() then return end
	s = tostring(s)
	if s == "" then return end
	opts = opts or {}
	local font = font_for(opts.font, s)
	local scale = self.scale
	local size = (opts.size or font.size) * scale
	local function width_of(part) return width_px(font, part, size) / scale end
	if opts.align == "center" or opts.align == "right" then
		local w = width_of(s)
		x = opts.align == "center" and x - w / 2 or x - w
	end
	local area = self.area
	if area then
		if y < area.y or y + size / scale * 0.7 > area.y + area.h then return end
		s, x = fit_line(s, x, area.x, area.x + area.w, width_of)
		if not s then return end
	end
	rawget(G, "Gui").text(gui, s, font.path, size, font.material,
		rawget(G, "Vector3")(self.ox + x * scale, self.oy + y * scale, self.z + 1), color(opts.color))
end

function Kit:measure(s, opts)
	if not self:ready() then return 0, 0 end
	s = tostring(s)
	opts = opts or {}
	if s == "" then return 0, opts.size or 18 end
	local font = font_for(opts.font, s)
	return width_px(font, s, (opts.size or font.size) * self.scale) / self.scale, opts.size or font.size
end

-- fn(kit) draws inside the rectangle.
function Kit:clip(x, y, w, h, fn)
	local outer = self.area
	local cx, cy, cw, ch = intersect(outer, x, y, w, h)
	if not cx then return end
	self.area = { x = cx, y = cy, w = cw, h = ch }
	local ok, err = pcall(fn, self)
	self.area = outer
	if not ok then error(err, 0) end
end

function M.frame(w, h)
	M.w, M.h = w, h
	return true
end

function M.canvas(id, opts)
	return setmetatable({ id = id, z = opts and opts.layer or 700, scale = 1, ox = 0, oy = 0 }, Kit)
end

function M.setup(log_fn)
	log = log_fn or log
end

return M
