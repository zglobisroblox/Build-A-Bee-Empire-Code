--[[
	FirstMinutesSim - a pretend new player, played hundreds of times in a couple of seconds.

	This is a TOOL for trying out prices. It is not part of the game and never runs in it.
	It copies the numbers in GameConfig, lets you change some of them in the copy, and plays
	the start of the game the way a new player would who does exactly what the yellow hint
	says (the same rules as State.Objective in the client). Rolls and honey prices are random,
	so it plays many games and reports the middle result.

	Use it from the command bar or a tool script:
		local Sim = require(game.ServerStorage.BeeEmpireDev.FirstMinutesSim:Clone())
		local report = Sim.Many(Sim.Config(function(cfg) cfg.HiveLevels[2].Cost = 150 end), { Policy = "hint", Seconds = 300 }, 300)

	Policy "tutorial" = follows the yellow hint as it is in the game now (State.Objective): the
	                    hint is a tutorial that ends once the player has sold honey, bought an
	                    upgrade and swapped in a better bee. The game stops there, and
	                    First.tutorialDone says when that was.
	Policy "hint"     = follows the hint as it was BEFORE 2026-10-12 (it never ended, and with
	                    a full hive it only said "save for a bigger hive").
	Policy "roller"   = like "hint", but when there is nothing else to do and the hive is full
	                    it rolls for better bees instead of standing still.
	                    (RollFromHive = 2 in the options: only once the hive is level 2 or more.)

	The walking distances are measured from Plot1 and the time each action takes was measured
	in a real play-test on 2026-10-12 (see NOTES).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- (a fresh copy of the file is read each time, so numbers changed since Studio was opened are seen)
local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig:Clone())

local Sim = {}

local function copy(value)
	if typeof(value) ~= "table" then
		return value
	end
	local out = {}
	for key, item in value do
		out[key] = copy(item)
	end
	return out
end

-- A copy of GameConfig's numbers. tweak(cfg) may change the copy.
function Sim.Config(tweak)
	local cfg = {}
	for key, value in GameConfig do
		if typeof(value) ~= "function" then
			cfg[key] = copy(value)
		end
	end
	if tweak then
		tweak(cfg)
	end
	return cfg
end

-- Studs between the places a player stands, measured in Plot1.
function Sim.Distances()
	local plot = workspace.Plots.Plot1
	local home = plot.SpawnPad.Position
	local function point(part, away)
		local p = part.Position
		local dir = Vector3.new(home.X - p.X, 0, home.Z - p.Z)
		local s = p + dir.Unit * away
		return Vector3.new(s.X, 0, s.Z)
	end
	local places = {
		spawn = Vector3.new(home.X, 0, home.Z),
		queen = point(plot.Queen.RollSpot, 5),
		stand = point(plot.Queen.Stands.Stand1.BuySpot, 4),
		jars = point(plot.CollectStation.Table, 6),
		market = point(plot.Market.Counter, 6),
		shop = point(plot.Upgrades.UpgradeSpot, 4),
	}
	local distances = {}
	for a, pa in places do
		distances[a] = {}
		for b, pb in places do
			distances[a][b] = (pa - pb).Magnitude
		end
	end
	return distances
end

local function tidyPrice(price)
	if price < 100 then
		return math.floor(price + 0.5)
	end
	local unit = 10 ^ (math.floor(math.log10(price)) - 1)
	return math.floor(price / unit + 0.5) * unit
end

-- Plays one game. Returns what happened and when.
function Sim.Run(cfg, options, random)
	local seconds = options.Seconds or 300
	local policy = options.Policy or "hint"
	local think = options.Think or 0.6
	local D = options.Distances
	local dt = 0.1

	local beesOfRarity = {}
	for _, name in cfg.BeeOrder do
		local rarity = cfg.Bees[name].Rarity
		beesOfRarity[rarity] = beesOfRarity[rarity] or {}
		table.insert(beesOfRarity[rarity], name)
	end
	local cheapest = math.huge
	for _, bee in cfg.Bees do
		cheapest = math.min(cheapest, bee.Price)
	end
	local topRate = cfg.Bees[cfg.BeeOrder[#cfg.BeeOrder]].NectarPerSecond
	local function rateOf(name)
		return cfg.Bees[name].NectarPerSecond
	end

	local S = {
		t = 0, coins = cfg.StartingCoins, hive = 1, cells = {}, bag = {},
		levels = { Luck = 1, BeeSpeed = 1, Rolls = 1 },
		stored = 0, carried = 0, stock = 0, workers = {}, offers = {},
		at = "spawn", busyUntil = 0, pending = nil,
	}
	local M = { purchases = {}, first = {}, earned = 0, rolls = 0, checks = {} }
	local T = { Sold = false, Upgrade = false, BetterBee = false } -- the tutorial's three lessons
	local function mark(name)
		if not M.first[name] then
			M.first[name] = S.t
		end
	end
	local function purchase(what)
		table.insert(M.purchases, { t = S.t, what = what })
	end

	local function capacity()
		return cfg.HiveLevels[S.hive].Capacity
	end
	local function working()
		local count = 0
		for index = 1, capacity() do
			if S.cells[index] then
				count += 1
			end
		end
		return count
	end
	local function countBees()
		return working() + #S.bag
	end
	local function speed()
		return cfg.Upgrades.BeeSpeed.Levels[S.levels.BeeSpeed].Value
	end
	local function jarsPerSecond()
		local rate = 0
		for index = 1, capacity() do
			local bee = S.cells[index]
			if bee then
				rate += rateOf(bee.Name)
			end
		end
		return rate * speed()
	end
	local function luck()
		return 1 + (S.levels.Luck - 1) * cfg.Upgrades.Luck.Endless.Step
	end
	local function nextCost(id)
		if id == "Hive" then
			local hive = cfg.HiveLevels[S.hive + 1]
			return hive and hive.Cost
		end
		local upgrade = cfg.Upgrades[id]
		if upgrade.Endless then
			return tidyPrice(upgrade.Endless.FirstCost * upgrade.Endless.Growth ^ (S.levels[id] - 1))
		end
		local nextLevel = upgrade.Levels[S.levels[id] + 1]
		return nextLevel and nextLevel.Cost
	end

	local function syncWorkers()
		local want = math.max(1, math.ceil(working() * cfg.WorkersPerBee))
		while #S.workers < want do
			table.insert(S.workers, { State = "Idle", LegEnd = 0, Amount = 0 })
		end
		while #S.workers > want do
			local gone = table.remove(S.workers)
			S.stock += gone.Amount
		end
	end
	syncWorkers()

	local function rollOne()
		local total = 0
		for _, rarity in cfg.RarityOrder do
			if beesOfRarity[rarity] then
				total += cfg.Rarities[rarity].Chance
			end
		end
		local left = total
		local chances = {}
		for index = #cfg.RarityOrder, 1, -1 do
			local rarity = cfg.RarityOrder[index]
			local chance = 0
			if beesOfRarity[rarity] then
				chance = if index == 1 then left else math.min(left, cfg.Rarities[rarity].Chance * math.max(1, luck()))
			end
			chances[rarity] = chance
			left -= chance
		end
		local pick = random:NextNumber() * total
		local rolled = nil
		for _, rarity in cfg.RarityOrder do
			pick -= chances[rarity]
			if pick <= 0 and chances[rarity] > 0 then
				rolled = rarity
				break
			end
		end
		local list = rolled and beesOfRarity[rolled]
		if not list then
			return cfg.BeeOrder[1]
		end
		local totalShare = 0
		for _, name in list do
			totalShare += cfg.Bees[name].Share or 1
		end
		local pickBee = random:NextNumber() * totalShare
		for _, name in list do
			pickBee -= cfg.Bees[name].Share or 1
			if pickBee <= 0 then
				return name
			end
		end
		return list[#list]
	end

	local function newPrice()
		local pick = random:NextNumber() * 100
		for _, band in cfg.SellPriceBands do
			pick -= band.Chance
			if pick <= 0 then
				local steps = math.floor((band.Max - band.Min) / cfg.SellPriceStep + 0.5)
				return band.Min + random:NextInteger(0, steps) * cfg.SellPriceStep
			end
		end
		return 2.5
	end
	local price = newPrice()
	local priceUntil = random:NextNumber() * cfg.SellPriceSeconds

	-- THE HINT'S QUESTIONS (the same ones State.Objective asks) --------------------------
	local function wouldHelp(name)
		if working() < capacity() then
			return true
		end
		for index = 1, capacity() do
			local bee = S.cells[index]
			if bee and rateOf(bee.Name) < rateOf(name) then
				return true
			end
		end
		return false
	end
	local function bestOffer()
		local bestIndex, bestRate = nil, -1
		for index, offer in S.offers do
			local rate = rateOf(offer.Name)
			if S.coins >= offer.Price and rate > bestRate and wouldHelp(offer.Name) then
				bestIndex, bestRate = index, rate
			end
		end
		return bestIndex
	end
	local function betterWaiting()
		local rates, current = {}, 0
		for index = 1, capacity() do
			local bee = S.cells[index]
			if bee then
				table.insert(rates, rateOf(bee.Name))
				current += rateOf(bee.Name)
			end
		end
		for _, name in S.bag do
			table.insert(rates, rateOf(name))
		end
		table.sort(rates, function(a, b)
			return a > b
		end)
		local best = 0
		for index = 1, math.min(capacity(), #rates) do
			best += rates[index]
		end
		return best > current + 1e-6
	end
	local function rollHelps()
		if working() < capacity() then
			return true
		end
		for index = 1, capacity() do
			local bee = S.cells[index]
			if bee and rateOf(bee.Name) < topRate then
				return true
			end
		end
		return false
	end
	local function weakestRate()
		local weakest = math.huge
		for index = 1, capacity() do
			local bee = S.cells[index]
			if bee then
				weakest = math.min(weakest, rateOf(bee.Name))
			end
		end
		return weakest
	end
	-- the cheapest bee that is better than the weakest one working now
	local function cheapestHelpful()
		local weakest = weakestRate()
		local best = math.huge
		for _, bee in cfg.Bees do
			if bee.NectarPerSecond > weakest then
				best = math.min(best, bee.Price)
			end
		end
		return best
	end
	local function worthVisit()
		local nextHive = cfg.HiveLevels[S.hive + 1]
		local ids = {}
		for _, id in cfg.UpgradeOrder do
			local upgrade = cfg.Upgrades[id]
			if id == "Hive" or not upgrade.NeedsAutoRoll then
				local cost = nextCost(id)
				if cost and S.coins >= cost then
					local endless = id ~= "Hive" and upgrade.Endless ~= nil
					local small = nextHive == nil or cost <= nextHive.Cost * cfg.EndlessHintShare
					if small or not endless then
						table.insert(ids, id)
					end
				end
			end
		end
		return ids
	end

	-- THE THINGS A PLAYER DOES -------------------------------------------------------------
	local function go(place)
		local distance = D[S.at][place]
		S.at = place
		return if distance > 1 then distance / cfg.WalkSpeed + 0.15 else 0
	end
	local function act(duration, effect)
		S.busyUntil = S.t + duration
		S.pending = effect
	end
	local function placeBee(index, name)
		S.cells[index] = { Name = name, Start = S.t + ((index - 1) % 6) * 0.6, Delivered = 0 }
		syncWorkers()
		if working() >= 2 then
			mark("bees2")
		end
		if working() >= 4 then
			mark("bees4")
		end
		local rarity = cfg.Bees[name].Rarity
		if rarity ~= cfg.RarityOrder[1] then
			mark("firstUncommonUp")
		end
		if rarity ~= cfg.RarityOrder[1] and rarity ~= cfg.RarityOrder[2] then
			mark("firstRareUp")
		end
	end
	local function doRoll()
		local walk = go("queen")
		act(walk + think + 0.35 + 2.1, function()
			local stands = cfg.Upgrades.Rolls.Levels[S.levels.Rolls].Value
			local starter = cfg.FirstBeeFree and countBees() == 0
			S.offers = {}
			for index = 1, stands do
				if starter and index == 1 then
					S.offers[index] = { Name = cfg.BeeOrder[1], Price = 0 }
				else
					local name = rollOne()
					S.offers[index] = { Name = name, Price = cfg.Bees[name].Price }
					local rarity = cfg.Bees[name].Rarity
					if rarity ~= cfg.RarityOrder[1] and rarity ~= cfg.RarityOrder[2] then
						mark("sawRareUp") -- a Rare or better hatched on a stand (bought or not)
					end
				end
			end
			M.rolls += 1
		end)
	end
	local function doBuy(index)
		local walk = go("stand")
		act(walk + think + 0.55, function()
			local offer = S.offers[index]
			if not offer then
				return
			end
			local cost = offer.Price
			if cost == 0 and countBees() > 0 then
				cost = cfg.Bees[offer.Name].Price
			end
			if S.coins < cost then
				return
			end
			local free = nil
			for cellIndex = 1, capacity() do
				if not S.cells[cellIndex] then
					free = cellIndex
					break
				end
			end
			if not free and #S.bag >= cfg.MaxBeesInBag then
				return
			end
			S.coins -= cost
			S.offers[index] = nil
			if free then
				placeBee(free, offer.Name)
			else
				table.insert(S.bag, offer.Name)
			end
			purchase("bee:" .. offer.Name)
		end)
	end
	local function doEquip()
		act(think * 2 + 0.4, function()
			while #S.bag > 0 do
				local bagIndex, bagRate = nil, -1
				for index, name in S.bag do
					if rateOf(name) > bagRate then
						bagIndex, bagRate = index, rateOf(name)
					end
				end
				local target, targetRate = nil, math.huge
				for cellIndex = 1, capacity() do
					local bee = S.cells[cellIndex]
					if not bee then
						target, targetRate = cellIndex, -1
						break
					elseif rateOf(bee.Name) < targetRate then
						target, targetRate = cellIndex, rateOf(bee.Name)
					end
				end
				if not target or bagRate <= targetRate then
					break
				end
				local name = table.remove(S.bag, bagIndex)
				local replaced = S.cells[target]
				placeBee(target, name)
				if replaced then
					table.insert(S.bag, replaced.Name)
					T.BetterBee = true
				end
			end
		end)
	end
	local function doSellBag()
		act(5, function()
			table.clear(S.bag) -- (spare bees are deleted for nothing since 2026-10-12)
		end)
	end
	local function doGrab()
		local walk = go("jars")
		act(walk + think + 0.35, function()
			S.carried += S.stored
			S.stored = 0
		end)
	end
	local function doSell()
		local walk = go("market")
		act(walk + think + 0.35, function()
			local earned = math.floor(S.carried * cfg.JarValue * price + 0.5)
			S.coins += earned
			M.earned += earned
			S.carried = 0
			mark("firstSale")
			T.Sold = true
		end)
	end
	local function shopStep()
		local id = worthVisit()[1]
		if not id then
			return
		end
		S.coins -= nextCost(id)
		if id == "Hive" then
			S.hive += 1
			mark("hive" .. S.hive)
		else
			S.levels[id] += 1
			if id == "BeeSpeed" then
				-- every bee starts a fresh trip at the new speed (as HiveService does)
				for index, bee in S.cells do
					bee.Start = S.t + ((index - 1) % 6) * 0.6
					bee.Delivered = 0
				end
			end
			mark(id .. S.levels[id])
		end
		purchase("up:" .. id)
		T.Upgrade = true
		if policy ~= "tutorial" and #worthVisit() > 0 then
			act(think + 0.4, shopStep)
		end
	end
	local function doShop()
		local walk = go("shop")
		act(walk + think * 2 + 0.4, shopStep)
	end

	local function choose()
		local bagTotal = #S.bag
		local empty = capacity() - working()
		local placed = working()
		local rate = jarsPerSecond()
		local worthIt = math.clamp(math.floor(rate * 8), 1, 20)
		local offerIndex = bestOffer()
		local helpfulWaiting, savingFor = false, false
		local income = rate * cfg.JarValue * 2.5
		for _, offer in S.offers do
			if wouldHelp(offer.Name) then
				helpfulWaiting = true
				if offer.Price > S.coins and offer.Price - S.coins <= income * (options.SaveSeconds or cfg.SaveForBeeSeconds or 45) then
					savingFor = true
				end
			end
		end
		local priceHigh = price >= cfg.SellPriceHigh
		local nextHive = cfg.HiveLevels[S.hive + 1]
		-- the "roller": nothing else to do, the hive is full, and a better bee is within reach
		local rollIdle = policy == "roller" and S.hive >= (options.RollFromHive or 1) and empty == 0
			and nextHive ~= nil and rollHelps() and S.coins >= cheapestHelpful() and not savingFor

		if bagTotal >= cfg.MaxBeesInBag then
			doSellBag()
		elseif bagTotal == 0 and placed == 0 then
			if S.offers[1] then
				doBuy(1)
			else
				doRoll()
			end
		elseif bagTotal > 0 and empty > 0 then
			doEquip()
		elseif betterWaiting() then
			doEquip()
		elseif priceHigh and S.carried > 0 then
			doSell()
		elseif priceHigh and S.stored >= worthIt then
			doGrab()
		elseif offerIndex then
			doBuy(offerIndex)
		elseif empty == 0 and nextHive and S.coins >= nextHive.Cost then
			doShop()
		elseif empty > 0 and S.coins >= cheapest then
			doRoll()
		elseif not nextHive and rollHelps() and S.coins >= cheapest and not helpfulWaiting then
			doRoll()
		elseif S.carried >= worthIt or (S.carried > 0 and S.stored < worthIt) then
			doSell()
		elseif S.stored >= worthIt then
			doGrab()
		elseif policy == "tutorial" then
			if not T.Upgrade then
				if #worthVisit() > 0 then
					doShop()
				end
			elseif empty == 0 and rollHelps() and not savingFor and S.coins >= cheapestHelpful() then
				doRoll() -- "Roll for better bees!"
			end
		elseif rollIdle and options.RollFirst then
			doRoll() -- (RollFirst: rolling for better bees comes before the "you can afford an upgrade" hint)
		elseif #worthVisit() > 0 then
			doShop()
		elseif rollIdle then
			doRoll()
		end
	end

	local checkTimes = options.Checks or { 180, 300 }
	local nextCheck = 1
	while S.t < seconds do
		if S.t >= priceUntil then
			price = newPrice()
			priceUntil += cfg.SellPriceSeconds
		end

		-- honey: workers drop off, bees come home, idle workers pick up
		for _, worker in S.workers do
			if worker.State == "Carry" then
				if S.t >= worker.LegEnd then
					S.stored += worker.Amount
					worker.Amount = 0
					worker.State = "Return"
					worker.LegEnd = S.t + cfg.WorkerReturnSeconds
				end
			elseif worker.State == "Return" and S.t >= worker.LegEnd then
				worker.State = "Idle"
			end
		end
		local tripSeconds = cfg.TripSeconds / speed()
		for index = 1, capacity() do
			local bee = S.cells[index]
			if bee then
				local finished = math.floor((S.t - bee.Start) / tripSeconds)
				if finished > bee.Delivered then
					S.stock += (finished - bee.Delivered) * rateOf(bee.Name) * cfg.TripSeconds
					bee.Delivered = finished
				end
			end
		end
		local whole = math.floor(S.stock)
		if whole > 0 then
			local idle = {}
			for _, worker in S.workers do
				if worker.State == "Idle" then
					table.insert(idle, worker)
				end
			end
			for index, worker in idle do
				if whole <= 0 then
					break
				end
				local load = math.ceil(whole / (#idle - index + 1))
				whole -= load
				S.stock -= load
				worker.State = "Carry"
				worker.Amount = load
				worker.LegEnd = S.t + cfg.WorkerCarrySeconds
			end
		end

		if S.pending and S.t >= S.busyUntil then
			local effect = S.pending
			S.pending = nil
			effect()
		end
		if policy == "tutorial" and T.Sold and T.Upgrade and T.BetterBee then
			mark("tutorialDone")
			break -- the hint is gone: what happens next is up to the player
		end
		if not S.pending then
			choose()
		end

		if checkTimes[nextCheck] and S.t >= checkTimes[nextCheck] then
			local kinds = {}
			for index = 1, capacity() do
				local bee = S.cells[index]
				if bee then
					kinds[bee.Name] = (kinds[bee.Name] or 0) + 1
				end
			end
			M.checks[checkTimes[nextCheck]] = {
				Rate = jarsPerSecond(), Hive = S.hive, Luck = S.levels.Luck, Speed = S.levels.BeeSpeed,
				Rolls = S.levels.Rolls, Coins = S.coins, Earned = M.earned, Bees = working(), Kinds = kinds,
				RollCount = M.rolls,
			}
			nextCheck += 1
		end
		S.t += dt
	end
	return M
end

local function middle(list)
	if #list == 0 then
		return nil
	end
	table.sort(list)
	return list[math.ceil(#list / 2)]
end

-- Plays many games and returns the middle result of each thing measured.
--   First[name]  = { Time = middle time in seconds (nil if fewer than half got there), Share = part of games that got there }
--   Checks[time] = middle jars per second, hive level, luck level... at that time
--   Buys180      = middle number of things bought or got in the first 3 minutes
--   Gap180       = middle longest wait between two of them in the first 3 minutes
function Sim.Many(cfg, options, games, seed)
	options = table.clone(options)
	options.Distances = options.Distances or Sim.Distances()
	local firsts, checks = {}, {}
	local buys, gaps = {}, {}
	local window = options.Window or 180
	for number = 1, games do
		local result = Sim.Run(cfg, options, Random.new((seed or 1000) + number))
		for name, when in result.first do
			firsts[name] = firsts[name] or {}
			table.insert(firsts[name], when)
		end
		for when, check in result.checks do
			checks[when] = checks[when] or {}
			for key, value in check do
				if typeof(value) == "number" then
					checks[when][key] = checks[when][key] or {}
					table.insert(checks[when][key], value)
				end
			end
		end
		local count, last, longest = 0, 0, 0
		for _, bought in result.purchases do
			if bought.t <= window then
				count += 1
				longest = math.max(longest, bought.t - last)
				last = bought.t
			end
		end
		longest = math.max(longest, window - last)
		table.insert(buys, count)
		table.insert(gaps, longest)
		if number % 20 == 0 then
			task.wait()
		end
	end
	local report = { First = {}, Checks = {}, Buys180 = middle(buys), Gap180 = middle(gaps) }
	for name, list in firsts do
		local share = #list / games
		-- the middle game overall: games that never got there count as "later than everything"
		table.sort(list)
		local index = math.ceil(games / 2)
		report.First[name] = { Time = list[index], Share = share }
	end
	for when, keys in checks do
		report.Checks[when] = {}
		for key, list in keys do
			report.Checks[when][key] = middle(list)
		end
	end
	return report
end

-- "1:09" from 69 seconds
function Sim.Clock(secondsIn)
	if not secondsIn then
		return "later"
	end
	local whole = math.floor(secondsIn + 0.5)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

return Sim
