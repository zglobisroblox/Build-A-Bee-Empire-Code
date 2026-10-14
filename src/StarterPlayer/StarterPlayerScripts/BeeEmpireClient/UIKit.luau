--[[
	UIKit - the "look" of the whole game UI in one place.

	Every button, panel, card and label on screen is made by a helper in this file,
	so the whole game shares one toy-brick style: flat bright buttons with dark outlines,
	dark see-through windows with a coloured title bar and a red X. Change a colour or a corner
	size here and it changes everywhere. The little pictures (coin, bees, hives...) are
	drawings of our own 3D models; their picture numbers are in BeeEmpire.UIImages.

	Sizes are written for a 1280 x 720 screen and then shrunk or grown to fit the
	player's real screen (see AutoScale). Phones get a bigger minimum size so text
	and buttons stay easy to read and tap.
]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("BeeEmpire")
local GameConfig = require(sharedFolder:WaitForChild("GameConfig"))
local BeeModelFactory = require(sharedFolder:WaitForChild("BeeModelFactory"))
local HiveModelFactory = require(sharedFolder:WaitForChild("HiveModelFactory"))
local UIImages = require(sharedFolder:WaitForChild("UIImages"))

local Kit = {}

-- fetch every menu picture straight away, so none pops in late the first time a menu opens
task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync(UIImages.All())
	end)
end)

Kit.Font = Enum.Font.FredokaOne

Kit.Colors = {
	Outline = Color3.fromRGB(20, 16, 26), -- the dark "ink" round everything
	White = Color3.fromRGB(255, 255, 255),
	-- windows: a dark see-through body under a bright title bar
	Body = Color3.fromRGB(14, 12, 18),
	Inner = Color3.fromRGB(20, 16, 26),
	Line = Color3.fromRGB(20, 16, 26),
	-- button and title-bar colours (each has a lighter top band, see BAND_TOPS below)
	Title = Color3.fromRGB(255, 176, 31), -- honey (the My Hive button and window)
	Green = Color3.fromRGB(63, 203, 63), -- yes / go
	Yellow = Color3.fromRGB(255, 194, 26), -- buy
	Blue = Color3.fromRGB(58, 157, 240), -- plain
	Red = Color3.fromRGB(227, 58, 50), -- remove / sell / close
	Pink = Color3.fromRGB(238, 79, 200), -- special
	Orange = Color3.fromRGB(255, 138, 31),
	Grey = Color3.fromRGB(154, 158, 175), -- cannot use
	Cyan = Color3.fromRGB(32, 232, 240),
	Purple = Color3.fromRGB(170, 84, 250),
	-- text colours
	Honey = Color3.fromRGB(255, 212, 90),
	Money = Color3.fromRGB(124, 255, 58), -- the bright green used for coins and prices
	Lime = Color3.fromRGB(120, 255, 40), -- "2 > 4" change text
	Select = Color3.fromRGB(255, 236, 60), -- the outline of a picked card
	-- pictures
	Gold = Color3.fromRGB(255, 205, 50),
	GoldDark = Color3.fromRGB(255, 174, 18),
	Jar = Color3.fromRGB(255, 170, 30),
	Cream = Color3.fromRGB(250, 242, 225),
	Toast = Color3.fromRGB(45, 28, 10),
}

-- The lighter top band that goes with each colour above. A colour that is not listed
-- gets a paler version of itself.
local BAND_TOPS = {
	[Kit.Colors.Title:ToHex()] = Color3.fromRGB(255, 212, 90),
	[Kit.Colors.Green:ToHex()] = Color3.fromRGB(123, 240, 106),
	[Kit.Colors.Yellow:ToHex()] = Color3.fromRGB(255, 230, 107),
	[Kit.Colors.Blue:ToHex()] = Color3.fromRGB(116, 198, 255),
	[Kit.Colors.Red:ToHex()] = Color3.fromRGB(255, 123, 110),
	[Kit.Colors.Pink:ToHex()] = Color3.fromRGB(255, 134, 224),
	[Kit.Colors.Orange:ToHex()] = Color3.fromRGB(255, 184, 96),
	[Kit.Colors.Grey:ToHex()] = Color3.fromRGB(201, 204, 216),
}

-- The top-to-bottom fade of a bee card, by rarity (both bees of a rarity share it). A rarity
-- that is not listed gets a fade made from its own colour.
local CARD_FADES = {
	Common = { Color3.fromRGB(237, 239, 246), Color3.fromRGB(169, 174, 191) },
	Uncommon = { Color3.fromRGB(166, 245, 132), Color3.fromRGB(63, 198, 74) },
	Rare = { Color3.fromRGB(142, 208, 255), Color3.fromRGB(47, 134, 240) },
	Epic = { Color3.fromRGB(226, 172, 255), Color3.fromRGB(150, 72, 240) },
	Legendary = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 138, 24) },
	Limited = { Color3.fromRGB(255, 176, 84), Color3.fromRGB(146, 72, 208) }, -- pumpkin orange into purple
}

-- how see-through the window body and the boxes inside it are (0 = solid, 1 = invisible)
Kit.BodyTransparency = 0.32
Kit.InnerTransparency = 0.5

Kit.BEE_ZOOM = 0.68

local BLACK = Color3.new(0, 0, 0)

-- BASICS ----------------------------------------------------------------------------

function Kit.Create(className: string, props: { [string]: any }): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	instance.Parent = props.Parent
	return instance
end

local create = Kit.Create

function Kit.Darken(color: Color3, amount: number): Color3
	return color:Lerp(BLACK, amount)
end

function Kit.Lighten(color: Color3, amount: number): Color3
	return color:Lerp(Kit.Colors.White, amount)
end

function Kit.Corner(parent: Instance, radius: number)
	return create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

-- (written further down, under FITTING ANY SCREEN)
local screenScale: () -> number

-- Outlines are written for a 1280 x 720 screen. On a smaller screen everything else shrinks,
-- so outlines are thinned to match (never below 60%, so they do not vanish).
local function strokeScale(): number
	return math.clamp(screenScale(), 0.6, 1.25)
end

