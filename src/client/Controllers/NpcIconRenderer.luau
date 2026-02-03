-- Renders NPC models into ViewportFrames for UI icons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("Animations"))

local rng = Random.new()

local NpcIconRenderer = {}

NpcIconRenderer.DEFAULT_YAW_OFFSET_RADIANS = -math.rad(90)

local function normalizeAssetId(id: string): string
	if id:match("^rbxassetid://") then
		return id
	end
	return "rbxassetid://" .. id
end

local function resolveAnimationIdValue(value: any): string?
	if type(value) == "string" then
		if value == "" then
			return nil
		end
		return value
	end

	if type(value) == "table" then
		local count = #value
		if count <= 0 then
			return nil
		end

		local picked = value[rng:NextInteger(1, count)]
		if type(picked) ~= "string" or picked == "" then
			return nil
		end
		return picked
	end

	return nil
end

local function toPascalCase(value: string): string
	local parts = {}
	for part in value:gmatch("[^%s%-_]+") do
		local lower = part:lower()
		local first = lower:sub(1, 1):upper()
		table.insert(parts, first .. lower:sub(2))
	end
	return table.concat(parts, "")
end

local function safeDestroyScripts(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function findHrp(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart", true)
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function uprightByHrp(model: Model, hrp: BasePart)
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-4 then
		flat = Vector3.new(0, 0, -1)
	else
		flat = flat.Unit
	end

	local desiredHrp = CFrame.lookAt(hrp.Position, hrp.Position + flat, Vector3.yAxis)
	local delta = desiredHrp * hrp.CFrame:Inverse()
	model:PivotTo(delta * model:GetPivot())
end

local function rotateAroundYAt(model: Model, worldPivot: Vector3, radians: number)
	local delta = CFrame.new(worldPivot) * CFrame.Angles(0, radians, 0) * CFrame.new(-worldPivot)
	model:PivotTo(delta * model:GetPivot())
end

local function centerAndGround(model: Model)
	local bboxCFrame, bboxSize = model:GetBoundingBox()
	local bottomY = bboxCFrame.Position.Y - (bboxSize.Y * 0.5)
	local translate = CFrame.new(-bboxCFrame.Position.X, -bottomY, -bboxCFrame.Position.Z)
	model:PivotTo(translate * model:GetPivot())
end

local function frameCameraToModel(camera: Camera, model: Model, fov: number?, direction: Vector3?)
	local bboxCFrame, bboxSize = model:GetBoundingBox()
	local center = bboxCFrame.Position

	local chosenFov = fov or 35
	camera.FieldOfView = chosenFov

	local radius = math.max(bboxSize.X, bboxSize.Y, bboxSize.Z) * 0.5
	local dist = (radius / math.tan(math.rad(chosenFov * 0.5))) * 1.35

	local dir = direction or Vector3.new(1, 0.75, 1)
	if dir.Magnitude < 1e-4 then
		dir = Vector3.new(1, 1, 1)
	end
	dir = dir.Unit

	camera.CFrame = CFrame.lookAt(center + dir * dist, center)
end

local function resolveIdleAnimationId(model: Model): string?
	local unitKind = model:GetAttribute("UnitKind")
	local unitClass = model:GetAttribute("UnitClass")

	if type(unitKind) == "string" and unitKind ~= "" and type(unitClass) == "string" and unitClass ~= "" then
		local kindTable = AnimationsConfig[toPascalCase(unitKind)]
		if type(kindTable) == "table" then
			local classTable = kindTable[toPascalCase(unitClass)]
			if type(classTable) == "table" then
				local rawValue = classTable.Idle
				local resolved = resolveAnimationIdValue(rawValue)
				if resolved then
					return normalizeAssetId(resolved)
				end
			end
		end
	end

	local idleAnim = model:FindFirstChild("Idle", true)
	if idleAnim and idleAnim:IsA("Animation") and idleAnim.AnimationId ~= "" then
		return idleAnim.AnimationId
	end

	return nil
end

local function ensureAnimator(container: Instance): Animator?
	local animator = container:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	animator = Instance.new("Animator")
	animator.Parent = container
	return animator
end

local function playIdlePose(model: Model)
	local assetId = resolveIdleAnimationId(model)
	if not assetId then
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animatorHost: Instance?
	if humanoid then
		animatorHost = humanoid
	else
		local controller = model:FindFirstChildOfClass("AnimationController")
		if controller then
			animatorHost = controller
		end
	end
	if not animatorHost then
		return
	end

	local animator = ensureAnimator(animatorHost)
	if not animator then
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = assetId

	local track: AnimationTrack?
	local ok = pcall(function()
		track = animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return
	end

	track.Looped = true
	pcall(function()
		track.Priority = Enum.AnimationPriority.Idle
	end)
	track:Play(0, 1, 1)
end

local function getStringAttributeDeep(model: Model, attributeName: string): string?
	local direct = model:GetAttribute(attributeName)
	if type(direct) == "string" and direct ~= "" then
		return direct
	end

	local hrp = model:FindFirstChild("HumanoidRootPart", true)
	if hrp then
		local fromHrp = hrp:GetAttribute(attributeName)
		if type(fromHrp) == "string" and fromHrp ~= "" then
			return fromHrp
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local fromHumanoid = humanoid:GetAttribute(attributeName)
		if type(fromHumanoid) == "string" and fromHumanoid ~= "" then
			return fromHumanoid
		end
	end

	for _, descendant in model:GetDescendants() do
		local value = descendant:GetAttribute(attributeName)
		if type(value) == "string" and value ~= "" then
			return value
		end
	end

	return nil
end

function NpcIconRenderer.getUnitIconLabel(model: Model): string
	local unitKind = getStringAttributeDeep(model, "UnitKind")
	local unitClass = getStringAttributeDeep(model, "UnitClass")

	if unitKind and unitClass then
		local kindLower = unitKind:lower()
		local classLabel = toPascalCase(unitClass)
		if kindLower == "infantry" then
			return classLabel
		elseif kindLower == "cavalry" then
			return "Cav. " .. classLabel
		end
	end

	return model.Name
end

export type RenderOptions = {
	yawOffsetRadians: number?,
	fov: number?,
	cameraDirection: Vector3?,
}

-- Renders a clone of npcModel into a ViewportFrame. Returns (hasHrp, cloneModel).
function NpcIconRenderer.renderIntoViewport(viewport: ViewportFrame, npcModel: Model, options: RenderOptions?): (boolean, Model)
	local camera = viewport.CurrentCamera
	if not camera then
		camera = Instance.new("Camera")
		camera.Name = "IconCamera"
		camera.Parent = viewport
		viewport.CurrentCamera = camera
	end

	for _, child in viewport:GetChildren() do
		if child:IsA("WorldModel") then
			child:Destroy()
		end
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "World"
	worldModel.Parent = viewport

	local clone = npcModel:Clone()
	safeDestroyScripts(clone)
	clone.Parent = worldModel

	local hrp = findHrp(clone)
	local hasHrp = hrp ~= nil
	if hrp then
		uprightByHrp(clone, hrp)
		local yaw = (options and options.yawOffsetRadians) or NpcIconRenderer.DEFAULT_YAW_OFFSET_RADIANS
		rotateAroundYAt(clone, hrp.Position, yaw)
	end

	playIdlePose(clone)
	centerAndGround(clone)
	frameCameraToModel(camera, clone, options and options.fov, options and options.cameraDirection)

	task.defer(function()
		RunService.Heartbeat:Wait()
		RunService.Heartbeat:Wait()
		if clone.Parent == nil then
			return
		end
		centerAndGround(clone)
		frameCameraToModel(camera, clone, options and options.fov, options and options.cameraDirection)
	end)

	return hasHrp, clone
end

return NpcIconRenderer
