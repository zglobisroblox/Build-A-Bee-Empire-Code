--[[
	Effects - the fun bits on screen:
	- pop-up messages: a line of outlined text near the top of the screen
	- coins and jars that fly from the market / station into your counters
	- the "NEW BEE!" card when you buy a bee (the rarest bees get a big gold reveal)
	- the big show when a bee of the best rarity hatches on your stand: flash, confetti, fanfare
	Nothing here changes game data; it is only for show.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("BeeEmpire")
local GameConfig = require(sharedFolder:WaitForChild("GameConfig"))
local NumberFormat = require(sharedFolder:WaitForChild("NumberFormat"))
local Upgrades = require(sharedFolder:WaitForChild("Upgrades"))
local Kit = require(script.Parent.UIKit)
local State = require(script.Parent.State)
local UIImages = require(sharedFolder:WaitForChild("UIImages"))

local Effects = {}

-- the colour of a pop-up message's pill, by kind
local TOAST_COLORS = {
	info = Kit.Colors.Blue,
	good = Kit.Colors.Green,
	bad = Kit.Colors.Red,
	coins = Kit.Colors.Yellow,
}
local RAINBOW_PILL = Color3.fromRGB(58, 44, 104) -- the dark pill behind a rainbow message
local MAX_TOASTS = 3
local TOAST_SECONDS = 2.4

local gui: ScreenGui
local toastHolder: Frame
local targets: { [string]: GuiObject } = {}
local onArrive: { [string]: () -> () } = {}

function Effects.Init(screenGui: ScreenGui)
	gui = screenGui
	toastHolder = Kit.Create("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(760, 170),
		Parent = gui,
	})
	Kit.AutoScale(toastHolder)
	Kit.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 2),
		Parent = toastHolder,
	})

	-- Messages sit just under the hint. While a window is open the hint is hidden,
	-- so they move up into its place.
	local function place(windowOpen: boolean)
		local top = if windowOpen then 2 else 8 + 38 * Kit.ScreenScale()
		toastHolder.Position = UDim2.new(0.5, 0, 0, top)
	end
	Kit.PanelChanged:Connect(place)
	place(false)
end

-- Where flying icons should land, and what to do when they get there.
function Effects.SetTarget(kind: string, target: GuiObject, arrive: () -> ())
	targets[kind] = target
	onArrive[kind] = arrive
end

-- POP-UP MESSAGES ---------------------------------------------------------------------

local toastCount = 0
local activeToasts: { Frame } = {}

local function removeToast(toast: Frame)
	local index = table.find(activeToasts, toast)
	if index then
		table.remove(activeToasts, index)
	end
	toast:Destroy()
end

