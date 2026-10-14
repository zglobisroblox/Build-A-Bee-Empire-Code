--[[
	State - reads the numbers the server shares with this player (coins, jars, bees...).

	The server writes them as attributes on the Player. This module only READS them,
	and tells the UI when something changed so it can redraw.
	It also works out what the player should do next (the hint and the arrow). The hint and
	the arrow are the TUTORIAL: they are only shown until the player has sold honey, bought
	an upgrade and swapped in a better bee, each once (the server keeps count).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("BeeEmpire")
local GameConfig = require(sharedFolder:WaitForChild("GameConfig"))
local NumberFormat = require(sharedFolder:WaitForChild("NumberFormat"))
local Upgrades = require(sharedFolder:WaitForChild("Upgrades"))

local player = Players.LocalPlayer

local State = {}

local changedEvent = Instance.new("BindableEvent")
State.Changed = changedEvent.Event -- fires (at most once per frame) after any value changes

function State.Number(name: string): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

function State.IsLoaded(): boolean
	return player:GetAttribute("DataLoaded") == true
end

-- True while the loading screen (ReplicatedFirst.BeeEmpireLoading) still covers the game.
-- Nothing should pop up or be announced until it has gone.
function State.LoadingScreenUp(): boolean
	return player:GetAttribute("LoadingScreen") == true
end

-- How many bees of each rarity are in the bag, e.g. { Common = 3, Uncommon = 1, Rare = 0 }
function State.Bag(): { [string]: number }
	local bag = {}
	for _, rarityName in GameConfig.BeeOrder do
		bag[rarityName] = State.Number("Bag_" .. rarityName)
	end
	return bag
end

function State.BagTotal(): number
	local total = 0
	for _, count in State.Bag() do
		total += count
	end
	return total
end

-- THE HIVE -----------------------------------------------------------------------

function State.HiveLevel(): number
	return math.max(1, State.Number("HiveLevel"))
end

-- How many bees the hive can hold right now.
function State.Capacity(): number
	return GameConfig.GetHive(State.HiveLevel()).Capacity
end

-- UPGRADES (an id is "Hive", "Luck", "BeeSpeed", "Rolls", "WalkSpeed" or "RollSpeed") -----

function State.UpgradeLevel(id: string): number
	if id == "Hive" then
		return State.HiveLevel()
	end
	return math.max(1, State.Number("Up_" .. id))
end

-- The price of the next level, or nil if it is already at its best.
function State.NextUpgradeCost(id: string): number?
	return Upgrades.NextCost(id, State.UpgradeLevel(id))
end

-- False for an upgrade the player cannot have yet (Roll Speed before Auto Roll is bought).
-- Such an upgrade is not shown in the shop and never counts for the hint.
function State.UpgradeAvailable(id: string): boolean
	return not Upgrades.NeedsAutoRoll(id) or State.AutoRollBought()
end

function State.CanAffordUpgrade(id: string): boolean
	local cost = State.NextUpgradeCost(id)
	return State.UpgradeAvailable(id) and cost ~= nil and State.Number("Coins") >= cost
end

-- True if the player has enough coins for at least one upgrade at the shop.
function State.CanAffordAnyUpgrade(): boolean
	for _, id in GameConfig.UpgradeOrder do
		if State.CanAffordUpgrade(id) then
			return true
		end
	end
	return false
end

-- True if the hint should send the player to the Upgrade Shop: they can pay for an upgrade.
-- Queen's Luck and Walk Speed come in many small steps that start cheap, so while a bigger
-- hive is still on sale they only count when their price is small next to that hive's
-- (GameConfig.EndlessHintShare). That way new players save up for the hive instead of
-- spending every coin on little steps.
function State.UpgradeWorthAVisit(): boolean
	local nextHive = State.NextHive()
	for _, id in GameConfig.UpgradeOrder do
		if State.CanAffordUpgrade(id) then
			local cost = State.NextUpgradeCost(id)
			local smallChange = nextHive == nil or (cost ~= nil and cost <= nextHive.Cost * GameConfig.EndlessHintShare)
			if smallChange or not Upgrades.IsStepped(id) then
				return true
			end
		end
	end
	return false
end

-- The next hive level's settings and its number, or nil if the hive is already the biggest.
function State.NextHive()
	local nextLevel = State.HiveLevel() + 1
	local hive = GameConfig.HiveLevels[nextLevel]
	if hive then
		return hive, nextLevel
	end
	return nil, nil
end

function State.CanUpgradeHive(): boolean
	local nextHive = State.NextHive()
	return nextHive ~= nil and State.Number("Coins") >= nextHive.Cost
end

-- The rarity of the bee in a hive slot, or nil if the slot is empty.
function State.Cell(cellIndex: number): string?
	local value = player:GetAttribute("Cell_" .. cellIndex)
	if typeof(value) == "string" and GameConfig.Bees[value] then
		return value
	end
	return nil
end

function State.EmptyCellCount(): number
	local empty = 0
	for cellIndex = 1, State.Capacity() do
		if not State.Cell(cellIndex) then
			empty += 1
		end
	end
	return empty
end

function State.TotalBees(): number
	return State.BagTotal() + State.Capacity() - State.EmptyCellCount()
end

-- The cheapest bee the honeycomb stand can offer (rolling itself is free).
function State.CheapestBeePrice(): number
	local cheapest = math.huge
	for _, beeName in GameConfig.QueenBees do -- (Limited bees are never on a stand)
		cheapest = math.min(cheapest, GameConfig.Bees[beeName].Price)
	end
	return cheapest
end

-- The bees waiting on your honeycomb stands after a roll:
-- { [stand number] = { Rarity = "Rare", Price = 1200 } }. A stand with nothing on it is left out.
function State.Offers(): { [number]: { Rarity: string, Price: number } }
	local list = {}
	for index = 1, GameConfig.RollStandSpots do
		local rarityName = player:GetAttribute("Offer" .. index)
		if typeof(rarityName) == "string" and GameConfig.Bees[rarityName] then
			list[index] = { Rarity = rarityName, Price = State.Number("OfferPrice" .. index) }
		end
	end
	return list
end

-- AUTO ROLL (bought once at the sign next to the Queen) -------------------------------

function State.AutoRollBought(): boolean
	return player:GetAttribute("AutoRoll") == true
end

function State.AutoRollOn(): boolean
	return State.AutoRollBought() and player:GetAttribute("AutoRollOn") == true
end

-- The kind of bee Auto Roll is waiting for right now ("Rare"...) and the stand it is on,
-- or nil when it is not waiting. (It waits when the Queen rolls a kind ticked in Settings.)
function State.AutoRollWaiting(): (string?, number?)
	local rarityName = player:GetAttribute("AutoRollWaiting")
	if State.AutoRollOn() and typeof(rarityName) == "string" and GameConfig.Bees[rarityName] then
		return rarityName, math.max(1, State.Number("AutoRollWaitingStand"))
	end
	return nil, nil
end

-- THE HONEY MARKET'S PRICE (the same for everyone in the server) ---------------------------
-- The server writes two numbers on the workspace: the price multiplier, and the server time
-- at which it changes next.

function State.SellPrice(): number
	local price = workspace:GetAttribute("SellPrice")
	return if typeof(price) == "number" and price > 0 then price else 1
end

-- Whole seconds until the price changes.
function State.SellPriceSecondsLeft(): number
	local changesAt = workspace:GetAttribute("SellPriceChangesAt")
	if typeof(changesAt) ~= "number" then
		return 0
	end
	return math.max(0, math.ceil(changesAt - workspace:GetServerTimeNow()))
end

-- True while the price is high enough to make a fuss about (GameConfig.SellPriceHigh).
function State.SellPriceIsHigh(): boolean
	return State.SellPrice() >= GameConfig.SellPriceHigh
end

-- SETTINGS (the gear button) --------------------------------------------------------------

-- How loud the music is, from 0 to 100.
function State.MusicVolume(): number
	local value = player:GetAttribute("Set_Music")
	return if typeof(value) == "number" then value else GameConfig.DefaultMusicVolume
end

-- How loud the sound effects are, from 0 to 100.
function State.SoundVolume(): number
	local value = player:GetAttribute("Set_Sounds")
	return if typeof(value) == "number" then value else GameConfig.DefaultSoundVolume
end

-- True if Auto Roll waits when the Queen rolls this kind of bee.
function State.StopsFor(rarityName: string): boolean
	return player:GetAttribute("Set_Stop_" .. rarityName) == true
end

-- True if the other players' flying bees are shown on this screen (a choice in Settings).
function State.ShowOtherBees(): boolean
	return player:GetAttribute("Set_OtherBees") ~= false
end

-- The Queen's Luck level in use (a player may use less luck than they own).
function State.LuckLevelInUse(): number
	local owned = State.UpgradeLevel("Luck")
	local chosen = State.Number("Set_Luck")
	return if chosen >= 1 then math.min(chosen, owned) else owned
end

-- The luck multiplier in use: the number the Queen really rolls with (1.3 = "x1.3 luck").
function State.LuckInUse(): number
	return Upgrades.ValueAt("Luck", State.LuckLevelInUse())
end

-- The luck multiplier the player OWNS (the same number unless they turned it down in Settings).
function State.LuckOwned(): number
	return Upgrades.ValueAt("Luck", State.UpgradeLevel("Luck"))
end

local function rateOf(rarityName: string): number
	return GameConfig.Bees[rarityName].NectarPerSecond
end

-- True when a bee in the bag is better than one working in a cell (Equip Best would help).
function State.BetterBeeWaiting(): boolean
	local rates = {}
	local current = 0
	local capacity = State.Capacity()
	for cellIndex = 1, capacity do
		local rarityName = State.Cell(cellIndex)
		if rarityName then
			table.insert(rates, rateOf(rarityName))
			current += rateOf(rarityName)
		end
	end
	for rarityName, count in State.Bag() do
		for _ = 1, count do
			table.insert(rates, rateOf(rarityName))
		end
	end
	table.sort(rates, function(a, b)
		return a > b
	end)
	local best = 0
	for index = 1, math.min(capacity, #rates) do
		best += rates[index]
	end
	return best > current
end

-- True if rolling could still improve the hive: there is a free spot, or some working bee
-- is not the best kind yet.
function State.RollCouldHelp(): boolean
	if State.EmptyCellCount() > 0 then
		return true
	end
	local bestRate = rateOf(GameConfig.QueenBees[#GameConfig.QueenBees]) -- the best bee the Queen can roll
	for cellIndex = 1, State.Capacity() do
		local rarityName = State.Cell(cellIndex)
		if rarityName and rateOf(rarityName) < bestRate then
			return true
		end
	end
	return false
end

-- True if a bee of this rarity would make the hive better: there is a free spot for it,
-- or it is stronger than the weakest bee working now.
function State.BeeWouldHelp(rarityName: string): boolean
	if State.EmptyCellCount() > 0 then
		return true
	end
	local rate = rateOf(rarityName)
	for cellIndex = 1, State.Capacity() do
		local working = State.Cell(cellIndex)
		if working and rateOf(working) < rate then
			return true
		end
	end
	return false
end

-- The best bee waiting on your stands that you can pay for AND that would make your hive
-- better: its rarity, its price and the number of the stand it is on. nil when there is none.
function State.BestOffer(): (string?, number, number)
	local coins = State.Number("Coins")
	local bestName, bestPrice, bestStand, bestRate = nil, 0, 0, -1
	for index, offer in State.Offers() do
		local rate = rateOf(offer.Rarity)
		if coins >= offer.Price and rate > bestRate and State.BeeWouldHelp(offer.Rarity) then
			bestName, bestPrice, bestStand, bestRate = offer.Rarity, offer.Price, index, rate
		end
	end
	return bestName, bestPrice, bestStand
end

-- BOOSTS (Double Honey, Double Luck: see GameConfig.Boosts) ----------------------------------
-- The server writes the server time at which each boost ends (0 while it is not running).

-- Seconds left of a boost (0 when it is not running). kind is "Honey" or "Luck".
function State.BoostSecondsLeft(kind: string): number
	local ends = player:GetAttribute("BoostEnds_" .. kind)
	if typeof(ends) ~= "number" or ends <= 0 then
		return 0
	end
	return math.max(0, ends - workspace:GetServerTimeNow())
end

-- What a boost multiplies by right now: its Multiplier while it is running, otherwise 1.
function State.BoostMultiplier(kind: string): number
	local boost = GameConfig.Boosts[kind]
	return if boost and State.BoostSecondsLeft(kind) > 0 then boost.Multiplier else 1
end

-- PASSES (things bought with Robux: see THE SHOP in GameConfig) ---------------------------------
-- The server marks each pass a player owns (it asks Roblox; a player's device has no say).

-- True if the player owns this pass. passName is a name from GameConfig.Passes.
function State.OwnsPass(passName: string): boolean
	return player:GetAttribute("Pass_" .. passName) == true
end

-- False in the few countries where passes that change random rolls may not be sold.
function State.RandomPassesAllowed(): boolean
	return player:GetAttribute("RandomPassesAllowed") == true
end

-- How many spare bees the Inventory holds (no real limit with the Infinite Inventory pass).
function State.BagLimit(): number
	local limit = State.Number("BagLimit")
	return if limit > 0 then limit else GameConfig.MaxBeesInBag
end

-- How many honeycomb stands the "+2 Rolls" pass adds for this player (0 without it).
function State.PassStands(): number
	return if State.OwnsPass("Rolls") then math.max(0, GameConfig.GamePassRollStands) else 0
end

-- What the Lucky Queen pass multiplies luck by (1 without it).
function State.PassLuck(): number
	return if State.OwnsPass("LuckyQueen") then GameConfig.LuckyQueenLuck else 1
end

-- The luck the Queen rolls with right now: the luck in use, times a running Double Luck
-- boost, times the Lucky Queen pass. (BeeService multiplies the very same three things.)
function State.RollLuck(): number
	return State.LuckInUse() * State.BoostMultiplier("Luck") * State.PassLuck()
end

-- True while the Auto Sell pass is owned and switched on.
function State.AutoSellOn(): boolean
	return State.OwnsPass("AutoSell") and player:GetAttribute("Set_AutoSell") ~= false
end

-- THE HALLOWEEN EGG (a limited-time event: see GameConfig) ---------------------------------------
-- The server writes on the workspace when the egg leaves (0 or nothing = it is not there).

-- Seconds until the Halloween Egg leaves (0 when it is not there).
function State.EggSecondsLeft(): number
	local ends = workspace:GetAttribute("HalloweenEggEndsAt")
	if typeof(ends) ~= "number" or ends <= 0 then
		return 0
	end
	return math.max(0, ends - workspace:GetServerTimeNow())
end

-- True if the player has at least one bee of this kind, working or spare.
function State.OwnsBee(beeName: string): boolean
	if State.Number("Bag_" .. beeName) > 0 then
		return true
	end
	for cellIndex = 1, State.Capacity() do
		if State.Cell(cellIndex) == beeName then
			return true
		end
	end
	return false
end

-- THE INVENTORY (spare bees and waiting boosts) -------------------------------------------------

-- True if the player has locked this kind of bee (a locked kind cannot be deleted).
function State.IsLocked(beeName: string): boolean
	return player:GetAttribute("Lock_" .. beeName) == true
end

-- The boosts waiting in the Inventory: { { Kind = "Honey", Minutes = 10, Count = 2 }, ... }
-- in the order of GameConfig.BoostOrder, shortest first.
function State.BoostItems(): { { Kind: string, Minutes: number, Count: number } }
	local list = {}
	for name, value in player:GetAttributes() do
		if typeof(value) == "number" and value > 0 and name:sub(1, 10) == "BoostItem_" then
			local kind, minutes = GameConfig.ReadBoostItemKey(name:sub(11))
			if kind and minutes then
				table.insert(list, { Kind = kind, Minutes = minutes, Count = value })
			end
		end
	end
	table.sort(list, function(a, b)
		local orderA = table.find(GameConfig.BoostOrder, a.Kind) or 99
		local orderB = table.find(GameConfig.BoostOrder, b.Kind) or 99
		if orderA ~= orderB then
			return orderA < orderB
		end
		return a.Minutes < b.Minutes
	end)
	return list
end

-- DAILY REWARDS -------------------------------------------------------------------------------

-- How many of this round's rewards have been collected (0 = none yet, so day 1 is next).
function State.DailyClaimed(): number
	return math.clamp(State.Number("DailyDay"), 0, #GameConfig.DailyRewards - 1)
end

-- Seconds until the next daily reward can be collected (0 = it is ready now).
function State.DailySecondsLeft(): number
	return math.max(0, State.Number("DailyNextAt") - workspace:GetServerTimeNow())
end

function State.DailyReady(): boolean
	return State.IsLoaded() and State.DailySecondsLeft() <= 0
end

-- THE TUTORIAL -------------------------------------------------------------------------------
-- The server ticks off three lessons (TutorialService): "Sold", "Upgrade" and "BetterBee".

-- True once that lesson is done.
function State.TutorialStep(step: string): boolean
	return player:GetAttribute("Tut_" .. step) == true
end

-- True once all three lessons are done: no more hint and no more arrow, for good.
function State.TutorialDone(): boolean
	return player:GetAttribute("TutorialDone") == true
end

-- The Honey Market's price on an ordinary day (the average of GameConfig.SellPriceBands).
local typicalSellPrice = 0
do
	local total, chances = 0, 0
	for _, band in GameConfig.SellPriceBands do
		total += band.Chance * (band.Min + band.Max) / 2
		chances += band.Chance
	end
	typicalSellPrice = if chances > 0 then total / chances else 1
end

-- The price of the cheapest bee that is stronger than the weakest bee working in the hive.
-- (math.huge when no bee is.)
function State.CheapestBetterBeePrice(): number
	local weakest = math.huge
	for cellIndex = 1, State.Capacity() do
		local working = State.Cell(cellIndex)
		if working then
			weakest = math.min(weakest, rateOf(working))
		end
	end
	local price = math.huge
	for _, beeName in GameConfig.QueenBees do -- (Limited bees are never on a stand)
		local bee = GameConfig.Bees[beeName]
		if bee.NectarPerSecond > weakest then
			price = math.min(price, bee.Price)
		end
	end
	return price
end

-- A bee waiting on a stand that would make the hive better, that the player cannot pay for
-- yet but soon could: their bees earn the missing coins within GameConfig.SaveForBeeSeconds.
-- Returns its name in GameConfig.Bees and the coins still missing, or nil.
function State.BeeWorthSavingFor(): (string?, number)
	local coins = State.Number("Coins")
	local coinsPerSecond = State.Number("JarsPerSecond") * GameConfig.JarValue * typicalSellPrice
	local bestName, bestMissing, bestRate = nil, 0, -1
	for _, offer in State.Offers() do
		local missing = offer.Price - coins
		if missing > 0 and missing <= coinsPerSecond * GameConfig.SaveForBeeSeconds and rateOf(offer.Rarity) > bestRate and State.BeeWouldHelp(offer.Rarity) then
			bestName, bestMissing, bestRate = offer.Rarity, missing, rateOf(offer.Rarity)
		end
	end
	return bestName, bestMissing
end

-- What the player should do next: a hint for the screen and which place to point the arrow at.
-- Targets: "Queen", "Stand", "Hive", "Upgrades", "Collect", "Market" or nil. For "Stand" the
-- third value is the number of the honeycomb stand.
-- Once the tutorial is done the hint is "" (nothing is shown) and there is no arrow.
function State.Objective(): (string, string?, number?)
	if not State.IsLoaded() then
		return "Loading your hive...", nil
	end
	if State.TutorialDone() then
		return "", nil
	end
	local upgradeLessonDone = State.TutorialStep("Upgrade")

	local bag = State.BagTotal()
	local empty = State.EmptyCellCount()
	local placed = State.Capacity() - empty
	local carried = State.Number("JarsCarried")
	local stored = State.Number("JarsStored")
	local coins = State.Number("Coins")
	local rate = State.Number("JarsPerSecond")
	-- "worth a trip": about 8 seconds of honey, at least 1 jar and at most 20
	local worthIt = math.clamp(math.floor(rate * 8), 1, 20)

	local offers = State.Offers()
	local offer, _, offerStand = State.BestOffer() -- a bee you can afford that would help
	-- is a bee that would help waiting on a stand at all (even one you cannot pay for yet)?
	local helpfulWaiting = false
	for _, waiting in offers do
		if State.BeeWouldHelp(waiting.Rarity) then
			helpfulWaiting = true
		end
	end
	-- with Auto Roll switched on there is no need to send the player to press E at the Queen
	local rollHint = if State.AutoRollOn() then "Auto Roll is on - buy a bee you like!" else "Roll a new bee at your Queen!"
	local rollMoreHint = if State.AutoRollOn() then "Auto Roll is on - watch for better bees!" else "Roll for even better bees!"

	if bag == 0 and placed == 0 then
		if offers[1] then
			return "Take your FREE bee from the honeycomb stand!", "Stand", 1
		end
		return "Roll your first bee for FREE at your Queen!", "Queen"
	elseif bag > 0 and empty > 0 then
		return "Your hive has room for a spare bee! Press Equip Best!", nil
	elseif State.BetterBeeWaiting() then
		return "You have a better bee! Press Equip Best!", nil
	end

	local waitingFor, waitingStand = State.AutoRollWaiting()
	if waitingFor then
		-- Auto Roll stopped for a kind of bee the player ticked in Settings
		return "Auto Roll found a " .. GameConfig.Bees[waitingFor].BeeName .. "! Buy it, or tap Keep Rolling.", "Stand", waitingStand
	end

	-- a great price at the Honey Market does not last: say so while there is honey to sell
	if State.SellPriceIsHigh() then
		local priceText = string.format("x%.1f", State.SellPrice())
		if carried > 0 then
			return "Honey price is " .. priceText .. "! Sell your jars now!", "Market"
		elseif stored >= worthIt then
			return "Honey price is " .. priceText .. "! Grab your jars and sell!", "Collect"
		end
	end

	local nextHive = State.NextHive()
	local rollHelps = State.RollCouldHelp()
	local cheapest = State.CheapestBeePrice()
	if offer then
		if empty == 0 and bag >= State.BagLimit() then
			-- no room anywhere: the server would refuse this buy
			return "Your Inventory is full! Delete a spare bee!", nil
		end
		-- a bee you can afford, and that would help, is waiting on a stand
		return "Buy the bee on your honeycomb stand!", "Stand", offerStand
	elseif empty == 0 and nextHive and coins >= nextHive.Cost then
		return "Buy a bigger hive at your Upgrade Shop!", "Upgrades"
	elseif empty > 0 and coins >= cheapest then
		-- room in the hive: more bees is always good (rolling is free, the bee has a price)
		return rollHint, "Queen"
	elseif not nextHive and rollHelps and coins >= cheapest and not helpfulWaiting then
		-- biggest hive already: keep rolling for better bees
		return rollMoreHint, "Queen"
	elseif carried >= worthIt or (carried > 0 and stored < worthIt) then
		return "Sell your jars at the Honey Market!", "Market"
	elseif stored >= worthIt then
		return "Grab your honey jars!", "Collect"
	elseif not upgradeLessonDone and State.UpgradeWorthAVisit() then
		-- (only until the first upgrade is bought: after that the player knows the shop)
		return "You can afford an upgrade! Visit your Upgrade Shop!", "Upgrades"
	elseif upgradeLessonDone and empty == 0 and rollHelps then
		-- the last lesson: the hive is full, so the way forward is a BETTER bee.
		-- (Rolling is free. A better bee bought now takes a weaker one's place.)
		local saveFor, missing = State.BeeWorthSavingFor()
		if saveFor then
			return "Save " .. NumberFormat.Short(missing) .. " more coins for the " .. GameConfig.Bees[saveFor].BeeName .. " on your stand!", nil
		end
		local betterPrice = State.CheapestBetterBeePrice()
		if coins >= betterPrice then
			return if State.AutoRollOn() then "Auto Roll is on - watch for better bees!" else "Roll for better bees!", "Queen"
		end
		return "Earn " .. NumberFormat.Short(betterPrice - coins) .. " more coins for a better bee!", nil
	elseif empty == 0 and nextHive then
		return "Save " .. NumberFormat.Short(nextHive.Cost) .. " coins for a bigger hive!", nil
	elseif rollHelps or nextHive then
		return "Your bees are visiting the flowers...", nil
	else
		return "Your hive has the best bees! Keep collecting!", nil
	end
end

-- Fire Changed once per frame at most, however many attributes changed.
local pending = false
local function announce()
	if pending then
		return
	end
	pending = true
	task.defer(function()
		pending = false
		changedEvent:Fire()
	end)
end
player.AttributeChanged:Connect(announce)
workspace:GetAttributeChangedSignal("SellPrice"):Connect(announce) -- the Honey Market's price
workspace:GetAttributeChangedSignal("HalloweenEggEndsAt"):Connect(announce) -- the Halloween Egg comes or goes

return State
