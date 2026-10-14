--[[
	HUD - the always-on-screen parts:
	- top middle (inside the Roblox top bar): the Equip Best and My Hive buttons, and the
	  gear button that opens Settings
	- just under them: a line of text telling you what to do next
	- bottom left: your Honey Coins (big and green), the jars you carry, how fast your bees
	  work, and your Queen's Luck ("x1.3 luck"). On phones these sit at the middle-left,
	  clear of the thumbstick.
	  (The Honey Market's price is NOT here: it is on the board above each market. The HUD
	  only pops up a rainbow message when the price turns great.)
	- bottom right (middle-right on phones, clear of the jump button): the Auto Roll switch.
	  It only shows once you have bought Auto Roll at the sign next to your Queen. While Auto
	  Roll is waiting for a bee you asked for, it turns into an orange "Keep Rolling" button.
	- left, in the middle: the backpack opens the Inventory, and above it the market stall
	  opens the Shop (passes, bought with Robux)
	A red "!" on a button means it can help you right now.
	While a window is open the whole HUD hides, so the window has room.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("BeeEmpire")
local GameConfig = require(sharedFolder:WaitForChild("GameConfig"))
local NumberFormat = require(sharedFolder:WaitForChild("NumberFormat"))
local remotes = sharedFolder:WaitForChild("Remotes")

local Kit = require(script.Parent.UIKit)
local State = require(script.Parent.State)
local Effects = require(script.Parent.Effects)

local HUD = {}

local TOP_BAR_HEIGHT = 72 -- the design height of the button row (it is scaled to fit the real top bar)

local coinsText: TextLabel
local jarsText: TextLabel
local rateText: TextLabel
local luckText: TextLabel -- the Queen's Luck in use: "x1.3 luck"
local shownLuck = 0
local shownPrice = 0 -- the Honey Market's price last seen (to notice when it turns great)
local hintLine: Frame
local hintText: TextLabel
local bagBadge: Frame
local equipBadge: Frame
local hiveIconArea: Frame -- where the My Hive button's picture is drawn
local shownHiveLevel = 0
local equipButton
local autoArea: Frame -- holds the Auto Roll switch
local autoButton
local autoFound: TextLabel -- "Guard Bee found!" above the button while Auto Roll is waiting
local rows: { [string]: Frame } = {}
local boostRows: { [string]: { Slot: Frame, Text: TextLabel } } = {} -- one line per running boost: "x2 honey  9:41"
local dailyBadge: Frame -- the "!" on the small Daily Rewards calendar (top right)
local inventoryArea: Frame -- holds the Inventory button (left, in the middle)
local coinTween = Instance.new("NumberValue")
local lastHint: string? = nil -- (nil = nothing shown yet, so the first hint is always drawn, even an empty one)

local function bounce(frame: Instance?)
	local scale = frame and frame:FindFirstChild("Bounce") :: UIScale?
	if scale then
		scale.Scale = 1.18
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- One line of the readout: a picture, then a number with a dark outline.
local function makeRow(parent: Instance, name: string, order: number, height: number, textSize: number, color: Color3)
	local slot = Kit.Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(300, height),
		LayoutOrder = order,
		Parent = parent,
	})
	-- the part that bounces (kept inside the slot so the other lines do not jump)
	local row = Kit.Create("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = slot,
	})
	Kit.Create("UIScale", { Name = "Bounce", Parent = row })
	local iconHolder = Kit.Create("Frame", {
		Name = "IconHolder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(height, height),
		Parent = row,
	})
	local text = Kit.Label({
		Parent = row,
		Name = "Amount",
		Text = "0",
		TextSize = textSize,
		Color = color,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(height + 8, 0),
		Size = UDim2.new(1, -height - 8, 1, 0),
		Stroke = math.max(3, textSize * 0.1),
	})
	rows[name] = row
	return row, iconHolder, text
end

local function centre(icon: GuiObject)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
end

