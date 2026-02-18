-- ServerScriptService.Services.OpenArenaCornerReservationService
-- Reserves castle corner cells + team colors for "Open Arena" servers.
--
-- Goals:
-- - When the first player arrives via Open Arena teleport, pre-reserve the other corners.
-- - Reserved corners are blocked so NPC spawning cannot use those cells.
-- - Each corner has a pre-chosen unique team color; joining players inherit the corner color.
-- - Reservation state is replicated to clients (ReplicatedStorage/CornerReservations) for hatched highlights.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EntryType = require(ReplicatedStorage:WaitForChild("EntryType"))
local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))

local ServerScriptService = game:GetService("ServerScriptService")
local TeamColorService = require(ServerScriptService.Services:WaitForChild("TeamColorService")) :: any
local GridCellOccupancyService = require(ServerScriptService.Services:WaitForChild("GridCellOccupancyService"))

local RESERVED_BLOCK_KIND = "ReservedCastleCorner"

local CASTLE_BLOCK_INSET_CELLS = 0
local CASTLE_BLOCK_SIZE_CELLS = 2

local Shared = {}

local active = false

-- cornerId -> teamColorName
local reservedColorByCornerId: { [number]: string } = {}

-- cornerId -> {cellKey}
local reservedCellKeysByCornerId: { [number]: { string } } = {}

local function getEntryTypeForPlayer(player: Player): EntryType.EntryType
	local attr = player:GetAttribute("EntryType")
	if type(attr) == "string" then
		return attr :: any
	end

	local okJoin, joinDataOrErr = pcall(function()
		return player:GetJoinData()
	end)
	local teleportData = nil
	if okJoin and type(joinDataOrErr) == "table" then
		teleportData = (joinDataOrErr :: any).TeleportData
	end
	return EntryType.FromTeleportData(teleportData)
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

local function computeCellKeysForCorner(baseplate: BasePart, cornerId: number): { string }
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

local function clearReservationForCorner(cornerId: number)
	local keys = reservedCellKeysByCornerId[cornerId]
	if keys then
		reservedCellKeysByCornerId[cornerId] = nil
		for _, key in ipairs(keys) do
			GridCellOccupancyService.ClearReservedOverlayForKey(key)
			GridCellOccupancyService.UnblockCellKey(key)
		end
	end
end

local function ensureReservationForCorner(baseplate: BasePart, cornerId: number, teamColorName: string)
	if reservedCellKeysByCornerId[cornerId] == nil then
		local keys = computeCellKeysForCorner(baseplate, cornerId)
		reservedCellKeysByCornerId[cornerId] = keys
		for _, key in ipairs(keys) do
			GridCellOccupancyService.BlockCellKey(key, RESERVED_BLOCK_KIND, 0)
			GridCellOccupancyService.SetReservedOverlayForKey(baseplate, key, teamColorName)
		end
	end
end

function Shared.IsActive(): boolean
	return active
end

function Shared.GetReservedColorForCorner(cornerId: number): string?
	return reservedColorByCornerId[cornerId]
end

-- Called during CastleSpawnOnJoin for the first player.
-- Expects the player's TeamColor to already be assigned.
function Shared.MaybeActivateForFirstPlayer(player: Player, baseplate: BasePart, firstCornerId: number)
	if active then
		return
	end

	-- Only activate for the very first player in the server.
	if #Players:GetPlayers() ~= 1 then
		return
	end

	local entryType = getEntryTypeForPlayer(player)
	if entryType ~= "Open Arena" then
		return
	end

	active = true

	local firstColor = TeamColorService.GetColorForPlayer(player) or (player:GetAttribute(TeamColorService.Attributes.TeamColor) :: any)
	if type(firstColor) ~= "string" or firstColor == "" then
		firstColor = "red"
	end

	reservedColorByCornerId[firstCornerId] = firstColor
	TeamColorService.ReserveColorName(firstColor)

	for cornerId = 1, 4 do
		if cornerId ~= firstCornerId then
			local c = TeamColorService.TakeRandomAvailablePlayerColorName()
			reservedColorByCornerId[cornerId] = c
			TeamColorService.ReserveColorName(c)
		end
	end
end

-- Ensure reservations exist for all currently-unoccupied corners.
-- The caller provides the authoritative occupiedCornerIds table.
function Shared.ApplyReservations(baseplate: BasePart, occupiedCornerIds: { [number]: boolean })
	if not active then
		return
	end

	for cornerId = 1, 4 do
		local colorName = reservedColorByCornerId[cornerId]
		if type(colorName) ~= "string" or colorName == "" then
			-- Should not happen, but stay resilient.
			colorName = TeamColorService.TakeRandomAvailablePlayerColorName()
			reservedColorByCornerId[cornerId] = colorName
			TeamColorService.ReserveColorName(colorName)
		end

		if occupiedCornerIds[cornerId] then
			clearReservationForCorner(cornerId)
		else
			ensureReservationForCorner(baseplate, cornerId, colorName)
		end
	end
end

-- Called when a player is about to spawn their castle in a reserved corner.
-- Unblocks the reserved cells for that corner so CastleSpawnOnJoin can mark them as "Castle".
function Shared.ClearReservationForCorner(cornerId: number)
	if not active then
		return
	end
	clearReservationForCorner(cornerId)
end

return Shared
