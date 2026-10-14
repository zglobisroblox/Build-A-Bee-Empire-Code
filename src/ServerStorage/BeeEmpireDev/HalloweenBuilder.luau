--[[
	HalloweenBuilder - builds the Halloween Egg's corner (a tool for Roblox Studio's command
	bar; the game itself never runs it).

	require(game.ServerStorage.BeeEmpireDev.HalloweenBuilder).Build()

	It makes ServerStorage.BeeEmpireEvents.HalloweenCorner from the Blender pieces in
	BeeEmpireDev.PropMeshes (HwEgg, Pumpkin, Gravestone...). HalloweenService puts a copy of
	that model into the world while the event is on. Run Build() again after changing
	anything below.

	Where the pieces stand comes from blender/halloween.py (its LAYOUT list, copied here).
	The corner's own middle is the egg; its front (-z) is turned towards the Flower Garden.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- (Studio remembers a script the first time it is used, and keeps using that old copy until it
-- is restarted. So this tool reads fresh copies of the game's shared scripts.)
local fresh = Instance.new("Folder")
for _, name in { "GameConfig", "NumberFormat", "Studs", "UIImages" } do
	ReplicatedStorage.BeeEmpire[name]:Clone().Parent = fresh
end
local GameConfig = require(fresh.GameConfig)
local NumberFormat = require(fresh.NumberFormat)
local Studs = require(fresh.Studs)
local UIImages = require(fresh.UIImages)

local Builder = {}

local MIDDLE = Vector3.new(40, 0, 71) -- where the egg stands (next to the Flower Garden, between two paths)
local FACES = Vector3.new(0, 0, 0) -- the corner's front looks at this point (the middle of the garden)
local GROUND_RADIUS = 17.5
local PEDESTAL_TOP = 1.46
local FONT = Enum.Font.FredokaOne
local INK = Color3.fromRGB(20, 16, 26)
local ORANGE = Color3.fromRGB(255, 150, 30)

-- name, x, y, z, turn (degrees), size
local LAYOUT = {
	{ "HwPedestal", 0, 0, 0, 0, 1 }, { "HwPedestalGems", 0, 0, 0, 0, 1 },
	{ "HwEgg", 0, 1.46, 0, 0, 1 }, { "HwEggGlow", 0, 1.46, 0, 0, 1 },
	{ "HwSign", -11, 0, 3, -31, 1 },
	{ "SpookyTree", 10.5, 0, 6.5, 20, 1 }, { "SpookyTree", -13.5, 0, 10.5, 200, 0.75 },
	{ "Gravestone", 6.5, 0, -6, 12, 1 }, { "Gravestone", 11.8, 0, -1, -24, 0.85 }, { "Gravestone", -5, 0, 9.5, 8, 0.9 },
	{ "Pumpkin", -4.6, 0, -6.2, -12, 1 }, { "PumpkinFace", -4.6, 0, -6.2, -12, 1 },
	{ "Pumpkin", 3.6, 0, -9.2, 14, 0.7 }, { "PumpkinFace", 3.6, 0, -9.2, 14, 0.7 },
	{ "Pumpkin", -13, 0, -4.5, -30, 1.3 }, { "PumpkinFace", -13, 0, -4.5, -30, 1.3 },
	{ "Pumpkin", 8, 0, 2, 0, 0.6 },
	{ "Pumpkin", 13.5, 0, 10, 40, 0.9 }, { "PumpkinFace", 13.5, 0, 10, 40, 0.9 },
	{ "Pumpkin", -8.5, 0, 12.5, 0, 0.7 },
	{ "Cauldron", 9, 0, -9.5, 0, 1 }, { "CauldronGoo", 9, 0, -9.5, 0, 1 },
	{ "BatProp", 9, 10.5, 3, 20, 1.2 }, { "BatProp", -3.5, 9.5, 7, -30, 1 }, { "BatProp", 4, 12.5, 9, 10, 1.4 },
	{ "BatProp", -11.5, 8, 3.5, 40, 1 }, { "BatProp", 0.5, 10.8, -3, 0, 0.9 },
	{ "Ghostie", 12.2, 4.6, -5.5, 30, 1 }, { "Ghostie", 6, 5.4, 6, 25, 1.2 },
}

-- white pieces that glow, and the colour they glow in
local GLOW = {
	HwEggGlow = Color3.fromRGB(255, 170, 40),
	HwPedestalGems = Color3.fromRGB(255, 120, 20),
	PumpkinFace = Color3.fromRGB(255, 170, 40),
	CauldronGoo = Color3.fromRGB(120, 255, 80),
}
-- How far each one's light reaches. (Kept few and soft: the game adds bloom while playing, and
-- a bright light next to an orange pumpkin washes it out to yellow.)
local LIGHT = { HwEggGlow = 14, CauldronGoo = 8 }
local STUDDED = { HwPedestal = true, Pumpkin = true, Gravestone = true, SpookyTree = true, Cauldron = true, HwSign = true } -- the toy-brick stud pattern
local SOLID = { HwPedestal = true, HwEgg = true, Pumpkin = true, Gravestone = true, SpookyTree = true, Cauldron = true, HwSign = true } -- can be bumped into
local FLOATS = { BatProp = "Bat", Ghostie = "Ghost" } -- hang in the air (each player's own screen moves them)

local function prop(templates: Instance, name: string, cframe: CFrame, scale: number, parent: Instance): MeshPart
	local template = templates:FindFirstChild(name)
	assert(template and template:IsA("MeshPart"), "PropMeshes has no piece called " .. name)
	local part = template:Clone()
	local place = template:GetAttribute("Place") :: CFrame
	part.Size = template.Size * scale
	part.CFrame = cframe * CFrame.new(place.Position * scale) * place.Rotation
	part.Anchored = true
	part.CanCollide = SOLID[name] == true
	part.CanTouch = false
	part.CanQuery = SOLID[name] == true
	part.CastShadow = not FLOATS[name] and not GLOW[name]
	part.Parent = parent
	return part
end

local function label(parent: Instance, name: string, text: string, position: UDim2, size: UDim2, color: Color3, xAlign: Enum.TextXAlignment?): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Font = FONT
	item.Text = text
	item.TextScaled = true
	item.TextColor3 = color
	item.TextXAlignment = xAlign or Enum.TextXAlignment.Center
	item.Position = position
	item.Size = size
	local edge = Instance.new("UIStroke")
	edge.Color = INK
	edge.Thickness = 4
	edge.Parent = item
	item.Parent = parent
	return item
end

function Builder.Build(): Model
	local templates = ServerStorage.BeeEmpireDev.PropMeshes
	local events = ServerStorage:FindFirstChild("BeeEmpireEvents")
	if not events then
		events = Instance.new("Folder")
		events.Name = "BeeEmpireEvents"
		events.Parent = ServerStorage
	end
	local old = events:FindFirstChild("HalloweenCorner")
	if old then
		old:Destroy()
	end

	local egg = GameConfig.HalloweenEgg
	local base = CFrame.lookAt(MIDDLE, FACES)
	local model = Instance.new("Model")
	model.Name = "HalloweenCorner"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- reaches a player's device all at once
	model:SetAttribute("Middle", MIDDLE)
	model:SetAttribute("Radius", GROUND_RADIUS)

	-- the dark patch of ground
	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Shape = Enum.PartType.Cylinder
	ground.Size = Vector3.new(0.3, GROUND_RADIUS * 2, GROUND_RADIUS * 2)
	ground.CFrame = CFrame.new(MIDDLE + Vector3.new(0, 0.17, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ground.Color = Color3.fromRGB(86, 62, 120)
	ground.Material = Enum.Material.SmoothPlastic
	ground.Anchored = true
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.BottomSurface = Enum.SurfaceType.Smooth
	ground.Parent = model
	Studs.Face(ground, Enum.NormalId.Right) -- (the round top: the cylinder lies on its side)

	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = model
	local floaters = Instance.new("Folder")
	floaters.Name = "Floaters"
	floaters.Parent = model
	local eggModel = Instance.new("Model")
	eggModel.Name = "EggModel"
	eggModel.Parent = model

	local signPlace: CFrame? = nil
	local eggPart: MeshPart? = nil
	for index, entry in LAYOUT do
		local name, x, y, z, turn, scale = entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
		local cframe = base * CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(turn), 0)
		local isEgg = name == "HwEgg" or name == "HwEggGlow"
		local parent = if isEgg then eggModel elseif FLOATS[name] then floaters else scenery
		local part = prop(templates, name, cframe, scale, parent)
		if GLOW[name] then
			part.Material = Enum.Material.Neon
			part.Color = GLOW[name]
			if LIGHT[name] then
				local light = Instance.new("PointLight")
				light.Color = GLOW[name]
				light.Range = LIGHT[name] * scale
				light.Brightness = 0.35
				light.Parent = part
			end
		end
		if STUDDED[name] then
			part:SetAttribute("Studs", true)
			for _, face in Enum.NormalId:GetEnumItems() do
				Studs.Face(part, face)
			end
		end
		if FLOATS[name] then
			part.Name = FLOATS[name]
			part:SetAttribute("Base", part.CFrame) -- where it hangs; the screen moves it round this
			part:SetAttribute("Phase", index * 1.7) -- so no two move in step
		elseif name == "HwEgg" then
			part.Name = "Egg"
			eggPart = part
		elseif name == "HwEggGlow" then
			part.Name = "EggGlow"
		elseif name == "HwSign" then
			signPlace = cframe
		end
	end
	assert(eggPart and signPlace, "the layout has no egg or no sign")
	eggModel.PrimaryPart = eggPart
	-- The egg is moved, and rocked, by the point it STANDS on (the top of the pedestal). A model
	-- with a main part is moved by that part's own handle, so the handle is put down there.
	-- (Without this the egg's middle was put on the pedestal, and it sank in up to its face.)
	local standsOn = base * CFrame.new(0, PEDESTAL_TOP, 0)
	eggPart.PivotOffset = eggPart.CFrame:ToObjectSpace(standsOn)
	eggModel:SetAttribute("BasePivot", standsOn)

	-- a few sparks rising out of the cauldron
	for _, part in scenery:GetChildren() do
		if part.Name == "CauldronGoo" then
			local sparks = Instance.new("ParticleEmitter")
			sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparks.Color = ColorSequence.new(GLOW.CauldronGoo)
			sparks.LightEmission = 1
			sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
			sparks.Lifetime = NumberRange.new(1.2, 2)
			sparks.Speed = NumberRange.new(1.5, 3)
			sparks.SpreadAngle = Vector2.new(20, 20)
			sparks.EmissionDirection = Enum.NormalId.Top
			sparks.Rate = 5
			sparks.Parent = part
		end
	end

	-- where E is pressed: in front of the egg's face
	local spot = Instance.new("Part")
	spot.Name = "EggSpot"
	spot.Size = Vector3.new(1, 1, 1)
	spot.CFrame = base * CFrame.new(0, 3.6, -3.4)
	spot.Transparency = 1
	spot.Anchored = true
	spot.CanCollide = false
	spot.CanTouch = false
	spot.CanQuery = false
	spot.Parent = model
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.Style = Enum.ProximityPromptStyle.Custom -- (drawn by WorldFX, like the game's other prompts)
	prompt.ActionText = "Give " .. NumberFormat.Short(egg.JarCost) .. " Jars"
	prompt.ObjectText = egg.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 13
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt:SetAttribute("Action", "HalloweenEgg")
	prompt.Parent = spot

	-- the words floating over the egg, seen from far away
	local beacon = Instance.new("BillboardGui")
	beacon.Name = "Beacon"
	beacon.Size = UDim2.fromScale(12, 3.2)
	beacon.StudsOffsetWorldSpace = Vector3.new(0, 11.5, 3.4)
	beacon.MaxDistance = 260
	beacon.LightInfluence = 0
	beacon.Parent = spot
	label(beacon, "Title", string.upper(egg.Name), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.62), ORANGE)
	label(beacon, "Sub", "Limited time!", UDim2.fromScale(0, 0.62), UDim2.fromScale(1, 0.38), Color3.fromRGB(255, 255, 255))

	-- the board: what is inside the egg. (Every player's own screen fills in THEIR chances and
	-- the countdown: see WorldFX. What is written here is what shows before that.)
	local screen = Instance.new("Part")
	screen.Name = "SignScreen"
	screen.Size = Vector3.new(9.2, 5.6, 0.1)
	screen.CFrame = signPlace * CFrame.new(0, 5.2, -0.31)
	screen.Color = Color3.fromRGB(40, 26, 62)
	screen.Material = Enum.Material.SmoothPlastic
	screen.Anchored = true
	screen.CanCollide = false
	screen.CanTouch = false
	screen.CanQuery = false
	screen.CastShadow = false
	screen:SetAttribute("NoStuds", true)
	screen.Parent = model
	local board = Instance.new("SurfaceGui")
	board.Name = "Board"
	board.Face = Enum.NormalId.Front
	board.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	board.PixelsPerStud = 100
	board.LightInfluence = 0
	board.Parent = screen
	label(board, "Title", string.upper(egg.Name), UDim2.fromOffset(20, 4), UDim2.fromOffset(880, 72), ORANGE)
	label(board, "Sub", "Bring " .. NumberFormat.Short(egg.JarCost) .. " jars to the egg!", UDim2.fromOffset(20, 76), UDim2.fromOffset(880, 58), Color3.fromRGB(255, 255, 255))
	local chances = GameConfig.EggChances(egg, 1)
	for index, entry in egg.Bees do
		local bee = GameConfig.Bees[entry.Bee]
		local row = Instance.new("Frame")
		row.Name = "Row_" .. entry.Bee
		row.BackgroundColor3 = Color3.fromRGB(24, 16, 40)
		row.BackgroundTransparency = 0.2
		row.Position = UDim2.fromOffset(24, 138 + (index - 1) * 114)
		row.Size = UDim2.fromOffset(872, 104)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 18)
		corner.Parent = row
		row.Parent = board
		local picture = Instance.new("ImageLabel")
		picture.Name = "Picture"
		picture.BackgroundTransparency = 1
		picture.Image = UIImages.Bee(entry.Bee)
		picture.ImageColor3 = if bee.Secret then Color3.new(0, 0, 0) else Color3.new(1, 1, 1) -- a secret bee is a black shape
		picture.Position = UDim2.fromOffset(10, 2)
		picture.Size = UDim2.fromOffset(100, 100)
		picture.Parent = row
		label(row, "BeeName", if bee.Secret then "???" else bee.BeeName, UDim2.fromOffset(124, 16), UDim2.fromOffset(430, 72), bee.RarityColor, Enum.TextXAlignment.Left)
		label(row, "Chance", NumberFormat.Percent(chances[entry.Bee]), UDim2.fromOffset(560, 16), UDim2.fromOffset(296, 72), Color3.fromRGB(255, 255, 255), Enum.TextXAlignment.Right)
	end
	label(board, "Luck", "", UDim2.fromOffset(28, 484), UDim2.fromOffset(380, 60), Color3.fromRGB(120, 255, 40), Enum.TextXAlignment.Left)
	label(board, "Countdown", "", UDim2.fromOffset(420, 484), UDim2.fromOffset(472, 60), Color3.fromRGB(255, 236, 60), Enum.TextXAlignment.Right)

	CollectionService:AddTag(model, "HalloweenCorner")
	model.Parent = events
	return model
end

return Builder
