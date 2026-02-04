-- ServerScriptService.ProcessReceiptHandler
-- Grants items after Developer Product purchase

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShopConfig = require(ReplicatedStorage.Configs.ShopConfig)
local NpcSpawnService = require(ServerScriptService.Services.NpcSpawnService)
local GridCellSpawnService = require(ServerScriptService.Services.GridCellSpawnService)


local function findItemByDevProductId(productId: number)
	for itemName, cfg in pairs(ShopConfig.Config.Items) do
		if type(cfg) == "table" and tonumber(cfg.DevProductId) == tonumber(productId) then
			return itemName, cfg
		end
	end
	return nil, nil
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		warn("[ProcessReceiptHandler] Player not found yet for PlayerId:", receiptInfo.PlayerId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local itemName, cfg = findItemByDevProductId(receiptInfo.ProductId)
	if not itemName or not cfg then
		warn("[ProcessReceiptHandler] No ShopConfig match for ProductId:", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if (cfg :: any).Enabled == false then
		warn("[ProcessReceiptHandler] Item disabled for ProductId:", receiptInfo.ProductId, "item=", itemName)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if cfg.ItemKind ~= "npc" then
		warn("[ProcessReceiptHandler] Unsupported ItemKind for productId:", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local npcModelName = (cfg :: any).NpcModelName
	local unitKind = cfg.UnitKind
	local unitClass = cfg.UnitClass

	local ok = GridCellSpawnService.TrySpawnShopItemOnCurrentCell(player, itemName)
	if not ok then
		-- Fallback: never block a Robux grant.
		if type(npcModelName) == "string" and npcModelName ~= "" then
			NpcSpawnService.SpawnUnitNearPlayer(player, npcModelName)
		elseif type(unitKind) == "string" and unitKind ~= "" and type(unitClass) == "string" and unitClass ~= "" then
			NpcSpawnService.SpawnUnitNearPlayer(player, unitKind, unitClass)
		else
			warn("[ProcessReceiptHandler] Invalid NPC config for item:", itemName)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	print(string.format(
		"[ProcessReceiptHandler] SOLD for ROBUX player=%s productId=%d item=%s NpcModelName=%s UnitKind=%s UnitClass=%s",
		player.Name,
		tonumber(receiptInfo.ProductId) or -1,
		itemName,
		tostring(npcModelName),
		unitKind,
		unitClass
	))

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return {}
