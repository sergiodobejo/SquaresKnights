-- ServerScriptService.Services.GridCellOccupancyService
-- Tracks which grid cells are occupied by NPCs and provides replicated state + world overlays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))
local TeamColors = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("TeamColors"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ShopConfig"))
local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local TeamColorService = require(ServerScriptService.Services:WaitForChild("TeamColorService"))
local NpcSpawnService = require(ServerScriptService.Services:WaitForChild("NpcSpawnService"))

local OCCUPANCY_FOLDER_NAME = "CellOccupancy"
local OVERLAY_FOLDER_NAME = "CellOverlays"
local CAPTURED_BLOCKS_FOLDER_NAME = "CapturedCellBlocks"

-- Duration for temporary capture highlight + block.
local CAPTURE_HIGHLIGHT_SECONDS = 5

local CAPTURE_SPAWN_ITEM_KEY = "Priest"
local CAPTURE_SPAWN_HEIGHT_ABOVE_SURFACE = 4.2
local SKIP_CAPTURE_CHECK_ATTRIBUTE = "SkipCaptureCheck"
local NPC_CELL_KEY_ATTRIBUTE = "CellKey"

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

local function ensureCapturedBlocksFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(CAPTURED_BLOCKS_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = CAPTURED_BLOCKS_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local capturedBlocksFolder = ensureCapturedBlocksFolder()
local capturedBlockRefCountByKey: { [string]: number } = {}

local function getCaptureExpiresAt(): number
	-- Use server-synced time so clients can compute remaining time.
	return workspace:GetServerTimeNow() + CAPTURE_HIGHLIGHT_SECONDS
end

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

-- Capture detection (enclosed empty regions)
local CAPTURE_OVERLAY_FOLDER_NAME = "CapturedCellOverlays"
local CAPTURE_OVERLAY_HEIGHT = 0.12
local CAPTURE_OVERLAY_Y_GAP = 0.28
local CAPTURE_OVERLAY_TRANSPARENCY = 0.35

local function ensureCaptureOverlayFolder(): Folder
	return getOrCreateFolder(workspace, CAPTURE_OVERLAY_FOLDER_NAME)
end

local function withinBounds(ix: number, iz: number, cellsX: number, cellsZ: number): boolean
	return ix >= 0 and iz >= 0 and ix < cellsX and iz < cellsZ
end

local function isTrulyEmptyKey(key: string): boolean
	return reservedByKey[key] == nil and occupiedByKey[key] == nil and blockedByKey[key] == nil
end

local function getPriestModelName(): string
	local cfg = ShopConfig.GetConfig(CAPTURE_SPAWN_ITEM_KEY)
	local modelName = cfg and (cfg :: any).NpcModelName
	if type(modelName) == "string" and modelName ~= "" then
		return modelName
	end
	return "SK_Priest"
end

local function spawnFreePriestOnCell(baseplate: BasePart, cellKey: string, userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end

	-- Only spawn into truly-empty cells.
	if not isTrulyEmptyKey(cellKey) then
		return
	end

	local teamColorName = TeamColorService.GetColorForPlayer(player)
	if type(teamColorName) ~= "string" or teamColorName == "" then
		teamColorName = (player:GetAttribute(TeamColorService.Attributes.TeamColor) :: any)
	end
	if type(teamColorName) ~= "string" or teamColorName == "" then
		teamColorName = "white"
	end

	if not Shared.TryReserveCellKey(cellKey, teamColorName) then
		return
	end

	local ix, iz = GridCells.ParseCellKey(cellKey)
	if ix == nil or iz == nil then
		Shared.CancelReservation(cellKey)
		return
	end

	local spawnPos = GridCells.GetCellCFrameOnTop(baseplate, ix, iz, CAPTURE_SPAWN_HEIGHT_ABOVE_SURFACE).Position
	local priestModelName = getPriestModelName()
	local npc = NpcSpawnService.SpawnUnitAtPosition(player, priestModelName, spawnPos)
	if not npc then
		Shared.CancelReservation(cellKey)
		return
	end

	pcall(function()
		npc:SetAttribute(SKIP_CAPTURE_CHECK_ATTRIBUTE, true)
	end)
	Shared.FinalizeReservation(cellKey, npc, baseplate)
end

local function isTrulyEmpty(ix: number, iz: number, cellsX: number, cellsZ: number): boolean
	if not withinBounds(ix, iz, cellsX, cellsZ) then
		return false
	end
	return isTrulyEmptyKey(GridCells.GetCellKey(ix, iz))
end

local function isWallOfPlayer(ix: number, iz: number, userId: number, cellsX: number, cellsZ: number): boolean
	if not withinBounds(ix, iz, cellsX, cellsZ) then
		return false
	end
	local key = GridCells.GetCellKey(ix, iz)
	if occupiedByKey[key] ~= nil and ownerUserIdByKey[key] == userId then
		return true
	end

	-- If the player's own castle footprint blocks a cell, count it as a valid boundary wall.
	local block = blockedByKey[key]
	if block ~= nil and block.kind == "Castle" and block.userId == userId then
		return true
	end

	return false
end

local function floodFillEmptyRegion(startIx: number, startIz: number, cellsX: number, cellsZ: number, visited: { [string]: boolean }): ({ string }, { [string]: boolean }, boolean)
	local regionKeys: { string } = {}
	local regionSet: { [string]: boolean } = {}
	local touchesBorder = false

	local queueIx: { number } = {}
	local queueIz: { number } = {}
	local head = 1

	local function push(ix: number, iz: number)
		local key = GridCells.GetCellKey(ix, iz)
		if visited[key] then
			return
		end
		if not isTrulyEmptyKey(key) then
			return
		end
		visited[key] = true
		table.insert(queueIx, ix)
		table.insert(queueIz, iz)
	end

	push(startIx, startIz)

	while head <= #queueIx do
		local ix = queueIx[head]
		local iz = queueIz[head]
		head += 1

		local key = GridCells.GetCellKey(ix, iz)
		if not regionSet[key] then
			regionSet[key] = true
			table.insert(regionKeys, key)
		end

		if ix == 0 or iz == 0 or ix == (cellsX - 1) or iz == (cellsZ - 1) then
			touchesBorder = true
		end

		-- 4-neighbor expansion
		if ix > 0 then
			push(ix - 1, iz)
		end
		if ix < cellsX - 1 then
			push(ix + 1, iz)
		end
		if iz > 0 then
			push(ix, iz - 1)
		end
		if iz < cellsZ - 1 then
			push(ix, iz + 1)
		end
	end

	return regionKeys, regionSet, touchesBorder
end

local function isRegionEnclosedByPlayer(regionKeys: { string }, regionSet: { [string]: boolean }, userId: number, cellsX: number, cellsZ: number): boolean
	for _, key in ipairs(regionKeys) do
		local ix, iz = GridCells.ParseCellKey(key)
		if ix == nil or iz == nil then
			return false
		end

		-- Check boundary in 8-neighborhood.
		for dx = -1, 1 do
			for dz = -1, 1 do
				if dx == 0 and dz == 0 then
					continue
				end
				local nx = (ix :: number) + dx
				local nz = (iz :: number) + dz
				if not withinBounds(nx, nz, cellsX, cellsZ) then
					-- If region doesn't touch border, this shouldn't happen.
					return false
				end

				local nKey = GridCells.GetCellKey(nx, nz)
				if regionSet[nKey] then
					continue
				end

				if isTrulyEmptyKey(nKey) then
					continue
				end

				-- Any non-empty neighbor must be player's occupied cell.
				if not isWallOfPlayer(nx, nz, userId, cellsX, cellsZ) then
					return false
				end
			end
		end
	end

	return true
end

local function isCaptureDebugEnabled(): boolean
	return workspace:GetAttribute("DebugCapture") == true
end

local function getNonWallReasonForKey(key: string, userId: number): string
	if occupiedByKey[key] ~= nil then
		local owner = ownerUserIdByKey[key]
		if owner == userId then
			return "ownOccupied"
		end
		return "otherOccupied:" .. tostring(owner)
	end
	if blockedByKey[key] ~= nil then
		local b = blockedByKey[key]
		return "blocked:" .. tostring(b.kind)
	end
	if reservedByKey[key] ~= nil then
		return "reserved"
	end
	if capturedBlockRefCountByKey[key] ~= nil or capturedBlocksFolder:FindFirstChild(key) ~= nil then
		return "capturedBlock"
	end
	-- Shouldn't happen (non-empty but not in our maps), but useful for debugging.
	return "unknownNonEmpty"
end

local function getEnclosureFailureSummary(regionKeys: { string }, regionSet: { [string]: boolean }, userId: number, cellsX: number, cellsZ: number): string
	local counts: { [string]: number } = {}
	local sample: string? = nil
	local checked = 0
	local maxChecks = 5000

	for _, key in ipairs(regionKeys) do
		checked += 1
		if checked > maxChecks then
			break
		end
		local ix, iz = GridCells.ParseCellKey(key)
		if ix == nil or iz == nil then
			return "badKey"
		end
		for dx = -1, 1 do
			for dz = -1, 1 do
				if dx == 0 and dz == 0 then
					continue
				end
				local nx = (ix :: number) + dx
				local nz = (iz :: number) + dz
				if not withinBounds(nx, nz, cellsX, cellsZ) then
					counts.outOfBounds = (counts.outOfBounds or 0) + 1
					if not sample then
						sample = string.format("oob neighbor at %s -> (%d,%d)", key, nx, nz)
					end
					continue
				end

				local nKey = GridCells.GetCellKey(nx, nz)
				if regionSet[nKey] then
					continue
				end
				if isTrulyEmptyKey(nKey) then
					continue
				end
				if isWallOfPlayer(nx, nz, userId, cellsX, cellsZ) then
					continue
				end

				local reason = getNonWallReasonForKey(nKey, userId)
				counts[reason] = (counts[reason] or 0) + 1
				if not sample then
					sample = string.format("non-wall neighbor %s at (%d,%d) touching region cell %s", reason, nx, nz, key)
				end
			end
		end
	end

	local pieces: { string } = {}
	for reason, count in pairs(counts) do
		table.insert(pieces, string.format("%s=%d", reason, count))
	end
	table.sort(pieces)
	local summary = table.concat(pieces, ",")
	if sample then
		return summary .. " | sample: " .. sample
	end
	return summary ~= "" and summary or "noDetails"
end

local function highlightCapturedRegion(baseplate: BasePart, userId: number, color3: Color3, regionKeys: { string })
	if #regionKeys == 0 then
		return
	end

	local captureFolder = ensureCaptureOverlayFolder()
	local stamp = string.format("%d_%d", userId, math.floor(os.clock() * 1000))
	local eventFolder = Instance.new("Folder")
	eventFolder.Name = "Capture_" .. stamp
	eventFolder.Parent = captureFolder

	for _, key in ipairs(regionKeys) do
		-- Replicated marker: prevents spawn-preview highlight for everyone while active.
		capturedBlockRefCountByKey[key] = (capturedBlockRefCountByKey[key] or 0) + 1
		local marker = capturedBlocksFolder:FindFirstChild(key)
		if marker == nil then
			marker = Instance.new("Folder")
			marker.Name = key
			marker.Parent = capturedBlocksFolder
		end
		local newExpiresAt = getCaptureExpiresAt()
		local existingExpiresAt = marker:GetAttribute("ExpiresAt")
		if type(existingExpiresAt) ~= "number" or existingExpiresAt < newExpiresAt then
			marker:SetAttribute("ExpiresAt", newExpiresAt)
		end

		local ix, iz = GridCells.ParseCellKey(key)
		if ix ~= nil and iz ~= nil then
			local p = Instance.new("Part")
			p.Name = key
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Material = Enum.Material.Neon
			p.Color = color3
			p.Transparency = CAPTURE_OVERLAY_TRANSPARENCY
			p.Size = Vector3.new(GridCells.SQUARE_SIZE_STUDS, CAPTURE_OVERLAY_HEIGHT, GridCells.SQUARE_SIZE_STUDS)
			p.CFrame = GridCells.GetCellCFrameOnTop(baseplate, ix, iz, (CAPTURE_OVERLAY_HEIGHT / 2) + CAPTURE_OVERLAY_Y_GAP)
			p.Parent = eventFolder
		end
	end

	task.delay(CAPTURE_HIGHLIGHT_SECONDS, function()
		if eventFolder.Parent ~= nil then
			eventFolder:Destroy()
		end
		local endedKeys: { string } = {}
		for _, key in ipairs(regionKeys) do
			local prev = capturedBlockRefCountByKey[key] or 0
			local nextCount = prev - 1
			if nextCount <= 0 then
				capturedBlockRefCountByKey[key] = nil
				local marker = capturedBlocksFolder:FindFirstChild(key)
				if marker and marker:IsA("Folder") then
					marker:Destroy()
				end
				table.insert(endedKeys, key)
			else
				capturedBlockRefCountByKey[key] = nextCount
			end
		end

		-- When capture highlight ends, spawn free Priests on those cells.
		for _, key in ipairs(endedKeys) do
			spawnFreePriestOnCell(baseplate, key, userId)
		end
	end)
end

local function checkCapturesAroundKey(baseplate: BasePart, key: string, userId: number, color3: Color3)
	if userId <= 0 then
		return
	end
	local ix, iz = GridCells.ParseCellKey(key)
	if ix == nil or iz == nil then
		return
	end
	local cellsX, cellsZ = GridCells.GetCellCounts(baseplate)
	if cellsX <= 0 or cellsZ <= 0 then
		return
	end

	local visited: { [string]: boolean } = {}
	local neighborStarts: { { number } } = {}
	for dx = -1, 1 do
		for dz = -1, 1 do
			if dx == 0 and dz == 0 then
				continue
			end
			table.insert(neighborStarts, { (ix :: number) + dx, (iz :: number) + dz })
		end
	end

	local debug = isCaptureDebugEnabled()
	if debug then
		print(string.format("[CaptureDebug] checkCapturesAroundKey placed=%s userId=%d", key, userId))
	end

	for _, pair in ipairs(neighborStarts) do
		local nx = pair[1]
		local nz = pair[2]
		if withinBounds(nx, nz, cellsX, cellsZ) and isTrulyEmpty(nx, nz, cellsX, cellsZ) then
			local regionKeys, regionSet, touchesBorder = floodFillEmptyRegion(nx, nz, cellsX, cellsZ, visited)
			if #regionKeys == 0 then
				if debug then
					print(string.format("[CaptureDebug] SKIP empty region start=(%d,%d)", nx, nz))
				end
				continue
			end
			local enclosed = (not touchesBorder) and isRegionEnclosedByPlayer(regionKeys, regionSet, userId, cellsX, cellsZ)
			if enclosed then
				if debug then
					print(string.format("[CaptureDebug] CAPTURED start=(%d,%d) size=%d", nx, nz, #regionKeys))
				end
				highlightCapturedRegion(baseplate, userId, color3, regionKeys)
			else
				if debug then
					local reason = touchesBorder and "touchesBorder" or getEnclosureFailureSummary(regionKeys, regionSet, userId, cellsX, cellsZ)
					print(string.format("[CaptureDebug] NOT captured start=(%d,%d) size=%d reason=%s", nx, nz, #regionKeys, reason))
				end
			end
		end
	end
end

function Shared.GetReplicatedFolder(): Folder
	return occupancyFolder
end

function Shared.IsBlocked(key: string): boolean
	if reservedByKey[key] ~= nil or occupiedByKey[key] ~= nil or blockedByKey[key] ~= nil then
		return true
	end
	if capturedBlockRefCountByKey[key] ~= nil then
		return true
	end
	-- Fallback in case a marker exists without refcount (e.g. leftover instances).
	return capturedBlocksFolder:FindFirstChild(key) ~= nil
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

	pcall(function()
		npc:SetAttribute(NPC_CELL_KEY_ATTRIBUTE, key)
	end)

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
		local skipCapture = npc:GetAttribute(SKIP_CAPTURE_CHECK_ATTRIBUTE) == true
		if baseplate and not skipCapture then
			checkCapturesAroundKey(baseplate, key, ownerUserId, baseTeamColor3)
		end
	end

	return true
end

return Shared
