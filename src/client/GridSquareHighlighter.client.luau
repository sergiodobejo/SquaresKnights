-- StarterPlayer.StarterPlayerScripts.GridSquareHighlighter

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))
local SQUARE_SIZE = GridCells.SQUARE_SIZE_STUDS

local OUTLINE_HEIGHT = 0.12
local EDGE_WIDTH = 0.22
local HEIGHT_OFFSET = 0.02

local COLOR = Color3.fromRGB(0, 255, 170)
local TRANSPARENCY = 0.25

local occupancyFolder: Folder? = nil
local capturedBlocksFolder: Folder? = nil

local CAPTURED_BLOCKS_FOLDER_NAME = "CapturedCellBlocks"

local function isCellBlocked(cellKey: string): boolean
	if not occupancyFolder or not occupancyFolder:IsDescendantOf(ReplicatedStorage) then
		local inst = ReplicatedStorage:FindFirstChild("CellOccupancy")
		if inst and inst:IsA("Folder") then
			occupancyFolder = inst
		else
			occupancyFolder = nil
		end
	end
	if not capturedBlocksFolder or not capturedBlocksFolder:IsDescendantOf(ReplicatedStorage) then
		local inst = ReplicatedStorage:FindFirstChild(CAPTURED_BLOCKS_FOLDER_NAME)
		if inst and inst:IsA("Folder") then
			capturedBlocksFolder = inst
		else
			capturedBlocksFolder = nil
		end
	end

	local occupied = (occupancyFolder ~= nil and occupancyFolder:FindFirstChild(cellKey) ~= nil)
	local captured = (capturedBlocksFolder ~= nil and capturedBlocksFolder:FindFirstChild(cellKey) ~= nil)
	return occupied or captured
end

local function findBaseplate(): BasePart?
	local inst = Workspace:FindFirstChild("Baseplate")
	if inst and inst:IsA("BasePart") then
		return inst
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

local function createEdgeAdornment(name: string): BoxHandleAdornment
	local adornment = Instance.new("BoxHandleAdornment")
	adornment.Name = name
	adornment.AlwaysOnTop = true
	adornment.ZIndex = 10
	adornment.Color3 = COLOR
	adornment.Transparency = TRANSPARENCY
	adornment.Visible = false
	return adornment
end

local player = Players.LocalPlayer
local edgeNorth = createEdgeAdornment("GridSquareEdgeNorth")
local edgeSouth = createEdgeAdornment("GridSquareEdgeSouth")
local edgeWest = createEdgeAdornment("GridSquareEdgeWest")
local edgeEast = createEdgeAdornment("GridSquareEdgeEast")

edgeNorth.Parent = Workspace
edgeSouth.Parent = Workspace
edgeWest.Parent = Workspace
edgeEast.Parent = Workspace

local baseplate: BasePart? = nil
local lastIx: number? = nil
local lastIz: number? = nil
local lastBaseplate: BasePart? = nil

local function setVisible(visible: boolean)
	if edgeNorth.Visible ~= visible then
		edgeNorth.Visible = visible
		edgeSouth.Visible = visible
		edgeWest.Visible = visible
		edgeEast.Visible = visible
	end
end

local function update()
	if baseplate == nil or not baseplate:IsDescendantOf(Workspace) then
		baseplate = findBaseplate()
	end

	local character = player.Character
	local hrp = getHumanoidRootPart(character)
	if not hrp or not baseplate then
		setVisible(false)
		return
	end

	local ix, iz = GridCells.GetCellIndexFromWorld(baseplate, hrp.Position)
	if ix == nil or iz == nil then
		setVisible(false)
		return
	end

	local cellKey = GridCells.GetCellKey(ix, iz)
	if isCellBlocked(cellKey) then
		setVisible(false)
		return
	end

	if ix ~= lastIx or iz ~= lastIz or baseplate ~= lastBaseplate then
		lastIx = ix
		lastIz = iz
		lastBaseplate = baseplate

		local halfX = baseplate.Size.X / 2
		local halfZ = baseplate.Size.Z / 2
		local xCenter = -halfX + (ix * SQUARE_SIZE) + (SQUARE_SIZE / 2)
		local zCenter = -halfZ + (iz * SQUARE_SIZE) + (SQUARE_SIZE / 2)
		local half = SQUARE_SIZE / 2
		local edgeInset = half - (EDGE_WIDTH / 2)
		local y = (baseplate.Size.Y / 2) + (OUTLINE_HEIGHT / 2) + HEIGHT_OFFSET

		edgeNorth.Adornee = baseplate
		edgeSouth.Adornee = baseplate
		edgeWest.Adornee = baseplate
		edgeEast.Adornee = baseplate

		-- North/South edges run along X, thin along Z.
		edgeNorth.Size = Vector3.new(SQUARE_SIZE, OUTLINE_HEIGHT, EDGE_WIDTH)
		edgeSouth.Size = Vector3.new(SQUARE_SIZE, OUTLINE_HEIGHT, EDGE_WIDTH)
		edgeNorth.CFrame = CFrame.new(xCenter, y, zCenter - edgeInset)
		edgeSouth.CFrame = CFrame.new(xCenter, y, zCenter + edgeInset)

		-- West/East edges run along Z, thin along X.
		edgeWest.Size = Vector3.new(EDGE_WIDTH, OUTLINE_HEIGHT, SQUARE_SIZE)
		edgeEast.Size = Vector3.new(EDGE_WIDTH, OUTLINE_HEIGHT, SQUARE_SIZE)
		edgeWest.CFrame = CFrame.new(xCenter - edgeInset, y, zCenter)
		edgeEast.CFrame = CFrame.new(xCenter + edgeInset, y, zCenter)
	end

	setVisible(true)
end

RunService.RenderStepped:Connect(update)
