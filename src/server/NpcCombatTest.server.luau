-- ServerScriptService.NpcCombatTest
-- Simple NPC-vs-NPC aggro test:
-- - Only owned NPCs (TeamId > 0) attack
-- - Targets are enemy NPCs (different TeamId OR TeamId=0)
-- - Plays Attack animation (looped) and turns to face target
-- - For archers/crossbowmen: draws a debug "arrow" line from ArrowOrigin to target
-- - For mages: draws a debug "magic" line from CastStart to target on Cast marker
-- - Arrow fire moment is driven by an animation marker:
--   - Marker name: "Attack"
--   - Marker parameter: "1" at the release frame
--   - Fallback: 1.5s cadence if marker isn't present

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local AnimationsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("Animations"))
local CombatParamsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CombatParams"))

local CastleHealthService = require(ServerScriptService.Services:WaitForChild("CastleHealthService"))

local NPC_FOLDER_NAMES = { "NPC", "LiveNPC" }

local MELEE_ATTACK_RADIUS = 20
local RANGED_ATTACK_RADIUS = 100
local SCAN_INTERVAL = 0.25

local ARROW_ORIGIN_NAME = "ArrowOrigin"
local ATTACK_MARKER_NAME = "Attack"
local ATTACK_RELEASE_PARAM = "1"
local CAST_ORIGIN_NAME = "CastStart"
local CAST_MARKER_NAME = "Cast"
local CAST_RELEASE_PARAM = "1"
local FALLBACK_RANGED_SHOT_INTERVAL_SECONDS = 1.5
local MIN_SHOT_INTERVAL_SECONDS = 0.08
local NPC_DESPAWN_SECONDS = 2
local ARROW_THICKNESS = 0.12
local ARROW_SEGMENT_LENGTH = 6
local ARROW_SPEED = 220 -- studs/sec

local MAGIC_MIN_INTERVAL_SECONDS = 0.08
local MAGIC_THICKNESS = 0.14
local MAGIC_SEGMENT_LENGTH = 7
local MAGIC_SPEED = 260 -- studs/sec

local rng = Random.new()

local function normalizeAssetId(id: string): string
	if id:match("^rbxassetid://") then
		return id
	end
	return "rbxassetid://" .. id
end

local function resolveAnimationIdValue(value: any): string?
	if type(value) == "string" then
		if value == "" then
			return nil
		end
		return value
	end

	if type(value) == "table" then
		local count = #value
		if count <= 0 then
			return nil
		end

		local picked = value[rng:NextInteger(1, count)]
		if type(picked) ~= "string" or picked == "" then
			return nil
		end
		return picked
	end

	return nil
end

local function toPascalCase(value: string): string
	local parts = {}
	for part in value:gmatch("[^%s%-_]+") do
		local lower = part:lower()
		local first = lower:sub(1, 1):upper()
		table.insert(parts, first .. lower:sub(2))
	end
	return table.concat(parts, "")
end

local function getHumanoid(model: Instance): Humanoid?
	if not model:IsA("Model") then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end

	local maybe = model:FindFirstChild("Humanoid")
	if maybe and maybe:IsA("Humanoid") then
		return maybe
	end

	return nil
end

