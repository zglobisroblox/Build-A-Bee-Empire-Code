--[[
	Notifier - sends things to ONE player's screen. It never changes game data.

	Send:   a short pop-up message. kind is "info", "good", "bad" or "coins".
	Effect: tells the screen to play an animation, for example "Hatch" or "Sold".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("BeeEmpire"):WaitForChild("Remotes")
local notifyEvent = remotes:WaitForChild("Notify")
local effectEvent = remotes:WaitForChild("Effect")

local Notifier = {}

-- rainbow = true writes the message in moving rainbow colours (for the best bees).
function Notifier.Send(player: Player, text: string, kind: string?, color: Color3?, rainbow: boolean?)
	notifyEvent:FireClient(player, text, kind or "info", color, rainbow == true)
end

function Notifier.Effect(player: Player, effectName: string, value: any)
	effectEvent:FireClient(player, effectName, value)
end

return Notifier
