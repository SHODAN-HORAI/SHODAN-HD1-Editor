-- SHODAN HD1 Editor for HELLDIVERS: every stat, in one window, changed live.
-- Edits go through api.edits (type and range checked, undoable). They're kept for the next launch and
-- in five presets, as lines of "where|path|type|value" in this mod's storage.
local api = fgw.import("api")
local catalog, edits, game = api.catalog, api.edits, api.game
local global = game.global

local H = 720
local WX, WY, WW, WH = 120, 40, 1040, 640
local PAD, LIST_W, ROW_H = 12, 300, 20
local IFACE, CURSOR = "shodan_stat_editor", "hud/cursors/menu"
local HELLDIVER = "characters/helldiver_private_01/helldiver_private_01"
local CLOSED_STATES = { logos = true, cutscene = true, transition = true }
local FIRST_REPEAT, NEXT_REPEAT, SAVE_AFTER = 0.4, 0.06, 2

-- SSEO's colours.
local GOLD, WHITE, MUTED, DIM, GOOD = { 255, 213, 0 }, { 238, 242, 246 }, { 153, 171, 184 }, { 95, 108, 120 }, { 120, 220, 140 }
local BG, BOX, HOT, SUNK, LINE = { 8, 11, 15, 242 }, { 28, 34, 42 }, { 52, 66, 80 }, { 20, 26, 34 }, { 70, 82, 94 }
local PICKED, HOVER, BAND, FOCUS, THUMB = { 90, 74, 8 }, { 40, 52, 64 }, { 15, 20, 26 }, { 30, 38, 48 }, { 110, 124, 138 }

local FAMILY = {
	firearm = "Firearm", beam = "Laser", flame = "Flamethrower", arc = "Arc", launcher = "Launcher", explosive = "Explosion",
	grenade = "Throw", melee = "Melee", turret = "Sentry", mine = "Mines", airstrike = "Airstrike", strafing = "Strafing run",
	artillery = "Artillery", orbital = "Orbital", backpack = "Backpack", vehicle = "Vehicle", toughness = "Toughness",
	enemy = "Enemy", stratagem = "Stratagem", status = "Status effect", character = "Helldiver",
}
local APPLIES = {
	live = "Applies at once.", reload = "Applies at once.", spawn = "Applies to the next one that spawns.",
	use = "Applies on the next call-in or use.", loadout = "Applies on the next mission or respawn.",
}

local CHARACTER = {
	{ path = "character_info.move_speed_jog", label = "Jog speed", min = 0.5, max = 20, apply = "use" },
	{ path = "character_info.move_speed_sprint_max", label = "Sprint speed", min = 0.5, max = 30, apply = "live" },
	{ path = "character_info.move_speed_sprint_min", label = "Tired sprint speed", min = 0.5, max = 30, apply = "live" },
	{ path = "character_info.move_speed_aim", label = "Aiming speed", min = 0.1, max = 10, apply = "use" },
	{ path = "character_info.move_speed_crawl", label = "Crawl speed", min = 0.1, max = 10, apply = "use" },
	{ path = "character_info.move_speed_dive", label = "Dive speed", min = 1, max = 40, apply = "use" },
	{ path = "character_info.dive_duration", label = "Dive time (s)", min = 0.2, max = 3, apply = "use" },
	{ path = "character_info.get_up_presses_needed", label = "Presses to get up", min = 1, max = 100, apply = "spawn" },
	{ path = "character_info.sprint_stamina", label = "Stamina (s)", min = 1, max = 120, apply = "live" },
	{ path = "character_info.spawn_time", label = "Landing time (s)", min = 0.5, max = 10, apply = "spawn" },
	{ path = "health_info.health", label = "Health", min = 1, max = 32767, apply = "spawn" },
	{ path = "health_info.armor_max", label = "Armor", min = 0, max = 3000, apply = "spawn" },
}
for _, f in ipairs(CHARACTER) do f.family, f.type = "character", "number" end

