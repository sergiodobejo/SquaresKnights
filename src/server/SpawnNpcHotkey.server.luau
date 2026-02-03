-- ServerScriptService.SpawnNpcHotkey

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteNames = require(ReplicatedStorage:WaitForChild("RemoteNames"))
local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local TeamTextures = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("TeamTextures"))

local NpcDamagePopupService = require(ServerScriptService.Services:WaitForChild("NpcDamagePopupService"))

local TEAM_COLOR_ATTRIBUTE = "TeamColor"

local SPAWN_HEIGHT_ABOVE_GROUND = 4.2 -- ~0.7 Robloxian height (assuming ~6 studs per height)
local SPAWN_ANCHOR_SECONDS = 1.5

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
local spawnNpcRemote = getOrCreateRemoteEvent(remotesFolder, RemoteNames.SpawnNpcRequest)

local npcsRoot = ReplicatedStorage:FindFirstChild("NPC")

local function collectNpcTemplates(): { Model }
	local results = {}
	if not npcsRoot then
		return results
	end

	for _, child in ipairs(npcsRoot:GetChildren()) do
		if child:IsA("Folder") then
			for _, npc in ipairs(child:GetChildren()) do
				if npc:IsA("Model") then
					table.insert(results, npc)
				end
			end
		elseif child:IsA("Model") then
			table.insert(results, child)
		end
	end

	return results
end

local function getCharacterRoot(character: Model): BasePart?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function getSpawnPositionNearPlayer(player: Player): Vector3?
	local character = player.Character
	if not character then
		return nil
	end

	local rootPart = getCharacterRoot(character)
	if not rootPart then
		return nil
	end

	local basePosition = rootPart.Position
	local direction = Vector3.new(math.random(-100, 100) / 100, 0, math.random(-100, 100) / 100)
	if direction.Magnitude < 1e-6 then
		direction = Vector3.new(1, 0, 0)
	else
		direction = direction.Unit
	end

	local distance = math.random(12, 22)
	local desired = basePosition + direction * distance

	local rayOrigin = desired + Vector3.new(0, 80, 0)
	local rayDirection = Vector3.new(0, -200, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	if hit then
		return hit.Position + Vector3.new(0, SPAWN_HEIGHT_ABOVE_GROUND, 0)
	end

	return desired + Vector3.new(0, SPAWN_HEIGHT_ABOVE_GROUND, 0)
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

local function normalizeAssetId(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	if value == "" then
		return nil
	end
	if string.find(value, "rbxassetid://", 1, true) then
		return value
	end
	if string.match(value, "^%d+$") then
		return "rbxassetid://" .. value
	end
	return value
end

local function applyNpcUnitTextureForPlayer(npc: Model, player: Player)
	local colorName = player:GetAttribute(TEAM_COLOR_ATTRIBUTE)
	if type(colorName) ~= "string" or colorName == "" then
		return
	end

	local cfg = TeamTextures[colorName]
	if type(cfg) ~= "table" then
		return
	end

	local textureId = normalizeAssetId(cfg.Units)
	if not textureId then
		return
	end

	local meshPart = npc:FindFirstChildWhichIsA("MeshPart", true)
	if not meshPart then
		return
	end

	pcall(function()
		(meshPart :: MeshPart).TextureID = textureId
	end)
end

local lastSpawnAt: { [number]: number } = {}
local COOLDOWN_SECONDS = 1.0

local function spawnRandomNpcNearPlayer(player: Player)
	if not npcsRoot then
		warn("[SpawnNpcHotkey] ReplicatedStorage/NPC folder not found")
		return
	end

	local templates = collectNpcTemplates()
	if #templates == 0 then
		warn("[SpawnNpcHotkey] No NPC models found under ReplicatedStorage/NPC/*")
		return
	end

	local spawnPosition = getSpawnPositionNearPlayer(player)
	if not spawnPosition then
		return
	end

	local template = templates[math.random(1, #templates)]
	local clone = template:Clone()
	applyNpcUnitTextureForPlayer(clone, player)
	Affiliation.StampNpc(clone, player.UserId, Affiliation.GetTeamIdForPlayer(player))

	local yaw = math.rad(math.random(0, 359))
	local targetCFrame = CFrame.new(spawnPosition) * CFrame.Angles(0, yaw, 0)
	pcall(function()
		clone:PivotTo(targetCFrame)
	end)

	local liveNpcFolder = getOrCreateFolder(workspace, "LiveNPC")
	clone.Parent = liveNpcFolder
	NpcDamagePopupService.TrackNpc(clone)

	local hrp = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp and hrp:IsA("BasePart") then
		pcall(function()
			hrp:SetNetworkOwner(nil)
		end)

		local existingGroundCollider = clone:FindFirstChild("GroundCollider")
		if existingGroundCollider and existingGroundCollider:IsA("BasePart") then
			existingGroundCollider:Destroy()
		end

		local oldAnchored = hrp.Anchored
		hrp.Anchored = true
		pcall(function()
			hrp.CFrame = targetCFrame
		end)

		task.delay(SPAWN_ANCHOR_SECONDS, function()
			if hrp.Parent == nil then
				return
			end
			hrp.Anchored = oldAnchored

			local humanoid = getHumanoid(clone)
			if humanoid then
				pcall(function()
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end)
			end
		end)
	else
		pcall(function()
			clone:PivotTo(targetCFrame)
		end)
	end
end

spawnNpcRemote.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	local userId = player.UserId
	local last = lastSpawnAt[userId]
	if last and (now - last) < COOLDOWN_SECONDS then
		return
	end
	lastSpawnAt[userId] = now

	spawnRandomNpcNearPlayer(player)
end)

return {}
