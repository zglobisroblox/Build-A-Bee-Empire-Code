--[[
	ShopPanel - the "Shop" window. It opens from the market-stall button on the left of the
	screen, above the Inventory button.

	It sells PASSES: things bought once, with Robux, that last for ever. The passes are listed
	in GameConfig.Passes (THE SHOP), one card each. A card's button shows the price in Robux,
	"Owned" once the player has the pass, or (for Auto Sell) an on/off switch.

	The Buy button only sends a request. The server checks it and opens Roblox's own purchase
	window; Roblox handles the Robux. The price on a button is read from Roblox, never from
	this game's own files.

	The "Bee Chances" button shows the chance of every bee in one roll, with the luck the
	player has right now and with double luck. Roblox asks for that list wherever Robux can buy
	something that changes random rolls (Lucky Queen, +2 Rolls, the Starter Pack's luck boosts).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("BeeEmpire")
local GameConfig = require(sharedFolder:WaitForChild("GameConfig"))
local NumberFormat = require(sharedFolder:WaitForChild("NumberFormat"))
local remotes = sharedFolder:WaitForChild("Remotes")

local Kit = require(script.Parent.UIKit)
local State = require(script.Parent.State)

local ShopPanel = {}

-- (Cards are wide and low, picture on the left, so the window is not tall: a low window
-- stays big on a phone held sideways, and its writing stays readable.)
local CARD_WIDTH = 300
local CARD_HEIGHT = 174
local GAP = 12
local COLUMNS = 3
local FOOTER = 56 -- the row under the cards: the Bee Chances button and a line of writing
local HEADER_COLOR = Color3.fromRGB(238, 79, 200) -- pink
local ROBUX = utf8.char(0xE002) -- Roblox's own Robux sign
local CHANCE_ROW = 44 -- one bee's line in the Bee Chances list

-- the light and dark colour of each pass's card
local FADES: { [string]: { Color3 } } = {
	StarterPack = { Color3.fromRGB(255, 236, 140), Color3.fromRGB(255, 160, 40) },
	Rolls = { Color3.fromRGB(226, 172, 255), Color3.fromRGB(150, 72, 240) },
	LuckyQueen = { Color3.fromRGB(182, 246, 164), Color3.fromRGB(58, 190, 98) },
	AutoSell = { Color3.fromRGB(255, 212, 158), Color3.fromRGB(246, 130, 46) },
	InfiniteInventory = { Color3.fromRGB(150, 232, 240), Color3.fromRGB(38, 160, 206) },
	VIP = { Color3.fromRGB(255, 176, 226), Color3.fromRGB(226, 70, 170) },
}
local PLAIN_FADE = { Color3.fromRGB(237, 239, 246), Color3.fromRGB(169, 174, 191) }

type Card = { Key: string, Frame: Frame, Button: any }
type ChanceRow = { Now: TextLabel, Double: TextLabel, NameLabel: TextLabel, Picture: Frame, Secret: boolean }

local panel
local cards: { Card } = {}
local passesPage: Frame
local chancesPage: Frame
local luckLine: TextLabel
local chanceRows: { [string]: ChanceRow } = {}
local queenList: Frame -- the Bee Chances page: the Queen's bees
local eggList: Frame -- and the Halloween Egg's bees
local chanceNote: TextLabel
local backButton
local eggButton
local showingEgg = false
-- what Roblox says each pass costs: a number, false = not on sale, true = Roblox did not
-- answer (the button then just says "Buy"), nil = not asked yet
local prices: { [string]: number | boolean } = {}

-- The passes that get a card. A pass with no Id is not on sale: it only shows in Roblox
-- Studio, so the window can be looked at before the passes exist.
local function shownPasses(): { string }
	local list = {}
	for _, key in GameConfig.PassOrder do
		local pass = GameConfig.Passes[key]
		if pass and (pass.Id ~= 0 or RunService:IsStudio()) then
			table.insert(list, key)
		end
	end
	return list
end


-- THE PASSES ---------------------------------------------------------------------------------

local function refreshCard(card: Card)
	local key = card.Key
	local pass = GameConfig.Passes[key]
	local button = card.Button
	if State.OwnsPass(key) then
		button.SetEnabled(true)
		if key == "AutoSell" then
			-- its owner can switch it off and on again
			local on = State.AutoSellOn()
			button.SetText(if on then "Auto Sell: ON" else "Auto Sell: OFF")
			button.SetColor(if on then Kit.Colors.Green else Kit.Colors.Grey)
		else
			button.SetText(if key == "StarterPack" then "Opened" else "Owned")
			button.SetColor(Kit.Colors.Blue)
		end
		return
	end
	button.SetColor(Kit.Colors.Green)
	local price = prices[key]
	if pass.Id == 0 then
		button.SetText("Soon")
		button.SetEnabled(false)
	elseif pass.Random and not State.RandomPassesAllowed() then
		-- (Roblox's rule for some countries: see PassService)
		button.SetText("Not available")
		button.SetEnabled(false)
	elseif price == false then
		button.SetText("Not on sale")
		button.SetEnabled(false)
	else
		button.SetText(if typeof(price) == "number" then ROBUX .. " " .. price elseif price == true then "Buy" else "...")
		button.SetEnabled(true)
	end
end

local function press(key: string)
	if not State.OwnsPass(key) then
		remotes.BuyPass:FireServer(key) -- only a request: the server opens Roblox's purchase window
	elseif key == "AutoSell" then
		remotes.SetSetting:FireServer("AutoSell", not State.AutoSellOn())
	end
end

local function buildCard(parent: Instance, key: string, position: UDim2)
	local pass = GameConfig.Passes[key]
	local frame = Kit.Create("Frame", {
		Name = "Pass_" .. key,
		BackgroundColor3 = Kit.Colors.White,
		Position = position,
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		Parent = parent,
	})
	Kit.Corner(frame, 14)
	Kit.Stroke(frame, 3.5)
	local fade = FADES[key] or PLAIN_FADE
	Kit.Gradient(frame, fade[1], fade[2])

	Kit.Label({
		Parent = frame,
		Name = "Title",
		Text = pass.Name,
		TextSize = 28,
		Position = UDim2.fromOffset(120, 6),
		Size = UDim2.new(1, -128, 0, 32),
		Fit = true,
	})
	local holder = Kit.Create("Frame", {
		Name = "Picture",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(104, 104),
		Parent = frame,
	})
	Kit.PassIcon(holder, 104, key)
	Kit.Label({
		Parent = frame,
		Name = "Text",
		Text = pass.Text,
		TextSize = 25,
		Position = UDim2.fromOffset(120, 40),
		Size = UDim2.new(1, -128, 0, 72),
		Stroke = 3,
		Fit = true,
	})
	if key == "StarterPack" then
		-- a little red flag on the corner of the cheapest, best card
		local flag = Kit.Create("Frame", {
			Name = "Flag",
			BackgroundColor3 = Kit.Colors.Red,
			Position = UDim2.fromOffset(-10, -8), -- (on the corner of the picture)
			Size = UDim2.fromOffset(86, 28),
			Rotation = -12,
			ZIndex = 3,
			Parent = frame,
		})
		Kit.Corner(flag, 8)
		Kit.Stroke(flag, 3)
		Kit.Label({ Parent = flag, Name = "Text", Text = "DEAL!", TextSize = 21, Stroke = 2.5, Fit = true, ZIndex = 3 })
	end

	local button = Kit.Button({
		Parent = frame,
		Name = "Buy",
		Text = "...",
		TextSize = 26,
		Color = Kit.Colors.Green,
		Size = UDim2.new(1, -16, 0, 46),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		OnClick = function()
			press(key)
		end,
	})
	table.insert(cards, { Key = key, Frame = frame, Button = button })
end

-- BEE CHANCES ----------------------------------------------------------------------------------
-- Two lists share this page: the Queen's bees, and (while that event is on) the three bees of
-- the Halloween Egg. A button at the bottom switches between them. Luck changes both.

local QUEEN_NOTE = '"x2 luck" is what the Lucky Queen pass, or a Double Luck boost, makes of your chances. +2 Rolls gives you 2 more bees every roll, each with these same chances. The numbers are rounded, so they may not add up to exactly 100%.'
local EGG_NOTE = '"x2 luck" is what the Lucky Queen pass, or a Double Luck boost, makes of your chances at the egg. One roll costs %s jars and gives one of these three bees. The numbers are rounded, so they may not add up to exactly 100%%.'

local function refreshChances()
	local egg = GameConfig.HalloweenEgg
	local eggOn = State.EggSecondsLeft() > 0
	if not eggOn then
		showingEgg = false
	end
	queenList.Visible = not showingEgg
	eggList.Visible = showingEgg
	eggButton.Holder.Visible = eggOn
	eggButton.SetText(if showingEgg then "Queen's Bees" else egg.Name)
	-- (with no second button, Back sits in the middle)
	backButton.Holder.Position = UDim2.new(0.5, if eggOn then -112 else 0, 1, 0)

	local luck = State.RollLuck()
	local queenNow, queenDouble = GameConfig.BeeChances(luck), GameConfig.BeeChances(luck * 2)
	local eggNow, eggDouble = GameConfig.EggChances(egg, luck), GameConfig.EggChances(egg, luck * 2)
	if showingEgg then
		luckLine.Text = string.format("The chance of each bee in one %s roll. Your luck right now: x%g", egg.Name, luck)
		chanceNote.Text = string.format(EGG_NOTE, NumberFormat.Short(egg.JarCost))
	else
		luckLine.Text = string.format("The chance of each bee in one roll. Your luck right now: x%g", luck)
		chanceNote.Text = QUEEN_NOTE
	end
	for beeName, row in chanceRows do
		row.Now.Text = NumberFormat.Percent(queenNow[beeName] or eggNow[beeName] or 0)
		row.Double.Text = NumberFormat.Percent(queenDouble[beeName] or eggDouble[beeName] or 0)
		if row.Secret then
			-- a secret bee is "???" and a black shape until the player has one
			local hide = not State.OwnsBee(beeName)
			row.NameLabel.Text = if hide then "???" else GameConfig.Bees[beeName].BeeName
			local image = row.Picture:FindFirstChildWhichIsA("ImageLabel", true)
			if image then
				image.ImageColor3 = if hide then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
			end
		end
	end
end

-- One bee's line: picture, name, its chance now and its chance with double luck.
local function chanceLine(parent: Instance, beeName: string, position: UDim2, width: number)
	local bee = GameConfig.Bees[beeName]
	local line = Kit.Box(parent, position, UDim2.fromOffset(width, CHANCE_ROW - 5), nil, "Bee_" .. beeName)
	local icon = Kit.BeeIcon(line, 34, beeName)
	icon.Position = UDim2.fromOffset(8, 3)
	local name = Kit.Label({
		Parent = line,
		Name = "BeeName",
		Text = bee.BeeName,
		TextSize = 22,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(54, 0),
		Size = UDim2.new(1, -54 - 200, 1, 0),
		Fit = true,
	})
	Kit.BeeNameText(name, beeName) -- (its rarity's colour; rainbow for the very best bees)
	local nowLabel = Kit.Label({
		Parent = line,
		Name = "Now",
		Text = "",
		TextSize = 23,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -104, 0, 0),
		Size = UDim2.new(0, 92, 1, 0),
		Fit = true,
	})
	local doubleLabel = Kit.Label({
		Parent = line,
		Name = "Double",
		Text = "",
		TextSize = 23,
		Color = Kit.Colors.Lime,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.new(0, 92, 1, 0),
		Fit = true,
	})
	chanceRows[beeName] = { Now = nowLabel, Double = doubleLabel, NameLabel = name, Picture = icon, Secret = bee.Secret == true }
end

-- The two little headings over a column of lines: "Now" and "x2 luck".
local function chanceHeads(parent: Instance, left: number, width: number)
	for _, head in { { "Now", 196, Kit.Colors.White }, { "x2 luck", 98, Kit.Colors.Lime } } do
		Kit.Label({
			Parent = parent,
			Name = "Head",
			Text = head[1] :: string,
			TextSize = 22,
			Color = head[3] :: Color3,
			Position = UDim2.fromOffset(left + width - (head[2] :: number), 31),
			Size = UDim2.fromOffset(92, 28),
			Fit = true,
		})
	end
end

local function buildChances(parent: Instance, width: number, height: number)
	chancesPage = Kit.Create("Frame", {
		Name = "Chances",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = parent,
	})
	luckLine = Kit.Label({
		Parent = chancesPage,
		Name = "Luck",
		Text = "",
		TextSize = 25,
		Size = UDim2.new(1, 0, 0, 30),
		Fit = true,
	})
	local top = 60
	local columnWidth = math.floor((width - GAP) / 2)

	-- the Queen's bees, in two columns
	queenList = Kit.Create("Frame", { Name = "QueenBees", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = chancesPage })
	local order = GameConfig.QueenBees
	local perColumn = math.ceil(#order / 2)
	for column = 0, 1 do
		chanceHeads(queenList, column * (columnWidth + GAP), columnWidth)
	end
	for index, beeName in order do
		local column = (index - 1) // perColumn
		local row = (index - 1) % perColumn
		chanceLine(queenList, beeName, UDim2.fromOffset(column * (columnWidth + GAP), top + row * CHANCE_ROW), columnWidth)
	end

	-- the Halloween Egg's bees: the egg on the left, one column of lines on the right
	eggList = Kit.Create("Frame", { Name = "EggBees", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = chancesPage })
	local eggLeft = width - columnWidth - 70
	local eggIcon = Kit.HalloweenEggIcon(eggList, 170)
	eggIcon.Position = UDim2.fromOffset(math.max(0, (eggLeft - 170) // 2), top + 4)
	chanceHeads(eggList, eggLeft, columnWidth)
	for index, entry in GameConfig.HalloweenEgg.Bees do
		-- (rarest at the bottom)
		chanceLine(eggList, entry.Bee, UDim2.fromOffset(eggLeft, top + (index - 1) * CHANCE_ROW), columnWidth)
	end

	local noteTop = top + perColumn * CHANCE_ROW + 2
	chanceNote = Kit.Label({
		Parent = chancesPage,
		Name = "Note",
		Text = QUEEN_NOTE,
		TextSize = 20,
		Color = Kit.Colors.Cream,
		Position = UDim2.fromOffset(0, noteTop),
		Size = UDim2.new(1, 0, 0, height - noteTop - 54),
		Stroke = 2.5,
		Fit = true,
	})
	chanceNote.TextWrapped = true
	backButton = Kit.Button({
		Parent = chancesPage,
		Name = "Back",
		Text = "Back",
		TextSize = 26,
		Color = Kit.Colors.Blue,
		Size = UDim2.fromOffset(190, 46),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		OnClick = function()
			ShopPanel.ShowPage("Passes")
		end,
	})
	-- switches between the two lists (only there while the Halloween Egg is)
	eggButton = Kit.Button({
		Parent = chancesPage,
		Name = "EggButton",
		Text = GameConfig.HalloweenEgg.Name,
		TextSize = 24,
		Color = Kit.Colors.Orange,
		Size = UDim2.fromOffset(214, 46),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 100, 1, 0),
		OnClick = function()
			showingEgg = not showingEgg
			refreshChances()
		end,
	})
	eggButton.Holder.Visible = false
end

-- THE WINDOW -----------------------------------------------------------------------------------

local function refresh()
	if not panel or not panel.IsOpen() then
		return
	end
	if chancesPage.Visible then
		refreshChances()
	else
		for _, card in cards do
			refreshCard(card)
		end
	end
end

function ShopPanel.ShowPage(name: string)
	chancesPage.Visible = name == "Chances"
	passesPage.Visible = name ~= "Chances"
	refresh()
end

-- Asks Roblox what a pass costs (the price is set on the Roblox website).
local function fetchPrice(key: string)
	local pass = GameConfig.Passes[key]
	if not pass or pass.Id == 0 then
		return
	end
	for attempt = 1, 3 do
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(pass.Id, Enum.InfoType.GamePass)
		end)
		if ok and typeof(info) == "table" then
			local price = info.PriceInRobux
			prices[key] = if info.IsForSale ~= false and typeof(price) == "number" then price else false
			refresh()
			return
		end
		task.wait(5 * attempt)
	end
	prices[key] = true
	refresh()
end

function ShopPanel.Init(gui: ScreenGui)
	local shown = shownPasses()
	local rowsOfCards = math.max(1, math.ceil(#shown / COLUMNS))
	local gridWidth = COLUMNS * CARD_WIDTH + (COLUMNS - 1) * GAP
	local gridHeight = rowsOfCards * CARD_HEIGHT + (rowsOfCards - 1) * GAP
	local contentHeight = math.max(gridHeight + FOOTER, 410) -- (the Bee Chances list needs this much room)

	panel = Kit.Panel({
		Parent = gui,
		Name = "ShopPanel",
		Title = "Shop",
		Size = Vector2.new(gridWidth + 44, contentHeight + 102),
		HeaderColor = HEADER_COLOR,
		Icon = function(holder)
			local icon = Kit.ShopIcon(holder, 84)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
		end,
	})
	local content = panel.Content

	passesPage = Kit.Create("Frame", {
		Name = "Passes",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = content,
	})
	for index, key in shown do
		local column = (index - 1) % COLUMNS
		local row = (index - 1) // COLUMNS
		buildCard(passesPage, key, UDim2.fromOffset(column * (CARD_WIDTH + GAP), row * (CARD_HEIGHT + GAP)))
	end
	if #shown == 0 then
		Kit.Label({ Parent = passesPage, Name = "Empty", Text = "The Shop opens soon!", TextSize = 34, Size = UDim2.new(1, 0, 0, gridHeight), Fit = true })
	end

	-- under the cards: the Bee Chances button, and what a pass is
	Kit.Button({
		Parent = passesPage,
		Name = "ChancesButton",
		Text = "Bee Chances",
		TextSize = 25,
		Color = Kit.Colors.Blue,
		Size = UDim2.fromOffset(264, 48),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Layout = "Row",
		Icon = function(area)
			local clover = Kit.CloverIcon(area, 34)
			clover.AnchorPoint = Vector2.new(0.5, 0.5)
			clover.Position = UDim2.fromScale(0.5, 0.5)
		end,
		OnClick = function()
			ShopPanel.ShowPage("Chances")
		end,
	})
	Kit.Label({
		Parent = passesPage,
		Name = "Footer",
		Text = "A pass is bought once, with Robux, and is yours for ever.",
		TextSize = 22,
		Color = Kit.Colors.Cream,
		XAlign = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, -4),
		Size = UDim2.new(1, -284, 0, 42),
		Fit = true,
	})

	buildChances(content, gridWidth, contentHeight)

	panel.OnOpen = function()
		ShopPanel.ShowPage("Passes") -- always opens on the passes
	end
	State.Changed:Connect(refresh)
	-- (a Double Luck boost can run out while the Bee Chances list is open)
	task.spawn(function()
		while true do
			task.wait(1)
			if panel.IsOpen() and chancesPage.Visible then
				refreshChances()
			end
		end
	end)
	for _, key in shown do
		task.spawn(fetchPrice, key)
	end
end

function ShopPanel.Toggle()
	panel.Toggle()
end

function ShopPanel.Open()
	panel.Open()
end

return ShopPanel
