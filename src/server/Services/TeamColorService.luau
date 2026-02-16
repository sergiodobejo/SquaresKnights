local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local TeamTextures = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("TeamTextures"))

local Shared = {}

Shared.Attributes = {
	TeamColor = "TeamColor",
}

local RESERVED_FOR_AI_COLOR = "blue"

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

local rng = Random.new()

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

local function assignColorInternal(player: Player): string
	local existing = assignedByUserId[player.UserId]
	if existing then
		return existing
	end

	local chosen: string
	if #availableColors > 0 then
		local idx = rng:NextInteger(1, #availableColors)
		chosen = table.remove(availableColors, idx) :: string
	else
		-- Should not happen in your constraints (players <= colors).
		local fallback: { string } = {}
		for _, name in ipairs(ALL_COLORS) do
			if isPlayerAssignableColor(name) then
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

function Shared.AssignPlayer(player: Player): string
	local colorName = assignColorInternal(player)
	local teamId = COLOR_TO_TEAM_ID[colorName]

	player:SetAttribute(Shared.Attributes.TeamColor, colorName)
	if teamId then
		player:SetAttribute(Affiliation.Attributes.TeamId, teamId)
	end

	return colorName
end

function Shared.ReleasePlayer(player: Player)
	local userId = player.UserId
	local colorName = assignedByUserId[userId]
	if not colorName then
		return
	end

	assignedByUserId[userId] = nil
	if isPlayerAssignableColor(colorName) then
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