-- A short message in a coloured pill: green = good news, red = something is missing,
-- blue = a tip, yellow = coins. (color, if given, replaces the pill's colour. rainbow = true
-- writes the message in rainbow colours on a dark pill: news about the best bees.)
function Effects.Toast(text: string, kind: string?, color: Color3?, rainbow: boolean?)
	toastCount += 1
	local line = Kit.Create("Frame", {
		Name = "Toast",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 50),
		LayoutOrder = toastCount,
		Parent = toastHolder,
	})
	-- the pill is just wide enough for its message
	local pill = Kit.Create("Frame", {
		Name = "Pill",
		BackgroundColor3 = Kit.Colors.White,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = line,
	})
	Kit.Corner(pill, 22)
	local pillStroke = Kit.Stroke(pill, 3)
	Kit.Bands(pill, if rainbow then RAINBOW_PILL else (color or TOAST_COLORS[kind or "info"] or TOAST_COLORS.info))
	Kit.Create("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22), Parent = pill })
	local label = Kit.Label({
		Parent = pill,
		Text = text,
		TextSize = 20,
		Size = UDim2.new(0, 0, 1, -2),
	})
	label.AutomaticSize = Enum.AutomaticSize.X
	if rainbow then
		Kit.SetRainbow(label, true)
	end
	local textStroke = label:FindFirstChildOfClass("UIStroke")
	local scale = Kit.Create("UIScale", { Scale = 0.4, Parent = pill })

	table.insert(activeToasts, line)
	while #activeToasts > MAX_TOASTS do
		removeToast(activeToasts[1])
	end

	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(TOAST_SECONDS, function()
		if line.Parent == nil then
			return
		end
		local fade = TweenInfo.new(0.35)
		TweenService:Create(pill, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(pillStroke, fade, { Transparency = 1 }):Play()
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		if textStroke then
			TweenService:Create(textStroke, fade, { Transparency = 1 }):Play()
		end
		task.wait(0.4)
		removeToast(line)
	end)
end

-- FLYING COINS AND JARS -----------------------------------------------------------------

-- A big "+123" that pops up where the coins start and floats away.
local function floatingNumber(text: string, color: Color3, at: Vector2)
	local holder = Kit.Create("Frame", {
		Name = "FloatingNumber",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(400, 70),
		ZIndex = 10,
		Parent = gui,
	})
	Kit.AutoScale(holder)
	local label = Kit.Label({ Parent = holder, Text = text, TextSize = 60, Color = color, Stroke = 5, ZIndex = 10 })
	local stroke = label:FindFirstChildOfClass("UIStroke")
	local pop = Kit.Create("UIScale", { Scale = 0.3, Parent = label })

	TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.6, function()
		local rise = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(holder, rise, { Position = UDim2.fromOffset(at.X, at.Y - 90) }):Play()
		TweenService:Create(label, rise, { TextTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, rise, { Transparency = 1 }):Play()
		end
		task.wait(0.65)
		holder:Destroy()
	end)
end

-- Where a 3D point is on the screen (or the middle of the screen if it is not visible).
local function screenPointOf(worldPosition: Vector3?): Vector2
	local center = gui.AbsoluteSize / 2
	local camera = workspace.CurrentCamera
	if worldPosition and camera then
		local point, onScreen = camera:WorldToScreenPoint(worldPosition)
		if onScreen then
			return Vector2.new(point.X, point.Y)
		end
	end
	return center
end

-- kind is "coin" or "jar". Little icons arc from the world spot into the counter on the left.
function Effects.Fly(kind: string, amount: number, fromWorld: Vector3?)
	local target = targets[kind]
	local start = screenPointOf(fromWorld)
	local color = if kind == "coin" then Kit.Colors.Money else Color3.fromRGB(255, 255, 255)
	floatingNumber("+" .. NumberFormat.Short(amount), color, start - Vector2.new(0, 70 * Kit.ScreenScale()))
	Kit.PlaySound(if kind == "coin" then "Sell" else "Jar")
	if not target then
		return
	end

	local scale = Kit.ScreenScale()
	local iconSize = math.floor(38 * scale)
	local count = math.clamp(math.ceil(amount / 10), 4, 10)
	local random = Random.new()
	local landed = 0 -- how many have landed so far (they do not land in the order they set off)

	for index = 1, count do
		task.delay((index - 1) * 0.05, function()
			local icon = if kind == "coin" then Kit.CoinIcon(gui, iconSize) else Kit.JarIcon(gui, iconSize)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.ZIndex = 9
			local from = start + Vector2.new(random:NextNumber(-60, 60), random:NextNumber(-30, 30)) * scale
			local finish = target.AbsolutePosition + target.AbsoluteSize / 2
			-- a curved path: up first, then down into the counter
			local bend = (from + finish) / 2 + Vector2.new(random:NextNumber(-60, 60), -160) * scale
			icon.Position = UDim2.fromOffset(from.X, from.Y)

			local progress = Instance.new("NumberValue")
			progress.Changed:Connect(function(t)
				local point = (1 - t) ^ 2 * from + 2 * (1 - t) * t * bend + t ^ 2 * finish
				icon.Position = UDim2.fromOffset(point.X, point.Y)
				local size = iconSize * (1 - 0.4 * t)
				icon.Size = UDim2.fromOffset(size, size)
			end)
			local tween = TweenService:Create(progress, TweenInfo.new(0.6 + random:NextNumber(0, 0.15), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 1 })
			tween:Play()
			tween.Completed:Once(function()
				icon:Destroy()
				progress:Destroy()
				landed += 1
				if landed % 2 == 0 then
					-- each one lands a note higher: a little run up the scale
					Kit.PlaySound(if kind == "coin" then "Coin" else "JarLand", Kit.ScaleNote(landed // 2))
				end
				local arrive = onArrive[kind]
				if arrive then
					arrive()
				end
			end)
		end)
	end
end

-- BIG REVEALS ("NEW BEE!" and "HIVE UPGRADED!") ---------------------------------------------
-- What shows when you get a new bee or a bigger hive:
-- - most bees: a small bright card slides up at the bottom (it never stops you rolling)
-- - Legendary and secret bees: the spotlight. The world dims and blurs, and the bee turns slowly
--   in the middle on spinning rays and a glow in its rarity's colour, with twinkles and confetti,
--   its rarity in big letters, its name, and how rare it is ("1 in 333", with your luck counted)
-- - a bigger hive: the old hive shakes and pops into the new one, and the bees it holds count up
-- The rays, glow and twinkles are white pictures (UIImages.Fx) tinted here.

local currentReveal = nil

local REVEAL_BLUR = 14 -- how much the world blurs behind a reveal
local TAP_GUARD = 0.6 -- seconds before a tap may close a reveal (so the tap that bought it cannot)

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 80, 90),
	Color3.fromRGB(255, 190, 40),
	Color3.fromRGB(110, 230, 90),
	Color3.fromRGB(70, 190, 255),
	Color3.fromRGB(190, 110, 255),
	Color3.fromRGB(255, 120, 210),
}

-- Paper pieces that rain down the whole screen. zIndex (optional) puts them over a reveal.
local function confetti(count: number, zIndex: number?)
	local random = Random.new()
	local screen = gui.AbsoluteSize
	for _ = 1, count do
		local size = random:NextInteger(8, 16)
		local piece = Kit.Create("Frame", {
			Name = "Confetti",
			BackgroundColor3 = CONFETTI_COLORS[random:NextInteger(1, #CONFETTI_COLORS)],
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(random:NextNumber(0, screen.X), random:NextNumber(-140, -20)),
			Size = UDim2.fromOffset(size, size * random:NextNumber(0.5, 1.5)),
			Rotation = random:NextNumber(0, 360),
			ZIndex = zIndex or 13,
			Parent = gui,
		})
		local seconds = random:NextNumber(1.6, 2.9)
		local fall = TweenService:Create(piece, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, random:NextNumber(0, 0.5)), {
			Position = UDim2.fromOffset(piece.Position.X.Offset + random:NextNumber(-120, 120), screen.Y + 60),
			Rotation = piece.Rotation + random:NextNumber(-540, 540),
		})
		fall:Play()
		fall.Completed:Once(function()
			piece:Destroy()
		end)
	end
end

-- 12345 -> "12,345"
local function withCommas(number: number): string
	local reversed = string.gsub(string.reverse(tostring(number)), "(%d%d%d)", "%1,")
	local text = string.reverse(reversed)
	return if string.sub(text, 1, 1) == "," then string.sub(text, 2) else text
end

-- How rare a bee is for this player right now, their luck counted: "1 in 333".
-- (The Halloween Egg's bees use the egg's own chances.)
local function chanceText(beeName: string): string?
	local luck = State.RollLuck()
	local percent = GameConfig.BeeChances(luck)[beeName]
	if percent == nil and GameConfig.HalloweenEgg then
		percent = GameConfig.EggChances(GameConfig.HalloweenEgg, luck)[beeName]
	end
	if not percent or percent <= 0 then
		return nil
	end
	return "1 in " .. withCommas(math.max(1, math.floor(100 / percent + 0.5)))
end

-- One of the white glow pictures, centred on its parent and tinted.
local function fxImage(parent: Instance, image: string, size: number, color: Color3, transparency: number, zIndex: number, name: string?): ImageLabel
	return Kit.Create("ImageLabel", {
		Name = name or "Fx",
		BackgroundTransparency = 1,
		Image = image,
		ImageColor3 = color,
		ImageTransparency = transparency,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		ZIndex = zIndex,
		Parent = parent,
	})
end

-- Keeps something turning round until it is destroyed. seconds = one full turn (below 0: the other way).
local function spinForever(thing: GuiObject, seconds: number)
	local goal = thing.Rotation + (if seconds < 0 then -360 else 360)
	TweenService:Create(thing, TweenInfo.new(math.abs(seconds), Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = goal }):Play()
end

-- Makes something grow out of nothing with a little bounce, after `delay` seconds.
local function popIn(thing: GuiObject, delay: number?, seconds: number?): UIScale
	local scale = Kit.Create("UIScale", { Name = "PopIn", Scale = 0, Parent = thing })
	TweenService:Create(scale, TweenInfo.new(seconds or 0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay or 0), { Scale = 1 }):Play()
	return scale
end

-- Little stars that keep twinkling at random spots round the middle of `centre` (a frame of no
-- size) while `alive()` says so.
local function twinkles(centre: GuiObject, count: number, inner: number, outer: number, color: Color3, zIndex: number, alive: () -> boolean)
	local random = Random.new()
	for _ = 1, count do
		task.spawn(function()
			task.wait(random:NextNumber(0, 0.9))
			while alive() and centre.Parent do
				local angle = random:NextNumber(0, math.pi * 2)
				local distance = random:NextNumber(inner, outer)
				local star = fxImage(centre, UIImages.Fx.Sparkle, random:NextNumber(30, 60), if random:NextNumber() < 0.5 then Kit.Colors.White else color, 0, zIndex, "Twinkle")
				star.Position = UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance * 0.8)
				local scale = Kit.Create("UIScale", { Scale = 0, Parent = star })
				TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				TweenService:Create(star, TweenInfo.new(0.9, Enum.EasingStyle.Linear), { Rotation = random:NextNumber(-90, 90) }):Play()
				task.wait(0.4)
				TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
				task.wait(0.4)
				star:Destroy()
				task.wait(random:NextNumber(0.1, 0.7))
			end
		end)
	end
end

-- Blurs the world behind a reveal (only on this screen), or brings it back.
local function blurWorld(on: boolean)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local blur = camera:FindFirstChild("RevealBlur") :: BlurEffect?
	if not blur then
		if not on then
			return
		end
		blur = Kit.Create("BlurEffect", { Name = "RevealBlur", Size = 0, Parent = camera })
	end
	TweenService:Create(blur :: BlurEffect, TweenInfo.new(if on then 0.3 else 0.25), { Size = if on then REVEAL_BLUR else 0 }):Play()
end

-- Darkens and blurs the world and makes the stage that a reveal is built on.
local function startReveal()
	if currentReveal then
		currentReveal.Destroy()
		currentReveal = nil
	end

	local reveal = { Closed = false, Parts = {} :: { Instance }, OpenedAt = os.clock() }

	-- dark backdrop (tap anywhere to close once the reveal is out)
	reveal.Dim = Kit.Create("TextButton", {
		Name = "RevealDim",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		-- bigger than the screen so it also covers the top bar strip and phone edges
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 600, 1, 600),
		ZIndex = 15,
		Parent = gui,
	})
	table.insert(reveal.Parts, reveal.Dim)
	TweenService:Create(reveal.Dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.35 }):Play()
	blurWorld(true)

	reveal.Root = Kit.Create("Frame", {
		Name = "Reveal",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(720, 600),
		ZIndex = 16,
		Parent = gui,
	})
	Kit.AutoScale(reveal.Root, Vector2.new(720, 620))
	table.insert(reveal.Parts, reveal.Root)
	-- everything is built on the stage, which shrinks away when the reveal closes
	reveal.Stage = Kit.Create("Frame", { Name = "Stage", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 16, Parent = reveal.Root })
	reveal.StageScale = Kit.Create("UIScale", { Name = "Close", Scale = 1, Parent = reveal.Stage })

	function reveal.Alive(): boolean
		return not reveal.Closed and currentReveal == reveal
	end

	function reveal.Destroy()
		reveal.Closed = true
		blurWorld(false)
		for _, part in reveal.Parts do
			part:Destroy()
		end
	end

	currentReveal = reveal
	return reveal
