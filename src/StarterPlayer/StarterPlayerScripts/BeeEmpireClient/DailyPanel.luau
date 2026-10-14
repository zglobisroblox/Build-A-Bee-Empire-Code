--[[
	DailyPanel - the "Daily Rewards" window. It opens from the calendar button at the top of
	the screen, and by itself once per visit when a reward is ready.

	The rewards are listed in GameConfig.DailyRewards: one card per day, and the last day is
	the tall card on the right. A collected card is shaded with a tick. The next card has a
	green Claim button when its reward is ready, or else shows how long there is to wait.

	The server decides everything (DailyService). The Claim button only sends a request.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("BeeEmpire")
local GameConfig = require(sharedFolder:WaitForChild("GameConfig"))
local NumberFormat = require(sharedFolder:WaitForChild("NumberFormat"))
local remotes = sharedFolder:WaitForChild("Remotes")

local Kit = require(script.Parent.UIKit)
local State = require(script.Parent.State)

local DailyPanel = {}

local CARD_WIDTH = 178
local CARD_HEIGHT = 186
local BIG_WIDTH = 236 -- the last day's card
local GAP = 12
local COLUMNS = 3 -- small cards in a row
local FOOTER = 40 -- the line of writing under the cards
local HEADER_COLOR = Color3.fromRGB(96, 214, 60) -- lime
local OPEN_AFTER = 1.2 -- seconds before the window pops up by itself

-- the light and dark colour of a card, by what its reward is (a bee's card has its rarity's colours)
local COIN_FADE = { Color3.fromRGB(255, 234, 138), Color3.fromRGB(255, 178, 44) }
local BOOST_FADES = {
	Honey = { Color3.fromRGB(255, 212, 158), Color3.fromRGB(246, 130, 46) },
	Luck = { Color3.fromRGB(182, 246, 164), Color3.fromRGB(58, 190, 98) },
}
local PILL_COLOR = Color3.fromRGB(44, 40, 58)
local CLAIMED_COLOR = Color3.fromRGB(110, 255, 90)

type Card = { Frame: Frame, Shade: Frame, Pill: Frame, PillText: TextLabel, Claim: any, Tap: TextButton, Edge: UIStroke }

local panel
local cards: { [number]: Card } = {}
local footerText: TextLabel
local offered = false -- the window opens by itself only once per visit

-- What a reward is called and the short line that goes with it: "Guard Bee", "x1".
function DailyPanel.Describe(reward): (string, string)
	if reward.Bee then
		local bee = GameConfig.Bees[reward.Bee]
		return if bee then bee.BeeName else "Bee", "x1"
	elseif reward.Boost then
		local boost = GameConfig.Boosts[reward.Boost]
		return if boost then boost.Name else "Boost", (reward.Minutes or 0) .. " min"
	end
	return "Coins", NumberFormat.Short(reward.Coins or 0)
end

-- "19 h 05 min", "12 min", "40 s"
local function waitWords(seconds: number): string
	local whole = math.ceil(seconds)
	if whole >= 3600 then
		return string.format("%d h %02d min", whole // 3600, (whole % 3600) // 60)
	elseif whole >= 60 then
		return math.ceil(whole / 60) .. " min"
	end
	return whole .. " s"
end

-- A chunky green tick made of two bars (for a collected card).
local function tick(parent: Instance, size: number)
	local holder = Kit.Create("Frame", {
		Name = "Tick",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	local function bar(name: string, x: number, y: number, long: number, turn: number)
		local piece = Kit.Create("Frame", {
			Name = name,
			BackgroundColor3 = CLAIMED_COLOR,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(0.2, long),
			Rotation = turn,
			Parent = holder,
		})
		Kit.Corner(piece, math.floor(size * 0.08))
		Kit.Stroke(piece, 3)
	end
	bar("Long", 0.6, 0.48, 0.86, 38)
	bar("Short", 0.27, 0.66, 0.46, -45)
	-- (a second, outline-free pass hides the outline where the two bars cross)
	local function cover(name: string, x: number, y: number, long: number, turn: number)
		local piece = Kit.Create("Frame", {
			Name = name,
			BackgroundColor3 = CLAIMED_COLOR,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(0.2, long),
			Rotation = turn,
			ZIndex = 2,
			Parent = holder,
		})
		Kit.Corner(piece, math.floor(size * 0.08))
	end
	cover("LongFill", 0.6, 0.48, 0.86, 38)
	cover("ShortFill", 0.27, 0.66, 0.46, -45)
end

local function buildCard(parent: Instance, day: number, reward, position: UDim2, size: UDim2, big: boolean)
	local frame = Kit.Create("Frame", {
		Name = "Day" .. day,
		BackgroundColor3 = Kit.Colors.White,
		Position = position,
		Size = size,
		Parent = parent,
	})
	Kit.Corner(frame, 14)
	local edge = Kit.Stroke(frame, if big then 5 else 3.5)
	local fade = COIN_FADE
	if reward.Bee then
		fade = { Kit.RarityFade(reward.Bee) }
	elseif reward.Boost then
		fade = BOOST_FADES[reward.Boost] or COIN_FADE
	end
	Kit.Gradient(frame, fade[1], fade[2])

	local title, amount = DailyPanel.Describe(reward)
	local titleLabel = Kit.Label({
		Parent = frame,
		Name = "Title",
		Text = title,
		TextSize = if big then 32 else 23,
		Position = UDim2.fromOffset(6, if big then 10 else 6),
		Size = UDim2.new(1, -12, 0, if big then 40 else 28),
		Fit = true,
	})
	local pictureTop = if big then 54 else 36
	if reward.Bee then
		Kit.BeeNameText(titleLabel, reward.Bee) -- (rainbow for the very best bees)
		if big then
			local rarityLabel = Kit.Label({
				Parent = frame,
				Name = "Rarity",
				Text = GameConfig.Bees[reward.Bee].DisplayName,
				TextSize = 25,
				Position = UDim2.fromOffset(6, 50),
				Size = UDim2.new(1, -12, 0, 30),
				Fit = true,
			})
			Kit.RarityText(rarityLabel, reward.Bee, 0.25)
			pictureTop = 86
		end
	end

	local pictureSize = if big then 190 else 84
	local holder = Kit.Create("Frame", {
		Name = "Picture",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, pictureTop),
		Size = UDim2.fromOffset(pictureSize, pictureSize),
		Parent = frame,
	})
	if reward.Bee then
		Kit.BeeIcon(holder, pictureSize, reward.Bee)
	elseif reward.Boost then
		Kit.BoostIcon(holder, pictureSize, reward.Boost)
	else
		Kit.CoinIcon(holder, pictureSize)
	end

	local pillHeight = if big then 44 else 34
	-- how many (or for how long), on the lower right of the picture
	Kit.Label({
		Parent = frame,
		Name = "Amount",
		Text = amount,
		TextSize = if big then 44 else 26,
		XAlign = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -(pillHeight + 12)),
		Size = UDim2.new(1, -24, 0, if big then 50 else 30),
		Stroke = if big then 5 else 3.5,
		Fit = true,
		ZIndex = 2,
	})

	-- a collected card: shaded, with a big tick
	local shade = Kit.Create("Frame", {
		Name = "Shade",
		BackgroundColor3 = Kit.Colors.Outline,
		BackgroundTransparency = 0.4,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Visible = false,
		Parent = frame,
	})
	Kit.Corner(shade, 14)
	tick(shade, if big then 150 else 86)

	-- the bar along the bottom: "Day 3", the wait, or "Claimed"
	local pill = Kit.Create("Frame", {
		Name = "Pill",
		BackgroundColor3 = PILL_COLOR,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -20, 0, pillHeight),
		ZIndex = 4,
		Parent = frame,
	})
	Kit.Corner(pill, 10)
	Kit.Stroke(pill, 3)
	local pillText = Kit.Label({
		Parent = pill,
		Name = "Text",
		Text = "Day " .. day,
		TextSize = if big then 30 else 22,
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		Fit = true,
		ZIndex = 4,
	})
	-- the same spot, as a green button, when this card's reward is ready
	local claim = Kit.Button({
		Parent = frame,
		Name = "Claim",
		Text = "Claim",
		TextSize = if big then 32 else 24,
		Color = Kit.Colors.Green,
		Size = UDim2.new(1, -20, 0, pillHeight + 6),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		ZIndex = 5,
		OnClick = function()
			remotes.ClaimDaily:FireServer() -- only a request: the server knows which reward is next
		end,
	})
	claim.Holder.Visible = false
	-- On a small phone the Claim button is too small for a finger, so while a card's reward is
	-- ready the WHOLE card can be tapped (an unseen button lying over it).
	local tap = Kit.Create("TextButton", {
		Name = "Tap",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Visible = false,
		Parent = frame,
	})
	local lastTap = 0
	tap.Activated:Connect(function()
		if os.clock() - lastTap < 0.5 then
			return -- ignore double taps
		end
		lastTap = os.clock()
		Kit.PlaySound("Click")
		remotes.ClaimDaily:FireServer()
	end)

	cards[day] = { Frame = frame, Shade = shade, Pill = pill, PillText = pillText, Claim = claim, Tap = tap, Edge = edge }
end

local function refresh()
	local claimed = State.DailyClaimed()
	local ready = State.DailyReady()
	local left = State.DailySecondsLeft()
	for day, card in cards do
		local isClaimed = day <= claimed
		local isNext = day == claimed + 1
		card.Shade.Visible = isClaimed
		card.Claim.Holder.Visible = isNext and ready
		card.Tap.Visible = isNext and ready
		card.Pill.Visible = not (isNext and ready)
		card.Edge.Color = if isNext then Kit.Colors.Select else Kit.Colors.Outline
		if isClaimed then
			card.PillText.Text = "Claimed"
			card.PillText.TextColor3 = CLAIMED_COLOR
		elseif isNext then
			card.PillText.Text = waitWords(left)
			card.PillText.TextColor3 = Kit.Colors.Select
		else
			card.PillText.Text = "Day " .. day
			card.PillText.TextColor3 = Kit.Colors.White
		end
	end
	if ready then
		footerText.Text = "Your reward is ready!"
		footerText.TextColor3 = Kit.Colors.Lime
	else
		footerText.Text = "Next reward in " .. waitWords(left)
		footerText.TextColor3 = Kit.Colors.Cream
	end
end

-- Pops the window up by itself, once per visit, when a reward is ready. It waits for the
-- tutorial to be over, for the "Welcome Back!" window, and for any other open window.
local function maybeOffer()
	if offered or State.LoadingScreenUp() or not State.TutorialDone() or not State.DailyReady() then
		return
	end
	if Kit.IsAnyPanelOpen() or State.Number("OfflineJars") > 0 then
		return
	end
	offered = true
	task.delay(OPEN_AFTER, function()
		if State.DailyReady() and not Kit.IsAnyPanelOpen() then
			panel.Open()
		else
			offered = false -- something else came up: try again later
		end
	end)
end

function DailyPanel.Init(gui: ScreenGui)
	local rewards = GameConfig.DailyRewards
	local small = #rewards - 1 -- every day but the last gets a small card
	local rowsOfCards = math.max(1, math.ceil(small / COLUMNS))
	local gridWidth = COLUMNS * CARD_WIDTH + (COLUMNS - 1) * GAP
	local gridHeight = rowsOfCards * CARD_HEIGHT + (rowsOfCards - 1) * GAP

	panel = Kit.Panel({
		Parent = gui,
		Name = "DailyPanel",
		Title = "Daily Rewards",
		Size = Vector2.new(gridWidth + GAP + BIG_WIDTH + 44, gridHeight + FOOTER + 102),
		HeaderColor = HEADER_COLOR,
		Icon = function(holder)
			local icon = Kit.CalendarIcon(holder, 84)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
		end,
	})
	local content = panel.Content

	for day = 1, small do
		local column = (day - 1) % COLUMNS
		local row = (day - 1) // COLUMNS
		buildCard(content, day, rewards[day], UDim2.fromOffset(column * (CARD_WIDTH + GAP), row * (CARD_HEIGHT + GAP)), UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT), false)
	end
	buildCard(content, #rewards, rewards[#rewards], UDim2.fromOffset(gridWidth + GAP, 0), UDim2.fromOffset(BIG_WIDTH, gridHeight), true)

	footerText = Kit.Label({
		Parent = content,
		Name = "Footer",
		Text = "",
		TextSize = 26,
		Position = UDim2.fromOffset(0, gridHeight + 8),
		Size = UDim2.new(1, 0, 0, FOOTER - 8),
		Fit = true,
	})

	panel.OnOpen = refresh
	State.Changed:Connect(function()
		if panel.IsOpen() then
			refresh()
		end
		maybeOffer()
	end)
	Kit.PanelChanged:Connect(maybeOffer)
	-- the wait counts down, and a reward can become ready, without the server saying anything
	task.spawn(function()
		while true do
			task.wait(1)
			if panel.IsOpen() then
				refresh()
			end
			maybeOffer()
		end
	end)
	refresh()
end

function DailyPanel.Toggle()
	panel.Toggle()
end

function DailyPanel.Open()
	panel.Open()
end

return DailyPanel
