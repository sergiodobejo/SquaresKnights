-- ReplicatedStorage.Configs.CastleUnderAttackSounds
-- Sounds to play while the player's castle is under attack.

export type SoundId = string

local Config = {
	Ids = {
		"rbxassetid://92657531361189",
		"rbxassetid://90319881048879",
		"rbxassetid://120261104825089",
		"rbxassetid://74014707684980",
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

local function collectAllSoundIds(): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local ids = (Config :: any).Ids
	if type(ids) ~= "table" then
		return out
	end
	for _, raw in ipairs(ids) do
		local n = normalizeSoundId(raw)
		if n and not seen[n] then
			seen[n] = true
			table.insert(out, n)
		end
	end
	return out
end

local function resolveRandom(): string?
	local ids = collectAllSoundIds()
	if #ids == 0 then
		return nil
	end
	return ids[math.random(1, #ids)]
end

return {
	Config = Config,
	ResolveRandom = resolveRandom,
	CollectAllSoundIds = collectAllSoundIds,
}
