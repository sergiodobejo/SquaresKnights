-- ServerScriptService.Services.PlayerDataService
-- Minimal persistence for buffs + codes (DataStore)

local DataStoreService = game:GetService("DataStoreService")
local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BuffStateService = require(ServerScriptService.Services.BuffStateService)
local BuffEffectService = require(ServerScriptService.Services.BuffEffectService)
local RuntimeSettings = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("RuntimeSettings"))
local WinsBadges = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("WinsBadges"))

local PlayerDataService = {}

local STORE = DataStoreService:GetDataStore("PlayerDataV1")

local STATS_FOLDER_NAME = "Stats"
local COINS_VALUE_NAME = "Coins"

local function getStartingCoins(): number
	local v = (RuntimeSettings :: any).StartingCoins
	if type(v) == "number" then
		return math.max(0, math.floor(v))
	end
	return 10
end

export type PlayerState = {
	buffs: any,
	codes: { [string]: boolean }?,
	wins: number?,
	castleKills: number?,
}

local StateByUserId: { [number]: PlayerState } = {}

local function keyFor(userId: number): string
	return tostring(userId)
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureCoinsValue(player: Player): IntValue
	local statsFolder = getOrCreateFolder(player, STATS_FOLDER_NAME)
	local coins = statsFolder:FindFirstChild(COINS_VALUE_NAME)
	if coins and coins:IsA("IntValue") then
		return coins
	end
	local v = Instance.new("IntValue")
	v.Name = COINS_VALUE_NAME
	v.Value = 0
	v.Parent = statsFolder
	return v
end

