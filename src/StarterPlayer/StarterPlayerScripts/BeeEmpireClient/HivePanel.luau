--[[
	HivePanel - the "My Hive" window (it opens from the My Hive button or at your hive).

	Left:   your beehive and its level (bigger hives are bought at the Upgrade Shop).
	Right:  the spots in your hive (locked spots show which hive level unlocks them),
	        and under them the buttons.

	How it works:
	- Tap a bee in the hive to pick it, then press Take Out to move it to your Inventory.
	- Equip Best puts your strongest bees to work in one go.
	- Spare bees live in the Inventory (the backpack button). The Inventory button here,
	  or a tap on an empty spot, opens it.

	Every button only sends a request; the server checks it and makes the change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("BeeEmpire")
local GameConfig = require(sharedFolder:WaitForChild("GameConfig"))
local NumberFormat = require(sharedFolder:WaitForChild("NumberFormat"))
local remotes = sharedFolder:WaitForChild("Remotes")

local Kit = require(script.Parent.UIKit)
local State = require(script.Parent.State)
local Effects = require(script.Parent.Effects)

local HivePanel = {}

local CARD_SIZE = Vector2.new(94, 106) -- a hive spot

local panel
local openInventory: ((string?) -> ())? = nil -- opens the Inventory window (given by ClientMain)
local hivePicture: Frame -- where the big hive picture is drawn
local headerPicture: Frame -- and the one in the title bar
local hiveName: TextLabel
local hiveLevelText: TextLabel
local hiveHoldsText: TextLabel
local nextTitle: TextLabel
local nextDetails: TextLabel
local nextCostRow: Frame
local nextCostText: TextLabel
local shopNote: TextLabel
local slotsTitle: TextLabel
local slotGrid: Frame
local selectedText: TextLabel
local spareText: TextLabel
local takeOutButton
local inventoryButton

local pickedSlot: number? = nil -- the hive spot whose bee is picked
local lastSignature = ""
local shownHiveLevel = 0
local slotCards: { [number]: any } = {}

-- The hive level that unlocks a slot, e.g. slot 5 -> level 3.
local function levelForSlot(slotIndex: number): number
	for level, hive in GameConfig.HiveLevels do
		if hive.Capacity >= slotIndex then
			return level
		end
	end
	return #GameConfig.HiveLevels
end

-- THE HIVE (left side) -------------------------------------------------------------

local function refreshHiveInfo()
	local level = State.HiveLevel()
	local hive = GameConfig.GetHive(level)
	local coins = State.Number("Coins")
	panel.CoinText.Text = NumberFormat.Short(coins)

	if level ~= shownHiveLevel then
		shownHiveLevel = level
		-- the hive pictures grow taller with the hive's level
		hivePicture:ClearAllChildren()
		local big = Kit.HiveIcon(hivePicture, 112, level)
		big.AnchorPoint = Vector2.new(0.5, 0.5)
		big.Position = UDim2.fromScale(0.5, 0.5)
		headerPicture:ClearAllChildren()
		Kit.HiveIcon(headerPicture, 84, level)
	end

	hiveName.Text = hive.Name
	hiveLevelText.Text = "Level " .. level .. " of " .. #GameConfig.HiveLevels
	hiveHoldsText.Text = "Holds " .. hive.Capacity .. " bees"

	-- the hive itself is bought at the Upgrade Shop; this window only shows what comes next
	local nextHive = State.NextHive()
	if nextHive then
		nextTitle.Text = "Next: " .. nextHive.Name
		nextDetails.Text = "Holds " .. nextHive.Capacity .. " bees"
		nextDetails.TextColor3 = Kit.Colors.Lime
		nextCostRow.Visible = true
		nextCostText.Text = NumberFormat.Short(nextHive.Cost)
		if coins >= nextHive.Cost then
			shopNote.Text = "You can afford it!\nGo to the Upgrade Shop!"
			shopNote.TextColor3 = Kit.Colors.Money
		else
			shopNote.Text = "Buy it at your Upgrade Shop"
			shopNote.TextColor3 = Kit.Colors.White
		end
	else
		nextTitle.Text = "The biggest hive!"
		nextDetails.Text = "You have the Royal treatment"
		nextDetails.TextColor3 = Kit.Colors.White
		nextCostRow.Visible = false
		shopNote.Text = "MAX LEVEL"
		shopNote.TextColor3 = Kit.Colors.Honey
	end
end

-- PICKING BEES ----------------------------------------------------------------------

-- Updates outlines and buttons to match what is picked (no rebuilding).
local function updateSelectionLook()
	if pickedSlot and not State.Cell(pickedSlot) then
		pickedSlot = nil -- that bee is no longer there
	end
	for slotIndex, card in slotCards do
		if slotIndex <= State.Capacity() then
			card.SetSelected(slotIndex == pickedSlot)
		end
	end

	if pickedSlot then
		local pickedName = State.Cell(pickedSlot) :: string
		local bee = GameConfig.Bees[pickedName]
		selectedText.Text = "Picked: " .. bee.BeeName
		Kit.RarityText(selectedText, pickedName, 0.3)
		takeOutButton.SetEnabled(true)
	else
		selectedText.Text = if State.TotalBees() > 0 then "Tap a bee to pick it" else "Roll bees at your Queen!"
		Kit.SetRainbow(selectedText, false)
		selectedText.TextColor3 = Kit.Colors.White
		takeOutButton.SetEnabled(false)
	end

	local spare = State.BagTotal()
	inventoryButton.SetText(if spare > 0 then "Inventory (" .. spare .. ")" else "Inventory")
	spareText.Text = if spare > 0
		then "You have " .. spare .. (if spare == 1 then " spare bee" else " spare bees") .. " in your Inventory."
		else "Spare bees wait in your Inventory."
end

local function onSlotClicked(slotIndex: number)
	if slotIndex > State.Capacity() then
		Effects.Toast("Upgrade your hive to unlock this spot!", "info")
		return
	end

	if State.Cell(slotIndex) then
		pickedSlot = if pickedSlot == slotIndex then nil else slotIndex
	elseif State.BagTotal() > 0 then
		-- an empty spot: the spare bees are in the Inventory
		if openInventory then
			openInventory("Bees")
		end
		return
	else
		Effects.Toast("Roll a bee at your Queen first!", "info")
	end
	updateSelectionLook()
end

local function rebuild()
	local capacity = State.Capacity()
	for _, child in slotGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(slotCards)
	local working = 0
	for slotIndex = 1, GameConfig.MaxHiveCapacity do
		local unlocked = slotIndex <= capacity
		local rarityName = if unlocked then State.Cell(slotIndex) else nil
		if rarityName then
			working += 1
		end
		slotCards[slotIndex] = Kit.BeeCard({
			Parent = slotGrid,
			Name = "Slot" .. slotIndex,
			RarityName = rarityName,
			Size = CARD_SIZE,
			Compact = true,
			LockedText = if unlocked then nil else "Lv " .. levelForSlot(slotIndex),
			EmptyText = "Empty",
			LayoutOrder = slotIndex,
			OnClick = function()
				onSlotClicked(slotIndex)
			end,
		})
	end
	slotsTitle.Text = string.format('Bees in your hive  <font color="#%s">%d / %d</font>', Kit.Colors.Money:ToHex(), working, capacity)
	updateSelectionLook()
end

local function signature(): string
	local parts = { tostring(State.HiveLevel()), tostring(State.BagTotal()) }
	for slotIndex = 1, GameConfig.MaxHiveCapacity do
		table.insert(parts, State.Cell(slotIndex) or "-")
	end
	return table.concat(parts, ",")
end

local function refreshIfChanged()
	if not panel.IsOpen() then
		return
	end
	refreshHiveInfo()
	local current = signature()
	if current ~= lastSignature then
		lastSignature = current
		rebuild()
	end
end

-- BUILDING THE WINDOW ------------------------------------------------------------------

local function buildHiveSide(content: Instance)
	local box = Kit.Box(content, UDim2.new(), UDim2.new(0, 232, 1, 0), nil, "HiveBox")

	-- the hive's picture, on a honey-coloured tile
	local tile = Kit.Create("Frame", {
		Name = "Picture",
		BackgroundColor3 = Kit.Colors.White,
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.new(1, -28, 0, 134),
		Parent = box,
	})
	Kit.Corner(tile, 12)
	Kit.Stroke(tile, 3)
	Kit.Gradient(tile, Color3.fromRGB(255, 246, 204), Kit.Colors.Honey)
	hivePicture = Kit.Create("Frame", { Name = "Hive", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = tile })

	hiveName = Kit.Label({
		Parent = box,
		Name = "HiveName",
		Text = "",
		TextSize = 32,
		Color = Kit.Colors.Honey,
		Position = UDim2.fromOffset(8, 154),
		Size = UDim2.new(1, -16, 0, 40),
		Stroke = 4,
		Fit = true,
	})
	hiveLevelText = Kit.Label({ Parent = box, Text = "", TextSize = 21, Position = UDim2.fromOffset(8, 196), Size = UDim2.new(1, -16, 0, 26), Fit = true })
	hiveHoldsText = Kit.Label({ Parent = box, Text = "", TextSize = 21, Position = UDim2.fromOffset(8, 224), Size = UDim2.new(1, -16, 0, 26), Fit = true })

	-- what the next hive level gives, and what it costs
	local nextBox = Kit.Create("Frame", {
		Name = "NextBox",
		BackgroundColor3 = Kit.Colors.Outline,
		BackgroundTransparency = 0.4,
		Position = UDim2.fromOffset(12, 262),
		Size = UDim2.new(1, -24, 0, 100),
		Parent = box,
	})
	Kit.Corner(nextBox, 12)
	Kit.Stroke(nextBox, 3)
	nextTitle = Kit.Label({ Parent = nextBox, Text = "", TextSize = 22, Color = Kit.Colors.Honey, Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 0, 28), Fit = true })
	nextDetails = Kit.Label({ Parent = nextBox, Text = "", TextSize = 19, Color = Kit.Colors.Lime, Position = UDim2.fromOffset(6, 36), Size = UDim2.new(1, -12, 0, 24), Fit = true })
	nextCostRow = Kit.Create("Frame", {
		Name = "Cost",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = nextBox,
	})
	Kit.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = nextCostRow,
	})
	Kit.CoinIcon(nextCostRow, 24)
	nextCostText = Kit.Label({ Parent = nextCostRow, Text = "", TextSize = 21, Size = UDim2.fromOffset(0, 28), LayoutOrder = 2 })
	nextCostText.AutomaticSize = Enum.AutomaticSize.X

	shopNote = Kit.Label({
		Parent = box,
		Name = "ShopNote",
		Text = "",
		TextSize = 16,
		Position = UDim2.new(0, 10, 1, -78),
		Size = UDim2.new(1, -20, 0, 68),
		Stroke = 3,
		Fit = true,
	})
	shopNote.TextWrapped = true
