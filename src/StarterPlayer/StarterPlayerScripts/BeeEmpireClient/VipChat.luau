--[[
	VipChat - a gold [VIP] in front of the chat messages of players who own the VIP pass.

	Every player's device does this for the messages it shows. It only looks at the mark the
	SERVER puts on a player who owns the pass (the attribute Pass_VIP), so nobody can give
	themselves the tag.
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local VipChat = {}

local TAG = '<font color="#FFCD32">[VIP]</font> '

function VipChat.Init()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local source = message.TextSource
		local sender = if source then Players:GetPlayerByUserId(source.UserId) else nil
		if sender and sender:GetAttribute("Pass_VIP") == true then
			local properties = Instance.new("TextChatMessageProperties")
			properties.PrefixText = TAG .. message.PrefixText
			return properties
		end
		return nil
	end
end

return VipChat