-- A picture you can press, with no plate behind it and (if wanted) a word under it: the
-- small buttons at the edges of the screen. drawIcon is one of Kit's picture makers.
local function pictureButton(parent: Instance, name: string, size: number, drawIcon: (Instance, number) -> Frame, word: string?, onClick: () -> ()): Frame
	local holder = Kit.Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size + (if word then 24 else 0)),
		Parent = parent,
	})
	local press = Kit.Create("UIScale", { Name = "Press", Parent = holder })
	local iconArea = Kit.Create("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Parent = holder,
	})
	centre(drawIcon(iconArea, size))
	if word then
		Kit.Label({
			Parent = holder,
			Name = "Word",
			Text = word,
			TextSize = 21,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 2),
			Size = UDim2.new(1, 34, 0, 28),
			Stroke = 3.5,
			Fit = true,
		})
	end
	local hit = Kit.Create("TextButton", {
		Name = "Hit",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = holder,
	})
	local function tween(target: number, time: number, style: Enum.EasingStyle?)
		TweenService:Create(press, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = target }):Play()
	end
	hit.MouseEnter:Connect(function()
		tween(1.08, 0.12)
	end)
	hit.MouseLeave:Connect(function()
		tween(1, 0.12)
	end)
	hit.Activated:Connect(function()
		Kit.PlaySound("Click")
		press.Scale = 0.88
		tween(1, 0.3, Enum.EasingStyle.Back)
		onClick()
	end)
	return holder
end

-- Things that change as time passes, not only when the server says something: the boosts'
-- countdowns, and the "!" on the Daily Rewards button.
local function refreshTimed()
	for _, kind in GameConfig.BoostOrder do
		local row = boostRows[kind]
		if row then
			local left = State.BoostSecondsLeft(kind)
			row.Slot.Visible = left > 0
			if left > 0 then
				local whole = math.ceil(left)
				row.Text.Text = string.format("x%g %s  %d:%02d", GameConfig.Boosts[kind].Multiplier, if kind == "Luck" then "luck" else "honey", whole // 60, whole % 60)
			end
		end
	end
	if dailyBadge then
		dailyBadge.Visible = State.DailyReady()
	end
end

local function refresh()
	local coins = State.Number("Coins")
	if coins ~= coinTween.Value then
		-- count up (or down) smoothly instead of jumping
		TweenService:Create(coinTween, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = coins }):Play()
	end
	jarsText.Text = NumberFormat.Short(State.Number("JarsCarried"))
	rateText.Text = Kit.FormatRate(State.Number("JarsPerSecond"))

	-- the Queen's Luck the player is rolling with. If they turned it down in Settings, it
	-- also says how much they own: "x1 luck (of x2.3)"
	-- (A Double Luck boost doubles both numbers and writes them in rainbow. The Lucky Queen
	-- pass doubles them too, always.)
	local luckBoost = State.BoostMultiplier("Luck")
	local luckTimes = luckBoost * State.PassLuck()
	local luck = State.LuckInUse() * luckTimes
	local owned = State.LuckOwned() * luckTimes
	luckText.Text = if luck < owned then string.format("x%g luck (of x%g)", luck, owned) else string.format("x%g luck", luck)
	Kit.SetRainbow(luckText, luckBoost > 1)
	if luckBoost <= 1 then
		luckText.TextColor3 = Kit.Colors.Lime
	end
	if State.IsLoaded() then
		if shownLuck > 0 and luck ~= shownLuck then
			bounce(rows.Luck) -- more luck!
		end
		shownLuck = luck
	end
	refreshTimed()

	-- a great price at the Honey Market: tell the player, in rainbow
	local price = State.SellPrice()
	if price ~= shownPrice then
		local first = shownPrice == 0
		shownPrice = price
		-- (not for a player whose honey sells itself: the Auto Sell pass)
		if not first and State.SellPriceIsHigh() and not State.AutoSellOn() then
			Kit.PlaySound("Alert") -- ding-ding!
			Effects.Toast(string.format("Honey price is x%.1f! Sell now!", price), "coins", nil, true)
		end
	end

	-- the hint is the tutorial: once that is done it is "" and the line is hidden for good
	local hint = State.Objective()
	if hint ~= lastHint then
		lastHint = hint
		hintText.Text = hint
		hintLine.Visible = hint ~= ""
		if hint ~= "" then
			bounce(hintLine)
		end
	end

	-- "!" on the Inventory button: a spare bee is waiting and the hive has a free spot
	bagBadge.Visible = State.BagTotal() > 0 and State.EmptyCellCount() > 0

	-- the button shows a picture of your hive as it is now
	local level = State.HiveLevel()
	if level ~= shownHiveLevel then
		shownHiveLevel = level
		hiveIconArea:ClearAllChildren()
		centre(Kit.HiveIcon(hiveIconArea, 52, level))
	end
	equipBadge.Visible = State.BetterBeeWaiting()
	-- Equip Best only makes sense once you own at least 2 bees
	equipButton.Holder.Visible = State.TotalBees() >= 2

	-- the Auto Roll switch: green while it is on, grey while it is off. While the Queen is
	-- waiting for a bee the player asked for, it is an orange "Keep Rolling" button instead.
	autoArea.Visible = State.AutoRollBought() and not Kit.IsAnyPanelOpen()
	local autoOn = State.AutoRollOn()
	local waitingFor = State.AutoRollWaiting()
	if waitingFor then
		local rarity = GameConfig.Bees[waitingFor]
		autoButton.SetText("Keep Rolling")
		autoButton.SetColor(Kit.Colors.Orange)
		autoFound.Text = rarity.BeeName .. " found!"
		Kit.RarityText(autoFound, waitingFor, 0.25) -- (rainbow for the best bees)
	else
		autoButton.SetText(if autoOn then "Auto Roll: ON" else "Auto Roll: OFF")
		autoButton.SetColor(if autoOn then Kit.Colors.Green else Kit.Colors.Grey)
	end
	autoFound.Visible = waitingFor ~= nil
