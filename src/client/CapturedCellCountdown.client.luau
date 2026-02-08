-- StarterPlayer.StarterPlayerScripts.CapturedCellCountdown
-- Shows a 5-second countdown number above temporarily-captured cells.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))

local CAPTURED_BLOCKS_FOLDER_NAME = "CapturedCellBlocks"

local TEXT_SIZE = 18
local MAX_DISTANCE = 120
local GUI_SIZE = UDim2.fromOffset(40, 40)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local baseplate: BasePart? = nil
local function getBaseplate(): BasePart?
	if baseplate and baseplate:IsDescendantOf(Workspace) then
		return baseplate
	end
	local inst = Workspace:FindFirstChild("Baseplate")
	if inst and inst:IsA("BasePart") then
		baseplate = inst
		return inst
	end
	baseplate = nil
	return nil
end

type Entry = {
	key: string,
	marker: Instance,
	attachment: Attachment,
	gui: BillboardGui,
	label: TextLabel,
	lastRemaining: number,
}

local entriesByKey: { [string]: Entry } = {}

local function destroyEntry(key: string)
	local entry = entriesByKey[key]
	if not entry then
		return
	end
	entriesByKey[key] = nil
	pcall(function()
		entry.gui:Destroy()
	end)
	pcall(function()
		entry.attachment:Destroy()
	end)
end

local function computeRemaining(marker: Instance): number?
	local expiresAt = marker:GetAttribute("ExpiresAt")
	if type(expiresAt) ~= "number" then
		return nil
	end
	local now = Workspace:GetServerTimeNow()
	local remaining = math.ceil(expiresAt - now)
	if remaining < 0 then
		remaining = 0
	end
	return remaining
end

local function createEntryForMarker(marker: Instance)
	local key = marker.Name
	if entriesByKey[key] then
		return
	end

	local bp = getBaseplate()
	if not bp then
		return
	end

	local ix, iz = GridCells.ParseCellKey(key)
	if ix == nil or iz == nil then
		return
	end

	local xCenter, zCenter = GridCells.GetCellCenterLocalXZ(bp, ix, iz)
	local attach = Instance.new("Attachment")
	attach.Name = "CaptureCountdown_" .. key
	attach.Position = Vector3.new(xCenter, (bp.Size.Y / 2) + 0.9, zCenter)
	attach.Parent = bp

	local gui = Instance.new("BillboardGui")
	gui.Name = "CaptureCountdownGui_" .. key
	gui.Adornee = attach
	gui.AlwaysOnTop = true
	gui.MaxDistance = MAX_DISTANCE
	gui.Size = GUI_SIZE
	gui.StudsOffsetWorldSpace = Vector3.zero
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.TextSize = TEXT_SIZE
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = ""
	label.Parent = gui

	entriesByKey[key] = {
		key = key,
		marker = marker,
		attachment = attach,
		gui = gui,
		label = label,
		lastRemaining = -1,
	}
end

local function refreshAll()
	for key, entry in pairs(entriesByKey) do
		if entry.marker.Parent == nil then
			destroyEntry(key)
			continue
		end
		local remaining = computeRemaining(entry.marker)
		if remaining == nil then
			-- If the server didn't set ExpiresAt (or it hasn't replicated yet), hide until it does.
			entry.gui.Enabled = false
			continue
		end
		if remaining <= 0 then
			-- Let ChildRemoved do cleanup, but hide immediately.
			entry.gui.Enabled = false
			continue
		end
		entry.gui.Enabled = true
		if remaining ~= entry.lastRemaining then
			entry.lastRemaining = remaining
			entry.label.Text = tostring(remaining)
		end
	end
end

local function hookFolder(folder: Folder)
	folder.ChildAdded:Connect(function(child)
		createEntryForMarker(child)
		refreshAll()
	end)
	folder.ChildRemoved:Connect(function(child)
		destroyEntry(child.Name)
	end)

	for _, child in ipairs(folder:GetChildren()) do
		createEntryForMarker(child)
	end
	refreshAll()
end

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild(CAPTURED_BLOCKS_FOLDER_NAME)
	if not folder or not folder:IsA("Folder") then
		return
	end
	hookFolder(folder)

	while true do
		-- Update at 1Hz; this keeps it cheap even with hundreds of cells.
		task.wait(1)
		refreshAll()
	end
end)
