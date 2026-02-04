-- ServerScriptService.AiNpcInit
-- Initializes and starts the AI NPC spawning system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AiNpcService = require(ServerScriptService.Services:WaitForChild("AiNpcService"))
local AiNpcBehaviorService = require(ServerScriptService.Services:WaitForChild("AiNpcBehaviorService"))
local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))

-- Start the periodic spawning of AI NPCs
AiNpcService.StartSpawning()

print("[AiNpcInit] AI NPC system started; spawning every 5 seconds into Workspace/NPC folder")

return {}
