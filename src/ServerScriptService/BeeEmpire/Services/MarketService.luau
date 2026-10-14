--[[
	MarketService - the Honey Market's price.

	The market pays GameConfig.JarValue x a price multiplier for every jar. The multiplier is
	the same for everyone in the server. Every GameConfig.SellPriceSeconds it jumps to a new
	random number, picked from GameConfig.SellPriceBands.

	The server picks the price and uses its own number when a player sells, so a player's
	device can never choose what it is paid. The price and the time of the next change are
	written on the workspace (attributes SellPrice and SellPriceChangesAt) so every screen
	can show them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)
local PlotService = require(script.Parent.PlotService)

local MarketService = {}

local random = Random.new()
local price = 1

-- A new random price: first a band (by its Chance), then a price inside that band.
local function pickPrice(): number
	local totalChance = 0
	for _, band in GameConfig.SellPriceBands do
		totalChance += band.Chance
	end
	local pick = random:NextNumber() * totalChance
	for _, band in GameConfig.SellPriceBands do
		pick -= band.Chance
		if pick <= 0 then
			local step = math.max(GameConfig.SellPriceStep, 0.01)
			local steps = math.max(0, math.floor((band.Max - band.Min) / step + 0.5))
			local picked = band.Min + random:NextInteger(0, steps) * step
			return math.max(0.01, math.floor(picked * 100 + 0.5) / 100)
		end
	end
	return 1
end

-- The price multiplier right now (2.4 means every jar pays 2.4 times GameConfig.JarValue).
function MarketService.Price(): number
	return price
end

-- How many Honey Coins this many jars are worth at the price right now.
function MarketService.Worth(jars: number): number
	return math.floor(jars * GameConfig.JarValue * price + 0.5)
end

-- The line under "Honey Market" on a market's sign.
function MarketService.SignText(): string
	return "Each jar = " .. string.format("%g", GameConfig.JarValue * price) .. " Honey Coins"
end

-- Tells every screen the price and when it changes, and rewrites the market signs.
local function publish(changesAt: number)
	workspace:SetAttribute("SellPrice", price)
	workspace:SetAttribute("SellPriceChangesAt", changesAt)
	for _, plot in PlotService.GetAllPlots() do
		local market = plot:FindFirstChild("Market")
		local counter = market and market:FindFirstChild("Counter")
		local info = counter and counter:FindFirstChild("Info")
		local sub = info and info:FindFirstChild("Sub")
		if sub and sub:IsA("TextLabel") then
			sub.Text = MarketService.SignText()
		end
	end
end

local function newPrice()
	-- (try a few times for a number different from the last one, so every change can be seen)
	local previous = price
	for _ = 1, 5 do
		price = pickPrice()
		if price ~= previous then
			break
		end
	end
	publish(workspace:GetServerTimeNow() + GameConfig.SellPriceSeconds)
end

function MarketService.Init()
	newPrice()
	task.spawn(function()
		while true do
			task.wait(GameConfig.SellPriceSeconds)
			newPrice()
		end
	end)
end

return MarketService
