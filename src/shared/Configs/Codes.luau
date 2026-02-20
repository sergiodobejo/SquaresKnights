-- PATH: ReplicatedStorage.Configs.Codes
-- PURPOSE: Redeemable promo codes config + helpers

export type CodeReward = {
	Type: "Coins",
	Amount: number,
}

export type CodeObject = {
	Code: string,
	Expiration: number,
	Reward: CodeReward,
}

local Config: { CodeObject } = {
	{
		Code = "Sprun8sW26",
		Expiration = 1767909263,
		Reward = {
			Type = "Coins",
			Amount = 500,
		},
	},
	{
		Code = "NewYSpru2026",
		Expiration = 1767302582,
		Reward = {
			Type = "Coins",
			Amount = 550,
		},
	},
	{
		Code = "YSpru2025XMas",
		Expiration = 1767045437,
		Reward = {
			Type = "Coins",
			Amount = 350,
		},
	},
	{
		Code = "2SprunkPuRz",
		Expiration = 1766698610,
		Reward = {
			Type = "Coins",
			Amount = 450,
		},
	},
	{
		Code = "TotSprunkLWQ",
		Expiration = 1766178622,
		Reward = {
			Type = "Coins",
			Amount = 350,
		},
	},
	{
		Code = "PoWSprunkMlK",
		Expiration = 1765749556,
		Reward = {
			Type = "Coins",
			Amount = 400,
		},
	},
	{
		Code = "ZqTSprunkP01",
		Expiration = 1765313431,
		Reward = {
			Type = "Coins",
			Amount = 500,
		},
	},
	{
		Code = "XTRush300L",
		Expiration = 1764619857,
		Reward = {
			Type = "Coins",
			Amount = 300,
		},
	},
	{
		Code = "GKRush500T",
		Expiration = 1764706257,
		Reward = {
			Type = "Coins",
			Amount = 500,
		},
	},
	{
		Code = "MpY800PFdBNm",
		Expiration = 1764792657,
		Reward = {
			Type = "Coins",
			Amount = 800,
		},
	},
	{
		Code = "MpYILuvSprunk",
		Expiration = 1765041597,
		Reward = {
			Type = "Coins",
			Amount = 300,
		},
	},
}

local ByLowerCode: { [string]: CodeObject } = {}
for _, codeObject in ipairs(Config) do
	ByLowerCode[codeObject.Code:lower()] = codeObject
end

local Shared = {}

Shared.Config = Config

function Shared.GetCodeObject(code: string): CodeObject?
	return ByLowerCode[code:lower()]
end

function Shared.IsExpired(codeObject: CodeObject): boolean
	return os.time() > codeObject.Expiration
end

export type RedeemState = {
	codes: { [string]: boolean }?,
}

function Shared.IsRedeemed(codeObject: CodeObject, state: RedeemState): boolean
	if type(state) ~= "table" then
		return false
	end
	if type(state.codes) ~= "table" then
		return false
	end
	return state.codes[codeObject.Code] == true
end

function Shared.IsRedeemable(codeObject: CodeObject?, state: RedeemState)
	if not codeObject then
		return "CodeInvalid"
	end

	local isExpired = Shared.IsExpired(codeObject)
	if isExpired then
		return "CodeExpired"
	end

	local isRedeemed = Shared.IsRedeemed(codeObject, state)
	if isRedeemed then
		return "CodeAlreadyRedeemed"
	end

	return true
end

return Shared
