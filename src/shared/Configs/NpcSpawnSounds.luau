-- PATH: ReplicatedStorage.Configs.NpcSpawnSounds
-- Per-shop-item spawn SFX configuration.
--
-- Config.ByItemName maps ShopConfig item keys (e.g. "Archer") to one or more SoundIds.
-- One sound is randomly picked from the list and played when an NPC of that shop item spawns.

export type SoundId = string

local DEFAULT_SPAWN_SFX: SoundId = "rbxassetid://101926158430042"

local Config = {
	Default = { DEFAULT_SPAWN_SFX },
	ByItemName = {
		-- Cavalry
		Cavalry_Scout = { "rbxassetid://72484510950310" },
		Cavalry_Crossbowman = { "rbxassetid://117336841077049" },
		Cavalry_Mage = { "rbxassetid://124895488161456" },
		Cavalry_Paladin = { DEFAULT_SPAWN_SFX },
		Cavalry_Priest = { "rbxassetid://73304269684496" },
		Knight = { "rbxassetid://137006360293094" },
		Cavalry_King = { DEFAULT_SPAWN_SFX },
		Heavy_Cavalry = { "rbxassetid://136605408817999" },
		Light_Cavalry = { "rbxassetid://87139065609255" },

		-- Infantry
		Archer = { "rbxassetid://73331298516808" },
		Scout = { DEFAULT_SPAWN_SFX },
		Crossbowman = { "rbxassetid://137788185980035" },
		HighPriest = { "rbxassetid://137776318301322" },
		Mage = { "rbxassetid://87964808775828" },
		Priest = { "rbxassetid://77243821070945" },
		Halberdier = { "rbxassetid://127035885508004" },
		Spearman = { "rbxassetid://108335321818228" },
		HeavySwordman = { "rbxassetid://77181510090379" },
		Heavy_Infantry = { "rbxassetid://87816980152858" },
		King = { DEFAULT_SPAWN_SFX },
		Light_Infantry = { "rbxassetid://127491733894160" },
		Paladin = { DEFAULT_SPAWN_SFX },
		Swordman = { "rbxassetid://123292748078166" },
		Commander = { "rbxassetid://87811869378817"},
	},
}

local function normalizeSoundId(id: any): string?
	if type(id) ~= "string" then
		return nil
	end
	local trimmed = id:gsub("%s+", "")
	if trimmed == "" then
		return nil
	end
	if trimmed:match("^rbxassetid://%d+$") then
		return trimmed
	end
	if trimmed:match("^%d+$") then
		return "rbxassetid://" .. trimmed
	end
	return nil
end

local function normalizeSoundList(list: any, fallback: { SoundId }): { SoundId }
	if type(list) ~= "table" then
		return fallback
	end
	local out: { SoundId } = {}
	for _, raw in ipairs(list) do
		local n = normalizeSoundId(raw)
		if n then
			table.insert(out, n)
		end
	end
	if #out == 0 then
		return fallback
	end
	return out
end

local Shared = {}
Shared.Config = Config

function Shared.ResolveByItemName(itemName: any): { SoundId }
	local defaultList = normalizeSoundList(Config.Default, { DEFAULT_SPAWN_SFX })
	if type(itemName) ~= "string" or itemName == "" then
		return defaultList
	end
	local raw = (Config.ByItemName :: any)[itemName]
	return normalizeSoundList(raw, defaultList)
end

function Shared.CollectAllSoundIds(): { SoundId }
	local ids: { SoundId } = {}
	local seen: { [string]: boolean } = {}

	local function addList(list: any)
		if type(list) ~= "table" then
			return
		end
		for _, raw in ipairs(list) do
			local n = normalizeSoundId(raw)
			if n and not seen[n] then
				seen[n] = true
				table.insert(ids, n)
			end
		end
	end

	addList(Config.Default)
	for _, list in pairs(Config.ByItemName) do
		addList(list)
	end

	return ids
end

return Shared
