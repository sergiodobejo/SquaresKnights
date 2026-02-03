-- ServerScriptService.ShopDevProductHandler
-- Prompts Developer Product purchases from client UI

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local PromptDevProduct = Remotes:FindFirstChild("PromptDevProduct")
if not PromptDevProduct then
	PromptDevProduct = Instance.new("RemoteEvent")
	PromptDevProduct.Name = "PromptDevProduct"
	PromptDevProduct.Parent = Remotes
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
