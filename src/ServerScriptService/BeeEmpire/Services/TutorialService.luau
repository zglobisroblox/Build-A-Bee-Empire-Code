--[[
	TutorialService - keeps count of the three things a new player learns.

	The yellow hint and the bouncing arrow on a player's screen are the tutorial. They stay
	until the player has done each of these once:
		"Sold"      sold honey at the Honey Market
		"Upgrade"   bought an upgrade at the Upgrade Shop (a bigger hive counts)
		"BetterBee" swapped a better bee into a full hive
	Then they go away for good. The record is saved with the player's progress
	(data.Tutorial in DataService), so the tutorial never comes back.

	The other services call TutorialService.Mark when one of those things really happens.
	A player's screen only reads the result (see State.Objective): it cannot mark anything.
]]

local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)

local TutorialService = {}

local STEPS = { "Sold", "Upgrade", "BetterBee" }
local DONE_MESSAGE = "Tutorial done! You know it all now. Have fun!"
local DONE_MESSAGE_WAIT = 1.5 -- seconds, so it does not land on top of the message for the last lesson

-- Ticks off one lesson for a player. When it was the last one, the tutorial is over.
function TutorialService.Mark(player: Player, step: string)
	local data = DataService.Get(player)
	local tutorial = data and data.Tutorial
	if not tutorial or tutorial.Done or tutorial[step] or not table.find(STEPS, step) then
		return
	end
	tutorial[step] = true

	local allDone = true
	for _, name in STEPS do
		if not tutorial[name] then
			allDone = false
		end
	end
	tutorial.Done = allDone
	DataService.Replicate(player)

	if allDone then
		task.delay(DONE_MESSAGE_WAIT, function()
			if player:IsDescendantOf(Players) then
				Notifier.Send(player, DONE_MESSAGE, "good", nil, true) -- in rainbow
			end
		end)
	end
end

return TutorialService