local function getRootPart(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end

	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end

	local anyPart = model:FindFirstChildWhichIsA("BasePart", true)
	if anyPart and anyPart:IsA("BasePart") then
		return anyPart
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

local function resolveAnimationId(model: Model, key: string): string?
	local unitKind = model:GetAttribute("UnitKind")
	local unitClass = model:GetAttribute("UnitClass")

	if type(unitKind) ~= "string" or unitKind == "" then
		return nil
	end
	if type(unitClass) ~= "string" or unitClass == "" then
		return nil
	end

	local kindKey = toPascalCase(unitKind)
	local classKey = toPascalCase(unitClass)

	local kindTable = AnimationsConfig[kindKey]
	if type(kindTable) ~= "table" then
		return nil
	end

	local classTable = kindTable[classKey]
	if type(classTable) ~= "table" then
		return nil
	end

	local rawValue = classTable[key]
	local animationId = resolveAnimationIdValue(rawValue)
	if not animationId then
		return nil
	end

	return normalizeAssetId(animationId)
end

local function resolveAttackRange(model: Model): number?
	local stats: any? = nil
	if type(CombatParamsConfig) == "table" and type((CombatParamsConfig :: any).ResolveForModel) == "function" then
		stats = (CombatParamsConfig :: any).ResolveForModel(model)
	else
		local unitKind = model:GetAttribute("UnitKind")
		local unitClass = model:GetAttribute("UnitClass")
		if type(unitKind) ~= "string" or unitKind == "" then
			return nil
		end
		if type(unitClass) ~= "string" or unitClass == "" then
			return nil
		end
		local kindKey = toPascalCase(unitKind)
		local classKey = toPascalCase(unitClass)
		local kindTable = (CombatParamsConfig :: any)[kindKey]
		if type(kindTable) ~= "table" then
			return nil
		end
		stats = (kindTable :: any)[classKey]
	end
	if type(stats) ~= "table" then
		return nil
	end
	local attackRange = (stats :: any).AttackRange
	if type(attackRange) ~= "number" or attackRange <= 0 then
		return nil
	end

	return attackRange
end

local function resolveDamage(model: Model): number?
	local stats: any? = nil
	if type(CombatParamsConfig) == "table" and type((CombatParamsConfig :: any).ResolveForModel) == "function" then
		stats = (CombatParamsConfig :: any).ResolveForModel(model)
	else
		local unitKind = model:GetAttribute("UnitKind")
		local unitClass = model:GetAttribute("UnitClass")
		if type(unitKind) ~= "string" or unitKind == "" then
			return nil
		end
		if type(unitClass) ~= "string" or unitClass == "" then
			return nil
		end
		local kindKey = toPascalCase(unitKind)
		local classKey = toPascalCase(unitClass)
		local kindTable = (CombatParamsConfig :: any)[kindKey]
		if type(kindTable) ~= "table" then
			return nil
		end
		stats = (kindTable :: any)[classKey]
	end
	if type(stats) ~= "table" then
		return nil
	end
	local dmg = (stats :: any).Damage
	if type(dmg) ~= "number" or dmg <= 0 then
		return nil
	end

	return dmg
end

local function resolveHealth(model: Model): number?
	local stats: any? = nil
	if type(CombatParamsConfig) == "table" and type((CombatParamsConfig :: any).ResolveForModel) == "function" then
		stats = (CombatParamsConfig :: any).ResolveForModel(model)
	else
		local unitKind = model:GetAttribute("UnitKind")
		local unitClass = model:GetAttribute("UnitClass")
		if type(unitKind) ~= "string" or unitKind == "" then
			return nil
		end
		if type(unitClass) ~= "string" or unitClass == "" then
			return nil
		end
		local kindKey = toPascalCase(unitKind)
		local classKey = toPascalCase(unitClass)
		local kindTable = (CombatParamsConfig :: any)[kindKey]
		if type(kindTable) ~= "table" then
			return nil
		end
		stats = (kindTable :: any)[classKey]
	end
	if type(stats) ~= "table" then
		return nil
	end
	local hp = (stats :: any).Health
	if type(hp) ~= "number" or hp <= 0 then
		return nil
	end

	return hp
end

local function resolveMoveSpeed(model: Model): number?
	local stats: any? = nil
	if type(CombatParamsConfig) == "table" and type((CombatParamsConfig :: any).ResolveForModel) == "function" then
		stats = (CombatParamsConfig :: any).ResolveForModel(model)
	else
		local unitKind = model:GetAttribute("UnitKind")
		local unitClass = model:GetAttribute("UnitClass")
		if type(unitKind) ~= "string" or unitKind == "" then
			return nil
		end
		if type(unitClass) ~= "string" or unitClass == "" then
			return nil
		end
		local kindKey = toPascalCase(unitKind)
		local classKey = toPascalCase(unitClass)
		local kindTable = (CombatParamsConfig :: any)[kindKey]
		if type(kindTable) ~= "table" then
			return nil
		end
		stats = (kindTable :: any)[classKey]
	end
	if type(stats) ~= "table" then
		return nil
	end
	local speed = (stats :: any).MoveSpeed
	if type(speed) ~= "number" or speed <= 0 then
		return nil
	end

	return speed
end

local animationCache: { [string]: Animation } = {}

local function getOrCreateAnimation(assetId: string): Animation
	local existing = animationCache[assetId]
	if existing then
		return existing
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = assetId
	animation.Parent = script
	animationCache[assetId] = animation
	return animation
end

local npcFolders: { Instance } = {}

local function refreshNpcFolders()
	local folders = {}
	for _, name in ipairs(NPC_FOLDER_NAMES) do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(folders, folder)
		end
	end
	npcFolders = folders
end

local function isNpcModel(model: Model): boolean
	for _, folder in ipairs(npcFolders) do
		if model:IsDescendantOf(folder) then
			return true
		end
	end
	return false
end

local function getUnitClassLower(model: Model): string
	local unitClass = model:GetAttribute("UnitClass")
	if type(unitClass) == "string" then
		return unitClass:lower()
	end
	return ""
end

local function isRangedUnit(model: Model): boolean
	local unitClass = getUnitClassLower(model)
	return unitClass == "archer" or unitClass == "crossbowman"
end

local function isMageUnit(model: Model): boolean
	return getUnitClassLower(model) == "mage"
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

local projectilesFolder: Folder? = nil

local function getProjectilesFolder(): Folder
	if projectilesFolder and projectilesFolder.Parent == Workspace then
		return projectilesFolder
	end

	local existing = Workspace:FindFirstChild("DebugProjectiles")
	if existing and existing:IsA("Folder") then
		projectilesFolder = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "DebugProjectiles"
	folder.Parent = Workspace
	projectilesFolder = folder
	return folder
end

local function spawnArrowSegmentProjectile(fromPos: Vector3, toPos: Vector3)
	local delta = (toPos - fromPos)
	local dist = delta.Magnitude
	if dist < 0.5 then
		return
	end

	local dir = delta.Unit
	local segmentLen = math.min(ARROW_SEGMENT_LENGTH, dist)

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
	part.Parent = getProjectilesFolder()

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

local magicProjectilesFolder: Folder? = nil

local function getMagicProjectilesFolder(): Folder
	if magicProjectilesFolder and magicProjectilesFolder.Parent == Workspace then
		return magicProjectilesFolder
	end

	local existing = Workspace:FindFirstChild("DebugMagicProjectiles")
	if existing and existing:IsA("Folder") then
		magicProjectilesFolder = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "DebugMagicProjectiles"
	folder.Parent = Workspace
	magicProjectilesFolder = folder
	return folder
end

local function spawnMagicBeamSegment(fromPos: Vector3, toPos: Vector3)
	local delta = (toPos - fromPos)
	local dist = delta.Magnitude
	if dist < 0.5 then
		return
	end

	local dir = delta.Unit
	local segmentLen = math.min(MAGIC_SEGMENT_LENGTH, dist)

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
	part.Parent = getMagicProjectilesFolder()

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

local observedNpcModels: { [Model]: boolean } = {} :: any
setmetatable(observedNpcModels, { __mode = "k" })

local combatStatsAppliedByNpc: { [Model]: boolean } = {} :: any
setmetatable(combatStatsAppliedByNpc, { __mode = "k" })

local diedConnByNpc: { [Model]: RBXScriptConnection } = {} :: any
setmetatable(diedConnByNpc, { __mode = "k" })

local healthConnByNpc: { [Model]: RBXScriptConnection } = {} :: any
setmetatable(healthConnByNpc, { __mode = "k" })

local deathCleanupScheduledByNpc: { [Model]: boolean } = {} :: any
setmetatable(deathCleanupScheduledByNpc, { __mode = "k" })

local attackTrackByNpc: { [Model]: AnimationTrack } = {} :: any
setmetatable(attackTrackByNpc, { __mode = "k" })

local currentTargetByNpc: { [Model]: Model } = {} :: any
setmetatable(currentTargetByNpc, { __mode = "k" })

local lastShotAtByNpc: { [Model]: number } = {} :: any
setmetatable(lastShotAtByNpc, { __mode = "k" })

local lastCastAtByNpc: { [Model]: number } = {} :: any
setmetatable(lastCastAtByNpc, { __mode = "k" })

local attackMarkerConnByNpc: { [Model]: RBXScriptConnection } = {} :: any
setmetatable(attackMarkerConnByNpc, { __mode = "k" })

local function stopAttack(npc: Model)
	currentTargetByNpc[npc] = nil
	lastShotAtByNpc[npc] = nil
	lastCastAtByNpc[npc] = nil
	local markerConn = attackMarkerConnByNpc[npc]
	if markerConn then
		attackMarkerConnByNpc[npc] = nil
		markerConn:Disconnect()
	end
	local track = attackTrackByNpc[npc]
	if track then
		attackTrackByNpc[npc] = nil
		pcall(function()
			track:Stop(0.1)
		end)
		pcall(function()
			track:Destroy()
		end)
	end
end

local function isDying(npc: Model): boolean
	local value = npc:GetAttribute("Dying")
	return value == true
end

local function anchorRootForDeath(npc: Model)
	local root = getRootPart(npc)
	if root then
		pcall(function()
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = true
		end)
	end
end

local function playDeathAndCleanup(npc: Model)
	if deathCleanupScheduledByNpc[npc] then
		return
	end
	deathCleanupScheduledByNpc[npc] = true

	pcall(function()
		npc:SetAttribute("Dying", true)
	end)

	anchorRootForDeath(npc)

	stopAttack(npc)

	local humanoid = getHumanoid(npc)
	if humanoid then
		pcall(function()
			humanoid.WalkSpeed = 0
		end)
		pcall(function()
			humanoid.JumpPower = 0
		end)
		pcall(function()
			humanoid.AutoRotate = false
		end)
		pcall(function()
			humanoid.PlatformStand = true
		end)
	end

	local assetId = resolveAnimationId(npc, "Die")
	if assetId and humanoid then
		local animator = ensureAnimator(humanoid)
		local animation = getOrCreateAnimation(assetId)
		local track: AnimationTrack?
		pcall(function()
			track = animator:LoadAnimation(animation)
		end)
		if track then
			track.Looped = false
			pcall(function()
				track.Priority = Enum.AnimationPriority.Action
			end)
			pcall(function()
				track:Play(0.05, 1, 1)
			end)
			task.delay(NPC_DESPAWN_SECONDS, function()
				pcall(function()
					track:Stop(0.05)
				end)
				pcall(function()
					track:Destroy()
				end)
			end)
		end
	end

	Debris:AddItem(npc, NPC_DESPAWN_SECONDS)
end

local function applyCombatStatsIfNeeded(npc: Model)
	if combatStatsAppliedByNpc[npc] then
		return
	end

	local humanoid = getHumanoid(npc)
	if not humanoid then
		return
	end

	combatStatsAppliedByNpc[npc] = true

	pcall(function()
		humanoid.BreakJointsOnDeath = false
	end)

	local hp = resolveHealth(npc)
	if hp then
		pcall(function()
			humanoid.MaxHealth = hp
			if humanoid.Health > hp or humanoid.Health <= 0 then
				humanoid.Health = hp
			end
		end)
	end

	local speed = resolveMoveSpeed(npc)
	if speed then
		pcall(function()
			humanoid.WalkSpeed = speed
		end)
	end

	if not diedConnByNpc[npc] then
		diedConnByNpc[npc] = humanoid.Died:Connect(function()
			playDeathAndCleanup(npc)
		end)
	end

	if not healthConnByNpc[npc] then
		healthConnByNpc[npc] = humanoid.HealthChanged:Connect(function(health)
			if health <= 0 and not deathCleanupScheduledByNpc[npc] then
				-- Prevent default death physics from making the rig slump/sink before the death animation.
				anchorRootForDeath(npc)
				pcall(function()
					humanoid.Health = 1
				end)
				playDeathAndCleanup(npc)
			end
		end)
	end

	if not diedConnByNpc[npc] then
		-- no-op (kept for safety)
		npc.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				local conn = diedConnByNpc[npc]
				if conn then
					diedConnByNpc[npc] = nil
					conn:Disconnect()
				end
				local hconn = healthConnByNpc[npc]
				if hconn then
					healthConnByNpc[npc] = nil
					hconn:Disconnect()
				end
			end
		end)
	end
