-- ServerScriptService.Services.NpcDamagePopupService

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage:WaitForChild("RemoteNames"))

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function getOrCreateRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local remotesFolder = getOrCreateFolder(ReplicatedStorage, "Remotes")
local npcDamagePopupRemote = getOrCreateRemoteEvent(remotesFolder, RemoteNames.NpcDamagePopup)

local lastHealthByNpc: { [Model]: number } = setmetatable({}, { __mode = "k" })
local connByNpc: { [Model]: RBXScriptConnection } = setmetatable({}, { __mode = "k" })

local HRP_NO_COLLISION_AFTER_SECONDS = 5

local function getHumanoid(model: Model): Humanoid?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end
	local maybe = model:FindFirstChild("Humanoid")
	if maybe and maybe:IsA("Humanoid") then
		return maybe
	end
	return nil
end

local NpcDamagePopupService = {}

function NpcDamagePopupService.TrackNpc(npc: Model)
	if connByNpc[npc] then
		return
	end

	local humanoid = getHumanoid(npc)
	if not humanoid then
		return
	end

	lastHealthByNpc[npc] = humanoid.Health

	-- After a short lifetime, disable collisions on HRP to reduce crowd jamming.
	-- Applies to both team NPCs and AI NPCs (anything we track here).
	local hrp = npc:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local rootPart: BasePart = hrp
		task.delay(HRP_NO_COLLISION_AFTER_SECONDS, function()
			if npc.Parent == nil or rootPart.Parent == nil then
				return
			end
			pcall(function()
				rootPart.CanCollide = false
			end)
		end)
	end

	connByNpc[npc] = humanoid.HealthChanged:Connect(function(health: number)
		local last = lastHealthByNpc[npc]
		lastHealthByNpc[npc] = health

		if typeof(last) ~= "number" then
			return
		end

		local delta = last - health
		if delta <= 0 then
			return
		end

		-- Ignore ultra-tiny changes (regen rounding, etc.)
		if delta < 0.5 then
			return
		end

		local amount = math.max(1, math.floor(delta + 0.5))
		npcDamagePopupRemote:FireAllClients(npc, amount)
	end)

	npc.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil then
			return
		end
		local conn = connByNpc[npc]
		if conn then
			connByNpc[npc] = nil
			conn:Disconnect()
		end
		lastHealthByNpc[npc] = nil
	end)
end

return NpcDamagePopupService
