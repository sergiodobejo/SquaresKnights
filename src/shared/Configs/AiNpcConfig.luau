-- ReplicatedStorage.Configs.AiNpcConfig
-- Configuration for spawning and behavior of AI NPCs (neutral units spawning in the center).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RuntimeSettings = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("RuntimeSettings"))

local Config = {
	-- Spawn one AI NPC every N seconds
	SpawnIntervalSeconds = RuntimeSettings.AiNpcSpawnIntervalSeconds,
	
	-- List of all available NPC model names that AI can spawn
	AvailableNpcModels = {
		"SK_Cavalry_Scout",
		"SK_Cavalry_Crossbowman",
		"SK_Cavalry_Mage",
		"SK_Knight",
		"SK_Cavalry_King",
		"SK_Heavy_Cavalry",
		"SK_Light_Cavalry",
		"SK_Archer",
		"SK_Crossbowman",
		"SK_Mage",
		"SK_Halberdier",
		"SK_Spearman",
		"SK_HeavySwordman",
		"SK_Heavy_Infantry",
		"SK_Light_Infantry",
		"SK_Swordman",
		"sk_Commander",
	},
	
	-- Team color for all AI NPCs
	TeamColorName = "blue",
}

return Config

