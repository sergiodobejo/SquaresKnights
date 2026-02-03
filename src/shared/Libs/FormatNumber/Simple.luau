-- PATH: ReplicatedStorage.Libs.FormatNumber.Simple
-- Minimal number formatting helpers used by UI.

local Simple = {}

local SUFFIXES = {
	{ value = 1e12, suffix = "T" },
	{ value = 1e9, suffix = "B" },
	{ value = 1e6, suffix = "M" },
	{ value = 1e3, suffix = "K" },
}

local function trimTrailingZeros(s: string): string
	-- turns "1.0" -> "1" and "1.20" -> "1.2"
	s = string.gsub(s, "(%d)0+$", "%1")
	s = string.gsub(s, "%.%s*$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

function Simple.FormatCompact(value: any): string
	local n = tonumber(value)
	if not n then
		return tostring(value)
	end

	local sign = ""
	if n < 0 then
		sign = "-"
		n = -n
	end

	for _, entry in ipairs(SUFFIXES) do
		if n >= entry.value then
			local scaled = n / entry.value
			local formatted = string.format("%.1f", scaled)
			formatted = trimTrailingZeros(formatted)
			return sign .. formatted .. entry.suffix
		end
	end

	return sign .. tostring(math.floor(n + 0.5))
end

return Simple
