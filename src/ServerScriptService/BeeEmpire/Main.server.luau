--[[
	Main - starts the game on the server and connects everything together.

	How a player action works:
	1. The player presses E at a station, or taps a button on their screen.
	2. That sends a REQUEST to the server ("I would like to buy this egg").
	3. The server checks it is allowed (their own hive, close enough, not spamming,
	   and that what they sent makes sense).
	4. Only then does the server change coins, jars or bees.
	The player's device never decides any of these things, which keeps cheaters out.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)

local Services = script.Parent.Services
local BeeService = require(Services.BeeService)
local BoostService = require(Services.BoostService)
local DailyService = require(Services.DailyService)
local DataService = require(Services.DataService)
local HalloweenService = require(Services.HalloweenService)
local HiveService = require(Services.HiveService)
local MarketService = require(Services.MarketService)
local Notifier = require(Services.Notifier)
local OfflineService = require(Services.OfflineService)
local PassService = require(Services.PassService)
local PlotService = require(Services.PlotService)
local ProductionService = require(Services.ProductionService)
local SettingsService = require(Services.SettingsService)
local ShopService = require(Services.ShopService)
local UpgradeService = require(Services.UpgradeService)

local DISTANCE_BUFFER = 6 -- extra studs allowed for lag, so honest players are never blocked
local SHOP_RANGE = 26 -- how close a player must be to their Upgrade Shop to buy from it
local PRODUCTION_INTERVAL = 0.5
local AUTO_ROLL_INTERVAL = 0.25 -- how often the server looks whether a Queen should roll by herself
local BOOST_INTERVAL = 1 -- how often running boosts lose the time that has passed
local PASS_WAIT = 4 -- the longest a joining player waits for Roblox to say which passes they own

local remotes = ReplicatedStorage.BeeEmpire.Remotes

-- [Player] = { [actionName] = time of last use }. Each action has its own cooldown,
-- so pressing two different buttons quickly never silently drops one.
local lastActionTime: { [Player]: { [string]: number } } = {}

local function passesCooldown(player: Player, actionName: string): boolean
	local times = lastActionTime[player]
	if not times then
		times = {}
		lastActionTime[player] = times
	end
	local now = os.clock()
	if now - (times[actionName] or 0) < GameConfig.ActionCooldown then
		return false -- too fast
	end
	times[actionName] = now
	return true
end

-- SETUP -----------------------------------------------------------------------------

PlotService.Init()
DataService.Init()
MarketService.Init() -- the Honey Market's price: a new one every half minute
PassService.Init() -- passes (things bought with Robux): who owns what
ShopService.Init() -- and what each pass does
HalloweenService.Init() -- the Halloween Egg (a limited-time event: it removes itself when its end day comes)

-- CHECKS EVERY REQUEST MUST PASS ------------------------------------------------------

local function isAllowed(player: Player, plot: Model, promptPart: BasePart, actionName: string): boolean
	if DataService.Get(player) == nil then
		return false -- their data has not loaded yet
	end

	if not passesCooldown(player, actionName) then
		return false
	end

	if PlotService.GetPlot(player) ~= plot then
		Notifier.Send(player, "That is not your hive!", "bad")
		return false
	end

	if not PlotService.IsNear(player, promptPart, GameConfig.InteractDistance + DISTANCE_BUFFER) then
		return false -- too far away (or not alive)
	end

	return true
end

local connectedPrompts: { [ProximityPrompt]: boolean } = {}

local function connectPrompt(plot: Model, proximityPrompt: ProximityPrompt)
	if connectedPrompts[proximityPrompt] then
		return
	end
	connectedPrompts[proximityPrompt] = true
	local action = proximityPrompt:GetAttribute("Action")
	local promptPart = proximityPrompt.Parent
	if typeof(action) ~= "string" or not promptPart or not promptPart:IsA("BasePart") then
		return
	end

	proximityPrompt.Triggered:Connect(function(player)
		if not isAllowed(player, plot, promptPart, action) then
			return
		end

		-- (the "Hive" and "Upgrades" buttons only open a window on the player's screen,
		-- so the server has nothing to do for them)
		if action == "Roll" then
			BeeService.Roll(player)
		elseif action == "BuyAutoRoll" then
			BeeService.BuyAutoRoll(player)
		elseif action == "BuyBee" then
			-- the button belongs to one honeycomb stand; the stand knows its own number
			local stand = promptPart.Parent
			BeeService.BuyOffer(player, stand and stand:GetAttribute("StandIndex"))
		elseif action == "Collect" then
			ProductionService.Collect(player)
		elseif action == "Sell" then
			ProductionService.Sell(player)
		end
	end)
end

for _, plot in PlotService.GetAllPlots() do
	for _, descendant in plot:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			connectPrompt(plot, descendant)
		end
	end
	-- Buttons that arrive later (a honeycomb stand is put into the world when its owner
	-- gets it) are connected the moment they appear.
	plot.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			connectPrompt(plot, descendant)
		end
	end)
end

-- Every home area starts empty.
for _, plot in PlotService.GetAllPlots() do
	HiveService.ResetPlot(plot)
	BeeService.ResetPlot(plot)
	ProductionService.ResetPlot(plot)
	UpgradeService.ResetPlot(plot)
end

-- REQUESTS FROM SCREEN BUTTONS ----------------------------------------------------------

-- Every button request passes through here first.
local function isRequestAllowed(player: Player, actionName: string): boolean
	if DataService.Get(player) == nil then
		return false -- their data has not loaded yet
	end
	return passesCooldown(player, actionName)
end

remotes.PlaceBee.OnServerEvent:Connect(function(player, rarityName, cellIndex)
	if isRequestAllowed(player, "PlaceBee") then
		BeeService.PlaceBee(player, rarityName, cellIndex)
	end
end)

remotes.RemoveBee.OnServerEvent:Connect(function(player, cellIndex)
	if isRequestAllowed(player, "RemoveBee") then
		BeeService.RemoveBee(player, cellIndex)
	end
end)

remotes.EquipBest.OnServerEvent:Connect(function(player)
	if isRequestAllowed(player, "EquipBest") then
		BeeService.EquipBest(player)
	end
end)

-- The Inventory: delete a spare bee, lock or unlock a kind of bee, use a waiting boost.
remotes.DeleteBee.OnServerEvent:Connect(function(player, rarityName)
	if isRequestAllowed(player, "DeleteBee") then
		BeeService.DeleteBee(player, rarityName)
	end
end)

remotes.LockBee.OnServerEvent:Connect(function(player, rarityName, locked)
	if isRequestAllowed(player, "LockBee") then
		BeeService.SetLock(player, rarityName, locked)
	end
end)

remotes.UseBoost.OnServerEvent:Connect(function(player, kind, minutes)
	if isRequestAllowed(player, "UseBoost") then
		BoostService.Use(player, kind, minutes)
	end
end)

-- The Auto Roll button: switch it on or off (only for players who have bought Auto Roll).
remotes.SetAutoRoll.OnServerEvent:Connect(function(player, on)
	if isRequestAllowed(player, "SetAutoRoll") then
		BeeService.SetAutoRoll(player, on)
	end
end)

-- The Keep Rolling button: Auto Roll stops waiting for the bees on the stands and rolls again.
remotes.KeepRolling.OnServerEvent:Connect(function(player)
	if isRequestAllowed(player, "KeepRolling") then
		BeeService.KeepRolling(player)
	end
end)

-- The Settings window: volumes, which bees Auto Roll waits for, how much luck to use.
remotes.SetSetting.OnServerEvent:Connect(function(player, name, value, extra)
	local key = SettingsService.KeyFor(name, value) -- nil when the request makes no sense
	if key and isRequestAllowed(player, key) then
		SettingsService.Set(player, name, value, extra)
	end
end)

-- The Collect button of the "Welcome Back!" window: take the honey the bees made while
-- the player was away. (The server knows how much is waiting; the request carries no numbers.)
remotes.ClaimOffline.OnServerEvent:Connect(function(player)
	if isRequestAllowed(player, "ClaimOffline") then
		OfflineService.Claim(player)
	end
end)

-- The Claim button of the Daily Rewards window. (The server knows which reward is next and
-- whether it is ready; the request carries no numbers.)
remotes.ClaimDaily.OnServerEvent:Connect(function(player)
	if isRequestAllowed(player, "ClaimDaily") then
		DailyService.Claim(player)
	end
end)

-- The Buy button of the Shop window (passes, bought with Robux). The request only names a
-- pass. The server checks it and then opens Roblox's own purchase window.
remotes.BuyPass.OnServerEvent:Connect(function(player, passName)
	if isRequestAllowed(player, "BuyPass") then
		ShopService.Request(player, passName)
	end
end)

-- Buying from the Upgrade Shop: the player must be standing at their own shop.
remotes.BuyUpgrade.OnServerEvent:Connect(function(player, upgradeId)
	if not isRequestAllowed(player, "BuyUpgrade") then
		return
	end
	local plot = PlotService.GetPlot(player)
	local shop = plot and plot:FindFirstChild("Upgrades")
	local shopSpot = shop and shop:FindFirstChild("UpgradeSpot")
	if not shopSpot or not PlotService.IsNear(player, shopSpot, SHOP_RANGE) then
		Notifier.Send(player, "Go to your Upgrade Shop to buy upgrades!", "bad")
		return
	end
	UpgradeService.Buy(player, upgradeId)
end)

-- PLAYERS JOINING AND LEAVING ---------------------------------------------------------

-- GameConfig.WalkSpeed times the player's Walk Speed upgrade (see UpgradeService)
local function applyWalkSpeed(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		UpgradeService.ApplyWalkSpeed(player)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		applyWalkSpeed(player, character)
	end)
	if player.Character then
		task.spawn(applyWalkSpeed, player, player.Character)
	end

	local plot = PlotService.Assign(player)
	if not plot then
		player:Kick("This server is full of busy bees! Please join again.")
		return
	end

	PassService.Begin(player) -- starts asking Roblox which passes they own (the answers come a moment later)
	local loaded = DataService.Load(player)
	if not player:IsDescendantOf(Players) then
		return -- they left while loading; onPlayerRemoving already tidied up
	end
	if not loaded then
		player:Kick("We could not load your hive. Your progress is safe - please join again!")
		return
	end

	PassService.WaitUntilChecked(player, PASS_WAIT)
	if not player:IsDescendantOf(Players) then
		return
	end

	HiveService.SetupPlayer(player)
	BeeService.SetupPlayer(player)
	ProductionService.SetupPlayer(player)
	UpgradeService.RefreshBoard(player)
	UpgradeService.ApplyWalkSpeed(player) -- their Walk Speed upgrade, now that their save is here
	OfflineService.SetupPlayer(player) -- the honey their bees made while they were away
	BoostService.SetupPlayer(player) -- boosts they still had left carry on
	ShopService.SetupPlayer(player) -- what their passes give them (Starter Pack, VIP crown...)
	DataService.Replicate(player)
	player:SetAttribute("DataLoaded", true)
end

local function onPlayerRemoving(player: Player)
	lastActionTime[player] = nil
	local plot = PlotService.GetPlot(player)
	if plot then
		HiveService.ResetPlot(plot)
		BeeService.ResetPlot(plot)
		UpgradeService.ResetPlot(plot)
	end
	BeeService.CleanupPlayer(player)
	ProductionService.CleanupPlayer(player)
	PlotService.Release(player)
	ShopService.CleanupPlayer(player)
	DataService.Release(player) -- saves their progress
	PassService.CleanupPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- GAME LOOPS --------------------------------------------------------------------------

-- Bees make jars.
task.spawn(function()
	while true do
		local deltaTime = task.wait(PRODUCTION_INTERVAL)
		ProductionService.Step(deltaTime)
	end
end)

-- Boosts run down.
task.spawn(function()
	while true do
		local deltaTime = task.wait(BOOST_INTERVAL)
		BoostService.Step(deltaTime)
	end
end)

-- Queens with Auto Roll switched on roll by themselves.
task.spawn(function()
	while true do
		task.wait(AUTO_ROLL_INTERVAL)
		BeeService.StepAutoRoll()
	end
end)
