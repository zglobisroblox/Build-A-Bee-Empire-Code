--[[
	UpgradeService - the Upgrade Shop on each plot.

	Sells every upgrade in GameConfig.UpgradeOrder: the Beehive, Queen's Luck, Bee Speed,
	More Rolls, Walk Speed and Roll Speed (Roll Speed only once Auto Roll has been bought).
	It also sets how fast each player walks (ApplyWalkSpeed).
	The server checks the price and the level; the player's screen only asks.

	After a purchase it tells the other services to refresh whatever changed (the hive,
	the bees' trips, the honeycomb stands in the roll area).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)
local NumberFormat = require(ReplicatedStorage.BeeEmpire.NumberFormat)
local Upgrades = require(ReplicatedStorage.BeeEmpire.Upgrades)
local BeeService = require(script.Parent.BeeService)
local DataService = require(script.Parent.DataService)
local HiveService = require(script.Parent.HiveService)
local Notifier = require(script.Parent.Notifier)
local PassService = require(script.Parent.PassService)
local PlotService = require(script.Parent.PlotService)
local ProductionService = require(script.Parent.ProductionService)
local TutorialService = require(script.Parent.TutorialService)

local UpgradeService = {}

-- THE UPGRADE BOARD ABOVE THE SHOP -------------------------------------------------------

local function boardFace(plot: Model)
	local shop = plot:FindFirstChild("Upgrades")
	local board = shop and shop:FindFirstChild("Board")
	return board and board:FindFirstChild("Face")
end

-- Fills in each upgrade's panel: what the next level gives ("2 > 4 bees") and its price.
-- data = nil for an empty plot. (Each player's own screen turns the price pill green or
-- grey depending on whether they can afford it - see WorldFX.)
-- (bonus: the stands the "+2 Rolls" pass adds for this plot's owner, so the board counts them)
local function showBoard(plot: Model, data, bonus: number?)
	local face = boardFace(plot)
	if not face then
		return
	end
	for _, id in GameConfig.UpgradeOrder do
		local panel = face:FindFirstChild("Panel_" .. id)
		local value = panel and panel:FindFirstChild("Value")
		local pill = panel and panel:FindFirstChild("Price")
		local priceLabel = pill and pill:FindFirstChild("Label")
		if value and priceLabel then
			local level = if data then DataService.UpgradeLevel(data, id) else 1
			local nextCost = Upgrades.NextCost(id, level)
			value.Text = Upgrades.DescribeChangeShort(id, level, bonus)
			priceLabel.Text = if nextCost then NumberFormat.Short(nextCost) else Upgrades.TopLabel(id)
		end
	end
end

function UpgradeService.RefreshBoard(player: Player)
	local data = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	if data and plot then
		showBoard(plot, data, PassService.ExtraStands(player))
	end
end

function UpgradeService.ResetPlot(plot: Model)
	showBoard(plot, nil)
end

-- WALK SPEED ------------------------------------------------------------------------------

-- Sets how fast the player's character walks: GameConfig.WalkSpeed times their Walk Speed
-- upgrade (x1 until their save has loaded). Main calls it when a character appears and when the
-- save has loaded; buying a Walk Speed upgrade calls it too.
function UpgradeService.ApplyWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local data = DataService.Get(player)
	local multiplier = if data then DataService.UpgradeValue(data, "WalkSpeed") else 1
	humanoid.WalkSpeed = GameConfig.WalkSpeed * multiplier
end

-- BUYING -----------------------------------------------------------------------------

-- Main has already checked that the player is standing at their own Upgrade Shop.
function UpgradeService.Buy(player: Player, id: any)
	if not Upgrades.Exists(id) or not table.find(GameConfig.UpgradeOrder, id) then
		return
	end

	local data = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	if not data or not plot then
		return
	end

	if Upgrades.NeedsAutoRoll(id) and not data.AutoRoll then
		Notifier.Send(player, "Buy Auto Roll at the sign next to your Queen first!", "info")
		return
	end

	if id == "Hive" then
		-- the beehive has its own model and celebration, so HiveService handles it
		if HiveService.Upgrade(player) then
			ProductionService.RefreshPlayer(player) -- a bigger hive has a bigger station
			showBoard(plot, data, PassService.ExtraStands(player))
			TutorialService.Mark(player, "Upgrade") -- (the tutorial: first upgrade bought)
		end
		return
	end

	local level = DataService.UpgradeLevel(data, id)
	local cost = Upgrades.NextCost(id, level)
	if not cost then
		Notifier.Send(player, Upgrades.DisplayName(id) .. " is already at its best!", "info")
		return
	end
	if data.Coins < cost then
		Notifier.Send(player, "You need " .. NumberFormat.Short(cost - data.Coins) .. " more Honey Coins!", "bad")
		return
	end

	data.Coins -= cost
	data.Upgrades[id] = level + 1
	if id == "Luck" then
		data.Settings.Luck = level + 1 -- new luck is used straight away (Settings can turn it down again)
	end

	-- make the upgrade take effect
	if id == "BeeSpeed" then
		HiveService.RefreshBees(plot, data)
	elseif id == "Rolls" then
		BeeService.RefreshStands(player) -- the new honeycomb stand appears in the roll area
	elseif id == "WalkSpeed" then
		UpgradeService.ApplyWalkSpeed(player) -- faster straight away
	end

	Notifier.Effect(player, "Upgraded", { Id = id, Level = level + 1 })
	showBoard(plot, data, PassService.ExtraStands(player))
	DataService.Replicate(player)
	TutorialService.Mark(player, "Upgrade") -- (the tutorial: first upgrade bought)
end

return UpgradeService
