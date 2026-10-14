--[[
	WorldFX - visual touches in the 3D world that run on the player's own device.
	Nothing here can change coins, jars or bees; it only changes what you SEE.

	1. Your own hive glows gold and says "Your Hive!". Other hives hide their buttons and signs.
	2. Dark toy-style "press E / tap" buttons (they also work by tapping them).
	3. Opens the My Hive window / the Upgrades window when you use their buttons.
	4. The roll show on every honeycomb stand you own: a mystery egg, a black shadow, then the
	   bee with its name, rarity and price. A bee you buy flies off the stand to your hive.
	5. Bees fly from their hive to a flower in the garden, pollinate it, and fly home with
	   pollen. Worker bees then carry the honey from the hive to your Honey Jars, and a "+N"
	   pops up there. (The server decides when honey really arrives; this just shows it.)
	   A player may hide the other players' flying bees in Settings: they are then not moved
	   or drawn on that player's screen.
	6. The Queens gently bob up and down.
	7. An arrow points at what to do next, and a screen-edge arrow when it is off screen.
	8. The price pills on your own upgrade board and Auto Roll sign are green when you can
	   afford them.
	9. Worker bees carry honey to the jars, and anyone carrying jars holds their arms up.
	10. The flowers in the Flower Garden sway gently, as if in a breeze.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("BeeEmpire")
local GameConfig = require(sharedFolder:WaitForChild("GameConfig"))
local BeeModelFactory = require(sharedFolder:WaitForChild("BeeModelFactory"))
local NumberFormat = require(sharedFolder:WaitForChild("NumberFormat"))
local Kit = require(script.Parent.UIKit)
local State = require(script.Parent.State)
local Effects = require(script.Parent.Effects)

local WorldFX = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local plotsFolder = workspace:WaitForChild("Plots")

local GOLD = Color3.fromRGB(255, 205, 50)
local WHITE = Color3.fromRGB(255, 255, 255)

-- 1. MY HIVE vs OTHER HIVES ---------------------------------------------------------

local myHighlight: Highlight? = nil

local function isMine(plot: Instance): boolean
	return plot:GetAttribute("OwnerUserId") == player.UserId
end

local function myPlot(): Instance?
	for _, plot in plotsFolder:GetChildren() do
		if isMine(plot) then
			return plot
		end
	end
	return nil
end

local function ownerLabel(plot: Instance): TextLabel?
	local sign = plot:FindFirstChild("OwnerSign")
	local board = sign and sign:FindFirstChild("Sign")
	local tag = board and board:FindFirstChild("NameTag")
	local label = tag and tag:FindFirstChild("Label")
	return if label and label:IsA("TextLabel") then label else nil
end

-- "Buy Bee" buttons on the honeycomb stands only work once a bee has hatched there.
-- (Section 4 keeps this list up to date. The server checks it all again anyway.)
local buyReady: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function promptAllowed(prompt: ProximityPrompt, mine: boolean): boolean
	if prompt:GetAttribute("Action") == "BuyBee" then
		return mine and buyReady[prompt] == true
	end
	return mine
end

local function refreshPlot(plot: Instance)
	local mine = isMine(plot)
	for _, descendant in plot:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = promptAllowed(descendant, mine)
			descendant.Style = Enum.ProximityPromptStyle.Custom
		elseif descendant:IsA("BillboardGui") and descendant.Name == "Info" then
			-- station and market signs only show on your own hive
			descendant.Enabled = mine
		end
	end

	local label = ownerLabel(plot)
	if label then
		if mine then
			label.Text = "Your Hive!"
			label.TextColor3 = GOLD
		else
			label.TextColor3 = WHITE
		end
	end

	if mine then
		if myHighlight then
			myHighlight:Destroy()
		end
		myHighlight = Kit.Create("Highlight", {
			Name = "MyHiveGlow",
			Adornee = plot:FindFirstChild("Rim"),
			FillTransparency = 1,
			OutlineColor = GOLD,
			OutlineTransparency = 0,
			DepthMode = Enum.HighlightDepthMode.Occluded,
			Parent = playerGui,
		})
	end
end

local function watchPlot(plot: Instance)
	refreshPlot(plot)
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		refreshPlot(plot)
	end)

	-- The server rewrites the owner's name on the sign; put "Your Hive!" back.
	-- (Parts of a plot can arrive a moment after the plot itself, so keep looking for the sign.)
	local signHooked = false
	local function hookSign()
		local label = ownerLabel(plot)
		if label and not signHooked then
			signHooked = true
			label:GetPropertyChangedSignal("Text"):Connect(function()
				if isMine(plot) and label.Text ~= "Your Hive!" then
					label.Text = "Your Hive!"
				end
			end)
			refreshPlot(plot)
		end
	end
	hookSign()

	plot.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = promptAllowed(descendant, isMine(plot))
			descendant.Style = Enum.ProximityPromptStyle.Custom
		elseif descendant:IsA("BillboardGui") and descendant.Name == "Info" then
			descendant.Enabled = isMine(plot)
		elseif not signHooked and descendant:IsA("TextLabel") then
			hookSign()
		end
	end)
end

-- 2. HONEY-STYLE PROMPTS -----------------------------------------------------------

local promptGuis: { [ProximityPrompt]: BillboardGui } = {}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	if inputType == Enum.ProximityPromptInputType.Touch or touchOnly then
		return "TAP"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return (string.gsub(prompt.GamepadKeyCode.Name, "Button", ""))
	end
	return prompt.KeyboardKeyCode.Name
end

local function showPrompt(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
		return
	end
	local old = promptGuis[prompt]
	if old then
		old:Destroy()
	end

	local scale = Kit.ScreenScale()
	local billboard = Kit.Create("BillboardGui", {
		Name = "BeePrompt",
		AlwaysOnTop = true,
		Active = true,
		ResetOnSpawn = false,
		LightInfluence = 0,
		Size = UDim2.fromOffset(338 * scale, 92 * scale),
		StudsOffsetWorldSpace = Vector3.new(0, 3, 0),
		Adornee = prompt.Parent,
		Parent = playerGui,
	})
	promptGuis[prompt] = billboard

	local button = Kit.Create("TextButton", {
		Name = "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Kit.Colors.Outline,
		BackgroundTransparency = 0.18,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(330, 84),
		Parent = billboard,
	})
	Kit.Create("UIScale", { Scale = scale, Parent = button })
	local pop = Kit.Create("UIScale", { Name = "Pop", Scale = 1, Parent = billboard })
	Kit.Corner(button, 16)
	Kit.Stroke(button, 3.5)

	local key = Kit.Create("Frame", {
		Name = "Key",
		BackgroundColor3 = Kit.Colors.White,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 13, 0.5, 0),
		Size = UDim2.fromOffset(58, 58),
		Parent = button,
	})
	Kit.Corner(key, 11)
	Kit.Stroke(key, 3, Color3.fromRGB(232, 234, 242))
	Kit.Bands(key, Color3.fromRGB(74, 76, 90))
	Kit.Label({ Parent = key, Text = keyText(prompt, inputType), TextSize = 30, Stroke = 0, Fit = true })

	local action = Kit.Label({
		Parent = button,
		Name = "Action",
		Text = prompt.ActionText,
		TextSize = 31,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(86, 7),
		Size = UDim2.new(1, -98, 0, 38),
		Stroke = 3.5,
		Fit = true,
	})
	local object = Kit.Label({
		Parent = button,
		Name = "Object",
		Text = prompt.ObjectText,
		TextSize = 19,
		Color = Kit.Colors.Honey,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(86, 47),
		Size = UDim2.new(1, -98, 0, 26),
		Stroke = 3,
		Fit = true,
	})
	local actionChanged = prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
		action.Text = prompt.ActionText
	end)
	local objectChanged = prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
		object.Text = prompt.ObjectText
	end)
	billboard.Destroying:Connect(function()
		actionChanged:Disconnect()
		objectChanged:Disconnect()
	end)

	-- tapping the honey button works the same as pressing E
	button.Activated:Connect(function()
		prompt:InputHoldBegin()
		task.wait()
		prompt:InputHoldEnd()
	end)

	pop.Scale = 0.5
	TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function hidePrompt(prompt: ProximityPrompt)
	local billboard = promptGuis[prompt]
	if billboard then
		promptGuis[prompt] = nil
		billboard:Destroy()
	end
end

local function bounceOnTrigger(prompt: ProximityPrompt)
	local billboard = promptGuis[prompt]
	local pop = billboard and billboard:FindFirstChild("Pop") :: UIScale?
	if pop then
		pop.Scale = 0.85
		TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- 4. ROLLING: THE SHOW ON THE HONEYCOMB STAND ------------------------------------------
-- The server rolls the bee and writes the result on the stand (its attributes OfferStart,
-- OfferRarity, OfferPrice and OfferNew). Every player's screen plays the same little show
-- from those: a mystery egg, then a black shadow, then the bee with its name, its rarity
-- and its price. Whether the bee can be bought is decided by the server; this only draws it.

local STAND_TAG = "RollStand"
local STAND_BEE_SCALE = 1.3
local STAND_CELL_FORWARD = 0.55 -- the middle of the stand's six-sided cell, in front of the bee's own middle
local EGG_SECONDS = GameConfig.RollEggSeconds
local SHADOW_SECONDS = GameConfig.RollShadowSeconds
local BIG_EGG_SECONDS = GameConfig.BigRevealEggSeconds -- a BigReveal bee stays in its golden egg this long
local EGG_HOVER = 1 -- how high the egg floats above the stand
local EGG_SHELL = Color3.fromRGB(255, 240, 200)
local EGG_SHELL_DARK = Color3.fromRGB(250, 222, 160)
local EGG_SPOT = Color3.fromRGB(255, 196, 40)
local SHADOW_COLOR = Color3.fromRGB(16, 14, 18)
local STAND_PILL_GREEN = Color3.fromRGB(60, 225, 70)
local STAND_PILL_GREY = Color3.fromRGB(205, 205, 228)
-- the egg, from the bottom up: { how wide, how tall }
local EGG_LAYERS = { { 1.2, 0.35 }, { 1.8, 0.4 }, { 2.2, 0.5 }, { 2.4, 0.55 }, { 2.2, 0.5 }, { 1.7, 0.4 }, { 1.1, 0.3 } }

type StandShow = {
	Stage: string, -- "none" (not drawn yet), "empty", "egg", "shadow" or "bee"
	Start: number?, -- the OfferStart this show belongs to
	Prop: Model?, -- the egg, shadow or bee on the stand
	Beam: BasePart?, -- the light over a top-rarity bee
	Wobble: number, -- so two stands never move in step
}
local stands: { [Model]: StandShow } = {}

