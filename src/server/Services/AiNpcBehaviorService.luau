-- ServerScriptService.Services.AiNpcBehaviorService
-- Controls AI NPC behavior: walking to target castle, attacking it (once castle health is added).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local CombatParams = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CombatParams"))
local Animations = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("Animations"))
local AttackSounds = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("AttackSounds"))
local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))

local CastleHealthService = require(ServerScriptService.Services:WaitForChild("CastleHealthService"))

local WALK_ANIM_SPEED_FACTOR = 1.5 -- animation speed multiplier
local ATTACK_MARKER_NAME = "Attack"
local ATTACK_RELEASE_PARAM = "1"
local CAST_MARKER_NAME = "Cast"
local CAST_RELEASE_PARAM = "1"
local DEBUG = false

local ATTACK_SFX_LIFETIME_SECONDS = 5

local ARROW_ORIGIN_NAME = "ArrowOrigin"
local CAST_ORIGIN_NAME = "CastStart"
local ARROW_THICKNESS = 0.12
local ARROW_SEGMENT_LENGTH = 6
local ARROW_SPEED = 220 -- studs/sec

local MAGIC_THICKNESS = 0.14
local MAGIC_SEGMENT_LENGTH = 7
local MAGIC_SPEED = 260 -- studs/sec

local function dprint(...)
	if DEBUG then
		print(...)
	end
end

local function playAttackSfx(parentPart: BasePart?, unitClass: string?)
	if not parentPart or not parentPart.Parent then
		return
	end

	local soundId = (AttackSounds :: any).ResolveByUnitClass(unitClass)
	if type(soundId) ~= "string" or soundId == "" then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "AttackSfx"
	sound.SoundId = soundId
	sound.Volume = 0.2666667
	sound.RollOffMaxDistance = 80
	sound.Parent = parentPart
	pcall(function()
		sound:Play()
	end)
	Debris:AddItem(sound, ATTACK_SFX_LIFETIME_SECONDS)
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

local function getCharacterRoot(character: Model): BasePart?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function _getAnyBasePart(model: Model): BasePart?
	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end
	local inst = model:FindFirstChildWhichIsA("BasePart", true)
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function getArrowOrigin(model: Model): Attachment?
	local inst = model:FindFirstChild(ARROW_ORIGIN_NAME, true)
	if inst and inst:IsA("Attachment") then
		return inst
	end
	return nil
end

local function getCastOrigin(model: Model): Attachment?
	local inst = model:FindFirstChild(CAST_ORIGIN_NAME, true)
	if inst and inst:IsA("Attachment") then
		return inst
	end
	return nil
end

local function spawnArrowSegmentProjectile(fromPos: Vector3, toPos: Vector3)
	local delta = (toPos - fromPos)
	local dist = delta.Magnitude
	if dist < 0.5 then
		return
	end

	local dir = delta.Unit
	local segmentLen = math.min(ARROW_SEGMENT_LENGTH, dist)

	local folder = Workspace:FindFirstChild("DebugProjectiles")
	if not (folder and folder:IsA("Folder")) then
		folder = Instance.new("Folder")
		folder.Name = "DebugProjectiles"
		folder.Parent = Workspace
	end

	local part = Instance.new("Part")
	part.Name = "ArrowSegment"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 235, 160)
	part.Size = Vector3.new(ARROW_THICKNESS, ARROW_THICKNESS, segmentLen)
	part.Parent = folder

	local flightTime = dist / ARROW_SPEED
	flightTime = math.clamp(flightTime, 0.05, 2)
	local startTime = os.clock()

	local connection: RBXScriptConnection?
	connection = RunService.Heartbeat:Connect(function()
		if not part.Parent then
			if connection then
				connection:Disconnect()
			end
			return
		end

		local t = (os.clock() - startTime) / flightTime
		if t >= 1 then
			part:Destroy()
			if connection then
				connection:Disconnect()
			end
			return
		end

		local headPos = fromPos:Lerp(toPos, t)
		local tailPos = headPos - dir * segmentLen
		local center = (headPos + tailPos) * 0.5
		part.CFrame = CFrame.lookAt(center, center + dir, Vector3.yAxis)
	end)

	Debris:AddItem(part, flightTime + 0.25)
end

