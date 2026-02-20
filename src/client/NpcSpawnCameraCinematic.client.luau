-- StarterPlayer.StarterPlayerScripts.NpcSpawnCameraCinematic
-- Plays a short camera cinematic when the local player's NPC spawns.
-- Uses the same tween timings and framing strategy as CapturedCellCountdown's capture cinematic,
-- but with a lower lift (height is divided by 1.5).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local RuntimeSettings = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("RuntimeSettings"))

local LOCAL_PLAYER = Players.LocalPlayer

local LIVE_NPC_FOLDER_NAME = "LiveNPC"

-- Match capture cinematic timings (CapturedCellCountdown).
local CAMERA_OUT_SECONDS = 0.45
local CAMERA_HOLD_SECONDS = RuntimeSettings.CaptureCinematicCameraHoldSeconds
local CAMERA_BACK_SECONDS = 0.45
local CAMERA_COOLDOWN_SECONDS = 2.5

-- Match capture cinematic framing (CapturedCellCountdown).
local CAMERA_MIN_DISTANCE = 34
local CAMERA_HEIGHT_RATIO = 0.7
local CAMERA_MAX_HORIZONTAL_DISTANCE = 450

-- "Поднимается в 1.5 раза ниже".
local HEIGHT_DIVISOR = 1.5

local cinematicRunning = false
local lastCinematicAt = -1e9

local function restoreCamera(cam: Camera, originalType: Enum.CameraType, originalCFrame: CFrame, originalFov: number)
	pcall(function()
		-- If we captured Scriptable (due to overlapping cinematics), always fall back to normal player camera.
		cam.CameraType = if originalType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else originalType
		cam.CFrame = originalCFrame
		cam.FieldOfView = originalFov
	end)

	pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)

	pcall(function()
		local character = LOCAL_PLAYER.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			cam.CameraSubject = humanoid
		end
	end)

	-- Failsafe: if anything still left Scriptable, force back to Custom next tick.
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

local function getCurrentCamera(): Camera?
	local cam = Workspace.CurrentCamera
	if cam then
		return cam
	end
	return Workspace:FindFirstChildOfClass("Camera")
end

local function getNpcFocusWorld(npc: Model): Vector3?
	if npc.PrimaryPart then
		return npc.PrimaryPart.Position
	end
	local hrp = npc:FindFirstChild("HumanoidRootPart", true)
	if hrp and hrp:IsA("BasePart") then
		return (hrp :: BasePart).Position
	end
	local ok, pivot = pcall(function()
		return npc:GetPivot()
	end)
	if ok and typeof(pivot) == "CFrame" then
		return (pivot :: CFrame).Position
	end
	return nil
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

local function chooseCinematicCameraCFrame(cam: Camera, lookAtWorld: Vector3, horizontalBack: Vector3, distance: number, height: number, ignore: { Instance }): CFrame
	local up = Vector3.new(0, 1, 0)
	local back = Vector3.new(horizontalBack.X, 0, horizontalBack.Z)
	if back.Magnitude < 1e-3 then
		back = Vector3.new(0, 0, 1)
	else
		back = back.Unit
	end
	local left = Vector3.new(-back.Z, 0, back.X)
	local right = -left

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

local function canStartCinematic(cam: Camera): boolean
	if cinematicRunning then
		return false
	end
	-- Avoid fighting other cinematics.
	if cam.CameraType == Enum.CameraType.Scriptable then
		return false
	end
	return (os.clock() - lastCinematicAt) >= CAMERA_COOLDOWN_SECONDS
end

local function playNpcSpawnCinematic(npc: Model)
	local cam = getCurrentCamera()
	if not cam then
		return
	end
	if not canStartCinematic(cam) then
		return
	end

	local focus = getNpcFocusWorld(npc)
	if not focus then
		return
	end

	local horizontalBack = getHorizontalBackVectorFromCamera(cam)

	local distance = CAMERA_MIN_DISTANCE
	if distance > CAMERA_MAX_HORIZONTAL_DISTANCE then
		distance = CAMERA_MAX_HORIZONTAL_DISTANCE
	end
	local height = ((distance * CAMERA_HEIGHT_RATIO) + 10) / HEIGHT_DIVISOR
	local lookAtWorld = focus + Vector3.new(0, 1.0, 0)

	local ignore: { Instance } = { npc }
	local character = LOCAL_PLAYER.Character
	if character then
		table.insert(ignore, character)
	end
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		table.insert(ignore, baseplate)
	end
	for _, name in ipairs({ "CellOverlays", "ReservedCellOverlays", "CapturedCellOverlays" }) do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end

	local targetCFrame = chooseCinematicCameraCFrame(cam, lookAtWorld, horizontalBack, distance, height, ignore)

	local originalType = cam.CameraType
	local originalCFrame = cam.CFrame
	local originalFov = cam.FieldOfView

	cinematicRunning = true
	lastCinematicAt = os.clock()

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
		warn("[NpcSpawnCameraCinematic] NPC spawn cinematic failed:", err)
		restoreCamera(cam, originalType, originalCFrame, originalFov)
	end

	cinematicRunning = false
end

local function waitForOwnerUserId(npc: Model, timeoutSeconds: number): number
	local deadline = os.clock() + timeoutSeconds
	while os.clock() < deadline do
		local owner = Affiliation.GetOwnerUserIdFromModel(npc)
		if owner > 0 then
			return owner
		end
		task.wait(0.05)
	end
	return Affiliation.GetOwnerUserIdFromModel(npc)
end

local function main()
	local liveNpcFolder = Workspace:FindFirstChild(LIVE_NPC_FOLDER_NAME)
	if not liveNpcFolder then
		liveNpcFolder = Workspace:WaitForChild(LIVE_NPC_FOLDER_NAME, 30)
	end
	if not liveNpcFolder or not liveNpcFolder:IsA("Folder") then
		warn("[NpcSpawnCameraCinematic] Workspace.LiveNPC folder not found")
		return
	end

	-- Do not play cinematics for NPCs that already existed before this script started.
	local seen = setmetatable(({} :: { [Instance]: boolean }), { __mode = "k" })
	for _, child in ipairs((liveNpcFolder :: Folder):GetChildren()) do
		seen[child] = true
	end

	liveNpcFolder.ChildAdded:Connect(function(child: Instance)
		if seen[child] then
			return
		end
		seen[child] = true
		if not child:IsA("Model") then
			return
		end

		-- Let replication finish stamping affiliation attributes.
		task.spawn(function()
			local npc = child :: Model
			local ownerUserId = waitForOwnerUserId(npc, 0.6)
			if ownerUserId ~= LOCAL_PLAYER.UserId then
				return
			end
			playNpcSpawnCinematic(npc)
		end)
	end)
end

main()
