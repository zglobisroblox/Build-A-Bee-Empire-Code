--[[
	DailyService - Daily Rewards.

	The rewards are listed in GameConfig.DailyRewards: one a day, then round again from the
	first. A player who misses a day keeps their place.
	- data.Daily.Day counts every reward the player has ever collected, so the next one is
	  number (Day mod the length of the list) + 1.
	- data.Daily.NextAt is the time (os.time()) from which the next one can be collected:
	  GameConfig.DailyRewardHours after the last one was. 0 = straight away (a new player).

	The server decides whether a reward is ready and what it is. The Claim button on a
	player's screen only asks; the request carries no numbers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)
local BeeService = require(script.Parent.BeeService)
local BoostService = require(script.Parent.BoostService)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)

local DailyService = {}

local MAX_COINS = 1e15

-- The Claim button of the Daily Rewards window.
function DailyService.Claim(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local daily = data.Daily
	if os.time() < daily.NextAt then
		Notifier.Send(player, "Your next daily reward is not ready yet!", "info")
		return
	end

	local list = GameConfig.DailyRewards
	local index = daily.Day % #list + 1
	local reward = list[index]
	local placed = false -- (for a bee: true if it went straight to work in the hive)

	if reward.Bee then
		-- a bee needs room: a free spot in the hive, or else the bag. With no room the reward
		-- is NOT used up; it waits until the player has made room (GiveBee tells them).
		local given, inHive = BeeService.GiveBee(player, reward.Bee)
		if not given then
			return
		end
		placed = inHive
	elseif reward.Boost then
		-- a boost goes into the Inventory; it starts when the player presses Use there
		BoostService.Give(player, reward.Boost, reward.Minutes or 0)
	elseif reward.Coins then
		data.Coins = math.min(data.Coins + reward.Coins, MAX_COINS)
	end

	daily.Day += 1
	daily.NextAt = os.time() + GameConfig.DailyRewardHours * 3600

	Notifier.Effect(player, "DailyClaimed", { Day = index, Placed = placed })
	DataService.Replicate(player)
end

return DailyService
