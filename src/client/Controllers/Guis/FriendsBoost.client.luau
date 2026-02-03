-- PATH: StarterPlayer.StarterPlayerScripts.Controllers.Guis.FriendsBoost

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GuiController = require(script.Parent.Parent.GuiController)

local GUI = GuiController.Guis.Right
local Buttons = GUI.Frame.Buttons
local Button = Buttons:WaitForChild("FriendsBoost")

local invitePromptEvent: RemoteEvent = ReplicatedStorage:WaitForChild("InvitePrompt")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local boostRemote: RemoteEvent = Remotes:WaitForChild("FriendsBoostUpdated")
local notifyRemote: RemoteEvent = Remotes:WaitForChild("FriendJoinLeaveNotification")
local presenceRemote: RemoteEvent = Remotes:WaitForChild("FriendPresenceForNewPlayer")

local _Local = {}
local Shared = {}

local started = false
local currentBoost = 1

local banner: Frame?
local bannerText: TextLabel?
local bannerShownPos = UDim2.new(0.5, 0, 0, 16)
local bannerHiddenPos = UDim2.new(0.5, 0, 0, -160)
local showToken = 0

local BANNER_HEIGHT = 100
local BANNER_PADDING_X = 18 + 18
local BANNER_MIN_WIDTH = 260
local BANNER_MAX_WIDTH_FACTOR = 0.9

local BANNER_TEXT_SIZE_MAX = 54
local BANNER_TEXT_SIZE_MIN = 12

local function applyFredokaOne(label: TextLabel)
	-- Prefer Enum.Font.FredokaOne if available, otherwise fall back to FontFace.
	local okEnum = pcall(function()
		label.Font = Enum.Font.FredokaOne
	end)
	if okEnum then
		return
	end

	pcall(function()
		label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	end)
end

local function ensureBanner()
	if banner and banner.Parent ~= nil and bannerText then
		return
	end

	local newBanner = (Instance.new("Frame") :: any) :: Frame
	newBanner.Name = "FriendsBoostBanner"
	newBanner.AnchorPoint = Vector2.new(0.5, 0)
	newBanner.Position = bannerHiddenPos
	newBanner.Size = UDim2.fromOffset(BANNER_MIN_WIDTH, BANNER_HEIGHT)
	newBanner.BackgroundColor3 = Color3.new(1, 1, 1)
	newBanner.BackgroundTransparency = 0
	newBanner.BorderSizePixel = 0
	newBanner.ZIndex = 50
	newBanner.Visible = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = newBanner

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = newBanner

	local newText = (Instance.new("TextLabel") :: any) :: TextLabel
	newText.Name = "Text"
	newText.BackgroundTransparency = 1
	newText.Size = UDim2.fromScale(1, 1)
	newText.TextWrapped = false
	newText.TextScaled = false
	newText.TextSize = BANNER_TEXT_SIZE_MAX
	newText.TextTruncate = Enum.TextTruncate.None
	newText.TextXAlignment = Enum.TextXAlignment.Center
	newText.TextYAlignment = Enum.TextYAlignment.Center
	newText.TextColor3 = Color3.fromRGB(0, 170, 0)
	newText.Text = ""
	newText.ZIndex = 51
	applyFredokaOne(newText)
	newText.Parent = newBanner

	newBanner.Parent = GUI

	banner = newBanner
	bannerText = newText
end

local function getViewportWidth(): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 0
	end
	return camera.ViewportSize.X
end

local function layoutBannerForText(text: string)
	if not banner or not bannerText then
		return
	end

	local viewportWidth = getViewportWidth()
	if viewportWidth <= 0 then
		return
	end

	local maxWidth = math.floor(viewportWidth * BANNER_MAX_WIDTH_FACTOR)
	if maxWidth <= 0 then
		return
	end

	-- Give ourselves the best chance to fit: allow banner up to maxWidth.
	local bannerMinWidth = math.min(BANNER_MIN_WIDTH, maxWidth)
	local availableTextWidth = math.max(1, maxWidth - BANNER_PADDING_X)

	local chosenTextSize = BANNER_TEXT_SIZE_MAX
	local measuredTextWidth = 0

	for size = BANNER_TEXT_SIZE_MAX, BANNER_TEXT_SIZE_MIN, -1 do
		local measured = TextService:GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(10000, BANNER_HEIGHT))
		measuredTextWidth = measured.X
		if measuredTextWidth <= availableTextWidth then
			chosenTextSize = size
			break
		end
		chosenTextSize = size
	end

	bannerText.TextSize = chosenTextSize

	-- Width: snug to text, but never exceed maxWidth.
	local targetWidth = math.clamp(math.ceil(measuredTextWidth) + BANNER_PADDING_X, bannerMinWidth, maxWidth)
	banner.Size = UDim2.fromOffset(targetWidth, BANNER_HEIGHT)
end

local function tweenTo(pos: UDim2)
	if not banner then
		return
	end
	TweenService:Create(
		banner,
		TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = pos }
	):Play()
end

local function showBanner(text: string)
	ensureBanner()
	if not banner or not bannerText then
		return
	end

	showToken += 1
	local token = showToken

	bannerText.Text = text
	banner.Visible = true

	-- Layout against viewport; retry briefly in case CurrentCamera isn't ready yet.
	layoutBannerForText(text)
	task.defer(function()
		layoutBannerForText(text)
	end)
	task.delay(0.1, function()
		layoutBannerForText(text)
	end)

	tweenTo(bannerShownPos)

	task.delay(7, function()
		if token ~= showToken then
			return
		end
		if not banner then
			return
		end
		tweenTo(bannerHiddenPos)
		task.delay(0.4, function()
			if token ~= showToken then
				return
			end
			if banner then
				banner.Visible = false
			end
		end)
	end)
end

function Shared.OnStart()
	if started then
		return
	end
	started = true

	Button.MouseButton1Click:Connect(function()
		invitePromptEvent:FireServer()
	end)

	boostRemote.OnClientEvent:Connect(function(boost: number)
		currentBoost = boost
		Button.Text = "Friends Boost: x" .. tostring(boost)
	end)

	notifyRemote.OnClientEvent:Connect(function(friendDisplayName: string, isJoin: boolean, boost: number?)
		local b = boost or currentBoost
		if isJoin then
			showBanner(friendDisplayName .. " joined. Friends Boost x" .. tostring(b))
		else
			showBanner(friendDisplayName .. " left. Friends Boost x" .. tostring(b))
		end
	end)

	presenceRemote.OnClientEvent:Connect(function(friendDisplayName: string, boost: number)
		showBanner("You joined " .. friendDisplayName .. ". Friends Boost x" .. tostring(boost))
	end)
end

Shared.OnStart()

return Shared
