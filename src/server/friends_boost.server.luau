-- ServerScriptService.friends_boost

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local FriendsBoostService = require(script.Parent.Services.FriendsBoostService)

-- InvitePrompt RemoteEvent lives at ReplicatedStorage.InvitePrompt (as in reference)
local invitePrompt = ReplicatedStorage:FindFirstChild("InvitePrompt")
if not invitePrompt then
	invitePrompt = Instance.new("RemoteEvent")
	invitePrompt.Name = "InvitePrompt"
	invitePrompt.Parent = ReplicatedStorage
end

invitePrompt.OnServerEvent:Connect(function(player)
	local ok, err = pcall(function()
		SocialService:PromptGameInvite(player)
	end)
	if not ok then
		warn("[InvitePrompt] PromptGameInvite failed:", err)
	end
end)

FriendsBoostService.OnStart()

return {}
