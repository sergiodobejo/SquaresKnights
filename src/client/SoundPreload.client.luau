-- PATH: StarterPlayer.StarterPlayerScripts.SoundPreload
-- Preload commonly-used sounds on the client to avoid first-play latency.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SoundCache = require(ReplicatedStorage:WaitForChild("Libs"):WaitForChild("SoundCache"))
local AttackSounds = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("AttackSounds"))

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

local function collectAttackSoundIds(): { string }
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}

	local config = (AttackSounds :: any).Config
	if type(config) ~= "table" then
		return ids
	end

	for _, list in pairs(config) do
		if type(list) == "table" then
			for _, raw in ipairs(list) do
				local n = normalizeSoundId(raw)
				if n and not seen[n] then
					seen[n] = true
					table.insert(ids, n)
				end
			end
		end
	end

	return ids
end

-- Known one-off SFX (server-spawned, but preloading client-side removes first-play delay).
local CASTLE_DESTROYED_SFX_ID = "rbxassetid://83808819886243"
local CAPTURE_SUCCESS_SFX_ID = "rbxassetid://104267438913431"

-- Shop UI sounds (same IDs as in Shop GUI script).
local NOT_ENOUGH_MONEY_SOUND_ID = "rbxassetid://71887292352019"
local SHOP_SUCCESS_SOUND_ID = "rbxassetid://117006835091805"

local all: { string } = {}
for _, id in ipairs(collectAttackSoundIds()) do
	table.insert(all, id)
end
for _, id in ipairs({ CASTLE_DESTROYED_SFX_ID, NOT_ENOUGH_MONEY_SOUND_ID, SHOP_SUCCESS_SOUND_ID }) do
	local n = normalizeSoundId(id)
	if n then
		table.insert(all, n)
	end
end

do
	local n = normalizeSoundId(CAPTURE_SUCCESS_SFX_ID)
	if n then
		table.insert(all, n)
	end
end

-- PoolSize=1 keeps memory low; this is only to preload content.
SoundCache.Preload(all, {
	parent = SoundService,
	poolSize = 1,
})

return {}
