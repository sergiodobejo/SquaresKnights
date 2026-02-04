-- ServerScriptService.BuffPurchaseHandler
-- Handle buff purchases from client

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShopConfig = require(ReplicatedStorage.Configs.ShopConfig)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local GridCellSpawnService = require(ServerScriptService.Services.GridCellSpawnService)

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local BuyItemRemote = RemotesFolder:WaitForChild("BuyItem")

if not BuyItemRemote:IsA("RemoteEvent") then
	error("[BuffPurchaseHandler] ReplicatedStorage.Remotes.BuyItem must be a RemoteEvent")
end

BuyItemRemote.OnServerEvent:Connect(function(player, itemName)
	if typeof(itemName) ~= "string" then
		warn("[BuffPurchaseHandler] Reject: invalid itemName type from", player.Name, typeof(itemName))
		return
	end

	local config = ShopConfig.GetConfig(itemName)
	
	if not config then
		warn("[BuffPurchaseHandler] Invalid item:", itemName)
		return
	end
	if (config :: any).Enabled == false then
		warn("[BuffPurchaseHandler] Reject: item disabled:", itemName)
		return
	end

	local itemKind = config.ItemKind
	if itemKind ~= "npc" then
		warn("[BuffPurchaseHandler] Reject: unsupported ItemKind:", tostring(itemKind), "item=", itemName)
		return
	end

	local priceCoins = tonumber(config.Price) or 0
	if priceCoins > 0 then
		local beforeCoins = PlayerDataService.GetCoins(player)
		if beforeCoins < priceCoins then
			warn(string.format(
				"[BuffPurchaseHandler] NOT SOLD (coins insufficient) player=%s item=%s coins=%d price=%d",
				player.Name,
				itemName,
				beforeCoins,
				priceCoins
			))
			return
		end


		-- Deduct first, then refund if spawn fails.
		PlayerDataService.AddCoins(player, -priceCoins)
		local ok, reason = GridCellSpawnService.TrySpawnShopItemOnCurrentCell(player, itemName)
		if not ok then
			PlayerDataService.AddCoins(player, priceCoins)
			warn(string.format(
				"[BuffPurchaseHandler] Spawn rejected/refunded player=%s item=%s reason=%s",
				player.Name,
				itemName,
				tostring(reason)
			))
			return
		end

		local afterCoins = PlayerDataService.GetCoins(player)
		print(string.format(
			"[BuffPurchaseHandler] SOLD for COINS (grid spawn) player=%s item=%s price=%d coins:%d->%d",
			player.Name,
			itemName,
			priceCoins,
			beforeCoins,
			afterCoins
		))
	else
		warn("[BuffPurchaseHandler] Reject: item has no valid coin price:", itemName)
		return
	end
end)

return {}
