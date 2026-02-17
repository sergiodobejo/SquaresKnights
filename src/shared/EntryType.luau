-- ReplicatedStorage.EntryType
-- Pure logic for determining entry type from TeleportData.

export type EntryType = "Solo" | "1v1" | "4 Players" | "Open Arena"

local SOURCE_TO_ENTRY: { [string]: EntryType } = {
	lobby_solo = "Solo",
	lobby_1v1 = "1v1",
	lobby_4p = "4 Players",
}

local function fromTeleportData(teleportData: any): EntryType
	if teleportData == nil then
		return "Open Arena"
	end

	if type(teleportData) ~= "table" then
		return "Open Arena"
	end

	local source = (teleportData :: any).source
	if type(source) ~= "string" then
		return "Open Arena"
	end

	local mapped = SOURCE_TO_ENTRY[source]
	if mapped == nil then
		return "Open Arena"
	end

	return mapped
end

return {
	FromTeleportData = fromTeleportData,
}