local function spawnMagicBeamSegment(fromPos: Vector3, toPos: Vector3)
	local delta = (toPos - fromPos)
	local dist = delta.Magnitude
	if dist < 0.5 then
		return
	end

	local dir = delta.Unit
	local segmentLen = math.min(MAGIC_SEGMENT_LENGTH, dist)

	local folder = Workspace:FindFirstChild("DebugMagicProjectiles")
	if not (folder and folder:IsA("Folder")) then
		folder = Instance.new("Folder")
		folder.Name = "DebugMagicProjectiles"
		folder.Parent = Workspace
	end

	local part = Instance.new("Part")
	part.Name = "MagicBeamSegment"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(170, 110, 255)
	part.Size = Vector3.new(MAGIC_THICKNESS, MAGIC_THICKNESS, segmentLen)
	part.Parent = folder

	local flightTime = dist / MAGIC_SPEED
	flightTime = math.clamp(flightTime, 0.05, 2)
	local startTime = os.clock()

	local connection: RBXScriptConnection?
	connection = RunService.Heartbeat:Connect(function()
		if not part.Parent then
			if connection then
				connection:Disconnect()
			end
			return
		end

		local t = (os.clock() - startTime) / flightTime
		if t >= 1 then
			if connection then
				connection:Disconnect()
			end
			part:Destroy()
			return
		end

		local curPos = fromPos + dir * (dist * t)
		local nextPos = fromPos + dir * (dist * math.min(1, t + (segmentLen / math.max(dist, 1e-3))))
		local mid = (curPos + nextPos) * 0.5
		part.CFrame = CFrame.lookAt(mid, nextPos)
		part.Size = Vector3.new(MAGIC_THICKNESS, MAGIC_THICKNESS, (nextPos - curPos).Magnitude)
	end)

	Debris:AddItem(part, 2)
end

local function faceTarget(attackerRoot: BasePart, targetPos: Vector3, attackerModel: Model)
	local aPos = attackerRoot.Position
	local flatDir = Vector3.new(targetPos.X - aPos.X, 0, targetPos.Z - aPos.Z)
	if flatDir.Magnitude < 1e-4 then
		return
	end
	local currentRootCf = attackerRoot.CFrame
	local desiredRootCf = CFrame.lookAt(aPos, aPos + flatDir.Unit, currentRootCf.UpVector)
	local delta = desiredRootCf * currentRootCf:Inverse()
	pcall(function()
		attackerModel:PivotTo(delta * attackerModel:GetPivot())
	end)
end

type CastleRectLocal = {
	xMin: number,
	xMax: number,
	zMin: number,
	zMax: number,
}

local function getCastleRectLocal(baseplate: BasePart, castle: Model): CastleRectLocal?
	local ixMin = castle:GetAttribute("CastleBlockIxMin")
	local ixMax = castle:GetAttribute("CastleBlockIxMax")
	local izMin = castle:GetAttribute("CastleBlockIzMin")
	local izMax = castle:GetAttribute("CastleBlockIzMax")
	if type(ixMin) ~= "number" or type(ixMax) ~= "number" or type(izMin) ~= "number" or type(izMax) ~= "number" then
		return nil
	end
	ixMin = math.floor(ixMin)
	ixMax = math.floor(ixMax)
	izMin = math.floor(izMin)
	izMax = math.floor(izMax)
	if ixMax < ixMin or izMax < izMin then
		return nil
	end

	local halfX = baseplate.Size.X / 2
	local halfZ = baseplate.Size.Z / 2
	local s = GridCells.SQUARE_SIZE_STUDS

	local xMin = -halfX + (ixMin * s)
	local xMax = -halfX + ((ixMax + 1) * s)
	local zMin = -halfZ + (izMin * s)
	local zMax = -halfZ + ((izMax + 1) * s)

	return { xMin = xMin, xMax = xMax, zMin = zMin, zMax = zMax }
end

local function getCastleCenterWorld(baseplate: BasePart, rect: CastleRectLocal): Vector3
	local x = (rect.xMin + rect.xMax) * 0.5
	local z = (rect.zMin + rect.zMax) * 0.5
	return (baseplate.CFrame * CFrame.new(x, 0, z)).Position
end

local function clamp(n: number, a: number, b: number): number
	return math.clamp(n, math.min(a, b), math.max(a, b))
end

