-- ServerScriptService.coin_tick
-- Grants coins periodically, with FriendsBoost multiplier

local Players = game:GetService("Players")

local PlayerDataService = require(script.Parent.Services.PlayerDataService)
local FriendsBoostService = require(script.Parent.Services.FriendsBoostService)

local INTERVAL_SECONDS = 10
local BASE_COINS_PER_TICK = 1

task.spawn(function()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			local boost = FriendsBoostService.GetBoost(player)
			local amount = BASE_COINS_PER_TICK * boost
			PlayerDataService.AddCoins(player, amount)
		end
		task.wait(INTERVAL_SECONDS)
	end
end)

return {}
