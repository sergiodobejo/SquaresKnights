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
			Price = 2,
			RobuxPrice = 2,
			DevProductId = 0,
		},
		["Cavalry_Crossbowman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Cavalry_Crossbowman",
			Price = 2,
			RobuxPrice = 2,
			DevProductId = 0,
		},
		["Cavalry_Mage"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Cavalry_Mage",
			Price = 2,
			RobuxPrice = 2,
			DevProductId = 0,
		},
		["Cavalry_Paladin"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_Cavalry_Paladin",
			Price = 2,
			RobuxPrice = 2,
			DevProductId = 0,
		},
		["Cavalry_Priest"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_Cavalry_Priest",
			Price = 2,
			RobuxPrice = 2,
			DevProductId = 0,
		},
		["Knight"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Knight",
			Price = 2,
			RobuxPrice = 2,
			DevProductId = 0,
		},
		["Cavalry_King"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Cavalry_King",
			Price = 2,
			RobuxPrice = 2,
			DevProductId = 0,
		},
		["Heavy_Cavalry"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Heavy_Cavalry",
			Price = 2,
			RobuxPrice = 2,
			DevProductId = 0,
		},
		["Light_Cavalry"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Light_Cavalry",
			Price = 2,
			RobuxPrice = 2,
			DevProductId = 0,
		},

		-- Infantry
		["Archer"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Archer",
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 0,
		},
		["Scout"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_Scout",
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 0,
		},
		["Crossbowman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Crossbowman",
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 0,
		},
		["HighPriest"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_HighPriest",
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 0,
		},
		["Mage"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Mage",
			Price = 1,
			RobuxPrice = 1,
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
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 0,
		},
		["Spearman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Spearman",
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 0,
		},
		["HeavySwordman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_HeavySwordman",
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 0,
		},
		["Heavy_Infantry"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Heavy_Infantry",
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 0,
		},
		["King"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_King",
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 0,
		},
		["Light_Infantry"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Light_Infantry",
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 0,
		},
		["Paladin"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_Paladin",
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 0,
		},
		["Swordman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Swordman",
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 0,
		},
		["Commander"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "sk_Commander",
			Price = 1,
			RobuxPrice = 1,
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