end

local function dealDamageNow(attacker: Model, target: Model)
	if not attacker.Parent or not target.Parent then
		return
	end
	if isDying(attacker) or isDying(target) then
		return
	end

	local attackerTeamId = Affiliation.GetTeamIdFromModel(attacker)
	local targetTeamId = Affiliation.GetTeamIdFromModel(target)
	if attackerTeamId <= 0 then
		return
	end
	if targetTeamId == attackerTeamId then
		return
	end

	local attackerHumanoid = getHumanoid(attacker)
	local targetHumanoid = getHumanoid(target)
	if not attackerHumanoid or attackerHumanoid.Health <= 0 then
		return
	end
	local isCastle = CastleHealthService.IsCastle(target)
	if targetHumanoid then
		if targetHumanoid.Health <= 0 then
			return
		end
	else
		if not isCastle then
			return
		end
		if CastleHealthService.IsDestroyed(target) then
			return
		end
	end

	local attackerRoot = getRootPart(attacker)
	local targetRoot = getRootPart(target)
	if not attackerRoot or not targetRoot then
		return
	end

	local range = resolveAttackRange(attacker)
		or (if isRangedUnit(attacker) or isMageUnit(attacker) then RANGED_ATTACK_RADIUS else MELEE_ATTACK_RADIUS)
	local dist = (targetRoot.Position - attackerRoot.Position).Magnitude
	if dist > range + 2 then
		return
	end

	local dmg = resolveDamage(attacker)
	if not dmg then
		return
	end

	if targetHumanoid then
		targetHumanoid:TakeDamage(dmg)
	else
		CastleHealthService.ApplyDamage(target, dmg, attacker)
	end
