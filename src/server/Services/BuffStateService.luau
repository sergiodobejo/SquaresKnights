-- ServerScriptService.Services.BuffStateService
-- Manages buff state in memory

local BuffStateService = {}

-- RAM: [player] = { [effectName] = { expire1, expire2, ... } }
local ActiveBuffs = {}

local function cleanupExpired(player, effectName)
	local buffs = ActiveBuffs[player]
	if not buffs then return end

	local list = buffs[effectName]
	if not list then return end

	local now = os.time()
	local newList = {}

	for _, exp in ipairs(list) do
		if exp > now then
			table.insert(newList, exp)
		end
	end

	if #newList > 0 then
		buffs[effectName] = newList
	else
		buffs[effectName] = nil
	end
end

function BuffStateService.AddBuff(player, effectName, duration)
	local now = os.time()
	local expire = now + duration

	ActiveBuffs[player] = ActiveBuffs[player] or {}
	ActiveBuffs[player][effectName] = ActiveBuffs[player][effectName] or {}
	table.insert(ActiveBuffs[player][effectName], expire)

	print("[BuffStateService] Added buff", effectName, "to", player.Name, "expires at", expire)
end

function BuffStateService.HasBuff(player, effectName)
	ActiveBuffs[player] = ActiveBuffs[player] or {}
	cleanupExpired(player, effectName)

	local list = ActiveBuffs[player][effectName]
	return list ~= nil and #list > 0
end

function BuffStateService.GetBuffList(player, effectName)
	local buffs = ActiveBuffs[player]
	if not buffs then return nil end
	return buffs[effectName]
end

function BuffStateService.GetAllBuffs(player)
	return ActiveBuffs[player]
end

function BuffStateService.GetRemaining(player, effectName)
	ActiveBuffs[player] = ActiveBuffs[player] or {}
	cleanupExpired(player, effectName)

	local list = ActiveBuffs[player][effectName]
	if not list then
		return 0
	end

	local now = os.time()
	local best = 0
	for _, exp in ipairs(list) do
		local remaining = exp - now
		if remaining > best then
			best = remaining
		end
	end

	if best < 0 then
		best = 0
	end
	return best
end

function BuffStateService.GetActiveRemainingAll(player)
	local buffs = ActiveBuffs[player]
	if not buffs then
		return {}
	end

	local out = {}
	for effectName in pairs(buffs) do
		local remaining = BuffStateService.GetRemaining(player, effectName)
		if remaining > 0 then
			out[effectName] = remaining
		end
	end
	return out
end

function BuffStateService.LoadFromState(player, stateBuffs)
	if type(stateBuffs) ~= "table" then
		return
	end

	ActiveBuffs[player] = ActiveBuffs[player] or {}

	for effectName, list in pairs(stateBuffs) do
		if type(effectName) == "string" and type(list) == "table" then
			ActiveBuffs[player][effectName] = {}
			for _, exp in ipairs(list) do
				if type(exp) == "number" then
					table.insert(ActiveBuffs[player][effectName], exp)
				end
			end
			cleanupExpired(player, effectName)
		end
	end
end

function BuffStateService.ExportForSave(player)
	local buffs = ActiveBuffs[player]
	if not buffs then
		return {}
	end

	local out = {}
	for effectName, list in pairs(buffs) do
		cleanupExpired(player, effectName)
		local cleaned = buffs[effectName]
		if type(cleaned) == "table" and #cleaned > 0 then
			out[effectName] = {}
			for _, exp in ipairs(cleaned) do
				table.insert(out[effectName], exp)
			end
		end
	end

	return out
end

function BuffStateService.ClearPlayer(player)
	ActiveBuffs[player] = nil
end

return BuffStateService