-- Fields the game has that the API doesn't list, by family. A row shows only where the item has the
-- value (opt ones everywhere), and a path the API already lists is skipped.
local MOVE = {
	{ path = "weapon_info.move_speed_aim", label = "Move speed aiming", min = 0, max = 3, apply = "reload", meaning = "Multiplier" },
	{ path = "weapon_info.move_speed_fire", label = "Move speed firing", min = 0, max = 3, apply = "reload", meaning = "Multiplier" },
	{ path = "weapon_info.move_speed_reload", label = "Move speed reloading", min = 0, max = 3, apply = "reload", meaning = "Multiplier. 0 stands you still" },
	{ path = "weapon_info.turn_speed_aim", label = "Turn speed aiming", min = 0, max = 1.5, apply = "reload", meaning = "Multiplier" },
	{ path = "weapon_info.turn_speed_fire", label = "Turn speed firing", min = 0, max = 1.5, apply = "reload", meaning = "Multiplier" },
	{ path = "weapon_info.turn_speed_reload", label = "Turn speed reloading", min = 0, max = 1.5, apply = "reload", meaning = "Multiplier" },
}
local RELOAD = {
	{ path = "weapon_info.reload_duration", label = "Reload time (empty)", min = 0.05, max = 30, apply = "live" },
	{ path = "weapon_info.reload_duration_fast", label = "Reload time (tactical)", min = 0.05, max = 30, apply = "live", meaning = "With rounds left in the magazine" },
	{ path = "weapon_info.reload_duration_assisted", label = "Reload time (assisted)", min = 0.05, max = 30, apply = "live", meaning = "When a teammate loads it" },
	{ path = "weapon_info.magazines", label = "Spare magazines", min = 0, max = 255, apply = "spawn", meaning = "Carried at the start, and added by an ammo pickup" },
}
local EXTRA = {
	firearm = {
		{ path = "weapon_info.heal_per_second", label = "Healing per second", min = 0, max = 5000, apply = "reload" },
		{ path = "weapon_info.max_num_targets", label = "Heal targets", min = 1, max = 10, apply = "reload", meaning = "People healed at once" },
	},
	launcher = {},
	beam = {},
	flame = {},
	arc = {
		{ path = "weapon_info.max_range_from_owner", label = "Max range", min = 1, max = 100, apply = "reload", meaning = "Meters from you" },
		{ path = "weapon_info.min_range_from_owner", label = "Min range", min = 0, max = 20, apply = "reload", meaning = "Meters from you" },
		{ path = "weapon_info.arc_size_min", label = "Cone at no charge", min = 0.05, max = 3.14, apply = "reload", meaning = "In radians" },
		{ path = "weapon_info.min_number_of_jumps", label = "Min jumps", min = 1, max = 20, apply = "reload" },
		{ path = "weapon_info.max_jump_distance_inside_arc", label = "Jump range inside the cone", min = 0, max = 50, apply = "live", meaning = "Meters" },
		{ path = "weapon_info.max_jump_distance_outside_arc", label = "Jump range outside the cone", min = 0, max = 50, apply = "live", meaning = "Meters" },
		{ path = "weapon_info.round_delay", label = "Shot delay (s)", min = 0, max = 2, apply = "reload" },
	},
	explosive = {
		{ path = "explosive_info.ignore_armor", type = "boolean", opt = true, label = "Ignores armor", apply = "live" },
		{ path = "explosive_info.ignore_shields", type = "boolean", opt = true, label = "Ignores shields", apply = "live" },
		{ path = "explosive_info.explode_on_impact", type = "boolean", label = "Explodes on impact", apply = "spawn" },
		{ path = "explosive_info.arm_time", label = "Arming time (s)", min = 0, max = 30, apply = "spawn" },
	},
}
for _, f in ipairs(RELOAD) do EXTRA.launcher[#EXTRA.launcher + 1] = f end
for _, list in pairs({ EXTRA.firearm, EXTRA.launcher, EXTRA.beam, EXTRA.flame, EXTRA.arc }) do
	for _, f in ipairs(MOVE) do list[#list + 1] = f end
end
for name, list in pairs(EXTRA) do
	for _, f in ipairs(list) do f.family, f.type = name, f.type or "number" end
end

-- The API's fields of a family and ours, without repeats.
local function fields_of(name)
	local out, have = {}, {}
	for _, f in ipairs(catalog.fields(name)) do out[#out + 1] = f have[f.path] = true end
	for _, f in ipairs(EXTRA[name] or {}) do
		if not have[f.path] then out[#out + 1] = f have[f.path] = true end
	end
	return out
end

local GRENADES = {
	{ "Frag grenade", "equipment/equipment_grenade_01" }, { "Incendiary grenade", "equipment/equipment_grenade_incendiary" },
	{ "Stun grenade", "equipment/equipment_grenade_stun" }, { "Smoke grenade", "equipment/equipment_grenade_smoke" },
}

local function units(list, extra)
	local out = {}
	-- save: the name the save keeps the item's upgrades under. A pack's are its stratagem's.
	for _, it in ipairs(list) do
		local strat = not it.upgrades and catalog.stratagem(it.stratagem or it.name)
		out[#out + 1] = { kind = "unit", name = catalog.text(it.name), unit = it.unit_path, save = it.stratagem or it.name, upgrades = it.upgrades or strat and strat.upgrades, strat = strat and strat.name }
	end
	for _, e in ipairs(extra or {}) do out[#out + 1] = { kind = "unit", name = e[1], unit = e[2] } end
	return out
end

local TABS = {
	{ "Primary", function() return units(catalog.primaries()) end },
	{ "Secondary", function() return units(catalog.sidearms()) end },
	{ "Support", function() return units(catalog.support_weapons()) end },
	{ "Grenades", function() return units({}, GRENADES) end },
	{ "Backpacks", function() return units(catalog.backpacks()) end },
	{ "Stratagems", function()
		local out = {}
		for _, s in ipairs(catalog.stratagems()) do out[#out + 1] = { kind = "strat", name = catalog.text(s.name), id = s.name } end
		return out
	end },
	{ "Sentries", function() return units(catalog.by_subtype("turret")) end },
	-- The drop has the number of mines, and each mine its own arming delay.
	{ "Mines", function() return units(catalog.by_subtype("mine"), { { "Mine", "gameobjects/mine_01" }, { "Stun mine", "gameobjects/mine_stun" } }) end },
	{ "Strikes", function() return units(catalog.by_subtype("strike")) end },
	{ "Vehicles", function() return units(catalog.vehicles()) end },
	{ "Enemies", function()
		local out = {}
		-- The data names some in capitals and a few not at all.
		local FACTION = { bugs = "Bug", cyborgs = "Cyborg", illuminates = "Illuminate" }
		for _, e in ipairs(catalog.enemies()) do
			local name = e.name or string.gsub(string.gsub(e.key, "^%a+_", ""), "_", " ")
			name = string.gsub(string.lower(name), "(%a)(%w*)", function(a, b) return string.upper(a) .. b end)
			out[#out + 1] = { kind = "unit", name = (FACTION[e.faction] or "") .. ": " .. name, unit = e.settings }
		end
		return out
	end },
	{ "Statuses", function()
		local out = {}
		for _, n in ipairs(catalog.status_templates()) do out[#out + 1] = { kind = "status", name = catalog.text(n), id = n } end
		return out
	end },
	{ "Helldiver", function() return { { kind = "hero", name = "Helldiver" } } end },
	-- Full presets, by name.
	{ "Presets", function()
		local out = {}
		for n = 1, 50 do
			local text = fgw.storage.get("full." .. n)
			if text then
				local count = 0
				for line in string.gmatch(text, "[^\n]+") do if string.find(line, "|", 1, true) then count = count + 1 end end
				out[#out + 1] = { kind = "preset", n = n, name = string.match(text, "^#name ([^\n]*)") or ("Preset " .. n), count = count }
			end
		end
		return out
	end },
}
local PRESETS_TAB = #TABS

local VERSION = "0.2.0"
local GITHUB = "https://github.com/SHODAN-HORAI/SHODAN-HD1-Editor"
-- Settings page choices: changes off puts the game's values back and keeps yours for when it's on again.
local BACKGROUNDS = { { "Solid", 252 }, { "Dark", 242 }, { "Medium", 210 }, { "Light", 170 } }
local DEFAULTS = { changes = true, bg = 2, hints = true, updates = 1, channel = 1 }

local S = {
	cfg = { changes = true, bg = 2, hints = true, updates = 1, channel = 1, hidden = {} }, settings = false,
	open = false, tab = 1, items = {}, shown = {}, pick = nil, rows = {}, row = 1, list_top = 1, row_top = 1, follow = true,
	search = "", typing = nil, slot = 1, hits = {}, next_hits = {}, hover = nil, keys = {}, dirty = nil, changed = {}, count = 0,
	-- Attachments: unit path -> the upgrade value its weapons use instead of the save's.
	att = {},
}
local kit

local function toast(s) pcall(api.menu.toast, s) end

-- Reading and writing one field.

local function settings_of(unit)
	local lsm = global("LuaSettingsManager")
	if not (lsm and unit) then return nil end
	local ok, sp, st = pcall(function() return lsm:get_settings_path_by_unit_path(unit), lsm:get_settings_by_unit_path(unit) end)
	if ok then return sp, st end
	return nil
end

-- An upgrade's name. Weapon attachments have their own (Penetrator rounds); the game calls a stratagem's
-- only "<stratagem> Mk2", so those are named by what the armory lists them adding: "Mk2: Magazine".
local function upgrade_title(up, i)
	local name = up and up.upgrade_name and catalog.text(up.upgrade_name) or ("Upgrade " .. i)
	local mk = string.match(name, "[Mm][Kk]%s*(%d+)%s*$")
	local attrs = up and type(up.upgrade_attributes) == "table" and up.upgrade_attributes
	if not (mk and attrs) then return name end
	local keys = {}
	for k, v in pairs(attrs) do keys[#keys + 1] = type(k) == "string" and k or tostring(v) end
	table.sort(keys)
	for n, k in ipairs(keys) do
		local t = string.lower(catalog.text(k))
		keys[n] = string.upper(string.sub(t, 1, 1)) .. string.sub(t, 2)
	end
	return #keys > 0 and ("Mk" .. mk .. ": " .. table.concat(keys, ", ")) or name
end

-- A launcher's damage is in the explosion of the projectile it fires, which has its own settings path.
-- Missiles (gameobjects/...) have no settings path, only a table found by unit path, so they're edited
-- as a table kept under "proj:<unit path>". A gun's shot is in weapon_info, an exosuit's missiles in
-- exosuit_info, and an upgrade can swap either for another (incendiary rounds). Each: { key the edits
-- go under, header, item, table }.
local function projectiles_of(st, name, upgrades)
	local out, seen = {}, {}
	local function add(t, suffix)
		for _, src in ipairs({ { "weapon_info", "Projectile" }, { "exosuit_info", "Missiles" } }) do
			local proj = type(t) == "table" and type(t[src[1]]) == "table" and t[src[1]].projectile
			local psp, pst = settings_of(type(proj) == "string" and proj or nil)
			local key = psp or (proj and "proj:" .. proj)
			if pst and pst.explosive_info and not seen[key] then
				seen[key] = true
				local item = psp and { kind = "unit", key = psp, name = name } or { kind = "proj", unit = proj, name = name }
				out[#out + 1] = { key = key, header = src[2] .. suffix, item = item, st = pst }
			end
		end
	end
	add(st, "")
	local info = st and st.upgrade_info
	for i, u in ipairs(type(info) == "table" and info or {}) do
		local up = upgrades and upgrades[i]
		local title = upgrade_title(up, i)
		add(u, " (" .. title .. ")")
	end
	return out
end

local function is_int(v) return type(v) == "number" and v == math.floor(v) end

local function step_of(f, v)
	local span = (f.max or 100) - (f.min or 0)
	if is_int(v) and span >= 10 then return 1 end
	if span <= 2 then return 0.05 end
	if span <= 20 then return 0.1 end
	if span <= 200 then return 1 end
	return 5
end

local function owned(item)
	local ok, map = pcall(api.progress.upgrades)
	return ok and type(map) == "table" and tonumber(map[item.save]) or 0
end

-- The upgrades a unit's weapons use now, by index into its upgrade_info: chosen here, else bought.
local function active_of(item)
	local _, st = settings_of(item.unit)
	local info = item.save and st and st.upgrade_info
	if type(info) ~= "table" then return {} end
	local mask
	if info.type == "bitmask" then mask = S.att[item.unit] or owned(item)
	elseif item.strat then mask = S.att["strat:" .. item.strat] or 2 ^ math.min(owned(item), #info) - 1
	else mask = 2 ^ math.min(S.att[item.unit] or owned(item), #info) - 1 end
	local out = {}
	for i = 1, #info do if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then out[#out + 1] = { i = i, t = info[i] } end end
	return out
end

-- An upgrade replaces a value rather than adding to it, so a row reads and writes the last active
-- upgrade that sets the field: an edit to the base would do nothing while that upgrade is on.
local function source_of(ups, path)
	for n = #ups, 1, -1 do
		if edits.table_value(ups[n].t, path) ~= nil then return ups[n] end
	end
	return nil
end

local function bind(item, f)
	local r = { f = f, label = f.label }
	local opts = { min = f.min, max = f.max, apply = f.apply, target = item.name, new = f.opt }
	if item.kind == "unit" or item.kind == "hero" then
		local sp = item.key
		local function at()
			local up = item.unit and source_of(active_of(item), f.path)
			return up and ("upgrade_info." .. up.i .. "." .. f.path) or f.path
		end
		r.get = function() return edits.value(sp, at()) end
		r.changed = function() return (edits.original(sp, at())) end
		r.reset = function() return edits.revert_where(sp, at()) end
		r.set = function(v) return edits.set_unit(sp, at(), v, opts) end
	elseif item.kind == "proj" then
		local _, t = settings_of(item.unit)
		opts.keep = "proj:" .. item.unit
		r.get = function() return edits.table_value(t, f.path) end
		r.changed = function() return edits.table_changed(t, f.path) end
		r.reset = function() return edits.revert_table(t, f.path) end
		r.set = function(v) return edits.set_table(item.name, t, f.path, v, opts) end
	elseif item.kind == "strat" then
		local s = catalog.stratagem(item.id)
		-- An edit lands in the stratagem and every upgrade that sets the field; this shows what's in use.
		r.get = function()
			local ups, mask = {}, S.att["strat:" .. item.id] or 2 ^ math.min(owned({ save = item.id }), #(s.upgrades or {})) - 1
			for i, u in ipairs(s.upgrades or {}) do if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then ups[#ups + 1] = { t = u } end end
			local up = source_of(ups, f.path)
			return edits.table_value(up and up.t or s, f.path)
		end
		r.changed = function() return edits.table_changed(s, f.path) end
		r.reset = function() return edits.revert_table(s, f.path) end
		r.set = function(v) return api.stratagems.edit(item.id, f.path, v) end
	else
		local t = global("StatusTemplateSettings")[item.id]
		opts.keep = "status:" .. item.id
		r.get = function() return edits.table_value(t, f.path) end
		r.changed = function() return edits.table_changed(t, f.path) end
		r.reset = function() return edits.revert_table(t, f.path) end
		r.set = function(v) return edits.set_table(item.id, t, f.path, v, opts) end
	end
	local v = r.get()
	-- A field the item doesn't have shows only where the API may add it: an absent boolean reads as off.
	if v == nil and not f.opt then return nil end
	if v == nil and f.type ~= "boolean" and item.kind ~= "strat" and item.kind ~= "status" then return nil end
	r.step = step_of(f, v)
	local help = f.meaning and (f.meaning .. ". ") or ""
	if f.min and f.max and f.type ~= "boolean" then help = help .. string.format("From %g to %g. ", f.min, f.max) end
	local up = item.kind == "unit" and item.unit and source_of(active_of(item), f.path)
	if up then help = help .. "Set by " .. upgrade_title(item.upgrades and item.upgrades[up.i] or up.t, up.i) .. ", which is on: this is its value. " end
	r.help = help .. (APPLIES[f.apply] or "")
	return r
end

-- Attachments. The game builds a settings table for every upgrade value of a weapon at load, and each
-- weapon finds its own through LuaSettingsManager:get_modified_settings(unit, upgrade_value). The hook
-- at the end hands it the value chosen here instead, so the save's upgrades stay as they are.

local function set_att(path, value, own)
	if value == own then S.att[path] = nil else S.att[path] = value end
	return true
end

-- Stratagem upgrades (Mk2, Mk3) are levels: the game applies upgrade 1 to n, to the stratagem through
-- LoadoutSettings.get_upgraded_stratagem and to its units (a support weapon, a turret) through
-- get_modified_settings. The choice here is a bitmask kept as att "strat:<name>", and the hooks at the
-- end build the mix it names, so any upgrade can be on or off alone.
local function upgrade_rows(name, names)
	local out, key = {}, "strat:" .. name
	local function own() return 2 ^ math.min(owned({ save = name }), #names) - 1 end
	local function value() return S.att[key] or own() end
	for i = 1, math.min(#names, 4) do
		local bit = 2 ^ (i - 1)
		local function has(m) return math.floor(m / bit) % 2 == 1 end
		local up = names[i] or {}
		local title = upgrade_title(up, i)
		local r = { label = title, f = { type = "boolean", apply = "reload", label = title }, step = 1 }
		r.get = function() return has(value()) end
		r.changed = function() return has(value()) ~= has(own()) end
		r.set = function(on)
			local m = value()
			if has(m) ~= on then m = on and m + bit or m - bit end
			return set_att(key, m, own())
		end
		r.reset = function() return r.set(has(own())) end
		local about = up.upgrade_description and catalog.text(up.upgrade_description) or ""
		if about ~= "" then about = (string.find(about, "[%.!?]%s*$") and about or about .. ".") .. " " end
		r.help = about .. (has(own()) and "Bought in the armory." or "Not bought in the armory.") .. " Weapons: at once. The stratagem itself: next mission or respawn."
		out[#out + 1] = r
	end
	return out
end

local function attachment_rows(item, info)
	local path, out, names = item.unit, {}, item.upgrades or {}
	local function value() return S.att[path] or owned(item) end
	if info.type == "bitmask" then
		-- The game's limit is 15: four upgrades.
		for i = 1, math.min(#info, 4) do
			local bit = 2 ^ (i - 1)
			local function has(m) return math.floor(m / bit) % 2 == 1 end
			local up = names[i] or {}
			local title = upgrade_title(up, i)
			local r = { label = title, f = { type = "boolean", apply = "reload", label = title }, step = 1 }
			r.get = function() return has(value()) end
			r.changed = function() return has(value()) ~= has(owned(item)) end
			r.set = function(on)
				local m = value()
				if has(m) ~= on then m = on and m + bit or m - bit end
				return set_att(path, m, owned(item))
			end
			r.reset = function() return r.set(has(owned(item))) end
			local about = up.upgrade_description and catalog.text(up.upgrade_description) or ""
			if about ~= "" then about = (string.find(about, "[%.!?]%s*$") and about or about .. ".") .. " " end
			r.help = about .. (has(owned(item)) and "Bought in the armory." or "Not bought in the armory.") .. " Applies at once."
			out[#out + 1] = r
		end
	elseif item.strat then
		-- A level kept by the old Upgrade level row becomes the same upgrades, on the toggles.
		local key = "strat:" .. item.strat
		if S.att[path] and not S.att[key] then S.att[key] = 2 ^ math.min(S.att[path], #names) - 1 end
		S.att[path] = nil
		return upgrade_rows(item.strat, names)
	else
		local top = math.min(#info, 15)
		local r = { label = "Upgrade level", f = { type = "number", min = 0, max = top, apply = "reload", label = "Upgrade level" }, step = 1 }
		r.get = function() return value() end
		r.changed = function() return S.att[path] ~= nil end
		r.set = function(v) return set_att(path, v, owned(item)) end
		r.reset = function() S.att[path] = nil end
		r.help = string.format("From 0 to %d. Bought in the armory: %d. Applies at once.", top, owned(item))
		out[#out + 1] = r
	end
	return out
end

-- The status effects a settings table and its projectiles apply, by template name.
local function status_ids(st, projs)
	local out, seen = {}, {}
	local t = global("StatusTemplateSettings")
	local sources = { st }
	for _, p in ipairs(projs or {}) do sources[#sources + 1] = p.st end
	for _, src in ipairs(sources) do
		for _, part in ipairs({ "weapon_info", "explosive_info", "melee_info" }) do
			local list = type(src) == "table" and type(src[part]) == "table" and src[part].hit_status_effects
			for _, id in ipairs(type(list) == "table" and list or {}) do
				if type(id) == "string" and not seen[id] and t and t[id] then seen[id] = true out[#out + 1] = id end
			end
		end
	end
	return out
end

-- The key a section's values are kept under, the same for every item that reaches them.
local function key_of(owner)
	if owner.kind == "unit" then return owner.key end
	if owner.kind == "proj" then return "proj:" .. owner.unit end
	if owner.kind == "status" then return "status:" .. owner.id end
	return nil
end

-- Which items reach each key (their own settings, their shots, their effects), over every tab of
-- units. Built once the game has loaded them, like SSEO's 'shared with' notes.
local share
local function share_names(key, own)
	if not key then return nil end
	if not share then
		local index, any = {}, false
		local function add(k, name)
			index[k] = index[k] or {}
			for _, n in ipairs(index[k]) do if n == name then return end end
			index[k][#index[k] + 1] = name
		end
		for i, tab in ipairs(TABS) do
			local ok, list = pcall(tab[2])
			for _, it in ipairs(ok and type(list) == "table" and list or {}) do
				if it.kind == "unit" then
					local sp, st = settings_of(it.unit)
					if sp and st then
						any = true
						add(sp, it.name)
						local projs = projectiles_of(st, it.name, it.upgrades)
						for _, p in ipairs(projs) do add(p.key, it.name) end
						for _, id in ipairs(status_ids(st, projs)) do add("status:" .. id, it.name) end
					end
				end
			end
		end
		if not any then return nil end
		share = index
	end
	local out = {}
	for _, n in ipairs(share[key] or {}) do if n ~= own then out[#out + 1] = n end end
	return #out > 0 and out or nil
end

-- Every row of an item: family headers, then its fields. nil when the game hasn't loaded its data here.
local function rows_of(item)
	if item.kind == "preset" then return {} end
	local out = {}
	local function family(name, fields, owner)
		local start = #out
		out[#out + 1] = { header = FAMILY[name] or name, share = share_names(key_of(owner or item), item.name) }
		for _, f in ipairs(fields) do out[#out + 1] = bind(owner or item, f) end
		if #out == start + 1 then out[#out] = nil end
	end
	if item.kind == "unit" then
		local _, st = settings_of(item.unit)
		if not (st and item.key) then return nil end
		local info = st.upgrade_info
		if item.save and type(info) == "table" and #info > 0 then
			out[#out + 1] = { header = "Attachments" }
			for _, r in ipairs(attachment_rows(item, info)) do out[#out + 1] = r end
		end
		for _, name in ipairs(catalog.families_of(st)) do family(name, fields_of(name)) end
		local projs = projectiles_of(st, item.name, item.upgrades)
		for _, p in ipairs(projs) do family(p.header, fields_of("explosive"), p.item) end
		-- Status effects are one table per effect, shared by everything that applies it: the game tracks
		-- them in a fixed list, so a weapon can't have its own copy.
		for _, id in ipairs(status_ids(st, projs)) do
			local shared = {}
			for _, f in ipairs(catalog.fields("status")) do
				local c = {}
				for k, v in pairs(f) do c[k] = v end
				c.meaning = "Shared: changes this effect for everything that applies it" .. (f.meaning and (". " .. f.meaning) or "")
				shared[#shared + 1] = c
			end
			local name = catalog.text(id)
			family("Effect: " .. name, shared, { kind = "status", id = id, name = name })
		end
	elseif item.kind == "hero" then
		if edits.value(HELLDIVER, "health_info.health") == nil then return nil end
		family("character", CHARACTER)
	elseif item.kind == "strat" then
		local strat = catalog.stratagem(item.id)
		if not strat then return nil end
		if type(strat.upgrades) == "table" and #strat.upgrades > 0 then
			out[#out + 1] = { header = "Upgrades" }
			for _, r in ipairs(upgrade_rows(item.id, strat.upgrades)) do out[#out + 1] = r end
		end
		family("stratagem", catalog.fields("stratagem"))
	else
		local t = global("StatusTemplateSettings")
		if not (t and t[item.id]) then return nil end
		family("status", catalog.fields("status"))
	end
	return out
end

local function show(v)
	if type(v) == "boolean" then return v and "On" or "Off" end
	if type(v) == "string" then return v end
	if type(v) ~= "number" then return "-" end
	return string.format("%.6g", v)
end

local function off_note()
	if S.cfg.changes then return false end
	toast("Your changes are off: turn them on in Settings to edit")
	return true
end

local function write(r, v)
	if not r.setting and off_note() then return end
	-- Back to the game's own value: that's no change, so it's undone rather than kept as an edit.
	if not r.setting and r.changed() then
		r.reset()
		if r.get() == v then
			if r.f.apply == "reload" then pcall(api.gear.refresh) end
			S.dirty = SAVE_AFTER
			return
		end
	end
	local ok, why = r.set(v)
	if not ok then return toast("Not changed: " .. tostring(why)) end
	-- Weapons in hand keep copies of some stats: this pushes the change into them. A weapon on an
	-- upgrade mix holds a copy of everything, so with one about every change does.
	local mixed = false
	for k in pairs(S.att) do mixed = mixed or string.find(k, "^strat:") ~= nil end
	if r.f.apply == "reload" or mixed then pcall(api.gear.refresh) end
	S.dirty = SAVE_AFTER
end

local function change(r, d, big)
	if not (r and r.f) or r.f.type == "action" then return end
	local v = r.get()
	if r.f.type == "boolean" then return write(r, v ~= true) end
	if r.f.choices then return write(r, (v - 1 + d) % #r.f.choices + 1) end
	if type(v) ~= "number" then v = 0 end
	local n = tonumber(string.format("%.6g", v + r.step * (big and 10 or 1) * d))
	if r.f.min and n < r.f.min then n = r.f.min end
	if r.f.max and n > r.f.max then n = r.f.max end
	write(r, n)
end

local function reset(r)
	if r and r.f and r.changed() then
		if not r.setting and off_note() then return end
		r.reset()
		S.dirty = SAVE_AFTER
	end
end

-- Kept edits and presets.

local function encode()
	-- shortcut: every edit in the game is taken as ours; fine while no other enabled mod makes edits.
	local lines = {}
	for _, e in ipairs(edits.list()) do
		local where = e.settings_path or e.keep
		if where then lines[#lines + 1] = table.concat({ where, e.path, type(e.value), tostring(e.value) }, "|") end
	end
	for path, value in pairs(S.att) do lines[#lines + 1] = "att|" .. path .. "|number|" .. value end
	return table.concat(lines, "\n")
end

local function restore(where, path, value)
	if where == "att" then
		if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 15 then return false, "bad_value" end
		S.att[path] = value
		return true
	end
	local kind, name = string.match(where, "^(%a+):(.+)$")
	if kind == "stratagem" then return api.stratagems.edit(name, path, value) end
	if kind == "proj" then
		local _, t = settings_of(name)
		if not t then return false, "no_target" end
		return edits.set_table(name, t, path, value, { keep = where, new = true })
	end
	if kind == "status" then
		local t = global("StatusTemplateSettings")[name]
		if not t then return false, "no_target" end
		return edits.set_table(name, t, path, value, { keep = where, new = true })
	end
	return edits.set_unit(where, path, value, { target = where, new = true })
end

local function apply_text(text)
	local n = 0
	for line in string.gmatch(text or "", "[^\n]+") do
		local where, path, kind, value = string.match(line, "^([^|]+)|([^|]+)|([^|]+)|(.*)$")
		if where then
			if kind == "number" then value = tonumber(value) elseif kind == "boolean" then value = value == "true" end
			local ok, why = restore(where, path, value)
			if ok then n = n + 1 else fgw.log("kept edit not applied (" .. tostring(why) .. "): " .. where .. " " .. path) end
		end
	end
	return n
end

local function save_current()
	S.dirty = nil
	-- Off, the game holds none of them: what's kept stays.
	if S.cfg.changes then fgw.storage.set("current", encode()) end
end

-- Full presets (the Presets tab): up to 50, each "#name <name>" and then every change, as "full.<n>".
-- Item presets: 5 per item, its own changes only, as "item.<item key>.<n>".

local FULL_MAX = 50
local storage = fgw.storage
local function full_key(n) return "full." .. n end
local function full_name(text) return text and string.match(text, "^#name ([^\n]*)") end
local function full_body(text) return (string.gsub(text, "^#name [^\n]*\n?", "")) end
local function count_lines(text)
	local n = 0
	for line in string.gmatch(text or "", "[^\n]+") do if string.find(line, "|", 1, true) then n = n + 1 end end
	return n
end

local function full_load(n)
	local text = storage.get(full_key(n))
	if not text or off_note() then return end
	edits.revert_all()
	S.att = {}
	local k = apply_text(text)
	storage.set("preset", n)
	save_current()
	pcall(api.gear.refresh)
	toast("Loaded " .. (full_name(text) or "preset") .. ": " .. k .. " value(s)")
end

local function full_save(n)
	local name = full_name(storage.get(full_key(n))) or ("Preset " .. n)
	storage.set(full_key(n), "#name " .. name .. "\n" .. encode())
	storage.set("preset", n)
	toast("Saved " .. name)
end

local function full_delete(n)
	storage.set(full_key(n), nil)
	if storage.get("preset") == n then storage.set("preset", nil) end
end

local function full_new()
	for n = 1, FULL_MAX do
		if not storage.get(full_key(n)) then
			storage.set(full_key(n), "#name Preset " .. n .. "\n" .. encode())
			storage.set("preset", n)
			return n
		end
	end
	toast("All " .. FULL_MAX .. " presets are in use")
end

local function full_rename(n, name)
	name = string.match(string.gsub(name, "[\r\n|]", " "), "^%s*(.-)%s*$")
	local text = storage.get(full_key(n))
	if name == "" or not text then return end
	storage.set(full_key(n), "#name " .. name .. "\n" .. full_body(text))
end

-- The old five presets (0.3.0 and before) become the first full presets.
for n = 1, 5 do
	local text = storage.get("preset." .. n)
	if text then
		if not storage.get(full_key(n)) then storage.set(full_key(n), "#name Preset " .. n .. "\n" .. text) end
		storage.set("preset." .. n, nil)
	end
end

local function item_key(item, n) return "item." .. tostring(item.key) .. "." .. n end

-- The kept lines that belong to one item: its own fields and its attachments.
local function item_lines(item)
	local out = {}
	for line in string.gmatch(encode(), "[^\n]+") do
		local where, path = string.match(line, "^([^|]+)|([^|]+)|")
		if where == item.key or (item.projs and item.projs[where]) or (where == "att" and (path == item.unit or path == "strat:" .. tostring(item.strat or item.kind == "strat" and item.id))) then out[#out + 1] = line end
	end
	return table.concat(out, "\n")
end

local function item_save(item)
	storage.set(item_key(item, S.slot), item_lines(item))
	toast("Saved " .. item.name .. " preset " .. S.slot)
end

local function item_load(item)
	local text = storage.get(item_key(item, S.slot))
	if not text then return toast(item.name .. " preset " .. S.slot .. " is empty") end
	if off_note() then return end
	-- Everything the preset doesn't name goes back to the game's.
	for _, r in ipairs(S.rows) do if r.f and r.changed() then r.reset() end end
	local k = apply_text(text)
	S.dirty = SAVE_AFTER
	pcall(api.gear.refresh)
	toast("Loaded " .. item.name .. " preset " .. S.slot .. ": " .. k .. " value(s)")
end

local function item_clear(item)
	storage.set(item_key(item, S.slot), nil)
	toast("Cleared " .. item.name .. " preset " .. S.slot)
end

local function reset_item()
	if not S.settings and off_note() then return end
	for _, r in ipairs(S.rows) do reset(r) end
end

local function reset_all()
	if off_note() then return end
	edits.revert_all()
	S.att = {}
	S.dirty = SAVE_AFTER
	pcall(api.gear.refresh)
	toast("Every value is back to the game's")
end

-- Lists.

local function first_row(from, d)
	local i = from
	while S.rows[i] and S.rows[i].header do i = i + d end
	return S.rows[i] and i or nil
end

local function pick(item)
	S.pick, S.confirm = item, nil
	S.rows = item and rows_of(item) or {}
	S.row = first_row(1, 1) or 1
	S.row_top, S.follow = 1, true
end

local function filter()
	local out, want = {}, string.lower(S.search)
	for _, it in ipairs(S.items) do
		if want == "" or string.find(string.lower(it.name), want, 1, true) then out[#out + 1] = it end
	end
	S.shown = out
	local still = false
	for _, it in ipairs(out) do still = still or it == S.pick end
	if not still then pick(out[1]) end
	S.list_top = 1
end

local function load_tab(n)
	local ok, list = pcall(TABS[n][2])
	S.items = ok and list or {}
	for _, it in ipairs(S.items) do
		if it.kind == "unit" then
			local st
			it.key, st = settings_of(it.unit)
			it.projs = {}
			for _, p in ipairs(projectiles_of(st)) do it.projs[p.key] = true end
		elseif it.kind == "hero" then it.key = HELLDIVER
		elseif it.kind == "preset" then it.key = nil
		elseif it.kind == "strat" then it.key = "stratagem:" .. it.id
		else it.key = "status:" .. it.id end
	end
	if n ~= S.tab then S.search = "" end
	S.tab, S.pick, S.settings = n, nil, false
	if n == PRESETS_TAB then S.names = nil end
	filter()
end

-- Settings, kept as lines of "name=value".

-- Updates, as in SHODAN Stat Editor: ask or install by themselves, from tested releases or every commit.
local UPDATES = { { "ask", "Ask" }, { "auto", "Automatic" } }
local CHANNELS = { { "releases", "Releases" }, { "commits", "Every commit" } }
local function check_updates()
	local u = fgw.update
	if u then pcall(u.check, VERSION, CHANNELS[S.cfg.channel][1], UPDATES[S.cfg.updates][1]) end
end

local function save_settings()
	local hide = {}
	for name in pairs(S.cfg.hidden) do hide[#hide + 1] = name end
	table.sort(hide)
	fgw.storage.set("settings", table.concat({ "changes=" .. (S.cfg.changes and 1 or 0), "bg=" .. S.cfg.bg,
		"hints=" .. (S.cfg.hints and 1 or 0), "updates=" .. UPDATES[S.cfg.updates][1], "channel=" .. CHANNELS[S.cfg.channel][1],
		"hide=" .. table.concat(hide, ",") }, "\n"))
end

local function load_settings()
	local text = fgw.storage.get("settings")
	if type(text) ~= "string" then return end
	for k, v in string.gmatch(text, "(%w+)=([^\n]*)") do
		if k == "changes" then S.cfg.changes = v ~= "0"
		elseif k == "hints" then S.cfg.hints = v ~= "0"
		elseif k == "bg" then S.cfg.bg = BACKGROUNDS[tonumber(v)] and tonumber(v) or DEFAULTS.bg
		elseif k == "updates" then S.cfg.updates = v == "auto" and 2 or 1
		elseif k == "channel" then S.cfg.channel = v == "commits" and 2 or 1
		elseif k == "hide" then for name in string.gmatch(v, "[^,]+") do S.cfg.hidden[name] = true end end
	end
end

-- The first shown tab from `from` on, stepping d (0: `from` itself if shown).
local function shown_tab(from, d)
	for k = 0, #TABS - 1 do
		local i = (from - 1 + (d == 0 and k or d * (k + 1))) % #TABS + 1
		-- Presets isn't a tab on the bar: it has its own button by Settings.
		if i ~= PRESETS_TAB and not S.cfg.hidden[TABS[i][1]] then return i end
	end
	return 1
end

local function set_changes(on)
	if on == S.cfg.changes then return end
	if on then
		S.cfg.changes = true
		apply_text(fgw.storage.get("current"))
	else
		save_current()
		S.cfg.changes = false
		edits.revert_all()
		S.att = {}
	end
	pcall(api.gear.refresh)
end

local function setting(label, help, f, get, set, default)
	f.label = label
	local r = { setting = true, label = label, help = help, f = f, step = 1, get = get }
	r.set = function(v)
		set(v)
		save_settings()
		return true
	end
	r.changed = function() return get() ~= default end
	r.reset = function() r.set(default) end
	return r
end

-- The key that opens the window: any keyboard key, caught by "Change" then a press. Kept as the
-- game's own key name ("f7"), which the runtime's keybind reads from storage.
local function open_key_name() return fgw.storage.get("key.open", "f7") end
local function key_label(name) return (name:gsub("(%a)(%w*)", function(a, r) return a:upper() .. r end)) end

-- The key pressed this frame, by the game's name for it. Esc is left out: it cancels.
local function pressed_key()
	local kb = global("Keyboard")
	local n = kb.num_buttons and kb.num_buttons() or 256
	for i = 0, n - 1 do
		local ok, down = pcall(kb.pressed, i)
		if ok and down == true then
			local ok2, name = pcall(kb.button_name, i)
			if ok2 and type(name) == "string" and name ~= "" then return name end
		end
	end
end

local function read_capture()
	local name = pressed_key()
	if not name then return end
	S.capture = nil
	if name == "esc" or name == "escape" then return toast("Open key not changed") end
	-- Written a frame later, so this same press doesn't also close the window.
	S.capture_set = name
end

local function settings_rows()
	local names = {}
	for i, b in ipairs(BACKGROUNDS) do names[i] = b[1] end
	local out = {
		{ header = "Changes" },
		setting("Your changes", "Off puts every value back to the game's and keeps yours for when you turn them on again.",
			{ type = "boolean" }, function() return S.cfg.changes end, set_changes, DEFAULTS.changes),
		{ header = "Window" },
		setting("Background", "How much of the game shows through the window.", { type = "choice", choices = names },
			function() return S.cfg.bg end, function(v) S.cfg.bg = v end, DEFAULTS.bg),
		setting("Key hints", "The line of keys at the bottom of the window.", { type = "boolean" },
			function() return S.cfg.hints end, function(v) S.cfg.hints = v end, DEFAULTS.hints),
	}
	-- Under Obsidian Mod Manager (no fgw.update) the open key and the updates are Obsidian's own.
	if fgw.update then
		local own = {
		{ label = "Open key", note = function() return S.capture and "Press a key (Esc: cancel)" or key_label(open_key_name()) end,
			help = "The key that opens and closes this window. Click Change, then press any key.",
			f = { type = "action", label = "Open key" }, setting = true, get = function() end, changed = function() return open_key_name() ~= "f7" end,
			reset = function() fgw.storage.set("key.open", "f7") end,
			buttons = { { "Change", function() S.capture = true end }, { "F7", function() fgw.storage.set("key.open", "f7") end } } },
		{ header = "Updates" },
		setting("Updates", "Ask: an Update button shows at the top when there's a new version. Automatic: it downloads by itself. Either way it goes in when you close the game.",
			{ type = "choice", choices = { "Ask", "Automatic" }, buttons = true }, function() return S.cfg.updates end,
			function(v)
				S.cfg.updates = v
				if fgw.update then pcall(fgw.update.set_mode, UPDATES[v][1]) end
			end, DEFAULTS.updates),
		setting("Update channel", "Releases: tested versions only. Every commit: every change as soon as it's pushed, before testing, so it may break.",
			{ type = "choice", choices = { "Releases", "Every commit" }, buttons = true }, function() return S.cfg.channel end,
			function(v)
				if v == S.cfg.channel then return end
				S.cfg.channel = v
				check_updates()
			end, DEFAULTS.channel),
		}
		for _, row in ipairs(own) do out[#out + 1] = row end
	end
	out[#out + 1] = { header = "Tabs" }
	for i, tab in ipairs(TABS) do
		local name = tab[1]
		if i ~= PRESETS_TAB then out[#out + 1] = setting(name, "Shows the " .. name .. " tab.", { type = "boolean" },
			function() return not S.cfg.hidden[name] end,
			function(on)
				if not on then
					local left = 0
					for k, t in ipairs(TABS) do if k ~= PRESETS_TAB and not S.cfg.hidden[t[1]] then left = left + 1 end end
					if left <= 1 then return toast("One tab has to stay") end
				end
				S.cfg.hidden[name] = (not on) or nil
			end, true) end
	end
	-- About, as SSEO's Settings has it: version, author, links.
	local function about(label, note, help, buttons)
		out[#out + 1] = { label = label, note = note, help = help, f = { type = "action", label = label }, buttons = buttons,
			get = function() end, changed = function() return false end, reset = function() end, setting = true }
	end
	local function copy(s)
		if pcall(global("InputManager").set_clipboard_text, global("InputManager"), s) then toast("Copied") end
	end
	local function open(s)
		if not (fgw.open and fgw.open(s)) then toast("Couldn't open it") end
	end
	out[#out + 1] = { header = "About" }
	about("SHODAN HD1 Editor " .. VERSION, "Made by SHODAN", "Thanks for using it.", {})
	about("GitHub", (GITHUB:gsub("^https://", "")), "Updates, the source, and where to report a problem.",
		fgw.open and { { "Open", function() open(GITHUB) end }, { "Copy", function() copy(GITHUB) end } } or { { "Copy", function() copy(GITHUB) end } })
	local folder = fgw.folder and (fgw.folder:gsub("\\$", ""))
	if folder then
		about("Editor folder", folder, "Your kept changes, presets, settings and the log.",
			{ { "Open", function() open(folder) end }, { "Copy", function() copy(folder) end } })
	end
	return out
end

-- The Presets tab again, on preset n.
local function show_presets(n)
	load_tab(PRESETS_TAB)
	for _, it in ipairs(S.shown) do if it.n == n then pick(it) end end
end

local function toggle_settings()
	if S.settings then return load_tab(S.tab == PRESETS_TAB and PRESETS_TAB or shown_tab(S.tab, 0)) end
	S.settings, S.typing, S.confirm = true, nil, nil
	S.pick = { kind = "settings", name = "Settings (version " .. VERSION .. ")" }
	S.rows = settings_rows()
	S.row = first_row(1, 1)
	S.row_top, S.follow = 1, true
end

local function step_item(d)
	for i, it in ipairs(S.shown) do
		if it == S.pick then
			local nxt = S.shown[i + d]
			if nxt then
				pick(nxt)
				if i + d < S.list_top then S.list_top = i + d end
				if S.list_rows and i + d >= S.list_top + S.list_rows then S.list_top = i + d - S.list_rows + 1 end
			end
			return
		end
	end
end

-- Input: our own controller interface holds the
-- focus, the system cursor shows, and the keyboard and the mouse are read raw.

local function users()
	local out = { global("KEYBOARD_MOUSE_USER_NAME") }
	local pads = global("PadManager")
	for _, u in ipairs(pads and pads.users or {}) do out[#out + 1] = u.name end
	return out
end

local function hold_focus()
	local im, keyboard = global("InputManager"), global("KEYBOARD_MOUSE_USER_NAME")
	if not im:has_interface(keyboard, IFACE) then
		im:create_controller_interface(keyboard, IFACE, {}, {})
		global("PadManager"):create_rebindable_interface(IFACE, global("ControllerSettings").pad)
	end
	for _, u in ipairs(users()) do im:take_focus(u, IFACE) end
end

local function drop_focus()
	local im = global("InputManager")
	for _, u in ipairs(users()) do
		if im:has_interface(u, IFACE) then im:release_focus(u, IFACE) end
	end
end

local function state_name()
	local boot = global("Boot")
	local sm = type(boot) == "table" and boot.state_machine
	if not sm then return nil end
	local ok, name = pcall(sm.get_current_state_name, sm)
	return ok and name or nil
end

-- The path has to be a string: with none the engine reads through a null, past any pcall.
local function show_cursor()
	local cursors = global("CursorManager")
	cursors:set_cursor(CURSOR)
	cursors:set_show_cursor(true)
	cursors:set_clip_cursor(false)
	pcall(global("Window").set_cursor, "")
end

local function close()
	if not S.open then return end
	S.open, S.typing = false, nil
	pcall(drop_focus)
	pcall(function()
		local c, cursors = S.cursor, global("CursorManager")
		if not c then return end
		local same = c.state == state_name()
		local name, shown = c.name, c.shown
		if not same then name, shown = cursors:get_current_cursor(), cursors:is_shown() end
		cursors:set_cursor(name)
		cursors:set_show_cursor(shown)
		if same then cursors:set_clip_cursor(name ~= CURSOR) end
	end)
	S.cursor = nil
	if S.dirty then save_current() end
end

local function open()
	local name = state_name()
	if not name or CLOSED_STATES[name] then return end
	local ok, why = pcall(hold_focus)
	if not ok then
		fgw.log("could not take input: " .. tostring(why))
		pcall(drop_focus)
		return
	end
	pcall(function()
		local cursors = global("CursorManager")
		S.cursor = { name = cursors:get_current_cursor(), shown = cursors:is_shown(), state = name }
		show_cursor()
	end)
	S.open, S.state = true, name
	load_tab(shown_tab(S.tab, 0))
end

local KEYS = {
	up = { "up" }, down = { "down" }, left = { "left" }, right = { "right" }, enter = { "enter", "numpad enter" },
	esc = { "esc" }, tab = { "tab" }, pgup = { "page up" }, pgdn = { "page down" }, del = { "delete" },
}
local REPEATS = { up = true, down = true, left = true, right = true, pgup = true, pgdn = true }

local function key(name, dt)
	local kb = global("Keyboard")
	local st = S.keys[name]
	if not st then
		st = { index = {}, wait = 0 }
		S.keys[name] = st
		for _, k in ipairs(KEYS[name]) do
			local ok, i = pcall(kb.button_index, k)
			if ok and i then st.index[#st.index + 1] = i end
		end
	end
	local pressed, held = false, false
	for _, i in ipairs(st.index) do
		pressed = pressed or kb.pressed(i) == true
		local level = kb.button(i)
		held = held or (type(level) == "number" and level > 0.5)
	end
	if pressed then
		st.wait = FIRST_REPEAT
		return true
	end
	if held and REPEATS[name] then
		st.wait = st.wait - dt
		if st.wait <= 0 then
			st.wait = NEXT_REPEAT
			return true
		end
	end
	return false
end

local function shift()
	local kb = global("Keyboard")
	for _, k in ipairs({ "left shift", "right shift" }) do
		local ok, i = pcall(kb.button_index, k)
		if ok and i and (kb.button(i) or 0) > 0.5 then return true end
	end
	return false
end

-- blank: a new preset's name box starts empty (left empty, it keeps "Preset n").
local function begin_typing(mode, r, blank)
	if not global("GuiItems") then return end
	local start = blank and "" or mode == "search" and S.search or mode == "name" and r.name or ""
	S.typing = { mode = mode, row = r, text = start, state = {} }
end

local function finish_typing(t)
	if t.mode == "name" then
		full_rename(t.row.n, t.text)
		return show_presets(t.row.n)
	end
	if t.mode == "number" then
		local n = tonumber(t.text)
		local f = t.row.f
		if not n then return end
		if f.min and n < f.min then n = f.min end
		if f.max and n > f.max then n = f.max end
		write(t.row, n)
	end
end

local function read_typing()
	local t = S.typing
	local before = t.text
	local text, _, finished, cancelled = global("GuiItems").InputField.do_input(t.text, t.state, t.mode == "number" and 16 or t.mode == "name" and 32 or 24)
	t.text = text or ""
	if t.mode == "number" then
		t.text = (string.gsub(t.text, "[^%d%.%-]", ""))
		if type(t.state.marker) == "number" and t.state.marker > #t.text + 1 then t.state.marker = #t.text + 1 end  -- #text + 1: after the last letter
	elseif t.mode == "search" and t.text ~= before then
		S.search = t.text
		filter()
	end
	if finished then
		S.typing = nil
		if not cancelled then finish_typing(t) end
	end
end

local function move_row(d)
	local i = first_row(S.row + d, d)
	if i then S.row, S.follow = i, true end
end

local function keys(dt)
	local r = S.rows[S.row]
	if key("esc", dt) then return close() end
	if key("up", dt) then move_row(-1) end
	if key("down", dt) then move_row(1) end
	if key("left", dt) then change(r, -1, shift()) end
	if key("right", dt) then change(r, 1, shift()) end
	if key("pgup", dt) then step_item(-1) end
	if key("pgdn", dt) then step_item(1) end
	if key("del", dt) then reset(r) end
	if key("enter", dt) and r and r.f and r.f.type ~= "boolean" and r.f.type ~= "action" and not r.f.choices then begin_typing("number", r) end
	if key("tab", dt) then load_tab(shown_tab(S.tab, shift() and -1 or 1)) end
end

local function read_mouse()
	local mouse = global("Mouse")
	if not mouse or S.no_mouse then return nil end
	local ok, m = pcall(function()
		local ids = S.mouse_ids
		if not ids then
			ids = { cursor = mouse.axis_index("cursor"), wheel = mouse.axis_index("wheel"), left = mouse.button_index("left") }
			S.mouse_ids = ids
		end
		local at, wheel = mouse.axis(ids.cursor), mouse.axis(ids.wheel)
		local x, y = kit:point(at.x, at.y)
		return { x = x, y = H - y, wheel = wheel.y, left = mouse.pressed(ids.left) == true }
	end)
	if ok then return m end
	S.no_mouse = true
	fgw.log("no mouse: " .. tostring(m))
	return nil
end

local function under(m)
	for i = #S.hits, 1, -1 do
		local b = S.hits[i]
		if m.x >= b.x and m.x < b.x + b.w and m.y >= b.y and m.y < b.y + b.h then return b end
	end
	return nil
end

local function mouse()
	local m = read_mouse()
	if not m then return end
	local b = under(m)
	S.hover = b and b.id
	if m.wheel ~= 0 then
		local d = m.wheel > 0 and -3 or 3
		if not S.settings and m.x < WX + PAD + LIST_W + 6 then S.list_top = S.list_top + d else S.row_top, S.follow = S.row_top + d, false end
	end
	if m.left then
		if S.typing then
			local t = S.typing
			S.typing = nil
			finish_typing(t)
		end
		-- A click anywhere else takes a reset's "Sure?" back.
		local c = S.confirm
		if c and not c.n and not (b and b.id == c.kind) then S.confirm = nil end
		if b and b.fn then b.fn() end
	end
end

-- Drawing, in a 1280 by 720 design space with y going down from the top. The kit's y goes up.

local function rect(x, y, w, h, c, z)
	kit:layer(z or 821)
	kit:rect(x, H - y - h, w, h, c)
end

local function outline(x, y, w, h, c, z)
	rect(x, y, w, 1, c, z or 822)
	rect(x, y + h - 1, w, 1, c, z or 822)
	rect(x, y, 1, h, c, z or 822)
	rect(x + w - 1, y, 1, h, c, z or 822)
end

-- cy: the line's middle.
local function text(s, x, cy, size, c, align, font, z)
	kit:layer(z or 824)
	kit:text(s, x, H - (cy + size * 0.33), { font = font or "ui", size = size, color = c, align = align })
end

local function width(s, size, font)
	local w = kit:measure(s, { font = font or "ui", size = size })
	return w or 0
end

-- What's being typed, with the line under the letter the arrow keys are on (after the last one at the end).
local function typed(x, cy, size, align)
	local t = S.typing.text
	local m = type(S.typing.state.marker) == "number" and S.typing.state.marker or #t + 1
	local left = align == "right" and x - width(t .. "_", size) or x
	text(t, left, cy, size, WHITE)
	text("_", left + width(string.sub(t, 1, m - 1), size), cy, size, WHITE)
end

-- Words into lines no wider than maxw.
local function wrap(s, size, maxw)
	local lines, line = {}, ""
	for word in string.gmatch(s, "%S+") do
		local try = line == "" and word or line .. " " .. word
		if line ~= "" and width(try, size) > maxw then
			lines[#lines + 1], line = line, word
		else
			line = try
		end
	end
	if line ~= "" then lines[#lines + 1] = line end
	return lines
end

local function clip(x, y, w, h, fn)
	kit:clip(x, H - y - h, w, h, fn)
end

local function hit(id, x, y, w, h, fn)
	S.next_hits[#S.next_hits + 1] = { id = id, x = x, y = y, w = w, h = h, fn = fn }
end

local function button(id, label, x, y, w, h, fn, active, ink)
	local hot = S.hover == id
	rect(x, y, w, h, active and PICKED or hot and HOT or BOX)
	outline(x, y, w, h, (active or hot) and GOLD or LINE)
	text(label, x + w / 2, y + h / 2, 14, ink or WHITE, "center")
	hit(id, x, y, w, h, fn)
end

local function scrollbar(x, y, h, top, shown, total)
	if total <= shown then return end
	rect(x, y, 5, h, BOX)
	local th = math.max(16, h * shown / total)
	rect(x, y + (h - th) * (top - 1) / (total - shown), 5, th, THUMB, 822)
end

local function draw_list(x, y, w, h)
	local list_h = h - 32
	local n = math.floor(list_h / ROW_H)
	S.list_rows = n
	S.list_top = math.max(1, math.min(S.list_top, #S.shown - n + 1))
	clip(x, y, w - 8, list_h, function()
		for i = S.list_top, math.min(#S.shown, S.list_top + n - 1) do
			local it = S.shown[i]
			local ry = y + (i - S.list_top) * ROW_H
			local id = "item" .. i
			if it == S.pick then rect(x, ry, w - 8, ROW_H - 1, PICKED)
			elseif S.hover == id then rect(x, ry, w - 8, ROW_H - 1, HOVER) end
			local edited = it.key and S.changed[it.key]
			for k in pairs(it.projs or {}) do edited = edited or S.changed[k] end
			text((edited and "* " or "") .. it.name, x + 6, ry + ROW_H / 2, 15, edited and GOLD or WHITE)
			if it.count then text(it.count .. " value(s)", x + w - 16, ry + ROW_H / 2, 13, MUTED, "right") end
			hit(id, x, ry, w - 8, ROW_H - 1, function() pick(it) end)
		end
	end)
	scrollbar(x + w - 5, y, list_h, S.list_top, n, #S.shown)
	if S.tab == PRESETS_TAB then
		if #S.shown == 0 then text("No presets yet.", x + 6, y + ROW_H / 2, 15, DIM) end
		button("newpreset", "+ New preset from current changes", x, y + h - 26, w, 26, function()
			local n = full_new()
			if n then
				show_presets(n)
				begin_typing("name", S.pick, true)
			end
		end)
		return
	end
	if #S.shown == 0 then text(#S.items == 0 and "Nothing here on this screen" or "No match", x + 6, y + ROW_H / 2, 15, DIM) end
	-- The search box.
	local sy, typing = y + h - 26, S.typing and S.typing.mode == "search"
	rect(x, sy, w - 36, 26, typing and SUNK or S.hover == "search" and HOT or BOX)
	outline(x, sy, w - 36, 26, (typing or S.hover == "search") and GOLD or LINE)
	if typing then
		typed(x + 8, sy + 13, 14)
	else
		text(S.search ~= "" and S.search or "Search " .. string.lower(TABS[S.tab][1]), x + 8, sy + 13, 14, S.search ~= "" and WHITE or DIM)
	end
	hit("search", x, sy, w - 36, 26, function() begin_typing("search") end)
	button("unsearch", "X", x + w - 30, sy, 30, 26, function()
		S.search = ""
		filter()
	end)
end

-- A full preset: its name (click to rename), Load / Save / Delete, and what it holds.
local function draw_preset(item, x, y, w)
	local n, typing = item.n, S.typing and S.typing.mode == "name"
	if typing then
		rect(x - 4, y - 4, 420, 28, SUNK)
		outline(x - 4, y - 4, 420, 28, GOLD)
		typed(x + 4, y + 10, 18)
		text("Enter keeps the name, Esc goes back", x + 428, y + 10, 13, MUTED)
	else
		text(item.name, x, y + 10, 20, S.hover == "rename" and WHITE or GOLD, nil, "ui_heading")
		hit("rename", x - 4, y - 4, w, 28, function() begin_typing("name", item) end)
	end
	local sure = S.confirm and S.confirm.n == n and S.confirm.kind
	local by = y + 36
	button("fload", "Load", x, by, 90, 24, function() full_load(n) end)
	button("fsave", sure == "save" and "Click again to overwrite" or "Save current changes", x + 98, by, 210, 24, function()
		if sure ~= "save" then S.confirm = { n = n, kind = "save" } return end
		full_save(n)
		show_presets(n)
	end, sure == "save")
	button("fdelete", sure == "delete" and "Sure?" or "Delete", x + 316, by, 90, 24, function()
		if sure ~= "delete" then S.confirm = { n = n, kind = "delete" } return end
		full_delete(n)
		load_tab(PRESETS_TAB)
	end, sure == "delete")
	text("Now changed: " .. S.count .. " value(s). Loading a preset replaces every current change with it.", x, by + 42, 14, MUTED)
	-- What it holds, by item.
	if not S.names then
		S.names = {}
		for i, tab in ipairs(TABS) do
			if i ~= PRESETS_TAB then
				local ok, list = pcall(tab[2])
				for _, it in ipairs(ok and list or {}) do
					local key = it.kind == "unit" and settings_of(it.unit) or it.kind == "hero" and HELLDIVER
						or it.kind == "strat" and ("stratagem:" .. it.id) or it.kind == "status" and ("status:" .. it.id)
					if key then S.names[key] = S.names[key] or it.name end
					if it.unit then S.names[it.unit] = S.names[it.unit] or it.name end
				end
			end
		end
	end
	local counts, order = {}, {}
	for line in string.gmatch(storage.get(full_key(n)) or "", "[^\n]+") do
		local where, path = string.match(line, "^([^|#]+)|([^|]+)|")
		if where then
			local name = S.names[where == "att" and path or where] or (where == "att" and path or where)
			if not counts[name] then counts[name], order[#order + 1] = 0, name end
			counts[name] = counts[name] + 1
		end
	end
	table.sort(order)
	local ly = by + 68
	rect(x, ly, w - 8, ROW_H - 2, BAND)
	text("WHAT IT HOLDS", x + 6, ly + ROW_H / 2 - 1, 13, MUTED)
	if #order == 0 then text("No changes: loading it puts every value back to the game's.", x + 6, ly + ROW_H * 1.5, 15, DIM) end
	for i, name in ipairs(order) do
		local ry = ly + i * ROW_H
		if ry > WY + WH - 140 then
			text("and " .. (#order - i + 1) .. " more", x + 6, ry + ROW_H / 2, 15, DIM)
			break
		end
		text(name, x + 6, ry + ROW_H / 2, 15, WHITE)
		text(counts[name] .. " value(s)", x + w - 16, ry + ROW_H / 2, 15, MUTED, "right")
	end
end

local function draw_rows(x, y, w, h)
	local item = S.pick
	if not item then
		if S.tab == PRESETS_TAB and not S.settings then
			text("Presets", x, y + 10, 20, GOLD, nil, "ui_heading")
			text("A preset keeps every change you have made as one set, under a name you choose.", x, y + 44, 15, WHITE)
			text("\"+ New preset\" saves your current changes as one; you name it next.", x, y + 66, 15, MUTED)
		end
		return
	end
	if item.kind == "preset" then return draw_preset(item, x, y, w) end
	text(item.name, x, y + 10, 20, GOLD, nil, "ui_heading")
	if S.rows == nil or #S.rows == 0 then
		text("Its data isn't loaded on this screen. Open it on the ship or in a mission.", x, y + 44, 15, MUTED)
		return
	end
	local top = y + 30
	local n = math.floor((h - 30) / ROW_H)
	if S.follow then
		if S.row < S.row_top then S.row_top = S.row end
		if S.row >= S.row_top + n then S.row_top = S.row - n + 1 end
	end
	S.row_top = math.max(1, math.min(S.row_top, #S.rows - n + 1))
	local vx, bx = x + w - 192, x + w - 158
	for i = S.row_top, math.min(#S.rows, S.row_top + n - 1) do
		local r = S.rows[i]
		local ry = top + (i - S.row_top) * ROW_H
		if r.header then
			rect(x, ry, w - 8, ROW_H - 2, BAND)
			local head = string.upper(r.header)
			text(head, x + 6, ry + ROW_H / 2 - 1, 13, MUTED)
			if r.share then
				-- As in SSEO: the other items this section's values also change, as many as fit, then +N.
				local nx = x + 6 + width(head, 13) + 14
				local room, note, shown = x + w - 16 - nx, nil, 0
				for k = math.min(3, #r.share), 1, -1 do
					shown = k
					note = "shared with " .. table.concat(r.share, ", ", 1, k) .. (#r.share > k and (" +" .. (#r.share - k)) or "")
					if k == 1 or width(note, 13) <= room then break end
				end
				clip(nx, ry, room, ROW_H, function() text(note, nx, ry + ROW_H / 2 - 1, 13, GOLD) end)
				local id = "share" .. i
				hit(id, nx, ry, room, ROW_H - 2, function() end)
				if S.hover == id and #r.share > shown then S.share_tip = { names = r.share, x = nx, y = ry + ROW_H } end
			end
		else
			local id = "row" .. i
			if i == S.row then rect(x, ry, w - 8, ROW_H - 1, FOCUS)
			elseif S.hover == id then rect(x, ry, w - 8, ROW_H - 1, HOVER) end
			hit(id, x, ry, w - 8, ROW_H - 1, function() S.row = i end)
			local v, changed = r.get(), r.changed()
			clip(x, ry, vx - x - 90, ROW_H, function() text(r.label, x + 6, ry + ROW_H / 2, 15, WHITE) end)
			local typing = S.typing and S.typing.row == r
			if r.f.type == "action" then
				text(type(r.note) == "function" and r.note() or r.note, vx, ry + ROW_H / 2, 15, S.capture and r.label == "Open key" and GOLD or MUTED, "right")
			elseif typing then
				rect(vx - 80, ry + 1, 84, ROW_H - 3, SUNK)
				outline(vx - 80, ry + 1, 84, ROW_H - 3, GOLD)
				typed(vx, ry + ROW_H / 2, 15, "right")
			else
				local shown = v
				if r.f.type == "boolean" then shown = v == true end
				if r.f.choices then shown = r.f.choices[v] end
				if not r.f.buttons then text(show(shown), vx, ry + ROW_H / 2, 15, changed and GOLD or WHITE, "right") end
				if r.f.type ~= "boolean" and not r.f.choices then
					hit("value" .. i, vx - 80, ry, 84, ROW_H - 1, function()
						S.row = i
						begin_typing("number", r)
					end)
				end
			end
			local by, bh = ry + 1, ROW_H - 3
			if r.f.type == "action" then
				for k, b in ipairs(r.buttons) do
					button("a" .. i .. "_" .. k, b[1], bx + (k - 1) * 76, by, 72, bh, function()
						S.row = i
						b[2]()
					end)
				end
			elseif r.f.type == "boolean" then
				button("t" .. i, v == true and "Turn off" or "Turn on", bx, by, 122, bh, function() change(r, 1) end)
			elseif r.f.buttons then
				-- One button per choice, the chosen one lit.
				for k, name in ipairs(r.f.choices) do
					button("t" .. i .. "_" .. k, name, bx + 122 - (#r.f.choices - k + 1) * 126 + 4, by, 122, bh, function()
						S.row = i
						r.set(k)
					end, v == k)
				end
			elseif r.f.choices then
				button("t" .. i, "Next", bx, by, 122, bh, function() change(r, 1) end)
			else
				button("mm" .. i, "--", bx, by, 28, bh, function() change(r, -1, true) end)
				button("m" .. i, "-", bx + 32, by, 28, bh, function() change(r, -1) end)
				button("p" .. i, "+", bx + 64, by, 28, bh, function() change(r, 1) end)
				button("pp" .. i, "++", bx + 96, by, 28, bh, function() change(r, 1, true) end)
			end
			if r.f.type ~= "action" then button("r" .. i, "R", bx + 128, by, 22, bh, function() reset(r) end, false, changed and GOLD or DIM) end
		end
	end
	scrollbar(x + w - 5, top, n * ROW_H, S.row_top, n, #S.rows)
end

local function draw_footer(x, y)
	rect(x + PAD, y, WW - PAD * 2, 1, LINE)
	local fy = y + 10
	-- This item's own presets.
	local item = S.pick
	if item and not S.settings and item.kind ~= "preset" and S.rows and #S.rows > 0 then
		text("PRESETS", x + PAD, fy + 11, 14, MUTED)
		local px = x + PAD + 72
		for n = 1, 5 do
			local has = storage.get(item_key(item, n)) ~= nil
			button("slot" .. n, tostring(n), px, fy, 26, 22, function() S.slot = n end, n == S.slot, has and GOLD or DIM)
			px = px + 30
		end
		button("save", "Save", px + 6, fy, 64, 22, function() item_save(item) end)
		button("load", "Load", px + 74, fy, 64, 22, function() item_load(item) end)
		button("clear", "Clear", px + 142, fy, 64, 22, function() item_clear(item) end)
	end
	local right = x + WW - PAD
	button("settings", "Settings", right - 90, fy, 90, 22, toggle_settings, S.settings)
	local on_presets = S.tab == PRESETS_TAB and not S.settings
	button("presets", "Presets", right - 184, fy, 90, 22, function()
		if on_presets then return load_tab(shown_tab(S.back or 1, 0)) end
		if S.tab ~= PRESETS_TAB then S.back = S.tab end
		load_tab(PRESETS_TAB)
	end, on_presets)
	-- Resets ask first: the button says "Sure?" and a second click does it.
	local function sure(kind, label, bx, bw, fn)
		local asking = S.confirm and S.confirm.kind == kind
		button(kind, asking and "Sure?" or label, bx, fy, bw, 22, function()
			if not asking then S.confirm = { kind = kind } return end
			S.confirm = nil
			fn()
		end, false, asking and GOLD or nil)
	end
	if S.settings then
		sure("resetall", "Reset all", right - 278, 90, reset_all)
		sure("resetitem", "Reset settings", right - 396, 114, reset_item)
	else
		sure("resetitem", "Reset item", right - 302, 114, reset_item)
	end
	local r = S.rows[S.row]
	for i, line in ipairs(wrap(r and r.help or "", 14, WW - PAD * 2 - 180)) do
		if i <= 2 then text(line, x + PAD, fy + 24 + i * 16, 14, MUTED) end
	end
	if S.cfg.hints then
		local hints = wrap("Up/Down choose a stat, Left/Right change it (Shift: bigger steps), click a value or press Enter to type it, PgUp/PgDn change item, Del resets, Tab changes tab, Esc closes",
			12, WW - PAD * 2)
		for i, line in ipairs(hints) do
			if i <= 2 then text(line, x + PAD, fy + 62 + i * 14, 12, DIM) end
		end
	end
	local count = S.cfg.changes and (S.count .. " value(s) changed") or "Your changes are off"
	text(count, right, fy + 40, 14, S.cfg.changes and (S.count > 0 and GOOD or DIM) or GOLD, "right")
end

local function draw()
	rect(WX, WY, WW, WH, { BG[1], BG[2], BG[3], BACKGROUNDS[S.cfg.bg][2] }, 820)
	outline(WX, WY, WW, WH, GOLD)
	text("SHODAN HD1 EDITOR", WX + PAD, WY + 18, 20, GOLD, nil, "ui_heading")
	local slot = storage.get("preset")
	local loaded = slot and full_name(storage.get(full_key(slot)))
	local pw = width(loaded or "none", 14)
	text(loaded or "none", WX + WW - PAD, WY + 18, 14, loaded and GOLD or MUTED, "right")
	text("Preset: ", WX + WW - PAD - pw, WY + 18, 14, MUTED, "right")
	local offer = fgw.update and fgw.update.offer()
	if offer then
		local ow = width(offer, 14) + 20
		local ox = WX + WW - PAD - pw - width("Preset: ", 14) - ow - 16
		local can = fgw.update.state == "available"
		button("update", offer, ox, WY + 7, ow, 22, function() if can then fgw.update.install() end end, can, can and WHITE or MUTED)
	end
	local tx, ty = WX + PAD, WY + 36
	for i, tab in ipairs(TABS) do
		if i ~= PRESETS_TAB and not S.cfg.hidden[tab[1]] then
			local w = width(tab[1], 14) + 12
			if tx + w > WX + WW - PAD then tx, ty = WX + PAD, ty + 26 end
			button("tab" .. i, tab[1], tx, ty, w, 22, function() load_tab(i) end, i == S.tab and not S.settings)
			tx = tx + w + 3
		end
	end
	local top, bottom = ty + 32, WY + WH - (S.cfg.hints and 116 or 86)
	if S.settings then
		draw_rows(WX + PAD, top, WW - PAD * 2, bottom - top)
	else
		draw_list(WX + PAD, top, LIST_W, bottom - top)
		rect(WX + PAD + LIST_W + 10, top, 2, bottom - top, LINE)
		draw_rows(WX + PAD + LIST_W + 24, top, WW - LIST_W - PAD * 2 - 24, bottom - top)
	end
	draw_footer(WX, bottom + 6)
	local tip = S.share_tip
	S.share_tip = nil
	if tip then
		-- Every name a cut-short 'shared with' names, in columns, over the rows below it.
		local names = {}
		for k, n in ipairs(tip.names) do names[k] = n end
		table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
		local col_w, pitch = 210, 18
		local cols = math.min(4, math.max(1, math.ceil(#names / 12)))
		local rows = math.min(math.ceil(#names / cols), math.floor((H - 160) / pitch))
		local shown = math.min(#names, cols * rows)
		if shown < #names then shown = shown - 1 end
		local w, h = cols * col_w + 24, rows * pitch + 40
		local x = math.max(16, math.min(tip.x, 1280 - 16 - w))
		local y = tip.y
		if y + h > H - 40 then y = math.max(16, tip.y - ROW_H - h) end
		rect(x, y, w, h, { 8, 11, 15 }, 830)
		outline(x, y, w, h, GOLD, 831)
		text("Also changes (" .. #names .. "):", x + 12, y + 16, 13, MUTED, nil, nil, 832)
		for k = 1, shown do
			local c, r = math.floor((k - 1) / rows), (k - 1) % rows
			text(names[k], x + 12 + c * col_w, y + 36 + r * pitch, 13, WHITE, nil, nil, 832)
		end
		if shown < #names then text("+" .. (#names - shown) .. " more", x + 12 + (cols - 1) * col_w, y + 36 + (rows - 1) * pitch, 13, DIM, nil, nil, 832) end
	end
end

local function frame()
	local dt = global("ENGINE_DT") or 0.016
	if S.dirty then
		S.dirty = S.dirty - dt
		if S.dirty <= 0 then save_current() end
	end
	if not S.open then return end
	if state_name() ~= S.state then return close() end
	hold_focus()
	if S.cursor then
		local cursors = global("CursorManager")
		if not cursors:is_shown() or cursors:get_current_cursor() ~= CURSOR then pcall(show_cursor) end
	end
	S.changed, S.count = {}, 0
	for _, e in ipairs(edits.list()) do
		S.changed[e.settings_path or e.keep or ""] = true
		S.count = S.count + 1
	end
	for path in pairs(S.att) do
		local name = string.match(path, "^strat:(.+)$")
		if name then
			S.changed["stratagem:" .. name] = true
			for _, it in ipairs(S.items or {}) do if it.strat == name and it.key then S.changed[it.key] = true end end
		end
		S.changed[settings_of(path) or path] = true
		S.count = S.count + 1
	end
	if S.capture_set then
		fgw.storage.set("key.open", S.capture_set)
		toast("Open key: " .. key_label(S.capture_set))
		S.capture_set = nil
	end
	if S.capture then read_capture() elseif S.typing then read_typing() else keys(dt) end
	if not S.open then return end
	mouse()
	if not S.open then return end
	local script = global("Script")
	local vectors, quaternions, matrices = script.temp_count()
	S.next_hits = {}
	local ok, err = pcall(draw)
	script.set_temp_count(vectors, quaternions, matrices)
	S.hits = S.next_hits
	if not ok then error(err, 0) end
end

load_settings()
check_updates()
fgw.ui.frame(1280, 720)
kit = fgw.ui.canvas("stat_editor", { over_fades = true })

fgw.on_frame(function()
	local ok, err = pcall(frame)
	if not ok then
		fgw.log("frame: " .. tostring(err))
		pcall(close)
	end
end)

local function raw_table(t) return rawget(t, "__protected_table") or t end

-- The units a stratagem's upgrades reach: its support weapon and the unit it calls in. Built once.
local strat_of
local function strat_mix(path)
	if not strat_of then
		local map = {}
		for _, w in ipairs(catalog.support_weapons()) do map[w.unit_path] = w.name end
		for _, st in ipairs(catalog.stratagems()) do
			if type(st.unit) == "string" and not map[st.unit] then map[st.unit] = st.name end
		end
		-- Before the game has loaded its stratagems there's nothing to map yet.
		if next(map) == nil then return nil end
		strat_of = map
	end
	local name = strat_of[path]
	local mask = name and S.att["strat:" .. name]
	if not mask then return nil end
	local base = global("LuaSettingsManager"):get_settings_by_unit_path(path)
	local info = base and base.upgrade_info
	if type(info) ~= "table" or info.type == "bitmask" then return nil end
	-- A fresh table per call: edits made since are in the base, and a refresh hands them over.
	local t = table.clone(raw_table(base))
	for i, up in ipairs(info) do
		if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then global("SettingsAux").recursive_override(t, up) end
	end
	return t
end

-- The attachments chosen here, for every weapon of that unit path. unit: a unit or a unit path.
fgw.hook("LuaSettingsManager", "get_modified_settings", function(original, self, unit, value, ...)
	if next(S.att) ~= nil then
		local path = unit
		if type(unit) ~= "string" then
			local ok, p = pcall(global("Unit").get_data, unit, "unit_path")
			path = ok and p or nil
		end
		local want = path and S.att[path]
		if want then value = want end
		local mix = path and not want and strat_mix(path)
		if mix then return mix end
	end
	return original(self, unit, value, ...)
end)

fgw.hook("LoadoutSettings", "get_upgraded_stratagem", function(original, name, level, ...)
	local base = original(name, 0, ...)
	local mask = type(base) == "table" and type(base.upgrades) == "table" and S.att["strat:" .. tostring(base.name)]
	if not mask then return original(name, level, ...) end
	local t = table.clone(raw_table(base))
	for i, up in ipairs(base.upgrades) do
		if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then global("SettingsAux").recursive_override(t, up) end
	end
	return t
end)

fgw.keybind("open", function()
	if S.capture or S.capture_set then return end
	if S.open then close() else open() end
end)

-- The chat would take the Enter that types a value.
fgw.wrap("TextChat", "start_typing", function(original, self, ...)
	if S.open then return end
	return original(self, ...)
end)

-- A lobby that stops being cleared takes the edits off, and the window must give the input back.
fgw.on_session(function(on)
	if not on then close() end
end)

-- The kept edits, once the game has made its weapon upgrade tables.
fgw.on_frame(function()
	local lsm = global("LuaSettingsManager")
	if not (lsm and next(lsm.unit_path_to_modified_settings or {}) ~= nil) then return false end
	if not S.cfg.changes then return true end
	local n = apply_text(fgw.storage.get("current"))
	if n > 0 then fgw.log("applied " .. n .. " kept edit(s)") end
	return true
end)

-- For the headless test.
return { S = S, frame = frame, open = open, close = close, load_tab = load_tab, pick = pick, change = change }