-- A block that is only for looks: it cannot be bumped into or clicked.
local function fxPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- The mystery egg: a chunky cream egg with honey spots and a "?" on the front and back.
-- Its middle is the model's own (0, 0, 0). The egg itself is a Blender piece (BeeMeshes.Egg);
-- if that piece is ever missing, an egg of plain blocks is built instead.
local function makeEgg(): Model
	local egg = Instance.new("Model")
	egg.Name = "MysteryEgg"
	local template = sharedFolder:WaitForChild("BeeMeshes"):FindFirstChild("Egg")
	if template and template:IsA("MeshPart") then
		local shell = template:Clone()
		shell.Name = "Shell"
		local place = template:GetAttribute("Place")
		-- (the piece stands on the ground and is 3 studs tall, so it goes down by half of that)
		shell.CFrame = CFrame.new(0, -1.5, 0) * (if typeof(place) == "CFrame" then place else CFrame.identity)
		shell.Color = WHITE
		shell.Anchored = true
		shell.CanCollide = false
		shell.CanTouch = false
		shell.CanQuery = false
		shell.CastShadow = false
		shell.PivotOffset = shell.CFrame:ToObjectSpace(CFrame.identity) -- it is moved by its middle
		shell.Parent = egg
		egg.PrimaryPart = shell
	else
		local y = -1.5
		for index, layer in EGG_LAYERS do
			local shell = fxPart("Shell", Vector3.new(layer[1], layer[2], layer[1]), CFrame.new(0, y + layer[2] / 2, 0), if index % 2 == 0 then EGG_SHELL else EGG_SHELL_DARK, egg)
			if index == 4 then
				egg.PrimaryPart = shell
			end
			y += layer[2]
		end
		for _, spot in { Vector3.new(-1.22, 0.3, 0.5), Vector3.new(-1.12, -0.45, -0.4), Vector3.new(1.22, 0.1, -0.5), Vector3.new(1.12, 0.65, 0.35) } do
			fxPart("Spot", Vector3.new(0.12, 0.42, 0.42), CFrame.new(spot), EGG_SPOT, egg).Material = Enum.Material.Neon
		end
	end
	for _, side in { 1, -1 } do
		local mark = fxPart("Mark", Vector3.new(1.7, 1.9, 0.05), CFrame.new(0, 0.05, side * 1.23), WHITE, egg)
		mark.Transparency = 1
		local gui = Kit.Create("SurfaceGui", {
			Name = "Face",
			Face = if side == 1 then Enum.NormalId.Back else Enum.NormalId.Front,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 40,
			LightInfluence = 0,
			Parent = mark,
		})
		local label = Kit.Create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.FredokaOne,
			Text = "?",
			TextScaled = true,
			TextColor3 = Color3.fromRGB(255, 205, 50),
			Parent = gui,
		})
		Kit.Create("UIStroke", { Color = Color3.fromRGB(20, 16, 24), Thickness = 4, LineJoinMode = Enum.LineJoinMode.Round, Parent = label })
	end
	return egg
end

-- Turns a mystery egg gold and sparkling: a bee of a BigReveal rarity is inside.
local function gildEgg(egg: Model)
	for _, descendant in egg:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == "Shell" then
			descendant.Color = Color3.fromRGB(255, 200, 50)
			descendant.Reflectance = 0.2
		elseif descendant:IsA("TextLabel") then
			Kit.SetRainbow(descendant, true) -- the "?" marks
		end
	end
	local shell = egg.PrimaryPart
	if shell then
		local glow = Instance.new("PointLight")
		glow.Color = GOLD
		glow.Range = 14
		glow.Brightness = 2
		glow.Parent = shell
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(GOLD, WHITE)
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Lifetime = NumberRange.new(0.6, 1)
		sparkles.Rate = 26
		sparkles.Speed = NumberRange.new(3, 6)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Parent = shell
	end
end

-- The black shadow of a bee: the same shape as the real one, painted all black.
local function makeShadow(): Model
	local shadow = BeeModelFactory.Create(SHADOW_COLOR, { Scale = STAND_BEE_SCALE })
	shadow.Name = "ShadowBee"
	for _, descendant in shadow:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Color = SHADOW_COLOR
			descendant.Material = Enum.Material.SmoothPlastic
			if descendant.Transparency < 1 then
				descendant.Transparency = 0
			end
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		end
	end
	return shadow
end

-- A puff of sparkles.
local function puff(part: BasePart, color: Color3, amount: number)
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Color = ColorSequence.new(color, WHITE)
	burst.LightEmission = 1
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	burst.Lifetime = NumberRange.new(0.6, 1.1)
	burst.Speed = NumberRange.new(8, 16)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Rate = 0
	burst.Parent = part
	burst:Emit(amount)
	Debris:AddItem(burst, 2)
end

local function plotOf(instance: Instance): Instance?
	local current = instance
	while current.Parent and current.Parent ~= plotsFolder do
		current = current.Parent
	end
	return if current.Parent == plotsFolder then current else nil
end

local function standSpot(stand: Model): BasePart?
	local spot = stand:FindFirstChild("BeeSpot")
	return if spot and spot:IsA("BasePart") then spot else nil
end

local function standPrompt(stand: Model): ProximityPrompt?
	local buySpot = stand:FindFirstChild("BuySpot")
	local prompt = buySpot and buySpot:FindFirstChild("Prompt")
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

-- The name (in GameConfig.Bees) of the bee waiting on a stand, and the bee itself.
local function offerName(stand: Model): string?
	local beeName = stand:GetAttribute("OfferRarity")
	return if typeof(beeName) == "string" and GameConfig.Bees[beeName] then beeName else nil
end

local function offerRarity(stand: Model)
	local beeName = offerName(stand)
	return if beeName then GameConfig.Bees[beeName] else nil
end

-- Writes the stand's screen for the stage the show is at.
local function drawScreen(stand: Model, stage: string)
	local screen = stand:FindFirstChild("Screen")
	local face = screen and screen:FindFirstChild("Face")
	if not face then
		return
	end
	local rarity = offerRarity(stand)
	local revealed = rarity ~= nil and stage == "bee"

	local mystery = face:FindFirstChild("Mystery")
	if mystery and mystery:IsA("TextLabel") then
		mystery.Visible = stage == "egg"
		Kit.SetRainbow(mystery, stage == "egg" and rarity ~= nil and rarity.BigReveal) -- a golden egg's "???"
	end
	local rarityLabel = face:FindFirstChild("Rarity")
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.Visible = rarity ~= nil and (stage == "shadow" or stage == "bee")
		-- on its own (the shadow stage) the rarity is written big; later it shares the screen
		rarityLabel.Position = if stage == "shadow" then UDim2.fromScale(0.06, 0.2) else UDim2.fromScale(0.04, 0.3)
		rarityLabel.Size = if stage == "shadow" then UDim2.fromScale(0.88, 0.6) else UDim2.fromScale(0.92, 0.33)
		if rarity then
			rarityLabel.Text = rarity.DisplayName
			Kit.RarityText(rarityLabel, rarity.Rarity) -- (rainbow for the best rarity)
		end
	end
	local nameLabel = face:FindFirstChild("BeeName")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Visible = revealed
		if rarity then
			nameLabel.Text = rarity.BeeName
		end
		Kit.BeeNameText(nameLabel, offerName(stand))
	end

	local pill = face:FindFirstChild("Price")
	if pill and pill:IsA("Frame") then
		pill.Visible = revealed
		local price = stand:GetAttribute("OfferPrice")
		if revealed and typeof(price) == "number" then
			local free = price <= 0
			local coin = pill:FindFirstChild("Coin")
			if coin and coin:IsA("GuiObject") then
				coin.Visible = not free
			end
			local label = pill:FindFirstChild("Label")
			if label and label:IsA("TextLabel") then
				label.Text = if free then "FREE" else NumberFormat.Short(price)
				label.Position = if free then UDim2.fromScale(0.06, 0.06) else UDim2.fromScale(0.28, 0.06)
				label.Size = if free then UDim2.fromScale(0.88, 0.88) else UDim2.fromScale(0.66, 0.88)
			end
			-- on your own stand the pill goes grey while you cannot afford the bee
			local plot = plotOf(stand)
			local tooDear = plot ~= nil and isMine(plot) and State.Number("Coins") < price
			pill.BackgroundColor3 = if tooDear then STAND_PILL_GREY else STAND_PILL_GREEN
		end
	end

	-- the tilted "New!" tag: a kind of bee the owner does not have yet
	local newTag = stand:FindFirstChild("NewTag")
	local newFace = newTag and newTag:FindFirstChild("Face")
	local newText = newFace and newFace:FindFirstChild("Text")
	if newText and newText:IsA("TextLabel") then
		newText.Visible = revealed and stand:GetAttribute("OfferNew") == true
	end
end

-- How loud a stand's roll sounds are for this player: full volume near the stand, fading to
-- nothing further away (GameConfig.RollSoundRange and RollSoundFade). So the eggs are only
-- heard in the roll area, not from the hive or the jars.
local function rollLoudness(spot: BasePart): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return 0
	end
	local distance = (root.Position - spot.Position).Magnitude
	return math.clamp(1 - (distance - GameConfig.RollSoundRange) / math.max(GameConfig.RollSoundFade, 0.01), 0, 1)
end

-- Swaps what stands on the stand. quiet = true skips the sparkles and sounds (used when we
-- arrive late, for example when the stand only just appeared on this device).
local function setStage(stand: Model, show: StandShow, stage: string, quiet: boolean)
	if show.Prop then
		show.Prop:Destroy()
		show.Prop = nil
	end
	if show.Beam then
		show.Beam:Destroy()
		show.Beam = nil
	end
	show.Stage = stage

	local plot = plotOf(stand)
	local mine = plot ~= nil and isMine(plot)
	local spot = standSpot(stand)
	local rarity = offerRarity(stand)
	if spot and rarity then
		local isTop = rarity.BigReveal -- the best rarity gets the big show
		local loud = if mine and not quiet then rollLoudness(spot) else 0 -- (0 = too far away to hear)
		if stage == "egg" then
			local egg = makeEgg()
			if isTop then
				gildEgg(egg) -- a golden egg: something special is inside!
			end
			show.Prop = egg
			if mine and not quiet then
				if isTop then
					-- the golden egg: its shakes and tings climb, and a whoosh rises into the reveal
					Kit.PlaySound("GoldEgg", 1, loud)
					task.delay(math.max(0, BIG_EGG_SECONDS + SHADOW_SECONDS - GameConfig.RiseLead), Kit.PlaySound, "Rise", 1, loud)
				else
					Kit.PlaySound("Shake", 1, loud)
				end
			end
		elseif stage == "shadow" then
			show.Prop = makeShadow()
			if not quiet then
				puff(spot, WHITE, 14)
				if mine then
					Kit.PlaySound("Shadow", 1, loud)
				end
			end
		elseif stage == "bee" then
			show.Prop = BeeModelFactory.Create(rarity.Color, { Scale = STAND_BEE_SCALE, Sparkles = rarity.Sparkles })
			if not quiet then
				puff(spot, rarity.RarityColor, if isTop then 60 else 24)
				if isTop then
					-- a burst in every colour
					puff(spot, Color3.fromRGB(255, 90, 160), 30)
					puff(spot, Color3.fromRGB(90, 220, 255), 30)
					puff(spot, Color3.fromRGB(140, 255, 110), 30)
				end
				if mine then
					local beeName = offerName(stand)
					if isTop and beeName then
						Effects.BigReveal(beeName, loud) -- flash, confetti and fanfare on your screen
					else
						Kit.PlaySound(if beeName then Kit.RevealSoundFor(beeName) else "Reveal1", 1, loud) -- the rarer, the bigger
					end
				end
			end
			if isTop then
				-- the best kind of bee gets a column of light
				local beam = fxPart("Beam", Vector3.new(2.4, 60, 2.4), CFrame.new(spot.Position + Vector3.new(0, 30, 0)), rarity.RarityColor:Lerp(WHITE, 0.5), stand)
				beam.Material = Enum.Material.Neon
				beam.Transparency = 0.78
				show.Beam = beam
			end
		end
		if show.Prop then
			show.Prop.Parent = stand -- so it disappears together with the stand
		end
	end

	drawScreen(stand, stage)

	local prompt = standPrompt(stand)
	if prompt then
		buyReady[prompt] = stage == "bee"
		prompt.Enabled = promptAllowed(prompt, mine)
	end
