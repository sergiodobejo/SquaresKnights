-- ServerScriptService.CavalryAnimation
-- Plays a looped animation on NPC models based on UnitKind/UnitClass attributes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local STARTED_ATTRIBUTE = "NpcLocomotionAnimationStarted"
local LOOPED_ANIMATION_ID_ATTRIBUTE = "LocomotionAnimationId"

local RUN_SPEED_THRESHOLD = 14
local STOP_SPEED_THRESHOLD = 0.25

local AnimationsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("Animations"))

local rng = Random.new()

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

local function getHumanoid(model: Instance): Humanoid?
	if not model:IsA("Model") then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end

	local maybeHumanoid = model:FindFirstChild("Humanoid")
	if maybeHumanoid and maybeHumanoid:IsA("Humanoid") then
		return maybeHumanoid
	end

	return nil
end

local function ensureAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function resolveAnimationId(model: Model, key: string): (string?, string?)
	local unitKind = model:GetAttribute("UnitKind")
	local unitClass = model:GetAttribute("UnitClass")

	if type(unitKind) ~= "string" or unitKind == "" then
		return nil, nil
	end
	if type(unitClass) ~= "string" or unitClass == "" then
		return nil, nil
	end

	local kindKey = toPascalCase(unitKind)
	local classKey = toPascalCase(unitClass)

	local kindTable = AnimationsConfig[kindKey]
	if type(kindTable) ~= "table" then
		return nil, ("Unknown UnitKind '%s'"):format(unitKind)
	end

	local classTable = kindTable[classKey]
	if type(classTable) ~= "table" then
		return nil, ("Unknown UnitClass '%s' for UnitKind '%s'"):format(unitClass, unitKind)
	end

	local rawValue = classTable[key]
	local animationId = resolveAnimationIdValue(rawValue)
	if not animationId then
		return nil,
			("Missing %s animation for UnitKind '%s' UnitClass '%s'")
				:format(key, unitKind, unitClass)
	end

	return normalizeAssetId(animationId), nil
end

local animationCache: { [string]: Animation } = {}

local function getOrCreateAnimation(assetId: string): Animation
	local existing = animationCache[assetId]
	if existing then
		return existing
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = assetId
	animation.Parent = script
	animationCache[assetId] = animation
	return animation
end

local function playLocomotionAnimationOnModel(model: Instance, key: string, lastWarned: any, tracksByModel: any)
	if not model:IsA("Model") then
		return
	end

	local animationId, warnReason = resolveAnimationId(model, key)
	if not animationId then
		if warnReason then
			if lastWarned[model] ~= warnReason then
				lastWarned[model] = warnReason
				warn(("[NpcLocomotionAnimation] %s (%s)"):format(warnReason, model:GetFullName()))
			end
		end
		return
	end

	local humanoid = getHumanoid(model)
	if not humanoid then
		return
	end

	local animator = ensureAnimator(humanoid)
	local currentId = model:GetAttribute(LOOPED_ANIMATION_ID_ATTRIBUTE)
	if model:GetAttribute(STARTED_ATTRIBUTE) and currentId == animationId then
		return
	end

	local animation = getOrCreateAnimation(animationId)
	local track: AnimationTrack?

	local ok, err = pcall(function()
		track = animator:LoadAnimation(animation)
	end)

	if not ok or not track then
		warn(("[CavalryAnimation] Failed to load animation for %s: %s"):format(model:GetFullName(), tostring(err)))
		return
	end

	local existingTrack = tracksByModel[model]
	if existingTrack then
		pcall(function()
			existingTrack:Stop(0.1)
		end)
		pcall(function()
			existingTrack:Destroy()
		end)
	end
	tracksByModel[model] = track

	model:SetAttribute(STARTED_ATTRIBUTE, true)
	model:SetAttribute(LOOPED_ANIMATION_ID_ATTRIBUTE, animationId)

	track.Looped = true
	pcall(function()
		if key == "Idle" then
			track.Priority = Enum.AnimationPriority.Idle
		else
			track.Priority = Enum.AnimationPriority.Movement
		end
	end)
	track:Play(0.1, 1, 1)
end

local observedModels: { [Model]: boolean } = {} :: any
setmetatable(observedModels, { __mode = "k" })

local lastWarned: { [Instance]: string } = {} :: any
setmetatable(lastWarned, { __mode = "k" })

local tracksByModel: { [Model]: AnimationTrack } = {} :: any
setmetatable(tracksByModel, { __mode = "k" })

local humanoidHooks: { [Model]: RBXScriptConnection } = {} :: any
setmetatable(humanoidHooks, { __mode = "k" })

local currentKeyByModel: { [Model]: string } = {} :: any
setmetatable(currentKeyByModel, { __mode = "k" })

local function pickDesiredKey(model: Model, speed: number): string
	if speed <= STOP_SPEED_THRESHOLD then
		return "Idle"
	end

	if speed >= RUN_SPEED_THRESHOLD then
		local runId = resolveAnimationId(model, "Run")
		if runId ~= nil then
			return "Run"
		end
	end

	local walkId = resolveAnimationId(model, "Walk")
	if walkId ~= nil then
		return "Walk"
	end

	return "Idle"
end

local function observeModel(model: Model)
	if observedModels[model] then
		return
	end
	observedModels[model] = true

	local function applyForSpeed(speed: number)
		local desiredKey = pickDesiredKey(model, speed)
		if currentKeyByModel[model] == desiredKey then
			return
		end
		currentKeyByModel[model] = desiredKey
		playLocomotionAnimationOnModel(model, desiredKey, lastWarned, tracksByModel)
	end

	local function tryHookHumanoid()
		local humanoid = getHumanoid(model)
		if not humanoid then
			return
		end

		local existing = humanoidHooks[model]
		if existing then
			existing:Disconnect()
			humanoidHooks[model] = nil
		end

		applyForSpeed(0)
		humanoidHooks[model] = humanoid.Running:Connect(function(speed)
			applyForSpeed(speed)
		end)
	end

	tryHookHumanoid()

	model:GetAttributeChangedSignal("UnitKind"):Connect(function()
		currentKeyByModel[model] = nil
		tryHookHumanoid()
	end)
	model:GetAttributeChangedSignal("UnitClass"):Connect(function()
		currentKeyByModel[model] = nil
		tryHookHumanoid()
	end)
	model.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") then
			currentKeyByModel[model] = nil
			task.defer(tryHookHumanoid)
		end
	end)
end

local function hookNpcFolder(npcFolder: Instance)
	for _, inst in ipairs(npcFolder:GetDescendants()) do
		if inst:IsA("Model") then
			observeModel(inst)
		end
	end

	npcFolder.DescendantAdded:Connect(function(inst)
		if inst:IsA("Model") then
			observeModel(inst)
		end
	end)
end

local function tryStart()
	local npcFolder = Workspace:FindFirstChild("NPC")
	if npcFolder then
		hookNpcFolder(npcFolder)
	end

	local liveNpcFolder = Workspace:FindFirstChild("LiveNPC")
	if liveNpcFolder then
		hookNpcFolder(liveNpcFolder)
	end
end

tryStart()

Workspace.ChildAdded:Connect(function(child)
	if child.Name ~= "NPC" and child.Name ~= "LiveNPC" then
		return
	end

	task.defer(function()
		hookNpcFolder(child)
	end)
end)

return {}
