--[[
	InventoryPanel - the "Inventory" window. It opens from the backpack button on the left of
	the screen. It has two tabs:

	BEES    your spare bees (the ones not working in your hive), one card per kind.
	        Tap a kind to pick it, then:
	          Equip   puts one to work (in a free spot, or in place of a weaker bee)
	          Lock    locks the kind so it cannot be deleted (Unlock undoes it)
	          Delete  throws one away for good; it needs two taps, so nobody does it by accident
	        Equip Best puts your strongest bees to work in one go.
	BOOSTS  the boosts you have saved up. Use starts one (or adds its minutes to the one
	        already running). The boosts running right now are listed at the top.

	Every button only sends a request; the server checks it and makes the change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("BeeEmpire")
local GameConfig = require(sharedFolder:WaitForChild("GameConfig"))
local remotes = sharedFolder:WaitForChild("Remotes")

local Kit = require(script.Parent.UIKit)
local State = require(script.Parent.State)

local InventoryPanel = {}

local WIDTH = 860
local TAB_ROW = 62 -- the two tab buttons and the count beside them
local BODY = 322 -- the page under them
local HEADER_COLOR = Color3.fromRGB(38, 188, 206) -- teal
local CARD_SIZE = Vector2.new(120, 112) -- one kind of spare bee (big, so its name can be read on a phone)
local BOOST_CARD = Vector2.new(176, 206) -- one kind of saved boost
local DELETE_CONFIRM_SECONDS = 2.5
local BOOST_FADES = {
	Honey = { Color3.fromRGB(255, 212, 158), Color3.fromRGB(246, 130, 46) },
	Luck = { Color3.fromRGB(182, 246, 164), Color3.fromRGB(58, 190, 98) },
}

local panel
local currentTab = "Bees"
local tabButtons: { [string]: any } = {}
local pages: { [string]: Frame } = {}
local countText: TextLabel

-- the Bees page
local beeGrid: Frame
local beeEmptyText: TextLabel
local pickedText: TextLabel
local pickedDetail: TextLabel
local equipButton
local lockButton
local deleteButton
local beeCards: { [string]: any } = {}
local picked: string? = nil -- the kind of bee that is picked
local deleteArmedFor: string? = nil
local beeSignature = ""

-- the Boosts page
local runningText: TextLabel
local boostGrid: Frame
local boostEmptyText: TextLabel
local boostSignature = ""

local function centred(icon: GuiObject)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
end

-- THE BEES PAGE -------------------------------------------------------------------------------

local function updateBeeButtons()
	if picked and (State.Bag()[picked] or 0) <= 0 then
		picked = nil -- the last one of that kind is gone
		deleteArmedFor = nil
	end
	for beeName, card in beeCards do
		card.SetSelected(beeName == picked)
	end

	if picked then
		local bee = GameConfig.Bees[picked]
		local locked = State.IsLocked(picked)
		pickedText.Text = bee.BeeName
		Kit.RarityText(pickedText, picked, 0.3)
		pickedDetail.Text = bee.DisplayName .. "  -  " .. Kit.FormatRate(bee.NectarPerSecond) .. (if locked then "  -  locked" else "")
		equipButton.SetEnabled(true)
		lockButton.SetEnabled(true)
		lockButton.SetText(if locked then "Unlock" else "Lock")
		lockButton.SetColor(if locked then Kit.Colors.Orange else Kit.Colors.Blue)
		if locked then
			deleteButton.SetText("Locked")
			deleteButton.SetEnabled(false)
		elseif deleteArmedFor == picked then
			deleteButton.SetText("Tap again!")
			deleteButton.SetColor(Kit.Colors.Orange)
			deleteButton.SetEnabled(true)
		else
			deleteButton.SetText("Delete")
			deleteButton.SetColor(Kit.Colors.Red)
			deleteButton.SetEnabled(true)
		end
	else
		pickedText.Text = if State.BagTotal() > 0 then "Tap a bee to pick it" else "No spare bees"
		Kit.SetRainbow(pickedText, false)
		pickedText.TextColor3 = Kit.Colors.White
		pickedDetail.Text = ""
		equipButton.SetEnabled(false)
		lockButton.SetText("Lock")
		lockButton.SetColor(Kit.Colors.Blue)
		lockButton.SetEnabled(false)
		deleteButton.SetText("Delete")
		deleteButton.SetColor(Kit.Colors.Red)
		deleteButton.SetEnabled(false)
	end
end

local function rebuildBees()
	for _, child in beeGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(beeCards)
	local bag = State.Bag()
	-- strongest first
	for order = #GameConfig.BeeOrder, 1, -1 do
		local beeName = GameConfig.BeeOrder[order]
		local count = bag[beeName] or 0
		if count > 0 then
			local card = Kit.BeeCard({
				Parent = beeGrid,
				RarityName = beeName,
				Size = CARD_SIZE,
				Count = count,
				LayoutOrder = #GameConfig.BeeOrder - order,
				OnClick = function()
					picked = if picked == beeName then nil else beeName
					deleteArmedFor = nil
					updateBeeButtons()
				end,
			})
			if State.IsLocked(beeName) then
				-- a little gold padlock on the corner of a locked kind
				local lock = Kit.LockIcon(card.Button, 30)
				lock.Name = "Locked"
				lock.AnchorPoint = Vector2.new(0, 1)
				lock.Position = UDim2.new(0, 2, 1, -2)
				lock.ZIndex = 3
			end
			beeCards[beeName] = card
		end
	end
	beeEmptyText.Visible = State.BagTotal() == 0
	updateBeeButtons()
end

local function beesNow(): string
	local parts = {}
	for _, beeName in GameConfig.BeeOrder do
		table.insert(parts, State.Number("Bag_" .. beeName) .. (if State.IsLocked(beeName) then "L" else ""))
	end
	return table.concat(parts, ",")
end

local function buildBeesPage(page: Frame)
	beeGrid = Kit.Create("Frame", {
		Name = "Bees",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, CARD_SIZE.Y * 2 + 8),
		Parent = page,
	})
	Kit.Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
		CellPadding = UDim2.fromOffset(8, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = beeGrid,
	})
	beeEmptyText = Kit.Label({
		Parent = page,
		Name = "Empty",
		Text = "No spare bees. A new bee goes straight to work when your hive has room!",
		TextSize = 24,
		Position = UDim2.fromOffset(40, 60),
		Size = UDim2.new(1, -80, 0, 100),
		Fit = true,
	})
	beeEmptyText.TextWrapped = true

	-- the bee that is picked, and what can be done with it
	local barTop = CARD_SIZE.Y * 2 + 16
	local bar = Kit.Box(page, UDim2.fromOffset(0, barTop), UDim2.new(1, 0, 1, -barTop), nil, "Actions")
	pickedText = Kit.Label({
		Parent = bar,
		Name = "Picked",
		Text = "",
		TextSize = 25,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.fromOffset(216, 32),
		Fit = true,
	})
	pickedDetail = Kit.Label({
		Parent = bar,
		Name = "Detail",
		Text = "",
		TextSize = 18,
		Color = Kit.Colors.Cream,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 42),
		Size = UDim2.fromOffset(216, 24),
		Fit = true,
	})
	local x = 238
	local function actionButton(name: string, text: string, color: Color3, width: number, onClick: () -> ())
		local button = Kit.Button({
			Parent = bar,
			Name = name,
			Text = text,
			TextSize = 25,
			Color = color,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, x, 0.5, 0),
			Size = UDim2.fromOffset(width, 58),
			OnClick = onClick,
		})
		x += width + 8
		return button
	end
	equipButton = actionButton("Equip", "Equip", Kit.Colors.Green, 124, function()
		if picked then
			remotes.PlaceBee:FireServer(picked) -- a free spot, or in place of a weaker bee
		end
	end)
	lockButton = actionButton("Lock", "Lock", Kit.Colors.Blue, 124, function()
		if picked then
			remotes.LockBee:FireServer(picked, not State.IsLocked(picked))
		end
	end)
	deleteButton = actionButton("Delete", "Delete", Kit.Colors.Red, 140, function()
		if not picked or State.IsLocked(picked) then
			return
		end
		local beeName = picked
		if deleteArmedFor == beeName then
			deleteArmedFor = nil
			remotes.DeleteBee:FireServer(beeName)
		else
			-- the first tap only arms the button
			deleteArmedFor = beeName
			task.delay(DELETE_CONFIRM_SECONDS, function()
				if deleteArmedFor == beeName then
					deleteArmedFor = nil
					updateBeeButtons()
				end
			end)
		end
		updateBeeButtons()
	end)
	actionButton("EquipBest", "Equip Best", Kit.Colors.Pink, 164, function()
		remotes.EquipBest:FireServer()
	end)