end

local function addStand(instance: Instance)
	if instance:IsA("Model") and instance:IsDescendantOf(plotsFolder) and not stands[instance] then
		stands[instance] = { Stage = "none", Start = nil, Prop = nil, Beam = nil, Wobble = math.random() * 10 }
	end
end

local function removeStand(instance: Instance)
	local show = stands[instance :: Model]
	if show then
		if show.Prop then
			show.Prop:Destroy()
		end
		if show.Beam then
			show.Beam:Destroy()
		end
		stands[instance :: Model] = nil
	end
end

-- Runs every frame: works out which stage each stand's show has reached (from the server's
-- clock, so everyone sees the same thing) and moves whatever is standing on it.
local function moveStands(now: number)
	local serverNow = workspace:GetServerTimeNow()
	for stand, show in stands do
		local start = stand:GetAttribute("OfferStart")
		local stage = "empty"
		local elapsed = 0
		local began = 0
		local offered = offerRarity(stand)
		-- (a BigReveal bee stays in its golden egg for longer)
		local eggSeconds = if offered and offered.BigReveal then BIG_EGG_SECONDS else EGG_SECONDS
		if typeof(start) == "number" and offered then
			elapsed = math.max(0, serverNow - start)
			if elapsed < eggSeconds then
				stage = "egg"
			elseif elapsed < eggSeconds + SHADOW_SECONDS then
				stage, began = "shadow", eggSeconds
			else
				stage, began = "bee", eggSeconds + SHADOW_SECONDS
			end
		end
		local started = if typeof(start) == "number" then start else nil
		if stage ~= show.Stage or started ~= show.Start then
			show.Start = started
			setStage(stand, show, stage, elapsed - began > 0.6)
		end

		local prop, spot = show.Prop, standSpot(stand)
		if show.Beam and spot then
			-- (stands move over when their owner buys another one: the light goes with them)
			show.Beam.CFrame = CFrame.new(spot.Position + Vector3.new(0, 30, 0))
		end
		if prop and spot then
			local t = now + show.Wobble
			if stage == "egg" then
				-- it floats, and rocks faster and faster as it gets ready to hatch
				local hurry = math.clamp(elapsed / eggSeconds, 0, 1)
				local lean = math.sin(t * (9 + hurry * 14)) * (0.06 + hurry * 0.22)
				prop:PivotTo(spot.CFrame * CFrame.new(0, 1.5 + EGG_HOVER + math.sin(t * 3) * 0.15, STAND_CELL_FORWARD) * CFrame.Angles(0, 0, lean))
			else
				-- a bee is built facing -Z and the stand's front is +Z, so turn it to face the player
				local lift = 0.94 * STAND_BEE_SCALE + 0.12
				local turn = 0
				if stage == "bee" then
					local since = elapsed - began
					local hop = if since < 0.35 then math.sin(since / 0.35 * math.pi) * 0.8 else 0
					lift += 0.25 + math.sin(t * 2.2) * 0.2 + hop
					turn = math.sin(t * 0.9) * 0.3
				end
				prop:PivotTo(spot.CFrame * CFrame.new(0, lift, 0) * CFrame.Angles(0, math.pi + turn, 0))
			end
		end
	end
end

-- The price pill on your own stand turns green the moment you can afford the bee.
local function refreshStandPills()
	for stand, show in stands do
		if show.Stage == "bee" then
			drawScreen(stand, "bee")
		end
	end
end

-- THE HONEY MARKET'S PRICE BOARD -------------------------------------------------------
-- Every Honey Market shows the price (the same for everyone in the server), a bar that runs
-- from red to green, and a countdown to the next change. The server only says what the price
-- is and when it changes (two numbers on the workspace); each device draws the boards itself.

local PRICE_LOWEST, PRICE_HIGHEST = math.huge, 0
for _, band in GameConfig.SellPriceBands do
	PRICE_LOWEST = math.min(PRICE_LOWEST, band.Min)
	PRICE_HIGHEST = math.max(PRICE_HIGHEST, band.Max)
end
local BOARD_INK = Color3.fromRGB(20, 16, 24)
local BAR_LEFT, BAR_WIDE = 0.07, 0.86 -- where the bar sits across the board

type PriceBoard = { Price: TextLabel, Empty: Frame, Marker: Frame, Countdown: TextLabel }
local priceBoards: { [Instance]: PriceBoard } = {}

local function boardText(parent: Instance, name: string, position: UDim2, size: UDim2, xAlign: Enum.TextXAlignment): TextLabel
	local label = Kit.Create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Position = position,
		Size = size,
		Font = Enum.Font.FredokaOne,
		Text = "",
		TextScaled = true,
		TextColor3 = WHITE,
		TextXAlignment = xAlign,
		Parent = parent,
	})
	Kit.Create("UIStroke", {
		Color = BOARD_INK,
		LineJoinMode = Enum.LineJoinMode.Round,
		StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize,
		Thickness = 0.08,
		Parent = label,
	})
	return label
end

local function makePriceBoard(counter: BasePart): PriceBoard
	local gui = Kit.Create("BillboardGui", {
		Name = "PriceBoard",
		Size = UDim2.fromScale(12, 4.4),
		StudsOffsetWorldSpace = Vector3.new(0, 12.5, 0), -- just above the "Honey Market" sign
		MaxDistance = 80,
		LightInfluence = 0,
		Parent = counter,
	})
	local title = boardText(gui, "Title", UDim2.fromScale(0, 0), UDim2.fromScale(0.5, 0.42), Enum.TextXAlignment.Right)
	title.Text = "Price"
	local price = boardText(gui, "Price", UDim2.fromScale(0.53, 0), UDim2.fromScale(0.47, 0.42), Enum.TextXAlignment.Left)

	-- the bar: every colour from red to green, with the part above the price blacked out
	local bar = Kit.Create("Frame", {
		Name = "Bar",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(BAR_LEFT, 0.5),
		Size = UDim2.fromScale(BAR_WIDE, 0.17),
		Parent = gui,
	})
	Kit.Create("UIStroke", { Color = BOARD_INK, Thickness = 2.5, Parent = bar })
	local colours = Kit.Create("Frame", { Name = "Colours", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = bar })
	Kit.Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 40, 40)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 150, 0)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 240, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 220, 40)),
		}),
		Parent = colours,
	})
	local empty = Kit.Create("Frame", {
		Name = "Empty",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(1, 1),
		Parent = bar,
	})
	-- a little yellow diamond that sits on the bar where the price is
	local marker = Kit.Create("Frame", {
		Name = "Marker",
		BackgroundColor3 = Color3.fromRGB(255, 226, 60),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(BAR_LEFT, 0.47),
		Size = UDim2.fromScale(0.034, 0.093),
		Rotation = 45,
		Parent = gui,
	})
	Kit.Create("UIStroke", { Color = BOARD_INK, Thickness = 2, Parent = marker })

	local countdown = boardText(gui, "Countdown", UDim2.fromScale(0, 0.72), UDim2.fromScale(1, 0.28), Enum.TextXAlignment.Center)
	countdown.RichText = true
	return { Price = price, Empty = empty, Marker = marker, Countdown = countdown }
end

-- Runs a few times a second: finds the markets this device can see and redraws their boards.
local function updatePriceBoards()
	local price = State.SellPrice()
	local secondsLeft = State.SellPriceSecondsLeft()
	local along = math.clamp((price - PRICE_LOWEST) / math.max(PRICE_HIGHEST - PRICE_LOWEST, 0.01), 0, 1)

	for _, plot in plotsFolder:GetChildren() do
		local market = plot:FindFirstChild("Market")
		local counter = market and market:FindFirstChild("Counter")
		if counter and counter:IsA("BasePart") then
			local board = priceBoards[counter]
			if not board then
				board = makePriceBoard(counter)
				priceBoards[counter] = board
			end
			board.Price.Text = string.format("x%.1f", price)
			Kit.PriceText(board.Price, price)
			board.Empty.Size = UDim2.fromScale(1 - along, 1)
			board.Marker.Position = UDim2.fromScale(BAR_LEFT + BAR_WIDE * along, 0.47)
			board.Countdown.Text = string.format('New price in <font color="#FF4040">%d</font>s', secondsLeft)
		end
	end
	-- (a market that has left this device takes its board with it)
	for counter in priceBoards do
		if not counter:IsDescendantOf(workspace) then
			priceBoards[counter] = nil
		end
	end
end

-- A BOUGHT BEE FLIES OFF THE STAND ----------------------------------------------------

local rollingBees: { { Model: Model, Start: number, From: Vector3, Bend: Vector3, To: Vector3 } } = {}
local ROLL_FLIGHT_SECONDS = 1.1

-- Plays on your own plot when you buy the bee on a stand. placed = true flies it to your
-- hive, otherwise it flies up and away (into your bag).
function WorldFX.PlayBought(rarityName: string, placed: boolean, standIndex: number)
	local rarity = GameConfig.Bees[rarityName]
	local plot = myPlot()
	local queen = plot and plot:FindFirstChild("Queen")
	local folder = queen and queen:FindFirstChild("Stands")
	local stand = folder and folder:FindFirstChild("Stand" .. standIndex)
	local spot = stand and stand:FindFirstChild("BeeSpot")
	if not rarity or not spot or not spot:IsA("BasePart") then
		return
	end

	puff(spot, rarity.RarityColor, 24)

	-- the bee itself (only you see this one; the real working bee is made by the server)
	local bee = BeeModelFactory.Create(rarity.Color, { Scale = 1.3, Trail = rarity.Trail })
	bee.Name = "BoughtBee"
	bee.Parent = workspace

	local from = spot.Position + Vector3.new(0, 1.6, 0)
	local to = from + Vector3.new(0, 22, 0)
	local anchor = plot and plot:FindFirstChild("HiveAnchor")
	if placed and anchor and anchor:IsA("BasePart") then
		to = anchor.Position + Vector3.new(0, 4, 0)
	end
	table.insert(rollingBees, {
		Model = bee,
		Start = os.clock(),
		From = from,
		Bend = (from + to) / 2 + Vector3.new(0, 12, 0),
		To = to,
	})
