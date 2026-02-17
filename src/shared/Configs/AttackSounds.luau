-- ReplicatedStorage.Configs.AttackSounds
-- Configure 0..N attack SFX per UnitClass.
--
-- Values:
--  - "" or missing key: no sound
--  - { "123", "rbxassetid://456" }: random pick

export type SoundId = string

local Config: { [string]: { SoundId } } = {
	-- Examples (fill with your IDs)
	-- Mage = { "rbxassetid://92659708154127" },
	-- Swordsman = { "123", "456" },
	Mage = { "rbxassetid://124879195670347" },
	Spearman = {"rbxassetid://113475005070643"},
	Swordsman = {"rbxassetid://77624991417774"},
	Archer = {"92659708154127"},
	Crossbowman = {"rbxassetid://136210569443951"},
	Polearmman = {"rbxassetid://79734034268791"},
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

local function pickFromList(list: any): string?
	if type(list) ~= "table" then
		return nil
	end
	local normalized: { string } = {}
	for _, v in ipairs(list) do
		local n = normalizeSoundId(v)
		if n then
			table.insert(normalized, n)
		end
	end
	if #normalized == 0 then
		return nil
	end
	if #normalized == 1 then
		return normalized[1]
	end
	return normalized[math.random(1, #normalized)]
end

local function resolveByUnitClass(unitClass: any): string?
	if type(unitClass) ~= "string" or unitClass == "" then
		return nil
	end

	-- Case-insensitive lookup
	local direct = Config[unitClass]
	if direct ~= nil then
		return pickFromList(direct)
	end
	local desiredLower = unitClass:lower()
	for k, v in pairs(Config) do
		if type(k) == "string" and k:lower() == desiredLower then
			return pickFromList(v)
		end
	end
	return nil
end

return {
	Config = Config,
	ResolveByUnitClass = resolveByUnitClass,
}
