-- ServerScriptService.CastleSpawnOnJoin
--
-- On player join:
-- 1) Clones ReplicatedStorage/Buildings/SM_Castle
-- 2) Places it in a corner of Workspace/Baseplate (based on team id)
-- 3) Applies team building texture
-- 4) Spawns/teleports the player near their castle

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TeamColorService = require(script.Parent:WaitForChild("Services"):WaitForChild("TeamColorService"))
local GridCellOccupancyService = require(script.Parent:WaitForChild("Services"):WaitForChild("GridCellOccupancyService"))
local CastleHealthService = require(script.Parent:WaitForChild("Services"):WaitForChild("CastleHealthService"))
local OpenArenaCornerReservationService = require(script.Parent:WaitForChild("Services"):WaitForChild("OpenArenaCornerReservationService"))
local PlayerDataService = require(ServerScriptService.Services:WaitForChild("PlayerDataService"))
local WarriorValueService = require(ServerScriptService.Services:WaitForChild("WarriorValueService"))
local TeamTextures = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("TeamTextures"))
local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))

local BASEPLATE_NAME = "Baseplate"
local BUILDINGS_FOLDER_NAME = "Buildings"
local CASTLE_MODEL_NAME = "SM_Castle"

local CASTLE_MARGIN = 0
local SPAWN_MARGIN = 14
local SPAWN_HEIGHT = 4

local CASTLE_YAW_ADJUST_DEG = 135 -- counter-clockwise

local TEAM_COLOR_ATTRIBUTE = "TeamColor"

local CORNER_ID_ATTRIBUTE = "CornerId" -- 1..4, used for baseplate corner placement

local OPEN_ARENA_START_COINS_APPLIED_ATTRIBUTE = "OpenArenaStartCoinsApplied"

