-- ServerScriptService.Services.BuffEffectService
-- Apply buff effects (billboard only, no specific mechanics)

local BuffEffectService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShopConfig = require(ReplicatedStorage.Configs.ShopConfig)

local HOLDER_NAME = "BuffBillboards"
local MAX_DISTANCE = 200

local BASE_Y = 1.6
local SPACING_Y = 0.65

local function prettifyName(name: string): string
	-- Insert spaces before capital letters (ForceField -> Force Field)
	local out = name:gsub("(%l)(%u)", "%1 %2")
	-- Handle sequences like XMLParser -> XML Parser
	out = out:gsub("(%u)(%u%l)", "%1 %2")
	return out
end

local function hashToColor(name: string): Color3
	-- Deterministic pleasant-ish color for any buff name.
	-- Keep saturation/value in a readable range.
	local hash = 0
	for i = 1, #name do
		hash = (hash * 31 + string.byte(name, i)) % 100000
	end
	local hue = (hash % 360) / 360
	local sat = 0.65
	local val = 1.0
	return Color3.fromHSV(hue, sat, val)
end

local function getStyle(buffName: string): (string, Color3)
	local cfgName, cfgColor = ShopConfig.GetBillboardStyle(buffName)
	local display = cfgName or prettifyName(buffName)
	local color = cfgColor or hashToColor(buffName)
	return display, color
end

local function getAdornee(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function getOrCreateHolder(character: Model): Folder
	local holder = character:FindFirstChild(HOLDER_NAME)
	if holder and holder:IsA("Folder") then
		return holder
	end
	holder = Instance.new("Folder")
	holder.Name = HOLDER_NAME
	holder.Parent = character
	return holder
end

local function relayout(holder: Folder)
	local list: { BillboardGui } = {}
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("BillboardGui") then
			table.insert(list, child)
		end
	end

	table.sort(list, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)

	for i, gui in ipairs(list) do
		gui.StudsOffset = Vector3.new(0, BASE_Y + (i - 1) * SPACING_Y, 0)
	end
end

local function createBillboard(holder: Folder, adornee: BasePart, buffName: string): BillboardGui
	local display, color = getStyle(buffName)

	local gui = Instance.new("BillboardGui")
	gui.Name = buffName
	gui.Adornee = adornee
	gui.AlwaysOnTop = true
	gui.MaxDistance = MAX_DISTANCE
	gui.Size = UDim2.new(0, 200, 0, 36)
	gui.StudsOffset = Vector3.new(0, BASE_Y, 0)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Text = display
	label.Parent = gui

	gui.Parent = holder
	return gui
end

function BuffEffectService.ApplyBuff(player: Player, buffName: string, _duration: number)
	local character = player.Character
	if not character then
		return
	end
	local adornee = getAdornee(character)
	if not adornee then
		return
	end

	local holder = getOrCreateHolder(character)
	local existing = holder:FindFirstChild(buffName)
	if existing and existing:IsA("BillboardGui") then
		-- refresh adornee and label text
		local display, color = getStyle(buffName)
		existing.Adornee = adornee
		local label = existing:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Text = display
			label.TextColor3 = color
		end
	else
		createBillboard(holder, adornee, buffName)
	end

	relayout(holder)
end

function BuffEffectService.RemoveBuff(player: Player, buffName: string)
	local character = player.Character
	if not character then
		return
	end
	local holder = character:FindFirstChild(HOLDER_NAME)
	if not holder or not holder:IsA("Folder") then
		return
	end

	local bb = holder:FindFirstChild(buffName)
	if bb and bb:IsA("BillboardGui") then
		bb:Destroy()
	end

	relayout(holder)
end

return BuffEffectService
