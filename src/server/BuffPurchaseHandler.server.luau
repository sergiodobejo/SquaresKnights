-- ServerScriptService.BuffPurchaseHandler
-- Handle buff purchases from client

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShopConfig = require(ReplicatedStorage.Configs.ShopConfig)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local NpcSpawnService = require(ServerScriptService.Services.NpcSpawnService)

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local BuyItemRemote = RemotesFolder:WaitForChild("BuyItem")

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

		PlayerDataService.AddCoins(player, -priceCoins)
		local afterCoins = PlayerDataService.GetCoins(player)
		print(string.format(
			"[BuffPurchaseHandler] SOLD for COINS player=%s item=%s price=%d coins:%d->%d",
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

	local npcModelName = (config :: any).NpcModelName
	local unitKind = config.UnitKind
	local unitClass = config.UnitClass

	local npc: Model?
	if type(npcModelName) == "string" and npcModelName ~= "" then
		npc = NpcSpawnService.SpawnUnitNearPlayer(player, npcModelName)
	elseif type(unitKind) == "string" and unitKind ~= "" and type(unitClass) == "string" and unitClass ~= "" then
		npc = NpcSpawnService.SpawnUnitNearPlayer(player, unitKind, unitClass)
	else
		warn("[BuffPurchaseHandler] Invalid NPC config for item:", itemName)
		return
	end
	if npc then
		print(string.format(
			"[BuffPurchaseHandler] NPC SPAWNED player=%s item=%s NpcModelName=%s UnitKind=%s UnitClass=%s",
			player.Name,
			itemName,
			tostring(npcModelName),
			tostring(unitKind),
			tostring(unitClass)
		))
	end
end)

return {}
