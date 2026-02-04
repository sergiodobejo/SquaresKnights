-- ServerScriptService.ShopDevProductHandler
-- Prompts Developer Product purchases from client UI

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PromptDevProduct = Remotes:WaitForChild("PromptDevProduct")

if not PromptDevProduct:IsA("RemoteEvent") then
	error("[ShopDevProductHandler] ReplicatedStorage.Remotes.PromptDevProduct must be a RemoteEvent")
end

PromptDevProduct.OnServerEvent:Connect(function(player, devId)
	local id = tonumber(devId)
	if not id then
		warn("[ShopDevProductHandler] Invalid devId from", player.Name)
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
