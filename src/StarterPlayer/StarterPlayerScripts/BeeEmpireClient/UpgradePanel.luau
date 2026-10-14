--[[
	UpgradePanel - the "Upgrade Shop" window. It opens when you press E at the Upgrade Shop
	on your plot, and closes by itself when you walk away.

	One bright panel per upgrade (from GameConfig.UpgradeOrder): the Beehive, Queen's Luck,
	Bee Speed, More Rolls, Walk Speed and Roll Speed. Each panel shows a picture, the name, what you have
	now and what the next level gives ("Holds 2 > 4 bees"), and a green price button.
	Roll Speed only shows once Auto Roll has been bought (the window is shorter until then).

	The price button only sends a request; the server checks your coins and that you are
	standing at your shop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("BeeEmpire")
local GameConfig = require(sharedFolder:WaitForChild("GameConfig"))
local NumberFormat = require(sharedFolder:WaitForChild("NumberFormat"))
local Upgrades = require(sharedFolder:WaitForChild("Upgrades"))
local remotes = sharedFolder:WaitForChild("Remotes")

local Kit = require(script.Parent.UIKit)
local State = require(script.Parent.State)

local UpgradePanel = {}

-- (Kept short on purpose: a window is shrunk until its whole height fits the screen, so a
-- shorter window shows bigger on a phone.)
local WIDTH = 840
local ROW_HEIGHT = 100
local ROW_GAP = 10
local TILE = ROW_HEIGHT - 24 -- the dark square behind each picture
local CLOSE_DISTANCE = 24 -- studs from the shop before the window closes by itself

-- each upgrade has its own bright panel: a left-to-right fade through these colours
local ROW_FADES = {
	Hive = { Color3.fromRGB(255, 108, 196), Color3.fromRGB(181, 101, 255) },
	Luck = { Color3.fromRGB(255, 226, 60), Color3.fromRGB(255, 138, 203), Color3.fromRGB(200, 115, 255) },
	BeeSpeed = { Color3.fromRGB(255, 185, 138), Color3.fromRGB(255, 74, 60) },
	Rolls = { Color3.fromRGB(70, 222, 255), Color3.fromRGB(58, 132, 255) },
	RollSpeed = { Color3.fromRGB(160, 240, 110), Color3.fromRGB(28, 186, 160) },
	WalkSpeed = { Color3.fromRGB(126, 214, 255), Color3.fromRGB(132, 112, 255) },
}
local DEFAULT_FADE = { Color3.fromRGB(116, 198, 255), Color3.fromRGB(58, 157, 240) }

local player = Players.LocalPlayer
local panel
-- [upgrade id] = the pieces of its row
local rows: { [string]: { Frame: Frame, Level: TextLabel, Change: TextLabel, Button: any, Picture: Frame?, ShownLevel: number } } = {}

-- How tall everything inside the window is with this many upgrades showing.
local function contentHeight(count: number): number
	return count * ROW_HEIGHT + math.max(0, count - 1) * ROW_GAP
end

-- "Holds 2 > 4 bees": what you have now and what the next level gives. (For More Rolls the
-- stands of the "+2 Rolls" pass are counted in, so the words match the stands by the Queen.)
local function changeText(id: string, level: number): string
	if not Upgrades.NextCost(id, level) then
		return Upgrades.DescribeTop(id, level, State.PassStands())
	end
	return Upgrades.DescribeChange(id, level, State.PassStands())
end

local function refresh()
	if not panel or not panel.IsOpen() then
		return
	end
	local coins = State.Number("Coins")
	panel.CoinText.Text = NumberFormat.Short(coins)
	local showing = 0
	for id, row in rows do
		-- (Roll Speed is not there until Auto Roll has been bought)
		local available = State.UpgradeAvailable(id)
		row.Frame.Visible = available
		if available then
			showing += 1
		end
		local level = State.UpgradeLevel(id)
		local cost = Upgrades.NextCost(id, level)

		row.Level.Text = Upgrades.LevelText(id, level) -- "Level 2 / 3", "Level 7" for Queen's Luck, "7 / 50 bought" for Walk Speed
		row.Change.Text = changeText(id, level)
		if cost then
			row.Button.SetText(NumberFormat.Short(cost))
			row.Button.SetEnabled(coins >= cost) -- grey until you can afford it
		else
			row.Button.SetText(Upgrades.TopLabel(id)) -- "MAX"
			row.Button.SetEnabled(false)
		end

		-- the beehive's picture grows with its level
		if row.Picture and row.ShownLevel ~= level then
			row.ShownLevel = level
			row.Picture:ClearAllChildren()
			local hivePicture = Kit.HiveIcon(row.Picture, TILE - 14, level)
			hivePicture.AnchorPoint = Vector2.new(0.5, 0.5)
			hivePicture.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
	-- the window is only as tall as the upgrades it shows
	panel.Root.Size = UDim2.fromOffset(WIDTH, contentHeight(showing) + 102)
end

local function buildRow(parent: Instance, id: string, order: number)
	local fade = ROW_FADES[id] or DEFAULT_FADE
	local row = Kit.Create("Frame", {
		Name = "Row_" .. id,
		BackgroundColor3 = Kit.Colors.White,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.Corner(row, 14)
	Kit.Stroke(row, 3.5)
	local points = {}
	for index, color in fade do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#fade - 1), color))
	end
	Kit.Create("UIGradient", { Color = ColorSequence.new(points), Parent = row })

	-- the picture, on a darker tile
	local tile = Kit.Create("Frame", {
		Name = "Icon",
		BackgroundColor3 = Kit.Colors.Outline,
		BackgroundTransparency = 0.78,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(TILE, TILE),
		Parent = row,
	})
	Kit.Corner(tile, 14)
	Kit.Stroke(tile, 3)
	local function centred(picture: GuiObject)
		picture.AnchorPoint = Vector2.new(0.5, 0.5)
		picture.Position = UDim2.fromScale(0.5, 0.5)
	end
	local picture: Frame? = nil
	if id == "Hive" then
		-- (refresh draws the hive here, taller as it levels up)
		picture = Kit.Create("Frame", { Name = "Hive", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = tile })
	elseif id == "BeeSpeed" then
		centred(Kit.SpeedIcon(tile, TILE - 10))
	elseif id == "Luck" then
		centred(Kit.CloverIcon(tile, TILE - 14))
	elseif id == "Rolls" then
		centred(Kit.EggIcon(tile, TILE - 12))
	elseif id == "RollSpeed" then
		centred(Kit.FastEggIcon(tile, TILE - 4))
	elseif id == "WalkSpeed" then
		centred(Kit.WalkSpeedIcon(tile, TILE - 4))
	else
		centred(Kit.JarIcon(tile, TILE - 20))
	end

	-- name, with the level over at the right
	Kit.Label({
		Parent = row,
		Name = "UpgradeName",
		Text = Upgrades.DisplayName(id),
		TextSize = 32,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(TILE + 28, 8),
		Size = UDim2.new(1, -(TILE + 28) - 372, 0, 40),
		Stroke = 4,
		Fit = true,
	})
	local levelText = Kit.Label({
		Parent = row,
		Name = "Level",
		Text = "",
		TextSize = 19,
		XAlign = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -226, 0, 16),
		Size = UDim2.fromOffset(140, 24),
		Stroke = 3,
		Fit = true,
	})

	-- "Holds 2 > 4 bees" in bright green
	local changeLabel = Kit.Label({
		Parent = row,
		Name = "Change",
		Text = "",
		TextSize = 24,
		Color = Kit.Colors.Lime,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(TILE + 28, 52),
		Size = UDim2.new(1, -(TILE + 28) - 226, 0, 34),
		Stroke = 3.5,
		Fit = true,
	})

	-- the price: a green button with a coin on it (grey while you cannot afford it)
	local button = Kit.Button({
		Parent = row,
		Name = "Buy",
		Text = "",
		TextSize = 30,
		Color = Kit.Colors.Green,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(196, 60),
		Layout = "Row",
		Icon = function(area)
			centred(Kit.CoinIcon(area, 40))
		end,
		OnClick = function()
			remotes.BuyUpgrade:FireServer(id)
		end,
	})

	rows[id] = { Frame = row, Level = levelText, Change = changeLabel, Button = button, Picture = picture, ShownLevel = 0 }
end

function UpgradePanel.Init(gui: ScreenGui)
	local count = #GameConfig.UpgradeOrder
	panel = Kit.Panel({
		Parent = gui,
		Name = "UpgradePanel",
		Title = "Upgrade Shop",
		Size = Vector2.new(WIDTH, contentHeight(count) + 102),
		HeaderColor = Kit.Colors.Blue,
		CoinReadout = true,
		Icon = function(holder)
			-- a green "up" arrow
			Kit.ArrowIcon(holder, 84)
		end,
	})

	Kit.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, ROW_GAP),
		Parent = panel.Content,
	})
	for order, id in GameConfig.UpgradeOrder do
		buildRow(panel.Content, id, order)
	end

	panel.OnOpen = function()
		for _, row in rows do
			row.ShownLevel = 0
		end
		refresh()
	end
	State.Changed:Connect(refresh)

	-- close the window if the player walks away from their shop
	task.spawn(function()
		while true do
			task.wait(0.3)
			if panel.IsOpen() then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local shopSpot = nil
				for _, plot in workspace.Plots:GetChildren() do
					if plot:GetAttribute("OwnerUserId") == player.UserId then
						local shop = plot:FindFirstChild("Upgrades")
						shopSpot = shop and shop:FindFirstChild("UpgradeSpot")
					end
				end
				if root and shopSpot and (root.Position - shopSpot.Position).Magnitude > CLOSE_DISTANCE then
					panel.Close()
				end
			end
		end
	end)
end

function UpgradePanel.Open()
	panel.Open()
end

return UpgradePanel
