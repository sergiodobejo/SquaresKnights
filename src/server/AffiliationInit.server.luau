-- ServerScriptService.AffiliationInit

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Affiliation = require(ReplicatedStorage:WaitForChild("Affiliation"))
local TeamColorService = require(script.Parent:WaitForChild("Services"):WaitForChild("TeamColorService"))

local function onPlayerAdded(player: Player)
	TeamColorService.AssignPlayer(player)
	Affiliation.StampPlayer(player)
	player.CharacterAdded:Connect(function(character)
		Affiliation.StampCharacter(player, character)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	task.defer(onPlayerAdded, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

return {}
