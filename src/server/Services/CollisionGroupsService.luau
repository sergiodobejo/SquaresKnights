-- ServerScriptService.Services.CollisionGroupsService

local PhysicsService = game:GetService("PhysicsService")

local GROUP_NPC = "NPC"
local GROUP_PLAYERS = "Players"

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

local function setWorldColliderForNpc(npc: Model)
	local hrp = npc:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		pcall(function()
			(hrp :: BasePart).CanCollide = true
		end)
		return
	end

	local ground = npc:FindFirstChild("GroundCollider")
	if ground and ground:IsA("BasePart") then
		pcall(function()
			(ground :: BasePart).CanCollide = true
		end)
		return
	end

	local anyPart = npc:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		pcall(function()
			(anyPart :: BasePart).CanCollide = true
		end)
	end
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
	for _, inst in ipairs(npc:GetDescendants()) do
		if inst:IsA("BasePart") then
			setCollisionGroup(inst, GROUP_NPC)
		end
	end
	setWorldColliderForNpc(npc)
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
