-- ReplicatedStorage.Configs.RuntimeSettings
-- Central place for toggling between ProductionMode and TestMode.

export type Mode = "ProductionMode" | "TestMode"

-- Switch the game mode here.
local CURRENT_MODE: Mode = "ProductionMode"

type Settings = {
	Mode: Mode,
	AiNpcSpawnIntervalSeconds: number,
	CaptureCinematicCameraHoldSeconds: number,
	DebugRobuxReceipts: boolean,
	EnableDataStore: boolean,
	StartingCoins: number,
	CaptureHighlightSeconds: number,
	EnableToYourCastleButton: boolean,
}

local production: Settings = {
	Mode = "ProductionMode",
	-- Current (pre-modes) values:
	AiNpcSpawnIntervalSeconds = 5,
	CaptureCinematicCameraHoldSeconds = 0.75,
	DebugRobuxReceipts = false,
	EnableDataStore = true,
	StartingCoins = 10,
	CaptureHighlightSeconds = 2,
	EnableToYourCastleButton = true,
}

local test: Settings = {
	Mode = "TestMode",
	AiNpcSpawnIntervalSeconds = 60,
	CaptureCinematicCameraHoldSeconds = 8,
	DebugRobuxReceipts = true,
	EnableDataStore = false,
	StartingCoins = 3000,
	CaptureHighlightSeconds = 2,
	EnableToYourCastleButton = true,
}

local settings: Settings
if CURRENT_MODE == "TestMode" then
	settings = test
else
	settings = production
end

return settings
