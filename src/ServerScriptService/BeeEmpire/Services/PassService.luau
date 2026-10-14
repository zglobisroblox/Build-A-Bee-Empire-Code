--[[
	PassService - who owns which pass.

	A pass is bought once, with Robux, and lasts for ever (see THE SHOP in GameConfig).
	Roblox keeps the record of who has bought what. This script only ASKS Roblox, and remembers
	the answers while the player is here. Nothing a player's own device says is ever believed:
	- when a player joins, Roblox is asked about every pass
	- when a purchase window closes with "bought", Roblox is asked again about that one pass

	It also asks Roblox whether this player may be sold things that change random rolls. (In a
	few countries they may not. Until Roblox has answered, the answer counts as "no".)

	Other scripts use: PassService.Owns(player, "AutoSell"), and the little helpers at the
	bottom (LuckMultiplier, HoneyMultiplier, BagLimit, ExtraStands).

	IN ROBLOX STUDIO the game's maker is told by Roblox that they own EVERY pass. That would
	hide all the prices and switch every pass on during each test. So in Studio Roblox's answer
	about owning is not used: a tester starts with no passes, exactly like a new player, and
	can press Buy to try a pass (a pretend purchase, see below). The switch TestRealPasses =
	true (see below) uses Roblox's answer after all.

	TESTING, IN ROBLOX STUDIO ONLY: the folder ServerStorage.BeeEmpireDev can carry switches
	named TestPass_<pass> (for example TestPass_AutoSell = true), which give the tester that
	pass, and TestNoRandom = true, which pretends the tester's country does not allow passes
	that change rolls. A purchase made inside Studio is a pretend one too (no Robux is taken),
	so there it is simply believed. None of this can happen in the real game: these lines only
	run when RunService:IsStudio() is true, and in the real game it never is.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)

local PassService = {}

local IS_STUDIO = RunService:IsStudio()
local TRIES = 3 -- how many times Roblox is asked before giving up for this visit
local RETRY_SECONDS = 2
local AFTER_PURCHASE_WAITS = { 0, 2, 5 } -- seconds: when Roblox is asked again after a purchase

local owned: { [Player]: { [string]: boolean } } = {}
local checked: { [Player]: boolean } = {} -- true once Roblox has been asked about every pass
local randomAllowed: { [Player]: boolean } = {} -- may this player be sold passes that change rolls?
local listeners: { (Player, string, boolean) -> () } = {}

local function testSwitch(name: string): boolean
	if not IS_STUDIO then
		return false
	end
	local folder = ServerStorage:FindFirstChild("BeeEmpireDev")
	return folder ~= nil and folder:GetAttribute(name) == true
end

local function keyOfId(passId: number): string?
	for key, pass in GameConfig.Passes do
		if pass.Id ~= 0 and pass.Id == passId then
			return key
		end
	end
	return nil
end

-- Asks Roblox whether the player owns a pass. Gives (answered, owns): answered is false when
-- Roblox could not be reached.
local function askRoblox(player: Player, key: string): (boolean, boolean)
	local pass = GameConfig.Passes[key]
	if not pass or pass.Id == 0 then
		return true, false -- not on sale yet, so nobody has it
	end
	for attempt = 1, TRIES do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
		end)
		if ok then
			return true, result == true
		end
		if attempt < TRIES then
			task.wait(RETRY_SECONDS)
		end
		if not player:IsDescendantOf(Players) then
			break
		end
	end
	return false, false
end

-- Writes down that a player has a pass, and tells the scripts that asked to hear about it.
-- bought = true when it was bought just now (false when they already had it on joining).
local function mark(player: Player, key: string, bought: boolean)
	local list = owned[player]
	if not list or list[key] then
		return
	end
	list[key] = true
	player:SetAttribute("Pass_" .. key, true)
	for _, listener in listeners do
		task.spawn(listener, player, key, bought)
	end
end

local function askPolicy(player: Player)
	local allowed = false
	for attempt = 1, TRIES do
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and typeof(info) == "table" then
			allowed = info.ArePaidRandomItemsRestricted ~= true
			break
		end
		if attempt < TRIES then
			task.wait(RETRY_SECONDS)
		end
		if not player:IsDescendantOf(Players) then
			return
		end
	end
	if testSwitch("TestNoRandom") then
		allowed = false
	end
	if owned[player] then
		randomAllowed[player] = allowed
		player:SetAttribute("RandomPassesAllowed", allowed)
	end
end

-- JOINING AND LEAVING ----------------------------------------------------------------------