end

local function whiteFlash(reveal)
	local flash = Kit.Create("Frame", {
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 600, 1, 600),
		ZIndex = 18,
		Parent = gui,
	})
	table.insert(reveal.Parts, flash)
	TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
end

-- Closes a reveal when it has been up for `holdSeconds`, or sooner when the player taps.
-- Everything shrinks away and the world comes back.
local function closeWhenDone(reveal, holdSeconds: number, onClose: (() -> ())?)
	local function close()
		if reveal.Closed or currentReveal ~= reveal then
			return
		end
		reveal.Closed = true
		local shrink = TweenService:Create(reveal.StageScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		shrink:Play()
		TweenService:Create(reveal.Dim, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
		blurWorld(false)
		shrink.Completed:Once(function()
			if currentReveal == reveal then
				currentReveal = nil
			end
			reveal.Destroy()
		end)
		if onClose then
			onClose()
		end
	end
	reveal.Dim.Activated:Connect(function()
		if os.clock() - reveal.OpenedAt > TAP_GUARD then
			close()
		end
	end)
	task.delay(holdSeconds, close)
end

-- The light behind a reveal: a wide glow in `color`, two layers of rays turning opposite ways,
-- and a white glow in the heart that breathes. Returns the holder (a frame of no size in the
-- middle of where the light shines) and the UIScale that grows it.
local function makeLight(stage: GuiObject, color: Color3, y: number)
	local light = Kit.Create("Frame", { Name = "Light", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, y), Size = UDim2.fromOffset(0, 0), ZIndex = 16, Parent = stage })
	local grow = Kit.Create("UIScale", { Name = "Grow", Scale = 0, Parent = light })
	fxImage(light, UIImages.Fx.Glow, 720, Kit.Lighten(color, 0.3), 0.05, 16, "Glow")
	local rays = fxImage(light, UIImages.Fx.Rays, 960, color, 0.1, 16, "Rays")
	spinForever(rays, 18)
	local whiteRays = fxImage(light, UIImages.Fx.Rays, 720, Kit.Colors.White, 0.5, 16, "WhiteRays")
	whiteRays.Rotation = 15
	spinForever(whiteRays, -26)
	local heart = fxImage(light, UIImages.Fx.Glow, 380, Kit.Colors.White, 0.15, 16, "Heart")
	TweenService:Create(heart, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = UDim2.fromOffset(440, 440) }):Play()
	return light, grow
