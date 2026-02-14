-- ServerScriptService.Services.NpcDamagePopupService

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage:WaitForChild("RemoteNames"))
local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remotesFolder then
	error("[NpcDamagePopupService] Missing ReplicatedStorage/Remotes folder. Create it in Roblox Studio.")
end

local npcDamagePopupRemoteInst = (remotesFolder :: Instance):WaitForChild(RemoteNames.NpcDamagePopup, 10)
if not npcDamagePopupRemoteInst or not npcDamagePopupRemoteInst:IsA("RemoteEvent") then
	error(string.format(
		"[NpcDamagePopupService] Missing RemoteEvent ReplicatedStorage/Remotes/%s. Create it in Roblox Studio.",
		RemoteNames.NpcDamagePopup
	))
end
local npcDamagePopupRemote = npcDamagePopupRemoteInst :: RemoteEvent

local lastHealthByNpc: { [Model]: number } = (setmetatable({}, { __mode = "k" }) :: any)
local connByNpc: { [Model]: RBXScriptConnection } = (setmetatable({}, { __mode = "k" }) :: any)

local HRP_NO_COLLISION_AFTER_SECONDS = 5
local NPC_CELL_KEY_ATTRIBUTE = "CellKey"

local function snapRootToCellCenterIfStamped(npc: Model, rootPart: BasePart)
	local key = npc:GetAttribute(NPC_CELL_KEY_ATTRIBUTE)
	if type(key) ~= "string" or key == "" then
		return
	end

	local baseplate = GridCells.FindBaseplate()
	if not baseplate then
		return
	end

	local ix, iz = GridCells.ParseCellKey(key)
	if ix == nil or iz == nil then
		return
	end

	local center = GridCells.GetCellCenterWorld(baseplate, ix, iz)
	local newPos = Vector3.new(center.X, rootPart.Position.Y, center.Z)
	local rotOnly = rootPart.CFrame - rootPart.CFrame.Position

	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		rootPart.CFrame = rotOnly + newPos
	end)
end

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
			snapRootToCellCenterIfStamped(npc, rootPart)
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
