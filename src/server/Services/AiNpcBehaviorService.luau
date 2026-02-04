-- ServerScriptService.Services.AiNpcBehaviorService
-- Controls AI NPC behavior: walking to target castle, attacking it (once castle health is added).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnitParams = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("UnitParams"))
local Animations = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("Animations"))

local WALK_ANIM_SPEED_FACTOR = 1.5 -- animation speed multiplier
local DEBUG = false

local function dprint(...)
	if DEBUG then
		print(...)
	end
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

local function getUnitParams(unitKind: string, unitClass: string): any?
	local kindKey = findKeyCaseInsensitive(UnitParams, unitKind)
	local params = if kindKey then UnitParams[kindKey] else nil
	if not params then
		return nil
	end
	local classKey = findKeyCaseInsensitive(params, unitClass)
	local classParams = if classKey then params[classKey] else nil
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
	
	local castleRoot = getCharacterRoot(targetCastle)
	if not castleRoot then
		castleRoot = targetCastle.PrimaryPart
	end
	if not castleRoot then
		-- Castle is not a character model; use its pivot position for targeting
		dprint("[AiNpcBehavior] Castle is not a character; using pivot for pathfinding")
		-- We'll use the castle's pivot position directly in the behavior loop
	end
	if not castleRoot and targetCastle:GetPivot() == CFrame.identity then
		dprint("[AiNpcBehavior] ERROR: Castle has no valid position")
		return
	end
	
	local unitKind, unitClass = getUnitKindAndClass(aiNpc)
	if not unitKind or not unitClass then
		dprint(string.format("[AiNpcBehavior] ERROR: NPC %s missing UnitKind or UnitClass attributes. Kind=%s, Class=%s", 
			aiNpc.Name, tostring(unitKind), tostring(unitClass)))
		return
	end
	
	local params = getUnitParams(unitKind, unitClass)
	if not params then
		dprint(string.format("[AiNpcBehavior] ERROR: No params found for %s/%s in UnitParams", 
			unitKind, unitClass))
		return
	end
	
	local moveSpeed = params.MoveSpeed or 16
	local attackRange = params.AttackRange or 20
	
	-- Set walk speed BEFORE animation to ensure movement happens
	humanoid.WalkSpeed = moveSpeed
	
	-- Play walk animation
	local walkAnimId = getAnimationId(unitKind, unitClass, "Walk")
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
		while root and root.Parent and humanoid and humanoid.Parent do
			iterations = iterations + 1
			
			-- Get castle target position (use HRP if available, else use pivot)
			local castleTargetPos = castleRoot and castleRoot.Position or targetCastle:GetPivot().Position
			local dist = (castleTargetPos - root.Position).Magnitude
			
			if iterations % 50 == 0 then -- Print every 50 iterations (~10 seconds)
				dprint(string.format("[AiNpcBehavior] %s distance to castle: %.1f studs", aiNpc.Name, dist))
			end
			
			if dist > attackRange then
				-- Walk towards castle
				humanoid:MoveTo(castleTargetPos)
				task.wait(0.2)
			else
				-- In attack range: prepare to attack (once castle has health system)
				humanoid:MoveTo(root.Position) -- Stop moving
				-- TODO: Play attack animation and damage castle when castle health is implemented
				task.wait(0.5)
			end
		end
	end)
end

return Shared
