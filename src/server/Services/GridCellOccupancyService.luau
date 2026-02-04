-- ServerScriptService.Services.GridCellOccupancyService
-- Tracks which grid cells are occupied by NPCs and provides replicated state + world overlays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))
local TeamColors = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("TeamColors"))
local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local TeamColorService = require(ServerScriptService.Services:WaitForChild("TeamColorService"))

local OCCUPANCY_FOLDER_NAME = "CellOccupancy"
local OVERLAY_FOLDER_NAME = "CellOverlays"

local OVERLAY_HEIGHT = 0.18
local OVERLAY_Y_GAP = 0.02
local OVERLAY_TRANSPARENCY = 0

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

local function getHumanoid(model: Model): Humanoid?
	local h = model:FindFirstChildOfClass("Humanoid")
	if h then
		return h
	end
	local maybe = model:FindFirstChild("Humanoid")
	if maybe and maybe:IsA("Humanoid") then
		return maybe
	end
	return nil
end

local function ensureReplicatedFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(OCCUPANCY_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = OCCUPANCY_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureOverlayFolder(): Folder
	return getOrCreateFolder(workspace, OVERLAY_FOLDER_NAME)
end

local occupancyFolder = ensureReplicatedFolder()
local overlayFolder = ensureOverlayFolder()

-- reservation/occupied state is kept server-side for atomicity.
local reservedByKey: { [string]: { teamColorName: string } } = {}
local occupiedByKey: {
	[string]: {
		teamColorName: string,
		npc: Model,
		overlay: BasePart?,
		connections: { RBXScriptConnection },
	}
} = {}

local Shared = {}

function Shared.GetReplicatedFolder(): Folder
	return occupancyFolder
end

function Shared.IsBlocked(key: string): boolean
	return reservedByKey[key] ~= nil or occupiedByKey[key] ~= nil
end

function Shared.TryReserveCellKey(key: string, teamColorName: string): boolean
	if Shared.IsBlocked(key) then
		return false
	end

	reservedByKey[key] = { teamColorName = teamColorName }

	local marker = Instance.new("Folder")
	marker.Name = key
	marker:SetAttribute("TeamColorName", teamColorName)
	marker:SetAttribute("Reserved", true)
	marker.Parent = occupancyFolder

	return true
end

function Shared.CancelReservation(key: string)
	reservedByKey[key] = nil
	local marker = occupancyFolder:FindFirstChild(key)
	if marker then
		marker:Destroy()
	end
end

local function destroyOverlayForKey(key: string)
	local existing = overlayFolder:FindFirstChild(key)
	if existing and existing:IsA("BasePart") then
		existing:Destroy()
	end
end

function Shared.FreeCellKey(key: string)
	local entry = occupiedByKey[key]
	if not entry then
		Shared.CancelReservation(key)
		return
	end

	occupiedByKey[key] = nil

	for _, conn in ipairs(entry.connections) do
		pcall(function()
			conn:Disconnect()
		end)
	end

	destroyOverlayForKey(key)

	local marker = occupancyFolder:FindFirstChild(key)
	if marker then
		marker:Destroy()
	end
end

function Shared.FinalizeReservation(key: string, npc: Model, baseplate: BasePart?): boolean
	local reservation = reservedByKey[key]
	if not reservation then
		return false
	end
	if occupiedByKey[key] then
		return false
	end

	reservedByKey[key] = nil

	local teamColorName = reservation.teamColorName
	local npcTeamId = Affiliation.GetTeamIdFromModel(npc)
	local actualColorName = TeamColorService.GetColorForTeamId(npcTeamId)
	if actualColorName then
		teamColorName = actualColorName
	end
	local teamColor3 = TeamColors.GetColor3(teamColorName)

	local marker = occupancyFolder:FindFirstChild(key)
	if not marker then
		marker = Instance.new("Folder")
		marker.Name = key
		marker.Parent = occupancyFolder
	end
	marker:SetAttribute("TeamColorName", teamColorName)
	marker:SetAttribute("TeamColor3", teamColor3)
	marker:SetAttribute("Reserved", false)
	marker:SetAttribute("Occupied", true)

	local overlay: BasePart? = nil
	if baseplate then
		local ix, iz = GridCells.ParseCellKey(key)
		if ix ~= nil and iz ~= nil then
			destroyOverlayForKey(key)
			local part = Instance.new("Part")
			part.Name = key
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Material = Enum.Material.Concrete
			part.Reflectance = 0
			part.Color = teamColor3
			part.Transparency = OVERLAY_TRANSPARENCY
			part.Size = Vector3.new(GridCells.SQUARE_SIZE_STUDS, OVERLAY_HEIGHT, GridCells.SQUARE_SIZE_STUDS)
			part.CFrame = GridCells.GetCellCFrameOnTop(baseplate, ix, iz, (OVERLAY_HEIGHT / 2) + OVERLAY_Y_GAP)
			part.Parent = overlayFolder
			overlay = part
		end
	end

	local connections: { RBXScriptConnection } = {}
	local function free()
		Shared.FreeCellKey(key)
	end

	table.insert(connections, npc.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			free()
		end
	end))

	local humanoid = getHumanoid(npc)
	if humanoid then
		table.insert(connections, humanoid.Died:Connect(function()
			free()
		end))
	end

	occupiedByKey[key] = {
		teamColorName = teamColorName,
		npc = npc,
		overlay = overlay,
		connections = connections,
	}

	return true
end

return Shared
