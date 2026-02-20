-- StarterPlayer.StarterPlayerScripts.CapturedCellCountdown
-- Shows a countdown number above temporarily-captured cells.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local GuiStrings = require(script.Parent:WaitForChild("Controllers"):WaitForChild("GuiStrings"))

local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))
local RuntimeSettings = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("RuntimeSettings"))

local CAPTURED_BLOCKS_FOLDER_NAME = "CapturedCellBlocks"

-- Camera focus on newly-captured regions (owned by this player).
local CAMERA_OUT_SECONDS = 0.45
local CAMERA_HOLD_SECONDS = RuntimeSettings.CaptureCinematicCameraHoldSeconds
local CAMERA_BACK_SECONDS = 0.45
local CAMERA_COOLDOWN_SECONDS = 2.5
local CAMERA_MARGIN_CELLS = 1
local CAMERA_MIN_DISTANCE = 34
local CAMERA_HEIGHT_RATIO = 0.7
local CAMERA_MAX_HORIZONTAL_DISTANCE = 450

-- VFX shown while the camera frames a captured region.
local VFX_START_HEIGHT_MIN = 10
local VFX_START_HEIGHT_MAX = 22
local VFX_START_DELAY_MAX = 0.5
local VFX_DROP_DURATION_MIN = 0.45
local VFX_DROP_DURATION_MAX = 0.85
local VFX_FADE_IN_SECONDS = 0.12
local VFX_FADE_OUT_SECONDS = 0.35
local VFX_HOLD_AFTER_LAND_MIN = 0.25
local VFX_HOLD_AFTER_LAND_MAX = 0.7
local VFX_TRANSPARENCY_VISIBLE = 0.25
-- Match the server NPC "occupied cell" overlay thickness/height so the VFX square
-- lands exactly flush with it (both bottom and top).
local VFX_THICKNESS = 0.18
local VFX_Y_OFFSET_ABOVE_SURFACE = 0.02
local VFX_LIFETIME_MAX = 4.5
local vfxRng = Random.new()

local TEXT_SIZE = 18
local MAX_DISTANCE = 120
local GUI_SIZE = UDim2.fromOffset(40, 40)

local CAPTURED_TEXT = GuiStrings.get("CapturedCellCountdown_Captured", "Captured")
local CAPTURED_PLATE_THICKNESS = 0.05
-- Place above the server-side captured overlay (keeps existing overlay intact).
local CAPTURED_PLATE_Y_OFFSET = 0.44
local CAPTURED_PIXELS_PER_STUD = 48

local CAPTURED_DIAGONAL_ROT_A = 45
local CAPTURED_DIAGONAL_ROT_B = -45

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local getBaseplate: () -> BasePart?

local refreshAll: () -> ()
local getHintRotationForLocalPlayer: () -> number
local applyCapturedTextStyle: (label: TextLabel, marker: Instance) -> ()

type Entry = {
	key: string,
	marker: Instance,
	attachment: Attachment,
	gui: BillboardGui,
	label: TextLabel,
	plate: BasePart,
	surfaceGui: SurfaceGui,
	surfaceLabel: TextLabel,
	diagonalRotation: number,
	lastRemaining: number,
}

local entriesByKey: { [string]: Entry } = {}

-- When a camera cinematic plays, we temporarily hide the normal captured overlay/text
-- for those cells until the falling VFX square lands.
local delayedRevealByKey: { [string]: boolean } = {}
local landedRevealByKey: { [string]: boolean } = {}

local pendingCameraKeys: { [string]: boolean } = {}
local pendingCameraFlushScheduled = false
local cinematicRunning = false
local lastCinematicAt = -1e9

local hiddenOverlayKeys: { [string]: boolean } = {}
local overlayWatcherConn: RBXScriptConnection? = nil

local function ensureOverlayWatcher()
	if overlayWatcherConn then
		return
	end
	local overlayFolder = Workspace:FindFirstChild("CapturedCellOverlays")
	if not overlayFolder or not overlayFolder:IsA("Folder") then
		return
	end
	overlayWatcherConn = overlayFolder.DescendantAdded:Connect(function(inst)
		if not inst:IsA("BasePart") then
			return
		end
		local key = inst.Name
		if hiddenOverlayKeys[key] then
			(inst :: BasePart).LocalTransparencyModifier = 1
		end
	end)
end

