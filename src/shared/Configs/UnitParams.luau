-- Plain config table.
--
-- Units:
--  - AttackRange: studs (distance at which the unit starts attacking)
--  - Damage: hit damage (game-defined)
--  - Health: max health
--  - MoveSpeed: humanoid WalkSpeed (studs/sec)
--
-- NOTE: Numbers here are starter defaults; tune for balance.

export type UnitParams = {
	AttackRange: number,
	Damage: number,
	Health: number,
	MoveSpeed: number,
}

return {
	Cavalry = {
		Mage = {
			AttackRange = 40,
			Damage = 22,
			Health = 110,
			MoveSpeed = 22,
		} :: UnitParams,
		Spearman = {
			AttackRange = 10,
			Damage = 18,
			Health = 140,
			MoveSpeed = 24,
		} :: UnitParams,
		Swordsman = {
			AttackRange = 10,
			Damage = 20,
			Health = 150,
			MoveSpeed = 24,
		} :: UnitParams,
		Archer = {
			AttackRange = 55,
			Damage = 16,
			Health = 100,
			MoveSpeed = 22,
		} :: UnitParams,
		Crossbowman = {
			AttackRange = 60,
			Damage = 18,
			Health = 105,
			MoveSpeed = 22,
		} :: UnitParams,
	},

	Infantry = {
		Mage = {
			AttackRange = 40,
			Damage = 20,
			Health = 95,
			MoveSpeed = 16,
		} :: UnitParams,
		Spearman = {
			AttackRange = 10,
			Damage = 16,
			Health = 125,
			MoveSpeed = 16,
		} :: UnitParams,
		Swordsman = {
			AttackRange = 10,
			Damage = 18,
			Health = 130,
			MoveSpeed = 16,
		} :: UnitParams,
		Archer = {
			AttackRange = 55,
			Damage = 14,
			Health = 85,
			MoveSpeed = 16,
		} :: UnitParams,
		Crossbowman = {
			AttackRange = 60,
			Damage = 16,
			Health = 90,
			MoveSpeed = 16,
		} :: UnitParams,
		Polearmman = {
			AttackRange = 12,
			Damage = 17,
			Health = 135,
			MoveSpeed = 16,
		} :: UnitParams,
	},
}
