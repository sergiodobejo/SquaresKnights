-- PATH: StarterPlayer.StarterPlayerScripts.Controllers.Guis.Shop
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

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

-- When closing the shop on mobile, the same tap can be observed by our tap-to-open logic
-- after Gui.Enabled flips to false. Suppress re-open briefly to avoid instant reopen.
local suppressWorldTapUntil = 0

function Local.CloseShop()
	Gui.Enabled = false
	suppressWorldTapUntil = os.clock() + 0.25
end

local occupancyFolder: Folder? = nil
local capturedBlocksFolder: Folder? = nil

local CAPTURED_BLOCKS_FOLDER_NAME = "CapturedCellBlocks"

local function getBaseplate(): BasePart?
	local inst = workspace:FindFirstChild("Baseplate")
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local VIEWPORT_RAY_DISTANCE = 50000

local MOUSE_CELL_SCREEN_TOLERANCE_PX = 32

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

local function ensureCapturedBlocksFolder(): Folder?
	if capturedBlocksFolder and capturedBlocksFolder:IsDescendantOf(ReplicatedStorage) then
		return capturedBlocksFolder
	end
	local inst = ReplicatedStorage:FindFirstChild(CAPTURED_BLOCKS_FOLDER_NAME)
	if inst and inst:IsA("Folder") then
		capturedBlocksFolder = inst
		return capturedBlocksFolder
	end
	capturedBlocksFolder = nil
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
	local capturedFolder = ensureCapturedBlocksFolder()
	local occupied = (folder ~= nil and folder:FindFirstChild(key) ~= nil)
	local captured = (capturedFolder ~= nil and capturedFolder:FindFirstChild(key) ~= nil)
	return occupied or captured
end

