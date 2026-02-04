-- PATH: StarterPlayer.StarterPlayerScripts.Controllers.Guis.Shop
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GuiController = require(script.Parent.Parent.GuiController)
local ShopConfig = require(ReplicatedStorage.Configs.ShopConfig)
local FormatNumber = require(ReplicatedStorage.Libs.FormatNumber.Simple)
local NpcIconRenderer = require(script.Parent.Parent:WaitForChild("NpcIconRenderer"))
local GridCells = require(ReplicatedStorage:WaitForChild("GridCells"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BuyItemRemote = Remotes:WaitForChild("BuyItem")
local PromptDevProductRemote = Remotes:FindFirstChild("PromptDevProduct")

local Gui = GuiController.Guis.Shop
local Frame = Gui.Frame
local Buffs = Frame:FindFirstChild("Buffs") or Frame:FindFirstChild("Gems")
if not Buffs then
	error("Shop GUI is missing container Frame.Buffs (or Frame.Gems)")
end
local Exit = Frame.Exit
local OpenButton = GuiController.Guis.Right.Frame.Buttons.Shop



local Local = {}
local Shared = {}

local started = false

local occupancyFolder: Folder? = nil

local function getBaseplate(): BasePart?
	local inst = workspace:FindFirstChild("Baseplate")
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function getRootPart(character: Model?): BasePart?
	if not character then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function ensureOccupancyFolder(): Folder?
	if occupancyFolder and occupancyFolder:IsDescendantOf(ReplicatedStorage) then
		return occupancyFolder
	end
	local inst = ReplicatedStorage:FindFirstChild("CellOccupancy")
	if inst and inst:IsA("Folder") then
		occupancyFolder = inst
		return occupancyFolder
	end
	occupancyFolder = nil
	return nil
end

local function getCurrentCellKeyUnderPlayer(): string?
	local player = Players.LocalPlayer
	local baseplate = getBaseplate()
	local root = getRootPart(player.Character)
	if not baseplate or not root then
		return nil
	end
	local ix, iz = GridCells.GetCellIndexFromWorld(baseplate, root.Position)
	if ix == nil or iz == nil then
		return nil
	end
	return GridCells.GetCellKey(ix, iz)
end

local function isCurrentCellBlocked(): boolean
	local key = getCurrentCellKeyUnderPlayer()
	if not key then
		return true
	end
	local folder = ensureOccupancyFolder()
	if not folder then
		return false
	end
	return folder:FindFirstChild(key) ~= nil
end

function Shared.OnStart()
	if started then
		return
	end
	started = true

	OpenButton.MouseButton1Click:Connect(Local.UpdateEnabled)
	Exit.MouseButton1Click:Connect(Local.UpdateEnabled)

	Local.GenerateBuffButtons()
end

function Local.UpdateEnabled()
	local nextEnabled = not Gui.Enabled
	if nextEnabled then
		-- Cannot open shop while standing on an occupied (or non-grid) cell.
		if isCurrentCellBlocked() then
			warn("[Shop] Cannot open shop: cell is occupied/reserved (or you are not on the grid)")
			Gui.Enabled = false
			return
		end
	end
	Gui.Enabled = nextEnabled
end

local function findNpcTemplate(unitKind: any, unitClass: any): Model?
	local npcRoot = ReplicatedStorage:FindFirstChild("NPC")
	if not npcRoot then
		npcRoot = ReplicatedStorage:WaitForChild("NPC", 5)
	end
	if not npcRoot then
		return nil
	end

	if type(unitKind) ~= "string" or type(unitClass) ~= "string" then
		return nil
	end
	local kindLower = unitKind:lower()
	local classLower = unitClass:lower()

	for _, inst in ipairs(npcRoot:GetDescendants()) do
		if inst:IsA("Model") then
			local k = inst:GetAttribute("UnitKind")
			local c = inst:GetAttribute("UnitClass")
			if type(k) == "string" and type(c) == "string" then
				if k:lower() == kindLower and c:lower() == classLower then
					return inst
				end
			end
		end
	end

	return nil
end

local function findNpcTemplateByName(npcModelName: any): Model?
	local npcRoot = ReplicatedStorage:FindFirstChild("NPC")
	if not npcRoot then
		npcRoot = ReplicatedStorage:WaitForChild("NPC", 5)
	end
	if not npcRoot then
		return nil
	end

	if type(npcModelName) ~= "string" or npcModelName == "" then
		return nil
	end

	local inst = npcRoot:FindFirstChild(npcModelName, true)
	if inst and inst:IsA("Model") then
		return inst
	end

	return nil
end

local function ensureViewportIcon(iconObject: Instance): ViewportFrame
	local existing = iconObject:FindFirstChild("Viewport")
	if existing and existing:IsA("ViewportFrame") then
		return existing
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Active = false
	viewport.Parent = iconObject
	return viewport
end

function Local.GenerateBuffButtons()
	local template = Buffs:FindFirstChild("Template")
	if not template then
		error("Shop GUI is missing Template inside " .. Buffs:GetFullName())
	end

	local layout = Buffs:FindFirstChildWhichIsA("UIGridLayout") or Buffs:FindFirstChildWhichIsA("UIListLayout")
	if layout then
		layout.SortOrder = Enum.SortOrder.LayoutOrder
	end

	local items = {}
	for name, config in pairs(ShopConfig.Config.Items) do
		if (config :: any).Enabled == false then
			continue
		end
		local price = tonumber((config :: any).Price)
		if price == nil then
			price = math.huge
		end
		table.insert(items, {
			name = name,
			config = config,
			price = price,
		})
	end

	table.sort(items, function(a, b)
		if a.price ~= b.price then
			return a.price < b.price
		end
		return a.name < b.name
	end)

	for index, item in ipairs(items) do
		local name = item.name
		local config = item.config
		local button = template:Clone()
		button.Name = name
		button.LayoutOrder = index
		button.Parent = Buffs

		button.Title.Text = name
		button.Amount.Text = config.Description or ""
		button.Buy.Price.Text = FormatNumber.FormatCompact(config.Price)
		local iconObj = button:FindFirstChild("Icon")
		if iconObj then
			if iconObj:IsA("ImageLabel") or iconObj:IsA("ImageButton") then
				(iconObj :: any).Image = ""
				(iconObj :: any).ImageTransparency = 1
			end
			local viewport = ensureViewportIcon(iconObj)
			local npcTemplate = findNpcTemplateByName((config :: any).NpcModelName)
			if not npcTemplate then
				npcTemplate = findNpcTemplate(config.UnitKind, config.UnitClass)
			end
			if npcTemplate then
				NpcIconRenderer.renderIntoViewport(viewport, npcTemplate, {
					yawOffsetRadians = NpcIconRenderer.DEFAULT_YAW_OFFSET_RADIANS,
				})
			else
				warn(string.format(
					"[Shop] NPC template not found for item=%s NpcModelName=%s UnitKind=%s UnitClass=%s",
					name,
					tostring((config :: any).NpcModelName),
					tostring(config.UnitKind),
					tostring(config.UnitClass)
				))
			end
		end

		if button:FindFirstChild("BuyRobux") and button.BuyRobux:FindFirstChild("Price") then
			local rp = tonumber(config.RobuxPrice)
			if rp and rp > 0 then
				button.BuyRobux.Price.Text = tostring(rp)
			end
		end

		button.Buy.MouseButton1Click:Connect(function()
			-- Close shop immediately on selection.
			Gui.Enabled = false
			if isCurrentCellBlocked() then
				warn("[Shop] Cannot spawn here: cell is occupied/reserved")
				return
			end
			BuyItemRemote:FireServer(name)
		end)

		-- Optional: DevProduct prompt flow (requires Remotes.PromptDevProduct and valid config.DevProductId)
		local devProductId = tonumber(config.DevProductId)
		if PromptDevProductRemote and devProductId and devProductId > 0 then
			if button:FindFirstChild("BuyRobux") then
				button.BuyRobux.MouseButton1Click:Connect(function()
					PromptDevProductRemote:FireServer(devProductId)
				end)
			end
			if button:FindFirstChild("Icon") then
				button.Icon.MouseButton1Click:Connect(function()
					PromptDevProductRemote:FireServer(devProductId)
				end)
			end
		elseif button:FindFirstChild("BuyRobux") then
			-- Make it explicit in output why nothing happens
			button.BuyRobux.MouseButton1Click:Connect(function()
				warn("[Shop] BuyRobux clicked, but PromptDevProduct/DevProductId is not configured")
			end)
		end
	end

	template.Visible = false
end

Shared.OnStart()
