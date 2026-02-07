-- ServerScriptService.ShopDevProductHandler
-- Prompts Developer Product purchases from client UI

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ShopConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PromptDevProduct = Remotes:WaitForChild("PromptDevProduct")

if not PromptDevProduct:IsA("RemoteEvent") then
	error("[ShopDevProductHandler] ReplicatedStorage.Remotes.PromptDevProduct must be a RemoteEvent")
end

-- Rate limiting
local lastPromptTime: { [number]: number } = {}
local RATE_LIMIT_SECONDS = 2.0

-- Build a set of valid DevProductIds from ShopConfig
local function getValidDevProductIds(): { [number]: boolean }
	local validIds = {}
	for _, itemConfig in pairs(ShopConfig.Config.Items) do
		local devProductId = tonumber(itemConfig.DevProductId)
		if devProductId and devProductId > 0 then
			validIds[devProductId] = true
		end
	end
	return validIds
end

local validDevProductIds = getValidDevProductIds()

PromptDevProduct.OnServerEvent:Connect(function(player, devId)
	-- Type validation
	local id = tonumber(devId)
	if not id then
		warn("[ShopDevProductHandler] Invalid devId type from", player.Name, typeof(devId))
		return
	end

	-- Rate limiting
	local now = os.clock()
	local userId = player.UserId
	local lastTime = lastPromptTime[userId]
	if lastTime and (now - lastTime) < RATE_LIMIT_SECONDS then
		warn("[ShopDevProductHandler] Rate limit exceeded for", player.Name)
		return
	end
	lastPromptTime[userId] = now

	-- Validate DevProductId is in whitelist
	if not validDevProductIds[id] then
		warn("[ShopDevProductHandler] DevProductId", id, "not in whitelist from", player.Name)
		return
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, id)
	end)
	if not ok then
		warn("[ShopDevProductHandler] PromptProductPurchase failed:", err)
	end
end)

return {}
