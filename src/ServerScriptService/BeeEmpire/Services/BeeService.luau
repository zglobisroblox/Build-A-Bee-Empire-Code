--[[
	BeeService - everything about bees:
	- rolling at the Queen (free), which puts a random bee on every honeycomb stand you own
	- buying a bee from a stand
	- how many stands a home area has (the More Rolls upgrade) and where they stand
	- Auto Roll: buying it at the sign, switching it on and off, and the Queen rolling by herself
	- putting bees to work in the hive, taking them out, and selling them

	The hive has numbered slots (1, 2, 3...). How many slots there are depends on the
	hive's level. In the save data the slots are called "Cells".

	All of this runs on the server. Players can only ASK; the server decides what really happens.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)
local NumberFormat = require(ReplicatedStorage.BeeEmpire.NumberFormat)
local DataService = require(script.Parent.DataService)
local HiveService = require(script.Parent.HiveService)
local Notifier = require(script.Parent.Notifier)
local PassService = require(script.Parent.PassService)
local PlotService = require(script.Parent.PlotService)
local TutorialService = require(script.Parent.TutorialService)

local BeeService = {}

local random = Random.new()

-- HELPERS -----------------------------------------------------------------------

local function rateOf(bee): number
	return GameConfig.Bees[bee.Rarity].NectarPerSecond
end

local function capacityOf(data): number
	return GameConfig.GetHive(data.HiveLevel).Capacity
end

local function countBees(data): number
	return #data.Bees + HiveService.CountBees(data)
end

local function isValidSlot(data, slotIndex: any): boolean
	return typeof(slotIndex) == "number" and slotIndex % 1 == 0 and slotIndex >= 1 and slotIndex <= capacityOf(data)
end

-- The bees of each rarity, and how likely each rarity is with some amount of luck. Both live
-- in GameConfig (THE CHANCES OF A ROLL), because the Shop's "Bee Chances" window shows the
-- very same numbers the Queen rolls with.
local beesOfRarity: { [string]: { string } } = GameConfig.BeesOfRarity
local rarityChances = GameConfig.RarityChances

-- Picks a bee at random. First the rarity (see rarityChances above). Then one of that
-- rarity's bees: a bigger Share means it is picked more often.
local function rollRarity(luck: number): string
	local weights, totalWeight = rarityChances(luck)
	local pick = random:NextNumber() * totalWeight
	local rolledRarity = nil
	for _, rarityName in GameConfig.RarityOrder do
		pick -= weights[rarityName]
		if pick <= 0 and weights[rarityName] > 0 then
			rolledRarity = rarityName
			break
		end
	end
	local list = if rolledRarity then beesOfRarity[rolledRarity] else nil
	if not list then
		return GameConfig.BeeOrder[1]
	end

	local totalShare = 0
	for _, beeName in list do
		totalShare += GameConfig.Bees[beeName].Share or 1
	end
	local pickBee = random:NextNumber() * totalShare
	for _, beeName in list do
		pickBee -= GameConfig.Bees[beeName].Share or 1
		if pickBee <= 0 then
			return beeName
		end
	end
	return list[#list]
end

-- For checking the odds from the command bar. Neither one changes anything in the game:
-- BeeService.RarityChances(2) lists the chances with x2 luck, BeeService.RollBee(2) picks a bee.
BeeService.RarityChances = rarityChances
BeeService.RollBee = rollRarity

-- Returns the position in the bag of the strongest (or weakest) bee, or nil if the bag is empty.
local function findInBag(data, wantStrongest: boolean): number?
	local bestIndex, bestRate = nil, nil
	for index, bee in data.Bees do
		local rate = rateOf(bee)
		if bestRate == nil or (wantStrongest and rate > bestRate) or (not wantStrongest and rate < bestRate) then
			bestIndex, bestRate = index, rate
		end
	end
	return bestIndex
end

local function findRarityInBag(data, rarityName: string): number?
	for index, bee in data.Bees do
		if bee.Rarity == rarityName then
			return index
		end
	end
	return nil
end

-- True if the player already has a bee of this rarity (working in the hive or in the bag).
local function ownsRarity(data, rarityName: string): boolean
	for _, placedBee in data.Cells do
		if placedBee.Rarity == rarityName then
			return true
		end
	end
	return findRarityInBag(data, rarityName) ~= nil
end

-- THE HONEYCOMB STANDS -------------------------------------------------------------------
-- A roll does not hand over a bee. It puts an OFFER on each honeycomb stand: which bee,
-- and what it costs. The player then buys one (BuyOffer) or rolls again for others.
-- Offers are SAVED with the player (data.Offers): leave and come back later, and the same
-- bees are still waiting on the stands (see rememberOffers and restoreOffers).

type Offer = { Rarity: string, Price: number, ReadyAt: number }
local offers: { [Player]: { [number]: Offer } } = {}
local nextRollAt: { [Player]: number } = {} -- the server time when each player may roll again
local nextAutoRollAt: { [Player]: number } = {} -- the server time of each player's next Auto Roll
local skipWait: { [Player]: boolean } = {} -- true after Keep Rolling: Auto Roll no longer waits for the bees on the stands now

-- WHAT STANDS IN A ROLL AREA. The map is built with one honeycomb stand, in the middle
-- behind the Queen. This script makes the others (copies of stand 1) when the server starts
-- and keeps them out of the world. A home area shows as many stands as its owner has (the
-- More Rolls upgrade), spread along an arc: the map says where each stand goes for each
-- number of stands (the "Spot_<how many>_<which>" attributes on the Stands folder).
-- The Auto Roll sign stands there until the owner has bought Auto Roll.
type RollArea = {
	Queen: Instance,
	StandsFolder: Instance,
	Stands: { Instance }, -- [stand number] = the honeycomb stand
	AutoSign: Instance?, -- the sign that sells Auto Roll
}
local rollAreas: { [Model]: RollArea } = {}

-- (The first look at a plot must happen while everything is still in the world: ResetPlot
-- does it when the server starts.)
local function rollAreaOf(plot: Model): RollArea?
	local area = rollAreas[plot]
	if area then
		return area
	end
	local queen = plot:FindFirstChild("Queen")
	local standsFolder = queen and queen:FindFirstChild("Stands")
	if not queen or not standsFolder then
		return nil
	end
	local newArea: RollArea = {
		Queen = queen,
		StandsFolder = standsFolder,
		Stands = {},
		AutoSign = queen:FindFirstChild("AutoRoll"),
	}
	local firstStand = standsFolder:FindFirstChild("Stand1")
	if not firstStand or not firstStand:IsA("Model") then
		return nil
	end
	newArea.Stands[1] = firstStand
	-- Make the other stands: copies of stand 1, kept out of the world until their owner has them.
	for index = 2, GameConfig.RollStandSpots do
		local stand = firstStand:Clone()
		stand.Name = "Stand" .. index
		stand:SetAttribute("StandIndex", index)
		newArea.Stands[index] = stand
	end
	rollAreas[plot] = newArea
	return newArea
end

-- How many stands the "+2 Rolls" pass adds for this player (none without the pass).
local function passStands(player: Player): number
	return PassService.ExtraStands(player)
end

-- How many seconds this player's Queen waits between her own rolls (the Roll Speed upgrade).
local function autoRollSeconds(data): number
	return math.max(0.5, DataService.UpgradeValue(data, "RollSpeed"))
end

-- How many honeycomb stands a player has: the More Rolls upgrade, plus any game-pass stands.
local function standCount(player: Player, data): number
	return math.clamp(DataService.UpgradeValue(data, "Rolls") + passStands(player), 1, GameConfig.RollStandSpots)
end

-- The stands on a plot that a roll fills: the first `count` of them.
local function standsOf(plot: Model, count: number): { Instance }
	local area = rollAreaOf(plot)
	local list = {}
	if area then
		for index = 1, math.min(count, #area.Stands) do
			table.insert(list, area.Stands[index])
		end
	end
	return list
end

local function buyPrompt(stand: Instance): ProximityPrompt?
	local buySpot = stand:FindFirstChild("BuySpot")
	local prompt = buySpot and buySpot:FindFirstChild("Prompt")
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

-- Writes an offer on a stand for everybody to see. Each player's own screen plays the
-- egg -> shadow -> bee show from these values (see WorldFX). The screen is never trusted:
-- BuyOffer checks everything again.
local function showOffer(stand: Instance, offer: Offer, startedAt: number, isNew: boolean)
	local rarity = GameConfig.Bees[offer.Rarity]
	local prompt = buyPrompt(stand)
	if prompt then
		prompt.ActionText = if offer.Price == 0 then "Take Bee" else "Buy Bee"
		prompt.ObjectText = rarity.BeeName .. (if offer.Price == 0 then "  -  FREE!" else "  -  " .. NumberFormat.Short(offer.Price) .. " coins")
	end
	stand:SetAttribute("OfferRarity", offer.Rarity)
	stand:SetAttribute("OfferPrice", offer.Price)
	stand:SetAttribute("OfferNew", isNew)
	stand:SetAttribute("OfferStart", startedAt) -- set last: this is what starts the show
end

-- Empties a stand (after the bee is bought, or when the player leaves).
local function clearOffer(stand: Instance)
	stand:SetAttribute("OfferStart", nil)
	stand:SetAttribute("OfferRarity", nil)
	stand:SetAttribute("OfferPrice", nil)
	stand:SetAttribute("OfferNew", nil)
	local prompt = buyPrompt(stand)
	if prompt then
		prompt.ActionText = "Buy Bee"
		prompt.ObjectText = "Honeycomb Stand"
	end
end

-- Shows the right things in a roll area: `owned` honeycomb stands, each in its place for
-- that many stands, and the Auto Roll sign unless Auto Roll has been bought.
local function showRollArea(plot: Model, owned: number, autoRollBought: boolean)
	local area = rollAreaOf(plot)
	if not area then
		return
	end
	for index, stand in area.Stands do
		if index <= owned then
			local spot = area.StandsFolder:GetAttribute(string.format("Spot_%d_%d", owned, index))
			if typeof(spot) == "CFrame" and stand:IsA("Model") then
				stand:PivotTo(spot)
			end
			stand.Parent = area.StandsFolder
		else
			clearOffer(stand)
			stand.Parent = nil
		end
	end
	if area.AutoSign then
		area.AutoSign.Parent = if autoRollBought then nil else area.Queen
	end
end

-- Writes the price from GameConfig on the Auto Roll sign.
local function writeAutoSign(area: RollArea)
	local autoSign = area.AutoSign
	if not autoSign then
		return
	end
	local price = NumberFormat.Short(GameConfig.AutoRollPrice)
	local sign = autoSign:FindFirstChild("Sign")
	local face = sign and sign:FindFirstChild("Face")
	local pill = face and face:FindFirstChild("Price")
	local label = pill and pill:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = price
	end
	local buySpot = autoSign:FindFirstChild("BuySpot")
	local prompt = buySpot and buySpot:FindFirstChild("Prompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.ObjectText = price .. " coins  -  you only pay once"
	end
end

-- Writes the bees on the player's stands into their save, so they are still there next time.
local function rememberOffers(player: Player, data)
	local saved = {}
	local list = offers[player]
	if list then
		for index, offer in list do
			saved[tostring(index)] = { Rarity = offer.Rarity, Free = if offer.Price == 0 then true else nil }
		end
	end
	data.Offers = saved
end

-- Puts the saved bees back on the player's stands when they join. They are shown already
-- hatched (no egg, no sounds). Prices come from GameConfig as it is today.
local function restoreOffers(player: Player)
	local data = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	if not data or not plot or typeof(data.Offers) ~= "table" then
		return
	end
	local list: { [number]: Offer } = {}
	local longAgo = workspace:GetServerTimeNow() - 3600 -- "this show finished long ago"
	local noBees = countBees(data) == 0
	local found = false
	for index, stand in standsOf(plot, standCount(player, data)) do
		local saved = data.Offers[tostring(index)]
		local rarity = if saved then GameConfig.Bees[saved.Rarity] else nil
		if saved and rarity then
			-- (the free starter bee stays free only while the player really has no bees)
			local free = saved.Free == true and noBees and GameConfig.FirstBeeFree
			local offer: Offer = { Rarity = saved.Rarity, Price = if free then 0 else rarity.Price, ReadyAt = 0 }
			list[index] = offer
			showOffer(stand, offer, longAgo, not ownsRarity(data, saved.Rarity))
			found = true
		end
	end
	if found then
		offers[player] = list
		-- Auto Roll gives the player a moment to look at them before she rolls again
		nextAutoRollAt[player] = workspace:GetServerTimeNow() + GameConfig.AutoRollJoinWait
	end
	rememberOffers(player, data) -- (drops anything that no longer fits, like a stand that is gone)
end

-- AUTO ROLL WAITS FOR WANTED BEES. In Settings a player ticks the kinds of bee Auto Roll
-- should stop for. While one of those is on a stand the Queen does not roll by herself: she
-- waits until that bee is bought, or until the player taps Keep Rolling (or rolls by hand).
-- Returns the best such bee on the player's stands (its kind, and its stand), or nil.
local function wantedOffer(player: Player, data): (string?, number?)
	local list = offers[player]
	local stopFor = data.Settings.StopFor
	if not list or skipWait[player] then
		return nil, nil
	end
	local bestName, bestStand, bestRank = nil, nil, 0
	for index, offer in list do
		local rank = table.find(GameConfig.BeeOrder, offer.Rarity) or 0
		if stopFor[GameConfig.Bees[offer.Rarity].Rarity] and rank > bestRank then
			bestName, bestStand, bestRank = offer.Rarity, index, rank
		end
	end
	return bestName, bestStand
end

-- Tells the player's own screen whether Auto Roll is waiting, and for which bee (the button
-- turns into "Keep Rolling"). hidden = true says "not yet" (the egg has not hatched).
local function shareWaiting(player: Player, hidden: boolean?)
	local data = DataService.Get(player)
	local name, stand = nil, nil
	if data and not hidden and data.AutoRoll and data.AutoRollOn then
		name, stand = wantedOffer(player, data)
	end
	player:SetAttribute("AutoRollWaiting", name)
	player:SetAttribute("AutoRollWaitingStand", stand)
end

-- Tells the player's own screen what is waiting on each of their stands (for the hint and
-- the arrow). hidden = true says "nothing yet" (while the egg-and-shadow show is running).
local function shareOffers(player: Player, hidden: boolean?)
	local list = offers[player]
	for index = 1, GameConfig.RollStandSpots do
		local offer = if hidden or not list then nil else list[index]
		player:SetAttribute("Offer" .. index, if offer then offer.Rarity else nil)
		player:SetAttribute("OfferPrice" .. index, if offer then offer.Price else nil)
	end
	shareWaiting(player, hidden)
end

-- Redraws the bees at the player's hive and updates their screen.
local function hiveChanged(player: Player, data)
	local plot = PlotService.GetPlot(player)
	if plot then
		HiveService.RefreshBees(plot, data)
	end
	DataService.Replicate(player)
end

-- PLAYER ACTIONS (Main has already checked who is asking and where they stand) -------------

-- Rolling at the Queen (or the Queen rolling by herself: Auto Roll). It is free. Every
-- honeycomb stand the player owns gets one random bee and its price; a new roll replaces
-- whatever was on the stands before.
-- The luck a player rolls with right now: the luck they own (unless they turned it down in
-- Settings), twice that while a Double Luck boost is running, and twice again, always, with
-- the Lucky Queen pass. (The Halloween Egg uses the same number.)
function BeeService.RollLuck(player: Player, data): number
	return DataService.LuckInUse(data) * DataService.BoostMultiplier(data, "Luck") * PassService.LuckMultiplier(player)
end

-- True if one more bee would fit: a free spot in the hive, or room in the Inventory.
function BeeService.HasRoom(player: Player): boolean
	local data = DataService.Get(player)
	if not data then
		return false
	end
	for index = 1, capacityOf(data) do
		if not data.Cells[tostring(index)] then
			return true
		end
	end
	return #data.Bees < PassService.BagLimit(player)
end

function BeeService.Roll(player: Player)
	local data = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	if not data or not plot then
		return
	end

	local now = workspace:GetServerTimeNow()
	if now < (nextRollAt[player] or 0) then
		return -- the Queen is still busy with the last roll
	end
	local stands = standsOf(plot, standCount(player, data))
	if #stands == 0 then
		return
	end
	nextRollAt[player] = now + GameConfig.RollCooldown
	skipWait[player] = nil -- new bees: Auto Roll looks at them afresh

	-- A player with no bees at all is offered the starter bee (the most common one) for free.
	local starter = GameConfig.FirstBeeFree and countBees(data) == 0
	local luck = BeeService.RollLuck(player, data)
	local list: { [number]: Offer } = {}
	local showSeconds = 0 -- how long until every stand's bee has hatched
	for index, stand in stands do
		local free = starter and index == 1
		local rarityName = if free then GameConfig.BeeOrder[1] else rollRarity(luck)
		-- (a BigReveal bee stays in its golden egg for longer)
		local eggSeconds = if GameConfig.Bees[rarityName].BigReveal then GameConfig.BigRevealEggSeconds else GameConfig.RollEggSeconds
		local offer: Offer = {
			Rarity = rarityName,
			Price = if free then 0 else GameConfig.Bees[rarityName].Price,
			ReadyAt = now + eggSeconds + GameConfig.RollShadowSeconds,
		}
		showSeconds = math.max(showSeconds, eggSeconds + GameConfig.RollShadowSeconds)
		list[index] = offer
		showOffer(stand, offer, now, not ownsRarity(data, rarityName))
	end
	offers[player] = list
	rememberOffers(player, data)
	-- Auto Roll waits her full time after any roll (the Roll Speed upgrade), and never rolls
	-- again before every egg on the stands has hatched
	nextAutoRollAt[player] = now + math.max(autoRollSeconds(data), showSeconds)
	if list[1] and list[1].Price == 0 then
		shareOffers(player) -- the free starter bee is no secret
	else
		-- keep the hint and arrow quiet until the egg-and-shadow show has finished
		shareOffers(player, true)
		task.delay(showSeconds, function()
			if offers[player] == list then
				shareOffers(player)
				-- Auto Roll found a bee the player asked it to stop for
				local found = player:GetAttribute("AutoRollWaiting")
				if typeof(found) == "string" and GameConfig.Bees[found] then
					local rarity = GameConfig.Bees[found]
					Notifier.Send(player, "Auto Roll found a " .. rarity.BeeName .. "!", "good", rarity.RarityColor, rarity.Rainbow)
				end
			end
		end)
	end
end

-- Buying the bee that is waiting on a honeycomb stand. It goes straight to work if the hive
-- has a free spot, otherwise it waits in the bag.
function BeeService.BuyOffer(player: Player, standIndex: any)
	if typeof(standIndex) ~= "number" then
		return
	end
	local data = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	if not data or not plot then
		return
	end

	local list = offers[player]
	local offer = list and list[standIndex]
	if not list or not offer then
		return -- nothing on the stand (for example a second tap that arrived just after the buy)
	end
	if workspace:GetServerTimeNow() < offer.ReadyAt then
		return -- the bee has not hatched yet
	end

	-- the starter bee is only free while the player really has no bees
	local price = offer.Price
	if price == 0 and countBees(data) > 0 then
		price = GameConfig.Bees[offer.Rarity].Price
	end
	if data.Coins < price then
		Notifier.Send(player, "You need " .. NumberFormat.Short(price - data.Coins) .. " more Honey Coins for this bee!", "bad")
		return
	end

	-- where will it go? A free spot in the hive first, otherwise the bag.
	local freeKey = nil
	for index = 1, capacityOf(data) do
		local key = tostring(index)
		if not data.Cells[key] then
			freeKey = key
			break
		end
	end
	if not freeKey and #data.Bees >= PassService.BagLimit(player) then
		Notifier.Send(player, "Your Inventory is full! Delete a spare bee first.", "bad")
		return
	end

	local newBee = { Rarity = offer.Rarity }
	data.Coins -= price
	if freeKey then
		data.Cells[freeKey] = newBee
	else
		table.insert(data.Bees, newBee)
	end

	list[standIndex] = nil
	rememberOffers(player, data)
	-- (if Auto Roll was waiting for this bee it carries on now; give the player time to look
	-- at the other stands first)
	local lookTime = math.max(autoRollSeconds(data), GameConfig.AutoRollBuyPause)
	nextAutoRollAt[player] = math.max(nextAutoRollAt[player] or 0, workspace:GetServerTimeNow() + lookTime)
	local area = rollAreaOf(plot)
	local stand = area and area.Stands[standIndex]
	if stand then
		clearOffer(stand)
	end
	shareOffers(player)

	Notifier.Effect(player, "Bought", { Rarity = offer.Rarity, Placed = freeKey ~= nil, Stand = standIndex })
	hiveChanged(player, data)
end

-- Gives a player a bee for nothing (a reward). It goes straight to work if the hive has a
-- free spot, otherwise it waits in the bag. Returns true if the bee was given, and then
-- whether it went into the hive. With no room anywhere it returns false and tells the player.
-- always = true puts it in the Inventory even when that is full (for a bee that was paid for
-- with Robux and must never be lost).
function BeeService.GiveBee(player: Player, beeName: string, always: boolean?): (boolean, boolean)
	local data = DataService.Get(player)
	if not data or GameConfig.Bees[beeName] == nil then
		return false, false
	end

	local freeKey = nil
	for index = 1, capacityOf(data) do
		local key = tostring(index)
		if not data.Cells[key] then
			freeKey = key
			break
		end
	end
	if not freeKey and not always and #data.Bees >= PassService.BagLimit(player) then
		Notifier.Send(player, "Your Inventory is full! Delete a spare bee first.", "bad")
		return false, false
	end

	local newBee = { Rarity = beeName }
	if freeKey then
		data.Cells[freeKey] = newBee
	else
		table.insert(data.Bees, newBee)
	end
	hiveChanged(player, data)
	return true, freeKey ~= nil
end

-- Puts one bee of the chosen rarity to work in the hive.
-- slotIndex is optional. Without it the server picks an empty slot, or replaces the weakest bee.
function BeeService.PlaceBee(player: Player, rarityName: any, slotIndex: any)
	if typeof(rarityName) ~= "string" or GameConfig.Bees[rarityName] == nil then
		return
	end

	local data = DataService.Get(player)
	if not data then
		return
	end
	if slotIndex ~= nil and not isValidSlot(data, slotIndex) then
		return
	end

	local bagIndex = findRarityInBag(data, rarityName)
	if not bagIndex then
		Notifier.Send(player, "You do not have that spare bee.", "bad")
		return
	end
	local bee = data.Bees[bagIndex]
	local rarity = GameConfig.Bees[rarityName]

	local targetIndex = slotIndex
	if not targetIndex then
		local weakestIndex, weakestRate = nil, nil
		for index = 1, capacityOf(data) do
			local placed = data.Cells[tostring(index)]
			if not placed then
				targetIndex = index
				break
			end
			local rate = rateOf(placed)
			if weakestRate == nil or rate < weakestRate then
				weakestIndex, weakestRate = index, rate
			end
		end
		if not targetIndex then
			if weakestRate and weakestRate < rateOf(bee) then
				targetIndex = weakestIndex
			else
				Notifier.Send(player, "Your hive is full of better bees! Upgrade your hive for more room.", "info")
				return
			end
		end
	end

	local key = tostring(targetIndex)
	local placedBee = data.Cells[key]
	if placedBee and rateOf(placedBee) >= rateOf(bee) then
		-- never swap a bee for a weaker (or equal) one by accident
		Notifier.Send(player, "That spot already has a better bee!", "info")
		return
	end
	if placedBee then
		data.Bees[bagIndex] = placedBee -- swap: the old bee goes back in the bag
	else
		table.remove(data.Bees, bagIndex)
	end
	data.Cells[key] = bee

	Notifier.Send(player, rarity.BeeName .. " is off to the flowers!", "good", rarity.RarityColor, rarity.Rainbow)
	hiveChanged(player, data)
	if placedBee then
		TutorialService.Mark(player, "BetterBee") -- (the tutorial: a better bee took a weaker one's place)
	end
end

-- Takes a bee out of the hive and puts it back in the bag.
function BeeService.RemoveBee(player: Player, slotIndex: any)
	local data = DataService.Get(player)
	if not data or not isValidSlot(data, slotIndex) then
		return
	end

	local key = tostring(slotIndex)
	local placedBee = data.Cells[key]
	if not placedBee then
		return
	end
	if #data.Bees >= PassService.BagLimit(player) then
		Notifier.Send(player, "Your Inventory is full!", "bad")
		return
	end

	data.Cells[key] = nil
	table.insert(data.Bees, placedBee)
	hiveChanged(player, data)
end

-- Puts the strongest bees the player owns to work in the hive.
function BeeService.EquipBest(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end

	local capacity = capacityOf(data)
	local allBees = {}
	local currentRate = 0
	for _, bee in data.Bees do
		table.insert(allBees, bee)
	end
	-- bees already working come last among equals, so they keep their spot when nothing better exists
	local working = {}
	for index = 1, capacity do
		local bee = data.Cells[tostring(index)]
		if bee then
			working[bee] = index
			table.insert(allBees, bee)
			currentRate += rateOf(bee)
		end
	end

	if #allBees == 0 then
		Notifier.Send(player, "You have no bees yet. Roll one at your Queen!", "bad")
		return
	end

	table.sort(allBees, function(a, b)
		if rateOf(a) ~= rateOf(b) then
			return rateOf(a) > rateOf(b)
		end
		-- equal strength: a bee that is already working wins (so it is not disturbed)
		return (working[a] ~= nil) and (working[b] == nil)
	end)

	local bestRate = 0
	for index = 1, math.min(capacity, #allBees) do
		bestRate += rateOf(allBees[index])
	end
	if bestRate <= currentRate then
		Notifier.Send(player, "Your best bees are already working!", "info")
		return
	end

	-- The chosen bees: ones already working keep their spot, new ones fill the gaps.
	local chosen = {}
	for index = 1, math.min(capacity, #allBees) do
		chosen[allBees[index]] = true
	end
	local newCells = {}
	local waiting = {}
	for bee in chosen do
		local spot = working[bee]
		if spot then
			newCells[tostring(spot)] = bee
		else
			table.insert(waiting, bee)
		end
	end
	for index = 1, capacity do
		local key = tostring(index)
		if not newCells[key] and #waiting > 0 then
			newCells[key] = table.remove(waiting)
		end
	end

	table.clear(data.Bees)
	for _, bee in allBees do
		if not chosen[bee] then
			table.insert(data.Bees, bee)
		end
	end
	-- did a bee that was working have to make way for a better one?
	local replaced = false
	for bee in working do
		if not chosen[bee] then
			replaced = true
		end
	end
	data.Cells = newCells

	Notifier.Send(player, "Best bees are working in your hive!", "good")
	hiveChanged(player, data)
	if replaced then
		TutorialService.Mark(player, "BetterBee") -- (the tutorial: a better bee took a weaker one's place)
	end
end

-- Deletes one spare bee from the Inventory for good. Nothing is paid for it.
-- A kind of bee the player has locked cannot be deleted.
function BeeService.DeleteBee(player: Player, rarityName: any)
	if typeof(rarityName) ~= "string" or GameConfig.Bees[rarityName] == nil then
		return
	end

	local data = DataService.Get(player)
	if not data then
		return
	end

	local bagIndex = findRarityInBag(data, rarityName)
	if not bagIndex then
		Notifier.Send(player, "You do not have that spare bee.", "bad")
		return
	end
	if data.Locked[rarityName] then
		Notifier.Send(player, GameConfig.Bees[rarityName].BeeName .. " is locked. Unlock it first!", "info")
		return
	end
	-- Never let a player delete their very last bee (that would also allow endless free rolls).
	if countBees(data) <= 1 then
		Notifier.Send(player, "You need to keep at least one bee!", "bad")
		return
	end

	table.remove(data.Bees, bagIndex)
	Notifier.Effect(player, "BeeDeleted", rarityName)
	hiveChanged(player, data)
end

-- Locks or unlocks a kind of bee. A locked kind cannot be deleted from the Inventory.
function BeeService.SetLock(player: Player, rarityName: any, locked: any)
	if typeof(rarityName) ~= "string" or GameConfig.Bees[rarityName] == nil or typeof(locked) ~= "boolean" then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Locked[rarityName] = if locked then true else nil
	DataService.Replicate(player)
end

-- AUTO ROLL ---------------------------------------------------------------------------

-- Buying Auto Roll at the sign next to the Queen. It is paid for once and kept for good;
-- the sign then leaves the home area.
function BeeService.BuyAutoRoll(player: Player)
	local data = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	if not data or not plot then
		return
	end
	if data.AutoRoll then
		return -- already bought (a second tap that arrived just after the buy)
	end
	local price = GameConfig.AutoRollPrice
	if data.Coins < price then
		Notifier.Send(player, "You need " .. NumberFormat.Short(price - data.Coins) .. " more Honey Coins for Auto Roll!", "bad")
		return
	end

	data.Coins -= price
	data.AutoRoll = true
	data.AutoRollOn = true
	nextAutoRollAt[player] = workspace:GetServerTimeNow() + 1 -- the first roll comes quickly, to show it off
	showRollArea(plot, standCount(player, data), true)
	Notifier.Send(player, "Auto Roll is yours! Your Queen now rolls by herself.", "good")
	DataService.Replicate(player)
	shareWaiting(player)
end

-- The Auto Roll button on the player's screen: switch it on or off.
function BeeService.SetAutoRoll(player: Player, on: any)
	if typeof(on) ~= "boolean" then
		return
	end
	local data = DataService.Get(player)
	if not data or not data.AutoRoll or data.AutoRollOn == on then
		return -- not bought, or nothing to change
	end
	data.AutoRollOn = on
	if on then
		nextAutoRollAt[player] = workspace:GetServerTimeNow() + 1
	end
	DataService.Replicate(player)
	shareWaiting(player)
end

-- The Keep Rolling button (it shows while Auto Roll is waiting for a bee the player asked
-- for): the Queen stops waiting for the bees on the stands now and rolls again.
function BeeService.KeepRolling(player: Player)
	local data = DataService.Get(player)
	if not data or not data.AutoRoll or not data.AutoRollOn then
		return
	end
	if not wantedOffer(player, data) then
		return -- she is not waiting (a second tap that arrived just after the first)
	end
	skipWait[player] = true
	nextAutoRollAt[player] = workspace:GetServerTimeNow() + 0.5
	shareWaiting(player)
end

-- Works out again whether Auto Roll is waiting (after the player changed which bees it
-- stops for in Settings).
function BeeService.RefreshWaiting(player: Player)
	-- only once the bees on the stands have hatched: until then nothing is shown
	local list = offers[player]
	local hatched = true
	if list then
		local now = workspace:GetServerTimeNow()
		for _, offer in list do
			if now < offer.ReadyAt then
				hatched = false
			end
		end
	end
	shareWaiting(player, not hatched)
end

-- Called a few times a second (from Main). A Queen rolls by herself when her owner has
-- Auto Roll switched on and is standing in the roll area.
function BeeService.StepAutoRoll()
	local now = workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		local data = DataService.Get(player)
		if data and data.AutoRoll and data.AutoRollOn and now >= (nextAutoRollAt[player] or 0) then
			local plot = PlotService.GetPlot(player)
			local area = plot and rollAreaOf(plot)
			local rollSpot = area and area.Queen:FindFirstChild("RollSpot")
			if wantedOffer(player, data) then
				-- waiting: a bee the player asked for is on a stand (see wantedOffer)
			elseif rollSpot and rollSpot:IsA("BasePart") and PlotService.IsNear(player, rollSpot, GameConfig.AutoRollRange) then
				BeeService.Roll(player)
			end
		end
	end
end

-- JOINING AND LEAVING ------------------------------------------------------------------

-- Puts a player's own stands and Auto Roll sign in their home area (after they join, and
-- after they buy More Rolls: the new stand appears and the others move over to make room).
function BeeService.RefreshStands(player: Player)
	local data = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	if data and plot then
		showRollArea(plot, standCount(player, data), data.AutoRoll == true)
	end
end

function BeeService.SetupPlayer(player: Player)
	BeeService.RefreshStands(player)
	restoreOffers(player) -- the bees that were on their stands when they left
	shareOffers(player)
end

function BeeService.CleanupPlayer(player: Player)
	offers[player] = nil
	nextRollAt[player] = nil
	nextAutoRollAt[player] = nil
	skipWait[player] = nil
end

-- An empty home area: every stand is emptied, and it shows one stand (in the middle) and
-- the Auto Roll sign.
function BeeService.ResetPlot(plot: Model)
	local area = rollAreaOf(plot)
	if area then
		for _, stand in area.Stands do
			clearOffer(stand)
		end
		writeAutoSign(area)
	end
	showRollArea(plot, 1, false)
end

return BeeService