local function pickApproachSide(rootLocal: Vector3, rect: CastleRectLocal): string
	local dx = 0
	if rootLocal.X < rect.xMin then
		dx = rect.xMin - rootLocal.X
	elseif rootLocal.X > rect.xMax then
		dx = rootLocal.X - rect.xMax
	end
	local dz = 0
	if rootLocal.Z < rect.zMin then
		dz = rect.zMin - rootLocal.Z
	elseif rootLocal.Z > rect.zMax then
		dz = rootLocal.Z - rect.zMax
	end

	if dx >= dz then
		return if rootLocal.X >= (rect.xMin + rect.xMax) * 0.5 then "xMax" else "xMin"
	else
		return if rootLocal.Z >= (rect.zMin + rect.zMax) * 0.5 then "zMax" else "zMin"
	end
end

local function getBoundaryPointLocal(rootLocal: Vector3, rect: CastleRectLocal, side: string, sideOffset: number): Vector3
	if side == "xMin" then
		return Vector3.new(rect.xMin, 0, clamp(rootLocal.Z + sideOffset, rect.zMin, rect.zMax))
	elseif side == "xMax" then
		return Vector3.new(rect.xMax, 0, clamp(rootLocal.Z + sideOffset, rect.zMin, rect.zMax))
	elseif side == "zMin" then
		return Vector3.new(clamp(rootLocal.X + sideOffset, rect.xMin, rect.xMax), 0, rect.zMin)
	else
		return Vector3.new(clamp(rootLocal.X + sideOffset, rect.xMin, rect.xMax), 0, rect.zMax)
	end
end

local function getOutwardDirLocal(side: string): Vector3
	if side == "xMin" then
		return Vector3.new(-1, 0, 0)
	elseif side == "xMax" then
		return Vector3.new(1, 0, 0)
	elseif side == "zMin" then
		return Vector3.new(0, 0, -1)
	else
		return Vector3.new(0, 0, 1)
	end
end

local function getUnitKindAndClass(npc: Model): (string?, string?)
	local kind = npc:GetAttribute("UnitKind")
	local class = npc:GetAttribute("UnitClass")
	if type(kind) == "string" and type(class) == "string" then
		return kind, class
	end
	return nil, nil
end

local function findKeyCaseInsensitive(tbl: any, desiredKey: string): string?
	if type(tbl) ~= "table" then
		return nil
	end
	if type(desiredKey) ~= "string" or desiredKey == "" then
		return nil
	end
	if tbl[desiredKey] ~= nil then
		return desiredKey
	end
	local desiredLower = desiredKey:lower()
	for k, _ in pairs(tbl) do
		if type(k) == "string" and k:lower() == desiredLower then
			return k
		end
	end
	return nil
end

