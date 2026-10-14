--[[
	SettingsService - what a player chooses in the Settings window (the gear button).

	- Music and Sounds: how loud, from 0 to 100. The server only remembers these (and saves
	  them); the player's own device does the turning up and down.
	- StopFor: the kinds of bee Auto Roll waits for.
	- Luck: how much of their Queen's Luck the player wants to use. Never more than they own.
	- AutoSell: whether the Auto Sell pass is switched on (the switch is on its card in the Shop).
	- OtherBees: whether the other players' flying bees show on this player's screen. (Only
	  their own screen changes: nobody else sees any difference.)

	The player's screen only ASKS. Every value is checked here before it is kept.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)
local BeeService = require(script.Parent.BeeService)
local DataService = require(script.Parent.DataService)

local SettingsService = {}

local VOLUMES = { Music = true, Sounds = true }

-- The name Main uses for its "not too fast" check, or nil when the request makes no sense.
-- (Each bee kind has its own name, so ticking two bees quickly never drops one.)
function SettingsService.KeyFor(name: any, value: any): string?
	if typeof(name) ~= "string" then
		return nil
	end
	if VOLUMES[name] or name == "Luck" or name == "AutoSell" or name == "OtherBees" then
		return "Setting_" .. name
	end
	if name == "StopFor" and typeof(value) == "string" and GameConfig.Rarities[value] then
		return "Setting_StopFor_" .. value
	end
	return nil
end

-- Main has already checked that the player's data has loaded and that they are not spamming.
function SettingsService.Set(player: Player, name: any, value: any, extra: any)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local settings = data.Settings

	if VOLUMES[name] then
		-- value: 0 to 100
		if typeof(value) ~= "number" or value ~= value then
			return
		end
		settings[name] = math.clamp(math.floor(value + 0.5), 0, 100)
	elseif name == "StopFor" then
		-- value: a kind of bee ("Rare"), extra: true = wait for it, false = roll past it
		if typeof(value) ~= "string" or not GameConfig.Rarities[value] or typeof(extra) ~= "boolean" then
			return
		end
		settings.StopFor[value] = if extra then true else nil
	elseif name == "Luck" then
		-- value: a Queen's Luck level the player owns
		if typeof(value) ~= "number" or value ~= value or value % 1 ~= 0 then
			return
		end
		if value < 1 or value > DataService.UpgradeLevel(data, "Luck") then
			return
		end
		settings.Luck = value
	elseif name == "AutoSell" then
		-- value: true = on, false = off (it only does anything for a player who owns the pass)
		if typeof(value) ~= "boolean" then
			return
		end
		settings.AutoSell = value
	elseif name == "OtherBees" then
		-- value: true = show the other players' flying bees, false = hide them (on this player's screen only)
		if typeof(value) ~= "boolean" then
			return
		end
		settings.OtherBees = value
	else
		return
	end

	DataService.Replicate(player)
	if name == "StopFor" then
		BeeService.RefreshWaiting(player) -- Auto Roll may start or stop waiting right now
	end
end

return SettingsService