end

local function buildBeeSide(content: Instance)
	local left = 248
	local gridHeight = CARD_SIZE.Y * 2 + 8

	slotsTitle = Kit.Label({
		Parent = content,
		Name = "SlotsTitle",
		Text = "Bees in your hive",
		TextSize = 26,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(left + 2, 0),
		Size = UDim2.new(1, -left - 4, 0, 32),
		Fit = true,
	})
	slotsTitle.RichText = true -- the "2 / 2" is written in green
	slotGrid = Kit.Create("Frame", {
		Name = "Slots",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(left, 38),
		Size = UDim2.new(1, -left, 0, gridHeight),
		Parent = content,
	})
	Kit.Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
		CellPadding = UDim2.fromOffset(8, 8),
		FillDirectionMaxCells = 6,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = slotGrid,
	})

	-- under the spots: what is picked, and the buttons
	local boxY = 38 + gridHeight + 12
	local box = Kit.Box(content, UDim2.fromOffset(left, boxY), UDim2.new(1, -left, 1, -boxY), nil, "Actions")
	selectedText = Kit.Label({
		Parent = box,
		Name = "Picked",
		Text = "",
		TextSize = 24,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 30),
		Fit = true,
	})
	local buttonY = 50
	takeOutButton = Kit.Button({
		Parent = box,
		Name = "TakeOut",
		Text = "Take Out",
		TextSize = 25,
		Color = Kit.Colors.Orange,
		Position = UDim2.fromOffset(14, buttonY),
		Size = UDim2.fromOffset(176, 58),
		OnClick = function()
			if pickedSlot then
				remotes.RemoveBee:FireServer(pickedSlot) -- it goes to the Inventory
				pickedSlot = nil
				updateSelectionLook()
			end
		end,
	})
	Kit.Button({
		Parent = box,
		Name = "EquipBest",
		Text = "Equip Best",
		TextSize = 25,
		Color = Kit.Colors.Pink,
		Position = UDim2.fromOffset(198, buttonY),
		Size = UDim2.fromOffset(186, 58),
		OnClick = function()
			pickedSlot = nil
			remotes.EquipBest:FireServer()
		end,
	})
	inventoryButton = Kit.Button({
		Parent = box,
		Name = "Inventory",
		Text = "Inventory",
		TextSize = 25,
		Color = Kit.Colors.Blue,
		Position = UDim2.fromOffset(392, buttonY),
		Size = UDim2.fromOffset(202, 58),
		Layout = "Row",
		Icon = function(area)
			local icon = Kit.BackpackIcon(area, 44)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
		end,
		OnClick = function()
			if openInventory then
				openInventory("Bees")
			end
		end,
	})
	spareText = Kit.Label({
		Parent = box,
		Name = "Spare",
		Text = "",
		TextSize = 20,
		Color = Kit.Colors.Cream,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, buttonY + 66),
		Size = UDim2.new(1, -32, 0, 28),
		Fit = true,
	})
end

-- openInventoryWindow(tabName) opens the Inventory window (the spare bees live there).
function HivePanel.Init(gui: ScreenGui, openInventoryWindow: ((string?) -> ())?)
	openInventory = openInventoryWindow
	panel = Kit.Panel({
		Parent = gui,
		Name = "HivePanel",
		Title = "My Hive",
		Size = Vector2.new(900, 548),
		HeaderColor = Kit.Colors.Title,
		CoinReadout = true,
		Icon = function(holder)
			headerPicture = holder
		end,
	})
	local content = panel.Content -- 856 x 446

	buildHiveSide(content)
	buildBeeSide(content)

	panel.OnOpen = function()
		pickedSlot = nil
		lastSignature = ""
		shownHiveLevel = 0
		refreshIfChanged()
	end
	panel.OnClose = function()
		pickedSlot = nil
	end

	State.Changed:Connect(refreshIfChanged)
end

function HivePanel.Toggle()
	panel.Toggle()
end

function HivePanel.Open()
	panel.Open()
end

return HivePanel
