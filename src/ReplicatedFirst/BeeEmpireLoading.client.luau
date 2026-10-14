--[[
	BeeEmpireLoading - the loading screen.

	This is the first thing that runs on a player's device. That is why it lives in
	ReplicatedFirst, and why it cannot use the game's other scripts (UIKit, GameConfig...):
	they have not arrived yet when it starts. It covers the screen with our own picture,
	fetches the game's pictures and models, waits for the player's save, and then fades away.

	It never keeps anybody waiting long:
	  - it goes the moment everything is ready (but not before SHORTEST seconds, so it does
	    not flash by),
	  - after LONGEST seconds it goes anyway, whatever has loaded,
	  - and the Skip button closes it at once.

	While it shows, the player has the attribute LoadingScreen = true. The rest of the game
	waits for that before it pops a window up (see State.LoadingScreenUp).

	Nothing here matters to the server: it only shows things.
]]

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- HOW LONG ------------------------------------------------------------------------------------
local LONGEST = 8 -- seconds: after this the player is let in, whatever has loaded
local SHORTEST = 2.5 -- seconds: it never flashes by faster than this
local FADE = 0.45 -- seconds the fade-out takes

-- THE PICTURE (our own: drawn with blender/thumbnails.py, mode "loading") ------------------------
-- It is extra wide, the shape of a phone held sideways. A wide phone shows all of it; a
-- desktop or a tablet shows the middle and loses a little at the sides.
-- Roblox shrinks any picture to 1024 across, so it is kept as three strips, side by side,
-- that overlap a little. Together they are PICTURE_SIZE.
local PICTURE_SIZE = Vector2.new(2400, 1080)
local STRIPS = { -- the picture's number, where the strip starts from the left, how wide it is
	{ Image = "rbxassetid://123164186142235", Start = 0, Width = 816 },
	{ Image = "rbxassetid://135286502631323", Start = 792, Width = 816 },
	{ Image = "rbxassetid://134975888801582", Start = 1584, Width = 816 },
}
-- Where the honeycomb sign is in the picture (printed by the Blender script): its middle,
-- from the left and from the top, and how far it leans.
local SIGN = { Across = 0.4392, Down = 0.4625, Lean = -9 }

local TIPS = {
	"Sell your honey when the price is high!",
	"Roll at the Queen Bee for free, then buy the bee you like.",
	"A bigger hive holds more bees.",
	"Your bees keep making honey while you are away.",
	"Come back every day for a Daily Reward.",
	"Queen's Luck makes rare bees show up more often.",
}

