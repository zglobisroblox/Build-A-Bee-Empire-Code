--[[
	SettingsPanel - the "Settings" window. It opens from the gear button at the top of the screen.

	- Music and Sounds: drag a slider to make them louder or quieter.
	- Other players' bees: Shown or Hidden. Hiding them calms a busy screen and helps a slow
	  device: their flying bees are then not moved or drawn at all. Only your own screen changes.
	- Auto Roll stops for: tap the rarities you want (Common, Uncommon...). When the Queen
	  rolls a bee of one of them by herself she waits, so you have time to buy it. (This row
	  only shows once you have bought Auto Roll.)
	- Queen's Luck: drag the slider down to use less luck than you own, to see more of the
	  cheap bees. (The slider shows once you have bought some luck.)

	Every tap only sends a request; the server checks it and remembers the choice.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("BeeEmpire")
local GameConfig = require(sharedFolder:WaitForChild("GameConfig"))
local Upgrades = require(sharedFolder:WaitForChild("Upgrades"))
local remotes = sharedFolder:WaitForChild("Remotes")

local Kit = require(script.Parent.UIKit)
local State = require(script.Parent.State)
local Audio = require(script.Parent.Audio)

local SettingsPanel = {}

local WIDTH = 840
-- (Kept short on purpose: a window is shrunk until its whole height fits the screen, so a
-- shorter window shows bigger on a phone.)
local ROW_GAP = 10
local SLIDER_ROW = 84 -- how tall the Music and Sounds rows are
local AUTO_ROW = 154 -- the Auto Roll row
local CHIP_HEIGHT = 56 -- one rarity card in that row
local RAINBOW_CARD = { Color3.fromRGB(74, 56, 128), Color3.fromRGB(38, 28, 76) } -- the dark card behind rainbow writing
local LUCK_ROW = 104 -- the Queen's Luck row
local SLIDER_LEFT = 330 -- where a slider's bar starts, counted from the left edge of its row
local SLIDER_STEP = 5 -- a volume slider moves in steps of this many percent
local ECHO_SECONDS = 1.5 -- how long a slider keeps its own number while the server saves it

-- each row has its own bright panel: a left-to-right fade through these colours
local ROW_FADES = {
	Music = { Color3.fromRGB(255, 127, 208), Color3.fromRGB(181, 101, 255) },
	Sounds = { Color3.fromRGB(122, 214, 255), Color3.fromRGB(63, 134, 240) },
	OtherBees = { Color3.fromRGB(255, 214, 70), Color3.fromRGB(255, 146, 38) },
	AutoRoll = { Color3.fromRGB(155, 242, 124), Color3.fromRGB(34, 185, 138) },
	Luck = { Color3.fromRGB(255, 226, 60), Color3.fromRGB(255, 138, 203), Color3.fromRGB(200, 115, 255) },
}

local panel
local autoRow: Frame
local luckTitle: TextLabel
local luckHint: TextLabel
local luckSlider -- the Queen's Luck slider (see makeSlider)
local otherBeesButton -- Shown / Hidden (see Kit.Button)
local sliders: { [string]: { Show: (number) -> (), IsBusy: () -> boolean } } = {}
local chips: { [string]: { Tick: Frame, Dim: Frame } } = {}

local function centred(picture: GuiObject)
	picture.AnchorPoint = Vector2.new(0.5, 0.5)
	picture.Position = UDim2.fromScale(0.5, 0.5)
end

-- How tall everything inside the window is (the Auto Roll row is left out until it is bought).
local function contentHeight(withAutoRoll: boolean): number
	local height = SLIDER_ROW * 3 + LUCK_ROW + ROW_GAP * 3 -- Music, Sounds, Other players' bees, Queen's Luck
	if withAutoRoll then
		height += AUTO_ROW + ROW_GAP
	end
	return height
end

-- A bright row with a picture tile at its left end.
local function makeRow(name: string, order: number, height: number, tileSize: number): (Frame, Frame)
	local row = Kit.Create("Frame", {
		Name = "Row_" .. name,
		BackgroundColor3 = Kit.Colors.White,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = order,
		Parent = panel.Content,
	})
	Kit.Corner(row, 14)
	Kit.Stroke(row, 3.5)
	local fade = ROW_FADES[name]
	local points = {}
	for index, color in fade do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#fade - 1), color))
	end
	Kit.Create("UIGradient", { Color = ColorSequence.new(points), Parent = row })

	local tile = Kit.Create("Frame", {
		Name = "Icon",
		BackgroundColor3 = Kit.Colors.Outline,
		BackgroundTransparency = 0.78,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(tileSize, tileSize),
		Parent = row,
	})
	Kit.Corner(tile, 14)
	Kit.Stroke(tile, 3)
	return row, tile
end

-- A green circle with a white tick: "this one is chosen". It sits on its parent's top right corner.
local function makeTick(parent: Instance, size: number): Frame
	local badge = Kit.Create("Frame", {
		Name = "Tick",
		BackgroundColor3 = Kit.Colors.Green,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 6,
		Visible = false,
		Parent = parent,
	})
	Kit.Corner(badge, size / 2)
	Kit.Stroke(badge, 3)
	-- the tick is two white bars: a short one going down, a long one going up
	local function bar(length: number, x: number, y: number, turn: number)
		local line = Kit.Create("Frame", {
			BackgroundColor3 = Kit.Colors.White,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(length, 0.17),
			Rotation = turn,
			ZIndex = 6,
			Parent = badge,
		})
		Kit.Corner(line, size)
	end
	bar(0.3, 0.34, 0.6, 45)
	bar(0.52, 0.58, 0.48, -50)
	return badge
end

-- A slider: a dark bar that fills with green, and a round white knob to drag.
-- It moves in whole steps of options.Step, from options.Min up to options.Max() (Max is asked
-- every time, because the luck a player owns can grow). options.Format turns the number into
-- the writing at the right end of the row ("45%", "x1.3"). options.CentreY (optional) is how
-- far down the row the slider sits, in pixels; without it the slider is in the middle.
-- onPreview(value) runs while it is dragged, onRelease(value) when the finger lifts.
local function makeSlider(
	row: Frame,
	options: { Min: number, Max: () -> number, Step: number, Format: (number) -> string, CentreY: number? },
	onPreview: (number) -> (),
	onRelease: (number) -> ()
)
	local value: number? = nil
	local shownMax: number? = nil
	local dragging: InputObject? = nil
	local busyUntil = 0
	-- how far down the row: the middle, or the line asked for
	local down = if options.CentreY then UDim.new(0, options.CentreY) else UDim.new(0.5, 0)

	local valueLabel = Kit.Label({
		Parent = row,
		Name = "Value",
		Text = "",
		TextSize = 30,
		XAlign = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, down.Scale, down.Offset),
		Size = UDim2.fromOffset(84, 40),
		Stroke = 4,
		Fit = true,
	})
	local track = Kit.Create("Frame", {
		Name = "Track",
		BackgroundColor3 = Kit.Colors.Outline,
		BackgroundTransparency = 0.45,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SLIDER_LEFT, down.Scale, down.Offset),
		Size = UDim2.new(1, -SLIDER_LEFT - 124, 0, 28),
		Parent = row,
	})
	Kit.Corner(track, 14)
	Kit.Stroke(track, 3)
	local fill = Kit.Create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Kit.Colors.White,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	})
	Kit.Corner(fill, 14)
	Kit.Bands(fill, Kit.Colors.Green)
	local knob = Kit.Create("Frame", {
		Name = "Knob",
		BackgroundColor3 = Kit.Colors.White,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(46, 46),
		ZIndex = 2,
		Parent = track,
	})
	Kit.Corner(knob, 23)
	Kit.Stroke(knob, 3.5)
	Kit.Gradient(knob, Kit.Colors.White, Color3.fromRGB(214, 219, 236))
	-- a see-through button over the whole slider catches the press (it is taller than the
	-- bar, so it is easy to hit with a thumb)
	local hit = Kit.Create("TextButton", {
		Name = "Hit",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 50, 0, 68),
		ZIndex = 3,
		Parent = track,
	})

	local function show(newValue: number)
		local top = options.Max()
		if newValue == value and top == shownMax then
			return
		end
		value = newValue
		shownMax = top
		local along = if top > options.Min then math.clamp((newValue - options.Min) / (top - options.Min), 0, 1) else 0
		fill.Size = UDim2.fromScale(along, 1)
		knob.Position = UDim2.fromScale(along, 0.5)
		valueLabel.Text = options.Format(newValue)
	end

	-- where along the bar a press is, as a number in whole steps
	local function dragTo(x: number)
		local top = options.Max()
		local along = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local steps = math.floor(along * (top - options.Min) / options.Step + 0.5)
		local newValue = math.clamp(options.Min + steps * options.Step, options.Min, top)
		if newValue ~= value then
			show(newValue)
			onPreview(newValue)
		end
	end

	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end

	hit.InputBegan:Connect(function(input)
		if isPress(input) and not dragging then
			dragging = input
			dragTo(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local held = dragging
		if not held then
			return
		end
		local mouseMoved = held.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
		if input == held or mouseMoved then
			dragTo(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local held = dragging
		if not held then
			return
		end
		local mouseUp = held.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1
		if input == held or mouseUp then
			dragging = nil
			busyUntil = os.clock() + ECHO_SECONDS
			if value then
				onRelease(value)
			end
		end
	end)

	return {
		Show = show,
		-- true while a finger is on it, or just after (the server is still saving the number)
		IsBusy = function(): boolean
			return dragging ~= nil or os.clock() < busyUntil
		end,
		-- hides the bar and its number (the Queen's Luck slider, before any luck is bought)
		SetVisible = function(visible: boolean)
			track.Visible = visible
			valueLabel.Visible = visible
		end,
	}
end

local function refresh()
	if not panel or not panel.IsOpen() then
		return
	end

	-- the sliders follow the saved numbers, unless a finger is on one
	if not sliders.Music.IsBusy() then
		sliders.Music.Show(State.MusicVolume())
	end
	if not sliders.Sounds.IsBusy() then
		sliders.Sounds.Show(State.SoundVolume())
	end

	-- other players' bees: shown (green) or hidden (grey)
	local showing = State.ShowOtherBees()
	otherBeesButton.SetText(if showing then "Shown" else "Hidden")
	otherBeesButton.SetColor(if showing then Kit.Colors.Green else Kit.Colors.Grey)

	-- the rarities Auto Roll stops for: ticked and bright, or dimmed
	local autoRollBought = State.AutoRollBought()
	autoRow.Visible = autoRollBought
	for rarityName, chip in chips do
		local chosen = State.StopsFor(rarityName)
		chip.Tick.Visible = chosen
		chip.Dim.Visible = not chosen
	end

	-- Queen's Luck: the slider goes from x1 up to all the luck the player owns. Before any
	-- luck is bought there is nothing to slide, so the row just says where to get some.
	local hasLuck = State.UpgradeLevel("Luck") > 1
	luckSlider.SetVisible(hasLuck)
	if not luckSlider.IsBusy() then
		luckSlider.Show(State.LuckLevelInUse())
	end
	local titleWidth = if hasLuck then UDim.new(0, SLIDER_LEFT - 106 - 14) else UDim.new(1, -106 - 14)
	luckTitle.Size = UDim2.new(titleWidth.Scale, titleWidth.Offset, 0, 40)
	luckHint.Text = if hasLuck then "Slide it down to roll with less luck: more cheap bees!" else "Buy luck at your Upgrade Shop!"

	-- the window is shorter while the Auto Roll row is not there
	panel.Root.Size = UDim2.fromOffset(WIDTH, contentHeight(autoRollBought) + 102)
end

-- A Music or Sounds row: picture, name, slider, percent.
local function buildVolumeRow(name: string, title: string, order: number, drawPicture: (Instance, number) -> Frame)
	local row, tile = makeRow(name, order, SLIDER_ROW, 60)
	centred(drawPicture(tile, 50))
	Kit.Label({
		Parent = row,
		Name = "Title",
		Text = title,
		TextSize = 32,
		XAlign = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 88, 0.5, 0),
		Size = UDim2.fromOffset(220, 42), -- (no taller than the writing: "Fit" text grows to fill its box)
		Stroke = 4,
		Fit = true,
	})
	local releases = 0
	local volume = {
		Min = 0,
		Max = function()
			return 100
		end,
		Step = SLIDER_STEP,
		Format = function(percent: number)
			return percent .. "%"
		end,
	}
	sliders[name] = makeSlider(row, volume, function(percent)
		Audio.Preview(name, percent) -- hear it straight away
	end, function(percent)
		remotes.SetSetting:FireServer(name, percent) -- only a request: the server saves it
		if name == "Sounds" then
			Kit.PlaySound("Pop") -- so the player hears how loud that is
		end
		-- once the server has had time to save it, go back to following the saved number
		releases += 1
		local thisRelease = releases
		task.delay(ECHO_SECONDS, function()
			if releases == thisRelease and not sliders[name].IsBusy() then
				Audio.Preview(name, nil)
				refresh()
			end
		end)
	end)
end

-- One rarity card in the Auto Roll row ("Common", "Rare"...). Tap it to tick or untick
-- that rarity: Auto Roll waits for every bee of a ticked rarity.
local function buildChip(parent: Instance, rarityName: string, order: number, width: number)
	local rarity = GameConfig.Rarities[rarityName]
	local top, bottom = Kit.RarityFade(rarityName)
	if rarity.Rainbow then
		top, bottom = RAINBOW_CARD[1], RAINBOW_CARD[2] -- rainbow writing needs a dark card to show up
	end
	local chip = Kit.Create("TextButton", {
		Name = "Rarity_" .. rarityName,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Kit.Colors.White,
		Size = UDim2.fromOffset(width, CHIP_HEIGHT),
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.Corner(chip, 12)
	Kit.Stroke(chip, 3)
	Kit.Gradient(chip, top, bottom)
	local pressScale = Kit.Create("UIScale", { Parent = chip })
	local nameLabel = Kit.Label({
		Parent = chip,
		Name = "RarityName",
		Text = rarity.DisplayName,
		TextSize = 25,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -12, 0, 34),
		Stroke = 3.5,
		Fit = true,
	})
	if rarity.Rainbow then
		Kit.SetRainbow(nameLabel, true)
	end
	-- a dark sheet over the card while this rarity is NOT ticked
	local dim = Kit.Create("Frame", {
		Name = "Dim",
		BackgroundColor3 = Kit.Colors.Outline,
		BackgroundTransparency = 0.5,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = chip,
	})
	Kit.Corner(dim, 12)
	chips[rarityName] = { Tick = makeTick(chip, 32), Dim = dim }

	chip.Activated:Connect(function()
		Kit.PlaySound("Click")
		pressScale.Scale = 0.9
		TweenService:Create(pressScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		-- only a request: the server remembers the choice
		remotes.SetSetting:FireServer("StopFor", rarityName, not State.StopsFor(rarityName))
	end)
end

function SettingsPanel.Init(gui: ScreenGui)
	panel = Kit.Panel({
		Parent = gui,
		Name = "SettingsPanel",
		Title = "Settings",
		Size = Vector2.new(WIDTH, contentHeight(true) + 102),
		HeaderColor = Kit.Colors.Purple,
		Icon = function(holder)
			centred(Kit.GearIcon(holder, 84))
		end,
	})
	Kit.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, ROW_GAP),
		Parent = panel.Content,
	})

	buildVolumeRow("Music", "Music", 1, Kit.MusicIcon)
	buildVolumeRow("Sounds", "Sounds", 2, Kit.SpeakerIcon)

	-- OTHER PLAYERS' BEES: shown or hidden, on this screen only
	local beesRow, beesTile = makeRow("OtherBees", 3, SLIDER_ROW, 60)
	centred(Kit.BeeIcon(beesTile, 54))
	Kit.Label({
		Parent = beesRow,
		Name = "Title",
		Text = "Other players' bees",
		TextSize = 30,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(88, 8),
		Size = UDim2.new(1, -88 - 200, 0, 38),
		Stroke = 4,
		Fit = true,
	})
	Kit.Label({
		Parent = beesRow,
		Name = "Hint",
		Text = "Hide them if the screen is too busy or the game is slow.",
		TextSize = 20,
		Color = Kit.Colors.Cream,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(88, 46),
		Size = UDim2.new(1, -88 - 200, 0, 28),
		Stroke = 3,
		Fit = true,
	})
	otherBeesButton = Kit.Button({
		Parent = beesRow,
		Name = "Toggle",
		Text = "Shown",
		TextSize = 26,
		Color = Kit.Colors.Green,
		Size = UDim2.fromOffset(170, 56),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		OnClick = function()
			-- only a request: the server remembers the choice
			remotes.SetSetting:FireServer("OtherBees", not State.ShowOtherBees())
		end,
	})

	-- AUTO ROLL: which bees it stops for
	local autoTile
	autoRow, autoTile = makeRow("AutoRoll", 4, AUTO_ROW, 64)
	centred(Kit.EggIcon(autoTile, 54))
	Kit.Label({
		Parent = autoRow,
		Name = "Title",
		Text = "Auto Roll stops for",
		TextSize = 32,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(90, 6),
		Size = UDim2.new(1, -104, 0, 40),
		Stroke = 4,
		Fit = true,
	})
	Kit.Label({
		Parent = autoRow,
		Name = "Hint",
		Text = "Tap the rarities you want. The Queen waits when she rolls one!",
		TextSize = 22,
		Color = Kit.Colors.Cream,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(90, 46),
		Size = UDim2.new(1, -104, 0, 30),
		Stroke = 3,
		Fit = true,
	})
	local chipHolder = Kit.Create("Frame", {
		Name = "Bees",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 86),
		Size = UDim2.new(1, -28, 0, CHIP_HEIGHT),
		Parent = autoRow,
	})
	Kit.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = chipHolder,
	})
	local kinds = #GameConfig.RarityOrder
	local chipWidth = math.floor((WIDTH - 44 - 28 - 8 * (kinds - 1)) / kinds)
	for order, rarityName in GameConfig.RarityOrder do
		buildChip(chipHolder, rarityName, order, chipWidth)
	end

	-- QUEEN'S LUCK: how much of it to use
	local luckRow, luckTile = makeRow("Luck", 5, LUCK_ROW, 80)
	centred(Kit.CloverIcon(luckTile, 66))
	luckTitle = Kit.Label({
		Parent = luckRow,
		Name = "Title",
		Text = Upgrades.DisplayName("Luck"),
		TextSize = 32,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(106, 10),
		Size = UDim2.new(0, SLIDER_LEFT - 106 - 14, 0, 40), -- (refresh widens it while there is no slider)
		Stroke = 4,
		Fit = true,
	})
	luckHint = Kit.Label({
		Parent = luckRow,
		Name = "Hint",
		Text = "",
		TextSize = 22,
		Color = Kit.Colors.Cream,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(106, 60),
		Size = UDim2.new(1, -106 - 14, 0, 30), -- (the whole width, under the slider)
		Stroke = 3,
		Fit = true,
	})
	-- the slider counts in luck LEVELS (1 = x1, 2 = x1.1 ...) and shows the multiplier
	local luckReleases = 0
	local luckLevels = {
		Min = 1,
		Max = function()
			return State.UpgradeLevel("Luck")
		end,
		Step = 1,
		Format = function(level: number)
			return string.format("x%g", Upgrades.ValueAt("Luck", level))
		end,
		CentreY = 30, -- on the title's line, so the hint can have the whole width below
	}
	luckSlider = makeSlider(luckRow, luckLevels, function() end, function(level)
		-- only a request: the server checks the player owns this much luck
		remotes.SetSetting:FireServer("Luck", level)
		Kit.PlaySound("Pop")
		-- once the server has had time to save it, go back to following the saved number
		luckReleases += 1
		local thisRelease = luckReleases
		task.delay(ECHO_SECONDS, function()
			if luckReleases == thisRelease and not luckSlider.IsBusy() then
				refresh()
			end
		end)
	end)

	panel.OnOpen = refresh
	State.Changed:Connect(refresh)
end

function SettingsPanel.Open()
	panel.Open()
end

function SettingsPanel.Toggle()
	panel.Toggle()
end

return SettingsPanel
