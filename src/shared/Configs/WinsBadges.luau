-- ReplicatedStorage.Configs.WinsBadges
-- Defines which badges should be awarded at which win milestones.

export type WinsBadgeRule = {
	RequiredWins: number,
	BadgeId: number,
}

-- Add more rules as needed. A player with wins >= RequiredWins will be awarded that badge.
-- Tip: keep RequiredWins unique.
local Config: { WinsBadgeRule } = {
	{
		RequiredWins = 1,
		BadgeId = 3708436602873836,
	},
}

return Config
