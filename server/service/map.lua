local skynet = require "skynet"
local logger = require "logger"
local aoi = require "map.aoi"

local world
local conf

local pending_character = {}
local online_character = {}
local CMD = {}

function CMD.init (w, c)
	world = w
	conf = c
	aoi.init (conf.bbox, conf.radius)
	logger.name (conf.name)
end

function CMD.character_enter (_, agent, character)
	logger.logf ("character(%d) loading map", character)

	pending_character[agent] = character
	skynet.call (agent, "lua", "map_enter")
end

function CMD.character_leave (agent)
	local character = online_character[agent] or pending_character[agent]
	if character ~= nil then
		logger.logf ("character(%d) leave map", character)
		local ok, notify_list = aoi.remove (agent)
		if ok then
			local t = { [agent] = agent }
			for _, a in pairs (notify_list) do
				skynet.call (a, "lua", "aoi_remove", t)
			end
		end
	end
	online_character[agent] = nil
	pending_character[agent] = nil
end

function CMD.character_ready (agent, pos)
	if pending_character[agent] == nil then return false end
	online_character[agent] = pending_character[agent]
	pending_character[agent] = nil

	logger.logf ("character(%d) enter map", online_character[agent])

	local ok, list = aoi.insert (agent, pos)
	if not ok then return false end

	skynet.call (agent, "lua", "aoi_add", list)

	local t = { agent }
	for _, a in pairs (list) do
		skynet.call (a, "lua", "aoi_add", t)
	end

	return true
end

function CMD.move_blink (agent, pos)
	local ok, add, update, remove = aoi.update (agent, pos)
	if not ok then return false end

	skynet.call (agent, "lua", "aoi_add", add)
	skynet.call (agent, "lua", "aoi_move", update)
	skynet.call (agent, "lua", "aoi_remove", remove)

	local t = { [agent] = agent }
	for _, a in pairs (add) do
		skynet.call (a, "lua", "aoi_add", t)
	end
	for _, a in pairs (update) do
		skynet.call (a, "lua", "aoi_move", t)
	end
	for _, a in pairs (remove) do
		skynet.call (a, "lua", "aoi_remove", t)
	end

	return true
end

skynet.start (function ()
	skynet.dispatch ("lua", function (_, source, command, ...)
		local f = assert (CMD[command])
		skynet.retpack (f (source, ...))
	end)
end)