local FONT = Enum.Font.FredokaOne
local INK = Color3.fromRGB(20, 16, 26) -- the dark outline (UIKit's Outline)
local WHITE = Color3.fromRGB(255, 255, 255)
local SKY_TOP = Color3.fromRGB(46, 144, 250)
local SKY_BOTTOM = Color3.fromRGB(160, 228, 255)
local BLUE = Color3.fromRGB(58, 157, 240) -- the Skip button (UIKit's Blue)
local BLUE_TOP = Color3.fromRGB(116, 198, 255)

local player = Players.LocalPlayer
local started = os.clock()
player:SetAttribute("LoadingScreen", true)

local function create(className: string, props: { [string]: any }): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	instance.Parent = props.Parent
	return instance
end

-- THE SCREEN ------------------------------------------------------------------------------------

local playerGui = player:WaitForChild("PlayerGui")

-- the picture covers everything, right into the corners of a phone
local gui = create("ScreenGui", {
	Name = "BeeEmpireLoading",
	IgnoreGuiInset = true,
	ScreenInsets = Enum.ScreenInsets.None,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 1000,
})
local root = create("CanvasGroup", {
	Name = "Root",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = SKY_BOTTOM,
	BorderSizePixel = 0,
	Active = true, -- nothing under the picture can be clicked
	Parent = gui,
})
-- a plain sky, seen for a moment before the picture has arrived
-- (the fade must sit on its own frame: on the group itself it would tint the whole picture)
local sky = create("Frame", { Name = "Sky", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 0, Parent = root })
create("UIGradient", { Rotation = 90, Color = ColorSequence.new(SKY_TOP, SKY_BOTTOM), Parent = sky })

local picture = create("Frame", {
	Name = "Picture",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.3),
	Position = UDim2.fromScale(0.5, 0.3),
	Size = UDim2.fromOffset(PICTURE_SIZE.X, PICTURE_SIZE.Y),
	Parent = root,
})
local strips: { ImageLabel } = {}
for index, strip in STRIPS do
	strips[index] = create("ImageLabel", {
		Name = "Strip" .. index,
		BackgroundTransparency = 1,
		Image = strip.Image,
		Position = UDim2.fromScale(strip.Start / PICTURE_SIZE.X, 0),
		Size = UDim2.fromScale(strip.Width / PICTURE_SIZE.X, 1),
		ZIndex = 1 + #STRIPS - index, -- each strip lies over the edge of the one to its right
		Parent = picture,
	})
end

-- The game's name, written across the honeycomb sign. (Writing, not part of the picture, so
-- it is sharp on every screen.) Each line has a dark copy just below it, like a shadow.
local titleStrokes: { UIStroke } = {}
local function titleLine(text: string, up: number, wide: number, tall: number, top: Color3, bottom: Color3)
	-- `up`: how far above the sign's middle the line sits; `wide` and `tall`: the line's box.
	-- All three are parts of the picture's HEIGHT.
	local lean = math.rad(SIGN.Lean)
	local shape = PICTURE_SIZE.Y / PICTURE_SIZE.X
	local across = SIGN.Across + up * math.sin(lean) * shape
	local down = SIGN.Down - up * math.cos(lean)
	for layer = 1, 2 do
		local shadow = layer == 1
		local label = create("TextLabel", {
			Name = if shadow then "Shadow" else "Title",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(across, down + (if shadow then tall * 0.09 else 0)),
			Size = UDim2.fromScale(wide * shape, tall),
			Rotation = SIGN.Lean,
			Font = FONT,
			Text = text,
			TextScaled = true,
			TextColor3 = if shadow then INK else WHITE,
			ZIndex = if shadow then 8 else 9,
			Parent = picture,
		})
		if not shadow then
			create("UIGradient", { Rotation = 90, Color = ColorSequence.new(top, bottom), Parent = label })
		end
		table.insert(titleStrokes, create("UIStroke", {
			Color = INK,
			Thickness = 8,
			LineJoinMode = Enum.LineJoinMode.Round,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			Parent = label,
		}))
	end
end
titleLine("Build A", 0.062, 0.356, 0.105, WHITE, Color3.fromRGB(236, 240, 255))
titleLine("Bee Empire", -0.07, 0.836, 0.17, Color3.fromRGB(255, 226, 70), Color3.fromRGB(255, 150, 16))

-- the words and the Skip button stay clear of a phone's rounded corners and its notch
local controls = create("ScreenGui", {
	Name = "BeeEmpireLoadingControls",
	IgnoreGuiInset = true,
	ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 1001,
})
local controlsRoot = create("CanvasGroup", {
	Name = "Root",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = controls,
})