-- Called the moment a player joins. It starts asking Roblox and does NOT wait for the answers
-- (see WaitUntilChecked).
function PassService.Begin(player: Player)
	owned[player] = {}
	checked[player] = false
	player:SetAttribute("RandomPassesAllowed", false)
	for _, key in GameConfig.PassOrder do
		player:SetAttribute("Pass_" .. key, false)
	end

	task.spawn(askPolicy, player)
	task.spawn(function()
		local waiting = #GameConfig.PassOrder
		for _, key in GameConfig.PassOrder do
			-- (asked all at once: Roblox bundles the questions into one)
			task.spawn(function()
				local answered, owns = askRoblox(player, key)
				if IS_STUDIO and not testSwitch("TestRealPasses") then
					owns = false -- (in Studio the maker "owns" everything: see the top of this file)
				end
				if (answered and owns) or testSwitch("TestPass_" .. key) then
					mark(player, key, false)
				end
				waiting -= 1
			end)
		end
		while waiting > 0 and player:IsDescendantOf(Players) do
			task.wait(0.1)
		end
		if owned[player] then
			checked[player] = true
			player:SetAttribute("PassesChecked", true)
		end
	end)
end

-- Waits (a few seconds at most) until Roblox has answered about every pass, so a player who
-- owns +2 Rolls sees all their stands from the first moment.
function PassService.WaitUntilChecked(player: Player, longest: number)
	local deadline = os.clock() + longest
	while not checked[player] and os.clock() < deadline and player:IsDescendantOf(Players) do
		task.wait(0.1)
	end
end

function PassService.CleanupPlayer(player: Player)
	owned[player] = nil
	checked[player] = nil
	randomAllowed[player] = nil
end

-- BUYING --------------------------------------------------------------------------------------

-- May this player be shown the purchase window for this pass? Gives (yes, why not).
function PassService.CanBuy(player: Player, key: any): (boolean, string?)
	local pass = if typeof(key) == "string" then GameConfig.Passes[key] else nil
	if not pass or not owned[player] then
		return false, nil
	end
	if owned[player][key] then
		return false, "You already have " .. pass.Name .. "!"
	end
	if pass.Id == 0 then
		return false, pass.Name .. " is not on sale yet."
	end
	if pass.Random and not randomAllowed[player] then
		return false, "Sorry, " .. pass.Name .. " is not available in your country."
	end
	return true, nil
end

-- Opens Roblox's own purchase window for a pass. (Roblox handles the Robux. This game never
-- sees or touches them.)
function PassService.Prompt(player: Player, key: string)
	local pass = GameConfig.Passes[key]
	if pass and pass.Id ~= 0 then
		pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, pass.Id)
		end)
	end
end

-- func(player, passName, bought) is called whenever a player turns out to own a pass.
function PassService.OnOwned(func: (Player, string, boolean) -> ())
	table.insert(listeners, func)
end

function PassService.Init()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased or not owned[player] then
			return
		end
		local key = keyOfId(passId)
		if not key then
			return
		end
		if IS_STUDIO then
			mark(player, key, true) -- a pretend purchase in Studio (see the top of this file)
			return
		end
		-- the real game: ask Roblox itself whether the pass is now theirs
		for _, seconds in AFTER_PURCHASE_WAITS do
			if seconds > 0 then
				task.wait(seconds)
			end
			if not owned[player] then
				return -- they left
			end
			local answered, owns = askRoblox(player, key)
			if answered and owns then
				mark(player, key, true)
				return
			end
		end
		warn("[BeeEmpire] Roblox does not (yet) show pass " .. key .. " as owned by " .. player.Name .. ". They get it when they next join.")
	end)

	if IS_STUDIO then
		-- the test switches can be flipped while the game runs
		local folder = ServerStorage:FindFirstChild("BeeEmpireDev")
		if folder then
			folder.AttributeChanged:Connect(function(name)
				local key = name:match("^TestPass_(.+)$")
				if key and GameConfig.Passes[key] and folder:GetAttribute(name) == true then
					for player in owned do
						mark(player, key, true)
					end
				end
			end)
		end
	end
end

-- WHAT THE PASSES DO (numbers the other scripts read) --------------------------------------------

function PassService.Owns(player: Player, key: string): boolean
	local list = owned[player]
	return list ~= nil and list[key] == true
end

-- Lucky Queen: what Queen's Luck is multiplied by for this player.
function PassService.LuckMultiplier(player: Player): number
	return if PassService.Owns(player, "LuckyQueen") then GameConfig.LuckyQueenLuck else 1
end

-- VIP: what every jar the bees bring is multiplied by.
function PassService.HoneyMultiplier(player: Player): number
	return if PassService.Owns(player, "VIP") then GameConfig.VipHoney else 1
end

-- Infinite Inventory: how many spare bees this player can keep.
function PassService.BagLimit(player: Player): number
	return if PassService.Owns(player, "InfiniteInventory") then GameConfig.InfiniteBagLimit else GameConfig.MaxBeesInBag
end

-- +2 Rolls: how many honeycomb stands the pass adds.
function PassService.ExtraStands(player: Player): number
	return if PassService.Owns(player, "Rolls") then math.max(0, GameConfig.GamePassRollStands) else 0
end

return PassService
