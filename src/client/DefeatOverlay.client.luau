-- StarterPlayer.StarterPlayerScripts.DefeatOverlay
-- Shows a big "You have been defeated." message when the server signals defeat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteNames = require(ReplicatedStorage:WaitForChild("RemoteNames"))
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local defeatedRemote = remotesFolder:WaitForChild(RemoteNames.PlayerDefeated) :: RemoteEvent

local GUI_NAME = "DefeatOverlay"

local function ensureGui(): ScreenGui
	local existing = playerGui:FindFirstChild(GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		return existing
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9999

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0, 0)
	label.AnchorPoint = Vector2.new(0, 0)
	label.Text = "You have been defeated."
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.RichText = false
	label.Parent = gui

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 140
	constraint.MinTextSize = 24
	constraint.Parent = label

	gui.Enabled = false
	gui.Parent = playerGui
	return gui
end

local function show()
	local gui = ensureGui()
	gui.Enabled = true
end

defeatedRemote.OnClientEvent:Connect(function()
	show()
end)
