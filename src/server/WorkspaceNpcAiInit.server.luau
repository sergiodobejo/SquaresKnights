-- ServerScriptService.WorkspaceNpcAiInit
--
-- Ensures NPCs placed under Workspace/NPC (including nested subfolders)
-- behave like spawned NPCs:
-- - (disabled) do NOT stamp a TeamId: avoids NPC-vs-NPC combat for Workspace/NPC rigs
-- - are tracked for damage popups

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local NpcDamagePopupService = require(ServerScriptService.Services:WaitForChild("NpcDamagePopupService"))

local initialized: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function getHumanoid(model: Model): Humanoid?
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

local function tryInitNpcModel(model: Model)
	if initialized[model] then
		return
	end

	-- Only consider actual character-like rigs.
	local humanoid = getHumanoid(model)
	if not humanoid then
		return
	end

	initialized[model] = true

	-- Combat participation for Workspace/NPC is intentionally disabled for now.
	-- Keep any existing TeamId if it was set elsewhere, but never stamp one here.
	pcall(function()
		model:SetAttribute("IsAiNpc", true)
	end)

	NpcDamagePopupService.TrackNpc(model)
end

local function initExistingUnder(folder: Instance)
	for _, inst in ipairs(folder:GetDescendants()) do
		if inst:IsA("Model") then
			tryInitNpcModel(inst)
		end
	end
end

local function hookFolder(folder: Instance)
	initExistingUnder(folder)

	folder.DescendantAdded:Connect(function(inst)
		if not inst:IsA("Model") then
			return
		end

		-- Give the model a moment to finish parenting its Humanoid.
		task.defer(function()
			tryInitNpcModel(inst)
			task.delay(0.5, function()
				tryInitNpcModel(inst)
			end)
		end)
	end)
end

local function tryStart()
	local npcFolder = Workspace:FindFirstChild("NPC")
	if npcFolder then
		hookFolder(npcFolder)
	end

	Workspace.ChildAdded:Connect(function(child)
		if child.Name ~= "NPC" then
			return
		end
		task.defer(function()
			hookFolder(child)
		end)
	end)
end

tryStart()

return {}
