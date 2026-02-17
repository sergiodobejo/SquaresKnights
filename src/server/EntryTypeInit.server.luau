-- ServerScriptService.EntryTypeInit
-- Determines entry type from TeleportData and stamps it onto the Player as an Attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local EntryType = require(ReplicatedStorage:WaitForChild("EntryType"))

local ENTRY_TYPE_ATTRIBUTE = "EntryType"

local function readJoinData(player: Player): any
	-- Most reliable source on the server: Player:GetJoinData().TeleportData
	local okJoin, joinDataOrErr = pcall(function()
		return player:GetJoinData()
	end)
	if okJoin and type(joinDataOrErr) == "table" then
		return joinDataOrErr
	end
	if not okJoin then
		warn(string.format("[EntryTypeInit] Player:GetJoinData failed for %s: %s", player.Name, tostring(joinDataOrErr)))
	else
		warn(string.format("[EntryTypeInit] Player:GetJoinData returned non-table for %s: %s", player.Name, typeof(joinDataOrErr)))
	end
	return nil
end

local function readTeleportData(player: Player): any
	local joinData = readJoinData(player)
	if type(joinData) == "table" then
		return (joinData :: any).TeleportData
	end

	-- Fallback: older API surface (may not exist / may error)
	local okTp, dataOrErr = pcall(function()
		return (TeleportService :: any):GetPlayerTeleportData(player)
	end)
	if not okTp then
		warn(string.format("[EntryTypeInit] TeleportService:GetPlayerTeleportData failed for %s: %s", player.Name, tostring(dataOrErr)))
		return nil
	end
	return dataOrErr
end

local function stamp(player: Player)
	local joinData = readJoinData(player)
	local teleportData = if type(joinData) == "table" then (joinData :: any).TeleportData else nil
	local entryType = EntryType.FromTeleportData(teleportData)
	player:SetAttribute(ENTRY_TYPE_ATTRIBUTE, entryType)
end

for _, player in ipairs(Players:GetPlayers()) do
	task.defer(stamp, player)
end

Players.PlayerAdded:Connect(stamp)

return {}