function Kit.Stroke(parent: Instance, thickness: number, color: Color3?)
	return create("UIStroke", {
		Thickness = thickness * strokeScale(),
		Color = color or Kit.Colors.Outline,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = if parent:IsA("TextLabel") then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- A top-to-bottom colour fade. The parent's own colour should be white.
function Kit.Gradient(parent: Instance, top: Color3, bottom: Color3)
	return create("UIGradient", { Rotation = 90, Color = ColorSequence.new(top, bottom), Parent = parent })
end

local function bandSequence(color: Color3, split: number): ColorSequence
	local top = BAND_TOPS[color:ToHex()] or color:Lerp(Color3.new(1, 1, 1), 0.3)
	if split <= 0 then
		-- soft version: the lighter colour melts into the main one
		return ColorSequence.new(top, color)
	end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(split, top),
		ColorSequenceKeypoint.new(math.min(split + 0.001, 0.999), color),
		ColorSequenceKeypoint.new(1, color),
	})
end

-- The toy-brick fill: a lighter band across the top half and the main colour below, with a
-- hard edge between them. The parent's own colour should be white. Use SetBands to recolour.
function Kit.Bands(parent: Instance, color: Color3, split: number?): UIGradient
	local gradient = create("UIGradient", { Name = "Bands", Rotation = 90, Color = bandSequence(color, split or 0.5), Parent = parent })
	gradient:SetAttribute("Split", split or 0.5) -- 0 = a soft fade instead of a hard edge
	return gradient
end

function Kit.SetBands(gradient: UIGradient, color: Color3)
	gradient.Color = bandSequence(color, gradient:GetAttribute("Split") or 0.5)
end

-- The light and dark colour of a bee card. Give a bee's name or a rarity's name.
function Kit.RarityFade(name: string): (Color3, Color3)
	local bee = GameConfig.Bees[name]
	local rarityName = if bee then bee.Rarity else name
	local pair = CARD_FADES[rarityName]
	if pair then
		return pair[1], pair[2]
	end
	local color = GameConfig.Rarities[rarityName].Color
	return Kit.Lighten(color, 0.55), Kit.Darken(color, 0.08)
end

-- "0.5 jars/sec", "1 jar/sec"
function Kit.FormatRate(rate: number): string
	return string.format("%g", rate) .. (if rate == 1 then " jar/sec" else " jars/sec")
end

-- FITTING ANY SCREEN ------------------------------------------------------------------

local function viewportSize(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

local function isSmallOrTouch(size: Vector2): boolean
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	return touchOnly or size.Y < 520
end

function screenScale(): number
	local size = viewportSize()
	if isSmallOrTouch(size) then
		-- phones: never shrink below 0.7 so text and buttons stay readable and tappable
		return math.clamp(math.min(size.X / 1040, size.Y / 580), 0.7, 1.25)
	end
	return math.clamp(math.min(size.X / 1280, size.Y / 720), 0.5, 1.25)
end

-- { UIScale, size it must fit inside the screen (optional) }
local autoScales: { { Scale: UIScale, Fit: Vector2? } } = {}

local function scaleFor(fit: Vector2?): number
	local scale = screenScale()
	if fit then
		local size = viewportSize()
		local inset = GuiService:GetGuiInset()
		local availableX = size.X - 20
		local availableY = size.Y - inset.Y - 16
		scale = math.min(scale, availableX / fit.X, availableY / fit.Y)
	end
	return scale
end

local function refreshScales()
	for index = #autoScales, 1, -1 do
		local entry = autoScales[index]
		if entry.Scale.Parent then
			entry.Scale.Scale = scaleFor(entry.Fit)
		else
			table.remove(autoScales, index)
		end
	end
end

-- Makes a piece of UI grow and shrink with the player's screen.
-- fit (optional) is the design size that must always fit on screen, used for windows.
function Kit.AutoScale(guiObject: GuiObject, fit: Vector2?): UIScale
	local uiScale = create("UIScale", { Name = "AutoScale", Scale = scaleFor(fit), Parent = guiObject })
	table.insert(autoScales, { Scale = uiScale, Fit = fit })
	return uiScale
end

function Kit.ScreenScale(): number
	return screenScale()
end

local function watchCamera()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScales)
	end
	refreshScales()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

-- SOUNDS ----------------------------------------------------------------------------------
-- The sound effects, and the little jingles made from them, are listed in GameConfig
-- (Sounds and SoundTunes). They come from Roblox's own free library, so nothing needs uploading.

local SOUNDS = GameConfig.Sounds
local TUNES = GameConfig.SoundTunes
local templates: { [string]: Sound } = {}
local loops: { [Sound]: string } = {} -- sounds that loop out in the world (the bees at every hive)
local soundFactor = 1 -- the Sounds slider in the Settings window: 0 = silent, 1 = full
local soundRandom = Random.new()
local lastPlayed: { [string]: number } = {} -- when each jingle last started
local SAME_MOMENT = 0.1 -- seconds: the same jingle asked for again within this plays only once
local lastReveal = { At = -1, Rank = 0 } -- the biggest bee reveal of this moment

local function soundTemplate(name: string): Sound?
	local found = templates[name]
	if found then
		return found
	end
	local info = SOUNDS[name]
	if not info then
		return nil
	end
	local sound = create("Sound", { Name = "BeeSound_" .. name, SoundId = info.Id, Volume = 0 })
	if info.From or info.To then
		-- play only part of the recording
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(info.From or 0, info.To or 600)
	end
	templates[name] = sound
	return sound
end

-- fetch every sound straight away, so the first pop is not late
task.spawn(function()
	local list = {}
	for name in SOUNDS do
		local sound = soundTemplate(name)
		if sound then
			table.insert(list, sound)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
end)

-- How loud the sound effects are, from 0 to 100 (the Sounds slider in the Settings window).
function Kit.SetSoundVolume(percent: number)
	soundFactor = math.clamp(percent / 100, 0, 1)
	for sound, name in loops do
		if sound.Parent then
			sound.Volume = SOUNDS[name].Volume * soundFactor
		else
			loops[sound] = nil
		end
	end
end