end

function HUD.Init(gui: ScreenGui, openBag: () -> (), openSettings: () -> (), openDaily: () -> (), openInventory: () -> (), openShop: () -> ())
	-- BOTTOM LEFT: coins, jars, speed, luck ------------------------------------------
	local touch = Kit.IsTouch()
	local left = Kit.Create("Frame", {
		Name = "Counters",
		BackgroundTransparency = 1,
		AnchorPoint = if touch then Vector2.new(0, 0.5) else Vector2.new(0, 1),
		-- (on a phone they sit in the middle of the left edge, just right of the Inventory button)
		Position = if touch then UDim2.new(0, 16 + math.floor(112 * Kit.ScreenScale()), 0.42, 0) else UDim2.new(0, 16, 1, -12),
		Size = UDim2.fromOffset(300, 190),
		Parent = gui,
	})
	Kit.AutoScale(left)
	Kit.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = if touch then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 2),
		Parent = left,
	})

	-- running boosts, each with the time it has left (a line only shows while its boost runs)
	for index, kind in GameConfig.BoostOrder do
		local row, boostHolder, boostLabel = makeRow(left, "Boost" .. kind, index - 10, 34, 24, Kit.Colors.White)
		centre(if kind == "Luck" then Kit.CloverIcon(boostHolder, 31) else Kit.JarIcon(boostHolder, 31))
		Kit.SetRainbow(boostLabel, true)
		local slot = row.Parent :: Frame
		slot.Visible = false
		boostRows[kind] = { Slot = slot, Text = boostLabel }
	end

	-- the Queen's Luck the player is rolling with
	local _, luckHolder, luckLabel = makeRow(left, "Luck", 0, 36, 27, Kit.Colors.Lime)
	luckText = luckLabel
	centre(Kit.CloverIcon(luckHolder, 34))

	local _, rateHolder, rateLabel = makeRow(left, "Rate", 1, 36, 25, Kit.Colors.White)
	rateText = rateLabel
	centre(Kit.BeeIcon(rateHolder, 34))

	local _, jarHolder, jarLabel = makeRow(left, "Jars", 2, 46, 31, Kit.Colors.White)
	jarsText = jarLabel
	local jarIcon = Kit.JarIcon(jarHolder, 44)
	centre(jarIcon)

	local _, coinHolder, coinLabel = makeRow(left, "Coins", 3, 62, 52, Kit.Colors.Money)
	coinsText = coinLabel
	local coinIcon = Kit.CoinIcon(coinHolder, 58)
	centre(coinIcon)

	coinTween.Value = State.Number("Coins")
	coinsText.Text = NumberFormat.Short(coinTween.Value)
	coinTween.Changed:Connect(function(value)
		coinsText.Text = NumberFormat.Short(value)
	end)

	Effects.SetTarget("coin", coinIcon, function()
		bounce(rows.Coins)
	end)
	Effects.SetTarget("jar", jarIcon, function()
		bounce(rows.Jars)
	end)

	-- LEFT, IN THE MIDDLE: the backpack opens the Inventory (spare bees and saved boosts) -----
	inventoryArea = Kit.Create("Frame", {
		Name = "InventoryButton",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, if touch then 0.42 else 0.5, 0),
		Size = UDim2.fromOffset(84, 104),
		Parent = gui,
	})
	Kit.AutoScale(inventoryArea)
	local inventoryHolder = pictureButton(inventoryArea, "Button", 78, Kit.BackpackIcon, "Inventory", openInventory)
	inventoryHolder.Position = UDim2.fromOffset(3, 0)
	bagBadge = Kit.Badge(inventoryHolder, 26)
	-- (a bee bought while the hive is full flies into the backpack)
	Effects.SetTarget("bag", inventoryHolder, function()
		local press = inventoryHolder:FindFirstChild("Press") :: UIScale?
		if press then
			press.Scale = 1.2
			TweenService:Create(press, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)

	-- JUST ABOVE IT: the market stall opens the Shop (passes, bought with Robux). The button is
	-- only there when something is on sale. (In Roblox Studio it always shows, so the window
	-- can be looked at before the passes exist.)
	local onSale = RunService:IsStudio()
	for _, pass in GameConfig.Passes do
		if pass.Id ~= 0 then
			onSale = true
		end
	end
	if onSale then
		-- (it lives inside the Inventory button's frame, so it grows, shrinks and hides with it)
		local shopArea = Kit.Create("Frame", {
			Name = "ShopButton",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, -110),
			Size = UDim2.fromOffset(84, 104),
			Parent = inventoryArea,
		})
		local shopHolder = pictureButton(shopArea, "Button", 78, Kit.ShopIcon, "Shop", openShop)
		shopHolder.Position = UDim2.fromOffset(3, 0)
	end

	-- BOTTOM RIGHT: the Auto Roll switch (hidden until Auto Roll has been bought) --------
	autoArea = Kit.Create("Frame", {
		Name = "AutoRoll",
		BackgroundTransparency = 1,
		AnchorPoint = if touch then Vector2.new(1, 0.5) else Vector2.new(1, 1),
		Position = if touch then UDim2.new(1, -14, 0.42, 0) else UDim2.new(1, -16, 1, -14),
		Size = UDim2.fromOffset(236, 64),
		Visible = false,
		Parent = gui,
	})
	Kit.AutoScale(autoArea)
	autoButton = Kit.Button({
		Parent = autoArea,
		Name = "Switch",
		Text = "Auto Roll: OFF",
		TextSize = 27,
		Color = Kit.Colors.Grey,
		Size = UDim2.fromOffset(236, 64),
		OnClick = function()
			-- only requests: the server checks that Auto Roll was bought
			if State.AutoRollWaiting() then
				remotes.KeepRolling:FireServer() -- stop waiting for the bees on the stands
			else
				remotes.SetAutoRoll:FireServer(not State.AutoRollOn())
			end
		end,
	})
	autoFound = Kit.Label({
		Parent = autoArea,
		Name = "Found",
		Text = "",
		TextSize = 21,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.fromOffset(236, 28),
		Stroke = 3,
		Fit = true,
	})
	autoFound.Visible = false

	-- TOP MIDDLE: the button row, inside the Roblox top bar -----------------------------
	local topGui = Kit.Create("ScreenGui", {
		Name = "BeeEmpireTopBar",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = gui.DisplayOrder,
		ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets, -- the free part of the top bar
		Parent = gui.Parent,
	})
	local bar = Kit.Create("Frame", {
		Name = "Bar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(548, TOP_BAR_HEIGHT),
		Parent = topGui,
	})
	local barScale = Kit.Create("UIScale", { Parent = bar })
	-- (the small calendar at the top right shrinks with the row, and sits in the middle of the bar's height)
	local dailyScale: UIScale? = nil
	local dailyArea: Frame? = nil
	Kit.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		Parent = bar,
	})
	-- shrink the row to fit the real top bar (it is shorter on some devices)
	local function fitBar()
		local barHeight = GuiService.TopbarInset.Height
		if barHeight <= 0 then
			barHeight = TOP_BAR_HEIGHT
		end
		local width = topGui.AbsoluteSize.X
		local scale = barHeight / TOP_BAR_HEIGHT
		if width > 0 then
			scale = math.min(scale, width / 560)
		end
		scale = math.clamp(scale, 0.5, 1.3)
		barScale.Scale = scale
		if dailyScale and dailyArea then
			dailyScale.Scale = scale
			dailyArea.Position = UDim2.new(1, -10, 0, barHeight / 2)
		end

		-- keep the row in the middle of the SCREEN when there is room (the free part of the
		-- top bar starts to the right of the Roblox buttons, so its own middle is off-centre)
		local inset = GuiService.TopbarInset
		local camera = workspace.CurrentCamera
		local half = 274 * scale
		if camera and inset.Width > 0 then
			local x = camera.ViewportSize.X / 2 - inset.Min.X
			bar.Position = UDim2.fromOffset(math.clamp(x, half, math.max(half, inset.Width - half)), 0)
		end
	end
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fitBar)
	topGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitBar)
	fitBar()

	-- TOP RIGHT: a small calendar opens Daily Rewards (it gets a "!" when a reward is ready).
	-- It is small because the window opens by itself whenever a reward is waiting.
	local dailyFrame = Kit.Create("Frame", {
		Name = "Daily",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0, TOP_BAR_HEIGHT / 2),
		Size = UDim2.fromOffset(46, 46),
		Parent = topGui,
	})
	dailyArea = dailyFrame
	dailyScale = Kit.Create("UIScale", { Parent = dailyFrame })
	local dailyHolder = pictureButton(dailyFrame, "Button", 46, Kit.CalendarIcon, nil, openDaily)
	dailyBadge = Kit.Badge(dailyHolder, 20)
	fitBar()

	equipButton = Kit.Button({
		Parent = bar,
		Name = "EquipBest",
		Text = "Equip Best",
		TextSize = 26,
		Color = Kit.Colors.Pink,
		Size = UDim2.fromOffset(214, 56),
		LayoutOrder = 1,
		Layout = "Row",
		Icon = function(area)
			centre(Kit.BeeIcon(area, 42))
		end,
		OnClick = function()
			remotes.EquipBest:FireServer()
		end,
	})
	equipBadge = Kit.Badge(equipButton.Holder, 26)

	local bagButton = Kit.Button({
		Parent = bar,
		Name = "MyHive",
		Text = "My Hive",
		TextSize = 32,
		Color = Kit.Colors.Title,
		Size = UDim2.fromOffset(240, 68),
		LayoutOrder = 2,
		Layout = "Row",
		Icon = function(area)
			hiveIconArea = area -- (refresh draws the hive in it, taller as the hive levels up)
		end,
		OnClick = openBag,
	})

	-- the gear: opens the Settings window
	Kit.Button({
		Parent = bar,
		Name = "Settings",
		Text = "",
		Color = Kit.Colors.Purple,
		Size = UDim2.fromOffset(60, 60),
		LayoutOrder = 3,
		Layout = "Row",
		Icon = function(area)
			centre(Kit.GearIcon(area, 44))
		end,
		OnClick = openSettings,
	})

	-- UNDER THE BUTTONS: what to do next ---------------------------------------------------
	local hintArea = Kit.Create("Frame", {
		Name = "HintArea",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(760, 38),
		Parent = gui,
	})
	Kit.AutoScale(hintArea)
	hintLine = Kit.Create("Frame", {
		Name = "Hint",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = hintArea,
	})
	Kit.Create("UIScale", { Name = "Bounce", Parent = hintLine })
	hintText = Kit.Label({
		Parent = hintLine,
		Name = "Text",
		Text = "Loading your hive...",
		TextSize = 28,
		Stroke = 4,
		Fit = true,
	})

	-- While a window is open, hide the HUD so the window has room
	-- (the window shows your coins in its own title bar).
	Kit.PanelChanged:Connect(function(isOpen)
		topGui.Enabled = not isOpen
		hintArea.Visible = not isOpen
		left.Visible = not isOpen
		inventoryArea.Visible = not isOpen
		autoArea.Visible = not isOpen and State.AutoRollBought()
	end)

	State.Changed:Connect(refresh)
	refresh()
	-- the countdowns tick on by themselves
	task.spawn(function()
		while true do
			task.wait(0.5)
			refreshTimed()
		end
	end)
end

return HUD
