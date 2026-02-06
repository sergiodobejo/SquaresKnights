-- ReplicatedStorage.Configs.TeamColors
-- Shared mapping from team color name -> Color3.

local Shared = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local LIGHT_LERP_ALPHA = 0.18
local DARK_LERP_ALPHA = 0.18

Shared.ByName = {
	red = Color3.fromRGB(255, 80, 80),
	blue = Color3.fromRGB(95, 170, 255),
	yellow = Color3.fromRGB(255, 220, 75),
	black = Color3.fromRGB(50, 50, 50),
	white = Color3.fromRGB(255, 255, 255),
	tan = Color3.fromRGB(220, 120, 40),
	purple = Color3.fromRGB(190, 125, 255),
	pink = Color3.fromRGB(255, 140, 200),
	green = Color3.fromRGB(120, 235, 120),
	brown = Color3.fromRGB(200, 150, 110),
}

function Shared.GetColor3(colorName: any): Color3
	if type(colorName) == "string" then
		local c = Shared.ByName[colorName:lower()]
		if c then
			return c
		end
	end
	return Color3.fromRGB(255, 255, 255)
end

function Shared.GetLighterColor3(baseColor: Color3): Color3
	return baseColor:Lerp(WHITE, LIGHT_LERP_ALPHA)
end

function Shared.GetDarkerColor3(baseColor: Color3): Color3
	return baseColor:Lerp(BLACK, DARK_LERP_ALPHA)
end

function Shared.GetCheckerboardVariantColor3(baseColor: Color3, ix: number, iz: number): Color3
	if ((ix + iz) % 2) == 0 then
		return Shared.GetLighterColor3(baseColor)
	end
	return Shared.GetDarkerColor3(baseColor)
end

function Shared.GetCheckerboardColor3(colorName: any, ix: number, iz: number): Color3
	return Shared.GetCheckerboardVariantColor3(Shared.GetColor3(colorName), ix, iz)
end

return Shared