-- One sound from GameConfig.Sounds, at a pitch and loudness.
local function playOne(name: string, speed: number, loudness: number)
	local info = SOUNDS[name]
	local base = soundTemplate(name)
	if not info or not base or soundFactor <= 0 then
		return
	end
	local vary = info.Vary or 0
	local copy = base:Clone()
	copy.PlaybackSpeed = speed * (info.Speed or 1) * (1 + soundRandom:NextNumber(-vary, vary))
	copy.Volume = info.Volume * soundFactor * loudness
	copy.Parent = SoundService
	copy:Play()
	local length = if info.To then info.To - (info.From or 0) else math.max(base.TimeLength - (info.From or 0), 1)
	Debris:AddItem(copy, length / copy.PlaybackSpeed + 0.5)
end

-- Plays a jingle from GameConfig.SoundTunes (or one sound from GameConfig.Sounds) by its name.
-- speed (optional) changes the pitch, e.g. 1.2 sounds higher.
-- loudness (optional, 0 to 1) plays it more quietly: 0.5 is half as loud, 0 is not played at all.
function Kit.PlaySound(name: string, speed: number?, loudness: number?)
	local loud = loudness or 1
	if loud <= 0 then
		return
	end
	-- (3 to 5 stands roll at the same time: their sounds would pile up and get too loud)
	local now = os.clock()
	if now - (lastPlayed[name] or -1) < (if name == "Coin" or name == "JarLand" then 0.03 else SAME_MOMENT) then
		return
	end
	lastPlayed[name] = now
	local rank = if name == "BigReveal" then 9 else tonumber(name:match("^Reveal(%d)$"))
	if rank then
		-- several bees revealed at once: only the rarest one's jingle plays
		if now - lastReveal.At < SAME_MOMENT and lastReveal.Rank >= rank then
			return
		end
		lastReveal.At, lastReveal.Rank = now, rank
	end
	local pitch = speed or 1
	local tune = TUNES[name]
	if not tune then
		playOne(name, pitch, loud)
		return
	end
	for _, step in tune do
		local soundName, at, stepPitch, stepLoud = step[1], step[2] or 0, step[3] or 1, step[4] or 1
		if at <= 0 then
			playOne(soundName, pitch * stepPitch, loud * stepLoud)
		else
			task.delay(at, playOne, soundName, pitch * stepPitch, loud * stepLoud)
		end
	end
end

