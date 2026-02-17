-- ServerScriptService.Services.CastleHealthService
-- Manages castle (and future building) health via Model attributes.

local Workspace = game:GetService("Workspace")

local HEALTH_ATTR = "Health"
local MAX_HEALTH_ATTR = "MaxHealth"
local DESTROYED_ATTR = "Destroyed"

local TEAM_ID_ATTR = "TeamId"
local OWNER_USER_ID_ATTR = "OwnerUserId"

local GUI_NAME = "CastleHealthBillboard"

local DEFAULT_MAX_HEALTH = 1000

local castleDestroyedBindable = Instance.new("BindableEvent")

local function getAnyBasePart(model: Model): BasePart?
	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end
	local inst = model:FindFirstChildWhichIsA("BasePart", true)
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function clampHealth(value: number, maxHealth: number): number
	if value ~= value then
		return 0
	end
	return math.clamp(value, 0, maxHealth)
end

local function formatHealth(value: number): string
	return tostring(math.floor(value + 0.5))
end

local function ensureBillboardGui(castle: Model, adornee: BasePart)
	local existing = castle:FindFirstChild(GUI_NAME)
	if existing and existing:IsA("BillboardGui") then
		(existing :: BillboardGui).Adornee = adornee
		return existing :: BillboardGui
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = GUI_NAME
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 300
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 12, 0)
	gui.Adornee = adornee

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.25
	label.Text = ""
	label.Parent = gui

	gui.Parent = castle
	return gui
end

local function updateBillboardText(castle: Model)
	local gui = castle:FindFirstChild(GUI_NAME)
	if not (gui and gui:IsA("BillboardGui")) then
		return
	end
	local label = gui:FindFirstChild("Label")
	if not (label and label:IsA("TextLabel")) then
		return
	end

	local health = castle:GetAttribute(HEALTH_ATTR)
	local maxHealth = castle:GetAttribute(MAX_HEALTH_ATTR)
	if type(health) ~= "number" then
		health = 0
	end
	if type(maxHealth) ~= "number" or maxHealth <= 0 then
		maxHealth = DEFAULT_MAX_HEALTH
	end
	(label :: TextLabel).Text = formatHealth(health)
end

local connectionsByCastle: { [Model]: { RBXScriptConnection } } = setmetatable({}, { __mode = "k" }) :: any

local Shared = {}

function Shared.GetOwnerUserId(castle: Model): number
	local v = castle:GetAttribute(OWNER_USER_ID_ATTR)
	if type(v) ~= "number" then
		return 0
	end
	if v ~= v or v <= 0 then
		return 0
	end
	return math.floor(v)
end

function Shared.OnCastleDestroyed(callback: (castle: Model, ownerUserId: number, teamId: number) -> ())
	return castleDestroyedBindable.Event:Connect(callback)
end

function Shared.IsCastle(model: Instance): boolean
	return model:IsA("Model") and string.find(model.Name, "SM_Castle_", 1, true) ~= nil
end

function Shared.GetCastleTeamId(castle: Model): number
	local v = castle:GetAttribute(TEAM_ID_ATTR)
	if type(v) ~= "number" then
		return 0
	end
	if v ~= v or v <= 0 then
		return 0
	end
	return math.floor(v)
end

function Shared.GetHealth(castle: Model): number
	local v = castle:GetAttribute(HEALTH_ATTR)
	if type(v) ~= "number" then
		return 0
	end
	if v ~= v or v < 0 then
		return 0
	end
	return v
end

function Shared.GetMaxHealth(castle: Model): number
	local v = castle:GetAttribute(MAX_HEALTH_ATTR)
	if type(v) ~= "number" then
		return DEFAULT_MAX_HEALTH
	end
	if v ~= v or v <= 0 then
		return DEFAULT_MAX_HEALTH
	end
	return v
end

function Shared.IsDestroyed(castle: Model): boolean
	return castle:GetAttribute(DESTROYED_ATTR) == true or Shared.GetHealth(castle) <= 0
end