end

local function shootRangedNow(attacker: Model, target: Model)
	if not isRangedUnit(attacker) then
		return
	end

	local now = os.clock()
	local last = lastShotAtByNpc[attacker]
	if last and (now - last) < MIN_SHOT_INTERVAL_SECONDS then
		return
	end

	local originAttachment = getArrowOrigin(attacker)
	if not originAttachment then
		return
	end

	local targetRoot = getRootPart(target)
	if not targetRoot then
		return
	end

	lastShotAtByNpc[attacker] = now
	local fromPos = originAttachment.WorldPosition
	local toPos = targetRoot.Position + Vector3.new(0, 1.6, 0)
	spawnArrowSegmentProjectile(fromPos, toPos)
end

local function castMagicNow(attacker: Model, target: Model)
	if not isMageUnit(attacker) then
		return
	end

	local now = os.clock()
	local last = lastCastAtByNpc[attacker]
	if last and (now - last) < MAGIC_MIN_INTERVAL_SECONDS then
		return
	end

	local originAttachment = getCastOrigin(attacker)
	if not originAttachment then
		return
	end

	local targetRoot = getRootPart(target)
	if not targetRoot then
		return
	end

	lastCastAtByNpc[attacker] = now
	local fromPos = originAttachment.WorldPosition
	local toPos = targetRoot.Position + Vector3.new(0, 1.6, 0)
	spawnMagicBeamSegment(fromPos, toPos)
