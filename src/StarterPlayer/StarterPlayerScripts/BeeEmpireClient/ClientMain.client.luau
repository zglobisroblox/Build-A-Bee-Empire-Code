--[[
	ClientMain - starts all the screen UI and visual effects on the player's device.

	The UI is built by code (see UIKit for the style). It only shows things and sends
	requests; the server decides everything that matters.

	Keyboard shortcut: B opens and closes the My Hive window.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local remotes = ReplicatedStorage:WaitForChild("BeeEmpire"):WaitForChild("Remotes")
local NumberFormat = require(ReplicatedStorage:WaitForChild("BeeEmpire"):WaitForChild("NumberFormat"))
local GameConfig = require(ReplicatedStorage:WaitForChild("BeeEmpire"):WaitForChild("GameConfig"))

local folder = script.Parent
local Kit = require(folder.UIKit)
local Effects = require(folder.Effects)
local HUD = require(folder.HUD)
local HivePanel = require(folder.HivePanel)
local UpgradePanel = require(folder.UpgradePanel)
local SettingsPanel = require(folder.SettingsPanel)
local WelcomePanel = require(folder.WelcomePanel)
local DailyPanel = require(folder.DailyPanel)
local InventoryPanel = require(folder.InventoryPanel)
local ShopPanel = require(folder.ShopPanel)
local VipChat = require(folder.VipChat)
local State = require(folder.State)
local LeaveBanner = require(folder.LeaveBanner)
local Audio = require(folder.Audio)
local WorldFX = require(folder.WorldFX)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local mainGui = Kit.Create("ScreenGui", {
	Name = "BeeEmpireUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 10,
	Parent = playerGui,
})
-- The HUD sits above the windows (and their dark backdrop), so its buttons always work.
local hudGui = Kit.Create("ScreenGui", {
	Name = "BeeEmpireHUD",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 12,
	Parent = playerGui,
})
local effectsGui = Kit.Create("ScreenGui", {
	Name = "BeeEmpireEffects",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 20,
	Parent = playerGui,
})

Effects.Init(effectsGui)
HUD.Init(hudGui, HivePanel.Toggle, SettingsPanel.Toggle, DailyPanel.Toggle, InventoryPanel.Toggle, ShopPanel.Toggle)
HivePanel.Init(mainGui, InventoryPanel.Open)
InventoryPanel.Init(mainGui) -- spare bees and saved boosts
ShopPanel.Init(mainGui) -- passes (things bought with Robux)
VipChat.Init() -- the gold [VIP] in the chat
UpgradePanel.Init(mainGui)
SettingsPanel.Init(mainGui)
WelcomePanel.Init(mainGui) -- "Welcome Back!": the honey the bees made while you were away
DailyPanel.Init(mainGui) -- Daily Rewards
LeaveBanner.Init(playerGui) -- "Your Bees Earn Offline!" while Roblox's own menu is open
Audio.Init() -- the song, and the volumes chosen in Settings
WorldFX.Init(HivePanel.Open, UpgradePanel.Open)

-- Where coins and jars should start flying from (your own market / station).
local function myPlotPart(modelName: string, partName: string): Vector3?
	for _, plot in workspace.Plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			local model = plot:FindFirstChild(modelName)
			local part = model and model:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				return part.Position + Vector3.new(0, 3, 0)
			end
		end
	end
	return nil
end

remotes.Notify.OnClientEvent:Connect(function(text, kind, color, rainbow)
	if typeof(text) == "string" then
		Effects.Toast(text, if typeof(kind) == "string" then kind else nil, if typeof(color) == "Color3" then color else nil, rainbow == true)
	end
end)

remotes.Effect.OnClientEvent:Connect(function(effectName, value)
	if effectName == "Bought" and typeof(value) == "table" and typeof(value.Rarity) == "string" then
		local placed = value.Placed == true
		-- the bee flies off its honeycomb stand, to your hive or up into your bag
		WorldFX.PlayBought(value.Rarity, placed, if typeof(value.Stand) == "number" then value.Stand else 1)
		Effects.Rolled(value.Rarity, placed, true) -- the "NEW BEE!" card (its reveal jingle already played at the stand)
	elseif effectName == "Sold" and typeof(value) == "number" then
		Effects.Fly("coin", value, myPlotPart("Market", "Counter"))
	elseif effectName == "Collected" and typeof(value) == "number" then
		Effects.Fly("jar", value, myPlotPart("CollectStation", "Table"))
	elseif effectName == "OfflineClaimed" and typeof(value) == "number" then
		-- the honey made while you were away is now at your Honey Jars stand
		Kit.PlaySound("Reward")
		Effects.Toast("+" .. NumberFormat.Short(value) .. " jars are at your Honey Jars!", "good")
	elseif effectName == "DailyClaimed" and typeof(value) == "table" and typeof(value.Day) == "number" then
		-- a daily reward was collected: show what it was
		local reward = GameConfig.DailyRewards[value.Day]
		if reward and reward.Bee then
			Effects.Rolled(reward.Bee, value.Placed == true) -- the "NEW BEE!" card
		elseif reward and reward.Boost then
			-- a boost waits in the Inventory until the player presses Use there
			local name, minutes = DailyPanel.Describe(reward)
			Kit.PlaySound("Reward")
			Effects.Toast(name .. " (" .. minutes .. ") is in your Inventory!", "good", nil, true)
		elseif reward then
			Effects.Fly("coin", reward.Coins or 0, nil)
		end
	elseif effectName == "BoostUsed" and typeof(value) == "table" and typeof(value.Kind) == "string" then
		-- a boost from the Inventory has started
		local boost = GameConfig.Boosts[value.Kind]
		if boost then
			Kit.PlaySound("Reward")
			Effects.Toast(boost.Name .. " for " .. tostring(value.Minutes) .. " minutes!", "good", nil, true)
		end
	elseif effectName == "BeeDeleted" and typeof(value) == "string" then
		Kit.PlaySound("Delete")
	elseif effectName == "EggHatched" and typeof(value) == "table" and typeof(value.Bee) == "string" and GameConfig.Bees[value.Bee] then
		-- the Halloween Egg was fed: it shakes, then the new bee's card shows
		local seconds = if typeof(value.Seconds) == "number" then math.clamp(value.Seconds, 0, 6) else 2
		Kit.CloseAll()
		WorldFX.PlayEggHatch(seconds)
		task.delay(seconds, Effects.Rolled, value.Bee, value.Placed == true)
	elseif effectName == "StarterPack" and typeof(value) == "table" then
		-- the Starter Pack (a pass) was opened: its bee, then a word about its boosts
		Kit.CloseAll()
		if typeof(value.Bee) == "string" and GameConfig.Bees[value.Bee] then
			Effects.Rolled(value.Bee, value.Placed == true) -- the "NEW BEE!" card
		end
		local boosts = if typeof(value.Boosts) == "number" then value.Boosts else 0
		if boosts > 0 then
			Kit.PlaySound("Reward")
			Effects.Toast("Starter Pack opened! " .. boosts .. " boosts are in your Inventory!", "good", nil, true)
		end
	elseif effectName == "PassBought" and typeof(value) == "string" and GameConfig.Passes[value] then
		-- a pass was bought just now
		Kit.PlaySound("Celebrate")
		Effects.Toast(GameConfig.Passes[value].Name .. " is yours! Thank you!", "good", nil, true)
		if value == "Rolls" then
			Kit.CloseAll()
			WorldFX.PlayNewStand() -- sparkles where the new honeycomb stands appear
		end
	elseif effectName == "HiveUpgraded" and typeof(value) == "number" then
		Effects.HiveUpgraded(value)
	elseif effectName == "Upgraded" and typeof(value) == "table" and typeof(value.Id) == "string" and typeof(value.Level) == "number" then
		Effects.Upgraded(value.Id, value.Level, State.PassStands())
		if value.Id == "Rolls" then
			WorldFX.PlayNewStand() -- sparkles where the new honeycomb stand appears
		end
	end
end)

-- A word about the Halloween Egg, once per visit, while it is there. (Not during the tutorial,
-- and not on top of an open window.)
task.spawn(function()
	for _ = 1, 40 do
		task.wait(6)
		if State.IsLoaded() and not State.LoadingScreenUp() and State.TutorialDone() and State.EggSecondsLeft() > 0 and not Kit.IsAnyPanelOpen() then
			Kit.PlaySound("Reward", 0.8)
			Effects.Toast("The " .. GameConfig.HalloweenEgg.Name .. " is by the Flower Garden! Bring it " .. NumberFormat.Short(GameConfig.HalloweenEgg.JarCost) .. " jars!", "good", Color3.fromRGB(255, 150, 30))
			break
		end
	end
end)

-- Close any open window when your character dies.
local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(Kit.CloseAll)
	end
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	task.spawn(watchCharacter, player.Character)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.B then
		HivePanel.Toggle()
	end
end)