end

-- THE BOOSTS PAGE -----------------------------------------------------------------------------

local function refreshRunning()
	local parts = {}
	for _, kind in GameConfig.BoostOrder do
		local left = State.BoostSecondsLeft(kind)
		if left > 0 then
			local whole = math.ceil(left)
			table.insert(parts, string.format("%s  %d:%02d", GameConfig.Boosts[kind].Name, whole // 60, whole % 60))
		end
	end
	if #parts > 0 then
		runningText.Text = "Running now:   " .. table.concat(parts, "      ")
		Kit.SetRainbow(runningText, true)
	else
		runningText.Text = "No boost is running. Press Use to start one!"
		Kit.SetRainbow(runningText, false)
		runningText.TextColor3 = Kit.Colors.Cream
	end
end

local function rebuildBoosts()
	for _, child in boostGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local items = State.BoostItems()
	for order, item in items do
		local boost = GameConfig.Boosts[item.Kind]
		local card = Kit.Create("Frame", {
			Name = item.Kind .. item.Minutes,
			BackgroundColor3 = Kit.Colors.White,
			LayoutOrder = order,
			Parent = boostGrid,
		})
		Kit.Corner(card, 14)
		Kit.Stroke(card, 3.5)
		local fade = BOOST_FADES[item.Kind] or BOOST_FADES.Honey
		Kit.Gradient(card, fade[1], fade[2])
		Kit.Label({
			Parent = card,
			Name = "Title",
			Text = boost.Name,
			TextSize = 23,
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.new(1, -12, 0, 28),
			Fit = true,
		})
		local holder = Kit.Create("Frame", {
			Name = "Picture",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 36),
			Size = UDim2.fromOffset(84, 84),
			Parent = card,
		})
		Kit.BoostIcon(holder, 84, item.Kind)
		Kit.Label({
			Parent = card,
			Name = "Minutes",
			Text = item.Minutes .. " min",
			TextSize = 24,
			XAlign = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, 120),
			Size = UDim2.new(0.6, 0, 0, 28),
			Fit = true,
		})
		Kit.Label({
			Parent = card,
			Name = "Count",
			Text = "x" .. item.Count,
			TextSize = 28,
			XAlign = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 118),
			Size = UDim2.new(0.4, 0, 0, 32),
			Fit = true,
		})
		Kit.Button({
			Parent = card,
			Name = "Use",
			Text = "Use",
			TextSize = 26,
			Color = Kit.Colors.Green,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -20, 0, 48),
			OnClick = function()
				remotes.UseBoost:FireServer(item.Kind, item.Minutes) -- the server checks you really have one
			end,
		})
	end
	boostEmptyText.Visible = #items == 0
