-- StarterPlayer.StarterPlayerScripts.JoinIntroCamera
-- Plays a short camera cinematic once when the local player joins: player in foreground, castle in background.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local INTRO_DELAY_SECONDS = 0.35

-- Show an initial wide shot (player foreground, their castle background),
-- then release back to the default camera on first user interaction.

local CASTLE_ROOT_FOLDER_NAME = "PlayerBuildings"
local CASTLE_MODEL_BASE_NAME = "SM_Castle"

local INTRO_DISTANCE = 14
local INTRO_HEIGHT = 7
local INTRO_LOOK_UP = 2.5
local INTRO_LOOK_AHEAD_MIN = 10
local INTRO_LOOK_AHEAD_MAX = 45

local ran = false

local function getCurrentCamera(): Camera?
	local cam = Workspace.CurrentCamera
	if cam and cam:IsA("Camera") then
		return cam
	end
	return nil
end

local function getHumanoidRootPart(character: Model?): BasePart?
	if not character then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function getPlayerCastle(): Model?
	local root = Workspace:FindFirstChild(CASTLE_ROOT_FOLDER_NAME)
	if not root or not root:IsA("Folder") then
		return nil
	end
	local name = string.format("%s_%d", CASTLE_MODEL_BASE_NAME, player.UserId)
	local inst = root:FindFirstChild(name)
	if inst and inst:IsA("Model") then
		return inst
	end
	return nil
end

local function getCastlePos(castle: Model): Vector3?
	local ok, bbCf = pcall(function()
		local cf, _ = castle:GetBoundingBox()
		return cf
	end)
	if ok and typeof(bbCf) == "CFrame" then
		return (bbCf :: CFrame).Position
	end
	local ok2, pivot = pcall(function()
		return castle:GetPivot()
	end)
	if ok2 and typeof(pivot) == "CFrame" then
		return (pivot :: CFrame).Position
	end
	return nil
end

local function waitForCastle(timeoutSeconds: number): Model?
	local t0 = os.clock()
	while os.clock() - t0 < timeoutSeconds do
		local castle = getPlayerCastle()
		if castle then
			return castle
		end
		task.wait(0.1)
	end
	return nil
end

local function computeWideCFrame(cam: Camera, playerPos: Vector3, castlePos: Vector3): CFrame
	local toCastle = Vector3.new(castlePos.X - playerPos.X, 0, castlePos.Z - playerPos.Z)
	local dir: Vector3
	if toCastle.Magnitude > 1e-3 then
		dir = toCastle.Unit
	else
		local look = cam.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 1e-3 then
			flat = Vector3.new(0, 0, -1)
		end
		dir = flat.Unit
	end

	local cameraPos = playerPos - dir * INTRO_DISTANCE + Vector3.new(0, INTRO_HEIGHT, 0)
	local lookAhead = math.clamp(toCastle.Magnitude * 0.35, INTRO_LOOK_AHEAD_MIN, INTRO_LOOK_AHEAD_MAX)
	local lookAt = playerPos + dir * lookAhead + Vector3.new(0, INTRO_LOOK_UP, 0)
	return CFrame.lookAt(cameraPos, lookAt)
end

local function getHumanoid(character: Model?): Humanoid?
	if not character then
		return nil
	end
	local h = character:FindFirstChildOfClass("Humanoid")
	if h then
		return h
	end
	local maybe = character:FindFirstChild("Humanoid")
	if maybe and maybe:IsA("Humanoid") then
		return maybe
	end
	return nil
end

local function waitForCharacterAndHrp(timeoutSeconds: number): (Model?, BasePart?)
	local t0 = os.clock()
	while os.clock() - t0 < timeoutSeconds do
		local character = player.Character
		local hrp = getHumanoidRootPart(character)
		if character and hrp then
			return character, hrp
		end
		player.CharacterAdded:Wait()
		task.wait(0.05)
	end
	return nil, nil
end


local function runIntroOnce()
	if ran then
		return
	end
	if player.UserId <= 0 then
		return
	end

	ran = true

	task.wait(INTRO_DELAY_SECONDS)

	local cam = getCurrentCamera()
	if not cam then
		return
	end
	-- Avoid fighting other cinematics.
	if cam.CameraType == Enum.CameraType.Scriptable then
		return
	end

	-- Wait a frame so the default camera scripts settle on their spawn view.
	RunService.RenderStepped:Wait()

	local _, hrp = waitForCharacterAndHrp(6)
	if not hrp then
		return
	end

	local wideCFrame: CFrame? = nil
	local castle = waitForCastle(6)
	if castle then
		local castlePos = getCastlePos(castle)
		if castlePos then
			wideCFrame = computeWideCFrame(cam, hrp.Position, castlePos)
		end
	end

	local originalType = cam.CameraType
	local originalFov = cam.FieldOfView
	local originalSubject = cam.CameraSubject
	local originalCFrame = cam.CFrame

	local released = false
	local inputConnA: RBXScriptConnection? = nil
	local inputConnB: RBXScriptConnection? = nil
	local moveConn: RBXScriptConnection? = nil

	local function release()
		if released then
			return
		end
		released = true

		if inputConnA then
			inputConnA:Disconnect()
			inputConnA = nil
		end
		if inputConnB then
			inputConnB:Disconnect()
			inputConnB = nil
		end
		if moveConn then
			moveConn:Disconnect()
			moveConn = nil
		end

		pcall(function()
			cam.FieldOfView = originalFov
			local humanoid = getHumanoid(player.Character)
			if humanoid then
				cam.CameraSubject = humanoid
			elseif originalSubject ~= nil then
				cam.CameraSubject = originalSubject
			end
			cam.CameraType = originalType
		end)
	end

	local ok, err = pcall(function()
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = originalFov
		cam.CFrame = wideCFrame or originalCFrame

		-- Release on any user interaction (tap/click/keyboard/gamepad).
		inputConnA = UserInputService.InputBegan:Connect(function()
			release()
		end)
		inputConnB = UserInputService.InputChanged:Connect(function(input)
			-- Thumbsticks/analog don't always fire InputBegan.
			if input.UserInputType == Enum.UserInputType.Gamepad1 then
				release()
			end
		end)

		-- Release when movement starts.
		moveConn = RunService.RenderStepped:Connect(function()
			local character = player.Character
			local humanoid = getHumanoid(character)
			if humanoid and humanoid.MoveDirection.Magnitude > 0.05 then
				release()
			end
		end)

		-- Sit in the spawn view until the player acts.
		while not released do
			RunService.RenderStepped:Wait()
		end
	end)

	-- Cleanup in case we error before the normal handoff path.
	if inputConnA then
		inputConnA:Disconnect()
		inputConnA = nil
	end
	if inputConnB then
		inputConnB:Disconnect()
		inputConnB = nil
	end
	if moveConn then
		moveConn:Disconnect()
		moveConn = nil
	end

	if not ok then
		warn("[JoinIntroCamera] Intro cinematic failed:", err)
		pcall(function()
			cam.CameraType = originalType
			cam.FieldOfView = originalFov
		end)
	end
end

task.spawn(runIntroOnce)
