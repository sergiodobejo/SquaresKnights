-- PATH: StarterPlayer.StarterPlayerScripts.NpcIconGallery

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GuiStrings = require(script.Parent:WaitForChild("Controllers"):WaitForChild("GuiStrings"))

local NpcIconRenderer = require(script.Parent:WaitForChild("Controllers"):WaitForChild("NpcIconRenderer"))

local LOCAL_PLAYER = Players.LocalPlayer
local PLAYER_GUI = LOCAL_PLAYER:WaitForChild("PlayerGui")

local ACTION_TOGGLE = "ToggleNpcIconGallery"
local GUI_NAME = "NpcIconGalleryGui"

-- We currently shoot from a fixed camera direction; rotate the model for consistent icon angle.
-- Clockwise (top-down) in Roblox corresponds to negative yaw.
local ICON_YAW_OFFSET_RADIANS = -math.rad(90)

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

	-- Fallback: try to find an Animation named "Idle" inside the model.
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

local function playIdlePose(model: Model): AnimationTrack?
	local assetId = resolveIdleAnimationId(model)
	if not assetId then
		return nil
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
		return nil
	end

	local animator = ensureAnimator(animatorHost)
	if not animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = assetId

	local track: AnimationTrack?
	local ok = pcall(function()
		track = animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end

	track.Looped = true
	pcall(function()
		track.Priority = Enum.AnimationPriority.Idle
	end)
	track:Play(0, 1, 1)
	return track
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

local function getUnitIconLabel(model: Model): string
	local unitKind = getStringAttributeDeep(model, "UnitKind")
	-- Your NPCs (per the dump) use UnitClass, not UnitType.
	local unitType = getStringAttributeDeep(model, "UnitType")
	local unitClass = getStringAttributeDeep(model, "UnitClass")
	local typeOrClass = unitType or unitClass

	if unitKind and typeOrClass then
		local kindLower = unitKind:lower()
		local typeLabel = toPascalCase(typeOrClass)
		if kindLower == "infantry" then
			return typeLabel
		elseif kindLower == "cavalry" then
			return "Cav. " .. typeLabel
		end
	end

	return model.Name
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

local function frameCameraToModel(camera: Camera, model: Model)
	local bboxCFrame, bboxSize = model:GetBoundingBox()
	local center = bboxCFrame.Position

	local fov = 35
	camera.FieldOfView = fov

	local radius = math.max(bboxSize.X, bboxSize.Y, bboxSize.Z) * 0.5
	local dist = (radius / math.tan(math.rad(fov * 0.5))) * 1.35

	local dir = Vector3.new(1, 0.75, 1)
	if dir.Magnitude < 1e-4 then
		dir = Vector3.new(1, 1, 1)
	end
	dir = dir.Unit

	camera.CFrame = CFrame.lookAt(center + dir * dist, center)
end

local function collectNpcModels(npcRoot: Instance): { Model }
	local models: { Model } = {}
	for _, category in npcRoot:GetChildren() do
		if category:IsA("Folder") then
			for _, child in category:GetChildren() do
				if child:IsA("Model") then
					table.insert(models, child)
				end
			end
		elseif category:IsA("Model") then
			table.insert(models, category)
		end
	end
	return models
end

local function createIconCell(parent: Instance, npcModel: Model): Frame
	local cell = Instance.new("Frame")
	cell.Name = npcModel.Name
	cell.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	cell.BorderSizePixel = 0
	cell.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = cell

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
	viewport.BorderSizePixel = 0
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Parent = cell

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, -8, 0, 18)
	nameLabel.Position = UDim2.new(0, 4, 1, -20)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 12
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
	nameLabel.Text = NpcIconRenderer.getUnitIconLabel(npcModel)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = cell

	local hasHrp = NpcIconRenderer.renderIntoViewport(viewport, npcModel, {
		yawOffsetRadians = ICON_YAW_OFFSET_RADIANS,
	})
	if not hasHrp then
		nameLabel.Text = NpcIconRenderer.getUnitIconLabel(npcModel)
			.. GuiStrings.get("NpcIconGallery_NoHrpSuffix", " (no HRP)")
	end

	return cell
end

local function buildGui()
	local existing = PLAYER_GUI:FindFirstChild(GUI_NAME)
	if existing then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = GUI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = PLAYER_GUI

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	root.BackgroundTransparency = 0.25
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = screenGui

	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 48)
	top.Parent = root

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 16, 0, 8)
	title.Size = UDim2.new(1, -120, 0, 32)
	title.Font = Enum.Font.GothamSemibold
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = GuiStrings.get("NpcIconGallery_Title", "NPC Icon Gallery (F6)")
	title.Parent = top

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 10)
	close.Size = UDim2.new(0, 90, 0, 28)
	close.Font = Enum.Font.Gotham
	close.TextSize = 14
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.BackgroundColor3 = Color3.fromRGB(40, 40, 44)
	close.BorderSizePixel = 0
	close.Text = GuiStrings.get("Common_Close", "Close")
	close.Parent = top

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = close

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.new(0, 16, 0, 56)
	scroll.Size = UDim2.new(1, -32, 1, -72)
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 8
	scroll.Parent = root

	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.CellSize = UDim2.fromOffset(120, 120)
	grid.SortOrder = Enum.SortOrder.Name
	grid.Parent = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 2)
	padding.PaddingRight = UDim.new(0, 2)
	padding.Parent = scroll

	close.Activated:Connect(function()
		screenGui.Enabled = false
	end)

	return screenGui, scroll
end

local function populate(scroll: ScrollingFrame)
	local npcRoot = ReplicatedStorage:FindFirstChild("NPC")
	if not npcRoot then
		npcRoot = ReplicatedStorage:WaitForChild("NPC", 5)
	end

	if not npcRoot then
		local warnLabel = Instance.new("TextLabel")
		warnLabel.BackgroundTransparency = 1
		warnLabel.Size = UDim2.new(1, 0, 0, 40)
		warnLabel.Font = Enum.Font.Gotham
		warnLabel.TextSize = 16
		warnLabel.TextColor3 = Color3.fromRGB(255, 200, 200)
		warnLabel.Text = GuiStrings.get("NpcIconGallery_NpcNotFound", "ReplicatedStorage/NPC not found")
		warnLabel.Parent = scroll
		return
	end

	local models = collectNpcModels(npcRoot)
	if #models == 0 then
		local warnLabel = Instance.new("TextLabel")
		warnLabel.BackgroundTransparency = 1
		warnLabel.Size = UDim2.new(1, 0, 0, 40)
		warnLabel.Font = Enum.Font.Gotham
		warnLabel.TextSize = 16
		warnLabel.TextColor3 = Color3.fromRGB(255, 200, 200)
		warnLabel.Text = GuiStrings.get(
			"NpcIconGallery_NoNpcModelsFound",
			"No NPC models found in ReplicatedStorage/NPC"
		)
		warnLabel.Parent = scroll
		return
	end

	for _, model in models do
		createIconCell(scroll, model)
	end
end

local function main()
	local gui, scroll = buildGui()
	gui.Enabled = false
	populate(scroll)

	-- Test GUI toggle hotkey removed.
	ContextActionService:UnbindAction(ACTION_TOGGLE)
end

main()
