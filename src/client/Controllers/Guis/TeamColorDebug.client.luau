-- Debug GUI: shows your assigned team color bottom-right.

local Players = game:GetService("Players")

local GuiStrings = require(script.Parent.Parent:WaitForChild("GuiStrings"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "TeamColorDebug"
local TEAM_COLOR_ATTRIBUTE = "TeamColor"

local existing = playerGui:FindFirstChild(GUI_NAME)
if existing then
	existing:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Name = "Color"
label.AnchorPoint = Vector2.new(1, 1)
label.Position = UDim2.new(1, -12, 1, -12)
label.Size = UDim2.new(0, 220, 0, 28)
label.BackgroundTransparency = 1
label.TextXAlignment = Enum.TextXAlignment.Right
label.TextYAlignment = Enum.TextYAlignment.Bottom
label.Font = Enum.Font.GothamBold
label.TextSize = 18
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextStrokeTransparency = 0.5
label.Text = GuiStrings.get("TeamColorDebug_Unknown", "Team: ?")
label.Parent = screenGui

local function update()
	local colorName = player:GetAttribute(TEAM_COLOR_ATTRIBUTE)
	if type(colorName) ~= "string" or colorName == "" then
		label.Text = GuiStrings.get("TeamColorDebug_Unknown", "Team: ?")
	else
		label.Text = GuiStrings.format("TeamColorDebug_Format", "Team: %s", colorName)
	end
end

update()
player:GetAttributeChangedSignal(TEAM_COLOR_ATTRIBUTE):Connect(update)
