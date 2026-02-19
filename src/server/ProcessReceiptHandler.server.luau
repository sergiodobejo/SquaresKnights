-- ServerScriptService.ProcessReceiptHandler
-- Grants items after Developer Product purchase

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShopConfig = require(ReplicatedStorage.Configs.ShopConfig)
local RuntimeSettings = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("RuntimeSettings"))
local NpcSpawnService = require(ServerScriptService.Services.NpcSpawnService)
local GridCellSpawnService = require(ServerScriptService.Services.GridCellSpawnService)

local DEBUG_ROBUX = (RuntimeSettings :: any).DebugRobuxReceipts == true

-- Runtime-only idempotency for dev product receipts.
-- Roblox can call ProcessReceipt multiple times for the same PurchaseId.
-- If we spawn twice, the 2nd spawn happens on the cell the player teleported to.
local PROCESSED_TTL_SECONDS = 20 * 60
local processedByPurchaseId: { [string]: number } = {}
local inFlightByPurchaseId: { [string]: boolean } = {}

local function normalizePurchaseId(receiptInfo: any): string?
	local pid = receiptInfo and (receiptInfo :: any).PurchaseId
	if pid == nil then
		return nil
	end
	local s = tostring(pid)
	if s == "" then
		return nil
	end
	return s
end


local function findItemByDevProductId(productId: number)
	for itemName, cfg in pairs(ShopConfig.Config.Items) do
		if type(cfg) == "table" and tonumber(cfg.DevProductId) == tonumber(productId) then
			return itemName, cfg
		end
	end
	return nil, nil
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local purchaseId = normalizePurchaseId(receiptInfo)
	if purchaseId then
		if processedByPurchaseId[purchaseId] ~= nil then
			if DEBUG_ROBUX then
				warn(string.format(
					"[ProcessReceiptHandler] DUPLICATE receipt ignored purchaseId=%s playerId=%s productId=%s",
					purchaseId,
					tostring((receiptInfo :: any).PlayerId),
					tostring((receiptInfo :: any).ProductId)
				))
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if inFlightByPurchaseId[purchaseId] then
			if DEBUG_ROBUX then
				warn(string.format(
					"[ProcessReceiptHandler] IN-FLIGHT receipt delayed purchaseId=%s playerId=%s productId=%s",
					purchaseId,
					tostring((receiptInfo :: any).PlayerId),
					tostring((receiptInfo :: any).ProductId)
				))
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		inFlightByPurchaseId[purchaseId] = true
		if DEBUG_ROBUX then
			print(string.format(
				"[ProcessReceiptHandler] receipt start purchaseId=%s playerId=%s productId=%s",
				purchaseId,
				tostring((receiptInfo :: any).PlayerId),
				tostring((receiptInfo :: any).ProductId)
			))
		end
	end

	local function finish(decision: any, markProcessed: boolean)
		if purchaseId then
			inFlightByPurchaseId[purchaseId] = nil
			if markProcessed then
				processedByPurchaseId[purchaseId] = os.clock()
				task.delay(PROCESSED_TTL_SECONDS, function()
					processedByPurchaseId[purchaseId] = nil
				end)
			end
		end
		return decision
	end

	local decision = Enum.ProductPurchaseDecision.NotProcessedYet
	local markProcessed = false

	local ok, err = xpcall(function()
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			warn("[ProcessReceiptHandler] Player not found yet for PlayerId:", receiptInfo.PlayerId)
			decision = Enum.ProductPurchaseDecision.NotProcessedYet
			return
		end

		local itemName, cfg = findItemByDevProductId(receiptInfo.ProductId)
		if not itemName or not cfg then
			warn("[ProcessReceiptHandler] No ShopConfig match for ProductId:", receiptInfo.ProductId)
			decision = Enum.ProductPurchaseDecision.NotProcessedYet
			return
		end
		if (cfg :: any).Enabled == false then
			warn("[ProcessReceiptHandler] Item disabled for ProductId:", receiptInfo.ProductId, "item=", itemName)
			decision = Enum.ProductPurchaseDecision.NotProcessedYet
			return
		end

		if cfg.ItemKind ~= "npc" then
			warn("[ProcessReceiptHandler] Unsupported ItemKind for productId:", receiptInfo.ProductId)
			decision = Enum.ProductPurchaseDecision.NotProcessedYet
			return
		end

		local npcModelName = (cfg :: any).NpcModelName
		local unitKind = cfg.UnitKind
		local unitClass = cfg.UnitClass
		local unitKindStr = tostring(unitKind)
		local unitClassStr = tostring(unitClass)

		local gridOk, reason, spawnCellKey, teleportToCellKey = GridCellSpawnService.TrySpawnShopItemOnCurrentCell(
			player,
			itemName
		)
		if not gridOk then
			-- Fallback: never block a Robux grant.
			if DEBUG_ROBUX then
				warn(string.format(
					"[ProcessReceiptHandler] grid spawn failed purchaseId=%s item=%s reason=%s spawnCell=%s teleportTo=%s",
					tostring(purchaseId),
					tostring(itemName),
					tostring(reason),
					tostring(spawnCellKey),
					tostring(teleportToCellKey)
				))
			end

			local spawned: Model? = nil
			if type(npcModelName) == "string" and npcModelName ~= "" then
				spawned = NpcSpawnService.SpawnUnitNearPlayer(player, npcModelName)
			elseif type(unitKind) == "string" and unitKind ~= "" and type(unitClass) == "string" and unitClass ~= "" then
				spawned = NpcSpawnService.SpawnUnitNearPlayer(player, unitKind, unitClass)
			else
				warn("[ProcessReceiptHandler] Invalid NPC config for item:", itemName)
				decision = Enum.ProductPurchaseDecision.NotProcessedYet
				return
			end

			if not spawned then
				warn("[ProcessReceiptHandler] Fallback spawn failed; will retry receipt item=", itemName)
				decision = Enum.ProductPurchaseDecision.NotProcessedYet
				return
			end
		else
			if DEBUG_ROBUX then
				print(string.format(
					"[ProcessReceiptHandler] grid spawn ok purchaseId=%s item=%s spawnCell=%s teleportTo=%s",
					tostring(purchaseId),
					tostring(itemName),
					tostring(spawnCellKey),
					tostring(teleportToCellKey)
				))
			end
		end

		print(string.format(
			"[ProcessReceiptHandler] SOLD for ROBUX player=%s productId=%d item=%s NpcModelName=%s UnitKind=%s UnitClass=%s",
			player.Name,
			tonumber(receiptInfo.ProductId) or -1,
			itemName,
			tostring(npcModelName),
			unitKindStr,
			unitClassStr
		))

		decision = Enum.ProductPurchaseDecision.PurchaseGranted
		markProcessed = true
	end, debug.traceback)

	if not ok then
		warn("[ProcessReceiptHandler] ERROR in ProcessReceipt:", err)
		decision = Enum.ProductPurchaseDecision.NotProcessedYet
		markProcessed = false
	end

	return finish(decision, markProcessed)
end

return {}