end

local function boostsNow(): string
	local parts = {}
	for _, item in State.BoostItems() do
		table.insert(parts, item.Kind .. item.Minutes .. "x" .. item.Count)
	end
	return table.concat(parts, ",")
end

local function buildBoostsPage(page: Frame)
	local strip = Kit.Box(page, UDim2.fromOffset(0, 4), UDim2.new(1, 0, 0, 52), nil, "Running")
	runningText = Kit.Label({
		Parent = strip,
		Name = "Text",
		Text = "",
		TextSize = 24,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Fit = true,
	})
	boostGrid = Kit.Create("Frame", {
		Name = "Boosts",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 1, -68),
		Parent = page,
	})
	Kit.Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(BOOST_CARD.X, BOOST_CARD.Y),
		CellPadding = UDim2.fromOffset(12, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = boostGrid,
	})
	boostEmptyText = Kit.Label({
		Parent = page,
		Name = "Empty",
		Text = "No boosts saved up. Daily Rewards give you boosts!",
		TextSize = 24,
		Position = UDim2.fromOffset(40, 110),
		Size = UDim2.new(1, -80, 0, 80),
		Fit = true,
	})
	boostEmptyText.TextWrapped = true
end

-- THE WINDOW ----------------------------------------------------------------------------------

local function refresh()
	if not panel.IsOpen() then
		return
	end
	for name, button in tabButtons do
		button.SetColor(if name == currentTab then Kit.Colors.Title else Kit.Colors.Grey)
		pages[name].Visible = name == currentTab
	end
	if currentTab == "Bees" then
		if State.OwnsPass("InfiniteInventory") then
			-- (the Infinite Inventory pass: no limit to show)
			countText.Text = string.format('Spare bees  <font color="#%s">%d</font>  (no limit)', Kit.Colors.Money:ToHex(), State.BagTotal())
		else
			countText.Text = string.format('Spare bees  <font color="#%s">%d / %d</font>', Kit.Colors.Money:ToHex(), State.BagTotal(), State.BagLimit())
		end
		local now = beesNow()
		if now ~= beeSignature then
			beeSignature = now
			rebuildBees()
		else
			updateBeeButtons()
		end
	else
		local total = 0
		for _, item in State.BoostItems() do
			total += item.Count
		end
		countText.Text = string.format('Boosts saved  <font color="#%s">%d</font>', Kit.Colors.Money:ToHex(), total)
		local now = boostsNow()
		if now ~= boostSignature then
			boostSignature = now
			rebuildBoosts()
		end
		refreshRunning()
	end