local function setLocalOverlayHidden(cellKey: string, hidden: boolean)
	local overlayFolder = Workspace:FindFirstChild("CapturedCellOverlays")
	if not overlayFolder or not overlayFolder:IsA("Folder") then
		return
	end
	for _, eventFolder in ipairs((overlayFolder :: Folder):GetChildren()) do
		if not eventFolder:IsA("Folder") then
			continue
		end
		local p = eventFolder:FindFirstChild(cellKey)
		if p and p:IsA("BasePart") then
			(p :: BasePart).LocalTransparencyModifier = if hidden then 1 else 0
			return
		end
	end
end

local function canStartCaptureCinematic(): boolean
	if cinematicRunning then
		return false
	end
	-- Avoid fighting other cinematics; also prevents capturing a Scriptable state as the "original".
	local cam = Workspace.CurrentCamera
	if cam and cam.CameraType == Enum.CameraType.Scriptable then
		return false
	end
	local now = os.clock()
	return (now - lastCinematicAt) >= CAMERA_COOLDOWN_SECONDS
end

local function hideFinalCapturedForKey(key: string)
	delayedRevealByKey[key] = true
	landedRevealByKey[key] = false
	hiddenOverlayKeys[key] = true
	ensureOverlayWatcher()
	setLocalOverlayHidden(key, true)
	local entry = entriesByKey[key]
	if entry then
		entry.gui.Enabled = false
		entry.surfaceGui.Enabled = false
	end
	refreshAll()
end

local function revealFinalCapturedForKey(key: string)
	landedRevealByKey[key] = true
	delayedRevealByKey[key] = nil
	hiddenOverlayKeys[key] = nil
	setLocalOverlayHidden(key, false)
	refreshAll()
end

local function getCurrentCamera(): Camera?
	local cam = Workspace.CurrentCamera
	if cam and cam:IsA("Camera") then
		return cam
	end
	return nil
end

local function restoreCamera(cam: Camera, originalType: Enum.CameraType, originalCFrame: CFrame, originalFov: number)
	pcall(function()
		cam.CameraType = if originalType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else originalType
		cam.CFrame = originalCFrame
		cam.FieldOfView = originalFov
	end)

	pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)

	pcall(function()
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			cam.CameraSubject = humanoid
		end
	end)

	task.defer(function()
		if cam.Parent == nil then
			return
		end
		if cam.CameraType == Enum.CameraType.Scriptable then
			pcall(function()
				cam.CameraType = Enum.CameraType.Custom
			end)
		end
		pcall(function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end)
	end)
end

local function tryGetCaptureOwnerUserId(marker: Instance): number?
	local v = marker:GetAttribute("CaptureOwnerUserId")
	if type(v) == "number" then
		return math.floor(v)
	end
	return nil
end

local function computeCaptureBoundsLocalXZ(bp: BasePart, keys: { string }): (number?, number?, number?, number?)
	local minX: number? = nil
	local maxX: number? = nil
	local minZ: number? = nil
	local maxZ: number? = nil

	local half = GridCells.SQUARE_SIZE_STUDS / 2
	local margin = (GridCells.SQUARE_SIZE_STUDS * CAMERA_MARGIN_CELLS)

	for _, key in ipairs(keys) do
		local ix, iz = GridCells.ParseCellKey(key)
		if ix ~= nil and iz ~= nil then
			local xCenter, zCenter = GridCells.GetCellCenterLocalXZ(bp, ix, iz)
			local aX = xCenter - half - margin
			local bX = xCenter + half + margin
			local aZ = zCenter - half - margin
			local bZ = zCenter + half + margin

			minX = if minX == nil then aX else math.min(minX, aX)
			maxX = if maxX == nil then bX else math.max(maxX, bX)
			minZ = if minZ == nil then aZ else math.min(minZ, aZ)
			maxZ = if maxZ == nil then bZ else math.max(maxZ, bZ)
		end
	end

	return minX, maxX, minZ, maxZ
end

local function getHorizontalBackVectorFromCamera(cam: Camera): Vector3
	local look = cam.CFrame.LookVector
	local horizontal = Vector3.new(look.X, 0, look.Z)
	if horizontal.Magnitude < 1e-3 then
		return Vector3.new(0, 0, 1)
	end
	return -horizontal.Unit
end

