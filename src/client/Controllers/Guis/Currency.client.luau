-- PATH: StarterPlayer.StarterPlayerScripts.Controllers.Guis.Currency

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer

local GuiController = require(script.Parent.Parent.GuiController)

local FormatNumber
pcall(function()
	FormatNumber = require(ReplicatedStorage.Libs.FormatNumber.Simple)
end)

local Gui = GuiController.Guis.Right
local Frame = Gui.Frame.Currency
local Coins = Frame.Coins
local CoinsAmount = Coins:WaitForChild("Amount")

local function format(n: number)
	if FormatNumber and FormatNumber.Format then
		return FormatNumber.Format(n)
	end
	return tostring(n)
end

local function bindCoins()
	local leaderstats = Player:WaitForChild("leaderstats")
	local coins = leaderstats:WaitForChild("Coins")

	local function update()
		CoinsAmount.Text = format(coins.Value)
	end

	update()
	coins.Changed:Connect(update)
end

bindCoins()

return {}
