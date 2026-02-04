-- Plain config table.
--
-- Units:
--  - AttackRange: studs (distance at which the unit starts attacking)
--  - Damage: hit damage (game-defined)
--  - Health: max health
--  - MoveSpeed: humanoid WalkSpeed (studs/sec)
--
-- NOTE: Numbers here are starter defaults; tune for balance.

export type WarriorCombatStats = {
	AttackRange: number,
	Damage: number,
	Health: number,
	MoveSpeed: number,
}

return {
	Cavalry = {
		Mage = {
			AttackRange = 30,
			Damage = 5,
			Health = 100,
			MoveSpeed = 8,
		} :: WarriorCombatStats,
		Spearman = {
			AttackRange = 15,
			Damage = 18,
			Health = 140,
			MoveSpeed = 8,
		} :: WarriorCombatStats,
		Swordsman = {
			AttackRange = 13,
			Damage = 20,
			Health = 150,
			MoveSpeed = 8,
		} :: WarriorCombatStats,
		Archer = {
			AttackRange = 30,
			Damage = 4,
			Health = 100,
			MoveSpeed = 8,
		} :: WarriorCombatStats,
		Crossbowman = {
			AttackRange = 30,
			Damage = 5,
			Health = 105,
			MoveSpeed = 8,
		} :: WarriorCombatStats,
	},

	Infantry = {
		Mage = {
			AttackRange = 25,
			Damage = 4,
			Health = 75,
			MoveSpeed = 6,
		} :: WarriorCombatStats,
		Spearman = {
			AttackRange = 12,
			Damage = 16,
			Health = 90,
			MoveSpeed = 6,
		} :: WarriorCombatStats,
		Swordsman = {
			AttackRange = 10,
			Damage = 18,
			Health = 95,
			MoveSpeed = 6,
		} :: WarriorCombatStats,
		Archer = {
			AttackRange = 25,
			Damage = 2,
			Health = 85,
			MoveSpeed = 6,
		} :: WarriorCombatStats,
		Crossbowman = {
			AttackRange = 30,
			Damage = 3,
			Health = 85,
			MoveSpeed = 6,
		} :: WarriorCombatStats,
		Polearmman = {
			AttackRange = 12,
			Damage = 17,
			Health = 95,
			MoveSpeed = 6,
		} :: WarriorCombatStats,
	},
}