local function isCinematicLineOfSightClear(fromWorld: Vector3, toWorld: Vector3, ignoreInstances: { Instance }): boolean
	local dir = toWorld - fromWorld
	if dir.Magnitude <= 1e-3 then
		return true
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreInstances
	params.IgnoreWater = true

	local hit = Workspace:Raycast(fromWorld, dir, params)
	return hit == nil
end

local function chooseCinematicCameraCFrame(cam: Camera, bp: BasePart, lookAtWorld: Vector3, horizontalBack: Vector3, distance: number, height: number): CFrame
	local up = Vector3.new(0, 1, 0)
	local back = Vector3.new(horizontalBack.X, 0, horizontalBack.Z)
	if back.Magnitude < 1e-3 then
		back = Vector3.new(0, 0, 1)
	else
		back = back.Unit
	end
	local left = Vector3.new(-back.Z, 0, back.X)
	local right = -left

	local ignore: { Instance } = { bp }
	local character = player.Character
	if character then
		table.insert(ignore, character)
	end
	for _, name in ipairs({ "CellOverlays", "ReservedCellOverlays", "CapturedCellOverlays" }) do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end

	local candidates = {
		back,
		-back,
		left,
		right,
		(back + left).Unit,
		(back + right).Unit,
		(-back + left).Unit,
		(-back + right).Unit,
	}

	for _, dir in ipairs(candidates) do
		local targetPos = lookAtWorld + (dir * distance) + (up * height)
		if isCinematicLineOfSightClear(lookAtWorld + (up * 1.0), targetPos, ignore) then
			return CFrame.lookAt(targetPos, lookAtWorld)
		end
	end

	local fallbackPos = lookAtWorld + (back * distance) + (up * height)
	return CFrame.lookAt(fallbackPos, lookAtWorld)
end

