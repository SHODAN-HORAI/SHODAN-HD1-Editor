-- No leaderboard reporting while SHODAN HD1 Editor is installed: edited missions stay off the boards,
-- Proving Grounds' included. Galactic War progress is sent as usual.
-- A blocked call is never sent, and every table handed to it is emptied: the ship menu saves that same
-- table back as the upload queue, so it can't go out later either.
local type, pairs, ipairs, select = type, pairs, ipairs, select

local M = {}

local UPLOADS = { "upload_leaderboard_stats", "upload_leaderboard_provinggrounds_stats" }
-- Results wait in these save keys until the ship menu sends them.
local USER_QUEUES = { "leaderboard_stats", "leaderboard_stats_to_upload",
	"leaderboard_provinggrounds_stats", "leaderboard_provinggrounds_stats_to_upload" }

local function empty(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	for _, k in ipairs(keys) do t[k] = nil end
end

function M.setup(hook, log)
	for _, name in ipairs(UPLOADS) do
		local said = false
		hook("CampaignManager", name, function(original, self, ...)
			for i = 1, select("#", ...) do
				local v = (select(i, ...))
				if type(v) == "table" then empty(v) end
			end
			if not said then said = true log("blocked upload: " .. name) end
		end)
	end
	hook("SaveManager", "user_save", function(original, self, done, fail, subtitle, details, user, ...)
		for _, key in ipairs(USER_QUEUES) do self:user_set(key, nil, user) end
		return original(self, done, fail, subtitle, details, user, ...)
	end)
	log("leaderboard reporting blocked")
end

return M
