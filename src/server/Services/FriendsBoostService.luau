-- ServerScriptService.Services.FriendsBoostService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FriendsBoostService = {}

local Boosts: { [Player]: number } = {}

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local remoteBoost = Remotes:FindFirstChild("FriendsBoostUpdated")
if not remoteBoost then
	remoteBoost = Instance.new("RemoteEvent")
	remoteBoost.Name = "FriendsBoostUpdated"
	remoteBoost.Parent = Remotes
end

local remoteNotify = Remotes:FindFirstChild("FriendJoinLeaveNotification")
if not remoteNotify then
	remoteNotify = Instance.new("RemoteEvent")
	remoteNotify.Name = "FriendJoinLeaveNotification"
	remoteNotify.Parent = Remotes
end

local remotePresence = Remotes:FindFirstChild("FriendPresenceForNewPlayer")
if not remotePresence then
	remotePresence = Instance.new("RemoteEvent")
	remotePresence.Name = "FriendPresenceForNewPlayer"
	remotePresence.Parent = Remotes
end

-------------------------------------------------
-- CHECK IF TWO USERS ARE FRIENDS
-------------------------------------------------
local function areFriends(id1: number, id2: number): boolean
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(id1)
	end)
	if not ok then
		return false
	end

	local page = pages:GetCurrentPage()
	for _, info in ipairs(page) do
		if info.Id == id2 then
			return true
		end
	end

	while pages.IsFinished ~= true do
		pages:AdvanceToNextPageAsync()
		page = pages:GetCurrentPage()
		for _, info in ipairs(page) do
			if info.Id == id2 then
				return true
			end
		end
	end

	return false
end

-------------------------------------------------
-- FULL RECALC (NO BROADCAST)
-------------------------------------------------
local function computeBoosts(excludePlayer: Player?)
	local players = Players:GetPlayers()
	if excludePlayer then
		local filtered = table.create(#players)
		for _, p in ipairs(players) do
			if p ~= excludePlayer then
				table.insert(filtered, p)
			end
		end
		players = filtered
	end

	for _, p in ipairs(players) do
		Boosts[p] = 1
	end

	if excludePlayer then
		Boosts[excludePlayer] = nil
	end

	for _, a in ipairs(players) do
		for _, b in ipairs(players) do
			if a ~= b then
				if areFriends(a.UserId, b.UserId) then
					Boosts[a] += 1
				end
			end
		end
	end
end

-------------------------------------------------
-- SEND BOOSTS
-------------------------------------------------
local function broadcastBoosts(excludePlayer: Player?)
	for _, p in ipairs(Players:GetPlayers()) do
		if excludePlayer and p == excludePlayer then
			continue
		end
		remoteBoost:FireClient(p, Boosts[p] or 1)
	end
end

-------------------------------------------------
-- SEND FRIEND JOIN/LEAVE NOTIFICATION
-------------------------------------------------
local function notifyFriendsAbout(player: Player, isJoin: boolean)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			if areFriends(other.UserId, player.UserId) then
				remoteNotify:FireClient(other, player.DisplayName, isJoin, Boosts[other] or 1)
			end
		end
	end
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------
function FriendsBoostService.GetBoost(player: Player): number
	return Boosts[player] or 1
end

function FriendsBoostService.OnStart()
	Players.PlayerAdded:Connect(function(player)
		computeBoosts(nil)
		broadcastBoosts(nil)
		notifyFriendsAbout(player, true)

		-- show "you joined your friend" for the new player (pick any one friend)
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				if areFriends(player.UserId, other.UserId) then
					remotePresence:FireClient(player, other.DisplayName or other.Name, Boosts[player] or 1)
					break
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		computeBoosts(player)
		broadcastBoosts(player)
		notifyFriendsAbout(player, false)
	end)

	computeBoosts(nil)
	broadcastBoosts(nil)
end

return FriendsBoostService
