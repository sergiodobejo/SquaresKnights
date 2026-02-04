-- ReplicatedStorage.GridCells
-- Utilities for mapping world positions to baseplate "grid cells".

local Workspace = game:GetService("Workspace")

local Shared = {}

Shared.TEXTURE_CELL_SIZE_STUDS = 4
Shared.SQUARE_CELLS = 2
Shared.SQUARE_SIZE_STUDS = Shared.TEXTURE_CELL_SIZE_STUDS * Shared.SQUARE_CELLS

function Shared.FindBaseplate(): BasePart?
	local inst = Workspace:FindFirstChild("Baseplate")
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

function Shared.GetCellCounts(baseplate: BasePart): (number, number)
	local cellsX = math.floor(baseplate.Size.X / Shared.SQUARE_SIZE_STUDS)
	local cellsZ = math.floor(baseplate.Size.Z / Shared.SQUARE_SIZE_STUDS)
	return cellsX, cellsZ
end

function Shared.IsIndexWithinBaseplate(baseplate: BasePart, ix: number, iz: number): boolean
	local cellsX, cellsZ = Shared.GetCellCounts(baseplate)
	return ix >= 0 and iz >= 0 and ix < cellsX and iz < cellsZ
end

function Shared.GetCellIndexFromWorld(baseplate: BasePart, worldPos: Vector3): (number?, number?)
	local localPos = baseplate.CFrame:PointToObjectSpace(worldPos)
	local halfX = baseplate.Size.X / 2
	local halfZ = baseplate.Size.Z / 2

	local x = localPos.X + halfX
	local z = localPos.Z + halfZ

	if x < 0 or x >= baseplate.Size.X or z < 0 or z >= baseplate.Size.Z then
		return nil, nil
	end

	local ix = math.floor(x / Shared.SQUARE_SIZE_STUDS)
	local iz = math.floor(z / Shared.SQUARE_SIZE_STUDS)

	if not Shared.IsIndexWithinBaseplate(baseplate, ix, iz) then
		return nil, nil
	end

	return ix, iz
end

function Shared.GetCellCenterLocalXZ(baseplate: BasePart, ix: number, iz: number): (number, number)
	local halfX = baseplate.Size.X / 2
	local halfZ = baseplate.Size.Z / 2
	local xCenter = -halfX + (ix * Shared.SQUARE_SIZE_STUDS) + (Shared.SQUARE_SIZE_STUDS / 2)
	local zCenter = -halfZ + (iz * Shared.SQUARE_SIZE_STUDS) + (Shared.SQUARE_SIZE_STUDS / 2)
	return xCenter, zCenter
end

function Shared.GetCellCenterWorld(baseplate: BasePart, ix: number, iz: number): Vector3
	local xCenter, zCenter = Shared.GetCellCenterLocalXZ(baseplate, ix, iz)
	return (baseplate.CFrame * CFrame.new(xCenter, 0, zCenter)).Position
end

-- Returns a CFrame aligned to the baseplate, positioned above the baseplate surface.
-- yOffsetAboveSurface is in studs and is added above the top surface.
function Shared.GetCellCFrameOnTop(baseplate: BasePart, ix: number, iz: number, yOffsetAboveSurface: number): CFrame
	local xCenter, zCenter = Shared.GetCellCenterLocalXZ(baseplate, ix, iz)
	local yLocal = (baseplate.Size.Y / 2) + yOffsetAboveSurface
	return baseplate.CFrame * CFrame.new(xCenter, yLocal, zCenter)
end

function Shared.GetCellKey(ix: number, iz: number): string
	return string.format("%d,%d", ix, iz)
end

function Shared.ParseCellKey(key: any): (number?, number?)
	if type(key) ~= "string" then
		return nil, nil
	end
	local a, b = string.match(key, "^(%-?%d+),(%-?%d+)$")
	if not a or not b then
		return nil, nil
	end
	local ix = tonumber(a)
	local iz = tonumber(b)
	if ix == nil or iz == nil then
		return nil, nil
	end
	return ix, iz
end

return Shared