function Shared.InitCastle(castle: Model, teamId: number?, ownerUserId: number?, maxHealth: number?)
	local prevMax = Shared.GetMaxHealth(castle)
	local mh = DEFAULT_MAX_HEALTH
	if type(maxHealth) == "number" and maxHealth > 0 then
		mh = math.floor(maxHealth)
	end

	if type(teamId) == "number" and teamId > 0 then
		castle:SetAttribute(TEAM_ID_ATTR, math.floor(teamId))
	end
	if type(ownerUserId) == "number" and ownerUserId > 0 then
		castle:SetAttribute(OWNER_USER_ID_ATTR, math.floor(ownerUserId))
	end

	castle:SetAttribute(MAX_HEALTH_ATTR, mh)
	local curHealth = castle:GetAttribute(HEALTH_ATTR)
	if type(curHealth) ~= "number" then
		castle:SetAttribute(HEALTH_ATTR, mh)
	else
		-- If the castle was at full health under the previous max, keep it at full after upgrading max.
		if type(prevMax) == "number" and prevMax > 0 and curHealth >= (prevMax - 1e-3) and prevMax < mh then
			castle:SetAttribute(HEALTH_ATTR, mh)
		else
			castle:SetAttribute(HEALTH_ATTR, clampHealth(curHealth, mh))
		end
	end
	castle:SetAttribute(DESTROYED_ATTR, false)

	local adornee = getAnyBasePart(castle)
	if adornee then
		ensureBillboardGui(castle, adornee)
		updateBillboardText(castle)
	end

	-- Avoid double-connecting.
	if connectionsByCastle[castle] then
		return
	end

	local conns: { RBXScriptConnection } = {}
	connectionsByCastle[castle] = conns

	table.insert(conns, castle:GetAttributeChangedSignal(HEALTH_ATTR):Connect(function()
		updateBillboardText(castle)
	end))
	table.insert(conns, castle:GetAttributeChangedSignal(MAX_HEALTH_ATTR):Connect(function()
		updateBillboardText(castle)
	end))
	table.insert(conns, castle.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil then
			return
		end
		local list = connectionsByCastle[castle]
		connectionsByCastle[castle] = nil
		if list then
			for _, c in ipairs(list) do
				pcall(function()
					c:Disconnect()
				end)
			end
		end
	end))
end

function Shared.ApplyDamage(castle: Model, amount: number, _source: Model?): boolean
	if not castle or not castle.Parent then
		return false
	end
	if Shared.IsDestroyed(castle) then
		return false
	end
	if type(amount) ~= "number" or amount <= 0 then
		return false
	end

	-- Replicated signal for clients/UI.
	pcall(function()
		castle:SetAttribute("LastDamagedServerTime", workspace:GetServerTimeNow())
	end)

	local maxHealth = Shared.GetMaxHealth(castle)
	local cur = Shared.GetHealth(castle)
	local nextHealth = clampHealth(cur - amount, maxHealth)
	castle:SetAttribute(HEALTH_ATTR, nextHealth)

	if nextHealth <= 0 then
		castle:SetAttribute(DESTROYED_ATTR, true)
		local ownerUserId = Shared.GetOwnerUserId(castle)
		local teamId = Shared.GetCastleTeamId(castle)
		-- Fire after marking destroyed but before model destruction.
		task.defer(function()
			castleDestroyedBindable:Fire(castle, ownerUserId, teamId)
		end)
		-- Destroy the model; CastleSpawnOnJoin listens for removal to unblock grid.
		task.defer(function()
			if castle.Parent then
				castle:Destroy()
			end
		end)
	end

	return true
end

-- Auto-init any castles already in Workspace.PlayerBuildings.
function Shared.TryInitExisting()
	local buildings = Workspace:FindFirstChild("PlayerBuildings")
	if not buildings then
		return
	end
	for _, child in ipairs(buildings:GetChildren()) do
		if child:IsA("Model") and Shared.IsCastle(child) then
			Shared.InitCastle(child, child:GetAttribute(TEAM_ID_ATTR), child:GetAttribute(OWNER_USER_ID_ATTR), DEFAULT_MAX_HEALTH)
		end
	end
end

return Shared
