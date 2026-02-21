-- ServerScriptService.ModePlayCountInit
-- Increments a global DataStore counter once per server, keyed by entry/mode.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EntryType = require(ReplicatedStorage:WaitForChild("EntryType"))
local RuntimeSettings = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("RuntimeSettings"))

local STORE = DataStoreService:GetDataStore("ModePlaysV1")

local didIncrement = false

local function readJoinData(player: Player): any
	local ok, joinDataOrErr = pcall(function()
		return player:GetJoinData()
	end)
	if ok and type(joinDataOrErr) == "table" then
		return joinDataOrErr
	end
	return nil
end

local function getServerEntryTypeFromFirstPlayer(player: Player): EntryType.EntryType
	local joinData = readJoinData(player)
	local teleportData = if type(joinData) == "table" then (joinData :: any).TeleportData else nil
	return EntryType.FromTeleportData(teleportData)
end

local function keyForEntryType(entryType: string): string
	-- Keep keys stable and safe (avoid spaces/punctuation).
	local safe = entryType:gsub("[^%w]", "_")
	return "plays_" .. safe
end

local function increment(entryType: string)
	if didIncrement then
		return
	end
	didIncrement = true

	if (RuntimeSettings :: any).EnableDataStore ~= true then
		return
	end

	-- Avoid polluting prod stats during Studio iteration.
	if RunService:IsStudio() then
		return
	end

	local key = keyForEntryType(entryType)
	local ok, err = pcall(function()
		STORE:UpdateAsync(key, function(oldValue)
			if type(oldValue) ~= "number" then
				oldValue = 0
			end
			return (oldValue :: number) + 1
		end)
	end)
	if not ok then
		warn(string.format("[ModePlayCountInit] UpdateAsync failed (%s): %s", key, tostring(err)))
	end
end

local function onFirstPlayer(player: Player)
	local entryType = getServerEntryTypeFromFirstPlayer(player)
	increment(entryType)
end

-- Use the first player to decide which mode this server represents.
local existing = Players:GetPlayers()
if #existing > 0 then
	task.defer(onFirstPlayer, existing[1])
else
	local conn: RBXScriptConnection? = nil
	conn = Players.PlayerAdded:Connect(function(player)
		if conn then
			conn:Disconnect()
			conn = nil
		end
		onFirstPlayer(player)
	end)
end

return {}
