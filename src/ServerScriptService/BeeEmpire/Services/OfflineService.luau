--[[
	OfflineService - "Your Bees Earn Offline!"

	Bees keep working while their owner is away from the game.
	- When a player joins, the server works out how long they were away (from the time their
	  save was last written) and how many jars their bees made in that time:
	      jars = the hive's jars per second x GameConfig.OfflineSpeed x the seconds away
	  Time away longer than GameConfig.OfflineMaxHours earns nothing extra, and a time away
	  shorter than GameConfig.OfflineMinSeconds earns nothing at all.
	- Those jars WAIT (data.Offline, saved) until the player presses Collect in the
	  "Welcome Back!" window. Then they go to the Honey Jars stand, to be grabbed and sold
	  like any other honey.
	- Uncollected jars are kept if the player leaves again. More time away adds to them, but
	  the waiting jars never stand for more than OfflineMaxHours in all.

	The server owns every number here. A player's screen only shows the window and asks to
	collect; it cannot say how long it was away or how many jars it should get.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local PassService = require(script.Parent.PassService)

local OfflineService = {}

-- Jars per second made by the bees working in the hive (the Bee Speed upgrade counts).
local function jarsPerSecond(data): number
	local rate = 0
	for _, bee in data.Cells do
		rate += GameConfig.Bees[bee.Rarity].NectarPerSecond
	end
	return rate * DataService.UpgradeValue(data, "BeeSpeed")
end

-- Called once when a player has joined and their save is loaded: adds the honey their bees
-- made while they were away to the jars waiting to be collected.
function OfflineService.SetupPlayer(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local away = DataService.TakeAwaySeconds(player)
	if away < GameConfig.OfflineMinSeconds then
		return
	end

	local waiting = data.Offline
	local longest = GameConfig.OfflineMaxHours * 3600
	local counted = math.min(away, math.max(0, longest - waiting.Seconds))
	-- (the VIP pass's extra honey counts while away too; boosts do not)
	local jars = math.floor(jarsPerSecond(data) * GameConfig.OfflineSpeed * counted * PassService.HoneyMultiplier(player))
	if counted <= 0 or jars <= 0 then
		return -- nothing new (no bees yet, or the waiting jars already stand for the longest time)
	end
	waiting.Jars += jars
	waiting.Seconds += counted
	-- (Main shares the numbers with the player's screen right after this)
end

-- The Collect button of the "Welcome Back!" window: the waiting jars go to the Honey Jars.
function OfflineService.Claim(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local waiting = data.Offline
	local jars = waiting.Jars
	if jars <= 0 then
		return -- nothing to collect (for example a second tap that arrived just after the first)
	end
	waiting.Jars = 0
	waiting.Seconds = 0
	data.JarsStored += jars -- (ProductionService redraws the Honey Jars stand a moment later)

	Notifier.Effect(player, "OfflineClaimed", jars)
	DataService.Replicate(player)
end

return OfflineService
