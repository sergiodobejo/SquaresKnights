-- ServerScriptService.CollisionGroupsInit

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local CollisionGroupsService = require(ServerScriptService.Services:WaitForChild("CollisionGroupsService"))

CollisionGroupsService.Init()

local function applyForPlayer(player: Player)
	local function onCharacter(character: Model)
		CollisionGroupsService.ApplyPlayerCharacter(character)
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.defer(onCharacter, player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	applyForPlayer(player)
end

Players.PlayerAdded:Connect(applyForPlayer)
