-- ReplicatedStorage.Configs.CastleKillsBadges
-- Defines which badges should be awarded at which castle-destruction milestones.

export type CastleKillsBadgeRule = {
	RequiredCastleKills: number,
	BadgeId: number,
}

-- Add more rules as needed. A player with castle kills >= RequiredCastleKills will be awarded that badge.
-- Tip: keep RequiredCastleKills unique.
local Config: { CastleKillsBadgeRule } = {
	{
		RequiredCastleKills = 1,
		BadgeId = 2422382930221827,
	},
}

return Config
