-- PATH: ReplicatedStorage.Configs.ShopConfig
-- Shop item definitions.
--
-- Items are NPC units (not buffs): buying spawns the unit.

local Config = {
	Items = {
		-- NOTE: items are keyed by NPC model name.
		-- This is intentional: there can be multiple models for the same UnitKind/UnitClass.
		
		-- Cavalry
		["Cavalry_Scout"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Cavalry_Scout",
			Price = 14,
			RobuxPrice = 14,
			DevProductId = 0,
		},
		["Cavalry_Crossbowman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Cavalry_Crossbowman",
			Price = 18,
			RobuxPrice = 18,
			DevProductId = 0,
		},
		["Cavalry_Mage"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Cavalry_Mage",
			Price = 16,
			RobuxPrice = 16,
			DevProductId = 0,
		},
		["Cavalry_Paladin"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_Cavalry_Paladin",
			Price = 19,
			RobuxPrice = 19,
			DevProductId = 0,
		},
		["Cavalry_Priest"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_Cavalry_Priest",
			Price = 21,
			RobuxPrice = 21,
			DevProductId = 0,
		},
		["Knight"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Knight",
			Price = 22,
			RobuxPrice = 22,
			DevProductId = 0,
		},
		["Cavalry_King"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Cavalry_King",
			Price = 23,
			RobuxPrice = 23,
			DevProductId = 0,
		},
		["Heavy_Cavalry"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Heavy_Cavalry",
			Price = 24,
			RobuxPrice = 24,
			DevProductId = 0,
		},
		["Light_Cavalry"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Light_Cavalry",
			Price = 20,
			RobuxPrice = 20,
			DevProductId = 0,
		},

		-- Infantry
		["Archer"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Archer",
			Price = 6,
			RobuxPrice = 6,
			DevProductId = 0,
		},
		["Scout"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_Scout",
			Price = 8,
			RobuxPrice = 8,
			DevProductId = 0,
		},
		["Crossbowman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Crossbowman",
			Price = 12,
			RobuxPrice = 12,
			DevProductId = 0,
		},
		["HighPriest"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_HighPriest",
			Price = 10,
			RobuxPrice = 10,
			DevProductId = 0,
		},
		["Mage"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Mage",
			Price = 4,
			RobuxPrice = 4,
			DevProductId = 0,
		},
		["Priest"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_Priest",
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 0,
		},
		["Halberdier"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Halberdier",
			Price = 5,
			RobuxPrice = 5,
			DevProductId = 0,
		},
		["Spearman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Spearman",
			Price = 2,
			RobuxPrice = 2,
			DevProductId = 0,
		},
		["HeavySwordman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_HeavySwordman",
			Price = 7,
			RobuxPrice = 7,
			DevProductId = 0,
		},
		["Heavy_Infantry"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Heavy_Infantry",
			Price = 17,
			RobuxPrice = 17,
			DevProductId = 0,
		},
		["King"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_King",
			Price = 11,
			RobuxPrice = 11,
			DevProductId = 0,
		},
		["Light_Infantry"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Light_Infantry",
			Price = 13,
			RobuxPrice = 13,
			DevProductId = 0,
		},
		["Paladin"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_Paladin",
			Price = 15,
			RobuxPrice = 15,
			DevProductId = 0,
		},
		["Swordman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Swordman",
			Price = 3,
			RobuxPrice = 3,
			DevProductId = 0,
		},
		["Commander"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "sk_Commander",
			Price = 9,
			RobuxPrice = 9,
			DevProductId = 0,
		},
	},
}

local Shared = {}

Shared.Config = Config

function Shared.GetConfig(package: string)
	return Config.Items[package]
end

function Shared.GetItemType(package: string)
	local itemConfig = Config.Items[package]
	if itemConfig then
		return itemConfig.ItemKind or "npc"
	end
	return nil
end

function Shared.GetBillboardStyle(effectName: string): (string?, Color3?)
	return nil, nil
end

return Shared

