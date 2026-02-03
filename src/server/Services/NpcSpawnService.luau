-- Spawns NPC units for players (shop purchases, etc.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local TeamTextures = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("TeamTextures"))

local NpcDamagePopupService = require(ServerScriptService.Services:WaitForChild("NpcDamagePopupService"))

local TEAM_COLOR_ATTRIBUTE = "TeamColor"

local SPAWN_HEIGHT_ABOVE_GROUND = 4.2
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

local function findNpcTemplate(unitKind: string, unitClass: string): Model?
	local npcRoot = ReplicatedStorage:FindFirstChild("NPC")
	if not npcRoot then
		return nil
	end

	local kindLower = unitKind:lower()
	local classLower = unitClass:lower()

	for _, inst in ipairs(npcRoot:GetDescendants()) do
		if inst:IsA("Model") then
			local k = inst:GetAttribute("UnitKind")
			local c = inst:GetAttribute("UnitClass")
			if type(k) == "string" and type(c) == "string" then
				if k:lower() == kindLower and c:lower() == classLower then
					return inst
				end
			end
		end
	end

	return nil
end

local function findNpcTemplateByName(npcModelName: string): Model?
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

local NpcSpawnService = {}

function NpcSpawnService.SpawnUnitNearPlayer(player: Player, a: any, b: any?): Model?
	local template: Model? = nil
	local npcModelName: string? = nil
	local unitKind: string? = nil
	local unitClass: string? = nil

	if type(a) == "string" and (b == nil or type(b) ~= "string") then
		local name = a
		npcModelName = name
		template = findNpcTemplateByName(name)
	elseif type(a) == "string" and type(b) == "string" then
		local kind = a
		local class = b
		unitKind = kind
		unitClass = class
		template = findNpcTemplate(kind, class)
	end

	if not template then
		warn(string.format(
			"[NpcSpawnService] No NPC template found for NpcModelName=%s UnitKind=%s UnitClass=%s",
			tostring(npcModelName),
			tostring(unitKind),
			tostring(unitClass)
		))
		return nil
	end

	local spawnPosition = getSpawnPositionNearPlayer(player)
	if not spawnPosition then
		return nil
	end

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

	local hrp = clone:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local root: BasePart = hrp
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end

	local rootPart = clone:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		local existingGroundCollider = clone:FindFirstChild("GroundCollider")
		if existingGroundCollider and existingGroundCollider:IsA("BasePart") then
			existingGroundCollider:Destroy()
		end

		local oldAnchored = rootPart.Anchored
		rootPart.Anchored = true
		pcall(function()
			(rootPart :: BasePart).CFrame = targetCFrame
		end)

		task.delay(SPAWN_ANCHOR_SECONDS, function()
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

return NpcSpawnService