-- The pitch for the nth thing in a run: coins (or jars) landing one after another climb a scale.
function Kit.ScaleNote(index: number): number
	local scale = GameConfig.SoundScale
	return scale[math.clamp(index, 1, #scale)]
end

-- The jingle for a bee that was just revealed or found: the rarer, the bigger.
-- (Common "Reveal1" up to Epic "Reveal4"; the best rarity and secret bees get "BigReveal";
-- a limited-time bee counts as a Rare.)
function Kit.RevealSoundFor(beeName: string): string
	local bee = GameConfig.Bees[beeName]
	if not bee then
		return "Reveal1"
	end
	local order = GameConfig.RarityOrder
	local tier = table.find(order, bee.Rarity) or (if bee.Secret then #order else 3)
	if tier >= #order then
		return "BigReveal"
	end
	return "Reveal" .. math.clamp(tier, 1, 4)
end

-- A sound that loops out in the world, louder up close: full within `near` studs, gone by `far`.
-- (The bees buzzing at a hive.) It follows the Sounds slider; destroy it, or its parent, to stop it.
function Kit.LoopSound(name: string, parent: Instance, near: number, far: number): Sound?
	local info = SOUNDS[name]
	if not info then
		return nil
	end
	local sound = create("Sound", {
		Name = "BeeLoop_" .. name,
		SoundId = info.Id,
		Looped = true,
		Volume = info.Volume * soundFactor,
		PlaybackSpeed = info.Speed or 1,
		RollOffMode = Enum.RollOffMode.InverseTapered,
		RollOffMinDistance = near,
		RollOffMaxDistance = far,
		Parent = parent,
	})
	loops[sound] = name
	sound.TimePosition = soundRandom:NextNumber(0, 20) -- so two hives never buzz exactly in step
	sound:Play()
	return sound
end

-- TEXT --------------------------------------------------------------------------------------

export type LabelProps = {
	Parent: Instance?,
	Name: string?,
	Text: string?,
	TextSize: number?,
	Color: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	XAlign: Enum.TextXAlignment?,
	Stroke: number?,
	Fit: boolean?,
	ZIndex: number?,
	LayoutOrder: number?,
}

-- How thick the dark outline round writing is, for a size of writing.
local function outlineFor(textSize: number): number
	return if textSize >= 40 then 5 elseif textSize >= 26 then 3.5 elseif textSize >= 20 then 3 else 2.5
end

-- Chunky white text with a dark outline. Fit = true shrinks long text to stay inside its box.
-- Leave Stroke out and the outline is picked to suit the size of the writing.
function Kit.Label(props: LabelProps): TextLabel
	local label = create("TextLabel", {
		Name = props.Name or "Label",
		BackgroundTransparency = 1,
		Font = Kit.Font,
		Text = props.Text or "",
		TextSize = props.TextSize or 20,
		TextColor3 = props.Color or Kit.Colors.White,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Center,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 1,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	if props.Fit then
		label.TextScaled = true
		-- (the smallest size is low on purpose: on a small phone, tiny writing is better than a word cut in half)
		create("UITextSizeConstraint", { MaxTextSize = props.TextSize or 20, MinTextSize = 7, Parent = label })
	end
	if props.Stroke ~= 0 then
		Kit.Stroke(label, props.Stroke or outlineFor(props.TextSize or 20))
	end
	return label
end

-- RAINBOW WRITING ---------------------------------------------------------------------------
-- The best bees have their names written in moving rainbow colours. A label is made rainbow
-- by giving it a colour fade, and one small loop keeps every such fade sliding along.

local rainbowFades: { [UIGradient]: boolean } = {}
local rainbowRunning = false

local function rainbowSequence(now: number): ColorSequence
	local points = {}
	for step = 0, 4 do
		local hue = (now * 0.45 - step * 0.16) % 1
		table.insert(points, ColorSequenceKeypoint.new(step / 4, Color3.fromHSV(hue, 0.62, 1)))
	end
	return ColorSequence.new(points)
end

local function runRainbow()
	if rainbowRunning then
		return
	end
	rainbowRunning = true
	task.spawn(function()
		while next(rainbowFades) ~= nil do
			local colors = rainbowSequence(os.clock())
			for fade in rainbowFades do
				if fade.Parent then
					fade.Color = colors
				else
					rainbowFades[fade] = nil -- its label is gone
				end
			end
			task.wait(0.04)
		end
		rainbowRunning = false
	end)
end

-- Turns rainbow writing on or off for a label. (The writing itself turns white: the rainbow
-- is laid over it.)
function Kit.SetRainbow(label: Instance, on: boolean)
	local fade = label:FindFirstChild("Rainbow")
	if on then
		if not fade then
			local newFade = create("UIGradient", { Name = "Rainbow", Color = rainbowSequence(os.clock()), Parent = label })
			rainbowFades[newFade] = true
			runRainbow()
		end
		if label:IsA("TextLabel") or label:IsA("TextButton") then
			label.TextColor3 = Kit.Colors.White
		end
	elseif fade then
		fade:Destroy()
	end
end

-- Writes a label in the colour of a rarity. Give a bee's name or a rarity's name. A Rainbow
-- rarity (see GameConfig.Bees) is written in rainbow; the others in their own colour,
-- made paler by `lighten` (0 to 1).
function Kit.RarityText(label: TextLabel, name: string, lighten: number?)
	local rarity = GameConfig.RarityOf(name)
	if rarity and rarity.Rainbow then
		Kit.SetRainbow(label, true)
	else
		Kit.SetRainbow(label, false)
		if rarity then
			label.TextColor3 = Kit.Lighten(rarity.Color, lighten or 0)
		end
	end
end

-- The colour the Honey Market's price is written in: pale when poor, then yellow, then lime
-- when good. (From GameConfig.SellPriceHigh up it is written in rainbow instead.)
function Kit.PriceColor(price: number): Color3
	if price < 1.5 then
		return Kit.Colors.Cream
	elseif price < 2 then
		return Kit.Colors.Honey
	end
	return Kit.Colors.Lime
end

-- Writes a price on a label ("x2.4") in its colour, or in rainbow when it is a great price.
function Kit.PriceText(label: TextLabel, price: number)
	if price >= GameConfig.SellPriceHigh then
		Kit.SetRainbow(label, true)
	else
		Kit.SetRainbow(label, false)
		label.TextColor3 = Kit.PriceColor(price)
	end
end

-- For a label that shows a bee's NAME (white writing): rainbow if the bee's rarity is a
-- Rainbow one, plain white otherwise.
function Kit.BeeNameText(label: TextLabel, beeName: string?)
	local bee = if beeName then GameConfig.Bees[beeName] else nil
	if bee and bee.Rainbow then
		Kit.SetRainbow(label, true)
	elseif label:FindFirstChild("Rainbow") then
		Kit.SetRainbow(label, false)
		label.TextColor3 = Kit.Colors.White
	end
end

-- BUTTONS -----------------------------------------------------------------------------------

export type ButtonProps = {
	Parent: Instance?,
	Name: string?,
	Text: string?,
	TextSize: number?,
	Color: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	ZIndex: number?,
	Icon: ((Frame) -> ())?, -- draws a picture on the button
	Layout: string?, -- "Row" = picture on the left of the text (otherwise the picture sits above the text)
	Rim: boolean?, -- a thin pale line just inside the edge (the red X uses it)
	OnClick: (() -> ())?,
}

local BUTTON_RADIUS = 13
local BUTTON_LIP = 5

-- A chunky toy-brick button: dark outline, a lighter top half, a darker "lip" underneath, white
-- outlined text.
-- It squishes when pressed and bounces back.
function Kit.Button(props: ButtonProps)
	local color = props.Color or Kit.Colors.Green
	local zIndex = props.ZIndex or 1
	local enabled = true
	local lastClick = 0

	local holder = create("Frame", {
		Name = props.Name or "Button",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(160, 50),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = zIndex,
		Parent = props.Parent,
	})
	local animScale = create("UIScale", { Parent = holder })

	local lip = create("Frame", {
		Name = "Lip",
		BackgroundColor3 = Kit.Darken(color, 0.3),
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex,
		Parent = holder,
	})
	Kit.Corner(lip, BUTTON_RADIUS)
	Kit.Stroke(lip, 3)

	local face = create("TextButton", {
		Name = "Face",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Kit.Colors.White,
		Size = UDim2.new(1, 0, 1, -BUTTON_LIP),
		ZIndex = zIndex,
		Parent = holder,
	})
	Kit.Corner(face, BUTTON_RADIUS)
	Kit.Stroke(face, 3)
	local bands = Kit.Bands(face, color)

	if props.Rim then
		local rim = create("Frame", {
			Name = "Rim",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 1, -8),
			ZIndex = zIndex,
			Parent = face,
		})
		Kit.Corner(rim, BUTTON_RADIUS - 3)
		Kit.Stroke(rim, 2.5, Kit.Darken(color, 0.3))
	end

	local height = (if props.Size then props.Size.Y.Offset else 50) - BUTTON_LIP
	local label
	if props.Icon and props.Layout == "Row" then
		local iconSize = height - 8
		local iconArea = create("Frame", {
			Name = "Icon",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(iconSize, iconSize),
			ZIndex = zIndex,
			Parent = face,
		})
		props.Icon(iconArea)
		label = Kit.Label({
			Parent = face,
			Text = props.Text or "",
			TextSize = props.TextSize or 22,
			Position = UDim2.fromOffset(iconSize + 8, 0),
			Size = UDim2.new(1, -(iconSize + 16), 1, 0),
			Fit = true,
			ZIndex = zIndex,
		})
	elseif props.Icon then
		local iconArea = create("Frame", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 6, 0, 4),
			Size = UDim2.new(1, -12, 0.62, -4),
			ZIndex = zIndex,
			Parent = face,
		})
		props.Icon(iconArea)
		label = Kit.Label({
			Parent = face,
			Text = props.Text or "",
			TextSize = props.TextSize or 20,
			Size = UDim2.new(1, -8, 0.36, 0),
			Position = UDim2.new(0.5, 0, 1, -4),
			AnchorPoint = Vector2.new(0.5, 1),
			Fit = true,
			ZIndex = zIndex,
		})
	else
		label = Kit.Label({
			Parent = face,
			Text = props.Text or "",
			TextSize = props.TextSize or 24,
			Size = UDim2.new(1, -12, 1, -6),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Fit = true,
			ZIndex = zIndex,
		})
	end

	local function tweenScale(target: number, time: number, style: Enum.EasingStyle?)
		TweenService:Create(animScale, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = target }):Play()
	end

	face.MouseEnter:Connect(function()
		if enabled then
			tweenScale(1.06, 0.12)
		end
	end)
	face.MouseLeave:Connect(function()
		tweenScale(1, 0.12)
		face.Position = UDim2.new()
	end)
	face.MouseButton1Down:Connect(function()
		if enabled then
			face.Position = UDim2.fromOffset(0, BUTTON_LIP - 1)
			tweenScale(0.95, 0.06)
		end
	end)
	face.MouseButton1Up:Connect(function()
		face.Position = UDim2.new()
	end)
	face.Activated:Connect(function()
		face.Position = UDim2.new()
		if not enabled then
			return
		end
		local now = os.clock()
		if now - lastClick < 0.25 then
			return -- ignore double taps
		end
		lastClick = now
		Kit.PlaySound("Click")
		animScale.Scale = 0.9
		tweenScale(1, 0.3, Enum.EasingStyle.Back)
		if props.OnClick then
			props.OnClick()
		end
	end)

	local button = {}
	button.Holder = holder
	button.Face = face
	button.Label = label

	function button.SetText(text: string)
		label.Text = text
	end

	function button.SetColor(newColor: Color3)
		color = newColor
		if enabled then
			Kit.SetBands(bands, newColor)
			lip.BackgroundColor3 = Kit.Darken(newColor, 0.3)
		end
	end

	-- A disabled button turns grey and ignores presses.
	function button.SetEnabled(isEnabled: boolean)
		enabled = isEnabled
		local shown = if isEnabled then color else Kit.Colors.Grey
		Kit.SetBands(bands, shown)
		lip.BackgroundColor3 = Kit.Darken(shown, 0.3)
	end

	return button
end

-- A small red "!" bubble that pulses on the corner of a button.
function Kit.Badge(parent: Instance, size: number?): Frame
	local badgeSize = size or 30
	local badge = create("Frame", {
		Name = "Badge",
		BackgroundColor3 = Kit.Colors.Red,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(badgeSize, badgeSize),
		ZIndex = 6,
		Visible = false,
		Parent = parent,
	})
	Kit.Corner(badge, badgeSize / 2)
	Kit.Stroke(badge, 2.5, Kit.Colors.White)
	Kit.Label({ Parent = badge, Text = "!", TextSize = math.floor(badgeSize * 0.8), Stroke = 0, ZIndex = 6 })
	local pulse = create("UIScale", { Parent = badge })
	TweenService:Create(pulse, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.2 }):Play()
	return badge
