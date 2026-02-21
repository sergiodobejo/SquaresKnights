-- StarterPlayer.StarterPlayerScripts.DefeatOverlay
-- Shows match-end messages when the server signals defeat/victory.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local GuiStrings = require(script.Parent:WaitForChild("Controllers"):WaitForChild("GuiStrings"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteNames = require(ReplicatedStorage:WaitForChild("RemoteNames"))
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local defeatedRemote = remotesFolder:WaitForChild(RemoteNames.PlayerDefeated) :: RemoteEvent

local SoundCache = require(ReplicatedStorage:WaitForChild("Libs"):WaitForChild("SoundCache"))

local GUI_NAME = "DefeatOverlay"
local STR_DEFEATED = "DefeatOverlay_Defeated"
local STR_VICTORY = "DefeatOverlay_Victory"
local DEFAULT_TEXT = GuiStrings.get(STR_DEFEATED)
local DEFAULT_MAX_TEXT_SIZE = 140

local LOSE_SFX_ID = "rbxassetid://75759245900834"
local WIN_SFX_ID = "rbxassetid://120357227206365"

local hideToken = 0

type MessagePayload = {
	key: string,
	args: { any }?,
}

local function resolveText(messageOrPayload: any): (string?, string?)
	-- returns (text, key)
	if typeof(messageOrPayload) == "table" then
		local payload = messageOrPayload :: any
		if type(payload.key) == "string" then
			if type(payload.args) == "table" then
				return GuiStrings.format(payload.key, nil, table.unpack(payload.args)), payload.key
			end
			return GuiStrings.get(payload.key, nil), payload.key
		end
	end
	if type(messageOrPayload) == "string" and messageOrPayload ~= "" then
		-- Backward compatibility: server may still send a literal string.
		return messageOrPayload, nil
	end
	return nil, nil
end

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

local function show(messageOrPayload: any, durationSeconds: number?)
	local gui = ensureGui()

	local localDefeated = player:GetAttribute("Defeated") == true
	local localVictory = player:GetAttribute("Victory") == true

	local resolvedText, resolvedKey = resolveText(messageOrPayload)
	local isVictoryMsg = resolvedKey == STR_VICTORY
	local isDefeatMsg = resolvedKey == STR_DEFEATED

	-- Safety: never show/announce local defeat unless the local player is actually defeated.
	if isDefeatMsg and not localDefeated then
		return
	end

	-- Only play match-end SFX for the local player.
	if localVictory or isVictoryMsg then
		if localVictory then
			SoundCache.Play(WIN_SFX_ID, { parent = SoundService, poolSize = 1 })
		end
	elseif localDefeated then
		SoundCache.Play(LOSE_SFX_ID, { parent = SoundService, poolSize = 1 })
	end

	local label = gui:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		-- Only the defeated local player should ever see the default defeat text.
		local text = if type(resolvedText) == "string" and resolvedText ~= "" then resolvedText else DEFAULT_TEXT
		if text == DEFAULT_TEXT and not localDefeated then
			return
		end
		(label :: TextLabel).Text = text
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
