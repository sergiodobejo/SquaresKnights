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
			DevProductId = 3539825367,
		},
		["Cavalry_Crossbowman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Cavalry_Crossbowman",
			Price = 18,
			RobuxPrice = 18,
			DevProductId = 3539825580,
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
			DevProductId = 3539826087,
		},
		["Cavalry_Priest"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_Cavalry_Priest",
			Price = 21,
			RobuxPrice = 21,
			DevProductId = 3539826158,
		},
		["Knight"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Knight",
			Price = 22,
			RobuxPrice = 22,
			DevProductId = 3539826240,
		},
		["Cavalry_King"] = {
			ItemKind = "npc",
			Enabled = false,
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
			DevProductId = 3539826533,
		},
		["Light_Cavalry"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Light_Cavalry",
			Price = 20,
			RobuxPrice = 20,
			DevProductId = 3539826864,
		},

		-- Infantry
		["Archer"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Archer",
			Price = 6,
			RobuxPrice = 6,
			DevProductId = 3539827010,
		},
		["Scout"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_Scout",
			Price = 8,
			RobuxPrice = 8,
			DevProductId = 3539827178,
		},
		["Crossbowman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Crossbowman",
			Price = 12,
			RobuxPrice = 12,
			DevProductId = 3539827307,
		},
		["HighPriest"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_HighPriest",
			Price = 10,
			RobuxPrice = 10,
			DevProductId = 3539827568,
		},
		["Mage"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Mage",
			Price = 4,
			RobuxPrice = 4,
			DevProductId = 3539827768,
		},
		["Priest"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_Priest",
			Price = 1,
			RobuxPrice = 1,
			DevProductId = 3539828023,
		},
		["Halberdier"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Halberdier",
			Price = 5,
			RobuxPrice = 5,
			DevProductId = 3539828192,
		},
		["Spearman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Spearman",
			Price = 2,
			RobuxPrice = 2,
			DevProductId = 3539828334,
		},
		["HeavySwordman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_HeavySwordman",
			Price = 7,
			RobuxPrice = 7,
			DevProductId = 3539828474,
		},
		["Heavy_Infantry"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Heavy_Infantry",
			Price = 17,
			RobuxPrice = 17,
			DevProductId = 3539828652,
		},
		["King"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_King",
			Price = 11,
			RobuxPrice = 11,
			DevProductId = 3539828814,
		},
		["Light_Infantry"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Light_Infantry",
			Price = 13,
			RobuxPrice = 13,
			DevProductId = 3539828980,
		},
		["Paladin"] = {
			ItemKind = "npc",
			Enabled = false,
			NpcModelName = "SK_Paladin",
			Price = 15,
			RobuxPrice = 15,
			DevProductId = 3539829150,
		},
		["Swordman"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "SK_Swordman",
			Price = 3,
			RobuxPrice = 3,
			DevProductId = 3539829318,
		},
		["Commander"] = {
			ItemKind = "npc",
			Enabled = true,
			NpcModelName = "sk_Commander",
			Price = 9,
			RobuxPrice = 9,
			DevProductId = 3539829506,
		},
	},
}

local Shared = {}

Shared.Config = Config

local PRICE_BY_NPC_MODEL_NAME: { [string]: number } = {}
local PRICE_BY_NPC_MODEL_NAME_LOWER: { [string]: number } = {}
for _, itemConfig in pairs(Config.Items) do
	if type(itemConfig) == "table" then
		local npcModelName = itemConfig.NpcModelName
		local price = itemConfig.Price
		if type(npcModelName) == "string" and npcModelName ~= "" and type(price) == "number" then
			PRICE_BY_NPC_MODEL_NAME[npcModelName] = price
			PRICE_BY_NPC_MODEL_NAME_LOWER[npcModelName:lower()] = price
		end
	end
end

function Shared.GetPriceForNpcModelName(npcModelName: any): number?
	if type(npcModelName) ~= "string" or npcModelName == "" then
		return nil
	end
	local direct = PRICE_BY_NPC_MODEL_NAME[npcModelName]
	if type(direct) == "number" then
		return direct
	end
	return PRICE_BY_NPC_MODEL_NAME_LOWER[npcModelName:lower()]
end

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

