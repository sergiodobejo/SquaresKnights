-- StarterPlayer.StarterPlayerScripts.Controllers.GuiStrings
-- Reads UI strings from StarterGui/Strings (StringValue instances).

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local GuiStrings = {}

local cachedFolder: Instance? = nil
local cache: { [string]: StringValue } = {}
local warnedMissing: { [string]: boolean } = {}

local function resolveFolder(): Instance?
	if cachedFolder and cachedFolder.Parent ~= nil then
		return cachedFolder
	end

	local player = Players.LocalPlayer
	if player then
		local playerGui = player:FindFirstChild("PlayerGui")
		if playerGui then
			local f = playerGui:FindFirstChild("Strings")
			if f then
				cachedFolder = f
				return f
			end
		end
	end

	local f = StarterGui:FindFirstChild("Strings")
	cachedFolder = f
	return f
end

local function getStringValue(key: string): StringValue?
	if cache[key] and cache[key].Parent ~= nil then
		return cache[key]
	end

	local folder = resolveFolder()
	if not folder then
		return nil
	end

	local inst = folder:FindFirstChild(key)
	if inst and inst:IsA("StringValue") then
		cache[key] = inst
		return inst
	end
	return nil
end

function GuiStrings.get(key: string, default: string?): string
	local sv = getStringValue(key)
	if sv then
		return sv.Value
	end

	if not warnedMissing[key] then
		warnedMissing[key] = true
		warn(string.format("[GuiStrings] Missing StarterGui/Strings/%s", key))
	end

	return default or key
end

function GuiStrings.format(key: string, default: string?, ...: any): string
	local template = GuiStrings.get(key, default)
	local ok, formatted = pcall(string.format, template, ...)
	if ok then
		return formatted
	end
	return template
end

return GuiStrings