local function getAnimationId(unitKind: string, unitClass: string, animationType: string): string?
	local kindKey = findKeyCaseInsensitive(Animations, unitKind)
	local anims = if kindKey then Animations[kindKey] else nil
	if not anims then
		return nil
	end
	local classKey = findKeyCaseInsensitive(anims, unitClass)
	local classAnims = if classKey then anims[classKey] else nil
	if not classAnims then
		return nil
	end
	local anim = classAnims[animationType]
	if not anim then
		return nil
	end
	if type(anim) == "string" then
		return anim
	elseif type(anim) == "table" and #anim > 0 then
		return anim[math.random(1, #anim)]
	end
	return nil
end

local function ensureAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end
	animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function getUnitClassLower(npc: Model): string
	local unitClass = npc:GetAttribute("UnitClass")
	if type(unitClass) == "string" then
		return unitClass:lower()
	end
	return ""
end

local function isMageUnit(npc: Model): boolean
	return getUnitClassLower(npc) == "mage"
end

local function getCombatParamsForNpc(npc: Model): any?
	if type(CombatParams) == "table" and type((CombatParams :: any).ResolveForModel) == "function" then
		return (CombatParams :: any).ResolveForModel(npc)
	end

	-- Backward compatibility if CombatParams is still a plain table
	local unitKind, unitClass = getUnitKindAndClass(npc)
	if not unitKind or not unitClass then
		return nil
	end
	local kindKey = findKeyCaseInsensitive(CombatParams, unitKind)
	local params = if kindKey then (CombatParams :: any)[kindKey] else nil
	if not params then
		return nil
	end
	local classKey = findKeyCaseInsensitive(params, unitClass)
	local classParams = if classKey then (params :: any)[classKey] else nil
	return classParams
end

local Shared = {}

-- Start AI behavior for a single spawned NPC
-- The NPC will walk towards the nearest castle and attack when in range
function Shared.StartAiBehavior(aiNpc: Model, targetCastle: Model?)
	if not targetCastle then
		dprint("[AiNpcBehavior] ERROR: No target castle provided")
		return -- No valid target
	end
	
	local humanoid = getHumanoid(aiNpc)
	local root = getCharacterRoot(aiNpc)
	if not humanoid or not root then
		dprint(string.format("[AiNpcBehavior] ERROR: Missing humanoid or root. Humanoid=%s, Root=%s", 
			humanoid and "OK" or "MISSING", root and "OK" or "MISSING"))
		return
	end
	
	local baseplate = GridCells.FindBaseplate()
	if not baseplate then
		dprint("[AiNpcBehavior] ERROR: Baseplate not found")
		return
	end
	local castleRect = getCastleRectLocal(baseplate, targetCastle)
	local castleCenterWorld = if castleRect then getCastleCenterWorld(baseplate, castleRect) else targetCastle:GetPivot().Position

	-- Choose an approach side + stable offset so units don't all converge to the same exact point.
	local rng = Random.new()
	local rootLocalAtStart = baseplate.CFrame:PointToObjectSpace(root.Position)
	local approachSide = if castleRect then pickApproachSide(rootLocalAtStart, castleRect) else "xMax"
	local sideOffset = rng:NextNumber(-6, 6)
	
	local unitKind, unitClass = getUnitKindAndClass(aiNpc)
	local params = getCombatParamsForNpc(aiNpc)
	if not params then
		dprint(string.format("[AiNpcBehavior] ERROR: No params found for NPC %s (Kind=%s Class=%s ShopKey=%s)", aiNpc.Name, tostring(unitKind), tostring(unitClass), tostring(aiNpc:GetAttribute((CombatParams :: any).ShopKeyAttribute or "ShopKey"))))
		return
	end
	
	local moveSpeed = params.MoveSpeed or 16
	local attackRange = params.AttackRange or 20
	
	-- Set walk speed BEFORE animation to ensure movement happens
	humanoid.WalkSpeed = moveSpeed
	
	-- Play walk animation
	-- Animations still resolve by UnitKind/UnitClass for now
	local walkAnimId = if unitKind and unitClass then getAnimationId(unitKind, unitClass, "Walk") else nil
	if walkAnimId then
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. walkAnimId
		pcall(function()
			local track = humanoid:LoadAnimation(anim)
			track:Play()
			track.Speed = (moveSpeed / 16) * WALK_ANIM_SPEED_FACTOR -- Normalize to Infantry base speed
		end)
		anim:Destroy()
	end
	
	-- Wait for spawn anchoring to release (0.5s in spawnAiNpc)
	task.wait(0.6)
	
	dprint(string.format("[AiNpcBehavior] Starting behavior for %s -> castle at %s. WalkSpeed=%d", 
		aiNpc.Name, targetCastle.Name, moveSpeed))
	
	-- Behavior loop: walk to castle, then attack
	task.spawn(function()
		local iterations = 0
		local attackTrack: AnimationTrack? = nil
		local markerConn: RBXScriptConnection? = nil

		local function stopAttack()
			if markerConn then
				pcall(function()
					markerConn:Disconnect()
				end)
				markerConn = nil
			end
			if attackTrack then
				pcall(function()
					attackTrack:Stop(0.1)
				end)
				pcall(function()
					attackTrack:Destroy()
				end)
				attackTrack = nil
			end
		end

		local function ensureAttackAnimation()
			if not humanoid or not humanoid.Parent then
				return
			end
			if attackTrack and attackTrack.IsPlaying then
				return
			end

			stopAttack()

			local attackType = if isMageUnit(aiNpc) then "Cast" else "Attack"
			local animId = if unitKind and unitClass then getAnimationId(unitKind, unitClass, attackType) else nil
			local resolvedType = attackType
			if not animId and attackType == "Cast" then
				animId = if unitKind and unitClass then getAnimationId(unitKind, unitClass, "Attack") else nil
				if animId then
					resolvedType = "Attack"
				end
			end
			if not animId then
				return
			end

			local animator = ensureAnimator(humanoid)
			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://" .. animId
			local track: AnimationTrack? = nil
			pcall(function()
				track = animator:LoadAnimation(anim)
			end)
			anim:Destroy()
			if not track then
				return
			end

			attackTrack = track
			pcall(function()
				track.Looped = true
				track.Priority = Enum.AnimationPriority.Action
				track:Play(0.1, 1, 1)
			end)

			local markerName = if resolvedType == "Cast" then CAST_MARKER_NAME else ATTACK_MARKER_NAME
			local releaseParam = if resolvedType == "Cast" then CAST_RELEASE_PARAM else ATTACK_RELEASE_PARAM
			markerConn = track:GetMarkerReachedSignal(markerName):Connect(function(param)
				if tostring(param) ~= releaseParam then
					return
				end
				if not targetCastle or not targetCastle.Parent then
					return
				end
				if CastleHealthService.IsDestroyed(targetCastle) then
					return
				end
				-- Always face the castle center during attack.
				faceTarget(root :: BasePart, castleCenterWorld, aiNpc)

				-- Apply damage strictly at the animation marker moment.
				playAttackSfx(root, unitClass)
				CastleHealthService.ApplyDamage(targetCastle, (params.Damage or 1), aiNpc)

				-- Spawn ranged/magic visuals toward the castle, like NPC-vs-NPC.
				if resolvedType == "Cast" then
					local origin = getCastOrigin(aiNpc)
					if origin then
						local toPos = Vector3.new(castleCenterWorld.X, origin.WorldPosition.Y, castleCenterWorld.Z)
						spawnMagicBeamSegment(origin.WorldPosition, toPos)
					end
				else
					local origin = getArrowOrigin(aiNpc)
					if origin then
						local toPos = Vector3.new(castleCenterWorld.X, origin.WorldPosition.Y, castleCenterWorld.Z)
						spawnArrowSegmentProjectile(origin.WorldPosition, toPos)
					end
				end
			end)
		end
		while root and root.Parent and humanoid and humanoid.Parent do
			if not targetCastle or not targetCastle.Parent then
				stopAttack()
				return
			end
			if CastleHealthService.IsDestroyed(targetCastle) then
				stopAttack()
				return
			end

			iterations = iterations + 1
			
			local rootLocal = baseplate.CFrame:PointToObjectSpace(root.Position)
			local castleTargetPos = castleCenterWorld
			local distToBoundary = math.huge
			local moveTargetWorld = castleTargetPos

			if castleRect then
				-- Compute boundary point and desired stand-off position using the grid-based castle footprint.
				local boundaryLocal = getBoundaryPointLocal(rootLocal, castleRect, approachSide, sideOffset)
				local dxz = Vector3.new(rootLocal.X - boundaryLocal.X, 0, rootLocal.Z - boundaryLocal.Z)
				distToBoundary = dxz.Magnitude

				local outward = getOutwardDirLocal(approachSide)
				local standOff = math.max(0, attackRange - 0.5)
				local standLocal = boundaryLocal + outward * standOff
				local standWorld = (baseplate.CFrame * CFrame.new(standLocal.X, 0, standLocal.Z)).Position
				moveTargetWorld = Vector3.new(standWorld.X, root.Position.Y, standWorld.Z)
			else
				-- Fallback: use center distance.
				distToBoundary = (castleTargetPos - root.Position).Magnitude
				moveTargetWorld = castleTargetPos
			end
			
			if iterations % 50 == 0 then -- Print every 50 iterations (~10 seconds)
				dprint(string.format("[AiNpcBehavior] %s distance to castle: %.1f studs", aiNpc.Name, distToBoundary))
			end
			
			if distToBoundary > attackRange then
				-- Walk towards castle
				stopAttack()
				pcall(function()
					humanoid.AutoRotate = true
				end)
				humanoid:MoveTo(moveTargetWorld)
				task.wait(0.2)
			else
				-- In attack range: prepare to attack (once castle has health system)
				humanoid:MoveTo(root.Position) -- Stop moving
				pcall(function()
					humanoid.AutoRotate = false
				end)

				-- Always face the castle center while in-range.
				faceTarget(root :: BasePart, castleCenterWorld, aiNpc)
				ensureAttackAnimation()
				task.wait(0.1)
			end
		end
		stopAttack()
	end)
end

return Shared
