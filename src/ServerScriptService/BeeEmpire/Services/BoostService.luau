--[[
	BoostService - boosts: something is better for a few minutes.

	The boosts are listed in GameConfig.Boosts ("Honey" = Double Honey, "Luck" = Double Luck).
	- A boost that is won goes into the player's Inventory (data.BoostItems) and waits there.
	  It starts when the player presses Use; using another one adds its minutes on top
	  (up to GameConfig.BoostMaxMinutes of one kind running).
	- The seconds left are kept in the player's saved data (data.Boosts) and only run down
	  while the player is in the game.
	- What a boost DOES is one line in the service it belongs to:
	      Honey: ProductionService.Step (jars arriving at the Honey Jars count double)
	      Luck:  BeeService.Roll (Queen's Luck is doubled for the roll)
	  Both ask DataService.BoostMultiplier.
	- A player's screen is told when each boost ends (the attribute BoostEnds_Honey /
	  BoostEnds_Luck: a server time, or 0 when the boost is not running) so it can count down.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)

local BoostService = {}

-- Tells the player's screen when each of their boosts ends.
local function share(player: Player, data)
	local now = workspace:GetServerTimeNow()
	for kind in GameConfig.Boosts do
		local left = data.Boosts[kind] or 0
		player:SetAttribute("BoostEnds_" .. kind, if left > 0 then now + left else 0)
	end
end

-- Starts a boost running for some seconds (on top of what the player has left of it).
function BoostService.Add(player: Player, kind: string, seconds: number)
	local data = DataService.Get(player)
	if not data or not GameConfig.Boosts[kind] or seconds <= 0 then
		return
	end
	data.Boosts[kind] = math.min((data.Boosts[kind] or 0) + seconds, GameConfig.BoostMaxMinutes * 60)
	share(player, data)
	DataService.Replicate(player) -- (the jars-per-second number on the screen changes with Double Honey)
end

-- Puts a boost in a player's Inventory (a reward). It does nothing until they press Use.
function BoostService.Give(player: Player, kind: string, minutes: number): boolean
	local data = DataService.Get(player)
	if not data or not GameConfig.Boosts[kind] or minutes < 1 then
		return false
	end
	local key = GameConfig.BoostItemKey(kind, minutes)
	data.BoostItems[key] = math.min((data.BoostItems[key] or 0) + 1, 999)
	DataService.Replicate(player)
	return true
end

-- The Use button in the Inventory: one waiting boost starts running (or adds its minutes to
-- the one that already is). The request names a kind and a length; the server checks the
-- player really has such a boost.
function BoostService.Use(player: Player, kind: any, minutes: any)
	if typeof(kind) ~= "string" or typeof(minutes) ~= "number" or minutes ~= minutes then
		return
	end
	local boost = GameConfig.Boosts[kind]
	local data = DataService.Get(player)
	if not boost or not data then
		return
	end
	local key = GameConfig.BoostItemKey(kind, minutes)
	if GameConfig.ReadBoostItemKey(key) == nil or (data.BoostItems[key] or 0) <= 0 then
		return -- they have no such boost (for example a second tap that arrived just after the first)
	end
	if (data.Boosts[kind] or 0) + math.floor(minutes) * 60 > GameConfig.BoostMaxMinutes * 60 then
		Notifier.Send(player, "You have plenty of " .. boost.Name .. " running. Use this one later!", "info")
		return
	end
	data.BoostItems[key] -= 1
	Notifier.Effect(player, "BoostUsed", { Kind = kind, Minutes = math.floor(minutes) })
	BoostService.Add(player, kind, math.floor(minutes) * 60) -- (this shares the new numbers too)
end

-- Called about once a second by Main: every running boost loses the time that has passed.
function BoostService.Step(deltaTime: number)
	for _, player in Players:GetPlayers() do
		local data = DataService.Get(player)
		if data then
			for kind, boost in GameConfig.Boosts do
				local left = data.Boosts[kind] or 0
				if left > 0 then
					left = math.max(0, left - deltaTime)
					data.Boosts[kind] = left
					if left == 0 then
						share(player, data)
						DataService.Replicate(player)
						Notifier.Send(player, boost.Name .. " has ended.", "info")
					end
				end
			end
		end
	end
end

-- Called when a player has joined and their save is loaded: boosts they still had carry on.
function BoostService.SetupPlayer(player: Player)
	local data = DataService.Get(player)
	if data then
		share(player, data)
	end
end

return BoostService