end

-- True on phones and tablets (touch only, no mouse).
function Kit.IsTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- PANELS (pop-up windows) ---------------------------------------------------------------------

local openPanel = nil
local panelChanged = Instance.new("BindableEvent")
Kit.PanelChanged = panelChanged.Event -- fires (isAnyPanelOpen) when a window opens or closes

function Kit.IsAnyPanelOpen(): boolean
	return openPanel ~= nil
end

function Kit.CloseAll()
	if openPanel then
		openPanel.Close()
	end
end

export type PanelProps = {
	Parent: Instance,
	Name: string,
	Title: string,
	Size: Vector2,
	HeaderColor: Color3?, -- the colour of the title bar
	Icon: ((Frame) -> ())?, -- draws the little picture at the left of the title bar
	CoinReadout: boolean?, -- shows your coins in the title bar (panel.CoinText is the number)
}

local HEADER_HEIGHT = 76
local BODY_TOP = 62 -- the dark body starts this far down, tucked under the title bar
local BODY_INSET = 8 -- and is this much narrower than the title bar on each side

-- A window: a bright title bar (tilted picture, title, red X) on top of a dark see-through body.
-- Only one can be open at a time. The game keeps going behind it; the red X closes it.
-- panel.Content is the space for the window's own things: 44 narrower and 102 shorter than Size.
function Kit.Panel(props: PanelProps)
	local panel = {}
	local isOpen = false
	local headerColor = props.HeaderColor or Kit.Colors.Title

	local root = create("Frame", {
		Name = props.Name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(props.Size.X, props.Size.Y),
		Visible = false,
		Parent = props.Parent,
	})
	-- the extra room is for the picture and the close button, which stick out of the corners
	Kit.AutoScale(root, props.Size + Vector2.new(56, 20))

	local pop = create("Frame", {
		Name = "Pop",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	local popScale = create("UIScale", { Parent = pop })

	local body = create("Frame", {
		Name = "Body",
		BackgroundColor3 = Kit.Colors.Body,
		BackgroundTransparency = Kit.BodyTransparency,
		Position = UDim2.fromOffset(BODY_INSET, BODY_TOP),
		Size = UDim2.new(1, -BODY_INSET * 2, 1, -BODY_TOP),
		Active = true, -- stops clicks passing through to the game world
		Parent = pop,
	})
	Kit.Corner(body, 16)
	Kit.Stroke(body, 4)

	local header = create("Frame", {
		Name = "Header",
		BackgroundColor3 = Kit.Colors.White,
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		Active = true,
		Parent = pop,
	})
	Kit.Corner(header, 14)
	Kit.Stroke(header, 4)
	Kit.Bands(header, headerColor)

	local titleLeft = 24
	if props.Icon then
		-- a big picture hanging over the left end of the title bar
		local iconHolder = create("Frame", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(-18, -4),
			Size = UDim2.fromOffset(84, 84),
			Rotation = -9, -- a jaunty tilt
			ZIndex = 2,
			Parent = header,
		})
		props.Icon(iconHolder)
		titleLeft = 88
	end
	Kit.Label({
		Parent = header,
		Name = "Title",
		Text = props.Title,
		TextSize = 44,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(titleLeft, -2),
		Size = UDim2.new(1, -titleLeft - (if props.CoinReadout then 320 else 96), 1, 0),
		Stroke = 5,
		Fit = true,
	})

	-- your coins, in a dark pill beside the red X (the HUD counters hide while a window is open)
	if props.CoinReadout then
		local pill = create("Frame", {
			Name = "Coins",
			BackgroundColor3 = Kit.Colors.Outline,
			BackgroundTransparency = 0.5,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -108, 0.5, -1),
			Size = UDim2.fromOffset(190, 50),
			Parent = header,
		})
		Kit.Corner(pill, 12)
		Kit.Stroke(pill, 3)
		local coin = Kit.CoinIcon(pill, 36)
		coin.AnchorPoint = Vector2.new(0, 0.5)
		coin.Position = UDim2.new(0, 8, 0.5, 0)
		panel.CoinText = Kit.Label({
			Parent = pill,
			Name = "Amount",
			Text = "0",
			TextSize = 28,
			Color = Kit.Colors.Money,
			XAlign = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(54, 0),
			Size = UDim2.new(1, -62, 1, 0),
			Fit = true,
		})
	end

	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(22, 86),
		Size = UDim2.new(1, -44, 1, -102),
		Parent = pop,
	})

	function panel.Close()
		if not isOpen then
			return
		end
		isOpen = false
		if openPanel == panel then
			openPanel = nil
		end
		local tween = TweenService:Create(popScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.6 })
		tween:Play()
		tween.Completed:Once(function()
			if not isOpen then
				root.Visible = false
			end
		end)
		if panel.OnClose then
			panel.OnClose()
		end
		panelChanged:Fire(openPanel ~= nil)
	end

	function panel.Open()
		if isOpen then
			return
		end
		if openPanel then
			openPanel.Close()
		end
		openPanel = panel
		isOpen = true
		root.Visible = true
		popScale.Scale = 0.6
		TweenService:Create(popScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		Kit.PlaySound("Open")
		if panel.OnOpen then
			panel.OnOpen()
		end
		panelChanged:Fire(true)
	end

	function panel.Toggle()
		if isOpen then
			panel.Close()
		else
			panel.Open()
		end
	end

	function panel.IsOpen(): boolean
		return isOpen
	end

	-- the red X: a square that sits on the right end of the title bar
	Kit.Button({
		Parent = pop,
		Name = "Close",
		Text = "X",
		TextSize = 46,
		Color = Kit.Colors.Red,
		Size = UDim2.fromOffset(80, 80), -- big enough to tap easily on a phone
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 6, 0, -2),
		OnClick = panel.Close,
	})

	panel.Root = root
	panel.Header = header
	panel.Content = content
	panel.OnOpen = nil :: (() -> ())?
	panel.OnClose = nil :: (() -> ())?
	return panel