end

-- A dark pill with one line of writing (how rare a bee is, or how many bees a hive holds).
local function makePill(stage: GuiObject, text: string, color: Color3, y: number, width: number): (Frame, TextLabel)
	local pill = Kit.Create("Frame", {
		Name = "Pill",
		BackgroundColor3 = Kit.Colors.Body,
		BackgroundTransparency = 0.12,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(width, 52),
		ZIndex = 18,
		Parent = stage,
	})
	Kit.Corner(pill, 26)
	Kit.Stroke(pill, 4, Kit.Lighten(color, 0.2))
	local label = Kit.Label({ Parent = pill, Text = text, TextSize = 32, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -24, 1, -10), Fit = true, ZIndex = 19 })
	return pill, label
end

local function tapToClose(stage: GuiObject)
	local hint = Kit.Label({ Parent = stage, Text = "tap to close", TextSize = 26, Color = Color3.fromRGB(235, 235, 235), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.fromOffset(300, 30), Stroke = 3, ZIndex = 18 })
	TweenService:Create(hint, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.45 }):Play()
end

type SpotlightOptions = {
	Title: string, -- the big letters at the top ("LEGENDARY!")
	TitleOf: string?, -- a bee's name: the title is written in its rarity's colours (rainbow for the best)
	Name: string, -- under the picture
	NameOf: string?, -- a bee's name: the name is written in rainbow if it is one of the best
	Model: Model,
	Zoom: number?,
	Color: Color3, -- the colour of the rays and the glow
	Pill: string?, -- the line in the dark pill at the bottom ("1 in 333")
	HoldSeconds: number,
	OnClose: (() -> ())?,
}

