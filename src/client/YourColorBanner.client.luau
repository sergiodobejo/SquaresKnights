-- StarterPlayer.StarterPlayerScripts.YourColorBanner

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeamColors = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("TeamColors"))
local RuntimeSettings = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("RuntimeSettings"))
local SoundCache = require(ReplicatedStorage:WaitForChild("Libs"):WaitForChild("SoundCache"))
local CastleUnderAttackSounds = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CastleUnderAttackSounds"))

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
	-- Slightly bias vertical padding so the LuckiestGuy glyphs are visually centered.
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 2)
	padding.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	return button
end

local function createUnderAttackLabel(parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "CastleUnderAttackLabel"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 66)
	label.Size = UDim2.new(1, -20, 0, 44)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = false
	label.TextSize = 20
	label.TextWrapped = true
	label.Text = "Castle under attack!\nDefend the castle!"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Visible = false
	label.Parent = parent
	return label
end

local function getLocalPlayerCastle(): Model?
	local player = Players.LocalPlayer
	local buildings = workspace:FindFirstChild("PlayerBuildings")
	if not buildings then
		return nil
	end
	local name = string.format("SM_Castle_%d", player.UserId)
	local castle = buildings:FindFirstChild(name)
	if castle and castle:IsA("Model") then
		return castle
	end
	return nil
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
		if (RuntimeSettings :: any).EnableToYourCastleButton == true then
			local createdButton = createButton(top, teamColor3, buttonTextColor, buttonStrokeColor)
			createdButton.Activated:Connect(function()
				teleportRemote:FireServer()
			end)
		end
		local underAttack = createUnderAttackLabel(top)

		local SHOW_SECONDS = 5
		local BREAK_SECONDS = 5
		local CONTINUE_GRACE_SECONDS = 6
		local BLINK_PERIOD_SECONDS = 0.35
		local SOUND_PERIOD_SECONDS = (SHOW_SECONDS + BREAK_SECONDS) * 2

		local lastShownAt = 0
		local lastSoundAt = -1e9
		local loopRunning = false

		local function getLastDamageTime(castle: Model): number
			local v = castle:GetAttribute("LastDamagedServerTime")
			if type(v) ~= "number" then
				return 0
			end
			if v ~= v or v <= 0 then
				return 0
			end
			return v
		end

		local function isAttackOngoing(castle: Model): boolean
			local lastDamage = getLastDamageTime(castle)
			if lastDamage <= 0 then
				return false
			end
			local now = workspace:GetServerTimeNow()
			return (now - lastDamage) <= CONTINUE_GRACE_SECONDS
		end

		local function maybeStartLoop(castle: Model)
			if loopRunning then
				return
			end
			loopRunning = true

			task.spawn(function()
				while castle.Parent ~= nil do
					if not isAttackOngoing(castle) then
						break
					end

					local now = workspace:GetServerTimeNow()
					if now - lastShownAt >= (SHOW_SECONDS + BREAK_SECONDS) then
						lastShownAt = now
						if now - lastSoundAt >= SOUND_PERIOD_SECONDS then
							lastSoundAt = now
							local soundId = (CastleUnderAttackSounds :: any).ResolveRandom and (CastleUnderAttackSounds :: any).ResolveRandom()
							if type(soundId) == "string" and soundId ~= "" then
								SoundCache.Play(soundId, { poolSize = 2 })
							end
						end
							underAttack.Visible = true
							local endAt = os.clock() + SHOW_SECONDS
							while os.clock() < endAt do
								underAttack.Visible = not underAttack.Visible
								task.wait(BLINK_PERIOD_SECONDS)
								if not isAttackOngoing(castle) then
									break
								end
							end
							underAttack.Visible = false
						task.wait(BREAK_SECONDS)
					else
						task.wait(0.2)
					end
				end
				underAttack.Visible = false
				loopRunning = false
			end)
		end

		-- Attach to castle when it appears; then listen for damage attribute.
		local function attach()
			local castle = getLocalPlayerCastle()
			if not castle then
				return
			end
			castle:GetAttributeChangedSignal("LastDamagedServerTime"):Connect(function()
				if isAttackOngoing(castle) then
					maybeStartLoop(castle)
				end
			end)
			if isAttackOngoing(castle) then
				maybeStartLoop(castle)
			end
		end

		attach()
		workspace.ChildAdded:Connect(function(child)
			if child and child.Name == "PlayerBuildings" then
				task.defer(attach)
			end
		end)
	end)
end

main()
