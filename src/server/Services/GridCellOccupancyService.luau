-- ServerScriptService.Services.GridCellOccupancyService
-- Tracks which grid cells are occupied by NPCs and provides replicated state + world overlays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

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

-- Territory leaderstats: percentage of baseplate cells occupied by a player's NPCs.
local TERRITORY_LEADERSTAT_NAME = "Territory%"
local occupiedCountByUserId: { [number]: number } = {}
local ownerUserIdByKey: { [string]: number } = {}
local cachedBaseplate: BasePart? = nil
local cachedTotalCells: number = 0

local function getTotalCells(): number
	if cachedBaseplate and cachedBaseplate:IsDescendantOf(workspace) then
		return cachedTotalCells
	end
	cachedBaseplate = GridCells.FindBaseplate()
	if not cachedBaseplate then
		cachedTotalCells = 0
		return 0
	end
	local cellsX, cellsZ = GridCells.GetCellCounts(cachedBaseplate)
	cachedTotalCells = math.max(0, math.floor(cellsX)) * math.max(0, math.floor(cellsZ))
	return cachedTotalCells
end

local function ensureTerritoryValue(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end
	local v = leaderstats:FindFirstChild(TERRITORY_LEADERSTAT_NAME)
	if v and v:IsA("IntValue") then
		return v
	end
	v = Instance.new("IntValue")
	v.Name = TERRITORY_LEADERSTAT_NAME
	v.Value = 0
	v.Parent = leaderstats
	return v :: IntValue
end

local function updateTerritoryForUserId(userId: number)
	if type(userId) ~= "number" or userId <= 0 then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	local totalCells = getTotalCells()
	local occupied = occupiedCountByUserId[userId] or 0
	local pct = 0
	if totalCells > 0 and occupied > 0 then
		pct = math.floor((occupied * 100) / totalCells + 0.5)
		if pct < 0 then
			pct = 0
		elseif pct > 100 then
			pct = 100
		end
	end
	local v = ensureTerritoryValue(player)
	if v then
		v.Value = pct
	end
end

do
	local function onPlayer(player: Player)
		-- Defer to let PlayerDataService create leaderstats.
		task.defer(function()
			updateTerritoryForUserId(player.UserId)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

-- reservation/occupied state is kept server-side for atomicity.
local reservedByKey: { [string]: { teamColorName: string } } = {}
local blockedByKey: {
	[string]: {
		kind: string?,
		userId: number?,
	}
} = {}
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
	return reservedByKey[key] ~= nil or occupiedByKey[key] ~= nil or blockedByKey[key] ~= nil
end

-- Blocks a cell key without spawning an NPC (used for static obstacles like castles).
-- Replicates a marker folder under ReplicatedStorage/CellOccupancy so clients can treat it as blocked.
-- Returns false if the key is currently reserved/occupied by an NPC.
function Shared.BlockCellKey(key: string, kind: string?, userId: number?): boolean
	if blockedByKey[key] ~= nil then
		return true
	end
	if reservedByKey[key] ~= nil or occupiedByKey[key] ~= nil then
		return false
	end

	-- If a marker already exists (e.g. from a previous session), treat it as blocked to avoid overwriting.
	local existingMarker = occupancyFolder:FindFirstChild(key)
	if existingMarker ~= nil then
		blockedByKey[key] = { kind = kind, userId = userId }
		return true
	end

	blockedByKey[key] = { kind = kind, userId = userId }

	local marker = Instance.new("Folder")
	marker.Name = key
	marker:SetAttribute("Blocked", true)
	if type(kind) == "string" and kind ~= "" then
		marker:SetAttribute("BlockKind", kind)
	end
	if type(userId) == "number" then
		marker:SetAttribute("BlockingUserId", userId)
	end
	marker.Parent = occupancyFolder

	return true
end

function Shared.UnblockCellKey(key: string)
	blockedByKey[key] = nil
	local marker = occupancyFolder:FindFirstChild(key)
	if marker and marker:IsA("Folder") and marker:GetAttribute("Blocked") == true then
		marker:Destroy()
	end
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
	if marker and marker:GetAttribute("Blocked") ~= true then
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
	local ownerUserId = ownerUserIdByKey[key]
	if type(ownerUserId) == "number" and ownerUserId > 0 then
		ownerUserIdByKey[key] = nil
		local prev = occupiedCountByUserId[ownerUserId] or 0
		local nextCount = prev - 1
		if nextCount < 0 then
			nextCount = 0
		end
		occupiedCountByUserId[ownerUserId] = nextCount
		updateTerritoryForUserId(ownerUserId)
	end

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
	if marker and marker:GetAttribute("Blocked") ~= true then
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
	local baseTeamColor3 = TeamColors.GetColor3(teamColorName)
	local ix, iz = GridCells.ParseCellKey(key)
	local overlayColor3 = baseTeamColor3
	if ix ~= nil and iz ~= nil then
		overlayColor3 = TeamColors.GetCheckerboardVariantColor3(baseTeamColor3, ix, iz)
	end

	local marker = occupancyFolder:FindFirstChild(key)
	if not marker then
		marker = Instance.new("Folder")
		marker.Name = key
		marker.Parent = occupancyFolder
	end
	marker:SetAttribute("TeamColorName", teamColorName)
	marker:SetAttribute("TeamColor3", baseTeamColor3)
	marker:SetAttribute("OverlayColor3", overlayColor3)
	marker:SetAttribute("Reserved", false)
	marker:SetAttribute("Occupied", true)

	local overlay: BasePart? = nil
	if baseplate then
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
			part.Color = overlayColor3
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

	local ownerUserId = Affiliation.GetOwnerUserIdFromModel(npc)
	if ownerUserId > 0 then
		ownerUserIdByKey[key] = ownerUserId
		occupiedCountByUserId[ownerUserId] = (occupiedCountByUserId[ownerUserId] or 0) + 1
		updateTerritoryForUserId(ownerUserId)
	end

	return true
end

return Shared