-- THE SPOTLIGHT: a Legendary or secret bee is yours.
local function showSpotlight(reveal, options: SpotlightOptions)
	local stage = reveal.Stage
	local _, lightGrow = makeLight(stage, options.Color, 0.47)
	TweenService:Create(lightGrow, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	-- the bee, turning slowly and bobbing
	local beeHolder = Kit.Create("Frame", { Name = "Bee", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(340, 340), ZIndex = 17, Parent = stage })
	local picture = Kit.Viewport({ Parent = beeHolder, Position = UDim2.fromOffset(0, -8), ZIndex = 17 })
	Kit.SetViewportModel(picture, options.Model, true, options.Zoom)
	TweenService:Create(picture, TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(0, 8) }):Play()
	popIn(beeHolder, 0.08, 0.6)

	-- the rarity in big letters, tilted a little and rocking
	local title = Kit.Label({ Parent = stage, Name = "Title", Text = options.Title, TextSize = 92, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.new(1, -30, 0, 108), Stroke = 7, Fit = true, ZIndex = 18 })
	title.Rotation = -3
	if options.TitleOf then
		Kit.RarityText(title, options.TitleOf, 0.1)
	else
		title.TextColor3 = Kit.Colors.Honey
	end
	popIn(title, 0.2, 0.5)
	TweenService:Create(title, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0.7), { Rotation = 3 }):Play()

	-- the bee's name, and how rare it is
	local name = Kit.Label({ Parent = stage, Name = "BeeName", Text = options.Name, TextSize = 56, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -140), Size = UDim2.new(1, -60, 0, 64), Stroke = 5, Fit = true, ZIndex = 18 })
	if options.NameOf then
		Kit.BeeNameText(name, options.NameOf)
	end
	popIn(name, 0.32)
	if options.Pill then
		local pill = makePill(stage, options.Pill, options.Color, 600 - 74, 250)
		popIn(pill, 0.42)
	end
	tapToClose(stage)

	-- twinkles round the bee, and confetti over everything
	local centre = Kit.Create("Frame", { Name = "Twinkles", BackgroundTransparency = 1, Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(0, 0), ZIndex = 17, Parent = stage })
	twinkles(centre, 12, 150, 320, Kit.Lighten(options.Color, 0.4), 17, reveal.Alive)
	confetti(80, 19)

	closeWhenDone(reveal, options.HoldSeconds, options.OnClose)
end

local function flyBeeToBag(rarityName: string, from: Vector2)
	local target = targets.bag
	if not target then
		return
	end
	local size = math.floor(80 * Kit.ScreenScale())
	local picture = Kit.Viewport({
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(from.X, from.Y),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 12,
	})
	Kit.SetViewportModel(picture, Kit.BeeModel(rarityName), false, Kit.BEE_ZOOM)
	local finish = target.AbsolutePosition + target.AbsoluteSize / 2
	local tween = TweenService:Create(picture, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromOffset(finish.X, finish.Y),
		Size = UDim2.fromOffset(size * 0.4, size * 0.4),
	})
	tween:Play()
	tween.Completed:Once(function()
		picture:Destroy()
		Kit.PlaySound("Pop")
		local arrive = onArrive.bag
		if arrive then
			arrive()
		end
	end)
end

-- A NEW BEE: THE SMALL CARD ------------------------------------------------------------------

local quickCard: Frame? = nil
local QUICK_SECONDS = 2.2 -- how long the small card stays up

