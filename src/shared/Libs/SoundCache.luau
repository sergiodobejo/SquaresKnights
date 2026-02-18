-- ReplicatedStorage.Libs.SoundCache
-- Lightweight sound caching + optional preload to avoid first-play latency.

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local SoundCache = {}

export type Options = {
	parent: Instance?,
	volume: number?,
	playbackSpeed: number?,
	rollOffMode: Enum.RollOffMode?,
	rollOffMaxDistance: number?,
	poolSize: number?,
}

type Pool = {
	sounds: { Sound },
	nextIndex: number,
}

local poolsByKey: { [string]: Pool } = {}

local function keyFor(soundId: string, parent: Instance): string
	return soundId .. "|" .. parent:GetFullName()
end

local function applyOptions(sound: Sound, soundId: string, options: Options)
	sound.SoundId = soundId
	if options.volume ~= nil then
		sound.Volume = options.volume
	elseif sound.Volume == 0 then
		sound.Volume = 1
	end
	if options.playbackSpeed ~= nil then
		sound.PlaybackSpeed = options.playbackSpeed
	end
	if options.rollOffMode ~= nil then
		sound.RollOffMode = options.rollOffMode
	end
	if options.rollOffMaxDistance ~= nil then
		sound.RollOffMaxDistance = options.rollOffMaxDistance
	end
end

local function ensurePool(soundId: string, options: Options): Pool
	local parent = options.parent or SoundService
	local poolSize = options.poolSize
	if type(poolSize) ~= "number" or poolSize < 1 then
		poolSize = 3
	end
	poolSize = math.floor(poolSize)

	local k = keyFor(soundId, parent)
	local existing = poolsByKey[k]
	if existing then
		-- Make sure the instances still exist.
		local alive = 0
		for _, s in ipairs(existing.sounds) do
			if s and s:IsA("Sound") and s:IsDescendantOf(game) then
				alive += 1
			end
		end
		if alive == #existing.sounds then
			return existing
		end
	end

	local pool: Pool = { sounds = {}, nextIndex = 1 }
	for i = 1, poolSize do
		local sound = Instance.new("Sound")
		sound.Name = "CachedSound"
		applyOptions(sound, soundId, options)
		-- Default for UI-style 2D sounds.
		if options.rollOffMode == nil then
			sound.RollOffMode = Enum.RollOffMode.Inverse
		end
		sound.Parent = parent
		table.insert(pool.sounds, sound)
	end

	poolsByKey[k] = pool
	return pool
end

function SoundCache.Preload(soundIds: { any }, options: Options?)
	local opts: Options = options or {}
	local instances: { Instance } = {}
	for _, raw in ipairs(soundIds) do
		if type(raw) == "string" and raw ~= "" then
			local pool = ensurePool(raw, opts)
			for _, s in ipairs(pool.sounds) do
				table.insert(instances, s)
			end
		end
	end
	if #instances == 0 then
		return
	end
	pcall(function()
		ContentProvider:PreloadAsync(instances)
	end)
end

function SoundCache.Play(soundId: any, options: Options?)
	if type(soundId) ~= "string" or soundId == "" then
		return
	end
	local opts: Options = options or {}
	local pool = ensurePool(soundId, opts)
	if #pool.sounds == 0 then
		return
	end

	local i = pool.nextIndex
	pool.nextIndex += 1
	if pool.nextIndex > #pool.sounds then
		pool.nextIndex = 1
	end

	local sound = pool.sounds[i]
	if not sound or not sound:IsA("Sound") then
		return
	end

	-- Keep properties fresh for cases where caller supplies different options.
	applyOptions(sound, soundId, opts)

	pcall(function()
		sound:Stop()
	end)
	pcall(function()
		sound.TimePosition = 0
	end)
	pcall(function()
		sound:Play()
	end)
end

return SoundCache
