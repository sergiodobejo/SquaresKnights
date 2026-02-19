-- ServerScriptService.Services.GridCellSpawnService
-- Spawns NPCs into the grid cell under the player, moves the player to a nearby free cell,
-- and marks the original cell as occupied until the NPC dies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShopConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ShopConfig"))
local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))

local TeamColorService = require(ServerScriptService.Services:WaitForChild("TeamColorService"))
local NpcSpawnService = require(ServerScriptService.Services:WaitForChild("NpcSpawnService"))
local GridCellOccupancyService = require(ServerScriptService.Services:WaitForChild("GridCellOccupancyService"))

local SPAWN_HEIGHT_ABOVE_GROUND = 4.2
local PLAYER_HEIGHT_ABOVE_GROUND = 3.2
local MAX_SEARCH_RADIUS = 10

local TEAM_COLOR_ATTRIBUTE = TeamColorService.Attributes.TeamColor

local function getCharacterRoot(character: Model): BasePart?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function teleportCharacterTo(character: Model, root: BasePart, player: Player, targetPos: Vector3)
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.05 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end
	local targetCFrame = CFrame.lookAt(targetPos, targetPos + flatLook)

	-- Player characters are usually client-owned; force a short server-authoritative teleport.
	pcall(function()
		(root :: BasePart):SetNetworkOwner(nil)
	end)

	local oldAnchored = root.Anchored
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		(root :: BasePart).CFrame = targetCFrame
	end)
	pcall(function()
		character:PivotTo(targetCFrame)
	end)

	-- Let replication settle for at least one heartbeat.
	task.wait()

	root.Anchored = oldAnchored
	pcall(function()
		(root :: BasePart):SetNetworkOwner(player)
	end)
end

