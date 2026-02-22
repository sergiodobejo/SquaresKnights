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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ShopConfig"))

local ByKindClass = {
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

-- Optional overrides keyed by ShopConfig item keys.
-- Example:
--   ByShopKey["Priest"] = { AttackRange=20, Damage=3, Health=120, MoveSpeed=6 }
local ByShopKey: { [string]: WarriorCombatStats } = {
	["Archer"] = { AttackRange = 25, Damage = 2, Health = 80, MoveSpeed = 6 },
	["Cavalry_Crossbowman"] = { AttackRange = 30, Damage = 3, Health = 96, MoveSpeed = 8 },
	["Cavalry_King"] = { AttackRange = 13, Damage = 20, Health = 150, MoveSpeed = 8 },
	["Cavalry_Mage"] = { AttackRange = 30, Damage = 5, Health = 100, MoveSpeed = 8 },
	["Cavalry_Paladin"] = { AttackRange = 30, Damage = 6, Health = 100, MoveSpeed = 8 },
	["Cavalry_Priest"] = { AttackRange = 30, Damage = 7, Health = 100, MoveSpeed = 8 },
	["Cavalry_Scout"] = { AttackRange = 29, Damage = 4, Health = 99, MoveSpeed = 8 },
	["Commander"] = { AttackRange = 10, Damage = 20, Health = 95, MoveSpeed = 6 },
	["Crossbowman"] = { AttackRange = 29, Damage = 3, Health = 85, MoveSpeed = 6 },
	["Halberdier"] = { AttackRange = 12, Damage = 17, Health = 95, MoveSpeed = 6 },
	["HeavySwordman"] = { AttackRange = 10, Damage = 19, Health = 96, MoveSpeed = 6 },
	["Heavy_Cavalry"] = { AttackRange = 13, Damage = 24, Health = 175, MoveSpeed = 8 },
	["Heavy_Infantry"] = { AttackRange = 10, Damage = 20, Health = 97, MoveSpeed = 6 },
	["HighPriest"] = { AttackRange = 25, Damage = 4, Health = 75, MoveSpeed = 6 },
	["King"] = { AttackRange = 10, Damage = 21, Health = 95, MoveSpeed = 6 },
	["Knight"] = { AttackRange = 15, Damage = 22, Health = 160, MoveSpeed = 8 },
	["Light_Cavalry"] = { AttackRange = 13, Damage = 19, Health = 150, MoveSpeed = 8 },
	["Light_Infantry"] = { AttackRange = 10, Damage = 18, Health = 95, MoveSpeed = 6 },
	["Mage"] = { AttackRange = 23, Damage = 3, Health = 75, MoveSpeed = 6 },
	["Paladin"] = { AttackRange = 10, Damage = 22, Health = 95, MoveSpeed = 6 },
	["Priest"] = { AttackRange = 20, Damage = 1, Health = 35, MoveSpeed = 6 },
	["Scout"] = { AttackRange = 25, Damage = 3, Health = 85, MoveSpeed = 6 },
	["Spearman"] = { AttackRange = 12, Damage = 16, Health = 90, MoveSpeed = 6 },
	["Swordman"] = { AttackRange = 10, Damage = 18, Health = 95, MoveSpeed = 6 },
}

local function sortedKeys(tbl: any): { string }
	local keys: { string } = {}
	if type(tbl) ~= "table" then
		return keys
	end
	for k, _ in pairs(tbl) do
		if type(k) == "string" then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	return keys
end

local function findKeyCaseInsensitive(tbl: any, desiredKey: string): string?
	if type(tbl) ~= "table" then
		return nil
	end
	if type(desiredKey) ~= "string" or desiredKey == "" then
		return nil
	end
	if tbl[desiredKey] ~= nil then
		return desiredKey
	end
	local desiredLower = desiredKey:lower()
	for k, _ in pairs(tbl) do
		if type(k) == "string" and k:lower() == desiredLower then
			return k
		end
	end
	return nil
end

local function resolveByKindClass(unitKind: string, unitClass: string): WarriorCombatStats?
	local kindKey = findKeyCaseInsensitive(ByKindClass, unitKind)
	local kindTable = if kindKey then ByKindClass[kindKey] else nil
	if type(kindTable) ~= "table" then
		return nil
	end
	local classKey = findKeyCaseInsensitive(kindTable, unitClass)
	local classStats = if classKey then kindTable[classKey] else nil
	if type(classStats) ~= "table" then
		return nil
	end
	return classStats :: any
end

local function resolveByShopKey(shopKey: string): WarriorCombatStats?
	local overrideKey = findKeyCaseInsensitive(ByShopKey, shopKey)
	if overrideKey then
		return ByShopKey[overrideKey]
	end

	-- Allows driving combat stats by the key used in ShopConfig (e.g. "Priest").
	-- We map ShopKey -> NpcModelName -> template attributes (UnitKind/UnitClass) -> ByKindClass.
	local cfg = ShopConfig.GetConfig(shopKey)
	if type(cfg) ~= "table" then
		return nil
	end
	local npcModelName = (cfg :: any).NpcModelName
	if type(npcModelName) ~= "string" or npcModelName == "" then
		return nil
	end
	local npcRoot = ReplicatedStorage:FindFirstChild("NPC")
	if not npcRoot then
		return nil
	end
	local template = npcRoot:FindFirstChild(npcModelName, true)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local unitKind = (template :: Model):GetAttribute("UnitKind")
	local unitClass = (template :: Model):GetAttribute("UnitClass")
	if type(unitKind) ~= "string" or type(unitClass) ~= "string" then
		return nil
	end
	return resolveByKindClass(unitKind, unitClass)
end

local SHOP_KEY_ATTRIBUTE = "ShopKey"

local Shared = {}

Shared.ByKindClass = ByKindClass
Shared.ByShopKey = ByShopKey
Shared.ShopKeyAttribute = SHOP_KEY_ATTRIBUTE

-- Back-compat: allow old indexing style `CombatParams.Cavalry.Mage`.
for kindKey, kindTable in pairs(ByKindClass) do
	(Shared :: any)[kindKey] = kindTable
end

function Shared.ResolveByKindClass(unitKind: string, unitClass: string): WarriorCombatStats?
	return resolveByKindClass(unitKind, unitClass)
end

function Shared.ResolveByShopKey(shopKey: string): WarriorCombatStats?
	return resolveByShopKey(shopKey)
end

function Shared.ResolveForModel(model: Model): WarriorCombatStats?
	local shopKey = model:GetAttribute(SHOP_KEY_ATTRIBUTE)
	if type(shopKey) == "string" and shopKey ~= "" then
		local byShop = resolveByShopKey(shopKey)
		if byShop then
			return byShop
		end
	end

	local unitKind = model:GetAttribute("UnitKind")
	local unitClass = model:GetAttribute("UnitClass")
	if type(unitKind) == "string" and unitKind ~= "" and type(unitClass) == "string" and unitClass ~= "" then
		return resolveByKindClass(unitKind, unitClass)
	end

	return nil
end

function Shared.PrintByShopKeyDefaults()
	-- Prints a ready-to-paste ByShopKey table (with numeric values) for every ShopConfig item.
	-- Usage in Studio Command Bar:
	--   local ReplicatedStorage = game:GetService("ReplicatedStorage")
	--   local CombatParams = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CombatParams"))
	--   CombatParams.PrintByShopKeyDefaults()
	local items = (ShopConfig :: any).Config and (ShopConfig :: any).Config.Items
	if type(items) ~= "table" then
		warn("[CombatParams] ShopConfig.Config.Items not found")
		return
	end

	print("-- Paste this into CombatParams.luau (replace ByShopKey)")
	print("local ByShopKey: { [string]: WarriorCombatStats } = {")

	local keys = sortedKeys(items)
	for _, shopKey in ipairs(keys) do
		local stats = Shared.ResolveByShopKey(shopKey)
		if stats then
			print(string.format(
				"\t[\"%s\"] = { AttackRange = %s, Damage = %s, Health = %s, MoveSpeed = %s },",
				shopKey,
				tostring(stats.AttackRange),
				tostring(stats.Damage),
				tostring(stats.Health),
				tostring(stats.MoveSpeed)
			))
		else
			local cfg = (items :: any)[shopKey]
			local modelName = cfg and (cfg :: any).NpcModelName
			print(string.format("\t-- [\"%s\"] = nil, -- unresolved (NpcModelName=%s)", shopKey, tostring(modelName)))
		end
	end

	print("}")
end

return Shared
