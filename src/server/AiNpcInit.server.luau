-- ServerScriptService.AiNpcInit
-- Initializes and starts the AI NPC spawning system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AiNpcService = require(ServerScriptService.Services:WaitForChild("AiNpcService"))
local AiNpcBehaviorService = require(ServerScriptService.Services:WaitForChild("AiNpcBehaviorService"))
local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))
local AiNpcConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("AiNpcConfig"))

-- Start the periodic spawning of AI NPCs
AiNpcService.StartSpawning()

print(string.format(
	"[AiNpcInit] AI NPC system started; base interval=%ss at 1 player (decreases by 1s per additional player, min 1s)",
	tostring(AiNpcConfig.SpawnIntervalSeconds)
))

return {}

