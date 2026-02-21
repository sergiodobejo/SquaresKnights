-- ServerScriptService.CastleDefeatHandler
-- Teleports the owning player back to the lobby when their castle is destroyed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local ServerScriptService = game:GetService("ServerScriptService")

local RemoteNames = require(ReplicatedStorage:WaitForChild("RemoteNames"))
local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local CastleHealthService = require(ServerScriptService.Services:WaitForChild("CastleHealthService"))
local OpenArenaCornerReservationService = require(ServerScriptService.Services:WaitForChild("OpenArenaCornerReservationService"))
local PlayerDataService = require(ServerScriptService.Services:WaitForChild("PlayerDataService"))

local LOBBY_PLACE_ID = 108248113575262
local PRE_RESULT_DELAY_SECONDS = 3
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

-- All user-facing text must come from StarterGui/Strings via GuiStrings on the client.
-- Server sends string keys (and optional args) only.
local STR_DEFEATED = "DefeatOverlay_Defeated"
local STR_VICTORY = "DefeatOverlay_Victory"
local STR_PLAYER_DEFEATED_FMT = "DefeatOverlay_PlayerDefeatedFmt"

local defeatedByUserId: { [number]: boolean } = {}
local matchEnded = false

local TERRITORY_VALUE_NAME = "Territory%"
local OPEN_ARENA_WIN_TERRITORY_PCT = 70

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

local function cleanupOwnedNpcsForUserId(userId: number)
	if type(userId) ~= "number" or userId <= 0 then
		return
	end

	local liveNpcFolder = Workspace:FindFirstChild("LiveNPC")
	if not liveNpcFolder or not liveNpcFolder:IsA("Folder") then
		return
	end

	local function maybeDestroyNpc(inst: Instance)
		if not inst:IsA("Model") then
			return
		end
		local npc = inst :: Model
		if Affiliation.GetOwnerUserIdFromModel(npc) ~= userId then
			return
		end
		pcall(function()
			npc:Destroy()
		end)
	end

	for _, child in ipairs((liveNpcFolder :: Folder):GetChildren()) do
		if child:IsA("Folder") then
			for _, sub in ipairs(child:GetChildren()) do
				maybeDestroyNpc(sub)
			end
		else
			maybeDestroyNpc(child)
		end
	end
end

local function markAndHandleDefeat(player: Player)
	if defeatedByUserId[player.UserId] then
		return
	end
	defeatedByUserId[player.UserId] = true

	-- Immediately clear this player's NPCs so their occupied cells/territory are freed for the match.
	cleanupOwnedNpcsForUserId(player.UserId)

	task.delay(PRE_RESULT_DELAY_SECONDS, function()
		if not player.Parent then
			return
		end
		if player:GetAttribute(PLAYER_DEFEATED_ATTR) == true then
			return
		end
		if player:GetAttribute(PLAYER_VICTORY_ATTR) == true then
			return
		end

		player:SetAttribute(PLAYER_DEFEATED_ATTR, true)
		defeatedRemote:FireClient(player, { key = STR_DEFEATED })

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
	end)
end

local function isOpenArenaMode(): boolean
	return OpenArenaCornerReservationService.IsActive()
end

local function teleportWinnerToLobbyAfterDelay(winner: Player)
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
end

local function endMatchWithWinner(winner: Player, reason: string)
	if matchEnded then
		return
	end
	if not winner or not winner:IsA("Player") then
		return
	end
	if winner:GetAttribute(PLAYER_DEFEATED_ATTR) == true or defeatedByUserId[winner.UserId] then
		return
	end

	matchEnded = true

	-- Persist win immediately so it gets saved on teleport (PlayerRemoving).
	pcall(function()
		PlayerDataService.AddWin(winner, 1)
	end)

	task.delay(PRE_RESULT_DELAY_SECONDS, function()
		if not winner.Parent then
			return
		end
		if winner:GetAttribute(PLAYER_DEFEATED_ATTR) == true then
			return
		end
		winner:SetAttribute(PLAYER_VICTORY_ATTR, true)
		defeatedRemote:FireClient(winner, { key = STR_VICTORY })
		teleportWinnerToLobbyAfterDelay(winner)
	end)

	-- Everyone else loses and returns to lobby.
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= winner and p:GetAttribute(PLAYER_DEFEATED_ATTR) ~= true then
			markAndHandleDefeat(p)
		end
	end

	print(string.format(
		"[CastleDefeatHandler] Match ended. Winner=%s reason=%s openArena=%s",
		winner.Name,
		tostring(reason),
		tostring(isOpenArenaMode())
	))
end

local function getTerritoryPct(player: Player): number
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return 0
	end
	local v = leaderstats:FindFirstChild(TERRITORY_VALUE_NAME)
	if v and v:IsA("IntValue") then
		return (v :: IntValue).Value
	end
	return 0
