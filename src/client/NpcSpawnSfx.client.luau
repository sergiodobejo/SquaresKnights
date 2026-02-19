-- PATH: StarterPlayer.StarterPlayerScripts.NpcSpawnSfx
-- Plays NPC spawn SFX only for the owning player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ShopConfig"))
local NpcSpawnSounds = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("NpcSpawnSounds"))
local SoundCache = require(ReplicatedStorage:WaitForChild("Libs"):WaitForChild("SoundCache"))

local LOCAL_PLAYER = Players.LocalPlayer
local rng = Random.new()

local function buildItemNameByNpcModelName(): { [string]: string }
	local map: { [string]: string } = {}
	local items = (ShopConfig :: any).Config and (ShopConfig :: any).Config.Items
	if type(items) ~= "table" then
		return map
	end

	for itemName, cfg in pairs(items) do
		if type(itemName) == "string" and type(cfg) == "table" then
			if cfg.ItemKind == "npc" then
				local npcModelName = cfg.NpcModelName
				if type(npcModelName) == "string" and npcModelName ~= "" then
					map[npcModelName] = itemName
				end
			end
		end
	end

	return map
end

local ITEM_NAME_BY_NPC_MODEL_NAME = buildItemNameByNpcModelName()

local function playSpawnSfxForNpc(npc: Model)
	if Affiliation.GetOwnerUserIdFromModel(npc) ~= LOCAL_PLAYER.UserId then
		return
	end

	local itemName = ITEM_NAME_BY_NPC_MODEL_NAME[npc.Name]
	if type(itemName) ~= "string" or itemName == "" then
		return
	end

	local soundIds = (NpcSpawnSounds :: any).ResolveByItemName(itemName)
	if type(soundIds) ~= "table" or #soundIds == 0 then
		return
	end

	local soundId = soundIds[rng:NextInteger(1, #soundIds)]
	SoundCache.Play(soundId, {
		parent = SoundService,
		poolSize = 3,
	})
end

task.defer(function()
	local liveNpcFolder = Workspace:FindFirstChild("LiveNPC")
	if not liveNpcFolder then
		liveNpcFolder = Workspace:WaitForChild("LiveNPC", 30)
	end
	if not liveNpcFolder or not liveNpcFolder:IsA("Folder") then
		return
	end

	liveNpcFolder.ChildAdded:Connect(function(child: Instance)
		if not child:IsA("Model") then
			return
		end
		playSpawnSfxForNpc(child :: Model)
	end)
end)

return {}
