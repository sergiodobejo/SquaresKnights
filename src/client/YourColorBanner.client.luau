-- StarterPlayer.StarterPlayerScripts.YourColorBanner

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeamColors = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("TeamColors"))

local TEAM_COLOR_ATTRIBUTE = "TeamColor"

local DISPLAY_SECONDS = 3

local function getTeamColorName(player: Player, timeoutSeconds: number): string
	local deadline = os.clock() + timeoutSeconds
	while os.clock() < deadline do
		local v = player:GetAttribute(TEAM_COLOR_ATTRIBUTE)
		if type(v) == "string" and v ~= "" then
			return v
		end
		task.wait(0.05)
	end
	return "white"
end

local function prettifyColorName(colorName: string): string
	if colorName == "" then
		return colorName
	end
	return colorName:sub(1, 1):upper() .. colorName:sub(2)
end

local function strokeForColorName(colorName: string): Color3
	if colorName:lower() == "black" then
		return Color3.new(1, 1, 1)
	end
	return Color3.new(0, 0, 0)
end

local function createTopContainer(): Frame
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")	
	gui.Name = "YourColorBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "Top"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.fromScale(0.5, 0)
	frame.Size = UDim2.new(1, 0, 0, 90)
	frame.Parent = gui

	return frame
end

local function createLabel(parent: Instance, textColor: Color3, strokeColor: Color3, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.new(1, 0, 0, 70)
	label.Position = UDim2.new(0, 0, 0, 10)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = textColor
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = strokeColor
	label.Parent = parent
	return label
end

local function createButton(parent: Instance, bg: Color3, textColor: Color3, strokeColor: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = "YourCastleButton"
	button.AutoButtonColor = true
	button.Size = UDim2.new(0, 220, 0, 44)
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, 20)
	button.BackgroundColor3 = bg
	button.BorderSizePixel = 0
	button.Font = Enum.Font.LuckiestGuy
	button.TextScaled = false
	button.TextSize = 26
	button.Text = "To Your Castle"
	button.TextColor3 = textColor
	button.TextXAlignment = Enum.TextXAlignment.Center
	button.TextYAlignment = Enum.TextYAlignment.Center
	button.TextStrokeTransparency = 0
	button.TextStrokeColor3 = strokeColor
	button.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	return button
end

local function main()
	local player = Players.LocalPlayer

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local teleportRemote = remotes:WaitForChild("TeleportToCastle")
	if not teleportRemote:IsA("RemoteEvent") then
		error("[YourColorBanner] ReplicatedStorage.Remotes.TeleportToCastle must be a RemoteEvent")
	end

	local colorName = getTeamColorName(player, 10)
	local teamColor3 = TeamColors.GetColor3(colorName)
	local strokeColor = strokeForColorName(colorName)

	local top = createTopContainer()
	local label = createLabel(top, teamColor3, strokeColor, string.format("Your color - %s", prettifyColorName(colorName)))

	task.delay(DISPLAY_SECONDS, function()
		if label.Parent then
			label:Destroy()
		end
		local buttonTextColor = Color3.new(1, 1, 1)
		local buttonStrokeColor = Color3.new(0, 0, 0)
		local button = createButton(top, teamColor3, buttonTextColor, buttonStrokeColor)
		button.Activated:Connect(function()
			teleportRemote:FireServer()
		end)
	end)
end

main()
