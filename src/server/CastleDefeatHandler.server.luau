-- ServerScriptService.CastleDefeatHandler
-- Teleports the owning player back to the lobby when their castle is destroyed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local ServerScriptService = game:GetService("ServerScriptService")

local RemoteNames = require(ReplicatedStorage:WaitForChild("RemoteNames"))
local CastleHealthService = require(ServerScriptService.Services:WaitForChild("CastleHealthService"))

local LOBBY_PLACE_ID = 108248113575262
local TELEPORT_DELAY_SECONDS = 2
local VICTORY_TELEPORT_DELAY_SECONDS = 5
local PLAYER_DEFEATED_ATTR = "Defeated"
local PLAYER_VICTORY_ATTR = "Victory"

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remotesFolder then
	error("[CastleDefeatHandler] Missing ReplicatedStorage/Remotes folder. Create it in Roblox Studio.")
end

local defeatedRemoteInst = (remotesFolder :: Instance):WaitForChild(RemoteNames.PlayerDefeated, 10)
if not defeatedRemoteInst or not defeatedRemoteInst:IsA("RemoteEvent") then
	error(string.format(
		"[CastleDefeatHandler] Missing RemoteEvent ReplicatedStorage/Remotes/%s. Create it in Roblox Studio.",
		RemoteNames.PlayerDefeated
	))
end
local defeatedRemote = defeatedRemoteInst :: RemoteEvent

local defeatedByUserId: { [number]: boolean } = {}
local matchEnded = false

local function getAliveOwnerUserIds(): { [number]: boolean }
	local alive: { [number]: boolean } = {}
	local buildingsFolder = Workspace:FindFirstChild("PlayerBuildings")
	if not buildingsFolder then
		return alive
	end

	for _, child in ipairs(buildingsFolder:GetChildren()) do
		if child:IsA("Model") and CastleHealthService.IsCastle(child) then
			local castle = child :: Model
			if not CastleHealthService.IsDestroyed(castle) then
				local ownerUserId = CastleHealthService.GetOwnerUserId(castle)
				if ownerUserId > 0 then
					alive[ownerUserId] = true
				end
			end
		end
	end

	return alive
end

local function countAliveOwners(alive: { [number]: boolean }): number
	local n = 0
	for _ in pairs(alive) do
		n += 1
	end
	return n
end

local function getOnlyAliveOwnerUserId(alive: { [number]: boolean }): number
	for userId in pairs(alive) do
		return userId
	end
	return 0
end

local function markAndHandleDefeat(player: Player)
	if defeatedByUserId[player.UserId] then
		return
	end
	defeatedByUserId[player.UserId] = true
	player:SetAttribute(PLAYER_DEFEATED_ATTR, true)

	defeatedRemote:FireClient(player, "You have been defeated.")

	task.delay(TELEPORT_DELAY_SECONDS, function()
		if not player.Parent then
			return
		end
		local ok, err = pcall(function()
			TeleportService:Teleport(LOBBY_PLACE_ID, player)
		end)
		if not ok then
			warn("[CastleDefeatHandler] Teleport failed:", err)
		end
	end)
end

CastleHealthService.OnCastleDestroyed(function(_castle: Model, ownerUserId: number, _teamId: number)
	if type(ownerUserId) ~= "number" or ownerUserId <= 0 then
		return
	end
	local player = Players:GetPlayerByUserId(ownerUserId)
	if not player then
		return
	end
	if player:GetAttribute(PLAYER_DEFEATED_ATTR) == true then
		return
	end
	markAndHandleDefeat(player)

	if matchEnded then
		return
	end

	local alive = getAliveOwnerUserIds()
	local aliveCount = countAliveOwners(alive)
	if aliveCount <= 0 then
		return
	end

	if aliveCount == 1 then
		local winnerUserId = getOnlyAliveOwnerUserId(alive)
		if winnerUserId <= 0 then
			return
		end
		local winner = Players:GetPlayerByUserId(winnerUserId)
		if not winner then
			return
		end
		if winner:GetAttribute(PLAYER_DEFEATED_ATTR) == true then
			return
		end

		matchEnded = true
		winner:SetAttribute(PLAYER_VICTORY_ATTR, true)
		defeatedRemote:FireClient(winner, "Victory!")

		task.delay(VICTORY_TELEPORT_DELAY_SECONDS, function()
			if not winner.Parent then
				return
			end
			local ok, err = pcall(function()
				TeleportService:Teleport(LOBBY_PLACE_ID, winner)
			end)
			if not ok then
				warn("[CastleDefeatHandler] Victory teleport failed:", err)
			end
		end)
		return
	end

	-- More than one player still alive: notify remaining players briefly.
	local defeatedName = player.Name
	local msg = string.format("%s defeated!", defeatedName)
	for _, p in ipairs(Players:GetPlayers()) do
		if alive[p.UserId] and p:GetAttribute(PLAYER_DEFEATED_ATTR) ~= true then
			defeatedRemote:FireClient(p, msg, 1.5)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	defeatedByUserId[player.UserId] = nil
end)