local function getCellKeyAtViewportPosition(viewportPos: Vector2): string?
	local baseplate = getBaseplate()
	local camera = Workspace.CurrentCamera
	if not baseplate or not camera then
		return nil
	end

	local ray = camera:ViewportPointToRay(viewportPos.X, viewportPos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { baseplate }
	params.IgnoreWater = true

	local result = Workspace:Raycast(ray.Origin, ray.Direction * VIEWPORT_RAY_DISTANCE, params)
	if not result then
		return nil
	end

	local ix, iz = GridCells.GetCellIndexFromWorld(baseplate, result.Position)
	if ix == nil or iz == nil then
		return nil
	end
	return GridCells.GetCellKey(ix, iz)
end

local function isViewportPosNearCurrentCellCenter(viewportPos: Vector2, tolerancePx: number): boolean
	if tolerancePx <= 0 then
		return false
	end

	local baseplate = getBaseplate()
	local camera = Workspace.CurrentCamera
	local root = getRootPart(Players.LocalPlayer.Character)
	if not baseplate or not camera or not root then
		return false
	end

	local ix, iz = GridCells.GetCellIndexFromWorld(baseplate, root.Position)
	if ix == nil or iz == nil then
		return false
	end
	-- Use a point on the top surface of the baseplate (where the click ray actually hits),
	-- not the baseplate's center plane.
	local cellCenterWorld = GridCells.GetCellCFrameOnTop(baseplate, ix, iz, 0).Position
	local screenPos, onScreen = camera:WorldToViewportPoint(cellCenterWorld)
	if not onScreen then
		return false
	end

	local dx = viewportPos.X - screenPos.X
	local dy = viewportPos.Y - screenPos.Y
	return (dx * dx + dy * dy) <= (tolerancePx * tolerancePx)
end

local function getRayFromViewportPosition(viewportPos: Vector2): (Vector3?, Vector3?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil, nil
	end
	local ray = camera:ViewportPointToRay(viewportPos.X, viewportPos.Y)
	local dir = ray.Direction
	local mag = dir.Magnitude
	if mag <= 0 then
		return nil, nil
	end
	return ray.Origin, dir / mag
end

local function isRayNearLocalCharacter(origin: Vector3, dirUnit: Vector3, nearRadiusStuds: number): boolean
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return false
	end
	local root = getRootPart(character)
	if not root then
		return false
	end

	-- If the ray hits the local character, treat it as a valid tap.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	local hit = Workspace:Raycast(origin, dirUnit * VIEWPORT_RAY_DISTANCE, params)
	if hit and hit.Instance and hit.Instance:IsDescendantOf(character) then
		return true
	end

	if nearRadiusStuds <= 0 then
		return false
	end

	-- Otherwise, allow taps that are "near" the character in 3D.
	local v = root.Position - origin
	local t = v:Dot(dirUnit)
	if t < 0 then
		return false
	end
	local closest = origin + dirUnit * t
	local dist = (root.Position - closest).Magnitude
	return dist <= nearRadiusStuds
end

-- nearCharacterRadiusStuds:
--  nil  -> only exact cell click
--  0    -> cell click OR direct click on the local character (no "near" radius)
--  >0   -> cell click OR direct click on/near the local character
-- screenTolerancePx: optional screen-space forgiveness (useful for mouse far zoom)
local function shouldOpenFromViewportTap(viewportPos: Vector2, nearCharacterRadiusStuds: number?, screenTolerancePx: number?): boolean
	local currentKey = getCurrentCellKeyUnderPlayer()
	if not currentKey then
		return false
	end
	if isCurrentCellBlocked() then
		return false
	end

	local clickedKey = getCellKeyAtViewportPosition(viewportPos)
	if clickedKey == currentKey then
		return true
	end

	if screenTolerancePx ~= nil and isViewportPosNearCurrentCellCenter(viewportPos, screenTolerancePx) then
		return true
	end

	if nearCharacterRadiusStuds ~= nil then
		local rayOrigin, rayDirUnit = getRayFromViewportPosition(viewportPos)
		if rayOrigin and rayDirUnit then
			return isRayNearLocalCharacter(rayOrigin, rayDirUnit, nearCharacterRadiusStuds)
		end
	end

	return false
end

function Shared.OnStart()
	if started then
		return
	end
	started = true

	if OpenButton:IsA("GuiButton") then
		OpenButton.Activated:Connect(Local.UpdateEnabled)
	end
	if Exit:IsA("GuiButton") then
		Exit.Activated:Connect(Local.UpdateEnabled)
	end

	-- Mouse: only open when clicking the same grid cell the player is standing on.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if Gui.Enabled then
			return
		end
		if os.clock() < suppressWorldTapUntil then
			return
		end

		local isClick = input.UserInputType == Enum.UserInputType.MouseButton1
		if not isClick then
			return
		end

		local mousePos = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		local rawViewportPos = Vector2.new(mousePos.X, mousePos.Y)
		local insetViewportPos = Vector2.new(mousePos.X - inset.X, mousePos.Y - inset.Y)

		if shouldOpenFromViewportTap(insetViewportPos, 0, MOUSE_CELL_SCREEN_TOLERANCE_PX)
			or shouldOpenFromViewportTap(rawViewportPos, 0, MOUSE_CELL_SCREEN_TOLERANCE_PX) then
			Gui.Enabled = true
		end
	end)

	-- Touch: open when tapping the same cell OR tapping on/near the local character.
	local function handleTouchTapPosition(pos: Vector2, processedByUI: boolean)
		if processedByUI then
			return
		end
		if Gui.Enabled then
			return
		end
		if os.clock() < suppressWorldTapUntil then
			return
		end

		-- Touch positions can be reported in screen coordinates; try both raw and inset-adjusted.
		local inset = GuiService:GetGuiInset()
		local rawViewportPos = Vector2.new(pos.X, pos.Y)
		local insetViewportPos = Vector2.new(pos.X - inset.X, pos.Y - inset.Y)

		local TOUCH_NEAR_RADIUS_STUDS = 10
		if shouldOpenFromViewportTap(rawViewportPos, TOUCH_NEAR_RADIUS_STUDS) or shouldOpenFromViewportTap(insetViewportPos, TOUCH_NEAR_RADIUS_STUDS) then
			Gui.Enabled = true
		end
	end

	-- Prefer world-only touch taps so UI buttons (Exit) don't accidentally trigger opening.
	UserInputService.TouchTapInWorld:Connect(function(pos: Vector2, processedByUI: boolean)
		handleTouchTapPosition(pos, processedByUI)
	end)

	-- Fallback for environments where TouchTapInWorld is flaky.
	UserInputService.TouchTap:Connect(function(touchPositions: { Vector2 }, processedByUI: boolean)
		local pos = touchPositions[1]
		if not pos then
			return
		end
		handleTouchTapPosition(pos, processedByUI)
	end)

	Local.GenerateBuffButtons()
end

function Local.UpdateEnabled()
	local nextEnabled = not Gui.Enabled
	if nextEnabled then
		-- Cannot open shop while standing on an occupied (or non-grid) cell.
		if isCurrentCellBlocked() then
			warn("[Shop] Cannot open shop: cell is occupied/reserved (or you are not on the grid)")
			Local.CloseShop()
			return
		end
	end
	if nextEnabled then
		Gui.Enabled = true
	else
		Local.CloseShop()
	end
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

		if button:FindFirstChild("Buy") and button.Buy:IsA("GuiButton") then
			button.Buy.Activated:Connect(function()
				-- Close shop immediately on selection.
				Local.CloseShop()
			if isCurrentCellBlocked() then
				warn("[Shop] Cannot spawn here: cell is occupied/reserved")
				return
			end
			BuyItemRemote:FireServer(name)
			end)
		end

		-- Optional: DevProduct prompt flow (requires Remotes.PromptDevProduct and valid config.DevProductId)
		local devProductId = tonumber(config.DevProductId)
		if PromptDevProductRemote and devProductId and devProductId > 0 then
			if button:FindFirstChild("BuyRobux") then
				if button.BuyRobux:IsA("GuiButton") then
					button.BuyRobux.Activated:Connect(function()
					PromptDevProductRemote:FireServer(devProductId)
					end)
				end
			end
			if button:FindFirstChild("Icon") then
				if button.Icon:IsA("GuiButton") then
					button.Icon.Activated:Connect(function()
					PromptDevProductRemote:FireServer(devProductId)
					end)
				end
			end
		elseif button:FindFirstChild("BuyRobux") then
			-- Make it explicit in output why nothing happens
			if button.BuyRobux:IsA("GuiButton") then
				button.BuyRobux.Activated:Connect(function()
					warn("[Shop] BuyRobux clicked, but PromptDevProduct/DevProductId is not configured")
				end)
			end
		end
	end

	template.Visible = false
end

Shared.OnStart()