local strokes: { { Stroke: UIStroke, Thickness: number } } = {}
local function outline(parent: Instance, thickness: number)
	local stroke = create("UIStroke", {
		Color = INK,
		Thickness = thickness,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = if parent:IsA("TextLabel") then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
	table.insert(strokes, { Stroke = stroke, Thickness = thickness })
end

-- "Loading (96%)" and a tip, in the middle of the bottom edge
local BOTTOM_WIDTH = 700
local bottom = create("Frame", {
	Name = "Bottom",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.fromOffset(BOTTOM_WIDTH, 90),
	Parent = controlsRoot,
})
local bottomScale = create("UIScale", { Parent = bottom })

local loadingText = create("TextLabel", {
	Name = "Loading",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 48),
	Font = FONT,
	Text = "Loading (0%)",
	TextSize = 42,
	TextColor3 = WHITE,
	Parent = bottom,
})
outline(loadingText, 4.5)

local tip = create("TextLabel", {
	Name = "Tip",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 52),
	Size = UDim2.new(1, 0, 0, 34),
	Font = FONT,
	Text = "Tip: " .. TIPS[Random.new():NextInteger(1, #TIPS)],
	TextSize = 24,
	TextColor3 = Color3.fromRGB(255, 240, 190),
	TextWrapped = true,
	Parent = bottom,
})
outline(tip, 3)

-- the Skip button, in the bottom right corner (the same chunky look as the game's buttons)
local skipPressed = false
local skip = create("Frame", {
	Name = "Skip",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -18, 1, -18),
	Size = UDim2.fromOffset(150, 56),
	Parent = controlsRoot,
})
local skipScale = create("UIScale", { Parent = skip })
local lip = create("Frame", { Name = "Lip", BackgroundColor3 = BLUE:Lerp(Color3.new(0, 0, 0), 0.3), Size = UDim2.fromScale(1, 1), Parent = skip })
create("UICorner", { CornerRadius = UDim.new(0, 13), Parent = lip })
outline(lip, 3)
local face = create("TextButton", {
	Name = "Face",
	Text = "",
	AutoButtonColor = false,
	BackgroundColor3 = WHITE,
	Size = UDim2.new(1, 0, 1, -5),
	Parent = skip,
})
create("UICorner", { CornerRadius = UDim.new(0, 13), Parent = face })
outline(face, 3)
create("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, BLUE_TOP), ColorSequenceKeypoint.new(0.5, BLUE_TOP),
		ColorSequenceKeypoint.new(0.501, BLUE), ColorSequenceKeypoint.new(1, BLUE),
	}),
	Parent = face,
})
local skipText = create("TextLabel", {
	Name = "Label",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Font = FONT,
	Text = "Skip",
	TextSize = 28,
	TextColor3 = WHITE,
	Parent = face,
})
outline(skipText, 3.5)
face.Activated:Connect(function()
	skipPressed = true
end)

-- Fits everything to the screen: the picture always covers it (its sides are cut off on a
-- screen that is less wide), the words shrink on small screens but stay readable on a phone.
local function fit()
	local view = root.AbsoluteSize
	if view.X < 1 or view.Y < 1 then
		return
	end
	local grow = math.max(view.X / PICTURE_SIZE.X, view.Y / PICTURE_SIZE.Y)
	picture.Size = UDim2.fromOffset(math.ceil(PICTURE_SIZE.X * grow), math.ceil(PICTURE_SIZE.Y * grow))
	for _, stroke in titleStrokes do
		stroke.Thickness = math.max(2, PICTURE_SIZE.Y * grow * 0.0095)
	end
	local phone = (UserInputService.TouchEnabled and not UserInputService.MouseEnabled) or view.Y < 520
	local scale = if phone
		then math.clamp(math.min(view.X / 1040, view.Y / 580), 0.7, 1.25)
		else math.clamp(math.min(view.X / 1280, view.Y / 720), 0.55, 1.5)
	bottomScale.Scale = math.min(scale, (view.X - 24) / BOTTOM_WIDTH) -- the words never run off a narrow screen
	skipScale.Scale = scale
	for _, entry in strokes do
		entry.Stroke.Thickness = entry.Thickness * math.clamp(scale, 0.6, 1.25)
	end
end
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

gui.Parent = playerGui
controls.Parent = playerGui
fit()
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- WHILE IT SHOWS: no walking about, no pressing things, none of Roblox's own buttons ---------------

local BLOCK = "BeeEmpireLoadingBlock"
ContextActionService:BindActionAtPriority(BLOCK, function()
	return Enum.ContextActionResult.Sink
end, false, 5000, table.unpack(Enum.PlayerActions:GetEnumItems()))
local touchWasOn = GuiService.TouchControlsEnabled
GuiService.TouchControlsEnabled = false
local promptsWereOn = ProximityPromptService.Enabled
ProximityPromptService.Enabled = false
local coreWasOn: { [Enum.CoreGuiType]: boolean } = {}
for _, kind in Enum.CoreGuiType:GetEnumItems() do
	if kind ~= Enum.CoreGuiType.All then
		pcall(function()
			coreWasOn[kind] = StarterGui:GetCoreGuiEnabled(kind)
			StarterGui:SetCoreGuiEnabled(kind, false)
		end)
	end
