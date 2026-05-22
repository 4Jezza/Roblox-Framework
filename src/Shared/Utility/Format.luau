--!strict
--[[
	FORMAT
	------
	General-purpose number and string formatting utilities.

	Import:
	    local Format = require(game.ReplicatedStorage.Utility.Format)
--]]

local suffixes = {"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg", "Uvg", "Dvg", "Tvg", "Qavg", "Qivg", "Sxvg", "Spvg", "Ocvg"}

local Module = {}

--[[
	Returns the possessive form of a given name.
	If the name ends in "s" (case-insensitive), appends just an apostrophe.
	Otherwise, appends `'s`.
]]
function Module.getPossessiveName(name: string): string
	assert(typeof(name) == "string", "getPossessiveName(): name must be a string")

	local lastCharacter = string.sub(name, -1)
	if lastCharacter:lower() == "s" then
		return name .. "'"
	end

	return name .. "'s"
end

-- Calls tostring() on input and removes all special characters (except for underscores).
function Module.getAttributeSafeString(input: any): string
	return tostring(input):gsub("[^%w_]", "")
end

-- Formats a number into float with a suffix (if applicable).
-- <strong>precision</strong>: Default is 1 decimal place.
function Module.abbreviateNumber(x: number, precision: number?)
	local precision = precision or 1

	if x < 1000 then
		return tostring(x)
	end

	local suffixIndex = math.floor(math.log10(x) / 3)
	local suffix = suffixes[suffixIndex]

	if not suffix then
		return tostring(x)
	end

	local divisor = 10 ^ (suffixIndex * 3)
	local shortValue = x / divisor

	local multiplier = 10 ^ precision
	local roundedValue = math.floor(shortValue * multiplier + 0.5) / multiplier

	-- If rounding pushes the value to 1000, switch to next suffix
	if roundedValue >= 1000 and suffixes[suffixIndex + 1] then
		suffixIndex += 1
		suffix = suffixes[suffixIndex]
		divisor = 10 ^ (suffixIndex * 3)
		roundedValue = math.floor((x / divisor) * multiplier + 0.5) / multiplier
	end

	local formatted = string.format(`%.{precision}f`, roundedValue)
	formatted = formatted:gsub("%.?0+$", "")

	return `{formatted}{suffix}`
end

function Module.removeRichTextTags(input: string): string
	return input:gsub("<[^<>]->", "")
end

-- Formats a number into abbreviated cash form with a suffix (if applicable).
-- <strong>precision</strong>: Default is 1 decimal place.
function Module.abbreviateCash(x: number, precision: number?)
	local precision = precision or 1

	if x < 1000 then
		return Module.formatCash(x)
	end

	local suffixIndex = math.floor(math.log10(x) / 3)
	local suffix = suffixes[suffixIndex]

	if not suffix then
		return Module.formatCash(x)
	end

	local divisor = 10 ^ (suffixIndex * 3)
	local shortValue = x / divisor

	local multiplier = 10 ^ precision
	local roundedValue = math.floor(shortValue * multiplier + 0.5) / multiplier

	-- If rounding pushes the value to 1000, switch to next suffix
	if roundedValue >= 1000 and suffixes[suffixIndex + 1] then
		suffixIndex += 1
		suffix = suffixes[suffixIndex]
		divisor = 10 ^ (suffixIndex * 3)
		roundedValue = math.floor((x / divisor) * multiplier + 0.5) / multiplier
	end

	local formatted = string.format(`%.{precision}f`, roundedValue)
	formatted = formatted:gsub("%.?0+$", "")

	return `{formatted}{suffix}`
end

-- Removes all rich text tags from the string, including replacing `\n` breaks
-- with their rich text counterpart.
function Module.removeTags(str: string): string
	str = str:gsub("<br%s*/>", "\n")
	return (str:gsub("<[^<>]->", ""))
end