-- A bright card that slides up at the bottom of the screen. It does not block anything, so you
-- can keep rolling. The bee sits big on its left side, on a glow (and turning rays for Rare and
-- up, and twinkles for Epic and up), with its name, its rarity and how rare it is.
local function showQuickCard(rarityName: string, placed: boolean)
	local bee = GameConfig.Bees[rarityName]
	local tier = table.find(GameConfig.RarityOrder, bee.Rarity) or 3
	local rarityColor = bee.RarityColor or Kit.Colors.Honey
	if quickCard then
		quickCard:Destroy()
		quickCard = nil
	end

	local root = Kit.Create("Frame", {
		Name = "NewBeeCard",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(520, 134),
		ZIndex = 8,
		Parent = gui,
	})
	Kit.AutoScale(root)
	quickCard = root
	local function stillUp(): boolean
		return quickCard == root and root.Parent ~= nil
	end

	-- everything sits on this, which slides up from below the screen and back down
	local slide = Kit.Create("Frame", { Name = "Slide", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 200), Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = root })

	-- the card: a fade in the rarity's colours with a glossy top and a shine that sweeps across
	-- (a CanvasGroup, so the shine is cut to the card's round corners)
	local body = Kit.Create("CanvasGroup", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(62, 16), Size = UDim2.new(1, -62, 1, -16), ZIndex = 8, Parent = slide })
	Kit.Corner(body, 20)
	local fill = Kit.Create("Frame", { Name = "Fill", BackgroundColor3 = Kit.Colors.White, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = body })
	Kit.Corner(fill, 20)
	Kit.Gradient(fill, Kit.RarityFade(rarityName))
	local gloss = Kit.Create("Frame", { Name = "Gloss", BackgroundColor3 = Kit.Colors.White, BorderSizePixel = 0, Size = UDim2.fromScale(1, 0.48), ZIndex = 8, Parent = body })
	Kit.Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.55, 1), Parent = gloss })
	local shine = Kit.Create("Frame", { Name = "Shine", BackgroundColor3 = Kit.Colors.White, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -90, 0.5, 0), Size = UDim2.new(0, 80, 2, 0), Rotation = 18, ZIndex = 9, Parent = body })
	Kit.Create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1) }), Parent = shine })
	TweenService:Create(shine, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, false, 0.3), { Position = UDim2.new(1, 90, 0.5, 0) }):Play()
	local outline = Kit.Create("Frame", { Name = "Outline", BackgroundTransparency = 1, Position = body.Position, Size = body.Size, ZIndex = 10, Parent = slide })
	Kit.Corner(outline, 20)
	Kit.Stroke(outline, 4)

	-- the bee: big, sticking out of the card's left side
	local spot = Kit.Create("Frame", { Name = "BeeSpot", BackgroundTransparency = 1, Position = UDim2.fromOffset(70, 74), Size = UDim2.fromOffset(0, 0), ZIndex = 11, Parent = slide })
	fxImage(spot, UIImages.Fx.Glow, 190, Kit.Lighten(rarityColor, 0.45), 0.1, 11, "Glow")
	if tier >= 3 then
		local rays = fxImage(spot, UIImages.Fx.Rays, 240, Kit.Lighten(rarityColor, 0.2), 0.3, 11, "Rays")
		spinForever(rays, 9)
	end
	local beeHolder = Kit.Create("Frame", { Name = "Bee", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(132, 132), Rotation = -8, ZIndex = 12, Parent = spot })
	local picture = Kit.BeeIcon(beeHolder, 132, rarityName)
	picture.ZIndex = 12
	for _, part in picture:GetDescendants() do
		if part:IsA("GuiObject") then
			part.ZIndex = 12
		end
	end
	popIn(beeHolder, 0.12, 0.5)
	TweenService:Create(beeHolder, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 6 }):Play()
	if tier >= 4 then
		twinkles(spot, 4, 40, 85, Kit.Colors.White, 13, stillUp)
	end

	-- the words: a "NEW BEE!" tab on the top edge, the name, then the rarity and the chance
	local tab = Kit.Create("Frame", { Name = "NewTab", BackgroundColor3 = Kit.Colors.White, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(142, 16), Size = UDim2.fromOffset(140, 34), Rotation = -4, ZIndex = 13, Parent = slide })
	Kit.Corner(tab, 12)
	Kit.Stroke(tab, 3.5)
	Kit.Gradient(tab, Kit.Lighten(Kit.Colors.Yellow, 0.4), Kit.Colors.Yellow)
	Kit.Label({ Parent = tab, Text = "NEW BEE!", TextSize = 24, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -12, 1, -4), Stroke = 3, Fit = true, ZIndex = 14 })
	popIn(tab, 0.2)
	local nameLabel = Kit.Label({ Parent = slide, Name = "BeeName", Text = bee.BeeName, TextSize = 36, XAlign = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(146, 38), Size = UDim2.new(1, -162, 0, 44), Stroke = 4, Fit = true, ZIndex = 13 })
	Kit.BeeNameText(nameLabel, rarityName) -- the best bees' names are rainbow
	local function smallPill(x: number, width: number, text: string): TextLabel
		local pill = Kit.Create("Frame", { Name = "Pill", BackgroundColor3 = Kit.Colors.Body, BackgroundTransparency = 0.2, Position = UDim2.fromOffset(x, 88), Size = UDim2.fromOffset(width, 34), ZIndex = 13, Parent = slide })
		Kit.Corner(pill, 17)
		return Kit.Label({ Parent = pill, Text = text, TextSize = 22, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -16, 1, -6), Stroke = 2.5, Fit = true, ZIndex = 14 })
	end
	local rarityLabel = smallPill(146, 138, bee.DisplayName)
	Kit.RarityText(rarityLabel, rarityName, 0.25)
	local chance = chanceText(rarityName)
	if chance then
		smallPill(292, 150, chance)
	end

	TweenService:Create(slide, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(0, 0) }):Play()
	task.delay(QUICK_SECONDS, function()
		if quickCard ~= root then
			return -- a newer card already replaced this one
		end
		quickCard = nil
		if not placed then
			flyBeeToBag(rarityName, beeHolder.AbsolutePosition + beeHolder.AbsoluteSize / 2) -- into the My Hive button
		end
		beeHolder.Visible = false
		local away = TweenService:Create(slide, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(0, 200) })
		away:Play()
		away.Completed:Once(function()
			root:Destroy()
		end)
	end)