local function ensureLeaderstats(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	-- Coins intentionally live outside leaderstats so they don't clutter the leaderboard.
	local coins = ensureCoinsValue(player)

	local wins = leaderstats:FindFirstChild("Wins")
	if not wins then
		wins = Instance.new("IntValue")
		wins.Name = "Wins"
		wins.Value = 0
		wins.Parent = leaderstats
	end

	local territory = leaderstats:FindFirstChild("Territory%")
	if not territory then
		territory = Instance.new("IntValue")
		territory.Name = "Territory%"
		territory.Value = 0
		territory.Parent = leaderstats
	end

	local castleKills = leaderstats:FindFirstChild("Castle Kills")
	if not castleKills then
		castleKills = Instance.new("IntValue")
		castleKills.Name = "Castle Kills"
		castleKills.Value = 0
		castleKills.Parent = leaderstats
	end

	return coins :: IntValue
end

local function setLeaderstatInt(player: Player, name: string, value: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local inst = leaderstats:FindFirstChild(name)
	if inst and inst:IsA("IntValue") then
		(inst :: IntValue).Value = math.max(0, math.floor(value))
	end
end

local function maybeAwardWinBadges(player: Player, wins: number)
	-- Skip badge awarding in Studio to avoid noisy API errors.
	if RunService:IsStudio() then
		return
	end
	if (RuntimeSettings :: any).EnableDataStore ~= true then
		-- In TestMode DataStore is off; wins are non-authoritative anyway.
		return
	end
	if type(wins) ~= "number" or wins <= 0 then
		return
	end
	if typeof(WinsBadges) ~= "table" then
		return
	end

	-- Copy + sort descending so higher milestones are attempted first.
	local rules = table.create(#(WinsBadges :: any))
	for _, r in ipairs(WinsBadges :: any) do
		table.insert(rules, r)
	end
	table.sort(rules, function(a: any, b: any)
		return (a.RequiredWins or 0) > (b.RequiredWins or 0)
	end)

	for _, rule in ipairs(rules) do
		local required = rule.RequiredWins
		local badgeId = rule.BadgeId
		if type(required) == "number" and type(badgeId) == "number" then
			required = math.floor(required)
			badgeId = math.floor(badgeId)
			if required > 0 and badgeId > 0 and wins >= required then
				local hasBadge = false
				local okHas, hasOrErr = pcall(function()
					return BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
				end)
				if okHas and hasOrErr == true then
					hasBadge = true
				end
				if not hasBadge then
					pcall(function()
						BadgeService:AwardBadge(player.UserId, badgeId)
					end)
				end
			end
		end
	end
end

local function getLeaderstatInt(player: Player, name: string): number?
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end
	local inst = leaderstats:FindFirstChild(name)
	if inst and inst:IsA("IntValue") then
		return (inst :: IntValue).Value
	end
	return nil
end

local function load(player: Player)
	local userId = player.UserId
	local data
	if (RuntimeSettings :: any).EnableDataStore == true then
		local ok, err = pcall(function()
			data = STORE:GetAsync(keyFor(userId))
		end)
		if not ok then
			warn("[PlayerDataService] GetAsync failed (enable Studio API Services for DataStore):", err)
		end
	end

	if type(data) ~= "table" then
		data = {
			buffs = {},
			codes = {},
			wins = 0,
			castleKills = 0,
		}
	end

	-- Coins are intentionally NOT persisted. Always reset to default on join.
	local anyData = data :: any
	anyData.coins = nil

	if type(data.buffs) ~= "table" then
		data.buffs = {}
	end
	if type(data.codes) ~= "table" then
		data.codes = {}
	end
	if type((data :: any).wins) ~= "number" then
		(data :: any).wins = 0
	end
	(data :: any).wins = math.max(0, math.floor((data :: any).wins))
	if type((data :: any).castleKills) ~= "number" then
		(data :: any).castleKills = 0
	end
	(data :: any).castleKills = math.max(0, math.floor((data :: any).castleKills))

	StateByUserId[userId] = data

	local coinsValue = ensureLeaderstats(player)
	coinsValue.Value = getStartingCoins()
	local wins = (data :: any).wins
	setLeaderstatInt(player, "Wins", wins)
	maybeAwardWinBadges(player, wins)

	local castleKills = (data :: any).castleKills
	setLeaderstatInt(player, "Castle Kills", castleKills)

	BuffStateService.LoadFromState(player, data.buffs)

	-- Restore active buffs on join and on respawn (if not expired)
	local function reapply()
		task.defer(function()
			-- give character time to spawn HRP
			task.wait(0.2)
			local remainingAll = BuffStateService.GetActiveRemainingAll(player)
			for effectName, remaining in pairs(remainingAll) do
				BuffEffectService.ApplyBuff(player, effectName, remaining)
			end
		end)
	end

	reapply()
	player.CharacterAdded:Connect(function()
		reapply()
	end)
end

local function save(player: Player)
	local userId = player.UserId
	local state = StateByUserId[userId]
	if not state then
		return
	end
	if (RuntimeSettings :: any).EnableDataStore ~= true then
		return
	end

	state.buffs = BuffStateService.ExportForSave(player)
	local anyState = state :: any
	anyState.coins = nil
	local wins = getLeaderstatInt(player, "Wins")
	if type(wins) == "number" then
		anyState.wins = math.max(0, math.floor(wins))
	end
	local castleKills = getLeaderstatInt(player, "Castle Kills")
	if type(castleKills) == "number" then
		anyState.castleKills = math.max(0, math.floor(castleKills))
	end

	local ok, err = pcall(function()
		STORE:SetAsync(keyFor(userId), state)
	end)
	if not ok then
		warn("[PlayerDataService] SetAsync failed (enable Studio API Services for DataStore):", err)
	end
end

function PlayerDataService.GetState(player: Player): PlayerState?
	return StateByUserId[player.UserId]
end

function PlayerDataService.IsCodeRedeemed(player: Player, code: string): boolean
	local state = StateByUserId[player.UserId]
	if not state then
		return false
	end
	if type(state.codes) ~= "table" then
		state.codes = {}
	end
	return state.codes[code] == true
end

function PlayerDataService.MarkCodeRedeemed(player: Player, code: string)
	local state = StateByUserId[player.UserId]
	if not state then
		return
	end
	if type(state.codes) ~= "table" then
		state.codes = {}
	end
	state.codes[code] = true
end

function PlayerDataService.AddCoins(player: Player, amount: number)
	local coinsValue = ensureCoinsValue(player)
	if coinsValue and coinsValue:IsA("IntValue") then
		local newValue = coinsValue.Value + math.floor(amount)
		if newValue < 0 then
			newValue = 0
		end
		coinsValue.Value = newValue
	end
end

function PlayerDataService.GetWins(player: Player): number
	local v = getLeaderstatInt(player, "Wins")
	if type(v) == "number" then
		return v
	end
	local state = StateByUserId[player.UserId]
	if state and type((state :: any).wins) == "number" then
		return (state :: any).wins
	end
	return 0
end

function PlayerDataService.AddWin(player: Player, amount: number?)
	local delta = if type(amount) == "number" then math.floor(amount) else 1
	if delta <= 0 then
		return
	end

	local newWins = PlayerDataService.GetWins(player) + delta
	setLeaderstatInt(player, "Wins", newWins)

	local state = StateByUserId[player.UserId]
	if state then
		(state :: any).wins = math.max(0, math.floor(newWins))
	end
end

function PlayerDataService.GetCastleKills(player: Player): number
	local v = getLeaderstatInt(player, "Castle Kills")
	if type(v) == "number" then
		return v
	end
	local state = StateByUserId[player.UserId]
	if state and type((state :: any).castleKills) == "number" then
		return (state :: any).castleKills
	end
	return 0
end

function PlayerDataService.AddCastleKill(player: Player, amount: number?)
	local delta = if type(amount) == "number" then math.floor(amount) else 1
	if delta <= 0 then
		return
	end

	local newKills = PlayerDataService.GetCastleKills(player) + delta
	setLeaderstatInt(player, "Castle Kills", newKills)

	local state = StateByUserId[player.UserId]
	if state then
		(state :: any).castleKills = math.max(0, math.floor(newKills))
	end
end

function PlayerDataService.GetCoins(player: Player): number
	local statsFolder = player:FindFirstChild(STATS_FOLDER_NAME)
	local coinsValue = statsFolder and statsFolder:FindFirstChild(COINS_VALUE_NAME)
	if coinsValue and coinsValue:IsA("IntValue") then
		return coinsValue.Value
	end
	return 0
end

function PlayerDataService.OnStart()
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(save)

	for _, player in ipairs(Players:GetPlayers()) do
		load(player)
	end

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			save(player)
		end
	end)
end

return PlayerDataService
