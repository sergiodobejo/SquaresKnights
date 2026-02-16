-- ServerScriptService.CastleDefeatHandler
-- Teleports the owning player back to the lobby when their castle is destroyed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local ServerScriptService = game:GetService("ServerScriptService")

local RemoteNames = require(ReplicatedStorage:WaitForChild("RemoteNames"))
local CastleHealthService = require(ServerScriptService.Services:WaitForChild("CastleHealthService"))

local LOBBY_PLACE_ID = 108248113575262
local TELEPORT_DELAY_SECONDS = 2
local PLAYER_DEFEATED_ATTR = "Defeated"

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

local function markAndHandleDefeat(player: Player)
	if defeatedByUserId[player.UserId] then
		return
	end
	defeatedByUserId[player.UserId] = true
	player:SetAttribute(PLAYER_DEFEATED_ATTR, true)

	defeatedRemote:FireClient(player)

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
end)

Players.PlayerRemoving:Connect(function(player: Player)
	defeatedByUserId[player.UserId] = nil
end)
