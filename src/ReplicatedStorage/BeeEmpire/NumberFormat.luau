--[[
	NumberFormat - turns big numbers into short, readable text.
	1500 -> "1.5K", 2000000 -> "2M"
]]

local NumberFormat = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

function NumberFormat.Short(value: number): string
	local amount = math.floor(value)
	if amount < 1000 then
		return tostring(amount)
	end

	local index = 1
	local scaled = amount
	while scaled >= 1000 and index < #SUFFIXES do
		scaled /= 1000
		index += 1
	end

	-- Round down to one decimal so we never show more than the player really has.
	local text = string.format("%.1f", math.floor(scaled * 10) / 10)
	text = string.gsub(text, "%.0$", "")
	return text .. SUFFIXES[index]
end

-- A chance as a percentage, as short as it can honestly be: "90%", "59.9%", "0.14%", "0.005%".
function NumberFormat.Percent(value: number): string
	if value <= 0 then
		return "0%"
	end
	local text = if value >= 1 then string.format("%.1f", value) elseif value >= 0.01 then string.format("%.3f", value) else string.format("%.4f", value)
	if text:find(".", 1, true) then
		text = (text:gsub("0+$", "")) -- (zeros after the point say nothing)
		text = (text:gsub("%.$", ""))
	end
	return text .. "%"
end

return NumberFormat
