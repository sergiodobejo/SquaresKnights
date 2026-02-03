-- ServerScriptService.Services.CodesService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local CodesConfig = require(ReplicatedStorage.Configs.Codes)

local CodesService = {}

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local RedeemCodeRemote = Remotes:FindFirstChild("RedeemCode")
if not RedeemCodeRemote then
	RedeemCodeRemote = Instance.new("RemoteEvent")
	RedeemCodeRemote.Name = "RedeemCode"
	RedeemCodeRemote.Parent = Remotes
end

local function normalize(input: any): string?
	if typeof(input) ~= "string" then
		return nil
	end
	local s = input:gsub("^%s+", ""):gsub("%s+$", "")
	if #s == 0 then
		return nil
	end
	-- basic abuse guard
	if #s > 64 then
		return nil
	end
	return s
end

local function reply(player: Player, ok: boolean, message: string, amount: number?)
	RedeemCodeRemote:FireClient(player, ok, message, amount)
end

function CodesService.OnStart()
	RedeemCodeRemote.OnServerEvent:Connect(function(player: Player, rawCode: any)
		local code = normalize(rawCode)
		print("[CodesService] Redeem request", player.Name, tostring(rawCode), "->", tostring(code))
		if not code then
			reply(player, false, "Code Invalid")
			return
		end

		local state = PlayerDataService.GetState(player)
		if not state then
			reply(player, false, "Code Invalid")
			return
		end

		local codeObject = CodesConfig.GetCodeObject(code)
		print("[CodesService] Matched codeObject:", codeObject and (codeObject :: any).Code or "nil")
		local isRedeemable = CodesConfig.IsRedeemable(codeObject, state)
		print("[CodesService] IsRedeemable:", isRedeemable)
		if isRedeemable ~= true then
			reply(player, false, tostring(isRedeemable))
			return
		end

		local reward = (codeObject :: any).Reward
		if reward.Type == "Coins" then
			PlayerDataService.AddCoins(player, reward.Amount)
		else
			reply(player, false, "Code Invalid")
			return
		end

		PlayerDataService.MarkCodeRedeemed(player, (codeObject :: any).Code)
		reply(player, true, "Code Redeemed", reward.Amount)
	end)
end

return CodesService