local function playCaptureCameraCinematic(keys: { string })
	if not canStartCaptureCinematic() then
		return
	end
	local now = os.clock()

	local bp = getBaseplate()
	if not bp then
		return
	end

	local cam = getCurrentCamera()
	if not cam then
		return
	end

	local minX, maxX, minZ, maxZ = computeCaptureBoundsLocalXZ(bp, keys)
	if minX == nil or maxX == nil or minZ == nil or maxZ == nil then
		return
	end

	local centerX = (minX + maxX) / 2
	local centerZ = (minZ + maxZ) / 2
	local targetWorld = (bp.CFrame * CFrame.new(centerX, (bp.Size.Y / 2) + 1.0, centerZ)).Position

	local sizeX = math.max(0, maxX - minX)
	local sizeZ = math.max(0, maxZ - minZ)
	local size = math.max(sizeX, sizeZ)

	local horizontalBack = getHorizontalBackVectorFromCamera(cam)
	local distance = math.max(CAMERA_MIN_DISTANCE, (size * 0.95) + 12)
	if distance > CAMERA_MAX_HORIZONTAL_DISTANCE then
		distance = CAMERA_MAX_HORIZONTAL_DISTANCE
	end
	local height = (distance * CAMERA_HEIGHT_RATIO) + 10
	local targetCFrame = chooseCinematicCameraCFrame(cam, bp, targetWorld, horizontalBack, distance, height)

	local originalType = cam.CameraType
	local originalCFrame = cam.CFrame
	local originalFov = cam.FieldOfView

	local capturedFolder = ReplicatedStorage:FindFirstChild(CAPTURED_BLOCKS_FOLDER_NAME)

	local function createVfxTextOnPart(part: BasePart, marker: Instance, ix: number, iz: number): (SurfaceGui, TextLabel)
		local diagonalRotation = if ((ix + iz) % 2) == 0 then CAPTURED_DIAGONAL_ROT_A else CAPTURED_DIAGONAL_ROT_B
		local surfaceGui = Instance.new("SurfaceGui")
		surfaceGui.Name = "CapturedVfxSurfaceGui"
		surfaceGui.Adornee = part
		surfaceGui.Face = Enum.NormalId.Top
		surfaceGui.AlwaysOnTop = false
		surfaceGui.LightInfluence = 0
		surfaceGui.ResetOnSpawn = false
		surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surfaceGui.PixelsPerStud = CAPTURED_PIXELS_PER_STUD
		surfaceGui.Enabled = true
		surfaceGui.Parent = part

		local surfaceLabel = Instance.new("TextLabel")
		surfaceLabel.Name = "Text"
		surfaceLabel.BackgroundTransparency = 1
		surfaceLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		surfaceLabel.Position = UDim2.fromScale(0.5, 0.5)
		surfaceLabel.Size = UDim2.fromScale(1.3, 1.3)
		surfaceLabel.Text = CAPTURED_TEXT
		surfaceLabel.TextScaled = true
		surfaceLabel.TextWrapped = true
		surfaceLabel.Font = Enum.Font.LuckiestGuy
		-- Colors/stroke are applied from marker attributes.
		surfaceLabel.TextColor3 = Color3.new(1, 1, 1)
		surfaceLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		surfaceLabel.TextStrokeTransparency = 0
		surfaceLabel.Rotation = getHintRotationForLocalPlayer() + diagonalRotation
		surfaceLabel.Parent = surfaceGui

		applyCapturedTextStyle(surfaceLabel, marker)
		return surfaceGui, surfaceLabel
	end

	local function getOwnedKeysAndPreHide(): { string }
		local ownedKeys: { string } = {}
		if not capturedFolder or not capturedFolder:IsA("Folder") then
			return ownedKeys
		end

		for _, key in ipairs(keys) do
			local marker = (capturedFolder :: Folder):FindFirstChild(key)
			if not marker then
				continue
			end
			local ownerUserId = tryGetCaptureOwnerUserId(marker)
			if ownerUserId ~= player.UserId then
				continue
			end

			-- Should already be hidden from ChildAdded, but keep it idempotent here.
			hideFinalCapturedForKey(key)

			table.insert(ownedKeys, key)
		end

		return ownedKeys
	end

	local function spawnCaptureVfx()
		if not capturedFolder or not capturedFolder:IsA("Folder") then
			return
		end

		local ownedKeys = getOwnedKeysAndPreHide()
		for _, key in ipairs(ownedKeys) do
			local ix, iz = GridCells.ParseCellKey(key)
			if ix == nil or iz == nil then
				continue
			end
			local marker = (capturedFolder :: Folder):FindFirstChild(key)
			if not marker then
				continue
			end
			local color = marker:GetAttribute("CaptureColor")
			local color3: Color3 = if typeof(color) == "Color3" then (color :: Color3) else Color3.new(1, 1, 1)

			local xCenter, zCenter = GridCells.GetCellCenterLocalXZ(bp, ix, iz)
			local thickness = VFX_THICKNESS
			local endYLocal = (bp.Size.Y / 2) + (thickness / 2) + VFX_Y_OFFSET_ABOVE_SURFACE
			local startHeight = vfxRng:NextNumber(VFX_START_HEIGHT_MIN, VFX_START_HEIGHT_MAX)
			local startYLocal = endYLocal + startHeight

			local part = Instance.new("Part")
			part.Name = "CaptureVfxSquare_" .. key
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
			part.Material = Enum.Material.SmoothPlastic
			part.Color = color3
			part.Transparency = 1
			part.Size = Vector3.new(GridCells.SQUARE_SIZE_STUDS, thickness, GridCells.SQUARE_SIZE_STUDS)
			part.CFrame = bp.CFrame * CFrame.new(xCenter, startYLocal, zCenter)
			part.Parent = Workspace
			Debris:AddItem(part, VFX_LIFETIME_MAX)
			local vfxSurfaceGui, vfxSurfaceLabel = createVfxTextOnPart(part, marker, ix :: number, iz :: number)
			-- Ensure the square + text appear together when the drop starts.
			vfxSurfaceGui.Enabled = false
			vfxSurfaceLabel.TextTransparency = 1
			vfxSurfaceLabel.TextStrokeTransparency = 1

			local startDelay = vfxRng:NextNumber(0, VFX_START_DELAY_MAX)
			local dropDuration = vfxRng:NextNumber(VFX_DROP_DURATION_MIN, VFX_DROP_DURATION_MAX)
			local holdAfter = vfxRng:NextNumber(VFX_HOLD_AFTER_LAND_MIN, VFX_HOLD_AFTER_LAND_MAX)

			task.delay(startDelay, function()
				if part.Parent == nil then
					return
				end
				if vfxSurfaceGui.Parent ~= nil then
					vfxSurfaceGui.Enabled = true
				end
				TweenService:Create(
					vfxSurfaceLabel,
					TweenInfo.new(VFX_FADE_IN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ TextTransparency = 0, TextStrokeTransparency = 0 }
				):Play()
				-- Fade in quickly as it starts falling.
				TweenService:Create(
					part,
					TweenInfo.new(VFX_FADE_IN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Transparency = VFX_TRANSPARENCY_VISIBLE }
				):Play()

				local endCFrame = bp.CFrame * CFrame.new(xCenter, endYLocal, zCenter)
				local dropTween = TweenService:Create(
					part,
					TweenInfo.new(dropDuration, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
					{ CFrame = endCFrame }
				)
				dropTween:Play()
				dropTween.Completed:Wait()
				-- Snap to the exact landing pose; prevents any residual offset.
				if part.Parent ~= nil then
					part.CFrame = endCFrame
				end

				-- Avoid a brief "blur" caused by two overlapping SurfaceGuis (the landing VFX text
				-- and the final captured plate text) being visible at the same time.
				if vfxSurfaceLabel.Parent ~= nil then
					vfxSurfaceLabel.TextTransparency = 1
					vfxSurfaceLabel.TextStrokeTransparency = 1
				end
				if vfxSurfaceGui.Parent ~= nil then
					vfxSurfaceGui.Enabled = false
				end

				-- Landed: reveal the normal overlay/text for this cell.
				revealFinalCapturedForKey(key)

				if part.Parent == nil then
					return
				end
				task.wait(holdAfter)
				if part.Parent == nil then
					return
				end
				local fadeOut = TweenService:Create(
					part,
					TweenInfo.new(VFX_FADE_OUT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Transparency = 1 }
				)
				TweenService:Create(
					vfxSurfaceLabel,
					TweenInfo.new(VFX_FADE_OUT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ TextTransparency = 1, TextStrokeTransparency = 1 }
				):Play()
				fadeOut:Play()
				fadeOut.Completed:Wait()
				pcall(function()
					part:Destroy()
				end)
			end)

			-- Failsafe: never keep the cell hidden forever.
			task.delay(1.8, function()
				if landedRevealByKey[key] then
					return
				end
				if marker.Parent == nil then
					return
				end
				revealFinalCapturedForKey(key)
			end)
		end
	end

	-- Run cinematic.
	cinematicRunning = true
	lastCinematicAt = now

	local ok, err = pcall(function()
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = originalFov

		local outTween = TweenService:Create(
			cam,
			TweenInfo.new(CAMERA_OUT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = targetCFrame }
		)
		outTween:Play()
		outTween.Completed:Wait()

		-- Show VFX while the region is framed.
		spawnCaptureVfx()

		task.wait(CAMERA_HOLD_SECONDS)

		local backTween = TweenService:Create(
			cam,
			TweenInfo.new(CAMERA_BACK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ CFrame = originalCFrame }
		)
		backTween:Play()
		backTween.Completed:Wait()

		restoreCamera(cam, originalType, originalCFrame, originalFov)
	end)

	if not ok then
		warn("[CapturedCellCountdown] Camera cinematic failed:", err)
		restoreCamera(cam, originalType, originalCFrame, originalFov)
	end

	cinematicRunning = false
end

local function flushPendingCameraKeys()
	if pendingCameraFlushScheduled then
		return
	end
	pendingCameraFlushScheduled = true

	-- Aggregate keys for a single capture event (markers are added one-by-one).
	task.delay(0.08, function()
		pendingCameraFlushScheduled = false
		local keys: { string } = {}
		for key in pairs(pendingCameraKeys) do
			pendingCameraKeys[key] = nil
			table.insert(keys, key)
		end
		if #keys > 0 then
			playCaptureCameraCinematic(keys)
		end
	end)
end

local function enqueueCameraForMarker(marker: Instance)
	local key = marker.Name
	local ownerUserId = tryGetCaptureOwnerUserId(marker)
	if ownerUserId == player.UserId then
		if canStartCaptureCinematic() then
			hideFinalCapturedForKey(key)
		end
		pendingCameraKeys[key] = true
		flushPendingCameraKeys()
		return
	end

	-- Attributes can replicate after the child instance; wait briefly.
	local conn: RBXScriptConnection? = nil
	conn = marker:GetAttributeChangedSignal("CaptureOwnerUserId"):Connect(function()
		local v = tryGetCaptureOwnerUserId(marker)
		if v == player.UserId then
			if canStartCaptureCinematic() then
				hideFinalCapturedForKey(key)
			end
			pendingCameraKeys[key] = true
			flushPendingCameraKeys()
			if conn then
				conn:Disconnect()
				conn = nil
			end
		end
	end)
	-- Safety disconnect.
	task.delay(2, function()
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end)
end

local baseplate: BasePart? = nil
getBaseplate = function(): BasePart?
	if baseplate and baseplate:IsDescendantOf(Workspace) then
		return baseplate
	end
	local inst = Workspace:FindFirstChild("Baseplate")
	if inst and inst:IsA("BasePart") then
		baseplate = inst
		return inst
	end
	baseplate = nil
	return nil
end

local function destroyEntry(key: string)
	local entry = entriesByKey[key]
	if not entry then
		return
	end
	entriesByKey[key] = nil
	delayedRevealByKey[key] = nil
	landedRevealByKey[key] = nil
	pcall(function()
		entry.gui:Destroy()
	end)
	pcall(function()
		entry.attachment:Destroy()
	end)
	pcall(function()
		entry.plate:Destroy()
	end)
end

getHintRotationForLocalPlayer = function(): number
	local cornerId = player:GetAttribute("CornerId")
	if type(cornerId) ~= "number" then
		return 0
	end
	cornerId = math.floor(cornerId)
	if cornerId == 1 or cornerId == 2 then
		return 180
	end
	return 0
end

local function computeLuminance(c: Color3): number
	return (0.2126 * c.R) + (0.7152 * c.G) + (0.0722 * c.B)
end

applyCapturedTextStyle = function(label: TextLabel, marker: Instance)
	local captureColor = marker:GetAttribute("CaptureColor")
	if typeof(captureColor) == "Color3" then
		local lum = computeLuminance(captureColor)
		if lum >= 0.72 then
			-- Bright (e.g. white team): use a dark text color so it reads on light fills.
			label.TextColor3 = Color3.fromRGB(25, 25, 25)
			label.TextStrokeColor3 = Color3.new(0, 0, 0)
			label.TextStrokeTransparency = 0
		else
			-- Darker colors: white text with black stroke.
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeColor3 = Color3.new(0, 0, 0)
			label.TextStrokeTransparency = 0
		end
	else
		-- Fallback if attributes haven't replicated yet.
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0
	end
end

local function createCapturedPlate(bp: BasePart, key: string, ix: number, iz: number): (BasePart, SurfaceGui, TextLabel, number)
	local xCenter, zCenter = GridCells.GetCellCenterLocalXZ(bp, ix, iz)
	local yLocal = (bp.Size.Y / 2) + (CAPTURED_PLATE_THICKNESS / 2) + CAPTURED_PLATE_Y_OFFSET
	local diagonalRotation = if ((ix + iz) % 2) == 0 then CAPTURED_DIAGONAL_ROT_A else CAPTURED_DIAGONAL_ROT_B

	local plate = Instance.new("Part")
	plate.Name = "CapturedCellPlate_" .. key
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanTouch = false
	plate.CanQuery = false
	plate.CastShadow = false
	plate.Transparency = 1
	plate.Material = Enum.Material.SmoothPlastic
	plate.Size = Vector3.new(GridCells.SQUARE_SIZE_STUDS, CAPTURED_PLATE_THICKNESS, GridCells.SQUARE_SIZE_STUDS)
	plate.CFrame = bp.CFrame * CFrame.new(xCenter, yLocal, zCenter)
	plate.Locked = true
	plate.Parent = bp

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "CapturedCellSurfaceGui_" .. key
	surfaceGui.Adornee = plate
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.AlwaysOnTop = false
	surfaceGui.LightInfluence = 0
	surfaceGui.ResetOnSpawn = false
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = CAPTURED_PIXELS_PER_STUD
	surfaceGui.Enabled = false
	surfaceGui.Parent = plate

	local surfaceLabel = Instance.new("TextLabel")
	surfaceLabel.Name = "Text"
	surfaceLabel.BackgroundTransparency = 1
	surfaceLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	surfaceLabel.Position = UDim2.fromScale(0.5, 0.5)
	surfaceLabel.Size = UDim2.fromScale(1.3, 1.3)
	surfaceLabel.Text = CAPTURED_TEXT
	surfaceLabel.TextScaled = true
	surfaceLabel.TextWrapped = true
	surfaceLabel.Font = Enum.Font.LuckiestGuy
	-- Colors/stroke are applied after we have the marker (CaptureColor attribute may replicate later).
	surfaceLabel.TextColor3 = Color3.new(1, 1, 1)
	surfaceLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	surfaceLabel.TextStrokeTransparency = 0
	surfaceLabel.Rotation = getHintRotationForLocalPlayer() + diagonalRotation
	surfaceLabel.Parent = surfaceGui

	return plate, surfaceGui, surfaceLabel, diagonalRotation
end

local function computeRemaining(marker: Instance): number?
	local expiresAt = marker:GetAttribute("ExpiresAt")
	if type(expiresAt) ~= "number" then
		return nil
	end
	local now = Workspace:GetServerTimeNow()
	local remaining = math.ceil(expiresAt - now)
	if remaining < 0 then
		remaining = 0
	end
	return remaining
end

local function createEntryForMarker(marker: Instance)
	local key = marker.Name
	if entriesByKey[key] then
		return
	end

	local bp = getBaseplate()
	if not bp then
		return
	end

	local ix, iz = GridCells.ParseCellKey(key)
	if ix == nil or iz == nil then
		return
	end

	local xCenter, zCenter = GridCells.GetCellCenterLocalXZ(bp, ix, iz)
	local attach = Instance.new("Attachment")
	attach.Name = "CaptureCountdown_" .. key
	attach.Position = Vector3.new(xCenter, (bp.Size.Y / 2) + 0.9, zCenter)
	attach.Parent = bp

	local gui = Instance.new("BillboardGui")
	gui.Name = "CaptureCountdownGui_" .. key
	gui.Adornee = attach
	gui.AlwaysOnTop = true
	gui.MaxDistance = MAX_DISTANCE
	gui.Size = GUI_SIZE
	gui.StudsOffsetWorldSpace = Vector3.zero
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.TextSize = TEXT_SIZE
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = ""
	label.Parent = gui

	local plate, surfaceGui, surfaceLabel, diagonalRotation = createCapturedPlate(bp, key, ix, iz)
	applyCapturedTextStyle(surfaceLabel, marker)

	entriesByKey[key] = {
		key = key,
		marker = marker,
		attachment = attach,
		gui = gui,
		label = label,
		plate = plate,
		surfaceGui = surfaceGui,
		surfaceLabel = surfaceLabel,
		diagonalRotation = diagonalRotation,
		lastRemaining = -1,
	}
end

refreshAll = function()
	for key, entry in pairs(entriesByKey) do
		if entry.marker.Parent == nil then
			destroyEntry(key)
			continue
		end
		local remaining = computeRemaining(entry.marker)
		if remaining == nil then
			-- If the server didn't set ExpiresAt (or it hasn't replicated yet), hide until it does.
			entry.gui.Enabled = false
			entry.surfaceGui.Enabled = false
			continue
		end
		if remaining <= 0 then
			-- Let ChildRemoved do cleanup, but hide immediately.
			entry.gui.Enabled = false
			entry.surfaceGui.Enabled = false
			continue
		end
		if delayedRevealByKey[key] and not landedRevealByKey[key] then
			entry.gui.Enabled = false
			entry.surfaceGui.Enabled = false
			continue
		end
		entry.gui.Enabled = true
		entry.surfaceGui.Enabled = true
		entry.surfaceLabel.Rotation = getHintRotationForLocalPlayer() + entry.diagonalRotation
		applyCapturedTextStyle(entry.surfaceLabel, entry.marker)
		if remaining ~= entry.lastRemaining then
			entry.lastRemaining = remaining
			entry.label.Text = tostring(remaining)
		end
	end
end

local function hookFolder(folder: Folder)
	folder.ChildAdded:Connect(function(child)
		createEntryForMarker(child)
		enqueueCameraForMarker(child)
		refreshAll()
	end)
	folder.ChildRemoved:Connect(function(child)
		destroyEntry(child.Name)
	end)

	for _, child in ipairs(folder:GetChildren()) do
		createEntryForMarker(child)
	end
	refreshAll()
end

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild(CAPTURED_BLOCKS_FOLDER_NAME)
	if not folder or not folder:IsA("Folder") then
		return
	end
	hookFolder(folder)

	while true do
		-- Update at 1Hz; this keeps it cheap even with hundreds of cells.
		task.wait(1)
		refreshAll()
	end
end)