local function waitForCoinsValue(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = player:WaitForChild("leaderstats", 5)
	end
	if not (leaderstats and leaderstats:IsA("Folder")) then
		return nil
	end
	local coins = leaderstats:FindFirstChild("Coins")
	if not coins then
		coins = leaderstats:WaitForChild("Coins", 5)
	end
	if coins and coins:IsA("IntValue") then
		return coins
	end
	return nil
end

local function applyOpenArenaStartingCoinsIfNeeded(player: Player)
	if player:GetAttribute(OPEN_ARENA_START_COINS_APPLIED_ATTRIBUTE) == true then
		return
	end

	if not OpenArenaCornerReservationService.IsActive() then
		return
	end

	local maxSum: number? = nil
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local coins = PlayerDataService.GetCoins(other)
			local warriorValue = WarriorValueService.GetWarriorValue(other)
			local sum = coins + warriorValue
			if maxSum == nil or sum > maxSum then
				maxSum = sum
			end
		end
	end

	-- If this is the first player, keep default starting coins.
	if maxSum == nil then
		pcall(function()
			player:SetAttribute(OPEN_ARENA_START_COINS_APPLIED_ATTRIBUTE, true)
		end)
		return
	end

	local coinsValue = waitForCoinsValue(player)
	if coinsValue then
		coinsValue.Value = math.max(0, math.floor(maxSum))
		pcall(function()
			player:SetAttribute(OPEN_ARENA_START_COINS_APPLIED_ATTRIBUTE, true)
		end)
	else
		-- Try again shortly if leaderstats aren't ready yet.
		task.delay(0.5, function()
			local coinsValueRetry = waitForCoinsValue(player)
			if coinsValueRetry then
				coinsValueRetry.Value = math.max(0, math.floor(maxSum :: number))
			end
			pcall(function()
				player:SetAttribute(OPEN_ARENA_START_COINS_APPLIED_ATTRIBUTE, true)
			end)
		end)
	end
end

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

local function normalizeAssetId(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	if value == "" then
		return nil
	end
	if string.find(value, "rbxassetid://", 1, true) then
		return value
	end
	if string.match(value, "^%d+$") then
		return "rbxassetid://" .. value
	end
	return value
end

local function applyBuildingTextureForPlayer(model: Model, player: Player)
	local colorName = player:GetAttribute(TEAM_COLOR_ATTRIBUTE)
	if type(colorName) ~= "string" or colorName == "" then
		return
	end

	local cfg = TeamTextures[colorName]
	if type(cfg) ~= "table" then
		return
	end

	local textureId = normalizeAssetId(cfg.Buildings)
	if not textureId then
		return
	end

	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("MeshPart") then
			pcall(function()
				(inst :: MeshPart).TextureID = textureId
			end)
		elseif inst:IsA("SurfaceAppearance") then
			pcall(function()
				(inst :: SurfaceAppearance).ColorMap = textureId
			end)
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			pcall(function()
				(inst :: any).Texture = textureId
			end)
		end
	end
end

local function anchorAllParts(model: Model)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			pcall(function()
				(inst :: BasePart).Anchored = true
			end)
		end
	end
end

local function getTeamIdForPlayer(player: Player): number
	local colorName = TeamColorService.GetColorForPlayer(player)
	if type(colorName) == "string" then
		local teamId = TeamColorService.GetTeamIdForColor(colorName)
		if type(teamId) == "number" then
			return teamId
		end
	end
	return 1
end

local function getCornerSignsForCornerId(cornerId: number): (number, number)
	-- 1: (-X,-Z)  2: (+X,-Z)  3: (-X,+Z)  4: (+X,+Z)
	if cornerId == 2 then
		return 1, -1
	elseif cornerId == 3 then
		return -1, 1
	elseif cornerId == 4 then
		return 1, 1
	end
	return -1, -1
end

local function computePivotForDesiredBoundingBox(model: Model, desiredBoundingBoxCFrame: CFrame): CFrame
	local pivot = model:GetPivot()
	local actualBbCf, _ = model:GetBoundingBox()
	local offset = pivot:ToObjectSpace(actualBbCf)
	return desiredBoundingBoxCFrame * offset:Inverse()
end

local function computeCastleAndSpawnCFrames(baseplate: BasePart, castle: Model, cornerId: number): (CFrame, CFrame)
	local baseplateCf = baseplate.CFrame
	local halfX = baseplate.Size.X / 2
	local halfZ = baseplate.Size.Z / 2

	local _, bbSize = castle:GetBoundingBox()
	local signX, signZ = getCornerSignsForCornerId(cornerId)

	local offsetX = signX * (halfX - bbSize.X / 2 - CASTLE_MARGIN)
	local offsetZ = signZ * (halfZ - bbSize.Z / 2 - CASTLE_MARGIN)
	local offsetY = baseplate.Size.Y / 2 + bbSize.Y / 2

	local desiredPos = (baseplateCf * CFrame.new(offsetX, offsetY, offsetZ)).Position
	local baseCenter = baseplateCf.Position
	local lookAtPos = Vector3.new(baseCenter.X, desiredPos.Y, baseCenter.Z)
	-- Fixed rotation relative to the corner: face toward baseplate center.
	local desiredBbCf = CFrame.lookAt(desiredPos, lookAtPos) * CFrame.Angles(0, math.rad(CASTLE_YAW_ADJUST_DEG), 0)
	local castlePivotCf = computePivotForDesiredBoundingBox(castle, desiredBbCf)

	-- Spawn on the side of the castle that faces the baseplate center.
	-- Also ensure the position stays within the baseplate bounds.
	local dirToCenterFlat = Vector3.new(baseCenter.X - desiredPos.X, 0, baseCenter.Z - desiredPos.Z)
	local dir = if dirToCenterFlat.Magnitude > 1e-6 then dirToCenterFlat.Unit else Vector3.new(0, 0, -1)

	-- Rough radius in XZ so we spawn outside the castle footprint.
	local castleRadiusXZ = math.sqrt((bbSize.X * 0.5) ^ 2 + (bbSize.Z * 0.5) ^ 2)
	local spawnOffsetY = -bbSize.Y / 2 + SPAWN_HEIGHT
	local spawnDistance = castleRadiusXZ + SPAWN_MARGIN

	-- Add slight sideways randomness so players don't stack perfectly.
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local sideJitter = (math.random(-600, 600) / 100) -- +/- 6 studs
	local spawnPos = desiredPos + Vector3.new(0, spawnOffsetY, 0) + dir * spawnDistance + side * sideJitter

	local localPos = baseplateCf:PointToObjectSpace(spawnPos)
	local clampX = halfX - SPAWN_MARGIN
	local clampZ = halfZ - SPAWN_MARGIN
	localPos = Vector3.new(
		math.clamp(localPos.X, -clampX, clampX),
		localPos.Y,
		math.clamp(localPos.Z, -clampZ, clampZ)
	)
	spawnPos = baseplateCf:PointToWorldSpace(localPos)

	local spawnLookAtPos = Vector3.new(baseplate.Position.X, spawnPos.Y, baseplate.Position.Z)
	local spawnCf = CFrame.lookAt(spawnPos, spawnLookAtPos)

	return castlePivotCf, spawnCf
end

local function getBaseplate(): BasePart?
	local bp = workspace:FindFirstChild(BASEPLATE_NAME)
	if bp and bp:IsA("BasePart") then
		return bp
	end
	return nil
end

local function getCastleTemplate(): Model?
	local buildings = ReplicatedStorage:FindFirstChild(BUILDINGS_FOLDER_NAME)
	if not buildings then
		return nil
	end
	local castle = buildings:FindFirstChild(CASTLE_MODEL_NAME)
	if castle and castle:IsA("Model") then
		return castle
	end
	return nil
end

local castlesByUserId: { [number]: Model } = {}
local spawnCFrameByUserId: { [number]: CFrame } = {}

local blockedCellKeysByUserId: { [number]: { string } } = {}

local CASTLE_BLOCK_INSET_CELLS = 0
local CASTLE_BLOCK_SIZE_CELLS = 2

local function unblockCastleCellsForUserId(userId: number)
	local keys = blockedCellKeysByUserId[userId]
	if not keys then
		return
	end
	blockedCellKeysByUserId[userId] = nil
	for _, key in ipairs(keys) do
		GridCellOccupancyService.UnblockCellKey(key)
	end
end


local function computeBlockedCellRectForCorner(baseplate: BasePart, cornerId: number): (number, number, number, number)
	local cellsX, cellsZ = GridCells.GetCellCounts(baseplate)
	local signX, signZ = getCornerSignsForCornerId(cornerId)

	local function axisRange(cells: number, sign: number): (number, number)
		if cells <= 0 then
			return 0, -1
		end
		if sign < 0 then
			local startIx = CASTLE_BLOCK_INSET_CELLS
			local endIx = CASTLE_BLOCK_INSET_CELLS + (CASTLE_BLOCK_SIZE_CELLS - 1)
			startIx = math.clamp(startIx, 0, cells - 1)
			endIx = math.clamp(endIx, 0, cells - 1)
			return startIx, endIx
		else
			local endIx = (cells - 1) - CASTLE_BLOCK_INSET_CELLS
			local startIx = endIx - (CASTLE_BLOCK_SIZE_CELLS - 1)
			startIx = math.clamp(startIx, 0, cells - 1)
			endIx = math.clamp(endIx, 0, cells - 1)
			return startIx, endIx
		end
	end

	local ixA, ixB = axisRange(cellsX, signX)
	local izA, izB = axisRange(cellsZ, signZ)
	local ixMin = math.min(ixA, ixB)
	local ixMax = math.max(ixA, ixB)
	local izMin = math.min(izA, izB)
	local izMax = math.max(izA, izB)
	return ixMin, ixMax, izMin, izMax
end

local function computeBlockedCellKeysForCorner(baseplate: BasePart, cornerId: number): { string }
	local ixMin, ixMax, izMin, izMax = computeBlockedCellRectForCorner(baseplate, cornerId)
	local keys: { string } = {}
	for ix = ixMin, ixMax do
		for iz = izMin, izMax do
			if GridCells.IsIndexWithinBaseplate(baseplate, ix, iz) then
				table.insert(keys, GridCells.GetCellKey(ix, iz))
			end
		end
	end
	return keys
end

local function blockCastleCellsForPlayer(player: Player, baseplate: BasePart, cornerId: number)
	local keys = computeBlockedCellKeysForCorner(baseplate, cornerId)
	local blockedKeys: { string } = {}
	for _, key in ipairs(keys) do
		local ok = GridCellOccupancyService.BlockCellKey(key, "Castle", player.UserId)
		if ok then
			table.insert(blockedKeys, key)
		end
	end
	blockedCellKeysByUserId[player.UserId] = blockedKeys
end

local cornerIdByUserId: { [number]: number } = {}
local occupiedCornerIds: { [number]: boolean } = {}

local function getOrAssignCornerIdForPlayer(player: Player): number
	local userId = player.UserId

	local existing = cornerIdByUserId[userId]
	if existing then
		return existing
	end

	-- Allow forcing corner via attribute (useful for debugging / tests).
	local attr = player:GetAttribute(CORNER_ID_ATTRIBUTE)
	if type(attr) == "number" then
		local forced = math.floor(attr)
		if forced >= 1 and forced <= 4 and not occupiedCornerIds[forced] then
			cornerIdByUserId[userId] = forced
			occupiedCornerIds[forced] = true
			player:SetAttribute(CORNER_ID_ATTRIBUTE, forced)
			return forced
		end
	end

	for cornerId = 1, 4 do
		if not occupiedCornerIds[cornerId] then
			cornerIdByUserId[userId] = cornerId
			occupiedCornerIds[cornerId] = true
			player:SetAttribute(CORNER_ID_ATTRIBUTE, cornerId)
			return cornerId
		end
	end

	-- Should not happen for your constraints (2..4 players). Fall back to a stable corner.
	warn(string.format("[CastleSpawnOnJoin] No free cornerId for userId=%d; reusing corner 1", userId))
	cornerIdByUserId[userId] = 1
	player:SetAttribute(CORNER_ID_ATTRIBUTE, 1)
	return 1
end

local function ensureCastleForPlayer(player: Player)
	unblockCastleCellsForUserId(player.UserId)

	local baseplate = getBaseplate()
	if not baseplate then
		warn("[CastleSpawnOnJoin] Workspace/" .. BASEPLATE_NAME .. " not found")
		return
	end

	local template = getCastleTemplate()
	if not template then
		warn("[CastleSpawnOnJoin] ReplicatedStorage/Buildings/SM_Castle not found")
		return
	end

	local cornerId = getOrAssignCornerIdForPlayer(player)

	-- Open Arena: initialize/consume corner reservations.
	-- For non-Open-Arena servers, this service is inactive and these calls are no-ops.
	if OpenArenaCornerReservationService.IsActive() then
		local reserved = OpenArenaCornerReservationService.GetReservedColorForCorner(cornerId)
		if type(reserved) == "string" and reserved ~= "" then
			TeamColorService.AssignPlayerSpecific(player, reserved)
		else
			TeamColorService.AssignPlayer(player)
		end
		OpenArenaCornerReservationService.ClearReservationForCorner(cornerId)
	else
		-- Ensure team color exists (idempotent).
		TeamColorService.AssignPlayer(player)
		-- If this is the first Open Arena player, activate and reserve the other corners.
		OpenArenaCornerReservationService.MaybeActivateForFirstPlayer(player, baseplate, cornerId)
		if OpenArenaCornerReservationService.IsActive() then
			-- After activation, keep reservations in sync with currently-occupied corners.
			OpenArenaCornerReservationService.ApplyReservations(baseplate, occupiedCornerIds)
		end
	end
	local clone = template:Clone()
	clone.Name = string.format("%s_%d", CASTLE_MODEL_NAME, player.UserId)
	anchorAllParts(clone)
	applyBuildingTextureForPlayer(clone, player)

	-- Stamp affiliation + health for combat systems.
	-- Use the same TeamId semantics as NPCs/players.
	local teamId = getTeamIdForPlayer(player)
	CastleHealthService.InitCastle(clone, teamId, player.UserId, 3000)

	local castlePivotCf, spawnCf = computeCastleAndSpawnCFrames(baseplate, clone, cornerId)

	pcall(function()
		clone:PivotTo(castlePivotCf)
	end)

	local root = getOrCreateFolder(workspace, "PlayerBuildings")
	-- Hot-reload safety: remove existing castle for this player to prevent duplicates.
	local existing = root:FindFirstChild(clone.Name)
	if existing and existing:IsA("Model") then
		existing:Destroy()
	end
	clone.Parent = root

	-- Store the grid-based footprint rectangle for AI targeting/distance checks.
	local ixMin, ixMax, izMin, izMax = computeBlockedCellRectForCorner(baseplate, cornerId)
	pcall(function()
		clone:SetAttribute("CastleBlockIxMin", ixMin)
		clone:SetAttribute("CastleBlockIxMax", ixMax)
		clone:SetAttribute("CastleBlockIzMin", izMin)
		clone:SetAttribute("CastleBlockIzMax", izMax)
		clone:SetAttribute("CastleCornerId", cornerId)
	end)

	blockCastleCellsForPlayer(player, baseplate, cornerId)

	if OpenArenaCornerReservationService.IsActive() then
		OpenArenaCornerReservationService.ApplyReservations(baseplate, occupiedCornerIds)
	end

	clone.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil then
			return
		end
		if castlesByUserId[player.UserId] == clone then
			unblockCastleCellsForUserId(player.UserId)
		end
	end)

	castlesByUserId[player.UserId] = clone
	spawnCFrameByUserId[player.UserId] = spawnCf
end

local function teleportCharacterToSpawn(player: Player, character: Model)
	local spawnCf = spawnCFrameByUserId[player.UserId]
	if not spawnCf then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		local hrpWaited = character:WaitForChild("HumanoidRootPart", 5)
		if not (hrpWaited and hrpWaited:IsA("BasePart")) then
			return
		end
		hrp = hrpWaited
	end

	pcall(function()
		(character :: Model):PivotTo(spawnCf)
	end)
end

local function onPlayerAdded(player: Player)
	ensureCastleForPlayer(player)
	applyOpenArenaStartingCoinsIfNeeded(player)

	player.CharacterAdded:Connect(function(character)
		-- Defer so Humanoid/HRP are guaranteed to exist.
		task.defer(function()
			teleportCharacterToSpawn(player, character)
		end)
	end)

	-- If character already exists (hot reload)
	if player.Character then
		task.defer(function()
			teleportCharacterToSpawn(player, player.Character :: Model)
		end)
	end
end

local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	spawnCFrameByUserId[userId] = nil
	unblockCastleCellsForUserId(userId)

	local cornerId = cornerIdByUserId[userId]
	cornerIdByUserId[userId] = nil
	if cornerId then
		occupiedCornerIds[cornerId] = nil
	end

	if OpenArenaCornerReservationService.IsActive() then
		local baseplate = getBaseplate()
		if baseplate then
			OpenArenaCornerReservationService.ApplyReservations(baseplate, occupiedCornerIds)
		end
	end

	local castle = castlesByUserId[userId]
	castlesByUserId[userId] = nil
	if castle and castle.Parent then
		-- In non-OpenArena 1v1, treat leaving as losing your castle.
		-- This intentionally goes through CastleHealthService so CastleDefeatHandler receives
		-- the same OnCastleDestroyed signal as it does for damage-based destruction.
		local remainingPlayers = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				remainingPlayers += 1
			end
		end
		if (not OpenArenaCornerReservationService.IsActive()) and (remainingPlayers == 1) then
			local ok = false
			pcall(function()
				ok = CastleHealthService.ApplyDamage(castle, CastleHealthService.GetMaxHealth(castle) + 1, nil)
			end)
			if ok then
				return
			end
		end
		castle:Destroy()
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	task.defer(onPlayerAdded, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Hot-reload safety: if castles already exist, ensure health/billboard is initialized.
pcall(function()
	CastleHealthService.TryInitExisting()
end)

return {}