end

-- Called when the Queen rolls you a bee. Legendary and secret bees get the spotlight; the
-- others get the small card so you can keep rolling without waiting.
-- bought = true when it was bought from the player's own stand, where its reveal jingle has
-- already played: then the happy "bought it!" sound plays instead.
function Effects.Rolled(rarityName: string, placed: boolean, bought: boolean?)
	local rarity = GameConfig.Bees[rarityName]
	if not rarity then
		return
	end
	-- 1 = Common, higher = rarer. (A Limited bee counts as a middle tier, and a Secret one as the very top.)
	local tier = table.find(GameConfig.RarityOrder, rarity.Rarity) or (if rarity.Secret then #GameConfig.RarityOrder else 3)
	local isTopTier = tier == #GameConfig.RarityOrder

	if not isTopTier then
		Kit.PlaySound(if bought then "Buy" else Kit.RevealSoundFor(rarityName))
		showQuickCard(rarityName, placed)
		return
	end

	local reveal = startReveal()
	whiteFlash(reveal)
	Kit.PlaySound(if bought then "Celebrate" else "BigReveal")
	showSpotlight(reveal, {
		Title = if rarity.Secret then "SECRET BEE!!!" else string.upper(rarity.DisplayName) .. "!",
		TitleOf = rarityName,
		Name = rarity.BeeName,
		NameOf = rarityName,
		Model = Kit.BeeModel(rarityName),
		Zoom = Kit.BEE_ZOOM,
		Color = rarity.RarityColor or Kit.Colors.Gold,
		Pill = chanceText(rarityName),
		HoldSeconds = if rarity.Secret then 6 else 4.5,
		OnClose = function()
			if not placed then
				flyBeeToBag(rarityName, gui.AbsoluteSize / 2)
			end
		end,
	})
end

-- A BIGGER HIVE: the old hive shakes harder and harder, then bursts into the new one, and the
-- number of bees it holds counts up.
local HIVE_SHAKE_SECONDS = 1.05

function Effects.HiveUpgraded(level: number)
	local hive = GameConfig.HiveLevels[level]
	if not hive then
		return
	end
	local before = GameConfig.HiveLevels[level - 1]
	local reveal = startReveal()
	local stage = reveal.Stage
	local _, lightGrow = makeLight(stage, Kit.Colors.Gold, 0.47)

	local function hivePicture(hiveLevel: number, spin: boolean): (Frame, ViewportFrame)
		local holder = Kit.Create("Frame", { Name = "Hive", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(330, 330), ZIndex = 17, Parent = stage })
		local picture = Kit.Viewport({ Parent = holder, ZIndex = 17 })
		Kit.SetViewportModel(picture, Kit.HiveModel(hiveLevel), spin)
		return holder, picture
	end

	local shakeFor = if before then HIVE_SHAKE_SECONDS else 0
	if before then
		-- the old hive, under a dim light, shaking harder and harder
		TweenService:Create(lightGrow, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.5 }):Play()
		local old, oldPicture = hivePicture(level - 1, false)
		popIn(old, 0, 0.3)
		-- (a 3D picture cannot be turned like a flat one, so its camera tilts instead)
		local camera = oldPicture.CurrentCamera :: Camera
		local still = camera.CFrame
		local started = os.clock()
		local shaking
		shaking = RunService.RenderStepped:Connect(function()
			local t = os.clock() - started
			if t >= shakeFor or not old.Parent then
				shaking:Disconnect()
				old:Destroy()
				return
			end
			local hurry = t / shakeFor
			local wobble = math.sin(t * (26 + hurry * 30))
			camera.CFrame = still * CFrame.Angles(0, 0, math.rad(wobble * (2 + hurry * 9)))
			old.Position = UDim2.new(0.5, wobble * hurry * 6, 0.47, 0)
			old.Size = UDim2.fromOffset(330 + hurry * 40, 330 + hurry * 40)
		end)
		Kit.PlaySound("Shake")
		task.delay(shakeFor * 0.35, Kit.PlaySound, "Shake", 1.15)
		task.delay(shakeFor * 0.7, Kit.PlaySound, "Shake", 1.3)
	end

	task.delay(shakeFor, function()
		if not reveal.Alive() then
			return
		end
		-- POP: the new hive, the full light, confetti
		whiteFlash(reveal)
		Kit.PlaySound("Celebrate")
		TweenService:Create(lightGrow, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		popIn((hivePicture(level, true)), 0, 0.6)
		confetti(60, 19)
		local centre = Kit.Create("Frame", { Name = "Twinkles", BackgroundTransparency = 1, Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(0, 0), ZIndex = 17, Parent = stage })
		twinkles(centre, 10, 150, 320, Kit.Colors.Honey, 17, reveal.Alive)

		local title = Kit.Label({ Parent = stage, Name = "Title", Text = "HIVE UPGRADED!", TextSize = 84, Color = Kit.Colors.Honey, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.new(1, -30, 0, 100), Stroke = 7, Fit = true, ZIndex = 18 })
		title.Rotation = -3
		popIn(title, 0.12, 0.5)
		TweenService:Create(title, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0.7), { Rotation = 3 }):Play()
		local name = Kit.Label({ Parent = stage, Name = "HiveName", Text = hive.Name, TextSize = 56, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -140), Size = UDim2.new(1, -60, 0, 64), Stroke = 5, Fit = true, ZIndex = 18 })
		popIn(name, 0.24)

		-- "4 bees > 6 bees", the new number counting up
		local fromCount = if before then before.Capacity else hive.Capacity
		local pill, label = makePill(stage, "", Kit.Colors.Gold, 600 - 74, 330)
		label.RichText = true
		local function write(count: number)
			local lime = "#" .. Kit.Colors.Lime:ToHex()
			label.Text = if before then string.format("%d bees  >  <font color=\"%s\">%d bees</font>", fromCount, lime, count) else string.format("Holds <font color=\"%s\">%d bees</font>", lime, count)
		end
		write(fromCount)
		popIn(pill, 0.34)
		local counter = Kit.Create("NumberValue", { Value = fromCount, Parent = pill })
		counter.Changed:Connect(function(value)
			write(math.floor(value + 0.5))
		end)
		TweenService:Create(counter, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.5), { Value = hive.Capacity }):Play()
		tapToClose(stage)
	end)

	closeWhenDone(reveal, shakeFor + 3.8)
