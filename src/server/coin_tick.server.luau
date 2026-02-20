-- ServerScriptService.coin_tick
-- Grants coins periodically, with FriendsBoost multiplier

local Players = game:GetService("Players")

local PlayerDataService = require(script.Parent.Services.PlayerDataService)
local FriendsBoostService = require(script.Parent.Services.FriendsBoostService)

local BASE_INTERVAL_SECONDS = 10
local DECREASE_PER_ADDITIONAL_PLAYER_SECONDS = 2
local MIN_INTERVAL_SECONDS = 2
local BASE_COINS_PER_TICK = 1

local function getDynamicIntervalSeconds(): number
	local playerCount = #Players:GetPlayers()
	local interval = BASE_INTERVAL_SECONDS - (math.max(0, playerCount - 1) * DECREASE_PER_ADDITIONAL_PLAYER_SECONDS)
	return math.max(MIN_INTERVAL_SECONDS, interval)
end

task.spawn(function()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			local boost = FriendsBoostService.GetBoost(player)
			local amount = BASE_COINS_PER_TICK * boost
			PlayerDataService.AddCoins(player, amount)
		end
		task.wait(getDynamicIntervalSeconds())
	end
end)

return {}
