--[[
	DataService - loads and saves each player's progress.

	Saved: Honey Coins, hive level, upgrade levels, jars (carried and waiting at the
	station), bees in the bag, bees working in the hive, Auto Roll (whether it was
	bought, and whether it is switched on), what the player chose in Settings, how far
	they are through the tutorial (the yellow hint), when they were last here, and any
	offline honey they have not collected yet.
	(Passes are NOT saved here: Roblox keeps the record of what a player has bought. Only
	"the Starter Pack has been opened" is saved, so it is handed out once.)

	Safety rules:
	- Every call to Roblox's save system is wrapped so an error can never crash the game.
	- Failed loads/saves are retried.
	- If a player's save could NOT be loaded, we never write over it.
	- Loaded data is rebuilt and checked, so a broken save cannot break the game.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)
local Upgrades = require(ReplicatedStorage.BeeEmpire.Upgrades)
local PassService = require(script.Parent.PassService)

local DataService = {}

local KEY_PREFIX = "Player_"
local MAX_ATTEMPTS = if RunService:IsStudio() then 1 else 3
local MAX_COINS = 1e15

-- Saves are numbered so old ones can be brought up to date when they load:
--   1 = Queen's Luck had 5 big levels (x1, x1.5, x2, x3, x4)
--   2 = Queen's Luck has endless small levels (GameConfig.Upgrades.Luck.Endless)
local SAVE_VERSION = 2
-- What an old luck level becomes: the coins that level cost (500, 3,000, 13,000 and 53,000 in
-- all) buy this many of the new small levels. Nobody loses luck: x1.5 stays x1.5, and the
-- others come out a little better (x2 > x2.3, x3 > x3.3, x4 > x4.3).
local OLD_LUCK_LEVELS = { 1, 6, 14, 24, 34 }

-- [Player] = { Data = {...}, CanSave = boolean, Releasing = boolean }
local profiles = {}

-- [UserId] = true while that player's final save is still being written
local savingUsers = {}

local store = nil
local storeChecked = false

local function getStore()
	if not storeChecked then
		storeChecked = true
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(GameConfig.DataStoreName)
		end)
		if ok then
			store = result
		else
			warn("[BeeEmpire] Save system unavailable: " .. tostring(result))
		end
	end
	return store
end

-- What a new player's Settings window starts with.
local function defaultSettings()
	local stopFor = {}
	for _, rarityName in GameConfig.AutoRollStopDefault do
		if GameConfig.Rarities[rarityName] then
			stopFor[rarityName] = true
		end
	end
	return {
		Music = GameConfig.DefaultMusicVolume, -- 0 to 100
		Sounds = GameConfig.DefaultSoundVolume, -- 0 to 100
		StopFor = stopFor, -- the kinds of bee Auto Roll waits for: { Epic = true, ... }
		Luck = 1, -- the Queen's Luck level in use (a player may use less luck than they own)
		AutoSell = true, -- Auto Sell (a pass) is switched on: its owner can switch it off in the Shop window
		OtherBees = true, -- other players' flying bees show on this player's screen (they may hide them in Settings)
	}
end

