-- DISABLED: temporary debug removed.
return {}

--[[

local function getRootPart(model: Model): BasePart?
	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return model:FindFirstChildWhichIsA("BasePart")
end

local function getHumanoidRootPart(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function fmtVec3(v: Vector3): string
	return ("(%.1f, %.1f, %.1f)"):format(v.X, v.Y, v.Z)
end

local function listAnchoredParts(model: Model): ({string}, number)
	local names = {}
	local anchoredCount = 0
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			if inst.Anchored then
				anchoredCount += 1
				if #names < MAX_LISTED_PARTS then
					table.insert(names, inst:GetFullName())
				end
			end
		end
	end
	return names, anchoredCount
end

local function listCollidableParts(model: Model): ({string}, number)
	local names = {}
	local collidableCount = 0
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			if inst.CanCollide then
				collidableCount += 1
				if #names < MAX_LISTED_COLLIDERS then
					table.insert(names, inst:GetFullName())
				end
			end
		end
	end
	return names, collidableCount
end

local function countConstraints(model: Model): {[string]: number}
	local counts: {[string]: number} = {}
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("Constraint") or inst:IsA("Weld") or inst:IsA("WeldConstraint") or inst:IsA("Motor6D") then
			local className = inst.ClassName
			counts[className] = (counts[className] or 0) + 1
		end
	end
	return counts
end

local function countControllers(model: Model): {[string]: number}
	local counts: {[string]: number} = {}
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BodyMover")
			or inst:IsA("VectorForce")
			or inst:IsA("LinearVelocity")
			or inst:IsA("AngularVelocity")
			or inst:IsA("AlignPosition")
			or inst:IsA("AlignOrientation")
			or inst:IsA("Torque")
		then
			local className = inst.ClassName
			counts[className] = (counts[className] or 0) + 1
		end
	end
	return counts
end

local function networkOwnerString(part: BasePart?): string
	if not part then
		return "(no root part)"
	end
	local ok, owner = pcall(function()
		return part:GetNetworkOwner()
	end)
	if not ok then
		return "(GetNetworkOwner failed)"
	end
	if owner == nil then
		return "server"
	end
	return owner.Name
end

local function debugPrint(header: string, lines: {string})
	print(("[DBG:%s] %s"):format(TARGET_NAME, header))
	for _, line in ipairs(lines) do
		print(("[DBG:%s]   %s"):format(TARGET_NAME, line))
	end
end

local function attach(model: Model)
	local humanoid = getHumanoid(model)
	local root = getRootPart(model)
	local hrp = getHumanoidRootPart(model)

	debugPrint("ATTACH", {
		("Model=%s"):format(model:GetFullName()),
		("PrimaryPart=%s"):format(model.PrimaryPart and model.PrimaryPart:GetFullName() or "nil"),
		("RootPart=%s"):format(root and root:GetFullName() or "nil"),
		("HumanoidRootPart=%s"):format(hrp and hrp:GetFullName() or "nil"),
		("NetworkOwner(root)=%s"):format(networkOwnerString(root)),
		("UnitKind=%s"):format(tostring(model:GetAttribute("UnitKind"))),
		("UnitClass=%s"):format(tostring(model:GetAttribute("UnitClass"))),
		("HasHumanoid=%s"):format(humanoid and "true" or "false"),
	})

	if hrp then
		debugPrint("HRP", {
			("Anchored=%s"):format(tostring(hrp.Anchored)),
			("CanCollide=%s"):format(tostring(hrp.CanCollide)),
			("Massless=%s"):format(tostring(hrp.Massless)),
			("CollisionGroup=%s"):format(hrp.CollisionGroup),
			("AssemblyRootPart=%s"):format(hrp.AssemblyRootPart and hrp.AssemblyRootPart:GetFullName() or "nil"),
		})
	end

	local anchoredList, anchoredCount = listAnchoredParts(model)
	local collidersList, collidersCount = listCollidableParts(model)
	local constraints = countConstraints(model)
	local controllers = countControllers(model)
	local constraintLines = {}
	for className, count in pairs(constraints) do
		table.insert(constraintLines, ("%s=%d"):format(className, count))
	end
	table.sort(constraintLines)

	local controllerLines = {}
	for className, count in pairs(controllers) do
		table.insert(controllerLines, ("%s=%d"):format(className, count))
	end
	table.sort(controllerLines)

	debugPrint("STRUCTURE", {
		("AnchoredParts=%d"):format(anchoredCount),
		("CollidableParts=%d"):format(collidersCount),
		(#constraintLines > 0 and ("Constraints: " .. table.concat(constraintLines, ", ")) or "Constraints: none"),
		(#controllerLines > 0 and ("Controllers: " .. table.concat(controllerLines, ", ")) or "Controllers: none"),
	})
	for _, name in ipairs(anchoredList) do
		print(("[DBG:%s]   Anchored: %s"):format(TARGET_NAME, name))
	end
	if anchoredCount > #anchoredList then
		print(("[DBG:%s]   (and %d more anchored parts)"):format(TARGET_NAME, anchoredCount - #anchoredList))
	end

	for _, name in ipairs(collidersList) do
		print(("[DBG:%s]   CanCollide: %s"):format(TARGET_NAME, name))
	end
	if collidersCount > #collidersList then
		print(("[DBG:%s]   (and %d more collidable parts)"):format(TARGET_NAME, collidersCount - #collidersList))
	end

	if not humanoid then
		warn(("[DBG:%s] No Humanoid; cannot subscribe to movement events."):format(TARGET_NAME))
		return
	end

	humanoid.StateChanged:Connect(function(old, new)
		print(("[DBG:%s] Humanoid.StateChanged %s -> %s"):format(TARGET_NAME, tostring(old), tostring(new)))
	end)

	humanoid.Running:Connect(function(speed)
		print(("[DBG:%s] Humanoid.Running speed=%.2f"):format(TARGET_NAME, speed))
	end)

	humanoid.MoveToFinished:Connect(function(reached)
		print(("[DBG:%s] Humanoid.MoveToFinished reached=%s"):format(TARGET_NAME, tostring(reached)))
	end)

	humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		print(("[DBG:%s] Humanoid.WalkSpeed=%s"):format(TARGET_NAME, tostring(humanoid.WalkSpeed)))
	end)

	humanoid:GetPropertyChangedSignal("PlatformStand"):Connect(function()
		print(("[DBG:%s] Humanoid.PlatformStand=%s"):format(TARGET_NAME, tostring(humanoid.PlatformStand)))
	end)

	humanoid:GetPropertyChangedSignal("Sit"):Connect(function()
		print(("[DBG:%s] Humanoid.Sit=%s"):format(TARGET_NAME, tostring(humanoid.Sit)))
	end)

	humanoid:GetPropertyChangedSignal("Health"):Connect(function()
		print(("[DBG:%s] Humanoid.Health=%s"):format(TARGET_NAME, tostring(humanoid.Health)))
	end)

	humanoid:GetPropertyChangedSignal("WalkToPoint"):Connect(function()
		print(("[DBG:%s] Humanoid.WalkToPoint=%s"):format(TARGET_NAME, fmtVec3(humanoid.WalkToPoint)))
	end)

	humanoid:GetPropertyChangedSignal("WalkToPart"):Connect(function()
		local part = humanoid.WalkToPart
		print(("[DBG:%s] Humanoid.WalkToPart=%s"):format(TARGET_NAME, part and part:GetFullName() or "nil"))
	end)

	local lastSnapshotAt = 0
	RunService.Heartbeat:Connect(function()
		if not model.Parent then
			return
		end
		local now = os.clock()
		if now - lastSnapshotAt < SNAPSHOT_INTERVAL then
			return
		end
		lastSnapshotAt = now

		local currentRoot = getRootPart(model)
		local currentHrp = getHumanoidRootPart(model)
		local seatPart = humanoid.SeatPart
		local state = humanoid:GetState()
		local floor = humanoid.FloorMaterial
		local walkToPoint = humanoid.WalkToPoint
		local walkToPart = humanoid.WalkToPart

		local vel = Vector3.zero
		local anchored = false
		if currentRoot then
			vel = currentRoot.AssemblyLinearVelocity
			anchored = currentRoot.Anchored
		end

		local distToWalkTo = 0
		if currentRoot then
			distToWalkTo = (walkToPoint - currentRoot.Position).Magnitude
		end

		debugPrint("SNAPSHOT", {
			("Players=%d"):format(#Players:GetPlayers()),
			("WalkSpeed=%.2f"):format(humanoid.WalkSpeed),
			("HipHeight=%.2f"):format(humanoid.HipHeight),
			("AutoRotate=%s"):format(tostring(humanoid.AutoRotate)),
			("PlatformStand=%s"):format(tostring(humanoid.PlatformStand)),
			("Sit=%s"):format(tostring(humanoid.Sit)),
			("MoveDirection=%s"):format(fmtVec3(humanoid.MoveDirection)),
			("State=%s"):format(tostring(state)),
			("Floor=%s"):format(tostring(floor)),
			("SeatPart=%s"):format(seatPart and seatPart:GetFullName() or "nil"),
			("WalkToPart=%s"):format(walkToPart and walkToPart:GetFullName() or "nil"),
			("WalkToPoint=%s dist=%.1f"):format(fmtVec3(walkToPoint), distToWalkTo),
			("RootAnchored=%s"):format(tostring(anchored)),
			("HRP=%s"):format(currentHrp and currentHrp:GetFullName() or "nil"),
			("RootPos=%s"):format(currentRoot and fmtVec3(currentRoot.Position) or "nil"),
			("RootVel=%s mag=%.2f"):format(fmtVec3(vel), vel.Magnitude),
			("NetworkOwner(root)=%s"):format(networkOwnerString(currentRoot)),
		})
	end)
end

local function findTargetModel(): Model?
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") and inst.Name == TARGET_NAME then
			return inst
		end
	end
	return nil
end

local function start()
	local model = findTargetModel()
	if model then
		attach(model)
		return
	end

	warn(("[DBG:%s] Target model not found yet; waiting for it to appear."):format(TARGET_NAME))
	Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("Model") and inst.Name == TARGET_NAME then
			attach(inst)
		end
	end)
end

start()

return {}
]]
