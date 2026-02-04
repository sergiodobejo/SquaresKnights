-- ReplicatedStorage.Configs.TeamColors
-- Shared mapping from team color name -> Color3.

local Shared = {}

Shared.ByName = {
	red = Color3.fromRGB(255, 80, 80),
	blue = Color3.fromRGB(95, 170, 255),
	yellow = Color3.fromRGB(255, 220, 75),
	black = Color3.fromRGB(235, 235, 235),
	white = Color3.fromRGB(255, 255, 255),
	tan = Color3.fromRGB(235, 216, 180),
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

return Shared
