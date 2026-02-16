-- StarterPlayer.StarterPlayerScripts.NpcDamagePopup

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RemoteNames = require(ReplicatedStorage:WaitForChild("RemoteNames"))
local TeamTextures = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("TeamTextures"))

local TEAM_ID_ATTRIBUTE = "TeamId"

local function collectColorNames(): { string }
	local names = {}
	for colorName in pairs(TeamTextures) do
		if type(colorName) == "string" then
			table.insert(names, colorName)
		end
	end

	local preferredOrder = { "red", "blue", "yellow", "black" }
	local preferredSet = {}
	for _, name in ipairs(preferredOrder) do
		preferredSet[name] = true
	end

	local ordered = {}
	for _, name in ipairs(preferredOrder) do
		if table.find(names, name) ~= nil then
			table.insert(ordered, name)
		end
	end

	table.sort(names)
	for _, name in ipairs(names) do
		if not preferredSet[name] then
			table.insert(ordered, name)
		end
	end

	return ordered
end

local ALL_COLORS = collectColorNames()
local TEAM_ID_TO_COLOR_NAME: { [number]: string } = {}
for i, name in ipairs(ALL_COLORS) do
	TEAM_ID_TO_COLOR_NAME[i] = name
end

local COLOR3_BY_NAME: { [string]: Color3 } = {
	red = Color3.fromRGB(255, 80, 80),
	blue = Color3.fromRGB(95, 170, 255),
	yellow = Color3.fromRGB(255, 220, 75),
	black = Color3.fromRGB(235, 235, 235),
	white = Color3.fromRGB(255, 255, 255),
	tan = Color3.fromRGB(235, 216, 180),
	purple = Color3.fromRGB(190, 125, 255),
	pink = Color3.fromRGB(255, 140, 200),
	green = Color3.fromRGB(120, 235, 120),
	brown = Color3.fromRGB(200, 150, 110),
}

local function getDamageColorForNpc(npc: Model): Color3
	local teamIdAttr = npc:GetAttribute(TEAM_ID_ATTRIBUTE)
	local teamId = if type(teamIdAttr) == "number" then math.floor(teamIdAttr) else 0
	local colorName = TEAM_ID_TO_COLOR_NAME[teamId]
	if colorName then
		local c = COLOR3_BY_NAME[colorName]
		if c then
			return c
		end
	end
	return Color3.fromRGB(255, 255, 255)
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local popupRemote: RemoteEvent = Remotes:WaitForChild(RemoteNames.NpcDamagePopup) :: RemoteEvent

local function getNpcRoot(npc: Model): BasePart?
	local hrp = npc:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	local primary = npc.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end
	local anyPart = npc:FindFirstChildWhichIsA("BasePart", true)
	return anyPart
end

local COIN_GREEN = Color3.fromRGB(80, 255, 120)

local function showDamagePopup(npc: Model, amount: number, overrideText: string?, overrideColor: Color3?, kind: string?)
	if amount <= 0 then
		return
	end

	local isCoin = (kind == "coins")

	local root = getNpcRoot(npc)
	if not root then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = if isCoin then "CoinPopup" else "DamagePopup"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 200
	if isCoin then
		-- Bigger text for coin rewards.
		billboard.Size = UDim2.fromOffset(180, 90)
		-- Keep coins more "anchored" and higher so they don't blend with damage numbers.
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 5.0, 0)
	else
		-- Make damage numbers slightly smaller than before.
		billboard.Size = UDim2.fromOffset(70, 34)
		billboard.StudsOffsetWorldSpace = Vector3.new(
			(math.random(-30, 30) / 100),
			3.1 + (math.random(0, 18) / 100),
			(math.random(-30, 30) / 100)
		)
	end
	billboard.Adornee = root
	billboard.Parent = root

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = if type(overrideText) == "string" and overrideText ~= "" then overrideText else tostring(amount)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	if isCoin then
		label.TextColor3 = COIN_GREEN
	else
		label.TextColor3 = if typeof(overrideColor) == "Color3" then overrideColor else getDamageColorForNpc(npc)
	end
	label.TextTransparency = 0
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = if isCoin then 3 else 2
	stroke.Color = Color3.fromRGB(10, 10, 10)
	stroke.Transparency = 0
	stroke.Parent = label

	local lifetime = if isCoin then 1.15 else 0.8
	local moveTime = if isCoin then 1.25 else 0.65

	local startOffset = billboard.StudsOffsetWorldSpace
	local endOffset = startOffset + (if isCoin then Vector3.new(0, 0.8, 0) else Vector3.new(0, 1.2, 0))

	TweenService:Create(
		billboard,
		TweenInfo.new(moveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = endOffset }
	):Play()

	TweenService:Create(
		label,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 1 }
	):Play()

	TweenService:Create(
		stroke,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 1 }
	):Play()

	task.delay(lifetime, function()
		if billboard.Parent then
			billboard:Destroy()
		end
	end)
end

popupRemote.OnClientEvent:Connect(function(npcInstance: Instance, amount: number, overrideText: any?, overrideColor: any?, kind: any?)
	if not npcInstance or not npcInstance:IsA("Model") then
		return
	end
	if typeof(amount) ~= "number" then
		return
	end
	local kindStr = if typeof(kind) == "string" then kind else nil
	if kindStr == "coins" then
		task.delay(1, function()
			showDamagePopup(npcInstance, amount, overrideText, overrideColor, kindStr)
		end)
		return
	end
	showDamagePopup(npcInstance, amount, overrideText, overrideColor, kindStr)
end)
