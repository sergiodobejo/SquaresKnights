-- ServerScriptService.Services.AiNpcService
-- Spawns and manages AI NPCs that periodically appear at baseplate center and walk towards random castles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local AiNpcConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("AiNpcConfig"))
local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))

local NpcDamagePopupService = require(ServerScriptService.Services:WaitForChild("NpcDamagePopupService"))
local AiNpcBehaviorService = require(ServerScriptService.Services:WaitForChild("AiNpcBehaviorService"))
local CastleHealthService = require(ServerScriptService.Services:WaitForChild("CastleHealthService"))

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

local function findNpcTemplate(npcModelName: string): Model?
	local npcRoot = ReplicatedStorage:FindFirstChild("NPC")
	if not npcRoot then
		return nil
	end
	local inst = npcRoot:FindFirstChild(npcModelName, true)
	if inst and inst:IsA("Model") then
		return inst
	end
	return nil
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

local function _getCharacterRoot(character: Model): BasePart?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function _getCastleForPlayer(player: Player): Model?
	local buildingsFolder = workspace:FindFirstChild("PlayerBuildings")
	if not buildingsFolder then
		return nil
	end
	local castleInstance = buildingsFolder:FindFirstChild(string.format("SM_Castle_%d", player.UserId))
	if castleInstance and castleInstance:IsA("Model") then
		return castleInstance
	end
	return nil
end