end

-- A darker box used to group things inside a window. With no colour it is see-through ink.
function Kit.Box(parent: Instance, position: UDim2, size: UDim2, color: Color3?, name: string?): Frame
	local box = create("Frame", {
		Name = name or "Box",
		BackgroundColor3 = color or Kit.Colors.Inner,
		BackgroundTransparency = if color then 0 else Kit.InnerTransparency,
		Position = position,
		Size = size,
		Parent = parent,
	})
	Kit.Corner(box, 14)
	Kit.Stroke(box, 3)
	return box
end

-- LITTLE 3D PICTURES -------------------------------------------------------------------------

local spinning: { [ViewportFrame]: { Center: Vector3, Distance: number, Direction: Vector3, Angle: number } } = {}
local DEFAULT_DIRECTION = Vector3.new(0.45, 0.3, -1).Unit

-- Shows a 3D model inside a square of UI. spin = true slowly turns the camera around it.
-- zoom below 1 moves the camera closer (bees have wide wings, so they use Kit.BEE_ZOOM).
function Kit.SetViewportModel(frame: ViewportFrame, model: Model?, spin: boolean?, zoom: number?)
	for _, child in frame:GetChildren() do
		if not child:IsA("Camera") then
			child:Destroy()
		end
	end
	spinning[frame] = nil
	if not model then
		return
	end

	model.Parent = frame
	local camera = frame.CurrentCamera :: Camera
	local boxCFrame, boxSize = model:GetBoundingBox()
	local radius = boxSize.Magnitude / 2
	local distance = radius / math.sin(math.rad(camera.FieldOfView / 2)) * (zoom or 1)
	local center = boxCFrame.Position
	camera.CFrame = CFrame.lookAt(center + DEFAULT_DIRECTION * distance, center)
	if spin then
		spinning[frame] = { Center = center, Distance = distance, Direction = DEFAULT_DIRECTION, Angle = 0 }
	end
end

function Kit.Viewport(props: { Parent: Instance?, Name: string?, Size: UDim2?, Position: UDim2?, AnchorPoint: Vector2?, ZIndex: number? }): ViewportFrame
	local frame = create("ViewportFrame", {
		Name = props.Name or "Picture",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 1,
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Kit.Colors.White,
		LightDirection = Vector3.new(0.3, -1, 1),
		Parent = props.Parent,
	})
	local camera = create("Camera", { FieldOfView = 30, Parent = frame })
	frame.CurrentCamera = camera
	return frame
end

RunService.RenderStepped:Connect(function(deltaTime)
	for frame, info in spinning do
		if not frame.Parent then
			spinning[frame] = nil
		else
			info.Angle += deltaTime * 1.2
			local direction = CFrame.Angles(0, info.Angle, 0):VectorToWorldSpace(info.Direction)
			local camera = frame.CurrentCamera
			if camera then
				camera.CFrame = CFrame.lookAt(info.Center + direction * info.Distance, info.Center)
			end
		end
	end
end)

-- A bee model for UI pictures (no sparkles: particles do not show inside UI pictures).
function Kit.BeeModel(rarityName: string, crown: boolean?): Model
	local rarity = GameConfig.Bees[rarityName]
	return BeeModelFactory.Create(rarity.Color, { Crown = crown })
end

-- A beehive model (for the given hive level) for UI pictures.
function Kit.HiveModel(level: number): Model
	local model = HiveModelFactory.Create(level)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("PointLight") then
			descendant:Destroy()
		end
	end
	return model
end

-- PICTURES (drawings of our own 3D models; the picture numbers are in BeeEmpire.UIImages) ---------

-- Each picture has a little empty edge round it, so it is drawn slightly bigger than its box.
local PICTURE_GROW = 1.14

local function picture(parent: Instance, name: string, size: number, image: string): Frame
	local holder = create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	create("ImageLabel", {
		Name = "Picture",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(PICTURE_GROW, PICTURE_GROW),
		Image = image,
		ScaleType = Enum.ScaleType.Fit,
		Parent = holder,
	})
	return holder
