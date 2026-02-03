-- Plain config table.
--
-- Team texture IDs by color.
-- Fill these with your current TextureId asset ids.
-- You can use either:
--  - "1234567890"
--  - "rbxassetid://1234567890"
--
-- Extend freely:
--  - Add more colors: green, yellow, etc.
--  - Add more texture targets: Flags, UI, Weapons, etc.

export type TextureTargets = {
	Units: string,
	Buildings: string,
	-- Future: [string]: string
}

export type TeamTexturesConfig = {
	[string]: TextureTargets,
}

local Config: TeamTexturesConfig = {
	red = {
		Units = "rbxassetid://79290944930741",
		Buildings = "rbxassetid://88911021689479",
	},
	blue = {
		Units = "rbxassetid://125268091219835",
		Buildings = "rbxassetid://72552478636240",
	},
	yellow = {
		Units = "rbxassetid://118879531072075",
		Buildings = "rbxassetid://125847199402260",
	},
	black = {
		Units = "rbxassetid://129278851714409",
		Buildings = "rbxassetid://134856081282930",
	},
	white = {
		Units = "rbxassetid://71736267041193",
		Buildings = "rbxassetid://124465429929295",
	},
	tan = {
		Units = "rbxassetid://138010259278187",
		Buildings = "rbxassetid://93052334713870",
	},
	purple = {
		Units = "rbxassetid://83771372141876",
		Buildings = "rbxassetid://79874210701536",
	},
	pink = {
		Units = "rbxassetid://139924175386475",
		Buildings = "rbxassetid://92523089729131",
	},
	green = {
		Units = "rbxassetid://97560399201218",
		Buildings = "rbxassetid://88661415638973",
	},
	brown = {
		Units = "rbxassetid://92947597891051",
		Buildings = "rbxassetid://118216520901241",
	},
}

return Config
