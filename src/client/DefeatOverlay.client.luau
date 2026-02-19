-- StarterPlayer.StarterPlayerScripts.DefeatOverlay
-- Shows a big "You have been defeated." message when the server signals defeat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteNames = require(ReplicatedStorage:WaitForChild("RemoteNames"))
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local defeatedRemote = remotesFolder:WaitForChild(RemoteNames.PlayerDefeated) :: RemoteEvent

local SoundCache = require(ReplicatedStorage:WaitForChild("Libs"):WaitForChild("SoundCache"))

local GUI_NAME = "DefeatOverlay"
local DEFAULT_TEXT = "You have been defeated."
local DEFAULT_MAX_TEXT_SIZE = 140

local LOSE_SFX_ID = "rbxassetid://75759245900834"
local WIN_SFX_ID = "rbxassetid://120357227206365"

local hideToken = 0

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
	label.Text = DEFAULT_TEXT
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.RichText = false
	label.Parent = gui

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = DEFAULT_MAX_TEXT_SIZE
	constraint.MinTextSize = 24
	constraint.Parent = label

	gui.Enabled = false
	gui.Parent = playerGui
	return gui
end

local function show(message: string?, durationSeconds: number?)
	local gui = ensureGui()

	local isVictory = false
	if type(message) == "string" then
		local lower = string.lower(message)
		isVictory = lower:find("victory", 1, true) ~= nil
	end
	SoundCache.Play(if isVictory then WIN_SFX_ID else LOSE_SFX_ID, {
		parent = SoundService,
		poolSize = 1,
	})

	local label = gui:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		(label :: TextLabel).Text = if type(message) == "string" and message ~= "" then message else DEFAULT_TEXT
	end

	hideToken += 1
	local tokenAtShow = hideToken
	gui.Enabled = true

	if type(durationSeconds) == "number" and durationSeconds > 0 then
		task.delay(durationSeconds, function()
			if tokenAtShow ~= hideToken then
				return
			end
			if gui and gui.Parent then
				gui.Enabled = false
			end
		end)
	end
end

defeatedRemote.OnClientEvent:Connect(function(message: string?, durationSeconds: number?)
	show(message, durationSeconds)
end)
