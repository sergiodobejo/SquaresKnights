-- StarterPlayer.StarterPlayerScripts.CapturedCellCountdown
-- Shows a 5-second countdown number above temporarily-captured cells.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))

local CAPTURED_BLOCKS_FOLDER_NAME = "CapturedCellBlocks"

local TEXT_SIZE = 18
local MAX_DISTANCE = 120
local GUI_SIZE = UDim2.fromOffset(40, 40)

local CAPTURED_TEXT = "Captured"
local CAPTURED_PLATE_THICKNESS = 0.05
-- Place above the server-side captured overlay (keeps existing overlay intact).
local CAPTURED_PLATE_Y_OFFSET = 0.44
local CAPTURED_PIXELS_PER_STUD = 48

local CAPTURED_DIAGONAL_ROT_A = 45
local CAPTURED_DIAGONAL_ROT_B = -45

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local baseplate: BasePart? = nil
local function getBaseplate(): BasePart?
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

local function destroyEntry(key: string)
	local entry = entriesByKey[key]
	if not entry then
		return
	end
	entriesByKey[key] = nil
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

local function getHintRotationForLocalPlayer(): number
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

local function applyCapturedTextStyle(label: TextLabel, marker: Instance)
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

local function refreshAll()
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