local function getGroundPositionAt(worldXZ: Vector3, ignoreInstances: { Instance }): Vector3
	local rayOrigin = worldXZ + Vector3.new(0, 120, 0)
	local rayDirection = Vector3.new(0, -400, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreInstances
	local hit = workspace:Raycast(rayOrigin, rayDirection, params)
	if hit then
		return hit.Position
	end
	return worldXZ
end

local function findNearestFreeCell(
	baseplate: BasePart,
	startIx: number,
	startIz: number,
	excludedKey: string,
	disallowedKeys: { [string]: boolean }?
): (number?, number?)
	local cellsX, cellsZ = GridCells.GetCellCounts(baseplate)

	local function isFree(ix: number, iz: number): boolean
		if ix < 0 or iz < 0 or ix >= cellsX or iz >= cellsZ then
			return false
		end
		local key = GridCells.GetCellKey(ix, iz)
		if key == excludedKey then
			return false
		end
		if disallowedKeys and disallowedKeys[key] then
			return false
		end
		return not GridCellOccupancyService.IsBlocked(key)
	end

	-- First ring outward; prefers closest.
	for radius = 1, MAX_SEARCH_RADIUS do
		for dx = -radius, radius do
			for dz = -radius, radius do
				if math.abs(dx) ~= radius and math.abs(dz) ~= radius then
					continue
				end
				local ix = startIx + dx
				local iz = startIz + dz
				if isFree(ix, iz) then
					return ix, iz
				end
			end
		end
	end

	return nil, nil
end

local Shared = {}

-- Returns (success, reason, spawnCellKey, teleportToCellKey, spawnedNpc)
function Shared.TrySpawnShopItemOnCurrentCell(player: Player, itemName: any): (boolean, string?, string?, string?, Model?)
	if typeof(itemName) ~= "string" or itemName == "" then
		return false, "invalid_item", nil, nil, nil
	end

	local cfg = ShopConfig.GetConfig(itemName)
	if not cfg or (cfg :: any).Enabled == false then
		return false, "invalid_config", nil, nil, nil
	end
	if cfg.ItemKind ~= "npc" then
		return false, "unsupported_kind", nil, nil, nil
	end

	local baseplate = GridCells.FindBaseplate()
	if not baseplate then
		return false, "no_baseplate", nil, nil, nil
	end

	local character = player.Character
	if not character then
		return false, "no_character", nil, nil, nil
	end
	local root = getCharacterRoot(character)
	if not root then
		return false, "no_root", nil, nil, nil
	end

	local ix, iz = GridCells.GetCellIndexFromWorld(baseplate, root.Position)
	if ix == nil or iz == nil then
		return false, "not_on_grid", nil, nil, nil
	end

	local cellKey = GridCells.GetCellKey(ix, iz)
	local teamColorName = TeamColorService.GetColorForPlayer(player) or (player:GetAttribute(TEAM_COLOR_ATTRIBUTE) :: any) or "white"
	if type(teamColorName) ~= "string" then
		teamColorName = "white"
	end

	if not GridCellOccupancyService.TryReserveCellKey(cellKey, teamColorName) then
		return false, "cell_occupied", cellKey, nil, nil
	end

	-- Predict which regions will become captured once this reserved cell becomes an occupied wall.
	-- Use this to ensure we never teleport the player onto a cell that's about to be captured.
	local predictedRegions = GridCellOccupancyService.PredictCaptureRegionsAroundKey(baseplate, cellKey, player.UserId)
	local disallowedKeys: { [string]: boolean } = {}
	for _, regionKeys in ipairs(predictedRegions) do
		for _, k in ipairs(regionKeys) do
			disallowedKeys[k] = true
		end
	end

	local freeIx, freeIz = findNearestFreeCell(baseplate, ix, iz, cellKey, disallowedKeys)
	if freeIx == nil or freeIz == nil then
		GridCellOccupancyService.CancelReservation(cellKey)
		return false, "no_free_cell", cellKey, nil, nil
	end
	local freeCellKey = GridCells.GetCellKey(freeIx, freeIz)

	-- Move player first so the NPC spawns cleanly.
	do
		local freeCenter = GridCells.GetCellCenterWorld(baseplate, freeIx, freeIz)
		local groundPos = getGroundPositionAt(freeCenter, { character })
		local targetPos = groundPos + Vector3.new(0, PLAYER_HEIGHT_ABOVE_GROUND, 0)
		teleportCharacterTo(character, root, player, targetPos)
	end

	-- Spawn NPC at the original cell center.
	local spawnCenter = GridCells.GetCellCenterWorld(baseplate, ix, iz)
	local spawnGround = getGroundPositionAt(spawnCenter, { character })
	local spawnPos = spawnGround + Vector3.new(0, SPAWN_HEIGHT_ABOVE_GROUND, 0)

	local npcModelName = (cfg :: any).NpcModelName
	local unitKind = cfg.UnitKind
	local unitClass = cfg.UnitClass

	local npc: Model? = nil
	if type(npcModelName) == "string" and npcModelName ~= "" then
		npc = NpcSpawnService.SpawnUnitAtPosition(player, npcModelName, spawnPos)
	elseif type(unitKind) == "string" and unitKind ~= "" and type(unitClass) == "string" and unitClass ~= "" then
		npc = NpcSpawnService.SpawnUnitAtPosition(player, unitKind, unitClass, spawnPos)
	end

	if not npc then
		GridCellOccupancyService.CancelReservation(cellKey)
		return false, "spawn_failed", cellKey, freeCellKey, nil
	end

	-- We'll apply the predicted captures ourselves (no extra flood-fill pass), so skip the default check.
	pcall(function()
		npc:SetAttribute("SkipCaptureCheck", true)
	end)

	GridCellOccupancyService.FinalizeReservation(cellKey, npc, baseplate)
	local actualColorName = TeamColorService.GetColorForPlayer(player)
	if type(actualColorName) == "string" and actualColorName ~= "" then
		teamColorName = actualColorName
	end
	GridCellOccupancyService.ApplyCaptureRegionsForTeam(baseplate, player.UserId, teamColorName, predictedRegions)
	return true, nil, cellKey, freeCellKey, npc
end

return Shared
