-- ServerScriptService.Services.WarriorValueService
-- Tracks the total "warrior value" (sum of coin prices) of purchased NPC units owned by each player.
--
-- Rules:
-- - On successful purchase/grant of an NPC unit, add its coin Price.
--   (Even if it was purchased for Robux.)
-- - On NPC death (or removal), subtract its tracked cost.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ShopConfig"))

local TRACKED_ATTRIBUTE = "WarriorValueTracked"
local COST_ATTRIBUTE = "WarriorValueCost"
local SUBTRACTED_ATTRIBUTE = "WarriorValueSubtracted"

local ValueByUserId: { [number]: number } = {}

local function normalizeCost(cost: any): number
	if type(cost) ~= "number" then
		return 0
	end
	if cost ~= cost or cost <= 0 then
		return 0
	end
	return math.floor(cost)
end

local function addForUserId(userId: number, delta: number)
	if type(userId) ~= "number" or userId <= 0 then
		return
	end
	local current = ValueByUserId[userId] or 0
	local nextValue = current + math.floor(delta)
	if nextValue < 0 then
		nextValue = 0
	end
	ValueByUserId[userId] = nextValue

	local player = Players:GetPlayerByUserId(userId)
	if player then
		pcall(function()
			player:SetAttribute("WarriorValue", nextValue)
		end)
	end
end

local function getHumanoid(model: Model): Humanoid?
	local h = model:FindFirstChildOfClass("Humanoid")
	if h then
		return h
	end
	local maybe = model:FindFirstChild("Humanoid")
	if maybe and maybe:IsA("Humanoid") then
		return maybe
	end
	return nil
end

local function subtractOnce(npc: Model)
	if npc:GetAttribute(SUBTRACTED_ATTRIBUTE) == true then
		return
	end
	pcall(function()
		npc:SetAttribute(SUBTRACTED_ATTRIBUTE, true)
	end)

	local cost = normalizeCost(npc:GetAttribute(COST_ATTRIBUTE))
	if cost <= 0 then
		return
	end

	local ownerUserId = Affiliation.GetOwnerUserIdFromModel(npc)
	if ownerUserId <= 0 then
		return
	end

	addForUserId(ownerUserId, -cost)
end

local WarriorValueService = {}

local function resolveCostForNpc(npc: Model): number
	-- Prefer explicit attribute if someone sets it.
	local attr = npc:GetAttribute("NpcModelName")
	if type(attr) == "string" and attr ~= "" then
		local price = ShopConfig.GetPriceForNpcModelName(attr)
		if type(price) == "number" then
			return normalizeCost(price)
		end
	end

	-- Default: the model Name is the template model name (e.g. SK_Archer).
	local price = ShopConfig.GetPriceForNpcModelName(npc.Name)
	if type(price) == "number" then
		return normalizeCost(price)
	end

	return 0
end

function WarriorValueService.GetWarriorValueByUserId(userId: number): number
	local v = ValueByUserId[userId]
	if type(v) ~= "number" then
		return 0
	end
	return v
end

function WarriorValueService.GetWarriorValue(player: Player): number
	return WarriorValueService.GetWarriorValueByUserId(player.UserId)
end

-- Auto-track any owned NPC with a known ShopConfig coin Price.
-- Safe to call multiple times.
function WarriorValueService.MaybeTrackNpc(npc: Model)
	if not npc then
		return
	end
	if not npc:IsA("Model") then
		return
	end
	if npc:GetAttribute(TRACKED_ATTRIBUTE) == true then
		return
	end

	local ownerUserId = Affiliation.GetOwnerUserIdFromModel(npc)
	if ownerUserId <= 0 then
		return
	end

	local cost = resolveCostForNpc(npc)
	if cost <= 0 then
		return
	end

	-- Mark + hook death/removal, then apply.
	pcall(function()
		npc:SetAttribute(TRACKED_ATTRIBUTE, true)
		npc:SetAttribute(COST_ATTRIBUTE, cost)
		npc:SetAttribute(SUBTRACTED_ATTRIBUTE, false)
	end)

	addForUserId(ownerUserId, cost)

	local humanoid = getHumanoid(npc)
	if humanoid then
		humanoid.Died:Connect(function()
			subtractOnce(npc)
		end)
	end

	npc.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			subtractOnce(npc)
		end
	end)
end

-- Call this ONLY when the NPC was granted via a successful purchase (coins or Robux).
function WarriorValueService.RegisterPurchasedNpc(player: Player, npc: Model, costCoins: any)
	if not (player and npc) then
		return
	end
	if not npc:IsA("Model") then
		return
	end

	local cost = normalizeCost(costCoins)
	if cost <= 0 then
		return
	end

	if npc:GetAttribute(TRACKED_ATTRIBUTE) == true then
		return
	end

	pcall(function()
		npc:SetAttribute(TRACKED_ATTRIBUTE, true)
		npc:SetAttribute(COST_ATTRIBUTE, cost)
		npc:SetAttribute(SUBTRACTED_ATTRIBUTE, false)
	end)

	addForUserId(player.UserId, cost)

	local humanoid = getHumanoid(npc)
	if humanoid then
		humanoid.Died:Connect(function()
			subtractOnce(npc)
		end)
	end

	-- Backup: if the model gets removed without a Humanoid death.
	npc.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			subtractOnce(npc)
		end
	end)
end

-- Best-effort catch-all for NPCs spawned outside of our known code paths.
task.defer(function()
	local liveNpcFolder = workspace:FindFirstChild("LiveNPC")
	if liveNpcFolder and liveNpcFolder:IsA("Folder") then
		for _, child in ipairs(liveNpcFolder:GetChildren()) do
			if child:IsA("Model") then
				WarriorValueService.MaybeTrackNpc(child)
			end
		end
		liveNpcFolder.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				-- Delay a tick so affiliation stamps/attributes are present.
				task.defer(function()
					WarriorValueService.MaybeTrackNpc(child)
				end)
			end
		end)
	end
end)

-- Cleanup to avoid stale values for players who leave.
Players.PlayerRemoving:Connect(function(player)
	ValueByUserId[player.UserId] = nil
end)

return WarriorValueService