local function defaultData()
	local boosts = {}
	for kind in GameConfig.Boosts do
		boosts[kind] = 0
	end
	return {
		Version = SAVE_VERSION,
		Coins = GameConfig.StartingCoins,
		HiveLevel = 1,
		Upgrades = {}, -- levels bought at the Upgrade Shop: { Luck = 2, BeeSpeed = 1, ... }
		JarsCarried = 0,
		JarsStored = 0,
		AutoRoll = false, -- true once Auto Roll has been bought (it is bought once and kept)
		AutoRollOn = false, -- whether Auto Roll is switched on right now
		Settings = defaultSettings(), -- the Settings window: volumes, Auto Roll's stop list, luck in use
		Bees = {}, -- bees in the bag: { { Rarity = "Common" }, ... } ("Rarity" holds the bee's name in GameConfig.Bees)
		Cells = {}, -- bees working in the hive, keyed by slot number as text: { ["1"] = { Rarity = "Rare" } }
		-- bees waiting on the honeycomb stands after a roll, keyed by stand number as text:
		-- { ["2"] = { Rarity = "Epic" } }. Free = true marks the free starter bee.
		Offers = {},
		-- the tutorial (the yellow hint and the arrow): which of its three lessons are done.
		-- Done = true once all three are: the hint is then never shown again. (TutorialService)
		Tutorial = { Sold = false, Upgrade = false, BetterBee = false, Done = false },
		-- when this save was last written (os.time(), in seconds). 0 = never. The time between
		-- this and the next join is the time the player was away. (OfflineService)
		LastSeen = 0,
		-- offline honey the bees made that has not been collected yet, and how much time away
		-- it stands for (the "Welcome Back!" window shows both)
		Offline = { Jars = 0, Seconds = 0 },
		-- Daily Rewards: how many have been collected in all (the next one is number
		-- Day + 1, counting round the list in GameConfig.DailyRewards), and the time
		-- (os.time(), in seconds) from which the next one can be collected. 0 = straight away.
		Daily = { Day = 0, NextAt = 0 },
		-- boosts: seconds left of each one ({ Honey = 0, Luck = 0 }). They only run down while
		-- the player is in the game. (BoostService)
		Boosts = boosts,
		-- boosts waiting in the Inventory, counted per kind and length: { ["Honey_10"] = 2 }
		-- is two Double Honey boosts of 10 minutes each (GameConfig.BoostItemKey)
		BoostItems = {},
		-- kinds of bee the player has locked, so they cannot be deleted: { Epic = true }
		Locked = {},
		-- true once the Starter Pack (a pass) has handed out its bee and boosts
		StarterPackOpened = false,
	}
end

local function cleanNumber(value, fallback, maximum)
	if typeof(value) ~= "number" or value ~= value or value < 0 then
		return fallback
	end
	return math.min(math.floor(value), maximum)
end

local function cleanBee(bee)
	if typeof(bee) == "table" and typeof(bee.Rarity) == "string" and GameConfig.Bees[bee.Rarity] then
		return { Rarity = bee.Rarity }
	end
	return nil
end

-- Rebuilds saved data from scratch, keeping only values that make sense.
local function sanitize(saved)
	local data = defaultData()
	if typeof(saved) ~= "table" then
		return data
	end

	data.Coins = cleanNumber(saved.Coins, data.Coins, MAX_COINS)
	data.HiveLevel = math.max(1, cleanNumber(saved.HiveLevel, 1, #GameConfig.HiveLevels))
	local hive = GameConfig.GetHive(data.HiveLevel)
	local savedUpgrades = if typeof(saved.Upgrades) == "table" then saved.Upgrades else {}
	for id in GameConfig.Upgrades do
		data.Upgrades[id] = Upgrades.CleanLevel(id, savedUpgrades[id])
	end
	-- an old save: turn its big luck levels into the new small ones (this happens once,
	-- because the rebuilt data carries the new save number)
	local oldLuck = cleanNumber(saved.Version, 1, SAVE_VERSION) < 2
	local function convertLuck(level: number): number
		return OLD_LUCK_LEVELS[math.clamp(level, 1, #OLD_LUCK_LEVELS)]
	end
	if oldLuck then
		data.Upgrades.Luck = convertLuck(data.Upgrades.Luck)
	end
	-- The Backpack upgrade was removed (carrying is unlimited now). Give back what was paid for it.
	-- This happens once: the rebuilt data no longer has a Backpack entry.
	local OLD_BACKPACK_COSTS = { 0, 150, 800, 3500, 15000, 60000 }
	for level = 2, cleanNumber(savedUpgrades.Backpack, 1, #OLD_BACKPACK_COSTS) do
		data.Coins = math.min(data.Coins + OLD_BACKPACK_COSTS[level], MAX_COINS)
	end
	data.JarsCarried = cleanNumber(saved.JarsCarried, 0, MAX_COINS) -- no carry limit; just a sanity cap
	data.JarsStored = cleanNumber(saved.JarsStored, 0, MAX_COINS) -- no limit on waiting honey; just a sanity cap
	data.AutoRoll = saved.AutoRoll == true
	data.AutoRollOn = data.AutoRoll and saved.AutoRollOn == true

	-- Settings. (A save from before the Settings window existed has none: it gets the
	-- starting ones, and all the luck the player owns.)
	local savedSettings = if typeof(saved.Settings) == "table" then saved.Settings else {}
	data.Settings.Music = cleanNumber(savedSettings.Music, data.Settings.Music, 100)
	data.Settings.Sounds = cleanNumber(savedSettings.Sounds, data.Settings.Sounds, 100)
	if typeof(savedSettings.StopFor) == "table" then
		data.Settings.StopFor = {}
		for _, rarityName in GameConfig.RarityOrder do
			if savedSettings.StopFor[rarityName] == true then
				data.Settings.StopFor[rarityName] = true
			end
		end
	end
	local ownedLuck = data.Upgrades.Luck
	local luckInUse = cleanNumber(savedSettings.Luck, ownedLuck, MAX_COINS)
	if oldLuck and typeof(savedSettings.Luck) == "number" then
		luckInUse = convertLuck(math.max(1, luckInUse)) -- the level they had chosen, as a new level
	end
	data.Settings.Luck = math.clamp(luckInUse, 1, ownedLuck)
	data.Settings.AutoSell = savedSettings.AutoSell ~= false
	data.Settings.OtherBees = savedSettings.OtherBees ~= false

	local function addToBag(bee)
		-- (the hard limit: whether THIS player may keep more than GameConfig.MaxBeesInBag is the
		-- Infinite Inventory pass, which BeeService checks whenever a bee is added)
		if bee and #data.Bees < GameConfig.InfiniteBagLimit then
			table.insert(data.Bees, bee)
		end
	end

	-- the bees that were waiting on the honeycomb stands
	if typeof(saved.Offers) == "table" then
		for key, bee in saved.Offers do
			local index = tonumber(key)
			local clean = cleanBee(bee)
			if clean and index and index % 1 == 0 and index >= 1 and index <= GameConfig.RollStandSpots then
				clean.Free = if bee.Free == true then true else nil
				data.Offers[tostring(index)] = clean
			end
		end
	end

	if typeof(saved.Bees) == "table" then
		for _, bee in saved.Bees do
			addToBag(cleanBee(bee))
		end
	end

	if typeof(saved.Cells) == "table" then
		for key, bee in saved.Cells do
			local index = tonumber(key)
			local clean = cleanBee(bee)
			if clean then
				if index and index % 1 == 0 and index >= 1 and index <= hive.Capacity then
					data.Cells[tostring(index)] = clean
				else
					addToBag(clean) -- that hive slot does not exist, so the bee goes back in the bag
				end
			end
		end
	end

	-- When the player was last here, and offline honey still waiting to be collected.
	-- (A save from before offline honey existed has neither: the first time away is not counted.)
	data.LastSeen = cleanNumber(saved.LastSeen, 0, 1e11)
	if typeof(saved.Offline) == "table" then
		data.Offline.Jars = cleanNumber(saved.Offline.Jars, 0, MAX_COINS)
		data.Offline.Seconds = cleanNumber(saved.Offline.Seconds, 0, GameConfig.OfflineMaxHours * 3600)
	end

	-- Daily Rewards and boosts.
	if typeof(saved.Daily) == "table" then
		data.Daily.Day = cleanNumber(saved.Daily.Day, 0, 1e9)
		-- (never further away than one full wait, in case the wait is made shorter in GameConfig)
		data.Daily.NextAt = math.min(cleanNumber(saved.Daily.NextAt, 0, 1e11), os.time() + GameConfig.DailyRewardHours * 3600)
	end
	local savedBoosts = if typeof(saved.Boosts) == "table" then saved.Boosts else {}
	for kind in GameConfig.Boosts do
		data.Boosts[kind] = cleanNumber(savedBoosts[kind], 0, GameConfig.BoostMaxMinutes * 60)
	end

	-- The Inventory: boosts waiting to be used, and the kinds of bee that are locked.
	if typeof(saved.BoostItems) == "table" then
		for key, count in saved.BoostItems do
			local kind = GameConfig.ReadBoostItemKey(key)
			local clean = cleanNumber(count, 0, 999)
			if kind and clean > 0 then
				data.BoostItems[key] = clean
			end
		end
	end
	if typeof(saved.Locked) == "table" then
		for beeName, locked in saved.Locked do
			if locked == true and typeof(beeName) == "string" and GameConfig.Bees[beeName] then
				data.Locked[beeName] = true
			end
		end
	end

	data.StarterPackOpened = saved.StarterPackOpened == true

	-- The tutorial. A save from before the tutorial existed has no record of it, so we look
	-- at what the player owns instead: anyone who already has an upgrade and a better bee
	-- has plainly learned the game, and is not shown the hint again.
	local savedTutorial = saved.Tutorial
	if typeof(savedTutorial) == "table" then
		data.Tutorial.Sold = savedTutorial.Sold == true
		data.Tutorial.Upgrade = savedTutorial.Upgrade == true
		data.Tutorial.BetterBee = savedTutorial.BetterBee == true
		data.Tutorial.Done = savedTutorial.Done == true
	else
		local upgraded = data.HiveLevel > 1 or data.AutoRoll
		for id in GameConfig.Upgrades do
			if data.Upgrades[id] > 1 then
				upgraded = true
			end
		end
		local starter = GameConfig.BeeOrder[1]
		local betterBee = false
		for _, bee in data.Cells do
			if bee.Rarity ~= starter then
				betterBee = true
			end
		end
		for _, bee in data.Bees do
			if bee.Rarity ~= starter then
				betterBee = true
			end
		end
		data.Tutorial.Upgrade = upgraded
		data.Tutorial.BetterBee = betterBee
		data.Tutorial.Sold = upgraded or betterBee or data.Coins > GameConfig.StartingCoins
	end
	if data.Tutorial.Sold and data.Tutorial.Upgrade and data.Tutorial.BetterBee then
		data.Tutorial.Done = true
	end

	return data
end

local function saveProfile(userId, profile)
	if not profile.CanSave then
		return true
	end
	local dataStore = getStore()
	if not dataStore then
		return false
	end

	profile.Data.LastSeen = os.time() -- "last here": the next join measures the time away from this
	for attempt = 1, MAX_ATTEMPTS do
		local ok, err = pcall(function()
			dataStore:SetAsync(KEY_PREFIX .. userId, profile.Data, { userId })
		end)
		if ok then
			return true
		end
		warn(string.format("[BeeEmpire] Save attempt %d failed for user %d: %s", attempt, userId, tostring(err)))
		if attempt < MAX_ATTEMPTS then
			task.wait(attempt * 2)
		end
	end
	return false
end

-- Loads a player's data. Returns true when the player is ready to play.
function DataService.Load(player: Player): boolean
	local dataStore = getStore()
	local loaded, saved = false, nil

	-- If they just left this same server, wait for that save to finish so we load the newest data.
	local waitUntil = os.clock() + 15
	while savingUsers[player.UserId] and os.clock() < waitUntil do
		task.wait(0.2)
	end

	if dataStore then
		for attempt = 1, MAX_ATTEMPTS do
			local ok, result = pcall(function()
				return dataStore:GetAsync(KEY_PREFIX .. player.UserId)
			end)
			if ok then
				loaded = true
				saved = result
				break
			end
			warn(string.format("[BeeEmpire] Load attempt %d failed for %s: %s", attempt, player.Name, tostring(result)))
			if attempt < MAX_ATTEMPTS then
				task.wait(attempt * 2)
			end
		end
	end

	if not player:IsDescendantOf(Players) then
		return false -- they left while we were loading
	end

	local profile
	if loaded then
		profile = { Data = sanitize(saved), CanSave = true, Releasing = false }
		-- how long they were away: from the last time their save was written until now
		local lastSeen = profile.Data.LastSeen
		profile.AwaySeconds = if lastSeen > 0 then math.max(0, os.time() - lastSeen) else 0
	elseif RunService:IsStudio() then
		warn("[BeeEmpire] SAVING IS OFF for this test. Publish the place and turn on 'Enable Studio Access to API Services' to test saving.")
		profile = { Data = defaultData(), CanSave = false, Releasing = false }
	else
		return false
	end
	profiles[player] = profile

	-- The leaderboard in the top-right corner of the screen.
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = profile.Data.Coins
	coins.Parent = leaderstats
	leaderstats.Parent = player

	DataService.Replicate(player)
	return true
end

-- Returns the live data table for a player, or nil if it has not loaded yet.
function DataService.Get(player: Player)
	local profile = profiles[player]
	if profile and not profile.Releasing then
		return profile.Data
	end
	return nil
end

-- What a boost multiplies by for this player right now: the boost's Multiplier while they
-- have some of it left, otherwise 1. kind is "Honey" or "Luck" (GameConfig.Boosts).
function DataService.BoostMultiplier(data, kind: string): number
	local boost = GameConfig.Boosts[kind]
	if boost and (data.Boosts[kind] or 0) > 0 then
		return boost.Multiplier
	end
	return 1
end

-- How many seconds the player was away before this visit. It is handed out ONCE (the
-- second call gives 0), so the same time away can never be paid for twice.
function DataService.TakeAwaySeconds(player: Player): number
	local profile = profiles[player]
	if not profile then
		return 0
	end
	local away = profile.AwaySeconds or 0
	profile.AwaySeconds = 0
	return away
end

-- The level of an upgrade in a player's data ("Hive" is the beehive level).
function DataService.UpgradeLevel(data, id: string): number
	if id == "Hive" then
		return data.HiveLevel
	end
	return Upgrades.CleanLevel(id, data.Upgrades[id])
end

-- What an upgrade currently gives a player (luck multiplier, speed multiplier...).
function DataService.UpgradeValue(data, id: string): number
	return Upgrades.ValueAt(id, DataService.UpgradeLevel(data, id))
end

-- The Queen's Luck LEVEL a player is using. It is the level they own unless they turned it
-- down in Settings (it can never be more than they own).
function DataService.LuckLevelInUse(data): number
	local owned = DataService.UpgradeLevel(data, "Luck")
	local chosen = data.Settings and data.Settings.Luck
	if typeof(chosen) ~= "number" or chosen ~= chosen then
		return owned
	end
	return math.clamp(math.floor(chosen), 1, owned)
end

-- The luck multiplier that level gives: this is what a roll uses.
function DataService.LuckInUse(data): number
	return Upgrades.ValueAt("Luck", DataService.LuckLevelInUse(data))
end

-- Copies the numbers the HUD needs onto the Player so their screen can show them.
function DataService.Replicate(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local data = profile.Data

	local placed = 0
	local jarsPerSecond = 0
	for _, bee in data.Cells do
		placed += 1
		jarsPerSecond += GameConfig.Bees[bee.Rarity].NectarPerSecond
	end

	-- What is in the bag (how many of each rarity) and what is in each cell.
	local bagCounts = {}
	for _, bee in data.Bees do
		bagCounts[bee.Rarity] = (bagCounts[bee.Rarity] or 0) + 1
	end
	for _, beeName in GameConfig.BeeOrder do
		player:SetAttribute("Bag_" .. beeName, bagCounts[beeName] or 0)
	end
	for cellIndex = 1, GameConfig.MaxHiveCapacity do
		local bee = data.Cells[tostring(cellIndex)]
		player:SetAttribute("Cell_" .. cellIndex, if bee then bee.Rarity else "")
	end
	-- faster bees (the Bee Speed upgrade) bring jars home more often
	-- (a Double Honey boost shows in this number too)
	-- (and so does the VIP pass's extra honey)
	player:SetAttribute("JarsPerSecond", jarsPerSecond * DataService.UpgradeValue(data, "BeeSpeed") * DataService.BoostMultiplier(data, "Honey") * PassService.HoneyMultiplier(player))
	player:SetAttribute("BagLimit", PassService.BagLimit(player)) -- spare bees the Inventory holds (the Infinite Inventory pass)
	player:SetAttribute("StarterPackOpened", data.StarterPackOpened == true)

	local hive = GameConfig.GetHive(data.HiveLevel)
	player:SetAttribute("HiveLevel", data.HiveLevel)
	player:SetAttribute("HiveCapacity", hive.Capacity)
	for id in GameConfig.Upgrades do
		player:SetAttribute("Up_" .. id, DataService.UpgradeLevel(data, id))
	end

	player:SetAttribute("AutoRoll", data.AutoRoll == true)
	player:SetAttribute("AutoRollOn", data.AutoRoll == true and data.AutoRollOn == true)

	-- the Settings window
	local settings = data.Settings
	player:SetAttribute("Set_Music", settings.Music)
	player:SetAttribute("Set_Sounds", settings.Sounds)
	player:SetAttribute("Set_Luck", DataService.LuckLevelInUse(data))
	player:SetAttribute("Set_AutoSell", settings.AutoSell ~= false)
	player:SetAttribute("Set_OtherBees", settings.OtherBees ~= false)
	for _, rarityName in GameConfig.RarityOrder do
		player:SetAttribute("Set_Stop_" .. rarityName, settings.StopFor[rarityName] == true)
	end

	-- the tutorial (the yellow hint and the arrow): which lessons are done
	local tutorial = data.Tutorial
	player:SetAttribute("Tut_Sold", tutorial.Sold == true)
	player:SetAttribute("Tut_Upgrade", tutorial.Upgrade == true)
	player:SetAttribute("Tut_BetterBee", tutorial.BetterBee == true)
	player:SetAttribute("TutorialDone", tutorial.Done == true)

	-- Daily Rewards: how many of this round's rewards are collected (0 = none yet), and the
	-- time from which the next one can be collected
	player:SetAttribute("DailyDay", data.Daily.Day % #GameConfig.DailyRewards)
	player:SetAttribute("DailyNextAt", data.Daily.NextAt)

	-- the Inventory: boosts waiting to be used (how many of each), and which bees are locked
	for key, count in data.BoostItems do
		player:SetAttribute("BoostItem_" .. key, count)
	end
	for _, beeName in GameConfig.BeeOrder do
		player:SetAttribute("Lock_" .. beeName, data.Locked[beeName] == true)
	end

	-- offline honey waiting to be collected (the "Welcome Back!" window)
	player:SetAttribute("OfflineJars", data.Offline.Jars)
	player:SetAttribute("OfflineSeconds", data.Offline.Seconds)

	player:SetAttribute("Coins", data.Coins)
	player:SetAttribute("JarsCarried", data.JarsCarried)
	player:SetAttribute("JarsStored", data.JarsStored)
	player:SetAttribute("BeesInBag", #data.Bees)
	player:SetAttribute("BeesPlaced", placed)

	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins then
		coins.Value = data.Coins
	end
end

-- Final save when a player leaves.
function DataService.Release(player: Player)
	local profile = profiles[player]
	if not profile or profile.Releasing then
		return
	end
	profile.Releasing = true
	local userId = player.UserId
	savingUsers[userId] = true
	saveProfile(userId, profile)
	savingUsers[userId] = nil
	profiles[player] = nil
end

function DataService.Init()
	-- Autosave
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveSeconds)
			for player, profile in profiles do
				if not profile.Releasing then
					task.spawn(saveProfile, player.UserId, profile)
				end
			end
		end
	end)

	-- When the server shuts down, save everyone before it closes.
	game:BindToClose(function()
		for player in profiles do
			task.spawn(DataService.Release, player)
		end
		local deadline = os.clock() + 25
		while next(profiles) ~= nil and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