end

-- More Rolls was bought: your stands have just moved apart and a new one has appeared.
-- A puff of sparkles on each of them.
function WorldFX.PlayNewStand()
	task.delay(0.35, function() -- (a moment for the new stand to reach this device)
		local plot = myPlot()
		local queen = plot and plot:FindFirstChild("Queen")
		local folder = queen and queen:FindFirstChild("Stands")
		if not folder then
			return
		end
		for _, stand in folder:GetChildren() do
			local spot = stand:FindFirstChild("BeeSpot")
			if spot and spot:IsA("BasePart") then
				puff(spot, GOLD, 30)
			end
		end
	end)
end

local function moveRollingBees(now: number)
	for index = #rollingBees, 1, -1 do
		local flight = rollingBees[index]
		local t = (now - flight.Start) / ROLL_FLIGHT_SECONDS
		if t >= 1 or not flight.Model.Parent then
			flight.Model:Destroy()
			table.remove(rollingBees, index)
		else
			local eased = t * t * (3 - 2 * t)
			local position = (1 - eased) ^ 2 * flight.From + 2 * (1 - eased) * eased * flight.Bend + eased ^ 2 * flight.To
			-- a little spin as it sets off
			flight.Model:PivotTo(CFrame.new(position) * CFrame.Angles(0, t * math.pi * 4, 0))
		end
	end
end

-- 5. BEES FLYING TO THE FLOWERS ---------------------------------------------------------

local FORAGER_TAG = "BeeForager"
local OUT_END = 0.36 -- first 36% of a trip: fly to the flower
local BACK_START = 0.64 -- last 36%: fly home (in between: pollinating the flower)

-- 5d. OTHER PLAYERS' BEES, HIDDEN (a choice in Settings) ------------------------------------
-- A player may hide the other players' flying bees (the ones flying to the flowers and the honey
-- carriers) on their own screen. Hidden bees are not moved at all and not drawn: that is what
-- makes a busy server calmer and lighter. Nobody else sees any difference.
-- (Written before the foragers and workers below, because removing a bee must forget it here.)

-- a hidden bee -> its sparkles and lights, and whether each one was on before it was hidden.
-- (A normal table on purpose: a "weak" table quietly loses Roblox objects, and then the
-- sparkles never came back on.)
local hiddenBees: { [Model]: { [Instance]: boolean } } = {}
local GLOW_CLASSES = { "ParticleEmitter", "Trail", "Beam", "PointLight", "SpotLight", "SurfaceLight", "BillboardGui", "Sparkles", "Fire", "Smoke" }

local function isGlow(instance: Instance): boolean
	for _, className in GLOW_CLASSES do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

