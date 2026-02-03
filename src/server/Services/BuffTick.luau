-- ServerScriptService.Services.BuffTick
-- Heartbeat loop to cleanup and apply buffs

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local BuffStateService = require(ServerScriptService.Services.BuffStateService)
local BuffEffectService = require(ServerScriptService.Services.BuffEffectService)

RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local allBuffs = BuffStateService.GetAllBuffs(player)
		if allBuffs then
			local effectNames = {}
			for effectName in pairs(allBuffs) do
				table.insert(effectNames, effectName)
			end
			for _, effectName in ipairs(effectNames) do
				local stillActive = BuffStateService.HasBuff(player, effectName)
				if not stillActive then
					BuffEffectService.RemoveBuff(player, effectName)
				end
			end
		end
	end
end)

return {}