end

-- Puts everything back and takes the screen away. Safe to call twice.
local gone = false
local function giveBack()
	if gone then
		return
	end
	gone = true
	ContextActionService:UnbindAction(BLOCK)
	GuiService.TouchControlsEnabled = touchWasOn
	ProximityPromptService.Enabled = promptsWereOn
	for kind, wasOn in coreWasOn do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(kind, wasOn)
		end)
	end
	player:SetAttribute("LoadingScreen", false)
end
local function remove()
	giveBack()
	gui:Destroy()
	controls:Destroy()
end
-- The safety net: whatever goes wrong below, the screen is gone a little after LONGEST.
task.delay(LONGEST + 2.5, remove)

-- WHAT IT WAITS FOR --------------------------------------------------------------------------

local ready = { Pictures = false, Game = false, Save = false, Character = false }
local assets = 0 -- 0 to 1: how much of the game's pictures and models has been fetched

task.spawn(function() -- this screen's own picture
	pcall(function()
		ContentProvider:PreloadAsync(strips)
	end)
	ready.Pictures = true
end)

task.spawn(function() -- the game itself, then its menu pictures and its bee and hive models
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	ready.Game = true
	local list: { any } = {}
	local shared = ReplicatedStorage:WaitForChild("BeeEmpire", 6)
	if shared then
		pcall(function()
			for _, image in require(shared:WaitForChild("UIImages", 3)).All() do
				table.insert(list, image)
			end
			table.insert(list, require(shared:WaitForChild("Studs", 3)).Texture)
		end)
		for _, name in { "BeeMeshes", "HiveMeshes" } do
			local folder = shared:FindFirstChild(name)
			if folder then
				for _, piece in folder:GetChildren() do
					table.insert(list, piece)
				end
			end
		end
	end
	local fetched = 0
	pcall(function()
		ContentProvider:PreloadAsync(list, function()
			fetched += 1
			assets = math.min(1, fetched / math.max(1, #list))
		end)
	end)
	assets = 1
end)

task.spawn(function() -- the player's save (the server says when it has arrived)
	while player:GetAttribute("DataLoaded") ~= true do
		player:GetAttributeChangedSignal("DataLoaded"):Wait()
	end
	ready.Save = true
end)

task.spawn(function() -- the player's character, standing in the world
	local character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart", 6)
	ready.Character = true
end)

local function loaded(): number
	return (if ready.Pictures then 0.12 else 0) + (if ready.Game then 0.13 else 0) + assets * 0.45
		+ (if ready.Save then 0.18 else 0) + (if ready.Character then 0.12 else 0)
end

-- THE LOOP: move the number, and decide when to go ---------------------------------------------

local shown = 0
local closing = false

local function close(showFull: boolean)
	closing = true
	if showFull then
		shown = 1
		task.wait(0.25) -- let "100%" be seen
	end
	giveBack()
	local fade = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(controlsRoot, fade, { GroupTransparency = 1 }):Play()
	local tween = TweenService:Create(root, fade, { GroupTransparency = 1 })
	tween:Play()
	tween.Completed:Wait()
	remove()
end

local connection: RBXScriptConnection
connection = RunService.RenderStepped:Connect(function(dt)
	if not gui.Parent then
		connection:Disconnect()
		return
	end
	local goal = if closing then shown else loaded()
	shown = math.max(shown, shown + (goal - shown) * (1 - math.exp(-dt * 7)))
	loadingText.Text = "Loading (" .. math.clamp(math.floor(shown * 100 + 0.5), 0, 100) .. "%)"
end)

local ok, problem = pcall(function()
	while true do
		local elapsed = os.clock() - started
		if skipPressed then
			close(false)
			break
		elseif loaded() >= 0.999 and elapsed >= SHORTEST and shown >= 0.97 then
			close(true)
			break
		elseif elapsed >= LONGEST then
			close(false)
			break
		end
		task.wait()
	end
end)
if not ok then
	warn("BeeEmpireLoading: " .. tostring(problem))
	remove()
end
