-- ServerScriptService.Services.CollisionGroupsService

local PhysicsService = game:GetService("PhysicsService")

local GROUP_NPC = "NPC"
local GROUP_PLAYERS = "Players"

local NPC_MESH_COLLIDE_AFTER_SPAWN_SECONDS = 10

local inited = false

local function registerGroup(groupName: string)
	local ok = pcall(function()
		(PhysicsService :: any):RegisterCollisionGroup(groupName)
	end)
	if not ok then
		pcall(function()
			(PhysicsService :: any):CreateCollisionGroup(groupName)
		end)
	end
end

local function setCollidable(groupA: string, groupB: string, collidable: boolean)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(groupA, groupB, collidable)
	end)
end

local function initOnce()
	if inited then
		return
	end
	inited = true

	registerGroup(GROUP_NPC)
	registerGroup(GROUP_PLAYERS)

	-- NPCs should not collide with other NPCs or with players, but should collide with the world.
	setCollidable(GROUP_NPC, GROUP_NPC, false)
	setCollidable(GROUP_NPC, GROUP_PLAYERS, false)
	setCollidable(GROUP_PLAYERS, GROUP_NPC, false)

	-- Make intent explicit (defaults are usually collidable anyway).
	setCollidable(GROUP_NPC, "Default", true)
	setCollidable(GROUP_PLAYERS, "Default", true)
end

local function setCollisionGroup(part: BasePart, groupName: string)
	pcall(function()
		part.CollisionGroup = groupName
	end)
end

local function getWorldColliderPartForNpc(npc: Model): BasePart?
	local hrp = npc:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end

	local ground = npc:FindFirstChild("GroundCollider")
	if ground and ground:IsA("BasePart") then
		return ground
	end

	local anyPart = npc:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		return anyPart
	end

	return nil
end

local function setWorldColliderForNpc(npc: Model): BasePart?
	local part = getWorldColliderPartForNpc(npc)
	if part then
		pcall(function()
			part.CanCollide = true
		end)
	end
	return part
end

local Shared = {}

Shared.Groups = {
	NPC = GROUP_NPC,
	Players = GROUP_PLAYERS,
}

function Shared.Init()
	initOnce()
end

function Shared.ApplyNpc(npc: Model)
	initOnce()

	local worldColliderPart = setWorldColliderForNpc(npc)

	local meshCollisionEnabled = true
	local descendantConn: RBXScriptConnection? = nil

	local function applyPart(part: BasePart)
		setCollisionGroup(part, GROUP_NPC)
		-- Never touch the intended root/world collider parts.
		if part.Name == "HumanoidRootPart" or part.Name == "GroundCollider" then
			return
		end
		if worldColliderPart and part == worldColliderPart then
			return
		end
		pcall(function()
			part.CanCollide = meshCollisionEnabled
		end)
	end

	for _, inst in ipairs(npc:GetDescendants()) do
		if inst:IsA("BasePart") then
			applyPart(inst)
		end
	end

	-- Keep newly added parts consistent (accessories, etc.).
	descendantConn = npc.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") then
			applyPart(inst)
		end
	end)

	-- Cleanup connection when NPC is removed.
	npc.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil then
			return
		end
		if descendantConn then
			descendantConn:Disconnect()
			descendantConn = nil
		end
	end)

	-- After a short spawn window, disable mesh collisions again.
	task.delay(NPC_MESH_COLLIDE_AFTER_SPAWN_SECONDS, function()
		meshCollisionEnabled = false
		if npc.Parent == nil then
			return
		end
		local currentWorldColliderPart = getWorldColliderPartForNpc(npc)
		for _, inst in ipairs(npc:GetDescendants()) do
			if inst:IsA("BasePart") then
				if inst.Name == "HumanoidRootPart" or inst.Name == "GroundCollider" then
					continue
				end
				if worldColliderPart and inst == worldColliderPart then
					continue
				end
				if currentWorldColliderPart and inst == currentWorldColliderPart then
					continue
				end
				pcall(function()
					(inst :: BasePart).CanCollide = false
				end)
			end
		end
	end)
end

function Shared.ApplyPlayerCharacter(character: Model)
	initOnce()
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("BasePart") then
			setCollisionGroup(inst, GROUP_PLAYERS)
		end
	end

	-- Ensure accessories added after spawn stay in the correct group.
	character.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") then
			setCollisionGroup(inst, GROUP_PLAYERS)
		end
	end)
end

return Shared