end

local territoryWatcherByUserId: { [number]: boolean } = {}
local function attachTerritoryWatcher(player: Player)
	if territoryWatcherByUserId[player.UserId] then
		return
	end
	territoryWatcherByUserId[player.UserId] = true

	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats", 10)
		if not leaderstats then
			return
		end
		if not leaderstats:IsA("Folder") then
			return
		end

		local function maybeCheckAndWin()
			if matchEnded then
				return
			end
			if not isOpenArenaMode() then
				return
			end
			if player.Parent == nil then
				return
			end
			if player:GetAttribute(PLAYER_DEFEATED_ATTR) == true then
				return
			end
			local pct = getTerritoryPct(player)
			if type(pct) == "number" and pct >= OPEN_ARENA_WIN_TERRITORY_PCT then
				endMatchWithWinner(player, "territory_70")
			end
		end

		local function onChild(child: Instance)
			if child.Name ~= TERRITORY_VALUE_NAME then
				return
			end
			if not child:IsA("IntValue") then
				return
			end
			(child :: IntValue).Changed:Connect(function()
				maybeCheckAndWin()
			end)
			maybeCheckAndWin()
		end

		for _, child in ipairs(leaderstats:GetChildren()) do
			onChild(child)
		end
		leaderstats.ChildAdded:Connect(onChild)
		maybeCheckAndWin()
	end)
end

Players.PlayerAdded:Connect(attachTerritoryWatcher)
for _, p in ipairs(Players:GetPlayers()) do
	attachTerritoryWatcher(p)
end

CastleHealthService.OnCastleDestroyed(function(_castle: Model, ownerUserId: number, _teamId: number)
	if type(ownerUserId) ~= "number" or ownerUserId <= 0 then
		return
	end
	local player = Players:GetPlayerByUserId(ownerUserId)
	if player then
		if player:GetAttribute(PLAYER_DEFEATED_ATTR) == true or defeatedByUserId[player.UserId] then
			return
		end
		markAndHandleDefeat(player)
	end

	if matchEnded then
		return
	end

	local alive = getAliveOwnerUserIds()
	local aliveCount = countAliveOwners(alive)
	if aliveCount <= 0 then
		return
	end

	if aliveCount == 1 then
		if isOpenArenaMode() then
			-- In OpenArena, destroying enemy castles never grants victory.
			return
		end

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

		endMatchWithWinner(winner, "last_castle")
		return
	end

	-- More than one player still alive: notify remaining players briefly.
	if player then
		local defeatedName = player.Name
		for _, p in ipairs(Players:GetPlayers()) do
			if alive[p.UserId] and p:GetAttribute(PLAYER_DEFEATED_ATTR) ~= true then
				defeatedRemote:FireClient(p, { key = STR_PLAYER_DEFEATED_FMT, args = { defeatedName } }, 1.5)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	-- If a player leaves mid-match (not due to defeat/victory teleports), briefly notify remaining alive players.
	if not matchEnded and not isOpenArenaMode() then
		local leftIsPartOfMatchFlow = player:GetAttribute(PLAYER_DEFEATED_ATTR) == true
			or player:GetAttribute(PLAYER_VICTORY_ATTR) == true
			or defeatedByUserId[player.UserId] == true
		if not leftIsPartOfMatchFlow then
			local alive = getAliveOwnerUserIds()
			local leftName = player.Name
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and alive[p.UserId] and p:GetAttribute(PLAYER_DEFEATED_ATTR) ~= true then
					defeatedRemote:FireClient(p, { key = STR_PLAYER_DEFEATED_FMT, args = { leftName } }, 1.5)
				end
			end
		end
	end

	-- If a player leaves mid-match, clear their NPCs so cells are freed.
	cleanupOwnedNpcsForUserId(player.UserId)

	-- Fallback: in normal mode, if after a leave only one player remains, grant them victory.
	-- This makes “opponent left” use the same win flow even if castle-destruction signaling
	-- is delayed or suppressed by ordering.
	task.spawn(function()
		local deadline = os.clock() + 2.0
		while os.clock() < deadline do
			if matchEnded or isOpenArenaMode() then
				return
			end
			local players = Players:GetPlayers()
			if #players == 1 then
				local winner = players[1]
				if winner and winner.Parent ~= nil then
					if winner:GetAttribute(PLAYER_DEFEATED_ATTR) ~= true and winner:GetAttribute(PLAYER_VICTORY_ATTR) ~= true then
						endMatchWithWinner(winner, "opponent_left")
					end
				end
				return
			end
			task.wait(0.1)
		end
	end)
	defeatedByUserId[player.UserId] = nil
	territoryWatcherByUserId[player.UserId] = nil
end)
