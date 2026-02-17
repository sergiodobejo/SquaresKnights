-- ServerScriptService.TeleportToCastle
-- Teleports a player near their own castle on request.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BASEPLATE_NAME = "Baseplate"
local PLAYER_BUILDINGS_FOLDER = "PlayerBuildings"
local CASTLE_MODEL_NAME = "SM_Castle"

local SPAWN_MARGIN = 6
local SPAWN_HEIGHT = 4

local function getBaseplate(): BasePart?
	local bp = workspace:FindFirstChild(BASEPLATE_NAME)
	if bp and bp:IsA("BasePart") then
		return bp
	end
	return nil
end

local function findPlayerCastle(player: Player): Model?
	local buildings = workspace:FindFirstChild(PLAYER_BUILDINGS_FOLDER)
	if not buildings then
		return nil
	end

	local name = string.format("%s_%d", CASTLE_MODEL_NAME, player.UserId)
	local castle = buildings:FindFirstChild(name)
	if castle and castle:IsA("Model") then
		return castle
	end

	-- Fallback: if renamed, scan by OwnerUserId attribute.
	for _, child in ipairs(buildings:GetChildren()) do
		if child:IsA("Model") then
			local owner = child:GetAttribute("OwnerUserId")
			if type(owner) == "number" and math.floor(owner) == player.UserId then
				return child
			end
		end
	end

	return nil
end

local function computeSpawnCFrameNearCastle(baseplate: BasePart, castle: Model): CFrame
	local baseplateCf = baseplate.CFrame
	local halfX = baseplate.Size.X / 2
	local halfZ = baseplate.Size.Z / 2

	local bbCf, bbSize = castle:GetBoundingBox()
	local desiredPos = bbCf.Position
	local baseCenter = baseplateCf.Position

	local dirToCenterFlat = Vector3.new(baseCenter.X - desiredPos.X, 0, baseCenter.Z - desiredPos.Z)
	local dir = if dirToCenterFlat.Magnitude > 1e-6 then dirToCenterFlat.Unit else Vector3.new(0, 0, -1)

	local castleRadiusXZ = math.sqrt((bbSize.X * 0.5) ^ 2 + (bbSize.Z * 0.5) ^ 2)
	local spawnOffsetY = -bbSize.Y / 2 + SPAWN_HEIGHT
	local spawnDistance = castleRadiusXZ + SPAWN_MARGIN

	local spawnPos = desiredPos + Vector3.new(0, spawnOffsetY, 0) + dir * spawnDistance

	local localPos = baseplateCf:PointToObjectSpace(spawnPos)
	local clampX = halfX - SPAWN_MARGIN
	local clampZ = halfZ - SPAWN_MARGIN
	localPos = Vector3.new(
		math.clamp(localPos.X, -clampX, clampX),
		localPos.Y,
		math.clamp(localPos.Z, -clampZ, clampZ)
	)
	spawnPos = baseplateCf:PointToWorldSpace(localPos)

	local lookAtPos = Vector3.new(desiredPos.X, spawnPos.Y, desiredPos.Z)
	return CFrame.lookAt(spawnPos, lookAtPos)
end

local function teleportCharacter(player: Player, targetCf: CFrame)
	local character = player.Character
	if not character then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		local hrpWaited = character:WaitForChild("HumanoidRootPart", 3)
		if not (hrpWaited and hrpWaited:IsA("BasePart")) then
			return
		end
		hrp = hrpWaited
	end

	pcall(function()
		(character :: Model):PivotTo(targetCf)
	end)
end

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remote = remotesFolder:WaitForChild("TeleportToCastle")
if not remote:IsA("RemoteEvent") then
	error("[TeleportToCastle] ReplicatedStorage.Remotes.TeleportToCastle must be a RemoteEvent")
end

(remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local baseplate = getBaseplate()
	if not baseplate then
		warn("[TeleportToCastle] Workspace/Baseplate not found")
		return
	end

	local castle = findPlayerCastle(player)
	if not castle then
		warn("[TeleportToCastle] Player castle not found for", player.Name)
		return
	end

	local targetCf = computeSpawnCFrameNearCastle(baseplate, castle)
	teleportCharacter(player, targetCf)
end)

return {}
