local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local TeamTextures = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("TeamTextures"))

local Shared = {}

Shared.Attributes = {
	TeamColor = "TeamColor",
}

local RESERVED_FOR_AI_COLOR = "blue"

-- Some color pairs are too visually similar and should never appear together
-- in the same server/map.
local MUTUALLY_EXCLUSIVE: { [string]: { [string]: boolean } } = {
	brown = { tan = true },
	tan = { brown = true },
	pink = { purple = true },
	purple = { pink = true },
}

local function isPlayerAssignableColor(colorName: any): boolean
	return type(colorName) == "string" and colorName ~= "" and colorName:lower() ~= RESERVED_FOR_AI_COLOR
end

local function collectColorNames(): { string }
	local names = {}
	for colorName in pairs(TeamTextures) do
		if type(colorName) == "string" then
			table.insert(names, colorName)
		end
	end

	-- NOTE: "blue" is reserved for AI NPCs; remove from available player colors
	local preferredOrder = { "red", "yellow", "black", "white", "tan", "purple", "pink", "green", "brown" }
	local preferredSet = {}
	for _, name in ipairs(preferredOrder) do
		preferredSet[name] = true
	end

	local ordered = {}
	for _, name in ipairs(preferredOrder) do
		if table.find(names, name) ~= nil then
			table.insert(ordered, name)
		end
	end

	table.sort(names)
	for _, name in ipairs(names) do
		if not preferredSet[name] then
			table.insert(ordered, name)
		end
	end

	return ordered
end

local ALL_COLORS = collectColorNames()
local COLOR_TO_TEAM_ID: { [string]: number } = {}
local TEAM_ID_TO_COLOR_NAME: { [number]: string } = {}
for i, name in ipairs(ALL_COLORS) do
	COLOR_TO_TEAM_ID[name] = i
	TEAM_ID_TO_COLOR_NAME[i] = name
end

local availableColors: { string } = {}
for _, name in ipairs(ALL_COLORS) do
	if isPlayerAssignableColor(name) then
		table.insert(availableColors, name)
	end
end
local assignedByUserId: { [number]: string } = {}
local reservedColorNames: { [string]: boolean } = {}

local rng = Random.new()

local function removeFromAvailable(colorName: string): boolean
	local idx = table.find(availableColors, colorName)
	if idx ~= nil then
		table.remove(availableColors, idx)
		return true
	end
	return false
end

local function getActiveColorSet(): { [string]: boolean }
	local active: { [string]: boolean } = {}
	for _, colorName in pairs(assignedByUserId) do
		if type(colorName) == "string" and colorName ~= "" then
			active[colorName:lower()] = true
		end
	end
	for colorName, isReserved in pairs(reservedColorNames) do
		if isReserved then
			active[tostring(colorName):lower()] = true
		end
	end
	return active
end

local function conflictsWithActive(candidateColorName: string, active: { [string]: boolean }): boolean
	local cand = candidateColorName:lower()
	local exclusions = MUTUALLY_EXCLUSIVE[cand]
	if not exclusions then
		return false
	end
	for other in pairs(exclusions) do
		if active[other] then
			return true
		end
	end
	return false
end