end

-- A shop upgrade (Luck, Bee Speed) was bought. The beehive has its own big reveal above.
-- (bonus: the stands the "+2 Rolls" pass adds, so More Rolls names the real number of bees)
function Effects.Upgraded(id: string, level: number, bonus: number?)
	Kit.PlaySound("Upgrade")
	Effects.Toast(Upgrades.DisplayName(id) .. " upgraded!  " .. Upgrades.Describe(id, level, bonus), "good")
end

-- THE BIG SHOW ------------------------------------------------------------------------------
-- A bee of a BigReveal rarity (see GameConfig.Bees) has just hatched on your own stand.
-- A white flash, the rarity in huge rainbow letters, confetti, and a fanfare. It does not
-- block anything: you can walk up and buy the bee while it plays.

-- loudness (optional, 0 to 1): how loud the fanfare is. The flash, letters and confetti always show.
function Effects.BigReveal(beeName: string, loudness: number?)
	local bee = GameConfig.Bees[beeName]
	if not bee then
		return
	end

	-- the flash
	local flash = Kit.Create("Frame", {
		Name = "BigFlash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.05,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 600, 1, 600),
		ZIndex = 14,
		Parent = gui,
	})
	local fade = TweenService:Create(flash, TweenInfo.new(0.7), { BackgroundTransparency = 1 })
	fade:Play()
	fade.Completed:Once(function()
		flash:Destroy()
	end)

	-- the fanfare: a magic burst, a run of dings up the scale and a sparkle (GameConfig.SoundTunes)
	Kit.PlaySound("BigReveal", 1, loudness)

	confetti(70)

	-- the rarity in huge rainbow letters, with the bee's name under it
	local banner = Kit.Create("Frame", {
		Name = "BigRevealBanner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(900, 190),
		ZIndex = 13,
		Parent = gui,
	})
	Kit.AutoScale(banner, Vector2.new(940, 200))
	local pop = Kit.Create("UIScale", { Name = "Pop", Scale = 0.2, Parent = banner })
	local title = Kit.Label({
		Parent = banner,
		Name = "Rarity",
		Text = string.upper(bee.DisplayName) .. "!",
		TextSize = 100,
		Size = UDim2.new(1, 0, 0, 112),
		Stroke = 7,
		Fit = true,
		ZIndex = 13,
	})
	Kit.RarityText(title, beeName, 0.1)
	local name = Kit.Label({
		Parent = banner,
		Name = "BeeName",
		Text = bee.BeeName,
		TextSize = 50,
		Position = UDim2.fromOffset(0, 118),
		Size = UDim2.new(1, 0, 0, 60),
		Stroke = 5,
		Fit = true,
		ZIndex = 13,
	})
	TweenService:Create(pop, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(2.6, function()
		local out = TweenInfo.new(0.4)
		for _, label in { title, name } do
			TweenService:Create(label, out, { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, out, { Transparency = 1 }):Play()
			end
		end
		task.wait(0.45)
		banner:Destroy()
	end)
end

return Effects