local function _pickRandomCastle(): Model?
	-- Find a random player's castle from workspace.PlayerBuildings
	local buildingsFolder = workspace:FindFirstChild("PlayerBuildings")
	if not buildingsFolder then
		return nil
	end
	
	local castles = {}
	for _, child in ipairs(buildingsFolder:GetChildren()) do
		if child:IsA("Model") and string.find(child.Name, "SM_Castle_", 1, true) then
			local castle = child :: Model
			-- Only pick castles that still exist and aren't destroyed.
			-- (If health attrs aren't initialized yet, IsDestroyed() returns false.)
			if castle.Parent ~= nil and not CastleHealthService.IsDestroyed(castle) then
				table.insert(castles, castle)
			end
		end
	end
	
	if #castles == 0 then
		return nil
	end
	return castles[math.random(1, #castles)]
end

local function listAliveCastles(): { Model }
	local buildingsFolder = workspace:FindFirstChild("PlayerBuildings")
	if not buildingsFolder then
		return {}
	end

	local castles = {}
	for _, child in ipairs(buildingsFolder:GetChildren()) do
		if child:IsA("Model") and string.find(child.Name, "SM_Castle_", 1, true) then
			local castle = child :: Model
			if castle.Parent ~= nil and not CastleHealthService.IsDestroyed(castle) then
				table.insert(castles, castle)
			end
		end
	end
	return castles
end

local function pickNearestCastleToPosition(worldPos: Vector3): Model?
	local castles = listAliveCastles()
	if #castles == 0 then
		return nil
	end

	local bestCastle: Model? = nil
	local bestDistSq = math.huge
	for _, castle in ipairs(castles) do
		local pivotPos = (castle :: Model):GetPivot().Position
		local d = pivotPos - worldPos
		local distSq = d.X * d.X + d.Y * d.Y + d.Z * d.Z
		if distSq < bestDistSq then
			bestDistSq = distSq
			bestCastle = castle
		end
	end

	return bestCastle
end

local function _getBaseplateCenter(): Vector3?
	local baseplate = GridCells.FindBaseplate()
	if not baseplate then
		return nil
	end
	return baseplate.Position
end

local AI_SPAWN_SPREAD_STUDS_DEFAULT = 20
local AI_SPAWN_SPREAD_STUDS_MULTIPLAYER = 63
local AI_SPAWN_HEIGHT_ABOVE_GROUND = 6.2

local function getDynamicSpawnSpreadStuds(): number
	local playerCount = #Players:GetPlayers()
	if playerCount > 1 then
		return AI_SPAWN_SPREAD_STUDS_MULTIPLAYER
	end
	return AI_SPAWN_SPREAD_STUDS_DEFAULT
end

local function getGroundPositionAt(worldXZ: Vector3, ignoreInstances: { Instance }): Vector3
	local rayOrigin = worldXZ + Vector3.new(0, 120, 0)
	local rayDirection = Vector3.new(0, -400, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreInstances
	local hit = workspace:Raycast(rayOrigin, rayDirection, params)
	if hit then
		return hit.Position
	end
	return worldXZ
end

-- Create a spawned AI NPC clone with proper setup
local function spawnAiNpc(npcTemplate: Model, baseplate: BasePart, spawnSpreadStuds: number): Model?
	-- Spawn near the baseplate center with a random 2D offset.
	local angle = math.random() * math.pi * 2
	local radius = math.sqrt(math.random()) * spawnSpreadStuds
	local offsetLocal = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	local offsetWorld = baseplate.CFrame:VectorToWorldSpace(offsetLocal)
	local spawnXZ = baseplate.Position + offsetWorld
	local ignore: { Instance } = {}
	local maybeNpcFolder = workspace:FindFirstChild("NPC")
	if maybeNpcFolder then
		table.insert(ignore, maybeNpcFolder)
	end
	local maybeLiveNpcFolder = workspace:FindFirstChild("LiveNPC")
	if maybeLiveNpcFolder then
		table.insert(ignore, maybeLiveNpcFolder)
	end
	local groundPos = getGroundPositionAt(spawnXZ, ignore)
	local spawnPos = groundPos + Vector3.new(0, AI_SPAWN_HEIGHT_ABOVE_GROUND, 0)
	
	local clone = npcTemplate:Clone()
	
	-- Mark as AI-owned (not belonging to any player).
	-- TeamId=0 disables NPC-vs-NPC attacker logic (they should run to castles for now).
	Affiliation.StampNpc(clone, 0, 0)
	
	-- Apply team texture (blue by default)
	local meshPart = clone:FindFirstChildWhichIsA("MeshPart", true)
	if meshPart then
		local blueCfg = ReplicatedStorage:FindFirstChild("Configs"):FindFirstChild("TeamTextures")
		if blueCfg then
			blueCfg = require(blueCfg)
			local teamCfg = blueCfg[AiNpcConfig.TeamColorName]
			local blueTexture = teamCfg and teamCfg.Units
			if blueTexture then
				pcall(function()
					(meshPart :: MeshPart).TextureID = blueTexture
				end)
			end
		end
	end
	
	-- Position at baseplate center
	local yaw = math.rad(math.random(0, 359))
	local targetCFrame = CFrame.new(spawnPos) * CFrame.Angles(0, yaw, 0)
	pcall(function()
		clone:PivotTo(targetCFrame)
	end)
	
	local aiFolders = getOrCreateFolder(workspace, "NPC")
	clone.Parent = aiFolders
	
	NpcDamagePopupService.TrackNpc(clone)
	
	local hrp = clone:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		pcall(function()
			(hrp :: BasePart):SetNetworkOwner(nil)
		end)
	end

	local rootPart = clone:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		local oldAnchored = rootPart.Anchored
		rootPart.Anchored = true
		pcall(function()
			(rootPart :: BasePart).CFrame = targetCFrame
		end)

		task.delay(0.5, function()
			if rootPart.Parent == nil then
				return
			end
			rootPart.Anchored = oldAnchored

			local humanoid = getHumanoid(clone)
			if humanoid then
				pcall(function()
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end)
			end
		end)
	end
	
	return clone
end

local Shared = {}

local spawnIntervalDirty = true
Players.PlayerAdded:Connect(function()
	spawnIntervalDirty = true
end)
Players.PlayerRemoving:Connect(function()
	spawnIntervalDirty = true
end)

local function getDynamicSpawnIntervalSeconds(): number
	local base = AiNpcConfig.SpawnIntervalSeconds
	if type(base) ~= "number" or base ~= base or base <= 0 then
		base = 5
	end
	local playerCount = #Players:GetPlayers()
	-- 1 player => base, 2 players => base-1, 3 players => base-2, ...
	local interval = base - math.max(0, playerCount - 1)
	return math.max(1, interval)
end

local function waitUntilNextSpawn(lastAttemptAt: number)
	local targetAt = lastAttemptAt + getDynamicSpawnIntervalSeconds()
	spawnIntervalDirty = false
	while true do
		if spawnIntervalDirty then
			spawnIntervalDirty = false
			targetAt = lastAttemptAt + getDynamicSpawnIntervalSeconds()
		end

		local remaining = targetAt - os.clock()
		if remaining <= 0 then
			return
		end
		task.wait(math.min(0.25, remaining))
	end
end

function Shared.StartSpawning()
	task.spawn(function()
		local lastAttemptAt = os.clock()
		while true do
			waitUntilNextSpawn(lastAttemptAt)
			lastAttemptAt = os.clock()

			-- Only spawn if there is at least one alive castle.
			-- Target selection happens after spawn so we can pick the nearest castle to the NPC.
			if #listAliveCastles() == 0 then
				continue
			end
			
			-- Pick a random NPC model
			local modelName = AiNpcConfig.AvailableNpcModels[math.random(1, #AiNpcConfig.AvailableNpcModels)]
			local template = findNpcTemplate(modelName)
			if not template then
				warn("[AiNpcService] NPC template not found:", modelName)
				continue
			end
			
			local baseplate = GridCells.FindBaseplate()
			if not baseplate then
				warn("[AiNpcService] Baseplate not found")
				continue
			end
			
			local npc = spawnAiNpc(template, baseplate, getDynamicSpawnSpreadStuds())
			if npc then
				print(string.format("[AiNpcService] Spawned AI NPC: %s", modelName))
				local targetCastle = pickNearestCastleToPosition((npc :: Model):GetPivot().Position)
				if not targetCastle then
					npc:Destroy()
					continue
				end
				-- Start AI behavior: walk to target castle and prepare to attack
				task.spawn(function()
					AiNpcBehaviorService.StartAiBehavior(npc, targetCastle)
				end)
			end
		end
	end)
end

return Shared