end

local function onAttackMarker(attacker: Model, param: string)
	if param ~= ATTACK_RELEASE_PARAM then
		return
	end

	local target = currentTargetByNpc[attacker]
	if not target or not target.Parent then
		return
	end

	dealDamageNow(attacker, target)
	if isMageUnit(attacker) then
		castMagicNow(attacker, target)
	else
		shootRangedNow(attacker, target)
	end
end

local function onCastMarker(attacker: Model, param: string)
	if param ~= CAST_RELEASE_PARAM then
		return
	end

	local target = currentTargetByNpc[attacker]
	if not target or not target.Parent then
		return
	end

	dealDamageNow(attacker, target)
	castMagicNow(attacker, target)
end

local function playOrEnsureAttack(npc: Model)
	local humanoid = getHumanoid(npc)
	if not humanoid or humanoid.Health <= 0 then
		stopAttack(npc)
		return
	end

	local existing = attackTrackByNpc[npc]
	if existing and existing.IsPlaying then
		return
	end

	local requestedKey = if isMageUnit(npc) then "Cast" else "Attack"
	local assetId = resolveAnimationId(npc, requestedKey)
	local resolvedKey = requestedKey
	if not assetId and requestedKey == "Cast" then
		assetId = resolveAnimationId(npc, "Attack")
		if assetId then
			resolvedKey = "Attack"
		end
	end
	if not assetId then
		return
	end

	local animator = ensureAnimator(humanoid)
	local animation = getOrCreateAnimation(assetId)

	local track: AnimationTrack?
	local ok = pcall(function()
		track = animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return
	end

	track.Looped = true
	pcall(function()
		track.Priority = Enum.AnimationPriority.Action
	end)
	attackTrackByNpc[npc] = track

	local existingMarkerConn = attackMarkerConnByNpc[npc]
	if existingMarkerConn then
		existingMarkerConn:Disconnect()
		attackMarkerConnByNpc[npc] = nil
	end

	if resolvedKey == "Cast" then
		attackMarkerConnByNpc[npc] = track:GetMarkerReachedSignal(CAST_MARKER_NAME):Connect(function(param)
			onCastMarker(npc, tostring(param))
		end)
	else
		attackMarkerConnByNpc[npc] = track:GetMarkerReachedSignal(ATTACK_MARKER_NAME):Connect(function(param)
			onAttackMarker(npc, tostring(param))
		end)
	end

	pcall(function()
		track:Play(0.1, 1, 1)
	end)
end

local function faceTarget(attacker: Model, target: Model)
	local attackerRoot = getRootPart(attacker)
	local targetRoot = getRootPart(target)
	if not attackerRoot or not targetRoot then
		return
	end

	local aPos = attackerRoot.Position
	local tPos = targetRoot.Position
	local flatDir = Vector3.new(tPos.X - aPos.X, 0, tPos.Z - aPos.Z)
	if flatDir.Magnitude < 1e-4 then
		return
	end

	local currentRootCf = attackerRoot.CFrame
	local desiredRootCf = CFrame.lookAt(aPos, aPos + flatDir.Unit, currentRootCf.UpVector)
	local delta = desiredRootCf * currentRootCf:Inverse()
	pcall(function()
		attacker:PivotTo(delta * attacker:GetPivot())
	end)
end

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

local function findNearestEnemyCastle(attacker: Model, radius: number): Model?
	local attackerTeamId = Affiliation.GetTeamIdFromModel(attacker)
	if attackerTeamId <= 0 then
		return nil
	end

	local attackerRoot = getRootPart(attacker)
	if not attackerRoot then
		return nil
	end

	local buildings = Workspace:FindFirstChild("PlayerBuildings")
	if not buildings then
		return nil
	end

	local maxDist = radius + 2
	local best: Model? = nil
	local bestDist = math.huge

	for _, child in ipairs(buildings:GetChildren()) do
		if child:IsA("Model") and CastleHealthService.IsCastle(child) then
			if not CastleHealthService.IsDestroyed(child) then
				local teamId = Affiliation.GetTeamIdFromModel(child)
				if teamId ~= attackerTeamId and teamId > 0 then
					local root = getRootPart(child)
					local pos = root and root.Position or child:GetPivot().Position
					local dist = (pos - attackerRoot.Position).Magnitude
					if dist <= maxDist and dist < bestDist then
						bestDist = dist
						best = child
					end
				end
			end
		end
	end

	return best
end

local function findNearestEnemyNpc(attacker: Model, radius: number): Model?
	local attackerTeamId = Affiliation.GetTeamIdFromModel(attacker)
	if attackerTeamId <= 0 then
		return nil
	end

	local attackerRoot = getRootPart(attacker)
	if not attackerRoot then
		return nil
	end

	local attackerHumanoid = getHumanoid(attacker)
	if not attackerHumanoid or attackerHumanoid.Health <= 0 then
		return nil
	end

	if #npcFolders == 0 then
		return nil
	end
	overlapParams.FilterDescendantsInstances = npcFolders
	local maxDist = radius + 2

	local parts = Workspace:GetPartBoundsInRadius(attackerRoot.Position, radius, overlapParams)
	local bestTarget: Model? = nil
	local bestDist = math.huge

	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model ~= attacker and model:IsA("Model") and isNpcModel(model) then
			local targetTeamId = Affiliation.GetTeamIdFromModel(model)
			if targetTeamId ~= attackerTeamId then
				local targetHumanoid = getHumanoid(model)
				local targetRoot = getRootPart(model)
				if targetHumanoid and targetRoot and targetHumanoid.Health > 0 then
					local dist = (targetRoot.Position - attackerRoot.Position).Magnitude
					if dist <= maxDist and dist < bestDist then
						bestDist = dist
						bestTarget = model
					end
				end
			end
		end
	end

	return bestTarget
end

local function tryShootRangedFallback(attacker: Model, target: Model)
	if not isRangedUnit(attacker) then
		return
	end

	local now = os.clock()
	local last = lastShotAtByNpc[attacker]
	if last and (now - last) < FALLBACK_RANGED_SHOT_INTERVAL_SECONDS then
		return
	end

	dealDamageNow(attacker, target)
	shootRangedNow(attacker, target)
end

local function stepNpc(attacker: Model)
	if not attacker.Parent then
		stopAttack(attacker)
		return
	end

	if not isNpcModel(attacker) then
		stopAttack(attacker)
		return
	end

	local attackerTeamId = Affiliation.GetTeamIdFromModel(attacker)
	if attackerTeamId <= 0 then
		stopAttack(attacker)
		return
	end

	applyCombatStatsIfNeeded(attacker)

	local radius = resolveAttackRange(attacker)
		or (if isRangedUnit(attacker) then RANGED_ATTACK_RADIUS else MELEE_ATTACK_RADIUS)
	local target = findNearestEnemyNpc(attacker, radius)
	if target == nil then
		-- Variant 2: if no enemy NPC is in range, attack the nearest enemy castle.
		target = findNearestEnemyCastle(attacker, radius)
	end
	local current = currentTargetByNpc[attacker]
	if target == nil then
		if current ~= nil then
			stopAttack(attacker)
		end
		return
	end

	currentTargetByNpc[attacker] = target
	faceTarget(attacker, target)
	playOrEnsureAttack(attacker)
	-- If the Attack animation has no marker yet, still show something while testing.
	tryShootRangedFallback(attacker, target)
end

local function observeNpcFolder(folder: Instance)
	for _, inst in ipairs(folder:GetDescendants()) do
		if inst:IsA("Model") then
			observedNpcModels[inst] = true
			applyCombatStatsIfNeeded(inst)
		end
	end

	folder.DescendantAdded:Connect(function(inst)
		if inst:IsA("Model") then
			observedNpcModels[inst] = true
			applyCombatStatsIfNeeded(inst)
		end
	end)
end

refreshNpcFolders()
for _, folder in ipairs(npcFolders) do
	observeNpcFolder(folder)
end

Workspace.ChildAdded:Connect(function(child)
	if child.Name == "NPC" or child.Name == "LiveNPC" then
		task.defer(function()
			refreshNpcFolders()
			observeNpcFolder(child)
		end)
	end
end)

task.spawn(function()
	while true do
		task.wait(SCAN_INTERVAL)
		for npcModel in pairs(observedNpcModels) do
			stepNpc(npcModel)
		end
	end
end)

return {}
