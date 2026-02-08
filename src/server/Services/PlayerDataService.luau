-- ServerScriptService.Services.PlayerDataService
-- Minimal persistence for coins + buffs (DataStore)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local BuffStateService = require(ServerScriptService.Services.BuffStateService)
local BuffEffectService = require(ServerScriptService.Services.BuffEffectService)

local PlayerDataService = {}

local STORE = DataStoreService:GetDataStore("PlayerDataV1")

local DEFAULT_COINS = 200

export type PlayerState = {
	coins: number,
	buffs: any,
	codes: { [string]: boolean }?,
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

	local territory = leaderstats:FindFirstChild("Territory%")
	if not territory then
		territory = Instance.new("IntValue")
		territory.Name = "Territory%"
		territory.Value = 0
		territory.Parent = leaderstats
	end

	return coins :: IntValue
end

local function load(player: Player)
	local userId = player.UserId
	local data
	local ok, err = pcall(function()
		data = STORE:GetAsync(keyFor(userId))
	end)
	if not ok then
		warn("[PlayerDataService] GetAsync failed (enable Studio API Services for DataStore):", err)
	end

	if type(data) ~= "table" then
		data = {
			coins = DEFAULT_COINS,
			buffs = {},
			codes = {},
		}
	end

	if type(data.coins) ~= "number" then
		data.coins = DEFAULT_COINS
	end
	if type(data.buffs) ~= "table" then
		data.buffs = {}
	end
	if type(data.codes) ~= "table" then
		data.codes = {}
	end

	StateByUserId[userId] = data

	local coinsValue = ensureLeaderstats(player)
	coinsValue.Value = math.floor(data.coins)

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

	local leaderstats = player:FindFirstChild("leaderstats")
	local coinsValue = leaderstats and leaderstats:FindFirstChild("Coins")
	if coinsValue and coinsValue:IsA("IntValue") then
		state.coins = coinsValue.Value
	end

	state.buffs = BuffStateService.ExportForSave(player)

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