--[[
	Formats a number into a 'cash' format.
	100     -> "100"
	0.011   -> "0.01"
	1000.15 -> "1,000.15"
]]
function Module.formatCash(amount: number): string
	assert(typeof(amount) == "number", "FormatCash expects a number")
	local roundedAmount = math.floor(amount * 100 + 0.5) / 100

	local formattedString = string.format("%.2f", roundedAmount)

	local isNegative = false
	if formattedString:sub(1, 1) == "-" then
		isNegative = true
		formattedString = formattedString:sub(2)
	end

	local integerPart, fractionalPart =
		formattedString:match("^(%d+)(%.%d%d)$")

	if not integerPart or not fractionalPart then
		error(`FormatCash failed to parse '{formattedString}'`, 2)
	end

	local integerNumber = tonumber(integerPart)
	if not integerNumber then
		error(`FormatCash invalid integer '{integerPart}'`, 2)
	end

	local withCommas = Module.formatWithCommas(integerNumber)
	local result = (isNegative and "-" or "") .. withCommas

	if fractionalPart ~= ".00" then
		result = result .. fractionalPart
	end

	return result
end

-- Formats any number to include commas (if applicable).
function Module.formatWithCommas(num: number): string
	local negative = false
	if num < 0 then
		negative = true
		num = -num
	end

	local str = tostring(num)
	local integer, fractional = str:match("^(%d+)(%.%d+)$")
	if not integer then
		integer = str
		fractional = ""
	end

	local reversed = (integer :: string):reverse()
	local parts = {}
	for i = 1, #reversed, 3 do
		parts[#parts + 1] = reversed:sub(i, i + 2)
	end

	local withCommas = table.concat(parts, ","):reverse()
	if negative then
		withCommas = `-{withCommas}`
	end

	return `{withCommas}{fractional}`
end

-- Formats the duration in seconds to a time string.
-- Example: 125 -> "2:05", 3605 -> "1:00:05"
-- <strong>minUnit</strong>: Default is "minutes"
function Module.formatTime(seconds: number, minUnit: ("hours" | "minutes" | "seconds")?): string
	assert(typeof(seconds) == "number", "formatTime expects a number")
	local precision = minUnit or "minutes"

	local totalSeconds = math.floor(seconds)
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local secs = totalSeconds % 60

	local parts = {}

	if precision == "hours" or hours > 0 then
		table.insert(parts, string.format("%02d", hours))
		table.insert(parts, string.format("%02d", minutes))
		table.insert(parts, string.format("%02d", secs))
	elseif precision == "minutes" or minutes > 0 then
		table.insert(parts, tostring(minutes))
		table.insert(parts, string.format("%02d", secs))
	else
		table.insert(parts, tostring(secs))
	end

	return table.concat(parts, ":")
end

--[[
	Formats the duration in seconds to a time string including milliseconds.
	Example: 125.3559 -> "2:05.356", 3605.15 -> "1:00:05.150"
	<strong>precision</strong>: Decimal places (0-3).
	<strong>minUnit</strong>: Default is "minutes"
]]
function Module.formatTimeWithMilliseconds(timeInSeconds: number, precision: number, minUnit: ("hours" | "minutes" | "seconds")?): string
	assert(typeof(timeInSeconds) == "number", "Expected number for timeInSeconds")
	assert(typeof(precision) == "number" and precision >= 0 and precision <= 3, "Precision must be between 0 and 3")

	local base = Module.formatTime(timeInSeconds, minUnit)

	if precision == 0 then
		return base
	end

	local factor = 10 ^ precision
	local fraction = timeInSeconds % 1
	local fractionalRounded = math.floor(fraction * factor + 0.5)
	return base .. string.format(`.%0{precision}d`, fractionalRounded)
end

-- Attempts to convert a string to PascalCase.
-- Examples: "HELLOTHERE" -> "Hellothere", "hello_there" -> "HelloThere"
function Module.toPascalCase(input: string): string
	local parts = {}
	for word in string.gmatch(input, "[A-Za-z0-9]+") do
		local firstChar = string.sub(word, 1, 1)
		local rest = string.sub(word, 2)
		local capitalized = string.upper(firstChar) .. string.lower(rest)
		table.insert(parts, capitalized)
	end
	return table.concat(parts)
end

-- Returns the ordinal string for a number. Accounts for 11–13.
-- Examples: 1 -> "1st", 11 -> "11th", 22 -> "22nd"
function Module.getOrdinalString(input: number): string
	local suffix = "th"
	if input % 100 < 11 or input % 100 > 13 then
		local lastDigit = input % 10
		if lastDigit == 1 then
			suffix = "st"
		elseif lastDigit == 2 then
			suffix = "nd"
		elseif lastDigit == 3 then
			suffix = "rd"
		end
	end
	return tostring(input) .. suffix
end

-- Adds a space before every uppercase letter.
-- Input: "HelloWorld" -> "Hello World"
function Module.addSpaceBeforeUpperCase(input: string): string
	return input:gsub("(%u)", " %1"):gsub("^ ", "")
end

-- Splits a string by uppercase letters into a table of words.
function Module.splitByUppercase(input: string): { string }
	local result = {}
	for word in input:gmatch("[A-Z][^A-Z]*") do
		table.insert(result, word)
	end
	return result
end

-- Formats a number as a cash display string: "$89.3B"
function Module.cash(amount: number): string
	return "$" .. Module.abbreviateCash(amount)
end

-- Formats a plain number with suffix, no currency symbol: "89.3B"
function Module.number(amount: number): string
	return Module.abbreviateNumber(amount)
end

-- ---------------------------------------------------------------------------
-- Client-visible number API
-- ---------------------------------------------------------------------------
-- MANDATORY for all client-visible numeric output (see architecture.md
-- § Client-visible numbers). Raw tostring(n) for client display is forbidden.

-- Ordered suffix table capped at Qi (1e18). Values are thresholds.
local _suffixThresholds: { { suffix: string, value: number } } = {
	{ suffix = "Qi", value = 1e18 },
	{ suffix = "Qa", value = 1e15 },
	{ suffix = "T",  value = 1e12 },
	{ suffix = "B",  value = 1e9  },
	{ suffix = "M",  value = 1e6  },
	{ suffix = "K",  value = 1e3  },
}

--[[
	Format.Suffix(n, decimals?) -> string
	DEFAULT for client-visible numbers.
	Returns compact suffix form: "40K", "1.5M", "1.2B", "1.5T", "500Qa", "1.5Qi".
	  • decimals defaults to 1.
	  • Trailing ".0" is trimmed ("1.0M" -> "1M").
	  • Numbers below 1 000 return an integer string.
	  • Negative prefix preserved.
	  • n >= 1e21 (past Qi range) returns Qi form of n.
	  • n == 0 returns "0".

	Usage:
	    Format.Suffix(1500)      -- "1.5K"
	    Format.Suffix(1500000)   -- "1.5M"
	    Format.Suffix(1200, 0)   -- "1K"
	    Format.Suffix(-40000)    -- "-40K"
]]
function Module.Suffix(n: number, decimals: number?): string
	local dec = decimals or 1

	if n == 0 then return "0" end

	local negative = n < 0
	local abs = math.abs(n)

	if abs < 1000 then
		return (negative and "-" or "") .. tostring(math.floor(abs))
	end

	-- Find the largest threshold that fits.
	local chosenSuffix = "K"
	local chosenValue  = 1e3
	for _, entry in _suffixThresholds do
		if abs >= entry.value then
			chosenSuffix = entry.suffix
			chosenValue  = entry.value
			break
		end
	end

	local raw = abs / chosenValue
	local mult = 10 ^ dec
	local rounded = math.floor(raw * mult + 0.5) / mult

	-- Format with requested decimal places then strip trailing ".0" pattern.
	local formatted = string.format("%." .. tostring(dec) .. "f", rounded)
	formatted = formatted:gsub("%.?0+$", "")

	return (negative and "-" or "") .. formatted .. chosenSuffix
end

--[[
	Format.Commas(n) -> string
	Returns n formatted with thousands commas.
	Delegates to the existing formatWithCommas which already handles negatives
	and decimals correctly.

	Usage:
	    Format.Commas(1500000)  -- "1,500,000"
	    Format.Commas(-3200)    -- "-3,200"
	    Format.Commas(99.5)     -- "99.5"
]]
function Module.Commas(n: number): string
	return Module.formatWithCommas(n)
end

--[[
	Format.Number(n, mode?) -> string
	Convenience wrapper. mode defaults to "suffix".
	  "suffix" -> Format.Suffix(n)
	  "commas" -> Format.Commas(n)

	Usage:
	    Format.Number(1500000)           -- "1.5M"
	    Format.Number(1500000, "commas") -- "1,500,000"
]]
function Module.Number(n: number, mode: ("suffix" | "commas")?): string
	if mode == "commas" then
		return Module.Commas(n)
	end
	return Module.Suffix(n)
end

return Module
