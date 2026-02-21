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
}

local StateByUserId: { [number]: PlayerState } = {}

local function keyFor(userId: number): string
	return tostring(userId)
end

local function ensureLeaderstats(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local coins = leaderstats:FindFirstChild("Coins")
	if not coins then
		coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Parent = leaderstats
	end

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

	StateByUserId[userId] = data

	local coinsValue = ensureLeaderstats(player)
	coinsValue.Value = getStartingCoins()
	local wins = (data :: any).wins
	setLeaderstatInt(player, "Wins", wins)
	maybeAwardWinBadges(player, wins)

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
	local leaderstats = player:FindFirstChild("leaderstats")
	local coinsValue = leaderstats and leaderstats:FindFirstChild("Coins")
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

function PlayerDataService.GetCoins(player: Player): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local coinsValue = leaderstats and leaderstats:FindFirstChild("Coins")
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