end

local function showTab(name: string)
	currentTab = name
	deleteArmedFor = nil
	refresh()
end

function InventoryPanel.Init(gui: ScreenGui)
	panel = Kit.Panel({
		Parent = gui,
		Name = "InventoryPanel",
		Title = "Inventory",
		Size = Vector2.new(WIDTH, TAB_ROW + BODY + 102),
		HeaderColor = HEADER_COLOR,
		Icon = function(holder)
			centred(Kit.BackpackIcon(holder, 84))
		end,
	})
	local content = panel.Content

	-- the two tabs
	local function tab(name: string, text: string, x: number, drawIcon: (Frame) -> ())
		tabButtons[name] = Kit.Button({
			Parent = content,
			Name = "Tab" .. name,
			Text = text,
			TextSize = 27,
			Color = Kit.Colors.Grey,
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(196, 54),
			Layout = "Row",
			Icon = drawIcon,
			OnClick = function()
				showTab(name)
			end,
		})
	end
	tab("Bees", "Bees", 0, function(area)
		centred(Kit.BeeIcon(area, 40))
	end)
	tab("Boosts", "Boosts", 206, function(area)
		centred(Kit.JarIcon(area, 38))
	end)
	countText = Kit.Label({
		Parent = content,
		Name = "Count",
		Text = "",
		TextSize = 25,
		XAlign = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(420, 8),
		Size = UDim2.new(1, -424, 0, 36),
		Fit = true,
	})
	countText.RichText = true

	for _, name in { "Bees", "Boosts" } do
		pages[name] = Kit.Create("Frame", {
			Name = name .. "Page",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, TAB_ROW),
			Size = UDim2.new(1, 0, 1, -TAB_ROW),
			Visible = false,
			Parent = content,
		})
	end
	buildBeesPage(pages.Bees)
	buildBoostsPage(pages.Boosts)

	panel.OnOpen = function()
		picked = nil
		deleteArmedFor = nil
		beeSignature = ""
		boostSignature = ""
		refresh()
	end
	panel.OnClose = function()
		picked = nil
		deleteArmedFor = nil
	end
	State.Changed:Connect(refresh)
	-- the running boosts' time counts down by itself
	task.spawn(function()
		while true do
			task.wait(0.5)
			if panel.IsOpen() and currentTab == "Boosts" then
				refreshRunning()
			end
		end
	end)
end

function InventoryPanel.Toggle()
	panel.Toggle()
end

-- Opens the window on a tab ("Bees" or "Boosts"; no tab = the one it was on).
function InventoryPanel.Open(tabName: string?)
	if tabName and pages[tabName] then
		currentTab = tabName
	end
	if panel.IsOpen() then
		refresh()
	else
		panel.Open()
	end
end

return InventoryPanel