local function takeRandomNonConflictingAvailableColor(): string?
	if #availableColors <= 0 then
		return nil
	end

	local active = getActiveColorSet()
	local candidates: { string } = {}
	for _, name in ipairs(availableColors) do
		if isPlayerAssignableColor(name) and not conflictsWithActive(name, active) then
			table.insert(candidates, name)
		end
	end

	if #candidates <= 0 then
		return nil
	end

	local chosen = candidates[rng:NextInteger(1, #candidates)]
	if not removeFromAvailable(chosen) then
		-- Safety: in case of inconsistent casing.
		removeFromAvailable(chosen:lower())
	end
	return chosen
end

local function stampPlayerAttributes(player: Player, colorName: string)
	local teamId = COLOR_TO_TEAM_ID[colorName]

	player:SetAttribute(Shared.Attributes.TeamColor, colorName)
	if teamId then
		player:SetAttribute(Affiliation.Attributes.TeamId, teamId)
	end
end

function Shared.GetAllColors(): { string }
	return table.clone(ALL_COLORS)
end

function Shared.GetTeamIdForColor(colorName: string): number?
	return COLOR_TO_TEAM_ID[colorName]
end

function Shared.GetColorForTeamId(teamId: any): string?
	if type(teamId) ~= "number" then
		return nil
	end
	local id = math.floor(teamId)
	if id <= 0 then
		return nil
	end
	return TEAM_ID_TO_COLOR_NAME[id]
end

function Shared.GetColorForPlayer(player: Player): string?
	local attr = player:GetAttribute(Shared.Attributes.TeamColor)
	if type(attr) == "string" and attr ~= "" and attr:lower() ~= RESERVED_FOR_AI_COLOR then
		return attr
	end
	return assignedByUserId[player.UserId]
end

-- Marks a color as reserved for system purposes (e.g. Open Arena corner pre-assignment).
-- Reserved colors are removed from the random pool and are not returned to the pool on player leave.
function Shared.ReserveColorName(colorName: any): boolean
	if not isPlayerAssignableColor(colorName) then
		return false
	end
	local name = (colorName :: string):lower()
	reservedColorNames[name] = true
	removeFromAvailable(name)
	return true
end

function Shared.IsColorNameReserved(colorName: any): boolean
	if type(colorName) ~= "string" then
		return false
	end
	return reservedColorNames[colorName:lower()] == true
end

-- Takes and returns a random available player-assignable color name.
-- If none are available, falls back to a random valid color.
function Shared.TakeRandomAvailablePlayerColorName(): string
	local chosen = takeRandomNonConflictingAvailableColor()
	if chosen then
		return chosen
	end

	-- Fallback: if the pool is empty or all remaining colors would conflict, pick a
	-- random valid color that does not conflict with already active colors.
	local active = getActiveColorSet()
	local fallback: { string } = {}
	for _, name in ipairs(ALL_COLORS) do
		if isPlayerAssignableColor(name) and not conflictsWithActive(name, active) then
			table.insert(fallback, name)
		end
	end
	if #fallback > 0 then
		return fallback[rng:NextInteger(1, #fallback)]
	end

	-- Last resort: preserve previous behavior.
	local anyValid: { string } = {}
	for _, name in ipairs(ALL_COLORS) do
		if isPlayerAssignableColor(name) then
			table.insert(anyValid, name)
		end
	end
	if #anyValid > 0 then
		return anyValid[rng:NextInteger(1, #anyValid)]
	end
	return "red"
end

local function assignColorInternal(player: Player): string
	local existing = assignedByUserId[player.UserId]
	if existing then
		return existing
	end

	local chosen = takeRandomNonConflictingAvailableColor()
	if not chosen then
		-- Should not happen in typical constraints (players <= colors), but keep a safe fallback.
		local active = getActiveColorSet()
		local fallback: { string } = {}
		for _, name in ipairs(ALL_COLORS) do
			if isPlayerAssignableColor(name) and not conflictsWithActive(name, active) then
				table.insert(fallback, name)
			end
		end
		if #fallback > 0 then
			chosen = fallback[rng:NextInteger(1, #fallback)]
		else
			chosen = "red"
		end
	end

	assignedByUserId[player.UserId] = chosen
	return chosen
end

-- Assigns a specific color to the player (idempotent).
-- This overrides any previous assignment for that userId.
function Shared.AssignPlayerSpecific(player: Player, colorName: any): string
	local userId = player.UserId
	if type(colorName) ~= "string" or colorName == "" then
		return Shared.AssignPlayer(player)
	end
	local desired = colorName:lower()
	if not isPlayerAssignableColor(desired) then
		return Shared.AssignPlayer(player)
	end

	local existing = assignedByUserId[userId]
	if existing == desired then
		stampPlayerAttributes(player, desired)
		return desired
	end

	-- Release previous choice back to pool unless it's reserved.
	if existing then
		assignedByUserId[userId] = nil
		if isPlayerAssignableColor(existing) and not reservedColorNames[existing:lower()] then
			table.insert(availableColors, existing)
		end
	end

	assignedByUserId[userId] = desired
	removeFromAvailable(desired)
	stampPlayerAttributes(player, desired)
	return desired
end

function Shared.AssignPlayer(player: Player): string
	local colorName = assignColorInternal(player)
	stampPlayerAttributes(player, colorName)

	return colorName
end

function Shared.ReleasePlayer(player: Player)
	local userId = player.UserId
	local colorName = assignedByUserId[userId]
	if not colorName then
		return
	end

	assignedByUserId[userId] = nil
	if isPlayerAssignableColor(colorName) and not reservedColorNames[colorName:lower()] then
		table.insert(availableColors, colorName)
	end

	-- Optional: keep attributes for debugging after leave; Roblox will destroy player anyway.
end

-- Safety: when scripts hot-reload, players may already exist.
for _, player in ipairs(Players:GetPlayers()) do
	task.defer(function()
		Shared.AssignPlayer(player)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	Shared.ReleasePlayer(player)
end)

return Shared