end

function Kit.CoinIcon(parent: Instance, size: number): Frame
	return picture(parent, "CoinIcon", size, UIImages.Coin)
end

function Kit.JarIcon(parent: Instance, size: number): Frame
	return picture(parent, "JarIcon", size, UIImages.Jar)
end

-- A bee. Say which kind ("Common", "Rare"...) or give its colour; no choice = the first kind.
function Kit.BeeIcon(parent: Instance, size: number, which: (string | Color3)?): Frame
	local rarityName = GameConfig.BeeOrder[1]
	if typeof(which) == "string" then
		rarityName = which
	elseif typeof(which) == "Color3" then
		for name, rarity in GameConfig.Bees do
			if rarity.Color == which then
				rarityName = name
				break
			end
		end
	end
	return picture(parent, "BeeIcon", size, UIImages.Bee(rarityName))
end

-- A beehive. A higher hive level shows the bigger, fancier hive.
function Kit.HiveIcon(parent: Instance, size: number, level: number?): Frame
	return picture(parent, "HiveIcon", size, UIImages.Hive(level or 1))
end

-- A green "up" arrow (the Upgrade Shop's picture). It sits in the middle of its parent.
function Kit.ArrowIcon(parent: Instance, size: number): Frame
	local arrow = picture(parent, "ArrowIcon", size, UIImages.Arrow)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromScale(0.5, 0.5)
	return arrow
end

-- A lucky four-leaf clover (the Queen's Luck upgrade).
function Kit.CloverIcon(parent: Instance, size: number): Frame
	return picture(parent, "CloverIcon", size, UIImages.Clover)
end

-- A bee with speed lines (the Bee Speed upgrade).
function Kit.SpeedIcon(parent: Instance, size: number): Frame
	return picture(parent, "SpeedIcon", size, UIImages.SpeedBee)
end

-- A mystery egg (the More Rolls upgrade).
function Kit.EggIcon(parent: Instance, size: number): Frame
	return picture(parent, "EggIcon", size, UIImages.Egg)
end

-- The mystery egg with speed lines (the Roll Speed upgrade).
function Kit.FastEggIcon(parent: Instance, size: number): Frame
	return picture(parent, "FastEggIcon", size, UIImages.FastEgg)
end

-- A bee-striped sneaker with a wing: the Walk Speed upgrade.
function Kit.WalkSpeedIcon(parent: Instance, size: number): Frame
	return picture(parent, "WalkSpeedIcon", size, UIImages.WalkSpeed)
end

-- A cog wheel (the Settings button and window).
function Kit.GearIcon(parent: Instance, size: number): Frame
	return picture(parent, "GearIcon", size, UIImages.Gear)
end

-- A pair of music notes (the Music slider).
function Kit.MusicIcon(parent: Instance, size: number): Frame
	return picture(parent, "MusicIcon", size, UIImages.Music)
end

-- A loudspeaker (the Sounds slider).
function Kit.SpeakerIcon(parent: Instance, size: number): Frame
	return picture(parent, "SpeakerIcon", size, UIImages.Speaker)
end

-- A gold padlock (shown on hive spots that are still locked).
function Kit.LockIcon(parent: Instance, size: number): Frame
	return picture(parent, "LockIcon", size, UIImages.Lock)
end

-- A calendar with a tick (the Daily Rewards button and window).
function Kit.CalendarIcon(parent: Instance, size: number): Frame
	return picture(parent, "CalendarIcon", size, UIImages.Calendar)
end

-- A honey-coloured backpack (the Inventory button and window).
function Kit.BackpackIcon(parent: Instance, size: number): Frame
	return picture(parent, "BackpackIcon", size, UIImages.Backpack)
end

-- The Halloween Egg (a limited-time event).
function Kit.HalloweenEggIcon(parent: Instance, size: number): Frame
	return picture(parent, "HalloweenEggIcon", size, UIImages.HalloweenEgg)
end

-- A market stall with a striped roof (the Shop button and window).
function Kit.ShopIcon(parent: Instance, size: number): Frame
	return picture(parent, "ShopIcon", size, UIImages.Shop)
end

-- A pass's picture. passName is a name from GameConfig.Passes ("AutoSell", "VIP"...).
function Kit.PassIcon(parent: Instance, size: number, passName: string): Frame
	return picture(parent, "PassIcon", size, UIImages.Pass(passName))
end

-- A boost's picture: the honey jar (Double Honey) or the clover (Double Luck), with its
-- "x2" written on the corner. kind is "Honey" or "Luck" (GameConfig.Boosts).
function Kit.BoostIcon(parent: Instance, size: number, kind: string): Frame
	local holder = if kind == "Luck" then Kit.CloverIcon(parent, size) else Kit.JarIcon(parent, size)
	holder.Name = "BoostIcon"
	local boost = GameConfig.Boosts[kind]
	Kit.Label({
		Parent = holder,
		Name = "Times",
		Text = "x" .. string.format("%g", if boost then boost.Multiplier else 2),
		TextSize = math.max(12, math.floor(size * 0.46)),
		Color = Kit.Colors.Select,
		XAlign = Enum.TextXAlignment.Right,
		-- (on the UPPER right corner: the lower right is where a card writes "10 min")
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, math.floor(size * 0.16), 0, -math.floor(size * 0.04)),
		Size = UDim2.fromScale(0.8, 0.5),
		Fit = true,
		ZIndex = 2,
	})
	return holder
end

-- BEE CARDS -----------------------------------------------------------------------------------

export type CardProps = {
	Parent: Instance?,
	Name: string?,
	RarityName: string?,
	Size: Vector2?,
	Count: number?,
	Compact: boolean?, -- small card: just the bee picture and its speed
	LockedText: string?, -- shows a locked slot with this text (e.g. "Lv 3")
	EmptyText: string?,
	LayoutOrder: number?,
	OnClick: (() -> ())?,
}

local CARD_RADIUS = 12
local CARD_OUTLINE = 3.5

-- A card showing one kind of bee, an empty slot (RarityName = nil) or a locked slot (LockedText).
-- With Count it is a bag card: the bee's name on top and "x3" in the corner.
function Kit.BeeCard(props: CardProps)
	local size = props.Size or Vector2.new(112, 132)
	local card = {}
	local selected = false
	local glowTween: Tween? = nil
	local restColor = Kit.Colors.Outline -- the outline colour when nothing special is going on
	local outlineScale = strokeScale() -- outlines are thinner on small screens

	local button = create("TextButton", {
		Name = props.Name or (if props.RarityName then "Card_" .. props.RarityName else "Card_Empty"),
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Kit.Colors.White,
		Size = UDim2.fromOffset(size.X, size.Y),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	Kit.Corner(button, CARD_RADIUS)
	local outline = Kit.Stroke(button, CARD_OUTLINE)
	local animScale = create("UIScale", { Parent = button })

	if props.RarityName then
		local rarity = GameConfig.Bees[props.RarityName]
		Kit.Gradient(button, Kit.RarityFade(props.RarityName))

		local hasName = props.Count ~= nil or not props.Compact
		local beeSize = math.floor(math.min(size.X * 0.62, size.Y * 0.56))
		local bee = Kit.BeeIcon(button, beeSize, rarity.Color)
		bee.AnchorPoint = Vector2.new(0.5, 0.5)
		bee.Position = UDim2.fromScale(0.5, if props.Count then 0.54 elseif hasName then 0.46 else 0.4)

		if hasName then
			local nameLabel = Kit.Label({
				Parent = button,
				Name = "BeeName",
				Text = rarity.BeeName,
				TextSize = if props.Compact then 15 else 18,
				Position = UDim2.fromOffset(4, 3),
				Size = UDim2.new(1, -8, 0, if props.Compact then 19 else 22),
				Fit = true,
			})
			Kit.BeeNameText(nameLabel, props.RarityName) -- the best bees' names are rainbow
		end
		if props.Count then
			-- a bag card: how many of this bee you have, bottom right
			Kit.Label({
				Parent = button,
				Name = "Count",
				Text = "x" .. props.Count,
				TextSize = 23,
				XAlign = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -6, 1, -3),
				Size = UDim2.new(0.7, 0, 0, 26),
				ZIndex = 3,
				Fit = true,
			})
		elseif props.Compact then
			Kit.Label({
				Parent = button,
				Name = "Rate",
				Text = string.format("%g/s", rarity.NectarPerSecond),
				TextSize = 19,
				Position = UDim2.new(0, 4, 1, -28),
				Size = UDim2.new(1, -8, 0, 24),
				Stroke = 3,
				Fit = true,
			})
		else
			Kit.Label({
				Parent = button,
				Name = "Rarity",
				Text = rarity.DisplayName .. "  " .. string.format("%g/s", rarity.NectarPerSecond),
				TextSize = 18,
				Position = UDim2.new(0, 6, 1, -27),
				Size = UDim2.new(1, -12, 0, 23),
				Fit = true,
			})
		end
	elseif props.LockedText then
		-- a locked spot: a gold padlock and the hive level that unlocks it
		button.BackgroundColor3 = Kit.Colors.Outline
		button.BackgroundTransparency = 0.3
		local lockSize = math.floor(math.min(size.X, size.Y) * 0.5)
		local lock = Kit.LockIcon(button, lockSize)
		lock.AnchorPoint = Vector2.new(0.5, 0.5)
		lock.Position = UDim2.fromScale(0.5, 0.4)
		Kit.Label({
			Parent = button,
			Text = props.LockedText,
			TextSize = 19,
			Position = UDim2.new(0, 4, 1, -28),
			Size = UDim2.new(1, -8, 0, 24),
			Stroke = 3,
			Fit = true,
		})
	else
		button.BackgroundColor3 = Kit.Colors.Outline
		button.BackgroundTransparency = 0.6
		Kit.Label({
			Parent = button,
			Text = "+",
			TextSize = if props.Compact then 44 else 54,
			Color = Kit.Colors.Money,
			Size = UDim2.new(1, 0, 1, -26),
			Stroke = 3.5,
		})
		Kit.Label({
			Parent = button,
			Text = props.EmptyText or "Empty",
			TextSize = if props.Compact then 18 else 19,
			Color = Kit.Colors.Money,
			Position = UDim2.new(0, 4, 1, -28),
			Size = UDim2.new(1, -8, 0, 24),
			Stroke = 3,
			Fit = true,
		})
	end

	-- a dark cover used to show "you can't put the picked bee here"
	local cover = create("Frame", {
		Name = "Cover",
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.5,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Visible = false,
		Parent = button,
	})
	Kit.Corner(cover, CARD_RADIUS)

	local function restingScale(): number
		return if selected then 1.08 else 1
	end

	button.MouseEnter:Connect(function()
		TweenService:Create(animScale, TweenInfo.new(0.12), { Scale = restingScale() + 0.04 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(animScale, TweenInfo.new(0.12), { Scale = restingScale() }):Play()
	end)
	button.Activated:Connect(function()
		Kit.PlaySound("Click")
		animScale.Scale = restingScale() - 0.1
		TweenService:Create(animScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = restingScale() }):Play()
		if props.OnClick then
			props.OnClick()
		end
	end)

	-- picked: lifts up with a thick yellow outline
	function card.SetSelected(isSelected: boolean)
		selected = isSelected
		if glowTween then
			glowTween:Cancel()
			glowTween = nil
		end
		outline.Color = if isSelected then Kit.Colors.Select else restColor
		outline.Thickness = (if isSelected then 5.5 else CARD_OUTLINE) * outlineScale
		TweenService:Create(animScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = restingScale() }):Play()
	end

	-- a pulsing coloured outline (e.g. green = "you can put the bee here"), or nil to turn it off
	function card.SetGlow(color: Color3?)
		if glowTween then
			glowTween:Cancel()
			glowTween = nil
		end
		if color then
			outline.Color = color
			outline.Thickness = CARD_OUTLINE * outlineScale
			glowTween = TweenService:Create(outline, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 6.5 * outlineScale })
			glowTween:Play()
		elseif not selected then
			outline.Color = restColor
			outline.Thickness = CARD_OUTLINE * outlineScale
		end
	end

	function card.SetCovered(isCovered: boolean)
		cover.Visible = isCovered
	end

	card.Button = button
	return card
end

return Kit