-- Hides a bee from this screen only, or shows it again. (LocalTransparencyModifier is the
-- part's see-through-ness on this device alone; the server never sees it.)
local function setHidden(bee: Model, hidden: boolean)
	local saved = hiddenBees[bee]
	if (saved ~= nil) == hidden then
		return
	end
	if hidden then
		saved = {}
		hiddenBees[bee] = saved
	else
		hiddenBees[bee] = nil
	end
	for _, piece in bee:GetDescendants() do
		if piece:IsA("BasePart") then
			piece.LocalTransparencyModifier = if hidden then 1 else 0
		elseif isGlow(piece) then
			local glow = piece :: any
			if hidden then
				(saved :: any)[piece] = glow.Enabled
				glow.Enabled = false
			elseif (saved :: any)[piece] ~= nil then
				glow.Enabled = (saved :: any)[piece]
			end
		end
	end
end

-- True if something that lives under `folder` (a bee, or a hive's folder of bees) is someone
-- else's and the player has chosen to hide those.
local function hideIt(folder: Instance, mine: Instance?, showOthers: boolean): boolean
	return not showOthers and not (mine ~= nil and folder:IsDescendantOf(mine))
end

type Forager = {
	Hive: Vector3,
	Flower: Vector3,
	Bend: Vector3,
	Start: number,
	Seconds: number,
	Jars: number,
	Wobble: number,
	Pollen: BasePart?,
	LastCycle: number,
	Mine: boolean,
}
local foragers: { [Model]: Forager } = {}

local function addForager(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local hive = instance:GetAttribute("HivePoint")
	local flower = instance:GetAttribute("FlowerPoint")
	local start = instance:GetAttribute("TripStart")
	local seconds = instance:GetAttribute("TripSeconds")
	if typeof(hive) ~= "Vector3" or typeof(flower) ~= "Vector3" or typeof(start) ~= "number" or typeof(seconds) ~= "number" or seconds <= 0 then
		return
	end
	local wobble = (start * 7.3) % (math.pi * 2)
	local sideways = (flower - hive):Cross(Vector3.yAxis)
	if sideways.Magnitude > 0 then
		sideways = sideways.Unit * math.sin(wobble) * 9
	end
	local plot = myPlot()
	local pollen = instance:FindFirstChild("Pollen")
	foragers[instance] = {
		Hive = hive,
		Flower = flower,
		-- the path curves up high so bees fly over the arch and the players
		Bend = (hive + flower) / 2 + Vector3.new(0, 26 + math.cos(wobble) * 4, 0) + sideways,
		Start = start,
		Seconds = seconds,
		Jars = instance:GetAttribute("JarsPerTrip") or 0,
		Wobble = wobble,
		Pollen = if pollen and pollen:IsA("BasePart") then pollen else nil,
		LastCycle = math.floor((workspace:GetServerTimeNow() - start) / seconds),
		Mine = plot ~= nil and instance:IsDescendantOf(plot),
	}
end

local function removeForager(instance: Instance)
	foragers[instance :: Model] = nil
	hiddenBees[instance :: Model] = nil
end

-- A little "+6" that floats up from your Honey Jars when a worker bee drops honey off.
local function honeyPop(jars: number)
	local plot = myPlot()
	local station = plot and plot:FindFirstChild("CollectStation")
	local tablePart = station and station:FindFirstChild("Table")
	if not tablePart or not tablePart:IsA("BasePart") or jars <= 0 then
		return
	end
	local billboard = Kit.Create("BillboardGui", {
		Name = "HoneyPop",
		Adornee = tablePart,
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(120, 44),
		StudsOffsetWorldSpace = Vector3.new(math.random(-20, 20) / 10, 4, 0),
		Parent = playerGui,
	})
	local label = Kit.Label({ Parent = billboard, Text = string.format("+%g", math.floor(jars * 10 + 0.5) / 10), TextSize = 30, Color = Color3.fromRGB(255, 225, 120), Stroke = 3 })
	local stroke = label:FindFirstChildOfClass("UIStroke")
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, info, { StudsOffsetWorldSpace = billboard.StudsOffsetWorldSpace + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	if stroke then
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	end
	Debris:AddItem(billboard, 1)
end

local function curve(from: Vector3, bend: Vector3, to: Vector3, t: number): Vector3
	return (1 - t) ^ 2 * from + 2 * (1 - t) * t * bend + t ^ 2 * to
end

local function moveForagers(now: number)
	local serverNow = workspace:GetServerTimeNow()
	local mine = myPlot()
	local showOthers = State.ShowOtherBees()
	for bee, info in foragers do
		local hidden = hideIt(bee, mine, showOthers)
		setHidden(bee, hidden)
		if bee.PrimaryPart and not hidden then
			local elapsed = serverNow - info.Start
			local position: Vector3
			local lookAt: Vector3
			local carrying = false

			if elapsed < 0 then
				-- waiting at the hive for its first trip
				position = info.Hive + Vector3.new(0, math.sin(now * 3 + info.Wobble) * 0.3, 0)
				lookAt = position + (info.Flower - info.Hive).Unit
			else
				local cycle = math.floor(elapsed / info.Seconds)
				local t = (elapsed % info.Seconds) / info.Seconds
				if cycle > info.LastCycle then
					info.LastCycle = cycle
				end

				if t < OUT_END then
					local u = t / OUT_END
					u = u * u * (3 - 2 * u)
					position = curve(info.Hive, info.Bend, info.Flower, u)
					lookAt = curve(info.Hive, info.Bend, info.Flower, math.min(1, u + 0.02))
				elseif t < BACK_START then
					-- pollinating: a tiny circle over the flower
					local angle = now * 4 + info.Wobble
					position = info.Flower + Vector3.new(math.cos(angle) * 0.9, math.sin(now * 5 + info.Wobble) * 0.25, math.sin(angle) * 0.9)
					lookAt = position + Vector3.new(-math.sin(angle), 0, math.cos(angle))
					carrying = t > (OUT_END + BACK_START) / 2
				else
					local u = (t - BACK_START) / (1 - BACK_START)
					u = u * u * (3 - 2 * u)
					position = curve(info.Flower, info.Bend, info.Hive, u)
					lookAt = curve(info.Flower, info.Bend, info.Hive, math.min(1, u + 0.02))
					carrying = true
				end
			end

			if (lookAt - position).Magnitude < 0.001 then
				lookAt = position + Vector3.zAxis
			end
			bee:PivotTo(CFrame.lookAt(position, lookAt))
			if info.Pollen then
				info.Pollen.Transparency = if carrying then 0 else 1
			end
		end
	end
end

-- 5b. WORKER BEES CARRYING HONEY TO THE JARS -----------------------------------------------
-- The server says what each worker is doing and since when (attributes on the bee);
-- this draws it. While a worker waits it flies loops round the hive. When honey is ready
-- it swoops to the hive door, picks up a jar and flies it to the Honey Jars, then flies back.

local WORKER_TAG = "BeeWorker"
local WORKER_ARC = 4 -- how high (in studs) a worker's path curves above a straight line
local WORKER_SWOOP = 0.25 -- the first part of a honey flight is spent swooping to the hive door
local WORKER_LOOP_SPEED = 0.9 -- how fast waiting workers circle the hive
local WORKER_MERGE_SECONDS = 0.7 -- how long a worker takes to drop from the hive door out onto the circle
local WORKER_ROOM = 5.2 -- studs of room a worker needs on the circle (a worker is about 4.2 long)
local WORKER_OVER = 4.2 -- a worker flying to its spot at the door comes in this far above the others, then drops onto it
local WORKER_WIDE = 2.4 -- and it swings this far out from the hive on the way, so it climbs past the door row at a distance

-- HOW THE WORKERS STAY APART (so two of them never look like one double bee):
-- * The server gives every hive as many LANES as it has workers. A lane is a spot at the
--   hive door and a spot above the jars, and the lanes run side by side, wider apart than a bee.
-- * A worker flying honey uses one lane, there and back, and no two workers share a lane.
--   When several set off together they take neighbouring free lanes in the order they are
--   flying in, so their paths to the door never cross.
--   A worker on its way to the door flies in ABOVE the row of spots and drops onto its own,
--   so it never passes through one that is already waiting there.
-- * After a delivery a worker waits at the door of its lane until there is room on the
--   circle round the hive. Then it drops straight out and down onto the circle (staying in
--   its own lane's space) and only then starts to fly round. Everyone on the circle flies
--   the same way at the same speed, so the room between them stays.
type Worker = {
	State: string,
	LegStart: number,
	LegSeconds: number,
	Load: number, -- the jars it was last seen carrying (for the "+N" when it lands)
	OwnHive: Vector3?, -- the lane with this worker's own number: its spot at the hive door...
	OwnJars: Vector3?, -- ...and its spot above the Honey Jars
	Middle: Vector3?, -- the middle of the hive (waiting workers circle it)
	Radius: number, -- how wide that circle is
	Slot: number, -- the number of its own lane (1, 2, 3...)
	Wobble: number, -- makes each worker's flight a little different
	Lane: number?, -- the lane it is using now (nil while it is out on the circle)
	Phase: number, -- where on the circle it flies
	MergeStart: number?, -- when it began easing from the hive door out onto the circle
	CarryFrom: Vector3?, -- where it was when it set off for honey
	Fresh: boolean, -- true until it has been given its first place
	LastPosition: Vector3?,
	Facing: Vector3?,
	Cargo: { BasePart }, -- the little honey jar under the bee, shown while it carries
	CargoShown: boolean,
	Changed: RBXScriptConnection?,
}
local workerBees: { [Model]: Worker } = {}
local landedJars = 0 -- honey my workers dropped off this frame (several can land together; one "+N" is shown)

-- Copies what the server says about a worker: what it is doing and since when.
local function readWorker(bee: Model, info: Worker)
	local state = bee:GetAttribute("State")
	local newState = if state == "Carry" or state == "Return" then state else "Idle"

	local amount = bee:GetAttribute("Amount")
	if typeof(amount) == "number" and amount > 0 then
		info.Load = amount
	end

	if newState ~= info.State then
		if info.State == "Carry" then
			-- one of MY workers just reached the jars: show the honey arriving
			local plot = myPlot()
			if plot and bee:IsDescendantOf(plot) then
				landedJars += info.Load
			end
			info.Load = 0
		end
		if newState == "Carry" then
			info.CarryFrom = info.LastPosition -- set off from wherever it is right now
		end
		info.MergeStart = nil
		info.State = newState
	end

	local legStart = bee:GetAttribute("LegStart")
	info.LegStart = if typeof(legStart) == "number" then legStart else 0
	local legSeconds = bee:GetAttribute("LegSeconds")
	info.LegSeconds = if typeof(legSeconds) == "number" and legSeconds > 0 then legSeconds else 1
	local hive = bee:GetAttribute("HivePoint")
	info.OwnHive = if typeof(hive) == "Vector3" then hive else nil
	local jars = bee:GetAttribute("JarPoint")
	info.OwnJars = if typeof(jars) == "Vector3" then jars else nil
	local middle = bee:GetAttribute("HiveMiddle")
	info.Middle = if typeof(middle) == "Vector3" then middle else nil
	local radius = bee:GetAttribute("LoopRadius")
	info.Radius = if typeof(radius) == "number" and radius > 0 then radius else 4
	local slot = bee:GetAttribute("LoopSlot")
	info.Slot = if typeof(slot) == "number" and slot >= 1 then slot else 1
end

local function addWorker(instance: Instance)
	if not instance:IsA("Model") or workerBees[instance] then
		return
	end
	local cargo = {}
	for _, child in instance:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 5) == "Cargo" then
			table.insert(cargo, child)
		end
	end
	local state = instance:GetAttribute("State")
	local info: Worker = {
		-- start from the state it is already in, so joining mid-flight does not pop a number
		State = if state == "Carry" or state == "Return" then state else "Idle",
		LegStart = 0,
		LegSeconds = 1,
		Load = 0,
		OwnHive = nil,
		OwnJars = nil,
		Middle = nil,
		Radius = 4,
		Slot = 1,
		Wobble = math.random() * math.pi * 2,
		Lane = nil,
		Phase = math.random() * math.pi * 2,
		MergeStart = nil,
		CarryFrom = nil,
		Fresh = true,
		LastPosition = nil,
		Facing = nil,
		Cargo = cargo,
		CargoShown = false,
		Changed = nil,
	}
	readWorker(instance, info)
	info.Changed = instance.AttributeChanged:Connect(function()
		readWorker(instance, info)
	end)
	workerBees[instance] = info
end

local function removeWorker(instance: Instance)
	hiddenBees[instance :: Model] = nil
	local info = workerBees[instance :: Model]
	if info then
		if info.Changed then
			info.Changed:Disconnect()
		end
		workerBees[instance :: Model] = nil
	end
end

-- Where a worker on the circle round the hive is at this moment.
local function loopPoint(info: Worker, middle: Vector3, now: number): Vector3
	local angle = now * WORKER_LOOP_SPEED + info.Phase
	local radius = info.Radius * (1 + 0.03 * math.sin(now * 0.7 + info.Wobble * 2))
	local height = math.sin(now * 1.1 + info.Wobble) * 0.8
	return middle + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- The direction of a point as seen from the hive's middle, as an angle.
local function angleRound(middle: Vector3, point: Vector3): number
	return math.atan2(point.Z - middle.Z, point.X - middle.X)
end

-- How far it is from angle b to angle a going the short way round (-half a turn to +half a turn).
local function angleGap(a: number, b: number): number
	return (a - b + math.pi) % (math.pi * 2) - math.pi
end

-- A point part of the way from one spot to another, going ROUND the hive (the short way)
-- instead of straight through it. It climbs (or drops) early and swings out wide in the
-- middle, so it is soon clear of the workers on the circle and of the ones at the door.
-- wide = how far out it swings.
local function roundHive(from: Vector3, to: Vector3, middle: Vector3?, t: number, wide: number): Vector3
	if not middle then
		return from:Lerp(to, t)
	end
	local a, b = from - middle, to - middle
	local angleA, angleB = math.atan2(a.Z, a.X), math.atan2(b.Z, b.X)
	local angle = angleA + angleGap(angleB, angleA) * t
	local radiusA, radiusB = math.sqrt(a.X * a.X + a.Z * a.Z), math.sqrt(b.X * b.X + b.Z * b.Z)
	local radius = radiusA + (radiusB - radiusA) * t + math.sin(math.pi * t) * wide
	local up = 1 - (1 - t) * (1 - t)
	return middle + Vector3.new(math.cos(angle) * radius, a.Y + (b.Y - a.Y) * up, math.sin(angle) * radius)
end

type Lane = { Hive: Vector3, Jars: Vector3 }

-- One hive's workers for one frame: hands out lanes, lets waiting workers onto the circle
-- when there is room, and moves every worker.
local function moveWorkerGroup(bees: { Model }, now: number, serverNow: number)
	-- this hive's lanes: [lane number] = its spot at the door and its spot above the jars
	local lanes: { [number]: Lane } = {}
	local middle: Vector3? = nil
	local doorSum, laneCount = Vector3.zero, 0
	for _, bee in bees do
		local info = workerBees[bee]
		if info.OwnHive and info.OwnJars and not lanes[info.Slot] then
			lanes[info.Slot] = { Hive = info.OwnHive, Jars = info.OwnJars }
			doorSum += info.OwnHive
			laneCount += 1
		end
		middle = middle or info.Middle
	end

	-- who is using which lane (a lane that is gone, or claimed twice, is given up)
	local holder: { [number]: Model } = {}
	for _, bee in bees do
		local info = workerBees[bee]
		local lane = info.Lane
		if lane then
			if lanes[lane] and not holder[lane] then
				holder[lane] = bee
			else
				info.Lane = nil
			end
		end
	end

	-- a worker that has only just appeared starts at the hive door, in its own lane if it is free
	for _, bee in bees do
		local info = workerBees[bee]
		if info.Fresh then
			info.Fresh = false
			if not info.Lane then
				local lane = if lanes[info.Slot] and not holder[info.Slot] then info.Slot else nil
				if not lane then
					for number in lanes do
						if not holder[number] then
							lane = number
							break
						end
					end
				end
				if lane then
					info.Lane = lane
					holder[lane] = bee
				end
			end
		end
	end

	-- workers setting off for honey from the circle need a lane each
	local needing: { Model } = {}
	for _, bee in bees do
		local info = workerBees[bee]
		if info.State == "Carry" and not info.Lane then
			table.insert(needing, bee)
		end
	end
	if #needing > 0 and middle and laneCount > 0 then
		local centre: Vector3 = middle
		local front = angleRound(centre, doorSum / laneCount) -- the way the hive door faces
		-- how far round the hive something is from the door: left of it is less than 0, right of it more
		local function side(point: Vector3): number
			return angleGap(angleRound(centre, point), front)
		end
		local function whereIs(bee: Model): number
			local info = workerBees[bee]
			local at = info.CarryFrom or info.LastPosition or info.OwnHive
			return if at then side(at) else 0
		end
		local free: { number } = {}
		for number in lanes do
			if not holder[number] then
				table.insert(free, number)
			end
		end
		table.sort(free, function(one, two)
			return side(lanes[one].Hive) < side(lanes[two].Hive)
		end)
		table.sort(needing, function(one, two)
			return whereIs(one) < whereIs(two)
		end)
		-- take the run of neighbouring free lanes that means the least flying, and hand them
		-- out from left to right: workers keep their order, so their paths never cross
		local bestStart, bestCost = 1, math.huge
		for start = 1, #free - #needing + 1 do
			local cost = 0
			for index, bee in needing do
				cost += math.abs(whereIs(bee) - side(lanes[free[start + index - 1]].Hive))
			end
			if cost < bestCost then
				bestStart, bestCost = start, cost
			end
		end
		for index, bee in needing do
			local lane = free[bestStart + index - 1]
			if lane then
				workerBees[bee].Lane = lane
				holder[lane] = bee
			end
		end
	end

	-- workers waiting at the door ease out onto the circle as soon as there is room for them
	for _, bee in bees do
		local info = workerBees[bee]
		local lane = if info.Lane then lanes[info.Lane] else nil
		if info.State == "Idle" and middle and lane then
			local mergeStart = info.MergeStart
			if mergeStart == nil then
				-- it will reach the circle, still at its own door's angle, a moment from now:
				-- is there room for it there at that moment?
				local doorAt = angleRound(middle, lane.Hive)
				local arriveAt = now + WORKER_MERGE_SECONDS
				local room = WORKER_ROOM / math.max(info.Radius, 1)
				local clear = true
				for _, other in bees do
					local otherInfo = workerBees[other]
					local onCircle = otherInfo.State == "Idle" and (otherInfo.Lane == nil or otherInfo.MergeStart ~= nil)
					if other ~= bee and onCircle then
						local otherAt = arriveAt * WORKER_LOOP_SPEED + otherInfo.Phase
						if math.abs(angleGap(otherAt, doorAt)) < room then
							clear = false
							break
						end
					end
				end
				if clear then
					info.Phase = doorAt - arriveAt * WORKER_LOOP_SPEED -- (it is at the door's angle when it gets there)
					info.MergeStart = now
				end
			elseif now - mergeStart >= WORKER_MERGE_SECONDS then
				-- out on the circle: its lane is free for the next worker
				info.Lane = nil
				info.MergeStart = nil
			end
		end
	end

	-- move every worker
	for _, bee in bees do
		local info = workerBees[bee]
		local lane = if info.Lane then lanes[info.Lane] else nil
		local hive = if lane then lane.Hive else info.OwnHive
		local jars = if lane then lane.Jars else info.OwnJars
		if bee.PrimaryPart and hive and jars then
			local position: Vector3
			local carrying = false
			if info.State == "Idle" then
				local centre = info.Middle
				local mergeStart = info.MergeStart
				if not centre then
					position = hive + Vector3.new(0, math.sin(now * 3 + info.Wobble) * 0.25, 0)
				elseif lane and mergeStart == nil then
					-- waiting at the hive door for room on the circle: a quick little hover
					position = hive + Vector3.new(0, math.sin(now * 5 + info.Wobble) * 0.3, 0)
				elseif lane and mergeStart then
					-- dropping straight out and down from the door onto the circle
					local blend = smooth(math.clamp((now - mergeStart) / WORKER_MERGE_SECONDS, 0, 1))
					position = hive:Lerp(loopPoint(info, centre, mergeStart + WORKER_MERGE_SECONDS), blend)
				else
					position = loopPoint(info, centre, now)
				end
			else
				local t = math.clamp((serverNow - info.LegStart) / info.LegSeconds, 0, 1)
				local bend = (hive + jars) / 2 + Vector3.new(0, WORKER_ARC, 0)
				if info.State == "Return" then
					position = curve(jars, bend, hive, smooth(t))
				elseif t < WORKER_SWOOP then
					-- swoop from wherever it was to the hive door to pick the honey up: round the
					-- hive and in above the other workers' spots, then straight down onto its own.
					-- (A worker that is already at its door just stays there.)
					local from = info.CarryFrom or hive
					local along = smooth(t / WORKER_SWOOP)
					local far = Vector3.new(from.X - hive.X, 0, from.Z - hive.Z).Magnitude
					local over = math.min(WORKER_OVER, far / 2)
					local above = hive + Vector3.new(0, over, 0)
					if along < 0.75 then
						position = roundHive(from, above, info.Middle, along / 0.75, math.min(WORKER_WIDE, far / 2))
					else
						position = above:Lerp(hive, smooth((along - 0.75) / 0.25))
					end
				else
					position = curve(hive, bend, jars, smooth((t - WORKER_SWOOP) / (1 - WORKER_SWOOP)))
					carrying = true
				end
			end

			-- face the way it is moving, keeping the bee level
			local last = info.LastPosition
			if last then
				local step = Vector3.new(position.X - last.X, 0, position.Z - last.Z)
				if step.Magnitude > 0.01 then
					info.Facing = step.Unit
				end
			end
			info.LastPosition = position
			local facing = info.Facing or Vector3.zAxis
			bee:PivotTo(CFrame.lookAt(position, position + facing))

			if carrying ~= info.CargoShown then
				info.CargoShown = carrying
				for _, part in info.Cargo do
					part.Transparency = if carrying then 0 else 1
				end
			end
		end
	end
end

local function moveWorkers(now: number)
	if landedJars > 0 then
		honeyPop(landedJars)
		landedJars = 0
	end
	local serverNow = workspace:GetServerTimeNow()
	-- each hive's workers share its lanes and its circle, so they are moved hive by hive
	local groups: { [Instance]: { Model } } = {}
	for bee in workerBees do
		local folder = bee.Parent
		if folder then
			local list = groups[folder]
			if not list then
				list = {}
				groups[folder] = list
			end
			table.insert(list, bee)
		end
	end
	local mine = myPlot()
	local showOthers = State.ShowOtherBees()
	for folder, bees in groups do
		local hidden = hideIt(folder, mine, showOthers)
		for _, bee in bees do
			setHidden(bee, hidden)
		end
		if not hidden then
			moveWorkerGroup(bees, now, serverNow)
		end
	end
end

-- 5c. HOLDING THE JARS UP ---------------------------------------------------------------
-- Anyone carrying a stack of jars (the server puts a "HoneyStack" in their character)
-- holds both arms straight up under it. This sets every arm joint a moment before each
-- physics step, after the walking animation has had its turn, so the whole arm stays
-- stiff and straight instead of swinging. The stack is fixed to the chest (where the
-- arms hang from), so arms and jars move as one.

local ARM_RAISE = math.rad(180) -- straight up
local ARM_LEAN = math.rad(20) -- how far each arm leans in, so the hands sit under the bottom jar
local STRAIGHT = CFrame.new()
local ARMS_UP = {
	-- R15 avatars: { the body part, the joint inside it, how to hold that joint }
	{ "RightUpperArm", "RightShoulder", CFrame.Angles(ARM_RAISE, 0, -ARM_LEAN) },
	{ "RightLowerArm", "RightElbow", STRAIGHT },
	{ "RightHand", "RightWrist", STRAIGHT },
	{ "LeftUpperArm", "LeftShoulder", CFrame.Angles(ARM_RAISE, 0, ARM_LEAN) },
	{ "LeftLowerArm", "LeftElbow", STRAIGHT },
	{ "LeftHand", "LeftWrist", STRAIGHT },
	-- R6 avatars (the joints live in the torso)
	{ "Torso", "Right Shoulder", CFrame.Angles(0, 0, ARM_RAISE) },
	{ "Torso", "Left Shoulder", CFrame.Angles(0, 0, -ARM_RAISE) },
}

local function holdJarsUp()
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if character and character:FindFirstChild("HoneyStack") then
			for _, arm in ARMS_UP do
				local part = character:FindFirstChild(arm[1])
				local joint = part and part:FindFirstChild(arm[2])
				if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
					joint.Transform = arm[3]
				end
			end
		end
	end
end

-- 6. BOBBING QUEENS ------------------------------------------------------------------

local BOB_TAG = "BeeBob"
local bobbing: { [Model]: number } = {} -- bee -> its own timing offset, so they do not move in sync

local function addBee(instance: Instance)
	if instance:IsA("Model") then
		bobbing[instance] = math.random() * math.pi * 2
	end
end

local function removeBee(instance: Instance)
	bobbing[instance :: Model] = nil
end

-- 7. "GO HERE" ARROWS ---------------------------------------------------------------

local arrow: BillboardGui
local edgeArrow: Frame
local arrowHeight = 0
local ARROW_HIDE_DISTANCE = 12
-- how far out (from the middle towards the edge) the screen-edge arrow may go.
-- The bottom is shorter so it stays clear of the hint.
local EDGE_REACH_SIDE = 0.82
local EDGE_REACH_TOP = 0.78
local EDGE_REACH_BOTTOM = 0.6
-- On a phone the arrow stays nearer the middle: the left and right edges of the screen are
-- taken by the coin readout, the thumbstick, the Auto Roll switch and the jump button.
local EDGE_REACH_SIDE_TOUCH = 0.4
local edgeReachSide = EDGE_REACH_SIDE

local function findTarget(targetName: string?, standIndex: number?): (BasePart?, number)
	local plot = myPlot()
	if not plot then
		return nil, 0
	end
	if targetName == "Queen" then
		local queen = plot:FindFirstChild("Queen")
		local rollSpot = queen and queen:FindFirstChild("RollSpot")
		if rollSpot and rollSpot:IsA("BasePart") then
			return rollSpot, 12.5
		end
	elseif targetName == "Stand" then
		local queen = plot:FindFirstChild("Queen")
		local folder = queen and queen:FindFirstChild("Stands")
		local stand = folder and folder:FindFirstChild("Stand" .. (standIndex or 1))
		local buySpot = stand and stand:FindFirstChild("BuySpot")
		if buySpot and buySpot:IsA("BasePart") then
			return buySpot, 6.5
		end
	elseif targetName == "Upgrades" then
		local shop = plot:FindFirstChild("Upgrades")
		local shopSpot = shop and shop:FindFirstChild("UpgradeSpot")
		if shopSpot and shopSpot:IsA("BasePart") then
			return shopSpot, 21.5
		end
	elseif targetName == "Hive" then
		local anchor = plot:FindFirstChild("HiveAnchor")
		local hive = plot:FindFirstChild("Hive")
		if anchor and anchor:IsA("BasePart") then
			local height = hive and hive:GetAttribute("Height")
			return anchor, (if typeof(height) == "number" then height else 5) + 7.5
		end
	elseif targetName == "Collect" then
		local station = plot:FindFirstChild("CollectStation")
		local tablePart = station and station:FindFirstChild("Table")
		if tablePart and tablePart:IsA("BasePart") then
			return tablePart, 21.5
		end
	elseif targetName == "Market" then
		local market = plot:FindFirstChild("Market")
		local counter = market and market:FindFirstChild("Counter")
		if counter and counter:IsA("BasePart") then
			return counter, 12.5
		end
	end
	return nil, 0
end

-- the place the arrow should point at (its parts may not have reached this device yet)
local wantedTarget: string? = nil
local lastArrowLook = 0

local function updateArrowTarget()
	local _, targetName, standIndex = State.Objective()
	wantedTarget = targetName
	local target, height = findTarget(targetName, standIndex)
	arrow.Adornee = target
	arrowHeight = height
end

local function buildArrows()
	edgeReachSide = if Kit.IsTouch() then EDGE_REACH_SIDE_TOUCH else EDGE_REACH_SIDE
	arrow = Kit.Create("BillboardGui", {
		Name = "GoHereArrow",
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(70, 70),
		LightInfluence = 0,
		ResetOnSpawn = false,
		Enabled = false,
		Parent = playerGui,
	})
	Kit.Label({
		Parent = arrow,
		Text = "\u{25BC}", -- a downward triangle
		TextSize = 64,
		Color = Kit.Colors.Honey,
		Stroke = 4,
	})

	local edgeGui = Kit.Create("ScreenGui", {
		Name = "BeeEmpireEdgeArrow",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		Parent = playerGui,
	})
	edgeArrow = Kit.Create("Frame", {
		Name = "EdgeArrow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(64, 64),
		Visible = false,
		Parent = edgeGui,
	})
	Kit.AutoScale(edgeArrow)
	local circle = Kit.Create("Frame", {
		Name = "Circle",
		BackgroundColor3 = Kit.Colors.Outline,
		BackgroundTransparency = 0.15,
		Size = UDim2.fromScale(1, 1),
		Parent = edgeArrow,
	})
	Kit.Corner(circle, 32)
	Kit.Stroke(circle, 3, Kit.Colors.Honey)
	-- a real arrow shape (shaft + head), so it is clear which way it points. It points UP when not rotated.
	Kit.Label({
		Parent = edgeArrow,
		Name = "Pointer",
		Text = "\u{2191}", -- an upward arrow, turned to face the target
		TextSize = 46,
		Color = Kit.Colors.Honey,
		Stroke = 2,
	})
end

local function updateEdgeArrow(target: BasePart?, now: number)
	local camera = workspace.CurrentCamera
	if not target or not camera then
		edgeArrow.Visible = false
		return
	end
	-- if the place itself is on screen, the floating arrow above it is enough
	local point, onScreen = camera:WorldToScreenPoint(target.Position)
	if onScreen then
		edgeArrow.Visible = false
		return
	end

	local screen = edgeArrow.Parent and (edgeArrow.Parent :: ScreenGui).AbsoluteSize or camera.ViewportSize
	local center = screen / 2
	local direction = Vector2.new(point.X, point.Y) - center
	if point.Z < 0 then
		direction = -direction -- the target is behind the camera
	end
	if direction.Magnitude < 1 then
		direction = Vector2.new(0, 1)
	end
	direction = direction.Unit

	-- slide the arrow out to the edge of the screen, in the target's direction
	local halfX = center.X * edgeReachSide
	local halfY = center.Y * (if direction.Y > 0 then EDGE_REACH_BOTTOM else EDGE_REACH_TOP)
	local stretch = math.min(halfX / math.max(math.abs(direction.X), 1e-3), halfY / math.max(math.abs(direction.Y), 1e-3))
	local spot = center + direction * stretch
	local wobble = math.sin(now * 6) * 6
	spot += direction * wobble

	edgeArrow.Position = UDim2.fromOffset(spot.X, spot.Y)
	edgeArrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
	edgeArrow.Visible = true
end

-- 8. PRICE PILLS ON YOUR UPGRADE BOARD -------------------------------------------------

local PILL_CAN_AFFORD = Color3.fromRGB(60, 225, 70)
local PILL_TOO_DEAR = Color3.fromRGB(205, 205, 228)

local function refreshBoardPills()
	local plot = myPlot()
	local shop = plot and plot:FindFirstChild("Upgrades")
	local board = shop and shop:FindFirstChild("Board")
	local face = board and board:FindFirstChild("Face")
	if not face then
		return
	end
	for _, id in GameConfig.UpgradeOrder do
		local panel = face:FindFirstChild("Panel_" .. id)
		local pill = panel and panel:FindFirstChild("Price")
		if pill and pill:IsA("Frame") then
			pill.BackgroundColor3 = if State.CanAffordUpgrade(id) then PILL_CAN_AFFORD else PILL_TOO_DEAR
		end
	end
end

-- The price on the Auto Roll sign next to your Queen (the sign is gone once you have bought it).
local function refreshAutoSign()
	local plot = myPlot()
	local queen = plot and plot:FindFirstChild("Queen")
	local autoSign = queen and queen:FindFirstChild("AutoRoll")
	local sign = autoSign and autoSign:FindFirstChild("Sign")
	local face = sign and sign:FindFirstChild("Face")
	local pill = face and face:FindFirstChild("Price")
	if pill and pill:IsA("Frame") then
		pill.BackgroundColor3 = if State.Number("Coins") >= GameConfig.AutoRollPrice then PILL_CAN_AFFORD else PILL_TOO_DEAR
	end
end

-- 10. THE FLOWER GARDEN SWAYS -----------------------------------------------------------
-- The map tool tags every garden flower (and the giant sunflower, and the reeds) and says
-- where its foot is and how tall it is. Each one leans a little to and fro from its foot.
-- A wave runs across the garden, so neighbours move together like in a breeze. Tall flowers
-- lean less than small ones, so their heads never swing far. Only this player's own screen
-- moves them: nothing about the game changes, and bees still find the same spots.

local SWAY_TAG = "GardenSway"
local SWAY_RANGE = 190 -- flowers further than this from the camera stand still (nobody would see them move)

type Sway = {
	Foot: CFrame,
	Parts: { BasePart },
	Places: { CFrame }, -- where each part sits, measured from the foot
	Known: { [BasePart]: CFrame }, -- the same, remembered per part
	Changed: boolean, -- true when parts have arrived or left since the lists were made
	Wave: number, -- where in the wave this flower is
	Speed: number,
	Lean: number, -- how far it leans, in radians
	Links: { RBXScriptConnection },
}
local swaying: { [Model]: Sway } = {}
local swayParts: { BasePart } = {}
local swayFrames: { CFrame } = {}

-- Lists a flower's parts. (Far-away parts of the map are sent to a device bit by bit, so a
-- flower's parts can arrive after the flower itself: a part is measured when it first shows
-- up, while it still stands where the map tool put it.)
local function listSwayParts(model: Model, sway: Sway)
	table.clear(sway.Parts)
	table.clear(sway.Places)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local place = sway.Known[part]
			if not place then
				place = sway.Foot:ToObjectSpace(part.CFrame)
				sway.Known[part] = place
			end
			table.insert(sway.Parts, part)
			table.insert(sway.Places, place)
		end
	end
	for part in sway.Known do
		if not part:IsDescendantOf(model) then
			sway.Known[part] = nil
		end
	end
	sway.Changed = false
end

local function addSway(instance: Instance)
	if not instance:IsA("Model") or swaying[instance] then
		return
	end
	local foot = instance:GetAttribute("Foot")
	if typeof(foot) ~= "CFrame" then
		return
	end
	local tallValue = instance:GetAttribute("Tall")
	local tall = if typeof(tallValue) == "number" and tallValue > 0 then tallValue else 6
	local sway: Sway = {
		Foot = foot,
		Parts = {},
		Places = {},
		Known = {},
		Changed = true,
		Wave = (foot.X * 0.11 + foot.Z * 0.07) % (math.pi * 2),
		Speed = math.clamp(2.1 - tall * 0.045, 0.55, 1.9),
		Lean = math.rad(math.clamp(15 / tall, 0.7, 4)),
		Links = {},
	}
	local function changed()
		sway.Changed = true
	end
	table.insert(sway.Links, instance.DescendantAdded:Connect(changed))
	table.insert(sway.Links, instance.DescendantRemoving:Connect(changed))
	swaying[instance] = sway
end

local function removeSway(instance: Instance)
	local sway = swaying[instance :: Model]
	if sway then
		for _, link in sway.Links do
			link:Disconnect()
		end
		swaying[instance :: Model] = nil
	end
end

local function moveSway(now: number)
	local camera = workspace.CurrentCamera
	if not camera or next(swaying) == nil then
		return
	end
	local eye = camera.CFrame.Position
	table.clear(swayParts)
	table.clear(swayFrames)
	for model, sway in swaying do
		if (sway.Foot.Position - eye).Magnitude < SWAY_RANGE then
			if sway.Changed then
				listSwayParts(model, sway)
			end
			local wave = now * sway.Speed + sway.Wave
			local bent = sway.Foot * CFrame.Angles(math.sin(wave) * sway.Lean, 0, math.sin(wave * 0.73 + 1.3) * sway.Lean * 0.7)
			for index, part in sway.Parts do
				table.insert(swayParts, part)
				table.insert(swayFrames, bent * sway.Places[index])
			end
		end
	end
	if #swayParts > 0 then
		-- (one call moves them all, which is much lighter than moving each part by itself)
		workspace:BulkMoveTo(swayParts, swayFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- 11. THE HALLOWEEN EGG (a limited-time event) ---------------------------------------------
-- The server puts the egg's corner into the world while the event is on (HalloweenService).
-- This part makes it live on THIS player's screen: the egg breathes, the bats and ghosts
-- drift about, the board shows this player's own chances and the time left, and the egg
-- shakes when this player feeds it.

local HALLOWEEN_TAG = "HalloweenCorner"
local HALLOWEEN_EGG = GameConfig.HalloweenEgg
local HALLOWEEN_SHOWN = Color3.new(1, 1, 1)
local HALLOWEEN_HIDDEN = Color3.new(0, 0, 0) -- a secret bee nobody has yet is a black shape

type HalloweenCorner = {
	Model: Model,
	EggModel: Model?,
	BasePivot: CFrame?,
	Floaters: { BasePart },
	Board: Instance?,
	ShakeFrom: number,
	ShakeUntil: number,
}
local halloween: HalloweenCorner? = nil

-- "20 d 5 h", "5 h 12 min", "12 min", "40 s"
local function halloweenWait(seconds: number): string
	local whole = math.ceil(seconds)
	if whole >= 86400 then
		return string.format("%d d %d h", whole // 86400, (whole % 86400) // 3600)
	elseif whole >= 3600 then
		return string.format("%d h %02d min", whole // 3600, (whole % 3600) // 60)
	elseif whole >= 60 then
		return math.ceil(whole / 60) .. " min"
	end
	return whole .. " s"
end

-- Writes this player's own chances and the countdown on the board.
local function fillHalloweenBoard()
	local corner = halloween
	local board = corner and corner.Board
	if not board then
		return
	end
	local luck = if HALLOWEEN_EGG.LuckCounts then State.RollLuck() else 1
	local chances = GameConfig.EggChances(HALLOWEEN_EGG, luck)
	for _, entry in HALLOWEEN_EGG.Bees do
		local row = board:FindFirstChild("Row_" .. entry.Bee)
		local bee = GameConfig.Bees[entry.Bee]
		local nameLabel = row and row:FindFirstChild("BeeName")
		local picture = row and row:FindFirstChild("Picture")
		local chance = row and row:FindFirstChild("Chance")
		if bee and nameLabel and nameLabel:IsA("TextLabel") and picture and picture:IsA("ImageLabel") and chance and chance:IsA("TextLabel") then
			local hide = bee.Secret == true and not State.OwnsBee(entry.Bee)
			nameLabel.Text = if hide then "???" else bee.BeeName
			picture.ImageColor3 = if hide then HALLOWEEN_HIDDEN else HALLOWEEN_SHOWN
			chance.Text = NumberFormat.Percent(chances[entry.Bee] or 0)
		end
	end
	local luckLabel = board:FindFirstChild("Luck")
	if luckLabel and luckLabel:IsA("TextLabel") then
		luckLabel.Text = if HALLOWEEN_EGG.LuckCounts then string.format("Your luck: x%g", luck) else ""
	end
	local countdown = board:FindFirstChild("Countdown")
	if countdown and countdown:IsA("TextLabel") then
		local left = State.EggSecondsLeft()
		countdown.Text = if left > 0 then "Leaves in " .. halloweenWait(left) else ""
	end
end

local function addHalloween(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local eggModel = instance:FindFirstChild("EggModel")
	local basePivot = eggModel and eggModel:GetAttribute("BasePivot")
	local corner: HalloweenCorner = {
		Model = instance,
		EggModel = if eggModel and eggModel:IsA("Model") then eggModel else nil,
		BasePivot = if typeof(basePivot) == "CFrame" then basePivot else nil,
		Floaters = {},
		Board = nil,
		ShakeFrom = 0,
		ShakeUntil = 0,
	}
	local floaters = instance:FindFirstChild("Floaters")
	if floaters then
		for _, part in floaters:GetChildren() do
			if part:IsA("BasePart") then
				table.insert(corner.Floaters, part)
			end
		end
	end
	local screen = instance:FindFirstChild("SignScreen")
	corner.Board = screen and screen:FindFirstChild("Board")
	halloween = corner
	fillHalloweenBoard()
end

local function removeHalloween(instance: Instance)
	if halloween and halloween.Model == instance then
		halloween = nil
	end
end

local function moveHalloween(now: number)
	local corner = halloween
	if not corner then
		return
	end
	for _, part in corner.Floaters do
		local base = part:GetAttribute("Base")
		local phase = part:GetAttribute("Phase")
		if typeof(base) == "CFrame" then
			local offset = if typeof(phase) == "number" then phase else 0
			if part.Name == "Bat" then
				-- a small circle, bobbing, with a flutter
				local angle = now * 1.1 + offset
				part.CFrame = base
					* CFrame.new(math.cos(angle) * 1.6, math.sin(now * 2.3 + offset) * 0.5, math.sin(angle) * 1.6)
					* CFrame.Angles(0, 0, math.sin(now * 9 + offset) * 0.18)
			else
				-- a ghost: floats up and down and looks about
				part.CFrame = base
					* CFrame.new(0, math.sin(now * 1.5 + offset) * 0.6, 0)
					* CFrame.Angles(0, math.sin(now * 0.8 + offset) * 0.35, math.sin(now * 1.2 + offset) * 0.08)
			end
		end
	end
	local eggModel, basePivot = corner.EggModel, corner.BasePivot
	if eggModel and basePivot and eggModel.PrimaryPart then
		if now < corner.ShakeUntil then
			-- being fed: it rocks harder and harder until the bee pops out
			local share = math.clamp((now - corner.ShakeFrom) / math.max(0.1, corner.ShakeUntil - corner.ShakeFrom), 0, 1)
			local strength = 0.05 + 0.2 * share
			eggModel:PivotTo(
				basePivot
					* CFrame.new(0, math.abs(math.sin(now * 14)) * 0.3 * share, 0)
					* CFrame.Angles(math.sin(now * 31) * strength * 0.6, 0, math.sin(now * 37) * strength)
			)
		else
			-- waiting: it breathes
			eggModel:PivotTo(basePivot * CFrame.new(0, 0.14 + math.sin(now * 1.6) * 0.12, 0) * CFrame.Angles(0, 0, math.sin(now * 1.1) * 0.03))
		end
	end
end

-- This player fed the egg: it shakes for `seconds`, then bursts into sparkles.
-- (ClientMain shows the new bee's card at that same moment.)
function WorldFX.PlayEggHatch(seconds: number)
	local corner = halloween
	if not corner then
		return
	end
	local now = os.clock()
	corner.ShakeFrom = now
	corner.ShakeUntil = now + seconds
	-- the shakes climb, and a whoosh rises into the hatch
	Kit.PlaySound("Shake")
	task.delay(seconds * 0.35, Kit.PlaySound, "Shake", 1.12)
	task.delay(seconds * 0.7, Kit.PlaySound, "Shake", 1.25)
	if seconds > GameConfig.RiseLead then
		task.delay(seconds - GameConfig.RiseLead, Kit.PlaySound, "Rise")
	end
	task.delay(seconds, function()
		local eggModel = corner.EggModel
		local shell = eggModel and eggModel.PrimaryPart
		if shell and shell:IsDescendantOf(workspace) then
			puff(shell, Color3.fromRGB(255, 150, 30), 40)
			puff(shell, Color3.fromRGB(170, 90, 255), 30)
		end
	end)
end

-- 12. BEES BUZZING AT THE HIVES ----------------------------------------------------------------
-- Every hive that belongs to a player hums quietly. It is only heard standing near it
-- (GameConfig.BuzzNear and BuzzFar).
-- The sound sits halfway up the hive, and it goes when the hive goes.

local hiveBuzz: { [Instance]: Attachment } = {}

local function refreshHiveBuzz()
	for _, plot in plotsFolder:GetChildren() do
		local hive = plot:FindFirstChild("Hive")
		local anchor = plot:FindFirstChild("HiveAnchor")
		local spot = hiveBuzz[plot]
		local owned = (plot:GetAttribute("OwnerUserId") or 0) ~= 0 -- (an empty home area's hive is quiet)
		if owned and hive and anchor and anchor:IsA("BasePart") then
			if not spot or spot.Parent ~= anchor then
				if spot then
					spot:Destroy()
				end
				spot = Instance.new("Attachment")
				spot.Name = "BuzzSpot"
				spot.Parent = anchor
				Kit.LoopSound("Buzz", spot, GameConfig.BuzzNear, GameConfig.BuzzFar)
				hiveBuzz[plot] = spot
			end
			-- (a hive grows taller when it is upgraded)
			local height = hive:GetAttribute("Height")
			local spotNow = spot :: Attachment
			spotNow.Position = Vector3.new(0, (if typeof(height) == "number" then height else 5) / 2, 0)
		elseif spot then
			spot:Destroy()
			hiveBuzz[plot] = nil
		end
	end
	for plot, spot in hiveBuzz do
		if not plot.Parent then
			spot:Destroy()
			hiveBuzz[plot] = nil
		end
	end
end

function WorldFX.Init(openHive: () -> (), openUpgrades: () -> ())
	for _, plot in plotsFolder:GetChildren() do
		watchPlot(plot)
	end
	plotsFolder.ChildAdded:Connect(watchPlot)

	ProximityPromptService.PromptShown:Connect(showPrompt)
	ProximityPromptService.PromptHidden:Connect(hidePrompt)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		bounceOnTrigger(prompt)
		local action = prompt:GetAttribute("Action")
		if action == "Hive" then
			openHive()
		elseif action == "Upgrades" then
			openUpgrades()
		end
	end)

	for _, instance in CollectionService:GetTagged(BOB_TAG) do
		addBee(instance)
	end
	CollectionService:GetInstanceAddedSignal(BOB_TAG):Connect(addBee)
	CollectionService:GetInstanceRemovedSignal(BOB_TAG):Connect(removeBee)

	for _, instance in CollectionService:GetTagged(FORAGER_TAG) do
		addForager(instance)
	end
	CollectionService:GetInstanceAddedSignal(FORAGER_TAG):Connect(addForager)
	CollectionService:GetInstanceRemovedSignal(FORAGER_TAG):Connect(removeForager)

	for _, instance in CollectionService:GetTagged(WORKER_TAG) do
		addWorker(instance)
	end
	CollectionService:GetInstanceAddedSignal(WORKER_TAG):Connect(addWorker)
	CollectionService:GetInstanceRemovedSignal(WORKER_TAG):Connect(removeWorker)

	for _, instance in CollectionService:GetTagged(STAND_TAG) do
		addStand(instance)
	end
	CollectionService:GetInstanceAddedSignal(STAND_TAG):Connect(addStand)
	CollectionService:GetInstanceRemovedSignal(STAND_TAG):Connect(removeStand)
	State.Changed:Connect(refreshStandPills)

	for _, instance in CollectionService:GetTagged(SWAY_TAG) do
		addSway(instance)
	end
	CollectionService:GetInstanceAddedSignal(SWAY_TAG):Connect(addSway)
	CollectionService:GetInstanceRemovedSignal(SWAY_TAG):Connect(removeSway)

	for _, instance in CollectionService:GetTagged(HALLOWEEN_TAG) do
		addHalloween(instance)
	end
	CollectionService:GetInstanceAddedSignal(HALLOWEEN_TAG):Connect(addHalloween)
	CollectionService:GetInstanceRemovedSignal(HALLOWEEN_TAG):Connect(removeHalloween)
	State.Changed:Connect(fillHalloweenBoard)

	buildArrows()
	State.Changed:Connect(updateArrowTarget)
	updateArrowTarget()
	State.Changed:Connect(refreshBoardPills)
	refreshBoardPills()
	State.Changed:Connect(refreshAutoSign)
	refreshAutoSign()

	RunService.PreSimulation:Connect(holdJarsUp)

	-- the Honey Market's price boards: their countdown ticks by itself
	task.spawn(function()
		local ticks = 0
		while true do
			updatePriceBoards()
			ticks += 1
			if ticks % 4 == 0 then
				fillHalloweenBoard() -- (its countdown, and luck that changes when a boost runs out)
				refreshHiveBuzz() -- (hives come and go with their owners)
			end
			task.wait(0.25)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()

		for bee, offset in bobbing do
			local basePivot = bee:GetAttribute("BasePivot")
			if typeof(basePivot) == "CFrame" and bee.PrimaryPart then
				local height = math.sin(now * 2.2 + offset) * 0.3
				local turn = math.sin(now * 0.9 + offset) * 0.25
				local tilt = math.sin(now * 1.7 + offset) * 0.08
				bee:PivotTo(basePivot * CFrame.new(0, height, 0) * CFrame.Angles(0, turn, tilt))
			end
		end

		moveForagers(now)
		moveWorkers(now)
		moveStands(now)
		moveRollingBees(now)
		moveSway(now)
		moveHalloween(now)

		-- Parts of a plot can reach this device late (or leave and come back), so keep looking
		-- for the place the arrow should point at until it is found.
		if wantedTarget and now - lastArrowLook > 0.5 then
			local adornee = arrow.Adornee
			if not adornee or not adornee:IsDescendantOf(workspace) then
				lastArrowLook = now
				updateArrowTarget()
			end
		end

		local target = arrow.Adornee :: BasePart?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hideAll = Kit.IsAnyPanelOpen()
		if target and root and not hideAll then
			local close = (root.Position - target.Position).Magnitude < ARROW_HIDE_DISTANCE
			arrow.Enabled = not close
			arrow.StudsOffsetWorldSpace = Vector3.new(0, arrowHeight + math.abs(math.sin(now * 3)) * 1.5, 0)
			updateEdgeArrow(if close then nil else target, now)
		else
			arrow.Enabled = false
			updateEdgeArrow(nil, now)
		end
	end)
end

return WorldFX
